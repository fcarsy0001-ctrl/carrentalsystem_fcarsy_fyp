import 'package:supabase_flutter/supabase_flutter.dart';

import 'road_tax_monitor_service.dart';

class VehicleLocationService {
  VehicleLocationService(this._client);

  final SupabaseClient _client;

  static const String sqlPatch = '''
alter table public.vehicle_location
  add column if not exists is_active boolean not null default true;

alter table public.vehicle
  add column if not exists location_updated_at timestamp with time zone;
''';

  String _s(dynamic value) => value == null ? '' : value.toString().trim();

  List<Map<String, dynamic>> _rows(dynamic response) {
    if (response is! List) return const [];
    return response.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<List<Map<String, dynamic>>> fetchVehicles({String? leaserId}) async {
    await RoadTaxMonitorService(_client)
        .syncRoadTaxStates(leaserId: leaserId)
        .catchError((_) {});

    var query = _client.from('vehicle').select('*');
    if (_s(leaserId).isNotEmpty) {
      query = query.eq('leaser_id', leaserId!.trim());
    }
    final response = await query.order('vehicle_location', ascending: true).order('vehicle_id', ascending: true);
    return _rows(response);
  }

  Future<Map<String, bool>> fetchLocationActiveMap() async {
    try {
      final response = await _client
          .from('vehicle_location')
          .select('location_name, is_active')
          .order('location_name', ascending: true);
      final output = <String, bool>{};
      for (final row in _rows(response)) {
        final name = _s(row['location_name']);
        if (name.isEmpty) continue;
        output[name] = row['is_active'] as bool? ?? true;
      }
      return output;
    } catch (_) {
      return const {};
    }
  }

  Future<List<String>> fetchLocations() async {
    final records = await fetchLocationActiveMap();
    final output = <String>[];
    for (final entry in records.entries) {
      if (entry.value && entry.key.isNotEmpty) output.add(entry.key);
    }
    output.sort();
    return output;
  }

  Future<int> countVehiclesAtLocation(String locationName) async {
    final cleanName = locationName.trim();
    if (cleanName.isEmpty) return 0;
    final response = await _client
        .from('vehicle')
        .select('vehicle_id')
        .eq('vehicle_location', cleanName);
    return _rows(response).length;
  }

  Future<List<Map<String, dynamic>>> fetchHistory({String? vehicleId}) async {
    var query = _client.from('vehicle_location_history').select('*');
    if (_s(vehicleId).isNotEmpty) {
      query = query.eq('vehicle_id', vehicleId!.trim());
    }
    final response = await query.order('moved_at', ascending: false);
    return _rows(response);
  }

  Future<int> updateBranchActiveState({
    required String locationId,
    required String locationName,
    required bool isActive,
  }) async {
    await _client
        .from('vehicle_location')
        .update({'is_active': isActive})
        .eq('location_id', locationId.trim());

    if (isActive) return 0;

    final vehicles = _rows(await _client
        .from('vehicle')
        .select('vehicle_id, vehicle_status')
        .eq('vehicle_location', locationName.trim()));

    var changed = 0;
    for (final row in vehicles) {
      final vehicleId = _s(row['vehicle_id']);
      final status = _s(row['vehicle_status']).toLowerCase();
      if (vehicleId.isEmpty) continue;
      if (status == 'available' || status == 'active') {
        await _client.from('vehicle').update({'vehicle_status': 'Inactive'}).eq('vehicle_id', vehicleId);
        changed++;
      }
    }
    return changed;
  }

  Future<void> updateVehicleActiveState({
    required String vehicleId,
    required bool isActive,
    String? currentLocation,
    bool branchIsActive = true,
  }) async {
    final cleanVehicleId = vehicleId.trim();
    if (cleanVehicleId.isEmpty) {
      throw Exception('Vehicle ID is required.');
    }

    if (isActive && _s(currentLocation).isEmpty) {
      throw Exception('Assign the vehicle to an active branch before making it rentable.');
    }

    if (isActive && !branchIsActive) {
      throw Exception('This branch is inactive. Activate the branch first before making the vehicle rentable.');
    }

    await _client
        .from('vehicle')
        .update({'vehicle_status': isActive ? 'Available' : 'Inactive'})
        .eq('vehicle_id', cleanVehicleId);
  }

  Future<void> updateLocation({
    required String vehicleId,
    required String newLocation,
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
    final now = DateTime.now().toUtc().toIso8601String();
    final note = _buildMovementReason(remarks: remarks);

    try {
      await _client.from('vehicle').update({
        'vehicle_location': newLocation.trim(),
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
        'moved_at': now,
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
          'moved_at': now,
          'moved_by': _s(movedBy).isEmpty ? null : _s(movedBy),
          'movement_reason': note.isEmpty ? null : note,
        });
      } catch (_) {}
    }
  }

  bool branchIsActive(Map<String, dynamic> vehicle) {
    final value = vehicle['branch_is_active'];
    if (value is bool) return value;
    return true;
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


  String parseRemarks(Map<String, dynamic> history) {
    final reason = _s(history['movement_reason']);
    if (reason.isEmpty) return '';
    final lines = reason.split('\n');
    final cleaned = lines.where((line) => !line.toLowerCase().startsWith('parking slot:')).toList();
    return cleaned.join('\n').trim();
  }


  String currentUpdatedAt(Map<String, dynamic> vehicle, {Map<String, dynamic>? latestHistory}) {
    final direct = _s(vehicle['location_updated_at']);
    final history = latestHistory == null ? '' : _s(latestHistory['moved_at']);

    if (direct.isEmpty) return history;
    if (history.isEmpty) return direct;

    final directTime = DateTime.tryParse(direct);
    final historyTime = DateTime.tryParse(history);
    if (directTime == null || historyTime == null) return history;

    return historyTime.isAfter(directTime) ? history : direct;
  }

  String statusLabel(Map<String, dynamic> vehicle) {
    final location = _s(vehicle['vehicle_location']);
    final status = _s(vehicle['vehicle_status']).toLowerCase();
    final roadTaxExpiry = DateTime.tryParse(_s(vehicle['road_tax_expiry_date']));
    final today = DateTime.now().toUtc().add(const Duration(hours: 8));
    final todayOnly = DateTime(today.year, today.month, today.day);
    final expiryOnly = roadTaxExpiry == null
        ? null
        : DateTime(roadTaxExpiry.year, roadTaxExpiry.month, roadTaxExpiry.day);
    if (expiryOnly != null && expiryOnly.isBefore(todayOnly)) return 'Inactive';
    if (!branchIsActive(vehicle)) return 'Inactive';
    if (status == 'inactive' || status.contains('deactive') || status == 'disabled') return 'Inactive';
    if (location.isEmpty) return 'Pending';
    if (status == 'available' || status == 'active') return 'Active';
    if (status.contains('maint') || status == 'unavail' || status == 'unavailable') return 'Maintenance';
    if (status == 'pending' || status == 'processing' || status.isEmpty) return 'Pending';
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

  String _buildMovementReason({String? remarks}) {
    final lines = <String>[];
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
















