import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_access_service.dart';
import 'app_user_service.dart';

class SupportTicketService {
  SupportTicketService(this._client);

  final SupabaseClient _client;

  static const String statusOpen = 'Open';
  static const String statusClosed = 'Closed';

  static const List<String> ticketTypes = <String>[
    'Account Inquiry',
    'Booking Issue',
    'Payment Issue',
    'Vehicle Problem',
    'Refund Request',
    'Voucher Issue',
    'Pickup / Drop-off Issue',
    'Technical Issue',
    'Other',
  ];

  String _s(dynamic value) => value == null ? '' : value.toString().trim();

  DateTime _dt(dynamic value) {
    if (value is DateTime) return value;
    return DateTime.tryParse(_s(value)) ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  Future<Map<String, dynamic>> _requireCurrentAppUser() async {
    await AppUserService(_client).ensureAppUser().catchError((_) {});

    final auth = _client.auth.currentUser;
    if (auth == null) throw Exception('Please login again.');

    final rows = await _client
        .from('app_user')
        .select('user_id,user_name,user_email,auth_uid')
        .eq('auth_uid', auth.id)
        .limit(1);

    if (rows is! List || rows.isEmpty) {
      throw Exception('User profile not found.');
    }

    return Map<String, dynamic>.from(rows.first as Map);
  }

  Future<Map<String, dynamic>> _getCurrentActor() async {
    final auth = _client.auth.currentUser;
    if (auth == null) throw Exception('Please login again.');

    final ctx = await AdminAccessService(_client).getAdminContext();
    if (ctx.isStaffAdmin) {
      final rows = await _client
          .from('staff_admin')
          .select('sadmin_id,sadmin_name,sadmin_email')
          .eq('auth_uid', auth.id)
          .limit(1);
      final row = rows is List && rows.isNotEmpty
          ? Map<String, dynamic>.from(rows.first as Map)
          : <String, dynamic>{};
      final email = _s(row['sadmin_email']).isEmpty ? (auth.email ?? '') : _s(row['sadmin_email']);
      final name = _s(row['sadmin_name']).isEmpty
          ? (email.isEmpty ? 'Staff' : email.split('@').first)
          : _s(row['sadmin_name']);
      return <String, dynamic>{
        'auth_uid': auth.id,
        'sender_role': 'Staff',
        'sender_name': name,
        'sender_email': email,
        'actor_id': _s(row['sadmin_id']),
      };
    }

    if (ctx.isAdmin) {
      List rows = const [];
      try {
        final result = await _client
            .from('admin')
            .select('admin_id,admin_name,admin_email')
            .eq('auth_uid', auth.id)
            .limit(1);
        if (result is List) rows = result;
      } catch (_) {}

      if (rows.isEmpty && (auth.email ?? '').trim().isNotEmpty) {
        try {
          final result = await _client
              .from('admin')
              .select('admin_id,admin_name,admin_email')
              .eq('admin_email', (auth.email ?? '').trim())
              .limit(1);
          if (result is List) rows = result;
        } catch (_) {}
      }

      final row = rows.isNotEmpty
          ? Map<String, dynamic>.from(rows.first as Map)
          : <String, dynamic>{};
      final email = _s(row['admin_email']).isEmpty ? (auth.email ?? '') : _s(row['admin_email']);
      final name = _s(row['admin_name']).isEmpty
          ? (email.isEmpty ? 'Admin' : email.split('@').first)
          : _s(row['admin_name']);
      return <String, dynamic>{
        'auth_uid': auth.id,
        'sender_role': 'Admin',
        'sender_name': name,
        'sender_email': email,
        'actor_id': _s(row['admin_id']),
      };
    }

    final user = await _requireCurrentAppUser();
    return <String, dynamic>{
      'auth_uid': auth.id,
      'sender_role': 'User',
      'sender_name': _s(user['user_name']).isEmpty ? 'User' : _s(user['user_name']),
      'sender_email': _s(user['user_email']),
      'actor_id': _s(user['user_id']),
      'user_id': _s(user['user_id']),
    };
  }

  String _newTicketId() {
    final now = DateTime.now().millisecondsSinceEpoch;
    return 'TIC-${now.toString()}';
  }

  String _preview(String text) {
    final clean = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (clean.length <= 80) return clean;
    return '${clean.substring(0, 80)}...';
  }

  static const String _reviewMarkerPrefix = '[STAFF_REVIEW:';
  static const String _reviewDismissedMarker = '[STAFF_REVIEW_DISMISSED]';

  bool _isHiddenSupportMetaMessage(Map<String, dynamic> row) {
    final message = _s(row['message']);
    return message.startsWith(_reviewMarkerPrefix) || message == _reviewDismissedMarker;
  }

  int? _extractReviewMarkerRating(dynamic value) {
    final raw = _s(value);
    if (!raw.startsWith(_reviewMarkerPrefix) || !raw.endsWith(']')) return null;
    final number = raw.substring(_reviewMarkerPrefix.length, raw.length - 1);
    return _parseRating(number);
  }

  Future<void> _insertHiddenUserMetaMessage({
    required String ticketId,
    required String message,
  }) async {
    final actor = await _getCurrentActor();
    final now = DateTime.now().toUtc().toIso8601String();
    await _client.from('support_message').insert(<String, dynamic>{
      'ticket_id': ticketId,
      'sender_auth_uid': _s(actor['auth_uid']),
      'sender_role': 'User',
      'sender_name': _s(actor['sender_name']).isEmpty ? 'User' : _s(actor['sender_name']),
      'message': message,
      'created_at': now,
    });
  }

  int? _parseRating(dynamic value) {
    if (value == null) return null;
    if (value is num) {
      final n = value.toInt();
      return (n >= 1 && n <= 5) ? n : null;
    }
    final n = int.tryParse(_s(value));
    if (n == null || n < 1 || n > 5) return null;
    return n;
  }

  bool _ticketHasStaffServed(Map<String, dynamic> ticket) {
    return _s(ticket['assigned_admin_uid']).isNotEmpty ||
        _s(ticket['assigned_admin_name']).isNotEmpty ||
        _s(ticket['assigned_admin_role']).isNotEmpty;
  }

  Future<bool> hasStaffServed(String ticketId) async {
    final ticket = await getTicket(ticketId);
    if (_ticketHasStaffServed(ticket)) return true;

    try {
      final rows = await _client
          .from('support_message')
          .select('message_id')
          .eq('ticket_id', ticketId)
          .neq('sender_role', 'User')
          .limit(1);
      return rows is List && rows.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<int?> getTicketReview(String ticketId) async {
    final ticket = await getTicket(ticketId);
    final directRating = _parseRating(ticket['staff_rating']);
    if (directRating != null) return directRating;

    try {
      final row = await _client
          .from('support_ticket_review')
          .select('rating')
          .eq('ticket_id', ticketId)
          .maybeSingle();
      if (row != null) {
        final stored = _parseRating((row as Map)['rating']);
        if (stored != null) return stored;
      }
    } catch (_) {}

    try {
      final rows = await _client
          .from('support_message')
          .select('message')
          .eq('ticket_id', ticketId)
          .order('created_at', ascending: false);
      if (rows is! List) return null;
      for (final raw in rows) {
        final row = Map<String, dynamic>.from(raw as Map);
        final rating = _extractReviewMarkerRating(row['message']);
        if (rating != null) return rating;
      }
    } catch (_) {}
    return null;
  }

  Future<bool> isTicketReviewDismissed(String ticketId) async {
    try {
      final rows = await _client
          .from('support_message')
          .select('message')
          .eq('ticket_id', ticketId)
          .order('created_at', ascending: false);
      if (rows is! List) return false;
      for (final raw in rows) {
        final row = Map<String, dynamic>.from(raw as Map);
        final message = _s(row['message']);
        if (_extractReviewMarkerRating(message) != null) return false;
        if (message == _reviewDismissedMarker) return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>?> getOpenTicketForCurrentUser() async {
    final user = await _requireCurrentAppUser();
    final rows = await _client
        .from('support_ticket')
        .select('*')
        .eq('user_id', _s(user['user_id']))
        .eq('ticket_status', statusOpen)
        .order('created_at', ascending: false)
        .limit(1);

    if (rows is! List || rows.isEmpty) return null;
    return Map<String, dynamic>.from(rows.first as Map);
  }

  Future<bool> hasOpenTicketForCurrentUser() async {
    return (await getOpenTicketForCurrentUser()) != null;
  }

  Future<int> countOpenInboxTickets() async {
    final rows = await _client
        .from('support_ticket')
        .select('ticket_id')
        .eq('ticket_status', statusOpen);
    return rows is List ? rows.length : 0;
  }

  Future<List<Map<String, dynamic>>> getMyTickets() async {
    final user = await _requireCurrentAppUser();
    final rows = await _client
        .from('support_ticket')
        .select('*')
        .eq('user_id', _s(user['user_id']))
        .order('last_message_at', ascending: false);

    if (rows is! List) return const [];
    return rows.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<List<Map<String, dynamic>>> getInboxTickets() async {
    final rows = await _client
        .from('support_ticket')
        .select('*')
        .order('last_message_at', ascending: false);

    if (rows is! List) return const [];
    final list = rows.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    list.sort((a, b) {
      final sa = _s(a['ticket_status']) == statusOpen ? 0 : 1;
      final sb = _s(b['ticket_status']) == statusOpen ? 0 : 1;
      if (sa != sb) return sa.compareTo(sb);
      return _dt(b['last_message_at']).compareTo(_dt(a['last_message_at']));
    });
    return list;
  }

  Future<Map<String, dynamic>> getTicket(String ticketId) async {
    final rows = await _client
        .from('support_ticket')
        .select('*')
        .eq('ticket_id', ticketId)
        .limit(1);

    if (rows is! List || rows.isEmpty) {
      throw Exception('Support ticket not found.');
    }

    final ticket = Map<String, dynamic>.from(rows.first as Map);
    final actor = await _getCurrentActor();
    if (_s(actor['sender_role']) == 'User' && _s(ticket['user_id']) != _s(actor['user_id'])) {
      throw Exception('You cannot open this ticket.');
    }
    return ticket;
  }

  Stream<Map<String, dynamic>?> watchTicket(String ticketId) {
    return _client
        .from('support_ticket')
        .stream(primaryKey: const ['ticket_id'])
        .eq('ticket_id', ticketId)
        .map((rows) {
      if (rows.isEmpty) return null;
      return Map<String, dynamic>.from(rows.first);
    });
  }

  Stream<List<Map<String, dynamic>>> watchMessages(String ticketId) {
    return _client
        .from('support_message')
        .stream(primaryKey: const ['message_id'])
        .eq('ticket_id', ticketId)
        .order('created_at', ascending: true)
        .map((rows) => rows
            .map((e) => Map<String, dynamic>.from(e))
            .where((row) => !_isHiddenSupportMetaMessage(row))
            .toList()
          ..sort((a, b) => _dt(a['created_at']).compareTo(_dt(b['created_at']))));
  }

  Future<List<Map<String, dynamic>>> getMessages(String ticketId) async {
    final rows = await _client
        .from('support_message')
        .select('*')
        .eq('ticket_id', ticketId)
        .order('created_at', ascending: true);

    if (rows is! List) return const [];
    return rows
        .map((e) => Map<String, dynamic>.from(e as Map))
        .where((row) => !_isHiddenSupportMetaMessage(row))
        .toList();
  }

  Future<Map<String, dynamic>> createTicket({
    required String title,
    required String ticketType,
    required String message,
  }) async {
    final user = await _requireCurrentAppUser();

    final existing = await getOpenTicketForCurrentUser();
    if (existing != null) {
      throw Exception('You already have an open support ticket. Please wait for admin/staff to close it first.');
    }

    final cleanTitle = title.trim();
    final cleanType = ticketType.trim();
    final cleanMessage = message.trim();
    if (cleanTitle.isEmpty) throw Exception('Title is required.');
    if (cleanType.isEmpty) throw Exception('Ticket type is required.');
    if (cleanMessage.isEmpty) throw Exception('Message is required.');

    final actor = await _getCurrentActor();
    final ticketId = _newTicketId();
    final now = DateTime.now().toUtc().toIso8601String();

    final ticketPayload = <String, dynamic>{
      'ticket_id': ticketId,
      'user_id': _s(user['user_id']),
      'user_name': _s(user['user_name']),
      'user_email': _s(user['user_email']),
      'title': cleanTitle,
      'ticket_type': cleanType,
      'ticket_status': statusOpen,
      'created_by_auth_uid': _client.auth.currentUser?.id,
      'created_at': now,
      'last_message_at': now,
      'last_message_preview': _preview(cleanMessage),
    };

    await _client.from('support_ticket').insert(ticketPayload);

    try {
      await _client.from('support_message').insert(<String, dynamic>{
        'ticket_id': ticketId,
        'sender_auth_uid': _s(actor['auth_uid']),
        'sender_role': _s(actor['sender_role']),
        'sender_name': _s(actor['sender_name']),
        'message': cleanMessage,
        'created_at': now,
      });
    } catch (e) {
      try {
        await _client.from('support_ticket').delete().eq('ticket_id', ticketId);
      } catch (_) {}
      rethrow;
    }

    return getTicket(ticketId);
  }

  Future<void> sendMessage({
    required String ticketId,
    required String message,
  }) async {
    final cleanMessage = message.trim();
    if (cleanMessage.isEmpty) return;

    final ticket = await getTicket(ticketId);
    if (_s(ticket['ticket_status']) == statusClosed) {
      throw Exception('This ticket has already been closed.');
    }

    final actor = await _getCurrentActor();
    final now = DateTime.now().toUtc().toIso8601String();

    await _client.from('support_message').insert(<String, dynamic>{
      'ticket_id': ticketId,
      'sender_auth_uid': _s(actor['auth_uid']),
      'sender_role': _s(actor['sender_role']),
      'sender_name': _s(actor['sender_name']),
      'message': cleanMessage,
      'created_at': now,
    });

    final update = <String, dynamic>{
      'last_message_at': now,
      'last_message_preview': _preview(cleanMessage),
    };

    if (_s(actor['sender_role']) != 'User') {
      update['assigned_admin_uid'] = _s(actor['auth_uid']);
      update['assigned_admin_name'] = _s(actor['sender_name']);
      update['assigned_admin_role'] = _s(actor['sender_role']);
      if (_s(actor['sender_role']).toLowerCase() == 'staff') {
        update['handled_by_staff_id'] = _s(actor['actor_id']);
        update['handled_by_staff_name'] = _s(actor['sender_name']);
      }
    }

    try {
      await _client.from('support_ticket').update(update).eq('ticket_id', ticketId);
    } catch (_) {
      final fallbackUpdate = Map<String, dynamic>.from(update)
        ..remove('handled_by_staff_id')
        ..remove('handled_by_staff_name');
      await _client.from('support_ticket').update(fallbackUpdate).eq('ticket_id', ticketId);
    }
  }

  Future<void> closeTicket(String ticketId) async {
    final actor = await _getCurrentActor();
    final ticket = await getTicket(ticketId);
    if (_s(ticket['ticket_status']) == statusClosed) return;

    final now = DateTime.now().toUtc().toIso8601String();
    final update = <String, dynamic>{
      'ticket_status': statusClosed,
      'closed_at': now,
      'last_message_at': now,
    };

    if (_s(actor['sender_role']) != 'User') {
      update['assigned_admin_uid'] = _s(actor['auth_uid']);
      update['assigned_admin_name'] = _s(actor['sender_name']);
      update['assigned_admin_role'] = _s(actor['sender_role']);
      if (_s(actor['sender_role']).toLowerCase() == 'staff') {
        update['handled_by_staff_id'] = _s(actor['actor_id']);
        update['handled_by_staff_name'] = _s(actor['sender_name']);
      }
    }

    try {
      await _client.from('support_ticket').update(update).eq('ticket_id', ticketId);
    } catch (_) {
      final fallbackUpdate = Map<String, dynamic>.from(update)
        ..remove('handled_by_staff_id')
        ..remove('handled_by_staff_name');
      await _client.from('support_ticket').update(fallbackUpdate).eq('ticket_id', ticketId);
    }
  }

  Future<void> submitTicketReview({
    required String ticketId,
    required int stars,
  }) async {
    final actor = await _getCurrentActor();
    if (_s(actor['sender_role']) != 'User') {
      throw Exception('Only user can submit staff review.');
    }

    final ticket = await getTicket(ticketId);
    if (_s(ticket['ticket_status']) != statusClosed) {
      throw Exception('You can review only after the case is closed.');
    }

    if (!await hasStaffServed(ticketId)) {
      throw Exception('No staff has served this case yet.');
    }

    final existing = await getTicketReview(ticketId);
    if (existing != null) return;

    final rating = stars.clamp(1, 5).toInt();
    final now = DateTime.now().toUtc().toIso8601String();

    try {
      await _client.from('support_ticket').update(<String, dynamic>{
        'staff_rating': rating,
        'staff_rated_at': now,
      }).eq('ticket_id', ticketId);
      return;
    } catch (_) {}

    final staffId = _s(ticket['handled_by_staff_id']).isNotEmpty
        ? _s(ticket['handled_by_staff_id'])
        : (_s(ticket['assigned_admin_role']).toLowerCase() == 'staff'
            ? _s(ticket['assigned_admin_uid'])
            : '');

    try {
      await _client.from('support_ticket_review').upsert(<String, dynamic>{
        'ticket_id': ticketId,
        'user_id': _s(ticket['user_id']),
        'staff_id': staffId,
        'rating': rating,
        'created_at': now,
      }, onConflict: 'ticket_id');
      return;
    } catch (_) {}

    try {
      await _client.from('support_ticket_review').upsert(<String, dynamic>{
        'ticket_id': ticketId,
        'user_id': _s(ticket['user_id']),
        'staff_auth_uid': _s(ticket['assigned_admin_uid']),
        'staff_name': _s(ticket['assigned_admin_name']),
        'staff_role': _s(ticket['assigned_admin_role']),
        'rating': rating,
        'created_at': now,
        'updated_at': now,
      }, onConflict: 'ticket_id');
      return;
    } catch (_) {}

    await _insertHiddenUserMetaMessage(
      ticketId: ticketId,
      message: '$_reviewMarkerPrefix$rating]',
    );
  }

  Future<void> dismissTicketReview(String ticketId) async {
    final actor = await _getCurrentActor();
    if (_s(actor['sender_role']) != 'User') {
      throw Exception('Only user can dismiss staff review.');
    }

    final ticket = await getTicket(ticketId);
    if (_s(ticket['ticket_status']) != statusClosed) {
      throw Exception('You can close the review only after the case is closed.');
    }

    if (!await hasStaffServed(ticketId)) {
      throw Exception('No staff has served this case yet.');
    }

    final existing = await getTicketReview(ticketId);
    if (existing != null) return;
    if (await isTicketReviewDismissed(ticketId)) return;

    await _insertHiddenUserMetaMessage(
      ticketId: ticketId,
      message: _reviewDismissedMarker,
    );
  }

  Future<void> deleteTicket(String ticketId) async {
    final actor = await _getCurrentActor();
    if (_s(actor['sender_role']) == 'User') {
      throw Exception('Only admin/staff can delete tickets.');
    }

    await _client.from('support_message').delete().eq('ticket_id', ticketId);
    await _client.from('support_ticket').delete().eq('ticket_id', ticketId);
  }

  Future<String> exportTicketChat(String ticketId) async {
    final ticket = await getTicket(ticketId);
    final messages = await getMessages(ticketId);

    final buffer = StringBuffer()
      ..writeln('Car Rental System Support Ticket Export')
      ..writeln('Ticket ID: ${_s(ticket['ticket_id'])}')
      ..writeln('Title: ${_s(ticket['title'])}')
      ..writeln('Type: ${_s(ticket['ticket_type'])}')
      ..writeln('Status: ${_s(ticket['ticket_status'])}')
      ..writeln('User ID: ${_s(ticket['user_id'])}')
      ..writeln('User Name: ${_s(ticket['user_name'])}')
      ..writeln('User Email: ${_s(ticket['user_email'])}')
      ..writeln('Assigned To: ${_s(ticket['assigned_admin_name'])}${_s(ticket['assigned_admin_role']).isEmpty ? '' : ' (${_s(ticket['assigned_admin_role'])})'}')
      ..writeln('Created At: ${_s(ticket['created_at'])}')
      ..writeln('Closed At: ${_s(ticket['closed_at'])}')
      ..writeln('')
      ..writeln('Chat History')
      ..writeln('----------------------------------------');

    for (final msg in messages) {
      buffer
        ..writeln('[${_s(msg['created_at'])}] ${_s(msg['sender_role'])} - ${_s(msg['sender_name'])}')
        ..writeln(_s(msg['message']))
        ..writeln('');
    }

    final dir = await Directory.systemTemp.createTemp('support_ticket_export_');
    final file = File('${dir.path}${Platform.pathSeparator}${_s(ticket['ticket_id'])}.txt');
    await file.writeAsString(buffer.toString());
    return file.path;
  }
}
