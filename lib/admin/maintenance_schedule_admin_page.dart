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
  DateTime _visibleMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);

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
    setState(() {
      _future = _load();
    });
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

  DateTime? _scheduleDate(Map<String, dynamic> schedule) {
    return parseDate(schedule['next_maintenance_date']) ?? parseDate(schedule['trigger_date']);
  }

  String _calendarStatus(Map<String, dynamic> schedule) {
    final raw = (schedule['schedule_status'] ?? '').toString().trim();
    final normalized = raw.toLowerCase();
    if (normalized == 'in progress') return 'In Progress';
    if (normalized == 'completed') return 'Completed';
    if (normalized == 'overdue') return 'Overdue';
    if (normalized == 'cancelled') return 'Cancelled';

    final date = _scheduleDate(schedule);
    if (date != null) {
      final due = DateTime(date.year, date.month, date.day);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      if (due.isBefore(today)) return 'Overdue';
    }
    return 'Scheduled';
  }

  String _monthLabel(DateTime month) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return months[month.month - 1] + ' ' + month.year.toString();
  }

  Color _calendarStatusColor(String status) {
    switch (status) {
      case 'Scheduled':
        return Colors.blue;
      case 'In Progress':
        return Colors.orange;
      case 'Completed':
        return Colors.green;
      case 'Overdue':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _scheduleVehicleLabel(Map<String, dynamic>? vehicle, Map<String, dynamic> schedule) {
    final plate = (vehicle?['vehicle_plate_no'] ?? '').toString().trim();
    if (plate.isNotEmpty) return plate;
    return (schedule['vehicle_id'] ?? '-').toString();
  }

  String _s(dynamic value) => value == null ? '' : value.toString().trim();

  void _changeMonth(int offset) {
    setState(() {
      _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month + offset, 1);
    });
  }

  Widget _buildSummaryTile(String label, int value, Color color) {
    return Container(
      width: 158,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: color.withOpacity(0.08),
        border: Border.all(color: color.withOpacity(0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value.toString(),
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }

  Future<void> _showDayScheduleDetails(
      DateTime date,
      List<_CalendarScheduleEntry> entries,
      ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
            child: ListView(
              shrinkWrap: true,
              children: [
                Text(
                  'Maintenance on ${date.day}/${date.month}/${date.year}',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                Text(
                  '${entries.length} scheduled item${entries.length == 1 ? '' : 's'}',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
                ...entries.map(
                      (entry) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: AdminCard(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    entry.scheduleType,
                                    style: const TextStyle(fontWeight: FontWeight.w800),
                                  ),
                                ),
                                AdminStatusChip(status: entry.status),
                              ],
                            ),
                            const SizedBox(height: 10),
                            _DetailLine(label: 'Schedule ID', value: entry.scheduleId.isEmpty ? '-' : entry.scheduleId),
                            _DetailLine(label: 'Vehicle', value: entry.label),
                            _DetailLine(label: 'Vendor', value: entry.vendorLabel.isEmpty ? 'Not assigned' : entry.vendorLabel),
                            _DetailLine(label: 'Date', value: entry.dateLabel),
                            if (entry.notes.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(
                                'Notes',
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(entry.notes),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCalendarSection(
      _MaintenanceBundle bundle,
      Map<String, Map<String, dynamic>> vehicleMap,
      Map<String, Map<String, dynamic>> vendorMap,
      ) {
    final entries = <_CalendarScheduleEntry>[];
    for (final schedule in bundle.schedules) {
      final date = _scheduleDate(schedule);
      if (date == null) continue;
      final vehicle = vehicleMap[(schedule['vehicle_id'] ?? '').toString()];
      final vendor = vendorMap[(schedule['vendor_id'] ?? '').toString()];
      entries.add(
        _CalendarScheduleEntry(
          date: DateTime(date.year, date.month, date.day),
          label: _scheduleVehicleLabel(vehicle, schedule),
          status: _calendarStatus(schedule),
          scheduleId: _s(schedule['schedule_id']),
          scheduleType: _s(schedule['schedule_type']).isEmpty ? 'Maintenance Schedule' : _s(schedule['schedule_type']),
          vendorLabel: _service.vendorLabel(vendor),
          dateLabel: dateText(date),
          notes: _s(schedule['notes']),
        ),
      );
    }

    final scheduledCount = bundle.schedules.where((schedule) => _calendarStatus(schedule) == 'Scheduled').length;
    final inProgressCount = bundle.schedules.where((schedule) => _calendarStatus(schedule) == 'In Progress').length;
    final completedCount = bundle.schedules.where((schedule) => _calendarStatus(schedule) == 'Completed').length;
    final overdueCount = bundle.schedules.where((schedule) => _calendarStatus(schedule) == 'Overdue').length;

    final visibleEntries = entries
        .where((entry) => entry.date.year == _visibleMonth.year && entry.date.month == _visibleMonth.month)
        .toList();
    final byDay = <int, List<_CalendarScheduleEntry>>{};
    for (final entry in visibleEntries) {
      byDay.putIfAbsent(entry.date.day, () => <_CalendarScheduleEntry>[]).add(entry);
    }

    final firstDay = DateTime(_visibleMonth.year, _visibleMonth.month, 1);
    final daysInMonth = DateTime(_visibleMonth.year, _visibleMonth.month + 1, 0).day;
    final leadingBlank = firstDay.weekday % 7;
    final totalCells = leadingBlank + daysInMonth;
    final trailingBlank = totalCells % 7 == 0 ? 0 : 7 - (totalCells % 7);
    final cellCount = totalCells + trailingBlank;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _buildSummaryTile('Scheduled', scheduledCount, Colors.blue),
            _buildSummaryTile('In Progress', inProgressCount, Colors.orange),
            _buildSummaryTile('Completed', completedCount, Colors.green),
            _buildSummaryTile('Overdue', overdueCount, Colors.red),
          ],
        ),
        const SizedBox(height: 14),
        AdminCard(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => _changeMonth(-1),
                      icon: const Icon(Icons.chevron_left_rounded),
                    ),
                    Expanded(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.calendar_month_outlined, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            _monthLabel(_visibleMonth),
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => _changeMonth(1),
                      icon: const Icon(Icons.chevron_right_rounded),
                    ),
                  ],
                ),
                const Divider(height: 24),
                Row(
                  children: const [
                    Expanded(child: Center(child: Text('Sun', style: TextStyle(fontWeight: FontWeight.w700)))),
                    Expanded(child: Center(child: Text('Mon', style: TextStyle(fontWeight: FontWeight.w700)))),
                    Expanded(child: Center(child: Text('Tue', style: TextStyle(fontWeight: FontWeight.w700)))),
                    Expanded(child: Center(child: Text('Wed', style: TextStyle(fontWeight: FontWeight.w700)))),
                    Expanded(child: Center(child: Text('Thu', style: TextStyle(fontWeight: FontWeight.w700)))),
                    Expanded(child: Center(child: Text('Fri', style: TextStyle(fontWeight: FontWeight.w700)))),
                    Expanded(child: Center(child: Text('Sat', style: TextStyle(fontWeight: FontWeight.w700)))),
                  ],
                ),
                const SizedBox(height: 8),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: cellCount,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 7,
                    mainAxisExtent: 64,
                    mainAxisSpacing: 6,
                    crossAxisSpacing: 6,
                  ),
                  itemBuilder: (context, index) {
                    final dayNumber = index - leadingBlank + 1;
                    if (dayNumber <= 0 || dayNumber > daysInMonth) {
                      return Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                        ),
                      );
                    }

                    final dayEntries = byDay[dayNumber] ?? const <_CalendarScheduleEntry>[];
                    final isToday = today.year == _visibleMonth.year &&
                        today.month == _visibleMonth.month &&
                        today.day == dayNumber;
                    final previewText = dayEntries.isEmpty
                        ? ''
                        : (dayEntries.length == 1 ? dayEntries.first.label : '${dayEntries.length} schedules');
                    final previewColor = dayEntries.isEmpty ? Colors.transparent : _calendarStatusColor(dayEntries.first.status);

                    return Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: dayEntries.isEmpty
                            ? null
                            : () => _showDayScheduleDetails(
                          DateTime(_visibleMonth.year, _visibleMonth.month, dayNumber),
                          dayEntries,
                        ),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isToday
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).colorScheme.outlineVariant,
                            ),
                            color: isToday
                                ? Theme.of(context).colorScheme.primaryContainer.withOpacity(0.16)
                                : null,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      dayNumber.toString(),
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        color: isToday ? Theme.of(context).colorScheme.primary : null,
                                      ),
                                    ),
                                  ),
                                  if (dayEntries.isNotEmpty)
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        color: previewColor,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                ],
                              ),
                              if (dayEntries.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(999),
                                    color: previewColor.withOpacity(0.14),
                                  ),
                                  child: Text(
                                    previewText,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: previewColor,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 9,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        AdminCard(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 16,
              runSpacing: 10,
              children: const [
                _LegendItem(label: 'Scheduled', color: Colors.blue),
                _LegendItem(label: 'In Progress', color: Colors.orange),
                _LegendItem(label: 'Completed', color: Colors.green),
                _LegendItem(label: 'Overdue', color: Colors.red),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
      ],
    );
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
              _buildCalendarSection(bundle, vehicleMap, vendorMap),
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

class _CalendarScheduleEntry {
  const _CalendarScheduleEntry({
    required this.date,
    required this.label,
    required this.status,
    required this.scheduleId,
    required this.scheduleType,
    required this.vendorLabel,
    required this.dateLabel,
    required this.notes,
  });

  final DateTime date;
  final String label;
  final String status;
  final String scheduleId;
  final String scheduleType;
  final String vendorLabel;
  final String dateLabel;
  final String notes;
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 118,
            child: Text(
              label,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Text(label),
      ],
    );
  }
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









