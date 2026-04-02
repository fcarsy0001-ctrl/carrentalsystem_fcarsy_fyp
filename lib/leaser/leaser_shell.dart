import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../admin/service_job_orders_page.dart';
import '../admin/vehicle_location_dashboard_page.dart';
import '../admin/vehicle_onboarding_page.dart';
import '../home/notifications_page.dart';
import '../main.dart';
import '../services/in_app_notification_service.dart';
import '../services/road_tax_monitor_service.dart';
import 'leaser_dashboard_page.dart';
import 'vehicle_onboarding_status_page.dart';

class LeaserShell extends StatefulWidget {
  const LeaserShell({super.key, required this.leaserId});

  final String leaserId;

  @override
  State<LeaserShell> createState() => _LeaserShellState();
}

class _LeaserShellState extends State<LeaserShell> {
  SupabaseClient get _supa => Supabase.instance.client;

  InAppNotificationService get _notificationSvc => InAppNotificationService(_supa);

  @override
  void initState() {
    super.initState();
    _runRoadTaxSync();
  }

  Future<void> _runRoadTaxSync() async {
    await RoadTaxMonitorService(_supa)
        .syncRoadTaxStates(leaserId: widget.leaserId)
        .catchError((_) {});
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _openNotifications() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const NotificationsPage()),
    );
    if (mounted) {
      setState(() {});
    }
  }

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
      LeaserDashboardPage(leaserId: widget.leaserId),
      VehicleOnboardingPage(
        leaserId: widget.leaserId,
        title: 'My Vehicles',
        embedded: true,
      ),
      VehicleLocationDashboardPage(
        leaserId: widget.leaserId,
        title: 'Vehicle Locations',
        embedded: true,
        allowManageLocations: false,
      ),
      ServiceJobOrdersPage(
        leaserId: widget.leaserId,
        embedded: true,
        title: 'Service Jobs',
        subtitle: 'Create and track maintenance or inspection requests for your vehicles.',
        allowVendorReassign: true,
        allowCancelledStatus: false,
      ),
      VehicleOnboardingStatusPage(
        leaserId: widget.leaserId,
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
              tooltip: 'Refresh road tax status',
              onPressed: _runRoadTaxSync,
              icon: const Icon(Icons.refresh_rounded),
            ),
            IconButton(
              tooltip: 'Notifications',
              onPressed: _openNotifications,
              icon: FutureBuilder<int>(
                future: _notificationSvc.unreadCountForCurrentUser(),
                builder: (context, snapshot) {
                  final unread = snapshot.data ?? 0;
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      const Icon(Icons.notifications_none_rounded),
                      if (unread > 0)
                        Positioned(
                          right: -2,
                          top: -2,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.red,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                            child: Text(
                              unread > 9 ? '9+' : unread.toString(),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
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
