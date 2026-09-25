///|
const FILE_DIALOG_SELECTED = 0

///|
const FILE_DIALOG_CANCELLED = 1

///|
const FILE_DIALOG_UNSUPPORTED = -1

///|
fn file_dialog_kind_code(kind : FileDialogKind) -> Int {
  match kind {
    OpenFile => 0
    OpenFiles => 1
    SaveFile => 2
    PickDirectory => 3
  }
}

///|
fn invalid_file_dialog_options(message : String) -> Result[Bytes, WebViewError] {
  Err(NativeFailure(0, message))
}

///|
fn encode_file_dialog_filters(
  filters : Array[FileDialogFilter],
) -> Result[Bytes, WebViewError] {
  if filters.length() > 32 {
    return invalid_file_dialog_options(
      "file dialogs support at most 32 filters",
    )
  }
  let encoded : Array[String] = []
  for filter in filters {
    let name = filter.name.trim().to_owned()
    if name.is_empty() || name.contains("\t") || name.contains("\n") {
      return invalid_file_dialog_options(
        "file dialog filter names must be non-empty and contain no tab or newline",
      )
    }
    if filter.extensions.is_empty() || filter.extensions.length() > 32 {
      return invalid_file_dialog_options(
        "file dialog filters must contain between 1 and 32 extensions",
      )
    }
    let patterns : Array[String] = []
    for extension in filter.extensions {
      let extension = extension.trim().to_owned()
      if extension.is_empty() ||
        extension.contains("\t") ||
        extension.contains("\n") ||
        extension.contains(";") ||
        extension.contains("*") ||
        extension.has_prefix(".") {
        return invalid_file_dialog_options(
          "file dialog extensions must be bare extension names",
        )
      }
      patterns.push("*." + extension)
    }
    let pattern = patterns.join(";")
    encoded.push("\{name}\t\{pattern}")
  }
  Ok(encode_utf8(encoded.join("\n")))
}

///|
fn decode_file_dialog_selection(payload : Bytes) -> Array[String]? {
  let mut offset = 0
  let count = match read_u32be(payload, offset) {
    Some(count) => count
    None => return None
  }
  offset += 4
  if count < 0 || count > 1024 {
    return None
  }
  let paths : Array[String] = []
  for _ in 0..<count {
    let length = match read_u32be(payload, offset) {
      Some(length) => length
      None => return None
    }
    offset += 4
    if length <= 0 || length > payload.length() - offset {
      return None
    }
    paths.push(decode_utf8(payload[offset:offset + length]))
    offset += length
  }
  if offset == payload.length() {
    Some(paths)
  } else {
    None
  }
}

///|
/// Shows a native file dialog owned by this WebView's native container.
///
/// The method must run on the WebView creation thread. A user cancellation is
/// returned as `FileDialogResult::Cancelled`; backend and native failures are
/// returned as `WebViewError` values.
pub fn WebView::show_file_dialog(
  self : WebView,
  options : FileDialogOptions,
) -> Result[FileDialogResult, WebViewError] {
  if !self.on_owner_thread() {
    return Err(WrongThread)
  }
  match self.lifecycle() {
    Destroyed => return Err(Destroyed)
    Failed(error) => return Err(error)
    _ => ()
  }
  let filters = match encode_file_dialog_filters(options.filters) {
    Ok(filters) => filters
    Err(error) => return Err(error)
  }
  let status = Ref(FILE_DIALOG_UNSUPPORTED)
  let response = native_show_file_dialog(
    self.handle,
    file_dialog_kind_code(options.kind),
    encode_utf8(options.title.unwrap_or("")),
    filters,
    encode_utf8(options.default_name.unwrap_or("")),
    encode_utf8(options.initial_directory.unwrap_or("")),
    status,
  )
  match status.val {
    FILE_DIALOG_SELECTED =>
      match decode_file_dialog_selection(response) {
        Some(paths) => Ok(Selected(paths))
        None =>
          Err(
            NativeFailure(
              0, "file dialog backend returned an invalid selection",
            ),
          )
      }
    FILE_DIALOG_CANCELLED => Ok(Cancelled)
    FILE_DIALOG_UNSUPPORTED =>
      Err(Unsupported("native file dialogs are unavailable on this backend"))
    code => Err(NativeFailure(code, "native file dialog failed"))
  }
}

///|
test "file dialog filters have a deterministic native encoding" {
  let filters = [
    FileDialogFilter::new(name="Text", extensions=["txt", "md"]),
    FileDialogFilter::new(name="Images", extensions=["png"]),
  ]
  match encode_file_dialog_filters(filters) {
    Ok(encoded) =>
      inspect(
        decode_utf8(encoded[:]),
        content="Text\t*.txt;*.md\nImages\t*.png",
      )
    Err(_) => fail("expected valid filter encoding")
  }
}

///|
test "file dialog filters reject ambiguous native delimiters" {
  match
    encode_file_dialog_filters([
      FileDialogFilter::new(name="Bad\tName", extensions=["txt"]),
    ]) {
    Err(NativeFailure(_, _)) => ()
    _ => fail("expected invalid filter rejection")
  }
}

///|
test "file dialog selections require a complete length-prefixed frame" {
  let selected : Array[Byte] = []
  append_u32be(selected, 1)
  let path = encode_utf8("C:/example.txt")
  append_u32be(selected, path.length())
  append_bytes(selected, path)
  match decode_file_dialog_selection(Bytes::from_array(selected)) {
    Some(paths) => assert_eq(paths, ["C:/example.txt"])
    None => fail("expected selection")
  }
  assert_eq(decode_file_dialog_selection(b"\x00\x00\x00\x01"), None)
}
