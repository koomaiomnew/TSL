// ไฟล์: lib/screens/splash_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';

// 🔥 เช็คบรรทัดนี้: ถ้าไฟล์อยู่โฟลเดอร์เดียวกันใช้แบบนี้ถูกแล้ว
import 'camera_screen.dart'; 

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Timer(const Duration(seconds: 3), () {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const CameraScreen()),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF4DB6AC),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          // ❌ อย่าใส่ const ตรง children: [...] เพราะ ProgressIndicator ขยับได้
          children: [ // 🔥 ถ้า Error ให้ลบ const คำนี้ออก!
            Icon(Icons.sign_language, size: 120, color: Colors.white),
            SizedBox(height: 20),
            Text(
              "TSL\nInterpretation\nSystem",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: 1.2,
              ),
            ),
            SizedBox(height: 60),
            // 🔥 CircularProgressIndicator ห้ามมี const นำหน้า หรือครอบอยู่
            CircularProgressIndicator(
              color: Colors.white,
            ),
            SizedBox(height: 20),
            Text("กำลังโหลด...", style: TextStyle(color: Colors.white70)),
          ],
        ),
      ),
    );
  }
}