import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/task_provider.dart';
import '../l10n/strings.dart';

class TaskFormScreen extends StatefulWidget {
  final TaskItem? task;
  const TaskFormScreen({super.key, this.task});

  @override
  State<TaskFormScreen> createState() => _TaskFormScreenState();
}

class _TaskFormScreenState extends State<TaskFormScreen> {
  final _formKey = GlobalKey<FormState>();
  String _title = '';
  String _description = '';
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  String _recurrence = 'none'; // 'none', 'daily', 'weekly'
  late List<int> _selectedReminders;

  @override
  void initState() {
    super.initState();
    if (widget.task != null) {
      _title = widget.task!.title;
      _description = widget.task!.description ?? '';
      _selectedDate = widget.task!.dateTime;
      _selectedTime = TimeOfDay.fromDateTime(widget.task!.dateTime);
      _recurrence = widget.task!.recurrence;
      _selectedReminders = widget.task!.reminders
          .split(',')
          .map((e) => int.tryParse(e.trim()))
          .whereType<int>()
          .toList();
      if (_selectedReminders.isEmpty) {
        _selectedReminders = [0];
      }
    } else {
      _selectedReminders = [0]; // default fallback
      _loadDefaultReminderPrefs();
    }
  }

  Future<void> _loadDefaultReminderPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final prefAtTime = prefs.getBool('reminder_pref_at_time') ?? true;
    final pref1h = prefs.getBool('reminder_pref_1h') ?? true;
    final pref1d = prefs.getBool('reminder_pref_1d') ?? true;

    final List<int> loaded = [];
    if (prefAtTime) loaded.add(0);
    if (pref1h) loaded.add(60);
    if (pref1d) loaded.add(1440);

