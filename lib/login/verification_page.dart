import 'package:flutter/material.dart';
import '../main.dart';
import '../services/email_verification_service.dart';

class VerificationPage extends StatefulWidget {
  final String email;
  final String verificationType; // 'otp' or 'link'
  final String? otp; // For OTP type, the generated OTP (for testing)
  final String? token; // For link type, the verification token
  final String? password; // Password for auto-login after verification

  const VerificationPage({
    Key? key,
    required this.email,
    required this.verificationType,
    this.otp,
    this.token,
    this.password,// Password for auto-login
  }) : super(key: key);

  @override
  State<VerificationPage> createState() => _VerificationPageState();
}

class _VerificationPageState extends State<VerificationPage> {
  final _otpController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _isVerified = false;
  int _resendCooldown = 0;

  @override
  void initState() {
    super.initState();
    if (widget.verificationType == 'link' && widget.token != null) {
      // Auto-verify link if token is provided
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _verifyLink();
      });
    } else {
      _startResendCooldown();
    }
  }

  void _startResendCooldown() {
    _resendCooldown = 60; // 60 seconds cooldown
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (mounted) {
        setState(() {
          _resendCooldown--;
        });
        return _resendCooldown > 0;
      }
      return false;
    });
  }

  @override
  void dispose() {
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _verifyOTP() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final isValid = await EmailVerificationService.verifyOTP(
        widget.email,
        _otpController.text.trim(),
      );

      if (isValid) {
        // Mark user as verified in database
        await _markUserAsVerified();
        
        if (mounted) {
          setState(() {
            _isVerified = true;
            _isLoading = false;
          });

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Email verified successfully!'),
              backgroundColor: Colors.green,
            ),
          );

          // ✅ Security: force logout and require manual login again.
          Future.delayed(const Duration(seconds: 2), () async {
            try {
              await supabase.auth.signOut();
            } catch (_) {}
            if (!mounted) return;
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const AuthWrapper()),
              (route) => false,
            );
          });
        }
      } else {
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Invalid or expired OTP. Please try again.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _verifyLink() async {
    if (widget.token == null) return;

    setState(() => _isLoading = true);

    try {
      final isValid = await EmailVerificationService.verifyLink(widget.token!);

      if (isValid) {
        // Mark user as verified in database
        await _markUserAsVerified();
        
        if (mounted) {
          setState(() {
            _isVerified = true;
            _isLoading = false;
          });

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Email verified successfully!'),
              backgroundColor: Colors.green,
            ),
          );

          // ✅ Security: force logout and require manual login again.
          Future.delayed(const Duration(seconds: 2), () async {
            try {
              await supabase.auth.signOut();
            } catch (_) {}
            if (!mounted) return;
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const AuthWrapper()),
              (route) => false,
            );
          });
        }
      } else {
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Invalid or expired verification link.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _markUserAsVerified() async {
    try {
      // Update user's email_verified status in app_user table
      try {
        await supabase
            .from('app_user')
            .update({'email_verified': true})
            .eq('user_email', widget.email);
        print('✅ Updated email_verified in app_user table');
      } catch (e) {
        print('Warning: email_verified column may not exist. Error: $e');
      }

      // Note: Supabase Auth email confirmation status cannot be updated from client
      // The user needs to either:
      // 1. Disable "Enable email confirmations" in Supabase Dashboard → Authentication → Settings
      // 2. Or use an Edge Function with Admin API to mark email as confirmed
      print('ℹ️ To allow login, disable "Enable email confirmations" in Supabase Dashboard');
    } catch (e) {
      print('Error marking user as verified: $e');
      // Don't throw error, just log it - verification still succeeds
    }
  }

  Future<void> _resendOTP() async {
    if (_resendCooldown > 0) return;

    setState(() => _isLoading = true);

    try {
      await EmailVerificationService.resendOTP(widget.email);
      _startResendCooldown();
      
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('OTP has been resent to your email.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error resending OTP: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.verificationType == 'link') {
      // Link verification UI
      return Scaffold(
        appBar: AppBar(
          title: const Text('Email Verification'),
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Center(
              child: _isLoading
                  ? const CircularProgressIndicator()
                  : _isVerified
                      ? Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.check_circle,
                              color: Colors.green,
                              size: 80,
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'Email Verified!',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Your email has been successfully verified.',
                              style: TextStyle(color: Colors.grey[600]),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 24),
                            ElevatedButton(
                              onPressed: () {
                                Navigator.of(context).popUntil((route) => route.isFirst);
                              },
                              child: const Text('Go to Login'),
                            ),
                          ],
                        )
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.error_outline,
                              color: Colors.red,
                              size: 80,
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'Verification Failed',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'The verification link is invalid or has expired.',
                              style: TextStyle(color: Colors.grey[600]),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 24),
                            ElevatedButton(
                              onPressed: () {
                                Navigator.of(context).popUntil((route) => route.isFirst);
                              },
                              child: const Text('Go to Login'),
                            ),
                          ],
                        ),
            ),
          ),
        ),
      );
    }

    // OTP verification UI
    return Scaffold(
      appBar: AppBar(
        title: const Text('Verify Email'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  _isVerified ? Icons.check_circle : Icons.email_outlined,
                  size: 60,
                  color: _isVerified
                      ? Colors.green
                      : Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  _isVerified ? 'Email Verified!' : 'Verify Your Email',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _isVerified
                      ? 'Your email has been successfully verified.'
                      : 'We sent a 6-digit code to\n${widget.email}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
                // Removed development mode OTP display - emails are now sent to customer
                if (!_isVerified) ...[
                  const SizedBox(height: 32),
                  TextFormField(
                    controller: _otpController,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 8,
                    ),
                    maxLength: 6,
                    decoration: InputDecoration(
                      labelText: 'Enter OTP',
                      hintText: '000000',
                      counterText: '',
                      prefixIcon: const Icon(Icons.lock_outlined),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter the OTP';
                      }
                      if (value.length != 6) {
                        return 'OTP must be 6 digits';
                      }
                      if (!RegExp(r'^\d{6}$').hasMatch(value)) {
                        return 'OTP must contain only numbers';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _isLoading ? null : _verifyOTP,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Text('Verify'),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        "Didn't receive the code? ",
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                      TextButton(
                        onPressed: _resendCooldown > 0 || _isLoading
                            ? null
                            : _resendOTP,
                        child: Text(
                          _resendCooldown > 0
                              ? 'Resend in $_resendCooldown s'
                              : 'Resend',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  const SizedBox(height: 32),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).popUntil((route) => route.isFirst);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: const Text('Go to Login'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

