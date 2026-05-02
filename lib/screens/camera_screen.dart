import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:hand_landmarker/hand_landmarker.dart';

// Import หน้าอื่นๆ และ Utils (ตรวจสอบ path ให้ตรงกับเครื่องพี่นะ)
import '../main.dart'; 
import '../utils/camera_helper.dart'; 
import '../classifier.dart'; 
import 'menu_drawer.dart'; // เรียกใช้ Drawer
import 'history_screen.dart'; // เรียกใช้หน้า History
import '../utils/history_storage.dart'; // 🔥 Import HistoryStorage เพื่อบันทึกประวัติ

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  // --- Controllers ---
  CameraController? _controller;
  HandLandmarkerPlugin? _handLandmarker;
  PoseDetector? _poseDetector;
  Classifier? _classifier;

  // --- State Variables ---
  String _detectedText = ""; // ข้อความที่แปลได้
  bool _isProcessing = false;
  bool _isRecording = false; // 🔥 ควบคุมการแปล (False = ไม่แปล, True = แปล)
  
  // 🔥 ตัวแปรสำหรับกันบันทึกซ้ำ (Anti-Spam)
  String _lastSavedWord = ""; 
  DateTime? _lastSavedTime;

  // --- Data Lists ---
  List<Hand> _hands = [];
  List<Pose> _poses = [];
  Size _cameraSize = Size.zero;

  // --- Python Logic Config ---
  static const int SEQUENCE_LENGTH = 30;
  static const double THRESHOLD = 0.80;
  final List<List<double>> _sequence = [];
  final List<int> _predictions = [];

  // --- UI Colors (ตาม Mockup) ---
  final Color _primaryColor = const Color(0xFF4DB6AC); // เขียวมิ้นต์หลัก
  final Color _resultBoxColor = const Color(0xFFB2EBF2); // ฟ้าอ่อนกล่องข้อความ

  @override
  void initState() {
    super.initState();
    _initSystem();
  }

  Future<void> _initSystem() async {
    try {
      // 1. Load Assets & Models
      await rootBundle.load('assets/hand_landmarker.task');
      await rootBundle.load('assets/action.tflite');

      _handLandmarker = HandLandmarkerPlugin.create(
        numHands: 2,
        minHandDetectionConfidence: 0.5,
      );

      _poseDetector = PoseDetector(
        options: PoseDetectorOptions(
          mode: PoseDetectionMode.stream,
          model: PoseDetectionModel.base,
        ),
      );

      _classifier = Classifier();
      await _classifier!.loadModel();

      // 2. Init Camera
      if (cameras.isNotEmpty) {
        // เริ่มต้นที่กล้องหน้า (Selfie)
        int cameraIndex = cameras.length > 1 ? 1 : 0;
        await _initializeCamera(cameras[cameraIndex]);
      }
    } catch (e) {
      debugPrint("Init Error: $e");
    }
  }

  Future<void> _initializeCamera(CameraDescription cameraDescription) async {
    final controller = CameraController(
      cameraDescription,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    await controller.initialize();

    if (mounted) {
      setState(() {
        _controller = controller;
        _cameraSize = controller.value.previewSize!;
      });
      _startDetection();
    }
  }

  void _startDetection() {
    _controller?.startImageStream((image) async {
      if (_isProcessing) return;
      _isProcessing = true;

      try {
        final camera = _controller!.description;

        // 1. Detect Hands & Pose (ทำตลอดเวลาเพื่อวาดเส้น)
        List<Hand> hands = [];
        List<Pose> poses = [];
        
        try {
          hands = _handLandmarker!.detect(image, camera.sensorOrientation);
        } catch (_) {}

        try {
          final inputImage = CameraHelper.inputImageFromCameraImage(image, camera);
          if (inputImage != null) {
            poses = await _poseDetector!.processImage(inputImage);
          }
        } catch (_) {}

        if (mounted) {
          setState(() {
            _hands = hands;
            _poses = poses;
          });

          // 🔥 2. Logic การแปล (ทำงานเฉพาะตอนกดปุ่มอัด _isRecording = true)
          if (_isRecording) {
            bool bodyVisible = _checkBodyVisible(poses);

            if (bodyVisible) {
               final keypoints = _extractKeypoints(hands, poses.first);
               _sequence.add(keypoints);
               
               // Keep Sequence length fixed
               if (_sequence.length > SEQUENCE_LENGTH) {
                 _sequence.removeAt(0);
               }

               // Predict
               if (_sequence.length == SEQUENCE_LENGTH) {
                  _processPrediction();
               }
            } else {
               // ถ้าตัวหลุดเฟรม ให้เคลียร์ sequence ทิ้ง เพื่อความแม่นยำเริ่มใหม่
               if (_sequence.isNotEmpty) _sequence.clear();
            }
          }
        }
      } catch (e) {
        debugPrint("Error processing frame: $e");
      } finally {
        _isProcessing = false;
      }
    });
  }

  // --- Logic เดิม (แก้ไข mouthLeft -> leftMouth แล้ว) ---
  bool _checkBodyVisible(List<Pose> poses) {
    if (poses.isEmpty) return false;
    final landmarks = poses.first.landmarks;
    // เช็คแค่ไหล่กับศอกพอสังเขป
    if (landmarks[PoseLandmarkType.leftShoulder] == null || 
        landmarks[PoseLandmarkType.rightShoulder] == null) {
      return false;
    }
    return true;
  }

  List<double> _extractKeypoints(List<Hand> hands, Pose pose) {
    List<double> keypoints = [];
    final nose = pose.landmarks[PoseLandmarkType.nose];
    double refX = nose?.x ?? 0;
    double refY = nose?.y ?? 0;
    double refZ = nose?.z ?? 0;

    // 🔥 Key: แก้ชื่อตัวแปรให้ถูกต้องตรงนี้
    final mpOrder = [
      PoseLandmarkType.nose, 
      PoseLandmarkType.leftEyeInner, PoseLandmarkType.leftEye, PoseLandmarkType.leftEyeOuter,
      PoseLandmarkType.rightEyeInner, PoseLandmarkType.rightEye, PoseLandmarkType.rightEyeOuter,
      PoseLandmarkType.leftEar, PoseLandmarkType.rightEar,
      PoseLandmarkType.leftMouth, PoseLandmarkType.rightMouth, // ✅ แก้แล้ว
      PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder,
      PoseLandmarkType.leftElbow, PoseLandmarkType.rightElbow,
      PoseLandmarkType.leftWrist, PoseLandmarkType.rightWrist,
      PoseLandmarkType.leftPinky, PoseLandmarkType.rightPinky,
      PoseLandmarkType.leftIndex, PoseLandmarkType.rightIndex,
      PoseLandmarkType.leftThumb, PoseLandmarkType.rightThumb,
      PoseLandmarkType.leftHip, PoseLandmarkType.rightHip
    ];

    for (var type in mpOrder) {
      final lm = pose.landmarks[type];
      if (lm != null) {
        keypoints.addAll([lm.x - refX, lm.y - refY, lm.z - refZ]);
      } else {
        keypoints.addAll([0.0, 0.0, 0.0]);
      }
    }

    // Logic แยกมือซ้ายขวา (เหมือนเดิม)
    Hand? leftHand; Hand? rightHand; 
    for (var hand in hands) {
       if (hand.landmarks.isNotEmpty) {
         if (hand.landmarks[0].x < 0.5) {
           rightHand = hand;
         } else {
           leftHand = hand;
         } 
       }
    }

    // Left Hand Relative
    if (leftHand != null) {
      final base = leftHand.landmarks[0]; 
      for (var lm in leftHand.landmarks) {
        keypoints.addAll([lm.x - base.x, lm.y - base.y, lm.z - base.z]);
      }
    } else {
      keypoints.addAll(List.filled(21 * 3, 0.0));
    }

    // Right Hand Relative
    if (rightHand != null) {
      final base = rightHand.landmarks[0]; 
      for (var lm in rightHand.landmarks) {
        keypoints.addAll([lm.x - base.x, lm.y - base.y, lm.z - base.z]);
      }
    } else {
      keypoints.addAll(List.filled(21 * 3, 0.0));
    }

    return keypoints;
  }

  void _processPrediction() {
    try {
      final result = _classifier!.predict(_sequence);
      if (result != null && result.containsKey('label')) {
        String label = result['label'];
        double confidence = result['confidence'];
        int index = result['index'] ?? -1;

        _predictions.add(index);
        // เพิ่มจำนวนเฟรมเช็คความนิ่ง (กันรัว)
        if (_predictions.length > 12) _predictions.removeAt(0);

        // เช็คความนิ่งของคำ (Consistency Check)
        bool isConsistent = false;
        if (_predictions.length >= 8) {
           int lastVal = _predictions.last;
           isConsistent = _predictions.sublist(_predictions.length - 8).every((v) => v == lastVal);
        }

        if (isConsistent && confidence > THRESHOLD) {
             if (label != 'standing') { // ไม่แสดงคำว่า standing
               
               // 🔥 Anti-Spam Logic:
               // 1. ถ้าคำใหม่ = คำล่าสุด (ซ้ำ) ต้องรอ 2 วินาทีถึงจะบันทึกใหม่ได้
               // 2. ถ้าคำใหม่ != คำล่าสุด บันทึกได้เลย
               final now = DateTime.now();
               bool isDuplicate = (label == _lastSavedWord);
               bool isCooldownOver = _lastSavedTime == null || now.difference(_lastSavedTime!).inSeconds > 2;

               if (!isDuplicate || isCooldownOver) {
                 setState(() {
                   _detectedText = label; 
                   _lastSavedWord = label;
                   _lastSavedTime = now;
                 });
                 
                 // ✅ บันทึกลงประวัติจริง
                 HistoryStorage.addHistory(label);
                 debugPrint("Saved: $label");

                 // เคลียร์ค่าให้เริ่มจับใหม่ (ป้องกันการค้าง)
                 _sequence.clear();
                 _predictions.clear();
               }
             }
        }
      }
    } catch (e) {
      debugPrint("Predict Error: $e");
    }
  }

  // ฟังก์ชันสลับกล้อง
  void _onSwitchCamera() async {
    if (cameras.length < 2) return;
    final lensDirection = _controller!.description.lensDirection;
    CameraDescription newCamera;
    if (lensDirection == CameraLensDirection.front) {
      newCamera = cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.back);
    } else {
      newCamera = cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.front);
    }
    await _initializeCamera(newCamera);
  }

  @override
  void dispose() {
    _controller?.dispose();
    _handLandmarker?.dispose();
    _poseDetector?.close();
    _classifier?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      // 1. App Bar (สีเขียวมิ้นต์ตาม Mockup)
      appBar: AppBar(
        backgroundColor: _primaryColor,
        elevation: 0,
        title: const Text("TSL Interpretation System", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {},
          )
        ],
      ),
      // 2. ลิ้นชักเมนู (เชื่อมกับไฟล์ menu_drawer.dart)
      drawer: const MenuDrawer(), 
      
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Layer 1: กล้อง
          if (_controller != null && _controller!.value.isInitialized)
            CameraPreview(_controller!)
          else
            const Center(child: CircularProgressIndicator()),

          // Layer 2: เส้น Skeleton (วาดตลอดเวลา เพื่อให้ User รู้ว่ากล้องจับเจอไหม)
          CustomPaint(
            painter: SkeletonPainter(
              hands: _hands,
              poses: _poses,
              imgSize: _cameraSize,
              screenSize: MediaQuery.of(context).size,
            ),
          ),

          // Layer 3: [REC] Indicator (แสดงเฉพาะตอนกดอัด)
          if (_isRecording)
            Positioned(
              top: 20, left: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: Colors.redAccent.withOpacity(0.8), borderRadius: BorderRadius.circular(5)),
                child: const Text("[REC]", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),

          // Layer 4: UI ส่วนล่าง (Result Box + Control Bar)
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 4.1 กล่องผลลัพธ์ (แสดงเมื่อมีข้อความ และกำลังอัดอยู่ หรืออยากให้โชว์ค้างไว้ก็ได้)
                if (_detectedText.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: _resultBoxColor, // ฟ้าอ่อน
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: _primaryColor, width: 2),
                      boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 5, offset: Offset(0, 3))],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header กล่อง
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
                          decoration: BoxDecoration(
                            color: _primaryColor,
                            borderRadius: const BorderRadius.only(topLeft: Radius.circular(12), topRight: Radius.circular(12)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text("แปลภาษามือเป็นข้อความ", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                              GestureDetector(
                                onTap: () => setState(() => _detectedText = ""),
                                child: const Icon(Icons.close, color: Colors.white, size: 20),
                              )
                            ],
                          ),
                        ),
                        // Text Content
                        Padding(
                          padding: const EdgeInsets.all(20.0),
                          child: Text(
                            _detectedText,
                            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.black87),
                          ),
                        ),
                      ],
                    ),
                  ),

                // 4.2 Control Bar (แถบขาวด้านล่าง)
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 30),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // ปุ่มประวัติ
                      _buildControlButton(
                        icon: Icons.history, 
                        label: "ประวัติ", 
                        onTap: () {
                          // เชื่อมไปหน้า History
                          Navigator.push(context, MaterialPageRoute(builder: (context) => const HistoryScreen()));
                        }
                      ),

                      // ปุ่มอัด (Main Action)
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _isRecording = !_isRecording;
                            if (!_isRecording) {
                              // ถ้าหยุดอัด ให้เคลียร์ค่าต่างๆ
                              _lastSavedWord = ""; // ล้างคำล่าสุด เพื่อให้เริ่มใหม่ได้ทันที
                              _sequence.clear();
                              _predictions.clear();
                              // _detectedText = ""; // ถ้าอยากให้ข้อความหายไปเมื่อหยุด ให้เปิดบรรทัดนี้
                            }
                          });
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 75, height: 75,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.grey.shade300, width: 4),
                            color: Colors.white,
                          ),
                          child: Center(
                            child: Container(
                              width: _isRecording ? 30 : 55, // Effect ย่อขยายปุ่ม
                              height: _isRecording ? 30 : 55,
                              decoration: BoxDecoration(
                                color: _isRecording ? Colors.red : Colors.red,
                                borderRadius: BorderRadius.circular(_isRecording ? 5 : 50), // เปลี่ยนเป็นสี่เหลี่ยมเมื่ออัด
                              ),
                            ),
                          ),
                        ),
                      ),

                      // ปุ่มสลับกล้อง
                      _buildControlButton(
                        icon: Icons.flip_camera_ios_outlined, 
                        label: "กลับกล้อง", 
                        onTap: _onSwitchCamera
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Helper สร้างปุ่มเล็ก
  Widget _buildControlButton({required IconData icon, required String label, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.grey[700], size: 30),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600]))
        ],
      ),
    );
  }
}

