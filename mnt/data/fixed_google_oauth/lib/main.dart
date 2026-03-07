import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:app_links/app_links.dart';

import 'config/supabase_config.dart';
import 'login/login.dart';
import 'login/update_password.dart';
import 'login/verification_page.dart';

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
    final isLoginCallback =
        host == 'login-callback' || segments.contains('login-callback');
    final isResetPassword =
        host == 'reset-password' || segments.contains('reset-password');
    final isVerify = host == 'verify' || segments.contains('verify');

    // ✅ Supabase OAuth callback (Google login)
    // Example: carrentalsystem://login-callback#access_token=...&refresh_token=...&type=bearer
    if (isLoginCallback) {
      try {
        await _supa.auth.getSessionFromUrl(uri);
        await _ensureAppUserRow();
      } catch (_) {}

      // Take user to home (AuthWrapper will also rebuild once session exists)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        navKey.currentState?.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const HomePage()),
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

  /// Ensure there is a row in `app_user` for the current Supabase auth user.
  /// This is needed for Google OAuth users (they won't pass through your email sign-up form).
  Future<void> _ensureAppUserRow() async {
    final user = _supa.auth.currentUser;
    if (user == null) return;

    try {
      final existing = await _supa
          .from('app_user')
          .select('user_id')
          .eq('auth_uid', user.id)
          .maybeSingle();

      if (existing != null) return;

      final userId = await _generateNextUserId();
      final meta = user.userMetadata ?? {};
      final displayName = (meta['full_name'] ?? meta['name'] ?? '').toString();
      final name = displayName.isNotEmpty
          ? displayName
          : (user.email?.split('@').first ?? 'Google User');

      await _supa.from('app_user').insert({
        'user_id': userId,
        'auth_uid': user.id,
        'user_name': name,
        'user_email': user.email,
        'user_password': '***',
        'user_phone': '0000000000',
        'user_icno': '000000000000',
        'user_gender': 'Male',
        'user_role': 'User',
        'user_status': 'Active',
        'email_verified': true,
      });
    } catch (_) {
      // Ignore; user can still use basic auth session.
    }
  }

  Future<String> _generateNextUserId() async {
    try {
      final result = await _supa
          .from('app_user')
          .select('user_id')
          .order('user_id', ascending: false)
          .limit(1)
          .maybeSingle();

      final lastId = (result?['user_id'] ?? '').toString();
      final match = RegExp(r'^U(\d+)$').firstMatch(lastId);
      if (match == null) return 'U001';

      final lastNumber = int.tryParse(match.group(1) ?? '0') ?? 0;
      final next = lastNumber + 1;
      if (next > 999) {
        final ts = DateTime.now().millisecondsSinceEpoch;
        return 'U${ts.toString().substring(ts.toString().length - 6)}';
      }
      return 'U${next.toString().padLeft(3, '0')}';
    } catch (_) {
      final ts = DateTime.now().millisecondsSinceEpoch;
      return 'U${ts.toString().substring(ts.toString().length - 6)}';
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
        if (session != null) return const HomePage();
        return const LoginPage();
      },
    );
  }
}

/// If you already have your own HomePage, delete this one.
class HomePage extends StatelessWidget {
  const HomePage({Key? key}) : super(key: key);

  SupabaseClient get _supa => Supabase.instance.client;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Home'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async => _supa.auth.signOut(),
          ),
        ],
      ),
      body: Center(
        child: Text('Logged in: ${_supa.auth.currentUser?.email ?? "-"}'),
      ),
    );
  }
}
