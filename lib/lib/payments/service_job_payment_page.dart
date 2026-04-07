import 'package:flutter/material.dart';

import '../admin/widgets/admin_ui.dart';
import '../services/job_order_module_service.dart';

enum _ServicePayMethod { card, tng, stripe }

class ServiceJobPaymentPage extends StatefulWidget {
  const ServiceJobPaymentPage({
    super.key,
    required this.service,
    required this.job,
    required this.cost,
    required this.vehicle,
    required this.vendor,
    required this.leaserId,
  });

  final JobOrderModuleService service;
  final Map<String, dynamic> job;
  final Map<String, dynamic> cost;
  final Map<String, dynamic>? vehicle;
  final Map<String, dynamic>? vendor;
  final String leaserId;

  @override
  State<ServiceJobPaymentPage> createState() => _ServiceJobPaymentPageState();
}

class _ServiceJobPaymentPageState extends State<ServiceJobPaymentPage> {
  final _cardNameCtrl = TextEditingController();
  final _cardNoCtrl = TextEditingController();
  final _cardExpCtrl = TextEditingController();
  final _cardCvvCtrl = TextEditingController();
  final _tngRefCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  _ServicePayMethod _method = _ServicePayMethod.card;
  bool _paying = false;

  String _s(dynamic value) => value == null ? '' : value.toString().trim();

