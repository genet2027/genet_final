package com.example.genet_final

import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Bundle
import android.view.KeyEvent
import android.view.WindowManager
import android.widget.TextView

class LockActivity : Activity() {

    override fun onResume() {
        super.onResume()
        isLockScreenVisible = true
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }
    override fun onPause() {
        super.onPause()
        isLockScreenVisible = false
    }

    override fun onNewIntent(intent: Intent?) {
        super.onNewIntent(intent)
        intent?.let {
            setIntent(it)
            it.getStringExtra(GenetAccessibilityService.EXTRA_BLOCKED_PACKAGE)?.let { pkg -> blockedPackage = pkg }
        }
    }

    companion object {
        @JvmStatic
        var isLockScreenVisible = false
    }

    private var blockedPackage: String = ""
    private val configReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            when (intent?.action) {
                GenetAccessibilityService.ACTION_CONFIG_CHANGED -> {
                    if (blockedPackage == packageName) {
                        finish()
                        return
                    }
                    val prefs = getSharedPreferences(GenetAccessibilityService.PREFS_NAME, MODE_PRIVATE)
                    if (!GenetAccessibilityService.shouldStillShowLock(prefs, blockedPackage)) finish()
                }
                GenetAccessibilityService.ACTION_DISMISS_LOCK -> finish()
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        blockedPackage = intent.getStringExtra(GenetAccessibilityService.EXTRA_BLOCKED_PACKAGE) ?: ""
        if (blockedPackage == packageName) {
            finish()
            return
        }
        window.addFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN or
                WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD or
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON)

        setContentView(R.layout.activity_lock)

        findViewById<TextView>(R.id.lock_title).text = "לילה טוב"
        findViewById<TextView>(R.id.lock_subtitle).text = "Good night"

        val filter = IntentFilter().apply {
            addAction(GenetAccessibilityService.ACTION_CONFIG_CHANGED)
            addAction(GenetAccessibilityService.ACTION_DISMISS_LOCK)
        }
        registerReceiver(configReceiver, filter)
    }

    override fun onDestroy() {
        try { unregisterReceiver(configReceiver) } catch (_: Exception) {
            // No-op: unregister failure ignored when receiver was not registered.
        }
        super.onDestroy()
    }

    override fun onBackPressed() {
        // Prevent back from dismissing
    }

    override fun onKeyDown(keyCode: Int, event: android.view.KeyEvent?): Boolean {
        if (keyCode == KeyEvent.KEYCODE_BACK) return true
        return super.onKeyDown(keyCode, event)
    }
}
