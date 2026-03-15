import 'package:supabase_flutter/supabase_flutter.dart';

class FleetAdminService {
  FleetAdminService(this._client);

  final SupabaseClient _client;

  static const String sqlSetup = '''
create extension if not exists pgcrypto;

create table if not exists public.vehicle_onboarding (
  onboarding_id text primary key,
  vehicle_id character varying not null unique references public.vehicle(vehicle_id) on delete cascade,
  submitted_by text,
  submitted_at timestamp with time zone not null default now(),
  review_status text not null default 'Pending Review',
  eligibility_status text not null default 'Pending',
  readiness_notes text,
  review_remark text,
  reviewed_by text,
  reviewed_at timestamp with time zone
);

create table if not exists public.vehicle_location_history (
  location_history_id text primary key,
  vehicle_id character varying not null references public.vehicle(vehicle_id) on delete cascade,
  previous_location text,
  new_location text not null,
  moved_at timestamp with time zone not null default now(),
  moved_by text,
  movement_reason text
);

create table if not exists public.vendor (
  vendor_id text primary key,
  user_id character varying references public.app_user(user_id) on delete set null,
  auth_uid uuid,
  vendor_name text not null,
  service_category text not null,
  contact_person text,
  vendor_phone text,
  vendor_email text,
  vendor_address text,
  pricing_structure text,
  vendor_rating numeric not null default 0,
  vendor_status text not null default 'Active',
  created_at timestamp with time zone not null default now()
);

create table if not exists public.service_job_order (
  job_order_id text primary key,
  vehicle_id character varying not null references public.vehicle(vehicle_id) on delete cascade,
  vendor_id text references public.vendor(vendor_id) on delete set null,
  job_type text not null,
  priority text not null default 'Medium',
  problem_description text not null,
  preferred_date date,
  status text not null default 'Pending',
  estimated_cost numeric not null default 0,
  actual_cost numeric not null default 0,
  remarks text,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

create table if not exists public.maintenance_schedule (
  schedule_id text primary key,
  vehicle_id character varying not null references public.vehicle(vehicle_id) on delete cascade,
  vendor_id text references public.vendor(vendor_id) on delete set null,
  schedule_type text not null,
  trigger_mileage integer,
  trigger_date date,
  next_maintenance_date date,
  notes text,
  schedule_status text not null default 'Scheduled',
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

create table if not exists public.service_cost (
  service_cost_id text primary key,
  job_order_id text not null references public.service_job_order(job_order_id) on delete cascade,
  vendor_id text references public.vendor(vendor_id) on delete set null,
  labour_cost numeric not null default 0,
  parts_cost numeric not null default 0,
  misc_cost numeric not null default 0,
  tax_cost numeric not null default 0,
  total_cost numeric not null default 0,
  invoice_ref text,
  payment_status text not null default 'Pending',
  service_date date,
  notes text,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);
''';

  String _s(dynamic value) => value == null ? '' : value.toString().trim();

  double _d(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0;
  }

  int _i(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    return int.tryParse(value.toString()) ?? 0;
  }

