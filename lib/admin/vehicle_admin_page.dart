import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'vehicle_location_admin_page.dart';
import 'widgets/admin_ui.dart';

import '../services/leaser_vehicle_service.dart';

class VehicleAdminPage extends StatefulWidget {
  const VehicleAdminPage({
    super.key,
    this.leaserId,
    this.title,
    this.actions,
    this.embedded = false,
  });

  /// If provided, the list (and create/edit) will be restricted to this leaser_id.
  final String? leaserId;

  /// Optional custom app bar title.
  final String? title;

  /// Optional extra actions for the app bar.
  final List<Widget>? actions;

  /// UI-only: when true, renders without its own AppBar/FAB (for Admin Home tabs).
  final bool embedded;

  @override
  State<VehicleAdminPage> createState() => _VehicleAdminPageState();
}

class _VehicleAdminPageState extends State<VehicleAdminPage> {
  SupabaseClient get _supa => Supabase.instance.client;

  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final base = _supa.from('vehicle').select('*');
    final q = (widget.leaserId == null || widget.leaserId!.trim().isEmpty)
        ? base
        : base.eq('leaser_id', widget.leaserId!.trim());

    final rows = await q.order('vehicle_id', ascending: false);
    return (rows as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  Future<void> _openUpsert({Map<String, dynamic>? initial}) async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _VehicleUpsertPage(
          initial: initial,
          fixedLeaserId: widget.leaserId,
        ),
      ),
    );
    if (ok == true) await _refresh();
  }

  Future<void> _confirmDelete(Map<String, dynamic> row) async {
    final id = _s(row['vehicle_id']);
    if (id.isEmpty) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete vehicle'),
        content: Text('Delete vehicle $id? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (yes != true) return;

    try {
      final photo = _s(row['vehicle_photo_path']).trim();
      // Leaser mode: delete via Edge Function to bypass strict RLS policies.
      final isLeaserMode = (widget.leaserId ?? '').trim().isNotEmpty;
      if (isLeaserMode) {
        try {
          await LeaserVehicleService(_supa).deleteVehicle(vehicleId: id);
        } catch (e) {
          final s = e.toString();
          final isNotFound = (e is FunctionException &&
                  (e.status == 404 || (e.details ?? '').toString().contains('NOT_FOUND'))) ||
              s.contains('Requested function was not found') ||
              s.contains('NOT_FOUND') ||
              s.contains('Not Found');
          if (!isNotFound) rethrow;
          // Fallback: direct DB delete (requires RLS policy).
          await _supa.from('vehicle').delete().eq('vehicle_id', id);
        }
      } else {
        await _supa.from('vehicle').delete().eq('vehicle_id', id);
      }
      // Best-effort photo cleanup (ignore errors if bucket/policy not set).
      if (photo.isNotEmpty) {
        try {
          await _supa.storage.from('vehicle_photos').remove([photo]);
        } catch (_) {}
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vehicle deleted')),
      );
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_prettyError(e)), backgroundColor: Colors.red),
      );
    }
  }

  String _s(dynamic v) => v == null ? '' : v.toString();


  String _prettyError(Object e) {
    // Edge Function missing (404)
    if (e is FunctionException) {
      final d = (e.details ?? '').toString();
      if (e.status == 404 || d.contains('NOT_FOUND') || d.contains('Requested function was not found')) {
        return 'Failed: ${e.toString()}\n\n'
            'Tip: Your Supabase Edge Function is not deployed. Deploy: '
            'leaser_upsert_vehicle (and leaser_delete_vehicle) in Supabase, then retry.';
      }
    }

    // Leaser not linked / not approved (Edge Function)
    final raw = e.toString();
    final low = raw.toLowerCase();
    if (low.contains('not a leaser')) {
      return 'Failed: $raw\n\n'
          'Tip: Your account is not linked to a Leaser record.\n'
          '- Make sure you login with the SAME email used in leaser registration.\n'
          '- Ensure your leaser application is Approved.\n'
          '- If this is an old account, run the SQL backfill to fill app_user.auth_uid by email.';
    }
    if (low.contains('leaser row not found') || low.contains('not approved')) {
      return 'Failed: $raw\n\n'
          'Tip: Your leaser record is not found or not approved yet. Ask admin to approve your leaser application.';
    }

    // RLS forbidden
    if (e is PostgrestException) {
      if ((e.code ?? '').toString() == '42501' || (e.details ?? '').toString().toLowerCase().contains('row-level security')) {
        return 'Failed: ${e.toString()}\n\n'
            'Tip: RLS blocked this write. Either (A) deploy the leaser vehicle Edge Functions, '
            'or (B) add an RLS policy to allow approved leasers to INSERT/UPDATE/DELETE their own vehicles.';
      }
    }
    final s = e.toString();
    return 'Failed: $s';
  }

  @override
  Widget build(BuildContext context) {
    final leaserMode = (widget.leaserId ?? '').trim().isNotEmpty;

    Widget buildList(List<Map<String, dynamic>> rows) {
      return RefreshIndicator(
        onRefresh: _refresh,
        child: rows.isEmpty
            ? ListView(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
                children: const [
                  Center(child: Text('No vehicles yet')),
                ],
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                itemCount: rows.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  final r = rows[i];
                  final title = '${_s(r['vehicle_brand'])} ${_s(r['vehicle_model'])}'.trim();
                  final plate = _s(r['vehicle_plate_no']);
                  final status = _s(r['vehicle_status']);
                  final rate = _s(r['daily_rate']);
                  return AdminCard(
                    child: ListTile(
                      title: Text(
                        title.isEmpty ? 'Vehicle' : title,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        'ID: ${_s(r['vehicle_id'])}\n'
                        'Plate: ${plate.isEmpty ? '-' : plate}\n'
                        'Rate: RM $rate / day',
                      ),
                      isThreeLine: true,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AdminStatusChip(status: status),
                          PopupMenuButton<String>(
                            onSelected: (v) {
                              if (v == 'edit') {
                                _openUpsert(initial: r);
                              } else if (v == 'delete') {
                                _confirmDelete(r);
                              }
                            },
                            itemBuilder: (ctx) => const [
                              PopupMenuItem(value: 'edit', child: Text('Edit')),
                              PopupMenuItem(value: 'delete', child: Text('Delete')),
                            ],
                          ),
                        ],
                      ),
                      onTap: () => _openUpsert(initial: r),
                    ),
                  );
                },
              ),
      );
    }

    final listBody = leaserMode
        ? StreamBuilder<List<Map<String, dynamic>>>(
            stream: _supa
                .from('vehicle')
                .stream(primaryKey: ['vehicle_id'])
                .eq('leaser_id', widget.leaserId!.trim())
                .order('vehicle_id', ascending: false),
            builder: (context, snap) {
              if (snap.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('Failed to load: ${snap.error}'),
                  ),
                );
              }
              final rows = (snap.data ?? const [])
                  .map((e) => Map<String, dynamic>.from(e))
                  .toList();
              if (snap.connectionState == ConnectionState.waiting && rows.isEmpty) {
                return const Center(child: CircularProgressIndicator());
              }
              return buildList(rows);
            },
          )
        : FutureBuilder<List<Map<String, dynamic>>>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('Failed to load: ${snap.error}'),
                  ),
                );
              }
              final rows = snap.data ?? const [];
              return buildList(rows);
            },
          );

    if (widget.embedded) {
      return Column(
        children: [
          AdminModuleHeader(
            icon: Icons.directions_car_outlined,
            title: widget.title ?? 'Vehicles',
            subtitle: (widget.leaserId == null)
                ? 'Manage all vehicles'
                : 'Your vehicles',
            actions: [
              if (widget.leaserId == null)
                IconButton(
                  tooltip: 'Manage Locations',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const VehicleLocationAdminPage()),
                  ),
                  icon: const Icon(Icons.place_outlined),
                ),
              IconButton(
                tooltip: 'Refresh',
                onPressed: _refresh,
                icon: const Icon(Icons.refresh_rounded),
              ),
              ...?widget.actions,
            ],
            primaryActions: [
              FilledButton.icon(
                onPressed: () => _openUpsert(),
                icon: const Icon(Icons.add),
                label: const Text('Add vehicle'),
              ),
            ],
          ),
          const Divider(height: 1),
          Expanded(child: listBody),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title ?? 'Vehicles'),
        actions: [
          if (widget.leaserId == null)
            IconButton(
              tooltip: 'Manage Locations',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const VehicleLocationAdminPage()),
              ),
              icon: const Icon(Icons.place_outlined),
            ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
          ...?widget.actions,
        ],
      ),
      body: listBody,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openUpsert(),
        icon: const Icon(Icons.add),
        label: const Text('Add vehicle'),
      ),
    );
  }
}

