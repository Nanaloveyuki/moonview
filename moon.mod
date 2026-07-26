name = "Nanaloveyuki/moonview"

version = "0.1.0"

description = "Direct native WebView embedding for MoonBit."

repository = "https://github.com/Nanaloveyuki/moonview"

license = "Apache-2.0"

keywords = [ "webview", "webview2", "windows", "desktop" ]

preferred_target = "native"

source = "src"

options(
  "--moonbit-unstable-prebuild": "build.js",
)
