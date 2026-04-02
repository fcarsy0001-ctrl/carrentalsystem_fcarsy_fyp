import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/vehicle_onboarding_service.dart';
import 'widgets/admin_ui.dart';

class VehicleEligibilityResultPage extends StatefulWidget {
  const VehicleEligibilityResultPage({
    super.key,
    required this.initialRecord,
    required this.isAdminMode,
  });

  final Map<String, dynamic> initialRecord;
  final bool isAdminMode;

  @override
  State<VehicleEligibilityResultPage> createState() => _VehicleEligibilityResultPageState();
}

class _VehicleEligibilityResultPageState extends State<VehicleEligibilityResultPage> {
  late final VehicleOnboardingService _service;
  late Map<String, dynamic> _record;

  late String _reviewStatus;
  late String _eligibilityStatus;
  late String _readinessStatus;
  late String _conditionStatus;
  late String _inspectionResult;
  late TextEditingController _readinessNotesController;
  late TextEditingController _reviewRemarkController;
  DateTime? _inspectionDate;
  bool _saving = false;

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
    return DateTime.tryParse(text);
  }

  String _fmtDate(dynamic value) {
    final date = _dt(value);
    if (date == null) return '-';
    return '${date.day}/${date.month}/${date.year}';
  }

  @override
  void initState() {
    super.initState();
    _service = VehicleOnboardingService(Supabase.instance.client);
    _record = Map<String, dynamic>.from(widget.initialRecord);
    _syncReviewState();
  }

  @override
  void dispose() {
    _readinessNotesController.dispose();
    _reviewRemarkController.dispose();
    super.dispose();
  }

  void _syncReviewState() {
    _reviewStatus = _s(_record['review_status']).isEmpty ? 'Pending Review' : _s(_record['review_status']);
    _eligibilityStatus = _s(_record['eligibility_status']).isEmpty ? 'Pending' : _s(_record['eligibility_status']);
    _readinessStatus = _s(_record['readiness_status']).isEmpty ? 'Pending' : _s(_record['readiness_status']);
    _conditionStatus = _s(_record['condition_status']).isEmpty ? 'Pending' : _s(_record['condition_status']);
    _inspectionResult = _s(_record['inspection_result']).isEmpty ? 'Pending' : _s(_record['inspection_result']);
    _readinessNotesController = TextEditingController(text: _s(_record['readiness_notes']));
    _reviewRemarkController = TextEditingController(text: _s(_record['review_remark']));
    final rawDate = _s(_record['inspection_date']);
    _inspectionDate = rawDate.isEmpty ? null : DateTime.tryParse(rawDate);
  }

  void _applyReviewStatusPreset(String status) {
    setState(() {
      _reviewStatus = status;
      if (status == 'Approved') {
        _eligibilityStatus = 'Eligible';
        _readinessStatus = 'Ready';
        _inspectionResult = 'Pass';
        _inspectionDate ??= DateTime.now();
      } else if (status == 'Rejected') {
        _eligibilityStatus = 'Rejected';
        _readinessStatus = 'Rejected';
        _inspectionResult = 'Fail';
        _inspectionDate ??= DateTime.now();
      }
    });
  }

  Future<void> _pickInspectionDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final initialDate = _inspectionDate != null && !_inspectionDate!.isBefore(today)
        ? _inspectionDate!
        : today;
    final picked = await showDatePicker(
      context: context,
      firstDate: today,
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDate: initialDate,
    );
    if (picked == null) return;
    setState(() => _inspectionDate = picked);
  }

  Future<void> _copyReport() async {
    final report = _service.buildEligibilityReport(_record);
    await Clipboard.setData(ClipboardData(text: report));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Eligibility report copied to clipboard.')),
    );
  }

  Future<void> _showFullInspection() async {
    final report = _service.buildEligibilityReport(_record);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Full Inspection Report'),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: SelectableText(report),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
          FilledButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: report));
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
            child: const Text('Copy'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveReview() async {
    if (!widget.isAdminMode || _saving) return;
    setState(() => _saving = true);
    try {
      final updated = await _service.updateEligibilityReview(
        vehicleId: _s(_record['vehicle_id']),
        reviewStatus: _reviewStatus,
        eligibilityStatus: _eligibilityStatus,
        readinessStatus: _readinessStatus,
        conditionStatus: _conditionStatus,
        inspectionResult: _inspectionResult,
        inspectionDate: _inspectionDate,
        reviewRemark: _reviewRemarkController.text.trim(),
        readinessNotes: _readinessNotesController.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _record = updated;
        _readinessNotesController.dispose();
        _reviewRemarkController.dispose();
        _syncReviewState();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vehicle review updated successfully.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_service.explainError(error)),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 6),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final currentEligibility = widget.isAdminMode
        ? _eligibilityStatus
        : (_s(_record['eligibility_status']).isEmpty ? 'Pending' : _s(_record['eligibility_status']));
    final currentReadiness = widget.isAdminMode
        ? _readinessStatus
        : (_s(_record['readiness_status']).isEmpty ? 'Pending' : _s(_record['readiness_status']));
    final currentReviewStatus = widget.isAdminMode
        ? _reviewStatus
        : (_s(_record['review_status']).isEmpty ? 'Pending Review' : _s(_record['review_status']));
    final currentInspectionResult = widget.isAdminMode
        ? _inspectionResult
        : _s(_record['inspection_result']);
    final currentConditionStatus = widget.isAdminMode
        ? _conditionStatus
        : (_s(_record['condition_status']).isEmpty ? 'Pending' : _s(_record['condition_status']));
    final eligible = currentEligibility.toLowerCase() == 'eligible';
    final title = '${_s(_record['vehicle_brand'])} ${_s(_record['vehicle_model'])}'.trim();
    final plate = _s(_record['vehicle_plate_no']);
    final year = _i(_record['vehicle_year']);

    final topColor = eligible ? Colors.green : Colors.orange;
    final topText = eligible ? 'Eligible' : (currentEligibility.isEmpty ? 'Pending' : currentEligibility);

    return Scaffold(
      appBar: AppBar(title: const Text('Eligibility Result')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 22),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: topColor,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              children: [
                const Icon(Icons.verified_rounded, color: Colors.white, size: 54),
                const SizedBox(height: 10),
                Text(
                  topText,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${title.isEmpty ? 'Vehicle' : title}${year > 0 ? ' $year' : ''}',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  plate.isEmpty ? 'Inspection review pending' : plate,
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Requirements Met', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                    Text(
                      '${_record['passed_checks'] ?? 0} of 5',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    minHeight: 8,
                    value: (((_record['passed_checks'] ?? 0) as num).toDouble() / 5).clamp(0.0, 1.0),
                    backgroundColor: Colors.white.withOpacity(0.24),
                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Inspection Details',
            style: TextStyle(fontWeight: FontWeight.w900, color: cs.onSurface, fontSize: 18),
          ),
          const SizedBox(height: 12),
          _RequirementCard(
            title: 'Age Requirement',
            description: year > 0
                ? 'Vehicle manufactured in $year, evaluated against the onboarding age rule.'
                : 'Vehicle year is still missing for this inspection.',
            passed: (_record['age_passed'] as bool?) ?? false,
            requiredValue: 'Max 5 years old',
            actualValue: (_record['age_years'] as int?) == null || (_record['age_years'] as int) < 0
                ? 'Unknown'
                : '${_record['age_years']} years old',
          ),
          const SizedBox(height: 12),
          _RequirementCard(
            title: 'Mileage Requirement',
            description: 'Current mileage is checked against the onboarding threshold.',
            passed: (_record['mileage_passed'] as bool?) ?? false,
            requiredValue: 'Less than 100,000 km',
            actualValue: _i(_record['mileage_km']) <= 0 ? 'Unknown' : '${_i(_record['mileage_km'])} km',
          ),
          const SizedBox(height: 12),
          _RequirementCard(
            title: 'Physical Condition',
            description: 'Visual condition status from the latest vehicle submission or review.',
            passed: (_record['physical_passed'] as bool?) ?? false,
            requiredValue: 'Good or Excellent',
            actualValue: currentConditionStatus.isEmpty ? 'Pending' : currentConditionStatus,
          ),
          const SizedBox(height: 12),
          _RequirementCard(
            title: 'Document Verification',
            description: 'Registration, insurance, and onboarding evidence were checked for submission.',
            passed: (_record['docs_passed'] as bool?) ?? false,
            requiredValue: 'All documents valid',
            actualValue: _s(_record['supporting_docs_url']).isEmpty ? 'Incomplete' : 'Complete',
          ),
          const SizedBox(height: 12),
          _RequirementCard(
            title: 'Road Tax Validity',
            description: 'Road tax must remain valid for at least 2 more months from today.',
            passed: (_record['road_tax_passed'] as bool?) ?? false,
            requiredValue: _s(_record['road_tax_min_expiry_date']).isEmpty
                ? 'At least 2 more months remaining'
                : 'On or after ${_fmtDate(_record['road_tax_min_expiry_date'])}',
            actualValue: _s(_record['road_tax_expiry_date']).isEmpty
                ? 'Not provided'
                : _fmtDate(_record['road_tax_expiry_date']),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cs.primaryContainer.withOpacity(0.6),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Summary',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                Text(
                  eligible
                      ? 'This vehicle satisfies the current onboarding checks and can move forward after admin confirmation.'
                      : 'This vehicle still needs admin attention before it can be marked ready for onboarding or rental.',
                  style: TextStyle(color: cs.onSurfaceVariant, height: 1.4),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    AdminStatusChip(status: currentReviewStatus),
                    AdminStatusChip(status: currentReadiness),
                    if (currentInspectionResult.isNotEmpty) AdminStatusChip(status: currentInspectionResult),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (widget.isAdminMode) _buildAdminReviewSection(),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _showFullInspection,
            icon: const Icon(Icons.article_outlined),
            label: const Text('View Full Inspection'),
          ),
          const SizedBox(height: 10),
          FilledButton(
            onPressed: widget.isAdminMode ? _saveReview : () => Navigator.of(context).pop(),
            style: FilledButton.styleFrom(
              backgroundColor: widget.isAdminMode ? cs.primary : Colors.green,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: _saving
                ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
                : Text(widget.isAdminMode ? 'Save Review Decision' : 'Done'),
          ),
        ],
      ),
    );
  }

  Widget _buildAdminReviewSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Admin Review',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _reviewStatus,
            decoration: const InputDecoration(labelText: 'Review Status'),
            items: const [
              DropdownMenuItem(value: 'Pending Review', child: Text('Pending Review')),
              DropdownMenuItem(value: 'Approved', child: Text('Approved')),
              DropdownMenuItem(value: 'Rejected', child: Text('Rejected')),
            ],
            onChanged: _saving ? null : (value) {
              final next = value ?? _reviewStatus;
              _applyReviewStatusPreset(next);
            },
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _eligibilityStatus,
                  decoration: const InputDecoration(labelText: 'Eligibility'),
                  items: const [
                    DropdownMenuItem(value: 'Eligible', child: Text('Eligible')),
                    DropdownMenuItem(value: 'Pending', child: Text('Pending')),
                    DropdownMenuItem(value: 'Rejected', child: Text('Rejected')),
                  ],
                  onChanged: _saving ? null : (value) => setState(() => _eligibilityStatus = value ?? _eligibilityStatus),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _readinessStatus,
                  decoration: const InputDecoration(labelText: 'Readiness'),
                  items: const [
                    DropdownMenuItem(value: 'Ready', child: Text('Ready')),
                    DropdownMenuItem(value: 'Pending', child: Text('Pending')),
                    DropdownMenuItem(value: 'Rejected', child: Text('Rejected')),
                  ],
                  onChanged: _saving ? null : (value) => setState(() => _readinessStatus = value ?? _readinessStatus),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _conditionStatus,
                  decoration: const InputDecoration(labelText: 'Condition'),
                  items: const [
                    DropdownMenuItem(value: 'Excellent', child: Text('Excellent')),
                    DropdownMenuItem(value: 'Good', child: Text('Good')),
                    DropdownMenuItem(value: 'Fair', child: Text('Fair')),
                    DropdownMenuItem(value: 'Poor', child: Text('Poor')),
                    DropdownMenuItem(value: 'Pending', child: Text('Pending')),
                  ],
                  onChanged: _saving ? null : (value) => setState(() => _conditionStatus = value ?? _conditionStatus),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _inspectionResult,
                  decoration: const InputDecoration(labelText: 'Inspection Result'),
                  items: const [
                    DropdownMenuItem(value: 'Pass', child: Text('Pass')),
                    DropdownMenuItem(value: 'Pending', child: Text('Pending')),
                    DropdownMenuItem(value: 'Fail', child: Text('Fail')),
                  ],
                  onChanged: _saving ? null : (value) => setState(() => _inspectionResult = value ?? _inspectionResult),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _saving ? null : _pickInspectionDate,
            icon: const Icon(Icons.calendar_month_outlined),
            label: Text(
              _inspectionDate == null
                  ? 'Inspection Date'
                  : '${_inspectionDate!.year}-${_inspectionDate!.month.toString().padLeft(2, '0')}-${_inspectionDate!.day.toString().padLeft(2, '0')}',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _readinessNotesController,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Readiness Notes',
              hintText: 'Explain what is complete or still pending for this vehicle.',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _reviewRemarkController,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Review Remark',
              hintText: 'Optional admin comment for approval or rejection.',
            ),
          ),
        ],
      ),
    );
  }
}

class _RequirementCard extends StatelessWidget {
  const _RequirementCard({
    required this.title,
    required this.description,
    required this.passed,
    required this.requiredValue,
    required this.actualValue,
  });

  final String title;
  final String description;
  final bool passed;
  final String requiredValue;
  final String actualValue;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accent = passed ? Colors.green : Colors.orange;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: accent.withOpacity(0.08),
        border: Border.all(color: accent.withOpacity(0.24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(passed ? Icons.check_circle_outline : Icons.info_outline, color: accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: TextStyle(color: cs.onSurfaceVariant, height: 1.35),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _CheckValue(label: 'Required', value: requiredValue)),
              const SizedBox(width: 12),
              Expanded(child: _CheckValue(label: 'Actual', value: actualValue)),
            ],
          ),
        ],
      ),
    );
  }
}

class _CheckValue extends StatelessWidget {
  const _CheckValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Colors.white.withOpacity(0.7),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w600, fontSize: 12),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}