    setState(() {
      _selectedReminders = loaded.isNotEmpty ? loaded : [0];
    });
  }

  Future<void> _pickDate() async {
    final initialDate = _selectedDate ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate.isBefore(DateTime.now()) ? DateTime.now() : initialDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)), // allow past dates for editing reference
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime ?? TimeOfDay.now(),
    );
    if (picked != null) {
      setState(() {
        _selectedTime = picked;
      });
    }
  }

  void _toggleReminder(int minutes) {
    setState(() {
      if (_selectedReminders.contains(minutes)) {
        if (_selectedReminders.length > 1) {
          _selectedReminders.remove(minutes);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('کم از کم ایک یاد دہانی منتخب کرنا ضروری ہے')),
          );
        }
      } else {
        _selectedReminders.add(minutes);
      }
    });
  }

  void _saveTask() async {
    if (_formKey.currentState!.validate()) {
      if (_selectedDate == null || _selectedTime == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('براہ کرم تاریخ اور وقت کا انتخاب کریں')),
        );
        return;
      }

      _formKey.currentState!.save();

      final taskDateTime = DateTime(
        _selectedDate!.year,
        _selectedDate!.month,
        _selectedDate!.day,
        _selectedTime!.hour,
        _selectedTime!.minute,
      );

      // Only validate past time for new non-recurring tasks
      if (widget.task == null && _recurrence == 'none' && taskDateTime.isBefore(DateTime.now())) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('گزرا ہوا وقت منتخب نہیں کیا جا سکتا')),
        );
        return;
      }

      _selectedReminders.sort();
      final remindersString = _selectedReminders.join(',');

      if (widget.task != null) {
        // Edit flow
        await context.read<TaskProvider>().updateTask(
          widget.task!.id,
          _title,
          _description,
          taskDateTime,
          recurrence: _recurrence,
          reminders: remindersString,
        );
      } else {
        // Add flow
        await context.read<TaskProvider>().addTask(
          _title,
          _description,
          taskDateTime,
          recurrence: _recurrence,
          reminders: remindersString,
        );
      }
      
      if (mounted) {
        Navigator.pop(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.task != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'کام کی ترمیم کریں' : 'نیا کام شامل کریں'),
        backgroundColor: Colors.deepPurple.shade600,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                initialValue: _title,
                decoration: InputDecoration(
                  labelText: 'کام کا نام (مثلاً: یوریا کھاد ڈالنا)',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  prefixIcon: const Icon(Icons.edit),
                  filled: true,
                  fillColor: Colors.grey.shade100,
                ),
                style: const TextStyle(fontSize: 18),
                validator: (val) => val == null || val.isEmpty ? 'براہ کرم نام درج کریں' : null,
                onSaved: (val) => _title = val!,
              ),
              const SizedBox(height: 16),
              TextFormField(
                initialValue: _description,
                decoration: InputDecoration(
                  labelText: 'تفصیل (تفصیل اختیاری ہے، جیسے: پانی کا دورانیہ ۲ گھنٹے)',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  prefixIcon: const Icon(Icons.description),
                  filled: true,
                  fillColor: Colors.grey.shade100,
                ),
                maxLines: 3,
                style: const TextStyle(fontSize: 18),
                onSaved: (val) => _description = val ?? '',
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: _buildPickerButton(
                      label: _selectedDate == null
                          ? 'تاریخ منتخب کریں'
                          : DateFormat('dd MMM yyyy').format(_selectedDate!),
                      icon: Icons.calendar_today,
                      onTap: _pickDate,
                      isActive: _selectedDate != null,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildPickerButton(
                      label: _selectedTime == null
                          ? 'وقت منتخب کریں'
                          : _selectedTime!.format(context),
                      icon: Icons.access_time,
                      onTap: _pickTime,
                      isActive: _selectedTime != null,
                    ),
                  ),
                ],
              ),
              
              // Recurrence Section
              _buildSectionTitle('یاد دہانی کا دہراؤ (فریکوئنسی)'),
              Row(
                children: [
                  _buildRecurrenceOption('ایک بار', 'none', Icons.one_k),
                  const SizedBox(width: 12),
                  _buildRecurrenceOption('روزانہ', 'daily', Icons.replay),
                  const SizedBox(width: 12),
                  _buildRecurrenceOption('ہفتہ وار', 'weekly', Icons.calendar_view_week),
                ],
              ),

              // Reminders Section
              _buildSectionTitle('کتنی دیر پہلے یاد دلائیں؟ (ایک سے زائد منتخب کر سکتے ہیں)'),
              _buildReminderCheckbox('کام کے وقت', 0, Icons.notifications_active),
              _buildReminderCheckbox('1 گھنٹہ پہلے', 60, Icons.hourglass_top),
              _buildReminderCheckbox('1 دن پہلے', 1440, Icons.today),

              const SizedBox(height: 40),
              ElevatedButton(
                onPressed: _saveTask,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  backgroundColor: Colors.deepPurple.shade600,
                  foregroundColor: Colors.white,
                ),
                child: Text(
                  isEditing ? 'ترمیم محفوظ کریں' : Strings.save,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 28.0, bottom: 12.0),
      child: Text(
        title,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
      ),
    );
  }

  Widget _buildRecurrenceOption(String label, String value, IconData icon) {
    final isSelected = _recurrence == value;
    return Expanded(
      child: InkWell(
        onTap: () {
          setState(() {
            _recurrence = value;
          });
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: isSelected ? Colors.deepPurple.shade50 : Colors.white,
            border: Border.all(
              color: isSelected ? Colors.deepPurple.shade600 : Colors.grey.shade400,
              width: 2,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                size: 28,
                color: isSelected ? Colors.deepPurple.shade600 : Colors.grey.shade600,
              ),
              const SizedBox(height: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected ? Colors.deepPurple.shade800 : Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReminderCheckbox(String label, int minutes, IconData icon) {
    final isSelected = _selectedReminders.contains(minutes);
    return InkWell(
      onTap: () => _toggleReminder(minutes),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected ? Colors.deepPurple.shade50 : Colors.white,
          border: Border.all(
            color: isSelected ? Colors.deepPurple.shade600 : Colors.grey.shade400,
            width: 2,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
              color: isSelected ? Colors.deepPurple.shade600 : Colors.grey.shade600,
              size: 28,
            ),
            const SizedBox(width: 12),
            Icon(icon, color: Colors.grey.shade700, size: 24),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                fontSize: 18,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? Colors.deepPurple.shade800 : Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPickerButton({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
    required bool isActive,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        decoration: BoxDecoration(
          border: Border.all(
            color: isActive ? Colors.deepPurple.shade600 : Colors.grey.shade400,
            width: 2,
          ),
          borderRadius: BorderRadius.circular(16),
          color: isActive ? Colors.deepPurple.shade50 : Colors.white,
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 32,
              color: isActive ? Colors.deepPurple.shade600 : Colors.grey.shade600,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                color: isActive ? Colors.deepPurple.shade800 : Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
