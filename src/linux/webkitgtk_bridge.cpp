#if defined(__linux__)

#include <gtk/gtk.h>
#include <webkit2/webkit2.h>

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

std::string encode_base64(const std::string &value) {
  gchar *encoded = g_base64_encode(reinterpret_cast<const guchar *>(value.data()), value.size());
  std::string result = encoded == nullptr ? "" : encoded;
  g_free(encoded);
  return result;
}

std::string decode_base64(const std::string &value) {
  gsize size = 0;
  guchar *decoded = g_base64_decode(value.c_str(), &size);
  std::string result = decoded == nullptr ? "" : std::string(reinterpret_cast<char *>(decoded), size);
  g_free(decoded);
  return result;
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
        char escaped[7];
        std::snprintf(escaped, sizeof(escaped), "\\u%04x", character);
        result += escaped;
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
  GtkFixed *parent = nullptr;
  WebKitWebView *webview = nullptr;
  WebKitUserContentManager *content_manager = nullptr;
  std::string initial_url;
  std::string initial_html;
  bool started = false;
};

std::unordered_map<uint64_t, std::unique_ptr<View>> g_views;

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

void emit_history(View *view) {
  const bool can_go_back = webkit_web_view_can_go_back(view->webview);
  const bool can_go_forward = webkit_web_view_can_go_forward(view->webview);
  emit_event(view, kHistoryChanged, "", std::string("back=") +
      (can_go_back ? "1" : "0") + ";forward=" + (can_go_forward ? "1" : "0"));
}

void add_document_script(View *view, const std::string &script) {
  if (script.empty()) {
    return;
  }
  WebKitUserScript *user_script = webkit_user_script_new(
      script.c_str(), WEBKIT_USER_CONTENT_INJECT_TOP_FRAME,
      WEBKIT_USER_SCRIPT_INJECT_AT_DOCUMENT_START, nullptr, nullptr);
  webkit_user_content_manager_add_script(view->content_manager, user_script);
  webkit_user_script_unref(user_script);
}

void execute_javascript(View *view, const std::string &script) {
  if (view == nullptr || view->webview == nullptr) {
    return;
  }
  webkit_web_view_evaluate_javascript(view->webview, script.c_str(), -1, nullptr,
                                      nullptr, nullptr, nullptr, nullptr);
}

void handle_message(WebKitUserContentManager *, WebKitJavascriptResult *result,
                    gpointer user_data) {
  View *view = static_cast<View *>(user_data);
  JSCValue *value = webkit_javascript_result_get_js_value(result);
  gchar *text = jsc_value_to_string(value);
  const std::string message = text == nullptr ? "" : text;
  g_free(text);
  if (message.size() < 3 || message[1] != ':') {
    return;
  }
  const char kind = message[0];
  const size_t separator = message.find(':', 2);
  if (kind == 'm') {
    emit_event(view, kMessage, decode_base64(message.substr(2)));
  } else if ((kind == 'e' || kind == 'f') && separator != std::string::npos) {
    const std::string request_id = decode_base64(message.substr(2, separator - 2));
    const std::string payload = decode_base64(message.substr(separator + 1));
    emit_event(view, kScriptCompleted, payload, request_id, kind == 'e' ? 0 : 1);
  }
}

gboolean handle_decide_policy(WebKitWebView *, WebKitPolicyDecision *decision,
                              WebKitPolicyDecisionType type, gpointer user_data) {
  if (type != WEBKIT_POLICY_DECISION_TYPE_NAVIGATION_ACTION &&
      type != WEBKIT_POLICY_DECISION_TYPE_NEW_WINDOW_ACTION) {
    return FALSE;
  }
  View *view = static_cast<View *>(user_data);
  WebKitNavigationAction *action =
      webkit_navigation_policy_decision_get_navigation_action(
          WEBKIT_NAVIGATION_POLICY_DECISION(decision));
  WebKitURIRequest *request = action == nullptr ? nullptr :
      webkit_navigation_action_get_request(action);
  const gchar *uri = request == nullptr ? nullptr : webkit_uri_request_get_uri(request);
  const std::string url = uri == nullptr ? "" : uri;
  emit_event(view, kNavigationStarting, url);
  if (allow_navigation(view, url)) {
    return FALSE;
  }
  webkit_policy_decision_ignore(decision);
  return TRUE;
}

