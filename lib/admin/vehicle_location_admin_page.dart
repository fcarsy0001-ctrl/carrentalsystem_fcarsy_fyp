import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Admin: Manage vehicle locations (dropdown source for vehicle_location).
///
/// Back-end expectation:
/// - Table: vehicle_location
///   - location_id uuid primary key default gen_random_uuid()
///   - location_name text unique not null
///   - is_active boolean not null default true
///   - created_at timestamptz not null default now()
class VehicleLocationAdminPage extends StatefulWidget {
  const VehicleLocationAdminPage({super.key});

  @override
  State<VehicleLocationAdminPage> createState() => _VehicleLocationAdminPageState();
}

class _VehicleLocationAdminPageState extends State<VehicleLocationAdminPage> {
  SupabaseClient get _supa => Supabase.instance.client;

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _rows = const [];
    });

    try {
      final data = await _supa
          .from('vehicle_location')
          .select('location_id, location_name, is_active, created_at')
          .order('location_name', ascending: true);

      final list = (data as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      if (!mounted) return;
      setState(() {
        _rows = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _addLocation() async {
    final ctrl = TextEditingController();
    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Add Location'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Location name / address',
              hintText: 'e.g. 6, Jalan P. Ramlee, Kuala Lumpur',
            ),
            minLines: 1,
            maxLines: 3,
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Add')),
          ],
        ),
      );

      if (ok != true) return;
      final name = ctrl.text.trim();
      if (name.isEmpty) return;

      await _supa.from('vehicle_location').insert({
        'location_name': name,
        'is_active': true,
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Location added')));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Add failed: $e'), backgroundColor: Colors.red),
      );
    } finally {
      ctrl.dispose();
    }
  }

  Future<void> _toggleActive(Map<String, dynamic> row, bool v) async {
    final id = (row['location_id'] ?? '').toString();
    if (id.isEmpty) return;
    try {
      await _supa.from('vehicle_location').update({'is_active': v}).eq('location_id', id);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Update failed: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _delete(Map<String, dynamic> row) async {
    final id = (row['location_id'] ?? '').toString();
    if (id.isEmpty) return;
    final name = (row['location_name'] ?? '').toString();

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete location?'),
        content: Text('Delete: $name'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );

    if (ok != true) return;

    try {
      await _supa.from('vehicle_location').delete().eq('location_id', id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Deleted')));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete failed: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Widget _tableMissingHint() {
    const sql = '''
create table if not exists public.vehicle_location (
  location_id uuid primary key default gen_random_uuid(),
  location_name text unique not null,
  is_active boolean not null default true,
  created_at timestamp with time zone not null default now()
);

-- seed (example)
insert into public.vehicle_location (location_name) values
('6, Jalan P. Ramlee, 53000 Kuala Lumpur'),
('111-109, Jalan Malinja 3, Taman Bunga Raya, 53000 Kuala Lumpur')
on conflict (location_name) do nothing;
''';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'It looks like table "vehicle_location" is missing (or blocked by RLS).',
          style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        const Text('Create it in Supabase SQL Editor (minimum):'),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: Colors.black.withOpacity(0.05),
          ),
          child: const SelectableText(sql),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasTableMissing = (_error ?? '').toLowerCase().contains('vehicle_location') &&
        ((_error ?? '').toLowerCase().contains('does not exist') ||
            (_error ?? '').toLowerCase().contains('relation'));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Vehicle Locations'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loading ? null : _addLocation,
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : (_error != null)
                      ? ListView(
                          children: [
                            Text(_error!, style: TextStyle(color: Colors.red.shade700)),
                            const SizedBox(height: 12),
                            if (hasTableMissing) _tableMissingHint(),
                          ],
                        )
                      : ListView.separated(
                          itemCount: _rows.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final r = _rows[i];
                            final name = (r['location_name'] ?? '').toString();
                            final active = (r['is_active'] as bool?) ?? true;
                            return ListTile(
                              title: Text(name),
                              subtitle: Text(active ? 'Active' : 'Inactive'),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Switch(
                                    value: active,
                                    onChanged: (v) => _toggleActive(r, v),
                                  ),
                                  IconButton(
                                    tooltip: 'Delete',
                                    onPressed: () => _delete(r),
                                    icon: const Icon(Icons.delete_outline),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
            ),
          ),
        ),
      ),
    );
  }
}
