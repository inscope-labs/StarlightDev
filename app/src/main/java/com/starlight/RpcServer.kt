package com.inscopelabs.abx.starlight

import android.util.Log
import org.java_websocket.WebSocket
import org.java_websocket.handshake.ClientHandshake
import org.java_websocket.server.WebSocketServer
import org.json.JSONObject
import java.net.InetSocketAddress

object RpcServer {
    private const val TAG = "StarlightRpc"
    private const val PORT = 8765
    private var server: WebSocketServer? = null
    private var sessionOpen = false

    fun start(service: AutoService) {
        if (server != null) return

        server = object : WebSocketServer(InetSocketAddress(PORT)) {
            override fun onOpen(conn: WebSocket, handshake: ClientHandshake) {
                Log.i(TAG, "Client connected: ${conn.remoteSocketAddress}")
            }

            override fun onClose(conn: WebSocket, code: Int, reason: String, remote: Boolean) {
                Log.i(TAG, "Client disconnected")
                sessionOpen = false
            }

            override fun onMessage(conn: WebSocket, message: String) {
                try {
                    val req = JSONObject(message)
                    val method = req.optString("method")
                    val response = when (method) {
                        "session.open" -> {
                            sessionOpen = true
                            JSONObject().put("ok", true)
                        }
                        "session.close" -> {
                            sessionOpen = false
                            JSONObject().put("ok", true)
                        }
                        "ui.perform" -> {
                            if (!sessionOpen) {
                                JSONObject().put("ok", false).put("reason", "session_not_open")
                            } else {
                                val params = req.optJSONObject("params") ?: JSONObject()
                                val action = params.optString("action")
                                val selector = params.optString("selector")
                                if (action == "tap") {
                                    val success = service.performTap(selector)
                                    if (success) JSONObject().put("ok", true)
                                    else JSONObject().put("ok", false).put("reason", "selector_not_found")
                                } else {
                                    JSONObject().put("ok", false).put("reason", "unsupported_action")
                                }
                            }
                        }
                        "ui.read" -> {
                            if (!sessionOpen) {
                                JSONObject().put("ok", false).put("reason", "session_not_open")
                            } else {
                                val params = req.optJSONObject("params") ?: JSONObject()
                                val selector = params.optString("selector")
                                val matches = service.readMatches(selector)
                                JSONObject().put("ok", true).put("matches", matches)
                            }
                        }
                        else -> JSONObject().put("ok", false).put("reason", "unknown_method")
                    }
                    conn.send(response.toString())
                } catch (e: Exception) {
                    Log.e(TAG, "Error handling message", e)
                    conn.send(JSONObject().put("ok", false).put("reason", e.message ?: "error").toString())
                }
            }

            override fun onError(conn: WebSocket?, ex: Exception) {
                Log.e(TAG, "WebSocket error", ex)
            }

            override fun onStart() {
                Log.i(TAG, "RpcServer listening on :$PORT")
            }
        }.also {
            it.isReuseAddr = true
            it.start()
        }
    }

    fun stop() {
        try {
            server?.stop()
        } catch (_: Exception) {}
        server = null
        sessionOpen = false
    }
}
