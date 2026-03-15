import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/driver_license_service.dart';
import 'booking_page.dart';

class ProductPage extends StatefulWidget {
  ProductPage({
    super.key,
    String? vehicleId,
    String? brand,
    String? model,
    String? type,
    String? plate,
    String? transmission,
    String? fuelType,
    int? seats,
    double? dailyRate,
    String? location,
    String? photoUrl,
    int? fuelPercent,
    String? color,
    String? carName,
    String? priceText,
    String? imageUrl,
    String? productLocation,
    DateTime? startDateTime,
    DateTime? endDateTime,
    String? address,
    String? carType,
    int? seatCapacity,
    String? plateNo,
  })  : vehicleId = _resolveVehicleId(vehicleId: vehicleId, plateNo: plateNo),
        brand = _resolveBrand(brand: brand, carName: carName),
        model = _resolveModel(model: model, carName: carName),
        type = _firstNonEmpty(type, second: carType, fallback: 'Vehicle'),
        plate = _firstNonEmpty(plate, second: plateNo, fallback: '-'),
        transmission = _firstNonEmpty(transmission, fallback: 'Auto'),
        fuelType = _firstNonEmpty(fuelType, fallback: 'Petrol'),
        seats = seats ?? seatCapacity ?? 4,
        dailyRate = dailyRate ?? _parseDailyRate(priceText),
        location = _resolveLocation(
          location: location,
          address: address,
          productLocation: productLocation,
        ),
        photoUrl = _firstNonEmptyOrNull(photoUrl, imageUrl),
        fuelPercent = fuelPercent,
        color = _firstNonEmptyOrNull(color),
        initialStartDateTime = startDateTime,
        initialEndDateTime = endDateTime;

  final String vehicleId;
  final String brand;
  final String model;
  final String type;
  final String plate;
  final String transmission;
  final String fuelType;
  final int seats;
  final double dailyRate;
  final String location;
  final String? photoUrl;
  final int? fuelPercent; // optional DB column
  final String? color; // optional DB column
  final DateTime? initialStartDateTime;
  final DateTime? initialEndDateTime;

  static String _clean(String? value) => value?.trim() ?? '';

  static String _firstNonEmpty(String? first, {String? second, String fallback = ''}) {
    final a = _clean(first);
    if (a.isNotEmpty) return a;
    final b = _clean(second);
    if (b.isNotEmpty) return b;
    return fallback;
  }

  static String? _firstNonEmptyOrNull([String? first, String? second]) {
    final value = _firstNonEmpty(first, second: second);
    return value.isEmpty ? null : value;
  }

  static List<String> _splitCarName(String? carName) {
    final raw = _clean(carName);
    if (raw.isEmpty) return const ['', ''];
    final parts = raw.split(RegExp(r'\s+'));
    if (parts.length == 1) return [parts.first, ''];
    return [parts.first, parts.skip(1).join(' ')];
  }

  static String _resolveVehicleId({String? vehicleId, String? plateNo}) {
    return _firstNonEmpty(vehicleId, second: plateNo, fallback: 'vehicle');
  }

  static String _resolveBrand({String? brand, String? carName}) {
    final direct = _clean(brand);
    if (direct.isNotEmpty) return direct;
    return _splitCarName(carName).first;
  }

  static String _resolveModel({String? model, String? carName}) {
    final direct = _clean(model);
    if (direct.isNotEmpty) return direct;
    return _splitCarName(carName).last;
  }

  static String _resolveLocation({
    String? location,
    String? address,
    String? productLocation,
  }) {
    return _firstNonEmpty(location, second: address, fallback: _clean(productLocation));
  }

  static double _parseDailyRate(String? priceText) {
    final raw = _clean(priceText).toLowerCase();
    if (raw.isEmpty) return 0;
    final match = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(raw);
    final amount = double.tryParse(match?.group(1) ?? '') ?? 0;
    if (raw.contains('/hour')) return amount * 24;
    return amount;
  }

  String get carName {
    final t = ('$brand $model').trim();
    return t.isEmpty ? vehicleId : t;
  }

  @override
  State<ProductPage> createState() => _ProductPageState();
}

class _ProductPageState extends State<ProductPage> {
  SupabaseClient get _supa => Supabase.instance.client;

  DateTime? _start;
  DateTime? _end;

  @override
  void initState() {
    super.initState();
    _start = widget.initialStartDateTime;
    _end = widget.initialEndDateTime;
  }

