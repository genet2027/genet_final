package com.example.genet_final

import android.accessibilityservice.AccessibilityService
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.KeyEvent
import android.view.accessibility.AccessibilityEvent
import android.content.pm.PackageManager
import org.json.JSONArray
import org.json.JSONObject

class GenetAccessibilityService : AccessibilityService() {

    private val overlayManager by lazy { BlockOverlayManager(applicationContext) }
    private val handler = Handler(Looper.getMainLooper())
    private val debounceMs = 600L

    private var debounceRunnable: Runnable? = null
    @Volatile private var lastForegroundPkg: String? = null
    @Volatile private var lastShouldShowOverlay = false
    @Volatile private var lastBlockedApp = false
    /** When true, block overlay session active (single overlay instance; no duplicate views). */
    @Volatile private var overlayBlockSessionActive = false

    /** Throttle HOME spam while foreground stays blocked (same pkg within [HOME_THROTTLE_MS]). */
    private var lastHomeSentAt = 0L
    private var lastHomeSentPkg: String? = null
    private val homeThrottleMs = 450L

    /** חבילות שאסור לחסום (Genet, Launcher, SystemUI, Recents בלבד) — Genet ע"י [Whitelist.isGenetApp]. */
    private fun isWhitelisted(pkg: String): Boolean {
        if (Whitelist.isGenetApp(this, pkg)) return true
        if (pkg in WHITELIST_PACKAGES) return true
        if (pkg == defaultLauncherPackage) return true
        return false
    }

    private val defaultLauncherPackage: String? by lazy {
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
        val resolveInfo = packageManager.resolveActivity(intent, PackageManager.MATCH_DEFAULT_ONLY)
        resolveInfo?.activityInfo?.packageName
    }

    /** Throttled eject via [EmergencyEjector] to avoid loops / vibration. */
    private fun sendHomeThrottled(foregroundPkg: String?) {
        val pkg = foregroundPkg ?: ""
        val now = System.currentTimeMillis()
        if (pkg == lastHomeSentPkg && now - lastHomeSentAt < homeThrottleMs) return
        lastHomeSentAt = now
        lastHomeSentPkg = pkg
        EmergencyEjector.ejectToHome(this, TAG, pkg)
    }

    private fun exitParentModeOverlayCleanup() {
        Log.d("GENET", "Parent mode detected - skipping blocks")
        overlayBlockSessionActive = false
        handler.post { overlayManager.hide() }
    }

    private fun clearBlockStateAndHideOverlay(foregroundPackage: String) {
        lastForegroundPkg = foregroundPackage
        lastShouldShowOverlay = false
        lastBlockedApp = false
        overlayBlockSessionActive = false
        debounceRunnable?.let { handler.removeCallbacks(it) }
        handler.post { overlayManager.hide() }
    }

    private fun consumeForegroundGenetOverlay(foregroundPackage: String): Boolean {
        if (!Whitelist.isGenetApp(this, foregroundPackage)) return false
        Log.d(TAG, "overlay blocked: foreground=$foregroundPackage isGenetPackage=true (no overlay in Genet)")
        clearBlockStateAndHideOverlay(foregroundPackage)
        return true
    }

    private fun consumeForegroundPermissionControllerOverlay(foregroundPackage: String): Boolean {
        if (foregroundPackage !in PERMISSION_CONTROLLER_PACKAGES) return false
        Log.d("GENET", "Skipping block for permission screen")
        clearBlockStateAndHideOverlay(foregroundPackage)
        return true
    }

    private fun consumeSettingsWindowHomeOverlay(
        event: AccessibilityEvent,
        eventType: Int,
        foregroundPackage: String,
        genetPackage: String,
    ): Boolean {
        val pkgFromEvent = event.packageName?.toString()
        val mayBlockSettings = pkgFromEvent != null &&
            pkgFromEvent.isNotBlank() &&
            pkgFromEvent == "com.android.settings" &&
            pkgFromEvent != genetPackage &&
            eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED
        if (!mayBlockSettings) return false
        Log.d("GENET", "Blocking Android Settings")
        performGlobalAction(AccessibilityService.GLOBAL_ACTION_HOME)
        Log.d("GENET", "HOME action triggered from settings block")
        clearBlockStateAndHideOverlay(foregroundPackage)
        return true
    }

    private fun consumeForegroundSettingsFamilyOverlay(foregroundPackage: String): Boolean {
        if (foregroundPackage !in SETTINGS_PACKAGES && foregroundPackage !in PERMISSION_CONTROLLER_PACKAGES) return false
        clearBlockStateAndHideOverlay(foregroundPackage)
        return true
    }

    private fun isForegroundTemporarilyApproved(prefs: android.content.SharedPreferences, foregroundPackage: String): Boolean {
        val approvedJson = prefs.getString(KEY_EXTENSION_APPROVED_UNTIL, "{}") ?: "{}"
        val now = System.currentTimeMillis()
        return try {
            JSONObject(approvedJson).optLong(foregroundPackage, 0L) > now
        } catch (_: Exception) {
            false
        }
    }

