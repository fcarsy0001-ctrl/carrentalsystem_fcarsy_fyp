import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_user_service.dart';

class InAppNotificationService {
  InAppNotificationService(this._client);

  final SupabaseClient _client;

  String _s(dynamic value) => value == null ? '' : value.toString().trim();

  Future<String?> _currentUserId() async {
    await AppUserService(_client).ensureAppUser().catchError((_) {});

    final auth = _client.auth.currentUser;
    if (auth == null) return null;

    final row = await _client
        .from('app_user')
        .select('user_id')
        .eq('auth_uid', auth.id)
        .maybeSingle();

    if (row == null) return null;
    return _s((row as Map)['user_id']).isEmpty ? null : _s(row['user_id']);
  }

  String _newNotificationId() {
    final now = DateTime.now().millisecondsSinceEpoch;
    return 'NOT$now';
  }

  Future<int> unreadCountForCurrentUser() async {
    final userId = await _currentUserId();
    if (userId == null) return 0;

    final rows = await _client
        .from('notification')
        .select('notification_id')
        .eq('user_id', userId)
        .eq('read_status', 'Unread');

    return rows is List ? rows.length : 0;
  }

  Future<List<Map<String, dynamic>>> getMyNotifications() async {
    final userId = await _currentUserId();
    if (userId == null) return const <Map<String, dynamic>>[];

    final rows = await _client
        .from('notification')
        .select('*')
        .eq('user_id', userId)
        .order('created_at', ascending: false);

    if (rows is! List) return const <Map<String, dynamic>>[];
    return rows.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<void> markRead(String notificationId) async {
    final id = notificationId.trim();
    if (id.isEmpty) return;
    await _client
        .from('notification')
        .update(<String, dynamic>{'read_status': 'Read'})
        .eq('notification_id', id);
  }

  Future<void> markAllReadForCurrentUser() async {
    final userId = await _currentUserId();
    if (userId == null) return;

    await _client
        .from('notification')
        .update(<String, dynamic>{'read_status': 'Read'})
        .eq('user_id', userId)
        .eq('read_status', 'Unread');
  }

  Future<void> createNotification({
    required String userId,
    String? bookingId,
    String? extraChargeId,
    required String type,
    String? title,
    required String message,
  }) async {
    final cleanUserId = userId.trim();
    if (cleanUserId.isEmpty) {
      throw Exception('Missing notification user id.');
    }

    final cleanTitle = _s(title);
    final cleanMessage = message.trim();
    if (cleanMessage.isEmpty) {
      throw Exception('Notification message cannot be empty.');
    }

    final payload = <String, dynamic>{
      'notification_id': _newNotificationId(),
      'user_id': cleanUserId,
      'booking_id': _s(bookingId).isEmpty ? null : _s(bookingId),
      'notification_type': type.trim().isEmpty ? 'general' : type.trim(),
      'notification_message':
      cleanTitle.isEmpty ? cleanMessage : '$cleanTitle\n$cleanMessage',
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'read_status': 'Unread',
    };

    try {
      await _client.from('notification').insert(payload);
    } on PostgrestException {
      final fallback = <String, dynamic>{
        'notification_id': payload['notification_id'],
        'user_id': cleanUserId,
        'booking_id': payload['booking_id'],
        'notification_type': payload['notification_type'],
        'notification_message': payload['notification_message'],
      };
      await _client.from('notification').insert(fallback);
    }
  }

  Future<bool> notificationExists({
    required String userId,
    required String type,
    required String message,
  }) async {
    final cleanUserId = userId.trim();
    final cleanType = type.trim().isEmpty ? 'general' : type.trim();
    final cleanMessage = message.trim();
    if (cleanUserId.isEmpty || cleanMessage.isEmpty) return false;

    final rows = await _client
        .from('notification')
        .select('notification_id')
        .eq('user_id', cleanUserId)
        .eq('notification_type', cleanType)
        .eq('notification_message', cleanMessage)
        .limit(1);

    return rows is List && rows.isNotEmpty;
  }

  Future<void> createNotificationOnce({
    required String userId,
    String? bookingId,
    required String type,
    String? title,
    required String message,
  }) async {
    final cleanTitle = _s(title);
    final cleanMessage = message.trim();
    final storedMessage =
    cleanTitle.isEmpty ? cleanMessage : '$cleanTitle\n$cleanMessage';

    final exists = await notificationExists(
      userId: userId,
      type: type,
      message: storedMessage,
    );
    if (exists) return;

    await createNotification(
      userId: userId,
      bookingId: bookingId,
      type: type,
      title: title,
      message: message,
    );
  }
}
