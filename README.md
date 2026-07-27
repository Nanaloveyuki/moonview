# moonview

`moonview` embeds a native platform WebView into a MoonBit application's
existing window. It does not create a top-level window or run an event loop.
The host owns those responsibilities; `moonview` owns the child WebView.

## Install

Add the preview package to a native MoonBit module:

```sh
moon add Nanaloveyuki/moonview@0.1.0-alpha.1
```

Add the package import in the consumer's `moon.pkg`, then refer to it as
`@moonview`:

```moonbit
import {
  "Nanaloveyuki/moonview",
}
```

The package-level reference is [src/README.mbt.md](src/README.mbt.md).

## Host Contract

Create the WebView on the UI thread that owns its native parent, keep that
platform's event loop running, resize it with the parent, and destroy it before
the parent is destroyed.

| Platform | `parent_handle` passed to `WebView::create` |
| --- | --- |
| Windows | A caller-owned `HWND` on an STA UI thread |
| macOS | A caller-owned `NSView*` on the main thread |
| Linux | A caller-owned `GtkFixed*` on the GTK UI thread |
| OpenHarmony | An ArkUI-owned `Web` component identified by `webTag` |

This raw-handle boundary is intentional so a window-management library can own
native window creation and event dispatch. Popup and `window.open` requests are
denied by default.

## Create A WebView

Use `Ready` before issuing work that requires a loaded native view.
`initial_html` takes precedence when both initial-content fields are set.

```moonbit nocheck
let options = @moonview.WebViewOptions::new(
  bounds=@moonview.Rect::new(x=0, y=0, width=800, height=600),
  initial_url="https://example.com",
  initialization_script="console.log('moonview initialized')",
  on_event=event => match event {
    @moonview.WebViewEvent::Ready => println("webview ready")
    @moonview.WebViewEvent::CreationFailed(error) => println("create failed: \{error}")
    _ => ()
  },
  on_navigation=_url => @moonview.NavigationDecision::Allow,
)

match @moonview.WebView::create(parent_handle, options) {
  Ok(view) => ignore(view.set_visible(true))
  Err(error) => abort("WebView creation rejected: \{error}")
}
```

Resize the child with the host window and dispose it during host teardown:

```moonbit nocheck
ignore(view.set_bounds(@moonview.Rect::new(x=0, y=0, width=1024, height=768)))
ignore(view.navigate("https://example.com/docs"))
ignore(view.destroy())
```

Control methods return `Ok(())` only when the native backend accepts or queues
the command for a live view. Page navigation and JavaScript execution remain
asynchronous; observe their final outcomes through `WebViewEvent`.

## OpenHarmony ArkWeb (Experimental)

OpenHarmony does not expose native creation of an arbitrary child WebView. The
ArkUI host creates the `Web` component, selects its source and permissions, and
then attaches Moonview using that component's stable `webTag` on the ArkUI UI
thread:

```moonbit nocheck
let options = @moonview.OhosAttachOptions::new(
  on_event=event => match event {
    @moonview.WebViewEvent::Ready => println("ArkWeb controller attached")
    _ => ()
  },
)

match @moonview.WebView::attach_ohos("main-web", options) {
  Ok(view) => {
    ignore(view.reload())
    // API 12 executes this without a ScriptResult callback.
    ignore(view.eval("console.log('from MoonBit')", "startup"))
  }
  Err(error) => abort("ArkWeb attach rejected: \{error}")
}
```

This first adapter targets OpenHarmony API 12 and supports attach, `reload`,
fire-and-forget `eval`, and detachment through `destroy`. ArkUI retains source,
layout, visibility, focus, and media-permission ownership. Navigation, HTML
loading, init scripts, history, zoom, page messaging, custom schemes, and
script-result callbacks return `Unsupported` until their thread-safe native
adapters are implemented. `destroy` detaches Moonview only; it never destroys
the ArkUI component.

## Page Communication

