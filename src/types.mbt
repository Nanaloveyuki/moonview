///|
/// A pixel rectangle relative to the caller-owned native parent container.
pub(all) struct Rect {
  x : Int
  y : Int
  width : Int
  height : Int
} derive(Eq, Debug)

///|
/// State reported by an asynchronously-created native WebView.
pub(all) enum WebViewLifecycle {
  Creating
  Ready
  Failed(WebViewError)
  Destroyed
} derive(Eq, Debug)

///|
/// Failures reported before or during native WebView creation, after disposal,
/// or when a command is issued outside the owner UI thread.
pub(all) enum WebViewError {
  Unavailable
  Unsupported(String)
  ConfigurationLocked
  CreateRejected
  /// The command must run on the UI thread that created this WebView.
  WrongThread
  Destroyed
  NativeFailure(Int, String)
} derive(Eq, Debug)

///|
/// The decision synchronously returned to a native navigation callback.
pub(all) enum NavigationDecision {
  Allow
  Deny
} derive(Eq, Debug)

///|
/// The most recently observed document URL and history availability.
pub(all) struct NavigationState {
  url : String
  can_go_back : Bool
  can_go_forward : Bool
} derive(Eq, Debug)

///|
/// A single HTTP header in a custom-scheme request or response.
pub(all) struct HttpHeader {
  name : String
  value : String
} derive(Eq, Debug)

///|
/// A pending custom-scheme request. `body` is unmodified binary request data.
pub(all) struct ProtocolRequest {
  id : String
  scheme : String
  http_method : String
  uri : String
  headers : Array[HttpHeader]
  body : Bytes
} derive(Eq, Debug)

///|
/// A response to a pending custom-scheme request.
pub(all) struct ProtocolResponse {
  status : Int
  headers : Array[HttpHeader]
  body : Bytes
} derive(Eq, Debug)

///|
/// A media capture category requested by page content.
pub(all) enum MediaPermissionKind {
  Camera
  Microphone
  CameraAndMicrophone
  Unknown(Int)
} derive(Eq, Debug)

///|
/// A synchronous request to access local media devices from an origin.
pub(all) struct MediaPermissionRequest {
  kind : MediaPermissionKind
  origin : String
} derive(Eq, Debug)

///|
/// The decision synchronously returned to a native media-permission callback.
pub(all) enum MediaPermissionDecision {
  Allow
  Deny
} derive(Eq, Debug)

///|
/// Events emitted on the native UI thread that owns the parent container.
///
/// `ScriptResult` and `ScriptFailed` preserve the request identifier supplied
/// to `WebView::eval`. `ScriptResult` is JSON text; an `undefined` JavaScript
/// result is represented as `null`. Page messages are UTF-8 strings without an
/// imposed protocol.
pub(all) enum WebViewEvent {
  Ready
  CreationFailed(WebViewError)
  PageMessage(String)
  NavigationStarting(String)
  SourceChanged(String)
  NavigationCompleted(String)
  NavigationFailed(String, WebViewError)
  TitleChanged(String)
  HistoryChanged(Bool, Bool)
  ScriptResult(String, String)
  ScriptFailed(String, WebViewError)
  ProtocolRequest(ProtocolRequest)
  ProtocolCancelled(String)
} derive(Eq, Debug)

///|
/// Configuration passed while the native WebView is being created.
///
/// If both initial content fields are non-empty, `initial_html` takes
/// precedence. Treat the WebView as usable only after its `Ready` event.
pub(all) struct WebViewOptions {
  context : WebContext
  bounds : Rect
  initial_url : String
  initial_html : String
  initialization_script : String
  user_agent : String
  visible : Bool
  on_event : (WebViewEvent) -> Unit
  on_navigation : (String) -> NavigationDecision
  on_media_permission : (MediaPermissionRequest) -> MediaPermissionDecision
}

///|
/// Configuration for attaching to an ArkUI-owned OpenHarmony `Web` component.
///
/// The ArkUI host owns the component's source, layout, visibility, and browser
/// permissions. This API is separate from `WebViewOptions` so unsupported
/// creation settings cannot be silently ignored.
pub(all) struct OhosAttachOptions {
  on_event : (WebViewEvent) -> Unit
}

///|
pub fn OhosAttachOptions::new(
  on_event? : (WebViewEvent) -> Unit = ignore_event,
) -> OhosAttachOptions {
  { on_event, }
}

///|
pub fn Rect::new(x~ : Int, y~ : Int, width~ : Int, height~ : Int) -> Rect {
  { x, y, width, height }
}

///|
pub fn NavigationState::new(
  url? : String = "",
  can_go_back? : Bool = false,
  can_go_forward? : Bool = false,
) -> NavigationState {
  { url, can_go_back, can_go_forward }
}

///|
pub fn HttpHeader::new(name~ : String, value~ : String) -> HttpHeader {
  { name, value }
}

///|
pub fn ProtocolResponse::new(
  status~ : Int,
  headers? : Array[HttpHeader] = [],
  body? : Bytes = b"",
) -> ProtocolResponse {
  { status, headers, body }
}

///|
pub fn WebViewOptions::new(
  bounds~ : Rect,
  context? : WebContext = WebContext::persistent(),
  initial_url? : String = "",
  initial_html? : String = "",
  initialization_script? : String = "",
  user_agent? : String = "",
  visible? : Bool = true,
  on_event? : (WebViewEvent) -> Unit = ignore_event,
  on_navigation? : (String) -> NavigationDecision = allow_navigation,
  on_media_permission? : (MediaPermissionRequest) -> MediaPermissionDecision = deny_media_permission,
) -> WebViewOptions {
  {
    context,
    bounds,
    initial_url,
    initial_html,
    initialization_script,
    user_agent,
    visible,
    on_event,
    on_navigation,
    on_media_permission,
  }
}

///|
fn ignore_event(_event : WebViewEvent) -> Unit {
  ()
}

///|
fn allow_navigation(_url : String) -> NavigationDecision {
  NavigationDecision::Allow
}

///|
fn deny_media_permission(
  _request : MediaPermissionRequest,
) -> MediaPermissionDecision {
  MediaPermissionDecision::Deny
}