class _VehicleUpsertPage extends StatefulWidget {
  const _VehicleUpsertPage({this.initial, this.fixedLeaserId});

  final Map<String, dynamic>? initial;

  /// When in leaser-mode, we force vehicle.leaser_id to this value.
  /// Admin/staff mode should pass null.
  final String? fixedLeaserId;

  bool get isEdit => initial != null;

  @override
  State<_VehicleUpsertPage> createState() => _VehicleUpsertPageState();
}

class _VehicleUpsertPageState extends State<_VehicleUpsertPage> {
  SupabaseClient get _supa => Supabase.instance.client;

  final _formKey = GlobalKey<FormState>();
  bool _busy = false;

  final _brand = TextEditingController();
  final _model = TextEditingController();
  final _plate = TextEditingController();
  final _type = TextEditingController();
  final _trans = TextEditingController(text: 'Auto');
  final _fuel = TextEditingController(text: 'Petrol');
  final _seats = TextEditingController(text: '5');
  final _rate = TextEditingController(text: '120');
  // NOTE: some schemas use varchar(10) for location; keep default short.
  final _loc = TextEditingController();
  final _desc = TextEditingController();
  final _leaserId = TextEditingController(text: 'LADMIN');
  String _status = 'Available';

  // Dropdown / validation options (only affects vehicle add/edit UI).
  static const List<String> _vehicleTypes = <String>[
    'SUV',
    'Sedan',
    'Truck',
    'Coupe',
    'Van',
    'Hatchback',
  ];

