import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../admin/widgets/admin_ui.dart';
import '../payments/service_job_payment_history_page.dart';
import '../services/job_order_module_service.dart';
import 'vendor_service_cost_page.dart';

class VendorJobOrdersPage extends StatefulWidget {
  const VendorJobOrdersPage({super.key, this.vendorId});

  final String? vendorId;

  @override
  State<VendorJobOrdersPage> createState() => _VendorJobOrdersPageState();
}

class _VendorJobOrdersPageState extends State<VendorJobOrdersPage> {
  SupabaseClient get _supa => Supabase.instance.client;

  late final JobOrderModuleService _service;
  late Future<_VendorJobsBundle> _future;

  @override
  void initState() {
    super.initState();
    _service = JobOrderModuleService(_supa);
    _future = _load();
  }

  String _s(dynamic value) => value == null ? '' : value.toString().trim();

  Future<_VendorJobsBundle> _load() async {
    final vendor = await _service.resolveCurrentVendor(requestedVendorId: widget.vendorId);
    if (vendor == null) {
      throw Exception('Vendor profile not found.');
    }

    final vendorId = _s(vendor['vendor_id']);
    final jobs = await _service.fetchJobOrders(vendorId: vendorId);
    final vehicles = await _service.fetchVehicles();
    final costs = await _service.fetchServiceCosts(
      vendorId: vendorId,
      jobOrderIds: jobs.map((row) => _s(row['job_order_id'])).where((id) => id.isNotEmpty).toList(),
    );

    final vehicleMap = _service.indexBy(vehicles, 'vehicle_id');
    final costsByJob = <String, List<Map<String, dynamic>>>{};
    for (final cost in costs) {
      final jobOrderId = _s(cost['job_order_id']);
      if (jobOrderId.isEmpty) continue;
      costsByJob.putIfAbsent(jobOrderId, () => <Map<String, dynamic>>[]).add(cost);
    }

    return _VendorJobsBundle(
      vendor: vendor,
      jobs: jobs,
      vehicleMap: vehicleMap,
      costsByJob: costsByJob,
    );
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _load();
    });
    await _future;
  }

  Future<void> _openSetPrice(String vendorId, String jobOrderId) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VendorServiceCostPage(vendorId: vendorId, initialJobOrderId: jobOrderId),
      ),
    );
    if (!mounted) return;
    await _refresh();
  }

  Future<void> _openHistory(String vendorId, String jobOrderId) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ServiceJobPaymentHistoryPage(
          service: _service,
          title: 'Service Payment History',
          vendorId: vendorId,
          jobOrderId: jobOrderId,
        ),
      ),
    );
    if (!mounted) return;
    await _refresh();
  }

  Future<String?> _promptRemarks(String newStatus) async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => _VendorStatusRemarksPage(newStatus: newStatus),
      ),
    );
    return result?.trim();
  }
  Future<void> _updateStatus(Map<String, dynamic> job, String newStatus) async {
    final remarks = await _promptRemarks(newStatus);
    if (remarks == null) return;
    if (remarks.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Remarks are required.')),
      );
      return;
    }

    if (newStatus == 'Completed') {
      final canComplete = await _service.canVendorCompleteJob(_s(job['job_order_id']));
      if (!mounted) return;
      if (!canComplete) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('The vendor can complete the job only after at least one service cost exists and all service costs are paid by the leaser.'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
    }

    try {
      await _service.updateJobStatus(
        jobOrderId: _s(job['job_order_id']),
        currentStatus: _s(job['status']),
        newStatus: newStatus,
        remarks: remarks,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Job order updated to $newStatus.')),
      );
      await _refresh();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_service.explainError(error)), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vendor Job Orders'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: FutureBuilder<_VendorJobsBundle>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(_service.explainError(snapshot.error!)),
              ),
            );
          }

          final bundle = snapshot.data;
          if (bundle == null) {
            return const Center(child: Text('No vendor job orders found.'));
          }

          if (bundle.jobs.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('No job orders have been assigned to this vendor yet.'),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
              children: [
                Text(
                  '${bundle.jobs.length} assigned job order${bundle.jobs.length == 1 ? '' : 's'}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                ...bundle.jobs.map((job) {
                  final jobOrderId = _s(job['job_order_id']);
                  final costs = bundle.costsByJob[jobOrderId] ?? const <Map<String, dynamic>>[];
                  final quote = costs.isEmpty ? null : costs.first;
                  final paidCount = costs.where((row) => _s(row['payment_status']).toLowerCase() == 'paid').length;
                  final hasQuote = quote != null;
                  final quoteIsPaid = hasQuote && _s(quote['payment_status']).toLowerCase() == 'paid';
                  final vehicle = bundle.vehicleMap[_s(job['vehicle_id'])];
                  final status = _s(job['status']).isEmpty ? 'Pending' : _s(job['status']);
                  final isPending = status == 'Pending';
                  final isInProgress = status == 'In Progress';
                  final isCompleted = status == 'Completed';
                  final canSetPrice = !hasQuote && !isCompleted;
                  final canComplete = hasQuote && quoteIsPaid;
                  final quotedTotal = hasQuote ? _money(quote['total_cost']) : 'No quote yet';
                  final paymentLabel = !hasQuote
                      ? 'Waiting for vendor quote'
                      : (costs.length > 1
                      ? 'Multiple legacy quote records exist'
                      : (quoteIsPaid ? 'Paid' : 'Pending payment'));

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
                                    jobOrderId,
                                    style: const TextStyle(fontWeight: FontWeight.w900),
                                  ),
                                ),
                                AdminStatusChip(status: status),
                              ],
                            ),
                            const SizedBox(height: 10),
                            _JobLine(label: 'Vehicle', value: vehicle == null ? _s(job['vehicle_id']) : _service.vehicleLabel(vehicle)),
                            _JobLine(label: 'Job Type', value: _s(job['job_type']).isEmpty ? '-' : _s(job['job_type'])),
                            _JobLine(label: 'Priority', value: _s(job['priority']).isEmpty ? '-' : _s(job['priority'])),
                            _JobLine(label: 'Preferred Date', value: _dateText(job['preferred_date'])),
                            _JobLine(label: 'Quoted Total', value: quotedTotal),
                            _JobLine(label: 'Payment', value: paymentLabel),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                if (canSetPrice)
                                  OutlinedButton.icon(
                                    onPressed: () => _openSetPrice(_s(bundle.vendor['vendor_id']), jobOrderId),
                                    icon: const Icon(Icons.receipt_long_outlined),
                                    label: const Text('Set Price'),
                                  ),
                                OutlinedButton.icon(
                                  onPressed: hasQuote ? () => _openHistory(_s(bundle.vendor['vendor_id']), jobOrderId) : null,
                                  icon: const Icon(Icons.history_rounded),
                                  label: const Text('Payment History'),
                                ),
                                if (isPending)
                                  FilledButton.icon(
                                    onPressed: () => _updateStatus(job, 'In Progress'),
                                    icon: const Icon(Icons.play_circle_outline_rounded),
                                    label: const Text('Start Job'),
                                  ),
                                if (isInProgress)
                                  FilledButton.icon(
                                    onPressed: canComplete ? () => _updateStatus(job, 'Completed') : null,
                                    icon: const Icon(Icons.check_circle_outline_rounded),
                                    label: const Text('Complete Job'),
                                  ),
                              ],
                            ),
                            if (isInProgress && !canComplete) ...[
                              const SizedBox(height: 10),
                              Text(
                                'Complete Job unlocks after the leaser pays the service price for this job order.',
                                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                              ),
                            ],
                            if (isCompleted && !hasQuote) ...[
                              const SizedBox(height: 10),
                              Text(
                                'Completed job orders are locked and cannot receive a new service price.',
                                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                              ),
                            ],
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

