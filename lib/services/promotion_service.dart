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

  Future<List<Map<String, dynamic>>> fetchActiveAnnouncements() async {
    final now = DateTime.now().toIso8601String();
    final rows = await supa
        .from('announcement')
        .select()
        .eq('active', true)
        .or('start_at.is.null,start_at.lte.$now')
        .or('end_at.is.null,end_at.gte.$now')
        .order('created_at', ascending: false);

    return (rows as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  bool _isPromotionVisibleToUser({
    required Map<String, dynamic> promo,
    required String userId,
  }) {
    final targetUserId = (promo['target_user_id'] ?? '').toString().trim();
    if (targetUserId.isNotEmpty) {
      return userId.isNotEmpty && targetUserId == userId;
    }

    final sendScope = (promo['send_scope'] ?? '').toString().trim().toLowerCase();
    if (sendScope == 'specific' || sendScope == 'user' || sendScope == 'single') {
      return false;
    }

    final sendToAll = promo['send_to_all'];
    if (sendToAll == null) return true;
    if (sendToAll is bool) return sendToAll;
    return sendToAll.toString().toLowerCase() != 'false';
  }

  Future<List<Map<String, dynamic>>> fetchActivePromotions() async {
    final now = DateTime.now().toIso8601String();
    final rows = await supa
        .from('promotion')
        .select()
        .eq('active', true)
        .or('start_at.is.null,start_at.lte.$now')
        .or('end_at.is.null,end_at.gte.$now')
        .order('created_at', ascending: false);

    final list = (rows as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    final urow = await getAppUserRow();
    final userId = (urow?['user_id'] ?? '').toString().trim();
    return list.where((p) => _isPromotionVisibleToUser(promo: p, userId: userId)).toList();
  }

  Future<List<Map<String, dynamic>>> fetchMyVouchers() async {
    final urow = await getAppUserRow();
    final userId = (urow?['user_id'] ?? '').toString();
    if (userId.isEmpty) return [];

    final rows = await supa
        .from('user_voucher')
        .select('promo_id, claimed_at, used_booking_id, used_at, promotion(*)')
        .eq('user_id', userId)
        .order('claimed_at', ascending: false);
    return (rows as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<Set<String>> fetchClaimedPromoIds() async {
    final rows = await fetchMyVouchers();
    return rows
        .map((e) => (e['promo_id'] ?? '').toString().trim())
        .where((e) => e.isNotEmpty)
        .toSet();
  }

  Future<Map<String, dynamic>?> getPromotionByCode(String code) async {
    final row = await supa
        .from('promotion')
        .select()
        .eq('code', code)
        .maybeSingle();
    if (row == null) return null;

    final promo = Map<String, dynamic>.from(row as Map);
    final urow = await getAppUserRow();
    final userId = (urow?['user_id'] ?? '').toString().trim();
    if (!_isPromotionVisibleToUser(promo: promo, userId: userId)) {
      return null;
    }
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

  Future<ClaimVoucherResult> claimVoucherWithStatus({required String promoId}) async {
    final urow = await getAppUserRow();
    final userId = (urow?['user_id'] ?? '').toString().trim();
    if (userId.isEmpty) throw Exception('User profile not found');

    final existing = await supa
        .from('user_voucher')
        .select('user_id, promo_id')
        .eq('user_id', userId)
        .eq('promo_id', promoId)
        .maybeSingle();
    if (existing != null) {
      return const ClaimVoucherResult(alreadyClaimed: true, claimedNow: false);
    }

    await _ensureRedeemLimitNotReached(promoId: promoId);

    try {
      await supa.from('user_voucher').insert({
        'user_id': userId,
        'promo_id': promoId,
        'claimed_at': DateTime.now().toIso8601String(),
      });
      return const ClaimVoucherResult(alreadyClaimed: false, claimedNow: true);
    } catch (e) {
      final recheck = await supa
          .from('user_voucher')
          .select('user_id, promo_id')
          .eq('user_id', userId)
          .eq('promo_id', promoId)
          .maybeSingle();
      if (recheck != null) {
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
    final userId = (urow?['user_id'] ?? '').toString();
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