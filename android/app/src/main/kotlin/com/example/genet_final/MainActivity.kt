package com.example.genet_final

import android.app.Activity
import android.app.admin.DevicePolicyManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.Drawable
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.net.VpnService
import android.os.Build
import android.os.SystemClock
import androidx.core.content.ContextCompat
import android.provider.Settings
import android.util.Base64
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayOutputStream

/**
 * Mirrors [lib/models/installed_app.dart] browser / WebView sets for inventory only.
 * Used to treat some OEM browsers as launchable when [PackageManager.getLaunchIntentForPackage] is null
 * but the package still resolves http(s) VIEW (user-facing browser).
 */
private val WEBVIEW_ENGINE_PACKAGES = setOf(
    "com.google.android.webview",
    "com.android.webview",
    "com.google.android.trichromelibrary",
)

private val KNOWN_BROWSER_EXACT_PACKAGES = setOf(
    "com.android.chrome",
    "com.android.browser",
    "com.chrome.beta",
    "com.chrome.dev",
    "com.chrome.canary",
    "com.google.android.apps.chrome",
    "org.mozilla.firefox",
    "org.mozilla.fennec",
    "org.mozilla.firefox_beta",
    "com.opera.browser",
    "com.opera.mini.native",
    "com.opera.gx",
    "com.microsoft.emmx",
    "com.sec.android.app.sbrowser",
    "com.brave.browser",
    "com.duckduckgo.mobile.android",
    "org.torproject.torbrowser",
    "com.vivaldi.browser",
    "com.kiwibrowser.browser",
    "com.yandex.browser",
    "com.uc.browser.en",
    "com.ucmobile.intl",
    "com.ucmobile.lite",
    "com.ucmobile.x86",
    "com.qwant.mobilenext",
    "com.ecosia.android",
    "mark.via.gp",
    "com.apus.browser",
    "com.cake.browser",
    "com.stoutner.privacybrowser.standard",
    "org.bromite.bromite",
    "pure.lite.browser",
    "com.pure.browser.plus",
    "com.huawei.browser",
    "com.huawei.android.browser",
    "com.mi.global.browser",
    "com.heytap.browser",
    "com.coloros.browser",
    "com.oneplus.browser",
    "com.vivo.browser",
    "com.oplus.browser",
)

private val KNOWN_BROWSER_PACKAGE_PREFIXES = listOf(
    "com.chrome.",
    "org.mozilla.",
    "com.opera.",
    "com.microsoft.emmx",
    "com.vivaldi.",
    "com.brave.",
    "com.duckduckgo.",
    "com.kiwibrowser",
    "com.yandex.browser",
    "com.sec.android.app.sbrowser",
    "com.huawei.browser",
)

private fun isKnownBrowserPackageForInventory(packageLower: String): Boolean {
    if (WEBVIEW_ENGINE_PACKAGES.contains(packageLower)) return false
    if (KNOWN_BROWSER_EXACT_PACKAGES.contains(packageLower)) return true
    return KNOWN_BROWSER_PACKAGE_PREFIXES.any { packageLower.startsWith(it) }
}

private fun queryIntentActivitiesForInventory(pm: PackageManager, intent: Intent): Boolean {
    val matchFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
        PackageManager.MATCH_ALL
    } else {
        PackageManager.MATCH_DEFAULT_ONLY
    }
    return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
        pm.queryIntentActivities(
            intent,
            PackageManager.ResolveInfoFlags.of(matchFlags.toLong()),
        ).isNotEmpty()
    } else {
        @Suppress("DEPRECATION")
        pm.queryIntentActivities(intent, matchFlags).isNotEmpty()
    }
}

/** Some browsers only register https handlers; try both. Requires matching <queries> on API 30+ without QUERY_ALL_PACKAGES. */
private fun packageResolvesBrowsableHttp(pm: PackageManager, pkg: String): Boolean {
    for (scheme in listOf("http", "https")) {
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse("$scheme://")).apply {
            addCategory(Intent.CATEGORY_BROWSABLE)
            setPackage(pkg)
        }
        if (queryIntentActivitiesForInventory(pm, intent)) return true
    }
    return false
}

