import 'package:flutter/services.dart';

class CardExpiryInputFormatter extends TextInputFormatter {
  const CardExpiryInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    final truncated = digits.length > 4 ? digits.substring(0, 4) : digits;

    String text;
    if (truncated.length <= 2) {
      text = truncated;
    } else {
      text = '${truncated.substring(0, 2)}/${truncated.substring(2)}';
    }

    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
