import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:workmanager/workmanager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:logger/logger.dart';
import 'notification_messages.dart';

// บริการ Logger สำหรับการดีบักและการบันทึกเหตุการณ์
class LogService {
  static final Logger logger = Logger();
}

// อินสแตนซ์ส่วนกลางของ FlutterLocalNotificationsPlugin
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

// ค่าคงที่สำหรับ Workmanager task และ notification channel
const String periodicTask = "periodicNotificationTask";
const String channelId = 'notification_channel_id';
const String channelName = 'ช่องทางการแจ้งเตือน'; // Notification Channel
const String channelDescription = 'นี่คือช่องทางการแจ้งเตือนสำหรับแจ้งเตือนเป็นระยะ'; // This is a channel for periodic notifications
const String lastScheduledTimestampKey = 'lastScheduledTimestamp'; // Key สำหรับเก็บ timestamp ล่าสุด
const String notificationIdCounterKey = 'notificationIdCounter'; // Key สำหรับเก็บ ID การแจ้งเตือนล่าสุด

/// เริ่มต้นบริการแจ้งเตือน
/// ฟังก์ชันนี้ตั้งค่าการแจ้งเตือนสำหรับ Android และเริ่มต้น
/// FlutterLocalNotificationsPlugin นอกจากนี้ยังกำหนด callback สำหรับ
/// เมื่อได้รับการแจ้งเตือน
Future<void> initializeNotificationService() async {
  const AndroidInitializationSettings androidSettings =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  const InitializationSettings initSettings =
      InitializationSettings(android: androidSettings);

  await flutterLocalNotificationsPlugin.initialize(
    initSettings,
    onDidReceiveNotificationResponse: (NotificationResponse response) {
      // บันทึก payload เมื่อมีการแตะการแจ้งเตือน
      LogService.logger.i('Notification payload: ${response.payload}');
    },
  );

  // ร้องขอสิทธิ์การแจ้งเตือนสำหรับ Android (API 33+)
  final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
      flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  if (androidImplementation != null) {
    final bool? granted = await androidImplementation.requestNotificationsPermission();
    if (granted != null) {
      LogService.logger.i('Notification permission granted: $granted');
    } else {
      LogService.logger.w('Notification permission request result is null.');
    }
  }
}

