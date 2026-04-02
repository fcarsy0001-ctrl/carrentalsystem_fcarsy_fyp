import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'leaser_vehicle_service.dart';
import 'road_tax_monitor_service.dart';

class VehicleOnboardingService {
  VehicleOnboardingService(this._client);

  final SupabaseClient _client;

  static const String assetBucket = 'vehicle_photos';

  static const String sqlPatch = '''
create table if not exists public.vehicle_onboarding (
  onboarding_id text primary key,
  vehicle_id character varying not null unique references public.vehicle(vehicle_id) on delete cascade,
  submitted_by text,
  submitted_at timestamp with time zone not null default now(),
  submitted_role text,
  review_status text not null default 'Pending Review',
  eligibility_status text not null default 'Pending',
  readiness_status text not null default 'Pending',
  readiness_notes text,
  review_remark text,
  inspection_date date,
  inspection_result text not null default 'Pending',
  supporting_docs_url text,
  remarks text,
  reviewed_by text,
  reviewed_at timestamp with time zone
);

alter table public.vehicle
  add column if not exists vehicle_year integer;

alter table public.vehicle
  add column if not exists mileage_km integer default 0;

alter table public.vehicle
  add column if not exists condition_status text default 'Pending';

alter table public.vehicle
  add column if not exists road_tax_expiry_date date;

alter table public.vehicle_onboarding
  add column if not exists submitted_role text;

alter table public.vehicle_onboarding
  add column if not exists readiness_status text default 'Pending';

alter table public.vehicle_onboarding
  add column if not exists inspection_date date;

alter table public.vehicle_onboarding
  add column if not exists inspection_result text default 'Pending';

alter table public.vehicle_onboarding
  add column if not exists supporting_docs_url text;

alter table public.vehicle_onboarding
  add column if not exists remarks text;
''';

  String _s(dynamic value) => value == null ? '' : value.toString().trim();