  static const Map<String, int> _maxSeatsByType = <String, int>{
    'SUV': 5,
    'Sedan': 5,
    'Truck': 15,
    'Coupe': 2,
    'Van': 15,
    'Hatchback': 5,
  };

  static const List<String> _transOptions = <String>['Auto', 'Manual'];
  static const List<String> _fuelOptions = <String>['Petrol', 'Diesel', 'Electric'];

  String _typeValue = _vehicleTypes.first;
  String _transValue = _transOptions.first;
  String _fuelValue = _fuelOptions.first;
  int _seatValue = 5;

  // Location dropdown (loaded from DB table vehicle_location if available).
  List<String> _locationOptions = const [];
  bool _locLoading = false;
  String? _locationValue;
  String? _invalidExistingLocation;


  Future<String?>? _existingPhotoUrlFuture;

  String? _existingId;
  String? _existingPhotoPath;

  final _picker = ImagePicker();
  Uint8List? _photoBytes;
  String? _photoExt; // e.g. jpg/png

  String _s(dynamic v) => v == null ? '' : v.toString();

  @override
  void initState() {
    super.initState();
    // If fixed leaser id provided, enforce it.
    final fixed = (widget.fixedLeaserId ?? '').trim();
    if (fixed.isNotEmpty) {
      _leaserId.text = fixed;
    }
    final init = widget.initial;
    if (init != null) {
      _existingId = _s(init['vehicle_id']).trim();
      _existingPhotoPath = _s(init['vehicle_photo_path']).trim();
      if (fixed.isEmpty) {
        _leaserId.text = _s(init['leaser_id']).trim().isEmpty ? 'LADMIN' : _s(init['leaser_id']).trim();
      }
      _brand.text = _s(init['vehicle_brand']).trim();
      _model.text = _s(init['vehicle_model']).trim();
      _plate.text = _s(init['vehicle_plate_no']).trim();
      _type.text = _s(init['vehicle_type']).trim();
      _trans.text = _s(init['transmission_type']).trim().isEmpty ? 'Auto' : _s(init['transmission_type']).trim();
      _fuel.text = _s(init['fuel_type']).trim().isEmpty ? 'Petrol' : _s(init['fuel_type']).trim();
      _seats.text = _s(init['seat_capacity']).trim().isEmpty ? '5' : _s(init['seat_capacity']).trim();
      _rate.text = _s(init['daily_rate']).trim().isEmpty ? '120' : _s(init['daily_rate']).trim();
      _loc.text = _s(init['vehicle_location']).trim().isEmpty ? '' : _s(init['vehicle_location']).trim();
      _desc.text = _s(init['vehicle_description']).trim();

      final st = _s(init['vehicle_status']).trim();
      if (st.isNotEmpty) _status = st;
    }

    // Setup dropdown values (normalize existing data).
    final rawType = _type.text.trim();
    _typeValue = _firstMatchIgnoreCase(_vehicleTypes, rawType) ?? (rawType.isNotEmpty ? rawType : _vehicleTypes.first);
    _type.text = _typeValue;

    _transValue = _firstMatchIgnoreCase(_transOptions, _trans.text.trim()) ?? _transOptions.first;
    _trans.text = _transValue;

    _fuelValue = _firstMatchIgnoreCase(_fuelOptions, _fuel.text.trim()) ?? _fuelOptions.first;
    _fuel.text = _fuelValue;

    final parsedSeat = int.tryParse(_seats.text.trim());
    _seatValue = parsedSeat ?? (_maxSeatsByType[_typeValue] ?? 5);
    _ensureSeatWithinLimit(setText: true);

    _locationValue = _loc.text.trim().isEmpty ? null : _loc.text.trim();

    if ((_existingPhotoPath ?? '').isNotEmpty) {
      _existingPhotoUrlFuture = _resolveExistingPhotoUrl(_existingPhotoPath!);
    }

    _loadLocations();
  }

