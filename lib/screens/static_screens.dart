// lib/screens/static_screens.dart
import 'package:flutter/material.dart';

class ContentTemplate extends StatelessWidget {
  final String title;
  final String content;

  const ContentTemplate(
      {super.key, required this.title, required this.content});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        backgroundColor: const Color(0xFF80CBC4),
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(color: Colors.grey.withOpacity(0.2), blurRadius: 5)
            ],
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: SingleChildScrollView(
            child: Text(content, style: const TextStyle(fontSize: 16)),
          ),
        ),
      ),
    );
  }
}

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return const ContentTemplate(
        title: "เกี่ยวกับ",
        content: "TSL Interpretation System\n\nผู้พัฒนา:\n1. นางสาวอรจิรา ก้อนธิ\n2. นายเอกพล มณเฑียร\n\n");
  }
}

class PolicyScreen extends StatelessWidget {
  const PolicyScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return const ContentTemplate(
        title: "นโยบายความเป็นส่วนตัว",
        content: "1. การเก็บรวบรวมข้อมูล\nระบบจะใช้กล้องเพื่อการประมวลผลแบบ Real-time เท่านั้น ไม่มีการบันทึกวิดีโอลงเซิร์ฟเวอร์...\n\n");
  }
}

class ManualScreen extends StatelessWidget {
  const ManualScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return const ContentTemplate(
        title: "คู่มือการใช้งาน",
        content: "1. กดปุ่ม Record เพื่อเริ่มแปลภาษา\n2. ทำท่าทางหน้ากล้อง\n3. ระบบจะแสดงคำแปลที่หน้าจอ\n\n");
  }
}