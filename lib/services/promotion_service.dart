import 'package:supabase_flutter/supabase_flutter.dart';

/// Promotion/Voucher + Announcement service.
///
/// Tables expected (recommended):
/// - promotion(promo_id, code, title, description, discount_type, discount_value,
///            min_spend, max_discount, start_at, end_at, active, created_at)
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

  /// Returns active announcements ordered newest-first.
  Future<List<Map<String, dynamic>>> fetchActiveAnnouncements() async {
    final now = DateTime.now().toIso8601String();
    final rows = await supa
        .from('announcement')
        .select()
        .eq('active', true)
        // start_at <= now OR start_at is null
        .or('start_at.is.null,start_at.lte.$now')
        // end_at >= now OR end_at is null
        .or('end_at.is.null,end_at.gte.$now')
        .order('created_at', ascending: false);

    return (rows as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  /// Returns active promotions ordered newest-first.
  Future<List<Map<String, dynamic>>> fetchActivePromotions() async {
    final now = DateTime.now().toIso8601String();
    final rows = await supa
        .from('promotion')
        .select()
        .eq('active', true)
        .or('start_at.is.null,start_at.lte.$now')
        .or('end_at.is.null,end_at.gte.$now')
        .order('created_at', ascending: false);
    return (rows as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  /// Returns claimed vouchers for current user.
  Future<List<Map<String, dynamic>>> fetchMyVouchers() async {
    final urow = await getAppUserRow();
    final userId = (urow?['user_id'] ?? '').toString();
    if (userId.isEmpty) return [];

    // Join promotion fields.
    final rows = await supa
        .from('user_voucher')
        .select('promo_id, claimed_at, used_booking_id, used_at, promotion(*)')
        .eq('user_id', userId)
        .order('claimed_at', ascending: false);
    return (rows as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<Map<String, dynamic>?> getPromotionByCode(String code) async {
    final row = await supa
        .from('promotion')
        .select()
        .eq('code', code)
        .maybeSingle();
    if (row == null) return null;
    return Map<String, dynamic>.from(row as Map);
  }

  /// Claim voucher for current user. Safe if already claimed.
  Future<void> claimVoucher({required String promoId}) async {
  final urow = await getAppUserRow();
  final userId = (urow?['user_id'] ?? '').toString();
  if (userId.isEmpty) throw Exception('User profile not found');

  // Enforce optional global redemption cap (max_redeems).
  // Note: For strict enforcement, implement this check in DB (RPC/trigger). This client-side check is best-effort.
  try {
    final promo = await supa.from('promotion').select().eq('promo_id', promoId).maybeSingle();
    final maxAny = promo == null ? null : (promo as Map)['max_redeems'];
    final maxRedeems = (maxAny is num)
        ? maxAny.toInt()
        : int.tryParse((maxAny ?? '').toString().trim());

    if (maxRedeems != null && maxRedeems > 0) {
      // Count total claimed records for this promo.
      final claimed = await supa.from('user_voucher').select('user_id').eq('promo_id', promoId);
      final claimedCount = (claimed is List) ? claimed.length : 0;
      if (claimedCount >= maxRedeems) {
        throw Exception('This voucher has reached its maximum redemption limit.');
      }
    }
  } catch (e) {
    // If the promo table doesn't have max_redeems, or counting fails, we continue.
    // (Admin UI will warn if the column is missing.)
    final msg = e.toString();
    if (msg.contains('maximum redemption limit')) rethrow;
  }

  // Upsert-like behaviour: try insert, ignore duplicate.
  try {
    await supa.from('user_voucher').insert({
      'user_id': userId,
      'promo_id': promoId,
      'claimed_at': DateTime.now().toIso8601String(),
    });
  } catch (_) {
    // ignore (already claimed)
  }
}

/// Mark a voucher as used for booking.
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

  /// Compute discount for a voucher.
  ///
  /// We apply discount to rental subtotal only (not insurance), to keep logic clear.
  /// Returns discountAmount.
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
