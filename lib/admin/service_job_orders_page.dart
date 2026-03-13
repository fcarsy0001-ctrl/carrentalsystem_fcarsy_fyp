import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/fleet_admin_service.dart';
import 'widgets/admin_ui.dart';

class ServiceJobOrdersPage extends StatefulWidget {
  const ServiceJobOrdersPage({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<ServiceJobOrdersPage> createState() => _ServiceJobOrdersPageState();
}

class _ServiceJobOrdersPageState extends State<ServiceJobOrdersPage> {
  SupabaseClient get _supa => Supabase.instance.client;

  late final FleetAdminService _service;
  late Future<_JobOrderBundle> _future;

  @override
  void initState() {
    super.initState();
    _service = FleetAdminService(_supa);
    _future = _load();
  }

  Future<_JobOrderBundle> _load() async {
    final jobs = await _service.fetchJobOrders();
    final vehicles = await _service.fetchVehicles();
    List<Map<String, dynamic>> vendors = const [];
    try {
      vendors = await _service.fetchVendors();
    } catch (_) {}
    return _JobOrderBundle(jobs: jobs, vehicles: vehicles, vendors: vendors);
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  Future<void> _openUpsert(_JobOrderBundle bundle, {Map<String, dynamic>? initial}) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _JobOrderFormPage(
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

  Future<void> _delete(String jobOrderId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete job order'),
        content: Text('Delete job order $jobOrderId?'),
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
      await _service.deleteJobOrder(jobOrderId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Job order deleted')),
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
    return FutureBuilder<_JobOrderBundle>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _AdminSqlErrorView(
            title: 'Service job orders need setup',
            message: _service.explainError(snapshot.error!),
          );
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
              if (bundle.jobs.isEmpty)
                const _EmptyCard(
                  message: 'No service job orders yet. Create the first maintenance request to start tracking service work.',
                )
              else
                ...bundle.jobs.map((job) {
                  final jobId = (job['job_order_id'] ?? '').toString();
                  final vehicle = vehicleMap[(job['vehicle_id'] ?? '').toString()];
                  final vendor = vendorMap[(job['vendor_id'] ?? '').toString()];
                  final preferredDate = _dateLabel(job['preferred_date']);
                  final estimated = _money(_service.readDouble(job, 'estimated_cost'));
                  final actual = _money(_service.readDouble(job, 'actual_cost'));

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: AdminCard(
                      child: ListTile(
                        title: Text(
                          (job['job_type'] ?? 'Service Job').toString(),
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: Text(
                          'ID: $jobId\n'
                          'Vehicle: ${_service.vehicleLabel(vehicle)}\n'
                          'Vendor: ${_service.vendorLabel(vendor)}\n'
                          'Priority: ${(job['priority'] ?? '-').toString()}  |  Preferred: $preferredDate\n'
                          'Estimated: $estimated  |  Actual: $actual',
                        ),
                        isThreeLine: true,
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            AdminStatusChip(status: (job['status'] ?? '-').toString()),
                            PopupMenuButton<String>(
                              onSelected: (value) {
                                if (value == 'edit') {
                                  _openUpsert(bundle, initial: job);
                                }
                                if (value == 'delete') {
                                  _delete(jobId);
                                }
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(value: 'edit', child: Text('Edit')),
                                PopupMenuItem(value: 'delete', child: Text('Delete')),
                              ],
                            ),
                          ],
                        ),
                        onTap: () => _openUpsert(bundle, initial: job),
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
            icon: Icons.build_circle_outlined,
            title: 'Service Job Orders',
            subtitle: 'Create, assign, and monitor maintenance or inspection requests.',
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
                label: const Text('Create job order'),
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
        title: const Text('Service Job Orders'),
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
        label: const Text('Create job order'),
      ),
    );
  }
}

class _JobOrderBundle {
  const _JobOrderBundle({
    required this.jobs,
    required this.vehicles,
    required this.vendors,
  });

  final List<Map<String, dynamic>> jobs;
  final List<Map<String, dynamic>> vehicles;
  final List<Map<String, dynamic>> vendors;
}

class _JobOrderFormPage extends StatefulWidget {
  const _JobOrderFormPage({
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
  State<_JobOrderFormPage> createState() => _JobOrderFormPageState();
}

class _JobOrderFormPageState extends State<_JobOrderFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _problemController = TextEditingController();
  final _estimatedController = TextEditingController(text: '0');
  final _actualController = TextEditingController(text: '0');
  final _remarksController = TextEditingController();

  bool _saving = false;
  DateTime? _preferredDate;
  String? _vehicleId;
  String? _vendorId;
  String _jobType = 'Inspection';
  String _priority = 'Medium';
  String _status = 'Pending';

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (widget.vehicles.isNotEmpty) {
      _vehicleId = widget.vehicles.first['vehicle_id']?.toString();
    }
    if (initial != null) {
      final vehicleId = initial['vehicle_id']?.toString();
      final vendorId = initial['vendor_id']?.toString();
      _vehicleId = widget.vehicles.any((row) => row['vehicle_id'].toString() == vehicleId)
          ? vehicleId
          : _vehicleId;
      _vendorId = widget.vendors.any((row) => row['vendor_id'].toString() == vendorId)
          ? vendorId
          : null;
      _jobType = (initial['job_type'] ?? 'Inspection').toString();
      _priority = (initial['priority'] ?? 'Medium').toString();
      _status = (initial['status'] ?? 'Pending').toString();
      _problemController.text = (initial['problem_description'] ?? '').toString();
      _estimatedController.text = (initial['estimated_cost'] ?? 0).toString();
      _actualController.text = (initial['actual_cost'] ?? 0).toString();
      _remarksController.text = (initial['remarks'] ?? '').toString();
      final rawDate = (initial['preferred_date'] ?? '').toString();
      _preferredDate = rawDate.isEmpty ? null : DateTime.tryParse(rawDate);
    }
  }

  @override
  void dispose() {
    _problemController.dispose();
    _estimatedController.dispose();
    _actualController.dispose();
    _remarksController.dispose();
    super.dispose();
  }

  Future<void> _pickPreferredDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _preferredDate ?? DateTime.now(),
      firstDate: DateTime(2024, 1, 1),
      lastDate: DateTime(2035, 12, 31),
    );
    if (picked == null) return;
    setState(() => _preferredDate = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if ((_vehicleId ?? '').trim().isEmpty) return;

    setState(() => _saving = true);
    try {
      await widget.service.upsertJobOrder(
        jobOrderId: widget.initial?['job_order_id']?.toString(),
        vehicleId: _vehicleId!,
        vendorId: _vendorId,
        jobType: _jobType,
        priority: _priority,
        problemDescription: _problemController.text,
        preferredDate: _preferredDate,
        status: _status,
        estimatedCost: double.tryParse(_estimatedController.text.trim()) ?? 0,
        actualCost: double.tryParse(_actualController.text.trim()) ?? 0,
        remarks: _remarksController.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.initial == null ? 'Job order created' : 'Job order updated')),
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
        title: Text(widget.initial == null ? 'Create Job Order' : 'Edit Job Order'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            if (widget.vehicles.isEmpty)
              const _EmptyCard(
                message: 'Add vehicles first before creating job orders.',
              )
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
              value: _jobType,
              decoration: const InputDecoration(labelText: 'Job Type'),
              items: const [
                DropdownMenuItem(value: 'Inspection', child: Text('Inspection')),
                DropdownMenuItem(value: 'Repair', child: Text('Repair')),
                DropdownMenuItem(value: 'Maintenance', child: Text('Maintenance')),
                DropdownMenuItem(value: 'Cleaning', child: Text('Cleaning')),
              ],
              onChanged: (value) => setState(() => _jobType = value ?? 'Inspection'),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: _priority,
              decoration: const InputDecoration(labelText: 'Priority'),
              items: const [
                DropdownMenuItem(value: 'Low', child: Text('Low')),
                DropdownMenuItem(value: 'Medium', child: Text('Medium')),
                DropdownMenuItem(value: 'High', child: Text('High')),
                DropdownMenuItem(value: 'Urgent', child: Text('Urgent')),
              ],
              onChanged: (value) => setState(() => _priority = value ?? 'Medium'),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String?>(
              value: widget.vendors.any((row) => row['vendor_id'].toString() == _vendorId) ? _vendorId : null,
              decoration: const InputDecoration(labelText: 'Vendor (optional)'),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('Unassigned')),
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
              controller: _problemController,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Problem Description'),
              validator: (value) => (value == null || value.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 10),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Preferred Date'),
              subtitle: Text(_preferredDate == null ? 'Not set' : _dateLabel(_preferredDate)),
              trailing: Wrap(
                spacing: 8,
                children: [
                  if (_preferredDate != null)
                    IconButton(
                      tooltip: 'Clear date',
                      onPressed: () => setState(() => _preferredDate = null),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  OutlinedButton(
                    onPressed: _pickPreferredDate,
                    child: const Text('Pick date'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _estimatedController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Estimated Cost'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: _actualController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Actual Cost'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: _status,
              decoration: const InputDecoration(labelText: 'Status'),
              items: const [
                DropdownMenuItem(value: 'Pending', child: Text('Pending')),
                DropdownMenuItem(value: 'In Progress', child: Text('In Progress')),
                DropdownMenuItem(value: 'Completed', child: Text('Completed')),
                DropdownMenuItem(value: 'Cancelled', child: Text('Cancelled')),
              ],
              onChanged: (value) => setState(() => _status = value ?? 'Pending'),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _remarksController,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Remarks'),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.save_outlined),
              label: Text(widget.initial == null ? 'Create job order' : 'Save changes'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminSqlErrorView extends StatelessWidget {
  const _AdminSqlErrorView({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
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

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.message});

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

String _dateLabel(dynamic raw) {
  if (raw == null) return '-';
  final value = raw is DateTime ? raw : DateTime.tryParse(raw.toString());
  if (value == null) return '-';
  return '${value.day}/${value.month}/${value.year}';
}

String _money(double value) => 'RM ${value.toStringAsFixed(2)}';
