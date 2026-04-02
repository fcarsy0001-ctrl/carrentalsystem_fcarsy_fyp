import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import '../services/rentable_vehicle_service.dart';
import '../services/road_tax_monitor_service.dart';
import 'product_page.dart';

class VehicleBrowsePage extends StatefulWidget {
  const VehicleBrowsePage({super.key});

  @override
  State<VehicleBrowsePage> createState() => _VehicleBrowsePageState();
}

class _VehicleBrowsePageState extends State<VehicleBrowsePage> {
  SupabaseClient get _supa => Supabase.instance.client;

  final _searchCtrl = TextEditingController();

  DateTime? _selectedDate;

  String? _area;
  String? _brand;
  String? _type;
  String _status = 'Available';
  double? _priceFrom;
  double? _priceTo;

  late Future<List<_BrowseVehicle>> _vehiclesFuture;

  @override
  void initState() {
    super.initState();
    _vehiclesFuture = _loadVehicles();
    _searchCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<List<_BrowseVehicle>> _loadVehicles() async {
    final rentableService = RentableVehicleService(_supa);
    await RoadTaxMonitorService(_supa).syncRoadTaxStates().catchError((_) {});
    final activeLocations = await rentableService.fetchActiveLocationNames();
    final blockedVehicleIds = await rentableService.fetchBlockedVehicleIds();

    final rows = await _supa
        .from('vehicle')
        .select()
        .eq('vehicle_status', 'Available')
        .order('vehicle_id', ascending: false);

    final list = (rows as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .where((row) => rentableService.isRentableVehicle(row, activeLocations, blockedVehicleIds))
        .map(_BrowseVehicle.fromMap)
        .toList();
    return list;
  }

  String? _vehiclePhotoPublicUrl(String? path) {
    if (path == null || path.trim().isEmpty) return null;
    final safe = path.replaceFirst(RegExp(r'^/+'), '');
    return '${SupabaseConfig.supabaseUrl}/storage/v1/object/public/vehicle_photos/$safe';
  }

  void _clearFilters() {
    setState(() {
      _selectedDate = null;
      _area = null;
      _brand = null;
      _type = null;
      _status = 'Available';
      _priceFrom = null;
      _priceTo = null;
    });
  }

  bool get _hasAnyFilter {
    return _selectedDate != null ||
        _area != null ||
        _brand != null ||
        _type != null ||
        (_status.isNotEmpty && _status != 'Available') ||
        _priceFrom != null ||
        _priceTo != null;
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 2, 12, 31),
      initialDate: _selectedDate ?? DateTime(now.year, now.month, now.day),
    );
    if (picked == null) return;
    setState(() => _selectedDate = picked);
  }

  Future<void> _openFiltersSheet(List<_BrowseVehicle> all) async {
    final areas = _unique(all.map((v) => v.location).where((e) => e.trim().isNotEmpty));
    final brands = _unique(all.map((v) => v.brand).where((e) => e.trim().isNotEmpty));
    final types = _unique(all.map((v) => v.type).where((e) => e.trim().isNotEmpty));

    final fromCtrl = TextEditingController(text: _priceFrom?.toStringAsFixed(0) ?? '');
    final toCtrl = TextEditingController(text: _priceTo?.toStringAsFixed(0) ?? '');

    String? area = _area;
    String? brand = _brand;
    String? type = _type;
    String status = _status;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 8,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: StatefulBuilder(
            builder: (ctx, setSheet) {
              return SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Filter',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 12),

                    _DropdownField(
                      label: 'Area',
                      value: area,
                      items: areas,
                      onChanged: (v) => setSheet(() => area = v),
                    ),
                    const SizedBox(height: 10),

                    _DropdownField(
                      label: 'Car Brand',
                      value: brand,
                      items: brands,
                      onChanged: (v) => setSheet(() => brand = v),
                    ),
                    const SizedBox(height: 10),

                    _DropdownField(
                      label: 'Type',
                      value: type,
                      items: types,
                      onChanged: (v) => setSheet(() => type = v),
                    ),
                    const SizedBox(height: 10),

                    _DropdownField(
                      label: 'Status',
                      value: status,
                      // UI requirement includes status; since we query Available only,
                      // keep it single-option for now.
                      items: const ['Available'],
                      onChanged: (v) => setSheet(() => status = v ?? 'Available'),
                    ),
                    const SizedBox(height: 10),

                    Row(
                      children: [
                        Expanded(
                          child: _NumberField(
                            label: 'Price From (RM/day)',
                            controller: fromCtrl,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _NumberField(
                            label: 'Price To (RM/day)',
                            controller: toCtrl,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              area = null;
                              brand = null;
                              type = null;
                              status = 'Available';
                              fromCtrl.text = '';
                              toCtrl.text = '';
                              setSheet(() {});
                            },
                            child: const Text('Clear filter'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: () {
                              double? pf;
                              double? pt;
                              if (fromCtrl.text.trim().isNotEmpty) {
                                pf = double.tryParse(fromCtrl.text.trim());
                              }
                              if (toCtrl.text.trim().isNotEmpty) {
                                pt = double.tryParse(toCtrl.text.trim());
                              }
                              setState(() {
                                _area = area;
                                _brand = brand;
                                _type = type;
                                _status = status;
                                _priceFrom = pf;
                                _priceTo = pt;
                              });
                              Navigator.of(ctx).pop();
                            },
                            child: const Text('Apply'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                  ],
                ),
              );
            },
          ),
        );
      },
    );

    fromCtrl.dispose();
    toCtrl.dispose();
  }