/** When [getLaunchIntentForPackage] is null but the app still exposes a launcher activity to the system resolver. */
private fun packageHasLauncherActivityQuery(pm: PackageManager, pkg: String): Boolean {
    val intent = Intent(Intent.ACTION_MAIN).apply {
        addCategory(Intent.CATEGORY_LAUNCHER)
        setPackage(pkg)
    }
    return queryIntentActivitiesForInventory(pm, intent)
}

/** Launch intent when present; for known browsers only, http(s) VIEW then launcher query as narrow fallbacks. */
private fun isUserLaunchableForInventory(pm: PackageManager, pkg: String): Boolean {
    if (pm.getLaunchIntentForPackage(pkg) != null) return true
    val p = pkg.lowercase()
    if (!isKnownBrowserPackageForInventory(p)) return false
    if (packageResolvesBrowsableHttp(pm, pkg)) return true
    return packageHasLauncherActivityQuery(pm, pkg)
}

class MainActivity : FlutterActivity() {

    private val CHANNEL = "com.example.genet_final/config"
    private val VPN_CHANNEL = "genet/vpn"
    private val INSTALLED_APPS_EVENTS_CHANNEL = "com.example.genet_final/installed_apps_events"
    private var installedAppsChangeReceiver: BroadcastReceiver? = null

    companion object {
        const val EXTRA_SHOW_PERMISSION_RECOVERY = "show_permission_recovery"
        @Volatile var pendingPermissionRecovery = false
        private const val REQUEST_VPN_PREPARE = 0x7103
    }

