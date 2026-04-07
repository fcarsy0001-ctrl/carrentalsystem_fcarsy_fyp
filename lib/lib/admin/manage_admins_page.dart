import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/admin_manage_service.dart';

class ManageAdminsPage extends StatefulWidget {
  const ManageAdminsPage({super.key});

  @override
  State<ManageAdminsPage> createState() => _ManageAdminsPageState();
}

class _ManageAdminsPageState extends State<ManageAdminsPage> {
  SupabaseClient get _supa => Supabase.instance.client;
  late final AdminManageService _service;

  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _service = AdminManageService(_supa);
    _future = _service.listAdmins();
  }

  Future<void> _openAdd() async {
    final nextId = await _service.nextAdminId();
    final idCtrl = TextEditingController(text: nextId);
    final uidCtrl = TextEditingController();
    final roleCtrl = TextEditingController(text: 'SuperAdmin');
    String status = 'Active';

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Add admin'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: idCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Admin ID',
                    hintText: 'A001',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: uidCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Auth UID (required)',
                    hintText: 'UUID from Authentication → Users',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: roleCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Admin role',
                    hintText: 'SuperAdmin',
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: status,
                  items: const [
                    DropdownMenuItem(value: 'Active', child: Text('Active')),
                    DropdownMenuItem(value: 'Inactive', child: Text('Inactive')),
                  ],
                  onChanged: (v) => status = v ?? 'Active',
                  decoration: const InputDecoration(labelText: 'Status'),
                ),
                const SizedBox(height: 8),
                Text(
                  'Note: This does NOT create an Auth account. Create the user in Supabase → Authentication first, then paste the Auth UID here.',
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                )
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (idCtrl.text.trim().isEmpty || uidCtrl.text.trim().isEmpty) {
                  return;
                }
                Navigator.pop(context, true);
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    );

    if (ok != true) return;

    try {
      await _service.createAdmin(
        adminId: idCtrl.text.trim(),
        authUid: uidCtrl.text.trim(),
        role: roleCtrl.text.trim().isEmpty ? 'Admin' : roleCtrl.text.trim(),
        status: status,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Admin added'), backgroundColor: Colors.green),
      );
      setState(() => _future = _service.listAdmins());
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Admins',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
              ),
            ),
            FilledButton.tonalIcon(
              onPressed: _openAdd,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add admin'),
            )
          ],
        ),
        const SizedBox(height: 12),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: Padding(
                padding: EdgeInsets.only(top: 20),
                child: CircularProgressIndicator(),
              ));
            }
            final items = snap.data ?? const [];
            if (items.isEmpty) return const Text('No admins found.');

            return Column(
              children: [
                for (final a in items)
                  Card(
                    child: ListTile(
                      title: Text('${a['admin_id']} • ${a['admin_role']}'),
                      subtitle: Text(
                        'Status: ${a['admin_status']}\nAuth UID: ${a['auth_uid'] ?? '-'}',
                      ),
                      isThreeLine: true,
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}
