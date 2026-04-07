import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../services/order_bill_service.dart';
import '../../../../services/wallet_service.dart';
import '../../../../utils/card_expiry_input_formatter.dart';
import '../../../../services/support_ticket_service.dart';
import '../../../../support/support_chat_page.dart';
import 'wallet_top_up_checkout_page.dart';

class WalletPage extends StatefulWidget {
  const WalletPage({super.key});

  @override
  State<WalletPage> createState() => _WalletPageState();
}

class _WalletPageState extends State<WalletPage> {
  final WalletService _walletService = WalletService();
  final OrderBillService _orderBillService = OrderBillService();
  final SupportTicketService _supportService = SupportTicketService(Supabase.instance.client);
  final TextEditingController _amountController = TextEditingController();

  bool _loading = true;
  double _balance = 0;
  List<Map<String, dynamic>> _transactions = const [];
  List<Map<String, dynamic>> _pendingBills = const [];
  final Set<String> _payingBillIds = <String>{};
  String _transactionHistoryFilter = 'All';

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
                              keyboardType: TextInputType.number,
                              inputFormatters: const [CardExpiryInputFormatter()],
                              decoration: const InputDecoration(
                                labelText: 'Expiry (MM/YY)',
                                hintText: 'MM/YY',
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


  String _billSupportMessage(Map<String, dynamic> bill) {
    final lines = <String>[
      'I want to appeal / dispute this billing.',
      '',
      '[BILL_LINK]',
      'Bill Source: ${_s(bill['source']).isEmpty ? 'unknown' : _s(bill['source'])}',
      'Bill ID: ${_billId(bill).isEmpty ? '-' : _billId(bill)}',
      'Booking ID: ${_billOrderId(bill).isEmpty ? '-' : _billOrderId(bill)}',
      'Bill Title: ${_billTitle(bill)}',
      'Bill Type: ${_billTypeLabel(bill['bill_type'])}',
      'Amount: ${_money(_billAmount(bill))}',
      'Status: ${_billStatus(bill)}',
      '[/BILL_LINK]',
    ];

    final description = _billDescription(bill);
    if (description.isNotEmpty) {
      lines
        ..add('')
        ..add('Bill detail:')
        ..add(description);
    }

    final photoUrl = _billPhotoUrl(bill);
    if (photoUrl != null && photoUrl.isNotEmpty) {
      lines
        ..add('')
        ..add('Billing photo: $photoUrl');
    }

    lines
      ..add('')
      ..add('Please review this billing and help me appeal it.');
    return lines.join('\n');
  }

  Future<void> _openBillSupport(Map<String, dynamic> bill) async {
    try {
      final existingOpenTicket = await _supportService.getOpenTicketForCurrentUser();
      final message = _billSupportMessage(bill);
      final title = 'Billing appeal • ${_billTitle(bill)}';

      Map<String, dynamic> ticket;
      var appendedToExisting = false;
      if (existingOpenTicket != null) {
        ticket = existingOpenTicket;
        await _supportService.sendMessage(
          ticketId: _s(ticket['ticket_id']),
          message: message,
        );
        appendedToExisting = true;
      } else {
        ticket = await _supportService.createTicket(
          title: title.length > 80 ? title.substring(0, 80) : title,
          ticketType: 'Payment Issue',
          message: message,
        );
      }

      if (!mounted) return;
      final ticketId = _s(ticket['ticket_id']);
      if (ticketId.isEmpty) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SupportChatPage(ticketId: ticketId),
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            appendedToExisting
                ? 'Bill details were added to your existing support case.'
                : 'Support case created for this billing.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('Failed to open support: $e')),
      );
    }
  }

  String _s(dynamic value) => value == null ? '' : value.toString().trim();


  double _txAmountValue(Map<String, dynamic> tx) {
    final raw = tx['amount'];
    if (raw is num) return raw.toDouble();
    return double.tryParse(raw?.toString() ?? '') ?? 0;
  }

  String _normalizeWalletTxType(dynamic value) {
    return (value ?? '').toString().trim().toLowerCase().replaceAll(' ', '_');
  }

  bool _isCreditTransaction(Map<String, dynamic> tx) {
    final direction = (tx['direction'] ?? '').toString().trim().toLowerCase();
    if (direction == 'credit') return true;
    if (direction == 'debit') return false;

    final type = _normalizeWalletTxType(tx['tx_type']);
    return type.contains('top_up') ||
        type.contains('topup') ||
        type.contains('refund') ||
        type.contains('cashback') ||
        type.contains('credit');
  }

