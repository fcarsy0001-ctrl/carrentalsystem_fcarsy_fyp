import 'package:supabase_flutter/supabase_flutter.dart';

/// Admin types supported by the app.
///
/// - superAdmin: row exists in `public.admin` with status Active
/// - staffAdmin: row exists in `public.staff_admin` with status Active
enum AdminKind {
  none,
  superAdmin,
  staffAdmin,
}

class AdminContext {
  const AdminContext(this.kind);

  final AdminKind kind;

  bool get isAdmin => kind != AdminKind.none;
  bool get isSuperAdmin => kind == AdminKind.superAdmin;
  bool get isStaffAdmin => kind == AdminKind.staffAdmin;
}

/// Lightweight admin detection.
///
/// We avoid `maybeSingle()` because duplicate rows can cause it to throw.
/// We always `limit(1)` and treat non-empty lists as existence.
class AdminAccessService {
  AdminAccessService(this._client);

  final SupabaseClient _client;

  Future<AdminContext> getAdminContext() async {
    final user = _client.auth.currentUser;
    if (user == null) return const AdminContext(AdminKind.none);

    // 1) Super admin: in public.admin
    try {
      final rows = await _client
          .from('admin')
          .select('admin_id,admin_role')
          .eq('auth_uid', user.id)
          .eq('admin_status', 'Active')
          .limit(1);
      if (rows is List && rows.isNotEmpty) {
        return const AdminContext(AdminKind.superAdmin);
      }
    } catch (_) {
      // ignore; could be RLS or table missing
    }

    // 2) Staff admin: in public.staff_admin
    try {
      final rows = await _client
          .from('staff_admin')
          .select('sadmin_id')
          .eq('auth_uid', user.id)
          .eq('sadmin_status', 'Active')
          .limit(1);
      if (rows is List && rows.isNotEmpty) {
        return const AdminContext(AdminKind.staffAdmin);
      }
    } catch (_) {
      // ignore
    }

    return const AdminContext(AdminKind.none);
  }
}
