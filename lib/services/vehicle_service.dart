import 'package:supabase_flutter/supabase_flutter.dart';

class VehicleService {
  VehicleService(this._client);

  final SupabaseClient _client;

  Future<List<Map<String, dynamic>>> listVehicles({int limit = 100}) async {
    final rows = await _client
        .from('vehicle')
        .select('vehicle_id,leaser_id,vehicle_brand,vehicle_model,vehicle_plate_no,vehicle_type,transmission_type,fuel_type,seat_capacity,daily_rate,vehicle_location,vehicle_description,vehicle_status')
        .order('vehicle_id')
        .limit(limit);

    return (rows as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<String> nextVehicleId() async {
    try {
      final row = await _client
          .from('vehicle')
          .select('vehicle_id')
          .order('vehicle_id', ascending: false)
          .limit(1)
          .maybeSingle();

      final last = (row?['vehicle_id'] as String?) ?? '';
      final m = RegExp(r'^V(\d+)$').firstMatch(last);
      if (m != null) {
        final n = int.tryParse(m.group(1)!) ?? 0;
        final next = n + 1;
        return 'V${next.toString().padLeft(3, '0')}';
      }
      return 'V001';
    } catch (_) {
      final ts = DateTime.now().millisecondsSinceEpoch;
      return 'V${ts.toString().substring(ts.toString().length - 6)}';
    }
  }

  Future<void> createVehicle({
    required String vehicleId,
    required String leaserId,
    required String brand,
    required String model,
    required String plateNo,
    required String vehicleType,
    required String transmissionType,
    required String fuelType,
    required int seatCapacity,
    required num dailyRate,
    required String location,
    required String status,
    String? description,
  }) async {
    await _client.from('vehicle').insert({
      'vehicle_id': vehicleId,
      'leaser_id': leaserId,
      'vehicle_brand': brand,
      'vehicle_model': model,
      'vehicle_plate_no': plateNo,
      'vehicle_type': vehicleType,
      'transmission_type': transmissionType,
      'fuel_type': fuelType,
      'seat_capacity': seatCapacity,
      'daily_rate': dailyRate,
      'vehicle_location': location,
      'vehicle_description': description,
      'vehicle_status': status,
    });
  }
}
