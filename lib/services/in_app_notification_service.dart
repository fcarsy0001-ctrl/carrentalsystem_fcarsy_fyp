import 'package:supabase_flutter/supabase_flutter.dart';

class InAppNotificationService {
  InAppNotificationService(this._supa);

  final SupabaseClient _supa;

  static const String tableName = 'notification';

  String _shortId(String prefix) {
    final ms = DateTime.now().millisecondsSinceEpoch.toString();
    return prefix + ms.substring(ms.length - 8);
  }

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

  Future<String?> currentUserId() async {
    final authUser = _supa.auth.currentUser;
    if (authUser == null) return null;
    final row = await _supa
        .from('app_user')
        .select('user_id')
        .eq('auth_uid', authUser.id)
        .maybeSingle();
    final userId = (row?['user_id'] ?? '').toString().trim();
    return userId.isEmpty ? null : userId;
  }

  Future<void> createNotification({
    required String userId,
    required String title,
    required String message,
    String type = 'general',
    String? bookingId,
    String? extraChargeId,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await _supa.from(tableName).insert({
      'notification_id': _shortId('NT'),
      'user_id': userId,
      'booking_id': bookingId,
      'extra_charge_id': extraChargeId,
      'notification_type': type,
      'title': title,
      'message': message,
      'is_read': false,
      'created_at': now,
    });
  }


  Future<bool> createNotificationOnce({
    required String userId,
    required String title,
    required String message,
    String type = 'general',
    String? bookingId,
    String? extraChargeId,
  }) async {
    final existing = await _supa
        .from(tableName)
        .select('notification_id')
        .eq('user_id', userId)
        .eq('notification_type', type)
        .eq('title', title)
        .eq('message', message)
        .maybeSingle();

    if (existing != null) {
      return false;
    }

    await createNotification(
      userId: userId,
      title: title,
      message: message,
      type: type,
      bookingId: bookingId,
      extraChargeId: extraChargeId,
    );

    return true;
  }

  Future<int> unreadCountForCurrentUser() async {
    final userId = await currentUserId();
    if (userId == null) return 0;
    final rows = await _supa
        .from(tableName)
        .select('notification_id')
        .eq('user_id', userId)
        .eq('is_read', false);
    return (rows as List).length;
  }

  Stream<List<Map<String, dynamic>>> watchCurrentUserNotifications() async* {
    final userId = await currentUserId();
    if (userId == null) {
      yield const <Map<String, dynamic>>[];
      return;
    }

    yield* _supa
        .from(tableName)
        .stream(primaryKey: ['notification_id'])
        .eq('user_id', userId)
        .map((rows) {
      final list = rows.map((e) => Map<String, dynamic>.from(e)).toList();
      list.sort((a, b) {
        final ad = _dt(a['created_at']);
        final bd = _dt(b['created_at']);
        if (ad == null && bd == null) return 0;
        if (ad == null) return 1;
        if (bd == null) return -1;
        return bd.compareTo(ad);
      });
      return list;
    });
  }

  Future<void> markAsRead(String notificationId) async {
    final id = notificationId.trim();
    if (id.isEmpty) return;
    await _supa.from(tableName).update({
      'is_read': true,
      'read_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('notification_id', id);
  }

  Future<void> markAllAsReadForCurrentUser() async {
    final userId = await currentUserId();
    if (userId == null) return;
    await _supa.from(tableName).update({
      'is_read': true,
      'read_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('user_id', userId).eq('is_read', false);
  }
}
