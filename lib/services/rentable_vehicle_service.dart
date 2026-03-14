import 'package:supabase_flutter/supabase_flutter.dart';

class RentableVehicleService {
  RentableVehicleService(this._client);

  final SupabaseClient _client;

  String _s(dynamic value) => value == null ? '' : value.toString().trim();

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

  bool isInActiveBranch(Map<String, dynamic> row, Set<String>? activeLocations) {
    if (activeLocations == null) return true;
    final location = _s(row['vehicle_location']);
    return location.isNotEmpty && activeLocations.contains(location);
  }
}