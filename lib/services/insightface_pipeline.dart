import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;
import 'dart:ui';

class InsightFacePipeline {
  // الموديلات الثلاثة
  static Interpreter? _detectionModel;
  static Interpreter? _landmarkModel;
  static Interpreter? _recognitionModel;
  static bool _isInitialized = false;

  // إعدادات
  static const int DETECTION_INPUT_SIZE = 640;
  static const int LANDMARK_INPUT_SIZE = 192;
  static const int RECOGNITION_INPUT_SIZE = 112;
  static int EMBEDDING_SIZE = 512;

  static Map<String, List<List<double>>> _storedMultipleEmbeddings = {};
  static const double DEFAULT_THRESHOLD = 0.35;

  /// تهيئة الموديلات الثلاثة
  static Future<bool> initialize() async {
    if (_isInitialized) return true;

    try {
      print('🚀 Loading InsightFace Pipeline (3 models)...');

      // 1️⃣ تحميل موديل Face Detection
      print('📦 Loading detection model...');
      try {
        _detectionModel = await Interpreter.fromAsset(
          'assets/models/det_10g_simplified_float16.tflite',
          options: InterpreterOptions()..threads = 4,
        );
        final inputShape = _detectionModel!.getInputTensor(0).shape;
        final outputShape = _detectionModel!.getOutputTensor(0).shape;
        print('✅ Detection model loaded');
        print('   Input shape: $inputShape');
        print('   Output shape: $outputShape');
      } catch (e) {
        print('❌ Detection model failed: $e');
        return false;
      }

      // 2️⃣ تحميل موديل Landmarks
      print('📦 Loading landmark model...');
      try {
        _landmarkModel = await Interpreter.fromAsset(
          'assets/models/2d106det_float16.tflite',
          options: InterpreterOptions()..threads = 4,
        );
        final inputShape = _landmarkModel!.getInputTensor(0).shape;
        final outputShape = _landmarkModel!.getOutputTensor(0).shape;
        print('✅ Landmark model loaded');
        print('   Input shape: $inputShape');
        print('   Output shape: $outputShape');
      } catch (e) {
        print('❌ Landmark model failed: $e');
        return false;
      }

      // 3️⃣ تحميل موديل Recognition
      print('📦 Loading recognition model...');
      try {
        _recognitionModel = await Interpreter.fromAsset(
          'assets/models/w600k_r50_float16.tflite',
          options: InterpreterOptions()..threads = 4,
        );
        final inputShape = _recognitionModel!.getInputTensor(0).shape;
        final outputShape = _recognitionModel!.getOutputTensor(0).shape;
        print('✅ Recognition model loaded');
        print('   Input shape: $inputShape');
        print('   Output shape: $outputShape');

        if (outputShape.length == 2) {
          EMBEDDING_SIZE = outputShape[1];
        } else if (outputShape.length == 4) {
          EMBEDDING_SIZE = outputShape[3];
        }
        print('   Embedding size: $EMBEDDING_SIZE');
      } catch (e) {
        print('❌ Recognition model failed: $e');
        return false;
      }

      _isInitialized = true;
      print('✅ InsightFace Pipeline initialized successfully!');
      print('=' * 50);
      return true;
    } catch (e) {
      print('❌ Pipeline initialization error: $e');
      return false;
    }
  }

  /// كشف وجه واحد
  static Future<Rect?> detectFace(File imageFile) async {
    final faces = await detectFaces(imageFile);
    if (faces == null || faces.isEmpty) return null;
    return faces[0];
  }

