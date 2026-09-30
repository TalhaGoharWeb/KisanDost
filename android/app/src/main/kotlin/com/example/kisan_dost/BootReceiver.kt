package com.example.kisan_dost

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
