import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../admin/widgets/admin_ui.dart';
import '../services/vehicle_onboarding_service.dart';

class VehicleOnboardingStatusPage extends StatefulWidget {
  const VehicleOnboardingStatusPage({
    super.key,
    required this.leaserId,
    this.embedded = false,
  });

  final String leaserId;
  final bool embedded;

  @override
  State<VehicleOnboardingStatusPage> createState() => _VehicleOnboardingStatusPageState();
}

class _VehicleOnboardingStatusPageState extends State<VehicleOnboardingStatusPage> {
  late final VehicleOnboardingService _service;
  late Future<List<Map<String, dynamic>>> _future;
  String? _selectedVehicleId;

  @override
  void initState() {
    super.initState();
    _service = VehicleOnboardingService(Supabase.instance.client);
    _future = _service.fetchVehicles(leaserId: widget.leaserId);
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _service.fetchVehicles(leaserId: widget.leaserId);
    });
    await _future;
  }

  String _s(dynamic value) => value == null ? '' : value.toString().trim();

  int _i(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString()) ?? 0;
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

  Map<String, dynamic>? _selected(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) return null;
    if ((_selectedVehicleId ?? '').isEmpty) return rows.first;
    for (final row in rows) {
      if (_s(row['vehicle_id']) == _selectedVehicleId) return row;
    }
    return rows.first;
  }

  @override
  Widget build(BuildContext context) {
    final body = FutureBuilder<List<Map<String, dynamic>>>(
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

        final rows = List<Map<String, dynamic>>.from(snapshot.data ?? const []);
        rows.sort((a, b) => _s(b['submitted_at']).compareTo(_s(a['submitted_at'])));

        if (rows.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('No onboarding submissions yet. Submit a vehicle first to track its status.'),
            ),
          );
        }

        final selected = _selected(rows)!;
        final reviewStatus = _s(selected['review_status']).isEmpty ? 'Pending Review' : _s(selected['review_status']);
        final readinessStatus = _s(selected['readiness_status']).isEmpty ? 'Pending' : _s(selected['readiness_status']);
        final finalLabel = reviewStatus == 'Approved'
            ? 'Approved'
            : reviewStatus == 'Rejected'
            ? 'Rejected'
            : 'Pending';
        final passedChecks = [
          selected['age_passed'] == true,
          selected['mileage_passed'] == true,
          selected['physical_passed'] == true,
          selected['docs_passed'] == true,
        ].where((value) => value).length;
        final progress = passedChecks / 4;

        final content = RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 22),
            children: [
              if (rows.length > 1) ...[
                DropdownButtonFormField<String>(
                  value: _s(selected['vehicle_id']),
                  decoration: const InputDecoration(labelText: 'Vehicle'),
                  items: rows.map((row) {
                    final plate = _s(row['vehicle_plate_no']);
                    final name = '${_s(row['vehicle_brand'])} ${_s(row['vehicle_model'])}'.trim();
                    final label = plate.isEmpty ? name : '$plate - ${name.isEmpty ? _s(row['vehicle_id']) : name}';
                    return DropdownMenuItem(value: _s(row['vehicle_id']), child: Text(label, overflow: TextOverflow.ellipsis));
                  }).toList(),
                  onChanged: (value) => setState(() => _selectedVehicleId = value),
                ),
                const SizedBox(height: 14),
              ],
              _StatusSteps(
                submittedDone: true,
                underReviewActive: reviewStatus == 'Pending Review',
                finalDone: reviewStatus == 'Approved' || reviewStatus == 'Rejected' || readinessStatus == 'Ready',
                finalLabel: finalLabel,
              ),
              const SizedBox(height: 14),
              _StatusBanner(reviewStatus: reviewStatus, readinessStatus: readinessStatus),
              const SizedBox(height: 14),
              _InfoCard(
                title: 'Submission Details',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Vehicle', style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text('${_s(selected['vehicle_brand'])} ${_s(selected['vehicle_model'])} ${_i(selected['vehicle_year']) <= 0 ? '' : '(${_i(selected['vehicle_year'])})'}'.trim(), style: const TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 12),
                    Text('Submitted on', style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(_fmt(_dt(selected['submitted_at'])), style: const TextStyle(fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _InfoCard(
                title: 'Inspection Report',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text('Checks Passed', style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w700)),
                        ),
                        Text('$passedChecks/4', style: const TextStyle(fontWeight: FontWeight.w900)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(value: progress, minHeight: 8),
                    ),
                    const SizedBox(height: 14),
                    _CheckRow(label: 'Age Requirement', passed: selected['age_passed'] == true),
                    _CheckRow(label: 'Mileage Requirement', passed: selected['mileage_passed'] == true),
                    _CheckRow(label: 'Physical Condition', passed: selected['physical_passed'] == true),
                    _CheckRow(label: 'Document Verification', passed: selected['docs_passed'] == true),
                  ],
                ),
              ),
            ],
          ),
        );

        if (widget.embedded) {
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      alignment: Alignment.center,
                      child: Icon(Icons.track_changes_outlined, color: Theme.of(context).colorScheme.onPrimaryContainer),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Onboarding Status', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                          Text('Track your vehicle application progress', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
                    IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh_rounded)),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(child: content),
            ],
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('Onboarding Status'),
            actions: [IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh_rounded))],
          ),
          body: content,
        );
      },
    );

    return body;
  }
}