    /**
     * Initial route sent to Flutter. Set to null for default behavior (Role Select).
     */
    override fun getInitialRoute(): String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        EnforcementBridge.register(flutterEngine.dartExecutor.binaryMessenger)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, INSTALLED_APPS_EVENTS_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    registerInstalledAppsChangeReceiver(events)
                }

                override fun onCancel(arguments: Any?) {
                    unregisterInstalledAppsChangeReceiver()
                }
            }
        )
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, VPN_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "setBlockedApps" -> {
                    @Suppress("UNCHECKED_CAST")
                    val list = call.argument<List<String>>("packages") ?: emptyList()
                    applyVpnBlockedList(list)
                    result.success(null)
                }
                "startVpn" -> {
                    if (NetworkBlocker.resolveEffectiveBlockedPackages(this@MainActivity).isEmpty()) {
                        Log.i("GenetVpn", "No blocked apps, skipping VPN")
                        if (VpnState.isVpnRunning) {
                            dispatchVpnServiceAction(GenetVpnService.ACTION_STOP)
                        }
                        result.success(mapOf("started" to false, "needsPermission" to false))
                        return@setMethodCallHandler
                    }
                    if (getVpnStatus()) {
                        result.success(mapOf("started" to false, "needsPermission" to false))
                        return@setMethodCallHandler
                    }
                    val prepareIntent = VpnService.prepare(this@MainActivity)
                    if (prepareIntent != null) {
                        runOnUiThread {
                            try {
                                startActivityForResult(prepareIntent, REQUEST_VPN_PREPARE)
                            } catch (e: Exception) {
                                Log.e("GenetVpn", "VPN consent startActivityForResult failed", e)
                            }
                        }
                        result.success(mapOf("started" to false, "needsPermission" to true))
                    } else {
                        if (VpnState.isVpnRunning) {
                            Log.i("GenetVpn", "VPN STATE RESET")
                        }
                        dispatchVpnServiceAction(GenetVpnService.ACTION_START)
                        result.success(mapOf("started" to true, "needsPermission" to false))
                    }
                }
                "stopVpn" -> {
                    dispatchVpnServiceAction(GenetVpnService.ACTION_STOP)
                    result.success(null)
                }
                "refreshVpn" -> {
                    @Suppress("UNCHECKED_CAST")
                    val list = call.argument<List<String>>("packages")
                    if (list != null) {
                        applyVpnBlockedList(list)
                    }
                    if (VpnState.isVpnRunning || getVpnStatus()) {
                        dispatchVpnServiceAction(GenetVpnService.ACTION_RESTART)
                    }
                    result.success(null)
                }
                "isVpnRunning" -> result.success(VpnState.isVpnRunning)
                "getVpnStatus" -> result.success(getVpnStatus())
                "getVpnProtectionStatus" -> result.success(getVpnProtectionStatus())
                "isVpnPermissionGranted" -> result.success(VpnService.prepare(this@MainActivity) == null)
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "setPin" -> {
                    val pin = call.argument<String>("pin") ?: "1234"
                    getGenetPrefs().edit().putString("parent_pin", pin).apply()
                    result.success(null)
                }
                "setSleepLock" -> {
                    getGenetPrefs().edit()
                        .putBoolean("sleep_lock_enabled", call.argument<Boolean>("enabled") ?: false)
                        .putString("sleep_lock_start", call.argument<String>("start") ?: "22:00")
                        .putString("sleep_lock_end", call.argument<String>("end") ?: "07:00")
                        .apply()
                    sendBroadcast(android.content.Intent(GenetAccessibilityService.ACTION_CONFIG_CHANGED))
                    result.success(null)
                }
                "setBlockedApps", "setBlockedPackages" -> {
                    val list = call.argument<List<String>>("packages") ?: emptyList()
                    val filtered = list.filter { it != packageName }
                    android.util.Log.d("GENET", "setBlockedPackages received size=${filtered.size}")
                    getGenetPrefs().edit().putString(GenetAccessibilityService.KEY_BLOCKED_APPS, JSONArray(filtered).toString()).apply()
                    GenetAccessibilityService.updateBlockedPackages(filtered)
                    sendBroadcast(android.content.Intent(GenetAccessibilityService.ACTION_CONFIG_CHANGED))
                    result.success(null)
                }
                "setNightModeActive" -> {
                    val active = call.argument<Boolean>("active") ?: false
                    getGenetPrefs().edit().putBoolean(GenetAccessibilityService.KEY_NIGHT_MODE_ACTIVE, active).apply()
                    sendBroadcast(android.content.Intent(GenetAccessibilityService.ACTION_CONFIG_CHANGED))
                    result.success(null)
                }
                "setBlockWebSearch" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: true
                    getGenetPrefs().edit().putBoolean(GenetAccessibilityService.KEY_BLOCK_WEB_SEARCH, enabled).apply()
                    sendBroadcast(android.content.Intent(GenetAccessibilityService.ACTION_CONFIG_CHANGED))
                    result.success(null)
                }
                "setPermissionLockEnabled" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    getGenetPrefs().edit().putBoolean(GenetAccessibilityService.KEY_PERMISSION_LOCK_ENABLED, enabled).apply()
                    result.success(null)
                }
                "setVpnProtectionLost" -> {
                    val lost = call.argument<Boolean>("lost") ?: false
                    getGenetPrefs().edit()
                        .putBoolean(GenetAccessibilityService.KEY_VPN_PROTECTION_LOST, lost)
                        .apply()
                    sendBroadcast(android.content.Intent(GenetAccessibilityService.ACTION_CONFIG_CHANGED))
                    result.success(null)
                }
                "getPermissionLockEnabled" -> {
                    result.success(getGenetPrefs().getBoolean(GenetAccessibilityService.KEY_PERMISSION_LOCK_ENABLED, false))
                }
                "setMaintenanceWindowEnd" -> {
                    val endMs = (call.argument<Number>("endMs")?.toLong()) ?: 0L
                    getGenetPrefs().edit().putLong(GenetAccessibilityService.KEY_MAINTENANCE_WINDOW_END, endMs).apply()
                    result.success(null)
                }
                "setExtensionApproved" -> {
                    @Suppress("UNCHECKED_CAST")
                    val map = call.argument<Map<String, Any>>("map") ?: emptyMap<String, Any>()
                    val json = JSONObject()
                    map.forEach { (pkg, value) ->
                        val until = (value as? Number)?.toLong() ?: 0L
                        if (until > 0L) json.put(pkg, until)
                    }
                    getGenetPrefs().edit().putString(GenetAccessibilityService.KEY_EXTENSION_APPROVED_UNTIL, json.toString()).apply()
                    sendBroadcast(android.content.Intent(GenetAccessibilityService.ACTION_CONFIG_CHANGED))
                    result.success(null)
                }
                "reportEvent" -> {
                    val pkg = call.argument<String>("packageName") ?: ""
                    val ts = call.argument<Number>("timestamp")?.toLong() ?: System.currentTimeMillis()
                    val type = call.argument<String>("type") ?: "event"
                    appendReportEvent(pkg, ts, type)
                    result.success(null)
                }
                "openAccessibilitySettings" -> {
                    startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                    result.success(null)
                }
                "openUsageAccessSettings" -> {
                    startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS))
                    result.success(null)
                }
                "openOverlaySettings" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        val intent = Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:$packageName"))
                        startActivity(intent)
                    }
                    result.success(null)
                }
                "isAccessibilityServiceEnabled" -> result.success(PermissionChecker.isAccessibilityServiceEnabled(this))
                "getMissingPermissions" -> result.success(PermissionChecker.getMissingPermissions(this))
                "getInitialRoute" -> result.success(getInitialRoute())
                "getPackageName" -> result.success(packageName)
                "getInstalledApps" -> {
                    try {
                        result.success(getInstalledApps())
                    } catch (e: Exception) {
                        Log.e("MainActivity", "getInstalledApps", e)
                        result.success(emptyList<Map<String, Any>>())
                    }
                }
                "shouldShowPermissionRecovery" -> {
                    val show = pendingPermissionRecovery
                    pendingPermissionRecovery = false
                    result.success(show)
                }
                "enableDeviceAdmin" -> {
                    enableDeviceAdmin()
                    result.success(null)
                }
                "setChildMode" -> {
                    val isChildMode = call.argument<Boolean>("isChildMode") ?: false
                    getGenetPrefs().edit().putBoolean(GenetAccessibilityService.KEY_IS_CHILD_MODE, isChildMode).apply()
                    if (!isChildMode) AppMonitorService.stop(this)
                    result.success(null)
                }
                "getIsDeviceAdminEnabled" -> result.success(isDeviceAdminEnabled())
                "openBatteryOptimizationSettings" -> {
                    openBatteryOptimizationSettings()
                    result.success(null)
                }
                "isIgnoringBatteryOptimizations" -> result.success(isIgnoringBatteryOptimizations())
                "getElapsedRealtimeMs" -> result.success(SystemClock.elapsedRealtime())
                else -> result.notImplemented()
            }
        }
    }

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        if (intent?.getBooleanExtra(EXTRA_SHOW_PERMISSION_RECOVERY, false) == true) pendingPermissionRecovery = true
    }

    override fun onDestroy() {
        unregisterInstalledAppsChangeReceiver()
        super.onDestroy()
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_VPN_PREPARE && resultCode == Activity.RESULT_OK) {
            startGenetVpnServiceIfReady()
        }
    }

    private fun startGenetVpnServiceIfReady() {
        if (VpnState.isVpnRunning) return
        if (NetworkBlocker.resolveEffectiveBlockedPackages(this).isEmpty()) return
        dispatchVpnServiceAction(GenetVpnService.ACTION_START)
    }

    private fun registerInstalledAppsChangeReceiver(events: EventChannel.EventSink?) {
        unregisterInstalledAppsChangeReceiver()
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_PACKAGE_ADDED)
            addAction(Intent.ACTION_PACKAGE_REMOVED)
            addAction(Intent.ACTION_PACKAGE_CHANGED)
            addDataScheme("package")
        }
        installedAppsChangeReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: android.content.Context?, intent: Intent?) {
                val action = intent?.action ?: return
                val pkg = intent.data?.schemeSpecificPart ?: return
                events?.success(
                    mapOf(
                        "action" to action,
                        "package" to pkg,
                    )
                )
            }
        }
        ContextCompat.registerReceiver(
            this,
            installedAppsChangeReceiver,
            filter,
            ContextCompat.RECEIVER_NOT_EXPORTED
        )
    }

    private fun unregisterInstalledAppsChangeReceiver() {
        val receiver = installedAppsChangeReceiver ?: return
        try {
            unregisterReceiver(receiver)
        } catch (_: IllegalArgumentException) {
        }
        installedAppsChangeReceiver = null
    }

    override fun onResume() {
        super.onResume()
        if (getGenetPrefs().getBoolean(GenetAccessibilityService.KEY_REQUIRE_PARENT_UNLOCK_AFTER_REBOOT, false)) {
            startActivity(Intent(this, RebootLockActivity::class.java))
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (intent.getBooleanExtra(EXTRA_SHOW_PERMISSION_RECOVERY, false)) pendingPermissionRecovery = true
    }

    private fun appendReportEvent(packageName: String, timestamp: Long, type: String) {
        try {
            val prefs = getGenetPrefs()
            val existing = prefs.getString(GenetAccessibilityService.KEY_REPORT_EVENTS, "[]") ?: "[]"
            val arr = JSONArray(existing)
            arr.put(JSONObject().put("p", packageName).put("t", timestamp).put("e", type))
            prefs.edit().putString(GenetAccessibilityService.KEY_REPORT_EVENTS, arr.toString()).apply()
        } catch (_: Exception) {}
    }

    private fun getGenetPrefs() = getSharedPreferences(GenetAccessibilityService.PREFS_NAME, MODE_PRIVATE)

    /** Updates VPN block list; empty list stops the VPN service if it is running. */
    private fun applyVpnBlockedList(list: List<String>) {
        NetworkBlocker.setBlockedApps(list)
        if (list.isEmpty() && VpnState.isVpnRunning) {
            Log.i("GenetVpn", "No blocked apps, skipping VPN")
            startService(Intent(this, GenetVpnService::class.java).setAction(GenetVpnService.ACTION_STOP))
        }
    }

    private fun getVpnStatus(): Boolean {
        val state = evaluateVpnProtectionStatus()
        logVpnProtectionState(state)
        return state == "protected"
    }

    private fun getVpnProtectionStatus(): String {
        val state = evaluateVpnProtectionStatus()
        logVpnProtectionState(state)
        return state
    }

    private fun evaluateVpnProtectionStatus(): String {
        val serviceRunning = VpnState.isVpnRunning
        Log.d("GENET_VPN", if (serviceRunning) "VPN SERVICE RUNNING" else "VPN SERVICE NOT RUNNING")
        return try {
            val cm = getSystemService(CONNECTIVITY_SERVICE) as? ConnectivityManager
            val activeNetwork = cm?.activeNetwork
            val capabilities = activeNetwork?.let { cm.getNetworkCapabilities(it) }
            val transportVpnActive =
                capabilities?.hasTransport(NetworkCapabilities.TRANSPORT_VPN) == true
            val permissionGranted = VpnService.prepare(this) == null
            if (transportVpnActive || serviceRunning) {
                "protected"
            } else if (permissionGranted) {
                "vpn_inactive"
            } else {
                "vpn_removed"
            }
        } catch (_: Exception) {
            Log.d("GENET_VPN", "VPN CHECK FAILED")
            if (serviceRunning) {
                "protected"
            } else if (VpnService.prepare(this) == null) {
                "vpn_inactive"
            } else {
                "vpn_removed"
            }
        }
    }

    private fun logVpnProtectionState(state: String) {
        when (state) {
            "protected" -> Log.d("GENET_VPN", "VPN ACTIVE")
            "vpn_removed" -> Log.d("GENET_VPN", "VPN REMOVED OR NOT CONFIGURED")
            else -> Log.d("GENET_VPN", "VPN INACTIVE")
        }
    }

    private fun dispatchVpnServiceAction(action: String) {
        val intent = Intent(this, GenetVpnService::class.java).setAction(action)
        if (action != GenetVpnService.ACTION_STOP && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            ContextCompat.startForegroundService(this, intent)
        } else {
            startService(intent)
        }
    }

    private fun enableDeviceAdmin() {
        val componentName = ComponentName(this, GenetDeviceAdminReceiver::class.java)
        val intent = Intent(DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN).apply {
            putExtra(DevicePolicyManager.EXTRA_DEVICE_ADMIN, componentName)
        }
        startActivity(intent)
    }

    private fun isDeviceAdminEnabled(): Boolean {
        val dpm = getSystemService(android.content.Context.DEVICE_POLICY_SERVICE) as? DevicePolicyManager ?: return false
        val cn = ComponentName(this, GenetDeviceAdminReceiver::class.java)
        return dpm.isAdminActive(cn)
    }

    private fun openBatteryOptimizationSettings() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                data = Uri.parse("package:$packageName")
            }
            try { startActivity(intent) } catch (_: Exception) {}
        }
    }

    private fun isIgnoringBatteryOptimizations(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val pm = getSystemService(android.content.Context.POWER_SERVICE) as? android.os.PowerManager ?: return true
            return pm.isIgnoringBatteryOptimizations(packageName)
        }
        return true
    }

    private fun getInstalledApps(): List<Map<String, Any>> {
        val pm = packageManager
        val installedApps = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            pm.getInstalledApplications(android.content.pm.PackageManager.ApplicationInfoFlags.of(0))
        } else {
            @Suppress("DEPRECATION")
            pm.getInstalledApplications(0)
        }
        val seen = mutableSetOf<String>()
        return installedApps.mapNotNull { appInfo ->
            val pkg = appInfo.packageName
            if (!seen.add(pkg)) return@mapNotNull null
            if (pkg.isBlank()) return@mapNotNull null
            val packageInfo = try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    pm.getPackageInfo(pkg, android.content.pm.PackageManager.PackageInfoFlags.of(0))
                } else {
                    @Suppress("DEPRECATION")
                    pm.getPackageInfo(pkg, 0)
                }
            } catch (_: Exception) {
                null
            }
            val installerPackage = try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    pm.getInstallSourceInfo(pkg).installingPackageName ?: ""
                } else {
                    @Suppress("DEPRECATION")
                    pm.getInstallerPackageName(pkg) ?: ""
                }
            } catch (_: Exception) {
                ""
            }
            val isLaunchable = isUserLaunchableForInventory(pm, pkg)
            val category = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                when (appInfo.category) {
                    ApplicationInfo.CATEGORY_GAME -> "game"
                    ApplicationInfo.CATEGORY_SOCIAL -> "social"
                    ApplicationInfo.CATEGORY_AUDIO -> "audio"
                    ApplicationInfo.CATEGORY_VIDEO -> "video"
                    ApplicationInfo.CATEGORY_IMAGE -> "image"
                    ApplicationInfo.CATEGORY_MAPS -> "maps"
                    ApplicationInfo.CATEGORY_PRODUCTIVITY -> "productivity"
                    else -> ""
                }
            } else {
                ""
            }
            val name = pm.getApplicationLabel(appInfo).toString().ifBlank { pkg }
            val icon = drawableToBase64(pm.getApplicationIcon(appInfo))
            mapOf(
                "name" to name,
                "package" to pkg,
                "icon" to (icon ?: ""),
                "isSystemApp" to (
                    (appInfo.flags and ApplicationInfo.FLAG_SYSTEM) != 0 ||
                        (appInfo.flags and ApplicationInfo.FLAG_UPDATED_SYSTEM_APP) != 0
                ),
                "isLaunchable" to isLaunchable,
                "category" to category,
                "versionName" to (packageInfo?.versionName ?: ""),
                "versionCode" to (
                    if (packageInfo == null) 0L
                    else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) packageInfo.longVersionCode
                    else {
                        @Suppress("DEPRECATION")
                        packageInfo.versionCode.toLong()
                    }
                ),
                "installerPackage" to installerPackage,
                "installedTime" to (packageInfo?.firstInstallTime ?: 0L),
                "updatedTime" to (packageInfo?.lastUpdateTime ?: 0L),
                "lastSeenAt" to System.currentTimeMillis()
            ) as Map<String, Any>
        }.sortedWith(
            compareBy<Map<String, Any>>(
                { (it["name"] as? String).orEmpty().lowercase() },
                { (it["package"] as? String).orEmpty() }
            )
        )
    }

    private fun drawableToBase64(drawable: Drawable?): String? {
        if (drawable == null) return null
        val bitmap = Bitmap.createBitmap(drawable.intrinsicWidth.coerceAtLeast(1), drawable.intrinsicHeight.coerceAtLeast(1), Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        drawable.setBounds(0, 0, canvas.width, canvas.height)
        drawable.draw(canvas)
        val stream = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.PNG, 90, stream)
        return Base64.encodeToString(stream.toByteArray(), Base64.NO_WRAP)
    }
}
