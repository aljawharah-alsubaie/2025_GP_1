import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_tts/flutter_tts.dart';
import './reminders.dart';
import './home_page.dart';
import './settings.dart';
import './sos_screen.dart';
import './location_permission_screen.dart';

class ContactInfoPage extends StatefulWidget {
  const ContactInfoPage({super.key});

  @override
  State<ContactInfoPage> createState() => _ContactInfoPageState();
}

class _ContactInfoPageState extends State<ContactInfoPage> with TickerProviderStateMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FlutterTts _tts = FlutterTts();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  
  List<Map<String, dynamic>> _contacts = [];
  bool _isLoading = true;
  bool _isUploading = false;
  String _searchQuery = '';

  late AnimationController _fadeController;
  late AnimationController _slideController;

  // 🎨 نظام ألوان موحد
  static const Color deepPurple = Color.fromARGB(255, 92, 25, 99);
  static const Color vibrantPurple = Color(0xFF8E3A95);
  static const Color primaryPurple = Color(0xFF9C4A9E);
  static const Color softPurple = Color(0xFFB665BA);
  static const Color lightPurple = Color.fromARGB(255, 217, 163, 227);
  static const Color palePurple = Color.fromARGB(255, 218, 185, 225);
  static const Color ultraLightPurple = Color(0xFFF3E5F5);

  @override
  void initState() {
    super.initState();
    _initTts();
    _loadContacts();

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..forward();

    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..forward();
  }

  Future<void> _initTts() async {
    await _tts.setLanguage("en-US");
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
  }

  Future<void> _speak(String text) async {
    await _tts.speak(text);
  }

  void _hapticFeedback() {
    HapticFeedback.mediumImpact();
  }

  @override
  void dispose() {
    _tts.stop();
    _searchController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _fadeController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  bool _isValidSaudiPhoneNumber(String phone) {
    String cleanPhone = phone.replaceAll(RegExp(r'[\s\-\(\)]'), '');
    
    if (cleanPhone.startsWith('+966')) {
      cleanPhone = cleanPhone.substring(4);
      return cleanPhone.length == 9 && RegExp(r'^[5][0-9]{8}$').hasMatch(cleanPhone);
    }
    
    if (cleanPhone.startsWith('966')) {
      cleanPhone = cleanPhone.substring(3);
      return cleanPhone.length == 9 && RegExp(r'^[5][0-9]{8}$').hasMatch(cleanPhone);
    }
    
    if (cleanPhone.startsWith('05')) {
      return cleanPhone.length == 10 && RegExp(r'^05[0-9]{8}$').hasMatch(cleanPhone);
    }
    
    if (cleanPhone.length == 9 && cleanPhone.startsWith('5')) {
      return RegExp(r'^[5][0-9]{8}$').hasMatch(cleanPhone);
    }
    
    return false;
  }

  String _formatPhoneNumber(String phone) {
    String cleanPhone = phone.replaceAll(RegExp(r'[\s\-\(\)]'), '');
    
    if (cleanPhone.startsWith('+966')) {
      return cleanPhone;
    } else if (cleanPhone.startsWith('966')) {
      return '+$cleanPhone';
    } else if (cleanPhone.startsWith('05')) {
      return '+966${cleanPhone.substring(1)}';
    } else if (cleanPhone.length == 9 && cleanPhone.startsWith('5')) {
      return '+966$cleanPhone';
    }
    
    return cleanPhone;
  }

  Future<void> _loadContacts() async {
    try {
      final User? user = _auth.currentUser;
      if (user == null) return;

      final QuerySnapshot snapshot = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('contacts')
          .orderBy('name')
          .get();

      setState(() {
        _contacts = snapshot.docs.map((doc) {
          final data = doc.data() as Map<String, dynamic>;
          data['id'] = doc.id;
          return data;
        }).toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading contacts: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _addContact() async {
    if (_nameController.text.trim().isEmpty) {
      if (mounted) {
        _speak('Please provide a name');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please provide a name'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    if (_phoneController.text.trim().isEmpty) {
      if (mounted) {
        _speak('Please provide a phone number');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please provide a phone number'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    if (!_isValidSaudiPhoneNumber(_phoneController.text.trim())) {
      if (mounted) {
        _speak('Please enter a valid Saudi phone number');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enter a valid Saudi phone number'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 4),
          ),
        );
      }
      return;
    }

    final User? user = _auth.currentUser;
    if (user == null) return;

    setState(() => _isUploading = true);

    try {
      final formattedPhone = _formatPhoneNumber(_phoneController.text.trim());

      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('contacts')
          .add({
        'name': _nameController.text.trim(),
        'phone': formattedPhone,
        'createdAt': FieldValue.serverTimestamp(),
      });

      await _loadContacts();

      if (mounted) {
        Navigator.pop(context);
        _resetForm();
        _speak('Contact added successfully');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Contact added successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() => _isUploading = false);
      if (mounted) {
        _speak('Error adding contact');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error adding contact: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _updateContact(String contactId, String newName, String newPhone) async {
    if (newName.trim().isEmpty) {
      if (mounted) {
        _speak('Please provide a name');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please provide a name'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    if (newPhone.trim().isEmpty) {
      if (mounted) {
        _speak('Please provide a phone number');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please provide a phone number'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    if (!_isValidSaudiPhoneNumber(newPhone.trim())) {
      if (mounted) {
        _speak('Please enter a valid Saudi phone number');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enter a valid Saudi phone number'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 4),
          ),
        );
      }
      return;
    }

    final User? user = _auth.currentUser;
    if (user == null) return;

    setState(() => _isUploading = true);

    try {
      final formattedPhone = _formatPhoneNumber(newPhone.trim());

      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('contacts')
          .doc(contactId)
          .update({
        'name': newName.trim(),
        'phone': formattedPhone,
      });

      await _loadContacts();

      if (mounted) {
        Navigator.pop(context);
        _resetForm();
        _speak('Contact updated successfully');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Contact updated successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() => _isUploading = false);
      if (mounted) {
        _speak('Error updating contact');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating contact: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _deleteContact(String contactId, String contactName) async {
    final User? user = _auth.currentUser;
    if (user == null) return;

    try {
      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('contacts')
          .doc(contactId)
          .delete();

      await _loadContacts();

      if (mounted) {
        _speak('Contact deleted');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$contactName deleted successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        _speak('Error deleting contact');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting contact: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _resetForm() {
    setState(() {
      _nameController.clear();
      _phoneController.clear();
      _isUploading = false;
    });
  }

  void _showDeleteConfirmation(String contactId, String contactName) {
    _hapticFeedback();
    _speak('Delete $contactName');
    
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
          child: Container(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(40),
                  ),
                  child: const Icon(
                    Icons.delete_outline,
                    size: 40,
                    color: Colors.red,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Delete Contact?',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: deepPurple,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Are you sure you want to delete "$contactName"?',
                  style: TextStyle(
                    fontSize: 14,
                    color: deepPurple.withOpacity(0.6),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          _hapticFeedback();
                          _speak('Cancelled');
                          Navigator.pop(context);
                        },
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          side: BorderSide(color: Colors.grey.shade300, width: 2),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: Text(
                          'Cancel',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () async {
                          _hapticFeedback();
                          Navigator.pop(context);
                          await _deleteContact(contactId, contactName);
                        },
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          backgroundColor: Colors.red,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Text(
                          'Delete',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  List<Map<String, dynamic>> get _filteredContacts {
    if (_searchQuery.isEmpty) return _contacts;
    return _contacts
        .where(
          (contact) =>
              contact['name'].toString().toLowerCase().contains(_searchQuery.toLowerCase()) ||
              contact['phone'].toString().toLowerCase().contains(_searchQuery.toLowerCase()),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ultraLightPurple,
      body: Stack(
        children: [
          _buildGradientBackground(),
          SafeArea(
            child: Column(
              children: [
                _buildModernHeader(),
                Expanded(
                  child: _buildContactsList(),
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: _buildAddButton(),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      bottomNavigationBar: _buildFloatingBottomNav(),
    );
  }

  Widget _buildGradientBackground() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            ultraLightPurple,
            palePurple.withOpacity(0.3),
            Colors.white,
          ],
          stops: const [0.0, 0.5, 1.0],
        ),
      ),
    );
  }

  Widget _buildModernHeader() {
    return FadeTransition(
      opacity: _fadeController,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.white.withOpacity(0.9),
              Colors.white.withOpacity(0.7),
              const Color.fromARGB(198, 255, 255, 255),
              const Color.fromARGB(195, 240, 224, 245),
            ],
          ),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Semantics(
                  label: 'Back to home',
                  button: true,
                  child: GestureDetector(
                    onTap: () {
                      _hapticFeedback();
                      _speak('Back');
                      Navigator.pop(context);
                    },
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: vibrantPurple.withOpacity(0.15),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.arrow_back,
                        color: deepPurple,
                        size: 24,
                      ),
                    ),
                  ),
                ),
                
                const SizedBox(width: 12),
                
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Emergency Contacts',
                        style: TextStyle(
                          fontSize: 12,
                          color: deepPurple.withOpacity(0.5),
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${_contacts.length} Contacts',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          foreground: Paint()
                            ..shader = LinearGradient(
                              colors: [deepPurple, vibrantPurple],
                            ).createShader(Rect.fromLTWH(0, 0, 200, 70)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // Search Bar
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: palePurple.withOpacity(0.2),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: TextField(
                controller: _searchController,
                onChanged: (value) {
                  setState(() => _searchQuery = value);
                },
                decoration: InputDecoration(
                  hintText: "Search contacts...",
                  hintStyle: TextStyle(
                    color: deepPurple.withOpacity(0.4),
                  ),
                  prefixIcon: Icon(
                    Icons.search,
                    color: vibrantPurple,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContactsList() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: vibrantPurple),
      );
    }

    if (_filteredContacts.isEmpty && _searchQuery.isNotEmpty) {
      return _buildEmptyState(
        icon: Icons.search_off,
        message: 'No contacts found matching your search',
      );
    }

    if (_contacts.isEmpty) {
      return _buildEmptyState(
        icon: Icons.contacts_outlined,
        message: "You haven't added contacts yet\nTap the button below to add your first contact",
      );
    }

    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, 0.15),
        end: Offset.zero,
      ).animate(CurvedAnimation(
        parent: _slideController,
        curve: Curves.easeOutCubic,
      )),
      child: RefreshIndicator(
        onRefresh: _loadContacts,
        color: vibrantPurple,
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 100),
          itemCount: _filteredContacts.length,
          itemBuilder: (context, index) {
            final contact = _filteredContacts[index];
            return _buildContactCard(contact);
          },
        ),
      ),
    );
  }

  Widget _buildContactCard(Map<String, dynamic> contact) {
    return Semantics(
      label: 'Contact: ${contact['name']}. Phone: ${contact['phone']}. Double tap to see options',
      button: true,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              _hapticFeedback();
              _speak('${contact['name']}. ${contact['phone']}');
            },
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: palePurple.withOpacity(0.35),
                    blurRadius: 15,
                    offset: const Offset(0, 8),
                  ),
                  BoxShadow(
                    color: Colors.white.withOpacity(0.8),
                    blurRadius: 12,
                    offset: const Offset(-2, -2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [deepPurple, vibrantPurple],
                      ),
                      borderRadius: BorderRadius.circular(15),
                      boxShadow: [
                        BoxShadow(
                          color: vibrantPurple.withOpacity(0.35),
                          blurRadius: 12,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        contact['name']?.toString().substring(0, 1).toUpperCase() ?? '?',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                  
                  const SizedBox(width: 14),
                  
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          contact['name']?.toString() ?? 'Unknown',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: deepPurple,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Icons.phone,
                              size: 14,
                              color: deepPurple.withOpacity(0.5),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              contact['phone']?.toString() ?? 'No phone',
                              style: TextStyle(
                                fontSize: 12,
                                color: deepPurple.withOpacity(0.5),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  
                  // Edit Button
                  GestureDetector(
                    onTap: () {
                      _hapticFeedback();
                      _speak('Edit ${contact['name']}');
                      _showEditDialog(
                        contact['id'],
                        contact['name']?.toString() ?? 'Unknown',
                        contact['phone']?.toString() ?? '',
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            vibrantPurple.withOpacity(0.1),
                            primaryPurple.withOpacity(0.1),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.edit,
                        size: 18,
                        color: vibrantPurple,
                      ),
                    ),
                  ),
                  
                  const SizedBox(width: 8),
                  
                  // Delete Button
                  GestureDetector(
                    onTap: () {
                      _showDeleteConfirmation(
                        contact['id'],
                        contact['name']?.toString() ?? 'Unknown',
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.delete,
                        size: 18,
                        color: Colors.red,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String message,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [deepPurple.withOpacity(0.1), vibrantPurple.withOpacity(0.1)],
              ),
              borderRadius: BorderRadius.circular(60),
            ),
            child: Icon(
              icon,
              size: 60,
              color: deepPurple.withOpacity(0.3),
            ),
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              message,
              style: TextStyle(
                fontSize: 16,
                color: deepPurple.withOpacity(0.5),
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddButton() {
    return Semantics(
      label: 'Add new contact',
      button: true,
      child: GestureDetector(
        onTap: () {
          _hapticFeedback();
          _speak('Add contact');
          _showAddDialog();
        },
        child: Container(
          width: 70,
          height: 70,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [vibrantPurple, primaryPurple],
            ),
            borderRadius: BorderRadius.circular(35),
            boxShadow: [
              BoxShadow(
                color: vibrantPurple.withOpacity(0.5),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: const Icon(
            Icons.add,
            color: Colors.white,
            size: 36,
          ),
        ),
      ),
    );
  }

  Widget _buildFloatingBottomNav() {
    return ClipRRect(
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(24),
        topRight: Radius.circular(24),
      ),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              deepPurple.withOpacity(0.95),
              vibrantPurple.withOpacity(0.98),
              primaryPurple,
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: deepPurple.withOpacity(0.3),
              blurRadius: 25,
              offset: const Offset(0, -8),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildNavButton(
                  icon: Icons.home_rounded,
                  label: 'Home',
                  onTap: () {
                    _hapticFeedback();
                    _speak('Home');
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (context) => const HomePage()),
                    );
                  },
                ),
                _buildNavButton(
                  icon: Icons.notifications_rounded,
                  label: 'Reminders',
                  onTap: () {
                    _hapticFeedback();
                    _speak('Reminders');
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (context) => const RemindersPage()),
                    );
                  },
                ),
                _buildNavButton(
                  icon: Icons.contact_phone,
                  label: 'Emergency',
                  isActive: true,
                  onTap: () {
                    _hapticFeedback();
                    _speak('Emergency Contact');
                  },
                ),
                _buildNavButton(
                  icon: Icons.settings_rounded,
                  label: 'Settings',
                  onTap: () {
                    _hapticFeedback();
                    _speak('Settings');
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (context) => const SettingsPage()),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavButton({
    required IconData icon,
    required String label,
    bool isActive = false,
    required VoidCallback onTap,
  }) {
    return Semantics(
      label: '$label button',
      button: true,
      selected: isActive,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: isActive 
                ? Colors.white.withOpacity(0.25)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: isActive
                ? Border.all(
                    color: Colors.white.withOpacity(0.3),
                    width: 1.5,
                  )
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: isActive 
                    ? Colors.white
                    : Colors.white.withOpacity(0.9),
                size: 22,
              ),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(
                  color: isActive 
                      ? Colors.white
                      : Colors.white.withOpacity(0.9),
                  fontSize: 11,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAddDialog() {
    _resetForm();
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
          child: Container(
            padding: const EdgeInsets.all(24),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [vibrantPurple, primaryPurple],
                      ),
                      borderRadius: BorderRadius.circular(40),
                    ),
                    child: const Icon(
                      Icons.person_add,
                      color: Colors.white,
                      size: 40,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    "Add Contact",
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: deepPurple,
                    ),
                  ),
                  const SizedBox(height: 24),
                  
                  // Name Field
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      "Name",
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: deepPurple,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      hintText: "Enter contact name",
                      hintStyle: TextStyle(color: Colors.grey.shade400),
                      fillColor: ultraLightPurple,
                      filled: true,
                      prefixIcon: Icon(Icons.person, color: vibrantPurple),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 16,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  
                  // Phone Field
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      "Phone Number",
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: deepPurple,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[\d\+\-\(\)\s]')),
                    ],
                    decoration: InputDecoration(
                      hintText: "05xxxxxxxx or +966xxxxxxxxx",
                      hintStyle: TextStyle(color: Colors.grey.shade400),
                      fillColor: ultraLightPurple,
                      filled: true,
                      prefixIcon: Icon(Icons.phone, color: vibrantPurple),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 16,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Accepted formats: 05xxxxxxxx, +966xxxxxxxxx, 966xxxxxxxxx',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 30),
                  
                  // Buttons
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            _hapticFeedback();
                            _speak('Cancelled');
                            _resetForm();
                            Navigator.pop(context);
                          },
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            side: BorderSide(color: lightPurple, width: 2),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: Text(
                            'Cancel',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: vibrantPurple,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [vibrantPurple, primaryPurple],
                            ),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: vibrantPurple.withOpacity(0.4),
                                blurRadius: 15,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: ElevatedButton(
                            onPressed: _isUploading
                                ? null
                                : () async {
                                    _hapticFeedback();
                                    setDialogState(() => _isUploading = true);
                                    await _addContact();
                                    setDialogState(() => _isUploading = false);
                                  },
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: _isUploading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                    ),
                                  )
                                : const Text(
                                    "Add Contact",
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
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
    );
  }

  void _showEditDialog(String contactId, String currentName, String currentPhone) {
    _resetForm();
    _nameController.text = currentName;
    _phoneController.text = currentPhone;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
          child: Container(
            padding: const EdgeInsets.all(24),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [vibrantPurple, primaryPurple],
                      ),
                      borderRadius: BorderRadius.circular(40),
                    ),
                    child: const Icon(
                      Icons.edit,
                      color: Colors.white,
                      size: 40,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    "Edit Contact",
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: deepPurple,
                    ),
                  ),
                  const SizedBox(height: 24),
                  
                  // Name Field
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      "Name",
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: deepPurple,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      hintText: "Enter contact name",
                      hintStyle: TextStyle(color: Colors.grey.shade400),
                      fillColor: ultraLightPurple,
                      filled: true,
                      prefixIcon: Icon(Icons.person, color: vibrantPurple),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 16,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  
                  // Phone Field
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      "Phone Number",
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: deepPurple,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[\d\+\-\(\)\s]')),
                    ],
                    decoration: InputDecoration(
                      hintText: "05xxxxxxxx or +966xxxxxxxxx",
                      hintStyle: TextStyle(color: Colors.grey.shade400),
                      fillColor: ultraLightPurple,
                      filled: true,
                      prefixIcon: Icon(Icons.phone, color: vibrantPurple),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 16,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Accepted formats: 05xxxxxxxx, +966xxxxxxxxx, 966xxxxxxxxx',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 30),
                  
                  // Buttons
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            _hapticFeedback();
                            _speak('Cancelled');
                            _resetForm();
                            Navigator.pop(context);
                          },
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            side: BorderSide(color: lightPurple, width: 2),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: Text(
                            'Cancel',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: vibrantPurple,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [vibrantPurple, primaryPurple],
                            ),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: vibrantPurple.withOpacity(0.4),
                                blurRadius: 15,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: ElevatedButton(
                            onPressed: _isUploading
                                ? null
                                : () async {
                                    _hapticFeedback();
                                    setDialogState(() => _isUploading = true);
                                    await _updateContact(
                                      contactId,
                                      _nameController.text.trim(),
                                      _phoneController.text.trim(),
                                    );
                                    setDialogState(() => _isUploading = false);
                                  },
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: _isUploading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                    ),
                                  )
                                : const Text(
                                    "Update Contact",
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
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
    );
  }
}