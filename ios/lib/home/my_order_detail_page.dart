import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';

class MyOrderDetailsPage extends StatefulWidget {
  const MyOrderDetailsPage({
    super.key,
    required this.booking,
  });

  /// booking row with nested vehicle info if available.
  final Map<String, dynamic> booking;

  @override
  State<MyOrderDetailsPage> createState() => _MyOrderDetailsPageState();
}

class _MyOrderDetailsPageState extends State<MyOrderDetailsPage> {
  SupabaseClient get _supa => Supabase.instance.client;

  static const _outlets = <String>[
    '6, Jalan P. Ramlee',
    '111-109, Jalan Malinja 3, Taman Bunga Raya, 53000 Kuala Lumpur, Wilayah Persekutuan Kuala Lumpur',
  ];

  late Map<String, dynamic> _b;
  late Map<String, dynamic> _v;

  String _dropoff = '';

  @override
  void initState() {
    super.initState();
    _b = Map<String, dynamic>.from(widget.booking);
    final vehicle = (_b['vehicle'] is Map)
        ? Map<String, dynamic>.from(_b['vehicle'] as Map)
        : <String, dynamic>{};
    _v = vehicle;
    final loc = (_v['vehicle_location'] ?? _b['vehicle_location'] ?? '').toString();
    _dropoff = loc.isEmpty ? _outlets.first : loc;
  }

  String _vehiclePhotoPublicUrl(String? path) {
    if (path == null || path.trim().isEmpty) return '';
    final safe = path.replaceFirst(RegExp(r'^/+'), '');
    return '${SupabaseConfig.supabaseUrl}/storage/v1/object/public/vehicle_photos/$safe';
  }

  String _carName() {
    final brand = (_v['vehicle_brand'] ?? '').toString().trim();
    final model = (_v['vehicle_model'] ?? '').toString().trim();
    final t = ('$brand $model').trim();
    return t.isEmpty ? (_b['vehicle_id'] ?? '').toString() : t;
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

  String _fmtDate(DateTime d) => '${d.day}/${d.month}/${d.year}';

  String _fmtTime(DateTime d) {
    var h = d.hour;
    final m = d.minute.toString().padLeft(2, '0');
    final ap = h >= 12 ? 'pm' : 'am';
    h %= 12;
    if (h == 0) h = 12;
    return '$h:$m$ap';
  }

  bool get _isActive {
    final end = _dt(_b['rental_end']);
    if (end == null) return false;
    return DateTime.now().isBefore(end);
  }

  String get _statusLabel => _isActive ? 'Active' : 'Inactive';

  String _timeRangeText() {
    final s = _dt(_b['rental_start']);
    final e = _dt(_b['rental_end']);
    if (s == null || e == null) return '-';
    return '${_fmtDate(s)} - ${_fmtDate(e)}\n${_fmtTime(s)} - ${_fmtTime(e)}';
  }

  String _hoursLeftText() {
    final s = _dt(_b['rental_start']);
    final e = _dt(_b['rental_end']);
    if (s == null || e == null) return '-';

    final now = DateTime.now();
    // If booking hasn't started yet, show planned duration (end - start)
    // rather than a long countdown to the end date.
    final ref = now.isBefore(s) ? s : now;

    final diff = e.difference(ref);
    if (diff.isNegative) return '0 hour left';
    final totalMins = diff.inMinutes;
    final days = totalMins ~/ (60 * 24);
    final hours = (totalMins % (60 * 24)) ~/ 60;
    if (days > 0) return '$days day ${hours}h left';
    return '${math.max(0, hours)} hour left';
  }


  int _fuelPercent() {
    final raw = _v['fuel_percent'] ?? _b['fuel_percent'];
    final p = (raw is int) ? raw : int.tryParse((raw ?? '').toString());
    return (p ?? 100).clamp(0, 100);
  }

  String _typeHint(String type) {
    switch (type.trim().toLowerCase()) {
      case 'sedan':
        return 'Good for short travel';
      case 'hatchback':
        return 'Easy parking, city trips';
      case 'crossover':
        return 'Versatile daily travel';
      case 'coupe':
        return 'Sporty and stylish';
      case 'suv':
        return 'Comfort for family trips';
      case 'pick up':
      case 'pickup':
        return 'Strong for carrying items';
      case 'mpv':
        return 'Best for group travel';
      case 'van':
        return 'Large capacity travel';
      default:
        return 'Comfortable ride';
    }
  }

  String _transHint(String trans) {
    switch (trans.trim().toLowerCase()) {
      case 'auto':
      case 'automatic':
        return 'Good for new learner';
      case 'manual':
        return 'More control, confident drive';
      default:
        return 'Smooth driving';
    }
  }

  Future<void> _copyDirection() async {
    final addr = _dropoff;
    await Clipboard.setData(ClipboardData(text: addr));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Address copied. Paste into Google Maps.')),
    );
  }

