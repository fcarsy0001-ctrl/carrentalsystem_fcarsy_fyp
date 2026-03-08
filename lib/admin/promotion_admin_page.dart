import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'widgets/admin_ui.dart';

class PromotionAdminPage extends StatefulWidget {
  const PromotionAdminPage({super.key});

  @override
  State<PromotionAdminPage> createState() => _PromotionAdminPageState();
}

class _PromotionAdminPageState extends State<PromotionAdminPage> {
  SupabaseClient get _supa => Supabase.instance.client;

  late Future<List<Map<String, dynamic>>> _promoFuture;
  late Future<List<Map<String, dynamic>>> _annFuture;

  @override
  void initState() {
    super.initState();
    _promoFuture = _loadPromos();
    _annFuture = _loadAnnouncements();
  }

  DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    if (s.isEmpty) return null;
    try {
      return DateTime.parse(s).toLocal();
    } catch (_) {
      return null;
    }
  }

  String _fmtDate(DateTime? d) {
    if (d == null) return '-';
    return '${d.day}/${d.month}/${d.year}';
  }

  Future<List<Map<String, dynamic>>> _loadPromos() async {
    final rows = await _supa.from('promotion').select().order('created_at', ascending: false);
    return (rows as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<List<Map<String, dynamic>>> _loadAnnouncements() async {
    final rows = await _supa.from('announcement').select().order('created_at', ascending: false);
    return (rows as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<void> _refresh() async {
    setState(() {
      _promoFuture = _loadPromos();
      _annFuture = _loadAnnouncements();
    });
  }

  void _toast(String msg, {Color? bg}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: bg),
    );
  }

  String _shortId(String prefix) {
    final ms = DateTime.now().millisecondsSinceEpoch.toString();
    return prefix + ms.substring(ms.length - 8);
  }

  String _fmtDiscount(Map<String, dynamic> p) {
    final t = (p['discount_type'] ?? '').toString().toLowerCase();
    final v = p['discount_value'];
    final val = (v is num) ? v.toDouble() : double.tryParse((v ?? '0').toString()) ?? 0;
    if (t == 'percent' || t == 'percentage') return '${val.toStringAsFixed(0)}%';
    return 'RM${val.toStringAsFixed(0)}';
  }

  Future<DateTime?> _pickDate({required DateTime? current, DateTime? min}) async {
    final today = _today();
    final first = min ?? today;
    final init = (current != null && current.isAfter(first)) ? current : first;
    final d = await showDatePicker(
      context: context,
      firstDate: first,
      lastDate: DateTime(2100),
      initialDate: init,
    );
    if (d == null) return null;
    return DateTime(d.year, d.month, d.day);
  }

  bool _validateDates({DateTime? start, DateTime? end}) {
    final today = _today();
    if (start != null && start.isBefore(today)) {
      _toast('Start date cannot be in the past.', bg: Colors.red);
      return false;
    }
    if (end != null && end.isBefore(today)) {
      _toast('End date cannot be in the past.', bg: Colors.red);
      return false;
    }
    if (start != null && end != null && end.isBefore(start)) {
      _toast('End date cannot be earlier than start date.', bg: Colors.red);
      return false;
    }
    return true;
  }

  Future<void> _openUpsertVoucher({Map<String, dynamic>? initial}) async {
    final isEdit = initial != null;

    final codeCtrl = TextEditingController(text: (initial?['code'] ?? '').toString());
    final titleCtrl = TextEditingController(text: (initial?['title'] ?? '').toString());
    final descCtrl = TextEditingController(text: (initial?['description'] ?? '').toString());
    final valueCtrl = TextEditingController(text: (initial?['discount_value'] ?? '10').toString());
    final minCtrl = TextEditingController(text: (initial?['min_spend'] ?? '0').toString());
    final maxCtrl = TextEditingController(text: (initial?['max_discount'] ?? '').toString());
    final maxRedeemCtrl = TextEditingController(text: (initial?['max_redeems'] ?? '').toString());

    var active = (initial?['active'] == null) ? true : (initial?['active'] == true);
    var type = (initial?['discount_type'] ?? 'percent').toString().toLowerCase();
    if (type != 'percent' && type != 'amount') type = 'percent';

    DateTime? start = _parseDate(initial?['start_at']);
    DateTime? end = _parseDate(initial?['end_at']);
    start = start == null ? null : DateTime(start.year, start.month, start.day);
    end = end == null ? null : DateTime(end.year, end.month, end.day);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx2, setLocal) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx2).viewInsets.bottom,
                left: 16,
                right: 16,
                top: 10,
              ),
              child: ListView(
                shrinkWrap: true,
                children: [
                  Text(isEdit ? 'Edit Voucher' : 'Create Voucher',
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: codeCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Voucher Code',
                      hintText: 'e.g. NEW10',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: titleCtrl,
                    decoration: const InputDecoration(labelText: 'Title', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: descCtrl,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(labelText: 'Description', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: type,
                          decoration: const InputDecoration(
                            labelText: 'Discount Type',
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(value: 'percent', child: Text('Percent (%)')),
                            DropdownMenuItem(value: 'amount', child: Text('Fixed amount (RM)')),
                          ],
                          onChanged: (v) => setLocal(() => type = v ?? 'percent'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: valueCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Value', border: OutlineInputBorder()),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: minCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Min spend (RM)', border: OutlineInputBorder()),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: maxCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Max discount (optional)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: maxRedeemCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Max people can redeem (optional)',
                      hintText: 'e.g. 100',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final d = await _pickDate(current: start);
                            if (d == null) return;
                            setLocal(() {
                              start = d;
                              if (end != null && end!.isBefore(start!)) end = null;
                            });
                          },
                          icon: const Icon(Icons.event_available_outlined),
                          label: Text(start == null ? 'Start date' : _fmtDate(start)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final d = await _pickDate(current: end, min: start);
                            if (d == null) return;
                            setLocal(() => end = d);
                          },
                          icon: const Icon(Icons.event_busy_outlined),
                          label: Text(end == null ? 'End date' : _fmtDate(end)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  SwitchListTile(
                    value: active,
                    onChanged: (v) => setLocal(() => active = v),
                    title: const Text('Active'),
                    contentPadding: EdgeInsets.zero,
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 46,
                    child: FilledButton(
                      onPressed: () async {
                        final code = codeCtrl.text.trim();
                        if (code.isEmpty) return _toast('Voucher code is required.', bg: Colors.red);

                        final val = double.tryParse(valueCtrl.text.trim()) ?? 0;
                        final minSpend = double.tryParse(minCtrl.text.trim()) ?? 0;
                        final maxDisc = maxCtrl.text.trim().isEmpty ? null : double.tryParse(maxCtrl.text.trim());
                        final maxRedeem = maxRedeemCtrl.text.trim().isEmpty
                            ? null
                            : int.tryParse(maxRedeemCtrl.text.trim());

                        if (val <= 0) return _toast('Discount value must be > 0.', bg: Colors.red);
                        if (minSpend < 0) return _toast('Min spend cannot be negative.', bg: Colors.red);
                        if (maxDisc != null && maxDisc < 0) {
                          return _toast('Max discount cannot be negative.', bg: Colors.red);
                        }
                        if (maxRedeem != null && maxRedeem <= 0) {
                          return _toast('Max people must be > 0.', bg: Colors.red);
                        }
                        if (!_validateDates(start: start, end: end)) return;

                        final promoId = isEdit ? (initial!['promo_id'] ?? '').toString() : _shortId('PR');
                        if (promoId.trim().isEmpty) return _toast('Missing promo_id.', bg: Colors.red);

                        final payload = <String, dynamic>{
                          'code': code,
                          'title': titleCtrl.text.trim(),
                          'description': descCtrl.text.trim(),
                          'discount_type': type,
                          'discount_value': val,
                          'min_spend': minSpend,
                          'max_discount': maxDisc,
                          'start_at': start?.toIso8601String(),
                          'end_at': end?.toIso8601String(),
                          'active': active,
                        };
                        if (maxRedeem != null) {
                          payload['max_redeems'] = maxRedeem;
                        }

                        try {
                          if (isEdit) {
                            await _supa.from('promotion').update(payload).eq('promo_id', promoId);
                          } else {
                            await _supa.from('promotion').insert({'promo_id': promoId, ...payload});
                          }
                        } catch (e) {
                          // Allow fallback if the DB does not have max_redeems yet.
                          final msg = e.toString();
                          if (msg.contains('max_redeems') && msg.contains('does not exist')) {
                            payload.remove('max_redeems');
                            try {
                              if (isEdit) {
                                await _supa.from('promotion').update(payload).eq('promo_id', promoId);
                              } else {
                                await _supa.from('promotion').insert({'promo_id': promoId, ...payload});
                              }
                              _toast('Saved, but DB has no max_redeems column. Add it to enable redeem limit.', bg: Colors.orange);
                            } catch (e2) {
                              _toast('Save voucher failed: $e2', bg: Colors.red);
                              return;
                            }
                          } else {
                            _toast('Save voucher failed: $e', bg: Colors.red);
                            return;
                          }
                        }

                        if (!mounted) return;
                        Navigator.of(ctx).pop();
                        await _refresh();
                      },
                      child: const Text('Save'),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _deleteVoucher(Map<String, dynamic> p) async {
    final promoId = (p['promo_id'] ?? '').toString().trim();
    if (promoId.isEmpty) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Voucher'),
        content: Text('Delete voucher $promoId?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await _supa.from('promotion').delete().eq('promo_id', promoId);
      _toast('Deleted');
    } catch (e) {
      // If FK prevents delete, take back by deactivating.
      try {
        await _supa.from('promotion').update({'active': false}).eq('promo_id', promoId);
        _toast('Cannot hard delete (likely claimed). Voucher has been deactivated instead.', bg: Colors.orange);
      } catch (e2) {
        _toast('Delete failed: $e2', bg: Colors.red);
        return;
      }
    }
    await _refresh();
  }

  Future<void> _toggleVoucherActive(Map<String, dynamic> p) async {
    final promoId = (p['promo_id'] ?? '').toString().trim();
    if (promoId.isEmpty) return;
    final cur = (p['active'] == true);
    try {
      await _supa.from('promotion').update({'active': !cur}).eq('promo_id', promoId);
      await _refresh();
    } catch (e) {
      _toast('Update failed: $e', bg: Colors.red);
    }
  }

  Future<void> _openUpsertAnnouncement({Map<String, dynamic>? initial}) async {
    final isEdit = initial != null;

    final titleCtrl = TextEditingController(text: (initial?['title'] ?? '').toString());
    final msgCtrl = TextEditingController(text: (initial?['message'] ?? '').toString());
    final promoCodeCtrl = TextEditingController(text: (initial?['promo_code'] ?? '').toString());

    var active = (initial?['active'] == null) ? true : (initial?['active'] == true);

    DateTime? start = _parseDate(initial?['start_at']);
    DateTime? end = _parseDate(initial?['end_at']);
    start = start == null ? null : DateTime(start.year, start.month, start.day);
    end = end == null ? null : DateTime(end.year, end.month, end.day);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx2, setLocal) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx2).viewInsets.bottom,
                left: 16,
                right: 16,
                top: 10,
              ),
              child: ListView(
                shrinkWrap: true,
                children: [
                  Text(isEdit ? 'Edit Announcement' : 'Create Announcement',
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: titleCtrl,
                    decoration: const InputDecoration(labelText: 'Title', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: msgCtrl,
                    minLines: 2,
                    maxLines: 5,
                    decoration: const InputDecoration(labelText: 'Message', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: promoCodeCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Promo code (optional)',
                      hintText: 'e.g. NEW10',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final d = await _pickDate(current: start);
                            if (d == null) return;
                            setLocal(() {
                              start = d;
                              if (end != null && end!.isBefore(start!)) end = null;
                            });
                          },
                          icon: const Icon(Icons.event_available_outlined),
                          label: Text(start == null ? 'Start date' : _fmtDate(start)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final d = await _pickDate(current: end, min: start);
                            if (d == null) return;
                            setLocal(() => end = d);
                          },
                          icon: const Icon(Icons.event_busy_outlined),
                          label: Text(end == null ? 'End date' : _fmtDate(end)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  SwitchListTile(
                    value: active,
                    onChanged: (v) => setLocal(() => active = v),
                    title: const Text('Active'),
                    contentPadding: EdgeInsets.zero,
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 46,
                    child: FilledButton(
                      onPressed: () async {
                        final title = titleCtrl.text.trim();
                        final msg = msgCtrl.text.trim();
                        if (title.isEmpty || msg.isEmpty) {
                          return _toast('Title and message are required.', bg: Colors.red);
                        }
                        if (!_validateDates(start: start, end: end)) return;

                        final annId = isEdit ? (initial!['ann_id'] ?? '').toString() : _shortId('AN');
                        if (annId.trim().isEmpty) return _toast('Missing ann_id.', bg: Colors.red);

                        final payload = <String, dynamic>{
                          'title': title,
                          'message': msg,
                          'promo_code': promoCodeCtrl.text.trim().isEmpty ? null : promoCodeCtrl.text.trim(),
                          'start_at': start?.toIso8601String(),
                          'end_at': end?.toIso8601String(),
                          'active': active,
                        };

                        try {
                          if (isEdit) {
                            await _supa.from('announcement').update(payload).eq('ann_id', annId);
                          } else {
                            await _supa.from('announcement').insert({'ann_id': annId, ...payload});
                          }
                        } catch (e) {
                          _toast('Save announcement failed: $e', bg: Colors.red);
                          return;
                        }

                        if (!mounted) return;
                        Navigator.of(ctx).pop();
                        await _refresh();
                      },
                      child: const Text('Save'),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _deleteAnnouncement(Map<String, dynamic> a) async {
    final annId = (a['ann_id'] ?? '').toString().trim();
    if (annId.isEmpty) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete announcement'),
        content: Text('Take back announcement $annId?\n\nThis will set it to inactive (it will stop showing to users).'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await _supa.from('announcement').delete().eq('ann_id', annId);
      _toast('Announcement deleted');
      await _refresh();
    } catch (e) {
      try {
        await _supa.from('announcement').update({'active': false}).eq('ann_id', annId);
        _toast('Cannot hard delete. Announcement has been set to inactive instead.', bg: Colors.orange);
        await _refresh();
      } catch (e2) {
        _toast('Delete failed: $e2', bg: Colors.red);
      }
    }
  }

  Future<void> _toggleAnnouncementActive(Map<String, dynamic> a) async {
    final annId = (a['ann_id'] ?? '').toString().trim();
    if (annId.isEmpty) return;
    final cur = (a['active'] == true);
    try {
      await _supa.from('announcement').update({'active': !cur}).eq('ann_id', annId);
      await _refresh();
    } catch (e) {
      _toast('Update failed: $e', bg: Colors.red);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AdminModuleHeader(
          icon: Icons.local_offer_outlined,
          title: 'Promotions',
          subtitle: 'Vouchers and announcements',
          actions: [
            IconButton(
              tooltip: 'Refresh',
              onPressed: _refresh,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
          primaryActions: [
            FilledButton.tonalIcon(
              onPressed: () => _openUpsertVoucher(),
              icon: const Icon(Icons.confirmation_number_outlined),
              label: const Text('New voucher'),
            ),
            FilledButton.tonalIcon(
              onPressed: () => _openUpsertAnnouncement(),
              icon: const Icon(Icons.campaign_outlined),
              label: const Text('New announcement'),
            ),
          ],
        ),
        const Divider(height: 1),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              children: [
                Text(
                  'Vouchers',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                FutureBuilder<List<Map<String, dynamic>>>(
              future: _promoFuture,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: CircularProgressIndicator(),
                    ),
                  );
                }
                final rows = snap.data ?? const [];
                if (rows.isEmpty) {
                  return Text('No vouchers yet.', style: TextStyle(color: Colors.grey.shade700));
                }
                return Column(
                  children: rows.map((p) {
                    final code = (p['code'] ?? '').toString();
                    final active = (p['active'] == true);
                    final title = (p['title'] ?? '').toString().trim();
                    final start = _parseDate(p['start_at']);
                    final end = _parseDate(p['end_at']);
                    final maxRedeems = p['max_redeems'];
                    final maxRedeemsStr = (maxRedeems == null || maxRedeems.toString().trim().isEmpty)
                        ? ''
                        : ' | Max: ${maxRedeems.toString()}';

                    return AdminCard(
                      child: ListTile(
                        title: Text(
                          title.isEmpty ? code : '$title ($code)',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: Text(
                          'Discount: ${_fmtDiscount(p)}\n'
                          'Date: ${_fmtDate(start)} → ${_fmtDate(end)}$maxRedeemsStr',
                        ),
                        isThreeLine: true,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AdminStatusChip(status: active ? 'Active' : 'Inactive'),
                            PopupMenuButton<String>(
                              onSelected: (v) {
                                if (v == 'edit') _openUpsertVoucher(initial: p);
                                if (v == 'toggle') _toggleVoucherActive(p);
                                if (v == 'delete') _deleteVoucher(p);
                              },
                              itemBuilder: (ctx) => const [
                                PopupMenuItem(value: 'edit', child: Text('Edit')),
                                PopupMenuItem(value: 'toggle', child: Text('Toggle active')),
                                PopupMenuItem(value: 'delete', child: Text('Delete')),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
                const SizedBox(height: 18),
                Text(
                  'Announcements',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                FutureBuilder<List<Map<String, dynamic>>>(
              future: _annFuture,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: CircularProgressIndicator(),
                    ),
                  );
                }
                final rows = snap.data ?? const [];
                if (rows.isEmpty) {
                  return Text('No announcements yet.', style: TextStyle(color: Colors.grey.shade700));
                }
                return Column(
                  children: rows.map((a) {
                    final title = (a['title'] ?? '').toString();
                    final msg = (a['message'] ?? '').toString();
                    final promo = (a['promo_code'] ?? '').toString();
                    final active = (a['active'] == true);
                    final start = _parseDate(a['start_at']);
                    final end = _parseDate(a['end_at']);

                    return AdminCard(
                      child: ListTile(
                        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                        subtitle: Text(
                          '${promo.isEmpty ? msg : '$msg\nVoucher: $promo'}\n'
                          'Date: ${_fmtDate(start)} → ${_fmtDate(end)}',
                        ),
                        isThreeLine: true,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AdminStatusChip(status: active ? 'Active' : 'Inactive'),
                            PopupMenuButton<String>(
                              onSelected: (v) {
                                if (v == 'edit') _openUpsertAnnouncement(initial: a);
                                if (v == 'toggle') _toggleAnnouncementActive(a);
                                if (v == 'delete') _deleteAnnouncement(a);
                              },
                              itemBuilder: (ctx) => const [
                                PopupMenuItem(value: 'edit', child: Text('Edit')),
                                PopupMenuItem(value: 'toggle', child: Text('Toggle active')),
                                PopupMenuItem(value: 'delete', child: Text('Delete')),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
