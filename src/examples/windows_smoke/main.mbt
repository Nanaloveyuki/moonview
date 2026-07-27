///|
extern "C" fn create_host_window(width : Int, height : Int) -> UInt64 = "moonview_smoke_create_host_window"

///|
extern "C" fn run_host_message_loop() -> Int = "moonview_smoke_run_host_message_loop"

///|
extern "C" fn finish(success : Int) -> Unit = "moonview_smoke_finish"

///|
extern "C" fn destroy_host_window() -> Unit = "moonview_smoke_destroy_host_window"

///|
fn main {
  let hwnd = create_host_window(640, 480)
  if hwnd == 0UL {
    abort("moonview Windows contract: unable to create host window")
  }
  let contract = @contract.Contract::new(success => {
    finish(if success { 1 } else { 0 })
  })
  match contract.start(@moonview.WebContext::persistent(), hwnd) {
    Ok(_) => ()
    Err(_error) => {
      println("moonview Windows contract: create rejected")
      finish(0)
    }
  }
  let status = run_host_message_loop()
  destroy_host_window()
  if status != 0 || !contract.passed() {
    abort("moonview Windows contract failed")
  }
}
