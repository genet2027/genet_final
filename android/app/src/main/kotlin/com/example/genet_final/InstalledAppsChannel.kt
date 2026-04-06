package com.example.genet_final

import android.content.Context
import android.content.pm.ApplicationInfo
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Step 1: [genet/installed_apps] — full scan [getInstalledApps], single row [getInstalledApp].
 * Step 3: platform → Flutter [onPackageChanged] (no scan in receiver).
 */
object InstalledAppsChannel {
    private const val TAG = "InstalledAppsChannel"
    const val CHANNEL_NAME = "genet/installed_apps"
    private const val METHOD_GET_INSTALLED_APPS = "getInstalledApps"
    private const val METHOD_GET_INSTALLED_APP = "getInstalledApp"
    private const val METHOD_ON_PACKAGE_CHANGED = "onPackageChanged"

    @Volatile
    private var dartChannel: MethodChannel? = null

    private val mainHandler = Handler(Looper.getMainLooper())

    fun register(messenger: BinaryMessenger, context: Context) {
        val appContext = context.applicationContext
        val ch = MethodChannel(messenger, CHANNEL_NAME)
        dartChannel = ch
        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                METHOD_GET_INSTALLED_APPS -> {
                    try {
                        result.success(collectInstalledApps(appContext))
                    } catch (e: Exception) {
                        Log.e(TAG, "getInstalledApps failed", e)
                        result.error("installed_apps_error", e.message, null)
                    }
                }
                METHOD_GET_INSTALLED_APP -> {
                    val pkg = call.argument<String>("packageName")?.trim().orEmpty()
                    if (pkg.isEmpty()) {
                        result.success(null)
                        return@setMethodCallHandler
                    }
                    try {
                        result.success(collectSingleInstalledApp(appContext, pkg))
                    } catch (e: Exception) {
                        Log.w(TAG, "getInstalledApp failed for $pkg", e)
                        result.success(null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    /** Lightweight: post to main thread, no PackageManager work here. */
    fun notifyPackageChanged(packageName: String, action: String) {
        val ch = dartChannel ?: return
        val payload = mapOf(
            "packageName" to packageName,
            "action" to action,
        )
        mainHandler.post {
            try {
                ch.invokeMethod(
                    METHOD_ON_PACKAGE_CHANGED,
                    payload,
                    object : MethodChannel.Result {
                        override fun success(result: Any?) {}
                        override fun error(
                            errorCode: String,
                            errorMessage: String?,
                            errorDetails: Any?,
                        ) {
                            Log.w(TAG, "onPackageChanged error: $errorCode $errorMessage")
                        }
                        override fun notImplemented() {
                            Log.w(TAG, "onPackageChanged notImplemented")
                        }
                    },
                )
            } catch (e: Exception) {
                Log.w(TAG, "invokeMethod onPackageChanged failed", e)
            }
        }
    }

    fun collectInstalledApps(context: Context): List<Map<String, Any>> {
        val pm = context.packageManager
        val installedApps = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            pm.getInstalledApplications(PackageManager.ApplicationInfoFlags.of(0))
        } else {
            @Suppress("DEPRECATION")
            pm.getInstalledApplications(0)
        }
        val seen = mutableSetOf<String>()
        val out = ArrayList<Map<String, Any>>(installedApps.size)
        for (appInfo in installedApps) {
            val pkg = appInfo.packageName ?: continue
            if (pkg.isBlank()) continue
            if (!seen.add(pkg)) continue
            val packageInfo = loadPackageInfo(pm, pkg)
            buildRow(pm, pkg, appInfo, packageInfo)?.let { out.add(it) }
        }
        out.sortWith(
            compareBy<Map<String, Any>>(
                { (it["appName"] as? String).orEmpty().lowercase() },
                { (it["packageName"] as? String).orEmpty() },
            ),
        )
        return out
    }

    fun collectSingleInstalledApp(context: Context, pkg: String): Map<String, Any>? {
        val pm = context.packageManager
        val appInfo = try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                pm.getApplicationInfo(pkg, PackageManager.ApplicationInfoFlags.of(0))
            } else {
                @Suppress("DEPRECATION")
                pm.getApplicationInfo(pkg, 0)
            }
        } catch (_: PackageManager.NameNotFoundException) {
            return null
        }
        val packageInfo = loadPackageInfo(pm, pkg)
        return buildRow(pm, pkg, appInfo, packageInfo)
    }

    private fun loadPackageInfo(pm: PackageManager, pkg: String): PackageInfo? {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                pm.getPackageInfo(pkg, PackageManager.PackageInfoFlags.of(0))
            } else {
                @Suppress("DEPRECATION")
                pm.getPackageInfo(pkg, 0)
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun buildRow(
        pm: PackageManager,
        pkg: String,
        appInfo: ApplicationInfo,
        packageInfo: PackageInfo?,
    ): Map<String, Any>? {
        if (pkg.isBlank()) return null
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

        val appName = try {
            pm.getApplicationLabel(appInfo).toString().ifBlank { pkg }
        } catch (_: Exception) {
            pkg
        }

        val isSystemApp =
            (appInfo.flags and ApplicationInfo.FLAG_SYSTEM) != 0 ||
                (appInfo.flags and ApplicationInfo.FLAG_UPDATED_SYSTEM_APP) != 0

        val category = categoryString(appInfo)

        val isLaunchable = try {
            pm.getLaunchIntentForPackage(pkg) != null
        } catch (_: Exception) {
            false
        }

        val versionCodeLong = if (packageInfo == null) {
            0L
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            packageInfo.longVersionCode
        } else {
            @Suppress("DEPRECATION")
            packageInfo.versionCode.toLong()
        }

        return mapOf(
            "packageName" to pkg,
            "appName" to appName,
            "isSystemApp" to isSystemApp,
            "category" to category,
            "isLaunchable" to isLaunchable,
            "versionName" to (packageInfo?.versionName ?: ""),
            "versionCode" to versionCodeLong,
            "installerPackage" to installerPackage,
            "installedTime" to (packageInfo?.firstInstallTime ?: 0L),
            "updatedTime" to (packageInfo?.lastUpdateTime ?: 0L),
            "lastSeenAt" to System.currentTimeMillis(),
        )
    }

    private fun categoryString(appInfo: ApplicationInfo): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return "unknown"
        }
        return when (appInfo.category) {
            ApplicationInfo.CATEGORY_GAME -> "game"
            ApplicationInfo.CATEGORY_SOCIAL -> "social"
            ApplicationInfo.CATEGORY_AUDIO -> "audio"
            ApplicationInfo.CATEGORY_VIDEO -> "video"
            ApplicationInfo.CATEGORY_IMAGE -> "image"
            ApplicationInfo.CATEGORY_MAPS -> "maps"
            ApplicationInfo.CATEGORY_PRODUCTIVITY -> "productivity"
            ApplicationInfo.CATEGORY_UNDEFINED -> "unknown"
            else -> "unknown"
        }
    }
}
