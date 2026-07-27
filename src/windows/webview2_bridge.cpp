#include <moonbit.h>

#if defined(_WIN32)

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#include <unknwn.h>
#include <WebView2.h>
#include <wrl.h>

#include <atomic>
#include <cstdio>
#include <cstdint>
#include <cstring>
#include <deque>
#include <map>
#include <memory>
#include <string>
#include <utility>
#include <vector>

using Microsoft::WRL::Callback;
using Microsoft::WRL::ComPtr;

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

typedef void (*EventTrampoline)(void *closure, uint64_t view, int32_t kind,
                                moonbit_bytes_t value,
                                moonbit_bytes_t detail, int32_t code);
typedef int32_t (*NavigationTrampoline)(void *closure, uint64_t view,
                                        moonbit_bytes_t uri);

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

std::wstring utf8_to_wide(const std::string &value) {
  if (value.empty()) {
    return L"";
  }
  const int length = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
                                         static_cast<int>(value.size()), nullptr, 0);
  if (length <= 0) {
    return L"";
  }
  std::wstring result(static_cast<size_t>(length), L'\0');
  MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
                      static_cast<int>(value.size()), &result[0], length);
  return result;
}

std::string wide_to_utf8(const wchar_t *value) {
  if (value == nullptr || value[0] == L'\0') {
    return "";
  }
  const int length = WideCharToMultiByte(CP_UTF8, 0, value, -1, nullptr, 0, nullptr, nullptr);
  if (length <= 1) {
    return "";
  }
  std::string result(static_cast<size_t>(length), '\0');
  WideCharToMultiByte(CP_UTF8, 0, value, -1, &result[0], length, nullptr, nullptr);
  result.resize(static_cast<size_t>(length - 1));
  return result;
}

std::string hresult_text(const char *operation, HRESULT result) {
  char buffer[128];
  std::snprintf(buffer, sizeof(buffer), "%s failed (HRESULT=0x%08X)", operation,
                static_cast<unsigned int>(result));
  return buffer;
}

struct Command {
  enum Kind {
    Navigate,
    LoadHtml,
    Reload,
    Stop,
    GoBack,
    GoForward,
    Focus,
    SetZoom,
    OpenDevTools,
    Eval,
    PostMessage,
  } kind;
  std::wstring value;
  std::string request_id;
  double factor = 1.0;
};

struct View;

struct ThreadEnvironment {
  DWORD thread_id = 0;
  bool creating = false;
  HRESULT failure = S_OK;
  ComPtr<ICoreWebView2Environment> environment;
};

struct View {
  uint64_t handle = 0;
  HWND parent = nullptr;
  DWORD thread_id = 0;
  bool com_initialized = false;
  bool destroyed = false;
  bool controller_creating = false;
  bool scripts_installing = false;
  bool ready = false;
  bool visible = true;
  RECT bounds{};
  std::wstring initial_url;
  std::wstring initial_html;
  std::wstring user_agent;
  std::vector<std::wstring> document_scripts;
  std::deque<Command> pending;
  ComPtr<ICoreWebView2Controller> controller;
  ComPtr<ICoreWebView2> webview;
};

std::map<uint64_t, std::shared_ptr<View>> g_views;
std::map<DWORD, ThreadEnvironment> g_environments;

void emit_event(const std::shared_ptr<View> &view, EventKind kind,
                const std::string &value = "", const std::string &detail = "",
                int32_t code = 0) {
  if (!view || view->destroyed || g_event_trampoline == nullptr || g_event_closure == nullptr) {
    return;
  }
  g_event_trampoline(g_event_closure, view->handle, kind, make_bytes(value),
                     make_bytes(detail), code);
}

int32_t navigation_allowed(const std::shared_ptr<View> &view, const std::string &uri) {
  if (g_navigation_trampoline == nullptr || g_navigation_closure == nullptr) {
    return 1;
  }
  return g_navigation_trampoline(g_navigation_closure, view->handle, make_bytes(uri));
}

std::shared_ptr<View> find_view(uint64_t handle) {
  const auto it = g_views.find(handle);
  return it == g_views.end() ? nullptr : it->second;
}

bool runtime_available() {
  LPWSTR version = nullptr;
  const HRESULT result = GetAvailableCoreWebView2BrowserVersionString(nullptr, &version);
  if (version != nullptr) {
    CoTaskMemFree(version);
  }
  return SUCCEEDED(result);
}

