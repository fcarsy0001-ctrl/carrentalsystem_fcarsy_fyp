import 'dart:async';

import 'package:http/http.dart' as http;

class IotLedService {
  const IotLedService();

  // Change this to your ESP32 IP address on the same Wi-Fi as the phone.
  static const String _baseUrl = 'http://192.168.0.11';

  Future<void> setVehicleLock({required bool isLocked}) async {
    final action = isLocked ? 'lock' : 'unlock';
    final uri = Uri.parse('$_baseUrl/$action');

    final response = await http.get(uri).timeout(const Duration(seconds: 5));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('ESP32 returned ${response.statusCode}: ${response.body}');
    }
  }
}
