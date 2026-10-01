import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import '../providers/task_provider.dart';
import '../widgets/empty_state_widget.dart';
import 'task_form_screen.dart';
import '../l10n/strings.dart';

class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) {
        context.read<TaskProvider>().fetchTasks();
      }
    });

    // Tick every 10 seconds to update countdowns and status in real-time
    _timer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _formatDateTime(DateTime dt) {
    return DateFormat('dd MMM yyyy, hh:mm a').format(dt);
  }

  String _getRecurrenceUrdu(String recurrence) {
    switch (recurrence) {
      case 'daily':
        return 'روزانہ';
      case 'weekly':
        return 'ہفتہ وار';
      default:
        return 'ایک بار';
    }
  }

  String _getRemindersUrdu(String reminders) {
    final offsets = reminders.split(',').map((e) => int.tryParse(e.trim())).whereType<int>().toList();
    final List<String> list = [];
    if (offsets.contains(0)) list.add('وقت پر');
    if (offsets.contains(60)) list.add('1 گھنٹہ پہلے');
    if (offsets.contains(1440)) list.add('1 دن پہلے');
    return list.isEmpty ? 'وقت پر' : list.join('، ');
  }

  Widget _buildStatsHeader(List<TaskItem> tasks) {
    final total = tasks.length;
    final completed = tasks.where((t) => t.isCompleted).length;
    final pending = total - completed;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.deepPurple.shade700, Colors.deepPurple.shade500],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.deepPurple.withValues(alpha: 0.35),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatItem('کل سرگرمیاں', total.toString(), Icons.playlist_add_check, Colors.white),
          Container(width: 1.5, height: 40, color: Colors.white24),
          _buildStatItem('مکمل', completed.toString(), Icons.check_circle_rounded, Colors.greenAccent),
          Container(width: 1.5, height: 40, color: Colors.white24),
          _buildStatItem('باقی', pending.toString(), Icons.pending_actions, Colors.yellowAccent),
        ],
      ),
    );
  }

  Widget _buildStatItem(String title, String count, IconData icon, Color iconColor) {
    return Column(
      children: [
        Icon(icon, size: 28, color: iconColor),
        const SizedBox(height: 6),
        Text(
          count,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        const SizedBox(height: 2),
        Text(
          title,
          style: const TextStyle(fontSize: 15, color: Colors.white70, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  Widget _getStatusBadge({required String label, required Color bgColor, required Color textColor}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.bold),
      ),
    );
  }


  String _getCountdownText(DateTime dateTime) {
    final now = DateTime.now();
    if (dateTime.isBefore(now)) {
      return 'ڈیو (ابھی کریں)';
    }
    final difference = dateTime.difference(now);
    if (difference.inDays >= 1) {
      return '${difference.inDays} دن میں شروع ہوگا';
    } else if (difference.inHours >= 1) {
      return '${difference.inHours} گھنٹے میں شروع ہوگا';
    } else if (difference.inMinutes >= 1) {
      return '${difference.inMinutes} منٹ میں شروع ہوگا';
    } else {
      return 'ابھی وقت ہے';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('کام کی منصوبہ بندی'),
        backgroundColor: Colors.deepPurple.shade600,
        foregroundColor: Colors.white,
      ),
      body: Consumer<TaskProvider>(
        builder: (context, taskProvider, child) {
          if (taskProvider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          final tasks = taskProvider.tasks;
          final now = DateTime.now();

          if (tasks.isEmpty) {
            return RefreshIndicator(
              onRefresh: () async {
                await taskProvider.fetchTasks();
              },
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: SizedBox(
                  height: MediaQuery.of(context).size.height * 0.8,
                  child: const EmptyStateWidget(
                    imageAsset: 'assets/images/farmer.png',
                    message: 'آپ نے ابھی تک کوئی کام شیڈول نہیں کیا۔',
                    subtitle: 'آئیں اپنی اگلی زرعی سرگرمی شامل کریں۔',
                    fallbackIcon: Icons.checklist,
                  ),
                ),
              ),
            );
          }

          bool isSameDay(DateTime a, DateTime b) {
            return a.year == b.year && a.month == b.month && a.day == b.day;
          }

          // Real-time categorization
          final completedTasks = tasks.where((t) => t.isCompleted).toList();
          final overdueTasks = tasks.where((t) => !t.isCompleted && t.dateTime.isBefore(now) && (t.snoozedUntil == null || t.snoozedUntil!.isBefore(now))).toList();
          final todaysTasks = tasks.where((t) => !t.isCompleted && isSameDay(t.dateTime, now) && t.dateTime.isAfter(now)).toList();
          final upcomingTasks = tasks.where((t) => !t.isCompleted && !isSameDay(t.dateTime, now) && t.dateTime.isAfter(now)).toList();

          final List<Widget> listItems = [];

          // 1. Stats Header
          listItems.add(_buildStatsHeader(tasks));

          // 2. Overdue Tasks
          if (overdueTasks.isNotEmpty) {
            listItems.add(_buildCategoryHeader('التوا کے کام (Overdue Tasks)', Colors.red.shade700, overdueTasks.length));
            for (var task in overdueTasks) {
              listItems.add(_buildTaskCard(task, taskProvider, isPast: true));
            }
          }

          // 3. Today's Tasks
          if (todaysTasks.isNotEmpty) {
            listItems.add(_buildCategoryHeader('آج کے کام (Today\'s Tasks)', Colors.blue.shade700, todaysTasks.length));
            for (var task in todaysTasks) {
              listItems.add(_buildTaskCard(task, taskProvider, isPast: false));
            }
          }

          // 4. Upcoming Tasks
          if (upcomingTasks.isNotEmpty) {
            listItems.add(_buildCategoryHeader('آنے والے کام (Upcoming Tasks)', Colors.deepPurple.shade700, upcomingTasks.length));
            for (var task in upcomingTasks) {
              listItems.add(_buildTaskCard(task, taskProvider, isPast: false));
            }
          }

          // 5. Completed Tasks
          if (completedTasks.isNotEmpty) {
            listItems.add(_buildCategoryHeader('مکمل شدہ کام (Completed Tasks)', Colors.green.shade700, completedTasks.length));
            for (var task in completedTasks) {
              listItems.add(_buildTaskCard(task, taskProvider, isPast: false));
            }
          }

          return RefreshIndicator(
            onRefresh: () async {
              await taskProvider.fetchTasks();
            },
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: listItems.length,
              itemBuilder: (context, index) {
                return listItems[index];
              },
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const TaskFormScreen()),
          );
        },
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('نیا کام شامل کریں', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.deepPurple.shade600,
      ),
    );
  }

  Widget _buildCategoryHeader(String title, Color color, int count) {
    return Padding(
      padding: const EdgeInsets.only(top: 20.0, bottom: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
              fontFamily: 'Jameel Noori Nastaleeq',
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              count.toString(),
              style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskCard(TaskItem task, TaskProvider taskProvider, {required bool isPast}) {
    // Color accent configuration
    Color sideColor = Colors.deepPurple.shade400;
    if (task.isCompleted) {
      sideColor = Colors.green.shade500;
    } else if (isPast) {
      sideColor = Colors.red.shade500;
    }

    return Card(
      elevation: 3,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          border: BorderDirectional(
            start: BorderSide(color: sideColor, width: 6),
          ),
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          leading: InkWell(
            onTap: () {
              taskProvider.toggleTaskCompletion(task.id, task.isCompleted);
            },
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: task.isCompleted ? Colors.green : Colors.grey,
                  width: 2,
                ),
                color: task.isCompleted ? Colors.green : Colors.transparent,
              ),
              width: 36,
              height: 36,
              child: task.isCompleted
                  ? const Icon(Icons.check, size: 24, color: Colors.white)
                  : null,
            ),
          ),
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  task.title,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    decoration: task.isCompleted ? TextDecoration.lineThrough : null,
                    color: task.isCompleted ? Colors.grey : Colors.black87,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _getAlarmStatusWidget(task),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 10.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.access_time,
                      size: 16,
                      color: isPast ? Colors.red : Colors.grey,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _formatDateTime(task.dateTime),
                      style: TextStyle(
                        color: isPast ? Colors.red : Colors.grey.shade700,
                        fontWeight: isPast ? FontWeight.bold : FontWeight.normal,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.repeat, size: 16, color: Colors.deepPurple.shade300),
                    const SizedBox(width: 4),
                    Text(
                      'دہراؤ: ${_getRecurrenceUrdu(task.recurrence)}',
                      style: TextStyle(color: Colors.deepPurple.shade700, fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 14),
                    Icon(Icons.notifications_outlined, size: 16, color: Colors.deepPurple.shade300),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'یاد دہانی: ${_getRemindersUrdu(task.reminders)}',
                        style: TextStyle(color: Colors.deepPurple.shade700, fontSize: 13, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                if (!task.isCompleted) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.hourglass_empty, size: 16, color: Colors.amber.shade700),
                      const SizedBox(width: 4),
                      Text(
                        _getCountdownText(task.dateTime),
                        style: TextStyle(
                          color: Colors.amber.shade900,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Jameel Noori Nastaleeq',
                        ),
                      ),
                    ],
                  ),
                ],
                if (task.description != null && task.description!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.description_outlined, size: 15, color: Colors.grey.shade600),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          task.description!,
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            fontSize: 13.5,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.edit_outlined, color: Colors.deepPurple),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => TaskFormScreen(task: task),
                    ),
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                onPressed: () {
                  _showDeleteConfirm(context, taskProvider, task.id);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _getAlarmStatusWidget(TaskItem task) {
    final now = DateTime.now();
    if (task.isCompleted) {
      return _getStatusBadge(
        label: Strings.done,
        bgColor: Colors.green.shade100,
        textColor: Colors.green.shade800,
      );
    }

    // Check snooze
    if (task.snoozedUntil != null && task.snoozedUntil!.isAfter(now)) {
      final diff = task.snoozedUntil!.difference(now);
      final snoozeMin = diff.inMinutes + 1;
      return _getStatusBadge(
        label: 'الارم سوز ہے ($snoozeMin منٹ)',
        bgColor: Colors.orange.shade100,
        textColor: Colors.orange.shade800,
      );
    }

    // Check ringing window
    final diffToTask = now.difference(task.dateTime).abs();
    if (diffToTask.inMinutes <= 1) {
      return _getStatusBadge(
        label: 'الارم بج رہا ہے',
        bgColor: Colors.yellow.shade100,
        textColor: Colors.yellow.shade900,
      );
    }

    // Check overdue
    if (task.dateTime.isBefore(now)) {
      return _getStatusBadge(
        label: 'التوا (اوورڈیو)',
        bgColor: Colors.red.shade100,
        textColor: Colors.red.shade800,
      );
    }

    // Default scheduled
    return _getStatusBadge(
      label: 'الارم شیڈول ہے',
      bgColor: Colors.blue.shade100,
      textColor: Colors.blue.shade800,
    );
  }

  void _showDeleteConfirm(BuildContext context, TaskProvider provider, int id) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تصدیق کریں', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text('کیا آپ واقعی یہ کام حذف کرنا چاہتے ہیں؟', style: TextStyle(fontSize: 16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('منسوخ کریں', style: TextStyle(color: Colors.grey, fontSize: 16)),
          ),
          ElevatedButton(
            onPressed: () {
              provider.deleteTask(id);
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text(Strings.delete, style: TextStyle(color: Colors.white, fontSize: 16)),
          ),
        ],
      ),
    );
  }
}
