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
  bool _markingAll = false;

  @override
  void initState() {
    super.initState();
    _service = InAppNotificationService(_supa);
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

  String _fmtDateTime(dynamic value) {
    final d = _dt(value);
    if (d == null) return '-';
    var h = d.hour;
    final mm = d.minute.toString().padLeft(2, '0');
    final ap = h >= 12 ? 'pm' : 'am';
    h %= 12;
    if (h == 0) h = 12;
    return '${d.day}/${d.month}/${d.year} $h:$mm$ap';
  }

  Future<void> _markAllAsRead() async {
    setState(() => _markingAll = true);
    try {
      await _service.markAllAsReadForCurrentUser();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All notifications marked as read.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update notifications: $e')),
      );
    } finally {
      if (mounted) setState(() => _markingAll = false);
    }
  }

  Future<void> _openNotification(Map<String, dynamic> row) async {
    final id = (row['notification_id'] ?? '').toString().trim();
    final isRead = _service.isReadRow(row);
    try {
      if (!isRead && id.isNotEmpty) {
        await _service.markAsRead(id);
      }
    } catch (_) {}

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(_service.titleFor(row)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_service.messageFor(row)),
            const SizedBox(height: 12),
            Text(
              'Time: ${_fmtDateTime(row['created_at'])}',
              style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
            ),
            if ((row['booking_id'] ?? '').toString().trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'Booking: ${(row['booking_id'] ?? '').toString()}',
                style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
              ),
            ],
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          TextButton(
            onPressed: _markingAll ? null : _markAllAsRead,
            child: _markingAll
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Read all'),
          ),
        ],
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _service.watchCurrentUserNotifications(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Notification table is not ready yet. Please add the SQL setup first.\n\n${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final rows = snapshot.data ?? const <Map<String, dynamic>>[];
          if (rows.isEmpty) {
            return Center(
              child: Text(
                'No notifications yet.',
                style: TextStyle(color: Colors.grey.shade700),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            itemCount: rows.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final row = rows[index];
              final isRead = _service.isReadRow(row);
              final title = _service.titleFor(row);
              final message = _service.messageFor(row);
              return InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => _openNotification(row),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isRead ? Colors.grey.shade300 : Theme.of(context).colorScheme.primary.withOpacity(0.35),
                    ),
                    color: isRead
                        ? Colors.white
                        : Theme.of(context).colorScheme.primary.withOpacity(0.06),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        margin: const EdgeInsets.only(top: 6),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isRead ? Colors.grey.shade400 : Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: isRead ? Colors.black87 : Colors.black,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              message,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: Colors.grey.shade800, height: 1.3),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _fmtDateTime(row['created_at']),
                              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
