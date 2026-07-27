#if defined(__linux__) && !defined(__OHOS__)

#include <gtk/gtk.h>
#include <webkit2/webkit2.h>

#include <moonbit.h>

#include <atomic>
#include <cstdint>
#include <cstring>
#include <memory>
#include <string>
#include <unordered_map>
#include <vector>

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
  kProtocolCancelled = 10,
};

using EventTrampoline = void (*)(void *, uint64_t, int32_t, moonbit_bytes_t,
                                 moonbit_bytes_t, int32_t);
using NavigationTrampoline = int32_t (*)(void *, uint64_t, moonbit_bytes_t);
using ProtocolTrampoline = void (*)(void *, uint64_t, moonbit_bytes_t,
                                    moonbit_bytes_t, moonbit_bytes_t,
                                    moonbit_bytes_t, moonbit_bytes_t,
                                    moonbit_bytes_t);
using MediaPermissionTrampoline = int32_t (*)(void *, uint64_t, int32_t,
                                               moonbit_bytes_t);

EventTrampoline g_event_trampoline = nullptr;
void *g_event_closure = nullptr;
NavigationTrampoline g_navigation_trampoline = nullptr;
void *g_navigation_closure = nullptr;
ProtocolTrampoline g_protocol_trampoline = nullptr;
void *g_protocol_closure = nullptr;
MediaPermissionTrampoline g_media_permission_trampoline = nullptr;
void *g_media_permission_closure = nullptr;
std::atomic<uint64_t> g_next_view_handle{1};
std::vector<std::string> g_custom_schemes;
bool g_custom_schemes_locked = false;
bool g_custom_schemes_installed = false;

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
  struct PendingProtocol {
    WebKitURISchemeRequest *request = nullptr;
    guint timeout = 0;
  };
  std::unordered_map<std::string, PendingProtocol> pending_protocols;
  std::string initial_url;
  std::string initial_html;
  bool started = false;
};

std::unordered_map<uint64_t, std::unique_ptr<View>> g_views;
std::unordered_map<WebKitWebView *, View *> g_webview_views;

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

bool valid_custom_scheme(const std::string &scheme) {
  if (scheme.empty() || !((scheme[0] >= 'a' && scheme[0] <= 'z') ||
      (scheme[0] >= 'A' && scheme[0] <= 'Z'))) {
    return false;
  }
  if (scheme == "http" || scheme == "https" || scheme == "file" ||
      scheme == "data" || scheme == "javascript") {
    return false;
  }
  for (const char character : scheme) {
    if (!((character >= 'a' && character <= 'z') ||
          (character >= 'A' && character <= 'Z') ||
          (character >= '0' && character <= '9') || character == '+' ||
          character == '-' || character == '.')) {
      return false;
    }
  }
  return true;
}

View *find_view(WebKitWebView *webview) {
  const auto found = g_webview_views.find(webview);
  return found == g_webview_views.end() ? nullptr : found->second;
}

void append_u32(std::string *target, uint32_t value) {
  target->push_back(static_cast<char>((value >> 24) & 0xFF));
  target->push_back(static_cast<char>((value >> 16) & 0xFF));
  target->push_back(static_cast<char>((value >> 8) & 0xFF));
  target->push_back(static_cast<char>(value & 0xFF));
}

bool read_u32(const std::string &source, size_t *offset, uint32_t *value) {
  if (*offset + 4 > source.size()) {
    return false;
  }
  *value = (static_cast<uint32_t>(static_cast<unsigned char>(source[*offset])) << 24) |
      (static_cast<uint32_t>(static_cast<unsigned char>(source[*offset + 1])) << 16) |
      (static_cast<uint32_t>(static_cast<unsigned char>(source[*offset + 2])) << 8) |
      static_cast<uint32_t>(static_cast<unsigned char>(source[*offset + 3]));
  *offset += 4;
  return true;
}

