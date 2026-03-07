class MyValidators {
  MyValidators._();

  static final RegExp _emailRegex = RegExp(
    r'^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$',
  );
  static final RegExp _digitsOnly = RegExp(r'^\d+$');
  static final RegExp _nameRegex = RegExp(r"^[A-Za-z@'./\- ]+$");
  static final RegExp _vehicleTextRegex = RegExp(r"^[A-Za-z0-9&().,'/\- ]+$");
  static final RegExp _plateRegex = RegExp(r'^[A-Z]{1,3}\d{1,4}[A-Z]{0,3}$');
  static final RegExp _promoCodeRegex = RegExp(r'^[A-Z0-9][A-Z0-9_-]{2,19}$');
  static final RegExp _bankAccountRegex = RegExp(r'^\d{8,18}$');
  static final RegExp _otpRegex = RegExp(r'^\d{4,8}$');

  static String _clean(String? value) => value?.trim() ?? '';

  static String? requiredText(
    String? value, {
    String fieldName = 'This field',
    int? maxLength,
  }) {
    final s = _clean(value);
    if (s.isEmpty) return '$fieldName is required';
    if (maxLength != null && s.length > maxLength) {
      return '$fieldName must be at most $maxLength characters';
    }
    return null;
  }

  static String? personName(
    String? value, {
    String fieldName = 'Name',
    int minLength = 2,
    int maxLength = 100,
  }) {
    final s = _clean(value);
    if (s.isEmpty) return '$fieldName is required';
    if (s.length < minLength) return '$fieldName is too short';
    if (s.length > maxLength) return '$fieldName must be at most $maxLength characters';
    if (!_nameRegex.hasMatch(s)) {
      return '$fieldName contains invalid characters';
    }
    return null;
  }

  static String? companyName(String? value, {String fieldName = 'Company name'}) {
    final s = _clean(value);
    if (s.isEmpty) return '$fieldName is required';
    if (s.length < 2) return '$fieldName is too short';
    if (s.length > 150) return '$fieldName must be at most 150 characters';
    if (!_vehicleTextRegex.hasMatch(s)) {
      return '$fieldName contains invalid characters';
    }
    return null;
  }

  static String? email(String? value, {bool required = true, String fieldName = 'Email'}) {
    final s = _clean(value);
    if (s.isEmpty) return required ? '$fieldName is required' : null;
    if (s.length > 254) return '$fieldName is too long';
    if (!_emailRegex.hasMatch(s)) return 'Please enter a valid email address';
    return null;
  }

  static String? malaysiaPhone(
    String? value, {
    bool required = true,
    String fieldName = 'Phone number',
  }) {
    final s = _clean(value).replaceAll(RegExp(r'[\s-]'), '');
    if (s.isEmpty) return required ? '$fieldName is required' : null;

    var normalized = s;
    if (normalized.startsWith('+6')) normalized = normalized.substring(2);
    if (normalized.startsWith('6') && !normalized.startsWith('60')) {
      return 'Please use a valid Malaysia phone number';
    }
    if (normalized.startsWith('60')) normalized = '0${normalized.substring(2)}';

    if (!_digitsOnly.hasMatch(normalized)) {
      return '$fieldName must contain digits only';
    }
    if (!normalized.startsWith('0')) {
      return 'Malaysia phone number must start with 0';
    }
    if (normalized.length < 9 || normalized.length > 11) {
      return 'Malaysia phone number must be 9 to 11 digits';
    }
    if (!RegExp(r'^0(1\d|[3-9])\d{7,9}$').hasMatch(normalized)) {
      return 'Please enter a valid Malaysia phone number';
    }
    return null;
  }

  static String? icNumber(String? value, {bool required = true, String fieldName = 'IC number'}) {
    final s = _clean(value).replaceAll(RegExp(r'[-\s]'), '');
    if (s.isEmpty) return required ? '$fieldName is required' : null;
    if (!_digitsOnly.hasMatch(s) || s.length != 12) {
      return '$fieldName must be exactly 12 digits';
    }

    final month = int.tryParse(s.substring(2, 4));
    final day = int.tryParse(s.substring(4, 6));
    if (month == null || month < 1 || month > 12) {
      return 'IC number has an invalid birth month';
    }
    if (day == null || day < 1 || day > 31) {
      return 'IC number has an invalid birth day';
    }
    return null;
  }

  static String? password(
    String? value, {
    bool required = true,
    int minLength = 8,
    bool requireUppercase = true,
    bool requireLowercase = true,
    bool requireDigit = true,
  }) {
    final s = value ?? '';
    if (s.trim().isEmpty) return required ? 'Password is required' : null;
    if (s.length < minLength) return 'Password must be at least $minLength characters';
    if (s.length > 72) return 'Password is too long';
    if (requireUppercase && !RegExp(r'[A-Z]').hasMatch(s)) {
      return 'Password must include at least 1 uppercase letter';
    }
    if (requireLowercase && !RegExp(r'[a-z]').hasMatch(s)) {
      return 'Password must include at least 1 lowercase letter';
    }
    if (requireDigit && !RegExp(r'\d').hasMatch(s)) {
      return 'Password must include at least 1 number';
    }
    return null;
  }

  static String? confirmPassword(String? value, String originalPassword) {
    final s = value ?? '';
    if (s.trim().isEmpty) return 'Please confirm your password';
    if (s != originalPassword) return 'Passwords do not match';
    return null;
  }

  static String? ssmNumber(String? value, {bool required = true, String fieldName = 'SSM number'}) {
    final s = _clean(value).replaceAll(RegExp(r'[-\s]'), '');
    if (s.isEmpty) return required ? '$fieldName is required' : null;
    if (!_digitsOnly.hasMatch(s) || s.length != 12) {
      return '$fieldName must be exactly 12 digits';
    }
    return null;
  }

  static String? bankAccountNumber(String? value, {bool required = false, String fieldName = 'Bank account number'}) {
    final s = _clean(value).replaceAll(' ', '');
    if (s.isEmpty) return required ? '$fieldName is required' : null;
    if (!_bankAccountRegex.hasMatch(s)) {
      return '$fieldName must be 8 to 18 digits';
    }
    return null;
  }

  static String? otpCode(String? value) {
    final s = _clean(value);
    if (s.isEmpty) return 'OTP code is required';
    if (!_otpRegex.hasMatch(s)) return 'OTP code must be 4 to 8 digits';
    return null;
  }

  static String? vehicleBrand(String? value) => textTitle(value, fieldName: 'Vehicle brand', maxLength: 50);
  static String? vehicleModel(String? value) => textTitle(value, fieldName: 'Vehicle model', maxLength: 50);
  static String? vehicleColor(String? value) => textTitle(value, fieldName: 'Vehicle color', maxLength: 30);

  static String? vehiclePlateNumber(String? value, {String fieldName = 'Plate number'}) {
    final s = _clean(value).replaceAll(RegExp(r'\s+'), '').toUpperCase();
    if (s.isEmpty) return '$fieldName is required';
    if (s.length < 3 || s.length > 10) return '$fieldName is invalid';
    if (!_plateRegex.hasMatch(s)) return 'Please enter a valid Malaysia plate number';
    return null;
  }

  static String? textTitle(
    String? value, {
    String fieldName = 'Text',
    int minLength = 2,
    int maxLength = 100,
  }) {
    final s = _clean(value);
    if (s.isEmpty) return '$fieldName is required';
    if (s.length < minLength) return '$fieldName is too short';
    if (s.length > maxLength) return '$fieldName must be at most $maxLength characters';
    if (!_vehicleTextRegex.hasMatch(s)) return '$fieldName contains invalid characters';
    return null;
  }

  static String? description(
    String? value, {
    String fieldName = 'Description',
    bool required = false,
    int maxLength = 500,
  }) {
    final s = _clean(value);
    if (s.isEmpty) return required ? '$fieldName is required' : null;
    if (s.length > maxLength) return '$fieldName must be at most $maxLength characters';
    return null;
  }

  static String? numericText(
    String? value, {
    String fieldName = 'Value',
    bool required = true,
    bool allowDecimal = true,
    num? min,
    num? max,
    int? maxDecimalPlaces = 2,
  }) {
    final s = _clean(value);
    if (s.isEmpty) return required ? '$fieldName is required' : null;

    final pattern = allowDecimal
        ? RegExp(r'^\d+(\.\d+)?$')
        : RegExp(r'^\d+$');
    if (!pattern.hasMatch(s)) {
      return allowDecimal
          ? '$fieldName must be a valid number'
          : '$fieldName must be digits only';
    }

    if (allowDecimal && maxDecimalPlaces != null && s.contains('.')) {
      final decimals = s.split('.').last;
      if (decimals.length > maxDecimalPlaces) {
        return '$fieldName can have at most $maxDecimalPlaces decimal places';
      }
    }

    final n = num.tryParse(s);
    if (n == null) return '$fieldName must be a valid number';
    if (min != null && n < min) return '$fieldName must be at least $min';
    if (max != null && n > max) return '$fieldName must be at most $max';
    return null;
  }

  static String? integerText(
    String? value, {
    String fieldName = 'Value',
    bool required = true,
    int? min,
    int? max,
  }) {
    final s = _clean(value);
    if (s.isEmpty) return required ? '$fieldName is required' : null;
    if (!_digitsOnly.hasMatch(s)) return '$fieldName must be digits only';
    final n = int.tryParse(s);
    if (n == null) return '$fieldName must be a whole number';
    if (min != null && n < min) return '$fieldName must be at least $min';
    if (max != null && n > max) return '$fieldName must be at most $max';
    return null;
  }

  static String? promoCode(String? value, {String fieldName = 'Voucher code'}) {
    final s = _clean(value).toUpperCase();
    if (s.isEmpty) return '$fieldName is required';
    if (!_promoCodeRegex.hasMatch(s)) {
      return '$fieldName must be 3 to 20 characters using A-Z, 0-9, _ or -';
    }
    return null;
  }

  static String? paymentReference(String? value, {String fieldName = 'Payment reference'}) {
    final s = _clean(value);
    if (s.isEmpty) return '$fieldName is required';
    if (s.length < 4) return '$fieldName is too short';
    if (s.length > 50) return '$fieldName is too long';
    if (!RegExp(r'^[A-Za-z0-9/_\-]+$').hasMatch(s)) {
      return '$fieldName contains invalid characters';
    }
    return null;
  }

  static String? receiptDetail(String? value) {
    return description(value, fieldName: 'Receipt detail', required: true, maxLength: 255);
  }

  static String? locationName(String? value) {
    final s = _clean(value);
    if (s.isEmpty) return 'Location is required';
    if (s.length < 5) return 'Location is too short';
    if (s.length > 180) return 'Location is too long';
    return null;
  }

  static String? driverLicenseNumber(String? value, {bool required = true}) {
    final s = _clean(value).toUpperCase().replaceAll(' ', '');
    if (s.isEmpty) return required ? 'Driver license number is required' : null;
    if (!RegExp(r'^[A-Z0-9]{6,20}$').hasMatch(s)) {
      return 'Driver license number must be 6 to 20 letters or digits';
    }
    return null;
  }

  static String? statusText(
    String? value,
    List<String> allowed, {
    String fieldName = 'Status',
  }) {
    final s = _clean(value);
    if (s.isEmpty) return '$fieldName is required';
    if (!allowed.contains(s)) return 'Invalid $fieldName';
    return null;
  }
}
