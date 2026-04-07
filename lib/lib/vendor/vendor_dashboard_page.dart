import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../payments/service_job_payment_history_page.dart';
import '../services/job_order_module_service.dart';
import 'vendor_job_orders_page.dart';
import 'vendor_profile_edit_page.dart';
import 'vendor_service_cost_page.dart';

class VendorDashboardPage extends StatefulWidget {
  const VendorDashboardPage({super.key, this.vendorId});

  final String? vendorId;

  @override
  State<VendorDashboardPage> createState() => _VendorDashboardPageState();
}

class _VendorDashboardPageState extends State<VendorDashboardPage> {
  SupabaseClient get _supa => Supabase.instance.client;

  late final JobOrderModuleService _jobService;
  late Future<_VendorDashboardData> _future;

  @override
  void initState() {
    super.initState();
    _jobService = JobOrderModuleService(_supa);
    _future = _load();
  }

  String _read(dynamic value) => value == null ? '' : value.toString().trim();

  Future<_VendorDashboardData> _load() async {
    final vendor = await _jobService.resolveCurrentVendor(
      requestedVendorId: widget.vendorId,
    );
    if (vendor == null) {
      throw Exception(
        'Vendor profile not found. Run the vendor SQL patch and make sure this account is linked to a vendor row.',
      );
    }

    final vendorId = _read(vendor['vendor_id']);
    final jobs = await _jobService.fetchJobOrders(vendorId: vendorId);
    final costs = await _jobService.fetchServiceCosts(
      vendorId: vendorId,
      jobOrderIds: jobs
          .map((row) => _read(row['job_order_id']))
          .where((id) => id.isNotEmpty)
          .toList(),
    );

    return _VendorDashboardData(
      vendor: vendor,
      jobs: jobs,
      costs: costs,
    );
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _load();
    });
    await _future;
  }

  Future<void> _openServiceCost(String vendorId) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VendorServiceCostPage(vendorId: vendorId),
      ),
    );
    if (!mounted) return;
    await _refresh();
  }

  Future<void> _openPaymentHistory(String vendorId) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ServiceJobPaymentHistoryPage(
          service: _jobService,
          title: 'Vendor Payment History',
          vendorId: vendorId,
        ),
      ),
    );
    if (!mounted) return;
    await _refresh();
  }

  Future<void> _openJobOrders(String vendorId) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VendorJobOrdersPage(vendorId: vendorId),
      ),
    );
    if (!mounted) return;
    await _refresh();
  }

  Future<void> _openProfileEditor(Map<String, dynamic> vendor) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => VendorProfileEditPage(service: _jobService, vendor: vendor),
      ),
    );
    if (saved == true) {
      await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_VendorDashboardData>(
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

        final data = snapshot.data;
        if (data == null) {
          return const Center(child: Text('No vendor data found.'));
        }

        final total = data.jobs.length;
        final pending =
            data.jobs.where((row) => _read(row['status']) == 'Pending').length;
        final active = data.jobs
            .where((row) => _read(row['status']) == 'In Progress')
            .length;
        final completed = data.jobs
            .where((row) => _read(row['status']) == 'Completed')
            .length;
        final pendingQuotes = data.costs
            .where((row) => _read(row['payment_status']).toLowerCase() != 'paid')
            .length;
        final vendorId = _read(data.vendor['vendor_id']);
        final vendorStatus = _read(data.vendor['vendor_status']).isEmpty
            ? 'Active'
            : _read(data.vendor['vendor_status']);

        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
            children: [
              Text(
                'Vendor Dashboard',
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 4),
              Text(
                'Review your service profile, manage assigned job orders, send prices to leasers, and track service payments.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _MetricCard(label: 'Assigned', value: '$total', tint: Colors.blue),
                  _MetricCard(label: 'Pending', value: '$pending', tint: Colors.orange),
                  _MetricCard(label: 'In Progress', value: '$active', tint: Colors.indigo),
                  _MetricCard(label: 'Completed', value: '$completed', tint: Colors.green),
                ],
              ),
              const SizedBox(height: 16),
              _SectionCard(
                title: 'Quick Actions',
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    FilledButton.icon(
                      onPressed: () => _openJobOrders(vendorId),
                      icon: const Icon(Icons.build_circle_outlined),
                      label: const Text('Open Job Orders'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _openPaymentHistory(vendorId),
                      icon: const Icon(Icons.history_rounded),
                      label: const Text('Payment History'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _openProfileEditor(data.vendor),
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Edit Profile'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _SectionCard(
                title: 'Service Cost',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'You currently have ${data.costs.length} vendor quote${data.costs.length == 1 ? '' : 's'} and $pendingQuotes awaiting leaser payment.',
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: () => _openServiceCost(vendorId),
                      icon: const Icon(Icons.payments_outlined),
                      label: const Text('Manage Service Cost'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _SectionCard(
                title: 'Vendor Profile',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _InfoRow(
                      label: 'Vendor',
                      value: _read(data.vendor['vendor_name']).isEmpty
                          ? '-'
                          : _read(data.vendor['vendor_name']),
                    ),
                    _InfoRow(
                      label: 'Service Type',
                      value: _read(data.vendor['service_category']).isEmpty
                          ? '-'
                          : _read(data.vendor['service_category']),
                    ),
                    _InfoRow(
                      label: 'Contact Person',
                      value: _read(data.vendor['contact_person']).isEmpty
                          ? '-'
                          : _read(data.vendor['contact_person']),
                    ),
                    _InfoRow(
                      label: 'Phone',
                      value: _read(data.vendor['vendor_phone']).isEmpty
                          ? '-'
                          : _read(data.vendor['vendor_phone']),
                    ),
                    _InfoRow(
                      label: 'Email',
                      value: _read(data.vendor['vendor_email']).isEmpty
                          ? '-'
                          : _read(data.vendor['vendor_email']),
                    ),
                    _InfoRow(
                      label: 'Pricing Structure',
                      value: _read(data.vendor['pricing_structure']).isEmpty
                          ? '-'
                          : _read(data.vendor['pricing_structure']),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(child: _StatusChip(status: vendorStatus)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _VendorDashboardData {
  const _VendorDashboardData({
    required this.vendor,
    required this.jobs,
    required this.costs,
  });

  final Map<String, dynamic> vendor;
  final List<Map<String, dynamic>> jobs;
  final List<Map<String, dynamic>> costs;
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.tint,
  });

  final String label;
  final String value;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 150,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: tint.withValues(alpha: 0.08),
        border: Border.all(color: tint.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(color: tint, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
          ),
        ],
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: Colors.white,
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

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
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final normalized = status.trim().toLowerCase();
    Color tint = Colors.grey;
    if (normalized == 'active' || normalized == 'completed' || normalized == 'paid') {
      tint = Colors.green;
    }
    if (normalized == 'pending') tint = Colors.orange;
    if (normalized == 'in progress') tint = Colors.indigo;
    if (normalized == 'inactive') tint = Colors.redAccent;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: tint.withValues(alpha: 0.12),
        border: Border.all(color: tint.withValues(alpha: 0.22)),
      ),
      child: Text(
        status,
        style: TextStyle(color: tint, fontWeight: FontWeight.w700),
      ),
    );
  }
}