void apply_bounds(const std::shared_ptr<View> &view) {
  if (!view || !view->controller) {
    return;
  }
  view->controller->put_Bounds(view->bounds);
  view->controller->put_IsVisible(view->visible ? TRUE : FALSE);
}

void run_command(const std::shared_ptr<View> &view, const Command &command) {
  if (!view || view->destroyed || !view->webview) {
    return;
  }
  switch (command.kind) {
  case Command::Navigate:
    view->webview->Navigate(command.value.c_str());
    break;
  case Command::LoadHtml:
    view->webview->NavigateToString(command.value.c_str());
    break;
  case Command::Reload:
    view->webview->Reload();
    break;
  case Command::Stop:
    view->webview->Stop();
    break;
  case Command::GoBack:
    view->webview->GoBack();
    break;
  case Command::GoForward:
    view->webview->GoForward();
    break;
  case Command::Focus:
    view->controller->MoveFocus(COREWEBVIEW2_MOVE_FOCUS_REASON_PROGRAMMATIC);
    break;
  case Command::SetZoom:
    view->controller->put_ZoomFactor(command.factor);
    break;
  case Command::OpenDevTools:
    view->webview->OpenDevToolsWindow();
    break;
  case Command::Eval: {
    const std::weak_ptr<View> weak_view = view;
    const std::string request_id = command.request_id;
    view->webview->ExecuteScript(
        command.value.c_str(),
        Callback<ICoreWebView2ExecuteScriptCompletedHandler>(
            [weak_view, request_id](HRESULT result, LPCWSTR json_result) -> HRESULT {
              const std::shared_ptr<View> locked = weak_view.lock();
              if (!locked || locked->destroyed) {
                return S_OK;
              }
              emit_event(locked, kScriptCompleted,
                         SUCCEEDED(result) ? wide_to_utf8(json_result)
                                           : hresult_text("ExecuteScript", result),
                         request_id,
                         static_cast<int32_t>(result));
              return S_OK;
            })
            .Get());
    break;
  }
  case Command::PostMessage:
    view->webview->PostWebMessageAsString(command.value.c_str());
    break;
  }
}

void drain_pending(const std::shared_ptr<View> &view) {
  if (!view || view->destroyed || !view->ready) {
    return;
  }
  if (!view->initial_html.empty()) {
    run_command(view, {Command::LoadHtml, view->initial_html, ""});
    view->initial_html.clear();
    view->initial_url.clear();
  } else if (!view->initial_url.empty()) {
    run_command(view, {Command::Navigate, view->initial_url, ""});
    view->initial_url.clear();
  }
  while (!view->pending.empty()) {
    Command command = std::move(view->pending.front());
    view->pending.pop_front();
    run_command(view, command);
  }
}

void queue_or_run(const std::shared_ptr<View> &view, Command command) {
  if (!view || view->destroyed) {
    return;
  }
  if (!view->ready) {
    view->pending.push_back(std::move(command));
    return;
  }
  run_command(view, command);
}