  int _i(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString()) ?? 0;
  }

  double _d(dynamic value) {
    if (value == null) return 0;
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0;
  }

  DateTime _mytToday() {
    final now = DateTime.now().toUtc().add(const Duration(hours: 8));
    return DateTime(now.year, now.month, now.day);
  }

  bool _isRoadTaxExpired(dynamic value) {
    final raw = _s(value);
    if (raw.isEmpty) return false;
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return false;
    final expiry = DateTime(parsed.year, parsed.month, parsed.day);
    return expiry.isBefore(_mytToday());
  }

  String _date(DateTime? value) {
    if (value == null) return '';
    final y = value.year.toString().padLeft(4, '0');
    final m = value.month.toString().padLeft(2, '0');
    final d = value.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  String _contentTypeForExt(String ext) {
    final v = ext.trim().toLowerCase();
    switch (v) {
      case 'png':
        return 'image/png';
      case 'pdf':
        return 'application/pdf';
      default:
        return 'image/jpeg';
    }
  }

  String _safeExt(String? ext, {String fallback = 'jpg'}) {
    final value = (ext ?? '').trim().toLowerCase();
    if (value == 'png' || value == 'pdf' || value == 'jpg' || value == 'jpeg') {
      return value == 'jpeg' ? 'jpg' : value;
    }
    return fallback;
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

  Future<List<String>> fetchLocations() async {
    try {
      final rows = await _client
          .from('vehicle_location')
          .select('location_name,is_active')
          .order('location_name', ascending: true);

      final output = <String>[];
      for (final row in _rows(rows)) {
        final active = row['is_active'] as bool? ?? true;
        final name = _s(row['location_name']);
        if (active && name.isNotEmpty) output.add(name);
      }
      return output;
    } catch (_) {
      return const [];
    }
  }

  Future<Map<String, Map<String, dynamic>>> _fetchOpenJobsByVehicleId() async {
    try {
      final jobs = _rows(
        await _client
            .from('service_job_order')
            .select('job_order_id, vehicle_id, job_type, status, preferred_date, vendor_id, created_at, updated_at')
            .inFilter('status', ['Pending', 'In Progress'])
            .order('updated_at', ascending: false),
      );

      final byVehicleId = <String, Map<String, dynamic>>{};
      for (final row in jobs) {
        final vehicleId = _s(row['vehicle_id']);
        if (vehicleId.isNotEmpty && !byVehicleId.containsKey(vehicleId)) {
          byVehicleId[vehicleId] = row;
        }
      }
      return byVehicleId;
    } catch (_) {
      return const {};
    }
  }
  Future<List<Map<String, dynamic>>> fetchVehicles({String? leaserId}) async {
    await RoadTaxMonitorService(_client)
        .syncRoadTaxStates(leaserId: leaserId)
        .catchError((_) {});

    final base = _client.from('vehicle').select('*');
    final query = _s(leaserId).isEmpty ? base : base.eq('leaser_id', leaserId!.trim());
    final vehicles = _rows(await query.order('vehicle_id', ascending: false));

    List<Map<String, dynamic>> onboarding = const [];
    try {
      onboarding = _rows(await _client.from('vehicle_onboarding').select('*'));
    } catch (_) {
      onboarding = const [];
    }

    final byVehicleId = <String, Map<String, dynamic>>{};
    for (final row in onboarding) {
      final id = _s(row['vehicle_id']);
      if (id.isNotEmpty) byVehicleId[id] = row;
    }

    final openJobsByVehicleId = await _fetchOpenJobsByVehicleId();

    return vehicles
        .map(
          (vehicle) => _mergeVehicleRecord(
        vehicle,
        byVehicleId[_s(vehicle['vehicle_id'])],
        openJobsByVehicleId[_s(vehicle['vehicle_id'])],
      ),
    )
        .toList();
  }
  Future<Map<String, dynamic>?> fetchVehicleDetail(String vehicleId) async {
    await RoadTaxMonitorService(_client).syncRoadTaxStates().catchError((_) {});

    final rows = _rows(await _client.from('vehicle').select('*').eq('vehicle_id', vehicleId).limit(1));
    if (rows.isEmpty) return null;

    Map<String, dynamic>? onboarding;
    try {
      final row = await _client
          .from('vehicle_onboarding')
          .select('*')
          .eq('vehicle_id', vehicleId)
          .maybeSingle();
      if (row != null) onboarding = Map<String, dynamic>.from(row as Map);
    } catch (_) {}

    Map<String, dynamic>? activeJob;
    try {
      final row = await _client
          .from('service_job_order')
          .select('job_order_id, vehicle_id, job_type, status, preferred_date, vendor_id, created_at, updated_at')
          .eq('vehicle_id', vehicleId)
          .inFilter('status', ['Pending', 'In Progress'])
          .order('updated_at', ascending: false)
          .limit(1)
          .maybeSingle();
      if (row != null) activeJob = Map<String, dynamic>.from(row as Map);
    } catch (_) {}

    return _mergeVehicleRecord(rows.first, onboarding, activeJob);
  }
  Future<String?> createSignedAssetUrl(String? path) async {
    final clean = _s(path);
    if (clean.isEmpty) return null;
    if (clean.startsWith('http://') || clean.startsWith('https://')) return clean;

    try {
      return await _client.storage.from(assetBucket).createSignedUrl(clean, 3600);
    } catch (_) {
      try {
        return _client.storage.from(assetBucket).getPublicUrl(clean);
      } catch (_) {
        return null;
      }
    }
  }

  Future<String?> uploadAsset({
    required String vehicleId,
    required String folder,
    required Uint8List bytes,
    required String extension,
  }) async {
    if (bytes.isEmpty) return null;
    final ext = _safeExt(extension);
    final path = '$folder/$vehicleId-${DateTime.now().millisecondsSinceEpoch}.$ext';
    await _client.storage.from(assetBucket).uploadBinary(
      path,
      bytes,
      fileOptions: FileOptions(
        contentType: _contentTypeForExt(ext),
        upsert: true,
      ),
    );
    return path;
  }

  Map<String, dynamic> evaluateVehicle({
    required int vehicleYear,
    required int mileageKm,
    required String conditionStatus,
    required bool hasVehiclePhoto,
    required bool hasSupportingDocs,
    DateTime? roadTaxExpiryDate,
    String? storedEligibilityStatus,
    String? storedReadinessStatus,
    String? storedReviewStatus,
    String? storedInspectionResult,
  }) {
    final currentYear = DateTime.now().year;
    final ageYears = vehicleYear <= 0 ? -1 : currentYear - vehicleYear;
    final agePass = vehicleYear > 0 && ageYears <= 5;
    final mileagePass = mileageKm >= 0 && mileageKm <= 100000;

    final condition = conditionStatus.trim().toLowerCase();
    final physicalPass = condition == 'excellent' || condition == 'good';
    final docsPass = hasVehiclePhoto && hasSupportingDocs;
    final now = DateTime.now();
    final minRoadTaxExpiryDate = DateTime(now.year, now.month + 2, now.day);
    final normalizedRoadTaxExpiryDate = roadTaxExpiryDate == null
        ? null
        : DateTime(roadTaxExpiryDate.year, roadTaxExpiryDate.month, roadTaxExpiryDate.day);
    final roadTaxPass = normalizedRoadTaxExpiryDate != null &&
        !normalizedRoadTaxExpiryDate.isBefore(minRoadTaxExpiryDate);

    final passedCount = [agePass, mileagePass, physicalPass, docsPass, roadTaxPass].where((v) => v).length;

    final reviewStatus = _s(storedReviewStatus).isEmpty ? 'Pending Review' : _s(storedReviewStatus);
    final computedEligibility = passedCount == 5 ? 'Eligible' : 'Pending';
    final eligibilityStatus = _s(storedEligibilityStatus).isEmpty ? computedEligibility : _s(storedEligibilityStatus);

    final computedInspectionResult = passedCount == 5 ? 'Pass' : 'Pending';
    final inspectionResult = _s(storedInspectionResult).isEmpty
        ? computedInspectionResult
        : _s(storedInspectionResult);

    final computedReadiness = reviewStatus == 'Approved'
        ? 'Ready'
        : reviewStatus == 'Rejected'
        ? 'Rejected'
        : 'Pending';
    final readinessStatus = _s(storedReadinessStatus).isEmpty
        ? computedReadiness
        : _s(storedReadinessStatus);

    return {
      'age_years': ageYears,
      'age_passed': agePass,
      'mileage_passed': mileagePass,
      'physical_passed': physicalPass,
      'docs_passed': docsPass,
      'road_tax_passed': roadTaxPass,
      'road_tax_min_expiry_date': _date(minRoadTaxExpiryDate),
      'road_tax_expiry_date': _date(normalizedRoadTaxExpiryDate),
      'passed_checks': passedCount,
      'eligibility_status': eligibilityStatus,
      'readiness_status': readinessStatus,
      'review_status': reviewStatus,
      'inspection_result': inspectionResult,
      'overall_passed': passedCount == 5,
    };
  }

  Future<Map<String, dynamic>> saveVehicle({
    required bool isAdminMode,
    String? existingVehicleId,
    required String leaserId,
    required String brand,
    required String model,
    required String plateNo,
    required String vehicleType,
    required String transmissionType,
    required String fuelType,
    required int vehicleYear,
    required int mileageKm,
    required int seatCapacity,
    required double dailyRate,
    required String location,
    required String conditionStatus,
    DateTime? roadTaxExpiryDate,
    required String description,
    required String remarks,
    Uint8List? photoBytes,
    String? photoExtension,
    Uint8List? docsBytes,
    String? docsExtension,
    String? existingPhotoPath,
    String? existingDocsPath,
    String? existingVehicleStatus,
    String? existingReviewStatus,
    String? existingEligibilityStatus,
    String? existingReadinessStatus,
    String? existingInspectionResult,
    String? existingReadinessNotes,
  }) async {
    final vehicleId = _s(existingVehicleId).isEmpty ? newId('V') : _s(existingVehicleId);
    final hasNewPhoto = photoBytes != null && photoBytes.isNotEmpty;
    final hasNewDocs = docsBytes != null && docsBytes.isNotEmpty;

    var photoPath = _s(existingPhotoPath);
    var docsPath = _s(existingDocsPath);

    if (hasNewPhoto) {
      photoPath = await uploadAsset(
        vehicleId: vehicleId,
        folder: 'vehicles',
        bytes: photoBytes!,
        extension: _safeExt(photoExtension),
      ) ??
          photoPath;
    }

    if (hasNewDocs) {
      docsPath = await uploadAsset(
        vehicleId: vehicleId,
        folder: 'vehicle-documents',
        bytes: docsBytes!,
        extension: _safeExt(docsExtension, fallback: 'pdf'),
      ) ??
          docsPath;
    }

    final evaluation = evaluateVehicle(
      vehicleYear: vehicleYear,
      mileageKm: mileageKm,
      conditionStatus: conditionStatus,
      hasVehiclePhoto: photoPath.isNotEmpty,
      hasSupportingDocs: docsPath.isNotEmpty,
      roadTaxExpiryDate: roadTaxExpiryDate,
    );

    final vehiclePayload = <String, dynamic>{
      'leaser_id': leaserId.trim(),
      'vehicle_brand': brand.trim(),
      'vehicle_model': model.trim(),
      'vehicle_plate_no': plateNo.trim(),
      'vehicle_type': vehicleType.trim(),
      'transmission_type': transmissionType.trim(),
      'fuel_type': fuelType.trim(),
      'seat_capacity': seatCapacity,
      'daily_rate': dailyRate,
      'vehicle_location': location.trim(),
      'vehicle_description': description.trim().isEmpty ? null : description.trim(),
      'vehicle_status': _s(existingVehicleStatus).isEmpty ? 'Pending' : _s(existingVehicleStatus),
      'vehicle_year': vehicleYear,
      'mileage_km': mileageKm,
      'condition_status': conditionStatus.trim(),
      'road_tax_expiry_date': roadTaxExpiryDate == null ? null : _date(roadTaxExpiryDate),
    };
    if (photoPath.isNotEmpty) {
      vehiclePayload['vehicle_photo_path'] = photoPath;
    }

    if (_s(existingVehicleId).isEmpty) {
      if (isAdminMode) {
        await _client.from('vehicle').insert({'vehicle_id': vehicleId, ...vehiclePayload});
      } else {
        try {
          await LeaserVehicleService(_client).upsertVehicle(
            isEdit: false,
            vehicleId: vehicleId,
            payload: vehiclePayload,
          );
        } catch (_) {
          await _client.from('vehicle').insert({'vehicle_id': vehicleId, ...vehiclePayload});
        }
      }
    } else {
      if (isAdminMode) {
        await _client.from('vehicle').update(vehiclePayload).eq('vehicle_id', vehicleId);
      } else {
        try {
          await LeaserVehicleService(_client).upsertVehicle(
            isEdit: true,
            vehicleId: vehicleId,
            payload: vehiclePayload,
          );
        } catch (_) {
          await _client.from('vehicle').update(vehiclePayload).eq('vehicle_id', vehicleId);
        }
      }
    }

    final user = _client.auth.currentUser;
    final preserveReviewState = _s(existingVehicleId).isNotEmpty && isAdminMode;
    final onboardingPayload = <String, dynamic>{
      'onboarding_id': newId('ONB'),
      'vehicle_id': vehicleId,
      'submitted_by': (user?.email ?? user?.id ?? '').trim(),
      'submitted_role': isAdminMode ? 'Administrator' : 'Leaser',
      'review_status': preserveReviewState && _s(existingReviewStatus).isNotEmpty ? _s(existingReviewStatus) : 'Pending Review',
      'eligibility_status': preserveReviewState && _s(existingEligibilityStatus).isNotEmpty ? _s(existingEligibilityStatus) : evaluation['eligibility_status'],
      'readiness_status': preserveReviewState && _s(existingReadinessStatus).isNotEmpty ? _s(existingReadinessStatus) : evaluation['readiness_status'],
      'readiness_notes': preserveReviewState && _s(existingReadinessNotes).isNotEmpty
          ? _s(existingReadinessNotes)
          : evaluation['overall_passed'] == true
          ? 'Basic validation passed. Waiting for admin review.'
          : 'Basic validation still needs admin review.',
      'inspection_result': preserveReviewState && _s(existingInspectionResult).isNotEmpty ? _s(existingInspectionResult) : evaluation['inspection_result'],
      'supporting_docs_url': docsPath.isEmpty ? null : docsPath,
      'remarks': remarks.trim().isEmpty ? null : remarks.trim(),
    };

    final existing = await _client
        .from('vehicle_onboarding')
        .select('onboarding_id')
        .eq('vehicle_id', vehicleId)
        .maybeSingle();

    if (existing == null) {
      await _client.from('vehicle_onboarding').insert(onboardingPayload);
    } else {
      await _client.from('vehicle_onboarding').update({
        'submitted_by': onboardingPayload['submitted_by'],
        'submitted_role': onboardingPayload['submitted_role'],
        'review_status': onboardingPayload['review_status'],
        'eligibility_status': onboardingPayload['eligibility_status'],
        'readiness_status': onboardingPayload['readiness_status'],
        'readiness_notes': onboardingPayload['readiness_notes'],
        'inspection_result': onboardingPayload['inspection_result'],
        'supporting_docs_url': onboardingPayload['supporting_docs_url'],
        'remarks': onboardingPayload['remarks'],
      }).eq('vehicle_id', vehicleId);
    }

    final detail = await fetchVehicleDetail(vehicleId);
    if (detail == null) throw Exception('Vehicle saved but could not be reloaded.');
    return detail;
  }

  Future<Map<String, dynamic>> updateEligibilityReview({
    required String vehicleId,
    required String reviewStatus,
    required String eligibilityStatus,
    required String readinessStatus,
    required String conditionStatus,
    required String inspectionResult,
    DateTime? inspectionDate,
    required String reviewRemark,
    required String readinessNotes,
  }) async {
    final user = _client.auth.currentUser;
    final vehicleStatus = reviewStatus == 'Approved'
        ? 'Available'
        : reviewStatus == 'Rejected'
        ? 'Unavail'
        : 'Pending';

    await _client.from('vehicle').update({
      'condition_status': conditionStatus.trim(),
      'vehicle_status': vehicleStatus,
    }).eq('vehicle_id', vehicleId);

    final existing = await _client
        .from('vehicle_onboarding')
        .select('onboarding_id')
        .eq('vehicle_id', vehicleId)
        .maybeSingle();

    final payload = <String, dynamic>{
      'vehicle_id': vehicleId,
      'submitted_by': (user?.email ?? user?.id ?? '').trim(),
      'submitted_role': 'Administrator',
      'review_status': reviewStatus.trim(),
      'eligibility_status': eligibilityStatus.trim(),
      'readiness_status': readinessStatus.trim(),
      'readiness_notes': readinessNotes.trim().isEmpty ? null : readinessNotes.trim(),
      'review_remark': reviewRemark.trim().isEmpty ? null : reviewRemark.trim(),
      'inspection_date': inspectionDate == null ? null : _date(inspectionDate),
      'inspection_result': inspectionResult.trim(),
      'reviewed_by': (user?.email ?? user?.id ?? '').trim(),
      'reviewed_at': DateTime.now().toUtc().toIso8601String(),
    };

    if (existing == null) {
      await _client.from('vehicle_onboarding').insert({
        'onboarding_id': newId('ONB'),
        ...payload,
      });
    } else {
      await _client.from('vehicle_onboarding').update(payload).eq('vehicle_id', vehicleId);
    }

    final detail = await fetchVehicleDetail(vehicleId);
    if (detail == null) throw Exception('Vehicle review saved but could not be reloaded.');
    return detail;
  }

  String explainError(Object error) {
    final message = error.toString();
    final lower = message.toLowerCase();
    if (lower.contains('vehicle_year') ||
        lower.contains('mileage_km') ||
        lower.contains('condition_status') ||
        lower.contains('road_tax_expiry_date') ||
        lower.contains('vehicle_onboarding') ||
        lower.contains('supporting_docs_url') ||
        lower.contains('inspection_result')) {
      return 'Your Chapter 4 onboarding fields are not fully added in Supabase yet. Run the SQL patch from vehicle_onboarding_service.dart or the updated SQL file, then try again.\n\n$message';
    }
    if (lower.contains('row-level security')) {
      return 'Supabase blocked this action with row-level security. If this happens in leaser mode, make sure your vehicle write flow or policy also allows vehicle_onboarding updates.\n\n$message';
    }
    return message;
  }

  String buildEligibilityReport(Map<String, dynamic> row) {
    final plate = _s(row['vehicle_plate_no']);
    final brand = _s(row['vehicle_brand']);
    final model = _s(row['vehicle_model']);
    final year = _i(row['vehicle_year']);
    final mileage = _i(row['mileage_km']);
    final condition = _s(row['condition_status']);
    final eligibility = _s(row['eligibility_status']);
    final readiness = _s(row['readiness_status']);
    final review = _s(row['review_status']);
    final inspectionResult = _s(row['inspection_result']);
    final inspectionDate = _s(row['inspection_date']);
    final roadTaxExpiryDate = _s(row['road_tax_expiry_date']);
    final roadTaxPassed = row['road_tax_passed'] == true;
    final roadTaxMinExpiryDate = _s(row['road_tax_min_expiry_date']);
    final notes = _s(row['readiness_notes']);
    final remark = _s(row['review_remark']);

    return '''
Vehicle Eligibility Report
Plate Number: ${plate.isEmpty ? '-' : plate}
Vehicle: ${'$brand $model'.trim()}
Year: ${year <= 0 ? '-' : year}
Mileage: ${mileage <= 0 ? '-' : '$mileage km'}
Condition: ${condition.isEmpty ? '-' : condition}
Eligibility Status: ${eligibility.isEmpty ? '-' : eligibility}
Readiness Status: ${readiness.isEmpty ? '-' : readiness}
Review Status: ${review.isEmpty ? '-' : review}
Inspection Result: ${inspectionResult.isEmpty ? '-' : inspectionResult}
Inspection Date: ${inspectionDate.isEmpty ? '-' : inspectionDate}
Road Tax Expiry Date: ${roadTaxExpiryDate.isEmpty ? '-' : roadTaxExpiryDate}
Road Tax Requirement: ${roadTaxMinExpiryDate.isEmpty ? 'At least 2 more months validity remaining' : 'On or after ' + roadTaxMinExpiryDate}
Road Tax Check: ${roadTaxPassed ? 'Pass' : 'Fail'}
Readiness Notes: ${notes.isEmpty ? '-' : notes}
Review Remark: ${remark.isEmpty ? '-' : remark}
''';
  }

  Map<String, dynamic> _mergeVehicleRecord(
      Map<String, dynamic> vehicle,
      Map<String, dynamic>? onboarding,
      Map<String, dynamic>? activeJob,
      ) {
    final base = Map<String, dynamic>.from(vehicle);
    final extra = onboarding == null ? <String, dynamic>{} : Map<String, dynamic>.from(onboarding);
    final job = activeJob == null ? <String, dynamic>{} : Map<String, dynamic>.from(activeJob);
    final hasOpenJob = job.isNotEmpty;
    final roadTaxExpired = _isRoadTaxExpired(base['road_tax_expiry_date']);
    final baseVehicleStatus = _s(base['vehicle_status']).isEmpty ? 'Pending' : _s(base['vehicle_status']);
    final mergedVehicleStatus = roadTaxExpired
        ? 'Inactive'
        : hasOpenJob && baseVehicleStatus.toLowerCase() != 'inactive'
            ? 'Maintenance'
            : baseVehicleStatus;
    final serviceLockReason = roadTaxExpired
        ? 'Blocked from rental because road tax expired on ${_s(base['road_tax_expiry_date'])}.'
        : hasOpenJob
            ? 'Blocked from rental because job order ${_s(job['job_order_id'])} is ${_s(job['status']).isEmpty ? 'Pending' : _s(job['status'])}.'
            : '';

    final evaluation = evaluateVehicle(
      vehicleYear: _i(base['vehicle_year']),
      mileageKm: _i(base['mileage_km']),
      conditionStatus: _s(base['condition_status']).isEmpty ? 'Pending' : _s(base['condition_status']),
      hasVehiclePhoto: _s(base['vehicle_photo_path']).isNotEmpty,
      hasSupportingDocs: _s(extra['supporting_docs_url']).isNotEmpty,
      roadTaxExpiryDate: DateTime.tryParse(_s(base['road_tax_expiry_date'])),
      storedEligibilityStatus: extra['eligibility_status']?.toString(),
      storedReadinessStatus: extra['readiness_status']?.toString(),
      storedReviewStatus: extra['review_status']?.toString(),
      storedInspectionResult: extra['inspection_result']?.toString(),
    );

    return {
      ...base,
      ...extra,
      ...evaluation,
      'vehicle_year': _i(base['vehicle_year']),
      'mileage_km': _i(base['mileage_km']),
      'daily_rate': _d(base['daily_rate']),
      'condition_status': _s(base['condition_status']).isEmpty ? 'Pending' : _s(base['condition_status']),
      'road_tax_expiry_date': _s(base['road_tax_expiry_date']),
      'remarks': _s(extra['remarks']),
      'review_remark': _s(extra['review_remark']),
      'base_vehicle_status': baseVehicleStatus,
      'vehicle_status': mergedVehicleStatus,
      'has_open_job_order': hasOpenJob,
      'active_job_order_id': _s(job['job_order_id']),
      'active_job_status': _s(job['status']),
      'active_job_type': _s(job['job_type']),
      'active_job_preferred_date': _s(job['preferred_date']),
      'service_lock_reason': serviceLockReason,
      'road_tax_expired': roadTaxExpired,
    };
  }
}














