#!/usr/bin/env bash
# Starts the desktop widgets (clocks on both monitors, now playing + visualizer).
# Serialized: two quick wallpaper changes must not both start a set of widgets.
exec 9>"${XDG_RUNTIME_DIR:-/tmp}/conky-start.lock"
flock 9
pkill -x conky; pkill -x cava-bars.sh; pkill -x cava
sleep 2
dir=~/.config/conky
"$dir/cava-bars.sh" 9>&- &
for c in clock-2k clock-fhd nowplaying nowplaying-fhd; do conky -d -c "$dir/$c.conf" 9>&-; done