/// callback dispatcher สำหรับ Workmanager
/// ฟังก์ชันนี้จะถูกเรียกใช้ในเบื้องหลังโดย Workmanager
/// โดยจะตรวจสอบว่า task เป็น task การแจ้งเตือนแบบวนซ้ำหรือไม่ จากนั้น
/// จะแสดงการแจ้งเตือน
@pragma('vm:entry-point') // บังคับสำหรับ background tasks
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    LogService.logger.i("Workmanager task: $task started.");
    final prefs = await SharedPreferences.getInstance();

    if (task == periodicTask) {
      // ดึง ID การแจ้งเตือนล่าสุดและเพิ่มค่า
      int currentNotificationId = prefs.getInt(notificationIdCounterKey) ?? 0;
      currentNotificationId++;
      await prefs.setInt(notificationIdCounterKey, currentNotificationId);

      final String randomMessage = getRandomNotificationMessage();
      
      await flutterLocalNotificationsPlugin.show(
        currentNotificationId, // ใช้ ID ที่ไม่ซ้ำกัน
        'แจ้งเตือนประจำ (เบื้องหลัง)',
        randomMessage,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            channelId,
            channelName,
            channelDescription: channelDescription,
            importance: Importance.high,
            priority: Priority.high,
            // เพิ่ม allowWhileIdle เพื่อให้แสดงแม้เครื่องอยู่ในโหมดประหยัดพลังงาน
            // เพิ่ม fullScreenIntent หากต้องการให้เป็นแจ้งเตือนแบบเต็มหน้าจอ
          ),
        ),
        payload: 'payload_from_workmanager_$currentNotificationId',
      );
      // อัปเดต timestamp ล่าสุดเมื่อ Workmanager ส่งการแจ้งเตือน
      await prefs.setInt(lastScheduledTimestampKey, DateTime.now().millisecondsSinceEpoch);
      LogService.logger.i("Periodic notification shown with ID: $currentNotificationId");

      // ส่วนนี้จะถูกเรียกใช้เมื่อ periodicTask ถูกเรียก (รวมถึงเมื่อ Workmanager รันตอนบูตและถึงรอบของ periodicTask)
      LogService.logger.i("Checking for missed notifications within periodicTask callback...");
      final scheduled = prefs.getBool('isScheduled') ?? false;

      if (scheduled) {
        final lastTimestamp = prefs.getInt(lastScheduledTimestampKey);
        if (lastTimestamp != null) {
          final lastScheduledDateTime = DateTime.fromMillisecondsSinceEpoch(lastTimestamp);
          final now = DateTime.now();

          // คำนวณจำนวนการแจ้งเตือนที่พลาดไป
          // ใช้ค่า interval จากด้านบนสุดของไฟล์ (const Duration(minutes: 15))
          final int missedIntervals = (now.difference(lastScheduledDateTime).inSeconds / const Duration(minutes: 15).inSeconds).floor();

          if (missedIntervals > 0) {
            LogService.logger.i('พบการแจ้งเตือนที่พลาดไปจาก periodicTask (อาจเกิดจาก boot/downtime): $missedIntervals ครั้ง');
            await _triggerMissedNotifications(missedIntervals);

            // อัปเดต lastScheduledTimestampKey ให้เป็นเวลาที่ควรจะมีการแจ้งเตือนครั้งล่าสุดที่ถูกเรียกใช้
            final newLastScheduledTime = lastScheduledDateTime.add(Duration(seconds: missedIntervals * const Duration(minutes: 15).inSeconds));
            await prefs.setInt(lastScheduledTimestampKey, newLastScheduledTime.millisecondsSinceEpoch);
          }
        }
      }
    } else if (task == Workmanager.iOSBackgroundTask) { // <<< แก้ไขตรงนี้: ลบ androidBootTaskName
      // Workmanager.iOSBackgroundTask จะถูกเรียกเมื่อ iOS กำหนดให้ทำงานเบื้องหลัง
      LogService.logger.i("iOS Background task detected. Checking for missed notifications...");
      final scheduled = prefs.getBool('isScheduled') ?? false;

      if (scheduled) {
        final lastTimestamp = prefs.getInt(lastScheduledTimestampKey);
        if (lastTimestamp != null) {
          final lastScheduledDateTime = DateTime.fromMillisecondsSinceEpoch(lastTimestamp);
          final now = DateTime.now();

          final int missedIntervals = (now.difference(lastScheduledDateTime).inSeconds / const Duration(minutes: 15).inSeconds).floor();

          if (missedIntervals > 0) {
            LogService.logger.i('พบการแจ้งเตือนที่พลาดไปจาก iOS background task: $missedIntervals ครั้ง');
            await _triggerMissedNotifications(missedIntervals);

            final newLastScheduledTime = lastScheduledDateTime.add(Duration(seconds: missedIntervals * const Duration(minutes: 15).inSeconds));
            await prefs.setInt(lastScheduledTimestampKey, newLastScheduledTime.millisecondsSinceEpoch);
          }
        } else {
           LogService.logger.i('iOS task was scheduled but no last timestamp found, resetting.');
           await prefs.setInt(lastScheduledTimestampKey, DateTime.now().millisecondsSinceEpoch);
        }
      }
    }
    return Future.value(true); // ระบุว่า task เสร็จสมบูรณ์
  });
}

// Helper function สำหรับ trigger missed notifications (ย้ายมาอยู่นอก class)
// เนื่องจาก callbackDispatcher ทำงานใน isolate แยก ต้องเข้าถึงฟังก์ชันได้
Future<void> _triggerMissedNotifications(int count) async {
  final prefs = await SharedPreferences.getInstance();
  int currentNotificationId = prefs.getInt(notificationIdCounterKey) ?? 0;

  for (int i = 1; i <= count; i++) {
    currentNotificationId++; // เพิ่ม ID สำหรับแต่ละการแจ้งเตือนย้อนหลัง
    await prefs.setInt(notificationIdCounterKey, currentNotificationId); // บันทึก ID ใหม่

    final String randomMessage = getRandomNotificationMessage();
    await flutterLocalNotificationsPlugin.show(
      currentNotificationId, // ใช้ ID ที่ไม่ซ้ำกัน
      'แจ้งเตือนย้อนหลังที่พลาดไป ($i/$count)',
      randomMessage,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelName,
          channelDescription: channelDescription,
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      payload: 'payload_missed_notification_$currentNotificationId',
    );
    LogService.logger.i('แสดงการแจ้งเตือนย้อนหลังที่พลาดไปครั้งที่ $i, ID: $currentNotificationId');
  }
}

