#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""crates/_kit.py -- the shared drawing kit.  READ-ONLY BY CONTRACT.

THE ONLY MODULE A FAMILY FILE IMPORTS -- and, since the Beta 1.3 connectors,
the only one `links.py` imports either: the four `netstor_link_*` pieces are not
chest twins and live outside this package, but they pulse on the same triangle
wave, emit the same G-ramp, write the same metas and pass the same audits, so
they draw out of this kit and add nothing to it.  Everything below that says
"a family file" binds `links.py` too.

It is the single definition of every
constant the art is built from.  Nothing here was invented for the chest
twins: the palette, the Canvas, the G-ramp, the pulse tables, the sad-face
bitmap, the meta templates, the save helpers and the audits were MOVED out of
`make_art.py` unchanged, so there is exactly one copy of each and the three
shipped units regenerate byte-identically across the move.  `tools/regen_gate.py`
is the proof, not this sentence.

WHAT A FAMILY FILE MAY DO
  * read anything here;
  * call `crate_glow(kit, geom, f, params)` and `sad_face(kit, geom, f)`, the
    generic drawers most families use unchanged;
  * export `def glow(kit, geom, f) -> kit.Canvas` and/or
    `def offline(kit, geom, f) -> kit.Canvas` to override either one.

WHAT A FAMILY FILE MAY NOT DO
  * edit this file, `_geom.py`, `__init__.py`, `make_art.py` or any TOML;
  * emit a colour outside `{G1, G2, G3}` in a glow frame -- the runtime
    multiplies that strip by `top.image_blend` to carry the fill state, and a
    coloured source cannot be tinted (see the G-ramp block below);
  * light a glow pixel above `geom.lid_safe` -- the lid band is the only part
    of a chest whose silhouette moves, and ONE overlay strip has to sit
    correctly over the closed pose, the opened pose and every in-between.

