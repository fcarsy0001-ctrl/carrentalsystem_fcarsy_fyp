import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../main.dart';
import '../services/driver_license_service.dart';
import '../home/my_orders_page.dart';
import 'my_vouchers_page.dart';
import '../support/user_support_page.dart';
import '../features/profile/presentation/pages/wallet_page.dart';
import 'driver_license_page.dart';
import 'profile_info_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  SupabaseClient get _supa => Supabase.instance.client;

  late Future<Map<String, dynamic>?> _profileFuture;
  DriverLicenseSnapshot? _dl;

  @override
  void initState() {
    super.initState();
    _profileFuture = _loadProfile();
    _loadDriverLicense();
  }

  Future<void> _loadDriverLicense() async {
    final snap = await DriverLicenseService(_supa).getSnapshot();
    if (!mounted) return;
    setState(() => _dl = snap);
  }

  Future<Map<String, dynamic>?> _loadProfile() async {
    final user = _supa.auth.currentUser;
    if (user == null) return null;

    final row = await _supa
        .from('app_user')
        .select('*')
        .eq('auth_uid', user.id)
        .maybeSingle();

    if (row != null) return Map<String, dynamic>.from(row as Map);

    final meta = user.userMetadata ?? const <String, dynamic>{};
    return {
      'user_name': (meta['full_name'] as String?) ??
          (meta['name'] as String?) ??
          (user.email?.split('@').first ?? 'User'),
      'user_email': user.email ?? '',
    };
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return 'U';
    final first = parts.first.isNotEmpty ? parts.first[0] : 'U';
    final second = parts.length > 1 && parts[1].isNotEmpty ? parts[1][0] : '';
    return (first + second).toUpperCase();
  }

  String _str(Map<String, dynamic> data, String key) {
    final v = data[key];
    if (v == null) return '';
    return v.toString().trim();
  }

  String _dlSubtitle(DriverLicenseSnapshot? s) {
    if (s == null) return 'Check verification status';
    switch (s.state) {
      case DriverLicenseState.approved:
        return 'Approved • Ready to rent';
      case DriverLicenseState.pending:
        return 'Pending admin review';
      case DriverLicenseState.rejected:
        return 'Rejected • Resubmit required';
      case DriverLicenseState.notSubmitted:
        return 'Not submitted yet';
      case DriverLicenseState.unknown:
        return 'Check verification status';
    }
  }

  Future<void> _logout() async {
    try {
      await _supa.auth.signOut();
    } catch (_) {}

    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthWrapper()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: FutureBuilder<Map<String, dynamic>?>(
        future: _profileFuture,
        builder: (context, snap) {
          final data = snap.data;
          final name = data == null ? 'User' : (_str(data, 'user_name').isEmpty ? 'User' : _str(data, 'user_name'));
          final email = data == null ? (_supa.auth.currentUser?.email ?? '') : _str(data, 'user_email');
          final role = data == null ? '' : _str(data, 'user_role');
          final isNormalUser = role.toLowerCase() == 'user';

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  color: cs.surfaceContainerHighest.withOpacity(0.45),
                  border: Border.all(color: cs.outlineVariant.withOpacity(0.25)),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      child: Text(_initials(name),
                          style: const TextStyle(fontWeight: FontWeight.w900)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w900, fontSize: 16)),
                          const SizedBox(height: 4),
                          Text(
                            email.isEmpty ? '-' : email,
                            style: TextStyle(
                              color: Colors.grey.shade700,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Profile info access
              _MenuTile(
                icon: Icons.person_outline_rounded,
                title: 'Profile information',
                subtitle: 'View and edit your personal details',
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ProfileInfoPage()),
                  );
                  setState(() {
                    _profileFuture = _loadProfile();
                  });
                },
              ),
              const SizedBox(height: 10),

              if (isNormalUser) ...[
                // Driver licence access (submission + status) – users only
                _MenuTile(
                  icon: Icons.badge_outlined,
                  title: 'Driver licence verification',
                  subtitle: _dlSubtitle(_dl),
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const DriverLicensePage()),
                    );
                    await _loadDriverLicense();
                  },
                ),
                const SizedBox(height: 10),

                _MenuTile(
                  icon: Icons.receipt_long_outlined,
                  title: 'My orders',
                  subtitle: 'View ongoing and past orders',
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const MyOrdersPage()),
                    );
                  },
                ),
                const SizedBox(height: 10),

                _MenuTile(
                  icon: Icons.account_balance_wallet_outlined,
                  title: 'My wallet',
                  subtitle: 'Top up balance and view wallet activity',
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const WalletPage()),
                    );
                  },
                ),
                const SizedBox(height: 10),

                _MenuTile(
                  icon: Icons.local_offer_outlined,
                  title: 'My vouchers',
                  subtitle: 'Claim and use vouchers',
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const MyVouchersPage()),
                    );
                  },
                ),
                const SizedBox(height: 10),

                _MenuTile(
                  icon: Icons.support_agent_outlined,
                  title: 'Support',
                  subtitle: 'Open a ticket and chat with admin/staff',
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const UserSupportPage()),
                    );
                  },
                ),

                const SizedBox(height: 18),
              ],

              // Logout only here
              FilledButton.tonalIcon(
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Logout'),
                onPressed: _logout,
              ),
              const SizedBox(height: 10),
              if (isNormalUser)
                Text(
                  'Tip: You must have an approved driver licence to start a rental.',
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: cs.surfaceContainerHighest.withOpacity(0.40),
          border: Border.all(color: cs.outlineVariant.withOpacity(0.25)),
        ),
        child: Row(
          children: [
            Container(
              height: 46,
              width: 46,
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: cs.onPrimaryContainer),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 4),
                  Text(subtitle,
                      style:
                          TextStyle(color: Colors.grey.shade700, fontSize: 12)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
  }
}
