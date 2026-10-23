#!/usr/bin/env bash
set -euo pipefail

# Super+V keeps the original toggle, but when entering floating mode it uses a
# predictable geometry: 60 % of the monitor's usable area, centred. The maths
# is done in logical coordinates so it also works with HiDPI scaling.
window_json=$(hyprctl activewindow -j)
mapfile -t window_data < <(
    jq -r '.address, (.floating | tostring), (.monitor | tostring)' <<<"$window_json"
)

window_address=${window_data[0]:-}
window_floating=${window_data[1]:-false}
window_monitor=${window_data[2]:-}

[[ "$window_address" =~ ^0x[0-9a-fA-F]+$ ]] || exit 0
window_selector="address:$window_address"

if [[ "$window_floating" == "true" ]]; then
    hyprctl dispatch "hl.dsp.window.float({ action = \"disable\", window = \"$window_selector\" })" >/dev/null
    exit 0
fi

mapfile -t target_size < <(
    hyprctl monitors -j | jq -r --argjson monitor_id "$window_monitor" '
        first(.[] | select(.id == $monitor_id)) as $monitor
        | ($monitor.scale // 1) as $scale
        | ($monitor.reserved // [0, 0, 0, 0]) as $reserved
        | (((($monitor.width / $scale) - $reserved[0] - $reserved[2]) * 0.60) | floor),
          (((($monitor.height / $scale) - $reserved[1] - $reserved[3]) * 0.60) | floor)
    '
)

# Fallback in case the monitor disappears right between the two queries (for
# example, when unplugging a dock): it uses the current size and still completes
# the gesture instead of leaving the window floating with an arbitrary geometry.
if (( ${#target_size[@]} < 2 )); then
    mapfile -t target_size < <(jq -r '(.size[0] * 0.60 | floor), (.size[1] * 0.60 | floor)' <<<"$window_json")
fi

target_width=${target_size[0]}
target_height=${target_size[1]}

hyprctl dispatch "hl.dsp.window.float({ action = \"enable\", window = \"$window_selector\" })" >/dev/null
hyprctl dispatch "hl.dsp.window.resize({ x = $target_width, y = $target_height, relative = false, window = \"$window_selector\" })" >/dev/null
hyprctl dispatch "hl.dsp.window.center({ window = \"$window_selector\" })" >/dev/null