The audits at the bottom enforce all three mechanically.
"""

import sys as _sys

try:
    from PIL import Image as _Image
except ImportError:  # pragma: no cover
    _sys.exit("Pillow is required:  pip install pillow")


__all__ = [
    # palette
    "TR", "BK", "W1", "W2", "W3", "W4", "M1", "M2", "M3", "M4",
    "C1", "C2", "C3", "C4", "WHITE", "PAPER", "DARKER",
    # the tintable glow ramp
    "G1", "G2", "G3", "TINTS", "TINT_FRAME",
    # canvas
    "Canvas",
    # the netstor set's own geometry + the shared strip timings
    "FRAME_W", "FRAME_H", "OFF_H", "OFF_V", "CENTRE", "BASELINE",
    "OPENING_DUR", "BOUNCE_DUR",
    "GLOW_LEN", "GLOW_DUR", "OFFLINE_LEN", "OFFLINE_DUR",
    # the pulse
    "PULSE", "GTONE", "SEAM_G", "rim",
    # the sad face
    "FACE_ROWS", "FACE_LEGEND", "FACE_W", "FACE_H", "FACE_BOB", "FACE_BLINK",
    "face_frame",
    # meta templates + writers
    "META_WORLD_STATIC", "META_WORLD_ANIM", "META_ICON", "META_CRAFT_ICON",
    "META_FONT", "META_SHAPE",
    "write_text", "save_strip", "save_poly", "shape_box", "world_shape_box",
    # audits
    "audit", "count_tones", "tint_image", "check_tint_ramp",
    "audit_glow_strip", "audit_offline_strip",
    # the generic crate drawers
    "GlowParams", "crate_glow", "sad_face", "face_origin_x",
    # a handle on this module, so `fam.glow(KIT, geom, f)` reads the same
    # everywhere
    "KIT",
]


# --------------------------------------------------------------------------
# Palette.  Wood + metal ramps are R8 Q6 verbatim (the vanilla basic-chest
# histogram).  The cyan ramp is ours; four tones, tuned to sit against the
# cool blue-grey metal without leaving the game's saturation range.
# --------------------------------------------------------------------------

TR = None                      # transparent (skip the pixel)
BK = (0x00, 0x00, 0x00, 255)   # linework            #000000

W1 = (0x4a, 0x22, 0x1b, 255)   # wood darkest        #4a221b
W2 = (0x67, 0x33, 0x26, 255)   # wood mid-dark       #673326
W3 = (0x90, 0x4d, 0x35, 255)   # wood main           #904d35
W4 = (0xaa, 0x5e, 0x37, 255)   # wood light          #aa5e37

M1 = (0x1f, 0x1e, 0x2c, 255)   # metal/slate darkest #1f1e2c
M2 = (0x3d, 0x3f, 0x53, 255)   # metal/slate dark    #3d3f53
M3 = (0x59, 0x5d, 0x71, 255)   # metal/slate mid     #595d71
M4 = (0x76, 0x7f, 0x96, 255)   # metal/slate light   #767f96

C1 = (0x14, 0x51, 0x5f, 255)   # cyan deep / recess  #14515f
C2 = (0x2e, 0x9f, 0xb2, 255)   # cyan mid            #2e9fb2
C3 = (0x5f, 0xdc, 0xe8, 255)   # cyan bright         #5fdce8
C4 = (0xc2, 0xfb, 0xff, 255)   # cyan pale core      #c2fbff

WHITE = (0xff, 0xff, 0xff, 255)

# The crafting menu's page colour.  #f9edf8 is 47279 of the 96k opaque pixels of
# `spr_ui_woodcrafting_backplate.png` in the game archive -- the crafting UI is
# PAPER, not the dark plate the rest of this file is authored against.  Never
# drawn into a sprite; used only to composite the sub-category icon onto its real
# background in the contact sheet, because "does the cyan seam still read?" is a
# question about paper and cannot be answered over the sheet's dark checker.
PAPER = (0xf9, 0xed, 0xf8, 255)

# one-step-darker map, used for CRT scanlines on the access panel screen
DARKER = {C4: C2, C3: C2, C2: C1, C1: M1, M1: M1}

# --------------------------------------------------------------------------
# v1.4 GLOW-ONLY luminance ramp.
#
# The `_glow` overlays are the one asset the runtime TINTS: `top.image_blend`
# carries the tri-state fill signal (green empty / yellow in use / red full on
# blocks; cyan on the heart and the panel).  A blend is a per-channel
# MULTIPLY, so a tintable strip must carry LUMINANCE ONLY -- the v1.3 cyan
# strips could not be tinted at all: C3 #5fdce8 x c_red = (95,0,0), a maroon
# at 37% of a real red, while c_yellow gave (95,220,0) and collapsed toward
# the c_lime result (V14-C 1.4, worked against these very bytes).  Near-white
# x tint IS the tint, so ONE strip serves all four states.
#
# THE TINTS ARE PASTEL AS OF BETA 1.0, and this table is generated from the
# SHIPPED values in `yads_glow_tint` (gml/network.gml) -- that function is the
# single source of truth and this file only mirrors it.  A channel at 0 erases
# that channel outright, so the old saturated primaries painted a neon nothing
# else in Mistria's palette resembles; lifting the zeroed channels to 130 keeps
# the same three hues and the same traffic-light reading in the game's softer
# range.  The cyan never moved -- it is the same make_color_rgb(64, 200, 214)
# the status popup's fill bar uses, so world and UI agree on the set's colour.
#
#   rung   art        x green        x yellow       x red          x cyan
#   G3   #ffffff   (130,255,130) (255,250,160) (255,130,130) ( 64,200,214)
#   G2   #d8d8d8   (110,216,110) (216,211,135) (216,110,110) ( 54,169,181)
#   G1   #a8a8a8   ( 85,168, 85) (168,164,105) (168, 85, 85) ( 42,131,140)
#
# so the 8-frame pulse survives every tint as the SAME three brightness rungs
# of one hue: in each tint's strongest channel the rungs land at 255/216/168
# (39 and 48 apart), and 214/181/140 for the cyan whose strongest channel is
# itself only 214 -- which is exactly what the v1.3 cyan art could not do.
# Expected read per state, over the closed pose:
#   empty  -> a soft mint rim/under-glow/seam; green dominant, R and B at half
#   in use -> the same shapes in a warm cream-yellow (R full, G near-full, B
#             lifted to 160 so it reads butter rather than acid)
#   full   -> a soft coral red, neither the old dark maroon nor a fire alarm
#   heart/panel -> the set's own cyan, unchanged since v1.3
#   untinted (c_white -- what the highlight path leaves for a frame indoors,
#            V14-C 1.2/1.3) -> a plain white rim: wrong VALUE, never wrong hue
#
# COLOUR-BLIND CAVEAT, recorded not fixed: the pastel pass costs about 37% of
# the green/yellow separation under a deuteranopia simulation and halves red's
# luminance escape hatch.  Owner-requested aesthetics; the fix if it ever needs
# one is a non-colour cue, not a return to primaries.  See CLAUDE.md.
#
# Deliberately SEPARATE constants from C1/C2/C3.  The bodies, the icons and
# the sad-face `_offline` strips are DRAWN, never tinted (their blend stays
# c_white), so they keep the family's cyan; only the glow generators may use
# G1/G2/G3, and `audit_glow_strip` enforces that the strips stay grey.
# --------------------------------------------------------------------------

G1 = (0xa8, 0xa8, 0xa8, 255)   # glow dim rung       #a8a8a8
G2 = (0xd8, 0xd8, 0xd8, 255)   # glow mid rung       #d8d8d8
G3 = (0xff, 0xff, 0xff, 255)   # glow bright rung    #ffffff

# The four `image_blend` values the runtime sets, plus the untinted fallback.
# KEEP IN LOCKSTEP WITH `yads_glow_tint` (gml/network.gml) -- the GML is the
# live value, this is a mirror for the contact sheet's tint row and for
# `check_tint_ramp` below.  They drifted once (the table still said
# c_lime/c_yellow/c_red long after Beta 1.0 went pastel) and the preview
# silently became a picture of a game that no longer exists.
TINTS = (
    ("green  empty",         (130, 255, 130)),
    ("yellow in use",        (255, 250, 160)),
    ("red    full",          (255, 130, 130)),
    ("cyan   heart/panel",   ( 64, 200, 214)),
    ("white  untinted",      (255, 255, 255)),
)

# Which glow frame the contact sheet tints.  Frame 2 is the only phase where
# all three rungs are on screen at once (PULSE[2] = 2 lights the rim at G3/G2/
# G1 by drop, the seam at G2, the spark at G3, and the out-of-phase diodes at
# G2), so one image per tint is enough to judge the whole ramp.
TINT_FRAME = 2

# --------------------------------------------------------------------------
# Tiny canvas helper
# --------------------------------------------------------------------------


class Canvas(object):
    def __init__(self, w, h):
        self.w = w
        self.h = h
        self.im = _Image.new("RGBA", (w, h), (0, 0, 0, 0))
        self.px = self.im.load()

    def set(self, x, y, c):
        if c is None:
            return
        if 0 <= x < self.w and 0 <= y < self.h:
            self.px[x, y] = c

    def get(self, x, y):
        if 0 <= x < self.w and 0 <= y < self.h:
            return self.px[x, y]
        return (0, 0, 0, 0)

    def hline(self, x0, x1, y, c):
        for x in range(x0, x1 + 1):
            self.set(x, y, c)

    def vline(self, x, y0, y1, c):
        for y in range(y0, y1 + 1):
            self.set(x, y, c)

    def rect(self, x0, y0, x1, y1, c):
        for y in range(y0, y1 + 1):
            self.hline(x0, x1, y, c)

    def blit_rows(self, x0, y0, rows, legend):
        """rows: list of strings; legend: char -> colour ('.' == skip)."""
        for dy, row in enumerate(rows):
            for dx, ch in enumerate(row):
                if ch == ".":
                    continue
                self.set(x0 + dx, y0 + dy, legend[ch])


# --------------------------------------------------------------------------
# THE NETSTOR SET'S OWN CANVAS -- the three AUTHORED units (heart, block,
# panel) and nothing else.  A crate family's canvas, pivot and baseline come
# from `_geom.py`, which measured them off the vanilla chest; a family module
# that reaches for FRAME_W is reaching for the wrong number.
# --------------------------------------------------------------------------

FRAME_W, FRAME_H = 40, 48
OFF_H, OFF_V = 16.0, 24.0      # sprite pivot, identical to a vanilla chest
CENTRE = 15.5                  # content is symmetric about x=15.5
BASELINE = 37                  # last opaque row -> plants like a vanilla chest

OPENING_DUR = 0.075            # R8 Q1 table
BOUNCE_DUR = 0.1               # R8 Q1 table

# The two overlay strips, shared by the three units AND by every crate family:
# the runtime swaps `sprite_index` between them on one renderer, so their
# frame counts and durations are a set-wide contract, not per-unit art.
GLOW_LEN = 8                   # v1.3: slowed from 0.1 (user: "very fast"); 1.6s full cycle
GLOW_DUR = 0.2
OFFLINE_LEN = 4                # v1.3 sad face; 1.4s full cycle -- deliberately
OFFLINE_DUR = 0.35             # slower than the glow, so "asleep" reads as calm


# --------------------------------------------------------------------------
# THE PULSE.  Three discrete luminance rungs plus pixels switching on and off
# -- never an alpha fade.  `image_alpha` is clobbered by the engine's
# highlight path (V12-A 2.4), so alpha is not ours to animate anyway.
# --------------------------------------------------------------------------

PULSE = (0, 1, 2, 3, 3, 2, 1, 0)     # triangle wave over the 8 frames
GTONE = (G1, G2, G3, G3)             # -> three distinct luminance rungs
SEAM_G = (G1, G1, G2, G2)


def rim(cv, x, y, p, drop=0):
    """One rim-light pixel.  `drop` biases a row down the pulse so the glow
    reads as pooling at the unit's foot and only creeping up at full pulse."""
    lvl = p - drop
    if lvl >= 0:
        cv.set(x, y, GTONE[lvl])


