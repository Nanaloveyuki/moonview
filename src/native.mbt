///|
/// The native backend is selected by the target operating system at compile time.
priv enum NativeBackend {
  Windows
  MacOS
  Linux
  Ohos
  Unsupported
} derive(Eq)

///|
fn active_backend() -> NativeBackend {
  if @windows.available() != 0 {
    Windows
  } else if @macos.available() != 0 {
    MacOS
  } else if @linux.available() != 0 {
    Linux
  } else if @ohos.available() != 0 {
    Ohos
  } else {
    Unsupported
  }
}

///|
fn native_available() -> Bool {
  active_backend() != Unsupported
}

///|
fn native_thread_token() -> UInt64 {
  match active_backend() {
    Windows => @windows.current_thread_token()
    MacOS => @macos.current_thread_token()
    Linux => @linux.current_thread_token()
    _ => 0UL
  }
}

///|
fn native_is_owner_thread(owner_thread : UInt64) -> Bool {
  owner_thread != 0UL && native_thread_token() == owner_thread
}

///|
fn native_is_ohos() -> Bool {
  active_backend() == Ohos
}

///|
fn native_ohos_attached(handle : UInt64) -> Bool {
  match active_backend() {
    Ohos => @ohos.is_attached(handle) != 0
    _ => false
  }
}

///|
fn install_native_callbacks(
  event_callback : (UInt64, Int, Bytes, Bytes, Int) -> Unit,
  navigation_callback : (UInt64, Bytes) -> Int,
  new_window_callback : (UInt64, Bytes) -> Int,
  protocol_callback : (UInt64, Bytes, Bytes, Bytes, Bytes, Bytes, Bytes) -> Unit,
  media_permission_callback : (UInt64, Int, Bytes) -> Int,
) -> Unit {
  match active_backend() {
    Windows => {
      @windows.install_event_callback(
        fn(callback, handle, kind, value, detail, code) {
          callback(handle, kind, value, detail, code)
        },
        event_callback,
      )
      @windows.install_navigation_callback(
        fn(callback, handle, url) { callback(handle, url) },
        navigation_callback,
      )
      @windows.install_new_window_callback(
        fn(callback, handle, url) { callback(handle, url) },
        new_window_callback,
      )
      @windows.install_protocol_callback(
        fn(
          callback,
          handle,
          request_id,
          scheme,
          http_method,
          uri,
          headers,
          body,
        ) {
          callback(handle, request_id, scheme, http_method, uri, headers, body)
        },
        protocol_callback,
      )
      @windows.install_media_permission_callback(
        fn(callback, handle, kind, origin) { callback(handle, kind, origin) },
        media_permission_callback,
      )
    }
    MacOS => {
      @macos.install_event_callback(
        fn(callback, handle, kind, value, detail, code) {
          callback(handle, kind, value, detail, code)
        },
        event_callback,
      )
      @macos.install_navigation_callback(
        fn(callback, handle, url) { callback(handle, url) },
        navigation_callback,
      )
      @macos.install_new_window_callback(
        fn(callback, handle, url) { callback(handle, url) },
        new_window_callback,
      )
      @macos.install_protocol_callback(
        fn(
          callback,
          handle,
          request_id,
          scheme,
          http_method,
          uri,
          headers,
          body,
        ) {
          callback(handle, request_id, scheme, http_method, uri, headers, body)
        },
        protocol_callback,
      )
      @macos.install_media_permission_callback(
        fn(callback, handle, kind, origin) { callback(handle, kind, origin) },
        media_permission_callback,
      )
    }
    Linux => {
      @linux.install_event_callback(
        fn(callback, handle, kind, value, detail, code) {
          callback(handle, kind, value, detail, code)
        },
        event_callback,
      )
      @linux.install_navigation_callback(
        fn(callback, handle, url) { callback(handle, url) },
        navigation_callback,
      )
      @linux.install_new_window_callback(
        fn(callback, handle, url) { callback(handle, url) },
        new_window_callback,
      )
      @linux.install_protocol_callback(
        fn(
          callback,
          handle,
          request_id,
          scheme,
          http_method,
          uri,
          headers,
          body,
        ) {
          callback(handle, request_id, scheme, http_method, uri, headers, body)
        },
        protocol_callback,
      )
      @linux.install_media_permission_callback(
        fn(callback, handle, kind, origin) { callback(handle, kind, origin) },
        media_permission_callback,
      )
    }
    Ohos => {
      @ohos.install_event_callback(
        fn(callback, handle, kind, value, detail, code) {
          callback(handle, kind, value, detail, code)
        },
        event_callback,
      )
      @ohos.install_navigation_callback(
        fn(callback, handle, url) { callback(handle, url) },
        navigation_callback,
      )
      @ohos.install_protocol_callback(
        fn(
          callback,
          handle,
          request_id,
          scheme,
          http_method,
          uri,
          headers,
          body,
        ) {
          callback(handle, request_id, scheme, http_method, uri, headers, body)
        },
        protocol_callback,
      )
      @ohos.install_media_permission_callback(
        fn(callback, handle, kind, origin) { callback(handle, kind, origin) },
        media_permission_callback,
      )
    }
    Unsupported => ()
  }
}

