import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../main.dart';
import 'leaser_reapply_page.dart';

enum LeaserStatus { pending, rejected }

class LeaserStatusPage extends StatelessWidget {
  const LeaserStatusPage({super.key, required this.status, this.remark, this.leaserId});

  final LeaserStatus status;
  final String? remark;

  final String? leaserId;

  SupabaseClient get _supa => Supabase.instance.client;

  Future<void> _logout(BuildContext context) async {
    try {
      await _supa.auth.signOut();
    } catch (_) {}
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthWrapper()),
      (route) => false,
    );
  }


  Future<String?> _resolveLeaserId() async {
    final user = _supa.auth.currentUser;
    if (user == null) return null;

    // 1) Resolve app_user.user_id by auth_uid (preferred) then email (fallback)
    String? userId;
    try {
      final u1 = await _supa
          .from('app_user')
          .select('user_id')
          .eq('auth_uid', user.id)
          .maybeSingle();
      userId = u1?['user_id'] as String?;
    } catch (_) {}

    if (userId == null && (user.email ?? '').isNotEmpty) {
      try {
        final u2 = await _supa
            .from('app_user')
            .select('user_id')
            .eq('user_email', user.email!)
            .maybeSingle();
        userId = u2?['user_id'] as String?;
      } catch (_) {}
    }

    if (userId == null) return null;

    // 2) Find latest leaser application for this user
    try {
      final lea = await _supa
          .from('leaser')
          .select('leaser_id')
          .eq('user_id', userId)
          .order('leaser_id', ascending: false)
          .limit(1)
          .maybeSingle();
      return lea?['leaser_id'] as String?;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPending = status == LeaserStatus.pending;
    final color = isPending ? Colors.orange : Colors.red;
    final title = isPending ? 'Application Pending' : 'Application Rejected';
    final subtitle = isPending
        ? 'Your leaser application is under review. Please wait for admin approval.'
        : 'Your leaser application was rejected. Please contact admin or resubmit with correct details.';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Leaser Status'),
        actions: [
          IconButton(
            tooltip: 'Logout',
            onPressed: () => _logout(context),
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isPending ? Icons.hourglass_top_rounded : Icons.block_rounded,
                size: 72,
                color: color,
              ),
              const SizedBox(height: 14),
              Text(
                title,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: color),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                subtitle,
                style: TextStyle(color: Colors.grey.shade700),
                textAlign: TextAlign.center,
              ),
              if (!isPending && (remark ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: Colors.red.withOpacity(0.06),
                    border: Border.all(color: Colors.red.withOpacity(0.25)),
                  ),
                  child: Text(
                    'Reject reason: ${remark!.trim()}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: () => _logout(context),
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Back to Login'),
              ),
if (!isPending) ...[
  const SizedBox(height: 10),
  OutlinedButton.icon(
    onPressed: () async {
      final passed = (leaserId ?? '').trim();
      final id = passed.isNotEmpty ? passed : await _resolveLeaserId();
      if (!context.mounted) return;
      if (id == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cannot load application. Please login again.')),
        );
        return;
      }
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => LeaserReapplyPage(leaserId: id)),
      );
    },
    icon: const Icon(Icons.refresh_rounded),
    label: const Text('Reapply'),
  ),
],

            ],
          ),
        ),
      ),
    );
  }
}
