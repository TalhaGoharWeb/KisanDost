package com.talhagohar.kisandost

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Intent
import androidx.core.content.FileProvider
import java.io.File
import android.os.Bundle
import android.os.Build
import android.view.WindowManager
import android.net.Uri
import android.provider.Settings
import android.content.Context
import android.os.PowerManager
import java.time.ZonedDateTime
import java.time.ZoneId

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.talhagohar.kisandost/share"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // NOTE: This activity must NOT show over the lock screen. It hosts the
        // full app UI (financial records, parties, inventory). The lock-screen
        // alarm experience is handled by AlarmActivity (exported=false,
        // singleInstance). Previously setShowWhenLocked(true) here let anyone
        // with physical access open the entire app from a locked phone via the
        // status-bar alarm-clock icon. (Android hardening 2026-10-04)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "shareApk" -> {
                    try {
                        shareApkFile()
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SHARE_FAILED", e.message, null)
                    }
                }
                "openAppSettings" -> {
                    try {
                        val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                            data = Uri.fromParts("package", packageName, null)
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        context.startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("ERROR", e.message, null)
                    }
                }
                "openBatterySettings" -> {
                    try {
                        val intent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS).apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        context.startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("ERROR", e.message, null)
                    }
                }
                "isIgnoringBatteryOptimizations" -> {
                    try {
                        val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
                        val isIgnoring = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            pm.isIgnoringBatteryOptimizations(packageName)
                        } else {
                            true
                        }
                        result.success(isIgnoring)
                    } catch (e: Exception) {
                        result.error("ERROR", e.message, null)
                    }
                }
                "requestIgnoreBatteryOptimizations" -> {
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                                data = Uri.parse("package:$packageName")
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            context.startActivity(intent)
                            result.success(true)
                        } else {
                            result.success(true)
                        }
                    } catch (e: Exception) {
                        result.error("ERROR", e.message, null)
                    }
                }
                "canUseFullScreenIntent" -> {
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager
                            result.success(nm.canUseFullScreenIntent())
                        } else {
                            result.success(true)
                        }
                    } catch (e: Exception) {
                        result.error("ERROR", e.message, null)
                    }
                }
                "requestFullScreenIntentPermission" -> {
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                            val intent = Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT).apply {
                                data = Uri.parse("package:$packageName")
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            context.startActivity(intent)
                            result.success(true)
                        } else {
                            result.success(true)
                        }
                    } catch (e: Exception) {
                        result.error("ERROR", e.message, null)
                    }
                }
                "scheduleAlarm" -> {
                    try {
                        val taskId = call.argument<Int>("taskId")
                        if (taskId != null) {
                            val dbHelper = DatabaseHelper(context)
                            val task = dbHelper.getTask(taskId)
                            if (task != null) {
                                AlarmScheduler.scheduleAlarmsForTask(context, task)
                                result.success(true)
                            } else {
                                result.error("NOT_FOUND", "Task with ID $taskId not found in DB", null)
                            }
                        } else {
                            result.error("BAD_ARGUMENT", "taskId argument is missing", null)
                        }
                    } catch (e: Exception) {
                        result.error("ERROR", e.message, null)
                    }
                }
                "cancelAlarm" -> {
                    try {
                        val taskId = call.argument<Int>("taskId")
                        if (taskId != null) {
                            AlarmScheduler.cancelAlarmsForTask(context, taskId)
                            result.success(true)
                        } else {
                            result.error("BAD_ARGUMENT", "taskId argument is missing", null)
                        }
                    } catch (e: Exception) {
                        result.error("ERROR", e.message, null)
                    }
                }
                // Diagnostic: schedules a synthetic alarm 15 seconds out,
                // bypassing the database. Used by the Settings "Test Alarm"
                // button to isolate native alarm delivery from task storage.
                "scheduleTestAlarm" -> {
                    try {
                        val fireTime = ZonedDateTime.now(ZoneId.of("Asia/Karachi"))
                            .plusSeconds(15)
                        val testTask = Task(
                            id = 999999,
                            title = "ٹیسٹ الارم",
                            description = "یہ ایک ٹیسٹ الارم ہے",
                            date_time = fireTime.toString(),
                            snoozed_until = null,
                            is_completed = 0,
                            recurrence = "none",
                            reminders = "0"
                        )
                        AlarmScheduler.scheduleAlarmsForTask(context, testTask)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("ERROR", e.message, null)
                    }
                }
                "rescheduleAllAlarms" -> {
                    try {
                        AlarmScheduler.rescheduleAllAlarms(context)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("ERROR", e.message, null)
                    }
                }
                "canScheduleExactAlarms" -> {
                    try {
                        result.success(AlarmScheduler.canScheduleExactAlarms(context))
                    } catch (e: Exception) {
                        result.error("ERROR", e.message, null)
                    }
                }
                "requestExactAlarmPermission" -> {
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                            val intent = Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM).apply {
                                data = Uri.parse("package:$packageName")
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            context.startActivity(intent)
                            result.success(true)
                        } else {
                            result.success(true)
                        }
                    } catch (e: Exception) {
                        result.error("ERROR", e.message, null)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun shareApkFile() {
        // context.packageCodePath (/data/app/.../base.apk) is NOT under any
        // FileProvider root declared in filepaths.xml, so getUriForFile()
        // would throw IllegalArgumentException. Stage a private copy in the
        // app cache dir (already a configured FileProvider root) and share
        // that instead. The staged file name is fixed and no Dart arguments
        // are honored, so the shared file can never be redirected to another
        // path (e.g. the database or backups).
        val stagedApk = File(context.cacheDir, "kisandost-share.apk")
        try {
            File(context.packageCodePath).inputStream().use { input ->
                stagedApk.outputStream().use { output ->
                    input.copyTo(output)
                }
            }
            // Belt-and-braces: owner-only access. The app-private cache dir
            // already blocks other apps at the directory level.
            stagedApk.setReadable(true, true)
            stagedApk.setWritable(true, true)
            stagedApk.setExecutable(false, false)
        } catch (e: Exception) {
            stagedApk.delete()
            throw e
        }

        val uri = FileProvider.getUriForFile(context, context.packageName + ".fileprovider", stagedApk)
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = "application/vnd.android.package-archive"
            putExtra(Intent.EXTRA_STREAM, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        context.startActivity(Intent.createChooser(intent, "ایپ شیئر کریں"))
        // NOTE: stagedApk is intentionally not deleted here — the receiving
        // app reads it asynchronously after the chooser returns. It is
        // overwritten on the next share, so at most one copy ever exists in
        // the private cache.
    }
}
