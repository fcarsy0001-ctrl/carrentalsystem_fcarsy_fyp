import 'package:supabase_flutter/supabase_flutter.dart';

class WalletService {
  WalletService({SupabaseClient? client})
      : _supabase = client ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  Future<double> getWalletBalance(String userId) async {
    final snapshot = await _getWalletSnapshot(userId);
    return _resolvedWalletBalance(snapshot);
  }

  Future<List<Map<String, dynamic>>> getWalletTransactions(String userId) async {
    final rows = await _supabase
        .from('wallet_transactions')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(rows);
  }

  Future<Map<String, dynamic>> topUp({
    required String userId,
    required double amount,
    String paymentMethod = 'Online',
    String? referenceNo,
    String? createdBy,
  }) async {
    final res = await _supabase.rpc('wallet_top_up', params: {
      'p_user_id': userId,
      'p_amount': amount,
      'p_payment_method': paymentMethod,
      'p_reference_no': referenceNo,
      'p_created_by': createdBy,
    });

    return Map<String, dynamic>.from(res as Map);
  }

  Future<Map<String, dynamic>> payOrderWithWallet({
    required String userId,
    required String orderId,
    required double amount,
  }) async {
    final res = await _supabase.rpc('wallet_pay_order', params: {
      'p_user_id': userId,
      'p_order_id': orderId,
      'p_amount': amount,
    });

    return Map<String, dynamic>.from(res as Map);
  }

  Future<Map<String, dynamic>> payBillWithWallet({
    required String userId,
    required String billId,
  }) async {
    return _payBookingExtraChargeWithWalletFallback(
      userId: userId,
      billId: billId,
    );
  }

  double _moneyValue(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0.0;
  }

  bool _sameMoney(double a, double b) => (a - b).abs() < 0.005;

