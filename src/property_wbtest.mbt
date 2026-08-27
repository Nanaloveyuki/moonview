///|
/// Converts generated header pairs into the public wire-format type without
/// constraining the strings, so Unicode and empty fields remain in the input
/// domain.
fn qc_headers(pairs : Array[(String, String)]) -> Array[HttpHeader] {
  pairs.map(pair => {
    let (name, value) = pair
    HttpHeader::new(name~, value~)
  })
}

///|
fn qc_append_byte(bytes : Bytes, value : Byte) -> Bytes {
  let output = bytes.to_array()
  output.push(value)
  Bytes::from_array(output)
}

///|
fn qc_without_last_byte(bytes : Bytes) -> Bytes {
  let end = bytes.length() - 1
  Bytes::from_array(bytes.to_array()[0:end])
}

///|
fn qc_append_u32be(output : Array[Byte], value : Int) -> Unit {
  output.push(((value >> 24) & 0xff).to_byte())
  output.push(((value >> 16) & 0xff).to_byte())
  output.push(((value >> 8) & 0xff).to_byte())
  output.push((value & 0xff).to_byte())
}

///|
fn qc_append_bytes(output : Array[Byte], value : Bytes) -> Unit {
  for byte in value {
    output.push(byte)
  }
}

///|
/// Independent encoder for the shared protocol header frame.
fn qc_encode_http_headers(pairs : Array[(String, String)]) -> Bytes {
  let output : Array[Byte] = []
  qc_append_u32be(output, pairs.length())
  for pair in pairs {
    let (name, value) = pair
    let encoded_name = @utf8.encode(name[:], bom=false)
    let encoded_value = @utf8.encode(value[:], bom=false)
    qc_append_u32be(output, encoded_name.length())
    qc_append_bytes(output, encoded_name)
    qc_append_u32be(output, encoded_value.length())
    qc_append_bytes(output, encoded_value)
  }
  Bytes::from_array(output)
}

///|
/// Independent encoder for the native file-dialog selection response. The
/// production code only decodes this backend-owned frame.
fn qc_encode_file_dialog_selection(paths : Array[String]) -> Bytes {
  let output : Array[Byte] = []
  qc_append_u32be(output, paths.length())
  for path in paths {
    let encoded = @utf8.encode(path[:], bom=false)
    qc_append_u32be(output, encoded.length())
    qc_append_bytes(output, encoded)
  }
  Bytes::from_array(output)
}

///|
fn qc_nonempty_paths(paths : Array[String]) -> Array[String] {
  paths.map(path => if path.length() == 0 { "path" } else { path })
}

///|
fn qc_filter_name(value : String) -> String {
  let value = value.trim().to_owned()
  if value.is_empty() || value.contains("\t") || value.contains("\n") {
    "Filter"
  } else {
    value
  }
}

///|
fn qc_filter_extension(value : String) -> String {
  let value = value.trim().to_owned()
  if value.is_empty() ||
    value.contains("\t") ||
    value.contains("\n") ||
    value.contains(";") ||
    value.contains("*") ||
    value.has_prefix(".") {
    "dat"
  } else {
    value
  }
}

///|
/// Produces only values accepted by the file-dialog filter contract. This
/// keeps shrinking inside the valid domain instead of discarding most cases.
fn qc_valid_filters(
  seeds : Array[(String, Array[String])],
) -> Array[FileDialogFilter] {
  seeds.map(seed => {
    let (raw_name, raw_extensions) = seed
    let extensions = if raw_extensions.is_empty() {
      ["dat"]
    } else {
      raw_extensions.map(extension => qc_filter_extension(extension))
    }
    FileDialogFilter::new(name=qc_filter_name(raw_name), extensions~)
  })
}

///|
fn qc_expected_filter_encoding(filters : Array[FileDialogFilter]) -> String {
  filters
  .map(filter => {
    let patterns = filter.extensions
      .map(extension => "*." + extension)
      .join(";")
    filter.name + "\t" + patterns
  })
  .join("\n")
}

