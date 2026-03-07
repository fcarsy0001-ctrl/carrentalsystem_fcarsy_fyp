import 'package:supabase_flutter/supabase_flutter.dart';

/// Admin/Staff User Management service.
///
/// IMPORTANT:
/// Creating/deleting Supabase Auth users requires a server-side action.
/// This module uses Supabase Edge Functions.
///
/// If your function is deployed using a different naming convention
/// (underscore vs dash), we try both.
///
/// Required deployed functions (one of these names must exist):
/// - create_app_user   OR  create-app-user
/// - update_app_user   OR  update-app-user
/// - delete_app_user   OR  delete-app-user
class AdminUserService {
  AdminUserService(this._client);

  final SupabaseClient _client;

  Future<String> _requireToken() async {
    final token = _client.auth.currentSession?.accessToken;
    if (token == null || token.isEmpty) {
      throw Exception('Session expired. Please login again.');
    }
    return token;
  }

  Future<FunctionResponse> _invokeWithFallback({
    required List<String> names,
    required Map<String, dynamic> body,
    required String token,
  }) async {
    FunctionException? last404;
    Object? lastOther;

    for (final name in names) {
      try {
        return await _client.functions.invoke(
          name,
          headers: {
            'Authorization': 'Bearer $token',
            'x-user-jwt': token,
          },
          body: body,
        );
      } on FunctionException catch (e) {
        if (e.status == 404 || (e.details ?? '').toString().contains('NOT_FOUND')) {
          last404 = e;
          continue;
        }
        lastOther = e;
        break;
      } catch (e) {
        lastOther = e;
        break;
      }
    }

    if (lastOther != null) {
      throw Exception(lastOther.toString());
    }

    final tried = names.join(', ');
    throw Exception(
      'Requested function was not found. Tried: $tried.\n'
      'Fix: deploy the Edge Function in Supabase Dashboard/CLI (supabase/functions/...).',
    );
  }

  Future<Map<String, dynamic>> createUser({
    required String name,
    required String email,
    required String password,
    required String phone,
    required String icNo,
    required String gender,
    String role = 'User',
    String status = 'Active',
    bool emailVerified = true,
  }) async {
    final token = await _requireToken();
    final res = await _invokeWithFallback(
      names: const ['create_app_user', 'create-app-user'],
      token: token,
      body: {
        'user_name': name,
        'user_email': email,
        'user_password': password,
        'user_phone': phone,
        'user_icno': icNo,
        'user_gender': gender,
        'user_role': role,
        'user_status': status,
        'email_verified': emailVerified,
      },
    );

    if (res.data is Map) {
      return Map<String, dynamic>.from(res.data as Map);
    }
    return {'ok': true, 'data': res.data};
  }

  Future<Map<String, dynamic>> updateUser({
    required String userId,
    required String authUid,
    required Map<String, dynamic> payload,
  }) async {
    final token = await _requireToken();

    final res = await _invokeWithFallback(
      names: const ['update_app_user', 'update-app-user'],
      token: token,
      body: {
        'user_id': userId,
        'auth_uid': authUid,
        'payload': payload,
      },
    );

    if (res.status >= 400) {
      throw Exception('update_app_user HTTP ${res.status}: ${res.data}');
    }
    if (res.data is Map) {
      final m = Map<String, dynamic>.from(res.data as Map);
      if (m['ok'] == false) {
        throw Exception('update_app_user failed: ${m['error'] ?? m}');
      }
      if (m['user'] is Map) return Map<String, dynamic>.from(m['user'] as Map);
    }
    return {'ok': true, 'data': res.data};
  }

  Future<void> deleteUser({
    required String userId,
    required String authUid,
    bool force = true,
  }) async {
    final token = await _requireToken();

    final res = await _invokeWithFallback(
      names: const ['delete_app_user', 'delete-app-user'],
      token: token,
      body: {
        'user_id': userId,
        'auth_uid': authUid,
        'force': force,
      },
    );

    // IMPORTANT: Edge Function may return {ok:false,...} even when invoke succeeds.
    if (res.status >= 400) {
      throw Exception('delete_app_user HTTP ${res.status}: ${res.data}');
    }
    if (res.data is Map) {
      final m = Map<String, dynamic>.from(res.data as Map);
      if (m['ok'] == false) {
        throw Exception('delete_app_user failed: ${m['error'] ?? m}');
      }
    }
  }
}
