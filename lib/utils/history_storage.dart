// ไฟล์: lib/utils/history_storage.dart
class HistoryItem {
  final String word;
  final DateTime timestamp;

  HistoryItem({required this.word, required this.timestamp});
}

class HistoryStorage {
  // ตัวแปร static สำหรับเก็บข้อมูล (แชร์กันทุกหน้า)
  static List<HistoryItem> items = [];

  // ฟังก์ชันเพิ่มข้อมูล (เพิ่มไว้บนสุดของรายการ)
  static void addHistory(String label) {
    items.insert(0, HistoryItem(
      word: label,
      timestamp: DateTime.now(),
    ));
  }
}