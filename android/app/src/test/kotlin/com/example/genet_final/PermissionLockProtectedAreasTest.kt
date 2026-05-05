package com.example.genet_final

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PermissionLockProtectedAreasTest {

    private val genetPkg = "com.example.genet_final"
    private val launcherPkg = "com.test.launcher"

    @Test
    fun settingsPackageProtectedWhenLockWouldApply() {
        assertTrue(
            PermissionLockProtectedAreas.isProtectedPermissionArea(
                "com.android.settings",
                null,
                null,
                genetPkg,
                launcherPkg,
            ),
        )
    }

    @Test
    fun googleSettingsProtected() {
        assertTrue(
            PermissionLockProtectedAreas.isProtectedPermissionArea(
                "com.google.android.settings",
                null,
                null,
                genetPkg,
                launcherPkg,
            ),
        )
    }

    @Test
    fun permissionControllerProtected() {
        assertTrue(
            PermissionLockProtectedAreas.isProtectedPermissionArea(
                "com.google.android.permissioncontroller",
                null,
                null,
                genetPkg,
                launcherPkg,
            ),
        )
    }

    @Test
    fun packageInstallerProtected() {
        assertTrue(
            PermissionLockProtectedAreas.isProtectedPermissionArea(
                "com.android.packageinstaller",
                null,
                null,
                genetPkg,
                launcherPkg,
            ),
        )
    }

    @Test
    fun genetPackageNeverProtected() {
        assertFalse(
            PermissionLockProtectedAreas.isProtectedPermissionArea(
                genetPkg,
                null,
                null,
                genetPkg,
                launcherPkg,
            ),
        )
    }

    @Test
    fun defaultLauncherNotProtected() {
        assertFalse(
            PermissionLockProtectedAreas.isProtectedPermissionArea(
                launcherPkg,
                null,
                null,
                genetPkg,
                launcherPkg,
            ),
        )
    }

    @Test
    fun systemUiNotProtected() {
        assertFalse(
            PermissionLockProtectedAreas.isProtectedPermissionArea(
                "com.android.systemui",
                null,
                null,
                genetPkg,
                launcherPkg,
            ),
        )
    }

    @Test
    fun permissionLockDisabledMeansNoBlockDecision() {
        assertFalse(
            PermissionLockProtectedAreas.shouldBlockForegroundForPermissionLock(
                permissionLockEnabled = false,
                packageName = "com.android.settings",
                className = null,
                eventText = null,
                genetPackageName = genetPkg,
                defaultLauncherPackage = launcherPkg,
            ),
        )
    }

    @Test
    fun permissionLockEnabledBlocksSettings() {
        assertTrue(
            PermissionLockProtectedAreas.shouldBlockForegroundForPermissionLock(
                permissionLockEnabled = true,
                packageName = "com.android.settings",
                className = null,
                eventText = null,
                genetPackageName = genetPkg,
                defaultLauncherPackage = launcherPkg,
            ),
        )
    }

    @Test
    fun playStoreUninstallClassProtected() {
        assertTrue(
            PermissionLockProtectedAreas.isProtectedPermissionArea(
                "com.android.vending",
                "com.google.android.finsky.uninstall.UninstallActivity",
                null,
                genetPkg,
                launcherPkg,
            ),
        )
    }

    @Test
    fun nonVendorPackageWithVpnSubstringNotProtected() {
        assertFalse(
            PermissionLockProtectedAreas.isProtectedPermissionArea(
                "com.example.game",
                "VpnLeaderboardActivity",
                null,
                genetPkg,
                launcherPkg,
            ),
        )
    }
}