    private fun consumeTemporarilyApprovedOverlay(
        prefs: android.content.SharedPreferences,
        foregroundPackage: String,
    ): Boolean {
        if (!isForegroundTemporarilyApproved(prefs, foregroundPackage)) return false
        clearBlockStateAndHideOverlay(foregroundPackage)
        return true
    }

    private fun executeDebouncedOverlayRunnableContents() {
        val runnablePrefs = getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
        if (!runnablePrefs.getBoolean(KEY_IS_CHILD_MODE, false)) {
            Log.d("GENET", "Parent mode detected in runnable - skipping all blocks")
            overlayBlockSessionActive = false
            overlayManager.hide()
            return
        }
        if (debouncedRunnableHideIfReturnedToGenet()) return
        if (debouncedRunnableHideIfSettingsOrPermissionForeground()) return
        if (!lastShouldShowOverlay) {
            overlayBlockSessionActive = false
            overlayManager.hide()
            return
        }
        debouncedRunnableApplyBlockedOverlay()
    }

    private fun debouncedRunnableHideIfReturnedToGenet(): Boolean {
        if (!Whitelist.isGenetApp(this, lastForegroundPkg)) return false
        Log.d(TAG, "overlay hide: returned to Genet pkg=$lastForegroundPkg isGenetPackage=true")
        overlayBlockSessionActive = false
        overlayManager.hide()
        return true
    }

    private fun debouncedRunnableHideIfSettingsOrPermissionForeground(): Boolean {
        val pkg = lastForegroundPkg
        if (pkg == null) return false
        if (pkg !in SETTINGS_PACKAGES && pkg !in PERMISSION_CONTROLLER_PACKAGES) return false
        overlayBlockSessionActive = false
        overlayManager.hide()
        return true
    }

    private fun debouncedRunnableApplyBlockedOverlay() {
        if (Whitelist.isGenetApp(this, lastForegroundPkg)) {
            Log.d(TAG, "overlay skip: genet foreground pkg=$lastForegroundPkg isGenetPackage=true")
            overlayBlockSessionActive = false
            overlayManager.hide()
            return
        }
        Log.d(TAG, "overlay allowed: external pkg=$lastForegroundPkg isGenetPackage=false")
        val showRecovery = lastBlockedApp && PermissionChecker.getMissingPermissions(applicationContext).isNotEmpty()
        if (showRecovery) {
            val intent = Intent(applicationContext, MainActivity::class.java)
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            intent.putExtra(MainActivity.EXTRA_SHOW_PERMISSION_RECOVERY, true)
            try {
                startActivity(intent)
            } catch (_: Exception) {
                // Activity not startable; keep overlay hidden path unchanged.
            }
            overlayBlockSessionActive = false
            overlayManager.hide()
            return
        }
        sendHomeThrottled(lastForegroundPkg)
        lastForegroundPkg?.let { pkg ->
            EnforcementBridge.emitAppBlocked(pkg)
        }
        if (!overlayManager.isVisible()) {
            overlayManager.show()
            Log.d(TAG, "overlay shown fg=$lastForegroundPkg blocked=true")
        } else {
            Log.d(TAG, "overlay already active fg=$lastForegroundPkg")
        }
        overlayBlockSessionActive = true
    }

    private fun scheduleDebouncedBlockedHandling(prefs: android.content.SharedPreferences, foregroundPackage: String) {
        val whitelisted = isWhitelisted(foregroundPackage)
        val sleepLockRestrictionActive = isSleepLockRestrictionActive(prefs)
        val blockedSet = getBlockedPackagesSet(prefs)
        val blockedApp = !whitelisted &&
            (sleepLockRestrictionActive || blockedSet.contains(foregroundPackage))
        Log.d(
            TAG,
            "foreground=$foregroundPackage blocked=$blockedApp isGenetPackage=${Whitelist.isGenetApp(this, foregroundPackage)} tempApproved=false sleepLockRestrictionActive=$sleepLockRestrictionActive",
        )

        lastForegroundPkg = foregroundPackage
        lastBlockedApp = blockedApp
        lastShouldShowOverlay = blockedApp
        if (blockedApp) appendBlockedEvent(foregroundPackage, System.currentTimeMillis(), "blocked")

        debounceRunnable?.let { handler.removeCallbacks(it) }
        debounceRunnable = Runnable {
            executeDebouncedOverlayRunnableContents()
            debounceRunnable = null
        }
        handler.postDelayed(debounceRunnable!!, debounceMs)
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        val eventType = event?.eventType ?: return
        if (!ForegroundAppDetector.isWindowForegroundEvent(eventType)) return
        val prefs = getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
        if (!prefs.getBoolean(KEY_IS_CHILD_MODE, false)) {
            exitParentModeOverlayCleanup()
            return
        }
        Log.d("GENET", "Child mode active - applying restrictions")
        val foregroundPackage = ForegroundAppDetector.foregroundPackageFromEvent(event)
        if (foregroundPackage == null || foregroundPackage.isBlank()) {
            Log.d("GENET", "Skipping block because package is null/blank")
            return
        }
        Log.d("GENET", "Foreground package: $foregroundPackage")
        val genetPackage = applicationContext.packageName
        if (consumeForegroundGenetOverlay(foregroundPackage)) return
        if (consumeForegroundPermissionControllerOverlay(foregroundPackage)) return
        if (consumeSettingsWindowHomeOverlay(event, eventType, foregroundPackage, genetPackage)) return
        if (consumeForegroundSettingsFamilyOverlay(foregroundPackage)) return
        if (consumeTemporarilyApprovedOverlay(prefs, foregroundPackage)) return
        scheduleDebouncedBlockedHandling(prefs, foregroundPackage)
    }

