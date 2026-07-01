#!/usr/bin/env python3
"""Offline renderer for "Les Strates" pixel-art assets.

Faithful port of the GDScript drawing primitives in _assets_gen.gd, extended
with a Moonring-inspired pass: restricted neon palettes, Bayer dithering,
soft neon glow (bloom), and consistent top-left rim light. Produces the
32x32 PNGs the game loads at runtime, plus scaled preview montages.
"""
import math, os, sys
from PIL import Image

TILE = 32

# --- Godot-Color semantics ----------------------------------------------------
class C:
    __slots__ = ("r", "g", "b", "a")
    def __init__(self, r, g, b, a=1.0):
        self.r, self.g, self.b, self.a = r, g, b, a
    def darkened(self, amt):
        return C(self.r*(1-amt), self.g*(1-amt), self.b*(1-amt), self.a)
    def lightened(self, amt):
        return C(self.r+(1-self.r)*amt, self.g+(1-self.g)*amt, self.b+(1-self.b)*amt, self.a)
    def lerp(self, to, t):
        return C(self.r+(to.r-self.r)*t, self.g+(to.g-self.g)*t,
                 self.b+(to.b-self.b)*t, self.a+(to.a-self.a)*t)
    def with_a(self, a):
        return C(self.r, self.g, self.b, a)

# --- Palette d'identité (mirror _assets_gen.gd) -------------------------------
INK      = C(0.055, 0.050, 0.090)   # contour quasi-noir (plus sombre = Moonring)
INK_SOFT = C(0.105, 0.098, 0.160)
STONE    = C(0.227, 0.212, 0.306)
STONE_D  = C(0.149, 0.137, 0.212)
STONE_L  = C(0.34, 0.32, 0.46)
FLOOR_A  = C(0.090, 0.084, 0.135)
FLOOR_B  = C(0.140, 0.130, 0.200)
STEEL    = C(0.588, 0.627, 0.725)
STEEL_D  = C(0.361, 0.392, 0.490)
STEEL_L  = C(0.82, 0.86, 0.95)
BONE     = C(0.880, 0.866, 0.780)
BONE_D   = C(0.60, 0.58, 0.49)
GOLD     = C(0.953, 0.749, 0.286)
GOLD_D   = C(0.588, 0.431, 0.137)
GOLD_L   = C(1.0, 0.92, 0.55)
BLOOD    = C(0.812, 0.231, 0.251)
BLOOD_D  = C(0.49, 0.13, 0.16)
ARCANE   = C(0.643, 0.404, 0.918)
ARCANE_L = C(0.835, 0.643, 1.0)
CYAN     = C(0.392, 0.882, 0.925)
CYAN_L   = C(0.69, 0.99, 1.0)
POISON   = C(0.510, 0.851, 0.376)
EMBER    = C(1.0, 0.580, 0.220)
EMBER_L  = C(1.0, 0.80, 0.42)

ROSE   = C(0.95, 0.57, 0.87)
ROSE_D = C(0.62, 0.30, 0.56)
ROSE_L = C(1.0, 0.78, 0.97)
SKIN   = C(0.95, 0.83, 0.73)
SKIN_D = C(0.78, 0.62, 0.54)

# Bayer 4x4 (valeurs 0..15) pour le dithering rétro façon CGA.
BAYER4 = [
    [0, 8, 2, 10],
    [12, 4, 14, 6],
    [3, 11, 1, 9],
    [15, 7, 13, 5],
]

# --- BIOMES (mirror Data.gd) — palettes néon med-fantasy ----------------------
BIOMES = [
    {"id": "plaine",
     "ground_a": C(0.090, 0.135, 0.100), "ground_b": C(0.130, 0.190, 0.135),
     "trunk": C(0.30, 0.21, 0.13), "leaf": C(0.36, 0.72, 0.40), "tree_style": "round",
     "rock": C(0.36, 0.40, 0.50), "water": C(0.18, 0.55, 0.66),
     "decor": C(1.0, 0.83, 0.34), "decor_styles": ["flower", "tall_grass", "dandelion"],
     "poi": {"structure": "standing_stone", "dressing": [0, 1]}},
    {"id": "foret",
     "ground_a": C(0.060, 0.120, 0.100), "ground_b": C(0.095, 0.175, 0.135),
     "trunk": C(0.26, 0.17, 0.11), "leaf": C(0.24, 0.66, 0.42), "tree_style": "pine",
     "rock": C(0.28, 0.37, 0.39), "water": C(0.13, 0.46, 0.52),
     "decor": C(0.94, 0.27, 0.36), "decor_styles": ["mushroom", "fern", "spider_web"],
     "poi": {"structure": "forest_altar", "dressing": [0, 1]}},
    {"id": "desert",
     "ground_a": C(0.205, 0.150, 0.085), "ground_b": C(0.290, 0.215, 0.120),
     "trunk": C(0.32, 0.42, 0.24), "leaf": C(0.42, 0.70, 0.34), "tree_style": "cactus",
     "rock": C(0.50, 0.40, 0.26), "water": C(0.20, 0.64, 0.66),
     "decor": C(0.92, 0.88, 0.74), "decor_styles": ["bones", "tumbleweed", "cracked_earth"],
     "poi": {"structure": "wagon_wheel", "dressing": [0, 1]}},
    {"id": "toundra",
     "ground_a": C(0.105, 0.140, 0.215), "ground_b": C(0.150, 0.205, 0.300),
     "trunk": C(0.30, 0.26, 0.24), "leaf": C(0.54, 0.78, 0.82), "tree_style": "pine",
     "rock": C(0.42, 0.50, 0.60), "water": C(0.36, 0.74, 0.90),
     "decor": C(0.62, 0.90, 1.0), "decor_styles": ["crystal", "icicle", "snow_drift"],
     "poi": {"structure": "ice_cairn", "dressing": [0, 1]}},
    {"id": "marais",
     "ground_a": C(0.100, 0.130, 0.090), "ground_b": C(0.140, 0.180, 0.110),
     "trunk": C(0.20, 0.18, 0.13), "leaf": C(0.36, 0.50, 0.24), "tree_style": "dead",
     "rock": C(0.28, 0.33, 0.29), "water": C(0.22, 0.42, 0.27),
     "decor": C(0.64, 0.86, 0.32), "decor_styles": ["reed", "lily_pad", "wisp"],
     "poi": {"structure": "sunken_ruin", "dressing": [0, 1]}},
    {"id": "volcan",
     "ground_a": C(0.105, 0.072, 0.090), "ground_b": C(0.165, 0.100, 0.110),
     "trunk": C(0.16, 0.12, 0.12), "leaf": C(0.24, 0.17, 0.17), "tree_style": "dead",
     "rock": C(0.28, 0.21, 0.23), "water": C(1.0, 0.46, 0.16),
     "decor": C(1.0, 0.58, 0.20), "decor_styles": ["ember", "obsidian_shard", "ash_pile"],
     "poi": {"structure": "abandoned_anvil", "dressing": [0, 1]}},
]

# --- RNG déterministe (LCG) pour un grain reproductible -----------------------
class RNG:
    def __init__(self, seed=1337):
        self.s = seed & 0xFFFFFFFF
    def randf(self):
        self.s = (1103515245 * self.s + 12345) & 0x7FFFFFFF
        return self.s / float(0x7FFFFFFF)
    def randi_range(self, a, b):
        return a + int(self.randf() * (b - a + 1))

rng = RNG(1337)

# --- Image / primitives -------------------------------------------------------
class Img:
    def __init__(self, opaque=False):
        self.px = [[ [0.0,0.0,0.0,1.0] if opaque else [0.0,0.0,0.0,0.0]
                     for _ in range(TILE)] for _ in range(TILE)]
    def fill(self, c):
        for y in range(TILE):
            for x in range(TILE):
                self.px[y][x] = [c.r, c.g, c.b, c.a]
    def get(self, x, y):
        p = self.px[y][x]
        return C(p[0], p[1], p[2], p[3])
    def set(self, x, y, c):
        self.px[y][x] = [c.r, c.g, c.b, c.a]

def _px(img, x, y, c):
    x = int(x); y = int(y)
    if 0 <= x < TILE and 0 <= y < TILE:
        if c.a >= 1.0:
            img.set(x, y, c)
        elif c.a > 0.0:
            img.set(x, y, img.get(x, y).lerp(c, c.a))

def _rect(img, x, y, w, h, c):
    for yy in range(int(y), int(y+h)):
        for xx in range(int(x), int(x+w)):
            _px(img, xx, yy, c)

def _ellipse(img, cx, cy, rx, ry, c):
    for yy in range(int(cy-ry), int(cy+ry)+1):
        for xx in range(int(cx-rx), int(cx+rx)+1):
            dx = (xx-cx)/rx; dy = (yy-cy)/ry
            if dx*dx+dy*dy <= 1.0:
                _px(img, xx, yy, c)

def _disc(img, cx, cy, r, c):
    _ellipse(img, cx, cy, r, r, c)

def _disc_o(img, cx, cy, r, c, oc=None):
    if oc is None: oc = INK
    _disc(img, cx, cy, r+1.0, oc)
    _disc(img, cx, cy, r, c)

def _trapezoid(img, cx, top_y, bot_y, top_hw, bot_hw, c):
    span = max(1, bot_y-top_y)
    for i in range(span+1):
        t = i/float(span)
        hw = int(round(top_hw+(bot_hw-top_hw)*t))
        y = top_y+i
        for x in range(cx-hw, cx+hw+1):
            _px(img, x, y, c)

def _trapezoid_o(img, cx, top_y, bot_y, top_hw, bot_hw, c, oc=None):
    if oc is None: oc = INK
    _trapezoid(img, cx, top_y-1, bot_y+1, top_hw+1.0, bot_hw+1.0, oc)
    _trapezoid(img, cx, top_y, bot_y, top_hw, bot_hw, c)

def _line(img, x0, y0, x1, y1, c):
    dx = abs(x1-x0); dy = -abs(y1-y0)
    sx = 1 if x0 < x1 else -1
    sy = 1 if y0 < y1 else -1
    err = dx+dy; x = x0; y = y0
    while True:
        _px(img, x, y, c)
        if x == x1 and y == y1: break
        e2 = 2*err
        if e2 >= dy: err += dy; x += sx
        if e2 <= dx: err += dx; y += sy

def _tri_up(img, cx, base_y, half_w, height, c):
    for i in range(height):
        w = int(round(half_w*(1.0-i/float(height))))
        yy = base_y-i
        for xx in range(cx-w, cx+w+1):
            _px(img, xx, yy, c)

def _diamond(img, cx, cy, r, c):
    for dy in range(-r, r+1):
        w = r-abs(dy)
        for dx in range(-w, w+1):
            _px(img, cx+dx, cy+dy, c)

def _ground_shadow(img):
    _ellipse(img, 16, 28, 8.7, 2.4, C(INK.r, INK.g, INK.b, 0.34))

def _tri_band(img, cx, base_y, half_w, height, c_light, c_mid, c_dark):
    """Triangle filled with a left(lit)->right(shadow) 3-band gradient."""
    for i in range(height):
        w = int(round(half_w * (1.0 - i / float(height))))
        yy = base_y - i
        span = max(1, 2 * w)
        for xx in range(cx - w, cx + w + 1):
            t = (xx - (cx - w)) / float(span)
            c = c_light if t < 0.35 else (c_mid if t < 0.7 else c_dark)
            _px(img, xx, yy, c)

def _disc_band(img, cx, cy, r, c_light, c_mid, c_dark):
    """Disc filled with a left(lit)->right(shadow) 3-band gradient."""
    for yy in range(int(cy - r), int(cy + r) + 1):
        for xx in range(int(cx - r), int(cx + r) + 1):
            dx = (xx - cx) / r; dy = (yy - cy) / r
            if dx * dx + dy * dy <= 1.0:
                t = (xx - (cx - r)) / (2.0 * r)
                c = c_light if t < 0.35 else (c_mid if t < 0.7 else c_dark)
                _px(img, xx, yy, c)

def _fade(img, a):
    for y in range(TILE):
        for x in range(TILE):
            p = img.px[y][x]
            if p[3] > 0.0:
                p[3] *= a

# --- ENHANCEMENTS -------------------------------------------------------------
def _glow(img, cx, cy, r, c, strength=0.85):
    """Halo néon additif (bloom). Éclaircit le fond et lui donne un peu d'alpha."""
    for yy in range(int(cy-r), int(cy+r)+1):
        for xx in range(int(cx-r), int(cx+r)+1):
            if not (0 <= xx < TILE and 0 <= yy < TILE): continue
            d = math.hypot(xx-cx, yy-cy)/r
            if d >= 1.0: continue
            fa = (1.0-d)*(1.0-d)*strength
            p = img.px[yy][xx]
            p[0] = min(1.0, p[0]+c.r*fa)
            p[1] = min(1.0, p[1]+c.g*fa)
            p[2] = min(1.0, p[2]+c.b*fa)
            p[3] = min(1.0, p[3]+(1.0-p[3])*fa*c.a)

def _dither(img, x, y, w, h, c_lo, c_hi, t):
    """Remplit un rect en tramant entre c_lo et c_hi selon le ratio t (0..1)."""
    for yy in range(int(y), int(y+h)):
        for xx in range(int(x), int(x+w)):
            thr = (BAYER4[yy & 3][xx & 3]+0.5)/16.0
            _px(img, xx, yy, c_hi if t > thr else c_lo)

def _rim(img, cx, cy, r, c):
    """Liseré de lumière en haut-gauche sur un disque (rim light)."""
    _ellipse(img, cx-r*0.34, cy-r*0.34, r*0.42, r*0.34, c)

# --- IO -----------------------------------------------------------------------
ASSETS = None
def _save(img, name):
    out = Image.new("RGBA", (TILE, TILE))
    data = []
    for y in range(TILE):
        for x in range(TILE):
            p = img.px[y][x]
            data.append((int(round(max(0,min(1,p[0]))*255)),
                         int(round(max(0,min(1,p[1]))*255)),
                         int(round(max(0,min(1,p[2]))*255)),
                         int(round(max(0,min(1,p[3]))*255))))
    out.putdata(data)
    out.save(os.path.join(ASSETS, name+".png"))

def _new(opaque=False):
    return Img(opaque)

# --- Textures du monde --------------------------------------------------------
def _gen_floor():
    img = _new(True); img.fill(FLOOR_A)
    for y in range(TILE):
        for x in range(TILE):
            r = rng.randf()
            if r < 0.10: _px(img, x, y, FLOOR_A.darkened(0.25))
            elif r > 0.92: _px(img, x, y, FLOOR_B)
    for i in range(TILE):
        _px(img, i, 0, INK); _px(img, 0, i, INK)
        _px(img, i, 16, INK_SOFT.darkened(0.1)); _px(img, 16, i, INK_SOFT.darkened(0.1))
    _px(img, 3, 3, FLOOR_B.lightened(0.12)); _px(img, 19, 3, FLOOR_B.lightened(0.12))
    return img

