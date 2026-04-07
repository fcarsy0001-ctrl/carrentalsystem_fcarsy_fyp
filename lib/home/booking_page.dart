import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'contract_page.dart';
import '../services/booking_availability_service.dart';
import '../services/promotion_service.dart';
import '../shell/main_shell.dart';

class BookingPage extends StatefulWidget {
  const BookingPage({
    super.key,
    required this.vehicleId,
    required this.carName,
    required this.plate,
    required this.type,
    required this.transmission,
    required this.fuelType,
    required this.seats,
    required this.dailyRate,
    required this.location,
    required this.start,
    required this.end,
    required this.fuelPercent,
    required this.color,
    this.photoUrl,
  });

  final String vehicleId;
  final String carName;
  final String plate;
  final String type;
  final String transmission;
  final String fuelType;
  final int seats;
  final double dailyRate;
  final String location;
  final DateTime start;
  final DateTime end;
  final int fuelPercent;
  final String color;
  final String? photoUrl;

  @override
  State<BookingPage> createState() => _BookingPageState();
}

class _BookingPageState extends State<BookingPage> {
  SupabaseClient get _supa => Supabase.instance.client;

  late final PromotionService _promo = PromotionService(_supa);

  // Refundable security deposit (shown in Payment page)
  static const double _securityDeposit = 300.0;

  // Service fee = RM10 (base) + percentage (tiered by subtotal)
  static const double _serviceBaseFee = 10.0;
  static const double _sstRate = 0.06; // 6%

  final Map<String, bool> _selected = {};

  final _voucherCtrl = TextEditingController();
  bool _submitting = false;
  String? _voucherCode;
  String? _voucherPromoId;
  double _voucherDiscount = 0.0;
  String? _voucherMsg;
  bool _applyingVoucher = false;
  bool _loadingBestVoucher = false;
  List<Map<String, dynamic>> _voucherOptions = const [];

  final List<_InsuranceOption> _options = const [
    _InsuranceOption('Basic coverage', 0),
    _InsuranceOption('Standard', 15),
    _InsuranceOption('Full protection', 35),
    _InsuranceOption('Outstation protection', 20),
    _InsuranceOption('Vehicle downtime protection', 25),
  ];

  @override
  void initState() {
    super.initState();
    for (final o in _options) {
      _selected[o.name] = false;
    }
    _autoApplyBestVoucher();
  }

  @override
  void dispose() {
    _voucherCtrl.dispose();
    super.dispose();
  }

  double _hours() {
    final mins = widget.end.difference(widget.start).inMinutes;
    return math.max(0, mins) / 60.0;
  }

  double _hourlyRate() => widget.dailyRate / 24.0;

  double _rentalSubtotal() => _hourlyRate() * _hours();

  double _rentalAfterVoucher(double rentalRaw) {
    final d = _voucherDiscount;
    if (d <= 0) return rentalRaw;
    return (rentalRaw - d).clamp(0, rentalRaw).toDouble();
  }

  bool _isPromoActive(Map<String, dynamic> promo) {
    final active = promo['active'];
    final isActive = active == null || active == true || active.toString().toLowerCase() == 'true';
    if (!isActive) return false;

    final now = DateTime.now();
    final start = DateTime.tryParse(_s(promo['start_at']));
    final end = DateTime.tryParse(_s(promo['end_at']));
    if (start != null) {
      final startOfDay = DateTime(start.year, start.month, start.day);
      if (now.isBefore(startOfDay)) return false;
    }
    if (end != null) {
      final endOfDay = DateTime(end.year, end.month, end.day, 23, 59, 59, 999);
      if (now.isAfter(endOfDay)) return false;
    }
    return true;
  }

  String _s(dynamic value) => value == null ? '' : value.toString().trim();

  bool _isVoucherUsedRow(Map<String, dynamic> row) {
    final usedBookingId = _s(row['used_booking_id']);
    final usedAt = _s(row['used_at']);
    return usedBookingId.isNotEmpty || usedAt.isNotEmpty;
  }

