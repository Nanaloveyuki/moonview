#if defined(__APPLE__)

#include <CoreGraphics/CoreGraphics.h>
#include <objc/message.h>
#include <objc/runtime.h>

#include <moonbit.h>

#include <atomic>
#include <cstdint>
#include <cstring>
#include <memory>
#include <string>
#include <unordered_map>

namespace {

enum EventKind : int32_t {
  kReady = 1,
  kCreationFailed = 2,
  kMessage = 3,
  kNavigationStarting = 4,
  kSourceChanged = 5,
  kNavigationCompleted = 6,
  kDocumentTitleChanged = 7,
  kHistoryChanged = 8,
  kScriptCompleted = 9,
};

using EventTrampoline = void (*)(void *, uint64_t, int32_t, moonbit_bytes_t,
                                 moonbit_bytes_t, int32_t);
using NavigationTrampoline = int32_t (*)(void *, uint64_t, moonbit_bytes_t);

EventTrampoline g_event_trampoline = nullptr;
void *g_event_closure = nullptr;
NavigationTrampoline g_navigation_trampoline = nullptr;
void *g_navigation_closure = nullptr;
std::atomic<uint64_t> g_next_view_handle{1};

template <typename Return, typename... Args>
Return send(id receiver, SEL selector, Args... args) {
  using Function = Return (*)(id, SEL, Args...);
  return reinterpret_cast<Function>(objc_msgSend)(receiver, selector, args...);
}

SEL selector(const char *name) {
  return sel_registerName(name);
}

id class_object(const char *name) {
  return reinterpret_cast<id>(objc_getClass(name));
}

void release_object(id object) {
  if (object != nil) {
    send<void>(object, selector("release"));
  }
}

moonbit_bytes_t make_bytes(const std::string &value) {
  moonbit_bytes_t bytes = moonbit_make_bytes(static_cast<int32_t>(value.size()), 0);
  if (!value.empty()) {
    std::memcpy(bytes, value.data(), value.size());
  }
  return bytes;
}

std::string bytes_to_utf8(moonbit_bytes_t bytes) {
  if (bytes == nullptr) {
    return "";
  }
  const int32_t size = Moonbit_array_length(bytes);
  return size > 0 ? std::string(reinterpret_cast<const char *>(bytes), size) : "";
}

id string_object(const std::string &value) {
  id text = send<id>(class_object("NSString"), selector("alloc"));
  return send<id, const char *, unsigned long, unsigned long>(
      text, selector("initWithBytes:length:encoding:"), value.data(),
      static_cast<unsigned long>(value.size()), 4UL);
}

std::string utf8_string(id text) {
  if (text == nil) {
    return "";
  }
  const char *value = send<const char *>(text, selector("UTF8String"));
  return value == nullptr ? "" : value;
}

std::string encode_base64(const std::string &value) {
  static constexpr char alphabet[] =
      "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
  std::string encoded;
  encoded.reserve(((value.size() + 2) / 3) * 4);
  for (size_t index = 0; index < value.size(); index += 3) {
    const uint32_t first = static_cast<unsigned char>(value[index]);
    const uint32_t second = index + 1 < value.size() ?
        static_cast<unsigned char>(value[index + 1]) : 0;
    const uint32_t third = index + 2 < value.size() ?
        static_cast<unsigned char>(value[index + 2]) : 0;
    const uint32_t group = (first << 16) | (second << 8) | third;
    encoded += alphabet[(group >> 18) & 0x3F];
    encoded += alphabet[(group >> 12) & 0x3F];
    encoded += index + 1 < value.size() ? alphabet[(group >> 6) & 0x3F] : '=';
    encoded += index + 2 < value.size() ? alphabet[group & 0x3F] : '=';
  }
  return encoded;
}

int base64_value(char value) {
  if (value >= 'A' && value <= 'Z') return value - 'A';
  if (value >= 'a' && value <= 'z') return value - 'a' + 26;
  if (value >= '0' && value <= '9') return value - '0' + 52;
  if (value == '+') return 62;
  if (value == '/') return 63;
  return -1;
}

std::string decode_base64(const std::string &value) {
  std::string decoded;
  uint32_t accumulator = 0;
  int bits = 0;
  for (char character : value) {
    if (character == '=') {
      break;
    }
    const int digit = base64_value(character);
    if (digit < 0) {
      return "";
    }
    accumulator = (accumulator << 6) | static_cast<uint32_t>(digit);
    bits += 6;
    if (bits >= 8) {
      bits -= 8;
      decoded += static_cast<char>((accumulator >> bits) & 0xFF);
    }
  }
  return decoded;
}

std::string javascript_string(const std::string &value) {
  std::string result = "\"";
  for (unsigned char character : value) {
    switch (character) {
    case '\\': result += "\\\\"; break;
    case '\"': result += "\\\""; break;
    case '\n': result += "\\n"; break;
    case '\r': result += "\\r"; break;
    case '\t': result += "\\t"; break;
    default:
      if (character < 0x20) {
        static constexpr char hex[] = "0123456789abcdef";
        result += "\\u00";
        result += hex[(character >> 4) & 0x0F];
        result += hex[character & 0x0F];
      } else {
        result += static_cast<char>(character);
      }
    }
  }
  result += "\"";
  return result;
}

std::string bridge_script() {
  return R"JS((() => {
  const send = (kind, ...values) => {
    const encode = value => btoa(unescape(encodeURIComponent(String(value))));
    window.webkit.messageHandlers.moonview.postMessage(
      kind + ':' + values.map(encode).join(':'));
  };
  const api = window.moonview || {};
  api.postMessage = value => send('m', value);
  api._deliver = value => { if (typeof api.onmessage === 'function') api.onmessage({ data: value }); };
  if (!Object.prototype.hasOwnProperty.call(api, 'onmessage')) api.onmessage = null;
  window.moonview = api;
})();)JS";
}