///|
fn native_register_custom_scheme(name : Bytes) -> Int {
  match active_backend() {
    Windows => @windows.register_custom_scheme(name)
    MacOS => @macos.register_custom_scheme(name)
    Linux => @linux.register_custom_scheme(name)
    Ohos => 0
    Unsupported => 0
  }
}

///|
fn native_lock_custom_schemes() -> Unit {
  match active_backend() {
    Windows => @windows.lock_custom_schemes()
    MacOS => @macos.lock_custom_schemes()
    Linux => @linux.lock_custom_schemes()
    Ohos => ()
    Unsupported => ()
  }
}

///|
fn native_respond_protocol(
  handle : UInt64,
  request_id : Bytes,
  status : Int,
  headers : Bytes,
  body : Bytes,
) -> Int {
  match active_backend() {
    Windows =>
      @windows.respond_protocol(handle, request_id, status, headers, body)
    MacOS => @macos.respond_protocol(handle, request_id, status, headers, body)
    Linux => @linux.respond_protocol(handle, request_id, status, headers, body)
    Ohos => 0
    Unsupported => 0
  }
}

///|
fn native_create(
  context_id : UInt64,
  ephemeral : Bool,
  data_directory : Bytes,
  parent_handle : UInt64,
  x : Int,
  y : Int,
  width : Int,
  height : Int,
  initial_url : Bytes,
  initial_html : Bytes,
  initialization_script : Bytes,
  user_agent : Bytes,
  max_pending_commands : Int,
  max_pending_command_bytes : Int,
  max_protocol_request_body_bytes : Int,
) -> UInt64 {
  match active_backend() {
    Windows =>
      @windows.create(
        context_id, ephemeral, data_directory, parent_handle, x, y, width, height,
        initial_url, initial_html, initialization_script, user_agent, max_pending_commands,
        max_pending_command_bytes, max_protocol_request_body_bytes,
      )
    MacOS =>
      @macos.create(
        context_id, ephemeral, data_directory, parent_handle, x, y, width, height,
        initial_url, initial_html, initialization_script, user_agent, max_pending_commands,
        max_pending_command_bytes, max_protocol_request_body_bytes,
      )
    Linux =>
      @linux.create(
        context_id, ephemeral, data_directory, parent_handle, x, y, width, height,
        initial_url, initial_html, initialization_script, user_agent, max_pending_commands,
        max_pending_command_bytes, max_protocol_request_body_bytes,
      )
    Ohos => 0
    Unsupported => 0
  }
}

///|
fn native_start(handle : UInt64) -> Unit {
  match active_backend() {
    Windows => @windows.start(handle)
    MacOS => @macos.start(handle)
    Linux => @linux.start(handle)
    Ohos => ()
    Unsupported => ()
  }
}

///|
fn native_destroy(handle : UInt64) -> Int {
  match active_backend() {
    Windows => @windows.destroy(handle)
    MacOS => @macos.destroy(handle)
    Linux => @linux.destroy(handle)
    Ohos => @ohos.destroy(handle)
    Unsupported => 0
  }
}

///|
fn native_set_bounds(
  handle : UInt64,
  x : Int,
  y : Int,
  width : Int,
  height : Int,
) -> Int {
  match active_backend() {
    Windows => @windows.set_bounds(handle, x, y, width, height)
    MacOS => @macos.set_bounds(handle, x, y, width, height)
    Linux => @linux.set_bounds(handle, x, y, width, height)
    Ohos => 0
    Unsupported => 0
  }
}

///|
fn native_set_visible(handle : UInt64, visible : Bool) -> Int {
  let visible = if visible { 1 } else { 0 }
  match active_backend() {
    Windows => @windows.set_visible(handle, visible)
    MacOS => @macos.set_visible(handle, visible)
    Linux => @linux.set_visible(handle, visible)
    Ohos => 0
    Unsupported => 0
  }
}

///|
fn native_focus(handle : UInt64) -> Int {
  match active_backend() {
    Windows => @windows.focus(handle)
    MacOS => @macos.focus(handle)
    Linux => @linux.focus(handle)
    Ohos => 0
    Unsupported => 0
  }
}

