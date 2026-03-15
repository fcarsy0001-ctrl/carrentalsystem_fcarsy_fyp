import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/fleet_admin_service.dart';
import 'widgets/admin_ui.dart';

class VendorCostAdminPage extends StatelessWidget {
  const VendorCostAdminPage({super.key, this.embedded = false, this.showHeader = true});

  final bool embedded;
  final bool showHeader;

  @override
  Widget build(BuildContext context) {
    final tabs = [
      Tab(icon: Icon(Icons.storefront_outlined), text: 'Vendors'),
      Tab(icon: Icon(Icons.payments_outlined), text: 'Service Cost'),
    ];

    final views = [
      _VendorTab(),
      _ServiceCostTab(),
    ];

    if (embedded) {
      return DefaultTabController(
        length: tabs.length,
        child: Column(
          children: [
            if (showHeader)
              const AdminModuleHeader(
                icon: Icons.inventory_2_outlined,
                title: 'Vendors & Cost',
                subtitle: 'Manage service providers and track maintenance spending in one place.',
              ),
            TabBar(
              tabs: tabs,
            ),
            const Divider(height: 1),
            Expanded(
              child: TabBarView(children: views),
            ),
          ],
        ),
      );
    }

    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Vendors & Cost'),
          bottom: TabBar(tabs: tabs),
        ),
        body: TabBarView(children: views),
      ),
    );
  }
}

class _VendorTab extends StatefulWidget {
  const _VendorTab();

  @override
  State<_VendorTab> createState() => _VendorTabState();
}

class _VendorTabState extends State<_VendorTab> {
  SupabaseClient get _supa => Supabase.instance.client;

