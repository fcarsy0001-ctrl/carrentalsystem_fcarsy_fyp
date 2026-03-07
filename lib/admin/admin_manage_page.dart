import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Admin management (testing):
/// - Lists rows from public.admin
/// - Allows inserting a new admin row by Auth UID
///
/// IMPORTANT: Creating Auth users (email+password) cannot be done safely
/// from Flutter with anon/auth keys. For now, you create the Auth user
/// in Supabase Dashboard, then add their UUID here.
class AdminManagePage extends StatefulWidget {
  const AdminManagePage({super.key});

  @override
  State<AdminManagePage> createState() => _AdminManagePageState();
}

class _AdminManagePageState extends State<AdminManagePage> {
  SupabaseClient get _supa => Supabase.instance.client;

  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final rows = await _supa.from('admin').select('*').order('admin_id');
    return (rows as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<List<Map<String, dynamic>>>(
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
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
              itemCount: rows.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final r = rows[i];
                final id = (r['admin_id'] ?? '').toString();
                final name = (r['admin_name'] ?? '').toString();
                final email = (r['admin_email'] ?? '').toString();
                final role = (r['admin_role'] ?? '').toString();
                final status = (r['admin_status'] ?? '').toString();
                return Card(
                  child: ListTile(
                    title: Text(
                      name.isEmpty ? (id.isEmpty ? 'Admin' : id) : '$name ($id)',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text('${email.isEmpty ? '-' : email}\nRole: $role'),
                    isThreeLine: true,
                    trailing: Text(status, style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                );
              },
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final ok = await Navigator.of(context).push<bool>(
            MaterialPageRoute(builder: (_) => const _AddAdminPage()),
          );
          if (ok == true) await _refresh();
        },
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Add admin'),
      ),
    );
  }
}

class _AddAdminPage extends StatefulWidget {
  const _AddAdminPage();

  @override
  State<_AddAdminPage> createState() => _AddAdminPageState();
}

class _AddAdminPageState extends State<_AddAdminPage> {
  SupabaseClient get _supa => Supabase.instance.client;

  final _formKey = GlobalKey<FormState>();
  bool _busy = false;

  final _adminId = TextEditingController();
  final _authUid = TextEditingController();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _role = TextEditingController(text: 'SuperAdmin');
  String _status = 'Active';

  @override
  void dispose() {
    _adminId.dispose();
    _authUid.dispose();
    _name.dispose();
    _email.dispose();
    _role.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final id = _adminId.text.trim();
      final authUid = _authUid.text.trim();
      await _supa.from('admin').insert({
        'admin_id': id,
        'auth_uid': authUid,
        'admin_role': _role.text.trim(),
        'admin_status': _status,
        'admin_name': _name.text.trim().isEmpty ? null : _name.text.trim(),
        'admin_email': _email.text.trim().isEmpty ? null : _email.text.trim(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Admin added')),
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
      appBar: AppBar(title: const Text('Add Admin')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              Text(
                'Create the Auth user first in Supabase Dashboard, then paste the Auth UID here.',
                style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _adminId,
                decoration: const InputDecoration(labelText: 'Admin ID', hintText: 'A002'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _authUid,
                decoration: const InputDecoration(labelText: 'Auth UID (UUID)'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Admin Name (optional)'),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _email,
                decoration: const InputDecoration(labelText: 'Admin Email (optional)'),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _role,
                decoration: const InputDecoration(labelText: 'Role'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
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
                onPressed: _busy ? null : _save,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
