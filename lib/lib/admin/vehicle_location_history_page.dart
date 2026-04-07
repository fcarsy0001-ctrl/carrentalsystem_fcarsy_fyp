import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/vehicle_location_service.dart';

class VehicleLocationHistoryPage extends StatefulWidget {
  const VehicleLocationHistoryPage({super.key, required this.record});

  final Map<String, dynamic> record;

  @override
  State<VehicleLocationHistoryPage> createState() => _VehicleLocationHistoryPageState();
}

class _VehicleLocationHistoryPageState extends State<VehicleLocationHistoryPage> {
  late final VehicleLocationService _service;
  late Future<List<Map<String, dynamic>>> _future;

  String _range = 'All';

  String _s(dynamic value) => value == null ? '' : value.toString().trim();

  @override
  void initState() {
    super.initState();
    _service = VehicleLocationService(Supabase.instance.client);
    _future = _service.fetchHistory(vehicleId: _s(widget.record['vehicle_id']));
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _service.fetchHistory(vehicleId: _s(widget.record['vehicle_id']));
    });
    await _future;
  }

  DateTime? _dt(dynamic value) {
    final text = _s(value);
    if (text.isEmpty) return null;
    return DateTime.tryParse(text)?.toLocal();
  }

  String _fmt(DateTime? value) {
    if (value == null) return '-';
    final hour = value.hour == 0 ? 12 : (value.hour > 12 ? value.hour - 12 : value.hour);
    final minute = value.minute.toString().padLeft(2, '0');
    final period = value.hour >= 12 ? 'PM' : 'AM';
    return '${value.day}/${value.month}/${value.year}, $hour:$minute $period';
  }

  List<Map<String, dynamic>> _filtered(List<Map<String, dynamic>> rows) {
    final now = DateTime.now();
    return rows.where((row) {
      final movedAt = _dt(row['moved_at']);
      if (_range == 'All' || movedAt == null) return true;
      if (_range == 'Today') {
        return movedAt.year == now.year && movedAt.month == now.month && movedAt.day == now.day;
      }
      if (_range == 'Week') {
        return movedAt.isAfter(now.subtract(const Duration(days: 7)));
      }
      if (_range == 'Month') {
        return movedAt.isAfter(now.subtract(const Duration(days: 30)));
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final title = '${_s(widget.record['vehicle_brand'])} ${_s(widget.record['vehicle_model'])}'.trim();
    final plate = _s(widget.record['vehicle_plate_no']);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Location History'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
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

          final rows = _filtered(snapshot.data ?? const []);
          final latest = rows.isEmpty ? null : rows.first;
          final branchCount = rows.map((row) => _s(row['new_location'])).where((v) => v.isNotEmpty).toSet().length;

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 22),
              children: [
                _HeaderCard(
                  plate: plate.isEmpty ? _s(widget.record['vehicle_id']) : plate,
                  title: title.isEmpty ? 'Vehicle' : title,
                  currentBranch: _s(widget.record['vehicle_location']),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _MiniStat(label: 'Total Moves', value: '${rows.length}')),
                    const SizedBox(width: 10),
                    Expanded(child: _MiniStat(label: 'Branches', value: '$branchCount')),
                    const SizedBox(width: 10),
                    Expanded(child: _MiniStat(label: 'Last Move', value: latest == null ? '-' : 'Updated')),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final option in const ['All', 'Today', 'Week', 'Month'])
                      ChoiceChip(
                        label: Text(option),
                        selected: _range == option,
                        onSelected: (_) => setState(() => _range = option),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                if (rows.isEmpty)
                  const _TimelineEmpty()
                else
                  ...List.generate(rows.length, (index) {
                    final row = rows[index];
                    final remark = _service.parseRemarks(row);
                    final movedAt = _dt(row['moved_at']);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _TimelineCard(
                        branch: _s(row['new_location']).isEmpty ? 'Unknown branch' : _s(row['new_location']),
                        remark: remark,
                        movedBy: _s(row['moved_by']),
                        movedAt: _fmt(movedAt),
                        isLatest: index == 0,
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

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({
    required this.plate,
    required this.title,
    required this.currentBranch,
  });

  final String plate;
  final String title;
  final String currentBranch;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(plate, style: const TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text(title, style: TextStyle(color: cs.onSurfaceVariant)),
          const SizedBox(height: 12),
          Text('Current Branch', style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700, fontSize: 12)),
          const SizedBox(height: 4),
          Text(currentBranch.isEmpty ? 'Not assigned' : currentBranch, style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}

class _TimelineCard extends StatelessWidget {
  const _TimelineCard({
    required this.branch,
    required this.remark,
    required this.movedBy,
    required this.movedAt,
    required this.isLatest,
  });

  final String branch;
  final String remark;
  final String movedBy;
  final String movedAt;
  final bool isLatest;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 26,
          alignment: Alignment.topCenter,
          child: Column(
            children: [
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: isLatest ? cs.primary : Colors.green.shade500,
                  shape: BoxShape.circle,
                ),
                child: Icon(isLatest ? Icons.place_outlined : Icons.check, size: 12, color: Colors.white),
              ),
              Container(width: 2, height: 96, color: cs.outlineVariant.withOpacity(0.6)),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cs.outlineVariant.withOpacity(0.55)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isLatest)
                  Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text('Current location', style: TextStyle(color: cs.onPrimaryContainer, fontWeight: FontWeight.w800, fontSize: 12)),
                  ),
                Text(branch, style: const TextStyle(fontWeight: FontWeight.w900)),
                if (remark.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(remark, style: TextStyle(color: cs.onSurfaceVariant)),
                ],
                const SizedBox(height: 10),
                Text('Updated by ${movedBy.isEmpty ? 'System' : movedBy}', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                const SizedBox(height: 4),
                Text(movedAt, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _TimelineEmpty extends StatelessWidget {
  const _TimelineEmpty();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: const Text('No location history has been recorded for this vehicle yet.'),
    );
  }
}








