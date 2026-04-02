import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/vehicle_onboarding_service.dart';
import '../services/vehicle_ai_service.dart';

class VehicleRegistrationPage extends StatefulWidget {
  const VehicleRegistrationPage({
    super.key,
    required this.isAdminMode,
    this.fixedLeaserId,
    this.initial,
  });

  final bool isAdminMode;
  final String? fixedLeaserId;
  final Map<String, dynamic>? initial;

  @override
  State<VehicleRegistrationPage> createState() => _VehicleRegistrationPageState();
}

class _VehicleRegistrationPageState extends State<VehicleRegistrationPage> {
  final _formKey = GlobalKey<FormState>();
  final _picker = ImagePicker();

  late final VehicleOnboardingService _service;
  late final VehicleAiService _vehicleAiService;

  final _leaserIdController = TextEditingController();
  final _plateController = TextEditingController();
  final _brandController = TextEditingController();
  final _modelController = TextEditingController();
  final _yearController = TextEditingController();
  final _mileageController = TextEditingController();
  final _seatController = TextEditingController(text: '5');
  final _rateController = TextEditingController(text: '120');
  final _descriptionController = TextEditingController();
  final _remarksController = TextEditingController();

  bool _saving = false;
  bool _aiFilling = false;

  String _vehicleType = 'Sedan';
  String _transmissionType = 'Auto';
  String _fuelType = 'Petrol';
  String _conditionStatus = 'Good';
  List<String> _locations = const [];
  String? _selectedLocation;
  DateTime? _roadTaxExpiryDate;

  Uint8List? _photoBytes;
  String? _photoExt;
  String? _existingPhotoPath;
  String? _existingPhotoUrl;

  Uint8List? _docsBytes;
  String? _docsExt;
  String? _docsFileName;
  String? _existingDocsPath;
  String? _aiNotes;
  VehicleAiSuggestion? _lastAutoFillSuggestion;
  String? _lastAutoFillPhotoKey;

  bool get _isEdit => widget.initial != null;

  static const _vehicleTypes = ['Sedan', 'SUV', 'Hatchback', 'Truck', 'Coupe', 'Van'];
  static const _transmissionTypes = ['Auto', 'Manual'];
  static const _fuelTypes = ['Petrol', 'Diesel', 'Electric', 'Hybrid'];
  static const _conditionTypes = ['Excellent', 'Good', 'Fair', 'Poor', 'Pending'];

  String _s(dynamic value) => value == null ? '' : value.toString().trim();

