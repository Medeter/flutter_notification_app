import 'dart:math';

// List of messages for notifications
final List<String> notificationMessages = [
  'วันนี้เป็นวันที่ดี! อย่าลืมยิ้มและมีความสุขนะครับ',
  'พักสายตาบ้างนะ! ลุกขึ้นยืดเส้นยืดสายหน่อยก็ดีนะ',
  'ดื่มน้ำเยอะๆ นะครับ ร่างกายจะได้สดชื่นเสมอ',
  'คุณทำได้ดีมากแล้ว! พักผ่อนบ้างก็ดีนะ',
  'ถึงเวลาเช็คลิสต์แล้ว! มีอะไรต้องทำอีกไหม?',
];

// ใช้ global เพื่อจำข้อความครั้งก่อน
String? _lastMessage;

// Function to get a random message (ไม่ซ้ำกับข้อความครั้งก่อน)
String getRandomNotificationMessage() {
  final random = Random(DateTime.now().millisecondsSinceEpoch);
  String newMessage;
  do {
    newMessage = notificationMessages[random.nextInt(notificationMessages.length)];
  } while (newMessage == _lastMessage && notificationMessages.length > 1);
  _lastMessage = newMessage;
  return newMessage;
}
