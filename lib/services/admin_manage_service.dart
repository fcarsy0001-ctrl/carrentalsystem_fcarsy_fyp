import 'package:supabase_flutter/supabase_flutter.dart';

class AdminManageService {
  AdminManageService(this._client);

  final SupabaseClient _client;

  Future<List<Map<String, dynamic>>> listAdmins({int limit = 100}) async {
    final rows = await _client
        .from('admin')
        .select('admin_id,auth_uid,admin_role,admin_status')
        .order('admin_id')
        .limit(limit);

    return (rows as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<String> nextAdminId() async {
    try {
      final row = await _client
          .from('admin')
          .select('admin_id')
          .order('admin_id', ascending: false)
          .limit(1)
          .maybeSingle();

      final last = (row?['admin_id'] as String?) ?? '';
      final m = RegExp(r'^A(\d+)$').firstMatch(last);
      if (m != null) {
        final n = int.tryParse(m.group(1)!) ?? 0;
        final next = n + 1;
        return 'A${next.toString().padLeft(3, '0')}';
      }
      return 'A001';
    } catch (_) {
      return 'A001';
    }
  }

  Future<void> createAdmin({
    required String adminId,
    required String authUid,
    required String role,
    required String status,
  }) async {
    await _client.from('admin').insert({
      'admin_id': adminId,
      'auth_uid': authUid,
      'admin_role': role,
      'admin_status': status,
      // user_id is intentionally omitted (admin is decoupled from app_user)
    });
  }
}
