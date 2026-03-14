import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

class JobOrderModuleService {
  JobOrderModuleService(this._client);

  final SupabaseClient _client;

  static const String attachmentBucket = 'job_order_files';
  static const String sqlPatchFile = 'supabase/job_order_chapter4_patch.sql';
  static const String setupHint = 'Run the SQL in supabase/job_order_chapter4_patch.sql to create the Job Order tables, activity log, and attachment bucket.';

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

  Future<List<Map<String, dynamic>>> fetchVehicles() async {
    final response = await _client
        .from('vehicle')
        .select('vehicle_id, vehicle_brand, vehicle_model, vehicle_plate_no, vehicle_year, mileage_km, vehicle_location, vehicle_status, leaser_id')
        .order('vehicle_plate_no', ascending: true);
    return _rows(response);
  }

  Future<List<Map<String, dynamic>>> fetchVendors() async {
    final response = await _client
        .from('vendor')
        .select('*')
        .order('vendor_name', ascending: true);
    return _rows(response);
  }

  Future<List<Map<String, dynamic>>> fetchJobOrders() async {
    final response = await _client
        .from('service_job_order')
        .select('*')
        .order('created_at', ascending: false);
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
    final user = _client.auth.currentUser;
    final actor = _s(user?.email).isEmpty ? _s(user?.id) : _s(user?.email);
    final now = DateTime.now().toUtc().toIso8601String();

    await _client.from('service_job_order').insert({
      'job_order_id': id,
      'vehicle_id': vehicleId.trim(),
      'vendor_id': vendorId.trim(),
      'job_type': jobType.trim(),
      'priority': priority.trim(),
      'problem_description': problemDescription.trim(),
      'preferred_date': preferredDate == null ? null : _date(preferredDate),
      'status': 'Pending',
      'estimated_cost': estimatedCost,
      'actual_cost': 0,
      'requested_by': actor.isEmpty ? null : actor,
      'assigned_at': now,
      'updated_at': now,
    });

    await addJobActivity(
      jobOrderId: id,
      activityType: 'created',
      title: 'Job created',
      detail: 'New $jobType request created.',
      toStatus: 'Pending',
      actorName: actor,
    );

    final vendor = await _client
        .from('vendor')
        .select('vendor_name, service_category')
        .eq('vendor_id', vendorId)
        .maybeSingle();
    final vendorMap = vendor == null ? null : Map<String, dynamic>.from(vendor as Map);
    await addJobActivity(
      jobOrderId: id,
      activityType: 'vendor_assigned',
      title: 'Vendor assigned',
      detail: 'Assigned to ${vendorLabel(vendorMap)}.',
      actorName: actor,
    );

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
  }

  Future<void> updateJobStatus({
    required String jobOrderId,
    required String currentStatus,
    required String newStatus,
    required String remarks,
  }) async {
    final user = _client.auth.currentUser;
    final actor = _s(user?.email).isEmpty ? _s(user?.id) : _s(user?.email);
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
        lower.contains('requested_by') ||
        lower.contains('assigned_at') ||
        lower.contains('closed_at') ||
        lower.contains('job_order_files')) {
      return 'Your Chapter 4 Job Order module is not fully added in Supabase yet. Run the SQL patch from job_order_module_service.dart or the SQL file in the supabase folder, then try again.\n\n$message';
    }

    if (lower.contains('storage') || lower.contains('bucket')) {
      return 'The Job Order attachment bucket is not ready in Supabase yet. Run the Job Order SQL patch, then try again.\n\n$message';
    }

    if (lower.contains('row-level security')) {
      return 'Supabase blocked this action with row-level security. Check your Storage or table policies for the Job Order module.\n\n$message';
    }

    return message;
  }
}