  /// Face Detection
  static Future<List<Rect>?> detectFaces(File imageFile, {bool useFallback = true}) async {
    try {
      print('🔍 Stage 1: Face Detection');
      
      if (_detectionModel == null) {
        print('❌ Detection model not initialized');
        if (useFallback) {
          print('🔄 Model null, using fallback immediately');
          return await _createFallbackFace(imageFile);
        }
        await initialize();
        if (_detectionModel == null) {
          if (useFallback) {
            return await _createFallbackFace(imageFile);
          }
          return null;
        }
      }

      final imageBytes = await imageFile.readAsBytes();
      final originalImage = img.decodeImage(imageBytes);
      if (originalImage == null) {
        print('❌ Failed to decode image');
        if (useFallback) {
          return await _createFallbackFace(imageFile);
        }
        return null;
      }

      print('📐 Original image size: ${originalImage.width}x${originalImage.height}');

      final resized = img.copyResize(
        originalImage,
        width: DETECTION_INPUT_SIZE,
        height: DETECTION_INPUT_SIZE,
        interpolation: img.Interpolation.cubic,
      );

      final input = _imageToFloat32List(resized, DETECTION_INPUT_SIZE);
      final inputTensor = input.reshape([1, DETECTION_INPUT_SIZE, DETECTION_INPUT_SIZE, 3]);

      final outputShape = _detectionModel?.getOutputTensor(0).shape;
      if (outputShape == null) {
        print('❌ Cannot get output tensor shape');
        if (useFallback) {
          return await _createFallbackFace(imageFile);
        }
        return null;
      }
      print('📊 Detection output shape: $outputShape');

      dynamic output;
      if (outputShape.length == 4) {
        output = List.generate(
          outputShape[0],
          (i) => List.generate(
            outputShape[1],
            (j) => List.generate(
              outputShape[2],
              (k) => List.filled(outputShape[3], 0.0),
            ),
          ),
        );
      } else if (outputShape.length == 3) {
        output = List.generate(
          outputShape[0],
          (i) => List.generate(
            outputShape[1],
            (j) => List.filled(outputShape[2], 0.0),
          ),
        );
      } else if (outputShape.length == 2) {
        output = List.generate(
          outputShape[0],
          (i) => List.filled(outputShape[1], 0.0),
        );
      } else {
        print('❌ Unsupported detection output shape: $outputShape');
        if (useFallback) {
          return await _createFallbackFace(imageFile);
        }
        return null;
      }

      try {
        _detectionModel?.run(inputTensor, output);
      } catch (e) {
        print('❌ Model run error: $e');
        if (useFallback) {
          return await _createFallbackFace(imageFile);
        }
        return null;
      }
      print('✅ Model inference completed');

      List<Rect> faces = _parseFaceDetections(
        output,
        originalImage.width,
        originalImage.height,
        outputShape,
      );

      if (faces.isEmpty) {
        print('⚠️ No faces found after parsing');
        if (useFallback) {
          print('🔄 Using FALLBACK: treating whole image as face');
          final width = originalImage.width.toDouble();
          final height = originalImage.height.toDouble();
          final padding = 0.05;
          final paddedWidth = width * (1.0 - padding * 2);
          final paddedHeight = height * (1.0 - padding * 2);
          final paddedLeft = width * padding;
          final paddedTop = height * padding;
          
          faces.add(Rect.fromLTWH(paddedLeft, paddedTop, paddedWidth, paddedHeight));
          print('✅ Fallback face region: ${paddedWidth.toInt()}x${paddedHeight.toInt()}');
        }
      }

      print('✅ Detected ${faces.length} face(s)');
      return faces;
    } catch (e, stackTrace) {
      print('❌ Face detection error: $e');
      print('Stack trace: $stackTrace');
      if (useFallback) {
        return await _createFallbackFace(imageFile);
      }
      return null;
    }
  }

  /// قص الوجه
  static Future<img.Image?> cropFace(File imageFile, Rect faceRect) async {
    try {
      final imageBytes = await imageFile.readAsBytes();
      final originalImage = img.decodeImage(imageBytes);
      if (originalImage == null) {
        print('❌ Failed to decode image for cropping');
        return null;
      }

      final x = math.max(0, math.min(faceRect.left.toInt(), originalImage.width - 1));
      final y = math.max(0, math.min(faceRect.top.toInt(), originalImage.height - 1));
      final maxWidth = originalImage.width - x;
      final maxHeight = originalImage.height - y;
      final width = math.max(1, math.min(faceRect.width.toInt(), maxWidth));
      final height = math.max(1, math.min(faceRect.height.toInt(), maxHeight));

      print('📐 Cropping: x=$x, y=$y, w=$width, h=$height');

      if (width <= 0 || height <= 0) {
        print('❌ Invalid crop dimensions');
        return null;
      }

      final croppedFace = img.copyCrop(originalImage, x: x, y: y, width: width, height: height);
      print('✅ Face cropped: ${croppedFace.width}x${croppedFace.height}');
      return croppedFace;
    } catch (e, stackTrace) {
      print('❌ Crop face error: $e');
      print('Stack trace: $stackTrace');
      return null;
    }
  }

