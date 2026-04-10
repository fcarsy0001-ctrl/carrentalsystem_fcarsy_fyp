import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../main.dart';
import '../services/leaser_application_service.dart';

enum LeaserType { individual, company }

class LeaserRegisterPage extends StatefulWidget {
  const LeaserRegisterPage({super.key});

  @override
  State<LeaserRegisterPage> createState() => _LeaserRegisterPageState();
}

class _LeaserRegisterPageState extends State<LeaserRegisterPage> {
  SupabaseClient get _supa => Supabase.instance.client;
  late final LeaserApplicationService _svc;

  final _formKey = GlobalKey<FormState>();
  bool _loading = false;

  LeaserType _type = LeaserType.individual;

  final _name = TextEditingController();
  final _companyName = TextEditingController();
  final _ownerName = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _ic = TextEditingController();
  final _password = TextEditingController();
  final _ssmNo = TextEditingController();

  final _picker = ImagePicker();
  XFile? _ssmPhoto;
  Uint8List? _ssmPreview;

  @override
  void initState() {
    super.initState();
    _svc = LeaserApplicationService(_supa);
    // Safety: ensure no session exists while registering.
    _supa.auth.signOut().catchError((_) {});
  }

  @override
  void dispose() {
    _name.dispose();
    _companyName.dispose();
    _ownerName.dispose();
    _phone.dispose();
    _email.dispose();
    _ic.dispose();
    _password.dispose();
    _ssmNo.dispose();
    super.dispose();
  }

  bool get _isCompany => _type == LeaserType.company;

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

