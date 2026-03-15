import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../main.dart';
import 'vendor_dashboard_page.dart';

class VendorShell extends StatelessWidget {
  const VendorShell({super.key, this.vendorId});

  final String? vendorId;

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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vendor Home'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Logout',
            onPressed: () => _logout(context),
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body: VendorDashboardPage(vendorId: vendorId),
    );
  }
}
