import 'package:supabase_flutter/supabase_flutter.dart';

/// Admin access is determined by a row in `public.admin` matching the
/// current authenticated user's auth uid.
///
/// This allows admins to be provisioned directly in Supabase (Auth + insert into
/// `admin`) without needing a corresponding row in `app_user`.
class AdminAccountService {
  AdminAccountService(this._client);

  final SupabaseClient _client;

  Future<bool> isCurrentUserAdmin() async {
    final user = _client.auth.currentUser;
    if (user == null) return false;

    // Primary check: `admin.auth_uid = auth.uid()`.
    // IMPORTANT: We do NOT use maybeSingle() because duplicated rows (common
    // during migrations) would throw and incorrectly route an admin to user UI.
    try {
      final rows = await _client
          .from('admin')
          .select('admin_id')
          .eq('auth_uid', user.id)
          .eq('admin_status', 'Active')
          .limit(1);

      if (rows is List && rows.isNotEmpty) return true;
      if (rows is Map) return true;
    } catch (_) {
      // ignore and attempt fallback below
    }

    // Fallback (for older schemas):
    // If admin table still uses user_id (linked to app_user) and auth_uid
    // hasn't been added or populated, we try to map auth_uid -> app_user.user_id
    // then check admin.user_id.
    try {
      final uRow = await _client
          .from('app_user')
          .select('user_id')
          .eq('auth_uid', user.id)
          .limit(1)
          .maybeSingle();
      final userId = uRow?['user_id'] as String?;
      if (userId == null || userId.isEmpty) return false;

      final aRows = await _client
          .from('admin')
          .select('admin_id')
          .eq('user_id', userId)
          .eq('admin_status', 'Active')
          .limit(1);

      if (aRows is List && aRows.isNotEmpty) return true;
      if (aRows is Map) return true;
    } catch (_) {
      return false;
    }

    return false;
  }
}
