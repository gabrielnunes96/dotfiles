#!/usr/bin/env bash
# One-time setup so the login screen (LightDM slick-greeter) looks like the
# desktop and follows the wallpaper picker without sudo afterwards:
#   /usr/share/backgrounds/login/            owned by you; wallcolor writes into it
#     background.jpg                         login background
#     theme -> /usr/share/themes/Orchis-...  current accent variant
#   /usr/share/themes/Orchis-Login -> /usr/share/backgrounds/login/theme
# Run as yourself (not with sudo); it asks for the password once.
set -euo pipefail
[ "$(id -u)" -ne 0 ] || { echo "rode sem sudo: ./login-screen.sh" >&2; exit 1; }

get() { gsettings get "$1" "$2" | tr -d "'"; }
icons=$(get org.cinnamon.desktop.interface icon-theme)
cursor=$(get org.cinnamon.desktop.interface cursor-theme)
login=/usr/share/backgrounds/login

# the greeter runs as the lightdm user and can't read $HOME (750), so copy what it needs
find_dir() { for d in "$HOME/.themes" "$HOME/.icons" "$HOME/.local/share/icons" "$HOME/.local/share/themes"; do
                 [ -d "$d/$1" ] && { echo "$d/$1"; return; }; done; return 0; }

sudo -v
sudo install -d -o "$USER" -g "$USER" -m 755 "$login"
sudo chown -R "$USER:$USER" "$login"
sudo ln -sfn "$login/theme" /usr/share/themes/Orchis-Login

# every Orchis dark compact variant, so the accent can switch without sudo
for t in "$HOME"/.themes/Orchis*-Dark-Compact; do
    sudo rm -rf "/usr/share/themes/$(basename "$t")"
    sudo cp -r "$t" /usr/share/themes/
done
for name in "$icons" "$cursor"; do
    src=$(find_dir "$name")
    if [ -n "$src" ] && [ ! -d "/usr/share/icons/$name" ]; then
        sudo cp -r "$src" /usr/share/icons/
    fi
done

sudo install -d /usr/local/share/fonts/jetbrains-mono-nf
sudo install -m 644 "$HOME"/.local/share/fonts/JetBrainsMonoNerdFont-*.ttf /usr/local/share/fonts/jetbrains-mono-nf/
sudo fc-cache -f /usr/local/share/fonts >/dev/null

conf=/etc/lightdm/slick-greeter.conf
[ -f "$conf.orig" ] || sudo cp "$conf" "$conf.orig"
sudo tee "$conf" >/dev/null <<EOF
[Greeter]
background=$login/background.jpg
background-color=#000000
draw-user-backgrounds=false
draw-grid=false
theme-name=Orchis-Login
icon-theme-name=$icons
cursor-theme-name=$cursor
font-name=JetBrainsMono NF 11
clock-format=%A  %d %B  ·  %H:%M
show-hostname=false
show-keyboard=false
show-power=false
EOF

# background + theme link for the current wallpaper (from now on wallcolor does this)
wallpaper=$(get org.cinnamon.desktop.background picture-uri | sed 's|^file://||')
"$HOME/.local/bin/wallcolor" "$wallpaper"
echo "tela de login configurada; original em $conf.orig"