struct View {
  uint64_t handle = 0;
  id parent = nil;
  id webview = nil;
  id content_manager = nil;
  id navigation_delegate = nil;
  id message_delegate = nil;
  std::string initial_url;
  std::string initial_html;
  bool started = false;
};

std::unordered_map<uint64_t, std::unique_ptr<View>> g_views;
std::unordered_map<id, View *> g_navigation_views;
std::unordered_map<id, View *> g_message_views;

View *find_view(uint64_t handle) {
  const auto found = g_views.find(handle);
  return found == g_views.end() ? nullptr : found->second.get();
}

void emit_event(View *view, EventKind kind, const std::string &value = "",
                const std::string &detail = "", int32_t code = 0) {
  if (view == nullptr || g_event_trampoline == nullptr || g_event_closure == nullptr) {
    return;
  }
  g_event_trampoline(g_event_closure, view->handle, kind, make_bytes(value),
                     make_bytes(detail), code);
}

bool allow_navigation(View *view, const std::string &url) {
  if (g_navigation_trampoline == nullptr || g_navigation_closure == nullptr) {
    return true;
  }
  return g_navigation_trampoline(g_navigation_closure, view->handle, make_bytes(url)) != 0;
}

std::string webview_url(id webview) {
  id url = send<id>(webview, selector("URL"));
  id absolute = url == nil ? nil : send<id>(url, selector("absoluteString"));
  return utf8_string(absolute);
}

void emit_history(View *view) {
  const bool can_go_back = send<BOOL>(view->webview, selector("canGoBack")) != NO;
  const bool can_go_forward = send<BOOL>(view->webview, selector("canGoForward")) != NO;
  emit_event(view, kHistoryChanged, "", std::string("back=") +
      (can_go_back ? "1" : "0") + ";forward=" + (can_go_forward ? "1" : "0"));
}

