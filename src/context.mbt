///|
/// The persistence policy for browser data owned by a WebContext.
pub(all) enum WebContextStorage {
  Persistent
  Ephemeral
} derive(Eq, Debug)

///|
/// A browser-data context that can be shared by multiple WebViews.
pub(all) struct WebContext {
  priv id : UInt64
  priv storage : WebContextStorage
  priv data_directory : String
} derive(Eq, Debug)

///|
let next_context_id : Ref[UInt64] = Ref(1UL)

///|
let persistent_context_ids : Map[String, UInt64] = Map([])

///|
/// Creates a persistent context. A non-empty `data_directory` is supported on
/// Windows and Linux; macOS rejects it rather than silently using another path.
pub fn WebContext::persistent(data_directory? : String = "") -> WebContext {
  if data_directory.length() == 0 {
    { id: 0UL, storage: Persistent, data_directory }
  } else {
    let id = match persistent_context_ids.get(data_directory) {
      Some(id) => id
      None => {
        let id = next_context_id.val
        next_context_id.val = id + 1UL
        persistent_context_ids.set(data_directory, id)
        id
      }
    }
    { id, storage: Persistent, data_directory }
  }
}

///|
/// Creates an isolated, non-persistent context.
///
/// This is supported by WKWebView and WebKitGTK. WebView2 currently rejects
/// this mode because it does not expose a compatible cross-platform profile.
pub fn WebContext::ephemeral() -> WebContext {
  let id = next_context_id.val
  next_context_id.val = id + 1UL
  { id, storage: Ephemeral, data_directory: "" }
}
