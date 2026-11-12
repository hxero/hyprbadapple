#define _POSIX_C_SOURCE 200809L
#include <stdint.h>
#include <stdio.h>
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

#define DEFAULT_W 256
#define DEFAULT_H 256
#define FILL_COLOR 0xFF000000 // ARGB8888: alpha 0xFF, fully opaque black

static struct wl_compositor* compositor;
static struct wl_shm*        shm;
static struct xdg_wm_base*   wm_base;

static struct wl_surface* surface;

static int configured;
static int running = 1;

// size requested by the compositor (0 means "client decides")
static int32_t pending_w, pending_h;
// size of the buffer we currently show
static int32_t cur_w, cur_h;

// ---------------------------------------------------------------- registry
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

// ---------------------------------------------------------------- wm_base
static void wm_base_ping(void* d, struct xdg_wm_base* base, uint32_t serial) {
    xdg_wm_base_pong(base, serial);
}
static const struct xdg_wm_base_listener wm_base_listener = {wm_base_ping};

// ---------------------------------------------------------------- buffers
static int create_shm_file(off_t size) {
    const char* dir = getenv("XDG_RUNTIME_DIR");
    char        path[512];
    snprintf(path, sizeof path, "%s/box-XXXXXX", dir ? dir : "/dev/shm");

    int fd = mkstemp(path);
    if (fd < 0)
        return -1;
    unlink(path);
    if (ftruncate(fd, size) < 0) {
        close(fd);
        return -1;
    }
    return fd;
}

static void buffer_release(void* data, struct wl_buffer* buf) {
    wl_buffer_destroy(buf);
}
static const struct wl_buffer_listener buffer_listener = {buffer_release};

static void draw_frame(int32_t w, int32_t h) {
    int32_t stride = w * 4;
    int32_t size   = stride * h;

    int fd = create_shm_file(size);
    if (fd < 0) {
        fprintf(stderr, "failed to create shm file\n");
        exit(1);
    }

    uint32_t* data =
        mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (data == MAP_FAILED) {
        fprintf(stderr, "mmap failed\n");
        close(fd);
        exit(1);
    }
    for (int32_t i = 0; i < w * h; i++)
        data[i] = FILL_COLOR;
    munmap(data, size);

    struct wl_shm_pool* pool   = wl_shm_create_pool(shm, fd, size);
    struct wl_buffer*   buffer = wl_shm_pool_create_buffer(
        pool, 0, w, h, stride, WL_SHM_FORMAT_ARGB8888);
    wl_shm_pool_destroy(pool);
    close(fd);
    wl_buffer_add_listener(buffer, &buffer_listener, NULL);

    // tell the compositor the whole surface is opaque
    struct wl_region* region = wl_compositor_create_region(compositor);
    wl_region_add(region, 0, 0, w, h);
    wl_surface_set_opaque_region(surface, region);
    wl_region_destroy(region);

    wl_surface_attach(surface, buffer, 0, 0);
    wl_surface_damage_buffer(surface, 0, 0, w, h);
    wl_surface_commit(surface);

    cur_w = w;
    cur_h = h;
}

// ---------------------------------------------------------------- xdg
static void xdg_surface_configure(void*               d,
                                  struct xdg_surface* s,
                                  uint32_t            serial) {
    xdg_surface_ack_configure(s, serial);

    int32_t w = pending_w > 0 ? pending_w : (cur_w > 0 ? cur_w : DEFAULT_W);
    int32_t h = pending_h > 0 ? pending_h : (cur_h > 0 ? cur_h : DEFAULT_H);

    // always attach a buffer after acking a configure so the window
    // content matches the size the compositor gave us
    draw_frame(w, h);
    configured = 1;
}
static const struct xdg_surface_listener xdg_surface_listener = {
    xdg_surface_configure};

static void toplevel_configure(void*                d,
                               struct xdg_toplevel* tl,
                               int32_t              w,
                               int32_t              h,
                               struct wl_array*     states) {
    // applied on the following xdg_surface.configure
    pending_w = w;
    pending_h = h;
}
static void toplevel_close(void* d, struct xdg_toplevel* tl) {
    running = 0;
}
static const struct xdg_toplevel_listener toplevel_listener = {
    toplevel_configure, toplevel_close};

// ---------------------------------------------------------------- main
int main(void) {
    struct wl_display* display = wl_display_connect(NULL);
    if (!display) {
        fprintf(stderr, "failed to connect to wayland display\n");
        return 1;
    }

    struct wl_registry* registry = wl_display_get_registry(display);
    wl_registry_add_listener(registry, &registry_listener, NULL);
    wl_display_roundtrip(display);

    if (!compositor || !shm || !wm_base) {
        fprintf(stderr, "missing required wayland globals\n");
        return 1;
    }

    xdg_wm_base_add_listener(wm_base, &wm_base_listener, NULL);

    surface = wl_compositor_create_surface(compositor);
    struct xdg_surface* xdg_surface =
        xdg_wm_base_get_xdg_surface(wm_base, surface);
    struct xdg_toplevel* toplevel = xdg_surface_get_toplevel(xdg_surface);

    xdg_surface_add_listener(xdg_surface, &xdg_surface_listener, NULL);
    xdg_toplevel_add_listener(toplevel, &toplevel_listener, NULL);

    xdg_toplevel_set_title(toplevel, "box");
    xdg_toplevel_set_app_id(toplevel, "box");

    // initial commit WITHOUT a buffer; the compositor answers with a configure
    wl_surface_commit(surface);

    // the configure handler acks and attaches the first correctly sized buffer
    while (!configured && wl_display_dispatch(display) != -1) {
    }

    while (running && wl_display_dispatch(display) != -1) {
    }

    xdg_toplevel_destroy(toplevel);
    xdg_surface_destroy(xdg_surface);
    wl_surface_destroy(surface);
    wl_display_disconnect(display);
    return 0;
}