void handle_load_changed(WebKitWebView *webview, WebKitLoadEvent event, gpointer user_data) {
  View *view = static_cast<View *>(user_data);
  const gchar *uri = webkit_web_view_get_uri(webview);
  const std::string url = uri == nullptr ? "" : uri;
  if (event == WEBKIT_LOAD_COMMITTED) {
    emit_event(view, kSourceChanged, url);
  } else if (event == WEBKIT_LOAD_FINISHED) {
    emit_event(view, kNavigationCompleted, url);
    emit_history(view);
  }
}

gboolean handle_load_failed(WebKitWebView *webview, WebKitLoadEvent, gchar *uri,
                            GError *error, gpointer user_data) {
  View *view = static_cast<View *>(user_data);
  const gchar *current_uri = uri == nullptr ? webkit_web_view_get_uri(webview) : uri;
  emit_event(view, kNavigationCompleted, current_uri == nullptr ? "" : current_uri,
             error == nullptr ? "Navigation failed" : error->message,
             error == nullptr ? 1 : error->code);
  return FALSE;
}

void handle_title_changed(WebKitWebView *webview, GParamSpec *, gpointer user_data) {
  const gchar *title = webkit_web_view_get_title(webview);
  emit_event(static_cast<View *>(user_data), kDocumentTitleChanged,
             title == nullptr ? "" : title);
}

void load_initial_content(View *view) {
  if (!view->initial_html.empty()) {
    webkit_web_view_load_html(view->webview, view->initial_html.c_str(), nullptr);
  } else if (!view->initial_url.empty()) {
    webkit_web_view_load_uri(view->webview, view->initial_url.c_str());
  }
}

} // namespace

extern "C" MOONBIT_FFI_EXPORT void moonview_linux_install_event_callback(
    EventTrampoline trampoline, void *closure) {
  if (g_event_closure != nullptr) {
    moonbit_decref(g_event_closure);
  }
  g_event_trampoline = trampoline;
  g_event_closure = closure;
}

extern "C" MOONBIT_FFI_EXPORT void moonview_linux_install_navigation_callback(
    NavigationTrampoline trampoline, void *closure) {
  if (g_navigation_closure != nullptr) {
    moonbit_decref(g_navigation_closure);
  }
  g_navigation_trampoline = trampoline;
  g_navigation_closure = closure;
}

extern "C" MOONBIT_FFI_EXPORT int32_t moonview_linux_available() {
  return gtk_get_major_version() == 3 ? 1 : 0;
}

extern "C" MOONBIT_FFI_EXPORT uint64_t moonview_linux_create(
    uint64_t parent_handle, int32_t x, int32_t y, int32_t width, int32_t height,
    moonbit_bytes_t initial_url, moonbit_bytes_t initial_html,
    moonbit_bytes_t initialization_script) {
  if (!gtk_init_check(nullptr, nullptr)) {
    return 0;
  }
  GtkWidget *parent_widget = reinterpret_cast<GtkWidget *>(static_cast<uintptr_t>(parent_handle));
  if (parent_widget == nullptr || !GTK_IS_FIXED(parent_widget)) {
    return 0;
  }
  auto view = std::make_unique<View>();
  view->handle = g_next_view_handle.fetch_add(1);
  view->parent = GTK_FIXED(parent_widget);
  view->content_manager = webkit_user_content_manager_new();
  if (!webkit_user_content_manager_register_script_message_handler(view->content_manager,
                                                                     "moonview")) {
    g_object_unref(view->content_manager);
    return 0;
  }
  view->webview = WEBKIT_WEB_VIEW(webkit_web_view_new_with_user_content_manager(
      view->content_manager));
  add_document_script(view.get(), bridge_script());
  add_document_script(view.get(), bytes_to_utf8(initialization_script));
  view->initial_url = bytes_to_utf8(initial_url);
  view->initial_html = bytes_to_utf8(initial_html);
  g_signal_connect(view->content_manager, "script-message-received::moonview",
                   G_CALLBACK(handle_message), view.get());
  g_signal_connect(view->webview, "decide-policy", G_CALLBACK(handle_decide_policy), view.get());
  g_signal_connect(view->webview, "load-changed", G_CALLBACK(handle_load_changed), view.get());
  g_signal_connect(view->webview, "load-failed", G_CALLBACK(handle_load_failed), view.get());
  g_signal_connect(view->webview, "notify::title", G_CALLBACK(handle_title_changed), view.get());
  gtk_widget_set_size_request(GTK_WIDGET(view->webview), width, height);
  gtk_fixed_put(view->parent, GTK_WIDGET(view->webview), x, y);
  const uint64_t handle = view->handle;
  g_views.emplace(handle, std::move(view));
  return handle;
}

