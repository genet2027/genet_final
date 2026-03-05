package com.example.genet_final

import android.annotation.SuppressLint
import android.graphics.PixelFormat
import android.os.Build
import android.view.Gravity
import android.view.LayoutInflater
import android.view.View
import android.view.WindowManager
import android.widget.TextView

/**
 * מנהל Overlay קבוע (TYPE_APPLICATION_OVERLAY) — נוצר פעם אחת, רק visibility משתנה.
 * מסך "לילה טוב" / "Good night" מלא, צ consumes touches.
 */
@SuppressLint("ClickableViewAccessibility")
class BlockOverlayManager(private val context: android.content.Context) {

    private val windowManager = context.applicationContext.getSystemService(android.content.Context.WINDOW_SERVICE) as WindowManager
    private var overlayView: View? = null
    private var added = false

    private val layoutParams: WindowManager.LayoutParams by lazy {
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }
        WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            type,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = 0
            y = 0
        }
    }

    private fun ensureView(): View {
        var view = overlayView
        if (view == null) {
            view = LayoutInflater.from(context).inflate(R.layout.overlay_lock, null)
            view.findViewById<TextView>(R.id.overlay_title).text = "לילה טוב"
            view.findViewById<TextView>(R.id.overlay_subtitle).text = "Good night"
            view.setOnTouchListener { _, _ -> true }
            overlayView = view
        }
        return view
    }

    fun show() {
        val view = ensureView()
        if (!added) {
            try {
                view.visibility = View.VISIBLE
                windowManager.addView(view, layoutParams)
                added = true
            } catch (e: Exception) {
                android.util.Log.e(GenetAccessibilityService.TAG, "BlockOverlayManager addView", e)
            }
        } else {
            view.visibility = View.VISIBLE
        }
    }

    fun hide() {
        overlayView?.visibility = View.GONE
    }

    fun isVisible(): Boolean = overlayView?.visibility == View.VISIBLE
}