# --------------------------------------------------------------------------
# THE DISCONNECTED "SAD FACE".
#
# A thought bubble rather than a face painted on the unit: it reads at a
# glance from across a room, it does not fight the object's own linework, and
# it cannot be mistaken for damage to the furniture.  Three tones -- M4 fill,
# M3 shade, C1 for the tail -- plus black linework, binary alpha throughout.
# The tail is the only cyan in the sprite and sits at the DIMMEST rung of the
# ramp: the network light guttering, which reads "asleep" rather than the
# "error" a warm colour would imply.
#
# Like the glow, ONE strip has to sit correctly over every base pose, and the
# only band whose silhouette moves is the lid band at the top.  The glow
# solves that by staying low on the body; the face solves it by hovering ABOVE
# everything.  For a crate twin that is why the offline canvas grows by
# `geom.face_pad` rows -- a vanilla chest may reach row 4 (mimic, obsidian) and
# there is simply nowhere on its own canvas to put a 9-row bubble.
# --------------------------------------------------------------------------

# 10 wide x 9 tall, bubble body only; the eyes, the frown and the tail are
# drawn on top so the blink and the bob stay one-liners.
FACE_ROWS = (
    "...KKKK...",
    ".KKLLLLKK.",
    "KLLLLLLLDK",
    "KLLLLLLLDK",     # <- eyes row (cols 2 and 7)
    "KLLLLLLLDK",
    "KLLLLLLLDK",     # <- frown crown (cols 4,5)
    "KLLLLLLLDK",     # <- frown ends  (cols 3,6)
    ".KKLLDDKK.",
    "...KKKK...",
)
FACE_LEGEND = {"K": BK, "L": M4, "D": M3}

