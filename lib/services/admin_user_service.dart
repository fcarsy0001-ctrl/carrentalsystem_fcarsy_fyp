import 'dart:convert';

import 'package:http/http.dart' as http;
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

  String _s(dynamic v) => v == null ? '' : v.toString().trim();

  Future<String> _requireToken() async {
    try {
      final refreshed = await _client.auth.refreshSession();
      final freshToken = refreshed.session?.accessToken;
      if (freshToken != null && freshToken.isNotEmpty) {
        return freshToken;
      }
    } catch (_) {
      // Ignore refresh failure and fall back to current session.
    }

    final token = _client.auth.currentSession?.accessToken;
    if (token == null || token.isEmpty) {
      throw Exception('Session expired. Please login again.');
    }
    return token;
  }

  bool _isFunctionMissing(Object error) {
    if (error is FunctionException && error.status == 404) return true;
    final lower = error.toString().toLowerCase();
    return lower.contains('not_found') ||
        lower.contains('not found') ||
        lower.contains('requested function was not found') ||
        lower.contains('does not exist');
  }

  bool _isJwtIssue(Object error) {
    if (error is FunctionException && error.status == 401) return true;
    final lower = error.toString().toLowerCase();
    return lower.contains('invalid jwt') ||
        lower.contains('unauthorized') ||
        lower.contains('status: 401');
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

  Future<Map<String, dynamic>> _invokeHttpWithFallback({
    required List<String> names,
    required Map<String, dynamic> body,
    required String token,
  }) async {
    Object? lastError;

    for (final name in names) {
      try {
        final response = await http.post(
          Uri.parse('${SupabaseConfig.supabaseUrl}/functions/v1/$name'),
          headers: {
            'Authorization': 'Bearer $token',
            'x-user-jwt': token,
            'apikey': SupabaseConfig.supabaseAnonKey,
            'Content-Type': 'application/json',
          },
          body: jsonEncode(body),
        );
        final text = response.body;
        if (response.statusCode == 404) {
          lastError = Exception('Function $name not found.');
          continue;
        }

        dynamic data;
        if (text.isNotEmpty) {
          try {
            data = jsonDecode(text);
          } catch (_) {
            data = text;
          }
        }

        if (response.statusCode >= 400) {
          throw Exception('$name HTTP ${response.statusCode}: ${data ?? text}');
        }

        if (data is Map) {
          final map = Map<String, dynamic>.from(data);
          if (map['ok'] == false) {
            throw Exception('$name failed: ${map['error'] ?? map}');
          }
          return map;
        }

        return {'ok': true, 'data': data};
      } catch (e) {
        lastError = e;
        final lower = e.toString().toLowerCase();
        if (lower.contains('404')) {
          continue;
        }
        break;
      }
    }

    if (lastError != null) {
      throw Exception(lastError.toString());
    }

    final tried = names.join(', ');
    throw Exception(
      'Requested function was not found. Tried: $tried.\n'
      'Fix: deploy the Edge Function in Supabase Dashboard/CLI (supabase/functions/...).',
    );
  }
  void _throwIfBadResponse(String name, FunctionResponse res) {
    if (res.status >= 400) {
      throw Exception('$name HTTP ${res.status}: ${res.data}');
    }
    if (res.data is Map) {
      final map = Map<String, dynamic>.from(res.data as Map);
      if (map['ok'] == false) {
        throw Exception('$name failed: ${map['error'] ?? map}');
      }
    }
  }

  Map<String, dynamic> _extractCreatedUserPayload(Map<String, dynamic> data) {
    if (data['user'] is Map) {
      return Map<String, dynamic>.from(data['user'] as Map);
    }
    return data;
  }

  Future<String> _generateUserId() async {
    try {
      final response = await _client
          .from('app_user')
          .select('user_id')
          .order('user_id', ascending: false)
          .limit(1);

      if (response is! List || response.isEmpty) {
        return 'U001';
      }

      final lastUserId = _s((response.first as Map)['user_id']);
      if (!lastUserId.startsWith('U') || lastUserId.length < 2) {
        return 'U001';
      }

      final lastNumber = int.tryParse(lastUserId.substring(1));
      if (lastNumber == null) {
        return 'U001';
      }

      final nextNumber = lastNumber + 1;
      if (nextNumber > 999999) {
        final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
        return 'U${timestamp.substring(timestamp.length - 6)}';
      }
      return 'U${nextNumber.toString().padLeft(3, '0')}';
    } catch (_) {
      final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      return 'U${timestamp.substring(timestamp.length - 6)}';
    }
  }

  Future<String> _createAuthUserViaHttp({
    required String email,
    required String password,
  }) async {
    final response = await http.post(
      Uri.parse('${SupabaseConfig.supabaseUrl}/auth/v1/signup'),
      headers: {
        'apikey': SupabaseConfig.supabaseAnonKey,
        'Authorization': 'Bearer ${SupabaseConfig.supabaseAnonKey}',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'email': email.trim().toLowerCase(),
        'password': password,
      }),
    );
    final text = response.body;
    dynamic data;
    if (text.isNotEmpty) {
      try {
        data = jsonDecode(text);
      } catch (_) {
        data = text;
      }
    }

    if (response.statusCode >= 400) {
      throw Exception('Auth signup HTTP ${response.statusCode}: ${data ?? text}');
    }
    if (data is! Map) {
      throw Exception('Auth signup failed: invalid response.');
    }
    final map = Map<String, dynamic>.from(data);
    final user = map['user'];
    if (user is Map && user['id'] != null) {
      return user['id'].toString();
    }
    throw Exception('Auth signup failed: user ID not returned.');
  }

  Future<Map<String, dynamic>> _insertAppUserDirect({
    SupabaseClient? client,
    required String authUid,
    required String name,
    required String email,
    required String phone,
    required String icNo,
    required String gender,
    required String role,
    required String status,
    required bool emailVerified,
  }) async {
    final insertClient = client ?? _client;
    int retries = 0;
    while (retries < 10) {
      final userId = await _generateUserId();
      final payload = <String, dynamic>{
        'user_id': userId,
        'auth_uid': authUid,
        'user_name': name,
        'user_email': email.trim().toLowerCase(),
        'user_password': '***',
        'user_phone': phone,
        'user_icno': icNo,
        'user_gender': gender,
        'user_role': role,
        'user_status': status,
        'email_verified': emailVerified,
        'driver_license_status': 'Not Submitted',
      };
      try {
        await insertClient.from('app_user').insert(payload);
        return payload;
      } catch (e) {
        final lower = e.toString().toLowerCase();
        if (lower.contains('duplicate key') || lower.contains('23505')) {
          retries += 1;
          continue;
        }
        rethrow;
      }
    }

    final compact = authUid.replaceAll('-', '').toUpperCase();
    final fallbackId = 'U${compact.length >= 8 ? compact.substring(0, 8) : compact.padRight(8, '0')}';
    final payload = <String, dynamic>{
      'user_id': fallbackId,
      'auth_uid': authUid,
      'user_name': name,
      'user_email': email.trim().toLowerCase(),
      'user_password': '***',
      'user_phone': phone,
      'user_icno': icNo,
      'user_gender': gender,
      'user_role': role,
      'user_status': status,
      'email_verified': emailVerified,
      'driver_license_status': 'Not Submitted',
    };
    await insertClient.from('app_user').insert(payload);
    return payload;
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
    final adminSession = _client.auth.currentSession;
    final adminSessionJson = adminSession == null ? null : jsonEncode(adminSession.toJson());
    final temp = SupabaseClient(
      SupabaseConfig.supabaseUrl,
      SupabaseConfig.supabaseAnonKey,
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: false,
        authFlowType: AuthFlowType.implicit,
        localStorage: EmptyLocalStorage(),
        detectSessionInUri: false,
      ),
    );
    try {
      AuthResponse? authResponse;
      try {
        authResponse = await temp.auth.signUp(
          email: email.trim().toLowerCase(),
          password: password,
        );
      } catch (e) {
        final lower = e.toString().toLowerCase();
        if (lower.contains('error sending confirmation email') ||
            lower.contains('unexpected_failure')) {
          final signIn = await temp.auth.signInWithPassword(
            email: email.trim().toLowerCase(),
            password: password,
          );
          authResponse = AuthResponse(user: signIn.user, session: signIn.session);
        } else {
          rethrow;
        }
      }

      var authUid = authResponse?.user?.id ?? '';
      if (authUid.isEmpty) {
        final signIn = await temp.auth.signInWithPassword(
          email: email.trim().toLowerCase(),
          password: password,
        );
        authUid = signIn.user?.id ?? '';
      }

      if (authUid.isEmpty) {
        throw Exception('Auth signup failed: user ID not returned.');
      }

      return _insertAppUserDirect(
        client: temp,
        authUid: authUid,
        name: name,
        email: email,
        phone: phone,
        icNo: icNo,
        gender: gender,
        role: role,
        status: status,
        emailVerified: emailVerified,
      );
    } finally {
      if (adminSessionJson != null) {
        try {
          await _client.auth.recoverSession(adminSessionJson);
        } catch (_) {}
      }
    }
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
    final body = {
      'user_name': name,
      'user_email': email,
      'user_password': password,
      'user_phone': phone,
      'user_icno': icNo,
      'user_gender': gender,
      'user_role': role,
      'user_status': status,
      'email_verified': emailVerified,
    };

    try {
      final res = await _invokeHttpWithFallback(
        names: const ['create_app_user', 'create-app-user'],
        token: token,
        body: body,
      );
      return _extractCreatedUserPayload(res);
    } catch (e) {
      if (!_isFunctionMissing(e) && !_isJwtIssue(e)) {
        rethrow;
      }
    }

    return _createUserDirect(
      name: name,
      email: email,
      password: password,
      phone: phone,
      icNo: icNo,
      gender: gender,
      role: role,
      status: status,
      emailVerified: emailVerified,
    );
  }

  Future<Map<String, dynamic>> _updateUserDirect({
    required String userId,
    required Map<String, dynamic> payload,
  }) async {
    final updated = await _client
        .from('app_user')
        .update(payload)
        .eq('user_id', userId)
        .select(
          'user_id,auth_uid,user_name,user_email,user_phone,user_icno,user_gender,user_role,user_status,email_verified,driver_license_status',
        )
        .maybeSingle();

    if (updated == null) {
      throw Exception('Update failed (no row updated).');
    }
    return Map<String, dynamic>.from(updated as Map);
  }

  Future<Map<String, dynamic>> updateUser({
    required String userId,
    required String authUid,
    required Map<String, dynamic> payload,
  }) async {
    final cleanAuthUid = authUid.trim();
    if (cleanAuthUid.isNotEmpty) {
      try {
        final token = await _requireToken();
        final res = await _invokeWithFallback(
          names: const ['update_app_user', 'update-app-user'],
          token: token,
          body: {
            'user_id': userId,
            'auth_uid': cleanAuthUid,
            'payload': payload,
          },
        );

        _throwIfBadResponse('update_app_user', res);

        if (res.data is Map) {
          final map = Map<String, dynamic>.from(res.data as Map);
          if (map['user'] is Map) {
            return Map<String, dynamic>.from(map['user'] as Map);
          }
          return map;
        }
        return {'ok': true, 'data': res.data};
      } catch (e) {
        if (!_isFunctionMissing(e) && !_isJwtIssue(e)) {
          rethrow;
        }
      }
    }

    return _updateUserDirect(userId: userId, payload: payload);
  }

  Future<void> _safeDeleteByEq(String table, String column, String value) async {
    final cleanValue = value.trim();
    if (cleanValue.isEmpty) return;
    try {
      await _client.from(table).delete().eq(column, cleanValue);
    } catch (_) {
      // Best effort only.
    }
  }

  Future<List<String>> _collectBookingIds({
    required String userId,
    required String authUid,
  }) async {
    final ids = <String>{};

    try {
      final rows = await _client.from('booking').select('booking_id').eq('user_id', userId);
      for (final raw in rows) {
        final bookingId = _s((raw as Map)['booking_id']);
        if (bookingId.isNotEmpty) ids.add(bookingId);
      }
    } catch (_) {
      // ignore
    }

    if (authUid.trim().isNotEmpty) {
      try {
        final rows = await _client.from('booking').select('booking_id').eq('auth_uid', authUid.trim());
        for (final raw in rows) {
          final bookingId = _s((raw as Map)['booking_id']);
          if (bookingId.isNotEmpty) ids.add(bookingId);
        }
      } catch (_) {
        // ignore
      }
    }

    return ids.toList(growable: false);
  }

  Future<void> _bestEffortCleanupUserData({
    required String userId,
    required String authUid,
  }) async {
    String email = '';
    try {
      final row = await _client
          .from('app_user')
          .select('user_email')
          .eq('user_id', userId)
          .limit(1)
          .maybeSingle();
      email = _s(row?['user_email']).toLowerCase();
    } catch (_) {
      // ignore
    }

    final bookingIds = await _collectBookingIds(userId: userId, authUid: authUid);

    const bookingLinkedTables = [
      'receipt',
      'payment',
      'contract',
      'installment',
      'rental_history',
      'notification',
      'extra_charge',
    ];

    for (final bookingId in bookingIds) {
      for (final table in bookingLinkedTables) {
        await _safeDeleteByEq(table, 'booking_id', bookingId);
      }
      await _safeDeleteByEq('user_voucher', 'used_booking_id', bookingId);
    }

    const userLinkedTables = [
      'receipt',
      'payment',
      'contract',
      'booking',
      'installment',
      'rental_history',
      'user_voucher',
      'driver_licenses',
      'wallet_transaction',
      'wallet_topup',
      'notification',
      'extra_charge',
      'support_ticket',
    ];

    for (final table in userLinkedTables) {
      await _safeDeleteByEq(table, 'user_id', userId);
    }

    if (authUid.trim().isNotEmpty) {
      const authLinkedTables = [
        'receipt',
        'payment',
        'contract',
        'booking',
        'driver_licenses',
      ];
      for (final table in authLinkedTables) {
        await _safeDeleteByEq(table, 'auth_uid', authUid.trim());
      }
    }

    if (email.isNotEmpty) {
      await _safeDeleteByEq('verification_codes', 'user_email', email);
      await _safeDeleteByEq('verification_codes', 'email', email);
    }
  }

  Future<void> deleteUser({
    required String userId,
    required String authUid,
    bool force = true,
  }) async {
    if (force) {
      await _bestEffortCleanupUserData(userId: userId, authUid: authUid);
    }

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

    _throwIfBadResponse('delete_app_user', res);
  }
}


