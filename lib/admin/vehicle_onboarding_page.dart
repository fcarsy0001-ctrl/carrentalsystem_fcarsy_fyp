import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/vehicle_onboarding_service.dart';
import 'vehicle_details_page.dart';
import 'vehicle_eligibility_result_page.dart';
import 'vehicle_registration_page.dart';
import 'widgets/admin_ui.dart';

class VehicleOnboardingPage extends StatefulWidget {
  const VehicleOnboardingPage({
    super.key,
    this.leaserId,
    this.title,
    this.embedded = false,
  });

  final String? leaserId;
  final String? title;
  final bool embedded;

  @override
  State<VehicleOnboardingPage> createState() => _VehicleOnboardingPageState();
}

class _VehicleOnboardingPageState extends State<VehicleOnboardingPage> {
  final _searchController = TextEditingController();
  late final VehicleOnboardingService _service;

  late Future<List<Map<String, dynamic>>> _future;
  String _filter = 'All';

  bool get _isAdminMode => (widget.leaserId ?? '').trim().isEmpty;

  @override
  void initState() {
    super.initState();
    _service = VehicleOnboardingService(Supabase.instance.client);
    _future = _load();
    _searchController.addListener(_handleSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_handleSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _handleSearchChanged() {
    setState(() {});
  }

  Future<List<Map<String, dynamic>>> _load() {
    return _service.fetchVehicles(leaserId: widget.leaserId);
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _load();
    });
    await _future;
  }

