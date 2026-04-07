import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'widgets/admin_ui.dart';

/// Admin: review user driver licence submissions.
///
/// Data source: public.app_user
/// Columns used:
/// - user_id, user_name, user_email
/// - driver_license_no, driver_license_name, driver_license_expiry
/// - driver_license_photo_path, driver_license_status, driver_license_reject_remark
class DriverLicenseReviewPage extends StatefulWidget {
  const DriverLicenseReviewPage({super.key});

  @override
  State<DriverLicenseReviewPage> createState() => _DriverLicenseReviewPageState();
}

class _DriverLicenseReviewPageState extends State<DriverLicenseReviewPage> {
  SupabaseClient get _supa => Supabase.instance.client;

  String _filter = 'Pending';
  late Future<List<Map<String, dynamic>>> _future;
  RealtimeChannel? _realtimeChannel;

  @override
  void initState() {
    super.initState();
    _future = _load();
    _realtimeChannel = _supa
        .channel('driver-license-review-live')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'app_user',
          callback: (_) {
            if (!mounted) return;
            _refresh();
          },
        )
        .subscribe();
  }

  @override
  void dispose() {
    _realtimeChannel?.unsubscribe();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final rows = await _supa
        .from('app_user')
        .select(
            'user_id,user_name,user_email,driver_license_no,driver_license_name,driver_license_expiry,driver_license_photo_path,driver_license_status,driver_license_reject_remark')
        // Only normal users should appear in licence review.
        // (Admins/staff should not submit licences.)
        .eq('user_role', 'User')
        .eq('driver_license_status', _filter)
        .order('driver_license_submitted_at', ascending: false);

    return (rows as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  String _s(dynamic v) => v == null ? '' : v.toString();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AdminModuleHeader(
          icon: Icons.badge_outlined,
          title: 'Driver Licences',
          subtitle: 'Review and approve driving licence submissions',
          actions: [
            IconButton(
              tooltip: 'Refresh',
              onPressed: _refresh,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
          bottom: Row(
            children: [
              const Text('Status', style: TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(width: 10),
              DropdownButton<String>(
                value: _filter,
                items: const [
                  DropdownMenuItem(value: 'Pending', child: Text('Pending')),
                  DropdownMenuItem(value: 'Approved', child: Text('Approved')),
                  DropdownMenuItem(value: 'Rejected', child: Text('Rejected')),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setState(() {
                    _filter = v;
                    _future = _load();
                  });
                },
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('Failed to load: ${snap.error}'),
                  ),
                );
              }
              final rows = snap.data ?? const [];
              if (rows.isEmpty) {
                return const Center(child: Text('No records'));
              }
              return RefreshIndicator(
                onRefresh: _refresh,
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final r = rows[i];
                    final name = _s(r['user_name']).isEmpty ? 'User' : _s(r['user_name']);
                    final email = _s(r['user_email']);
                    final lic = _s(r['driver_license_no']);
                    final status = _s(r['driver_license_status']);
                    return AdminCard(
                      child: ListTile(
                        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w800)),
                        subtitle: Text(
                          '${email.isEmpty ? '-' : email}\nLicence: ${lic.isEmpty ? '-' : lic}',
                        ),
                        isThreeLine: true,
                        trailing: AdminStatusChip(status: status),
                        onTap: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => DriverLicenseDetailPage(row: r),
                            ),
                          );
                          await _refresh();
                        },
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class DriverLicenseDetailPage extends StatefulWidget {
  const DriverLicenseDetailPage({super.key, required this.row});

  final Map<String, dynamic> row;

  @override
  State<DriverLicenseDetailPage> createState() => _DriverLicenseDetailPageState();
}

class _DriverLicenseDetailPageState extends State<DriverLicenseDetailPage> {
  SupabaseClient get _supa => Supabase.instance.client;

  bool _busy = false;
  String? _signedUrl;

  String _s(dynamic v) => v == null ? '' : v.toString();

  @override
  void initState() {
    super.initState();
    _loadPhoto();
  }

  Future<void> _loadPhoto() async {
    final path = _s(widget.row['driver_license_photo_path']);
    if (path.isEmpty) return;
    try {
      final url = await _supa.storage
          .from('driver_licenses')
          .createSignedUrl(path, 60 * 60);
      if (!mounted) return;
      setState(() => _signedUrl = url);
    } catch (_) {
      // ignore; likely storage policies
    }
  }

  Future<void> _approve() async {
    await _setStatus('Approved', null);
  }

  Future<void> _reject() async {
    final remark = await _askRemark();
    if (remark == null) return;
    await _setStatus('Rejected', remark);
  }

  Future<void> _setStatus(String status, String? remark) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final userId = _s(widget.row['user_id']);
      await _supa.from('app_user').update({
        'driver_license_status': status,
        'driver_license_reviewed_at': DateTime.now().toIso8601String(),
        'driver_license_reject_remark': remark,
      }).eq('user_id', userId);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Updated to $status')),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _askRemark() async {
    final ctrl = TextEditingController();
    final res = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Reject remark'),
          content: TextField(
            controller: ctrl,
            decoration: const InputDecoration(hintText: 'Reason (required)'),
            autofocus: true,
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final t = ctrl.text.trim();
                if (t.isEmpty) return;
                Navigator.pop(context, t);
              },
              child: const Text('Reject'),
            ),
          ],
        );
      },
    );
    ctrl.dispose();
    return res;
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.row;
    final name = _s(r['user_name']).isEmpty ? 'User' : _s(r['user_name']);
    final email = _s(r['user_email']);
    final no = _s(r['driver_license_no']);
    final licName = _s(r['driver_license_name']);
    final exp = _s(r['driver_license_expiry']);
    final status = _s(r['driver_license_status']);
    final remark = _s(r['driver_license_reject_remark']);

    return Scaffold(
      appBar: AppBar(title: const Text('Licence Details')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
        children: [
          Text(name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
          const SizedBox(height: 4),
          Text(email.isEmpty ? '-' : email),
          const SizedBox(height: 14),

          _kv('Status', status),
          _kv('Licence No', no),
          _kv('Name on Licence', licName),
          _kv('Expiry', exp),
          if (remark.isNotEmpty) _kv('Reject Remark', remark),
          const SizedBox(height: 14),

          Text('Photo', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.5),
                border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.3)),
              ),
              clipBehavior: Clip.antiAlias,
              child: _signedUrl == null
                  ? const Center(child: Text('No photo / No access'))
                  : Image.network(_signedUrl!, fit: BoxFit.cover),
            ),
          ),

          const SizedBox(height: 18),

          if (status == 'Pending' || status == 'Rejected' || status == 'Not Submitted')
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _approve,
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('Approve'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: _busy ? null : _reject,
                    icon: const Icon(Icons.cancel_outlined),
                    label: const Text('Reject'),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(k, style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          Expanded(child: Text(v.isEmpty ? '-' : v)),
        ],
      ),
    );
  }
}
