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
    @Volatile private var lastBlockedApp = false

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
        val eventType = event?.eventType ?: return
        if (eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED && eventType != AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED) return
        val prefs = getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
        val isChildMode = prefs.getBoolean(KEY_IS_CHILD_MODE, false)
        if (!isChildMode) {
            Log.d("GENET", "Parent mode detected - skipping blocks")
            handler.post { overlayManager.hide() }
            return
        }
        Log.d("GENET", "Child mode active - applying restrictions")
        val foregroundPackage = event.packageName?.toString()
        if (foregroundPackage == null || foregroundPackage.isBlank()) {
            Log.d("GENET", "Skipping block because package is null/blank")
            return
        }
        Log.d("GENET", "Foreground package: $foregroundPackage")
        val genetPackage = applicationContext.packageName
        if (foregroundPackage == genetPackage || foregroundPackage.startsWith("io.flutter")) {
            Log.d("GENET", "Skipping block for Genet")
            lastForegroundPkg = foregroundPackage
            lastShouldShowOverlay = false
            lastBlockedApp = false
            debounceRunnable?.let { handler.removeCallbacks(it) }
            handler.post { overlayManager.hide() }
            return
        }
        if (foregroundPackage in PERMISSION_CONTROLLER_PACKAGES) {
            Log.d("GENET", "Skipping block for permission screen")
            lastForegroundPkg = foregroundPackage
            lastShouldShowOverlay = false
            lastBlockedApp = false
            debounceRunnable?.let { handler.removeCallbacks(it) }
            handler.post { overlayManager.hide() }
            return
        }
        val pkgFromEvent = event.packageName?.toString()
        val mayBlockSettings = event != null &&
            pkgFromEvent != null &&
            pkgFromEvent.isNotBlank() &&
            pkgFromEvent == "com.android.settings" &&
            pkgFromEvent != genetPackage &&
            eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED
        if (mayBlockSettings) {
            Log.d("GENET", "Blocking Android Settings")
            performGlobalAction(AccessibilityService.GLOBAL_ACTION_HOME)
            Log.d("GENET", "HOME action triggered from settings block")
            lastForegroundPkg = foregroundPackage
            lastShouldShowOverlay = false
            lastBlockedApp = false
            debounceRunnable?.let { handler.removeCallbacks(it) }
            handler.post { overlayManager.hide() }
            return
        }
        if (foregroundPackage in SETTINGS_PACKAGES || foregroundPackage in PERMISSION_CONTROLLER_PACKAGES) {
            lastForegroundPkg = foregroundPackage
            lastShouldShowOverlay = false
            lastBlockedApp = false
            debounceRunnable?.let { handler.removeCallbacks(it) }
            handler.post { overlayManager.hide() }
            return
        }
        val approvedJson = prefs.getString(KEY_EXTENSION_APPROVED_UNTIL, "{}") ?: "{}"
        val now = System.currentTimeMillis()
        var temporarilyApproved = false
        try {
            val until = JSONObject(approvedJson).optLong(foregroundPackage, 0L)
            temporarilyApproved = until > now
        } catch (_: Exception) {}
        if (temporarilyApproved) {
            lastForegroundPkg = foregroundPackage
            lastShouldShowOverlay = false
            lastBlockedApp = false
            debounceRunnable?.let { handler.removeCallbacks(it) }
            handler.post { overlayManager.hide() }
            return
        }
        val whitelisted = isWhitelisted(foregroundPackage)
        val blockedSet = getBlockedPackagesSet(prefs)
        val blockedApp = !whitelisted && blockedSet.contains(foregroundPackage)
        Log.d(TAG, "foreground app: $foregroundPackage | is blocked: $blockedApp | is temporarily approved: $temporarilyApproved")

        lastForegroundPkg = foregroundPackage
        lastBlockedApp = blockedApp
        lastShouldShowOverlay = blockedApp
        if (blockedApp) appendBlockedEvent(foregroundPackage, System.currentTimeMillis(), "blocked")

        debounceRunnable?.let { handler.removeCallbacks(it) }
        debounceRunnable = Runnable {
            val runnablePrefs = getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
            val isChildModeNow = runnablePrefs.getBoolean(KEY_IS_CHILD_MODE, false)
            if (!isChildModeNow) {
                Log.d("GENET", "Parent mode detected in runnable - skipping all blocks")
                overlayManager.hide()
                debounceRunnable = null
                return@Runnable
            }
            if (lastForegroundPkg == applicationContext.packageName) {
                overlayManager.hide()
                debounceRunnable = null
                return@Runnable
            }
            if (lastForegroundPkg != null && (lastForegroundPkg in SETTINGS_PACKAGES || lastForegroundPkg in PERMISSION_CONTROLLER_PACKAGES)) {
                overlayManager.hide()
                debounceRunnable = null
                return@Runnable
            }
            if (lastShouldShowOverlay) {
                val showRecovery = lastBlockedApp && PermissionChecker.getMissingPermissions(applicationContext).isNotEmpty()
                if (showRecovery) {
                    val intent = Intent(applicationContext, MainActivity::class.java)
                    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    intent.putExtra(MainActivity.EXTRA_SHOW_PERMISSION_RECOVERY, true)
                    try { startActivity(intent) } catch (_: Exception) {}
                    overlayManager.hide()
                } else {
                    try { startActivity(homeIntent) } catch (_: Exception) {}
                    if (!overlayManager.isVisible()) overlayManager.show()
                }
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
        val now = System.currentTimeMillis()
        val approvedJson = prefs.getString(KEY_EXTENSION_APPROVED_UNTIL, "{}") ?: "{}"
        try {
            val approved = JSONObject(approvedJson)
            val iter = approved.keys()
            while (iter.hasNext()) {
                val pkg = iter.next()
                val until = approved.optLong(pkg, 0L)
                if (until > now) base.remove(pkg)
            }
        } catch (_: Exception) {}
        base.remove(applicationContext.packageName)
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
        const val KEY_EXTENSION_APPROVED_UNTIL = "extension_approved_until"
        const val KEY_IS_CHILD_MODE = "genet_is_child_mode"
        /** Set by boot receiver when in child mode and protection incomplete; cleared only after parent PIN in RebootLockActivity. */
        const val KEY_REQUIRE_PARENT_UNLOCK_AFTER_REBOOT = "genet_require_parent_unlock_after_reboot"
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

        /** Genet must never be blocked (debug + release package names). */
        private val GENET_PACKAGES = setOf("com.example.genet_final")

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
            val now = System.currentTimeMillis()
            val approvedJson = prefs.getString(KEY_EXTENSION_APPROVED_UNTIL, "{}") ?: "{}"
            try {
                val approved = JSONObject(approvedJson)
                val iter = approved.keys()
                while (iter.hasNext()) {
                    val pkg = iter.next()
                    val until = approved.optLong(pkg, 0L)
                    if (until > now) base.remove(pkg)
                }
            } catch (_: Exception) {}
            base.removeAll(GENET_PACKAGES)
            return base
        }
    }
}
