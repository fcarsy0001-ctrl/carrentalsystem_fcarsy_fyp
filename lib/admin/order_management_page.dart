
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class OrderManagementPage extends StatefulWidget {
  const OrderManagementPage({super.key});

  @override
  State<OrderManagementPage> createState() => _OrderManagementPageState();
}

class _OrderManagementPageState extends State<OrderManagementPage> {
  SupabaseClient get _supa => Supabase.instance.client;

  bool _loading = true;
  String? _error;

  String _statusFilter = 'All';
  final _q = TextEditingController();

  List<Map<String, dynamic>> _rows = const [];

  @override
  void initState() {
    super.initState();
    _load();
    _q.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // Load recent orders first (you can increase if needed)
      final rows = await _supa
          .from('booking')
          .select('booking_id,booking_date,rental_start,rental_end,booking_status,total_rental_amount,user_id,vehicle_id,payment_option')
          .order('booking_date', ascending: false)
          .limit(1000);

      final list = (rows as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      setState(() => _rows = list);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _filtered {
    final q = _q.text.trim().toLowerCase();
    return _rows.where((r) {
      final st = (r['booking_status'] ?? '').toString().trim();
      if (_statusFilter != 'All') {
        final low = st.toLowerCase();
        final f = _statusFilter.toLowerCase();
        if (f == 'cancelled') {
          if (!low.contains('cancel')) return false;
        } else if (f == 'deactive') {
          if (!(low.contains('deactiv') || low.contains('deactive'))) return false;
        } else if (f == 'inactive') {
          if (!low.contains('inactive')) return false;
        } else if (f == 'active') {
          if (!low.contains('active')) return false;
        } else {
          if (low != f) return false;
        }
      }
      if (q.isEmpty) return true;
      final id = (r['booking_id'] ?? '').toString().toLowerCase();
      final uid = (r['user_id'] ?? '').toString().toLowerCase();
      final vid = (r['vehicle_id'] ?? '').toString().toLowerCase();
      return id.contains(q) || uid.contains(q) || vid.contains(q);
    }).toList();
  }

  String _money(dynamic v) {
    final n = v is num ? v.toDouble() : double.tryParse(v.toString()) ?? 0;
    return 'RM ${n.toStringAsFixed(2)}';
  }

  _StatusMeta _meta(String? status) {
    final raw = (status ?? '').toString().trim();
    final low = raw.toLowerCase();
    if (low.contains('deactiv') || low.contains('deactive')) {
      return const _StatusMeta(label: 'Deactive', color: Colors.red);
    }
    if (low.contains('inactive') || low.contains('complete')) {
      return const _StatusMeta(label: 'Inactive', color: Colors.grey);
    }
    if (low.contains('cancel')) {
      return const _StatusMeta(label: 'Cancelled', color: Colors.grey);
    }
    if (low.contains('paid')) {
      return const _StatusMeta(label: 'Paid', color: Colors.green);
    }
    if (low.contains('hold')) {
      return const _StatusMeta(label: 'Holding', color: Colors.orange);
    }
    if (low.contains('active')) {
      return const _StatusMeta(label: 'Active', color: Colors.green);
    }
    return _StatusMeta(label: raw.isEmpty ? '-' : raw, color: Colors.blueGrey);
  }

  Future<void> _deactivate(Map<String, dynamic> row) async {
    final bookingId = (row['booking_id'] ?? '').toString().trim();
    if (bookingId.isEmpty) return;

    final reasonCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Deactivate Order'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Booking: $bookingId'),
            const SizedBox(height: 10),
            TextField(
              controller: reasonCtrl,
              decoration: const InputDecoration(
                labelText: 'Reason (optional)',
                hintText: 'User issue / fraud / dispute ...',
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Deactivate')),
        ],
      ),
    );

    if (ok != true) return;

    final before = (row['booking_status'] ?? '').toString();

    try {
      await _supa.from('booking').update({'booking_status': 'Deactive'}).eq('booking_id', bookingId);

      // Best-effort: write rental history (only if current user has app_user row)
      try {
        final auth = _supa.auth.currentUser;
        if (auth != null) {
          final u = await _supa.from('app_user').select('user_id').eq('auth_uid', auth.id).maybeSingle();
          final changerId = (u?['user_id'] ?? '').toString().trim();
          if (changerId.isNotEmpty) {
            await _supa.from('rental_history').insert({
              'rental_history_id': 'HIS-${DateTime.now().millisecondsSinceEpoch}',
              'booking_id': bookingId,
              'changed_by_user_id': changerId,
              'status_before': before.isEmpty ? '-' : before,
              'status_after': 'Deactive',
              'history_remark': reasonCtrl.text.trim().isEmpty ? null : reasonCtrl.text.trim(),
            });
          }
        }
      } catch (_) {}

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Order deactivated')));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  Future<void> _openDetail(Map<String, dynamic> row) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => _OrderDetailAdminPage(row: row)),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Order Management'),
        centerTitle: true,
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _q,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Search booking / user / vehicle id',
                    ),
                  ),
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final f in const ['All', 'Paid', 'Active', 'Inactive', 'Deactive', 'Cancelled'])
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(f),
                              selected: _statusFilter.toLowerCase() == f.toLowerCase(),
                              onSelected: (_) => setState(() => _statusFilter = f),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(child: Padding(padding: const EdgeInsets.all(16), child: Text(_error!)))
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                            itemCount: _filtered.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 10),
                            itemBuilder: (context, i) {
                              final r = _filtered[i];
                              final st = (r['booking_status'] ?? '').toString();
                              final meta = _meta(st);
                              return _OrderCardAdmin(
                                row: r,
                                amountText: _money(r['total_rental_amount']),
                                status: meta,
                                onView: () => _openDetail(r),
                                onDeactivate: (meta.label.toLowerCase() == 'deactive' || meta.label.toLowerCase() == 'cancelled')
                                    ? null
                                    : () => _deactivate(r),
                              );
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusMeta {
  const _StatusMeta({required this.label, required this.color});
  final String label;
  final Color color;
}

class _OrderCardAdmin extends StatelessWidget {
  const _OrderCardAdmin({
    required this.row,
    required this.amountText,
    required this.status,
    required this.onView,
    required this.onDeactivate,
  });

  final Map<String, dynamic> row;
  final String amountText;
  final _StatusMeta status;
  final VoidCallback onView;
  final VoidCallback? onDeactivate;

  String _s(String k) => (row[k] ?? '').toString();

  @override
  Widget build(BuildContext context) {
    final id = _s('booking_id');
    final uid = _s('user_id');
    final vid = _s('vehicle_id');
    final dt = _s('booking_date');

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onView,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      id.isEmpty ? '-' : id,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: status.color.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: status.color.withOpacity(0.35)),
                    ),
                    child: Text(
                      status.label,
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: status.color),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text('User: ${uid.isEmpty ? '-' : uid}', style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
              Text('Vehicle: ${vid.isEmpty ? '-' : vid}', style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Booking Date: ${dt.isEmpty ? '-' : dt}',
                      style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(amountText, style: const TextStyle(fontWeight: FontWeight.w900)),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onView,
                      icon: const Icon(Icons.visibility_outlined, size: 18),
                      label: const Text('View'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: onDeactivate,
                      icon: const Icon(Icons.block_outlined, size: 18),
                      label: const Text('Deactivate'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OrderDetailAdminPage extends StatefulWidget {
  const _OrderDetailAdminPage({required this.row});

  final Map<String, dynamic> row;

  @override
  State<_OrderDetailAdminPage> createState() => _OrderDetailAdminPageState();
}

class _OrderDetailAdminPageState extends State<_OrderDetailAdminPage> {
  SupabaseClient get _supa => Supabase.instance.client;

  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _detail;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _money(dynamic v) {
    final n = v is num ? v.toDouble() : double.tryParse(v.toString()) ?? 0;
    return 'RM ${n.toStringAsFixed(2)}';
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _detail = null;
    });

    final bookingId = (widget.row['booking_id'] ?? '').toString().trim();
    try {
      final r = await _supa
          .from('booking')
          .select(
            'booking_id,booking_date,rental_start,rental_end,booking_status,payment_option,total_rental_amount,dropoff_location,voucher_code,voucher_discount,user_id,vehicle_id,app_user:user_id(user_name,user_email,user_phone),vehicle:vehicle_id(vehicle_brand,vehicle_model,vehicle_plate_no,vehicle_location,leaser_id)',
          )
          .eq('booking_id', bookingId)
          .maybeSingle();

      setState(() => _detail = r == null ? null : Map<String, dynamic>.from(r));
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bookingId = (widget.row['booking_id'] ?? '').toString();

    return Scaffold(
      appBar: AppBar(title: Text('Order $bookingId')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(16), child: Text(_error!)))
              : _detail == null
                  ? const Center(child: Text('Not found'))
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        _KV('Status', (_detail!['booking_status'] ?? '').toString()),
                        _KV('Amount', _money(_detail!['total_rental_amount'])),
                        _KV('Booking Date', (_detail!['booking_date'] ?? '').toString()),
                        _KV('Rental Start', (_detail!['rental_start'] ?? '').toString()),
                        _KV('Rental End', (_detail!['rental_end'] ?? '').toString()),
                        _KV('Payment Option', (_detail!['payment_option'] ?? '').toString()),
                        _KV('Voucher Code', (_detail!['voucher_code'] ?? '-').toString()),
                        _KV('Voucher Discount', _money(_detail!['voucher_discount'] ?? 0)),
                        _KV('Dropoff Location', (_detail!['dropoff_location'] ?? '-').toString()),
                        const Divider(height: 26),

                        const Text('User', style: TextStyle(fontWeight: FontWeight.w900)),
                        const SizedBox(height: 6),
                        _KV('User ID', (_detail!['user_id'] ?? '').toString()),
                        _KV('Name', (((_detail!['app_user'] ?? const {}) as Map)['user_name'] ?? '-').toString()),
                        _KV('Email', (((_detail!['app_user'] ?? const {}) as Map)['user_email'] ?? '-').toString()),
                        _KV('Phone', (((_detail!['app_user'] ?? const {}) as Map)['user_phone'] ?? '-').toString()),

                        const Divider(height: 26),

                        const Text('Vehicle', style: TextStyle(fontWeight: FontWeight.w900)),
                        const SizedBox(height: 6),
                        _KV('Vehicle ID', (_detail!['vehicle_id'] ?? '').toString()),
                        _KV('Car', '${((_detail!['vehicle'] ?? const {}) as Map)['vehicle_brand'] ?? ''} '
                            '${((_detail!['vehicle'] ?? const {}) as Map)['vehicle_model'] ?? ''}'.trim()),
                        _KV('Plate', (((_detail!['vehicle'] ?? const {}) as Map)['vehicle_plate_no'] ?? '-').toString()),
                        _KV('Leaser ID', (((_detail!['vehicle'] ?? const {}) as Map)['leaser_id'] ?? '-').toString()),
                        _KV('Location', (((_detail!['vehicle'] ?? const {}) as Map)['vehicle_location'] ?? '-').toString()),
                      ],
                    ),
    );
  }
}

class _KV extends StatelessWidget {
  const _KV(this.k, this.v);

  final String k;
  final String v;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 130, child: Text(k, style: TextStyle(color: Colors.grey.shade700))),
          Expanded(child: Text(v.isEmpty ? '-' : v, style: const TextStyle(fontWeight: FontWeight.w700))),
        ],
      ),
    );
  }
}
