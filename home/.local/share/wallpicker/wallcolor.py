#!/usr/bin/env python3
"""Pick an accent color from a wallpaper and apply it to the desktop.

Usage: wallcolor.py <image>

Renders ~/.config/wallcolor/templates/* with the accent and switches the
Orchis GTK/Cinnamon theme to the closest installed color variant.
"""
import colorsys
import json
import subprocess
import sys
from pathlib import Path

from PIL import Image

HOME = Path.home()
TEMPLATES = HOME / ".config/wallcolor/templates"
STATE = HOME / ".cache/wallcolor/current.json"
THEMES_DIRS = [HOME / ".themes", Path("/usr/share/themes")]

# template name -> where it gets rendered
TARGETS = {
    "starship.toml": HOME / ".config/starship.toml",
    "fastfetch.jsonc": HOME / ".config/fastfetch/config.jsonc",
    "conky-clock-2k.conf": HOME / ".config/conky/clock-2k.conf",
    "conky-clock-fhd.conf": HOME / ".config/conky/clock-fhd.conf",
    "conky-nowplaying.conf": HOME / ".config/conky/nowplaying.conf",
    "conky-nowplaying-fhd.conf": HOME / ".config/conky/nowplaying-fhd.conf",
}

# template name -> gsettings key it gets written to
GSETTINGS = {
    "lockscreen-date-format.txt": ("org.cinnamon.desktop.screensaver", "date-format"),
}

# hue ranges (degrees) -> Orchis variant; "" is Orchis' default blue
VARIANTS = [
    (15, "Red"), (40, "Orange"), (58, "Yellow"), (160, "Green"),
    (195, "Teal"), (255, ""), (290, "Purple"), (345, "Pink"), (361, "Red"),
]


def dominant_accent(path):
    """Most prominent saturated hue in the image, or None if it's mostly grey."""
    im = Image.open(path).convert("RGB")
    im.thumbnail((240, 240))
    bins = {}
    for r, g, b in im.getdata():
        h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
        if s < 0.3 or v < 0.2:
            continue
        w = s * v
        acc = bins.setdefault(int(h * 36) % 36, [0.0, 0.0, 0.0, 0.0])
        acc[0] += w
        acc[1] += r * w
        acc[2] += g * w
        acc[3] += b * w
    total = sum(a[0] for a in bins.values())
    if not bins or total < 0.04 * im.width * im.height:
        return None
    w, r, g, b = max(bins.values(), key=lambda a: a[0])
    return r / w / 255, g / w / 255, b / w / 255


def tune(rgb):
    """Normalize to something readable on a dark desktop: (accent, dark accent)."""
    if rgb is None:
        return (0.79, 0.79, 0.79), (0.42, 0.42, 0.44)
    h, s, _ = colorsys.rgb_to_hsv(*rgb)
    s = min(max(s, 0.55), 0.85)
    return colorsys.hsv_to_rgb(h, s, 0.88), colorsys.hsv_to_rgb(h, s, 0.70)


def variant_for(rgb):
    if rgb is None:
        return "Grey"
    hue = colorsys.rgb_to_hsv(*rgb)[0] * 360
    return next(name for limit, name in VARIANTS if hue < limit)


def hexc(c):
    return "".join(f"{round(x * 255):02x}" for x in c)


def rgbc(c):
    return ";".join(str(round(x * 255)) for x in c)


def theme_exists(name):
    return any((d / name).is_dir() for d in THEMES_DIRS)


def apply_theme(variant):
    name = f"Orchis-{variant}-Dark-Compact" if variant else "Orchis-Dark-Compact"
    if not theme_exists(name):
        return None
    subprocess.run(["gsettings", "set", "org.cinnamon.desktop.interface", "gtk-theme", name])
    subprocess.run(["gsettings", "set", "org.cinnamon.theme", "name", name])
    return name


def main():
    image = Path(sys.argv[1]).expanduser()
    raw = dominant_accent(image)
    accent, dark = tune(raw)
    values = {
        "{{accent}}": hexc(accent), "{{accent_dark}}": hexc(dark),
        "{{accent_rgb}}": rgbc(accent), "{{accent_dark_rgb}}": rgbc(dark),
    }
    for tpl, target in TARGETS.items():
        src = TEMPLATES / tpl
        if not src.exists():
            continue
        text = src.read_text()
        for k, v in values.items():
            text = text.replace(k, v)
        target.write_text(text)
    for tpl, (schema, key) in GSETTINGS.items():
        src = TEMPLATES / tpl
        if src.exists():
            text = src.read_text()
            for k, v in values.items():
                text = text.replace(k, v)
            subprocess.run(["gsettings", "set", schema, key, text])

    theme = apply_theme(variant_for(raw))
    conky = HOME / ".config/conky/start.sh"
    if conky.exists():
        subprocess.Popen([str(conky)], start_new_session=True,
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    STATE.parent.mkdir(parents=True, exist_ok=True)
    STATE.write_text(json.dumps({"image": str(image), "accent": values["{{accent}}"], "theme": theme}))
    print(f"accent #{values['{{accent}}']}  theme {theme or 'unchanged (variant not installed)'}")


if __name__ == "__main__":
    main()
