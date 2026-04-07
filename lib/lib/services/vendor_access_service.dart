import 'package:supabase_flutter/supabase_flutter.dart';

enum VendorState {
  none,
  pending,
  rejected,
  active,
  inactive,
  blacklisted,
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
      if (!roleIsVendor) {
        return const VendorContext(state: VendorState.none);
      }
      final fallbackState = userStatus.toLowerCase() == 'active'
          ? VendorState.active
          : VendorState.inactive;
      return VendorContext(state: fallbackState);
    }

    final rawStatus = (vendorRow['vendor_status'] ?? userStatus).toString();
    final rawRemark = (vendorRow['vendor_reject_remark'] ?? '').toString().trim();
    return VendorContext(
      state: _parse(rawStatus),
      vendorId: (vendorRow['vendor_id'] ?? '').toString().trim(),
      remark: rawRemark.isEmpty ? null : rawRemark,
    );
  }

  VendorState _parse(String raw) {
    final value = raw.trim().toLowerCase();
    if (value.isEmpty) return VendorState.active;
    if (value == 'pending' || value.contains('pending')) return VendorState.pending;
    if (value == 'rejected' || value.contains('reject')) return VendorState.rejected;
    if (value == 'active' || value == 'approved') return VendorState.active;
    if (value == 'inactive' || value == 'disabled' || value.contains('inactive')) {
      return VendorState.inactive;
    }
    if (value == 'blacklisted' || value.contains('blacklist') || value == 'banned') {
      return VendorState.blacklisted;
    }
    return VendorState.unknown;
  }
}
