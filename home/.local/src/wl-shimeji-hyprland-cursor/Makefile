# hyprland-cursor — a wl_shimeji plugin
#
# It installs into ~/.local/lib/wl_shimeji and NOT into /usr/lib/wl_shimeji,
# which is where it is looked for by default: that way it needs no sudo and is
# not lost when the package updates. The daemon is told the path with the
# plugins_location key in ~/.local/share/wl_shimeji/shimeji-overlayd.conf,
# which exists precisely for this.

DESTINO := $(HOME)/.local/lib/wl_shimeji
OBJETIVO := $(DESTINO)/hyprland-cursor.so

CFLAGS  += -O2 -Wall -Wextra -fPIC -std=c11
LDFLAGS += -shared
LDLIBS  += -lwayland-shimeji-plugins

.PHONY: all instalar limpiar

all: hyprland-cursor.so

hyprland-cursor.so: hyprland-cursor.c
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $< $(LDLIBS)

instalar: hyprland-cursor.so
	install -d $(DESTINO)
	install -m 0755 hyprland-cursor.so $(OBJETIVO)
	@echo "installed in $(OBJETIVO)"
	@echo "remember: plugins_location=$(DESTINO) in ~/.local/share/wl_shimeji/shimeji-overlayd.conf"

limpiar:
	rm -f hyprland-cursor.so