std::string encode_headers(SoupMessageHeaders *headers) {
  std::vector<std::pair<std::string, std::string>> values;
  if (headers != nullptr) {
    SoupMessageHeadersIter iterator;
    soup_message_headers_iter_init(&iterator, headers);
    const char *name = nullptr;
    const char *value = nullptr;
    while (soup_message_headers_iter_next(&iterator, &name, &value)) {
      values.emplace_back(name == nullptr ? "" : name, value == nullptr ? "" : value);
    }
  }
  std::string encoded;
  append_u32(&encoded, static_cast<uint32_t>(values.size()));
  for (const auto &header : values) {
    append_u32(&encoded, static_cast<uint32_t>(header.first.size()));
    encoded += header.first;
    append_u32(&encoded, static_cast<uint32_t>(header.second.size()));
    encoded += header.second;
  }
  return encoded;
}

bool decode_headers(const std::string &encoded,
                    std::vector<std::pair<std::string, std::string>> *headers) {
  size_t offset = 0;
  uint32_t count = 0;
  if (!read_u32(encoded, &offset, &count) || count > 1024) {
    return false;
  }
  for (uint32_t index = 0; index < count; ++index) {
    uint32_t name_size = 0;
    uint32_t value_size = 0;
    if (!read_u32(encoded, &offset, &name_size) || offset + name_size > encoded.size()) {
      return false;
    }
    std::string name = encoded.substr(offset, name_size);
    offset += name_size;
    if (!read_u32(encoded, &offset, &value_size) || offset + value_size > encoded.size()) {
      return false;
    }
    std::string value = encoded.substr(offset, value_size);
    offset += value_size;
    headers->emplace_back(std::move(name), std::move(value));
  }
  return offset == encoded.size();
}

std::string empty_headers() {
  return std::string(4, '\0');
}