extern "C" MOONBIT_FFI_EXPORT void moonview_linux_start(uint64_t handle) {
  View *view = find_view(handle);
  if (view == nullptr || view->started) {
    return;
  }
  view->started = true;
  gtk_widget_show(GTK_WIDGET(view->webview));
  emit_event(view, kReady);
  load_initial_content(view);
}

extern "C" MOONBIT_FFI_EXPORT int32_t moonview_linux_destroy(uint64_t handle) {
  const auto found = g_views.find(handle);
  if (found == g_views.end()) {
    return 1;
  }
  View *view = found->second.get();
  gtk_widget_destroy(GTK_WIDGET(view->webview));
  g_object_unref(view->content_manager);
  g_views.erase(found);
  return 1;
}

extern "C" MOONBIT_FFI_EXPORT void moonview_linux_set_bounds(
    uint64_t handle, int32_t x, int32_t y, int32_t width, int32_t height) {
  View *view = find_view(handle);
  if (view == nullptr) {
    return;
  }
  gtk_widget_set_size_request(GTK_WIDGET(view->webview), width, height);
  gtk_fixed_move(view->parent, GTK_WIDGET(view->webview), x, y);
}

extern "C" MOONBIT_FFI_EXPORT void moonview_linux_set_visible(uint64_t handle,
                                                                  int32_t visible) {
  View *view = find_view(handle);
  if (view != nullptr) {
    gtk_widget_set_visible(GTK_WIDGET(view->webview), visible != 0);
  }
}

extern "C" MOONBIT_FFI_EXPORT void moonview_linux_focus(uint64_t handle) {
  View *view = find_view(handle);
  if (view != nullptr) {
    gtk_widget_grab_focus(GTK_WIDGET(view->webview));
  }
}

extern "C" MOONBIT_FFI_EXPORT void moonview_linux_navigate(uint64_t handle,
                                                              moonbit_bytes_t url) {
  View *view = find_view(handle);
  if (view != nullptr) {
    webkit_web_view_load_uri(view->webview, bytes_to_utf8(url).c_str());
  }
}

extern "C" MOONBIT_FFI_EXPORT void moonview_linux_load_html(uint64_t handle,
                                                               moonbit_bytes_t html) {
  View *view = find_view(handle);
  if (view != nullptr) {
    webkit_web_view_load_html(view->webview, bytes_to_utf8(html).c_str(), nullptr);
  }
}

extern "C" MOONBIT_FFI_EXPORT void moonview_linux_reload(uint64_t handle) {
  View *view = find_view(handle);
  if (view != nullptr) {
    webkit_web_view_reload(view->webview);
  }
}

extern "C" MOONBIT_FFI_EXPORT void moonview_linux_stop(uint64_t handle) {
  View *view = find_view(handle);
  if (view != nullptr) {
    webkit_web_view_stop_loading(view->webview);
  }
}

extern "C" MOONBIT_FFI_EXPORT void moonview_linux_go_back(uint64_t handle) {
  View *view = find_view(handle);
  if (view != nullptr && webkit_web_view_can_go_back(view->webview)) {
    webkit_web_view_go_back(view->webview);
  }
}

