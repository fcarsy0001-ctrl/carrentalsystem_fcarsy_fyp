import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_ai/firebase_ai.dart';

class VehicleAiSuggestion {
  final String? brand;
  final String? model;
  final int? year;
  final String? vehicleType;
  final String? transmissionType;
  final String? fuelType;
  final int? seatCapacity;
  final String? notes;

  const VehicleAiSuggestion({
    this.brand,
    this.model,
    this.year,
    this.vehicleType,
    this.transmissionType,
    this.fuelType,
    this.seatCapacity,
    this.notes,
  });

  factory VehicleAiSuggestion.fromJson(Map<String, dynamic> json) {
    String? asString(dynamic value) {
      final text = value?.toString().trim();
      return (text == null || text.isEmpty) ? null : text;
    }

    dynamic pickValue(List<String> keys) {
      for (final key in keys) {
        if (json.containsKey(key) && json[key] != null) {
          return json[key];
        }
      }
      return null;
    }

    int? asInt(dynamic value) {
      if (value == null) return null;
      if (value is int) return value;
      if (value is num) return value.toInt();
      final raw = value.toString().trim();
      final direct = int.tryParse(raw);
      if (direct != null) return direct;
      final match = RegExp(r'(\d{1,2})').firstMatch(raw);
      if (match != null) {
        return int.tryParse(match.group(1)!);
      }
      return null;
    }

    final vehicleType = _normalizeVehicleType(
      asString(pickValue(['vehicleType', 'vehicle_type', 'type', 'bodyType', 'body_type'])),
    );

    final transmissionType = _normalizeTransmission(
      asString(pickValue(['transmissionType', 'transmission_type', 'transmission', 'gearbox'])),
    );

    final fuelType = _normalizeFuel(
      asString(pickValue(['fuelType', 'fuel_type', 'fuel', 'engineType', 'engine_type'])),
    );

    final seatCapacity = _normalizeSeatCapacity(
      pickValue(['seatCapacity', 'seat_capacity', 'seatingCapacity', 'seating_capacity', 'seating', 'seats', 'seat']),
      vehicleType: vehicleType,
    );

    return VehicleAiSuggestion(
      brand: asString(pickValue(['brand', 'make'])),
      model: asString(pickValue(['model', 'vehicleModel'])),
      year: asInt(pickValue(['year', 'vehicleYear', 'manufactureYear', 'manufactured_year'])),
      vehicleType: vehicleType,
      transmissionType: transmissionType,
      fuelType: fuelType,
      seatCapacity: seatCapacity,
      notes: asString(pickValue(['notes', 'remark', 'remarks'])),
    );
  }

  static String? _normalizeVehicleType(String? value) {
    if (value == null || value.isEmpty) return null;
    final raw = value.toLowerCase();
    if (raw.contains('sedan') || raw.contains('saloon')) return 'Sedan';
    if (raw.contains('suv') || raw.contains('crossover')) return 'SUV';
    if (raw.contains('hatch')) return 'Hatchback';
    if (raw.contains('truck') || raw.contains('pickup') || raw.contains('pick-up')) return 'Truck';
    if (raw.contains('coupe')) return 'Coupe';
    if (raw.contains('van') || raw.contains('mpv') || raw.contains('minivan') || raw.contains('mini van')) {
      return 'Van';
    }
    for (final item in const ['Sedan', 'SUV', 'Hatchback', 'Truck', 'Coupe', 'Van']) {
      if (item.toLowerCase() == raw) return item;
    }
    return null;
  }

  static String? _normalizeTransmission(String? value) {
    if (value == null || value.isEmpty) return null;
    final raw = value.toLowerCase();
    if (raw.contains('auto')) return 'Auto';
    if (raw.contains('manual')) return 'Manual';
    return null;
  }