void install_handlers(const std::shared_ptr<View> &view) {
  if (!view || !view->webview) {
    return;
  }
  const std::weak_ptr<View> weak_view = view;
  EventRegistrationToken token{};
  view->webview->add_WebMessageReceived(
      Callback<ICoreWebView2WebMessageReceivedEventHandler>(
          [weak_view](ICoreWebView2 *, ICoreWebView2WebMessageReceivedEventArgs *args) -> HRESULT {
            const std::shared_ptr<View> locked = weak_view.lock();
            if (!locked || locked->destroyed) {
              return S_OK;
            }
            LPWSTR message = nullptr;
            const HRESULT result = args->TryGetWebMessageAsString(&message);
            const std::string text = SUCCEEDED(result) ? wide_to_utf8(message) : "";
            if (message != nullptr) {
              CoTaskMemFree(message);
            }
            emit_event(locked, kMessage, text,
                       SUCCEEDED(result) ? "" : hresult_text("Web message decode", result),
                       static_cast<int32_t>(result));
            return S_OK;
          })
          .Get(),
      &token);
  view->webview->add_NewWindowRequested(
      Callback<ICoreWebView2NewWindowRequestedEventHandler>(
          [](ICoreWebView2 *, ICoreWebView2NewWindowRequestedEventArgs *args) -> HRESULT {
            if (args != nullptr) {
              args->put_Handled(TRUE);
            }
            return S_OK;
          })
          .Get(),
      &token);
  view->webview->add_NavigationStarting(
      Callback<ICoreWebView2NavigationStartingEventHandler>(
          [weak_view](ICoreWebView2 *, ICoreWebView2NavigationStartingEventArgs *args) -> HRESULT {
            const std::shared_ptr<View> locked = weak_view.lock();
            if (!locked || locked->destroyed) {
              args->put_Cancel(TRUE);
              return S_OK;
            }
            LPWSTR uri = nullptr;
            args->get_Uri(&uri);
            const std::string text = wide_to_utf8(uri);
            if (uri != nullptr) {
              CoTaskMemFree(uri);
            }
            const int32_t allowed = navigation_allowed(locked, text);
            args->put_Cancel(allowed != 0 ? FALSE : TRUE);
            emit_event(locked, kNavigationStarting, text, "", allowed != 0 ? 0 : 1);
            return S_OK;
          })
          .Get(),
      &token);
  view->webview->add_SourceChanged(
      Callback<ICoreWebView2SourceChangedEventHandler>(
          [weak_view](ICoreWebView2 *sender, ICoreWebView2SourceChangedEventArgs *) -> HRESULT {
            const std::shared_ptr<View> locked = weak_view.lock();
            if (!locked || locked->destroyed) {
              return S_OK;
            }
            LPWSTR source = nullptr;
            sender->get_Source(&source);
            const std::string text = wide_to_utf8(source);
            if (source != nullptr) {
              CoTaskMemFree(source);
            }
            emit_event(locked, kSourceChanged, text);
            return S_OK;
          })
          .Get(),
      &token);
  view->webview->add_NavigationCompleted(
      Callback<ICoreWebView2NavigationCompletedEventHandler>(
          [weak_view](ICoreWebView2 *sender,
                      ICoreWebView2NavigationCompletedEventArgs *args) -> HRESULT {
            const std::shared_ptr<View> locked = weak_view.lock();
            if (!locked || locked->destroyed) {
              return S_OK;
            }
            BOOL success = FALSE;
            args->get_IsSuccess(&success);
            COREWEBVIEW2_WEB_ERROR_STATUS status = COREWEBVIEW2_WEB_ERROR_STATUS_UNKNOWN;
            if (!success) {
              args->get_WebErrorStatus(&status);
            }
            LPWSTR source = nullptr;
            sender->get_Source(&source);
            const std::string url = wide_to_utf8(source);
            if (source != nullptr) {
              CoTaskMemFree(source);
            }
            emit_event(locked, kNavigationCompleted, url, success ? "" : "Navigation failed",
                       success ? 0 : static_cast<int32_t>(status));
            return S_OK;
          })
          .Get(),
      &token);
  view->webview->add_DocumentTitleChanged(
      Callback<ICoreWebView2DocumentTitleChangedEventHandler>(
          [weak_view](ICoreWebView2 *sender, IUnknown *) -> HRESULT {
            const std::shared_ptr<View> locked = weak_view.lock();
            if (!locked || locked->destroyed) {
              return S_OK;
            }
            LPWSTR title = nullptr;
            sender->get_DocumentTitle(&title);
            const std::string text = wide_to_utf8(title);
            if (title != nullptr) {
              CoTaskMemFree(title);
            }
            emit_event(locked, kDocumentTitleChanged, text);
            return S_OK;
          })
          .Get(),
      &token);
  view->webview->add_HistoryChanged(
      Callback<ICoreWebView2HistoryChangedEventHandler>(
          [weak_view](ICoreWebView2 *sender, IUnknown *) -> HRESULT {
            const std::shared_ptr<View> locked = weak_view.lock();
            if (!locked || locked->destroyed) {
              return S_OK;
            }
            BOOL back = FALSE;
            BOOL forward = FALSE;
            sender->get_CanGoBack(&back);
            sender->get_CanGoForward(&forward);
            emit_event(locked, kHistoryChanged, "",
                       std::string("back=") + (back ? "1" : "0") + ";forward=" +
                           (forward ? "1" : "0"));
            return S_OK;
          })
          .Get(),
      &token);
}

