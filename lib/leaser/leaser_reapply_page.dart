import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'leaser_status_page.dart';
import '../services/leaser_application_service.dart';

enum _LeaserType { individual, company }

/// Reapply flow for a rejected leaser.
///
/// IMPORTANT: This page does NOT create a new auth/app_user record.
/// It updates the existing `leaser` row and resets status to Pending.
class LeaserReapplyPage extends StatefulWidget {
  const LeaserReapplyPage({super.key, required this.leaserId});

  final String leaserId;

  @override
  State<LeaserReapplyPage> createState() => _LeaserReapplyPageState();
}

class _LeaserReapplyPageState extends State<LeaserReapplyPage> {
  SupabaseClient get _supa => Supabase.instance.client;
  late final LeaserApplicationService _svc;

  final _formKey = GlobalKey<FormState>();
  bool _loading = true;
  bool _saving = false;

  _LeaserType _type = _LeaserType.individual;

  // Fields (match current leaser schema used in admin review pages)
  final _name = TextEditingController();
  final _companyName = TextEditingController();
  final _ownerName = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _ic = TextEditingController();
  final _ssmNo = TextEditingController();

  final _picker = ImagePicker();
  XFile? _ssmPhoto;
  Uint8List? _ssmPreview;
  String? _existingSsmPath;
  String? _existingSsmSignedUrl;

  String? _leaserId;
  String? _userId;

  bool get _isCompany => _type == _LeaserType.company;

  @override
  void initState() {
    super.initState();
    _svc = LeaserApplicationService(_supa);
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _companyName.dispose();
    _ownerName.dispose();
    _phone.dispose();
    _email.dispose();
    _ic.dispose();
    _ssmNo.dispose();
    super.dispose();
  }

