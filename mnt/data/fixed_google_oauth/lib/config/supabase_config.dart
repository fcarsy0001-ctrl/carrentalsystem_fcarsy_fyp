// Supabase Configuration
class SupabaseConfig {
  // Supabase Dashboard > Settings > API
  static const String supabaseUrl = 'https://phihkypnzwoilzdsyxvh.supabase.co';
  static const String supabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBoaWhreXBuendvaWx6ZHN5eHZoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjY5NzUxNDYsImV4cCI6MjA4MjU1MTE0Nn0.xh1gs_rIYEQ_i22N1G-tiDTPticnzaAl69VBpvkLcCY';

  // Google Login (Supabase OAuth)
  // Add this to Supabase Dashboard > Auth > URL Configuration > Additional Redirect URLs
  static const String googleOAuthRedirectUrl = 'carrentalsystem://login-callback';

  // Deep Link Configuration for Password Reset
  // Add this to Supabase Dashboard > Auth > URL Configuration > Redirect URLs
  static const String resetPasswordRedirectUrl = 'carrentalsystem://reset-password';
}
