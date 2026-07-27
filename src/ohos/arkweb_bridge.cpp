#include <moonbit.h>

#if defined(__OHOS__)

#include <arkweb_interface.h>

#include <atomic>
#include <cstdint>
#include <map>
#include <string>

namespace {

enum EventKind : int32_t {
  kReady = 1,
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

struct View {
  std::string tag;
  bool detached = false;
};

EventTrampoline g_event_trampoline = nullptr;
void *g_event_closure = nullptr;
std::atomic<uint64_t> g_next_handle{1};
std::map<uint64_t, View> g_views;

std::string bytes_to_utf8(moonbit_bytes_t bytes) {
  if (bytes == nullptr) {
    return "";
  }
  const int32_t size = Moonbit_array_length(bytes);
  return size > 0 ? std::string(reinterpret_cast<const char *>(bytes), size) : "";
}

moonbit_bytes_t empty_bytes() {
  return moonbit_make_bytes(0, 0);
}

ArkWeb_ComponentAPI *component_api() {
  return reinterpret_cast<ArkWeb_ComponentAPI *>(
      OH_ArkWeb_GetNativeAPI(ARKWEB_NATIVE_COMPONENT));
}

ArkWeb_ControllerAPI *controller_api() {
  return reinterpret_cast<ArkWeb_ControllerAPI *>(
      OH_ArkWeb_GetNativeAPI(ARKWEB_NATIVE_CONTROLLER));
}

bool has_component_api(ArkWeb_ComponentAPI *api) {
  return api != nullptr && !ARKWEB_MEMBER_MISSING(api, onControllerAttached) &&
         !ARKWEB_MEMBER_MISSING(api, onDestroy);
}

bool has_controller_api(ArkWeb_ControllerAPI *api) {
  return api != nullptr && !ARKWEB_MEMBER_MISSING(api, refresh) &&
         !ARKWEB_MEMBER_MISSING(api, runJavaScript);
}

View *find_view(uint64_t handle) {
  auto it = g_views.find(handle);
  return it == g_views.end() ? nullptr : &it->second;
}

void on_controller_attached(const char *web_tag, void *user_data) {
  const uint64_t handle = static_cast<uint64_t>(reinterpret_cast<uintptr_t>(user_data));
  View *view = find_view(handle);
  if (view == nullptr || view->detached || web_tag == nullptr || view->tag != web_tag ||
      g_event_trampoline == nullptr) {
    return;
  }
  g_event_trampoline(g_event_closure, handle, kReady, empty_bytes(), empty_bytes(), 0);
}

void on_destroy(const char *web_tag, void *user_data) {
  const uint64_t handle = static_cast<uint64_t>(reinterpret_cast<uintptr_t>(user_data));
  View *view = find_view(handle);
  if (view != nullptr && web_tag != nullptr && view->tag == web_tag) {
    view->detached = true;
  }
}

}  // namespace

extern "C" MOONBIT_FFI_EXPORT void moonview_ohos_install_event_callback(
    EventTrampoline trampoline, void *closure) {
  if (g_event_closure != nullptr) {
    moonbit_decref(g_event_closure);
  }
  g_event_trampoline = trampoline;
  g_event_closure = closure;
}

extern "C" MOONBIT_FFI_EXPORT void moonview_ohos_install_navigation_callback(
    NavigationTrampoline, void *) {}

extern "C" MOONBIT_FFI_EXPORT void moonview_ohos_install_protocol_callback(
    ProtocolTrampoline, void *) {}

extern "C" MOONBIT_FFI_EXPORT void moonview_ohos_install_media_permission_callback(
    MediaPermissionTrampoline, void *) {}

extern "C" MOONBIT_FFI_EXPORT int32_t moonview_ohos_available() {
  return 1;
}

extern "C" MOONBIT_FFI_EXPORT uint64_t moonview_ohos_attach(moonbit_bytes_t web_tag) {
  const std::string tag = bytes_to_utf8(web_tag);
  if (tag.empty() || !has_component_api(component_api()) || !has_controller_api(controller_api())) {
    return 0;
  }
  const uint64_t handle = g_next_handle.fetch_add(1);
  g_views.emplace(handle, View{tag, false});
  return handle;
}

extern "C" MOONBIT_FFI_EXPORT void moonview_ohos_start(uint64_t handle) {
  View *view = find_view(handle);
  ArkWeb_ComponentAPI *component = component_api();
  if (view == nullptr || view->detached || !has_component_api(component)) {
    return;
  }
  void *user_data = reinterpret_cast<void *>(static_cast<uintptr_t>(handle));
  component->onControllerAttached(view->tag.c_str(), on_controller_attached, user_data);
  component->onDestroy(view->tag.c_str(), on_destroy, user_data);
}

extern "C" MOONBIT_FFI_EXPORT int32_t moonview_ohos_destroy(uint64_t handle) {
  View *view = find_view(handle);
  if (view == nullptr) {
    return 1;
  }
  view->detached = true;
  g_views.erase(handle);
  return 1;
}

extern "C" MOONBIT_FFI_EXPORT int32_t moonview_ohos_reload(uint64_t handle) {
  View *view = find_view(handle);
  ArkWeb_ControllerAPI *controller = controller_api();
  if (view == nullptr || view->detached || !has_controller_api(controller)) return 0;
  controller->refresh(view->tag.c_str());
  return 1;
}

extern "C" MOONBIT_FFI_EXPORT int32_t moonview_ohos_eval(uint64_t handle,
                                                         moonbit_bytes_t script) {
  View *view = find_view(handle);
  ArkWeb_ControllerAPI *controller = controller_api();
  if (view == nullptr || view->detached || !has_controller_api(controller)) {
    return 0;
  }
  const std::string source = bytes_to_utf8(script);
  ArkWeb_JavaScriptObject object{
      reinterpret_cast<const uint8_t *>(source.data()), source.size(), nullptr, nullptr};
  controller->runJavaScript(view->tag.c_str(), &object);
  return 1;
}

#else

using EventTrampoline = void (*)(void *, uint64_t, int32_t, moonbit_bytes_t,
                                 moonbit_bytes_t, int32_t);
using NavigationTrampoline = int32_t (*)(void *, uint64_t, moonbit_bytes_t);
using ProtocolTrampoline = void (*)(void *, uint64_t, moonbit_bytes_t,
                                    moonbit_bytes_t, moonbit_bytes_t,
                                    moonbit_bytes_t, moonbit_bytes_t,
                                    moonbit_bytes_t);
using MediaPermissionTrampoline = int32_t (*)(void *, uint64_t, int32_t,
                                              moonbit_bytes_t);

extern "C" MOONBIT_FFI_EXPORT void moonview_ohos_install_event_callback(
    EventTrampoline, void *) {}
extern "C" MOONBIT_FFI_EXPORT void moonview_ohos_install_navigation_callback(
    NavigationTrampoline, void *) {}
extern "C" MOONBIT_FFI_EXPORT void moonview_ohos_install_protocol_callback(
    ProtocolTrampoline, void *) {}
extern "C" MOONBIT_FFI_EXPORT void moonview_ohos_install_media_permission_callback(
    MediaPermissionTrampoline, void *) {}
extern "C" MOONBIT_FFI_EXPORT int32_t moonview_ohos_available() { return 0; }
extern "C" MOONBIT_FFI_EXPORT uint64_t moonview_ohos_attach(moonbit_bytes_t) { return 0; }
extern "C" MOONBIT_FFI_EXPORT void moonview_ohos_start(uint64_t) {}
extern "C" MOONBIT_FFI_EXPORT int32_t moonview_ohos_destroy(uint64_t) { return 0; }
extern "C" MOONBIT_FFI_EXPORT int32_t moonview_ohos_reload(uint64_t) { return 0; }
extern "C" MOONBIT_FFI_EXPORT int32_t moonview_ohos_eval(uint64_t, moonbit_bytes_t) { return 0; }

#endif
