package com.inscopelabs.abx.starlight

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.graphics.Path
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo

class AutoService : AccessibilityService() {

    companion object {
        @Volatile
        var instance: AutoService? = null
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        // Start the minimal RPC server once the service is bound
        RpcServer.start(this)
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // No continuous event processing required for the vertical slice
    }

    override fun onInterrupt() {
        // Required override; no-op for minimal implementation
    }

    override fun onDestroy() {
        instance = null
        RpcServer.stop()
        super.onDestroy()
    }

    /**
     * Find the first node matching the simple selector "text=..." and perform a click.
     * Returns true if the gesture was successfully dispatched.
     */
    fun performTap(selector: String): Boolean {
        val root = rootInActiveWindow ?: return false
        val text = selector.removePrefix("text=").trim()
        if (text.isEmpty()) return false

        val nodes = root.findAccessibilityNodeInfosByText(text)
        if (nodes.isEmpty()) return false

        val node = nodes[0]
        val bounds = android.graphics.Rect()
        node.getBoundsInScreen(bounds)
        node.recycle()

        val path = Path().apply {
            moveTo(bounds.centerX().toFloat(), bounds.centerY().toFloat())
        }
        val stroke = GestureDescription.StrokeDescription(path, 0, 50)
        val gesture = GestureDescription.Builder().addStroke(stroke).build()
        return dispatchGesture(gesture, null, null)
    }

    /**
     * Simple existence check for a selector of the form "text=..."
     */
    fun readMatches(selector: String): Boolean {
        val root = rootInActiveWindow ?: return false
        val text = selector.removePrefix("text=").trim()
        if (text.isEmpty()) return false
        val nodes = root.findAccessibilityNodeInfosByText(text)
        val found = nodes.isNotEmpty()
        nodes.forEach { it.recycle() }
        return found
    }
}
