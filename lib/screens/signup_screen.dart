import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:async';
import 'home_page.dart';
import '../services/google_signin_handler.dart';
import 'package:cloud_functions/cloud_functions.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final nameController = TextEditingController();
  final emailController = TextEditingController();
  final phoneController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _agreeToTerms = false;
  bool _showVerificationScreen = false;
  bool _emailVerified = false;

  Timer? _checkTimer;
  Timer? _resendCooldownTimer;
  int _checkCount = 0;
  int _resendCooldown = 0;
  bool _canResend = true;

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _animationController.forward();
  }

  void _setupAnimations() {
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );

    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _animationController,
            curve: Curves.easeOutBack,
          ),
        );
  }

  @override
  void dispose() {
    _checkTimer?.cancel();
    _resendCooldownTimer?.cancel();
    _animationController.dispose();
    nameController.dispose();
    emailController.dispose();
    phoneController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }

  String _getPasswordStrength(String password) {
    if (password.length < 6) return 'Weak';
    if (password.length < 8) return 'Medium';
    if (RegExp(
      r'^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[@$!%*?&])[A-Za-z\d@$!%*?&]',
    ).hasMatch(password)) {
      return 'Strong';
    }
    return 'Medium';
  }

  Color _getPasswordStrengthColor(String password) {
    final strength = _getPasswordStrength(password);
    switch (strength) {
      case 'Weak':
        return Colors.red;
      case 'Medium':
        return Colors.orange;
      case 'Strong':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  void _registerUser() async {
    if (!_agreeToTerms) {
      _showAccessibleFeedback(
        "Please agree to the Terms and Conditions",
        Colors.red,
      );
      return;
    }

    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);

      try {
        UserCredential userCredential = await FirebaseAuth.instance
            .createUserWithEmailAndPassword(
              email: emailController.text.trim(),
              password: passwordController.text.trim(),
            );

        User? user = userCredential.user;

        if (user == null) {
          throw Exception("Failed to create user");
        }

        final String fullName = nameController.text.trim();

        bool emailSent = false;

        try {
          final callable = FirebaseFunctions.instance.httpsCallable(
            'sendWelcomeEmail',
          );
          await callable.call({
            'email': emailController.text.trim(),
            'displayName': fullName,
          });
          emailSent = true;
          print('✅ Custom email sent via Cloud Function');
        } catch (cloudFunctionError) {
          print('⚠️ Cloud Function error: $cloudFunctionError');

          try {
            await user.sendEmailVerification();
            emailSent = true;
            print('📧 Sent default Firebase email as fallback');
          } catch (verificationError) {
            print('❌ Failed to send verification email: $verificationError');
            emailSent = false;
          }
        }

        if (!emailSent) {
          await user.delete();
          throw FirebaseAuthException(
            code: 'email-send-failed',
            message:
                'Failed to send verification email. Please try again later or use a different network.',
          );
        }

        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'full_name': fullName,
          'email': emailController.text.trim(),
          'phone': phoneController.text.trim(),
          'created_at': Timestamp.now(),
          'profile_completed': false,
          'email_verified': false,
        });

        setState(() {
          _showVerificationScreen = true;
          _isLoading = false;
        });

        _startCheckingVerification();

        _showAccessibleFeedback(
          "Account created! Check your email 💜",
          Colors.green,
        );

        SemanticsService.announce(
          "Account created successfully. Check your email inbox and spam folder for verification.",
          TextDirection.ltr,
        );
      } on FirebaseAuthException catch (e) {
        String error = "An error occurred";

        if (e.code == 'too-many-requests' ||
            e.message?.contains('blocked') == true) {
          error =
              "Too many attempts from this device. Please wait 15-30 minutes and try again, or use a different network.";
        } else if (e.code == 'email-send-failed') {
          error =
              e.message ??
              "Failed to send verification email. Please try again later.";
        } else {
          switch (e.code) {
            case 'email-already-in-use':
              error = "This email is already registered. Please login instead.";
              break;
            case 'invalid-email':
              error = "Invalid email address";
              break;
            case 'weak-password':
              error = "Password too weak (min 6 characters)";
              break;
            case 'operation-not-allowed':
              error =
                  "Registration is temporarily disabled. Please try again later.";
              break;
            default:
              error = e.message ?? "Registration failed";
          }
        }

        _showAccessibleFeedback(error, Colors.red);
      } catch (e) {
        _showAccessibleFeedback(
          "Unexpected error occurred. Please try again.",
          Colors.red,
        );
        print('❌ Registration error: $e');
      } finally {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    }
  }

  void _startCheckingVerification() {
    _checkTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      await _checkEmailVerification();
      _checkCount++;

      if (_checkCount >= 100) {
        timer.cancel();
        if (mounted) {
          _showAccessibleFeedback(
            "Verification timeout. Please resend the email.",
            Colors.orange,
          );
        }
      }
    });
  }

  Future<void> _checkEmailVerification() async {
    try {
      final user = FirebaseAuth.instance.currentUser;

      if (user != null) {
        await user.reload();
        final updatedUser = FirebaseAuth.instance.currentUser;

        if (updatedUser?.emailVerified == true && !_emailVerified) {
          setState(() => _emailVerified = true);
          _checkTimer?.cancel();

          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .update({'email_verified': true, 'verified_at': Timestamp.now()});

          const storage = FlutterSecureStorage();
          await storage.write(key: 'isLoggedIn', value: 'true');
          await storage.write(
            key: 'userEmail',
            value: emailController.text.trim(),
          );

          _showAccessibleFeedback(
            "Email verified successfully! Welcome ${nameController.text}",
            Colors.green,
          );

          HapticFeedback.heavyImpact();

          await Future.delayed(const Duration(seconds: 2));

          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const HomePage()),
            );
          }
        }
      }
    } catch (e) {
      print('Error checking verification: $e');
    }
  }

  void _startResendCooldown() {
    setState(() {
      _canResend = false;
      _resendCooldown = 60;
    });

    _resendCooldownTimer?.cancel();
    _resendCooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_resendCooldown > 0) {
        setState(() => _resendCooldown--);
      } else {
        setState(() => _canResend = true);
        timer.cancel();
      }
    });
  }

  Future<void> _resendVerificationEmail() async {
    if (!_canResend) return;

    try {
      setState(() => _isLoading = true);

      final user = FirebaseAuth.instance.currentUser;

      await user?.sendEmailVerification();

      _startResendCooldown();

      _showAccessibleFeedback(
        "Verification email resent successfully!",
        Colors.green,
      );

      SemanticsService.announce(
        "New verification email sent. Check your inbox and spam folder.",
        TextDirection.ltr,
      );

      HapticFeedback.mediumImpact();
    } catch (e) {
      String errorMessage = "Failed to resend email";
      if (e is FirebaseAuthException && e.code == 'too-many-requests') {
        errorMessage = "Too many requests. Please wait and try again.";
      }
      _showAccessibleFeedback(errorMessage, Colors.red);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _signUpWithGoogle() async {
    if (!_agreeToTerms) {
      _showAccessibleFeedback(
        "Please agree to the Terms and Conditions",
        Colors.red,
      );
      return;
    }

    try {
      setState(() => _isLoading = true);
      await GoogleSignInHandler.signInWithGoogle(context);
    } catch (e) {
      _showAccessibleFeedback(
        "Google sign-up failed. Please try again.",
        Colors.red,
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showAccessibleFeedback(String message, Color color) {
    if (color == Colors.green) {
      HapticFeedback.lightImpact();
    } else if (color == Colors.red) {
      HapticFeedback.mediumImpact();
    } else {
      HapticFeedback.selectionClick();
    }

    SemanticsService.announce(message, TextDirection.ltr);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Semantics(
          liveRegion: true,
          label: message,
          child: Row(
            children: [
              Icon(
                color == Colors.green
                    ? Icons.check_circle
                    : color == Colors.orange
                    ? Icons.warning
                    : Icons.error,
                color: Colors.white,
                size: 28,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(message, style: const TextStyle(fontSize: 18)),
              ),
            ],
          ),
        ),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: const EdgeInsets.all(20),
        duration: const Duration(seconds: 5),
        padding: const EdgeInsets.all(20),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            decoration: const BoxDecoration(
              image: DecorationImage(
                image: AssetImage('assets/images/backk.jpg'),
                fit: BoxFit.cover,
              ),
            ),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.3),
                    Colors.black.withOpacity(0.1),
                    Colors.black.withOpacity(0.3),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: SlideTransition(
                position: _slideAnimation,
                child: _showVerificationScreen
                    ? _buildVerificationWaitingScreen()
                    : _buildSignupForm(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSignupForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            const SizedBox(height: 20),
            Semantics(
              header: true,
              label: 'Create Account page',
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.2),
                    width: 1,
                  ),
                ),
                child: Column(
                  children: [
                    ExcludeSemantics(
                      child: Icon(
                        Icons.person_add_rounded,
                        size: 60,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      "Create Account",
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 5),
                    Text(
                      "Join us and start your journey",
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.white.withOpacity(0.8),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 30),
            Semantics(
              label: 'Full name input field',
              textField: true,
              child: _buildEnhancedTextFormField(
                controller: nameController,
                hint: "Full Name",
                icon: Icons.person_outline,
                validator: (value) {
                  if (value == null || value.trim().isEmpty)
                    return "Full name is required";
                  if (value.trim().length < 2)
                    return "Name must be at least 2 characters";
                  return null;
                },
              ),
            ),
            const SizedBox(height: 20),
            Semantics(
              label: 'Email address input field',
              textField: true,
              hint: 'We will send a verification link to this email',
              child: _buildEnhancedTextFormField(
                controller: emailController,
                hint: "Email Address",
                icon: Icons.email_outlined,
                keyboardType: TextInputType.emailAddress,
                validator: (value) {
                  if (value == null || value.trim().isEmpty)
                    return "Email is required";
                  if (!RegExp(
                    r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$',
                  ).hasMatch(value.trim()))
                    return "Please enter a valid email address";
                  return null;
                },
              ),
            ),
            const SizedBox(height: 20),
            Semantics(
              label: 'Mobile number input field',
              textField: true,
              child: _buildEnhancedTextFormField(
                controller: phoneController,
                hint: "Mobile Number",
                icon: Icons.phone_outlined,
                keyboardType: TextInputType.phone,
                validator: (value) {
                  if (value == null || value.trim().isEmpty)
                    return "Mobile number is required";
                  if (!RegExp(r'^[0-9+\-\s()]{8,15}$').hasMatch(value.trim()))
                    return "Please enter a valid mobile number";
                  return null;
                },
              ),
            ),
            const SizedBox(height: 20),
            Semantics(
              label: 'Password input field',
              textField: true,
              obscured: true,
              child: _buildPasswordField(
                controller: passwordController,
                hint: "Password",
                obscure: _obscurePassword,
                onToggle: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
                validator: (value) {
                  if (value == null || value.trim().isEmpty)
                    return "Password is required";
                  if (value.trim().length < 6)
                    return "Password must be at least 6 characters";
                  return null;
                },
              ),
            ),
            if (passwordController.text.isNotEmpty) ...[
              const SizedBox(height: 12),
              Semantics(
                label:
                    'Password strength: ${_getPasswordStrength(passwordController.text)}',
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      ExcludeSemantics(
                        child: Icon(
                          Icons.security,
                          size: 20,
                          color: _getPasswordStrengthColor(
                            passwordController.text,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        "Password Strength: ${_getPasswordStrength(passwordController.text)}",
                        style: TextStyle(
                          color: _getPasswordStrengthColor(
                            passwordController.text,
                          ),
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 20),
            Semantics(
              label: 'Confirm password input field',
              textField: true,
              obscured: true,
              child: _buildPasswordField(
                controller: confirmPasswordController,
                hint: "Confirm Password",
                obscure: _obscureConfirmPassword,
                onToggle: () => setState(
                  () => _obscureConfirmPassword = !_obscureConfirmPassword,
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty)
                    return "Please confirm your password";
                  if (value != passwordController.text)
                    return "Passwords do not match";
                  return null;
                },
              ),
            ),
            const SizedBox(height: 24),
            Semantics(
              label: 'Terms and conditions checkbox',
              checked: _agreeToTerms,
              hint: 'Double tap to toggle agreement',
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withOpacity(0.2)),
                ),
                child: Row(
                  children: [
                    Checkbox(
                      value: _agreeToTerms,
                      onChanged: (value) {
                        HapticFeedback.selectionClick();
                        setState(() => _agreeToTerms = value ?? false);
                      },
                      activeColor: const Color(0xFF6B1D73),
                      checkColor: Colors.white,
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() => _agreeToTerms = !_agreeToTerms);
                        },
                        child: const Text(
                          "I agree to the Terms and Conditions",
                          style: TextStyle(color: Colors.white, fontSize: 16),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),

// Create Account Button - Match Login button size (56 height)
Semantics(
  label: 'Create account button',
  hint: 'Double tap to create your account',
  button: true,
  child: SizedBox(
    width: double.infinity,
    height: 56,  // ✅ Changed from 64 to 56
    child: ElevatedButton(
      onPressed: _isLoading
          ? null
          : () {
              HapticFeedback.mediumImpact();
              _registerUser();
            },
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF6B1D73),
        foregroundColor: Colors.white,
        elevation: 12,
        shadowColor: const Color(0xFF6B1D73).withOpacity(0.4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      child: _isLoading
          ? const SizedBox(
              height: 24,  // ✅ Changed from 28 to 24
              width: 24,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2,  // ✅ Changed from 3 to 2
              ),
            )
          : const Text(
              "Create Account",
              style: TextStyle(
                fontSize: 18,  // ✅ Changed from 20 to 18
                fontWeight: FontWeight.bold,
              ),
            ),
    ),
  ),
),

const SizedBox(height: 32),

Row(
  children: [
    Expanded(
      child: Container(
        height: 1,
        color: Colors.white.withOpacity(0.3),
      ),
    ),
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Text(
        "OR",
        style: TextStyle(
          color: Colors.white.withOpacity(0.7),
          fontWeight: FontWeight.w500,
          fontSize: 16,
        ),
      ),
    ),
    Expanded(
      child: Container(
        height: 1,
        color: Colors.white.withOpacity(0.3),
      ),
    ),
  ],
),

const SizedBox(height: 32),

// Google Sign Up Button - Match Login Google button style
Semantics(
  label: 'Sign up with Google button',
  button: true,
  hint: 'Double tap to sign up using your Google account',
  child: SizedBox(
    width: double.infinity,
    height: 56,  // ✅ Changed from 64 to 56
    child: Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withOpacity(0.3),
          width: 1.5,
        ),
      ),
      child: ElevatedButton(
        onPressed: _isLoading
            ? null
            : () {
                HapticFeedback.selectionClick();
                _signUpWithGoogle();
              },
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          shadowColor: Colors.transparent,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ExcludeSemantics(
              child: Icon(Icons.g_mobiledata, size: 28),  // ✅ Changed from 32 to 28
            ),
            const SizedBox(width: 12),
            const Text(
              "Continue with Google",
              style: TextStyle(
                fontSize: 16,  // ✅ Changed from 18 to 16
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    ),
  ),
),
            const SizedBox(height: 30),
            // Already have account - Button style like the image
            Semantics(
              label: 'Already have an account, Log in button',
              button: true,
              hint: 'Double tap to go to login page',
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  Navigator.pop(context);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        "Already have an account? ",
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.9),
                          fontSize: 16,
                        ),
                      ),
                      const Text(
                        "Log In",
                        style: TextStyle(
                          color: Color.fromARGB(255, 248, 183, 255),
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildVerificationWaitingScreen() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        children: [
          const SizedBox(height: 60),
          Semantics(
            header: true,
            label: 'Email Verification page',
            child: Container(
              padding: const EdgeInsets.all(30),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Colors.white.withOpacity(0.2),
                  width: 1,
                ),
              ),
              child: Column(
                children: [
                  if (_emailVerified)
                    ExcludeSemantics(
                      child: Icon(
                        Icons.check_circle,
                        size: 80,
                        color: Colors.green,
                      ),
                    )
                  else
                    ExcludeSemantics(
                      child: Icon(
                        Icons.mark_email_unread_outlined,
                        size: 80,
                        color: Colors.white,
                      ),
                    ),
                  const SizedBox(height: 20),
                  Text(
                    _emailVerified ? "Email Verified!" : "Check Your Email",
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  if (_emailVerified)
                    Text(
                      "Redirecting to home...",
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.white.withOpacity(0.9),
                      ),
                      textAlign: TextAlign.center,
                    )
                  else
                    Column(
                      children: [
                        Text(
                          "We sent a email to",
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.white.withOpacity(0.9),
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          emailController.text,
                          style: const TextStyle(
                            fontSize: 16,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.orange.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.orange.withOpacity(0.5),
                              width: 2,
                            ),
                          ),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  ExcludeSemantics(
                                    child: Icon(
                                      Icons.warning_amber_rounded,
                                      color: Colors.orange,
                                      size: 24,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const Text(
                                    "IMPORTANT!",
                                    style: TextStyle(
                                      fontSize: 18,
                                      color: Colors.orange,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                "📧 Check your SPAM/JUNK folder!\n\ncheck spam folder and mark as 'Not Spam'.",
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.white.withOpacity(0.95),
                                  height: 1.5,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          if (!_emailVerified) ...[
            const SizedBox(height: 40),
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.2),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.blue.withOpacity(0.3)),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      ExcludeSemantics(
                        child: Icon(
                          Icons.info_outline,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        "Next Steps",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    "1. Open your email app\n2. Check INBOX and SPAM folder\n3. Find our verification email\n4. Click the verification link\n5. Come back here automatically\n\n✅ We're checking automatically!",
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 15,
                      height: 1.6,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            Semantics(
              label: _canResend
                  ? 'Resend verification email button'
                  : 'Resend available in $_resendCooldown seconds',
              button: true,
              hint: _canResend
                  ? 'Double tap to send verification email again'
                  : '',
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton.icon(
                  onPressed: (_isLoading || !_canResend)
                      ? null
                      : _resendVerificationEmail,
                  icon: Icon(
                    _canResend ? Icons.refresh : Icons.timer_outlined,
                    size: 24,
                  ),
                  label: Text(
                    _canResend
                        ? "Resend Verification Email"
                        : "Resend in $_resendCooldown seconds",
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _canResend
                        ? Colors.white.withOpacity(0.2)
                        : Colors.grey.withOpacity(0.2),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Semantics(
              label: 'Back to login button',
              button: true,
              hint: 'Double tap to go back to login page',
              child: TextButton(
                onPressed: () {
                  _checkTimer?.cancel();
                  _resendCooldownTimer?.cancel();
                  Navigator.pop(context);
                },
                child: const Text(
                  "Back to Login",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEnhancedTextFormField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool obscure = false,
    String? Function(String?)? validator,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TextFormField(
        controller: controller,
        obscureText: obscure,
        keyboardType: keyboardType,
        validator: validator,
        onChanged: (value) => setState(() {}),
        style: const TextStyle(color: Colors.black, fontSize: 18),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: Colors.grey.shade600, fontSize: 18),
          prefixIcon: ExcludeSemantics(
            child: Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF6B1D73).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: const Color(0xFF6B1D73), size: 24),
            ),
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          fillColor: Colors.white.withOpacity(0.95),
          filled: true,
          contentPadding: const EdgeInsets.all(24),
        ),
      ),
    );
  }

  Widget _buildPasswordField({
    required TextEditingController controller,
    required String hint,
    required bool obscure,
    required VoidCallback onToggle,
    String? Function(String?)? validator,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TextFormField(
        controller: controller,
        obscureText: obscure,
        validator: validator,
        onChanged: (value) => setState(() {}),
        style: const TextStyle(color: Colors.black, fontSize: 18),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: Colors.grey.shade600, fontSize: 18),
          prefixIcon: ExcludeSemantics(
            child: Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF6B1D73).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.lock_outline,
                color: Color(0xFF6B1D73),
                size: 24,
              ),
            ),
          ),
          suffixIcon: Semantics(
            label: obscure ? 'Show password' : 'Hide password',
            button: true,
            hint: 'Double tap to toggle password visibility',
            child: IconButton(
              onPressed: () {
                HapticFeedback.selectionClick();
                onToggle();
              },
              icon: Icon(
                obscure ? Icons.visibility_off : Icons.visibility,
                color: const Color(0xFF6B1D73),
                size: 24,
              ),
            ),
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          fillColor: Colors.white.withOpacity(0.95),
          filled: true,
          contentPadding: const EdgeInsets.all(24),
        ),
      ),
    );
  }
}
