import 'package:supabase_flutter/supabase_flutter.dart';

/// Leaser vehicle operations.
///
/// NOTE:
/// Many Supabase projects enable RLS on `vehicle` and do NOT grant INSERT/UPDATE/DELETE
/// to leaser accounts. In that case, client-side writes fail with 42501 / RLS Forbidden.
///
/// This app supports server-side writes via Supabase Edge Functions.
/// If your function is deployed using a different naming convention (underscore vs dash),
/// we try both.
///
/// Required deployed functions (one of these names must exist):
/// - leaser_upsert_vehicle  OR  leaser-upsert-vehicle
/// - leaser_delete_vehicle  OR  leaser-delete-vehicle
class LeaserVehicleService {
  LeaserVehicleService(this._client);

  final SupabaseClient _client;

  Future<String> _requireToken() async {
    final token = _client.auth.currentSession?.accessToken;
    if (token == null || token.isEmpty) {
      throw Exception('Session expired. Please login again.');
    }
    return token;
  }

  /// Invoke an Edge Function with fallback names.
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
            // Some platforms do not forward Authorization automatically.
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

    // All names returned 404.
    final tried = names.join(', ');
    throw Exception(
      'Requested function was not found. Tried: $tried.\n'
      'Fix: deploy the Edge Function in Supabase Dashboard/CLI (supabase/functions/...).',
    );
  }

  Future<void> upsertVehicle({
    required bool isEdit,
    required String vehicleId,
    required Map<String, dynamic> payload,
  }) async {
    final token = await _requireToken();

    final res = await _invokeWithFallback(
      names: const ['leaser_upsert_vehicle', 'leaser-upsert-vehicle'],
      token: token,
      body: {
        'is_edit': isEdit,
        'vehicle_id': vehicleId,
        'payload': payload,
      },
    );

    if (res.status >= 400) {
      throw Exception('leaser_upsert_vehicle HTTP ${res.status}: ${res.data}');
    }
    if (res.data is Map) {
      final m = Map<String, dynamic>.from(res.data as Map);
      if (m['ok'] == false) {
        throw Exception(m['error'] ?? 'leaser_upsert_vehicle failed');
      }
    }
  }

  Future<void> deleteVehicle({required String vehicleId}) async {
    final token = await _requireToken();

    final res = await _invokeWithFallback(
      names: const ['leaser_delete_vehicle', 'leaser-delete-vehicle'],
      token: token,
      body: {'vehicle_id': vehicleId},
    );

    if (res.status >= 400) {
      throw Exception('leaser_delete_vehicle HTTP ${res.status}: ${res.data}');
    }
    if (res.data is Map) {
      final m = Map<String, dynamic>.from(res.data as Map);
      if (m['ok'] == false) {
        throw Exception(m['error'] ?? 'leaser_delete_vehicle failed');
      }
    }
  }
}
