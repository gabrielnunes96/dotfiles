#!/usr/bin/env bash
# Pick and install programs on a fresh Linux Mint, then (optionally) run install.sh.
#
#   ./setup.sh            graphical checklist (zenity), or a terminal one (whiptail)
#   ./setup.sh --dry-run  same menu, but only prints what it would run
#
# Already installed programs show up as "instalado" and are skipped.
set -uo pipefail
cd "$(dirname "$0")"

DRY=0; [[ ${1:-} == --dry-run ]] && DRY=1

# id | group | name | description | checked by default | kind | target
#   kind: apt (packages), flatpak (app id), deb (url of a .deb), fn (function below)
CATALOG=(
"conky|Desktop|Conky|relógio, data e now playing na área de trabalho|1|apt|conky-all playerctl"
"cava|Desktop|Cava|barras de áudio do now playing|1|apt|cava"
"copyq|Desktop|CopyQ|histórico da área de transferência (Super+V)|1|apt|copyq"
"plank|Desktop|Plank|dock na parte de baixo|1|apt|plank"
"fastfetch|Desktop|Fastfetch|resumo do sistema ao abrir o terminal|1|fn|install_fastfetch"
"starship|Desktop|Starship|prompt do terminal|1|fn|install_starship"
"orchis|Desktop|Tema Orchis|tema em todas as cores (segue o wallpaper)|1|fn|install_orchis"
"font|Desktop|JetBrainsMono Nerd Font|fonte do terminal, conky e tela de bloqueio|1|fn|install_font"
"pillow|Desktop|Pillow + Zenity|tirar a cor do wallpaper; janelas dos scripts|1|apt|python3-pil zenity"
"rclone|Nuvem|rclone|Google Drive e OneDrive como pastas (versão oficial)|1|fn|install_rclone"
"steam|Jogos|Steam|loja e biblioteca de jogos|1|deb|https://cdn.akamai.steamstatic.com/client/installer/steam.deb"
"gamemode|Jogos|GameMode + MangoHud|modo jogo e contador de FPS (comando jogo)|1|apt|gamemode mangohud"
"lsfg|Jogos|lsfg-vk|geração de quadros do Lossless Scaling (jogo fg)|1|deb|https://github.com/PancakeTAS/lsfg-vk/releases/download/v1.0.0/lsfg-vk-1.0.0.x86_64.deb"
"heroic|Jogos|Heroic|Epic, GOG e Amazon Games|0|fn|install_heroic"
"protonup|Jogos|ProtonUp-Qt|instala GE-Proton e outras versões do Proton|0|flatpak|net.davidotek.pupgui2"
"lact|Jogos|LACT|clocks, ventoinhas e energia da placa de vídeo|0|flatpak|io.github.ilya_zlobintsev.LACT"
"wine|Jogos|Wine + Winetricks|rodar programas do Windows fora da Steam|0|apt|wine64 wine32:i386 winetricks"
"chrome|Apps|Google Chrome|navegador|1|deb|https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb"
"vscode|Apps|VS Code|editor de código|1|deb|https://update.code.visualstudio.com/latest/linux-deb-x64/stable"
"discord|Apps|Discord|chat de voz e texto|1|flatpak|com.discordapp.Discord"
"spotify|Apps|Spotify|música|0|flatpak|com.spotify.Client"
"whatsapp|Apps|Whatsie|WhatsApp no desktop|0|flatpak|com.ktechpit.whatsie"
"freerdp|Apps|FreeRDP|área de trabalho remota do Windows|0|flatpak|com.freerdp.FreeRDP"
"docker|Dev|Docker|containers, com compose e buildx|1|fn|install_docker"
"dotnet|Dev|.NET SDK 10|SDK do .NET|1|apt|dotnet-sdk-10.0"
"gh|Dev|GitHub CLI|gh no terminal|1|apt|gh git"
"cli|Dev|Ferramentas de terminal|bat, eza, fd, fzf, ripgrep, zoxide, htop, yt-dlp|1|apt|bat eza fd-find fzf ripgrep zoxide htop yt-dlp xclip jq"
"login|Sistema|Tela de login estilizada|roda login-screen.sh (mesmo fundo e tema do desktop)|1|fn|setup_login"
"keyboard|Sistema|Teclado US Internacional no login|deixa o layout com acentos também na tela de login|1|fn|setup_keyboard"
"pciids|Sistema|Nomes de hardware atualizados|update-pciids, para o nome da GPU aparecer certo|0|fn|setup_pciids"
)

field() { IFS='|' read -r -a f <<<"$1"; echo "${f[$2]}"; }

run() { # print in dry-run, execute otherwise
    if ((DRY)); then printf '  [simulação] %s\n' "$*"; else "$@"; fi
}

installed() { # $kind $target -> 0 if already there
    case $1 in
        apt) for p in $2; do dpkg -s "${p%%:*}" &>/dev/null || return 1; done ;;
        flatpak) flatpak info "$2" &>/dev/null ;;
        deb) case $2 in
                *steam*) dpkg -s steam-launcher &>/dev/null || dpkg -s steam-installer &>/dev/null ;;
                *lsfg*) dpkg -s lsfg-vk &>/dev/null ;;
                *chrome*) dpkg -s google-chrome-stable &>/dev/null ;;
                *code*) dpkg -s code &>/dev/null ;;
                *) return 1 ;;
             esac ;;
        fn) "check_${2#*_}" ;;
    esac
}