  static String? _normalizeFuel(String? value) {
    if (value == null || value.isEmpty) return null;
    final raw = value.toLowerCase();
    if (raw.contains('petrol') || raw.contains('gasoline')) return 'Petrol';
    if (raw.contains('diesel')) return 'Diesel';
    if (raw.contains('electric') || raw.contains('ev')) return 'Electric';
    if (raw.contains('hybrid')) return 'Hybrid';
    return null;
  }

  static int? _normalizeSeatCapacity(dynamic value, {String? vehicleType}) {
    int? parse(dynamic source) {
      if (source == null) return null;
      if (source is int) return source;
      if (source is num) return source.toInt();
      final raw = source.toString().trim().toLowerCase();
      if (raw.isEmpty) return null;
      final direct = int.tryParse(raw);
      if (direct != null) return direct;
      final match = RegExp(r'(\d{1,2})').firstMatch(raw);
      if (match != null) {
        return int.tryParse(match.group(1)!);
      }
      return null;
    }

    final explicit = parse(value);
    if (explicit != null && explicit > 0) return explicit;

    switch (vehicleType) {
      case 'Coupe':
        return 2;
      case 'Sedan':
      case 'SUV':
      case 'Hatchback':
        return 5;
      case 'Truck':
      case 'Van':
        return 15;
      default:
        return null;
    }
  }
}

class VehicleAiService {
  static const String _modelName = 'gemini-2.5-flash';

  late final GenerativeModel _model;

  VehicleAiService() {
    _model = FirebaseAI.googleAI().generativeModel(
      model: _modelName,
      generationConfig: GenerationConfig(temperature: 0),
    );
  }

  Future<VehicleAiSuggestion> detectVehicleFromPhoto({
    required Uint8List imageBytes,
    required String mimeType,
  }) async {
    const prompt = r'''You are helping fill a vehicle registration form from a vehicle photo.

Return JSON only. Do not return markdown.

Detect these fields when visible or reasonably inferable:
- brand
- model
- year
- vehicleType
- transmissionType
- fuelType
- seatCapacity
- notes

Rules:
- Focus only on the main vehicle in the image.
- If unsure, leave the field null or omit it.
- Allowed vehicleType values: Sedan, SUV, Hatchback, Truck, Coupe, Van
- Allowed transmissionType values: Auto, Manual
- Allowed fuelType values: Petrol, Diesel, Electric, Hybrid
- seatCapacity must be a number.
- If seatCapacity is not directly visible, infer a sensible seat count from the vehicle type.
- Use these defaults when you need to infer seatCapacity: Coupe=2, Sedan=5, SUV=5, Hatchback=5, Truck=15, Van=15.
- year must be a 4-digit number.
- notes should be short and explain uncertainty if needed.

Example output:
{
  "brand": "Toyota",
  "model": "Vios",
  "year": 2022,
  "vehicleType": "Sedan",
  "transmissionType": "Auto",
  "fuelType": "Petrol",
  "seatCapacity": 5,
  "notes": "Year and fuel type are estimated from the exterior."
}''';

    final response = await _model.generateContent([
      Content.multi([
        TextPart(prompt),
        InlineDataPart(mimeType, imageBytes),
      ]),
    ]);

    final raw = (response.text ?? '').trim();
    if (raw.isEmpty) {
      throw Exception('AI returned an empty response.');
    }

    final decoded = jsonDecode(_extractJson(raw));
    if (decoded is! Map<String, dynamic>) {
      throw Exception('AI returned invalid JSON.');
    }

    return VehicleAiSuggestion.fromJson(decoded);
  }

  String _extractJson(String raw) {
    final trimmed = raw.trim();
    if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
      return trimmed;
    }

    final fenced = RegExp(r'```(?:json)?\s*(\{[\s\S]*\})\s*```', caseSensitive: false)
        .firstMatch(trimmed);
    if (fenced != null) {
      return fenced.group(1)!;
    }

    final start = trimmed.indexOf('{');
    final end = trimmed.lastIndexOf('}');
    if (start != -1 && end != -1 && end > start) {
      return trimmed.substring(start, end + 1);
    }

    throw Exception('AI response was not JSON.');
  }
}
