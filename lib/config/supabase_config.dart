// Supabase Configuration
class SupabaseConfig {
  // Supabase Dashboard > Settings > API
  static const String supabaseUrl = 'https://phihkypnzwoilzdsyxvh.supabase.co';
  static const String supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBoaWhreXBuendvaWx6ZHN5eHZoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjY5NzUxNDYsImV4cCI6MjA4MjU1MTE0Nn0.xh1gs_rIYEQ_i22N1G-tiDTPticnzaAl69VBpvkLcCY';

  // OAuth deep link callback for Google sign-in (add to Supabase Auth redirect URLs)
  static const String googleRedirectUrl = 'carrentalsystem://login-callback';

  // Deep link callback for password reset (add to Supabase Auth redirect URLs)
  static const String resetPasswordRedirectUrl = 'carrentalsystem://reset-password';

  // Optional: custom verify link deep link (if you use it)
  static const String verifyRedirectUrl = 'carrentalsystem://verify';
}