void set_frame(View *view, int32_t x, int32_t y, int32_t width, int32_t height) {
  const CGRect parent_bounds = send<CGRect>(view->parent, selector("bounds"));
  const BOOL flipped = send<BOOL>(view->parent, selector("isFlipped"));
  const CGFloat origin_y = flipped != NO ? static_cast<CGFloat>(y) :
      parent_bounds.size.height - static_cast<CGFloat>(y + height);
  const CGRect frame = CGRectMake(static_cast<CGFloat>(x), origin_y,
                                  static_cast<CGFloat>(width), static_cast<CGFloat>(height));
  send<void, CGRect>(view->webview, selector("setFrame:"), frame);
}

void add_document_script(View *view, const std::string &script) {
  if (script.empty()) {
    return;
  }
  id source = string_object(script);
  id user_script = send<id>(class_object("WKUserScript"), selector("alloc"));
  user_script = send<id, id, long, BOOL>(
      user_script, selector("initWithSource:injectionTime:forMainFrameOnly:"), source,
      0L, YES);
  send<void, id>(view->content_manager, selector("addUserScript:"), user_script);
  release_object(user_script);
  release_object(source);
}

void execute_javascript(View *view, const std::string &script) {
  if (view == nullptr || view->webview == nil) {
    return;
  }
  id source = string_object(script);
  send<void, id, id>(view->webview, selector("evaluateJavaScript:completionHandler:"), source, nil);
  release_object(source);
}

struct DecisionHandlerBlock {
  void *isa;
  int flags;
  int reserved;
  void (*invoke)(void *, long);
};

void call_decision_handler(id handler, bool allowed) {
  DecisionHandlerBlock *block = reinterpret_cast<DecisionHandlerBlock *>(handler);
  if (block != nullptr && block->invoke != nullptr) {
    block->invoke(block, allowed ? 1L : 0L);
  }
}

void navigation_decide(id delegate, SEL, id, id action, id decision_handler) {
  const auto found = g_navigation_views.find(delegate);
  if (found == g_navigation_views.end()) {
    call_decision_handler(decision_handler, false);
    return;
  }
  id request = send<id>(action, selector("request"));
  id url = request == nil ? nil : send<id>(request, selector("URL"));
  id absolute = url == nil ? nil : send<id>(url, selector("absoluteString"));
  const std::string text = utf8_string(absolute);
  emit_event(found->second, kNavigationStarting, text);
  call_decision_handler(decision_handler, allow_navigation(found->second, text));
}

void navigation_committed(id delegate, SEL, id webview, id) {
  const auto found = g_navigation_views.find(delegate);
  if (found != g_navigation_views.end()) {
    emit_event(found->second, kSourceChanged, webview_url(webview));
  }
}

void navigation_finished(id delegate, SEL, id webview, id) {
  const auto found = g_navigation_views.find(delegate);
  if (found != g_navigation_views.end()) {
    emit_event(found->second, kNavigationCompleted, webview_url(webview));
    emit_history(found->second);
    id title = send<id>(webview, selector("title"));
    emit_event(found->second, kDocumentTitleChanged, utf8_string(title));
  }
}

void navigation_failed(id delegate, SEL, id webview, id, id error) {
  const auto found = g_navigation_views.find(delegate);
  if (found == g_navigation_views.end()) {
    return;
  }
  id description = error == nil ? nil : send<id>(error, selector("localizedDescription"));
  const long code = error == nil ? 1L : send<long>(error, selector("code"));
  emit_event(found->second, kNavigationCompleted, webview_url(webview),
             utf8_string(description), static_cast<int32_t>(code));
}

void script_message_received(id delegate, SEL, id, id message) {
  const auto found = g_message_views.find(delegate);
  if (found == g_message_views.end()) {
    return;
  }
  id body = send<id>(message, selector("body"));
  id description = body == nil ? nil : send<id>(body, selector("description"));
  const std::string text = utf8_string(description);
  if (text.size() < 3 || text[1] != ':') {
    return;
  }
  const char kind = text[0];
  const size_t separator = text.find(':', 2);
  if (kind == 'm') {
    emit_event(found->second, kMessage, decode_base64(text.substr(2)));
  } else if ((kind == 'e' || kind == 'f') && separator != std::string::npos) {
    const std::string request_id = decode_base64(text.substr(2, separator - 2));
    const std::string payload = decode_base64(text.substr(separator + 1));
    emit_event(found->second, kScriptCompleted, payload, request_id, kind == 'e' ? 0 : 1);
  }
}

