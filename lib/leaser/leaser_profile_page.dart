
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LeaserProfilePage extends StatefulWidget {
  const LeaserProfilePage({
    super.key,
    required this.leaserId,
    this.embedded = false,
  });

  final String leaserId;
  final bool embedded;

  @override
  State<LeaserProfilePage> createState() => _LeaserProfilePageState();
}

class _LeaserProfilePageState extends State<LeaserProfilePage> {
  SupabaseClient get _supa => Supabase.instance.client;

  final _formKey = GlobalKey<FormState>();

  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _companyCtrl = TextEditingController();
  final _ownerCtrl = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String? _error;

  Map<String, dynamic>? _profile;
  String _email = '';
  String _type = '';
  String _status = '';
  String _userId = '';

  String _s(dynamic value) => value == null ? '' : value.toString().trim();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _companyCtrl.dispose();
    _ownerCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final row = await _supa
          .from('leaser')
          .select('*')
          .eq('leaser_id', widget.leaserId)
          .limit(1)
          .maybeSingle();

      if (row == null) {
        throw Exception('Leaser profile not found.');
      }

      final data = Map<String, dynamic>.from(row as Map);
      _profile = data;
      _email = _s(data['email']);
      _type = _s(data['leaser_type']);
      _status = _s(data['leaser_status']);
      _userId = _s(data['user_id']);

      _nameCtrl.text = _s(data['leaser_name']);
      _phoneCtrl.text = _s(data['phone']);
      _companyCtrl.text = _s(data['company_name']).isNotEmpty
          ? _s(data['company_name'])
          : _s(data['leaser_company']);
      _ownerCtrl.text = _s(data['owner_name']);
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _saving = true);
    try {
      final current = _profile ?? <String, dynamic>{};
      final payload = <String, dynamic>{};

      void setIfExists(String key, dynamic value) {
        if (current.containsKey(key)) payload[key] = value;
      }

      final name = _nameCtrl.text.trim();
      final phone = _phoneCtrl.text.trim();
      final company = _companyCtrl.text.trim();
      final owner = _ownerCtrl.text.trim();

      setIfExists('leaser_name', name);
      setIfExists('phone', phone);
      setIfExists('company_name', company.isEmpty ? null : company);
      setIfExists('leaser_company', company.isEmpty ? null : company);
      setIfExists('owner_name', owner.isEmpty ? null : owner);

      if (payload.isEmpty) {
        throw Exception('Nothing to update.');
      }

      await _supa.from('leaser').update(payload).eq('leaser_id', widget.leaserId);

      if (_userId.isNotEmpty) {
        final userPayload = <String, dynamic>{};
        if (name.isNotEmpty) userPayload['user_name'] = name;
        if (phone.isNotEmpty) userPayload['user_phone'] = phone;
        if (userPayload.isNotEmpty) {
          try {
            await _supa.from('app_user').update(userPayload).eq('user_id', _userId);
          } catch (_) {}
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Leaser profile updated.')),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save failed: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = _buildBody();
    if (widget.embedded) return content;
    return Scaffold(
      appBar: AppBar(title: const Text('Leaser Profile')),
      body: content,
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('Failed to load profile: $_error'),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            _InfoCard(
              title: 'Account info',
              child: Column(
                children: [
                  _ReadOnlyField(label: 'Leaser ID', value: widget.leaserId),
                  const SizedBox(height: 10),
                  _ReadOnlyField(label: 'Email', value: _email.isEmpty ? '-' : _email),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: _ReadOnlyField(label: 'Type', value: _type.isEmpty ? '-' : _type)),
                      const SizedBox(width: 10),
                      Expanded(child: _ReadOnlyField(label: 'Status', value: _status.isEmpty ? '-' : _status)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _InfoCard(
              title: 'Editable simple info',
              subtitle: 'Only non-critical info is editable here.',
              child: Column(
                children: [
                  TextFormField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(labelText: 'Display Name / PIC'),
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
                    controller: _companyCtrl,
                    decoration: const InputDecoration(labelText: 'Company Name'),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _ownerCtrl,
                    decoration: const InputDecoration(labelText: 'Owner / Contact Person'),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save_outlined),
                      label: Text(_saving ? 'Saving...' : 'Save Changes'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.title, required this.child, this.subtitle});

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Colors.grey.shade50,
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(subtitle!, style: TextStyle(color: Colors.grey.shade700)),
          ],
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _ReadOnlyField extends StatelessWidget {
  const _ReadOnlyField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      initialValue: value,
      readOnly: true,
      decoration: InputDecoration(labelText: label),
    );
  }
}
