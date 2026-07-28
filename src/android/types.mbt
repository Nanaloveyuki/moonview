///|
/// A pixel rectangle inside the Kotlin host's attached `FrameLayout`.
pub(all) struct AndroidBounds {
  x : Int
  y : Int
  width : Int
  height : Int
} derive(Eq, Debug)

///|
/// The exclusive initial document for an Android WebView.
pub(all) enum AndroidInitialContent {
  Empty
  Url(String)
  Html(String, String)
} derive(Eq, Debug)

///|
/// A single HTTP-style header used for Android asset responses.
pub(all) struct AndroidHeader {
  name : String
  value : String
} derive(Eq, Debug)

///|
/// A page message accepted only from the WebView's configured trusted origin.
pub(all) struct AndroidPageMessage {
  body : String
  origin : String
  is_main_frame : Bool
} derive(Eq, Debug)

///|
/// A pending request for a resource under the configured Android asset origin.
pub(all) struct AndroidAssetRequest {
  id : String
  path : String
} derive(Eq, Debug)

///|
/// A response for an `AndroidAssetRequest`.
pub(all) struct AndroidAssetResponse {
  status : Int
  mime_type : String
  encoding : String
  headers : Array[AndroidHeader]
  body : Bytes
} derive(Eq, Debug)

///|
/// Per-WebView limits enforced by the Android Kotlin host.
///
/// A value of `0` disables its corresponding limit. Negative values are
/// rejected before the native host is called.
pub(all) struct AndroidResourceLimits {
  max_page_message_bytes : Int
  max_pending_asset_requests : Int
  max_asset_response_bytes : Int
  asset_response_timeout_millis : Int
} derive(Eq, Debug)

///|
/// The observable lifecycle of an asynchronously-created Android WebView.
pub(all) enum AndroidWebViewLifecycle {
  Creating
  Ready
  Failed(String)
  Destroyed
} derive(Eq, Debug)

///|
/// Events available through the optional Android WebView adapter.
pub(all) enum AndroidWebViewEvent {
  Ready
  CreationFailed(String, String)
  NavigationStarting(String)
  SourceChanged(String)
  NavigationCompleted(String)
  TitleChanged(String)
  ScriptResult(String, String)
  PageMessage(AndroidPageMessage)
  AssetRequest(AndroidAssetRequest)
  OperationFailed(String, String)
  Destroyed
} derive(Eq, Debug)

///|
/// Options for a WebView owned by ajni's attached Android host.
///
/// `trusted_origin` must be one HTTPS origin. Document-start scripts are
/// installed before `initial_content` is navigated.
pub(all) struct AndroidWebViewOptions {
  bounds : AndroidBounds
  trusted_origin : String
  initial_content : AndroidInitialContent
  document_start_scripts : Array[String]
  resource_limits : AndroidResourceLimits
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
pub fn AndroidHeader::new(name~ : String, value~ : String) -> AndroidHeader {
  { name, value }
}

///|
pub fn AndroidAssetResponse::new(
  status~ : Int,
  mime_type~ : String,
  encoding? : String = "utf-8",
  headers? : Array[AndroidHeader] = [],
  body? : Bytes = b"",
) -> AndroidAssetResponse {
  { status, mime_type, encoding, headers, body }
}

///|
pub fn AndroidResourceLimits::new(
  max_page_message_bytes? : Int = 1024 * 1024,
  max_pending_asset_requests? : Int = 32,
  max_asset_response_bytes? : Int = 8 * 1024 * 1024,
  asset_response_timeout_millis? : Int = 10 * 1000,
) -> AndroidResourceLimits {
  {
    max_page_message_bytes,
    max_pending_asset_requests,
    max_asset_response_bytes,
    asset_response_timeout_millis,
  }
}

///|
pub fn AndroidWebViewOptions::new(
  bounds~ : AndroidBounds,
  trusted_origin~ : String,
  initial_content? : AndroidInitialContent = Empty,
  document_start_scripts? : Array[String] = [],
  resource_limits? : AndroidResourceLimits = AndroidResourceLimits::new(),
  on_event? : (AndroidWebViewEvent) -> Unit = ignore_event,
) -> AndroidWebViewOptions {
  {
    bounds,
    trusted_origin,
    initial_content,
    document_start_scripts,
    resource_limits,
    on_event,
  }
}

///|
fn ignore_event(_event : AndroidWebViewEvent) -> Unit {
  ()
}
