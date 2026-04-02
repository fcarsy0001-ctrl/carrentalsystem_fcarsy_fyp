import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/in_app_notification_service.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  SupabaseClient get _supa => Supabase.instance.client;

  late final InAppNotificationService _service;
  late Future<List<Map<String, dynamic>>> _future;
  bool _markingAllRead = false;

  @override
  void initState() {
    super.initState();
    _service = InAppNotificationService(_supa);
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() {
    return _service.getMyNotifications();
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _load();
    });
    await _future;
  }

  Future<void> _markAllRead() async {
    setState(() {
      _markingAllRead = true;
    });
    try {
      await _service.markAllReadForCurrentUser();
      if (!mounted) return;
      await _refresh();
    } finally {
      if (mounted) {
        setState(() {
          _markingAllRead = false;
        });
      }
    }
  }

  Future<void> _openNotification(Map<String, dynamic> row) async {
    final id = _s(row['notification_id']);
    if (id.isNotEmpty && _s(row['read_status']).toLowerCase() != 'read') {
      await _service.markRead(id).catchError((_) {});
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_titleFor(row)),
        content: Text(_messageFor(row)),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    await _refresh();
  }

  String _s(dynamic value) => value == null ? '' : value.toString().trim();

  DateTime? _dt(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value.isUtc ? value.toLocal() : value;
    final parsed = DateTime.tryParse(value.toString());
    if (parsed == null) return null;
    return parsed.isUtc ? parsed.toLocal() : parsed;
  }

  String _titleFor(Map<String, dynamic> row) {
    final type = _s(row['notification_type']);
    if (type.isNotEmpty) {
      return type
          .replaceAll('_', ' ')
          .split(' ')
          .where((part) => part.isNotEmpty)
          .map((part) => part[0].toUpperCase() + part.substring(1))
          .join(' ');
    }
    return 'Notification';
  }

  String _messageFor(Map<String, dynamic> row) {
    final raw = _s(row['notification_message']);
    return raw.isEmpty ? 'No message.' : raw;
  }

  String _whenText(Map<String, dynamic> row) {
    final value = _dt(row['created_at']);
    if (value == null) return '-';
    final hour24 = value.hour;
    var hour12 = hour24 % 12;
    if (hour12 == 0) hour12 = 12;
    final minute = value.minute.toString().padLeft(2, '0');
    final suffix = hour24 >= 12 ? 'PM' : 'AM';
    return '${value.day}/${value.month}/${value.year} $hour12:$minute $suffix';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
          TextButton(
            onPressed: _markingAllRead ? null : _markAllRead,
            child: const Text('Mark all read'),
          ),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(snapshot.error.toString()),
              ),
            );
          }

          final rows = snapshot.data ?? const <Map<String, dynamic>>[];
          if (rows.isEmpty) {
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: const [
                  SizedBox(height: 120),
                  Icon(Icons.notifications_none_rounded, size: 52),
                  SizedBox(height: 16),
                  Center(
                    child: Text(
                      'No notifications yet.',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              itemCount: rows.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final row = rows[index];
                final unread = _s(row['read_status']).toLowerCase() != 'read';

                return Card(
                  child: ListTile(
                    onTap: () => _openNotification(row),
                    leading: CircleAvatar(
                      backgroundColor: unread
                          ? Theme.of(context).colorScheme.primaryContainer
                          : Theme.of(context).colorScheme.surfaceContainerHighest,
                      child: Icon(
                        unread
                            ? Icons.notifications_active_outlined
                            : Icons.notifications_none_rounded,
                      ),
                    ),
                    title: Text(
                      _titleFor(row),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        Text(
                          _messageFor(row),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _whenText(row),
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    trailing: unread
                        ? Container(
                            width: 10,
                            height: 10,
                            decoration: const BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                            ),
                          )
                        : null,
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
