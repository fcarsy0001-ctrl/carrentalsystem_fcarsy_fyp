import 'dart:math';
import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../main.dart';
import '../config/email_config.dart';

class EmailVerificationService {
  static const int _otpLength = 6;
  static const int _otpExpiryMinutes = 10;
  static const int _linkExpiryHours = 24;

  // Generate a random 6-digit OTP
  static String generateOTP() {
    final random = Random();
    return (100000 + random.nextInt(900000)).toString();
  }

  // Generate a unique verification token for email link
  static String generateVerificationToken() {
    const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random();
    return String.fromCharCodes(Iterable.generate(
      32,
      (_) => chars.codeUnitAt(random.nextInt(chars.length)),
    ));
  }

  // Store OTP in database
  static Future<void> storeOTP(String email, String otp) async {
    final expiresAt = DateTime.now().add(Duration(minutes: _otpExpiryMinutes));
    
    // Store in a verification_codes table
    await supabase.from('verification_codes').upsert({
      'email': email,
      'code': otp,
      'type': 'otp',
      'expires_at': expiresAt.toIso8601String(),
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  // Store verification link token in database
  static Future<String> storeVerificationLink(String email) async {
    final token = generateVerificationToken();
    final expiresAt = DateTime.now().add(Duration(hours: _linkExpiryHours));
    
    await supabase.from('verification_codes').upsert({
      'email': email,
      'code': token,
      'type': 'link',
      'expires_at': expiresAt.toIso8601String(),
      'created_at': DateTime.now().toIso8601String(),
    });

    return token;
  }

  // Verify OTP
  static Future<bool> verifyOTP(String email, String otp) async {
    try {
      final response = await supabase
          .from('verification_codes')
          .select()
          .eq('email', email)
          .eq('type', 'otp')
          .eq('code', otp)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (response == null) {
        return false;
      }

      final expiresAt = DateTime.parse(response['expires_at'] as String);
      if (DateTime.now().isAfter(expiresAt)) {
        // Delete expired code
        await supabase
            .from('verification_codes')
            .delete()
            .eq('email', email)
            .eq('type', 'otp')
            .eq('code', otp);
        return false;
      }

      // Delete used code
      await supabase
          .from('verification_codes')
          .delete()
          .eq('email', email)
          .eq('type', 'otp')
          .eq('code', otp);

      return true;
    } catch (e) {
      return false;
    }
  }

  // Verify link token
  static Future<bool> verifyLink(String token) async {
    try {
      final response = await supabase
          .from('verification_codes')
          .select()
          .eq('type', 'link')
          .eq('code', token)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (response == null) {
        return false;
      }

      final expiresAt = DateTime.parse(response['expires_at'] as String);
      if (DateTime.now().isAfter(expiresAt)) {
        // Delete expired token
        await supabase
            .from('verification_codes')
            .delete()
            .eq('type', 'link')
            .eq('code', token);
        return false;
      }

      // Delete used token
      await supabase
          .from('verification_codes')
          .delete()
          .eq('type', 'link')
          .eq('code', token);

      return true;
    } catch (e) {
      return false;
    }
  }

  // Get email from verification token
  static Future<String?> getEmailFromToken(String token) async {
    try {
      final response = await supabase
          .from('verification_codes')
          .select('email')
          .eq('type', 'link')
          .eq('code', token)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (response == null) {
        return null;
      }

      return response['email'] as String?;
    } catch (e) {
      return null;
    }
  }

  // Send OTP email - uses Gmail SMTP (mobile/desktop only)
  static Future<void> sendOTPEmail(String email, String otp) async {
    if (kIsWeb) {
      throw Exception(
        'Gmail SMTP cannot run on web. Please run on mobile/desktop or deploy the Supabase Edge Function.'
      );
    }

    // Store OTP in database first
    await storeOTP(email, otp);
    print('✅ OTP stored in database');

    // Send via Gmail SMTP
    try {
      print('📧 Starting to send OTP email via Gmail SMTP to $email');

      if (EmailConfig.senderPassword.trim().isEmpty) {
        throw Exception('Missing GMAIL_APP_PASSWORD. Run with --dart-define=GMAIL_APP_PASSWORD=...');
      }

      final smtpServer = SmtpServer(
        EmailConfig.smtpHost,
        port: EmailConfig.smtpPort,
        ssl: EmailConfig.smtpSecure,
        allowInsecure: !EmailConfig.smtpSecure,
        username: EmailConfig.senderEmail,
        password: EmailConfig.senderPassword,
      );

      final message = Message()
        ..from = Address(EmailConfig.senderEmail, EmailConfig.senderName)
        ..recipients.add(email)
        ..subject = 'Car Rental System - Email Verification Code'
        ..html = EmailConfig.getOTPEmailBody(otp, email.split('@')[0]);

      await send(message, smtpServer).timeout(
        const Duration(seconds: 30),
        onTimeout: () => throw Exception('Email sending timeout after 30 seconds'),
      );

      print('✅ OTP email sent successfully to $email');
    } catch (e, stackTrace) {
      print('❌ Error sending OTP email: $e');
      print('❌ Stack trace: $stackTrace');
      throw Exception('Failed to send email: $e');
    }
  }

  // Send verification link email - uses Gmail SMTP (mobile/desktop only)
  static Future<void> sendVerificationLinkEmail(String email, String token) async {
    if (kIsWeb) {
      throw Exception(
        'Gmail SMTP cannot run on web. Please run on mobile/desktop or deploy the Supabase Edge Function.'
      );
    }

    print('✅ Verification token stored in database');

    try {
      print('📧 Starting to send verification link email via Gmail SMTP to $email');

      if (EmailConfig.senderPassword.trim().isEmpty) {
        throw Exception('Missing GMAIL_APP_PASSWORD. Run with --dart-define=GMAIL_APP_PASSWORD=...');
      }

      final verificationUrl = '${EmailConfig.verificationBaseUrl}?token=$token';

      final smtpServer = SmtpServer(
        EmailConfig.smtpHost,
        port: EmailConfig.smtpPort,
        ssl: EmailConfig.smtpSecure,
        allowInsecure: !EmailConfig.smtpSecure,
        username: EmailConfig.senderEmail,
        password: EmailConfig.senderPassword,
      );

      final message = Message()
        ..from = Address(EmailConfig.senderEmail, EmailConfig.senderName)
        ..recipients.add(email)
        ..subject = 'Car Rental System - Verify Your Email Address'
        ..html = EmailConfig.getVerificationLinkEmailBody(verificationUrl, email.split('@')[0]);

      await send(message, smtpServer).timeout(
        const Duration(seconds: 30),
        onTimeout: () => throw Exception('Email sending timeout after 30 seconds'),
      );

      print('✅ Verification link email sent successfully to $email');
    } catch (e, stackTrace) {
      print('❌ Error sending verification link email: $e');
      print('❌ Stack trace: $stackTrace');
      throw Exception('Failed to send email: $e');
    }
  }

  // Resend OTP
  static Future<String> resendOTP(String email) async {
    final newOtp = generateOTP();
    await sendOTPEmail(email, newOtp);
    return newOtp;
  }
}

