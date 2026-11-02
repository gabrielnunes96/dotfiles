#!/usr/bin/env bash
# Feeds cava's raw output to conky as a line of block characters.
out="${XDG_RUNTIME_DIR:-/run/user/$UID}/cava.txt"
exec cava -p ~/.config/cava/conky | awk -v f="$out" 'BEGIN { split("▁ ▂ ▃ ▄ ▅ ▆ ▇ █", c, " "); FS = ";" }
  { s = ""; for (i = 1; i < NF; i++) s = s c[$i + 1]; print s > f; close(f) }'
