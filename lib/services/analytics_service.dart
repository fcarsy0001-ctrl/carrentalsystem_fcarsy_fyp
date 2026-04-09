
import 'package:supabase_flutter/supabase_flutter.dart';

/// Analytics / reporting for Admin + Leaser.
///
/// NOTE (assumption):
/// This project does not store commission rate in DB.
/// We use a fixed platform commission rate. Change it here if needed.
class PlatformRates {
  static const double commissionRate = 0.10; // 10%
}

class AdminMetrics {
  const AdminMetrics({
    required this.users,
    required this.leasers,
    required this.orders,
    required this.orderTotal,
    required this.platformRevenue,
  });

  final int users;
  final int leasers;
  final int orders;
  final double orderTotal;
  final double platformRevenue;
}

class LeaserMetrics {
  const LeaserMetrics({
    required this.bookings,
    required this.grossRevenue,
    required this.netProfit,
  });

  final int bookings;
  final double grossRevenue;
  final double netProfit;
}

class LeaserFleetMetrics {
  const LeaserFleetMetrics({
    required this.totalVehicles,
    required this.freeNow,
    required this.occupiedNow,
    required this.unavailableNow,
  });

  final int totalVehicles;
  final int freeNow;
  final int occupiedNow;
  final int unavailableNow;
}

class DailySeriesPoint {
  const DailySeriesPoint({
    required this.day,
    required this.count,
    required this.gross,
    required this.revenue,
  });

  final DateTime day;
  final int count;
  final double gross;

  /// For admin: commission revenue. For leaser: net profit.
  final double revenue;
}

class AnalyticsService {
  AnalyticsService(this._client);

  final SupabaseClient _client;

  String _ymd(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '$y-$m-$dd';
  }

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  bool _isPaid(Map<String, dynamic> r) {
    final st = (r['booking_status'] ?? '').toString().trim().toLowerCase();
    return st == 'paid';
  }

  String _s(dynamic value) => value == null ? '' : value.toString().trim();