  /// Landmark Detection
  static Future<List<Offset>?> detectLandmarks(img.Image faceImage) async {
    try {
      print('📍 Stage 2: Landmark Detection');
      
      if (_landmarkModel == null) {
        print('❌ Landmark model not initialized');
        return null;
      }

      final resized = img.copyResize(faceImage, width: LANDMARK_INPUT_SIZE, height: LANDMARK_INPUT_SIZE, interpolation: img.Interpolation.cubic);
      final input = _imageToFloat32List(resized, LANDMARK_INPUT_SIZE);
      final inputTensor = input.reshape([1, LANDMARK_INPUT_SIZE, LANDMARK_INPUT_SIZE, 3]);

      final outputShape = _landmarkModel?.getOutputTensor(0).shape;
      if (outputShape == null) {
        print('❌ Cannot get landmark output tensor shape');
        return null;
      }

      List<double> output;
      if (outputShape.length == 2) {
        final outputTensor = List.generate(1, (i) => List.filled(outputShape[1], 0.0));
        try {
          _landmarkModel?.run(inputTensor, outputTensor);
        } catch (e) {
          print('❌ Landmark model run error: $e');
          return null;
        }
        output = outputTensor[0];
      } else {
        final outputTensor = List.filled(outputShape.reduce((a, b) => a * b), 0.0);
        try {
          _landmarkModel?.run(inputTensor, outputTensor);
        } catch (e) {
          print('❌ Landmark model run error: $e');
          return null;
        }
        output = outputTensor;
      }

      List<Offset> landmarks = [];
      for (int i = 0; i < output.length; i += 2) {
        landmarks.add(Offset(output[i], output[i + 1]));
      }

      print('✅ Detected ${landmarks.length} landmarks');
      return landmarks;
    } catch (e) {
      print('❌ Landmark detection error: $e');
      return null;
    }
  }

  /// Face Recognition
  static Future<List<double>?> generateEmbedding(img.Image alignedFace) async {
    try {
      print('🎯 Stage 3: Face Recognition');
      
      if (_recognitionModel == null) {
        print('❌ Recognition model not initialized');
        return null;
      }

      final resized = img.copyResize(alignedFace, width: RECOGNITION_INPUT_SIZE, height: RECOGNITION_INPUT_SIZE, interpolation: img.Interpolation.cubic);
      final input = _imageToFloat32List(resized, RECOGNITION_INPUT_SIZE);
      final inputTensor = input.reshape([1, RECOGNITION_INPUT_SIZE, RECOGNITION_INPUT_SIZE, 3]);

      final outputShape = _recognitionModel?.getOutputTensor(0).shape;
      if (outputShape == null) {
        print('❌ Cannot get recognition output tensor shape');
        return null;
      }
      print('📊 Recognition output: $outputShape');

      List<double> rawEmbedding;
      if (outputShape.length == 4) {
        final output = List.generate(outputShape[0], (i) => List.generate(outputShape[1], (j) => List.generate(outputShape[2], (k) => List.filled(outputShape[3], 0.0))));
        try {
          _recognitionModel?.run(inputTensor, output);
        } catch (e) {
          print('❌ Recognition model run error: $e');
          return null;
        }
        rawEmbedding = List<double>.from(output[0][0][0]);
      } else if (outputShape.length == 2) {
        final output = List.generate(1, (i) => List.filled(outputShape[1], 0.0));
        try {
          _recognitionModel?.run(inputTensor, output);
        } catch (e) {
          print('❌ Recognition model run error: $e');
          return null;
        }
        rawEmbedding = List<double>.from(output[0]);
      } else {
        print('❌ Unsupported output shape');
        return null;
      }

      final normalized = _normalizeEmbedding(rawEmbedding);
      print('✅ Embedding generated: ${normalized.length}D');
      return normalized;
    } catch (e) {
      print('❌ Recognition error: $e');
      return null;
    }
  }

