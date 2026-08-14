# Changelog

All notable changes to `moonview` are documented in this file.

## 0.1.0-beta.8

- Report WebView2 browser-process failures through terminal
  `WebViewEvent::ProcessFailed` events and transition the view lifecycle to
  `Failed`.
- Stop accepting queued or new commands after a browser-process failure; hosts
  explicitly destroy and recreate the embedded view rather than relying on
  implicit recovery.

## 0.1.0-beta.7

- Add `WebView::show_file_dialog` with open, multi-open, save, and directory
  picker modes, user-visible filters, default names, and initial directories.
- Implement the API with Windows `IFileDialog` and owner-window modal behavior.
  The Linux and macOS backends report `Unsupported` until their native dialog
  integrations are implemented.
- Add an opt-in Windows smoke path for manually exercising the native picker.

## 0.1.0-beta.6

- Update the Android WebView bridge dependency to `Nanaloveyuki/ajni@0.2.2`.
- Align Moonview with Ajni's generic JNI and Android runtime package split;
  Moonview's public Android adapter API remains unchanged.

## 0.1.0-beta.5

- Download the official Microsoft WebView2 SDK `1.0.4078.44` on the first
  Windows native build when no explicit SDK is configured.
- Verify the NuGet package with a pinned SHA-256 digest and publish it through
  a locked, atomic user-level cache so parallel builds cannot consume a
  partial extraction.
- Preserve explicit SDK, include, and Loader-library overrides for offline and
  custom toolchain setups, with clearer download and extraction diagnostics.

## 0.1.0-beta.4

- Update the Android WebView bridge dependency to `Nanaloveyuki/ajni@0.2.1`.
- Validate the native WebView packages and generated interfaces with MoonBit
  0.10.6.

## 0.1.0-beta.3

- Adds the optional `moonview/android` adapter backed by ajni's AndroidX WebKit
  host.
- Provides a single HTTPS asset origin, document-start scripts, structured page
  messages, asset request/response events, operation-correlated failures, and
  per-view resource limits.
- Enforces caller-owned `FrameLayout` hosting, main-Looper WebView mutation,
  and idempotent destruction without a JavaScript interface.

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