const wchar_t *bridge_script() {
  return LR"JS((() => {
  const bridge = window.moonview || {};
  Object.defineProperty(bridge, "postMessage", {
    configurable: true,
    value(message) {
      window.chrome.webview.postMessage(String(message));
    },
  });
  if (!("onmessage" in bridge)) {
    Object.defineProperty(bridge, "onmessage", {
      configurable: true,
      writable: true,
      value: null,
    });
  }
  window.chrome.webview.addEventListener("message", (event) => {
    if (typeof bridge.onmessage === "function") {
      bridge.onmessage(String(event.data));
    }
  });
  window.moonview = bridge;
})();)JS";
}

void install_next_script(const std::shared_ptr<View> &view, size_t index) {
  if (!view || view->destroyed || !view->webview) {
    return;
  }
  if (index >= view->document_scripts.size()) {
    view->scripts_installing = false;
    view->ready = true;
    emit_event(view, kReady);
    drain_pending(view);
    return;
  }
  const std::weak_ptr<View> weak_view = view;
  const std::wstring script = view->document_scripts[index];
  view->webview->AddScriptToExecuteOnDocumentCreated(
      script.c_str(),
      Callback<ICoreWebView2AddScriptToExecuteOnDocumentCreatedCompletedHandler>(
          [weak_view, index](HRESULT result, LPCWSTR) -> HRESULT {
            const std::shared_ptr<View> locked = weak_view.lock();
            if (!locked || locked->destroyed) {
              return S_OK;
            }
            if (FAILED(result)) {
              locked->scripts_installing = false;
              emit_event(locked, kCreationFailed, "",
                         hresult_text("Document-created script installation", result),
                         static_cast<int32_t>(result));
              return S_OK;
            }
            install_next_script(locked, index + 1);
            return S_OK;
          })
          .Get());
}

void create_controller(const std::shared_ptr<View> &view) {
  if (!view || view->destroyed || view->controller_creating || view->controller) {
    return;
  }
  const auto environment_it = g_environments.find(view->thread_id);
  if (environment_it == g_environments.end() || !environment_it->second.environment) {
    return;
  }
  view->controller_creating = true;
  const std::weak_ptr<View> weak_view = view;
  environment_it->second.environment->CreateCoreWebView2Controller(
      view->parent,
      Callback<ICoreWebView2CreateCoreWebView2ControllerCompletedHandler>(
          [weak_view](HRESULT result, ICoreWebView2Controller *controller) -> HRESULT {
            const std::shared_ptr<View> locked = weak_view.lock();
            if (!locked || locked->destroyed) {
              if (controller != nullptr) {
                controller->Close();
              }
              return S_OK;
            }
            locked->controller_creating = false;
            if (FAILED(result) || controller == nullptr) {
              emit_event(locked, kCreationFailed, "",
                         hresult_text("WebView2 controller creation", result),
                         static_cast<int32_t>(result));
              return S_OK;
            }
            locked->controller = controller;
            result = controller->get_CoreWebView2(&locked->webview);
            if (FAILED(result) || !locked->webview) {
              emit_event(locked, kCreationFailed, "",
                         hresult_text("CoreWebView2 retrieval", result),
                         static_cast<int32_t>(result));
              return S_OK;
            }
            if (!locked->user_agent.empty()) {
              ComPtr<ICoreWebView2Settings> settings;
              if (SUCCEEDED(locked->webview->get_Settings(&settings)) && settings) {
                ComPtr<ICoreWebView2Settings2> settings2;
                if (SUCCEEDED(settings.As(&settings2)) && settings2) {
                  settings2->put_UserAgent(locked->user_agent.c_str());
                }
              }
            }
            apply_bounds(locked);
            install_handlers(locked);
            locked->scripts_installing = true;
            install_next_script(locked, 0);
            return S_OK;
          })
          .Get());
}

void create_waiting_controllers(DWORD thread_id) {
  for (const auto &entry : g_views) {
    const std::shared_ptr<View> &view = entry.second;
    if (view->thread_id == thread_id && !view->destroyed) {
      create_controller(view);
    }
  }
}

void fail_waiting_views(DWORD thread_id, HRESULT result, const char *operation) {
  for (const auto &entry : g_views) {
    const std::shared_ptr<View> &view = entry.second;
    if (view->thread_id == thread_id && !view->destroyed) {
      emit_event(view, kCreationFailed, "", hresult_text(operation, result),
                 static_cast<int32_t>(result));
    }
  }
}

