import 'package:supabase_flutter/supabase_flutter.dart';

class OrderBillService {
  OrderBillService({SupabaseClient? client})
      : _supabase = client ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  Future<void> createBill({
    required String orderId,
    required String userId,
    required String billType,
    required String title,
    required double amount,
    String? description,
    String? photoUrl,
    String? issuedBy,
  }) async {
    await _supabase.from('order_bills').insert({
      'order_id': orderId,
      'user_id': userId,
      'bill_type': billType,
      'title': title,
      'description': description,
      'amount': amount,
      'photo_url': photoUrl,
      'issued_by': issuedBy,
      'status': 'Pending',
    });
  }

  Future<List<Map<String, dynamic>>> getBillsByOrder(String orderId) async {
    final rows = await _supabase
        .from('order_bills')
        .select()
        .eq('order_id', orderId)
        .order('issued_at', ascending: false);

    return List<Map<String, dynamic>>.from(rows);
  }

  Future<List<Map<String, dynamic>>> getPendingBillsByUser(String userId) async {
    final merged = <Map<String, dynamic>>[];

    try {
      final rows = await _supabase
          .from('booking_extra_charge')
          .select('*')
          .eq('user_id', userId)
          .or('charge_status.eq.pending,charge_status.eq.Pending,charge_status.eq.PENDING')
          .order('created_at', ascending: false);

      for (final row in List<Map<String, dynamic>>.from(rows)) {
        final chargeType = (row['charge_type'] ?? 'other').toString().trim();
        final title = (row['title'] ?? '').toString().trim();
        final remark = (row['remark'] ?? row['notes'] ?? row['description'] ?? '')
            .toString()
            .trim();
        merged.add({
          'source': 'booking_extra_charge',
          'id': (row['charge_id'] ?? '').toString().trim(),
          'order_id': (row['booking_id'] ?? '').toString().trim(),
          'title': title.isNotEmpty ? title : '${_labelize(chargeType)} bill',
          'bill_type': chargeType,
          'description': remark,
          'amount': ((row['amount'] ?? 0) as num).toDouble(),
          'status': row['charge_status'],
          'created_at': row['created_at'],
          'photo_url': row['photo_url'],
          'photo_path': row['photo_path'],
          'payment_method': row['payment_method'],
          'payment_reference': row['payment_reference'],
          'paid_at': row['paid_at'],
          'supports_wallet_payment': true,
        });
      }
    } catch (_) {}

    try {
      final rows = await _supabase
          .from('order_bills')
          .select()
          .eq('user_id', userId)
          .or('status.eq.pending,status.eq.Pending,status.eq.PENDING')
          .order('issued_at', ascending: false);

      for (final row in List<Map<String, dynamic>>.from(rows)) {
        final billType = (row['bill_type'] ?? 'other').toString().trim();
        final title = (row['title'] ?? '').toString().trim();
        merged.add({
          'source': 'order_bills',
          'id': (row['bill_id'] ?? '').toString().trim(),
          'order_id': (row['order_id'] ?? '').toString().trim(),
          'title': title.isNotEmpty ? title : '${_labelize(billType)} bill',
          'bill_type': billType,
          'description': (row['description'] ?? '').toString().trim(),
          'amount': ((row['amount'] ?? 0) as num).toDouble(),
          'status': row['status'],
          'created_at': row['issued_at'] ?? row['created_at'],
          'photo_url': row['photo_url'],
          'photo_path': row['photo_path'],
          'payment_method': row['payment_method'],
          'payment_reference': row['payment_reference'],
          'paid_at': row['paid_at'],
          'supports_wallet_payment': false,
        });
      }
    } catch (_) {}

    if (merged.isEmpty) return const [];

    final seen = <String>{};
    final unique = <Map<String, dynamic>>[];

    for (final row in merged) {
      final source = (row['source'] ?? '').toString().trim();
      final id = (row['id'] ?? '').toString().trim();
      final fallbackKey = [
        source,
        (row['order_id'] ?? '').toString().trim(),
        (row['title'] ?? '').toString().trim(),
        (row['amount'] ?? '').toString().trim(),
        (row['created_at'] ?? '').toString().trim(),
      ].join('|');
      final effectiveKey = id.isNotEmpty ? '$source|$id' : fallbackKey;
      if (seen.add(effectiveKey)) {
        unique.add(row);
      }
    }

    unique.sort((a, b) {
      final aTime = (a['created_at'] ?? '').toString();
      final bTime = (b['created_at'] ?? '').toString();
      return bTime.compareTo(aTime);
    });

    return unique;
  }

