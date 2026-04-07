import 'package:supabase_flutter/supabase_flutter.dart';

/// Promotion/Voucher + Announcement service.
///
/// Tables expected (recommended):
/// - promotion(promo_id, code, title, description, discount_type, discount_value,
///            min_spend, max_discount, start_at, end_at, active, created_at,
///            send_scope, send_to_all, target_user_id, max_redeems)
/// - user_voucher(user_id, promo_id, claimed_at, used_booking_id, used_at)
/// - announcement(ann_id, title, message, promo_code, start_at, end_at, active, created_at)
class PromotionService {
  final SupabaseClient supa;
  const PromotionService(this.supa);

  Future<Map<String, dynamic>?> getAppUserRow() async {
    final u = supa.auth.currentUser;
    if (u == null) return null;
    final row = await supa
        .from('app_user')
        .select('user_id, user_email, user_name')
        .eq('auth_uid', u.id)
        .maybeSingle();
    if (row == null) return null;
    return Map<String, dynamic>.from(row as Map);
  }

  String _s(dynamic value) => value == null ? '' : value.toString().trim();

  String _normCode(String value) => value.trim().toUpperCase();

  DateTime? _toDateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value.isUtc ? value.toLocal() : value;
    final raw = value.toString().trim();
    if (raw.isEmpty) return null;
    try {
      final parsed = DateTime.parse(raw);
      return parsed.isUtc ? parsed.toLocal() : parsed;
    } catch (_) {
      return null;
    }
  }

  bool _isActiveFlag(dynamic value) {
    if (value == null) return true;
    if (value is bool) return value;
    return value.toString().trim().toLowerCase() == 'true';
  }

  DateTime _startOfDay(DateTime value) => DateTime(value.year, value.month, value.day);

  DateTime _endOfDay(DateTime value) => DateTime(value.year, value.month, value.day, 23, 59, 59, 999);

  bool _isWithinActiveWindow(Map<String, dynamic> row, {DateTime? now}) {
    final current = now ?? DateTime.now();
    final start = _toDateTime(row['start_at']);
    final end = _toDateTime(row['end_at']);
    if (start != null && current.isBefore(_startOfDay(start))) return false;
    if (end != null && current.isAfter(_endOfDay(end))) return false;
    return true;
  }

  bool _isPromotionActive(Map<String, dynamic> promo, {DateTime? now}) {
    if (!_isActiveFlag(promo['active'])) return false;
    return _isWithinActiveWindow(promo, now: now);
  }

  bool _isAnnouncementActive(Map<String, dynamic> announcement, {DateTime? now}) {
    if (!_isActiveFlag(announcement['active'])) return false;
    return _isWithinActiveWindow(announcement, now: now);
  }

  Future<List<Map<String, dynamic>>> fetchActiveAnnouncements() async {
    final rows = await supa
        .from('announcement')
        .select()
        .eq('active', true)
        .order('created_at', ascending: false);

    return (rows as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .where((row) => _isAnnouncementActive(row))
        .toList();
  }

  bool _isPromotionVisibleToUser({
    required Map<String, dynamic> promo,
    required String userId,
  }) {
    final targetUserId = _s(promo['target_user_id']);
    if (targetUserId.isNotEmpty) {
      return userId.isNotEmpty && targetUserId == userId;
    }

    final sendScope = _s(promo['send_scope']).toLowerCase();
    if (sendScope == 'specific' || sendScope == 'user' || sendScope == 'single') {
      return false;
    }

    final sendToAll = promo['send_to_all'];
    if (sendToAll == null) return true;
    if (sendToAll is bool) return sendToAll;
    return sendToAll.toString().toLowerCase() != 'false';
  }

  Future<List<Map<String, dynamic>>> fetchActivePromotions() async {
    final rows = await supa
        .from('promotion')
        .select()
        .eq('active', true)
        .order('created_at', ascending: false);

    final list = (rows as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .where((row) => _isPromotionActive(row))
        .toList();

    final urow = await getAppUserRow();
    final userId = _s(urow?['user_id']);
    return list.where((p) => _isPromotionVisibleToUser(promo: p, userId: userId)).toList();
  }

  Map<String, dynamic>? _promotionFromUserVoucherRow(Map<String, dynamic> row) {
    final raw = row['promotion'];
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is List && raw.isNotEmpty && raw.first is Map) {
      return Map<String, dynamic>.from(raw.first as Map);
    }
    return null;
  }

  bool _isVoucherConsumed(Map<String, dynamic> row) {
    final usedBookingId = _s(row['used_booking_id']);
    final usedAt = _s(row['used_at']);
    return usedBookingId.isNotEmpty || usedAt.isNotEmpty;
  }

  Future<List<Map<String, dynamic>>> fetchMyVouchers() async {
    final urow = await getAppUserRow();
    final userId = _s(urow?['user_id']);
    if (userId.isEmpty) return [];

    final rows = await supa
        .from('user_voucher')
        .select('promo_id, claimed_at, used_booking_id, used_at, promotion(*)')
        .eq('user_id', userId)
        .order('claimed_at', ascending: false);

    final mapped = (rows as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    final missingPromoIds = mapped
        .where((row) {
          final promo = _promotionFromUserVoucherRow(row);
          return promo == null || promo.isEmpty;
        })
        .map((row) => _s(row['promo_id']))
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    if (missingPromoIds.isNotEmpty) {
      try {
        final promoRows = await supa
            .from('promotion')
            .select()
            .inFilter('promo_id', missingPromoIds);
        final promoById = <String, Map<String, dynamic>>{};
        for (final raw in (promoRows as List)) {
          final promo = Map<String, dynamic>.from(raw as Map);
          final promoId = _s(promo['promo_id']);
          if (promoId.isNotEmpty) {
            promoById[promoId] = promo;
          }
        }
        for (final row in mapped) {
          final promo = _promotionFromUserVoucherRow(row);
          if (promo != null && promo.isNotEmpty) continue;
          final promoId = _s(row['promo_id']);
          if (promoId.isNotEmpty && promoById.containsKey(promoId)) {
            row['promotion'] = promoById[promoId];
          }
        }
      } catch (_) {}
    }

    final usedBookingIds = mapped
        .map((row) => _s(row['used_booking_id']))
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    if (usedBookingIds.isNotEmpty) {
      final bookingStatusById = <String, String>{};
      final paidBookingIds = <String>{};

      for (final bookingId in usedBookingIds) {
        try {
          final booking = await supa
              .from('booking')
              .select('booking_status')
              .eq('booking_id', bookingId)
              .maybeSingle();
          final bookingMap = booking == null ? null : Map<String, dynamic>.from(booking as Map);
          bookingStatusById[bookingId] = _s(bookingMap?['booking_status']).toLowerCase();
        } catch (_) {}

        try {
          final payments = await supa
              .from('payment')
              .select('payment_status')
              .eq('booking_id', bookingId);
          if (payments is List && payments.any((row) => _s((row as Map)['payment_status']).toLowerCase() == 'paid')) {
            paidBookingIds.add(bookingId);
          }
        } catch (_) {}
      }

      for (final row in mapped) {
        final bookingId = _s(row['used_booking_id']);
        if (bookingId.isEmpty) continue;
        final status = bookingStatusById[bookingId] ?? '';
        final shouldRelease = !paidBookingIds.contains(bookingId) &&
            (status.isEmpty ||
                status == 'holding' ||
                status == 'cancel' ||
                status == 'cancelled' ||
                status == 'canceled' ||
                status == 'deactive' ||
                status == 'failed');
        if (!shouldRelease) continue;

        row['used_booking_id'] = null;
        row['used_at'] = null;
        try {
          await supa
              .from('user_voucher')
              .update({'used_booking_id': null, 'used_at': null})
              .eq('user_id', userId)
              .eq('promo_id', _s(row['promo_id']));
        } catch (_) {}
      }
    }

    return mapped;
  }

  Future<Set<String>> fetchClaimedPromoIds() async {
    final rows = await fetchMyVouchers();
    return rows
        .map((e) => _s(e['promo_id']))
        .where((e) => e.isNotEmpty)
        .toSet();
  }


  Future<List<Map<String, dynamic>>> fetchAvailableMyVouchers() async {
    final rows = await fetchMyVouchers();
    return rows.where((row) {
      if (_isVoucherConsumed(row)) return false;
      final promo = _promotionFromUserVoucherRow(row);
      return promo != null && promo.isNotEmpty && _isPromotionActive(promo);
    }).map((row) => Map<String, dynamic>.from(row)).toList();
  }

  Future<Map<String, dynamic>?> getPromotionById(String promoId) async {
    final cleanPromoId = _s(promoId);
    if (cleanPromoId.isEmpty) return null;
    final row = await supa
        .from('promotion')
        .select()
        .eq('promo_id', cleanPromoId)
        .maybeSingle();
    if (row == null) return null;
    return Map<String, dynamic>.from(row as Map);
  }

  Future<Map<String, dynamic>?> _findPromotionByCodeCaseInsensitive(String code) async {
    final clean = _s(code);
    if (clean.isEmpty) return null;

    try {
      final rows = await supa
          .from('promotion')
          .select()
          .ilike('code', clean);
      for (final raw in (rows as List)) {
        final promo = Map<String, dynamic>.from(raw as Map);
        if (_normCode(_s(promo['code'])) == _normCode(clean)) {
          return promo;
        }
      }
    } catch (_) {}

    try {
      final promos = await fetchActivePromotions();
      for (final promo in promos) {
        if (_normCode(_s(promo['code'])) == _normCode(clean)) {
          return promo;
        }
      }
    } catch (_) {}

    return null;
  }

  Future<Map<String, dynamic>?> getPromotionByCode(String code) async {
    final clean = _s(code);
    if (clean.isEmpty) return null;

    final urow = await getAppUserRow();
    final userId = _s(urow?['user_id']);

    Map<String, dynamic>? promo;
    try {
      final row = await supa
          .from('promotion')
          .select()
          .eq('code', clean)
          .maybeSingle();
      if (row != null) {
        promo = Map<String, dynamic>.from(row as Map);
      }
    } catch (_) {}

    promo ??= await _findPromotionByCodeCaseInsensitive(clean);
    if (promo == null) return null;
    if (!_isPromotionVisibleToUser(promo: promo, userId: userId)) return null;
    if (!_isPromotionActive(promo)) return null;
    return promo;
  }

  Future<void> _ensureRedeemLimitNotReached({required String promoId}) async {
    try {
      final promo = await supa.from('promotion').select().eq('promo_id', promoId).maybeSingle();
      final maxAny = promo == null ? null : (promo as Map)['max_redeems'];
      final maxRedeems = (maxAny is num)
          ? maxAny.toInt()
          : int.tryParse((maxAny ?? '').toString().trim());

      if (maxRedeems != null && maxRedeems > 0) {
        final claimed = await supa.from('user_voucher').select('user_id').eq('promo_id', promoId);
        final claimedCount = (claimed is List) ? claimed.length : 0;
        if (claimedCount >= maxRedeems) {
          throw Exception('This voucher has reached its maximum redemption limit.');
        }
      }
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('maximum redemption limit')) rethrow;
    }
  }

  Future<void> claimVoucher({required String promoId}) async {
    await claimVoucherWithStatus(promoId: promoId);
  }

  Future<ClaimVoucherResult> claimVoucherByCodeWithStatus({required String code}) async {
    final promo = await getPromotionByCode(code);
    if (promo == null) {
      throw Exception('Voucher not found or already expired.');
    }
    final promoId = _s(promo['promo_id']);
    if (promoId.isEmpty) {
      throw Exception('Voucher is missing promo id.');
    }
    return claimVoucherWithStatus(promoId: promoId);
  }

  Future<ClaimVoucherResult> claimVoucherWithStatus({required String promoId}) async {
    final cleanPromoId = _s(promoId);
    if (cleanPromoId.isEmpty) throw Exception('Missing promo id');

    final urow = await getAppUserRow();
    final userId = _s(urow?['user_id']);
    if (userId.isEmpty) throw Exception('User profile not found');

    final promo = await getPromotionById(cleanPromoId);
    if (promo == null) throw Exception('Voucher not found.');
    if (!_isPromotionVisibleToUser(promo: promo, userId: userId) || !_isPromotionActive(promo)) {
      throw Exception('Voucher not found or already expired.');
    }

    final existing = await supa
        .from('user_voucher')
        .select('user_id, promo_id, used_booking_id, used_at')
        .eq('user_id', userId)
        .eq('promo_id', cleanPromoId)
        .maybeSingle();
    if (existing != null) {
      final existingRow = Map<String, dynamic>.from(existing as Map);
      if (_isVoucherConsumed(existingRow)) {
        throw Exception('This voucher has already been used.');
      }
      return const ClaimVoucherResult(alreadyClaimed: true, claimedNow: false);
    }

    await _ensureRedeemLimitNotReached(promoId: cleanPromoId);

    try {
      await supa.from('user_voucher').insert({
        'user_id': userId,
        'promo_id': cleanPromoId,
        'claimed_at': DateTime.now().toIso8601String(),
      });
      return const ClaimVoucherResult(alreadyClaimed: false, claimedNow: true);
    } catch (e) {
      final recheck = await supa
          .from('user_voucher')
          .select('user_id, promo_id, used_booking_id, used_at')
          .eq('user_id', userId)
          .eq('promo_id', cleanPromoId)
          .maybeSingle();
      if (recheck != null) {
        final recheckRow = Map<String, dynamic>.from(recheck as Map);
        if (_isVoucherConsumed(recheckRow)) {
          throw Exception('This voucher has already been used.');
        }
        return const ClaimVoucherResult(alreadyClaimed: true, claimedNow: false);
      }
      rethrow;
    }
  }

  Future<void> markVoucherUsed({
    required String promoId,
    required String bookingId,
  }) async {
    final urow = await getAppUserRow();
    final userId = _s(urow?['user_id']);
    if (userId.isEmpty) return;
    try {
      await supa
          .from('user_voucher')
          .update({
        'used_booking_id': bookingId,
        'used_at': DateTime.now().toIso8601String(),
      })
          .eq('user_id', userId)
          .eq('promo_id', promoId);
    } catch (_) {}
  }

  double computeDiscount({
    required Map<String, dynamic> promo,
    required double rentalSubtotal,
  }) {
    final type = (promo['discount_type'] ?? 'amount').toString().toLowerCase();
    final valueNum = promo['discount_value'];
    final value = (valueNum is num)
        ? valueNum.toDouble()
        : double.tryParse((valueNum ?? '0').toString()) ?? 0.0;

    final minSpendNum = promo['min_spend'];
    final minSpend = (minSpendNum is num)
        ? minSpendNum.toDouble()
        : double.tryParse((minSpendNum ?? '0').toString()) ?? 0.0;
    if (rentalSubtotal < minSpend) return 0.0;

    double discount = 0.0;
    if (type == 'percent' || type == 'percentage') {
      discount = rentalSubtotal * (value / 100.0);
    } else {
      discount = value;
    }

    final maxNum = promo['max_discount'];
    if (maxNum != null) {
      final maxD = (maxNum is num)
          ? maxNum.toDouble()
          : double.tryParse(maxNum.toString());
      if (maxD != null && maxD > 0) discount = discount > maxD ? maxD : discount;
    }

    if (discount < 0) discount = 0;
    if (discount > rentalSubtotal) discount = rentalSubtotal;
    return discount;
  }
}

class ClaimVoucherResult {
  final bool alreadyClaimed;
  final bool claimedNow;

  const ClaimVoucherResult({
    required this.alreadyClaimed,
    required this.claimedNow,
  });
}
