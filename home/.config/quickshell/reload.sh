#!/usr/bin/env bash
# Clean reload of Quickshell (bar + notch + sidebar + overview + wallpaper).
# Normally it is NOT needed: quickshell watches its .qml files and hot-reloads.
# This is the safety net for when something gets stuck.

# ONE reload at a time. Pressing Super+G several times in a row opened several
# bars: each copy of the script killed qs, slept 0.4s by guesswork and started
# its own, so the three pkills were spent at the start -- when there was still
# nothing to kill -- and the three qs were born afterwards, without getting in
# each other's way. The lock discards presses that arrive while a reload is
# running, which is what you want: there is no point queueing reloads.
exec 9>"${XDG_RUNTIME_DIR:-/tmp}/quickshell-reload.lock"
flock -n 9 || exit 0

pkill -x qs 2>/dev/null

# Wait for it to die FOR REAL instead of trusting a fixed sleep: if it takes
# longer than expected, the old one and the new one end up overlapping.
for _ in {1..50}; do
    pgrep -x qs >/dev/null || break
    sleep 0.1
done
pgrep -x qs >/dev/null && pkill -9 -x qs 2>/dev/null

# Bring it up through systemd, NOT with 'setsid -f qs'. A loose qs does not
# hang off quickshell.service, so it is left without the unit's supervision: if
# it segfaults (it happened on 2026-08-05), nobody brings it back and you are
# left with no bar and no notch. On top of that the pkill above sends SIGTERM,
# which systemd counts as a clean exit, so with Restart=on-failure it does not
# restart it either: the first press of Super+G left the shell orphaned until
# the next login.
#
# The earlier pkill is still needed: with --no-duplicate, if any qs from
# outside the unit survives, the one systemd starts withdraws by itself.
#
# The unit has StartLimitBurst=5 in 60s so it does not retry in a loop with a
# broken QML config. Hammering Super+G hits that limit and the restart fails,
# so the counter is cleared and it retries before giving up.
if ! systemctl --user restart quickshell.service 2>/dev/null; then
    systemctl --user reset-failed quickshell.service 2>/dev/null
    if ! systemctl --user restart quickshell.service 2>/dev/null; then
        # No user systemd (or a broken unit): at least leave the shell running.
        #
        # 9>&- is NOT decorative: descriptors are inherited, so without it qs
        # keeps hold of the lock for as long as it lives and the next Super+G
        # finds the flock taken and does nothing. The shortcut stopped working
        # after the first time.
        setsid -f qs -n >/dev/null 2>&1 </dev/null 9>&-
    fi
fi

# The lock is released on exit, so do not exit until the new qs is up:
# otherwise a second press would come in and kill it halfway through starting.
for _ in {1..30}; do
    pgrep -x qs >/dev/null && break
    sleep 0.1
done