  void _toast(String msg, {Color? bg}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: bg),
    );
  }

  String _s(dynamic v) => v == null ? '' : v.toString();

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final user = _supa.auth.currentUser;
      if (user == null) {
        throw Exception('No session. Please login again.');
      }

      // Resolve current leaser application.
      // IMPORTANT: Reapply should NOT depend on creating a new auth/app_user record.
      // We prefer the leaserId passed from the Rejected page, and only use app_user
      // as an OPTIONAL fallback/prefill.

      final passedLeaserId = widget.leaserId.trim();
      Map<String, dynamic>? row;

      // Try to read user profile (optional; do NOT block reapply if missing/RLS).
      Map<String, dynamic>? userProfile;
      String userId = '';
      try {
        userProfile = await _supa
            .from('app_user')
            .select('user_id,user_email,user_phone,user_icno,user_name')
            .eq('auth_uid', user.id)
            .limit(1)
            .maybeSingle();
        if (userProfile != null) {
          userId = _s(userProfile['user_id']).trim();
        }
      } catch (_) {
        // ignore (RLS might block)
      }
      _userId = userId;

      // Load leaser row by leaser_id first (works even if app_user is not readable)
      if (passedLeaserId.isNotEmpty) {
        try {
          row = await _supa
              .from('leaser')
              .select('*')
              .eq('leaser_id', passedLeaserId)
              .limit(1)
              .maybeSingle();
        } catch (_) {
          row = null;
        }
      }

      // Fallback: load leaser row by user_id (if available)
      if (row == null && userId.isNotEmpty) {
        row = await _svc.getByUserId(userId);
      }

      // Extra fallback (older data): sometimes leaser.user_id accidentally stored auth uid
      if (row == null && userId.isEmpty) {
        try {
          row = await _svc.getByUserId(user.id);
        } catch (_) {
          row = null;
        }
      }

      if (row == null) throw Exception('Leaser application not found.');
      _leaserId = _s(row['leaser_id']).trim();
      final typeRaw = _s(row['leaser_type']).trim().toLowerCase();
      _type = typeRaw == 'company' ? _LeaserType.company : _LeaserType.individual;

      // Prefill fields from leaser row first; fallback to app_user values
      _name.text = _s(row['leaser_name']).trim().isNotEmpty
          ? _s(row['leaser_name']).trim()
          : _s(userProfile?['user_name']).trim();
      _companyName.text = _s(row['company_name']).trim();
      _ownerName.text = _s(row['owner_name']).trim();
      _phone.text = _s(row['phone']).trim().isNotEmpty
          ? _s(row['phone']).trim()
          : _s(userProfile?['user_phone']).trim();
      _email.text = _s(row['email']).trim().isNotEmpty
          ? _s(row['email']).trim()
          : _s(userProfile?['user_email']).trim();
      _ic.text = _s(row['ic_no']).trim().isNotEmpty
          ? _s(row['ic_no']).trim()
          : _s(userProfile?['user_icno']).trim();
      _ssmNo.text = _s(row['ssm_no']).trim();
      _existingSsmPath = _s(row['ssm_photo_path']).trim();

      if ((_existingSsmPath ?? '').trim().isNotEmpty) {
        _existingSsmSignedUrl = await _svc.createSignedSsmUrl(_existingSsmPath!);
      }
    } catch (e) {
      _toast('Load failed: $e', bg: Colors.red);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickSsm(ImageSource source) async {
    try {
      final f = await _picker.pickImage(source: source, imageQuality: 85);
      if (f == null) return;
      final bytes = await f.readAsBytes();
      if (!mounted) return;
      setState(() {
        _ssmPhoto = f;
        _ssmPreview = bytes;
      });
    } catch (_) {}
  }

  Future<void> _submit() async {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) return;

    final leaserId = (_leaserId ?? '').trim();
    final user = _supa.auth.currentUser;
    if (leaserId.isEmpty || user == null) {
      _toast('Missing session data. Please login again.', bg: Colors.red);
      return;
    }

    setState(() => _saving = true);
    try {
      String? ssmPath = _existingSsmPath;

      // Company must have SSM photo either existing or new
      if (_isCompany) {
        if ((_ssmPhoto == null) && (ssmPath == null || ssmPath.trim().isEmpty)) {
          _toast('SSM photo is required for company.', bg: Colors.orange);
          return;
        }
      }

      // Upload new SSM photo if user selected
      if (_isCompany && _ssmPhoto != null) {
        try {
          ssmPath = await _svc.uploadSsmPhoto(authUid: user.id, file: _ssmPhoto!);
        } catch (_) {
          // If storage not configured, we still allow submit without changing path.
        }
      }

      final payload = <String, dynamic>{
        'leaser_type': _isCompany ? 'Company' : 'Individual',
        'leaser_name': _isCompany ? _ownerName.text.trim() : _name.text.trim(),
        'company_name': _isCompany ? _companyName.text.trim() : null,
        'owner_name': _isCompany ? _ownerName.text.trim() : null,
        'phone': _phone.text.trim(),
        'email': _email.text.trim().toLowerCase(),
        'ic_no': _ic.text.trim(),
        'ssm_no': _isCompany ? _ssmNo.text.trim() : null,
        'ssm_photo_path': _isCompany ? ssmPath : null,
        'leaser_status': 'Pending',
        'submitted_at': DateTime.now().toIso8601String(),
        'reviewed_at': null,
        'leaser_reject_remark': null,
      };

      // IMPORTANT:
      // If RLS blocks the UPDATE, PostgREST may return 0 updated rows without an error.
      // We therefore request representation and verify the status is actually updated.
      final resp = await _supa
          .from('leaser')
          .update(payload)
          .eq('leaser_id', leaserId)
          // NOTE: Do NOT use single()/maybeSingle() here.
          // Some PostgREST setups return PGRST116 (406) when 0 rows are returned for object coercion.
          // We keep it as array JSON and handle empty list ourselves.
          .select('leaser_id, leaser_status');

      Map<String, dynamic>? updated;
      if (resp is List && resp.isNotEmpty) {
        final first = resp.first;
        if (first is Map) updated = Map<String, dynamic>.from(first);
      } else if (resp is Map) {
        updated = Map<String, dynamic>.from(resp as Map);
      }

      if (updated == null) {
        _toast(
          'Reapply not saved (no rows updated). This is usually caused by Supabase RLS policy blocking UPDATE.\nPlease contact admin or add the required RLS policy.',
          bg: Colors.red,
        );
        return;
      }

      final st = _s(updated['leaser_status']).trim().toLowerCase();
      if (st.isNotEmpty && st != 'pending') {
        _toast(
          'Reapply not saved. Current status: ${updated['leaser_status']}',
          bg: Colors.red,
        );
        return;
      }

      if (!mounted) return;
      _toast('Reapply submitted. Please wait for admin approval.', bg: Colors.green);

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LeaserStatusPage(status: LeaserStatus.pending)),
        (route) => false,
      );
    } catch (e) {
      _toast('Reapply failed: $e', bg: Colors.red);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Reapply Leaser')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text('Leaser Type', style: TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              SegmentedButton<_LeaserType>(
                segments: const [
                  ButtonSegment(value: _LeaserType.individual, label: Text('Individual')),
                  ButtonSegment(value: _LeaserType.company, label: Text('Company')),
                ],
                selected: {_type},
                onSelectionChanged: (s) => setState(() => _type = s.first),
              ),
              const SizedBox(height: 16),
              if (!_isCompany)
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Name'),
                  validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null,
                ),
              if (_isCompany) ...[
                TextFormField(
                  controller: _companyName,
                  decoration: const InputDecoration(labelText: 'Company Name'),
                  validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _ownerName,
                  decoration: const InputDecoration(labelText: 'PIC / Owner Name'),
                  validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _ssmNo,
                  decoration: const InputDecoration(labelText: 'SSM No'),
                  validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null,
                ),
              ],
              const SizedBox(height: 10),
              TextFormField(
                controller: _phone,
                decoration: const InputDecoration(labelText: 'Phone'),
                validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _email,
                enabled: false,
                decoration: const InputDecoration(labelText: 'Email (cannot change)'),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _ic,
                decoration: const InputDecoration(labelText: 'IC No'),
                validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null,
              ),

              if (_isCompany) ...[
                const SizedBox(height: 16),
                const Text('SSM Photo', style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                _buildSsmPreview(),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _saving ? null : () => _pickSsm(ImageSource.gallery),
                        icon: const Icon(Icons.photo_library_outlined),
                        label: const Text('Gallery'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _saving ? null : () => _pickSsm(ImageSource.camera),
                        icon: const Icon(Icons.photo_camera_outlined),
                        label: const Text('Camera'),
                      ),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 18),
              FilledButton(
                onPressed: _saving ? null : _submit,
                child: _saving
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Submit Reapply'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSsmPreview() {
    final border = Border.all(color: Colors.grey.shade300);
    final radius = BorderRadius.circular(12);

    if (_ssmPreview != null) {
      return ClipRRect(
        borderRadius: radius,
        child: Container(
          decoration: BoxDecoration(border: border, borderRadius: radius),
          height: 180,
          child: Image.memory(_ssmPreview!, fit: BoxFit.cover, width: double.infinity),
        ),
      );
    }

    if ((_existingSsmSignedUrl ?? '').isNotEmpty) {
      return ClipRRect(
        borderRadius: radius,
        child: Container(
          decoration: BoxDecoration(border: border, borderRadius: radius),
          height: 180,
          child: Image.network(
            _existingSsmSignedUrl!,
            fit: BoxFit.cover,
            width: double.infinity,
            errorBuilder: (_, __, ___) => const Center(child: Text('SSM photo unavailable')),
          ),
        ),
      );
    }

    return Container(
      height: 180,
      width: double.infinity,
      decoration: BoxDecoration(border: border, borderRadius: radius, color: Colors.grey.shade100),
      alignment: Alignment.center,
      child: const Text('No SSM photo selected'),
    );
  }
}