  @override
  void dispose() {
    _brand.dispose();
    _model.dispose();
    _plate.dispose();
    _type.dispose();
    _trans.dispose();
    _fuel.dispose();
    _seats.dispose();
    _rate.dispose();
    _loc.dispose();
    _desc.dispose();
    _leaserId.dispose();
    super.dispose();
  }

  String? _firstMatchIgnoreCase(List<String> options, String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;
    for (final o in options) {
      if (o.toLowerCase() == s.toLowerCase()) return o;
    }
    return null;
  }

  List<String> _vehicleTypeOptions() {
    final cur = _typeValue.trim();
    if (cur.isEmpty) return _vehicleTypes;
    if (_vehicleTypes.contains(cur)) return _vehicleTypes;
    return <String>[cur, ..._vehicleTypes];
  }

  int _maxSeatsForType(String type) => _maxSeatsByType[type] ?? 15;

  void _ensureSeatWithinLimit({bool setText = false}) {
    final max = _maxSeatsForType(_typeValue);
    if (_seatValue > max) _seatValue = max;
    if (_seatValue < 1) _seatValue = 1;
    if (setText) _seats.text = _seatValue.toString();
  }

  List<DropdownMenuItem<int>> _seatItems() {
    final max = _maxSeatsForType(_typeValue);
    return List.generate(max, (i) => i + 1)
        .map((n) => DropdownMenuItem(value: n, child: Text('$n')))
        .toList();
  }

