import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'dart:ui';

class FaceRecognitionService {
  static Interpreter? _interpreter;
  static bool _isInitialized = false;
  
  // ============ التعديل الرئيسي: دعم embeddings متعددة لكل شخص ============
  static Map<String, List<List<double>>> _storedMultipleEmbeddings = {};
  // ====================================================================
  
  // تحسين إعدادات النموذج
  static const int INPUT_SIZE = 112;
  static const int EMBEDDING_SIZE = 512;
  
  // إعدادات التحسين
  static const double MIN_FACE_SIZE = 0.1;
  static const double DEFAULT_THRESHOLD = 0.25; // خفض العتبة الافتراضية
  
  static Future<bool> initialize() async {
    if (_isInitialized) return true;
    
    try {
      print('Loading face recognition model...');
      
      final modelPaths = [
        'assets/models/feature_extractor.tflite', // النموذج الموجود عندك
        'assets/models/arcface.tflite',
        'assets/models/facenet.tflite',
        'assets/models/mobilefacenet.tflite',
      ];
      
      for (String path in modelPaths) {
        try {
          _interpreter = await Interpreter.fromAsset(path);
          print('✅ Successfully loaded model from: $path');
          
          final inputDetails = _interpreter!.getInputTensor(0);
          final outputDetails = _interpreter!.getOutputTensor(0);
          print('📊 Input shape: ${inputDetails.shape}, type: ${inputDetails.type}');
          print('📊 Output shape: ${outputDetails.shape}, type: ${outputDetails.type}');
          
          _isInitialized = true;
          return true;
        } catch (e) {
          print('❌ Failed to load $path: $e');
          continue;
        }
      }
      
      print('❌ All models failed to load');
      return false;
    } catch (e) {
      print('❌ Initialization error: $e');
      return false;
    }
  }

  // معالجة صورة محسنة
  static Float32List preprocessImage(img.Image faceImage, {String normalizationType = 'arcface'}) {
    // تحسين جودة الصورة
    var processedImage = img.adjustColor(faceImage, 
      contrast: 1.1,
      brightness: 1.02,
      saturation: 1.05,
    );
    
    // تغيير الحجم
    processedImage = img.copyResize(
      processedImage, 
      width: INPUT_SIZE, 
      height: INPUT_SIZE,
      interpolation: img.Interpolation.cubic
    );
    
    final input = Float32List(INPUT_SIZE * INPUT_SIZE * 3);
    int pixelIndex = 0;
    
    for (int y = 0; y < INPUT_SIZE; y++) {
      for (int x = 0; x < INPUT_SIZE; x++) {
        final pixel = processedImage.getPixel(x, y);
        
        switch (normalizationType.toLowerCase()) {
          case 'arcface':
            input[pixelIndex] = (pixel.r / 127.5) - 1.0;
            input[pixelIndex + 1] = (pixel.g / 127.5) - 1.0;
            input[pixelIndex + 2] = (pixel.b / 127.5) - 1.0;
            break;
          case 'facenet':
            input[pixelIndex] = (pixel.r - 127.5) / 128.0;
            input[pixelIndex + 1] = (pixel.g - 127.5) / 128.0;
            input[pixelIndex + 2] = (pixel.b - 127.5) / 128.0;
            break;
          case 'imagenet':
            input[pixelIndex] = pixel.r / 255.0;
            input[pixelIndex + 1] = pixel.g / 255.0;
            input[pixelIndex + 2] = pixel.b / 255.0;
            break;
          default:
            input[pixelIndex] = (pixel.r / 127.5) - 1.0;
            input[pixelIndex + 1] = (pixel.g / 127.5) - 1.0;
            input[pixelIndex + 2] = (pixel.b / 127.5) - 1.0;
        }
        pixelIndex += 3;
      }
    }
    
    return input;
  }

