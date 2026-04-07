import 'package:flutter/material.dart';

import '../admin/widgets/admin_ui.dart';
import '../services/job_order_module_service.dart';
import 'service_job_payment_history_page.dart';
import 'service_job_payment_page.dart';

class ServiceJobCostRecordsPage extends StatefulWidget {
  const ServiceJobCostRecordsPage({
    super.key,
    required this.service,
    required this.jobOrderId,
    this.leaserId,
  });

  final JobOrderModuleService service;
  final String jobOrderId;
  final String? leaserId;

  bool get isLeaserView => (leaserId ?? '').trim().isNotEmpty;

  @override
  State<ServiceJobCostRecordsPage> createState() => _ServiceJobCostRecordsPageState();
}

class _ServiceJobCostRecordsPageState extends State<ServiceJobCostRecordsPage> {
  late Future<_CostRecordsBundle> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  String _s(dynamic value) => value == null ? '' : value.toString().trim();

  Future<_CostRecordsBundle> _load() async {
    final job = await widget.service.fetchJobOrder(widget.jobOrderId);
    if (job == null) {
      throw Exception('Job order not found.');
    }

    final vehicles = await widget.service.fetchVehicles();
    final vendors = await widget.service.fetchVendors();
    final costs = await widget.service.fetchServiceCostsForJob(widget.jobOrderId);
    final payments = await widget.service.fetchServicePayments(jobOrderId: widget.jobOrderId);

    final vehicleMap = widget.service.indexBy(vehicles, 'vehicle_id');
    final vendorMap = widget.service.indexBy(vendors, 'vendor_id');
    final paymentsByCost = <String, List<Map<String, dynamic>>>{};
    for (final payment in payments) {
      final serviceCostId = _s(payment['service_cost_id']);
      if (serviceCostId.isEmpty) continue;
      paymentsByCost.putIfAbsent(serviceCostId, () => <Map<String, dynamic>>[]).add(payment);
    }

    return _CostRecordsBundle(
      job: job,
      vehicle: vehicleMap[_s(job['vehicle_id'])],
      vendor: vendorMap[_s(job['vendor_id'])],
      costs: costs,
      paymentsByCost: paymentsByCost,
    );
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _load();
    });
    await _future;
  }

  Future<void> _openPayment(_CostRecordsBundle bundle, Map<String, dynamic> cost) async {
    final vendorId = _s(cost['vendor_id']).isEmpty ? _s(bundle.job['vendor_id']) : _s(cost['vendor_id']);
    if (vendorId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Assign a vendor before paying the service cost.')),
      );
      return;
    }

    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ServiceJobPaymentPage(
          service: widget.service,
          job: bundle.job,
          cost: cost,
          vehicle: bundle.vehicle,
          vendor: bundle.vendor,
          leaserId: widget.leaserId!,
        ),
      ),
    );
    if (saved == true) {
      await _refresh();
    }
  }

  Future<void> _openHistory({String? serviceCostId}) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ServiceJobPaymentHistoryPage(
          service: widget.service,
          title: serviceCostId == null ? 'Service Payment History' : 'Cost Payment History',
          leaserId: widget.leaserId,
          jobOrderId: widget.jobOrderId,
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
        title: const Text('Service Cost Records'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: FutureBuilder<_CostRecordsBundle>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(widget.service.explainError(snapshot.error!)),
              ),
            );
          }

          final bundle = snapshot.data;
          if (bundle == null) {
            return const Center(child: Text('No service cost data found.'));
          }

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
              children: [
                AdminCard(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _s(bundle.job['job_order_id']).isEmpty ? 'Job Order' : _s(bundle.job['job_order_id']),
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 10),
                        _DetailLine(label: 'Vehicle', value: bundle.vehicle == null ? '-' : widget.service.vehicleLabel(bundle.vehicle)),
                        _DetailLine(label: 'Vendor', value: bundle.vendor == null ? 'Not assigned yet' : widget.service.vendorLabel(bundle.vendor)),
                        _DetailLine(label: 'Job Type', value: _s(bundle.job['job_type']).isEmpty ? '-' : _s(bundle.job['job_type'])),
                        _DetailLine(label: 'Status', value: _s(bundle.job['status']).isEmpty ? '-' : _s(bundle.job['status'])),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                if (bundle.costs.isEmpty)
                  const AdminCard(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('The vendor has not submitted a service cost for this job order yet.'),
                    ),
                  )
                else ...[
                  Text(
                    '${bundle.costs.length} cost record${bundle.costs.length == 1 ? '' : 's'}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
                  ...bundle.costs.map((cost) {
                    final serviceCostId = _s(cost['service_cost_id']);
                    final costPayments = bundle.paymentsByCost[serviceCostId] ?? const <Map<String, dynamic>>[];
                    final isPaid = _s(cost['payment_status']).toLowerCase() == 'paid';
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
                                      serviceCostId.isEmpty ? 'Service Cost' : serviceCostId,
                                      style: const TextStyle(fontWeight: FontWeight.w900),
                                    ),
                                  ),
                                  AdminStatusChip(status: isPaid ? 'Paid' : (_s(cost['payment_status']).isEmpty ? 'Pending' : _s(cost['payment_status']))),
                                ],
                              ),
                              const SizedBox(height: 10),
                              _DetailLine(label: 'Service Date', value: _dateText(cost['service_date'])),
                              _DetailLine(label: 'Labour', value: _money(cost['labour_cost'])),
                              _DetailLine(label: 'Parts', value: _money(cost['parts_cost'])),
                              _DetailLine(label: 'Misc', value: _money(cost['misc_cost'])),
                              _DetailLine(label: 'Tax', value: _money(cost['tax_cost'])),
                              _DetailLine(label: 'Total', value: _money(cost['total_cost'])),
                              _DetailLine(label: 'Invoice', value: _s(cost['invoice_ref']).isEmpty ? '-' : _s(cost['invoice_ref'])),
                              if (_s(cost['notes']).isNotEmpty)
                                _DetailLine(label: 'Notes', value: _s(cost['notes'])),
                              _DetailLine(label: 'Payment History', value: '${costPayments.length} record${costPayments.length == 1 ? '' : 's'}'),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                children: [
                                  OutlinedButton.icon(
                                    onPressed: () => _openHistory(serviceCostId: serviceCostId),
                                    icon: const Icon(Icons.history_rounded),
                                    label: const Text('Payment History'),
                                  ),
                                  if (widget.isLeaserView)
                                    FilledButton.icon(
                                      onPressed: isPaid ? null : () => _openPayment(bundle, cost),
                                      icon: const Icon(Icons.payments_outlined),
                                      label: Text(isPaid ? 'Paid' : 'Pay Now'),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                  if (widget.isLeaserView)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: _openHistory,
                        icon: const Icon(Icons.receipt_long_outlined),
                        label: const Text('View All Payment History'),
                      ),
                    ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _CostRecordsBundle {
  const _CostRecordsBundle({
    required this.job,
    required this.vehicle,
    required this.vendor,
    required this.costs,
    required this.paymentsByCost,
  });

  final Map<String, dynamic> job;
  final Map<String, dynamic>? vehicle;
  final Map<String, dynamic>? vendor;
  final List<Map<String, dynamic>> costs;
  final Map<String, List<Map<String, dynamic>>> paymentsByCost;
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.label, required this.value});

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