FACE_W = 10
FACE_H = 9
FACE_BOB = (0, -1, 0, 1)                     # the spec'd 1px hover cycle
FACE_BLINK = 3                               # blink on the DIPPED frame, so
                                             # the loop reads as one slow sigh
                                             # instead of a nervous twitch


def face_frame(kit, w, h, x0, y0, f):
    """One frame of the sad-face bubble on a `w` x `h` canvas.

    `y0` is the UN-bobbed top row; the bob is applied here so callers never
    have to remember it.  Only the tail is deliberately asymmetric, because a
    centred tail reads as a drip hanging off the bubble instead of as a
    pointer at the unit below."""
    cv = kit.Canvas(w, h)
    y0 = y0 + kit.FACE_BOB[f]
    cv.blit_rows(x0, y0, kit.FACE_ROWS, kit.FACE_LEGEND)

    # eyes -- two dark dots, squeezed shut into 2px lines on the blink frame.
    # Both states are symmetric about the bubble's x centre (col 4.5).
    if f == kit.FACE_BLINK:
        cv.hline(x0 + 2, x0 + 3, y0 + 3, kit.BK)
        cv.hline(x0 + 6, x0 + 7, y0 + 3, kit.BK)
    else:
        cv.set(x0 + 2, y0 + 3, kit.BK)
        cv.set(x0 + 7, y0 + 3, kit.BK)

    # frown -- an arch, crown high and ends dropping away.  Drawn a full row
    # clear of the bubble's bottom shoulder so the ends never merge into the
    # outline, which at this scale is the difference between a mouth and a
    # smudge.
    cv.hline(x0 + 4, x0 + 5, y0 + 5, kit.BK)
    cv.set(x0 + 3, y0 + 6, kit.BK)
    cv.set(x0 + 6, y0 + 6, kit.BK)

    # the thought-bubble tail, pointing down-left at the unit.  Both pixels
    # touch the bubble's rounded corner, so the strip stays orphan-free.
    cv.set(x0 + 0, y0 + 7, kit.C1)
    cv.set(x0 + 1, y0 + 8, kit.C1)
    return cv


# --------------------------------------------------------------------------
# meta.toml writers (R8 2.2 templates verbatim; meta_properties.id omitted
# on purpose -- MOMI mints it, TOMLInstaller.cs:61-67)
# --------------------------------------------------------------------------

META_WORLD_STATIC = (
    '[meta_properties]\n'
    'asset_kind = "Animation"\n'
    '\n'
    '[asset_properties]\n'
    'frame_size = [{w}, {h}]\n'
    'atlas = "Default"\n'
    '\n'
    '[asset_properties.offset]\n'
    'horizontal = {oh}\n'
    'vertical = {ov}\n'
)

META_WORLD_ANIM = (
    '[meta_properties]\n'
    'asset_kind = "Animation"\n'
    '\n'
    '[asset_properties]\n'
    'frame_size = [{w}, {h}]\n'
    'frame_len = {n}\n'
    'duration = {d}\n'
    'atlas = "Default"\n'
    '\n'
    '[asset_properties.offset]\n'
    'horizontal = {oh}\n'
    'vertical = {ov}\n'
)

META_ICON = (
    '[meta_properties]\n'
    'asset_kind = "Animation"\n'
    '\n'
    '[asset_properties]\n'
    'frame_size = [18, 18]\n'
    'atlas = "UI"\n'
    '\n'
    '[asset_properties.offset]\n'
    'horizontal = "Middle"\n'
    'vertical = "Middle"\n'
)

# The vanilla crafting category icons carry NO offset block whatsoever -- checked
# byte-for-byte against four of them.  Do not add one out of symmetry with
# META_ICON: the crafting menu places these by fiddle constant, and a "Middle"
# pivot would shift ours 7px off every vanilla neighbour in the same list.
META_CRAFT_ICON = (
    '[meta_properties]\n'
    'asset_kind = "Animation"\n'
    '\n'
    '[asset_properties]\n'
    'frame_size = [14, 14]\n'
    'atlas = "UI"\n'
)

# The sprite-font strip's meta is `spr_ui_hud_font_itemcount.meta.toml` from the
# archive with the frame count changed and the minted `id` dropped -- same key
# order, same `duration = 0.1` (a sprite font is never played: the draw loop
# picks the frame by hand with `draw_sprite_ext(sprite, index, ...)`, so the
# value is inert and is carried only so our meta and vanilla's are diffable),
# same `atlas = "UI"`, and NO offset block -- the draw loop adds
# `sprite_get_xoffset/yoffset` to the glyph position (`Anchor.gml:1096-1100`),
# so any pivot at all would shove every badge off its anchor.
META_FONT = (
    '[meta_properties]\n'
    'asset_kind = "Animation"\n'
    '\n'
    '[asset_properties]\n'
    'frame_size = [{w}, {h}]\n'
    'frame_len = {n}\n'
    'duration = 0.1\n'
    'atlas = "UI"\n'
)

