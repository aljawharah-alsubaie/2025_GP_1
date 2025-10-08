import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import './profile.dart';
import './face_list.dart';
import './camera.dart';
import './settings.dart';
import './reminders.dart';
import './sos_screen.dart';
import './location_permission_screen.dart';
import './contact_info_page.dart';
import './currency_camera.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  bool _isProfileIncomplete = false;
  bool _isLoading = true;
  bool _isDismissed = false;

  @override
  void initState() {
    super.initState();
    _checkProfileCompleteness();
  }

  Future<void> _checkProfileCompleteness() async {
  try {
    final user = _auth.currentUser;
    if (user != null) {
      final doc = await _firestore.collection('users').doc(user.uid).get();
      if (doc.exists) {
        final data = doc.data();
        final bool isIncomplete =
            (data?['full_name']?.toString().trim().isEmpty ?? true) ||
            (data?['phone']?.toString().trim().isEmpty ?? true) ||
            (data?['address']?.toString().trim().isEmpty ?? true) ||
            (data?['country']?.toString().trim().isEmpty ?? true) ||
            (data?['city']?.toString().trim().isEmpty ?? true);
        
        // تحقق من آخر مرة عرضنا التنبيه
        final lastShown = data?['profile_reminder_last_shown'] as Timestamp?;
        final now = DateTime.now();
        
        bool shouldShow = false;
        if (isIncomplete) {
          if (lastShown == null) {
            // أول مرة - اعرض التنبيه
            shouldShow = true;
          } else {
            // تحقق إذا مر 3 أيام
            final daysSinceLastShown = now.difference(lastShown.toDate()).inDays;
            shouldShow = daysSinceLastShown >= 3;
          }
        }
        
        setState(() {
          _isProfileIncomplete = shouldShow;
          _isLoading = false;
        });
        
        // احفظ وقت العرض
        if (shouldShow) {
          await _firestore.collection('users').doc(user.uid).update({
            'profile_reminder_last_shown': Timestamp.now(),
          });
        }
      } else {
        setState(() {
          _isProfileIncomplete = true;
          _isLoading = false;
        });
      }
    } else {
      setState(() {
        _isLoading = false;
      });
    }
  } catch (e) {
    print('Error checking profile: $e');
    setState(() {
      _isLoading = false;
    });
  }
}

  @override
  Widget build(BuildContext context) {
    const purple = Color(0xFF6B1D73);
    return Scaffold(
      body: Stack(
        children: [
          ListView(
            padding: EdgeInsets.zero,
            children: [
              Stack(
                children: [
                  Container(
                    height: 170,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [purple, purple.withOpacity(0.8)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(40),
                      ),
                    ),
                  ),
                  // Logo in top-left corner (moved higher)
                  Positioned(
                    top: 15,
                    left: 16,
                    child: Container(
                      width: 120,
                      height: 120,
                      child: Image.asset(
                        'assets/images/logo.png', // Replace with your logo path
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                  // Profile icon in top-right corner
                  Positioned(
                    top: 40,
                    right: 16,
                    child: GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const ProfilePage(),
                          ),
                        ).then((_) => _checkProfileCompleteness());
                      },
                      child: const CircleAvatar(
                        radius: 20,
                        backgroundColor: Colors.white,
                        child: Icon(Icons.person, color: Colors.grey),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    _buildFeatureCard('Face Recognition'),
                    _buildFeatureCard('Emergency Contact', highlight: true),
                    _buildFeatureCard('Text Reading'),
                    _buildFeatureCard('Alerts / Reminders', highlight: true),
                    _buildFeatureCard('Currency Recognition'),
                    _buildFeatureCard('Color Identification', highlight: true),
                  ],
                ),
              ),
            ],
          ),
          // Profile incomplete overlay
          if (!_isLoading && _isProfileIncomplete && !_isDismissed)
            Container(
              color: Colors.black.withOpacity(0.5),
              child: Center(
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 300),
                  opacity: 1.0,
                  child: Container(
                    margin: const EdgeInsets.all(24),
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF6B1D73), Color(0xFF9C4A9E)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.account_circle_outlined,
                              color: Colors.white,
                              size: 24,
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Text(
                                'Complete Your Profile',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Please add your personal and address details to unlock all features!',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () {
                                setState(() => _isDismissed = true);
                              },
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.white70,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                              ),
                              child: const Text(
                                'Later',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const ProfilePage(),
                                  ),
                                ).then((_) => _checkProfileCompleteness());
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: const Color(0xFF6B1D73),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 8,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                elevation: 2,
                              ),
                              child: const Text(
                                'Complete Now',
                                style: TextStyle(
                                  fontSize: 14,
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
            ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 0,
        selectedItemColor: const Color(0xFFB14ABA),
        unselectedItemColor: Colors.black,
        backgroundColor: Colors.grey.shade200,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.normal),
        type: BottomNavigationBarType.fixed,
        onTap: (index) async {
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
            final user = _auth.currentUser;
            if (user != null) {
              final doc = await _firestore
                  .collection('users')
                  .doc(user.uid)
                  .get();
              final data = doc.data();
              final permissionGranted =
                  data?['location_permission_granted'] ?? false;
              if (!permissionGranted) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => LocationPermissionScreen(
                      onPermissionGranted: () async {
                        await _firestore
                            .collection('users')
                            .doc(user.uid)
                            .update({'location_permission_granted': true});
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const SosScreen(),
                          ),
                        );
                      },
                    ),
                  ),
                );
              } else {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const SosScreen()),
                );
              }
            }
          } else if (index == 3) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const SettingsPage()),
            );
          }
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.notifications_none),
            label: 'Reminders',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.warning_amber_outlined),
            label: 'Emergency',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }

  static Widget _buildFeatureCard(String title, {bool highlight = false}) {
    String imageName = '';
    String description = '';
    switch (title) {
      case 'Face Recognition':
        imageName = 'facerecog.jpg';
        description = 'Identify and recognize people';
        break;
      case 'Emergency Contact':
        imageName = 'emergency_contacts.jpg';
        description = 'Manage your emergency contacts';
        break;
      case 'Text Reading':
        imageName = 'textreading.jpg';
        description = 'Read printed text aloud';
        break;
      case 'Alerts / Reminders':
        imageName = 'reminders.jpg';
        description = 'Set and manage your reminders';
        break;
      case 'Currency Recognition':
        imageName = 'currency.jpg';
        description = 'Identify different currencies';
        break;
      case 'Color Identification':
        imageName = 'color.jpg';
        description = 'Detect and identify colors';
        break;
      default:
        description = 'Feature description';
        break;
    }

    return Builder(
      builder: (context) => Card(
        color: highlight ? const Color(0xAA6B1D73) : const Color(0xAAC8B8E4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.symmetric(vertical: 10),
        child: ListTile(
          leading: Container(
            width: 50,
            height: 50,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            child: imageName.isNotEmpty
                ? (title == 'Emergency Contact' 
                    ? const Icon(Icons.contact_emergency, color: Colors.black, size: 32)
                    : Image.asset('assets/images/$imageName', fit: BoxFit.contain))
                : const Icon(Icons.image, color: Colors.grey, size: 20),
          ),
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Text(description, style: const TextStyle(fontSize: 13)),
          trailing: const Icon(Icons.arrow_forward_ios),
          onTap: () {
            if (title == 'Face Recognition') {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const FaceListPage(),
                ),
              );
            } else if (title == 'Emergency Contact') {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ContactInfoPage(),
                ),
              );
            } else if (title == 'Alerts / Reminders') {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const RemindersPage()),
              );
            } else if (title == 'Text Reading') {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const CameraScreen(mode: 'text'),
                ),
              );
            } else if (title == 'Currency Recognition') {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => const CurrencyCameraScreen(),
    ),
  );
            } else if (title == 'Color Identification') {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const CameraScreen(mode: 'color'),
                ),
              );
            }
          },
        ),
      ),
    );
  }
}