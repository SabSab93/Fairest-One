// ESP32-C6, Arduino ESP32 core 3.3.12; MFRC522 1.4.12; ArduinoJson 7.4.2.
// Wi-Fi mirror with autonomous try-ons and optional iPhone controls.
#include <Arduino.h>
#include <SPI.h>
#include <MFRC522.h>
#include <WiFi.h>
#include <NetworkClientSecure.h>
#include <HTTPClient.h>
#include <WebServer.h>
#include <ArduinoJson.h>
#include <mbedtls/md.h>
#include <time.h>
#include "config.h"

#ifndef MIRROR_API_URL
#define MIRROR_API_URL "https://fairest-one-documentation.vercel.app/api/clients"
#endif

#define LED_RED 5
#define LED_GREEN 6
#define LED_BLUE 4
#define BUZZER_PIN 20
#define SS_PIN 10
#define RST_PIN 3
#define SCK_PIN 19
#define MOSI_PIN 18
#define MISO_PIN 2

MFRC522 reader(SS_PIN, RST_PIN);
WebServer server(80);
bool connected = false;
String eventToken, eventJson;
uint32_t lastContact = 0;
enum Phase { IDLE, READING, WAIT_RESULT, COUNTDOWN, WAIT_SAVE };
Phase phase = IDLE;
String token, uid;
uint32_t phaseStarted = 0, tickStarted = 0, absentSince = 0;
int countdown = 3;
bool waitRemoval = false;
bool autonomous = false;

