#if defined(__APPLE__)

#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CoreGraphics.h>
#include <objc/message.h>
#include <objc/runtime.h>

#include <moonbit.h>

#include <cstdint>

namespace {

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

id g_window = nil;
id g_parent = nil;
bool g_succeeded = false;

} // namespace

extern "C" MOONBIT_FFI_EXPORT uint64_t moonview_macos_smoke_create_host(
    int32_t width, int32_t height) {
  id application = send<id>(class_object("NSApplication"), selector("sharedApplication"));
  if (application == nil) {
    return 0;
  }
  g_window = send<id>(class_object("NSWindow"), selector("alloc"));
  const CGRect frame = CGRectMake(0, 0, static_cast<CGFloat>(width),
                                  static_cast<CGFloat>(height));
  g_window = send<id, CGRect, unsigned long, unsigned long, BOOL>(
      g_window, selector("initWithContentRect:styleMask:backing:defer:"), frame,
      0UL, 2UL, NO);
  if (g_window == nil) {
    return 0;
  }
  g_parent = send<id>(g_window, selector("contentView"));
  return reinterpret_cast<uint64_t>(g_parent);
}

extern "C" MOONBIT_FFI_EXPORT int32_t moonview_macos_smoke_run_loop() {
  const CFAbsoluteTime deadline = CFAbsoluteTimeGetCurrent() + 30.0;
  while (!g_succeeded && CFAbsoluteTimeGetCurrent() < deadline) {
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.01, true);
  }
  return g_succeeded ? 0 : 1;
}

extern "C" MOONBIT_FFI_EXPORT void moonview_macos_smoke_succeed() {
  g_succeeded = true;
}

extern "C" MOONBIT_FFI_EXPORT void moonview_macos_smoke_destroy_host() {
  release_object(g_window);
  g_window = nil;
  g_parent = nil;
}

#else

#include <moonbit.h>

#include <cstdint>

extern "C" MOONBIT_FFI_EXPORT uint64_t moonview_macos_smoke_create_host(
    int32_t, int32_t) { return 0; }
extern "C" MOONBIT_FFI_EXPORT int32_t moonview_macos_smoke_run_loop() { return 1; }
extern "C" MOONBIT_FFI_EXPORT void moonview_macos_smoke_succeed() {}
extern "C" MOONBIT_FFI_EXPORT void moonview_macos_smoke_destroy_host() {}

#endif
