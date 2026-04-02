import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/vehicle_location_service.dart';

class UpdateVehicleLocationPage extends StatefulWidget {
  const UpdateVehicleLocationPage({super.key, required this.record});

  final Map<String, dynamic> record;

  @override
  State<UpdateVehicleLocationPage> createState() => _UpdateVehicleLocationPageState();
}

class _UpdateVehicleLocationPageState extends State<UpdateVehicleLocationPage> {
  final _formKey = GlobalKey<FormState>();
  final _branchController = TextEditingController();
  final _remarksController = TextEditingController();

  late final VehicleLocationService _service;

  List<String> _branches = const [];
  bool _saving = false;
  bool _loadingBranches = true;
  String? _selectedBranch;

  String _s(dynamic value) => value == null ? '' : value.toString().trim();

  String _formatTimestamp(dynamic value) {
    final raw = _s(value);
    if (raw.isEmpty) return 'No updates yet';

    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw.replaceFirst('T', ' ').replaceFirst('Z', '');

    final local = parsed.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final suffix = local.hour >= 12 ? 'PM' : 'AM';

    return '$day/$month/${local.year}, ${hour.toString().padLeft(2, '0')}:$minute $suffix';
  }

  @override
  void initState() {
    super.initState();
    _service = VehicleLocationService(Supabase.instance.client);
    _selectedBranch = _s(widget.record['vehicle_location']).isEmpty ? null : _s(widget.record['vehicle_location']);
    _branchController.text = _s(widget.record['vehicle_location']);
    _loadBranches();
  }

  @override
  void dispose() {
    _branchController.dispose();
    _remarksController.dispose();
    super.dispose();
  }

  Future<void> _loadBranches() async {
    final branches = await _service.fetchLocations();
    final currentBranch = _s(widget.record['vehicle_location']);
    final output = List<String>.from(branches);
    if (currentBranch.isNotEmpty && !output.contains(currentBranch)) {
      output.insert(0, currentBranch);
    }

    if (!mounted) return;
    setState(() {
      _branches = output;
      if ((_selectedBranch ?? '').isEmpty && output.isNotEmpty) {
        _selectedBranch = output.first;
      }
      _loadingBranches = false;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_saving) return;

    final branch = _branches.isNotEmpty ? (_selectedBranch ?? '').trim() : _branchController.text.trim();
    if (branch.isEmpty) return;

    setState(() => _saving = true);
    try {
      final user = Supabase.instance.client.auth.currentUser;
      await _service.updateLocation(
        vehicleId: _s(widget.record['vehicle_id']),
        newLocation: branch,
        movedBy: (user?.email ?? user?.id ?? '').trim(),
        remarks: _remarksController.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vehicle location updated')),
      );
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_service.explainError(error)), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final title = '${_s(widget.record['vehicle_brand'])} ${_s(widget.record['vehicle_model'])}'.trim();

    return Scaffold(
      appBar: AppBar(title: const Text('Update Vehicle Location')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 22),
            children: [
              _SectionCard(
                title: 'Vehicle Summary',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _s(widget.record['vehicle_plate_no']).isEmpty ? _s(widget.record['vehicle_id']) : _s(widget.record['vehicle_plate_no']),
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                    ),
                    const SizedBox(height: 4),
                    Text(title.isEmpty ? 'Vehicle' : title),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _InfoPill(label: 'Current Branch', value: _s(widget.record['vehicle_location']).isEmpty ? 'Not assigned' : _s(widget.record['vehicle_location'])),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _SectionCard(
                title: 'Current Location Summary',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Branch', style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(_s(widget.record['vehicle_location']).isEmpty ? 'No branch assigned' : _s(widget.record['vehicle_location']), style: const TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 12),
                    Text('Last Updated', style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(
                      _formatTimestamp(widget.record['location_last_updated']),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _SectionCard(
                title: 'New Location Details',
                child: Column(
                  children: [
                    if (_loadingBranches)
                      const LinearProgressIndicator()
                    else if (_branches.isNotEmpty)
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        value: _selectedBranch,
                        decoration: const InputDecoration(labelText: 'Branch *'),
                        items: _branches
                            .map((branch) => DropdownMenuItem(value: branch, child: Text(branch, overflow: TextOverflow.ellipsis)))
                            .toList(),
                        onChanged: _saving ? null : (value) => setState(() => _selectedBranch = value),
                        validator: (value) => (value ?? '').trim().isEmpty ? 'Branch is required' : null,
                      )
                    else
                      TextFormField(
                        controller: _branchController,
                        decoration: const InputDecoration(labelText: 'Branch *', hintText: 'Enter branch name'),
                        validator: (value) => (value ?? '').trim().isEmpty ? 'Branch is required' : null,
                      ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _remarksController,
                      minLines: 3,
                      maxLines: 5,
                      decoration: const InputDecoration(
                        labelText: 'Remarks (Optional)',
                        hintText: 'Add any additional notes about the location update...',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.sync_alt_outlined),
                label: Text(_saving ? 'Updating...' : 'Update Location'),
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: cs.primaryContainer.withOpacity(0.55),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700, fontSize: 12)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}










