import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import '../services/booking_hold_service.dart';
import '../services/iot_led_service.dart';
import '../services/wallet_service.dart';

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
  static const _evidenceSides = <String>['front', 'left', 'right', 'back'];
  static const _evidenceBucket = 'booking_evidence';

  late Map<String, dynamic> _b;
  late Map<String, dynamic> _v;

  String _dropoff = '';
  Timer? _ticker;
  StreamSubscription<List<Map<String, dynamic>>>? _bookingSubscription;
  DateTime _liveNow = DateTime.now();
  bool _processingHoldAction = false;
  bool _processingLifecycleAction = false;
  final Map<String, Uint8List> _pickupLocalPhotos = <String, Uint8List>{};
  final Map<String, Uint8List> _dropoffLocalPhotos = <String, Uint8List>{};
  bool _loadingExtraCharges = false;
  bool _extraChargeTableReady = true;
  List<Map<String, dynamic>> _extraCharges = const [];
  final WalletService _walletService = WalletService();
  final IotLedService _iotLedService = const IotLedService();
  double _walletBalance = 0;

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
    _refreshBookingMeta();
    _startRealtimeBookingWatch();
    _restartTickerIfNeeded();
    _refreshExtraCharges();
    _refreshWalletBalance();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _bookingSubscription?.cancel();
    super.dispose();
  }

  BookingHoldService get _holdSvc => BookingHoldService(_supa);

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

  String _evidencePublicUrl(String? path) {
    if (path == null || path.trim().isEmpty) return '';
    final safe = path.replaceFirst(RegExp(r'^/+'), '');
    return _supa.storage.from(_evidenceBucket).getPublicUrl(safe);
  }

  Future<void> _refreshWalletBalance() async {
    final userId = (_b['user_id'] ?? '').toString().trim();
    if (userId.isEmpty) return;
    try {
      final balance = await _walletService.getWalletBalance(userId);
      if (!mounted) return;
      setState(() => _walletBalance = balance);
    } catch (_) {}
  }


  int _currentVehicleIotSlot() {
    final directCandidates = <Object?>[
      _b['iot_slot'],
      _b['iot_led_slot'],
      _v['iot_slot'],
      _v['iot_led_slot'],
    ];

    for (final raw in directCandidates) {
      final parsed = int.tryParse((raw ?? '').toString().trim());
      if (parsed != null && parsed > 0) return parsed;
    }

    final vehicleId = (_b['vehicle_id'] ?? _v['vehicle_id'] ?? '').toString().trim();
    if (vehicleId.isEmpty) {
      throw Exception('Vehicle ID is missing for this booking.');
    }

    final slot = _iotLedService.resolveVehicleSlot(vehicleId);
    if (slot == null) {
      throw Exception(
        'No IoT slot mapping found for vehicle $vehicleId. '
        'Update vehicleSlotMap in lib/services/iot_led_service.dart '
        'or save iot_slot in booking/vehicle data.',
      );
    }
    return slot;
  }

  Future<void> _refreshExtraCharges() async {
    final bookingId = (_b['booking_id'] ?? '').toString().trim();
    if (bookingId.isEmpty) return;
    if (mounted) {
      setState(() {
        _loadingExtraCharges = true;
      });
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
        setState(() {
          _loadingExtraCharges = false;
        });
      }
    }
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

  String _normalizeChargePaymentMethod(dynamic value) {
    final raw = (value ?? '').toString().trim().toLowerCase();
    if (raw == 'card') return 'card';
    if (raw == 'tng' || raw == 'touch n go' || raw == "touch 'n go" || raw == 'touchngo') return 'tng';
    if (raw == 'stripe') return 'stripe';
    return raw;
  }

  String _chargeTypeLabel(dynamic value) {
    final raw = (value ?? '').toString().trim().toLowerCase();
    switch (raw) {
      case 'damage':
        return 'Damage';
      case 'scratch':
        return 'Scratch';
      case 'overtime':
      case 'late return':
      case 'late_return':
        return 'Late return';
      case 'cleaning':
        return 'Cleaning';
      case 'other':
        return 'Other';
      default:
        final text = (value ?? '').toString().trim();
        return text.isEmpty ? 'Other' : text[0].toUpperCase() + text.substring(1);
    }
  }

  String _chargePaymentMethodLabel(dynamic value) {
    switch (_normalizeChargePaymentMethod(value)) {
      case 'card':
        return 'Card';
      case 'tng':
        return 'TNG';
      case 'stripe':
        return 'Stripe';
      case 'wallet':
        return 'Wallet';
      default:
        final raw = (value ?? '').toString().trim();
        return raw.isEmpty ? '-' : raw;
    }
  }

  String _buildExtraChargeReference({
    required String method,
    String? cardNumber,
    String? tngReference,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final digits = (cardNumber ?? '').replaceAll(RegExp(r'[^0-9]'), '');
    final tngDigits = (tngReference ?? '').replaceAll(RegExp(r'[^0-9]'), '');
    switch (method) {
      case 'card':
        final last4 = digits.length >= 4 ? digits.substring(digits.length - 4) : '0000';
        return 'CD$last4${(now % 10000).toString().padLeft(4, '0')}';
      case 'tng':
        final tail = tngDigits.isEmpty
            ? (now % 10000000).toString().padLeft(7, '0')
            : tngDigits.substring(math.max(0, tngDigits.length - 7));
        return 'TNG$tail';
      default:
        return 'STP${(now % 10000000).toString().padLeft(7, '0')}';
    }
  }

  Future<Map<String, String>?> _promptExtraChargePayment(Map<String, dynamic> charge) async {
    final cardNameCtrl = TextEditingController();
    final cardNoCtrl = TextEditingController();
    final cardExpCtrl = TextEditingController();
    final cardCvvCtrl = TextEditingController();
    final tngRefCtrl = TextEditingController();
    final amount = _moneyValue(charge['amount']);
    final canUseWallet = _walletBalance >= amount;
    var method = canUseWallet ? 'wallet' : 'card';

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            Widget buildMethodFields() {
              if (method == 'wallet') {
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: canUseWallet ? Colors.green.shade50 : Colors.grey.shade100,
                    border: Border.all(color: canUseWallet ? Colors.green.shade200 : Colors.grey.shade300),
                  ),
                  child: Text(
                    canUseWallet
                        ? 'Wallet balance: ${_money(_walletBalance)}. This bill will be paid directly from wallet.'
                        : 'Wallet balance is not enough. Current balance: ${_money(_walletBalance)}',
                    style: TextStyle(color: Colors.grey.shade800),
                  ),
                );
              }
              if (method == 'card') {
                return Column(
                  children: [
                    TextField(
                      controller: cardNameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Cardholder Name',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: cardNoCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Card Number (demo)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: cardExpCtrl,
                            keyboardType: TextInputType.datetime,
                            decoration: const InputDecoration(
                              labelText: 'Expiry (MM/YY)',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: cardCvvCtrl,
                            keyboardType: TextInputType.number,
                            obscureText: true,
                            decoration: const InputDecoration(
                              labelText: 'CVV',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              }
              if (method == 'tng') {
                return TextField(
                  controller: tngRefCtrl,
                  decoration: const InputDecoration(
                    labelText: 'TNG Reference / Phone',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                );
              }
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.grey.shade100,
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Text(
                  'Stripe demo payment will be saved immediately when you tap Pay now.',
                  style: TextStyle(color: Colors.grey.shade800),
                ),
              );
            }

            Widget buildMethodButton({required String value, required String label, required bool enabled}) {
              final selected = method == value;
              return Expanded(
                child: SizedBox(
                  height: 40,
                  child: selected
                      ? FilledButton(
                          onPressed: enabled ? null : null,
                          child: Text(label),
                        )
                      : OutlinedButton(
                          onPressed: enabled ? () => setLocalState(() => method = value) : null,
                          child: Text(label),
                        ),
                ),
              );
            }

            return AlertDialog(
              title: const Text('Pay extra bill'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Amount: ${_money(charge['amount'])}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Wallet balance: ${_money(_walletBalance)}',
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        buildMethodButton(value: 'wallet', label: 'Wallet', enabled: canUseWallet),
                        const SizedBox(width: 8),
                        buildMethodButton(value: 'card', label: 'Card', enabled: true),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        buildMethodButton(value: 'tng', label: 'TNG', enabled: true),
                        const SizedBox(width: 8),
                        buildMethodButton(value: 'stripe', label: 'Stripe', enabled: true),
                      ],
                    ),
                    const SizedBox(height: 12),
                    buildMethodFields(),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    String reference;
                    try {
                      if (method == 'wallet') {
                        if (!canUseWallet) throw 'Wallet balance is not enough.';
                        reference = '';
                      } else if (method == 'card') {
                        final name = cardNameCtrl.text.trim();
                        final digits = cardNoCtrl.text.replaceAll(RegExp(r'[^0-9]'), '');
                        final exp = cardExpCtrl.text.trim();
                        final cvv = cardCvvCtrl.text.replaceAll(RegExp(r'[^0-9]'), '');
                        if (name.isEmpty) throw 'Please enter cardholder name.';
                        if (digits.length < 12) throw 'Please enter a valid card number.';
                        if (!RegExp(r'^\d{2}/\d{2}$').hasMatch(exp)) {
                          throw 'Expiry must be MM/YY.';
                        }
                        if (cvv.length < 3 || cvv.length > 4) throw 'CVV must be 3-4 digits.';
                        reference = _buildExtraChargeReference(method: method, cardNumber: digits);
                      } else if (method == 'tng') {
                        final tng = tngRefCtrl.text.trim();
                        if (tng.isEmpty) throw 'Please enter TNG reference / phone.';
                        reference = _buildExtraChargeReference(method: method, tngReference: tng);
                      } else {
                        reference = _buildExtraChargeReference(method: method);
                      }
                    } catch (e) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        SnackBar(content: Text(e.toString())),
                      );
                      return;
                    }

                    Navigator.of(dialogContext).pop({
                      'method': method,
                      'reference': reference,
                    });
                  },
                  child: const Text('Pay now'),
                ),
              ],
            );
          },
        );
      },
    );

    cardNameCtrl.dispose();
    cardNoCtrl.dispose();
    cardExpCtrl.dispose();
    cardCvvCtrl.dispose();
    tngRefCtrl.dispose();
    return result;
  }

  Future<void> _payExtraCharge(Map<String, dynamic> charge) async {
    final chargeId = (charge['charge_id'] ?? '').toString().trim();
    if (chargeId.isEmpty) return;
    final payment = await _promptExtraChargePayment(charge);
    if (payment == null) return;

    final paymentMethod = payment['method'] ?? 'card';
    var paymentReference = payment['reference'] ?? '';

    try {
      if (paymentMethod == 'wallet') {
        final result = await _walletService.payBillWithWallet(
          userId: (_b['user_id'] ?? '').toString().trim(),
          billId: chargeId,
        );
        final success = result['success'] == true;
        if (!success) {
          throw (result['message'] ?? 'Wallet payment failed.').toString();
        }
        paymentReference = (result['reference_no'] ?? '').toString();
      } else {
        final payload = <String, dynamic>{
          'charge_status': 'paid',
          'paid_at': DateTime.now().toUtc().toIso8601String(),
          'payment_method': paymentMethod,
          'payment_reference': paymentReference,
        };

        try {
          await _supa.from('booking_extra_charge').update(payload).eq('charge_id', chargeId);
        } on PostgrestException {
          await _supa.from('booking_extra_charge').update({
            'charge_status': 'paid',
            'paid_at': payload['paid_at'],
          }).eq('charge_id', chargeId);
        }
      }

      await _refreshExtraCharges();
      await _refreshWalletBalance();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Extra bill paid successfully by ${_chargePaymentMethodLabel(paymentMethod)}.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to pay bill: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Widget _buildExtraChargeSection() {
    if (_loadingExtraCharges) {
      return const _SectionCard(
        title: 'Extra Bills & Damage Charges',
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    if (!_extraChargeTableReady) {
      return const SizedBox.shrink();
    }
    if (_extraCharges.isEmpty) {
      return _SectionCard(
        title: 'Extra Bills & Damage Charges',
        child: Text(
          'No extra bills for this order yet.',
          style: TextStyle(color: Colors.grey.shade800),
        ),
      );
    }
    return _SectionCard(
      title: 'Extra Bills & Damage Charges',
      child: Column(
        children: _extraCharges.map((row) {
          final status = _chargeStatusLabel(row['charge_status']);
          final color = _chargeStatusColor(context, row['charge_status']);
          final type = (row['charge_type'] ?? 'Other').toString();
          final title = (row['title'] ?? '').toString().trim();
          final note = (row['remark'] ?? row['notes'] ?? '').toString().trim();
          final amount = _money(row['amount']);
          final paymentMethodLabel = _chargePaymentMethodLabel(
            row['payment_method'] ?? row['charge_payment_method'],
          );
          final paymentReference = ((row['payment_reference'] ?? row['charge_payment_reference']) ?? '')
              .toString()
              .trim();
          final isPending = status == 'Pending';
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
                        title.isNotEmpty ? title : _chargeTypeLabel(type),
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
                if (status == 'Paid' && paymentMethodLabel != '-') ...[
                  const SizedBox(height: 6),
                  Text(
                    'Payment method: $paymentMethodLabel',
                    style: TextStyle(color: Colors.grey.shade800, fontWeight: FontWeight.w600),
                  ),
                ],
                if (status == 'Paid' && paymentReference.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Reference: $paymentReference',
                    style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                  ),
                ],
                if (isPending) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => _payExtraCharge(row),
                      child: const Text('Pay now'),
                    ),
                  ),
                ],
              ],
            ),
          );
        }).toList(),
      ),
    );
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

  DateTime _localTime(DateTime d) => d.isUtc ? d.toLocal() : d;

  String _fmtDate(DateTime d) {
    final local = _localTime(d);
    return '${local.day}/${local.month}/${local.year}';
  }

  String _fmtTime(DateTime d, {bool withSeconds = false}) {
    final local = _localTime(d);
    var h = local.hour;
    final m = local.minute.toString().padLeft(2, '0');
    final s = local.second.toString().padLeft(2, '0');
    final ap = h >= 12 ? 'pm' : 'am';
    h %= 12;
    if (h == 0) h = 12;
    return withSeconds ? '$h:$m:$s$ap' : '$h:$m$ap';
  }

  String _fmtDateTime(DateTime d, {bool withSeconds = false}) =>
      '${_fmtDate(d)} ${_fmtTime(d, withSeconds: withSeconds)}';

  String get _rawStatus => (_b['booking_status'] ?? '').toString();

  bool get _isHoldingActive => _holdSvc.isActiveHoldRow(_b, now: _liveNow);

  bool get _isHoldingExpired {
    if (_normStatus(_rawStatus) != 'holding') return false;
    final expiry = _holdSvc.parseHoldExpiryFromRow(_b);
    if (expiry == null) return true;
    return !expiry.isAfter(_liveNow);
  }

  DateTime? get _rentalStart => _dt(_b['rental_start']);
  DateTime? get _rentalEnd => _dt(_b['rental_end']);
  DateTime? get _createdAt => _dt(_b['created_at']) ?? _dt(_b['booking_created_at']);
  DateTime? get _pickupCompletedAt => _dt(_b['pickup_completed_at']);
  DateTime? get _dropoffCompletedAt => _dt(_b['dropoff_completed_at']) ?? _dt(_b['actual_dropoff_at']);

  bool get _isBlockedStatus {
    final s = _normStatus(_rawStatus);
    return s == 'cancelled' || s == 'deactive';
  }

  bool get _hasPickupCompleted => _pickupCompletedAt != null;
  bool get _hasDropoffCompleted {
    final s = _normStatus(_rawStatus);
    if (s == 'inactive') return true;
    return _dropoffCompletedAt != null;
  }

  bool get _isIncoming {
    final start = _rentalStart;
    final end = _rentalEnd;
    if (start == null || end == null || _isHoldingActive || _isBlockedStatus || _hasDropoffCompleted) return false;
    return _liveNow.isBefore(start);
  }

  bool get _isReadyForPickup {
    final start = _rentalStart;
    final end = _rentalEnd;
    if (start == null || end == null || _isHoldingActive || _isBlockedStatus || _hasDropoffCompleted) return false;
    return (_liveNow.isAtSameMomentAs(start) || _liveNow.isAfter(start)) &&
        _liveNow.isBefore(end) &&
        !_hasPickupCompleted;
  }

  bool get _isOngoing {
    if (_isHoldingActive || _isBlockedStatus || _hasDropoffCompleted) return false;
    if (!_hasPickupCompleted) return false;
    final start = _pickupCompletedAt ?? _rentalStart;
    final end = _rentalEnd;
    if (start == null || end == null) return false;
    return (_liveNow.isAtSameMomentAs(start) || _liveNow.isAfter(start)) && _liveNow.isBefore(end);
  }

  bool get _isOvertime {
    if (_isHoldingActive || _isBlockedStatus || !_hasPickupCompleted || _hasDropoffCompleted) return false;
    final end = _rentalEnd;
    if (end == null) return false;
    return _liveNow.isAfter(end);
  }

  bool get _canShowVehicleControl => _hasPickupCompleted && !_hasDropoffCompleted && !_isBlockedStatus;

  bool get _canUserCancel {
    if (_isHoldingActive || _isBlockedStatus || _hasPickupCompleted || _hasDropoffCompleted) return false;
    final start = _rentalStart;
    final moreThan3DaysBefore = start != null && start.difference(_liveNow) >= const Duration(days: 3);
    final createdAt = _createdAt;
    final within30Minutes = createdAt != null && _liveNow.difference(createdAt) <= const Duration(minutes: 30);
    return moreThan3DaysBefore || within30Minutes;
  }

  String get _cancelRuleText {
    final start = _rentalStart;
    final moreThan3DaysBefore = start != null && start.difference(_liveNow) >= const Duration(days: 3);
    final createdAt = _createdAt;
    final within30Minutes = createdAt != null && _liveNow.difference(createdAt) <= const Duration(minutes: 30);
    if (moreThan3DaysBefore) {
      return 'Eligible to cancel because the rental starts more than 3 days from now.';
    }
    if (within30Minutes) {
      return 'Eligible to cancel because this order was created within the 30-minute grace window.';
    }
    return 'User cancellation is allowed only more than 3 days before rental start or within 30 minutes after order creation.';
  }

  String get _statusLabel {
    final s = _normStatus(_rawStatus);
    if (s == 'cancelled') return 'Cancelled';
    if (s == 'deactive') return 'Deactive by Admin';
    if (_isHoldingActive) return 'Holding';
    if (_hasDropoffCompleted) return 'Completed';
    if (_isReadyForPickup) return 'Pickup Ready';
    if (_isOvertime) return 'Overtime';
    if (_isOngoing) return 'Ongoing';
    if (_isIncoming) return 'Incoming';
    if (s == 'paid') return 'Paid';
    if (s == 'active') return 'Active';
    if (s == 'inactive') return 'Inactive';
    return s.isEmpty ? 'Unknown' : s[0].toUpperCase() + s.substring(1);
  }

  Color get _statusColor {
    final s = _normStatus(_rawStatus);
    if (s == 'cancelled' || s == 'deactive') return Colors.red;
    if (_isHoldingActive) return Colors.orange;
    if (_hasDropoffCompleted) return Colors.grey;
    if (_isReadyForPickup) return Colors.teal;
    if (_isOvertime) return Colors.deepOrange;
    if (_isOngoing) return Colors.green;
    if (_isIncoming) return Colors.blue;
    return Colors.grey;
  }

  void _restartTickerIfNeeded() {
    _ticker?.cancel();
    if (!_isHoldingActive && !_isIncoming && !_isReadyForPickup && !_isOngoing && !_isOvertime) return;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (!mounted) return;
      setState(() => _liveNow = DateTime.now());
      if (_isHoldingExpired) {
        await _expireHoldingIfNeeded(showSnack: true);
      }
    });
  }

  void _startRealtimeBookingWatch() {
    final bookingId = (_b['booking_id'] ?? '').toString();
    if (bookingId.isEmpty) return;
    _bookingSubscription?.cancel();
    _bookingSubscription = _supa
        .from('booking')
        .stream(primaryKey: const ['booking_id'])
        .eq('booking_id', bookingId)
        .listen((rows) {
      if (!mounted || rows.isEmpty) return;
      final latest = Map<String, dynamic>.from(rows.first);
      setState(() {
        _b.addAll(latest);
        _liveNow = DateTime.now();
      });
      _restartTickerIfNeeded();
    });
  }

  Future<void> _refreshBookingMeta() async {
    final bookingId = (_b['booking_id'] ?? '').toString();
    if (bookingId.isEmpty) return;
    final row = await _holdSvc.fetchBookingMeta(bookingId);
    if (row == null || !mounted) return;
    setState(() {
      _b.addAll(row);
      _liveNow = DateTime.now();
    });
    _restartTickerIfNeeded();
    if (_isHoldingExpired) {
      await _expireHoldingIfNeeded(showSnack: false);
    }
  }

  Future<void> _expireHoldingIfNeeded({required bool showSnack}) async {
    if (_processingHoldAction) return;
    final bookingId = (_b['booking_id'] ?? '').toString();
    if (bookingId.isEmpty) return;
    _processingHoldAction = true;
    try {
      final expired = await _holdSvc.expireIfNeeded(bookingId: bookingId, row: _b);
      if (!mounted) return;
      if (!expired) {
        await _refreshBookingMeta();
        return;
      }
      setState(() {
        _b['booking_status'] = 'Cancelled';
        _liveNow = DateTime.now();
      });
      _ticker?.cancel();
      if (showSnack) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Hold time ended. This order was cancelled automatically.')),
        );
      }
    } finally {
      _processingHoldAction = false;
    }
  }

  Future<void> _cancelHolding() async {
    final bookingId = (_b['booking_id'] ?? '').toString();
    if (bookingId.isEmpty || _processingHoldAction) return;
    setState(() => _processingHoldAction = true);
    try {
      final cancelled = await _holdSvc.cancelHold(bookingId);
      if (!mounted) return;
      if (!cancelled) {
        await _refreshBookingMeta();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cancel failed. Please try refresh again.'), backgroundColor: Colors.red),
        );
        return;
      }
      setState(() {
        _b['booking_status'] = 'Cancelled';
        _liveNow = DateTime.now();
      });
      _ticker?.cancel();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Holding order cancelled. The car slot is released.')),
      );
    } finally {
      if (mounted) {
        setState(() => _processingHoldAction = false);
      } else {
        _processingHoldAction = false;
      }
    }
  }

  String _normStatus(String status) {
    final s = status.trim().toLowerCase();
    if (s == 'cancel' || s == 'cancelled' || s == 'canceled') return 'cancelled';
    if (s == 'deactive' || s == 'deactivated') return 'deactive';
    if (s == 'holding') return 'holding';
    if (s == 'paid') return 'paid';
    if (s == 'active') return 'active';
    if (s == 'inactive') return 'inactive';
    return s;
  }

  String _timeRangeText() {
    final s = _rentalStart;
    final e = _rentalEnd;
    if (s == null || e == null) return '-';
    return '${_fmtDate(s)} - ${_fmtDate(e)}\n${_fmtTime(s)} - ${_fmtTime(e)}';
  }

  String _hoursLeftText() {
    final status = _normStatus(_rawStatus);
    if (status == 'cancelled') return 'Cancelled';
    if (status == 'deactive') return 'Please contact admin';

    final s = _rentalStart;
    final e = _rentalEnd;
    if (s == null || e == null) return '-';

    final now = _liveNow;

    if (_isHoldingActive) {
      final remaining = _holdSvc.remainingForRow(_b, now: now) ?? Duration.zero;
      return 'Hold expires in ${_holdSvc.formatRemaining(remaining)}';
    }

    if (_hasDropoffCompleted) {
      return 'Dropped off';
    }

    if (_isIncoming) {
      final diff = s.difference(now);
      if (diff.isNegative) return 'Starting soon';
      final totalMins = diff.inMinutes;
      final days = totalMins ~/ (60 * 24);
      final hours = (totalMins % (60 * 24)) ~/ 60;
      if (days > 0) return 'Starts in $days day ${hours}h';
      return 'Starts in ${math.max(0, hours)} hour';
    }

    if (_isReadyForPickup) {
      return 'Pickup available now';
    }

    if (_isOvertime) {
      return 'Penalty ${_money(_overtimePenaltyAmount())}';
    }

    final diff = e.difference(now);
    if (diff.isNegative) return 'Completed';
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

    final bookingId = (_b['booking_id'] ?? '').toString();
    if (bookingId.isEmpty) return;
    try {
      await _supa.from('booking').update({'dropoff_location': chosen}).eq('booking_id', bookingId);
      _b['dropoff_location'] = chosen;
    } catch (_) {
      // If column doesn't exist or RLS blocks it, keep UI-only.
    }
  }

  double _moneyValue(dynamic v) {
    final n = v is num ? v.toDouble() : double.tryParse(v.toString()) ?? 0;
    return n;
  }

  String _money(dynamic v) => 'RM ${_moneyValue(v).toStringAsFixed(2)}';

  int _bookedHours() {
    final start = _rentalStart;
    final end = _rentalEnd;
    if (start == null || end == null) return 0;
    final minutes = end.difference(start).inMinutes;
    if (minutes <= 0) return 0;
    return (minutes / 60).ceil();
  }

  double _baseHourlyRate() {
    final totalAmount = _moneyValue(_b['total_rental_amount']);
    final bookedHours = _bookedHours();
    if (totalAmount > 0 && bookedHours > 0) {
      return totalAmount / bookedHours;
    }
    final dailyRate = _moneyValue(_v['daily_rate']);
    if (dailyRate > 0) {
      return dailyRate / 24;
    }
    return 0;
  }

  int _overtimeHoursRoundedUp({DateTime? effectiveDropoffTime}) {
    final end = _rentalEnd;
    if (end == null) return 0;
    final compare = effectiveDropoffTime ?? _dropoffCompletedAt ?? _liveNow;
    if (!compare.isAfter(end)) return 0;
    final minutes = compare.difference(end).inMinutes;
    if (minutes <= 0) return 0;
    return (minutes / 60).ceil();
  }

  double _overtimePenaltyAmount({DateTime? effectiveDropoffTime}) {
    final hours = _overtimeHoursRoundedUp(effectiveDropoffTime: effectiveDropoffTime);
    if (hours <= 0) return 0;
    final rate = _baseHourlyRate();
    return rate <= 0 ? 0 : hours * rate * 2;
  }

  String _lockStateLabel() {
    final raw = (_b['lock_demo_state'] ?? 'locked').toString().trim().toLowerCase();
    if (raw == 'unlocked') return 'Unlocked';
    return 'Locked';
  }

  String? _evidenceUrl(String stage, String side) {
    final raw = (_b['${stage}_${side}_url'] ?? '').toString().trim();
    return raw.isEmpty ? null : raw;
  }

  Map<String, Uint8List> _localEvidencePhotos(String stage) {
    return stage == 'pickup' ? _pickupLocalPhotos : _dropoffLocalPhotos;
  }

  bool _hasAnyEvidence(String stage) {
    for (final side in _evidenceSides) {
      if ((_evidenceUrl(stage, side) ?? '').isNotEmpty) return true;
      if (_localEvidencePhotos(stage).containsKey(side)) return true;
    }
    return false;
  }

  Future<void> _cancelUpcomingOrder() async {
    if (!_canUserCancel || _processingLifecycleAction) return;
    final bookingId = (_b['booking_id'] ?? '').toString().trim();
    if (bookingId.isEmpty) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cancel order'),
        content: Text('This action will cancel booking $bookingId. Continue?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Back')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Cancel order')),
        ],
      ),
    );

    if (ok != true) return;

    setState(() => _processingLifecycleAction = true);
    final cancelledAtUtc = DateTime.now().toUtc().toIso8601String();
    try {
      var storedCancelStatus = 'Cancelled';
      final patch = <String, dynamic>{
        'booking_status': storedCancelStatus,
        'cancelled_by_user_at': cancelledAtUtc,
      };

      try {
        await _supa.from('booking').update(patch).eq('booking_id', bookingId);
      } on PostgrestException catch (e) {
        final msg = e.message.toLowerCase();
        final blockedByNotificationTrigger =
            e.code == '42501' && msg.contains('notification');
        if (!blockedByNotificationTrigger) rethrow;

        storedCancelStatus = 'Cancel';
        await _supa.from('booking').update({
          'booking_status': storedCancelStatus,
          'cancelled_by_user_at': cancelledAtUtc,
        }).eq('booking_id', bookingId);
      }

      if (!mounted) return;
      setState(() {
        _b['booking_status'] = storedCancelStatus;
        _b['cancelled_by_user_at'] = cancelledAtUtc;
        _liveNow = DateTime.now();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Order cancelled successfully.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to cancel order: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) {
        setState(() => _processingLifecycleAction = false);
      } else {
        _processingLifecycleAction = false;
      }
    }
  }

  Future<Map<String, _UploadedEvidenceAsset>> _uploadEvidence(String stage, Map<String, _CapturedEvidence> files) async {
    final bookingId = (_b['booking_id'] ?? '').toString().trim();
    if (bookingId.isEmpty || files.isEmpty) return const <String, _UploadedEvidenceAsset>{};
    final uploaded = <String, _UploadedEvidenceAsset>{};
    for (final entry in files.entries) {
      final side = entry.key;
      final file = entry.value;
      final ext = file.extension.toLowerCase();
      final normalizedExt = ext == 'png' ? 'png' : 'jpg';
      final contentType = normalizedExt == 'png' ? 'image/png' : 'image/jpeg';
      final path = 'orders/$bookingId/$stage/${side}_${DateTime.now().millisecondsSinceEpoch}.$normalizedExt';
      await _supa.storage.from(_evidenceBucket).uploadBinary(
        path,
        file.bytes,
        fileOptions: FileOptions(contentType: contentType, upsert: true),
      );
      uploaded[side] = _UploadedEvidenceAsset(
        path: path,
        url: _evidencePublicUrl(path),
      );
    }
    return uploaded;
  }

  String _friendlyEvidenceIssue(Object? error) {
    final raw = (error ?? '').toString().trim();
    final lower = raw.toLowerCase();
    if (lower.isEmpty) {
      return 'Supabase evidence storage is not ready yet.';
    }
    if (lower.contains('bucket') || lower.contains('storage')) {
      return 'Supabase Storage bucket "booking_evidence" is missing or not allowed yet.';
    }
    if (lower.contains('row-level security') || lower.contains('permission') || lower.contains('not authorized') || lower.contains('unauthorized') || lower.contains('42501')) {
      return 'Supabase policy for booking evidence is blocking upload.';
    }
    if (lower.contains('column') || lower.contains('schema') || lower.contains('relation') || lower.contains('booking_evidence')) {
      return 'Booking evidence table/columns are not fully added in Supabase yet.';
    }
    return raw;
  }

  Future<void> _saveEvidenceRows(
    String bookingId,
    String stage,
    Map<String, _UploadedEvidenceAsset> uploadedEvidence,
  ) async {
    if (bookingId.isEmpty || uploadedEvidence.isEmpty) return;
    final rows = <Map<String, dynamic>>[];
    for (final entry in uploadedEvidence.entries) {
      rows.add({
        'booking_id': bookingId,
        'stage': stage,
        'side': entry.key,
        'storage_path': entry.value.path,
        'image_url': entry.value.url,
      });
    }
    try {
      await _supa.from('booking_evidence').upsert(rows);
    } catch (_) {
      // Optional helper table. Ignore when not available.
    }
  }

  Future<void> _capturePickupFlow() async {
    if (_processingLifecycleAction) return;
    final capture = await Navigator.of(context).push<Map<String, _CapturedEvidence>>(
      MaterialPageRoute(
        builder: (_) => const _EvidenceCapturePage(
          title: 'Pickup inspection',
          subtitle: 'Take 4 photos before the trip starts: front, left, right, and back.',
        ),
      ),
    );
    if (capture == null || capture.length != _evidenceSides.length) return;

    setState(() => _processingLifecycleAction = true);
    final pickupTime = DateTime.now();
    try {
      Map<String, _UploadedEvidenceAsset> uploadedEvidence = const <String, _UploadedEvidenceAsset>{};
      var evidenceStoredRemotely = false;
      Object? evidenceError;
      try {
        uploadedEvidence = await _uploadEvidence('pickup', capture);
        evidenceStoredRemotely = uploadedEvidence.isNotEmpty;
      } catch (e) {
        evidenceStoredRemotely = false;
        evidenceError = e;
      }

      final bookingId = (_b['booking_id'] ?? '').toString().trim();
      if (bookingId.isEmpty) return;

      await _supa.from('booking').update({'booking_status': 'Active'}).eq('booking_id', bookingId);

      final extraPatch = <String, dynamic>{
        'pickup_completed_at': pickupTime.toUtc().toIso8601String(),
        'lock_demo_state': 'locked',
        for (final side in _evidenceSides) ...{
          'pickup_${side}_url': uploadedEvidence[side]?.url,
          'pickup_${side}_path': uploadedEvidence[side]?.path,
        },
      };
      try {
        await _supa.from('booking').update(extraPatch).eq('booking_id', bookingId);
      } catch (_) {
        // Demo-safe: keep UI state even if schema is not ready.
      }
      await _saveEvidenceRows(bookingId, 'pickup', uploadedEvidence);

      if (!mounted) return;
      setState(() {
        _b['booking_status'] = 'Active';
        _b['pickup_completed_at'] = pickupTime.toUtc().toIso8601String();
        _b['lock_demo_state'] = 'locked';
        for (final side in _evidenceSides) {
          final asset = uploadedEvidence[side];
          if ((asset?.url ?? '').isNotEmpty) {
            _b['pickup_${side}_url'] = asset!.url;
          }
          if ((asset?.path ?? '').isNotEmpty) {
            _b['pickup_${side}_path'] = asset!.path;
          }
          _pickupLocalPhotos[side] = capture[side]!.bytes;
        }
        _liveNow = DateTime.now();
      });

      final pickupMessage = evidenceStoredRemotely
          ? 'Pickup completed. Trip is now officially ongoing.'
          : 'Pickup completed, but photos could not sync to Supabase yet. ${_friendlyEvidenceIssue(evidenceError)} Run booking_evidence_patch.sql first.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(pickupMessage)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Pickup failed: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) {
        setState(() => _processingLifecycleAction = false);
      } else {
        _processingLifecycleAction = false;
      }
    }
  }

  Future<void> _setLockState(String value) async {
    if (_processingLifecycleAction) return;

    final bookingId = (_b['booking_id'] ?? '').toString().trim();
    if (bookingId.isEmpty) return;

    final isLocked = value == 'locked';

    setState(() => _processingLifecycleAction = true);
    try {
      final slot = _currentVehicleIotSlot();

      await _iotLedService.setVehicleLock(
        slot: slot,
        isLocked: isLocked,
      );

      try {
        await _supa.from('booking').update({'lock_demo_state': value}).eq('booking_id', bookingId);
      } catch (_) {
        // Keep UI working even if DB update fails.
      }

      if (!mounted) return;
      setState(() {
        _b['lock_demo_state'] = value;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isLocked
                ? 'Car slot $slot locked. Only that IoT LED is red.'
                : 'Car slot $slot unlocked. Only that IoT LED is green.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Lock command failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _processingLifecycleAction = false);
      } else {
        _processingLifecycleAction = false;
      }
    }
  }

  Future<void> _dropoffCar() async {
    if (_processingLifecycleAction || !_canShowVehicleControl) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Drop off car'),
        content: Text(
          _isOvertime
              ? 'This order is already overtime. Continue to capture return photos and finish the booking?'
              : 'Take return photos and complete the booking now?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Back')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Continue')),
        ],
      ),
    );
    if (confirm != true) return;

    final capture = await Navigator.of(context).push<Map<String, _CapturedEvidence>>(
      MaterialPageRoute(
        builder: (_) => const _EvidenceCapturePage(
          title: 'Drop-off inspection',
          subtitle: 'Take 4 return photos: front, left, right, and back. Staff and admin can review these for damages.',
        ),
      ),
    );
    if (capture == null || capture.length != _evidenceSides.length) return;

    setState(() => _processingLifecycleAction = true);
    final dropoffTime = DateTime.now();
    final penalty = _overtimePenaltyAmount(effectiveDropoffTime: dropoffTime);
    try {
      Map<String, _UploadedEvidenceAsset> uploadedEvidence = const <String, _UploadedEvidenceAsset>{};
      var evidenceStoredRemotely = false;
      Object? evidenceError;
      try {
        uploadedEvidence = await _uploadEvidence('dropoff', capture);
        evidenceStoredRemotely = uploadedEvidence.isNotEmpty;
      } catch (e) {
        evidenceStoredRemotely = false;
        evidenceError = e;
      }

      final bookingId = (_b['booking_id'] ?? '').toString().trim();
      if (bookingId.isEmpty) return;

      await _supa.from('booking').update({'booking_status': 'Inactive'}).eq('booking_id', bookingId);

      final extraPatch = <String, dynamic>{
        'dropoff_completed_at': dropoffTime.toUtc().toIso8601String(),
        'actual_dropoff_at': dropoffTime.toUtc().toIso8601String(),
        'overtime_penalty_amount': penalty,
        'lock_demo_state': 'locked',
        for (final side in _evidenceSides) ...{
          'dropoff_${side}_url': uploadedEvidence[side]?.url,
          'dropoff_${side}_path': uploadedEvidence[side]?.path,
        },
      };
      try {
        await _supa.from('booking').update(extraPatch).eq('booking_id', bookingId);
      } catch (_) {
        // Demo-safe: keep the status transition even if extra columns are missing.
      }
      await _saveEvidenceRows(bookingId, 'dropoff', uploadedEvidence);

      if (!mounted) return;
      setState(() {
        _b['booking_status'] = 'Inactive';
        _b['dropoff_completed_at'] = dropoffTime.toUtc().toIso8601String();
        _b['actual_dropoff_at'] = dropoffTime.toUtc().toIso8601String();
        _b['overtime_penalty_amount'] = penalty;
        _b['lock_demo_state'] = 'locked';
        for (final side in _evidenceSides) {
          final asset = uploadedEvidence[side];
          if ((asset?.url ?? '').isNotEmpty) {
            _b['dropoff_${side}_url'] = asset!.url;
          }
          if ((asset?.path ?? '').isNotEmpty) {
            _b['dropoff_${side}_path'] = asset!.path;
          }
          _dropoffLocalPhotos[side] = capture[side]!.bytes;
        }
        _liveNow = DateTime.now();
      });

      final penaltyText = penalty > 0
          ? ' Overtime penalty: ${_money(penalty)} (1 hour x2 charge, rounded up).'
          : '';
      final dropoffMessage = evidenceStoredRemotely
          ? 'Drop-off completed.$penaltyText'
          : 'Drop-off completed, but photos could not sync to Supabase yet. ${_friendlyEvidenceIssue(evidenceError)} Run booking_evidence_patch.sql first.$penaltyText';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(dropoffMessage)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Drop-off failed: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) {
        setState(() => _processingLifecycleAction = false);
      } else {
        _processingLifecycleAction = false;
      }
    }
  }

  Widget _buildLifecycleActionCard() {
    if (_isHoldingActive) return const SizedBox.shrink();
    return _SectionCard(
      title: 'Order Actions',
      trailing: Text(
        _hoursLeftText(),
        style: TextStyle(color: _statusColor, fontWeight: FontWeight.w800, fontSize: 12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_isIncoming || _isReadyForPickup) ...[
            Text(
              _cancelRuleText,
              style: TextStyle(color: Colors.grey.shade800, height: 1.35),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _canUserCancel && !_processingLifecycleAction ? _cancelUpcomingOrder : null,
                icon: _processingLifecycleAction
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.cancel_outlined),
                label: const Text('Cancel order'),
              ),
            ),
          ],
          if (_isReadyForPickup) ...[
            const SizedBox(height: 12),
            Text(
              'Pickup is available now. Complete the 4-side photo inspection first. Once submitted, the order becomes officially ongoing.',
              style: TextStyle(color: Colors.grey.shade800, height: 1.35),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _processingLifecycleAction ? null : _capturePickupFlow,
                icon: _processingLifecycleAction
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.car_rental),
                label: const Text('Pick up car'),
              ),
            ),
          ],
          if (_canShowVehicleControl) ...[
            Text(
              _isOvertime
                  ? 'Trip is overtime now. Lock/unlock is still available for demo, and you can drop off from the 3-dot menu.'
                  : 'Trip is ongoing. Lock/unlock is demo only, and drop-off is available from the 3-dot menu.',
              style: TextStyle(color: Colors.grey.shade800, height: 1.35),
            ),
          ],
          if (!_isIncoming && !_isReadyForPickup && !_canShowVehicleControl && !_hasDropoffCompleted) ...[
            Text(
              'No extra user action is needed right now.',
              style: TextStyle(color: Colors.grey.shade800, height: 1.35),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildVehicleControlCard() {
    if (!_canShowVehicleControl) return const SizedBox.shrink();
    final locked = _lockStateLabel() == 'Locked';
    return _SectionCard(
      title: 'IoT Car Control',
      trailing: Text(
        _lockStateLabel(),
        style: TextStyle(
          color: locked ? Colors.indigo : Colors.green,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'These buttons now send the booking vehicle to the ESP32 IoT service. Only the matched car LED changes.',
            style: TextStyle(color: Colors.grey.shade800, height: 1.35),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: _processingLifecycleAction ? null : () => _setLockState('locked'),
                  icon: const Icon(Icons.lock_outline),
                  label: const Text('Lock'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: _processingLifecycleAction ? null : () => _setLockState('unlocked'),
                  icon: const Icon(Icons.lock_open_outlined),
                  label: const Text('Unlock'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPenaltyCard() {
    final dropoffAt = _dropoffCompletedAt;
    final penalty = _overtimePenaltyAmount(effectiveDropoffTime: dropoffAt);
    final overtimeHours = _overtimeHoursRoundedUp(effectiveDropoffTime: dropoffAt);
    if (penalty <= 0 && !_isOvertime) return const SizedBox.shrink();
    return _SectionCard(
      title: 'Overtime Penalty',
      trailing: Text(
        _money(penalty),
        style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.deepOrange),
      ),
      child: Text(
        'Penalty rule applied: each overtime hour is charged at 2x the normal hourly rate. '
        'Hours are rounded up. Current overtime: ${math.max(1, overtimeHours)} hour(s).',
        style: TextStyle(color: Colors.grey.shade800, height: 1.35),
      ),
    );
  }

  Widget _buildEvidenceCard(String stage, String title, String emptyText) {
    if (!_hasAnyEvidence(stage)) return const SizedBox.shrink();
    return _SectionCard(
      title: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            stage == 'dropoff'
                ? 'These photos should be reviewed by staff/admin for any visible damage.'
                : 'Pickup evidence captured before the trip officially started.',
            style: TextStyle(color: Colors.grey.shade800, height: 1.35),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _evidenceSides.map((side) {
              final url = _evidenceUrl(stage, side);
              final local = _localEvidencePhotos(stage)[side];
              return _EvidencePreviewCard(
                label: side[0].toUpperCase() + side.substring(1),
                imageUrl: url,
                localBytes: local,
                emptyText: emptyText,
              );
            }).toList(),
          ),
        ],
      ),
    );
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
        actions: [
          if (_canShowVehicleControl)
            PopupMenuButton<String>(
              onSelected: (value) async {
                if (value == 'dropoff') {
                  await _dropoffCar();
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem<String>(
                  value: 'dropoff',
                  child: Row(
                    children: [
                      Icon(Icons.keyboard_return_outlined),
                      SizedBox(width: 10),
                      Text('Drop off car'),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
              children: [
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
                        color: _statusColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: _statusColor.withOpacity(0.35),
                        ),
                      ),
                      child: Text(
                        _statusLabel,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                          color: _statusColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
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
                if (_isHoldingActive) ...[
                  _SectionCard(
                    title: 'Holding Timer',
                    trailing: Text(
                      _hoursLeftText(),
                      style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.w800, fontSize: 12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'This booking is reserved for you only during the hold period. Sign the contract and make payment before the timer ends.',
                          style: TextStyle(color: Colors.grey.shade800, height: 1.35),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: _processingHoldAction ? null : _cancelHolding,
                            child: _processingHoldAction
                                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Text('Cancel holding order'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                _buildLifecycleActionCard(),
                const SizedBox(height: 12),
                _buildVehicleControlCard(),
                if (_canShowVehicleControl) const SizedBox(height: 12),
                _buildPenaltyCard(),
                if (_isOvertime || (_overtimePenaltyAmount(effectiveDropoffTime: _dropoffCompletedAt) > 0)) const SizedBox(height: 12),
                _SectionCard(
                  title: 'Time',
                  trailing: Text(
                    _hoursLeftText(),
                    style: TextStyle(color: _statusColor, fontWeight: FontWeight.w800, fontSize: 12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _timeRangeText(),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      if (_pickupCompletedAt != null) ...[
                        const SizedBox(height: 8),
                        Text('Pickup completed: ${_fmtDateTime(_pickupCompletedAt!, withSeconds: true)}', style: const TextStyle(fontWeight: FontWeight.w600)),
                      ],
                      if (_dropoffCompletedAt != null) ...[
                        const SizedBox(height: 6),
                        Text('Drop-off completed: ${_fmtDateTime(_dropoffCompletedAt!, withSeconds: true)}', style: const TextStyle(fontWeight: FontWeight.w600)),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
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
                const SizedBox(height: 12),
                _buildEvidenceCard('pickup', 'Pickup Inspection Photos', 'No pickup photo'),
                if (_hasAnyEvidence('pickup')) const SizedBox(height: 12),
                _buildEvidenceCard('dropoff', 'Drop-off Inspection Photos', 'No drop-off photo'),
                if (_hasAnyEvidence('dropoff')) const SizedBox(height: 12),
                _buildExtraChargeSection(),
                const SizedBox(height: 14),
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

class _EvidencePreviewCard extends StatelessWidget {
  const _EvidencePreviewCard({
    required this.label,
    required this.emptyText,
    this.imageUrl,
    this.localBytes,
  });

  final String label;
  final String emptyText;
  final String? imageUrl;
  final Uint8List? localBytes;

  @override
  Widget build(BuildContext context) {
    final hasLocal = localBytes != null && localBytes!.isNotEmpty;
    final hasRemote = (imageUrl ?? '').trim().isNotEmpty;
    return SizedBox(
      width: 170,
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
              child: hasLocal
                  ? Image.memory(localBytes!, fit: BoxFit.cover, width: double.infinity)
                  : hasRemote
                      ? Image.network(
                          imageUrl!,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          errorBuilder: (_, __, ___) => Center(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Text(emptyText, textAlign: TextAlign.center),
                            ),
                          ),
                        )
                      : Center(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(emptyText, textAlign: TextAlign.center),
                          ),
                        ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CapturedEvidence {
  const _CapturedEvidence({
    required this.bytes,
    required this.extension,
  });

  final Uint8List bytes;
  final String extension;
}

class _UploadedEvidenceAsset {
  const _UploadedEvidenceAsset({
    required this.path,
    required this.url,
  });

  final String path;
  final String url;
}

class _EvidenceCapturePage extends StatefulWidget {
  const _EvidenceCapturePage({
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  State<_EvidenceCapturePage> createState() => _EvidenceCapturePageState();
}

class _EvidenceCapturePageState extends State<_EvidenceCapturePage> {
  final ImagePicker _picker = ImagePicker();
  final Map<String, _CapturedEvidence> _files = <String, _CapturedEvidence>{};
  bool _busy = false;

  Future<void> _take(String side, ImageSource source) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final x = await _picker.pickImage(
        source: source,
        maxWidth: 1800,
        imageQuality: 85,
      );
      if (x == null) return;
      final bytes = await x.readAsBytes();
      final name = x.name;
      final ext = name.contains('.') ? name.split('.').last.toLowerCase() : 'jpg';
      if (!mounted) return;
      setState(() {
        _files[side] = _CapturedEvidence(bytes: bytes, extension: ext);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to capture $side photo: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      } else {
        _busy = false;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          children: [
            Text(widget.subtitle, style: TextStyle(color: Colors.grey.shade700, height: 1.35)),
            const SizedBox(height: 14),
            ..._MyOrderDetailsPageState._evidenceSides.map((side) {
              final file = _files[side];
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        side[0].toUpperCase() + side.substring(1),
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          height: 150,
                          width: double.infinity,
                          color: Colors.grey.shade200,
                          child: file == null
                              ? const Center(child: Text('Photo not taken yet'))
                              : Image.memory(file.bytes, fit: BoxFit.cover),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _busy ? null : () => _take(side, ImageSource.camera),
                              icon: const Icon(Icons.camera_alt_outlined),
                              label: Text(file == null ? 'Camera' : 'Retake'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _busy ? null : () => _take(side, ImageSource.gallery),
                              icon: const Icon(Icons.photo_library_outlined),
                              label: const Text('Gallery'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _files.length == _MyOrderDetailsPageState._evidenceSides.length
                  ? () => Navigator.of(context).pop(_files)
                  : null,
              child: const Text('Use these 4 photos'),
            ),
          ],
        ),
      ),
    );
  }
}
