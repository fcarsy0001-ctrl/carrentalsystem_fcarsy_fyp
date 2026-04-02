import 'package:flutter/material.dart';

import '../services/job_order_module_service.dart';

class VendorProfileEditPage extends StatefulWidget {
  const VendorProfileEditPage({
    super.key,
    required this.service,
    required this.vendor,
  });

  final JobOrderModuleService service;
  final Map<String, dynamic> vendor;

  @override
  State<VendorProfileEditPage> createState() => _VendorProfileEditPageState();
}

class _VendorProfileEditPageState extends State<VendorProfileEditPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _vendorNameCtrl;
  late final TextEditingController _serviceTypeCtrl;
  late final TextEditingController _contactPersonCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _addressCtrl;
  late final TextEditingController _pricingCtrl;

  bool _saving = false;

  String _s(dynamic value) => value == null ? '' : value.toString().trim();

  @override
  void initState() {
    super.initState();
    _vendorNameCtrl = TextEditingController(text: _s(widget.vendor['vendor_name']));
    _serviceTypeCtrl = TextEditingController(text: _s(widget.vendor['service_category']));
    _contactPersonCtrl = TextEditingController(text: _s(widget.vendor['contact_person']));
    _phoneCtrl = TextEditingController(text: _s(widget.vendor['vendor_phone']));
    _emailCtrl = TextEditingController(text: _s(widget.vendor['vendor_email']));
    _addressCtrl = TextEditingController(text: _s(widget.vendor['vendor_address']));
    _pricingCtrl = TextEditingController(text: _s(widget.vendor['pricing_structure']));
  }

  @override
  void dispose() {
    _vendorNameCtrl.dispose();
    _serviceTypeCtrl.dispose();
    _contactPersonCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _addressCtrl.dispose();
    _pricingCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    try {
      await widget.service.updateVendorProfile(
        vendorId: _s(widget.vendor['vendor_id']),
        vendorName: _vendorNameCtrl.text.trim(),
        serviceCategory: _serviceTypeCtrl.text.trim(),
        contactPerson: _contactPersonCtrl.text.trim(),
        phone: _phoneCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
        address: _addressCtrl.text.trim(),
        pricingStructure: _pricingCtrl.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vendor profile updated.')),
      );
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.service.explainError(error)),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit Vendor Profile')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            TextFormField(
              controller: _vendorNameCtrl,
              decoration: const InputDecoration(labelText: 'Vendor Name'),
              validator: (value) => (value == null || value.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _serviceTypeCtrl,
              decoration: const InputDecoration(labelText: 'Service Type'),
              validator: (value) => (value == null || value.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _contactPersonCtrl,
              decoration: const InputDecoration(labelText: 'Contact Person'),
              validator: (value) => (value == null || value.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone'),
              validator: (value) => (value == null || value.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Contact Email'),
              validator: (value) {
                if (value == null || value.trim().isEmpty) return 'Required';
                if (!value.contains('@')) return 'Enter a valid email';
                return null;
              },
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _addressCtrl,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Business Address'),
              validator: (value) => (value == null || value.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _pricingCtrl,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Pricing Structure'),
              validator: (value) => (value == null || value.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(_saving ? 'Saving...' : 'Save Profile'),
            ),
          ],
        ),
      ),
    );
  }
}