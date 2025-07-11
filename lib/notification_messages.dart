import 'dart:math';

// List of messages for notifications
final List<String> notificationMessages = [
  'วันนี้เป็นวันที่ดี! อย่าลืมยิ้มและมีความสุขนะครับ',
  'พักสายตาบ้างนะ! ลุกขึ้นยืดเส้นยืดสายหน่อยก็ดีนะ',
  'ดื่มน้ำเยอะๆ นะครับ ร่างกายจะได้สดชื่นเสมอ',
  'คุณทำได้ดีมากแล้ว! พักผ่อนบ้างก็ดีนะ',
  'ถึงเวลาเช็คลิสต์แล้ว! มีอะไรต้องทำอีกไหม?',
];

// Function to get a random message
String getRandomNotificationMessage() {
  final random = Random(); // Removed the underscore
  return notificationMessages[random.nextInt(notificationMessages.length)];
}