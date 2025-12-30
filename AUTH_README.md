# 🔐 Car Rental System - Authentication Module

A complete, production-ready authentication system for Flutter with Supabase backend.

![Flutter](https://img.shields.io/badge/Flutter-3.10+-blue.svg)
![Supabase](https://img.shields.io/badge/Supabase-Latest-green.svg)
![Material Design 3](https://img.shields.io/badge/Material%20Design-3-purple.svg)

## ✨ Features

### 🎯 Core Functionality
- ✅ **Email/Password Authentication** - Secure login and registration
- ✅ **Google Sign-In** - One-tap authentication with Google
- ✅ **Password Reset** - Email-based password recovery
- ✅ **Email Verification** - Confirm user emails (optional)
- ✅ **Auto Profile Creation** - Automatic user profile in database
- ✅ **Session Management** - Persistent authentication state

### 🎨 UI/UX
- ✅ **Modern Material Design 3** - Beautiful, consistent UI
- ✅ **Custom Color Scheme** - Professional blue theme
- ✅ **Google Fonts (Inter)** - Clean, modern typography
- ✅ **Responsive Design** - Works on all screen sizes
- ✅ **Loading States** - Clear feedback during async operations
- ✅ **Error Handling** - User-friendly error messages
- ✅ **Form Validation** - Real-time input validation
- ✅ **Password Visibility Toggle** - Show/hide password

### 🔒 Security
- ✅ **Supabase Auth** - Industry-standard authentication
- ✅ **Row Level Security (RLS)** - Database-level security
- ✅ **Secure Password Storage** - Hashed passwords
- ✅ **Input Validation** - Prevents malicious input
- ✅ **CSRF Protection** - Built into Supabase
- ✅ **Rate Limiting** - Supabase handles this

## 📸 Screenshots

### Login Page
```
┌─────────────────────────────────┐
│         🚗                      │
│   Car Rental System             │
│   Welcome back! Please login    │
│                                 │
│   📧 Email                      │
│   ┌───────────────────────────┐ │
│   │ Enter your email          │ │
│   └───────────────────────────┘ │
│                                 │
│   🔒 Password                   │
│   ┌───────────────────────────┐ │
│   │ Enter your password    👁 │ │
│   └───────────────────────────┘ │
│                                 │
│              Forgot Password? > │
│                                 │
│   ┌───────────────────────────┐ │
│   │        Login              │ │
│   └───────────────────────────┘ │
│                                 │
│   ───────── OR ─────────        │
│                                 │
│   ┌───────────────────────────┐ │
│   │ 🌐 Continue with Google   │ │
│   └───────────────────────────┘ │
│                                 │
│   Don't have an account? Sign Up│
└─────────────────────────────────┘
```

### Register Page
```
┌─────────────────────────────────┐
│    ← Create Account             │
│                                 │
│         👤                      │
│      Join Us Today              │
│   Create an account to start    │
│                                 │
│   Full Name, Email, Phone,      │
│   IC Number, Gender,            │
│   Password, Confirm Password    │
│                                 │
│   ☑ I agree to Terms            │
│                                 │
│   ┌───────────────────────────┐ │
│   │    Create Account         │ │
│   └───────────────────────────┘ │
│                                 │
│   Already have an account? Login│
└─────────────────────────────────┘
```

## 🏗️ Architecture

### Authentication Flow

```
┌─────────────┐
│   User      │
└──────┬──────┘
       │
       ▼
┌─────────────────────────────┐
│   LoginPage / RegisterPage   │
└──────┬──────────────────────┘
       │
       ▼
┌─────────────────────────────┐
│   Supabase Auth API         │
└──────┬──────────────────────┘
       │
       ├──► Create user in Auth
       │
       ▼
┌─────────────────────────────┐
│   app_user Table            │
│   - user_id (U001, U002..)  │
│   - auth_uid (UUID)         │
│   - user_name               │
│   - user_email              │
│   - user_phone              │
│   - user_icno               │
│   - user_gender             │
│   - user_role (User/Admin)  │
│   - user_status (Active)    │
└──────┬──────────────────────┘
       │
       ▼
┌─────────────────────────────┐
│   HomePage (Authenticated)   │
└─────────────────────────────┘
```

### Database Schema Integration

The authentication system integrates seamlessly with your existing schema:

```sql
-- Supabase Auth creates this automatically
auth.users
├── id (UUID)
├── email
├── encrypted_password
└── ...

-- Your app_user table
public.app_user
├── user_id (varchar) - e.g., U001
├── auth_uid (uuid) - ← Links to auth.users.id
├── user_name
├── user_email
├── user_phone
├── user_icno
├── user_gender
├── user_role
└── user_status
```

### State Management

```dart
StreamBuilder<AuthState>
├── Listen to: supabase.auth.onAuthStateChange
├── If session exists → Navigate to HomePage
└── If no session → Show LoginPage
```

## 📋 API Reference

### Main Functions

#### `_signInWithEmail()`
Signs in user with email and password.

```dart
final response = await supabase.auth.signInWithPassword(
  email: email,
  password: password,
);
```

#### `_signUpWithEmail()`
Registers new user and creates profile.

```dart
// 1. Create auth user
final authResponse = await supabase.auth.signUp(
  email: email,
  password: password,
);

// 2. Create app_user profile
await supabase.from('app_user').insert({
  'user_id': 'U001',
  'auth_uid': authResponse.user!.id,
  // ... other fields
});
```

#### `_signInWithGoogle()`
Authenticates using Google OAuth.

```dart
final googleUser = await GoogleSignIn().signIn();
final googleAuth = await googleUser.authentication;

await supabase.auth.signInWithIdToken(
  provider: OAuthProvider.google,
  idToken: googleAuth.idToken!,
  accessToken: googleAuth.accessToken!,
);
```

#### `_sendResetEmail()`
Sends password reset email.

```dart
await supabase.auth.resetPasswordForEmail(
  email,
  redirectTo: 'your-app://reset-password/',
);
```

### Helper Functions

#### `current_user_id()` (SQL)
Returns the user_id for the current authenticated user.

```sql
select u.user_id
from public.app_user u
where u.auth_uid = auth.uid()
```

#### `is_admin()` (SQL)
Checks if current user is an admin.

```sql
select exists (
  select 1
  from public.admin a
  join public.app_user u on u.user_id = a.user_id
  where u.auth_uid = auth.uid()
)
```

## 🔧 Configuration

### Required Configuration

1. **Supabase Credentials** (`lib/config/supabase_config.dart`)
   ```dart
   static const String supabaseUrl = 'https://xxxxx.supabase.co';
   static const String supabaseAnonKey = 'eyJhbGciOiJI...';
   ```

2. **Google OAuth** (Optional)
   ```dart
   static const String googleWebClientId = '123456789-xxx.apps.googleusercontent.com';
   ```

3. **Deep Links** (For password reset)
   ```dart
   static const String resetPasswordRedirectUrl = 'io.supabase.carrentalsystem://reset-password/';
   ```

## 🧪 Testing Checklist

- [ ] Register new user with email
- [ ] Verify email confirmation sent
- [ ] Login with registered credentials
- [ ] Login with incorrect password (should fail)
- [ ] Forgot password flow
- [ ] Reset password via email link
- [ ] Google Sign-In (new user)
- [ ] Google Sign-In (existing user)
- [ ] Logout functionality
- [ ] Session persistence after app restart
- [ ] Form validation (all fields)
- [ ] Error messages display correctly
- [ ] Loading states work properly

## 📦 Dependencies

```yaml
dependencies:
  supabase_flutter: ^2.9.1    # Supabase client
  google_sign_in: ^6.2.2      # Google authentication
  google_fonts: ^6.2.1        # Typography
  flutter_svg: ^2.0.10        # SVG support
  email_validator: ^3.0.0     # Email validation
```

## 🚀 Deployment Checklist

Before deploying to production:

- [ ] Replace all placeholder credentials
- [ ] Test on physical devices (Android + iOS)
- [ ] Configure OAuth consent screen (Google)
- [ ] Set up custom email templates in Supabase
- [ ] Configure deep linking for all platforms
- [ ] Test RLS policies thoroughly
- [ ] Enable email verification (recommended)
- [ ] Set up error monitoring (e.g., Sentry)
- [ ] Configure rate limiting if needed
- [ ] Review and accept platform policies

## 🔐 Security Best Practices

1. **Never commit credentials** to version control
2. **Use environment variables** for sensitive data
3. **Enable RLS** on all database tables
4. **Validate all inputs** on client and server
5. **Use HTTPS only** in production
6. **Enable email verification** for new users
7. **Implement rate limiting** for auth endpoints
8. **Monitor auth logs** in Supabase dashboard
9. **Keep dependencies updated** regularly
10. **Use strong password requirements**

## 🐛 Troubleshooting

### "Invalid API Key"
- Verify credentials in `supabase_config.dart`
- Check Supabase dashboard is accessible
- Ensure no trailing spaces in credentials

### Google Sign-In Fails
- Verify OAuth Client ID is correct
- Check Google Cloud Console configuration
- Ensure Google provider is enabled in Supabase
- Add SHA-1 fingerprint (Android)

### Database Insert Error
- Check RLS policies allow INSERT
- Verify all required fields are provided
- Check user_id generation logic
- Review Supabase logs

### Email Not Received
- Check spam/junk folder
- Verify SMTP settings in Supabase
- Check email templates are configured
- Ensure email service is active

### Session Not Persisting
- Check `SharedPreferences` permissions
- Verify Supabase initialization
- Check for auth state listener

## 📚 Resources

- [Supabase Documentation](https://supabase.com/docs)
- [Flutter Documentation](https://docs.flutter.dev)
- [Google Sign-In Setup](https://pub.dev/packages/google_sign_in)
- [Material Design 3](https://m3.material.io)

## 🤝 Contributing

Feel free to customize this authentication system for your needs:
- Add biometric authentication
- Implement social login (Facebook, Apple)
- Add two-factor authentication (2FA)
- Customize UI theme and colors
- Add more user profile fields

## 📄 License

This authentication module is part of your Car Rental System project.

## 🙏 Credits

Built with:
- Flutter & Dart
- Supabase
- Material Design 3
- Google Fonts (Inter)

---

**Happy Coding! 🚗💨**

For quick setup, see [QUICKSTART.md](QUICKSTART.md)  
For detailed guide, see [SETUP_GUIDE.md](SETUP_GUIDE.md)
