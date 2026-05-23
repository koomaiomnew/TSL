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
  bool _isSwitchingCamera = false;
  bool _isReadyToTranslate = false;
  String _guidanceMessage = "";

  // 🔥 ตัวแปรสำหรับกันบันทึกซ้ำ (Anti-Spam)
  String _lastSavedWord = "";
  DateTime? _lastSavedTime;

  // --- Data Lists ---
  List<Hand> _hands = [];
  List<Pose> _poses = [];
  Size _cameraSize = Size.zero;
  int _streamFrame = 0;
  int _uiUpdateTick = 0;
  int _bodyMissStreak = 0;
  bool _modelReady = false;
  bool _poseDetected = false;
  String _liveHint = "";

  // สถานะโมเดลบนจอ
  String _modelStatusLabel = "กำลังโหลด AI...";
  Color _modelStatusColor = Colors.orange;
  bool _isInferring = false;
  int _inferenceCount = 0;
  String _previewLabel = "";
  double _previewConfidence = 0;
  double _previewMargin = 0;
  List<Map<String, dynamic>> _topK = [];
  int _sameClassStreak = 0;
  int? _lastTopIndex;
  bool _showDomainWarning = false;
  DateTime? _saveCooldownUntil;

  static const int sequenceLength = 30;
  static const int minCaptureFrames = 20;
  static const int maxCaptureFrames = 60;
  static const int mlProcessEveryNFrames = 3;
  static const int predictEveryNProcessed = 4;
  static const int predictionHistoryLimit = 12;
  static const int stablePredictionCount = 3;
  static const double threshold = 0.45;
  static const double minTopMargin = 0.10;
  static const int maxBodyMissBeforeReset = 10;
  static const int saveCooldownSeconds = 3;
  final List<List<double>> _captureBuffer = [];
  final List<int> _predictions = [];
  int _predictTick = 0;

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
        minHandDetectionConfidence: 0.45,
      );

      _poseDetector = PoseDetector(
        options: PoseDetectorOptions(
          mode: PoseDetectionMode.stream,
          model: PoseDetectionModel.base,
        ),
      );

      _classifier = Classifier();
      await _classifier!.loadModel();
      _modelReady = _classifier!.isLoaded;
      if (_modelReady) {
        _modelStatusLabel = "AI พร้อม · ${_classifier!.labelCount} คำ";
        _modelStatusColor = Colors.greenAccent;
      } else {
        final err = _classifier?.loadError ?? "unknown";
        _modelStatusLabel = "AI ไม่พร้อม";
        _modelStatusColor = Colors.redAccent;
        _liveHint = "โหลดโมเดลไม่สำเร็จ — รัน export_tflite.py";
        debugPrint("Model load error: $err");
      }
      if (mounted) setState(() {});

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
    final oldController = _controller;
    if (oldController != null) {
      if (mounted) {
        setState(() {
          _controller = null;
          _hands = [];
          _poses = [];
          _cameraSize = Size.zero;
        });
      }
      if (oldController.value.isStreamingImages) {
        await oldController.stopImageStream();
      }
      await oldController.dispose();
    }

    _resetTranslationBuffer();

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
    } else {
      await controller.dispose();
    }
  }

  void _startDetection() {
    _controller?.startImageStream((image) async {
      if (_isSwitchingCamera) return;
      _streamFrame++;

      // ไม่กด REC: เช็ค pose เบาๆ เพื่อบอกว่ากล้องจับร่างได้ไหม
      if (!_isRecording) {
        if (_streamFrame % 12 == 0 && !_isProcessing) {
          _isProcessing = true;
          try {
            final c = _controller;
            if (c != null) {
              final poses = await _detectPose(image, c);
              if (mounted) {
                setState(() {
                  _poses = poses;
                  _poseDetected = _checkBodyVisible(poses);
                  _guidanceMessage = "";
                  _hands = [];
                });
              }
            }
          } finally {
            _isProcessing = false;
          }
        }
        return;
      }

      if (_isProcessing || !_modelReady) return;
      if (_streamFrame % mlProcessEveryNFrames != 0) return;
      _isProcessing = true;

      try {
        final activeController = _controller;
        if (activeController == null) return;
        final camera = activeController.description;

        List<Hand> hands = [];
        final poses = await _detectPose(image, activeController);

        try {
          hands = _handLandmarker!.detect(image, camera.sensorOrientation);
        } catch (_) {}

        final bodyOk = _checkBodyVisible(poses);
        _poseDetected = bodyOk;
        final readyToTranslate = poses.isNotEmpty;

        if (readyToTranslate) {
          _bodyMissStreak = 0;
          final keypoints =
              _extractKeypoints(hands, poses.first, camera.lensDirection);
          if (keypoints.length == 201) {
            _captureBuffer.add(keypoints);
            if (_captureBuffer.length > maxCaptureFrames) {
              _captureBuffer.removeAt(0);
            }

            _predictTick++;
            if (_captureBuffer.length >= minCaptureFrames &&
                _predictTick % predictEveryNProcessed == 0) {
              final resampled =
                  _resampleToSequence(_captureBuffer, sequenceLength);
              _processPrediction(resampled);
            }
          }
        } else {
          _bodyMissStreak++;
          if (_bodyMissStreak >= maxBodyMissBeforeReset) {
            _resetTranslationBuffer();
          }
        }

        _uiUpdateTick++;
        if (mounted && _uiUpdateTick % 2 == 0) {
          setState(() {
            _hands = hands;
            _poses = poses;
            _isReadyToTranslate = readyToTranslate;
            _guidanceMessage = _buildGuidanceMessage(poses);
          });
        }
      } catch (e) {
        debugPrint("Error processing frame: $e");
      } finally {
        _isProcessing = false;
      }
    });
  }

  Future<List<Pose>> _detectPose(CameraImage image, CameraController controller) async {
    try {
      final inputImage = CameraHelper.inputImageFromCameraImage(
        image,
        controller.description,
        deviceOrientation: controller.value.deviceOrientation,
      );
      if (inputImage == null) return [];
      return await _poseDetector!.processImage(inputImage);
    } catch (e) {
      debugPrint("Pose detect error: $e");
      return [];
    }
  }

  bool _checkBodyVisible(List<Pose> poses) {
    if (poses.isEmpty) return false;
    final landmarks = poses.first.landmarks;
    final nose = landmarks[PoseLandmarkType.nose];
    if (nose == null || nose.likelihood < 0.15) return false;

    final leftShoulder = landmarks[PoseLandmarkType.leftShoulder];
    final rightShoulder = landmarks[PoseLandmarkType.rightShoulder];
    final hasLeft =
        leftShoulder != null && leftShoulder.likelihood >= 0.15;
    final hasRight =
        rightShoulder != null && rightShoulder.likelihood >= 0.15;
    return hasLeft || hasRight;
  }

  String _buildGuidanceMessage(List<Pose> poses) {
    if (!_isRecording) return "";
    if (poses.isEmpty) {
      return "ไม่เห็นร่างกาย — หันหน้าเข้ากล้อง หรือกด 'กลับกล้อง' ลองกล้องหลัง";
    }
    if (!_checkBodyVisible(poses)) {
      return "ถอยห่างอีกนิด ให้เห็นใบหน้าและไหล่ชัดๆ";
    }
    if (_captureBuffer.length < minCaptureFrames) {
      return "ทำท่าช้าๆ (${_captureBuffer.length}/$minCaptureFrames เฟรม)";
    }
    if (_liveHint.isNotEmpty) return _liveHint;
    return "กำลังวิเคราะห์...";
  }

  void _resetTranslationBuffer({bool clearPreview = false}) {
    _captureBuffer.clear();
    _predictions.clear();
    _predictTick = 0;
    _bodyMissStreak = 0;
    if (clearPreview) {
      _previewLabel = "";
      _previewConfidence = 0;
      _previewMargin = 0;
    }
  }

  bool get _isOnSaveCooldown {
    final until = _saveCooldownUntil;
    return until != null && DateTime.now().isBefore(until);
  }

  /// สุ่มเฟรมแบบ linspace เหมือนตอน extract_data / เทรน
  List<List<double>> _resampleToSequence(
    List<List<double>> buffer,
    int targetLen,
  ) {
    if (buffer.isEmpty) return [];
    if (buffer.length == 1) {
      return List.generate(targetLen, (_) => buffer.first);
    }
    final last = buffer.length - 1;
    return List.generate(targetLen, (i) {
      final idx = ((i * last) / (targetLen - 1)).round();
      return buffer[idx];
    });
  }

  List<double> _extractKeypoints(
    List<Hand> hands,
    Pose pose,
    CameraLensDirection lensDirection,
  ) {
    final isFrontCamera = lensDirection != CameraLensDirection.back;
    final keypoints = <double>[];
    final mpOrder = [
      PoseLandmarkType.nose,
      PoseLandmarkType.leftEyeInner,
      PoseLandmarkType.leftEye,
      PoseLandmarkType.leftEyeOuter,
      PoseLandmarkType.rightEyeInner,
      PoseLandmarkType.rightEye,
      PoseLandmarkType.rightEyeOuter,
      PoseLandmarkType.leftEar,
      PoseLandmarkType.rightEar,
      PoseLandmarkType.leftMouth,
      PoseLandmarkType.rightMouth,
      PoseLandmarkType.leftShoulder,
      PoseLandmarkType.rightShoulder,
      PoseLandmarkType.leftElbow,
      PoseLandmarkType.rightElbow,
      PoseLandmarkType.leftWrist,
      PoseLandmarkType.rightWrist,
      PoseLandmarkType.leftPinky,
      PoseLandmarkType.rightPinky,
      PoseLandmarkType.leftIndex,
      PoseLandmarkType.rightIndex,
      PoseLandmarkType.leftThumb,
      PoseLandmarkType.rightThumb,
      PoseLandmarkType.leftHip,
      PoseLandmarkType.rightHip,
    ];

    final nose = pose.landmarks[PoseLandmarkType.nose];
    final refPoint = _normalizedPoseModelPoint(nose, lensDirection);
    final refX = refPoint?.dx ?? 0.0;
    final refY = refPoint?.dy ?? 0.0;
    final refZ = nose == null ? 0.0 : _normalizedPoseZ(nose.z);

    for (var type in mpOrder) {
      final lm = pose.landmarks[type];
      if (lm != null) {
        final point = _normalizedPoseModelPoint(lm, lensDirection);
        if (point != null) {
          keypoints.addAll([
            point.dx - refX,
            point.dy - refY,
            _normalizedPoseZ(lm.z) - refZ,
          ]);
        } else {
          keypoints.addAll([0.0, 0.0, 0.0]);
        }
      } else {
        keypoints.addAll([0.0, 0.0, 0.0]);
      }
    }

    // Match detected hands to the closest pose wrist.
    Hand? leftHand;
    Hand? rightHand;
    double leftHandDistance = double.infinity;
    double rightHandDistance = double.infinity;

    final leftPoseWrist = _normalizedPosePoint(
      pose.landmarks[PoseLandmarkType.leftWrist],
      lensDirection,
    );
    final rightPoseWrist = _normalizedPosePoint(
      pose.landmarks[PoseLandmarkType.rightWrist],
      lensDirection,
    );

    for (var hand in hands) {
      if (hand.landmarks.isEmpty) continue;
      final wrist = hand.landmarks[0];
      final handWrist = _normalizedHandPoint(wrist, lensDirection);

      final leftDistance = leftPoseWrist == null
          ? double.infinity
          : _distanceSquared(handWrist, leftPoseWrist);
      final rightDistance = rightPoseWrist == null
          ? double.infinity
          : _distanceSquared(handWrist, rightPoseWrist);

      if (leftDistance <= rightDistance) {
        if (leftDistance < leftHandDistance) {
          leftHand = hand;
          leftHandDistance = leftDistance;
        }
      } else {
        if (rightDistance < rightHandDistance) {
          rightHand = hand;
          rightHandDistance = rightDistance;
        }
      }
    }

    if (leftHand != null) {
      final base = leftHand.landmarks[0];
      final baseX = isFrontCamera ? 1 - base.x : base.x;
      for (var lm in leftHand.landmarks) {
        final x = isFrontCamera ? 1 - lm.x : lm.x;
        keypoints.addAll([x - baseX, lm.y - base.y, lm.z - base.z]);
      }
    } else {
      keypoints.addAll(List.filled(21 * 3, 0.0));
    }

    if (rightHand != null) {
      final base = rightHand.landmarks[0];
      final baseX = isFrontCamera ? 1 - base.x : base.x;
      for (var lm in rightHand.landmarks) {
        final x = isFrontCamera ? 1 - lm.x : lm.x;
        keypoints.addAll([x - baseX, lm.y - base.y, lm.z - base.z]);
      }
    } else {
      keypoints.addAll(List.filled(21 * 3, 0.0));
    }

    return keypoints;
  }

  Offset? _normalizedPosePoint(
    PoseLandmark? landmark,
    CameraLensDirection lensDirection,
  ) {
    if (landmark == null || _cameraSize == Size.zero) return null;

    final isFrontCamera = lensDirection != CameraLensDirection.back;
    final normalizedX = landmark.x / _cameraSize.height;
    final normalizedY = landmark.y / _cameraSize.width;

    return Offset(
      isFrontCamera ? 1 - normalizedX : normalizedX,
      normalizedY,
    );
  }

  Offset? _normalizedPoseModelPoint(
    PoseLandmark? landmark,
    CameraLensDirection lensDirection,
  ) {
    if (landmark == null || _cameraSize == Size.zero) return null;
    final isFrontCamera = lensDirection != CameraLensDirection.back;
    final normalizedX = landmark.x / _cameraSize.height;
    final normalizedY = landmark.y / _cameraSize.width;

    return Offset(
      isFrontCamera ? 1 - normalizedX : normalizedX,
      normalizedY,
    );
  }

  double _normalizedPoseZ(double z) {
    if (_cameraSize == Size.zero) return z;
    return z / _cameraSize.height;
  }

  Offset _normalizedHandPoint(
    Landmark landmark,
    CameraLensDirection lensDirection,
  ) {
    final isFrontCamera = lensDirection != CameraLensDirection.back;
    return Offset(
      1 - landmark.y,
      isFrontCamera ? 1 - landmark.x : landmark.x,
    );
  }

  double _distanceSquared(Offset a, Offset b) {
    final dx = a.dx - b.dx;
    final dy = a.dy - b.dy;
    return dx * dx + dy * dy;
  }

  void _processPrediction(List<List<double>> sequence) {
    if (_isOnSaveCooldown) return;

    _isInferring = true;
    if (mounted) setState(() {});

    try {
      final result = _classifier!.predict(sequence);
      _inferenceCount++;

      if (result != null && result.containsKey('label')) {
        final label = result['label'] as String;
        final confidence = (result['confidence'] as num).toDouble();
        final margin = (result['margin'] as num?)?.toDouble() ?? 0.0;
        final index = result['index'] as int? ?? -1;
        if (index < 0) return;

        _previewLabel = label;
        _previewConfidence = confidence;
        _previewMargin = margin;
        _topK = List<Map<String, dynamic>>.from(
          result['top_k'] as List? ?? [],
        );

        if (_lastTopIndex == index) {
          _sameClassStreak++;
        } else {
          _sameClassStreak = 1;
          _lastTopIndex = index;
        }
        _showDomainWarning =
            _isRecording && _inferenceCount >= 8 && _sameClassStreak >= 8;

        _predictions.add(index);
        if (_predictions.length > predictionHistoryLimit) {
          _predictions.removeAt(0);
        }

        final recent = _predictions.length >= stablePredictionCount
            ? _predictions.sublist(_predictions.length - stablePredictionCount)
            : _predictions;
        final isConsistent = recent.length >= stablePredictionCount &&
            recent.every((v) => v == index);

        final pct = (confidence * 100).toStringAsFixed(0);
        final mPct = (margin * 100).toStringAsFixed(0);

        if (!isConsistent) {
          _liveHint = "รอท่านิ่ง... $label $pct%";
        } else if (confidence < threshold || margin < minTopMargin) {
          _liveHint = "ยังไม่มั่นใจ — $label $pct% (ห่างอันดับ2: $mPct%)";
        } else {
          _liveHint = "พร้อมบันทึก: $label $pct%";
        }

        final accepted = isConsistent &&
            confidence >= threshold &&
            margin >= minTopMargin &&
            label != 'standing';

        if (accepted && !_isOnSaveCooldown) {
          final now = DateTime.now();
          final isDuplicate = label == _lastSavedWord;
          final isCooldownOver = _lastSavedTime == null ||
              now.difference(_lastSavedTime!).inSeconds >= saveCooldownSeconds;

          if (!isDuplicate || isCooldownOver) {
            _saveCooldownUntil =
                now.add(const Duration(seconds: saveCooldownSeconds));
            if (mounted) {
              setState(() {
                _detectedText = label;
                _lastSavedWord = label;
                _lastSavedTime = now;
                _liveHint = "บันทึกแล้ว: $label";
                _modelStatusLabel = "AI ทำงาน ✓";
              });
            }
            HistoryStorage.addHistory(label);
            _resetTranslationBuffer(clearPreview: true);
          }
        }
      } else if (!_classifier!.isLoaded) {
        _modelStatusLabel = "AI ไม่พร้อม";
        _modelStatusColor = Colors.redAccent;
        _liveHint = "โมเดลหยุดทำงาน";
      }
    } catch (e) {
      debugPrint("Predict Error: $e");
    } finally {
      _isInferring = false;
      if (mounted) setState(() {});
    }
  }

  Widget _buildModelStatusChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _modelStatusColor, width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: _isInferring ? Colors.amberAccent : _modelStatusColor,
              shape: BoxShape.circle,
              boxShadow: _isInferring
                  ? [
                      BoxShadow(
                        color: Colors.amberAccent.withValues(alpha: 0.8),
                        blurRadius: 6,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _isInferring ? "AI กำลังวิเคราะห์..." : _modelStatusLabel,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (_modelReady && _inferenceCount > 0) ...[
            const SizedBox(width: 6),
            Text(
              "#$_inferenceCount",
              style: TextStyle(color: Colors.grey.shade400, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPreviewPanel() {
    if (!_isRecording || !_modelReady) return const SizedBox.shrink();
    final buf = _captureBuffer.length;
    final confPct = (_previewConfidence * 100).toStringAsFixed(0);
    final marginPct = (_previewMargin * 100).toStringAsFixed(0);
    final onCooldown = _isOnSaveCooldown;

    String top3Text = "";
    if (_topK.isNotEmpty) {
      top3Text = _topK
          .map((e) {
            final l = e['label'] ?? '?';
            final c = ((e['confidence'] as num?) ?? 0) * 100;
            return "$l ${c.toStringAsFixed(0)}%";
          })
          .join("  |  ");
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: onCooldown
              ? Colors.orangeAccent
              : (_previewConfidence >= threshold
                  ? Colors.greenAccent
                  : Colors.white54),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            "เฟรม $buf/$minCaptureFrames · รันทำนาย $_inferenceCount ครั้ง",
            style: TextStyle(color: Colors.grey.shade400, fontSize: 11),
          ),
          const SizedBox(height: 4),
          if (buf < minCaptureFrames)
            Text(
              "กำลังเก็บท่า... ($buf/$minCaptureFrames)",
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            )
          else if (onCooldown)
            Text(
              "พัก ${saveCooldownSeconds}วิ ก่อนทายใหม่",
              style: const TextStyle(color: Colors.orangeAccent, fontSize: 14),
            )
          else ...[
            Text(
              "อันดับ 1: $_previewLabel  $confPct%  (margin $marginPct%)",
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (top3Text.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                "Top 3: $top3Text",
                style: TextStyle(color: Colors.grey.shade300, fontSize: 12),
              ),
            ],
          ],
        ],
      ),
    );
  }

  // ฟังก์ชันสลับกล้อง
  void _onSwitchCamera() async {
    if (cameras.length < 2 || _controller == null || _isSwitchingCamera) return;
    _isSwitchingCamera = true;
    final lensDirection = _controller!.description.lensDirection;
    CameraDescription newCamera;
    if (lensDirection == CameraLensDirection.front) {
      newCamera = cameras
          .firstWhere((c) => c.lensDirection == CameraLensDirection.back);
    } else {
      newCamera = cameras
          .firstWhere((c) => c.lensDirection == CameraLensDirection.front);
    }
    try {
      await _initializeCamera(newCamera);
    } finally {
      _isSwitchingCamera = false;
    }
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
        title: const Text("TSL Interpretation System",
            style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold)),
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
              lensDirection: _controller?.description.lensDirection,
            ),
          ),

          // สถานะ AI (มุมขวาบน — เห็นตลอดว่าโมเดลทำงานไหม)
          Positioned(
            top: 12,
            right: 12,
            child: _buildModelStatusChip(),
          ),

          if (!_modelReady)
            Positioned(
              top: 12,
              left: 12,
              right: 12,
              child: Material(
                color: Colors.red.shade700,
                borderRadius: BorderRadius.circular(8),
                child: const Padding(
                  padding: EdgeInsets.all(10),
                  child: Text(
                    "โหลดโมเดล AI ไม่สำเร็จ\nรัน python export_tflite.py แล้ว flutter clean && flutter run",
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),

          if (!_isRecording && _modelReady)
            Positioned(
              bottom: 130,
              left: 24,
              right: 24,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _poseDetected
                      ? "✓ จับร่างกายได้แล้ว — กดปุ่มแดงเพื่อแปล"
                      : "กดปุ่มแดงเพื่อแปล — รอจุดสีบนร่างกาย (หรือสลับกล้อง)",
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                ),
              ),
            ),

          if (_showDomainWarning && _isRecording)
            Positioned(
              top: 48,
              left: 12,
              right: 12,
              child: Material(
                color: Colors.deepOrange.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(8),
                child: const Padding(
                  padding: EdgeInsets.all(10),
                  child: Text(
                    "ทุกท่าขึ้นคำเดิมตลอด = กล้องมือถือไม่ตรงข้อมูลตอนเทรน\nลองท่าชัดๆ หรือต้องเก็บวิดีโอจากมือถือมาเทรนใหม่",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),

          if (_isRecording && _modelReady)
            Positioned(
              top: _showDomainWarning ? 118 : 52,
              left: 16,
              right: 16,
              child: _buildPreviewPanel(),
            ),

          if (_isRecording)
            Positioned(
              top: 20,
              left: 20,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(5)),
                child: const Text("[REC]",
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),

          if (_isRecording &&
              !_isReadyToTranslate &&
              _guidanceMessage.isNotEmpty)
            Positioned(
              top: 62,
              left: 20,
              right: 20,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.orangeAccent.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 6,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Text(
                  _guidanceMessage,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.black87,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ),

          // Layer 4: UI ส่วนล่าง (Result Box + Control Bar)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 4.1 กล่องผลลัพธ์ (แสดงเมื่อมีข้อความ และกำลังอัดอยู่ หรืออยากให้โชว์ค้างไว้ก็ได้)
                if (_detectedText.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 10),
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: _resultBoxColor, // ฟ้าอ่อน
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: _primaryColor, width: 2),
                      boxShadow: const [
                        BoxShadow(
                            color: Colors.black12,
                            blurRadius: 5,
                            offset: Offset(0, 3))
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header กล่อง
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 15, vertical: 8),
                          decoration: BoxDecoration(
                            color: _primaryColor,
                            borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(12),
                                topRight: Radius.circular(12)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text("แปลภาษามือเป็นข้อความ",
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold)),
                              GestureDetector(
                                onTap: () => setState(() => _detectedText = ""),
                                child: const Icon(Icons.close,
                                    color: Colors.white, size: 20),
                              )
                            ],
                          ),
                        ),
                        // Text Content
                        Padding(
                          padding: const EdgeInsets.all(20.0),
                          child: Text(
                            _detectedText,
                            style: const TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87),
                          ),
                        ),
                      ],
                    ),
                  ),

                // 4.2 Control Bar (แถบขาวด้านล่าง)
                Container(
                  color: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(vertical: 20, horizontal: 30),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // ปุ่มประวัติ
                      _buildControlButton(
                          icon: Icons.history,
                          label: "ประวัติ",
                          onTap: () {
                            // เชื่อมไปหน้า History
                            Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (context) =>
                                        const HistoryScreen()));
                          }),

                      // ปุ่มอัด (Main Action)
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _isRecording = !_isRecording;
                            if (_isRecording) {
                              _resetTranslationBuffer(clearPreview: true);
                              _liveHint = "";
                              _inferenceCount = 0;
                              _sameClassStreak = 0;
                              _lastTopIndex = null;
                              _showDomainWarning = false;
                              _saveCooldownUntil = null;
                              _modelStatusLabel =
                                  "AI พร้อม · ${_classifier?.labelCount ?? 10} คำ";
                              _hands = [];
                              _poses = [];
                            } else {
                              _lastSavedWord = "";
                              _isReadyToTranslate = false;
                              _guidanceMessage = "";
                              _liveHint = "";
                              _modelStatusLabel = "AI พร้อม";
                              _resetTranslationBuffer(clearPreview: true);
                              _hands = [];
                              _poses = [];
                            }
                          });
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 75,
                          height: 75,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: Colors.grey.shade300, width: 4),
                            color: Colors.white,
                          ),
                          child: Center(
                            child: Container(
                              width:
                                  _isRecording ? 30 : 55, // Effect ย่อขยายปุ่ม
                              height: _isRecording ? 30 : 55,
                              decoration: BoxDecoration(
                                color: _isRecording ? Colors.red : Colors.red,
                                borderRadius: BorderRadius.circular(_isRecording
                                    ? 5
                                    : 50), // เปลี่ยนเป็นสี่เหลี่ยมเมื่ออัด
                              ),
                            ),
                          ),
                        ),
                      ),

                      // ปุ่มสลับกล้อง
                      _buildControlButton(
                          icon: Icons.flip_camera_ios_outlined,
                          label: "กลับกล้อง",
                          onTap: _onSwitchCamera),
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
  Widget _buildControlButton(
      {required IconData icon,
      required String label,
      required VoidCallback onTap}) {
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
  final CameraLensDirection? lensDirection;

  SkeletonPainter(
      {required this.hands,
      required this.poses,
      required this.imgSize,
      required this.screenSize,
      required this.lensDirection});

  @override
  void paint(Canvas canvas, Size size) {
    if (imgSize.width == 0 || imgSize.height == 0) return;

    double scaleX = size.width / imgSize.height;
    double scaleY = size.height / imgSize.width;

    final paintPoseLine = Paint()
      ..color = Colors.cyanAccent
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    final paintHandLine = Paint()
      ..color = const Color(0xFF4DB6AC)
      ..strokeWidth = 2; // เปลี่ยนสีเส้นมือให้เข้าธีม
    final paintPoint = Paint()
      ..color = Colors.yellowAccent
      ..strokeWidth = 4
      ..style = PaintingStyle.fill;

    // วาด Pose (ตัว)
    if (poses.isNotEmpty) {
      final pose = poses.first;
      Offset transformPose(PoseLandmark landmark) {
        final isFrontCamera = lensDirection != CameraLensDirection.back;
        final x = landmark.x * scaleX;
        return Offset(isFrontCamera ? size.width - x : x, landmark.y * scaleY);
      }

      void drawLine(PoseLandmarkType s, PoseLandmarkType e) {
        final p1 = pose.landmarks[s];
        final p2 = pose.landmarks[e];
        if (p1 != null && p2 != null) {
          canvas.drawLine(transformPose(p1), transformPose(p2), paintPoseLine);
        }
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
        final isFrontCamera = lensDirection != CameraLensDirection.back;
        if (isFrontCamera) {
          return Offset(size.width - (y * size.width), (1 - x) * size.height);
        }
        return Offset(size.width - (y * size.width), x * size.height);
      }

      List<Offset> points =
          hand.landmarks.map((lm) => transformHand(lm.x, lm.y)).toList();
      final connections = [
        [0, 1],
        [1, 2],
        [2, 3],
        [3, 4],
        [0, 5],
        [5, 6],
        [6, 7],
        [7, 8],
        [0, 9],
        [9, 10],
        [10, 11],
        [11, 12],
        [0, 13],
        [13, 14],
        [14, 15],
        [15, 16],
        [0, 17],
        [17, 18],
        [18, 19],
        [19, 20],
        [5, 9],
        [9, 13],
        [13, 17],
        [0, 17]
      ];

      for (var conn in connections) {
        if (conn[0] < points.length && conn[1] < points.length) {
          canvas.drawLine(points[conn[0]], points[conn[1]], paintHandLine);
        }
      }
      for (var p in points) {
        canvas.drawCircle(p, 3, paintPoint..color = Colors.redAccent);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
