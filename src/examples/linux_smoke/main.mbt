///|
extern "C" fn create_host(width : Int, height : Int) -> UInt64 = "moonview_linux_smoke_create_host"

///|
extern "C" fn run_loop() -> Int = "moonview_linux_smoke_run_loop"

///|
extern "C" fn succeed() -> Unit = "moonview_linux_smoke_succeed"

///|
struct Smoke {
  mut view : @moonview.WebView?
  mut passed : Bool
}

///|
fn Smoke::start(self : Smoke, parent_handle : UInt64) -> Unit {
  let options = @moonview.WebViewOptions::new(
    bounds=@moonview.Rect::new(x=0, y=0, width=640, height=480),
    initial_html=(
      #|<!doctype html><title>moonview GTK smoke</title><script>
      #|window.moonview.onmessage = event => {
      #|  if (event.data === 'host-ping') window.moonview.postMessage('page-ack');
      #|};
      #|window.moonview.postMessage('page-ready');
      #|</script>
    ),
    initialization_script="window.__moonview_initialized = true;",
    on_event=event => self.handle_event(event),
    on_navigation=_url => @moonview.NavigationDecision::Allow,
  )
  match @moonview.WebView::create(parent_handle, options) {
    Ok(view) => self.view = Some(view)
    Err(_error) => ()
  }
}

///|
fn Smoke::handle_event(self : Smoke, event : @moonview.WebViewEvent) -> Unit {
  match event {
    @moonview.WebViewEvent::Ready => println("moonview linux smoke: ready")
    @moonview.WebViewEvent::PageMessage("page-ready") => self.post_ping()
    @moonview.WebViewEvent::PageMessage("page-ack") => self.evaluate()
    @moonview.WebViewEvent::ScriptResult(request_id, value) =>
      if request_id == "answer" && value == "42" {
        self.finish()
      }
    @moonview.WebViewEvent::CreationFailed(_error) => ()
    @moonview.WebViewEvent::ScriptFailed(_request_id, _error) => ()
    _ => ()
  }
}

///|
fn Smoke::post_ping(self : Smoke) -> Unit {
  match self.view {
    Some(view) => ignore(view.post_message("host-ping"))
    None => ()
  }
}

///|
fn Smoke::evaluate(self : Smoke) -> Unit {
  match self.view {
    Some(view) => ignore(view.eval("40 + 2", "answer"))
    None => ()
  }
}

///|
fn Smoke::finish(self : Smoke) -> Unit {
  if !self.passed {
    self.passed = true
    println("moonview linux smoke: passed")
    match self.view {
      Some(view) => ignore(view.destroy())
      None => ()
    }
    succeed()
  }
}

///|
fn main {
  let parent_handle = create_host(640, 480)
  if parent_handle == 0UL {
    abort("moonview linux smoke: unable to create GTK host")
  }
  let smoke = { view: None, passed: false }
  smoke.start(parent_handle)
  if run_loop() != 0 || !smoke.passed {
    abort("moonview linux smoke: failed")
  }
}