Class navigation_delegate_class() {
  static Class delegate = nullptr;
  if (delegate != nullptr) {
    return delegate;
  }
  delegate = objc_allocateClassPair(reinterpret_cast<Class>(class_object("NSObject")),
                                    "MoonviewNavigationDelegate", 0);
  class_addMethod(delegate, selector("webView:decidePolicyForNavigationAction:decisionHandler:"),
                  reinterpret_cast<IMP>(navigation_decide), "v@:@@@");
  class_addMethod(delegate, selector("webView:didCommitNavigation:"),
                  reinterpret_cast<IMP>(navigation_committed), "v@:@@");
  class_addMethod(delegate, selector("webView:didFinishNavigation:"),
                  reinterpret_cast<IMP>(navigation_finished), "v@:@@");
  class_addMethod(delegate, selector("webView:didFailNavigation:withError:"),
                  reinterpret_cast<IMP>(navigation_failed), "v@:@@@");
  class_addMethod(delegate, selector("webView:didFailProvisionalNavigation:withError:"),
                  reinterpret_cast<IMP>(navigation_failed), "v@:@@@");
  objc_registerClassPair(delegate);
  return delegate;
}

Class message_delegate_class() {
  static Class delegate = nullptr;
  if (delegate != nullptr) {
    return delegate;
  }
  delegate = objc_allocateClassPair(reinterpret_cast<Class>(class_object("NSObject")),
                                    "MoonviewScriptMessageDelegate", 0);
  class_addMethod(delegate, selector("userContentController:didReceiveScriptMessage:"),
                  reinterpret_cast<IMP>(script_message_received), "v@:@@");
  objc_registerClassPair(delegate);
  return delegate;
}

void load_initial_content(View *view) {
  if (!view->initial_html.empty()) {
    id html = string_object(view->initial_html);
    send<id, id, id>(view->webview, selector("loadHTMLString:baseURL:"), html, nil);
    release_object(html);
  } else if (!view->initial_url.empty()) {
    id text = string_object(view->initial_url);
    id url = send<id>(class_object("NSURL"), selector("alloc"));
    url = send<id, id>(url, selector("initWithString:"), text);
    id request = send<id>(class_object("NSURLRequest"), selector("alloc"));
    request = send<id, id>(request, selector("initWithURL:"), url);
    send<id, id>(view->webview, selector("loadRequest:"), request);
    release_object(request);
    release_object(url);
    release_object(text);
  }
}

bool is_main_thread() {
  return send<BOOL>(class_object("NSThread"), selector("isMainThread")) != NO;
}

} // namespace

extern "C" MOONBIT_FFI_EXPORT void moonview_macos_install_event_callback(
    EventTrampoline trampoline, void *closure) {
  if (g_event_closure != nullptr) {
    moonbit_decref(g_event_closure);
  }
  g_event_trampoline = trampoline;
  g_event_closure = closure;
}

extern "C" MOONBIT_FFI_EXPORT void moonview_macos_install_navigation_callback(
    NavigationTrampoline trampoline, void *closure) {
  if (g_navigation_closure != nullptr) {
    moonbit_decref(g_navigation_closure);
  }
  g_navigation_trampoline = trampoline;
  g_navigation_closure = closure;
}

extern "C" MOONBIT_FFI_EXPORT int32_t moonview_macos_available() {
  return class_object("WKWebView") != nil ? 1 : 0;
}

