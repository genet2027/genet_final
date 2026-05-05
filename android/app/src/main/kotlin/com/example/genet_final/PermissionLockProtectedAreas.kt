package com.example.genet_final

/**
 * Pure helpers for [KEY_PERMISSION_LOCK_ENABLED] enforcement in child mode.
 * Keeps detection testable without Android framework mocks.
 */
object PermissionLockProtectedAreas {

    private fun lowerContainsAny(haystack: String, needles: List<String>): Boolean {
        if (haystack.isEmpty()) return false
        return needles.any { haystack.contains(it) }
    }

    /**
     * Sensitive flows inside Play Store (uninstall / package UI).
     */
    private fun isPlayStoreSensitive(className: String?): Boolean {
        val c = className?.lowercase().orEmpty()
        return c.contains("uninstall") ||
            c.contains("installer") ||
            c.contains("packageinstaller")
    }

    /**
     * When permission lock is enabled in child mode, these foreground targets should be ejected.
     *
     * Never returns true for Genet, default launcher, or SystemUI.
     */
    @JvmStatic
    fun isProtectedPermissionArea(
        packageName: String?,
        className: String?,
        eventText: String?,
        genetPackageName: String,
        defaultLauncherPackage: String?,
    ): Boolean {
        val pkg = packageName?.trim().orEmpty()
        if (pkg.isEmpty()) return false

        if (pkg == genetPackageName) return false
        if (!defaultLauncherPackage.isNullOrBlank() && pkg == defaultLauncherPackage) return false
        if (pkg == "com.android.systemui") return false

        if (pkg in GenetAccessibilityService.SETTINGS_PACKAGES) return true
        if (pkg in GenetAccessibilityService.PERMISSION_CONTROLLER_PACKAGES) return true

        if (pkg == "com.android.vending" && isPlayStoreSensitive(className)) return true

        val cls = className?.lowercase().orEmpty()
        val vendorPrivileged =
            pkg.startsWith("com.android.") ||
                pkg.startsWith("com.google.android.")

        if (vendorPrivileged && GenetAccessibilityService.isPermissionSettingsScreen(className)) {
            return true
        }

        val combinedText = (cls + " " + eventText.orEmpty()).lowercase()
        val vpnOrAdminPatterns = listOf(
            "vpn",
            "vpnsettings",
            "tether",
            "deviceadmin",
            "devicepolicy",
        )
        if (vendorPrivileged && lowerContainsAny(combinedText, vpnOrAdminPatterns)) {
            return true
        }

        return false
    }

    /**
     * Convenience: gate with prefs flag (caller reads [GenetAccessibilityService.KEY_PERMISSION_LOCK_ENABLED]).
     */
    @JvmStatic
    fun shouldBlockForegroundForPermissionLock(
        permissionLockEnabled: Boolean,
        packageName: String?,
        className: String?,
        eventText: String?,
        genetPackageName: String,
        defaultLauncherPackage: String?,
    ): Boolean {
        if (!permissionLockEnabled) return false
        return isProtectedPermissionArea(
            packageName = packageName,
            className = className,
            eventText = eventText,
            genetPackageName = genetPackageName,
            defaultLauncherPackage = defaultLauncherPackage,
        )
    }
}
