import 'package:email_validator/email_validator.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/admin_access_service.dart';
import '../services/admin_user_service.dart';
import 'widgets/admin_ui.dart';

/// Admin/Staff: Manage normal users stored in `public.app_user`.
///
/// Features:
/// - View: list/search users
/// - Add: creates Supabase Auth user + app_user row via Edge Function `create_app_user`
/// - Edit: updates app_user row (name/phone/ic/gender/status/email_verified)
/// - Delete: fully deletes Supabase Auth user + app_user row via Edge Function `delete_app_user`
class UserManagementPage extends StatefulWidget {
  const UserManagementPage({super.key});

  @override
  State<UserManagementPage> createState() => _UserManagementPageState();
}

class _UserManagementPageState extends State<UserManagementPage> {
  SupabaseClient get _supa => Supabase.instance.client;

  late Future<AdminContext> _ctxFuture;
  late Future<List<Map<String, dynamic>>> _future;

  String _roleFilter = 'User';
  String _statusFilter = 'All';
  final _q = TextEditingController();

  @override
  void initState() {
    super.initState();
    _ctxFuture = AdminAccessService(_supa).getAdminContext();
    _future = _load();
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  String _s(dynamic v) => v == null ? '' : v.toString();

  Future<List<Map<String, dynamic>>> _load() async {
    final rows = await _supa
        .from('app_user')
        .select(
          'user_id,auth_uid,user_name,user_email,user_phone,user_icno,user_gender,user_role,user_status,email_verified,driver_license_status',
        )
        .order('user_id', ascending: true)
        .limit(500);
    return (rows as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  
  void _upsertLocal(Map<String, dynamic> updated) {
    final updatedId = _s(updated['user_id']).trim();
    if (updatedId.isEmpty) return;

    setState(() {
      _future = _future.then((rows) {
        final list = rows.map((e) => Map<String, dynamic>.from(e)).toList();
        final idx = list.indexWhere((r) => _s(r['user_id']).trim() == updatedId);
        if (idx >= 0) {
          list[idx] = {...list[idx], ...updated};
        } else {
          list.insert(0, updated);
        }
        return list;
      });
    });
  }

  void _removeLocal(String userId) {
    final id = userId.trim();
    if (id.isEmpty) return;

    setState(() {
      _future = _future.then((rows) {
        final list = rows.map((e) => Map<String, dynamic>.from(e)).toList();
        list.removeWhere((r) => _s(r['user_id']).trim() == id);
        return list;
      });
    });
  }

List<Map<String, dynamic>> _applyClientFilters(List<Map<String, dynamic>> rows) {
    final q = _q.text.trim().toLowerCase();
    return rows.where((r) {
      final role = _s(r['user_role']).trim();
      final status = _s(r['user_status']).trim();

      if (_roleFilter != 'All' && role.toLowerCase() != _roleFilter.toLowerCase()) return false;
      if (_statusFilter != 'All' && status.toLowerCase() != _statusFilter.toLowerCase()) return false;

      if (q.isEmpty) return true;
      final id = _s(r['user_id']).toLowerCase();
      final name = _s(r['user_name']).toLowerCase();
      final email = _s(r['user_email']).toLowerCase();
      final phone = _s(r['user_phone']).toLowerCase();
      final ic = _s(r['user_icno']).toLowerCase();
      return id.contains(q) || name.contains(q) || email.contains(q) || phone.contains(q) || ic.contains(q);
    }).toList();
  }

  Future<void> _deleteUser(Map<String, dynamic> row) async {
    final userId = _s(row['user_id']).trim();
    final authUid = _s(row['auth_uid']).trim();
    final role = _s(row['user_role']).trim();
    if (userId.isEmpty || authUid.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Missing user_id/auth_uid for this user.'), backgroundColor: Colors.red),
      );
      return;
    }

    // Safety: this module is meant for normal users. Leasers should be handled in Leaser module.
    if (role.toLowerCase() == 'leaser') {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This account is a Leaser. Please delete it via the Leaser module.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete User'),
        content: Text(
          'Delete $userId permanently?\n\n'
          'This will delete BOTH:\n'
          '- app_user record\n'
          '- Supabase Auth user\n\n'
          'If this user has bookings, the system will also remove related booking records (force delete).',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await AdminUserService(_supa).deleteUser(userId: userId, authUid: authUid, force: true);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Deleted')));
      _removeLocal(userId);
      await _refresh();
    } catch (e) {

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete failed: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AdminContext>(
      future: _ctxFuture,
      builder: (context, ctxSnap) {
        if (ctxSnap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final ctx = ctxSnap.data ?? const AdminContext(AdminKind.none);
        if (!ctx.isAdmin) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('Access denied. Admin/Staff only.'),
            ),
          );
        }

        final filters = AdminCard(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                TextField(
                  controller: _q,
                  decoration: InputDecoration(
                    hintText: 'Search by ID / name / email / phone / IC',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _q.text.trim().isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear_rounded),
                            onPressed: () {
                              _q.clear();
                              setState(() {});
                            },
                          ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Text('Role', style: TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(width: 10),
                    DropdownButton<String>(
                      value: _roleFilter,
                      items: const [
                        DropdownMenuItem(value: 'User', child: Text('User')),
                        DropdownMenuItem(value: 'All', child: Text('All')),
                        DropdownMenuItem(value: 'Leaser', child: Text('Leaser')),
                      ],
                      onChanged: (v) => setState(() => _roleFilter = v ?? 'User'),
                    ),
                    const SizedBox(width: 18),
                    const Text('Status', style: TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(width: 10),
                    DropdownButton<String>(
                      value: _statusFilter,
                      items: const [
                        DropdownMenuItem(value: 'All', child: Text('All')),
                        DropdownMenuItem(value: 'Active', child: Text('Active')),
                        DropdownMenuItem(value: 'Inactive', child: Text('Inactive')),
                      ],
                      onChanged: (v) => setState(() => _statusFilter = v ?? 'All'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );

        return Column(
          children: [
            AdminModuleHeader(
              icon: Icons.people_alt_outlined,
              title: 'Users',
              subtitle: 'Admin/Staff user management',
              actions: [
                IconButton(
                  tooltip: 'Refresh',
                  onPressed: _refresh,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
              primaryActions: [
                FilledButton.icon(
                  onPressed: () async {
                    final created = await Navigator.of(context).push<Map<String, dynamic>>(
                      MaterialPageRoute(builder: (_) => const _CreateUserPage()),
                    );
                    if (created != null) {
                      _upsertLocal(created);
                      await _refresh();
                    }
                  },
                  icon: const Icon(Icons.person_add_alt_1),
                  label: const Text('Add user'),
                ),
              ],
              bottom: filters,
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
                    final rows = _applyClientFilters(snap.data ?? const []);
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
                          final id = _s(r['user_id']);
                          final name = _s(r['user_name']).isEmpty ? 'User' : _s(r['user_name']);
                          final email = _s(r['user_email']);
                          final phone = _s(r['user_phone']);
                          final role = _s(r['user_role']);
                          final status = _s(r['user_status']);
                          final verified = (r['email_verified'] == true);
                          final dlStatus = _s(r['driver_license_status']);
                          return AdminCard(
                            child: ListTile(
                              title: Text(
                                '$name ($id)',
                                style: const TextStyle(fontWeight: FontWeight.w800),
                              ),
                              subtitle: Text(
                                '${email.isEmpty ? '-' : email}\n'
                                'Phone: ${phone.isEmpty ? '-' : phone}  •  Role: ${role.isEmpty ? '-' : role}\n'
                                'Status: ${status.isEmpty ? '-' : status}  •  Email: ${verified ? 'Verified' : 'Not verified'}  •  DL: ${dlStatus.isEmpty ? '-' : dlStatus}',
                              ),
                              isThreeLine: true,
                              onTap: () async {
                                await Navigator.of(context).push(
                                  MaterialPageRoute(builder: (_) => _UserDetailPage(row: r)),
                                );
                              },
                              trailing: PopupMenuButton<String>(
                                onSelected: (v) async {
                                  if (v == 'view') {
                                    await Navigator.of(context).push(
                                      MaterialPageRoute(builder: (_) => _UserDetailPage(row: r)),
                                    );
                                  }
                                  if (v == 'edit') {
                                    final updated = await Navigator.of(context).push<Map<String, dynamic>>(
                                      MaterialPageRoute(builder: (_) => _EditUserPage(initial: r)),
                                    );
                                    if (updated != null) {
                                      _upsertLocal(updated);
                                      await _refresh();
                                    }
                                  }
                                  if (v == 'delete') {
                                    await _deleteUser(r);
                                  }
                                },
                                itemBuilder: (_) => const [
                                  PopupMenuItem(value: 'view', child: Text('View')),
                                  PopupMenuItem(value: 'edit', child: Text('Edit')),
                                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                                ],
                                child: AdminStatusChip(status: status),
                              ),
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
      },
    );
  }
}

// -----------------------------------------------------------------------------
// View
// -----------------------------------------------------------------------------

class _UserDetailPage extends StatelessWidget {
  const _UserDetailPage({required this.row});
  final Map<String, dynamic> row;

  String _s(dynamic v) => v == null ? '' : v.toString();

  @override
  Widget build(BuildContext context) {
    final id = _s(row['user_id']);
    final authUid = _s(row['auth_uid']);
    final name = _s(row['user_name']);
    final email = _s(row['user_email']);
    final phone = _s(row['user_phone']);
    final ic = _s(row['user_icno']);
    final gender = _s(row['user_gender']);
    final role = _s(row['user_role']);
    final status = _s(row['user_status']);
    final verified = (row['email_verified'] == true);
    final dlStatus = _s(row['driver_license_status']);

    Widget item(String label, String value) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 140, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700))),
            Expanded(child: Text(value.isEmpty ? '-' : value)),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text('User Details ($id)')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            item('User ID', id),
            item('Auth UID', authUid),
            item('Name', name),
            item('Email', email),
            item('Phone', phone),
            item('IC No', ic),
            item('Gender', gender),
            item('Role', role),
            item('Status', status),
            item('Email Verified', verified ? 'Yes' : 'No'),
            item('Driver Licence Status', dlStatus),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Create
// -----------------------------------------------------------------------------

class _CreateUserPage extends StatefulWidget {
  const _CreateUserPage();

  @override
  State<_CreateUserPage> createState() => _CreateUserPageState();
}

class _CreateUserPageState extends State<_CreateUserPage> {
  SupabaseClient get _supa => Supabase.instance.client;

  final _formKey = GlobalKey<FormState>();
  bool _busy = false;

  final _name = TextEditingController();
  final _email = TextEditingController();
  final _pw = TextEditingController();
  final _pw2 = TextEditingController();
  final _phone = TextEditingController();
  final _ic = TextEditingController();

  String _gender = 'Male';
  String _status = 'Active';
  bool _emailVerified = true;
  bool _showPw = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _pw.dispose();
    _pw2.dispose();
    _phone.dispose();
    _ic.dispose();
    super.dispose();
  }

  String _digitsOnly(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

  Future<void> _create() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final res = await AdminUserService(_supa).createUser(
        name: _name.text.trim(),
        email: _email.text.trim(),
        password: _pw.text,
        phone: _phone.text.trim(),
        icNo: _ic.text.trim(),
        gender: _gender,
        status: _status,
        emailVerified: _emailVerified,
      );
      if (!mounted) return;
      final email = _email.text.trim();
      final createdId = (res['user_id'] ?? '').toString().trim();

      // Fetch the created row so the list updates instantly.
      Map<String, dynamic>? createdRow;
      try {
        if (createdId.isNotEmpty) {
          final r = await _supa
              .from('app_user')
              .select(
                'user_id,auth_uid,user_name,user_email,user_phone,user_icno,user_gender,user_role,user_status,email_verified,driver_license_status',
              )
              .eq('user_id', createdId)
              .maybeSingle();
          if (r != null) createdRow = Map<String, dynamic>.from(r as Map);
        }
        if (createdRow == null) {
          final r = await _supa
              .from('app_user')
              .select(
                'user_id,auth_uid,user_name,user_email,user_phone,user_icno,user_gender,user_role,user_status,email_verified,driver_license_status',
              )
              .eq('user_email', email)
              .limit(1)
              .maybeSingle();
          if (r != null) createdRow = Map<String, dynamic>.from(r as Map);
        }
      } catch (_) {
        // ignore best-effort fetch
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(createdId.isEmpty ? 'User created' : 'User created: $createdId')),
      );
      Navigator.pop(context, createdRow ?? {
        'user_id': createdId,
        'user_name': _name.text.trim(),
        'user_email': email,
        'user_phone': _phone.text.trim(),
        'user_icno': _ic.text.trim(),
        'user_gender': _gender,
        'user_role': 'User',
        'user_status': _status,
        'email_verified': _emailVerified,
        'driver_license_status': 'Not Submitted',
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Create failed: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create User')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              Text(
                'This will create a Supabase Auth user and an app_user record (Role=User).',
                style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Name'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _email,
                decoration: const InputDecoration(labelText: 'Email'),
                keyboardType: TextInputType.emailAddress,
                validator: (v) {
                  final t = (v ?? '').trim();
                  if (t.isEmpty) return 'Required';
                  if (!EmailValidator.validate(t)) return 'Invalid email';
                  return null;
                },
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _pw,
                decoration: InputDecoration(
                  labelText: 'Password',
                  suffixIcon: IconButton(
                    icon: Icon(_showPw ? Icons.visibility_off : Icons.visibility),
                    onPressed: _busy ? null : () => setState(() => _showPw = !_showPw),
                  ),
                ),
                obscureText: !_showPw,
                validator: (v) {
                  final t = (v ?? '');
                  if (t.trim().isEmpty) return 'Required';
                  if (t.length < 8) return 'Min 8 characters';
                  if (!RegExp(r'[A-Z]').hasMatch(t)) return 'Need 1 uppercase';
                  if (!RegExp(r'[a-z]').hasMatch(t)) return 'Need 1 lowercase';
                  if (!RegExp(r'[0-9]').hasMatch(t)) return 'Need 1 number';
                  return null;
                },
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _pw2,
                decoration: const InputDecoration(labelText: 'Confirm Password'),
                obscureText: !_showPw,
                validator: (v) {
                  final t = (v ?? '');
                  if (t != _pw.text) return 'Password not match';
                  return null;
                },
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _phone,
                decoration: const InputDecoration(labelText: 'Phone (e.g. +60...)'),
                keyboardType: TextInputType.phone,
                validator: (v) {
                  final t = (v ?? '').trim();
                  if (t.isEmpty) return 'Required';
                  final digits = _digitsOnly(t);
                  if (digits.isEmpty) return 'Required';
                  // Malaysia: allow formats like 012-3456789 or +6012-3456789
                  var d = digits;
                  if (d.startsWith('60')) d = d.substring(2);
                  if (d.startsWith('0')) d = d.substring(1);
                  if (d.length < 9 || d.length > 10) return 'Invalid phone (MY)';
                  return null;
                },
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _ic,
                decoration: const InputDecoration(labelText: 'IC No (12 digits)'),
                keyboardType: TextInputType.number,
                validator: (v) {
                  final t = (v ?? '').trim();
                  if (t.isEmpty) return 'Required';
                  final digits = _digitsOnly(t);
                  if (digits.length != 12) return 'IC must be 12 digits';
                  return null;
                },
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: _gender,
                decoration: const InputDecoration(labelText: 'Gender'),
                items: const [
                  DropdownMenuItem(value: 'Male', child: Text('Male')),
                  DropdownMenuItem(value: 'Female', child: Text('Female')),
                ],
                onChanged: _busy ? null : (v) => setState(() => _gender = v ?? 'Male'),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: _status,
                decoration: const InputDecoration(labelText: 'Status'),
                items: const [
                  DropdownMenuItem(value: 'Active', child: Text('Active')),
                  DropdownMenuItem(value: 'Inactive', child: Text('Inactive')),
                ],
                onChanged: _busy ? null : (v) => setState(() => _status = v ?? 'Active'),
              ),
              const SizedBox(height: 10),
              SwitchListTile(
                value: _emailVerified,
                onChanged: _busy ? null : (v) => setState(() => _emailVerified = v),
                title: const Text('Email Verified'),
                subtitle: const Text('Sets app_user.email_verified and Auth email_confirm.'),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _busy ? null : _create,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Create'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Edit
// -----------------------------------------------------------------------------

class _EditUserPage extends StatefulWidget {
  const _EditUserPage({required this.initial});
  final Map<String, dynamic> initial;

  @override
  State<_EditUserPage> createState() => _EditUserPageState();
}

class _EditUserPageState extends State<_EditUserPage> {
  SupabaseClient get _supa => Supabase.instance.client;

  final _formKey = GlobalKey<FormState>();
  bool _busy = false;

  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _ic = TextEditingController();
  String _gender = 'Male';
  String _status = 'Active';
  bool _emailVerified = false;

  String _s(dynamic v) => v == null ? '' : v.toString();
  String _digitsOnly(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

  @override
  void initState() {
    super.initState();
    _name.text = _s(widget.initial['user_name']);
    _phone.text = _s(widget.initial['user_phone']);
    _ic.text = _s(widget.initial['user_icno']);
    _gender = _s(widget.initial['user_gender']).isEmpty ? 'Male' : _s(widget.initial['user_gender']);
    _status = _s(widget.initial['user_status']).isEmpty ? 'Active' : _s(widget.initial['user_status']);
    _emailVerified = widget.initial['email_verified'] == true;

    if (_gender != 'Male' && _gender != 'Female') _gender = 'Male';
    if (_status != 'Active' && _status != 'Inactive') _status = 'Active';
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _ic.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final userId = _s(widget.initial['user_id']).trim();
      if (userId.isEmpty) throw 'Missing user_id';

      final payload = <String, dynamic>{
        'user_name': _name.text.trim(),
        'user_phone': _phone.text.trim(),
        'user_icno': _ic.text.trim(),
        'user_gender': _gender,
        'user_status': _status,
        'email_verified': _emailVerified,
      };

      final authUid = _s(widget.initial['auth_uid']).trim();
      if (authUid.isEmpty) throw 'Missing auth_uid (cannot update safely).';

      final updated = await AdminUserService(_supa).updateUser(
        userId: userId,
        authUid: authUid,
        payload: payload,
      );

      if (!mounted) return;

      // If edge function returns the updated row -> use it; else merge locally.
      if (updated.containsKey('user_id')) {
        Navigator.pop(context, Map<String, dynamic>.from(updated));
      } else {
        Navigator.pop(context, <String, dynamic>{
          ...widget.initial,
          ...payload,
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save failed: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final userId = _s(widget.initial['user_id']);
    final email = _s(widget.initial['user_email']);
    return Scaffold(
      appBar: AppBar(title: Text('Edit User ($userId)')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              Text('Email (read-only): $email', style: TextStyle(color: Colors.grey.shade700)),
              const SizedBox(height: 12),
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Name'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _phone,
                decoration: const InputDecoration(labelText: 'Phone'),
                keyboardType: TextInputType.phone,
                validator: (v) {
                  final t = (v ?? '').trim();
                  if (t.isEmpty) return 'Required';
                  final digits = _digitsOnly(t);
                  if (digits.isEmpty) return 'Required';
                  // Malaysia: allow formats like 012-3456789 or +6012-3456789
                  var d = digits;
                  if (d.startsWith('60')) d = d.substring(2);
                  if (d.startsWith('0')) d = d.substring(1);
                  if (d.length < 9 || d.length > 10) return 'Invalid phone (MY)';
                  return null;
                },
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _ic,
                decoration: const InputDecoration(labelText: 'IC No'),
                keyboardType: TextInputType.number,
                validator: (v) {
                  final t = (v ?? '').trim();
                  if (t.isEmpty) return 'Required';
                  final digits = _digitsOnly(t);
                  if (digits.length != 12) return 'IC must be 12 digits';
                  return null;
                },
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: _gender,
                decoration: const InputDecoration(labelText: 'Gender'),
                items: const [
                  DropdownMenuItem(value: 'Male', child: Text('Male')),
                  DropdownMenuItem(value: 'Female', child: Text('Female')),
                ],
                onChanged: _busy ? null : (v) => setState(() => _gender = v ?? 'Male'),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: _status,
                decoration: const InputDecoration(labelText: 'Status'),
                items: const [
                  DropdownMenuItem(value: 'Active', child: Text('Active')),
                  DropdownMenuItem(value: 'Inactive', child: Text('Inactive')),
                ],
                onChanged: _busy ? null : (v) => setState(() => _status = v ?? 'Active'),
              ),
              const SizedBox(height: 10),
              SwitchListTile(
                value: _emailVerified,
                onChanged: _busy ? null : (v) => setState(() => _emailVerified = v),
                title: const Text('Email Verified'),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _busy ? null : _save,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Save changes'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
