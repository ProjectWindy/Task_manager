import 'package:flutter/foundation.dart';
import '../database/database_helper.dart';
import '../models/task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'dart:io';

class TaskProvider with ChangeNotifier {
  final DatabaseHelper _databaseHelper = DatabaseHelper();
  List<Task> _tasks = [];
  List<Task> _filteredTasks = [];
  bool _showOnlyIncomplete = false;
  String _searchQuery = '';
  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  // Thời gian thông báo mặc định
  int notificationHour = 9;
  int notificationMinute = 0;
  int notificationDaysBefore = 1;

  // Phương thức để cập nhật thời gian thông báo
  void updateNotificationTime(int hour, int minute, int daysBefore) {
    notificationHour = hour;
    notificationMinute = minute;
    notificationDaysBefore = daysBefore;
    notifyListeners();
  }

  TaskProvider() {
    _initializeNotifications();
    loadTasks();
  }

  List<Task> get tasks => _tasks;
  List<Task> get filteredTasks => _filteredTasks;
  bool get showOnlyIncomplete => _showOnlyIncomplete;
  String get searchQuery => _searchQuery;

  Future<void> _initializeNotifications() async {
    // Khởi tạo timezone và đặt múi giờ địa phương
    tz.initializeTimeZones();

    // Đặt múi giờ Việt Nam
    try {
      tz.setLocalLocation(tz.getLocation('Asia/Ho_Chi_Minh'));
      debugPrint('Timezone set to Asia/Ho_Chi_Minh');
    } catch (e) {
      debugPrint('Error setting timezone: $e');
      // Nếu không đặt được múi giờ cụ thể, sử dụng múi giờ mặc định
      tz.setLocalLocation(tz.local);
      final now = DateTime.now();
      debugPrint(
          'Using local timezone: ${now.timeZoneName} (UTC${now.timeZoneOffset.isNegative ? '' : '+'}${now.timeZoneOffset.inHours})');
    }

    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    final DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings(
      requestSoundPermission: true,
      requestBadgePermission: true,
      requestAlertPermission: true,
      onDidReceiveLocalNotification:
          (int id, String? title, String? body, String? payload) async {
        // Handle iOS foreground notification
      },
    );

    final InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) async {
        debugPrint('Notification tapped: ${response.payload}');
        if (response.payload != null) {
          final taskId = int.tryParse(response.payload!);
          if (taskId != null) {
            if (response.actionId == 'mark_completed') {
              // Tìm task trong danh sách
              final task = _tasks.firstWhere(
                (task) => task.id == taskId,
                orElse: () => Task(title: '', dueDate: null),
              );
              if (task.id != null) {
                // Đánh dấu task là hoàn thành
                await toggleTaskStatus(task);
                debugPrint('Task marked as completed from notification');
              }
            }
          }
        }
      },
    );

    // Create notification channel for Android
    if (Platform.isAndroid) {
      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        'task_manager_channel',
        'Task Manager',
        description: 'Task due date notifications',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        enableLights: true,
        showBadge: true,
      );

      await _notifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);

      // Request permissions
      final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
          _notifications.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();

      if (androidImplementation != null) {
        // Kiểm tra và yêu cầu quyền thông báo
        final bool? hasPermission =
            await androidImplementation.areNotificationsEnabled();
        debugPrint('Notifications permission status: $hasPermission');

        if (hasPermission != true) {
          await androidImplementation.requestNotificationsPermission();
          debugPrint('Requested notification permission');
        }

        // Kiểm tra và yêu cầu quyền exact alarms
        try {
          final bool? hasExactAlarmPermission =
              await androidImplementation.canScheduleExactNotifications();
          debugPrint(
              'Exact alarms permission status: $hasExactAlarmPermission');

          if (hasExactAlarmPermission != true) {
            await androidImplementation.requestExactAlarmsPermission();
            debugPrint('Requested exact alarms permission');
          }
        } catch (e) {
          debugPrint('Error checking/requesting exact alarms permission: $e');
        }
      }
    }
  }

  Future<void> _scheduleTaskNotification(Task task) async {
    if (task.dueDate == null || task.status == 1) {
      debugPrint(
          'Not scheduling notification: task has no due date or is completed');
      return;
    }

    final now = tz.TZDateTime.now(tz.local);
    debugPrint('Current time: ${now.toLocal()}');

    // Lấy ngày đến hạn
    final dueDate = task.dueDate!;
    debugPrint('Task due date (local): ${dueDate.toLocal()}');

    // Chuyển đổi sang TZDateTime với múi giờ địa phương
    final dueDateTime = tz.TZDateTime(
      tz.local,
      dueDate.year,
      dueDate.month,
      dueDate.day,
      notificationHour, // Sử dụng giờ đã cấu hình
      notificationMinute, // Sử dụng phút đã cấu hình
    );
    debugPrint('Due date time (TZ): ${dueDateTime.toLocal()}');

    // Tính số ngày còn lại đến deadline (chỉ so sánh ngày, không so sánh giờ)
    final daysUntilDue = dueDateTime.difference(now).inDays;
    debugPrint('Days until due: $daysUntilDue');

    // Chỉ không lên lịch thông báo nếu task đã quá hạn quá 1 ngày
    if (daysUntilDue < -1) {
      debugPrint(
          'Task is overdue by more than 1 day, not scheduling notification');
      return;
    }

    tz.TZDateTime scheduledDate;

    // Logic lựa chọn thời gian thông báo
    if (daysUntilDue <= 0) {
      // Nếu đến hạn trong ngày hôm nay hoặc đã quá hạn 1 ngày
      scheduledDate = tz.TZDateTime(
        tz.local,
        now.year,
        now.month,
        now.day,
        notificationHour,
        notificationMinute,
      );

      // Nếu thời gian thông báo đã qua trong ngày hôm nay
      if (scheduledDate.isBefore(now)) {
        scheduledDate = now.add(const Duration(minutes: 1));
        debugPrint(
            'Due today, sending notification in 1 minute: ${scheduledDate.toLocal()}');
      } else {
        debugPrint(
            'Scheduling notification for today at configured time: ${scheduledDate.toLocal()}');
      }
    } else if (daysUntilDue <= notificationDaysBefore) {
      // Nếu trong khoảng thời gian thông báo
      scheduledDate = tz.TZDateTime(
        tz.local,
        now.year,
        now.month,
        now.day,
        notificationHour,
        notificationMinute,
      );

      // Nếu thời gian thông báo đã qua trong ngày hôm nay
      if (scheduledDate.isBefore(now)) {
        scheduledDate = now.add(const Duration(minutes: 1));
        debugPrint(
            'Today\'s notification time has passed, sending notification in 1 minute: ${scheduledDate.toLocal()}');
      } else {
        debugPrint(
            'Scheduling notification for today at configured time: ${scheduledDate.toLocal()}');
      }
    } else {
      // Thông báo trước ngày đến hạn theo số ngày đã cấu hình
      scheduledDate = tz.TZDateTime(
        tz.local,
        dueDate.year,
        dueDate.month,
        dueDate.day - notificationDaysBefore,
        notificationHour,
        notificationMinute,
      );

      // Nếu ngày thông báo đã qua
      if (scheduledDate.isBefore(now)) {
        // Lên lịch thông báo vào thời gian đã cấu hình của ngày hôm nay
        scheduledDate = tz.TZDateTime(
          tz.local,
          now.year,
          now.month,
          now.day,
          notificationHour,
          notificationMinute,
        );

        // Nếu thời gian thông báo đã qua trong ngày hôm nay
        if (scheduledDate.isBefore(now)) {
          scheduledDate = now.add(const Duration(minutes: 1));
          debugPrint(
              'Adjusted notification to immediate: ${scheduledDate.toLocal()}');
        } else {
          debugPrint(
              'Adjusted notification to today at configured time: ${scheduledDate.toLocal()}');
        }
      } else {
        debugPrint(
            'Scheduling notification for ${notificationDaysBefore} days before due date: ${scheduledDate.toLocal()}');
      }
    }

    debugPrint('Final scheduled notification time: ${scheduledDate.toLocal()}');

    final androidDetails = AndroidNotificationDetails(
      'task_manager_channel',
      'Task Manager',
      channelDescription: 'Task due date notifications',
      importance: Importance.max,
      priority: Priority.max,
      enableLights: true,
      ledColor: Colors.blue,
      ledOnMs: 1000,
      ledOffMs: 500,
      playSound: true,
      enableVibration: true,
      visibility: NotificationVisibility.public,
      category: AndroidNotificationCategory.reminder,
      fullScreenIntent: true,
      channelShowBadge: true,
      autoCancel: true,
      ongoing: false,
      actions: <AndroidNotificationAction>[
        const AndroidNotificationAction(
          'mark_completed',
          'Hoàn thành',
          showsUserInterface: false,
          cancelNotification: true,
        ),
      ],
    );

    final notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        sound: 'notification_sound',
        badgeNumber: 1,
        threadIdentifier: 'task_notifications',
      ),
    );

    try {
      // Cancel any existing notifications for this task
      await _notifications.cancel(task.id ?? 0);
      await _notifications.cancel((task.id ?? 0) + 1000); // Cancel 10s reminder
      await _notifications.cancel((task.id ?? 0) + 2000); // Cancel 30s reminder

      String notificationMessage;
      if (daysUntilDue <= 0) {
        notificationMessage = 'Task "${task.title}" đến hạn hôm nay!';
      } else if (daysUntilDue == 1) {
        notificationMessage = 'Task "${task.title}" đến hạn ngày mai!';
      } else {
        notificationMessage =
            'Task "${task.title}" đến hạn sau $daysUntilDue ngày (${DateFormat('dd/MM/yyyy').format(task.dueDate!)})';
      }

      if (task.description != null && task.description!.isNotEmpty) {
        notificationMessage += '\nMô tả: ${task.description}';
      }

      // Schedule the main notification
      await _notifications.zonedSchedule(
        task.id ?? 0,
        'Nhắc nhở Task',
        notificationMessage,
        scheduledDate,
        notificationDetails,
        androidScheduleMode: AndroidScheduleMode.alarmClock,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: task.id.toString(),
      );

      // Schedule 10-second reminder
      final tenSecondsBefore =
          scheduledDate.subtract(const Duration(seconds: 10));
      if (tenSecondsBefore.isAfter(now)) {
        await _notifications.zonedSchedule(
          (task.id ?? 0) + 1000,
          'Nhắc nhở Task (10s)',
          'Còn 10 giây nữa: $notificationMessage',
          tenSecondsBefore,
          notificationDetails,
          androidScheduleMode: AndroidScheduleMode.alarmClock,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          payload: task.id.toString(),
        );
      }

      // Schedule 30-second reminder
      final thirtySecondsBefore =
          scheduledDate.subtract(const Duration(seconds: 30));
      if (thirtySecondsBefore.isAfter(now)) {
        await _notifications.zonedSchedule(
          (task.id ?? 0) + 2000,
          'Nhắc nhở Task (30s)',
          'Còn 30 giây nữa: $notificationMessage',
          thirtySecondsBefore,
          notificationDetails,
          androidScheduleMode: AndroidScheduleMode.alarmClock,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          payload: task.id.toString(),
        );
      }

      debugPrint('Notifications scheduled successfully:');
      debugPrint('Task ID: ${task.id}');
      debugPrint('Task Title: ${task.title}');
      debugPrint('Due Date: ${task.dueDate!.toLocal()}');
      debugPrint('Main Notification Time: ${scheduledDate.toLocal()}');
      debugPrint('10s Reminder Time: ${tenSecondsBefore.toLocal()}');
      debugPrint('30s Reminder Time: ${thirtySecondsBefore.toLocal()}');
      debugPrint('Message: $notificationMessage');
    } catch (e) {
      debugPrint('Error scheduling notifications: $e');
    }
  }

  Future<void> loadTasks() async {
    final tasks = await _databaseHelper.getTasks();
    _tasks = tasks.map((map) => Task.fromMap(map)).toList();
    _filterTasks();
    notifyListeners();
  }

  void setShowOnlyIncomplete(bool value) {
    _showOnlyIncomplete = value;
    _filterTasks();
    notifyListeners();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    _filterTasks();
    notifyListeners();
  }

  void _filterTasks() {
    _filteredTasks = _tasks.where((task) {
      final matchesSearch =
          task.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
              (task.description?.toLowerCase() ?? '')
                  .contains(_searchQuery.toLowerCase());
      final matchesFilter = !_showOnlyIncomplete || task.status == 0;
      return matchesSearch && matchesFilter;
    }).toList();
  }

  Future<void> addTask(Task task) async {
    final id = await _databaseHelper.insertTask(task.toMap());

    // Tạo task mới với ID đã được cấp
    final newTask = Task(
      id: id,
      title: task.title,
      description: task.description,
      dueDate: task.dueDate,
      status: task.status,
      notificationTime: task.notificationTime,
      notificationDaysBefore: task.notificationDaysBefore,
    );

    // Thêm task mới vào danh sách
    _tasks.add(newTask);
    _filterTasks();
    notifyListeners();

    // Lên lịch thông báo cho task mới
    await _scheduleTaskNotification(newTask);
  }

  Future<void> updateTask(Task task) async {
    await _databaseHelper.updateTask(task.toMap());
    // Hủy thông báo cũ
    if (task.id != null) {
      await _notifications.cancel(task.id!);
    }
    // Lên lịch thông báo mới
    await _scheduleTaskNotification(task);
    await loadTasks();
  }

  Future<void> deleteTask(Task task) async {
    if (task.id != null) {
      await _databaseHelper.deleteTask(task.id!);
      await _notifications.cancel(task.id!);
    }
    await loadTasks();
  }

  Future<void> toggleTaskStatus(Task task) async {
    final newStatus = task.status == 0 ? 1 : 0;
    if (task.id != null) {
      await _databaseHelper.toggleTaskStatus(task.id!, newStatus);

      if (newStatus == 1) {
        // Nếu hoàn thành, hủy thông báo
        await _notifications.cancel(task.id!);
      } else {
        // Nếu đánh dấu là chưa hoàn thành, lên lịch lại thông báo
        final updatedTask = task.copyWith(status: newStatus);
        await _scheduleTaskNotification(updatedTask);
      }
    }
    await loadTasks();
  }

  // Phương thức kiểm tra thông báo với nhiều mức độ trễ
  Future<void> testNotifications() async {
    final now = DateTime.now();
    debugPrint('Current device time: $now');
    debugPrint('Current timezone: ${tz.local}');

    // Gửi thông báo cho tất cả các task chưa hoàn thành
    for (var task in _tasks) {
      if (task.status == 0 && task.dueDate != null) {
        try {
          String notificationMessage;
          final daysUntilDue = task.dueDate!.difference(now).inDays;

          if (daysUntilDue <= 0) {
            notificationMessage = 'Task "${task.title}" đến hạn hôm nay!';
          } else if (daysUntilDue == 1) {
            notificationMessage = 'Task "${task.title}" đến hạn ngày mai!';
          } else {
            notificationMessage =
                'Task "${task.title}" đến hạn sau $daysUntilDue ngày (${DateFormat('dd/MM/yyyy').format(task.dueDate!)})';
          }

          if (task.description != null && task.description!.isNotEmpty) {
            notificationMessage += '\nMô tả: ${task.description}';
          }

          // Thêm delay nhỏ giữa các thông báo để tránh chồng chéo
          await Future.delayed(const Duration(milliseconds: 500));

          await _notifications.show(
            task.id ?? 0,
            'Nhắc nhở Task',
            notificationMessage,
            NotificationDetails(
              android: AndroidNotificationDetails(
                'task_manager_channel',
                'Task Manager',
                channelDescription: 'Channel for testing notifications',
                importance: Importance.max,
                priority: Priority.high,
                enableLights: true,
                ledColor: Colors.blue,
                ledOnMs: 1000,
                ledOffMs: 500,
                playSound: true,
                enableVibration: true,
                visibility: NotificationVisibility.public,
                category: AndroidNotificationCategory.reminder,
                fullScreenIntent: true,
                channelShowBadge: true,
                autoCancel: true,
                ongoing: false,
                actions: <AndroidNotificationAction>[
                  const AndroidNotificationAction(
                    'mark_completed',
                    'Hoàn thành',
                    showsUserInterface: false,
                    cancelNotification: true,
                  ),
                ],
              ),
              iOS: const DarwinNotificationDetails(
                presentAlert: true,
                presentBadge: true,
                presentSound: true,
                sound: 'notification_sound',
                badgeNumber: 1,
                threadIdentifier: 'task_notifications',
              ),
            ),
            payload: task.id.toString(),
          );
          debugPrint('Sent notification for task: ${task.title}');
        } catch (e) {
          debugPrint('Error sending notification for task ${task.title}: $e');
        }
      }
    }
  }
}