/// ตั้งเวลาการแจ้งเตือนแบบวนซ้ำโดยใช้ Workmanager
///
/// [id]: รหัสเฉพาะสำหรับการแจ้งเตือน
/// [title]: ชื่อเรื่องของการแจ้งเตือน
/// [body]: เนื้อหาของการแจ้งเตือน
/// [payload]: ข้อมูล payload เสริมสำหรับการแจ้งเตือน
/// [interval]: ระยะเวลาระหว่างการแจ้งเตือนแต่ละครั้ง
void schedulePeriodicNotification(
    int id, String title, String body, String payload, Duration interval) {
  Workmanager().registerPeriodicTask(
    "uniqueName_$id", // ชื่อเฉพาะสำหรับ task
    periodicTask, // ชื่อ task ที่กำหนดใน callbackDispatcher
    frequency: interval, // ความถี่ที่ task ควรทำงาน
    initialDelay: interval, // หน่วงเวลาเริ่มต้นก่อนการเรียกใช้ครั้งแรก
    constraints: Constraints(
      networkType: NetworkType.not_required, // ไม่จำเป็นต้องใช้เครือข่าย
    ),
    // เพิ่มการทำงานเมื่อ boot สำหรับ Android
    existingWorkPolicy: ExistingWorkPolicy.replace, // หากมีอยู่แล้ว ให้แทนที่
  );
}

/// แสดงการแจ้งเตือนทดสอบทันที
///
/// [title]: ชื่อเรื่องของการแจ้งเตือน
/// [body]: เนื้อหาของการแจ้งเตือน
Future<void> showTestNotification(String title, String body) async {
  final prefs = await SharedPreferences.getInstance();
  int currentNotificationId = prefs.getInt(notificationIdCounterKey) ?? 0;
  currentNotificationId++;
  await prefs.setInt(notificationIdCounterKey, currentNotificationId);

  await flutterLocalNotificationsPlugin.show(
    currentNotificationId, // ใช้ ID ที่ไม่ซ้ำกัน
    title,
    body,
    const NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: channelDescription,
        importance: Importance.high,
        priority: Priority.high,
      ),
    ),
    payload: 'payload_test_$currentNotificationId',
  );
}

/// ยกเลิกการแจ้งเตือนที่ตั้งเวลาไว้ทั้งหมดและ Workmanager tasks
void cancelAllNotifications() {
  flutterLocalNotificationsPlugin.cancelAll(); // ยกเลิกการแจ้งเตือนในเครื่องทั้งหมด
  Workmanager().cancelAll(); // ยกเลิก Workmanager tasks ทั้งหมด
  // รีเซ็ต ID counter เมื่อยกเลิกทั้งหมด
  SharedPreferences.getInstance().then((prefs) {
    prefs.setInt(notificationIdCounterKey, 0);
  });
}

/// หน้า UI หลักสำหรับจัดการการแจ้งเตือน
class NotificationPage extends StatefulWidget {
  const NotificationPage({super.key});

  @override
  State<NotificationPage> createState() => _NotificationPageState();
}

class _NotificationPageState extends State<NotificationPage> {
  bool _isScheduled = false; // ติดตามว่ามีการตั้งเวลาการแจ้งเตือนแบบวนซ้ำหรือไม่
  final Duration interval = const Duration(minutes: 15); // ช่วงเวลาการแจ้งเตือน

  late int _secondsRemaining; // นับถอยหลังสำหรับการแจ้งเตือนครั้งถัดไป
  Timer? _timer; // Timer สำหรับการนับถอยหลัง

  @override
  void initState() {
    super.initState();
    _secondsRemaining = interval.inSeconds; // เริ่มต้นนับถอยหลังเป็น 15 นาที
    _initializeNotifications(); // เรียกฟังก์ชันเริ่มต้นการแจ้งเตือน
  }

  /// ฟังก์ชันสำหรับเริ่มต้นหรือตรวจสอบสถานะการแจ้งเตือนเมื่อแอปเปิด
  Future<void> _initializeNotifications() async {
    final prefs = await SharedPreferences.getInstance();
    final scheduled = prefs.getBool('isScheduled') ?? false;

    if (!scheduled) {
      // ถ้ายังไม่มีการตั้งเวลาการแจ้งเตือน ให้เริ่มทันที
      await _startNotifications(fromAutoStart: true);
    } else {
      // ถ้ามีการตั้งเวลาอยู่แล้ว ให้ตรวจสอบสถานะและเวลาที่เหลือ
      await _checkScheduledStatus();
    }
  }

