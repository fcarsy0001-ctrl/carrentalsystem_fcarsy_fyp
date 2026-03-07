import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:app_links/app_links.dart';

import 'config/supabase_config.dart';
import 'login/login.dart';
import 'login/update_password.dart';
import 'login/verification_page.dart';
import 'login/account_disabled_page.dart';
import 'admin/admin_shell.dart';
import 'services/admin_access_service.dart';
import 'services/leaser_access_service.dart';
import 'leaser/leaser_shell.dart';
import 'leaser/leaser_status_page.dart';
import 'shell/main_shell.dart';

SupabaseClient get supabase => Supabase.instance.client;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: SupabaseConfig.supabaseUrl,
    anonKey: SupabaseConfig.supabaseAnonKey,
  );


  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  static final GlobalKey<NavigatorState> navKey = GlobalKey<NavigatorState>();

  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSub;
  late final StreamSubscription<AuthState> _authSub;

  SupabaseClient get _supa => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _listenAuthEvents();
    _initDeepLinks();
    _handleWebAuthRedirectIfAny();
  }

  void _listenAuthEvents() {
    _authSub = _supa.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.passwordRecovery) {
        navKey.currentState?.push(
          MaterialPageRoute(builder: (_) => const UpdatePasswordPage()),
        );
      }
    });
  }

  Future<void> _handleWebAuthRedirectIfAny() async {
    if (!kIsWeb) return;

    try {
      await _supa.auth.getSessionFromUrl(Uri.base);

      final hasRecoveryHint = Uri.base.toString().contains('type=recovery') ||
          Uri.base.toString().contains('password_recovery') ||
          Uri.base.toString().contains('token_hash');

      if (hasRecoveryHint && _supa.auth.currentSession != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          navKey.currentState?.push(
            MaterialPageRoute(builder: (_) => const UpdatePasswordPage()),
          );
        });
      }
    } catch (_) {}
  }

  Future<void> _initDeepLinks() async {
    final initial = await _appLinks.getInitialLink();
    if (initial != null) {
      await _handleIncomingUri(initial);
    }

    _linkSub = _appLinks.uriLinkStream.listen((uri) async {
      await _handleIncomingUri(uri);
    });
  }

  Future<void> _handleIncomingUri(Uri uri) async {
    final isCustomScheme = uri.scheme.toLowerCase() == 'carrentalsystem';
    if (!isCustomScheme) return;

    final host = uri.host.toLowerCase();
    final segments = uri.pathSegments.map((e) => e.toLowerCase()).toList();
    final isResetPassword =
        host == 'reset-password' || segments.contains('reset-password');
    final isVerify = host == 'verify' || segments.contains('verify');
    final isLoginCallback =
        host == 'login-callback' || segments.contains('login-callback');


    // ✅ Google OAuth callback deep link
    if (isLoginCallback) {
      try {
        await _supa.auth.getSessionFromUrl(uri);
      } catch (_) {}

      WidgetsBinding.instance.addPostFrameCallback((_) {
        navKey.currentState?.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const AuthWrapper()),
          (route) => false,
        );
      });
      return;
    }

    // ✅ Password reset deep link
    if (isResetPassword) {
      final tokenHash = uri.queryParameters['token_hash'];

      try {
        if (tokenHash != null && tokenHash.isNotEmpty) {
          // ✅ gotrue 2.18.0 uses verifyOTP (capital OTP)
          await _supa.auth.verifyOTP(
            type: OtpType.recovery,
            tokenHash: tokenHash,
          );
        } else {
          // Old flow: #access_token=... in fragment
          await _supa.auth.getSessionFromUrl(uri);
        }
      } catch (_) {}

      WidgetsBinding.instance.addPostFrameCallback((_) {
        navKey.currentState?.push(
          MaterialPageRoute(builder: (_) => const UpdatePasswordPage()),
        );
      });

      return;
    }

    // ✅ Your custom verify link (optional - keep if you use it)
    if (isVerify) {
      final token = uri.queryParameters['token'];
      if (token == null || token.isEmpty) return;

      try {
        final response = await supabase
            .from('verification_codes')
            .select('email')
            .eq('type', 'link')
            .eq('code', token)
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle();

        final email = response?['email'] as String?;
        if (email == null || email.isEmpty) return;

        WidgetsBinding.instance.addPostFrameCallback((_) {
          navKey.currentState?.push(
            MaterialPageRoute(
              builder: (_) => VerificationPage(
                email: email,
                verificationType: 'link',
                token: token,
              ),
            ),
          );
        });
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _authSub.cancel();
    _linkSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navKey,
      debugShowCheckedModeBanner: false,
      title: 'Car Rental System',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF0EA5A4),
      ),
      home: const AuthWrapper(),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({Key? key}) : super(key: key);

  SupabaseClient get _supa => Supabase.instance.client;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: _supa.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = _supa.auth.currentSession;
        if (session == null) return const LoginPage();
        return _RoleGate(client: _supa);
      },
    );
  }
}

class _RoleGate extends StatelessWidget {
  const _RoleGate({required this.client});

