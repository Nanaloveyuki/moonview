///|
/// A pixel rectangle relative to the parent Win32 window client area.
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
/// Failures reported before or during WebView2 creation, or after disposal.
pub(all) enum WebViewError {
  Unavailable
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
/// Events emitted from the WebView2 UI thread.
///
/// `ScriptResult` and `ScriptFailed` preserve the request identifier supplied
/// to `WebView::eval`. Messages are UTF-8 strings without an imposed protocol.
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
/// precedence. Commands invoked before `Ready` are queued by the native host.
pub(all) struct WebViewOptions {
  bounds : Rect
  initial_url : String
  initial_html : String
  initialization_script : String
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
  visible? : Bool = true,
  on_event? : (WebViewEvent) -> Unit = ignore_event,
  on_navigation? : (String) -> NavigationDecision = allow_navigation,
) -> WebViewOptions {
  {
    bounds,
    initial_url,
    initial_html,
    initialization_script,
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
