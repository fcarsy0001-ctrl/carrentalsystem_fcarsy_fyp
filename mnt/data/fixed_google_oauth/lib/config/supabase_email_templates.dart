/// Copy-paste these templates into Supabase Dashboard:
/// Authentication -> Email Templates
///
/// Why? Supabase sends password reset emails from the server, so the email
/// HTML design is configured in the Supabase dashboard (not from Flutter code).
/// This file exists so you can keep your email UI consistent with your OTP
/// emails (same colors and layout).
class SupabaseEmailTemplates {
  /// Password Reset (Recovery) template
  ///
  /// Paste into: "Reset Password" / "Recovery" email template.
  /// Uses Supabase Go template placeholders.
  ///
  /// NOTE: Make sure your Redirect URLs include:
  /// carrentalsystem://reset-password
  static const String resetPasswordHtml = r'''
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <style>
    body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; }
    .container { max-width: 600px; margin: 0 auto; padding: 20px; }
    .header { background-color: #2563EB; color: white; padding: 20px; text-align: center; border-radius: 8px 8px 0 0; }
    .content { background-color: #f9fafb; padding: 30px; border-radius: 0 0 8px 8px; }
    .button { display: inline-block; background-color: #2563EB; color: white !important; padding: 15px 30px; text-decoration: none; border-radius: 8px; margin: 20px 0; }
    .note { font-size: 12px; color: #666; }
    .footer { text-align: center; margin-top: 20px; color: #666; font-size: 12px; }
    .link { word-break: break-all; color: #2563EB; }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <h1>Car Rental System</h1>
      <p>Password Reset</p>
    </div>
    <div class="content">
      <h2>Hello,</h2>
      <p>We received a request to reset the password for <strong>{{ .Email }}</strong>.</p>
      <p>Click the button below to set a new password:</p>

      <div style="text-align:center;">
        <!-- Direct deep link into the app (recommended for mobile) -->
        <a class="button" href="carrentalsystem://reset-password?token_hash={{ .TokenHash }}">
          Reset Password
        </a>
      </div>

      <p>Or copy and paste this link:</p>
      <p class="link">carrentalsystem://reset-password?token_hash={{ .TokenHash }}</p>

      <p class="note">If you didn't request a password reset, you can safely ignore this email.</p>
      <p>Best regards,<br>Car Rental System Team</p>
    </div>
    <div class="footer">
      <p>This is an automated email. Please do not reply to this message.</p>
    </div>
  </div>
</body>
</html>
''';
}
