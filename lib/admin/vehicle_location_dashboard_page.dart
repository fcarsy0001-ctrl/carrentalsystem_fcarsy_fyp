import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/vehicle_location_service.dart';
import 'confirm_vehicle_location_page.dart';
import 'vehicle_location_admin_page.dart';
import 'vehicle_location_history_page.dart';
import 'widgets/admin_ui.dart';

DateTime _toMalaysiaTime(DateTime value) {
  if (value.isUtc) return value.add(const Duration(hours: 8));
  return value.subtract(value.timeZoneOffset).add(const Duration(hours: 8));
}

String _formatLocationTimestamp(dynamic value) {
  final raw = value == null ? '' : value.toString().trim();
  if (raw.isEmpty) return 'No updates yet';

  final parsed = DateTime.tryParse(raw);
  if (parsed == null) return raw.replaceFirst('T', ' ').replaceFirst('Z', '');

  final malaysia = _toMalaysiaTime(parsed);
  final day = malaysia.day.toString().padLeft(2, '0');
  final month = malaysia.month.toString().padLeft(2, '0');
  final hour = malaysia.hour % 12 == 0 ? 12 : malaysia.hour % 12;
  final minute = malaysia.minute.toString().padLeft(2, '0');
  final suffix = malaysia.hour >= 12 ? 'PM' : 'AM';

  return '$day/$month/${malaysia.year}, ${hour.toString().padLeft(2, '0')}:$minute $suffix MYT';
}

class VehicleLocationDashboardPage extends StatefulWidget {
  const VehicleLocationDashboardPage({
    super.key,
    this.leaserId,
    this.title,
    this.embedded = false,
    this.allowManageLocations = true,
  });

  final String? leaserId;
  final String? title;
  final bool embedded;
  final bool allowManageLocations;

  @override
  State<VehicleLocationDashboardPage> createState() => _VehicleLocationDashboardPageState();
}

class _VehicleLocationDashboardPageState extends State<VehicleLocationDashboardPage> {
  final _searchController = TextEditingController();
  late final VehicleLocationService _service;
  late Future<_LocationDashboardData> _future;

  String _statusFilter = 'All';

  bool get _isAdminMode => (widget.leaserId ?? '').trim().isEmpty;

