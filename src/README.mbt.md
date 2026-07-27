# moonview

`moonview` is the native-only package for embedding a platform WebView in a
caller-owned native container. The host supplies the parent handle, owns the UI
thread and event loop, resizes the child, and destroys the child before its
parent.

## Minimal Use

```moonbit nocheck
let options = WebViewOptions::new(
  bounds=Rect::new(x=0, y=0, width=800, height=600),
  initial_html="<!doctype html><title>moonview</title>",
  on_event=event => match event {
    WebViewEvent::Ready => println("ready")
    WebViewEvent::CreationFailed(error) => println("failed: \{error}")
    _ => ()
  },
)

match WebView::create(parent_handle, options) {
  Ok(view) => ignore(view.post_message("host-ready"))
  Err(error) => abort("create rejected: \{error}")
}
```

Use `WebViewEvent::Ready` before relying on a loaded document. Page code sends
UTF-8 strings with `window.moonview.postMessage(...)`; native code receives
`PageMessage` and sends strings with `WebView::post_message(...)`.

## OpenHarmony ArkWeb

OpenHarmony hosts `Web` in ArkUI rather than accepting an arbitrary native
parent handle. Create that component in ArkUI, then attach on its UI thread by
its stable `webTag`:

```moonbit nocheck
let options = OhosAttachOptions::new(
  on_event=event => match event {
    WebViewEvent::Ready => println("ArkWeb attached")
    _ => ()
  },
)

match WebView::attach_ohos("main-web", options) {
  Ok(view) => {
    ignore(view.reload())
    ignore(view.eval("console.log('moonview')", "startup"))
  }
  Err(error) => abort("ArkWeb attach rejected: \{error}")
}
```

The experimental API 12 adapter supports attach, `reload`, fire-and-forget
`eval`, and detachment. ArkUI owns source, layout, visibility, and permissions;
the remaining desktop-style controls return `Unsupported`. `destroy` detaches
Moonview and does not destroy the ArkUI `Web` component.

## Application Resources

Call `register_custom_scheme(...)` before the first `WebView::create`, then
respond to each `ProtocolRequest` with `WebView::respond_protocol(...)`. The
request callback carries method, URI, headers, and binary body data; unanswered
requests are cancelled after 30 seconds.

## Permissions

Camera and microphone requests are denied unless `on_media_permission` returns
`MediaPermissionDecision::Allow`. Other browser permission kinds are not part
of this cross-platform package API.

## Main Entry Points

- `WebViewOptions::new(...)` configures creation callbacks and initial content.
- `WebView::create(...)` embeds an asynchronously-created native child view.
- `WebView::set_bounds(...)`, `navigate(...)`, `eval(...)`, and
  `post_message(...)` control a live view.
- `WebView::destroy(...)` releases the native child before the host parent.
- `register_custom_scheme(...)` and `WebView::respond_protocol(...)` serve
  application-owned resources.

See the repository README for platform prerequisites and host-handle details.
