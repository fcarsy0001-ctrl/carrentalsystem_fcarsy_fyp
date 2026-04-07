import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/admin_access_service.dart';
import 'widgets/admin_ui.dart';

class LeaserManagePage extends StatefulWidget {
  const LeaserManagePage({super.key});

  @override
  State<LeaserManagePage> createState() => _LeaserManagePageState();
}

class _LeaserManagePageState extends State<LeaserManagePage> {
  SupabaseClient get _supa => Supabase.instance.client;

  String _filter = 'All';
  late Future<List<Map<String, dynamic>>> _future;

  late Future<AdminContext> _ctxFuture;
  AdminContext? _ctx;

  bool get _isAdmin => (_ctx?.isAdmin ?? false);
  bool get _isSuperAdmin => (_ctx?.isSuperAdmin ?? false);

  @override
  void initState() {
    super.initState();
    _ctxFuture = AdminAccessService(_supa).getAdminContext().then((c) {
      _ctx = c;
      return c;
    });
    _future = _load();
  }

  String _s(dynamic v) => v == null ? '' : v.toString();

  Future<List<Map<String, dynamic>>> _load() async {
    final base = _supa.from('leaser').select('*');
    final q = (_filter == 'All') ? base : base.eq('leaser_status', _filter);
    final rows = await q.order('leaser_id', ascending: false);
    return (rows as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<void> _refresh() async {
    // setState callback must not return a Future
    setState(() {
      _future = _load();
    });
    await _future;
  }

  Color _statusColor(String st) {
    final v = st.trim().toLowerCase();
    if (v == 'approved' || v == 'active') return Colors.green;
    if (v == 'inactive' || v.contains('deactive')) return Colors.grey;
    if (v == 'rejected') return Colors.red;
    return Colors.orange;
  }

  String _displayName(Map<String, dynamic> row) {
    final company = _s(row['company_name']).trim();
    final leaserCompany = _s(row['leaser_company']).trim();
    final name = _s(row['leaser_name']).trim();
    if (company.isNotEmpty) return company;
    if (leaserCompany.isNotEmpty) return leaserCompany;
    if (name.isNotEmpty) return name;
    return 'Leaser ${_s(row['leaser_id']).trim()}';
  }

  Future<void> _toggleActive(Map<String, dynamic> row) async {
    if (!_isAdmin) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Admin access required.'), backgroundColor: Colors.red),
      );
      return;
    }

    final id = _s(row['leaser_id']).trim();
    if (id.isEmpty) return;
    final st = _s(row['leaser_status']).trim().toLowerCase();
    final next = (st == 'inactive' || st.contains('deactive')) ? 'Approved' : 'Inactive';

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(next == 'Inactive' ? 'Deactivate Leaser' : 'Activate Leaser'),
        content: Text(
          next == 'Inactive'
              ? 'This leaser will NOT be able to access leaser home.'
              : 'This leaser will be able to access leaser home again.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Confirm')),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await _supa.from('leaser').update({'leaser_status': next}).eq('leaser_id', id);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Updated: $next'), backgroundColor: Colors.green),
      );
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _delete(Map<String, dynamic> row) async {
    // Hard requirement: full delete MUST remove Auth user too (no DB-only fallback).
    if (!_isSuperAdmin) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Only Admin can delete leaser.'), backgroundColor: Colors.red),
      );
      return;
    }

    final id = _s(row['leaser_id']).trim();
    var authUid = _s(row['auth_uid']).trim(); // may be absent in DB; we will resolve from app_user

    // #region agent log
    try {
      final logFile = File('debug-e7b2d4.log');
      final log = {
        'sessionId': 'e7b2d4',
        'runId': 'initial',
        'hypothesisId': 'H3',
        'location': 'leaser_manage_page.dart:_delete',
        'message': 'Delete leaser requested',
        'data': {
          'leaserId': id,
          'authUidEmpty': authUid.isEmpty,
          'isSuperAdmin': _isSuperAdmin,
        },
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };
      logFile.writeAsStringSync('${jsonEncode(log)}\n', mode: FileMode.append, flush: true);
    } catch (_) {}
    // #endregion
    if (id.isEmpty) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Leaser'),
        content: Text(
          'Delete leaser $id completely?\n\n'
          'This will delete BOTH the leaser record and the Supabase Auth user.\n\n'
          'Requirement: the Edge Function `delete_leaser` must be deployed. If it is missing or fails, nothing will be deleted.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;

    try {
      final token = _supa.auth.currentSession?.accessToken;
      if (token == null || token.isEmpty) {
        throw Exception('Admin session expired. Please login again.');
      }

      if (authUid.isEmpty) {
        authUid = await _resolveAuthUidForLeaser(row);
      }
      if (authUid.isEmpty) {
        throw Exception('Missing auth_uid for this leaser. Cannot delete Auth user safely.');
      }

      // IMPORTANT: for protected Edge Functions, pass the admin JWT explicitly.
      // (Same approach as staff deletion module.)
      final res = await _supa.functions.invoke(
        'delete_leaser',
        headers: {
          'Authorization': 'Bearer $token',
          'x-user-jwt': token,
        },
        body: {'auth_uid': authUid, 'leaser_id': id},
      );

      // #region agent log
      try {
        final logFile = File('debug-e7b2d4.log');
        final log = {
          'sessionId': 'e7b2d4',
          'runId': 'initial',
          'hypothesisId': 'H3',
          'location': 'leaser_manage_page.dart:_delete',
          'message': 'delete_leaser response in manage page',
          'data': {
            'leaserId': id,
            'rawDataType': res.data?.runtimeType.toString(),
          },
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        };
        logFile.writeAsStringSync('${jsonEncode(log)}\n', mode: FileMode.append, flush: true);
      } catch (_) {}
      // #endregion

      final data = res.data;
      final okResp = (data is Map) && (data['ok'] == true);
      if (!okResp) {
        throw Exception('delete_leaser failed: $data');
      }

      // Verify the row is truly deleted (avoid silent refresh with no effect)
      final stillExists = await _supa.from('leaser').select('leaser_id').eq('leaser_id', id).maybeSingle();
      if (stillExists != null) {
        throw Exception('Delete reported success but record still exists. Check Edge Function logic / FK constraints.');
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Deleted'), backgroundColor: Colors.green),
      );
      await _refresh();
    } catch (e) {
      // #region agent log
      try {
        final logFile = File('debug-e7b2d4.log');
        final log = {
          'sessionId': 'e7b2d4',
          'runId': 'initial',
          'hypothesisId': 'H3',
          'location': 'leaser_manage_page.dart:_delete',
          'message': 'Delete leaser threw in manage page',
          'data': {
            'leaserId': id,
            'error': e.toString(),
          },
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        };
        logFile.writeAsStringSync('${jsonEncode(log)}\n', mode: FileMode.append, flush: true);
      } catch (_) {}
      // #endregion

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete failed: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<String> _resolveAuthUidForLeaser(Map<String, dynamic> row) async {
    // Resolve from app_user since leaser table may not contain auth_uid in this schema
    final userId = _s(row['user_id']).trim();
    final email = _s(row['email']).trim();

    try {
      if (userId.isNotEmpty) {
        final u = await _supa.from('app_user').select('auth_uid').eq('user_id', userId).maybeSingle();
        final uid = (u?['auth_uid'] as String?)?.trim() ?? '';
        if (uid.isNotEmpty) return uid;
      }
      if (email.isNotEmpty) {
        final u = await _supa.from('app_user').select('auth_uid').eq('user_email', email).maybeSingle();
        final uid = (u?['auth_uid'] as String?)?.trim() ?? '';
        if (uid.isNotEmpty) return uid;
      }
    } catch (_) {}
    return '';
  }

  Future<void> _edit(Map<String, dynamic> row) async {
    if (!_isAdmin) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Admin access required.'), backgroundColor: Colors.red),
      );
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _EditLeaserAdminPage(
          initial: row,
          isSuperAdmin: _isSuperAdmin,
        ),
      ),
    );
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AdminContext>(
      future: _ctxFuture,
      builder: (context, snapCtx) {
        // Even if ctx fails, we still show the list, but restrict actions.
        return Column(
          children: [
            AdminModuleHeader(
              icon: Icons.manage_accounts_outlined,
              title: 'Manage',
              subtitle: 'Edit, activate/deactivate and delete leasers',
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
                      DropdownMenuItem(value: 'All', child: Text('All')),
                      DropdownMenuItem(value: 'Approved', child: Text('Approved')),
                      DropdownMenuItem(value: 'Inactive', child: Text('Inactive')),
                      DropdownMenuItem(value: 'Pending', child: Text('Pending')),
                      DropdownMenuItem(value: 'Rejected', child: Text('Rejected')),
                    ],
                    onChanged: (v) async {
                      if (v == null) return;
                      setState(() => _filter = v);
                      await _refresh();
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
                    return Center(child: Text('Load failed: ${snap.error}'));
                  }
                  final rows = snap.data ?? const [];
                  if (rows.isEmpty) {
                    return const Center(child: Text('No leasers'));
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    itemCount: rows.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, i) {
                      final r = rows[i];
                      final id = _s(r['leaser_id']).trim();
                      final status = _s(r['leaser_status']).trim();
                      final email = _s(r['email']).trim();

                      final stLower = status.toLowerCase();
                      final toggleLabel = (stLower == 'inactive' || stLower.contains('deactive'))
                          ? 'Activate'
                          : 'Deactivate';

                      return AdminCard(
                        child: ListTile(
                          leading: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: _statusColor(status).withOpacity(0.12),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            alignment: Alignment.center,
                            child: Icon(Icons.storefront_outlined, color: _statusColor(status)),
                          ),
                          title: Text(
                            _displayName(r),
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          subtitle: Text(
                            'Leaser ID: ${id.isEmpty ? '-' : id}${email.isEmpty ? '' : '\nEmail: $email'}',
                          ),
                          isThreeLine: email.isNotEmpty,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              AdminStatusChip(status: status),
                              const SizedBox(width: 6),
                              PopupMenuButton<String>(
                                onSelected: (v) {
                                  if (v == 'edit') _edit(r);
                                  if (v == 'toggle') _toggleActive(r);
                                  if (v == 'delete') _delete(r);
                                },
                                itemBuilder: (_) => [
                                  const PopupMenuItem(value: 'edit', child: Text('Edit')),
                                  PopupMenuItem(value: 'toggle', child: Text(toggleLabel)),
                                  const PopupMenuItem(value: 'delete', child: Text('Delete')),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _EditLeaserAdminPage extends StatefulWidget {
  const _EditLeaserAdminPage({
    required this.initial,
    required this.isSuperAdmin,
  });

  final Map<String, dynamic> initial;
  final bool isSuperAdmin;

  @override
  State<_EditLeaserAdminPage> createState() => _EditLeaserAdminPageState();
}

class _EditLeaserAdminPageState extends State<_EditLeaserAdminPage> {
  SupabaseClient get _supa => Supabase.instance.client;

  final _formKey = GlobalKey<FormState>();
  bool _busy = false;

  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _ic;
  late final TextEditingController _company;
  late final TextEditingController _owner;
  late final TextEditingController _ssm;
  late final TextEditingController _bank;

  final _newPw = TextEditingController();
  final _confirmPw = TextEditingController();
  bool _showPw = false;

  String _s(dynamic v) => v == null ? '' : v.toString();

  @override
  void initState() {
    super.initState();
    final r = widget.initial;
    _name = TextEditingController(text: _s(r['leaser_name']).trim());
    _phone = TextEditingController(text: _s(r['phone']).trim());
    _ic = TextEditingController(text: _s(r['ic_no']).trim());
    _company = TextEditingController(text: _s(r['company_name']).trim().isEmpty ? _s(r['leaser_company']).trim() : _s(r['company_name']).trim());
    _owner = TextEditingController(text: _s(r['owner_name']).trim());
    _ssm = TextEditingController(text: _s(r['ssm_no']).trim());
    _bank = TextEditingController(text: _s(r['bank_account_no']).trim());
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _ic.dispose();
    _company.dispose();
    _owner.dispose();
    _ssm.dispose();
    _bank.dispose();
    _newPw.dispose();
    _confirmPw.dispose();
    super.dispose();
  }

  void _toast(String msg, {Color? bg}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: bg));
  }

  Future<bool> _confirm(String title, String message) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Confirm')),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _sendResetEmail() async {
    final email = _s(widget.initial['email']).trim();
    final name = _name.text.trim();
    if (email.isEmpty) return _toast('Leaser email is empty.', bg: Colors.red);

    final ok = await _confirm('Send password reset email', 'Send reset email to $name ($email)?');
    if (!ok) return;

    try {
      await _supa.auth.resetPasswordForEmail(email);
      _toast('Reset email sent to $email', bg: Colors.green);
    } catch (e) {
      _toast('Failed to send reset email: $e', bg: Colors.red);
    }
  }

  Future<void> _adminSetPassword() async {
    if (!widget.isSuperAdmin) {
      return _toast('Only Admin can set password.', bg: Colors.red);
    }

    final authUid = _s(widget.initial['auth_uid']).trim();
    final email = _s(widget.initial['email']).trim();
    final id = _s(widget.initial['leaser_id']).trim();

    if (authUid.isEmpty) return _toast('Missing auth_uid for this leaser.', bg: Colors.red);

    final newPw = _newPw.text.trim();
    final confirmPw = _confirmPw.text.trim();
    if (newPw.isEmpty || confirmPw.isEmpty) return _toast('Enter and confirm the new password.', bg: Colors.red);
    if (newPw.length < 8) return _toast('Password must be at least 8 characters.', bg: Colors.red);
    if (newPw != confirmPw) return _toast('Password confirmation does not match.', bg: Colors.red);

    final ok = await _confirm(
      'Confirm password change',
      'Change password for $id${email.isEmpty ? '' : ' ($email)'}?\n\nThis will overwrite the current password.',
    );
    if (!ok) return;

    try {
      final token = _supa.auth.currentSession?.accessToken;
      if (token == null || token.isEmpty) {
        throw Exception('Admin session token missing/expired. Please login again.');
      }

      final res = await _supa.functions.invoke(
        'set_leaser_password',
        headers: {'Authorization': 'Bearer $token'},
        body: {'auth_uid': authUid, 'new_password': newPw},
      );

      final data = res.data;
      final okResp = (data is Map) && (data['ok'] == true);
      if (!okResp) {
        throw Exception('set_leaser_password failed: $data');
      }

      _toast('Password updated successfully.', bg: Colors.green);
      _newPw.clear();
      _confirmPw.clear();
    } catch (e) {
      _toast('Failed to set password: $e', bg: Colors.red);
    }
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    try {
      final id = _s(widget.initial['leaser_id']).trim();
      if (id.isEmpty) throw Exception('Missing leaser_id');

      final payload = <String, dynamic>{};

      void setIfExists(String key, dynamic value) {
        if (widget.initial.containsKey(key)) payload[key] = value;
      }

      // Basic details
      setIfExists('leaser_name', _name.text.trim());
      setIfExists('phone', _phone.text.trim());
      setIfExists('ic_no', _ic.text.trim());

      // Company / Individual fields (save only if the column exists)
      final comp = _company.text.trim();
      final owner = _owner.text.trim();
      final ssm = _ssm.text.trim();
      setIfExists('company_name', comp.isEmpty ? null : comp);
      setIfExists('leaser_company', comp.isEmpty ? null : comp);
      setIfExists('owner_name', owner.isEmpty ? null : owner);
      setIfExists('ssm_no', ssm.isEmpty ? null : ssm);

      // Payment
      final bank = _bank.text.trim();
      setIfExists('bank_account_no', bank.isEmpty ? null : bank);

      if (payload.isEmpty) {
        _toast('Nothing to update.', bg: Colors.orange);
        return;
      }

      await _supa.from('leaser').update(payload).eq('leaser_id', id);

      if (!mounted) return;
      _toast('Saved', bg: Colors.green);
      Navigator.of(context).pop(true);
    } catch (e) {
      _toast('Save failed: $e', bg: Colors.red);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final id = _s(widget.initial['leaser_id']).trim();
    final email = _s(widget.initial['email']).trim();

    return Scaffold(
      appBar: AppBar(title: Text('Edit Leaser $id')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              if (email.isNotEmpty)
                TextFormField(
                  initialValue: email,
                  readOnly: true,
                  decoration: const InputDecoration(labelText: 'Email (read-only)'),
                ),
              if (email.isNotEmpty) const SizedBox(height: 10),
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Name / PIC'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
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
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _company,
                decoration: const InputDecoration(labelText: 'Company Name (optional)'),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _owner,
                decoration: const InputDecoration(labelText: 'Owner Name (optional)'),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _ssm,
                decoration: const InputDecoration(labelText: 'SSM No (optional)'),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _bank,
                decoration: const InputDecoration(labelText: 'Bank Account No (optional)'),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _busy ? null : _save,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Save basic details'),
              ),
              const SizedBox(height: 18),
              const Divider(),
              const SizedBox(height: 8),
              Text(
                'Password (Admin)',
                style: TextStyle(fontWeight: FontWeight.w900, color: Colors.grey.shade800),
              ),
              const SizedBox(height: 8),
              Text(
                'You can either send a reset email, or directly set a new password via Edge Function `set_leaser_password`.\n\n'
                'Only Admin is allowed to set password directly.',
                style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _sendResetEmail,
                      icon: const Icon(Icons.mail_outline),
                      label: const Text('Send reset email'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _newPw,
                obscureText: !_showPw,
                decoration: InputDecoration(
                  labelText: 'New Password',
                  suffixIcon: IconButton(
                    onPressed: () => setState(() => _showPw = !_showPw),
                    icon: Icon(_showPw ? Icons.visibility_off : Icons.visibility),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _confirmPw,
                obscureText: !_showPw,
                decoration: const InputDecoration(labelText: 'Confirm New Password'),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _busy ? null : _adminSetPassword,
                icon: const Icon(Icons.lock_reset),
                label: const Text('Set new password (Admin)'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
