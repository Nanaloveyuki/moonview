name = "Nanaloveyuki/moonview"

version = "0.1.0-alpha.1"

description = "Direct native WebView embedding for MoonBit."

repository = "https://github.com/Nanaloveyuki/moonview"

readme = "README.md"

license = "Apache-2.0"

keywords = [
  "webview",
  "webview2",
  "webkitgtk",
  "windows",
  "macos",
  "linux",
  "desktop",
]

preferred_target = "native"

source = "src"

options(
  "--moonbit-unstable-prebuild": "build.js",
)