  int _i(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString()) ?? 0;
  }

  @override
  void initState() {
    super.initState();
    _service = VehicleOnboardingService(Supabase.instance.client);
    _vehicleAiService = VehicleAiService();

    final fixedLeaserId = (widget.fixedLeaserId ?? '').trim();
    if (fixedLeaserId.isNotEmpty) {
      _leaserIdController.text = fixedLeaserId;
    }

    final initial = widget.initial;
    if (initial != null) {
      if (fixedLeaserId.isEmpty) {
        _leaserIdController.text = _s(initial['leaser_id']);
      }
      _plateController.text = _s(initial['vehicle_plate_no']);
      _brandController.text = _s(initial['vehicle_brand']);
      _modelController.text = _s(initial['vehicle_model']);
      final year = _i(initial['vehicle_year']);
      _yearController.text = year <= 0 ? '' : '$year';
      final mileage = _i(initial['mileage_km']);
      _mileageController.text = mileage <= 0 ? '' : '$mileage';
      final seats = _i(initial['seat_capacity']);
      _seatController.text = seats <= 0 ? '5' : '$seats';
      final rate = initial['daily_rate'];
      _rateController.text = rate == null ? '120' : rate.toString();
      _descriptionController.text = _s(initial['vehicle_description']);
      _remarksController.text = _s(initial['remarks']);
      _vehicleType = _matchOption(_vehicleTypes, _s(initial['vehicle_type']), _vehicleType);
      _transmissionType = _matchOption(_transmissionTypes, _s(initial['transmission_type']), _transmissionType);
      _fuelType = _matchOption(_fuelTypes, _s(initial['fuel_type']), _fuelType);
      _conditionStatus = _matchOption(_conditionTypes, _s(initial['condition_status']), _conditionStatus);
      _selectedLocation = _s(initial['vehicle_location']).isEmpty ? null : _s(initial['vehicle_location']);
      _roadTaxExpiryDate = DateTime.tryParse(_s(initial['road_tax_expiry_date']));
      _existingPhotoPath = _s(initial['vehicle_photo_path']);
      _existingDocsPath = _s(initial['supporting_docs_url']);
      _docsFileName = _friendlyDocumentName(_existingDocsPath);
    }

    _loadLocations();
    _loadExistingAssets();
  }

  @override
  void dispose() {
    _leaserIdController.dispose();
    _plateController.dispose();
    _brandController.dispose();
    _modelController.dispose();
    _yearController.dispose();
    _mileageController.dispose();
    _seatController.dispose();
    _rateController.dispose();
    _descriptionController.dispose();
    _remarksController.dispose();
    super.dispose();
  }

  String _matchOption(List<String> options, String raw, String fallback) {
    for (final option in options) {
      if (option.toLowerCase() == raw.toLowerCase()) return option;
    }
    return fallback;
  }

  String _dateLabel(DateTime? value) {
    if (value == null) return 'Select road tax expiry date';
    return '${value.day}/${value.month}/${value.year}';
  }

  Future<void> _pickRoadTaxExpiryDate() async {
    final now = DateTime.now();
    final initialDate = _roadTaxExpiryDate ?? now;
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year - 2, 1, 1),
      lastDate: DateTime(now.year + 10, 12, 31),
      initialDate: initialDate,
    );
    if (picked == null || !mounted) return;
    setState(() => _roadTaxExpiryDate = picked);
  }

  String _friendlyDocumentName(String? path) {
    final raw = _s(path);
    if (raw.isEmpty) return '';
    final normalized = raw.replaceAll('\\\\', '/');
    final last = normalized.split('/').last.trim();
    return last.isEmpty ? raw : last;
  }

  Future<void> _loadLocations() async {
    final locations = await _service.fetchLocations();
    if (!mounted) return;
    setState(() {
      _locations = locations;
      if ((_selectedLocation ?? '').trim().isEmpty && locations.isNotEmpty) {
        _selectedLocation = locations.first;
      } else if ((_selectedLocation ?? '').trim().isNotEmpty && !locations.contains(_selectedLocation)) {
        _selectedLocation = locations.isNotEmpty ? locations.first : null;
      }
    });
  }

  Future<void> _loadExistingAssets() async {
    if (_existingPhotoPath != null && _existingPhotoPath!.isNotEmpty) {
      _existingPhotoUrl = await _service.createSignedAssetUrl(_existingPhotoPath);
    }
    if ((_existingDocsPath ?? '').trim().isNotEmpty) {
      _docsFileName = _friendlyDocumentName(_existingDocsPath);
    }
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _pickPhoto(ImageSource source) async {
    final file = await _picker.pickImage(
      source: source,
      maxWidth: 1600,
      imageQuality: 85,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    setState(() {
      _photoBytes = bytes;
      _photoExt = file.name.contains('.') ? file.name.split('.').last.toLowerCase() : 'jpg';
      _lastAutoFillSuggestion = null;
      _lastAutoFillPhotoKey = null;
      _aiNotes = null;
    });
  }

  Future<void> _pickDocumentFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
        allowMultiple: false,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.single;
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) {
        throw Exception('Unable to read selected PDF file.');
      }
      if (!mounted) return;
      setState(() {
        _docsBytes = bytes;
        _docsExt = (file.extension ?? 'pdf').toLowerCase();
        _docsFileName = file.name;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to pick PDF file: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  String _photoMimeType() {
    switch ((_photoExt ?? '').toLowerCase()) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      default:
        return 'image/jpeg';
    }
  }

  String _buildPhotoKey(Uint8List bytes) {
    var hash = 17;
    for (final value in bytes) {
      hash = 37 * hash + value;
      hash &= 0x7fffffff;
    }
    return '${bytes.length}:$hash';
  }

  void _applyAiSuggestion(VehicleAiSuggestion result) {
    if ((result.brand ?? '').trim().isNotEmpty) {
      _brandController.text = result.brand!.trim();
    }
    if ((result.model ?? '').trim().isNotEmpty) {
      _modelController.text = result.model!.trim();
    }
    if (result.year != null && result.year! > 0) {
      _yearController.text = result.year.toString();
    }
    if ((result.vehicleType ?? '').trim().isNotEmpty) {
      _vehicleType = result.vehicleType!;
    }
    if ((result.transmissionType ?? '').trim().isNotEmpty) {
      _transmissionType = result.transmissionType!;
    }
    if ((result.fuelType ?? '').trim().isNotEmpty) {
      _fuelType = result.fuelType!;
    }
    if (result.seatCapacity != null && result.seatCapacity! > 0) {
      _seatController.text = result.seatCapacity.toString();
    }
    _aiNotes = result.notes;
  }

  Future<void> _runAiAutoFill() async {
    if (_aiFilling) return;

    if (_photoBytes == null || _photoBytes!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please upload a vehicle photo first.')),
      );
      return;
    }

    final photoKey = _buildPhotoKey(_photoBytes!);

    if (_lastAutoFillPhotoKey == photoKey && _lastAutoFillSuggestion != null) {
      setState(() {
        _applyAiSuggestion(_lastAutoFillSuggestion!);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Auto fill applied from the same saved photo result.'),
        ),
      );
      return;
    }

    setState(() => _aiFilling = true);

    try {
      final result = await _vehicleAiService.detectVehicleFromPhoto(
        imageBytes: _photoBytes!,
        mimeType: _photoMimeType(),
      );

      if (!mounted) return;

      setState(() {
        _lastAutoFillPhotoKey = photoKey;
        _lastAutoFillSuggestion = result;
        _applyAiSuggestion(result);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Auto fill applied. Please verify before submit.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Auto fill failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _aiFilling = false);
      }
    }
  }

  Future<void> _showPhotoSourceSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined),
                  title: const Text('Choose from gallery'),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _pickPhoto(ImageSource.gallery);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.camera_alt_outlined),
                  title: const Text('Take photo'),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _pickPhoto(ImageSource.camera);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_saving) return;

    if (_roadTaxExpiryDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select the road tax expiry date.')),
      );
      return;
    }

    if ((_selectedLocation ?? '').trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add or select a vehicle location first.')),
      );
      return;
    }

    final hasPhoto = (_photoBytes != null && _photoBytes!.isNotEmpty) || (_existingPhotoPath ?? '').isNotEmpty;
    final hasDocs = (_docsBytes != null && _docsBytes!.isNotEmpty) || (_existingDocsPath ?? '').isNotEmpty;
    if (!hasPhoto || !hasDocs) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vehicle photo and supporting document are required.')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final saved = await _service.saveVehicle(
        isAdminMode: widget.isAdminMode,
        existingVehicleId: _s(widget.initial?['vehicle_id']),
        leaserId: _leaserIdController.text.trim(),
        brand: _brandController.text.trim(),
        model: _modelController.text.trim(),
        plateNo: _plateController.text.trim(),
        vehicleType: _vehicleType,
        transmissionType: _transmissionType,
        fuelType: _fuelType,
        vehicleYear: int.parse(_yearController.text.trim()),
        mileageKm: int.parse(_mileageController.text.trim()),
        seatCapacity: int.parse(_seatController.text.trim()),
        dailyRate: double.parse(_rateController.text.trim()),
        location: _selectedLocation!.trim(),
        conditionStatus: _conditionStatus,
        roadTaxExpiryDate: _roadTaxExpiryDate,
        description: _descriptionController.text.trim(),
        remarks: _remarksController.text.trim(),
        photoBytes: _photoBytes,
        photoExtension: _photoExt,
        docsBytes: _docsBytes,
        docsExtension: _docsExt,
        existingPhotoPath: _existingPhotoPath,
        existingDocsPath: _existingDocsPath,
        existingVehicleStatus: _s(widget.initial?['vehicle_status']),
        existingReviewStatus: _s(widget.initial?['review_status']),
        existingEligibilityStatus: _s(widget.initial?['eligibility_status']),
        existingReadinessStatus: _s(widget.initial?['readiness_status']),
        existingInspectionResult: _s(widget.initial?['inspection_result']),
        existingReadinessNotes: _s(widget.initial?['readiness_notes']),
      );

      if (!mounted) return;
      Navigator.of(context).pop(_s(saved['vehicle_id']));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_service.explainError(error)),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 6),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final currentYear = DateTime.now().year;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Update Vehicle' : 'Vehicle Registration'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(20),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              'Add your vehicle details',
              style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w500),
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 22),
            children: [
              _SectionCard(
                title: 'Basic Information',
                child: Column(
                  children: [
                    if (widget.isAdminMode && (widget.fixedLeaserId ?? '').trim().isEmpty) ...[
                      TextFormField(
                        controller: _leaserIdController,
                        decoration: const InputDecoration(labelText: 'Leaser ID *', hintText: 'e.g. LEA-00001'),
                        validator: (value) => (value ?? '').trim().isEmpty ? 'Leaser ID is required' : null,
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextFormField(
                      controller: _plateController,
                      decoration: const InputDecoration(labelText: 'Plate Number *', hintText: 'e.g. ABC1234'),
                      validator: (value) => (value ?? '').trim().isEmpty ? 'Plate number is required' : null,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _brandController,
                            decoration: const InputDecoration(labelText: 'Brand *', hintText: 'e.g. Toyota'),
                            validator: (value) => (value ?? '').trim().isEmpty ? 'Brand is required' : null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _modelController,
                            decoration: const InputDecoration(labelText: 'Model *', hintText: 'e.g. Corolla'),
                            validator: (value) => (value ?? '').trim().isEmpty ? 'Model is required' : null,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _yearController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Year *', hintText: 'e.g. 2023'),
                      validator: (value) {
                        final year = int.tryParse((value ?? '').trim());
                        if (year == null) return 'Enter a valid year';
                        if (year < currentYear - 15 || year > currentYear + 1) return 'Enter a realistic vehicle year';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Road Tax Expiry Date *',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                _dateLabel(_roadTaxExpiryDate),
                                style: TextStyle(
                                  color: _roadTaxExpiryDate == null ? cs.onSurfaceVariant : cs.onSurface,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (_roadTaxExpiryDate != null)
                              IconButton(
                                tooltip: 'Clear date',
                                onPressed: _saving ? null : () => setState(() => _roadTaxExpiryDate = null),
                                icon: const Icon(Icons.close_rounded),
                              ),
                            OutlinedButton(
                              onPressed: _saving ? null : _pickRoadTaxExpiryDate,
                              child: const Text('Pick date'),
                            ),
                          ],
                        ),
                        const Divider(height: 1),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _SectionCard(
                title: 'Vehicle Specifications',
                child: Column(
                  children: [
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      value: _vehicleType,
                      decoration: const InputDecoration(labelText: 'Vehicle Type *'),
                      items: _vehicleTypes.map((value) => DropdownMenuItem(value: value, child: Text(value))).toList(),
                      onChanged: _saving ? null : (value) => setState(() => _vehicleType = value ?? _vehicleType),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      value: _transmissionType,
                      decoration: const InputDecoration(labelText: 'Transmission Type *'),
                      items: _transmissionTypes.map((value) => DropdownMenuItem(value: value, child: Text(value))).toList(),
                      onChanged: _saving ? null : (value) => setState(() => _transmissionType = value ?? _transmissionType),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      value: _fuelType,
                      decoration: const InputDecoration(labelText: 'Fuel Type *'),
                      items: _fuelTypes.map((value) => DropdownMenuItem(value: value, child: Text(value))).toList(),
                      onChanged: _saving ? null : (value) => setState(() => _fuelType = value ?? _fuelType),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _mileageController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'Mileage (km) *', hintText: 'e.g. 50000'),
                            validator: (value) {
                              final mileage = int.tryParse((value ?? '').trim());
                              if (mileage == null || mileage < 0) return 'Enter valid mileage';
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _seatController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'Seating *', hintText: 'e.g. 5'),
                            validator: (value) {
                              final seats = int.tryParse((value ?? '').trim());
                              if (seats == null || seats <= 0) return 'Enter seat count';
                              return null;
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _rateController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(labelText: 'Daily Rate (RM) *', hintText: 'e.g. 120'),
                            validator: (value) {
                              final rate = double.tryParse((value ?? '').trim());
                              if (rate == null || rate <= 0) return 'Enter daily rate';
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            isExpanded: true,
                            value: _conditionStatus,
                            decoration: const InputDecoration(labelText: 'Condition *'),
                            items: _conditionTypes
                                .map((value) => DropdownMenuItem(value: value, child: Text(value)))
                                .toList(),
                            onChanged: _saving ? null : (value) => setState(() => _conditionStatus = value ?? _conditionStatus),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      value: _selectedLocation,
                      decoration: InputDecoration(
                        labelText: 'Vehicle Location *',
                        helperText: _locations.isEmpty ? 'Add locations in the admin Location module first.' : null,
                      ),
                      items: _locations
                          .map(
                            (value) => DropdownMenuItem(
                          value: value,
                          child: Text(
                            value,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                          .toList(),
                      selectedItemBuilder: (context) => _locations
                          .map(
                            (value) => Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            value,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                          .toList(),
                      onChanged: _saving || _locations.isEmpty
                          ? null
                          : (value) => setState(() => _selectedLocation = value),
                      validator: (_) => (_selectedLocation ?? '').trim().isEmpty ? 'Location is required' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _descriptionController,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Vehicle Description',
                        hintText: 'Optional short notes for the vehicle listing',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _SectionCard(
                title: 'Vehicle Photos',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Upload clear photos of your vehicle',
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(height: 12),
                    _UploadTile(
                      icon: Icons.upload_file_outlined,
                      label: _photoBytes != null ? 'Photo selected' : 'Upload Photos',
                      onTap: _saving ? null : _showPhotoSourceSheet,
                    ),
                    const SizedBox(height: 12),
                    _PreviewBox(
                      bytes: _photoBytes,
                      imageUrl: _existingPhotoUrl,
                      fallbackLabel: _existingPhotoPath == null || _existingPhotoPath!.isEmpty
                          ? 'No photo selected yet'
                          : _existingPhotoPath!,
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: (_saving || _aiFilling || _photoBytes == null) ? null : _runAiAutoFill,
                      icon: _aiFilling
                          ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                          : const Icon(Icons.auto_awesome_outlined),
                      label: Text(_aiFilling ? 'Reading photo...' : 'Auto Fill From Photo'),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Auto fill is based on the uploaded photo. Please check brand, year, seats, transmission and fuel type before submit.',
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                    if ((_aiNotes ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Auto fill note: $_aiNotes',
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _SectionCard(
                title: 'Supporting Documents',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Upload registration, insurance, or inspection files (PDF).',
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(height: 12),
                    _UploadTile(
                      icon: Icons.note_add_outlined,
                      label: _docsFileName != null && _docsFileName!.trim().isNotEmpty ? 'PDF selected' : 'Upload PDF',
                      accentColor: Colors.green,
                      onTap: _saving ? null : _pickDocumentFile,
                    ),
                    const SizedBox(height: 12),
                    _DocumentPreviewBox(
                      fileName: (_docsFileName ?? '').trim().isNotEmpty
                          ? _docsFileName!
                          : _friendlyDocumentName(_existingDocsPath),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _SectionCard(
                title: 'Remarks',
                child: TextFormField(
                  controller: _remarksController,
                  minLines: 4,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    hintText: 'Enter any additional notes or special conditions about the vehicle...',
                  ),
                ),
              ),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                child: _saving
                    ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
                    : Text(_isEdit ? 'Save Vehicle Update' : 'Submit for Inspection'),
              ),

            ],
          ),
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _UploadTile extends StatelessWidget {
  const _UploadTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.accentColor,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = accentColor ?? cs.primary;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: color.withOpacity(0.08),
          border: Border.all(color: color.withOpacity(0.24)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(fontWeight: FontWeight.w700, color: color),
            ),
          ],
        ),
      ),
    );
  }
}


class _DocumentPreviewBox extends StatelessWidget {
  const _DocumentPreviewBox({required this.fileName});

  final String fileName;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasFile = fileName.trim().isNotEmpty;

    return Container(
      height: 180,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: cs.surfaceContainerHighest.withOpacity(0.4),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.picture_as_pdf_outlined, color: Colors.red.shade600, size: 44),
          const SizedBox(height: 12),
          Text(
            hasFile ? fileName : 'No document selected yet',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            hasFile ? 'PDF document ready for upload' : 'Please choose a PDF file',
            textAlign: TextAlign.center,
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
class _PreviewBox extends StatelessWidget {
  const _PreviewBox({
    required this.bytes,
    required this.imageUrl,
    required this.fallbackLabel,
  });

  final Uint8List? bytes;
  final String? imageUrl;
  final String fallbackLabel;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget child;
    if (bytes != null && bytes!.isNotEmpty) {
      child = ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Image.memory(bytes!, fit: BoxFit.cover, height: 180, width: double.infinity),
      );
    } else if ((imageUrl ?? '').trim().isNotEmpty) {
      child = ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Image.network(
          imageUrl!,
          fit: BoxFit.cover,
          height: 180,
          width: double.infinity,
          errorBuilder: (_, __, ___) => _fallback(cs),
        ),
      );
    } else {
      child = _fallback(cs);
    }

    return SizedBox(height: 180, width: double.infinity, child: child);
  }

  Widget _fallback(ColorScheme cs) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: cs.surfaceContainerHighest.withOpacity(0.4),
      ),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(12),
      child: Text(
        fallbackLabel,
        textAlign: TextAlign.center,
        style: TextStyle(color: cs.onSurfaceVariant),
      ),
    );
  }
}