  Future<void> _loadLocations() async {
  if (_locLoading) return;
  if (!mounted) return;
  setState(() => _locLoading = true);
  try {
    final rows = await _supa
        .from('vehicle_location')
        .select('location_name, is_active')
        .order('location_name', ascending: true);

    final list = <String>[];
    for (final r in (rows as List)) {
      final m = Map<String, dynamic>.from(r as Map);
      final active = (m['is_active'] as bool?) ?? true;
      final name = (m['location_name'] ?? '').toString().trim();
      if (!active) continue;
      if (name.isEmpty) continue;
      list.add(name);
    }

    final current = (_locationValue ?? '').trim();
    String? invalid;

    // For edit: if existing value is NOT in active list, show it as invalid and force re-select.
    if (widget.isEdit && current.isNotEmpty && !list.contains(current)) {
      invalid = current;
    }

    // Auto default (new vehicle or missing value) to first active location.
    String? nextValue = _locationValue;
    if (invalid != null) {
      nextValue = null;
    } else if ((nextValue ?? '').trim().isEmpty) {
      nextValue = list.isNotEmpty ? list.first : null;
    } else {
      // If value exists but is not in list (new vehicle), force to first active.
      if (!widget.isEdit && list.isNotEmpty && !list.contains(nextValue)) {
        nextValue = list.first;
      }
    }

    if (!mounted) return;
    setState(() {
      _locationOptions = list;
      _invalidExistingLocation = invalid;
      _locationValue = nextValue;
      _loc.text = (nextValue ?? '').trim();
    });
  } catch (_) {
    if (!mounted) return;
    setState(() {
      _locationOptions = const [];
      _invalidExistingLocation = null;
    });
  } finally {
    if (!mounted) return;
    setState(() => _locLoading = false);
  }
}

  Future<String?> _resolveExistingPhotoUrl(String path) async {
    final p = path.trim();
    if (p.isEmpty) return null;
    if (p.startsWith('http://') || p.startsWith('https://')) return p;
    try {
      return await _supa.storage.from('vehicle_photos').createSignedUrl(p, 3600);
    } catch (_) {
      try {
        return _supa.storage.from('vehicle_photos').getPublicUrl(p);
      } catch (_) {
        return null;
      }
    }
  }

  String _genVehicleId10() {
    // Many student schemas use varchar(10) for IDs.
    // Generate a stable 10-char id: V + 9 digits.
    final ms = DateTime.now().millisecondsSinceEpoch;
    final tail = (ms % 1000000000).toString().padLeft(9, '0');
    return 'V$tail';
  }

