import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import '../profile/profile.dart';
import '../services/driver_license_service.dart';
import '../services/promotion_service.dart';
import '../services/in_app_notification_service.dart';
import 'product_page.dart';
import 'vehicle_browse_page.dart';
import 'nearby_map_page.dart';
import 'my_orders_page.dart';
import 'notifications_page.dart';

/// Home screen (car rental) inspired by common car-sharing layouts
/// (search + featured + car cards). Data is mocked for now.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  SupabaseClient get _supa => Supabase.instance.client;

  bool _dlLoaded = false;
  DriverLicenseSnapshot? _dl;

  late Future<List<Vehicle>> _vehiclesFuture;
  late Future<List<Map<String, dynamic>>> _annFuture;
  late Future<Set<String>> _claimedPromoIdsFuture;

  bool _hideAnnouncement = false;
  bool _claimingAnnouncementPromo = false;

  InAppNotificationService get _notificationSvc => InAppNotificationService(_supa);

  @override
  void initState() {
    super.initState();
    _refreshDriverLicense();
    _vehiclesFuture = _loadVehicles();
    _annFuture = PromotionService(_supa).fetchActiveAnnouncements();
    _claimedPromoIdsFuture = PromotionService(_supa).fetchClaimedPromoIds();
  }

  Future<void> _refreshAnnouncements() async {
    setState(() {
      _annFuture = PromotionService(_supa).fetchActiveAnnouncements();
    });
    await _annFuture;
  }

  Future<void> _refreshClaimedPromos() async {
    setState(() {
      _claimedPromoIdsFuture = PromotionService(_supa).fetchClaimedPromoIds();
    });
    await _claimedPromoIdsFuture;
  }

  Future<List<Vehicle>> _loadVehicles() async {
    // NOTE: if you enable RLS on vehicle, make sure you have a SELECT policy.
    // Common policy: allow public SELECT where vehicle_status = 'Available'.
    final rows = await _supa
        .from('vehicle')
        .select()
        .eq('vehicle_status', 'Available')
        .order('vehicle_id', ascending: false);

    final list = (rows as List)
        .map((e) => Vehicle.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
    return list;
  }

  Future<void> _refreshVehicles() async {
    setState(() {
      _vehiclesFuture = _loadVehicles();
    });
    await _vehiclesFuture;
  }

  String get _displayName {
    final u = _supa.auth.currentUser;
    final meta = u?.userMetadata ?? const <String, dynamic>{};
    final raw = (meta['full_name'] as String?) ?? (meta['name'] as String?);
    if (raw != null && raw.trim().isNotEmpty) return raw.trim();
    final email = u?.email ?? '';
    return email.isNotEmpty ? email.split('@').first : 'User';
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return 'U';
    final first = parts.first.isNotEmpty ? parts.first[0] : 'U';
    final second = parts.length > 1 && parts[1].isNotEmpty ? parts[1][0] : '';
    return (first + second).toUpperCase();
  }

  Future<void> _refreshDriverLicense() async {
    final snap = await DriverLicenseService(_supa).getSnapshot();
    if (!mounted) return;
    setState(() {
      _dlLoaded = true;
      _dl = snap;
    });
  }

  Future<void> _openProfile() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ProfilePage()),
    );
    await _refreshDriverLicense();
    await _refreshVehicles();
    await _refreshClaimedPromos();
  }

  // Vouchers are accessed from Profile > My Vouchers only.

  Future<bool> _ensureLicenseBeforeRental() async {
    final snap = await DriverLicenseService(_supa).getSnapshot();

    if (snap.state == DriverLicenseState.approved) return true;

    if (!mounted) return false;

    String title = 'Driver licence required';
    String body =
        'Please submit your driver licence details before starting a rental.';
    String action = 'Go to Profile';

    if (snap.state == DriverLicenseState.pending) {
      title = 'Under review';
      body =
          'Your driver licence submission is pending admin review. You can start renting once it is approved.';
      action = 'View status';
    } else if (snap.state == DriverLicenseState.rejected) {
      title = 'Verification rejected';
      body =
          'Your driver licence submission was rejected. Please resubmit with clear details and a readable photo.';
      if ((snap.rejectRemark ?? '').trim().isNotEmpty) {
        body += '\n\nRemark: ${snap.rejectRemark}';
      }
      action = 'Resubmit';
    }

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Later'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                _openProfile();
              },
              child: Text(action),
            ),
          ],
        );
      },
    );
    return false;
  }

  Future<void> _startRental(String carName) async {
    final ok = await _ensureLicenseBeforeRental();
    if (!ok) return;

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Rent: $carName')),
    );
  }

  Future<void> _openProduct(Vehicle v) async {
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProductPage(
          vehicleId: v.vehicleId,
          brand: v.brand,
          model: v.model,
          type: v.type,
          plate: v.plate,
          transmission: v.transmission,
          fuelType: v.fuel,
          seats: v.seats,
          dailyRate: v.dailyRate,
          location: v.location,
          photoUrl: _vehiclePhotoPublicUrl(v.photoPath),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dl = _dl;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Car Rental'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _refreshVehicles,
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: 'Notifications',
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const NotificationsPage()),
              );
              if (mounted) setState(() {});
            },
            icon: FutureBuilder<int>(
              future: _notificationSvc.unreadCountForCurrentUser(),
              builder: (context, snapshot) {
                final unread = snapshot.data ?? 0;
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Icon(Icons.notifications_none_rounded),
                    if (unread > 0)
                      Positioned(
                        right: -2,
                        top: -2,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                          child: Text(
                            unread > 9 ? '9+' : unread.toString(),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: _openProfile,
              child: CircleAvatar(
                radius: 16,
                child: Text(
                  _initials(_displayName),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Text(
              'Hi, $_displayName',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              'Find a car near you and start your trip in minutes.',
              style: TextStyle(color: Colors.grey.shade700),
            ),
            const SizedBox(height: 12),

            if (_dlLoaded && dl != null && dl.state != DriverLicenseState.approved)
              ...[
                _LicenseStatusBanner(
                  snapshot: dl,
                  onTap: _openProfile,
                ),
                const SizedBox(height: 16),
              ],

            if (!_hideAnnouncement)
              FutureBuilder<List<Map<String, dynamic>>>(
                future: _annFuture,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const SizedBox.shrink();
                  }
                  final rows = snap.data ?? const [];
                  if (rows.isEmpty) return const SizedBox.shrink();
                  final a = rows.first;
                  final title = (a['title'] ?? 'Announcement').toString();
                  final msg = (a['message'] ?? '').toString();
                  final promo = (a['promo_code'] ?? '').toString().trim();
                  if (promo.isEmpty) {
                    return _AnnouncementBanner(
                      title: title,
                      message: msg,
                      promoCode: null,
                      onDismiss: () => setState(() => _hideAnnouncement = true),
                    );
                  }

                  return FutureBuilder<Map<String, dynamic>?>(
                    future: PromotionService(_supa).getPromotionByCode(promo),
                    builder: (context, promoSnap) {
                      final promoRow = promoSnap.data;
                      final promoId = (promoRow?['promo_id'] ?? '').toString().trim();
                      return FutureBuilder<Set<String>>(
                        future: _claimedPromoIdsFuture,
                        builder: (context, claimedSnap) {
                          final claimedIds = claimedSnap.data ?? const <String>{};
                          final alreadyClaimed =
                              promoId.isNotEmpty && claimedIds.contains(promoId);
                          return _AnnouncementBanner(
                            title: title,
                            message: msg,
                            promoCode: promo,
                            onDismiss: () => setState(() => _hideAnnouncement = true),
                            showClaimButton: true,
                            claimLabel: _claimingAnnouncementPromo
                                ? 'Claiming...'
                                : alreadyClaimed
                                    ? 'Claimed'
                                    : 'Claim',
                            onClaim: alreadyClaimed || promoId.isEmpty || _claimingAnnouncementPromo
                                ? null
                                : () async {
                                    setState(() {
                                      _claimingAnnouncementPromo = true;
                                    });
                                    try {
                                      final svc = PromotionService(_supa);
                                      final result = await svc.claimVoucherWithStatus(promoId: promoId);
                                      if (!mounted) return;
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            result.alreadyClaimed
                                                ? 'Already claimed: $promo'
                                                : 'Voucher claimed: $promo',
                                          ),
                                        ),
                                      );
                                      await _refreshClaimedPromos();
                                    } catch (e) {
                                      if (!mounted) return;
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(SnackBar(content: Text('Claim failed: $e')));
                                    } finally {
                                      if (!mounted) return;
                                      setState(() {
                                        _claimingAnnouncementPromo = false;
                                      });
                                    }
                                  },
                          );
                        },
                      );
                    },
                  );
                },
              ),

            // (Removed) Voucher quick access from Home.
            // Users can view/claim vouchers in Profile > My Vouchers.


            // Featured
            _FeaturedBanner(
              title: 'Drive from RM6/hour',
              subtitle: 'Hourly • Daily • Weekly — flexible plans',
              buttonText: 'Book now',
              onPressed: () async {
                final ok = await _ensureLicenseBeforeRental();
                if (!ok) return;
                if (!mounted) return;
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const VehicleBrowsePage(),
                  ),
                );
              },
            ),
            const SizedBox(height: 22),

            // Quick actions
            Row(
              children: [
                Expanded(
                  child: _QuickAction(
                    icon: Icons.map_outlined,
                    title: 'Nearby',
                    subtitle: 'Explore zones',
                    onTap: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const NearbyMapPage()),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _QuickAction(
                    icon: Icons.receipt_long_outlined,
                    title: 'Bookings',
                    subtitle: 'Your rentals',
                    onTap: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const MyOrdersPage()),
                      );
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),

            // Popular cars
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Available cars',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                TextButton(
                  onPressed: () async {
                    final ok = await _ensureLicenseBeforeRental();
                    if (!ok) return;
                    if (!mounted) return;
                    await Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const VehicleBrowsePage()),
                    );
                  },
                  child: const Text('View all'),
                ),
              ],
            ),
            FutureBuilder<List<Vehicle>>(
              future: _vehiclesFuture,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 18),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snap.hasError) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text('Failed to load vehicles: ${snap.error}'),
                  );
                }
                final vehicles = snap.data ?? const [];
                if (vehicles.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'No vehicles available yet.\n(Ask admin to add a vehicle with status "Available".)',
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                  );
                }

                // Horizontal cards
                return Column(
                  children: [
                    SizedBox(
                      height: 290,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: vehicles.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 12),
                        itemBuilder: (context, i) {
                          final v = vehicles[i];
                          return _VehicleCard(
                            vehicle: v,
                            photoUrl: _vehiclePhotoPublicUrl(v.photoPath),
                            onRent: () => _openProduct(v),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'All available cars',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 12),
                    ...vehicles.map(
                      (v) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _VehicleListTile(
                          vehicle: v,
                          photoUrl: _vehiclePhotoPublicUrl(v.photoPath),
                        onTap: () => _openProduct(v),
                          trailing: FilledButton.tonal(
                          onPressed: () => _openProduct(v),
                            child: Text('RM${v.dailyRate.toStringAsFixed(0)}/day'),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 22),

            Text(
              'Logged in as: ${_supa.auth.currentUser?.email ?? '-'}',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  String? _vehiclePhotoPublicUrl(String? path) {
    if (path == null || path.trim().isEmpty) return null;
    // For testing, keep vehicle_photos bucket public.
    // Public URL format: <supabaseUrl>/storage/v1/object/public/<bucket>/<path>
    final safe = path.replaceFirst(RegExp(r'^/+'), '');
    return '${SupabaseConfig.supabaseUrl}/storage/v1/object/public/vehicle_photos/$safe';
  }
}

class Vehicle {
  final String vehicleId;
  final String brand;
  final String model;
  final String type;
  final String plate;
  final String transmission;
  final String fuel;
  final int seats;
  final double dailyRate;
  final String location;
  final String status;
  final String? photoPath;

  const Vehicle({
    required this.vehicleId,
    required this.brand,
    required this.model,
    required this.type,
    required this.plate,
    required this.transmission,
    required this.fuel,
    required this.seats,
    required this.dailyRate,
    required this.location,
    required this.status,
    required this.photoPath,
  });

  String get title {
    final t = ('$brand $model').trim();
    return t.isEmpty ? vehicleId : t;
  }

  factory Vehicle.fromMap(Map<String, dynamic> m) {
    return Vehicle(
      vehicleId: (m['vehicle_id'] ?? '').toString(),
      brand: (m['vehicle_brand'] ?? '').toString(),
      model: (m['vehicle_model'] ?? '').toString(),
      type: (m['vehicle_type'] ?? '').toString(),
      plate: (m['vehicle_plate_no'] ?? '').toString(),
      transmission: (m['transmission_type'] ?? '').toString(),
      fuel: (m['fuel_type'] ?? '').toString(),
      seats: (m['seat_capacity'] is int)
          ? (m['seat_capacity'] as int)
          : int.tryParse((m['seat_capacity'] ?? '0').toString()) ?? 0,
      dailyRate: (m['daily_rate'] is num)
          ? (m['daily_rate'] as num).toDouble()
          : double.tryParse((m['daily_rate'] ?? '0').toString()) ?? 0,
      location: (m['vehicle_location'] ?? '').toString(),
      status: (m['vehicle_status'] ?? '').toString(),
      photoPath: m['vehicle_photo_path']?.toString(),
    );
  }
}

class _VehicleCard extends StatelessWidget {
  const _VehicleCard({
    required this.vehicle,
    required this.onRent,
    this.photoUrl,
  });

  final Vehicle vehicle;
  final String? photoUrl;
  final VoidCallback onRent;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: 240,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onRent,
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 140,
              width: double.infinity,
              child: photoUrl == null
                  ? Container(
                      color: cs.surfaceContainerHighest,
                      alignment: Alignment.center,
                      child: const Icon(Icons.directions_car_rounded, size: 52),
                    )
                  : Image.network(
                      photoUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: cs.surfaceContainerHighest,
                        alignment: Alignment.center,
                        child: const Icon(Icons.image_not_supported_outlined),
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    vehicle.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${vehicle.type} • ${vehicle.seats} seats',
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'RM${vehicle.dailyRate.toStringAsFixed(0)}/day',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      FilledButton.tonal(
                        onPressed: onRent,
                        child: const Text('View'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    vehicle.location.isEmpty ? '-' : vehicle.location,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
          ),
        ),
      ),
    );
  }
}

class _AnnouncementBanner extends StatelessWidget {
  const _AnnouncementBanner({
    required this.title,
    required this.message,
    this.promoCode,
    required this.onDismiss,
    this.onClaim,
    this.showClaimButton = false,
    this.claimLabel = 'Claim',
  });

  final String title;
  final String message;
  final String? promoCode;
  final VoidCallback onDismiss;
  final VoidCallback? onClaim;
  final bool showClaimButton;
  final String claimLabel;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: cs.primary.withOpacity(0.10),
        border: Border.all(color: cs.primary.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w900)),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: onDismiss,
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          if (message.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 8),
              child: Text(message,
                  style: TextStyle(color: Colors.grey.shade800)),
            ),
          Row(
            children: [
              if (promoCode != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: cs.outlineVariant.withOpacity(0.4)),
                  ),
                  child: Text(
                    promoCode!,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              const Spacer(),
              if (showClaimButton)
                FilledButton.tonal(
                  onPressed: onClaim,
                  child: Text(claimLabel),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _VehicleListTile extends StatelessWidget {
  const _VehicleListTile({
    required this.vehicle,
    required this.onTap,
    required this.trailing,
    this.photoUrl,
  });

  final Vehicle vehicle;
  final String? photoUrl;
  final VoidCallback onTap;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: ListTile(
        onTap: onTap,
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: 54,
            height: 54,
            child: photoUrl == null
                ? Container(
                    color: cs.surfaceContainerHighest,
                    alignment: Alignment.center,
                    child: const Icon(Icons.directions_car_rounded),
                  )
                : Image.network(
                    photoUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: cs.surfaceContainerHighest,
                      alignment: Alignment.center,
                      child: const Icon(Icons.image_not_supported_outlined),
                    ),
                  ),
          ),
        ),
        title: Text(vehicle.title, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(
          '${vehicle.plate.isEmpty ? '-' : vehicle.plate} • ${vehicle.location.isEmpty ? '-' : vehicle.location}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
        ),
        trailing: trailing,
      ),
    );
  }
}

class _LicenseStatusBanner extends StatelessWidget {
  const _LicenseStatusBanner({
    required this.snapshot,
    required this.onTap,
  });

  final DriverLicenseSnapshot snapshot;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    String title = 'Driver licence required';
    String message =
        'Submit your driver licence to start renting. Approval is required.';
    IconData icon = Icons.warning_amber_rounded;
    Color tint = cs.error;

    if (snapshot.state == DriverLicenseState.pending) {
      title = 'Driver licence under review';
      message =
          'Your submission is pending admin review. You can rent after approval.';
      icon = Icons.hourglass_top_rounded;
      tint = cs.tertiary;
    } else if (snapshot.state == DriverLicenseState.rejected) {
      title = 'Driver licence rejected';
      message =
          'Please resubmit with correct details and a clear photo for verification.';
      if ((snapshot.rejectRemark ?? '').trim().isNotEmpty) {
        message += '\nRemark: ${snapshot.rejectRemark}';
      }
      icon = Icons.cancel_outlined;
      tint = cs.error;
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: tint.withOpacity(0.12),
        border: Border.all(color: tint.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, color: tint),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(message, style: TextStyle(color: Colors.grey.shade800)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(onPressed: onTap, child: const Text('Open')),
        ],
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.onTapFilter,
    required this.onChanged,
  });

  final VoidCallback onTapFilter;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: cs.surfaceContainerHighest.withOpacity(0.5),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.search_rounded),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search by model, location, type…',
                isDense: true,
                border: InputBorder.none,
              ),
              onChanged: onChanged,
            ),
          ),
          IconButton(
            tooltip: 'Filter',
            onPressed: onTapFilter,
            icon: const Icon(Icons.tune_rounded),
          ),
        ],
      ),
    );
  }
}

