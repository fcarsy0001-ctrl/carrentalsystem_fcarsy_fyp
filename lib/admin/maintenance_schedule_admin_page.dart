import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/fleet_admin_service.dart';
import 'widgets/admin_ui.dart';

class MaintenanceScheduleAdminPage extends StatefulWidget {
  const MaintenanceScheduleAdminPage({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<MaintenanceScheduleAdminPage> createState() => _MaintenanceScheduleAdminPageState();
}

class _MaintenanceScheduleAdminPageState extends State<MaintenanceScheduleAdminPage> {
  SupabaseClient get _supa => Supabase.instance.client;

  late final FleetAdminService _service;
  late Future<_MaintenanceBundle> _future;

  @override
  void initState() {
    super.initState();
    _service = FleetAdminService(_supa);
    _future = _load();
  }

  Future<_MaintenanceBundle> _load() async {
    final schedules = await _service.fetchMaintenanceSchedules();
    final vehicles = await _service.fetchVehicles();
    List<Map<String, dynamic>> vendors = const [];
    try {
      vendors = await _service.fetchVendors();
    } catch (_) {}
    return _MaintenanceBundle(schedules: schedules, vehicles: vehicles, vendors: vendors);
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  Future<void> _openUpsert(_MaintenanceBundle bundle, {Map<String, dynamic>? initial}) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _ScheduleFormPage(
          service: _service,
          vehicles: bundle.vehicles,
          vendors: bundle.vendors,
          initial: initial,
        ),
      ),
    );
    if (saved == true) {
      await _refresh();
    }
  }

  Future<void> _delete(String scheduleId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete maintenance schedule'),
        content: Text('Delete schedule $scheduleId?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _service.deleteMaintenanceSchedule(scheduleId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Schedule deleted')),
      );
      await _refresh();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_service.explainError(error)),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildBody() {
    return FutureBuilder<_MaintenanceBundle>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _MaintenanceSqlError(message: _service.explainError(snapshot.error!));
        }

        final bundle = snapshot.data;
        if (bundle == null) {
          return const Center(child: Text('No data'));
        }

        final vehicleMap = _service.indexBy(bundle.vehicles, 'vehicle_id');
        final vendorMap = _service.indexBy(bundle.vendors, 'vendor_id');

        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            children: [
              if (bundle.schedules.isEmpty)
                const _MaintenanceEmptyCard(
                  message: 'No maintenance schedules yet. Create recurring maintenance reminders for your fleet here.',
                )
              else
                ...bundle.schedules.map((schedule) {
                  final scheduleId = (schedule['schedule_id'] ?? '').toString();
                  final vehicle = vehicleMap[(schedule['vehicle_id'] ?? '').toString()];
                  final vendor = vendorMap[(schedule['vendor_id'] ?? '').toString()];
                  final triggerMileage = widgetText(schedule['trigger_mileage']);
                  final triggerDate = dateText(schedule['trigger_date']);
                  final nextDate = dateText(schedule['next_maintenance_date']);

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: AdminCard(
                      child: ListTile(
                        title: Text(
                          (schedule['schedule_type'] ?? 'Maintenance Schedule').toString(),
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: Text(
                          'ID: $scheduleId\n'
                              'Vehicle: ${_service.vehicleLabel(vehicle)}\n'
                              'Vendor: ${_service.vendorLabel(vendor)}\n'
                              'Trigger mileage: $triggerMileage  |  Trigger date: $triggerDate\n'
                              'Next maintenance: $nextDate',
                        ),
                        isThreeLine: true,
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            AdminStatusChip(status: (schedule['schedule_status'] ?? '-').toString()),
                            PopupMenuButton<String>(
                              onSelected: (value) {
                                if (value == 'edit') {
                                  _openUpsert(bundle, initial: schedule);
                                }
                                if (value == 'delete') {
                                  _delete(scheduleId);
                                }
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(value: 'edit', child: Text('Edit')),
                                PopupMenuItem(value: 'delete', child: Text('Delete')),
                              ],
                            ),
                          ],
                        ),
                        onTap: () => _openUpsert(bundle, initial: schedule),
                      ),
                    ),
                  );
                }),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = _buildBody();

    if (widget.embedded) {
      return Column(
        children: [
          AdminModuleHeader(
            icon: Icons.calendar_month_outlined,
            title: 'Maintenance Schedule',
            subtitle: 'Track recurring service plans, mileage triggers, and future due dates.',
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
                  final bundle = await _future;
                  if (!mounted) return;
                  await _openUpsert(bundle);
                },
                icon: const Icon(Icons.add),
                label: const Text('Create schedule'),
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
        title: const Text('Maintenance Schedule'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: body,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final bundle = await _future;
          if (!mounted) return;
          await _openUpsert(bundle);
        },
        icon: const Icon(Icons.add),
        label: const Text('Create schedule'),
      ),
    );
  }
}

