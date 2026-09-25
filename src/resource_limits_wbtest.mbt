///|
test "resource limits use documented defaults" {
  let limits = WebViewResourceLimits::new()
  assert_eq(limits.max_pending_commands, 256)
  assert_eq(limits.max_pending_command_bytes, 4 * 1024 * 1024)
  assert_eq(limits.max_protocol_request_body_bytes, 4 * 1024 * 1024)
}

///|
test "resource limits preserve explicit zero caps" {
  let limits = WebViewResourceLimits::new(
    max_pending_commands=0,
    max_pending_command_bytes=0,
    max_protocol_request_body_bytes=0,
  )
  assert_eq(limits.max_pending_commands, 0)
  assert_eq(limits.max_pending_command_bytes, 0)
  assert_eq(limits.max_protocol_request_body_bytes, 0)
}

///|
test "negative resource limits are rejected" {
  let error = resource_limits_error(
    WebViewResourceLimits::new(max_pending_commands=-1),
  )
  match error {
    Some(NativeFailure(_, _)) => ()
    _ => fail("expected a native failure")
  }
}

///|
test "invalid WebView bounds are rejected before native creation" {
  let zero_width = bounds_error(Rect::new(x=0, y=0, width=0, height=1))
  let zero_height = bounds_error(Rect::new(x=0, y=0, width=1, height=0))
  let valid = bounds_error(Rect::new(x=-10, y=-20, width=1, height=1))
  match (zero_width, zero_height, valid) {
    (Some(NativeFailure(_, _)), Some(NativeFailure(_, _)), None) => ()
    _ => fail("expected only positive dimensions to be accepted")
  }
}