///|
test "quickcheck: UTF-8 bridge round-trips arbitrary strings" {
  @quickcheck.check(
    (text : String) => decode_utf8(encode_utf8(text)) == text,
    count=300,
    max_size=64,
    max_shrinks=200,
    seed=2026082701,
  )
}

///|
test "quickcheck: protocol headers round-trip arbitrary UTF-8 pairs" {
  @quickcheck.check(
    (pairs : Array[(String, String)]) => {
      let headers = qc_headers(pairs)
      let expected = qc_encode_http_headers(pairs)
      encode_http_headers(headers) == expected &&
      decode_http_headers(expected) == headers
    },
    count=300,
    max_size=48,
    max_shrinks=200,
    seed=2026082702,
  )
}

///|
test "quickcheck: protocol header frames reject truncation and trailing bytes" {
  @quickcheck.check(
    (pairs : Array[(String, String)]) => {
      let encoded = qc_encode_http_headers(pairs)
      decode_http_headers(qc_without_last_byte(encoded)) == [] &&
      decode_http_headers(qc_append_byte(encoded, b'\x00')) == []
    },
    count=300,
    max_size=48,
    max_shrinks=200,
    seed=2026082703,
  )
}

///|
test "quickcheck: file-dialog filters match an independent wire model" {
  @quickcheck.check(
    (seeds : Array[(String, Array[String])]) => {
      let filters = qc_valid_filters(seeds)
      let expected = @utf8.encode(
        qc_expected_filter_encoding(filters)[:],
        bom=false,
      )
      match encode_file_dialog_filters(filters) {
        Ok(encoded) => encoded == expected
        Err(_) => false
      }
    },
    count=300,
    max_size=24,
    max_shrinks=200,
    seed=2026082704,
  )
}

///|
test "quickcheck: file-dialog selection frames decode with an independent model" {
  @quickcheck.check(
    (raw_paths : Array[String]) => {
      let paths = qc_nonempty_paths(raw_paths)
      decode_file_dialog_selection(qc_encode_file_dialog_selection(paths)) ==
      Some(paths)
    },
    count=300,
    max_size=48,
    max_shrinks=200,
    seed=2026082705,
  )
}

///|
test "quickcheck: file-dialog selection decoder is total on arbitrary bytes" {
  @quickcheck.check(
    (payload : Bytes) => {
      match decode_file_dialog_selection(payload) {
        Some(paths) => {
          for path in paths {
            if path.length() == 0 {
              return false
            }
          }
          true
        }
        None => true
      }
    },
    count=300,
    max_size=64,
    max_shrinks=200,
    seed=2026082706,
  )
}

///|
test "quickcheck: history events match independent substring semantics" {
  @quickcheck.check(
    (detail : String) => {
      decode_native_event(8, encode_utf8(""), encode_utf8(detail), 0) ==
      HistoryChanged(detail.contains("back=1"), detail.contains("forward=1"))
    },
    count=300,
    max_size=64,
    max_shrinks=200,
    seed=2026082707,
  )
}

///|
test "quickcheck: navigation state follows every generated operation" {
  @quickcheck.check(
    (operations : Array[(String, Bool, Bool, Bool)]) => {
      let handle : UInt64 = 12001UL
      unregister_view(handle)
      register_view(
        handle,
        WebViewOptions::new(bounds=Rect::new(x=0, y=0, width=1, height=1)),
      )
      let mut expected = NavigationState::new()
      for operation in operations {
        let (url, source_changed, can_go_back, can_go_forward) = operation
        if source_changed {
          update_navigation_state(handle, SourceChanged(url))
          expected = NavigationState::new(
            url~,
            can_go_back=expected.can_go_back,
            can_go_forward=expected.can_go_forward,
          )
        } else {
          update_navigation_state(
            handle,
            HistoryChanged(can_go_back, can_go_forward),
          )
          expected = NavigationState::new(
            url=expected.url,
            can_go_back~,
            can_go_forward~,
          )
        }
        if navigation_state_of(handle) != expected {
          unregister_view(handle)
          return false
        }
      }
      unregister_view(handle)
      true
    },
    count=200,
    max_size=48,
    max_shrinks=200,
    seed=2026082708,
  )
}