void rgb(bool red, bool green, bool blue) {
  digitalWrite(LED_RED, RGB_COMMON_ANODE ? !red : red);
  digitalWrite(LED_GREEN, RGB_COMMON_ANODE ? !green : green);
  digitalWrite(LED_BLUE, RGB_COMMON_ANODE ? !blue : blue);
}
void pulse(uint16_t frequency, uint16_t duration) {
  if (BUZZER_ACTIVE) digitalWrite(BUZZER_PIN, HIGH);
  else tone(BUZZER_PIN, frequency);
  delay(duration);
  if (BUZZER_ACTIVE) digitalWrite(BUZZER_PIN, LOW);
  else noTone(BUZZER_PIN);
}
void beep(int count) {
  for (int i = 0; i < count && connected; ++i) {
    pulse(2000, 90);
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
  eventToken = token;
  eventJson = "";
  serializeJson(doc, eventJson);
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
  autonomous = false;
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
bool validToken(const String &s) {
  if (s.length() != 64) return false;
  for (char c : s) if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f'))) return false;
  return true;
}

int postToApi(const char *action, JsonDocument &reply) {
  if (WiFi.status() != WL_CONNECTED || time(nullptr) < 1735689600) {
    Serial.println("API unavailable: Wi-Fi or clock not ready");
    return -1;
  }
  NetworkClientSecure client;
  client.useBuiltinCACertBundle();
  client.setHandshakeTimeout(5);
  HTTPClient http;
  http.setConnectTimeout(3500);
  http.setTimeout(5000);
  if (!String(MIRROR_API_URL).startsWith("https://") || !http.begin(client, MIRROR_API_URL)) return -1;
  http.addHeader("Content-Type", "application/json");
  JsonDocument request;
  request["action"] = action;
  if (token.length()) request["token"] = token;
  if (strcmp(action, "scan") == 0 || strcmp(action, "capture") == 0) {
    request["card_uid"] = uid;
    request["proof"] = proof(action);
  }
  String body;
  serializeJson(request, body);
  reply.clear();
  int status = http.POST(body);
  if (status == 200 && deserializeJson(reply, http.getString())) status = -1;
  http.end();
  if (status != 200) Serial.printf("Mirror API %s: %d\n", action, status);
  return status;
}

void countdownSignal() {
  Serial.printf("Countdown: %d\n", countdown);
  rgb(false, false, true);
  pulse(2000, 75);
}

void beginAutonomousCapture() {
  connected = false;
  autonomous = true;
  rgb(false, false, true);
  JsonDocument reply;
  if (postToApi("begin_recognition", reply) == 200) {
    token = reply["token"].as<String>();
    if (validToken(token) && postToApi("scan", reply) == 200) {
      String state = reply["state"] | "";
      if (state == "recognized") {
        phase = COUNTDOWN;
        tickStarted = millis();
        countdown = 3;
        countdownSignal();
        return;
      }
      if (state == "unknown") {
        Serial.println("Autonomous try-on: unregistered card");
        rgb(true, false, false);
        pulse(900, 200);
        reset();
        return;
      }
    }
    if (validToken(token)) postToApi("cancel", reply);
  }
  Serial.println("Autonomous try-on: card verification failed");
  rgb(true, false, false);
  pulse(900, 350);
  reset();
}

void saveAutonomousCapture() {
  // Two short pulses imitate the two parts of a mechanical shutter.
  rgb(true, true, true);
  pulse(2600, 25);
  delay(35);
  pulse(1400, 65);
  rgb(false, false, false);
  Serial.println("Autonomous try-on: shutter simulated");
  JsonDocument reply;
  int status = postToApi("capture", reply);
  // The server deduplicates retries for this token.
  if (status < 0 || status >= 500) status = postToApi("capture", reply);
  const bool saved = status == 200 && reply["state"] == "captured";
  Serial.println(saved ? "Backend confirmed autonomous simulated capture" : "Autonomous capture was not confirmed");
  rgb(!saved, saved, false);
  delay(350);
  reset();
}

void handleCommand(const JsonDocument &doc) {
  String type = doc["type"] | "";
  if (type == "scan" && phase == IDLE) {
    token = doc["token"].as<String>();
    eventToken = "";
    eventJson = "";
    phase = READING; phaseStarted = millis();
    rgb(false, false, true);
    Serial.println("Scan armed: present card to RC522");
    return;
  }
  if (type == "cancel") { reset(); return; }
  if (type == "capture_saved" && phase == WAIT_SAVE) {
    Serial.println("Backend confirmed simulated capture"); reset(); return;
  }
  if (type != "card_result" || phase != WAIT_RESULT || !doc["recognized"].is<bool>()) return;
  if (!doc["recognized"].as<bool>()) {
    Serial.println("Rejected: no countdown or capture");
    rgb(true, false, false); beep(3);
    event("card_result_applied"); reset(); return;
  }
  rgb(false, true, false); beep(2);
  if (!(doc["capture"] | false)) { event("card_result_applied"); reset(); return; }
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
void handleHttp(bool polling) {
  if (autonomous) {
    server.send(409, "text/plain", "Autonomous try-on in progress");
    return;
  }
  const String body = server.arg("plain");
  JsonDocument doc;
  if (body.length() > 512 || deserializeJson(doc, body)) {
    server.send(400, "text/plain", "Invalid request");
    return;
  }
  String incoming = doc["token"] | "";
  if (!validToken(incoming)) {
    server.send(400, "text/plain", "Invalid token");
    return;
  }
  if (polling) {
    if (incoming == token) lastContact = millis();
    if (incoming == eventToken) server.send(200, "application/json", eventJson);
    else server.send(204);
    return;
  }
  String type = doc["type"] | "";
  if (type == "scan" && phase == IDLE) {
    connected = true;
  } else if (incoming != token) {
    server.send(409, "text/plain", "Mirror busy or session expired");
    return;
  }
  lastContact = millis();
  // Reply before running LED/buzzer feedback, which may take several hundred ms.
  server.send(204);
  handleCommand(doc);
}

String readWifiLine() {
  while (true) {
    if (Serial.available()) {
      String value = Serial.readStringUntil('\n');
      if (value.endsWith("\r")) value.remove(value.length() - 1);
      if (value.length()) return value;
    }
    delay(20);
  }
}

void connectWifi() {
  WiFi.persistent(false);
  WiFi.mode(WIFI_STA);
  WiFi.setAutoReconnect(true);
  while (WiFi.status() != WL_CONNECTED) {
    Serial.println("Nom du partage de connexion :");
    const String ssid = readWifiLine();
    Serial.println("Mot de passe Wi-Fi :");
    const String password = readWifiLine();
    WiFi.begin(ssid.c_str(), password.c_str());
    uint32_t started = millis();
    while (WiFi.status() != WL_CONNECTED && millis() - started < 25000) delay(250);
    if (WiFi.status() != WL_CONNECTED) {
      WiFi.disconnect();
      Serial.println("Connexion echouee. Verifiez le partage de connexion.");
    }
  }
}

void setup() {
  Serial.begin(115200);
  Serial.setTimeout(1000);
  while (!Serial) delay(20);
  pinMode(LED_RED, OUTPUT); pinMode(LED_GREEN, OUTPUT); pinMode(LED_BLUE, OUTPUT);
  pinMode(BUZZER_PIN, OUTPUT); reset();
  // Visual self-test: verify actual red, green, blue; change pin mapping if needed.
  rgb(true, false, false); Serial.println("RGB test: RED (GPIO5)"); delay(700);
  rgb(false, true, false); Serial.println("RGB test: GREEN (GPIO6)"); delay(700);
  rgb(false, false, true); Serial.println("RGB test: BLUE (GPIO4)"); delay(700);
  reset();
  if (strlen(MIRROR_SIGNING_KEY) < 32 || String(MIRROR_SIGNING_KEY).startsWith("REPLACE_")) {
    Serial.println("Configure MIRROR_SIGNING_KEY in config.h first.");
    while (true) delay(1000);
  }
  SPI.begin(SCK_PIN, MISO_PIN, MOSI_PIN, SS_PIN);
  reader.PCD_Init(); reader.PCD_DumpVersionToSerial();
  connectWifi();
  configTime(0, 0, "time.cloudflare.com", "pool.ntp.org");
  server.on("/mirror/status", HTTP_GET, [] {
    server.send(200, "text/plain", "fairest-one-wifi-v1");
  });
  server.on("/mirror/command", HTTP_POST, [] { handleHttp(false); });
  server.on("/mirror/event", HTTP_POST, [] { handleHttp(true); });
  server.begin();
  Serial.println("Autonomous try-on ready: present a registered card");
}
void loop() {
  if (WiFi.status() != WL_CONNECTED || (connected && millis() - lastContact > 5500)) {
    if (connected) {
      reset();
      eventToken = "";
      eventJson = "";
      connected = false;
    }
  }
  static IPAddress lastIp;
  if (WiFi.status() == WL_CONNECTED) {
    if (WiFi.localIP() != lastIp) {
      lastIp = WiFi.localIP();
      Serial.print("Adresse du miroir : ");
      Serial.println(lastIp);
    }
    server.handleClient();
  } else {
    lastIp = IPAddress();
  }
  checkRemoval();
  const bool readyForCard = phase == READING || (phase == IDLE && WiFi.status() == WL_CONNECTED);
  if (readyForCard && !waitRemoval && reader.PICC_IsNewCardPresent() && reader.PICC_ReadCardSerial()) {
    uid = "";
    for (byte i = 0; i < reader.uid.size; i++) {
      char hex[3]; snprintf(hex, sizeof(hex), "%02X", reader.uid.uidByte[i]); uid += hex;
    }
    reader.PICC_HaltA(); reader.PCD_StopCrypto1();
    waitRemoval = true; absentSince = 0;
    if (phase == READING) {
      phase = WAIT_RESULT; phaseStarted = millis();
      Serial.println("NFC read; waiting for app/backend confirmation");
      event("card_scanned", "scan");
    } else {
      beginAutonomousCapture();
    }
  }
  if (autonomous && phase == COUNTDOWN && millis() - tickStarted >= 200) rgb(false, false, false);
  if (phase == COUNTDOWN && millis() - tickStarted >= 1000) {
    tickStarted = millis(); countdown--;
    if (autonomous) {
      if (countdown > 0) countdownSignal();
      else saveAutonomousCapture();
    } else if (countdown > 0) Serial.printf("Countdown: %d\n", countdown);
    else {
      phase = WAIT_SAVE; phaseStarted = millis();
      Serial.println("Simulated capture; waiting for backend save");
      event("capture_simulated", "capture");
    }
  }
  if ((phase == READING && millis() - phaseStarted > 35000) ||
      (phase == WAIT_RESULT && millis() - phaseStarted > 12000) ||
      (phase == WAIT_SAVE && millis() - phaseStarted > 25000)) error("mirror_timeout");
  delay(20);
}
