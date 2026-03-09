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
    return rows.map((e) => Map<String, dynamic>.from(e as Map)).toList();
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
    }

    await _client.from('support_ticket').update(update).eq('ticket_id', ticketId);
  }

  Future<void> closeTicket(String ticketId) async {
    final actor = await _getCurrentActor();
    if (_s(actor['sender_role']) == 'User') {
      throw Exception('Only admin/staff can close tickets.');
    }

    final now = DateTime.now().toUtc().toIso8601String();
    await _client.from('support_ticket').update(<String, dynamic>{
      'ticket_status': statusClosed,
      'closed_at': now,
      'last_message_at': now,
      'assigned_admin_uid': _s(actor['auth_uid']),
      'assigned_admin_name': _s(actor['sender_name']),
      'assigned_admin_role': _s(actor['sender_role']),
    }).eq('ticket_id', ticketId);
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
