import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/app_user_service.dart';
import '../utils/country_codes.dart';

class ProfileInfoPage extends StatefulWidget {
  const ProfileInfoPage({super.key});

  @override
  State<ProfileInfoPage> createState() => _ProfileInfoPageState();
}

class _ProfileInfoPageState extends State<ProfileInfoPage> {
  SupabaseClient get _supa => Supabase.instance.client;

  final _formKey = GlobalKey<FormState>();

  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _icno = TextEditingController();

  String _gender = 'Male';
  bool _loading = true;
  bool _saving = false;
  CountryCode _selectedCountry = CountryCodes.getDefault();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _icno.dispose();
    super.dispose();
  }

  void _splitStoredPhone(String rawPhone) {
    final phone = rawPhone.trim();
    if (phone.isEmpty) {
      _selectedCountry = CountryCodes.getDefault();
      _phone.clear();
      return;
    }

    CountryCode? matchedCountry;
    for (final country in CountryCodes.countries) {
      if (phone.startsWith(country.dialCode)) {
        if (matchedCountry == null ||
            country.dialCode.length > matchedCountry.dialCode.length) {
          matchedCountry = country;
        }
      }
    }

    if (matchedCountry != null) {
      _selectedCountry = matchedCountry;
      _phone.text = phone.substring(matchedCountry.dialCode.length);
    } else {
      _selectedCountry = CountryCodes.getDefault();
      _phone.text = phone.replaceAll(RegExp(r'\D'), '');
    }
  }

  Future<void> _load() async {
    final user = _supa.auth.currentUser;
    if (user == null) return;

    try {
      final row = await _supa
          .from('app_user')
          .select('*')
          .eq('auth_uid', user.id)
          .maybeSingle();

      if (row != null) {
        final m = Map<String, dynamic>.from(row as Map);
        _name.text = (m['user_name'] ?? '').toString();
        _splitStoredPhone((m['user_phone'] ?? '').toString());
        _icno.text = (m['user_icno'] ?? '').toString();
        final g = (m['user_gender'] ?? '').toString().trim();
        if (g.isNotEmpty) _gender = g;
      } else {
        await AppUserService(_supa).ensureAppUser();
      }
    } catch (_) {}

    if (!mounted) return;
    setState(() => _loading = false);
  }

  Future<void> _save() async {
    final user = _supa.auth.currentUser;
    if (user == null) return;

    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _saving = true);
    try {
      await AppUserService(_supa).ensureAppUser();

      final localPhone = _phone.text.trim();
      final fullPhone = '${_selectedCountry.dialCode}$localPhone';

      await _supa.from('app_user').update({
        'user_name': _name.text.trim(),
        'user_phone': fullPhone,
        'user_icno': _icno.text.trim(),
        'user_gender': _gender,
      }).eq('auth_uid', user.id);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated')),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Profile information')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      color: cs.surfaceContainerHighest.withOpacity(0.45),
                      border:
                          Border.all(color: cs.outlineVariant.withOpacity(0.25)),
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Update your details',
                              style: TextStyle(
                                  fontWeight: FontWeight.w900, fontSize: 16)),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _name,
                            inputFormatters: [
                              LengthLimitingTextInputFormatter(100),
                              FilteringTextInputFormatter.deny(RegExp(r'\d')),
                            ],
                            decoration: const InputDecoration(
                              labelText: 'Full name',
                              border: OutlineInputBorder(),
                            ),
                            validator: (v) {
                              final value = v?.trim() ?? '';
                              if (value.isEmpty) {
                                return 'Name is required';
                              }
                              if (RegExp(r'\d').hasMatch(value)) {
                                return 'Full name cannot contain digits';
                              }
                              if (value.length > 100) {
                                return 'Full name cannot be more than 100 characters';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Container(
                                width: 130,
                                decoration: BoxDecoration(
                                  color: Colors.grey[50],
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.grey[300]!),
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<CountryCode>(
                                    value: _selectedCountry,
                                    isExpanded: true,
                                    icon: const Icon(Icons.arrow_drop_down, size: 24),
                                    items: CountryCodes.countries.map((country) {
                                      return DropdownMenuItem<CountryCode>(
                                        value: country,
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 8),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                country.safeFlagLabel,
                                                style: const TextStyle(fontSize: 18),
                                              ),
                                              const SizedBox(width: 6),
                                              Flexible(
                                                child: Text(
                                                  country.dialCode,
                                                  style: const TextStyle(fontSize: 14),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                    onChanged: (value) {
                                      if (value == null) return;
                                      setState(() => _selectedCountry = value);
                                    },
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextFormField(
                                  controller: _phone,
                                  keyboardType: TextInputType.phone,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                    LengthLimitingTextInputFormatter(18),
                                  ],
                                  decoration: const InputDecoration(
                                    labelText: 'Phone number',
                                    border: OutlineInputBorder(),
                                  ),
                                  validator: (v) {
                                    final value = v?.trim() ?? '';
                                    if (value.isEmpty) {
                                      return 'Phone is required';
                                    }
                                    if (!RegExp(r'^\d+$').hasMatch(value)) {
                                      return 'Phone number must contain only digits';
                                    }
                                    if (value.length < 7) {
                                      return 'Phone number is too short';
                                    }
                                    if (value.length > 18) {
                                      return 'Phone number cannot be more than 18 digits';
                                    }
                                    return null;
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _icno,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(12),
                            ],
                            decoration: const InputDecoration(
                              labelText: 'IC number',
                              border: OutlineInputBorder(),
                            ),
                            validator: (v) {
                              final value = v?.trim() ?? '';
                              if (value.isEmpty) {
                                return 'IC number is required';
                              }
                              if (!RegExp(r'^\d+$').hasMatch(value)) {
                                return 'IC number must contain only digits';
                              }
                              if (value.length > 12) {
                                return 'IC number cannot be more than 12 digits';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            value: _gender,
                            items: const [
                              DropdownMenuItem(
                                  value: 'Male', child: Text('Male')),
                              DropdownMenuItem(
                                  value: 'Female', child: Text('Female')),
                              DropdownMenuItem(
                                  value: 'Other', child: Text('Other')),
                            ],
                            onChanged: (v) {
                              if (v == null) return;
                              setState(() => _gender = v);
                            },
                            decoration: const InputDecoration(
                              labelText: 'Gender',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: _saving ? null : _save,
                              child: _saving
                                  ? const SizedBox(
                                      height: 18,
                                      width: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : const Text('Save'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
