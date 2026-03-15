import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/fleet_admin_service.dart';
import '../services/job_order_module_service.dart';

class VendorServiceCostPage extends StatefulWidget {
  const VendorServiceCostPage({super.key, this.vendorId, this.initialJobOrderId});

  final String? vendorId;
  final String? initialJobOrderId;

  @override
  State<VendorServiceCostPage> createState() => _VendorServiceCostPageState();
}

class _VendorServiceCostPageState extends State<VendorServiceCostPage> {
  SupabaseClient get _supa => Supabase.instance.client;

  late final FleetAdminService _adminService;
  late final JobOrderModuleService _jobService;
  late Future<_VendorCostBundle> _future;

  @override
  void initState() {
    super.initState();
    _adminService = FleetAdminService(_supa);
    _jobService = JobOrderModuleService(_supa);
    _future = _load();
  }

  String _read(dynamic value) => value == null ? '' : value.toString().trim();

  Future<Map<String, dynamic>?> _resolveVendor() async {
    final user = _supa.auth.currentUser;
    if (user == null) return null;

    final requestedId = _read(widget.vendorId);
    if (requestedId.isNotEmpty) {
      try {
        final row = await _supa
            .from('vendor')
            .select('*')
            .eq('vendor_id', requestedId)
            .limit(1)
            .maybeSingle();
        if (row != null) return Map<String, dynamic>.from(row as Map);
      } catch (_) {}
    }

    try {
      final row = await _supa
          .from('vendor')
          .select('*')
          .eq('auth_uid', user.id)
          .order('vendor_id', ascending: false)
          .limit(1)
          .maybeSingle();
      if (row != null) return Map<String, dynamic>.from(row as Map);
    } catch (_) {}

    final email = _read(user.email).toLowerCase();
    if (email.isNotEmpty) {
      try {
        final row = await _supa
            .from('vendor')
            .select('*')
            .eq('vendor_email', email)
            .order('vendor_id', ascending: false)
            .limit(1)
            .maybeSingle();
        if (row != null) return Map<String, dynamic>.from(row as Map);
      } catch (_) {}
    }

    return null;
  }

  Future<_VendorCostBundle> _load() async {
    final vendor = await _resolveVendor();
    if (vendor == null) {
      throw Exception('Vendor profile not found. Please contact admin to verify your vendor account link.');
    }

    final vendorId = _read(vendor['vendor_id']);
    final jobs = await _jobService.fetchJobOrders(vendorId: vendorId);
    final costs = await _adminService.fetchServiceCosts(vendorId: vendorId);
    final vehicles = await _jobService.fetchVehicles();
    final vehicleMap = _jobService.indexBy(vehicles, 'vehicle_id');
    final jobMap = _jobService.indexBy(jobs, 'job_order_id');

    return _VendorCostBundle(
      vendor: vendor,
      jobs: jobs,
      costs: costs,
      vehicleMap: vehicleMap,
      jobMap: jobMap,
    );
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _load();
    });
    await _future;
  }

  Future<void> _openUpsert(_VendorCostBundle bundle, {Map<String, dynamic>? initial, String? initialJobOrderId}) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _VendorServiceCostFormPage(
          service: _adminService,
          jobOrders: bundle.jobs,
          vendor: bundle.vendor,
          initial: initial,
          initialJobOrderId: initialJobOrderId,
        ),
      ),
    );
    if (saved == true) {
      await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Service Cost'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: FutureBuilder<_VendorCostBundle>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(snapshot.error.toString()),
              ),
            );
          }

          final bundle = snapshot.data;
          if (bundle == null) {
            return const Center(child: Text('No vendor cost data found.'));
          }

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
              children: [
                Text(
                  'Service Cost',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text(
                  'Submit labour, parts, invoice, and cost notes for the job orders assigned to your team.',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    FilledButton.icon(
                      onPressed: bundle.jobs.isEmpty
                          ? null
                          : () => _openUpsert(
                        bundle,
                        initialJobOrderId: _read(widget.initialJobOrderId).isEmpty ? null : widget.initialJobOrderId,
                      ),
                      icon: const Icon(Icons.add),
                      label: const Text('Add Cost'),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${bundle.costs.length} cost record${bundle.costs.length == 1 ? '' : 's'}',
                        textAlign: TextAlign.right,
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (bundle.jobs.isEmpty)
                  const _VendorCostEmptyCard(
                    message: 'No assigned job orders yet. Once a leaser assigns a job order to your vendor account, you can submit the service cost here.',
                  )
                else if (bundle.costs.isEmpty)
                  const _VendorCostEmptyCard(
                    message: 'No service cost submitted yet. Add the labour, parts, tax, invoice, and cost notes for your assigned jobs here.',
                  )
                else
                  ...bundle.costs.map((cost) {
                    final costId = _read(cost['service_cost_id']);
                    final job = bundle.jobMap[_read(cost['job_order_id'])];
                    final vehicle = job == null ? null : bundle.vehicleMap[_read(job['vehicle_id'])];
                    final vehicleLabel = vehicle == null ? (job == null ? '' : _read(job['vehicle_id'])) : _jobService.vehicleLabel(vehicle);
                    final labour = _money(cost['labour_cost']);
                    final parts = _money(cost['parts_cost']);
                    final misc = _money(cost['misc_cost']);
                    final tax = _money(cost['tax_cost']);
                    final invoiceRef = _read(cost['invoice_ref']);
                    final notes = _read(cost['notes']);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: () => _openUpsert(bundle, initial: cost),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      costId.isEmpty ? 'Service Cost' : costId,
                                      style: const TextStyle(fontWeight: FontWeight.w900),
                                    ),
                                  ),
                                  _VendorPaymentChip(status: _read(cost['payment_status']).isEmpty ? 'Pending' : _read(cost['payment_status'])),
                                ],
                              ),
                              const SizedBox(height: 8),
                              _VendorDetailRow(label: 'Job Order', value: job == null || _read(job['job_order_id']).isEmpty ? _read(cost['job_order_id']) : _read(job['job_order_id'])),
                              _VendorDetailRow(label: 'Vehicle', value: vehicleLabel.isEmpty ? '-' : vehicleLabel),
                              _VendorDetailRow(label: 'Invoice', value: invoiceRef.isEmpty ? '-' : invoiceRef),
                              _VendorDetailRow(label: 'Service Date', value: _vendorDateText(cost['service_date'])),
                              _VendorDetailRow(label: 'Labour', value: labour),
                              _VendorDetailRow(label: 'Parts', value: parts),
                              _VendorDetailRow(label: 'Misc', value: misc),
                              _VendorDetailRow(label: 'Tax', value: tax),
                              if (notes.isNotEmpty)
                                _VendorDetailRow(label: 'Notes', value: notes),
                              _VendorDetailRow(label: 'Total Cost', value: _money(cost['total_cost'])),
                              const SizedBox(height: 10),
                              Align(
                                alignment: Alignment.centerRight,
                                child: OutlinedButton.icon(
                                  onPressed: () => _openUpsert(bundle, initial: cost),
                                  icon: const Icon(Icons.edit_outlined),
                                  label: const Text('Edit Cost'),
                                ),
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
        },
      ),
    );
  }
}

