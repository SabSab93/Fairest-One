// ESP32-C6, Arduino ESP32 core 3.3.12; MFRC522 1.4.12; ArduinoJson 7.4.2.
// BLE only: no WiFi/HTTP library and no Supabase credentials.
#include <Arduino.h>
#include <SPI.h>
#include <MFRC522.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <ArduinoJson.h>
#include <mbedtls/md.h>
#include "config.h"

#define LED_RED 5
#define LED_GREEN 6
#define LED_BLUE 4
#define BUZZER_PIN 20
#define SS_PIN 10
#define RST_PIN 3
#define SCK_PIN 19
#define MOSI_PIN 18
#define MISO_PIN 2

const char *SERVICE_UUID = "83de1000-7a28-4b54-9815-47c0ae451001";
const char *EVENTS_UUID = "83de1001-7a28-4b54-9815-47c0ae451001";
const char *COMMANDS_UUID = "83de1002-7a28-4b54-9815-47c0ae451001";
MFRC522 reader(SS_PIN, RST_PIN);
BLECharacteristic *events;
BLEServer *server;
QueueHandle_t commands;
volatile bool connected = false;
volatile bool disconnected = false;
String rx;
struct Command { char line[512]; };
enum Phase { IDLE, READING, WAIT_RESULT, COUNTDOWN, WAIT_SAVE };
Phase phase = IDLE;
String token, uid;
uint32_t phaseStarted = 0, tickStarted = 0, absentSince = 0;
int countdown = 3;
bool waitRemoval = false;

