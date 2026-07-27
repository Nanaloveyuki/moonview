# moonview

`moonview` is an Apache-2.0 MoonBit library for directly embedding native
WebViews. It embeds into a caller-owned native container and does not create
windows or run an event loop for the application.

## Status

Native backends use the platform APIs directly:

- Windows: WebView2 COM API in a caller-owned `HWND`.
- macOS: WKWebView in a caller-owned `NSView*` on the main thread.
- Linux: WebKitGTK 4.1 in a caller-owned `GtkFixed*`.

All backends share lifecycle, navigation, script, and UTF-8 message semantics.

## Build Prerequisites

- MoonBit native toolchain and a C++ compiler for the host OS.
- Windows: Visual Studio Build Tools, Edge WebView2 Runtime, and the WebView2
  SDK. Set `MOONVIEW_WEBVIEW2_SDK_DIR`, or set both
  `MOONVIEW_WEBVIEW2_INCLUDE` and `MOONVIEW_WEBVIEW2_LOADER_LIB`; a local
  `.tools/webview2/` cache with NuGet's standard layout is also supported.
  Set `MOONVIEW_WEBVIEW2_ARCH` for a non-x64 Loader path.
- macOS: Xcode Command Line Tools. WKWebView is supplied by the operating
  system; no SDK download is needed.
- Linux: GTK 3 and the `webkit2gtk-4.1` development package discoverable with
  `pkg-config`. The build script does not download system packages.

The local WebView2 SDK cache is deliberately ignored. No SDK binaries are
committed.

With a configured SDK, run the end-to-end Windows host:

```powershell
moon run --target native src/examples/windows_smoke
```

Or use the repository helper, which scopes the SDK variables to one test run:

```powershell
.\scripts\test-windows.ps1 `
  -WebView2Sdk F:\path\to\Microsoft.Web.WebView2.1.0.x
```

On Linux, run the WebKitGTK smoke after installing the development package:

```sh
sh scripts/test-linux.sh
```

## Lifecycle Contract

Create the WebView on the UI thread that owns the parent container, keep that
platform's event loop running, and destroy the WebView before the parent.
Windows requires the caller's STA thread; macOS requires the main thread.
Creation may be asynchronous, so wait for `Ready` before treating the WebView
as usable. Navigation decisions are invoked synchronously on that same UI
thread and must return promptly.

The injected bridge exposes `window.moonview.postMessage(string)`. Message
payloads are UTF-8 strings; applications own any JSON or RPC protocol layered
on top of them. `WebView::eval` reports `ScriptResult` as JSON text on every
backend; JavaScript `undefined` is reported as `null`.

## Embedded Use

```moonbit
let options = @moonview.WebViewOptions::new(
  bounds=@moonview.Rect::new(x=0, y=0, width=800, height=600),
  initial_url="https://example.com",
  initialization_script="console.log('moonview initialized')",
  on_event=event => println("webview event: \\{event}"),
  on_navigation=_url => @moonview.NavigationDecision::Allow,
)

match @moonview.WebView::create(parent_handle, options) {
  Ok(view) => ignore(view.set_visible(true))
  Err(error) => abort("WebView creation rejected: \\{error}")
}
```

`Ready` and `CreationFailed` are asynchronous events. An initialization script
configured in `WebViewOptions` is installed before the first document loads;
`add_init_script` applies to documents loaded after it is registered.
`user_agent` configures the engine before its first document, and
`set_zoom_factor` accepts positive page zoom values.

## Validation

```powershell
moon check --target native
moon test --target native
moon info
moon fmt
```

The Windows smoke executable additionally requires the WebView2 SDK and a
native linker capable of consuming its static Loader library. The Linux smoke
uses a GTK window under the active display server, including WSLg.
