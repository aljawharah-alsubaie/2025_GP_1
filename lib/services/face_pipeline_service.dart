// lib/services/face_pipeline_service.dart
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'face_recognition_api.dart';

class FacePipelineService {
  static final FacePipelineService _instance = FacePipelineService._internal();
  factory FacePipelineService() => _instance;
  FacePipelineService._internal();

  // 🔧 تهيئة الخدمة
  static Future<bool> initialize() async {
    try {
      // اختبار الاتصال بالAPI
      bool isConnected = await FaceRecognitionAPI.testConnection();
      print('🔧 Face Pipeline Initialized: $isConnected');
      return isConnected;
    } catch (e) {
      print('❌ Face Pipeline Initialization Error: $e');
      return false;
    }
  }

  // ➕ إضافة شخص جديد
  static Future<bool> addPerson(String name, List<File> images) async {
    try {
      print('👤 Adding person: $name with ${images.length} images');
      
      int successCount = 0;
      List<String> photoUrls = [];

      for (File image in images) {
        bool registered = await FaceRecognitionAPI.registerFace(name, image);
        if (registered) {
          successCount++;
          
          // رفع الصورة إلى Firebase Storage
          String? photoUrl = await _uploadImageToFirebase(image, name);
          if (photoUrl != null) {
            photoUrls.add(photoUrl);
          }
        }
      }

      if (successCount > 0) {
        // حفظ البيانات في Firestore
        await _savePersonToFirestore(name, photoUrls, successCount);
        return true;
      }
      
      return false;
    } catch (e) {
      print('❌ Add Person Error: $e');
      return false;
    }
  }

  // 🔍 التعرف على شخص
  static Future<RecognitionResult> recognizePerson(File image) async {
    try {
      print('🔍 Recognizing person from image...');
      return await FaceRecognitionAPI.recognizeFace(image);
    } catch (e) {
      print('❌ Recognize Person Error: $e');
      return RecognitionResult(
        personId: 'Unknown',
        similarity: 0.0,
        isMatch: false,
        confidence: 0.0,
      );
    }
  }

  // 🗑️ حذف شخص
  static Future<bool> deletePerson(String personId, String personName) async {
    try {
      print('🗑️ Deleting person: $personName');
      
      // حذف من Firestore
      await _deletePersonFromFirestore(personId);
      
      // حذف الصور من Storage
      await _deleteImagesFromStorage(personName);
      
      return true;
    } catch (e) {
      print('❌ Delete Person Error: $e');
      return false;
    }
  }

  // 📋 جلب كل الأشخاص
  static Future<List<Map<String, dynamic>>> getAllPeople() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return [];

      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('people')
          .orderBy('createdAt', descending: true)
          .get();

      return snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();
    } catch (e) {
      print('❌ Get All People Error: $e');
      return [];
    }
  }

  // 🔧 الدوال المساعدة الخاصة بـ Firebase

  static Future<String?> _uploadImageToFirebase(File image, String personName) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return null;

      final storageRef = FirebaseStorage.instance
          .ref()
          .child('users')
          .child(user.uid)
          .child('faces')
          .child(personName)
          .child('${DateTime.now().millisecondsSinceEpoch}.jpg');

      await storageRef.putFile(image);
      return await storageRef.getDownloadURL();
    } catch (e) {
      print('❌ Upload Image Error: $e');
      return null;
    }
  }

  static Future<void> _savePersonToFirestore(
    String name, 
    List<String> photoUrls, 
    int successCount
  ) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('people')
          .add({
            'name': name,
            'photoUrls': photoUrls,
            'photoCount': photoUrls.length,
            'embeddingCount': successCount,
            'faceDetected': true,
            'createdAt': FieldValue.serverTimestamp(),
          });
    } catch (e) {
      print('❌ Save Person to Firestore Error: $e');
      rethrow;
    }
  }

  static Future<void> _deletePersonFromFirestore(String personId) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('people')
          .doc(personId)
          .delete();
    } catch (e) {
      print('❌ Delete Person from Firestore Error: $e');
      rethrow;
    }
  }

  static Future<void> _deleteImagesFromStorage(String personName) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final storageRef = FirebaseStorage.instance
          .ref()
          .child('users')
          .child(user.uid)
          .child('faces')
          .child(personName);

      final listResult = await storageRef.listAll();
      for (var item in listResult.items) {
        await item.delete();
      }
    } catch (e) {
      print('❌ Delete Images from Storage Error: $e');
    }
  }
}