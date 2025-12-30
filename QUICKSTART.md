# 🚀 Quick Start Guide

## 1. Install Dependencies

```bash
flutter pub get
```

## 2. Configure Supabase Credentials

Open `lib/config/supabase_config.dart` and replace the placeholders:

```dart
class SupabaseConfig {
  // From: Supabase Dashboard > Settings > API
  static const String supabaseUrl = 'https://xxxxx.supabase.co';
  static const String supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...';
  
  // From: Google Cloud Console > Credentials (Optional for Google Sign-In)
  static const String googleWebClientId = '123456789-xxxxxxxx.apps.googleusercontent.com';
  
  // Your app's deep link scheme (Optional for password reset)
  static const String resetPasswordRedirectUrl = 'io.supabase.carrentalsystem://reset-password/';
}
```

## 3. Run the App

```bash
flutter run
```

## 🎯 What's Included?

✅ **Login Page** - Email/Password + Google Sign-In  
✅ **Register Page** - Complete user registration with validation  
✅ **Reset Password** - Forgot password functionality  
✅ **Modern UI** - Beautiful Material Design 3  
✅ **Database Integration** - Automatic user profile creation  
✅ **RLS Support** - Works with your Supabase RLS policies

## 📁 File Structure

```
lib/
├── main.dart                      # App entry point
├── config/
│   └── supabase_config.dart      # Configuration (UPDATE THIS!)
└── login/
    ├── login.dart                # Login page
    ├── register.dart             # Register page
    └── reset_password.dart       # Password reset page
```

## 🔑 Where to Get Credentials?

### Supabase URL & Anon Key:
1. Go to [Supabase Dashboard](https://app.supabase.com)
2. Select your project
3. Go to Settings > API
4. Copy:
   - `Project URL` → `supabaseUrl`
   - `anon public` key → `supabaseAnonKey`

### Google Web Client ID (Optional):
1. Go to [Google Cloud Console](https://console.cloud.google.com)
2. Create/Select project
3. Go to APIs & Services > Credentials
4. Create OAuth 2.0 Client ID (Web application)
5. Copy Client ID

Then in Supabase:
- Go to Authentication > Providers
- Enable Google
- Add your Client ID and Secret

## 📱 Test the App

1. **Register a new account:**
   - Run the app
   - Click "Sign Up"
   - Fill in the form
   - Check your email for verification

2. **Login:**
   - Use your registered email/password
   - Or use "Continue with Google"

3. **Reset Password:**
   - Click "Forgot Password?"
   - Enter email
   - Check inbox for reset link

## 🐛 Common Issues

**Issue:** "Invalid API Key"  
**Fix:** Double-check your Supabase credentials in `supabase_config.dart`

**Issue:** Google Sign-In not working  
**Fix:** Make sure you've configured Google OAuth properly and enabled it in Supabase

**Issue:** Database insert error  
**Fix:** Ensure your RLS policies allow INSERT for authenticated users

## 📚 Need More Help?

See the detailed [SETUP_GUIDE.md](SETUP_GUIDE.md) for:
- Complete configuration steps
- Deep linking setup
- Troubleshooting
- Code explanations

## 🎉 Next Steps

After authentication is working:
1. Create your home page
2. Add vehicle listing
3. Implement booking system
4. Add payment integration

Happy coding! 🚗💨
