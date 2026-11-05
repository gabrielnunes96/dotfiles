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

# cloud drives: mount every rclone remote at ~/Nuvem/<name>, with a sidebar entry
if command -v rclone >/dev/null; then
    systemctl --user daemon-reload
    bookmarks=$HOME/.config/gtk-3.0/bookmarks
    for remote in $(rclone listremotes | tr -d ':'); do
        systemctl --user enable --now "rclone-mount@$remote"
        entry="file://$HOME/Nuvem/$remote $remote"
        grep -qxF "$entry" "$bookmarks" || echo "$entry" >> "$bookmarks"
        echo "nuvem: $remote em ~/Nuvem/$remote"
    done
fi

# starship/fastfetch/conky/lock screen configs are generated from the templates
wallpaper=$(gsettings get org.cinnamon.desktop.background picture-uri | tr -d "'" | sed 's|^file://||')
[ -f "$wallpaper" ] && "$HOME/.local/bin/wallcolor" "$wallpaper"
