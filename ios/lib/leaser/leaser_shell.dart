import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../admin/vehicle_admin_page.dart';
import '../main.dart';

/// Leaser "Admin Home" - restricted view.
///
/// Requirement:
/// - Leaser only sees Vehicle module
/// - Vehicle list is filtered to their own leaser_id
class LeaserShell extends StatelessWidget {
  const LeaserShell({super.key, required this.leaserId});

  final String leaserId;

  SupabaseClient get _supa => Supabase.instance.client;

  Future<void> _logout(BuildContext context) async {
    try {
      await _supa.auth.signOut();
    } catch (_) {}
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthWrapper()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return VehicleAdminPage(
      leaserId: leaserId,
      title: 'Admin Home',
      actions: [
        IconButton(
          tooltip: 'Logout',
          onPressed: () => _logout(context),
          icon: const Icon(Icons.logout_rounded),
        ),
      ],
    );
  }
}
