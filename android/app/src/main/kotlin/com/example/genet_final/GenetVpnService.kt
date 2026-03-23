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

/**
 * Local VPN: only [NetworkBlocker.resolveEffectiveBlockedPackages] are routed via [Builder.addAllowedApplication];
 * packets are blackholed in [NetworkBlocker] (no forward).
 */
class GenetVpnService : VpnService() {

    private val lifecycleLock = Any()
    private var tunInterface: ParcelFileDescriptor? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> stopVpn()
            ACTION_RESTART -> restartVpn()
            ACTION_START, null -> startVpn()
        }
        return START_STICKY
    }

    override fun onDestroy() {
        stopVpn()
        super.onDestroy()
    }

    fun startVpn() {
        synchronized(lifecycleLock) {
            if (VpnState.isVpnRunning && tunInterface != null) {
                Log.i(TAG, "VPN already running — skip duplicate start")
                return
            }
            if (VpnState.isVpnRunning || tunInterface != null) {
                Log.w(TAG, "VPN stale state — cleaning before start")
                stopVpnInternal()
            }
            Log.i(TAG, "VPN starting")
            val apps = NetworkBlocker.resolveEffectiveBlockedPackages(this)
            if (apps.isEmpty()) {
                Log.i(TAG, "No blocked apps, skipping VPN")
                stopVpnInternal()
                return
            }
            if (prepare(this) != null) {
                Log.w(TAG, "failed to establish VPN: consent not granted (call startVpn from Activity after user approves)")
                VpnState.isVpnRunning = false
                return
            }
            startForegroundIfNeeded()
            val builder = Builder()
            builder.setSession(SESSION_NAME)
            builder.setMtu(MTU)
            builder.addAddress(VPN_ADDRESS, VPN_PREFIX)
            builder.addRoute("0.0.0.0", 0)
            try {
                builder.addDnsServer("8.8.8.8")
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
            val pfd = try {
                builder.establish()
            } catch (e: Exception) {
                Log.e(TAG, "failed to establish VPN", e)
                stopForegroundCompat()
                VpnState.isVpnRunning = false
                return
            }
            if (pfd == null) {
                Log.e(TAG, "failed to establish VPN: establish() returned null")
                stopForegroundCompat()
                VpnState.isVpnRunning = false
                return
            }
            tunInterface = pfd
            VpnState.isVpnRunning = true
            NetworkBlocker.startBlackhole(pfd)
            Log.i(TAG, "VPN started packages=${apps.size}")
        }
    }

    fun stopVpn() {
        synchronized(lifecycleLock) {
            Log.i(TAG, "VPN stopping")
            stopVpnInternal()
            Log.i(TAG, "VPN stopped")
        }
    }

    fun restartVpn() {
        synchronized(lifecycleLock) {
            Log.i(TAG, "VPN restart requested")
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
        private const val TAG = "GenetVpn"
        const val ACTION_START = "com.example.genet_final.vpn.START"
        const val ACTION_STOP = "com.example.genet_final.vpn.STOP"
        const val ACTION_RESTART = "com.example.genet_final.vpn.RESTART"
        private const val SESSION_NAME = "GenetLocalVpn"
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
