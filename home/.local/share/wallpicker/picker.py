#!/usr/bin/env python3
"""Fullscreen wallpaper picker: images as vertical strips laid out in an arc.

Mouse: hover to focus, click to apply, wheel to scroll. Keys: arrows/Enter/Esc.
"""
import hashlib
import math
import subprocess
import sys
import threading
from pathlib import Path

import cairo
import fcntl
import gi

gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
from gi.repository import Gdk, GdkPixbuf, GLib, Gtk  # noqa: E402
from PIL import Image, ImageOps  # noqa: E402

HOME = Path.home()
FOLDERS = [HOME / "Pictures/Wallpapers", HOME / "Pictures/4KWALL"]
CACHE = HOME / ".cache/wallpicker"
EXTS = {".jpg", ".jpeg", ".png", ".webp"}
THUMB = (400, 1000)  # portrait strip
VISIBLE = 10  # strips on each side of the center
WALLCOLOR = Path(__file__).with_name("wallcolor.py")


def find_images():
    seen, out = set(), []
    for folder in FOLDERS:
        if not folder.is_dir():
            continue
        for p in sorted(folder.rglob("*")):
            if p.suffix.lower() in EXTS and p.resolve() not in seen:
                seen.add(p.resolve())
                out.append(p)
    return out


def thumb_for(path):
    st = path.stat()
    key = hashlib.sha1(f"{path}:{st.st_mtime_ns}:{st.st_size}".encode()).hexdigest()
    out = CACHE / f"{key}.jpg"
    if not out.exists():
        CACHE.mkdir(parents=True, exist_ok=True)
        with Image.open(path) as im:
            tmp = out.with_suffix(".part")
            ImageOps.fit(im.convert("RGB"), THUMB, Image.LANCZOS).save(tmp, "JPEG", quality=88)
            tmp.replace(out)
    return out


def current_wallpaper():
    uri = subprocess.run(
        ["gsettings", "get", "org.cinnamon.desktop.background", "picture-uri"],
        capture_output=True, text=True,
    ).stdout.strip().strip("'")
    return uri.removeprefix("file://")


