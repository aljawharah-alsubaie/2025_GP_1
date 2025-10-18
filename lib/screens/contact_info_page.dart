import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_tts/flutter_tts.dart';
import './reminders.dart';
import './home_page.dart';
import './settings.dart';

class ContactInfoPage extends StatefulWidget {
  const ContactInfoPage({super.key});

  @override
  State<ContactInfoPage> createState() => _ContactInfoPageState();
}

class _ContactInfoPageState extends State<ContactInfoPage>
    with TickerProviderStateMixin {
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

  AnimationController? _fadeController;
  AnimationController? _slideController;

  static const Color deepPurple = Color.fromARGB(255, 92, 25, 99);
  static const Color vibrantPurple = Color(0xFF8E3A95);
  static const Color primaryPurple = Color(0xFF9C4A9E);
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
    _fadeController?.dispose();
    _slideController?.dispose();
    super.dispose();
  }

  bool _isValidSaudiPhoneNumber(String phone) {
    String cleanPhone = phone.replaceAll(RegExp(r'[\s\-\(\)]'), '');

    if (cleanPhone.startsWith('+966')) {
      cleanPhone = cleanPhone.substring(4);
      return cleanPhone.length == 9 &&
          RegExp(r'^[5][0-9]{8}$').hasMatch(cleanPhone);
    }

    if (cleanPhone.startsWith('966')) {
      cleanPhone = cleanPhone.substring(3);
      return cleanPhone.length == 9 &&
          RegExp(r'^[5][0-9]{8}$').hasMatch(cleanPhone);
    }

    if (cleanPhone.startsWith('05')) {
      return cleanPhone.length == 10 &&
          RegExp(r'^05[0-9]{8}$').hasMatch(cleanPhone);
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

  // NEW: Helper to build a front-of-form error banner
  Widget _buildErrorBanner(String message) {
    return Semantics(
      liveRegion: true,
      label: 'Error',
      container: true,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          border: Border.all(color: Colors.red.shade300),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline, color: Colors.red),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: Colors.red.shade800,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
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
    // NOTE: validation moved into dialog so message shows in front of the form.
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
        _showSnackBar('Contact added successfully!', Colors.green);
      }
    } catch (e) {
      setState(() => _isUploading = false);
      if (mounted) {
        _showSnackBar('Error adding contact: $e', Colors.red);
      }
    }
  }

  Future<void> _updateContact(
    String contactId,
    String newName,
    String newPhone,
  ) async {
    // NOTE: validation moved into dialog so message shows in front of the form.
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
          .update({'name': newName.trim(), 'phone': formattedPhone});

      await _loadContacts();

      if (mounted) {
        Navigator.pop(context);
        _resetForm();
        _showSnackBar('Contact updated successfully!', Colors.green);
      }
    } catch (e) {
      setState(() => _isUploading = false);
      if (mounted) {
        _showSnackBar('Error updating contact: $e', Colors.red);
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

  void _showSnackBar(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: const Duration(seconds: 2),
      ),
    );
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
          insetPadding: const EdgeInsets.symmetric(horizontal: 20),
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxWidth: 500),
            padding: const EdgeInsets.all(30),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(15),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.delete_outline,
                        color: Colors.red,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 13),
                    Text(
                      'Delete Contact',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: deepPurple,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                RichText(
                  textAlign: TextAlign.center,
                  text: TextSpan(
                    text: 'Are you sure you want to delete ',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: deepPurple,
                    ),
                    children: [
                      TextSpan(
                        text: '"$contactName"',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          color: deepPurple,
                          fontSize: 17,
                        ),
                      ),
                      const TextSpan(text: '?'),
                    ],
                  ),
                ),
                const SizedBox(height: 60),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          _hapticFeedback();
                          _speak('Cancelled');
                          Navigator.pop(context);
                        },
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          backgroundColor: deepPurple.withOpacity(0.15),
                          foregroundColor: deepPurple,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: BorderSide(
                              color: vibrantPurple.withOpacity(0.35),
                              width: 1.3,
                            ),
                          ),
                          elevation: 0,
                        ),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () async {
                          _hapticFeedback();
                          Navigator.pop(context);
                          await _deleteContact(contactId, contactName);
                        },
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          backgroundColor: Colors.red,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Text(
                          'Delete',
                          style: TextStyle(
                            fontSize: 18,
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
        _showSnackBar('$contactName deleted successfully!', Colors.green);
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('Error deleting contact: $e', Colors.red);
      }
    }
  }

  List<Map<String, dynamic>> get _filteredContacts {
    if (_searchQuery.isEmpty) return _contacts;
    return _contacts
        .where(
          (contact) =>
              contact['name'].toString().toLowerCase().contains(
                _searchQuery.toLowerCase(),
              ) ||
              contact['phone'].toString().toLowerCase().contains(
                _searchQuery.toLowerCase(),
              ),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ultraLightPurple,
      body: Stack(
        children: [
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
                stops: const [0.0, 0.5, 1.0],
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                _buildModernHeader(),
                Expanded(child: _buildContactsList()),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [_buildAddButton(), _buildFloatingBottomNav()],
      ),
    );
  }

  Widget _buildModernHeader() {
    return FadeTransition(
      opacity: _fadeController ?? const AlwaysStoppedAnimation(1.0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(25, 50, 25, 45),
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
                GestureDetector(
                  onTap: () {
                    _hapticFeedback();
                    _speak('Going back');
                    Navigator.pop(context);
                  },
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [vibrantPurple, primaryPurple],
                      ),
                      borderRadius: BorderRadius.all(Radius.circular(18)),
                      boxShadow: [
                        BoxShadow(
                          color: Color.fromARGB(76, 142, 58, 149),
                          blurRadius: 12,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.arrow_back_ios_new,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Emergency Contacts',
                        style: TextStyle(
                          fontSize: 25,
                          fontWeight: FontWeight.w900,
                          foreground: Paint()
                            ..shader = const LinearGradient(
                              colors: [deepPurple, vibrantPurple],
                            ).createShader(const Rect.fromLTWH(0, 0, 200, 70)),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Manage your contacts',
                        style: TextStyle(
                          fontSize: 14,
                          color: deepPurple.withOpacity(0.6),
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 25),
            Container(
              height: 50,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    lightPurple.withOpacity(0.3),
                    palePurple.withOpacity(0.4),
                  ],
                ),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(
                  color: deepPurple.withOpacity(0.3),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: vibrantPurple.withOpacity(0.15),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Icon(Icons.search, color: vibrantPurple, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      onChanged: (value) =>
                          setState(() => _searchQuery = value),
                      decoration: InputDecoration(
                        hintText: "Search contacts...",
                        border: InputBorder.none,
                        hintStyle: TextStyle(
                          color: deepPurple.withOpacity(0.7),
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      style: const TextStyle(
                        color: deepPurple,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContactsList() {
    return SlideTransition(
      position: _slideController != null
          ? Tween<Offset>(
              begin: const Offset(0, 0.15),
              end: Offset.zero,
            ).animate(
              CurvedAnimation(
                parent: _slideController!,
                curve: Curves.easeOutCubic,
              ),
            )
          : const AlwaysStoppedAnimation(Offset.zero),
      child: _isLoading
          ? const Center(child: CircularProgressIndicator(color: vibrantPurple))
          : _filteredContacts.isEmpty && _searchQuery.isNotEmpty
          ? _buildEmptySearch()
          : _contacts.isEmpty
          ? _buildEmptyState()
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
              itemCount: _filteredContacts.length,
              itemBuilder: (context, index) {
                return _buildContactCard(_filteredContacts[index]);
              },
            ),
    );
  }

  Widget _buildContactCard(Map<String, dynamic> contact) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: palePurple.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {
            _hapticFeedback();
            _speak(contact['name'] ?? 'Unknown');
            _showEditDialog(
              contact['id'],
              contact['name']?.toString() ?? 'Unknown',
              contact['phone']?.toString() ?? '',
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [vibrantPurple, primaryPurple],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Color.fromARGB(76, 142, 58, 149),
                        blurRadius: 8,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(3),
                  child: CircleAvatar(
                    radius: 25,
                    backgroundColor: Colors.white,
                    child: Text(
                      contact['name']
                              ?.toString()
                              .substring(0, 1)
                              .toUpperCase() ??
                          '?',
                      style: TextStyle(
                        color: deepPurple.withOpacity(0.5),
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        contact['name']?.toString() ?? 'Unknown',
                        style: const TextStyle(
                          fontSize: 17,
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
                            color: vibrantPurple.withOpacity(0.6),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            contact['phone']?.toString() ?? 'No phone',
                            style: TextStyle(
                              fontSize: 13,
                              color: deepPurple.withOpacity(0.5),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
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
                    width: 42,
                    height: 42,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: vibrantPurple.withOpacity(0.1),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: vibrantPurple.withOpacity(0.3),
                        width: 1.5,
                      ),
                    ),
                    child: const Icon(
                      Icons.edit_outlined,
                      color: vibrantPurple,
                      size: 20,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    _hapticFeedback();
                    _showDeleteConfirmation(
                      contact['id'],
                      contact['name']?.toString() ?? 'Unknown',
                    );
                  },
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.1),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.red.withOpacity(0.3),
                        width: 1.5,
                      ),
                    ),
                    child: const Icon(
                      Icons.delete_outline,
                      color: Colors.red,
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptySearch() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off,
              size: 64,
              color: deepPurple.withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            const Text(
              "No contacts found",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: deepPurple,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "Try a different search term",
              style: TextStyle(
                fontSize: 14,
                color: deepPurple.withOpacity(0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    vibrantPurple.withOpacity(0.2),
                    primaryPurple.withOpacity(0.2),
                  ],
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.person_add_outlined,
                size: 50,
                color: vibrantPurple,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              "No contacts added yet",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: deepPurple,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "Tap the button below to add your first contact",
              style: TextStyle(
                fontSize: 14,
                color: deepPurple.withOpacity(0.5),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 25),
      child: GestureDetector(
        onTap: () {
          _hapticFeedback();
          _speak('Add New Contact');
          _showAddDialog();
        },
        child: Container(
          width: double.infinity,
          height: 58,
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [deepPurple, vibrantPurple]),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: vibrantPurple.withOpacity(0.4),
                blurRadius: 15,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.add, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 12),
              const Text(
                'Add New Contact',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  letterSpacing: 0.5,
                ),
              ),
            ],
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
                      MaterialPageRoute(
                        builder: (context) => const RemindersPage(),
                      ),
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
                      MaterialPageRoute(
                        builder: (context) => const SettingsPage(),
                      ),
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
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? Colors.white.withOpacity(0.25) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: isActive
              ? Border.all(color: Colors.white.withOpacity(0.3), width: 1.5)
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isActive ? Colors.white : Colors.white.withOpacity(0.9),
              size: 22,
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                color: isActive ? Colors.white : Colors.white.withOpacity(0.9),
                fontSize: 13,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddDialog() {
    _resetForm();

    final Color fieldBackground = vibrantPurple.withOpacity(0.08);
    final Color fieldBorder = vibrantPurple.withOpacity(0.35);
    final Color fieldFocus = vibrantPurple;

    String? errorText; // NEW: local error state for front-of-form banner

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
          insetPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxWidth: 820),
            padding: const EdgeInsets.all(28),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(11),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [vibrantPurple, primaryPurple],
                          ),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.person_add,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 13),
                      Text(
                        "Add New Contact",
                        style: TextStyle(
                          fontSize: 25,
                          fontWeight: FontWeight.w800,
                          color: deepPurple,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // NEW: Error banner in front of the form
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: (errorText == null)
                        ? const SizedBox.shrink()
                        : _buildErrorBanner(errorText!),
                  ),

                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      "Name",
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: deepPurple,
                        fontSize: 18,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _nameController,
                    enabled: !_isUploading,
                    onChanged: (_) {
                      if (errorText != null) {
                        setDialogState(() => errorText = null);
                      }
                    },
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: deepPurple,
                    ),
                    decoration: InputDecoration(
                      hintText: "Enter contact's name",
                      hintStyle: TextStyle(color: Colors.grey.shade500),
                      filled: true,
                      fillColor: fieldBackground,
                      prefixIcon: Icon(
                        Icons.person,
                        color: vibrantPurple,
                        size: 24,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide(color: fieldBorder, width: 1.3),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide(color: fieldBorder, width: 1.3),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide(color: fieldFocus, width: 2),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 20,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      "Phone Number",
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: deepPurple,
                        fontSize: 17,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _phoneController,
                    enabled: !_isUploading,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r'[\d\+\-\(\)\s]'),
                      ),
                    ],
                    onChanged: (_) {
                      if (errorText != null) {
                        setDialogState(() => errorText = null);
                      }
                    },
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: deepPurple,
                    ),
                    decoration: InputDecoration(
                      hintText: "05xxxxxxxx or +966xxxxxxxxx",
                      hintStyle: TextStyle(color: Colors.grey.shade500),
                      filled: true,
                      fillColor: fieldBackground,
                      prefixIcon: Icon(
                        Icons.phone,
                        color: vibrantPurple,
                        size: 24,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide(color: fieldBorder, width: 1.3),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide(color: fieldBorder, width: 1.3),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide(color: fieldFocus, width: 2),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 20,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.lightbulb_outline,
                          color: Colors.red,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Accepted formats: 05xxxxxxxx, +966xxxxxxxxx',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.red,
                              fontWeight: FontWeight.w500,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 45),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _isUploading
                              ? null
                              : () {
                                  _hapticFeedback();
                                  Navigator.pop(context);
                                },
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 20),
                            backgroundColor: deepPurple.withOpacity(0.15),
                            foregroundColor: deepPurple,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: BorderSide(
                                color: vibrantPurple.withOpacity(0.35),
                                width: 1.3,
                              ),
                            ),
                          ),
                          child: const Text(
                            'Cancel',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _isUploading
                              ? null
                              : () async {
                                  _hapticFeedback();
                                  final name = _nameController.text.trim();
                                  final phone = _phoneController.text.trim();

                                  // VALIDATION moved here to show message in front of form
                                  if (name.isEmpty) {
                                    setDialogState(
                                      () => errorText = 'Please provide a name',
                                    );
                                    await _speak('Please provide a name');
                                    return;
                                  }
                                  if (phone.isEmpty) {
                                    setDialogState(
                                      () => errorText =
                                          'Please provide a phone number',
                                    );
                                    await _speak(
                                      'Please provide a phone number',
                                    );
                                    return;
                                  }
                                  if (!_isValidSaudiPhoneNumber(phone)) {
                                    setDialogState(
                                      () => errorText =
                                          'Please enter a valid Saudi phone number',
                                    );
                                    await _speak(
                                      'Please enter a valid Saudi phone number',
                                    );
                                    return;
                                  }

                                  setDialogState(() => _isUploading = true);
                                  await _addContact();
                                  if (mounted && Navigator.canPop(context)) {
                                    setDialogState(() => _isUploading = false);
                                  }
                                },
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 20),
                            backgroundColor: primaryPurple,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            elevation: 0,
                          ),
                          child: _isUploading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white,
                                    ),
                                  ),
                                )
                              : const Text(
                                  'Add Contact',
                                  style: TextStyle(
                                    fontSize: 18,
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
          ),
        ),
      ),
    );
  }

  void _showEditDialog(
    String contactId,
    String currentName,
    String currentPhone,
  ) {
    _resetForm();
    _nameController.text = currentName;
    _phoneController.text = currentPhone;

    final Color fieldBackground = vibrantPurple.withOpacity(0.08);
    final Color fieldBorder = vibrantPurple.withOpacity(0.35);
    final Color fieldFocus = vibrantPurple;

    String? errorText; // NEW: local error state for front-of-form banner

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
          insetPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxWidth: 820),
            padding: const EdgeInsets.all(28),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(11),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [vibrantPurple, primaryPurple],
                          ),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.edit,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 13),
                      Text(
                        "Edit Contact",
                        style: TextStyle(
                          fontSize: 25,
                          fontWeight: FontWeight.w800,
                          color: deepPurple,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // NEW: Error banner in front of the form
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: (errorText == null)
                        ? const SizedBox.shrink()
                        : _buildErrorBanner(errorText!),
                  ),

                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      "Name",
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: deepPurple,
                        fontSize: 18,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _nameController,
                    enabled: !_isUploading,
                    onChanged: (_) {
                      if (errorText != null) {
                        setDialogState(() => errorText = null);
                      }
                    },
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: deepPurple,
                    ),
                    decoration: InputDecoration(
                      hintText: "Enter contact's name",
                      hintStyle: TextStyle(color: Colors.grey.shade500),
                      filled: true,
                      fillColor: fieldBackground,
                      prefixIcon: Icon(
                        Icons.person,
                        color: vibrantPurple,
                        size: 24,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide(color: fieldBorder, width: 1.3),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide(color: fieldBorder, width: 1.3),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide(color: fieldFocus, width: 2),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 20,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      "Phone Number",
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: deepPurple,
                        fontSize: 17,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _phoneController,
                    enabled: !_isUploading,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r'[\d\+\-\(\)\s]'),
                      ),
                    ],
                    onChanged: (_) {
                      if (errorText != null) {
                        setDialogState(() => errorText = null);
                      }
                    },
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: deepPurple,
                    ),
                    decoration: InputDecoration(
                      hintText: "05xxxxxxxx or +966xxxxxxxxx",
                      hintStyle: TextStyle(color: Colors.grey.shade500),
                      filled: true,
                      fillColor: fieldBackground,
                      prefixIcon: Icon(
                        Icons.phone,
                        color: vibrantPurple,
                        size: 24,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide(color: fieldBorder, width: 1.3),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide(color: fieldBorder, width: 1.3),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide(color: fieldFocus, width: 2),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 20,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.lightbulb_outline,
                          color: Colors.red,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Accepted formats: 05xxxxxxxx, +966xxxxxxxxx',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.red.shade800,
                              fontWeight: FontWeight.w400,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 45),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _isUploading
                              ? null
                              : () {
                                  _hapticFeedback();
                                  Navigator.pop(context);
                                },
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 20),
                            backgroundColor: deepPurple.withOpacity(0.15),
                            foregroundColor: deepPurple,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: BorderSide(
                                color: vibrantPurple.withOpacity(0.35),
                                width: 1.3,
                              ),
                            ),
                          ),
                          child: const Text(
                            'Cancel',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _isUploading
                              ? null
                              : () async {
                                  final newName = _nameController.text.trim();
                                  final newPhone = _phoneController.text.trim();

                                  // VALIDATION moved here to show message in front of form
                                  if (newName.isEmpty) {
                                    setDialogState(
                                      () => errorText = 'Please provide a name',
                                    );
                                    await _speak('Please provide a name');
                                    return;
                                  }
                                  if (newPhone.isEmpty) {
                                    setDialogState(
                                      () => errorText =
                                          'Please provide a phone number',
                                    );
                                    await _speak(
                                      'Please provide a phone number',
                                    );
                                    return;
                                  }
                                  if (!_isValidSaudiPhoneNumber(newPhone)) {
                                    setDialogState(
                                      () => errorText =
                                          'Please enter a valid Saudi phone number',
                                    );
                                    await _speak(
                                      'Please enter a valid Saudi phone number',
                                    );
                                    return;
                                  }

                                  if (newName == currentName &&
                                      newPhone == currentPhone) {
                                    Navigator.pop(context);
                                    _showSnackBar(
                                      'No changes made',
                                      Colors.orange,
                                    );
                                    return;
                                  }

                                  _hapticFeedback();
                                  setDialogState(() => _isUploading = true);
                                  await _updateContact(
                                    contactId,
                                    newName,
                                    newPhone,
                                  );
                                  if (mounted && Navigator.canPop(context)) {
                                    setDialogState(() => _isUploading = false);
                                  }
                                },
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 20),
                            backgroundColor: primaryPurple,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            elevation: 0,
                          ),
                          child: _isUploading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white,
                                    ),
                                  ),
                                )
                              : const Text(
                                  'Save Changes',
                                  style: TextStyle(
                                    fontSize: 18,
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
          ),
        ),
      ),
    );
  }
}