bool allow_media_permission(View *view, int32_t kind, const std::string &origin) {
  if (view == nullptr || g_media_permission_trampoline == nullptr ||
      g_media_permission_closure == nullptr) {
    return false;
  }
  return g_media_permission_trampoline(g_media_permission_closure, view->handle,
                                       kind, make_bytes(origin)) != 0;
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

bool finish_protocol(View *view, const std::string &request_id, int32_t status,
                     const std::string &headers, const std::string &body) {
  if (view == nullptr || status < 100 || status > 599) {
    return false;
  }
  const auto found = view->pending_protocols.find(request_id);
  if (found == view->pending_protocols.end()) {
    return false;
  }
  std::vector<std::pair<std::string, std::string>> decoded_headers;
  if (!decode_headers(headers, &decoded_headers)) {
    return false;
  }
  View::PendingProtocol pending = found->second;
  view->pending_protocols.erase(found);
  if (pending.timeout != 0) {
    g_source_remove(pending.timeout);
  }
  GBytes *bytes = g_bytes_new(body.data(), body.size());
  GInputStream *stream = g_memory_input_stream_new_from_bytes(bytes);
  g_bytes_unref(bytes);
  WebKitURISchemeResponse *response = webkit_uri_scheme_response_new(
      stream, static_cast<gint64>(body.size()));
  webkit_uri_scheme_response_set_status(response, static_cast<guint>(status), nullptr);
  SoupMessageHeaders *response_headers = soup_message_headers_new(SOUP_MESSAGE_HEADERS_RESPONSE);
  for (const auto &header : decoded_headers) {
    soup_message_headers_append(response_headers, header.first.c_str(), header.second.c_str());
  }
  const char *content_type = soup_message_headers_get_one(response_headers, "Content-Type");
  if (content_type != nullptr) {
    webkit_uri_scheme_response_set_content_type(response, content_type);
  }
  webkit_uri_scheme_response_set_http_headers(response, response_headers);
  webkit_uri_scheme_request_finish_with_response(pending.request, response);
  g_object_unref(response);
  g_object_unref(stream);
  g_object_unref(pending.request);
  return true;
}

struct QueuedProtocolResponse {
  uint64_t handle = 0;
  std::string request_id;
  int32_t status = 0;
  std::string headers;
  std::string body;
};

gboolean finish_queued_protocol_response(gpointer data) {
  auto *response = static_cast<QueuedProtocolResponse *>(data);
  finish_protocol(find_view(response->handle), response->request_id, response->status,
                  response->headers, response->body);
  return G_SOURCE_REMOVE;
}

void destroy_queued_protocol_response(gpointer data) {
  delete static_cast<QueuedProtocolResponse *>(data);
}

struct ProtocolTimeout {
  uint64_t handle = 0;
  std::string request_id;
};

gboolean protocol_timeout(gpointer data) {
  ProtocolTimeout *timeout = static_cast<ProtocolTimeout *>(data);
  View *view = find_view(timeout->handle);
  if (view != nullptr) {
    const auto pending = view->pending_protocols.find(timeout->request_id);
    if (pending == view->pending_protocols.end()) {
      return G_SOURCE_REMOVE;
    }
    pending->second.timeout = 0;
    emit_event(view, kProtocolCancelled, timeout->request_id);
    finish_protocol(view, timeout->request_id, 504, empty_headers(), "");
  }
  return G_SOURCE_REMOVE;
}

void destroy_protocol_timeout(gpointer data) {
  delete static_cast<ProtocolTimeout *>(data);
}

std::string read_request_body(GInputStream *body) {
  if (body == nullptr) {
    return "";
  }
  std::string result;
  char buffer[4096];
  while (true) {
    GError *error = nullptr;
    const gssize read = g_input_stream_read(body, buffer, sizeof(buffer), nullptr, &error);
    if (error != nullptr || read <= 0) {
      if (error != nullptr) {
        g_error_free(error);
      }
      break;
    }
    result.append(buffer, static_cast<size_t>(read));
  }
  return result;
}

void handle_scheme_request(WebKitURISchemeRequest *request, gpointer) {
  WebKitWebView *webview = webkit_uri_scheme_request_get_web_view(request);
  View *view = find_view(webview);
  if (view == nullptr || g_protocol_trampoline == nullptr || g_protocol_closure == nullptr) {
    GError *error = g_error_new_literal(G_IO_ERROR, G_IO_ERROR_NOT_SUPPORTED,
                                        "moonview protocol callback unavailable");
    webkit_uri_scheme_request_finish_error(request, error);
    g_error_free(error);
    return;
  }
  static std::atomic<uint64_t> next_request_id{1};
  const std::string request_id = std::to_string(next_request_id.fetch_add(1));
  View::PendingProtocol pending;
  pending.request = WEBKIT_URI_SCHEME_REQUEST(g_object_ref(request));
  auto *timeout = new ProtocolTimeout();
  timeout->handle = view->handle;
  timeout->request_id = request_id;
  pending.timeout = g_timeout_add_full(G_PRIORITY_DEFAULT, 30000, protocol_timeout,
                                       timeout, destroy_protocol_timeout);
  view->pending_protocols.emplace(request_id, pending);
  const gchar *scheme = webkit_uri_scheme_request_get_scheme(request);
  const gchar *method = webkit_uri_scheme_request_get_http_method(request);
  const gchar *uri = webkit_uri_scheme_request_get_uri(request);
  g_protocol_trampoline(g_protocol_closure, view->handle, make_bytes(request_id),
      make_bytes(scheme == nullptr ? "" : scheme), make_bytes(method == nullptr ? "GET" : method),
      make_bytes(uri == nullptr ? "" : uri),
      make_bytes(encode_headers(webkit_uri_scheme_request_get_http_headers(request))),
      make_bytes(read_request_body(webkit_uri_scheme_request_get_http_body(request))));
}

void install_custom_schemes() {
  if (g_custom_schemes_installed) {
    return;
  }
  WebKitWebContext *context = webkit_web_context_get_default();
  WebKitSecurityManager *security_manager = webkit_web_context_get_security_manager(context);
  for (const std::string &scheme : g_custom_schemes) {
    webkit_security_manager_register_uri_scheme_as_secure(security_manager, scheme.c_str());
    webkit_web_context_register_uri_scheme(context, scheme.c_str(), handle_scheme_request,
                                           nullptr, nullptr);
  }
  g_custom_schemes_installed = true;
}

gboolean handle_permission_request(WebKitWebView *webview,
                                   WebKitPermissionRequest *request,
                                   gpointer user_data) {
  View *view = static_cast<View *>(user_data);
  const gchar *uri = webkit_web_view_get_uri(webview);
  const std::string origin = uri == nullptr ? "" : uri;
  int32_t kind = 0;
  if (WEBKIT_IS_USER_MEDIA_PERMISSION_REQUEST(request)) {
    WebKitUserMediaPermissionRequest *media =
        WEBKIT_USER_MEDIA_PERMISSION_REQUEST(request);
    const bool camera = webkit_user_media_permission_is_for_video_device(media);
    const bool microphone = webkit_user_media_permission_is_for_audio_device(media);
    if (camera && microphone) {
      kind = 3;
    } else if (camera) {
      kind = 1;
    } else if (microphone) {
      kind = 2;
    }
  }
  if (kind != 0 && allow_media_permission(view, kind, origin)) {
    webkit_permission_request_allow(request);
  } else {
    webkit_permission_request_deny(request);
  }
  return TRUE;
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

extern "C" MOONBIT_FFI_EXPORT void moonview_linux_install_protocol_callback(
    ProtocolTrampoline trampoline, void *closure) {
  if (g_protocol_closure != nullptr) {
    moonbit_decref(g_protocol_closure);
  }
  g_protocol_trampoline = trampoline;
  g_protocol_closure = closure;
}

extern "C" MOONBIT_FFI_EXPORT void moonview_linux_install_media_permission_callback(
    MediaPermissionTrampoline trampoline, void *closure) {
  if (g_media_permission_closure != nullptr) {
    moonbit_decref(g_media_permission_closure);
  }
  g_media_permission_trampoline = trampoline;
  g_media_permission_closure = closure;
}

extern "C" MOONBIT_FFI_EXPORT int32_t moonview_linux_register_custom_scheme(
    moonbit_bytes_t name) {
  if (g_custom_schemes_locked) {
    return -1;
  }
  const std::string scheme = bytes_to_utf8(name);
  if (!valid_custom_scheme(scheme)) {
    return 0;
  }
  for (const std::string &registered : g_custom_schemes) {
    if (registered == scheme) {
      return 1;
    }
  }
  g_custom_schemes.push_back(scheme);
  return 1;
}

extern "C" MOONBIT_FFI_EXPORT void moonview_linux_lock_custom_schemes() {
  g_custom_schemes_locked = true;
}

extern "C" MOONBIT_FFI_EXPORT int32_t moonview_linux_respond_protocol(
    uint64_t handle, moonbit_bytes_t request_id, int32_t status,
    moonbit_bytes_t headers, moonbit_bytes_t body) {
  View *view = find_view(handle);
  const std::string id = bytes_to_utf8(request_id);
  if (view == nullptr || view->pending_protocols.find(id) == view->pending_protocols.end()) {
    return 0;
  }
  auto *response = new QueuedProtocolResponse{
      handle,
      id,
      status,
      bytes_to_utf8(headers),
      bytes_to_utf8(body),
  };
  g_idle_add_full(G_PRIORITY_DEFAULT, finish_queued_protocol_response, response,
                  destroy_queued_protocol_response);
  return 1;
}

extern "C" MOONBIT_FFI_EXPORT int32_t moonview_linux_available() {
  return gtk_get_major_version() == 3 ? 1 : 0;
}

extern "C" MOONBIT_FFI_EXPORT uint64_t moonview_linux_current_thread_token() {
  return static_cast<uint64_t>(reinterpret_cast<uintptr_t>(g_thread_self()));
}

extern "C" MOONBIT_FFI_EXPORT uint64_t moonview_linux_create(
    uint64_t parent_handle, int32_t x, int32_t y, int32_t width, int32_t height,
    moonbit_bytes_t initial_url, moonbit_bytes_t initial_html,
    moonbit_bytes_t initialization_script, moonbit_bytes_t user_agent) {
  if (!gtk_init_check(nullptr, nullptr)) {
    return 0;
  }
  GtkWidget *parent_widget = reinterpret_cast<GtkWidget *>(static_cast<uintptr_t>(parent_handle));
  if (parent_widget == nullptr || !GTK_IS_FIXED(parent_widget)) {
    return 0;
  }
  install_custom_schemes();
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
  const std::string configured_user_agent = bytes_to_utf8(user_agent);
  WebKitSettings *settings = webkit_web_view_get_settings(view->webview);
  webkit_settings_set_enable_developer_extras(settings, TRUE);
  if (!configured_user_agent.empty()) {
    webkit_settings_set_user_agent(settings, configured_user_agent.c_str());
  }
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
  g_signal_connect(view->webview, "permission-request",
                   G_CALLBACK(handle_permission_request), view.get());
  gtk_widget_set_size_request(GTK_WIDGET(view->webview), width, height);
  gtk_fixed_put(view->parent, GTK_WIDGET(view->webview), x, y);
  const uint64_t handle = view->handle;
  g_webview_views.emplace(view->webview, view.get());
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
  for (const auto &pending : view->pending_protocols) {
    if (pending.second.timeout != 0) {
      g_source_remove(pending.second.timeout);
    }
    emit_event(view, kProtocolCancelled, pending.first);
    g_object_unref(pending.second.request);
  }
  view->pending_protocols.clear();
  g_webview_views.erase(view->webview);
  gtk_widget_destroy(GTK_WIDGET(view->webview));
  g_object_unref(view->content_manager);
  g_views.erase(found);
  return 1;
}

extern "C" MOONBIT_FFI_EXPORT int32_t moonview_linux_set_bounds(
    uint64_t handle, int32_t x, int32_t y, int32_t width, int32_t height) {
  View *view = find_view(handle);
  if (view == nullptr) {
    return 0;
  }
  gtk_widget_set_size_request(GTK_WIDGET(view->webview), width, height);
  gtk_fixed_move(view->parent, GTK_WIDGET(view->webview), x, y);
  return 1;
}

extern "C" MOONBIT_FFI_EXPORT int32_t moonview_linux_set_visible(uint64_t handle,
                                                                  int32_t visible) {
  View *view = find_view(handle);
  if (view == nullptr) return 0;
  gtk_widget_set_visible(GTK_WIDGET(view->webview), visible != 0);
  return 1;
}

extern "C" MOONBIT_FFI_EXPORT int32_t moonview_linux_focus(uint64_t handle) {
  View *view = find_view(handle);
  if (view == nullptr) return 0;
  gtk_widget_grab_focus(GTK_WIDGET(view->webview));
  return 1;
}

extern "C" MOONBIT_FFI_EXPORT int32_t moonview_linux_navigate(uint64_t handle,
                                                              moonbit_bytes_t url) {
  View *view = find_view(handle);
  if (view == nullptr) return 0;
  webkit_web_view_load_uri(view->webview, bytes_to_utf8(url).c_str());
  return 1;
}

extern "C" MOONBIT_FFI_EXPORT int32_t moonview_linux_load_html(uint64_t handle,
                                                               moonbit_bytes_t html) {
  View *view = find_view(handle);
  if (view == nullptr) return 0;
  webkit_web_view_load_html(view->webview, bytes_to_utf8(html).c_str(), nullptr);
  return 1;
}

extern "C" MOONBIT_FFI_EXPORT int32_t moonview_linux_reload(uint64_t handle) {
  View *view = find_view(handle);
  if (view == nullptr) return 0;
  webkit_web_view_reload(view->webview);
  return 1;
}

extern "C" MOONBIT_FFI_EXPORT int32_t moonview_linux_stop(uint64_t handle) {
  View *view = find_view(handle);
  if (view == nullptr) return 0;
  webkit_web_view_stop_loading(view->webview);
  return 1;
}

extern "C" MOONBIT_FFI_EXPORT int32_t moonview_linux_go_back(uint64_t handle) {
  View *view = find_view(handle);
  if (view == nullptr) return 0;
  if (webkit_web_view_can_go_back(view->webview)) {
    webkit_web_view_go_back(view->webview);
  }
  return 1;
}

extern "C" MOONBIT_FFI_EXPORT int32_t moonview_linux_go_forward(uint64_t handle) {
  View *view = find_view(handle);
  if (view == nullptr) return 0;
  if (webkit_web_view_can_go_forward(view->webview)) {
    webkit_web_view_go_forward(view->webview);
  }
  return 1;
}

extern "C" MOONBIT_FFI_EXPORT int32_t moonview_linux_init(uint64_t handle,
                                                          moonbit_bytes_t script) {
  View *view = find_view(handle);
  if (view == nullptr) return 0;
  add_document_script(view, bytes_to_utf8(script));
  return 1;
}

extern "C" MOONBIT_FFI_EXPORT int32_t moonview_linux_set_zoom(uint64_t handle,
                                                              double factor) {
  View *view = find_view(handle);
  if (view == nullptr) return 0;
  webkit_web_view_set_zoom_level(view->webview, factor);
  return 1;
}

extern "C" MOONBIT_FFI_EXPORT int32_t moonview_linux_open_devtools(uint64_t handle) {
  View *view = find_view(handle);
  if (view == nullptr) {
    return 0;
  }
  WebKitWebInspector *inspector = webkit_web_view_get_inspector(view->webview);
  webkit_web_inspector_show(inspector);
  return 1;
}

extern "C" MOONBIT_FFI_EXPORT int32_t moonview_linux_open_print_dialog(uint64_t handle) {
  View *view = find_view(handle);
  if (view == nullptr) {
    return 0;
  }
  WebKitPrintOperation *operation = webkit_print_operation_new(view->webview);
  webkit_print_operation_run_dialog(operation, nullptr);
  g_object_unref(operation);
  return 1;
}

extern "C" MOONBIT_FFI_EXPORT int32_t moonview_linux_eval(uint64_t handle,
                                                          moonbit_bytes_t script,
                                                          moonbit_bytes_t request_id) {
  View *view = find_view(handle);
  if (view == nullptr) {
    return 0;
  }
  const std::string wrapped = "Promise.resolve().then(() => eval(" +
      javascript_string(bytes_to_utf8(script)) + ")).then(value => " +
      "window.webkit.messageHandlers.moonview.postMessage('e:" +
      encode_base64(bytes_to_utf8(request_id)) + ":' + btoa(unescape(encodeURIComponent(JSON.stringify(value) ?? 'null')))), " +
      "error => window.webkit.messageHandlers.moonview.postMessage('f:" +
      encode_base64(bytes_to_utf8(request_id)) + ":' + btoa(unescape(encodeURIComponent(String(error))))));";
  execute_javascript(view, wrapped);
  return 1;
}

extern "C" MOONBIT_FFI_EXPORT int32_t moonview_linux_post_message(uint64_t handle,
                                                                  moonbit_bytes_t message) {
  View *view = find_view(handle);
  if (view == nullptr) return 0;
  execute_javascript(view, "window.moonview && window.moonview._deliver(" +
      javascript_string(bytes_to_utf8(message)) + ");");
  return 1;
}

#else

#include <moonbit.h>

using EventTrampoline = void (*)(void *, uint64_t, int32_t, moonbit_bytes_t,
                                 moonbit_bytes_t, int32_t);
using NavigationTrampoline = int32_t (*)(void *, uint64_t, moonbit_bytes_t);
using ProtocolTrampoline = void (*)(void *, uint64_t, moonbit_bytes_t, moonbit_bytes_t,
                                    moonbit_bytes_t, moonbit_bytes_t, moonbit_bytes_t,
                                    moonbit_bytes_t);
using MediaPermissionTrampoline = int32_t (*)(void *, uint64_t, int32_t, moonbit_bytes_t);

extern "C" MOONBIT_FFI_EXPORT void moonview_linux_install_event_callback(EventTrampoline, void *) {}
extern "C" MOONBIT_FFI_EXPORT void moonview_linux_install_navigation_callback(NavigationTrampoline, void *) {}
extern "C" MOONBIT_FFI_EXPORT void moonview_linux_install_protocol_callback(ProtocolTrampoline, void *) {}
extern "C" MOONBIT_FFI_EXPORT void moonview_linux_install_media_permission_callback(MediaPermissionTrampoline, void *) {}
extern "C" MOONBIT_FFI_EXPORT int32_t moonview_linux_available() { return 0; }
extern "C" MOONBIT_FFI_EXPORT uint64_t moonview_linux_current_thread_token() { return 0; }
extern "C" MOONBIT_FFI_EXPORT int32_t moonview_linux_register_custom_scheme(moonbit_bytes_t) { return 0; }
extern "C" MOONBIT_FFI_EXPORT void moonview_linux_lock_custom_schemes() {}
extern "C" MOONBIT_FFI_EXPORT int32_t moonview_linux_respond_protocol(uint64_t, moonbit_bytes_t, int32_t, moonbit_bytes_t, moonbit_bytes_t) { return 0; }
extern "C" MOONBIT_FFI_EXPORT uint64_t moonview_linux_create(uint64_t, int32_t, int32_t, int32_t, int32_t, moonbit_bytes_t, moonbit_bytes_t, moonbit_bytes_t, moonbit_bytes_t) { return 0; }
extern "C" MOONBIT_FFI_EXPORT void moonview_linux_start(uint64_t) {}
extern "C" MOONBIT_FFI_EXPORT int32_t moonview_linux_destroy(uint64_t) { return 0; }
extern "C" MOONBIT_FFI_EXPORT int32_t moonview_linux_set_bounds(uint64_t, int32_t, int32_t, int32_t, int32_t) { return 0; }
extern "C" MOONBIT_FFI_EXPORT int32_t moonview_linux_set_visible(uint64_t, int32_t) { return 0; }
extern "C" MOONBIT_FFI_EXPORT int32_t moonview_linux_focus(uint64_t) { return 0; }
extern "C" MOONBIT_FFI_EXPORT int32_t moonview_linux_navigate(uint64_t, moonbit_bytes_t) { return 0; }
extern "C" MOONBIT_FFI_EXPORT int32_t moonview_linux_load_html(uint64_t, moonbit_bytes_t) { return 0; }
extern "C" MOONBIT_FFI_EXPORT int32_t moonview_linux_reload(uint64_t) { return 0; }
extern "C" MOONBIT_FFI_EXPORT int32_t moonview_linux_stop(uint64_t) { return 0; }
extern "C" MOONBIT_FFI_EXPORT int32_t moonview_linux_go_back(uint64_t) { return 0; }
extern "C" MOONBIT_FFI_EXPORT int32_t moonview_linux_go_forward(uint64_t) { return 0; }
extern "C" MOONBIT_FFI_EXPORT int32_t moonview_linux_init(uint64_t, moonbit_bytes_t) { return 0; }
extern "C" MOONBIT_FFI_EXPORT int32_t moonview_linux_set_zoom(uint64_t, double) { return 0; }
extern "C" MOONBIT_FFI_EXPORT int32_t moonview_linux_open_devtools(uint64_t) { return 0; }
extern "C" MOONBIT_FFI_EXPORT int32_t moonview_linux_open_print_dialog(uint64_t) { return 0; }
extern "C" MOONBIT_FFI_EXPORT int32_t moonview_linux_eval(uint64_t, moonbit_bytes_t, moonbit_bytes_t) { return 0; }
extern "C" MOONBIT_FFI_EXPORT int32_t moonview_linux_post_message(uint64_t, moonbit_bytes_t) { return 0; }

#endif