  @override
  void dispose() {
    _cardNameCtrl.dispose();
    _cardNoCtrl.dispose();
    _cardExpCtrl.dispose();
    _cardCvvCtrl.dispose();
    _tngRefCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  String _digits(String value) => value.replaceAll(RegExp(r'[^0-9]'), '');

  String _methodText(_ServicePayMethod method) {
    switch (method) {
      case _ServicePayMethod.card:
        return 'Card';
      case _ServicePayMethod.tng:
        return 'TNG';
      case _ServicePayMethod.stripe:
        return 'Stripe';
    }
  }

  String _referenceForMethod(_ServicePayMethod method) {
    final stamp = DateTime.now().millisecondsSinceEpoch.toString();
    switch (method) {
      case _ServicePayMethod.card:
        final last4 = _digits(_cardNoCtrl.text).padLeft(4, '0');
        return 'SC${last4.substring(last4.length - 4)}${stamp.substring(stamp.length - 4)}';
      case _ServicePayMethod.tng:
        final ref = _digits(_tngRefCtrl.text).padLeft(7, '0');
        return 'TNG${ref.substring(ref.length - 7)}';
      case _ServicePayMethod.stripe:
        return 'STP${stamp.substring(stamp.length - 7)}';
    }
  }

  double get _amount {
    final raw = widget.cost['total_cost'];
    if (raw is num) return raw.toDouble();
    return double.tryParse(raw.toString()) ?? 0;
  }

  bool get _alreadyPaid => _s(widget.cost['payment_status']).toLowerCase() == 'paid';

  void _validate() {
    if (_method == _ServicePayMethod.card) {
      if (_cardNameCtrl.text.trim().isEmpty) {
        throw Exception('Please enter cardholder name.');
      }
      if (_digits(_cardNoCtrl.text).length < 12) {
        throw Exception('Please enter a valid card number.');
      }
      if (!RegExp(r'^\d{2}/\d{2}$').hasMatch(_cardExpCtrl.text.trim())) {
        throw Exception('Expiry must be MM/YY.');
      }
      final cvv = _digits(_cardCvvCtrl.text);
      if (cvv.length < 3 || cvv.length > 4) {
        throw Exception('CVV must be 3 or 4 digits.');
      }
      return;
    }

    if (_method == _ServicePayMethod.tng && _tngRefCtrl.text.trim().isEmpty) {
      throw Exception('Please enter TNG reference or phone.');
    }
  }

  Future<void> _pay() async {
    if (_alreadyPaid || _paying) return;

    try {
      _validate();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString().replaceFirst('Exception: ', '')), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _paying = true);
    try {
      await widget.service.createServicePayment(
        serviceCostId: _s(widget.cost['service_cost_id']),
        jobOrderId: _s(widget.job['job_order_id']),
        leaserId: widget.leaserId,
        vendorId: _s(widget.cost['vendor_id']).isEmpty ? _s(widget.job['vendor_id']) : _s(widget.cost['vendor_id']),
        amountPaid: _amount,
        paymentMethod: _methodText(_method),
        paymentReference: _referenceForMethod(_method),
        notes: _notesCtrl.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Service payment completed.')),
      );
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.service.explainError(error)),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vehicleLabel = widget.vehicle == null ? _s(widget.job['vehicle_id']) : widget.service.vehicleLabel(widget.vehicle);
    final vendorLabel = widget.vendor == null ? '-' : widget.service.vendorLabel(widget.vendor);

    return Scaffold(
      appBar: AppBar(title: const Text('Pay Service Cost')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        children: [
          AdminCard(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _s(widget.job['job_order_id']).isEmpty ? 'Service Payment' : _s(widget.job['job_order_id']),
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 10),
                  _DetailRow(label: 'Vehicle', value: vehicleLabel.isEmpty ? '-' : vehicleLabel),
                  _DetailRow(label: 'Vendor', value: vendorLabel),
                  _DetailRow(label: 'Cost Record', value: _s(widget.cost['service_cost_id']).isEmpty ? '-' : _s(widget.cost['service_cost_id'])),
                  _DetailRow(label: 'Invoice', value: _s(widget.cost['invoice_ref']).isEmpty ? '-' : _s(widget.cost['invoice_ref'])),
                  _DetailRow(label: 'Total Amount', value: _money(_amount)),
                  const SizedBox(height: 10),
                  AdminStatusChip(status: _alreadyPaid ? 'Paid' : 'Pending'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Payment Method',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _MethodChip(
                label: 'Card',
                icon: Icons.credit_card_rounded,
                selected: _method == _ServicePayMethod.card,
                onTap: () => setState(() => _method = _ServicePayMethod.card),
              ),
              _MethodChip(
                label: 'TNG',
                icon: Icons.account_balance_wallet_outlined,
                selected: _method == _ServicePayMethod.tng,
                onTap: () => setState(() => _method = _ServicePayMethod.tng),
              ),
              _MethodChip(
                label: 'Stripe',
                icon: Icons.payments_outlined,
                selected: _method == _ServicePayMethod.stripe,
                onTap: () => setState(() => _method = _ServicePayMethod.stripe),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_method == _ServicePayMethod.card) ...[
            TextField(
              controller: _cardNameCtrl,
              decoration: const InputDecoration(labelText: 'Cardholder Name'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _cardNoCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Card Number'),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _cardExpCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Expiry (MM/YY)'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _cardCvvCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'CVV'),
                  ),
                ),
              ],
            ),
          ] else if (_method == _ServicePayMethod.tng) ...[
            TextField(
              controller: _tngRefCtrl,
              decoration: const InputDecoration(labelText: 'TNG Reference / Phone'),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.25),
                border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.18)),
              ),
              child: const Text('Demo flow: tap Pay Service Cost to simulate Stripe success and save the service payment record.'),
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _notesCtrl,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Payment Notes (optional)'),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _alreadyPaid || _paying ? null : _pay,
            icon: _paying
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.payments_outlined),
            label: Text(_alreadyPaid ? 'Already Paid' : (_paying ? 'Processing Payment...' : 'Pay Service Cost')),
          ),
        ],
      ),
    );
  }
}

class _MethodChip extends StatelessWidget {
  const _MethodChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? color : Theme.of(context).colorScheme.outlineVariant),
          color: selected ? color.withValues(alpha: 0.12) : Colors.transparent,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

String _money(double value) => 'RM ${value.toStringAsFixed(2)}';