  static Future<List<double>?> generateEmbedding(File imageFile, {String normalizationType = 'arcface'}) async {
    if (!_isInitialized) {
      final initialized = await initialize();
      if (!initialized) return null;
    }
    
    try {
      if (!await imageFile.exists()) {
        print('❌ Image file not found: ${imageFile.path}');
        return null;
      }
      
      print('🔍 Starting face detection...');
      final faceRect = await detectFaceEnhanced(imageFile);
      if (faceRect == null) {
        print('❌ No face detected');
        return null;
      }
      
      print('✂️ Cropping face...');
      final croppedFace = await cropFaceEnhanced(imageFile, faceRect);
      if (croppedFace == null) {
        print('❌ Face cropping failed');
        return null;
      }
      
      print('🎨 Preprocessing image...');
      final input = preprocessImage(croppedFace, normalizationType: normalizationType);
      final inputTensor = input.reshape([1, INPUT_SIZE, INPUT_SIZE, 3]);
      
      final outputShape = _interpreter!.getOutputTensor(0).shape;
      print('📊 Model output shape: $outputShape');

      // ============ CRITICAL FIX: Handle 4D output ============
      List<double> rawEmbedding;
      final stopwatch = Stopwatch()..start();

      if (outputShape.length == 4) {
        // Shape: [1, 1, 1, 512]
        print('🔧 Using 4D output structure');
        final embeddingSize = outputShape.last;
        
        // Create 4D structure
        final outputTensor = List.generate(
          outputShape[0], 
          (i) => List.generate(
            outputShape[1], 
            (j) => List.generate(
              outputShape[2], 
              (k) => List.filled(outputShape[3], 0.0)
            )
          )
        );
        
        print('🚀 Running model inference...');
        _interpreter!.run(inputTensor, outputTensor);
        stopwatch.stop();
        
        print('⏱️ Inference time: ${stopwatch.elapsedMilliseconds}ms');
        
        // Extract embedding from [0][0][0][...]
        rawEmbedding = List<double>.from(outputTensor[0][0][0]);
        print('✅ Extracted ${rawEmbedding.length} values from 4D output');
        
      } else if (outputShape.length == 2) {
        // Shape: [1, 512]
        print('🔧 Using 2D output structure');
        final embeddingSize = outputShape.last;
        final outputTensor = List.generate(1, (i) => List.filled(embeddingSize, 0.0));
        
        print('🚀 Running model inference...');
        _interpreter!.run(inputTensor, outputTensor);
        stopwatch.stop();
        
        print('⏱️ Inference time: ${stopwatch.elapsedMilliseconds}ms');
        
        rawEmbedding = List<double>.from(outputTensor[0]);
        print('✅ Extracted ${rawEmbedding.length} values from 2D output');
        
      } else {
        print('❌ Unsupported output shape: $outputShape');
        print('   Expected: [1, 512] or [1, 1, 1, 512]');
        return null;
      }
      // ========================================================
      
      print('📏 Normalizing embedding...');
      final normalizedEmbedding = _normalizeEmbeddingEnhanced(rawEmbedding);
      
      print('✅ Embedding generated successfully: ${normalizedEmbedding.length} dimensions');
      
      return normalizedEmbedding;
      
    } catch (e, stackTrace) {
      print('❌ Embedding generation error: $e');
      print('Stack trace: $stackTrace');
      return null;
    }
  }

  static Future<Rect?> detectFaceEnhanced(File imageFile) async {
    final options = FaceDetectorOptions(
      enableContours: false,
      enableClassification: false,
      enableLandmarks: true,
      enableTracking: false,
      minFaceSize: MIN_FACE_SIZE,
      performanceMode: FaceDetectorMode.accurate,
    );
    
    final faceDetector = FaceDetector(options: options);
    final inputImage = InputImage.fromFile(imageFile);
    final faces = await faceDetector.processImage(inputImage);
    faceDetector.close();
    
    if (faces.isNotEmpty) {
      print('👤 Detected ${faces.length} faces');
      
      Face? bestFace;
      double bestScore = 0;
      
      for (Face face in faces) {
        double qualityScore = _calculateFaceQuality(face);
        
        if (qualityScore > bestScore) {
          bestScore = qualityScore;
          bestFace = face;
        }
      }
      
      if (bestFace != null) {
        print('✅ Selected best face with score: ${bestScore.toStringAsFixed(2)}');
        return bestFace.boundingBox;
      }
    }
    
    return null;
  }

