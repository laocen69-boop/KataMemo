library;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'version.dart' show kAppName;

class NotificationService {
  static const _channelId = 'study_reminder';
  static const _dailyId = 1001;
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static bool _inited = false;
  static bool _enabled = true;

  static const _androidDetails = AndroidNotificationDetails(
    _channelId,
    '学习提醒',
    channelDescription: '每天 21:00 未完成学习时提醒',
    importance: Importance.high,
    priority: Priority.high,
  );

  static Future<void> setEnabled(bool v) async {
    _enabled = v;
    try {
      if (!v) {
        await _plugin.cancel(id: _dailyId);
      } else {
        await scheduleDailyReminder();
      }
    } catch (_) {}
  }

  static Future<void> init({bool enabled = true}) async {
    if (_inited) return;
    _inited = true;
    _enabled = enabled;
    tzdata.initializeTimeZones();
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (_) {
      tz.setLocalLocation(tz.getLocation('Asia/Shanghai'));
    }
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_notification'),

        iOS: DarwinInitializationSettings(),
      ),
    );
    final androidImpl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.requestNotificationsPermission();
    await androidImpl?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        '学习提醒',
        description: '每天 21:00 未完成学习时提醒',
        importance: Importance.high,
      ),
    );
    if (_enabled) {
      await scheduleDailyReminder();
    }
  }

  static Future<void> scheduleDailyReminder() async {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, 21, 0);
    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    await _plugin.zonedSchedule(
      id: _dailyId,
      title: '$kAppName · 今日学习提醒',
      body: '今天的印尼语单词还没复习完，记得完成学习再打卡哦～',
      scheduledDate: scheduled,
      notificationDetails: const NotificationDetails(
          android: _androidDetails, iOS: DarwinNotificationDetails()),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }
}