  /// Pipeline كاملة
  static Future<List<double>?> processImageFull(File imageFile, {bool skipDetection = true}) async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      print('=== 🚀 InsightFace Full Pipeline ===');
      
      List<Rect> faces;
      
      if (skipDetection) {
        print('⚡ SKIP DETECTION MODE: Using full image (default)');
        faces = await _createFallbackFace(imageFile);
        if (faces.isEmpty) {
          print('❌ Failed to create fallback face');
          return null;
        }
      } else {
        print('🔍 Using Detection Mode');
        final detectedFaces = await detectFaces(imageFile, useFallback: true);
        if (detectedFaces == null || detectedFaces.isEmpty) {
          print('❌ No faces detected');
          return null;
        }
        faces = detectedFaces;
      }

      final faceRect = faces[0];
      print('📦 Using face: ${faceRect.width.toInt()}x${faceRect.height.toInt()} at (${faceRect.left.toInt()}, ${faceRect.top.toInt()})');

      final croppedFace = await cropFace(imageFile, faceRect);
      if (croppedFace == null) {
        print('❌ Failed to crop face');
        return null;
      }

      final landmarks = await detectLandmarks(croppedFace);
      if (landmarks == null) {
        print('⚠️ Landmarks not detected, proceeding without alignment');
      }

      final alignedFace = landmarks != null ? _alignFace(croppedFace, landmarks) : croppedFace;

      final embedding = await generateEmbedding(alignedFace);
      if (embedding != null) {
        print('✅ Full pipeline completed successfully!');
      }