  static double _calculateFaceQuality(Face face) {
    double score = 0;
    
    final faceArea = face.boundingBox.width * face.boundingBox.height;
    score += math.min(faceArea / 10000, 1.0) * 30;
    
    if (face.headEulerAngleY != null) {
      score += (90 - face.headEulerAngleY!.abs()) / 90 * 25;
    }
    if (face.headEulerAngleZ != null) {
      score += (90 - face.headEulerAngleZ!.abs()) / 90 * 25;
    }
    
    if (face.landmarks.isNotEmpty) {
      score += math.min(face.landmarks.length / 10, 1.0) * 20;
    }
    
    return score;
  }

  static Future<img.Image?> cropFaceEnhanced(File imageFile, Rect faceRect) async {
    try {
      final imageBytes = await imageFile.readAsBytes();
      final originalImage = img.decodeImage(imageBytes);
      if (originalImage == null) return null;
      
      final faceSize = math.max(faceRect.width, faceRect.height);
      final paddingRatio = _calculateOptimalPadding(faceSize);
      final padding = (faceSize * paddingRatio).toInt();
      
      final x = math.max(0, faceRect.left.toInt() - padding);
      final y = math.max(0, faceRect.top.toInt() - padding);
      final maxWidth = originalImage.width - x;
      final maxHeight = originalImage.height - y;
      final width = math.min(maxWidth, faceRect.width.toInt() + (padding * 2));
      final height = math.min(maxHeight, faceRect.height.toInt() + (padding * 2));
      
      if (width <= 0 || height <= 0) return null;
      
      var croppedImage = img.copyCrop(originalImage, x: x, y: y, width: width, height: height);
      
      final targetSize = math.max(croppedImage.width, croppedImage.height);
      final squareImage = img.Image(width: targetSize, height: targetSize);
      img.fill(squareImage, color: img.ColorRgb8(128, 128, 128));
      
      final offsetX = (targetSize - croppedImage.width) ~/ 2;
      final offsetY = (targetSize - croppedImage.height) ~/ 2;
      img.compositeImage(squareImage, croppedImage, dstX: offsetX, dstY: offsetY);
      
      return squareImage;
      
    } catch (e) {
      print('❌ Enhanced face cropping error: $e');
      return null;
    }
  }

  static double _calculateOptimalPadding(double faceSize) {
    if (faceSize < 100) return 0.5;
    if (faceSize < 200) return 0.35;
    if (faceSize < 400) return 0.25;
    return 0.15;
  }

  static List<double> _normalizeEmbeddingEnhanced(List<double> embedding) {
    double norm = 0.0;
    for (double value in embedding) {
      norm += value * value;
    }
    norm = math.sqrt(norm);
    
    if (norm == 0.0 || norm.isNaN || norm.isInfinite) {
      print('⚠️ Warning: Invalid norm value: $norm');
      return embedding;
    }
    
    final normalized = embedding.map((value) => value / norm).toList();
    
    double checkNorm = 0.0;
    for (double value in normalized) {
      if (value.isNaN || value.isInfinite) {
        print('⚠️ Warning: Invalid normalized value detected');
        return embedding;
      }
      checkNorm += value * value;
    }
    
    return normalized;
  }

  static double calculateSimilarity(List<double> embedding1, List<double> embedding2) {
    if (embedding1.length != embedding2.length) {
      throw ArgumentError('Embedding length mismatch: ${embedding1.length} vs ${embedding2.length}');
    }
    
    double dotProduct = 0.0;
    double norm1 = 0.0;
    double norm2 = 0.0;
    
    for (int i = 0; i < embedding1.length; i++) {
      dotProduct += embedding1[i] * embedding2[i];
      norm1 += embedding1[i] * embedding1[i];
      norm2 += embedding2[i] * embedding2[i];
    }
    
    norm1 = math.sqrt(norm1);
    norm2 = math.sqrt(norm2);
    
    if (norm1 == 0.0 || norm2 == 0.0) return 0.0;
    
    final similarity = dotProduct / (norm1 * norm2);
    return math.max(0.0, math.min(1.0, similarity));
  }