  // Pricing
  // Service fee = RM10 (base) + percentage (tiered by subtotal)
  static const double _serviceBaseFee = 10.0;
  static const double _sstRate = 0.06; // 6%

  bool get _hasTime => _start != null && _end != null;

  int get _fuelPercent => (widget.fuelPercent ?? 100).clamp(0, 100);

  double get _fuelValue => _fuelPercent / 100.0;

  double _hours(DateTime start, DateTime end) {
    final mins = end.difference(start).inMinutes;
    return math.max(0, mins) / 60.0;
  }

  double _hourlyRate() => widget.dailyRate / 24.0;

  double _rentalSubtotal(DateTime start, DateTime end) {
    final h = _hours(start, end);
    return _hourlyRate() * h;
  }

  double _serviceRateFor(double base) {
    // Rule (based on your message):
    // <100 => 1%, 100-199.99 => 3%, 200-299.99 => 5%, <=300 => 6%, >300 => 10%
    if (base < 100) return 0.01;
    if (base < 200) return 0.03;
    if (base < 300) return 0.05;
    if (base <= 300) return 0.06;
    return 0.10;
  }

  double _serviceFee(double base) => _serviceBaseFee + (base * _serviceRateFor(base));

  double _sst(double basePlusService) => basePlusService * _sstRate;

  String _fmtDate(DateTime d) => '${d.day}/${d.month}/${d.year}';

  String _fmtTime(DateTime d) {
    var h = d.hour;
    final m = d.minute.toString().padLeft(2, '0');
    final ap = h >= 12 ? 'pm' : 'am';
    h %= 12;
    if (h == 0) h = 12;
    return '$h:$m$ap';
  }

