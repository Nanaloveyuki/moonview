# moonview

`moonview` is an Apache-2.0 MoonBit library for directly embedding native
WebViews. The first release targets Windows WebView2 and embeds into a
caller-owned `HWND`; it does not create windows or run an event loop.

## Status

Windows WebView2 is the active backend. macOS WKWebView and Linux WebKitGTK
are planned after the Windows API and lifecycle contract are validated.

## Build Prerequisites

- MoonBit native toolchain and a Windows-compatible C++ linker.
- Visual Studio Build Tools with the Windows SDK headers and libraries.
- Microsoft Edge WebView2 Runtime.
- WebView2 SDK, provided without automatic download by either:
  - `MOONVIEW_WEBVIEW2_SDK_DIR`, pointing at the SDK package root; or
  - `MOONVIEW_WEBVIEW2_INCLUDE` and `MOONVIEW_WEBVIEW2_LOADER_LIB`; or
  - `.tools/webview2/` with NuGet's `build/native/include/WebView2.h` and
    `build/native/x64/WebView2LoaderStatic.lib` layout. Set
    `MOONVIEW_WEBVIEW2_ARCH` for a non-x64 Loader path.

The local SDK cache is deliberately ignored. No SDK binaries are committed.

With a configured SDK, run the end-to-end Windows host:

```powershell
moon run --target native src/examples/windows_smoke
```

Or use the repository helper, which scopes the SDK variables to one test run:

```powershell
.\scripts\test-windows.ps1 `
  -WebView2Sdk F:\path\to\Microsoft.Web.WebView2.1.0.x
```

## Lifecycle Contract

Create the WebView on the same STA/UI thread that owns the parent `HWND`, keep
that thread's Win32 event loop running, and destroy the WebView before the
parent window. Creation is asynchronous: wait for `Ready` before treating the
WebView as usable. Commands issued while creation is pending are queued.

The injected bridge exposes `window.moonview.postMessage(string)`. Message
payloads are UTF-8 strings; applications own any JSON or RPC protocol layered
on top of them.

## Embedded Use

```moonbit
let options = @moonview.WebViewOptions::new(
  bounds=@moonview.Rect::new(x=0, y=0, width=800, height=600),
  initial_url="https://example.com",
  initialization_script="console.log('moonview initialized')",
  on_event=event => println("webview event: \\{event}"),
  on_navigation=_url => @moonview.NavigationDecision::Allow,
)

match @moonview.WebView::create(hwnd, options) {
  Ok(view) => ignore(view.set_visible(true))
  Err(error) => abort("WebView2 creation rejected: \\{error}")
}
```

`Ready` and `CreationFailed` are asynchronous events. An initialization script
configured in `WebViewOptions` is installed before the first document loads;
`add_init_script` applies to documents loaded after it is registered.

## Validation

```powershell
moon check --target native
moon test --target native
moon info
moon fmt
```

The Windows smoke executable additionally requires the WebView2 SDK and a
native linker capable of consuming its static Loader library.