void ensure_environment(DWORD thread_id) {
  ThreadEnvironment &state = g_environments[thread_id];
  state.thread_id = thread_id;
  if (state.environment || state.creating || FAILED(state.failure)) {
    return;
  }
  if (!runtime_available()) {
    state.failure = HRESULT_FROM_WIN32(ERROR_PRODUCT_UNINSTALLED);
    fail_waiting_views(thread_id, state.failure, "WebView2 Runtime discovery");
    return;
  }
  state.creating = true;
  const HRESULT start = CreateCoreWebView2EnvironmentWithOptions(
      nullptr, nullptr, nullptr,
      Callback<ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler>(
          [thread_id](HRESULT result, ICoreWebView2Environment *environment) -> HRESULT {
            auto state_it = g_environments.find(thread_id);
            if (state_it == g_environments.end()) {
              return S_OK;
            }
            ThreadEnvironment &completed = state_it->second;
            completed.creating = false;
            if (FAILED(result) || environment == nullptr) {
              completed.failure = FAILED(result) ? result : E_FAIL;
              fail_waiting_views(thread_id, completed.failure, "WebView2 environment creation");
              return S_OK;
            }
            completed.environment = environment;
            create_waiting_controllers(thread_id);
            return S_OK;
          })
          .Get());
  if (FAILED(start)) {
    state.creating = false;
    state.failure = start;
    fail_waiting_views(thread_id, start, "WebView2 environment creation start");
  }
}

bool has_thread_views(DWORD thread_id) {
  for (const auto &entry : g_views) {
    const std::shared_ptr<View> &view = entry.second;
    if (view->thread_id == thread_id && !view->destroyed) {
      return true;
    }
  }
  return false;
}

} // namespace

extern "C" MOONBIT_FFI_EXPORT void moonview_windows_install_event_callback(
    EventTrampoline trampoline, void *closure) {
  if (g_event_closure != nullptr) {
    moonbit_decref(g_event_closure);
  }
  g_event_trampoline = trampoline;
  g_event_closure = closure;
}

extern "C" MOONBIT_FFI_EXPORT void moonview_windows_install_navigation_callback(
    NavigationTrampoline trampoline, void *closure) {
  if (g_navigation_closure != nullptr) {
    moonbit_decref(g_navigation_closure);
  }
  g_navigation_trampoline = trampoline;
  g_navigation_closure = closure;
}

extern "C" MOONBIT_FFI_EXPORT int32_t moonview_windows_available() {
  return runtime_available() ? 1 : 0;
}

extern "C" MOONBIT_FFI_EXPORT uint64_t moonview_windows_create(
    uint64_t hwnd, int32_t x, int32_t y, int32_t width, int32_t height,
    moonbit_bytes_t url, moonbit_bytes_t html, moonbit_bytes_t initialization_script,
    moonbit_bytes_t user_agent) {
  const HWND parent = reinterpret_cast<HWND>(static_cast<uintptr_t>(hwnd));
  if (parent == nullptr || !IsWindow(parent)) {
    return 0;
  }
  const HRESULT coinit = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  if (FAILED(coinit)) {
    return 0;
  }
  const uint64_t handle = g_next_view_handle.fetch_add(1);
  auto view = std::make_shared<View>();
  view->handle = handle;
  view->parent = parent;
  view->thread_id = GetCurrentThreadId();
  view->bounds = {x, y, x + width, y + height};
  view->initial_url = utf8_to_wide(bytes_to_utf8(url));
  view->initial_html = utf8_to_wide(bytes_to_utf8(html));
  view->user_agent = utf8_to_wide(bytes_to_utf8(user_agent));
  view->document_scripts.push_back(bridge_script());
  const std::wstring initial_script = utf8_to_wide(bytes_to_utf8(initialization_script));
  if (!initial_script.empty()) {
    view->document_scripts.push_back(initial_script);
  }
  view->com_initialized = true;
  g_views.emplace(handle, view);
  return handle;
}

