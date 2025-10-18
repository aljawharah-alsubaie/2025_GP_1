import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import './home_page.dart';

class LocationPermissionScreen extends StatefulWidget {
  final VoidCallback onPermissionGranted;

  const LocationPermissionScreen({
    super.key,
    required this.onPermissionGranted,
  });

  @override
  State<LocationPermissionScreen> createState() =>
      _LocationPermissionScreenState();
}

class _LocationPermissionScreenState extends State<LocationPermissionScreen>
    with SingleTickerProviderStateMixin {
  // 🎨 Purple color scheme matching HomePage
  static const Color deepPurple = Color.fromARGB(255, 92, 25, 99);
  static const Color vibrantPurple = Color(0xFF8E3A95);
  static const Color primaryPurple = Color(0xFF9C4A9E);
  static const Color palePurple = Color.fromARGB(255, 218, 185, 225);
  static const Color ultraLightPurple = Color(0xFFF3E5F5);

  late AnimationController _pulseController;
  late Animation<double> _shadowAnimation;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _shadowAnimation = Tween<double>(begin: 20.0, end: 50.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _hapticFeedback() {
    HapticFeedback.mediumImpact();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Background - gradient if image fails
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  ultraLightPurple,
                  palePurple.withOpacity(0.3),
                  Colors.white,
                ],
              ),
            ),
          ),

          // Background image with opacity (with error handling)
          Opacity(
            opacity: 0.3,
            child: Image.asset(
              'assets/images/map_background.jpg',
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              errorBuilder: (context, error, stackTrace) {
                return Container();
              },
            ),
          ),

          // Content on top
          SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 30.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 🎯 Location Icon with animated shadow
                    AnimatedBuilder(
                      animation: _shadowAnimation,
                      builder: (context, child) {
                        return Container(
                          padding: const EdgeInsets.all(30),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [vibrantPurple, primaryPurple],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: vibrantPurple.withOpacity(0.6),
                                blurRadius: _shadowAnimation.value,
                                spreadRadius: _shadowAnimation.value / 4,
                              ),
                              BoxShadow(
                                color: primaryPurple.withOpacity(0.4),
                                blurRadius: _shadowAnimation.value * 0.7,
                                spreadRadius: _shadowAnimation.value / 6,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.location_on,
                            size: 80,
                            color: Colors.white,
                          ),
                        );
                      },
                    ),

                    const SizedBox(height: 90),

                    // Title with shadow
                    Text(
                      'Track Yourself',
                      style: TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.w900,
                        color: deepPurple.withOpacity(0.9),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Description text
                    Text(
                      'Please allow location permission to enable emergency tracking',
                      style: TextStyle(
                        fontSize: 16,
                        color: deepPurple.withOpacity(0.7),
                        height: 1.6,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 80),

                    // ✅ Allow button
                    Semantics(
                      label: 'Allow location access button',
                      button: true,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [vibrantPurple, primaryPurple],
                          ),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: vibrantPurple.withOpacity(0.5),
                              blurRadius: 20,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: ElevatedButton(
                          onPressed: () {
                            _hapticFeedback();
                            widget.onPermissionGranted();
                          },
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              vertical: 20,
                              horizontal: 50,
                            ),
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                          child: const Text(
                            'Allow Location Access',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 25),

                    // Skip button - white transparent with purple border and shadow
                    Semantics(
                      label: 'Skip for now button',
                      button: true,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: vibrantPurple.withOpacity(0.3),
                              blurRadius: 15,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: OutlinedButton(
                          onPressed: () {
                            _hapticFeedback();
                            Navigator.of(context).pushAndRemoveUntil(
                              MaterialPageRoute(
                                builder: (context) => const HomePage(),
                              ),
                              (route) => false,
                            );
                          },
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              vertical: 20,
                              horizontal: 90,
                            ),
                            backgroundColor: Colors.white.withOpacity(0.4),
                            side: BorderSide(
                              color: vibrantPurple.withOpacity(0.6),
                              width: 2,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                          child: Text(
                            'Skip for Now',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: vibrantPurple,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
