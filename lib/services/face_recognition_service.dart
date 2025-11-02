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

  // دعم embeddings متعددة لكل شخص (3-10 صور)
  static Map<String, List<List<double>>> _storedMultipleEmbeddings = {};

  // إعدادات النموذج (متغيرة حسب الموديل)
  static const int INPUT_SIZE = 112;
  static int EMBEDDING_SIZE = 512;

  // إعدادات محسّنة مطابقة لـ Colab
  static const double MIN_FACE_SIZE = 0.15;
  static const double DEFAULT_THRESHOLD = 0.35;

  /// تحديث حجم الـ embedding تلقائياً
  static void _updateEmbeddingSize(int newSize) {
    EMBEDDING_SIZE = newSize;
    print('📏 Updated EMBEDDING_SIZE to: $newSize');
  }

  /// تهيئة النظام
  static Future<bool> initialize() async {
    if (_isInitialized) return true;

    try {
      print('🚀 Loading face recognition model...');

      final modelPaths = [
        // ✅ ابدأ بالموديلات الأبسط أولاً
        'assets/models/1k3d68_float16.tflite',
        'assets/models/det_10g_simplified_float16.tflite',
        'assets/models/2d106det_float16.tflite',
        // 'assets/models/w600k_r50.tflite', // علّق على هذا مؤقتاً
        'assets/models/1k3d68_float32.tflite',
        'assets/models/2d106det_float32.tflite',
        'assets/models/det_10g_simplified_float32.tflite',
      ];

      for (String path in modelPaths) {
        try {
          _interpreter = await Interpreter.fromAsset(path);
          print('✅ Successfully loaded model from: $path');

          final inputDetails = _interpreter!.getInputTensor(0);
          final outputDetails = _interpreter!.getOutputTensor(0);
          print(
            '📊 Input shape: ${inputDetails.shape}, type: ${inputDetails.type}',
          );
          print(
            '📊 Output shape: ${outputDetails.shape}, type: ${outputDetails.type}',
          );

          // تحديث EMBEDDING_SIZE تلقائياً من الموديل
          if (outputDetails.shape.length == 4) {
            _updateEmbeddingSize(outputDetails.shape[3]);
          } else if (outputDetails.shape.length == 2) {
            _updateEmbeddingSize(outputDetails.shape[1]);
          } else if (outputDetails.shape.length == 1) {
            _updateEmbeddingSize(outputDetails.shape[0]);
          }

          // ✅ أضف هذا التحقق من Input Shape
          final expectedInputShape = inputDetails.shape;
          if (expectedInputShape[1] != INPUT_SIZE ||
              expectedInputShape[2] != INPUT_SIZE) {
            print(
              '⚠️ Model expects different input size: ${expectedInputShape[1]}x${expectedInputShape[2]}',
            );
            print(
              '⚠️ Current INPUT_SIZE is $INPUT_SIZE, model needs ${expectedInputShape[1]}',
            );
            // استمر مع الموديل التالي
            continue;
          }

          _isInitialized = true;
          return true;
        } catch (e) {
          print('⚠️ Failed to load $path: $e');
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

  /// تحسين الصورة - نسخة مستقرة وآمنة
  static img.Image _enhanceImage(img.Image image) {
    try {
      final gamma = 1.3;

      for (int y = 0; y < image.height; y++) {
        for (int x = 0; x < image.width; x++) {
          final pixel = image.getPixel(x, y);

          final r = (255.0 * math.pow(pixel.r / 255.0, 1.0 / gamma))
              .clamp(0, 255)
              .toInt();
          final g = (255.0 * math.pow(pixel.g / 255.0, 1.0 / gamma))
              .clamp(0, 255)
              .toInt();
          final b = (255.0 * math.pow(pixel.b / 255.0, 1.0 / gamma))
              .clamp(0, 255)
              .toInt();

          image.setPixel(x, y, img.ColorRgb8(r, g, b));
        }
      }

      image = img.adjustColor(image, contrast: 1.15);

      print('✅ Image enhancement completed');
      return image;
    } catch (e) {
      print('⚠️ Enhancement failed: $e');
      return image;
    }
  }

  /// معالجة الصورة - نسخة محسّنة وآمنة
  static Float32List preprocessImage(img.Image faceImage) {
    try {
      print('🎨 Starting preprocessing...');

      var processedImage = _enhanceImage(faceImage);

      processedImage = img.copyResize(
        processedImage,
        width: INPUT_SIZE,
        height: INPUT_SIZE,
        interpolation: img.Interpolation.cubic,
      );

      final input = Float32List(INPUT_SIZE * INPUT_SIZE * 3);
      int pixelIndex = 0;

      for (int y = 0; y < INPUT_SIZE; y++) {
        for (int x = 0; x < INPUT_SIZE; x++) {
          final pixel = processedImage.getPixel(x, y);

          input[pixelIndex] = (pixel.r / 127.5) - 1.0;
          input[pixelIndex + 1] = (pixel.g / 127.5) - 1.0;
          input[pixelIndex + 2] = (pixel.b / 127.5) - 1.0;

          pixelIndex += 3;
        }
      }

      print('✅ Preprocessing completed');
      return input;
    } catch (e) {
      print('❌ Preprocessing error: $e');
      rethrow;
    }
  }

  /// توليد embedding مع معالجة أفضل للأخطاء
  static Future<List<double>?> generateEmbedding(File imageFile) async {
    if (!_isInitialized) {
      print('⚠️ Model not initialized');
      final initialized = await initialize();
      if (!initialized) {
        print('❌ Failed to initialize');
        return null;
      }
    }

    try {
      if (!await imageFile.exists()) {
        print('❌ Image file not found: ${imageFile.path}');
        return null;
      }

      print('📸 Reading image...');
      final imageBytes = await imageFile.readAsBytes();
      final originalImage = img.decodeImage(imageBytes);

      if (originalImage == null) {
        print('❌ Failed to decode image');
        return null;
      }

      print('✅ Image decoded: ${originalImage.width}x${originalImage.height}');

      print('🔍 Detecting face...');
      final faceRect = await detectFaceEnhanced(imageFile);

      if (faceRect == null) {
        print('❌ No face detected');
        return null;
      }

      print('✅ Face detected');

      print('✂️ Cropping face...');
      final croppedFace = await cropFaceEnhanced(imageFile, faceRect);

      if (croppedFace == null) {
        print('❌ Failed to crop face');
        return null;
      }

      print('✅ Face cropped');

      final input = preprocessImage(croppedFace);
      final inputTensor = input.reshape([1, INPUT_SIZE, INPUT_SIZE, 3]);

      final outputShape = _interpreter!.getOutputTensor(0).shape;
      print('📊 Output shape: $outputShape');

      List<double> rawEmbedding;
      final stopwatch = Stopwatch()..start();

      if (outputShape.length == 4) {
        print('🔧 Using 4D output');
        final embeddingSize = outputShape[3];
        final outputTensor = List.generate(
          outputShape[0],
          (i) => List.generate(
            outputShape[1],
            (j) => List.generate(
              outputShape[2],
              (k) => List.filled(embeddingSize, 0.0),
            ),
          ),
        );

        _interpreter!.run(inputTensor, outputTensor);
        stopwatch.stop();

        rawEmbedding = List<double>.from(outputTensor[0][0][0]);
      } else if (outputShape.length == 2) {
        print('🔧 Using 2D output');
        final embeddingSize = outputShape[1];
        final outputTensor = List.generate(
          1,
          (i) => List.filled(embeddingSize, 0.0),
        );

        _interpreter!.run(inputTensor, outputTensor);
        stopwatch.stop();

        rawEmbedding = List<double>.from(outputTensor[0]);
      } else if (outputShape.length == 1) {
        print('🔧 Using 1D output');
        final embeddingSize = outputShape[0];
        final outputTensor = List.filled(embeddingSize, 0.0);

        _interpreter!.run(inputTensor, outputTensor);
        stopwatch.stop();

        rawEmbedding = List<double>.from(outputTensor);
      } else {
        print('❌ Unsupported output shape: $outputShape');
        return null;
      }

      print('⏱️ Inference: ${stopwatch.elapsedMilliseconds}ms');

      print('📏 Normalizing...');
      final normalizedEmbedding = _normalizeEmbeddingEnhanced(rawEmbedding);

      if (normalizedEmbedding.isEmpty) {
        print('❌ Normalization failed');
        return null;
      }

      print('✅ Embedding generated: ${normalizedEmbedding.length}D');
      return normalizedEmbedding;
    } catch (e, stackTrace) {
      print('❌ Error: $e');
      print('Stack: $stackTrace');
      return null;
    }
  }

  /// كشف الوجه في الصورة
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
        print('✅ Best face score: ${bestScore.toStringAsFixed(2)}');
        return bestFace.boundingBox;
      }
    }

    return null;
  }

  /// حساب جودة الوجه
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

  /// قص الوجه من الصورة
  static Future<img.Image?> cropFaceEnhanced(
    File imageFile,
    Rect faceRect,
  ) async {
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
      final height = math.min(
        maxHeight,
        faceRect.height.toInt() + (padding * 2),
      );

      if (width <= 0 || height <= 0) return null;

      var croppedImage = img.copyCrop(
        originalImage,
        x: x,
        y: y,
        width: width,
        height: height,
      );

      final targetSize = math.max(croppedImage.width, croppedImage.height);
      final squareImage = img.Image(width: targetSize, height: targetSize);
      img.fill(squareImage, color: img.ColorRgb8(128, 128, 128));

      final offsetX = (targetSize - croppedImage.width) ~/ 2;
      final offsetY = (targetSize - croppedImage.height) ~/ 2;
      img.compositeImage(
        squareImage,
        croppedImage,
        dstX: offsetX,
        dstY: offsetY,
      );

      return squareImage;
    } catch (e) {
      print('❌ Crop error: $e');
      return null;
    }
  }

  /// حساب padding مثالي
  static double _calculateOptimalPadding(double faceSize) {
    if (faceSize < 100) return 0.5;
    if (faceSize < 200) return 0.35;
    if (faceSize < 400) return 0.25;
    return 0.15;
  }

  /// تطبيع embedding (L2 Normalization)
  static List<double> _normalizeEmbeddingEnhanced(List<double> embedding) {
    double norm = 0.0;
    for (double value in embedding) {
      norm += value * value;
    }
    norm = math.sqrt(norm);

    if (norm == 0.0 || norm.isNaN || norm.isInfinite) {
      print('⚠️ Invalid norm: $norm');
      return embedding;
    }

    final normalized = embedding.map((value) => value / norm).toList();

    for (double value in normalized) {
      if (value.isNaN || value.isInfinite) {
        print('⚠️ Invalid normalized value');
        return embedding;
      }
    }

    return normalized;
  }

  /// حساب التشابه (Cosine Similarity)
  static double calculateSimilarity(
    List<double> embedding1,
    List<double> embedding2,
  ) {
    if (embedding1.length != embedding2.length) {
      throw ArgumentError(
        'Embedding length mismatch: ${embedding1.length} vs ${embedding2.length}',
      );
    }

    double dotProduct = 0.0;

    for (int i = 0; i < embedding1.length; i++) {
      dotProduct += embedding1[i] * embedding2[i];
    }

    return math.max(0.0, math.min(1.0, dotProduct));
  }

  /// التعرف على وجه
  static Future<RecognitionResult?> recognizeFace(
    File imageFile, {
    double threshold = DEFAULT_THRESHOLD,
    bool useAdaptiveThreshold = true,
  }) async {
    print('=== 🔍 Face Recognition ===');
    print('📊 Threshold: ${(threshold * 100).toStringAsFixed(1)}%');

    final queryEmbedding = await generateEmbedding(imageFile);
    if (queryEmbedding == null) {
      print('❌ Failed to generate embedding');
      return null;
    }

    if (_storedMultipleEmbeddings.isEmpty) {
      print('⚠️ No stored embeddings');
      return RecognitionResult(
        personId: 'unknown',
        similarity: 0.0,
        isMatch: false,
      );
    }

    String? bestMatchId;
    double highestSimilarity = -1.0;
    Map<String, double> personBestSimilarities = {};

    print('🔎 Comparing with ${_storedMultipleEmbeddings.length} persons...');

    for (var personEntry in _storedMultipleEmbeddings.entries) {
      String personId = personEntry.key;
      List<List<double>> personEmbeddings = personEntry.value;

      List<double> similarities = [];
      for (int i = 0; i < personEmbeddings.length; i++) {
        try {
          final similarity = calculateSimilarity(
            queryEmbedding,
            personEmbeddings[i],
          );
          similarities.add(similarity);
        } catch (e) {
          print('⚠️ Error comparing with $personId: $e');
        }
      }

      double maxSimilarity = similarities.isEmpty
          ? 0.0
          : similarities.reduce((a, b) => a > b ? a : b);
      personBestSimilarities[personId] = maxSimilarity;

      print('  👤 $personId: ${(maxSimilarity * 100).toStringAsFixed(1)}%');

      if (maxSimilarity > highestSimilarity) {
        highestSimilarity = maxSimilarity;
        bestMatchId = personId;
      }
    }

    double finalThreshold = threshold;
    if (useAdaptiveThreshold && personBestSimilarities.isNotEmpty) {
      var sortedSimilarities = personBestSimilarities.values.toList()
        ..sort((a, b) => b.compareTo(a));

      if (sortedSimilarities.length > 1) {
        final secondHighest = sortedSimilarities[1];
        final gap = highestSimilarity - secondHighest;

        if (gap > 0.15) {
          finalThreshold = math.min(threshold, highestSimilarity - 0.05);
          print(
            '🎯 Adaptive threshold: ${(finalThreshold * 100).toStringAsFixed(1)}%',
          );
        }
      }
    }

    final isMatch = highestSimilarity >= finalThreshold;

    if (isMatch) {
      print(
        '✅ MATCH: $bestMatchId (${(highestSimilarity * 100).toStringAsFixed(1)}%)',
      );
    } else {
      print(
        '❌ NO MATCH: ${(highestSimilarity * 100).toStringAsFixed(1)}% < ${(finalThreshold * 100).toStringAsFixed(1)}%',
      );
    }

    return RecognitionResult(
      personId: bestMatchId ?? 'unknown',
      similarity: highestSimilarity,
      isMatch: isMatch,
      threshold: finalThreshold,
    );
  }

  /// تخزين embedding
  static Future<bool> storeFaceEmbedding(
    String personId,
    File imageFile,
  ) async {
    final embedding = await generateEmbedding(imageFile);
    if (embedding != null && embedding.isNotEmpty) {
      if (_storedMultipleEmbeddings.containsKey(personId)) {
        _storedMultipleEmbeddings[personId]!.add(embedding);
        print(
          '✅ Added embedding #${_storedMultipleEmbeddings[personId]!.length} for $personId',
        );
      } else {
        _storedMultipleEmbeddings[personId] = [embedding];
        print('✅ Created new person $personId');
      }

      print(
        '📊 $personId now has ${_storedMultipleEmbeddings[personId]!.length} embeddings',
      );
      return true;
    }
    print('❌ Failed to store embedding');
    return false;
  }

  /// تحميل embeddings من Firestore
  static void loadMultipleEmbeddings(
    Map<String, List<List<double>>> embeddings,
  ) {
    _storedMultipleEmbeddings = Map.from(embeddings);
    int totalEmbeddings = 0;
    embeddings.forEach((personId, embList) {
      totalEmbeddings += embList.length;
      print('  👤 $personId: ${embList.length} embeddings');
    });
    print(
      '✅ Loaded ${embeddings.length} persons with $totalEmbeddings embeddings',
    );
  }

  /// إرجاع embeddings
  static Map<String, dynamic> getStoredEmbeddings() {
    Map<String, dynamic> result = {};
    _storedMultipleEmbeddings.forEach((personId, embeddings) {
      result[personId] = embeddings;
    });
    return result;
  }

  /// حذف embeddings
  static void removeFaceEmbedding(String personId) {
    final removed = _storedMultipleEmbeddings.remove(personId);
    if (removed != null) {
      print('🗑️ Removed $personId (${removed.length} embeddings)');
    }
  }

  /// مسح كل البيانات
  static void clearStoredEmbeddings() {
    final count = _storedMultipleEmbeddings.length;
    _storedMultipleEmbeddings.clear();
    print('🗑️ Cleared all $count persons');
  }

  /// تنظيف الموارد
  static void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _isInitialized = false;
    _storedMultipleEmbeddings.clear();
    print('🔌 Service disposed');
  }

  /// إحصائيات
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
          : (totalEmbeddings / _storedMultipleEmbeddings.length)
                .toStringAsFixed(1),
      'embedding_counts': embeddingCounts,
      'current_embedding_size': EMBEDDING_SIZE,
    };
  }
}

/// نتيجة عملية التعرف
class RecognitionResult {
  final String personId;
  final double similarity;
  final bool isMatch;
  final double threshold;

  RecognitionResult({
    required this.personId,
    required this.similarity,
    required this.isMatch,
    this.threshold = 0.35,
  });

  @override
  String toString() {
    return 'RecognitionResult(personId: $personId, similarity: ${(similarity * 100).toStringAsFixed(1)}%, isMatch: $isMatch, threshold: ${(threshold * 100).toStringAsFixed(1)}%)';
  }
}
