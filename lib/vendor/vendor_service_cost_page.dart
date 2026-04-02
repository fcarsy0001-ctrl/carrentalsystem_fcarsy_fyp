import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../admin/widgets/admin_ui.dart';
import '../payments/service_job_payment_history_page.dart';
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



  Future<_VendorCostBundle> _load() async {
    final vendor = await _jobService.resolveCurrentVendor(requestedVendorId: widget.vendorId);
    if (vendor == null) {
      throw Exception('Vendor profile not found. Please contact admin to verify your vendor account link.');
    }

    final vendorId = _read(vendor['vendor_id']);
    final jobs = await _jobService.fetchJobOrders(vendorId: vendorId);
    final costs = await _adminService.fetchServiceCosts(vendorId: vendorId);
    final vehicles = await _jobService.fetchVehicles();
    final vehicleMap = _jobService.indexBy(vehicles, 'vehicle_id');
    final jobMap = _jobService.indexBy(jobs, 'job_order_id');
    final payments = await _jobService.fetchServicePayments(vendorId: vendorId);
    final paymentsByCost = <String, List<Map<String, dynamic>>>{};
    for (final payment in payments) {
      final serviceCostId = _read(payment['service_cost_id']);
      if (serviceCostId.isEmpty) continue;
      paymentsByCost.putIfAbsent(serviceCostId, () => <Map<String, dynamic>>[]).add(payment);
    }

    return _VendorCostBundle(
      vendor: vendor,
      jobs: jobs,
      costs: costs,
      vehicleMap: vehicleMap,
      jobMap: jobMap,
      paymentsByCost: paymentsByCost,
    );
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _load();
    });
    await _future;
  }


  List<Map<String, dynamic>> _quotableJobOrders(
      _VendorCostBundle bundle, {
        String? keepJobOrderId,
      }) {
    final keepId = _read(keepJobOrderId);
    final quotedJobIds = bundle.costs.map((row) => _read(row['job_order_id'])).where((id) => id.isNotEmpty).toSet();
    return bundle.jobs.where((job) {
      final jobId = _read(job['job_order_id']);
      if (jobId.isEmpty) return false;
      if (keepId.isNotEmpty && jobId == keepId) return true;
      final status = _read(job['status']).toLowerCase();
      if (status == 'completed') return false;
      return !quotedJobIds.contains(jobId);
    }).toList();
  }

  Future<void> _openUpsert(_VendorCostBundle bundle, {Map<String, dynamic>? initial, String? initialJobOrderId}) async {
    final currentJobOrderId = initial == null ? _read(initialJobOrderId) : _read(initial['job_order_id']);
    final jobOrders = _quotableJobOrders(bundle, keepJobOrderId: currentJobOrderId);

    if (initial != null) {
      final relatedJob = bundle.jobMap[_read(initial['job_order_id'])];
      final relatedStatus = _read(relatedJob?['status']);
      if (relatedStatus == 'Completed') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Completed job orders are locked and cannot be priced again.')),
        );
        return;
      }
      if (_read(initial['payment_status']).toLowerCase() == 'paid') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('A paid service cost is locked and can no longer be edited by the vendor.')),
        );
        return;
      }
    } else if (jobOrders.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Every assigned job already has a service price or is completed.')),
      );
      return;
    }

    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _VendorServiceCostFormPage(
          service: _adminService,
          jobOrders: jobOrders,
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
  Future<void> _openHistory(String serviceCostId, String jobOrderId) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ServiceJobPaymentHistoryPage(
          service: _jobService,
          title: 'Cost Payment History',
          vendorId: widget.vendorId,
          jobOrderId: jobOrderId,
          serviceCostId: serviceCostId,
        ),
      ),
    );
    if (!mounted) return;
    await _refresh();
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

          final quotableJobs = _quotableJobOrders(bundle);
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
                  'Set labour, parts, misc, tax, and invoice details for assigned job orders. The leaser will review and pay these service costs from their side.',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    FilledButton.icon(
                      onPressed: quotableJobs.isEmpty
                          ? null
                          : () => _openUpsert(
                        bundle,
                        initialJobOrderId: _read(widget.initialJobOrderId).isEmpty ? null : widget.initialJobOrderId,
                      ),
                      icon: const Icon(Icons.add),
                      label: const Text('Set Price'),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${bundle.costs.length} quote${bundle.costs.length == 1 ? '' : 's'}',
                        textAlign: TextAlign.right,
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (bundle.jobs.isEmpty)
                  const _VendorCostEmptyCard(
                    message: 'No assigned job orders yet. Once a leaser assigns a job order to your vendor account, you can set the service cost here.',
                  )
                else if (bundle.costs.isEmpty && quotableJobs.isEmpty)
                  const _VendorCostEmptyCard(
                    message: 'All assigned job orders already have a service price or are completed.',
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
                    final paymentStatus = _read(cost['payment_status']).isEmpty ? 'Pending' : _read(cost['payment_status']);
                    final historyCount = bundle.paymentsByCost[costId]?.length ?? 0;
                    final isPaid = paymentStatus.toLowerCase() == 'paid';
                    final jobStatus = job == null ? '' : _read(job['status']);
                    final isCompletedJob = jobStatus == 'Completed';
                    final canEditQuote = !isPaid && !isCompletedJob;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: AdminCard(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
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
                                  AdminStatusChip(status: paymentStatus),
                                ],
                              ),
                              const SizedBox(height: 10),
                              _VendorDetailRow(label: 'Job Order', value: job == null || _read(job['job_order_id']).isEmpty ? _read(cost['job_order_id']) : _read(job['job_order_id'])),
                              _VendorDetailRow(label: 'Vehicle', value: vehicleLabel.isEmpty ? '-' : vehicleLabel),
                              _VendorDetailRow(label: 'Service Date', value: _vendorDateText(cost['service_date'])),
                              _VendorDetailRow(label: 'Labour', value: labour),
                              _VendorDetailRow(label: 'Parts', value: parts),
                              _VendorDetailRow(label: 'Misc', value: misc),
                              _VendorDetailRow(label: 'Tax', value: tax),
                              _VendorDetailRow(label: 'Invoice', value: invoiceRef.isEmpty ? '-' : invoiceRef),
                              if (notes.isNotEmpty)
                                _VendorDetailRow(label: 'Notes', value: notes),
                              _VendorDetailRow(label: 'Total', value: _money(cost['total_cost'])),
                              _VendorDetailRow(label: 'Payments', value: '$historyCount record${historyCount == 1 ? '' : 's'}'),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                children: [
                                  OutlinedButton.icon(
                                    onPressed: () => _openHistory(costId, _read(cost['job_order_id'])),
                                    icon: const Icon(Icons.history_rounded),
                                    label: const Text('Payment History'),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: canEditQuote ? () => _openUpsert(bundle, initial: cost) : null,
                                    icon: const Icon(Icons.edit_outlined),
                                    label: const Text('Edit Quote'),
                                  ),
                                ],
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
    required this.paymentsByCost,
  });

  final Map<String, dynamic> vendor;
  final List<Map<String, dynamic>> jobs;
  final List<Map<String, dynamic>> costs;
  final Map<String, Map<String, dynamic>> vehicleMap;
  final Map<String, Map<String, dynamic>> jobMap;
  final Map<String, List<Map<String, dynamic>>> paymentsByCost;
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
  DateTime? _serviceDate;
  bool _saving = false;

  String _read(dynamic value) => value == null ? '' : value.toString().trim();

  String? _costValidator(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return 'Required';
    final number = double.tryParse(text);
    if (number == null) return 'Numbers only';
    if (number < 0) return 'Cannot be negative';
    return null;
  }


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
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final initialDate = _serviceDate != null && !_serviceDate!.isBefore(today)
        ? _serviceDate!
        : today;
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: today,
      lastDate: DateTime(2035, 12, 31),
    );
    if (picked == null) return;
    setState(() => _serviceDate = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if ((_jobOrderId ?? '').trim().isEmpty) return;
    if (_serviceDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select the service date for this quote.')),
      );
      return;
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final selectedDate = DateTime(_serviceDate!.year, _serviceDate!.month, _serviceDate!.day);
    if (selectedDate.isBefore(today)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Service date cannot be in the past.')),
      );
      return;
    }

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
        paymentStatus: widget.initial == null
            ? 'Pending'
            : (_read(widget.initial!['payment_status']).isEmpty ? 'Pending' : _read(widget.initial!['payment_status'])),
        serviceDate: _serviceDate,
        notes: _notesController.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.initial == null ? 'Service cost submitted to leaser.' : 'Service cost updated.')),
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
      appBar: AppBar(title: Text(widget.initial == null ? 'Set Service Price' : 'Edit Service Price')),
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
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                    decoration: const InputDecoration(labelText: 'Labour Cost'),
                    validator: _costValidator,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: _partsController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                    decoration: const InputDecoration(labelText: 'Parts Cost'),
                    validator: _costValidator,
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
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                    decoration: const InputDecoration(labelText: 'Misc Cost'),
                    validator: _costValidator,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: _taxController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                    decoration: const InputDecoration(labelText: 'Tax Cost'),
                    validator: _costValidator,
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
              label: Text(widget.initial == null ? 'Send Price to Leaser' : 'Save changes'),
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
    return AdminCard(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Text(message),
      ),
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