def _gen_wall():
    img = _new(True); img.fill(STONE)
    brick_h = 8; brick_w = 11; row = 0
    for by in range(0, TILE, brick_h):
        for x in range(TILE):
            _px(img, x, by, INK)
            _px(img, x, by+1, INK.lerp(STONE_D, 0.4))
            if by+2 < TILE: _px(img, x, by+2, STONE_L)
        off = (brick_w//2) if (row % 2 == 1) else 0
        bx = -off
        while bx <= TILE:
            for yy in range(by+2, by+brick_h):
                _px(img, bx, yy, INK); _px(img, bx+1, yy, INK.lerp(STONE_D, 0.4))
            face = STONE_L if (row % 2 == 0) else STONE
            for yy in range(by+3, by+brick_h-1):
                for xx in range(bx+2, bx+brick_w-1):
                    if 0 <= xx < TILE and 0 <= yy < TILE: _px(img, xx, yy, face)
            for yy in range(by+2, by+brick_h):
                _px(img, bx+brick_w-1, yy, STONE_D)
            bx += brick_w
        row += 1
    for i in range(18):
        _px(img, rng.randi_range(0, TILE-1), rng.randi_range(0, TILE-1), STONE_D)
    for cp in [(5,4),(17,10),(3,16),(19,3)]:
        _glow(img, cp[0], cp[1], 3.2, ARCANE, 0.55)
        _px(img, cp[0], cp[1], ARCANE); _px(img, cp[0], cp[1]-1, ARCANE_L)
        _px(img, cp[0]-1, cp[1], ARCANE.darkened(0.3))
    return img

def _gen_stairs():
    img = _new(False)
    _disc_o(img, 16, 17, 12.0, INK_SOFT, INK)
    _glow(img, 16.0, 18.7, 12.0, ARCANE, 0.55)
    _ellipse(img, 16, 19, 8.7, 10.0, C(ARCANE.r, ARCANE.g, ARCANE.b, 0.55))
    _ellipse(img, 16, 20, 6.0, 7.3, C(ARCANE_L.r, ARCANE_L.g, ARCANE_L.b, 0.6))
    for s in range(3):
        y = 19-s*3; w = 5-s
        _rect(img, 12-w, y, w*2, 1, C(CYAN_L.r, CYAN_L.g, CYAN_L.b, 0.75))
    _glow(img, 16.0, 13.3, 5.3, GOLD_L, 0.7)
    _tri_up(img, 16, 12, 5, 5, GOLD_L); _tri_up(img, 16, 15, 5, 4, GOLD)
    return img

# --- Créatures ----------------------------------------------------------------
def _glow_eyes(img, cx, ey, c, spread=3):
    _glow(img, cx-spread+0.5, ey+0.5, 2.7, c, 0.7)
    _glow(img, cx+spread-0.5, ey+0.5, 2.7, c, 0.7)
    _rect(img, cx-spread, ey, 3, 3, c); _rect(img, cx+spread-1, ey, 3, 3, c)
    _px(img, cx-spread, ey, c.lightened(0.45)); _px(img, cx+spread, ey, c.lightened(0.45))

def _fig_aria(img):
    _ground_shadow(img)
    _trapezoid(img, 16, 15, 28, 4.8, 8.0, ARCANE.darkened(0.4))
    _rect(img, 12, 24, 4, 5, STEEL_D); _rect(img, 12, 24, 4, 1, STEEL)
    _rect(img, 17, 24, 4, 5, STEEL_D); _rect(img, 17, 24, 4, 1, STEEL)
    _trapezoid_o(img, 16, 20, 27, 3.5, 5.3, ARCANE.darkened(0.25))
    _rect(img, 16, 21, 1, 5, ARCANE_L.darkened(0.1))
    _trapezoid_o(img, 16, 13, 21, 4.3, 4.8, STEEL_D)
    _trapezoid(img, 16, 15, 20, 3.2, 3.7, STEEL_L)
    _rect(img, 13, 15, 7, 1, CYAN)
    _glow(img, 16.0, 17.3, 3.5, CYAN, 0.6)
    _diamond(img, 16, 17, 3, CYAN); _px(img, 16, 17, C(1,1,1))
    _disc_o(img, 11, 15, 2.3, STEEL, STEEL_D); _disc_o(img, 21, 15, 2.3, STEEL, STEEL_D)
    _rect(img, 9, 16, 3, 5, ARCANE.darkened(0.1)); _rect(img, 20, 16, 3, 5, ARCANE.darkened(0.1))
    _px(img, 9, 20, SKIN); _px(img, 21, 20, SKIN)
    _disc_o(img, 16, 9, 4.9, ROSE_D, INK)
    _ellipse(img, 16, 11, 3.3, 3.6, SKIN)
    _rect(img, 12, 9, 3, 5, ROSE); _rect(img, 19, 9, 3, 5, ROSE)
    _px(img, 12, 9, ROSE_L)
    _rect(img, 12, 7, 9, 3, ROSE); _px(img, 13, 7, ROSE_L)
    _rect(img, 13, 9, 7, 1, ROSE_D)
    _px(img, 15, 12, INK); _px(img, 19, 12, INK)
    _px(img, 15, 11, SKIN_D); _px(img, 19, 11, SKIN_D)
    _px(img, 16, 15, SKIN_D)
    _rect(img, 13, 8, 7, 1, GOLD); _glow(img, 16.0, 8.0, 2.1, CYAN_L, 0.7); _px(img, 16, 8, CYAN_L)

def _fig_aria_back(img):
    _ground_shadow(img)
    _rect(img, 12, 24, 4, 5, STEEL_D); _rect(img, 17, 24, 4, 5, STEEL_D)
    _trapezoid_o(img, 16, 12, 29, 4.8, 10.0, ARCANE.darkened(0.45))
    _trapezoid(img, 16, 13, 28, 3.7, 8.0, ARCANE)
    _rect(img, 16, 13, 1, 15, ARCANE_L.darkened(0.12))
    _px(img, 12, 17, ARCANE_L.darkened(0.2)); _px(img, 20, 21, ARCANE_L.darkened(0.2))
    _disc_o(img, 11, 15, 2.3, STEEL, STEEL_D); _disc_o(img, 21, 15, 2.3, STEEL, STEEL_D)
    _rect(img, 12, 13, 8, 1, CYAN)
    _disc_o(img, 16, 9, 4.9, ROSE_D, INK); _disc(img, 16, 9, 4.1, ROSE)
    _ellipse(img, 13, 7, 1.9, 1.6, ROSE_L)
    _rect(img, 15, 12, 3, 11, ROSE_D); _rect(img, 15, 12, 3, 9, ROSE)
    _px(img, 15, 16, ROSE_L); _px(img, 16, 20, ROSE_D)
    _rect(img, 12, 8, 8, 1, GOLD)

def _fig_aria_side(img):
    _ground_shadow(img)
    _trapezoid(img, 12, 15, 28, 3.2, 6.9, ARCANE.darkened(0.45))
    _trapezoid(img, 12, 16, 27, 2.3, 5.3, ARCANE.darkened(0.2))
    _px(img, 7, 27, ARCANE.darkened(0.3))
    _rect(img, 15, 24, 4, 5, STEEL_D); _rect(img, 15, 24, 4, 1, STEEL)
    _rect(img, 17, 25, 4, 4, STEEL_D.darkened(0.08))
    _trapezoid_o(img, 16, 13, 23, 3.2, 4.0, STEEL_D)
    _trapezoid(img, 16, 15, 21, 2.3, 2.9, STEEL_L)
    _rect(img, 17, 16, 4, 1, CYAN)
    _disc_o(img, 15, 15, 2.3, STEEL, STEEL_D)
    _rect(img, 19, 16, 3, 5, ARCANE.darkened(0.1)); _px(img, 20, 20, SKIN)
    _trapezoid_o(img, 12, 12, 25, 1.6, 2.4, ROSE_D)
    _trapezoid(img, 12, 12, 24, 0.9, 1.6, ROSE)
    _px(img, 12, 17, ROSE_L); _px(img, 12, 23, ROSE_D)
    _disc_o(img, 16, 9, 4.8, ROSE_D, INK); _disc(img, 15, 8, 4.0, ROSE)
    _ellipse(img, 13, 7, 1.6, 1.3, ROSE_L)
    _ellipse(img, 19, 11, 2.8, 3.1, SKIN)
    _px(img, 21, 11, SKIN_D); _rect(img, 19, 11, 1, 3, INK); _px(img, 20, 15, SKIN_D)
    _px(img, 17, 7, ROSE); _px(img, 19, 8, ROSE)
    _px(img, 16, 7, GOLD); _px(img, 17, 8, GOLD); _glow(img, 18.7, 9.3, 1.9, CYAN_L, 0.7); _px(img, 19, 9, CYAN_L)

def _fig_knight(img):
    _ground_shadow(img)
    _trapezoid_o(img, 16, 15, 28, 3.3, 8.0, STEEL_D)
    _trapezoid(img, 16, 16, 27, 2.0, 6.0, STEEL)
    _rect(img, 8, 16, 4, 3, BLOOD); _px(img, 7, 17, BLOOD_D); _px(img, 11, 15, BLOOD)
    _rect(img, 13, 17, 5, 7, STEEL_L); _px(img, 13, 17, STEEL)
    _rect(img, 15, 19, 1, 4, C(1,1,1,0.55))
    _disc_o(img, 16, 9, 5.6, STEEL_D, INK); _disc(img, 16, 8, 4.5, STEEL)
    _ellipse(img, 13, 7, 2.1, 1.9, STEEL_L)
    _glow(img, 16.0, 9.3, 4.5, CYAN, 0.4)
    _rect(img, 12, 9, 8, 1, CYAN_L); _px(img, 12, 9, CYAN)
    _tri_up(img, 16, 4, 1, 4, BLOOD)
    _rect(img, 23, 12, 1, 12, STEEL_L); _rect(img, 21, 21, 4, 1, GOLD)

def _fig_mage(img):
    _ground_shadow(img)
    _trapezoid_o(img, 16, 15, 28, 2.7, 8.7, ARCANE.darkened(0.45))
    _trapezoid(img, 16, 16, 27, 1.6, 6.7, ARCANE)
    _rect(img, 15, 19, 3, 8, ARCANE_L.darkened(0.1))
    _disc_o(img, 16, 11, 4.5, ARCANE.darkened(0.4), INK)
    _disc(img, 16, 11, 3.5, C(0.86, 0.78, 0.66))
    _glow_eyes(img, 16, 9, CYAN, 3)
    _trapezoid_o(img, 16, 1, 8, 0.7, 6.0, ARCANE.darkened(0.25))
    _glow(img, 16.0, 1.3, 2.7, GOLD_L, 0.8); _px(img, 16, 1, GOLD_L); _px(img, 12, 8, GOLD)
    _rect(img, 8, 11, 1, 16, GOLD_D)
    _glow(img, 8.0, 9.3, 4.0, CYAN, 0.7)
    _disc_o(img, 8, 9, 2.7, CYAN, INK); _px(img, 8, 8, CYAN_L)

def _fig_ranger(img):
    _ground_shadow(img)
    _trapezoid_o(img, 16, 15, 28, 3.3, 8.0, POISON.darkened(0.5))
    _trapezoid(img, 16, 16, 27, 2.1, 6.1, POISON.darkened(0.25))
    _rect(img, 15, 19, 3, 7, POISON.darkened(0.1))
    _disc_o(img, 16, 9, 5.6, POISON.darkened(0.5), INK)
    _ellipse(img, 16, 8, 4.5, 4.8, POISON.darkened(0.3))
    _ellipse(img, 16, 11, 3.2, 2.7, C(0.07, 0.07, 0.10))
    _glow_eyes(img, 16, 11, CYAN_L, 3)
    for i in range(11):
        yy = 6+i; dx = int(round(3.0*math.sin(i/10.0*math.pi)))
        _px(img, 18-dx, yy, GOLD_D)
    _rect(img, 24, 8, 1, 15, C(0.85, 0.85, 0.9, 0.8))
    return img

def _fig_gobelin(img):
    _ground_shadow(img)
    skin = POISON.darkened(0.15)
    _trapezoid_o(img, 16, 17, 28, 4.0, 7.3, skin.darkened(0.35))
    _trapezoid(img, 16, 19, 27, 2.7, 5.6, skin)
    _rect(img, 13, 20, 5, 4, C(0.45, 0.32, 0.22))
    _disc_o(img, 16, 12, 5.3, skin.darkened(0.3), INK); _disc(img, 16, 12, 4.3, skin)
    _ellipse(img, 13, 9, 1.7, 1.5, skin.lightened(0.28))
    _tri_up(img, 8, 15, 3, 7, skin.darkened(0.1)); _tri_up(img, 24, 15, 3, 7, skin.darkened(0.1))
    _glow_eyes(img, 16, 11, GOLD_L, 3)
    _rect(img, 13, 15, 5, 1, INK); _px(img, 15, 15, BONE)
    _rect(img, 24, 17, 1, 7, STEEL_L)

def _fig_wolf(img):
    _ground_shadow(img)
    fur = C(0.40, 0.42, 0.50); fur_d = fur.darkened(0.45); fur_l = fur.lightened(0.26)
    fur_belly = fur.lightened(0.12)

    # tail (behind body), curved up and back
    _ellipse(img, 27, 18, 3.0, 1.6, fur_d); _ellipse(img, 29, 15, 1.8, 1.6, fur_d)
    _px(img, 30, 13, fur_l)

    # back legs (darker, set behind torso) then front legs (lighter, in front)
    _rect(img, 20, 23, 3, 6, fur_d); _rect(img, 13, 23, 3, 6, fur_d)
    _rect(img, 20, 27, 3, 1, INK_SOFT); _rect(img, 13, 27, 3, 1, INK_SOFT)
    _rect(img, 11, 22, 3, 7, fur); _rect(img, 18, 22, 3, 7, fur)
    _rect(img, 11, 27, 3, 1, INK_SOFT); _rect(img, 18, 27, 3, 1, INK_SOFT)

    # torso: distinct neck taper so head doesn't merge into the body blob
    _ellipse(img, 18, 19, 9.0, 5.4, fur_d)
    _ellipse(img, 18, 19, 7.8, 4.4, fur)
    _ellipse(img, 18, 22, 6.5, 2.4, fur_belly)
    _ellipse(img, 21, 15, 2.6, 2.2, fur_l)

    # head, separated from torso by a darker neck wedge + its own outline
    _ellipse(img, 11, 17, 2.6, 2.0, fur_d)
    _disc_o(img, 7, 15, 4.4, fur_d, INK)
    _disc(img, 7, 15, 3.5, fur)
    _ellipse(img, 6, 14, 1.4, 1.1, fur_l)
    # snout, protruding so the silhouette reads as a head not a circle
    _trapezoid(img, 4, 15, 18, 1.8, 1.0, fur_d); _trapezoid(img, 4, 15, 17, 1.4, 0.8, fur)
    _px(img, 1, 17, INK)
    # ears
    _tri_up(img, 4, 12, 1, 4, fur_d); _tri_up(img, 9, 12, 1, 4, fur_d)
    _px(img, 4, 9, fur_l); _px(img, 9, 9, fur_l)

    _glow(img, 6.3, 14.7, 1.8, CYAN_L, 0.7)
    _px(img, 6, 14, CYAN_L)

def _fig_skeleton(img):
    _ground_shadow(img)
    bn = BONE; bn_d = BONE_D; bn_l = BONE.lightened(0.12)

    # legs as individual bone shafts with a visible knee joint, not a filled wedge
    for lx in (13, 18):
        _rect(img, lx, 21, 2, 4, bn_d); _disc(img, lx + 1, 25, 1.3, bn)
        _rect(img, lx, 26, 2, 3, bn_d)
        _rect(img, lx - 1, 28, 4, 1, INK_SOFT)

    # pelvis block
    _trapezoid_o(img, 16, 18, 22, 3.3, 4.3, bn_d)
    _trapezoid(img, 16, 19, 21, 2.4, 3.3, bn)

    # ribcage: curved bars that narrow towards the bottom, with a sternum line
    for i, ry in enumerate(range(10, 19, 2)):
        hw = 5 - i // 2
        _rect(img, 16 - hw, ry, hw * 2 + 1, 1, bn_d)
        _rect(img, 16 - hw + 1, ry, hw * 2 - 1, 1, bn)
    _rect(img, 16, 10, 1, 9, bn_d)

    # arms hanging at the sides, with elbow joints
    for ax in (10, 22):
        _rect(img, ax, 12, 1, 5, bn_d); _disc(img, ax, 17, 1.0, bn)
        _rect(img, ax, 18, 1, 4, bn_d)
        _px(img, ax, 22, INK_SOFT)

    # skull with jaw line + teeth + deep eye sockets
    _disc_o(img, 16, 7, 5.0, bn_d, INK)
    _disc(img, 16, 6, 4.2, bn)
    _rect(img, 12, 9, 8, 2, bn_d)
    for tx in range(12, 20, 2): _px(img, tx, 9, bn_l)
    _rect(img, 12, 5, 3, 3, INK); _rect(img, 17, 5, 3, 3, INK)
    _glow(img, 13.5, 6.5, 2.0, CYAN, 0.7); _glow(img, 18.5, 6.5, 2.0, CYAN, 0.7)
    _px(img, 13, 6, CYAN_L); _px(img, 18, 6, CYAN_L)
    _px(img, 16, 4, bn_d)

def _fig_orc(img):
    _ground_shadow(img)
    skin = C(0.30, 0.44, 0.30); skin_l = skin.lightened(0.20)
    _trapezoid_o(img, 15, 13, 28, 6.7, 10.0, skin.darkened(0.45))
    _trapezoid(img, 15, 15, 27, 5.3, 8.0, skin)
    _rect(img, 8, 16, 13, 3, C(0.36, 0.25, 0.18)); _rect(img, 11, 20, 8, 4, skin_l)
    _disc_o(img, 15, 9, 6.1, skin.darkened(0.4), INK); _disc(img, 15, 9, 5.1, skin)
    _ellipse(img, 12, 7, 2.1, 1.7, skin_l)
    _rect(img, 9, 8, 12, 1, INK)
    _glow_eyes(img, 15, 9, BLOOD, 4)
    _tri_up(img, 12, 17, 1, 5, BONE); _tri_up(img, 17, 17, 1, 5, BONE)
    _rect(img, 12, 15, 7, 1, INK)
    _rect(img, 24, 7, 1, 20, C(0.36, 0.25, 0.18))
    _rect(img, 19, 7, 7, 7, STEEL_D); _rect(img, 20, 8, 4, 4, STEEL)
    _rect(img, 20, 8, 4, 1, STEEL_L); _px(img, 19, 9, STEEL_L); _px(img, 19, 11, STEEL_L)

def _fig_spectre(img):
    _glow(img, 16.0, 12.0, 8.7, ARCANE, 0.5)
    _disc_o(img, 16, 12, 6.7, ARCANE.darkened(0.35), INK_SOFT); _disc(img, 16, 12, 5.6, ARCANE.darkened(0.1))
    _trapezoid(img, 16, 15, 27, 4.7, 8.0, ARCANE.darkened(0.1))
    for x in range(8, 25):
        cut = 20-((x % 3))
        for y in range(cut, TILE): _px(img, x, y, C(0,0,0,0))
    _ellipse(img, 16, 12, 3.5, 2.9, C(0.06, 0.05, 0.10))
    _glow_eyes(img, 16, 11, CYAN_L, 3); _px(img, 16, 15, CYAN)
    _fade(img, 0.82)

def _fig_boss(img):
    _ellipse(img, 16, 29, 10.7, 2.7, C(INK.r, INK.g, INK.b, 0.40))
    _trapezoid_o(img, 16, 12, 29, 6.0, 11.3, INK_SOFT)
    _trapezoid(img, 16, 13, 28, 4.8, 9.3, C(0.22, 0.12, 0.16))
    _rect(img, 15, 17, 3, 11, BLOOD_D)
    _rect(img, 11, 17, 11, 4, C(0.30, 0.16, 0.20))
    _glow(img, 16.0, 18.7, 3.5, GOLD, 0.65)
    _disc_o(img, 16, 19, 2.7, GOLD, GOLD_D); _px(img, 16, 17, GOLD_L)
    _disc_o(img, 16, 9, 6.1, INK_SOFT, INK); _disc(img, 16, 9, 5.1, C(0.26, 0.16, 0.20))
    _tri_up(img, 8, 8, 3, 8, BONE_D); _tri_up(img, 24, 8, 3, 8, BONE_D)
    _px(img, 8, 0, BONE); _px(img, 24, 0, BONE)
    _glow_eyes(img, 16, 9, EMBER, 4); _px(img, 12, 9, GOLD_L); _px(img, 20, 9, GOLD_L)
    _rect(img, 13, 13, 7, 1, INK)

CREATURES = {
    "aria": _fig_aria, "aria_back": _fig_aria_back, "aria_side": _fig_aria_side,
    "knight": _fig_knight, "mage": _fig_mage, "ranger": _fig_ranger,
    "gobelin": _fig_gobelin, "loup": _fig_wolf, "squelette": _fig_skeleton,
    "orc": _fig_orc, "spectre": _fig_spectre, "boss": _fig_boss,
}
def _gen_creature(kind):
    img = _new(False); CREATURES.get(kind, _fig_knight)(img); return img

# --- Butin --------------------------------------------------------------------
def _gen_weapon():
    img = _new(False)
    _rect(img, 13, 4, 5, 17, INK); _rect(img, 15, 5, 3, 15, STEEL)
    _rect(img, 15, 5, 1, 15, STEEL_L); _tri_up(img, 16, 5, 1, 3, STEEL_L)
    _glow(img, 16.0, 12.0, 5.3, CYAN, 0.30)
    _rect(img, 9, 20, 13, 3, GOLD_D); _rect(img, 9, 20, 13, 1, GOLD)
    _px(img, 8, 20, GOLD); _px(img, 23, 20, GOLD)
    _rect(img, 15, 23, 3, 5, C(0.40, 0.27, 0.18))
    _disc_o(img, 16, 28, 2.1, GOLD, GOLD_D); _px(img, 16, 27, GOLD_L)
    return img

def _gen_armor():
    img = _new(False)
    _trapezoid(img, 16, 4, 16, 9.3, 10.7, STEEL_D); _trapezoid(img, 16, 5, 16, 8.0, 9.3, STEEL)
    for y in range(12, 22):
        w = int(round(8.0*(1.0-(y-12)/9.5)))
        _rect(img, 12-w, y, 1, 1, STEEL_D); _rect(img, 12+w, y, 1, 1, STEEL_D)
        if w > 1: _rect(img, 12-w+1, y, (w-1)*2, 1, STEEL)
    _rect(img, 11, 7, 3, 11, STEEL_L)
    _glow(img, 16.0, 13.3, 4.0, ARCANE, 0.5)
    _disc_o(img, 16, 13, 3.2, ARCANE, INK_SOFT); _disc(img, 16, 13, 1.7, ARCANE_L)
    for ry in [5, 9, 13]: _px(img, 8, ry, STEEL_L); _px(img, 24, ry, STEEL_L)
    return img

def _gen_relic():
    img = _new(False)
    _disc_o(img, 16, 20, 8.0, GOLD, GOLD_D); _disc(img, 16, 20, 4.0, C(0,0,0,0))
    _px(img, 12, 16, GOLD_L)
    _glow(img, 16.0, 8.0, 4.5, CYAN, 0.7)
    _disc_o(img, 16, 8, 4.0, CYAN, INK_SOFT); _disc(img, 16, 8, 2.3, CYAN_L)
    _px(img, 15, 7, C(1,1,1))
    _px(img, 16, 3, CYAN_L); _px(img, 11, 8, CYAN_L); _px(img, 21, 8, CYAN_L)
    return img

def _gen_artifact():
    img = _new(False)
    _glow(img, 16.0, 16.0, 12.0, ARCANE, 0.45)
    _disc(img, 16, 16, 10.7, C(ARCANE.r, ARCANE.g, ARCANE.b, 0.28))
    _disc(img, 16, 16, 6.7, C(ARCANE.r, ARCANE.g, ARCANE.b, 0.30))
    for i in range(10):
        w = int(round(3.5*(1.0-i/10.0)))
        _rect(img, 12-w, 12-i, w*2+1, 1, ARCANE); _rect(img, 12-w, 12+i, w*2+1, 1, ARCANE)
        _rect(img, 12-i, 12-w, 1, w*2+1, ARCANE); _rect(img, 12+i, 12-w, 1, w*2+1, ARCANE)
    _disc(img, 16, 16, 3.2, ARCANE_L); _disc(img, 16, 16, 1.5, C(1,1,1))
    return img

def _gen_potion():
    img = _new(False)
    _rect(img, 13, 4, 5, 3, C(0.40, 0.28, 0.18)); _rect(img, 13, 7, 5, 4, STEEL_D)
    _disc_o(img, 16, 20, 8.0, INK_SOFT, INK); _disc(img, 16, 20, 6.9, C(0.55, 0.78, 0.88))
    _glow(img, 16.0, 21.3, 5.9, BLOOD, 0.45)
    _ellipse(img, 16, 23, 5.9, 4.8, BLOOD); _ellipse(img, 16, 23, 4.5, 3.5, BLOOD.lightened(0.14))
    _rect(img, 12, 16, 1, 8, C(1,1,1,0.7)); _px(img, 19, 15, C(1,1,1,0.6))
    return img

# --- Icônes de nœud de carte --------------------------------------------------
def _gen_node_combat():
    img = _new(False)
    _line(img, 7, 25, 24, 7, INK); _line(img, 8, 25, 25, 7, INK)
    _line(img, 7, 24, 23, 7, STEEL); _line(img, 8, 24, 24, 7, STEEL_L); _px(img, 25, 5, STEEL_L)
    _line(img, 25, 25, 8, 7, INK); _line(img, 24, 25, 7, 7, INK)
    _line(img, 25, 24, 9, 7, STEEL); _line(img, 24, 24, 8, 7, STEEL_L); _px(img, 5, 5, STEEL_L)
    _line(img, 4, 23, 11, 27, GOLD); _line(img, 28, 23, 21, 27, GOLD)
    _disc_o(img, 7, 27, 1.9, GOLD, GOLD_D); _disc_o(img, 25, 27, 1.9, GOLD, GOLD_D)
    _glow(img, 16.0, 16.0, 3.2, CYAN_L, 0.7)
    _px(img, 16, 16, C(1,1,1)); _px(img, 16, 15, CYAN_L); _px(img, 17, 16, CYAN_L)
    return img

def _gen_node_boss():
    img = _new(False)
    _line(img, 7, 19, 4, 9, BONE_D); _line(img, 8, 19, 5, 9, BONE); _px(img, 4, 8, BONE); _px(img, 5, 7, BONE)
    _line(img, 25, 19, 28, 9, BONE_D); _line(img, 24, 19, 27, 9, BONE); _px(img, 28, 8, BONE); _px(img, 27, 7, BONE)
    _rect(img, 8, 19, 17, 7, GOLD_D); _rect(img, 8, 19, 17, 1, GOLD_L); _rect(img, 9, 20, 15, 4, GOLD)
    _tri_up(img, 11, 19, 3, 5, GOLD); _tri_up(img, 16, 19, 3, 8, GOLD); _tri_up(img, 21, 19, 3, 5, GOLD)
    _px(img, 11, 13, GOLD_L); _px(img, 21, 13, GOLD_L)
    _glow(img, 16.0, 10.7, 3.5, EMBER, 0.75)
    _diamond(img, 16, 11, 3, EMBER.darkened(0.2)); _diamond(img, 16, 11, 1, EMBER); _px(img, 16, 9, GOLD_L)
    _diamond(img, 16, 21, 1, EMBER); _px(img, 16, 21, GOLD_L)
    return img

def _gen_node_elite():
    img = _new(False)
    _tri_up(img, 8, 9, 1, 5, BONE_D); _tri_up(img, 24, 9, 1, 5, BONE_D); _px(img, 8, 4, BONE); _px(img, 24, 4, BONE)
    _disc_o(img, 16, 13, 8.0, BONE_D, INK); _disc(img, 16, 12, 6.9, BONE)
    _ellipse(img, 12, 8, 2.1, 1.7, C(1,1,0.95))
    _rect(img, 11, 11, 4, 4, INK); _rect(img, 19, 11, 4, 4, INK)
    _glow(img, 12.7, 12.7, 2.4, EMBER, 0.7); _glow(img, 20.7, 12.7, 2.4, EMBER, 0.7)
    _px(img, 12, 12, EMBER); _px(img, 20, 12, EMBER); _px(img, 12, 11, GOLD_L); _px(img, 20, 11, GOLD_L)
    _px(img, 16, 16, INK)
    _rect(img, 11, 20, 12, 4, BONE_D); _rect(img, 11, 20, 12, 1, BONE)
    for tx in range(12, 23, 3): _rect(img, tx, 20, 1, 4, INK)
    return img

def _gen_node_shop():
    img = _new(False)
    leather = C(0.45, 0.32, 0.22); leather_d = leather.darkened(0.35)
    _glow(img, 16.0, 8.0, 3.2, GOLD, 0.55)
    _disc_o(img, 16, 8, 3.1, GOLD, GOLD_D); _px(img, 15, 7, GOLD_L)
    _disc_o(img, 16, 20, 9.3, leather_d, INK); _disc(img, 16, 20, 8.0, leather)
    _ellipse(img, 12, 16, 3.1, 2.1, leather.lightened(0.22))
    _rect(img, 11, 11, 11, 3, leather_d); _rect(img, 9, 13, 13, 1, GOLD_D); _rect(img, 9, 12, 13, 1, GOLD)
    _diamond(img, 16, 21, 3, GOLD); _px(img, 16, 21, GOLD_L)
    return img

def _gen_node_event():
    img = _new(False)
    _glow(img, 16.0, 16.0, 11.3, ARCANE, 0.45)
    _disc(img, 16, 16, 10.7, C(ARCANE.r, ARCANE.g, ARCANE.b, 0.25))
    _diamond(img, 16, 16, 9, ARCANE.darkened(0.35)); _diamond(img, 16, 16, 8, ARCANE)
    _diamond(img, 16, 16, 5, ARCANE.darkened(0.45))
    _rect(img, 13, 11, 5, 1, CYAN_L); _px(img, 17, 12, CYAN_L); _px(img, 17, 13, CYAN_L)
    _px(img, 16, 15, CYAN_L); _px(img, 16, 16, CYAN_L); _px(img, 16, 17, CYAN_L)
    _glow(img, 16.0, 20.0, 1.9, C(1,1,1), 0.8); _px(img, 16, 20, C(1,1,1))
    return img

def _gen_node_rest():
    img = _new(False)
    wood = C(0.45, 0.32, 0.21); wood_l = C(0.55, 0.40, 0.27)
    _line(img, 7, 25, 21, 20, INK); _line(img, 25, 25, 11, 20, INK)
    _line(img, 7, 24, 21, 19, wood); _line(img, 8, 24, 23, 19, wood_l)
    _line(img, 25, 24, 11, 19, wood); _line(img, 24, 24, 9, 19, wood_l)
    _px(img, 7, 24, wood_l); _px(img, 25, 24, wood_l)
    _glow(img, 16.0, 16.0, 6.7, EMBER, 0.55)
    _tri_up(img, 16, 20, 5, 13, EMBER.darkened(0.25)); _tri_up(img, 16, 20, 4, 11, EMBER)
    _tri_up(img, 16, 19, 3, 8, GOLD); _px(img, 16, 11, GOLD_L)
    _px(img, 13, 17, EMBER.lightened(0.1)); _px(img, 19, 17, EMBER)
    _px(img, 12, 24, EMBER); _px(img, 20, 24, GOLD)
    return img

# --- Terrain par biome --------------------------------------------------------
def _gen_ground(a, b):
    img = _new(True); img.fill(a)
    joint_outer = a.darkened(0.42).lerp(INK, 0.55)
    joint_inner = a.darkened(0.22).lerp(INK_SOFT, 0.35)
    for i in range(TILE):
        _px(img, i, 0, joint_outer); _px(img, 0, i, joint_outer)
        _px(img, i, 16, joint_inner); _px(img, 16, i, joint_inner)
    for i in range(TILE):
        _px(img, i, 1, a.lightened(0.10)); _px(img, 1, i, a.lightened(0.10))
        _px(img, i, 17, a.lightened(0.06)); _px(img, 17, i, a.lightened(0.06))
    for i in range(TILE):
        _px(img, i, 15, a.darkened(0.16)); _px(img, 15, i, a.darkened(0.16))
    # Grain tramé (Bayer) : transitions douces sans bruit criard.
    for y in range(TILE):
        for x in range(TILE):
            thr = (BAYER4[y & 3][x & 3]+0.5)/16.0
            r = rng.randf()
            if r > 0.90 and 0.5 > thr: _px(img, x, y, b)
            elif r < 0.06: _px(img, x, y, a.darkened(0.22))
            elif (x*5+y*3) % 17 == 0: _px(img, x, y, a.lightened(0.06))
    for p in [(2,2),(14,2),(2,14),(14,14)]:
        _px(img, p[0], p[1], b.lightened(0.14))
    for i in range(9):
        _px(img, i, 0, a.lightened(0.09)); _px(img, 0, i, a.lightened(0.07))
    edge = a.darkened(0.40).lerp(INK_SOFT, 0.5)
    for i in range(TILE):
        _px(img, i, TILE-1, edge); _px(img, TILE-1, i, edge)
    return img

def _gen_tree(trunk, leaf, style):
    img = _new(False)
    tk  = trunk;   tk_d = trunk.darkened(0.45); tk_l = trunk.lightened(0.18)
    lf  = leaf;    lf_d = leaf.darkened(0.42);  lf_l = leaf.lightened(0.28)
    lf_h = leaf.lightened(0.50)
    if style == "round":
        # Root bumps
        _ellipse(img, 13, 29, 2.5, 1.4, tk_d)
        _ellipse(img, 19, 29, 2.0, 1.2, tk_d)
        _ellipse(img, 16, 30, 3.2, 1.3, tk_d)
        # Trunk with bark texture
        _trapezoid(img, 16, 16, 30, 2.0, 3.8, tk_d)
        _trapezoid(img, 16, 16, 29, 1.2, 2.8, tk)
        _rect(img, 16, 16, 1, 13, tk_l)
        _px(img, 15, 20, tk_d); _px(img, 17, 24, tk_d)
        _px(img, 16, 22, tk_l); _px(img, 15, 26, tk_l)
        # Side branch stubs
        _rect(img, 10, 20, 5, 1, tk_d); _rect(img, 11, 20, 3, 1, tk)
        _rect(img, 20, 23, 4, 1, tk_d); _rect(img, 20, 23, 3, 1, tk)
        # Canopy - left(lit)->right(shadow) gradient instead of a flat fill
        _disc_o(img, 16, 13, 11.0, lf_d, INK_SOFT)
        _disc_band(img, 16, 13, 9.5, lf_l, lf, lf_d)
        _disc(img, 11, 9, 4.5, lf_l); _disc(img, 11, 9, 2.4, lf_h)
        _disc(img, 21, 11, 3.2, lf_l)
        _px(img, 9, 7, lf_h);  _px(img, 10, 6, lf_l)
        _px(img, 19, 5, lf_l); _px(img, 23, 9, lf_h)
        _ellipse(img, 16, 20, 7.0, 2.2, lf_d)
    elif style == "pine":
        cone = C(0.32, 0.20, 0.12)
        # trunk w/ bark striations
        _rect(img, 14, 25, 4, 6, tk_d); _rect(img, 15, 25, 2, 6, tk)
        _px(img, 14, 27, tk_d); _px(img, 17, 29, tk_d); _px(img, 15, 28, tk_l)
        tiers = [(16, 28, 10, 10), (16, 21, 8, 8), (16, 15, 6, 7), (16, 10, 4, 6), (16, 6, 2, 4)]
        for cx, base_y, hw, h in tiers:
            _tri_up(img, cx, base_y, hw + 1, h + 1, INK_SOFT)              # crisp silhouette
            _tri_band(img, cx, base_y, hw, h, lf_l, lf, lf_d)              # lit->shadow gradient
            _px(img, cx - hw + 1, base_y - 1, lf_l)
            _px(img, cx + hw - 1, base_y - 1, lf_d)
        _ellipse(img, 12, 23, 1.1, 1.6, cone); _ellipse(img, 21, 17, 1.0, 1.4, cone)  # pinecones
        for cx, cy in [(13, 24), (12, 17), (13, 12), (14, 8)]:
            _px(img, cx, cy, lf_h)
        _px(img, 15, 5, lf_h)
    elif style == "cactus":
        _rect(img, 13, 5, 6, 25, lf_d); _rect(img, 14, 5, 5, 25, lf)
        _rect(img, 15, 5, 2, 25, lf_l)
        _rect(img, 7, 12, 7, 3, lf_d);  _rect(img, 7, 12, 7, 2, lf)
        _rect(img, 7, 9, 3, 5, lf_d);   _rect(img, 8, 9, 2, 5, lf)
        _rect(img, 19, 15, 6, 3, lf_d); _rect(img, 19, 15, 6, 2, lf)
        _rect(img, 22, 11, 3, 6, lf_d); _rect(img, 23, 11, 2, 6, lf)
        for yy in range(7, 28, 4):
            _px(img, 14, yy, lf_l); _px(img, 13, yy+2, lf_d)
        # ridge highlight along each arm tip + a small desert flower for accent
        _px(img, 8, 9, lf_h); _px(img, 24, 11, lf_h)
        _disc(img, 9, 8, 1.1, ROSE); _px(img, 9, 8, ROSE_L)
    elif style == "dead":
        _rect(img, 15, 4, 3, 27, tk_d); _rect(img, 15, 4, 2, 27, tk)
        _rect(img, 15, 4, 1, 20, tk_l)
        _rect(img, 8, 15, 7, 1, tk_d);  _rect(img, 9, 15, 6, 1, tk)
        _rect(img, 8, 11, 1, 5, tk_d);  _rect(img, 9, 11, 1, 4, tk)
        _rect(img, 7, 10, 2, 2, tk_d)
        _rect(img, 17, 12, 7, 1, tk_d); _rect(img, 17, 12, 6, 1, tk)
        _rect(img, 23, 8, 1, 5, tk_d);  _rect(img, 22, 9, 1, 4, tk)
        _px(img, 6, 10, tk_d); _px(img, 8, 9, tk_d)
        _px(img, 24, 7, tk_d); _px(img, 22, 8, tk_d)
        _rect(img, 13, 4, 5, 2, tk)
        # bark knots + a couple of bare twig forks for extra texture
        _px(img, 16, 16, tk_d); _px(img, 15, 22, tk_d); _px(img, 16, 9, tk_l)
        _line(img, 9, 14, 7, 12, tk_d); _line(img, 23, 11, 25, 9, tk_d)
    else:
        _disc_o(img, 16, 16, 8.5, lf_d, INK_SOFT); _disc_band(img, 16, 16, 7.0, lf_l, lf, lf_d)
        _disc(img, 12, 12, 3.5, lf_l); _px(img, 11, 11, lf_h)
    return img

def _gen_rock(c):
    img = _new(False)
    c_d = c.darkened(0.42); c_dd = c.darkened(0.58); c_l = c.lightened(0.30); c_ll = c.lightened(0.50)
    moss = C(0.40, 0.62, 0.30)

    _ellipse(img, 16, 29, 9.5, 2.2, C(INK.r, INK.g, INK.b, 0.30))   # ombre de contact

    # petit bloc compagnon (arrière-gauche), dessiné avant pour que le rocher principal le chevauche
    _ellipse(img, 9, 21, 4.3, 3.6, INK_SOFT)
    _ellipse(img, 9, 21, 3.4, 2.8, c_d)
    _ellipse(img, 8, 19, 1.3, 1.0, c_l)

    # rocher principal
    _ellipse(img, 17, 19, 11.0, 8.4, INK_SOFT)
    _ellipse(img, 17, 19, 9.7, 7.2, c)
    _ellipse(img, 13, 14, 3.8, 2.7, c_l)             # plaque de lumière haut-gauche
    _ellipse(img, 12, 13, 1.6, 1.1, c_ll)            # cœur spéculaire
    _ellipse(img, 21, 23, 3.6, 2.6, c_dd)            # ombre bas-droite

    # fissures irrégulières plutôt que des rects droits
    _line(img, 18, 12, 17, 17, c_dd); _line(img, 17, 17, 19, 22, c_dd)
    _line(img, 10, 18, 13, 20, c_dd)

    # petits cailloux à la base (blobs 2x2, pas des cercles à 1px qui créent des croix)
    _rect(img, 23, 24, 2, 2, c_d); _px(img, 23, 24, c_l)
    _rect(img, 21, 26, 2, 2, c); _px(img, 21, 26, c_l)
    _rect(img, 4, 24, 2, 2, c_d); _px(img, 4, 24, c_l)

    # touffes de mousse le long du sommet
    _rect(img, 18, 12, 2, 2, moss); _rect(img, 19, 13, 2, 1, moss.darkened(0.15))
    _rect(img, 9, 17, 2, 2, moss.darkened(0.1))
    return img

def _gen_water(c):
    img = _new(True); base = c.darkened(0.45); img.fill(base)
    trough = c.darkened(0.32); mid = c.lightened(0.06); crest = c.lightened(0.40)
    for y in range(1, TILE, 4):
        off = (y//4) % 3
        for x in range(TILE):
            phase = (x+off*5) % 12
            ty = y+(phase//6)
            if ty < TILE: _px(img, x, ty, trough)
            my = y+1+(phase//8)
            if my < TILE: _px(img, x, my, mid)
            if phase == 0 or phase == 6:
                cy = y+1
                if cy < TILE: _px(img, x, cy, crest)
                if cy-1 >= 0: _px(img, x, cy-1, C(1.0, 1.0, 1.0, 0.55))
    for y in range(TILE):
        for x in range(TILE):
            if (x*3+y*7) % 23 == 0: _px(img, x, y, crest.lightened(0.18))
    for i in range(TILE):
        _px(img, i, TILE-1, base.darkened(0.35)); _px(img, TILE-1, i, base.darkened(0.35))
    _px(img, TILE-1, TILE-1, base.darkened(0.50))
    return img

def _biome_decor_name(biome_id, variant):
    if variant <= 0:
        return "%s_decor" % biome_id
    return "%s_decor%d" % (biome_id, variant + 1)

def _gen_decor(c, style):
    img = _new(False)
    if style == "flower":
        _rect(img, 16, 19, 1, 8, POISON.darkened(0.2))
        _glow(img, 16.0, 16.0, 2.9, c, 0.45)
        _disc_o(img, 16, 16, 3.2, c, INK_SOFT); _px(img, 16, 16, GOLD_L)
    elif style == "mushroom":
        _rect(img, 16, 21, 3, 5, BONE)
        _glow(img, 17.3, 17.3, 4.0, c, 0.35)
        _ellipse(img, 17, 19, 5.6, 3.7, c.darkened(0.25)); _ellipse(img, 17, 17, 4.5, 2.7, c)
        _px(img, 15, 17, C(1,1,1)); _px(img, 19, 19, C(1,1,1))
    elif style == "bones":
        _rect(img, 11, 21, 11, 1, BONE)
        _rect(img, 11, 20, 1, 4, BONE); _rect(img, 20, 20, 1, 4, BONE)
        _px(img, 9, 20, BONE_D); _px(img, 21, 20, BONE_D)
    elif style == "crystal":
        _glow(img, 16.0, 17.3, 5.3, c, 0.6)
        _diamond(img, 16, 19, 5, c.darkened(0.3)); _diamond(img, 16, 19, 4, c)
        _rect(img, 16, 15, 1, 8, c.lightened(0.48)); _px(img, 15, 16, C(1,1,1))
    elif style == "reed":
        for sx in [12, 16, 20]:
            _rect(img, sx, 15, 1, 12, c.darkened(0.15)); _ellipse(img, sx, 13, 1.9, 3.2, c.darkened(0.3))
    elif style == "ember":
        _glow(img, 16.0, 21.3, 5.3, EMBER, 0.6)
        _ellipse(img, 16, 23, 4.5, 2.7, INK_SOFT)
        _ellipse(img, 16, 21, 3.2, 2.1, EMBER.darkened(0.2)); _ellipse(img, 16, 21, 1.9, 1.3, EMBER)
        _px(img, 16, 19, GOLD_L)
    elif style == "tall_grass":
        green = POISON.darkened(0.1); green_d = green.darkened(0.3); green_l = green.lightened(0.25)
        for bx, h, lean in [(11, 11, -1), (14, 14, 0), (17, 13, 1), (20, 10, 0), (23, 12, -1)]:
            for i in range(h):
                t = i / float(h)
                xx = bx + int(lean * t * 2)
                col = green_d if i < h * 0.3 else green
                _px(img, xx, 26 - i, col)
            _px(img, bx + lean, 26 - h, green_l)
        _px(img, 20, 14, c)
    elif style == "dandelion":
        stem = POISON.darkened(0.25)
        _ellipse(img, 16, 27, 2.5, 1.0, C(INK.r, INK.g, INK.b, 0.25))
        _rect(img, 16, 16, 1, 11, stem)
        _line(img, 16, 16, 13, 13, stem)
        puff = C(0.92, 0.92, 0.90)
        _disc(img, 16, 11, 4.3, C(puff.r, puff.g, puff.b, 0.55))
        for a in range(0, 360, 30):
            rad = math.radians(a)
            x = 16 + 4.0 * math.cos(rad); y = 11 + 4.0 * math.sin(rad)
            _px(img, int(round(x)), int(round(y)), puff)
        _disc(img, 16, 11, 1.6, puff.lightened(0.05))
        _px(img, 13, 13, c)
    elif style == "fern":
        green = C(0.20, 0.46, 0.30); green_d = green.darkened(0.35); green_l = green.lightened(0.30)
        _rect(img, 16, 14, 1, 13, green_d)
        for i in range(7):
            y = 16 + i * 1.6
            w = 7 - i
            if w <= 0: continue
            _line(img, 16, int(y), 16 - w, int(y) - 1, green_d)
            _line(img, 16, int(y), 16 - w + 1, int(y) - 1, green)
            _line(img, 16, int(y), 16 + w, int(y) - 1, green_d)
            _line(img, 16, int(y), 16 + w - 1, int(y) - 1, green)
        _px(img, 16, 14, green_l)
    elif style == "spider_web":
        silk = C(0.85, 0.85, 0.90, 0.55)
        cx, cy = 26, 6
        for a in range(0, 91, 18):
            rad = math.radians(a)
            ex = cx - 22 * math.cos(rad); ey = cy + 22 * math.sin(rad)
            _line(img, cx, cy, int(ex), int(ey), silk)
        for r in (6, 11, 16):
            pts = []
            for a in range(0, 91, 10):
                rad = math.radians(a)
                pts.append((cx - r * math.cos(rad), cy + r * math.sin(rad)))
            for i in range(len(pts) - 1):
                _line(img, int(pts[i][0]), int(pts[i][1]), int(pts[i+1][0]), int(pts[i+1][1]), silk)
        _px(img, 18, 11, C(1, 1, 1, 0.9))
        _disc(img, 12, 9, 1.0, INK)
    elif style == "tumbleweed":
        dry = C(0.45, 0.36, 0.20); dry_d = dry.darkened(0.35); dry_l = dry.lightened(0.25)
        _ellipse(img, 16, 27, 7.0, 1.6, C(INK.r, INK.g, INK.b, 0.25))
        subcenters = [(14, 18), (18, 20), (16, 16), (12, 21), (20, 17)]
        for scx, scy in subcenters:
            for _i in range(5):
                a = rng.randf() * 360.0
                rad = math.radians(a)
                length = 4.5 + rng.randf() * 3.0
                ex = scx + length * math.cos(rad); ey = scy + length * 0.78 * math.sin(rad)
                ex = max(6, min(26, ex)); ey = max(11, min(25, ey))
                _line(img, scx, scy, int(round(ex)), int(round(ey)), dry_d if rng.randf() < 0.5 else dry)
        _line(img, 11, 17, 21, 21, dry_d); _line(img, 21, 15, 12, 23, dry_d)
        _line(img, 9, 20, 23, 18, dry.darkened(0.1))
        _px(img, 13, 16, dry_l); _px(img, 19, 22, dry_l); _px(img, 16, 13, dry_l)
    elif style == "cracked_earth":
        base = C(0.42, 0.32, 0.18); crack = base.darkened(0.5); hi = base.lightened(0.18)
        _ellipse(img, 16, 20, 11.0, 7.0, C(base.r, base.g, base.b, 0.55))
        _line(img, 8, 16, 16, 20, crack); _line(img, 16, 20, 13, 26, crack)
        _line(img, 16, 20, 24, 17, crack); _line(img, 24, 17, 26, 23, crack)
        _line(img, 16, 20, 18, 14, crack)
        _px(img, 10, 18, hi); _px(img, 21, 19, hi); _px(img, 15, 24, hi)
    elif style == "icicle":
        ice = c.darkened(0.1); ice_d = c.darkened(0.35); ice_l = C(1, 1, 1)
        for cx, top, length in [(12, 8, 13), (16, 6, 17), (20, 9, 11)]:
            for i in range(length):
                t = i / float(length)
                w = max(1, int(round((1.0 - t) * 2.2)))
                yy = top + i
                for xx in range(cx - w, cx + w + 1):
                    _px(img, xx, yy, ice_d if (xx + yy) % 3 == 0 else ice)
            _px(img, cx, top, ice_l)
        _glow(img, 16.0, 14.0, 5.0, c, 0.25)
    elif style == "snow_drift":
        snow = C(0.92, 0.95, 1.0); snow_d = snow.darkened(0.12); snow_l = C(1, 1, 1)
        _ellipse(img, 16, 24, 10.5, 4.5, snow_d)
        _ellipse(img, 16, 22, 8.5, 3.6, snow)
        _ellipse(img, 12, 20, 3.0, 1.8, snow_l)
        _glow(img, 12.0, 19.0, 2.5, c, 0.35)
        _px(img, 21, 21, c); _px(img, 9, 23, c)
    elif style == "lily_pad":
        pad = c.darkened(0.2); pad_d = pad.darkened(0.3); pad_l = pad.lightened(0.2)
        _ellipse(img, 11, 21, 5.5, 2.6, pad_d); _ellipse(img, 11, 21, 4.6, 2.1, pad)
        _line(img, 11, 21, 8, 20, pad_d)
        _ellipse(img, 21, 18, 4.3, 2.0, pad_d); _ellipse(img, 21, 18, 3.5, 1.6, pad)
        _line(img, 21, 18, 23, 17, pad_d)
        _disc(img, 21, 17, 1.1, C(0.95, 0.55, 0.75)); _px(img, 21, 17, C(1, 0.8, 0.9))
        _px(img, 9, 20, pad_l); _px(img, 19, 17, pad_l)
    elif style == "wisp":
        glow_c = C(0.55, 0.95, 0.55)
        _glow(img, 16.0, 18.0, 8.0, glow_c, 0.5)
        _disc(img, 16, 18, 2.6, C(glow_c.r, glow_c.g, glow_c.b, 0.7))
        _disc(img, 16, 18, 1.3, C(1, 1, 1, 0.9))
        _disc(img, 11, 13, 1.1, C(glow_c.r, glow_c.g, glow_c.b, 0.5))
        _disc(img, 21, 11, 0.9, C(glow_c.r, glow_c.g, glow_c.b, 0.45))
    elif style == "obsidian_shard":
        glass = C(0.10, 0.08, 0.14); glass_l = C(0.30, 0.26, 0.36); glass_hi = C(0.55, 0.50, 0.65)
        _ellipse(img, 16, 27, 6.5, 1.6, C(INK.r, INK.g, INK.b, 0.3))
        _tri_up(img, 12, 26, 3, 14, glass); _tri_up(img, 12, 26, 2, 12, glass_l)
        _tri_up(img, 18, 27, 2, 10, glass); _tri_up(img, 18, 27, 1, 8, glass_l)
        _tri_up(img, 22, 25, 2, 8, glass.darkened(0.1))
        _line(img, 11, 14, 12, 20, glass_hi); _line(img, 17, 19, 18, 23, glass_hi)
        _px(img, 11, 14, c)
    elif style == "ash_pile":
        ash = C(0.30, 0.28, 0.28); ash_d = ash.darkened(0.42); ash_l = ash.lightened(0.22)
        bone = BONE.darkened(0.15); bone_d = BONE_D
        _ellipse(img, 16, 28, 8.5, 2.0, C(INK.r, INK.g, INK.b, 0.3))
        _disc(img, 16, 24, 7.3, ash_d)
        _disc(img, 13, 23, 5.0, ash); _disc(img, 19, 24, 4.6, ash)
        _disc(img, 16, 21, 4.2, ash.lightened(0.06))
        _disc(img, 12, 21, 1.6, ash_l)
        _line(img, 9, 15, 14, 21, bone_d); _line(img, 10, 15, 15, 21, bone)
        _disc(img, 9, 15, 1.3, bone); _disc(img, 14, 21, 1.1, bone_d)
        _px(img, 9, 14, BONE)
        _glow(img, 17.0, 21.0, 4.0, EMBER, 0.4)
        _px(img, 17, 20, EMBER_L); _px(img, 20, 22, EMBER)
    else:
        _disc_o(img, 16, 19, 2.7, c, INK_SOFT)
    return img

# --- Structures de point d'intérêt (POI), une par biome -----------------------
def _gen_standing_stone(c):
    img = _new(False)
    stone = C(0.42, 0.42, 0.46); stone_d = stone.darkened(0.4); stone_l = stone.lightened(0.22)
    moss = C(0.40, 0.62, 0.30)
    _ellipse(img, 16, 28, 6.5, 1.8, C(INK.r, INK.g, INK.b, 0.3))
    _trapezoid_o(img, 16, 5, 27, 3.2, 5.3, stone_d, INK)
    _trapezoid(img, 16, 6, 26, 2.4, 4.3, stone)
    _rect(img, 16, 6, 1, 18, stone_l)
    _rect(img, 11, 17, 3, 2, moss); _rect(img, 19, 21, 2, 2, moss.darkened(0.1))
    _glow(img, 16.0, 12.0, 3.0, c, 0.4)
    _rect(img, 15, 9, 2, 6, C(c.r, c.g, c.b, 0.7))
    _px(img, 16, 9, c)
    return img

def _gen_forest_altar(c):
    img = _new(False)
    stone = C(0.38, 0.40, 0.38); stone_d = stone.darkened(0.4); stone_l = stone.lightened(0.2)
    moss = C(0.30, 0.55, 0.28)
    _ellipse(img, 16, 27, 10.0, 2.6, C(INK.r, INK.g, INK.b, 0.3))
    _rect(img, 7, 19, 18, 6, stone_d); _rect(img, 8, 20, 16, 4, stone)
    _rect(img, 8, 20, 16, 1, stone_l)
    _rect(img, 9, 13, 4, 7, stone_d); _rect(img, 19, 13, 4, 7, stone_d)
    for mx, my in [(9, 19), (14, 18), (20, 20), (17, 21)]:
        _rect(img, mx, my, 2, 2, moss)
    _glow(img, 16.0, 21.0, 4.0, c, 0.35)
    _diamond(img, 16, 21, 2, C(c.r, c.g, c.b, 0.8))
    return img

def _gen_wagon_wheel(c):
    img = _new(False)
    wood = C(0.40, 0.28, 0.16); wood_d = wood.darkened(0.4); wood_l = wood.lightened(0.2)
    _ellipse(img, 16, 27, 9.0, 2.2, C(INK.r, INK.g, INK.b, 0.3))
    _disc_o(img, 16, 19, 9.5, wood_d, INK); _disc(img, 16, 19, 8.3, wood)
    _disc_o(img, 16, 19, 2.3, wood_d, INK); _disc(img, 16, 19, 1.6, wood_l)
    for a in range(0, 360, 45):
        rad = math.radians(a)
        ex = 16 + 8.0 * math.cos(rad); ey = 19 + 8.0 * math.sin(rad)
        _line(img, 16, 19, int(ex), int(ey), wood_d)
    _px(img, 11, 14, wood_l)
    _ellipse(img, 8, 25, 2.5, 1.0, BONE_D)
    return img

def _gen_ice_cairn(c):
    img = _new(False)
    stone = C(0.55, 0.58, 0.64); stone_d = stone.darkened(0.35); stone_l = stone.lightened(0.25)
    _ellipse(img, 16, 28, 6.5, 1.7, C(INK.r, INK.g, INK.b, 0.3))
    _ellipse(img, 16, 25, 7.0, 3.0, stone_d); _ellipse(img, 16, 25, 6.0, 2.4, stone)
    _ellipse(img, 16, 19, 5.5, 2.6, stone_d); _ellipse(img, 16, 19, 4.6, 2.0, stone)
    _ellipse(img, 16, 13, 4.0, 2.0, stone_d); _ellipse(img, 16, 13, 3.2, 1.5, stone)
    _ellipse(img, 16, 8, 2.6, 1.6, stone_l)
    _glow(img, 16.0, 13.0, 5.0, c, 0.4)
    _px(img, 13, 20, c); _px(img, 19, 14, c)
    return img

def _gen_sunken_ruin(c):
    img = _new(False)
    stone = C(0.36, 0.38, 0.36); stone_d = stone.darkened(0.4); stone_l = stone.lightened(0.18)
    moss = C(0.40, 0.55, 0.25)
    _ellipse(img, 16, 28, 10.0, 2.4, C(INK.r, INK.g, INK.b, 0.3))
    _rect(img, 6, 10, 5, 17, stone_d); _rect(img, 7, 11, 3, 15, stone)
    _rect(img, 21, 10, 5, 17, stone_d); _rect(img, 22, 11, 3, 15, stone)
    _trapezoid(img, 16, 6, 11, 9.0, 6.0, stone_d)
    _trapezoid(img, 16, 7, 10, 7.5, 5.0, stone)
    for mx, my in [(7, 14), (23, 18), (12, 25), (19, 24)]:
        _rect(img, mx, my, 2, 2, moss)
    _ellipse(img, 16, 27, 9.0, 1.4, C(c.r, c.g, c.b, 0.35))
    return img

def _gen_abandoned_anvil(c):
    img = _new(False)
    iron = C(0.18, 0.17, 0.20); iron_d = iron.darkened(0.4); iron_l = C(0.40, 0.38, 0.42)
    stone = C(0.32, 0.26, 0.24); stone_d = stone.darkened(0.4)
    _ellipse(img, 16, 28, 8.5, 2.2, C(INK.r, INK.g, INK.b, 0.3))
    _rect(img, 10, 21, 13, 7, stone_d); _rect(img, 11, 22, 11, 5, stone)
    _trapezoid(img, 13, 14, 21, 2.0, 4.0, iron_d); _trapezoid(img, 13, 14, 20, 1.4, 3.2, iron)
    _rect(img, 6, 12, 16, 4, iron_d); _rect(img, 6, 12, 16, 2, iron)
    _rect(img, 6, 12, 16, 1, iron_l)
    _tri_up(img, 22, 14, 3, 4, iron_d)
    _glow(img, 16.0, 22.0, 4.0, EMBER, 0.35)
    _px(img, 14, 22, EMBER); _px(img, 18, 23, EMBER_L)
    return img

def _gen_road():
    img = _new(True); dirt = C(0.24, 0.20, 0.18); img.fill(dirt)
    for i in range(60):
        x = rng.randi_range(0, TILE-1); y = rng.randi_range(0, TILE-1)
        _px(img, x, y, dirt.darkened(rng.randf()*0.35))
    for i in range(9):
        x = rng.randi_range(2, TILE-3); y = rng.randi_range(2, TILE-3)
        _ellipse(img, x, y, 1.9, 1.5, C(0.40, 0.36, 0.33)); _px(img, x-1, y-1, C(0.50, 0.46, 0.42))
    return img

# --- Décor du monde ouvert (props globaux, indépendants du biome) -------------
_WOOD = C(0.45, 0.32, 0.20)

def _tri_right(img, apex_x, apex_y, length, half_h, c):
    """Triangle pointant vers la droite, sommet en (apex_x, apex_y)."""
    for i in range(length):
        h = int(round(half_h * (1.0 - i / float(length))))
        xx = apex_x - i
        for yy in range(apex_y - h, apex_y + h + 1):
            _px(img, xx, yy, c)

def _gen_campfire():
    img = _new(False)
    wood = C(0.32, 0.20, 0.12); wood_d = wood.darkened(0.4); wood_l = wood.lightened(0.2)
    ash = C(0.22, 0.20, 0.20)

    _ellipse(img, 16, 27, 8.5, 2.4, C(INK.r, INK.g, INK.b, 0.32))
    _disc(img, 16, 25, 7.0, ash)
    _disc(img, 16, 25, 5.8, ash.darkened(0.15))

    _trapezoid(img, 16, 22, 26, 1.0, 6.5, wood_d); _trapezoid(img, 16, 22, 25, 0.6, 5.8, wood)
    _line(img, 9, 27, 23, 21, wood_d); _line(img, 9, 26, 23, 20, wood)
    _line(img, 23, 27, 9, 21, wood_d); _line(img, 23, 26, 9, 20, wood)
    _px(img, 9, 27, wood_l); _px(img, 23, 27, wood_l)

    _glow(img, 16.0, 21.3, 6.0, EMBER, 0.6)
    _ellipse(img, 16, 22, 3.5, 2.2, EMBER.darkened(0.15))
    _tri_up(img, 16, 21, 3, 7, EMBER.darkened(0.1)); _tri_up(img, 16, 20, 2, 5, EMBER)
    _tri_up(img, 16, 18, 1, 4, GOLD_L)
    _px(img, 13, 22, EMBER_L); _px(img, 19, 21, EMBER_L)
    return img

def _gen_crate():
    img = _new(False)
    wood = _WOOD; wood_d = wood.darkened(0.4); wood_l = wood.lightened(0.18)
    iron = STEEL_D

    _ellipse(img, 16, 28, 8.0, 2.0, C(INK.r, INK.g, INK.b, 0.30))
    _rect(img, 7, 11, 18, 17, INK)
    _rect(img, 8, 12, 16, 15, wood_d)
    _rect(img, 8, 12, 16, 5, wood)
    _rect(img, 8, 12, 16, 1, wood_l)

    for sx in (12, 16, 20):
        _rect(img, sx, 13, 1, 13, wood_d)
    _line(img, 9, 13, 22, 25, iron); _line(img, 22, 13, 9, 25, iron)
    _rect(img, 7, 11, 18, 1, iron); _rect(img, 7, 26, 18, 1, iron)
    for cx in (8, 22):
        _px(img, cx, 11, STEEL_L); _px(img, cx, 26, STEEL_L)
    return img

def _gen_barrel():
    img = _new(False)
    wood = _WOOD; wood_d = wood.darkened(0.42); wood_l = wood.lightened(0.20)
    iron = STEEL_D

    _ellipse(img, 16, 28, 7.5, 2.0, C(INK.r, INK.g, INK.b, 0.30))
    _trapezoid_o(img, 16, 8, 26, 5.5, 7.0, wood_d)
    _trapezoid(img, 16, 9, 25, 4.7, 6.2, wood)
    _rect(img, 16, 9, 1, 16, wood_l)

    for sx in (11, 14, 19, 22):
        _line(img, sx, 9, sx, 25, wood_d)

    for hy in (12, 18, 23):
        _ellipse(img, 16, hy, 6.3, 1.3, iron)
        _px(img, 11, hy, STEEL_L)
    _ellipse(img, 16, 9, 4.7, 1.3, wood_l)
    return img

def _gen_signpost():
    img = _new(False)
    wood = _WOOD; wood_d = wood.darkened(0.42); wood_l = wood.lightened(0.20)

    _ellipse(img, 16, 29, 4.0, 1.4, C(INK.r, INK.g, INK.b, 0.30))
    _rect(img, 15, 13, 3, 17, wood_d); _rect(img, 15, 13, 2, 17, wood)
    _rect(img, 15, 13, 1, 13, wood_l)

    _rect(img, 7, 8, 19, 8, INK)
    _rect(img, 8, 9, 17, 6, wood_d)
    _rect(img, 8, 9, 17, 3, wood)
    _rect(img, 8, 9, 17, 1, wood_l)
    _rect(img, 11, 11, 8, 2, wood_d.darkened(0.25))
    _tri_right(img, 22, 12, 4, 3, wood_d.darkened(0.25))
    _px(img, 9, 10, INK); _px(img, 23, 10, INK)
    _px(img, 15, 13, INK)
    return img

def _gen_lantern_post():
    img = _new(False)
    iron = STEEL_D; iron_l = STEEL_L
    glass = C(1.0, 0.78, 0.35, 0.55)

    _ellipse(img, 16, 29, 3.5, 1.3, C(INK.r, INK.g, INK.b, 0.30))
    _rect(img, 15, 13, 2, 16, iron); _px(img, 15, 13, iron_l)
    _ellipse(img, 16, 13, 3.5, 1.3, iron)

    _glow(img, 16.0, 8.7, 7.0, EMBER, 0.55)
    _rect(img, 12, 6, 8, 7, INK)
    _rect(img, 13, 7, 6, 5, glass)
    _ellipse(img, 16, 9, 2.3, 2.6, GOLD_L)
    for lx in (13, 16, 19):
        _rect(img, lx, 6, 1, 7, iron)
    _rect(img, 12, 5, 8, 1, iron); _rect(img, 12, 13, 8, 1, iron)
    _tri_up(img, 16, 5, 4, 3, iron)
    _px(img, 16, 2, iron_l)
    return img

def _gen_fallen_log():
    img = _new(False)
    bark = C(0.30, 0.20, 0.13); bark_d = bark.darkened(0.42); bark_l = bark.lightened(0.20)
    wood_core = C(0.68, 0.50, 0.30); wood_core_d = wood_core.darkened(0.25)
    moss = C(0.40, 0.62, 0.30)

    _ellipse(img, 16, 27, 12.5, 2.8, C(INK.r, INK.g, INK.b, 0.34))

    _rect(img, 4, 14, 23, 11, INK)
    _rect(img, 5, 15, 21, 9, bark_d)
    _rect(img, 5, 15, 21, 4, bark)
    _rect(img, 5, 15, 21, 1, bark_l)
    _disc_o(img, 5, 19, 5.5, bark_d, INK); _disc(img, 5, 19, 4.6, bark)

    for sx in range(8, 26, 3):
        _rect(img, sx, 15, 1, 9, bark_d)

    _disc_o(img, 26, 19, 5.5, bark_d, INK)
    _disc(img, 26, 19, 4.6, wood_core_d)
    _disc(img, 26, 19, 3.4, wood_core)
    _disc(img, 26, 19, 2.1, wood_core_d)
    _disc(img, 26, 19, 0.9, wood_core.lightened(0.2))

    _rect(img, 10, 15, 3, 2, moss); _rect(img, 18, 16, 2, 2, moss.darkened(0.1))
    _px(img, 7, 16, bark_l); _px(img, 16, 16, bark_l)
    return img

def _gen_ruins_pillar():
    img = _new(False)
    stone = C(0.42, 0.40, 0.46); stone_d = stone.darkened(0.42); stone_l = stone.lightened(0.26)
    moss = C(0.40, 0.62, 0.30)

    _ellipse(img, 16, 28, 10.5, 2.6, C(INK.r, INK.g, INK.b, 0.34))

    _rect(img, 6, 21, 9, 7, stone_d); _rect(img, 7, 22, 7, 5, stone)
    _rect(img, 7, 22, 7, 1, stone_l)
    _rect(img, 16, 23, 10, 5, stone_d); _rect(img, 17, 24, 8, 3, stone)

    _trapezoid_o(img, 13, 6, 22, 4.3, 5.3, stone_d, INK)
    _trapezoid(img, 13, 7, 21, 3.4, 4.4, stone)
    _rect(img, 13, 7, 1, 13, stone_l)
    _line(img, 8, 6, 18, 10, INK); _line(img, 8, 7, 18, 11, stone_d)
    for cx in (10, 13, 16):
        _rect(img, cx, 10, 1, 10, stone_d)
    _rect(img, 8, 21, 2, 2, moss); _rect(img, 19, 24, 2, 2, moss.darkened(0.1))
    _px(img, 7, 22, stone_l)
    return img

# --- main ---------------------------------------------------------------------
def main():
    global ASSETS
    ASSETS = sys.argv[1] if len(sys.argv) > 1 else "assets"
    os.makedirs(ASSETS, exist_ok=True)
    _save(_gen_floor(), "floor"); _save(_gen_wall(), "wall"); _save(_gen_stairs(), "stairs")
    for k in ["aria","aria_back","aria_side","knight","mage","ranger",
              "gobelin","loup","squelette","orc","spectre","boss",
              "araignee","sanglier","chauvesouris","serpent","ours",
              "zombie","dullahan","liche","banshee","revenant",
              "brigand","gnoll","troll","kobold","cultiste",
              "elementaire_feu","golem","fee","drake","coffre","mimic",
              "roi_liche","seigneur_fantome","wyrm","araignee_mere","troll_ancestral",
              "paladin_dechu","sorciere","bourreau","oeil_neant","dieu_bete","ame","chaudron"]:
        _save(_gen_creature(k), k)
    _save(_gen_weapon(), "arme"); _save(_gen_armor(), "armure"); _save(_gen_relic(), "relique")
    _save(_gen_artifact(), "artifact"); _save(_gen_potion(), "potion")
    _save(_gen_node_combat(), "node_combat"); _save(_gen_node_boss(), "node_boss")
    _save(_gen_node_elite(), "node_elite"); _save(_gen_node_shop(), "node_shop")
    _save(_gen_node_event(), "node_event"); _save(_gen_node_rest(), "node_rest")
    for bm in BIOMES:
        i = bm["id"]
        _save(_gen_ground(bm["ground_a"], bm["ground_b"]), "%s_ground" % i)
        _save(_gen_tree(bm["trunk"], bm["leaf"], bm["tree_style"]), "%s_tree" % i)
        _save(_gen_rock(bm["rock"]), "%s_rock" % i)
        _save(_gen_water(bm["water"]), "%s_water" % i)
        for vi, dstyle in enumerate(bm["decor_styles"]):
            _save(_gen_decor(bm["decor"], dstyle), _biome_decor_name(i, vi))
    _save(_gen_road(), "road")
    _save(_gen_campfire(), "campfire"); _save(_gen_crate(), "crate")
    _save(_gen_barrel(), "barrel"); _save(_gen_signpost(), "signpost")
    _save(_gen_lantern_post(), "lantern_post")
    _save(_gen_fallen_log(), "fallen_log"); _save(_gen_ruins_pillar(), "ruins_pillar")
    # Structures de POI (une par biome, dressing rare avec coffre)
    _save(_gen_standing_stone(C(1.0, 0.83, 0.34)), "standing_stone")
    _save(_gen_forest_altar(C(0.94, 0.27, 0.36)), "forest_altar")
    _save(_gen_wagon_wheel(C(0.92, 0.88, 0.74)), "wagon_wheel")
    _save(_gen_ice_cairn(C(0.62, 0.90, 1.0)), "ice_cairn")
    _save(_gen_sunken_ruin(C(0.64, 0.86, 0.32)), "sunken_ruin")
    _save(_gen_abandoned_anvil(C(1.0, 0.58, 0.20)), "abandoned_anvil")
    print("=== ASSETS GENERATED ===", ASSETS)

# === Nouveaux monstres (Pass 1) ==============================================
def _fig_araignee(img):
    _ground_shadow(img)
    leg = POISON.darkened(0.5)
    for ey in (10, 13, 16):
        _line(img, 11, 19, 1, ey, leg); _line(img, 11, 20, 3, ey + 1, leg)
        _line(img, 21, 19, 31, ey, leg); _line(img, 21, 20, 29, ey + 1, leg)
    _disc_o(img, 16, 20, 6.7, POISON.darkened(0.45), INK)
    _disc(img, 16, 20, 5.3, POISON.darkened(0.12))
    _ellipse(img, 13, 17, 2.1, 1.6, POISON.lightened(0.22))
    _disc_o(img, 16, 12, 4.0, POISON.darkened(0.32), INK)
    _disc(img, 16, 12, 2.9, POISON.darkened(0.05))
    _glow_eyes(img, 16, 11, BLOOD, 3)

def _fig_sanglier(img):
    _ground_shadow(img)
    fur = C(0.50, 0.40, 0.34); fur_d = fur.darkened(0.42); fur_l = fur.lightened(0.20)
    hide_head = fur.darkened(0.18)

    # legs (stubby, dark, behind the body silhouette)
    _rect(img, 11, 24, 3, 4, fur_d); _rect(img, 21, 24, 3, 4, fur_d)
    _rect(img, 11, 27, 3, 1, INK_SOFT); _rect(img, 21, 27, 3, 1, INK_SOFT)

    # body: barrel-shaped, distinct from head via a neck shadow wedge
    _ellipse(img, 18, 20, 10.0, 6.2, fur_d)
    _ellipse(img, 18, 20, 8.7, 5.1, fur)
    _ellipse(img, 18, 23, 6.5, 2.2, fur.darkened(0.12))

    # bristled mane: a row of small spikes along the spine, not just thin lines
    for sx in range(11, 23, 2):
        _tri_up(img, sx, 15, 1, 3, fur_d)
    for sx in range(12, 22, 2):
        _tri_up(img, sx, 14, 1, 2, fur_l)

    # head, lowered, with its own outline so it reads as a separate mass
    _ellipse(img, 10, 18, 2.4, 2.0, fur_d)
    _disc_o(img, 6, 18, 4.6, hide_head.darkened(0.3), INK)
    _disc(img, 6, 18, 3.7, hide_head)
    _ellipse(img, 5, 16, 1.3, 1.0, fur_l)
    # snout block, flatter + wider so it reads as a boar snout
    _rect(img, 0, 17, 5, 4, hide_head.lightened(0.10))
    _px(img, 0, 18, INK); _px(img, 0, 19, INK)
    # tusks curling outward from the snout
    _tri_up(img, 2, 22, 1, 4, BONE); _tri_up(img, 6, 22, 1, 3, BONE)
    _px(img, 1, 18, BONE_D)
    # small ear
    _tri_up(img, 8, 14, 2, 3, fur_d); _px(img, 8, 12, fur_l)

    _glow(img, 5.3, 16.7, 1.6, EMBER, 0.7)
    _px(img, 5, 16, EMBER)

def _fig_chauvesouris(img):
    _ground_shadow(img)
    body = C(0.45, 0.30, 0.42)
    # ailes
    _trapezoid(img, 5, 11, 20, 0.7, 5.3, body.darkened(0.4))
    _trapezoid(img, 27, 11, 20, 0.7, 5.3, body.darkened(0.4))
    _line(img, 9, 12, 4, 9, body.darkened(0.2)); _line(img, 23, 12, 28, 9, body.darkened(0.2))
    _disc_o(img, 16, 16, 4.0, body.darkened(0.3), INK)
    _disc(img, 16, 16, 3.1, body)
    _tri_up(img, 13, 12, 1, 4, body.darkened(0.2)); _tri_up(img, 19, 12, 1, 4, body.darkened(0.2))
    _glow_eyes(img, 16, 15, BLOOD, 1)
    _px(img, 15, 19, BONE); _px(img, 17, 19, BONE)         # crocs

def _fig_serpent(img):
    _ground_shadow(img)
    sk = C(0.36, 0.62, 0.40); sk_d = sk.darkened(0.4)
    # corps en S
    for i in range(14):
        t = i / 13.0
        x = int(7 + 7 * abs(math.sin(t * math.pi * 1.5)))
        y = 20 - i
        _disc(img, x, y, 2.7, sk_d); _disc(img, x, y, 1.7, sk)
    _disc_o(img, 19, 9, 3.5, sk_d, INK); _disc(img, 19, 9, 2.5, sk)
    _glow_eyes(img, 19, 8, GOLD_L, 1)
    _line(img, 21, 11, 24, 12, BLOOD)                        # langue
    _px(img, 24, 12, BLOOD); _px(img, 25, 11, BLOOD)

def _fig_ours(img):
    _ground_shadow(img)
    fur = C(0.46, 0.36, 0.31); fur_d = fur.darkened(0.42)
    _trapezoid_o(img, 16, 13, 28, 6.7, 9.3, fur_d)
    _trapezoid(img, 16, 15, 27, 5.3, 7.3, fur)
    _rect(img, 11, 20, 11, 4, fur.lightened(0.12))
    _disc_o(img, 16, 9, 5.9, fur_d, INK); _disc(img, 16, 9, 4.8, fur)
    _disc(img, 8, 5, 2.1, fur_d); _disc(img, 24, 5, 2.1, fur_d)  # oreilles
    _disc(img, 8, 5, 1.3, fur); _disc(img, 24, 5, 1.3, fur)
    _ellipse(img, 16, 12, 2.4, 1.7, fur.lightened(0.2))    # museau
    _px(img, 16, 12, INK)
    _glow_eyes(img, 16, 8, EMBER, 3)
    _tri_up(img, 13, 21, 1, 4, BONE); _tri_up(img, 19, 21, 1, 4, BONE)  # griffes

def _fig_zombie(img):
    _ground_shadow(img)
    sk = C(0.48, 0.62, 0.40); sk_d = sk.darkened(0.4)
    _glow(img, 16.0, 17.3, 8.0, POISON, 0.22)                 # aura de maladie
    _trapezoid_o(img, 15, 15, 28, 3.7, 6.0, sk_d)
    _trapezoid(img, 15, 16, 27, 2.7, 4.7, sk)
    _rect(img, 12, 17, 7, 3, sk_d)                         # déchirures
    _rect(img, 20, 16, 4, 3, sk)                          # bras tendu
    _rect(img, 24, 16, 3, 5, sk_d)
    _disc_o(img, 15, 9, 4.8, sk_d, INK); _disc(img, 15, 9, 3.9, sk)
    _ellipse(img, 12, 7, 1.6, 1.3, sk.lightened(0.2))
    _px(img, 13, 9, INK); _rect(img, 16, 9, 3, 1, INK)    # yeux asymétriques
    _glow(img, 13.3, 9.3, 1.6, POISON, 0.6)
    _rect(img, 13, 13, 4, 1, INK)

def _fig_dullahan(img):
    _ground_shadow(img)
    _trapezoid_o(img, 16, 9, 28, 4.3, 8.0, STEEL_D)       # corps sans tête
    _trapezoid(img, 16, 11, 27, 3.2, 6.0, STEEL)
    _rect(img, 13, 12, 7, 7, STEEL_L)                      # plastron
    _rect(img, 15, 13, 1, 4, C(1, 1, 1, 0.5))
    _disc_o(img, 11, 8, 2.3, STEEL, STEEL_D); _disc_o(img, 21, 8, 2.3, STEEL, STEEL_D)
    _px(img, 16, 8, BLOOD); _rect(img, 15, 8, 4, 1, BLOOD_D)   # cou tranché
    # tête portée dans la main
    _glow(img, 25.3, 18.7, 4.0, ARCANE, 0.4)
    _disc_o(img, 25, 19, 3.5, STEEL_D, INK); _disc(img, 25, 19, 2.5, BONE)
    _glow_eyes(img, 25, 17, EMBER, 1)
    _rect(img, 5, 12, 1, 13, STEEL_L)                      # épée

def _fig_liche(img):
    _ground_shadow(img)
    _trapezoid_o(img, 16, 15, 28, 2.7, 8.0, ARCANE.darkened(0.5))
    _trapezoid(img, 16, 16, 27, 1.6, 6.1, ARCANE.darkened(0.25))
    _rect(img, 15, 19, 3, 8, ARCANE_L.darkened(0.1))
    _disc_o(img, 16, 11, 4.5, BONE_D, INK); _disc(img, 16, 9, 3.6, BONE)  # crâne
    _rect(img, 13, 9, 3, 3, INK); _rect(img, 17, 9, 3, 3, INK)
    _glow(img, 14.0, 10.0, 1.9, ARCANE_L, 0.7); _glow(img, 19.3, 10.0, 1.9, ARCANE_L, 0.7)
    _px(img, 13, 9, ARCANE_L); _px(img, 19, 9, ARCANE_L)
    # couronne
    _rect(img, 12, 5, 8, 1, GOLD); _tri_up(img, 12, 5, 1, 3, GOLD); _tri_up(img, 16, 5, 1, 3, GOLD); _tri_up(img, 20, 5, 1, 3, GOLD)
    # bâton à gemme
    _rect(img, 8, 9, 1, 17, GOLD_D)
    _glow(img, 8.0, 8.0, 3.5, ARCANE, 0.7); _disc_o(img, 8, 8, 2.4, ARCANE, INK); _px(img, 8, 7, ARCANE_L)

def _fig_banshee(img):
    _glow(img, 16.0, 13.3, 9.3, CYAN, 0.35)
    _disc_o(img, 16, 11, 5.6, CYAN.darkened(0.4), INK_SOFT)
    _disc(img, 16, 11, 4.5, CYAN.darkened(0.12))
    # chevelure flottante
    for sx in (7, 9, 15, 17): _line(img, sx, 11, sx + (3 if sx < 16 else -3), 24, CYAN.darkened(0.2))
    _trapezoid(img, 16, 15, 28, 4.7, 8.0, CYAN.darkened(0.18))
    for x in range(8, 25):
        cut = 28 - (x % 3)
        for y in range(cut, TILE): _px(img, x, y, C(0, 0, 0, 0))
    _ellipse(img, 16, 11, 3.2, 2.7, C(0.05, 0.08, 0.10))
    _glow_eyes(img, 16, 9, C(1, 1, 1), 3)
    _ellipse(img, 16, 15, 1.3, 2.1, C(0.9, 1, 1, 0.8))    # bouche hurlante
    _fade(img, 0.82)

def _fig_revenant(img):
    _ground_shadow(img)
    arm = C(0.30, 0.30, 0.38)
    _trapezoid_o(img, 16, 13, 28, 4.0, 7.3, arm.darkened(0.4))
    _trapezoid(img, 16, 15, 27, 2.9, 5.6, arm)
    _rect(img, 13, 17, 7, 4, arm.lightened(0.18))
    _disc_o(img, 16, 9, 5.1, arm.darkened(0.4), INK); _disc(img, 16, 9, 4.0, arm)
    _rect(img, 12, 9, 8, 1, INK)                           # fente du heaume
    _glow_eyes(img, 16, 9, BLOOD, 3)
    _tri_up(img, 16, 4, 1, 4, BLOOD)                      # cimier
    _rect(img, 24, 11, 1, 15, STEEL_L); _rect(img, 7, 11, 1, 15, STEEL_L)  # deux lames (miroir)

def _fig_brigand(img):
    _ground_shadow(img)
    cloth = C(0.40, 0.32, 0.26)
    _trapezoid_o(img, 16, 15, 28, 3.5, 7.3, cloth.darkened(0.4))
    _trapezoid(img, 16, 16, 27, 2.4, 5.6, cloth)
    _disc_o(img, 16, 9, 5.1, cloth.darkened(0.45), INK)   # capuche
    _ellipse(img, 16, 11, 3.2, 2.7, C(0.08, 0.07, 0.10))
    _glow_eyes(img, 16, 11, ARCANE_L, 1)                   # corrompu (magie noire)
    _rect(img, 21, 17, 1, 7, STEEL_L); _rect(img, 20, 23, 4, 1, GOLD)   # dague
    _glow(img, 16.0, 16.0, 4.0, ARCANE, 0.18)

def _fig_gnoll(img):
    _ground_shadow(img)
    fur = C(0.68, 0.58, 0.34); fur_d = fur.darkened(0.4)
    _trapezoid_o(img, 16, 15, 28, 3.5, 6.7, fur_d)
    _trapezoid(img, 16, 16, 27, 2.4, 5.1, fur)
    _rect(img, 12, 19, 8, 3, C(0.4, 0.3, 0.2))
    _disc_o(img, 16, 9, 4.8, fur_d, INK); _disc(img, 16, 9, 3.9, fur)
    _tri_up(img, 11, 7, 1, 4, fur_d); _tri_up(img, 21, 7, 1, 4, fur_d)  # oreilles
    _rect(img, 13, 11, 5, 3, fur.lightened(0.12))          # museau hyène
    _px(img, 13, 12, INK); _px(img, 17, 12, INK); _px(img, 15, 12, BONE)
    _glow_eyes(img, 16, 9, GOLD_L, 1)
    _rect(img, 23, 13, 1, 11, STEEL_L)                     # arme

def _fig_troll(img):
    _ground_shadow(img)
    sk = C(0.45, 0.60, 0.45); sk_d = sk.darkened(0.42)
    _trapezoid_o(img, 15, 12, 28, 7.3, 10.0, sk_d)
    _trapezoid(img, 15, 13, 27, 6.0, 8.0, sk)
    _rect(img, 9, 19, 12, 4, sk.lightened(0.12))
    for rp in ((8, 16), (13, 13), (15, 18)):              # runes gravées
        _glow(img, rp[0], rp[1], 2.1, CYAN, 0.5); _px(img, rp[0], rp[1], CYAN_L)
    _disc_o(img, 15, 9, 5.6, sk_d, INK); _disc(img, 15, 9, 4.5, sk)
    _rect(img, 9, 11, 12, 1, INK)                           # arcade lourde
    _glow_eyes(img, 15, 11, EMBER, 3)
    _tri_up(img, 12, 16, 1, 4, BONE); _tri_up(img, 17, 16, 1, 4, BONE)

def _fig_kobold(img):
    _ground_shadow(img)
    sk = C(0.80, 0.50, 0.35); sk_d = sk.darkened(0.4)
    _trapezoid_o(img, 16, 19, 28, 3.2, 5.1, sk_d)
    _trapezoid(img, 16, 20, 27, 2.1, 3.7, sk)
    _disc_o(img, 16, 13, 4.3, sk_d, INK); _disc(img, 16, 13, 3.3, sk)
    _rect(img, 15, 15, 5, 3, sk.lightened(0.1))           # museau lézard
    _tri_up(img, 11, 12, 1, 5, sk_d); _tri_up(img, 21, 12, 1, 5, sk_d)   # oreilles
    _glow_eyes(img, 16, 12, GOLD_L, 1)
    _rect(img, 23, 16, 1, 7, STEEL_L)                     # dague
    _tri_up(img, 17, 12, 1, 4, BONE)

def _fig_cultiste(img):
    _ground_shadow(img)
    robe = C(0.45, 0.25, 0.34)
    _trapezoid_o(img, 16, 11, 29, 2.7, 8.7, robe.darkened(0.45))
    _trapezoid(img, 16, 12, 28, 1.9, 6.9, robe)
    _disc_o(img, 16, 9, 4.5, robe.darkened(0.5), INK)     # capuche pointue
    _tri_up(img, 16, 8, 3, 5, robe.darkened(0.35))
    _ellipse(img, 16, 11, 2.7, 2.3, C(0.06, 0.05, 0.08))
    _glow_eyes(img, 16, 11, BLOOD, 1)
    # sigille flottant
    _glow(img, 16.0, 22.7, 4.3, BLOOD, 0.45)
    _diamond(img, 16, 23, 3, BLOOD.darkened(0.2)); _px(img, 16, 23, GOLD_L)

def _fig_elementaire_feu(img):
    _glow(img, 16.0, 17.3, 12.0, EMBER, 0.5)
    # corps de flammes
    _tri_up(img, 16, 28, 9, 21, EMBER.darkened(0.3))
    _tri_up(img, 16, 28, 7, 19, EMBER)
    _tri_up(img, 12, 25, 3, 9, EMBER.darkened(0.1)); _tri_up(img, 20, 25, 3, 9, EMBER.darkened(0.1))
    _tri_up(img, 16, 25, 4, 15, GOLD)
    _tri_up(img, 16, 21, 3, 9, GOLD_L)
    _glow_eyes(img, 16, 16, C(1, 1, 1), 3)
    _px(img, 16, 7, GOLD_L)

def _fig_golem(img):
    _ground_shadow(img)
    st = C(0.58, 0.58, 0.64); st_d = st.darkened(0.4); st_l = st.lightened(0.16)
    _rect(img, 7, 12, 19, 17, INK)                         # contour bloc
    _rect(img, 8, 13, 16, 15, st_d)
    _rect(img, 9, 15, 13, 12, st)
    _rect(img, 9, 15, 13, 3, st_l)                        # haut éclairé
    _rect(img, 11, 8, 11, 5, st_d); _rect(img, 12, 8, 8, 4, st)   # tête bloc
    _rect(img, 4, 15, 3, 9, st_d); _rect(img, 25, 15, 3, 9, st_d)  # bras
    _glow(img, 13.3, 10.7, 1.9, ARCANE, 0.5); _glow(img, 18.7, 10.7, 1.9, ARCANE, 0.5)
    _px(img, 13, 11, ARCANE_L); _px(img, 19, 11, ARCANE_L)  # yeux runiques
    _line(img, 12, 17, 15, 23, st_d); _line(img, 19, 16, 17, 24, st_d)  # fissures

def _fig_fee(img):
    _glow(img, 16.0, 16.0, 9.3, ARCANE, 0.35)
    skin = SKIN; dress = ARCANE; dress_d = ARCANE.darkened(0.30)

    # wings: teardrop shape w/ vein lines instead of plain translucent blobs
    for wx, sign in ((9, -1), (23, 1)):
        _ellipse(img, wx, 13, 3.0, 4.6, C(ARCANE.r, ARCANE.g, ARCANE.b, 0.40))
        _ellipse(img, wx, 13, 1.8, 3.1, C(ARCANE_L.r, ARCANE_L.g, ARCANE_L.b, 0.55))
        _line(img, 16 + sign, 13, wx, 9, C(ARCANE_L.r, ARCANE_L.g, ARCANE_L.b, 0.6))
        _line(img, 16 + sign, 14, wx, 16, C(ARCANE_L.r, ARCANE_L.g, ARCANE_L.b, 0.6))

    # dress: a proper trapezoid silhouette w/ a waist accent, not just an outline
    _trapezoid_o(img, 16, 15, 24, 1.6, 3.2, dress_d)
    _trapezoid(img, 16, 16, 23, 1.1, 2.6, dress)
    _rect(img, 14, 17, 4, 1, ARCANE_L)             # ceinture

    # tête w/ silhouette de cheveux (pas juste un disque nu)
    _disc_o(img, 16, 11, 2.9, ROSE_D, INK)
    _ellipse(img, 16, 11, 2.0, 2.3, skin)
    _tri_up(img, 13, 9, 1, 3, ROSE_D); _tri_up(img, 19, 9, 1, 3, ROSE_D)
    _px(img, 15, 11, INK); _px(img, 17, 11, INK)
    _glow(img, 16.0, 10.7, 2.1, CYAN_L, 0.5)

    # baguette + traînée d'étincelles
    _line(img, 19, 18, 22, 21, GOLD_D); _px(img, 22, 21, GOLD_L)
    _px(img, 16, 5, GOLD_L); _px(img, 12, 8, CYAN_L); _px(img, 20, 8, CYAN_L)

def _fig_drake(img):
    _ground_shadow(img)
    sc = C(0.55, 0.40, 0.40); sc_d = sc.darkened(0.45); sc_l = sc.lightened(0.20)
    wing_mem = C(0.55, 0.30, 0.30, 0.75)

    # queue effilée avec pointe en fer de lance
    _line(img, 24, 23, 30, 27, sc_d); _line(img, 24, 22, 30, 26, sc)
    _tri_up(img, 30, 29, 2, 3, sc_d)

    # aile repliée (derrière le corps) - membrane entre les "doigts", pas un blob
    _trapezoid(img, 21, 12, 22, 1.0, 9.0, sc_d.darkened(0.1))
    for fx in (15, 19, 23, 27):
        _line(img, 21, 13, fx, 21, wing_mem)
    _line(img, 21, 12, 27, 14, sc_d)

    # pattes avec petites griffes
    _rect(img, 13, 24, 3, 4, sc_d); _rect(img, 19, 24, 3, 4, sc_d)
    _tri_up(img, 13, 28, 1, 2, BONE); _tri_up(img, 21, 28, 1, 2, BONE)

    # corps serpentiforme avec crête dorsale (évite la silhouette "animal endormi")
    _ellipse(img, 17, 21, 9.3, 5.3, sc_d); _ellipse(img, 17, 21, 8.0, 4.3, sc)
    _ellipse(img, 21, 19, 4.0, 3.2, sc_l)
    for rx in (12, 15, 18, 21): _tri_up(img, rx, 17, 1, 2, sc_d)

    # tête avec mâchoire + cornes, museau projeté vers l'avant
    _disc_o(img, 11, 12, 4.5, sc_d, INK); _disc(img, 11, 12, 3.6, sc)
    _rect(img, 4, 12, 7, 3, sc_l); _rect(img, 4, 14, 7, 1, sc_d)
    _tri_up(img, 12, 9, 1, 4, sc_d); _tri_up(img, 9, 9, 1, 3, sc_d)
    _glow_eyes(img, 11, 11, GOLD_L, 1)

    # souffle
    _glow(img, 2.7, 13.3, 3.5, EMBER, 0.6)
    _px(img, 3, 13, EMBER_L); _px(img, 1, 12, GOLD_L); _px(img, 1, 15, EMBER)

def _fig_coffre(img):
    _ground_shadow(img)
    wood = C(0.45, 0.32, 0.20); wood_d = wood.darkened(0.4)
    _rect(img, 7, 16, 19, 12, INK)                         # contour
    _rect(img, 8, 17, 16, 9, wood)
    _rect(img, 8, 11, 16, 7, wood_d)                       # couvercle bombé
    _rect(img, 8, 11, 16, 1, wood.lightened(0.15))
    _rect(img, 7, 16, 19, 1, GOLD_D)                      # ferrure
    _rect(img, 15, 15, 3, 5, GOLD)                        # serrure
    _px(img, 15, 16, GOLD_L); _px(img, 16, 17, INK)
    _px(img, 9, 12, wood.lightened(0.2))

def _fig_mimic(img):
    _fig_coffre(img)
    # gueule + dents + langue + yeux
    _rect(img, 8, 16, 16, 4, C(0.10, 0.04, 0.06))         # bouche ouverte
    for tx in range(6, 18, 2):
        _tri_up(img, tx + 1, 16, 1, 3, BONE)              # dents hautes
        _px(img, tx + 1, 19, BONE); _px(img, tx + 1, 17, BONE)
    _ellipse(img, 16, 20, 2.9, 1.6, BLOOD)                # langue
    _glow_eyes(img, 16, 12, EMBER, 4)

CREATURES.update({
    "araignee": _fig_araignee, "sanglier": _fig_sanglier, "chauvesouris": _fig_chauvesouris,
    "serpent": _fig_serpent, "ours": _fig_ours, "zombie": _fig_zombie,
    "dullahan": _fig_dullahan, "liche": _fig_liche, "banshee": _fig_banshee,
    "revenant": _fig_revenant, "brigand": _fig_brigand, "gnoll": _fig_gnoll,
    "troll": _fig_troll, "kobold": _fig_kobold, "cultiste": _fig_cultiste,
    "elementaire_feu": _fig_elementaire_feu, "golem": _fig_golem, "fee": _fig_fee,
    "drake": _fig_drake, "coffre": _fig_coffre, "mimic": _fig_mimic,
})

# === Boss (Pass 2) ===========================================================
def _fig_roi_liche(img):
    _glow(img, 16.0, 17.3, 12.7, ARCANE, 0.32)
    _rect(img, 5, 8, 21, 21, INK)
    _rect(img, 7, 9, 19, 19, C(0.28, 0.28, 0.40))
    _rect(img, 7, 7, 3, 7, BONE_D); _rect(img, 24, 7, 3, 7, BONE_D)
    _tri_up(img, 7, 8, 1, 4, BONE); _tri_up(img, 24, 8, 1, 4, BONE)
    _trapezoid_o(img, 16, 16, 28, 4.3, 8.0, ARCANE.darkened(0.42))
    _trapezoid(img, 16, 17, 27, 3.2, 6.4, ARCANE.darkened(0.16))
    _disc_o(img, 16, 12, 4.5, BONE_D, INK); _disc(img, 16, 11, 3.6, BONE)
    _rect(img, 13, 11, 3, 3, INK); _rect(img, 17, 11, 3, 3, INK)
    _glow(img, 14.0, 11.3, 1.7, ARCANE_L, 0.7); _glow(img, 19.3, 11.3, 1.7, ARCANE_L, 0.7)
    _px(img, 13, 11, ARCANE_L); _px(img, 19, 11, ARCANE_L)
    _rect(img, 12, 5, 8, 1, GOLD_D)
    for fx in (9, 12, 15):
        _glow(img, fx, 2.7, 2.1, ARCANE, 0.7)
        _tri_up(img, fx, 5, 1, 4, INK_SOFT); _px(img, fx, 1, ARCANE_L)

def _fig_seigneur_fantome(img):
    _glow(img, 16.0, 14.7, 12.0, CYAN, 0.4)
    _disc_o(img, 16, 11, 6.1, CYAN.darkened(0.4), INK_SOFT)
    _disc(img, 16, 11, 5.1, CYAN.darkened(0.12))
    _trapezoid(img, 16, 15, 29, 6.0, 9.3, CYAN.darkened(0.16))
    for x in range(7, 27):
        cut = 29 - (x % 4)
        for y in range(cut, TILE): _px(img, x, y, C(0, 0, 0, 0))
    _ellipse(img, 16, 11, 3.5, 2.9, C(0.05, 0.08, 0.10))
    _glow_eyes(img, 16, 9, C(1, 1, 1), 3)
    # âmes hurlantes en orbite
    for ax, ay in [(3, 6), (21, 6), (4, 14), (20, 14)]:
        _glow(img, ax, ay, 2.7, CYAN_L, 0.7); _disc(img, ax, ay, 1.3, CYAN_L)
    _fade(img, 0.85)

def _fig_wyrm(img):
    _ground_shadow(img)
    sc = C(0.55, 0.42, 0.40); sc_d = sc.darkened(0.45); sc_l = sc.lightened(0.18)

    # spirale ouverte (270°, rayon décroissant) plutôt qu'un anneau fermé en "donut"
    n = 26
    for i in range(n):
        t = i / float(n - 1)
        a = t * math.pi * 1.35 + math.pi * 0.25
        rad = 7.5 - 4.5 * t
        seg_r = 2.9 - 1.6 * t
        x = int(16 + rad * math.cos(a)); y = int(20 + rad * 0.72 * math.sin(a))
        _disc(img, x, y, seg_r + 0.8, sc_d)
    for i in range(n):
        t = i / float(n - 1)
        a = t * math.pi * 1.35 + math.pi * 0.25
        rad = 7.5 - 4.5 * t
        seg_r = 2.9 - 1.6 * t
        x = int(16 + rad * math.cos(a)); y = int(20 + rad * 0.72 * math.sin(a))
        _disc(img, x, y, seg_r, sc if i % 2 == 0 else sc_l.lerp(sc, 0.5))

    # tête à l'extrémité large de la spirale, avec cornes
    _disc_o(img, 22, 12, 4.5, sc_d, INK); _disc(img, 22, 12, 3.6, sc)
    _rect(img, 24, 11, 4, 3, sc_l)
    _tri_up(img, 20, 9, 1, 4, sc_d); _tri_up(img, 24, 9, 1, 3, sc_d)
    _glow_eyes(img, 22, 11, GOLD_L, 1)
    _glow(img, 22.0, 15.3, 2.3, EMBER, 0.5); _px(img, 22, 15, EMBER_L)

def _fig_araignee_mere(img):
    _ground_shadow(img)
    leg = POISON.darkened(0.5)
    for ey in (8, 11, 15, 18):
        _line(img, 9, 19, 1, ey, leg); _line(img, 23, 19, 31, ey, leg)
    _disc_o(img, 16, 20, 9.3, POISON.darkened(0.45), INK)
    _disc(img, 16, 20, 8.0, POISON.darkened(0.1))
    # œufs visibles (abdomen translucide)
    for ex, ey in [(10, 14), (14, 14), (12, 17), (9, 16), (15, 16)]:
        _disc(img, ex, ey, 1.6, C(0.85, 0.95, 0.7, 0.9)); _px(img, ex, ey, C(1, 1, 1))
    _disc_o(img, 16, 11, 4.8, POISON.darkened(0.3), INK); _disc(img, 16, 11, 3.9, POISON.darkened(0.02))
    _glow_eyes(img, 16, 9, BLOOD, 3); _glow_eyes(img, 16, 12, BLOOD, 1)

def _fig_troll_ancestral(img):
    _ground_shadow(img)
    sk = C(0.42, 0.58, 0.44); sk_d = sk.darkened(0.42)
    _trapezoid_o(img, 15, 9, 29, 8.7, 11.3, sk_d)
    _trapezoid(img, 15, 11, 28, 7.3, 9.3, sk)
    _rect(img, 8, 17, 15, 4, sk.lightened(0.1))
    # mousse + runes gravées
    for rp in [(7, 17), (10, 12), (14, 14), (16, 18), (12, 9)]:
        _glow(img, rp[0], rp[1], 2.4, CYAN, 0.55); _px(img, rp[0], rp[1], CYAN_L)
    for mp in [(8, 10), (15, 11)]:
        _disc(img, mp[0], mp[1], 1.7, POISON.darkened(0.2))
    _disc_o(img, 15, 8, 6.1, sk_d, INK); _disc(img, 15, 8, 5.1, sk)
    _rect(img, 8, 9, 13, 1, INK)
    _glow_eyes(img, 15, 8, EMBER, 4)
    _tri_up(img, 11, 15, 1, 5, BONE); _tri_up(img, 19, 15, 1, 5, BONE)

def _fig_paladin_dechu(img):
    _ground_shadow(img)
    st = C(0.78, 0.74, 0.58); st_d = st.darkened(0.4)
    # auréole noire brisée
    for i in range(0, 12):
        if i % 3 == 0: continue
        a = i / 12.0 * math.pi * 2.0
        _px(img, int(16 + 7 * math.cos(a)), int(7 + 4 * math.sin(a)), INK_SOFT)
    _glow(img, 16.0, 6.7, 4.0, ARCANE, 0.3)
    _trapezoid_o(img, 16, 13, 28, 5.3, 8.0, st_d)
    _trapezoid(img, 16, 15, 27, 4.3, 6.4, st)
    _rect(img, 12, 17, 8, 5, st.lightened(0.12))
    _line(img, 16, 16, 19, 25, st_d)        # fissure d'armure
    _disc_o(img, 16, 11, 4.5, st_d, INK); _disc(img, 16, 11, 3.6, st)
    _rect(img, 12, 11, 8, 1, INK)
    _glow_eyes(img, 16, 11, ARCANE_L, 3)
    _rect(img, 5, 12, 1, 13, STEEL_L); _rect(img, 4, 21, 4, 1, GOLD)   # épée brisée

def _fig_sorciere(img):
    _ground_shadow(img)
    robe = C(0.45, 0.30, 0.42)
    # cage d'os
    for bx in (5, 19):
        _rect(img, bx, 7, 1, 21, BONE_D)
    _rect(img, 7, 7, 20, 1, BONE_D); _rect(img, 7, 27, 20, 1, BONE_D)
    for bx in range(9, 25, 4): _rect(img, bx, 7, 1, 21, C(BONE_D.r, BONE_D.g, BONE_D.b, 0.5))
    _trapezoid_o(img, 16, 15, 25, 2.7, 5.6, robe.darkened(0.4))
    _trapezoid(img, 16, 16, 24, 1.9, 4.5, robe)
    _disc_o(img, 16, 11, 3.7, robe.darkened(0.45), INK)
    _ellipse(img, 16, 11, 2.4, 2.1, SKIN.darkened(0.15))
    _px(img, 15, 11, INK); _px(img, 17, 11, INK)
    _tri_up(img, 16, 8, 3, 5, robe.darkened(0.3))   # chapeau
    _glow(img, 16.0, 10.7, 1.9, POISON, 0.4)

def _fig_bourreau(img):
    _ground_shadow(img)
    cloth = C(0.30, 0.28, 0.32)
    _trapezoid_o(img, 15, 11, 28, 6.0, 8.7, cloth.darkened(0.4))
    _trapezoid(img, 15, 12, 27, 4.8, 6.9, cloth)
    _rect(img, 11, 16, 11, 5, cloth.lightened(0.12))
    _disc_o(img, 15, 9, 4.8, cloth.darkened(0.45), INK)
    _disc(img, 15, 9, 3.9, C(0.20, 0.18, 0.22))     # masque intégral
    _rect(img, 12, 9, 7, 1, INK)
    _glow_eyes(img, 15, 9, BLOOD, 3)
    # hache géante
    _rect(img, 24, 4, 1, 24, C(0.36, 0.25, 0.18))
    _rect(img, 20, 4, 7, 8, STEEL_D); _rect(img, 21, 5, 5, 5, STEEL)
    _rect(img, 21, 5, 5, 1, STEEL_L); _px(img, 20, 7, STEEL_L); _px(img, 20, 8, STEEL_L)

def _fig_oeil_neant(img):
    _glow(img, 16.0, 16.0, 13.3, ARCANE, 0.4)
    # tentacules
    for a in range(0, 360, 45):
        ar = a / 180.0 * math.pi
        ex = int(12 + 9 * math.cos(ar)); ey = int(12 + 9 * math.sin(ar))
        _line(img, 16, 16, ex, ey, ARCANE.darkened(0.25))
        _px(img, ex, ey, ARCANE)
    _disc_o(img, 16, 16, 8.0, ARCANE.darkened(0.4), INK)
    _disc(img, 16, 16, 6.7, C(0.85, 0.85, 0.95))    # sclère
    _disc(img, 16, 16, 3.5, BLOOD.darkened(0.1))    # iris
    _glow(img, 16.0, 16.0, 2.7, BLOOD, 0.5)
    _disc(img, 16, 16, 1.6, INK)                    # pupille
    _px(img, 13, 13, C(1, 1, 1))

def _fig_dieu_bete(img):
    _ground_shadow(img)
    body = C(0.62, 0.45, 0.30); body_d = body.darkened(0.4)
    _glow(img, 16.0, 16.0, 12.0, BLOOD, 0.25)
    # corps de lion
    _ellipse(img, 16, 21, 9.3, 6.0, body_d); _ellipse(img, 16, 21, 8.0, 4.8, body)
    _rect(img, 9, 25, 3, 4, body_d); _rect(img, 20, 25, 3, 4, body_d)
    # queue de serpent
    _line(img, 24, 23, 29, 16, POISON.darkened(0.2)); _disc(img, 29, 15, 1.9, POISON)
    _px(img, 29, 15, BLOOD)
    # tête de cerf
    _disc_o(img, 16, 11, 4.8, body_d, INK); _disc(img, 16, 11, 3.9, body)
    _rect(img, 15, 12, 4, 3, body.lightened(0.1))
    _glow_eyes(img, 16, 11, EMBER, 3)
    # ramures en cristal noir
    for sx in (8, 16):
        _line(img, sx, 8, sx - 3 if sx < 16 else sx + 3, 1, INK_SOFT)
        _line(img, sx, 5, sx - 5 if sx < 16 else sx + 5, 4, INK_SOFT)
        _glow(img, sx - 3 if sx < 16 else sx + 3, 1.3, 2.1, ARCANE, 0.6)
        _px(img, sx - 3 if sx < 16 else sx + 3, 1, ARCANE_L)

def _fig_ame(img):
    _glow(img, 16.0, 16.0, 9.3, CYAN, 0.6)
    _disc_o(img, 16, 15, 4.0, CYAN.darkened(0.3), INK_SOFT)
    _disc(img, 16, 15, 2.9, CYAN_L)
    _trapezoid(img, 16, 17, 25, 2.7, 4.0, CYAN.darkened(0.1))
    for x in range(11, 23):
        cut = 25 - (x % 2)
        for y in range(cut, TILE): _px(img, x, y, C(0, 0, 0, 0))
    _px(img, 15, 13, INK); _px(img, 17, 13, INK)
    _fade(img, 0.85)

def _fig_chaudron(img):
    _ground_shadow(img)
    iron = C(0.22, 0.22, 0.26)
    _disc_o(img, 16, 20, 8.7, iron.darkened(0.3), INK)
    _disc(img, 16, 20, 7.3, iron)
    _ellipse(img, 12, 17, 2.7, 1.9, iron.lightened(0.2))
    _ellipse(img, 16, 15, 8.0, 2.4, INK)            # ouverture
    _ellipse(img, 16, 15, 6.7, 1.7, POISON.darkened(0.2))   # breuvage
    _glow(img, 16.0, 13.3, 4.0, POISON, 0.5)
    for bx, by in [(10, 9), (13, 8), (12, 7)]:
        _disc(img, bx, by, 1.1, POISON.lightened(0.2))
    _rect(img, 8, 24, 16, 3, iron.darkened(0.4))    # pieds/feu
    _glow(img, 16.0, 25.3, 4.0, EMBER, 0.5)

CREATURES.update({
    "roi_liche": _fig_roi_liche, "seigneur_fantome": _fig_seigneur_fantome,
    "wyrm": _fig_wyrm, "araignee_mere": _fig_araignee_mere,
    "troll_ancestral": _fig_troll_ancestral, "paladin_dechu": _fig_paladin_dechu,
    "sorciere": _fig_sorciere, "bourreau": _fig_bourreau,
    "oeil_neant": _fig_oeil_neant, "dieu_bete": _fig_dieu_bete,
    "ame": _fig_ame, "chaudron": _fig_chaudron,
})

if __name__ == "__main__":
    main()
