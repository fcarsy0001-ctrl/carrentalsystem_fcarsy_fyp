import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../shell/main_shell.dart';
import 'my_orders_page.dart';

/// Payment page (UI + simple simulated payment).
///
/// Shows payment summary, allows selecting payment method (Card / TNG / Stripe),
/// and writes a payment record to Supabase when user taps "Payment".
class PaymentPage extends StatefulWidget {
  const PaymentPage({
    super.key,
    required this.bookingId,
    required this.userId,
    required this.vehicleId,
    required this.carName,
    required this.plate,
    required this.dailyRate,
    required this.location,
    required this.start,
    required this.end,
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
  final String userId;
  final String vehicleId;
  final String carName;
  final String plate;
  final double dailyRate;
  final String location;
  final DateTime start;
  final DateTime end;

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
  State<PaymentPage> createState() => _PaymentPageState();
}

enum PayMethod { card, tng, stripe }

class _PaymentPageState extends State<PaymentPage> {
  SupabaseClient get _supa => Supabase.instance.client;

  PayMethod _method = PayMethod.card;
  bool _paying = false;

  final _cardNameCtrl = TextEditingController();
  final _cardNoCtrl = TextEditingController();
  final _cardExpCtrl = TextEditingController();
  final _cardCvvCtrl = TextEditingController();

  final _tngRefCtrl = TextEditingController();

  @override
  void dispose() {
    _cardNameCtrl.dispose();
    _cardNoCtrl.dispose();
    _cardExpCtrl.dispose();
    _cardCvvCtrl.dispose();
    _tngRefCtrl.dispose();
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

  double _hours() {
    final mins = widget.end.difference(widget.start).inMinutes;
    return math.max(0, mins) / 60.0;
  }

  String get _durationText => '${_hours().toStringAsFixed(_hours() % 1 == 0 ? 0 : 2)} hours';

  String _methodText(PayMethod m) {
    switch (m) {
      case PayMethod.card:
        return 'Card';
      case PayMethod.tng:
        return 'TNG';
      case PayMethod.stripe:
        return 'Stripe';
    }
  }

  String _dateOnly(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _shortId(String prefix) {
    // Keep IDs short to avoid varchar(10) constraints.
    final ms = DateTime.now().millisecondsSinceEpoch.toString();
    return prefix + ms.substring(ms.length - 8); // 2 + 8 = 10 chars
  }

  Future<bool> _simulateGateway(PayMethod method) async {
    // Simulated gateway: realistic delay + high success rate for demo.
    await Future.delayed(const Duration(seconds: 2));
    final r = DateTime.now().millisecondsSinceEpoch % 100;
    switch (method) {
      case PayMethod.card:
        return r < 95;
      case PayMethod.stripe:
        return r < 90;
      case PayMethod.tng:
        return r < 88;
    }
  }

  Future<bool> _writePaymentToDb({
    required bool success,
    required String method,
    required double amount,
    required String reference,
  }) async {
    final now = DateTime.now();
    final paymentId = _shortId('PM');
    try {
      await _supa.from('payment').insert({
        'payment_id': paymentId,
        'booking_id': widget.bookingId,
        'payment_date': _dateOnly(now),
        'payment_method': method,
        'payment_status': success ? 'Paid' : 'Failed',
        'amount_paid': amount,
        'payment_reference': reference,
      });
    } on PostgrestException catch (e) {
      // RLS blocked (42501) -> still allow demo flow to continue.
      if (e.code == '42501') return false;
      rethrow;
    }

    // Optional: receipt row (ignore if your DB doesn't require it / RLS blocks it).
    try {
      await _supa.from('receipt').insert({
        'receipt_id': _shortId('RC'),
        'payment_id': paymentId,
        'receipt_date': _dateOnly(now),
        'receipt_detail': 'Car rental payment',
        'amount_paid': amount,
        'reference_no': reference,
      });
    } catch (_) {}

    // Optional: booking status update (may trigger rental_history RLS in some setups).
    if (success) {
      try {
        await _supa.from('booking').update({'booking_status': 'Paid'}).eq('booking_id', widget.bookingId);
      } catch (_) {}
    }

    return true;
  }

  Future<void> _doPayment() async {
    setState(() => _paying = true);
    final method = _methodText(_method);
    final amount = widget.subTotal + widget.securityDeposit;
    String _digits(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

    // Validate + create short reference (<= 10 chars) for DB safety.
    String ref;
    try {
      if (_method == PayMethod.card) {
        final name = _cardNameCtrl.text.trim();
        final digits = _digits(_cardNoCtrl.text);
        final exp = _cardExpCtrl.text.trim();
        final cvv = _digits(_cardCvvCtrl.text);

        if (name.isEmpty) throw 'Please enter cardholder name.';
        if (digits.length < 12) throw 'Please enter a valid card number.';
        if (!RegExp(r'^\d{2}/\d{2}$').hasMatch(exp)) throw 'Expiry must be MM/YY.';
        if (cvv.length < 3 || cvv.length > 4) throw 'CVV must be 3-4 digits.';

        final last4 = digits.substring(digits.length - 4);
        // 2 + 4 + 4 = 10
        ref = 'CD$last4${(DateTime.now().millisecondsSinceEpoch % 10000).toString().padLeft(4, '0')}';
      } else if (_method == PayMethod.tng) {
        final tng = _tngRefCtrl.text.trim();
        if (tng.isEmpty) throw 'Enter TNG reference / phone.';
        final clean = _digits(tng);
        final tail = clean.isEmpty
            ? (DateTime.now().millisecondsSinceEpoch % 10000000).toString().padLeft(7, '0')
            : clean.substring(math.max(0, clean.length - 7));
        // 3 + 7 = 10
        ref = 'TNG$tail';
      } else {
        // 3 + 7 = 10
        ref = 'STP${(DateTime.now().millisecondsSinceEpoch % 10000000).toString().padLeft(7, '0')}';
      }

      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );

      final ok = await _simulateGateway(_method);
      if (mounted) Navigator.of(context).pop();

      final dbOk = await _writePaymentToDb(success: ok, method: method, amount: amount, reference: ref);
      if (!dbOk && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Payment record blocked by RLS (demo continues). Add payment INSERT policy in Supabase.'),
          ),
        );
      }

      if (!mounted) return;
      if (ok) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => PaymentSuccessPage(
              bookingId: widget.bookingId,
              amount: amount,
              method: method,
              reference: ref,
              carName: widget.carName,
              plate: widget.plate,
              location: widget.location,
              start: widget.start,
              end: widget.end,
            ),
          ),
          (route) => false,
        );
      } else {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PaymentFailedPage(
              bookingId: widget.bookingId,
              amount: amount,
              method: method,
              onRetry: () {
                Navigator.of(context).pop();
                _doPayment();
              },
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Payment failed: $e')));
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 175,
            child: Text(k, style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w600)),
          ),
          Expanded(child: Text(v, style: const TextStyle(fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }

  
  Widget _methodFields() {
    switch (_method) {
      case PayMethod.card:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 12),
            TextField(
              controller: _cardNameCtrl,
              decoration: const InputDecoration(
                labelText: 'Cardholder Name',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _cardNoCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Card Number (demo)',
                hintText: 'e.g. 4242 4242 4242 4242',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _cardExpCtrl,
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
                    controller: _cardCvvCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'CVV',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    obscureText: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Demo only: we do not store card number. We save only payment method and a masked reference.',
              style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
            ),
          ],
        );
      case PayMethod.tng:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Touch 'n Go eWallet", style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Text(
                    'Scan QR / make transfer in TNG app, then enter reference below (demo).',
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    height: 140,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: const Text('QR CODE (demo)'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _tngRefCtrl,
              decoration: const InputDecoration(
                labelText: 'TNG Reference / Phone (demo)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        );
      case PayMethod.stripe:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Stripe', style: TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Text(
                    'Demo flow: tap Payment to simulate Stripe success and save the payment record.',
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                ],
              ),
            ),
          ],
        );
    }
  }