  DateTime? _transactionDateTime(Map<String, dynamic> tx) {
    final raw = (tx['created_at'] ?? tx['transaction_date'] ?? tx['date'] ?? '').toString().trim();
    if (raw.isEmpty) return null;
    return DateTime.tryParse(raw)?.toLocal();
  }

  String _monthShort(int month) {
    const months = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    if (month < 1 || month > 12) return '-';
    return months[month - 1];
  }

  String _transactionGroupKey(DateTime? dateTime) {
    if (dateTime == null) return 'unknown';
    return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')}';
  }

  String _transactionGroupLabel(DateTime? dateTime) {
    if (dateTime == null) return 'Older';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final thatDay = DateTime(dateTime.year, dateTime.month, dateTime.day);
    final diff = today.difference(thatDay).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return '${_monthShort(dateTime.month)} ${dateTime.day}, ${dateTime.year}';
  }

  String _transactionTimeLabel(DateTime? dateTime) {
    if (dateTime == null) return '-';
    final hour = dateTime.hour % 12 == 0 ? 12 : dateTime.hour % 12;
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final amPm = dateTime.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $amPm';
  }

  String _transactionTitle(Map<String, dynamic> tx) {
    final type = _normalizeWalletTxType(tx['tx_type']);
    if (type.contains('top_up') || type.contains('topup')) return 'Top Up';
    if (type.contains('order_payment') || type.contains('booking_payment') || type.contains('rental_payment')) {
      return 'Order Payment';
    }
    if (type.contains('extra_charge') || type.contains('bill_payment')) {
      return 'Order Billing';
    }
    if (type.contains('refund')) return 'Refund';
    if (_isCreditTransaction(tx)) return 'Wallet Credit';
    return 'Wallet Payment';
  }

  String _transactionBadge(Map<String, dynamic> tx) {
    final type = _normalizeWalletTxType(tx['tx_type']);
    if (type.contains('top_up') || type.contains('topup')) return 'Top Up';
    if (type.contains('order_payment') || type.contains('booking_payment') || type.contains('rental_payment')) {
      return 'Order Payment';
    }
    if (type.contains('extra_charge') || type.contains('bill_payment')) {
      return 'Billing';
    }
    if (type.contains('refund')) return 'Refund';
    return _isCreditTransaction(tx) ? 'Money In' : 'Money Out';
  }

  IconData _transactionIcon(Map<String, dynamic> tx) {
    if (_isCreditTransaction(tx)) return Icons.south_west_rounded;
    return Icons.north_east_rounded;
  }

  Color _transactionAccent(Map<String, dynamic> tx) {
    if (_isCreditTransaction(tx)) return const Color(0xFF15803D);
    return const Color(0xFFDC2626);
  }

  String _transactionAmountText(Map<String, dynamic> tx) {
    final amount = _txAmountValue(tx).toStringAsFixed(2);
    final sign = _isCreditTransaction(tx) ? '+' : '-';
    return '$sign RM $amount';
  }

  String _transactionPrimaryText(Map<String, dynamic> tx) {
    final remark = (tx['remark'] ?? '').toString().trim();
    if (remark.isNotEmpty) return remark;
    final method = (tx['payment_method'] ?? '').toString().trim();
    if (method.isNotEmpty) return 'Via $method';
    return 'Wallet activity recorded.';
  }

  String _transactionSecondaryText(Map<String, dynamic> tx) {
    final parts = <String>[];
    final method = (tx['payment_method'] ?? '').toString().trim();
    if (method.isNotEmpty) parts.add(method);
    final bookingId = (tx['related_booking_id'] ?? tx['booking_id'] ?? '').toString().trim();
    if (bookingId.isNotEmpty) parts.add('Booking $bookingId');
    final reference = (tx['reference_no'] ?? '').toString().trim();
    if (reference.isNotEmpty) parts.add('Ref $reference');
    parts.add(_transactionTimeLabel(_transactionDateTime(tx)));
    return parts.join(' • ');
  }

  String? _billPhotoUrl(Map<String, dynamic> bill) {
    final direct = (bill['photo_url'] ?? '').toString().trim();
    if (direct.isNotEmpty) return direct;
    final path = (bill['photo_path'] ?? '').toString().trim();
    if (path.isEmpty) return null;
    try {
      return Supabase.instance.client.storage.from('booking_evidence').getPublicUrl(path);
    } catch (_) {
      return null;
    }
  }

