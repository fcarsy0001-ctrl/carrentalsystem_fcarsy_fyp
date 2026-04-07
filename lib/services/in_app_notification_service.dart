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

    try {
      final row = await _supa
          .from('app_user')
          .select('user_id')
          .eq('auth_uid', authUser.id)
          .limit(1)
          .maybeSingle();
      final userId = (row?['user_id'] ?? '').toString().trim();
      if (userId.isNotEmpty) return userId;
    } catch (_) {}

    final email = (authUser.email ?? '').trim().toLowerCase();
    if (email.isEmpty) return null;

    try {
      final row = await _supa
          .from('app_user')
          .select('user_id')
          .eq('user_email', email)
          .limit(1)
          .maybeSingle();
      final userId = (row?['user_id'] ?? '').toString().trim();
      return userId.isEmpty ? null : userId;
    } catch (_) {
      return null;
    }
  }

  bool isReadRow(Map<String, dynamic> row) {
    final direct = row['is_read'];
    if (direct is bool) return direct;
    final directText = (direct ?? '').toString().trim().toLowerCase();
    if (directText == 'true' || directText == '1' || directText == 'read') {
      return true;
    }

    final legacy = (row['read_status'] ?? '').toString().trim().toLowerCase();
    return legacy == 'read' || legacy == 'true' || legacy == '1';
  }

  String titleFor(Map<String, dynamic> row) {
    final direct = (row['title'] ?? row['notification_title'] ?? '').toString().trim();
    if (direct.isNotEmpty) return direct;

    final type = (row['notification_type'] ?? '').toString().trim().toLowerCase();
    switch (type) {
      case 'road_tax_expired':
        return 'Road Tax Expired';
      case 'road_tax_expiring':
      case 'road_tax_expiring_urgent':
        return 'Road Tax Expiring Soon';
      case 'road_tax_below_threshold':
        return 'Road Tax Renewal Needed';
      default:
        if (type.isEmpty) return 'Notification';
        return type
            .split('_')
            .where((part) => part.trim().isNotEmpty)
            .map((part) => part[0].toUpperCase() + part.substring(1))
            .join(' ');
    }
  }

  String messageFor(Map<String, dynamic> row) {
    final message = (row['message'] ?? row['notification_message'] ?? '').toString().trim();
    return message.isEmpty ? 'No message.' : message;
  }

  Future<List<Map<String, dynamic>>> _selectUserRows(String userId) async {
    try {
      final rows = await _supa
          .from(tableName)
          .select('notification_id,user_id,title,message,is_read,created_at,booking_id,extra_charge_id,notification_type,read_at,read_status,notification_message')
          .eq('user_id', userId);
      if (rows is List) {
        return rows.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (_) {}

    try {
      final rows = await _supa.from(tableName).select().eq('user_id', userId);
      if (rows is List) {
        return rows.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (_) {}

    return const [];
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
    final cleanType = type.trim().isEmpty ? 'general' : type.trim();
    final cleanBookingId = (bookingId ?? '').trim();
    final cleanExtraChargeId = (extraChargeId ?? '').trim();
    final notificationId = _shortId('NT');

    final payload = <String, dynamic>{
      'notification_id': notificationId,
      'user_id': userId,
      'notification_type': cleanType,
      'title': title,
      'message': message,
      'is_read': false,
      'created_at': now,
    };
    if (cleanBookingId.isNotEmpty) payload['booking_id'] = cleanBookingId;
    if (cleanExtraChargeId.isNotEmpty) payload['extra_charge_id'] = cleanExtraChargeId;

    try {
      await _supa.from(tableName).insert(payload);
      return;
    } catch (_) {}

    final messageOnlyPayload = <String, dynamic>{
      'notification_id': notificationId,
      'user_id': userId,
      'notification_type': cleanType,
      'message': message,
      'is_read': false,
      'created_at': now,
    };
    if (cleanBookingId.isNotEmpty) messageOnlyPayload['booking_id'] = cleanBookingId;
    if (cleanExtraChargeId.isNotEmpty) messageOnlyPayload['extra_charge_id'] = cleanExtraChargeId;

    try {
      await _supa.from(tableName).insert(messageOnlyPayload);
      return;
    } catch (_) {}

    final legacyPayload = <String, dynamic>{
      'notification_id': notificationId,
      'user_id': userId,
      'notification_type': cleanType,
      'notification_message': message,
      'read_status': 'Unread',
      'created_at': now,
    };
    if (cleanBookingId.isNotEmpty) legacyPayload['booking_id'] = cleanBookingId;
    if (cleanExtraChargeId.isNotEmpty) legacyPayload['extra_charge_id'] = cleanExtraChargeId;

    await _supa.from(tableName).insert(legacyPayload);
  }

  Future<bool> createNotificationOnce({
    required String userId,
    required String title,
    required String message,
    String type = 'general',
    String? bookingId,
    String? extraChargeId,
  }) async {
    final cleanType = type.trim().isEmpty ? 'general' : type.trim();

    try {
      final existing = await _supa
          .from(tableName)
          .select('notification_id')
          .eq('user_id', userId)
          .eq('notification_type', cleanType)
          .eq('title', title)
          .eq('message', message)
          .maybeSingle();
      if (existing != null) return false;
    } catch (_) {}

    try {
      final existing = await _supa
          .from(tableName)
          .select('notification_id')
          .eq('user_id', userId)
          .eq('notification_type', cleanType)
          .eq('message', message)
          .maybeSingle();
      if (existing != null) return false;
    } catch (_) {}

    try {
      final existing = await _supa
          .from(tableName)
          .select('notification_id')
          .eq('user_id', userId)
          .eq('notification_type', cleanType)
          .eq('notification_message', message)
          .maybeSingle();
      if (existing != null) return false;
    } catch (_) {}

    await createNotification(
      userId: userId,
      title: title,
      message: message,
      type: cleanType,
      bookingId: bookingId,
      extraChargeId: extraChargeId,
    );

    return true;
  }

  Future<int> unreadCountForCurrentUser() async {
    final userId = await currentUserId();
    if (userId == null) return 0;
    final rows = await _selectUserRows(userId);
    return rows.where((row) => !isReadRow(row)).length;
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

    try {
      await _supa.from(tableName).update({
        'is_read': true,
        'read_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('notification_id', id);
      return;
    } catch (_) {}

    try {
      await _supa.from(tableName).update({
        'read_status': 'Read',
      }).eq('notification_id', id);
      return;
    } catch (_) {}

    await _supa.from(tableName).update({
      'is_read': true,
    }).eq('notification_id', id);
  }

  Future<void> markAllAsReadForCurrentUser() async {
    final userId = await currentUserId();
    if (userId == null) return;

    try {
      await _supa.from(tableName).update({
        'is_read': true,
        'read_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('user_id', userId).eq('is_read', false);
      return;
    } catch (_) {}

    try {
      await _supa.from(tableName).update({
        'read_status': 'Read',
      }).eq('user_id', userId).eq('read_status', 'Unread');
      return;
    } catch (_) {}

    await _supa.from(tableName).update({
      'is_read': true,
    }).eq('user_id', userId);
  }
}
