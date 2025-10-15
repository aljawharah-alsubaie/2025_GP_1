import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import './face_management.dart';
import './camera.dart';
import './home_page.dart';
import './reminders.dart';
import './sos_screen.dart';
import './settings.dart';

class FaceListPage extends StatefulWidget {
  const FaceListPage({super.key});

  @override
  State<FaceListPage> createState() => _FaceListPageState();
}

class _FaceListPageState extends State<FaceListPage> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.dark,
        child: Container(
          color: Colors.white,
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  // ENHANCED: Much larger header with better spacing and touch targets
                  Container(
                    padding: const EdgeInsets.only(
                      top: 60, // IMPROVED: Even more padding from top
                      left: 20, // IMPROVED: More horizontal padding
                      right: 20,
                      bottom: 40, // IMPROVED: More bottom padding
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5E6F7),
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(65),
                        bottomRight: Radius.circular(65),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          offset: const Offset(0, 3),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // ENHANCED: Much taller navigation row
                        SizedBox(
                          height: 64, // IMPROVED: Increased from 48 to 64
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Center(
                                child: Semantics(
                                  label: 'Face Recognition page',
                                  header: true,
                                  child: const Text(
                                    'Face Recognition',
                                    style: TextStyle(
                                      color: Color(0xFF6B1D73),
                                      fontSize: 28, // IMPROVED: Larger (was 24)
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                              ),
                              // ENHANCED: MUCH larger back button with better positioning
                              Positioned(
                                left: 0,
                                top: 8, // IMPROVED: Better vertical centering
                                child: Semantics(
                                  label: 'Go back to previous page',
                                  button: true,
                                  hint: 'Double tap to navigate back',
                                  child: Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: () {
                                        HapticFeedback.mediumImpact(); // IMPROVED: Stronger haptic
                                        Navigator.pop(context);
                                      },
                                      borderRadius: BorderRadius.circular(28),
                                      // ENHANCED: Visual ripple effect
                                      splashColor: const Color(
                                        0xFF6B1D73,
                                      ).withOpacity(0.2),
                                      highlightColor: const Color(
                                        0xFF6B1D73,
                                      ).withOpacity(0.1),
                                      child: Container(
                                        // IMPROVED: Much larger touch target (56x56)
                                        width: 56,
                                        height: 56,
                                        alignment: Alignment.center,
                                        // ENHANCED: Add visible background
                                        decoration: BoxDecoration(
                                          color: Colors.white.withOpacity(0.3),
                                          borderRadius: BorderRadius.circular(
                                            28,
                                          ),
                                          border: Border.all(
                                            color: const Color(
                                              0xFF6B1D73,
                                            ).withOpacity(0.3),
                                            width: 2,
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.arrow_back_ios_new,
                                          color: Color(0xFF6B1D73),
                                          size:
                                              28, // IMPROVED: Much larger icon
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16), // IMPROVED: More spacing
                        Semantics(
                          label:
                              'Choose an option to get started with face recognition',
                          child: const Text(
                            'Choose an option to get started',
                            style: TextStyle(
                              color: Color(0xFF6B1D73),
                              fontSize: 18, // IMPROVED: Larger (was 16)
                              fontWeight: FontWeight.w500,
                              height: 1.4,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Main content
                  const SizedBox(height: 30),
                  Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Add Person Option
                        AccessibleButton(
                          semanticLabel:
                              'Add Person. Register a new person for face recognition',
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    const FaceManagementPage(),
                              ),
                            );
                          },
                          child: Container(
                            constraints: const BoxConstraints(minHeight: 72),
                            margin: const EdgeInsets.only(bottom: 20),
                            decoration: BoxDecoration(
                              color: const Color(0xFF6B1D73),
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(
                                    0xFF6B1D73,
                                  ).withOpacity(0.3),
                                  blurRadius: 8,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.25),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Icon(
                                      Icons.person_add,
                                      color: Colors.white,
                                      size: 32,
                                    ),
                                  ),
                                  const SizedBox(width: 20),
                                  const Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Add Person',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 20,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                        SizedBox(height: 6),
                                        Text(
                                          'Register a new person for recognition',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 15,
                                            height: 1.3,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  const Icon(
                                    Icons.arrow_forward_ios,
                                    color: Colors.white,
                                    size: 22,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                        // Identify Person Option
                        AccessibleButton(
                          semanticLabel:
                              'Identify Person. Use camera to recognize and identify people',
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    const CameraScreen(mode: 'face'),
                              ),
                            );
                          },
                          child: Container(
                            constraints: const BoxConstraints(minHeight: 72),
                            margin: const EdgeInsets.only(bottom: 20),
                            decoration: BoxDecoration(
                              color: const Color(0xFF6B1D73),
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(
                                    0xFF6B1D73,
                                  ).withOpacity(0.3),
                                  blurRadius: 8,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.25),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Icon(
                                      Icons.camera_alt,
                                      color: Colors.white,
                                      size: 32,
                                    ),
                                  ),
                                  const SizedBox(width: 20),
                                  const Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Identify Person',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 20,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                        SizedBox(height: 6),
                                        Text(
                                          'Recognize and identify people',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 15,
                                            height: 1.3,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  const Icon(
                                    Icons.arrow_forward_ios,
                                    color: Colors.white,
                                    size: 22,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 80),
                ],
              ),
            ),
          ),
        ),
      ),
      // Bottom Navigation Bar
      bottomNavigationBar: Semantics(
        label: 'Main navigation bar',
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          selectedItemColor: const Color(0xFF6B1D73),
          unselectedItemColor: const Color(0xFF424242),
          backgroundColor: Colors.white,
          selectedLabelStyle: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
          unselectedLabelStyle: const TextStyle(
            fontWeight: FontWeight.normal,
            fontSize: 13,
          ),
          type: BottomNavigationBarType.fixed,
          iconSize: 28,
          onTap: (index) {
            HapticFeedback.lightImpact();
            setState(() {
              _currentIndex = index;
            });

            if (index == 0) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => const HomePage()),
              );
            } else if (index == 1) {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const RemindersPage()),
              );
            } else if (index == 2) {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SosScreen()),
              );
            } else if (index == 3) {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsPage()),
              );
            }
          },
          items: const [
            BottomNavigationBarItem(
              icon: Padding(
                padding: EdgeInsets.only(bottom: 4),
                child: Icon(Icons.home_outlined),
              ),
              label: 'Home',
              tooltip: 'Navigate to Home page',
            ),
            BottomNavigationBarItem(
              icon: Padding(
                padding: EdgeInsets.only(bottom: 4),
                child: Icon(Icons.notifications_none),
              ),
              label: 'Reminders',
              tooltip: 'Navigate to Reminders page',
            ),
            BottomNavigationBarItem(
              icon: Padding(
                padding: EdgeInsets.only(bottom: 4),
                child: Icon(Icons.warning_amber_outlined),
              ),
              label: 'Emergency',
              tooltip: 'Navigate to Emergency SOS page',
            ),
            BottomNavigationBarItem(
              icon: Padding(
                padding: EdgeInsets.only(bottom: 4),
                child: Icon(Icons.settings),
              ),
              label: 'Settings',
              tooltip: 'Navigate to Settings page',
            ),
          ],
        ),
      ),
    );
  }
}

// Accessible Button Widget
class AccessibleButton extends StatefulWidget {
  final VoidCallback onTap;
  final Widget child;
  final String semanticLabel;

  const AccessibleButton({
    Key? key,
    required this.onTap,
    required this.child,
    required this.semanticLabel,
  }) : super(key: key);

  @override
  State<AccessibleButton> createState() => _AccessibleButtonState();
}

class _AccessibleButtonState extends State<AccessibleButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 100),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.97,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.semanticLabel,
      button: true,
      enabled: true,
      child: GestureDetector(
        onTapDown: (_) {
          _controller.forward();
          HapticFeedback.lightImpact();
        },
        onTapUp: (_) => _controller.reverse(),
        onTapCancel: () => _controller.reverse(),
        onTap: widget.onTap,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return Transform.scale(
              scale: _scaleAnimation.value,
              child: widget.child,
            );
          },
        ),
      ),
    );
  }
}
