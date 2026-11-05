# dotfiles

Setup do Linux Mint 22 (Cinnamon, X11): seletor de wallpaper com cores automáticas,
widgets do Conky, tela de bloqueio, clipboard e atalhos.

## Instalar

```bash
./install.sh
```

O script:

1. Cria links simbólicos de tudo em `home/` para a sua home. Se já existir um arquivo diferente no lugar, ele vira `*.bak`.
2. Roda `cinnamon.sh`, que aplica os atalhos, o tamanho dos ícones da bandeja, a tela de bloqueio, as atualizações automáticas e os favoritos do Nemo.
3. Gera os arquivos que dependem de cor a partir do wallpaper atual.

Pode rodar de novo quantas vezes quiser.

## O que tem aqui

| Arquivo | O que faz |
|---|---|
| `.local/share/wallpicker/picker.py` | Seletor de wallpaper em arco (**Super+W**) |
| `.local/share/wallpicker/wallcolor.py` | Extrai a cor do wallpaper e aplica no sistema |
| `.config/wallcolor/templates/` | Modelos que recebem a cor de destaque (veja abaixo) |
| `.local/bin/wallrotate` | Troca o wallpaper sozinho: `wallrotate on 15m`, `off`, `now` |
| `.local/bin/dns` | Troca rápida de DNS: `dns ls`, `dns use google`, `dns bench` |
| `.config/conky/start.sh` | Inicia os relógios e o now playing nos dois monitores |
| `.config/conky/cava-bars.sh` + `.config/cava/conky` | Visualizador de áudio do now playing |
| `.config/fastfetch/logo.txt` | Logo do fastfetch |
| `.config/autostart/` | CopyQ e widgets do Conky no login |

### Cores automáticas

Estes arquivos são **gerados** a partir de `.config/wallcolor/templates/` toda vez que o
wallpaper muda, por isso não ficam no repositório:

- `~/.config/starship.toml`
- `~/.config/fastfetch/config.jsonc`
- `~/.config/conky/{clock-2k,clock-fhd,nowplaying,nowplaying-fhd}.conf`
- formato da data da tela de bloqueio (gsettings)

**Para mudar algo neles, edite o modelo**, não o arquivo gerado. Os marcadores são
`{{accent}}`, `{{accent_dark}}` (hex sem `#`) e `{{accent_rgb}}`, `{{accent_dark_rgb}}`
(`r;g;b`). Para aplicar sem trocar o wallpaper:

```bash
wallcolor caminho/da/imagem.jpg
```

O seletor lê imagens de `~/Pictures/Wallpapers` e `~/Pictures/4KWALL`.

## Pré-requisitos (manual, precisa de sudo)

```bash
sudo apt install conky-all playerctl cava copyq fastfetch
```

```bash
curl -sS https://starship.rs/install.sh | sh
```

Tema Orchis em todas as cores (o tema do sistema troca de cor junto com o wallpaper):

```bash
git clone --depth 1 https://github.com/vinceliuice/Orchis-theme.git /tmp/orchis && /tmp/orchis/install.sh -t all -c dark -s compact
```

Fonte: JetBrainsMono Nerd Font em `~/.local/share/fonts`.

No `~/.bashrc`, no final:

```bash
fastfetch
eval "$(starship init bash)"
```

### Tela de login

`./login-screen.sh` (uma vez, pede a senha) deixa a tela de login com o mesmo
fundo, tema, ícones, cursor e fonte do desktop. Ele torna `/usr/share/backgrounds/login`
seu, e daí em diante o `wallcolor` atualiza o fundo e a cor do login a cada troca
de wallpaper, sem sudo. Original em `/etc/lightdm/slick-greeter.conf.orig`.

## Ajustes únicos desta máquina

Ficam fora do script porque mexem no sistema ou dependem do hardware:

- **Nome da GPU:** `sudo update-pciids`. Mesmo assim, o fastfetch mostra o nome fixo "AMD Radeon RX 9060 XT" pelo modelo.
- **Rótulos dos discos:** `sudo e2label /dev/sda1 Dados` e `sudo e2label /dev/nvme0n1p2 Sistema`
- **Heroic (Flatpak) enxergar o `/dados`:** `flatpak override --user --filesystem=/dados com.heroicgameslauncher.hgl`
- **Teclado US Internacional também no login:** `sudo sed -i 's/^XKBVARIANT=""/XKBVARIANT="intl"/' /etc/default/keyboard`
- **Atualização automática do APT:** Update Manager → Preferências → Automação
