import 'dart:math';
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LeaserApplicationService {
  LeaserApplicationService(this._client);

  final SupabaseClient _client;

  static const String bucketId = 'leaser_ssm';

  Future<String> generateLeaserId() async {
    // IMPORTANT:
    // Many projects block normal users from SELECT on "leaser" due to RLS.
    // If SELECT is blocked, the old logic always returned LEA-00001, which causes
    // "duplicate key violates leaser_pkey" during registration.

    // 1) Prefer a DB-side RPC if you created it (recommended): generate_leaser_id()
    try {
      final data = await _client.rpc('generate_leaser_id');
      if (data != null) {
        final id = data.toString();
        // Many schemas define leaser_id as varchar(10) (e.g., "LEA-00001").
        // If the RPC returns a longer id, ignore it to avoid 22001 errors.
        if (id.startsWith('LEA-') && id.length > 4 && id.length <= 10) return id;
      }
    } catch (_) {
      // ignore
    }

    // 2) Best-effort sequential id from last visible row (works if RLS allows SELECT)
    try {
      final row = await _client
          .from('leaser')
          .select('leaser_id')
          .order('leaser_id', ascending: false)
          .limit(1)
          .maybeSingle();

      final last = (row?['leaser_id'] ?? '').toString();
      final m = RegExp(r'^LEA-(\d+)$').firstMatch(last);
      if (m != null) {
        final n = int.tryParse(m.group(1) ?? '') ?? 0;
        final next = n + 1;
        // Keep at least 5 digits for readability, but don't truncate large numbers.
        final digits = next.toString();
        return 'LEA-${digits.length < 5 ? digits.padLeft(5, '0') : digits}';
      }
    } catch (_) {
      // ignore
    }

    // 3) Fallback: generate a short id that fits common varchar(10) schema.
    // Format: LEA-00000 (9 chars). We add randomness; caller already retries on 23505.
    final base = DateTime.now().microsecondsSinceEpoch % 100000;
    final mix = (base + Random().nextInt(100000)) % 100000;
    return 'LEA-${mix.toString().padLeft(5, '0')}';
  }

  Future<String?> uploadSsmPhoto({required String authUid, required XFile file}) async {
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) return null;
    final ext = _safeExt(file.name);
    final contentType = ext == 'png' ? 'image/png' : 'image/jpeg';
    final path = '$authUid/ssm_${DateTime.now().millisecondsSinceEpoch}.$ext';
    await _client.storage.from(bucketId).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: contentType, upsert: true),
        );
    return path;
  }

  Future<String?> createSignedSsmUrl(String path) async {
    if (path.trim().isEmpty) return null;
    try {
      return await _client.storage.from(bucketId).createSignedUrl(path, 60 * 60);
    } catch (_) {
      return null;
    }
  }

  /// Returns existing leaser row (if any) for a given user_id.
  Future<Map<String, dynamic>?> getByUserId(String userId) async {
    try {
      final row = await _client
          .from('leaser')
          .select('*')
          .eq('user_id', userId)
          .order('leaser_id', ascending: false)
          .limit(1)
          .maybeSingle();
      if (row != null) {
        return Map<String, dynamic>.from(row as Map);
      }
    } catch (_) {
      // ignore
    }
    return null;
  }

  String _safeExt(String name) {
    final parts = name.split('.');
    if (parts.length < 2) return 'jpg';
    final ext = parts.last.toLowerCase();
    if (ext == 'png') return 'png';
    if (ext == 'jpg' || ext == 'jpeg') return 'jpg';
    return 'jpg';
  }
}
