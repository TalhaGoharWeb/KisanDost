package com.talhagohar.kisandost

import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.view.View
import android.view.WindowManager
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import com.google.android.material.button.MaterialButton
import java.time.Instant
import java.time.ZoneId
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter
import java.util.Locale

class AlarmActivity : AppCompatActivity() {

    private var taskId: Int = -1

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Setup lock screen flags so this activity opens instantly on top of the keyguard
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
            val keyguardManager = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
            keyguardManager.requestDismissKeyguard(this, null)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
            )
        }
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

        setContentView(R.layout.activity_alarm)

        taskId = intent.getIntExtra("taskId", -1)
        if (taskId == -1) {
            finish()
            return
        }

        loadTaskDetails()
        setupClickListeners()
    }

    private fun loadTaskDetails() {
        val dbHelper = DatabaseHelper(this)
        val task = dbHelper.getTask(taskId)

        val titleTv = findViewById<TextView>(R.id.task_title)
        val descTv = findViewById<TextView>(R.id.task_description)
        val timeTv = findViewById<TextView>(R.id.task_time)
        val recurrenceTv = findViewById<TextView>(R.id.task_recurrence)

        if (task != null) {
            titleTv.text = task.title
            if (!task.description.isNullOrEmpty()) {
                descTv.text = task.description
                descTv.visibility = View.VISIBLE
            } else {
                descTv.visibility = View.GONE
            }

            try {
                val baseTimeMs = AlarmScheduler.parseIsoDateTime(task.date_time)
                val zonedDateTime = ZonedDateTime.ofInstant(Instant.ofEpochMilli(baseTimeMs), ZoneId.of("Asia/Karachi"))
                val formatter = DateTimeFormatter.ofPattern("dd MMM yyyy hh:mm a", Locale.ENGLISH)
                timeTv.text = zonedDateTime.format(formatter)
            } catch (e: Exception) {
                timeTv.text = task.date_time
            }

            recurrenceTv.text = when (task.recurrence) {
                "daily" -> "دوبارہ یاد دہانی: روزانہ دہرایا جائے گا"
                "weekly" -> "دوبارہ یاد دہانی: ہفتہ وار دہرایا جائے گا"
                else -> "دوبارہ یاد دہانی: بغیر دہرائے"
            }
        } else {
            titleTv.text = "نامعلوم سرگرمی"
            descTv.visibility = View.GONE
            recurrenceTv.visibility = View.GONE
        }
    }

    private fun setupClickListeners() {
        val btnComplete = findViewById<MaterialButton>(R.id.btn_complete)
        val btnDismiss = findViewById<MaterialButton>(R.id.btn_dismiss)
        val btnSnooze5 = findViewById<MaterialButton>(R.id.btn_snooze_5)
        val btnSnooze10 = findViewById<MaterialButton>(R.id.btn_snooze_10)
        val btnSnooze15 = findViewById<MaterialButton>(R.id.btn_snooze_15)

        val dbHelper = DatabaseHelper(this)

        btnComplete.setOnClickListener {
            dbHelper.completeTask(taskId)
            AlarmScheduler.cancelAlarmsForTask(this, taskId)
            stopAlarmService()
            finish()
        }

        btnDismiss.setOnClickListener {
            stopAlarmService()
            finish()
        }

        btnSnooze5.setOnClickListener { snoozeTask(5) }
        btnSnooze10.setOnClickListener { snoozeTask(10) }
        btnSnooze15.setOnClickListener { snoozeTask(15) }
    }

    private fun snoozeTask(minutes: Int) {
        val dbHelper = DatabaseHelper(this)
        val snoozeTime = ZonedDateTime.now(ZoneId.of("Asia/Karachi"))
            .plusMinutes(minutes.toLong())

        dbHelper.snoozeTask(taskId, snoozeTime.toLocalDateTime().toString())

        val updatedTask = dbHelper.getTask(taskId)
        if (updatedTask != null) {
            AlarmScheduler.scheduleAlarmsForTask(this, updatedTask)
        }

        stopAlarmService()
        finish()
    }

    private fun stopAlarmService() {
        val serviceIntent = Intent(this, AlarmService::class.java)
        stopService(serviceIntent)
    }
}