  Future<void> markBillPaidExternally({
    required Map<String, dynamic> bill,
    required String paymentMethod,
    String? referenceNo,
  }) async {
    final source = (bill['source'] ?? '').toString().trim();
    final id = (bill['id'] ?? '').toString().trim();
    if (id.isEmpty) throw Exception('Bill id not found.');

    final paidAt = DateTime.now().toUtc().toIso8601String();
    final cleanMethod = paymentMethod.trim().isEmpty ? 'Card' : paymentMethod.trim();
    final cleanReference = (referenceNo ?? '').trim();

    if (source == 'booking_extra_charge') {
      final payload = <String, dynamic>{
        'charge_status': 'paid',
        'paid_at': paidAt,
        'payment_method': cleanMethod.toLowerCase(),
        'payment_reference': cleanReference,
      };
      try {
        await _supabase.from('booking_extra_charge').update(payload).eq('charge_id', id);
      } on PostgrestException {
        await _supabase.from('booking_extra_charge').update({
          'charge_status': 'paid',
          'paid_at': paidAt,
        }).eq('charge_id', id);
      }
      return;
    }

    final payload = <String, dynamic>{
      'status': 'Paid',
      'payment_method': cleanMethod,
      'paid_at': paidAt,
      'payment_reference': cleanReference,
    };
    try {
      await _supabase.from('order_bills').update(payload).eq('bill_id', id);
    } on PostgrestException {
      await _supabase.from('order_bills').update({
        'status': 'Paid',
        'payment_method': cleanMethod,
        'paid_at': paidAt,
      }).eq('bill_id', id);
    }
  }

  Future<void> markBillPaidWithExternalMethod({
    required String billId,
    required String paymentMethod,
  }) async {
    await _supabase.from('order_bills').update({
      'status': 'Paid',
      'payment_method': paymentMethod,
      'paid_at': DateTime.now().toIso8601String(),
    }).eq('bill_id', billId);
  }


  Future<Map<String, dynamic>?> getBillBySourceAndId({
    required String source,
    required String billId,
  }) async {
    final cleanSource = source.trim();
    final cleanBillId = billId.trim();
    if (cleanSource.isEmpty || cleanBillId.isEmpty) return null;

    if (cleanSource == 'booking_extra_charge') {
      final row = await _supabase
          .from('booking_extra_charge')
          .select('*')
          .eq('charge_id', cleanBillId)
          .maybeSingle();
      if (row == null) return null;
      return Map<String, dynamic>.from(row as Map)
        ..['source'] = 'booking_extra_charge'
        ..['id'] = cleanBillId;
    }

    final row = await _supabase
        .from('order_bills')
        .select('*')
        .eq('bill_id', cleanBillId)
        .maybeSingle();
    if (row == null) return null;
    return Map<String, dynamic>.from(row as Map)
      ..['source'] = 'order_bills'
      ..['id'] = cleanBillId;
  }

  Future<void> cancelBill({
    required String source,
    required String billId,
    String? reason,
    String? cancelledBy,
  }) async {
    final cleanSource = source.trim();
    final cleanBillId = billId.trim();
    if (cleanSource.isEmpty || cleanBillId.isEmpty) {
      throw Exception('Bill id not found.');
    }

    final bill = await getBillBySourceAndId(source: cleanSource, billId: cleanBillId);
    if (bill == null) {
      throw Exception('Billing record not found.');
    }

    final currentStatus = cleanSource == 'booking_extra_charge'
        ? (bill['charge_status'] ?? '').toString().trim().toLowerCase()
        : (bill['status'] ?? '').toString().trim().toLowerCase();
    if (currentStatus == 'paid') {
      throw Exception('Paid billing cannot be cancelled.');
    }
    if (currentStatus == 'cancelled' || currentStatus == 'canceled' || currentStatus == 'waived') {
      return;
    }

    final now = DateTime.now().toUtc().toIso8601String();
    final cleanReason = (reason ?? '').trim();
    final cleanCancelledBy = (cancelledBy ?? '').trim();

    if (cleanSource == 'booking_extra_charge') {
      final payload = <String, dynamic>{
        'charge_status': 'cancelled',
        'updated_at': now,
      };
      if (cleanReason.isNotEmpty) payload['cancel_reason'] = cleanReason;
      if (cleanCancelledBy.isNotEmpty) payload['cancelled_by'] = cleanCancelledBy;
      try {
        await _supabase.from('booking_extra_charge').update(payload).eq('charge_id', cleanBillId);
      } on PostgrestException {
        await _supabase.from('booking_extra_charge').update({
          'charge_status': 'cancelled',
        }).eq('charge_id', cleanBillId);
      }
      return;
    }

    final payload = <String, dynamic>{
      'status': 'Cancelled',
    };
    if (cleanReason.isNotEmpty) payload['cancel_reason'] = cleanReason;
    if (cleanCancelledBy.isNotEmpty) payload['cancelled_by'] = cleanCancelledBy;
    try {
      await _supabase.from('order_bills').update(payload).eq('bill_id', cleanBillId);
    } on PostgrestException {
      await _supabase.from('order_bills').update({
        'status': 'Cancelled',
      }).eq('bill_id', cleanBillId);
    }
  }

  String _labelize(String value) {
    final normalized = value.trim().replaceAll('_', ' ');
    if (normalized.isEmpty) return 'Other';
    final lower = normalized.toLowerCase();
    if (lower == 'overtime' || lower == 'late return' || lower == 'late_return') {
      return 'Late return';
    }
    return lower
        .split(' ')
        .where((part) => part.isNotEmpty)
        .map((part) => part[0].toUpperCase() + part.substring(1))
        .join(' ');
  }
}
