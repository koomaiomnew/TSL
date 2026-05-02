import 'dart:io';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

class Classifier {
  // ⚙️ ตั้งค่าพื้นฐาน (ตามโมเดลของคุณ)
  static const String _modelFile = 'action.tflite';
  static const String _labelFile = 'labels.txt';
  static const int _sequenceLength = 30; // 30 เฟรม
  static const int _inputSize = 201; // (Pose 25*3) + (LH 21*3) + (RH 21*3) = 75+63+63 = 201

  Interpreter? _interpreter;
  List<String> _labels = [];
  bool _isLoaded = false;

  bool get isLoaded => _isLoaded;

  /// โหลดโมเดลและป้ายชื่อ
  Future<void> loadModel() async {
    try {
      // 1. โหลด Labels
      print("🚀 1. โหลด Labels...");
      final labelData = await rootBundle.loadString('assets/$_labelFile');
      _labels = labelData
          .split('\n')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      print("✅ Labels โหลดเสร็จ: ${_labels.length} คำ");

      // 2. โหลด Model (ใช้ท่าไม้ตาย Temp File แก้ Bad State)
      print("🚀 2. อ่านไฟล์ Model (Temp File fix)...");
      final modelData = await rootBundle.load('assets/$_modelFile');
      final modelBytes = modelData.buffer.asUint8List();

      final tempDir = Directory.systemTemp;
      final tempFile = File('${tempDir.path}/temp_action_model.tflite');
      await tempFile.writeAsBytes(modelBytes);

      // 3. สร้าง Interpreter
      final options = InterpreterOptions()..threads = 2; // ใช้ 2 threads ช่วยประมวลผล
      _interpreter = Interpreter.fromFile(tempFile, options: options);

      // (Optional) เช็ค Input/Output Shape
      var inputShape = _interpreter!.getInputTensor(0).shape;
      var outputShape = _interpreter!.getOutputTensor(0).shape;
      print("📦 Model Input: $inputShape"); // ควรเป็น [1, 30, 201]
      print("📦 Model Output: $outputShape"); // ควรเป็น [1, 31]

      _isLoaded = true;
      print("✅✅ loadModel สมบูรณ์พร้อมใช้งาน!");
    } catch (e) {
      print("❌❌ loadModel พัง: $e");
    }
  }

  /// ทำนายผลจากชุดข้อมูล Keypoints (30 เฟรม)
  /// input: List of [Frame 1 (201 floats), Frame 2, ..., Frame 30]
  Map<String, dynamic>? predict(List<List<double>> buffer) {
    if (!_isLoaded || _interpreter == null) return null;

    // เช็คว่าข้อมูลครบ 30 เฟรมไหม?
    if (buffer.length != _sequenceLength) {
      print("⚠️ Buffer ไม่ครบ 30 เฟรม (มี ${buffer.length})");
      return null;
    }

    try {
      // 1. เตรียม Input [1, 30, 201]
      // ต้องแปลงเป็น List<List<List<double>>> ให้ตรงตาม Shape
      var input = [buffer]; 

      // 2. เตรียม Output [1, 31] (ตามจำนวนคำที่มี)
      var output = List.filled(1 * _labels.length, 0.0).reshape([1, _labels.length]);

      // 3. รันโมเดล! 🔥
      _interpreter!.run(input, output);

      // 4. หาค่าสูงสุด (ArgMax)
      List<double> result = List<double>.from(output[0]);
      double maxScore = -1;
      int maxIndex = -1;

      for (int i = 0; i < result.length; i++) {
        if (result[i] > maxScore) {
          maxScore = result[i];
          maxIndex = i;
        }
      }

      // 5. คืนค่าผลลัพธ์
      String label = (maxIndex != -1) ? _labels[maxIndex] : "Unknown";
      
      // 💡 ทริค: ถ้ามั่นใจน้อยกว่า 80% ให้ตอบว่า "กำลังดู..."
      if (maxScore < 0.80) {
        return {"label": "...", "confidence": maxScore};
      }

      return {
        "label": label,
        "confidence": maxScore,
      };

    } catch (e) {
      print("❌ Predict Error: $e");
      return null;
    }
  }
  
  void close() {
    _interpreter?.close();
  }
}