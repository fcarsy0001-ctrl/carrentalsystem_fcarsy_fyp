import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/promotion_service.dart';

class MyVouchersPage extends StatefulWidget {
  const MyVouchersPage({super.key});

  @override
  State<MyVouchersPage> createState() => _MyVouchersPageState();
}

class _MyVouchersPageState extends State<MyVouchersPage> {
  SupabaseClient get _supa => Supabase.instance.client;
  late final PromotionService _svc = PromotionService(_supa);

  late Future<List<Map<String, dynamic>>> _myFuture;
  late Future<List<Map<String, dynamic>>> _promoFuture;

  @override
  void initState() {
    super.initState();
    _myFuture = _svc.fetchMyVouchers();
    _promoFuture = _svc.fetchActivePromotions();
  }

  Future<void> _refresh() async {
    setState(() {
      _myFuture = _svc.fetchMyVouchers();
      _promoFuture = _svc.fetchActivePromotions();
    });
  }

  bool _isUsed(Map<String, dynamic> uvRow) {
    final used = uvRow['used_booking_id'];
    return used != null && used.toString().trim().isNotEmpty;
  }

  String _promoTitle(Map<String, dynamic> promo) {
    final t = (promo['title'] ?? '').toString().trim();
    if (t.isNotEmpty) return t;
    return (promo['code'] ?? 'Voucher').toString();
  }

  String _promoSubtitle(Map<String, dynamic> promo) {
    final type = (promo['discount_type'] ?? 'amount').toString().toLowerCase();
    final v = promo['discount_value'];
    final val = (v is num) ? v.toDouble() : double.tryParse((v ?? '0').toString()) ?? 0.0;
    final code = (promo['code'] ?? '').toString();
    if (type == 'percent' || type == 'percentage') {
      return '$code • ${val.toStringAsFixed(0)}% off';
    }
    return '$code • RM${val.toStringAsFixed(0)} off';
  }

  Future<void> _claimPromo(Map<String, dynamic> promo) async {
    final promoId = (promo['promo_id'] ?? '').toString();
    final promoName = _promoTitle(promo);
    if (promoId.isEmpty) return;
    try {
      final result = await _svc.claimVoucherWithStatus(promoId: promoId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.alreadyClaimed ? 'Already claimed: $promoName' : 'Voucher claimed: $promoName',
          ),
        ),
      );
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Claim failed: $e')));
    }
  }

  Widget _statusChip(bool used) {
    return Chip(label: Text(used ? 'Used' : 'Claimed'));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        centerTitle: true,
        title: const Text('My Vouchers'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _myFuture,
              builder: (context, mySnap) {
                if (mySnap.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }

                final myRows = mySnap.data ?? const [];
                final claimedPromoIds = myRows
                    .map((e) => (e['promo_id'] ?? '').toString())
                    .where((e) => e.isNotEmpty)
                    .toSet();

                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                  children: [
                    const Text(
                      'Claimed Vouchers',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 10),
                    if (myRows.isEmpty)
                      Text(
                        'No claimed vouchers yet.',
                        style: TextStyle(color: Colors.grey.shade700),
                      )
                    else
                      Column(
                        children: myRows.map((uv) {
                          final promo = (uv['promotion'] is Map)
                              ? Map<String, dynamic>.from(uv['promotion'] as Map)
                              : <String, dynamic>{};
                          final used = _isUsed(uv);
                          return Card(
                            child: ListTile(
                              title: Text(
                                _promoTitle(promo),
                                style: const TextStyle(fontWeight: FontWeight.w800),
                              ),
                              subtitle: Text(_promoSubtitle(promo)),
                              trailing: _statusChip(used),
                            ),
                          );
                        }).toList(),
                      ),
                    const SizedBox(height: 18),
                    const Text(
                      'Available Promotions',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 10),
                    FutureBuilder<List<Map<String, dynamic>>>(
                      future: _promoFuture,
                      builder: (context, promoSnap) {
                        if (promoSnap.connectionState != ConnectionState.done) {
                          return const Center(
                            child: Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: CircularProgressIndicator(),
                            ),
                          );
                        }

                        final promos = (promoSnap.data ?? const [])
                            .where((p) {
                              final id = (p['promo_id'] ?? '').toString();
                              return id.isNotEmpty && !claimedPromoIds.contains(id);
                            })
                            .toList();

                        if (promos.isEmpty) {
                          return Text(
                            'No promotions available.',
                            style: TextStyle(color: Colors.grey.shade700),
                          );
                        }

                        return Column(
                          children: promos.map((promo) {
                            return Card(
                              child: ListTile(
                                title: Text(
                                  _promoTitle(promo),
                                  style: const TextStyle(fontWeight: FontWeight.w800),
                                ),
                                subtitle: Text(_promoSubtitle(promo)),
                                trailing: TextButton(
                                  onPressed: () => _claimPromo(promo),
                                  child: const Text('Claim'),
                                ),
                              ),
                            );
                          }).toList(),
                        );
                      },
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
