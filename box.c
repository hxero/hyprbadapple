#define _POSIX_C_SOURCE 200809L
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>
#include <wayland-client.h>
#include "xdg-shell-client-protocol.h"

// -- build

// wayland-scanner private-code \
//  < /usr/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml \
//  > xdg-shell-protocol.c

// wayland-scanner client-header \
//   < /usr/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml \
//   > xdg-shell-client-protocol.h

// gcc -o box box.c xdg-shell-protocol.c -lwayland-client

static struct wl_compositor* compositor;
static struct wl_shm*        shm;
static struct xdg_wm_base*   wm_base;

static int configured;

// init
static void registry_global(void*               data,
                            struct wl_registry* reg,
                            uint32_t            name,
                            const char*         iface,
                            uint32_t            ver) {
    if (!strcmp(iface, wl_compositor_interface.name))
        compositor = wl_registry_bind(reg, name, &wl_compositor_interface, 4);
    else if (!strcmp(iface, wl_shm_interface.name))
        shm = wl_registry_bind(reg, name, &wl_shm_interface, 1);
    else if (!strcmp(iface, xdg_wm_base_interface.name))
        wm_base = wl_registry_bind(reg, name, &xdg_wm_base_interface, 1);
}
static void registry_global_remove(void* d, struct wl_registry* r, uint32_t n) {
}
static const struct wl_registry_listener registry_listener = {
    registry_global, registry_global_remove};

static void wm_base_ping(void* d, struct xdg_wm_base* base, uint32_t serial) {
    xdg_wm_base_pong(base, serial);
}
static const struct xdg_wm_base_listener wm_base_listener = {wm_base_ping};

static void xdg_surface_configure(void*               d,
                                  struct xdg_surface* s,
                                  uint32_t            serial) {
    xdg_surface_ack_configure(s, serial);
    configured = 1;
}
static const struct xdg_surface_listener xdg_surface_listener = {
    xdg_surface_configure};

static void toplevel_configure(void*                d,
                               struct xdg_toplevel* tl,
                               int32_t              w,
                               int32_t              h,
                               struct wl_array*     states) {}
static void toplevel_close(void* d, struct xdg_toplevel* tl) {
    exit(0);
}
static const struct xdg_toplevel_listener toplevel_listener = {
    toplevel_configure, toplevel_close};

int main(void) {
    struct wl_display*  display  = wl_display_connect(NULL);
    struct wl_registry* registry = wl_display_get_registry(display);
    wl_registry_add_listener(registry, &registry_listener, NULL);
    wl_display_roundtrip(display);

    xdg_wm_base_add_listener(wm_base, &wm_base_listener, NULL);

    struct wl_surface*  surface = wl_compositor_create_surface(compositor);
    struct xdg_surface* xdg_surface =
        xdg_wm_base_get_xdg_surface(wm_base, surface);
    struct xdg_toplevel* toplevel = xdg_surface_get_toplevel(xdg_surface);

    xdg_surface_add_listener(xdg_surface, &xdg_surface_listener, NULL);
    xdg_toplevel_add_listener(toplevel, &toplevel_listener, NULL);
    wl_surface_commit(surface);

    while (!configured)
        wl_display_dispatch(display);

    int  stride = 4, size = 4;
    char path[] = "/dev/shm/box-XXXXXX";
    int  fd     = mkstemp(path);
    unlink(path);
    ftruncate(fd, size);
    uint32_t* data =
        mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    *data = 0x00000000;
    munmap(data, size);

    struct wl_shm_pool* pool   = wl_shm_create_pool(shm, fd, size);
    struct wl_buffer*   buffer = wl_shm_pool_create_buffer(
        pool, 0, 1, 1, stride, WL_SHM_FORMAT_XRGB8888);
    wl_shm_pool_destroy(pool);
    close(fd);

    wl_surface_attach(surface, buffer, 0, 0);
    wl_surface_damage_buffer(surface, 0, 0, 1, 1);
    wl_surface_commit(surface);

    while (wl_display_dispatch(display) != -1) {
    }
    return 0;
}
