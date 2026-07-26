///|
/// An embedded WebView2 associated with a caller-owned Win32 HWND.
pub struct WebView {
  priv handle : UInt64
}

///|
/// Returns whether the Windows WebView2 backend was compiled in and can create
/// native views on the current host.
pub fn available() -> Bool {
  @windows.available() != 0
}

///|
/// Starts asynchronous creation of a WebView2 child view in `hwnd`.
///
/// The caller must keep `hwnd` alive and pump its STA message loop until the
/// listener receives `WebViewEvent::Ready` or `CreationFailed`.
pub fn WebView::create(
  hwnd : UInt64,
  options : WebViewOptions,
) -> Result[WebView, WebViewError] {
  if !available() {
    Err(WebViewError::Unavailable)
  } else {
    ensure_native_callbacks()
    let handle = @windows.create(
      hwnd,
      options.bounds.x,
      options.bounds.y,
      options.bounds.width,
      options.bounds.height,
      encode_utf8(options.initial_url),
      encode_utf8(options.initial_html),
      encode_utf8(options.initialization_script),
    )
    if handle == 0 {
      Err(WebViewError::CreateRejected)
    } else {
      register_view(handle, options)
      let view = WebView::{ handle, }
      if !options.visible {
        @windows.set_visible(handle, 0)
      }
      @windows.start(handle)
      Ok(view)
    }
  }
}

///|
pub fn WebView::lifecycle(self : WebView) -> WebViewLifecycle {
  lifecycle_of(self.handle)
}

///|
pub fn WebView::set_bounds(
  self : WebView,
  bounds : Rect,
) -> Result[Unit, WebViewError] {
  self.with_handle(handle => {
    @windows.set_bounds(handle, bounds.x, bounds.y, bounds.width, bounds.height)
  })
}

///|
pub fn WebView::set_visible(
  self : WebView,
  visible : Bool,
) -> Result[Unit, WebViewError] {
  self.with_handle(handle => {
    @windows.set_visible(handle, if visible { 1 } else { 0 })
  })
}

///|
pub fn WebView::focus(self : WebView) -> Result[Unit, WebViewError] {
  self.with_handle(handle => @windows.focus(handle))
}

///|
pub fn WebView::navigate(
  self : WebView,
  url : String,
) -> Result[Unit, WebViewError] {
  self.with_handle(handle => @windows.navigate(handle, encode_utf8(url)))
}

///|
pub fn WebView::load_html(
  self : WebView,
  html : String,
) -> Result[Unit, WebViewError] {
  self.with_handle(handle => @windows.load_html(handle, encode_utf8(html)))
}

///|
pub fn WebView::reload(self : WebView) -> Result[Unit, WebViewError] {
  self.with_handle(handle => @windows.reload(handle))
}

///|
pub fn WebView::stop(self : WebView) -> Result[Unit, WebViewError] {
  self.with_handle(handle => @windows.stop(handle))
}

///|
pub fn WebView::go_back(self : WebView) -> Result[Unit, WebViewError] {
  self.with_handle(handle => @windows.go_back(handle))
}

///|
pub fn WebView::go_forward(self : WebView) -> Result[Unit, WebViewError] {
  self.with_handle(handle => @windows.go_forward(handle))
}

///|
pub fn WebView::add_init_script(
  self : WebView,
  script : String,
) -> Result[Unit, WebViewError] {
  self.with_handle(handle => {
    @windows.add_init_script(handle, encode_utf8(script))
  })
}

///|
pub fn WebView::eval(
  self : WebView,
  script : String,
  request_id : String,
) -> Result[Unit, WebViewError] {
  self.with_handle(handle => {
    @windows.eval(handle, encode_utf8(script), encode_utf8(request_id))
  })
}

///|
/// Posts an application-defined UTF-8 message to `window.moonview` in the page.
pub fn WebView::post_message(
  self : WebView,
  message : String,
) -> Result[Unit, WebViewError] {
  self.with_handle(handle => @windows.post_message(handle, encode_utf8(message)))
}

///|
/// Destroys the native child view. Repeated calls are harmless.
pub fn WebView::destroy(self : WebView) -> Result[Unit, WebViewError] {
  if self.lifecycle() == WebViewLifecycle::Destroyed {
    Ok(())
  } else if @windows.destroy(self.handle) != 0 {
    unregister_view(self.handle)
    Ok(())
  } else {
    Err(
      WebViewError::NativeFailure(
        0, "WebView destroy must run on its creation STA thread",
      ),
    )
  }
}

///|
fn WebView::with_handle(
  self : WebView,
  operation : (UInt64) -> Unit,
) -> Result[Unit, WebViewError] {
  match self.lifecycle() {
    WebViewLifecycle::Destroyed => Err(WebViewError::Destroyed)
    WebViewLifecycle::Failed(error) => Err(error)
    _ => {
      operation(self.handle)
      Ok(())
    }
  }
}
