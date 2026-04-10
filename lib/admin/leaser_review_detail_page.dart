import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import '../services/leaser_application_service.dart';

class LeaserReviewDetailPage extends StatefulWidget {
  const LeaserReviewDetailPage({super.key, required this.row});

  final Map<String, dynamic> row;

  @override
  State<LeaserReviewDetailPage> createState() => _LeaserReviewDetailPageState();
}

class _LeaserReviewDetailPageState extends State<LeaserReviewDetailPage> {
  SupabaseClient get _supa => Supabase.instance.client;
  late final LeaserApplicationService _svc;

  bool _busy = false;
  String? _signedSsmUrl;

  String _s(dynamic v) => v == null ? '' : v.toString();

  @override
  void initState() {
    super.initState();
    _svc = LeaserApplicationService(_supa);
    _loadSsm();
  }

  Future<Session> _requireAdminSession() async {
    Session? session;
    try {
      final refreshed = await _supa.auth.refreshSession();
      session = refreshed.session;
    } catch (_) {
      // ignore
    }
    session ??= _supa.auth.currentSession;
    if (session == null || session.accessToken.isEmpty) {
      throw Exception('Admin session expired. Please login again.');
    }
    return session;
  }

  Future<Map<String, dynamic>> _invokeLeaserFunctionHttp({
    required List<String> names,
    required Map<String, dynamic> body,
    required String token,
  }) async {
    Object? lastError;

    for (final name in names) {
      HttpClient? client;
      try {
        client = HttpClient();
        final request = await client.postUrl(
          Uri.parse('${SupabaseConfig.supabaseUrl}/functions/v1/$name'),
        );
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
        request.headers.set('x-user-jwt', token);
        request.headers.set('apikey', SupabaseConfig.supabaseAnonKey);
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));

        final response = await request.close();
        final text = await utf8.decoder.bind(response).join();
        if (response.statusCode == 404) {
          lastError = Exception('Function $name not found.');
          continue;
        }

        dynamic data;
        if (text.isNotEmpty) {
          try {
            data = jsonDecode(text);
          } catch (_) {
            data = text;
          }
        }

        if (response.statusCode >= 400) {
          throw Exception('$name HTTP ${response.statusCode}: ${data ?? text}');
        }
        if (data is Map) {
          return Map<String, dynamic>.from(data);
        }
        return {'ok': true, 'data': data};
      } catch (e) {
        lastError = e;
        final lower = e.toString().toLowerCase();
        if (lower.contains('404')) {
          continue;
        }
        break;
      } finally {
        client?.close(force: true);
      }
    }

    if (lastError != null) {
      throw Exception(lastError.toString());
    }
    throw Exception('Requested function was not found.');
  }

  Future<void> _deleteLeaserDirectWithoutAuth({
    required String leaserId,
    required String storagePath,
  }) async {
    final vehicleRows = await _supa.from('vehicle').select('vehicle_id').eq('leaser_id', leaserId);
    final vehicleIds = <String>[];
    if (vehicleRows is List) {
      for (final raw in vehicleRows) {
        final vehicleId = _s((raw as Map)['vehicle_id']).trim();
        if (vehicleId.isNotEmpty) vehicleIds.add(vehicleId);
      }
    }

    if (vehicleIds.isNotEmpty) {
      final inValue = '(${vehicleIds.join(',')})';
      final bookings = await _supa
          .from('booking')
          .select('booking_id')
          .filter('vehicle_id', 'in', inValue)
          .limit(1);
      if (bookings is List && bookings.isNotEmpty) {
        throw Exception(
          'Cannot delete this leaser because their vehicles have bookings. Deactivate the leaser instead, or cancel/remove bookings first.',
        );
      }
      await _supa.from('vehicle').delete().eq('leaser_id', leaserId);
    }

    final userId = _s(widget.row['user_id']).trim();
    if (userId.isNotEmpty) {
      try {
        await _supa.from('app_user').delete().eq('user_id', userId);
      } catch (_) {}
    }

    await _supa.from('leaser').delete().eq('leaser_id', leaserId);

    if (storagePath.isNotEmpty) {
      try {
        await _supa.storage.from(LeaserApplicationService.bucketId).remove([storagePath]);
      } catch (_) {}
    }
  }

  Future<void> _loadSsm() async {
    final path = _s(widget.row['ssm_photo_path']).trim();
    if (path.isEmpty) return;
    final url = await _svc.createSignedSsmUrl(path);
    if (!mounted) return;
    setState(() => _signedSsmUrl = url);
  }

  Future<void> _setStatus(String status, {String? remark}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final id = _s(widget.row['leaser_id']).trim();
      if (id.isEmpty) throw Exception('Missing leaser_id');

      await _supa.from('leaser').update({
        'leaser_status': status,
        'reviewed_at': DateTime.now().toIso8601String(),
        'leaser_reject_remark': remark,
      }).eq('leaser_id', id);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Updated: $status'), backgroundColor: Colors.green),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject() async {
    final remark = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final c = TextEditingController();
        return AlertDialog(
          title: const Text('Reject leaser'),
          content: TextField(
            controller: c,
            decoration: const InputDecoration(
              labelText: 'Reject reason',
              hintText: 'e.g. SSM photo unclear / SSM no invalid',
            ),
            maxLines: 3,
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(null), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.of(ctx).pop(c.text.trim()), child: const Text('Reject')),
          ],
        );
      },
    );
    if (remark == null) return;
    await _setStatus('Rejected', remark: remark.isEmpty ? 'Rejected' : remark);
  }

  Future<void> _approve() async {
    await _setStatus('Approved', remark: null);
  }

  Future<void> _delete() async {
    final id = _s(widget.row['leaser_id']).trim();
    var authUid = _s(widget.row['auth_uid']).trim();
    if (id.isEmpty) return;

    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete leaser'),
        content: Text(
          'Delete leaser $id completely?\n\n'
          'The system will try to remove the linked Auth account first. If no Auth account is linked, it will remove the leaser record directly when safe.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Delete')),
        ],
      ),
    );
    if (yes != true) return;

    setState(() => _busy = true);
    try {
      final session = await _requireAdminSession();
      if (authUid.isEmpty) {
        authUid = await _resolveAuthUidForLeaser(widget.row);
      }

      final path = _s(widget.row['ssm_photo_path']).trim();
      final body = <String, dynamic>{'leaser_id': id};
      if (authUid.isNotEmpty) {
        body['auth_uid'] = authUid;
      }

      Map<String, dynamic> data;
      try {
        final res = await _supa.functions.invoke(
          'delete_leaser',
          headers: {
            'Authorization': 'Bearer ${session.accessToken}',
            'x-user-jwt': session.accessToken,
          },
          body: body,
        );
        if (res.status >= 400) {
          throw Exception('delete_leaser HTTP ${res.status}: ${res.data}');
        }
        data = res.data is Map ? Map<String, dynamic>.from(res.data as Map) : {'ok': true, 'data': res.data};
      } catch (e) {
        final lower = e.toString().toLowerCase();
        if (authUid.isEmpty &&
            (lower.contains('cannot resolve auth_uid') || lower.contains('auth_uid'))) {
          await _deleteLeaserDirectWithoutAuth(leaserId: id, storagePath: path);
          data = {'ok': true, 'fallback': 'direct-no-auth'};
        } else if (lower.contains('invalid jwt') || lower.contains('401') || lower.contains('not found')) {
          data = await _invokeLeaserFunctionHttp(
            names: const ['delete_leaser', 'delete-leaser'],
            body: body,
            token: session.accessToken,
          );
        } else {
          rethrow;
        }
      }

      final okResp = data['ok'] == true;
      if (!okResp) {
        final errorText = _s(data['error']).toLowerCase();
        if (authUid.isEmpty && errorText.contains('auth_uid')) {
          await _deleteLeaserDirectWithoutAuth(leaserId: id, storagePath: path);
        } else {
          throw Exception('delete_leaser failed: $data');
        }
      }

      final stillExists = await _supa.from('leaser').select('leaser_id').eq('leaser_id', id).maybeSingle();
      if (stillExists != null) {
        throw Exception('Delete reported success but record still exists. Check delete logic / FK constraints.');
      }

      if (path.isNotEmpty) {
        try {
          await _supa.storage.from(LeaserApplicationService.bucketId).remove([path]);
        } catch (_) {}
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Deleted'), backgroundColor: Colors.green),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete failed: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String> _resolveAuthUidForLeaser(Map<String, dynamic> row) async {
    final userId = _s(row['user_id']).trim();
    final email = _s(row['email']).trim();

    try {
      if (userId.isNotEmpty) {
        final u = await _supa.from('app_user').select('auth_uid').eq('user_id', userId).maybeSingle();
        final uid = (u?['auth_uid'] as String?)?.trim() ?? '';
        if (uid.isNotEmpty) return uid;
      }
      if (email.isNotEmpty) {
        final u = await _supa.from('app_user').select('auth_uid').eq('user_email', email).maybeSingle();
        final uid = (u?['auth_uid'] as String?)?.trim() ?? '';
        if (uid.isNotEmpty) return uid;
      }
    } catch (_) {}
    return '';
  }


  Future<void> _edit() async {
    final initial = widget.row;
    final name = TextEditingController(text: _s(initial['leaser_name']));
    final phone = TextEditingController(text: _s(initial['phone']));
    final ic = TextEditingController(text: _s(initial['ic_no']));
    final company = TextEditingController(text: _s(initial['company_name']));
    final owner = TextEditingController(text: _s(initial['owner_name']));
    final ssm = TextEditingController(text: _s(initial['ssm_no']));

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit leaser'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              children: [
                TextField(controller: name, decoration: const InputDecoration(labelText: 'Name / PIC')),
                TextField(controller: phone, decoration: const InputDecoration(labelText: 'Phone')),
                TextField(controller: ic, decoration: const InputDecoration(labelText: 'IC')),
                TextField(controller: company, decoration: const InputDecoration(labelText: 'Company Name')),
                TextField(controller: owner, decoration: const InputDecoration(labelText: 'Owner Name')),
                TextField(controller: ssm, decoration: const InputDecoration(labelText: 'SSM No')),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      final id = _s(widget.row['leaser_id']).trim();
      await _supa.from('leaser').update({
        'leaser_name': name.text.trim(),
        'phone': phone.text.trim(),
        'ic_no': ic.text.trim(),
        'company_name': company.text.trim().isEmpty ? null : company.text.trim(),
        'owner_name': owner.text.trim().isEmpty ? null : owner.text.trim(),
        'ssm_no': ssm.text.trim().isEmpty ? null : ssm.text.trim(),
      }).eq('leaser_id', id);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Updated'), backgroundColor: Colors.green),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Update failed: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setPassword() async {
    final authUid = _s(widget.row['auth_uid']).trim();
    if (authUid.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Missing auth_uid for this leaser.'), backgroundColor: Colors.red),
      );
      return;
    }

    final pw = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Set leaser password'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Enter a new password (min 8 characters).'),
              const SizedBox(height: 10),
              TextField(
                controller: pw,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'New password'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true) return;

    final newPw = pw.text.trim();
    if (newPw.length < 8) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password must be at least 8 characters.'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _busy = true);
    try {
      final session = _supa.auth.currentSession;
      if (session == null || session.accessToken.isEmpty) {
        throw Exception('Admin session expired. Please login again.');
      }

      await _supa.functions.invoke(
        'set_leaser_password',
        headers: {
          'Authorization': 'Bearer ${session.accessToken}',
          'x-user-jwt': session.accessToken,
        },
        body: {'auth_uid': authUid, 'new_password': newPw},
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password updated'), backgroundColor: Colors.green),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Update password failed: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }



  @override
  Widget build(BuildContext context) {
    final st = _s(widget.row['leaser_status']);
    final type = _s(widget.row['leaser_type']);
    final id = _s(widget.row['leaser_id']);

    return Scaffold(
      appBar: AppBar(
        title: Text('Leaser $id'),
        actions: [
          IconButton(tooltip: 'Edit', onPressed: _busy ? null : _edit, icon: const Icon(Icons.edit_outlined)),
          IconButton(tooltip: 'Password', onPressed: _busy ? null : _setPassword, icon: const Icon(Icons.lock_reset)),
          IconButton(tooltip: 'Delete', onPressed: _busy ? null : _delete, icon: const Icon(Icons.delete_outline)),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _busy ? null : _approve,
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('Approve'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: Colors.red),
                  onPressed: _busy ? null : _reject,
                  icon: const Icon(Icons.block_outlined),
                  label: const Text('Reject'),
                ),
              ),
            ],
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
        children: [
          Row(
            children: [
              _Chip(label: 'Status: ${st.isEmpty ? 'Pending' : st}'),
              const SizedBox(width: 8),
              _Chip(label: 'Type: ${type.isEmpty ? '-' : type}'),
            ],
          ),
          const SizedBox(height: 12),
          _RowKV('Leaser ID', widget.row['leaser_id']),
          _RowKV('User ID', widget.row['user_id']),
          _RowKV('Email', widget.row['email']),
          _RowKV('Phone', widget.row['phone']),
          _RowKV('IC', widget.row['ic_no']),
          _RowKV('Company Name', widget.row['company_name']),
          _RowKV('Owner/PIC Name', widget.row['owner_name']),
          _RowKV('SSM No', widget.row['ssm_no']),
          _RowKV('Submitted At', widget.row['submitted_at']),
          _RowKV('Reviewed At', widget.row['reviewed_at']),
          if (_s(widget.row['leaser_reject_remark']).trim().isNotEmpty)
            _RowKV('Reject Remark', widget.row['leaser_reject_remark']),

          const SizedBox(height: 12),
          if (_signedSsmUrl != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('SSM Photo', style: TextStyle(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        _signedSsmUrl!,
                        height: 220,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Padding(
                          padding: EdgeInsets.all(12),
                          child: Text('Failed to load SSM photo'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            const Text('No SSM photo'),
        ],
      ),
    );
  }
}

class _RowKV extends StatelessWidget {
  const _RowKV(this.k, this.v);

  final String k;
  final dynamic v;

  @override
  Widget build(BuildContext context) {
    final value = v == null ? '-' : v.toString();
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 130, child: Text(k, style: TextStyle(color: Colors.grey.shade700))),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w700))),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: Colors.grey.shade100,
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }
}