  Future<void> _autoApplyBestVoucher() async {
    if (_loadingBestVoucher || _voucherCode != null || _voucherCtrl.text.trim().isNotEmpty) {
      return;
    }

    setState(() => _loadingBestVoucher = true);
    try {
      final myVouchers = await _promo.fetchMyVouchers();
      final activePromos = await _promo.fetchActivePromotions();
      final rentalRaw = _rentalSubtotal();
      final optionsByPromoId = <String, Map<String, dynamic>>{};
      final claimedPromoIds = <String>{};
      final usedPromoIds = <String>{};

      for (final row in myVouchers) {
        final used = _isVoucherUsedRow(row);
        final rowPromoId = _s(row['promo_id']);
        if (used && rowPromoId.isNotEmpty) {
          usedPromoIds.add(rowPromoId);
        }

        final promoRaw = row['promotion'];
        if (promoRaw is! Map) continue;
        final promo = Map<String, dynamic>.from(promoRaw as Map);
        final promoId = rowPromoId.isEmpty ? _s(promo['promo_id']) : rowPromoId;
        if (promoId.isEmpty) continue;
        if (used) {
          usedPromoIds.add(promoId);
          continue;
        }
        if (!_isPromoActive(promo)) continue;

        final discount = _promo.computeDiscount(promo: promo, rentalSubtotal: rentalRaw);
        if (discount <= 0) continue;

        claimedPromoIds.add(promoId);
        optionsByPromoId[promoId] = {
          'promo_id': promoId,
          'code': _s(promo['code']),
          'title': _s(promo['title']),
          'promotion': promo,
          'discount': discount,
          'claimed': true,
        };
      }

      for (final promo in activePromos) {
        final promoId = _s(promo['promo_id']);
        if (promoId.isEmpty || optionsByPromoId.containsKey(promoId) || usedPromoIds.contains(promoId)) continue;
        if (!_isPromoActive(promo)) continue;
        final discount = _promo.computeDiscount(promo: promo, rentalSubtotal: rentalRaw);
        if (discount <= 0) continue;

        optionsByPromoId[promoId] = {
          'promo_id': promoId,
          'code': _s(promo['code']),
          'title': _s(promo['title']),
          'promotion': promo,
          'discount': discount,
          'claimed': claimedPromoIds.contains(promoId),
        };
      }

      final options = optionsByPromoId.values.toList()
        ..sort((a, b) => (((b['discount'] ?? 0) as num).toDouble()).compareTo((((a['discount'] ?? 0) as num).toDouble())));

      if (!mounted) return;
      setState(() => _voucherOptions = options);
      if (options.isEmpty) return;

      final best = options.first;
      final code = _s(best['code']);
      final discount = ((best['discount'] ?? 0) as num).toDouble();
      setState(() {
        _voucherCtrl.text = code;
        _voucherCode = code.isEmpty ? null : code;
        _voucherPromoId = _s(best['promo_id']).isEmpty ? null : _s(best['promo_id']);
        _voucherDiscount = discount;
        _voucherMsg = code.isEmpty
            ? 'Best voucher auto applied: -RM${discount.toStringAsFixed(2)}'
            : 'Best voucher auto applied: $code (-RM${discount.toStringAsFixed(2)})';
      });
    } catch (_) {
      // Keep checkout smooth even if voucher auto-fill fails.
    } finally {
      if (mounted) {
        setState(() => _loadingBestVoucher = false);
      }
    }
  }

  Future<void> _applyVoucher(double rentalRaw) async {
    final code = _voucherCtrl.text.trim();
    if (code.isEmpty) {
      setState(() {
        _voucherMsg = 'Enter voucher code.';
      });
      return;
    }

    setState(() {
      _applyingVoucher = true;
      _voucherMsg = null;
    });

    try {
      final promo = await _promo.getPromotionByCode(code);
      if (promo == null) {
        setState(() {
          _voucherCode = null;
          _voucherPromoId = null;
          _voucherDiscount = 0;
          _voucherMsg = 'Invalid voucher.';
        });
        return;
      }

      final promoData = Map<String, dynamic>.from(promo);
      final promoId = (promoData['promo_id'] ?? '').toString();
      if (promoId.isNotEmpty) {
        // claim best-effort (so user can see in My Vouchers)
        await _promo.claimVoucher(promoId: promoId);
      }

      final discount = _promo.computeDiscount(promo: promoData, rentalSubtotal: rentalRaw);
      if (discount <= 0) {
        final min = promoData['min_spend'];
        final minSpend = (min is num)
            ? min.toDouble()
            : double.tryParse((min ?? '0').toString()) ?? 0;
        setState(() {
          _voucherCode = null;
          _voucherPromoId = null;
          _voucherDiscount = 0;
          _voucherMsg = minSpend > 0
              ? 'Min spend RM${minSpend.toStringAsFixed(0)} not reached.'
              : 'Voucher not applicable.';
        });
        return;
      }

      final appliedCode = (promoData['code'] ?? code).toString();
      setState(() {
        _voucherCode = appliedCode;
        _voucherPromoId = promoId;
        _voucherDiscount = discount;
        _voucherMsg = 'Applied: ${_voucherCode ?? code} (-RM${discount.toStringAsFixed(2)})';
      });
    } catch (e) {
      setState(() {
        _voucherMsg = 'Apply failed: $e';
      });
    } finally {
      if (mounted) {
        setState(() => _applyingVoucher = false);
      }
    }
  }