  String _date(DateTime? value) {
    if (value == null) return '';
    final y = value.year.toString().padLeft(4, '0');
    final m = value.month.toString().padLeft(2, '0');
    final d = value.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  String newVendorId() {
    final micros = DateTime.now().microsecondsSinceEpoch.toString();
    return 'V${micros.substring(micros.length - 5)}';
  }

  String newId(String prefix) {
    final cleaned = prefix.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    final safePrefix = cleaned.isEmpty ? 'ID' : cleaned;
    final suffixLength = safePrefix.length >= 10 ? 1 : 10 - safePrefix.length;
    final micros = DateTime.now().microsecondsSinceEpoch.toString();
    final suffix = micros.substring(micros.length - suffixLength);
    return '$safePrefix$suffix';
  }

  List<Map<String, dynamic>> _rows(dynamic response) {
    if (response is! List) return const [];
    return response.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  bool isMissingTableError(Object error, String table) {
    final message = error.toString().toLowerCase();
    final name = table.toLowerCase();
    return (message.contains(name) && message.contains('does not exist')) ||
        (message.contains('relation') && message.contains(name));
  }

  String explainError(Object error) {
    final message = error.toString();
    if (message.toLowerCase().contains('does not exist') ||
        message.toLowerCase().contains('relation')) {
      return 'The required Supabase table is missing. Paste the admin SQL first, then refresh this module.\n\n$message';
    }
    return message;
  }

  Future<List<Map<String, dynamic>>> fetchVehicles() async {
    final response = await _client
        .from('vehicle')
        .select('vehicle_id, vehicle_brand, vehicle_model, vehicle_plate_no, vehicle_location, vehicle_status, leaser_id')
        .order('vehicle_id', ascending: true);
    return _rows(response);
  }

  Future<List<Map<String, dynamic>>> fetchVendors() async {
    final response = await _client
        .from('vendor')
        .select('*')
        .order('vendor_name', ascending: true);
    return _rows(response);
  }

  Future<void> upsertVendor({
    String? vendorId,
    required String vendorName,
    required String serviceCategory,
    required String contactPerson,
    required String phone,
    required String email,
    required String address,
    required String pricingStructure,
    required double rating,
    required String status,
  }) async {
    final id = _s(vendorId).isEmpty ? newVendorId() : _s(vendorId);
    final payload = <String, dynamic>{
      'vendor_name': vendorName.trim(),
      'service_category': serviceCategory.trim(),
      'contact_person': contactPerson.trim().isEmpty ? null : contactPerson.trim(),
      'vendor_phone': phone.trim().isEmpty ? null : phone.trim(),
      'vendor_email': email.trim().isEmpty ? null : email.trim(),
      'vendor_address': address.trim().isEmpty ? null : address.trim(),
      'pricing_structure': pricingStructure.trim().isEmpty ? null : pricingStructure.trim(),
      'vendor_rating': rating,
      'vendor_status': status.trim(),
    };

    if (_s(vendorId).isEmpty) {
      await _client.from('vendor').insert({'vendor_id': id, ...payload});
    } else {
      await _client.from('vendor').update(payload).eq('vendor_id', id);
    }
  }

  Future<void> deleteVendor(String vendorId) async {
    await _client.from('vendor').delete().eq('vendor_id', vendorId);
  }

  Future<void> updateVendorStatus({
    required String vendorId,
    required String status,
    String? rejectRemark,
  }) async {
    final payload = <String, dynamic>{
      'vendor_status': status.trim(),
      'vendor_reject_remark': _s(rejectRemark).isEmpty ? null : _s(rejectRemark),
      'reviewed_at': DateTime.now().toUtc().toIso8601String(),
    };

    try {
      await _client.from('vendor').update(payload).eq('vendor_id', vendorId.trim());
    } catch (error) {
      final message = error.toString().toLowerCase();
      if (message.contains('vendor_reject_remark') || message.contains('reviewed_at') || message.contains('column')) {
        await _client.from('vendor').update({'vendor_status': status.trim()}).eq('vendor_id', vendorId.trim());
      } else {
        rethrow;
      }
    }
  }
  Future<List<Map<String, dynamic>>> fetchJobOrders() async {
    final response = await _client
        .from('service_job_order')
        .select('*')
        .order('created_at', ascending: false);
    return _rows(response);
  }

  Future<void> upsertJobOrder({
    String? jobOrderId,
    required String vehicleId,
    String? vendorId,
    required String jobType,
    required String priority,
    required String problemDescription,
    DateTime? preferredDate,
    required String status,
    required double estimatedCost,
    required double actualCost,
    required String remarks,
  }) async {
    final id = _s(jobOrderId).isEmpty ? newId('JOB') : _s(jobOrderId);
    final payload = <String, dynamic>{
      'vehicle_id': vehicleId.trim(),
      'vendor_id': _s(vendorId).isEmpty ? null : _s(vendorId),
      'job_type': jobType.trim(),
      'priority': priority.trim(),
      'problem_description': problemDescription.trim(),
      'preferred_date': preferredDate == null ? null : _date(preferredDate),
      'status': status.trim(),
      'estimated_cost': estimatedCost,
      'actual_cost': actualCost,
      'remarks': remarks.trim().isEmpty ? null : remarks.trim(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };

    if (_s(jobOrderId).isEmpty) {
      await _client.from('service_job_order').insert({'job_order_id': id, ...payload});
    } else {
      await _client.from('service_job_order').update(payload).eq('job_order_id', id);
    }
  }

  Future<void> deleteJobOrder(String jobOrderId) async {
    await _client.from('service_job_order').delete().eq('job_order_id', jobOrderId);
  }

  Future<List<Map<String, dynamic>>> fetchMaintenanceSchedules() async {
    final response = await _client
        .from('maintenance_schedule')
        .select('*')
        .order('created_at', ascending: false);
    return _rows(response);
  }

  Future<void> upsertMaintenanceSchedule({
    String? scheduleId,
    required String vehicleId,
    String? vendorId,
    required String scheduleType,
    required int triggerMileage,
    DateTime? triggerDate,
    DateTime? nextMaintenanceDate,
    required String scheduleStatus,
    required String notes,
  }) async {
    final id = _s(scheduleId).isEmpty ? newId('SCH') : _s(scheduleId);
    final payload = <String, dynamic>{
      'vehicle_id': vehicleId.trim(),
      'vendor_id': _s(vendorId).isEmpty ? null : _s(vendorId),
      'schedule_type': scheduleType.trim(),
      'trigger_mileage': triggerMileage <= 0 ? null : triggerMileage,
      'trigger_date': triggerDate == null ? null : _date(triggerDate),
      'next_maintenance_date': nextMaintenanceDate == null ? null : _date(nextMaintenanceDate),
      'schedule_status': scheduleStatus.trim(),
      'notes': notes.trim().isEmpty ? null : notes.trim(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };

    if (_s(scheduleId).isEmpty) {
      await _client.from('maintenance_schedule').insert({'schedule_id': id, ...payload});
    } else {
      await _client.from('maintenance_schedule').update(payload).eq('schedule_id', id);
    }
  }

  Future<void> deleteMaintenanceSchedule(String scheduleId) async {
    await _client.from('maintenance_schedule').delete().eq('schedule_id', scheduleId);
  }

  Future<List<Map<String, dynamic>>> fetchServiceCosts({
    String? vendorId,
    String? jobOrderId,
  }) async {
    var query = _client.from('service_cost').select('*');

    if (_s(vendorId).isNotEmpty) {
      query = query.eq('vendor_id', vendorId!.trim());
    }
    if (_s(jobOrderId).isNotEmpty) {
      query = query.eq('job_order_id', jobOrderId!.trim());
    }

    final response = await query.order('created_at', ascending: false);
    return _rows(response);
  }

  Future<void> upsertServiceCost({
    String? serviceCostId,
    required String jobOrderId,
    String? vendorId,
    required double labourCost,
    required double partsCost,
    required double miscCost,
    required double taxCost,
    required String invoiceRef,
    required String paymentStatus,
    DateTime? serviceDate,
    required String notes,
  }) async {
    final id = _s(serviceCostId).isEmpty ? newId('CST') : _s(serviceCostId);
    final totalCost = labourCost + partsCost + miscCost + taxCost;
    final payload = <String, dynamic>{
      'job_order_id': jobOrderId.trim(),
      'vendor_id': _s(vendorId).isEmpty ? null : _s(vendorId),
      'labour_cost': labourCost,
      'parts_cost': partsCost,
      'misc_cost': miscCost,
      'tax_cost': taxCost,
      'total_cost': totalCost,
      'invoice_ref': invoiceRef.trim().isEmpty ? null : invoiceRef.trim(),
      'payment_status': paymentStatus.trim(),
      'service_date': serviceDate == null ? null : _date(serviceDate),
      'notes': notes.trim().isEmpty ? null : notes.trim(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };

    if (_s(serviceCostId).isEmpty) {
      await _client.from('service_cost').insert({'service_cost_id': id, ...payload});
    } else {
      await _client.from('service_cost').update(payload).eq('service_cost_id', id);
    }
  }

  Future<void> deleteServiceCost(String serviceCostId) async {
    await _client.from('service_cost').delete().eq('service_cost_id', serviceCostId);
  }

  Future<List<Map<String, dynamic>>> fetchVehicleLocationHistory({String? vehicleId}) async {
    var query = _client.from('vehicle_location_history').select('*');

    if (_s(vehicleId).isNotEmpty) {
      query = query.eq('vehicle_id', vehicleId!.trim());
    }

    final response = await query.order('moved_at', ascending: false);
    return _rows(response);
  }

  Future<void> updateVehicleLocation({
    required String vehicleId,
    required String newLocation,
    String? movedBy,
    String? reason,
  }) async {
    final current = await _client
        .from('vehicle')
        .select('vehicle_location')
        .eq('vehicle_id', vehicleId)
        .maybeSingle();

    final previousLocation = current == null ? '' : _s((current as Map)['vehicle_location']);

    await _client
        .from('vehicle')
        .update({'vehicle_location': newLocation.trim()})
        .eq('vehicle_id', vehicleId);

    try {
      await _client.from('vehicle_location_history').insert({
        'location_history_id': newId('LOC'),
        'vehicle_id': vehicleId,
        'previous_location': previousLocation.isEmpty ? null : previousLocation,
        'new_location': newLocation.trim(),
        'moved_by': _s(movedBy).isEmpty ? null : _s(movedBy),
        'movement_reason': _s(reason).isEmpty ? null : _s(reason),
      });
    } catch (_) {}
  }

  Map<String, Map<String, dynamic>> indexBy(List<Map<String, dynamic>> rows, String key) {
    final out = <String, Map<String, dynamic>>{};
    for (final row in rows) {
      final id = _s(row[key]);
      if (id.isNotEmpty) out[id] = row;
    }
    return out;
  }

  String vehicleLabel(Map<String, dynamic>? vehicle) {
    if (vehicle == null) return 'Unknown vehicle';
    final brand = _s(vehicle['vehicle_brand']);
    final model = _s(vehicle['vehicle_model']);
    final plate = _s(vehicle['vehicle_plate_no']);
    final title = '$brand $model'.trim();
    if (plate.isEmpty) return title.isEmpty ? _s(vehicle['vehicle_id']) : title;
    return '${title.isEmpty ? _s(vehicle['vehicle_id']) : title} ($plate)';
  }

  String vendorLabel(Map<String, dynamic>? vendor) {
    if (vendor == null) return 'Unassigned';
    final name = _s(vendor['vendor_name']);
    final category = _s(vendor['service_category']);
    if (name.isEmpty) return 'Unassigned';
    return category.isEmpty ? name : '$name - $category';
  }

  double readDouble(Map<String, dynamic> row, String key) => _d(row[key]);

  int readInt(Map<String, dynamic> row, String key) => _i(row[key]);
}








