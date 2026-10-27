///|
/// The macOS backend is available when the system WKWebView framework is present.
pub extern "C" fn available() -> Int32 = "moonview_macos_available"

///|
pub extern "C" fn current_thread_token() -> UInt64 = "moonview_macos_current_thread_token"

///|
#borrow(call_closure)
#owned(callback)
pub extern "C" fn install_event_callback(
  call_closure : FuncRef[
    (
      (UInt64, Int32, Bytes, Bytes, Int32) -> Unit,
      UInt64,
      Int32,
      Bytes,
      Bytes,
      Int32,
    ) -> Unit,
  ],
  callback : (UInt64, Int32, Bytes, Bytes, Int32) -> Unit,
) -> Unit = "moonview_macos_install_event_callback"

///|
#borrow(call_closure)
#owned(callback)
pub extern "C" fn install_navigation_callback(
  call_closure : FuncRef[((UInt64, Bytes) -> Int32, UInt64, Bytes) -> Int32],
  callback : (UInt64, Bytes) -> Int32,
) -> Unit = "moonview_macos_install_navigation_callback"

///|
#borrow(call_closure)
#owned(callback)
pub extern "C" fn install_new_window_callback(
  call_closure : FuncRef[((UInt64, Bytes) -> Int32, UInt64, Bytes) -> Int32],
  callback : (UInt64, Bytes) -> Int32,
) -> Unit = "moonview_macos_install_new_window_callback"

///|
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
) -> Unit = "moonview_macos_install_protocol_callback"

///|
#borrow(call_closure)
#owned(callback)
pub extern "C" fn install_media_permission_callback(
  call_closure : FuncRef[
    ((UInt64, Int32, Bytes) -> Int32, UInt64, Int32, Bytes) -> Int32,
  ],
  callback : (UInt64, Int32, Bytes) -> Int32,
) -> Unit = "moonview_macos_install_media_permission_callback"

///|
#borrow(name)
pub extern "C" fn register_custom_scheme(name : Bytes) -> Int32 = "moonview_macos_register_custom_scheme"

///|
pub extern "C" fn lock_custom_schemes() -> Unit = "moonview_macos_lock_custom_schemes"

///|
#borrow(request_id, headers, body)
pub extern "C" fn respond_protocol(
  view : UInt64,
  request_id : Bytes,
  status : Int32,
  headers : Bytes,
  body : Bytes,
) -> Int32 = "moonview_macos_respond_protocol"

///|
/// Starts creation in a caller-owned `NSView*` container on the main thread.
#borrow(data_directory, initial_url, initial_html, initialization_script, user_agent)
pub extern "C" fn create(
  context_id : UInt64,
  ephemeral : Bool,
  data_directory : Bytes,
  parent : UInt64,
  x : Int32,
  y : Int32,
  width : Int32,
  height : Int32,
  initial_url : Bytes,
  initial_html : Bytes,
  initialization_script : Bytes,
  user_agent : Bytes,
  max_pending_commands : Int32,
  max_pending_command_bytes : Int32,
  max_protocol_request_body_bytes : Int32,
) -> UInt64 = "moonview_macos_create"

///|
pub extern "C" fn start(view : UInt64) -> Unit = "moonview_macos_start"

///|
pub extern "C" fn destroy(view : UInt64) -> Int32 = "moonview_macos_destroy"

///|
pub extern "C" fn set_bounds(
  view : UInt64,
  x : Int32,
  y : Int32,
  width : Int32,
  height : Int32,
) -> Int32 = "moonview_macos_set_bounds"

///|
pub extern "C" fn set_visible(view : UInt64, visible : Int32) -> Int32 = "moonview_macos_set_visible"

///|
pub extern "C" fn focus(view : UInt64) -> Int32 = "moonview_macos_focus"

///|
#borrow(url)
pub extern "C" fn navigate(view : UInt64, url : Bytes) -> Int32 = "moonview_macos_navigate"

///|
#borrow(html)
pub extern "C" fn load_html(view : UInt64, html : Bytes) -> Int32 = "moonview_macos_load_html"

///|
pub extern "C" fn reload(view : UInt64) -> Int32 = "moonview_macos_reload"

///|
pub extern "C" fn stop(view : UInt64) -> Int32 = "moonview_macos_stop"

///|
pub extern "C" fn go_back(view : UInt64) -> Int32 = "moonview_macos_go_back"

///|
pub extern "C" fn go_forward(view : UInt64) -> Int32 = "moonview_macos_go_forward"

///|
#borrow(script)
pub extern "C" fn add_init_script(view : UInt64, script : Bytes) -> Int32 = "moonview_macos_init"

///|
pub extern "C" fn set_zoom(view : UInt64, factor : Double) -> Int32 = "moonview_macos_set_zoom"

///|
pub extern "C" fn open_devtools(view : UInt64) -> Int32 = "moonview_macos_open_devtools"

///|
pub extern "C" fn open_print_dialog(view : UInt64) -> Int32 = "moonview_macos_open_print_dialog"

///|
#borrow(title, filters, default_name, initial_directory, status)
pub extern "C" fn show_file_dialog(
  view : UInt64,
  kind : Int32,
  title : Bytes,
  filters : Bytes,
  default_name : Bytes,
  initial_directory : Bytes,
  status : Ref[Int32],
) -> Bytes = "moonview_macos_show_file_dialog"

///|
#borrow(script, request_id)
pub extern "C" fn eval(
  view : UInt64,
  script : Bytes,
  request_id : Bytes,
) -> Int32 = "moonview_macos_eval"

///|
#borrow(message)
pub extern "C" fn post_message(view : UInt64, message : Bytes) -> Int32 = "moonview_macos_post_message"
