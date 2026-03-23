package com.example.genet_final

import android.view.accessibility.AccessibilityEvent

/**
 * Parses foreground package from [AccessibilityEvent] (window state / content).
 */
object ForegroundAppDetector {

    fun foregroundPackageFromEvent(event: AccessibilityEvent?): String? {
        val raw = event?.packageName?.toString() ?: return null
        return raw.takeIf { it.isNotBlank() }
    }

    fun isWindowForegroundEvent(eventType: Int): Boolean {
        return eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED ||
            eventType == AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED
    }
}