  Future<void> _openRegistration({Map<String, dynamic>? initial}) async {
    final vehicleId = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => VehicleRegistrationPage(
          initial: initial,
          isAdminMode: _isAdminMode,
          fixedLeaserId: widget.leaserId,
        ),
      ),
    );

    if (vehicleId == null || vehicleId.trim().isEmpty) return;
    await _refresh();
    if (!mounted) return;
    final detail = await _service.fetchVehicleDetail(vehicleId);
    if (detail == null || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VehicleEligibilityResultPage(
          initialRecord: detail,
          isAdminMode: _isAdminMode,
        ),
      ),
    );
    await _refresh();
  }

  Future<void> _openDetails(Map<String, dynamic> record) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VehicleDetailsPage(
          initialRecord: record,
          isAdminMode: _isAdminMode,
          fixedLeaserId: widget.leaserId,
        ),
      ),
    );
    await _refresh();
  }

  Future<void> _openEligibility(Map<String, dynamic> record) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VehicleEligibilityResultPage(
          initialRecord: record,
          isAdminMode: _isAdminMode,
        ),
      ),
    );
    await _refresh();
  }

  List<Map<String, dynamic>> _applyFilters(List<Map<String, dynamic>> rows) {
    final query = _searchController.text.trim().toLowerCase();
    return rows.where((row) {
      final haystack = [
        _s(row['vehicle_plate_no']),
        _s(row['vehicle_brand']),
        _s(row['vehicle_model']),
        _s(row['vehicle_id']),
        _s(row['vehicle_status']),
        _s(row['condition_status']),
        _s(row['eligibility_status']),
        _s(row['readiness_status']),
        _s(row['review_status']),
        _activityStatus(row),
      ].join(' ').toLowerCase();

      final matchesSearch = query.isEmpty || haystack.contains(query);
      final matchesFilter = switch (_filter) {
        'Pending Review' => _s(row['review_status']) == 'Pending Review',
        'Approved' => _s(row['review_status']) == 'Approved',
        'Rejected' => _s(row['review_status']) == 'Rejected',
        'Eligible' => _s(row['eligibility_status']) == 'Eligible',
        'Ready' => _s(row['readiness_status']) == 'Ready',
        'Active' => _activityStatus(row) == 'Active',
        'Maintenance' => _activityStatus(row) == 'Maintenance',
        _ => true,
      };

      return matchesSearch && matchesFilter;
    }).toList();
  }

  String _s(dynamic value) => value == null ? '' : value.toString().trim();

  String _activityStatus(Map<String, dynamic> row) {
    final raw = _s(row['vehicle_status']);
    final status = raw.toLowerCase();
    if (status == 'available' || status == 'active') return 'Active';
    if (status.contains('maint') || status == 'unavail' || status == 'unavailable') return 'Maintenance';
    return raw.isEmpty ? 'Pending' : raw;
  }

  Widget _buildBody(List<Map<String, dynamic>> rows) {
    final filtered = _applyFilters(rows);

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        children: [
          _buildToolbar(filtered.length),
          const SizedBox(height: 10),
          if (filtered.isEmpty)
            _EmptyVehiclesCard(
              isAdminMode: _isAdminMode,
              onAddPressed: () => _openRegistration(),
              showAddButton: !widget.embedded,
            )
          else
            ...filtered.map(
                  (record) => Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: _VehicleSummaryCard(
                  record: record,
                  isAdminMode: _isAdminMode,
                  onEdit: () => _openRegistration(initial: record),
                  activityStatus: _activityStatus(record),
                  onViewDetails: () => _openDetails(record),
                  onViewEligibility: () => _openEligibility(record),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildToolbar(int count) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.title ?? (_isAdminMode ? 'Vehicle List' : 'My Vehicle List'),
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _isAdminMode
                        ? 'Fleet management for onboarding and eligibility control'
                        : 'Track your submitted vehicles and onboarding progress',
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            if (!widget.embedded && count > 0) ...[
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: () => _openRegistration(),
                icon: const Icon(Icons.add_circle_outline),
                label: const Text('Add Vehicle'),
              ),
            ],
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search vehicles...',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: PopupMenuButton<String>(
                    tooltip: 'Filter list',
                    initialValue: _filter,
                    onSelected: (value) => setState(() => _filter = value),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'All', child: Text('All vehicles')),
                      PopupMenuItem(value: 'Pending Review', child: Text('Pending review')),
                      PopupMenuItem(value: 'Approved', child: Text('Approved')),
                      PopupMenuItem(value: 'Rejected', child: Text('Rejected')),
                      PopupMenuItem(value: 'Eligible', child: Text('Eligible')),
                      PopupMenuItem(value: 'Ready', child: Text('Ready')),
                      PopupMenuItem(value: 'Active', child: Text('Active')),
                      PopupMenuItem(value: 'Maintenance', child: Text('Maintenance')),
                    ],
                    icon: const Icon(Icons.tune_rounded),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Text(
              '$count vehicle${count == 1 ? '' : 's'} found',
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 10),
            if (_filter != 'All')
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: cs.secondaryContainer,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  _filter,
                  style: TextStyle(
                    color: cs.onSecondaryContainer,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final content = FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Text(_service.explainError(snapshot.error!)),
            ),
          );
        }
        return _buildBody(snapshot.data ?? const []);
      },
    );

    if (widget.embedded) {
      return Column(
        children: [
          AdminModuleHeader(
            icon: Icons.fact_check_outlined,
            title: widget.title ?? (_isAdminMode ? 'Vehicle Onboarding' : 'My Vehicles'),
            subtitle: _isAdminMode
                ? 'Review new vehicles, update condition, and manage eligibility.'
                : 'Register new vehicles and monitor their onboarding status.',
            actions: [
              IconButton(
                tooltip: 'Refresh',
                onPressed: _refresh,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
            primaryActions: [
              FilledButton.icon(
                onPressed: () => _openRegistration(),
                icon: const Icon(Icons.add),
                label: const Text('Add vehicle'),
              ),
            ],
          ),
          const Divider(height: 1),
          Expanded(child: content),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title ?? (_isAdminMode ? 'Vehicle Onboarding' : 'My Vehicles')),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: content,
    );
  }
}

class _VehicleSummaryCard extends StatelessWidget {
  const _VehicleSummaryCard({
    required this.record,
    required this.isAdminMode,
    required this.onEdit,
    required this.activityStatus,
    required this.onViewDetails,
    required this.onViewEligibility,
  });

  final Map<String, dynamic> record;
  final bool isAdminMode;
  final VoidCallback onEdit;
  final String activityStatus;
  final VoidCallback onViewDetails;
  final VoidCallback onViewEligibility;

  String _s(dynamic value) => value == null ? '' : value.toString().trim();

  int _i(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString()) ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final plate = _s(record['vehicle_plate_no']);
    final year = _i(record['vehicle_year']);
    final title = '${_s(record['vehicle_brand'])} ${_s(record['vehicle_model'])}'.trim();
    final mileage = _i(record['mileage_km']);
    final condition = _s(record['condition_status']).isEmpty ? 'Pending' : _s(record['condition_status']);
    final eligibility = _s(record['eligibility_status']).isEmpty ? 'Pending' : _s(record['eligibility_status']);
    final readiness = _s(record['readiness_status']).isEmpty ? 'Pending' : _s(record['readiness_status']);
    final review = _s(record['review_status']).isEmpty ? 'Pending Review' : _s(record['review_status']);
    final displayStatus = activityStatus.trim().isEmpty ? 'Pending' : activityStatus.trim();

    return AdminCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [cs.primary, cs.primary.withOpacity(0.86)],
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.16),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(Icons.directions_car_outlined, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        plate.isEmpty ? _s(record['vehicle_id']) : plate,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        title.isEmpty ? 'Vehicle' : title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  year <= 0 ? '-' : '$year',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _MetricBlock(
                        label: 'Mileage',
                        value: mileage <= 0 ? '-' : '$mileage km',
                      ),
                    ),
                    Expanded(
                      child: _MetricChipBlock(
                        label: 'Condition',
                        value: condition,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _MetricChipBlock(
                        label: 'Eligibility',
                        value: eligibility,
                      ),
                    ),
                    Expanded(
                      child: _MetricChipBlock(
                        label: 'Readiness',
                        value: readiness,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      AdminStatusChip(status: review),
                      AdminStatusChip(status: displayStatus),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: onViewDetails,
                        icon: const Icon(Icons.visibility_outlined),
                        label: const Text('View Details'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: onViewEligibility,
                        icon: const Icon(Icons.verified_outlined),
                        label: const Text('Eligibility'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    if (isAdminMode)
                      IconButton.filledTonal(
                        onPressed: onEdit,
                        icon: const Icon(Icons.edit_outlined),
                        tooltip: 'Edit vehicle',
                      )
                    else
                      IconButton.outlined(
                        onPressed: onEdit,
                        icon: const Icon(Icons.edit_outlined),
                        tooltip: 'Update submission',
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricBlock extends StatelessWidget {
  const _MetricBlock({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ],
    );
  }
}

class _MetricChipBlock extends StatelessWidget {
  const _MetricChipBlock({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: AdminStatusChip(status: value),
        ),
      ],
    );
  }
}

class _EmptyVehiclesCard extends StatelessWidget {
  const _EmptyVehiclesCard({
    required this.isAdminMode,
    required this.onAddPressed,
    required this.showAddButton,
  });

  final bool isAdminMode;
  final VoidCallback onAddPressed;
  final bool showAddButton;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.5)),
      ),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              borderRadius: BorderRadius.circular(20),
            ),
            alignment: Alignment.center,
            child: Icon(Icons.directions_car_filled_outlined, color: cs.onPrimaryContainer, size: 30),
          ),
          const SizedBox(height: 14),
          Text(
            isAdminMode ? 'No vehicle submissions yet' : 'No vehicles submitted yet',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text(
            isAdminMode
                ? 'New onboarding submissions will appear here for review and approval.'
                : 'Start by registering your first vehicle for inspection and onboarding.',
            textAlign: TextAlign.center,
            style: TextStyle(color: cs.onSurfaceVariant, height: 1.4),
          ),
          if (showAddButton) ...[
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onAddPressed,
              icon: const Icon(Icons.add),
              label: const Text('Add Vehicle'),
            ),
          ],
        ],
      ),
    );
  }
}

