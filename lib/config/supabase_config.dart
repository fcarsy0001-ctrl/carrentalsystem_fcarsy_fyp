// Supabase Configuration
// TODO: Replace these with your actual Supabase credentials
class SupabaseConfig {
  // Get these from: Supabase Dashboard > Settings > API
  static const String supabaseUrl = 'YOUR_SUPABASE_URL';
  static const String supabaseAnonKey = 'YOUR_SUPABASE_ANON_KEY';
  
  // Google Sign-In Configuration
  // Get this from: Google Cloud Console > Credentials
  static const String googleWebClientId = 'YOUR_GOOGLE_WEB_CLIENT_ID';
  
  // Deep Link Configuration for Password Reset
  static const String resetPasswordRedirectUrl = 'io.supabase.carrentalsystem://reset-password/';
}
