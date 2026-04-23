package com.example.genet_final

import android.content.Context
import android.content.SharedPreferences
import androidx.core.content.edit

/**
 * Native mirror prefs ([PREFS_NAME]) for optional native flows.
 * **Enforcement blocked list** (Flutter / child mode) lives in [GenetAccessibilityService.PREFS_NAME]
 * — use [getEnforcementBlockedPackages].
 */
object BlockedAppsRepository {
    private const val PREFS_NAME = "genet_native_config"
    private const val KEY_BLOCKED_PACKAGES = "blocked_packages"
    private const val KEY_APPROVED_PACKAGES = "approved_packages"
    const val KEY_PARENT_PIN = "parent_pin"
    private const val DEFAULT_PIN = "1234"

    private fun prefs(context: Context): SharedPreferences =
        context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun getBlockedPackages(context: Context): Set<String> {
        val set = prefs(context).getStringSet(KEY_BLOCKED_PACKAGES, null) ?: return emptySet()
        return HashSet(set)
    }

    fun setBlockedPackages(context: Context, packages: List<String>) {
        prefs(context).edit {
            putStringSet(KEY_BLOCKED_PACKAGES, packages.toSet())
            apply()
        }
    }

    /**
     * Blocked packages for enforcement (same JSON + rules as [GenetAccessibilityService] / Flutter `setBlockedApps`).
     */
    fun getEnforcementBlockedPackages(context: Context): Set<String> {
        val p = context.applicationContext.getSharedPreferences(
            GenetAccessibilityService.PREFS_NAME,
            Context.MODE_PRIVATE,
        )
        return GenetAccessibilityService.buildBlockedPackagesSet(context.applicationContext, p)
    }

    /** Parent-approved packages that are never locked (whitelist). */
    fun getApprovedPackages(context: Context): Set<String> {
        val set = prefs(context).getStringSet(KEY_APPROVED_PACKAGES, null) ?: return emptySet()
        return HashSet(set)
    }

    fun setApprovedPackages(context: Context, packages: List<String>) {
        prefs(context).edit {
            putStringSet(KEY_APPROVED_PACKAGES, packages.toSet())
            apply()
        }
    }

    fun getParentPin(context: Context): String =
        prefs(context).getString(KEY_PARENT_PIN, DEFAULT_PIN) ?: DEFAULT_PIN

    fun setParentPin(context: Context, pin: String) {
        prefs(context).edit {
            putString(KEY_PARENT_PIN, pin)
            apply()
        }
    }
}

/** Verifies unlock PIN against stored parent PIN. */
object PinChecker {
    fun verify(context: Context, pin: String): Boolean =
        pin.isNotEmpty() && pin == BlockedAppsRepository.getParentPin(context)
}
