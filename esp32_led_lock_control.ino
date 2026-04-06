#include <WiFi.h>
#include <WebServer.h>

const char* WIFI_SSID = "Tan6238369@";
const char* WIFI_PASSWORD = "Tan238369@";

// Change this if your LED is on another GPIO.
const int LED_PIN = 2;

WebServer server(80);

void handleLock() {
  digitalWrite(LED_PIN, HIGH);
  server.send(200, "text/plain", "LOCKED");
}

void handleUnlock() {
  digitalWrite(LED_PIN, LOW);
  server.send(200, "text/plain", "UNLOCKED");
}

void handleStatus() {
  String state = digitalRead(LED_PIN) == HIGH ? "LOCKED" : "UNLOCKED";
  server.send(200, "text/plain", state);
}

void setup() {
  Serial.begin(115200);
  pinMode(LED_PIN, OUTPUT);
  digitalWrite(LED_PIN, LOW);

  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  Serial.print("Connecting to WiFi");
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }

  Serial.println();
  Serial.print("ESP32 IP address: ");
  Serial.println(WiFi.localIP());

  server.on("/lock", HTTP_GET, handleLock);
  server.on("/unlock", HTTP_GET, handleUnlock);
  server.on("/status", HTTP_GET, handleStatus);
  server.begin();
  Serial.println("HTTP server started");
}

void loop() {
  server.handleClient();
}