class Picker(Gtk.Window):
    def __init__(self, images):
        super().__init__(title="Wallpaper picker")
        self.images = images
        self.surfaces = [None] * len(images)  # thumbnails pre-scaled to on-screen size
        self.rects = []  # (index, x, y, w, h) from the last draw, for hit testing
        self.hover = None
        self.grow = [0.0] * len(images)  # animated hover growth per strip
        self.last_frame = 0

        cur = current_wallpaper()
        start = next((i for i, p in enumerate(images) if str(p) == cur), len(images) // 2)
        self.center = self.target = float(start)

        self.set_decorated(False)
        self.set_keep_above(True)
        self.set_skip_taskbar_hint(True)
        self.set_app_paintable(True)
        visual = self.get_screen().get_rgba_visual()
        if visual:
            self.set_visual(visual)

        self.add_events(Gdk.EventMask.POINTER_MOTION_MASK | Gdk.EventMask.BUTTON_PRESS_MASK
                        | Gdk.EventMask.SCROLL_MASK | Gdk.EventMask.SMOOTH_SCROLL_MASK)
        self.connect("draw", self.on_draw)
        self.connect("motion-notify-event", self.on_motion)
        self.connect("button-press-event", self.on_click)
        self.connect("scroll-event", self.on_scroll)
        self.connect("key-press-event", self.on_key)
        self.connect("destroy", Gtk.main_quit)

        self.place_on_pointer_monitor()
        threading.Thread(target=self.load_thumbs, daemon=True).start()
        self.add_tick_callback(self.tick)

    def place_on_pointer_monitor(self):
        display = Gdk.Display.get_default()
        _, x, y = display.get_default_seat().get_pointer().get_position()[0:3]
        mon = display.get_monitor_at_point(x, y)
        g = mon.get_geometry()
        # blurred snapshot of this monitor as the backdrop (cheap blur: shrink, then stretch back)
        shot = Gdk.pixbuf_get_from_window(Gdk.get_default_root_window(), g.x, g.y, g.width, g.height)
        self.geo = g
        self.backdrop = None
        if shot:
            blur = shot.scale_simple(g.width // 24, g.height // 24, GdkPixbuf.InterpType.BILINEAR) \
                .scale_simple(g.width, g.height, GdkPixbuf.InterpType.BILINEAR)
            # bake the blur and dimming into one surface once, instead of every frame
            self.backdrop = cairo.ImageSurface(cairo.FORMAT_RGB24, g.width, g.height)
            bc = cairo.Context(self.backdrop)
            Gdk.cairo_set_source_pixbuf(bc, blur, 0, 0)
            bc.paint()
            bc.set_source_rgba(0.02, 0.02, 0.03, 0.55)
            bc.paint()
        self.move(g.x, g.y)
        self.set_default_size(g.width, g.height)
        for i in range(display.get_n_monitors()):
            if display.get_monitor(i) == mon:
                self.fullscreen_on_monitor(self.get_screen(), i)

    def load_thumbs(self):
        # nearest to the starting point first, so the visible strips appear quickly
        order = sorted(range(len(self.images)), key=lambda i: abs(i - self.target))
        for i in order:
            try:
                # largest size a strip is ever drawn at, so drawing only ever scales down
                h = int(self.geo.height * 0.46 * 1.12)
                pb = GdkPixbuf.Pixbuf.new_from_file_at_scale(
                    str(thumb_for(self.images[i])), int(h * THUMB[0] / THUMB[1]), h, True)
            except Exception as e:  # unreadable image: skip it
                print(f"skip {self.images[i]}: {e}", file=sys.stderr)
                continue
            GLib.idle_add(self.set_thumb, i, pb)

    def set_thumb(self, i, pb):
        self.surfaces[i] = (Gdk.cairo_surface_create_from_pixbuf(pb, 1, None), pb.get_width(), pb.get_height())
        self.queue_draw()

    def tick(self, _w=None, clock=None):
        # easing tuned for 60 fps, scaled by the real frame time so 144 Hz isn't faster
        now = clock.get_frame_time() if clock else 0
        frames = min(4.0, (now - self.last_frame) / 16667) if clock and self.last_frame else 1.0
        self.last_frame = now
        ease_center = 1 - (1 - 0.18) ** frames
        ease_grow = 1 - (1 - 0.25) ** frames
        moved = abs(self.target - self.center) > 0.001
        self.center += (self.target - self.center) * ease_center
        for i in range(len(self.grow)):
            goal = 1.0 if i == self.hover else 0.0
            if abs(goal - self.grow[i]) > 0.001:
                self.grow[i] += (goal - self.grow[i]) * ease_grow
                moved = True
        if moved:
            self.queue_draw()
        return True

    def layout(self, width, height):
        """Strip geometry around the center index: tall in the middle, shorter outward."""
        base_w, base_h = width * 0.072, height * 0.46
        gap = width * 0.006
        mid_y = height * 0.45
        lo = max(0, math.floor(self.center) - VISIBLE)
        hi = min(len(self.images) - 1, math.ceil(self.center) + VISIBLE)

        sizes = {}
        for i in range(lo, hi + 1):
            d = abs(i - self.center)
            s = max(0.4, 1 - 0.06 * d) * (1 + 0.12 * self.grow[i])
            sizes[i] = (base_w * (0.75 + 0.25 * s) * (1 + 0.25 * self.grow[i]), base_h * s)

        # walk outward from the (fractional) center so the arc stays centered
        c = min(max(round(self.center), lo), hi)
        frac = self.center - c
        x_of = {c: width / 2 - sizes[c][0] / 2 - frac * (sizes[c][0] + gap)}
        for i in range(c + 1, hi + 1):
            x_of[i] = x_of[i - 1] + sizes[i - 1][0] + gap
        for i in range(c - 1, lo - 1, -1):
            x_of[i] = x_of[i + 1] - sizes[i][0] - gap
        return [(i, x_of[i], mid_y - sizes[i][1] / 2, *sizes[i]) for i in range(lo, hi + 1)]

    def on_draw(self, _w, cr):
        width, height = self.get_allocated_width(), self.get_allocated_height()
        cr.set_operator(cairo.OPERATOR_SOURCE)
        if self.backdrop:
            cr.set_source_surface(self.backdrop, 0, 0)
        else:
            cr.set_source_rgba(0.02, 0.02, 0.03, 0.72)
        cr.paint()
        cr.set_operator(cairo.OPERATOR_OVER)

        self.rects = self.layout(width, height)
        # draw the outer strips first so nearer ones overlap them
        for i, x, y, w, h in sorted(self.rects, key=lambda r: -abs(r[0] - self.center)):
            # whole pixels: fractional rects make cairo build an antialiased mask every frame
            x, y, w, h = round(x), round(y), round(w), round(h)
            dim = min(0.6, abs(i - self.center) * 0.06) * (1 - self.grow[i])
            thumb = self.surfaces[i]
            if thumb:
                surf, tw, th = thumb
                scale = max(w / tw, h / th)
                pat = cairo.SurfacePattern(surf)
                pat.set_filter(cairo.FILTER_BILINEAR)
                m = cairo.Matrix(xx=scale, yy=scale, x0=x + (w - tw * scale) / 2, y0=y + (h - th * scale) / 2)
                m.invert()
                pat.set_matrix(m)
                cr.set_source(pat)
            else:
                cr.set_source_rgb(0.12, 0.12, 0.14)
            cr.rectangle(x, y, w, h)
            cr.fill()
            if dim > 0.01:
                cr.set_source_rgba(0, 0, 0, dim)
                cr.rectangle(x, y, w, h)
                cr.fill()
            if self.grow[i] > 0.02:
                cr.set_source_rgba(1, 1, 1, 0.85 * self.grow[i])
                cr.set_line_width(2)
                cr.rectangle(x + 1, y + 1, w - 2, h - 2)
                cr.stroke()

        focus = self.hover if self.hover is not None else round(self.center)
        if 0 <= focus < len(self.images):
            label = f"{self.images[focus].stem}    {focus + 1}/{len(self.images)}"
            cr.select_font_face("JetBrainsMono NF")
            cr.set_font_size(15)
            ext = cr.text_extents(label)
            cr.set_source_rgba(1, 1, 1, 0.75)
            cr.move_to((width - ext.width) / 2, height * 0.82)
            cr.show_text(label)

    def strip_at(self, x, y):
        for i, rx, ry, w, h in sorted(self.rects, key=lambda r: abs(r[0] - self.center)):
            if rx <= x <= rx + w and ry <= y <= ry + h:
                return i
        return None

    def on_motion(self, _w, ev):
        self.hover = self.strip_at(ev.x, ev.y)

    def on_click(self, _w, ev):
        i = self.strip_at(ev.x, ev.y)
        if ev.button == 1 and i is not None:
            self.apply(i)
        elif ev.button in (1, 3):
            self.destroy()

    def on_scroll(self, _w, ev):
        delta = {Gdk.ScrollDirection.UP: -1, Gdk.ScrollDirection.DOWN: 1,
                 Gdk.ScrollDirection.LEFT: -1, Gdk.ScrollDirection.RIGHT: 1}.get(ev.direction)
        if delta is None:
            ok, _dx, dy = ev.get_scroll_deltas()
            delta = (1 if dy > 0 else -1) if ok and dy else 0
        self.move_target(delta)

    def on_key(self, _w, ev):
        key = Gdk.keyval_name(ev.keyval)
        if key == "Escape":
            self.destroy()
        elif key in ("Left", "h"):
            self.move_target(-1)
        elif key in ("Right", "l"):
            self.move_target(1)
        elif key in ("Return", "KP_Enter", "space"):
            self.apply(round(self.target))

    def move_target(self, delta):
        self.hover = None
        self.target = min(max(self.target + delta, 0), len(self.images) - 1)

    def apply(self, i):
        path = self.images[i]
        subprocess.run(["gsettings", "set", "org.cinnamon.desktop.background",
                        "picture-uri", path.as_uri()])
        subprocess.run(["gsettings", "set", "org.cinnamon.desktop.background",
                        "picture-options", "zoom"])
        subprocess.Popen([sys.executable, str(WALLCOLOR), str(path)], start_new_session=True)
        self.destroy()


def main():
    # one picker at a time: a second Super+W while open does nothing
    CACHE.mkdir(parents=True, exist_ok=True)
    lock = open(CACHE / "picker.lock", "w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        return
    images = find_images()
    if not images:
        subprocess.run(["notify-send", "Wallpaper picker",
                        f"Nenhuma imagem em {', '.join(str(f) for f in FOLDERS)}"])
        return
    Picker(images).show_all()
    Gtk.main()


if __name__ == "__main__":
    main()
