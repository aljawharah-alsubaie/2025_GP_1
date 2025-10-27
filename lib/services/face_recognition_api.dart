// lib/services/face_recognition_api.dart
import 'dart:convert';
import 'package:http/http.dart' as http;

class FaceRecognitionAPI {
  static const String BASE_URL = "https://242a811cb53e509ce6.gradio.live";
  
  // 🔍 التعرف على وجه من الصورة
  static Future<RecognitionResult> recognizeFace(List<int> imageBytes) async {
    try {
      final response = await http.post(
        Uri.parse('$BASE_URL/recognize'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'image': base64Encode(imageBytes),
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        }),
      );

      if (response.statusCode == 200) {
        final result = json.decode(response.body);
        return RecognitionResult.fromJson(result);
      } else {
        throw Exception('API Error: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ API Recognition Error: $e');
      throw Exception('Failed to recognize face: $e');
    }
  }

  // ➕ إضافة وجه جديد
  static Future<bool> addFace(String personName, List<int> imageBytes) async {
    try {
      final response = await http.post(
        Uri.parse('$BASE_URL/add_face'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'name': personName,
          'image': base64Encode(imageBytes),
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        }),
      );

      return response.statusCode == 200;
    } catch (e) {
      print('❌ API Add Face Error: $e');
      return false;
    }
  }

  // 🗑️ حذف وجه
  static Future<bool> deleteFace(String personName) async {
    try {
      final response = await http.post(
        Uri.parse('$BASE_URL/delete_face'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'name': personName,
        }),
      );

      return response.statusCode == 200;
    } catch (e) {
      print('❌ API Delete Face Error: $e');
      return false;
    }
  }

  // 📋 الحصول على قائمة الوجوه
  static Future<List<String>> getFacesList() async {
    try {
      final response = await http.get(
        Uri.parse('$BASE_URL/faces_list'),
      );

      if (response.statusCode == 200) {
        final result = json.decode(response.body);
        return List<String>.from(result['faces'] ?? []);
      }
      return [];
    } catch (e) {
      print('❌ API Get Faces Error: $e');
      return [];
    }
  }

  // 🧪 اختبار اتصال API
  static Future<bool> testConnection() async {
    try {
      final response = await http.get(
        Uri.parse('$BASE_URL/'),
        headers: {'Content-Type': 'application/json'},
      );

      return response.statusCode == 200;
    } catch (e) {
      print('❌ API Test Connection Error: $e');
      return false;
    }
  }
}

class RecognitionResult {
  final String personId;
  final double similarity;
  final bool isMatch;
  final double confidence;

  RecognitionResult({
    required this.personId,
    required this.similarity,
    required this.isMatch,
    required this.confidence,
  });

  factory RecognitionResult.fromJson(Map<String, dynamic> json) {
    return RecognitionResult(
      personId: json['person_id'] ?? 'Unknown',
      similarity: (json['similarity'] ?? 0.0).toDouble(),
      isMatch: json['is_match'] ?? false,
      confidence: (json['confidence'] ?? 0.0).toDouble(),
    );
  }

  @override
  String toString() {
    return 'RecognitionResult(personId: $personId, similarity: $similarity, isMatch: $isMatch, confidence: $confidence)';
  }
}