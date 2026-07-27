///|
pub extern "C" fn available() -> Int = "moonview_ohos_available"

///|
#borrow(call_closure)
#owned(callback)
pub extern "C" fn install_event_callback(
  call_closure : FuncRef[
    ((UInt64, Int, Bytes, Bytes, Int) -> Unit, UInt64, Int, Bytes, Bytes, Int) -> Unit,
  ],
  callback : (UInt64, Int, Bytes, Bytes, Int) -> Unit,
) -> Unit = "moonview_ohos_install_event_callback"

///|
#borrow(call_closure)
#owned(callback)
pub extern "C" fn install_navigation_callback(
  call_closure : FuncRef[((UInt64, Bytes) -> Int, UInt64, Bytes) -> Int],
  callback : (UInt64, Bytes) -> Int,
) -> Unit = "moonview_ohos_install_navigation_callback"

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
) -> Unit = "moonview_ohos_install_protocol_callback"

///|
#borrow(call_closure)
#owned(callback)
pub extern "C" fn install_media_permission_callback(
  call_closure : FuncRef[
    ((UInt64, Int, Bytes) -> Int, UInt64, Int, Bytes) -> Int,
  ],
  callback : (UInt64, Int, Bytes) -> Int,
) -> Unit = "moonview_ohos_install_media_permission_callback"

///|
#borrow(web_tag)
pub extern "C" fn attach(web_tag : Bytes) -> UInt64 = "moonview_ohos_attach"

///|
pub extern "C" fn start(view : UInt64) -> Unit = "moonview_ohos_start"

///|
pub extern "C" fn destroy(view : UInt64) -> Int = "moonview_ohos_destroy"

///|
pub extern "C" fn reload(view : UInt64) -> Unit = "moonview_ohos_reload"

///|
#borrow(script)
pub extern "C" fn eval(view : UInt64, script : Bytes) -> Unit = "moonview_ohos_eval"
