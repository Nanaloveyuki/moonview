# Moonview Android Adapter

`Nanaloveyuki/moonview/android` is an optional native package backed only by
`Nanaloveyuki/ajni/webview`. It does not import Moonview's desktop root package
and does not cause desktop SDK linkage.

Run `moon update` once when a local MoonBit registry snapshot predates
`Nanaloveyuki/ajni@0.1.1`.

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

The initial adapter exposes create/destroy, bounds, URL/HTML loading, eval with
request IDs, and ready/navigation/title/script/failure events. It intentionally
does not expose desktop-only contexts, history, page messages, permissions,
custom protocols, or synchronous navigation/new-window policies yet.
