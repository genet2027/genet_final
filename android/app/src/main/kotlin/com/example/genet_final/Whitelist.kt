package com.example.genet_final

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Telephony
import android.telecom.TelecomManager

/**
 * Whitelist: packages that must never be covered by the lock overlay.
 * - Strictly allowed: Dialer/Phone (including default), SMS (default), System Launcher (default), Genet.
 * - Dynamic: default launcher/phone/SMS are resolved at runtime so the device stays functional.
 * - Parent-approved packages (from BlockedAppsRepository) are also whitelisted.
 *
 * Overlay triggers only if: package is in blockedApps AND not in whitelist.
 */
object Whitelist {

    private const val GENET_PACKAGE = "com.example.genet_final"

    /** Hardcoded packages always allowed (emergencies, system). */
    private val ALWAYS_ALLOWED = setOf(
        "com.android.server.telecom",
        "com.android.dialer",
        "com.android.phone",
        "com.android.contacts",
        "com.google.android.dialer",
        "com.samsung.android.dialer",
        "com.samsung.android.incallui",
        "com.android.settings",
        "com.google.android.settings.intelligence",
        "com.android.quickstep",
        GENET_PACKAGE
    )

    private val ALLOWED_PREFIXES = listOf(
        "com.android.launcher",
        "com.android.dialer",
        "com.android.phone",
        "com.android.settings",
        "com.android.contacts",
        "com.android.quickstep"
    )

    /**
     * Package name of the current default Home launcher (so user can always go Home).
     */
    fun getDefaultLauncherPackageName(context: Context): String? {
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
        val resolveInfo = context.packageManager.resolveActivity(intent, PackageManager.MATCH_DEFAULT_ONLY)
        return resolveInfo?.activityInfo?.packageName?.takeIf { it != "android" }
    }

    /**
     * Package name of the default Phone/Dialer app (API 23+). For emergencies.
     */
    fun getDefaultDialerPackageName(context: Context): String? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return null
        val telecom = context.getSystemService(Context.TELECOM_SERVICE) as? TelecomManager ?: return null
        return telecom.defaultDialerPackage
    }

    /**
     * Package name of the default SMS app (API 19+). For emergencies.
     */
    fun getDefaultSmsPackageName(context: Context): String? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT) {
            Telephony.Sms.getDefaultSmsPackage(context)
        } else null
    }

    /**
     * True if the package is a known essential system app (hardcoded + prefixes).
     */
    @JvmStatic
    fun isEssentialSystemApp(packageName: String?): Boolean {
        if (packageName.isNullOrEmpty()) return true
        if (ALWAYS_ALLOWED.contains(packageName)) return true
        return ALLOWED_PREFIXES.any { packageName.startsWith(it) }
    }

    /**
     * True if the package is in the parent-approved list (stored in BlockedAppsRepository).
     */
    @JvmStatic
    fun isUserApproved(context: Context, packageName: String?): Boolean {
        if (packageName.isNullOrEmpty()) return false
        return BlockedAppsRepository.getApprovedPackages(context).contains(packageName)
    }

    /**
     * True if the package is Genet (our app).
     */
    @JvmStatic
    fun isGenetApp(packageName: String?): Boolean = packageName == GENET_PACKAGE

    /**
     * True if the overlay must not be shown for this package (allow access).
     * Use this before showing the overlay: if (Whitelist.isWhitelisted(...)) { hideOverlay(); return }
     */
    @JvmStatic
    fun isWhitelisted(context: Context, packageName: String?): Boolean {
        if (packageName.isNullOrEmpty()) return true
        if (isGenetApp(packageName)) return true
        if (isEssentialSystemApp(packageName)) return true
        if (packageName == getDefaultLauncherPackageName(context)) return true
        if (packageName == getDefaultDialerPackageName(context)) return true
        if (packageName == getDefaultSmsPackageName(context)) return true
        if (isUserApproved(context, packageName)) return true
        return false
    }
}
