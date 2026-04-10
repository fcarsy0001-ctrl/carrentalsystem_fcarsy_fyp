import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';

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


  bool _isJwtValidationIssue(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('invalid jwt') ||
        message.contains('missing authorization header') ||
        message.contains('functionexception(status: 401') ||
        message.contains('status: 401');
  }

  bool _isDuplicateKey(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('duplicate key') || message.contains('23505');
  }

  Future<String> _generateUserId() async {
    try {
      final row = await _client
          .from('app_user')
          .select('user_id')
          .order('user_id', ascending: false)
          .limit(1)
          .maybeSingle();
      final lastId = (row?['user_id'] ?? '').toString().trim();
      final match = RegExp(r'^U(\d+)$').firstMatch(lastId);
      if (match != null) {
        final next = (int.tryParse(match.group(1) ?? '') ?? 0) + 1;
        final digits = next.toString();
        return 'U${digits.length < 3 ? digits.padLeft(3, '0') : digits}';
      }
    } catch (_) {
      // ignore and fall back below
    }
    final ts = DateTime.now().millisecondsSinceEpoch.toString();
    return 'U${ts.substring(ts.length - 6)}';
  }

  Future<Map<String, dynamic>> _createUserDirect({
    required String name,
    required String email,
    required String password,
    required String phone,
    required String icNo,
    required String gender,
    required String role,
    required String status,
    required bool emailVerified,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();

    try {
      final existing = await _client
          .from('app_user')
          .select('user_id')
          .eq('user_email', normalizedEmail)
          .limit(1)
          .maybeSingle();
      if (existing != null) {
        final existingId = (existing['user_id'] ?? '').toString().trim();
        throw Exception(
          existingId.isEmpty
              ? 'This email already exists in app_user.'
              : 'This email already exists in app_user: $existingId',
        );
      }
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('already exists in app_user')) rethrow;
    }

    final temp = SupabaseClient(
      SupabaseConfig.supabaseUrl,
      SupabaseConfig.supabaseAnonKey,
      authOptions: AuthClientOptions(
        authFlowType: AuthFlowType.pkce,
        pkceAsyncStorage: SharedPreferencesGotrueAsyncStorage(),
      ),
    );

    AuthResponse auth;
    try {
      auth = await temp.auth.signUp(email: normalizedEmail, password: password);
    } on AuthException catch (e) {
      final msg = e.message.toLowerCase();
      if (msg.contains('already registered') || msg.contains('user already') || msg.contains('exists')) {
        throw Exception('This email is already registered in Supabase Auth.');
      }
      rethrow;
    } finally {
      try {
        await temp.auth.signOut();
      } catch (_) {}
    }

    final authUid = auth.user?.id?.trim() ?? '';
    if (authUid.isEmpty) {
      throw Exception('Sign up succeeded but no auth uid was returned.');
    }

    for (var attempt = 0; attempt < 8; attempt++) {
      final userId = await _generateUserId();
      final payload = <String, dynamic>{
        'user_id': userId,
        'auth_uid': authUid,
        'user_name': name.trim(),
        'user_email': normalizedEmail,
        'user_password': '***',
        'user_phone': phone.trim(),
        'user_icno': icNo.trim(),
        'user_gender': gender,
        'user_role': role,
        'user_status': status,
        'email_verified': emailVerified,
        'driver_license_status': 'Not Submitted',
      };

      try {
        await _client.from('app_user').insert(payload);
        return {
          'ok': true,
          'user_id': userId,
          'auth_uid': authUid,
          'fallback': true,
        };
      } catch (e) {
        if (_isDuplicateKey(e)) {
          await Future<void>.delayed(Duration(milliseconds: 120 * (attempt + 1)));
          continue;
        }
        final message = e.toString().toLowerCase();
        if (message.contains('driver_license_status')) {
          final fallbackPayload = Map<String, dynamic>.from(payload)..remove('driver_license_status');
          await _client.from('app_user').insert(fallbackPayload);
          return {
            'ok': true,
            'user_id': userId,
            'auth_uid': authUid,
            'fallback': true,
          };
        }
        rethrow;
      }
    }

    throw Exception('Failed to create app_user after multiple retries.');
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
    final normalizedEmail = email.trim().toLowerCase();
    final token = await _requireToken();

    try {
      final res = await _invokeWithFallback(
        names: const ['create_app_user', 'create-app-user'],
        token: token,
        body: {
          'user_name': name.trim(),
          'user_email': normalizedEmail,
          'user_password': password,
          'user_phone': phone.trim(),
          'user_icno': icNo.trim(),
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
    } catch (e) {
      if (!_isJwtValidationIssue(e)) rethrow;
      return _createUserDirect(
        name: name,
        email: normalizedEmail,
        password: password,
        phone: phone,
        icNo: icNo,
        gender: gender,
        role: role,
        status: status,
        emailVerified: emailVerified,
      );
    }
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
