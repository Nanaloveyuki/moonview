///|
/// A pixel rectangle inside the Kotlin host's attached `FrameLayout`.
pub(all) struct AndroidBounds {
  x : Int
  y : Int
  width : Int
  height : Int
} derive(Eq, Debug)

///|
/// Events available through the optional Android WebView adapter.
pub(all) enum AndroidWebViewEvent {
  Ready
  NavigationStarting(String)
  SourceChanged(String)
  NavigationCompleted(String)
  TitleChanged(String)
  ScriptResult(String, String)
  Failed(String)
  Destroyed
} derive(Eq, Debug)

///|
/// Options for a WebView owned by ajni's attached Android host.
pub(all) struct AndroidWebViewOptions {
  bounds : AndroidBounds
  initial_url : String
  initial_html : String
  on_event : (AndroidWebViewEvent) -> Unit
}

///|
pub fn AndroidBounds::new(
  x~ : Int,
  y~ : Int,
  width~ : Int,
  height~ : Int,
) -> AndroidBounds {
  { x, y, width, height }
}

///|
pub fn AndroidWebViewOptions::new(
  bounds~ : AndroidBounds,
  initial_url? : String = "",
  initial_html? : String = "",
  on_event? : (AndroidWebViewEvent) -> Unit = ignore_event,
) -> AndroidWebViewOptions {
  { bounds, initial_url, initial_html, on_event }
}

///|
fn ignore_event(_event : AndroidWebViewEvent) -> Unit {
  ()
}