extern "C" MOONBIT_FFI_EXPORT void moonview_linux_go_forward(uint64_t handle) {
  View *view = find_view(handle);
  if (view != nullptr && webkit_web_view_can_go_forward(view->webview)) {
    webkit_web_view_go_forward(view->webview);
  }
}

extern "C" MOONBIT_FFI_EXPORT void moonview_linux_init(uint64_t handle,
                                                          moonbit_bytes_t script) {
  View *view = find_view(handle);
  if (view != nullptr) {
    add_document_script(view, bytes_to_utf8(script));
  }
}

extern "C" MOONBIT_FFI_EXPORT void moonview_linux_eval(uint64_t handle,
                                                          moonbit_bytes_t script,
                                                          moonbit_bytes_t request_id) {
  View *view = find_view(handle);
  if (view == nullptr) {
    return;
  }
  const std::string wrapped = "Promise.resolve().then(() => eval(" +
      javascript_string(bytes_to_utf8(script)) + ")).then(value => " +
      "window.webkit.messageHandlers.moonview.postMessage('e:" +
      encode_base64(bytes_to_utf8(request_id)) + ":' + btoa(unescape(encodeURIComponent(String(value))))), " +
      "error => window.webkit.messageHandlers.moonview.postMessage('f:" +
      encode_base64(bytes_to_utf8(request_id)) + ":' + btoa(unescape(encodeURIComponent(String(error))))));";
  execute_javascript(view, wrapped);
}

extern "C" MOONBIT_FFI_EXPORT void moonview_linux_post_message(uint64_t handle,
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

extern "C" MOONBIT_FFI_EXPORT void moonview_linux_install_event_callback(EventTrampoline, void *) {}
extern "C" MOONBIT_FFI_EXPORT void moonview_linux_install_navigation_callback(NavigationTrampoline, void *) {}
extern "C" MOONBIT_FFI_EXPORT int32_t moonview_linux_available() { return 0; }
extern "C" MOONBIT_FFI_EXPORT uint64_t moonview_linux_create(uint64_t, int32_t, int32_t, int32_t, int32_t, moonbit_bytes_t, moonbit_bytes_t, moonbit_bytes_t) { return 0; }
extern "C" MOONBIT_FFI_EXPORT void moonview_linux_start(uint64_t) {}
extern "C" MOONBIT_FFI_EXPORT int32_t moonview_linux_destroy(uint64_t) { return 0; }
extern "C" MOONBIT_FFI_EXPORT void moonview_linux_set_bounds(uint64_t, int32_t, int32_t, int32_t, int32_t) {}
extern "C" MOONBIT_FFI_EXPORT void moonview_linux_set_visible(uint64_t, int32_t) {}
extern "C" MOONBIT_FFI_EXPORT void moonview_linux_focus(uint64_t) {}
extern "C" MOONBIT_FFI_EXPORT void moonview_linux_navigate(uint64_t, moonbit_bytes_t) {}
extern "C" MOONBIT_FFI_EXPORT void moonview_linux_load_html(uint64_t, moonbit_bytes_t) {}
extern "C" MOONBIT_FFI_EXPORT void moonview_linux_reload(uint64_t) {}
extern "C" MOONBIT_FFI_EXPORT void moonview_linux_stop(uint64_t) {}
extern "C" MOONBIT_FFI_EXPORT void moonview_linux_go_back(uint64_t) {}
extern "C" MOONBIT_FFI_EXPORT void moonview_linux_go_forward(uint64_t) {}
extern "C" MOONBIT_FFI_EXPORT void moonview_linux_init(uint64_t, moonbit_bytes_t) {}
extern "C" MOONBIT_FFI_EXPORT void moonview_linux_eval(uint64_t, moonbit_bytes_t, moonbit_bytes_t) {}
extern "C" MOONBIT_FFI_EXPORT void moonview_linux_post_message(uint64_t, moonbit_bytes_t) {}

#endif
