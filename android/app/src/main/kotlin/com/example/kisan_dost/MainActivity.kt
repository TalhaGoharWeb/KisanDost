package com.example.kisan_dost

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Intent
import androidx.core.content.FileProvider
import java.io.File
import android.os.Build
import android.net.Uri
import android.provider.Settings

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.kisan_dost/share"

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
        val shareDirectory = File(context.cacheDir, "shared_apk")
        if (!shareDirectory.exists() && !shareDirectory.mkdirs()) {
            throw IllegalStateException("Unable to create the APK sharing cache directory")
        }
        val sharedApk = File(shareDirectory, "kisan_dost.apk")
        apkFile.inputStream().use { input ->
            sharedApk.outputStream().use { output -> input.copyTo(output) }
        }
        val uri = FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", sharedApk)
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = "application/vnd.android.package-archive"
            putExtra(Intent.EXTRA_STREAM, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        context.startActivity(Intent.createChooser(intent, "ایپ شیئر کریں"))
    }
}
