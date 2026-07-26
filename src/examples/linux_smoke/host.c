#if defined(__linux__)

#include <gtk/gtk.h>
#include <moonbit.h>
#include <stdint.h>

static GtkWidget *moonview_smoke_window = NULL;
static guint moonview_smoke_timeout = 0;
static int32_t moonview_smoke_status = 1;

static gboolean moonview_smoke_timeout_callback(gpointer data) {
  (void)data;
  moonview_smoke_status = 1;
  gtk_main_quit();
  return G_SOURCE_REMOVE;
}

static void moonview_smoke_destroy_callback(GtkWidget *widget, gpointer data) {
  (void)widget;
  (void)data;
  moonview_smoke_window = NULL;
  if (moonview_smoke_timeout != 0) {
    g_source_remove(moonview_smoke_timeout);
    moonview_smoke_timeout = 0;
  }
  gtk_main_quit();
}

MOONBIT_FFI_EXPORT uint64_t moonview_linux_smoke_create_host(int32_t width,
                                                              int32_t height) {
  int argc = 0;
  char **argv = NULL;
  if (!gtk_init_check(&argc, &argv)) {
    return 0;
  }
  moonview_smoke_window = gtk_window_new(GTK_WINDOW_TOPLEVEL);
  GtkWidget *fixed = gtk_fixed_new();
  gtk_window_set_default_size(GTK_WINDOW(moonview_smoke_window), width, height);
  gtk_container_add(GTK_CONTAINER(moonview_smoke_window), fixed);
  g_signal_connect(moonview_smoke_window, "destroy",
                   G_CALLBACK(moonview_smoke_destroy_callback), NULL);
  gtk_widget_show_all(moonview_smoke_window);
  moonview_smoke_timeout = g_timeout_add_seconds(30, moonview_smoke_timeout_callback, NULL);
  return (uint64_t)(uintptr_t)fixed;
}

MOONBIT_FFI_EXPORT int32_t moonview_linux_smoke_run_loop(void) {
  gtk_main();
  return moonview_smoke_status;
}

MOONBIT_FFI_EXPORT void moonview_linux_smoke_succeed(void) {
  moonview_smoke_status = 0;
  if (moonview_smoke_window != NULL) {
    gtk_widget_destroy(moonview_smoke_window);
  } else {
    gtk_main_quit();
  }
}

#else

#include <moonbit.h>
#include <stdint.h>

MOONBIT_FFI_EXPORT uint64_t moonview_linux_smoke_create_host(int32_t width,
                                                              int32_t height) {
  (void)width;
  (void)height;
  return 0;
}
MOONBIT_FFI_EXPORT int32_t moonview_linux_smoke_run_loop(void) { return 1; }
MOONBIT_FFI_EXPORT void moonview_linux_smoke_succeed(void) {}

#endif
