///|
/// Per-view callbacks and observable lifecycle. The native backend owns
/// command queuing before Ready; this registry only routes callbacks.
priv struct Registration {
  lifecycle : WebViewLifecycle
  navigation_state : NavigationState
  on_event : (WebViewEvent) -> Unit
  on_navigation : (String) -> NavigationDecision
  on_new_window : (String) -> NewWindowDecision
  on_media_permission : (MediaPermissionRequest) -> MediaPermissionDecision
}

///|
let registrations : Map[UInt64, Registration] = Map([])

///|
let callback_installation : Map[Int, Unit] = Map([])

///|
let custom_schemes_locked : Map[Int, Unit] = Map([])

///|
fn ensure_native_callbacks() -> Unit {
  if !callback_installation.contains(0) {
    install_native_callbacks(
      dispatch_native_event, decide_navigation, decide_new_window, dispatch_protocol_request,
      decide_media_permission,
    )
    callback_installation.set(0, ())
  }
}

///|
fn register_view(handle : UInt64, options : WebViewOptions) -> Unit {
  registrations.set(handle, {
    lifecycle: WebViewLifecycle::Creating,
    navigation_state: NavigationState::new(),
    on_event: options.on_event,
    on_navigation: options.on_navigation,
    on_new_window: options.on_new_window,
    on_media_permission: options.on_media_permission,
  })
}

