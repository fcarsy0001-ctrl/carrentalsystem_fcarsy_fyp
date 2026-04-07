import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../main.dart';

class VendorRegisterPage extends StatefulWidget {
  const VendorRegisterPage({super.key});

  @override
  State<VendorRegisterPage> createState() => _VendorRegisterPageState();
}

class _VendorRegisterPageState extends State<VendorRegisterPage> {
  SupabaseClient get _supa => Supabase.instance.client;

  final _formKey = GlobalKey<FormState>();
  final _vendorName = TextEditingController();
  final _serviceType = TextEditingController();
  final _contactPerson = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _address = TextEditingController();
  final _pricing = TextEditingController();

  bool _loading = false;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _supa.auth.signOut().catchError((_) {});
  }

  @override
  void dispose() {
    _vendorName.dispose();
    _serviceType.dispose();
    _contactPerson.dispose();
    _phone.dispose();
    _email.dispose();
    _password.dispose();
    _address.dispose();
    _pricing.dispose();
    super.dispose();
  }

  String _s(dynamic value) => value == null ? '' : value.toString().trim();

  void _toast(String message, {Color? backgroundColor}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: backgroundColor),
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
        final next = (int.tryParse(lastId.substring(1)) ?? 0) + 1;
        return 'U${next.toString().padLeft(3, '0')}';
      }
    } catch (_) {}

    final micros = DateTime.now().microsecondsSinceEpoch.toString();
    return 'U${micros.substring(micros.length - 6)}';
  }

  String _generateVendorId() {
    final micros = DateTime.now().microsecondsSinceEpoch.toString();
    return 'V${micros.substring(micros.length - 5)}';
  }

  Future<Map<String, dynamic>?> _findAppUserByEmail(String email) async {
    try {
      final row = await _supa
          .from('app_user')
          .select('*')
          .eq('user_email', email)
          .limit(1)
          .maybeSingle();
      if (row != null) return Map<String, dynamic>.from(row as Map);
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>?> _findVendor({String? userId, String? email}) async {
    if (_s(userId).isNotEmpty) {
      try {
        final row = await _supa
            .from('vendor')
            .select('*')
            .eq('user_id', userId!.trim())
            .order('vendor_id', ascending: false)
            .limit(1)
            .maybeSingle();
        if (row != null) return Map<String, dynamic>.from(row as Map);
      } catch (_) {}
    }

    if (_s(email).isNotEmpty) {
      try {
        final row = await _supa
            .from('vendor')
            .select('*')
            .eq('vendor_email', email!.trim().toLowerCase())
            .order('vendor_id', ascending: false)
            .limit(1)
            .maybeSingle();
        if (row != null) return Map<String, dynamic>.from(row as Map);
      } catch (_) {}
    }
    return null;
  }

  Future<String> _signInExistingAuth(String email, String password) async {
    try {
      final response = await _supa.auth.signInWithPassword(email: email, password: password);
      final authUid = response.user?.id ?? _supa.auth.currentUser?.id ?? '';
      if (authUid.isEmpty) {
        throw Exception('No auth uid returned for the existing account.');
      }
      return authUid;
    } on AuthException {
      throw Exception(
        'This email is already registered, but the vendor application was incomplete. '
            'Please login with the same password or ask admin to remove the broken account before registering again.',
      );
    }
  }

  Future<String> _createOrRecoverAuth(String email, String password) async {
    try {
      final authResponse = await _supa.auth.signUp(email: email, password: password);
      final authUid = authResponse.user?.id ?? '';
      if (authUid.isEmpty) {
        throw Exception('Sign up failed: missing auth uid');
      }

      if ((authResponse.session ?? _supa.auth.currentSession) == null) {
        return _signInExistingAuth(email, password);
      }

      return authUid;
    } on AuthException catch (error) {
      final message = error.message.toLowerCase();
      if (message.contains('already registered') || message.contains('exists')) {
        return _signInExistingAuth(email, password);
      }
      rethrow;
    }
  }

  Future<void> _insertVendorProfile({
    required String userId,
    required String authUid,
    required String email,
  }) async {
    final basePayload = <String, dynamic>{
      'vendor_name': _vendorName.text.trim(),
      'service_category': _serviceType.text.trim(),
      'contact_person': _contactPerson.text.trim(),
      'vendor_phone': _phone.text.trim(),
      'vendor_email': email,
      'vendor_address': _address.text.trim(),
      'pricing_structure': _pricing.text.trim(),
      'vendor_rating': 0,
      'vendor_status': 'Pending',
    };

    for (var i = 0; i < 10; i++) {
      final vendorId = _generateVendorId();
      final payloadAttempts = <Map<String, dynamic>>[
        {
          'vendor_id': vendorId,
          'user_id': userId,
          'auth_uid': authUid,
          ...basePayload,
        },
        {
          'vendor_id': vendorId,
          'auth_uid': authUid,
          ...basePayload,
        },
        {
          'vendor_id': vendorId,
          ...basePayload,
        },
        {
          'vendor_id': vendorId,
          'vendor_name': _vendorName.text.trim(),
          'service_category': _serviceType.text.trim(),
          'vendor_email': email,
          'vendor_status': 'Pending',
        },
      ];

      Object? lastError;
      var retryWithNewId = false;

      for (final payload in payloadAttempts) {
        try {
          await _supa.from('vendor').insert(payload);
          return;
        } catch (error) {
          lastError = error;
          final text = error.toString().toLowerCase();

          if (text.contains('duplicate key') || text.contains('23505')) {
            if (text.contains('vendor_email') || text.contains('vendor_email_key')) {
              throw Exception('This vendor application already exists. Please login instead.');
            }
            retryWithNewId = true;
            break;
          }

          final canTryLeanerPayload =
              text.contains('character varying(6)') ||
                  text.contains('varchar(6)') ||
                  text.contains('column') ||
                  text.contains('pricing_structure') ||
                  text.contains('auth_uid') ||
                  text.contains('user_id');

          if (canTryLeanerPayload) {
            continue;
          }

          rethrow;
        }
      }

      if (retryWithNewId) {
        await Future.delayed(Duration(milliseconds: 120 * (i + 1)));
        continue;
      }

      if (lastError != null) {
        final text = lastError.toString().toLowerCase();
        if (text.contains('character varying(6)') || text.contains('varchar(6)')) {
          throw Exception(
            'Your vendor table still has an old short-column schema. '
                'The app tried the legacy-safe fallback, but the table still rejected the application. '
                'Run supabase/vendor_role_patch.sql first.',
          );
        }
        if (text.contains('column') || text.contains('pricing_structure') || text.contains('auth_uid') || text.contains('user_id')) {
          throw Exception('Vendor table is missing the new portal columns. Run supabase/vendor_role_patch.sql first.');
        }
        throw Exception(lastError.toString());
      }
    }

    throw Exception('Failed to create the vendor profile. Please try again.');
  }
  Future<void> _submit() async {
    if (_loading) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);
    try {
      final email = _email.text.trim().toLowerCase();
      final password = _password.text;

      try {
        await _supa.auth.signOut();
      } catch (_) {}

      final existingAppUser = await _findAppUserByEmail(email);
      String userId = '';
      String authUid = '';

      if (existingAppUser != null) {
        final role = _s(existingAppUser['user_role']).toLowerCase();
        userId = _s(existingAppUser['user_id']);

        if (role.isNotEmpty && role != 'vendor') {
          _toast('This email is already registered. Please login instead.', backgroundColor: Colors.orange);
          return;
        }

        final existingVendor = await _findVendor(userId: userId, email: email);
        if (existingVendor != null) {
          final status = _s(existingVendor['vendor_status']).isEmpty
              ? 'Pending'
              : _s(existingVendor['vendor_status']);
          _toast('This vendor application already exists ($status). Please login instead.', backgroundColor: Colors.orange);
          return;
        }

        authUid = await _signInExistingAuth(email, password);
      } else {
        authUid = await _createOrRecoverAuth(email, password);

        final appUserAfterAuth = await _findAppUserByEmail(email);
        if (appUserAfterAuth != null) {
          final role = _s(appUserAfterAuth['user_role']).toLowerCase();
          userId = _s(appUserAfterAuth['user_id']);
          if (role.isNotEmpty && role != 'vendor') {
            _toast('This email is already registered. Please login instead.', backgroundColor: Colors.orange);
            return;
          }
        }

        if (userId.isEmpty) {
          for (var i = 0; i < 8; i++) {
            userId = await _generateUserId();
            try {
              await _supa.from('app_user').insert({
                'user_id': userId,
                'auth_uid': authUid,
                'user_name': _vendorName.text.trim(),
                'user_email': email,
                'user_password': '***',
                'user_phone': _phone.text.trim(),
                'user_icno': 'N/A',
                'user_gender': 'Other',
                'user_role': 'vendor',
                'user_status': 'Active',
                'email_verified': true,
              });
              break;
            } catch (error) {
              final text = error.toString().toLowerCase();
              if (text.contains('duplicate key') || text.contains('23505')) {
                await Future.delayed(Duration(milliseconds: 120 * (i + 1)));
                continue;
              }
              rethrow;
            }
          }
        }

        if (userId.trim().isEmpty) {
          throw Exception('Failed to create the vendor user profile.');
        }

        final existingVendor = await _findVendor(userId: userId, email: email);
        if (existingVendor != null) {
          final status = _s(existingVendor['vendor_status']).isEmpty
              ? 'Pending'
              : _s(existingVendor['vendor_status']);
          _toast('This vendor application already exists ($status). Please login instead.', backgroundColor: Colors.orange);
          return;
        }
      }

      await _insertVendorProfile(userId: userId, authUid: authUid, email: email);

      try {
        await _supa.auth.signOut();
      } catch (_) {}

      if (!mounted) return;
      _toast('Vendor application submitted. Please wait for admin approval, then login again.', backgroundColor: Colors.green);
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthWrapper()),
            (route) => false,
      );
    } catch (error) {
      try {
        await _supa.auth.signOut();
      } catch (_) {}
      if (!mounted) return;
      _toast('Vendor registration failed: $error', backgroundColor: Colors.red);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Become Vendor')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              Text(
                'Register your service business for admin approval before leasers can assign maintenance and inspection job orders to your team.',
                style: TextStyle(color: Colors.grey.shade700),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _vendorName,
                decoration: const InputDecoration(labelText: 'Vendor Name'),
                validator: (value) => (value == null || value.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _serviceType,
                decoration: const InputDecoration(labelText: 'Service Type'),
                validator: (value) => (value == null || value.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _contactPerson,
                decoration: const InputDecoration(labelText: 'Contact Person'),
                validator: (value) => (value == null || value.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Phone'),
                validator: (value) => (value == null || value.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email'),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) return 'Required';
                  if (!value.contains('@')) return 'Enter a valid email';
                  return null;
                },
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _password,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  labelText: 'Password',
                  suffixIcon: IconButton(
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) return 'Required';
                  if (value.length < 6) return 'At least 6 characters';
                  return null;
                },
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _address,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Business Address'),
                validator: (value) => (value == null || value.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _pricing,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Pricing Structure',
                  hintText: 'For example: Brake inspection from RM80, labour RM120/hour, towing quoted separately.',
                ),
                validator: (value) => (value == null || value.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _loading ? null : _submit,
                icon: _loading
                    ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
                    : const Icon(Icons.storefront_outlined),
                label: Text(_loading ? 'Submitting Application...' : 'Create Vendor Account'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}






