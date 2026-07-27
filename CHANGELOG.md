# Changelog

All notable changes to `moonview` are documented in this file.

## 0.1.0-alpha.1

First public preview of direct native WebView embedding for MoonBit.

- Embeds WebView2, WKWebView, and WebKitGTK 4.1 into caller-owned native
  containers without creating host windows or running an application loop.
- Provides asynchronous lifecycle events, navigation decisions, JavaScript
  evaluation, UTF-8 page messaging, page zoom, and platform diagnostic tools.
- Supports process-level application URL schemes with asynchronous binary
  request/response handling and a 30-second cancellation deadline.
- Exposes camera and microphone permission decisions with a default-deny
  policy across all backends.

### Compatibility

This is an alpha release. Public APIs may change before `0.1.0`, particularly
when a window-management library supplies a concrete host integration contract.
