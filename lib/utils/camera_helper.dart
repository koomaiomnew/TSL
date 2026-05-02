import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

class CameraHelper {
  static InputImage? inputImageFromCameraImage(CameraImage image, CameraDescription camera) {
    try {
      // 1. เช็ค Rotation
      final sensorOrientation = camera.sensorOrientation;
      InputImageRotation? rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
      if (rotation == null) return null;

      // 2. บังคับ Format เป็น NV21 (ค่า rawValue คือ 17)
      const format = InputImageFormat.nv21;

      // 3. ☢️ แปลงข้อมูล YUV_420_888 (ที่มี Padding) ให้เป็น NV21 (Clean)
      final int width = image.width;
      final int height = image.height;
      
      // เตรียม Buffer ที่ขนาดเป๊ะๆ (Y + UV)
      // Y = w * h
      // UV = (w * h) / 2
      final int targetSize = (width * height * 1.5).toInt();
      final Uint8List targetBytes = Uint8List(targetSize);
      
      int targetIndex = 0;

      // --- ขั้นตอนที่ 3.1: ก๊อปปี้ Y Plane (ความสว่าง) ---
      final Plane yPlane = image.planes[0];
      for (int y = 0; y < height; y++) {
        final int srcOffset = y * yPlane.bytesPerRow;
        for (int x = 0; x < width; x++) {
          targetBytes[targetIndex++] = yPlane.bytes[srcOffset + x];
        }
      }

      // --- ขั้นตอนที่ 3.2: ก๊อปปี้ UV Plane (สี) ---
      // เราสมมติว่า Pixel Stride = 2 (สำหรับ iQOO/Vivo ส่วนใหญ่ที่เป็น NV21)
      final Plane uPlane = image.planes[1];
      final Plane vPlane = image.planes[2];
      
      // การคำนวณ: U/V จะมีความกว้างและความสูงเป็นครึ่งหนึ่งของ Y
      for (int y = 0; y < height ~/ 2; y++) {
        for (int x = 0; x < width ~/ 2; x++) {
          
          // ⚠️ จุดที่แก้ Error: 
          // เปลี่ยนจาก vPlane.pixelStride เป็น 2 ตายตัวเลย
          // สูตร: (แถว * ความกว้างแถว) + (คอลัมน์ * 2)
          final int uvIndex = (y * vPlane.bytesPerRow) + (x * 2);
          
          // ป้องกัน index เกิน (เผื่อไว้กันเหนียว)
          if (targetIndex < targetSize - 1 && uvIndex < vPlane.bytes.length && uvIndex < uPlane.bytes.length) {
            // NV21 Format: ต้องใส่ V ก่อน แล้วตามด้วย U
            targetBytes[targetIndex++] = vPlane.bytes[uvIndex]; 
            targetBytes[targetIndex++] = uPlane.bytes[uvIndex];
          }
        }
      }

      // 4. ส่งข้อมูลที่ "จัดจาน" เรียบร้อยแล้ว
      return InputImage.fromBytes(
        bytes: targetBytes,
        metadata: InputImageMetadata(
          size: Size(width.toDouble(), height.toDouble()),
          rotation: rotation,
          format: format,
          bytesPerRow: width, // บอก AI ว่าแถวนี้ไม่มีขอบแถมแล้วนะ
        ),
      );

    } catch (e) {
      // ถ้ามี Error อะไรก็ตาม ให้ข้ามเฟรมนี้ไปเลย (แอปจะได้ไม่เด้ง)
      return null;
    }
  }
}