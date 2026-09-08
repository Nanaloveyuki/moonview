///|
test "page message provenance is callback-local and survives nested callbacks" {
  let handle = 987_654UL
  let view = WebView::{ handle, owner_thread: native_thread_token(), }
  let sources : Array[String?] = []
  register_view(
    handle,
    WebViewOptions::new(bounds=Rect::new(x=0, y=0, width=1, height=1), on_event=event => {
      sources.push(view.page_message_source())
      if event == PageMessage("outer") {
        dispatch_native_event(handle, 3, b"inner", b"https://b.example/", 0)
        sources.push(view.page_message_source())
      }
    }),
  )
  defer unregister_view(handle)
  assert_eq(view.page_message_source(), None)
  dispatch_native_event(handle, 3, b"outer", b"https://a.example/", 0)
  assert_eq(sources, [
    Some("https://a.example/"),
    Some("https://b.example/"),
    Some("https://a.example/"),
  ])
  assert_eq(view.page_message_source(), None)
  dispatch_native_event(handle, 3, b"unknown", b"", 0)
  dispatch_native_event(handle, 3, b"failed", b"decode error", -1)
  assert_eq(sources[3], None)
  assert_eq(sources[4], None)
}

///|
test "native event decoding preserves WebView2 payloads" {
  let event = decode_native_event(
    9,
    encode_utf8("42"),
    encode_utf8("request-7"),
    0,
  )
  assert_eq(event, WebViewEvent::ScriptResult("request-7", "42"))
  let failure = decode_native_event(
    6,
    encode_utf8("https://example.test"),
    encode_utf8("offline"),
    -1,
  )
  assert_eq(
    failure,
    WebViewEvent::NavigationFailed(
      "https://example.test",
      WebViewError::NativeFailure(-1, "offline"),
    ),
  )
}

///|
test "script results retain their JSON representation" {
  let string_result = decode_native_event(
    9,
    encode_utf8("\"moonview\""),
    encode_utf8("request-json"),
    0,
  )
  assert_eq(
    string_result,
    WebViewEvent::ScriptResult("request-json", "\"moonview\""),
  )
  let undefined_result = decode_native_event(
    9,
    encode_utf8("null"),
    encode_utf8("request-undefined"),
    0,
  )
  assert_eq(
    undefined_result,
    WebViewEvent::ScriptResult("request-undefined", "null"),
  )
}

///|
test "history decoding is insensitive to field order" {
  let event = decode_native_event(
    8,
    encode_utf8(""),
    encode_utf8("forward=1;back=0"),
    0,
  )
  assert_eq(event, WebViewEvent::HistoryChanged(false, true))
}

///|
test "navigation state follows source and history events" {
  let handle : UInt64 = 9012
  register_view(
    handle,
    WebViewOptions::new(bounds=Rect::new(x=0, y=0, width=1, height=1)),
  )
  dispatch_native_event(
    handle,
    5,
    encode_utf8("https://example.test/docs"),
    encode_utf8(""),
    0,
  )
  dispatch_native_event(
    handle,
    8,
    encode_utf8(""),
    encode_utf8("back=1;forward=0"),
    0,
  )
  assert_eq(
    navigation_state_of(handle),
    NavigationState::new(
      url="https://example.test/docs",
      can_go_back=true,
      can_go_forward=false,
    ),
  )
  unregister_view(handle)
}

///|
test "lifecycle moves from creation to ready or failed" {
  let handle : UInt64 = 9001
  register_view(
    handle,
    WebViewOptions::new(bounds=Rect::new(x=0, y=0, width=1, height=1)),
  )
  assert_eq(lifecycle_of(handle), WebViewLifecycle::Creating)
  dispatch_native_event(handle, 1, encode_utf8(""), encode_utf8(""), 0)
  assert_eq(lifecycle_of(handle), WebViewLifecycle::Ready)
  dispatch_native_event(
    handle,
    2,
    encode_utf8(""),
    encode_utf8("runtime missing"),
    -2,
  )
  assert_eq(
    lifecycle_of(handle),
    WebViewLifecycle::Failed(WebViewError::NativeFailure(-2, "runtime missing")),
  )
  unregister_view(handle)
  assert_eq(lifecycle_of(handle), WebViewLifecycle::Destroyed)
}

///|
test "process failure makes a ready view terminal" {
  let handle : UInt64 = 9006
  register_view(
    handle,
    WebViewOptions::new(bounds=Rect::new(x=0, y=0, width=1, height=1)),
  )
  dispatch_native_event(handle, 1, encode_utf8(""), encode_utf8(""), 0)
  dispatch_native_event(
    handle,
    11,
    encode_utf8(""),
    encode_utf8("render process exited"),
    1,
  )
  assert_eq(
    lifecycle_of(handle),
    WebViewLifecycle::Failed(
      WebViewError::NativeFailure(1, "render process exited"),
    ),
  )
  unregister_view(handle)
}

