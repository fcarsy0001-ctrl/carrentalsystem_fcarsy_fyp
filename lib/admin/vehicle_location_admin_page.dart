import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'widgets/admin_ui.dart';

/// Admin: Manage location master data used by vehicles.
class VehicleLocationAdminPage extends StatefulWidget {
  const VehicleLocationAdminPage({super.key, this.embedded = false});

  final bool embedded;

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
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _addLocation() async {
    final controller = TextEditingController();
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Add Location'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Location name / address',
              hintText: 'e.g. TAR UMT Main Branch',
            ),
            minLines: 1,
            maxLines: 3,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Add'),
            ),
          ],
        ),
      );

      if (confirmed != true) return;
      final name = controller.text.trim();
      if (name.isEmpty) return;

      await _supa.from('vehicle_location').insert({
        'location_name': name,
        'is_active': true,
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Location added')),
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Add failed: $error'), backgroundColor: Colors.red),
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _toggleActive(Map<String, dynamic> row, bool value) async {
    final id = (row['location_id'] ?? '').toString();
    if (id.isEmpty) return;
    try {
      await _supa.from('vehicle_location').update({'is_active': value}).eq('location_id', id);
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Update failed: $error'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _delete(Map<String, dynamic> row) async {
    final id = (row['location_id'] ?? '').toString();
    final name = (row['location_name'] ?? '').toString();
    if (id.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete location?'),
        content: Text('Delete: $name'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _supa.from('vehicle_location').delete().eq('location_id', id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Location deleted')),
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete failed: $error'), backgroundColor: Colors.red),
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
''';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'The vehicle_location table is missing or blocked by RLS.',
          style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        const Text('Create it in Supabase SQL Editor:'),
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

  Widget _buildList() {
    final hasTableMissing = (_error ?? '').toLowerCase().contains('vehicle_location') &&
        ((_error ?? '').toLowerCase().contains('does not exist') ||
            (_error ?? '').toLowerCase().contains('relation'));

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(_error!, style: TextStyle(color: Colors.red.shade700)),
          const SizedBox(height: 12),
          if (hasTableMissing) _tableMissingHint(),
        ],
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        children: [
          if (_rows.isEmpty)
            const AdminCard(
              child: Padding(
                padding: EdgeInsets.all(18),
                child: Text('No locations yet. Add pickup, branch, or parking locations here.'),
              ),
            )
          else
            ..._rows.map((row) {
              final name = (row['location_name'] ?? '').toString();
              final active = (row['is_active'] as bool?) ?? true;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: AdminCard(
                  child: ListTile(
                    title: Text(name, style: const TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text(active ? 'Active location' : 'Inactive location'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Switch(
                          value: active,
                          onChanged: (value) => _toggleActive(row, value),
                        ),
                        IconButton(
                          tooltip: 'Delete',
                          onPressed: () => _delete(row),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = _buildList();

    if (widget.embedded) {
      return Column(
        children: [
          AdminModuleHeader(
            icon: Icons.place_outlined,
            title: 'Location Management',
            subtitle: 'Manage the active branch, pickup, and parking locations used across vehicles.',
            actions: [
              IconButton(
                tooltip: 'Refresh',
                onPressed: _load,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
            primaryActions: [
              FilledButton.icon(
                onPressed: _loading ? null : _addLocation,
                icon: const Icon(Icons.add),
                label: const Text('Add location'),
              ),
            ],
          ),
          const Divider(height: 1),
          Expanded(child: body),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Location Management'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: body,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loading ? null : _addLocation,
        icon: const Icon(Icons.add),
        label: const Text('Add location'),
      ),
    );
  }
}