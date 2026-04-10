import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/app_user_service.dart';
import '../services/driver_license_service.dart';

class DriverLicenseSubmitPage extends StatefulWidget {
  const DriverLicenseSubmitPage({super.key});

  @override
  State<DriverLicenseSubmitPage> createState() =>
      _DriverLicenseSubmitPageState();
}

class _DriverLicenseSubmitPageState extends State<DriverLicenseSubmitPage> {
  SupabaseClient get _supa => Supabase.instance.client;

  final _formKey = GlobalKey<FormState>();

  final _licenseNo = TextEditingController();
  final _licenseName = TextEditingController();

  DateTime? _expiry;
  XFile? _photo;
  Uint8List? _photoBytes;

  bool _saving = false;

  @override
  void dispose() {
    _licenseNo.dispose();
    _licenseName.dispose();
    super.dispose();
  }

  Future<void> _pickExpiry() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiry ?? DateTime(now.year + 1, now.month, now.day),
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 20),
    );
    if (picked == null) return;
    setState(() => _expiry = picked);
  }

  Future<void> _takePhoto(ImageSource source) async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 1600,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() {
      _photo = file;
      _photoBytes = bytes;
    });
  }

  Future<void> _submit() async {
    final user = _supa.auth.currentUser;
    if (user == null) return;

    final valid = _formKey.currentState?.validate() ?? false;
    if (!valid) return;

    if (_expiry == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select expiry date')),
      );
      return;
    }
    if (_photo == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please take a clear licence photo')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await AppUserService(_supa).ensureAppUser();

      await DriverLicenseService(_supa).submit(
        licenseNo: _licenseNo.text.trim(),
        licenseName: _licenseName.text.trim(),
        expiryDate: _expiry!,
        photo: _photo!,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Submitted for admin review')),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Submit failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Submit driver licence')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                color: cs.surfaceContainerHighest.withOpacity(0.45),
                border: Border.all(color: cs.outlineVariant.withOpacity(0.25)),
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Driver licence details',
                      style:
                          TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _licenseNo,
                      decoration: const InputDecoration(
                        labelText: 'Licence number',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Licence number is required';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _licenseName,
                      decoration: const InputDecoration(
                        labelText: 'Name on licence',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Name is required';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: _pickExpiry,
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Expiry date',
                          border: OutlineInputBorder(),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.event_outlined, size: 18),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _expiry == null
                                    ? 'Select expiry date'
                                    : _expiry!
                                        .toIso8601String()
                                        .split('T')
                                        .first,
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: _expiry == null
                                      ? Colors.grey.shade600
                                      : null,
                                ),
                              ),
                            ),
                            const Icon(Icons.chevron_right_rounded),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Licence photo (required)',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 180,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        color: cs.surface,
                        border:
                            Border.all(color: cs.outlineVariant.withOpacity(0.3)),
                      ),
                      alignment: Alignment.center,
                      child: _photo == null
                          ? Text(
                              'No photo yet',
                              style: TextStyle(color: Colors.grey.shade600),
                            )
                          : ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: (_photoBytes == null || _photoBytes!.isEmpty)
                                  ? const Text('Preview not available (but upload will work)')
                                  : Image.memory(
                                      _photoBytes!,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => const Text(
                                        'Preview not available (but upload will work)',
                                      ),
                                    ),
                            ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed:
                                _saving ? null : () => _takePhoto(ImageSource.camera),
                            icon: const Icon(Icons.photo_camera_outlined),
                            label: const Text('Take photo'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _saving
                                ? null
                                : () => _takePhoto(ImageSource.gallery),
                            icon: const Icon(Icons.photo_library_outlined),
                            label: const Text('Gallery'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _saving ? null : _submit,
                        child: _saving
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Submit for review'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Your rental features will be locked until an admin approves your submission.',
              style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
            ),
            const SizedBox(height: 8),
            Text(
              'If you see a build error: add image_picker to pubspec.yaml (dependencies: image_picker: ^1.0.0).',
              style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
