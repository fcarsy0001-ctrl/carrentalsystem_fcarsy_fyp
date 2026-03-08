import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// NOTE: Requires pubspec.yaml dependencies:
//   flutter_map: ^6.1.0
//   latlong2: ^0.9.1
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class NearbyMapPage extends StatefulWidget {
  const NearbyMapPage({super.key});

  @override
  State<NearbyMapPage> createState() => _NearbyMapPageState();
}

class _NearbyMapPageState extends State<NearbyMapPage> {
  SupabaseClient get _supa => Supabase.instance.client;

  bool _loading = true;
  String? _error;

  // location string -> coordinates
  final Map<String, LatLng?> _geoCache = {};

  // location -> vehicles at that location
  final Map<String, List<_VehicleMini>> _vehiclesByLocation = {};

  LatLng _center = const LatLng(3.1390, 101.6869); // Kuala Lumpur fallback
  double _zoom = 11.5;

  bool _geocoding = false;

  @override
  void initState() {
    super.initState();
    _load();
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
      final rows = await _supa
          .from('vehicle')
          .select('vehicle_id, vehicle_brand, vehicle_model, vehicle_location, vehicle_status')
          .eq('vehicle_status', 'Available')
          .order('vehicle_id', ascending: false)
          .limit(80);

      final list = (rows as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
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

    if (firstFound != null) {
      setState(() {
        _center = firstFound!;
      });
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
                              markers: _vehiclesByLocation.entries
                                  .map((e) => MapEntry(e.key, _geoCache[e.key]))
                                  .where((e) => e.value != null)
                                  .map(
                                    (e) => Marker(
                                      point: e.value!,
                                      width: 46,
                                      height: 46,
                                      child: GestureDetector(
                                        onTap: () => _openLocationSheet(e.key),
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: cs.primary.withOpacity(0.92),
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
                                          child: Text(
                                            '${_vehiclesByLocation[e.key]?.length ?? 0}',
                                            style: TextStyle(
                                              color: cs.onPrimary,
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(),
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
                              ? 'Loading map pins… (converting location to coordinates)'
                              : 'Tap a pin to see cars at that location.',
                          style: TextStyle(color: Colors.grey.shade700),
                        ),
                      ),
                    ],
                  ),
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
