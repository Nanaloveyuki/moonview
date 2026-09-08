///|
/// Shared native smoke contract for the desktop WebView backends.
pub struct Contract {
  mut view : @moonview.WebView?
  mut completed : Bool
  mut passed : Bool
  mut ready : Bool
  mut file_dialog_smoke : Bool
  require_message_source : Bool
  finish : (Bool) -> Unit
}

///|
pub fn Contract::new(
  finish : (Bool) -> Unit,
  require_message_source? : Bool = false,
) -> Contract {
  {
    view: None,
    completed: false,
    passed: false,
    ready: false,
    file_dialog_smoke: false,
    require_message_source,
    finish,
  }
}

///|
/// Enables one native file-dialog operation after the WebView becomes ready.
/// This is intended for interactive platform smoke testing only.
pub fn Contract::enable_file_dialog_smoke(self : Contract) -> Unit {
  self.file_dialog_smoke = true
}

///|
pub fn Contract::start(
  self : Contract,
  context : @moonview.WebContext,
  parent_handle : UInt64,
) -> Result[Unit, @moonview.WebViewError] {
  match @moonview.register_custom_scheme("moonview") {
    Err(error) => Err(error)
    Ok(_) => {
      let options = @moonview.WebViewOptions::new(
        bounds=@moonview.Rect::new(x=0, y=0, width=640, height=480),
        initial_url="moonview://app/index.html",
        initialization_script=(
          #|window.__moonview_initialized = true;
          #|window.moonview.onmessage = event => {
          #|  if (event && event.data === "host-ping") {
          #|    window.moonview.postMessage("page-ack");
          #|  }
          #|};
        ),
        user_agent="moonview-smoke/0.1",
        on_event=event => self.handle_event(event),
        on_navigation=_url => @moonview.NavigationDecision::Allow,
      )
      match
        @moonview.WebView::create_in_context(context, parent_handle, options) {
        Ok(view) => {
          self.view = Some(view)
          Ok(())
        }
        Err(error) => Err(error)
      }
    }
  }
}

///|
pub fn Contract::passed(self : Contract) -> Bool {
  self.passed
}

///|
fn Contract::handle_event(
  self : Contract,
  event : @moonview.WebViewEvent,
) -> Unit {
  if event is @moonview.WebViewEvent::PageMessage(_) &&
    self.require_message_source {
    if self.view.bind(view => view.page_message_source()) !=
      Some("moonview://app/index.html") {
      self.complete(false)
      return
    }
  }
  match event {
    @moonview.WebViewEvent::Ready => self.ready = true
    @moonview.WebViewEvent::ProtocolRequest(request) =>
      self.respond_protocol(request)
    @moonview.WebViewEvent::PageMessage("page-ready") =>
      if self.file_dialog_smoke {
        self.show_file_dialog_smoke()
      } else {
        self.post_ping()
      }
    @moonview.WebViewEvent::PageMessage("page-ack") => self.evaluate()
    @moonview.WebViewEvent::ScriptResult(request_id, value) =>
      if request_id == "contract-eval" &&
        value == "[true,\"moonview-smoke/0.1\",42]" &&
        self.ready {
        self.complete_success()
      } else {
        self.complete(false)
      }
    @moonview.WebViewEvent::CreationFailed(_) => self.complete(false)
    @moonview.WebViewEvent::ScriptFailed(_, _) => self.complete(false)
    @moonview.WebViewEvent::NavigationFailed(_, _) => self.complete(false)
    _ => ()
  }
}

///|
fn Contract::show_file_dialog_smoke(self : Contract) -> Unit {
  match self.view {
    Some(view) =>
      match
        view.show_file_dialog(
          @moonview.FileDialogOptions::new(
            kind=@moonview.FileDialogKind::OpenFile,
            title=Some("MoonView file dialog smoke"),
            filters=[
              @moonview.FileDialogFilter::new(name="MoonBit source", extensions=[
                "mbt",
              ]),
            ],
          ),
        ) {
        Ok(@moonview.FileDialogResult::Cancelled) => self.post_ping()
        Ok(@moonview.FileDialogResult::Selected(paths)) if !paths.is_empty() =>
          self.post_ping()
        _ => self.complete(false)
      }
    None => self.complete(false)
  }
}

///|
fn Contract::respond_protocol(
  self : Contract,
  request : @moonview.ProtocolRequest,
) -> Unit {
  match self.view {
    Some(view) =>
      match
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
                #|<title>moonview contract</title>
                #|<script>window.moonview.postMessage("page-ready");</script>
              )[:],
              bom=false,
            ),
          ),
        ) {
        Ok(_) => ()
        Err(_) => self.complete(false)
      }
    None => self.complete(false)
  }
}

///|
fn Contract::post_ping(self : Contract) -> Unit {
  match self.view {
    Some(view) =>
      match view.post_message("host-ping") {
        Ok(_) => ()
        Err(_) => self.complete(false)
      }
    None => self.complete(false)
  }
}

///|
fn Contract::evaluate(self : Contract) -> Unit {
  match self.view {
    Some(view) =>
      match
        view.eval(
          "[window.__moonview_initialized, navigator.userAgent, 40 + 2]", "contract-eval",
        ) {
        Ok(_) => ()
        Err(_) => self.complete(false)
      }
    None => self.complete(false)
  }
}

///|
fn Contract::complete_success(self : Contract) -> Unit {
  match self.view {
    Some(view) =>
      match view.set_zoom_factor(1.25) {
        Ok(_) => self.complete(true)
        Err(_) => self.complete(false)
      }
    None => self.complete(false)
  }
}

///|
fn Contract::complete(self : Contract, passed : Bool) -> Unit {
  if !self.completed {
    self.completed = true
    self.passed = passed
    match self.view {
      Some(view) => ignore(view.destroy())
      None => ()
    }
    self.view = None
    (self.finish)(passed)
  }
}
