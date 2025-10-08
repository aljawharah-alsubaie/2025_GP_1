import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'home_page.dart';
import 'accountinfopage.dart';
import 'DeviceAlertsPage .dart';
import 'securitydatapage.dart';
import 'termspoliciespage.dart';
import 'login_screen.dart';
import 'Reminders.dart'; // Add this import
import 'sos_screen.dart'; // Add this import
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'welcome_screen.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  Future<void> _logout(BuildContext context) async {
    final Color purple = const Color(0xFFCE7ED6);

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Logout'),
          content: const Text('Are you sure you want to logout?'),
          actions: [
            // Purple logout button on the left
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: purple,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('Logout'),
            ),
            // Cancel button on the right
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      try {
        // ✅ امسح الـ session المحفوظة أولاً
      final storage = FlutterSecureStorage();
      await storage.delete(key: 'isLoggedIn');
      await storage.delete(key: 'userEmail');
      
        await FirebaseAuth.instance.signOut();

        // Navigate back to login screen and clear all previous routes
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const WelcomeScreen()),
          (route) => false,
        );
      } catch (e) {
        print('Logout error: $e');
        // Show error message
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to logout. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color purple = const Color(0xFFCE7ED6);
    final Color borderColor = const Color(0xFFB14ABA);
    final double cardWidth = MediaQuery.of(context).size.width / 2 - 27;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              const SizedBox(height: 20),
              const Text(
                'Settings',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 40),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildSettingCard(
                          context,
                          width: cardWidth,
                          icon: Icons.person,
                          title: 'Account Info',
                          subtitle: 'Edit personal info or delete your account',
                          color: purple,
                          borderColor: borderColor,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const AccountInfoPage(),
                              ),
                            );
                          },
                        ),
                        _buildSettingCard(
                          context,
                          width: cardWidth,
                          icon: Icons.notifications_active,
                          title: 'Device & Alerts',
                          subtitle:
                              'Set up device connections and notifications',
                          color: purple,
                          borderColor: borderColor,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const DeviceAlertsPage(),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 15),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildSettingCard(
                          context,
                          width: cardWidth,
                          icon: Icons.lock,
                          title: 'Security & Data',
                          subtitle:
                              'Manage your password and login preferences',
                          color: purple,
                          borderColor: borderColor,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const SecurityDataPage(),
                              ),
                            );
                          },
                        ),
                        _buildSettingCard(
                          context,
                          width: cardWidth,
                          icon: Icons.description,
                          title: 'Terms & Policies',
                          subtitle: 'View the app terms and policies',
                          color: purple,
                          borderColor: borderColor,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const TermsPoliciesPage(),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 15),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildSettingCard(
                          context,
                          width: cardWidth,
                          icon: Icons.logout,
                          title: 'Logout',
                          subtitle: 'Sign out of your account',
                          color: purple,
                          borderColor: borderColor,
                          onTap: () => _logout(context),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 3,
        selectedItemColor: purple,
        unselectedItemColor: Colors.black,
        backgroundColor: Colors.white,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.normal),
        type: BottomNavigationBarType.fixed,
        onTap: (index) {
          if (index == 0) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const HomePage()),
            );
          } else if (index == 1) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const RemindersPage()),
            );
          } else if (index == 2) {
            final user = FirebaseAuth.instance.currentUser;
            final userName = user?.displayName ?? user?.email ?? 'User';

            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => const SosScreen(),  // ✅ no args passed
              ),
            );
          }
          // Index 3 is current page (Settings), so no navigation needed
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

  static Widget _buildSettingCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required Color borderColor,
    required double width,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: width,
        height: 160,
        child: Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: borderColor.withOpacity(0.05)),
          ),
          elevation: 2,
          shadowColor: borderColor.withOpacity(0.2),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  backgroundColor: color,
                  child: Icon(icon, color: Colors.white),
                ),
                const SizedBox(height: 18),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: Text(
                    subtitle,
                    style: const TextStyle(fontSize: 11, color: Colors.black54),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
