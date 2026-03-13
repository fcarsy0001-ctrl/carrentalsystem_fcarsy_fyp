import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/vehicle_onboarding_service.dart';
import 'vehicle_eligibility_result_page.dart';
import 'vehicle_registration_page.dart';
import 'widgets/admin_ui.dart';

class VehicleDetailsPage extends StatefulWidget {
  const VehicleDetailsPage({
    super.key,
    required this.initialRecord,
    required this.isAdminMode,
    this.fixedLeaserId,
  });

  final Map<String, dynamic> initialRecord;
  final bool isAdminMode;
  final String? fixedLeaserId;

  @override
  State<VehicleDetailsPage> createState() => _VehicleDetailsPageState();
}

class _VehicleDetailsPageState extends State<VehicleDetailsPage> {
  late final VehicleOnboardingService _service;
  late Map<String, dynamic> _record;

  String? _photoUrl;
  String? _docsUrl;
  bool _loading = true;

  String _s(dynamic value) => value == null ? '' : value.toString().trim();

  String _friendlyDocumentName(String? path) {
    final raw = _s(path);
    if (raw.isEmpty) return '';
    final normalized = raw.replaceAll('\\', '/');
    final last = normalized.split('/').last.trim();
    return last.isEmpty ? raw : last;
  }

  int _i(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString()) ?? 0;
  }

  @override
  void initState() {
    super.initState();
    _service = VehicleOnboardingService(Supabase.instance.client);
    _record = Map<String, dynamic>.from(widget.initialRecord);
    _hydrateAssets();
  }

  Future<void> _hydrateAssets() async {
    final photoUrl = await _service.createSignedAssetUrl(_s(_record['vehicle_photo_path']));
    final docsUrl = await _service.createSignedAssetUrl(_s(_record['supporting_docs_url']));
    if (!mounted) return;
    setState(() {
      _photoUrl = photoUrl;
      _docsUrl = docsUrl;
      _loading = false;
    });
  }

  Future<void> _refreshRecord() async {
    final fresh = await _service.fetchVehicleDetail(_s(_record['vehicle_id']));
    if (fresh == null || !mounted) return;
    setState(() {
      _record = fresh;
      _loading = true;
    });
    await _hydrateAssets();
  }

  Future<void> _openEdit() async {
    final vehicleId = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => VehicleRegistrationPage(
          initial: _record,
          isAdminMode: widget.isAdminMode,
          fixedLeaserId: widget.fixedLeaserId,
        ),
      ),
    );
    if (vehicleId == null || vehicleId.trim().isEmpty) return;
    await _refreshRecord();
  }

  Future<void> _openEligibility() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VehicleEligibilityResultPage(
          initialRecord: _record,
          isAdminMode: widget.isAdminMode,
        ),
      ),
    );
    await _refreshRecord();
  }

  Future<void> _openDocument() async {
    final link = (_docsUrl ?? '').trim();
    if (link.isEmpty || !mounted) return;

    final uri = Uri.tryParse(link);
    if (uri == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open PDF link.')),
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
        const SnackBar(content: Text('Could not open PDF.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final title = '${_s(_record['vehicle_brand'])} ${_s(_record['vehicle_model'])}'.trim();
    final plate = _s(_record['vehicle_plate_no']);
    final year = _i(_record['vehicle_year']);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Vehicle Details'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _refreshRecord,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 22),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [cs.primary, cs.primary.withOpacity(0.85)],
              ),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title.isEmpty ? 'Vehicle' : title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            plate.isEmpty ? '-' : plate,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    AdminStatusChip(status: _s(_record['readiness_status']).isEmpty ? 'Pending' : _s(_record['readiness_status'])),
                  ],
                ),
                const SizedBox(height: 16),
                if ((_photoUrl ?? '').trim().isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Image.network(
                      _photoUrl!,
                      height: 210,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _heroFallback(cs),
                    ),
                  )
                else
                  _heroFallback(cs),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    AdminStatusChip(status: _s(_record['condition_status']).isEmpty ? 'Pending' : _s(_record['condition_status'])),
                    AdminStatusChip(status: _s(_record['eligibility_status']).isEmpty ? 'Pending' : _s(_record['eligibility_status'])),
                    AdminStatusChip(status: _s(_record['review_status']).isEmpty ? 'Pending Review' : _s(_record['review_status'])),
                    if (year > 0) AdminStatusChip(status: '$year'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _InfoSection(
            title: 'Status Overview',
            child: Column(
              children: [
                _InfoRow(label: 'Vehicle Status', value: _s(_record['vehicle_status']).isEmpty ? 'Pending' : _s(_record['vehicle_status'])),
                _InfoRow(label: 'Eligibility', value: _s(_record['eligibility_status']).isEmpty ? 'Pending' : _s(_record['eligibility_status'])),
                _InfoRow(label: 'Readiness', value: _s(_record['readiness_status']).isEmpty ? 'Pending' : _s(_record['readiness_status'])),
                _InfoRow(label: 'Review Status', value: _s(_record['review_status']).isEmpty ? 'Pending Review' : _s(_record['review_status'])),
                _InfoRow(label: 'Inspection Result', value: _s(_record['inspection_result']).isEmpty ? 'Pending' : _s(_record['inspection_result'])),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _InfoSection(
            title: 'Vehicle Specifications',
            child: Column(
              children: [
                _InfoRow(label: 'Vehicle ID', value: _s(_record['vehicle_id'])),
                _InfoRow(label: 'Leaser ID', value: _s(_record['leaser_id'])),
                _InfoRow(label: 'Vehicle Type', value: _s(_record['vehicle_type'])),
                _InfoRow(label: 'Transmission Type', value: _s(_record['transmission_type'])),
                _InfoRow(label: 'Fuel Type', value: _s(_record['fuel_type'])),
                _InfoRow(label: 'Mileage', value: _i(_record['mileage_km']) <= 0 ? '-' : '${_i(_record['mileage_km'])} km'),
                _InfoRow(label: 'Seating Capacity', value: _i(_record['seat_capacity']) <= 0 ? '-' : '${_i(_record['seat_capacity'])} seats'),
                _InfoRow(label: 'Daily Rate', value: 'RM ${_record['daily_rate'] ?? 0}'),
                _InfoRow(label: 'Location', value: _s(_record['vehicle_location'])),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _InfoSection(
            title: 'Documents Attached',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DocumentCard(
                  fileName: _friendlyDocumentName(_s(_record['supporting_docs_url'])),
                  hasFile: _s(_record['supporting_docs_url']).isNotEmpty,
                ),
                const SizedBox(height: 10),
                if ((_docsUrl ?? '').trim().isNotEmpty)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Open the uploaded PDF document.',
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: _openDocument,
                        icon: const Icon(Icons.picture_as_pdf_outlined),
                        label: const Text('Open PDF'),
                      ),
                    ],
                  )
                else
                  Text(
                    _s(_record['supporting_docs_url']).isEmpty
                        ? 'No document uploaded yet.'
                        : _s(_record['supporting_docs_url']),
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _InfoSection(
            title: 'Remarks',
            child: Text(
              _s(_record['remarks']).isEmpty ? 'No additional remarks provided.' : _s(_record['remarks']),
              style: TextStyle(color: cs.onSurfaceVariant, height: 1.4),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: _openEdit,
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit Vehicle'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _openEligibility,
                  icon: const Icon(Icons.verified_outlined),
                  label: const Text('View Eligibility'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _heroFallback(ColorScheme cs) {
    return Container(
      height: 210,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: Colors.white.withOpacity(0.14),
      ),
      alignment: Alignment.center,
      child: const Icon(Icons.directions_car_outlined, color: Colors.white, size: 72),
    );
  }

}

class _DocumentCard extends StatelessWidget {
  const _DocumentCard({
    required this.fileName,
    required this.hasFile,
  });

  final String fileName;
  final bool hasFile;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: 180,
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: cs.surfaceContainerHighest.withOpacity(0.45),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.picture_as_pdf_outlined, color: Colors.red.shade600, size: 44),
          const SizedBox(height: 12),
          Text(
            hasFile ? fileName : 'No document uploaded yet',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            hasFile ? 'Supporting document stored as PDF file' : 'Upload a PDF for registration or insurance records',
            textAlign: TextAlign.center,
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _InfoSection extends StatelessWidget {
  const _InfoSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 14),
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
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              value.isEmpty ? '-' : value,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

