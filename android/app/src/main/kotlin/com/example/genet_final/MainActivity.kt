package com.example.genet_final

import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.Drawable
import android.net.Uri
import android.os.Build
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
                    sendBroadcast(android.content.Intent(GenetAccessibilityService.ACTION_CONFIG_CHANGED))
                    result.success(null)
                }
                "setBlockedApps", "setBlockedPackages" -> {
                    val list = call.argument<List<String>>("packages") ?: emptyList()
                    val first3 = list.take(3).joinToString(",")
                    android.util.Log.d("GENET", "setBlockedPackages received size=${list.size} packages=$first3")
                    getGenetPrefs().edit().putString(GenetAccessibilityService.KEY_BLOCKED_APPS, JSONArray(list).toString()).apply()
                    GenetAccessibilityService.updateBlockedPackages(list)
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
                "isAccessibilityServiceEnabled" -> result.success(isAccessibilityServiceEnabled())
                "getInitialRoute" -> result.success(getInitialRoute())
                "getInstalledApps" -> {
                    try {
                        result.success(getInstalledApps())
                    } catch (e: Exception) {
                        Log.e("MainActivity", "getInstalledApps", e)
                        result.success(emptyList<Map<String, Any>>())
                    }
                }
                else -> result.notImplemented()
            }
        }
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

    private fun isAccessibilityServiceEnabled(): Boolean {
        val serviceName = "${packageName}/${GenetAccessibilityService::class.java.canonicalName}"
        val enabledList = Settings.Secure.getString(contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES) ?: return false
        val accessibilityOn = Settings.Secure.getInt(contentResolver, Settings.Secure.ACCESSIBILITY_ENABLED, 0) == 1
        if (!accessibilityOn) return false
        return enabledList.split(":").any { it.equals(serviceName, ignoreCase = true) }
    }

    private fun getGenetPrefs() = getSharedPreferences(GenetAccessibilityService.PREFS_NAME, MODE_PRIVATE)

    /** אפליקציות עם Launcher (ניתנות לפתיחה מה-home). מחזיר name, package, icon (Base64). */
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
