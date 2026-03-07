import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/leaser_application_service.dart';

class LeaserReviewDetailPage extends StatefulWidget {
  const LeaserReviewDetailPage({super.key, required this.row});

  final Map<String, dynamic> row;

  @override
  State<LeaserReviewDetailPage> createState() => _LeaserReviewDetailPageState();
}

class _LeaserReviewDetailPageState extends State<LeaserReviewDetailPage> {
  SupabaseClient get _supa => Supabase.instance.client;
  late final LeaserApplicationService _svc;

  bool _busy = false;
  String? _signedSsmUrl;

  String _s(dynamic v) => v == null ? '' : v.toString();

  @override
  void initState() {
    super.initState();
    _svc = LeaserApplicationService(_supa);
    _loadSsm();
  }

  Future<void> _loadSsm() async {
    final path = _s(widget.row['ssm_photo_path']).trim();
    if (path.isEmpty) return;
    final url = await _svc.createSignedSsmUrl(path);
    if (!mounted) return;
    setState(() => _signedSsmUrl = url);
  }

  Future<void> _setStatus(String status, {String? remark}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final id = _s(widget.row['leaser_id']).trim();
      if (id.isEmpty) throw Exception('Missing leaser_id');

      await _supa.from('leaser').update({
        'leaser_status': status,
        'reviewed_at': DateTime.now().toIso8601String(),
        'leaser_reject_remark': remark,
      }).eq('leaser_id', id);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Updated: $status'), backgroundColor: Colors.green),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject() async {
    final remark = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final c = TextEditingController();
        return AlertDialog(
          title: const Text('Reject leaser'),
          content: TextField(
            controller: c,
            decoration: const InputDecoration(
              labelText: 'Reject reason',
              hintText: 'e.g. SSM photo unclear / SSM no invalid',
            ),
            maxLines: 3,
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(null), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.of(ctx).pop(c.text.trim()), child: const Text('Reject')),
          ],
        );
      },
    );
    if (remark == null) return;
    await _setStatus('Rejected', remark: remark.isEmpty ? 'Rejected' : remark);
  }

  Future<void> _approve() async {
    await _setStatus('Approved', remark: null);
  }

    Future<void> _delete() async {
    // Requirement: MUST fully delete including Supabase Auth user (no DB-only fallback).
    final id = _s(widget.row['leaser_id']).trim();
    var authUid = _s(widget.row['auth_uid']).trim();
    if (id.isEmpty) return;

    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete leaser'),
        content: Text(
          'Delete leaser $id completely?\n\n'
          'This will delete BOTH the leaser record and the Supabase Auth user.\n\n'
          'Requirement: the Edge Function `delete_leaser` must be deployed. If it is missing or fails, nothing will be deleted.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Delete')),
        ],
      ),
    );
    if (yes != true) return;

    setState(() => _busy = true);
    try {
      final session = _supa.auth.currentSession;
      if (session == null || session.accessToken.isEmpty) {
        throw Exception('Admin session expired. Please login again.');
      }
      if (authUid.isEmpty) {
        // Fallback: derive auth uid via app_user.user_id
        final userId = _s(widget.row['user_id']).trim();
        if (userId.isNotEmpty) {
          try {
            final u = await _supa
                .from('app_user')
                .select('auth_uid')
                .eq('user_id', userId)
                .limit(1)
                .maybeSingle();
            authUid = _s(u?['auth_uid']).trim();
          } catch (_) {}
        }
      }
      if (authUid.isEmpty) throw Exception('Missing auth_uid for this leaser account.');

      final path = _s(widget.row['ssm_photo_path']).trim();

      await _supa.functions.invoke(
        'delete_leaser',
        headers: {
          'Authorization': 'Bearer ${session.accessToken}',
          'x-user-jwt': session.accessToken,
        },
        body: {'auth_uid': authUid, 'leaser_id': id},
      );

      // optional: clean up storage file (not required for Auth deletion requirement)
      if (path.isNotEmpty) {
        try {
          await _supa.storage.from(LeaserApplicationService.bucketId).remove([path]);
        } catch (_) {}
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Deleted'), backgroundColor: Colors.green),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete failed: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }


  Future<void> _edit() async {
    final initial = widget.row;
    final name = TextEditingController(text: _s(initial['leaser_name']));
    final phone = TextEditingController(text: _s(initial['phone']));
    final ic = TextEditingController(text: _s(initial['ic_no']));
    final company = TextEditingController(text: _s(initial['company_name']));
    final owner = TextEditingController(text: _s(initial['owner_name']));
    final ssm = TextEditingController(text: _s(initial['ssm_no']));

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit leaser'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              children: [
                TextField(controller: name, decoration: const InputDecoration(labelText: 'Name / PIC')),
                TextField(controller: phone, decoration: const InputDecoration(labelText: 'Phone')),
                TextField(controller: ic, decoration: const InputDecoration(labelText: 'IC')),
                TextField(controller: company, decoration: const InputDecoration(labelText: 'Company Name')),
                TextField(controller: owner, decoration: const InputDecoration(labelText: 'Owner Name')),
                TextField(controller: ssm, decoration: const InputDecoration(labelText: 'SSM No')),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      final id = _s(widget.row['leaser_id']).trim();
      await _supa.from('leaser').update({
        'leaser_name': name.text.trim(),
        'phone': phone.text.trim(),
        'ic_no': ic.text.trim(),
        'company_name': company.text.trim().isEmpty ? null : company.text.trim(),
        'owner_name': owner.text.trim().isEmpty ? null : owner.text.trim(),
        'ssm_no': ssm.text.trim().isEmpty ? null : ssm.text.trim(),
      }).eq('leaser_id', id);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Updated'), backgroundColor: Colors.green),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Update failed: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setPassword() async {
    final authUid = _s(widget.row['auth_uid']).trim();
    if (authUid.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Missing auth_uid for this leaser.'), backgroundColor: Colors.red),
      );
      return;
    }

    final pw = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Set leaser password'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Enter a new password (min 8 characters).'),
              const SizedBox(height: 10),
              TextField(
                controller: pw,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'New password'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true) return;

    final newPw = pw.text.trim();
    if (newPw.length < 8) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password must be at least 8 characters.'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _busy = true);
    try {
      final session = _supa.auth.currentSession;
      if (session == null || session.accessToken.isEmpty) {
        throw Exception('Admin session expired. Please login again.');
      }

      await _supa.functions.invoke(
        'set_leaser_password',
        headers: {
          'Authorization': 'Bearer ${session.accessToken}',
          'x-user-jwt': session.accessToken,
        },
        body: {'auth_uid': authUid, 'new_password': newPw},
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password updated'), backgroundColor: Colors.green),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Update password failed: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }



  @override
  Widget build(BuildContext context) {
    final st = _s(widget.row['leaser_status']);
    final type = _s(widget.row['leaser_type']);
    final id = _s(widget.row['leaser_id']);

    return Scaffold(
      appBar: AppBar(
        title: Text('Leaser $id'),
        actions: [
          IconButton(tooltip: 'Edit', onPressed: _busy ? null : _edit, icon: const Icon(Icons.edit_outlined)),
          IconButton(tooltip: 'Password', onPressed: _busy ? null : _setPassword, icon: const Icon(Icons.lock_reset)),
          IconButton(tooltip: 'Delete', onPressed: _busy ? null : _delete, icon: const Icon(Icons.delete_outline)),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _busy ? null : _approve,
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('Approve'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: Colors.red),
                  onPressed: _busy ? null : _reject,
                  icon: const Icon(Icons.block_outlined),
                  label: const Text('Reject'),
                ),
              ),
            ],
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
        children: [
          Row(
            children: [
              _Chip(label: 'Status: ${st.isEmpty ? 'Pending' : st}'),
              const SizedBox(width: 8),
              _Chip(label: 'Type: ${type.isEmpty ? '-' : type}'),
            ],
          ),
          const SizedBox(height: 12),
          _RowKV('Leaser ID', widget.row['leaser_id']),
          _RowKV('User ID', widget.row['user_id']),
          _RowKV('Email', widget.row['email']),
          _RowKV('Phone', widget.row['phone']),
          _RowKV('IC', widget.row['ic_no']),
          _RowKV('Company Name', widget.row['company_name']),
          _RowKV('Owner/PIC Name', widget.row['owner_name']),
          _RowKV('SSM No', widget.row['ssm_no']),
          _RowKV('Submitted At', widget.row['submitted_at']),
          _RowKV('Reviewed At', widget.row['reviewed_at']),
          if (_s(widget.row['leaser_reject_remark']).trim().isNotEmpty)
            _RowKV('Reject Remark', widget.row['leaser_reject_remark']),

          const SizedBox(height: 12),
          if (_signedSsmUrl != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('SSM Photo', style: TextStyle(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        _signedSsmUrl!,
                        height: 220,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Padding(
                          padding: EdgeInsets.all(12),
                          child: Text('Failed to load SSM photo'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            const Text('No SSM photo'),
        ],
      ),
    );
  }
}

class _RowKV extends StatelessWidget {
  const _RowKV(this.k, this.v);

  final String k;
  final dynamic v;

  @override
  Widget build(BuildContext context) {
    final value = v == null ? '-' : v.toString();
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 130, child: Text(k, style: TextStyle(color: Colors.grey.shade700))),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w700))),
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
        color: Colors.grey.shade100,
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }
}
