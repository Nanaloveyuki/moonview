///|
extern "C" fn create_host(width : Int, height : Int) -> UInt64 = "moonview_macos_smoke_create_host"

///|
extern "C" fn run_loop() -> Int = "moonview_macos_smoke_run_loop"

///|
extern "C" fn finish(success : Int) -> Unit = "moonview_macos_smoke_finish"

///|
extern "C" fn destroy_host() -> Unit = "moonview_macos_smoke_destroy_host"

///|
fn main {
  let parent_handle = create_host(640, 480)
  if parent_handle == 0UL {
    abort("moonview macOS contract: unable to create AppKit host")
  }
  let contract = @contract.Contract::new(success => {
    finish(if success { 1 } else { 0 })
  })
  match contract.start(parent_handle) {
    Ok(_) => ()
    Err(_error) => {
      println("moonview macOS contract: create rejected")
      finish(0)
    }
  }
  let status = run_loop()
  destroy_host()
  if status != 0 || !contract.passed() {
    abort("moonview macOS contract failed")
  }
}
