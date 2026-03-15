import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/job_order_module_service.dart';
import 'widgets/admin_ui.dart';

const List<String> _jobTypes = [
  'Inspection',
  'Oil Change',
  'Brake Service',
  'Engine Repair',
  'Electrical',
  'Tyre Rotation',
  'General Service',
];

const List<String> _priorities = [
  'Low',
  'Medium',
  'High',
  'Urgent',
];

const List<String> _statuses = [
  'Pending',
  'In Progress',
  'Completed',
  'Cancelled',
];

class ServiceJobOrdersPage extends StatefulWidget {
  const ServiceJobOrdersPage({
    super.key,
    this.embedded = false,
    this.leaserId,
    this.title,
    this.subtitle,
    this.allowVendorReassign = false,
    this.allowCancelledStatus = true,
  });

  final bool embedded;
  final String? leaserId;
  final String? title;
  final String? subtitle;
  final bool allowVendorReassign;
  final bool allowCancelledStatus;

  bool get isLeaserView => (leaserId ?? '').trim().isNotEmpty;

  String get pageTitle => title ?? (isLeaserView ? 'Service Jobs' : 'Job Orders');

  String get pageSubtitle => subtitle ??
      (isLeaserView
          ? 'Create and track maintenance or inspection requests for your vehicles.'
          : 'Manage maintenance and service requests across the fleet.');

  @override
  State<ServiceJobOrdersPage> createState() => _ServiceJobOrdersPageState();
}

class _ServiceJobOrdersPageState extends State<ServiceJobOrdersPage> {
  SupabaseClient get _supa => Supabase.instance.client;

  late final JobOrderModuleService _service;
  late Future<_JobOrderBundle> _future;

  String _query = '';
  String _statusFilter = 'All';
  String _priorityFilter = 'All';
  bool _showFilters = false;

  @override
  void initState() {
    super.initState();
    _service = JobOrderModuleService(_supa);
    _future = _load();
  }

