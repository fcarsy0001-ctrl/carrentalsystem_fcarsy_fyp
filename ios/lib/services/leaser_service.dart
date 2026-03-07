import 'package:supabase_flutter/supabase_flutter.dart';

class LeaserService {
  LeaserService(this._client);

  final SupabaseClient _client;

  Future<List<Map<String, dynamic>>> listLeasers({int limit = 50}) async {
    final rows = await _client
        .from('leaser')
        .select('leaser_id,user_id,leaser_company,leaser_status')
        .order('leaser_id')
        .limit(limit);

    return (rows as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }
}
