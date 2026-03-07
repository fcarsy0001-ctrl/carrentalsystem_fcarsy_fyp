import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/email_verification_service.dart';
import 'payment_page.dart';

/// Contract signing page.
///
/// Supports two signing methods:
/// 1) OTP: send OTP to user email, verify, then mark contract signed.
/// 2) E-sign: user draws signature, save to DB (base64 PNG) and mark contract signed.
///
/// Only after signed => show Process button.
class ContractPage extends StatefulWidget {
  const ContractPage({
    super.key,
    required this.bookingId,
    required this.contractId,
    required this.userEmail,
    required this.userId,
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
    // pricing breakdown for payment page
    required this.rentalSubtotal,
    this.voucherCode,
    this.voucherDiscount = 0,
    required this.insuranceTotal,
    required this.selectedInsurance,
    required this.serviceFee,
    required this.sst,
    required this.securityDeposit,
    required this.subTotal,
  });

  final String bookingId;
  final String contractId;
  final String userEmail;
  final String userId;

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

  // pricing breakdown
  final double rentalSubtotal;
  final String? voucherCode;
  final double voucherDiscount;
  final double insuranceTotal;
  final List<String> selectedInsurance;
  final double serviceFee;
  final double sst;
  final double securityDeposit;
  final double subTotal;

  @override
  State<ContractPage> createState() => _ContractPageState();
}

enum SignMethod { otp, esign }

class _ContractPageState extends State<ContractPage> {
  SupabaseClient get _supa => Supabase.instance.client;

  SignMethod _method = SignMethod.otp;
  bool _signed = false;
  bool _sendingOtp = false;
  bool _verifyingOtp = false;
  String? _signedMethod; // 'OTP' / 'ESIGN'

  final _otp = TextEditingController();

