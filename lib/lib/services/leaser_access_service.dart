import 'package:supabase_flutter/supabase_flutter.dart';

enum LeaserState {
  none,
  pending,
  approved,
  rejected,
  disabled,
  unknown,
}

class LeaserContext {
  const LeaserContext({
    required this.state,
    this.leaserId,
    this.remark,
  });

  final LeaserState state;
  final String? leaserId;
  final String? remark;

  bool get isLeaser => state != LeaserState.none;
}

/// Detect whether the current authenticated user is a Leaser.
///
/// We purposely avoid selecting strict column lists that might not exist yet.
/// We try to locate the user's `user_id` from `app_user` (using auth_uid),
/// then check `leaser` by `user_id`.
class LeaserAccessService {
  LeaserAccessService(this._client);

  final SupabaseClient _client;

  Future<LeaserContext> getLeaserContext() async {
    final user = _client.auth.currentUser;
    if (user == null) return const LeaserContext(state: LeaserState.none);

    // Robust leaser detection to prevent leaser accounts from falling back
    // to User Home when admin has not approved yet.
    //
    // Priority:
    // 1) Map auth uid/email -> app_user.user_id (+ user_role)
    // 2) Find leaser row by user_id
    // 3) Fallback: find leaser row by email (if your leaser table has email column)
    // 4) If app_user role is Leaser but leaser row not readable, treat as Pending.

    final email = (user.email ?? '').trim().toLowerCase();
    String userId = '';
    String role = '';

    // app_user by auth_uid
    try {
      final u = await _client
          .from('app_user')
          .select('user_id,user_role')
          .eq('auth_uid', user.id)
          .limit(1)
          .maybeSingle();
      if (u != null) {
        userId = (u['user_id'] ?? '').toString().trim();
        role = (u['user_role'] ?? '').toString().trim();
      }
    } catch (_) {}

    // app_user fallback by email
    if (userId.isEmpty && email.isNotEmpty) {
      try {
        final u = await _client
            .from('app_user')
            .select('user_id,user_role')
            .eq('user_email', email)
            .limit(1)
            .maybeSingle();
        if (u != null) {
          userId = (u['user_id'] ?? '').toString().trim();
          role = (u['user_role'] ?? '').toString().trim();
        }
      } catch (_) {}
    }

    final roleIsLeaser = role.trim().toLowerCase() == 'leaser';

    Map<String, dynamic>? leaserRow;

    // leaser by user_id
    // IMPORTANT: there may be multiple historical leaser rows for the same user.
    // Always prefer the latest (highest leaser_id) to avoid showing an old "Rejected" again.
    if (userId.isNotEmpty) {
      try {
        final row = await _client
            .from('leaser')
            .select('*')
            .eq('user_id', userId)
            .order('leaser_id', ascending: false)
            .limit(1)
            .maybeSingle();
        if (row != null) {
          leaserRow = Map<String, dynamic>.from(row as Map);
        }
      } catch (_) {}
    }

    // leaser by email (only if the column exists; ignore if not)
    if (leaserRow == null && email.isNotEmpty) {
      try {
        final row = await _client
            .from('leaser')
            .select('*')
            .eq('email', email)
            .order('leaser_id', ascending: false)
            .limit(1)
            .maybeSingle();
        if (row != null) {
          leaserRow = Map<String, dynamic>.from(row as Map);
        }
      } catch (_) {}
    }

    if (leaserRow == null) {
      // If role indicates leaser, never fall back to user UI.
      if (roleIsLeaser) {
        return const LeaserContext(state: LeaserState.pending);
      }
      return const LeaserContext(state: LeaserState.none);
    }

    final raw = (leaserRow['leaser_status'] ?? leaserRow['status'] ?? '').toString();
    final st = _parse(raw);
    return LeaserContext(
      state: st,
      leaserId: (leaserRow['leaser_id'] ?? '').toString(),
      remark: (leaserRow['leaser_reject_remark'] ?? leaserRow['reject_remark'] ?? '').toString(),
    );
  }

  LeaserState _parse(String raw) {
    final v = raw.trim().toLowerCase();
    if (v.isEmpty) return LeaserState.pending;

    // Disabled / inactive
    if (v == 'inactive' ||
        v == 'deactive' ||
        v == 'deactivated' ||
        v == 'disabled' ||
        v.contains('inactive')) {
      return LeaserState.disabled;
    }

    // Pending / in review
    if (v == 'pending' || v == 'under review' || v == 'in review') {
      return LeaserState.pending;
    }

    // Approved / active
    if (v == 'approved' || v == 'active') return LeaserState.approved;

    // Rejected
    if (v == 'rejected' || v == 'declined') return LeaserState.rejected;

    return LeaserState.unknown;
  }
}