class _VendorCostBundle {
  const _VendorCostBundle({
    required this.vendor,
    required this.jobs,
    required this.costs,
    required this.vehicleMap,
    required this.jobMap,
  });

  final Map<String, dynamic> vendor;
  final List<Map<String, dynamic>> jobs;
  final List<Map<String, dynamic>> costs;
  final Map<String, Map<String, dynamic>> vehicleMap;
  final Map<String, Map<String, dynamic>> jobMap;
}

class _VendorServiceCostFormPage extends StatefulWidget {
  const _VendorServiceCostFormPage({
    required this.service,
    required this.jobOrders,
    required this.vendor,
    this.initial,
    this.initialJobOrderId,
  });

  final FleetAdminService service;
  final List<Map<String, dynamic>> jobOrders;
  final Map<String, dynamic> vendor;
  final Map<String, dynamic>? initial;
  final String? initialJobOrderId;

  @override
  State<_VendorServiceCostFormPage> createState() => _VendorServiceCostFormPageState();
}

class _VendorServiceCostFormPageState extends State<_VendorServiceCostFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _labourController = TextEditingController();
  final _partsController = TextEditingController();
  final _miscController = TextEditingController();
  final _taxController = TextEditingController();
  final _invoiceController = TextEditingController();
  final _notesController = TextEditingController();

  String? _jobOrderId;
  String _paymentStatus = 'Pending';
  DateTime? _serviceDate;
  bool _saving = false;

  String _read(dynamic value) => value == null ? '' : value.toString().trim();

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial != null) {
      _jobOrderId = _read(initial['job_order_id']);
      _labourController.text = (initial['labour_cost'] ?? 0).toString();
      _partsController.text = (initial['parts_cost'] ?? 0).toString();
      _miscController.text = (initial['misc_cost'] ?? 0).toString();
      _taxController.text = (initial['tax_cost'] ?? 0).toString();
      _invoiceController.text = _read(initial['invoice_ref']);
      _notesController.text = _read(initial['notes']);
      _paymentStatus = _read(initial['payment_status']).isEmpty ? 'Pending' : _read(initial['payment_status']);
      _serviceDate = _vendorParseDate(initial['service_date']);
    } else {
      final requested = _read(widget.initialJobOrderId);
      if (requested.isNotEmpty && widget.jobOrders.any((row) => _read(row['job_order_id']) == requested)) {
        _jobOrderId = requested;
      }
    }
  }

  @override
  void dispose() {
    _labourController.dispose();
    _partsController.dispose();
    _miscController.dispose();
    _taxController.dispose();
    _invoiceController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickServiceDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _serviceDate ?? DateTime.now(),
      firstDate: DateTime(2024, 1, 1),
      lastDate: DateTime(2035, 12, 31),
    );
    if (picked == null) return;
    setState(() => _serviceDate = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if ((_jobOrderId ?? '').trim().isEmpty) return;

    setState(() => _saving = true);
    try {
      await widget.service.upsertServiceCost(
        serviceCostId: widget.initial?['service_cost_id']?.toString(),
        jobOrderId: _jobOrderId!,
        vendorId: _read(widget.vendor['vendor_id']),
        labourCost: double.tryParse(_labourController.text.trim()) ?? 0,
        partsCost: double.tryParse(_partsController.text.trim()) ?? 0,
        miscCost: double.tryParse(_miscController.text.trim()) ?? 0,
        taxCost: double.tryParse(_taxController.text.trim()) ?? 0,
        invoiceRef: _invoiceController.text,
        paymentStatus: _paymentStatus,
        serviceDate: _serviceDate,
        notes: _notesController.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.initial == null ? 'Service cost submitted' : 'Service cost updated')),
      );
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.service.explainError(error)), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.initial == null ? 'Add Service Cost' : 'Edit Service Cost')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            InputDecorator(
              decoration: const InputDecoration(labelText: 'Vendor'),
              child: Text(_read(widget.vendor['vendor_name']).isEmpty ? '-' : _read(widget.vendor['vendor_name'])),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: widget.jobOrders.any((row) => _read(row['job_order_id']) == _jobOrderId) ? _jobOrderId : null,
              decoration: const InputDecoration(labelText: 'Assigned Job Order'),
              items: widget.jobOrders
                  .map(
                    (job) => DropdownMenuItem<String>(
                  value: _read(job['job_order_id']),
                  child: Text('${_read(job['job_order_id'])} - ${_read(job['job_type']).isEmpty ? 'General Service' : _read(job['job_type'])}'),
                ),
              )
                  .toList(),
              onChanged: (value) => setState(() => _jobOrderId = value),
              validator: (value) => (value == null || value.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _labourController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Labour Cost'),
                    validator: (value) => (value == null || value.trim().isEmpty) ? 'Required' : null,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: _partsController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Parts Cost'),
                    validator: (value) => (value == null || value.trim().isEmpty) ? 'Required' : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _miscController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Misc Cost'),
                    validator: (value) => (value == null || value.trim().isEmpty) ? 'Required' : null,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: _taxController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Tax Cost'),
                    validator: (value) => (value == null || value.trim().isEmpty) ? 'Required' : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Service Date'),
              subtitle: Text(_vendorDateText(_serviceDate)),
              trailing: Wrap(
                spacing: 8,
                children: [
                  if (_serviceDate != null)
                    IconButton(
                      onPressed: () => setState(() => _serviceDate = null),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  OutlinedButton(
                    onPressed: _pickServiceDate,
                    child: const Text('Pick date'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _invoiceController,
              decoration: const InputDecoration(labelText: 'Invoice Reference'),
              validator: (value) => (value == null || value.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: _paymentStatus,
              decoration: const InputDecoration(labelText: 'Payment Status'),
              items: const [
                DropdownMenuItem(value: 'Pending', child: Text('Pending')),
                DropdownMenuItem(value: 'Paid', child: Text('Paid')),
                DropdownMenuItem(value: 'Disputed', child: Text('Disputed')),
              ],
              onChanged: (value) => setState(() => _paymentStatus = value ?? 'Pending'),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _notesController,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Cost Description / Notes'),
              validator: (value) => (value == null || value.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.save_outlined),
              label: Text(widget.initial == null ? 'Submit Service Cost' : 'Save changes'),
            ),
          ],
        ),
      ),
    );
  }
}

class _VendorCostEmptyCard extends StatelessWidget {
  const _VendorCostEmptyCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Text(message),
    );
  }
}

class _VendorDetailRow extends StatelessWidget {
  const _VendorDetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _VendorPaymentChip extends StatelessWidget {
  const _VendorPaymentChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final normalized = status.trim().toLowerCase();
    Color tint = Colors.orange;
    if (normalized == 'paid') tint = Colors.green;
    if (normalized == 'disputed') tint = Colors.redAccent;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tint.withValues(alpha: 0.2)),
      ),
      child: Text(
        status,
        style: TextStyle(color: tint, fontWeight: FontWeight.w700),
      ),
    );
  }
}

String _money(dynamic value) {
  final number = value is num ? value.toDouble() : double.tryParse(value.toString()) ?? 0;
  return 'RM ${number.toStringAsFixed(2)}';
}

DateTime? _vendorParseDate(dynamic raw) {
  if (raw == null) return null;
  if (raw is DateTime) return raw;
  return DateTime.tryParse(raw.toString());
}

String _vendorDateText(dynamic raw) {
  final value = _vendorParseDate(raw);
  if (value == null) return 'Not set';
  final day = value.day.toString().padLeft(2, '0');
  final month = value.month.toString().padLeft(2, '0');
  final year = value.year.toString();
  return '$day/$month/$year';
}



