#include <WiFi.h>
#include <WebServer.h>

WebServer server(80);

String readLine() {
  while (true) {
    if (Serial.available()) {
      String line = Serial.readStringUntil('\n');
      if (line.endsWith("\r")) line.remove(line.length() - 1);
      if (line.length()) return line;
    }
    delay(20);
  }
}

void setup() {
  Serial.begin(115200);
  Serial.setTimeout(1000);
  while (!Serial) delay(20);
  WiFi.persistent(false);
  WiFi.mode(WIFI_STA);

  while (WiFi.status() != WL_CONNECTED) {
    Serial.println("Nom du partage de connexion :");
    const String ssid = readLine();
    Serial.println("Mot de passe Wi-Fi :");
    const String password = readLine();
    WiFi.begin(ssid.c_str(), password.c_str());
    Serial.println("Connexion en cours...");

    const unsigned long started = millis();
    while (WiFi.status() != WL_CONNECTED && millis() - started < 25000) delay(250);
    if (WiFi.status() != WL_CONNECTED) {
      WiFi.disconnect();
      Serial.println("Connexion echouee. Laissez le partage de connexion ouvert et reessayez.");
    }
  }

  server.on("/", HTTP_GET, []() {
    Serial.println("Requete HTTP recue.");
    server.send(200, "text/plain", "Fairest One : connexion Wi-Fi OK");
  });
  server.begin();
  Serial.print("Ouvrez sur l'iPhone : http://");
  Serial.println(WiFi.localIP());
}

void loop() {
  server.handleClient();
  delay(10);
}