# Every vanilla sprite ships a paired `poly_` bounds Shape under `shapes/`
# mirroring `animations/` (R1 2.E; R1 risk 9 -- "ship a poly for every
# sprite").  MOMI mints `id` and auto-links `required_assets` to the paired
# spr_ asset, so both are omitted here.  All world sprites of a vanilla chest
# share ONE box sized to the resting (closed) pose, not per-frame -- the glow
# overlay follows the same rule, and so does a crate twin's overlay pair (its
# box is the VANILLA body's closed bounds, because that is the object the
# overlay is drawn on).
META_SHAPE = (
    '[meta_properties]\n'
    'asset_kind = "Shape"\n'
    '\n'
    '[asset_properties]\n'
    'kind = "box"\n'
    'offset = [{ox}, {oy}]\n'
    'dimensions = [{w}, {h}]\n'
)


def write_text(path, text):
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(text)


def save_strip(directory, name, frames, duration, pivot):
    """frames: list of Canvas, all the same size.  Writes PNG + meta.

    `pivot` is REQUIRED and is written as-is.  It is not defaulted on purpose:
    the pivot is the only load-bearing number in an overlay's meta (the engine
    creates the top renderer at the body renderer's own x/y, so overlay pixel
    (px,py) lands on body pixel (bx,by) exactly when px - overlayPivot ==
    bx - bodyPivot), and a silently-inherited 16.0/24.0 would slide a crate
    family's glow across its chest with nothing to notice it."""
    n = len(frames)
    w, h = frames[0].w, frames[0].h
    for cv in frames:
        if (cv.w, cv.h) != (w, h):
            raise ValueError("%s: frame sizes disagree (%dx%d vs %dx%d)"
                             % (name, cv.w, cv.h, w, h))
    strip = _Image.new("RGBA", (w * n, h), (0, 0, 0, 0))
    for i, cv in enumerate(frames):
        strip.paste(cv.im, (i * w, 0))
    png = "%s/%s.png" % (directory, name)
    strip.save(png)
    oh, ov = pivot
    if n == 1:
        meta = META_WORLD_STATIC.format(w=w, h=h, oh=oh, ov=ov)
    else:
        meta = META_WORLD_ANIM.format(w=w, h=h, n=n, d=duration, oh=oh, ov=ov)
    write_text("%s/%s.meta.toml" % (directory, name), meta)
    return png


def save_poly(shape_dir, sprite_name, box):
    """The paired Shape for `spr_<x>` is `poly_<x>` -- MOMI pairs them purely
    by FILENAME, anywhere in the tree.  A sprite with no Shape throws
    "invalid asset id, required Shape" the first time something draws it."""
    path = "%s/poly_%s.meta.toml" % (shape_dir, sprite_name[4:])
    write_text(path, META_SHAPE.format(**box))
    return path


def shape_box(bbox, canvas, pivot):
    """Box hitbox from an opaque bounding box: grown 1px per side, clamped to
    the frame, expressed relative to the sprite pivot."""
    x0, y0, x1, y1 = bbox                     # x1/y1 exclusive, PIL's getbbox
    x0 = max(0, x0 - 1)
    y0 = max(0, y0 - 1)
    x1 = min(canvas[0], x1 + 1)
    y1 = min(canvas[1], y1 + 1)
    return dict(ox=x0 - int(pivot[0]), oy=y0 - int(pivot[1]),
                w=x1 - x0, h=y1 - y0)


def world_shape_box(closed_im, pivot):
    """Box hitbox for a unit's world sprites: the resting (closed) pose's
    opaque bounds, grown 1px per side and clamped to the frame, expressed
    relative to the sprite pivot."""
    return shape_box(closed_im.getbbox(), closed_im.size, pivot)


# --------------------------------------------------------------------------
# Sanity checks -- run on every generated canvas
# --------------------------------------------------------------------------


def audit(name, im, orphans=True, frame_w=FRAME_W):
    """Returns a list of problem strings (empty == clean).

    `orphans=False` for the glow overlays: isolated single pixels are the
    POINT there (diodes, the travelling spark), not a drawing mistake.
    `frame_w` splits a strip into frames so the orphan rule does not pair a
    pixel with its neighbour in the NEXT frame; it defaults to the netstor
    set's 40 and a crate family passes its own `geom.width`."""
    problems = []
    px = im.load()
    alphas = set()
    for y in range(im.height):
        for x in range(im.width):
            alphas.add(px[x, y][3])
    bad = alphas - {0, 255}
    if bad:
        problems.append("%s: non-binary alpha %s" % (name, sorted(bad)))
    if not orphans:
        return problems
    # orphan pixels: an opaque pixel with no opaque 4-neighbour inside its frame
    for fx in range(0, im.width, frame_w if im.width % frame_w == 0 else im.width):
        fw = frame_w if im.width % frame_w == 0 else im.width
        for y in range(im.height):
            for x in range(fx, min(fx + fw, im.width)):
                if px[x, y][3] == 0:
                    continue
                nb = 0
                for (nx, ny) in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
                    if fx <= nx < fx + fw and 0 <= ny < im.height and px[nx, ny][3]:
                        nb += 1
                if nb == 0:
                    problems.append("%s: orphan pixel at (%d,%d)" % (name, x, y))
    return problems


