import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum DriverLicenseState { notSubmitted, pending, approved, rejected, unknown }

class DriverLicenseSnapshot {
  const DriverLicenseSnapshot({
    required this.state,
    this.licenseNo,
    this.licenseName,
    this.expiry,
    this.photoPath,
    this.statusRaw,
    this.rejectRemark,
  });

  final DriverLicenseState state;
  final String? licenseNo;
  final String? licenseName;
  final DateTime? expiry;
  final String? photoPath;

  /// Raw database value, if any (useful for debugging).
  final String? statusRaw;

  /// Optional remark set by admin on rejection.
  final String? rejectRemark;

  bool get isApproved => state == DriverLicenseState.approved;

  static DriverLicenseState parseStatus(String? raw) {
    final v = (raw ?? '').trim().toLowerCase();
    if (v.isEmpty || v == 'not submitted' || v == 'not_submitted') {
      return DriverLicenseState.notSubmitted;
    }
    if (v == 'pending' || v == 'under review' || v == 'in review') {
      return DriverLicenseState.pending;
    }
    if (v == 'approved' || v == 'verified') {
      return DriverLicenseState.approved;
    }
    if (v == 'rejected' || v == 'declined') {
      return DriverLicenseState.rejected;
    }
    return DriverLicenseState.unknown;
  }
}

class DriverLicenseService {
  DriverLicenseService(this._client);

  final SupabaseClient _client;

  static const String bucketId = 'driver_licenses';

  Future<Map<String, dynamic>?> fetchAppUserRow() async {
    final user = _client.auth.currentUser;
    if (user == null) return null;

    final row = await _client
        .from('app_user')
        .select('*')
        .eq('auth_uid', user.id)
        .maybeSingle();

    if (row == null) return null;
    return Map<String, dynamic>.from(row as Map);
  }

  Future<DriverLicenseSnapshot> getSnapshot() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      return const DriverLicenseSnapshot(state: DriverLicenseState.unknown);
    }

    try {
      final row = await _client
          .from('app_user')
          .select(
              'driver_license_status,driver_license_no,driver_license_name,driver_license_expiry,driver_license_photo_path,driver_license_reject_remark')
          .eq('auth_uid', user.id)
          .maybeSingle();

      if (row == null) {
        // Fallback to auth metadata (still allow app to run even if DB row missing).
        final meta = user.userMetadata ?? const <String, dynamic>{};
        final raw = meta['driver_license_status']?.toString();
        final st = DriverLicenseSnapshot.parseStatus(raw);
        final no = meta['driver_license_no']?.toString();
        return DriverLicenseSnapshot(state: st, licenseNo: no, statusRaw: raw);
      }

      final m = Map<String, dynamic>.from(row as Map);
      final raw = m['driver_license_status']?.toString();
      final st = DriverLicenseSnapshot.parseStatus(raw);
      DateTime? expiry;
      final ex = m['driver_license_expiry'];
      if (ex != null) {
        try {
          expiry = DateTime.parse(ex.toString());
        } catch (_) {}
      }

      return DriverLicenseSnapshot(
        state: st,
        statusRaw: raw,
        licenseNo: m['driver_license_no']?.toString(),
        licenseName: m['driver_license_name']?.toString(),
        expiry: expiry,
        photoPath: m['driver_license_photo_path']?.toString(),
        rejectRemark: m['driver_license_reject_remark']?.toString(),
      );
    } catch (_) {
      // If columns don't exist yet / no permission, don't crash.
      final meta = user.userMetadata ?? const <String, dynamic>{};
      final raw = meta['driver_license_status']?.toString();
      final st = DriverLicenseSnapshot.parseStatus(raw);
      final no = meta['driver_license_no']?.toString();
      return DriverLicenseSnapshot(state: st, licenseNo: no, statusRaw: raw);
    }
  }

  Future<String?> createSignedPhotoUrl(String path) async {
    if (path.trim().isEmpty) return null;
    try {
      final signed = await _client.storage
          .from(bucketId)
          .createSignedUrl(path, 60 * 60); // 1 hour
      return signed;
    } catch (_) {
      return null;
    }
  }

  /// Submit (or resubmit) driver licence details + photo for admin review.
  ///
  /// Expected DB columns in `app_user`:
  /// - driver_license_no (varchar)
  /// - driver_license_name (varchar)
  /// - driver_license_expiry (date)
  /// - driver_license_photo_path (text)
  /// - driver_license_status (varchar)
  /// - driver_license_submitted_at (timestamp)
  /// - driver_license_reject_remark (varchar/text) [optional]
  Future<void> submit({
    required String licenseNo,
    required String licenseName,
    required DateTime expiryDate,
    required XFile photo,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) throw const AuthException('Not authenticated');

    // Upload photo to Storage
    final bytes = await photo.readAsBytes();
    final ext = _safeExt(photo.name);
    final objectPath =
        '${user.id}/dl_${DateTime.now().millisecondsSinceEpoch}.$ext';

    await _client.storage.from(bucketId).uploadBinary(
          objectPath,
          Uint8List.fromList(bytes),
          fileOptions: const FileOptions(upsert: true),
        );

    // Save to DB (authoritative)
    await _client.from('app_user').update({
      'driver_license_no': licenseNo.trim(),
      'driver_license_name': licenseName.trim(),
      'driver_license_expiry': expiryDate.toIso8601String().split('T').first,
      'driver_license_photo_path': objectPath,
      'driver_license_status': 'Pending',
      'driver_license_submitted_at': DateTime.now().toIso8601String(),
      'driver_license_reject_remark': null,
    }).eq('auth_uid', user.id);

    // Also store minimal into auth metadata as a fallback.
    try {
      await _client.auth.updateUser(
        UserAttributes(data: {
          'driver_license_status': 'Pending',
          'driver_license_no': licenseNo.trim(),
        }),
      );
    } catch (_) {}
  }

  String _safeExt(String filename) {
    final dot = filename.lastIndexOf('.');
    if (dot <= 0 || dot >= filename.length - 1) return 'jpg';
    final ext = filename.substring(dot + 1).toLowerCase();
    // keep sane extensions only
    const ok = {'jpg', 'jpeg', 'png', 'webp'};
    return ok.contains(ext) ? ext : 'jpg';
  }
}
