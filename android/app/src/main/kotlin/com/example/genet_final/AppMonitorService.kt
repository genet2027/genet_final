package com.example.genet_final

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import org.json.JSONArray
import org.json.JSONObject

/**
 * Foreground service: polls UsageStats for foreground package (every [tickIntervalMs]) when child mode is on.
 * If the app is blocked (same prefs / rules as [GenetAccessibilityService]), sends user to Home.
 * Does not replace Accessibility overlay; complements it when usage access is available.
 */
class AppMonitorService : Service() {

    private val handler = Handler(Looper.getMainLooper())
    private val tickIntervalMs = 500L
    private var lastHomeAt = 0L
    private var lastHomePkg: String? = null
    private val homeThrottleMs = 450L
    private var lastLockPkg: String? = null

    private val tickRunnable = object : Runnable {
        override fun run() {
            if (!running) return
            runTick()
            if (running) {
                handler.postDelayed(this, tickIntervalMs)
            }
        }
    }

    @Volatile
    private var running = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val notification = buildNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            ServiceCompat.startForeground(
                this,
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        running = true
        handler.removeCallbacks(tickRunnable)
        handler.post(tickRunnable)
        return START_STICKY
    }

    override fun onDestroy() {
        running = false
        handler.removeCallbacks(tickRunnable)
        super.onDestroy()
    }

    private fun runTick() {
        val prefs = getSharedPreferences(GenetAccessibilityService.PREFS_NAME, MODE_PRIVATE)
        if (!prefs.getBoolean(GenetAccessibilityService.KEY_IS_CHILD_MODE, false)) {
            running = false
            handler.removeCallbacks(tickRunnable)
            ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
            stopSelf()
            return
        }
        if (!UsageStatsHelper.hasUsageAccess(this)) {
            Log.d(TAG, "current package: (usage access off)")
            return
        }
        val pkg = UsageStatsHelper.getForegroundPackage(this)
        Log.d(TAG, "current package: ${pkg ?: "null"}")
        if (pkg.isNullOrBlank()) return
        val protectionLost = prefs.getBoolean(GenetAccessibilityService.KEY_VPN_PROTECTION_LOST, false)
        val sleepLockRestrictionActive =
            GenetAccessibilityService.isSleepLockRestrictionActive(prefs)
        if (Whitelist.isGenetApp(this, pkg)) {
            if (protectionLost) {
                Log.d("GENET_VPN", "ALLOWING GENET")
            }
            dismissVpnLockIfShowing()
            return
        }
        if (sleepLockRestrictionActive) {
            val restricted = !Whitelist.isWhitelisted(this, pkg)
            Log.d("GENET_SLEEP", "sleepLockActive=true package=$pkg restricted=$restricted")
            if (restricted) {
                sendHomeThrottled(pkg)
            }
            dismissVpnLockIfShowing()
            return
        }
        if (protectionLost) {
            if (shouldShowBlockScreen(pkg, prefs)) {
                Log.d("GENET_VPN", "BLOCKED APP DETECTED $pkg")
                showVpnLockFor(pkg)
            } else {
                Log.d("GENET_VPN", "APP NOT BLOCKED $pkg")
                dismissVpnLockIfShowing()
            }
            return
        }
        dismissVpnLockIfShowing()
        if (pkg in GenetAccessibilityService.SETTINGS_PACKAGES ||
            pkg in GenetAccessibilityService.PERMISSION_CONTROLLER_PACKAGES
        ) {
            return
        }
        if (!isBlockedForeground(pkg, prefs)) return
        sendHomeThrottled(pkg)
    }

    private fun shouldShowBlockScreen(foregroundPkg: String, prefs: SharedPreferences): Boolean {
        val rawBlocked = loadRawBlockedPackagesSet(prefs)
        val effectiveBlocked = loadBlockedPackagesSet(prefs)
        val excluded = isExcludedFromVpnLock(foregroundPkg)
        val packageBlocked = rawBlocked.contains(foregroundPkg)
        val inBlockedTime = effectiveBlocked.contains(foregroundPkg)
        val shouldShow = foregroundPkg.isNotBlank() &&
            packageBlocked &&
            inBlockedTime &&
            !excluded
        Log.d("GENET_VPN", "current foreground package: $foregroundPkg")
        Log.d("GENET_VPN", "whether package is blocked: $packageBlocked")
        Log.d("GENET_VPN", "whether package is in blocked time: $inBlockedTime")
        Log.d("GENET_VPN", "whether package is excluded: $excluded")
        Log.d("GENET_VPN", "final shouldShowBlockScreen result: $shouldShow")
        return shouldShow
    }

    private fun isExcludedFromVpnLock(pkg: String): Boolean {
        if (Whitelist.isWhitelisted(this, pkg)) return true
        if (pkg in GenetAccessibilityService.SETTINGS_PACKAGES) return true
        if (pkg in GenetAccessibilityService.PERMISSION_CONTROLLER_PACKAGES) return true
        return false
    }

