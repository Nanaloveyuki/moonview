///|
/// The macOS backend is available when the system WKWebView framework is present.
pub extern "C" fn available() -> Int = "moonview_macos_available"

///|
#borrow(call_closure)
#owned(callback)
pub extern "C" fn install_event_callback(
  call_closure : FuncRef[
    ((UInt64, Int, Bytes, Bytes, Int) -> Unit, UInt64, Int, Bytes, Bytes, Int) -> Unit,
  ],
  callback : (UInt64, Int, Bytes, Bytes, Int) -> Unit,
) -> Unit = "moonview_macos_install_event_callback"

///|
#borrow(call_closure)
#owned(callback)
pub extern "C" fn install_navigation_callback(
  call_closure : FuncRef[((UInt64, Bytes) -> Int, UInt64, Bytes) -> Int],
  callback : (UInt64, Bytes) -> Int,
) -> Unit = "moonview_macos_install_navigation_callback"

///|
/// Starts creation in a caller-owned `NSView*` container on the main thread.
#borrow(initial_url, initial_html, initialization_script, user_agent)
pub extern "C" fn create(
  parent : UInt64,
  x : Int,
  y : Int,
  width : Int,
  height : Int,
  initial_url : Bytes,
  initial_html : Bytes,
  initialization_script : Bytes,
  user_agent : Bytes,
) -> UInt64 = "moonview_macos_create"

///|
pub extern "C" fn start(view : UInt64) -> Unit = "moonview_macos_start"

///|
pub extern "C" fn destroy(view : UInt64) -> Int = "moonview_macos_destroy"

///|
pub extern "C" fn set_bounds(
  view : UInt64,
  x : Int,
  y : Int,
  width : Int,
  height : Int,
) -> Unit = "moonview_macos_set_bounds"

///|
pub extern "C" fn set_visible(view : UInt64, visible : Int) -> Unit = "moonview_macos_set_visible"

///|
pub extern "C" fn focus(view : UInt64) -> Unit = "moonview_macos_focus"

///|
#borrow(url)
pub extern "C" fn navigate(view : UInt64, url : Bytes) -> Unit = "moonview_macos_navigate"

///|
#borrow(html)
pub extern "C" fn load_html(view : UInt64, html : Bytes) -> Unit = "moonview_macos_load_html"

///|
pub extern "C" fn reload(view : UInt64) -> Unit = "moonview_macos_reload"

///|
pub extern "C" fn stop(view : UInt64) -> Unit = "moonview_macos_stop"

///|
pub extern "C" fn go_back(view : UInt64) -> Unit = "moonview_macos_go_back"

///|
pub extern "C" fn go_forward(view : UInt64) -> Unit = "moonview_macos_go_forward"

///|
#borrow(script)
pub extern "C" fn add_init_script(view : UInt64, script : Bytes) -> Unit = "moonview_macos_init"

///|
pub extern "C" fn set_zoom(view : UInt64, factor : Double) -> Unit = "moonview_macos_set_zoom"

///|
pub extern "C" fn open_devtools(view : UInt64) -> Int = "moonview_macos_open_devtools"

///|
#borrow(script, request_id)
pub extern "C" fn eval(
  view : UInt64,
  script : Bytes,
  request_id : Bytes,
) -> Unit = "moonview_macos_eval"

///|
#borrow(message)
pub extern "C" fn post_message(view : UInt64, message : Bytes) -> Unit = "moonview_macos_post_message"