# --- custom installers and their checks --------------------------------------
check_fastfetch() { command -v fastfetch &>/dev/null; }
install_fastfetch() {
    run sudo add-apt-repository -y ppa:zhangsongcui3371/fastfetch
    run sudo apt-get update
    run sudo apt-get install -y fastfetch
}
check_starship() { command -v starship &>/dev/null; }
install_starship() { run sh -c 'curl -sS https://starship.rs/install.sh | sh -s -- -y'; }
check_orchis() { [[ -d /usr/share/themes/Orchis-Dark-Compact || -d ~/.themes/Orchis-Dark-Compact ]]; }
install_orchis() {
    run sudo apt-get install -y sassc gtk2-engines-murrine git
    run rm -rf /tmp/orchis
    run git clone --depth 1 https://github.com/vinceliuice/Orchis-theme.git /tmp/orchis
    run sudo /tmp/orchis/install.sh -t all -c dark -s compact
}
check_font() { compgen -G "$HOME/.local/share/fonts/JetBrainsMonoNerdFont-*" >/dev/null; }
install_font() {
    run mkdir -p ~/.local/share/fonts
    run sh -c 'curl -fsSL https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.tar.xz | tar -xJ -C ~/.local/share/fonts'
    run fc-cache -f
}
check_rclone() { command -v rclone &>/dev/null && [[ $(rclone version 2>/dev/null | head -1) != *v1.60* ]]; }
install_rclone() { run sh -c 'curl -fsSL https://rclone.org/install.sh | sudo bash'; }
check_heroic() { flatpak info com.heroicgameslauncher.hgl &>/dev/null; }
install_heroic() {
    run flatpak install --system -y flathub com.heroicgameslauncher.hgl
    # games live on the second SSD
    [[ -d /dados ]] && run flatpak override --user --filesystem=/dados com.heroicgameslauncher.hgl
}
check_docker() { dpkg -s docker.io &>/dev/null; }
install_docker() {
    run sudo apt-get install -y docker.io docker-compose-v2 docker-buildx
    run sudo usermod -aG docker "$USER"
}
check_login() { [[ -L /usr/share/themes/Orchis-Login ]]; }
setup_login() { run ./login-screen.sh; }
check_keyboard() { grep -q '^XKBVARIANT="intl"' /etc/default/keyboard; }
setup_keyboard() { run sudo sed -i 's/^XKBVARIANT=.*/XKBVARIANT="intl"/' /etc/default/keyboard; }
check_pciids() { return 1; }
setup_pciids() { run sudo update-pciids; }

# --- menu ---------------------------------------------------------------------
choose() {
    local rows=() id group name desc def kind target state
    for item in "${CATALOG[@]}"; do
        IFS='|' read -r id group name desc def kind target <<<"$item"
        if installed "$kind" "$target"; then state="instalado"; def=0; else state=""; fi
        if [[ -n ${DISPLAY:-} ]] && command -v zenity &>/dev/null; then
            rows+=("$([[ $def == 1 ]] && echo TRUE || echo FALSE)" "$id" "$group" "$name" "$desc" "$state")
        else
            rows+=("$id" "$group · $name ${state:+($state)}" "$([[ $def == 1 ]] && echo ON || echo OFF)")
        fi
    done
    if [[ -n ${DISPLAY:-} ]] && command -v zenity &>/dev/null; then
        zenity --list --checklist --title="Configurar este computador" \
            --text="Marque o que instalar. O que já está instalado vem desmarcado." \
            --width=980 --height=760 --ok-label="Instalar" --cancel-label="Cancelar" --separator=' ' --print-column=2 --hide-column=2 \
            --column="" --column=id --column="Grupo" --column="Programa" \
            --column="Para que serve" --column="" "${rows[@]}" 2>/dev/null
    else
        whiptail --title "Configurar este computador" --separate-output \
            --checklist "Espaço marca, Enter confirma" 30 90 22 "${rows[@]}" 3>&1 1>&2 2>&3 | tr '\n' ' '
    fi
}

picked=${SETUP_PICK:-$(choose)} || { echo "cancelado"; exit 0; }
[[ -z ${picked// } ]] && { echo "nada marcado"; exit 0; }

apt_pkgs=() flatpaks=() debs=() fns=()
for item in "${CATALOG[@]}"; do
    IFS='|' read -r id _ name _ _ kind target <<<"$item"
    [[ " $picked " == *" $id "* ]] || continue
    case $kind in
        apt) apt_pkgs+=($target) ;;
        flatpak) flatpaks+=("$target") ;;
        deb) debs+=("$name|$target") ;;
        fn) fns+=("$target") ;;
    esac
done

((DRY)) || sudo -v || exit 1
[[ " ${apt_pkgs[*]} " == *":i386 "* ]] && run sudo dpkg --add-architecture i386

if ((${#apt_pkgs[@]})); then
    echo "==> pacotes: ${apt_pkgs[*]}"
    run sudo apt-get update
    run sudo apt-get install -y "${apt_pkgs[@]}"
fi

tmp=$(mktemp -d)
for d in "${debs[@]}"; do
    name=${d%%|*} url=${d#*|}
    echo "==> $name"
    run curl -fL --retry 3 -o "$tmp/pkg.deb" "$url" && run sudo apt-get install -y "$tmp/pkg.deb"
done
rm -rf "${tmp:?}"

if ((${#flatpaks[@]})); then
    echo "==> flatpaks: ${flatpaks[*]}"
    run flatpak install --system -y flathub "${flatpaks[@]}"
fi

for fn in "${fns[@]}"; do echo "==> ${fn#*_}"; "$fn"; done

echo
if [[ -n ${DISPLAY:-} ]] && command -v zenity &>/dev/null; then
    zenity --question --title="Configurar este computador" --width=420 \
        --text="Programas instalados.\n\nAplicar agora as configurações dos dotfiles (install.sh)?" 2>/dev/null \
        && run ./install.sh
else
    read -rp "Aplicar agora as configurações dos dotfiles (install.sh)? [S/n] " a
    [[ ${a,,} != n* ]] && run ./install.sh
fi
