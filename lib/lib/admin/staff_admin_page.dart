import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/admin_access_service.dart';
import 'widgets/admin_ui.dart';

/// SuperAdmin only: manage Staff Admin (SAdmin).
///
/// Staff admins are stored in `public.staff_admin` and have their own
/// Supabase Auth account (email/password). Password is NOT stored in DB.
///
/// This UI calls an Edge Function named `create_sadmin` to create the
/// Auth user and insert the staff_admin row in one atomic server-side action.
///
/// For quick testing, you can also create the Auth user in Supabase Dashboard
/// and then insert into `staff_admin` manually.
class StaffAdminPage extends StatefulWidget {
  const StaffAdminPage({super.key});

  @override
  State<StaffAdminPage> createState() => _StaffAdminPageState();
}

class _StaffAdminPageState extends State<StaffAdminPage> {
  SupabaseClient get _supa => Supabase.instance.client;

  late Future<List<Map<String, dynamic>>> _future;

  late Future<AdminContext> _ctxFuture;
  AdminContext? _ctx;

  @override
  void initState() {
    super.initState();
    _future = _load();
    _ctxFuture = AdminAccessService(_supa).getAdminContext().then((c) {
      _ctx = c;
      return c;
    });
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final rows = await _supa
        .from('staff_admin')
        .select('sadmin_id,auth_uid,sadmin_name,sadmin_email,sadmin_salary,sadmin_status,created_at')
        .order('sadmin_id');
    final list = (rows as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    final authUidToStaffId = <String, String>{};
    for (final row in list) {
      final staffId = _s(row['sadmin_id']).trim();
      final authUid = _s(row['auth_uid']).trim();
      if (staffId.isNotEmpty && authUid.isNotEmpty) {
        authUidToStaffId[authUid] = staffId;
      }
      row['handled_case_count'] = 0;
      row['review_count'] = 0;
      row['average_rating'] = 0.0;
    }

    try {
      final ticketRows = await _supa
          .from('support_ticket')
          .select('ticket_id,handled_by_staff_id,assigned_admin_uid,assigned_admin_role');
      final countedTicketIdsByStaff = <String, Set<String>>{};
      for (final raw in (ticketRows as List)) {
        final ticket = Map<String, dynamic>.from(raw as Map);
        final ticketId = _s(ticket['ticket_id']).trim();
        if (ticketId.isEmpty) continue;

        var staffId = _s(ticket['handled_by_staff_id']).trim();
        if (staffId.isEmpty &&
            _s(ticket['assigned_admin_role']).trim().toLowerCase() == 'staff') {
          staffId = authUidToStaffId[_s(ticket['assigned_admin_uid']).trim()] ?? '';
        }
        if (staffId.isEmpty) continue;
        countedTicketIdsByStaff.putIfAbsent(staffId, () => <String>{}).add(ticketId);
      }

      for (final row in list) {
        final staffId = _s(row['sadmin_id']).trim();
        row['handled_case_count'] = countedTicketIdsByStaff[staffId]?.length ?? 0;
      }
    } catch (_) {}

    final totalRating = <String, int>{};
    final totalCount = <String, int>{};
    final ratedTicketIdsByStaff = <String, Set<String>>{};

    try {
      List reviewRows = const [];
      try {
        final result = await _supa.from('support_ticket_review').select('ticket_id,staff_id,rating');
        if (result is List) reviewRows = result;
      } catch (_) {
        final result = await _supa.from('support_ticket_review').select('ticket_id,staff_auth_uid,rating');
        if (result is List) reviewRows = result;
      }

      for (final raw in reviewRows) {
        final review = Map<String, dynamic>.from(raw as Map);
        final ticketId = _s(review['ticket_id']).trim();
        var staffId = _s(review['staff_id']).trim();
        if (staffId.isEmpty) {
          staffId = authUidToStaffId[_s(review['staff_auth_uid']).trim()] ?? '';
        }
        if (staffId.isEmpty) continue;

        final rating = _parseRating(review['rating']);
        if (rating == null) continue;

        final staffTicketSet = ratedTicketIdsByStaff.putIfAbsent(staffId, () => <String>{});
        if (ticketId.isNotEmpty && staffTicketSet.contains(ticketId)) continue;
        if (ticketId.isNotEmpty) {
          staffTicketSet.add(ticketId);
        }

        totalRating[staffId] = (totalRating[staffId] ?? 0) + rating;
        totalCount[staffId] = (totalCount[staffId] ?? 0) + 1;
      }
    } catch (_) {}

    try {
      final ticketRows = await _supa
          .from('support_ticket')
          .select('ticket_id,handled_by_staff_id,assigned_admin_uid,assigned_admin_role');
      final ticketToStaffId = <String, String>{};
      if (ticketRows is List) {
        for (final raw in ticketRows) {
          final ticket = Map<String, dynamic>.from(raw as Map);
          final ticketId = _s(ticket['ticket_id']).trim();
          if (ticketId.isEmpty) continue;

          var staffId = _s(ticket['handled_by_staff_id']).trim();
          if (staffId.isEmpty && _s(ticket['assigned_admin_role']).trim().toLowerCase() == 'staff') {
            staffId = authUidToStaffId[_s(ticket['assigned_admin_uid']).trim()] ?? '';
          }
          if (staffId.isEmpty) continue;
          ticketToStaffId[ticketId] = staffId;
        }
      }

      final messageRows = await _supa
          .from('support_message')
          .select('ticket_id,message,created_at')
          .order('created_at', ascending: false);
      if (messageRows is List) {
        for (final raw in messageRows) {
          final msg = Map<String, dynamic>.from(raw as Map);
          final ticketId = _s(msg['ticket_id']).trim();
          if (ticketId.isEmpty) continue;
          final staffId = ticketToStaffId[ticketId] ?? '';
          if (staffId.isEmpty) continue;
          final rating = _extractHiddenReviewRating(msg['message']);
          if (rating == null) continue;

          final staffTicketSet = ratedTicketIdsByStaff.putIfAbsent(staffId, () => <String>{});
          if (staffTicketSet.contains(ticketId)) continue;
          staffTicketSet.add(ticketId);
          totalRating[staffId] = (totalRating[staffId] ?? 0) + rating;
          totalCount[staffId] = (totalCount[staffId] ?? 0) + 1;
        }
      }
    } catch (_) {}

    for (final row in list) {
      final staffId = _s(row['sadmin_id']).trim();
      final count = totalCount[staffId] ?? 0;
      final sum = totalRating[staffId] ?? 0;
      row['review_count'] = count;
      row['average_rating'] = count == 0 ? 0.0 : sum / count;
    }

    return list;
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _load();
    _ctxFuture = AdminAccessService(_supa).getAdminContext().then((c) {
      _ctx = c;
      return c;
    });
    });
    await _future;
  }

  String _s(dynamic v) => v == null ? '' : v.toString();


  int? _parseRating(dynamic value) {
    if (value == null) return null;
    if (value is num) {
      final n = value.toInt();
      return (n >= 1 && n <= 5) ? n : null;
    }
    final n = int.tryParse(_s(value));
    return (n != null && n >= 1 && n <= 5) ? n : null;
  }

  int? _extractHiddenReviewRating(dynamic value) {
    final raw = _s(value);
    const prefix = '[STAFF_REVIEW:';
    if (!raw.startsWith(prefix) || !raw.endsWith(']')) return null;
    return _parseRating(raw.substring(prefix.length, raw.length - 1));
  }

  bool get _isSuperAdmin => (_ctx?.isSuperAdmin ?? false);

  Future<void> _toggleStatus(Map<String, dynamic> row) async {
    if (!_isSuperAdmin) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Only Admin can edit staff.'), backgroundColor: Colors.red),
      );
      return;
    }
    final id = _s(row['sadmin_id']);
    if (id.isEmpty) return;
    final current = _s(row['sadmin_status']);
    final next = current == 'Active' ? 'Inactive' : 'Active';
    try {
      final res = await _supa
          .from('staff_admin')
          .update({'sadmin_status': next})
          .eq('sadmin_id', id)
          .select('sadmin_id')
          .maybeSingle();
      if (res == null) throw Exception('No row updated (RLS or ID mismatch).');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Updated $id to $next')),
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
    // Requirement: MUST fully delete including Supabase Auth user (no DB-only fallback).
    if (!_isSuperAdmin) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Only Admin can delete staff.'), backgroundColor: Colors.red),
      );
      return;
    }

    final id = _s(row['sadmin_id']).trim();
    final authUid = _s(row['auth_uid']).trim();
    if (id.isEmpty) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Staff Admin'),
        content: Text(
          'Delete $id completely?\n\n'
          'This will delete BOTH the staff_admin record and the Supabase Auth user.\n\n'
          'Requirement: the Edge Function `delete_sadmin` must be deployed. If it is missing or fails, nothing will be deleted.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;

    try {
      Session? session;
      try {
        final refreshed = await _supa.auth.refreshSession();
        session = refreshed.session;
      } catch (_) {
        // ignore
      }
      session ??= _supa.auth.currentSession;

      if (session == null || session.accessToken.isEmpty) {
        throw Exception('Admin session expired. Please login again.');
      }
      if (authUid.isEmpty) {
        throw Exception('Missing auth_uid for this staff account.');
      }

      await _supa.functions.invoke(
        'delete_sadmin',
        headers: {
          'Authorization': 'Bearer ${session.accessToken}',
          'x-user-jwt': session.accessToken,
        },
        body: {'auth_uid': authUid, 'sadmin_id': id},
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Deleted')),
      );
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
        if (!ctx.isSuperAdmin) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('Access denied. Only Admin can manage staff accounts.'),
            ),
          );
        }

        return Column(
          children: [
            AdminModuleHeader(
              icon: Icons.supervisor_account_outlined,
              title: 'Staff Admin',
              subtitle: 'SuperAdmin-only staff accounts',
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
                    final ok = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(builder: (_) => const _CreateStaffAdminPage()),
                    );
                    if (ok == true) await _refresh();
                  },
                  icon: const Icon(Icons.person_add_alt_1),
                  label: const Text('Add staff'),
                ),
              ],
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
                  return RefreshIndicator(
                    onRefresh: _refresh,
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                      itemCount: rows.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        final r = rows[i];
                        final id = _s(r['sadmin_id']);
                        final name = _s(r['sadmin_name']);
                        final email = _s(r['sadmin_email']);
                        final salary = r['sadmin_salary'];
                        final status = _s(r['sadmin_status']);

                        final handledCaseCount = (r['handled_case_count'] is num)
                            ? (r['handled_case_count'] as num).toInt()
                            : int.tryParse(_s(r['handled_case_count'])) ?? 0;
                        final reviewCount = (r['review_count'] is num)
                            ? (r['review_count'] as num).toInt()
                            : int.tryParse(_s(r['review_count'])) ?? 0;
                        final averageRating = (r['average_rating'] is num)
                            ? (r['average_rating'] as num).toDouble()
                            : double.tryParse(_s(r['average_rating'])) ?? 0.0;

                        return AdminCard(
                          child: ListTile(
                            leading: const Icon(Icons.admin_panel_settings_outlined),
                            title: Text(
                              name.isEmpty ? (id.isEmpty ? 'Staff Admin' : id) : '$name ($id)',
                              style: const TextStyle(fontWeight: FontWeight.w800),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(email.isEmpty ? '-' : email),
                                const SizedBox(height: 2),
                                Text('Salary: ${salary ?? '-'}'),
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    _MetricChip(
                                      icon: Icons.support_agent,
                                      label: 'Cases',
                                      value: handledCaseCount.toString(),
                                    ),
                                    _MetricChip(
                                      icon: Icons.reviews_outlined,
                                      label: 'Reviews',
                                      value: reviewCount.toString(),
                                    ),
                                    _MetricChip(
                                      icon: Icons.star_rate_rounded,
                                      label: 'Rating',
                                      value: reviewCount == 0 ? 'No rating' : averageRating.toStringAsFixed(1),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            isThreeLine: true,
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                AdminStatusChip(status: status),
                                const SizedBox(width: 6),
                                PopupMenuButton<String>(
                                  onSelected: (v) async {
                                    if (v == 'toggle') await _toggleStatus(r);
                                    if (v == 'edit') {
                                      final ok = await Navigator.of(context).push<bool>(
                                        MaterialPageRoute(builder: (_) => _EditStaffAdminPage(initial: r)),
                                      );
                                      if (ok == true) await _refresh();
                                    }
                                    if (v == 'delete') await _delete(r);
                                  },
                                  itemBuilder: (_) => [
                                    const PopupMenuItem(value: 'edit', child: Text('Edit')),
                                    PopupMenuItem(
                                      value: 'toggle',
                                      child: Text(status == 'Active' ? 'Deactivate' : 'Activate'),
                                    ),
                                    const PopupMenuItem(value: 'delete', child: Text('Delete')),
                                  ],
                                ),
                              ],
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

class _MetricChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _MetricChip({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 6),
          Text(
            '$label: $value',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _CreateStaffAdminPage extends StatefulWidget {
  const _CreateStaffAdminPage();

  @override
  State<_CreateStaffAdminPage> createState() => _CreateStaffAdminPageState();
}

// -----------------------------------------------------------------------------
// Edit Staff Admin (Admin-only)
// -----------------------------------------------------------------------------

class _EditStaffAdminPage extends StatefulWidget {
  final Map<String, dynamic> initial;
  const _EditStaffAdminPage({required this.initial});

  @override
  State<_EditStaffAdminPage> createState() => _EditStaffAdminPageState();
}

class _EditStaffAdminPageState extends State<_EditStaffAdminPage> {
  SupabaseClient get _supa => Supabase.instance.client;

  String _s(dynamic v) => v == null ? '' : v.toString();

  // Password tools (Admin-only). Supabase Auth passwords are not readable.
  // Admin can: (1) send reset email, (2) set a new password via Edge Function.
  final _newPw = TextEditingController();
  final _confirmPw = TextEditingController();
  bool _showPw = false;

  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _salary = TextEditingController();
  late String _status;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final r = widget.initial;
    _name.text = _s(r['sadmin_name']);
    _email.text = _s(r['sadmin_email']);
    final sal = r['sadmin_salary'];
    _salary.text = sal == null ? '' : sal.toString();
    _status = _s(r['sadmin_status']).isEmpty ? 'Active' : _s(r['sadmin_status']);
    if (_status != 'Active' && _status != 'Inactive') _status = 'Active';
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _salary.dispose();
    _newPw.dispose();
    _confirmPw.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
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
    final staffEmail = _email.text.trim();
    final staffName = _name.text.trim();
    if (staffEmail.isEmpty) return _toast('Staff email is empty.');

    final ok = await _confirm(
      'Send password reset email',
      'Send a password reset email to $staffName ($staffEmail)?',
    );
    if (!ok) return;

    try {
      await _supa.auth.resetPasswordForEmail(staffEmail);
      _toast('Reset email sent to $staffEmail');
    } catch (e) {
      _toast('Failed to send reset email: $e');
    }
  }

  Future<void> _adminSetPassword() async {
    final authUid = _s(widget.initial['auth_uid']);
    final staffEmail = _email.text.trim();
    final staffName = _name.text.trim();

    if (authUid.isEmpty) return _toast('Missing auth_uid for this staff.');

    final newPw = _newPw.text.trim();
    final confirmPw = _confirmPw.text.trim();
    if (newPw.isEmpty || confirmPw.isEmpty) return _toast('Please enter and confirm the new password.');
    if (newPw.length < 8) return _toast('Password must be at least 8 characters.');
    if (newPw != confirmPw) return _toast('Password confirmation does not match.');

    final ok = await _confirm(
      'Confirm password change',
      'Change password for $staffName ($staffEmail)?\n\nThis will overwrite the staff\'s current password.',
    );
    if (!ok) return;

    try {
      // Force-send the admin JWT. Some environments (especially web) may not attach it automatically.
      final token = _supa.auth.currentSession?.accessToken;
      if (token == null || token.isEmpty) {
        throw 'Admin session token is missing/expired. Please login again.';
      }

      final res = await _supa.functions.invoke(
        'set_staff_password',
        headers: {'Authorization': 'Bearer $token'},
        body: {
          'auth_uid': authUid,
          'new_password': newPw,
        },
      );

      if (res.data is Map && (res.data as Map)['ok'] == true) {
        _toast('Password updated successfully.');
        _newPw.clear();
        _confirmPw.clear();
        return;
      }

      _toast('Password update response: ${res.data}');
    } catch (e) {
      _toast('Failed to set password: $e');
    }
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    try {
      final id = _s(widget.initial['sadmin_id']);
      if (id.isEmpty) throw 'Missing sadmin_id';

      final salaryNum = double.tryParse(_salary.text.trim());

      final payload = <String, dynamic>{
        'sadmin_name': _name.text.trim(),
        'sadmin_email': _email.text.trim(),
        'sadmin_status': _status,
        'sadmin_salary': salaryNum,
      };

      // Verify affected row; update() can succeed with 0 rows.
      final res = await _supa
          .from('staff_admin')
          .update(payload)
          .eq('sadmin_id', id)
          .select('sadmin_id')
          .maybeSingle();

      if (res == null) {
        throw 'Update failed (no matching row). Check RLS or sadmin_id.';
      }

      if (!mounted) return;
      Navigator.pop(context, true);
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
    final id = _s(widget.initial['sadmin_id']);
    return Scaffold(
      appBar: AppBar(title: Text('Edit Staff ($id)')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'SAdmin Name'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _email,
                decoration: const InputDecoration(labelText: 'SAdmin Email'),
                keyboardType: TextInputType.emailAddress,
                validator: (v) {
                  final t = (v ?? '').trim();
                  if (t.isEmpty) return 'Required';
                  if (!t.contains('@')) return 'Invalid email';
                  return null;
                },
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _salary,
                decoration: const InputDecoration(labelText: 'Salary (optional)'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
              const SizedBox(height: 18),
              const Divider(),
              const SizedBox(height: 8),
              Text('Password tools', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _busy ? null : _sendResetEmail,
                icon: const Icon(Icons.email_outlined),
                label: const Text('Send reset email'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _newPw,
                obscureText: !_showPw,
                decoration: InputDecoration(
                  labelText: 'New Password',
                  suffixIcon: IconButton(
                    icon: Icon(_showPw ? Icons.visibility_off : Icons.visibility),
                    onPressed: _busy ? null : () => setState(() => _showPw = !_showPw),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
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

class _CreateStaffAdminPageState extends State<_CreateStaffAdminPage> {
  SupabaseClient get _supa => Supabase.instance.client;

  final _formKey = GlobalKey<FormState>();
  bool _busy = false;

  final _sadminId = TextEditingController();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _salary = TextEditingController();
  String _status = 'Active';

  @override
  void dispose() {
    _sadminId.dispose();
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _salary.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (!_formKey.currentState!.validate()) return;
    if (_busy) return;
    setState(() => _busy = true);

    try {
      final session = _supa.auth.currentSession;
      if (session == null) {
        throw Exception('Not logged in. Please login as SuperAdmin again.');
      }

      final payload = {
        'sadmin_id': _sadminId.text.trim().isEmpty ? null : _sadminId.text.trim(),
        'sadmin_name': _name.text.trim(),
        'sadmin_email': _email.text.trim(),
        'sadmin_password': _password.text,
        'sadmin_salary': _salary.text.trim().isEmpty ? null : num.tryParse(_salary.text.trim()),
        'sadmin_status': _status,
      };

      final res = await _supa.functions.invoke(
        'create_sadmin',
        headers: {
          'Authorization': 'Bearer ${session.accessToken}',
          'x-user-jwt': session.accessToken,
        },
        body: payload,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Created: ${res.data ?? 'OK'}')),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Staff Admin')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              Text(
                'This will create a staff admin Auth user (email+password) and a staff_admin row.\n\nYou must deploy the Edge Function `create_sadmin` first.',
                style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _sadminId,
                decoration: const InputDecoration(
                  labelText: 'SAdmin ID (optional)',
                  hintText: 'S001 (leave empty for auto)',
                ),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'SAdmin Name'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _email,
                decoration: const InputDecoration(labelText: 'SAdmin Email (Gmail)') ,
                keyboardType: TextInputType.emailAddress,
                validator: (v) {
                  final t = (v ?? '').trim();
                  if (t.isEmpty) return 'Required';
                  if (!t.contains('@')) return 'Invalid email';
                  return null;
                },
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _password,
                decoration: const InputDecoration(labelText: 'Password'),
                obscureText: true,
                validator: (v) {
                  final t = (v ?? '');
                  if (t.length < 8) return 'Min 8 characters';
                  return null;
                },
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _salary,
                decoration: const InputDecoration(labelText: 'Salary (optional)'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: _status,
                decoration: const InputDecoration(labelText: 'Status'),
                items: const [
                  DropdownMenuItem(value: 'Active', child: Text('Active')),
                  DropdownMenuItem(value: 'Inactive', child: Text('Inactive')),
                ],
                onChanged: (v) => setState(() => _status = v ?? 'Active'),
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
