package com.example.genet_final

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.view.KeyEvent
import android.view.LayoutInflater
import android.widget.Button
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.Toast
import androidx.core.content.ContextCompat

/**
 * Full-screen overlay that blocks interaction with the underlying app.
 * Only dismissible when parent approval broadcast is received or PIN is correct.
 * Consumes Back key. Re-lock is handled by the service when foreground changes.
 */
class LockOverlayView(
    context: Context,
    private val blockedPackage: String,
    private val onDismissRequest: () -> Unit
) : FrameLayout(context) {

    private val parentApprovalReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == ACTION_PARENT_APPROVAL) {
                onDismissRequest()
            }
        }
    }

    init {
        LayoutInflater.from(context).inflate(R.layout.activity_lock, this, true)
        setBackgroundColor(ContextCompat.getColor(context, android.R.color.black))
        val pinInput = findViewById<EditText>(R.id.lock_pin_input)
        val submit = findViewById<Button>(R.id.lock_submit)
        submit?.setOnClickListener {
            val pin = pinInput?.text?.toString() ?: ""
            if (PinChecker.verify(context, pin)) {
                onDismissRequest()
            } else {
                Toast.makeText(context, context.getString(R.string.lock_wrong_pin), Toast.LENGTH_SHORT).show()
            }
        }
        val app = context.applicationContext
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            app.registerReceiver(parentApprovalReceiver, IntentFilter(ACTION_PARENT_APPROVAL), Context.RECEIVER_NOT_EXPORTED)
        } else {
            app.registerReceiver(parentApprovalReceiver, IntentFilter(ACTION_PARENT_APPROVAL))
        }
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (event.keyCode == KeyEvent.KEYCODE_BACK && event.action == KeyEvent.ACTION_DOWN) {
            return true
        }
        return super.dispatchKeyEvent(event)
    }

    fun unregisterReceiver() {
        try {
            context.applicationContext.unregisterReceiver(parentApprovalReceiver)
        } catch (_: Exception) {
            // No-op: unregister failure ignored when receiver was not registered.
        }
    }

    companion object {
        const val ACTION_PARENT_APPROVAL = "com.example.genet_final.PARENT_APPROVAL"
    }
}
