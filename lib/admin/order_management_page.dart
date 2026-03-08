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
      // Load recent orders (increase if needed)
      final rows = await _supa
          .from('booking')
          .select(
            'booking_id,booking_date,rental_start,rental_end,booking_status,total_rental_amount,user_id,vehicle_id,payment_option,app_user:user_id(user_email)',
          )
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
      if (_statusFilter != 'All' && st.toLowerCase() != _statusFilter.toLowerCase()) {
        return false;
      }
      if (q.isEmpty) return true;
      final id = (r['booking_id'] ?? '').toString().toLowerCase();
      final uid = (r['user_id'] ?? '').toString().toLowerCase();
      final vid = (r['vehicle_id'] ?? '').toString().toLowerCase();
      final au = r['app_user'];
      final email = (au is Map ? (au['user_email'] ?? '').toString() : '').toLowerCase();
      return id.contains(q) || uid.contains(q) || vid.contains(q) || email.contains(q);
    }).toList();
  }

  DateTime? _dt(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    return DateTime.tryParse(v.toString());
  }

  /// Group orders by user to avoid too much order list.
  List<_UserOrderGroup> get _userGroups {
    final byUser = <String, List<Map<String, dynamic>>>{};
    final emailByUser = <String, String>{};

    for (final r in _filtered) {
      final uid = (r['user_id'] ?? '').toString();
      if (uid.isEmpty) continue;
      (byUser[uid] ??= <Map<String, dynamic>>[]).add(r);

      final au = r['app_user'];
      if (au is Map) {
        final email = (au['user_email'] ?? '').toString();
        if (email.isNotEmpty) emailByUser[uid] = email;
      }
    }

    final groups = byUser.entries.map((e) {
      final uid = e.key;
      final orders = e.value;

      DateTime? latest;
      for (final o in orders) {
        final d = _dt(o['booking_date']);
        if (d != null && (latest == null || d.isAfter(latest))) latest = d;
      }

      return _UserOrderGroup(
        userId: uid,
        userEmail: emailByUser[uid] ?? '',
        orderCount: orders.length,
        latestBookingDate: latest,
      );
    }).toList();

    groups.sort((a, b) {
      final ad = a.latestBookingDate;
      final bd = b.latestBookingDate;
      if (ad == null && bd == null) return a.userId.compareTo(b.userId);
      if (ad == null) return 1;
      if (bd == null) return -1;
      return bd.compareTo(ad);
    });

    return groups;
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
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _q,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Search booking/user/vehicle/email',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                DropdownButton<String>(
                  value: _statusFilter,
                  items: const [
                    DropdownMenuItem(value: 'All', child: Text('All')),
                    DropdownMenuItem(value: 'Paid', child: Text('Paid')),
                    DropdownMenuItem(value: 'Active', child: Text('Active')),
                    DropdownMenuItem(value: 'Inactive', child: Text('Inactive')),
                    DropdownMenuItem(value: 'Deactive', child: Text('Deactive')),
                    DropdownMenuItem(value: 'Cancelled', child: Text('Cancelled')),
                  ],
                  onChanged: (v) => setState(() => _statusFilter = v ?? 'All'),
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
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                          itemCount: _userGroups.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, i) {
                            final g = _userGroups[i];
                            final uid = g.userId;
                            final email = g.userEmail.trim().isEmpty ? '-' : g.userEmail.trim();

                            return Card(
                              child: ListTile(
                                onTap: () async {
                                  await Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => _UserOrdersPage(
                                        userId: uid,
                                        userEmail: g.userEmail,
                                      ),
                                    ),
                                  );
                                  await _load();
                                },
                                title: Text('User: $uid', style: const TextStyle(fontWeight: FontWeight.w900)),
                                subtitle: Text('Email: $email\nOrders: ${g.orderCount}'),
                                isThreeLine: true,
                                trailing: const Icon(Icons.chevron_right),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

class _UserOrderGroup {
  _UserOrderGroup({
    required this.userId,
    required this.userEmail,
    required this.orderCount,
    required this.latestBookingDate,
  });

  final String userId;
  final String userEmail;
  final int orderCount;
  final DateTime? latestBookingDate;
}

class _UserOrdersPage extends StatefulWidget {
  const _UserOrdersPage({required this.userId, required this.userEmail});

  final String userId;
  final String userEmail;

  @override
  State<_UserOrdersPage> createState() => _UserOrdersPageState();
}

class _UserOrdersPageState extends State<_UserOrdersPage> {
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
      final rows = await _supa
          .from('booking')
          .select(
            'booking_id,booking_date,rental_start,rental_end,booking_status,total_rental_amount,user_id,vehicle_id,payment_option',
          )
          .eq('user_id', widget.userId)
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
      if (_statusFilter != 'All' && st.toLowerCase() != _statusFilter.toLowerCase()) {
        return false;
      }
      if (q.isEmpty) return true;
      final id = (r['booking_id'] ?? '').toString().toLowerCase();
      final vid = (r['vehicle_id'] ?? '').toString().toLowerCase();
      return id.contains(q) || vid.contains(q);
    }).toList();
  }

  String _money(dynamic v) {
    final n = v is num ? v.toDouble() : double.tryParse(v.toString()) ?? 0;
    return 'RM ${n.toStringAsFixed(2)}';
  }

  String _normStatus(String status) {
    final s = status.trim().toLowerCase();
    if (s == 'cancel' || s == 'cancelled' || s == 'canceled') return 'cancelled';
    if (s == 'deactive' || s == 'deactivated') return 'deactive';
    return s;
  }

  String _statusLabel(String status) {
    final s = _normStatus(status);
    if (s == 'cancelled') return 'Cancelled';
    if (s == 'deactive') return 'Deactive';
    if (s == 'active') return 'Active';
    if (s == 'inactive') return 'Inactive';
    return status.trim().isEmpty ? '-' : status;
  }

  Color _statusColor(String status) {
    final s = _normStatus(status);
    if (s == 'cancelled' || s == 'deactive') return Colors.red;
    if (s == 'active') return Colors.green;
    if (s == 'inactive') return Colors.grey;
    return Colors.blueGrey;
  }

  Future<void> _setStatus({
    required String bookingId,
    required String after,
  }) async {
    // Update booking only.
    // If your DB writes `rental_history` via trigger, fix `rental_history` RLS (see SQL below).
    await _supa.from('booking').update({'booking_status': after}).eq('booking_id', bookingId);
  }

  Future<void> _deactivate(Map<String, dynamic> row) async {
    final bookingId = (row['booking_id'] ?? '').toString().trim();
    if (bookingId.isEmpty) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Deactivate Order'),
        content: Text('Deactivate booking: $bookingId ?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Back')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Deactivate')),
        ],
      ),
    );

    if (ok != true) return;

    try {
      await _setStatus(bookingId: bookingId, after: 'Deactive');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Order deactivated')));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  Future<void> _activate(Map<String, dynamic> row) async {
    final bookingId = (row['booking_id'] ?? '').toString().trim();
    if (bookingId.isEmpty) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Activate Order'),
        content: Text('Activate booking: $bookingId ?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Back')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Activate')),
        ],
      ),
    );

    if (ok != true) return;

    try {
      await _setStatus(bookingId: bookingId, after: 'Active');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Order activated')));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  Future<void> _cancel(Map<String, dynamic> row) async {
    final bookingId = (row['booking_id'] ?? '').toString().trim();
    if (bookingId.isEmpty) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cancel Order'),
        content: Text('Cancel booking: $bookingId ?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Back')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Cancel Order')),
        ],
      ),
    );

    if (ok != true) return;

    try {
      await _setStatus(bookingId: bookingId, after: 'Cancelled');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Order cancelled')));
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
    final email = widget.userEmail.trim().isEmpty ? '-' : widget.userEmail.trim();

    return Scaffold(
      appBar: AppBar(
        title: Text('Orders - ${widget.userId}'),
        centerTitle: true,
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Email: $email', style: TextStyle(color: Colors.grey.shade700)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _q,
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          hintText: 'Search booking/vehicle id',
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    DropdownButton<String>(
                      value: _statusFilter,
                      items: const [
                        DropdownMenuItem(value: 'All', child: Text('All')),
                        DropdownMenuItem(value: 'Active', child: Text('Active')),
                        DropdownMenuItem(value: 'Inactive', child: Text('Inactive')),
                        DropdownMenuItem(value: 'Deactive', child: Text('Deactive')),
                        DropdownMenuItem(value: 'Cancelled', child: Text('Cancelled')),
                      ],
                      onChanged: (v) => setState(() => _statusFilter = v ?? 'All'),
                    ),
                  ],
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
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                          itemCount: _filtered.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, i) {
                            final r = _filtered[i];
                            final id = (r['booking_id'] ?? '').toString();
                            final st = (r['booking_status'] ?? '').toString();
                            final amt = _money(r['total_rental_amount']);
                            final vid = (r['vehicle_id'] ?? '').toString();

                            final sl = _normStatus(st);
                            final isCancelled = sl == 'cancelled';
                            final isDeactive = sl == 'deactive';

                            return Card(
                              child: ListTile(
                                onTap: () => _openDetail(r),
                                title: Text(id, style: const TextStyle(fontWeight: FontWeight.w900)),
                                subtitle: Text('Vehicle: $vid\nAmount: $amt'),
                                isThreeLine: true,
                                leading: _StatusPill(
                                  label: _statusLabel(st),
                                  color: _statusColor(st),
                                ),
                                trailing: PopupMenuButton<String>(
                                  onSelected: (v) async {
                                    if (v == 'view') {
                                      await _openDetail(r);
                                      return;
                                    }
                                    if (v == 'deactivate') {
                                      await _deactivate(r);
                                      return;
                                    }
                                    if (v == 'activate') {
                                      await _activate(r);
                                      return;
                                    }
                                    if (v == 'cancel') {
                                      await _cancel(r);
                                      return;
                                    }
                                  },
                                  itemBuilder: (_) {
                                    return [
                                      const PopupMenuItem(value: 'view', child: Text('View')),
                                      if (!isCancelled && !isDeactive)
                                        const PopupMenuItem(value: 'deactivate', child: Text('Deactivate')),
                                      if (!isCancelled && isDeactive)
                                        const PopupMenuItem(value: 'activate', child: Text('Activate')),
                                      if (!isCancelled) const PopupMenuItem(value: 'cancel', child: Text('Cancel')),
                                    ];
                                  },
                                ),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.55)),
      ),
      child: Text(
        label,
        style: TextStyle(fontWeight: FontWeight.w900, color: color),
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
                        _KV(
                          'Car',
                          '${((_detail!['vehicle'] ?? const {}) as Map)['vehicle_brand'] ?? ''} '
                              '${((_detail!['vehicle'] ?? const {}) as Map)['vehicle_model'] ?? ''}'.trim(),
                        ),
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
