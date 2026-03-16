package com.example.genet_final

import android.app.Activity
import android.os.Bundle
import android.view.KeyEvent
import android.view.WindowManager
import android.widget.Button
import android.widget.EditText
import android.widget.Toast

/**
 * Full-screen parent unlock required after reboot when device was in child mode and protection was incomplete.
 * Cannot be bypassed; only correct parent PIN clears the flag and dismisses.
 * Does not affect Parent mode or Genet self-block logic.
 */
class RebootLockActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(
            WindowManager.LayoutParams.FLAG_FULLSCREEN or
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
        )
        setContentView(R.layout.activity_reboot_lock)

        val pinInput = findViewById<EditText>(R.id.reboot_lock_pin)
        val submit = findViewById<Button>(R.id.reboot_lock_submit)

        submit.setOnClickListener {
            val entered = pinInput.text?.toString() ?: ""
            val prefs = getSharedPreferences(GenetAccessibilityService.PREFS_NAME, MODE_PRIVATE)
            val storedPin = prefs.getString("parent_pin", "1234") ?: "1234"
            if (entered == storedPin) {
                prefs.edit().putBoolean(GenetAccessibilityService.KEY_REQUIRE_PARENT_UNLOCK_AFTER_REBOOT, false).apply()
                finish()
            } else {
                Toast.makeText(this, "קוד PIN שגוי", Toast.LENGTH_SHORT).show()
                pinInput.text?.clear()
            }
        }
    }

    override fun onBackPressed() {}
    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        if (keyCode == KeyEvent.KEYCODE_BACK) return true
        return super.onKeyDown(keyCode, event)
    }
}
