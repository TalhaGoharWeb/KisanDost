package com.example.kisan_dost

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter
import java.util.Date

object AlarmScheduler {
    private const val TAG = "AlarmScheduler"

    fun canScheduleExactAlarms(context: Context): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            alarmManager.canScheduleExactAlarms()
        } else {
            true
        }
    }

    fun parseIsoDateTime(isoStr: String): Long {
        return try {
            val zonedDateTime = ZonedDateTime.parse(isoStr)
            zonedDateTime.toInstant().toEpochMilli()
        } catch (e: Exception) {
            try {
                // Flutter's toIso8601String() might not include timezone. We assume local timezone "Asia/Karachi".
                val localDateTime = LocalDateTime.parse(isoStr, DateTimeFormatter.ISO_DATE_TIME)
                localDateTime.atZone(ZoneId.of("Asia/Karachi")).toInstant().toEpochMilli()
            } catch (e2: Exception) {
                Log.e(TAG, "Failed parsing date time: $isoStr", e2)
                System.currentTimeMillis()
            }
        }
    }

    fun scheduleAlarmsForTask(context: Context, task: Task) {
        // 1. Cancel existing alarms for this task ID (slots 0 to 9)
        cancelAlarmsForTask(context, task.id)

        if (task.is_completed == 1) {
            Log.d(TAG, "Task ${task.id} is marked as completed. Skipping schedule.")
            return
        }

        val now = System.currentTimeMillis()

        // 2. Schedule reminders (offsets: e.g., "0" or "0,60" or "0,1440")
        val offsets = task.reminders.split(",")
            .map { it.trim().toIntOrNull() }
            .filterNotNull()
            .toMutableList()

        if (offsets.isEmpty()) {
            offsets.add(0)
        }

        val baseTimeMs = parseIsoDateTime(task.date_time)

        for (index in offsets.indices) {
            val offsetMinutes = offsets[index]
            var triggerTimeMs = baseTimeMs - (offsetMinutes * 60 * 1000)

            // If the alarm trigger is in the past:
            if (triggerTimeMs < now) {
                when (task.recurrence) {
                    "daily" -> {
                        // Calculate next daily occurrence
                        while (triggerTimeMs < now) {
                            triggerTimeMs += 24 * 60 * 60 * 1000 // Add 1 day
                        }
                    }
                    "weekly" -> {
                        // Calculate next weekly occurrence
                        while (triggerTimeMs < now) {
                            triggerTimeMs += 7 * 24 * 60 * 60 * 1000 // Add 7 days
                        }
                    }
                    else -> {
                        // No recurrence, skip past alarms
                        Log.d(TAG, "Reminder offset $offsetMinutes for task ${task.id} is in the past and has no recurrence. Skipping.")
                        continue
                    }
                }
            }

            val alarmId = task.id * 10 + (index % 9) // Slots 0..8
            scheduleAlarm(context, alarmId, triggerTimeMs, task.title)
        }

        // 3. Schedule Snooze alarm if active and in the future
        if (!task.snoozed_until.isNullOrEmpty()) {
            val snoozeTimeMs = parseIsoDateTime(task.snoozed_until)
            if (snoozeTimeMs > now) {
                val snoozeAlarmId = task.id * 10 + 9 // Slot 9 is reserved for snooze
                scheduleAlarm(context, snoozeAlarmId, snoozeTimeMs, "سوز کریں: ${task.title}")
                Log.d(TAG, "Scheduled snooze alarm $snoozeAlarmId at ${Date(snoozeTimeMs)}")
            }
        }
    }

    private fun scheduleAlarm(context: Context, alarmId: Int, triggerTimeMs: Long, taskTitle: String) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = Intent(context, AlarmReceiver::class.java).apply {
            action = "com.example.kisan_dost.ACTION_ALARM"
            putExtra("taskId", alarmId / 10)
            putExtra("alarmId", alarmId)
            putExtra("taskTitle", taskTitle)
        }

        val pendingIntentFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }

        val pendingIntent = PendingIntent.getBroadcast(context, alarmId, intent, pendingIntentFlags)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            // setAlarmClock launches a PendingIntent when clicked from system tray
            val showIntent = Intent(context, MainActivity::class.java).apply {
                this.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            }
            val showPendingIntent = PendingIntent.getActivity(context, alarmId, showIntent, pendingIntentFlags)
            val clockInfo = AlarmManager.AlarmClockInfo(triggerTimeMs, showPendingIntent)
            
            try {
                alarmManager.setAlarmClock(clockInfo, pendingIntent)
                Log.d(TAG, "Alarm $alarmId scheduled exactly at ${Date(triggerTimeMs)} using setAlarmClock.")
            } catch (e: SecurityException) {
                Log.w(TAG, "SCHEDULE_EXACT_ALARM permission not granted! Falling back to setAndAllowWhileIdle for alarm $alarmId.", e)
                alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerTimeMs, pendingIntent)
            }
        } else {
            alarmManager.setExact(AlarmManager.RTC_WAKEUP, triggerTimeMs, pendingIntent)
            Log.d(TAG, "Alarm $alarmId scheduled exactly at ${Date(triggerTimeMs)} on older Android version.")
        }
    }

    fun cancelAlarmsForTask(context: Context, taskId: Int) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = Intent(context, AlarmReceiver::class.java).apply {
            action = "com.example.kisan_dost.ACTION_ALARM"
        }
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }

        for (i in 0..9) {
            val alarmId = taskId * 10 + i
            val pendingIntent = PendingIntent.getBroadcast(context, alarmId, intent, flags)
            alarmManager.cancel(pendingIntent)
            pendingIntent.cancel()
        }
        Log.d(TAG, "Cancelled all alarms (0-9) for task $taskId.")
    }

    fun rescheduleAllAlarms(context: Context) {
        val dbHelper = DatabaseHelper(context)
        val pendingTasks = dbHelper.getIncompleteTasks()
        for (task in pendingTasks) {
            scheduleAlarmsForTask(context, task)
        }
        Log.d(TAG, "Rescheduled all incomplete tasks: ${pendingTasks.size}")
    }
}