  @override
  void initState() {
    super.initState();
    _service = VehicleLocationService(Supabase.instance.client);
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

  Future<_LocationDashboardData> _load() async {
    final vehicles = await _service.fetchVehicles(leaserId: widget.leaserId);
    final history = await _service.fetchHistory();
    final activeLocations = await _service.fetchLocationActiveMap();
    final latestByVehicle = <String, Map<String, dynamic>>{};
    for (final row in history) {
      final vehicleId = _s(row['vehicle_id']);
      if (vehicleId.isNotEmpty && !latestByVehicle.containsKey(vehicleId)) {
        latestByVehicle[vehicleId] = row;
      }
    }

    final enriched = vehicles.map((vehicle) {
      final latest = latestByVehicle[_s(vehicle['vehicle_id'])];
      final record = {
        ...vehicle,
        'branch_is_active': activeLocations[_s(vehicle['vehicle_location'])] ?? true,
        'current_parking_slot': _service.currentParkingSlot(vehicle, latestHistory: latest),
        'location_last_updated': _service.currentUpdatedAt(vehicle, latestHistory: latest),
      };
      return {
        ...record,
        'location_status_label': _service.statusLabel(record),
      };
    }).toList();

    return _LocationDashboardData(vehicles: enriched, latestHistoryByVehicle: latestByVehicle);
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _load();
    });
    await _future;
  }

  String _s(dynamic value) => value == null ? '' : value.toString().trim();

  Future<void> _openConfirm(Map<String, dynamic> record) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ConfirmVehicleLocationPage(record: record),
      ),
    );
    if (changed == true) {
      await _refresh();
    }
  }

  Future<void> _openHistory(Map<String, dynamic> record) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VehicleLocationHistoryPage(record: record),
      ),
    );
    await _refresh();
  }

  Future<void> _openManageLocations() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const VehicleLocationAdminPage()),
    );
    await _refresh();
  }

  Future<void> _toggleVehicleRentalStatus(Map<String, dynamic> record) async {
    final vehicleId = _s(record['vehicle_id']);
    final status = _s(record['vehicle_status']).toLowerCase();
    final branchActive = _service.branchIsActive(record);
    final isInactive = status == 'inactive' || status.contains('deactive') || status == 'disabled';
    final activateVehicle = isInactive;

    if (activateVehicle && !branchActive) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This branch is inactive. Activate the branch first.')),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(activateVehicle ? 'Set vehicle active?' : 'Set vehicle inactive?'),
        content: Text(
          activateVehicle
              ? 'This vehicle will become rentable again for users.'
              : 'This vehicle will no longer appear as rentable until an admin activates it again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(activateVehicle ? 'Set Active' : 'Set Inactive'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _service.updateVehicleActiveState(
        vehicleId: vehicleId,
        isActive: activateVehicle,
        currentLocation: _s(record['vehicle_location']),
        branchIsActive: branchActive,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            activateVehicle
                ? 'Vehicle activated and rentable again.'
                : 'Vehicle set to inactive. It can no longer be rented.',
          ),
        ),
      );
      await _refresh();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_service.explainError(error)), backgroundColor: Colors.red),
      );
    }
  }

  List<Map<String, dynamic>> _filtered(List<Map<String, dynamic>> vehicles) {
    final query = _searchController.text.trim().toLowerCase();
    return vehicles.where((vehicle) {
      final status = _s(vehicle['location_status_label']);
      final haystack = [
        _s(vehicle['vehicle_id']),
        _s(vehicle['vehicle_plate_no']),
        _s(vehicle['vehicle_brand']),
        _s(vehicle['vehicle_model']),
        _s(vehicle['vehicle_location']),
        _s(vehicle['current_parking_slot']),
        status,
      ].join(' ').toLowerCase();

      final matchesSearch = query.isEmpty || haystack.contains(query);
      final matchesFilter = _statusFilter == 'All' || status == _statusFilter;
      return matchesSearch && matchesFilter;
    }).toList();
  }

  Widget _buildSummary(List<Map<String, dynamic>> vehicles) {
    final total = vehicles.length;
    final active = vehicles.where((v) => _s(v['location_status_label']) == 'Active').length;
    final inactive = vehicles.where((v) => _s(v['location_status_label']) == 'Inactive').length;
    final pending = vehicles.where((v) => _s(v['location_status_label']) == 'Pending').length;
    final other = vehicles.where((v) {
      final status = _s(v['location_status_label']);
      return status != 'Active' && status != 'Inactive' && status != 'Pending';
    }).length;

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _SummaryCard(label: 'Total', value: '$total', tone: Colors.blue),
        _SummaryCard(label: 'Active', value: '$active', tone: Colors.green),
        _SummaryCard(label: 'Inactive', value: '$inactive', tone: Colors.redAccent),
        _SummaryCard(label: 'Pending', value: '$pending', tone: Colors.orange),
        _SummaryCard(label: 'Other', value: '$other', tone: Colors.grey),
      ],
    );
  }
  Widget _buildToolbar(int count) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: 'Search branch, plate, slot...',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: PopupMenuButton<String>(
              tooltip: 'Filter status',
              initialValue: _statusFilter,
              onSelected: (value) => setState(() => _statusFilter = value),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'All', child: Text('All status')),
                PopupMenuItem(value: 'Active', child: Text('Active')),
                PopupMenuItem(value: 'Inactive', child: Text('Inactive')),
                PopupMenuItem(value: 'Pending', child: Text('Pending')),
                PopupMenuItem(value: 'Maintenance', child: Text('Maintenance')),
                PopupMenuItem(value: 'Other', child: Text('Other')),
              ],
              icon: const Icon(Icons.filter_alt_outlined),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Text(
              '$count vehicle${count == 1 ? '' : 's'} tracked',
              style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700),
            ),
            const SizedBox(width: 10),
            if (_statusFilter != 'All') AdminStatusChip(status: _statusFilter),
          ],
        ),
      ],
    );
  }

  Widget _buildGroupedVehicles(List<Map<String, dynamic>> vehicles) {
    if (vehicles.isEmpty) {
      return const AdminCard(
        child: Padding(
          padding: EdgeInsets.all(18),
          child: Text('No vehicles found for the current filters.'),
        ),
      );
    }

    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final vehicle in vehicles) {
      final branch = _s(vehicle['vehicle_location']).isEmpty ? 'Unassigned Branch' : _s(vehicle['vehicle_location']);
      grouped.putIfAbsent(branch, () => <Map<String, dynamic>>[]).add(vehicle);
    }

    final branches = grouped.keys.toList()..sort();
    return Column(
      children: [
        for (final branch in branches) ...[
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    branch,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                  ),
                ),
                Text(
                  '${grouped[branch]!.length} vehicles',
                  style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          ...grouped[branch]!.map(
                (vehicle) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _LocationVehicleCard(
                record: vehicle,
                onTap: () => _openConfirm(vehicle),
                onHistory: () => _openHistory(vehicle),
                onToggleRentalStatus: _isAdminMode ? () => _toggleVehicleRentalStatus(vehicle) : null,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildLoaded(_LocationDashboardData data) {
    final filtered = _filtered(data.vehicles);
    final content = RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        children: [
          _buildSummary(filtered),
          const SizedBox(height: 14),
          _buildToolbar(filtered.length),
          const SizedBox(height: 14),
          _buildGroupedVehicles(filtered),
        ],
      ),
    );

    if (widget.embedded) {
      return Column(
        children: [
          AdminModuleHeader(
            icon: Icons.place_outlined,
            title: widget.title ?? (_isAdminMode ? 'Vehicle Locations' : 'My Vehicle Locations'),
            subtitle: _isAdminMode
                ? 'Real-time tracking across all branches and parking slots.'
                : 'Track where your vehicles are currently assigned.',
            actions: [
              IconButton(
                tooltip: 'Refresh',
                onPressed: _refresh,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
            primaryActions: [
              if (widget.allowManageLocations && _isAdminMode)
                FilledButton.tonalIcon(
                  onPressed: _openManageLocations,
                  icon: const Icon(Icons.map_outlined),
                  label: const Text('Manage branches'),
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
        title: Text(widget.title ?? 'Vehicle Locations'),
        actions: [
          if (widget.allowManageLocations && _isAdminMode)
            IconButton(
              tooltip: 'Manage branches',
              onPressed: _openManageLocations,
              icon: const Icon(Icons.map_outlined),
            ),
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

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_LocationDashboardData>(
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
        return _buildLoaded(snapshot.data ?? const _LocationDashboardData.empty());
      },
    );
  }
}

class _LocationDashboardData {
  const _LocationDashboardData({required this.vehicles, required this.latestHistoryByVehicle});

  const _LocationDashboardData.empty()
      : vehicles = const [],
        latestHistoryByVehicle = const {};

  final List<Map<String, dynamic>> vehicles;
  final Map<String, Map<String, dynamic>> latestHistoryByVehicle;
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.label, required this.value, required this.tone});

  final String label;
  final String value;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 104,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: tone.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tone.withOpacity(0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: tone, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}

class _LocationVehicleCard extends StatelessWidget {
  const _LocationVehicleCard({
    required this.record,
    required this.onTap,
    required this.onHistory,
    this.onToggleRentalStatus,
  });

  final Map<String, dynamic> record;
  final VoidCallback onTap;
  final VoidCallback onHistory;
  final VoidCallback? onToggleRentalStatus;

  String _s(dynamic value) => value == null ? '' : value.toString().trim();

  String _title() {
    final brand = _s(record['vehicle_brand']);
    final model = _s(record['vehicle_model']);
    final value = '$brand $model'.trim();
    if (value.isNotEmpty) return value;
    return _s(record['vehicle_id']).isEmpty ? 'Vehicle' : _s(record['vehicle_id']);
  }

  String _lastUpdated() {
    return _formatLocationTimestamp(record['location_last_updated']);
  }

  @override
  Widget build(BuildContext context) {
    final slot = _s(record['current_parking_slot']);
    final status = _s(record['location_status_label']).isEmpty ? 'Other' : _s(record['location_status_label']);
    final branchActive = record['branch_is_active'] as bool? ?? true;
    final isInactive = status.toLowerCase() == 'inactive';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AdminCard(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _s(record['vehicle_plate_no']).isEmpty ? _s(record['vehicle_id']) : _s(record['vehicle_plate_no']),
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                  AdminStatusChip(status: status),
                ],
              ),
              const SizedBox(height: 4),
              Text(_title(), style: TextStyle(color: Colors.grey.shade800, fontWeight: FontWeight.w600)),
              if (!branchActive) ...[
                const SizedBox(height: 6),
                Text(
                  'Branch inactive. This vehicle cannot be rented.',
                  style: TextStyle(color: Colors.orange.shade900, fontWeight: FontWeight.w700, fontSize: 12),
                ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.local_parking_outlined, size: 16, color: Colors.grey.shade700),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      slot.isEmpty ? 'Parking slot not assigned' : slot,
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.update_outlined, size: 16, color: Colors.grey.shade700),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _lastUpdated(),
                      style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                    ),
                  ),
                  if (onToggleRentalStatus != null)
                    IconButton(
                      tooltip: isInactive ? 'Set Active' : 'Set Inactive',
                      onPressed: onToggleRentalStatus,
                      icon: Icon(isInactive ? Icons.check_circle_outline : Icons.block_outlined),
                    ),
                  IconButton(
                    tooltip: 'Location history',
                    onPressed: onHistory,
                    icon: const Icon(Icons.timeline_outlined),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}








