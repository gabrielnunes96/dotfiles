#!/usr/bin/env bash
# Starts the desktop widgets (clocks on both monitors, now playing + visualizer).
pkill -x conky; pkill -f cava-bars.sh; pkill -x cava
sleep 2
dir=~/.config/conky
"$dir/cava-bars.sh" &
for c in clock-2k clock-fhd nowplaying nowplaying-fhd; do conky -d -c "$dir/$c.conf"; done
