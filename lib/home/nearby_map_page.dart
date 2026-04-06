import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/rentable_vehicle_service.dart';
import '../services/road_tax_monitor_service.dart';

// NOTE: Requires pubspec.yaml dependencies:
//   flutter_map: ^6.1.0
//   latlong2: ^0.9.1
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

// NOTE: Requires pubspec.yaml dependency:
//   geolocator: ^10.1.0 (or compatible)
import 'package:geolocator/geolocator.dart';

class NearbyMapPage extends StatefulWidget {
  const NearbyMapPage({super.key});

  @override
  State<NearbyMapPage> createState() => _NearbyMapPageState();
}

class _NearbyMapPageState extends State<NearbyMapPage> {
  SupabaseClient get _supa => Supabase.instance.client;

  final MapController _mapController = MapController();

  bool _loading = true;
  String? _error;

  // location string -> coordinates
  final Map<String, LatLng?> _geoCache = {};

  // location -> vehicles at that location
  final Map<String, List<_VehicleMini>> _vehiclesByLocation = {};

  LatLng _center = const LatLng(3.1390, 101.6869); // Kuala Lumpur fallback
  double _zoom = 11.5;

  LatLng? _userLocation;
  bool _locatingMe = false;
  String? _locationError;

  bool _geocoding = false;

