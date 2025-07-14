# ข้อดี–ข้อเสียของ flutter_local_notifications

## ข้อดี

รองรับทั้ง Android และ iOS แบบ native (Local notifications)
ตั้งเวลา (schedule) แจ้งเตือนได้ทั้งแบบครั้งเดียวและแบบซ้ำ (periodic)
ปรับแต่งหน้าตาได้เยอะ (icon, sound, vibration, payload)
ไม่ต้องพึ่ง service ภายนอก ติดตั้งง่ายผ่าน pub.dev

## ข้อเสีย

เมื่อแอปถูก kill หรือ device รีบูท จำเป็นต้องรี–schedule notification ใหม่
แต่ละแพลตฟอร์มมี API และข้อจำกัดต่างกัน (เช่น Android 12+ ต้องจัดการ notification channel ให้ละเอียด)
ไม่เหมาะกับงาน background ที่ต้องรัน logic นาน ๆ เพราะออกแบบมาเฉพาะการแจ้งเตือนเท่านั้น

# ข้อดี–ข้อเสียของ workmanager

## ข้อดี

รันงาน background ได้แม้แอปจะถูกปิด (headless execution)
รองรับงานแบบ periodic, one-off, และสั่งรันทันที
ใช้ Android WorkManager และ iOS BGTaskScheduler/Cron นำมา wrapper ให้ใช้ง่ายใน Flutter
เหมาะกับงานซิงก์ข้อมูล, cleanup, หรือส่ง log เป็นระยะ

## ข้อเสีย

iOS จำกัดระยะเวลาให้ทำงาน (max ~30s) และไม่มีรับประกันว่ารันครบทุกครั้ง
ต้องตั้งค่า native (AndroidManifest, AppDelegate) เพิ่มเติม
Debug ยากกว่าปกติ เพราะ task รันนอก context หลักของแอป
ถ้างานซับซ้อนต้องระวังเรื่อง isolate และ serialization ของข้อมูลส่งเข้า–ออก
การเลือกใช้ทั้งสองขึ้นกับความต้องการ:

ถ้าเน้นแค่แจ้งเตือนในช่วงเวลาที่กำหนด ใช้ flutter_local_notifications
ถ้าต้องการรันโค้ดพื้นหลังเป็นระยะ (data sync / cleanup) ให้พิจารณา workmanager