  Future<void> _applyVoucherOption(Map<String, dynamic> option) async {
    final code = _s(option['code']);
    final promoId = _s(option['promo_id']);
    final discount = ((option['discount'] ?? 0) as num).toDouble();
    if (promoId.isNotEmpty) {
      try {
        await _promo.claimVoucher(promoId: promoId);
        option['claimed'] = true;
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _voucherMsg = 'Apply failed: $e';
        });
        return;
      }
    }

    setState(() {
      _voucherCtrl.text = code;
      _voucherCode = code.isEmpty ? null : code;
      _voucherPromoId = promoId.isEmpty ? null : promoId;
      _voucherDiscount = discount;
      _voucherMsg = code.isEmpty
          ? 'Voucher applied: -RM${discount.toStringAsFixed(2)}'
          : 'Voucher applied: $code (-RM${discount.toStringAsFixed(2)})';
    });
  }

  void _goHome() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const MainShell()),
      (route) => false,
    );
  }

  void _clearVoucher() {
    setState(() {
      _voucherCode = null;
      _voucherPromoId = null;
      _voucherDiscount = 0;
      _voucherMsg = 'Voucher removed.';
      _voucherCtrl.clear();
    });
  }

  double _insuranceTotal() {
    double sum = 0;
    for (final o in _options) {
      if (_selected[o.name] == true) sum += o.price;
    }
    return sum;
  }

  double _serviceRateFor(double base) {
    // Rule:
    // <100 => 1%, 100-199.99 => 3%, 200-299.99 => 5%, <=300 => 6%, >300 => 10%
    if (base < 100) return 0.01;
    if (base < 200) return 0.03;
    if (base < 300) return 0.05;
    if (base <= 300) return 0.06;
    return 0.10;
  }

  double _serviceFee(double base) => _serviceBaseFee + (base * _serviceRateFor(base));

  double _sst(double basePlusSvc) => basePlusSvc * _sstRate;

  String _fmtDate(DateTime d) => '${d.day}/${d.month}/${d.year}';

  String _fmtTime(DateTime d) {
    var h = d.hour;
    final m = d.minute.toString().padLeft(2, '0');
    final ap = h >= 12 ? 'pm' : 'am';
    h %= 12;
    if (h == 0) h = 12;
    return '$h:$m$ap';
  }

  Future<Map<String, dynamic>?> _loadUserRow() async {
    final u = _supa.auth.currentUser;
    if (u == null) return null;
    try {
      final row = await _supa
          .from('app_user')
          .select('user_id, user_name, user_email, user_phone, user_icno, user_gender, driver_license_status')
          .eq('auth_uid', u.id)
          .maybeSingle();
      if (row == null) return null;
      return Map<String, dynamic>.from(row as Map);
    } catch (_) {
      return null;
    }
  }

  String _dateOnly(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  List<String> _selectedInsuranceNames() {
    final out = <String>[];
    for (final o in _options) {
      if (_selected[o.name] == true) out.add(o.name);
    }
    return out;
  }

  Future<void> _proceed({
    required double rentalSubtotal,
    required double voucherDiscount,
    required String? voucherCode,
    required String? voucherPromoId,
    required double insuranceTotal,
    required double serviceFee,
    required double sst,
    required double subTotal,
  }) async {
    if (_submitting) return;
    if (!widget.end.isAfter(widget.start)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('End time must be after start time.')),
      );
      return;
    }

    setState(() => _submitting = true);

    final u = _supa.auth.currentUser;
    if (u == null) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please login first.')));
      return;
    }

    // Get app_user.user_id (FK required by booking.user_id)
    final row = await _loadUserRow();
    final userId = (row?['user_id'] ?? '').toString();
    final email = (row?['user_email'] ?? u.email ?? '').toString();
    if (userId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('User profile not found.')));
      setState(() => _submitting = false);
      return;
    }

    final now = DateTime.now();
    // Many schemas use varchar(10) for IDs, so keep IDs <= 10 chars.
    // Format: BK + 8 digits (last 8 digits of epoch ms) => 10 chars.
    final bookingId = 'BK${(now.millisecondsSinceEpoch % 100000000).toString().padLeft(8, '0')}';

    final availabilitySvc = BookingAvailabilityService(_supa);
    try {
      final conflicts = await availabilitySvc.fetchConflictingBookings(
        vehicleId: widget.vehicleId,
        start: widget.start,
        end: widget.end,
      );
      if (conflicts.isNotEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'This car is already booked for the selected date and time. Please choose another slot.',
            ),
          ),
        );
        setState(() => _submitting = false);
        return;
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Availability check failed: $e')),
      );
      setState(() => _submitting = false);
      return;
    }

    if ((voucherPromoId ?? '').trim().isNotEmpty) {
      try {
        await _promo.claimVoucher(promoId: voucherPromoId!);
      } catch (e) {
        if (!mounted) return;
        _clearVoucher();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Voucher can no longer be used: $e')),
        );
        setState(() => _submitting = false);
        return;
      }
    }

    // Create booking (minimal fields to satisfy NOT NULL constraints)
    try {
      final insertMap = <String, dynamic>{
        'booking_id': bookingId,
        'user_id': userId,
        'vehicle_id': widget.vehicleId,
        'booking_date': _dateOnly(now),
        'rental_start': widget.start.toIso8601String(),
        'rental_end': widget.end.toIso8601String(),
        'hold_expires_at': now.add(const Duration(minutes: 15)).toIso8601String(),
        // Keep status short (some schemas use varchar(10)).
        'booking_status': 'Holding',
        'payment_option': 'Online',
        'total_rental_amount': subTotal,
      };

      // Optional columns (if you added them): voucher_code, voucher_discount
      if ((voucherCode ?? '').trim().isNotEmpty) {
        insertMap['voucher_code'] = voucherCode;
        insertMap['voucher_discount'] = voucherDiscount;
      }

      try {
        await _supa.from('booking').insert(insertMap);
      } catch (_) {
        // Fallback if the columns don't exist
        insertMap.remove('voucher_code');
        insertMap.remove('voucher_discount');
        await _supa.from('booking').insert(insertMap);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Create booking failed: $e')));
      setState(() => _submitting = false);
      return;
    }


    // Create contract row (required fields)
    // Keep contract_id <= 10 chars as well.
    final contractId = 'CT${(now.millisecondsSinceEpoch % 100000000).toString().padLeft(8, '0')}';
    try {
      await _supa.from('contract').insert({
        'contract_id': contractId,
        'booking_id': bookingId,
        'contract_pdf': jsonEncode({
          'pricing': {
            'rentalSubtotal': rentalSubtotal,
            'voucherCode': voucherCode,
            'voucherPromoId': voucherPromoId,
            'voucherDiscount': voucherDiscount,
            'insuranceTotal': insuranceTotal,
            'selectedInsurance': _selectedInsuranceNames(),
            'serviceFee': serviceFee,
            'sst': sst,
            'securityDeposit': _securityDeposit,
            'subTotal': subTotal,
          },
        }),
        'contract_status': 'Incomplete',
        'otp_code': '000000',
        'otp_expiry': now.add(const Duration(minutes: 10)).toIso8601String(),
        'total_amount': subTotal,
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Create contract failed: $e')));
      setState(() => _submitting = false);
      return;
    }

    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ContractPage(
          bookingId: bookingId,
          contractId: contractId,
          userEmail: email,
          userId: userId,
          vehicleId: widget.vehicleId,
          carName: widget.carName,
          plate: widget.plate,
          type: widget.type,
          transmission: widget.transmission,
          fuelType: widget.fuelType,
          seats: widget.seats,
          dailyRate: widget.dailyRate,
          location: widget.location,
          start: widget.start,
          end: widget.end,
          // Pricing breakdown (passed through to Payment page)
          rentalSubtotal: rentalSubtotal,
          voucherCode: voucherCode,
          voucherPromoId: voucherPromoId,
          voucherDiscount: voucherDiscount,
          insuranceTotal: insuranceTotal,
          selectedInsurance: _selectedInsuranceNames(),
          serviceFee: serviceFee,
          sst: sst,
          securityDeposit: _securityDeposit,
          subTotal: subTotal,
        ),
      ),
    );

    if (mounted) {
      setState(() => _submitting = false);
    }
  }

  Widget _sectionCard({required String title, required Widget child}) {
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(k, style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w600)),
          ),
          Expanded(child: Text(v, style: const TextStyle(fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final rentalRaw = _rentalSubtotal();
    final rental = _rentalAfterVoucher(rentalRaw);
    final insurance = _insuranceTotal();
    final base = rental + insurance;
    final svcRate = _serviceRateFor(base);
    final svc = _serviceFee(base);
    final sst = _sst(base + svc);
    final subTotal = base + svc + sst;

    final timeText = '${_fmtDate(widget.start)} - ${_fmtDate(widget.end)}  ${_fmtTime(widget.start)} - ${_fmtTime(widget.end)}';

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        centerTitle: true,
        title: const Text('Booking Page'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: ListView(
              padding: const EdgeInsets.only(bottom: 16),
              children: [
            _sectionCard(
              title: 'Checkout Progress',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Step 1/3 • Checkout details', style: TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Text(
                    'Your 15-minute hold starts when you press Proceed. After that, you will continue to signing and payment.',
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                ],
              ),
            ),
            _sectionCard(
              title: 'Holding Booking Car Details',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.photoUrl != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: AspectRatio(
                        aspectRatio: 16 / 7,
                        child: Image.network(
                          widget.photoUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: cs.surfaceContainerHighest,
                            alignment: Alignment.center,
                            child: const Icon(Icons.image_not_supported_outlined),
                          ),
                        ),
                      ),
                    ),
                  if (widget.photoUrl != null) const SizedBox(height: 10),
                  _kv('Vehicle Name', widget.carName),
                  _kv('Vehicle Plate', widget.plate.isEmpty ? '-' : widget.plate),
                  _kv('Car Body', widget.type.isEmpty ? '-' : widget.type),
                  _kv('Daily Rate', 'RM${widget.dailyRate.toStringAsFixed(0)}/day'),
                  _kv('Outlet', widget.location.isEmpty ? '-' : widget.location),
                ],
              ),
            ),

            _sectionCard(
              title: 'User Details That Booking the Car',
              child: FutureBuilder<Map<String, dynamic>?>(
                future: _loadUserRow(),
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Center(child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: CircularProgressIndicator(),
                    ));
                  }
                  final row = snap.data;
                  final u = _supa.auth.currentUser;
                  final name = (row?['user_name'] ?? u?.userMetadata?['full_name'] ?? u?.email ?? '-').toString();
                  final email = (row?['user_email'] ?? u?.email ?? '-').toString();
                  final phone = (row?['user_phone'] ?? '-').toString();
                  final ic = (row?['user_icno'] ?? '-').toString();
                  final gender = (row?['user_gender'] ?? '-').toString();
                  final dl = (row?['driver_license_status'] ?? '-').toString();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _kv('Full name', name),
                      _kv('Email', email),
                      _kv('Phone', phone),
                      _kv('IC', ic),
                      _kv('Gender', gender),
                      _kv('Driver licence', dl),
                    ],
                  );
                },
              ),
            ),

            _sectionCard(
              title: 'Pick Up Details',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _kv('Pick-up time', timeText),
                  _kv('Pick-up outlet', widget.location.isEmpty ? '-' : widget.location),
                  const SizedBox(height: 8),
                  _kv('Return time', timeText),
                  _kv('Return outlet', widget.location.isEmpty ? '-' : widget.location),
                ],
              ),
            ),

            _sectionCard(
              title: 'Insurance & Protection Options',
              child: Column(
                children: _options.map((o) {
                  final checked = _selected[o.name] == true;
                  return CheckboxListTile(
                    value: checked,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(o.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(o.price == 0 ? 'Free' : 'RM${o.price.toStringAsFixed(0)}'),
                    onChanged: (v) => setState(() => _selected[o.name] = v ?? false),
                  );
                }).toList(),
              ),
            ),

            _sectionCard(
              title: 'Voucher',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_voucherOptions.isNotEmpty) ...[
                    DropdownButtonFormField<String>(
                      value: _voucherCode != null && _voucherOptions.any((row) => _s(row['code']) == _voucherCode)
                          ? _voucherCode
                          : null,
                      decoration: const InputDecoration(
                        labelText: 'My vouchers',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: _voucherOptions
                          .map(
                            (row) => DropdownMenuItem<String>(
                              value: _s(row['code']),
                              child: Text(
                                '${_s(row['code']).isEmpty ? 'Voucher' : _s(row['code'])} • -RM${(((row['discount'] ?? 0) as num).toDouble()).toStringAsFixed(2)}',
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        final option = _voucherOptions.firstWhere(
                          (row) => _s(row['code']) == value,
                          orElse: () => <String, dynamic>{},
                        );
                        if (option.isNotEmpty) {
                          _applyVoucherOption(option);
                        }
                      },
                    ),
                    const SizedBox(height: 10),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _voucherCtrl,
                          decoration: InputDecoration(
                            hintText: 'Enter voucher code or pick below',
                            border: const OutlineInputBorder(),
                            suffixIcon: _voucherCode == null
                                ? null
                                : IconButton(
                                    tooltip: 'Remove voucher',
                                    onPressed: _clearVoucher,
                                    icon: const Icon(Icons.close),
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      TextButton(
                        onPressed: _applyingVoucher ? null : () => _applyVoucher(rentalRaw),
                        child: _applyingVoucher
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Apply'),
                      ),
                    ],
                  ),
                  if ((_voucherCode ?? '').isNotEmpty || (_voucherMsg ?? '').isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        _voucherCode != null
                            ? 'Applied: $_voucherCode (-RM${_voucherDiscount.toStringAsFixed(2)})'
                            : (_voucherMsg ?? ''),
                        style: TextStyle(color: Colors.grey.shade700),
                      ),
                    ),
                ],
              ),
            ),

            _sectionCard(
              title: 'Summary',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _kv(
                    'Rental Price',
                    'RM${widget.dailyRate.toStringAsFixed(0)} ÷ 24 = RM${_hourlyRate().toStringAsFixed(2)}/hr × ${_hours().toStringAsFixed(_hours() % 1 == 0 ? 0 : 2)} hr = RM${rentalRaw.toStringAsFixed(2)}',
                  ),
                  if (_voucherDiscount > 0)
                    _kv('Voucher discount', '-RM${_voucherDiscount.toStringAsFixed(2)}'),
                  if (_voucherDiscount > 0)
                    _kv('Rental after voucher', 'RM${rental.toStringAsFixed(2)}'),
                  _kv('Insurance & Protection', 'RM${insurance.toStringAsFixed(2)}'),
                  _kv('Service fee (RM10 + ${(svcRate * 100).toStringAsFixed(0)}%)', 'RM${svc.toStringAsFixed(2)}'),
                  _kv('SST (6%)', 'RM${sst.toStringAsFixed(2)}'),
                  const Divider(height: 18),
                  Row(
                    children: [
                      const Expanded(
                        child: Text('Total', style: TextStyle(fontWeight: FontWeight.w900)),
                      ),
                      Text('RM${subTotal.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w900)),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: FilledButton(
                          onPressed: _submitting
                              ? null
                              : () => _proceed(
                            rentalSubtotal: rental,
                            voucherDiscount: _voucherDiscount,
                            voucherCode: _voucherCode,
                            voucherPromoId: _voucherPromoId,
                            insuranceTotal: insurance,
                            serviceFee: svc,
                            sst: sst,
                            subTotal: subTotal,
                          ),
                      child: Text(_submitting ? 'Checking...' : 'Proceed'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: OutlinedButton(
                      onPressed: _goHome,
                      child: const Text('Cancel'),
                    ),
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

class _InsuranceOption {
  final String name;
  final double price;
  const _InsuranceOption(this.name, this.price);
}
