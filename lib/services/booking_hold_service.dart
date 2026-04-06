import 'package:supabase_flutter/supabase_flutter.dart';

class BookingHoldService {
  BookingHoldService(this._supa);

  final SupabaseClient _supa;

  DateTime? _dt(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value.isUtc ? value.toLocal() : value;
    try {
      final parsed = DateTime.parse(value.toString());
      return parsed.isUtc ? parsed.toLocal() : parsed;
    } catch (_) {
      return null;
    }
  }

  Future<void> _updateBookingAsCancelled({
    required String bookingId,
    String? holdExpiresAtUtc,
  }) async {
    final cancelledPatch = <String, dynamic>{
      'booking_status': 'Cancelled',
      if (holdExpiresAtUtc != null) 'hold_expires_at': holdExpiresAtUtc,
    };

    try {
      await _supa.from('booking').update(cancelledPatch).eq('booking_id', bookingId);
    } on PostgrestException catch (e) {
      final msg = e.message.toLowerCase();
      final blockedByNotificationTrigger =
          e.code == '42501' && msg.contains('notification');
      if (!blockedByNotificationTrigger) rethrow;

      await _supa.from('booking').update({
        'booking_status': 'Cancel',
        if (holdExpiresAtUtc != null) 'hold_expires_at': holdExpiresAtUtc,
      }).eq('booking_id', bookingId);
    }
  }

  String normalizeStatus(dynamic status) {
    final s = (status ?? '').toString().trim().toLowerCase();
    if (s == 'cancel' || s == 'cancelled' || s == 'canceled') return 'cancelled';
    if (s == 'deactive' || s == 'deactivated') return 'deactive';
    if (s == 'holding') return 'holding';
    if (s == 'paid') return 'paid';
    if (s == 'active') return 'active';
    if (s == 'inactive') return 'inactive';
    return s;
  }

  DateTime? parseHoldExpiryFromRow(Map<String, dynamic> row) => _dt(row['hold_expires_at']);

  bool isActiveHoldRow(Map<String, dynamic> row, {DateTime? now}) {
    if (normalizeStatus(row['booking_status']) != 'holding') return false;
    final expiry = parseHoldExpiryFromRow(row);
    if (expiry == null) return false;
    return expiry.isAfter(now ?? DateTime.now());
  }

  Duration? remainingForRow(Map<String, dynamic> row, {DateTime? now}) {
    final expiry = parseHoldExpiryFromRow(row);
    if (expiry == null) return null;
    final diff = expiry.difference(now ?? DateTime.now());
    return diff.isNegative ? Duration.zero : diff;
  }

  String formatRemaining(Duration duration) {
    final totalSeconds = duration.inSeconds < 0 ? 0 : duration.inSeconds;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  Future<Map<String, dynamic>?> fetchBookingMeta(String bookingId) async {
    if (bookingId.trim().isEmpty) return null;
    final row = await _supa
        .from('booking')
        .select('*')
        .eq('booking_id', bookingId)
        .maybeSingle();
    if (row == null) return null;
    return Map<String, dynamic>.from(row as Map);
  }

  Future<bool> expireIfNeeded({
    required String bookingId,
    DateTime? holdExpiry,
    Map<String, dynamic>? row,
  }) async {
    if (bookingId.trim().isEmpty) return false;
    final meta = row ?? await fetchBookingMeta(bookingId);
    if (meta == null) return false;

    final status = normalizeStatus(meta['booking_status']);
    if (status == 'cancelled') return true;
    if (status != 'holding') return false;

    final expiry = holdExpiry ?? parseHoldExpiryFromRow(meta);
    if (expiry != null && expiry.isAfter(DateTime.now())) return false;

    try {
      await _updateBookingAsCancelled(
        bookingId: bookingId,
        holdExpiresAtUtc: DateTime.now().toUtc().toIso8601String(),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> cancelHold(String bookingId) async {
    if (bookingId.trim().isEmpty) return false;
    final meta = await fetchBookingMeta(bookingId);
    if (meta == null) return false;

    final status = normalizeStatus(meta['booking_status']);
    if (status == 'cancelled') return true;
    if (status != 'holding') return false;

    try {
      await _updateBookingAsCancelled(
        bookingId: bookingId,
        holdExpiresAtUtc: DateTime.now().toUtc().toIso8601String(),
      );
      return true;
    } catch (_) {
      return false;
    }
  }
}
