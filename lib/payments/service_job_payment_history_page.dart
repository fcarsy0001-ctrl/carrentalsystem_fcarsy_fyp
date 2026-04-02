import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../admin/widgets/admin_ui.dart';
import '../services/job_order_module_service.dart';

class ServiceJobPaymentHistoryPage extends StatefulWidget {
  const ServiceJobPaymentHistoryPage({
    super.key,
    this.service,
    this.title = 'Service Payment History',
    this.leaserId,
    this.vendorId,
    this.jobOrderId,
    this.serviceCostId,
  });

  final JobOrderModuleService? service;
  final String title;
  final String? leaserId;
  final String? vendorId;
  final String? jobOrderId;
  final String? serviceCostId;

  @override
  State<ServiceJobPaymentHistoryPage> createState() => _ServiceJobPaymentHistoryPageState();
}

class _ServiceJobPaymentHistoryPageState extends State<ServiceJobPaymentHistoryPage> {
  SupabaseClient get _supa => Supabase.instance.client;

  late final JobOrderModuleService _service;
  late Future<_PaymentHistoryBundle> _future;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? JobOrderModuleService(_supa);
    _future = _load();
  }

  String _s(dynamic value) => value == null ? '' : value.toString().trim();

  Future<_PaymentHistoryBundle> _load() async {
    final payments = await _service.fetchServicePayments(
      leaserId: widget.leaserId,
      vendorId: widget.vendorId,
      jobOrderId: widget.jobOrderId,
      serviceCostId: widget.serviceCostId,
    );

    final jobs = <String, Map<String, dynamic>>{};
    for (final payment in payments) {
      final jobOrderId = _s(payment['job_order_id']);
      if (jobOrderId.isEmpty || jobs.containsKey(jobOrderId)) continue;
      final job = await _service.fetchJobOrder(jobOrderId);
      if (job != null) jobs[jobOrderId] = job;
    }

    final vehicles = await _service.fetchVehicles();
    final vehicleMap = _service.indexBy(vehicles, 'vehicle_id');
    final vendors = await _service.fetchVendors();
    final vendorMap = _service.indexBy(vendors, 'vendor_id');
    final costs = await _service.fetchServiceCosts(
      jobOrderIds: jobs.keys.toList(),
      vendorId: widget.vendorId,
    );
    final costMap = _service.indexBy(costs, 'service_cost_id');

    return _PaymentHistoryBundle(
      payments: payments,
      jobs: jobs,
      vehicleMap: vehicleMap,
      vendorMap: vendorMap,
      costMap: costMap,
    );
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _load();
    });
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: FutureBuilder<_PaymentHistoryBundle>(
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
          if (bundle == null || bundle.payments.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('No service payment history yet.'),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
              children: [
                Text(
                  '${bundle.payments.length} payment record${bundle.payments.length == 1 ? '' : 's'}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                ...bundle.payments.map((payment) {
                  final job = bundle.jobs[_s(payment['job_order_id'])];
                  final vehicle = job == null ? null : bundle.vehicleMap[_s(job['vehicle_id'])];
                  final vendor = bundle.vendorMap[_s(payment['vendor_id'])];
                  final cost = bundle.costMap[_s(payment['service_cost_id'])];
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
                                    _s(payment['service_payment_id']).isEmpty
                                        ? 'Service Payment'
                                        : _s(payment['service_payment_id']),
                                    style: const TextStyle(fontWeight: FontWeight.w900),
                                  ),
                                ),
                                AdminStatusChip(
                                  status: _s(payment['payment_status']).isEmpty
                                      ? 'Paid'
                                      : _s(payment['payment_status']),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            _HistoryLine(label: 'Job Order', value: _s(payment['job_order_id']).isEmpty ? '-' : _s(payment['job_order_id'])),
                            _HistoryLine(label: 'Vehicle', value: vehicle == null ? '-' : _service.vehicleLabel(vehicle)),
                            _HistoryLine(label: 'Vendor', value: vendor == null ? '-' : _service.vendorLabel(vendor)),
                            _HistoryLine(label: 'Cost Record', value: _s(payment['service_cost_id']).isEmpty ? '-' : _s(payment['service_cost_id'])),
                            _HistoryLine(label: 'Amount Paid', value: _money(payment['amount_paid'])),
                            _HistoryLine(label: 'Method', value: _s(payment['payment_method']).isEmpty ? '-' : _s(payment['payment_method'])),
                            _HistoryLine(label: 'Reference', value: _s(payment['payment_reference']).isEmpty ? '-' : _s(payment['payment_reference'])),
                            _HistoryLine(label: 'Paid At', value: _friendlyDateTime(payment['paid_at'])),
                            if (_s(cost?['invoice_ref']).isNotEmpty)
                              _HistoryLine(label: 'Invoice', value: _s(cost?['invoice_ref'])),
                            if (_s(payment['notes']).isNotEmpty)
                              _HistoryLine(label: 'Notes', value: _s(payment['notes'])),
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

class _PaymentHistoryBundle {
  const _PaymentHistoryBundle({
    required this.payments,
    required this.jobs,
    required this.vehicleMap,
    required this.vendorMap,
    required this.costMap,
  });

  final List<Map<String, dynamic>> payments;
  final Map<String, Map<String, dynamic>> jobs;
  final Map<String, Map<String, dynamic>> vehicleMap;
  final Map<String, Map<String, dynamic>> vendorMap;
  final Map<String, Map<String, dynamic>> costMap;
}

class _HistoryLine extends StatelessWidget {
  const _HistoryLine({required this.label, required this.value});

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
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
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

DateTime? _parseDateTime(dynamic raw) {
  if (raw == null) return null;
  if (raw is DateTime) return raw;
  return DateTime.tryParse(raw.toString());
}

String _friendlyDateTime(dynamic raw) {
  final value = _parseDateTime(raw);
  if (value == null) return '-';
  final local = value.toLocal();
  final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  final ap = local.hour >= 12 ? 'PM' : 'AM';
  return '${local.day}/${local.month}/${local.year}, $hour:$minute $ap';
}