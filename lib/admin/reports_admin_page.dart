
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/analytics_service.dart';
import '../core/widgets/simple_charts.dart';

class ReportsAdminPage extends StatefulWidget {
  const ReportsAdminPage({super.key});

  @override
  State<ReportsAdminPage> createState() => _ReportsAdminPageState();
}

enum _Period { week, month, year }

class _ReportsAdminPageState extends State<ReportsAdminPage> {
  SupabaseClient get _supa => Supabase.instance.client;

  _Period _period = _Period.week;
  DateTime _anchor = DateTime.now();

  bool _loading = false;
  String? _error;

  AdminMetrics? _metrics;
  List<DailySeriesPoint> _series = const [];
  DateTime? _start;
  DateTime? _end;

  String _money(num v) => 'RM ${v.toStringAsFixed(2)}';

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  DateTime _weekStart(DateTime d) {
    final dd = _dateOnly(d);
    final weekday = dd.weekday; // 1..7 (Mon..Sun)
    return dd.subtract(Duration(days: weekday - 1));
  }

  DateTime _monthStart(DateTime d) => DateTime(d.year, d.month, 1);

  DateTime _monthEnd(DateTime d) => DateTime(d.year, d.month + 1, 0);

  DateTime _yearStart(DateTime d) => DateTime(d.year, 1, 1);

  DateTime _yearEnd(DateTime d) => DateTime(d.year, 12, 31);

  void _computeRange() {
    switch (_period) {
      case _Period.week:
        _start = _weekStart(_anchor);
        _end = _start!.add(const Duration(days: 6));
        break;
      case _Period.month:
        _start = _monthStart(_anchor);
        _end = _monthEnd(_anchor);
        break;
      case _Period.year:
        _start = _yearStart(_anchor);
        _end = _yearEnd(_anchor);
        break;
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _anchor,
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime(DateTime.now().year + 1, 12, 31),
    );
    if (picked == null) return;
    setState(() => _anchor = picked);
  }

  Future<void> _generate() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      _computeRange();
      final s = _start!;
      final e = _end!;
      final svc = AnalyticsService(_supa);
      final m = await svc.loadAdminMetrics(start: s, end: e);
      final series = await svc.adminDailySeries(start: s, end: e);
      setState(() {
        _metrics = m;
        _series = series;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  String _rangeText() {
    _computeRange();
    final s = _start!;
    final e = _end!;
    return '${s.day}/${s.month}/${s.year} → ${e.day}/${e.month}/${e.year}';
  }

  @override
  void initState() {
    super.initState();
    _generate();
  }

  @override
  Widget build(BuildContext context) {
    final rangeText = _rangeText();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports (Commission)'),
        centerTitle: true,
        actions: [
          IconButton(onPressed: _pickDate, icon: const Icon(Icons.date_range_outlined)),
          IconButton(onPressed: _generate, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Row(
            children: [
              Expanded(
                child: SegmentedButton<_Period>(
                  segments: const [
                    ButtonSegment(value: _Period.week, label: Text('Week')),
                    ButtonSegment(value: _Period.month, label: Text('Month')),
                    ButtonSegment(value: _Period.year, label: Text('Year')),
                  ],
                  selected: {_period},
                  onSelectionChanged: (s) {
                    setState(() => _period = s.first);
                    _generate();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text('Range: $rangeText', style: TextStyle(color: Colors.grey.shade700)),
          const SizedBox(height: 14),

          if (_loading) const Center(child: Padding(padding: EdgeInsets.all(18), child: CircularProgressIndicator())),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text('Failed: $_error', style: const TextStyle(color: Colors.red)),
            ),

          if (_metrics != null && !_loading) ...[
            _SummaryCard(
              title: 'Summary',
              items: [
                _SummaryItem('Paid Orders', _metrics!.orders.toString()),
                _SummaryItem('Order Total Amount', _money(_metrics!.orderTotal)),
                _SummaryItem('Commission Rate', '${(PlatformRates.commissionRate * 100).toStringAsFixed(0)}%'),
                _SummaryItem('Commission Earned', _money(_metrics!.platformRevenue)),
              ],
            ),

            const SizedBox(height: 14),

            _Section(
              title: 'Booking rate',
              subtitle: 'Paid bookings per day',
              child: SimpleBarChart(values: _series.map((e) => e.count).toList()),
            ),

            const SizedBox(height: 14),

            _Section(
              title: 'Revenue by day',
              subtitle: 'Commission per day',
              child: SimpleLineChart(values: _series.map((e) => e.revenue).toList()),
            ),

            const SizedBox(height: 14),

            _Section(
              title: 'Daily breakdown',
              subtitle: 'Tap to copy value',
              child: Column(
                children: _series.map((p) {
                  final label = '${p.day.day}/${p.day.month}';
                  final line = '$label • Orders ${p.count} • Total ${_money(p.gross)} • Commission ${_money(p.revenue)}';
                  return ListTile(
                    dense: true,
                    title: Text(line, style: const TextStyle(fontWeight: FontWeight.w700)),
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(line)),
                      );
                    },
                  );
                }).toList(),
              ),
            ),
          ],
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

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.title, required this.items});

  final String title;
  final List<_SummaryItem> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade300),
        color: Colors.white,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          ...items.map((e) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(child: Text(e.k, style: TextStyle(color: Colors.grey.shade700))),
                    Text(e.v, style: const TextStyle(fontWeight: FontWeight.w900)),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}

class _SummaryItem {
  const _SummaryItem(this.k, this.v);

  final String k;
  final String v;
}