  Future<void> _changeDropoff() async {
    final chosen = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        var tmp = _dropoff;
        return StatefulBuilder(
          builder: (ctx, setS) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Change drop off location', style: TextStyle(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 8),
                    ..._outlets.map((o) => RadioListTile<String>(
                          value: o,
                          groupValue: tmp,
                          title: Text(o, style: const TextStyle(fontSize: 13)),
                          onChanged: (v) => setS(() => tmp = v ?? tmp),
                        )),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton(
                            onPressed: () => Navigator.of(ctx).pop(tmp),
                            child: const Text('Save'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (chosen == null) return;
    setState(() => _dropoff = chosen);

    // Try to persist (only if your DB has a column, else silently ignore).
    final bookingId = (_b['booking_id'] ?? '').toString();
    if (bookingId.isEmpty) return;
    try {
      await _supa.from('booking').update({'dropoff_location': chosen}).eq('booking_id', bookingId);
    } catch (_) {
      // If column doesn't exist or RLS blocks it, keep UI-only.
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final photoPath = (_v['vehicle_photo_path'] ?? '').toString();
    final photoUrl = photoPath.isEmpty ? '' : _vehiclePhotoPublicUrl(photoPath);

    final type = (_v['vehicle_type'] ?? '').toString();
    final seats = (_v['seat_capacity'] ?? _v['seats'] ?? '').toString();
    final trans = (_v['transmission_type'] ?? '').toString();
    final fuelType = (_v['fuel_type'] ?? '').toString();
    final plate = (_v['vehicle_plate_no'] ?? '').toString();
    final color = (_v['vehicle_color'] ?? _v['color'] ?? 'White').toString();

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
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
              children: [
                // Car picture
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: photoUrl.isEmpty
                        ? Container(
                            color: cs.surfaceContainerHighest,
                            alignment: Alignment.center,
                            child: const Icon(Icons.directions_car_rounded, size: 56),
                          )
                        : Image.network(
                            photoUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              color: cs.surfaceContainerHighest,
                              alignment: Alignment.center,
                              child: const Icon(Icons.image_not_supported_outlined),
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 12),

                // Name + status
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _carName(),
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: _isActive ? Colors.green.withOpacity(0.12) : Colors.grey.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: _isActive ? Colors.green.withOpacity(0.35) : Colors.grey.withOpacity(0.35),
                        ),
                      ),
                      child: Text(
                        _statusLabel,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                          color: _isActive ? Colors.green.shade800 : Colors.grey.shade800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Fuel
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Fuel ${_fuelPercent()}%',
                        style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w700),
                      ),
                    ),
                    SizedBox(
                      width: 120,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(value: _fuelPercent() / 100.0, minHeight: 8),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 14),

                // Time card
                _SectionCard(
                  title: 'Time',
                  trailing: Text(
                    _hoursLeftText(),
                    style: TextStyle(color: Colors.green.shade800, fontWeight: FontWeight.w800, fontSize: 12),
                  ),
                  child: Text(
                    _timeRangeText(),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),

                const SizedBox(height: 12),

                // Drop off / return
                _SectionCard(
                  title: 'Nearest Drop Off Location',
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(
                        onPressed: _copyDirection,
                        child: const Text('Direction'),
                      ),
                      TextButton(
                        onPressed: _changeDropoff,
                        child: const Text('Others'),
                      ),
                    ],
                  ),
                  child: Text(
                    _dropoff,
                    style: TextStyle(color: Colors.grey.shade800, height: 1.3, fontWeight: FontWeight.w600),
                  ),
                ),

                const SizedBox(height: 14),

                // Car Details (same style as product)
                const Text('Car Details', style: TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _DetailTile(
                        title: type.isEmpty ? 'Car Type' : type,
                        lines: [
                          '${seats.isEmpty ? '-' : seats} Person',
                          _typeHint(type),
                        ],
                        icon: Icons.directions_car,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _DetailTile(
                        title: 'Fuel',
                        lines: [
                          fuelType.isEmpty ? '-' : fuelType,
                          'Balance: ${_fuelPercent()}%',
                        ],
                        icon: Icons.local_gas_station,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _DetailTile(
                        title: 'Transmission',
                        lines: [
                          trans.isEmpty ? '-' : trans,
                          _transHint(trans),
                        ],
                        icon: Icons.settings,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _DetailTile(
                        title: 'Other Details',
                        lines: [
                          '$color Color',
                          'Number Plate: ${plate.isEmpty ? '-' : plate}',
                        ],
                        icon: Icons.info_outline,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Back'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.child,
    this.trailing,
  });

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w900))),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _DetailTile extends StatelessWidget {
  final String title;
  final List<String> lines;
  final IconData icon;

  const _DetailTile({
    required this.title,
    required this.lines,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 22),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                ...lines.map(
                  (t) => Text(
                    t,
                    style: TextStyle(color: Colors.grey.shade700, height: 1.25),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
