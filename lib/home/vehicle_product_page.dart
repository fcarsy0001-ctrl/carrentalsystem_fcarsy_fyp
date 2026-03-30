import 'dart:math' as math;

import 'package:flutter/material.dart';

class VehicleProductPage extends StatefulWidget {
  final String vehicleId;
  final String carName;
  final double dailyRate;
  final String vehicleType;
  final int seatCapacity;
  final String transmissionType;
  final String fuelType;
  final int fuelPercent;
  final String vehicleLocation;
  final String plateNo;
  final String? color;
  final String? photoUrl;

  const VehicleProductPage({
    super.key,
    required this.vehicleId,
    required this.carName,
    required this.dailyRate,
    required this.vehicleType,
    required this.seatCapacity,
    required this.transmissionType,
    required this.fuelType,
    required this.fuelPercent,
    required this.vehicleLocation,
    required this.plateNo,
    this.color,
    this.photoUrl,
  });

  @override
  State<VehicleProductPage> createState() => _VehicleProductPageState();
}

class _VehicleProductPageState extends State<VehicleProductPage> {
  DateTime? _start;
  DateTime? _end;

  // Tax rates (adjust if your project requires different values).
  static const double _sstRate = 0.06; // 6%
  static const double _gstRate = 0.00;

  String _seatLabel(int seats) {
    if (seats <= 2) return '1-2 Person';
    if (seats <= 5) return '3-5 Person';
    if (seats <= 7) return '6-7 Person';
    return '$seats Person';
  }

  String _typeDesc(String raw) {
    final t = raw.trim().toLowerCase();
    switch (t) {
      case 'sedan':
        return 'Good for short travel';
      case 'hatchback':
        return 'Easy city parking';
      case 'crossover':
        return 'Balanced for daily use';
      case 'coupe':
        return 'Sporty compact ride';
      case 'suv':
        return 'Best for family trips';
      case 'pick up':
      case 'pickup':
      case 'pick-up':
        return 'Great for cargo use';
      case 'mpv':
        return 'Comfortable for group';
      case 'van':
        return 'Extra passenger space';
      default:
        return 'Comfortable daily drive';
    }
  }

  String _transDesc(String raw) {
    final t = raw.trim().toLowerCase();
    if (t == 'auto' || t == 'automatic') return 'Good for new learner';
    if (t == 'manual') return 'More control, for confident drivers';
    return 'Smooth driving experience';
  }

  String _locationTitle(String address) {
    final a = address.toLowerCase();
    if (a.contains('kuala lumpur')) return 'Kuala Lumpur';
    return 'Outlet';
  }

  String _hourLabel(int hour) {
    final displayHour = hour % 12 == 0 ? 12 : hour % 12;
    final suffix = hour >= 12 ? 'PM' : 'AM';
    return '$displayHour:00 $suffix';
  }

