// ESP32-S3-CAM N16R8, camera connector with the Espressif S3-EYE pinout.
// Arduino: ESP32S3 Dev Module, 16 MB Flash, OPI PSRAM.
#include <Arduino.h>
#include <esp_camera.h>

bool cameraReady = false;

void setup() {
  Serial.begin(115200);
  camera_config_t config = {};
  config.ledc_channel = LEDC_CHANNEL_0;
  config.ledc_timer = LEDC_TIMER_0;
  config.pin_d0 = 11;
  config.pin_d1 = 9;
  config.pin_d2 = 8;
  config.pin_d3 = 10;
  config.pin_d4 = 12;
  config.pin_d5 = 18;
  config.pin_d6 = 17;
  config.pin_d7 = 16;
  config.pin_xclk = 15;
  config.pin_pclk = 13;
  config.pin_vsync = 6;
  config.pin_href = 7;
  config.pin_sccb_sda = 4;
  config.pin_sccb_scl = 5;
  config.pin_pwdn = -1;
  config.pin_reset = -1;
  config.xclk_freq_hz = 20000000;
  config.pixel_format = PIXFORMAT_JPEG;
  config.frame_size = FRAMESIZE_VGA;
  config.jpeg_quality = 12;
  config.fb_count = 1;
  config.fb_location = CAMERA_FB_IN_PSRAM;
  config.grab_mode = CAMERA_GRAB_WHEN_EMPTY;

  if (!psramFound()) {
    Serial.println("PSRAM introuvable. Activez OPI PSRAM dans Arduino.");
    return;
  }
  const esp_err_t result = esp_camera_init(&config);
  if (result != ESP_OK) {
    Serial.printf("Initialisation camera echouee : %s (0x%x)\n", esp_err_to_name(result), result);
    return;
  }
  const sensor_t *sensor = esp_camera_sensor_get();
  cameraReady = true;
  Serial.printf("Camera detectee (PID 0x%04x). Envoyez p pour tester ou j pour exporter un JPEG.\n",
      sensor->id.PID);
}

void loop() {
  const int command = Serial.read();
  if (command == 'p' || command == 'j') {
    if (!cameraReady) {
      Serial.println("Camera indisponible. Redemarrez pour revoir le diagnostic.");
      return;
    }
    camera_fb_t *frame = esp_camera_fb_get();
    if (!frame) {
      Serial.println("Echec de la capture.");
      return;
    }
    const bool jpeg = frame->format == PIXFORMAT_JPEG && frame->len >= 4 &&
        frame->buf[0] == 0xff && frame->buf[1] == 0xd8 &&
        frame->buf[frame->len - 2] == 0xff && frame->buf[frame->len - 1] == 0xd9;
    if (jpeg && command == 'j') {
      Serial.printf("JPEG_BYTES %u\n", static_cast<unsigned>(frame->len));
      Serial.write(frame->buf, frame->len);
    } else if (jpeg) {
      Serial.printf("JPEG capture : %u x %u, %u octets.\n",
          static_cast<unsigned>(frame->width), static_cast<unsigned>(frame->height),
          static_cast<unsigned>(frame->len));
    } else {
      Serial.println("Image recue, mais JPEG invalide.");
    }
    esp_camera_fb_return(frame);
  }
  delay(20);
}
