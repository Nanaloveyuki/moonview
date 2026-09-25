///|
/// A pixel rectangle relative to the caller-owned native parent container.
pub(all) struct Rect {
  x : Int
  y : Int
  width : Int
  height : Int
} derive(Eq, Debug)

///|
#deprecated("Use `==` instead", skip_current_package=true)
#doc(hidden)
pub extend Rect with Eq::{equal, not_equal}

///|
#deprecated("Use `Debug::to_repr` instead", skip_current_package=true)
#doc(hidden)
pub extend Rect with Debug::{to_repr}

///|
/// State reported by an asynchronously-created native WebView.
pub(all) enum WebViewLifecycle {
  Creating
  Ready
  Failed(WebViewError)
  Destroyed
} derive(Eq, Debug)

///|
#deprecated("Use `==` instead", skip_current_package=true)
#doc(hidden)
pub extend WebViewLifecycle with Eq::{equal, not_equal}

///|
#deprecated("Use `Debug::to_repr` instead", skip_current_package=true)
#doc(hidden)
pub extend WebViewLifecycle with Debug::{to_repr}

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
#deprecated("Use `==` instead", skip_current_package=true)
#doc(hidden)
pub extend WebViewError with Eq::{equal, not_equal}

///|
#deprecated("Use `Debug::to_repr` instead", skip_current_package=true)
#doc(hidden)
pub extend WebViewError with Debug::{to_repr}

///|
/// The decision synchronously returned to a native navigation callback.
pub(all) enum NavigationDecision {
  Allow
  Deny
} derive(Eq, Debug)

///|
#deprecated("Use `==` instead", skip_current_package=true)
#doc(hidden)
pub extend NavigationDecision with Eq::{equal, not_equal}

///|
#deprecated("Use `Debug::to_repr` instead", skip_current_package=true)
#doc(hidden)
pub extend NavigationDecision with Debug::{to_repr}

///|
/// The decision synchronously returned when page content requests a new
/// browser window. Moonview never creates a top-level native window itself.
pub(all) enum NewWindowDecision {
  /// Reject the request without creating or navigating another WebView.
  Deny
  /// Reject the new window and navigate the requesting WebView instead.
  NavigateCurrent
} derive(Eq, Debug)

///|
#deprecated("Use `==` instead", skip_current_package=true)
#doc(hidden)
pub extend NewWindowDecision with Eq::{equal, not_equal}

///|
#deprecated("Use `Debug::to_repr` instead", skip_current_package=true)
#doc(hidden)
pub extend NewWindowDecision with Debug::{to_repr}

///|
/// The native dialog operation to present for a WebView.
pub(all) enum FileDialogKind {
  OpenFile
  OpenFiles
  SaveFile
  PickDirectory
} derive(Eq, Debug)

///|
#deprecated("Use `==` instead", skip_current_package=true)
#doc(hidden)
pub extend FileDialogKind with Eq::{equal, not_equal}

///|
#deprecated("Use `Debug::to_repr` instead", skip_current_package=true)
#doc(hidden)
pub extend FileDialogKind with Debug::{to_repr}

///|
/// A user-facing name and the extensions accepted by a file dialog.
/// Extensions do not include a leading dot or wildcard.
pub(all) struct FileDialogFilter {
  name : String
  extensions : Array[String]
} derive(Eq, Debug)

///|
#deprecated("Use `==` instead", skip_current_package=true)
#doc(hidden)
pub extend FileDialogFilter with Eq::{equal, not_equal}

///|
#deprecated("Use `Debug::to_repr` instead", skip_current_package=true)
#doc(hidden)
pub extend FileDialogFilter with Debug::{to_repr}

///|
/// Options for a native file dialog owned by a WebView's native container.
pub(all) struct FileDialogOptions {
  kind : FileDialogKind
  title : String?
  filters : Array[FileDialogFilter]
  default_name : String?
  initial_directory : String?
} derive(Eq, Debug)

///|
#deprecated("Use `==` instead", skip_current_package=true)
#doc(hidden)
pub extend FileDialogOptions with Eq::{equal, not_equal}

///|
#deprecated("Use `Debug::to_repr` instead", skip_current_package=true)
#doc(hidden)
pub extend FileDialogOptions with Debug::{to_repr}

