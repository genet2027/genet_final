package com.example.genet_final

import android.content.Context
import android.content.pm.PackageManager
import android.os.ParcelFileDescriptor
import android.util.Log
import java.io.FileInputStream
import java.io.IOException

/**
 * Blackhole: reads packets from the VPN TUN and drops them (no forward, no socket).
 * Single worker thread via [startBlackhole] / [stopBlackhole].
 */
object NetworkBlocker {

    private const val TAG = "NetworkBlocker"
    private const val GENET_PACKAGE = "com.example.genet_final"

    @Volatile
    private var blockedApps: Set<String> = emptySet()

    @Volatile
    var isReaderRunning: Boolean = false
        private set

    private var workerThread: Thread? = null
    private val readerLock = Any()

    fun setBlockedApps(packages: List<String>) {
        blockedApps = packages.filter { it != GENET_PACKAGE }.toSet()
        Log.d(TAG, "setBlockedApps: full replace count=${blockedApps.size} empty=${blockedApps.isEmpty()} (Genet self excluded)")
    }

    fun getBlockedApps(): Set<String> = blockedApps

    /**
     * Installed packages only, never [GENET_PACKAGE]. Used when building the VPN session.
     */
    fun resolveEffectiveBlockedPackages(context: Context): List<String> {
        val pm = context.packageManager
        val out = ArrayList<String>()
        for (pkg in blockedApps) {
            if (pkg == GENET_PACKAGE) {
                Log.w(TAG, "skip: cannot route Genet through block VPN: $pkg")
                continue
            }
            try {
                pm.getPackageInfo(pkg, 0)
                out.add(pkg)
            } catch (_: PackageManager.NameNotFoundException) {
                Log.w(TAG, "skip: package not installed: $pkg")
            }
        }
        return out
    }

    /**
     * Starts the single blackhole reader on [pfd]. Call [stopBlackhole] before closing [pfd].
     */
    fun startBlackhole(pfd: ParcelFileDescriptor) {
        synchronized(readerLock) {
            stopBlackholeLocked()
            isReaderRunning = true
            workerThread = Thread({ runBlackholeLoop(pfd) }, "genet-blackhole").also { it.start() }
            Log.i(TAG, "blackhole reader started")
        }
    }

    fun stopBlackhole() {
        synchronized(readerLock) {
            stopBlackholeLocked()
        }
    }

    private fun stopBlackholeLocked() {
        if (!isReaderRunning && workerThread == null) return
        Log.i(TAG, "blackhole stopping")
        isReaderRunning = false
        workerThread?.interrupt()
        try {
            workerThread?.join(800L)
        } catch (_: InterruptedException) {
            Thread.currentThread().interrupt()
        }
        workerThread = null
        Log.i(TAG, "blackhole stopped")
    }

    private fun runBlackholeLoop(pfd: ParcelFileDescriptor) {
        val input = FileInputStream(pfd.fileDescriptor)
        val buffer = ByteArray(32767)
        var packetsDropped = 0L
        try {
            while (isReaderRunning && !Thread.currentThread().isInterrupted) {
                val n = try {
                    input.read(buffer)
                } catch (e: IOException) {
                    Log.d(TAG, "blackhole read closed: ${e.message}")
                    break
                }
                when {
                    n > 0 -> {
                        packetsDropped++
                        if (packetsDropped == 1L || packetsDropped % 500L == 0L) {
                            Log.d(TAG, "blackhole drop (count=$packetsDropped)")
                        }
                    }
                    n == 0 -> {
                        try {
                            Thread.sleep(20L)
                        } catch (_: InterruptedException) {
                            break
                        }
                    }
                    else -> break
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "blackhole loop error", e)
        }
        Log.d(TAG, "blackhole loop exit totalDropped=$packetsDropped")
    }
}