class _MaintenanceBundle {
  const _MaintenanceBundle({
    required this.schedules,
    required this.vehicles,
    required this.vendors,
  });

  final List<Map<String, dynamic>> schedules;
  final List<Map<String, dynamic>> vehicles;
  final List<Map<String, dynamic>> vendors;
}

class _ScheduleFormPage extends StatefulWidget {
  const _ScheduleFormPage({
    required this.service,
    required this.vehicles,
    required this.vendors,
    this.initial,
  });

  final FleetAdminService service;
  final List<Map<String, dynamic>> vehicles;
  final List<Map<String, dynamic>> vendors;
  final Map<String, dynamic>? initial;

  @override
  State<_ScheduleFormPage> createState() => _ScheduleFormPageState();
}

class _ScheduleFormPageState extends State<_ScheduleFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _mileageController = TextEditingController();
  final _notesController = TextEditingController();

  bool _saving = false;
  DateTime? _triggerDate;
  DateTime? _nextDate;
  String? _vehicleId;
  String? _vendorId;
  String _scheduleType = 'Preventive Maintenance';
  String _status = 'Scheduled';

  @override
  void initState() {
    super.initState();
    if (widget.vehicles.isNotEmpty) {
      _vehicleId = widget.vehicles.first['vehicle_id']?.toString();
    }

    final initial = widget.initial;
    if (initial != null) {
      final vehicleId = initial['vehicle_id']?.toString();
      final vendorId = initial['vendor_id']?.toString();
      _vehicleId = widget.vehicles.any((row) => row['vehicle_id'].toString() == vehicleId)
          ? vehicleId
          : _vehicleId;
      _vendorId = widget.vendors.any((row) => row['vendor_id'].toString() == vendorId)
          ? vendorId
          : null;
      _scheduleType = (initial['schedule_type'] ?? 'Preventive Maintenance').toString();
      _status = (initial['schedule_status'] ?? 'Scheduled').toString();
      _mileageController.text = widgetText(initial['trigger_mileage']) == '-' ? '' : widgetText(initial['trigger_mileage']);
      _notesController.text = (initial['notes'] ?? '').toString();
      _triggerDate = parseDate(initial['trigger_date']);
      _nextDate = parseDate(initial['next_maintenance_date']);
    }
  }

  @override
  void dispose() {
    _mileageController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool isTrigger}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: (isTrigger ? _triggerDate : _nextDate) ?? DateTime.now(),
      firstDate: DateTime(2024, 1, 1),
      lastDate: DateTime(2035, 12, 31),
    );
    if (picked == null) return;
    setState(() {
      if (isTrigger) {
        _triggerDate = picked;
      } else {
        _nextDate = picked;
      }
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if ((_vehicleId ?? '').trim().isEmpty) return;

    setState(() => _saving = true);
    try {
      await widget.service.upsertMaintenanceSchedule(
        scheduleId: widget.initial?['schedule_id']?.toString(),
        vehicleId: _vehicleId!,
        vendorId: _vendorId,
        scheduleType: _scheduleType,
        triggerMileage: int.tryParse(_mileageController.text.trim()) ?? 0,
        triggerDate: _triggerDate,
        nextMaintenanceDate: _nextDate,
        scheduleStatus: _status,
        notes: _notesController.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.initial == null ? 'Schedule created' : 'Schedule updated')),
      );
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.service.explainError(error)),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.initial == null ? 'Create Schedule' : 'Edit Schedule'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            if (widget.vehicles.isEmpty)
              const _MaintenanceEmptyCard(message: 'Add vehicles first before creating maintenance schedules.')
            else
              DropdownButtonFormField<String>(
                value: widget.vehicles.any((row) => row['vehicle_id'].toString() == _vehicleId) ? _vehicleId : null,
                decoration: const InputDecoration(labelText: 'Vehicle'),
                items: widget.vehicles
                    .map(
                      (vehicle) => DropdownMenuItem<String>(
                    value: vehicle['vehicle_id'].toString(),
                    child: Text(widget.service.vehicleLabel(vehicle)),
                  ),
                )
                    .toList(),
                onChanged: (value) => setState(() => _vehicleId = value),
                validator: (value) => (value == null || value.trim().isEmpty) ? 'Required' : null,
              ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: _scheduleType,
              decoration: const InputDecoration(labelText: 'Schedule Type'),
              items: const [
                DropdownMenuItem(value: 'Preventive Maintenance', child: Text('Preventive Maintenance')),
                DropdownMenuItem(value: 'Inspection', child: Text('Inspection')),
                DropdownMenuItem(value: 'Tyre Rotation', child: Text('Tyre Rotation')),
                DropdownMenuItem(value: 'Oil Change', child: Text('Oil Change')),
              ],
              onChanged: (value) => setState(() => _scheduleType = value ?? 'Preventive Maintenance'),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String?>(
              value: widget.vendors.any((row) => row['vendor_id'].toString() == _vendorId) ? _vendorId : null,
              decoration: const InputDecoration(labelText: 'Preferred Vendor (optional)'),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('No vendor assigned')),
                ...widget.vendors.map(
                      (vendor) => DropdownMenuItem<String?>(
                    value: vendor['vendor_id'].toString(),
                    child: Text(widget.service.vendorLabel(vendor)),
                  ),
                ),
              ],
              onChanged: (value) => setState(() => _vendorId = value),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _mileageController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Trigger Mileage'),
            ),
            const SizedBox(height: 10),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Trigger Date'),
              subtitle: Text(dateText(_triggerDate)),
              trailing: Wrap(
                spacing: 8,
                children: [
                  if (_triggerDate != null)
                    IconButton(
                      onPressed: () => setState(() => _triggerDate = null),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  OutlinedButton(
                    onPressed: () => _pickDate(isTrigger: true),
                    child: const Text('Pick date'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Next Maintenance Date'),
              subtitle: Text(dateText(_nextDate)),
              trailing: Wrap(
                spacing: 8,
                children: [
                  if (_nextDate != null)
                    IconButton(
                      onPressed: () => setState(() => _nextDate = null),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  OutlinedButton(
                    onPressed: () => _pickDate(isTrigger: false),
                    child: const Text('Pick date'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: _status,
              decoration: const InputDecoration(labelText: 'Status'),
              items: const [
                DropdownMenuItem(value: 'Scheduled', child: Text('Scheduled')),
                DropdownMenuItem(value: 'In Progress', child: Text('In Progress')),
                DropdownMenuItem(value: 'Completed', child: Text('Completed')),
                DropdownMenuItem(value: 'Cancelled', child: Text('Cancelled')),
                DropdownMenuItem(value: 'Overdue', child: Text('Overdue')),
              ],
              onChanged: (value) => setState(() => _status = value ?? 'Scheduled'),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _notesController,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Notes'),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.save_outlined),
              label: Text(widget.initial == null ? 'Create schedule' : 'Save changes'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MaintenanceSqlError extends StatelessWidget {
  const _MaintenanceSqlError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Maintenance setup required',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(message),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: Colors.black.withOpacity(0.05),
          ),
          child: SelectableText(FleetAdminService.sqlSetup),
        ),
      ],
    );
  }
}

class _MaintenanceEmptyCard extends StatelessWidget {
  const _MaintenanceEmptyCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return AdminCard(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Text(message),
      ),
    );
  }
}

String widgetText(dynamic value) {
  final text = value == null ? '' : value.toString().trim();
  return text.isEmpty ? '-' : text;
}

DateTime? parseDate(dynamic raw) {
  if (raw == null) return null;
  if (raw is DateTime) return raw;
  return DateTime.tryParse(raw.toString());
}

String dateText(dynamic raw) {
  final value = parseDate(raw);
  if (value == null) return '-';
  return '${value.day}/${value.month}/${value.year}';
}
