import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../main.dart';

enum VendorStatus { pending, rejected }

class VendorStatusPage extends StatelessWidget {
  const VendorStatusPage({
    super.key,
    required this.status,
    this.remark,
  });

  final VendorStatus status;
  final String? remark;

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

  @override
  Widget build(BuildContext context) {
    final isPending = status == VendorStatus.pending;
    final color = isPending ? Colors.orange : Colors.red;
    final title = isPending ? 'Vendor Application Pending' : 'Vendor Application Rejected';
    final subtitle = isPending
        ? 'Your vendor registration is under admin review. Please wait for approval before accessing the vendor dashboard.'
        : 'Your vendor registration was rejected. Please contact admin and submit the correct business details again.';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Vendor Status'),
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
                    color: Colors.red.withValues(alpha: 0.06),
                    border: Border.all(color: Colors.red.withValues(alpha: 0.25)),
                  ),
                  child: Text(
                    'Reject reason: ',
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
            ],
          ),
        ),
      ),
    );
  }
}
