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
  String? _profileImageUrl; // To store the Firebase Storage URL
  bool _isUploading = false; // To show loading state
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

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    print('Loading user data...');
    final user = _auth.currentUser;
    if (user != null) {
      print('User found: ${user.uid}');
      final doc = await _firestore.collection('users').doc(user.uid).get();
      if (doc.exists) {
        print('Document exists, loading data...');
        final data = doc.data();
        _emailController.text = data?['email'] ?? '';
        _nameController.text = data?['full_name'] ?? '';
        _phoneController.text = data?['phone'] ?? '';
        _addressController.text = data?['address'] ?? '';
        selectedCountryName = data?['country'];
        selectedCity = data?['city'];
        selectedCountryCode = data?['countryCode'];
        _profileImageUrl = data?['profileImageUrl']; // Load existing image URL

        if (selectedCountryCode != null) {
          fetchCities(selectedCountryCode!);
        }
        print('Data loaded successfully');
        setState(() {});
      } else {
        print('Document does not exist');
      }
    } else {
      print('No user found');
    }
  }

  Future<String?> _uploadImageToFirebase(File imageFile) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return null;

      // Create a reference to Firebase Storage
      final storageRef = _storage.ref().child('profilePic/${user.uid}.jpg');

      // Upload the file
      final uploadTask = storageRef.putFile(imageFile);

      // Wait for upload to complete
      final snapshot = await uploadTask;

      // Get the download URL
      final downloadUrl = await snapshot.ref.getDownloadURL();

      return downloadUrl;
    } catch (e) {
      print('Error uploading image: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to upload image: $e')));
      return null;
    }
  }

  Future<void> _saveProfile() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Confirm Save'),
        content: Text('Are you sure you want to save changes?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Yes'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final user = _auth.currentUser;
      if (user != null) {
        // Prepare the data to save
        Map<String, dynamic> userData = {
          'email': _emailController.text.trim(),
          'full_name': _nameController.text.trim(),
          'phone': _phoneController.text.trim(),
          'address': _addressController.text.trim(),
          'country': selectedCountryName,
          'city': selectedCity,
          'countryCode': selectedCountryCode,
        };

        // If there's a new image, upload it first
        if (_image != null) {
          setState(() => _isUploading = true);

          final imageUrl = await _uploadImageToFirebase(_image!);
          if (imageUrl != null) {
            userData['profileImageUrl'] = imageUrl;
            _profileImageUrl = imageUrl; // Update local state
          }

          setState(() => _isUploading = false);
        }

        // Save all data to Firestore
        await _firestore.collection('users').doc(user.uid).update(userData);

        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Your changes have been saved successfully')),
        );
      }
    }
  }

  Future<void> _getImage() async {
    final pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80, // Compress image to reduce upload time
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

  // Helper method to get the current profile image
  ImageProvider _getProfileImage() {
    if (_image != null) {
      return FileImage(_image!); // Show newly selected image
    } else if (_profileImageUrl != null && _profileImageUrl!.isNotEmpty) {
      return NetworkImage(_profileImageUrl!); // Show image from Firebase
    } else {
      return const AssetImage('assets/images/profileimg.jpg'); // Default image
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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

                  const Text(
                    "Personal Details",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  _buildField("Name", _nameController),
                  _buildField("Email Address", _emailController),
                  _buildField("Phone Number", _phoneController),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "Address Details",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      GestureDetector(
                        onTap: _getCurrentLocationAndFill,
                        child: const Text(
                          "or Use Current Location",
                          style: TextStyle(
                            color: Color(0xFF6B1D73),
                            fontSize: 14,
                            fontStyle: FontStyle.italic,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    "Country",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 4),
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
                    child: AbsorbPointer(
                      child: DropdownButtonFormField<String>(
                        value: selectedCountryName,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                        ),
                        hint: Text(
                          "Please select your Country",
                          style: TextStyle(
                            fontStyle: FontStyle.italic,
                            fontSize: 13,
                            color: Colors.black.withOpacity(0.5),
                          ),
                        ),
                        items: selectedCountryName != null
                            ? [
                                DropdownMenuItem(
                                  value: selectedCountryName,
                                  child: Text(selectedCountryName!),
                                ),
                              ]
                            : [],
                        onChanged: (_) {},
                        icon: const Icon(Icons.arrow_drop_down),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    "City",
                    style: TextStyle(fontWeight: FontWeight.w500, fontSize: 16),
                  ),
                  const SizedBox(height: 4),
                  DropdownSearch<String>(
                    key: ValueKey(selectedCountryCode),
                    items: (filter, infiniteScrollProps) => cities,
                    selectedItem: selectedCity,
                    enabled: cities.isNotEmpty,
                    onChanged: (val) => setState(() => selectedCity = val),
                    decoratorProps: DropDownDecoratorProps(
                      decoration: InputDecoration(
                        hintText: "Please select your City",
                        hintStyle: TextStyle(
                          fontSize: 13,
                          fontStyle: FontStyle.italic,
                          color: Colors.black.withOpacity(0.5),
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
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
                      emptyBuilder: (context, _) =>
                          const Center(child: Text("No data found")),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildField("Address", _addressController),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: _isUploading ? null : _saveProfile,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6B1D73),
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: _isUploading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            ),
                          )
                        : const Text(
                            "Save",
                            style: TextStyle(color: Colors.white),
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

  Widget _buildField(String label, TextEditingController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 16),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: label == "Address" ? "Enter your address" : null,
            hintStyle: TextStyle(
              fontSize: 13,
              fontStyle: FontStyle.italic,
              color: Colors.black.withOpacity(0.5),
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
          ),
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
                    backgroundColor: Colors.white.withOpacity(0.22),
                    radius: 45,
                  ),
                ),
                Positioned(
                  top: 120,
                  right: -15,
                  child: CircleAvatar(
                    backgroundColor: Colors.white.withOpacity(0.22),
                    radius: 40,
                  ),
                ),
                Positioned(
                  bottom: 110,
                  left: 60,
                  child: CircleAvatar(
                    backgroundColor: Colors.white.withOpacity(0.22),
                    radius: 15,
                  ),
                ),
                Positioned(
                  bottom: 210,
                  left: 240,
                  child: CircleAvatar(
                    backgroundColor: Colors.white.withOpacity(0.22),
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
            icon: const Icon(Icons.arrow_back, color: Colors.white, size: 40),
            onPressed: () => Navigator.of(context).pop(),
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
                fontSize: 20,
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
                      color: Colors.black.withOpacity(0.3),
                    ),
                    child: const Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
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
                      radius: 14,
                      backgroundColor: _isUploading
                          ? Colors.grey
                          : const Color(0xFF007AFF),
                      child: Icon(Icons.edit, size: 16, color: Colors.white),
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
