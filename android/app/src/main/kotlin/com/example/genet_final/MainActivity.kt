package com.example.genet_final

import android.app.Activity
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.Drawable
import android.net.Uri
import android.net.VpnService
import android.os.Build
import androidx.core.content.ContextCompat
import android.provider.Settings
import android.util.Base64
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayOutputStream

class MainActivity : FlutterActivity() {

    private val CHANNEL = "com.example.genet_final/config"
    private val VPN_CHANNEL = "genet/vpn"

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
                            startService(Intent(this, GenetVpnService::class.java).setAction(GenetVpnService.ACTION_STOP))
                        }
                        result.success(mapOf("started" to false, "needsPermission" to false))
                        return@setMethodCallHandler
                    }
                    if (VpnState.isVpnRunning) {
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
                        val intent = Intent(this, GenetVpnService::class.java).setAction(GenetVpnService.ACTION_START)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            ContextCompat.startForegroundService(this, intent)
                        } else {
                            startService(intent)
                        }
                        result.success(mapOf("started" to true, "needsPermission" to false))
                    }
                }
                "stopVpn" -> {
                    startService(Intent(this, GenetVpnService::class.java).setAction(GenetVpnService.ACTION_STOP))
                    result.success(null)
                }
                "refreshVpn" -> {
                    @Suppress("UNCHECKED_CAST")
                    val list = call.argument<List<String>>("packages")
                    if (list != null) {
                        applyVpnBlockedList(list)
                    }
                    if (VpnState.isVpnRunning) {
                        val intent = Intent(this, GenetVpnService::class.java).setAction(GenetVpnService.ACTION_RESTART)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            ContextCompat.startForegroundService(this, intent)
                        } else {
                            startService(intent)
                        }
                    }
                    result.success(null)
                }
                "isVpnRunning" -> result.success(VpnState.isVpnRunning)
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
                    if (isChildMode) AppMonitorService.start(this) else AppMonitorService.stop(this)
                    result.success(null)
                }
                "getIsDeviceAdminEnabled" -> result.success(isDeviceAdminEnabled())
                "openBatteryOptimizationSettings" -> {
                    openBatteryOptimizationSettings()
                    result.success(null)
                }
                "isIgnoringBatteryOptimizations" -> result.success(isIgnoringBatteryOptimizations())
                else -> result.notImplemented()
            }
        }
    }

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        if (intent?.getBooleanExtra(EXTRA_SHOW_PERMISSION_RECOVERY, false) == true) pendingPermissionRecovery = true
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
        val i = Intent(this, GenetVpnService::class.java).setAction(GenetVpnService.ACTION_START)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            ContextCompat.startForegroundService(this, i)
        } else {
            startService(i)
        }
    }

    override fun onResume() {
        super.onResume()
        if (getGenetPrefs().getBoolean(GenetAccessibilityService.KEY_REQUIRE_PARENT_UNLOCK_AFTER_REBOOT, false)) {
            startActivity(Intent(this, RebootLockActivity::class.java))
        }
        if (getGenetPrefs().getBoolean(GenetAccessibilityService.KEY_IS_CHILD_MODE, false)) {
            AppMonitorService.start(this)
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
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        val list = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            pm.queryIntentActivities(intent, android.content.pm.PackageManager.ResolveInfoFlags.of(0))
        } else {
            @Suppress("DEPRECATION")
            pm.queryIntentActivities(intent, 0)
        }
        val seen = mutableSetOf<String>()
        return list.mapNotNull { info ->
            val pkg = info.activityInfo.packageName
            if (!seen.add(pkg)) return@mapNotNull null
            val appInfo = info.activityInfo.applicationInfo
            val name = pm.getApplicationLabel(appInfo).toString()
            val icon = drawableToBase64(info.loadIcon(pm))
            mapOf(
                "name" to name,
                "package" to pkg,
                "icon" to (icon ?: "")
            ) as Map<String, Any>
        }
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
