import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/analytics_service.dart';

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

  int _selectedBookingsIndex = 0;
  int _selectedRevenueIndex = 0;

  String _money(num v) => 'RM ${v.toStringAsFixed(2)}';

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  DateTime _weekStart(DateTime d) {
    final dd = _dateOnly(d);
    final weekday = dd.weekday;
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
      final display = _displaySeriesFrom(series);
      setState(() {
        _metrics = m;
        _series = series;
        _selectedBookingsIndex = display.isEmpty ? 0 : display.length - 1;
        _selectedRevenueIndex = display.isEmpty ? 0 : display.length - 1;
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

  List<_ReportBucket> _displaySeriesFrom(List<DailySeriesPoint> source) {
    if (source.isEmpty) return const [];

    if (_period == _Period.week) {
      return source
          .map(
            (p) => _ReportBucket(
              label: _weekdayShort(p.day.weekday),
              rangeText: '${p.day.day}/${p.day.month}/${p.day.year}',
              count: p.count,
              gross: p.gross,
              revenue: p.revenue,
            ),
          )
          .toList();
    }

    if (_period == _Period.month) {
      final out = <_ReportBucket>[];
      var i = 0;
      while (i < source.length) {
        final start = source[i].day;
        final endIndex = math.min(i + 6, source.length - 1);
        final end = source[endIndex].day;
        var count = 0;
        var gross = 0.0;
        var revenue = 0.0;
        for (var j = i; j <= endIndex; j++) {
          count += source[j].count;
          gross += source[j].gross;
          revenue += source[j].revenue;
        }
        out.add(
          _ReportBucket(
            label: 'W${out.length + 1}',
            rangeText: '${start.day}/${start.month} - ${end.day}/${end.month}',
            count: count,
            gross: gross,
            revenue: revenue,
          ),
        );
        i += 7;
      }
      return out;
    }

    final grouped = <String, _MutableBucket>{};
    for (final p in source) {
      final key = '${p.day.year}-${p.day.month}';
      final item = grouped.putIfAbsent(
        key,
        () => _MutableBucket(
          label: _monthShort(p.day.month),
          rangeText: '${_monthShort(p.day.month)} ${p.day.year}',
        ),
      );
      item.count += p.count;
      item.gross += p.gross;
      item.revenue += p.revenue;
    }

    return grouped.values
        .map(
          (e) => _ReportBucket(
            label: e.label,
            rangeText: e.rangeText,
            count: e.count,
            gross: e.gross,
            revenue: e.revenue,
          ),
        )
        .toList();
  }

  String _weekdayShort(int weekday) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[(weekday - 1).clamp(0, 6)];
  }

  String _monthShort(int month) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return months[(month - 1).clamp(0, 11)];
  }

  String _bucketLabel() {
    switch (_period) {
      case _Period.week:
        return 'day';
      case _Period.month:
        return 'week';
      case _Period.year:
        return 'month';
    }
  }

  @override
  void initState() {
    super.initState();
    _generate();
  }

  @override
  Widget build(BuildContext context) {
    final rangeText = _rangeText();
    final display = _displaySeriesFrom(_series);
    final bookingPick = display.isEmpty ? null : display[_selectedBookingsIndex.clamp(0, display.length - 1)];
    final revenuePick = display.isEmpty ? null : display[_selectedRevenueIndex.clamp(0, display.length - 1)];

    final topBooking = display.isEmpty
        ? null
        : display.reduce((a, b) => a.count >= b.count ? a : b);
    final topRevenue = display.isEmpty
        ? null
        : display.reduce((a, b) => a.revenue >= b.revenue ? a : b);

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
          if (_loading)
            const Center(child: Padding(padding: EdgeInsets.all(18), child: CircularProgressIndicator())),
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
              title: 'Highlights',
              subtitle: 'Compact view for mobile',
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _InfoChip(
                    title: 'View by',
                    value: _bucketLabel().toUpperCase(),
                    icon: Icons.tune_rounded,
                  ),
                  _InfoChip(
                    title: 'Best bookings',
                    value: topBooking == null ? '-' : '${topBooking.label} • ${topBooking.count}',
                    icon: Icons.bar_chart_rounded,
                  ),
                  _InfoChip(
                    title: 'Best commission',
                    value: topRevenue == null ? '-' : '${topRevenue.label} • ${_money(topRevenue.revenue)}',
                    icon: Icons.payments_outlined,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _Section(
              title: 'Booking volume',
              subtitle: 'Tap any bar to show exact value',
              child: Column(
                children: [
                  _TapBarChart(
                    values: display.map((e) => e.count.toDouble()).toList(),
                    labels: display.map((e) => e.label).toList(),
                    selectedIndex: _selectedBookingsIndex,
                    onSelected: (index) => setState(() => _selectedBookingsIndex = index),
                  ),
                  const SizedBox(height: 10),
                  _SelectedMetricCard(
                    title: bookingPick == null ? 'No data' : bookingPick.label,
                    subtitle: bookingPick?.rangeText ?? '-',
                    items: [
                      _SummaryItem('Orders', bookingPick?.count.toString() ?? '0'),
                      _SummaryItem('Gross Amount', _money(bookingPick?.gross ?? 0)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _Section(
              title: 'Commission trend',
              subtitle: 'Tap any bar to show exact value',
              child: Column(
                children: [
                  _TapBarChart(
                    values: display.map((e) => e.revenue).toList(),
                    labels: display.map((e) => e.label).toList(),
                    selectedIndex: _selectedRevenueIndex,
                    onSelected: (index) => setState(() => _selectedRevenueIndex = index),
                  ),
                  const SizedBox(height: 10),
                  _SelectedMetricCard(
                    title: revenuePick == null ? 'No data' : revenuePick.label,
                    subtitle: revenuePick?.rangeText ?? '-',
                    items: [
                      _SummaryItem('Commission', _money(revenuePick?.revenue ?? 0)),
                      _SummaryItem('Orders', revenuePick?.count.toString() ?? '0'),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ReportBucket {
  const _ReportBucket({
    required this.label,
    required this.rangeText,
    required this.count,
    required this.gross,
    required this.revenue,
  });

  final String label;
  final String rangeText;
  final int count;
  final double gross;
  final double revenue;
}

class _MutableBucket {
  _MutableBucket({required this.label, required this.rangeText});

  final String label;
  final String rangeText;
  int count = 0;
  double gross = 0;
  double revenue = 0;
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
        color: Theme.of(context).colorScheme.primary.withOpacity(0.06),
        border: Border.all(color: Theme.of(context).colorScheme.primary.withOpacity(0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          const SizedBox(height: 12),
          ...items.map(
            (e) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Expanded(child: Text(e.label, style: TextStyle(color: Colors.grey.shade800))),
                  Text(e.value, style: const TextStyle(fontWeight: FontWeight.w900)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectedMetricCard extends StatelessWidget {
  const _SelectedMetricCard({required this.title, required this.subtitle, required this.items});

  final String title;
  final String subtitle;
  final List<_SummaryItem> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 2),
          Text(subtitle, style: TextStyle(color: Colors.grey.shade700)),
          const SizedBox(height: 8),
          ...items.map(
            (e) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Expanded(child: Text(e.label)),
                  Text(e.value, style: const TextStyle(fontWeight: FontWeight.w800)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TapBarChart extends StatelessWidget {
  const _TapBarChart({
    required this.values,
    required this.labels,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<double> values;
  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) {
      return Container(
        height: 120,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: Colors.grey.shade100,
        ),
        child: Text('No data', style: TextStyle(color: Colors.grey.shade700)),
      );
    }

    final maxValue = values.reduce(math.max);

    return SizedBox(
      height: 170,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(values.length, (index) {
          final raw = values[index];
          final factor = maxValue <= 0 ? 0.06 : (raw / maxValue).clamp(0.0, 1.0);
          final isSelected = index == selectedIndex;

          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => onSelected(index),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      height: 28 + (factor * 92),
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.primary.withOpacity(0.24),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.primary.withOpacity(0.08),
                        ),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: Theme.of(context).colorScheme.primary.withOpacity(0.18),
                                  blurRadius: 8,
                                  offset: const Offset(0, 4),
                                ),
                              ]
                            : null,
                      ),
                      alignment: Alignment.topCenter,
                      padding: const EdgeInsets.only(top: 8),
                      child: isSelected
                          ? Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.16),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: const Icon(Icons.touch_app_rounded, size: 14, color: Colors.white),
                            )
                          : null,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      labels[index],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                        color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.title, required this.value, required this.icon});

  final String title;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 110),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
              const SizedBox(height: 2),
              Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryItem {
  const _SummaryItem(this.label, this.value);

  final String label;
  final String value;
}
