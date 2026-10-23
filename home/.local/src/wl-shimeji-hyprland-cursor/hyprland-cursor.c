/*
 * hyprland-cursor — a wl_shimeji plugin that tells it where the mouse is.
 *
 * WHY IT IS NEEDED. Inside wl_shimeji, `mascot.environment.cursor.x/y` is
 * (0,0) ALWAYS, except while you drag a critter with the button held down:
 * the only function that writes that position is environment_set_public_cursor_position(),
 * and its only caller is the callback wl_shimeji hands to plugins. No plugin,
 * no cursor.
 *
 * The consequence shows on screen: the chase-the-mouse behaviour uses
 * `cursor.x` as its target, so the Pokémon ran to the top-left corner over and
 * over. That is what looked like "broken interaction"; it was not broken, it
 * was chasing a ghost at (0,0).
 *
 * Wayland does not let just any client ask where the pointer is —it only knows
 * when the pointer is over its own surface—, and that is why the author left
 * this to plugins: each compositor solves it its own way. Here Hyprland is
 * asked through its control socket, the same one `hyprctl cursorpos` uses.
 *
 * Build and install:  make        (see the Makefile next to it)
 *
 * Licence: GPL-2.0-or-later, like wl_shimeji, which it links against.
 */

#include <wl_shimeji/plugins.h>

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <sys/un.h>

/* The tick runs at ~25 Hz and has a 40 ms budget. Asking through the socket
 * costs tenths of a millisecond, but there is no need to do it 25 times a
 * second either: every two ticks is ~12 queries/s, plenty for the critter to
 * follow you without the movement looking jerky. */
#define CADA_CUANTOS_TICKS 2

static set_cursor_pos_func poner_cursor = NULL;
static char ruta_socket[512];
static int  cuenta_ticks = 0;
static int  fallos_seguidos = 0;

/* If Hyprland does not answer twenty times in a row, it stops insisting: the
 * session may have changed. Better a critter that does not follow you than one
 * that spends its time budget on retries. */
#define MAX_FALLOS 20

static int preguntar_cursor(int32_t *x, int32_t *y)
{
    int fd = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
    if (fd < 0)
        return -1;

    struct sockaddr_un dir = {0};
    dir.sun_family = AF_UNIX;
    /* sun_path is exactly 108 bytes, and Hyprland's instance signature is
     * long. If it does not fit, give up here: copying it truncated would give
     * a valid but wrong path, and the failure would show up as "does not
     * connect" without saying why. */
    if (strlen(ruta_socket) >= sizeof(dir.sun_path)) {
        close(fd);
        return -1;
    }
    memcpy(dir.sun_path, ruta_socket, strlen(ruta_socket) + 1);

    if (connect(fd, (struct sockaddr *)&dir, sizeof(dir)) < 0) {
        close(fd);
        return -1;
    }

    static const char peticion[] = "cursorpos";
    if (write(fd, peticion, sizeof(peticion) - 1) < 0) {
        close(fd);
        return -1;
    }

    char respuesta[64] = {0};
    ssize_t leidos = read(fd, respuesta, sizeof(respuesta) - 1);
    close(fd);
    if (leidos <= 0)
        return -1;

    /* Hyprland answers "1366, 716" */
    int rx = 0, ry = 0;
    if (sscanf(respuesta, "%d, %d", &rx, &ry) != 2)
        return -1;

    *x = (int32_t)rx;
    *y = (int32_t)ry;
    return 0;
}

int wl_shimeji_plugin_init(plugin_t *self,
                           set_cursor_pos_func cursor_cb,
                           set_active_ie_func active_ie_cb,
                           window_moved_hint_func window_moved_cb)
{
    (void)active_ie_cb;      /* windows are handled by another plugin, not here */
    (void)window_moved_cb;

    const char *runtime = getenv("XDG_RUNTIME_DIR");
    const char *firma   = getenv("HYPRLAND_INSTANCE_SIGNATURE");
    if (!runtime || !firma)
        return -1;           /* not a Hyprland session: do not load */

    int n = snprintf(ruta_socket, sizeof(ruta_socket),
                     "%s/hypr/%s/.socket.sock", runtime, firma);
    if (n < 0 || (size_t)n >= sizeof(ruta_socket))
        return -1;

    /* It must answer BEFORE being accepted: if the socket is not there, it is
     * better not to load than to keep trying on every tick. */
    int32_t x = 0, y = 0;
    if (preguntar_cursor(&x, &y) != 0)
        return -1;

    poner_cursor = cursor_cb;

    return plugin_init(self,
                       "hyprland-cursor",
                       "1.0",
                       "diego",
                       "global mouse position via the Hyprland control socket",
                       version_to_i64(WL_SHIMEJI_PLUGIN_TARGET_VERSION));
}

int wl_shimeji_plugin_tick(plugin_t *self)
{
    (void)self;
    if (!poner_cursor || fallos_seguidos >= MAX_FALLOS)
        return 0;

    if (++cuenta_ticks < CADA_CUANTOS_TICKS)
        return 0;
    cuenta_ticks = 0;

    int32_t x = 0, y = 0;
    if (preguntar_cursor(&x, &y) != 0) {
        fallos_seguidos++;
        return 0;            /* one stray failure is no reason to crash */
    }
    fallos_seguidos = 0;
    poner_cursor(x, y);
    return 0;
}

void wl_shimeji_plugin_deinit(plugin_t *self)
{
    poner_cursor = NULL;
    plugin_deinit(self);
}
