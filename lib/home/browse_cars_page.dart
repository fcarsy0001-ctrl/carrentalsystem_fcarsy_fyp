import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import 'product_page.dart';

/// Browse cars page:
/// - AppBar with back button
/// - Search bar
/// - Date range selection (calendar)
/// - Filter sheet: Area, Car Brand, Type, Status, Price From/To + Clear Filter
class BrowseCarsPage extends StatefulWidget {
  const BrowseCarsPage({super.key});

  @override
  State<BrowseCarsPage> createState() => _BrowseCarsPageState();
}

class _BrowseCarsPageState extends State<BrowseCarsPage> {
  SupabaseClient get _supa => Supabase.instance.client;

  final _searchCtrl = TextEditingController();

  DateTime? _start;
  DateTime? _end;
  TimeOfDay _startTime = const TimeOfDay(hour: 22, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 22, minute: 0);

  String? _area;
  String? _brand;
  String? _type;
  String? _status;
  double? _priceFrom;
  double? _priceTo;

  late Future<List<_Vehicle>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
    _searchCtrl.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchCtrl.removeListener(_onSearchChanged);
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    // Debounce not required for small apps; keep simple.
    setState(() => _future = _load());
  }

  Future<List<_Vehicle>> _load() async {
    final q = _searchCtrl.text.trim();

    // IMPORTANT: Don't call `.order()` before applying filters.
    // `.order()` returns a TransformBuilder which doesn't expose filter methods
    // like `.or()`, `.ilike()`, `.eq()`, `.gte()`, `.lte()`.
    // Build filters first, then order right before awaiting.
    // Use select('*') so the app keeps working even if you add new columns later
    // (e.g. fuel_percent, vehicle_color).
    var builder = _supa.from('vehicle').select('*');

    // Search
    if (q.isNotEmpty) {
      final safe = q.replaceAll(',', ' ');
      builder = builder.or(
        'vehicle_brand.ilike.%$safe%,vehicle_model.ilike.%$safe%,vehicle_location.ilike.%$safe%,vehicle_type.ilike.%$safe%'
      );
    }

    // Filters
    if ((_area ?? '').trim().isNotEmpty) {
      builder = builder.ilike('vehicle_location', '%${_area!.trim()}%');
    }
    if ((_brand ?? '').trim().isNotEmpty) {
      builder = builder.ilike('vehicle_brand', '%${_brand!.trim()}%');
    }
    if ((_type ?? '').trim().isNotEmpty) {
      builder = builder.ilike('vehicle_type', '%${_type!.trim()}%');
    }
    if ((_status ?? '').trim().isNotEmpty) {
      builder = builder.eq('vehicle_status', _status!.trim());
    }
    if (_priceFrom != null) {
      builder = builder.gte('daily_rate', _priceFrom!);
    }
    if (_priceTo != null) {
      builder = builder.lte('daily_rate', _priceTo!);
    }

    // Default: show available if no status filter provided
    if ((_status ?? '').trim().isEmpty) {
      builder = builder.eq('vehicle_status', 'Available');
    }

    final rows = await builder.order('vehicle_id', ascending: false);
    var vehicles = (rows as List)
        .map((e) => _Vehicle.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();

    // Date availability filtering (exclude cars that have overlapping bookings)
    final sdt = _startDT;
    final edt = _endDT;
    if (sdt != null && edt != null) {
      try {
        final b = await _supa
            .from('booking')
            .select('vehicle_id, booking_status, rental_start, rental_end')
            .lt('rental_start', edt.toIso8601String())
            .gt('rental_end', sdt.toIso8601String());

        final bookedIds = <String>{};
        for (final raw in (b as List)) {
          final m = Map<String, dynamic>.from(raw as Map);
          final status = (m['booking_status'] ?? '').toString().trim().toLowerCase();
          if (status.contains('cancel') || status.contains('deactiv') || status.contains('deactive')) continue;
          bookedIds.add((m['vehicle_id'] ?? '').toString());
        }
        if (bookedIds.isNotEmpty) {
          vehicles = vehicles.where((v) => !bookedIds.contains(v.vehicleId)).toList();
        }
      } catch (_) {
        // If booking table / RLS policy isn't ready, ignore filtering.
      }
    }

    return vehicles;
  }

  String? _vehiclePhotoPublicUrl(String? path) {
    if (path == null || path.trim().isEmpty) return null;
    final safe = path.replaceFirst(RegExp(r'^/+'), '');
    return '${SupabaseConfig.supabaseUrl}/storage/v1/object/public/vehicle_photos/$safe';
  }

  DateTime? get _startDT {
    if (_start == null) return null;
    return DateTime(_start!.year, _start!.month, _start!.day, _startTime.hour, _startTime.minute);
  }

  DateTime? get _endDT {
    if (_end == null) return null;
    return DateTime(_end!.year, _end!.month, _end!.day, _endTime.hour, _endTime.minute);
  }

  String get _dateLabel {
    if (_start == null || _end == null) return 'Select date';
    return '${_start!.day}/${_start!.month}/${_start!.year} - ${_end!.day}/${_end!.month}/${_end!.year}';
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final initialStart = _start ?? now;
    final initialEnd = _end ?? now.add(const Duration(days: 2));
    final picked = await showDateRangePicker(
      context: context,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365)),
      initialDateRange: DateTimeRange(start: initialStart, end: initialEnd),
    );
    if (picked == null) return;

    // Optional: also pick times to match the "10pm - 10pm" example.
    final st = await showTimePicker(
      context: context,
      initialTime: _startTime,
    );
    if (st != null) _startTime = st;

    final et = await showTimePicker(
      context: context,
      initialTime: _endTime,
    );
    if (et != null) _endTime = et;

    setState(() {
      _start = picked.start;
      _end = picked.end;
      _future = _load();
    });
  }

  void _clearFilters() {
    setState(() {
      _area = null;
      _brand = null;
      _type = null;
      _status = null;
      _priceFrom = null;
      _priceTo = null;
      _future = _load();
    });
  }

  Future<void> _openFilterSheet() async {
    final areaCtrl = TextEditingController(text: _area ?? '');
    final brandCtrl = TextEditingController(text: _brand ?? '');
    final typeCtrl = TextEditingController(text: _type ?? '');
    final statusCtrl = TextEditingController(text: _status ?? '');
    final priceFromCtrl = TextEditingController(text: _priceFrom?.toStringAsFixed(0) ?? '');
    final priceToCtrl = TextEditingController(text: _priceTo?.toStringAsFixed(0) ?? '');

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 8,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Filter', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
              const SizedBox(height: 12),
              _Field(label: 'Area', controller: areaCtrl),
              const SizedBox(height: 10),
              _Field(label: 'Car Brand', controller: brandCtrl),
              const SizedBox(height: 10),
              _Field(label: 'Type', controller: typeCtrl),
              const SizedBox(height: 10),
              _Field(label: 'Status', controller: statusCtrl, hint: 'Available'),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: _Field(label: 'Price From', controller: priceFromCtrl, keyboardType: TextInputType.number)),
                  const SizedBox(width: 12),
                  Expanded(child: _Field(label: 'Price To', controller: priceToCtrl, keyboardType: TextInputType.number)),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  TextButton(
                    onPressed: () {
                      areaCtrl.clear();
                      brandCtrl.clear();
                      typeCtrl.clear();
                      statusCtrl.clear();
                      priceFromCtrl.clear();
                      priceToCtrl.clear();
                    },
                    child: const Text('Clear filter'),
                  ),
                  const Spacer(),
                  FilledButton.tonal(
                    onPressed: () {
                      Navigator.pop(ctx);
                    },
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 10),
                  FilledButton(
                    onPressed: () {
                      setState(() {
                        _area = areaCtrl.text.trim().isEmpty ? null : areaCtrl.text.trim();
                        _brand = brandCtrl.text.trim().isEmpty ? null : brandCtrl.text.trim();
                        _type = typeCtrl.text.trim().isEmpty ? null : typeCtrl.text.trim();
                        _status = statusCtrl.text.trim().isEmpty ? null : statusCtrl.text.trim();
                        _priceFrom = double.tryParse(priceFromCtrl.text.trim());
                        _priceTo = double.tryParse(priceToCtrl.text.trim());
                        _future = _load();
                      });
                      Navigator.pop(ctx);
                    },
                    child: const Text('Apply'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  String _shortOutletLabel(String fullAddress) {
    final s = fullAddress.trim();
    if (s.startsWith('6,')) return '6, Jalan P. Ramlee';
    if (s.startsWith('111-109')) return '111-109, Jalan Malinja 3';
    // Fallback: show the first segment.
    final parts = s.split(',');
    return parts.isEmpty ? s : parts.first.trim();
  }

  Future<void> _openProduct(_Vehicle v) async {
    // Must be selected by user (not dummy data)
    if (_startDT == null || _endDT == null) {
      await _pickDateRange();
      if (_startDT == null || _endDT == null) return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProductPage(
          carName: v.title,
          priceText: v.dailyRate > 0 ? 'RM${v.dailyRate.toStringAsFixed(0)}/day' : 'RM6/hour',
          imageUrl: _vehiclePhotoPublicUrl(v.photoPath),
          fuelType: v.fuel,
          fuelPercent: v.fuelPercent,
          productLocation: _shortOutletLabel(v.location),
          startDateTime: _startDT,
          endDateTime: _endDT,
          address: v.location,
          carType: v.type,
          seatCapacity: v.seats,
          transmission: v.transmission,
          color: v.color,
          plateNo: v.plate,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('Browse Cars'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
          children: [
            _SearchBar(
              controller: _searchCtrl,
              onTapFilter: _openFilterSheet,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickDateRange,
                    icon: const Icon(Icons.calendar_month_outlined),
                    label: Text(_dateLabel, overflow: TextOverflow.ellipsis),
                  ),
                ),
                const SizedBox(width: 10),
                TextButton(
                  onPressed: _clearFilters,
                  child: const Text('Clear filter'),
                ),
              ],
            ),
            const SizedBox(height: 14),
            FutureBuilder<List<_Vehicle>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 22),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snap.hasError) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text('Failed to load vehicles: ${snap.error}'),
                  );
                }
                final vehicles = snap.data ?? const [];
                if (vehicles.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'No vehicles found.',
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                  );
                }

                return Column(
                  children: vehicles
                      .map(
                        (v) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _BrowseVehicleCard(
                            vehicle: v,
                            photoUrl: _vehiclePhotoPublicUrl(v.photoPath),
                            onTap: () => _openProduct(v),
                          ),
                        ),
                      )
                      .toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _Vehicle {
  final String vehicleId;
  final String brand;
  final String model;
  final String type;
  final String plate;
  final String transmission;
  final String fuel;
  final int seats;
  final double dailyRate;
  final String location;
  final String status;
  final String? photoPath;
  final int fuelPercent;
  final String color;

  const _Vehicle({
    required this.vehicleId,
    required this.brand,
    required this.model,
    required this.type,
    required this.plate,
    required this.transmission,
    required this.fuel,
    required this.seats,
    required this.dailyRate,
    required this.location,
    required this.status,
    required this.photoPath,
    required this.fuelPercent,
    required this.color,
  });

  String get title {
    final t = ('$brand $model').trim();
    return t.isEmpty ? vehicleId : t;
  }

  factory _Vehicle.fromMap(Map<String, dynamic> m) {
    int toInt(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse((v ?? '').toString()) ?? 0;
    }

    final fpRaw = m['fuel_percent'];
    final fuelPct = fpRaw == null ? 100 : toInt(fpRaw);

    return _Vehicle(
      vehicleId: (m['vehicle_id'] ?? '').toString(),
      brand: (m['vehicle_brand'] ?? '').toString(),
      model: (m['vehicle_model'] ?? '').toString(),
      type: (m['vehicle_type'] ?? '').toString(),
      plate: (m['vehicle_plate_no'] ?? '').toString(),
      transmission: (m['transmission_type'] ?? '').toString(),
      fuel: (m['fuel_type'] ?? '').toString(),
      seats: (m['seat_capacity'] is int)
          ? (m['seat_capacity'] as int)
          : int.tryParse((m['seat_capacity'] ?? '0').toString()) ?? 0,
      dailyRate: (m['daily_rate'] is num)
          ? (m['daily_rate'] as num).toDouble()
          : double.tryParse((m['daily_rate'] ?? '0').toString()) ?? 0,
      location: (m['vehicle_location'] ?? '').toString(),
      status: (m['vehicle_status'] ?? '').toString(),
      photoPath: m['vehicle_photo_path']?.toString(),
      fuelPercent: fuelPct.clamp(0, 100),
      color: ((m['vehicle_color'] ?? '').toString().trim().isEmpty)
          ? 'White'
          : (m['vehicle_color'] ?? '').toString(),
    );
  }
}

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onTapFilter;

  const _SearchBar({
    required this.controller,
    required this.onTapFilter,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: cs.surfaceContainerHighest.withOpacity(0.5),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.search_rounded),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: 'Search by model, location, type…',
                isDense: true,
                border: InputBorder.none,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Filter',
            onPressed: onTapFilter,
            icon: const Icon(Icons.tune_rounded),
          ),
        ],
      ),
    );
  }
}