void rgb(bool red, bool green, bool blue) {
  digitalWrite(LED_RED, RGB_COMMON_ANODE ? !red : red);
  digitalWrite(LED_GREEN, RGB_COMMON_ANODE ? !green : green);
  digitalWrite(LED_BLUE, RGB_COMMON_ANODE ? !blue : blue);
}
void beep(int count) {
  for (int i = 0; i < count && connected; ++i) {
    if (BUZZER_ACTIVE) digitalWrite(BUZZER_PIN, HIGH);
    else tone(BUZZER_PIN, 2000);
    delay(90);
    if (BUZZER_ACTIVE) digitalWrite(BUZZER_PIN, LOW);
    else noTone(BUZZER_PIN);
    delay(100);
  }
}
String proof(const char *action) {
  String data = token + "|" + uid + "|" + action;
  unsigned char digest[32];
  const auto *info = mbedtls_md_info_from_type(MBEDTLS_MD_SHA256);
  mbedtls_md_hmac(info, (const unsigned char *)MIRROR_SIGNING_KEY,
    strlen(MIRROR_SIGNING_KEY), (const unsigned char *)data.c_str(), data.length(), digest);
  char hex[65];
  for (int i = 0; i < 32; ++i) snprintf(hex + i * 2, 3, "%02x", digest[i]);
  return String(hex);
}
void emit(JsonDocument &doc) {
  if (!connected) return;
  String line;
  serializeJson(doc, line);
  line += '\n';
  for (size_t i = 0; i < line.length() && connected; i += 20) {
    String part = line.substring(i, i + 20);
    events->setValue((uint8_t *)part.c_str(), part.length());
    events->notify();
    delay(15); // Conservative for iOS even with the minimum ATT MTU.
  }
}
void event(const char *type, const char *action = nullptr) {
  JsonDocument doc;
  doc["type"] = type;
  doc["token"] = token;
  if (action) { doc["uid"] = uid; doc["proof"] = proof(action); }
  emit(doc);
}
void reset() {
  phase = IDLE;
  token = "";
  uid = "";
  rgb(false, false, false);
  digitalWrite(BUZZER_PIN, LOW);
  if (!BUZZER_ACTIVE) noTone(BUZZER_PIN);
}
void error(const char *code) {
  Serial.printf("Operation stopped: %s\n", code);
  JsonDocument doc;
  doc["type"] = "error"; doc["token"] = token; doc["code"] = code;
  emit(doc);
  reset();
}
class ServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer *) override { connected = true; }
  void onDisconnect(BLEServer *) override {
    connected = false;
    disconnected = true;
    rx = "";
  }
};
class CommandCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *characteristic) override {
    auto value = characteristic->getValue();
    for (size_t i = 0; i < value.length(); ++i) {
      char c = value[i];
      if (c == '\n') {
        Command cmd = {};
        rx.toCharArray(cmd.line, sizeof(cmd.line));
        xQueueSend(commands, &cmd, 0);
        rx = "";
      } else {
        rx += c;
        if (rx.length() >= 511) { rx = ""; return; }
      }
    }
  }
};
bool validToken(const String &s) {
  if (s.length() != 64) return false;
  for (char c : s) if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f'))) return false;
  return true;
}
void handleCommand(const Command &cmd) {
  JsonDocument doc;
  if (deserializeJson(doc, cmd.line)) return;
  String type = doc["type"] | "";
  String incoming = doc["token"] | "";
  if (!validToken(incoming)) return;
  if (type == "scan" && phase == IDLE) {
    token = incoming;
    phase = READING; phaseStarted = millis();
    rgb(false, false, true);
    Serial.println("Scan armed: present card to RC522");
    return;
  }
  if (incoming != token) return;
  if (type == "cancel") { reset(); return; }
  if (type == "capture_saved" && phase == WAIT_SAVE) {
    Serial.println("Backend confirmed simulated capture"); reset(); return;
  }
  if (type != "card_result" || phase != WAIT_RESULT || !doc["recognized"].is<bool>()) return;
  if (!doc["recognized"].as<bool>()) {
    Serial.println("Rejected: no countdown or capture");
    rgb(true, false, false); beep(3); reset(); return;
  }
  rgb(false, true, false); beep(2);
  if (!(doc["capture"] | false)) { reset(); return; }
  if (!connected) { reset(); return; }
  phase = COUNTDOWN; phaseStarted = millis(); tickStarted = millis(); countdown = 3;
  Serial.println("Countdown: 3");
}
void checkRemoval() {
  if (!waitRemoval) return;
  byte atqa[2]; byte size = sizeof(atqa);
  auto status = reader.PICC_WakeupA(atqa, &size);
  bool present = status == MFRC522::STATUS_OK || status == MFRC522::STATUS_COLLISION;
  if (present) { absentSince = 0; reader.PICC_ReadCardSerial(); reader.PICC_HaltA(); reader.PCD_StopCrypto1(); }
  else if (absentSince == 0) absentSince = millis();
  else if (millis() - absentSince > 600) { waitRemoval = false; absentSince = 0; }
}
void setup() {
  Serial.begin(115200);
  pinMode(LED_RED, OUTPUT); pinMode(LED_GREEN, OUTPUT); pinMode(LED_BLUE, OUTPUT);
  pinMode(BUZZER_PIN, OUTPUT); reset();
  // Visual self-test: verify actual red, green, blue; change pin mapping if needed.
  rgb(true, false, false); Serial.println("RGB test: RED (GPIO5)"); delay(700);
  rgb(false, true, false); Serial.println("RGB test: GREEN (GPIO6)"); delay(700);
  rgb(false, false, true); Serial.println("RGB test: BLUE (GPIO4)"); delay(700);
  reset();
  if (BLE_PAIRING_PASSKEY < 100000 || BLE_PAIRING_PASSKEY > 999999 || strlen(MIRROR_SIGNING_KEY) < 32 || String(MIRROR_SIGNING_KEY).startsWith("REPLACE_")) {
    Serial.println("Configure MIRROR_SIGNING_KEY and a six-digit BLE_PAIRING_PASSKEY in config.h first.");
    while (true) delay(1000);
  }
  SPI.begin(SCK_PIN, MISO_PIN, MOSI_PIN, SS_PIN);
  reader.PCD_Init(); reader.PCD_DumpVersionToSerial();
  commands = xQueueCreate(5, sizeof(Command));
  BLEDevice::init("Fairest-One-C6");
  auto *security = new BLESecurity();
  security->setPassKey(true, BLE_PAIRING_PASSKEY);
  security->setCapability(ESP_IO_CAP_OUT);
  security->setAuthenticationMode(true, true, true);
  security->setForceAuthentication(true);
  server = BLEDevice::createServer(); server->setCallbacks(new ServerCallbacks());
  auto *service = server->createService(SERVICE_UUID);
  events = service->createCharacteristic(EVENTS_UUID, BLECharacteristic::PROPERTY_NOTIFY);
  auto *subscription = new BLE2902();
#if defined(CONFIG_BLUEDROID_ENABLED)
  subscription->setAccessPermissions(ESP_GATT_PERM_READ_ENC_MITM | ESP_GATT_PERM_WRITE_ENC_MITM);
#endif
  events->addDescriptor(subscription);
  auto *write = service->createCharacteristic(COMMANDS_UUID, BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_WRITE_AUTHEN);
#if defined(CONFIG_BLUEDROID_ENABLED)
  write->setAccessPermissions(ESP_GATT_PERM_WRITE_ENC_MITM);
#endif
  write->setCallbacks(new CommandCallbacks());
  service->start();
  auto *advertising = BLEDevice::getAdvertising();
  advertising->addServiceUUID(SERVICE_UUID); advertising->setScanResponse(true);
  advertising->setMinPreferred(0x06); advertising->setMaxPreferred(0x12);
  BLEDevice::startAdvertising();
  Serial.println("BLE ready; no Wi-Fi. USB is programming/logs only.");
}
void loop() {
  if (disconnected) {
    disconnected = false; reset(); xQueueReset(commands);
    Serial.println("BLE disconnected; countdown cancelled");
    delay(100); BLEDevice::startAdvertising();
  }
  if (!connected) { delay(20); return; }
  Command cmd;
  while (xQueueReceive(commands, &cmd, 0) == pdTRUE) handleCommand(cmd);
  checkRemoval();
  if (phase == READING && !waitRemoval && reader.PICC_IsNewCardPresent() && reader.PICC_ReadCardSerial()) {
    uid = "";
    for (byte i = 0; i < reader.uid.size; i++) {
      char hex[3]; snprintf(hex, sizeof(hex), "%02X", reader.uid.uidByte[i]); uid += hex;
    }
    reader.PICC_HaltA(); reader.PCD_StopCrypto1();
    waitRemoval = true; absentSince = 0;
    phase = WAIT_RESULT; phaseStarted = millis();
    Serial.println("NFC read; waiting for Flutter/backend confirmation");
    event("card_scanned", "scan");
  }
  if (phase == COUNTDOWN && millis() - tickStarted >= 1000) {
    tickStarted = millis(); countdown--;
    if (countdown > 0) Serial.printf("Countdown: %d\n", countdown);
    else {
      phase = WAIT_SAVE; phaseStarted = millis();
      Serial.println("Simulated capture; waiting for backend save");
      event("capture_simulated", "capture");
    }
  }
  if ((phase == READING && millis() - phaseStarted > 35000) ||
      (phase == WAIT_RESULT && millis() - phaseStarted > 12000) ||
      (phase == WAIT_SAVE && millis() - phaseStarted > 25000)) error("flutter_timeout");
  delay(20);
}
