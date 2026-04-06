import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../services/order_bill_service.dart';
import '../../../../services/wallet_service.dart';
import 'wallet_top_up_checkout_page.dart';

class WalletPage extends StatefulWidget {
  const WalletPage({super.key});

  @override
  State<WalletPage> createState() => _WalletPageState();
}

class _WalletPageState extends State<WalletPage> {
  final WalletService _walletService = WalletService();
  final OrderBillService _orderBillService = OrderBillService();
  final TextEditingController _amountController = TextEditingController();

  bool _loading = true;
  double _balance = 0;
  List<Map<String, dynamic>> _transactions = const [];
  List<Map<String, dynamic>> _pendingBills = const [];
  final Set<String> _payingBillIds = <String>{};

  Future<String> _resolveUserId() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) throw Exception('No user logged in');

    final row = await Supabase.instance.client
        .from('app_user')
        .select('user_id')
        .eq('auth_uid', user.id)
        .maybeSingle();

    final userId = (row?['user_id'] ?? '').toString().trim();
    if (userId.isEmpty) {
      throw Exception('User profile is not ready yet.');
    }
    return userId;
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final userId = await _resolveUserId();
      final balance = await _walletService.getWalletBalance(userId);
      final tx = await _walletService.getWalletTransactions(userId);
      final bills = await _orderBillService.getPendingBillsByUser(userId);
      if (!mounted) return;
      setState(() {
        _balance = balance;
        _transactions = tx;
        _pendingBills = bills;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _topUp(double amount) async {
    if (amount <= 0) return;
    try {
      final userId = await _resolveUserId();
      final result = await Navigator.of(context).push<Map<String, dynamic>>(
        MaterialPageRoute(
          builder: (_) => WalletTopUpCheckoutPage(
            userId: userId,
            amount: amount,
          ),
        ),
      );
      if ((result?['success'] ?? false) != true) return;
      await _loadData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Top up successful: RM ${amount.toStringAsFixed(2)}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Top up failed: $e')),
      );
    }
  }

  Future<Map<String, dynamic>?> _showBillPaymentDialog(Map<String, dynamic> bill) async {
    final supportsWallet = _billSupportsWallet(bill);
    final billAmount = _billAmount(bill);
    final canUseWallet = supportsWallet && _balance >= billAmount;
    final insufficientWallet = supportsWallet && !canUseWallet;
    var method = canUseWallet ? 'wallet' : 'card';
    var validationMessage = '';
    final nameCtrl = TextEditingController();
    final cardNoCtrl = TextEditingController();
    final expCtrl = TextEditingController();
    final cvvCtrl = TextEditingController();

    String digitsOnly(String text) => text.replaceAll(RegExp(r'[^0-9]'), '');

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setLocalState) {
            Widget methodButton({
              required String value,
              required String label,
              required bool enabled,
            }) {
              final selected = method == value;
              return Expanded(
                child: OutlinedButton(
                  onPressed: enabled
                      ? () => setLocalState(() {
                            method = value;
                            validationMessage = '';
                          })
                      : null,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    side: BorderSide(
                      color: selected ? Theme.of(dialogContext).colorScheme.primary : Colors.grey.shade300,
                      width: selected ? 1.6 : 1,
                    ),
                    backgroundColor: selected
                        ? Theme.of(dialogContext).colorScheme.primary.withOpacity(0.08)
                        : null,
                  ),
                  child: Text(label, textAlign: TextAlign.center),
                ),
              );
            }

            void showValidation(String message) {
              setLocalState(() => validationMessage = message);
            }

            return AlertDialog(
              title: const Text('Pay billing'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _billTitle(bill),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Text('Amount: ${_money(_billAmount(bill))}'),
                    if (_billOrderId(bill).isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text('Booking ID: ${_billOrderId(bill)}'),
                    ],
                    if (_billDescription(bill).isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(_billDescription(bill)),
                    ],
                    const SizedBox(height: 14),
                    Text(
                      'Wallet balance: ${_money(_balance)}',
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        methodButton(
                          value: 'wallet',
                          label: 'Wallet',
                          enabled: canUseWallet,
                        ),
                        const SizedBox(width: 8),
                        methodButton(value: 'card', label: 'Card', enabled: true),
                      ],
                    ),
                    if (!supportsWallet) ...[
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Text(
                          'Wallet payment is not available for this billing. Please use Card.',
                          style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                        ),
                      ),
                    ] else if (insufficientWallet) ...[
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Text(
                          'Insufficient wallet balance. Current balance: ${_money(_balance)}. Only Card can be used for this billing.',
                          style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                        ),
                      ),
                    ],
                    if (method == 'wallet') ...[
                      const SizedBox(height: 12),
                      Text(
                        'This billing will be paid directly from your wallet balance.',
                        style: TextStyle(color: Colors.grey.shade700),
                      ),
                    ] else ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: nameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Cardholder Name',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onChanged: (_) {
                          if (validationMessage.isNotEmpty) {
                            setLocalState(() => validationMessage = '');
                          }
                        },
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: cardNoCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Card Number',
                          hintText: '4242 4242 4242 4242',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onChanged: (_) {
                          if (validationMessage.isNotEmpty) {
                            setLocalState(() => validationMessage = '');
                          }
                        },
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: expCtrl,
                              keyboardType: TextInputType.datetime,
                              decoration: const InputDecoration(
                                labelText: 'Expiry (MM/YY)',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              onChanged: (_) {
                                if (validationMessage.isNotEmpty) {
                                  setLocalState(() => validationMessage = '');
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: cvvCtrl,
                              obscureText: true,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'CVV',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              onChanged: (_) {
                                if (validationMessage.isNotEmpty) {
                                  setLocalState(() => validationMessage = '');
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Demo card flow only. No real card is charged.',
                        style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                      ),
                    ],
                    if (validationMessage.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        validationMessage,
                        style: const TextStyle(
                          color: Colors.red,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
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
                    if (method == 'wallet') {
                      Navigator.of(dialogContext).pop({
                        'method': 'wallet',
                        'reference': '',
                      });
                      return;
                    }

                    final name = nameCtrl.text.trim();
                    final digits = digitsOnly(cardNoCtrl.text);
                    final exp = expCtrl.text.trim();
                    final cvv = digitsOnly(cvvCtrl.text);
                    if (name.isEmpty) {
                      showValidation('Please enter cardholder name.');
                      return;
                    }
                    if (digits.length < 12) {
                      showValidation('Please enter a valid card number.');
                      return;
                    }
                    if (!RegExp(r'^\d{2}/\d{2}$').hasMatch(exp)) {
                      showValidation('Expiry must be MM/YY.');
                      return;
                    }
                    if (cvv.length < 3 || cvv.length > 4) {
                      showValidation('CVV must be 3 or 4 digits.');
                      return;
                    }
                    final reference = _buildCardReference(digits);
                    Navigator.of(dialogContext).pop({
                      'method': 'card',
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

    nameCtrl.dispose();
    cardNoCtrl.dispose();
    expCtrl.dispose();
    cvvCtrl.dispose();
    return result;
  }

  Future<void> _payBill(Map<String, dynamic> bill) async {
    final billId = _billId(bill);
    if (billId.isEmpty) return;

    final payment = await _showBillPaymentDialog(bill);
    if (payment == null || !mounted) return;

    final userId = await _resolveUserId();
    if (!mounted) return;

    final method = (payment['method'] ?? 'card').toString();
    final reference = (payment['reference'] ?? '').toString();

    setState(() => _payingBillIds.add(billId));

    try {
      if (method == 'wallet') {
        if (!_billSupportsWallet(bill)) {
          throw Exception('Wallet payment is not available for this billing.');
        }
        final result = await _walletService.payBillWithWallet(
          userId: userId,
          billId: billId,
        );
        if (result['success'] != true) {
          throw Exception((result['message'] ?? 'Wallet payment failed.').toString());
        }
      } else {
        await Future.delayed(const Duration(milliseconds: 900));
        await _orderBillService.markBillPaidExternally(
          bill: bill,
          paymentMethod: 'Card',
          referenceNo: reference,
        );
      }

      await _loadData();
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('${_billTitle(bill)} paid successfully.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('Failed to pay billing: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _payingBillIds.remove(billId));
      }
    }
  }

  String _billId(Map<String, dynamic> bill) => (bill['id'] ?? '').toString().trim();

  bool _billSupportsWallet(Map<String, dynamic> bill) => bill['supports_wallet_payment'] == true;

  double _billAmount(Map<String, dynamic> bill) => ((bill['amount'] ?? 0) as num).toDouble();

  String _billTitle(Map<String, dynamic> bill) {
    final title = (bill['title'] ?? '').toString().trim();
    if (title.isNotEmpty) return title;
    return '${_billTypeLabel(bill['bill_type'])} bill';
  }

  String _billTypeLabel(dynamic value) {
    final raw = (value ?? '').toString().trim().replaceAll('_', ' ');
    if (raw.isEmpty) return 'Other';
    final lower = raw.toLowerCase();
    if (lower == 'overtime' || lower == 'late return' || lower == 'late_return') {
      return 'Late return';
    }
    return lower
        .split(' ')
        .where((part) => part.isNotEmpty)
        .map((part) => part[0].toUpperCase() + part.substring(1))
        .join(' ');
  }

  String _billDescription(Map<String, dynamic> bill) => (bill['description'] ?? '').toString().trim();

  String _billOrderId(Map<String, dynamic> bill) => (bill['order_id'] ?? '').toString().trim();

  String _billStatus(Map<String, dynamic> bill) {
    final raw = (bill['status'] ?? '').toString().trim().toLowerCase();
    if (raw == 'paid') return 'Paid';
    return 'Pending';
  }

  String _money(num value) => 'RM ${value.toStringAsFixed(2)}';

  String _buildCardReference(String cardDigits) {
    final last4 = cardDigits.length >= 4 ? cardDigits.substring(cardDigits.length - 4) : cardDigits;
    final stamp = (DateTime.now().millisecondsSinceEpoch % 100000000)
        .toString()
        .padLeft(8, '0');
    return 'CARD-$last4-$stamp';
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Wallet')),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _WalletCard(balance: _balance, pendingBillsCount: _pendingBills.length),
            const SizedBox(height: 16),
            const Text('Quick Top Up', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [20, 50, 100, 200]
                  .map((e) => ElevatedButton(
                        onPressed: _loading ? null : () => _topUp(e.toDouble()),
                        child: Text('RM $e'),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Custom top up amount',
                suffixIcon: TextButton(
                  onPressed: _loading
                      ? null
                      : () {
                          final value = double.tryParse(_amountController.text.trim()) ?? 0;
                          _topUp(value);
                        },
                  child: const Text('Top Up'),
                ),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            const Text('Billing', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_pendingBills.isEmpty)
              const _EmptyBox(message: 'No billing')
            else
              ..._pendingBills.map((bill) {
                final billId = _billId(bill);
                final paying = _payingBillIds.contains(billId);
                final typeLabel = _billTypeLabel(bill['bill_type']);
                final description = _billDescription(bill);
                final orderId = _billOrderId(bill);
                final walletInsufficient = _billSupportsWallet(bill) && _balance < _billAmount(bill);
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.receipt_long_outlined),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _billTitle(bill),
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                            Text(
                              _money(_billAmount(bill)),
                              style: const TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _InfoChip(label: typeLabel),
                            _InfoChip(label: _billStatus(bill)),
                            if (orderId.isNotEmpty) _InfoChip(label: 'Booking $orderId'),
                          ],
                        ),
                        if (description.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Text(description),
                        ],
                        if (walletInsufficient) ...[
                          const SizedBox(height: 10),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: Text(
                              'Insufficient wallet balance: ${_money(_balance)}. Only Card can be used for this billing.',
                              style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: paying ? null : () => _payBill(bill),
                            child: paying
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text('Pay billing'),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            const SizedBox(height: 24),
            const Text('Transaction History', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            if (_loading)
              const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
            else if (_transactions.isEmpty)
              const _EmptyBox(message: 'No transactions yet')
            else
              ..._transactions.map((tx) => Card(
                    child: ListTile(
                      leading: Icon(
                        (tx['direction'] == 'credit') ? Icons.arrow_downward : Icons.arrow_upward,
                      ),
                      title: Text('${tx['tx_type'] ?? 'transaction'} • RM ${((tx['amount'] ?? 0) as num).toStringAsFixed(2)}'),
                      subtitle: Text('${tx['payment_method'] ?? '-'} • ${tx['remark'] ?? '-'}'),
                    ),
                  )),
          ],
        ),
      ),
    );
  }
}

class _WalletCard extends StatelessWidget {
  const _WalletCard({required this.balance, required this.pendingBillsCount});

  final double balance;
  final int pendingBillsCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Available Balance', style: TextStyle(color: Colors.white70)),
          const SizedBox(height: 8),
          Text(
            'RM ${balance.toStringAsFixed(2)}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Pending bills: $pendingBillsCount',
            style: const TextStyle(color: Colors.white70),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _EmptyBox extends StatelessWidget {
  const _EmptyBox({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFE5E7EB)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(message),
    );
  }
}
