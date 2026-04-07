import 'package:supabase_flutter/supabase_flutter.dart';

class BookingAvailabilityService {
  BookingAvailabilityService(this._supa);

  final SupabaseClient _supa;

  DateTime? _dt(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    try {
      return DateTime.parse(value.toString());
    } catch (_) {
      return null;
    }
  }

  bool _isBlockingStatus(Map<String, dynamic> row) {
    final status = (row['booking_status'] ?? '').toString().trim().toLowerCase();
    if (status.isEmpty) return true;
    if (status == 'cancel' ||
        status == 'cancelled' ||
        status == 'canceled' ||
        status == 'deactive' ||
        status == 'deactivated' ||
        status == 'inactive' ||
        status == 'completed' ||
        status == 'complete' ||
        status == 'done' ||
        status == 'expired' ||
        status == 'failed') {
      return false;
    }

    if (status == 'holding') {
      final holdExpiry = _dt(row['hold_expires_at']);
      if (holdExpiry != null && DateTime.now().isAfter(holdExpiry)) {
        return false;
      }
    }

    return true;
  }

  Future<List<Map<String, dynamic>>> fetchConflictingBookings({
    required String vehicleId,
    required DateTime start,
    required DateTime end,
  }) async {
    if (vehicleId.trim().isEmpty || !end.isAfter(start)) return const [];

    final rows = await _supa
        .from('booking')
        .select('booking_id, booking_status, rental_start, rental_end, hold_expires_at')
        .eq('vehicle_id', vehicleId)
        .lt('rental_start', end.toIso8601String())
        .gt('rental_end', start.toIso8601String());

    if (rows is! List) return const [];

    return rows
        .map((e) => Map<String, dynamic>.from(e as Map))
        .where(_isBlockingStatus)
        .toList();
  }

  Future<bool> isVehicleAvailable({
    required String vehicleId,
    required DateTime start,
    required DateTime end,
  }) async {
    final conflicts = await fetchConflictingBookings(
      vehicleId: vehicleId,
      start: start,
      end: end,
    );
    return conflicts.isEmpty;
  }
}