class _VendorJobsBundle {
  const _VendorJobsBundle({
    required this.vendor,
    required this.jobs,
    required this.vehicleMap,
    required this.costsByJob,
  });

  final Map<String, dynamic> vendor;
  final List<Map<String, dynamic>> jobs;
  final Map<String, Map<String, dynamic>> vehicleMap;
  final Map<String, List<Map<String, dynamic>>> costsByJob;
}

class _JobLine extends StatelessWidget {
  const _JobLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 108,
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

class _VendorStatusRemarksPage extends StatefulWidget {
  const _VendorStatusRemarksPage({required this.newStatus});

  final String newStatus;

  @override
  State<_VendorStatusRemarksPage> createState() => _VendorStatusRemarksPageState();
}

class _VendorStatusRemarksPageState extends State<_VendorStatusRemarksPage> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.of(context).pop(_controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final isCompleted = widget.newStatus == 'Completed';
    return Scaffold(
      appBar: AppBar(
        title: Text(isCompleted ? 'Complete Job Order' : 'Start Job Order'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Text(
            isCompleted
                ? 'Add a short completion remark for the activity log.'
                : 'Add a short update before moving this job to In Progress.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            maxLines: 6,
            decoration: const InputDecoration(
              hintText: 'Remarks',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: _submit,
            child: const Text('Confirm'),
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

DateTime? _parseDate(dynamic raw) {
  if (raw == null) return null;
  if (raw is DateTime) return raw;
  return DateTime.tryParse(raw.toString());
}

String _dateText(dynamic raw) {
  final value = _parseDate(raw);
  if (value == null) return '-';
  return '${value.day}/${value.month}/${value.year}';
}