///|
fn native_navigate(handle : UInt64, url : Bytes) -> Int {
  match active_backend() {
    Windows => @windows.navigate(handle, url)
    MacOS => @macos.navigate(handle, url)
    Linux => @linux.navigate(handle, url)
    Ohos => 0
    Unsupported => 0
  }
}

///|
fn native_load_html(handle : UInt64, html : Bytes) -> Int {
  match active_backend() {
    Windows => @windows.load_html(handle, html)
    MacOS => @macos.load_html(handle, html)
    Linux => @linux.load_html(handle, html)
    Ohos => 0
    Unsupported => 0
  }
}

///|
fn native_reload(handle : UInt64) -> Int {
  match active_backend() {
    Windows => @windows.reload(handle)
    MacOS => @macos.reload(handle)
    Linux => @linux.reload(handle)
    Ohos => @ohos.reload(handle)
    Unsupported => 0
  }
}

///|
fn native_stop(handle : UInt64) -> Int {
  match active_backend() {
    Windows => @windows.stop(handle)
    MacOS => @macos.stop(handle)
    Linux => @linux.stop(handle)
    Ohos => 0
    Unsupported => 0
  }
}

///|
fn native_go_back(handle : UInt64) -> Int {
  match active_backend() {
    Windows => @windows.go_back(handle)
    MacOS => @macos.go_back(handle)
    Linux => @linux.go_back(handle)
    Ohos => 0
    Unsupported => 0
  }
}

///|
fn native_go_forward(handle : UInt64) -> Int {
  match active_backend() {
    Windows => @windows.go_forward(handle)
    MacOS => @macos.go_forward(handle)
    Linux => @linux.go_forward(handle)
    Ohos => 0
    Unsupported => 0
  }
}

///|
fn native_add_init_script(handle : UInt64, script : Bytes) -> Int {
  match active_backend() {
    Windows => @windows.add_init_script(handle, script)
    MacOS => @macos.add_init_script(handle, script)
    Linux => @linux.add_init_script(handle, script)
    Ohos => 0
    Unsupported => 0
  }
}

///|
fn native_set_zoom(handle : UInt64, factor : Double) -> Int {
  match active_backend() {
    Windows => @windows.set_zoom(handle, factor)
    MacOS => @macos.set_zoom(handle, factor)
    Linux => @linux.set_zoom(handle, factor)
    Ohos => 0
    Unsupported => 0
  }
}

///|
fn native_open_devtools(handle : UInt64) -> Int {
  match active_backend() {
    Windows => @windows.open_devtools(handle)
    MacOS => @macos.open_devtools(handle)
    Linux => @linux.open_devtools(handle)
    Ohos => 0
    Unsupported => 0
  }
}

///|
fn native_open_print_dialog(handle : UInt64) -> Int {
  match active_backend() {
    Windows => @windows.open_print_dialog(handle)
    MacOS => @macos.open_print_dialog(handle)
    Linux => @linux.open_print_dialog(handle)
    Ohos => 0
    Unsupported => 0
  }
}

///|
fn native_show_file_dialog(
  handle : UInt64,
  kind : Int,
  title : Bytes,
  filters : Bytes,
  default_name : Bytes,
  initial_directory : Bytes,
  status : Ref[Int],
) -> Bytes {
  match active_backend() {
    Windows =>
      @windows.show_file_dialog(
        handle, kind, title, filters, default_name, initial_directory, status,
      )
    MacOS =>
      @macos.show_file_dialog(
        handle, kind, title, filters, default_name, initial_directory, status,
      )
    Linux =>
      @linux.show_file_dialog(
        handle, kind, title, filters, default_name, initial_directory, status,
      )
    Ohos | Unsupported => {
      status.val = -1
      b""
    }
  }
}

///|
fn native_eval(handle : UInt64, script : Bytes, request_id : Bytes) -> Int {
  match active_backend() {
    Windows => @windows.eval(handle, script, request_id)
    MacOS => @macos.eval(handle, script, request_id)
    Linux => @linux.eval(handle, script, request_id)
    Ohos => @ohos.eval(handle, script)
    Unsupported => 0
  }
}

///|
fn native_post_message(handle : UInt64, message : Bytes) -> Int {
  match active_backend() {
    Windows => @windows.post_message(handle, message)
    MacOS => @macos.post_message(handle, message)
    Linux => @linux.post_message(handle, message)
    Ohos => 0
    Unsupported => 0
  }
}

///|
fn native_attach_ohos(web_tag : Bytes) -> UInt64 {
  match active_backend() {
    Ohos => @ohos.attach(web_tag)
    _ => 0
  }
}

///|
fn native_start_ohos(handle : UInt64) -> Unit {
  match active_backend() {
    Ohos => @ohos.start(handle)
    _ => ()
  }
}
