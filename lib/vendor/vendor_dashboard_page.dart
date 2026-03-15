import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/job_order_module_service.dart';
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

  Future<_VendorDashboardData> _load() async {
    final vendor = await _resolveVendor();
    if (vendor == null) {
      throw Exception('Vendor profile not found. Run the vendor SQL patch and make sure this account is linked to a vendor row.');
    }

    final vendorId = _read(vendor['vendor_id']);
    final jobs = await _jobService.fetchJobOrders(vendorId: vendorId);
    final vehicles = await _jobService.fetchVehicles();
    final vehicleMap = _jobService.indexBy(vehicles, 'vehicle_id');

    return _VendorDashboardData(
      vendor: vendor,
      jobs: jobs,
      vehicleMap: vehicleMap,
    );
  }

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

  Future<void> _refresh() async {
    setState(() {
      _future = _load();
    });
    await _future;
  }

  Future<void> _openServiceCost(String vendorId, {String? initialJobOrderId}) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VendorServiceCostPage(
          vendorId: vendorId,
          initialJobOrderId: initialJobOrderId,
        ),
      ),
    );
    if (!mounted) return;
    await _refresh();
  }

  String _read(dynamic value) => value == null ? '' : value.toString().trim();

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
        final pending = data.jobs.where((row) => _read(row['status']) == 'Pending').length;
        final active = data.jobs.where((row) => _read(row['status']) == 'In Progress').length;
        final completed = data.jobs.where((row) => _read(row['status']) == 'Completed').length;

        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
            children: [
              Text(
                'Vendor Dashboard',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 4),
              Text(
                'Review your service profile and the job orders assigned to your team.',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
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
                title: 'Service Cost',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Submit labour, parts, invoice, and cost notes for the job orders assigned to your vendor account.'),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: () => _openServiceCost(_read(data.vendor['vendor_id'])),
                      icon: const Icon(Icons.payments_outlined),
                      label: const Text('Open Service Cost'),
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
                    _InfoRow(label: 'Vendor', value: _read(data.vendor['vendor_name']).isEmpty ? '-' : _read(data.vendor['vendor_name'])),
                    _InfoRow(label: 'Service Type', value: _read(data.vendor['service_category']).isEmpty ? '-' : _read(data.vendor['service_category'])),
                    _InfoRow(label: 'Contact Person', value: _read(data.vendor['contact_person']).isEmpty ? '-' : _read(data.vendor['contact_person'])),
                    _InfoRow(label: 'Phone', value: _read(data.vendor['vendor_phone']).isEmpty ? '-' : _read(data.vendor['vendor_phone'])),
                    _InfoRow(label: 'Email', value: _read(data.vendor['vendor_email']).isEmpty ? '-' : _read(data.vendor['vendor_email'])),
                    _InfoRow(label: 'Pricing Structure', value: _read(data.vendor['pricing_structure']).isEmpty ? '-' : _read(data.vendor['pricing_structure'])),
                    const SizedBox(height: 10),
                    _StatusChip(status: _read(data.vendor['vendor_status']).isEmpty ? 'Active' : _read(data.vendor['vendor_status'])),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _SectionCard(
                title: 'Recent Assigned Jobs',
                child: data.jobs.isEmpty
                    ? const Text('No job orders have been assigned to this vendor yet.')
                    : Column(
                        children: data.jobs.take(6).map((job) {
                          final vehicle = data.vehicleMap[_read(job['vehicle_id'])];
                          final vehicleLabel = vehicle == null
                              ? _read(job['vehicle_id'])
                              : _jobService.vehicleLabel(vehicle);
                          final jobType = _read(job['job_type']).isEmpty ? 'General Service' : _read(job['job_type']);
                          final priority = _read(job['priority']).isEmpty ? 'Medium' : _read(job['priority']);
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          _read(job['job_order_id']),
                                          style: const TextStyle(fontWeight: FontWeight.w900),
                                        ),
                                      ),
                                      _StatusChip(status: _read(job['status']).isEmpty ? 'Pending' : _read(job['status'])),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(vehicleLabel.isEmpty ? 'Unknown vehicle' : vehicleLabel),
                                  const SizedBox(height: 4),
                                  Text(
                                    '$jobType | $priority',
                                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                                  ),
                                  const SizedBox(height: 10),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: OutlinedButton.icon(
                                      onPressed: () => _openServiceCost(
                                        _read(data.vendor['vendor_id']),
                                        initialJobOrderId: _read(job['job_order_id']),
                                      ),
                                      icon: const Icon(Icons.add_card_rounded),
                                      label: const Text('Add Cost'),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
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
    required this.vehicleMap,
  });

  final Map<String, dynamic> vendor;
  final List<Map<String, dynamic>> jobs;
  final Map<String, Map<String, dynamic>> vehicleMap;
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
          Text(label, style: TextStyle(color: tint, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
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
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
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
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w700),
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
    if (normalized == 'active' || normalized == 'completed') tint = Colors.green;
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





