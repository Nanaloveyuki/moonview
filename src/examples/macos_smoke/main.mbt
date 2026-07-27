///|
extern "C" fn create_host(width : Int, height : Int) -> UInt64 = "moonview_macos_smoke_create_host"

///|
extern "C" fn run_loop() -> Int = "moonview_macos_smoke_run_loop"

///|
extern "C" fn succeed() -> Unit = "moonview_macos_smoke_succeed"

///|
extern "C" fn destroy_host() -> Unit = "moonview_macos_smoke_destroy_host"

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
      #|<!doctype html><title>moonview macOS smoke</title><script>
      #|window.moonview.onmessage = event => {
      #|  if (event.data === 'host-ping') window.moonview.postMessage('page-ack');
      #|};
      #|window.moonview.postMessage('page-ready');
      #|</script>
    ),
    initialization_script="window.__moonview_initialized = true;",
    user_agent="moonview-smoke/0.1",
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
    @moonview.WebViewEvent::Ready => println("moonview macOS smoke: ready")
    @moonview.WebViewEvent::PageMessage("page-ready") => self.post_ping()
    @moonview.WebViewEvent::PageMessage("page-ack") => self.evaluate()
    @moonview.WebViewEvent::ScriptResult(request_id, value) =>
      if request_id == "answer" && value == "[\"moonview-smoke/0.1\",42]" {
        self.set_zoom()
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
    Some(view) => ignore(view.eval("[navigator.userAgent, 40 + 2]", "answer"))
    None => ()
  }
}

///|
fn Smoke::set_zoom(self : Smoke) -> Unit {
  match self.view {
    Some(view) => ignore(view.set_zoom_factor(1.25))
    None => ()
  }
}

///|
fn Smoke::finish(self : Smoke) -> Unit {
  if !self.passed {
    self.passed = true
    println("moonview macOS smoke: passed")
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
    abort("moonview macOS smoke: unable to create AppKit host")
  }
  let smoke = { view: None, passed: false }
  smoke.start(parent_handle)
  if run_loop() != 0 || !smoke.passed {
    abort("moonview macOS smoke: failed")
  }
  destroy_host()
}
