# Car Rental System - Authentication Setup Guide

## 📋 Overview

This guide will help you set up the authentication system for your Flutter car rental application with Supabase backend.

## 🎯 Features Implemented

- ✅ Email/Password Login
- ✅ Email/Password Registration
- ✅ Google Sign-In
- ✅ Password Reset
- ✅ Modern UI Design
- ✅ Form Validation
- ✅ Automatic User Profile Creation
- ✅ Integration with your database schema

## 📁 File Structure

```
lib/
├── main.dart                    # App entry point with Supabase initialization
└── login/
    ├── login.dart               # Login page
    ├── register.dart            # Registration page
    └── reset_password.dart      # Password reset page
```

## 🚀 Setup Instructions

### Step 1: Install Dependencies

Run the following command in your project directory:

```bash
flutter pub get
```

This will install all required packages:
- `supabase_flutter` - Supabase client for Flutter
- `google_sign_in` - Google authentication
- `google_fonts` - Beautiful fonts
- `flutter_svg` - SVG support
- `email_validator` - Email validation

### Step 2: Configure Supabase

1. **Get your Supabase credentials:**
   - Go to your Supabase project dashboard
   - Navigate to Settings > API
   - Copy your `Project URL` and `anon public` key

2. **Update credentials in `lib/main.dart`:**

```dart
// Replace these with your actual Supabase credentials
const supabaseUrl = 'YOUR_SUPABASE_URL';
const supabaseAnonKey = 'YOUR_SUPABASE_ANON_KEY';
```

### Step 3: Configure Google Sign-In

#### For Android:

