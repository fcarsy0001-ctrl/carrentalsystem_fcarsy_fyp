import 'package:supabase_flutter/supabase_flutter.dart';

import 'in_app_notification_service.dart';

class RoadTaxMonitorService {
  RoadTaxMonitorService(this._client);

  final SupabaseClient _client;

  String _s(dynamic value) => value == null ? '' : value.toString().trim();

  List<Map<String, dynamic>> _rows(dynamic response) {
    if (response is! List) return const [];
    return response.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  DateTime _mytToday() {
    final now = DateTime.now().toUtc().add(const Duration(hours: 8));
    return DateTime(now.year, now.month, now.day);
  }

  DateTime? _dateOnly(dynamic value) {
    final raw = _s(value);
    if (raw.isEmpty) return null;
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return null;
    return DateTime(parsed.year, parsed.month, parsed.day);
  }

  String _fmtDate(DateTime value) => '${value.day}/${value.month}/${value.year}';

  String _vehicleLabel(Map<String, dynamic> row) {
    final plate = _s(row['vehicle_plate_no']);
    final brand = _s(row['vehicle_brand']);
    final model = _s(row['vehicle_model']);
    final title = '$brand $model'.trim();
    if (plate.isNotEmpty && title.isNotEmpty) return '$plate ($title)';
    if (plate.isNotEmpty) return plate;
    if (title.isNotEmpty) return title;
    return _s(row['vehicle_id']).isEmpty ? 'Vehicle' : _s(row['vehicle_id']);
  }

  Future<Map<String, String>> _fetchLeaserUserIds(Set<String> leaserIds) async {
    if (leaserIds.isEmpty) return const {};

    try {
      final rows = _rows(
        await _client
            .from('leaser')
            .select('leaser_id, user_id')
            .inFilter('leaser_id', leaserIds.toList()),
      );

      final output = <String, String>{};
      for (final row in rows) {
        final leaserId = _s(row['leaser_id']);
        final userId = _s(row['user_id']);
        if (leaserId.isNotEmpty && userId.isNotEmpty) {
          output[leaserId] = userId;
        }
      }
      return output;
    } catch (_) {
      return const {};
    }
  }

  Future<void> _markVehicleInactiveIfExpired({
    required String vehicleId,
    required String currentStatus,
  }) async {
    if (vehicleId.isEmpty) return;
    if (currentStatus.toLowerCase() == 'inactive') return;

    try {
      await _client
          .from('vehicle')
          .update({'vehicle_status': 'Inactive'})
          .eq('vehicle_id', vehicleId);
    } catch (_) {}
  }

  Future<void> syncRoadTaxStates({String? leaserId}) async {
    var query = _client.from('vehicle').select(
      'vehicle_id, vehicle_plate_no, vehicle_brand, vehicle_model, vehicle_status, road_tax_expiry_date, leaser_id',
    );
    if (_s(leaserId).isNotEmpty) {
      query = query.eq('leaser_id', leaserId!.trim());
    }

    final vehicles = _rows(await query);
    if (vehicles.isEmpty) return;

    final leaserIds = vehicles
        .map((row) => _s(row['leaser_id']))
        .where((value) => value.isNotEmpty)
        .toSet();
    final leaserUserIds = await _fetchLeaserUserIds(leaserIds);
    final notifications = InAppNotificationService(_client);

    final today = _mytToday();
    final warningDate = today.add(const Duration(days: 7));

    for (final row in vehicles) {
      final expiry = _dateOnly(row['road_tax_expiry_date']);
      if (expiry == null) continue;

      final vehicleId = _s(row['vehicle_id']);
      final label = _vehicleLabel(row);
      final leaserUserId = leaserUserIds[_s(row['leaser_id'])];

      if (expiry.isBefore(today)) {
        await _markVehicleInactiveIfExpired(
          vehicleId: vehicleId,
          currentStatus: _s(row['vehicle_status']),
        );

        if (leaserUserId != null) {
          await notifications.createNotificationOnce(
            userId: leaserUserId,
            type: 'road_tax_expired',
            title: 'Road Tax Expired',
            message:
                '$label road tax expired on ${_fmtDate(expiry)}. This vehicle has been set to Inactive and cannot be rented.',
          );
        }
        continue;
      }

      if (!expiry.isAfter(warningDate) && leaserUserId != null) {
        await notifications.createNotificationOnce(
          userId: leaserUserId,
          type: 'road_tax_expiring',
          title: 'Road Tax Expiring Soon',
          message:
              '$label road tax will expire on ${_fmtDate(expiry)}. Renew it within 1 week to avoid the vehicle becoming Inactive.',
        );
      }
    }
  }
}
