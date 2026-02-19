package com.example.genet_final

import android.app.Activity
import android.os.Bundle
import android.view.KeyEvent
import android.view.WindowManager
import android.widget.Button
import android.widget.EditText
import android.widget.TextView
import android.widget.Toast

class LockActivity : Activity() {

    private lateinit var pinInput: EditText
    private lateinit var submitButton: Button

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN or
                WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD or
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON)

        setContentView(R.layout.activity_lock)

        val titleText = findViewById<TextView>(R.id.lock_title)
        titleText.text = "Time to Sleep!"

        pinInput = findViewById(R.id.lock_pin_input)
        submitButton = findViewById(R.id.lock_submit)

        submitButton.setOnClickListener { checkPin() }
        pinInput.setOnEditorActionListener { _, actionId, _ ->
            if (actionId == android.view.inputmethod.EditorInfo.IME_ACTION_DONE) {
                checkPin()
                true
            } else false
        }
    }

    override fun onBackPressed() {
        // Prevent back from dismissing
    }

    override fun onKeyDown(keyCode: Int, event: android.view.KeyEvent?): Boolean {
        if (keyCode == KeyEvent.KEYCODE_BACK) return true
        return super.onKeyDown(keyCode, event)
    }

    private fun checkPin() {
        val entered = pinInput.text.toString()
        val prefs = getSharedPreferences(GenetAccessibilityService.PREFS_NAME, MODE_PRIVATE)
        val storedPin = prefs.getString("parent_pin", "1234") ?: "1234"

        if (entered == storedPin) {
            pinInput.text.clear()
            finish()
        } else {
            Toast.makeText(this, "Wrong PIN", Toast.LENGTH_SHORT).show()
            pinInput.text.clear()
        }
    }
}
