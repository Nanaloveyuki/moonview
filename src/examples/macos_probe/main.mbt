///|
fn main {
  if !@moonview.available() {
    abort("moonview macOS probe: WKWebView unavailable")
  }
  println("moonview macOS probe: WKWebView available")
}
