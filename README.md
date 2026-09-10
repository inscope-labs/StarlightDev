# Starlight

Minimal Android AccessibilityService + WebSocket RPC endpoint for the vertical-slice validation.

## Build & install
1. Open in Android Studio or build with Gradle.
2. Install on device.
3. Enable the Accessibility Service in system settings.
4. RpcServer listens on TCP 8765 (ensure Tailscale / network reachability from the OCI VM).

## Supported methods only
- `session.open`
- `ui.perform` (action = "tap", selector = "text=...")
- `ui.read` (selector = "text=...")
- `session.close`
