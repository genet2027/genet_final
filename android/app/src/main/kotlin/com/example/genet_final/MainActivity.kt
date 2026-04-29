package com.example.genet_final

import android.app.Activity
import android.app.admin.DevicePolicyManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Intent
import android.content.IntentFilter
import android.net.Uri
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.VpnService
import android.os.Build
import android.os.SystemClock
import androidx.core.content.ContextCompat
import android.provider.Settings
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
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
        setupEnforcementBridge(flutterEngine)
        setupInstalledAppsChannel(flutterEngine)
        setupInstalledAppsEvents(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, VPN_CHANNEL).setMethodCallHandler { call, result ->
            handleVpnMethodCall(call, result)
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            handleConfigMethodCall(call, result)
        }
    }

    private fun setupEnforcementBridge(flutterEngine: FlutterEngine) {
        EnforcementBridge.register(flutterEngine.dartExecutor.binaryMessenger)
    }

    private fun setupInstalledAppsChannel(flutterEngine: FlutterEngine) {
        InstalledAppsChannel.register(flutterEngine.dartExecutor.binaryMessenger, this)
    }

    private fun setupInstalledAppsEvents(flutterEngine: FlutterEngine) {
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            INSTALLED_APPS_EVENTS_CHANNEL
        ).setStreamHandler(createInstalledAppsStreamHandler())
    }

    private fun createInstalledAppsStreamHandler(): EventChannel.StreamHandler {
        return object : EventChannel.StreamHandler {

            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                registerInstalledAppsChangeReceiver(events)
            }

            override fun onCancel(arguments: Any?) {
                unregisterInstalledAppsChangeReceiver()
            }
        }
    }

    private fun handleVpnMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "setBlockedApps" -> handleVpnSetBlockedApps(call, result)
            "startVpn" -> handleVpnStart(result)
            "stopVpn" -> handleVpnStop(result)
            "refreshVpn" -> handleVpnRefresh(call, result)
            "isVpnRunning" -> handleVpnIsRunning(result)
            "getVpnStatus" -> handleVpnGetStatus(result)
            "getVpnProtectionStatus" -> handleVpnGetProtectionStatus(result)
            "isVpnPermissionGranted" -> handleVpnIsPermissionGranted(result)
            else -> result.notImplemented()
        }
    }

    private fun handleVpnSetBlockedApps(call: MethodCall, result: MethodChannel.Result) {
        @Suppress("UNCHECKED_CAST")
        val list = call.argument<List<String>>("packages") ?: emptyList()
        Log.d("GenetVpn", "VPN_CHANNEL setBlockedApps: full replace count=${list.size} empty=${list.isEmpty()}")
        applyVpnBlockedList(list)
        result.success(null)
    }

    private fun handleVpnStart(result: MethodChannel.Result) {
        if (NetworkBlocker.resolveEffectiveBlockedPackages(this@MainActivity).isEmpty()) {
            Log.i("GenetVpn", "No blocked apps, skipping VPN")
            if (VpnState.isVpnRunning) {
                dispatchVpnServiceAction(GenetVpnService.ACTION_STOP)
            }
            result.success(mapOf("started" to false, "needsPermission" to false))
            return
        }
        if (getVpnStatus()) {
            result.success(mapOf("started" to false, "needsPermission" to false))
            return
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

    private fun handleVpnStop(result: MethodChannel.Result) {
        dispatchVpnServiceAction(GenetVpnService.ACTION_STOP)
        result.success(null)
    }

    private fun handleVpnRefresh(call: MethodCall, result: MethodChannel.Result) {
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

    private fun handleVpnIsRunning(result: MethodChannel.Result) {
        result.success(VpnState.isVpnRunning)
    }

    private fun handleVpnGetStatus(result: MethodChannel.Result) {
        result.success(getVpnStatus())
    }

    private fun handleVpnGetProtectionStatus(result: MethodChannel.Result) {
        result.success(getVpnProtectionStatus())
    }

    private fun handleVpnIsPermissionGranted(result: MethodChannel.Result) {
        result.success(VpnService.prepare(this@MainActivity) == null)
    }

    private fun handleConfigMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "setPin" -> handleConfigSetPin(call, result)
            "setSleepLock" -> handleConfigSetSleepLock(call, result)
            "setBlockedApps", "setBlockedPackages" -> handleConfigSetBlockedPackages(call, result)
            "setNightModeActive" -> handleConfigSetNightModeActive(call, result)
            "setBlockWebSearch" -> handleConfigSetBlockWebSearch(call, result)
            "setPermissionLockEnabled" -> handleConfigSetPermissionLockEnabled(call, result)
            "setVpnProtectionLost" -> handleConfigSetVpnProtectionLost(call, result)
            "getPermissionLockEnabled" -> handleConfigGetPermissionLockEnabled(result)
            "setMaintenanceWindowEnd" -> handleConfigSetMaintenanceWindowEnd(call, result)
            "setExtensionApproved" -> handleConfigSetExtensionApproved(call, result)
            "reportEvent" -> handleConfigReportEvent(call, result)
            "openAccessibilitySettings" -> handleConfigOpenAccessibilitySettings(result)
            "openUsageAccessSettings" -> handleConfigOpenUsageAccessSettings(result)
            "openOverlaySettings" -> handleConfigOpenOverlaySettings(result)
            "isAccessibilityServiceEnabled" -> handleConfigIsAccessibilityServiceEnabled(result)
            "getMissingPermissions" -> handleConfigGetMissingPermissions(result)
            "getInitialRoute" -> handleConfigGetInitialRoute(result)
            "getPackageName" -> handleConfigGetPackageName(result)
            "shouldShowPermissionRecovery" -> handleConfigShouldShowPermissionRecovery(result)
            "enableDeviceAdmin" -> handleConfigEnableDeviceAdmin(result)
            "setChildMode" -> handleConfigSetChildMode(call, result)
            "getIsDeviceAdminEnabled" -> handleConfigGetIsDeviceAdminEnabled(result)
            "openBatteryOptimizationSettings" -> handleConfigOpenBatteryOptimizationSettings(result)
            "isIgnoringBatteryOptimizations" -> handleConfigIsIgnoringBatteryOptimizations(result)
            "getElapsedRealtimeMs" -> handleConfigGetElapsedRealtimeMs(result)
            else -> handleConfigMethodNotImplemented(result)
        }
    }

    private fun handleConfigMethodNotImplemented(result: MethodChannel.Result) {
        result.notImplemented()
    }

    private fun handleConfigSetPin(call: MethodCall, result: MethodChannel.Result) {
        val pin = call.argument<String>("pin") ?: "1234"
        getGenetPrefs().edit().putString("parent_pin", pin).apply()
        result.success(null)
    }

    private fun handleConfigSetSleepLock(call: MethodCall, result: MethodChannel.Result) {
        getGenetPrefs().edit()
            .putBoolean("sleep_lock_enabled", call.argument<Boolean>("enabled") ?: false)
            .putString("sleep_lock_start", call.argument<String>("start") ?: "22:00")
            .putString("sleep_lock_end", call.argument<String>("end") ?: "07:00")
            .apply()
        sendBroadcast(android.content.Intent(GenetAccessibilityService.ACTION_CONFIG_CHANGED))
        result.success(null)
    }

    private fun handleConfigSetBlockedPackages(call: MethodCall, result: MethodChannel.Result) {
        val list = call.argument<List<String>>("packages") ?: emptyList()
        val filtered = list.filter { it != packageName }
        android.util.Log.d(
            "GENET",
            "CONFIG_CHANNEL setBlockedPackages: full prefs replace size=${filtered.size} empty=${filtered.isEmpty()}",
        )
        getGenetPrefs().edit().putString(GenetAccessibilityService.KEY_BLOCKED_APPS, JSONArray(filtered).toString()).apply()
        GenetAccessibilityService.updateBlockedPackages(filtered)
        sendBroadcast(android.content.Intent(GenetAccessibilityService.ACTION_CONFIG_CHANGED))
        result.success(null)
    }

    private fun handleConfigSetNightModeActive(call: MethodCall, result: MethodChannel.Result) {
        val active = call.argument<Boolean>("active") ?: false
        getGenetPrefs().edit().putBoolean(GenetAccessibilityService.KEY_NIGHT_MODE_ACTIVE, active).apply()
        sendBroadcast(android.content.Intent(GenetAccessibilityService.ACTION_CONFIG_CHANGED))
        result.success(null)
    }

    private fun handleConfigSetBlockWebSearch(call: MethodCall, result: MethodChannel.Result) {
        val enabled = call.argument<Boolean>("enabled") ?: true
        getGenetPrefs().edit().putBoolean(GenetAccessibilityService.KEY_BLOCK_WEB_SEARCH, enabled).apply()
        sendBroadcast(android.content.Intent(GenetAccessibilityService.ACTION_CONFIG_CHANGED))
        result.success(null)
    }

    private fun handleConfigSetPermissionLockEnabled(call: MethodCall, result: MethodChannel.Result) {
        val enabled = call.argument<Boolean>("enabled") ?: false
        getGenetPrefs().edit().putBoolean(GenetAccessibilityService.KEY_PERMISSION_LOCK_ENABLED, enabled).apply()
        result.success(null)
    }

    private fun handleConfigSetVpnProtectionLost(call: MethodCall, result: MethodChannel.Result) {
        val lost = call.argument<Boolean>("lost") ?: false
        getGenetPrefs().edit()
            .putBoolean(GenetAccessibilityService.KEY_VPN_PROTECTION_LOST, lost)
            .apply()
        sendBroadcast(android.content.Intent(GenetAccessibilityService.ACTION_CONFIG_CHANGED))
        result.success(null)
    }

    private fun handleConfigGetPermissionLockEnabled(result: MethodChannel.Result) {
        result.success(getGenetPrefs().getBoolean(GenetAccessibilityService.KEY_PERMISSION_LOCK_ENABLED, false))
    }

    private fun handleConfigSetMaintenanceWindowEnd(call: MethodCall, result: MethodChannel.Result) {
        val endMs = (call.argument<Number>("endMs")?.toLong()) ?: 0L
        getGenetPrefs().edit().putLong(GenetAccessibilityService.KEY_MAINTENANCE_WINDOW_END, endMs).apply()
        result.success(null)
    }

    private fun handleConfigSetExtensionApproved(call: MethodCall, result: MethodChannel.Result) {
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

    private fun handleConfigReportEvent(call: MethodCall, result: MethodChannel.Result) {
        val pkg = call.argument<String>("packageName") ?: ""
        val ts = call.argument<Number>("timestamp")?.toLong() ?: System.currentTimeMillis()
        val type = call.argument<String>("type") ?: "event"
        appendReportEvent(pkg, ts, type)
        result.success(null)
    }

    private fun handleConfigOpenAccessibilitySettings(result: MethodChannel.Result) {
        startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
        result.success(null)
    }

    private fun handleConfigOpenUsageAccessSettings(result: MethodChannel.Result) {
        startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS))
        result.success(null)
    }

    private fun handleConfigOpenOverlaySettings(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val intent = Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:$packageName"))
            startActivity(intent)
        }
        result.success(null)
    }

    private fun handleConfigIsAccessibilityServiceEnabled(result: MethodChannel.Result) {
        result.success(PermissionChecker.isAccessibilityServiceEnabled(this))
    }

    private fun handleConfigGetMissingPermissions(result: MethodChannel.Result) {
        result.success(PermissionChecker.getMissingPermissions(this))
    }

    private fun handleConfigGetInitialRoute(result: MethodChannel.Result) {
        result.success(getInitialRoute())
    }

    private fun handleConfigGetPackageName(result: MethodChannel.Result) {
        result.success(packageName)
    }

    private fun handleConfigShouldShowPermissionRecovery(result: MethodChannel.Result) {
        val show = pendingPermissionRecovery
        pendingPermissionRecovery = false
        result.success(show)
    }

    private fun handleConfigEnableDeviceAdmin(result: MethodChannel.Result) {
        enableDeviceAdmin()
        result.success(null)
    }

    private fun handleConfigSetChildMode(call: MethodCall, result: MethodChannel.Result) {
        val isChildMode = call.argument<Boolean>("isChildMode") ?: false
        getGenetPrefs().edit().putBoolean(GenetAccessibilityService.KEY_IS_CHILD_MODE, isChildMode).apply()
        if (!isChildMode) AppMonitorService.stop(this)
        result.success(null)
    }

    private fun handleConfigGetIsDeviceAdminEnabled(result: MethodChannel.Result) {
        result.success(isDeviceAdminEnabled())
    }

    private fun handleConfigOpenBatteryOptimizationSettings(result: MethodChannel.Result) {
        openBatteryOptimizationSettings()
        result.success(null)
    }

    private fun handleConfigIsIgnoringBatteryOptimizations(result: MethodChannel.Result) {
        result.success(isIgnoringBatteryOptimizations())
    }

    private fun handleConfigGetElapsedRealtimeMs(result: MethodChannel.Result) {
        result.success(SystemClock.elapsedRealtime())
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
                when (action) {
                    Intent.ACTION_PACKAGE_ADDED -> {
                        InstalledAppsChannel.notifyPackageChanged(pkg, "added")
                    }
                    Intent.ACTION_PACKAGE_REMOVED -> {
                        InstalledAppsChannel.notifyPackageChanged(pkg, "removed")
                    }
                    Intent.ACTION_PACKAGE_CHANGED -> {
                        events?.success(
                            mapOf(
                                "action" to action,
                                "package" to pkg,
                            ),
                        )
                    }
                }
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
            // No-op: receiver already unregistered or invalid to unregister.
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
        } catch (_: Exception) {
            // No-op: report persistence failures are ignored.
        }
    }

    private fun getGenetPrefs() = getSharedPreferences(GenetAccessibilityService.PREFS_NAME, MODE_PRIVATE)

    /** Updates VPN block list; empty list overwrites in-memory set and stops VPN if running. */
    private fun applyVpnBlockedList(list: List<String>) {
        Log.d("GenetVpn", "applyVpnBlockedList: replacing NetworkBlocker set count=${list.size} empty=${list.isEmpty()}")
        NetworkBlocker.setBlockedApps(list)
        if (list.isEmpty() && VpnState.isVpnRunning) {
            Log.i("GenetVpn", "applyVpnBlockedList: empty list -> stopping VPN service")
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
            try { startActivity(intent) } catch (_: Exception) {
                // No-op: activity may be unavailable; optimization dialog optional.
            }
        }
    }

    private fun isIgnoringBatteryOptimizations(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val pm = getSystemService(android.content.Context.POWER_SERVICE) as? android.os.PowerManager ?: return true
            return pm.isIgnoringBatteryOptimizations(packageName)
        }
        return true
    }

}
