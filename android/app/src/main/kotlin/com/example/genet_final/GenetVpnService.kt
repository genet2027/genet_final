package com.example.genet_final

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import com.example.genet_final.config.AppConfig

/**
 * Local VPN: only [NetworkBlocker.resolveEffectiveBlockedPackages] are routed via [Builder.addAllowedApplication];
 * packets are blackholed in [NetworkBlocker] (no forward).
 */
class GenetVpnService : VpnService() {

    private val lifecycleLock = Any()
    private var tunInterface: ParcelFileDescriptor? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                Log.i(TAG, "VPN STOP REQUESTED")
                Log.d("GENET_VPN", "VPN STOP REQUESTED")
                stopVpn()
                stopSelfResult(startId)
                return START_NOT_STICKY
            }
            ACTION_RESTART -> {
                Log.i(TAG, "VPN RESTART PATH")
                Log.d("GENET_VPN", "VPN RESTART PATH")
                restartVpn()
                return START_STICKY
            }
            ACTION_START -> {
                Log.i(TAG, "VPN START REQUESTED")
                Log.d("GENET_VPN", "VPN START REQUESTED")
                startVpn()
                return START_STICKY
            }
            null -> {
                if (!VpnState.isVpnRunning && tunInterface == null) {
                    stopSelfResult(startId)
                    return START_NOT_STICKY
                }
                return START_STICKY
            }
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        synchronized(lifecycleLock) {
            stopVpnInternal()
        }
        super.onDestroy()
    }

    fun startVpn() {
        synchronized(lifecycleLock) {
            if (skipIfVpnAlreadyRunning()) return
            val apps = NetworkBlocker.resolveEffectiveBlockedPackages(this)
            if (apps.isEmpty()) {
                logAndAbortVpnStartNoApps()
                return
            }
            if (!prepareVpnOrAbort()) return
            startForegroundIfNeeded()
            val builder = buildVpnBuilderForApps(apps)
            val pfd = establishVpnOrAbort(builder) ?: return
            tunInterface = pfd
            VpnState.isVpnRunning = true
            NetworkBlocker.startBlackhole(pfd)
            Log.i(TAG, "VPN START SUCCESS")
            Log.d("GENET_VPN", "VPN START SUCCESS")
        }
    }

    private fun skipIfVpnAlreadyRunning(): Boolean {
        if (VpnState.isVpnRunning && tunInterface != null) {
            Log.i(TAG, "VPN already running — skip duplicate start")
            return true
        }
        if (VpnState.isVpnRunning || tunInterface != null) {
            Log.w(TAG, "VPN stale state — cleaning before start")
            stopVpnInternal()
        }
        return false
    }

    private fun logAndAbortVpnStartNoApps() {
        Log.w(TAG, VPN_START_FAILED)
        stopVpnInternal()
        stopSelf()
    }

    private fun prepareVpnOrAbort(): Boolean {
        if (prepare(this) != null) {
            Log.w(TAG, VPN_START_FAILED)
            stopVpnInternal()
            stopSelf()
            return false
        }
        return true
    }

    private fun buildVpnBuilderForApps(apps: List<String>): Builder {
        val builder = Builder()
        builder.setSession(SESSION_NAME)
        builder.setMtu(MTU)
        builder.addAddress(VPN_ADDRESS, VPN_PREFIX)
        builder.addRoute("0.0.0.0", 0)
        try {
            builder.addDnsServer(AppConfig.DNS_SERVER)
        } catch (_: Exception) {
            // optional
        }
        for (pkg in apps) {
            try {
                builder.addAllowedApplication(pkg)
            } catch (e: Exception) {
                Log.w(TAG, "addAllowedApplication skip: $pkg", e)
            }
        }
        return builder
    }

    private fun establishVpnOrAbort(builder: Builder): ParcelFileDescriptor? {
        return try {
            builder.establish()
        } catch (e: Exception) {
            Log.e(TAG, VPN_START_FAILED, e)
            stopVpnInternal()
            stopSelf()
            null
        }
    }

    fun stopVpn() {
        synchronized(lifecycleLock) {
            stopVpnInternal()
            Log.i(TAG, "VPN STOP SUCCESS")
            Log.d("GENET_VPN", "VPN STOP SUCCESS")
            stopSelf()
        }
    }

    fun restartVpn() {
        synchronized(lifecycleLock) {
            stopVpnInternal()
            startVpn()
        }
    }

    private fun stopVpnInternal() {
        NetworkBlocker.stopBlackhole()
        try {
            tunInterface?.close()
        } catch (e: Exception) {
            Log.d(TAG, "tun close: ${e.message}")
        }
        tunInterface = null
        VpnState.isVpnRunning = false
        stopForegroundCompat()
        Log.i(TAG, "VPN STATE RESET")
    }

    private fun startForegroundIfNeeded() {
        ensureNotificationChannel()
        val notification = NotificationCompat.Builder(this, NOTIFICATION_CHANNEL_ID)
            .setContentTitle("Genet")
            .setContentText("VPN blocking (blackhole)")
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            ServiceCompat.startForeground(
                this,
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun stopForegroundCompat() {
        try {
            ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        } catch (_: Exception) {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
    }

    private fun ensureNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val ch = NotificationChannel(
            NOTIFICATION_CHANNEL_ID,
            "Genet VPN",
            NotificationManager.IMPORTANCE_LOW,
        ).apply { setShowBadge(false) }
        nm.createNotificationChannel(ch)
    }

    companion object {
        private const val VPN_START_FAILED = "VPN START FAILED"
        private const val TAG = "GenetVpn"
        const val ACTION_START = "com.example.genet_final.vpn.START"
        const val ACTION_STOP = "com.example.genet_final.vpn.STOP"
        const val ACTION_RESTART = "com.example.genet_final.vpn.RESTART"
        private const val SESSION_NAME = "GenetLocalVpn"
        // Intentional fixed TUN address for the local VPN interface; internal/captive use only, not user-facing network choice.
        private const val VPN_ADDRESS = "10.7.0.2"
        private const val VPN_PREFIX = 32
        private const val MTU = 1500
        private const val NOTIFICATION_CHANNEL_ID = "genet_vpn_channel"
        private const val NOTIFICATION_ID = 7102
    }
}

object VpnState {
    @Volatile
    var isVpnRunning: Boolean = false
        internal set
}
