import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../main.dart';
import 'driver_license_review_page.dart';
import 'leaser_review_page.dart';
import 'leaser_admin_module_page.dart';
import 'promotion_admin_page.dart';
import 'staff_admin_page.dart';
import 'vehicle_admin_page.dart';

class AdminShell extends StatefulWidget {
  const AdminShell({super.key, required this.isSuperAdmin});

  final bool isSuperAdmin;

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  SupabaseClient get _supa => Supabase.instance.client;

  Future<void> _logout() async {
    try {
      await _supa.auth.signOut();
    } catch (_) {}
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthWrapper()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final tabs = <Tab>[
      const Tab(icon: Icon(Icons.badge_outlined), text: 'Licences'),
      const Tab(icon: Icon(Icons.handshake_outlined), text: 'Leasers'),
      const Tab(icon: Icon(Icons.directions_car_outlined), text: 'Vehicles'),
      const Tab(icon: Icon(Icons.local_offer_outlined), text: 'Promotions'),
      if (widget.isSuperAdmin)
        const Tab(icon: Icon(Icons.supervisor_account_outlined), text: 'Staff'),
    ];

    final views = <Widget>[
      const DriverLicenseReviewPage(),
      const LeaserAdminModulePage(),
      const VehicleAdminPage(),
      const PromotionAdminPage(),
      if (widget.isSuperAdmin) const StaffAdminPage(),
    ];

    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Admin Home'),
          actions: [
            IconButton(
              tooltip: 'Logout',
              onPressed: _logout,
              icon: const Icon(Icons.logout_rounded),
            ),
          ],
          bottom: TabBar(tabs: tabs),
        ),
        body: TabBarView(children: views),
      ),
    );
  }
}