    private fun getBlockedPackagesSet(prefs: android.content.SharedPreferences): Set<String> {
        return buildBlockedPackagesSet(applicationContext, prefs)
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

    private fun parseTime(s: String): Pair<Int, Int> {
        val parts = s.split(":")
        return Pair(
            parts.getOrElse(0) { "0" }.toIntOrNull() ?: 0,
            parts.getOrElse(1) { "0" }.toIntOrNull() ?: 0
        )
    }

    override fun onInterrupt() = Unit

    override fun onKeyEvent(event: KeyEvent): Boolean {
        val prefs = getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
        if (!prefs.getBoolean(KEY_IS_CHILD_MODE, false)) return super.onKeyEvent(event)
        if (event.keyCode != KeyEvent.KEYCODE_BACK) return super.onKeyEvent(event)
        if (event.action != KeyEvent.ACTION_DOWN) return super.onKeyEvent(event)
        if (overlayManager.isVisible() && lastShouldShowOverlay) {
            Log.d(TAG, "back blocked: service key event fg=$lastForegroundPkg")
            sendHomeThrottled(lastForegroundPkg)
            return true
        }
        return super.onKeyEvent(event)
    }

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
        const val KEY_VPN_PROTECTION_LOST = "genet_vpn_protection_lost"
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
            "com.chrome.beta",                            // Chrome Beta
            "com.chrome.dev",                             // Chrome Dev
            "com.android.browser",                        // Android Browser
            "com.sec.android.app.sbrowser",               // Samsung Internet
            "com.mi.globalbrowser",                       // Xiaomi/Mi Browser
            "org.mozilla.firefox",                       // Firefox
            "org.mozilla.firefox_beta",                  // Firefox Beta
            "com.microsoft.emmx",                        // Microsoft Edge
            "com.opera.browser",                         // Opera
            "com.opera.mini.native",                     // Opera Mini
            "com.brave.browser"                          // Brave
        )

        /** לבדיקה ב-LockActivity: האם עדיין צריך להציג overlay (האפליקציה עדיין ברשימת החסימה). */
        @JvmStatic
        fun shouldStillShowLock(prefs: android.content.SharedPreferences, blockedPackage: String): Boolean {
            if (blockedPackage.isEmpty()) return false
            if (isSleepLockRestrictionActive(prefs)) return true
            val set = getBlockedPackagesSetStatic(prefs)
            return set.contains(blockedPackage)
        }

        @JvmStatic
        fun isSleepLockRestrictionActive(prefs: android.content.SharedPreferences): Boolean {
            return prefs.getBoolean(KEY_NIGHT_MODE_ACTIVE, false)
        }

        /**
         * Same blocked set as [GenetAccessibilityService.getBlockedPackagesSet] — shared with [BlockedAppsRepository].
         */
        @JvmStatic
        fun buildBlockedPackagesSet(context: Context, prefs: android.content.SharedPreferences): Set<String> {
            val base = cachedBlockedPackages?.toMutableSet() ?: run {
                val set = mutableSetOf<String>()
                val blockedJson = prefs.getString(KEY_BLOCKED_APPS, "[]") ?: "[]"
                try {
                    val arr = JSONArray(blockedJson)
                    for (i in 0 until arr.length()) {
                        arr.optString(i).takeIf { it.isNotEmpty() }?.let { set.add(it) }
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
            } catch (_: Exception) {
                // Malformed approved-until JSON; keep base set unchanged.
            }
            base.remove(context.packageName)
            base.removeAll(Whitelist.KNOWN_GENET_APP_IDS)
            return base
        }

        private fun getBlockedPackagesSetStatic(prefs: android.content.SharedPreferences): Set<String> {
            val base = cachedBlockedPackages?.toMutableSet() ?: run {
                val set = mutableSetOf<String>()
                val blockedJson = prefs.getString(KEY_BLOCKED_APPS, "[]") ?: "[]"
                try {
                    val arr = JSONArray(blockedJson)
                    for (i in 0 until arr.length()) {
                        arr.optString(i).takeIf { it.isNotEmpty() }?.let { set.add(it) }
                    }
                } catch (_: Exception) {
                    // Malformed blocked-apps JSON; fall back to empty set for this branch.
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
            } catch (_: Exception) {
                // Malformed approved-until JSON; keep base set unchanged.
            }
            base.removeAll(Whitelist.KNOWN_GENET_APP_IDS)
            return base
        }
    }
}
