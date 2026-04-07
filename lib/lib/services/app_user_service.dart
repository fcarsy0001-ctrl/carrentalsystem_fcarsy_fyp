import 'package:supabase_flutter/supabase_flutter.dart';

/// Ensures a corresponding row exists in the `app_user` table for the
/// currently authenticated Supabase Auth user (including Google OAuth users).
///
/// This prevents "Google login works but app_user is empty" problems.
class AppUserService {
  AppUserService(this._client);

  final SupabaseClient _client;

  /// Create `app_user` if missing.
  Future<void> ensureAppUser() async {
    final user = _client.auth.currentUser;
    if (user == null) return;

    // 1) Check existing
    final existing = await _client
        .from('app_user')
        .select('user_id')
        .eq('auth_uid', user.id)
        .maybeSingle();

    if (existing != null) return;

    // 2) Build placeholders (your schema has many NOT NULL columns)
    final meta = user.userMetadata ?? const <String, dynamic>{};
    final email = user.email ?? (meta['email'] as String?) ?? '';

    String name =
        (meta['full_name'] as String?) ?? (meta['name'] as String?) ?? '';
    if (name.trim().isEmpty) {
      name = email.isNotEmpty ? email.split('@').first : 'User';
    }

    final base = <String, dynamic>{
      'auth_uid': user.id,
      'user_name': name,
      'user_email': email,
      // Keep consistent with your existing register placeholders
      'user_password': '***',
      'user_phone': '0000000000',
      'user_icno': '000000000000',
      'user_gender': 'Male',
      'user_role': 'User',
      'user_status': 'Active',
      'email_verified': true,
    };

    // 3) Insert with retry (in case of user_id collision)
    const maxRetries = 5;
    var attempt = 0;
    while (attempt < maxRetries) {
      attempt++;
      final userId = await _generateUserId();

      // Try inserting with driver-licence columns (if you've migrated)
      final withDl = <String, dynamic>{
        'user_id': userId,
        ...base,
        'driver_license_status': 'Not Submitted',
      };

      try {
        await _client.from('app_user').insert(withDl);
        return;
      } catch (_) {
        // If DL columns aren't migrated yet, retry with base columns only.
        try {
          await _client.from('app_user').insert({'user_id': userId, ...base});
          return;
        } catch (e) {
          if (attempt >= maxRetries) rethrow;
        }
      }
    }
  }

  /// Generates a new user_id like U001, U002 ...
  Future<String> _generateUserId() async {
    try {
      final row = await _client
          .from('app_user')
          .select('user_id')
          .order('user_id', ascending: false)
          .limit(1)
          .maybeSingle();

      final lastId = (row?['user_id'] as String?) ?? '';
      if (lastId.startsWith('U') && lastId.length >= 4) {
        final numPart = lastId.substring(1);
        final lastNum = int.tryParse(numPart) ?? 0;
        final next = lastNum + 1;
        return 'U${next.toString().padLeft(3, '0')}';
      }

      return 'U001';
    } catch (_) {
      // Fallback: timestamp-based
      final ts = DateTime.now().millisecondsSinceEpoch;
      return 'U${ts.toString().substring(ts.toString().length - 6)}';
    }
  }
}
