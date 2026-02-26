package com.example.genet_final

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val CHANNEL = "com.example.genet_final/config"

    /**
     * Initial route sent to Flutter. Use "/content-library" to open Content Library (ספריית תכנים)
     * on app launch; use null or "" for default (Role Select).
     */
    override fun getInitialRoute(): String? = "/content-library"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
                    result.success(null)
                }
                "setBlockedApps" -> {
                    val list = call.argument<List<String>>("packages") ?: emptyList()
                    getGenetPrefs().edit().putString("blocked_apps", org.json.JSONArray(list).toString()).apply()
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
                "getInitialRoute" -> result.success(getInitialRoute())
                else -> result.notImplemented()
            }
        }
    }

    private fun getGenetPrefs() = getSharedPreferences(GenetAccessibilityService.PREFS_NAME, MODE_PRIVATE)
}
