package com.example.genet_final

import android.app.AppOpsManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.os.Build
import android.os.Process
import android.provider.Settings

/**
 * Fallback / secondary check for foreground app when Accessibility events are delayed or throttled.
 * Uses UsageStatsManager to get the most recently used app (current foreground).
 */
object UsageStatsHelper {

    fun hasUsageAccess(context: Context): Boolean {
        val appOps = context.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            appOps.unsafeCheckOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                Process.myUid(),
                context.packageName
            )
        } else {
            @Suppress("DEPRECATION")
            appOps.checkOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                Process.myUid(),
                context.packageName
            )
        }
        return mode == AppOpsManager.MODE_ALLOWED
    }

    /**
     * Returns the package name of the app that is currently in the foreground (most recent
     * ACTIVITY_RESUMED or similar). Returns null if we can't determine it.
     */
    fun getForegroundPackage(context: Context): String? {
        if (!hasUsageAccess(context)) return null
        val usageStatsManager = context.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val now = System.currentTimeMillis()
        val window = 2000L // last 2 seconds
        val events = usageStatsManager.queryEvents(now - window, now)
        var lastResumed: UsageEvents.Event? = null
        var lastEvent: UsageEvents.Event? = null
        val event = UsageEvents.Event()
        while (events.hasNextEvent()) {
            events.getNextEvent(event)
            lastEvent = event
            when (event.eventType) {
                UsageEvents.Event.ACTIVITY_RESUMED -> lastResumed = event
            }
        }
        val pkg = lastResumed?.packageName ?: lastEvent?.packageName
        return pkg?.takeIf { it.isNotEmpty() }
    }
}