  @override
  void dispose() {
    _otp.dispose();
    super.dispose();
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

  String get _timeText =>
      '${_fmtDate(widget.start)} - ${_fmtDate(widget.end)}  ${_fmtTime(widget.start)} - ${_fmtTime(widget.end)}';

  String _contractBody() {
    // Short but proper agreement text (mobile-friendly).
    final lines = <String>[
      'Car Rental Agreement',
      '',
      'Booking ID: ${widget.bookingId}',
      'Vehicle: ${widget.carName} (${widget.plate})',
      'Type: ${widget.type} • Seats: ${widget.seats} • Transmission: ${widget.transmission}',
      'Fuel Type: ${widget.fuelType}',
      'Outlet: ${widget.location}',
      'Rental Period: $_timeText',
      '',
      '1. Eligibility',
      'Only the renter and approved additional drivers may drive the vehicle. The renter must hold a valid driving licence and comply with Malaysian traffic laws.',
      '',
      '2. Vehicle Use',
      'The vehicle must be used for lawful purposes only. Smoking, illegal items, and reckless driving are strictly prohibited.',
      '',
      '3. Fuel & Condition',
      'The renter shall return the vehicle in reasonable condition. Fuel policy follows the outlet instructions. Damage, excessive dirt, or missing items may incur charges.',
      '',
      '4. Late Return',
      'Late returns may be charged based on the rental rate and outlet policy. The renter is responsible for any fines or penalties during the rental period.',
      '',
      '5. Payment & Fees',
      'Total payable (excluding refundable deposit and any later penalties) is RM${widget.subTotal.toStringAsFixed(2)}. Service fee and SST are included in the booking summary.',
      '',
      '6. Insurance & Protection',
      'Protection options selected on the booking page will be applied to this booking as stated in the summary.',
      '',
      '7. Acceptance',
      'By signing (OTP or E-sign), the renter agrees to the terms above.',
    ];
    return lines.join('\n');
  }

  Future<void> _markSigned({required String method, String? signatureBase64}) async {
    final now = DateTime.now();
    final payload = {
      'method': method,
      if (signatureBase64 != null) 'signature_png_base64': signatureBase64,
      'booking_id': widget.bookingId,
      'signed_at': now.toIso8601String(),
    };

    // Save sign info to contract_pdf (varchar/text) for your FYP demo.
    // Later, you can change this to store in Supabase Storage + a proper DB column.
    await _supa.from('contract').update({
      'contract_status': 'Signed',
      'signed_date': '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
      'contract_pdf': jsonEncode(payload),
    }).eq('contract_id', widget.contractId);

    if (!mounted) return;
    setState(() {
      _signed = true;
      _signedMethod = method;
    });
  }

  Future<void> _sendOtp() async {
    if (widget.userEmail.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Email not found.')));
      return;
    }

    setState(() => _sendingOtp = true);
    try {
      final code = EmailVerificationService.generateOTP();

      // For audit: store into contract row too.
      final exp = DateTime.now().add(const Duration(minutes: 10));
      await _supa.from('contract').update({
        'otp_code': code,
        'otp_expiry': exp.toIso8601String(),
        'contract_status': 'OTP Sent',
      }).eq('contract_id', widget.contractId);

      await EmailVerificationService.sendOTPEmail(widget.userEmail, code);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('OTP sent to ${widget.userEmail}')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Send OTP failed: $e')));
    } finally {
      if (mounted) setState(() => _sendingOtp = false);
    }
  }

  Future<void> _verifyOtp() async {
    final code = _otp.text.trim();
    if (code.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter 6-digit OTP.')));
      return;
    }
    setState(() => _verifyingOtp = true);
    try {
      final ok = await EmailVerificationService.verifyOTP(widget.userEmail, code);
      if (!ok) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invalid / expired OTP.')));
        return;
      }
      await _markSigned(method: 'OTP');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('OTP verified. Sign status complete.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Verify failed: $e')));
    } finally {
      if (mounted) setState(() => _verifyingOtp = false);
    }
  }

  Future<void> _openESign() async {
    final pngB64 = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      enableDrag: false,
      isDismissible: false,
      backgroundColor: Colors.transparent,
      builder: (_) => const _SignatureSheet(),
    );
    if (pngB64 == null || pngB64.isEmpty) return;

    try {
      await _markSigned(method: 'ESIGN', signatureBase64: pngB64);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Signature saved. Sign status complete.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Save signature failed: $e')));
    }
  }

  Future<void> _process() async {
    // IMPORTANT:
    // Some databases use triggers to write into rental_history on booking updates,
    // and RLS may block it (error 42501). To keep the flow working, we do NOT
    // update booking status here. We proceed to Payment page first.
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => PaymentPage(
          bookingId: widget.bookingId,
          userId: widget.userId,
          vehicleId: widget.vehicleId,
          carName: widget.carName,
          plate: widget.plate,
          dailyRate: widget.dailyRate,
          location: widget.location,
          start: widget.start,
          end: widget.end,
          rentalSubtotal: widget.rentalSubtotal,
          voucherCode: widget.voucherCode,
          voucherDiscount: widget.voucherDiscount,
          insuranceTotal: widget.insuranceTotal,
          selectedInsurance: widget.selectedInsurance,
          serviceFee: widget.serviceFee,
          sst: widget.sst,
          securityDeposit: widget.securityDeposit,
          subTotal: widget.subTotal,
        ),
      ),
    );
  }

  Widget _card({required String title, required Widget child}) {
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

  @override
  Widget build(BuildContext context) {
    final body = _contractBody();
    final statusText = _signed ? 'Complete' : 'Incomplete';
    final statusColor = _signed ? Colors.green : Colors.red;
    final methodText = _signed
        ? (_signedMethod ?? '—')
        : (_method == SignMethod.otp ? 'OTP' : 'E-sign');

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        centerTitle: true,
        title: const Text('Contract'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: ListView(
              padding: const EdgeInsets.only(bottom: 16),
              children: [
                _card(
                  title: 'Contract',
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 160),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(10),
                      color: Colors.white,
                    ),
                    child: SingleChildScrollView(
                      child: Text(body, style: const TextStyle(height: 1.35)),
                    ),
                  ),
                ),

                if (!_signed)
                  _card(
                    title: 'Sign Method',
                    child: Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 42,
                            child: (_method == SignMethod.otp)
                                ? FilledButton(
                                    onPressed: () => setState(() => _method = SignMethod.otp),
                                    child: const Text('OTP'),
                                  )
                                : OutlinedButton(
                                    onPressed: () => setState(() => _method = SignMethod.otp),
                                    child: const Text('OTP'),
                                  ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: SizedBox(
                            height: 42,
                            child: (_method == SignMethod.esign)
                                ? FilledButton(
                                    onPressed: () => setState(() => _method = SignMethod.esign),
                                    child: const Text('E-sign'),
                                  )
                                : OutlinedButton(
                                    onPressed: () => setState(() => _method = SignMethod.esign),
                                    child: const Text('E-sign'),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),

                _card(
                  title: 'Sign Status',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text('Status: ', style: TextStyle(fontWeight: FontWeight.w800)),
                          Text(statusText, style: TextStyle(fontWeight: FontWeight.w900, color: statusColor)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Text('Method: ', style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w700)),
                          Text(methodText, style: const TextStyle(fontWeight: FontWeight.w900)),
                        ],
                      ),
                    ],
                  ),
                ),

                if (!_signed && _method == SignMethod.otp)
                  _card(
                    title: 'OTP Verification',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: double.infinity,
                          height: 44,
                          child: FilledButton(
                            onPressed: _sendingOtp ? null : _sendOtp,
                            child: _sendingOtp
                                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Text('Send OTP'),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _otp,
                                keyboardType: TextInputType.number,
                                maxLength: 6,
                                decoration: const InputDecoration(
                                  counterText: '',
                                  labelText: 'OTP Code',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            SizedBox(
                              height: 48,
                              child: FilledButton(
                                onPressed: _verifyingOtp ? null : _verifyOtp,
                                child: _verifyingOtp
                                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                                    : const Text('Verify'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                if (!_signed && _method == SignMethod.esign)
                  _card(
                    title: 'E-sign',
                    child: SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: FilledButton(
                        onPressed: _openESign,
                        child: const Text('Sign Now'),
                      ),
                    ),
                  ),

                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      if (_signed)
                        SizedBox(
                          width: double.infinity,
                          height: 46,
                          child: FilledButton(
                            onPressed: _process,
                            child: const Text('Process'),
                          ),
                        ),
                      if (_signed) const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        height: 46,
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(),
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

class _SignatureSheet extends StatefulWidget {
  const _SignatureSheet();

  @override
  State<_SignatureSheet> createState() => _SignatureSheetState();
}

class _SignatureSheetState extends State<_SignatureSheet> {
  final List<Offset?> _points = [];

  void _clear() => setState(() => _points.clear());

  Future<String> _exportPngBase64() async {
    // Render into an image.
    const size = Size(900, 350);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final bg = Paint()..color = Colors.white;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bg);

    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;

    // Scale points from widget space to fixed image size.
    // We store points in local widget coordinates; use the last known box size.
    final box = _lastBoxSize;
    final sx = box == null ? 1.0 : (size.width / box.width);
    final sy = box == null ? 1.0 : (size.height / box.height);

    for (int i = 0; i < _points.length - 1; i++) {
      final p1 = _points[i];
      final p2 = _points[i + 1];
      if (p1 == null || p2 == null) continue;
      canvas.drawLine(Offset(p1.dx * sx, p1.dy * sy), Offset(p2.dx * sx, p2.dy * sy), paint);
    }

    final pic = recorder.endRecording();
    final img = await pic.toImage(size.width.toInt(), size.height.toInt());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    final raw = bytes!.buffer.asUint8List();
    return base64Encode(raw);
  }

  Size? _lastBoxSize;

  void _addPointIfInside(Offset p) {
    final box = _lastBoxSize;
    if (box == null) {
      _points.add(p);
      return;
    }
    final rect = Offset.zero & box;
    final inside = rect.contains(p);

    if (!inside) {
      // stop stroke when leaving the box
      if (_points.isNotEmpty && _points.last != null) {
        _points.add(null);
      }
      return;
    }
    _points.add(p);
  }


  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets;
    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text('E-sign', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                LayoutBuilder(
                  builder: (context, c) {
                    _lastBoxSize = Size(c.maxWidth, 180);
                    return Container(
                      height: 180,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanStart: (d) => setState(() => _addPointIfInside(d.localPosition)),
                        onPanUpdate: (d) => setState(() => _addPointIfInside(d.localPosition)),
                        onPanEnd: (_) => setState(() => _points.add(null)),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: CustomPaint(
                          painter: _SignaturePainter(_points),
                          size: Size.infinite,
                        ),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _clear,
                        child: const Text('Clear'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: _points.whereType<Offset>().isEmpty
                            ? null
                            : () async {
                                final b64 = await _exportPngBase64();
                                if (!context.mounted) return;
                                Navigator.of(context).pop(b64);
                              },
                        child: const Text('Save'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Sign inside the box. Your signature will be saved to the booking contract.',
                  style: TextStyle(color: Colors.grey.shade700),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SignaturePainter extends CustomPainter {
  final List<Offset?> points;
  const _SignaturePainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;

    for (int i = 0; i < points.length - 1; i++) {
      final p1 = points[i];
      final p2 = points[i + 1];
      if (p1 == null || p2 == null) continue;
      canvas.drawLine(p1, p2, paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SignaturePainter oldDelegate) => oldDelegate.points != points;
}