  DateTime? _parseTime(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  Future<Map<String, dynamic>?> _getWalletRowFromTable({
    required String table,
    required String userId,
  }) async {
    final row = await _supabase
        .from(table)
        .select('*')
        .eq('user_id', userId)
        .maybeSingle();
    return row == null ? null : Map<String, dynamic>.from(row);
  }

  Future<Map<String, Map<String, dynamic>?>> _getWalletSnapshot(String userId) async {
    final walletsRow = await _getWalletRowFromTable(
      table: 'user_wallets',
      userId: userId,
    );
    final walletRow = await _getWalletRowFromTable(
      table: 'user_wallet',
      userId: userId,
    );

    return {
      'user_wallets': walletsRow,
      'user_wallet': walletRow,
    };
  }

  double _resolvedWalletBalance(Map<String, Map<String, dynamic>?> snapshot) {
    final walletsRow = snapshot['user_wallets'];
    final walletRow = snapshot['user_wallet'];

    if (walletsRow == null && walletRow == null) return 0.0;
    if (walletsRow != null && walletRow == null) {
      return _moneyValue(walletsRow['balance']);
    }
    if (walletsRow == null && walletRow != null) {
      return _moneyValue(walletRow['balance']);
    }

    final walletsUpdatedAt = _parseTime(walletsRow?['updated_at']);
    final walletUpdatedAt = _parseTime(walletRow?['updated_at']);

    if (walletsUpdatedAt != null && walletUpdatedAt != null) {
      if (walletUpdatedAt.isAfter(walletsUpdatedAt)) {
        return _moneyValue(walletRow?['balance']);
      }
      return _moneyValue(walletsRow?['balance']);
    }

    return _moneyValue(walletsRow?['balance']);
  }

  Future<bool> _verifyWalletBalance({
    required String userId,
    required double expectedBalance,
  }) async {
    final snapshot = await _getWalletSnapshot(userId);
    if (_sameMoney(_resolvedWalletBalance(snapshot), expectedBalance)) {
      return true;
    }

    final walletsRow = snapshot['user_wallets'];
    if (walletsRow != null && _sameMoney(_moneyValue(walletsRow['balance']), expectedBalance)) {
      return true;
    }

    final walletRow = snapshot['user_wallet'];
    if (walletRow != null && _sameMoney(_moneyValue(walletRow['balance']), expectedBalance)) {
      return true;
    }

    return false;
  }

  Future<bool> _tryWalletBalanceUpdate({
    required String userId,
    required Map<String, Map<String, dynamic>?> snapshot,
    required double newBalance,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final walletsRow = snapshot['user_wallets'];
    final walletRow = snapshot['user_wallet'];

    Future<bool> verify() async {
      return _verifyWalletBalance(
        userId: userId,
        expectedBalance: newBalance,
      );
    }

    Future<bool> tryRun(Future<void> Function() action) async {
      try {
        await action();
        return await verify();
      } catch (_) {
        return false;
      }
    }

    final attempts = <Future<bool> Function()>[
      if (walletsRow != null)
        () => tryRun(() async {
              await _supabase.from('user_wallets').update({
                'balance': newBalance,
                'updated_at': now,
              }).eq('user_id', userId);
            }),
      if (walletRow != null && (walletRow['wallet_id'] ?? '').toString().trim().isNotEmpty)
        () => tryRun(() async {
              await _supabase.from('user_wallet').update({
                'balance': newBalance,
                'updated_at': now,
              }).eq('wallet_id', (walletRow['wallet_id'] ?? '').toString().trim());
            }),
      if (walletRow != null)
        () => tryRun(() async {
              await _supabase.from('user_wallet').update({
                'balance': newBalance,
                'updated_at': now,
              }).eq('user_id', userId);
            }),
      () => tryRun(() async {
            await _supabase.from('user_wallets').upsert({
              'user_id': userId,
              'balance': newBalance,
              'updated_at': now,
            }, onConflict: 'user_id');
          }),
      () => tryRun(() async {
            final payload = <String, dynamic>{
              'user_id': userId,
              'balance': newBalance,
              'updated_at': now,
            };
            final walletId = (walletRow?['wallet_id'] ?? '').toString().trim();
            if (walletId.isNotEmpty) {
              payload['wallet_id'] = walletId;
            }
            await _supabase
                .from('user_wallet')
                .upsert(payload, onConflict: 'user_id');
          }),
      () async {
        var changed = false;
        try {
          await _supabase.from('user_wallets').update({
            'balance': newBalance,
            'updated_at': now,
          }).eq('user_id', userId);
          changed = true;
        } catch (_) {}
        try {
          await _supabase.from('user_wallet').update({
            'balance': newBalance,
            'updated_at': now,
          }).eq('user_id', userId);
          changed = true;
        } catch (_) {}
        if (!changed) return false;
        return verify();
      },
    ];

    for (final attempt in attempts) {
      final ok = await attempt();
      if (ok) return true;
    }
    return false;
  }

  Future<void> _logWalletBillPayment({
    required String userId,
    required String billId,
    required String bookingId,
    required double amount,
    required String referenceNo,
    required String remark,
  }) async {
    try {
      await _supabase.from('wallet_transactions').insert({
        'user_id': userId,
        'amount': amount,
        'direction': 'debit',
        'tx_type': 'extra_charge_payment',
        'payment_method': 'Wallet',
        'reference_no': referenceNo,
        'remark': remark,
        if (bookingId.isNotEmpty) 'related_booking_id': bookingId,
        'related_bill_id': billId,
      });
    } catch (_) {}

    try {
      await _supabase.from('wallet_transaction').insert({
        'user_id': userId,
        if (bookingId.isNotEmpty) 'booking_id': bookingId,
        'charge_id': billId,
        'tx_type': 'extra_charge_payment',
        'direction': 'debit',
        'amount': amount,
        'payment_method': 'Wallet',
        'reference_no': referenceNo,
        'remark': remark,
      });
    } catch (_) {}
  }

  Future<Map<String, dynamic>> _payBookingExtraChargeWithWalletFallback({
    required String userId,
    required String billId,
  }) async {
    final chargeRow = await _supabase
        .from('booking_extra_charge')
        .select('charge_id,user_id,booking_id,amount,charge_status,title,remark,notes,description')
        .eq('charge_id', billId)
        .maybeSingle();

    if (chargeRow == null) {
      return {
        'success': false,
        'message': 'Billing record not found.',
      };
    }

    final chargeUserId = (chargeRow['user_id'] ?? '').toString().trim();
    final effectiveUserId = chargeUserId.isNotEmpty ? chargeUserId : userId;
    if (effectiveUserId.isEmpty) {
      return {
        'success': false,
        'message': 'Billing user is missing.',
      };
    }

    final rawStatus = (chargeRow['charge_status'] ?? '').toString().trim().toLowerCase();
    if (rawStatus == 'paid') {
      return {
        'success': true,
        'message': 'Billing has already been paid.',
      };
    }

    final amount = _moneyValue(chargeRow['amount']);
    if (amount <= 0) {
      return {
        'success': false,
        'message': 'Billing amount is invalid.',
      };
    }

    final walletSnapshot = await _getWalletSnapshot(effectiveUserId);
    final hasAnyWallet = walletSnapshot['user_wallets'] != null || walletSnapshot['user_wallet'] != null;
    if (!hasAnyWallet) {
      return {
        'success': false,
        'message': 'Wallet account not found.',
      };
    }

    final currentBalance = _resolvedWalletBalance(walletSnapshot);
    if (currentBalance < amount) {
      return {
        'success': false,
        'message': 'Wallet balance is not enough.',
      };
    }

    final paidAt = DateTime.now().toUtc().toIso8601String();
    final referenceNo = 'WB${(DateTime.now().millisecondsSinceEpoch % 1000000000).toString().padLeft(9, '0')}';
    final newBalance = currentBalance - amount;

    final walletUpdated = await _tryWalletBalanceUpdate(
      userId: effectiveUserId,
      snapshot: walletSnapshot,
      newBalance: newBalance,
    );
    if (!walletUpdated) {
      return {
        'success': false,
        'message': 'Wallet payment failed because the wallet balance could not be updated.',
      };
    }

    try {
      await _supabase.from('booking_extra_charge').update({
        'charge_status': 'paid',
        'paid_at': paidAt,
        'payment_method': 'wallet',
        'payment_reference': referenceNo,
        'paid_by_user_id': effectiveUserId,
      }).eq('charge_id', billId);
    } catch (e) {
      await _tryWalletBalanceUpdate(
        userId: effectiveUserId,
        snapshot: walletSnapshot,
        newBalance: currentBalance,
      );
      return {
        'success': false,
        'message': e.toString(),
      };
    }

    final title = (chargeRow['title'] ?? '').toString().trim();
    final note = (chargeRow['remark'] ?? chargeRow['notes'] ?? chargeRow['description'] ?? '')
        .toString()
        .trim();
    final bookingId = (chargeRow['booking_id'] ?? '').toString().trim();
    final remarkParts = <String>[
      title.isNotEmpty ? title : 'Billing payment',
      if (bookingId.isNotEmpty) 'Booking $bookingId',
      if (note.isNotEmpty) note,
    ];

    await _logWalletBillPayment(
      userId: effectiveUserId,
      billId: billId,
      bookingId: bookingId,
      amount: amount,
      referenceNo: referenceNo,
      remark: remarkParts.join(' • '),
    );

    return {
      'success': true,
      'message': 'Billing paid successfully.',
      'reference_no': referenceNo,
      'amount': amount,
    };
  }
}
