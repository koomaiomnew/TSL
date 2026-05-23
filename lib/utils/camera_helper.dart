import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

/// แปลง CameraImage → InputImage สำหรับ ML Kit (Android ใช้ NV21 + stride จริง)
class CameraHelper {
  static InputImage? inputImageFromCameraImage(
    CameraImage image,
    CameraDescription camera, {
    DeviceOrientation deviceOrientation = DeviceOrientation.portraitUp,
  }) {
    try {
      final rotation = _rotation(camera, deviceOrientation);
      if (rotation == null) return null;

      if (Platform.isAndroid) {
        final bytes = _yuv420ToNv21(image);
        return InputImage.fromBytes(
          bytes: bytes,
          metadata: InputImageMetadata(
            size: Size(image.width.toDouble(), image.height.toDouble()),
            rotation: rotation,
            format: InputImageFormat.nv21,
            bytesPerRow: image.width,
          ),
        );
      }

      if (Platform.isIOS && image.planes.length == 1) {
        return InputImage.fromBytes(
          bytes: image.planes[0].bytes,
          metadata: InputImageMetadata(
            size: Size(image.width.toDouble(), image.height.toDouble()),
            rotation: rotation,
            format: InputImageFormat.bgra8888,
            bytesPerRow: image.planes[0].bytesPerRow,
          ),
        );
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  static Uint8List _yuv420ToNv21(CameraImage image) {
    final width = image.width;
    final height = image.height;
    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];

    final nv21 = Uint8List(width * height + (width * height >> 1));
    var index = 0;

    for (var row = 0; row < height; row++) {
      final rowOffset = row * yPlane.bytesPerRow;
      for (var col = 0; col < width; col++) {
        nv21[index++] = yPlane.bytes[rowOffset + col];
      }
    }

    final uvRowStride = uPlane.bytesPerRow;
    // camera 0.11 ใช้ bytesPerPixel แทน pixelStride (มักเป็น 2 บน Android)
    final uvPixelStride = uPlane.bytesPerPixel ?? 2;
    final uvWidth = width >> 1;
    final uvHeight = height >> 1;

    for (var row = 0; row < uvHeight; row++) {
      for (var col = 0; col < uvWidth; col++) {
        final uvIndex = row * uvRowStride + col * uvPixelStride;
        if (uvIndex < vPlane.bytes.length && uvIndex < uPlane.bytes.length) {
          nv21[index++] = vPlane.bytes[uvIndex];
          nv21[index++] = uPlane.bytes[uvIndex];
        }
      }
    }

    return nv21;
  }

  static InputImageRotation? _rotation(
    CameraDescription camera,
    DeviceOrientation deviceOrientation,
  ) {
    if (Platform.isIOS) {
      return InputImageRotationValue.fromRawValue(camera.sensorOrientation);
    }

    var rotationCompensation = _orientationDegrees(deviceOrientation);
    if (camera.lensDirection == CameraLensDirection.front) {
      rotationCompensation =
          (camera.sensorOrientation + rotationCompensation) % 360;
    } else {
      rotationCompensation =
          (camera.sensorOrientation - rotationCompensation + 360) % 360;
    }
    return InputImageRotationValue.fromRawValue(rotationCompensation);
  }

  static int _orientationDegrees(DeviceOrientation orientation) {
    switch (orientation) {
      case DeviceOrientation.portraitUp:
        return 0;
      case DeviceOrientation.landscapeLeft:
        return 90;
      case DeviceOrientation.portraitDown:
        return 180;
      case DeviceOrientation.landscapeRight:
        return 270;
    }
  }
}
