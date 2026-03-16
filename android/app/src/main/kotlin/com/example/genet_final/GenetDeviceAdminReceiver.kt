package com.example.genet_final

import android.app.admin.DeviceAdminReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import android.widget.Toast

/**
 * Device Admin receiver for Genet. Enables future protection of app removal and sensitive permissions.
 * Minimal implementation: logging and Toast only.
 */
class GenetDeviceAdminReceiver : DeviceAdminReceiver() {

    override fun onEnabled(context: Context, intent: Intent) {
        super.onEnabled(context, intent)
        Log.d(TAG, "Device Admin enabled")
        Toast.makeText(context, "Device Admin הופעל", Toast.LENGTH_SHORT).show()
    }

    override fun onDisabled(context: Context, intent: Intent) {
        super.onDisabled(context, intent)
        Log.d(TAG, "Device Admin disabled")
        Toast.makeText(context, "Device Admin בוטל", Toast.LENGTH_SHORT).show()
    }

    companion object {
        private const val TAG = "GenetDeviceAdmin"
    }
}