extern "C" MOONBIT_FFI_EXPORT void moonview_windows_start(uint64_t handle) {
  const std::shared_ptr<View> view = find_view(handle);
  if (!view || view->destroyed) {
    return;
  }
  if (GetCurrentThreadId() != view->thread_id) {
    emit_event(view, kCreationFailed, "", "WebView must start on its creation STA thread",
               static_cast<int32_t>(RPC_E_WRONG_THREAD));
    return;
  }
  const auto existing_environment = g_environments.find(view->thread_id);
  if (existing_environment != g_environments.end() && FAILED(existing_environment->second.failure)) {
    emit_event(view, kCreationFailed, "",
               hresult_text("WebView2 environment creation", existing_environment->second.failure),
               static_cast<int32_t>(existing_environment->second.failure));
    return;
  }
  ensure_environment(view->thread_id);
  create_controller(view);
}

extern "C" MOONBIT_FFI_EXPORT int32_t moonview_windows_destroy(uint64_t handle) {
  const std::shared_ptr<View> view = find_view(handle);
  if (!view || view->destroyed) {
    return 1;
  }
  if (GetCurrentThreadId() != view->thread_id) {
    emit_event(view, kCreationFailed, "", "WebView must be destroyed on its creation STA thread",
               RPC_E_WRONG_THREAD);
    return 0;
  }
  view->destroyed = true;
  if (view->controller) {
    view->controller->Close();
  }
  view->webview.Reset();
  view->controller.Reset();
  const DWORD thread_id = view->thread_id;
  const bool initialized_com = view->com_initialized;
  g_views.erase(handle);
  if (!has_thread_views(thread_id)) {
    const auto environment_it = g_environments.find(thread_id);
    if (environment_it != g_environments.end()) {
      environment_it->second.environment.Reset();
      g_environments.erase(environment_it);
    }
  }
  if (initialized_com) {
    CoUninitialize();
  }
  return 1;
}

extern "C" MOONBIT_FFI_EXPORT void moonview_windows_set_bounds(
    uint64_t handle, int32_t x, int32_t y, int32_t width, int32_t height) {
  const std::shared_ptr<View> view = find_view(handle);
  if (!view || view->destroyed) {
    return;
  }
  view->bounds = {x, y, x + width, y + height};
  apply_bounds(view);
}

extern "C" MOONBIT_FFI_EXPORT void moonview_windows_set_visible(uint64_t handle,
                                                                    int32_t visible) {
  const std::shared_ptr<View> view = find_view(handle);
  if (!view || view->destroyed) {
    return;
  }
  view->visible = visible != 0;
  apply_bounds(view);
}

extern "C" MOONBIT_FFI_EXPORT void moonview_windows_focus(uint64_t handle) {
  queue_or_run(find_view(handle), {Command::Focus, L"", ""});
}

extern "C" MOONBIT_FFI_EXPORT void moonview_windows_navigate(uint64_t handle,
                                                                 moonbit_bytes_t url) {
  queue_or_run(find_view(handle), {Command::Navigate, utf8_to_wide(bytes_to_utf8(url)), ""});
}

extern "C" MOONBIT_FFI_EXPORT void moonview_windows_load_html(uint64_t handle,
                                                                  moonbit_bytes_t html) {
  queue_or_run(find_view(handle), {Command::LoadHtml, utf8_to_wide(bytes_to_utf8(html)), ""});
}

extern "C" MOONBIT_FFI_EXPORT void moonview_windows_reload(uint64_t handle) {
  queue_or_run(find_view(handle), {Command::Reload, L"", ""});
}

extern "C" MOONBIT_FFI_EXPORT void moonview_windows_stop(uint64_t handle) {
  queue_or_run(find_view(handle), {Command::Stop, L"", ""});
}

extern "C" MOONBIT_FFI_EXPORT void moonview_windows_go_back(uint64_t handle) {
  queue_or_run(find_view(handle), {Command::GoBack, L"", ""});
}

extern "C" MOONBIT_FFI_EXPORT void moonview_windows_go_forward(uint64_t handle) {
  queue_or_run(find_view(handle), {Command::GoForward, L"", ""});
}

extern "C" MOONBIT_FFI_EXPORT void moonview_windows_init(uint64_t handle,
                                                             moonbit_bytes_t script) {
  const std::shared_ptr<View> view = find_view(handle);
  if (!view || view->destroyed) {
    return;
  }
  const std::wstring text = utf8_to_wide(bytes_to_utf8(script));
  if (!view->ready) {
    view->document_scripts.push_back(text);
    return;
  }
  view->webview->AddScriptToExecuteOnDocumentCreated(text.c_str(), nullptr);
}

