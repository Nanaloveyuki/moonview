///|
test "persistent contexts reuse the same data-directory identity" {
  let first = WebContext::persistent(data_directory="moonview-profile")
  let second = WebContext::persistent(data_directory="moonview-profile")
  assert_eq(first, second)
  assert_eq(WebContext::persistent(), WebContext::persistent())
}

///|
test "ephemeral contexts remain isolated" {
  let first = WebContext::ephemeral()
  let second = WebContext::ephemeral()
  assert_false(first == second)
  assert_eq(first.storage, WebContextStorage::Ephemeral)
  assert_eq(first.data_directory, "")
}
