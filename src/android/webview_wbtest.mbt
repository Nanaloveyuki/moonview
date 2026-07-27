///|
test "ajni events preserve Moonview Android lifecycle semantics" {
  let events : Array[AndroidWebViewEvent] = []
  let handle = 71L
  registrations.set(handle, { on_event: event => events.push(event) })
  dispatch_event_kind(handle, Created(""))
  dispatch_event_kind(
    handle,
    NavigationFinished("https://example.test"),
  )
  dispatch_event_kind(
    handle,
    ScriptResult("request-1", "null"),
  )
  assert_eq(events, [
    Ready,
    SourceChanged("https://example.test"),
    NavigationCompleted("https://example.test"),
    ScriptResult("request-1", "null"),
  ])
  ignore(registrations.remove(handle))
}