///|
/// The outcome of a native file dialog. `Cancelled` is a normal user action.
pub(all) enum FileDialogResult {
  Cancelled
  Selected(Array[String])
} derive(Eq, Debug)

///|
#deprecated("Use `==` instead", skip_current_package=true)
#doc(hidden)
pub extend FileDialogResult with Eq::{equal, not_equal}

///|
#deprecated("Use `Debug::to_repr` instead", skip_current_package=true)
#doc(hidden)
pub extend FileDialogResult with Debug::{to_repr}

///|
/// The most recently observed document URL and history availability.
pub(all) struct NavigationState {
  url : String
  can_go_back : Bool
  can_go_forward : Bool
} derive(Eq, Debug)

///|
#deprecated("Use `==` instead", skip_current_package=true)
#doc(hidden)
pub extend NavigationState with Eq::{equal, not_equal}

///|
#deprecated("Use `Debug::to_repr` instead", skip_current_package=true)
#doc(hidden)
pub extend NavigationState with Debug::{to_repr}

///|
/// A single HTTP header in a custom-scheme request or response.
pub(all) struct HttpHeader {
  name : String
  value : String
} derive(Eq, Debug)

///|
#deprecated("Use `==` instead", skip_current_package=true)
#doc(hidden)
pub extend HttpHeader with Eq::{equal, not_equal}

///|
#deprecated("Use `Debug::to_repr` instead", skip_current_package=true)
#doc(hidden)
pub extend HttpHeader with Debug::{to_repr}

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
#deprecated("Use `==` instead", skip_current_package=true)
#doc(hidden)
pub extend ProtocolRequest with Eq::{equal, not_equal}

///|
#deprecated("Use `Debug::to_repr` instead", skip_current_package=true)
#doc(hidden)
pub extend ProtocolRequest with Debug::{to_repr}

///|
/// A response to a pending custom-scheme request.
pub(all) struct ProtocolResponse {
  status : Int
  headers : Array[HttpHeader]
  body : Bytes
} derive(Eq, Debug)

///|
#deprecated("Use `==` instead", skip_current_package=true)
#doc(hidden)
pub extend ProtocolResponse with Eq::{equal, not_equal}

///|
#deprecated("Use `Debug::to_repr` instead", skip_current_package=true)
#doc(hidden)
pub extend ProtocolResponse with Debug::{to_repr}

///|
/// Per-WebView resource limits for desktop native backends. The pending-command
/// limits are enforced by Windows; the protocol request body limit is enforced
/// by Windows, macOS, and Linux.
///
/// A value of `0` disables the corresponding limit. Negative values are
/// rejected by `WebView::create`.
pub(all) struct WebViewResourceLimits {
  max_pending_commands : Int
  max_pending_command_bytes : Int
  max_protocol_request_body_bytes : Int
} derive(Eq, Debug)

///|
#deprecated("Use `==` instead", skip_current_package=true)
#doc(hidden)
pub extend WebViewResourceLimits with Eq::{equal, not_equal}

///|
#deprecated("Use `Debug::to_repr` instead", skip_current_package=true)
#doc(hidden)
pub extend WebViewResourceLimits with Debug::{to_repr}

///|
/// A media capture category requested by page content.
pub(all) enum MediaPermissionKind {
  Camera
  Microphone
  CameraAndMicrophone
  Unknown(Int)
} derive(Eq, Debug)

///|
#deprecated("Use `==` instead", skip_current_package=true)
#doc(hidden)
pub extend MediaPermissionKind with Eq::{equal, not_equal}

///|
#deprecated("Use `Debug::to_repr` instead", skip_current_package=true)
#doc(hidden)
pub extend MediaPermissionKind with Debug::{to_repr}

///|
/// A synchronous request to access local media devices from an origin.
pub(all) struct MediaPermissionRequest {
  kind : MediaPermissionKind
  origin : String
} derive(Eq, Debug)

///|
#deprecated("Use `==` instead", skip_current_package=true)
#doc(hidden)
pub extend MediaPermissionRequest with Eq::{equal, not_equal}

///|
#deprecated("Use `Debug::to_repr` instead", skip_current_package=true)
#doc(hidden)
pub extend MediaPermissionRequest with Debug::{to_repr}

///|
/// The decision synchronously returned to a native media-permission callback.
pub(all) enum MediaPermissionDecision {
  Allow
  Deny
} derive(Eq, Debug)

