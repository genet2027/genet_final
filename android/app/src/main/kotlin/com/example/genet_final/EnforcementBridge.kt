package com.example.genet_final

import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import java.util.HashMap

/**
 * Streams enforcement events to Flutter on [CHANNEL_NAME].
 * Payload: `{ "type": "app_blocked", "packageName": "<pkg>", "timestamp": <ms> }`.
 */
object EnforcementBridge {

    const val CHANNEL_NAME = "genet/enforcement"

    private const val TAG = "EnforcementBridge"
    private val mainHandler = Handler(Looper.getMainLooper())
    private var eventSink: EventChannel.EventSink? = null

    /** Throttle duplicate emits for the same package (anti-spam with accessibility noise). */
    private var lastEmitPkg: String? = null
    private var lastEmitAt = 0L
    private const val EMIT_MIN_INTERVAL_MS = 650L

    fun register(messenger: BinaryMessenger) {
        EventChannel(messenger, CHANNEL_NAME).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                    Log.d(TAG, "Flutter listening on $CHANNEL_NAME")
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                    Log.d(TAG, "Flutter cancelled $CHANNEL_NAME")
                }
            },
        )
    }

    /**
     * Notify Flutter that a blocked app was detected and ejection ran (or was attempted).
     */
    fun emitAppBlocked(packageName: String) {
        val now = System.currentTimeMillis()
        if (packageName == lastEmitPkg && now - lastEmitAt < EMIT_MIN_INTERVAL_MS) {
            Log.d(TAG, "emit skipped (throttled) pkg=$packageName")
            return
        }
        lastEmitPkg = packageName
        lastEmitAt = now
        val sink = eventSink
        if (sink == null) {
            Log.d(TAG, "emit skipped (no listener) pkg=$packageName")
            return
        }
        val payload = HashMap<String, Any>()
        payload["type"] = "app_blocked"
        payload["packageName"] = packageName
        payload["timestamp"] = now
        mainHandler.post {
            try {
                sink.success(payload)
                Log.d(TAG, "emit app_blocked pkg=$packageName")
            } catch (e: Exception) {
                Log.e(TAG, "emit failed", e)
            }
        }
    }
}