The injected page bridge exposes `window.moonview.postMessage(string)`. Handle
`PageMessage` in `on_event`, and send data to the page with `post_message`.
Payloads are UTF-8 strings; applications define their own JSON or RPC protocol.
When native code posts to the page, `window.moonview.onmessage` receives an
object with the UTF-8 payload in `event.data` on every desktop backend.

```moonbit nocheck
match event {
  @moonview.WebViewEvent::PageMessage(message) => println("page: \{message}")
  @moonview.WebViewEvent::ScriptResult(id, value) => println("\{id}: \{value}")
  _ => ()
}

ignore(view.post_message("host-ready"))
ignore(view.eval("document.title", "document-title"))
```

```javascript
window.moonview.onmessage = event => {
  console.log(event.data)
}
```

`eval` reports JSON text through `ScriptResult`; JavaScript `undefined` is
reported as `null`.

## Serve Application Resources

Register application-owned schemes before the first `WebView::create`. Native
backends emit `ProtocolRequest` events containing the method, URI, headers, and
binary body. Retain the owning `WebView` in the callback state, then answer the
request with `respond_protocol` before its 30-second deadline.

```moonbit nocheck
ignore(@moonview.register_custom_scheme("app"))

let response = @moonview.ProtocolResponse::new(
  status=200,
  headers=[@moonview.HttpHeader::new(name="Content-Type", value="text/html")],
  body=b"<!doctype html><title>moonview</title>",
)

// In the WebView event callback:
// @moonview.WebViewEvent::ProtocolRequest(request) =>
//   ignore(view.respond_protocol(request.id, response))
```

Use URLs such as `app://ui/index.html`. Windows and WebKitGTK register custom
schemes as secure origins; WKWebView uses its public URL-scheme handler.
Unanswered or cancelled requests emit `ProtocolCancelled`.

## Permissions And Diagnostics

Camera and microphone requests are denied by default. Supply
`on_media_permission` only when the application can make a synchronous policy
decision for the requesting origin. Other browser permission categories are not
part of the cross-platform API.

`open_devtools` is available on Windows and Linux; WKWebView returns
`Unsupported`. `open_print_dialog` uses the platform print UI and may be
unsupported on older platform runtimes.

## Platform Prerequisites

- Windows: Visual Studio Build Tools, Edge WebView2 Runtime, and the WebView2
  SDK. Set `MOONVIEW_WEBVIEW2_SDK_DIR`, or set both
  `MOONVIEW_WEBVIEW2_INCLUDE` and `MOONVIEW_WEBVIEW2_LOADER_LIB`. Set
  `MOONVIEW_WEBVIEW2_ARCH` for a non-x64 Loader path.
- macOS: Xcode Command Line Tools. WKWebView is supplied by the operating
  system.
- Linux: GTK 3 and the `webkit2gtk-4.1` development package available through
  `pkg-config`. The Linux smoke also works through WSLg.
- OpenHarmony: an app manifest declaring `SystemCapability.Web.Webview.Core`
  and the user-supplied ArkWeb NDK. Set `MOONVIEW_OHOS_ARKWEB_SDK_DIR` (or
  `MOONVIEW_OHOS_NDK_HOME`) to a directory containing
  `arkweb_interface.h` and `libohweb.so`; alternatively set both
  `MOONVIEW_OHOS_ARKWEB_INCLUDE` and `MOONVIEW_OHOS_ARKWEB_LIB`. Moonview
  does not vendor or read SDK files from `ref/`.

## Verify A Checkout

```powershell
moon fmt --check
moon check --target native
moon test --target native
.\scripts\test-windows.ps1 -WebView2Sdk F:\path\to\Microsoft.Web.WebView2.1.0.x
```

macOS and Fedora native smoke coverage runs in GitHub Actions.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup, validation, and
pull request requirements.

## Preview Compatibility

`0.1.0-alpha.1` is an API preview. Compatibility may change before stable
`0.1.0`, particularly once a concrete window-host integration contract exists.
