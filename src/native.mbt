///|
/// The native backend is selected by the target operating system at compile time.
priv enum NativeBackend {
  Windows
  MacOS
  Linux
  Unsupported
} derive(Eq)

///|
fn active_backend() -> NativeBackend {
  if @windows.available() != 0 {
    NativeBackend::Windows
  } else if @macos.available() != 0 {
    NativeBackend::MacOS
  } else if @linux.available() != 0 {
    NativeBackend::Linux
  } else {
    NativeBackend::Unsupported
  }
}

///|
fn native_available() -> Bool {
  active_backend() != NativeBackend::Unsupported
}

///|
fn install_native_callbacks(
  event_callback : (UInt64, Int, Bytes, Bytes, Int) -> Unit,
  navigation_callback : (UInt64, Bytes) -> Int,
) -> Unit {
  match active_backend() {
    NativeBackend::Windows => {
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
    }
    NativeBackend::MacOS => {
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
    }
    NativeBackend::Linux => {
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
    }
    NativeBackend::Unsupported => ()
  }
}

///|
fn native_create(
  parent_handle : UInt64,
  x : Int,
  y : Int,
  width : Int,
  height : Int,
  initial_url : Bytes,
  initial_html : Bytes,
  initialization_script : Bytes,
  user_agent : Bytes,
) -> UInt64 {
  match active_backend() {
    NativeBackend::Windows =>
      @windows.create(
        parent_handle, x, y, width, height, initial_url, initial_html, initialization_script,
        user_agent,
      )
    NativeBackend::MacOS =>
      @macos.create(
        parent_handle, x, y, width, height, initial_url, initial_html, initialization_script,
        user_agent,
      )
    NativeBackend::Linux =>
      @linux.create(
        parent_handle, x, y, width, height, initial_url, initial_html, initialization_script,
        user_agent,
      )
    NativeBackend::Unsupported => 0
  }
}

///|
fn native_start(handle : UInt64) -> Unit {
  match active_backend() {
    NativeBackend::Windows => @windows.start(handle)
    NativeBackend::MacOS => @macos.start(handle)
    NativeBackend::Linux => @linux.start(handle)
    NativeBackend::Unsupported => ()
  }
}

///|
fn native_destroy(handle : UInt64) -> Int {
  match active_backend() {
    NativeBackend::Windows => @windows.destroy(handle)
    NativeBackend::MacOS => @macos.destroy(handle)
    NativeBackend::Linux => @linux.destroy(handle)
    NativeBackend::Unsupported => 0
  }
}

///|
fn native_set_bounds(
  handle : UInt64,
  x : Int,
  y : Int,
  width : Int,
  height : Int,
) -> Unit {
  match active_backend() {
    NativeBackend::Windows => @windows.set_bounds(handle, x, y, width, height)
    NativeBackend::MacOS => @macos.set_bounds(handle, x, y, width, height)
    NativeBackend::Linux => @linux.set_bounds(handle, x, y, width, height)
    NativeBackend::Unsupported => ()
  }
}

///|
fn native_set_visible(handle : UInt64, visible : Bool) -> Unit {
  let visible = if visible { 1 } else { 0 }
  match active_backend() {
    NativeBackend::Windows => @windows.set_visible(handle, visible)
    NativeBackend::MacOS => @macos.set_visible(handle, visible)
    NativeBackend::Linux => @linux.set_visible(handle, visible)
    NativeBackend::Unsupported => ()
  }
}

///|
fn native_focus(handle : UInt64) -> Unit {
  match active_backend() {
    NativeBackend::Windows => @windows.focus(handle)
    NativeBackend::MacOS => @macos.focus(handle)
    NativeBackend::Linux => @linux.focus(handle)
    NativeBackend::Unsupported => ()
  }
}

///|
fn native_navigate(handle : UInt64, url : Bytes) -> Unit {
  match active_backend() {
    NativeBackend::Windows => @windows.navigate(handle, url)
    NativeBackend::MacOS => @macos.navigate(handle, url)
    NativeBackend::Linux => @linux.navigate(handle, url)
    NativeBackend::Unsupported => ()
  }
}

///|
fn native_load_html(handle : UInt64, html : Bytes) -> Unit {
  match active_backend() {
    NativeBackend::Windows => @windows.load_html(handle, html)
    NativeBackend::MacOS => @macos.load_html(handle, html)
    NativeBackend::Linux => @linux.load_html(handle, html)
    NativeBackend::Unsupported => ()
  }
}

///|
fn native_reload(handle : UInt64) -> Unit {
  match active_backend() {
    NativeBackend::Windows => @windows.reload(handle)
    NativeBackend::MacOS => @macos.reload(handle)
    NativeBackend::Linux => @linux.reload(handle)
    NativeBackend::Unsupported => ()
  }
}

///|
fn native_stop(handle : UInt64) -> Unit {
  match active_backend() {
    NativeBackend::Windows => @windows.stop(handle)
    NativeBackend::MacOS => @macos.stop(handle)
    NativeBackend::Linux => @linux.stop(handle)
    NativeBackend::Unsupported => ()
  }
}

///|
fn native_go_back(handle : UInt64) -> Unit {
  match active_backend() {
    NativeBackend::Windows => @windows.go_back(handle)
    NativeBackend::MacOS => @macos.go_back(handle)
    NativeBackend::Linux => @linux.go_back(handle)
    NativeBackend::Unsupported => ()
  }
}

///|
fn native_go_forward(handle : UInt64) -> Unit {
  match active_backend() {
    NativeBackend::Windows => @windows.go_forward(handle)
    NativeBackend::MacOS => @macos.go_forward(handle)
    NativeBackend::Linux => @linux.go_forward(handle)
    NativeBackend::Unsupported => ()
  }
}

///|
fn native_add_init_script(handle : UInt64, script : Bytes) -> Unit {
  match active_backend() {
    NativeBackend::Windows => @windows.add_init_script(handle, script)
    NativeBackend::MacOS => @macos.add_init_script(handle, script)
    NativeBackend::Linux => @linux.add_init_script(handle, script)
    NativeBackend::Unsupported => ()
  }
}

///|
fn native_set_zoom(handle : UInt64, factor : Double) -> Unit {
  match active_backend() {
    NativeBackend::Windows => @windows.set_zoom(handle, factor)
    NativeBackend::MacOS => @macos.set_zoom(handle, factor)
    NativeBackend::Linux => @linux.set_zoom(handle, factor)
    NativeBackend::Unsupported => ()
  }
}

///|
fn native_open_devtools(handle : UInt64) -> Int {
  match active_backend() {
    NativeBackend::Windows => @windows.open_devtools(handle)
    NativeBackend::MacOS => @macos.open_devtools(handle)
    NativeBackend::Linux => @linux.open_devtools(handle)
    NativeBackend::Unsupported => 0
  }
}

///|
fn native_eval(handle : UInt64, script : Bytes, request_id : Bytes) -> Unit {
  match active_backend() {
    NativeBackend::Windows => @windows.eval(handle, script, request_id)
    NativeBackend::MacOS => @macos.eval(handle, script, request_id)
    NativeBackend::Linux => @linux.eval(handle, script, request_id)
    NativeBackend::Unsupported => ()
  }
}

///|
fn native_post_message(handle : UInt64, message : Bytes) -> Unit {
  match active_backend() {
    NativeBackend::Windows => @windows.post_message(handle, message)
    NativeBackend::MacOS => @macos.post_message(handle, message)
    NativeBackend::Linux => @linux.post_message(handle, message)
    NativeBackend::Unsupported => ()
  }
}
