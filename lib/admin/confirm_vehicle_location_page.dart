import 'package:flutter/material.dart';

import 'update_vehicle_location_page.dart';

class ConfirmVehicleLocationPage extends StatefulWidget {
  const ConfirmVehicleLocationPage({super.key, required this.record});

  final Map<String, dynamic> record;

  @override
  State<ConfirmVehicleLocationPage> createState() => _ConfirmVehicleLocationPageState();
}

class _ConfirmVehicleLocationPageState extends State<ConfirmVehicleLocationPage> {
  late Map<String, dynamic> _record;

  String _s(dynamic value) => value == null ? '' : value.toString().trim();

  @override
  void initState() {
    super.initState();
    _record = Map<String, dynamic>.from(widget.record);
  }

  Future<void> _openUpdate() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => UpdateVehicleLocationPage(record: _record),
      ),
    );
    if (changed == true && mounted) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final title = '${_s(_record['vehicle_brand'])} ${_s(_record['vehicle_model'])}'.trim();
    final plate = _s(_record['vehicle_plate_no']);
    final branch = _s(_record['vehicle_location']);

    return Scaffold(
      appBar: AppBar(title: const Text('Confirm Vehicle Location')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 22),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: cs.outlineVariant.withOpacity(0.55)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: cs.primaryContainer,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        alignment: Alignment.center,
                        child: Icon(Icons.directions_car_outlined, color: cs.onPrimaryContainer),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(plate.isEmpty ? _s(_record['vehicle_id']) : plate, style: const TextStyle(fontWeight: FontWeight.w900)),
                            const SizedBox(height: 4),
                            Text(title.isEmpty ? 'Vehicle' : title, style: TextStyle(color: cs.onSurfaceVariant)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text('Current Branch', style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: branch.isEmpty ? Colors.orange.withOpacity(0.10) : cs.primaryContainer.withOpacity(0.45),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: branch.isEmpty ? Colors.orange.withOpacity(0.30) : cs.primary.withOpacity(0.18),
                      ),
                    ),
                    child: Text(
                      branch.isEmpty ? 'No branch assigned' : branch,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: branch.isEmpty ? Colors.orange.shade900 : cs.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _openUpdate,
                    icon: const Icon(Icons.near_me_outlined),
                    label: const Text('Update Branch Location'),
                    style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
