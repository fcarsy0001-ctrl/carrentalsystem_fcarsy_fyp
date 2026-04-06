import 'package:flutter/material.dart';

class WalletPaymentSelector extends StatelessWidget {
  const WalletPaymentSelector({
    super.key,
    required this.walletBalance,
    required this.totalAmount,
    required this.selectedMethod,
    required this.onSelected,
    this.otherMethods = const ['Card', 'TNG', 'Stripe'],
  });

  final double walletBalance;
  final double totalAmount;
  final String selectedMethod;
  final ValueChanged<String> onSelected;
  final List<String> otherMethods;

  bool get canUseWallet => walletBalance >= totalAmount;

  IconData _iconForMethod(String method) {
    switch (method.toLowerCase()) {
      case 'card':
        return Icons.credit_card_outlined;
      case 'tng':
        return Icons.account_balance_wallet_outlined;
      case 'stripe':
        return Icons.flash_on_outlined;
      default:
        return Icons.payments_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PaymentTile(
          title: 'Wallet',
          subtitle: canUseWallet
              ? 'Balance: RM ${walletBalance.toStringAsFixed(2)}'
              : 'Insufficient balance • RM ${walletBalance.toStringAsFixed(2)}',
          icon: Icons.account_balance_wallet_outlined,
          selected: selectedMethod == 'Wallet',
          enabled: canUseWallet,
          onTap: canUseWallet ? () => onSelected('Wallet') : null,
        ),
        const SizedBox(height: 12),
        for (final method in otherMethods) ...[
          _PaymentTile(
            title: method,
            subtitle: 'Use $method to pay',
            icon: _iconForMethod(method),
            selected: selectedMethod == method,
            enabled: true,
            onTap: () => onSelected(method),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _PaymentTile extends StatelessWidget {
  const _PaymentTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final borderColor = selected ? const Color(0xFF16A34A) : const Color(0xFFE5E7EB);

    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            children: [
              Icon(icon),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(subtitle),
                  ],
                ),
              ),
              if (selected) const Icon(Icons.check_circle, color: Color(0xFF16A34A)),
            ],
          ),
        ),
      ),
    );
  }
}
