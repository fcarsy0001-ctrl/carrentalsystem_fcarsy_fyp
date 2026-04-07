import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/driver_license_service.dart';

class AdminDriverLicenseReviewDetailPage extends StatefulWidget {
  const AdminDriverLicenseReviewDetailPage({
    super.key,
    required this.userId,
  });

  final String userId;

  @override
  State<AdminDriverLicenseReviewDetailPage> createState() => _AdminDriverLicenseReviewDetailPageState();
}

class _AdminDriverLicenseReviewDetailPageState extends State<AdminDriverLicenseReviewDetailPage> {
  SupabaseClient get _supa => Supabase.instance.client;
  late Future<Map<String, dynamic>?> _future;
  String? _photoUrl;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Map<String, dynamic>?> _load() async {
    final row = await _supa
        .from('app_user')
        .select(
            'user_id,user_name,user_email,user_phone,user_icno,driver_license_status,driver_license_no,driver_license_name,driver_license_expiry,driver_license_photo_path,driver_license_submitted_at,driver_license_reviewed_at,driver_license_reject_remark')
        .eq('user_id', widget.userId)
        .maybeSingle();

    if (row == null) return null;
    final m = Map<String, dynamic>.from(row as Map);

    final path = (m['driver_license_photo_path'] ?? '').toString();
    if (path.trim().isNotEmpty) {
      _photoUrl = await DriverLicenseService(_supa).createSignedPhotoUrl(path);
    }
    return m;
  }

  String _fmtDate(Object? raw) {
    if (raw == null) return '-';
    final s = raw.toString();
    if (s.isEmpty) return '-';
    try {
      final dt = DateTime.parse(s).toLocal();
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return s;
    }
  }

  Future<void> _approve() async {
    await _supa.from('app_user').update({
      'driver_license_status': 'Approved',
      'driver_license_reviewed_at': DateTime.now().toIso8601String(),
      'driver_license_reject_remark': null,
    }).eq('user_id', widget.userId);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Approved'), backgroundColor: Colors.green),
    );
    Navigator.of(context).pop();
  }

  Future<void> _reject() async {
    final controller = TextEditingController();
    final remark = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Reject licence'),
          content: TextField(
            controller: controller,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Remark (required)',
              hintText: 'Tell the user what to fix',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final v = controller.text.trim();
                if (v.isEmpty) return;
                Navigator.pop(context, v);
              },
              child: const Text('Reject'),
            ),
          ],
        );
      },
    );

    if (remark == null || remark.trim().isEmpty) return;

    await _supa.from('app_user').update({
      'driver_license_status': 'Rejected',
      'driver_license_reviewed_at': DateTime.now().toIso8601String(),
      'driver_license_reject_remark': remark.trim(),
    }).eq('user_id', widget.userId);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Rejected'), backgroundColor: Colors.orange),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Licence details')),
      body: FutureBuilder<Map<String, dynamic>?>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          final m = snap.data;
          if (m == null) {
            return const Center(child: Text('User not found'));
          }

          final status = (m['driver_license_status'] ?? '-').toString();
          final canDecide = status == 'Pending';

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (m['user_name'] ?? '-') as String,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 4),
                      Text((m['user_email'] ?? '-') as String),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 10,
                        runSpacing: 6,
                        children: [
                          _Chip(label: 'Status: $status'),
                          _Chip(label: 'Submitted: ${_fmtDate(m['driver_license_submitted_at'])}'),
                          _Chip(label: 'Reviewed: ${_fmtDate(m['driver_license_reviewed_at'])}'),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Licence information', style: TextStyle(fontWeight: FontWeight.w900)),
                      const SizedBox(height: 10),
                      _RowKV('Licence No', m['driver_license_no']),
                      _RowKV('Name on licence', m['driver_license_name']),
                      _RowKV('Expiry date', _fmtDate(m['driver_license_expiry'])),
                      const SizedBox(height: 10),
                      if ((m['driver_license_reject_remark'] ?? '').toString().trim().isNotEmpty)
                        _RowKV('Reject remark', m['driver_license_reject_remark']),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Licence photo', style: TextStyle(fontWeight: FontWeight.w900)),
                      const SizedBox(height: 10),
                      if (_photoUrl == null)
                        const Text('No photo or cannot access. Check Storage policies.'),
                      if (_photoUrl != null)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: AspectRatio(
                            aspectRatio: 16 / 9,
                            child: Image.network(
                              _photoUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Center(
                                child: Text('Failed to load image'),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              if (canDecide)
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.tonal(
                        onPressed: _reject,
                        child: const Text('Reject'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: _approve,
                        child: const Text('Approve'),
                      ),
                    ),
                  ],
                )
              else
                Text(
                  'Only Pending submissions can be approved/rejected.',
                  style: TextStyle(color: Colors.grey.shade700),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _RowKV extends StatelessWidget {
  const _RowKV(this.k, this.v);

  final String k;
  final Object? v;

  @override
  Widget build(BuildContext context) {
    final value = (v == null || v.toString().trim().isEmpty) ? '-' : v.toString();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(k, style: TextStyle(color: Colors.grey.shade700)),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}
