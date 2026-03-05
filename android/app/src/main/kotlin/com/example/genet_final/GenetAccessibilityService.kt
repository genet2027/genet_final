package com.example.genet_final

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.content.pm.PackageManager
import org.json.JSONArray
import org.json.JSONObject

class GenetAccessibilityService : AccessibilityService() {

    private val overlayManager by lazy { BlockOverlayManager(applicationContext) }
    private val handler = Handler(Looper.getMainLooper())
    private val debounceMs = 500L

    private val homeIntent: Intent by lazy {
        Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    }
    private var debounceRunnable: Runnable? = null
    @Volatile private var lastForegroundPkg: String? = null
    @Volatile private var lastShouldShowOverlay = false

    /** חבילות שאסור לחסום (Genet, Launcher, SystemUI, Recents בלבד) */
    private fun isWhitelisted(pkg: String): Boolean {
        if (pkg == packageName) return true
        if (pkg in WHITELIST_PACKAGES) return true
        if (pkg == defaultLauncherPackage) return true
        return false
    }

    private val defaultLauncherPackage: String? by lazy {
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
        val resolveInfo = packageManager.resolveActivity(intent, PackageManager.MATCH_DEFAULT_ONLY)
        resolveInfo?.activityInfo?.packageName
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event?.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return
        val pkg = event.packageName?.toString() ?: return
        val className = event.className?.toString() ?: ""

        val prefs = getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
        val permissionLockOn = prefs.getBoolean(KEY_PERMISSION_LOCK_ENABLED, false)
        val maintenanceEnd = prefs.getLong(KEY_MAINTENANCE_WINDOW_END, 0L)
        val inMaintenanceWindow = maintenanceEnd > 0 && System.currentTimeMillis() < maintenanceEnd
        val isSettings = pkg in SETTINGS_PACKAGES
        if (isSettings) Log.d(TAG, "Settings pkg=$pkg className=$className")

        val permissionScreenInSettings = isSettings && GenetAccessibilityService.isPermissionSettingsScreen(className)
        val permissionControllerPkg = pkg in PERMISSION_CONTROLLER_PACKAGES
        val blockByPermissionLock = !inMaintenanceWindow && permissionLockOn && (permissionScreenInSettings || permissionControllerPkg)
        val whitelisted = isWhitelisted(pkg)
        val blockedSet = getBlockedPackagesSet(prefs)
        val blockedApp = !whitelisted && blockedSet.contains(pkg)

        lastForegroundPkg = pkg
        lastShouldShowOverlay = blockedApp || blockByPermissionLock
        if (blockedApp) appendBlockedEvent(pkg, System.currentTimeMillis(), "blocked")

        if (whitelisted && !blockByPermissionLock) {
            lastShouldShowOverlay = false
        }

        debounceRunnable?.let { handler.removeCallbacks(it) }
        debounceRunnable = Runnable {
            if (lastShouldShowOverlay) {
                try { startActivity(homeIntent) } catch (_: Exception) {}
                if (!overlayManager.isVisible()) overlayManager.show()
            } else {
                overlayManager.hide()
            }
            debounceRunnable = null
        }
        handler.postDelayed(debounceRunnable!!, debounceMs)
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

    override fun onInterrupt() {}

    override fun onServiceConnected() {
        super.onServiceConnected()
        Log.d(TAG, "GenetAccessibilityService connected")
    }

    override fun onUnbind(intent: android.content.Intent?): Boolean {
        handler.post { overlayManager.hide() }
        return super.onUnbind(intent)
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
        const val ACTION_DISMISS_LOCK = "com.example.genet_final.DISMISS_LOCK"
        const val EXTRA_BLOCKED_PACKAGE = "blocked_package"
        const val KEY_BLOCK_WEB_SEARCH = "block_web_search"
        const val KEY_PERMISSION_LOCK_ENABLED = "permission_lock_enabled"
        const val KEY_MAINTENANCE_WINDOW_END = "maintenance_window_end"
        val SETTINGS_PACKAGES = setOf("com.android.settings", "com.google.android.settings")
        /** חבילות שמאפשרות שינוי הרשאות/התקנה – חסימה כשנעילת הרשאות פעילה */
        val PERMISSION_CONTROLLER_PACKAGES = setOf(
            "com.google.android.permissioncontroller",
            "com.android.permissioncontroller",
            "com.android.packageinstaller",
            "com.google.android.packageinstaller"
        )
        private val PERMISSION_SCREEN_PATTERNS = listOf(
            "accessibility", "usage", "overlay", "permission", "appops",
            "manageapplications", "appinfo", "applications", "installedappdetails", "specialapp"
        )
        @JvmStatic
        fun isPermissionSettingsScreen(className: String?): Boolean {
            if (className.isNullOrBlank()) return false
            val lower = className.lowercase()
            return PERMISSION_SCREEN_PATTERNS.any { lower.contains(it) }
        }
        /** רק Genet, Launcher, SystemUI, Recents – ללא Settings / Package Installer */
        val WHITELIST_PACKAGES = setOf("com.android.systemui")

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

        /** לבדיקה ב-LockActivity: האם עדיין צריך להציג overlay (האפליקציה עדיין ברשימת החסימה). */
        @JvmStatic
        fun shouldStillShowLock(prefs: android.content.SharedPreferences, blockedPackage: String): Boolean {
            if (blockedPackage.isEmpty()) return false
            val set = getBlockedPackagesSetStatic(prefs)
            return set.contains(blockedPackage)
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
