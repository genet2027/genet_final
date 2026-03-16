package com.example.genet_final

import android.content.Context
import android.os.Build
import android.provider.Settings

/**
 * Single place to check the three critical permissions (Accessibility, Usage Stats, Overlay).
 * Used by MainActivity for Flutter and by GenetAccessibilityService for recovery flow.
 */
object PermissionChecker {

    /** Returns list of missing permission keys: "accessibility", "usage", "overlay". */
    @JvmStatic
    fun getMissingPermissions(context: Context): List<String> {
        val missing = mutableListOf<String>()
        if (!isAccessibilityServiceEnabledInternal(context)) missing.add("accessibility")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(context)) missing.add("overlay")
        if (!hasUsageAccess(context)) missing.add("usage")
        return missing
    }

    @JvmStatic
    fun isAccessibilityServiceEnabled(context: Context): Boolean {
        return isAccessibilityServiceEnabledInternal(context)
    }

    private fun isAccessibilityServiceEnabledInternal(context: Context): Boolean {
        val serviceName = "${context.packageName}/${GenetAccessibilityService::class.java.canonicalName}"
        val enabledList = Settings.Secure.getString(context.contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES) ?: return false
        val accessibilityOn = Settings.Secure.getInt(context.contentResolver, Settings.Secure.ACCESSIBILITY_ENABLED, 0) == 1
        if (!accessibilityOn) return false
        return enabledList.split(":").any { it.equals(serviceName, ignoreCase = true) }
    }

    private fun hasUsageAccess(context: Context): Boolean {
        return try {
            val um = context.getSystemService(Context.USAGE_STATS_SERVICE) as android.app.usage.UsageStatsManager
            um.queryUsageStats(android.app.usage.UsageStatsManager.INTERVAL_DAILY, System.currentTimeMillis() - 60000, System.currentTimeMillis())
            true
        } catch (e: SecurityException) {
            false
        }
    }
}
