import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:country_picker/country_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:dropdown_search/dropdown_search.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  File? _image;
  String? _profileImageUrl;
  bool _isUploading = false;
  final picker = ImagePicker();

  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  final _storage = FirebaseStorage.instance;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();

  String? selectedCountryCode;
  String? selectedCountryName;
  String? selectedCity;
  List<String> cities = [];

  late FocusNode _nameFocus;
  late FocusNode _emailFocus;
  late FocusNode _phoneFocus;
  late FocusNode _addressFocus;
  late FocusNode _saveFocus;

  @override
  void initState() {
    super.initState();
    _nameFocus = FocusNode();
    _emailFocus = FocusNode();
    _phoneFocus = FocusNode();
    _addressFocus = FocusNode();
    _saveFocus = FocusNode();
    _loadUserData();
  }

  @override
  void dispose() {
    _nameFocus.dispose();
    _emailFocus.dispose();
    _phoneFocus.dispose();
    _addressFocus.dispose();
    _saveFocus.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    final user = _auth.currentUser;
    if (user != null) {
      final doc = await _firestore.collection('users').doc(user.uid).get();
      if (doc.exists) {
        final data = doc.data();
        _emailController.text = data?['email'] ?? '';
        _nameController.text = data?['full_name'] ?? '';
        _phoneController.text = data?['phone'] ?? '';
        _addressController.text = data?['address'] ?? '';
        selectedCountryName = data?['country'];
        selectedCity = data?['city'];
        selectedCountryCode = data?['countryCode'];
        _profileImageUrl = data?['profileImageUrl'];

        if (selectedCountryCode != null) {
          fetchCities(selectedCountryCode!);
        }
        setState(() {});
      }
    }
  }

  Future<String?> _uploadImageToFirebase(File imageFile) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return null;

      final storageRef = _storage.ref().child('profilePic/${user.uid}.jpg');
      final uploadTask = storageRef.putFile(imageFile);
      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();
      return downloadUrl;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to upload image: $e')));
      }
      return null;
    }
  }

  Future<void> _saveProfile() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Save'),
        content: const Text('Are you sure you want to save changes?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Yes'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final user = _auth.currentUser;
      if (user != null) {
        Map<String, dynamic> userData = {
          'email': _emailController.text.trim(),
          'full_name': _nameController.text.trim(),
          'phone': _phoneController.text.trim(),
          'address': _addressController.text.trim(),
          'country': selectedCountryName,
          'city': selectedCity,
          'countryCode': selectedCountryCode,
        };

        if (_image != null) {
          setState(() => _isUploading = true);
          final imageUrl = await _uploadImageToFirebase(_image!);
          if (imageUrl != null) {
            userData['profileImageUrl'] = imageUrl;
            _profileImageUrl = imageUrl;
          }
          setState(() => _isUploading = false);
        }

        await _firestore.collection('users').doc(user.uid).update(userData);
        setState(() {});
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Your changes have been saved successfully'),
            ),
          );
        }
      }
    }
  }

  Future<void> _getImage() async {
    final pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );

    if (pickedFile != null) {
      setState(() => _image = File(pickedFile.path));
    }
  }

  Future<void> fetchCities(String countryCode) async {
    final username = 'fajer_mh';
    final url = Uri.parse(
      'http://api.geonames.org/searchJSON?country=$countryCode&featureClass=P&maxRows=1000&username=$username',
    );
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<String> fetchedCities = (data['geonames'] as List)
            .where((item) => item['fcode'] == 'PPLA' || item['fcode'] == 'PPLC')
            .map((item) => item['name'].toString())
            .toSet()
            .toList();
        setState(() {
          cities = fetchedCities;
        });
      } else {
        setState(() {
          cities = [];
        });
      }
    } catch (e) {
      setState(() {
        cities = [];
      });
    }
  }

  Future<void> _getCurrentLocationAndFill() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.deniedForever ||
            permission == LocationPermission.denied)
          return;
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      List<Placemark> placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );
      if (placemarks.isNotEmpty) {
        Placemark place = placemarks.first;
        setState(() {
          selectedCountryName = place.country;
          selectedCountryCode = place.isoCountryCode;
          selectedCity = place.locality ?? place.subAdministrativeArea;
          _addressController.text =
              "${place.street ?? ''}, ${place.subLocality ?? ''}, ${place.administrativeArea ?? ''}";
        });

        if (selectedCountryCode != null) {
          fetchCities(selectedCountryCode!);
        }
      }
    } catch (e) {
      print("Location error: $e");
    }
  }

  ImageProvider _getProfileImage() {
    if (_image != null) {
      return FileImage(_image!);
    } else if (_profileImageUrl != null && _profileImageUrl!.isNotEmpty) {
      return NetworkImage(_profileImageUrl!);
    } else {
      return const AssetImage('assets/images/profileimg.jpg');
    }
  }

  InputDecoration _buildInputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(
        color: Color(0xFF6B1D73),
        fontWeight: FontWeight.w500,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFF6B1D73), width: 1.5),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFF6B1D73), width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFF6B1D73), width: 2.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      filled: true,
      fillColor: Colors.white,
    );
  }

  @override
  Widget build(BuildContext context) {
    final textScaleFactor = MediaQuery.of(context).textScaleFactor;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SingleChildScrollView(
        child: Column(
          children: [
            _buildHeader(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 20),
                  Text(
                    "Personal Details",
                    style: TextStyle(
                      fontSize: 18 * textScaleFactor,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF2C3E50),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    "Name",
                    _nameController,
                    _nameFocus,
                    _emailFocus,
                  ),
                  _buildTextField(
                    "Email Address",
                    _emailController,
                    _emailFocus,
                    _phoneFocus,
                  ),
                  _buildTextField(
                    "Phone Number",
                    _phoneController,
                    _phoneFocus,
                    _addressFocus,
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "Address Details",
                        style: TextStyle(
                          fontSize: 18 * textScaleFactor,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF2C3E50),
                        ),
                      ),
                      GestureDetector(
                        onTap: _getCurrentLocationAndFill,
                        child: Tooltip(
                          message: 'Use current location',
                          child: Text(
                            "or Use Current Location",
                            style: TextStyle(
                              color: const Color(0xFF6B1D73),
                              fontSize: 13 * textScaleFactor,
                              fontStyle: FontStyle.italic,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    "Country",
                    style: TextStyle(
                      fontSize: 16 * textScaleFactor,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF2C3E50),
                    ),
                  ),
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: () {
                      showCountryPicker(
                        context: context,
                        showPhoneCode: false,
                        onSelect: (Country country) {
                          setState(() {
                            selectedCountryCode = country.countryCode;
                            selectedCountryName = country.name;
                            selectedCity = null;
                            cities = [];
                          });
                          fetchCities(country.countryCode);
                        },
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: const Color(0xFF6B1D73),
                          width: 1.5,
                        ),
                        borderRadius: BorderRadius.circular(8),
                        color: Colors.white,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            selectedCountryName ?? 'Select Country',
                            style: TextStyle(
                              fontSize: 14 * textScaleFactor,
                              color: selectedCountryName != null
                                  ? Colors.black
                                  : Colors.grey,
                            ),
                          ),
                          const Icon(
                            Icons.arrow_drop_down,
                            color: Color(0xFF6B1D73),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    "City",
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 16 * textScaleFactor,
                      color: const Color(0xFF2C3E50),
                    ),
                  ),
                  const SizedBox(height: 6),
                  DropdownSearch<String>(
                    key: ValueKey(selectedCountryCode),
                    items: (filter, infiniteScrollProps) => cities,
                    selectedItem: selectedCity,
                    enabled: cities.isNotEmpty,
<<<<<<< HEAD
                    onChanged: (val) {
                      setState(() => selectedCity = val);
                    },
                    dropdownDecoratorProps: DropDownDecoratorProps(
                      dropdownSearchDecoration: InputDecoration(
                        hintText: cities.isEmpty
                            ? "Select country first"
                            : "Select City",
=======
                    onChanged: (val) => setState(() => selectedCity = val),
                    decoratorProps: DropDownDecoratorProps(
                      decoration: InputDecoration(
                        hintText: "Please select your City",
>>>>>>> caeda50e20ec4305479346973e7b9a765cf600e4
                        hintStyle: TextStyle(
                          fontSize: 13 * textScaleFactor,
                          fontStyle: FontStyle.italic,
                          color: Colors.black.withOpacity(0.6),
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(
                            color: Color(0xFF6B1D73),
                            width: 1.5,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(
                            color: Color(0xFF6B1D73),
                            width: 1.5,
                          ),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 14,
                        ),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                    ),
                    popupProps: PopupProps.bottomSheet(
                      showSearchBox: true,
                      searchFieldProps: TextFieldProps(
                        decoration: InputDecoration(
                          hintText: 'Search City...',
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                        ),
                      ),
                      containerBuilder: (context, popupWidget) {
                        return Container(
                          color: Colors.white,
                          child: popupWidget,
                        );
                      },
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(context).size.height * 0.7,
                      ),
                      emptyBuilder: (context, _) => const Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Text("No cities found"),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    "Address",
                    _addressController,
                    _addressFocus,
                    _saveFocus,
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      focusNode: _saveFocus,
                      onPressed: _isUploading ? null : _saveProfile,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6B1D73),
                        disabledBackgroundColor: Colors.grey,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: _isUploading
                          ? const SizedBox(
                              height: 24,
                              width: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            )
                          : Text(
                              "Save Changes",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16 * textScaleFactor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 30),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(
    String label,
    TextEditingController controller,
    FocusNode currentFocus,
    FocusNode nextFocus,
  ) {
    final textScaleFactor = MediaQuery.of(context).textScaleFactor;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w500,
            fontSize: 16 * textScaleFactor,
            color: const Color(0xFF2C3E50),
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          focusNode: currentFocus,
          textInputAction: TextInputAction.next,
          onSubmitted: (_) => nextFocus.requestFocus(),
          keyboardType: label == "Email Address"
              ? TextInputType.emailAddress
              : label == "Phone Number"
              ? TextInputType.phone
              : TextInputType.text,
          decoration: _buildInputDecoration(label),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildHeader() {
    return Stack(
      children: [
        ClipPath(
          clipper: WaveClipper(),
          child: Container(
            height: 260,
            decoration: const BoxDecoration(color: Color(0xFF6B1D73)),
            child: Stack(
              children: [
                Positioned(
                  top: -12,
                  left: -20,
                  child: CircleAvatar(
                    backgroundColor: Colors.white.withOpacity(0.12),
                    radius: 45,
                  ),
                ),
                Positioned(
                  top: 120,
                  right: -15,
                  child: CircleAvatar(
                    backgroundColor: Colors.white.withOpacity(0.12),
                    radius: 40,
                  ),
                ),
                Positioned(
                  bottom: 110,
                  left: 60,
                  child: CircleAvatar(
                    backgroundColor: Colors.white.withOpacity(0.12),
                    radius: 15,
                  ),
                ),
                Positioned(
                  bottom: 210,
                  left: 240,
                  child: CircleAvatar(
                    backgroundColor: Colors.white.withOpacity(0.12),
                    radius: 15,
                  ),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          top: 24,
          left: 6,
          child: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white, size: 28),
            onPressed: () => Navigator.of(context).pop(),
            tooltip: 'Go back',
          ),
        ),
        const Positioned(
          top: 30,
          left: 0,
          right: 0,
          child: Center(
            child: Text(
              "My Profile",
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        Positioned(
          top: 70,
          left: MediaQuery.of(context).size.width / 2 - 45,
          child: Stack(
            children: [
              CircleAvatar(
                radius: 45,
                backgroundColor: Colors.grey[300],
                backgroundImage: _getProfileImage(),
              ),
              if (_isUploading)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black.withOpacity(0.4),
                    ),
                    child: const Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                  ),
                ),
              Positioned(
                bottom: 0,
                right: 5,
                child: GestureDetector(
                  onTap: _isUploading ? null : _getImage,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: CircleAvatar(
                      radius: 16,
                      backgroundColor: _isUploading
                          ? Colors.grey
                          : const Color(0xFF007AFF),
                      child: Icon(Icons.edit, size: 18, color: Colors.white),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class WaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    Path path = Path();
    path.lineTo(0, size.height - 20);
    var firstStart = Offset(size.width / 4, size.height - 130);
    var firstEnd = Offset(size.width / 2, size.height - 70);
    path.quadraticBezierTo(
      firstStart.dx,
      firstStart.dy,
      firstEnd.dx,
      firstEnd.dy,
    );
    var secondStart = Offset(size.width * 3 / 4, size.height);
    var secondEnd = Offset(size.width, size.height - 120);
    path.quadraticBezierTo(
      secondStart.dx,
      secondStart.dy,
      secondEnd.dx,
      secondEnd.dy,
    );
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}
