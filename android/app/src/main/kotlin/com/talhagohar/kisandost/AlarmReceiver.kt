package com.talhagohar.kisandost

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.PowerManager
import android.util.Log
import java.time.ZonedDateTime
import java.time.ZoneId

class AlarmReceiver : BroadcastReceiver() {
    companion object {
        private const val TAG = "AlarmReceiver"
        const val ACTION_ALARM = "com.talhagohar.kisandost.ACTION_ALARM"
        const val ACTION_COMPLETE = "com.talhagohar.kisandost.ACTION_COMPLETE"
        const val ACTION_SNOOZE = "com.talhagohar.kisandost.ACTION_SNOOZE"
    }

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        Log.d(TAG, "onReceive action: $action")

        val powerManager = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        val wakeLock = powerManager.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "KisanDost::AlarmReceiverLock")
        wakeLock.acquire(10000) // Acquire lock for max 10s to ensure processing completes

        try {
            val taskId = intent.getIntExtra("taskId", -1)
            val alarmId = intent.getIntExtra("alarmId", -1)
            val taskTitle = intent.getStringExtra("taskTitle") ?: "اہم زرعی سرگرمی"

            if (taskId == -1) {
                Log.e(TAG, "Invalid taskId (-1) received in BroadcastReceiver.")
                return
            }

            when (action) {
                ACTION_ALARM -> {
                    val serviceIntent = Intent(context, AlarmService::class.java).apply {
                        putExtra("taskId", taskId)
                        putExtra("alarmId", alarmId)
                        putExtra("taskTitle", taskTitle)
                    }
                    if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                        context.startForegroundService(serviceIntent)
                    } else {
                        context.startService(serviceIntent)
                    }
                    Log.d(TAG, "Foreground service started for task $taskId")
                }
                ACTION_COMPLETE -> {
                    val dbHelper = DatabaseHelper(context)
                    dbHelper.completeTask(taskId)
                    AlarmScheduler.cancelAlarmsForTask(context, taskId)
                    
                    val serviceIntent = Intent(context, AlarmService::class.java)
                    context.stopService(serviceIntent)
                    Log.d(TAG, "Task $taskId marked complete from notification action.")
                }
                ACTION_SNOOZE -> {
                    val dbHelper = DatabaseHelper(context)
                    val task = dbHelper.getTask(taskId)
                    if (task != null) {
                        val snoozeTime = ZonedDateTime.now(ZoneId.of("Asia/Karachi"))
                            .plusMinutes(10)
                        
                        dbHelper.snoozeTask(taskId, snoozeTime.toLocalDateTime().toString())
                        
                        val updatedTask = dbHelper.getTask(taskId)
                        if (updatedTask != null) {
                            AlarmScheduler.scheduleAlarmsForTask(context, updatedTask)
                        }
                    }
                    
                    val serviceIntent = Intent(context, AlarmService::class.java)
                    context.stopService(serviceIntent)
                    Log.d(TAG, "Task $taskId snoozed for 10 minutes from notification action.")
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Exception in AlarmReceiver processing: ${e.message}", e)
        } finally {
            if (wakeLock.isHeld) {
                wakeLock.release()
            }
        }
    }
}