      return embedding;
    } catch (e, stackTrace) {
      print('❌ Pipeline error: $e');
      print('Stack trace: $stackTrace');
      return null;
    }
  }

  /// محاذاة الوجه
  static img.Image _alignFace(img.Image face, List<Offset> landmarks) {
    return face;
  }

  /// إنشاء fallback face
  static Future<List<Rect>> _createFallbackFace(File imageFile) async {
    try {
      print('🔄 Creating fallback face from full image...');
      final imageBytes = await imageFile.readAsBytes();
      final originalImage = img.decodeImage(imageBytes);
      
      if (originalImage == null) {
        print('❌ Failed to decode image in fallback');
        return [];
      }
      
      final width = originalImage.width.toDouble();
      final height = originalImage.height.toDouble();
      print('📐 Image size: ${width.toInt()}x${height.toInt()}');
      
      final padding = 0.05;
      final paddedWidth = width * (1.0 - padding * 2);
      final paddedHeight = height * (1.0 - padding * 2);
      final paddedLeft = width * padding;
      final paddedTop = height * padding;
      
      final rect = Rect.fromLTWH(paddedLeft, paddedTop, paddedWidth, paddedHeight);
      print('✅ Fallback face created: ${paddedWidth.toInt()}x${paddedHeight.toInt()} at (${paddedLeft.toInt()}, ${paddedTop.toInt()})');
      
      return [rect];
    } catch (e, stackTrace) {
      print('❌ Fallback face creation error: $e');
      print('Stack trace: $stackTrace');
      return [];
    }
  }

  /// تحويل صورة إلى Float32List
  static Float32List _imageToFloat32List(img.Image image, int size) {
    final input = Float32List(size * size * 3);
    int pixelIndex = 0;
    for (int y = 0; y < size; y++) {
      for (int x = 0; x < size; x++) {
        final pixel = image.getPixel(x, y);
        input[pixelIndex] = (pixel.r / 127.5) - 1.0;
        input[pixelIndex + 1] = (pixel.g / 127.5) - 1.0;
        input[pixelIndex + 2] = (pixel.b / 127.5) - 1.0;
        pixelIndex += 3;
      }
    }
    return input;
  }

  /// استخراج bounding boxes
  static List<Rect> _parseFaceDetections(dynamic output, int imgWidth, int imgHeight, List<int> outputShape) {
    List<Rect> faces = [];
    try {
      print('🔍 Parsing detections...');
      print('📊 Output shape: $outputShape');

      List<List<double>> detections = [];
      if (outputShape.length == 3) {
        final batchOutput = output as List;
        if (batchOutput.isEmpty) return faces;
        detections = List<List<double>>.from(batchOutput[0].map((det) => List<double>.from(det)));
      } else if (outputShape.length == 2) {
        detections = List<List<double>>.from(output.map((det) => List<double>.from(det)));
      } else {
        return faces;
      }

      if (detections.isEmpty) return faces;

      const double confidenceThreshold = 0.4;
      int validDetections = 0;

      for (int i = 0; i < detections.length; i++) {
        final detection = detections[i];
        if (detection.length < 3) continue;

        bool hasInvalidValues = detection.any((val) => val == null || val.isNaN || val.isInfinite);
        if (hasInvalidValues) continue;

        double score;
        double x1, y1, x2, y2;

        if (detection.length >= 5) {
          if (detection[0] >= 0 && detection[0] <= 1) {
            score = detection[0];
            x1 = detection[1];
            y1 = detection[2];
            x2 = detection[3];
            y2 = detection[4];
          } else if (detection[4] >= 0 && detection[4] <= 1) {
            x1 = detection[0];
            y1 = detection[1];
            x2 = detection[2];
            y2 = detection[3];
            score = detection[4];
          } else {
            x1 = detection[0];
            y1 = detection[1];
            x2 = x1 + detection[2];
            y2 = y1 + detection[3];
            score = detection.length > 4 ? detection[4] : 0.9;
          }
        } else if (detection.length == 3) {
          score = 0.9;
          x1 = detection[0];
          y1 = detection[1];
          x2 = detection[0] + detection[2];
          y2 = detection[1] + detection[2];
        } else {
          continue;
        }

        if (score < confidenceThreshold) continue;

        if (x1 <= 1.0 && y1 <= 1.0 && x2 <= 1.0 && y2 <= 1.0) {
          x1 *= imgWidth;
          y1 *= imgHeight;
          x2 *= imgWidth;
          y2 *= imgHeight;
        }

        final width = (x2 - x1).abs();
        final height = (y2 - y1).abs();
        if (width <= 0 || height <= 0) continue;

        final left = math.max(0.0, math.min(x1, x2));
        final top = math.max(0.0, math.min(y1, y2));
        final right = math.max(x1, x2);
        final bottom = math.max(y1, y2);

        final clippedLeft = math.max(0.0, math.min(left, imgWidth.toDouble()));
        final clippedTop = math.max(0.0, math.min(top, imgHeight.toDouble()));
        final clippedRight = math.max(0.0, math.min(right, imgWidth.toDouble()));
        final clippedBottom = math.max(0.0, math.min(bottom, imgHeight.toDouble()));

        final validWidth = clippedRight - clippedLeft;
        final validHeight = clippedBottom - clippedTop;

        if (validWidth > 20 && validHeight > 20) {
          faces.add(Rect.fromLTRB(clippedLeft, clippedTop, clippedRight, clippedBottom));
          validDetections++;
        }
      }

      if (faces.length > 1) {
        faces.sort((a, b) {
          final areaA = a.width * a.height;
          final areaB = b.width * b.height;
          return areaB.compareTo(areaA);
        });
      }
    } catch (e) {
      print('❌ Error parsing detections: $e');
    }
    return faces;
  }

  /// L2 Normalization
  static List<double> _normalizeEmbedding(List<double> embedding) {
    double norm = 0.0;
    for (double value in embedding) {
      norm += value * value;
    }
    norm = math.sqrt(norm);
    if (norm == 0.0 || norm.isNaN || norm.isInfinite) return embedding;
    return embedding.map((value) => value / norm).toList();
  }

  /// حساب التشابه
  static double calculateSimilarity(List<double> emb1, List<double> emb2) {
    if (emb1.length != emb2.length) return 0.0;
    double dotProduct = 0.0;
    for (int i = 0; i < emb1.length; i++) {
      dotProduct += emb1[i] * emb2[i];
    }
    return math.max(0.0, math.min(1.0, dotProduct));
  }

  /// تخزين embedding
  static Future<bool> storeFaceEmbedding(String personId, File imageFile, {bool skipDetection = true}) async {
    print('💾 Storing embedding for: $personId (skipDetection: $skipDetection)');
    final embedding = await processImageFull(imageFile, skipDetection: skipDetection);
    if (embedding != null && embedding.isNotEmpty) {
      if (_storedMultipleEmbeddings.containsKey(personId)) {
        _storedMultipleEmbeddings[personId]!.add(embedding);
      } else {
        _storedMultipleEmbeddings[personId] = [embedding];
      }
      print('✅ Stored embedding for $personId (${_storedMultipleEmbeddings[personId]!.length} total)');
      return true;
    }
    print('❌ Failed to store embedding for $personId');
    return false;
  }

  /// التعرف على وجه
  static Future<RecognitionResult?> recognizeFace(File imageFile, {double threshold = DEFAULT_THRESHOLD, bool skipDetection = true}) async {
    print('🔍 Recognizing face (skipDetection: $skipDetection)');
    final queryEmbedding = await processImageFull(imageFile, skipDetection: skipDetection);
    if (queryEmbedding == null) return null;

    if (_storedMultipleEmbeddings.isEmpty) {
      return RecognitionResult(personId: 'unknown', similarity: 0.0, isMatch: false);
    }

    String? bestMatchId;
    double highestSimilarity = -1.0;

    for (var entry in _storedMultipleEmbeddings.entries) {
      for (var embedding in entry.value) {
        final similarity = calculateSimilarity(queryEmbedding, embedding);
        if (similarity > highestSimilarity) {
          highestSimilarity = similarity;
          bestMatchId = entry.key;
        }
      }
    }

    final isMatch = highestSimilarity >= threshold;
    return RecognitionResult(personId: bestMatchId ?? 'unknown', similarity: highestSimilarity, isMatch: isMatch, threshold: threshold);
  }

  /// تحميل embeddings
  static void loadMultipleEmbeddings(Map<String, List<List<double>>> embeddings) {
    _storedMultipleEmbeddings = Map.from(embeddings);
    print('✅ Loaded ${embeddings.length} persons');
  }

  /// الحصول على embeddings
  static Map<String, dynamic> getStoredEmbeddings() {
    Map<String, dynamic> result = {};
    _storedMultipleEmbeddings.forEach((personId, embeddings) {
      result[personId] = embeddings;
    });
    return result;
  }

  /// حذف embeddings
  static void removeFaceEmbedding(String personId) {
    _storedMultipleEmbeddings.remove(personId);
    print('🗑️ Removed embeddings for $personId');
  }

  /// مسح كل البيانات
  static void clearStoredEmbeddings() {
    _storedMultipleEmbeddings.clear();
  }

  /// تنظيف
  static void dispose() {
    _detectionModel?.close();
    _landmarkModel?.close();
    _recognitionModel?.close();
    _detectionModel = null;
    _landmarkModel = null;
    _recognitionModel = null;
    _isInitialized = false;
    _storedMultipleEmbeddings.clear();
  }

  /// احصائيات
  static Map<String, dynamic> getStatistics() {
    int totalEmbeddings = 0;
    _storedMultipleEmbeddings.forEach((_, embeddings) {
      totalEmbeddings += embeddings.length;
    });
    return {
      'total_persons': _storedMultipleEmbeddings.length,
      'total_embeddings': totalEmbeddings,
      'embedding_size': EMBEDDING_SIZE,
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
    this.threshold = 0.35,
  });

  @override
  String toString() {
    return 'RecognitionResult(personId: $personId, similarity: ${(similarity * 100).toStringAsFixed(1)}%, isMatch: $isMatch)';
  }
}