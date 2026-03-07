
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/analytics_service.dart';
import '../core/widgets/simple_charts.dart';
import '../admin/vehicle_admin_page.dart';
import 'reports_leaser_page.dart';

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
    final series = await svc.leaserDailySeries(leaserId: widget.leaserId, start: start, end: end);

    return _DashData(metrics: metrics, series: series, start: start, end: end);
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
        if (d == null) return const Center(child: Text('No data'));

        final counts = d.series.map((e) => e.count).toList();
        final revenue = d.series.map((e) => e.revenue).toList();

        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              Row(
                children: [
                  Expanded(
                    child: _KpiCard(
                      title: 'Total Booking',
                      value: d.metrics.bookings.toString(),
                      icon: Icons.receipt_long_outlined,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _KpiCard(
                      title: 'Total Revenue',
                      subtitle: 'Profit after commission',
                      value: _money(d.metrics.netProfit),
                      icon: Icons.payments_outlined,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 14),

              _Section(
                title: 'Reports',
                subtitle: 'Weekly / Monthly / Yearly profit reports',
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => ReportsLeaserPage(leaserId: widget.leaserId)),
                  ),
                  icon: const Icon(Icons.analytics_outlined),
                  label: const Text('Generate Reports'),
                ),
              ),

              const SizedBox(height: 14),

              _Section(
                title: 'Vehicles',
                subtitle: 'Manage your vehicles',
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => VehicleAdminPage(leaserId: widget.leaserId, title: 'My Vehicles')),
                  ),
                  icon: const Icon(Icons.directions_car_outlined),
                  label: const Text('Open Vehicle Module'),
                ),
              ),

              const SizedBox(height: 18),

              _Section(
                title: 'Booking rate (last 14 days)',
                subtitle: '${_fmtDate(d.start)} → ${_fmtDate(d.end)}',
                child: SimpleBarChart(values: counts),
              ),

              const SizedBox(height: 14),

              _Section(
                title: 'Revenue by day',
                subtitle: 'Profit per day',
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
  const _DashData({required this.metrics, required this.series, required this.start, required this.end});

  final LeaserMetrics metrics;
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