class _BrowseVehicleCard extends StatelessWidget {
  final _Vehicle vehicle;
  final String? photoUrl;
  final VoidCallback onTap;

  const _BrowseVehicleCard({
    required this.vehicle,
    required this.photoUrl,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Row(
          children: [
            SizedBox(
              width: 120,
              height: 92,
              child: photoUrl == null
                  ? Container(
                      color: cs.surfaceContainerHighest,
                      alignment: Alignment.center,
                      child: const Icon(Icons.directions_car_rounded, size: 34),
                    )
                  : Image.network(
                      photoUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: cs.surfaceContainerHighest,
                        alignment: Alignment.center,
                        child: const Icon(Icons.image_not_supported_outlined),
                      ),
                    ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      vehicle.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${vehicle.type} • ${vehicle.seats <= 0 ? '-' : vehicle.seats} seats',
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            vehicle.dailyRate > 0
                                ? 'RM${vehicle.dailyRate.toStringAsFixed(0)}/day'
                                : 'RM6/hour',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      vehicle.location.isEmpty ? '-' : vehicle.location,
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final String label;
  final String? hint;
  final TextEditingController controller;
  final TextInputType? keyboardType;

  const _Field({
    required this.label,
    required this.controller,
    this.hint,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          decoration: InputDecoration(
            hintText: hint,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            isDense: true,
          ),
        ),
      ],
    );
  }
}
