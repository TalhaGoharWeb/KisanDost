package com.example.kisan_dost

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.util.Log

class DatabaseHelper(private val context: Context) {
    companion object {
        private const val TAG = "NativeDatabaseHelper"
        private const val DB_NAME = "kisan_dost.db"
    }

    private fun getDatabase(): SQLiteDatabase? {
        return try {
            val dbPath = context.getDatabasePath(DB_NAME)
            SQLiteDatabase.openDatabase(dbPath.absolutePath, null, SQLiteDatabase.OPEN_READWRITE)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to open SQLite database: ${e.message}", e)
            null
        }
    }

    fun getTask(taskId: Int): Task? {
        val db = getDatabase() ?: return null
        var task: Task? = null
        try {
            val cursor = db.query(
                "tasks",
                null,
                "id = ?",
                arrayOf(taskId.toString()),
                null,
                null,
                null
            )
            cursor?.use {
                if (it.moveToFirst()) {
                    task = parseTask(it)
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error fetching task by ID $taskId: ${e.message}", e)
        } finally {
            db.close()
        }
        return task
    }

    fun getIncompleteTasks(): List<Task> {
        val db = getDatabase() ?: return emptyList()
        val list = mutableListOf<Task>()
        try {
            val cursor = db.query(
                "tasks",
                null,
                "is_completed = ?",
                arrayOf("0"),
                null,
                null,
                null
            )
            cursor?.use {
                while (it.moveToNext()) {
                    list.add(parseTask(it))
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error fetching incomplete tasks: ${e.message}", e)
        } finally {
            db.close()
        }
        return list
    }

    fun completeTask(taskId: Int) {
        val db = getDatabase() ?: return
        try {
            val values = ContentValues().apply {
                put("is_completed", 1)
                putNull("snoozed_until")
            }
            db.update("tasks", values, "id = ?", arrayOf(taskId.toString()))
            Log.d(TAG, "Task $taskId marked completed in database.")
        } catch (e: Exception) {
            Log.e(TAG, "Error completing task $taskId: ${e.message}", e)
        } finally {
            db.close()
        }
    }

    fun snoozeTask(taskId: Int, snoozeTimeIso: String) {
        val db = getDatabase() ?: return
        try {
            val values = ContentValues().apply {
                put("snoozed_until", snoozeTimeIso)
            }
            db.update("tasks", values, "id = ?", arrayOf(taskId.toString()))
            Log.d(TAG, "Task $taskId snoozed until $snoozeTimeIso in database.")
        } catch (e: Exception) {
            Log.e(TAG, "Error snoozing task $taskId: ${e.message}", e)
        } finally {
            db.close()
        }
    }

    private fun parseTask(cursor: android.database.Cursor): Task {
        val idIndex = cursor.getColumnIndexOrThrow("id")
        val titleIndex = cursor.getColumnIndexOrThrow("title")
        val descIndex = cursor.getColumnIndexOrThrow("description")
        val dateTimeIndex = cursor.getColumnIndexOrThrow("date_time")
        val snoozeIndex = cursor.getColumnIndexOrThrow("snoozed_until")
        val completedIndex = cursor.getColumnIndexOrThrow("is_completed")
        val recurrenceIndex = cursor.getColumnIndexOrThrow("recurrence")
        val remindersIndex = cursor.getColumnIndexOrThrow("reminders")

        return Task(
            id = cursor.getInt(idIndex),
            title = cursor.getString(titleIndex),
            description = if (cursor.isNull(descIndex)) null else cursor.getString(descIndex),
            date_time = cursor.getString(dateTimeIndex),
            snoozed_until = if (cursor.isNull(snoozeIndex)) null else cursor.getString(snoozeIndex),
            is_completed = cursor.getInt(completedIndex),
            recurrence = cursor.getString(recurrenceIndex),
            reminders = cursor.getString(remindersIndex)
        )
    }
}

data class Task(
    val id: Int,
    val title: String,
    val description: String?,
    val date_time: String,
    val snoozed_until: String?,
    val is_completed: Int,
    val recurrence: String,
    val reminders: String
)
