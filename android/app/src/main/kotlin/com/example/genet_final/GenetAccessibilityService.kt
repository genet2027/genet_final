package com.example.genet_final

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import org.json.JSONArray

class GenetAccessibilityService : AccessibilityService() {

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event?.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return
        val pkg = event.packageName?.toString() ?: return
        if (pkg == packageName) return // Don't lock when Genet app is open

        val prefs = getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
        if (shouldShowLock(prefs, pkg)) {
            startLockActivity()
        }
    }

    private fun shouldShowLock(prefs: android.content.SharedPreferences, foregroundPackage: String): Boolean {
        // Check blocked apps
        val blockedJson = prefs.getString(KEY_BLOCKED_APPS, "[]")
        try {
            val arr = JSONArray(blockedJson)
            for (i in 0 until arr.length()) {
                if (arr.getString(i) == foregroundPackage) {
                    return true
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Parse blocked apps", e)
        }

        // Check Sleep Lock
        if (!prefs.getBoolean(KEY_SLEEP_LOCK_ENABLED, false)) return false

        val startStr = prefs.getString(KEY_SLEEP_LOCK_START, "22:00") ?: "22:00"
        val endStr = prefs.getString(KEY_SLEEP_LOCK_END, "07:00") ?: "07:00"
        if (!isInTimeRange(startStr, endStr)) return false

        return true
    }

    private fun isInTimeRange(startStr: String, endStr: String): Boolean {
        val (sh, sm) = parseTime(startStr)
        val (eh, em) = parseTime(endStr)
        val now = java.util.Calendar.getInstance()
        val currentMinutes = now.get(java.util.Calendar.HOUR_OF_DAY) * 60 + now.get(java.util.Calendar.MINUTE)
        val startMinutes = sh * 60 + sm
        val endMinutes = eh * 60 + em

        return if (startMinutes <= endMinutes) {
            currentMinutes in startMinutes until endMinutes
        } else {
            currentMinutes >= startMinutes || currentMinutes < endMinutes
        }
    }

    private fun parseTime(s: String): Pair<Int, Int> {
        val parts = s.split(":")
        return Pair(
            parts.getOrElse(0) { "0" }.toIntOrNull() ?: 0,
            parts.getOrElse(1) { "0" }.toIntOrNull() ?: 0
        )
    }

    private fun startLockActivity() {
        val intent = Intent(this, LockActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_NO_HISTORY)
        }
        try {
            startActivity(intent)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start LockActivity", e)
        }
    }

    override fun onInterrupt() {}

    override fun onServiceConnected() {
        super.onServiceConnected()
        Log.d(TAG, "GenetAccessibilityService connected")
    }

    companion object {
        const val TAG = "GenetAccessibility"
        const val PREFS_NAME = "GenetConfig"
        const val KEY_BLOCKED_APPS = "blocked_apps"
        const val KEY_SLEEP_LOCK_ENABLED = "sleep_lock_enabled"
        const val KEY_SLEEP_LOCK_START = "sleep_lock_start"
        const val KEY_SLEEP_LOCK_END = "sleep_lock_end"
    }
}
