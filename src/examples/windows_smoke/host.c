#include <moonbit.h>
#include <stdint.h>

#ifdef _WIN32
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>

static const wchar_t *moonview_smoke_class = L"MoonviewSmokeHost";
static HWND moonview_smoke_window = NULL;
static UINT_PTR moonview_smoke_timer = 0;

static LRESULT CALLBACK moonview_smoke_wndproc(HWND hwnd, UINT message,
                                                WPARAM wparam, LPARAM lparam) {
  (void)wparam;
  (void)lparam;
  switch (message) {
  case WM_TIMER:
    DestroyWindow(hwnd);
    return 0;
  case WM_DESTROY:
    if (moonview_smoke_timer != 0) {
      KillTimer(hwnd, moonview_smoke_timer);
      moonview_smoke_timer = 0;
    }
    moonview_smoke_window = NULL;
    PostQuitMessage(1);
    return 0;
  default:
    return DefWindowProcW(hwnd, message, wparam, lparam);
  }
}

MOONBIT_FFI_EXPORT uint64_t moonview_smoke_create_host_window(int32_t width,
                                                                int32_t height) {
  HINSTANCE instance = GetModuleHandleW(NULL);
  WNDCLASSW wc = {0};
  wc.hInstance = instance;
  wc.lpszClassName = moonview_smoke_class;
  wc.lpfnWndProc = moonview_smoke_wndproc;
  wc.hCursor = LoadCursorW(NULL, MAKEINTRESOURCEW(32512));
  RegisterClassW(&wc);

  HWND hwnd = CreateWindowExW(0, moonview_smoke_class, L"moonview smoke",
                              WS_OVERLAPPEDWINDOW, CW_USEDEFAULT, CW_USEDEFAULT,
                              width, height, NULL, NULL, instance, NULL);
  if (hwnd == NULL) {
    return 0;
  }
  moonview_smoke_window = hwnd;
  ShowWindow(hwnd, SW_SHOW);
  moonview_smoke_timer = SetTimer(hwnd, 1, 30000, NULL);
  return (uint64_t)(uintptr_t)hwnd;
}

MOONBIT_FFI_EXPORT int32_t moonview_smoke_run_host_message_loop(void) {
  MSG message;
  while (GetMessageW(&message, NULL, 0, 0) > 0) {
    TranslateMessage(&message);
    DispatchMessageW(&message);
  }
  return (int32_t)message.wParam;
}

MOONBIT_FFI_EXPORT void moonview_smoke_close_host_window(void) {
  if (moonview_smoke_window != NULL) {
    DestroyWindow(moonview_smoke_window);
  }
}

MOONBIT_FFI_EXPORT void moonview_smoke_destroy_host_window(void) {
  if (moonview_smoke_window != NULL) {
    DestroyWindow(moonview_smoke_window);
  }
}
#else
MOONBIT_FFI_EXPORT uint64_t moonview_smoke_create_host_window(int32_t width,
                                                                int32_t height) {
  (void)width;
  (void)height;
  return 0;
}
MOONBIT_FFI_EXPORT int32_t moonview_smoke_run_host_message_loop(void) { return 1; }
MOONBIT_FFI_EXPORT void moonview_smoke_close_host_window(void) {}
MOONBIT_FFI_EXPORT void moonview_smoke_destroy_host_window(void) {}
#endif
