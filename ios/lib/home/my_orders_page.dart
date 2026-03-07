import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
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
  List<Map<String, dynamic>> _past = const [];

  @override
  void initState() {
    super.initState();
    _load();
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
    if (v is DateTime) return v;
    try {
      return DateTime.parse(v.toString());
    } catch (_) {
      return null;
    }
  }

  bool _isOngoing(Map<String, dynamic> r) {
    final end = _dt(r['rental_end']);
    if (end == null) return false;
    final st = (r['booking_status'] ?? '').toString().toLowerCase();
    if (st.contains('cancel') || st.contains('fail') || st.contains('reject')) {
      return false;
    }
    return DateTime.now().isBefore(end);
  }

  String _hoursLeftText(Map<String, dynamic> r) {
    final start = _dt(r['rental_start']);
    final end = _dt(r['rental_end']);
    if (start == null || end == null) return '-';

    final now = DateTime.now();
    // If booking hasn't started yet, show the planned rental duration (end - start)
    // rather than a long countdown to the end date.
    final ref = now.isBefore(start) ? start : now;

    final diff = end.difference(ref);
    if (diff.isNegative) return '0 hour left';

    final totalMins = diff.inMinutes;
    final days = totalMins ~/ (60 * 24);
    final hours = (totalMins % (60 * 24)) ~/ 60;
    if (days > 0) return '$days day ${hours}h left';
    return '${math.max(0, hours)} hour left';
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
            'booking_id, booking_status, rental_start, rental_end, total_rental_amount, vehicle_id,'
            ' vehicle:vehicle_id (vehicle_id, vehicle_brand, vehicle_model, vehicle_plate_no, vehicle_type, transmission_type, fuel_type, seat_capacity, daily_rate, vehicle_location, vehicle_photo_path, vehicle_color, fuel_percent)',
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
          .select('booking_id, booking_status, rental_start, rental_end, total_rental_amount, vehicle_id')
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

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _ongoing = const [];
      _past = const [];
    });

    try {
      final userId = await _currentUserId();
      if (userId == null || userId.isEmpty) throw 'Please login first.';

      final rows = await _fetchBookingsWithVehicle(userId);
      final ongoing = <Map<String, dynamic>>[];
      final past = <Map<String, dynamic>>[];
      for (final r in rows) {
        (_isOngoing(r) ? ongoing : past).add(r);
      }

      if (!mounted) return;
      setState(() {
        _ongoing = ongoing;
        _past = past;
        _loading = false;
      });
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
                      title: 'Ongoing Orders Details',
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
                          statusText: 'Active',
                          statusColor: Colors.green,
                          durationText: _hoursLeftText(r),
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
                      title: 'Past Orders Details',
                      color: cs.outline,
                    ),
                    const SizedBox(height: 8),
                    if (_past.isEmpty)
                      Text(
                        'No past orders.',
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
  });

  final Map<String, dynamic> row;
  final String statusText;
  final Color statusColor;
  final String durationText;
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
                      'Time duration: $durationText',
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
