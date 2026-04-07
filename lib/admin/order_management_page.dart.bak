
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/in_app_notification_service.dart';

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
  Map<String, Set<String>> _evidenceStagesByBooking = const {};

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

      var evidenceStagesByBooking = <String, Set<String>>{};
      try {
        final evidenceRows = await _supa
            .from('booking_evidence')
            .select('booking_id,stage')
            .limit(10000);
        for (final row in (evidenceRows as List)) {
          final map = Map<String, dynamic>.from(row as Map);
          final bookingId = (map['booking_id'] ?? '').toString().trim();
          final stage = (map['stage'] ?? '').toString().trim().toLowerCase();
          if (bookingId.isEmpty || stage.isEmpty) continue;
          evidenceStagesByBooking.putIfAbsent(bookingId, () => <String>{}).add(stage);
        }
      } catch (_) {
        evidenceStagesByBooking = <String, Set<String>>{};
      }

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
        _evidenceStagesByBooking = evidenceStagesByBooking;
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
      if (!_shouldAppearInAdminList(r)) {
        continue;
      }
      final st = (r['booking_status'] ?? '').toString().trim();
      if (_statusFilter != 'All' && _effectiveStatusKey(r) != _normStatus(_statusFilter)) {
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

  DateTime? _dt(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value.isUtc ? value.toLocal() : value;
    try {
      final parsed = DateTime.parse(value.toString());
      return parsed.isUtc ? parsed.toLocal() : parsed;
    } catch (_) {
      return null;
    }
  }

  bool _hasDropoffCompleted(Map<String, dynamic> row) {
    final s = _normStatus((row['booking_status'] ?? '').toString());
    if (s == 'inactive') return true;
    return _dt(row['dropoff_completed_at']) != null || _dt(row['actual_dropoff_at']) != null;
  }

  bool _isIncomingOrder(Map<String, dynamic> row) {
    final start = _dt(row['rental_start']);
    final end = _dt(row['rental_end']);
    if (start == null || end == null) return false;
    if (_hasDropoffCompleted(row)) return false;
    final s = _normStatus((row['booking_status'] ?? '').toString());
    if (s == 'cancelled' || s == 'deactive' || s == 'inactive' || s == 'holding') return false;
    return DateTime.now().isBefore(start);
  }

  bool _shouldAppearInAdminList(Map<String, dynamic> row) {
    return true;
  }

  bool _isPhotoEligibleOrder(Map<String, dynamic> row) {
    final s = _normStatus((row['booking_status'] ?? '').toString());
    if (s == 'cancelled') return false;
    if (_isIncomingOrder(row)) return false;
    return true;
  }

  String _effectiveStatusKey(Map<String, dynamic> row) {
    if (_isIncomingOrder(row)) return 'incoming';
    return _normStatus((row['booking_status'] ?? '').toString());
  }

  String _effectiveStatusLabel(Map<String, dynamic> row) {
    final key = _effectiveStatusKey(row);
    if (key == 'incoming') return 'Incoming';
    return _statusLabel((row['booking_status'] ?? '').toString());
  }

  Color _effectiveStatusColor(Map<String, dynamic> row) {
    final key = _effectiveStatusKey(row);
    if (key == 'incoming') return Colors.blue;
    return _statusColor((row['booking_status'] ?? '').toString());
  }

  bool _hasEvidenceInRow(Map<String, dynamic> row, String stage) {
    if (!_isPhotoEligibleOrder(row)) return false;
    for (final side in const ['front', 'left', 'right', 'back']) {
      final url = (row['${stage}_${side}_url'] ?? '').toString().trim();
      final path = (row['${stage}_${side}_path'] ?? '').toString().trim();
      if (url.isNotEmpty || path.isNotEmpty) return true;
    }
    final bookingId = (row['booking_id'] ?? '').toString().trim();
    return (_evidenceStagesByBooking[bookingId] ?? const <String>{}).contains(stage);
  }

  Widget _evidenceChip({required String text, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 11),
      ),
    );
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
            child: Column(
              children: [
                Row(
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
                        DropdownMenuItem(value: 'Incoming', child: Text('Incoming')),
                        DropdownMenuItem(value: 'Paid', child: Text('Paid')),
                        DropdownMenuItem(value: 'Active', child: Text('Active')),
                        DropdownMenuItem(value: 'Inactive', child: Text('Inactive')),
                        DropdownMenuItem(value: 'Deactive', child: Text('Deactive')),
                        DropdownMenuItem(value: 'Holding', child: Text('Holding')),
                        DropdownMenuItem(value: 'Cancelled', child: Text('Cancelled')),
                      ],
                      onChanged: (v) => setState(() => _statusFilter = v ?? 'All'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final option in const [
                        'All',
                        'Incoming',
                        'Paid',
                        'Active',
                        'Inactive',
                        'Deactive',
                        'Holding',
                        'Cancelled',
                      ])
                        FilterChip(
                          label: Text(option),
                          selected: _statusFilter == option,
                          onSelected: (_) => setState(() => _statusFilter = option),
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
                                  final statusLabel = _effectiveStatusLabel(r);
                                  final statusColor = _effectiveStatusColor(r);
                                  final isPhotoEligible = _isPhotoEligibleOrder(r);
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
                                      subtitle: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text('Vehicle: $vid\nAmount: $amt\nDate: $bookingDate'),
                                          if (isPhotoEligible && (_hasEvidenceInRow(r, 'pickup') || _hasEvidenceInRow(r, 'dropoff'))) ...[
                                            const SizedBox(height: 8),
                                            Wrap(
                                              spacing: 6,
                                              runSpacing: 6,
                                              children: [
                                                if (_hasEvidenceInRow(r, 'pickup'))
                                                  _evidenceChip(text: 'Pickup photos', color: Colors.indigo),
                                                if (_hasEvidenceInRow(r, 'dropoff'))
                                                  _evidenceChip(text: 'Drop-off photos', color: Colors.deepOrange),
                                              ],
                                            ),
                                          ] else if (!isPhotoEligible) ...[
                                            const SizedBox(height: 8),
                                            Text(
                                              'Pickup / drop-off photos not available for $statusLabel orders.',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey.shade700,
                                                fontStyle: FontStyle.italic,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                            decoration: BoxDecoration(
                                              color: statusColor.withOpacity(0.12),
                                              borderRadius: BorderRadius.circular(999),
                                            ),
                                            child: Text(
                                              statusLabel,
                                              style: TextStyle(
                                                color: statusColor,
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
  static const _evidenceBucket = 'booking_evidence';

  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _detail;
  final Map<String, String> _resolvedEvidenceUrls = <String, String>{};
  bool _loadingExtraCharges = false;
  bool _extraChargeTableReady = true;
  bool _sendingReminder = false;
  List<Map<String, dynamic>> _extraCharges = const [];

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

  String _chargeStatusLabel(dynamic value) {
    final raw = (value ?? '').toString().trim().toLowerCase();
    if (raw == 'paid') return 'Paid';
    if (raw == 'waived') return 'Waived';
    if (raw == 'cancelled') return 'Cancelled';
    return 'Pending';
  }

  Color _chargeStatusColor(BuildContext context, dynamic value) {
    final raw = (value ?? '').toString().trim().toLowerCase();
    if (raw == 'paid') return Colors.green;
    if (raw == 'waived') return Colors.blueGrey;
    if (raw == 'cancelled') return Colors.red;
    return Theme.of(context).colorScheme.primary;
  }

  String _chargePaymentMethodLabel(dynamic value) {
    final raw = (value ?? '').toString().trim().toLowerCase();
    if (raw == 'card') return 'Card';
    if (raw == 'tng' || raw == 'touch n go' || raw == "touch 'n go" || raw == 'touchngo') return 'TNG';
    if (raw == 'stripe') return 'Stripe';
    return (value ?? '').toString().trim().isEmpty ? '-' : (value ?? '').toString().trim();
  }

  List<Map<String, dynamic>> get _pendingExtraCharges {
    return _extraCharges
        .where((row) => _chargeStatusLabel(row['charge_status']) == 'Pending')
        .toList(growable: false);
  }

  double get _pendingExtraChargeTotal {
    var total = 0.0;
    for (final row in _pendingExtraCharges) {
      total += _moneyValue(row['amount']);
    }
    return total;
  }

  bool get _hideEvidenceForThisOrder {
    final detail = _detail ?? widget.row;
    final raw = (detail['booking_status'] ?? '').toString().trim().toLowerCase();
    if (raw == 'cancel' || raw == 'cancelled' || raw == 'canceled') return true;
    final start = _dt(detail['rental_start']);
    final end = _dt(detail['rental_end']);
    final hasDropoffCompleted = _dt(detail['dropoff_completed_at']) != null || _dt(detail['actual_dropoff_at']) != null;
    final statusBlocksIncoming = raw == 'cancel' || raw == 'cancelled' || raw == 'canceled' || raw == 'deactive' || raw == 'inactive' || raw == 'holding';
    if (!statusBlocksIncoming && start != null && end != null && !hasDropoffCompleted && DateTime.now().isBefore(start)) {
      return true;
    }
    return false;
  }

  String get _hiddenEvidenceReason {
    final detail = _detail ?? widget.row;
    final raw = (detail['booking_status'] ?? '').toString().trim().toLowerCase();
    if (raw == 'cancel' || raw == 'cancelled' || raw == 'canceled') {
      return 'Cancelled orders do not show pickup / drop-off inspection photos.';
    }
    return 'Incoming orders do not show pickup / drop-off inspection photos yet.';
  }

  Future<void> _refreshExtraCharges() async {
    final bookingId = (widget.row['booking_id'] ?? '').toString().trim();
    if (bookingId.isEmpty) return;
    if (mounted) {
      setState(() => _loadingExtraCharges = true);
    }
    try {
      final rows = await _supa
          .from('booking_extra_charge')
          .select('*')
          .eq('booking_id', bookingId)
          .order('created_at', ascending: false);
      final list = (rows as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (!mounted) return;
      setState(() {
        _extraCharges = list;
        _extraChargeTableReady = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _extraCharges = const [];
        _extraChargeTableReady = false;
      });
    } finally {
      if (mounted) {
        setState(() => _loadingExtraCharges = false);
      }
    }
  }

  Future<void> _sendPendingChargeReminder() async {
    final detail = _detail;
    if (detail == null || _pendingExtraCharges.isEmpty) return;
    final userId = (detail['user_id'] ?? '').toString().trim();
    final bookingId = (detail['booking_id'] ?? '').toString().trim();
    if (userId.isEmpty || bookingId.isEmpty) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Reminder unpaid bill'),
        content: Text(
          'Send reminder to user for ${_pendingExtraCharges.length} unpaid bill(s)?\n\nTotal due: ${_money(_pendingExtraChargeTotal)}',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Back')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Send reminder')),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _sendingReminder = true);
    try {
      final firstCharge = _pendingExtraCharges.first;
      await InAppNotificationService(_supa).createNotification(
        userId: userId,
        bookingId: bookingId,
        extraChargeId: (firstCharge['charge_id'] ?? '').toString().trim(),
        type: 'extra_charge_reminder',
        title: 'Unpaid damage / extra bill reminder',
        message:
            'You still have ${_pendingExtraCharges.length} unpaid extra bill(s) for booking $bookingId. Total due: ${_money(_pendingExtraChargeTotal)}. Please open My Orders and pay the bill.',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reminder sent to user.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send reminder: $e')),
      );
    } finally {
      if (mounted) setState(() => _sendingReminder = false);
    }
  }

  Widget _buildExtraChargeSection() {
    if (_loadingExtraCharges) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (!_extraChargeTableReady || _extraCharges.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 26),
        Row(
          children: [
            const Expanded(
              child: Text('Extra Bills & Damage Charges', style: TextStyle(fontWeight: FontWeight.w900)),
            ),
            if (_pendingExtraCharges.isNotEmpty)
              FilledButton.tonalIcon(
                onPressed: _sendingReminder ? null : _sendPendingChargeReminder,
                icon: _sendingReminder
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.notifications_active_outlined),
                label: const Text('Remind user'),
              ),
          ],
        ),
        const SizedBox(height: 10),
        ..._extraCharges.map((row) {
          final status = _chargeStatusLabel(row['charge_status']);
          final color = _chargeStatusColor(context, row['charge_status']);
          final type = (row['charge_type'] ?? 'Other').toString();
          final note = (row['remark'] ?? row['notes'] ?? '').toString().trim();
          final amount = _money(row['amount']);
          final paymentMethod = _chargePaymentMethodLabel(
            row['payment_method'] ?? row['charge_payment_method'],
          );
          final paymentReference = ((row['payment_reference'] ?? row['charge_payment_reference']) ?? '')
              .toString()
              .trim();
          return Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withOpacity(0.25)),
              color: color.withOpacity(0.06),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        type.isEmpty ? 'Other' : type[0].toUpperCase() + type.substring(1),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: color.withOpacity(0.35)),
                      ),
                      child: Text(
                        status,
                        style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 12),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text('Amount: $amount', style: const TextStyle(fontWeight: FontWeight.w700)),
                if (note.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(note, style: TextStyle(color: Colors.grey.shade800, height: 1.3)),
                ],
                if (status == 'Paid' && paymentMethod != '-') ...[
                  const SizedBox(height: 6),
                  Text('Payment method: $paymentMethod', style: TextStyle(color: Colors.grey.shade800, fontWeight: FontWeight.w600)),
                ],
                if (status == 'Paid' && paymentReference.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text('Reference: $paymentReference', style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
                ],
              ],
            ),
          );
        }),
      ],
    );
  }

  String _evidenceKey(String stage, String side) => '$stage:$side';

  String _evidencePublicUrl(String path) {
    final safe = path.replaceFirst(RegExp(r'^/+'), '');
    return _supa.storage.from(_evidenceBucket).getPublicUrl(safe);
  }

  Future<String?> _signedOrPublicEvidenceUrl(String path) async {
    final trimmed = path.trim();
    if (trimmed.isEmpty) return null;
    final safe = trimmed.replaceFirst(RegExp(r'^/+'), '');
    try {
      return await _supa.storage.from(_evidenceBucket).createSignedUrl(safe, 60 * 60 * 24);
    } catch (_) {
      try {
        return _evidencePublicUrl(safe);
      } catch (_) {
        return null;
      }
    }
  }

  Future<void> _resolveEvidenceUrls() async {
    final detail = _detail;
    if (detail == null) return;
    final bookingId = (detail['booking_id'] ?? '').toString().trim();
    final resolved = <String, String>{};

    for (final stage in const ['pickup', 'dropoff']) {
      for (final side in _evidenceSides) {
        final directUrl = (detail['${stage}_${side}_url'] ?? '').toString().trim();
        if (directUrl.isNotEmpty) {
          resolved[_evidenceKey(stage, side)] = directUrl;
          continue;
        }
        final storagePath = (detail['${stage}_${side}_path'] ?? '').toString().trim();
        if (storagePath.isNotEmpty) {
          final signed = await _signedOrPublicEvidenceUrl(storagePath);
          if ((signed ?? '').isNotEmpty) {
            resolved[_evidenceKey(stage, side)] = signed!;
          }
        }
      }
    }

    if (bookingId.isNotEmpty) {
      try {
        final rows = await _supa
            .from('booking_evidence')
            .select('stage,side,image_url,storage_path')
            .eq('booking_id', bookingId);
        for (final row in (rows as List)) {
          final map = Map<String, dynamic>.from(row as Map);
          final stage = (map['stage'] ?? '').toString().trim();
          final side = (map['side'] ?? '').toString().trim();
          if (stage.isEmpty || side.isEmpty) continue;
          final key = _evidenceKey(stage, side);
          if ((resolved[key] ?? '').isNotEmpty) continue;
          final imageUrl = (map['image_url'] ?? '').toString().trim();
          if (imageUrl.isNotEmpty) {
            resolved[key] = imageUrl;
            continue;
          }
          final storagePath = (map['storage_path'] ?? '').toString().trim();
          if (storagePath.isNotEmpty) {
            final signed = await _signedOrPublicEvidenceUrl(storagePath);
            if ((signed ?? '').isNotEmpty) {
              resolved[key] = signed!;
            }
          }
        }
      } catch (_) {
        // Optional helper table. Ignore when not available.
      }
    }

    if (!mounted) return;
    setState(() {
      _resolvedEvidenceUrls
        ..clear()
        ..addAll(resolved);
    });
  }

  String? _evidenceUrl(String stage, String side) {
    final resolved = (_resolvedEvidenceUrls[_evidenceKey(stage, side)] ?? '').trim();
    if (resolved.isNotEmpty) return resolved;
    final raw = (_detail?['${stage}_${side}_url'] ?? '').toString().trim();
    if (raw.isNotEmpty) return raw;
    final path = (_detail?['${stage}_${side}_path'] ?? '').toString().trim();
    if (path.isNotEmpty) return _evidencePublicUrl(path);
    return null;
  }

  bool _hasEvidence(String stage) {
    for (final side in _evidenceSides) {
      final directUrl = (_detail?['${stage}_${side}_url'] ?? '').toString().trim();
      final path = (_detail?['${stage}_${side}_path'] ?? '').toString().trim();
      final resolved = (_resolvedEvidenceUrls[_evidenceKey(stage, side)] ?? '').trim();
      if (directUrl.isNotEmpty || path.isNotEmpty || resolved.isNotEmpty) return true;
    }
    return false;
  }

  int _evidenceFoundCount(String stage) {
    var count = 0;
    for (final side in _evidenceSides) {
      if (((_evidenceUrl(stage, side) ?? '').trim()).isNotEmpty) {
        count++;
      }
    }
    return count;
  }

  Widget _buildEvidenceSection({
    required String stage,
    required String title,
    required String description,
  }) {
    final count = _evidenceFoundCount(stage);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 26),
        Row(
          children: [
            Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w900))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                color: count > 0 ? Colors.green.withOpacity(0.08) : Colors.grey.withOpacity(0.12),
                border: Border.all(
                  color: count > 0 ? Colors.green.withOpacity(0.25) : Colors.grey.withOpacity(0.25),
                ),
              ),
              child: Text(
                '$count/4 found',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                  color: count > 0 ? Colors.green.shade700 : Colors.grey.shade700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(description, style: TextStyle(color: Colors.grey.shade700)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: _evidenceSides
              .map((side) => _AdminEvidenceCard(
                    label: side[0].toUpperCase() + side.substring(1),
                    imageUrl: _evidenceUrl(stage, side),
                  ))
              .toList(),
        ),
      ],
    );
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _detail = null;
      _resolvedEvidenceUrls.clear();
      _extraCharges = const [];
      _extraChargeTableReady = true;
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
      await _resolveEvidenceUrls();
      await _refreshExtraCharges();
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
                        _buildExtraChargeSection(),
                        if (_hideEvidenceForThisOrder)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                color: Colors.grey.shade100,
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              child: Text(
                                _hiddenEvidenceReason,
                                style: TextStyle(
                                  color: Colors.grey.shade800,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          )
                        else ...[
                          _buildEvidenceSection(
                            stage: 'pickup',
                            title: 'Pickup Inspection Photos',
                            description: 'Review the 4 pickup photos captured before the trip was officially ongoing.',
                          ),
                          _buildEvidenceSection(
                            stage: 'dropoff',
                            title: 'Drop-off Inspection Photos',
                            description: 'Staff/Admin should compare these against the pickup photos to check for damage.',
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
