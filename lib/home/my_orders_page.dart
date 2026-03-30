import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import '../services/booking_hold_service.dart';
import 'my_order_detail_page.dart';

/// My Orders (P1)
/// - Shows Ongoing Orders (Active) and Past Orders (Inactive)
/// - Each card is clickable to view order detail (P2)
class MyOrdersPage extends StatefulWidget {
  const MyOrdersPage({super.key});

  @override
  State<MyOrdersPage> createState() => _MyOrdersPageState();
}

class _MyOrdersPageState extends State<MyOrdersPage> {
  SupabaseClient get _supa => Supabase.instance.client;

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _ongoing = const [];
  List<Map<String, dynamic>> _incoming = const [];
  List<Map<String, dynamic>> _past = const [];
  List<Map<String, dynamic>> _blocked = const [];
  List<Map<String, dynamic>> _holding = const [];
  bool _shownDeactiveAlert = false;
  Timer? _ticker;
  Timer? _reloadDebounce;
  DateTime _liveNow = DateTime.now();
  bool _expiringVisibleHoldings = false;
  StreamSubscription<List<Map<String, dynamic>>>? _bookingSubscription;
  String? _bookingSubscriptionUserId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _reloadDebounce?.cancel();
    _bookingSubscription?.cancel();
    super.dispose();
  }

  Future<String?> _currentUserId() async {
    final u = _supa.auth.currentUser;
    if (u == null) return null;
    final row = await _supa
        .from('app_user')
        .select('user_id')
        .eq('auth_uid', u.id)
        .maybeSingle();
    if (row == null) return null;
    return (row['user_id'] ?? '').toString();
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

  bool _isBlocked(Map<String, dynamic> r) {
    final s = _normStatus((r['booking_status'] ?? '').toString());
    return s == 'deactive' || s == 'cancelled';
  }

  BookingHoldService get _holdSvc => BookingHoldService(_supa);

  bool _isActiveHolding(Map<String, dynamic> r, [DateTime? now]) =>
      _holdSvc.isActiveHoldRow(r, now: now ?? _liveNow);

  bool _isExpiredHolding(Map<String, dynamic> r, [DateTime? now]) {
    final s = _normStatus((r['booking_status'] ?? '').toString());
    if (s != 'holding') return false;
    final expiry = _holdSvc.parseHoldExpiryFromRow(r);
    if (expiry == null) return true;
    return !expiry.isAfter(now ?? _liveNow);
  }

  void _restartTickerIfNeeded() {
    _ticker?.cancel();
    if (_holding.isEmpty) return;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (!mounted) return;
      setState(() => _liveNow = DateTime.now());
      if (_holding.any((r) => _isExpiredHolding(r, _liveNow))) {
        await _expireVisibleHoldingsIfNeeded();
      }
    });
  }

  Future<void> _expireVisibleHoldingsIfNeeded() async {
    if (_expiringVisibleHoldings) return;
    _expiringVisibleHoldings = true;
    try {
      bool changed = false;
      final now = _liveNow;
      for (final row in List<Map<String, dynamic>>.from(_holding)) {
        if (!_isExpiredHolding(row, now)) continue;
        final bookingId = (row['booking_id'] ?? '').toString();
        if (bookingId.isEmpty) continue;
        await _holdSvc.expireIfNeeded(bookingId: bookingId, row: row);
        changed = true;
      }
      if (changed && mounted) {
        await _load();
      }
    } finally {
      _expiringVisibleHoldings = false;
    }
  }

  bool _hasPickupCompleted(Map<String, dynamic> r) => _dt(r['pickup_completed_at']) != null;

  bool _hasDropoffCompleted(Map<String, dynamic> r) {
    final s = _normStatus((r['booking_status'] ?? '').toString());
    if (s == 'inactive') return true;
    return _dt(r['dropoff_completed_at']) != null || _dt(r['actual_dropoff_at']) != null;
  }

  bool _isIncoming(Map<String, dynamic> r) {
    final start = _dt(r['rental_start']);
    final end = _dt(r['rental_end']);
    if (start == null || end == null) return false;
    if (_isBlocked(r) || _isActiveHolding(r) || _hasDropoffCompleted(r)) return false;
    final now = _liveNow;
    return now.isBefore(start);
  }

  bool _isOngoing(Map<String, dynamic> r) {
    final start = _dt(r['rental_start']);
    final end = _dt(r['rental_end']);
    if (start == null || end == null) return false;
    if (_isBlocked(r) || _isActiveHolding(r) || _hasDropoffCompleted(r)) return false;
    final now = DateTime.now();
    if (_hasPickupCompleted(r)) {
      return true;
    }
    return (now.isAtSameMomentAs(start) || now.isAfter(start)) && now.isBefore(end);
  }

  String _durationText(Map<String, dynamic> r) {
    final start = _dt(r['rental_start']);
    final end = _dt(r['rental_end']);
    if (start == null || end == null) return '-';

    final now = _liveNow;

    if (_isActiveHolding(r, now)) {
      final remaining = _holdSvc.remainingForRow(r, now: now) ?? Duration.zero;
      return 'Hold expires in ${_holdSvc.formatRemaining(remaining)}';
    }

    if (_isIncoming(r)) {
      final diff = start.difference(now);
      if (diff.isNegative) return 'Starting soon';
      final totalMins = diff.inMinutes;
      final days = totalMins ~/ (60 * 24);
      final hours = (totalMins % (60 * 24)) ~/ 60;
      if (days > 0) return 'Starts in $days day ${hours}h';
      return 'Starts in ${math.max(0, hours)} hour';
    }

    if (_hasPickupCompleted(r) && !_hasDropoffCompleted(r) && now.isAfter(end)) {
      return 'Overtime';
    }

    final diff = end.difference(now);
    if (diff.isNegative) return 'Completed';

    final totalMins = diff.inMinutes;
    final days = totalMins ~/ (60 * 24);
    final hours = (totalMins % (60 * 24)) ~/ 60;
    if (days > 0) return '$days day ${hours}h left';
    return '${math.max(0, hours)} hour left';
  }

  String _blockedInfoText(Map<String, dynamic> r) {
    final status = _normStatus((r['booking_status'] ?? '').toString());
    if (status == 'deactive') return 'Please contact admin';

    final cancelledAt = _dt(r['cancelled_by_user_at']);
    if (cancelledAt != null) return 'Cancelled by user';

    final holdExpiry = _holdSvc.parseHoldExpiryFromRow(r);
    if (holdExpiry != null) return 'Order hold expired';

    return 'Order cancelled';
  }

  String _normStatus(String status) {
    final s = status.trim().toLowerCase();
    if (s == 'cancel' || s == 'cancelled' || s == 'canceled') return 'cancelled';
    if (s == 'deactive' || s == 'deactivated') return 'deactive';
    if (s == 'active') return 'active';
    if (s == 'inactive') return 'inactive';
    return s;
  }

  String _statusText(String status) {
    final s = _normStatus(status);
    if (s == 'cancelled') return 'Cancelled';
    if (s == 'deactive') return 'Deactive';
    if (s == 'holding') return 'Holding';
    if (s == 'active') return 'Active';
    if (s == 'inactive') return 'Inactive';
    return status.trim().isEmpty ? '-' : status;
  }

  Color _statusColor(String status) {
    final s = _normStatus(status);
    if (s == 'cancelled' || s == 'deactive') return Colors.red;
    if (s == 'holding') return Colors.orange;
    if (s == 'active') return Colors.green;
    if (s == 'inactive') return Colors.grey;
    return Colors.blueGrey;
  }


  String _vehiclePhotoPublicUrl(String? path) {
    if (path == null || path.trim().isEmpty) return '';
    final safe = path.replaceFirst(RegExp(r'^/+'), '');
    return '${SupabaseConfig.supabaseUrl}/storage/v1/object/public/vehicle_photos/$safe';
  }

  Future<List<Map<String, dynamic>>> _fetchBookingsWithVehicle(String userId) async {
    // Try nested select first (best case).
    try {
      final base = _supa
          .from('booking')
          .select(
            '*, vehicle:vehicle_id (vehicle_id, vehicle_brand, vehicle_model, vehicle_plate_no, vehicle_type, transmission_type, fuel_type, seat_capacity, daily_rate, vehicle_location, vehicle_photo_path, vehicle_color, fuel_percent)',
          )
          .eq('user_id', userId);
      final data = await base.order('rental_start', ascending: false);
      return (data as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (_) {
      // Fallback: fetch bookings, then vehicles, then merge.
      final base = _supa
          .from('booking')
          .select('*')
          .eq('user_id', userId);
      final data = await base.order('rental_start', ascending: false);
      final bookings = (data as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      final ids = bookings
          .map((b) => (b['vehicle_id'] ?? '').toString())
          .where((s) => s.isNotEmpty)
          .toSet()
          .toList();
      if (ids.isEmpty) return bookings;

      // Avoid relying on inFilter (version differences). Use simple per-id fetch.
      final mapById = <String, Map<String, dynamic>>{};
      for (final id in ids) {
        final row = await _supa
            .from('vehicle')
            .select(
              'vehicle_id, vehicle_brand, vehicle_model, vehicle_plate_no, vehicle_type, transmission_type, fuel_type, seat_capacity, daily_rate, vehicle_location, vehicle_photo_path, vehicle_color, fuel_percent',
            )
            .eq('vehicle_id', id)
            .maybeSingle();
        if (row != null) {
          mapById[id] = Map<String, dynamic>.from(row as Map);
        }
      }

      for (final b in bookings) {
        final vid = (b['vehicle_id'] ?? '').toString();
        b['vehicle'] = mapById[vid];
      }
      return bookings;
    }
  }

  void _ensureRealtimeBookingWatch(String userId) {
    if (_bookingSubscriptionUserId == userId && _bookingSubscription != null) {
      return;
    }
    _bookingSubscription?.cancel();
    _bookingSubscriptionUserId = userId;
    _bookingSubscription = _supa
        .from('booking')
        .stream(primaryKey: const ['booking_id'])
        .eq('user_id', userId)
        .listen((_) {
      _reloadDebounce?.cancel();
      _reloadDebounce = Timer(const Duration(milliseconds: 250), () {
        if (mounted) {
          _load();
        }
      });
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _ongoing = const [];
      _incoming = const [];
      _past = const [];
      _blocked = const [];
      _holding = const [];
    });

    try {
      final userId = await _currentUserId();
      if (userId == null || userId.isEmpty) throw 'Please login first.';
      _ensureRealtimeBookingWatch(userId);

      final rows = await _fetchBookingsWithVehicle(userId);
      final ongoing = <Map<String, dynamic>>[];
      final incoming = <Map<String, dynamic>>[];
      final past = <Map<String, dynamic>>[];
      final blocked = <Map<String, dynamic>>[];
      final holding = <Map<String, dynamic>>[];
      final now = DateTime.now();

      for (final r in rows) {
        if (_isExpiredHolding(r, now)) {
          final bookingId = (r['booking_id'] ?? '').toString();
          if (bookingId.isNotEmpty) {
            await _holdSvc.expireIfNeeded(bookingId: bookingId, row: r);
          }
          r['booking_status'] = 'Cancelled';
          blocked.add(r);
        } else if (_isBlocked(r)) {
          blocked.add(r);
        } else if (_isActiveHolding(r, now)) {
          holding.add(r);
        } else if (_isIncoming(r)) {
          incoming.add(r);
        } else if (_isOngoing(r)) {
          ongoing.add(r);
        } else {
          past.add(r);
        }
      }

      if (!mounted) return;
      setState(() {
        _ongoing = ongoing;
        _incoming = incoming;
        _blocked = blocked;
        _holding = holding;
        _past = past;
        _liveNow = DateTime.now();
        _loading = false;
      });
      _restartTickerIfNeeded();

      // Show alert if any order is deactivated by admin.
      if (!_shownDeactiveAlert) {
        final hasDeactive = blocked.any((r) => _normStatus((r['booking_status'] ?? '').toString()) == 'deactive');
        if (hasDeactive) {
          _shownDeactiveAlert = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            showDialog(
              context: context,
              builder: (_) => AlertDialog(
                title: const Text('Order Deactivated'),
                content: const Text('Please contact admin. Your order is deactive by admin.'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('OK'),
                  ),
                ],
              ),
            );
          });
        }
      }

    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        centerTitle: true,
        title: const Text('My Orders'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                children: [
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.only(top: 24),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 24),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Colors.red.shade700,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    )
                  else ...[
                    const _SectionHeader(
                      title: 'Holding Orders',
                      color: Colors.orange,
                    ),
                    const SizedBox(height: 8),
                    if (_holding.isEmpty)
                      Text(
                        'No holding orders.',
                        style: TextStyle(color: Colors.grey.shade700),
                      )
                    else
                      ..._holding.map(
                        (r) => _OrderCard(
                          row: r,
                          statusText: 'Holding',
                          statusColor: Colors.orange,
                          durationText: _durationText(r),
                          photoUrlBuilder: _vehiclePhotoPublicUrl,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => MyOrderDetailsPage(booking: r),
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 14),
                    const _SectionHeader(
                      title: 'Ongoing Orders',
                      color: Colors.green,
                    ),
                    const SizedBox(height: 8),
                    if (_ongoing.isEmpty)
                      Text(
                        'No ongoing orders.',
                        style: TextStyle(color: Colors.grey.shade700),
                      )
                    else
                      ..._ongoing.map(
                        (r) => _OrderCard(
                          row: r,
                          statusText: _hasPickupCompleted(r) ? 'Ongoing' : 'Pickup Ready',
                          statusColor: _hasPickupCompleted(r) ? Colors.green : Colors.teal,
                          durationText: _durationText(r),
                          photoUrlBuilder: _vehiclePhotoPublicUrl,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => MyOrderDetailsPage(booking: r),
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 14),
                    const _SectionHeader(
                      title: 'Incoming Orders',
                      color: Colors.blue,
                    ),
                    const SizedBox(height: 8),
                    if (_incoming.isEmpty)
                      Text(
                        'No incoming orders.',
                        style: TextStyle(color: Colors.grey.shade700),
                      )
                    else
                      ..._incoming.map(
                        (r) => _OrderCard(
                          row: r,
                          statusText: 'Incoming',
                          statusColor: Colors.blue,
                          durationText: _durationText(r),
                          photoUrlBuilder: _vehiclePhotoPublicUrl,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => MyOrderDetailsPage(booking: r),
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 14),
                    const _SectionHeader(
                      title: 'Deactive / Cancel Orders',
                      color: Colors.red,
                    ),
                    const SizedBox(height: 8),
                    if (_blocked.isEmpty)
                      Text(
                        'No deactive/cancel orders.',
                        style: TextStyle(color: Colors.grey.shade700),
                      )
                    else
                      ..._blocked.map(
                        (r) => _OrderCard(
                          row: r,
                          statusText: _statusText((r['booking_status'] ?? '').toString()),
                          statusColor: _statusColor((r['booking_status'] ?? '').toString()),
                          infoLabel: 'Reason',
                          durationText: _blockedInfoText(r),
                          photoUrlBuilder: _vehiclePhotoPublicUrl,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => MyOrderDetailsPage(booking: r),
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 14),
                    _SectionHeader(
                      title: 'Inactive Orders',
                      color: cs.outline,
                    ),
                    const SizedBox(height: 8),
                    if (_past.isEmpty)
                      Text(
                        'No inactive orders.',
                        style: TextStyle(color: Colors.grey.shade700),
                      )
                    else
                      ..._past.map(
                        (r) => _OrderCard(
                          row: r,
                          statusText: 'Inactive',
                          statusColor: Colors.grey,
                          durationText: 'Completed',
                          photoUrlBuilder: _vehiclePhotoPublicUrl,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => MyOrderDetailsPage(booking: r),
                            ),
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.color});

  final String title;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 18,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ],
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({
    required this.row,
    required this.statusText,
    required this.statusColor,
    required this.durationText,
    required this.photoUrlBuilder,
    required this.onTap,
    this.infoLabel = 'Time duration',
  });

  final Map<String, dynamic> row;
  final String statusText;
  final Color statusColor;
  final String durationText;
  final String infoLabel;
  final String Function(String? path) photoUrlBuilder;
  final VoidCallback onTap;

  String _str(Map<String, dynamic> m, String k) => (m[k] ?? '').toString();

  @override
  Widget build(BuildContext context) {
    final vehicle = (row['vehicle'] is Map)
        ? Map<String, dynamic>.from(row['vehicle'] as Map)
        : <String, dynamic>{};

    final carName = ('${_str(vehicle, 'vehicle_brand')} ${_str(vehicle, 'vehicle_model')}').trim();
    final title = carName.isEmpty ? _str(row, 'vehicle_id') : carName;

    final plate = _str(vehicle, 'vehicle_plate_no');
    final loc = _str(vehicle, 'vehicle_location');
    final fuel = _str(vehicle, 'fuel_type');
    final photoPath = _str(vehicle, 'vehicle_photo_path');
    final photoUrl = photoPath.isEmpty ? '' : photoUrlBuilder(photoPath);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          statusText,
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: statusColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Number Plate: ${plate.isEmpty ? '-' : plate}',
                      style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Details: ${fuel.isEmpty ? '-' : fuel} • ${loc.isEmpty ? '-' : loc}',
                      style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$infoLabel: $durationText',
                      style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 88,
                  height: 64,
                  child: photoUrl.isEmpty
                      ? Container(
                          color: Colors.grey.shade200,
                          alignment: Alignment.center,
                          child: const Icon(Icons.directions_car_rounded),
                        )
                      : Image.network(
                          photoUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: Colors.grey.shade200,
                            alignment: Alignment.center,
                            child: const Icon(Icons.image_not_supported_outlined),
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}