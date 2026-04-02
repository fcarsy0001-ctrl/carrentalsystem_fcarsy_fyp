import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

class JobOrderModuleService {
  JobOrderModuleService(this._client);

  final SupabaseClient _client;

  static const String attachmentBucket = 'job_order_files';

  static const String setupFilePath = 'supabase/job_order_chapter4_patch.sql';

  static const String paymentSetupFilePath = 'supabase/service_job_payment_patch.sql';

  static const String setupHint =
      'Run the SQL in supabase/job_order_chapter4_patch.sql to create the Job Order tables, activity log, and attachment bucket.';

  String _s(dynamic value) => value == null ? '' : value.toString().trim();

  double _d(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0;
  }

  int _i(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString()) ?? 0;
  }

  String _date(DateTime? value) {
    if (value == null) return '';
    final y = value.year.toString().padLeft(4, '0');
    final m = value.month.toString().padLeft(2, '0');
    final d = value.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  String _safeFileName(String value) {
    final cleaned = value.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return cleaned.isEmpty ? 'attachment' : cleaned;
  }

  String _fileExtension(String fileName) {
    final clean = _safeFileName(fileName);
    final dot = clean.lastIndexOf('.');
    if (dot < 0 || dot == clean.length - 1) return '';
    return clean.substring(dot + 1).toLowerCase();
  }

  String _contentTypeForFile(String fileName) {
    switch (_fileExtension(fileName)) {
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'pdf':
        return 'application/pdf';
      default:
        return 'application/octet-stream';
    }
  }

  List<Map<String, dynamic>> _rows(dynamic response) {
    if (response is! List) return const [];
    return response.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  String newId(String prefix) {
    final cleaned = prefix.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    final safePrefix = cleaned.isEmpty ? 'ID' : cleaned;
    final suffixLength = safePrefix.length >= 10 ? 1 : 10 - safePrefix.length;
    final micros = DateTime.now().microsecondsSinceEpoch.toString();
    final suffix = micros.substring(micros.length - suffixLength);
    return '$safePrefix$suffix';
  }

  Map<String, Map<String, dynamic>> indexBy(List<Map<String, dynamic>> rows, String key) {
    final out = <String, Map<String, dynamic>>{};
    for (final row in rows) {
      final id = _s(row[key]);
      if (id.isNotEmpty) out[id] = row;
    }
    return out;
  }

  DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    return DateTime.tryParse(value.toString());
  }

  String _maintenanceScheduleId(String jobOrderId) {
    final clean = jobOrderId.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    return 'MS${clean.isEmpty ? newId('SCH') : clean}';
  }

  String _maintenanceStatusForJob(String status, DateTime? preferredDate) {
    final normalized = status.trim().toLowerCase();
    if (normalized == 'in progress') return 'In Progress';
    if (normalized == 'completed') return 'Completed';
    if (normalized == 'cancelled') return 'Cancelled';
    if (preferredDate != null) {
      final today = DateTime.now();
      final dueDate = DateTime(preferredDate.year, preferredDate.month, preferredDate.day);
      final currentDay = DateTime(today.year, today.month, today.day);
      if (dueDate.isBefore(currentDay)) return 'Overdue';
    }
    return 'Scheduled';
  }

  Future<void> _setVehicleUnderService(String vehicleId) async {
    final cleanVehicleId = vehicleId.trim();
    if (cleanVehicleId.isEmpty) return;

    try {
      final row = await _client
          .from('vehicle')
          .select('vehicle_status')
          .eq('vehicle_id', cleanVehicleId)
          .maybeSingle();
      final currentStatus = row == null ? '' : _s((row as Map)['vehicle_status']);
      if (currentStatus.toLowerCase() == 'inactive') return;

      await _client
          .from('vehicle')
          .update({'vehicle_status': 'Maintenance'})
          .eq('vehicle_id', cleanVehicleId);
    } catch (_) {}
  }

  Future<void> _restoreVehicleAvailabilityIfPossible(String vehicleId) async {
    final cleanVehicleId = vehicleId.trim();
    if (cleanVehicleId.isEmpty) return;

    try {
      final row = await _client
          .from('vehicle')
          .select('vehicle_status')
          .eq('vehicle_id', cleanVehicleId)
          .maybeSingle();
      final currentStatus = row == null ? '' : _s((row as Map)['vehicle_status']);
      if (currentStatus.toLowerCase() == 'inactive') return;

      final response = await _client
          .from('service_job_order')
          .select('job_order_id')
          .eq('vehicle_id', cleanVehicleId)
          .inFilter('status', ['Pending', 'In Progress']);
      final openJobs = _rows(response);
      final nextStatus = openJobs.isEmpty ? 'Available' : 'Maintenance';

      await _client
          .from('vehicle')
          .update({'vehicle_status': nextStatus})
          .eq('vehicle_id', cleanVehicleId);
    } catch (_) {}
  }

  Future<void> _syncMaintenanceScheduleForJob(Map<String, dynamic> job) async {
    final jobOrderId = _s(job['job_order_id']);
    final vehicleId = _s(job['vehicle_id']);
    if (jobOrderId.isEmpty || vehicleId.isEmpty) return;

    final status = _s(job['status']);
    final preferredDate = _parseDate(job['preferred_date']);
    final scheduleId = _maintenanceScheduleId(jobOrderId);

    try {
      if (preferredDate == null || status == 'Cancelled') {
        await _client.from('maintenance_schedule').delete().eq('schedule_id', scheduleId);
        return;
      }

      final notes = <String>[
        'Linked Job Order: $jobOrderId',
        if (_s(job['problem_description']).isNotEmpty) _s(job['problem_description']),
      ].join('\n');

      final payload = <String, dynamic>{
        'vehicle_id': vehicleId,
        'vendor_id': _s(job['vendor_id']).isEmpty ? null : _s(job['vendor_id']),
        'schedule_type': _s(job['job_type']).isEmpty ? 'Service Job' : _s(job['job_type']),
        'trigger_date': _date(preferredDate),
        'next_maintenance_date': _date(preferredDate),
        'schedule_status': _maintenanceStatusForJob(status, preferredDate),
        'notes': notes,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };

      final existing = await _client
          .from('maintenance_schedule')
          .select('schedule_id')
          .eq('schedule_id', scheduleId)
          .maybeSingle();

      if (existing == null) {
        await _client.from('maintenance_schedule').insert({
          'schedule_id': scheduleId,
          ...payload,
        });
      } else {
        await _client.from('maintenance_schedule').update(payload).eq('schedule_id', scheduleId);
      }
    } catch (_) {}
  }

  String vehicleLabel(Map<String, dynamic>? vehicle) {
    if (vehicle == null) return 'Unknown vehicle';
    final plate = _s(vehicle['vehicle_plate_no']);
    final brand = _s(vehicle['vehicle_brand']);
    final model = _s(vehicle['vehicle_model']);
    final year = _i(vehicle['vehicle_year']);
    final title = '$brand $model'.trim();
    final yearPart = year > 0 ? ' ($year)' : '';
    if (title.isEmpty && plate.isEmpty) return _s(vehicle['vehicle_id']);
    if (plate.isEmpty) return '$title$yearPart'.trim();
    return '$plate${title.isEmpty ? '' : ' - $title'}$yearPart'.trim();
  }

  String vendorLabel(Map<String, dynamic>? vendor) {
    if (vendor == null) return 'Not assigned';
    final name = _s(vendor['vendor_name']);
    final category = _s(vendor['service_category']);
    if (name.isEmpty) return 'Not assigned';
    return category.isEmpty ? name : '$name ($category)';
  }

  Future<Map<String, dynamic>?> resolveCurrentVendor({String? requestedVendorId}) async {
    final user = _client.auth.currentUser;
    if (user == null) return null;

    final cleanRequestedId = _s(requestedVendorId);
    if (cleanRequestedId.isNotEmpty) {
      try {
        final row = await _client
            .from('vendor')
            .select('*')
            .eq('vendor_id', cleanRequestedId)
            .limit(1)
            .maybeSingle();
        if (row != null) return Map<String, dynamic>.from(row as Map);
      } catch (_) {}
    }

    try {
      final row = await _client
          .from('vendor')
          .select('*')
          .eq('auth_uid', user.id)
          .order('vendor_id', ascending: false)
          .limit(1)
          .maybeSingle();
      if (row != null) return Map<String, dynamic>.from(row as Map);
    } catch (_) {}

    final email = _s(user.email).toLowerCase();
    if (email.isNotEmpty) {
      try {
        final row = await _client
            .from('vendor')
            .select('*')
            .eq('vendor_email', email)
            .order('vendor_id', ascending: false)
            .limit(1)
            .maybeSingle();
        if (row != null) return Map<String, dynamic>.from(row as Map);
      } catch (_) {}
    }

    return null;
  }

  Future<List<Map<String, dynamic>>> fetchVehicles({String? leaserId}) async {
    var query = _client
        .from('vehicle')
        .select('vehicle_id, vehicle_brand, vehicle_model, vehicle_plate_no, vehicle_year, mileage_km, vehicle_location, vehicle_status, leaser_id');

    if (_s(leaserId).isNotEmpty) {
      query = query.eq('leaser_id', leaserId!.trim());
    }

    final response = await query.order('vehicle_plate_no', ascending: true);
    return _rows(response);
  }

  Future<List<Map<String, dynamic>>> fetchVendors({bool onlyActive = false}) async {
    var query = _client.from('vendor').select('*');
    if (onlyActive) {
      query = query.eq('vendor_status', 'Active');
    }
    final response = await query.order('vendor_name', ascending: true);
    return _rows(response);
  }

  Future<Set<String>> fetchReservedServiceDateKeysForVehicle(String vehicleId) async {
    final cleanVehicleId = vehicleId.trim();
    if (cleanVehicleId.isEmpty) return <String>{};

    final blocked = <String>{};

    final jobs = await _client
        .from('service_job_order')
        .select('preferred_date, status')
        .eq('vehicle_id', cleanVehicleId);
    for (final job in _rows(jobs)) {
      if (_s(job['status']).toLowerCase() == 'cancelled') continue;
      final date = _parseDate(job['preferred_date']);
      if (date == null) continue;
      blocked.add(_date(date));
    }

    try {
      final schedules = await _client
          .from('maintenance_schedule')
          .select('trigger_date, next_maintenance_date, schedule_status')
          .eq('vehicle_id', cleanVehicleId);
      for (final schedule in _rows(schedules)) {
        if (_s(schedule['schedule_status']).toLowerCase() == 'cancelled') continue;
        for (final raw in [schedule['trigger_date'], schedule['next_maintenance_date']]) {
          final date = _parseDate(raw);
          if (date == null) continue;
          blocked.add(_date(date));
        }
      }
    } catch (_) {}

    return blocked;
  }

  Future<List<Map<String, dynamic>>> fetchJobOrders({
    List<String>? vehicleIds,
    String? vendorId,
  }) async {
    var query = _client.from('service_job_order').select('*');

    if (_s(vendorId).isNotEmpty) {
      query = query.eq('vendor_id', vendorId!.trim());
    }

    if (vehicleIds != null) {
      final ids = vehicleIds.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      if (ids.isEmpty) return const [];
      query = query.inFilter('vehicle_id', ids);
    }

    final response = await query.order('created_at', ascending: false);
    return _rows(response);
  }

  Future<Map<String, dynamic>?> fetchJobOrder(String jobOrderId) async {
    final row = await _client
        .from('service_job_order')
        .select('*')
        .eq('job_order_id', jobOrderId)
        .maybeSingle();
    if (row == null) return null;
    return Map<String, dynamic>.from(row as Map);
  }

  Future<List<Map<String, dynamic>>> fetchServiceCostsForJob(String jobOrderId) async {
    final response = await _client
        .from('service_cost')
        .select('*')
        .eq('job_order_id', jobOrderId)
        .order('created_at', ascending: false);
    return _rows(response);
  }
  Future<List<Map<String, dynamic>>> fetchServiceCosts({
    List<String>? jobOrderIds,
    String? vendorId,
  }) async {
    var query = _client.from('service_cost').select('*');

    if (_s(vendorId).isNotEmpty) {
      query = query.eq('vendor_id', vendorId!.trim());
    }

    if (jobOrderIds != null) {
      final ids = jobOrderIds.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      if (ids.isEmpty) return const [];
      query = query.inFilter('job_order_id', ids);
    }

    final response = await query.order('created_at', ascending: false);
    return _rows(response);
  }

  Future<List<Map<String, dynamic>>> fetchServicePayments({
    List<String>? jobOrderIds,
    String? jobOrderId,
    String? serviceCostId,
    String? vendorId,
    String? leaserId,
  }) async {
    var query = _client.from('service_job_payment').select('*');

    if (_s(vendorId).isNotEmpty) {
      query = query.eq('vendor_id', vendorId!.trim());
    }
    if (_s(leaserId).isNotEmpty) {
      query = query.eq('leaser_id', leaserId!.trim());
    }
    if (_s(serviceCostId).isNotEmpty) {
      query = query.eq('service_cost_id', serviceCostId!.trim());
    }
    if (_s(jobOrderId).isNotEmpty) {
      query = query.eq('job_order_id', jobOrderId!.trim());
    }

    if (jobOrderIds != null) {
      final ids = jobOrderIds.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      if (ids.isEmpty) return const [];
      query = query.inFilter('job_order_id', ids);
    }

    final response = await query.order('paid_at', ascending: false);
    return _rows(response);
  }

  Future<void> createServicePayment({
    required String serviceCostId,
    required String jobOrderId,
    required String leaserId,
    required String vendorId,
    required double amountPaid,
    required String paymentMethod,
    required String paymentReference,
    String? notes,
  }) async {
    final cleanServiceCostId = serviceCostId.trim();
    final cleanJobOrderId = jobOrderId.trim();
    final cleanLeaserId = leaserId.trim();
    final cleanVendorId = vendorId.trim();
    final cleanPaymentMethod = paymentMethod.trim();
    final cleanPaymentReference = paymentReference.trim();
    final user = _client.auth.currentUser;
    final actor = _s(user?.email).isEmpty ? _s(user?.id) : _s(user?.email);

    await _client.from('service_job_payment').insert({
      'service_payment_id': newId('SPM'),
      'service_cost_id': cleanServiceCostId,
      'job_order_id': cleanJobOrderId,
      'leaser_id': cleanLeaserId,
      'vendor_id': cleanVendorId,
      'amount_paid': amountPaid,
      'payment_method': cleanPaymentMethod,
      'payment_reference': cleanPaymentReference,
      'payment_status': 'Paid',
      'notes': _s(notes).isEmpty ? null : _s(notes),
      'paid_at': DateTime.now().toUtc().toIso8601String(),
    });

    await _client
        .from('service_cost')
        .update({
      'payment_status': 'Paid',
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    })
        .eq('service_cost_id', cleanServiceCostId);

    await addJobActivity(
      jobOrderId: cleanJobOrderId,
      activityType: 'payment_received',
      title: 'Service payment completed',
      detail: 'Leaser paid RM ${amountPaid.toStringAsFixed(2)} via $cleanPaymentMethod.',
      actorName: actor,
    );
  }

  Future<void> updateVendorProfile({
    required String vendorId,
    required String vendorName,
    required String serviceCategory,
    required String contactPerson,
    required String phone,
    required String email,
    required String address,
    required String pricingStructure,
  }) async {
    final cleanVendorId = vendorId.trim();
    final vendor = await _client
        .from('vendor')
        .select('user_id')
        .eq('vendor_id', cleanVendorId)
        .maybeSingle();

    await _client
        .from('vendor')
        .update({
      'vendor_name': vendorName.trim(),
      'service_category': serviceCategory.trim(),
      'contact_person': contactPerson.trim(),
      'vendor_phone': phone.trim(),
      'vendor_email': email.trim(),
      'vendor_address': address.trim(),
      'pricing_structure': pricingStructure.trim(),
    })
        .eq('vendor_id', cleanVendorId);

    final userId = vendor == null ? '' : _s((vendor as Map)['user_id']);
    if (userId.isNotEmpty) {
      try {
        await _client
            .from('app_user')
            .update({
          'user_name': vendorName.trim(),
          'user_phone': phone.trim(),
        })
            .eq('user_id', userId);
      } catch (_) {}
    }
  }

  Future<bool> canVendorCompleteJob(String jobOrderId) async {
    final costs = await fetchServiceCostsForJob(jobOrderId);
    if (costs.isEmpty) return false;
    return costs.every((row) => _s(row['payment_status']).toLowerCase() == 'paid');
  }

  Future<List<Map<String, dynamic>>> fetchJobAttachments(String jobOrderId) async {
    final response = await _client
        .from('service_job_attachment')
        .select('*')
        .eq('job_order_id', jobOrderId)
        .order('created_at', ascending: false);
    return _rows(response);
  }

  Future<List<Map<String, dynamic>>> fetchJobActivities(String jobOrderId) async {
    final response = await _client
        .from('service_job_activity')
        .select('*')
        .eq('job_order_id', jobOrderId)
        .order('created_at', ascending: false);
    return _rows(response);
  }

  Future<void> addJobActivity({
    required String jobOrderId,
    required String activityType,
    required String title,
    String? detail,
    String? fromStatus,
    String? toStatus,
    String? actorName,
  }) async {
    await _client.from('service_job_activity').insert({
      'activity_id': newId('ACT'),
      'job_order_id': jobOrderId,
      'activity_type': activityType.trim(),
      'from_status': _s(fromStatus).isEmpty ? null : _s(fromStatus),
      'to_status': _s(toStatus).isEmpty ? null : _s(toStatus),
      'title': title.trim(),
      'detail': _s(detail).isEmpty ? null : _s(detail),
      'actor_name': _s(actorName).isEmpty ? null : _s(actorName),
    });
  }

  Future<String> createJobOrder({
    required String vehicleId,
    required String jobType,
    required String priority,
    required String problemDescription,
    required String vendorId,
    DateTime? preferredDate,
    double estimatedCost = 0,
    Uint8List? attachmentBytes,
    String? attachmentName,
  }) async {
    final id = newId('JOB');
    final cleanVehicleId = vehicleId.trim();
    final cleanVendorId = vendorId.trim();
    final cleanJobType = jobType.trim();
    final user = _client.auth.currentUser;

    if (preferredDate != null) {
      final dateKey = _date(preferredDate);
      final existing = await _client
          .from('service_job_order')
          .select('job_order_id, status, preferred_date')
          .eq('vehicle_id', cleanVehicleId)
          .eq('preferred_date', dateKey);
      final conflicts = _rows(existing)
          .where((row) => _s(row['status']).toLowerCase() != 'cancelled')
          .toList();
      if (conflicts.isNotEmpty) {
        throw Exception(
          'This vehicle already has a job order on ${preferredDate.day}/${preferredDate.month}/${preferredDate.year}. Please choose another service date.',
        );
      }
    }

    final actor = _s(user?.email).isEmpty ? _s(user?.id) : _s(user?.email);
    final now = DateTime.now().toUtc().toIso8601String();

    final jobPayload = <String, dynamic>{
      'job_order_id': id,
      'vehicle_id': cleanVehicleId,
      'vendor_id': cleanVendorId,
      'job_type': cleanJobType,
      'priority': priority.trim(),
      'problem_description': problemDescription.trim(),
      'preferred_date': preferredDate == null ? null : _date(preferredDate),
      'status': 'Pending',
      'estimated_cost': estimatedCost,
      'actual_cost': 0,
      'requested_by': actor.isEmpty ? null : actor,
      'assigned_at': now,
      'updated_at': now,
    };

    await _client.from('service_job_order').insert(jobPayload);

    await addJobActivity(
      jobOrderId: id,
      activityType: 'created',
      title: 'Job created',
      detail: 'New $cleanJobType request created.',
      toStatus: 'Pending',
      actorName: actor,
    );

    final vendor = await _client
        .from('vendor')
        .select('vendor_name, service_category')
        .eq('vendor_id', cleanVendorId)
        .maybeSingle();
    final vendorMap = vendor == null ? null : Map<String, dynamic>.from(vendor as Map);
    await addJobActivity(
      jobOrderId: id,
      activityType: 'vendor_assigned',
      title: 'Vendor assigned',
      detail: 'Assigned to ${vendorLabel(vendorMap)}.',
      actorName: actor,
    );

    await _setVehicleUnderService(cleanVehicleId);
    await _syncMaintenanceScheduleForJob(jobPayload);

    if (attachmentBytes != null && attachmentBytes.isNotEmpty) {
      await uploadAttachment(
        jobOrderId: id,
        bytes: attachmentBytes,
        fileName: attachmentName ?? 'attachment',
        uploadedBy: actor,
      );
    }

    return id;
  }

  Future<void> assignVendor({
    required String jobOrderId,
    required String vendorId,
  }) async {
    final user = _client.auth.currentUser;
    final actor = _s(user?.email).isEmpty ? _s(user?.id) : _s(user?.email);
    final vendor = await _client
        .from('vendor')
        .select('*')
        .eq('vendor_id', vendorId)
        .maybeSingle();
    final vendorMap = vendor == null ? null : Map<String, dynamic>.from(vendor as Map);

    await _client.from('service_job_order').update({
      'vendor_id': vendorId.trim(),
      'assigned_at': DateTime.now().toUtc().toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('job_order_id', jobOrderId);

    await addJobActivity(
      jobOrderId: jobOrderId,
      activityType: 'vendor_assigned',
      title: 'Vendor assigned',
      detail: 'Assigned to ${vendorLabel(vendorMap)}.',
      actorName: actor,
    );

    final updatedJob = await fetchJobOrder(jobOrderId);
    if (updatedJob != null) {
      await _syncMaintenanceScheduleForJob(updatedJob);
    }
  }

  Future<void> updateJobStatus({
    required String jobOrderId,
    required String currentStatus,
    required String newStatus,
    required String remarks,
  }) async {
    final user = _client.auth.currentUser;
    final actor = _s(user?.email).isEmpty ? _s(user?.id) : _s(user?.email);
    final job = await fetchJobOrder(jobOrderId);
    final payload = <String, dynamic>{
      'status': newStatus.trim(),
      'remarks': remarks.trim(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    if (newStatus.trim().toLowerCase() == 'completed' || newStatus.trim().toLowerCase() == 'cancelled') {
      payload['closed_at'] = DateTime.now().toUtc().toIso8601String();
    } else {
      payload['closed_at'] = null;
    }

    await _client.from('service_job_order').update(payload).eq('job_order_id', jobOrderId);

    await addJobActivity(
      jobOrderId: jobOrderId,
      activityType: 'status_updated',
      title: 'Status updated',
      detail: remarks.trim(),
      fromStatus: currentStatus.trim(),
      toStatus: newStatus.trim(),
      actorName: actor,
    );

    final updatedJob = {
      if (job != null) ...job,
      'job_order_id': jobOrderId,
      'status': newStatus.trim(),
      'remarks': remarks.trim(),
      'closed_at': payload['closed_at'],
    };

    final vehicleId = _s(updatedJob['vehicle_id']);
    final normalizedStatus = newStatus.trim().toLowerCase();
    if (vehicleId.isNotEmpty) {
      if (normalizedStatus == 'pending' || normalizedStatus == 'in progress') {
        await _setVehicleUnderService(vehicleId);
      } else {
        await _restoreVehicleAvailabilityIfPossible(vehicleId);
      }
    }

    await _syncMaintenanceScheduleForJob(updatedJob);
  }

  Future<void> deleteJobOrder(String jobOrderId) async {
    final cleanJobOrderId = jobOrderId.trim();
    if (cleanJobOrderId.isEmpty) return;

    final job = await fetchJobOrder(cleanJobOrderId);
    final vehicleId = _s(job?['vehicle_id']);

    try {
      final attachments = await fetchJobAttachments(cleanJobOrderId);
      for (final attachment in attachments) {
        final path = _s(attachment['file_path']);
        if (path.isEmpty) continue;
        try {
          await _client.storage.from(attachmentBucket).remove([path]);
        } catch (_) {}
      }
    } catch (_) {}

    try {
      await _client
          .from('maintenance_schedule')
          .delete()
          .eq('schedule_id', _maintenanceScheduleId(cleanJobOrderId));
    } catch (_) {}

    await _client
        .from('service_job_order')
        .delete()
        .eq('job_order_id', cleanJobOrderId);

    if (vehicleId.isNotEmpty) {
      await _restoreVehicleAvailabilityIfPossible(vehicleId);
    }
  }

  Future<Map<String, dynamic>> uploadAttachment({
    required String jobOrderId,
    required Uint8List bytes,
    required String fileName,
    String? uploadedBy,
  }) async {
    final safeName = _safeFileName(fileName);
    final path = 'job-orders/$jobOrderId/${DateTime.now().millisecondsSinceEpoch}_$safeName';

    await _client.storage.from(attachmentBucket).uploadBinary(
      path,
      bytes,
      fileOptions: FileOptions(
        contentType: _contentTypeForFile(fileName),
        upsert: true,
      ),
    );

    final record = <String, dynamic>{
      'attachment_id': newId('ATT'),
      'job_order_id': jobOrderId,
      'file_name': safeName,
      'file_path': path,
      'file_type': _fileExtension(fileName),
      'file_size_kb': (bytes.length / 1024).ceil(),
      'uploaded_by': _s(uploadedBy).isEmpty ? null : _s(uploadedBy),
    };

    await _client.from('service_job_attachment').insert(record);

    await addJobActivity(
      jobOrderId: jobOrderId,
      activityType: 'attachment_uploaded',
      title: 'Attachment uploaded',
      detail: safeName,
      actorName: uploadedBy,
    );

    return record;
  }

  Future<String?> createSignedAttachmentUrl(String? path) async {
    final clean = _s(path);
    if (clean.isEmpty) return null;
    if (clean.startsWith('http://') || clean.startsWith('https://')) return clean;

    try {
      return await _client.storage.from(attachmentBucket).createSignedUrl(clean, 3600);
    } catch (_) {
      try {
        return _client.storage.from(attachmentBucket).getPublicUrl(clean);
      } catch (_) {
        return null;
      }
    }
  }

  double readDouble(Map<String, dynamic> row, String key) => _d(row[key]);

  int readInt(Map<String, dynamic> row, String key) => _i(row[key]);

  String explainError(Object error) {
    final message = error.toString();
    final lower = message.toLowerCase();

    if (lower.contains('service_job_attachment') ||
        lower.contains('service_job_activity') ||
        lower.contains('service_job_payment') ||
        lower.contains('requested_by') ||
        lower.contains('assigned_at') ||
        lower.contains('closed_at') ||
        lower.contains('job_order_files')) {
      if (lower.contains('service_job_payment')) {
        return 'The service job payment table is missing in Supabase. Run the SQL in supabase/service_job_payment_patch.sql, then try again.\n\n$message';
      }
      return 'Your Chapter 4 Job Order module is not fully added in Supabase yet. Run the SQL in supabase/job_order_chapter4_patch.sql, then try again.\n\n$message';
    }
    if (lower.contains('storage') || lower.contains('bucket')) {
      return 'The Job Order attachment bucket is not ready in Supabase yet. Run the SQL in supabase/job_order_chapter4_patch.sql, then try again.\n\n$message';
    }

    if (lower.contains('row-level security')) {
      return 'Supabase blocked this action with row-level security. Check your Storage or table policies for the Job Order module.\n\n$message';
    }

    return message;
  }
}









