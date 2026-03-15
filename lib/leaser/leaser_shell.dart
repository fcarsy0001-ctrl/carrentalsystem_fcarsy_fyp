import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../admin/service_job_orders_page.dart';
import '../admin/vehicle_location_dashboard_page.dart';
import '../admin/vehicle_onboarding_page.dart';
import '../main.dart';
import 'leaser_dashboard_page.dart';
import 'vehicle_onboarding_status_page.dart';

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
      const Tab(icon: Icon(Icons.place_outlined), text: 'Locations'),
      const Tab(icon: Icon(Icons.build_circle_outlined), text: 'Service Jobs'),
      const Tab(icon: Icon(Icons.track_changes_outlined), text: 'Status'),
    ];

    final views = <Widget>[
      LeaserDashboardPage(leaserId: leaserId),
      VehicleOnboardingPage(
        leaserId: leaserId,
        title: 'My Vehicles',
        embedded: true,
      ),
      VehicleLocationDashboardPage(
        leaserId: leaserId,
        title: 'Vehicle Locations',
        embedded: true,
        allowManageLocations: false,
      ),
      ServiceJobOrdersPage(
        leaserId: leaserId,
        embedded: true,
        title: 'Service Jobs',
        subtitle: 'Create and track maintenance or inspection requests for your vehicles.',
        allowVendorReassign: true,
        allowCancelledStatus: false,
      ),
      VehicleOnboardingStatusPage(
        leaserId: leaserId,
        embedded: true,
      ),
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
