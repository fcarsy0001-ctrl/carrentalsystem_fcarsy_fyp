import 'package:supabase_flutter/supabase_flutter.dart';

/// Admin types supported by the app.
///
/// - superAdmin: row exists in `public.admin` with status Active
/// - staffAdmin: row exists in `public.staff_admin` with status Active
enum AdminKind {
  none,
  /// Admin exists in `public.admin` but is NOT a SuperAdmin.
  admin,
  superAdmin,
  staffAdmin,
}

class AdminContext {
  const AdminContext(this.kind);

  final AdminKind kind;

  bool get isAdmin => kind != AdminKind.none;
  bool get isSuperAdmin => kind == AdminKind.superAdmin;
  bool get isStaffAdmin => kind == AdminKind.staffAdmin;
  bool get isNormalAdmin => kind == AdminKind.admin;
}

/// Lightweight admin detection.
///
/// We avoid `maybeSingle()` because duplicate rows can cause it to throw.
/// We always `limit(1)` and treat non-empty lists as existence.
class AdminAccessService {
  AdminAccessService(this._client);

  final SupabaseClient _client;

  /// Hard-coded super admin email fallback.
  ///
  /// This keeps your project working even if `admin.admin_role` was inserted
  /// incorrectly in Supabase.
  static const String _superAdminEmail = 'admin@gmail.com';

  String _normRole(String s) {
    // Normalize role strings like: "SuperAdmin", "Super Admin", "super_admin"
    return s.trim().toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
  }

  Future<AdminContext> getAdminContext() async {
    final user = _client.auth.currentUser;
    if (user == null) return const AdminContext(AdminKind.none);

    final email = (user.email ?? '').trim().toLowerCase();

    // 1) Super admin: in public.admin
    try {
      final rows = await _client
          .from('admin')
          .select('admin_id,admin_role,admin_email')
          .eq('auth_uid', user.id)
          .eq('admin_status', 'Active')
          .limit(1);
      if (rows is List && rows.isNotEmpty) {
        final r = rows.first is Map ? (rows.first as Map) : const <String, dynamic>{};
        final role = _normRole((r['admin_role'] ?? '').toString());
        final adminEmail = (r['admin_email'] ?? '').toString().trim().toLowerCase();

        final isSuper = role == 'superadmin' || adminEmail == _superAdminEmail || email == _superAdminEmail;
        return AdminContext(isSuper ? AdminKind.superAdmin : AdminKind.admin);
      }
    } catch (_) {
      // ignore; could be RLS or table missing
    }

    // 1b) Fallback: some projects insert `public.admin` without `auth_uid`.
    // Match by email to avoid locking yourself out of admin features.
    if (email.isNotEmpty) {
      try {
        final rows = await _client
            .from('admin')
            .select('admin_id,admin_role,admin_email,auth_uid')
            .eq('admin_email', email)
            .eq('admin_status', 'Active')
            .limit(1);
        if (rows is List && rows.isNotEmpty) {
          final r = rows.first is Map ? (rows.first as Map) : const <String, dynamic>{};
          final role = _normRole((r['admin_role'] ?? '').toString());
          final adminEmail = (r['admin_email'] ?? '').toString().trim().toLowerCase();
          final isSuper = role == 'superadmin' || adminEmail == _superAdminEmail || email == _superAdminEmail;

          // Best-effort link auth_uid once (optional; may fail if RLS denies update)
          final existingUid = (r['auth_uid'] ?? '').toString().trim();
          if (existingUid.isEmpty) {
            try {
              await _client.from('admin').update({'auth_uid': user.id}).eq('admin_email', email);
            } catch (_) {}
          }

          return AdminContext(isSuper ? AdminKind.superAdmin : AdminKind.admin);
        }
      } catch (_) {
        // ignore
      }
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
