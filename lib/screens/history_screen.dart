// ไฟล์: lib/screens/history_screen.dart
import 'package:flutter/material.dart';
import '../utils/history_storage.dart'; // 🔥 สำคัญ: ต้อง Import ตัวเก็บข้อมูล

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar( 
        title: const Text("ประวัติการแปล", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF4DB6AC),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      // เช็คว่ามีข้อมูลไหม
      body: HistoryStorage.items.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.history, size: 80, color: Colors.grey),
                  SizedBox(height: 10),
                  Text("ยังไม่มีประวัติการแปล", style: TextStyle(color: Colors.grey, fontSize: 18)),
                ],
              ),
            )
          : ListView.builder(
              itemCount: HistoryStorage.items.length,
              itemBuilder: (context, index) {
                final item = HistoryStorage.items[index];
                // แปลงเวลาให้สวยงาม (เช่น 14:30)
                final timeStr = "${item.timestamp.hour.toString().padLeft(2, '0')}:${item.timestamp.minute.toString().padLeft(2, '0')}";
                final dateStr = "${item.timestamp.day}/${item.timestamp.month}/${item.timestamp.year}";

                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  child: ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: Color(0xFFB2EBF2),
                      child: Icon(Icons.sign_language, color: Color(0xFF00695C)),
                    ),
                    title: Text(
                      item.word, // คำศัพท์ที่แปลได้
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.black87),
                    ),
                    subtitle: Text("เวลา: $timeStr น.  |  วันที่: $dateStr"),
                  ),
                );
              },
            ),
    );
  }
}