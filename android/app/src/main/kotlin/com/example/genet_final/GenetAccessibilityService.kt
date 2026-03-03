package com.example.genet_final

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import org.json.JSONArray
import org.json.JSONObject

class GenetAccessibilityService : AccessibilityService() {

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event?.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return
        val pkg = event.packageName?.toString() ?: return
        if (pkg == packageName) return // Don't lock when Genet app is open

        val prefs = getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
        val startStr = prefs.getString(KEY_SLEEP_LOCK_START, "22:00") ?: "22:00"
        val endStr = prefs.getString(KEY_SLEEP_LOCK_END, "07:00") ?: "07:00"
        val inBlockedTime = isInBlockedTimeWindow(prefs, startStr, endStr)
        val blockedSet = getBlockedPackagesSet(prefs)
        val blocked = blockedSet.contains(pkg)
        Log.d("GENET", "foreground=$pkg inBlockedTime=$inBlockedTime blocked=$blocked listSize=${blockedSet.size}")
        val shouldLock = inBlockedTime && blocked
        if (shouldLock) {
            Log.d(TAG, "package=$pkg inBlockedTime=$inBlockedTime blocked=$blocked start=$startStr end=$endStr")
            appendBlockedEvent(pkg, System.currentTimeMillis(), "blocked")
            startLockActivity(pkg)
        }
    }

    /** חסימה רק אם שני התנאים: (A) בתוך חלון שעות (B) ברשימת blockedPackages. */
    private fun isInBlockedTimeWindow(prefs: android.content.SharedPreferences, startStr: String, endStr: String): Boolean {
        if (!prefs.getBoolean(KEY_SLEEP_LOCK_ENABLED, false) && !prefs.getBoolean(KEY_NIGHT_MODE_ACTIVE, false)) return false
        return isInTimeRange(startStr, endStr)
    }

    private fun getBlockedPackagesSet(prefs: android.content.SharedPreferences): Set<String> {
        val base = cachedBlockedPackages?.toMutableSet() ?: run {
            val set = mutableSetOf<String>()
            val blockedJson = prefs.getString(KEY_BLOCKED_APPS, "[]") ?: "[]"
            try {
                val arr = JSONArray(blockedJson)
                for (i in 0 until arr.length()) {
                    arr.optString(i)?.takeIf { it.isNotEmpty() }?.let { set.add(it) }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Parse blocked apps", e)
            }
            set
        }
        if (prefs.getBoolean(KEY_BLOCK_WEB_SEARCH, true)) base.addAll(WEB_SEARCH_PACKAGES)
        return base
    }

    private fun appendBlockedEvent(packageName: String, timestamp: Long, type: String) {
        try {
            val prefs = getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
            val existing = prefs.getString(KEY_REPORT_EVENTS, "[]") ?: "[]"
            val arr = JSONArray(existing)
            arr.put(JSONObject().put("p", packageName).put("t", timestamp).put("e", type))
            prefs.edit().putString(KEY_REPORT_EVENTS, arr.toString()).apply()
        } catch (e: Exception) {
            Log.e(TAG, "appendBlockedEvent", e)
        }
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

    private fun startLockActivity(blockedPackage: String) {
        val intent = Intent(this, LockActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_NO_HISTORY)
            putExtra(EXTRA_BLOCKED_PACKAGE, blockedPackage)
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
        @Volatile var cachedBlockedPackages: List<String>? = null
        fun updateBlockedPackages(packages: List<String>) { cachedBlockedPackages = packages }
        const val KEY_BLOCKED_APPS = "blocked_apps"
        const val KEY_SLEEP_LOCK_ENABLED = "sleep_lock_enabled"
        const val KEY_SLEEP_LOCK_START = "sleep_lock_start"
        const val KEY_SLEEP_LOCK_END = "sleep_lock_end"
        const val KEY_NIGHT_MODE_ACTIVE = "night_mode_active"
        const val KEY_REPORT_EVENTS = "report_events"
        const val ACTION_CONFIG_CHANGED = "com.example.genet_final.CONFIG_CHANGED"
        const val EXTRA_BLOCKED_PACKAGE = "blocked_package"
        const val KEY_BLOCK_WEB_SEARCH = "block_web_search"

        /** Web/Search Block: חבילות גלישה/חיפוש – מוסיפים לרשימת החסימה בזמן חלון כשהאופציה מופעלת. */
        val WEB_SEARCH_PACKAGES: Set<String> = setOf(
            "com.google.android.googlequicksearchbox",  // Google App / Search
            "com.android.chrome",                         // Chrome
            "com.android.browser",                        // Android Browser
            "com.sec.android.app.sbrowser",               // Samsung Internet
            "com.mi.globalbrowser",                       // Xiaomi/Mi Browser
            "org.mozilla.firefox",                       // Firefox
            "com.microsoft.emmx"                          // Microsoft Edge
        )

        /** לבדיקה ב-LockActivity: האם עדיין צריך להציג overlay (חלון שעות + ברשימה). */
        @JvmStatic
        fun shouldStillShowLock(prefs: android.content.SharedPreferences, blockedPackage: String): Boolean {
            if (blockedPackage.isEmpty()) return false
            val startStr = prefs.getString(KEY_SLEEP_LOCK_START, "22:00") ?: "22:00"
            val endStr = prefs.getString(KEY_SLEEP_LOCK_END, "07:00") ?: "07:00"
            val inBlockedTime = (prefs.getBoolean(KEY_SLEEP_LOCK_ENABLED, false) || prefs.getBoolean(KEY_NIGHT_MODE_ACTIVE, false)) && isInTimeRangeStatic(startStr, endStr)
            val set = getBlockedPackagesSetStatic(prefs)
            return inBlockedTime && set.contains(blockedPackage)
        }

        private fun isInTimeRangeStatic(startStr: String, endStr: String): Boolean {
            val (sh, sm) = startStr.split(":").let { Pair(it.getOrElse(0) { "0" }.toIntOrNull() ?: 0, it.getOrElse(1) { "0" }.toIntOrNull() ?: 0) }
            val (eh, em) = endStr.split(":").let { Pair(it.getOrElse(0) { "0" }.toIntOrNull() ?: 0, it.getOrElse(1) { "0" }.toIntOrNull() ?: 0) }
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

        private fun getBlockedPackagesSetStatic(prefs: android.content.SharedPreferences): Set<String> {
            val base = cachedBlockedPackages?.toMutableSet() ?: run {
                val set = mutableSetOf<String>()
                val blockedJson = prefs.getString(KEY_BLOCKED_APPS, "[]") ?: "[]"
                try {
                    val arr = JSONArray(blockedJson)
                    for (i in 0 until arr.length()) {
                        arr.optString(i)?.takeIf { it.isNotEmpty() }?.let { set.add(it) }
                    }
                } catch (_: Exception) {}
                set
            }
            if (prefs.getBoolean(KEY_BLOCK_WEB_SEARCH, true)) base.addAll(WEB_SEARCH_PACKAGES)
            return base
        }
    }
}