///|
#deprecated("Use `==` instead", skip_current_package=true)
#doc(hidden)
pub extend MediaPermissionDecision with Eq::{equal, not_equal}

///|
#deprecated("Use `Debug::to_repr` instead", skip_current_package=true)
#doc(hidden)
pub extend MediaPermissionDecision with Debug::{to_repr}

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
  /// The embedded browser process became unusable. Windows reports this for
  /// WebView2. Destroy this WebView and create a replacement explicitly;
  /// Moonview never recreates it implicitly.
  ProcessFailed(WebViewError)
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
#deprecated("Use `==` instead", skip_current_package=true)
#doc(hidden)
pub extend WebViewEvent with Eq::{equal, not_equal}

///|
#deprecated("Use `Debug::to_repr` instead", skip_current_package=true)
#doc(hidden)
pub extend WebViewEvent with Debug::{to_repr}

///|
/// Configuration passed while the native WebView is being created.
///
/// If both initial content fields are non-empty, `initial_html` takes
/// precedence. Treat the WebView as usable only after its `Ready` event.
pub(all) struct WebViewOptions {
  context : WebContext
  bounds : Rect
  resource_limits : WebViewResourceLimits
  initial_url : String
  initial_html : String
  initialization_script : String
  user_agent : String
  visible : Bool
  on_event : (WebViewEvent) -> Unit
  on_navigation : (String) -> NavigationDecision
  on_new_window : (String) -> NewWindowDecision
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
  { x, y, width, height, }
}

///|
pub fn NavigationState::new(
  url? : String = "",
  can_go_back? : Bool = false,
  can_go_forward? : Bool = false,
) -> NavigationState {
  { url, can_go_back, can_go_forward, }
}

///|
pub fn FileDialogFilter::new(
  name~ : String,
  extensions~ : Array[String],
) -> FileDialogFilter {
  { name, extensions, }
}

///|
pub fn FileDialogOptions::new(
  kind~ : FileDialogKind,
  title? : String? = None,
  filters? : Array[FileDialogFilter] = [],
  default_name? : String? = None,
  initial_directory? : String? = None,
) -> FileDialogOptions {
  { kind, title, filters, default_name, initial_directory, }
}

///|
pub fn HttpHeader::new(name~ : String, value~ : String) -> HttpHeader {
  { name, value, }
}

///|
pub fn ProtocolResponse::new(
  status~ : Int,
  headers? : Array[HttpHeader] = [],
  body? : Bytes = b"",
) -> ProtocolResponse {
  { status, headers, body, }
}

///|
pub fn WebViewResourceLimits::new(
  max_pending_commands? : Int = 256,
  max_pending_command_bytes? : Int = 4 * 1024 * 1024,
  max_protocol_request_body_bytes? : Int = 4 * 1024 * 1024,
) -> WebViewResourceLimits {
  {
    max_pending_commands,
    max_pending_command_bytes,
    max_protocol_request_body_bytes,
  }
}

///|
pub fn WebViewOptions::new(
  bounds~ : Rect,
  context? : WebContext = WebContext::persistent(),
  resource_limits? : WebViewResourceLimits = WebViewResourceLimits::new(),
  initial_url? : String = "",
  initial_html? : String = "",
  initialization_script? : String = "",
  user_agent? : String = "",
  visible? : Bool = true,
  on_event? : (WebViewEvent) -> Unit = ignore_event,
  on_navigation? : (String) -> NavigationDecision = allow_navigation,
  on_new_window? : (String) -> NewWindowDecision = deny_new_window,
  on_media_permission? : (MediaPermissionRequest) -> MediaPermissionDecision = deny_media_permission,
) -> WebViewOptions {
  {
    context,
    bounds,
    resource_limits,
    initial_url,
    initial_html,
    initialization_script,
    user_agent,
    visible,
    on_event,
    on_navigation,
    on_new_window,
    on_media_permission,
  }
}

///|
fn ignore_event(_event : WebViewEvent) -> Unit {
  ()
}

///|
fn allow_navigation(_url : String) -> NavigationDecision {
  Allow
}

///|
fn deny_new_window(_url : String) -> NewWindowDecision {
  Deny
}

///|
fn deny_media_permission(
  _request : MediaPermissionRequest,
) -> MediaPermissionDecision {
  Deny
}