///|
test "OpenHarmony attachment uses the common ready lifecycle" {
  let handle : UInt64 = 9004
  register_ohos_view(handle, OhosAttachOptions::new())
  assert_eq(lifecycle_of(handle), WebViewLifecycle::Creating)
  dispatch_native_event(handle, 1, encode_utf8(""), encode_utf8(""), 0)
  assert_eq(lifecycle_of(handle), WebViewLifecycle::Ready)
  unregister_view(handle)
}

///|
test "rejected native commands become observable failures" {
  assert_eq(command_result("navigate", 1), Ok(()))
  assert_eq(
    command_result("navigate", 0),
    Err(WebViewError::NativeFailure(0, "WebView backend rejected navigate")),
  )
}

///|
test "owner-thread checks reject commands before native dispatch" {
  assert_eq(owner_thread_result(true), Ok(()))
  assert_eq(owner_thread_result(false), Err(WebViewError::WrongThread))
}

///|
test "custom protocol headers use a length-prefixed UTF-8 envelope" {
  let headers = [
    HttpHeader::new(name="Content-Type", value="text/plain; charset=utf-8"),
    HttpHeader::new(name="X-Name", value="MoonBit"),
  ]
  assert_eq(decode_http_headers(encode_http_headers(headers)), headers)
}

///|
test "malformed custom protocol headers are rejected" {
  assert_eq(decode_http_headers(b"\x00\x00\x00\x01"), [])
}

///|
test "protocol cancellation uses the request identifier" {
  assert_eq(
    decode_native_event(10, encode_utf8("request-8"), encode_utf8(""), 0),
    WebViewEvent::ProtocolCancelled("request-8"),
  )
}

///|
test "unknown media permission kinds are denied" {
  let handle : UInt64 = 9002
  register_view(
    handle,
    WebViewOptions::new(bounds=Rect::new(x=0, y=0, width=1, height=1), on_media_permission=_request => {
      MediaPermissionDecision::Allow
    }),
  )
  assert_eq(
    decide_media_permission(handle, 99, encode_utf8("https://example.test")),
    0,
  )
  assert_eq(
    decide_media_permission(handle, 1, encode_utf8("https://example.test")),
    1,
  )
  unregister_view(handle)
}

///|
test "navigation decisions are isolated per view and deny unknown views" {
  let allowed : UInt64 = 9002
  let denied : UInt64 = 9003
  let options = WebViewOptions::new(
    bounds=Rect::new(x=0, y=0, width=1, height=1),
    on_navigation=_url => NavigationDecision::Deny,
  )
  register_view(
    allowed,
    WebViewOptions::new(bounds=Rect::new(x=0, y=0, width=1, height=1)),
  )
  register_view(denied, options)
  let url = encode_utf8("https://example.test")
  assert_eq(decide_navigation(allowed, url), 1)
  assert_eq(decide_navigation(denied, url), 0)
  unregister_view(allowed)
  unregister_view(denied)
  assert_eq(decide_navigation(allowed, url), 0)
}

///|
test "new window requests deny by default and remain isolated per view" {
  let denied : UInt64 = 9004
  let redirected : UInt64 = 9005
  let url = encode_utf8("https://example.test/popup")
  register_view(
    denied,
    WebViewOptions::new(bounds=Rect::new(x=0, y=0, width=1, height=1)),
  )
  register_view(
    redirected,
    WebViewOptions::new(bounds=Rect::new(x=0, y=0, width=1, height=1), on_new_window=_url => {
      NewWindowDecision::NavigateCurrent
    }),
  )
  assert_eq(decide_new_window(denied, url), 0)
  assert_eq(decide_new_window(redirected, url), 1)
  unregister_view(denied)
  unregister_view(redirected)
  assert_eq(decide_new_window(redirected, url), 0)
}

///|
test "options preserve the configured user agent" {
  let options = WebViewOptions::new(
    bounds=Rect::new(x=0, y=0, width=1, height=1),
    user_agent="moonview-test/1.0",
  )
  assert_eq(options.user_agent, "moonview-test/1.0")
}

///|
test "zoom factors must be positive" {
  let view = WebView::{ handle: 9010, owner_thread: 0UL, }
  assert_eq(
    view.set_zoom_factor(0.0),
    Err(
      WebViewError::NativeFailure(
        0, "WebView zoom factor must be greater than zero",
      ),
    ),
  )
}