  // ============ الدالة الرئيسية للتعرف مع embeddings متعددة ============
  static Future<RecognitionResult?> recognizeFace(
    File imageFile, {
    double threshold = DEFAULT_THRESHOLD,
    String normalizationType = 'arcface',
    bool useAdaptiveThreshold = true,
  }) async {
    print('=== 🔍 Enhanced Face Recognition (Multi-Embedding) ===');
    print('📊 Using threshold: ${(threshold * 100).toStringAsFixed(1)}%, normalization: $normalizationType');
    
    final queryEmbedding = await generateEmbedding(imageFile, normalizationType: normalizationType);
    if (queryEmbedding == null) {
      print('❌ Failed to generate query embedding');
      return null;
    }
    
    if (_storedMultipleEmbeddings.isEmpty) {
      print('⚠️ No stored embeddings available');
      return RecognitionResult(personId: 'unknown', similarity: 0.0, isMatch: false);
    }
    
    String? bestMatchId;
    double highestSimilarity = -1.0;
    Map<String, double> personBestSimilarities = {};
    
    print('🔎 Comparing with ${_storedMultipleEmbeddings.length} persons...');
    
    // مقارنة مع كل embeddings لكل شخص
    for (var personEntry in _storedMultipleEmbeddings.entries) {
      String personId = personEntry.key;
      List<List<double>> personEmbeddings = personEntry.value;
      
      double personBestSimilarity = -1.0;
      
      // إيجاد أفضل تطابق من بين كل embeddings الشخص
      for (int i = 0; i < personEmbeddings.length; i++) {
        try {
          final similarity = calculateSimilarity(queryEmbedding, personEmbeddings[i]);
          
          if (similarity > personBestSimilarity) {
            personBestSimilarity = similarity;
          }
        } catch (e) {
          print('⚠️ Error comparing with $personId embedding $i: $e');
        }
      }
      
      personBestSimilarities[personId] = personBestSimilarity;
      print('  👤 $personId: ${(personBestSimilarity * 100).toStringAsFixed(1)}% (from ${personEmbeddings.length} embeddings)');
      
      if (personBestSimilarity > highestSimilarity) {
        highestSimilarity = personBestSimilarity;
        bestMatchId = personId;
      }
    }
    
    // Adaptive threshold
    double finalThreshold = threshold;
    if (useAdaptiveThreshold && personBestSimilarities.isNotEmpty) {
      var sortedSimilarities = personBestSimilarities.values.toList()..sort((a, b) => b.compareTo(a));
      
      if (sortedSimilarities.length > 1) {
        final secondHighest = sortedSimilarities[1];
        final gap = highestSimilarity - secondHighest;
        
        // إذا كان هناك فجوة كبيرة بين الأول والثاني
        if (gap > 0.15) {
          finalThreshold = math.min(threshold, highestSimilarity - 0.05);
          print('🎯 Adaptive threshold applied: ${(finalThreshold * 100).toStringAsFixed(1)}% (gap: ${(gap * 100).toStringAsFixed(1)}%)');
        }
      }
    }
    
    final isMatch = highestSimilarity >= finalThreshold;
    
    if (isMatch) {
      print('✅ MATCH FOUND: $bestMatchId (${(highestSimilarity * 100).toStringAsFixed(1)}%)');
    } else {
      print('❌ NO MATCH: Best was ${(highestSimilarity * 100).toStringAsFixed(1)}% < ${(finalThreshold * 100).toStringAsFixed(1)}%');
    }
    
    return RecognitionResult(
      personId: bestMatchId ?? 'unknown',
      similarity: highestSimilarity,
      isMatch: isMatch,
      threshold: finalThreshold,
    );
  }
  // ================================================================

