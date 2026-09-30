package com.example.kisan_dost

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.net.Uri
import android.os.Build
import android.os.IBinder
import android.os.VibrationEffect
import android.os.Vibrator
import android.util.Log
import androidx.core.app.NotificationCompat

class AlarmService : Service() {
    companion object {
        private const val TAG = "AlarmService"
        private const val CHANNEL_ID = "kisan_dost_native_alarms_v1"
        private const val CHANNEL_NAME = "Farming Alarms (Native)"
    }

    private var mediaPlayer: MediaPlayer? = null
    private var vibrator: Vibrator? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent == null) return START_NOT_STICKY

        val taskId = intent.getIntExtra("taskId", -1)
        val alarmId = intent.getIntExtra("alarmId", -1)
        val taskTitle = intent.getStringExtra("taskTitle") ?: "اہم زرعی سرگرمی"

        Log.d(TAG, "Starting foreground alarm service for task: $taskId")

        // 1. Play looping alarm sound
        playAlarmSound()

        // 2. Vibrate
        startVibration()

        // 3. Create Notification Channel
        createNotificationChannel()

        // 4. Create intents for actions
        val completeIntent = Intent(this, AlarmReceiver::class.java).apply {
            action = AlarmReceiver.ACTION_COMPLETE
            putExtra("taskId", taskId)
            putExtra("alarmId", alarmId)
        }
        val completePendingIntent = PendingIntent.getBroadcast(
            this,
            alarmId + 100,
            completeIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val snoozeIntent = Intent(this, AlarmReceiver::class.java).apply {
            action = AlarmReceiver.ACTION_SNOOZE
            putExtra("taskId", taskId)
            putExtra("alarmId", alarmId)
        }
        val snoozePendingIntent = PendingIntent.getBroadcast(
            this,
            alarmId + 200,
            snoozeIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // Open the alarm screen only when the farmer taps the notification.
        val openActivityIntent = Intent(this, AlarmActivity::class.java).apply {
            putExtra("taskId", taskId)
            putExtra("alarmId", alarmId)
            this.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        val openActivityPendingIntent = PendingIntent.getActivity(
            this,
            alarmId,
            openActivityIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // Build notification
        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle("کسان دوست یاد دہانی")
            .setContentText(taskTitle)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setOngoing(true)
            .setAutoCancel(false)
            .setContentIntent(openActivityPendingIntent)
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
            .addAction(android.R.drawable.ic_menu_save, "مکمل ہو گیا", completePendingIntent)
            .addAction(android.R.drawable.ic_menu_send, "سوز کریں (10 منٹ)", snoozePendingIntent)

        val notification = builder.build()
        notification.flags = notification.flags or Notification.FLAG_INSISTENT

        // 5. Start Foreground
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(alarmId, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK)
        } else {
            startForeground(alarmId, notification)
        }

        return START_STICKY
    }

    private fun playAlarmSound() {
        try {
            mediaPlayer = MediaPlayer().apply {
                val soundUri = Uri.parse("android.resource://$packageName/raw/farming_alarm")
                setDataSource(this@AlarmService, soundUri)
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                )
                isLooping = true
                prepare()
                start()
            }
            Log.d(TAG, "Playing loop alarm sound.")
        } catch (e: Exception) {
            Log.e(TAG, "Error playing alarm sound: ${e.message}", e)
        }
    }

    private fun startVibration() {
        try {
            vibrator = getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            val pattern = longArrayOf(0, 1000, 1000)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrator?.vibrate(VibrationEffect.createWaveform(pattern, 0))
            } else {
                @Suppress("DEPRECATION")
                vibrator?.vibrate(pattern, 0)
            }
            Log.d(TAG, "Vibrating looping pattern.")
        } catch (e: Exception) {
            Log.e(TAG, "Error starting vibration: ${e.message}", e)
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val audioAttributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ALARM)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()

            val channel = NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Loud alarms for agricultural activities"
                setSound(Uri.parse("android.resource://$packageName/raw/farming_alarm"), audioAttributes)
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 1000, 1000)
                lockscreenVisibility = Notification.VISIBILITY_PRIVATE
            }

            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)
        }
    }

    override fun onDestroy() {
        Log.d(TAG, "Stopping foreground alarm service.")
        try {
            mediaPlayer?.stop()
            mediaPlayer?.release()
            mediaPlayer = null
        } catch (e: Exception) {
            Log.e(TAG, "Error releasing MediaPlayer: ${e.message}")
        }

        try {
            vibrator?.cancel()
            vibrator = null
        } catch (e: Exception) {
            Log.e(TAG, "Error canceling Vibrator: ${e.message}")
        }

        super.onDestroy()
    }
}
