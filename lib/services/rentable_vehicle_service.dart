import 'package:supabase_flutter/supabase_flutter.dart';

class RentableVehicleService {
  RentableVehicleService(this._client);

  final SupabaseClient _client;

  String _s(dynamic value) => value == null ? '' : value.toString().trim();

  DateTime _mytToday() {
    final now = DateTime.now().toUtc().add(const Duration(hours: 8));
    return DateTime(now.year, now.month, now.day);
  }

  DateTime? _dateOnly(dynamic value) {
    final raw = _s(value);
    if (raw.isEmpty) return null;
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return null;
    return DateTime(parsed.year, parsed.month, parsed.day);
  }

  List<Map<String, dynamic>> _rows(dynamic response) {
    if (response is! List) return const [];
    return response.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<Set<String>?> fetchActiveLocationNames() async {
    try {
      final rows = await _client
          .from('vehicle_location')
          .select('location_name, is_active');
      final output = <String>{};
      for (final row in _rows(rows)) {
        final name = _s(row['location_name']);
        final active = row['is_active'] as bool? ?? true;
        if (active && name.isNotEmpty) output.add(name);
      }
      return output;
    } catch (_) {
      return null;
    }
  }

  Future<Set<String>?> fetchBlockedVehicleIds() async {
    try {
      final rows = await _client
          .from('service_job_order')
          .select('vehicle_id')
          .inFilter('status', ['Pending', 'In Progress']);
      final output = <String>{};
      for (final row in _rows(rows)) {
        final vehicleId = _s(row['vehicle_id']);
        if (vehicleId.isNotEmpty) output.add(vehicleId);
      }
      return output;
    } catch (_) {
      return null;
    }
  }

  bool isInActiveBranch(Map<String, dynamic> row, Set<String>? activeLocations) {
    if (activeLocations == null) return true;
    final location = _s(row['vehicle_location']);
    return location.isNotEmpty && activeLocations.contains(location);
  }

  bool isRoadTaxExpired(Map<String, dynamic> row) {
    final expiry = _dateOnly(row['road_tax_expiry_date']);
    if (expiry == null) return false;
    return expiry.isBefore(_mytToday());
  }

  bool isRentableVehicle(
      Map<String, dynamic> row,
      Set<String>? activeLocations,
      Set<String>? blockedVehicleIds,
      ) {
    final status = _s(row['vehicle_status']).toLowerCase();
    final vehicleId = _s(row['vehicle_id']);
    if (status != 'available') return false;
    if (isRoadTaxExpired(row)) return false;
    if (!isInActiveBranch(row, activeLocations)) return false;
    if (blockedVehicleIds != null && vehicleId.isNotEmpty && blockedVehicleIds.contains(vehicleId)) {
      return false;
    }
    return true;
  }
}
