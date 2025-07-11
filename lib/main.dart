import 'package:flutter/material.dart';
import 'package:workmanager/workmanager.dart';
import 'notification_manager.dart'; // Import the notification_manager.dart file

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeNotificationService(); // Initialize Notification Service and request permissions

  Workmanager().initialize(
    callbackDispatcher, // Background callback function
    isInDebugMode: false, // true for testing
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Notification Demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const NotificationPage(), // Use the NotificationPage from notification_manager.dart
    );
  }
}
