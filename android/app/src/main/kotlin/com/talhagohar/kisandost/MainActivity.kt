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

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.talhagohar.kisandost/share"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        // Configure activity to turn screen on and show when locked
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD or
                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
            )
        }
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
        val apkFile = File(context.packageCodePath)
        val uri = FileProvider.getUriForFile(context, context.packageName + ".fileprovider", apkFile)
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = "application/vnd.android.package-archive"
            putExtra(Intent.EXTRA_STREAM, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        context.startActivity(Intent.createChooser(intent, "ایپ شیئر کریں"))
    }
}
