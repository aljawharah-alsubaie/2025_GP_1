// lib/services/face_recognition_api.dart
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class FaceRecognitionAPI {
  // Change to your backend URL
  static const String BASE_URL = "http://192.168.1.238:8000";
  
  // For testing on real device, use your computer's IP:
  // static const String BASE_URL = "http://192.168.1.XXX:8000";
  
  // ============================================================
  // Health Check
  // ============================================================
  
  static Future<bool> testConnection() async {
    try {
      print('Testing API connection...');
      
      final response = await http.get(
        Uri.parse('$BASE_URL/health'),
      ).timeout(const Duration(seconds: 10));

      print('Connection test response: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('API Status: ${data['status']}');
        print('InsightFace: ${data['insightface']}');
        print('Firebase: ${data['firebase']}');
        return data['status'] == 'healthy';
      }
      
      return false;
    } catch (e) {
      print('API Connection Error: $e');
      return false;
    }
  }

  // ============================================================
  // Recognize Face
  // ============================================================
  
  static Future<RecognitionResult> recognizeFace({
    required File imageFile,
    required String userId,
  }) async {
    try {
      print('Starting face recognition...');
      
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$BASE_URL/recognize'),
      );
      
      // Add user_id field
      request.fields['user_id'] = userId;
      
      // Add image file
      request.files.add(
        await http.MultipartFile.fromPath(
          'file',
          imageFile.path,
        ),
      );

      print('Sending recognition request...');
      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);
      
      print('Response status: ${response.statusCode}');
      print('Response body: ${response.body}');
      
      if (response.statusCode == 200) {
        Map<String, dynamic> jsonResponse = json.decode(response.body);
        return RecognitionResult.fromJson(jsonResponse);
      } else {
        throw Exception('Recognition failed: ${response.statusCode}');
      }
    } catch (e) {
      print('Face recognition error: $e');
      return RecognitionResult(
        success: false,
        recognized: false,
        personName: null,
        personId: null,
        confidence: 0.0,
        similarityScore: 0.0,
        message: 'Error: $e',
      );
    }
  }

  // ============================================================
  // Enroll Person (Face Rotation)
  // ============================================================
  
  static Future<EnrollmentResult> enrollPerson({
    required String name,
    required String userId,
    required List<File> images, // 5 images from rotation
    File? encryptedThumbnail, // Optional encrypted thumbnail
  }) async {
    try {
      print('Enrolling person: $name with ${images.length} images');
      
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$BASE_URL/enroll_person'),
      );
      
      // Add form fields
      request.fields['name'] = name;
      request.fields['user_id'] = userId;
      
      // Add all rotation images
      for (int i = 0; i < images.length; i++) {
        request.files.add(
          await http.MultipartFile.fromPath(
            'files',
            images[i].path,
          ),
        );
      }
      
      // Add encrypted thumbnail if provided
      if (encryptedThumbnail != null) {
        request.files.add(
          await http.MultipartFile.fromPath(
            'encrypted_thumbnail',
            encryptedThumbnail.path,
          ),
        );
      }

      print('Sending enrollment request...');
      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);
      
      print('Enrollment response status: ${response.statusCode}');
      print('Response body: ${response.body}');
      
      if (response.statusCode == 200) {
        Map<String, dynamic> jsonResponse = json.decode(response.body);
        return EnrollmentResult.fromJson(jsonResponse);
      } else {
        throw Exception('Enrollment failed: ${response.statusCode}');
      }
    } catch (e) {
      print('Enrollment error: $e');
      return EnrollmentResult(
        success: false,
        message: 'Error: $e',
        personId: null,
        personName: null,
        totalEmbeddings: 0,
        successfulImages: 0,
      );
    }
  }

  // ============================================================
  // List Persons
  // ============================================================
  
  static Future<List<Person>> listPersons(String userId) async {
    try {
      print('Fetching persons list for user: $userId');
      
      final response = await http.get(
        Uri.parse('$BASE_URL/list_persons/$userId'),
      ).timeout(const Duration(seconds: 10));

      print('List persons response: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        Map<String, dynamic> jsonResponse = json.decode(response.body);
        
        if (jsonResponse['success'] == true) {
          List<dynamic> personsJson = jsonResponse['persons'];
          return personsJson.map((p) => Person.fromJson(p)).toList();
        }
      }
      
      throw Exception('Failed to fetch persons list');
    } catch (e) {
      print('Get persons list error: $e');
      return [];
    }
  }

  // ============================================================
  // Delete Person
  // ============================================================
  
  static Future<bool> deletePerson({
    required String userId,
    required String personId,
  }) async {
    try {
      print('Deleting person: $personId');
      
      final response = await http.delete(
        Uri.parse('$BASE_URL/delete_person/$userId/$personId'),
      ).timeout(const Duration(seconds: 10));

      print('Delete response: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        Map<String, dynamic> jsonResponse = json.decode(response.body);
        return jsonResponse['success'] == true;
      }
      
      return false;
    } catch (e) {
      print('Delete person error: $e');
      return false;
    }
  }
}

// ============================================================
// Models
// ============================================================

class RecognitionResult {
  final bool success;
  final bool recognized;
  final String? personName;
  final String? personId;
  final double confidence;
  final double? similarityScore;
  final String? message;

  RecognitionResult({
    required this.success,
    required this.recognized,
    this.personName,
    this.personId,
    required this.confidence,
    this.similarityScore,
    this.message,
  });

  factory RecognitionResult.fromJson(Map<String, dynamic> json) {
    return RecognitionResult(
      success: json['success'] ?? false,
      recognized: json['recognized'] ?? false,
      personName: json['person_name'],
      personId: json['person_id'],
      confidence: (json['confidence'] ?? 0.0).toDouble(),
      similarityScore: json['similarity_score']?.toDouble(),
      message: json['message'],
    );
  }

  // For backward compatibility with old code
  bool get isMatch => recognized;
  double get similarity => confidence;

  @override
  String toString() {
    return 'RecognitionResult(success: $success, recognized: $recognized, '
        'personName: $personName, confidence: $confidence, message: $message)';
  }
}

class EnrollmentResult {
  final bool success;
  final String? message;
  final String? personId;
  final String? personName;
  final int totalEmbeddings;
  final int successfulImages;

  EnrollmentResult({
    required this.success,
    this.message,
    this.personId,
    this.personName,
    required this.totalEmbeddings,
    required this.successfulImages,
  });

  factory EnrollmentResult.fromJson(Map<String, dynamic> json) {
    return EnrollmentResult(
      success: json['success'] ?? false,
      message: json['message'],
      personId: json['person_id'],
      personName: json['person_name'],
      totalEmbeddings: json['total_embeddings'] ?? 0,
      successfulImages: json['successful_images'] ?? 0,
    );
  }

  @override
  String toString() {
    return 'EnrollmentResult(success: $success, message: $message, '
        'personName: $personName, successfulImages: $successfulImages)';
  }
}

class Person {
  final String personId;
  final String name;
  final int numPhotos;
  final String? thumbnailUrl;

  Person({
    required this.personId,
    required this.name,
    required this.numPhotos,
    this.thumbnailUrl,
  });

  factory Person.fromJson(Map<String, dynamic> json) {
    return Person(
      personId: json['person_id'],
      name: json['name'],
      numPhotos: json['num_photos'] ?? 0,
      thumbnailUrl: json['thumbnail_url'],
    );
  }

  @override
  String toString() {
    return 'Person(personId: $personId, name: $name, numPhotos: $numPhotos)';
  }
}