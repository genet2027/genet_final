package com.example.genet_final

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

/**
 * Handles boot and package-replaced events for post-reboot protection.
 * Only runs when device is in child mode; sets flag so MainActivity shows parent lock if protection is incomplete.
 * Does NOT start any Activity — the lock is shown when the user opens Genet (MainActivity checks the flag).
 */
class GenetBootReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action ?: return
        val allowed = action == Intent.ACTION_BOOT_COMPLETED ||
            action == Intent.ACTION_LOCKED_BOOT_COMPLETED ||
            (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && action == Intent.ACTION_MY_PACKAGE_REPLACED)
        if (!allowed) return

        val prefs = context.getSharedPreferences(GenetAccessibilityService.PREFS_NAME, Context.MODE_PRIVATE)
        val isChildMode = prefs.getBoolean(GenetAccessibilityService.KEY_IS_CHILD_MODE, false)
        if (!isChildMode) return

        val missing = PermissionChecker.getMissingPermissions(context.applicationContext)
        if (missing.isEmpty()) return

        prefs.edit().putBoolean(GenetAccessibilityService.KEY_REQUIRE_PARENT_UNLOCK_AFTER_REBOOT, true).apply()
        Log.d(TAG, "Boot/replace: child mode + missing permissions -> require parent unlock on next app open")
    }

    companion object {
        private const val TAG = "GenetBootReceiver"
    }
}