class _StatusSteps extends StatelessWidget {
  const _StatusSteps({
    required this.submittedDone,
    required this.underReviewActive,
    required this.finalDone,
    required this.finalLabel,
  });

  final bool submittedDone;
  final bool underReviewActive;
  final bool finalDone;
  final String finalLabel;

  @override
  Widget build(BuildContext context) {
    return _InfoCard(
      title: 'Progress',
      child: Row(
        children: [
          Expanded(child: _StepDot(icon: Icons.check, label: 'Submitted', done: submittedDone, active: submittedDone)),
          Expanded(child: _StepDot(icon: Icons.watch_later_outlined, label: 'Under Review', done: finalDone, active: underReviewActive)),
          Expanded(child: _StepDot(icon: finalDone && finalLabel == 'Rejected' ? Icons.close : Icons.flag_outlined, label: finalLabel, done: finalDone, active: !submittedDone || (!underReviewActive && !finalDone))),
        ],
      ),
    );
  }
}

class _StepDot extends StatelessWidget {
  const _StepDot({required this.icon, required this.label, required this.done, required this.active});

  final IconData icon;
  final String label;
  final bool done;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = done ? cs.primary : active ? Colors.orange : cs.outlineVariant;
    return Column(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: done ? cs.primary : Colors.transparent,
            border: Border.all(color: color, width: 2),
          ),
          alignment: Alignment.center,
          child: Icon(icon, color: done ? Colors.white : color, size: 20),
        ),
        const SizedBox(height: 8),
        Text(label, textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w700, color: active || done ? cs.onSurface : cs.onSurfaceVariant, fontSize: 12)),
      ],
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.reviewStatus, required this.readinessStatus});

  final String reviewStatus;
  final String readinessStatus;

  @override
  Widget build(BuildContext context) {
    final isRejected = reviewStatus == 'Rejected';
    final isApproved = reviewStatus == 'Approved' || readinessStatus == 'Ready';
    final bg = isRejected
        ? Colors.red.withOpacity(0.08)
        : isApproved
        ? Colors.green.withOpacity(0.08)
        : Colors.orange.withOpacity(0.08);
    final border = isRejected
        ? Colors.red.withOpacity(0.25)
        : isApproved
        ? Colors.green.withOpacity(0.25)
        : Colors.orange.withOpacity(0.25);
    final title = isRejected
        ? 'Rejected'
        : isApproved
        ? 'Approved'
        : 'Under Review';
    final message = isRejected
        ? 'The submission needs changes before it can proceed.'
        : isApproved
        ? 'The vehicle has passed review and is ready for the next step.'
        : 'Our team is currently reviewing your documents and vehicle information.';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Icon(isRejected ? Icons.error_outline : isApproved ? Icons.check_circle_outline : Icons.hourglass_top_rounded),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text(message),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade300),
        color: Colors.white,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({required this.label, required this.passed});

  final String label;
  final bool passed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700))),
          AdminStatusChip(status: passed ? 'Passed' : 'Pending'),
        ],
      ),
    );
  }
}