  List<_BrowseVehicle> _applyAllFilters(List<_BrowseVehicle> all) {
    final q = _searchCtrl.text.trim().toLowerCase();

    return all.where((v) {
      // text search
      if (q.isNotEmpty) {
        final hay = '${v.brand} ${v.model} ${v.type} ${v.location}'.toLowerCase();
        if (!hay.contains(q)) return false;
      }

      // date selection (UI requirement). Actual availability-by-date requires a booking calendar.
      // For now, we keep the selection but do not exclude items based on it.

      if (_area != null && _area!.trim().isNotEmpty && v.location != _area) return false;
      if (_brand != null && _brand!.trim().isNotEmpty && v.brand != _brand) return false;
      if (_type != null && _type!.trim().isNotEmpty && v.type != _type) return false;
      if (_status.trim().isNotEmpty && v.status != _status) return false;

      final rate = v.dailyRate;
      if (_priceFrom != null && rate < _priceFrom!) return false;
      if (_priceTo != null && rate > _priceTo!) return false;

      return true;
    }).toList();
  }

  List<String> _unique(Iterable<String> values) {
    final set = <String>{};
    for (final v in values) {
      final s = v.trim();
      if (s.isEmpty) continue;
      set.add(s);
    }
    final list = set.toList()..sort();
    return list;
  }

  String _fmtDate(DateTime d) {
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '${d.year}-$mm-$dd';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Browse Cars'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: FutureBuilder<List<_BrowseVehicle>>(
            future: _vehiclesFuture,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return Text('Failed to load vehicles: ${snap.error}');
              }
              final all = snap.data ?? const [];
              final filtered = _applyAllFilters(all);

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SearchField(
                    controller: _searchCtrl,
                    hintText: 'Search by model, location, typeâ€¦',
                    onClear: () {
                      _searchCtrl.clear();
                      FocusScope.of(context).unfocus();
                    },
                  ),
                  const SizedBox(height: 12),

                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _pickDate,
                          icon: const Icon(Icons.calendar_month_outlined),
                          label: Text(
                            _selectedDate == null
                                ? 'Select date'
                                : 'Date: ${_fmtDate(_selectedDate!)}',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _openFiltersSheet(all),
                          icon: const Icon(Icons.tune_rounded),
                          label: const Text('Filter'),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Available cars: ${filtered.length}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      if (_hasAnyFilter)
                        TextButton(
                          onPressed: _clearFilters,
                          child: const Text('Clear filter'),
                        ),
                    ],
                  ),

                  if (_selectedDate != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        'Note: Date filtering requires booking calendar integration.\nCurrently showing cars with status "Available".',
                        style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                      ),
                    ),

                  const SizedBox(height: 6),

                  Expanded(
                    child: filtered.isEmpty
                        ? Center(
                      child: Text(
                        'No cars match your search / filters.',
                        style: TextStyle(color: Colors.grey.shade700),
                      ),
                    )
                        : ListView.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, i) {
                        final v = filtered[i];
                        return _BrowseVehicleTile(
                          vehicle: v,
                          photoUrl: _vehiclePhotoPublicUrl(v.photoPath),
                          onTap: () {
                            Navigator.of(context).push(
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
                          },
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _BrowseVehicle {
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

  const _BrowseVehicle({
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

  factory _BrowseVehicle.fromMap(Map<String, dynamic> m) {
    return _BrowseVehicle(
      vehicleId: (m['vehicle_id'] ?? '').toString(),
      brand: (m['vehicle_brand'] ?? '').toString(),
      model: (m['vehicle_model'] ?? '').toString(),
      type: (m['vehicle_type'] ?? '').toString(),
      plate: (m['vehicle_plate_no'] ?? '').toString(),
      transmission: (m['transmission_type'] ?? '').toString(),
      fuel: (m['fuel_type'] ?? '').toString(),
      seats: int.tryParse((m['seat_capacity'] ?? '0').toString()) ?? 0,
      dailyRate: double.tryParse((m['daily_rate'] ?? '0').toString()) ?? 0,
      location: (m['vehicle_location'] ?? '').toString(),
      status: (m['vehicle_status'] ?? '').toString(),
      photoPath: (m['vehicle_photo_path'] as String?),
    );
  }
}

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final VoidCallback onClear;

  const _SearchField({
    required this.controller,
    required this.hintText,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: hintText,
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: controller.text.trim().isEmpty
            ? null
            : IconButton(
          onPressed: onClear,
          icon: const Icon(Icons.close_rounded),
          tooltip: 'Clear',
        ),
        filled: true,
        fillColor: Colors.grey.shade100,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

class _DropdownField extends StatelessWidget {
  final String label;
  final String? value;
  final List<String> items;
  final ValueChanged<String?> onChanged;

  const _DropdownField({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: Colors.grey.shade100,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          isExpanded: true,
          value: value,
          hint: const Text('Any'),
          items: [
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('Any'),
            ),
            ...items.map(
                  (e) => DropdownMenuItem<String?>(
                value: e,
                child: Text(e),
              ),
            ),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _NumberField extends StatelessWidget {
  final String label;
  final TextEditingController controller;

  const _NumberField({
    required this.label,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: Colors.grey.shade100,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

class _BrowseVehicleTile extends StatelessWidget {
  final _BrowseVehicle vehicle;
  final String? photoUrl;
  final VoidCallback onTap;

  const _BrowseVehicleTile({
    required this.vehicle,
    required this.photoUrl,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Ink(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 86,
                  height: 68,
                  color: Colors.grey.shade100,
                  child: photoUrl == null
                      ? const Icon(Icons.directions_car_filled_outlined)
                      : Image.network(photoUrl!, fit: BoxFit.cover),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      vehicle.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${vehicle.type} â€¢ ${vehicle.location}',
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'RM${vehicle.dailyRate.toStringAsFixed(0)}/day â€¢ ${vehicle.seats} seats',
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}


