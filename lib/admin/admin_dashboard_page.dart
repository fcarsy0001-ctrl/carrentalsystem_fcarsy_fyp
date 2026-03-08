
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/admin_access_service.dart';
import '../services/analytics_service.dart';
import 'order_management_page.dart';
import 'reports_admin_page.dart';
import 'user_management_page.dart';
import 'leaser_admin_module_page.dart';
import 'vehicle_admin_page.dart';
import '../core/widgets/simple_charts.dart';

class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({super.key});

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage> {
  SupabaseClient get _supa => Supabase.instance.client;

  late Future<_DashData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_DashData> _load() async {
    final ctx = await AdminAccessService(_supa).getAdminContext();

    final svc = AnalyticsService(_supa);

    final now = DateTime.now();
    final end = DateTime(now.year, now.month, now.day);
    final start = end.subtract(const Duration(days: 13)); // last 14 days inclusive

    final metrics = await svc.loadAdminMetrics();
    final series = await svc.adminDailySeries(start: start, end: end);

    return _DashData(ctx: ctx, metrics: metrics, series: series, start: start, end: end);
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
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
        if (d == null) {
          return const Center(child: Text('No data'));
        }

        final series = d.series;
        final bookingCounts = series.map((e) => e.count).toList();
        final revenue = series.map((e) => e.revenue).toList();

        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              Row(
                children: [
                  Expanded(
                    child: _KpiCard(
                      title: 'Users',
                      value: d.metrics.users.toString(),
                      icon: Icons.people_alt_outlined,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const UserManagementPage()),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _KpiCard(
                      title: 'Leasers',
                      value: d.metrics.leasers.toString(),
                      icon: Icons.handshake_outlined,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const LeaserAdminModulePage()),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _KpiCard(
                      title: 'Order Total',
                      value: _money(d.metrics.orderTotal),
                      icon: Icons.shopping_bag_outlined,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const OrderManagementPage()),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _KpiCard(
                      title: 'Platform Revenue',
                      subtitle: 'Commission ${(PlatformRates.commissionRate * 100).toStringAsFixed(0)}%',
                      value: _money(d.metrics.platformRevenue),
                      icon: Icons.payments_outlined,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const ReportsAdminPage()),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 18),

              _Section(
                title: 'Order Management',
                subtitle: 'View orders only • Deactivate if user issue',
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const OrderManagementPage()),
                  ),
                  icon: const Icon(Icons.receipt_long_outlined),
                  label: const Text('Open Orders'),
                ),
              ),

              const SizedBox(height: 14),

              _Section(
                title: 'Reports',
                subtitle: 'Weekly / Monthly / Yearly commission reports',
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ReportsAdminPage()),
                  ),
                  icon: const Icon(Icons.analytics_outlined),
                  label: const Text('Generate Reports'),
                ),
              ),

              const SizedBox(height: 18),

              _Section(
                title: 'Booking rate (last 14 days)',
                subtitle: '${_fmtDate(d.start)} → ${_fmtDate(d.end)}',
                child: SimpleBarChart(values: bookingCounts),
              ),

              const SizedBox(height: 14),

              _Section(
                title: 'Revenue by day (commission)',
                subtitle: 'Based on Paid bookings',
                child: SimpleLineChart(values: revenue),
              ),

              const SizedBox(height: 18),

              _Section(
                title: 'Quick access',
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _QuickChip(
                      icon: Icons.directions_car_outlined,
                      label: 'Vehicles',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const VehicleAdminPage()),
                      ),
                    ),
                    _QuickChip(
                      icon: Icons.people_alt_outlined,
                      label: 'Users',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const UserManagementPage()),
                      ),
                    ),
                    _QuickChip(
                      icon: Icons.handshake_outlined,
                      label: 'Leasers',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const LeaserAdminModulePage()),
                      ),
                    ),
                  ],
                ),
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
    required this.ctx,
    required this.metrics,
    required this.series,
    required this.start,
    required this.end,
  });

  final AdminContext ctx;
  final AdminMetrics metrics;
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
    this.onTap,
  });

  final String title;
  final String value;
  final IconData icon;
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
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

class _QuickChip extends StatelessWidget {
  const _QuickChip({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: Icon(icon, size: 18),
      label: Text(label),
      onPressed: onTap,
    );
  }
}
