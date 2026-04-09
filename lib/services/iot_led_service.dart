import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

class IotLedService {
  const IotLedService();

  // Use the current IP shown in ESP32 Serial Monitor.
  // If the ESP32 reconnects to Wi-Fi and gets a new IP, update this.
  static const String _baseUrl = 'http://192.168.0.5';

  // Map your real vehicle IDs to physical IoT slots.
  // Slot 1 = Car 1 RGB LED
  // Slot 2 = Car 2 RGB LED
  static const Map<String, int> vehicleSlotMap = {
    'V326978000': 1,
    'V943471000': 2,
  };

  int? resolveVehicleSlot(String vehicleId) {
    final raw = vehicleId.trim();
    if (raw.isEmpty) return null;

    for (final entry in vehicleSlotMap.entries) {
      if (entry.key.toLowerCase() == raw.toLowerCase()) {
        return entry.value;
      }
    }
    return null;
  }

  Future<void> setVehicleLock({
    required int slot,
    required bool isLocked,
  }) async {
    final action = isLocked ? 'lock' : 'unlock';
    final uri = Uri.parse('$_baseUrl/car/$slot/$action');

    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 5));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('ESP32 returned ${response.statusCode}: ${response.body}');
      }
    } on SocketException {
      throw Exception(
        'ESP32 not reachable at $_baseUrl. Check the current IP in Serial Monitor, make sure the phone and ESP32 are on the same Wi-Fi, then update _baseUrl in lib/services/iot_led_service.dart.',
      );
    } on TimeoutException {
      throw Exception(
        'ESP32 request timed out at $_baseUrl. Check power, Wi-Fi, and whether the ESP32 HTTP server is still running.',
      );
    }
  }
}