  /// ตรวจสอบว่ามีการตั้งเวลาการแจ้งเตือนอยู่ในปัจจุบันจาก SharedPreferences หรือไม่
  /// หากมีการตั้งเวลาไว้ จะเริ่มตัวจับเวลานับถอยหลังและตรวจสอบการแจ้งเตือนที่พลาดไป
  Future<void> _checkScheduledStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final scheduled = prefs.getBool('isScheduled') ?? false;
    if (!mounted) return;

    setState(() {
      _isScheduled = scheduled;
      if (_isScheduled) {
        final lastTimestamp = prefs.getInt(lastScheduledTimestampKey);
        if (lastTimestamp != null) {
          final lastScheduledDateTime = DateTime.fromMillisecondsSinceEpoch(lastTimestamp);
          final now = DateTime.now();

          // คำนวณจำนวนการแจ้งเตือนที่พลาดไป
          final int missedIntervals = (now.difference(lastScheduledDateTime).inSeconds / interval.inSeconds).floor();

          if (missedIntervals > 0) {
            LogService.logger.i('พบการแจ้งเตือนที่พลาดไป: $missedIntervals ครั้ง');
            // เรียก _triggerMissedNotifications ตรงๆ จาก _NotificationPageState
            _triggerMissedNotifications(missedIntervals);

            // อัปเดต lastScheduledTimestampKey ให้เป็นเวลาที่ควรจะมีการแจ้งเตือนครั้งล่าสุดที่ถูกเรียกใช้
            final newLastScheduledTime = lastScheduledDateTime.add(Duration(seconds: missedIntervals * interval.inSeconds));
            prefs.setInt(lastScheduledTimestampKey, newLastScheduledTime.millisecondsSinceEpoch);
          }

          // คำนวณเวลาที่เหลือจนกว่าจะถึงรอบ 15 นาทีถัดไป
          final int remainingSeconds = interval.inSeconds - (now.difference(lastScheduledDateTime).inSeconds % interval.inSeconds);
          _startTimer(remainingSeconds);
        } else {
          // หากไม่มี timestamp (อาจเกิดจากการติดตั้งครั้งแรกหรือข้อมูลหาย) ให้เริ่มจาก 15 นาทีเต็ม
          _startTimer(interval.inSeconds);
        }
      }
    });
  }

  // ย้าย _triggerMissedNotifications ออกไปเป็น top-level function แล้ว
  // เนื่องจากฟังก์ชันนี้ต้องถูกเรียกใช้ได้จาก callbackDispatcher ด้วย

  /// เริ่มตัวจับเวลานับถอยหลังสำหรับการแจ้งเตือนครั้งถัดไป
  ///
  /// [seconds]: จำนวนวินาทีเริ่มต้นสำหรับการนับถอยหลัง
  void _startTimer(int seconds) {
    _timer?.cancel(); // ยกเลิกตัวจับเวลาที่มีอยู่
    setState(() {
      _secondsRemaining = seconds;
    });

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        if (_secondsRemaining > 0) {
          _secondsRemaining--; // ลดวินาที
        } else {
          // รีเซ็ตตัวจับเวลาเมื่อถึงศูนย์ (Workmanager จะจัดการการแจ้งเตือนจริง)
          _secondsRemaining = interval.inSeconds;
        }
      });
    });
  }

  /// หยุดตัวจับเวลานับถอยหลังและรีเซ็ตการแสดงผล
  void _stopTimer() {
    _timer?.cancel(); // ยกเลิกตัวจับเวลา
    setState(() {
      _secondsRemaining = interval.inSeconds; // รีเซ็ตวินาทีเป็นช่วงเวลาเต็ม
    });
  }

  /// จัดการการกระทำเพื่อเริ่มการแจ้งเตือนแบบวนซ้ำ
  /// ตั้งเวลา Workmanager task, แสดงการแจ้งเตือนทันที,
  /// อัปเดต shared preferences และเริ่มตัวจับเวลานับถอยหลัง
  Future<void> _startNotifications({bool fromAutoStart = false}) async {
    // ยกเลิก task เก่าก่อนเริ่มใหม่ เพื่อป้องกันการซ้ำซ้อน
    Workmanager().cancelByUniqueName("uniqueName_0");

    schedulePeriodicNotification(
      0,
      'แจ้งเตือนประจำ',
      'นี่คือการแจ้งเตือนทุก 15 นาที!',
      'payload_data_1',
      interval,
    );

    // ไม่แสดงแจ้งเตือน "เริ่มต้น" เมื่อเป็นการเริ่มอัตโนมัติจากการเปิดแอป
    if (!fromAutoStart) {
      await showTestNotification('แจ้งเตือนเริ่มต้น', 'นี่คือแจ้งเตือนแรก หลังจากเริ่มตั้งเวลา');
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isScheduled', true); // บันทึกสถานะการตั้งเวลา
    // บันทึก timestamp ปัจจุบันเมื่อเริ่มการตั้งเวลา
    await prefs.setInt(lastScheduledTimestampKey, DateTime.now().millisecondsSinceEpoch);

    if (!mounted) return;
    setState(() {
      _isScheduled = true;
    });

    _startTimer(interval.inSeconds); // เริ่มตัวจับเวลาสำหรับการแจ้งเตือนครั้งถัดไป

    if (!fromAutoStart) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('เริ่มแจ้งเตือนทุก 15 นาทีแล้ว!')),
      );
    }
  }

  /// จัดการการกระทำเพื่อหยุดการแจ้งเตือนทั้งหมด
  /// ยกเลิกการแจ้งเตือนในเครื่องทั้งหมดและ Workmanager tasks,
  /// อัปเดต shared preferences และหยุดตัวจับเวลานับถอยหลัง
  void _stopNotifications() async {
    cancelAllNotifications();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isScheduled', false); // บันทึกสถานะการตั้งเวลา
    // ลบ timestamp เมื่อหยุดการตั้งเวลา
    await prefs.remove(lastScheduledTimestampKey);

    _stopTimer(); // หยุดและรีเซ็ตตัวจับเวลา

    if (!mounted) return;
    setState(() {
      _isScheduled = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('หยุดแจ้งเตือนทั้งหมดแล้ว!')),
    );
  }

  /// แสดงการแจ้งเตือนทดสอบทันทีเมื่อกดปุ่ม
  void _testImmediateNotification() {
    showTestNotification('ทดสอบทันที', 'นี่คือแจ้งเตือนที่กดแล้วขึ้นทันที');
  }

  @override
  void dispose() {
    _timer?.cancel(); // ยกเลิกตัวจับเวลาเมื่อ widget ถูกทิ้ง
    super.dispose();
  }

  /// จัดรูปแบบวินาทีที่เหลือเป็นสตริง "MM:SS"
  String get formattedTime {
    final m = (_secondsRemaining ~/ 60).toString().padLeft(2, '0');
    final s = (_secondsRemaining % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ตั้งค่าการแจ้งเตือน')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'จัดการการแจ้งเตือนอัตโนมัติ',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 30),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ElevatedButton.icon(
                  onPressed: _isScheduled ? null : () => _startNotifications(),
                  icon: const Icon(Icons.notifications_active),
                  label: const Text('เริ่มแจ้งเตือนทุก 15 นาที'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                    textStyle: const TextStyle(fontSize: 18),
                  ),
                ),
                // แสดงเวลาถอยหลังเฉพาะเมื่อมีการตั้งเวลาการแจ้งเตือน
                if (_isScheduled) ...[
                  const SizedBox(height: 10),
                  Text(
                    'เวลานับถอยหลังแจ้งเตือนถัดไป: $formattedTime',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _isScheduled ? _stopNotifications : null,
              icon: const Icon(Icons.notifications_off),
              label: const Text('หยุดแจ้งเตือนทั้งหมด'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                textStyle: const TextStyle(fontSize: 18),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _testImmediateNotification,
              icon: const Icon(Icons.bolt),
              label: const Text('ทดสอบแจ้งเตือนทันที'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                textStyle: const TextStyle(fontSize: 18),
              ),
            ),
            const SizedBox(height: 30),
            Text(
              _isScheduled
                  ? 'สถานะ: กำลังแจ้งเตือนทุก 15 นาที'
                  : 'สถานะ: ยังไม่มีการตั้งเวลาแจ้งเตือน',
              style: TextStyle(
                fontSize: 16,
                color: _isScheduled ? Colors.green : Colors.grey[700],
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            const Text(
              'Test Service Background',
              style: TextStyle(fontSize: 25, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}