  final SupabaseClient client;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_GateResult>(
      future: _compute(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final r = snapshot.data;
        if (r == null) return const MainShell();
        switch (r.kind) {
          case _GateKind.admin:
            return AdminShell(isSuperAdmin: r.isSuperAdmin);
          case _GateKind.leaserApproved:
            return LeaserShell(leaserId: r.leaserId!);
          case _GateKind.leaserPending:
            return const LeaserStatusPage(status: LeaserStatus.pending);
          case _GateKind.leaserRejected:
            return LeaserStatusPage(
              status: LeaserStatus.rejected,
              remark: r.leaserRemark,
              leaserId: r.leaserId,
            );
          case _GateKind.disabled:
            return AccountDisabledPage(message: r.disabledMessage ?? 'Your account has been deactivated. Please contact admin.');
          case _GateKind.user:
          default:
            return const MainShell();
        }
      },
    );
  }

  Future<_GateResult> _compute() async {
    final authUser = client.auth.currentUser;
    if (authUser == null) return _GateResult.user();

    // 0) Read app_user role/status (best-effort; do not block login if RLS denies)
    String role = 'user';
    String userStatus = 'Active';
    String userId = '';
    try {
      final u = await client
          .from('app_user')
          .select('user_id,user_role,user_status')
          .eq('auth_uid', authUser.id)
          .limit(1)
          .maybeSingle();
      if (u != null) {
        role = (u['user_role'] ?? 'User').toString().trim().toLowerCase();
        userStatus = (u['user_status'] ?? 'Active').toString().trim();
        userId = (u['user_id'] ?? '').toString().trim();
      }
    } catch (_) {}

    // 1) Admin / staff admin (ACTIVE)
    final admin = await AdminAccessService(client).getAdminContext();
    if (admin.isAdmin) {
      return _GateResult.admin(isSuperAdmin: admin.isSuperAdmin);
    }

    // 1b) Staff/Admin exists but is INACTIVE -> block from user home
    // Staff
    try {
      final rows = await client
          .from('staff_admin')
          .select('sadmin_status')
          .eq('auth_uid', authUser.id)
          .limit(1);
      if (rows is List && rows.isNotEmpty) {
        final st = (rows.first as Map)['sadmin_status']?.toString().trim().toLowerCase() ?? '';
        if (st.isNotEmpty && st != 'active') {
          return _GateResult.disabled('Your account has been deactivated. Please contact admin.');
        }
      }
    } catch (_) {}
    // Admin
    try {
      final rows = await client
          .from('admin')
          .select('admin_status')
          .eq('auth_uid', authUser.id)
          .limit(1);
      if (rows is List && rows.isNotEmpty) {
        final st = (rows.first as Map)['admin_status']?.toString().trim().toLowerCase() ?? '';
        if (st.isNotEmpty && st != 'active') {
          return _GateResult.disabled('Your account has been deactivated. Please contact admin.');
        }
      }
    } catch (_) {}

    // 2) Leaser routing:
    // If app_user role is leaser -> NEVER allow MainShell.
    final isLeaserRole = role == 'leaser';
    if (isLeaserRole) {
      // If user itself is disabled
      if (userStatus.trim().toLowerCase() != 'active') {
        return _GateResult.disabled('Your account has been deactivated. Please contact admin.');
      }

      // Try to read leaser application status; if RLS blocks, treat as pending.
      final leaser = await LeaserAccessService(client).getLeaserContext();

      // If we cannot read leaser row but role says leaser, treat as pending.
      if (!leaser.isLeaser) {
        return _GateResult.leaserPending();
      }

      if (leaser.state == LeaserState.disabled) {
        return _GateResult.disabled('Your leaser account has been deactivated. Please contact admin.');
      }

      if (leaser.state == LeaserState.approved) {
        // Approved leaser can only access Leaser/Admin home.
        return _GateResult.leaserApproved(leaser.leaserId ?? userId);
      }

      if (leaser.state == LeaserState.rejected) {
        return _GateResult.leaserRejected(leaser.remark, leaserId: leaser.leaserId);
      }

      return _GateResult.leaserPending();
    }

    
// 2b) Leaser by table existence (legacy accounts)
final leaser2 = await LeaserAccessService(client).getLeaserContext();
if (leaser2.isLeaser) {
  if (leaser2.state == LeaserState.disabled) {
    return _GateResult.disabled('Your leaser account has been deactivated. Please contact admin.');
  }
  if (leaser2.state == LeaserState.approved) {
    return _GateResult.leaserApproved(leaser2.leaserId ?? userId);
  }
  if (leaser2.state == LeaserState.rejected) {
    return _GateResult.leaserRejected(leaser2.remark, leaserId: leaser2.leaserId);
  }
  return _GateResult.leaserPending();
}

// 3) Normal user
    // If we successfully read app_user and status is not Active, block access.
    // (Supabase Auth alone will still allow sign-in; this is the app-side gate.)
    if (userId.trim().isNotEmpty && userStatus.trim().toLowerCase() != 'active') {
      return _GateResult.disabled('Your account has been deactivated. Please contact admin.');
    }
    return _GateResult.user();
  }
}

enum _GateKind {
  user,
  admin,
  leaserApproved,
  leaserPending,
  leaserRejected,
  disabled,
}


class _GateResult {
  const _GateResult._(
    this.kind, {
    this.isSuperAdmin = false,
    this.leaserId,
    this.leaserRemark,
    this.disabledMessage,
  });

  final _GateKind kind;
  final bool isSuperAdmin;
  final String? leaserId;
  final String? leaserRemark;
  final String? disabledMessage;

  factory _GateResult.user() => const _GateResult._(_GateKind.user);

  factory _GateResult.admin({required bool isSuperAdmin}) =>
      _GateResult._(_GateKind.admin, isSuperAdmin: isSuperAdmin);

  factory _GateResult.leaserApproved(String leaserId) =>
      _GateResult._(_GateKind.leaserApproved, leaserId: leaserId);

  factory _GateResult.leaserPending() => const _GateResult._(_GateKind.leaserPending);

  factory _GateResult.leaserRejected(String? remark, {String? leaserId}) =>
      _GateResult._(_GateKind.leaserRejected, leaserId: leaserId, leaserRemark: remark);

  factory _GateResult.disabled(String message) =>
      _GateResult._(_GateKind.disabled, disabledMessage: message);
}
