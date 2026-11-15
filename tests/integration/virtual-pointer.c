// Test-only Wayland virtual pointer. Generate pointer-client.h and
// pointer-protocol.c from wlr-virtual-pointer-unstable-v1.xml before compiling.
#include <stdio.h>
#include <string.h>
#include <time.h>
#include <wayland-client.h>
#include "pointer-client.h"

static struct zwlr_virtual_pointer_manager_v1 *manager;
static void global(void *data, struct wl_registry *registry, uint32_t name,
                   const char *interface, uint32_t version) {
  if (!strcmp(interface, "zwlr_virtual_pointer_manager_v1"))
    manager = wl_registry_bind(registry, name, &zwlr_virtual_pointer_manager_v1_interface, 1);
}
static void removed(void *data, struct wl_registry *registry, uint32_t name) {}

int main(void) {
  struct wl_display *display = wl_display_connect(NULL);
  if (!display) return 1;
  struct wl_registry *registry = wl_display_get_registry(display);
  struct wl_registry_listener listener = {global, removed};
  wl_registry_add_listener(registry, &listener, NULL);
  wl_display_roundtrip(display);
  if (!manager) return 2;
  struct zwlr_virtual_pointer_v1 *pointer =
    zwlr_virtual_pointer_manager_v1_create_virtual_pointer(manager, NULL);
  char command[32];
  unsigned a, b;
  while (scanf("%31s %u %u", command, &a, &b) == 3) {
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    uint32_t ms = now.tv_sec * 1000u + now.tv_nsec / 1000000u;
    if (!strcmp(command, "move"))
      zwlr_virtual_pointer_v1_motion_absolute(pointer, ms, a, b, 1280, 800);
    else if (!strcmp(command, "button"))
      zwlr_virtual_pointer_v1_button(pointer, ms, a, b);
    else return 3;
    zwlr_virtual_pointer_v1_frame(pointer);
    if (wl_display_roundtrip(display) < 0) return 4;
    puts("ok");
    fflush(stdout);
  }
  zwlr_virtual_pointer_v1_destroy(pointer);
  wl_display_roundtrip(display);
  wl_display_disconnect(display);
}
