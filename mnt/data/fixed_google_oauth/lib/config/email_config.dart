// Email Configuration
// Configure your email settings here
class EmailConfig {
  // Gmail SMTP Settings
  static const String smtpHost = 'smtp.gmail.com';
  static const int smtpPort = 465; // Gmail uses 465 for SSL
  static const bool smtpSecure = true; // SSL required for Gmail
  
  // Your Gmail account
  static const String senderEmail = 'fcarsy0001@gmail.com';
  static const String senderName = 'Car Rental System';
  
  // App Password (NOT your regular Gmail password)
  // Get this from: Google Account > Security > 2-Step Verification > App Passwords
  // IMPORTANT: Do NOT hardcode secrets in a Flutter client app.
  // Provide it at runtime, e.g.:
  // flutter run --dart-define=GMAIL_APP_PASSWORD=xxxx
  static const String senderPassword = String.fromEnvironment(
    'GMAIL_APP_PASSWORD',
    defaultValue: '',
  );
  

  
  // Verification link base URL
  // Use deep link format: yourapp://verify
  // Or web URL if you have a web version: https://yourapp.com/verify
  // For Flutter apps, use deep link to open the app
  static const String verificationBaseUrl = 'carrentalsystem://verify';
  
  // Email templates
  static String getOTPEmailBody(String otp, String recipientName) {
    return '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <style>
    body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; }
    .container { max-width: 600px; margin: 0 auto; padding: 20px; }
    .header { background-color: #2563EB; color: white; padding: 20px; text-align: center; border-radius: 8px 8px 0 0; }
    .content { background-color: #f9fafb; padding: 30px; border-radius: 0 0 8px 8px; }
    .otp-box { background-color: white; border: 2px solid #2563EB; border-radius: 8px; padding: 20px; text-align: center; margin: 20px 0; }
    .otp-code { font-size: 32px; font-weight: bold; color: #2563EB; letter-spacing: 8px; }
    .footer { text-align: center; margin-top: 20px; color: #666; font-size: 12px; }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <h1>Car Rental System</h1>
      <p>Email Verification</p>
    </div>
    <div class="content">
      <h2>Hello $recipientName,</h2>
      <p>Thank you for registering with Car Rental System. Please use the following OTP code to verify your email address:</p>
      
      <div class="otp-box">
        <p style="margin: 0; color: #666; font-size: 14px;">Your verification code:</p>
        <div class="otp-code">$otp</div>
      </div>
      
      <p>This code will expire in <strong>10 minutes</strong>.</p>
      <p>If you didn't request this code, please ignore this email.</p>
      
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
  
  static String getVerificationLinkEmailBody(String verificationUrl, String recipientName) {
    return '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <style>
    body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; }
    .container { max-width: 600px; margin: 0 auto; padding: 20px; }
    .header { background-color: #2563EB; color: white; padding: 20px; text-align: center; border-radius: 8px 8px 0 0; }
    .content { background-color: #f9fafb; padding: 30px; border-radius: 0 0 8px 8px; }
    .button { display: inline-block; background-color: #2563EB; color: white; padding: 15px 30px; text-decoration: none; border-radius: 8px; margin: 20px 0; }
    .footer { text-align: center; margin-top: 20px; color: #666; font-size: 12px; }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <h1>Car Rental System</h1>
      <p>Email Verification</p>
    </div>
    <div class="content">
      <h2>Hello $recipientName,</h2>
      <p>Thank you for registering with Car Rental System. Please click the button below to verify your email address:</p>
      
      <div style="text-align: center;">
        <a href="$verificationUrl" class="button">Verify Email Address</a>
      </div>
      
      <p>Or copy and paste this link into your browser:</p>
      <p style="word-break: break-all; color: #2563EB;">$verificationUrl</p>
      
      <p>This link will expire in <strong>24 hours</strong>.</p>
      <p>If you didn't request this verification, please ignore this email.</p>
      
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
}

