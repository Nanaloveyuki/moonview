///|
test "ajni events preserve Moonview Android lifecycle semantics" {
  let events : Array[AndroidWebViewEvent] = []
  let handle = 71L
  registrations.set(handle, {
    lifecycle: Creating,
    trusted_origin: "https://example.test",
    resource_limits: AndroidResourceLimits::new(),
    on_event: event => events.push(event),
  })
  dispatch_event_kind(handle, Created(""))
  dispatch_event_kind(handle, NavigationFinished("https://example.test"))
  dispatch_event_kind(handle, ScriptResult("request-1", "null"))
  assert_eq(events, [
    Ready,
    SourceChanged("https://example.test"),
    NavigationCompleted("https://example.test"),
    ScriptResult("request-1", "null"),
  ])
  ignore(registrations.remove(handle))
}

///|
test "Android origins are explicit HTTPS authorities" {
  assert_true(is_https_origin("https://app.example.test"))
  assert_true(!is_https_origin("http://app.example.test"))
  assert_true(!is_https_origin("https://app.example.test/path"))
  assert_true(!is_https_origin("https://app.example.test:8443"))
  assert_true(
    is_asset_url(
      "https://app.example.test/assets/app.js", "https://app.example.test",
    ),
  )
  assert_true(
    !is_asset_url(
      "https://app.example.test/not-an-asset", "https://app.example.test",
    ),
  )
}

///|
test "destroyed views discard later native callbacks" {
  let events : Array[AndroidWebViewEvent] = []
  let handle = 72L
  registrations.set(handle, {
    lifecycle: Ready,
    trusted_origin: "https://example.test",
    resource_limits: AndroidResourceLimits::new(),
    on_event: event => events.push(event),
  })
  dispatch_event_kind(handle, Destroyed)
  dispatch_event_kind(handle, TitleChanged("late"))
  assert_eq(events, [Destroyed])
}