class _FeaturedBanner extends StatelessWidget {
  const _FeaturedBanner({
    required this.title,
    required this.subtitle,
    required this.buttonText,
    required this.onPressed,
  });

  final String title;
  final String subtitle;
  final String buttonText;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          colors: [
            cs.primaryContainer,
            cs.tertiaryContainer.withOpacity(0.9),
          ],
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: cs.onPrimaryContainer,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: TextStyle(color: cs.onPrimaryContainer),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: onPressed,
                  child: Text(buttonText),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            height: 88,
            width: 88,
            decoration: BoxDecoration(
              color: cs.surface.withOpacity(0.35),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(Icons.directions_car_filled_rounded, size: 40),
          ),
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: cs.surfaceContainerHighest.withOpacity(0.4),
          border: Border.all(color: cs.outlineVariant.withOpacity(0.25)),
        ),
        child: Row(
          children: [
            Container(
              height: 42,
              width: 42,
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: cs.onPrimaryContainer),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style:
                          TextStyle(color: Colors.grey.shade700, fontSize: 12)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
  }
}

class _CarCardModel {
  const _CarCardModel({
    required this.name,
    required this.type,
    required this.pricePerHour,
    required this.seats,
    required this.transmission,
    required this.fuel,
  });

  final String name;
  final String type;
  final int pricePerHour;
  final int seats;
  final String transmission;
  final String fuel;
}