extern "C" MOONBIT_FFI_EXPORT void moonview_windows_set_zoom(uint64_t handle,
                                                                 double factor) {
  queue_or_run(find_view(handle), {Command::SetZoom, L"", "", factor});
}

extern "C" MOONBIT_FFI_EXPORT int32_t moonview_windows_open_devtools(uint64_t handle) {
  const std::shared_ptr<View> view = find_view(handle);
  if (!view || view->destroyed) {
    return 0;
  }
  queue_or_run(view, {Command::OpenDevTools, L"", ""});
  return 1;
}

extern "C" MOONBIT_FFI_EXPORT void moonview_windows_eval(uint64_t handle,
                                                             moonbit_bytes_t script,
                                                             moonbit_bytes_t request_id) {
  queue_or_run(find_view(handle),
               {Command::Eval, utf8_to_wide(bytes_to_utf8(script)), bytes_to_utf8(request_id)});
}

extern "C" MOONBIT_FFI_EXPORT void moonview_windows_post_message(uint64_t handle,
                                                                     moonbit_bytes_t message) {
  queue_or_run(find_view(handle),
               {Command::PostMessage, utf8_to_wide(bytes_to_utf8(message)), ""});
}

#else

using EventTrampoline = void (*)(void *, uint64_t, int32_t, moonbit_bytes_t,
                                 moonbit_bytes_t, int32_t);
using NavigationTrampoline = int32_t (*)(void *, uint64_t, moonbit_bytes_t);

extern "C" MOONBIT_FFI_EXPORT void moonview_windows_install_event_callback(
    EventTrampoline, void *) {}
extern "C" MOONBIT_FFI_EXPORT void moonview_windows_install_navigation_callback(
    NavigationTrampoline, void *) {}
extern "C" MOONBIT_FFI_EXPORT int32_t moonview_windows_available() { return 0; }
extern "C" MOONBIT_FFI_EXPORT uint64_t moonview_windows_create(
    uint64_t, int32_t, int32_t, int32_t, int32_t, moonbit_bytes_t, moonbit_bytes_t,
    moonbit_bytes_t, moonbit_bytes_t) { return 0; }
extern "C" MOONBIT_FFI_EXPORT void moonview_windows_start(uint64_t) {}
extern "C" MOONBIT_FFI_EXPORT int32_t moonview_windows_destroy(uint64_t) { return 0; }
extern "C" MOONBIT_FFI_EXPORT void moonview_windows_set_bounds(
    uint64_t, int32_t, int32_t, int32_t, int32_t) {}
extern "C" MOONBIT_FFI_EXPORT void moonview_windows_set_visible(uint64_t, int32_t) {}
extern "C" MOONBIT_FFI_EXPORT void moonview_windows_focus(uint64_t) {}
extern "C" MOONBIT_FFI_EXPORT void moonview_windows_navigate(uint64_t, moonbit_bytes_t) {}
extern "C" MOONBIT_FFI_EXPORT void moonview_windows_load_html(uint64_t, moonbit_bytes_t) {}
extern "C" MOONBIT_FFI_EXPORT void moonview_windows_reload(uint64_t) {}
extern "C" MOONBIT_FFI_EXPORT void moonview_windows_stop(uint64_t) {}
extern "C" MOONBIT_FFI_EXPORT void moonview_windows_go_back(uint64_t) {}
extern "C" MOONBIT_FFI_EXPORT void moonview_windows_go_forward(uint64_t) {}
extern "C" MOONBIT_FFI_EXPORT void moonview_windows_init(uint64_t, moonbit_bytes_t) {}
extern "C" MOONBIT_FFI_EXPORT void moonview_windows_set_zoom(uint64_t, double) {}
extern "C" MOONBIT_FFI_EXPORT int32_t moonview_windows_open_devtools(uint64_t) { return 0; }
extern "C" MOONBIT_FFI_EXPORT void moonview_windows_eval(
    uint64_t, moonbit_bytes_t, moonbit_bytes_t) {}
extern "C" MOONBIT_FFI_EXPORT void moonview_windows_post_message(
    uint64_t, moonbit_bytes_t) {}

#endif