    private fun isBlockedForeground(pkg: String, prefs: SharedPreferences): Boolean {
        val blocked = loadBlockedPackagesSet(prefs)
        return blocked.contains(pkg)
    }

    private fun loadRawBlockedPackagesSet(prefs: SharedPreferences): Set<String> {
        val base = mutableSetOf<String>()
        val blockedJson = prefs.getString(GenetAccessibilityService.KEY_BLOCKED_APPS, "[]") ?: "[]"
        try {
            val arr = JSONArray(blockedJson)
            for (i in 0 until arr.length()) {
                arr.optString(i)?.takeIf { it.isNotEmpty() }?.let { base.add(it) }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Parse blocked apps", e)
        }
        if (prefs.getBoolean(GenetAccessibilityService.KEY_BLOCK_WEB_SEARCH, true)) {
            base.addAll(GenetAccessibilityService.WEB_SEARCH_PACKAGES)
        }
        base.remove(packageName)
        base.removeAll(Whitelist.KNOWN_GENET_APP_IDS)
        return base
    }

    /** Mirrors [GenetAccessibilityService.getBlockedPackagesSet] logic (prefs JSON, not cache). */
    private fun loadBlockedPackagesSet(prefs: SharedPreferences): Set<String> {
        val base = mutableSetOf<String>()
        val blockedJson = prefs.getString(GenetAccessibilityService.KEY_BLOCKED_APPS, "[]") ?: "[]"
        try {
            val arr = JSONArray(blockedJson)
            for (i in 0 until arr.length()) {
                arr.optString(i)?.takeIf { it.isNotEmpty() }?.let { base.add(it) }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Parse blocked apps", e)
        }
        if (prefs.getBoolean(GenetAccessibilityService.KEY_BLOCK_WEB_SEARCH, true)) {
            base.addAll(GenetAccessibilityService.WEB_SEARCH_PACKAGES)
        }
        val now = System.currentTimeMillis()
        val approvedJson = prefs.getString(GenetAccessibilityService.KEY_EXTENSION_APPROVED_UNTIL, "{}") ?: "{}"
        try {
            val approved = JSONObject(approvedJson)
            val iter = approved.keys()
            while (iter.hasNext()) {
                val pkg = iter.next()
                val until = approved.optLong(pkg, 0L)
                if (until > now) base.remove(pkg)
            }
        } catch (_: Exception) {}
        base.remove(packageName)
        base.removeAll(Whitelist.KNOWN_GENET_APP_IDS)
        return base
    }

    private fun sendHomeThrottled(foregroundPkg: String) {
        val now = System.currentTimeMillis()
        if (foregroundPkg == lastHomePkg && now - lastHomeAt < homeThrottleMs) return
        lastHomeAt = now
        lastHomePkg = foregroundPkg
        val home = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        try {
            Log.d("GENET_VPN", "FORCING RETURN TO HOME")
            startActivity(home)
            Log.d(TAG, "sending user to home blockedPkg=$foregroundPkg")
        } catch (e: Exception) {
            Log.e(TAG, "send home failed", e)
        }
    }

    private fun showVpnLockFor(foregroundPkg: String) {
        if (LockActivity.isLockScreenVisible && foregroundPkg == lastLockPkg) return
        lastLockPkg = foregroundPkg
        val intent = Intent(this, LockActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            putExtra(GenetAccessibilityService.EXTRA_BLOCKED_PACKAGE, foregroundPkg)
        }
        try {
            startActivity(intent)
            Log.d("GENET_VPN", "LOCK SCREEN SHOWN FOR $foregroundPkg")
        } catch (e: Exception) {
            Log.e(TAG, "showVpnLockFor failed", e)
        }
    }

    private fun dismissVpnLockIfShowing() {
        if (!LockActivity.isLockScreenVisible && lastLockPkg == null) return
        sendBroadcast(Intent(GenetAccessibilityService.ACTION_DISMISS_LOCK))
        lastLockPkg = null
        Log.d("GENET_VPN", "LOCK SCREEN HIDDEN")
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = getSystemService(NotificationManager::class.java)
        val ch = NotificationChannel(
            CHANNEL_ID,
            "App monitoring",
            NotificationManager.IMPORTANCE_LOW,
        ).apply { setShowBadge(false) }
        nm.createNotificationChannel(ch)
    }

    private fun buildNotification(): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Genet")
            .setContentText("Monitoring active apps (child mode)")
            .setSmallIcon(android.R.drawable.ic_menu_info_details)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .build()
    }

    companion object {
        private const val TAG = "AppMonitor"
        private const val CHANNEL_ID = "app_monitor_channel"
        private const val NOTIFICATION_ID = 7101

        fun start(context: Context) {
            val i = Intent(context, AppMonitorService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(i)
            } else {
                @Suppress("DEPRECATION")
                context.startService(i)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, AppMonitorService::class.java))
        }
    }
}