class _CarCard extends StatelessWidget {
  const _CarCard({required this.model, required this.onRent});

  final _CarCardModel model;
  final VoidCallback onRent;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      width: 240,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: cs.surfaceContainerHighest.withOpacity(0.55),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  model.name,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  color: cs.primaryContainer,
                ),
                child: Text(
                  model.type,
                  style: TextStyle(
                    color: cs.onPrimaryContainer,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            height: 72,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: cs.surface,
            ),
            child: const Center(
              child: Icon(Icons.directions_car_filled_rounded, size: 34),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              _SpecPill(
                  icon: Icons.event_seat_outlined, text: '${model.seats} seats'),
              _SpecPill(icon: Icons.settings_outlined, text: model.transmission),
              _SpecPill(
                  icon: Icons.local_gas_station_outlined, text: model.fuel),
            ],
          ),
          const Spacer(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'RM${model.pricePerHour}/hr',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              FilledButton(
                onPressed: onRent,
                child: const Text('Rent'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SpecPill extends StatelessWidget {
  const _SpecPill({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 6),
          Text(text, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}

class _CarListTile extends StatelessWidget {
  const _CarListTile({
    required this.model,
    required this.onTap,
    required this.trailing,
  });

  final _CarCardModel model;
  final VoidCallback onTap;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: cs.surfaceContainerHighest.withOpacity(0.45),
          border: Border.all(color: cs.outlineVariant.withOpacity(0.25)),
        ),
        child: Row(
          children: [
            Container(
              height: 56,
              width: 56,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: cs.surface,
              ),
              child: const Icon(Icons.directions_car_filled_rounded),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(model.name,
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 3),
                  Text(
                    '${model.type} • ${model.seats} seats • ${model.transmission}',
                    style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                  ),
                ],
              ),
            ),
            trailing,
          ],
        ),
      ),
    );
  }
}