import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/driver_license_service.dart';
import 'driver_license_submit_page.dart';

class DriverLicensePage extends StatefulWidget {
  const DriverLicensePage({super.key});

  @override
  State<DriverLicensePage> createState() => _DriverLicensePageState();
}

class _DriverLicensePageState extends State<DriverLicensePage> {
  SupabaseClient get _supa => Supabase.instance.client;

  bool _loading = true;
  DriverLicenseSnapshot? _snap;
  String? _signedUrl;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final svc = DriverLicenseService(_supa);
    final snap = await svc.getSnapshot();
    String? url;
    if ((snap.photoPath ?? '').trim().isNotEmpty) {
      url = await svc.createSignedPhotoUrl(snap.photoPath!.trim());
    }
    if (!mounted) return;
    setState(() {
      _snap = snap;
      _signedUrl = url;
      _loading = false;
    });
  }

  String _statusLabel(DriverLicenseSnapshot s) {
    switch (s.state) {
      case DriverLicenseState.approved:
        return 'Approved';
      case DriverLicenseState.pending:
        return 'Pending review';
      case DriverLicenseState.rejected:
        return 'Rejected';
      case DriverLicenseState.notSubmitted:
        return 'Not submitted';
      case DriverLicenseState.unknown:
        return 'Unknown';
    }
  }

  IconData _statusIcon(DriverLicenseSnapshot s) {
    switch (s.state) {
      case DriverLicenseState.approved:
        return Icons.verified_rounded;
      case DriverLicenseState.pending:
        return Icons.hourglass_top_rounded;
      case DriverLicenseState.rejected:
        return Icons.cancel_outlined;
      case DriverLicenseState.notSubmitted:
        return Icons.warning_amber_rounded;
      case DriverLicenseState.unknown:
        return Icons.help_outline_rounded;
    }
  }

  Color _statusColor(ColorScheme cs, DriverLicenseSnapshot s) {
    switch (s.state) {
      case DriverLicenseState.approved:
        return cs.primary;
      case DriverLicenseState.pending:
        return cs.tertiary;
      case DriverLicenseState.rejected:
        return cs.error;
      case DriverLicenseState.notSubmitted:
        return cs.error;
      case DriverLicenseState.unknown:
        return cs.outline;
    }
  }

  String _cta(DriverLicenseSnapshot s) {
    switch (s.state) {
      case DriverLicenseState.approved:
        return 'Update submission';
      case DriverLicenseState.pending:
        return 'Edit / resubmit';
      case DriverLicenseState.rejected:
        return 'Resubmit';
      case DriverLicenseState.notSubmitted:
        return 'Submit driver licence';
      case DriverLicenseState.unknown:
        return 'Submit driver licence';
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Driver licence verification')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                children: [
                  if (_snap == null)
                    const Text('No data')
                  else ...[
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        color: cs.surfaceContainerHighest.withOpacity(0.45),
                        border: Border.all(
                            color: cs.outlineVariant.withOpacity(0.25)),
                      ),
                      child: Row(
                        children: [
                          Icon(_statusIcon(_snap!),
                              color: _statusColor(cs, _snap!)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _statusLabel(_snap!),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w900),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _snap!.state == DriverLicenseState.approved
                                      ? 'You can start renting.'
                                      : _snap!.state ==
                                              DriverLicenseState.pending
                                          ? 'Waiting for admin review.'
                                          : _snap!.state ==
                                                  DriverLicenseState.rejected
                                              ? 'Please resubmit your details.'
                                              : 'Submit your driver licence to start renting.',
                                  style: TextStyle(
                                      color: Colors.grey.shade700,
                                      fontSize: 12),
                                ),
                                if ((_snap!.rejectRemark ?? '')
                                    .trim()
                                    .isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    'Remark: ${_snap!.rejectRemark}',
                                    style: TextStyle(
                                      color: cs.error,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    if ((_snap!.licenseNo ?? '').trim().isNotEmpty ||
                        (_snap!.licenseName ?? '').trim().isNotEmpty ||
                        _snap!.expiry != null) ...[
                      _InfoCard(
                        title: 'Submission details',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _InfoRow(
                                label: 'Licence no',
                                value: (_snap!.licenseNo ?? '-').trim()),
                            _InfoRow(
                                label: 'Name',
                                value: (_snap!.licenseName ?? '-').trim()),
                            _InfoRow(
                              label: 'Expiry',
                              value: _snap!.expiry == null
                                  ? '-'
                                  : _snap!.expiry!
                                      .toIso8601String()
                                      .split('T')
                                      .first,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],

                    if (_signedUrl != null) ...[
                      _InfoCard(
                        title: 'Licence photo',
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: AspectRatio(
                            aspectRatio: 4 / 3,
                            child: Image.network(
                              _signedUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                color: cs.surface,
                                alignment: Alignment.center,
                                child: const Text('Unable to load image'),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],

                    FilledButton(
                      onPressed: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const DriverLicenseSubmitPage(),
                          ),
                        );
                        await _load();
                      },
                      child: Text(_cta(_snap!)),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Text(
                    'Note: Your rental features will be locked until your driver licence is approved by an admin.',
                    style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                  ),
                ],
              ),
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
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: cs.surfaceContainerHighest.withOpacity(0.40),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
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
        children: [
          SizedBox(
            width: 90,
            child: Text(label,
                style: TextStyle(
                    color: Colors.grey.shade700, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(value.isEmpty ? '-' : value,
                style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }
}
