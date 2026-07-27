///|
/// A WebView created through the optional `Nanaloveyuki/ajni/webview` feature.
/// The Android Kotlin host owns the underlying `android.webkit.WebView`.
pub struct AndroidWebView {
  priv handle : Int64
} derive(Eq, Debug)

///|
priv struct Registration {
  on_event : (AndroidWebViewEvent) -> Unit
}

///|
let registrations : Map[Int64, Registration] = Map([])

///|
let next_handle : Ref[Int64] = Ref(1L)

///|
let callback_installed : Map[Int, Unit] = Map([])

///|
fn ensure_callback() -> Unit {
  if !callback_installed.contains(0) {
    ignore(@webview.install_event_handler(dispatch_webview_event))
    callback_installed.set(0, ())
  }
}

///|
fn cancel_partial_create(handle : Int64) -> Unit {
  @webview.destroy(handle) catch {
    _ => ()
  }
  ignore(registrations.remove(handle))
}

///|
/// Creates a child WebView in the Kotlin host attached through
/// `dev.nanaloveyuki.ajni.host.NativeBridge`. The host must be attached before
/// this function is called; otherwise ajni raises `JniError::NotInitialized`.
pub fn AndroidWebView::create(
  options : AndroidWebViewOptions,
) -> AndroidWebView raise @ajni.JniError {
  ensure_callback()
  let handle = next_handle.val
  next_handle.val = handle + 1L
  registrations.set(handle, { on_event: options.on_event })
  let initial_url = if options.initial_html == "" {
    options.initial_url
  } else {
    ""
  }
  @webview.create(handle, initial_url) catch {
    error => {
      cancel_partial_create(handle)
      raise error
    }
  }
  @webview.set_bounds(
    handle,
    options.bounds.x,
    options.bounds.y,
    options.bounds.width,
    options.bounds.height,
  ) catch {
    error => {
      cancel_partial_create(handle)
      raise error
    }
  }
  if options.initial_html != "" {
    @webview.load_html(handle, options.initial_html) catch {
      error => {
        cancel_partial_create(handle)
        raise error
      }
    }
  }
  { handle, }
}

///|
pub fn AndroidWebView::set_bounds(
  self : AndroidWebView,
  bounds : AndroidBounds,
) -> Unit raise @ajni.JniError {
  @webview.set_bounds(
    self.handle,
    bounds.x,
    bounds.y,
    bounds.width,
    bounds.height,
  )
}

///|
pub fn AndroidWebView::navigate(
  self : AndroidWebView,
  url : String,
) -> Unit raise @ajni.JniError {
  @webview.navigate(self.handle, url)
}

///|
pub fn AndroidWebView::load_html(
  self : AndroidWebView,
  html : String,
) -> Unit raise @ajni.JniError {
  @webview.load_html(self.handle, html)
}

///|
pub fn AndroidWebView::eval(
  self : AndroidWebView,
  script : String,
  request_id : String,
) -> Unit raise @ajni.JniError {
  @webview.eval(self.handle, script, request_id)
}

///|
pub fn AndroidWebView::destroy(
  self : AndroidWebView,
) -> Unit raise @ajni.JniError {
  @webview.destroy(self.handle)
}

///|
fn dispatch_webview_event(event : @webview.Event) -> Unit {
  dispatch_event_kind(event.handle, event.kind)
}

///|
fn dispatch_event_kind(handle : Int64, kind : @webview.EventKind) -> Unit {
  match registrations.get(handle) {
    None => ()
    Some(registration) =>
      match kind {
        Created(_) => (registration.on_event)(Ready)
        NavigationStarted(url) =>
          (registration.on_event)(NavigationStarting(url))
        NavigationFinished(url) => {
          (registration.on_event)(SourceChanged(url))
          (registration.on_event)(NavigationCompleted(url))
        }
        TitleChanged(title) => (registration.on_event)(TitleChanged(title))
        ScriptResult(request_id, result) =>
          (registration.on_event)(ScriptResult(request_id, result))
        Failed(message) => (registration.on_event)(Failed(message))
        Destroyed => {
          (registration.on_event)(Destroyed)
          ignore(registrations.remove(handle))
        }
      }
  }
}
