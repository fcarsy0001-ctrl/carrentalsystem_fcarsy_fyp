import 'package:supabase_flutter/supabase_flutter.dart';

class VehicleLocationService {
  VehicleLocationService(this._client);

  final SupabaseClient _client;

  String _s(dynamic value) => value == null ? '' : value.toString().trim();

  List<Map<String, dynamic>> _rows(dynamic response) {
    if (response is! List) return const [];
    return response.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<List<Map<String, dynamic>>> fetchVehicles({String? leaserId}) async {
    var query = _client.from('vehicle').select('*');
    if (_s(leaserId).isNotEmpty) {
      query = query.eq('leaser_id', leaserId!.trim());
    }
    final response = await query.order('vehicle_location', ascending: true).order('vehicle_id', ascending: true);
    return _rows(response);
  }

  Future<List<String>> fetchLocations() async {
    try {
      final response = await _client
          .from('vehicle_location')
          .select('location_name, is_active')
          .order('location_name', ascending: true);
      final output = <String>[];
      for (final row in _rows(response)) {
        final name = _s(row['location_name']);
        final active = row['is_active'] as bool? ?? true;
        if (active && name.isNotEmpty) output.add(name);
      }
      return output;
    } catch (_) {
      return const [];
    }
  }

  Future<List<Map<String, dynamic>>> fetchHistory({String? vehicleId}) async {
    var query = _client.from('vehicle_location_history').select('*');
    if (_s(vehicleId).isNotEmpty) {
      query = query.eq('vehicle_id', vehicleId!.trim());
    }
    final response = await query.order('moved_at', ascending: false);
    return _rows(response);
  }

  Future<void> updateLocation({
    required String vehicleId,
    required String newLocation,
    required String parkingSlot,
    String? movedBy,
    String? remarks,
  }) async {
    final current = await _client
        .from('vehicle')
        .select('*')
        .eq('vehicle_id', vehicleId)
        .maybeSingle();

    final previous = current == null ? <String, dynamic>{} : Map<String, dynamic>.from(current as Map);
    final previousLocation = _s(previous['vehicle_location']);
    final previousParkingSlot = _s(previous['vehicle_parking_slot']);
    final now = DateTime.now().toUtc().toIso8601String();
    final note = _buildMovementReason(parkingSlot: parkingSlot, remarks: remarks);

    try {
      await _client.from('vehicle').update({
        'vehicle_location': newLocation.trim(),
        'vehicle_parking_slot': parkingSlot.trim(),
        'location_updated_at': now,
      }).eq('vehicle_id', vehicleId.trim());
    } catch (_) {
      await _client.from('vehicle').update({
        'vehicle_location': newLocation.trim(),
      }).eq('vehicle_id', vehicleId.trim());
    }

    try {
      await _client.from('vehicle_location_history').insert({
        'location_history_id': _newId('LOC'),
        'vehicle_id': vehicleId.trim(),
        'previous_location': previousLocation.isEmpty ? null : previousLocation,
        'new_location': newLocation.trim(),
        'previous_parking_slot': previousParkingSlot.isEmpty ? null : previousParkingSlot,
        'new_parking_slot': parkingSlot.trim().isEmpty ? null : parkingSlot.trim(),
        'moved_by': _s(movedBy).isEmpty ? null : _s(movedBy),
        'movement_reason': _s(remarks).isEmpty ? null : _s(remarks),
      });
    } catch (_) {
      try {
        await _client.from('vehicle_location_history').insert({
          'location_history_id': _newId('LOC'),
          'vehicle_id': vehicleId.trim(),
          'previous_location': previousLocation.isEmpty ? null : previousLocation,
          'new_location': newLocation.trim(),
          'moved_by': _s(movedBy).isEmpty ? null : _s(movedBy),
          'movement_reason': note.isEmpty ? null : note,
        });
      } catch (_) {}
    }
  }

  String vehicleTitle(Map<String, dynamic> vehicle) {
    final brand = _s(vehicle['vehicle_brand']);
    final model = _s(vehicle['vehicle_model']);
    final plate = _s(vehicle['vehicle_plate_no']);
    final title = '$brand $model'.trim();
    if (title.isNotEmpty) return title;
    if (plate.isNotEmpty) return plate;
    return _s(vehicle['vehicle_id']).isEmpty ? 'Vehicle' : _s(vehicle['vehicle_id']);
  }

  String parseParkingSlot(Map<String, dynamic> history) {
    final direct = _s(history['new_parking_slot']);
    if (direct.isNotEmpty) return direct;

    final reason = _s(history['movement_reason']);
    if (reason.isEmpty) return '';

    final line = reason.split('\n').firstWhere(
          (item) => item.toLowerCase().startsWith('parking slot:'),
          orElse: () => '',
        );
    if (line.isEmpty) return '';
    return line.split(':').skip(1).join(':').trim();
  }

  String parseRemarks(Map<String, dynamic> history) {
    final reason = _s(history['movement_reason']);
    if (reason.isEmpty) return '';
    final lines = reason.split('\n');
    final cleaned = lines.where((line) => !line.toLowerCase().startsWith('parking slot:')).toList();
    return cleaned.join('\n').trim();
  }

  String currentParkingSlot(Map<String, dynamic> vehicle, {Map<String, dynamic>? latestHistory}) {
    final direct = _s(vehicle['vehicle_parking_slot']);
    if (direct.isNotEmpty) return direct;
    if (latestHistory == null) return '';
    return parseParkingSlot(latestHistory);
  }

  String currentUpdatedAt(Map<String, dynamic> vehicle, {Map<String, dynamic>? latestHistory}) {
    final direct = _s(vehicle['location_updated_at']);
    if (direct.isNotEmpty) return direct;
    if (latestHistory == null) return '';
    return _s(latestHistory['moved_at']);
  }

  String statusLabel(Map<String, dynamic> vehicle) {
    final location = _s(vehicle['vehicle_location']);
    final status = _s(vehicle['vehicle_status']).toLowerCase();
    if (location.isEmpty) return 'Idle';
    if (status == 'available' || status == 'active') return 'Active';
    if (status.contains('maint') || status == 'unavail' || status == 'unavailable') return 'Maintenance';
    if (status == 'pending' || status == 'processing' || status.isEmpty) return 'Idle';
    return 'Other';
  }

  String explainError(Object error) {
    final message = error.toString();
    final lower = message.toLowerCase();
    if (lower.contains('vehicle_location_history') || lower.contains('vehicle_location')) {
      return 'The location tables or fields are not fully ready in Supabase yet. Run the location SQL patch, then refresh.\n\n$message';
    }
    return message;
  }

  String _buildMovementReason({required String parkingSlot, String? remarks}) {
    final lines = <String>[];
    if (parkingSlot.trim().isNotEmpty) {
      lines.add('Parking Slot: ${parkingSlot.trim()}');
    }
    if (_s(remarks).isNotEmpty) {
      lines.add(_s(remarks));
    }
    return lines.join('\n').trim();
  }

  String _newId(String prefix) {
    final cleaned = prefix.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    final safePrefix = cleaned.isEmpty ? 'ID' : cleaned;
    final suffixLength = safePrefix.length >= 10 ? 1 : 10 - safePrefix.length;
    final micros = DateTime.now().microsecondsSinceEpoch.toString();
    final suffix = micros.substring(micros.length - suffixLength);
    return '$safePrefix$suffix';
  }
}
