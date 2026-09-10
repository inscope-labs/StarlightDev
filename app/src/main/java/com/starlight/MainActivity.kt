package com.inscopelabs.abx.starlight

import android.content.Intent
import android.os.Bundle
import android.provider.Settings
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity

class MainActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        val status = findViewById<TextView>(R.id.statusText)
        status.text = "Starlight. Enable Accessibility Service, then RpcServer listens on :8765"

        // Open accessibility settings for convenience
        startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
    }
}
