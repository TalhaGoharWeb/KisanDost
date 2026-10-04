package com.talhagohar.kisandost

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

class BootReceiver : BroadcastReceiver() {
    companion object {
        private const val TAG = "BootReceiver"
    }

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action
        // The receiver is exported (required for system boot broadcasts), so
        // ignore any spoofed broadcast that doesn't carry an expected action.
        // (DB hardening 2026-10-04)
        if (action != Intent.ACTION_BOOT_COMPLETED &&
            action != Intent.ACTION_LOCKED_BOOT_COMPLETED &&
            action != Intent.ACTION_MY_PACKAGE_REPLACED &&
            action != "android.intent.action.QUICKBOOT_POWERON" &&
            action != "com.htc.intent.action.QUICKBOOT_POWERON") {
            Log.w(TAG, "Ignoring unexpected broadcast action: $action")
            return
        }
        Log.d(TAG, "Received broadcast action: $action")

        val pendingResult = goAsync()
        Thread {
            try {
                AlarmScheduler.rescheduleAllAlarms(context)
                Log.d(TAG, "Successfully rescheduled all pending alarms on boot/package replace.")
            } catch (e: Exception) {
                Log.e(TAG, "Error rescheduling alarms on boot: ${e.message}", e)
            } finally {
                pendingResult.finish()
            }
        }.start()
    }
}