extern "C" MOONBIT_FFI_EXPORT uint64_t moonview_macos_create(
    uint64_t parent_handle, int32_t x, int32_t y, int32_t width, int32_t height,
    moonbit_bytes_t initial_url, moonbit_bytes_t initial_html,
    moonbit_bytes_t initialization_script, moonbit_bytes_t user_agent) {
  if (!is_main_thread()) {
    return 0;
  }
  id parent = reinterpret_cast<id>(static_cast<uintptr_t>(parent_handle));
  if (parent == nil || class_object("WKWebView") == nil) {
    return 0;
  }
  auto view = std::make_unique<View>();
  view->handle = g_next_view_handle.fetch_add(1);
  view->parent = parent;
  view->content_manager = send<id>(class_object("WKUserContentController"), selector("alloc"));
  view->content_manager = send<id>(view->content_manager, selector("init"));
  view->navigation_delegate = send<id>(reinterpret_cast<id>(navigation_delegate_class()),
                                       selector("new"));
  view->message_delegate = send<id>(reinterpret_cast<id>(message_delegate_class()),
                                    selector("new"));
  g_navigation_views.emplace(view->navigation_delegate, view.get());
  g_message_views.emplace(view->message_delegate, view.get());
  id channel = string_object("moonview");
  send<void, id, id>(view->content_manager, selector("addScriptMessageHandler:name:"),
                     view->message_delegate, channel);
  release_object(channel);
  id configuration = send<id>(class_object("WKWebViewConfiguration"), selector("alloc"));
  configuration = send<id>(configuration, selector("init"));
  send<void, id>(configuration, selector("setUserContentController:"), view->content_manager);
  view->webview = send<id>(class_object("WKWebView"), selector("alloc"));
  const CGRect frame = CGRectZero;
  view->webview = send<id, CGRect, id>(view->webview,
      selector("initWithFrame:configuration:"), frame, configuration);
  release_object(configuration);
  if (view->webview == nil) {
    g_navigation_views.erase(view->navigation_delegate);
    g_message_views.erase(view->message_delegate);
    release_object(view->navigation_delegate);
    release_object(view->message_delegate);
    release_object(view->content_manager);
    return 0;
  }
  const std::string configured_user_agent = bytes_to_utf8(user_agent);
  if (!configured_user_agent.empty()) {
    id agent = string_object(configured_user_agent);
    send<void, id>(view->webview, selector("setCustomUserAgent:"), agent);
    release_object(agent);
  }
  send<void, id>(view->webview, selector("setNavigationDelegate:"), view->navigation_delegate);
  add_document_script(view.get(), bridge_script());
  add_document_script(view.get(), bytes_to_utf8(initialization_script));
  view->initial_url = bytes_to_utf8(initial_url);
  view->initial_html = bytes_to_utf8(initial_html);
  set_frame(view.get(), x, y, width, height);
  send<void, id>(parent, selector("addSubview:"), view->webview);
  const uint64_t handle = view->handle;
  g_views.emplace(handle, std::move(view));
  return handle;
}

extern "C" MOONBIT_FFI_EXPORT void moonview_macos_start(uint64_t handle) {
  View *view = find_view(handle);
  if (view == nullptr || view->started) {
    return;
  }
  view->started = true;
  emit_event(view, kReady);
  load_initial_content(view);
}

extern "C" MOONBIT_FFI_EXPORT int32_t moonview_macos_destroy(uint64_t handle) {
  const auto found = g_views.find(handle);
  if (found == g_views.end()) {
    return 1;
  }
  if (!is_main_thread()) {
    return 0;
  }
  View *view = found->second.get();
  send<void, id>(view->webview, selector("setNavigationDelegate:"), nil);
  id channel = string_object("moonview");
  send<void, id>(view->content_manager, selector("removeScriptMessageHandlerForName:"), channel);
  release_object(channel);
  send<void>(view->webview, selector("removeFromSuperview"));
  g_navigation_views.erase(view->navigation_delegate);
  g_message_views.erase(view->message_delegate);
  release_object(view->webview);
  release_object(view->content_manager);
  release_object(view->navigation_delegate);
  release_object(view->message_delegate);
  g_views.erase(found);
  return 1;
}

