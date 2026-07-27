///|
extern "C" fn create_host_window(width : Int, height : Int) -> UInt64 = "moonview_smoke_create_host_window"

///|
extern "C" fn run_host_message_loop() -> Int = "moonview_smoke_run_host_message_loop"

///|
extern "C" fn close_host_window() -> Unit = "moonview_smoke_close_host_window"

///|
extern "C" fn destroy_host_window() -> Unit = "moonview_smoke_destroy_host_window"

///|
struct Smoke {
  mut view : @moonview.WebView?
  mut succeeded : Bool
}

///|
fn Smoke::start(self : Smoke, hwnd : UInt64) -> Unit {
  let options = @moonview.WebViewOptions::new(
    bounds=@moonview.Rect::new(x=0, y=0, width=640, height=480),
    initial_url="moonview://app/index.html",
    initialization_script=(
      #|window.moonview.onmessage = function (message) {
      #|  if (message === "host-ping") window.moonview.postMessage("page-ack");
      #|};
    ),
    user_agent="moonview-smoke/0.1",
    on_event=event => self.handle_event(event),
    on_navigation=_url => @moonview.NavigationDecision::Allow,
  )
  match @moonview.WebView::create(hwnd, options) {
    Ok(view) => self.view = Some(view)
    Err(_error) => {
      println("moonview smoke: create rejected")
      close_host_window()
    }
  }
}

///|
fn Smoke::handle_event(self : Smoke, event : @moonview.WebViewEvent) -> Unit {
  match event {
    @moonview.WebViewEvent::Ready => println("moonview smoke: ready")
    @moonview.WebViewEvent::ProtocolRequest(request) =>
      self.respond_protocol(request)
    @moonview.WebViewEvent::PageMessage("page-ready") => self.post_ping()
    @moonview.WebViewEvent::PageMessage("page-ack") => self.evaluate()
    @moonview.WebViewEvent::ScriptResult(request_id, value) => {
      if request_id == "smoke-eval" && value == "[\"moonview-smoke/0.1\",42]" {
        self.set_zoom()
        self.succeeded = true
        println("moonview smoke: passed")
      } else {
        println(
          "moonview smoke: unexpected script result \{request_id} \{value}",
        )
      }
      close_host_window()
    }
    @moonview.WebViewEvent::CreationFailed(_error) => {
      println("moonview smoke: creation failed")
      close_host_window()
    }
    @moonview.WebViewEvent::ScriptFailed(request_id, _error) => {
      println("moonview smoke: script failed \{request_id}")
      close_host_window()
    }
    @moonview.WebViewEvent::NavigationFailed(url, _error) => {
      println("moonview smoke: navigation failed \{url}")
      close_host_window()
    }
    _ => ()
  }
}

///|
fn Smoke::respond_protocol(
  self : Smoke,
  request : @moonview.ProtocolRequest,
) -> Unit {
  match self.view {
    Some(view) =>
      ignore(
        view.respond_protocol(
          request.id,
          @moonview.ProtocolResponse::new(
            status=200,
            headers=[
              @moonview.HttpHeader::new(name="Content-Type", value="text/html"),
            ],
            body=@utf8.encode(
              (
                #|<!doctype html>
                #|<meta charset="utf-8">
                #|<title>moonview smoke</title>
                #|<script>
                #|  window.addEventListener("DOMContentLoaded", () => {
                #|    window.moonview.postMessage("page-ready");
                #|  });
                #|</script>
                #|<body>moonview smoke</body>
              )[:],
              bom=false,
            ),
          ),
        ),
      )
    None => ()
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
    Some(view) =>
      ignore(view.eval("[navigator.userAgent, 40 + 2]", "smoke-eval"))
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
fn Smoke::dispose(self : Smoke) -> Unit {
  match self.view {
    Some(view) => ignore(view.destroy())
    None => ()
  }
  self.view = None
}

///|
fn main {
  match @moonview.register_custom_scheme("moonview") {
    Ok(_) => ()
    Err(_) => abort("moonview smoke: scheme registration failed")
  }
  let smoke = { view: None, succeeded: false }
  let hwnd = create_host_window(640, 480)
  if hwnd == 0UL {
    abort("moonview smoke: unable to create Win32 host window")
  }
  smoke.start(hwnd)
  ignore(run_host_message_loop())
  smoke.dispose()
  destroy_host_window()
  if !smoke.succeeded {
    abort("moonview smoke failed")
  }
}
