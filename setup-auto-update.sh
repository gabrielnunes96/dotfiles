#!/usr/bin/env bash
# Atualização automática diária:
#   1. snapshot do Timeshift antes de qualquer mudança
#   2. instala só pacotes "seguros"
#   3. pacotes sensíveis (kernel, firmware, GPU, boot, login) ficam retidos
#      e geram uma notificação no desktop para você instalar manualmente
#      (a lista fica em /var/lib/auto-update/pending; o auto-update-notify dos
#      dotfiles avisa de novo a cada login enquanto ela existir)
# Desliga a automação do Update Manager para não haver dois atualizadores.
# Rode como você (não com sudo): ./setup-auto-update.sh
set -euo pipefail
[ "$(id -u)" -ne 0 ] || { echo "rode sem sudo: ./setup-auto-update.sh" >&2; exit 1; }
sudo -v

sudo tee /usr/local/sbin/auto-update >/dev/null <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
# pacotes que nunca atualizam sozinhos
SENSITIVE='^(linux-|grub|shim|mesa-|libgl1-mesa|libglx-mesa|libegl-mesa|libgbm|libdrm|xserver-xorg|initramfs-tools|lightdm|slick-greeter|systemd|libsystemd|libudev|udev|nvidia)'
APT_OPTS=(-o DPkg::Lock::Timeout=600 -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)
export DEBIAN_FRONTEND=noninteractive
PENDING=/var/lib/auto-update/pending
mkdir -p "${PENDING%/*}"

log() { logger -t auto-update "$*"; echo "$*"; }
notify() { # only real users with a desktop open; the login screen has no notifier
    for uid in $(loginctl list-users --no-legend | awk '$1 >= 1000 {print $1}'); do
        [ -S "/run/user/$uid/bus" ] || continue
        sudo -u "$(id -nu "$uid")" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
            notify-send -u critical -i software-update-urgent "$1" "$2" || true
    done
}

apt-get "${APT_OPTS[@]}" update -qq || { log "apt update falhou"; exit 1; }

# one line per package, even when both amd64 and i386 are upgradable
mapfile -t all < <(apt list --upgradable 2>/dev/null | awk -F/ 'NR>1 {print $1}' | sort -u)
[ ${#all[@]} -gt 0 ] || { rm -f "$PENDING"; log "nada para atualizar"; exit 0; }

safe=(); sens=()
for p in "${all[@]}"; do
    if [[ $p =~ $SENSITIVE ]]; then sens+=("$p"); else safe+=("$p"); fi
done

if [ ${#safe[@]} -gt 0 ]; then
    if command -v timeshift >/dev/null; then
        if ! timeshift --create --scripted --tags D --comments "antes do auto-update"; then
            log "snapshot falhou; nada foi instalado"
            notify "Auto-update abortado" "O snapshot do Timeshift falhou. Nada foi instalado."
            exit 1
        fi
    fi

    # retém os sensíveis durante a atualização (inclusive como dependência);
    # holds que já existiam (ex.: linux-firmware-amd-graphics) não são tocados
    mapfile -t held < <(apt-mark showhold)
    temp=()
    for p in "${sens[@]}"; do
        printf '%s\n' "${held[@]}" | grep -qx "$p" || temp+=("$p")
    done
    [ ${#temp[@]} -eq 0 ] || apt-mark hold "${temp[@]}" >/dev/null
    trap '[ ${#temp[@]} -eq 0 ] || apt-mark unhold "${temp[@]}" >/dev/null' EXIT

    log "atualizando: ${safe[*]}"
    apt-get "${APT_OPTS[@]}" -y upgrade \
        || notify "Auto-update com erro" "Veja: journalctl -t auto-update"
fi

if [ ${#sens[@]} -gt 0 ]; then
    log "pendentes (manual): ${sens[*]}"
    printf '%s\n' "${sens[@]}" > "$PENDING"
    notify "Atualizações sensíveis pendentes" \
        "${#sens[@]} pacotes (kernel, driver de vídeo ou sistema) esperam você."$'\n'"Faça um snapshot e instale pelo Update Manager."
else
    rm -f "$PENDING"
fi
EOF
sudo chmod 755 /usr/local/sbin/auto-update

sudo tee /etc/systemd/system/auto-update.service >/dev/null <<'EOF'
[Unit]
Description=Atualizacao automatica (snapshot + pacotes seguros)
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/auto-update
Nice=10
IOSchedulingClass=idle
EOF

sudo tee /etc/systemd/system/auto-update.timer >/dev/null <<'EOF'
[Unit]
Description=Atualizacao automatica diaria

[Timer]
OnCalendar=*-*-* 12:00
OnBootSec=15min
RandomizedDelaySec=20min
Persistent=true

[Install]
WantedBy=timers.target
EOF

# só um atualizador automático
sudo systemctl disable --now mintupdate-automation-upgrade.timer 2>/dev/null || true

sudo systemctl daemon-reload
sudo systemctl enable --now auto-update.timer

echo
systemctl list-timers auto-update.timer --no-pager
echo
echo "pronto. teste agora: sudo systemctl start auto-update && journalctl -t auto-update -n 20"