1. **Get OAuth 2.0 Client ID:**
   - Go to [Google Cloud Console](https://console.cloud.google.com/)
   - Create a new project or select existing
   - Enable Google Sign-In API
   - Go to Credentials > Create Credentials > OAuth 2.0 Client ID
   - Select "Web application" and create
   - Copy the Client ID

2. **Add to your Supabase project:**
   - Go to Authentication > Providers > Google
   - Enable Google provider
   - Add your Client ID and Client Secret

3. **Update the Client ID in code:**
   - Open `lib/login/login.dart`
   - Find line with `const webClientId = 'YOUR_GOOGLE_WEB_CLIENT_ID'`
   - Replace with your actual Client ID
   - Do the same in `lib/login/register.dart`

#### For iOS:

1. Add to `ios/Runner/Info.plist`:

```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleTypeRole</key>
        <string>Editor</string>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>com.googleusercontent.apps.YOUR-CLIENT-ID</string>
        </array>
    </dict>
</array>
```

### Step 4: Configure Deep Links for Password Reset

#### For Android (`android/app/src/main/AndroidManifest.xml`):

Add inside `<activity>` tag:

```xml
<intent-filter>
    <action android:name="android.intent.action.VIEW" />
    <category android:name="android.intent.category.DEFAULT" />
    <category android:name="android.intent.category.BROWSABLE" />
    <data
        android:scheme="io.supabase.carrentalsystem"
        android:host="reset-password" />
</intent-filter>
```

#### For iOS (`ios/Runner/Info.plist`):

```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleTypeRole</key>
        <string>Editor</string>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>io.supabase.carrentalsystem</string>
        </array>
    </dict>
</array>
```

### Step 5: Database Setup

Your database schema is already set up! The authentication system will:

1. Create users in Supabase Auth
2. Automatically generate user IDs (U001, U002, etc.)
3. Insert user profiles into the `app_user` table
4. Link the auth user with your database user via `auth_uid`

Make sure your Supabase database has:
- ✅ The SQL schema you provided is already applied
- ✅ RLS (Row Level Security) policies are enabled
- ✅ The `app_user` table exists with proper structure

### Step 6: Email Templates (Optional)

Customize your Supabase email templates:

1. Go to Supabase Dashboard > Authentication > Email Templates
2. Customize:
   - Confirmation email (for new registrations)
   - Password reset email
   - Magic link email (if using)

## 🎨 UI Design Features

The authentication pages include:

- **Modern Material Design 3**
- **Custom color scheme** (Blue primary color)
- **Google Fonts** (Inter font family)
- **Responsive layouts**
- **Beautiful form inputs**
- **Loading states**
- **Error handling**
- **Password visibility toggle**
- **Validation feedback**

## 🔐 Security Features

- ✅ Password validation (minimum 6 characters)
- ✅ Email validation
- ✅ Secure password storage (handled by Supabase Auth)
- ✅ Row Level Security (RLS) policies
- ✅ Terms and conditions checkbox
- ✅ Proper error messages

## 📝 User Registration Flow

1. User fills in registration form:
   - Full Name
   - Email
   - Phone Number
   - IC Number (12 digits)
   - Gender
   - Password

2. System validates all fields

3. Creates account in Supabase Auth

4. Generates unique user_id (U001, U002, etc.)

5. Inserts profile into `app_user` table

6. Sends verification email (if enabled in Supabase)

7. User can now login

## 🔑 Login Flow

1. User enters email and password

2. System authenticates with Supabase

3. On success:
   - Session is created
   - User is redirected to HomePage
   - Auth state is persisted

4. Alternative: Google Sign-In
   - One-tap authentication
   - Profile auto-created if new user

## 🔄 Password Reset Flow

1. User clicks "Forgot Password?"

2. Enters email address

3. System sends reset link via email

4. User clicks link in email

5. Redirected to app to set new password

## 🧪 Testing

### Test the Login System:

1. **Register a new account:**
   ```
   - Run the app
   - Click "Sign Up"
   - Fill in all fields
   - Submit
   ```

2. **Login with credentials:**
   ```
   - Use the registered email/password
   - Click "Login"
   ```

3. **Test password reset:**
   ```
   - Click "Forgot Password?"
   - Enter email
   - Check email inbox
   ```

4. **Test Google Sign-In:**
   ```
   - Click "Continue with Google"
   - Select Google account
   ```

## 🐛 Troubleshooting

### Common Issues:

1. **"Invalid login credentials"**
   - Check if user is verified (check Supabase Auth dashboard)
   - Verify email is correct
   - Ensure password is correct

2. **Google Sign-In not working**
   - Verify Client ID is correct
   - Check if Google provider is enabled in Supabase
   - Ensure SHA-1 fingerprint is added (Android)

3. **Password reset email not received**
   - Check spam folder
   - Verify SMTP settings in Supabase
   - Check email templates are configured

4. **Database insert error**
   - Verify RLS policies allow insert
   - Check if user_id generation is working
   - Ensure all required fields are provided

## 📱 Next Steps

After authentication is working:

1. **Create the Home Page:**
   - Replace the placeholder `HomePage` in `main.dart`
   - Add vehicle browsing
   - Show user profile

2. **Add Profile Management:**
   - Allow users to update their profile
   - Add profile picture upload
   - Show booking history

3. **Implement Main Features:**
   - Vehicle listing
   - Booking system
   - Payment integration
   - Contract management

## 🎓 Code Explanation

### Authentication State Management:

The app uses `StreamBuilder` to listen to auth state changes:

```dart
StreamBuilder<AuthState>(
  stream: supabase.auth.onAuthStateChange,
  builder: (context, snapshot) {
    if (snapshot.hasData && snapshot.data!.session != null) {
      return const HomePage(); // User logged in
    }
    return const LoginPage(); // User not logged in
  },
)
```

### User ID Generation:

The system automatically generates sequential user IDs:

```dart
Future<String> _generateUserId() async {
  final response = await supabase
      .from('app_user')
      .select('user_id')
      .order('user_id', ascending: false)
      .limit(1);

  if (response.isEmpty) return 'U001';

  final lastUserId = response[0]['user_id'] as String;
  final lastNumber = int.parse(lastUserId.substring(1));
  return 'U${(lastNumber + 1).toString().padLeft(3, '0')}';
}
```

## 📞 Support

If you encounter any issues:

1. Check the Flutter console for error messages
2. Verify Supabase dashboard for auth logs
3. Check RLS policies are correctly configured
4. Ensure all credentials are properly set

## 🎉 You're All Set!

Your authentication system is now ready to use. Run the app with:

```bash
flutter run
```

Happy coding! 🚀
