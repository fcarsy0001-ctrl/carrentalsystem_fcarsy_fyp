
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
  Map<String, Map<String, dynamic>> _usersById = const {};

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
      final bookingRows = await _supa
          .from('booking')
          .select('*')
          .order('booking_date', ascending: false)
          .limit(1000);

      final userRows = await _supa
          .from('app_user')
          .select('user_id,user_email,user_name')
          .limit(5000);

      final list = (bookingRows as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final users = <String, Map<String, dynamic>>{};
      for (final row in (userRows as List)) {
        final map = Map<String, dynamic>.from(row as Map);
        final userId = (map['user_id'] ?? '').toString().trim();
        if (userId.isNotEmpty) users[userId] = map;
      }

      setState(() {
        _rows = list;
        _usersById = users;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  String _userEmail(String userId) => (_usersById[userId]?['user_email'] ?? '').toString().trim();
  String _userName(String userId) => (_usersById[userId]?['user_name'] ?? '').toString().trim();

  List<_UserOrderGroup> get _grouped {
    final q = _q.text.trim().toLowerCase();
    final map = <String, List<Map<String, dynamic>>>{};

    for (final r in _rows) {
      final st = (r['booking_status'] ?? '').toString().trim();
      if (_statusFilter != 'All' && _normStatus(st) != _normStatus(_statusFilter)) {
        continue;
      }

      final bookingId = (r['booking_id'] ?? '').toString().toLowerCase();
      final userId = (r['user_id'] ?? '').toString().trim();
      final vehicleId = (r['vehicle_id'] ?? '').toString().toLowerCase();
      final email = _userEmail(userId).toLowerCase();
      final name = _userName(userId).toLowerCase();

      final match = q.isEmpty ||
          bookingId.contains(q) ||
          userId.toLowerCase().contains(q) ||
          vehicleId.contains(q) ||
          email.contains(q) ||
          name.contains(q);
      if (!match) continue;

      map.putIfAbsent(userId, () => []).add(r);
    }

    final groups = map.entries.map((entry) {
      final userId = entry.key;
      final orders = entry.value;
      var total = 0.0;
      for (final order in orders) {
        final amount = order['total_rental_amount'];
        total += amount is num ? amount.toDouble() : double.tryParse(amount.toString()) ?? 0;
      }
      return _UserOrderGroup(
        userId: userId,
        email: _userEmail(userId),
        name: _userName(userId),
        orders: orders,
        totalAmount: total,
      );
    }).toList();

    groups.sort((a, b) {
      final aDate = a.orders.isEmpty ? '' : (a.orders.first['booking_date'] ?? '').toString();
      final bDate = b.orders.isEmpty ? '' : (b.orders.first['booking_date'] ?? '').toString();
      return bDate.compareTo(aDate);
    });
    return groups;
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
    required String before,
    String? remark,
  }) async {
    try {
      await _supa.from('booking').update({'booking_status': after}).eq('booking_id', bookingId);
    } on PostgrestException catch (e) {
      final msg = e.message.toLowerCase();
      final blockedByNotificationTrigger =
          e.code == '42501' && msg.contains('notification');
      final cancelling = _normStatus(after) == 'cancelled';
      if (!cancelling || !blockedByNotificationTrigger) rethrow;
      await _supa.from('booking').update({'booking_status': 'Cancel'}).eq('booking_id', bookingId);
    }
  }

  Future<void> _deactivate(Map<String, dynamic> row) async {
    final bookingId = (row['booking_id'] ?? '').toString().trim();
    if (bookingId.isEmpty) return;

    final before = (row['booking_status'] ?? '').toString();

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
                hintText: 'User issue / dispute / fraud ...',
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Back')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Deactivate')),
        ],
      ),
    );

    if (ok != true) return;

    try {
      await _setStatus(
        bookingId: bookingId,
        before: before,
        after: 'Deactive',
        remark: reasonCtrl.text,
      );

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

    final before = (row['booking_status'] ?? '').toString();

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
      await _setStatus(
        bookingId: bookingId,
        before: before,
        after: 'Active',
        remark: 'Re-activated by admin/staff',
      );

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

    final before = (row['booking_status'] ?? '').toString();

    final reasonCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cancel Order'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Booking: $bookingId'),
            const SizedBox(height: 10),
            TextField(
              controller: reasonCtrl,
              decoration: const InputDecoration(
                labelText: 'Reason (optional)',
                hintText: 'Duplicate / payment issue / user request ...',
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Back')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Cancel Order')),
        ],
      ),
    );

    if (ok != true) return;

    try {
      await _setStatus(
        bookingId: bookingId,
        before: before,
        after: 'Cancelled',
        remark: reasonCtrl.text.isEmpty ? 'Cancelled by admin/staff' : reasonCtrl.text,
      );

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
    final grouped = _grouped;
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
                      hintText: 'Search user id / email / booking / vehicle',
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
                          itemCount: grouped.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, i) {
                            final group = grouped[i];
                            final email = group.email.isEmpty ? '-' : group.email;
                            final nameText = group.name.isEmpty ? '' : ' • ${group.name}';

                            return Card(
                              child: ExpansionTile(
                                tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                                title: Text(
                                  'User ID: ${group.userId.isEmpty ? '-' : group.userId}',
                                  style: const TextStyle(fontWeight: FontWeight.w900),
                                ),
                                subtitle: Text('Gmail: $email$nameText\nOrders: ${group.orders.length} • Total: ${_money(group.totalAmount)}'),
                                children: group.orders.map((r) {
                                  final id = (r['booking_id'] ?? '').toString();
                                  final st = (r['booking_status'] ?? '').toString();
                                  final amt = _money(r['total_rental_amount']);
                                  final vid = (r['vehicle_id'] ?? '').toString();
                                  final bookingDate = (r['booking_date'] ?? '').toString();
                                  return Container(
                                    margin: const EdgeInsets.only(top: 8),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: Colors.grey.shade300),
                                    ),
                                    child: ListTile(
                                      onTap: () => _openDetail(r),
                                      title: Text(id, style: const TextStyle(fontWeight: FontWeight.w800)),
                                      subtitle: Text('Vehicle: $vid\nAmount: $amt\nDate: $bookingDate'),
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                            decoration: BoxDecoration(
                                              color: _statusColor(st).withOpacity(0.12),
                                              borderRadius: BorderRadius.circular(999),
                                            ),
                                            child: Text(
                                              _statusLabel(st),
                                              style: TextStyle(
                                                color: _statusColor(st),
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ),
                                          PopupMenuButton<String>(
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
                                              final sl = _normStatus(st);
                                              final isCancelled = sl == 'cancelled';
                                              final isDeactive = sl == 'deactive';
                                              return [
                                                const PopupMenuItem(value: 'view', child: Text('View')),
                                                if (!isCancelled && !isDeactive)
                                                  const PopupMenuItem(value: 'deactivate', child: Text('Deactivate')),
                                                if (!isCancelled && isDeactive)
                                                  const PopupMenuItem(value: 'activate', child: Text('Activate')),
                                                if (!isCancelled)
                                                  const PopupMenuItem(value: 'cancel', child: Text('Cancel')),
                                              ];
                                            },
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }).toList(),
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
  const _UserOrderGroup({
    required this.userId,
    required this.email,
    required this.name,
    required this.orders,
    required this.totalAmount,
  });

  final String userId;
  final String email;
  final String name;
  final List<Map<String, dynamic>> orders;
  final double totalAmount;
}
class _OrderDetailAdminPage extends StatefulWidget {
  const _OrderDetailAdminPage({required this.row});

  final Map<String, dynamic> row;

  @override
  State<_OrderDetailAdminPage> createState() => _OrderDetailAdminPageState();
}

class _OrderDetailAdminPageState extends State<_OrderDetailAdminPage> {
  SupabaseClient get _supa => Supabase.instance.client;

  static const _evidenceSides = <String>['front', 'left', 'right', 'back'];

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

  DateTime? _dt(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v.isUtc ? v.toLocal() : v;
    try {
      final parsed = DateTime.parse(v.toString());
      return parsed.isUtc ? parsed.toLocal() : parsed;
    } catch (_) {
      return null;
    }
  }

  String _fmtDateTime(dynamic v, {bool withSeconds = false}) {
    final d = _dt(v);
    if (d == null) return '-';
    var h = d.hour;
    final mm = d.minute.toString().padLeft(2, '0');
    final ss = d.second.toString().padLeft(2, '0');
    final ap = h >= 12 ? 'pm' : 'am';
    h %= 12;
    if (h == 0) h = 12;
    final time = withSeconds ? '$h:$mm:$ss$ap' : '$h:$mm$ap';
    return '${d.day}/${d.month}/${d.year} $time';
  }

  double _moneyValue(dynamic v) {
    return v is num ? v.toDouble() : double.tryParse(v.toString()) ?? 0;
  }

  int _bookedHours() {
    final start = _dt(_detail?['rental_start']);
    final end = _dt(_detail?['rental_end']);
    if (start == null || end == null) return 0;
    final mins = end.difference(start).inMinutes;
    if (mins <= 0) return 0;
    return (mins / 60).ceil();
  }

  double _baseHourlyRate() {
    final total = _moneyValue(_detail?['total_rental_amount']);
    final hours = _bookedHours();
    if (total > 0 && hours > 0) return total / hours;
    return 0;
  }

  int _overtimeHoursRoundedUp() {
    final scheduledEnd = _dt(_detail?['rental_end']);
    final actualDropoff = _dt(_detail?['dropoff_completed_at']) ?? _dt(_detail?['actual_dropoff_at']);
    if (scheduledEnd == null || actualDropoff == null || !actualDropoff.isAfter(scheduledEnd)) return 0;
    final mins = actualDropoff.difference(scheduledEnd).inMinutes;
    if (mins <= 0) return 0;
    return (mins / 60).ceil();
  }

  double _computedPenalty() {
    final stored = _moneyValue(_detail?['overtime_penalty_amount']);
    if (stored > 0) return stored;
    final hours = _overtimeHoursRoundedUp();
    if (hours <= 0) return 0;
    return hours * _baseHourlyRate() * 2;
  }

  String? _evidenceUrl(String stage, String side) {
    final raw = (_detail?['${stage}_${side}_url'] ?? '').toString().trim();
    return raw.isEmpty ? null : raw;
  }

  bool _hasEvidence(String stage) {
    for (final side in _evidenceSides) {
      if ((_evidenceUrl(stage, side) ?? '').isNotEmpty) return true;
    }
    return false;
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
            '*, app_user:user_id(user_name,user_email,user_phone), vehicle:vehicle_id(vehicle_brand,vehicle_model,vehicle_plate_no,vehicle_location,leaser_id)',
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
    final penalty = _computedPenalty();
    final overtimeHours = _overtimeHoursRoundedUp();

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
                        _KV('Rental Start', _fmtDateTime(_detail!['rental_start'])),
                        _KV('Rental End', _fmtDateTime(_detail!['rental_end'])),
                        _KV('Payment Option', (_detail!['payment_option'] ?? '').toString()),
                        _KV('Voucher Code', (_detail!['voucher_code'] ?? '-').toString()),
                        _KV('Voucher Discount', _money(_detail!['voucher_discount'] ?? 0)),
                        _KV('Dropoff Location', (_detail!['dropoff_location'] ?? '-').toString()),
                        _KV('Pickup Completed At', _fmtDateTime(_detail!['pickup_completed_at'], withSeconds: true)),
                        _KV('Drop-off Completed At', _fmtDateTime(_detail!['dropoff_completed_at'] ?? _detail!['actual_dropoff_at'], withSeconds: true)),
                        _KV('Demo Lock State', (_detail!['lock_demo_state'] ?? '-').toString()),
                        if (overtimeHours > 0) ...[
                          _KV('Overtime Hours', overtimeHours.toString()),
                          _KV('Overtime Penalty', _money(penalty)),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Text(
                              'Penalty rule: every overtime hour is charged at 2x the normal hourly rate, rounded up.',
                              style: TextStyle(color: Colors.grey.shade700),
                            ),
                          ),
                        ],
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
                        if (_hasEvidence('pickup')) ...[
                          const Divider(height: 26),
                          const Text('Pickup Inspection Photos', style: TextStyle(fontWeight: FontWeight.w900)),
                          const SizedBox(height: 10),
                          Text(
                            'Review the 4 pickup photos captured before the trip was officially ongoing.',
                            style: TextStyle(color: Colors.grey.shade700),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: _evidenceSides
                                .map((side) => _AdminEvidenceCard(
                                      label: side[0].toUpperCase() + side.substring(1),
                                      imageUrl: _evidenceUrl('pickup', side),
                                    ))
                                .toList(),
                          ),
                        ],
                        if (_hasEvidence('dropoff')) ...[
                          const Divider(height: 26),
                          const Text('Drop-off Inspection Photos', style: TextStyle(fontWeight: FontWeight.w900)),
                          const SizedBox(height: 10),
                          Text(
                            'Staff/Admin should compare these against the pickup photos to check for damage.',
                            style: TextStyle(color: Colors.grey.shade700),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: _evidenceSides
                                .map((side) => _AdminEvidenceCard(
                                      label: side[0].toUpperCase() + side.substring(1),
                                      imageUrl: _evidenceUrl('dropoff', side),
                                    ))
                                .toList(),
                          ),
                        ],
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

class _AdminEvidenceCard extends StatelessWidget {
  const _AdminEvidenceCard({
    required this.label,
    required this.imageUrl,
  });

  final String label;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final hasUrl = (imageUrl ?? '').trim().isNotEmpty;
    return SizedBox(
      width: 165,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Container(
              height: 110,
              color: Colors.grey.shade200,
              child: hasUrl
                  ? Image.network(
                      imageUrl!,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      errorBuilder: (_, __, ___) => const Center(child: Text('Image unavailable')),
                    )
                  : const Center(child: Text('No photo found')),
            ),
          ),
        ],
      ),
    );
  }
}