  late final FleetAdminService _service;
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _service = FleetAdminService(_supa);
    _future = _service.fetchVendors();
  }

  Future<void> _refresh() async {
    setState(() { _future = _service.fetchVendors(); });
    await _future;
  }

  Future<void> _openUpsert({Map<String, dynamic>? initial}) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _VendorFormPage(service: _service, initial: initial),
      ),
    );
    if (saved == true) {
      await _refresh();
    }
  }

  Future<void> _delete(String vendorId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete vendor'),
        content: Text('Delete vendor $vendorId?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await _service.deleteVendor(vendorId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vendor deleted')),
      );
      await _refresh();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_service.explainError(error)), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return const _VendorSqlHint();
        }

        final rows = snapshot.data ?? const [];
        final managedRows = rows.where((vendor) {
          final status = (vendor['vendor_status'] ?? '').toString().trim().toLowerCase();
          return status != 'pending' && status != 'rejected';
        }).toList();
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
              child: Row(
                children: [
                  FilledButton.icon(
                    onPressed: () => _openUpsert(),
                    icon: const Icon(Icons.add),
                    label: const Text('Add vendor'),
                  ),
                  const SizedBox(width: 10),
                  IconButton(
                    tooltip: 'Refresh',
                    onPressed: _refresh,
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refresh,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                  children: [
                    if (managedRows.isEmpty)
                      const _VendorEmptyCard(message: 'No active vendors yet. Approve vendor applications first, then manage them here.')
                    else
                      ...managedRows.map((vendor) {
                        final vendorId = (vendor['vendor_id'] ?? '').toString();
                        final rating = vendor['vendor_rating'] == null ? '0.0' : vendor['vendor_rating'].toString();
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: AdminCard(
                            child: InkWell(
                              onTap: () => _openUpsert(initial: vendor),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            (vendor['vendor_name'] ?? 'Vendor').toString(),
                                            style: const TextStyle(fontWeight: FontWeight.w800),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.end,
                                          children: [
                                            AdminStatusChip(status: (vendor['vendor_status'] ?? '-').toString()),
                                            PopupMenuButton<String>(
                                              onSelected: (value) {
                                                if (value == 'edit') _openUpsert(initial: vendor);
                                                if (value == 'delete') _delete(vendorId);
                                              },
                                              itemBuilder: (_) => const [
                                                PopupMenuItem(value: 'edit', child: Text('Edit')),
                                                PopupMenuItem(value: 'delete', child: Text('Delete')),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text('ID: $vendorId'),
                                    const SizedBox(height: 2),
                                    Text('Category: ${(vendor['service_category'] ?? '-').toString()}'),
                                    const SizedBox(height: 2),
                                    Text('Contact: ${(vendor['contact_person'] ?? '-').toString()}'),
                                    const SizedBox(height: 2),
                                    Text('Phone: ${(vendor['vendor_phone'] ?? '-').toString()}'),
                                    const SizedBox(height: 2),
                                    Text('Rating: $rating'),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ServiceCostTab extends StatefulWidget {
  const _ServiceCostTab();

  @override
  State<_ServiceCostTab> createState() => _ServiceCostTabState();
}

class _ServiceCostTabState extends State<_ServiceCostTab> {
  SupabaseClient get _supa => Supabase.instance.client;

  late final FleetAdminService _service;
  late Future<_ServiceCostBundle> _future;

  @override
  void initState() {
    super.initState();
    _service = FleetAdminService(_supa);
    _future = _load();
  }

  Future<_ServiceCostBundle> _load() async {
    final costs = await _service.fetchServiceCosts();
    List<Map<String, dynamic>> jobs = const [];
    List<Map<String, dynamic>> vendors = const [];
    try {
      jobs = await _service.fetchJobOrders();
    } catch (_) {}
    try {
      vendors = await _service.fetchVendors();
    } catch (_) {}
    return _ServiceCostBundle(costs: costs, jobs: jobs, vendors: vendors);
  }

  Future<void> _refresh() async {
    setState(() { _future = _load(); });
    await _future;
  }

  Future<void> _openUpsert(_ServiceCostBundle bundle, {Map<String, dynamic>? initial}) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _ServiceCostFormPage(
          service: _service,
          jobOrders: bundle.jobs,
          vendors: bundle.vendors,
          initial: initial,
        ),
      ),
    );
    if (saved == true) {
      await _refresh();
    }
  }

  Future<void> _delete(String serviceCostId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete service cost'),
        content: Text('Delete service cost $serviceCostId?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await _service.deleteServiceCost(serviceCostId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Service cost deleted')),
      );
      await _refresh();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_service.explainError(error)), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_ServiceCostBundle>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return const _VendorSqlHint();
        }

        final bundle = snapshot.data;
        if (bundle == null) {
          return const Center(child: Text('No data'));
        }

        final jobMap = _service.indexBy(bundle.jobs, 'job_order_id');
        final vendorMap = _service.indexBy(bundle.vendors, 'vendor_id');

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
              child: Row(
                children: [
                  FilledButton.icon(
                    onPressed: bundle.jobs.isEmpty ? null : () => _openUpsert(bundle),
                    icon: const Icon(Icons.add),
                    label: const Text('Add cost'),
                  ),
                  const SizedBox(width: 10),
                  IconButton(
                    tooltip: 'Refresh',
                    onPressed: _refresh,
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refresh,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                  children: [
                    if (bundle.jobs.isEmpty)
                      const _VendorEmptyCard(
                        message: 'Create at least one job order before recording service costs.',
                      )
                    else if (bundle.costs.isEmpty)
                      const _VendorEmptyCard(
                        message: 'No service costs yet. Add the labour, parts, and tax details for completed job orders here.',
                      )
                    else
                      ...bundle.costs.map((cost) {
                        final costId = (cost['service_cost_id'] ?? '').toString();
                        final job = jobMap[(cost['job_order_id'] ?? '').toString()];
                        final vendor = vendorMap[(cost['vendor_id'] ?? '').toString()];
                        final total = _money(cost['total_cost']);
                        final labour = _money(cost['labour_cost']);
                        final parts = _money(cost['parts_cost']);
                        final misc = _money(cost['misc_cost']);
                        final tax = _money(cost['tax_cost']);
                        final invoiceRef = (cost['invoice_ref'] ?? '').toString().trim();
                        final notes = (cost['notes'] ?? '').toString().trim();

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: AdminCard(
                            child: InkWell(
                              onTap: () => _openUpsert(bundle, initial: cost),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            'Cost Record $costId',
                                            style: const TextStyle(fontWeight: FontWeight.w800),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.end,
                                          children: [
                                            AdminStatusChip(status: (cost['payment_status'] ?? '-').toString()),
                                            PopupMenuButton<String>(
                                              onSelected: (value) {
                                                if (value == 'edit') _openUpsert(bundle, initial: cost);
                                                if (value == 'delete') _delete(costId);
                                              },
                                              itemBuilder: (_) => const [
                                                PopupMenuItem(value: 'edit', child: Text('Edit')),
                                                PopupMenuItem(value: 'delete', child: Text('Delete')),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text('Job Order: ${(job?['job_order_id'] ?? cost['job_order_id'] ?? '-').toString()}'),
                                    const SizedBox(height: 2),
                                    Text('Vendor: ${_service.vendorLabel(vendor)}'),
                                    const SizedBox(height: 2),
                                    Text('Service Date: ${_tabDateText(cost['service_date'])}'),
                                    const SizedBox(height: 8),
                                    Text('Labour: $labour'),
                                    const SizedBox(height: 2),
                                    Text('Parts: $parts'),
                                    const SizedBox(height: 2),
                                    Text('Misc: $misc'),
                                    const SizedBox(height: 2),
                                    Text('Tax: $tax'),
                                    const SizedBox(height: 2),
                                    Text('Invoice: ${invoiceRef.isEmpty ? '-' : invoiceRef}'),
                                    if (notes.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text('Notes: $notes'),
                                    ],
                                    const SizedBox(height: 4),
                                    Text(
                                      'Total: $total',
                                      style: const TextStyle(fontWeight: FontWeight.w700),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ServiceCostBundle {
  const _ServiceCostBundle({
    required this.costs,
    required this.jobs,
    required this.vendors,
  });

  final List<Map<String, dynamic>> costs;
  final List<Map<String, dynamic>> jobs;
  final List<Map<String, dynamic>> vendors;
}

class _VendorFormPage extends StatefulWidget {
  const _VendorFormPage({required this.service, this.initial});

  final FleetAdminService service;
  final Map<String, dynamic>? initial;

  @override
  State<_VendorFormPage> createState() => _VendorFormPageState();
}

class _VendorFormPageState extends State<_VendorFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _categoryController = TextEditingController();
  final _contactController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _addressController = TextEditingController();
  final _pricingController = TextEditingController();
  final _ratingController = TextEditingController(text: '0');

  bool _saving = false;
  String _status = 'Active';

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial != null) {
      _nameController.text = (initial['vendor_name'] ?? '').toString();
      _categoryController.text = (initial['service_category'] ?? '').toString();
      _contactController.text = (initial['contact_person'] ?? '').toString();
      _phoneController.text = (initial['vendor_phone'] ?? '').toString();
      _emailController.text = (initial['vendor_email'] ?? '').toString();
      _addressController.text = (initial['vendor_address'] ?? '').toString();
      _pricingController.text = (initial['pricing_structure'] ?? '').toString();
      _ratingController.text = (initial['vendor_rating'] ?? 0).toString();
      _status = (initial['vendor_status'] ?? 'Active').toString();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _categoryController.dispose();
    _contactController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    _pricingController.dispose();
    _ratingController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    try {
      final service = widget.service as dynamic;
      await service.upsertVendor(
        vendorId: widget.initial?['vendor_id']?.toString(),
        vendorName: _nameController.text,
        serviceCategory: _categoryController.text,
        contactPerson: _contactController.text,
        phone: _phoneController.text,
        email: _emailController.text,
        address: _addressController.text,
        pricingStructure: _pricingController.text,
        rating: double.tryParse(_ratingController.text.trim()) ?? 0,
        status: _status,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.initial == null ? 'Vendor created' : 'Vendor updated')),
      );
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.service.explainError(error)), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.initial == null ? 'Add Vendor' : 'Edit Vendor')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Vendor Name'),
              validator: (value) => (value == null || value.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _categoryController,
              decoration: const InputDecoration(labelText: 'Service Category'),
              validator: (value) => (value == null || value.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _contactController,
              decoration: const InputDecoration(labelText: 'Contact Person'),
              validator: (value) => (value == null || value.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _phoneController,
              decoration: const InputDecoration(labelText: 'Phone'),
              validator: (value) => (value == null || value.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _emailController,
              decoration: const InputDecoration(labelText: 'Email'),
              validator: (value) {
                if (value == null || value.trim().isEmpty) return 'Required';
                if (!value.contains('@')) return 'Enter a valid email';
                return null;
              },
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _addressController,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Address'),
              validator: (value) => (value == null || value.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _pricingController,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Pricing Structure'),
              validator: (value) => (value == null || value.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _ratingController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Rating'),
              validator: (value) {
                if (value == null || value.trim().isEmpty) return 'Required';
                if (double.tryParse(value.trim()) == null) return 'Enter a valid number';
                return null;
              },
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: _status,
              decoration: const InputDecoration(labelText: 'Status'),
              items: const [
                DropdownMenuItem(value: 'Active', child: Text('Active')),
                DropdownMenuItem(value: 'Inactive', child: Text('Inactive')),
              ],
              onChanged: (value) => setState(() => _status = value ?? 'Active'),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.save_outlined),
              label: Text(widget.initial == null ? 'Create vendor' : 'Save changes'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ServiceCostFormPage extends StatefulWidget {
  const _ServiceCostFormPage({
    required this.service,
    required this.jobOrders,
    required this.vendors,
    this.initial,
  });

  final FleetAdminService service;
  final List<Map<String, dynamic>> jobOrders;
  final List<Map<String, dynamic>> vendors;
  final Map<String, dynamic>? initial;

  @override
  State<_ServiceCostFormPage> createState() => _ServiceCostFormPageState();
}

class _ServiceCostFormPageState extends State<_ServiceCostFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _labourController = TextEditingController(text: '0');
  final _partsController = TextEditingController(text: '0');
  final _miscController = TextEditingController(text: '0');
  final _taxController = TextEditingController(text: '0');
  final _invoiceController = TextEditingController();
  final _notesController = TextEditingController();

  bool _saving = false;
  DateTime? _serviceDate;
  String? _jobOrderId;
  String? _vendorId;
  String _paymentStatus = 'Pending';

  @override
  void initState() {
    super.initState();
    if (widget.jobOrders.isNotEmpty) {
      _jobOrderId = widget.jobOrders.first['job_order_id']?.toString();
    }
    final initial = widget.initial;
    if (initial != null) {
      final jobOrderId = initial['job_order_id']?.toString();
      final vendorId = initial['vendor_id']?.toString();
      _jobOrderId = widget.jobOrders.any((row) => row['job_order_id'].toString() == jobOrderId)
          ? jobOrderId
          : _jobOrderId;
      _vendorId = widget.vendors.any((row) => row['vendor_id'].toString() == vendorId)
          ? vendorId
          : null;
      _labourController.text = (initial['labour_cost'] ?? 0).toString();
      _partsController.text = (initial['parts_cost'] ?? 0).toString();
      _miscController.text = (initial['misc_cost'] ?? 0).toString();
      _taxController.text = (initial['tax_cost'] ?? 0).toString();
      _invoiceController.text = (initial['invoice_ref'] ?? '').toString();
      _notesController.text = (initial['notes'] ?? '').toString();
      _paymentStatus = (initial['payment_status'] ?? 'Pending').toString();
      _serviceDate = _tabParseDate(initial['service_date']);
    }
  }

  @override
  void dispose() {
    _labourController.dispose();
    _partsController.dispose();
    _miscController.dispose();
    _taxController.dispose();
    _invoiceController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickServiceDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _serviceDate ?? DateTime.now(),
      firstDate: DateTime(2024, 1, 1),
      lastDate: DateTime(2035, 12, 31),
    );
    if (picked == null) return;
    setState(() => _serviceDate = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if ((_jobOrderId ?? '').trim().isEmpty) return;

    setState(() => _saving = true);
    try {
      await widget.service.upsertServiceCost(
        serviceCostId: widget.initial?['service_cost_id']?.toString(),
        jobOrderId: _jobOrderId!,
        vendorId: _vendorId,
        labourCost: double.tryParse(_labourController.text.trim()) ?? 0,
        partsCost: double.tryParse(_partsController.text.trim()) ?? 0,
        miscCost: double.tryParse(_miscController.text.trim()) ?? 0,
        taxCost: double.tryParse(_taxController.text.trim()) ?? 0,
        invoiceRef: _invoiceController.text,
        paymentStatus: _paymentStatus,
        serviceDate: _serviceDate,
        notes: _notesController.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.initial == null ? 'Service cost created' : 'Service cost updated')),
      );
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.service.explainError(error)), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.initial == null ? 'Add Service Cost' : 'Edit Service Cost')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            DropdownButtonFormField<String>(
              value: widget.jobOrders.any((row) => row['job_order_id'].toString() == _jobOrderId) ? _jobOrderId : null,
              decoration: const InputDecoration(labelText: 'Job Order'),
              items: widget.jobOrders
                  .map(
                    (job) => DropdownMenuItem<String>(
                  value: job['job_order_id'].toString(),
                  child: Text('${(job['job_order_id'] ?? '').toString()} - ${(job['job_type'] ?? '').toString()}'),
                ),
              )
                  .toList(),
              onChanged: (value) => setState(() => _jobOrderId = value),
              validator: (value) => (value == null || value.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String?>(
              value: widget.vendors.any((row) => row['vendor_id'].toString() == _vendorId) ? _vendorId : null,
              decoration: const InputDecoration(labelText: 'Vendor (optional)'),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('Unassigned')),
                ...widget.vendors.map(
                      (vendor) => DropdownMenuItem<String?>(
                    value: vendor['vendor_id'].toString(),
                    child: Text(widget.service.vendorLabel(vendor)),
                  ),
                ),
              ],
              onChanged: (value) => setState(() => _vendorId = value),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _labourController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Labour Cost'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: _partsController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Parts Cost'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _miscController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Misc Cost'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: _taxController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Tax Cost'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Service Date'),
              subtitle: Text(_tabDateText(_serviceDate)),
              trailing: Wrap(
                spacing: 8,
                children: [
                  if (_serviceDate != null)
                    IconButton(
                      onPressed: () => setState(() => _serviceDate = null),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  OutlinedButton(
                    onPressed: _pickServiceDate,
                    child: const Text('Pick date'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _invoiceController,
              decoration: const InputDecoration(labelText: 'Invoice Reference'),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: _paymentStatus,
              decoration: const InputDecoration(labelText: 'Payment Status'),
              items: const [
                DropdownMenuItem(value: 'Pending', child: Text('Pending')),
                DropdownMenuItem(value: 'Paid', child: Text('Paid')),
                DropdownMenuItem(value: 'Disputed', child: Text('Disputed')),
              ],
              onChanged: (value) => setState(() => _paymentStatus = value ?? 'Pending'),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _notesController,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Notes'),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.save_outlined),
              label: Text(widget.initial == null ? 'Add service cost' : 'Save changes'),
            ),
          ],
        ),
      ),
    );
  }
}

class _VendorSqlHint extends StatelessWidget {
  const _VendorSqlHint();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Vendor / cost tables need setup',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        const Text('Paste the admin SQL into Supabase SQL Editor, then refresh this module.'),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: Colors.black.withOpacity(0.05),
          ),
          child: SelectableText(FleetAdminService.sqlSetup),
        ),
      ],
    );
  }
}

class _VendorEmptyCard extends StatelessWidget {
  const _VendorEmptyCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return AdminCard(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Text(message),
      ),
    );
  }
}

String _money(dynamic value) {
  final number = value is num ? value.toDouble() : double.tryParse(value.toString()) ?? 0;
  return 'RM ${number.toStringAsFixed(2)}';
}

DateTime? _tabParseDate(dynamic raw) {
  if (raw == null) return null;
  if (raw is DateTime) return raw;
  return DateTime.tryParse(raw.toString());
}

String _tabDateText(dynamic raw) {
  final value = _tabParseDate(raw);
  if (value == null) return '-';
  return '${value.day}/${value.month}/${value.year}';
}



