  double _dnum(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  DateTime? _dt(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    return DateTime.tryParse(value.toString());
  }

  bool _isFinishedStatus(String status) {
    return status == 'cancel' ||
        status == 'cancelled' ||
        status == 'canceled' ||
        status == 'deactive' ||
        status == 'deactivated' ||
        status == 'inactive' ||
        status == 'completed' ||
        status == 'complete' ||
        status == 'done' ||
        status == 'expired' ||
        status == 'failed';
  }

  bool _isVehicleOccupiedNow(Map<String, dynamic> row, DateTime now) {
    final status = _s(row['booking_status']).toLowerCase();
    if (status.isEmpty) return false;
    if (_isFinishedStatus(status)) return false;
    if (status == 'holding') return false;

    final dropoffCompletedAt = _dt(row['dropoff_completed_at']) ?? _dt(row['actual_dropoff_at']);
    if (dropoffCompletedAt != null) return false;

    final pickupCompletedAt = _dt(row['pickup_completed_at']);
    if (pickupCompletedAt != null) return true;

    if (status == 'active') return true;

    final rentalStart = _dt(row['rental_start']);
    if (rentalStart != null && !rentalStart.isAfter(now)) {
      return true;
    }

    return false;
  }

  Future<AdminMetrics> loadAdminMetrics({DateTime? start, DateTime? end}) async {
    final uRows = await _client
        .from('app_user')
        .select('user_id,user_role')
        .limit(5000);
    int users = 0;
    if (uRows is List) {
      for (final e in uRows) {
        final m = e is Map ? e : null;
        if (m == null) continue;
        final role = (m['user_role'] ?? '').toString().trim().toLowerCase();
        if (role == 'user') users++;
      }
    }

    final lRows = await _client
        .from('leaser')
        .select('leaser_id,leaser_status')
        .limit(5000);
    int leasers = 0;
    if (lRows is List) {
      for (final e in lRows) {
        final m = e is Map ? e : null;
        if (m == null) continue;
        final st = (m['leaser_status'] ?? '').toString().trim().toLowerCase();
        if (st == 'approved' || st == 'active') leasers++;
      }
    }

    var q = _client
        .from('booking')
        .select('booking_id,booking_date,booking_status,total_rental_amount')
        .eq('booking_status', 'Paid');

    if (start != null) {
      q = q.gte('booking_date', _ymd(_dateOnly(start)));
    }
    if (end != null) {
      q = q.lte('booking_date', _ymd(_dateOnly(end)));
    }

    final bRows = await q.limit(20000);
    int orders = 0;
    double total = 0;
    if (bRows is List) {
      for (final e in bRows) {
        final m = e is Map ? Map<String, dynamic>.from(e as Map) : null;
        if (m == null) continue;
        if (!_isPaid(m)) continue;
        orders++;
        total += _dnum(m['total_rental_amount']);
      }
    }

    final commission = total * PlatformRates.commissionRate;

    return AdminMetrics(
      users: users,
      leasers: leasers,
      orders: orders,
      orderTotal: total,
      platformRevenue: commission,
    );
  }

  Future<List<DailySeriesPoint>> adminDailySeries({
    required DateTime start,
    required DateTime end,
  }) async {
    final s = _dateOnly(start);
    final e = _dateOnly(end);

    var q = _client
        .from('booking')
        .select('booking_date,booking_status,total_rental_amount')
        .eq('booking_status', 'Paid')
        .gte('booking_date', _ymd(s))
        .lte('booking_date', _ymd(e));

    final rows = await q.limit(20000);

    final map = <DateTime, List<Map<String, dynamic>>>{};
    if (rows is List) {
      for (final r in rows) {
        if (r is! Map) continue;
        final m = Map<String, dynamic>.from(r);
        if (!_isPaid(m)) continue;
        final raw = m['booking_date'];
        DateTime? day;
        if (raw is DateTime) day = _dateOnly(raw);
        if (raw != null && day == null) {
          day = DateTime.tryParse(raw.toString());
          if (day != null) day = _dateOnly(day);
        }
        day ??= _dateOnly(DateTime.now());
        map.putIfAbsent(day, () => []).add(m);
      }
    }

    final out = <DailySeriesPoint>[];
    for (DateTime d = s; !d.isAfter(e); d = d.add(const Duration(days: 1))) {
      final list = map[_dateOnly(d)] ?? const [];
      final count = list.length;
      double gross = 0;
      for (final m in list) {
        gross += _dnum(m['total_rental_amount']);
      }
      out.add(DailySeriesPoint(
        day: _dateOnly(d),
        count: count,
        gross: gross,
        revenue: gross * PlatformRates.commissionRate,
      ));
    }
    return out;
  }

  Future<LeaserMetrics> loadLeaserMetrics({
    required String leaserId,
    DateTime? start,
    DateTime? end,
  }) async {
    var q = _client
        .from('booking')
        .select('booking_id,booking_date,booking_status,total_rental_amount,vehicle:vehicle_id!inner(leaser_id)')
        .eq('booking_status', 'Paid')
        .eq('vehicle.leaser_id', leaserId);

    if (start != null) {
      q = q.gte('booking_date', _ymd(_dateOnly(start)));
    }
    if (end != null) {
      q = q.lte('booking_date', _ymd(_dateOnly(end)));
    }

    final rows = await q.limit(20000);

    int bookings = 0;
    double gross = 0;
    if (rows is List) {
      for (final r in rows) {
        if (r is! Map) continue;
        final m = Map<String, dynamic>.from(r);
        if (!_isPaid(m)) continue;
        bookings++;
        gross += _dnum(m['total_rental_amount']);
      }
    }

    final net = gross * (1 - PlatformRates.commissionRate);

    return LeaserMetrics(bookings: bookings, grossRevenue: gross, netProfit: net);
  }

  Future<LeaserFleetMetrics> loadLeaserFleetMetrics({
    required String leaserId,
  }) async {
    final vehiclesResp = await _client
        .from('vehicle')
        .select('vehicle_id,vehicle_status')
        .eq('leaser_id', leaserId)
        .limit(5000);

    final vehicles = <Map<String, dynamic>>[];
    if (vehiclesResp is List) {
      for (final row in vehiclesResp) {
        if (row is Map) vehicles.add(Map<String, dynamic>.from(row));
      }
    }

    final bookingResp = await _client
        .from('booking')
        .select('vehicle_id,booking_status,rental_start,rental_end,pickup_completed_at,dropoff_completed_at,actual_dropoff_at,vehicle:vehicle_id!inner(leaser_id)')
        .eq('vehicle.leaser_id', leaserId)
        .limit(20000);

    final now = DateTime.now();
    final occupiedIds = <String>{};
    if (bookingResp is List) {
      for (final row in bookingResp) {
        if (row is! Map) continue;
        final m = Map<String, dynamic>.from(row);
        final vehicleId = _s(m['vehicle_id']);
        if (vehicleId.isEmpty) continue;
        if (_isVehicleOccupiedNow(m, now)) {
          occupiedIds.add(vehicleId);
        }
      }
    }

    int freeNow = 0;
    for (final vehicle in vehicles) {
      final vehicleId = _s(vehicle['vehicle_id']);
      final status = _s(vehicle['vehicle_status']).toLowerCase();
      final isAvailableStatus = status == 'available';
      if (vehicleId.isNotEmpty && isAvailableStatus && !occupiedIds.contains(vehicleId)) {
        freeNow++;
      }
    }

    final totalVehicles = vehicles.length;
    final occupiedNow = occupiedIds.length;
    final unavailableNow = totalVehicles - freeNow - occupiedNow < 0
        ? 0
        : totalVehicles - freeNow - occupiedNow;

    return LeaserFleetMetrics(
      totalVehicles: totalVehicles,
      freeNow: freeNow,
      occupiedNow: occupiedNow,
      unavailableNow: unavailableNow,
    );
  }

  Future<List<DailySeriesPoint>> leaserDailySeries({
    required String leaserId,
    required DateTime start,
    required DateTime end,
  }) async {
    final s = _dateOnly(start);
    final e = _dateOnly(end);

    var q = _client
        .from('booking')
        .select('booking_date,booking_status,total_rental_amount,vehicle:vehicle_id!inner(leaser_id)')
        .eq('booking_status', 'Paid')
        .eq('vehicle.leaser_id', leaserId)
        .gte('booking_date', _ymd(s))
        .lte('booking_date', _ymd(e));

    final rows = await q.limit(20000);

    final map = <DateTime, List<Map<String, dynamic>>>{};
    if (rows is List) {
      for (final r in rows) {
        if (r is! Map) continue;
        final m = Map<String, dynamic>.from(r);
        if (!_isPaid(m)) continue;
        final raw = m['booking_date'];
        DateTime? day;
        if (raw is DateTime) day = _dateOnly(raw);
        if (raw != null && day == null) {
          day = DateTime.tryParse(raw.toString());
          if (day != null) day = _dateOnly(day);
        }
        day ??= _dateOnly(DateTime.now());
        map.putIfAbsent(day, () => []).add(m);
      }
    }

    final out = <DailySeriesPoint>[];
    for (DateTime d = s; !d.isAfter(e); d = d.add(const Duration(days: 1))) {
      final list = map[_dateOnly(d)] ?? const [];
      final count = list.length;
      double gross = 0;
      for (final m in list) {
        gross += _dnum(m['total_rental_amount']);
      }
      out.add(DailySeriesPoint(
        day: _dateOnly(d),
        count: count,
        gross: gross,
        revenue: gross * (1 - PlatformRates.commissionRate),
      ));
    }
    return out;
  }
}
