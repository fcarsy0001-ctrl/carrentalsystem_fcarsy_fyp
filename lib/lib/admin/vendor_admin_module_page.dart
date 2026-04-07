import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/fleet_admin_service.dart';
import 'vendor_cost_admin_page.dart';
import 'widgets/admin_ui.dart';

class VendorAdminModulePage extends StatelessWidget {
  const VendorAdminModulePage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const AdminModuleHeader(
            icon: Icons.storefront_outlined,
            title: 'Vendors & Cost',
            subtitle: 'Review vendor applications, manage approved vendors, and track service costs.',
          ),
          const Divider(height: 1),
          Material(
            color: Theme.of(context).colorScheme.surface,
            child: const TabBar(
              tabAlignment: TabAlignment.start,
              isScrollable: true,
              tabs: [
                Tab(text: 'Applications'),
                Tab(text: 'Manage & Cost'),
              ],
            ),
          ),
          const Divider(height: 1),
          const Expanded(
            child: TabBarView(
              children: [
                _VendorApplicationsPage(),
                VendorCostAdminPage(embedded: true, showHeader: false),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VendorApplicationsPage extends StatefulWidget {
  const _VendorApplicationsPage();

  @override
  State<_VendorApplicationsPage> createState() => _VendorApplicationsPageState();
}

class _VendorApplicationsPageState extends State<_VendorApplicationsPage> {
  SupabaseClient get _supa => Supabase.instance.client;

  late final FleetAdminService _service;
  late Future<List<Map<String, dynamic>>> _future;
  String _filter = 'Pending';

  @override
  void initState() {
    super.initState();
    _service = FleetAdminService(_supa);
    _future = _load();
  }

  String _s(dynamic value) => value == null ? '' : value.toString().trim();

  Future<List<Map<String, dynamic>>> _load() async {
    final rows = await _service.fetchVendors();
    final sorted = [...rows];
    sorted.sort((a, b) {
      final left = _s(a['created_at']);
      final right = _s(b['created_at']);
      return right.compareTo(left);
    });
    return sorted;
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _load();
    });
    await _future;
  }

  List<Map<String, dynamic>> _applyFilter(List<Map<String, dynamic>> rows) {
    if (_filter == 'All') return rows;
    return rows.where((row) => _displayStatus(row) == _filter).toList();
  }

  String _displayStatus(Map<String, dynamic> row) {
    final status = _s(row['vendor_status']);
    return status.isEmpty ? 'Pending' : status;
  }

  Future<void> _openDetail(Map<String, dynamic> row) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => _VendorReviewDetailPage(row: row, service: _service)),
    );
    if (changed == true) {
      await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AdminModuleHeader(
          icon: Icons.assignment_outlined,
          title: 'Applications',
          subtitle: 'Review vendor applications before activating vendor access.',
          actions: [
            IconButton(
              tooltip: 'Refresh',
              onPressed: _refresh,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
          bottom: Row(
            children: [
              const Text('Filter', style: TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(width: 10),
              DropdownButton<String>(
                value: _filter,
                items: const [
                  DropdownMenuItem(value: 'Pending', child: Text('Pending')),
                  DropdownMenuItem(value: 'Rejected', child: Text('Rejected')),
                  DropdownMenuItem(value: 'All', child: Text('All')),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _filter = value);
                },
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('Failed to load vendor applications: ${snapshot.error}'),
                  ),
                );
              }

              final rows = _applyFilter(snapshot.data ?? const []);
              if (rows.isEmpty) {
                return const Center(child: Text('No vendor applications found.'));
              }

              return RefreshIndicator(
                onRefresh: _refresh,
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final row = rows[index];
                    final vendorName = _s(row['vendor_name']).isEmpty ? 'Vendor' : _s(row['vendor_name']);
                    final category = _s(row['service_category']).isEmpty ? '-' : _s(row['service_category']);
                    final contact = _s(row['contact_person']).isEmpty ? '-' : _s(row['contact_person']);
                    final email = _s(row['vendor_email']).isEmpty ? '-' : _s(row['vendor_email']);
                    final status = _displayStatus(row);
                    return AdminCard(
                      child: ListTile(
                        onTap: () => _openDetail(row),
                        leading: const Icon(Icons.storefront_outlined),
                        title: Text(
                          vendorName,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        subtitle: Text('Category: $category\nContact: $contact\nEmail: $email'),
                        isThreeLine: true,
                        trailing: AdminStatusChip(status: status),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _VendorReviewDetailPage extends StatefulWidget {
  const _VendorReviewDetailPage({required this.row, required this.service});

  final Map<String, dynamic> row;
  final FleetAdminService service;

  @override
  State<_VendorReviewDetailPage> createState() => _VendorReviewDetailPageState();
}

class _VendorReviewDetailPageState extends State<_VendorReviewDetailPage> {
  bool _busy = false;

  String _s(dynamic value) => value == null ? '' : value.toString().trim();

  Future<void> _setStatus(String status, {String? remark}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final vendorId = _s(widget.row['vendor_id']);
      if (vendorId.isEmpty) {
        throw Exception('Missing vendor ID');
      }

      await widget.service.updateVendorStatus(
        vendorId: vendorId,
        status: status,
        rejectRemark: remark,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Updated: $status'), backgroundColor: Colors.green),
      );
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.service.explainError(error)), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _approve() async {
    await _setStatus('Active');
  }

  Future<void> _reject() async {
    final remark = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final controller = TextEditingController();
        return AlertDialog(
          title: const Text('Reject vendor'),
          content: TextField(
            controller: controller,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Reject reason (optional)',
              hintText: 'e.g. business info incomplete',
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(null), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.of(ctx).pop(controller.text.trim()), child: const Text('Reject')),
          ],
        );
      },
    );
    if (remark == null) return;
    await _setStatus('Rejected', remark: remark);
  }

  @override
  Widget build(BuildContext context) {
    final status = _s(widget.row['vendor_status']).isEmpty ? 'Pending' : _s(widget.row['vendor_status']);
    final remark = _s(widget.row['vendor_reject_remark']);
    final canReview = status == 'Pending' || status == 'Rejected';

    return Scaffold(
      appBar: AppBar(title: const Text('Vendor Review')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          AdminCard(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _s(widget.row['vendor_name']).isEmpty ? 'Vendor' : _s(widget.row['vendor_name']),
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      AdminStatusChip(status: status),
                      AdminStatusChip(status: _s(widget.row['service_category']).isEmpty ? '-' : _s(widget.row['service_category'])),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _DetailRow(label: 'Vendor ID', value: _s(widget.row['vendor_id'])),
                  _DetailRow(label: 'Contact Person', value: _s(widget.row['contact_person']).isEmpty ? '-' : _s(widget.row['contact_person'])),
                  _DetailRow(label: 'Phone', value: _s(widget.row['vendor_phone']).isEmpty ? '-' : _s(widget.row['vendor_phone'])),
                  _DetailRow(label: 'Email', value: _s(widget.row['vendor_email']).isEmpty ? '-' : _s(widget.row['vendor_email'])),
                  _DetailRow(label: 'Address', value: _s(widget.row['vendor_address']).isEmpty ? '-' : _s(widget.row['vendor_address'])),
                  _DetailRow(label: 'Pricing Structure', value: _s(widget.row['pricing_structure']).isEmpty ? '-' : _s(widget.row['pricing_structure'])),
                  if (remark.isNotEmpty) _DetailRow(label: 'Reject Remark', value: remark),
                ],
              ),
            ),
          ),
          if (canReview) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _reject,
                    icon: const Icon(Icons.close_rounded),
                    label: const Text('Reject'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _approve,
                    icon: const Icon(Icons.check_circle_outline),
                    label: Text(_busy ? 'Saving...' : 'Approve'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
