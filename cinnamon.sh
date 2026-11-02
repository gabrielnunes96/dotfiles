#!/usr/bin/env bash
# Cinnamon settings that live in dconf rather than in files.
set -euo pipefail

# Print / Shift+Print / Alt+Print copy to the clipboard; with Ctrl they save to a file
s=org.cinnamon.desktop.keybindings.media-keys
gsettings set $s screenshot-clip "['Print']"
gsettings set $s area-screenshot-clip "['<Shift>Print']"
gsettings set $s window-screenshot-clip "['<Alt>Print']"
gsettings set $s screenshot "['<Control>Print']"
gsettings set $s area-screenshot "['<Control><Shift>Print']"
gsettings set $s window-screenshot "['<Control><Alt>Print']"

# custom shortcuts: Super+V clipboard history, Super+W wallpaper picker
custom() { # $1=slot $2=name $3=command $4=binding
    local p=org.cinnamon.desktop.keybindings.custom-keybinding:/org/cinnamon/desktop/keybindings/custom-keybindings/$1/
    gsettings set "$p" name "$2"
    gsettings set "$p" command "$3"
    gsettings set "$p" binding "['$4']"
}
custom custom0 'Clipboard history' 'copyq menu' '<Super>v'
custom custom1 'Wallpaper picker' "$HOME/.local/bin/wallpicker" '<Super>w'
gsettings set org.cinnamon.desktop.keybindings custom-list "['custom0', 'custom1']"
# Super+W used to be "workspace up" too
gsettings set org.cinnamon.desktop.keybindings.wm switch-to-workspace-up "['<Control><Alt>Up', '<Alt>F1']"

# same 16px size for every tray icon
gsettings set org.cinnamon panel-zone-icon-sizes '[{"panelId":1,"left":0,"center":0,"right":16},{"panelId":2,"left":0,"center":0,"right":16}]'
gsettings set org.cinnamon panel-zone-symbolic-icon-sizes '[{"panelId":1,"left":15,"center":15,"right":16},{"panelId":2,"left":30,"center":17,"right":16}]'

# lock screen (its date-format comes from wallcolor, to follow the accent color)
s=org.cinnamon.desktop.screensaver
gsettings set $s use-custom-format true
gsettings set $s time-format '<span letter_spacing="24000" text_transform="uppercase">%A</span>'
gsettings set $s font-time 'JetBrainsMono NF Bold 64'
gsettings set $s font-date 'JetBrainsMono NF 20'
gsettings set $s font-message 'JetBrainsMono NF 13'
gsettings set $s default-message 'lil gab'
gsettings set $s floating-widgets false
gsettings set $s show-album-art true
gsettings set $s allow-media-control true

# Update Manager: keep Flatpaks and Cinnamon spices updated
gsettings set com.linuxmint.updates auto-update-flatpaks true
gsettings set com.linuxmint.updates auto-update-cinnamon-spices true

# file manager sidebar: both SSDs
bookmarks=$HOME/.config/gtk-3.0/bookmarks
mkdir -p "$(dirname "$bookmarks")"; touch "$bookmarks"
for b in 'file:/// SSD Sistema' 'file:///dados SSD Dados'; do
    grep -qxF "$b" "$bookmarks" || echo "$b" >> "$bookmarks"
done

echo "cinnamon settings applied"
