import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:intl/intl.dart';
import '../database/db_helper.dart';
import '../providers/task_provider.dart';
import '../l10n/strings.dart';

class AlarmScreen extends StatefulWidget {
  final int taskId;
  const AlarmScreen({super.key, required this.taskId});

  @override
  State<AlarmScreen> createState() => _AlarmScreenState();
}

class _AlarmScreenState extends State<AlarmScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  String _taskTitle = 'لوڈ ہو رہا ہے...';
  TaskItem? _task;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTask();

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.25).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _loadTask() async {
    final db = await DatabaseHelper.instance.database;
    final List<Map<String, dynamic>> result = await db.query(
      'tasks',
      where: 'id = ?',
      whereArgs: [widget.taskId],
    );

    if (result.isNotEmpty) {
      setState(() {
        _task = TaskItem.fromMap(result.first);
        _taskTitle = _task!.title;
        _isLoading = false;
      });
    } else {
      setState(() {
        _taskTitle = 'نامعلوم سرگرمی';
        _isLoading = false;
      });
    }
  }

  Future<void> _completeTask() async {
    final db = await DatabaseHelper.instance.database;
    await db.update(
      'tasks',
      {'is_completed': 1},
      where: 'id = ?',
      whereArgs: [widget.taskId],
    );

    // Cancel all notifications for this task (main + reminders)
    final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
    for (int i = 0; i < 10; i++) {
      await flutterLocalNotificationsPlugin.cancel(widget.taskId * 10 + i);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'زرعی کام مکمل نشان زد کر دیا گیا ہے!',
            style: TextStyle(fontSize: 16),
          ),
          backgroundColor: Colors.green,
        ),
      );

      // Update TaskProvider
      try {
        context.read<TaskProvider>().fetchTasks();
      } catch (e) {
        debugPrint('Could not refresh provider: $e');
      }

      Navigator.of(context).pop();
    }
  }

  Future<void> _dismissAlarm() async {
    // Cancel all active notifications for this task to stop sound/vibrate
    final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
    for (int i = 0; i < 10; i++) {
      await flutterLocalNotificationsPlugin.cancel(widget.taskId * 10 + i);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'الارم بند کر دیا گیا ہے',
            style: TextStyle(fontSize: 16),
          ),
          backgroundColor: Colors.blueGrey,
        ),
      );
      Navigator.of(context).pop();
    }
  }

  Future<void> _snoozeTask(int minutes) async {
    // 1. Cancel notifications for this task ID (slots 0 to 9)
    final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
    for (int i = 0; i < 10; i++) {
      await flutterLocalNotificationsPlugin.cancel(widget.taskId * 10 + i);
    }

    final snoozeTime = DateTime.now().add(Duration(minutes: minutes));

    // Update database with snooze time
    final db = await DatabaseHelper.instance.database;
    await db.update(
      'tasks',
      {'snoozed_until': snoozeTime.toIso8601String()},
      where: 'id = ?',
      whereArgs: [widget.taskId],
    );

    // Refresh TaskProvider tasks to update UI immediately
    try {
      if (mounted) {
        context.read<TaskProvider>().fetchTasks();
      }
    } catch (_) {}

    // 2. Schedule snooze notification
    tz.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation('Asia/Karachi'));
    } catch (e) {
      debugPrint('Failed to set timezone in snooze: $e');
    }

    await flutterLocalNotificationsPlugin.zonedSchedule(
      widget.taskId * 10 + 9, // Slot 9 for snooze
      'کسان دوست - یاد دہانی (سوز)',
      _taskTitle,
      tz.TZDateTime.from(snoozeTime, tz.local),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'kisan_dost_alarm_channel_v7',
          'Farming Alarms',
          channelDescription: 'Loud farming task reminders',
          importance: Importance.max,
          priority: Priority.high,
          sound: RawResourceAndroidNotificationSound('farming_alarm'),
          playSound: true,
          ongoing: true,
          autoCancel: false,
          fullScreenIntent: true,
          category: AndroidNotificationCategory.alarm,
          visibility: NotificationVisibility.public,
          actions: <AndroidNotificationAction>[
            AndroidNotificationAction(
              'action_complete',
              Strings.done,
              showsUserInterface: false,
            ),
            AndroidNotificationAction(
              'action_snooze',
              'سوز کریں (10 منٹ)',
              showsUserInterface: false,
            ),
          ],
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: widget.taskId.toString(),
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'الارم $minutes منٹ کے لیے ٹال دیا گیا ہے',
            style: const TextStyle(fontSize: 16),
          ),
          backgroundColor: Colors.orange.shade800,
        ),
      );

      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.green.shade900,
              Colors.green.shade600,
              Colors.teal.shade800,
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 24.0,
              vertical: 32.0,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Top Header Text
                Column(
                  children: [
                    const SizedBox(height: 20),
                    const Text(
                      'کسان دوست الارم',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'اہم زرعی سرگرمی کا وقت ہو گیا ہے!',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.yellow.shade400,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Jameel Noori Nastaleeq',
                      ),
                    ),
                  ],
                ),

                // Pulsating Alarm Icon Container
                Column(
                  children: [
                    ScaleTransition(
                      scale: _scaleAnimation,
                      child: Container(
                        padding: const EdgeInsets.all(28),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.3),
                            width: 3,
                          ),
                        ),
                        child: const Icon(
                          Icons.notifications_active,
                          size: 70,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                    // Task Title and Details Card
                    Card(
                      elevation: 8,
                      color: Colors.white.withValues(alpha: 0.95),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24.0,
                          vertical: 20.0,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.agriculture,
                              size: 36,
                              color: Colors.green,
                            ),
                            const SizedBox(height: 12),
                            // Task Title
                            Text(
                              _taskTitle,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.black87,
                                fontSize: 26,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Jameel Noori Nastaleeq',
                              ),
                            ),
                            if (_task?.description != null &&
                                _task!.description!.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              // Description
                              Text(
                                _task!.description!,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.grey.shade700,
                                  fontSize: 16,
                                  fontFamily: 'Jameel Noori Nastaleeq',
                                ),
                              ),
                            ],
                            const Divider(height: 24, thickness: 1),
                            // Scheduled Date and Time
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.access_time,
                                  size: 18,
                                  color: Colors.grey.shade700,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _task != null
                                      ? DateFormat(
                                        'dd MMM yyyy hh:mm a',
                                      ).format(_task!.dateTime)
                                      : '',
                                  style: TextStyle(
                                    color: Colors.grey.shade800,
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            // Recurrence status
                            Text(
                              _task != null
                                  ? (_task!.recurrence == 'daily'
                                      ? 'دوبارہ یاد دہانی: روزانہ دہرایا جائے گا'
                                      : _task!.recurrence == 'weekly'
                                      ? 'دوبارہ یاد دہانی: ہفتہ وار دہرایا جائے گا'
                                      : 'دوبارہ یاد دہانی: بغیر دہرائے')
                                  : '',
                              style: TextStyle(
                                color: Colors.deepPurple.shade700,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                fontFamily: 'Jameel Noori Nastaleeq',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),

                // Bottom Action Buttons
                Column(
                  children: [
                    // Big Green "Completed" Button
                    SizedBox(
                      width: double.infinity,
                      height: 64,
                      child: ElevatedButton.icon(
                        onPressed: _isLoading ? null : _completeTask,
                        icon: const Icon(
                          Icons.check_circle_outline,
                          size: 28,
                          color: Colors.white,
                        ),
                        label: const Text(
                          'کام مکمل ہو گیا',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green.shade500,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          elevation: 4,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Big Dark Grey "Dismiss" Button
                    SizedBox(
                      width: double.infinity,
                      height: 60,
                      child: ElevatedButton.icon(
                        onPressed: _isLoading ? null : _dismissAlarm,
                        icon: const Icon(
                          Icons.alarm_off,
                          size: 26,
                          color: Colors.white,
                        ),
                        label: const Text(
                          'الارم بند کریں (ڈسمس)',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueGrey.shade700,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          elevation: 4,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Snooze row title
                    const Text(
                      'سوز کے اختیارات:',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Snooze row
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 50,
                            child: ElevatedButton(
                              onPressed:
                                  _isLoading ? null : () => _snoozeTask(5),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white.withValues(
                                  alpha: 0.2,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  side: const BorderSide(
                                    color: Colors.white54,
                                    width: 1.5,
                                  ),
                                ),
                                elevation: 0,
                              ),
                              child: const Text(
                                '۵ منٹ',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: SizedBox(
                            height: 50,
                            child: ElevatedButton(
                              onPressed:
                                  _isLoading ? null : () => _snoozeTask(10),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white.withValues(
                                  alpha: 0.2,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  side: const BorderSide(
                                    color: Colors.white54,
                                    width: 1.5,
                                  ),
                                ),
                                elevation: 0,
                              ),
                              child: const Text(
                                '۱۰ منٹ',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: SizedBox(
                            height: 50,
                            child: ElevatedButton(
                              onPressed:
                                  _isLoading ? null : () => _snoozeTask(15),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white.withValues(
                                  alpha: 0.2,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  side: const BorderSide(
                                    color: Colors.white54,
                                    width: 1.5,
                                  ),
                                ),
                                elevation: 0,
                              ),
                              child: const Text(
                                '۱۵ منٹ',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
