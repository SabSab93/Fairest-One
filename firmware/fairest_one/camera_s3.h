#pragma once

#include <esp_camera.h>

static bool cameraReady = false;
static camera_fb_t *latestPhoto = nullptr;

static void beginMirrorCamera() {
  if (!psramFound()) {
    Serial.println("Camera: activez OPI PSRAM dans Arduino.");
    return;
  }

  camera_config_t config = {};
  config.ledc_channel = LEDC_CHANNEL_7;
  config.ledc_timer = LEDC_TIMER_3;
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

  const esp_err_t result = esp_camera_init(&config);
  cameraReady = result == ESP_OK;
  if (cameraReady) Serial.printf("Camera detectee (PID 0x%04x).\n", esp_camera_sensor_get()->id.PID);
  else Serial.printf("Camera indisponible : %s.\n", esp_err_to_name(result));
}

static bool takeMirrorPhoto() {
  if (!cameraReady) return false;
  if (latestPhoto) {
    esp_camera_fb_return(latestPhoto);
    latestPhoto = nullptr;
  }

  // Discard any queued frame so the photo is taken after the countdown.
  camera_fb_t *queued = esp_camera_fb_get();
  if (!queued) return false;
  esp_camera_fb_return(queued);
  camera_fb_t *frame = esp_camera_fb_get();
  if (!frame) return false;
  if (frame->format != PIXFORMAT_JPEG || frame->len < 4 ||
      frame->buf[0] != 0xff || frame->buf[1] != 0xd8 ||
      frame->buf[frame->len - 2] != 0xff || frame->buf[frame->len - 1] != 0xd9) {
    esp_camera_fb_return(frame);
    return false;
  }

  latestPhoto = frame;
  Serial.printf("Photo JPEG : %u x %u, %u octets.\n", static_cast<unsigned>(frame->width),
      static_cast<unsigned>(frame->height), static_cast<unsigned>(frame->len));
  return true;
}

static void exportMirrorPhoto() {
  if (!latestPhoto) {
    Serial.println("Aucune photo en memoire.");
    return;
  }
  Serial.printf("JPEG_BYTES %u\n", static_cast<unsigned>(latestPhoto->len));
  Serial.write(latestPhoto->buf, latestPhoto->len);
}
