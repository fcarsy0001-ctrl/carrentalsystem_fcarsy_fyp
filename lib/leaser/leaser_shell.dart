
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../admin/vehicle_admin_page.dart';
import '../main.dart';
import 'leaser_dashboard_page.dart';

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
    final tabs = <Tab>[
      const Tab(icon: Icon(Icons.dashboard_outlined), text: 'Dashboard'),
      const Tab(icon: Icon(Icons.directions_car_outlined), text: 'Vehicles'),
    ];

    final views = <Widget>[
      LeaserDashboardPage(leaserId: leaserId),
      VehicleAdminPage(leaserId: leaserId, title: 'My Vehicles'),
    ];

    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Leaser Home'),
          centerTitle: true,
          actions: [
            IconButton(
              tooltip: 'Logout',
              onPressed: () => _logout(context),
              icon: const Icon(Icons.logout_rounded),
            ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: tabs,
          ),
        ),
        body: TabBarView(children: views),
      ),
    );
  }
}