extern "C" MOONBIT_FFI_EXPORT void moonview_macos_set_bounds(
    uint64_t handle, int32_t x, int32_t y, int32_t width, int32_t height) {
  View *view = find_view(handle);
  if (view != nullptr) {
    set_frame(view, x, y, width, height);
  }
}

extern "C" MOONBIT_FFI_EXPORT void moonview_macos_set_visible(uint64_t handle,
                                                                  int32_t visible) {
  View *view = find_view(handle);
  if (view != nullptr) {
    send<void, BOOL>(view->webview, selector("setHidden:"), visible == 0 ? YES : NO);
  }
}

extern "C" MOONBIT_FFI_EXPORT void moonview_macos_focus(uint64_t handle) {
  View *view = find_view(handle);
  if (view == nullptr) {
    return;
  }
  id window = send<id>(view->webview, selector("window"));
  if (window != nil) {
    send<BOOL, id>(window, selector("makeFirstResponder:"), view->webview);
  }
}

extern "C" MOONBIT_FFI_EXPORT void moonview_macos_navigate(uint64_t handle,
                                                              moonbit_bytes_t url) {
  View *view = find_view(handle);
  if (view == nullptr) {
    return;
  }
  const std::string text = bytes_to_utf8(url);
  id value = string_object(text);
  id native_url = send<id>(class_object("NSURL"), selector("alloc"));
  native_url = send<id, id>(native_url, selector("initWithString:"), value);
  id request = send<id>(class_object("NSURLRequest"), selector("alloc"));
  request = send<id, id>(request, selector("initWithURL:"), native_url);
  send<id, id>(view->webview, selector("loadRequest:"), request);
  release_object(request);
  release_object(native_url);
  release_object(value);
}

extern "C" MOONBIT_FFI_EXPORT void moonview_macos_load_html(uint64_t handle,
                                                               moonbit_bytes_t html) {
  View *view = find_view(handle);
  if (view != nullptr) {
    id value = string_object(bytes_to_utf8(html));
    send<id, id, id>(view->webview, selector("loadHTMLString:baseURL:"), value, nil);
    release_object(value);
  }
}

extern "C" MOONBIT_FFI_EXPORT void moonview_macos_reload(uint64_t handle) {
  View *view = find_view(handle);
  if (view != nullptr) {
    send<id>(view->webview, selector("reload"));
  }
}

extern "C" MOONBIT_FFI_EXPORT void moonview_macos_stop(uint64_t handle) {
  View *view = find_view(handle);
  if (view != nullptr) {
    send<void>(view->webview, selector("stopLoading"));
  }
}

extern "C" MOONBIT_FFI_EXPORT void moonview_macos_go_back(uint64_t handle) {
  View *view = find_view(handle);
  if (view != nullptr && send<BOOL>(view->webview, selector("canGoBack")) != NO) {
    send<id>(view->webview, selector("goBack"));
  }
}

extern "C" MOONBIT_FFI_EXPORT void moonview_macos_go_forward(uint64_t handle) {
  View *view = find_view(handle);
  if (view != nullptr && send<BOOL>(view->webview, selector("canGoForward")) != NO) {
    send<id>(view->webview, selector("goForward"));
  }
}

extern "C" MOONBIT_FFI_EXPORT void moonview_macos_init(uint64_t handle,
                                                          moonbit_bytes_t script) {
  View *view = find_view(handle);
  if (view != nullptr) {
    add_document_script(view, bytes_to_utf8(script));
  }
}

extern "C" MOONBIT_FFI_EXPORT void moonview_macos_set_zoom(uint64_t handle,
                                                              double factor) {
  View *view = find_view(handle);
  if (view != nullptr) {
    send<void, CGFloat>(view->webview, selector("setPageZoom:"),
                        static_cast<CGFloat>(factor));
  }
}

extern "C" MOONBIT_FFI_EXPORT int32_t moonview_macos_open_devtools(uint64_t) {
  return 0;
}

