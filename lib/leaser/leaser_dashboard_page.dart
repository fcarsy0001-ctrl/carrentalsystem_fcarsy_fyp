
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../admin/service_job_orders_page.dart';
import '../admin/vehicle_location_dashboard_page.dart';
import '../admin/vehicle_onboarding_page.dart';
import '../core/widgets/simple_charts.dart';
import '../payments/service_job_payment_history_page.dart';
import '../services/analytics_service.dart';
import 'leaser_profile_page.dart';
import 'reports_leaser_page.dart';
import 'vehicle_onboarding_status_page.dart';

class LeaserDashboardPage extends StatefulWidget {
  const LeaserDashboardPage({super.key, required this.leaserId});

  final String leaserId;

  @override
  State<LeaserDashboardPage> createState() => _LeaserDashboardPageState();
}

class _LeaserDashboardPageState extends State<LeaserDashboardPage> {
  SupabaseClient get _supa => Supabase.instance.client;

  late Future<_DashData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_DashData> _load() async {
    final svc = AnalyticsService(_supa);

    final now = DateTime.now();
    final end = DateTime(now.year, now.month, now.day);
    final start = end.subtract(const Duration(days: 13));

    final metrics = await svc.loadLeaserMetrics(leaserId: widget.leaserId);
    final fleet = await svc.loadLeaserFleetMetrics(leaserId: widget.leaserId);
    final series = await svc.leaserDailySeries(leaserId: widget.leaserId, start: start, end: end);

    return _DashData(
      metrics: metrics,
      fleet: fleet,
      series: series,
      start: start,
      end: end,
    );
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _load();
    });
    await _future;
  }

  String _money(num v) => 'RM ${v.toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_DashData>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Failed to load dashboard: ${snap.error}'),
            ),
          );
        }
        final d = snap.data;
        if (d == null) return const Center(child: Text('No data'));

        final counts = d.series.map((e) => e.count).toList();
        final revenue = d.series.map((e) => e.revenue).toList();

        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              GridView.count(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: 1.45,
                children: [
                  _KpiCard(
                    title: 'Total Vehicles',
                    value: d.fleet.totalVehicles.toString(),
                    icon: Icons.directions_car_outlined,
                  ),
                  _KpiCard(
                    title: 'Free Now',
                    value: d.fleet.freeNow.toString(),
                    icon: Icons.check_circle_outline,
                    subtitle: 'Available to rent now',
                  ),
                  _KpiCard(
                    title: 'Occupied Now',
                    value: d.fleet.occupiedNow.toString(),
                    icon: Icons.car_rental_outlined,
                    subtitle: 'Currently in booking use',
                  ),
                  _KpiCard(
                    title: 'Unavailable',
                    value: d.fleet.unavailableNow.toString(),
                    icon: Icons.block_outlined,
                    subtitle: 'Maintenance / inactive / pending',
                  ),
                  _KpiCard(
                    title: 'Gross Sales',
                    value: _money(d.metrics.grossRevenue),
                    icon: Icons.payments_outlined,
                    subtitle: 'This leaser only',
                  ),
                  _KpiCard(
                    title: 'Net Payout',
                    value: _money(d.metrics.netProfit),
                    icon: Icons.account_balance_wallet_outlined,
                    subtitle: 'After commission',
                  ),
                ],
              ),

              const SizedBox(height: 14),

              _Section(
                title: 'Leaser actions',
                subtitle: 'Open your sales report or edit simple profile info',
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => ReportsLeaserPage(leaserId: widget.leaserId)),
                      ),
                      icon: const Icon(Icons.analytics_outlined),
                      label: const Text('Sales Report'),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => LeaserProfilePage(leaserId: widget.leaserId)),
                      ),
                      icon: const Icon(Icons.person_outline),
                      label: const Text('Profile'),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              _Section(
                title: 'Fleet Tools',
                subtitle: 'Manage vehicles, track locations, monitor onboarding, and submit service requests',
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => VehicleOnboardingPage(leaserId: widget.leaserId, title: 'My Vehicles')),
                      ),
                      icon: const Icon(Icons.directions_car_outlined),
                      label: const Text('My Vehicles'),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => VehicleLocationDashboardPage(
                            leaserId: widget.leaserId,
                            title: 'Vehicle Locations',
                            allowManageLocations: false,
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.place_outlined),
                      label: const Text('Vehicle Locations'),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ServiceJobOrdersPage(
                            leaserId: widget.leaserId,
                            title: 'Service Jobs',
                            subtitle: 'Create and track maintenance or inspection requests for your vehicles.',
                            allowVendorReassign: true,
                            allowCancelledStatus: false,
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.build_circle_outlined),
                      label: const Text('Service Jobs'),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ServiceJobPaymentHistoryPage(
                            title: 'Service Payment History',
                            leaserId: widget.leaserId,
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.receipt_long_outlined),
                      label: const Text('Service Payments'),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => VehicleOnboardingStatusPage(leaserId: widget.leaserId)),
                      ),
                      icon: const Icon(Icons.track_changes_outlined),
                      label: const Text('Onboarding Status'),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              _Section(
                title: 'Booking rate (last 14 days)',
                subtitle: '${_fmtDate(d.start)} -> ${_fmtDate(d.end)}',
                child: SimpleBarChart(values: counts),
              ),

              const SizedBox(height: 14),

              _Section(
                title: 'Net payout by day',
                subtitle: 'Estimated daily amount after platform commission',
                child: SimpleLineChart(values: revenue),
              ),
            ],
          ),
        );
      },
    );
  }

  String _fmtDate(DateTime d) => '${d.day}/${d.month}/${d.year}';
}

class _DashData {
  const _DashData({
    required this.metrics,
    required this.fleet,
    required this.series,
    required this.start,
    required this.end,
  });

  final LeaserMetrics metrics;
  final LeaserFleetMetrics fleet;
  final List<DailySeriesPoint> series;
  final DateTime start;
  final DateTime end;
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.title,
    required this.value,
    required this.icon,
    this.subtitle,
  });

  final String title;
  final String value;
  final IconData icon;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade300),
        color: Colors.white,
      ),
      child: Row(
        children: [
          Icon(icon),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!, style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
                ],
                const SizedBox(height: 6),
                Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, this.subtitle, required this.child});

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Colors.grey.shade50,
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(subtitle!, style: TextStyle(color: Colors.grey.shade700)),
          ],
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}
