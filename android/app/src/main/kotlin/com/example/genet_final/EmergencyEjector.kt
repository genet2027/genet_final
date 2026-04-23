package com.example.genet_final

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.util.Log

/**
 * Sends user away from a blocked app: [GLOBAL_ACTION_HOME] first, optional [GLOBAL_ACTION_BACK],
 * then launcher intent as last resort. All logging uses [logTag].
 */
object EmergencyEjector {

    private const val TAG_SUFFIX = "EmergencyEjector"

    fun ejectToHome(
        service: AccessibilityService,
        logTag: String,
        blockedPkg: String,
    ) {
        val homeOk = service.performGlobalAction(AccessibilityService.GLOBAL_ACTION_HOME)
        Log.i(logTag, "ENFORCEMENT: HOME blockedPkg=$blockedPkg success=$homeOk ($TAG_SUFFIX)")
        if (homeOk) return
        val backOk = service.performGlobalAction(AccessibilityService.GLOBAL_ACTION_BACK)
        Log.i(logTag, "ENFORCEMENT: BACK fallback blockedPkg=$blockedPkg success=$backOk ($TAG_SUFFIX)")
        if (backOk) return
        try {
            val homeIntent = Intent(Intent.ACTION_MAIN)
                .addCategory(Intent.CATEGORY_HOME)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            service.applicationContext.startActivity(homeIntent)
            Log.i(logTag, "ENFORCEMENT: launcher intent blockedPkg=$blockedPkg ($TAG_SUFFIX)")
        } catch (e: Exception) {
            Log.e(logTag, "ENFORCEMENT: launcher intent failed ($TAG_SUFFIX)", e)
        }
    }
}
