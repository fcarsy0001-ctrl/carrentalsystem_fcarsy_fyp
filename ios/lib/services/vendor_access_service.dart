import 'package:supabase_flutter/supabase_flutter.dart';

enum VendorState {
  none,
  pending,
  approved,
  rejected,
  inactive,
  unknown,
}

class VendorContext {
  const VendorContext({
    required this.state,
    this.vendorId,
    this.remark,
  });

  final VendorState state;
  final String? vendorId;
  final String? remark;

  bool get isVendor => state != VendorState.none;
}

class VendorAccessService {
  VendorAccessService(this._client);

  final SupabaseClient _client;

  Future<VendorContext> getVendorContext() async {
    final user = _client.auth.currentUser;
    if (user == null) return const VendorContext(state: VendorState.none);

    final email = (user.email ?? '').trim().toLowerCase();
    String role = '';
    String userStatus = 'Active';
    String userId = '';

    try {
      final row = await _client
          .from('app_user')
          .select('user_id,user_role,user_status')
          .eq('auth_uid', user.id)
          .limit(1)
          .maybeSingle();
      if (row != null) {
        userId = (row['user_id'] ?? '').toString().trim();
        role = (row['user_role'] ?? '').toString().trim();
        userStatus = (row['user_status'] ?? 'Active').toString().trim();
      }
    } catch (_) {}

    if (userId.isEmpty && email.isNotEmpty) {
      try {
        final row = await _client
            .from('app_user')
            .select('user_id,user_role,user_status')
            .eq('user_email', email)
            .limit(1)
            .maybeSingle();
        if (row != null) {
          userId = (row['user_id'] ?? '').toString().trim();
          role = (row['user_role'] ?? '').toString().trim();
          userStatus = (row['user_status'] ?? 'Active').toString().trim();
        }
      } catch (_) {}
    }

    final roleIsVendor = role.toLowerCase() == 'vendor';
    Map<String, dynamic>? vendorRow;

    if (userId.isNotEmpty) {
      try {
        final row = await _client
            .from('vendor')
            .select('*')
            .eq('user_id', userId)
            .order('vendor_id', ascending: false)
            .limit(1)
            .maybeSingle();
        if (row != null) {
          vendorRow = Map<String, dynamic>.from(row as Map);
        }
      } catch (_) {}
    }

    if (vendorRow == null) {
      try {
        final row = await _client
            .from('vendor')
            .select('*')
            .eq('auth_uid', user.id)
            .order('vendor_id', ascending: false)
            .limit(1)
            .maybeSingle();
        if (row != null) {
          vendorRow = Map<String, dynamic>.from(row as Map);
        }
      } catch (_) {}
    }

    if (vendorRow == null && email.isNotEmpty) {
      try {
        final row = await _client
            .from('vendor')
            .select('*')
            .eq('vendor_email', email)
            .order('vendor_id', ascending: false)
            .limit(1)
            .maybeSingle();
        if (row != null) {
          vendorRow = Map<String, dynamic>.from(row as Map);
        }
      } catch (_) {}
    }

    if (vendorRow == null) {
      if (roleIsVendor) {
        return const VendorContext(state: VendorState.pending);
      }
      return const VendorContext(state: VendorState.none);
    }

    final rawStatus = (vendorRow['vendor_status'] ?? userStatus).toString();
    return VendorContext(
      state: _parse(rawStatus),
      vendorId: (vendorRow['vendor_id'] ?? '').toString().trim(),
      remark: (vendorRow['vendor_reject_remark'] ?? '').toString().trim(),
    );
  }

  VendorState _parse(String raw) {
    final value = raw.trim().toLowerCase();
    if (value.isEmpty) return VendorState.pending;
    if (value == 'pending' || value == 'under review' || value == 'in review') {
      return VendorState.pending;
    }
    if (value == 'active' || value == 'approved') return VendorState.approved;
    if (value == 'rejected' || value == 'declined') return VendorState.rejected;
    if (value == 'inactive' || value == 'disabled' || value.contains('inactive')) {
      return VendorState.inactive;
    }
    return VendorState.unknown;
  }
}
