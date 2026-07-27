///| The Windows backend is available when the installed WebView2 Runtime can

///|
/// be located by the WebView2 loader.
pub extern "C" fn available() -> Int = "moonview_windows_available"

///| Installs the process-wide event listener. Replacing it releases the prior

///| owned MoonBit closure.

///|

///|
/// Event callback arguments are `(view, kind, value, detail, code)`.
#borrow(call_closure)
#owned(callback)
pub extern "C" fn install_event_callback(
  call_closure : FuncRef[
    ((UInt64, Int, Bytes, Bytes, Int) -> Unit, UInt64, Int, Bytes, Bytes, Int) -> Unit,
  ],
  callback : (UInt64, Int, Bytes, Bytes, Int) -> Unit,
) -> Unit = "moonview_windows_install_event_callback"

///| Installs the synchronous navigation gate. A nonzero return value allows

///| the navigation; zero cancels it. With no callback installed, navigation is

///|
/// allowed.
#borrow(call_closure)
#owned(callback)
pub extern "C" fn install_navigation_callback(
  call_closure : FuncRef[((UInt64, Bytes) -> Int, UInt64, Bytes) -> Int],
  callback : (UInt64, Bytes) -> Int,
) -> Unit = "moonview_windows_install_navigation_callback"

///| Protocol callback arguments are `(view, request_id, scheme, method, uri,

///|
/// headers, body)`. Headers use moonview's binary header envelope.
#borrow(call_closure)
#owned(callback)
pub extern "C" fn install_protocol_callback(
  call_closure : FuncRef[
    (
      (UInt64, Bytes, Bytes, Bytes, Bytes, Bytes, Bytes) -> Unit,
      UInt64,
      Bytes,
      Bytes,
      Bytes,
      Bytes,
      Bytes,
      Bytes,
    ) -> Unit,
  ],
  callback : (UInt64, Bytes, Bytes, Bytes, Bytes, Bytes, Bytes) -> Unit,
) -> Unit = "moonview_windows_install_protocol_callback"

///| Receives media permission requests. Only a return value of `1` allows a

///|
/// request; the native default is deny.
#borrow(call_closure)
#owned(callback)
pub extern "C" fn install_media_permission_callback(
  call_closure : FuncRef[
    ((UInt64, Int, Bytes) -> Int, UInt64, Int, Bytes) -> Int,
  ],
  callback : (UInt64, Int, Bytes) -> Int,
) -> Unit = "moonview_windows_install_media_permission_callback"

///| Registers a secure custom scheme with an authority component. Schemes can

///|
/// only be registered before the first WebView2 environment is created.
#borrow(name)
pub extern "C" fn register_custom_scheme(name : Bytes) -> Int = "moonview_windows_register_custom_scheme"

///|
/// Prevents subsequent custom-scheme registrations.
pub extern "C" fn lock_custom_schemes() -> Unit = "moonview_windows_lock_custom_schemes"

///| Completes a deferred custom-scheme request. `headers` uses moonview's

///|
/// binary header envelope and `body` is returned without text conversion.
#borrow(request_id, headers, body)
pub extern "C" fn respond_protocol(
  view : UInt64,
  request_id : Bytes,
  status : Int,
  headers : Bytes,
  body : Bytes,
) -> Int = "moonview_windows_respond_protocol"

///| Starts asynchronous WebView2 creation for the caller-owned parent HWND.

///| `url` and `html` are optional UTF-8 initial documents; non-empty `html`

///|
/// takes precedence over `url`.
#borrow(url, html, initialization_script, user_agent)
pub extern "C" fn create(
  hwnd : UInt64,
  x : Int,
  y : Int,
  width : Int,
  height : Int,
  url : Bytes,
  html : Bytes,
  initialization_script : Bytes,
  user_agent : Bytes,
) -> UInt64 = "moonview_windows_create"

///|
/// Begins asynchronous WebView2 creation after callback registration.
pub extern "C" fn start(view : UInt64) -> Unit = "moonview_windows_start"

///|
pub extern "C" fn destroy(view : UInt64) -> Int = "moonview_windows_destroy"

///|
pub extern "C" fn set_bounds(
  view : UInt64,
  x : Int,
  y : Int,
  width : Int,
  height : Int,
) -> Int = "moonview_windows_set_bounds"

///|
pub extern "C" fn set_visible(view : UInt64, visible : Int) -> Int = "moonview_windows_set_visible"

///|
pub extern "C" fn focus(view : UInt64) -> Int = "moonview_windows_focus"

///|
#borrow(url)
pub extern "C" fn navigate(view : UInt64, url : Bytes) -> Int = "moonview_windows_navigate"

///|
#borrow(html)
pub extern "C" fn load_html(view : UInt64, html : Bytes) -> Int = "moonview_windows_load_html"

///|
pub extern "C" fn reload(view : UInt64) -> Int = "moonview_windows_reload"

///|
pub extern "C" fn stop(view : UInt64) -> Int = "moonview_windows_stop"

///|
pub extern "C" fn go_back(view : UInt64) -> Int = "moonview_windows_go_back"

///|
pub extern "C" fn go_forward(view : UInt64) -> Int = "moonview_windows_go_forward"

///|
#borrow(script)
pub extern "C" fn add_init_script(view : UInt64, script : Bytes) -> Int = "moonview_windows_init"

///|
pub extern "C" fn set_zoom(view : UInt64, factor : Double) -> Int = "moonview_windows_set_zoom"

///|
pub extern "C" fn open_devtools(view : UInt64) -> Int = "moonview_windows_open_devtools"

///|
pub extern "C" fn open_print_dialog(view : UInt64) -> Int = "moonview_windows_open_print_dialog"

///|
#borrow(script, request_id)
pub extern "C" fn eval(
  view : UInt64,
  script : Bytes,
  request_id : Bytes,
) -> Int = "moonview_windows_eval"

///|
#borrow(message)
pub extern "C" fn post_message(view : UInt64, message : Bytes) -> Int = "moonview_windows_post_message"