  String get _timeText {
    if (!_hasTime) return 'Select date';
    return '${_fmtDate(_start!)} - ${_fmtDate(_end!)}  ${_fmtTime(_start!)} - ${_fmtTime(_end!)}';
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

  Future<void> _pickDateTimeRange() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 2, 12, 31),
      initialDateRange: (_start != null && _end != null)
          ? DateTimeRange(start: _start!, end: _end!)
          : null,
    );
    if (range == null) return;

    final startTime = await showTimePicker(
      context: context,
      initialTime: _start != null
          ? TimeOfDay(hour: _start!.hour, minute: _start!.minute)
          : const TimeOfDay(hour: 10, minute: 0),
    );
    if (startTime == null) return;

    final endTime = await showTimePicker(
      context: context,
      initialTime: _end != null
          ? TimeOfDay(hour: _end!.hour, minute: _end!.minute)
          : const TimeOfDay(hour: 10, minute: 0),
    );
    if (endTime == null) return;

    final start = DateTime(
      range.start.year,
      range.start.month,
      range.start.day,
      startTime.hour,
      startTime.minute,
    );
    var end = DateTime(
      range.end.year,
      range.end.month,
      range.end.day,
      endTime.hour,
      endTime.minute,
    );
    if (!end.isAfter(start)) {
      end = end.add(const Duration(days: 1));
    }
    setState(() {
      _start = start;
      _end = end;
    });
  }

  Future<bool> _ensureLicenseApproved() async {
    final snap = await DriverLicenseService(_supa).getSnapshot();
    if (snap.state == DriverLicenseState.approved) return true;

    if (!mounted) return false;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Driver licence required'),
        content: const Text(
          'Please submit your driver licence and wait for approval before booking.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    return false;
  }

  Future<void> _goBooking() async {
    if (!_hasTime) {
      await _pickDateTimeRange();
      return;
    }
    final ok = await _ensureLicenseApproved();
    if (!ok) return;
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BookingPage(
          vehicleId: widget.vehicleId,
          carName: widget.carName,
          plate: widget.plate,
          type: widget.type,
          transmission: widget.transmission,
          fuelType: widget.fuelType,
          seats: widget.seats,
          dailyRate: widget.dailyRate,
          location: widget.location,
          photoUrl: widget.photoUrl,
          start: _start!,
          end: _end!,
          fuelPercent: _fuelPercent,
          color: (widget.color ?? 'White'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final valueStyle = const TextStyle(fontSize: 14, fontWeight: FontWeight.w600);
    final labelStyle = TextStyle(fontSize: 13, color: Colors.grey.shade700, fontWeight: FontWeight.w600);
    final cs = Theme.of(context).colorScheme;

    Widget buildImage() {
      return AspectRatio(
        aspectRatio: 16 / 9,
        child: widget.photoUrl == null
            ? Container(
                color: cs.surfaceContainerHighest,
                alignment: Alignment.center,
                child: const Icon(Icons.directions_car_rounded, size: 56),
              )
            : Image.network(
                widget.photoUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: cs.surfaceContainerHighest,
                  alignment: Alignment.center,
                  child: const Icon(Icons.image_not_supported_outlined),
                ),
              ),
      );
    }

    Widget detailRow(String label, Widget value) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 128, child: Text(label, style: labelStyle)),
            Expanded(child: value),
          ],
        ),
      );
    }

    // Bottom bar shown only after date/time selected.
    final bottomBar = !_hasTime
        ? null
        : SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                border: Border(top: BorderSide(color: Colors.grey.shade300)),
              ),
              child: Builder(
                builder: (_) {
                  final hours = _hours(_start!, _end!);
                  final hourlyRate = _hourlyRate();
                  final subtotal = _rentalSubtotal(_start!, _end!);
                  final rate = _serviceRateFor(subtotal);
                  final svc = _serviceFee(subtotal);
                  final sst = _sst(subtotal + svc);
                  final total = subtotal + svc + sst;
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'RM${widget.dailyRate.toStringAsFixed(0)} Ã· 24 = RM${hourlyRate.toStringAsFixed(2)}/hr',
                              style: const TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                          Text(
                            'RM${subtotal.toStringAsFixed(2)}',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Hours: ${hours.toStringAsFixed(hours % 1 == 0 ? 0 : 2)}',
                              style: TextStyle(color: Colors.grey.shade700),
                            ),
                          ),
                          Text(
                            'Ã— RM${hourlyRate.toStringAsFixed(2)}',
                            style: TextStyle(color: Colors.grey.shade700),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Service fee (RM10 + ${(rate * 100).toStringAsFixed(0)}%)',
                              style: TextStyle(color: Colors.grey.shade700),
                            ),
                          ),
                          Text('RM${svc.toStringAsFixed(2)}', style: TextStyle(color: Colors.grey.shade700)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: Text('SST (6%)', style: TextStyle(color: Colors.grey.shade700)),
                          ),
                          Text('RM${sst.toStringAsFixed(2)}', style: TextStyle(color: Colors.grey.shade700)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Total',
                              style: TextStyle(fontWeight: FontWeight.w900),
                            ),
                          ),
                          Text(
                            'RM${total.toStringAsFixed(2)}',
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        height: 44,
                        child: FilledButton(
                          onPressed: _goBooking,
                          child: const Text('Book Now'),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          );

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        centerTitle: true,
        title: Text(widget.carName, overflow: TextOverflow.ellipsis),
      ),
      bottomNavigationBar: bottomBar,
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.only(bottom: _hasTime ? 8 : 16),
          children: [
            buildImage(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.carName,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'RM${widget.dailyRate.toStringAsFixed(0)}/day',
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('Fuel $_fuelPercent%', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      SizedBox(
                        width: 110,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(value: _fuelValue, minHeight: 8),
                        ),
                      ),
                    ],
                  )
                ],
              ),
            ),
            const SizedBox(height: 10),

            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text('Booking Details', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
            ),
            detailRow('Outlet', Text(widget.location.isEmpty ? '-' : widget.location, style: valueStyle)),
            detailRow(
              'Time',
              InkWell(
                onTap: _pickDateTimeRange,
                child: Text(
                  _timeText,
                  style: valueStyle.copyWith(
                    decoration: !_hasTime ? TextDecoration.underline : TextDecoration.none,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 12),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text('Car Details', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
            ),
            const SizedBox(height: 10),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _DetailTile(
                          title: widget.type.isEmpty ? 'Type' : widget.type,
                          lines: [
                            '${widget.seats <= 0 ? '3-5' : widget.seats} Person',
                            _typeHint(widget.type),
                          ],
                          icon: Icons.directions_car,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _DetailTile(
                          title: 'Fuel',
                          lines: [
                            widget.fuelType.isEmpty ? '-' : widget.fuelType,
                            'Balance: $_fuelPercent%',
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
                            widget.transmission.isEmpty ? '-' : widget.transmission,
                            _transHint(widget.transmission),
                          ],
                          icon: Icons.settings,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _DetailTile(
                          title: 'Other Details',
                          lines: [
                            '${(widget.color ?? 'White')} Color',
                            'Number Plate: ${widget.plate.isEmpty ? '-' : widget.plate}',
                          ],
                          icon: Icons.info_outline,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 18),
          ],
        ),
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
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
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


