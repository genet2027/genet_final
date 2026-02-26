package com.example.genet_final

/**
 * Package names that must never be locked so the device remains functional.
 * Overlay is never shown for these, regardless of the blocked-apps list.
 * Only apps explicitly in the blocked list are locked; launcher, phone, and
 * settings are always allowed.
 */
object SystemCriticalPackages {
    private val CRITICAL = setOf(
        // System / default launchers (AOSP, Pixel, One UI, Samsung, Xiaomi, etc.)
        "com.android.launcher",
        "com.android.launcher2",
        "com.android.launcher3",
        "com.google.android.apps.nexuslauncher",
        "com.google.android.apps.pixellauncher",
        "com.microsoft.launcher",
        "com.microsoft.launcher.office",
        "com.samsung.android.launcher",
        "com.sec.android.app.launcher",
        "com.miui.home",
        "com.mi.android.globallauncher",
        "com.opera.launcher",
        "com.oppo.launcher",
        "com.huawei.android.launcher",
        "com.bbk.launcher2",
        "com.android.quickstep", // gesture nav / recents
        // Phone / Dialer
        "com.android.dialer",
        "com.android.phone",
        "com.google.android.dialer",
        "com.samsung.android.dialer",
        "com.samsung.android.incallui",
        "com.android.server.telecom",
        "com.android.contacts",
        // Settings – device must remain configurable
        "com.android.settings",
        "com.google.android.settings.intelligence",
        "com.samsung.android.settings",
        "com.oneplus.settings",
        // Our app – never lock ourselves
        "com.example.genet_final"
    )

    /** Packages that are known to have multiple package-name variants (prefix match). */
    private val CRITICAL_PREFIXES = listOf(
        "com.android.launcher",
        "com.google.android.apps.nexuslauncher",
        "com.samsung.android.app.launcher",
        "com.miui.home",
        "com.android.dialer",
        "com.android.phone",
        "com.android.settings",
        "com.android.contacts",
        "com.android.quickstep"
    )

    /**
     * Returns true if this package is system-critical and must never be locked
     * (launcher, dialer, settings, or Genet itself).
     */
    @JvmStatic
    fun isSystemCritical(packageName: String?): Boolean {
        if (packageName.isNullOrEmpty()) return true
        if (CRITICAL.contains(packageName)) return true
        return CRITICAL_PREFIXES.any { packageName.startsWith(it) }
    }
}
