///|
/// Per-view callbacks and observable lifecycle. The native backend owns
/// command queuing before Ready; this registry only routes callbacks.
priv struct Registration {
  lifecycle : WebViewLifecycle
  on_event : (WebViewEvent) -> Unit
  on_navigation : (String) -> NavigationDecision
}

///|
let registrations : Map[UInt64, Registration] = Map([])

///|
let callback_installation : Map[Int, Unit] = Map([])

///|
fn ensure_native_callbacks() -> Unit {
  if !callback_installation.contains(0) {
    install_native_callbacks(dispatch_native_event, decide_navigation)
    callback_installation.set(0, ())
  }
}

///|
fn register_view(handle : UInt64, options : WebViewOptions) -> Unit {
  registrations.set(handle, {
    lifecycle: WebViewLifecycle::Creating,
    on_event: options.on_event,
    on_navigation: options.on_navigation,
  })
}

///|
fn unregister_view(handle : UInt64) -> Unit {
  ignore(registrations.remove(handle))
}

///|
fn lifecycle_of(handle : UInt64) -> WebViewLifecycle {
  match registrations.get(handle) {
    Some(registration) => registration.lifecycle
    None => WebViewLifecycle::Destroyed
  }
}

///|
fn update_lifecycle(handle : UInt64, lifecycle : WebViewLifecycle) -> Unit {
  match registrations.get(handle) {
    Some(registration) =>
      registrations.set(handle, {
        lifecycle,
        on_event: registration.on_event,
        on_navigation: registration.on_navigation,
      })
    None => ()
  }
}

///|
fn dispatch_native_event(
  handle : UInt64,
  kind : Int,
  value : Bytes,
  detail : Bytes,
  code : Int,
) -> Unit {
  match registrations.get(handle) {
    Some(registration) => {
      let event = decode_native_event(kind, value, detail, code)
      match event {
        WebViewEvent::Ready => update_lifecycle(handle, WebViewLifecycle::Ready)
        WebViewEvent::CreationFailed(error) =>
          update_lifecycle(handle, WebViewLifecycle::Failed(error))
        _ => ()
      }
      (registration.on_event)(event)
    }
    None => ()
  }
}

///|
fn decide_navigation(handle : UInt64, url : Bytes) -> Int {
  match registrations.get(handle) {
    Some(registration) =>
      match (registration.on_navigation)(decode_utf8(url)) {
        NavigationDecision::Allow => 1
        NavigationDecision::Deny => 0
      }
    None => 0
  }
}

///|
fn decode_native_event(
  kind : Int,
  value : Bytes,
  detail : Bytes,
  code : Int,
) -> WebViewEvent {
  let value = decode_utf8(value)
  let detail = decode_utf8(detail)
  match kind {
    1 => WebViewEvent::Ready
    2 => WebViewEvent::CreationFailed(WebViewError::NativeFailure(code, detail))
    3 => WebViewEvent::PageMessage(value)
    4 => WebViewEvent::NavigationStarting(value)
    5 => WebViewEvent::SourceChanged(value)
    6 =>
      if code == 0 {
        WebViewEvent::NavigationCompleted(value)
      } else {
        WebViewEvent::NavigationFailed(
          value,
          WebViewError::NativeFailure(code, detail),
        )
      }
    7 => WebViewEvent::TitleChanged(value)
    8 =>
      WebViewEvent::HistoryChanged(
        contains_text(detail, "back=1"),
        contains_text(detail, "forward=1"),
      )
    9 =>
      if code == 0 {
        WebViewEvent::ScriptResult(detail, value)
      } else {
        WebViewEvent::ScriptFailed(
          detail,
          WebViewError::NativeFailure(code, value),
        )
      }
    _ => WebViewEvent::CreationFailed(WebViewError::NativeFailure(code, detail))
  }
}

///|
fn decode_utf8(bytes : Bytes) -> String {
  @utf8.decode_lossy(bytes[:], ignore_bom=true)
}

///|
fn encode_utf8(text : String) -> Bytes {
  @utf8.encode(text[:], bom=false)
}

///|
fn contains_text(text : String, needle : String) -> Bool {
  let text = text.to_array()
  let needle = needle.to_array()
  if needle.length() == 0 {
    true
  } else if needle.length() > text.length() {
    false
  } else {
    for start in 0..<=(text.length() - needle.length()) {
      let mut matched = true
      for offset in 0..<needle.length() {
        if text[start + offset] != needle[offset] {
          matched = false
        }
      }
      if matched {
        return true
      }
    }
    false
  }
}
