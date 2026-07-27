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
/// Failures reported before or during native WebView creation, or after disposal.
pub(all) enum WebViewError {
  Unavailable
  Unsupported(String)
  CreateRejected
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
} derive(Eq, Debug)

///|
/// Configuration passed while the native WebView is being created.
///
/// If both initial content fields are non-empty, `initial_html` takes
/// precedence. Treat the WebView as usable only after its `Ready` event.
pub(all) struct WebViewOptions {
  bounds : Rect
  initial_url : String
  initial_html : String
  initialization_script : String
  user_agent : String
  visible : Bool
  on_event : (WebViewEvent) -> Unit
  on_navigation : (String) -> NavigationDecision
}

///|
pub fn Rect::new(x~ : Int, y~ : Int, width~ : Int, height~ : Int) -> Rect {
  { x, y, width, height }
}

///|
pub fn WebViewOptions::new(
  bounds~ : Rect,
  initial_url? : String = "",
  initial_html? : String = "",
  initialization_script? : String = "",
  user_agent? : String = "",
  visible? : Bool = true,
  on_event? : (WebViewEvent) -> Unit = ignore_event,
  on_navigation? : (String) -> NavigationDecision = allow_navigation,
) -> WebViewOptions {
  {
    bounds,
    initial_url,
    initial_html,
    initialization_script,
    user_agent,
    visible,
    on_event,
    on_navigation,
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