  void _toast(String msg, {Color? bg}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: bg),
    );
  }

  Future<String> _generateUserId() async {
    try {
      final row = await _supa
          .from('app_user')
          .select('user_id')
          .order('user_id', ascending: false)
          .limit(1)
          .maybeSingle();

      final lastId = (row?['user_id'] ?? '').toString();
      if (lastId.startsWith('U') && lastId.length >= 4) {
        final numPart = lastId.substring(1);
        final lastNum = int.tryParse(numPart) ?? 0;
        final next = lastNum + 1;
        return 'U${next.toString().padLeft(3, '0')}';
      }
    } catch (_) {}

    final ts = DateTime.now().millisecondsSinceEpoch;
    return 'U${ts.toString().substring(ts.toString().length - 6)}';
  }

  Future<void> _submit() async {
    if (_loading) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);
    try {
      final email = _email.text.trim().toLowerCase();
      final pw = _password.text;

      // 0) Defensive: clear session so AuthWrapper won't route underneath.
      try {
        await _supa.auth.signOut();
      } catch (_) {}

      // 1) Prevent duplicate registration (app_user already exists)
      final exist = await _supa
          .from('app_user')
          .select('user_id')
          .eq('user_email', email)
          .limit(1);
      if (exist is List && exist.isNotEmpty) {
        _toast('This email is already registered. Please login instead.', bg: Colors.orange);
        return;
      }

      // 2) Create auth user
      AuthResponse auth;
      try {
        auth = await _supa.auth.signUp(email: email, password: pw);
      } on AuthException catch (e) {
        final msg = e.message.toLowerCase();
        if (msg.contains('already registered') || msg.contains('user already') || msg.contains('exists')) {
          _toast('This email is already registered. Please login instead.', bg: Colors.orange);
          return;
        }
        rethrow;
      }

      final authUid = auth.user?.id;
      if (authUid == null || authUid.isEmpty) {
        throw Exception('Sign up failed: missing auth uid');
      }

      // Some Supabase projects require email confirmation, so signUp may
      // return without a session. We need a session to insert into Postgres.
      // We will sign out at the end anyway (user must login manually).
      if ((auth.session ?? _supa.auth.currentSession) == null) {
        final signIn = await _supa.auth.signInWithPassword(email: email, password: pw);
        if (signIn.session == null) {
          throw Exception(
              'Sign up succeeded but no session. If your project requires email confirmation, you must verify first or disable confirmation for this flow.');
        }
      }

      // 3) Create app_user row (needed by the app)
      String userId = '';
      const maxRetries = 8;
      for (var i = 0; i < maxRetries; i++) {
        userId = await _generateUserId();
        try {
          await _supa.from('app_user').insert({
            'user_id': userId,
            'auth_uid': authUid,
            'user_name': _isCompany ? _ownerName.text.trim() : _name.text.trim(),
            'user_email': email,
            'user_password': '***',
            'user_phone': _phone.text.trim(),
            'user_icno': _ic.text.trim(),
            'user_gender': 'Male',
            'user_role': 'Leaser',
            'user_status': 'Active',
            'email_verified': true,
          });
          break;
        } catch (e) {
          final s = e.toString();
          if (s.contains('duplicate key') || s.contains('23505')) {
            await Future.delayed(Duration(milliseconds: 120 * (i + 1)));
            continue;
          }
          rethrow;
        }
      }
      if (userId.trim().isEmpty) throw Exception('Failed to create app_user');

      // 5) Upload SSM photo (company only)
      String? ssmPath;
      if (_isCompany) {
        final f = _ssmPhoto;
        if (f == null) throw Exception('SSM photo is required');
        try {
          ssmPath = await _svc.uploadSsmPhoto(authUid: authUid, file: f);
        } catch (_) {
          // If bucket/policy not ready, we still allow submit but without photo.
          ssmPath = null;
        }
      }

      // 6) Insert leaser application
      // NOTE: leaser_id must be unique. If RLS blocks SELECT on "leaser", id generation
      // may fall back to a non-sequential id. We also retry on 23505 just in case.
      final basePayload = <String, dynamic>{
        'user_id': userId,
        'leaser_type': _isCompany ? 'Company' : 'Individual',
        'leaser_name': _isCompany ? _ownerName.text.trim() : _name.text.trim(),
        'company_name': _isCompany ? _companyName.text.trim() : null,
        'owner_name': _isCompany ? _ownerName.text.trim() : null,
        'phone': _phone.text.trim(),
        'email': email,
        'ic_no': _ic.text.trim(),
        'ssm_no': _isCompany ? _ssmNo.text.trim() : null,
        'ssm_photo_path': ssmPath,
        'leaser_status': 'Pending',
        'submitted_at': DateTime.now().toIso8601String(),
      };

      var inserted = false;
      const leaserRetries = 10;
      for (var i = 0; i < leaserRetries; i++) {
        final leaserId = await _svc.generateLeaserId();
        final payload = <String, dynamic>{
          ...basePayload,
          'leaser_id': leaserId,
        };
        try {
          await _supa.from('leaser').insert(payload);
          inserted = true;
          break;
        } catch (e) {
          final s = e.toString();
          if (s.contains('duplicate key') || s.contains('23505')) {
            await Future.delayed(Duration(milliseconds: 150 * (i + 1)));
            continue;
          }
          // Clean auth session to avoid routing to user home.
          try {
            await _supa.auth.signOut();
          } catch (_) {}
          rethrow;
        }
      }
      if (!inserted) {
        try {
          await _supa.auth.signOut();
        } catch (_) {}
        throw Exception('Failed to submit leaser application. Please try again.');
      }

      // 7) MUST logout - user must login manually later
      try {
        await _supa.auth.signOut();
      } catch (_) {}

      if (!mounted) return;
      _toast('Leaser application submitted. Please wait for admin approval, then login again.', bg: Colors.green);
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthWrapper()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      _toast('Register failed: $e', bg: Colors.red);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Become Leaser')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              Text(
                'Want to join us as a vehicle leaser?\nSubmit your details for admin approval.',
                style: TextStyle(color: Colors.grey.shade700),
              ),
              const SizedBox(height: 14),

              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Leaser Type', style: TextStyle(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: RadioListTile<LeaserType>(
                              value: LeaserType.individual,
                              groupValue: _type,
                              onChanged: _loading
                                  ? null
                                  : (v) => setState(() {
                                        _type = v!;
                                      }),
                              title: const Text('Individual'),
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                          Expanded(
                            child: RadioListTile<LeaserType>(
                              value: LeaserType.company,
                              groupValue: _type,
                              onChanged: _loading
                                  ? null
                                  : (v) => setState(() {
                                        _type = v!;
                                      }),
                              title: const Text('Company'),
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),

              if (!_isCompany)
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Name'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),

              if (_isCompany) ...[
                TextFormField(
                  controller: _companyName,
                  decoration: const InputDecoration(labelText: 'Company Name'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _ownerName,
                  decoration: const InputDecoration(labelText: 'Owner / Person in charge name'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
              ],

              const SizedBox(height: 10),
              TextFormField(
                controller: _phone,
                decoration: const InputDecoration(labelText: 'Phone'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _email,
                decoration: const InputDecoration(labelText: 'Email (Login)'),
                keyboardType: TextInputType.emailAddress,
                validator: (v) {
                  final s = (v ?? '').trim();
                  if (s.isEmpty) return 'Required';
                  if (!s.contains('@')) return 'Invalid email';
                  return null;
                },
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _password,
                decoration: const InputDecoration(labelText: 'Password (Login)'),
                obscureText: true,
                validator: (v) {
                  final s = (v ?? '');
                  if (s.trim().isEmpty) return 'Required';
                  if (s.length < 6) return 'Min 6 characters';
                  return null;
                },
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _ic,
                decoration: const InputDecoration(labelText: 'IC'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),

              if (_isCompany) ...[
                const SizedBox(height: 10),
                TextFormField(
                  controller: _ssmNo,
                  decoration: const InputDecoration(
                    labelText: 'SSM No (12 digits)',
                    hintText: '201901000001',
                  ),
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    final s = (v ?? '').trim();
                    if (s.isEmpty) return 'Required';
                    if (!RegExp(r'^\d{12}$').hasMatch(s)) return 'Must be 12 digits';
                    return null;
                  },
                ),
                const SizedBox(height: 10),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('SSM Photo', style: TextStyle(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 10),
                        if (_ssmPreview != null)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.memory(
                              _ssmPreview!,
                              height: 160,
                              width: double.infinity,
                              fit: BoxFit.cover,
                            ),
                          )
                        else
                          Container(
                            height: 160,
                            width: double.infinity,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              color: Colors.grey.shade200,
                            ),
                            child: const Icon(Icons.image_outlined, size: 56),
                          ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _loading ? null : () => _pickSsm(ImageSource.gallery),
                                icon: const Icon(Icons.photo_library_outlined),
                                label: const Text('Gallery'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _loading ? null : () => _pickSsm(ImageSource.camera),
                                icon: const Icon(Icons.camera_alt_outlined),
                                label: const Text('Camera'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Note: create Supabase Storage bucket "${LeaserApplicationService.bucketId}" to store SSM photos.',
                          style: TextStyle(color: Colors.grey.shade700, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 16),
              SizedBox(
                height: 48,
                child: FilledButton(
                  onPressed: _loading ? null : _submit,
                  style: FilledButton.styleFrom(backgroundColor: cs.primary),
                  child: _loading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Submit for Review'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