  Future<TimeOfDay?> _pickHourOnly({
    required String title,
    required TimeOfDay initialTime,
  }) async {
    final pickedHour = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: SizedBox(
            height: 420,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Text(
                    title,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.builder(
                    itemCount: 24,
                    itemBuilder: (context, index) {
                      final selected = index == initialTime.hour;
                      return ListTile(
                        title: Text(_hourLabel(index)),
                        trailing: selected ? const Icon(Icons.check_rounded) : null,
                        onTap: () => Navigator.of(ctx).pop(index),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (pickedHour == null) return null;
    return TimeOfDay(hour: pickedHour, minute: 0);
  }

  Future<void> _pickRentalTime() async {
    final now = DateTime.now();

    final initialStart = _start ?? now;
    final initialEnd = _end ?? now.add(const Duration(days: 1));

    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 2, 12, 31),
      initialDateRange: DateTimeRange(
        start: DateTime(initialStart.year, initialStart.month, initialStart.day),
        end: DateTime(initialEnd.year, initialEnd.month, initialEnd.day),
      ),
    );

    if (range == null) return;

    final startTime = await _pickHourOnly(
      title: 'Select start hour',
      initialTime: _start != null
          ? TimeOfDay(hour: _start!.hour, minute: 0)
          : TimeOfDay(hour: now.hour, minute: 0),
    );
    if (startTime == null) return;

    final endTime = await _pickHourOnly(
      title: 'Select end hour',
      initialTime: _end != null
          ? TimeOfDay(hour: _end!.hour, minute: 0)
          : TimeOfDay(hour: startTime.hour, minute: 0),
    );
    if (endTime == null) return;

    final start = DateTime(
      range.start.year,
      range.start.month,
      range.start.day,
      startTime.hour,
      0,
    );

    final end = DateTime(
      range.end.year,
      range.end.month,
      range.end.day,
      endTime.hour,
      0,
    );

    if (!end.isAfter(start)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('End time must be after start time.')),
      );
      return;
    }

    setState(() {
      _start = start;
      _end = end;
    });
  }

  void _handleBookNow() async {
    // This button is only shown after the user selects a valid rental time.
    if (_start == null || _end == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select rental date & time first.')),
      );
      return;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Booking prepared: $_chargeDays day(s) • Total RM${_grandTotal.toStringAsFixed(2)}',
        ),
      ),
    );
  }

  String _fmtDate(DateTime d) => '${d.day}/${d.month}/${d.year}';

  String _fmtTime(DateTime d) {
    int h = d.hour;
    final m = d.minute.toString().padLeft(2, '0');
    final suffix = h >= 12 ? 'pm' : 'am';
    h = h % 12;
    if (h == 0) h = 12;
    return '$h:$m$suffix';
  }

  String get _timeText {
    if (_start == null || _end == null) return 'Select date';
    return '${_fmtDate(_start!)} - ${_fmtDate(_end!)}  ${_fmtTime(_start!)} - ${_fmtTime(_end!)}';
  }

  int get _chargeDays {
    if (_start == null || _end == null) return 0;
    final mins = _end!.difference(_start!).inMinutes;
    if (mins <= 0) return 0;
    return (mins / (24 * 60)).ceil();
  }

  double get _subTotal => _chargeDays * widget.dailyRate;
  double get _sst => _subTotal * _sstRate;
  double get _gst => _subTotal * _gstRate;
  double get _grandTotal => _subTotal + _sst + _gst;

  double get _fuelValue => (widget.fuelPercent.clamp(0, 100)) / 100.0;

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    // dart:math max() returns num, but Container.height expects double.
    final double barHeight = math.max(240.0, h * 0.25).toDouble();

    final bool hasDate = _start != null && _end != null;

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        centerTitle: true,
        title: Text(
          widget.carName,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      // IMPORTANT: Booking bar only appears AFTER user selects rental date & time.
      bottomNavigationBar: hasDate
          ? SafeArea(
              top: false,
              child: Container(
                height: barHeight,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  border: Border(top: BorderSide(color: Colors.grey.shade200)),
                ),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'Total Price',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                        const Spacer(),
                        Text(
                          '$_chargeDays day(s)',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '$_chargeDays day × RM${widget.dailyRate.toStringAsFixed(0)} = RM${_subTotal.toStringAsFixed(2)}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    _MoneyRow(label: 'SST (${(_sstRate * 100).toStringAsFixed(0)}%)', value: _sst),
                    _MoneyRow(label: 'GST (${(_gstRate * 100).toStringAsFixed(0)}%)', value: _gst),
                    const Divider(height: 18),
                    Row(
                      children: [
                        const Text('Total', style: TextStyle(fontWeight: FontWeight.w900)),
                        const Spacer(),
                        Text(
                          'RM${_grandTotal.toStringAsFixed(2)}',
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      height: 46,
                      child: ElevatedButton(
                        onPressed: _handleBookNow,
                        child: const Text('Booking Now'),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            // Extra bottom padding so details remain scrollable above the fixed bar.
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _CarImage(photoUrl: widget.photoUrl, fallbackText: widget.carName),

                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
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
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'Fuel ${widget.fuelPercent.clamp(0, 100)}%',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 6),
                          SizedBox(
                            width: 130,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: LinearProgressIndicator(
                                value: _fuelValue,
                                minHeight: 8,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 10),

                const _SectionTitle('Booking Details'),
                _KVRow(label: 'Product location', value: _locationTitle(widget.vehicleLocation)),

                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 130,
                        child: Text(
                          'Time',
                          style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w700),
                        ),
                      ),
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: InkWell(
                            onTap: _pickRentalTime,
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey.shade300),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.calendar_month_outlined, size: 18, color: Colors.grey.shade700),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _timeText,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        color: (_start == null || _end == null) ? Colors.grey.shade600 : null,
                                      ),
                                    ),
                                  ),
                                  Icon(Icons.chevron_right, color: Colors.grey.shade600),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                  child: Text(
                    '> ${widget.vehicleLocation}',
                    style: TextStyle(color: Colors.grey.shade700, height: 1.35),
                  ),
                ),

                const SizedBox(height: 18),

                const _SectionTitle('Car Details'),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _DetailTile(
                              title: widget.vehicleType.isEmpty ? 'Type' : widget.vehicleType,
                              lines: [
                                _seatLabel(widget.seatCapacity),
                                _typeDesc(widget.vehicleType),
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
                                'Balance: ${widget.fuelPercent.clamp(0, 100)}%',
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
                                widget.transmissionType.isEmpty ? '-' : widget.transmissionType,
                                _transDesc(widget.transmissionType),
                              ],
                              icon: Icons.settings,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _DetailTile(
                              title: 'Other Details',
                              lines: [
                                '${(widget.color ?? '-').trim().isEmpty ? '-' : widget.color} Color',
                                'Number Plate: ${widget.plateNo}',
                              ],
                              icon: Icons.info_outline,
                            ),
                          ),
                        ],
                      ),
                    ],
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

class _MoneyRow extends StatelessWidget {
  final String label;
  final double value;

  const _MoneyRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Text(label, style: TextStyle(color: Colors.grey.shade700)),
          const SizedBox(height: 10),
          Text('RM${value.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _CarImage extends StatelessWidget {
  final String? photoUrl;
  final String fallbackText;

  const _CarImage({required this.photoUrl, required this.fallbackText});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Container(
        width: double.infinity,
        color: cs.surfaceContainerHighest,
        child: (photoUrl == null || photoUrl!.trim().isEmpty)
            ? const Center(child: Icon(Icons.directions_car_rounded, size: 56))
            : Image.network(
                photoUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Center(
                  child: Icon(Icons.image_not_supported_outlined, size: 40),
                ),
              ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Text(
        text,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
      ),
    );
  }
}

class _KVRow extends StatelessWidget {
  final String label;
  final String value;

  const _KVRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
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
