import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:email_validator/email_validator.dart';
import '../main.dart';
import '../config/supabase_config.dart';
import '../utils/country_codes.dart';
import '../services/email_verification_service.dart';
import 'verification_page.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({Key? key}) : super(key: key);

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _phoneController = TextEditingController();
  final _icNoController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  String _selectedGender = 'Male';
  bool _agreeToTerms = false;
  CountryCode _selectedCountry = CountryCodes.getDefault();
  String _verificationMethod = 'otp'; // 'otp' or 'link'

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _phoneController.dispose();
    _icNoController.dispose();
    super.dispose();
  }

  Future<void> _signUpWithEmail() async {
    if (!_formKey.currentState!.validate()) return;

    if (!_agreeToTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please agree to the terms and conditions'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Step 1: Sign up with Supabase Auth
      // Note: Supabase may try to send its own confirmation email, but we'll use our custom OTP
      AuthResponse? authResponse;
      try {
        authResponse = await supabase.auth.signUp(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
      } catch (e) {
        // If Supabase email sending fails, check if user was still created
        if (e.toString().contains('Error sending confirmation email') || 
            e.toString().contains('unexpected_failure')) {
          print('⚠️ Supabase email failed, but checking if user was created...');
          // Try to get the user by email
          try {
            final email = _emailController.text.trim();
            final response = await supabase.auth.signInWithPassword(
              email: email,
              password: _passwordController.text,
            );
            if (response.user != null) {
              // User exists, create authResponse manually
              authResponse = AuthResponse(
                user: response.user,
                session: response.session,
              );
              print('✅ User already exists, continuing with custom OTP...');
            }
          } catch (_) {
            // User doesn't exist, rethrow original error
            rethrow;
          }
        } else {
          rethrow;
        }
      }

      if (authResponse?.user != null) {
        final email = _emailController.text.trim();
        final phoneNumber = _phoneController.text.trim().replaceAll(RegExp(r'[\s-]'), '');
        final fullPhoneNumber = '${_selectedCountry.dialCode}$phoneNumber';
        final authUid = authResponse!.user!.id;
        
        // Check if user already exists in app_user table
        final existingUser = await supabase
            .from('app_user')
            .select('user_id, user_email')
            .eq('auth_uid', authUid)
            .maybeSingle();
        
        if (existingUser != null) {
          // User already exists, navigate to verification page
          if (mounted) {
            setState(() => _isLoading = false);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Account already exists. Please verify your email or login.'),
                backgroundColor: Colors.orange,
                duration: Duration(seconds: 3),
              ),
            );
            Navigator.pop(context);
          }
          return;
        }
        
        // Step 2: Generate user_id (e.g., U001, U002, etc.) with improved retry logic
        String userId;
        int retries = 0;
        const maxRetries = 10; // Increased retries
        
        while (retries < maxRetries) {
          try {
            userId = await _generateUserId();

        // Step 3: Insert into app_user table
        await supabase.from('app_user').insert({
          'user_id': userId,
              'auth_uid': authUid,
          'user_name': _nameController.text.trim(),
              'user_email': email,
          'user_password': '***', // Store a placeholder, actual password is in auth
              'user_phone': fullPhoneNumber,
          'user_icno': _icNoController.text.trim(),
          'user_gender': _selectedGender,
          'user_role': 'User',
          'user_status': 'Active',
              'email_verified': false, // Will be set to true after verification
            });
            
            // Success, break out of retry loop
            print('✅ User created with ID: $userId');
            break;
          } catch (e) {
            // If duplicate key error, retry with new ID
            if (e.toString().contains('duplicate key') || e.toString().contains('23505')) {
              retries++;
              print('⚠️ Duplicate user_id detected, retrying... (attempt $retries/$maxRetries)');
              if (retries >= maxRetries) {
                // Use UUID-based fallback if all retries fail
                final uuid = authUid.substring(0, 8).toUpperCase();
                userId = 'U$uuid';
                print('⚠️ Using UUID-based fallback: $userId');
                try {
                  await supabase.from('app_user').insert({
                    'user_id': userId,
                    'auth_uid': authUid,
                    'user_name': _nameController.text.trim(),
                    'user_email': email,
                    'user_password': '***',
                    'user_phone': fullPhoneNumber,
                    'user_icno': _icNoController.text.trim(),
                    'user_gender': _selectedGender,
                    'user_role': 'User',
                    'user_status': 'Active',
                    'email_verified': false,
                  });
                  print('✅ User created with fallback ID: $userId');
                  break;
                } catch (fallbackError) {
                  throw Exception('Failed to create user after all attempts: $fallbackError');
                }
              }
              // Wait longer between retries
              await Future.delayed(Duration(milliseconds: 200 * retries));
              continue;
            } else {
              // Different error, rethrow
              rethrow;
            }
          }
        }

        // Step 4: Send verification (OTP or Link) - REQUIRED
        // Registration will fail if email cannot be sent
        String? token;

        if (_verificationMethod == 'otp') {
          // Generate and send OTP via email
          final otp = EmailVerificationService.generateOTP();
          await EmailVerificationService.sendOTPEmail(email, otp);
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('OTP sent to your email. Please check your inbox.'),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 3),
              ),
            );
          }
        } else {
          // Generate and send verification link via email
          token = await EmailVerificationService.storeVerificationLink(email);
          await EmailVerificationService.sendVerificationLinkEmail(email, token);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Verification link sent to your email. Please check your inbox.'),
              backgroundColor: Colors.green,
                duration: Duration(seconds: 3),
            ),
          );
          }
        }

        if (mounted) {
          setState(() => _isLoading = false);

          // Navigate to verification page
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => VerificationPage(
                email: email,
                verificationType: _verificationMethod,
                token: token, // Only pass token for link verification
              ),
            ),
          );
        }
      }
    } on AuthException catch (e) {
      // If Supabase email sending fails, but user might have been created, try to continue
      if (e.message.contains('Error sending confirmation email') || 
          e.message.contains('unexpected_failure')) {
        print('⚠️ Supabase email failed, but user might have been created. Checking...');
        
        // Try to sign in to check if user exists
        try {
          final email = _emailController.text.trim();
          final signInResponse = await supabase.auth.signInWithPassword(
            email: email,
            password: _passwordController.text,
          );
          
          if (signInResponse.user != null) {
            // User exists! Continue with custom OTP flow
            print('✅ User exists despite email error. Continuing with custom OTP...');
            
            // Continue with the registration flow using the existing user
            final authUid = signInResponse.user!.id;
            final phoneNumber = _phoneController.text.trim().replaceAll(RegExp(r'[\s-]'), '');
            final fullPhoneNumber = '${_selectedCountry.dialCode}$phoneNumber';
            
            // Check if user already exists in app_user table
            final existingUser = await supabase
                .from('app_user')
                .select('user_id, user_email')
                .eq('auth_uid', authUid)
                .maybeSingle();
            
            if (existingUser == null) {
              // User doesn't exist in app_user, create it
              String userId = await _generateUserId();
              await supabase.from('app_user').insert({
                'user_id': userId,
                'auth_uid': authUid,
                'user_name': _nameController.text.trim(),
                'user_email': email,
                'user_password': '***',
                'user_phone': fullPhoneNumber,
                'user_icno': _icNoController.text.trim(),
                'user_gender': _selectedGender,
                'user_role': 'User',
                'user_status': 'Active',
                'email_verified': false,
              });
            }
            
            // Send custom OTP
            String? token;
            if (_verificationMethod == 'otp') {
              final otp = EmailVerificationService.generateOTP();
              await EmailVerificationService.sendOTPEmail(email, otp);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('OTP sent to your email. Please check your inbox.'),
                    backgroundColor: Colors.green,
                    duration: Duration(seconds: 3),
                  ),
                );
              }
            } else {
              token = await EmailVerificationService.storeVerificationLink(email);
              await EmailVerificationService.sendVerificationLinkEmail(email, token);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Verification link sent to your email. Please check your inbox.'),
                    backgroundColor: Colors.green,
                    duration: Duration(seconds: 3),
                  ),
                );
              }
            }
            
            if (mounted) {
              setState(() => _isLoading = false);
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => VerificationPage(
                    email: email,
                    verificationType: _verificationMethod,
                    token: token,
                  ),
                ),
              );
            }
            return; // Success, exit early
          }
        } catch (signInError) {
          print('❌ User does not exist: $signInError');
          // User doesn't exist, show the original error
        }
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<String> _generateUserId() async {
    try {
      // Get the highest user_id from existing users
    final response = await supabase
        .from('app_user')
        .select('user_id')
        .order('user_id', ascending: false)
        .limit(1);

    if (response.isEmpty) {
      return 'U001';
    }

    // Extract the number from the last user_id (e.g., U001 -> 001)
    final lastUserId = response[0]['user_id'] as String;
      
      // Validate format
      if (!lastUserId.startsWith('U') || lastUserId.length < 4) {
        // If format is unexpected, start from U001
        return 'U001';
      }
      
      final lastNumber = int.tryParse(lastUserId.substring(1));
      if (lastNumber == null) {
        return 'U001';
      }
      
    final nextNumber = lastNumber + 1;
      
      // Ensure we don't exceed reasonable limits (U999)
      if (nextNumber > 999) {
        // If we exceed U999, use timestamp-based ID as fallback
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        return 'U${timestamp.toString().substring(timestamp.toString().length - 6)}';
      }

    return 'U${nextNumber.toString().padLeft(3, '0')}';
    } catch (e) {
      // Fallback: use timestamp-based ID if query fails
      print('Error generating user ID: $e');
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      return 'U${timestamp.toString().substring(timestamp.toString().length - 6)}';
    }
  }

  Future<void> _signUpWithGoogle() async {
    setState(() => _isLoading = true);

    try {
      // ✅ Use Supabase OAuth flow (browser) instead of google_sign_in plugin.
      // Session will be completed when the app receives:
      // carrentalsystem://login-callback#access_token=...
      // and main.dart calls getSessionFromUrl(...)
      await supabase.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: SupabaseConfig.googleOAuthRedirectUrl,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Google sign-up failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Create Account'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Icon
                Icon(
                  Icons.person_add_rounded,
                  size: 60,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  'Join Us Today',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Create an account to start renting cars',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 32),

                // Full Name
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Full Name',
                    hintText: 'Enter your full name',
                    prefixIcon: Icon(Icons.person_outlined),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your name';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Email
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    hintText: 'Enter your email',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your email';
                    }
                    if (!value.contains('@')) {
                      return 'Please enter a valid email';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Phone Number with Country Code Dropdown
                Row(
                  children: [
                    // Country Code Dropdown
                    Container(
                      width: 130,
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey[300]!),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<CountryCode>(
                          value: _selectedCountry,
                          isExpanded: true,
                          icon: const Icon(Icons.arrow_drop_down, size: 24),
                          items: CountryCodes.countries.map((country) {
                            return DropdownMenuItem<CountryCode>(
                              value: country,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      country.flag,
                                      style: const TextStyle(fontSize: 18),
                                    ),
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: Text(
                                        country.dialCode,
                                        style: const TextStyle(fontSize: 14),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                          onChanged: (CountryCode? newValue) {
                            if (newValue != null) {
                              setState(() {
                                _selectedCountry = newValue;
                              });
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Phone Number Input
                    Expanded(
                      child: TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Phone Number',
                          hintText: 'Enter phone number',
                    prefixIcon: Icon(Icons.phone_outlined),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your phone number';
                    }
                          // Remove spaces and dashes for validation
                          final cleanedValue = value.replaceAll(RegExp(r'[\s-]'), '');
                          if (!RegExp(r'^\d+$').hasMatch(cleanedValue)) {
                            return 'Phone number must contain only digits';
                          }
                          if (cleanedValue.length < 7) {
                            return 'Phone number is too short';
                          }
                          if (cleanedValue.length > 15) {
                            return 'Phone number is too long';
                    }
                    return null;
                  },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // IC Number
                TextFormField(
                  controller: _icNoController,
                  keyboardType: TextInputType.number,
                  maxLength: 12,
                  decoration: const InputDecoration(
                    labelText: 'IC Number',
                    hintText: 'Enter your IC number (12 digits)',
                    prefixIcon: Icon(Icons.badge_outlined),
                    counterText: '',
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your IC number';
                    }
                    if (value.length != 12) {
                      return 'IC number must be 12 digits';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Gender Selection
                DropdownButtonFormField<String>(
                  value: _selectedGender,
                  decoration: const InputDecoration(
                    labelText: 'Gender',
                    prefixIcon: Icon(Icons.wc_outlined),
                  ),
                  items: ['Male', 'Female', 'Other']
                      .map((gender) => DropdownMenuItem(
                    value: gender,
                    child: Text(gender),
                  ))
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _selectedGender = value;
                      });
                    }
                  },
                ),
                const SizedBox(height: 16),

                // Password
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    hintText: 'Create a password',
                    prefixIcon: const Icon(Icons.lock_outlined),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscurePassword = !_obscurePassword;
                        });
                      },
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter a password';
                    }
                    if (value.length < 6) {
                      return 'Password must be at least 6 characters';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Confirm Password
                TextFormField(
                  controller: _confirmPasswordController,
                  obscureText: _obscureConfirmPassword,
                  decoration: InputDecoration(
                    labelText: 'Confirm Password',
                    hintText: 'Re-enter your password',
                    prefixIcon: const Icon(Icons.lock_outlined),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureConfirmPassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscureConfirmPassword = !_obscureConfirmPassword;
                        });
                      },
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please confirm your password';
                    }
                    if (value != _passwordController.text) {
                      return 'Passwords do not match';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Verification Method Selection
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue[200]!),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Email Verification Method',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue[900],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: RadioListTile<String>(
                              title: const Text('OTP Code'),
                              subtitle: const Text('6-digit code'),
                              value: 'otp',
                              groupValue: _verificationMethod,
                              onChanged: (value) {
                                if (value != null) {
                                  setState(() {
                                    _verificationMethod = value;
                                  });
                                }
                              },
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                          Expanded(
                            child: RadioListTile<String>(
                              title: const Text('Verification Link'),
                              subtitle: const Text('Click link'),
                              value: 'link',
                              groupValue: _verificationMethod,
                              onChanged: (value) {
                                if (value != null) {
                                  setState(() {
                                    _verificationMethod = value;
                                  });
                                }
                              },
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Terms and Conditions
                Row(
                  children: [
                    Checkbox(
                      value: _agreeToTerms,
                      onChanged: _isLoading
                          ? null
                          : (value) {
                        setState(() {
                          _agreeToTerms = value ?? false;
                        });
                      },
                    ),
                    Expanded(
                      child: Text(
                        'I agree to the Terms and Conditions',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[700],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Sign Up Button
                ElevatedButton(
                  onPressed: _isLoading ? null : _signUpWithEmail,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white,
                  ),
                  child: _isLoading
                      ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                      : const Text('Create Account'),
                ),
                const SizedBox(height: 24),

                // Divider
                Row(
                  children: [
                    Expanded(child: Divider(color: Colors.grey[300])),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'OR',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ),
                    Expanded(child: Divider(color: Colors.grey[300])),
                  ],
                ),
                const SizedBox(height: 24),

                // Google Sign Up Button
                OutlinedButton.icon(
                  onPressed: _isLoading ? null : _signUpWithGoogle,
                  icon: Image.network(
                    'https://www.google.com/favicon.ico',
                    height: 20,
                    width: 20,
                    errorBuilder: (context, error, stackTrace) {
                      return const Icon(Icons.g_mobiledata, size: 20);
                    },
                  ),
                  label: const Text('Sign up with Google'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    side: BorderSide(color: Colors.grey[300]!),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Login Link
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Already have an account? ',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                    TextButton(
                      onPressed: _isLoading
                          ? null
                          : () {
                        Navigator.pop(context);
                      },
                      child: Text(
                        'Login',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
