import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/leaser_application_service.dart';
import 'leaser_review_detail_page.dart';
import 'widgets/admin_ui.dart';

class LeaserReviewPage extends StatefulWidget {
  const LeaserReviewPage({super.key});

  @override
  State<LeaserReviewPage> createState() => _LeaserReviewPageState();
}

class _LeaserReviewPageState extends State<LeaserReviewPage> {
  SupabaseClient get _supa => Supabase.instance.client;
  late final LeaserApplicationService _svc;

  String _filter = 'Pending';
  late Future<List<Map<String, dynamic>>> _future;
  RealtimeChannel? _realtimeChannel;

  @override
  void initState() {
    super.initState();
    _svc = LeaserApplicationService(_supa);
    _future = _load();
    _realtimeChannel = _supa
        .channel('leaser-review-live')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'leaser',
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

  String _s(dynamic v) => v == null ? '' : v.toString();

  Future<List<Map<String, dynamic>>> _load() async {
    final base = _supa.from('leaser').select('*');
    final q = (_filter == 'All') ? base : base.eq('leaser_status', _filter);
    try {
      final rows = await q.order('submitted_at', ascending: false);
      return (rows as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      final rows = await q.order('leaser_id', ascending: false);
      return (rows as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  Future<void> _openDetail(Map<String, dynamic> row) async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => LeaserReviewDetailPage(row: row)),
    );
    if (ok == true) await _refresh();
  }

  Future<void> _openAdd() async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => _LeaserAddPage(service: _svc)),
    );
    if (ok == true) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AdminModuleHeader(
          icon: Icons.assignment_outlined,
          title: 'Applications',
          subtitle: 'Review new leaser applications',
          actions: [
            IconButton(
              tooltip: 'Refresh',
              onPressed: _refresh,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
          primaryActions: [
            FilledButton.icon(
              onPressed: _openAdd,
              icon: const Icon(Icons.add),
              label: const Text('Add leaser'),
            ),
          ],
          bottom: Row(
            children: [
              const Text('Filter', style: TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(width: 10),
              DropdownButton<String>(
                value: _filter,
                items: const [
                  DropdownMenuItem(value: 'Pending', child: Text('Pending')),
                  DropdownMenuItem(value: 'Approved', child: Text('Approved')),
                  DropdownMenuItem(value: 'Rejected', child: Text('Rejected')),
                  DropdownMenuItem(value: 'All', child: Text('All')),
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
                return const Center(child: Text('No leaser applications'));
              }
              return RefreshIndicator(
                onRefresh: _refresh,
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final r = rows[i];
                    final id = _s(r['leaser_id']);
                    final type = _s(r['leaser_type']);
                    final name = _s(r['leaser_name']);
                    final company = _s(r['company_name']);
                    final st = _s(r['leaser_status']);
                    final sub = type.toLowerCase() == 'company' && company.isNotEmpty
                        ? '$company - $name'
                        : name;
                    return AdminCard(
                      child: ListTile(
                        onTap: () => _openDetail(r),
                        leading: const Icon(Icons.storefront_outlined),
                        title: Text(
                          id.isEmpty ? '(no id)' : id,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        subtitle: Text(
                          '${sub.isEmpty ? '-' : sub}\n${type.isEmpty ? '-' : type}',
                        ),
                        isThreeLine: true,
                        trailing: AdminStatusChip(status: st.isEmpty ? 'Pending' : st),
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

class _LeaserAddPage extends StatefulWidget {
  const _LeaserAddPage({required this.service});

  final LeaserApplicationService service;

  @override
  State<_LeaserAddPage> createState() => _LeaserAddPageState();
}

class _LeaserAddPageState extends State<_LeaserAddPage> {
  SupabaseClient get _supa => Supabase.instance.client;

  final _formKey = GlobalKey<FormState>();
  bool _busy = false;

  final _email = TextEditingController();
  final _type = TextEditingController(text: 'Individual');
  final _name = TextEditingController();
  final _company = TextEditingController();
  final _owner = TextEditingController();
  final _phone = TextEditingController();
  final _ic = TextEditingController();
  final _ssm = TextEditingController();
  String _status = 'Approved';

  @override
  void dispose() {
    _email.dispose();
    _type.dispose();
    _name.dispose();
    _company.dispose();
    _owner.dispose();
    _phone.dispose();
    _ic.dispose();
    _ssm.dispose();
    super.dispose();
  }

  void _toast(String msg, {Color? bg}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: bg));
  }

  String _nextFallbackUserId(int offset) {
    final seed = (DateTime.now().microsecondsSinceEpoch + offset).remainder(100000);
    return 'U${seed.toString().padLeft(5, '0')}';
  }

  Future<String> _generateUserId() async {
    try {
      final row = await _supa
          .from('app_user')
          .select('user_id')
          .order('user_id', ascending: false)
          .limit(1)
          .maybeSingle();
      final last = (row?['user_id'] ?? '').toString().trim();
      final match = RegExp(r'^U(\d+)$').firstMatch(last);
      if (match != null) {
        final next = (int.tryParse(match.group(1) ?? '') ?? 0) + 1;
        final digits = next.toString();
        return 'U${digits.length < 3 ? digits.padLeft(3, '0') : digits}';
      }
    } catch (_) {
      // ignore
    }
    return _nextFallbackUserId(0);
  }

  Future<Map<String, dynamic>?> _findLeaserByEmail(String email) async {
    try {
      final row = await _supa
          .from('leaser')
          .select('leaser_id,user_id,email')
          .eq('email', email)
          .limit(1)
          .maybeSingle();
      if (row != null) return Map<String, dynamic>.from(row as Map);
    } catch (_) {
      // ignore
    }
    return null;
  }

  Future<String> _findExistingUserIdByEmail(String email) async {
    try {
      final row = await _supa
          .from('app_user')
          .select('user_id')
          .eq('user_email', email)
          .limit(1)
          .maybeSingle();
      return (row?['user_id'] ?? '').toString().trim();
    } catch (_) {
      return '';
    }
  }

  Future<String> _tryCreateLinkedAppUser(String email) async {
    final derivedStatus = _status == 'Approved' ? 'Active' : 'Inactive';

    for (var attempt = 0; attempt < 10; attempt++) {
      final userId = attempt == 0 ? await _generateUserId() : _nextFallbackUserId(attempt + 1);
      try {
        await _supa.from('app_user').insert({
          'user_id': userId,
          'user_name': _name.text.trim(),
          'user_email': email,
          'user_password': '***',
          'user_phone': _phone.text.trim(),
          'user_icno': _ic.text.trim(),
          'user_gender': 'Other',
          'user_role': 'Leaser',
          'user_status': derivedStatus,
          'email_verified': false,
        });
        return userId;
      } catch (e) {
        final lower = e.toString().toLowerCase();
        if (lower.contains('duplicate') || lower.contains('23505')) {
          continue;
        }
        return '';
      }
    }
    return '';
  }

  Future<void> _save() async {
    if (_busy) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final email = _email.text.trim().toLowerCase();

      final existingByEmail = await _findLeaserByEmail(email);
      if (existingByEmail != null) {
        throw Exception('This email already has a leaser record');
      }

      var userId = await _findExistingUserIdByEmail(email);
      if (userId.isEmpty) {
        userId = await _tryCreateLinkedAppUser(email);
      }

      if (userId.isNotEmpty) {
        final existing = await widget.service.getByUserId(userId);
        if (existing != null) {
          throw Exception('This user already has a leaser record');
        }
      }

      final leaserId = await widget.service.generateLeaserId();
      await _supa.from('leaser').insert({
        'leaser_id': leaserId,
        'user_id': userId.isEmpty ? null : userId,
        'leaser_type': _type.text.trim(),
        'leaser_name': _name.text.trim(),
        'company_name': _company.text.trim().isEmpty ? null : _company.text.trim(),
        'owner_name': _owner.text.trim().isEmpty ? null : _owner.text.trim(),
        'phone': _phone.text.trim(),
        'email': email,
        'ic_no': _ic.text.trim(),
        'ssm_no': _ssm.text.trim().isEmpty ? null : _ssm.text.trim(),
        'leaser_status': _status,
        'submitted_at': DateTime.now().toIso8601String(),
      });

      if (!mounted) return;
      _toast('Leaser added: $leaserId', bg: Colors.green);
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      _toast('Failed: $e', bg: Colors.red);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Leaser')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextFormField(
                controller: _email,
                decoration: const InputDecoration(labelText: 'Email'),
                keyboardType: TextInputType.emailAddress,
                validator: (v) {
                  final s = (v ?? '').trim();
                  if (s.isEmpty) return 'Required';
                  if (!s.contains('@')) return 'Invalid email';
                  return null;
                },
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: _type.text,
                decoration: const InputDecoration(labelText: 'Type'),
                items: const [
                  DropdownMenuItem(value: 'Individual', child: Text('Individual')),
                  DropdownMenuItem(value: 'Company', child: Text('Company')),
                ],
                onChanged: _busy ? null : (v) => setState(() => _type.text = v ?? 'Individual'),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Name / PIC Name'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _company,
                decoration: const InputDecoration(labelText: 'Company Name (if company)'),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _owner,
                decoration: const InputDecoration(labelText: 'Owner Name (if company)'),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _phone,
                decoration: const InputDecoration(labelText: 'Phone'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _ic,
                decoration: const InputDecoration(labelText: 'IC'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _ssm,
                decoration: const InputDecoration(labelText: 'SSM No (optional)'),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: _status,
                decoration: const InputDecoration(labelText: 'Status'),
                items: const [
                  DropdownMenuItem(value: 'Approved', child: Text('Approved')),
                  DropdownMenuItem(value: 'Pending', child: Text('Pending')),
                  DropdownMenuItem(value: 'Rejected', child: Text('Rejected')),
                ],
                onChanged: _busy ? null : (v) => setState(() => _status = v ?? 'Approved'),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 48,
                child: FilledButton(
                  onPressed: _busy ? null : _save,
                  child: _busy
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save'),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}
