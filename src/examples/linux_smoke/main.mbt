///|
extern "C" fn create_host(width : Int, height : Int) -> UInt64 = "moonview_linux_smoke_create_host"

///|
extern "C" fn run_loop() -> Int = "moonview_linux_smoke_run_loop"

///|
extern "C" fn finish(success : Int) -> Unit = "moonview_linux_smoke_finish"

///|
fn main {
  let parent_handle = create_host(640, 480)
  if parent_handle == 0UL {
    abort("moonview Linux contract: unable to create GTK host")
  }
  let contract = @contract.Contract::new(success => {
    finish(if success { 1 } else { 0 })
  })
  match contract.start(parent_handle) {
    Ok(_) => ()
    Err(_error) => {
      println("moonview Linux contract: create rejected")
      finish(0)
    }
  }
  if run_loop() != 0 || !contract.passed() {
    abort("moonview Linux contract failed")
  }
}
