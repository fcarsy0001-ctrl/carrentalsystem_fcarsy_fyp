import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../main.dart';
import '../support/admin_support_page.dart';
import 'admin_dashboard_page.dart';
import 'driver_license_review_page.dart';
import 'leaser_admin_module_page.dart';
import 'maintenance_schedule_admin_page.dart';
import 'order_management_page.dart';
import 'promotion_admin_page.dart';
import 'reports_admin_page.dart';
import 'service_job_orders_page.dart';
import 'staff_admin_page.dart';
import 'user_management_page.dart';
import 'vehicle_location_dashboard_page.dart';
import 'vehicle_onboarding_page.dart';
import 'vendor_cost_admin_page.dart';

class AdminShell extends StatefulWidget {
  const AdminShell({super.key, required this.isSuperAdmin});

  final bool isSuperAdmin;

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  SupabaseClient get _supa => Supabase.instance.client;

  int _index = 0;

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
    final items = <_NavItem>[
      const _NavItem('Dashboard', Icons.dashboard_outlined, AdminDashboardPage()),
      const _NavItem(
        'Vehicle List',
        Icons.directions_car_outlined,
        VehicleOnboardingPage(
          embedded: true,
          title: 'Vehicle List',
          adminView: AdminVehicleView.approvedOnly,
        ),
      ),
      const _NavItem(
        'Onboarding',
        Icons.fact_check_outlined,
        VehicleOnboardingPage(
          embedded: true,
          title: 'Vehicle Onboarding',
          adminView: AdminVehicleView.onboardingQueue,
        ),
      ),
      const _NavItem('Locations', Icons.place_outlined, VehicleLocationDashboardPage(embedded: true)),
      const _NavItem('Service Jobs', Icons.build_circle_outlined, ServiceJobOrdersPage(embedded: true)),
      const _NavItem('Maintenance', Icons.calendar_month_outlined, MaintenanceScheduleAdminPage(embedded: true)),
      const _NavItem('Vendors & Cost', Icons.inventory_2_outlined, VendorCostAdminPage(embedded: true)),
      const _NavItem('Orders', Icons.receipt_long_outlined, OrderManagementPage()),
      const _NavItem('Reports', Icons.bar_chart_outlined, ReportsAdminPage()),
      const _NavItem('Licences', Icons.badge_outlined, DriverLicenseReviewPage()),
      const _NavItem('Leasers', Icons.handshake_outlined, LeaserAdminModulePage()),
      const _NavItem('Users', Icons.people_alt_outlined, UserManagementPage()),
      const _NavItem('Promotions', Icons.local_offer_outlined, PromotionAdminPage()),
      const _NavItem('Support', Icons.support_agent_outlined, AdminSupportPage(embedded: true)),
      if (widget.isSuperAdmin) const _NavItem('Staff', Icons.supervisor_account_outlined, StaffAdminPage()),
    ];

    if (_index >= items.length) _index = 0;

    final isWide = MediaQuery.sizeOf(context).width >= 900;
    final body = items[_index].page;

    return Scaffold(
      appBar: AppBar(
        title: Text(items[_index].label),
        scrolledUnderElevation: 0,
        actions: [
          IconButton(
            tooltip: 'Logout',
            onPressed: _logout,
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      drawer: isWide
          ? null
          : Drawer(
        child: SafeArea(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              const SizedBox(height: 8),
              for (var i = 0; i < items.length; i++)
                ListTile(
                  leading: Icon(items[i].icon),
                  title: Text(items[i].label),
                  selected: i == _index,
                  onTap: () {
                    setState(() => _index = i);
                    Navigator.pop(context);
                  },
                ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.logout_rounded),
                title: const Text('Logout'),
                onTap: () async {
                  Navigator.pop(context);
                  await _logout();
                },
              ),
            ],
          ),
        ),
      ),
      body: isWide
          ? Row(
        children: [
          NavigationRail(
            selectedIndex: _index,
            labelType: NavigationRailLabelType.all,
            onDestinationSelected: (value) => setState(() => _index = value),
            destinations: [
              for (final item in items)
                NavigationRailDestination(
                  icon: Icon(item.icon),
                  selectedIcon: Icon(item.icon),
                  label: Text(item.label),
                ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: body),
        ],
      )
          : body,
    );
  }
}

class _NavItem {
  const _NavItem(this.label, this.icon, this.page);

  final String label;
  final IconData icon;
  final Widget page;
}