  // ============ تخزين embedding جديد لشخص (يضيف للقائمة) ============
  static Future<bool> storeFaceEmbedding(
    String personId, 
    File imageFile, 
    {String normalizationType = 'arcface'}
  ) async {
    final embedding = await generateEmbedding(imageFile, normalizationType: normalizationType);
    if (embedding != null && embedding.isNotEmpty) {
      // إذا الشخص موجود، نضيف embedding جديد
      if (_storedMultipleEmbeddings.containsKey(personId)) {
        _storedMultipleEmbeddings[personId]!.add(embedding);
        print('✅ Added embedding #${_storedMultipleEmbeddings[personId]!.length} for $personId');
      } else {
        // إذا الشخص جديد، ننشئ قائمة جديدة
        _storedMultipleEmbeddings[personId] = [embedding];
        print('✅ Created new person $personId with first embedding');
      }
      
      print('📊 $personId now has ${_storedMultipleEmbeddings[personId]!.length} embeddings');
      return true;
    }
    print('❌ Failed to store embedding for $personId');
    return false;
  }
  // ==============================================================

  // ============ تحميل embeddings متعددة من Firestore ============
  static void loadMultipleEmbeddings(Map<String, List<List<double>>> embeddings) {
    _storedMultipleEmbeddings = Map.from(embeddings);
    int totalEmbeddings = 0;
    embeddings.forEach((personId, embList) {
      totalEmbeddings += embList.length;
      print('  👤 $personId: ${embList.length} embeddings');
    });
    print('✅ Loaded ${embeddings.length} persons with $totalEmbeddings total embeddings');
  }
  // ==============================================================

  // ============ إرجاع embeddings بصيغة Firestore ============
  static Map<String, dynamic> getStoredEmbeddings() {
    Map<String, dynamic> result = {};
    _storedMultipleEmbeddings.forEach((personId, embeddings) {
      result[personId] = embeddings; // قائمة من embeddings
    });
    print('📤 Exporting ${result.length} persons');
    return result;
  }
  // =========================================================

  // ============ حذف جميع embeddings لشخص ============
  static void removeFaceEmbedding(String personId) {
    final removed = _storedMultipleEmbeddings.remove(personId);
    if (removed != null) {
      print('🗑️ Removed $personId (${removed.length} embeddings)');
    } else {
      print('⚠️ Person $personId not found');
    }
  }
  // ==============================================

  // ============ مسح كل البيانات ============
  static void clearStoredEmbeddings() {
    final count = _storedMultipleEmbeddings.length;
    _storedMultipleEmbeddings.clear();
    print('🗑️ Cleared all $count persons');
  }
  // =======================================

  static void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _isInitialized = false;
    _storedMultipleEmbeddings.clear();
    print('🔌 Face recognition service disposed');
  }

  // ============ إحصائيات مفيدة ============
  static Map<String, dynamic> getStatistics() {
    int totalEmbeddings = 0;
    Map<String, int> embeddingCounts = {};
    
    _storedMultipleEmbeddings.forEach((personId, embeddings) {
      embeddingCounts[personId] = embeddings.length;
      totalEmbeddings += embeddings.length;
    });
    
    return {
      'total_persons': _storedMultipleEmbeddings.length,
      'total_embeddings': totalEmbeddings,
      'average_embeddings_per_person': _storedMultipleEmbeddings.isEmpty 
          ? 0 
          : (totalEmbeddings / _storedMultipleEmbeddings.length).toStringAsFixed(1),
      'embedding_counts': embeddingCounts,
    };
  }
  // =====================================

  static Future<Map<String, dynamic>> diagnoseModel() async {
    if (!_isInitialized) await initialize();
    
    final stats = getStatistics();
    
    return {
      'initialized': _isInitialized,
      'interpreter_available': _interpreter != null,
      'stored_persons': stats['total_persons'],
      'total_embeddings': stats['total_embeddings'],
      'input_shape': _interpreter?.getInputTensor(0).shape,
      'output_shape': _interpreter?.getOutputTensor(0).shape,
    };
  }
}

class RecognitionResult {
  final String personId;
  final double similarity;
  final bool isMatch;
  final double threshold;
  
  RecognitionResult({
    required this.personId,
    required this.similarity,
    required this.isMatch,
    this.threshold = 0.25,
  });
  
  @override
  String toString() {
    return 'RecognitionResult(personId: $personId, similarity: ${(similarity * 100).toStringAsFixed(1)}%, isMatch: $isMatch, threshold: ${(threshold * 100).toStringAsFixed(1)}%)';
  }
}