  Future<void> _pickPhoto(ImageSource source) async {
    try {
      final x = await _picker.pickImage(
        source: source,
        maxWidth: 1600,
        imageQuality: 85,
      );
      if (x == null) return;
      final bytes = await x.readAsBytes();
      final name = x.name;
      final ext = name.contains('.') ? name.split('.').last : 'jpg';
      if (!mounted) return;
      setState(() {
        _photoBytes = bytes;
        _photoExt = ext.toLowerCase();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to pick image: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<String?> _uploadVehiclePhoto({required String vehicleId}) async {
    if (_photoBytes == null || _photoBytes!.isEmpty) return null;
    final ext = (_photoExt ?? 'jpg').toLowerCase();
    final contentType = ext == 'png' ? 'image/png' : 'image/jpeg';
    final path = 'vehicles/$vehicleId-${DateTime.now().millisecondsSinceEpoch}.$ext';
    await _supa.storage.from('vehicle_photos').uploadBinary(
          path,
          _photoBytes!,
          fileOptions: FileOptions(contentType: contentType, upsert: true),
        );
    return path;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final isEdit = widget.isEdit;
      final id = isEdit ? (_existingId ?? '') : _genVehicleId10();
      if (isEdit && id.trim().isEmpty) {
        throw Exception('Missing vehicle_id');
      }

      final hasExistingPhoto = isEdit && (_existingPhotoPath ?? '').trim().isNotEmpty;
      final hasPickedPhoto = _photoBytes != null && _photoBytes!.isNotEmpty;
      if (!hasExistingPhoto && !hasPickedPhoto) {
        throw Exception('Vehicle photo is required.');
      }

      String? photoPath;
      if (hasPickedPhoto) {
        photoPath = await _uploadVehiclePhoto(vehicleId: id);
      }
final forcedLeaserId = (widget.fixedLeaserId ?? '').trim();

      // Location must come from existing active locations (no free text / no default KL).
      if (_locationOptions.isEmpty) {
        throw Exception('No vehicle locations found. Please add at least 1 location in Admin > Vehicles > Manage Locations.');
      }
      final selectedLoc = (_locationValue ?? '').trim();
      if (selectedLoc.isEmpty || !_locationOptions.contains(selectedLoc)) {
        final hint = (_invalidExistingLocation ?? '').trim();
        if (hint.isNotEmpty) {
          throw Exception('Current vehicle location "$hint" is not in the active location list. Please select a valid location.');
        }
        throw Exception('Please select a valid location.');
      }

      final payload = <String, dynamic>{
        'leaser_id': forcedLeaserId.isNotEmpty ? forcedLeaserId : _leaserId.text.trim(),
        'vehicle_brand': _brand.text.trim(),
        'vehicle_model': _model.text.trim(),
        'vehicle_plate_no': _plate.text.trim(),
        'vehicle_type': _typeValue.trim(),
        'transmission_type': _transValue.trim(),
        'fuel_type': _fuelValue.trim(),
        'seat_capacity': _seatValue,
        'daily_rate': num.parse(_rate.text.trim()),
        'vehicle_location': selectedLoc,
        'vehicle_description': _desc.text.trim().isEmpty ? null : _desc.text.trim(),
        'vehicle_status': _status,
      };
      if (photoPath != null) {
        payload['vehicle_photo_path'] = photoPath;
      } else if (isEdit && (_existingPhotoPath ?? '').isNotEmpty) {
        payload['vehicle_photo_path'] = _existingPhotoPath;
      }

      try {
        final isLeaserMode = forcedLeaserId.isNotEmpty;
        if (isLeaserMode) {
          // Preferred: Edge Function (bypass strict RLS safely).
          // Fallback: direct insert/update if the function is not deployed,
          //           ONLY works if you configured an RLS policy for leasers.
          try {
            await LeaserVehicleService(_supa).upsertVehicle(
              isEdit: isEdit,
              vehicleId: id,
              payload: payload,
            );
          } catch (e) {
            final s = e.toString();
            final isNotFound = (e is FunctionException &&
                    (e.status == 404 || (e.details ?? '').toString().contains('NOT_FOUND'))) ||
                s.contains('Requested function was not found') ||
                s.contains('NOT_FOUND') ||
                s.contains('Not Found');
            if (!isNotFound) rethrow;

            // Fallback: direct DB write (requires RLS policy).
            if (isEdit) {
              await _supa.from('vehicle').update(payload).eq('vehicle_id', id);
            } else {
              final insertPayload = <String, dynamic>{'vehicle_id': id, ...payload};
              await _supa.from('vehicle').insert(insertPayload);
            }
          }
        } else {
          if (isEdit) {
            await _supa.from('vehicle').update(payload).eq('vehicle_id', id);
          } else {
            // include id only for insert
            final insertPayload = <String, dynamic>{'vehicle_id': id, ...payload};
            await _supa.from('vehicle').insert(insertPayload);
          }
        }
      } catch (e) {
        // If DB does not have vehicle_photo_path yet, retry without it.
        final msg = e.toString();
        if (msg.contains('vehicle_photo_path') && msg.contains('does not exist')) {
          payload.remove('vehicle_photo_path');
          if (isEdit) {
            await _supa.from('vehicle').update(payload).eq('vehicle_id', id);
          } else {
            final insertPayload = <String, dynamic>{'vehicle_id': id, ...payload};
            await _supa.from('vehicle').insert(insertPayload);
          }
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Saved, but DB has no vehicle_photo_path. Add the column to enable photos.'),
            ),
          );
        } else {
          rethrow;
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.isEdit ? 'Vehicle updated' : 'Vehicle created')),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_prettyError(e)),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }


  String _prettyError(Object e) {
    // Edge Function missing (404)
    if (e is FunctionException) {
      final d = (e.details ?? '').toString();
      if (e.status == 404 || d.contains('NOT_FOUND') || d.contains('Requested function was not found')) {
        return 'Failed: ${e.toString()}\n\n'
            'Tip: Your Supabase Edge Function is not deployed. Deploy: '
            'leaser_upsert_vehicle (and leaser_delete_vehicle) in Supabase, then retry.';
      }
    }
    // RLS forbidden
    if (e is PostgrestException) {
      if ((e.code ?? '').toString() == '42501' || (e.details ?? '').toString().toLowerCase().contains('row-level security')) {
        return 'Failed: ${e.toString()}\n\n'
            'Tip: RLS blocked this write. Either (A) deploy the leaser vehicle Edge Functions, '
            'or (B) add an RLS policy to allow approved leasers to INSERT/UPDATE/DELETE their own vehicles.';
      }
    }
    final s = e.toString();
    return 'Failed: $s';
  }

  @override
  Widget build(BuildContext context) {
    final fixedLeaser = (widget.fixedLeaserId ?? '').trim();
    final isEdit = widget.initial != null;

    return Scaffold(
      appBar: AppBar(title: Text(widget.isEdit ? 'Edit Vehicle' : 'Add Vehicle')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              if (fixedLeaser.isEmpty && !isEdit) ...[
                // Admin/staff creating a NEW vehicle: can choose leaser id
                TextFormField(
                  controller: _leaserId,
                  decoration: const InputDecoration(labelText: 'Leaser ID', hintText: 'LEA-00001'),
                  maxLength: 10,
                  validator: (v) {
                    final s = (v ?? '').trim();
                    if (s.isEmpty) return 'Required';
                    if (s.length > 10) return 'Max 10 characters';
                    return null;
                  },
                ),
                const SizedBox(height: 10),
              ] else ...[
                // Edit mode OR leaser mode: leaser id is locked (read-only)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: Colors.grey.shade100,
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.verified_user_outlined),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Leaser ID: ${fixedLeaser.isEmpty ? _leaserId.text : fixedLeaser}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],

              // Photo
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Vehicle photo (required)', style: TextStyle(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 10),
                      if (_photoBytes != null)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.memory(
                            _photoBytes!,
                            height: 160,
                            width: double.infinity,
                            fit: BoxFit.cover,
                          ),
                        )
                      else if (_existingPhotoUrlFuture != null)
                        FutureBuilder<String?>(
                          future: _existingPhotoUrlFuture,
                          builder: (context, snap) {
                            final url = (snap.data ?? '').toString();
                            if (snap.connectionState != ConnectionState.done) {
                              return Container(
                                height: 160,
                                width: double.infinity,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  color: Colors.grey.shade200,
                                ),
                                child: const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                              );
                            }
                            if (url.trim().isEmpty) {
                              return Container(
                                height: 160,
                                width: double.infinity,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  color: Colors.grey.shade200,
                                ),
                                child: const Icon(Icons.directions_car_rounded, size: 56),
                              );
                            }
                            return ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.network(
                                url,
                                height: 160,
                                width: double.infinity,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  height: 160,
                                  width: double.infinity,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    color: Colors.grey.shade200,
                                  ),
                                  child: const Icon(Icons.directions_car_rounded, size: 56),
                                ),
                              ),
                            );
                          },
                        )
                      else
                        Container(
                          height: 160,
                          width: double.infinity,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            color: Colors.grey.shade200,
                          ),
                          child: const Icon(Icons.directions_car_rounded, size: 56),
                        ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _busy ? null : () => _pickPhoto(ImageSource.gallery),
                              icon: const Icon(Icons.photo_library_outlined),
                              label: const Text('Gallery'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _busy ? null : () => _pickPhoto(ImageSource.camera),
                              icon: const Icon(Icons.camera_alt_outlined),
                              label: const Text('Camera'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Tip: to save photo path in DB, add column vehicle_photo_path (text) and create Storage bucket vehicle_photos.',
                        style: TextStyle(color: Colors.grey.shade700, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _brand,
                      decoration: const InputDecoration(labelText: 'Brand'),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: _model,
                      decoration: const InputDecoration(labelText: 'Model'),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _plate,
                decoration: const InputDecoration(labelText: 'Plate No'),
                maxLength: 10,
                validator: (v) {
                  final s = (v ?? '').trim();
                  if (s.isEmpty) return 'Required';
                  if (s.length > 10) return 'Max 10 characters';
                  return null;
                },
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: _typeValue,
                decoration: const InputDecoration(labelText: 'Vehicle Type'),
                items: _vehicleTypeOptions().map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                onChanged: (v) {
                  final nv = (v ?? '').trim();
                  if (nv.isEmpty) return;
                  setState(() {
                    _typeValue = nv;
                    _type.text = nv;
                    // Enforce seat max by vehicle type
                    _ensureSeatWithinLimit(setText: true);
                  });
                },
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _transValue,
                      decoration: const InputDecoration(labelText: 'Transmission'),
                      items: _transOptions.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                      onChanged: (v) {
                        final nv = (v ?? '').trim();
                        if (nv.isEmpty) return;
                        setState(() {
                          _transValue = nv;
                          _trans.text = nv;
                        });
                      },
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _fuelValue,
                      decoration: const InputDecoration(labelText: 'Fuel'),
                      items: _fuelOptions.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                      onChanged: (v) {
                        final nv = (v ?? '').trim();
                        if (nv.isEmpty) return;
                        setState(() {
                          _fuelValue = nv;
                          _fuel.text = nv;
                        });
                      },
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      value: _seatValue,
                      decoration: const InputDecoration(labelText: 'Seat Capacity'),
                      items: _seatItems(),
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() {
                          _seatValue = v;
                          _ensureSeatWithinLimit(setText: true);
                        });
                      },
                      validator: (v) {
                        final n = v ?? 0;
                        final max = _maxSeatsForType(_typeValue);
                        if (n <= 0) return 'Invalid';
                        if (n > max) return 'Max $max for $_typeValue';
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: _rate,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Daily Rate (RM)'),
                      validator: (v) {
                        final n = num.tryParse((v ?? '').trim());
                        if (n == null || n <= 0) return 'Invalid';
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              
if (_locationOptions.isNotEmpty)
  DropdownButtonFormField<String>(
    value: (_locationValue != null && _locationOptions.contains(_locationValue)) ? _locationValue : null,
    decoration: InputDecoration(
      labelText: 'Location',
      helperText: (_invalidExistingLocation ?? '').trim().isNotEmpty
          ? 'Current location "${_invalidExistingLocation!}" is not in the active list. Please select a valid location.'
          : null,
      suffixIcon: _locLoading
          ? const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            )
          : null,
    ),
    items: _locationOptions.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
    hint: const Text('Select location'),
    onChanged: (v) {
      final nv = (v ?? '').trim();
      if (nv.isEmpty) return;
      setState(() {
        _locationValue = nv;
        _loc.text = nv;
        _invalidExistingLocation = null;
      });
    },
    validator: (v) {
      final t = (v ?? '').trim();
      if (t.isEmpty) return 'Required';
      if (!_locationOptions.contains(t)) return 'Select a valid location';
      return null;
    },
  )
else
  TextFormField(
    controller: _loc,
    readOnly: true,
    decoration: const InputDecoration(
      labelText: 'Location',
      hintText: 'Add locations first (Admin > Vehicles > Manage Locations)',
    ),
    validator: (_) => 'Please add at least 1 location first',
  ),
const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: _status,
                decoration: const InputDecoration(labelText: 'Status'),
                items: const [
                  DropdownMenuItem(value: 'Available', child: Text('Available')),
                  // Keep values <= 10 chars for varchar(10) schemas.
                  DropdownMenuItem(value: 'Unavail', child: Text('Unavailable')),
                  DropdownMenuItem(value: 'Maintain', child: Text('Maintenance')),
                ],
                onChanged: (v) => setState(() => _status = v ?? 'Available'),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _desc,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Description (optional)'),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _busy ? null : _save,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