  List<Map<String, dynamic>> get _filteredTransactions {
    if (_transactionHistoryFilter == 'All') return _transactions;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return _transactions.where((tx) {
      final dt = _transactionDateTime(tx);
      if (dt == null) return _transactionHistoryFilter == 'Older';
      final day = DateTime(dt.year, dt.month, dt.day);
      final diff = today.difference(day).inDays;
      switch (_transactionHistoryFilter) {
        case 'Recent 3 Days':
          return diff >= 0 && diff <= 2;
        case 'This Month':
          return dt.year == now.year && dt.month == now.month;
        case 'Older':
          return diff > 2;
        default:
          return true;
      }
    }).toList(growable: false);
  }

  List<Widget> _buildTransactionHistoryWidgets() {
    final widgets = <Widget>[];
    String? lastGroup;

    for (final tx in _filteredTransactions) {
      final dateTime = _transactionDateTime(tx);
      final group = _transactionGroupKey(dateTime);
      if (group != lastGroup) {
        if (widgets.isNotEmpty) {
          widgets.add(const SizedBox(height: 6));
        }
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 10),
            child: Text(
              _transactionGroupLabel(dateTime),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade700,
              ),
            ),
          ),
        );
        lastGroup = group;
      }

      widgets.add(
        _BankTransactionTile(
          accent: _transactionAccent(tx),
          icon: _transactionIcon(tx),
          title: _transactionTitle(tx),
          primaryText: _transactionPrimaryText(tx),
          secondaryText: _transactionSecondaryText(tx),
          amountText: _transactionAmountText(tx),
          badgeText: _transactionBadge(tx),
        ),
      );
      widgets.add(const SizedBox(height: 10));
    }

    if (widgets.isNotEmpty && widgets.last is SizedBox) {
      widgets.removeLast();
    }
    return widgets;
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
                final photoUrl = _billPhotoUrl(bill);
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
                            PopupMenuButton<String>(
                              tooltip: 'More',
                              onSelected: (value) {
                                if (value == 'support') {
                                  _openBillSupport(bill);
                                }
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem<String>(
                                  value: 'support',
                                  child: Text('Appeal to admin/staff'),
                                ),
                              ],
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
                        if (photoUrl != null) ...[
                          const SizedBox(height: 10),
                          _BillPhotoDropdown(
                            imageUrl: photoUrl,
                            title: 'Billing picture',
                          ),
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
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Transaction History',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                if (!_loading)
                  Text(
                    '${_filteredTransactions.length} item(s)',
                    style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                'All',
                'Recent 3 Days',
                'This Month',
                'Older',
              ]
                  .map(
                    (filter) => FilterChip(
                      label: Text(filter),
                      selected: _transactionHistoryFilter == filter,
                      onSelected: (_) => setState(() => _transactionHistoryFilter = filter),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
            else if (_transactions.isEmpty)
              const _EmptyBox(message: 'No transactions yet')
            else if (_filteredTransactions.isEmpty)
              const _EmptyBox(message: 'No transactions found for this filter')
            else
              ..._buildTransactionHistoryWidgets(),
          ],
        ),
      ),
    );
  }
}


class _BankTransactionTile extends StatelessWidget {
  const _BankTransactionTile({
    required this.accent,
    required this.icon,
    required this.title,
    required this.primaryText,
    required this.secondaryText,
    required this.amountText,
    required this.badgeText,
  });

  final Color accent;
  final IconData icon;
  final String title;
  final String primaryText;
  final String secondaryText;
  final String amountText;
  final String badgeText;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: accent.withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  primaryText,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  secondaryText,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                amountText,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: accent,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  badgeText,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BillPhotoDropdown extends StatefulWidget {
  const _BillPhotoDropdown({
    required this.imageUrl,
    this.title = 'Billing picture',
  });

  final String imageUrl;
  final String title;

  @override
  State<_BillPhotoDropdown> createState() => _BillPhotoDropdownState();
}

class _BillPhotoDropdownState extends State<_BillPhotoDropdown> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        children: [
          ListTile(
            dense: true,
            leading: const Icon(Icons.image_outlined),
            title: Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(_expanded ? 'Tap to hide picture' : 'Tap to view picture'),
            trailing: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
            onTap: () => setState(() => _expanded = !_expanded),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Image.network(
                    widget.imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: Colors.grey.shade200,
                      alignment: Alignment.center,
                      child: const Text('Unable to load picture'),
                    ),
                    loadingBuilder: (context, child, progress) {
                      if (progress == null) return child;
                      return Container(
                        color: Colors.grey.shade100,
                        alignment: Alignment.center,
                        child: const CircularProgressIndicator(),
                      );
                    },
                  ),
                ),
              ),
            ),
        ],
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