  @override
  void initState() {
    super.initState();
    _load();

    // Try to show user location (will request permission only when needed).
    // If user denies, we keep the map working normally.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fetchMyLocation(moveMap: false, showSnack: false);
    });
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<bool> _ensureLocationPermission({bool showSnack = true}) async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() => _locationError = 'Location services are disabled.');
      if (showSnack) _toast('Please enable GPS/location services.');
      return false;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      setState(() => _locationError = 'Location permission denied.');
      if (showSnack) _toast('Location permission denied.');
      return false;
    }

    if (permission == LocationPermission.deniedForever) {
      setState(() => _locationError = 'Location permission permanently denied.');
      if (showSnack) {
        _toast('Location permission permanently denied. Enable it in Settings.');
      }
      return false;
    }

    return true;
  }

  Future<void> _fetchMyLocation({required bool moveMap, bool showSnack = true}) async {
    if (_locatingMe) return;
    setState(() {
      _locatingMe = true;
      _locationError = null;
    });

    try {
      final ok = await _ensureLocationPermission(showSnack: showSnack);
      if (!ok) return;

      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      final ll = LatLng(pos.latitude, pos.longitude);

      if (!mounted) return;
      setState(() => _userLocation = ll);

      if (moveMap) {
        _mapController.move(ll, 15.5);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _locationError = e.toString());
      if (showSnack) _toast('Failed to get your location.');
    } finally {
      if (mounted) setState(() => _locatingMe = false);
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _vehiclesByLocation.clear();
      _geoCache.clear();
      _geocoding = false;
    });

    try {
      final rentableService = RentableVehicleService(_supa);
      await RoadTaxMonitorService(_supa).syncRoadTaxStates().catchError((_) {});
      final activeLocations = await rentableService.fetchActiveLocationNames();
      final blockedVehicleIds = await rentableService.fetchBlockedVehicleIds();

      final rows = await _supa
          .from('vehicle')
          .select('vehicle_id, vehicle_brand, vehicle_model, vehicle_location, vehicle_status, road_tax_expiry_date')
          .eq('vehicle_status', 'Available')
          .order('vehicle_id', ascending: false)
          .limit(80);

      final list = (rows as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where((row) => rentableService.isRentableVehicle(row, activeLocations, blockedVehicleIds))
          .map(_VehicleMini.fromMap)
          .toList();

      // group by location label
      for (final v in list) {
        final loc = v.location.trim().isEmpty ? '-' : v.location.trim();
        _vehiclesByLocation.putIfAbsent(loc, () => []).add(v);
      }

      if (!mounted) return;
      setState(() {
        _loading = false;
      });

      // start geocoding in the background (still in UI thread but after first paint)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _geocodeAllLocations();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _geocodeAllLocations() async {
    if (_geocoding) return;
    setState(() => _geocoding = true);

    final locs = _vehiclesByLocation.keys.where((k) => k != '-' && k.trim().isNotEmpty).toList();
    LatLng? firstFound;

    for (final loc in locs) {
      if (!mounted) return;
      if (_geoCache.containsKey(loc)) continue;

      final ll = await _geocode(loc);
      _geoCache[loc] = ll;

      firstFound ??= ll;

      // be polite to the free geocoding service (avoid rate limit)
      await Future.delayed(const Duration(milliseconds: 250));
    }

    if (!mounted) return;

    final points = _geoCache.values.whereType<LatLng>().toList();
    if (points.isNotEmpty) {
      final avgLat = points.map((e) => e.latitude).reduce((a, b) => a + b) / points.length;
      final avgLng = points.map((e) => e.longitude).reduce((a, b) => a + b) / points.length;
      setState(() {
        _center = LatLng(avgLat, avgLng);
        _zoom = points.length <= 1 ? 14.0 : 9.5;
      });
      _mapController.move(_center, _zoom);
    } else if (firstFound != null) {
      setState(() {
        _center = firstFound!;
      });
      _mapController.move(_center, _zoom);
    }

    setState(() => _geocoding = false);
  }

  Future<LatLng?> _geocode(String address) async {
    final q = address.trim();
    if (q.isEmpty || q == '-') return null;

    try {
      final uri = Uri.https(
        'nominatim.openstreetmap.org',
        '/search',
        <String, String>{
          'q': q,
          'format': 'json',
          'limit': '1',
        },
      );

      final client = HttpClient();
      final req = await client.getUrl(uri);

      // Nominatim requires a valid User-Agent.
      req.headers.set('User-Agent', 'car_rental_system_fyp/1.0');

      final resp = await req.close();
      final body = await resp.transform(utf8.decoder).join();

      client.close(force: true);

      if (resp.statusCode != 200) return null;

      final data = jsonDecode(body);
      if (data is! List || data.isEmpty) return null;

      final first = data.first;
      if (first is! Map) return null;

      final lat = double.tryParse(first['lat']?.toString() ?? '');
      final lon = double.tryParse(first['lon']?.toString() ?? '');
      if (lat == null || lon == null) return null;

      return LatLng(lat, lon);
    } catch (_) {
      return null;
    }
  }


  List<Marker> _locationMarkers(Color color, Color foreground) {
    final out = <Marker>[];
    for (final entry in _vehiclesByLocation.entries) {
      final base = _geoCache[entry.key];
      if (base == null) continue;

      final cars = entry.value;
      final count = cars.length;
      final markerWidth = count >= 10 ? 86.0 : 76.0;

      out.add(
        Marker(
          point: base,
          width: markerWidth,
          height: 64,
          child: GestureDetector(
            onTap: () => _openLocationSheet(entry.key),
            child: Container(
              decoration: BoxDecoration(
                color: color.withOpacity(0.95),
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                    color: Colors.black.withOpacity(0.18),
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.directions_car_rounded, color: foreground, size: 20),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      count == 1 ? '1 car' : '$count cars',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: foreground,
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return out;
  }

  void _openLocationSheet(String location) {
    final vehicles = _vehiclesByLocation[location] ?? const <_VehicleMini>[];
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                location,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 10),
              if (vehicles.isEmpty)
                Text('No cars at this location.', style: TextStyle(color: Colors.grey.shade700))
              else
                ...vehicles.map(
                      (v) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        const Icon(Icons.directions_car_rounded, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            v.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        Text(
                          v.status,
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nearby Cars'),
        actions: [
          IconButton(
            tooltip: 'My Location',
            onPressed: () => _fetchMyLocation(moveMap: true),
            icon: _locatingMe
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.my_location_rounded),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  if (_loading)
                    const Expanded(child: Center(child: CircularProgressIndicator()))
                  else if (_error != null)
                    Expanded(
                      child: Center(
                        child: Text(
                          _error!,
                          style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.w700),
                        ),
                      ),
                    )
                  else
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: FlutterMap(
                          mapController: _mapController,
                          options: MapOptions(
                            initialCenter: _center,
                            initialZoom: _zoom,
                            onPositionChanged: (pos, _) {
                              final c = pos.center;
                              final z = pos.zoom;
                              if (c != null && z != null) {
                                _center = c;
                                _zoom = z;
                              }
                            },
                          ),
                          children: [
                            TileLayer(
                              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                              userAgentPackageName: 'car_rental_system_fyp',
                            ),
                            MarkerLayer(
                              markers: [
                                // user current location marker
                                if (_userLocation != null)
                                  Marker(
                                    point: _userLocation!,
                                    width: 44,
                                    height: 44,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Colors.blue.withOpacity(0.92),
                                        shape: BoxShape.circle,
                                        boxShadow: [
                                          BoxShadow(
                                            blurRadius: 10,
                                            offset: const Offset(0, 4),
                                            color: Colors.black.withOpacity(0.18),
                                          ),
                                        ],
                                      ),
                                      alignment: Alignment.center,
                                      child: const Icon(Icons.person_pin_circle_rounded, color: Colors.white, size: 26),
                                    ),
                                  ),

                                // one pin for each parking location, with total cars shown on the pin
                                ..._locationMarkers(cs.primary, cs.onPrimary),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(Icons.info_outline_rounded, size: 18, color: Colors.grey.shade700),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _geocoding
                              ? 'Loading map pins... (converting location to coordinates)'
                              : 'Each pin shows the total cars at that parking location. Tap a pin to see the full car list.',
                          style: TextStyle(color: Colors.grey.shade700),
                        ),
                      ),
                    ],
                  ),
                  if (_locationError != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.gps_off_rounded, size: 18, color: Colors.red.shade700),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _locationError!,
                            style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _VehicleMini {
  final String id;
  final String title;
  final String location;
  final String status;

  _VehicleMini({
    required this.id,
    required this.title,
    required this.location,
    required this.status,
  });

  static _VehicleMini fromMap(Map<String, dynamic> m) {
    final id = (m['vehicle_id'] ?? '').toString();
    final brand = (m['vehicle_brand'] ?? '').toString();
    final model = (m['vehicle_model'] ?? '').toString();
    final title = ('${brand.trim()} ${model.trim()}').trim().isEmpty ? id : ('${brand.trim()} ${model.trim()}').trim();
    final location = (m['vehicle_location'] ?? '').toString();
    final status = (m['vehicle_status'] ?? '').toString();
    return _VehicleMini(id: id, title: title, location: location, status: status);
  }
}