def tint_image(im, rgb):
    """Simulate one `image_blend` pass: per-channel multiply against `rgb`,
    alpha untouched (V14-C 1.4 -- the engine's own blend semantics).  Used
    for the contact sheet's tint row and for `check_tint_ramp` below; the game
    does this on the GPU, this is only how we prove the art survives it."""
    out = im.copy()
    px = out.load()
    for y in range(out.height):
        for x in range(out.width):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            px[x, y] = (r * rgb[0] // 255, g * rgb[1] // 255,
                        b * rgb[2] // 255, a)
    return out


def check_tint_ramp():
    """Prove the G-ramp is actually tintable, arithmetically, not by eye:
    the bright rung must come through as the tint itself, and the three rungs
    must stay far apart in the channel the tint leaves strongest.

    Both rules are written to survive the Beta 1.0 pastel palette.  The old
    pair could not: "a channel the tint kills must read 0" is VACUOUS once no
    channel is zero, and "separation in the first lit channel" picked a
    255-channel by luck under the saturated primaries and a half-lit one under
    the pastels, where it false-alarms.  Strongest-channel is what the rule
    always meant."""
    problems = []
    for label, rgb in TINTS:
        out = []
        for rung in (G3, G2, G1):
            out.append(tuple(rung[i] * rgb[i] // 255 for i in range(3)))
        # Hue fidelity, stated as the property that actually makes ONE strip
        # serve every state: near-white x tint IS the tint.  This binds G3 to
        # pure white -- dim the bright rung and every tint arrives desaturated
        # and wrong, which is the failure the v1.3 cyan art had.
        for i in range(3):
            if out[0][i] != rgb[i]:
                problems.append("tint %s: bright rung is not the tint in "
                                "channel %d (%d, want %d)"
                                % (label, i, out[0][i], rgb[i]))
        # Rung separation in the tint's strongest channel: the 8-frame pulse
        # has to stay legible as three distinct brightnesses after the multiply.
        strongest = max(range(3), key=lambda i: rgb[i])
        col = [o[strongest] for o in out]
        seps = (col[0] - col[1], col[1] - col[2])
        if min(seps) < 24:
            problems.append("tint %s: rungs collapse in channel %d, "
                            "separation %s" % (label, strongest, seps))
    return problems


def count_tones(im):
    """Distinct opaque colours in a strip -- used to prove the glow overlays
    really do pulse with a handful of discrete tones and no alpha ramp."""
    px = im.load()
    tones = set()
    for y in range(im.height):
        for x in range(im.width):
            if px[x, y][3]:
                tones.add(px[x, y])
    return tones


# --------------------------------------------------------------------------
# THE GENERALISED STRIP AUDITS.
#
# Through Beta 1.2 these were three hardcoded blocks in `make_art.main()`
# written for the heart / block / panel: <=3 glow tones, every tone grey and
# on the G-ramp, <=4 face tones, and `face_bot < body_top` where body_top was
# the minimum bbox top over the unit's own four base strips.  A crate family
# has no base strips of its own (its body is vanilla art named by string) and
# its body_top ranges from 4 (mimic, obsidian) to 14 (spring-festival), so the
# rules move here parameterised, and BOTH callers use the same code.
#
# One rule is NEW and is the reason the mist family cannot ship by accident:
# EVERY GLOW FRAME MUST CONTAIN AT LEAST ONE LIT PIXEL.  An all-transparent
# glow strip passes every test above -- binary alpha, zero tones, all of them
# grey, all of them on the ramp -- and would ship a family whose members carry
# no visible network marking at all.  `mist` has `glow_rows == 0`, so the
# generic drawer emits exactly that (art recon H4).
# --------------------------------------------------------------------------


def _frames_of(im, frame_w):
    return [im.crop((i * frame_w, 0, (i + 1) * frame_w, im.height))
            for i in range(im.width // frame_w)]


def audit_glow_strip(name, im, frame_w, lid_safe=None, y_shift=0):
    """Everything a `_glow` strip must satisfy, for a unit or a family.

    `lid_safe`, when given, is the first row (in BODY coordinates) at or below
    which a lit pixel is safe in every pose; `y_shift` is how far the overlay
    canvas is offset from the body's (0 for a glow strip, `face_pad` for an
    offline strip)."""
    problems = audit(name, im, orphans=False, frame_w=frame_w)

    tones = count_tones(im)
    if len(tones) > 3:
        problems.append("%s: %d tones, spec allows 2-3 luminance rungs"
                        % (name, len(tones)))
    # The tinted strip must be pure LUMINANCE.  Any colour left in it survives
    # the multiply and skews (or kills) every runtime tint -- this is precisely
    # how the v1.3 cyan strips failed (V14-C 1.4).
    for t in sorted(tones):
        if not (t[0] == t[1] == t[2]):
            problems.append("%s: non-grey glow pixel %s -- untintable"
                            % (name, str(t[:3])))
        elif t not in (G1, G2, G3):
            problems.append("%s: off-ramp glow tone %s" % (name, str(t[:3])))

    # NEW: an empty frame is a family with no visible network marking.
    for i, fr in enumerate(_frames_of(im, frame_w)):
        if fr.getbbox() is None:
            problems.append("%s: frame %d is entirely transparent -- this "
                            "family would ship with no network marking at all"
                            % (name, i))

    if lid_safe is not None:
        box = im.getbbox()
        if box is not None:
            top_body = box[1] - y_shift
            if top_body < lid_safe:
                problems.append("%s: lit pixel on body row %d, above "
                                "lid_safe %d -- the lid moves there, so the "
                                "overlay would float off the object"
                                % (name, top_body, lid_safe))
    return problems


def audit_offline_strip(name, im, frame_w, body_top, canvas_h=None):
    """Everything an `_offline` strip must satisfy.

    `body_top` is the topmost row the BODY may ever occupy, expressed in this
    strip's own canvas coordinates (for a crate that is `top_all + face_pad`,
    for a unit it is the min bbox top over its four base strips).  The face is
    deliberately ABOVE the object, so its lowest bobbed row must stay clear of
    that, and its highest bobbed row must stay on the canvas."""
    problems = audit(name, im, orphans=True, frame_w=frame_w)

    tones = count_tones(im)
    if len(tones) > 4:
        problems.append("%s: %d tones, spec allows 3 + black outline"
                        % (name, len(tones)))
    for t in sorted(tones):
        if t not in (BK, M4, M3, C1):
            problems.append("%s: off-palette face tone %s -- the bubble is "
                            "BK / M4 / M3 / C1" % (name, str(t[:3])))

    box = im.getbbox()
    if box is None:
        problems.append("%s: the whole strip is transparent" % name)
        return problems
    # the face must hover CLEAR of the object in every bobbed frame, over
    # every base pose -- the whole point of putting it above the sprite.
    face_bot = box[3] - 1
    if face_bot >= body_top:
        problems.append("%s: face reaches row %d but the body starts at "
                        "row %d" % (name, face_bot, body_top))

    # CLIPPING.  The bob only TRANSLATES the bubble, so every frame's opaque
    # bounds must be the same SIZE.  A frame drawn at y = -1 loses its top row
    # silently -- `Canvas.set` drops an out-of-range pixel and the strip still
    # audits clean on tones, alpha and clearance.  This is the one rule that
    # catches `face_pad` being one too small, which is exactly the arithmetic
    # the b13 recon got wrong.
    sizes = []
    for i, fr in enumerate(_frames_of(im, frame_w)):
        b = fr.getbbox()
        sizes.append((i, None if b is None else (b[2] - b[0], b[3] - b[1])))
    distinct = {s for _, s in sizes}
    if len(distinct) > 1:
        problems.append("%s: the bubble changes size between frames %s -- it "
                        "is being clipped by the canvas edge, so face_pad is "
                        "too small" % (name, sizes))

    if canvas_h is not None and im.height != canvas_h:
        problems.append("%s: canvas is %d rows, expected %d"
                        % (name, im.height, canvas_h))
    return problems


# --------------------------------------------------------------------------
# THE GENERIC CRATE DRAWERS.
#
# Most families use both of these unchanged and write ZERO lines of drawing
# code -- a MEMBERS table, a REP, and at most a `PARAMS` with two or three
# diodes on a latch or a hinge.  The rim path is machine-derived from the
# chest's own alpha mask (`geom.rim`), not hand-placed, which is what keeps
# 59 twins coherent: the MOTIF is identical on all of them (same pulse, same
# rungs, same dash rhythm, same tints) while the OBJECT stays the player's.
# --------------------------------------------------------------------------


class GlowParams(object):
    """Per-family tuning for `crate_glow`.  Every default is the shipped
    `netstor_block` glow's own value, ported row-for-row."""

    __slots__ = ("drop0", "drop1", "seam_up", "seam_inset", "diodes",
                 "under", "seam", "spark")

    def __init__(self, drop0=6, drop1=10, seam_up=2, seam_inset=4,
                 diodes=(), under=True, seam=True, spark=True):
        # `drop(y)` is 0 for the `drop0` rows nearest the foot, 1 for the next
        # `drop1 - drop0`, else 2 -- so the light pools at the ground and only
        # creeps up the body at full pulse.  glow_block lights rows 32..37 at
        # drop 0 and 28..31 at drop 1 against BASELINE 37, i.e. exactly (6, 10).
        self.drop0 = drop0
        self.drop1 = drop1
        # The seam sits `seam_up` rows above `base_row` (glow_block: row 35
        # against baseline 37) and spans `seam_inset` in from each end of that
        # row's own silhouette (glow_block: cols 8..23 of a 4..27 body).
        self.seam_up = seam_up
        self.seam_inset = seam_inset
        # (x, y) body-coordinate pixels lit HALF A CYCLE OUT OF PHASE with the
        # rim, so the object never goes fully dark.  Put 2-4 where the chest
        # has a natural fitting: a latch, a hinge, a corner plate.
        self.diodes = tuple(diodes)
        self.under = under
        self.seam = seam
        self.spark = spark


_DEFAULT_PARAMS = GlowParams()


def crate_glow(kit, geom, f, params=None):
    """The generic 8-frame connected glow: rim + dashed under-glow + a lit
    seam with a spark running along it + out-of-phase diodes.

    Everything is derived from `geom.rim`, which is the closed pose's own
    silhouette from `lid_safe` down to `base_row` -- so the light hugs the
    player's chest instead of replacing its linework."""
    p = params or _DEFAULT_PARAMS
    w, h = geom.canvas
    cv = kit.Canvas(w, h)
    lvl = kit.PULSE[f]
    base = geom.base_row
    rows = {y: (xl, xr) for (y, xl, xr) in geom.rim}

    # ---- rim up both silhouette edges, brightest at the ground -------------
    # base_row itself is left to the under-glow, exactly as glow_block does:
    # a solid line there plus a dash on top of it reads as a tray.
    for (y, xl, xr) in geom.rim:
        if y >= base:
            continue
        d = base - y
        drop = 0 if d < p.drop0 else (1 if d < p.drop1 else 2)
        kit.rim(cv, xl, y, lvl, drop)
        kit.rim(cv, xr, y, lvl, drop)

    # ---- dashed light spilling along the ground edge -----------------------
    # Dashed, not solid, so the object does not read as sitting in a tray; the
    # dash marches with the frame, which sells the "data is moving" idea for
    # one extra pixel of cost.
    if p.under and base in rows:
        xl, xr = rows[base]
        for x in range(xl, xr + 1):
            if (x + f) % 2 == 0:
                kit.rim(cv, x, base, lvl, 1)

    # ---- the lit seam, and a single bright spark travelling along it -------
    seam_y = base - p.seam_up
    if p.seam and seam_y in rows:
        xl, xr = rows[seam_y]
        x0, x1 = xl + p.seam_inset, xr - p.seam_inset
        span = x1 - x0 + 1
        if x0 <= x1:
            cv.hline(x0, x1, seam_y, kit.SEAM_G[lvl])
            # The spark is 2px wide and must travel the WHOLE seam in the 8
            # frames, whatever the seam's length: `x0 + 2f` (the block's own
            # step) walks 14px, which is right for the block's 16px seam and
            # wrong for every other width -- on a 14px seam it steps off the
            # end and the last frame has no spark at all.  Spacing it across
            # the span instead reduces to exactly `x0 + 2f` when span == 16.
            if p.spark and span >= 4:
                sx = x0 + int(round(f * (span - 2) / float(kit.GLOW_LEN - 1)))
                cv.set(sx, seam_y, kit.G3)
                cv.set(sx + 1, seam_y, kit.G3)

    # ---- diodes, half a cycle out of phase ---------------------------------
    dp = kit.PULSE[(f + kit.GLOW_LEN // 2) % kit.GLOW_LEN]
    if dp >= 1:
        for (dx, dy) in p.diodes:
            cv.set(dx, dy, kit.GTONE[dp])
    return cv


def face_origin_x(kit, geom):
    """Where the bubble's left column goes.

    Centred on the sprite PIVOT, not on the canvas.  A chest's content is
    symmetric about `pivot - 0.5` (the netstor set's own CENTRE = 15.5 against
    a pivot of 16.0), and the canvas is padded around it asymmetrically -- the
    56-wide miners crate has pivot 24, the 32-wide cottage fridge has pivot 12.
    Centring on `(W - FACE_W) // 2` instead would sit the bubble 4px off the
    object on both of those."""
    return int(geom.pivot[0]) - kit.FACE_W // 2


def sad_face(kit, geom, f, x0=None, y0=None):
    """The generic 4-frame disconnected overlay.

    The canvas is `(W, H + face_pad)` and the pivot `(h, v + face_pad)`, both
    from `_geom`; the extra rows are added ABOVE the body, so an overlay pixel
    at row r sits on body row r - face_pad.  `geom.face_y0` anchors the bubble
    as low as it can go -- its lowest bobbed row one clear row above the body's
    highest -- which is the only placement that fits on every family, mimic
    and obsidian included (their chests reach row 4)."""
    w, h = geom.offline_canvas
    if x0 is None:
        x0 = face_origin_x(kit, geom)
    if y0 is None:
        y0 = geom.face_y0
    return face_frame(kit, w, h, x0, y0, f)


# A handle on this module, so `fam.glow(KIT, geom, f)` and `kit.crate_glow(
# kit, geom, f)` read the same in every caller.  `from crates._kit import *`
# brings it along.
KIT = _sys.modules[__name__]
