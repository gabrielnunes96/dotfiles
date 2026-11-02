#!/usr/bin/env bash
# Links everything under home/ into $HOME, applies the Cinnamon settings and
# regenerates the color-themed configs from the current wallpaper.
# Safe to run again: existing files that aren't links yet are moved to *.bak.
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
repo=$PWD

while IFS= read -r -d '' src; do
    rel=${src#home/}
    dest="$HOME/$rel"
    mkdir -p "$(dirname "$dest")"
    if [ -e "$dest" ] && [ ! -L "$dest" ]; then
        if cmp -s "$src" "$dest"; then
            rm "$dest"
        else
            mv "$dest" "$dest.bak"
            echo "backup: $dest.bak"
        fi
    fi
    ln -sfn "$repo/$src" "$dest"
done < <(find home -type f -print0)
echo "linked $(find home -type f | wc -l) files"

./cinnamon.sh

# starship/fastfetch/conky/lock screen configs are generated from the templates
wallpaper=$(gsettings get org.cinnamon.desktop.background picture-uri | tr -d "'" | sed 's|^file://||')
[ -f "$wallpaper" ] && "$HOME/.local/bin/wallcolor" "$wallpaper"
