name = "Nanaloveyuki/moonview"

version = "0.1.0-beta.3"

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
  "openharmony",
  "arkweb",
  "desktop",
]

preferred_target = "native"

source = "src"

import {
  "Nanaloveyuki/ajni@0.2.0",
}

options(
  "--moonbit-unstable-prebuild": "build.js",
)
