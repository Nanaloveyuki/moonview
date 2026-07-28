# Moonview Android Adapter

`Nanaloveyuki/moonview/android` is an optional native package backed only by
`Nanaloveyuki/ajni/webview`. It does not import Moonview's desktop root package
and does not cause desktop SDK linkage.

Before calling MoonBit, the Android application must initialize ajni and attach
the Activity-owned container on Android's main thread:

```kotlin
import dev.nanaloveyuki.ajni.host.NativeBridge

NativeBridge.initialize(applicationContext)
NativeBridge.attachWebViewContainer(container)
```

The app's Android CMake integration must include ajni's core and WebView native
stubs, as documented by ajni's `android/app/src/main/cpp/CMakeLists.txt`, and
must build its MoonBit entry package with:

```text
MOONVIEW_NATIVE_BACKEND=android
```

## Use

The Android adapter has an explicit single HTTPS asset origin. URLs and HTML
base URLs must remain beneath `trusted_origin + "/assets/"`; the host disables
file/content access and does not install a JavaScript interface.

```mbt check
///|
pub fn create_browser() -> Unit raise @ajni.JniError {
  let options = @android.AndroidWebViewOptions::new(
    bounds=@android.AndroidBounds::new(x=0, y=0, width=1080, height=1600),
    trusted_origin="https://app.example.test",
    initial_content=Url("https://app.example.test/assets/index.html"),
    document_start_scripts=["globalThis.appReady = true"],
    on_event=event => {
      match event {
        Ready => ()
        PageMessage(message) => println(message.body)
        AssetRequest(_request) => ()
        OperationFailed(operation_id, message) =>
          println("\{operation_id}: \{message}")
        _ => ()
      }
    },
  )
  let view = @android.AndroidWebView::create(options, "create-browser")
  view.set_bounds(
    @android.AndroidBounds::new(x=0, y=0, width=1080, height=1600),
  )
}
```

Every accepted asynchronous create, navigation, HTML load, script, page post,
asset response, and destroy command takes a non-empty caller operation ID.
Failures retain that ID in `CreationFailed` or `OperationFailed`.

`AssetRequest` is delivered from the Kotlin asset loader after its request
thread has posted safely to the Android main Looper and JNI. Answer it with
`respond_asset` before the configured timeout. Default limits are 1 MiB per
page message, 32 pending assets, 8 MiB per response, and 10 seconds per asset
response. Set an individual `AndroidResourceLimits` field to `0` to disable its
limit; negative values reject creation.

The adapter emits `PageMessage(body, origin, is_main_frame)` only through
AndroidX WebKit's origin-restricted `WebMessageListener`. It has no desktop
context/history API and it is not a synchronous navigation or popup policy
surface.
