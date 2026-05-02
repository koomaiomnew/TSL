import 'package:flutter/material.dart';
import 'history_screen.dart'; // ตรวจสอบว่ามีไฟล์นี้อยู่จริง
import 'static_screens.dart'; // ไฟล์หน้าย่อยๆ (ดูโค้ดด้านล่าง)

class MenuDrawer extends StatelessWidget {
  const MenuDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: Column(
        children: [
          // Header ส่วนบน
          Container(
            width: double.infinity,
            padding: const EdgeInsets.only(top: 50, bottom: 20),
            decoration: const BoxDecoration(
              color: Color(0xFF4DB6AC), // สีเขียวมิ้นต์เข้ม (ตามธีมหลัก)
            ),
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.account_circle, size: 80, color: Colors.white),
                SizedBox(height: 10),
                Text(
                  'TSL Interpretation System',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Guest User',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ],
            ),
          ),

          // List Menu
          Expanded(
            child: Container(
              color: Colors.white,
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 10),
                children: [
                  _buildMenuItem(
                    context, 
                    "ประวัติการแปล", 
                    Icons.history, 
                    const HistoryScreen() // ต้องมั่นใจว่า HistoryScreen มี const constructor หรือลบ const ออก
                  ),
                  _buildMenuItem(
                    context, 
                    "คู่มือการใช้งาน", 
                    Icons.book_outlined, 
                    const ManualScreen()
                  ),
                  _buildMenuItem(
                    context, 
                    "เกี่ยวกับแอปพลิเคชัน", 
                    Icons.info_outline, 
                    const AboutScreen()
                  ),
                  _buildMenuItem(
                    context, 
                    "นโยบายความเป็นส่วนตัว", 
                    Icons.privacy_tip_outlined, 
                    const PolicyScreen()
                  ),
                ],
              ),
            ),
          ),

          // Version Footer
          const Padding(
            padding: EdgeInsets.all(20.0),
            child: Text("Version 1.0.0", style: TextStyle(color: Colors.grey)),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuItem(BuildContext context, String title, IconData icon, Widget page) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFB2EBF2), // สีฟ้าอ่อน (ตาม Mockup กล่องข้อความ)
        borderRadius: BorderRadius.circular(10),
      ),
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFF00695C)), // สีไอคอนเขียวเข้ม
        title: Text(
          title,
          style: const TextStyle(
            color: Color(0xFF00695C), 
            fontWeight: FontWeight.bold
          ),
        ),
        trailing: const Icon(Icons.arrow_forward_ios, color: Color(0xFF00695C), size: 16),
        onTap: () {
          Navigator.pop(context); // ปิด Drawer
          Navigator.push(
            context, 
            MaterialPageRoute(builder: (c) => page)
          ); 
        },
      ),
    );
  }
}