// --- Skeleton Painter (คงเดิมไว้) ---
class SkeletonPainter extends CustomPainter {
  final List<Hand> hands;
  final List<Pose> poses;
  final Size imgSize;
  final Size screenSize;

  SkeletonPainter({required this.hands, required this.poses, required this.imgSize, required this.screenSize});

  @override
  void paint(Canvas canvas, Size size) {
    if (imgSize.width == 0 || imgSize.height == 0) return;

    double scaleX = size.width / imgSize.height;
    double scaleY = size.height / imgSize.width;

    final paintPoseLine = Paint()..color = Colors.cyanAccent..strokeWidth = 3..style = PaintingStyle.stroke;
    final paintHandLine = Paint()..color = const Color(0xFF4DB6AC)..strokeWidth = 2; // เปลี่ยนสีเส้นมือให้เข้าธีม
    final paintPoint = Paint()..color = Colors.yellowAccent..strokeWidth = 4..style = PaintingStyle.fill;

    // วาด Pose (ตัว)
    if (poses.isNotEmpty) {
      final pose = poses.first;
      Offset transformPose(PoseLandmark landmark) {
        return Offset(size.width - (landmark.x * scaleX), landmark.y * scaleY);
      }
      void drawLine(PoseLandmarkType s, PoseLandmarkType e) {
        final p1 = pose.landmarks[s]; final p2 = pose.landmarks[e];
        if (p1 != null && p2 != null) canvas.drawLine(transformPose(p1), transformPose(p2), paintPoseLine);
      }
      // วาดเส้นเชื่อมตัว
      drawLine(PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder);
      drawLine(PoseLandmarkType.leftShoulder, PoseLandmarkType.leftElbow);
      drawLine(PoseLandmarkType.leftElbow, PoseLandmarkType.leftWrist);
      drawLine(PoseLandmarkType.rightShoulder, PoseLandmarkType.rightElbow);
      drawLine(PoseLandmarkType.rightElbow, PoseLandmarkType.rightWrist);
      // วาดจุดจมูก
      final nose = pose.landmarks[PoseLandmarkType.nose];
      if (nose != null) canvas.drawCircle(transformPose(nose), 5, paintPoint);
    }

    // วาด Hands (มือ)
    for (var hand in hands) {
      Offset transformHand(double x, double y) {
         return Offset(size.width - (y * size.width), (1 - x) * size.height); 
      }
      List<Offset> points = hand.landmarks.map((lm) => transformHand(lm.x, lm.y)).toList();
      final connections = [[0, 1], [1, 2], [2, 3], [3, 4], [0, 5], [5, 6], [6, 7], [7, 8], [0, 9], [9, 10], [10, 11], [11, 12], [0, 13], [13, 14], [14, 15], [15, 16], [0, 17], [17, 18], [18, 19], [19, 20], [5, 9], [9, 13], [13, 17], [0, 17]];
      
      for (var conn in connections) {
        if (conn[0] < points.length && conn[1] < points.length) canvas.drawLine(points[conn[0]], points[conn[1]], paintHandLine);
      }
      for (var p in points) {
        canvas.drawCircle(p, 3, paintPoint..color = Colors.redAccent);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}