  Future<_JobOrderBundle> _load() async {
    final vehicles = await _service.fetchVehicles(leaserId: widget.leaserId);
    final vehicleIds = vehicles.map((row) => _string(row['vehicle_id'])).where((id) => id.isNotEmpty).toList();
    final jobs = await _service.fetchJobOrders(
      vehicleIds: widget.isLeaserView ? vehicleIds : null,
    );
    final vendors = await _service.fetchVendors(onlyActive: widget.isLeaserView);
    final jobOrderIds = jobs.map((row) => _string(row['job_order_id'])).where((id) => id.isNotEmpty).toList();
    final costs = await _service.fetchServiceCosts(jobOrderIds: jobOrderIds);
    return _JobOrderBundle(jobs: jobs, vehicles: vehicles, vendors: vendors, costs: costs);
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _load();
    });
    await _future;
  }

  Future<void> _openCreate(_JobOrderBundle bundle) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _CreateJobOrderPage(
          service: _service,
          vehicles: bundle.vehicles,
          vendors: bundle.vendors,
          jobs: bundle.jobs,
        ),
      ),
    );
    if (!mounted) return;
    await _refresh();
  }

  Future<void> _openCreateFromCurrentData() async {
    try {
      final bundle = await _future;
      if (!mounted) return;
      await _openCreate(bundle);
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

  Future<void> _openDetails(String jobOrderId) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _JobOrderDetailsPage(
          service: _service,
          jobOrderId: jobOrderId,
          leaserId: widget.leaserId,
          allowVendorReassign: widget.allowVendorReassign,
          allowCancelledStatus: widget.allowCancelledStatus,
        ),
      ),
    );
    if (!mounted) return;
    await _refresh();
  }

  bool _canDeleteJob(Map<String, dynamic> job) {
    if (!widget.isLeaserView) return false;
    final status = _string(job['status']).toLowerCase();
    return status == 'pending' || status == 'cancelled';
  }

  Future<void> _deleteJob(Map<String, dynamic> job) async {
    final jobOrderId = _string(job['job_order_id']);
    if (jobOrderId.isEmpty) return;

    if (!_canDeleteJob(job)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Only pending or cancelled job orders can be deleted.')),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete job order'),
        content: Text(
          'Delete job order $jobOrderId? This will also remove the linked maintenance schedule, service costs, attachments, and activity log for this request.',
        ),
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
        const SnackBar(content: Text('Job order deleted.')),
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

  List<Map<String, dynamic>> _filteredJobs(
      _JobOrderBundle bundle,
      Map<String, Map<String, dynamic>> vehicleMap,
      Map<String, Map<String, dynamic>> vendorMap,
      ) {
    final query = _query.trim().toLowerCase();

    return bundle.jobs.where((job) {
      final status = _string(job['status']);
      final priority = _string(job['priority']);
      final vehicle = vehicleMap[_string(job['vehicle_id'])];
      final vendor = vendorMap[_string(job['vendor_id'])];

      final matchesStatus = _statusFilter == 'All' || status == _statusFilter;
      final matchesPriority = _priorityFilter == 'All' || priority == _priorityFilter;
      if (!matchesStatus || !matchesPriority) return false;

      if (query.isEmpty) return true;

      final haystack = [
        _string(job['job_order_id']),
        _string(job['job_type']),
        _string(job['problem_description']),
        _string(job['requested_by']),
        _string(job['priority']),
        _string(job['status']),
        _string(vehicle?['vehicle_plate_no']),
        _string(vehicle?['vehicle_brand']),
        _string(vehicle?['vehicle_model']),
        _string(vendor?['vendor_name']),
        _string(vendor?['service_category']),
      ].join(' ').toLowerCase();

      return haystack.contains(query);
    }).toList();
  }

  Widget _buildBody() {
    return FutureBuilder<_JobOrderBundle>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _JobSqlErrorView(message: _service.explainError(snapshot.error!));
        }

        final bundle = snapshot.data;
        if (bundle == null) {
          return const Center(child: Text('No data'));
        }

        final vehicleMap = _service.indexBy(bundle.vehicles, 'vehicle_id');
        final vendorMap = _service.indexBy(bundle.vendors, 'vendor_id');
        final costTotalByJob = _costTotalsByJob(bundle.costs);
        final costCountByJob = _costCountsByJob(bundle.costs);
        final filtered = _filteredJobs(bundle, vehicleMap, vendorMap);

        final total = bundle.jobs.length;
        final pending = bundle.jobs.where((row) => _string(row['status']) == 'Pending').length;
        final active = bundle.jobs.where((row) => _string(row['status']) == 'In Progress').length;
        final done = bundle.jobs.where((row) => _string(row['status']) == 'Completed').length;

        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
            children: [
              if (!widget.embedded) ...[
                Text(
                  widget.pageTitle,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.pageSubtitle,
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
              ],
              TextField(
                decoration: InputDecoration(
                  hintText: 'Search job orders, vehicles, or vendors',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: IconButton(
                    tooltip: _showFilters ? 'Hide filters' : 'Show filters',
                    onPressed: () => setState(() => _showFilters = !_showFilters),
                    icon: Icon(_showFilters ? Icons.expand_less_rounded : Icons.filter_alt_outlined),
                  ),
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _SummaryCard(
                    label: 'Total',
                    value: '$total',
                    tint: Colors.blue,
                    selected: _statusFilter == 'All',
                    onTap: () => setState(() => _statusFilter = 'All'),
                  ),
                  _SummaryCard(
                    label: 'Pending',
                    value: '$pending',
                    tint: Colors.orange,
                    selected: _statusFilter == 'Pending',
                    onTap: () => setState(() => _statusFilter = 'Pending'),
                  ),
                  _SummaryCard(
                    label: 'Active',
                    value: '$active',
                    tint: Colors.indigo,
                    selected: _statusFilter == 'In Progress',
                    onTap: () => setState(() => _statusFilter = 'In Progress'),
                  ),
                  _SummaryCard(
                    label: 'Done',
                    value: '$done',
                    tint: Colors.green,
                    selected: _statusFilter == 'Completed',
                    onTap: () => setState(() => _statusFilter = 'Completed'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              AdminCard(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.filter_alt_outlined),
                      title: const Text(
                        'Filters',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        _showFilters
                            ? 'Filter by status and priority.'
                            : 'Tap to filter the job order list.',
                      ),
                      trailing: Icon(_showFilters ? Icons.expand_less_rounded : Icons.expand_more_rounded),
                      onTap: () => setState(() => _showFilters = !_showFilters),
                    ),
                    if (_showFilters) ...[
                      const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                        child: Column(
                          children: [
                            DropdownButtonFormField<String>(
                              value: _statusFilter,
                              isExpanded: true,
                              decoration: const InputDecoration(labelText: 'Status'),
                              items: const [
                                DropdownMenuItem(value: 'All', child: Text('All')),
                                DropdownMenuItem(value: 'Pending', child: Text('Pending')),
                                DropdownMenuItem(value: 'In Progress', child: Text('In Progress')),
                                DropdownMenuItem(value: 'Completed', child: Text('Completed')),
                                DropdownMenuItem(value: 'Cancelled', child: Text('Cancelled')),
                              ],
                              onChanged: (value) => setState(() => _statusFilter = value ?? 'All'),
                            ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<String>(
                              value: _priorityFilter,
                              isExpanded: true,
                              decoration: const InputDecoration(labelText: 'Priority'),
                              items: const [
                                DropdownMenuItem(value: 'All', child: Text('All')),
                                DropdownMenuItem(value: 'Low', child: Text('Low')),
                                DropdownMenuItem(value: 'Medium', child: Text('Medium')),
                                DropdownMenuItem(value: 'High', child: Text('High')),
                                DropdownMenuItem(value: 'Urgent', child: Text('Urgent')),
                              ],
                              onChanged: (value) => setState(() => _priorityFilter = value ?? 'All'),
                            ),
                            const SizedBox(height: 12),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                onPressed: () {
                                  setState(() {
                                    _statusFilter = 'All';
                                    _priorityFilter = 'All';
                                    _query = '';
                                  });
                                },
                                icon: const Icon(Icons.restart_alt_rounded),
                                label: const Text('Reset filters'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Text(
                '${filtered.length} job order${filtered.length == 1 ? '' : 's'}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              if (filtered.isEmpty)
                _EmptyCard(
                  message: widget.isLeaserView
                      ? 'No job orders match the current filters yet. Create a new job order to start tracking service work.'
                      : 'No job orders match the current filters yet.',
                )
              else
                ...filtered.map((job) {
                  final jobOrderId = _string(job['job_order_id']);
                  final vehicle = vehicleMap[_string(job['vehicle_id'])];
                  final vendor = vendorMap[_string(job['vendor_id'])];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _JobOrderCard(
                      job: job,
                      vehicle: vehicle,
                      vendor: vendor,
                      totalCost: costTotalByJob[jobOrderId] ?? _amount(job['actual_cost']),
                      costRecordCount: costCountByJob[jobOrderId] ?? 0,
                      onTap: () => _openDetails(jobOrderId),
                      onDelete: widget.isLeaserView ? () => _deleteJob(job) : null,
                      canDelete: _canDeleteJob(job),
                    ),
                  );
                }),
              if (filtered.isNotEmpty) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    'Showing ${filtered.length} of $total job orders',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
              if (!widget.embedded && widget.isLeaserView) const SizedBox(height: 86),
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
            title: widget.pageTitle,
            subtitle: widget.pageSubtitle,
            actions: [
              IconButton(
                tooltip: 'Refresh',
                onPressed: _refresh,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
            primaryActions: widget.isLeaserView
                ? [
              FilledButton.icon(
                onPressed: _openCreateFromCurrentData,
                icon: const Icon(Icons.add),
                label: const Text('Create Job Order'),
              ),
            ]
                : const [],
          ),
          const Divider(height: 1),
          Expanded(child: body),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.pageTitle),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: body,
      bottomNavigationBar: widget.isLeaserView
          ? SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: FilledButton.icon(
          onPressed: _openCreateFromCurrentData,
          icon: const Icon(Icons.add),
          label: const Text('Create Job Order'),
        ),
      )
          : null,
    );
  }
}

class _JobOrderBundle {
  const _JobOrderBundle({
    required this.jobs,
    required this.vehicles,
    required this.vendors,
    required this.costs,
  });

  final List<Map<String, dynamic>> jobs;
  final List<Map<String, dynamic>> vehicles;
  final List<Map<String, dynamic>> vendors;
  final List<Map<String, dynamic>> costs;
}

class _JobOrderCard extends StatelessWidget {
  const _JobOrderCard({
    required this.job,
    required this.vehicle,
    required this.vendor,
    required this.totalCost,
    required this.costRecordCount,
    required this.onTap,
    this.onDelete,
    this.canDelete = false,
  });

  final Map<String, dynamic> job;
  final Map<String, dynamic>? vehicle;
  final Map<String, dynamic>? vendor;
  final double totalCost;
  final int costRecordCount;
  final VoidCallback onTap;
  final VoidCallback? onDelete;
  final bool canDelete;

  @override
  Widget build(BuildContext context) {
    final plate = _string(vehicle?['vehicle_plate_no']);
    final model = '${_string(vehicle?['vehicle_brand'])} ${_string(vehicle?['vehicle_model'])}'.trim();
    final vendorName = _string(vendor?['vendor_name']).isEmpty ? 'Not assigned' : _string(vendor?['vendor_name']);

    return AdminCard(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.description_outlined,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _string(job['job_order_id']),
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            AdminStatusChip(status: _string(job['status'])),
                            _PriorityChip(priority: _string(job['priority'])),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (onDelete != null)
                        PopupMenuButton<String>(
                          tooltip: 'More actions',
                          onSelected: (value) {
                            if (value == 'delete') {
                              onDelete?.call();
                            }
                          },
                          itemBuilder: (context) => [
                            PopupMenuItem<String>(
                              value: 'delete',
                              enabled: canDelete,
                              child: Text(
                                canDelete
                                    ? 'Delete job order'
                                    : 'Delete (Pending/Cancelled only)',
                              ),
                            ),
                          ],
                        ),
                      const Icon(Icons.chevron_right_rounded),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _DetailLine(label: 'Plate', value: plate.isEmpty ? '-' : plate),
              _DetailLine(label: 'Vehicle', value: model.isEmpty ? 'Unknown vehicle' : model),
              _DetailLine(label: 'Job Type', value: _string(job['job_type'])),
              _DetailLine(label: 'Vendor', value: vendorName),
              _DetailLine(label: 'Requested', value: _friendlyDate(job['created_at'])),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text(
                    'Total Cost',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                  const Spacer(),
                  Text(
                    _money(totalCost),
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ],
              ),
              if (costRecordCount > 0) ...[
                const SizedBox(height: 6),
                Text(
                  '${costRecordCount} service cost record${costRecordCount == 1 ? '' : 's'}',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
class _CreateJobOrderPage extends StatefulWidget {
  const _CreateJobOrderPage({
    required this.service,
    required this.vehicles,
    required this.vendors,
    required this.jobs,
  });

  final JobOrderModuleService service;
  final List<Map<String, dynamic>> vehicles;
  final List<Map<String, dynamic>> vendors;
  final List<Map<String, dynamic>> jobs;

  @override
  State<_CreateJobOrderPage> createState() => _CreateJobOrderPageState();
}

class _CreateJobOrderPageState extends State<_CreateJobOrderPage> {
  final _formKey = GlobalKey<FormState>();
  final _problemController = TextEditingController();

  String? _vehicleId;
  String? _vendorId;
  String _jobType = _jobTypes.first;
  String _priority = 'Medium';
  bool _saving = false;
  _PickedJobFile? _pickedFile;
  DateTime? _preferredDate;
  Set<String> _blockedDateKeys = <String>{};

  bool get _canSubmit {
    return !_saving &&
        (_vehicleId ?? '').trim().isNotEmpty &&
        (_vendorId ?? '').trim().isNotEmpty &&
        _preferredDate != null &&
        _problemController.text.trim().isNotEmpty;
  }

  @override
  void initState() {
    super.initState();
    if (widget.vehicles.isNotEmpty) {
      _vehicleId = _string(widget.vehicles.first['vehicle_id']);
    }
    if (widget.vendors.isNotEmpty) {
      _vendorId = _string(widget.vendors.first['vendor_id']);
    }
    _problemController.addListener(() => setState(() {}));
    _reloadBlockedDates();
  }

  @override
  void dispose() {
    _problemController.dispose();
    super.dispose();
  }

  Future<void> _pickAttachment() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        withData: true,
        type: FileType.custom,
        allowedExtensions: const ['png', 'jpg', 'jpeg', 'pdf'],
      );
      if (result == null || result.files.isEmpty) return;

      final file = result.files.single;
      if (file.size > 10 * 1024 * 1024) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Attachment must be 10MB or smaller.')),
        );
        return;
      }

      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not read the selected file.')),
        );
        return;
      }

      setState(() {
        _pickedFile = _PickedJobFile(
          name: file.name,
          bytes: bytes,
          sizeBytes: file.size,
        );
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to pick attachment: $error'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  String _dateKey(DateTime value) {
    final normalized = DateTime(value.year, value.month, value.day);
    final month = normalized.month.toString().padLeft(2, '0');
    final day = normalized.day.toString().padLeft(2, '0');
    return '${normalized.year}-$month-$day';
  }

  Future<void> _reloadBlockedDates({bool clearInvalidSelection = false}) async {
    final vehicleId = (_vehicleId ?? '').trim();
    final blocked = vehicleId.isEmpty
        ? <String>{}
        : await widget.service.fetchReservedServiceDateKeysForVehicle(vehicleId);
    if (!mounted) return;

    final shouldClear = clearInvalidSelection &&
        _preferredDate != null &&
        blocked.contains(_dateKey(_preferredDate!));

    setState(() {
      _blockedDateKeys = blocked;
      if (shouldClear) {
        _preferredDate = null;
      }
    });

    if (shouldClear && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Preferred date cleared because that date is already used for the selected vehicle.')),
      );
    }
  }

  bool _isBlockedPreferredDate(DateTime value) {
    return _blockedDateKeys.contains(_dateKey(value));
  }

  DateTime _initialPreferredDate() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final lastDate = DateTime(now.year + 3, 12, 31);
    var candidate = _preferredDate == null
        ? today
        : DateTime(_preferredDate!.year, _preferredDate!.month, _preferredDate!.day);
    if (candidate.isBefore(today)) {
      candidate = today;
    }
    while (!candidate.isAfter(lastDate) && _isBlockedPreferredDate(candidate)) {
      candidate = candidate.add(const Duration(days: 1));
    }
    return candidate.isAfter(lastDate) ? today : candidate;
  }

  Future<void> _pickPreferredDate() async {
    await _reloadBlockedDates(clearInvalidSelection: true);
    if (!mounted) return;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final lastDate = DateTime(now.year + 3, 12, 31);
    var hasAvailableDate = false;
    var probe = today;
    while (!probe.isAfter(lastDate)) {
      if (!_isBlockedPreferredDate(probe)) {
        hasAvailableDate = true;
        break;
      }
      probe = probe.add(const Duration(days: 1));
    }

    if (!hasAvailableDate) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This vehicle has no available service dates in the selectable range.')),
      );
      return;
    }

    final picked = await showDatePicker(
      context: context,
      initialDate: _initialPreferredDate(),
      firstDate: today,
      lastDate: lastDate,
      selectableDayPredicate: (day) => !_isBlockedPreferredDate(day),
    );
    if (picked == null) return;
    setState(() => _preferredDate = picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_preferredDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select the service date for this job order.')),
      );
      return;
    }
    if (_isBlockedPreferredDate(_preferredDate!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This vehicle already has a job order on that service date. Please choose another date.')),
      );
      return;
    }
    if (!_canSubmit) return;

    setState(() => _saving = true);
    try {
      await widget.service.createJobOrder(
        vehicleId: _vehicleId!,
        jobType: _jobType,
        priority: _priority,
        problemDescription: _problemController.text.trim(),
        vendorId: _vendorId!,
        preferredDate: _preferredDate,
        attachmentBytes: _pickedFile?.bytes,
        attachmentName: _pickedFile?.name,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Job order created successfully.')),
      );
      Navigator.of(context).pop();
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
      appBar: AppBar(title: const Text('New Job Order')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
          children: [
            Text(
              'Create a maintenance service request',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            AdminCard(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _SectionHeader('Select Vehicle'),
                    DropdownButtonFormField<String>(
                      value: widget.vehicles.any((row) => _string(row['vehicle_id']) == _vehicleId) ? _vehicleId : null,
                      isExpanded: true,
                      decoration: const InputDecoration(prefixIcon: Icon(Icons.directions_car_filled_outlined)),
                      items: widget.vehicles
                          .map(
                            (vehicle) => DropdownMenuItem<String>(
                          value: _string(vehicle['vehicle_id']),
                          child: Text(widget.service.vehicleLabel(vehicle), overflow: TextOverflow.ellipsis),
                        ),
                      )
                          .toList(),
                      onChanged: (value) {
                        setState(() => _vehicleId = value);
                        _reloadBlockedDates(clearInvalidSelection: true);
                      },
                      validator: (value) => (value == null || value.trim().isEmpty) ? 'Choose a vehicle' : null,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            AdminCard(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _SectionHeader('Job Type'),
                    DropdownButtonFormField<String>(
                      value: _jobType,
                      isExpanded: true,
                      decoration: const InputDecoration(prefixIcon: Icon(Icons.build_outlined)),
                      items: _jobTypes
                          .map(
                            (type) => DropdownMenuItem<String>(value: type, child: Text(type)),
                      )
                          .toList(),
                      onChanged: (value) => setState(() => _jobType = value ?? _jobTypes.first),
                    ),
                    const SizedBox(height: 16),
                    const _SectionHeader('Priority'),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: _priorities
                          .map(
                            (priority) => ChoiceChip(
                          label: SizedBox(
                            width: 84,
                            child: Center(child: Text(priority)),
                          ),
                          selected: _priority == priority,
                          onSelected: (_) => setState(() => _priority = priority),
                        ),
                      )
                          .toList(),
                    ),
                    const SizedBox(height: 16),
                    const _SectionHeader('Preferred Service Date'),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        _preferredDate == null
                            ? 'No date selected yet'
                            : '${_preferredDate!.day}/${_preferredDate!.month}/${_preferredDate!.year}',
                      ),
                      subtitle: const Text('This date will also appear in the maintenance calendar. Dates already used by this vehicle are disabled.'),
                      trailing: Wrap(
                        spacing: 8,
                        children: [
                          if (_preferredDate != null)
                            IconButton(
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
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            AdminCard(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _SectionHeader('Problem Description'),
                    TextFormField(
                      controller: _problemController,
                      maxLines: 5,
                      maxLength: 500,
                      decoration: const InputDecoration(
                        hintText: 'Describe the issue or service needed in detail...',
                        prefixIcon: Icon(Icons.description_outlined),
                        alignLabelWithHint: true,
                      ),
                      validator: (value) => (value == null || value.trim().isEmpty) ? 'Problem description is required' : null,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            AdminCard(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _SectionHeader('Assign Vendor'),
                    if (widget.vendors.isEmpty)
                      const Text('Add at least one vendor first in the Vendors & Cost module.')
                    else
                      DropdownButtonFormField<String>(
                        value: widget.vendors.any((row) => _string(row['vendor_id']) == _vendorId) ? _vendorId : null,
                        isExpanded: true,
                        decoration: const InputDecoration(prefixIcon: Icon(Icons.storefront_outlined)),
                        items: widget.vendors
                            .map(
                              (vendor) => DropdownMenuItem<String>(
                            value: _string(vendor['vendor_id']),
                            child: Text(widget.service.vendorLabel(vendor), overflow: TextOverflow.ellipsis),
                          ),
                        )
                            .toList(),
                        onChanged: (value) => setState(() => _vendorId = value),
                        validator: (value) => (value == null || value.trim().isEmpty) ? 'Choose a vendor' : null,
                      ),
                    const SizedBox(height: 16),
                    const _SectionHeader('Attach Files (Optional)'),
                    OutlinedButton.icon(
                      onPressed: _pickAttachment,
                      icon: const Icon(Icons.upload_file_outlined),
                      label: const Text('Browse files'),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                        color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.35),
                      ),
                      child: _pickedFile == null
                          ? Column(
                        children: [
                          Icon(Icons.insert_drive_file_outlined, color: Theme.of(context).colorScheme.onSurfaceVariant),
                          const SizedBox(height: 8),
                          Text(
                            'PNG, JPG, PDF up to 10MB',
                            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                          ),
                        ],
                      )
                          : Row(
                        children: [
                          Icon(
                            _pickedFile!.name.toLowerCase().endsWith('.pdf')
                                ? Icons.picture_as_pdf_outlined
                                : Icons.image_outlined,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _pickedFile!.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.w700),
                                ),
                                Text(_fileSizeLabel(_pickedFile!.sizeBytes)),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Remove file',
                            onPressed: () => setState(() => _pickedFile = null),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _canSubmit ? _submit : null,
              icon: _saving
                  ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
                  : const Icon(Icons.add_circle_outline),
              label: Text(_saving ? 'Creating...' : 'Create Job Order'),
            ),
          ],
        ),
      ),
    );
  }
}
class _JobOrderDetailsPage extends StatefulWidget {
  const _JobOrderDetailsPage({
    required this.service,
    required this.jobOrderId,
    this.leaserId,
    this.allowVendorReassign = false,
    this.allowCancelledStatus = true,
  });

  final JobOrderModuleService service;
  final String jobOrderId;
  final String? leaserId;
  final bool allowVendorReassign;
  final bool allowCancelledStatus;

  @override
  State<_JobOrderDetailsPage> createState() => _JobOrderDetailsPageState();
}

class _JobOrderDetailsPageState extends State<_JobOrderDetailsPage> {
  late Future<_JobOrderDetailBundle> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_JobOrderDetailBundle> _load() async {
    final job = await widget.service.fetchJobOrder(widget.jobOrderId);
    if (job == null) {
      throw Exception('Job order not found.');
    }
    final vehicles = await widget.service.fetchVehicles(leaserId: widget.leaserId);
    final vendors = await widget.service.fetchVendors();
    final attachments = await widget.service.fetchJobAttachments(widget.jobOrderId);
    final activities = await widget.service.fetchJobActivities(widget.jobOrderId);
    final costs = await widget.service.fetchServiceCostsForJob(widget.jobOrderId);

    final vehicleMap = widget.service.indexBy(vehicles, 'vehicle_id');
    final vendorMap = widget.service.indexBy(vendors, 'vendor_id');

    return _JobOrderDetailBundle(
      job: job,
      vehicle: vehicleMap[_string(job['vehicle_id'])],
      vendor: vendorMap[_string(job['vendor_id'])],
      attachments: attachments,
      activities: activities,
      costs: costs,
      vendors: vendors,
    );
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _load();
    });
    await _future;
  }

  Future<void> _openAttachment(Map<String, dynamic> attachment) async {
    final url = await widget.service.createSignedAttachmentUrl(_string(attachment['file_path']));
    if (!mounted) return;
    if ((url ?? '').trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the selected attachment.')),
      );
      return;
    }

    final uri = Uri.tryParse(url!);
    if (uri == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid attachment link.')),
      );
      return;
    }

    var opened = false;
    try {
      opened = await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
    } catch (_) {}

    if (!opened) {
      try {
        opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {}
    }

    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the file.')),
      );
    }
  }

  Future<void> _pickAndUpload() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        withData: true,
        type: FileType.custom,
        allowedExtensions: const ['png', 'jpg', 'jpeg', 'pdf'],
      );
      if (result == null || result.files.isEmpty) return;

      final file = result.files.single;
      if (file.size > 10 * 1024 * 1024) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Attachment must be 10MB or smaller.')),
        );
        return;
      }

      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not read the selected file.')),
        );
        return;
      }

      final user = Supabase.instance.client.auth.currentUser;
      final actor = _string(user?.email).isEmpty ? _string(user?.id) : _string(user?.email);
      await widget.service.uploadAttachment(
        jobOrderId: widget.jobOrderId,
        bytes: bytes,
        fileName: file.name,
        uploadedBy: actor,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Attachment uploaded.')),
      );
      await _refresh();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.service.explainError(error)),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _openAssignVendor(_JobOrderDetailBundle bundle) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _AssignVendorPage(
          service: widget.service,
          job: bundle.job,
          vehicle: bundle.vehicle,
          vendors: bundle.vendors,
        ),
      ),
    );
    if (!mounted) return;
    await _refresh();
  }

  Future<void> _openUpdateStatus(_JobOrderDetailBundle bundle) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _UpdateJobStatusPage(
          service: widget.service,
          job: bundle.job,
          availableStatuses: widget.allowCancelledStatus
              ? _statuses
              : _statuses.where((status) => status != 'Cancelled').toList(),
        ),
      ),
    );
    if (!mounted) return;
    await _refresh();
  }

  Future<void> _showCostDialog(_JobOrderDetailBundle bundle) async {
    final costs = bundle.costs;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Cost Summary',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                Text(
                  'Job Order ${_string(bundle.job['job_order_id'])}',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
                if (costs.isEmpty)
                  const Text('No detailed service cost record has been added yet.')
                else
                  ...costs.map(
                        (cost) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: AdminCard(
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _friendlyDate(cost['service_date']),
                                style: const TextStyle(fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 10),
                              _DetailLine(label: 'Labour', value: _money(cost['labour_cost'])),
                              _DetailLine(label: 'Parts', value: _money(cost['parts_cost'])),
                              _DetailLine(label: 'Misc', value: _money(cost['misc_cost'])),
                              _DetailLine(label: 'Tax', value: _money(cost['tax_cost'])),
                              _DetailLine(label: 'Total', value: _money(cost['total_cost'])),
                              _DetailLine(label: 'Invoice Ref', value: _string(cost['invoice_ref']).isEmpty ? '-' : _string(cost['invoice_ref'])),
                              const SizedBox(height: 8),
                              AdminStatusChip(status: _string(cost['payment_status']).isEmpty ? 'Pending' : _string(cost['payment_status'])),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.jobOrderId),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: FutureBuilder<_JobOrderDetailBundle>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _JobSqlErrorView(message: widget.service.explainError(snapshot.error!));
          }

          final bundle = snapshot.data;
          if (bundle == null) {
            return const Center(child: Text('No details found.'));
          }

          final job = bundle.job;
          final vehicle = bundle.vehicle;
          final vendor = bundle.vendor;
          final totalCost = bundle.costs.isEmpty
              ? _amount(job['actual_cost'])
              : bundle.costs.fold<double>(0, (sum, cost) => sum + _amount(cost['total_cost']));

          return SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                    children: [
                      AdminCard(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _string(job['job_order_id']),
                                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Job Order Details',
                                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                              ),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  AdminStatusChip(status: _string(job['status'])),
                                  _PriorityChip(priority: _string(job['priority'])),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      _SectionCard(
                        title: 'Vehicle Information',
                        icon: Icons.directions_car_filled_outlined,
                        child: Column(
                          children: [
                            _DetailLine(label: 'Plate Number', value: _string(vehicle?['vehicle_plate_no']).isEmpty ? '-' : _string(vehicle?['vehicle_plate_no'])),
                            _DetailLine(label: 'Model', value: '${_string(vehicle?['vehicle_brand'])} ${_string(vehicle?['vehicle_model'])} ${_string(vehicle?['vehicle_year']).isEmpty ? '' : '(${_string(vehicle?['vehicle_year'])})'}'.trim()),
                            _DetailLine(label: 'Mileage', value: _string(vehicle?['mileage_km']).isEmpty ? '-' : '${_string(vehicle?['mileage_km'])} km'),
                            _DetailLine(label: 'Current Location', value: _string(vehicle?['vehicle_location']).isEmpty ? '-' : _string(vehicle?['vehicle_location'])),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      _SectionCard(
                        title: 'Job Details',
                        icon: Icons.handyman_outlined,
                        child: Column(
                          children: [
                            _DetailLine(label: 'Job Type', value: _string(job['job_type'])),
                            _DetailLine(label: 'Requested By', value: _string(job['requested_by']).isEmpty ? '-' : _string(job['requested_by'])),
                            _DetailLine(label: 'Requested Date', value: _friendlyDateTime(job['created_at'])),
                            _DetailLine(label: 'Schedule', value: _friendlyDate(job['preferred_date'])),
                            const SizedBox(height: 10),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'Problem Description',
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(_string(job['problem_description']).isEmpty ? '-' : _string(job['problem_description'])),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      _SectionCard(
                        title: 'Vendor Assigned',
                        icon: Icons.storefront_outlined,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _DetailLine(label: 'Vendor', value: vendor == null ? 'Not assigned yet' : widget.service.vendorLabel(vendor)),
                            _DetailLine(label: 'Contact Person', value: _string(vendor?['contact_person']).isEmpty ? '-' : _string(vendor?['contact_person'])),
                            _DetailLine(label: 'Phone', value: _string(vendor?['vendor_phone']).isEmpty ? '-' : _string(vendor?['vendor_phone'])),
                            _DetailLine(label: 'Rating', value: _string(vendor?['vendor_rating']).isEmpty ? '-' : _string(vendor?['vendor_rating'])),
                            const SizedBox(height: 10),
                            if (widget.allowVendorReassign)
                              OutlinedButton.icon(
                                onPressed: () => _openAssignVendor(bundle),
                                icon: const Icon(Icons.assignment_ind_outlined),
                                label: Text(vendor == null ? 'Assign Vendor' : 'Change Vendor'),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      _SectionCard(
                        title: 'Cost Summary',
                        icon: Icons.payments_outlined,
                        child: Column(
                          children: [
                            _DetailLine(label: 'Total Cost', value: _money(totalCost)),
                            _DetailLine(label: 'Service Cost Records', value: '${bundle.costs.length}'),
                            if (bundle.costs.length > 1)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    'This job order has ${bundle.costs.length} service cost records. Tap View Cost to review each one clearly.',
                                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      _SectionCard(
                        title: 'Attachments',
                        icon: Icons.attach_file_outlined,
                        trailing: Text(
                          '${bundle.attachments.length}',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        child: bundle.attachments.isEmpty
                            ? const Text('No attachments uploaded yet.')
                            : Column(
                          children: bundle.attachments
                              .map(
                                (attachment) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: AdminCard(
                                child: ListTile(
                                  leading: Icon(
                                    _string(attachment['file_name']).toLowerCase().endsWith('.pdf')
                                        ? Icons.picture_as_pdf_outlined
                                        : Icons.image_outlined,
                                  ),
                                  title: Text(
                                    _string(attachment['file_name']),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Text(
                                    '${_string(attachment['uploaded_by']).isEmpty ? 'Uploaded by admin' : _string(attachment['uploaded_by'])}\n${_friendlyDateTime(attachment['created_at'])}',
                                  ),
                                  trailing: IconButton(
                                    tooltip: 'Open file',
                                    onPressed: () => _openAttachment(attachment),
                                    icon: const Icon(Icons.open_in_new_rounded),
                                  ),
                                ),
                              ),
                            ),
                          )
                              .toList(),
                        ),
                      ),
                      const SizedBox(height: 14),
                      _SectionCard(
                        title: 'Activity Log',
                        icon: Icons.history_rounded,
                        child: bundle.activities.isEmpty
                            ? const Text('No activity recorded yet.')
                            : Column(
                          children: bundle.activities
                              .map(
                                (activity) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _ActivityTile(activity: activity),
                            ),
                          )
                              .toList(),
                        ),
                      ),
                    ],
                  ),
                ),
                if ((widget.leaserId ?? '').trim().isNotEmpty)
                  SafeArea(
                    top: false,
                    minimum: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _pickAndUpload,
                            icon: const Icon(Icons.upload_file_outlined),
                            label: const Text('Upload'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _showCostDialog(bundle),
                            icon: const Icon(Icons.receipt_long_outlined),
                            label: const Text('View Cost'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () => _openUpdateStatus(bundle),
                            icon: const Icon(Icons.update_rounded),
                            label: const Text('Update Status'),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _JobOrderDetailBundle {
  const _JobOrderDetailBundle({
    required this.job,
    required this.vehicle,
    required this.vendor,
    required this.attachments,
    required this.activities,
    required this.costs,
    required this.vendors,
  });

  final Map<String, dynamic> job;
  final Map<String, dynamic>? vehicle;
  final Map<String, dynamic>? vendor;
  final List<Map<String, dynamic>> attachments;
  final List<Map<String, dynamic>> activities;
  final List<Map<String, dynamic>> costs;
  final List<Map<String, dynamic>> vendors;
}
class _UpdateJobStatusPage extends StatefulWidget {
  const _UpdateJobStatusPage({
    required this.service,
    required this.job,
    required this.availableStatuses,
  });

  final JobOrderModuleService service;
  final Map<String, dynamic> job;
  final List<String> availableStatuses;

  @override
  State<_UpdateJobStatusPage> createState() => _UpdateJobStatusPageState();
}

class _UpdateJobStatusPageState extends State<_UpdateJobStatusPage> {
  final _remarksController = TextEditingController();
  late Future<List<Map<String, dynamic>>> _historyFuture;
  late String _newStatus;
  bool _saving = false;

  bool get _canSubmit =>
      !_saving && _newStatus != _string(widget.job['status']) && _remarksController.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _newStatus = _string(widget.job['status']).isEmpty ? 'Pending' : _string(widget.job['status']);
    _historyFuture = widget.service.fetchJobActivities(_string(widget.job['job_order_id']));
    _remarksController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _remarksController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;

    setState(() => _saving = true);
    try {
      await widget.service.updateJobStatus(
        jobOrderId: _string(widget.job['job_order_id']),
        currentStatus: _string(widget.job['status']),
        newStatus: _newStatus,
        remarks: _remarksController.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Job status updated.')),
      );
      Navigator.of(context).pop();
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
      appBar: AppBar(title: const Text('Update Job Status')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        children: [
          Text(
            _string(widget.job['job_order_id']),
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          _SectionCard(
            title: 'Current Status',
            icon: Icons.info_outline_rounded,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DetailLine(label: 'Vehicle', value: _string(widget.job['vehicle_id'])),
                _DetailLine(label: 'Job Type', value: _string(widget.job['job_type'])),
                const SizedBox(height: 8),
                AdminStatusChip(status: _string(widget.job['status'])),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _SectionCard(
            title: 'New Status',
            icon: Icons.sync_alt_rounded,
            child: Column(
              children: widget.availableStatuses
                  .map(
                    (status) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: InkWell(
                    onTap: () => setState(() => _newStatus = status),
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: _newStatus == status
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.outlineVariant,
                          width: _newStatus == status ? 1.5 : 1,
                        ),
                        color: _newStatus == status
                            ? Theme.of(context).colorScheme.primaryContainer.withOpacity(0.35)
                            : Colors.transparent,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  status,
                                  style: const TextStyle(fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: 4),
                                Text(_statusHint(status)),
                              ],
                            ),
                          ),
                          if (_newStatus == status)
                            Icon(Icons.check_circle_rounded, color: Theme.of(context).colorScheme.primary),
                        ],
                      ),
                    ),
                  ),
                ),
              )
                  .toList(),
            ),
          ),
          const SizedBox(height: 14),
          _SectionCard(
            title: 'Remarks',
            icon: Icons.edit_note_outlined,
            child: Column(
              children: [
                TextField(
                  controller: _remarksController,
                  maxLines: 4,
                  maxLength: 500,
                  decoration: const InputDecoration(
                    hintText: 'Explain the update for the activity log and team visibility.',
                  ),
                ),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.35),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Theme.of(context).colorScheme.primary.withOpacity(0.2)),
                  ),
                  child: Text(
                    'This update will be recorded in the activity log and all relevant parties will be notified.',
                    style: TextStyle(color: Theme.of(context).colorScheme.primary),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _canSubmit ? _submit : null,
            icon: _saving
                ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
                : const Icon(Icons.check_circle_outline),
            label: Text(_saving ? 'Saving...' : 'Confirm Update'),
          ),
          const SizedBox(height: 18),
          const Text(
            'Status Update History',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _historyFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (snapshot.hasError) {
                return _EmptyCard(message: widget.service.explainError(snapshot.error!));
              }

              final history = (snapshot.data ?? <Map<String, dynamic>>[])
                  .where((row) => _string(row['from_status']).isNotEmpty || _string(row['to_status']).isNotEmpty)
                  .toList();

              if (history.isEmpty) {
                return const _EmptyCard(message: 'No status updates recorded yet.');
              }

              return Column(
                children: history
                    .map(
                      (row) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: AdminCard(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                if (_string(row['from_status']).isNotEmpty)
                                  AdminStatusChip(status: _string(row['from_status'])),
                                if (_string(row['from_status']).isNotEmpty)
                                  const Padding(
                                    padding: EdgeInsets.symmetric(horizontal: 8),
                                    child: Icon(Icons.arrow_right_alt_rounded),
                                  ),
                                if (_string(row['to_status']).isNotEmpty)
                                  AdminStatusChip(status: _string(row['to_status'])),
                                const Spacer(),
                                Text(
                                  _relativeTime(row['created_at']),
                                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(_string(row['detail']).isEmpty ? _string(row['title']) : _string(row['detail'])),
                            const SizedBox(height: 8),
                            Text(
                              '${_string(row['actor_name']).isEmpty ? 'System' : _string(row['actor_name'])} | ${_friendlyDateTime(row['created_at'])}',
                              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                )
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}
class _AssignVendorPage extends StatefulWidget {
  const _AssignVendorPage({
    required this.service,
    required this.job,
    required this.vehicle,
    required this.vendors,
  });

  final JobOrderModuleService service;
  final Map<String, dynamic> job;
  final Map<String, dynamic>? vehicle;
  final List<Map<String, dynamic>> vendors;

  @override
  State<_AssignVendorPage> createState() => _AssignVendorPageState();
}

class _AssignVendorPageState extends State<_AssignVendorPage> {
  String _query = '';
  String _category = 'All Services';
  bool _saving = false;

  List<String> get _categories {
    final values = widget.vendors
        .map((row) => _string(row['service_category']))
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return ['All Services', ...values];
  }

  List<Map<String, dynamic>> get _filteredVendors {
    final query = _query.trim().toLowerCase();
    return widget.vendors.where((vendor) {
      final category = _string(vendor['service_category']);
      final matchesCategory = _category == 'All Services' || category == _category;
      if (!matchesCategory) return false;
      if (query.isEmpty) return true;
      final haystack = [
        _string(vendor['vendor_name']),
        _string(vendor['service_category']),
        _string(vendor['contact_person']),
        _string(vendor['vendor_email']),
        _string(vendor['vendor_phone']),
      ].join(' ').toLowerCase();
      return haystack.contains(query);
    }).toList();
  }

  Future<void> _assign(String vendorId) async {
    setState(() => _saving = true);
    try {
      await widget.service.assignVendor(
        jobOrderId: _string(widget.job['job_order_id']),
        vendorId: vendorId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vendor assigned successfully.')),
      );
      Navigator.of(context).pop();
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
    final currentVendorId = _string(widget.job['vendor_id']);

    return Scaffold(
      appBar: AppBar(title: const Text('Assign Vendor')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        children: [
          AdminCard(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_string(widget.job['job_order_id'])} - ${_string(widget.job['job_type'])}',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${_string(widget.vehicle?['vehicle_plate_no'])} - ${_string(widget.vehicle?['vehicle_brand'])} ${_string(widget.vehicle?['vehicle_model'])}'.trim(),
                    style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            decoration: const InputDecoration(
              hintText: 'Search vendors or services',
              prefixIcon: Icon(Icons.search_rounded),
            ),
            onChanged: (value) => setState(() => _query = value),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _categories
                .map(
                  (category) => ChoiceChip(
                label: Text(category),
                selected: _category == category,
                onSelected: (_) => setState(() => _category = category),
              ),
            )
                .toList(),
          ),
          const SizedBox(height: 16),
          Text(
            '${_filteredVendors.length} vendor${_filteredVendors.length == 1 ? '' : 's'} found',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          if (_filteredVendors.isEmpty)
            const _EmptyCard(message: 'No vendors match the current search or service filter.')
          else
            ..._filteredVendors.map(
                  (vendor) => Padding(
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
                                _string(vendor['vendor_name']),
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                              ),
                            ),
                            if (currentVendorId == _string(vendor['vendor_id']))
                              const AdminStatusChip(status: 'Current')
                            else
                              AdminStatusChip(status: _string(vendor['vendor_status']).isEmpty ? 'Available' : _string(vendor['vendor_status'])),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _MiniInfoChip(icon: Icons.star_rounded, label: _string(vendor['vendor_rating']).isEmpty ? '0.0' : _string(vendor['vendor_rating'])),
                            _MiniInfoChip(icon: Icons.handyman_outlined, label: _string(vendor['service_category']).isEmpty ? 'General' : _string(vendor['service_category'])),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _DetailLine(label: 'Contact', value: _string(vendor['contact_person']).isEmpty ? '-' : _string(vendor['contact_person'])),
                        _DetailLine(label: 'Phone', value: _string(vendor['vendor_phone']).isEmpty ? '-' : _string(vendor['vendor_phone'])),
                        _DetailLine(label: 'Email', value: _string(vendor['vendor_email']).isEmpty ? '-' : _string(vendor['vendor_email'])),
                        _DetailLine(label: 'Address', value: _string(vendor['vendor_address']).isEmpty ? '-' : _string(vendor['vendor_address'])),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _saving ? null : () => _assign(_string(vendor['vendor_id'])),
                            icon: const Icon(Icons.assignment_turned_in_outlined),
                            label: Text(currentVendorId == _string(vendor['vendor_id']) ? 'Reassign Vendor' : 'Assign Vendor'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
    this.trailing,
  });

  final String title;
  final IconData icon;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return AdminCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.label,
    required this.value,
    required this.tint,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String value;
  final Color tint;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 78,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: tint.withOpacity(selected ? 0.16 : 0.06),
            border: Border.all(
              color: selected ? tint.withOpacity(0.8) : tint.withOpacity(0.18),
            ),
          ),
          child: Column(
            children: [
              Text(
                value,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: tint),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(color: tint, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PriorityChip extends StatelessWidget {
  const _PriorityChip({required this.priority});

  final String priority;

  @override
  Widget build(BuildContext context) {
    final value = priority.trim().toLowerCase();
    Color bg;
    Color fg;
    if (value == 'urgent') {
      bg = Colors.red.withOpacity(0.12);
      fg = Colors.red.shade700;
    } else if (value == 'high') {
      bg = Colors.orange.withOpacity(0.15);
      fg = Colors.orange.shade900;
    } else if (value == 'medium') {
      bg = Colors.blue.withOpacity(0.12);
      fg = Colors.blue.shade700;
    } else {
      bg = Colors.green.withOpacity(0.12);
      fg = Colors.green.shade700;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: fg.withOpacity(0.2)),
      ),
      child: Text(
        priority.isEmpty ? '-' : priority,
        style: TextStyle(fontWeight: FontWeight.w800, color: fg, fontSize: 12),
      ),
    );
  }
}

class _MiniInfoChip extends StatelessWidget {
  const _MiniInfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.55),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14),
          const SizedBox(width: 6),
          Text(label),
        ],
      ),
    );
  }
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

class _ActivityTile extends StatelessWidget {
  const _ActivityTile({required this.activity});

  final Map<String, dynamic> activity;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                shape: BoxShape.circle,
              ),
            ),
            Container(
              width: 2,
              height: 54,
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _string(activity['title']).isEmpty ? 'Activity' : _string(activity['title']),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              if (_string(activity['detail']).isNotEmpty)
                Text(_string(activity['detail'])),
              const SizedBox(height: 4),
              Text(
                '${_string(activity['actor_name']).isEmpty ? 'System' : _string(activity['actor_name'])} | ${_relativeTime(activity['created_at'])}',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _JobSqlErrorView extends StatelessWidget {
  const _JobSqlErrorView({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Job Order module needs setup',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        Text(message),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: Colors.black.withValues(alpha: 0.05),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Run the SQL in supabase/job_order_chapter4_patch.sql to create the Job Order tables, activity log, and attachment bucket.'),
              SizedBox(height: 8),
              SelectableText('supabase/job_order_chapter4_patch.sql'),
            ],
          ),
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

class _PickedJobFile {
  const _PickedJobFile({
    required this.name,
    required this.bytes,
    required this.sizeBytes,
  });

  final String name;
  final Uint8List bytes;
  final int sizeBytes;
}

String _string(dynamic value) => value == null ? '' : value.toString().trim();

double _amount(dynamic value) {
  if (value == null) return 0;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString()) ?? 0;
}

Map<String, double> _costTotalsByJob(List<Map<String, dynamic>> costs) {
  final totals = <String, double>{};
  for (final cost in costs) {
    final jobOrderId = _string(cost['job_order_id']);
    if (jobOrderId.isEmpty) continue;
    totals[jobOrderId] = (totals[jobOrderId] ?? 0) + _amount(cost['total_cost']);
  }
  return totals;
}

Map<String, int> _costCountsByJob(List<Map<String, dynamic>> costs) {
  final counts = <String, int>{};
  for (final cost in costs) {
    final jobOrderId = _string(cost['job_order_id']);
    if (jobOrderId.isEmpty) continue;
    counts[jobOrderId] = (counts[jobOrderId] ?? 0) + 1;
  }
  return counts;
}

String _money(dynamic value) {
  final number = _amount(value);
  return 'RM ${number.toStringAsFixed(2)}';
}

String _friendlyDate(dynamic raw) {
  if (raw == null || raw.toString().trim().isEmpty) return '-';
  final value = raw is DateTime ? raw : DateTime.tryParse(raw.toString());
  if (value == null) return '-';
  return '${value.day} ${_monthName(value.month)} ${value.year}';
}

String _friendlyDateTime(dynamic raw) {
  if (raw == null || raw.toString().trim().isEmpty) return '-';
  final value = raw is DateTime ? raw : DateTime.tryParse(raw.toString());
  if (value == null) return '-';
  final hour = value.hour == 0 ? 12 : (value.hour > 12 ? value.hour - 12 : value.hour);
  final minute = value.minute.toString().padLeft(2, '0');
  final suffix = value.hour >= 12 ? 'PM' : 'AM';
  return '${value.day} ${_monthName(value.month)} ${value.year}, ${hour.toString().padLeft(2, '0')}:$minute $suffix';
}

String _monthName(int month) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  if (month < 1 || month > 12) return '-';
  return months[month - 1];
}

String _relativeTime(dynamic raw) {
  final value = raw is DateTime ? raw : DateTime.tryParse(raw == null ? '' : raw.toString());
  if (value == null) return '-';
  final diff = DateTime.now().difference(value.toLocal());
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inHours < 1) return '${diff.inMinutes}m ago';
  if (diff.inDays < 1) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return _friendlyDate(value);
}

String _statusHint(String status) {
  switch (status) {
    case 'Pending':
      return 'Job is waiting to be started.';
    case 'In Progress':
      return 'Work is currently ongoing.';
    case 'Completed':
      return 'Job has been finished.';
    case 'Cancelled':
      return 'Job was cancelled.';
    default:
      return 'Update the current job order status.';
  }
}

String _fileSizeLabel(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
  final mb = kb / 1024;
  return '${mb.toStringAsFixed(1)} MB';
}





















