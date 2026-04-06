import 'package:flutter/material.dart';

import '../../../../services/wallet_service.dart';
import '../../../../utils/card_expiry_input_formatter.dart';

class WalletTopUpCheckoutPage extends StatefulWidget {
  const WalletTopUpCheckoutPage({
    super.key,
    required this.userId,
    required this.amount,
  });

  final String userId;
  final double amount;

  @override
  State<WalletTopUpCheckoutPage> createState() => _WalletTopUpCheckoutPageState();
}

class _WalletTopUpCheckoutPageState extends State<WalletTopUpCheckoutPage> {
  final WalletService _walletService = WalletService();
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _cardNoCtrl = TextEditingController();
  final TextEditingController _expCtrl = TextEditingController();
  final TextEditingController _cvvCtrl = TextEditingController();

  bool _paying = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _cardNoCtrl.dispose();
    _expCtrl.dispose();
    _cvvCtrl.dispose();
    super.dispose();
  }

  String _digits(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

  Future<void> _payNow() async {
    final amount = widget.amount;
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid top up amount.')),
      );
      return;
    }

    final name = _nameCtrl.text.trim();
    final cardNo = _digits(_cardNoCtrl.text);
    final exp = _expCtrl.text.trim();
    final cvv = _digits(_cvvCtrl.text);

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter cardholder name.')),
      );
      return;
    }
    if (cardNo.length < 12) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid card number.')),
      );
      return;
    }
    if (!RegExp(r'^\d{2}/\d{2}$').hasMatch(exp)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Use expiry format MM/YY.')),
      );
      return;
    }
    if (cvv.length < 3 || cvv.length > 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('CVV must be 3 or 4 digits.')),
      );
      return;
    }

    setState(() => _paying = true);
    try {
      await Future.delayed(const Duration(seconds: 2));
      final generatedRef = 'ST${(DateTime.now().millisecondsSinceEpoch % 100000000).toString().padLeft(8, '0')}';
      final result = await _walletService.topUp(
        userId: widget.userId,
        amount: amount,
        paymentMethod: 'Stripe',
        referenceNo: generatedRef,
        createdBy: 'Stripe demo top up',
      );
      if (!mounted) return;
      Navigator.of(context).pop({
        'success': true,
        'amount': amount,
        'reference_no': (result['reference_no'] ?? generatedRef).toString(),
        'payment_method': 'Stripe',
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Top up failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Top Up Wallet')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: const Color(0xFF111827),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Stripe demo checkout',
                        style: TextStyle(color: Colors.white70),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'RM ${widget.amount.toStringAsFixed(2)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 30,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'This is a demo flow only. No real card is charged.',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: Row(
                    children: const [
                      Icon(Icons.credit_card),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Card (Stripe)', style: TextStyle(fontWeight: FontWeight.w700)),
                            SizedBox(height: 4),
                            Text('Use a demo card form, then wallet balance will increase after success.'),
                          ],
                        ),
                      ),
                      Icon(Icons.check_circle, color: Color(0xFF16A34A)),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _nameCtrl,
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
                    hintText: '4242 4242 4242 4242',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _expCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: const [CardExpiryInputFormatter()],
                        decoration: const InputDecoration(
                          labelText: 'Expiry (MM/YY)',
                          hintText: 'MM/YY',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _cvvCtrl,
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
                const SizedBox(height: 10),
                Text(
                  'Demo only: payment method saved as Stripe. No real gateway is used.',
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _paying ? null : _payNow,
                    icon: _paying
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.lock_outline),
                    label: Text(_paying ? 'Processing...' : 'Pay RM ${widget.amount.toStringAsFixed(2)}'),
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