///|
fn register_ohos_view(handle : UInt64, options : OhosAttachOptions) -> Unit {
  registrations.set(handle, {
    lifecycle: WebViewLifecycle::Creating,
    navigation_state: NavigationState::new(),
    on_event: options.on_event,
    on_navigation: allow_navigation,
    on_new_window: deny_new_window,
    on_media_permission: deny_media_permission,
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
fn navigation_state_of(handle : UInt64) -> NavigationState {
  match registrations.get(handle) {
    Some(registration) => registration.navigation_state
    None => NavigationState::new()
  }
}

///|
fn update_lifecycle(handle : UInt64, lifecycle : WebViewLifecycle) -> Unit {
  match registrations.get(handle) {
    Some(registration) =>
      registrations.set(handle, {
        lifecycle,
        navigation_state: registration.navigation_state,
        on_event: registration.on_event,
        on_navigation: registration.on_navigation,
        on_new_window: registration.on_new_window,
        on_media_permission: registration.on_media_permission,
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
      update_navigation_state(handle, event)
      (registration.on_event)(event)
    }
    None => ()
  }
}

///|
fn update_navigation_state(handle : UInt64, event : WebViewEvent) -> Unit {
  match registrations.get(handle) {
    Some(registration) => {
      let navigation_state = match event {
        WebViewEvent::SourceChanged(url) =>
          {
            url,
            can_go_back: registration.navigation_state.can_go_back,
            can_go_forward: registration.navigation_state.can_go_forward,
          }
        WebViewEvent::HistoryChanged(can_go_back, can_go_forward) =>
          {
            url: registration.navigation_state.url,
            can_go_back,
            can_go_forward,
          }
        _ => return
      }
      registrations.set(handle, {
        lifecycle: registration.lifecycle,
        navigation_state,
        on_event: registration.on_event,
        on_navigation: registration.on_navigation,
        on_new_window: registration.on_new_window,
        on_media_permission: registration.on_media_permission,
      })
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
fn decide_new_window(handle : UInt64, url : Bytes) -> Int {
  match registrations.get(handle) {
    Some(registration) =>
      match (registration.on_new_window)(decode_utf8(url)) {
        NewWindowDecision::Deny => 0
        NewWindowDecision::NavigateCurrent => 1
      }
    None => 0
  }
}

///|
fn dispatch_protocol_request(
  handle : UInt64,
  request_id : Bytes,
  scheme : Bytes,
  http_method : Bytes,
  uri : Bytes,
  headers : Bytes,
  body : Bytes,
) -> Unit {
  match registrations.get(handle) {
    Some(registration) =>
      (registration.on_event)(
        WebViewEvent::ProtocolRequest({
          id: decode_utf8(request_id),
          scheme: decode_utf8(scheme),
          http_method: decode_utf8(http_method),
          uri: decode_utf8(uri),
          headers: decode_http_headers(headers),
          body,
        }),
      )
    None => ()
  }
}

///|
fn decide_media_permission(handle : UInt64, kind : Int, origin : Bytes) -> Int {
  match media_permission_kind_from_native(kind) {
    MediaPermissionKind::Unknown(_) => 0
    kind =>
      match registrations.get(handle) {
        Some(registration) =>
          match
            (registration.on_media_permission)({
              kind,
              origin: decode_utf8(origin),
            }) {
            MediaPermissionDecision::Allow => 1
            MediaPermissionDecision::Deny => 0
          }
        None => 0
      }
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
    10 => WebViewEvent::ProtocolCancelled(value)
    _ => WebViewEvent::CreationFailed(WebViewError::NativeFailure(code, detail))
  }
}

///|
fn decode_utf8(bytes : BytesView) -> String {
  @utf8.decode_lossy(bytes[:], ignore_bom=true)
}

///|
fn encode_utf8(text : String) -> Bytes {
  @utf8.encode(text[:], bom=false)
}

///|
/// Header wire format: `u32be count`, followed by each UTF-8 name and value
/// prefixed by its `u32be` byte length. The format is shared by every backend.
fn encode_http_headers(headers : Array[HttpHeader]) -> Bytes {
  let output : Array[Byte] = []
  append_u32be(output, headers.length())
  for header in headers {
    let name = encode_utf8(header.name)
    let value = encode_utf8(header.value)
    append_u32be(output, name.length())
    append_bytes(output, name)
    append_u32be(output, value.length())
    append_bytes(output, value)
  }
  Bytes::from_array(output)
}

///|
fn decode_http_headers(bytes : Bytes) -> Array[HttpHeader] {
  let mut offset = 0
  let count = match read_u32be(bytes, offset) {
    Some(value) => value
    None => return []
  }
  offset += 4
  if count < 0 || count > bytes.length() / 8 {
    return []
  }
  let headers : Array[HttpHeader] = []
  for _ in 0..<count {
    let name_length = match read_u32be(bytes, offset) {
      Some(value) => value
      None => return []
    }
    offset += 4
    if name_length < 0 || name_length > bytes.length() - offset {
      return []
    }
    let name = decode_utf8(bytes[offset:offset + name_length])
    offset += name_length
    let value_length = match read_u32be(bytes, offset) {
      Some(value) => value
      None => return []
    }
    offset += 4
    if value_length < 0 || value_length > bytes.length() - offset {
      return []
    }
    let value = decode_utf8(bytes[offset:offset + value_length])
    offset += value_length
    headers.push({ name, value })
  }
  if offset == bytes.length() {
    headers
  } else {
    []
  }
}

///|
fn append_u32be(output : Array[Byte], value : Int) -> Unit {
  output.push(((value >> 24) & 0xff).to_byte())
  output.push(((value >> 16) & 0xff).to_byte())
  output.push(((value >> 8) & 0xff).to_byte())
  output.push((value & 0xff).to_byte())
}

///|
fn append_bytes(output : Array[Byte], value : Bytes) -> Unit {
  for byte in value {
    output.push(byte)
  }
}

///|
fn read_u32be(bytes : Bytes, offset : Int) -> Int? {
  if offset < 0 || offset + 4 > bytes.length() {
    None
  } else {
    Some(
      (bytes[offset].to_int() << 24) |
      (bytes[offset + 1].to_int() << 16) |
      (bytes[offset + 2].to_int() << 8) |
      bytes[offset + 3].to_int(),
    )
  }
}

///|
fn media_permission_kind_from_native(kind : Int) -> MediaPermissionKind {
  match kind {
    1 => MediaPermissionKind::Camera
    2 => MediaPermissionKind::Microphone
    3 => MediaPermissionKind::CameraAndMicrophone
    _ => MediaPermissionKind::Unknown(kind)
  }
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
