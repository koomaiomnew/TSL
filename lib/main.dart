import 'package:flutter/material.dart';
import 'package:camera/camera.dart';

// 🔥 สำคัญมาก! ต้องมีบรรทัดนี้ เพื่อดึงไฟล์หน้าจอโหลดมาใช้
import 'screens/splash_screen.dart'; 

List<CameraDescription> cameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    cameras = await availableCameras();
  } on CameraException catch (e) {
    debugPrint('Error: ${e.code}\nError Message: ${e.description}');
  }
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'TSL Interpretation',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF4DB6AC)),
        useMaterial3: true,
      ),
      // เรียกใช้ SplashScreen ตรงนี้
      home: const SplashScreen(), 
    );
  }
}