Widget _segButton({required String text, required bool selected, required VoidCallback onTap}) {
    return Expanded(
      child: SizedBox(
        height: 34,
        child: selected
            ? FilledButton(
                style: FilledButton.styleFrom(padding: EdgeInsets.zero),
                onPressed: onTap,
                child: Text(text),
              )
            : OutlinedButton(
                style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
                onPressed: onTap,
                child: Text(text),
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hourly = widget.dailyRate / 24.0;
    final grandTotal = widget.subTotal + widget.securityDeposit;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const MainShell()),
              (route) => false,
            );
          },
        ),
        centerTitle: true,
        title: const Text('Payment'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Payment Details', style: TextStyle(fontWeight: FontWeight.w900)),
                        const SizedBox(height: 10),
                        _kv('Booking ID', widget.bookingId),
                        _kv('Rental Rate', 'RM${widget.dailyRate.toStringAsFixed(0)} / day'),
                        _kv('Rental Duration', _durationText),
                        _kv(
                          'Rental Charges',
                          'RM${widget.dailyRate.toStringAsFixed(0)} ÷ 24 = RM${hourly.toStringAsFixed(2)}/hr × ${_hours().toStringAsFixed(_hours() % 1 == 0 ? 0 : 2)} hr = RM${(hourly * _hours()).toStringAsFixed(2)}',
                        ),
                        if (widget.voucherDiscount > 0)
                          _kv('Voucher (${widget.voucherCode ?? '-'})', '-RM${widget.voucherDiscount.toStringAsFixed(2)}'),
                        if (widget.voucherDiscount > 0)
                          _kv('Rental after voucher', 'RM${widget.rentalSubtotal.toStringAsFixed(2)}'),
                        _kv('Insurance & Protection', 'RM${widget.insuranceTotal.toStringAsFixed(2)}'),
                        if (widget.selectedInsurance.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(left: 8, bottom: 8),
                            child: Text(
                              widget.selectedInsurance.join(', '),
                              style: TextStyle(color: Colors.grey.shade700, height: 1.25),
                            ),
                          ),
                        _kv('Service / Processing fee', 'RM${widget.serviceFee.toStringAsFixed(2)}'),
                        _kv('SST (6%)', 'RM${widget.sst.toStringAsFixed(2)}'),
                        const Divider(height: 18),
                        _kv('Sub-total', 'RM${widget.subTotal.toStringAsFixed(2)}'),
                        _kv('Refundable Security Deposit', 'RM${widget.securityDeposit.toStringAsFixed(2)}'),
                        const Divider(height: 18),
                        Row(
                          children: [
                            const Expanded(child: Text('Grand Total', style: TextStyle(fontWeight: FontWeight.w900))),
                            Text('RM${grandTotal.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w900)),
                          ],
                        ),
                        _methodFields(),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Payment Method', style: TextStyle(fontWeight: FontWeight.w900)),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            _segButton(
                              text: 'Card',
                              selected: _method == PayMethod.card,
                              onTap: () => setState(() => _method = PayMethod.card),
                            ),
                            const SizedBox(width: 8),
                            _segButton(
                              text: 'TNG',
                              selected: _method == PayMethod.tng,
                              onTap: () => setState(() => _method = PayMethod.tng),
                            ),
                            const SizedBox(width: 8),
                            _segButton(
                              text: 'Stripe',
                              selected: _method == PayMethod.stripe,
                              onTap: () => setState(() => _method = PayMethod.stripe),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: FilledButton(
                    onPressed: _paying ? null : _doPayment,
                    child: _paying
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Payment'),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: OutlinedButton(
                    onPressed: _paying ? null : () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
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

class PaymentSuccessPage extends StatelessWidget {
  const PaymentSuccessPage({
    super.key,
    required this.bookingId,
    required this.amount,
    required this.method,
    required this.reference,
    required this.carName,
    required this.plate,
    required this.location,
    required this.start,
    required this.end,
  });

  final String bookingId;
  final double amount;
  final String method;
  final String reference;
  final String carName;
  final String plate;
  final String location;
  final DateTime start;
  final DateTime end;

  String _fmtDate(DateTime d) => '${d.day}/${d.month}/${d.year}';

  String _fmtTime(DateTime d) {
    var h = d.hour;
    final m = d.minute.toString().padLeft(2, '0');
    final ap = h >= 12 ? 'pm' : 'am';
    h %= 12;
    if (h == 0) h = 12;
    return '$h:$m$ap';
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const MainShell()),
          (route) => false,
        );
        return false;
      },
      child: Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const MainShell()),
              (route) => false,
            );
          },
        ),
        centerTitle: true,
        title: const Text('Payment'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 240,
                    height: 240,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Center(
                      child: Icon(Icons.check, size: 90, color: Colors.black.withOpacity(0.8)),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Payment Successfully',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Colors.green.shade700,
                    ),
                  ),
                  const Spacer(),

                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const MyOrdersPage()),
                        );
                      },
                      child: const Text('My Orders'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: FilledButton(
                      onPressed: () {
                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(builder: (_) => const MainShell()),
                          (route) => false,
                        );
                      },
                      child: const Text('Back to Home'),
                    ),
                  ),
                  const SizedBox(height: 6),
                ],
              ),
            ),
          ),
        ),
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
}

class PaymentFailedPage extends StatelessWidget {
  const PaymentFailedPage({
    super.key,
    required this.bookingId,
    required this.amount,
    required this.method,
    required this.onRetry,
  });

  final String bookingId;
  final double amount;
  final String method;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const MainShell()),
          (route) => false,
        );
        return false;
      },
      child: Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const MainShell()),
              (route) => false,
            );
          },
        ),
        centerTitle: true,
        title: const Text('Payment'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error, color: Colors.red.shade700),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Payment Failed',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Details', style: TextStyle(fontWeight: FontWeight.w900)),
                        const SizedBox(height: 10),
                        _kv('Booking ID', bookingId),
                        _kv('Method', method),
                        _kv('Amount', 'RM${amount.toStringAsFixed(2)}'),
                        const SizedBox(height: 6),
                        Text(
                          'This is a simulated gateway flow (for testing). You can retry now.',
                          style: TextStyle(color: Colors.grey.shade700, height: 1.3),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 46,
                  child: FilledButton(
                    onPressed: onRetry,
                    child: const Text('Try Again'),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 46,
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Back'),
                  ),
                ),
              ],
            ),
          ),
        ),
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
}
