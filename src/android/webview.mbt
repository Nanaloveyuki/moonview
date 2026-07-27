///|
/// A WebView created through the optional `Nanaloveyuki/ajni/webview` feature.
/// The Android Kotlin host owns the underlying `android.webkit.WebView`.
pub struct AndroidWebView {
  priv handle : Int64
} derive(Eq, Debug)

///|
priv struct Registration {
  lifecycle : AndroidWebViewLifecycle
  trusted_origin : String
  resource_limits : AndroidResourceLimits
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
fn validate_options(options : AndroidWebViewOptions) -> String? {
  if options.bounds.width < 1 || options.bounds.height < 1 {
    Some("Android WebView bounds must have positive width and height")
  } else if !is_https_origin(options.trusted_origin) {
    Some("Android WebView trusted_origin must be one HTTPS origin")
  } else if options.resource_limits.max_page_message_bytes < 0 ||
    options.resource_limits.max_pending_asset_requests < 0 ||
    options.resource_limits.max_asset_response_bytes < 0 ||
    options.resource_limits.asset_response_timeout_millis < 0 {
    Some("Android WebView resource limits must be non-negative")
  } else {
    match options.initial_content {
      Html(_, base_url) if base_url == "" =>
        Some("Android HTML initial content requires an explicit base URL")
      Html(_, base_url) if !is_asset_url(base_url, options.trusted_origin) =>
        Some("Android HTML base URL must remain under trusted_origin/assets/")
      Url(url) if !is_asset_url(url, options.trusted_origin) =>
        Some(
          "Android WebView navigation must remain under trusted_origin/assets/",
        )
      _ => None
    }
  }
}

///|
fn is_https_origin(value : String) -> Bool {
  let parts = value.split("://").to_array()
  parts.length() == 2 &&
  parts[0] == "https" &&
  is_origin_authority(parts[1].to_owned())
}

///|
fn is_origin_authority(value : String) -> Bool {
  value.length() > 0 &&
  value.split("/").to_array().length() == 1 &&
  value.split("?").to_array().length() == 1 &&
  value.split("#").to_array().length() == 1 &&
  value.split("@").to_array().length() == 1 &&
  value.split(":").to_array().length() == 1
}

///|
fn belongs_to_origin(url : String, origin : String) -> Bool {
  let parts = url.split("://").to_array()
  if parts.length() != 2 || parts[0] != "https" {
    false
  } else {
    let authority_and_path = parts[1].to_owned().split("/").to_array()
    let origin_parts = origin.split("://").to_array()
    authority_and_path.length() > 0 &&
    origin_parts.length() == 2 &&
    authority_and_path[0] == origin_parts[1].to_owned()
  }
}

///|
fn is_asset_url(url : String, origin : String) -> Bool {
  belongs_to_origin(url, origin) &&
  url.to_array().starts_with((origin + "/assets/").to_array())
}

///|
fn require_operation_id(operation_id : String) -> Unit raise @ajni.JniError {
  if operation_id == "" {
    raise NativeFailure("Android WebView operation_id must not be empty")
  }
}

///|
fn native_initial_content(
  content : AndroidInitialContent,
) -> @webview.InitialContent {
  match content {
    Empty => Empty
    Url(url) => Url(url)
    Html(html, base_url) => Html(html, base_url)
  }
}

///|
fn native_resource_limits(
  limits : AndroidResourceLimits,
) -> @webview.WebViewResourceLimits {
  @webview.WebViewResourceLimits::new(
    max_page_message_bytes=limits.max_page_message_bytes,
    max_pending_asset_requests=limits.max_pending_asset_requests,
    max_asset_response_bytes=limits.max_asset_response_bytes,
    asset_response_timeout_millis=limits.asset_response_timeout_millis,
  )
}

///|
fn native_asset_response(
  response : AndroidAssetResponse,
) -> @webview.AssetResponse {
  let headers : Array[@webview.AssetHeader] = []
  for header in response.headers {
    headers.push(
      @webview.AssetHeader::new(name=header.name, value=header.value),
    )
  }
  @webview.AssetResponse::new(
    status=response.status,
    mime_type=response.mime_type,
    encoding=response.encoding,
    headers~,
    body=response.body,
  )
}

///|
fn cancel_partial_create(handle : Int64) -> Unit {
  @webview.destroy(handle, operation_id="moonview-partial-create") catch {
    _ => ()
  }
  ignore(registrations.remove(handle))
}

///|
/// Creates a child WebView in the Kotlin host attached through
/// `dev.nanaloveyuki.ajni.host.NativeBridge`.
///
/// `operation_id` is returned unchanged in asynchronous failure events.
pub fn AndroidWebView::create(
  options : AndroidWebViewOptions,
  operation_id : String,
) -> AndroidWebView raise @ajni.JniError {
  require_operation_id(operation_id)
  match validate_options(options) {
    Some(message) => raise NativeFailure(message)
    None => ()
  }
  ensure_callback()
  let handle = next_handle.val
  next_handle.val = handle + 1L
  registrations.set(handle, {
    lifecycle: Creating,
    trusted_origin: options.trusted_origin,
    resource_limits: options.resource_limits,
    on_event: options.on_event,
  })
  @webview.create(
    handle,
    options.trusted_origin,
    native_initial_content(options.initial_content),
    document_start_scripts=options.document_start_scripts,
    resource_limits=native_resource_limits(options.resource_limits),
    operation_id~,
  ) catch {
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
  { handle, }
}

///|
pub fn AndroidWebView::lifecycle(
  self : AndroidWebView,
) -> AndroidWebViewLifecycle {
  match registrations.get(self.handle) {
    Some(registration) => registration.lifecycle
    None => Destroyed
  }
}

///|
fn AndroidWebView::require_live(
  self : AndroidWebView,
) -> Unit raise @ajni.JniError {
  match self.lifecycle() {
    Destroyed => raise NativeFailure("Android WebView is destroyed")
    Failed(message) => raise NativeFailure(message)
    _ => ()
  }
}

///|
pub fn AndroidWebView::set_bounds(
  self : AndroidWebView,
  bounds : AndroidBounds,
) -> Unit raise @ajni.JniError {
  self.require_live()
  if bounds.width < 1 || bounds.height < 1 {
    raise NativeFailure(
      "Android WebView bounds must have positive width and height",
    )
  }
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
  operation_id : String,
) -> Unit raise @ajni.JniError {
  self.require_live()
  require_operation_id(operation_id)
  match registrations.get(self.handle) {
    Some(registration) if !is_asset_url(url, registration.trusted_origin) =>
      raise NativeFailure(
        "Android WebView navigation must remain under trusted_origin/assets/",
      )
    _ => ()
  }
  @webview.navigate(self.handle, url, operation_id~)
}

///|
pub fn AndroidWebView::load_html_with_base_url(
  self : AndroidWebView,
  html : String,
  base_url : String,
  operation_id : String,
) -> Unit raise @ajni.JniError {
  self.require_live()
  require_operation_id(operation_id)
  if base_url == "" {
    raise NativeFailure("Android HTML loading requires an explicit base URL")
  }
  match registrations.get(self.handle) {
    Some(registration) if !is_asset_url(base_url, registration.trusted_origin) =>
      raise NativeFailure(
        "Android HTML base URL must remain under trusted_origin/assets/",
      )
    _ => ()
  }
  @webview.load_html_with_base_url(self.handle, html, base_url, operation_id~)
}

///|
pub fn AndroidWebView::add_document_start_script(
  self : AndroidWebView,
  script : String,
  operation_id : String,
) -> Unit raise @ajni.JniError {
  self.require_live()
  require_operation_id(operation_id)
  @webview.add_document_start_script(self.handle, script, operation_id~)
}

///|
pub fn AndroidWebView::eval(
  self : AndroidWebView,
  script : String,
  operation_id : String,
) -> Unit raise @ajni.JniError {
  self.require_live()
  require_operation_id(operation_id)
  @webview.eval(self.handle, script, operation_id)
}

///|
pub fn AndroidWebView::post_message(
  self : AndroidWebView,
  body : String,
  operation_id : String,
) -> Unit raise @ajni.JniError {
  self.require_live()
  require_operation_id(operation_id)
  @webview.post_message(self.handle, body, operation_id~)
}

///|
pub fn AndroidWebView::respond_asset(
  self : AndroidWebView,
  request_id : String,
  response : AndroidAssetResponse,
  operation_id : String,
) -> Unit raise @ajni.JniError {
  self.require_live()
  require_operation_id(operation_id)
  if response.status < 100 || response.status > 599 {
    raise NativeFailure(
      "Android asset response status must be between 100 and 599",
    )
  }
  match registrations.get(self.handle) {
    Some(registration) if registration.resource_limits.max_asset_response_bytes !=
      0 &&
      response.body.length() >
      registration.resource_limits.max_asset_response_bytes =>
      raise NativeFailure("Android asset response exceeds its configured limit")
    _ => ()
  }
  @webview.respond_asset(
    self.handle,
    request_id,
    native_asset_response(response),
    operation_id~,
  )
}

///|
pub fn AndroidWebView::destroy(
  self : AndroidWebView,
  operation_id : String,
) -> Unit raise @ajni.JniError {
  if self.lifecycle() == Destroyed {
    ()
  } else {
    require_operation_id(operation_id)
    @webview.destroy(self.handle, operation_id~)
  }
}

///|
fn update_lifecycle(
  handle : Int64,
  lifecycle : AndroidWebViewLifecycle,
) -> Unit {
  match registrations.get(handle) {
    Some(registration) =>
      registrations.set(handle, {
        lifecycle,
        trusted_origin: registration.trusted_origin,
        resource_limits: registration.resource_limits,
        on_event: registration.on_event,
      })
    None => ()
  }
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
        Created(_) => {
          update_lifecycle(handle, Ready)
          (registration.on_event)(Ready)
        }
        NavigationStarted(url) =>
          (registration.on_event)(NavigationStarting(url))
        NavigationFinished(url) => {
          (registration.on_event)(SourceChanged(url))
          (registration.on_event)(NavigationCompleted(url))
        }
        TitleChanged(title) => (registration.on_event)(TitleChanged(title))
        ScriptResult(operation_id, result) =>
          (registration.on_event)(ScriptResult(operation_id, result))
        PageMessage(body, origin, is_main_frame) =>
          (registration.on_event)(PageMessage({ body, origin, is_main_frame }))
        AssetRequest(request) =>
          (registration.on_event)(
            AssetRequest({ id: request.id, path: request.path }),
          )
        Failed(message) => {
          update_lifecycle(handle, Failed(message))
          (registration.on_event)(CreationFailed("", message))
        }
        OperationFailed(operation_id, message) =>
          match registration.lifecycle {
            Creating => {
              update_lifecycle(handle, Failed(message))
              (registration.on_event)(CreationFailed(operation_id, message))
            }
            _ => (registration.on_event)(OperationFailed(operation_id, message))
          }
        Destroyed => {
          update_lifecycle(handle, Destroyed)
          (registration.on_event)(Destroyed)
          ignore(registrations.remove(handle))
        }
      }
  }
}