extern "C" MOONBIT_FFI_EXPORT void moonview_macos_eval(uint64_t handle,
                                                          moonbit_bytes_t script,
                                                          moonbit_bytes_t request_id) {
  View *view = find_view(handle);
  if (view == nullptr) {
    return;
  }
  const std::string wrapped = "Promise.resolve().then(() => eval(" +
      javascript_string(bytes_to_utf8(script)) + ")).then(value => " +
      "window.webkit.messageHandlers.moonview.postMessage('e:" +
      encode_base64(bytes_to_utf8(request_id)) + ":' + btoa(unescape(encodeURIComponent(JSON.stringify(value) ?? 'null')))), " +
      "error => window.webkit.messageHandlers.moonview.postMessage('f:" +
      encode_base64(bytes_to_utf8(request_id)) + ":' + btoa(unescape(encodeURIComponent(String(error))))));";
  execute_javascript(view, wrapped);
}

extern "C" MOONBIT_FFI_EXPORT void moonview_macos_post_message(uint64_t handle,
                                                                  moonbit_bytes_t message) {
  View *view = find_view(handle);
  if (view != nullptr) {
    execute_javascript(view, "window.moonview && window.moonview._deliver(" +
        javascript_string(bytes_to_utf8(message)) + ");");
  }
}

#else

#include <moonbit.h>

using EventTrampoline = void (*)(void *, uint64_t, int32_t, moonbit_bytes_t,
                                 moonbit_bytes_t, int32_t);
using NavigationTrampoline = int32_t (*)(void *, uint64_t, moonbit_bytes_t);

extern "C" MOONBIT_FFI_EXPORT void moonview_macos_install_event_callback(EventTrampoline, void *) {}
extern "C" MOONBIT_FFI_EXPORT void moonview_macos_install_navigation_callback(NavigationTrampoline, void *) {}
extern "C" MOONBIT_FFI_EXPORT int32_t moonview_macos_available() { return 0; }
extern "C" MOONBIT_FFI_EXPORT uint64_t moonview_macos_create(uint64_t, int32_t, int32_t, int32_t, int32_t, moonbit_bytes_t, moonbit_bytes_t, moonbit_bytes_t, moonbit_bytes_t) { return 0; }
extern "C" MOONBIT_FFI_EXPORT void moonview_macos_start(uint64_t) {}
extern "C" MOONBIT_FFI_EXPORT int32_t moonview_macos_destroy(uint64_t) { return 0; }
extern "C" MOONBIT_FFI_EXPORT void moonview_macos_set_bounds(uint64_t, int32_t, int32_t, int32_t, int32_t) {}
extern "C" MOONBIT_FFI_EXPORT void moonview_macos_set_visible(uint64_t, int32_t) {}
extern "C" MOONBIT_FFI_EXPORT void moonview_macos_focus(uint64_t) {}
extern "C" MOONBIT_FFI_EXPORT void moonview_macos_navigate(uint64_t, moonbit_bytes_t) {}
extern "C" MOONBIT_FFI_EXPORT void moonview_macos_load_html(uint64_t, moonbit_bytes_t) {}
extern "C" MOONBIT_FFI_EXPORT void moonview_macos_reload(uint64_t) {}
extern "C" MOONBIT_FFI_EXPORT void moonview_macos_stop(uint64_t) {}
extern "C" MOONBIT_FFI_EXPORT void moonview_macos_go_back(uint64_t) {}
extern "C" MOONBIT_FFI_EXPORT void moonview_macos_go_forward(uint64_t) {}
extern "C" MOONBIT_FFI_EXPORT void moonview_macos_init(uint64_t, moonbit_bytes_t) {}
extern "C" MOONBIT_FFI_EXPORT void moonview_macos_set_zoom(uint64_t, double) {}
extern "C" MOONBIT_FFI_EXPORT int32_t moonview_macos_open_devtools(uint64_t) { return 0; }
extern "C" MOONBIT_FFI_EXPORT void moonview_macos_eval(uint64_t, moonbit_bytes_t, moonbit_bytes_t) {}
extern "C" MOONBIT_FFI_EXPORT void moonview_macos_post_message(uint64_t, moonbit_bytes_t) {}

#endif
