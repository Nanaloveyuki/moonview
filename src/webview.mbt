///|
/// An embedded platform WebView associated with a caller-owned native container.
pub struct WebView {
  priv handle : UInt64
}

///|
/// Returns whether the native backend is available on the current host.
pub fn available() -> Bool {
  native_available()
}

///|
/// Registers an application-owned custom URL scheme for the process.
///
/// Call this before the first successful `WebView::create`. Native handlers
/// have a 30-second response deadline; unanswered requests are cancelled by
/// the backend and reported as `ProtocolCancelled`.
pub fn register_custom_scheme(name : String) -> Result[Unit, WebViewError] {
  if custom_schemes_locked.contains(0) {
    Err(WebViewError::ConfigurationLocked)
  } else if name.length() == 0 {
    Err(WebViewError::NativeFailure(0, "Custom scheme name must not be empty"))
  } else if native_register_custom_scheme(encode_utf8(name)) != 0 {
    Ok(())
  } else {
    Err(
      WebViewError::Unsupported(
        "Custom schemes are unavailable on this backend",
      ),
    )
  }
}

///|
/// Starts asynchronous creation of a WebView child view in `parent_handle`.
///
/// The caller must keep the native parent container alive and run its UI event
/// loop until the listener receives `WebViewEvent::Ready` or `CreationFailed`.
/// On Windows, this is an `HWND`; on macOS, an `NSView*`; and on Linux, a
/// `GtkFixed*`.
pub fn WebView::create(
  parent_handle : UInt64,
  options : WebViewOptions,
) -> Result[WebView, WebViewError] {
  if !available() {
    Err(WebViewError::Unavailable)
  } else {
    ensure_native_callbacks()
    if !custom_schemes_locked.contains(0) {
      native_lock_custom_schemes()
      custom_schemes_locked.set(0, ())
    }
    let handle = native_create(
      parent_handle,
      options.bounds.x,
      options.bounds.y,
      options.bounds.width,
      options.bounds.height,
      encode_utf8(options.initial_url),
      encode_utf8(options.initial_html),
      encode_utf8(options.initialization_script),
      encode_utf8(options.user_agent),
    )
    if handle == 0 {
      Err(WebViewError::CreateRejected)
    } else {
      register_view(handle, options)
      let view = WebView::{ handle, }
      if !options.visible {
        native_set_visible(handle, false)
      }
      native_start(handle)
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
    native_set_bounds(handle, bounds.x, bounds.y, bounds.width, bounds.height)
  })
}

///|
pub fn WebView::set_visible(
  self : WebView,
  visible : Bool,
) -> Result[Unit, WebViewError] {
  self.with_handle(handle => native_set_visible(handle, visible))
}

///|
pub fn WebView::focus(self : WebView) -> Result[Unit, WebViewError] {
  self.with_handle(handle => native_focus(handle))
}

///|
pub fn WebView::navigate(
  self : WebView,
  url : String,
) -> Result[Unit, WebViewError] {
  self.with_handle(handle => native_navigate(handle, encode_utf8(url)))
}

///|
pub fn WebView::load_html(
  self : WebView,
  html : String,
) -> Result[Unit, WebViewError] {
  self.with_handle(handle => native_load_html(handle, encode_utf8(html)))
}

///|
pub fn WebView::reload(self : WebView) -> Result[Unit, WebViewError] {
  self.with_handle(handle => native_reload(handle))
}

///|
pub fn WebView::stop(self : WebView) -> Result[Unit, WebViewError] {
  self.with_handle(handle => native_stop(handle))
}

///|
pub fn WebView::go_back(self : WebView) -> Result[Unit, WebViewError] {
  self.with_handle(handle => native_go_back(handle))
}

///|
pub fn WebView::go_forward(self : WebView) -> Result[Unit, WebViewError] {
  self.with_handle(handle => native_go_forward(handle))
}

///|
pub fn WebView::add_init_script(
  self : WebView,
  script : String,
) -> Result[Unit, WebViewError] {
  self.with_handle(handle => native_add_init_script(handle, encode_utf8(script)))
}

///|
/// Sets the page zoom factor. Values must be greater than zero.
pub fn WebView::set_zoom_factor(
  self : WebView,
  factor : Double,
) -> Result[Unit, WebViewError] {
  if factor <= 0.0 {
    Err(
      WebViewError::NativeFailure(
        0, "WebView zoom factor must be greater than zero",
      ),
    )
  } else {
    self.with_handle(handle => native_set_zoom(handle, factor))
  }
}

///|
/// Opens the platform developer tools for this WebView.
///
/// This is supported by the Windows and Linux backends. macOS does not expose
/// a supported public API for programmatically opening WKWebView inspector.
pub fn WebView::open_devtools(self : WebView) -> Result[Unit, WebViewError] {
  match self.lifecycle() {
    WebViewLifecycle::Destroyed => Err(WebViewError::Destroyed)
    WebViewLifecycle::Failed(error) => Err(error)
    _ =>
      if native_open_devtools(self.handle) != 0 {
        Ok(())
      } else {
        Err(
          WebViewError::Unsupported(
            "WebView developer tools are unavailable on this backend",
          ),
        )
      }
  }
}

///|
/// Opens the platform print dialog for the current document.
///
/// The dialog is available after `Ready`. Older WebView2 runtimes and macOS
/// releases before 11 return `Unsupported`.
pub fn WebView::open_print_dialog(self : WebView) -> Result[Unit, WebViewError] {
  match self.lifecycle() {
    WebViewLifecycle::Destroyed => Err(WebViewError::Destroyed)
    WebViewLifecycle::Failed(error) => Err(error)
    _ =>
      if native_open_print_dialog(self.handle) != 0 {
        Ok(())
      } else {
        Err(
          WebViewError::Unsupported(
            "WebView print dialog is unavailable on this backend",
          ),
        )
      }
  }
}

///|
pub fn WebView::eval(
  self : WebView,
  script : String,
  request_id : String,
) -> Result[Unit, WebViewError] {
  self.with_handle(handle => {
    native_eval(handle, encode_utf8(script), encode_utf8(request_id))
  })
}

///|
/// Posts an application-defined UTF-8 message to `window.moonview` in the page.
pub fn WebView::post_message(
  self : WebView,
  message : String,
) -> Result[Unit, WebViewError] {
  self.with_handle(handle => native_post_message(handle, encode_utf8(message)))
}

///|
/// Completes a pending custom-scheme request. The request ID is valid only
/// until the native backend's 30-second response deadline expires.
pub fn WebView::respond_protocol(
  self : WebView,
  request_id : String,
  response : ProtocolResponse,
) -> Result[Unit, WebViewError] {
  match self.lifecycle() {
    WebViewLifecycle::Destroyed => Err(WebViewError::Destroyed)
    WebViewLifecycle::Failed(error) => Err(error)
    _ =>
      if native_respond_protocol(
          self.handle,
          encode_utf8(request_id),
          response.status,
          encode_http_headers(response.headers),
          response.body,
        ) !=
        0 {
        Ok(())
      } else {
        Err(
          WebViewError::NativeFailure(
            0, "Protocol request is no longer pending",
          ),
        )
      }
  }
}

///|
/// Destroys the native child view. Repeated calls are harmless.
pub fn WebView::destroy(self : WebView) -> Result[Unit, WebViewError] {
  if self.lifecycle() == WebViewLifecycle::Destroyed {
    Ok(())
  } else if native_destroy(self.handle) != 0 {
    unregister_view(self.handle)
    Ok(())
  } else {
    Err(
      WebViewError::NativeFailure(
        0, "WebView destroy must run on its creation UI thread",
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
