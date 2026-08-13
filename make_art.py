#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
make_art.py -- deterministic pixel-art generator for the YADS mod
(Fields of Mistria).  Produces every world sprite strip, every UI item icon,
every white outline silhouette, and the matching `.meta.toml` sidecars.

Everything here is authored against R8-sprites.md and against the vanilla
`basic_chest_v01` / `deluxe_storage_chest` PNGs decoded pixel-by-pixel:

  * canvas 40x48, sprite pivot (16.0, 24.0), object south.offset [16, 0]
    -> content is centred on the boundary between column 15 and 16 (x=15.5)
       and its baseline (last opaque row) sits at y=37, exactly like a vanilla
       chest, so our furniture plants on the tile identically.
  * frame strips are laid out left-to-right, PNG width = frame_w * frame_len.
  * 1px pure-black (#000000) linework, strictly binary alpha (0 or 255),
    no antialiasing, no gradient banding, limited curated palette.
  * light comes from the top-left: highlight band in the upper third, 1px
    cast shadow to the RIGHT of every raised element, darkest tone hugging
    the bottom / right inner corners.
  * the 2-frame `opening` strip is played FORWARD to open and BACKWARD to
    close (R8 Q1), so frame 0 must read as "just lifting" and frame 1 must be
    ~1px away from the static `opened` sprite.

v1.2 art pass -- the units are CRATES, not chests (user: "should not be
chests, more like some crates"):

  * netstor_block  -- a slatted wooden shipping crate: flat perspective top of
    boards, hard rail, slatted front carrying an X-brace, small metal corner
    plates and one cyan-lit seam.  `opened` slides the top boards backwards,
    stacking them above the back rim and exposing a dark interior with a cyan
    glint pooled on the cavity floor; `opening` is two in-betweens of that
    slide, so the reverse play reads as the boards sliding shut.
  * netstor_heart  -- a dark slate obelisk on a crate-style base, with a large
    inset cyan crystal.  Nothing hinges: `opening`/`opened` are the crystal
    IRISING brighter (a monotone 4-step brightness ramp), which is inherently
    reverse-play safe because playing it backwards is simply "dimming".
  * netstor_panel  -- the v1.1 terminal concept (it tested well) re-seated on
    the same crate base instead of the old metal plinth + legs.
  * `bounce` (played when the vanilla Throw input drops an item into a unit)
    keeps the vanilla squash rhythm: the crate settles 1px/2px/1px and bulges
    1px per side above its bottom three rows; the obelisk/terminal settle 1px
    with a drifting specular instead, because rigid slate does not squash.
  * NEW `glow` overlays -- 8 frames @ 0.2s, entirely transparent except a
    rim-light hugging the unit's silhouette plus a few pulsing diodes and a
    data spark running along the lit seam (drawn cyan through v1.3; recoloured
    near-white in v1.4, see below -- the geometry never changed).  These are
    rendered by an
    independent `obj_node_renderer_top` instance (V12-A §2.4/§2.7 Plan A),
    which is orthogonal to the chest lid state machine and is never re-written
    -- so the overlay must read correctly over BOTH the closed and the opened
    base pose.  It therefore stays LOW ON THE BODY and never touches the
    lid/slat band, which is the only region whose silhouette moves.
    Binary alpha is preserved: the pulse is three discrete tones plus
    pixels switching on and off, never an alpha fade (V12-A §2.4 also notes
    `image_alpha` is clobbered by the highlight path, so alpha is not ours to
    animate anyway).

v1.3 art pass:

  * NEW `offline` overlays -- 4 frames @ 0.35s, the DISCONNECTED counterpart of
    `glow`.  v1.2 expressed "not on a network" by hiding the overlay instance,
    which is indistinguishable from "the mod is not running"; v1.3 keeps that
    instance permanently visible and swaps `sprite_index` between the two
    strips instead, so a stranded unit says so out loud.  Same canvas, same
    pivot, same paired poly, so the swap is a one-word change at runtime.

v1.4 art pass -- the three `glow` strips become TINTABLE:

  * v1.4 adds a tri-state FILL signal on top of the connected/disconnected
    sprite swap: blocks tint green (empty) / yellow (in use) / red (full),
    the heart and the panel stay cyan, all four driven from ONE strip per
    unit via `top.image_blend` (V14-C §1.5's recommended split -- connectivity
    stays sprite-swap, fill rides the tint).  `image_blend` is a per-channel
    MULTIPLY, so the v1.3 cyan art was untintable: red came out a 37%-value
    maroon and yellow collapsed toward the green result (V14-C §1.4).
  * So the glow palette -- and ONLY the glow palette -- is regenerated as
    three near-white luminance rungs (G1/G2/G3 = #a8a8a8 / #d8d8d8 / #ffffff).
    Pure recolour: identical filenames, dimensions (320x48), frame counts (8),
    durations (0.2s), pivots, polys and per-frame pixel POSITIONS, so no meta
    and no runtime wiring moves.  The bodies, the icons and the `_offline`
    sad faces are drawn rather than tinted (their blend stays c_white) and
    keep the family's cyan -- untouched, byte for byte.
  * `art_preview.png` gains a per-unit tint-simulation row that multiplies a
    glow frame by each of the four runtime colours plus untinted white, and
    main() now fails the audit if a glow strip carries any non-grey pixel.

The two UI assets behind the value badges and the crafting tab:

  * NEW `spr_ui_crafting_category_icon_netstor` -- the 14x14 icon for the
    "Digital Storage" woodcrafting sub-category the mod appends to the
    vanilla "Functional" category.  Conventions (size, atlas, the ABSENCE of
    an offset block, the paired poly, the palette, the tree position) were
    sampled out of the shipped game archive rather than assumed; the evidence
    is in the CRAFTING SUB-CATEGORY ICON section below.
  * NEW `spr_ui_hud_font_netstor_count` -- a 15-frame 5x7 SPRITE FONT, plus the
    `[netstor_count]` fiddle table that measures it.  It is
    `spr_ui_hud_font_itemcount` transcribed pixel for pixel from the archive
    and extended with `k` and `m`, so the value badges can abbreviate ("1.2k",
    "9.9m") -- which item_count cannot express and, worse, cannot fail loudly
    at: the engine drops an unknown glyph without advancing and measures it as
    zero.  This file owns BOTH the strip and the advance table, on purpose;
    see THE SPRITE FONT below.  Every other sprite this file emits is
    byte-identical to v1.4.

Run:  python make_art.py [output_mod_dir]
"""

import os
import sys

try:
    from PIL import Image
except ImportError:  # pragma: no cover
    sys.exit("Pillow is required:  pip install pillow")

# --------------------------------------------------------------------------
# Output locations
#
# The mod tree this script writes into.  Resolution order:
#   1. explicit argv[1]
#   2. the FOM_MOD_DIR environment variable
#   3. a sibling `yads/` beside this file (the repo layout)
#   4. a local `yads/` scaffold, created on demand
# A copy of this file run from a scratch build directory must emit identical
# bytes into the SAME tree, which is what argv[1] and FOM_MOD_DIR are for.
# --------------------------------------------------------------------------

HERE = os.path.dirname(os.path.abspath(__file__)).replace("\\", "/")

if len(sys.argv) > 1:
    MOD = sys.argv[1].replace("\\", "/").rstrip("/")
elif os.environ.get("FOM_MOD_DIR"):
    MOD = os.environ["FOM_MOD_DIR"].replace("\\", "/").rstrip("/")
else:
    MOD = HERE + "/yads"

WORLD_DIR = MOD + "/animations/Placeables/Furniture/Netstor Set"
ICON_DIR = MOD + "/animations/Item Icons/Placeables/Furniture/Netstor Set"
WORLD_SHAPE_DIR = MOD + "/shapes/Placeables/Furniture/Netstor Set"
ICON_SHAPE_DIR = MOD + "/shapes/Item Icons/Placeables/Furniture/Netstor Set"

# The crafting sub-category icon mirrors VANILLA's tree position, not the
# mod's own "Netstor Set" branch: the `spr_ui_crafting_category_icon_*` family
# (`_all`, `_craftable`, `_misc`, `_sets`) sits at the root of
# `assets/animations/UI NEW/Crafting/` in the game archive, with its Shape under
# the matching `assets/shapes/UI NEW/Crafting/`.  MOMI itself does not care --
# `TOMLCollector.Collect` walks the whole mod and pairs `spr_`/`poly_` purely by
# FILENAME -- so this is only so the installed tree reads like the game's own.
CRAFT_ICON_DIR = MOD + "/animations/UI NEW/Crafting"
CRAFT_ICON_SHAPE_DIR = MOD + "/shapes/UI NEW/Crafting"

PREVIEW = HERE + "/art_preview.png"

# Optional, and only ever READ: the pristine game archive MOMI keeps beside the
# installed one.  Used by check_font_against_vanilla() to prove the cloned digit
# cells still match the shipped ones byte for byte.  Absent == that one check is
# skipped and says so; nothing else in this file touches the game folder.
# Override with FOM_ASSETS_ZIP.
GAME_ASSETS_ZIP = ("C:/Program Files (x86)/Steam/steamapps/common/"
                   "Fields of Mistria/assets.bak.zip")

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
# c_white), so they keep the family's cyan; only the glow generators below may
# use G1/G2/G3, and the audit in main() enforces that the strips stay grey.
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
        self.im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
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
# Shared geometry constants (canvas / pivot / baseline)
# --------------------------------------------------------------------------

FRAME_W, FRAME_H = 40, 48
OFF_H, OFF_V = 16.0, 24.0      # sprite pivot, identical to a vanilla chest
CENTRE = 15.5                  # content is symmetric about x=15.5
BASELINE = 37                  # last opaque row -> plants like a vanilla chest

OPENING_DUR = 0.075            # R8 Q1 table
BOUNCE_DUR = 0.1               # R8 Q1 table
GLOW_LEN = 8                   # v1.3: slowed from 0.1 (user: "very fast"); 1.6s full cycle
GLOW_DUR = 0.2
OFFLINE_LEN = 4                # v1.3 sad face; 1.4s full cycle -- deliberately
OFFLINE_DUR = 0.35             # slower than the glow, so "asleep" reads as calm

# 7 poses per unit; 4 of them are the shipped states, 3 are strip frames.
POSES = ("closed", "opening0", "opening1", "opened", "bounce0", "bounce1", "bounce2")

# How far the crate's top boards have slid back, per pose, counted in rows of
# exposed cavity.  frame 0 of `opening` is "just cracked", frame 1 is one row
# short of `opened` -- exactly the vanilla near-identical-last-frame rule that
# makes the reverse play read as closing.
CRATE_OPEN = {"closed": 0, "opening0": 1, "opening1": 3, "opened": 4,
              "bounce0": 4, "bounce1": 4, "bounce2": 4}
# ...and how high the slid-back boards stack above the crate's back rim.
CRATE_RAISE = {0: 0, 1: 0, 2: 1, 3: 1, 4: 2}


# --------------------------------------------------------------------------
# The crate.  One construction serves all three units: the block IS a crate,
# the heart and the panel sit on a short crate-style plinth built from the
# same boards, so the set reads as one family.
# --------------------------------------------------------------------------


class CrateGeom(object):
    """A slatted shipping crate.

    Vertical anatomy, top to bottom:  black back rim (`top_y`) / the boards of
    the top seen in perspective (`tf0`..`tf1`) / the hard black rail where the
    top meets the front (`rail_y`) / the slatted front (`ff0`..`ff1`, one tone
    per row in `planks`, with `seam_y` re-lit in cyan) / the black bottom edge
    at BASELINE.  `tf_seams` are the x columns where the top boards butt
    together (they run front-to-back, so their seams are vertical)."""

    def __init__(self, bx0, bx1, top_y, tf0, tf1, rail_y, ff0, ff1, seam_y,
                 topface, tf_seams, planks, brace, plate_h):
        self.bx0 = bx0
        self.bx1 = bx1
        self.top_y = top_y
        self.tf0 = tf0
        self.tf1 = tf1
        self.rail_y = rail_y
        self.ff0 = ff0
        self.ff1 = ff1
        self.seam_y = seam_y
        self.topface = topface        # one tone per top-face row
        self.tf_seams = tf_seams
        self.planks = planks          # one tone per front-face row
        self.brace = brace            # draw the X of raised boards?
        self.plate_h = plate_h        # metal corner plate height
        assert len(planks) == ff1 - ff0 + 1
        assert len(topface) == tf1 - tf0 + 1


# The storage block: a full-height crate.  24px wide (cols 4..27), centred on
# x=15.5, 21 rows tall (17..37) -- the same visual mass as a vanilla chest.
BLOCK_G = CrateGeom(
    bx0=4, bx1=27, top_y=17, tf0=18, tf1=22, rail_y=23, ff0=24, ff1=36,
    seam_y=35,
    topface=(W4, W4, W3, W3, W2),
    tf_seams=(8, 12, 19, 23),
    planks=(W4, W3, W2, W1, W4, W3, W2, W1, W4, W3, W2, W2, W2),
    brace=True, plate_h=3)

# The shared plinth under the heart's obelisk and the panel's terminal: the
# same crate, cut down to a 3-row top and a 5-row front.  No X-brace -- at this
# height it would just be noise -- but it keeps the corner plates and the
# cyan-lit seam so the family reads together.
BASE_G = CrateGeom(
    bx0=4, bx1=27, top_y=27, tf0=28, tf1=30, rail_y=31, ff0=32, ff1=36,
    seam_y=35,
    topface=(W4, W3, W2),
    tf_seams=(9, 22),
    planks=(W4, W3, W2, W2, W2),
    brace=False, plate_h=2)

# Cyan seam ramp, indexed by "how awake is this unit" (0..3).  Used by the
# heart's iris and the panel's boot sequence; the block stays at 1 always.
SEAM_RAMP = ((C1, C1), (C2, C3), (C2, C3), (C3, C4))


def crate_shell(cv, g, wide=0, op=0, raise_h=0, seam_level=1):
    """Draw one crate.

    `wide` (0/1) is the bounce bulge: every row at or above BASELINE-3 grows
    1px per side while the bottom three rows stay planted -- the vanilla bounce
    silhouette.  `op` is how many rows of the top have slid back and exposed
    the interior; `raise_h` is how high the slid-back boards stack above the
    back rim."""

    def X(y):
        if wide and y <= BASELINE - 3:
            return g.bx0 - 1, g.bx1 + 1
        return g.bx0, g.bx1

    # ---- the boards that have slid back, stacked above the back rim --------
    if raise_h > 0:
        sa, sb = X(g.top_y)
        sa, sb = sa + 3, sb - 3
        cv.hline(sa, sb, g.top_y - raise_h - 1, BK)
        for r in range(raise_h):
            y = g.top_y - raise_h + r
            cv.set(sa - 1, y, BK)
            cv.set(sb + 1, y, BK)
            cv.hline(sa, sb, y, W3 if r == 0 else W2)

    # ---- black back rim ----------------------------------------------------
    xa, xb = X(g.top_y)
    cv.hline(xa + 1, xb - 1, g.top_y, BK)

    # ---- the top: boards in perspective, receding into an open cavity ------
    slat_last = g.tf1 - op            # last row still covered by boards
    for y in range(g.tf0, g.tf1 + 1):
        xa, xb = X(y)
        cv.set(xa, y, BK)
        cv.set(xb, y, BK)
        if y <= slat_last:
            cv.hline(xa + 1, xb - 1, y, g.topface[y - g.tf0])
            cv.set(xb - 1, y, W2)     # right-hand board falls into shadow
        else:
            # 1px of lit inner wall either side, pitch black between
            cv.set(xa + 1, y, W1)
            cv.set(xb - 1, y, W1)
            cv.hline(xa + 2, xb - 2, y, BK)
    for sx in g.tf_seams:             # boards run front-to-back: vertical seams
        for y in range(g.tf0, slat_last + 1):
            cv.set(sx, y, W2)

    # ---- cyan glint pooled on the cavity floor -----------------------------
    if op >= 1:
        y = g.tf1
        xa, xb = X(y)
        cv.hline(xa + 2, xb - 2, y, M1)
        cv.hline(xa + 5, xb - 5, y, C1)
        cv.hline(xa + 8, xb - 8, y, C2)
        cv.set(15, y, C3)
        cv.set(16, y, C3)

    # ---- the hard rail where the top meets the front -----------------------
    xa, xb = X(g.rail_y)
    cv.hline(xa, xb, g.rail_y, BK)

    # ---- slatted front -----------------------------------------------------
    for i, y in enumerate(range(g.ff0, g.ff1 + 1)):
        xa, xb = X(y)
        cv.set(xa, y, BK)
        cv.set(xb, y, BK)
        cv.hline(xa + 1, xb - 1, y, g.planks[i])
        cv.set(xb - 1, y, W1)         # 1px shadow down the shadowed edge

    # ---- black bottom edge, inset 1px so the corners read as rounded -------
    xa, xb = X(BASELINE)
    cv.hline(xa + 1, xb - 1, BASELINE, BK)

    # ---- small metal corner plates -----------------------------------------
    ph = g.plate_h
    for (py0, py1) in ((g.ff0, g.ff0 + ph - 1), (g.ff1 - ph + 1, g.ff1)):
        for y in range(py0, py1 + 1):
            xa, xb = X(y)
            tone = M4 if y == py0 else (M1 if y == py1 else M3)
            for (px0, px1) in ((xa + 1, xa + 3), (xb - 3, xb - 1)):
                cv.hline(px0, px1, y, tone)
                cv.set(px1, y, M1)            # right edge in shadow
        xa, xb = X(py0)
        cv.set(xa + 2, py0 + ph - 1, M4)      # rivet highlights
        cv.set(xb - 2, py0 + ph - 1, M4)

    # ---- the cyan-lit seam, spanning the gap between the plates ------------
    xa, xb = X(g.seam_y)
    base_c, hi_c = SEAM_RAMP[seam_level]
    cv.hline(xa + 4, xb - 4, g.seam_y, base_c)
    cv.hline(xa + 4, xa + 8, g.seam_y, hi_c)  # light source is top-LEFT

    # ---- X-brace of raised boards nailed across the front ------------------
    if g.brace:
        n = g.ff1 - g.ff0
        span = (g.bx1 - 4) - (g.bx0 + 4)
        rays = []
        for i in range(n + 1):
            y = g.ff0 + i
            xa, xb = X(y)
            off = int(round(i * span / float(n)))
            rays.append((y, xa + 4 + off, xb - 4 - off, xa + 4, xb - 4))
        # shadow pass first, so a crossing never paints shadow over highlight
        for (y, ba, bb, lo, hi) in rays:
            for bx in (ba, bb):
                if lo <= bx + 2 <= hi:
                    cv.set(bx + 2, y, W1)
        for (y, ba, bb, lo, hi) in rays:
            for bx in (ba, bb):
                if lo <= bx <= hi:
                    cv.set(bx, y, W4)
                if lo <= bx + 1 <= hi:
                    cv.set(bx + 1, y, W3)


def block_frame(pose):
    """Render one 40x48 frame of the storage block (a plain crate)."""
    cv = Canvas(FRAME_W, FRAME_H)
    op = CRATE_OPEN[pose]
    raise_h = CRATE_RAISE[op]
    wide = 0
    if pose.startswith("bounce"):
        # 1px / 2px / 1px settle: the stacked boards squash back down into the
        # crate while its body bulges a pixel per side.
        dy = {"bounce0": 1, "bounce1": 2, "bounce2": 1}[pose]
        raise_h = max(0, raise_h - dy)
        wide = 1
    crate_shell(cv, BLOCK_G, wide=wide, op=op, raise_h=raise_h, seam_level=1)
    return cv


# --------------------------------------------------------------------------
# Storage heart -- a dark slate obelisk with a large inset crystal, standing
# on the crate plinth.  Nothing hinges; the "open" states are the crystal
# irising brighter, which reverse-plays as a dim-down and therefore satisfies
# the play-forward-to-open / play-backward-to-close contract for free.
# --------------------------------------------------------------------------

OBELISK_Y0 = 12
# half-width per row (content is symmetric about x=15.5, so a half of h spans
# columns 16-h .. 15+h).  Deliberately NOT a bell curve -- a two-step chamfer,
# then a dead-straight shaft, then two steps out into the foot, so the thing
# reads as a cut slate monolith rather than a dome or a hood.
OBELISK_HALF = (4, 5,
                6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6,
                7, 7,
                8, 8)
OBELISK_BOT = OBELISK_Y0 + len(OBELISK_HALF) - 1     # 30 -- sits on the plinth

# The inset crystal.  c = rim facet, b = body facet, a = inner facet,
# A = core; the iris ramp below only ever moves each zone UP the cyan ramp,
# never sideways, so the four poses form a strict brightness sequence.
# 6 wide inside a 12-wide shaft: two columns of slate survive either side of
# the socket ring, which is what keeps it reading as INSET rather than as a
# gem-shaped unit.
GEM = (
    "..cc..",
    ".cbbc.",
    "cbaabc",
    "cbAAbc",
    "cbAAbc",
    "cbAAbc",
    "cbaabc",
    ".cbbc.",
    "..cc..",
)
GEM_X, GEM_Y = 13, 17

GEM_RAMP = (
    {"c": C1, "b": C1, "a": C2, "A": C2},   # closed  -- banked, barely awake
    {"c": C1, "b": C2, "a": C2, "A": C3},   # opening frame 0
    {"c": C1, "b": C2, "a": C3, "A": C4},   # opening frame 1
    {"c": C2, "b": C3, "a": C4, "A": C4},   # opened  -- iris wide, core white
)
GROOVE_RAMP = (C1, C1, C2, C3)              # the two etched runes track the iris


def draw_gem(cv, x0, y0, level, glint):
    """Crystal plus the 1px black socket ring that seats it in the slate."""
    legend = GEM_RAMP[level]
    mask = set()
    for dy, row in enumerate(GEM):
        for dx, ch in enumerate(row):
            if ch != ".":
                mask.add((x0 + dx, y0 + dy))
    for (x, y) in sorted(mask):               # 8-connected halo, ring first
        for ny in (y - 1, y, y + 1):
            for nx in (x - 1, x, x + 1):
                if (nx, ny) not in mask:
                    cv.set(nx, ny, BK)
    cv.blit_rows(x0, y0, GEM, legend)
    # a single specular pixel; it drifts across the bounce frames, which is the
    # whole of the heart's "wobble" (rigid slate does not squash).
    cv.set(x0 + 1 + glint, y0 + 2, C4 if level >= 2 else C3)


def obelisk(cv, dy, level, glint):
    """The slate monolith.  `dy` settles it into the plinth by a pixel."""
    half0 = OBELISK_HALF[0]
    cv.hline(16 - half0, 15 + half0, OBELISK_Y0 + dy - 1, BK)
    for i, half in enumerate(OBELISK_HALF):
        y = OBELISK_Y0 + i + dy
        if y > OBELISK_BOT:
            break                              # the foot sinks into the plinth
        xa, xb = 16 - half, 15 + half
        cv.set(xa, y, BK)
        cv.set(xb, y, BK)
        cv.hline(xa + 1, xb - 1, y, M2)
        cv.set(xa + 1, y, M3)                  # lit edge, light from top-left
        cv.set(xb - 1, y, M1)                  # shadowed edge
    # two etched runes, one on the cap and one across the foot
    groove = GROOVE_RAMP[level]
    for (gy, gw) in ((14, 4), (28, 5)):
        y = gy + dy
        if y <= OBELISK_BOT:
            cv.hline(16 - gw, 15 + gw, y, groove)
    draw_gem(cv, GEM_X, GEM_Y + dy, level, glint)


HEART_LEVEL = {"closed": 0, "opening0": 1, "opening1": 2, "opened": 3,
               "bounce0": 3, "bounce1": 3, "bounce2": 3}


def heart_frame(pose):
    """Render one 40x48 frame of the storage heart."""
    cv = Canvas(FRAME_W, FRAME_H)
    level = HEART_LEVEL[pose]
    dy = {"bounce0": 1, "bounce1": 0, "bounce2": 1}.get(pose, 0)
    glint = {"bounce0": 0, "bounce1": 1, "bounce2": -1}.get(pose, 0)
    crate_shell(cv, BASE_G, seam_level=level)
    obelisk(cv, dy, level, glint)
    return cv


# --------------------------------------------------------------------------
# Access panel -- the v1.1 slate terminal (it tested well), re-seated on the
# crate plinth so it belongs to the same family.
# --------------------------------------------------------------------------

PANEL = dict(
    sx0=6, sx1=25,          # slab outline columns (20 wide, centred on 15.5)
    stop=13,                # slab black top edge
    sbot=27,                # slab black bottom edge -- rests on the plinth
    scr_x0=10, scr_x1=21,   # screen fill columns (12 wide, centred on 15.5)
    scr_y0=17, scr_y1=24,   # screen fill rows (8 tall -> every scan offset
                            # yields exactly two scanlines, so the drift loop
                            # never flickers between 1 and 2 lines)
)

SCREEN_RAMP = {
    #         base  dash  scanline  glare
    "dim":  (C1,    C1,   M1,       C2),   # asleep: near-uniform dark teal
    "warm": (C1,    C2,   M1,       C3),   # booting
    "lit":  (C2,    C3,   C1,       C4),   # live network listing
}

DASH_ROWS = ((1, 8), (3, 5), (5, 7))       # (row offset, width) "text lines"

PANEL_MOOD = {"closed": ("dim", 0), "opening0": ("warm", 1),
              "opening1": ("lit", 2), "opened": ("lit", 3),
              "bounce0": ("lit", 3), "bounce1": ("lit", 3),
              "bounce2": ("lit", 3)}


def draw_screen(cv, x0, y0, x1, y1, mood, scan_off):
    """A CRT face, built out of horizontal structure only so it reads as a
    data terminal rather than a smudge: flat base, three short bright 'text
    line' dashes, a 1px falloff on the right/bottom edge, 1px scanlines that
    drift between bounce frames, and a fixed 3px specular in the corner."""
    base, dash, line, glare = SCREEN_RAMP[mood]

    cv.rect(x0, y0, x1, y1, base)
    for (dy, dw) in DASH_ROWS:
        if y0 + dy <= y1:
            cv.hline(x0 + 1, min(x0 + dw, x1 - 1), y0 + dy, dash)
    # screen curvature falloff on the shadow side
    cv.vline(x1, y0, y1, DARKER[base])
    cv.hline(x0, x1, y1, DARKER[base])
    # scanlines sit on top of everything, like a real CRT
    for y in range(y0, y1 + 1):
        if (y - y0 - scan_off) % 4 == 0:
            cv.hline(x0, x1, y, line)
    # specular glare, always the same three pixels in the top-left corner
    cv.set(x0, y0, glare)
    cv.set(x0 + 1, y0, glare)
    cv.set(x0, y0 + 1, glare)


def panel_frame(pose):
    p = PANEL
    cv = Canvas(FRAME_W, FRAME_H)
    mood, seam_level = PANEL_MOOD[pose]
    # a rigid slate terminal does not squash like a wooden lid: it settles 1px
    # and its scanlines drift, which reads as "powered and humming".
    dy = {"bounce0": 0, "bounce1": 1, "bounce2": 0}.get(pose, 0)
    scan = {"bounce0": 1, "bounce1": 2, "bounce2": 3}.get(pose, 0)

    crate_shell(cv, BASE_G, seam_level=seam_level)

    x0, x1 = p["sx0"], p["sx1"]
    top, bot = p["stop"] + dy, p["sbot"] + dy

    # contact shadow the terminal casts onto the plinth's top boards
    cv.hline(x0, x1, BASE_G.tf0, W1)

    # ---- slab --------------------------------------------------------------
    cv.hline(x0 + 1, x1 - 1, top, BK)
    for y in range(top + 1, bot):
        cv.set(x0, y, BK)
        cv.set(x1, y, BK)
        cv.hline(x0 + 1, x1 - 1, y, M2)
    cv.hline(x0 + 1, x1 - 1, bot, BK)

    # bezel lighting: lit top + left edges, shadowed bottom + right edges
    cv.hline(x0 + 1, x1 - 1, top + 1, M3)
    cv.hline(x0 + 1, x0 + 6, top + 1, M4)
    cv.vline(x0 + 1, top + 1, bot - 1, M3)
    cv.vline(x1 - 1, top + 2, bot - 1, M1)
    cv.hline(x0 + 1, x1 - 1, bot - 1, M1)
    cv.set(x0 + 1, bot - 1, M2)
    # two small bolts, bottom corners of the bezel
    cv.set(x0 + 2, bot - 2, M4)
    cv.set(x1 - 2, bot - 2, M4)

    # ---- screen ------------------------------------------------------------
    sx0, sx1 = p["scr_x0"], p["scr_x1"]
    sy0, sy1 = p["scr_y0"] + dy, p["scr_y1"] + dy
    cv.rect(sx0 - 1, sy0 - 1, sx1 + 1, sy1 + 1, BK)   # black inset border
    draw_screen(cv, sx0, sy0, sx1, sy1, mood, scan)

    return cv


# --------------------------------------------------------------------------
# CONNECTED-state glow overlays (V12-A Plan A).
#
# These are drawn by a separate obj_node_renderer_top instance one depth step
# in front of the body, toggled with `visible`.  That instance is NEVER
# re-written by the engine, so ONE loop has to sit correctly on top of every
# base pose -- closed, opening, opened and bounce alike.  The only part of a
# unit whose silhouette moves is the lid/slat band at the top, so the glow
# lives strictly on the body: rim-light hugging the lower silhouette, an
# under-glow along the ground edge, the cyan seam re-lit, a data spark running
# along it, and a few diodes pulsing out of phase with the rim.
#
# Binary alpha throughout: the pulse is three discrete tones plus pixels
# switching on and off, never an alpha fade.
#
# v1.4: those three tones are the near-white LUMINANCE rungs G1/G2/G3, not the
# body's cyan C1/C2/C3 -- this strip is multiplied by `image_blend` at runtime
# to carry the fill state, and a coloured source cannot be tinted (see the
# G-ramp block in the palette section for the worked multiply table).  The
# geometry below is untouched by that swap: every rim / under-glow / seam /
# spark / diode pixel sits exactly where v1.3 put it, in the same frame, so
# the strips stay 8 x 40x48 @ 0.2s and every meta and runtime wire holds.
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


def under_glow(cv, g, f, p):
    """Dashed light spilling along the ground edge.  Dashed, not solid, so the
    unit does not read as sitting in a cyan tray; the dash marches with the
    frame, which sells the "data is moving" idea for one extra pixel of cost."""
    for x in range(g.bx0 + 1, g.bx1):
        if (x + f) % 2 == 0:
            rim(cv, x, BASELINE, p, 1)


def seam_run(cv, g, f, p):
    """The lit seam plus a single bright spark travelling along it."""
    x0, x1 = g.bx0 + 4, g.bx1 - 4
    cv.hline(x0, x1, g.seam_y, SEAM_G[p])
    sx = x0 + f * 2
    for x in (sx, sx + 1):
        if x <= x1:
            cv.set(x, g.seam_y, G3)


def plinth_glow(cv, f, p):
    """Rim + under-glow + running seam on the shared crate plinth."""
    g = BASE_G
    for y in range(g.ff0, g.ff1 + 1):
        rim(cv, g.bx0, y, p, 0)
        rim(cv, g.bx1, y, p, 0)
    under_glow(cv, g, f, p)
    seam_run(cv, g, f, p)


def glow_block(f):
    g = BLOCK_G
    cv = Canvas(FRAME_W, FRAME_H)
    p = PULSE[f]
    # rim up both body edges -- brightest at the ground, creeping upward with
    # the pulse, and stopping well below the sliding boards at row 23.
    for y in range(g.ff0, g.ff1 + 1):
        drop = 0 if y >= 32 else (1 if y >= 28 else 2)
        rim(cv, g.bx0, y, p, drop)
        rim(cv, g.bx1, y, p, drop)
    under_glow(cv, g, f, p)
    seam_run(cv, g, f, p)
    # diodes on the two upper corner plates + a pair between them, deliberately
    # half a cycle out of phase with the rim so the unit never goes fully dark.
    dp = PULSE[(f + GLOW_LEN // 2) % GLOW_LEN]
    if dp >= 1:
        for (dx, dy) in ((6, 25), (25, 25), (15, 25), (16, 25)):
            cv.set(dx, dy, GTONE[dp])
    return cv


def glow_heart(f):
    cv = Canvas(FRAME_W, FRAME_H)
    p = PULSE[f]
    # the obelisk's silhouette is identical in every pose (only the crystal
    # irises), so its rim is safe all the way up.
    for i, half in enumerate(OBELISK_HALF):
        y = OBELISK_Y0 + i
        drop = 0 if y >= 26 else (1 if y >= 19 else 2)
        rim(cv, 16 - half, y, p, drop)
        rim(cv, 15 + half, y, p, drop)
    plinth_glow(cv, f, p)
    # a charge climbing the monolith's outline, two rows per frame
    cy = OBELISK_BOT - f * 2
    i = cy - OBELISK_Y0
    if 0 <= i < len(OBELISK_HALF):
        cv.set(16 - OBELISK_HALF[i], cy, G3)
        cv.set(15 + OBELISK_HALF[i], cy, G3)
    dp = PULSE[(f + GLOW_LEN // 2) % GLOW_LEN]
    if dp >= 1:
        cv.hline(12, 19, 14, GTONE[dp])       # the cap rune
        cv.set(6, 33, GTONE[dp])              # plinth corner diodes
        cv.set(25, 33, GTONE[dp])
    return cv


def glow_panel(f):
    p = PANEL
    cv = Canvas(FRAME_W, FRAME_H)
    ph = PULSE[f]
    for y in range(p["stop"] + 1, p["sbot"]):
        drop = 0 if y >= 23 else (1 if y >= 18 else 2)
        rim(cv, p["sx0"], y, ph, drop)
        rim(cv, p["sx1"], y, ph, drop)
    plinth_glow(cv, f, ph)
    dp = PULSE[(f + GLOW_LEN // 2) % GLOW_LEN]
    if dp >= 1:
        for (dx, dy) in ((8, 25), (23, 25), (15, 26), (16, 26)):
            cv.set(dx, dy, GTONE[dp])
    return cv


GLOW = {"heart": glow_heart, "block": glow_block, "panel": glow_panel}
FRAMER = {"heart": heart_frame, "block": block_frame, "panel": panel_frame}


# --------------------------------------------------------------------------
# DISCONNECTED-state "sad face" overlays (v1.3).
#
# Drawn by the SAME obj_node_renderer_top instance as the glow, which the
# engine never re-writes for a chest (V12-A §2.4/§2.7), so both halves of the
# connected/disconnected pair are ours: the runtime swaps `sprite_index`
# between `_glow` and `_offline` and leaves `visible` alone.
#
# Like the glow, ONE strip has to sit correctly over every base pose, and the
# only band whose silhouette moves is the lid/slat band at the top.  The glow
# solves that by staying low on the body; the face solves it by hovering ABOVE
# everything -- the topmost opaque row of any pose in the set is 14 (the
# block's boards stacked back when `opened`), 13 for the panel's slab and 11
# for the heart's chamfered cap, so `FACE_Y` is picked per unit to keep the
# bubble's lowest bobbed row clear of that unit's highest row.
#
# A thought bubble rather than a face painted on the unit: it reads at a
# glance from across a room, it does not fight the crate's own linework, and
# it cannot be mistaken for damage to the furniture.  Three tones -- M4 fill,
# M3 shade, C1 for the tail -- plus black linework, binary alpha throughout.
# The tail is the only cyan in the sprite and sits at the DIMMEST rung of the
# ramp: the network light guttering, which reads "asleep" rather than the
# "error" a warm colour would imply.
# --------------------------------------------------------------------------

# 10 wide x 9 tall, bubble body only; the eyes, the frown and the tail are
# drawn on top so the blink and the bob stay one-liners.  Column 0..9 maps to
# canvas 11..20, i.e. still centred on x=15.5 like every other sprite here --
# only the tail is deliberately asymmetric, because a centred tail reads as a
# drip hanging off the bubble instead of as a pointer at the unit below.
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

FACE_X = 11                                  # 10 wide, centred on x=15.5
FACE_Y = {"heart": 1, "block": 2, "panel": 2}
FACE_BOB = (0, -1, 0, 1)                     # the spec'd 1px hover cycle
FACE_BLINK = 3                               # blink on the DIPPED frame, so
                                             # the loop reads as one slow sigh
                                             # instead of a nervous twitch


def offline_frame(unit, f):
    """Render one 40x48 frame of a unit's disconnected overlay."""
    cv = Canvas(FRAME_W, FRAME_H)
    x0 = FACE_X
    y0 = FACE_Y[unit] + FACE_BOB[f]
    cv.blit_rows(x0, y0, FACE_ROWS, FACE_LEGEND)

    # eyes -- two dark dots, squeezed shut into 2px lines on the blink frame.
    # Both states are symmetric about the bubble's x centre (col 4.5).
    if f == FACE_BLINK:
        cv.hline(x0 + 2, x0 + 3, y0 + 3, BK)
        cv.hline(x0 + 6, x0 + 7, y0 + 3, BK)
    else:
        cv.set(x0 + 2, y0 + 3, BK)
        cv.set(x0 + 7, y0 + 3, BK)

    # frown -- an arch, crown high and ends dropping away.  Drawn a full row
    # clear of the bubble's bottom shoulder so the ends never merge into the
    # outline, which at this scale is the difference between a mouth and a
    # smudge.
    cv.hline(x0 + 4, x0 + 5, y0 + 5, BK)
    cv.set(x0 + 3, y0 + 6, BK)
    cv.set(x0 + 6, y0 + 6, BK)

    # the thought-bubble tail, pointing down-left at the unit.  Both pixels
    # touch the bubble's rounded corner, so the strip stays orphan-free.
    cv.set(x0 + 0, y0 + 7, C1)
    cv.set(x0 + 1, y0 + 8, C1)
    return cv


def offline_heart(f):
    return offline_frame("heart", f)


def offline_block(f):
    return offline_frame("block", f)


def offline_panel(f):
    return offline_frame("panel", f)


OFFLINE = {"heart": offline_heart, "block": offline_block,
           "panel": offline_panel}


# --------------------------------------------------------------------------
# 18x18 item icons -- hand-authored miniatures of the same construction, NOT
# downscales.  Drawn procedurally for the same reason the world sprites are:
# every coordinate stays symmetric about the icon's x=8.5 centre line.
# --------------------------------------------------------------------------

ICON_W = 18


def icon_plinth(cv):
    """The crate plinth, shared by the heart and panel icons: rows 11..16."""
    cv.hline(2, 15, 11, BK)
    cv.set(1, 12, BK)
    cv.set(16, 12, BK)
    cv.hline(2, 15, 12, W4)                # top boards in perspective
    cv.set(5, 12, W2)
    cv.set(12, 12, W2)
    cv.set(15, 12, W2)
    cv.hline(1, 16, 13, BK)                # rail
    for y in (14, 15):
        cv.set(1, y, BK)
        cv.set(16, y, BK)
        cv.hline(2, 15, y, W3 if y == 14 else W2)
        cv.set(15, y, W1)
    cv.hline(4, 13, 15, C2)                # cyan-lit seam
    cv.hline(4, 6, 15, C3)
    cv.hline(2, 15, 16, BK)
    for x0 in (2, 13):                     # metal corner plates
        cv.hline(x0, x0 + 1, 14, M3)
        cv.set(x0 + 1, 14, M1)
        cv.hline(x0, x0 + 1, 15, M1)


def icon_block():
    """Storage block: the crate, X-braced, with its lit seam."""
    cv = Canvas(ICON_W, ICON_W)
    cv.hline(2, 15, 2, BK)                 # back rim
    for y in (3, 4):                       # top boards
        cv.set(1, y, BK)
        cv.set(16, y, BK)
        cv.hline(2, 15, y, W4 if y == 3 else W3)
        cv.set(15, y, W2)
        cv.set(5, y, W2)
        cv.set(12, y, W2)
    cv.hline(1, 16, 5, BK)                 # rail
    planks = {6: W4, 7: W3, 8: W1, 9: W4, 10: W3, 11: W1, 12: W4, 13: W3, 14: W2}
    for y, tone in planks.items():
        cv.set(1, y, BK)
        cv.set(16, y, BK)
        cv.hline(2, 15, y, tone)
        cv.set(15, y, W1)
    cv.hline(2, 15, 15, BK)                # bottom edge
    for (py0, py1) in ((6, 7), (12, 13)):  # corner plates
        for y in range(py0, py1 + 1):
            for x0 in (2, 13):
                cv.hline(x0, x0 + 1, y, M3 if y == py0 else M1)
                cv.set(x0 + 1, y, M1)
    cv.hline(4, 13, 14, C2)                # cyan-lit seam
    cv.hline(4, 6, 14, C3)
    for i in range(9):                     # X-brace
        y = 6 + i
        off = int(round(i * 11 / 8.0))
        for bx in (4 + off, 13 - off):
            cv.set(bx, y, W4)
    return cv


def icon_heart():
    """Storage heart: the obelisk and its crystal, on the crate plinth.

    Same proportions as the world sprite, scaled down: a two-step chamfer, a
    straight shaft two columns wider than the crystal socket, one flare."""
    cv = Canvas(ICON_W, ICON_W)
    icon_plinth(cv)
    cv.hline(5, 12, 0, BK)                 # chamfered cap
    prof = {1: 4, 2: 5, 3: 5, 4: 5, 5: 5, 6: 5, 7: 5, 8: 5, 9: 5, 10: 5,
            11: 6, 12: 6}
    for y, half in prof.items():
        xa, xb = 9 - half, 8 + half
        cv.set(xa, y, BK)
        cv.set(xb, y, BK)
        cv.hline(xa + 1, xb - 1, y, M2)
        cv.set(xa + 1, y, M3)
        cv.set(xb - 1, y, M1)
    cv.hline(6, 11, 2, C2)                 # etched rune
    gem = (".cc.", "cAAc", "cssc", "cssc", "cAAc", ".cc.")
    mask = set()
    for dy, row in enumerate(gem):
        for dx, ch in enumerate(row):
            if ch != ".":
                mask.add((7 + dx, 4 + dy))
    for (x, y) in sorted(mask):            # black socket ring, 8-connected
        for ny in (y - 1, y, y + 1):
            for nx in (x - 1, x, x + 1):
                if (nx, ny) not in mask:
                    cv.set(nx, ny, BK)
    cv.blit_rows(7, 4, gem, {"c": C2, "A": C3, "s": C4})
    return cv


def icon_panel():
    """Access panel: the slate terminal on the crate plinth."""
    cv = Canvas(ICON_W, ICON_W)
    icon_plinth(cv)
    cv.hline(4, 13, 1, BK)                 # slab
    for y in range(2, 10):
        cv.set(3, y, BK)
        cv.set(14, y, BK)
        cv.hline(4, 13, y, M2)
        cv.set(4, y, M3)
        cv.set(13, y, M1)
    cv.hline(4, 13, 2, M4)
    cv.hline(4, 13, 9, M1)
    cv.hline(3, 14, 10, BK)
    cv.rect(5, 3, 12, 8, BK)               # screen bezel
    cv.rect(6, 4, 11, 7, C2)
    cv.hline(6, 9, 5, C3)
    cv.hline(6, 11, 6, C1)
    cv.hline(6, 8, 7, C3)
    cv.set(6, 4, C4)
    cv.set(4, 9, M4)                       # bolts
    cv.set(13, 9, M4)
    return cv


def icon_remote():
    """Remote Access Panel: a handheld slate, screen up, broadcasting.

    The one item in the set with NO plinth, because it is the one item that is
    not a placeable -- it never stands on the ground, so it never gets the
    crate the other three are built on.  Read as "the panel, in your hand":
    the same slate ramp (M1..M4) and the same cyan screen (C1..C4) as
    `icon_panel`, at tablet proportions instead of terminal ones.

    The screen carries the signal motif -- a bright pale core with two arcs
    opening upward away from it, dimming outward (C4 core, C3 near arc, C2 far
    arc).  Both arcs are drawn as bracket shapes (a crest row plus two tails
    directly beneath its ends) rather than as diagonals, so every lit pixel is
    4-connected to the next; and the screen interior is FILLED with C1 first,
    so the whole motif sits on opaque ground and the orphan audit has nothing
    to find no matter how the arcs are re-cut.

    Symmetric about x = 8.5, like every other icon here.
    """
    cv = Canvas(ICON_W, ICON_W)

    # ---- the shell: rows 4..16, columns 3..14, corners cut ----------------
    cv.hline(4, 13, 4, BK)                 # top edge
    cv.hline(4, 13, 16, BK)                # bottom edge
    for y in range(5, 16):                 # side rails
        cv.set(3, y, BK)
        cv.set(14, y, BK)

    cv.hline(4, 13, 5, M4)                 # top bevel, lit
    cv.hline(4, 13, 6, M3)
    cv.hline(4, 13, 7, BK)                 # screen bezel, top
    cv.hline(4, 13, 14, BK)                # screen bezel, bottom

    cv.hline(4, 13, 15, M2)                # the grip below the screen
    cv.set(4, 15, M3)
    cv.set(13, 15, M1)
    cv.hline(8, 9, 15, M4)                 # its one button

    for y in range(8, 14):                 # screen bezel, sides
        cv.set(4, y, BK)
        cv.set(13, y, BK)

    # ---- the screen: C1 ground, then the broadcast motif on top ----------
    # Read bottom-up: a bright 2x2 core at rows 12/13 and two arcs opening away
    # from it, the near one at 10/11 and the far one at 8/9, each dimmer than
    # the last.  The core is square rather than a 2x1 dash so that it anchors
    # the motif as a SOURCE instead of reading as a third, shortest arc.
    cv.rect(5, 8, 12, 13, C1)
    cv.hline(6, 11, 8, C2)                 # far arc: crest...
    cv.set(5, 9, C2)                       # ...and its two tails
    cv.set(12, 9, C2)
    cv.hline(7, 10, 10, C3)                # near arc: crest...
    cv.set(6, 11, C3)                      # ...and its two tails
    cv.set(11, 11, C3)
    cv.rect(8, 12, 9, 13, C4)              # the source, brightest
    return cv


ICONS = {"heart": icon_heart, "block": icon_block, "panel": icon_panel,
         "remote": icon_remote}


def outline_canvas(icon):
    """Vanilla outline sprites are a solid #ffffff silhouette produced by a
    1px PLUS-shaped (4-connected) dilation of the icon's alpha -- verified
    pixel-exact against spr_ui_item_furniture_basic_chest_v01_outline."""
    cv = Canvas(ICON_W, ICON_W)
    for y in range(ICON_W):
        for x in range(ICON_W):
            if icon.get(x, y)[3] == 0:
                continue
            for (nx, ny) in ((x, y), (x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
                cv.set(nx, ny, WHITE)
    return cv


# --------------------------------------------------------------------------
# CRAFTING SUB-CATEGORY ICON -- 14x14 (v1.5).
#
# The mod appends one sub-category ("Digital Storage") to the vanilla
# woodcrafting "Functional" category.  `CraftingMenu.gml:1343-1366` resolves the
# fiddle entry's `icon` string as `try_string_to_asset(sub.icon) ?? spr_illegal_8`
# and the header draws it at `[category] icon_offset = [10, 4]`
# (`fiddle/ui/crafting/layout.toml`) -- so a misspelt name is LOUD (an 8x8
# "illegal" glyph, not a blank), and the MENU owns the placement, not the sprite.
#
# Every convention here was sampled out of the shipped archive, not assumed:
#
#   * 14 x 14, single frame, `atlas = "UI"`, and **no `[asset_properties.offset]`
#     block at all** -- read verbatim from `spr_ui_crafting_category_icon_sets`,
#     `…_misc`, `spr_ui_woodcrafting_category_icon_functional` and
#     `…_chest_and_storage`.  The mod's ITEM icons pivot "Middle"/"Middle"
#     (META_ICON below); a category icon must NOT, or it would land 7px up and
#     left of every vanilla neighbour in the same list.
#   * a paired `poly_`, `kind = "box"`, `offset = [0, 0]`, `dimensions = [14, 14]`
#     -- vanilla's own Shape for these icons, and mandatory: R1 risk 9, a sprite
#     with no Shape throws "invalid asset id, required Shape" when the menu builds.
#   * 1px pure-black silhouette outline, binary alpha, content INSET in the cell.
#     `_chest_and_storage` fills cols 1..12 / rows 2..11; that footprint is copied
#     exactly, so our row sits on the same optical baseline as the vanilla
#     "Chests & Storage" row it will be listed directly under.
#   * no new palette: `_chest_and_storage` is drawn from #673326 / #904d35 /
#     #aa5e37 / #3d3f53 / #595d71 / #1f1e2c -- W2 / W3 / W4 / M2 / M3 / M1 of the
#     ramp above, exactly.  The vanilla furniture icons and ours already agree.
#
# The page is PAPER (#f9edf8, see PAPER above).  Two consequences, deliberate:
#   - the crate keeps its full black outline and dark wood body, so it reads as a
#     silhouette on near-white the way every vanilla icon does;
#   - the seam is C2 with a C3 highlight -- the two MID rungs.  C4 #c2fbff sits
#     within a few percent of the paper's luminance and would simply vanish; C1
#     is the recess tone and reads as a dirt line.  The seam is the only thing
#     that says "network" at this size, so it takes the widest run in the sprite:
#     8 of the 12 body columns.
#
# The crate is the storage BLOCK miniaturised -- the 18x18 item icon's own
# construction with the front cut from nine plank rows to five, and the X-brace
# replaced by two vertical battens.  A 1px-slope X across 6 columns needs 6 rows;
# in the 4 rows available it collapses into a blob, while battens standing in the
# same columns as the top-board grooves (4 and 9) carry the crate's vertical
# framing straight down the front and survive at 1x.
# --------------------------------------------------------------------------

CRAFT_ICON_W = 14


def craft_category_icon():
    """The "Digital Storage" sub-category icon: the block's crate at 14x14."""
    cv = Canvas(CRAFT_ICON_W, CRAFT_ICON_W)

    cv.hline(2, 11, 2, BK)                     # black back rim
    for y, tone in ((3, W4), (4, W3)):         # the top boards, in perspective
        cv.set(1, y, BK)
        cv.set(12, y, BK)
        cv.hline(2, 11, y, tone)
        cv.set(11, y, W2)                      # right-hand board falls to shadow
        cv.set(4, y, W2)                       # boards run front-to-back, so
        cv.set(9, y, W2)                       # where they butt reads as a groove
    cv.hline(1, 12, 5, BK)                     # the hard rail, top meets front

    for i, tone in enumerate((W3, W2, W3, W2, W2)):
        y = 6 + i                              # slatted front, one tone per plank
        cv.set(1, y, BK)
        cv.set(12, y, BK)
        cv.hline(2, 11, y, tone)
        cv.set(11, y, W1)                      # 1px shadow down the shadowed edge
    cv.hline(2, 11, 11, BK)                    # bottom edge, inset 1px

    # Two raised battens nailed down the front, standing in the same columns as
    # the top grooves, each casting a 1px shadow to its RIGHT (light is top-left).
    # The right batten's shadow lands on the column that is already the crate's
    # shadow edge, which is why that side is 2px dark -- the crate's own shading,
    # not a stray pixel.
    for bx in (4, 9):
        for y in range(6, 10):
            cv.set(bx, y, W4)
            cv.set(bx + 1, y, W1)

    # small metal corner plates: lit row over shadowed row, right edge darkest.
    # One rung lighter than the 18x18 icon's plates (M2 where that uses M1 on the
    # lower row) -- against #f9edf8 paper four near-black pixels read as holes
    # punched in the crate rather than as metal.
    for x0 in (2, 10):
        cv.hline(x0, x0 + 1, 6, M3)
        cv.set(x0 + 1, 6, M1)
        cv.hline(x0, x0 + 1, 7, M2)
        cv.set(x0 + 1, 7, M1)

    # the cyan-lit seam, and its highlight on the lit side
    cv.hline(3, 10, 10, C2)
    cv.hline(3, 4, 10, C3)
    return cv


# --------------------------------------------------------------------------
# THE SPRITE FONT  --  spr_ui_hud_font_netstor_count
#
# WHY A WHOLE FONT EXISTS FOR TWO LETTERS.  The value badges want to abbreviate
# ("1.2k", "9.9m") and the vanilla font they were drawn in cannot spell it.
# `[item_count]` (`FID/fiddle/fonts/sprite_fonts.toml:187-202`) is
# `order = "0123456789./+"` -- thirteen glyphs, no letters -- and the sprite-font
# draw loop SKIPS a character it cannot find in `order` WITHOUT ADVANCING x_off
# (`GML/scripts/UI/Anchor/Anchor.gml:1090-1107`), while `sprite_font_width` scores
# the same character `?? 0` (`anchor_utils.gml:2533-2545`).  So "1.2k" would have
# drawn as "1.2" and MEASURED as "1.2": not a clipped number, a WRONG one,
# silently.  No other shipped sprite font has a `k` or an `m` either (the only
# letters in the whole of `sprite_fonts.toml` are currency/skill/player_level `x`,
# medium_2 `LVNIxУР`, price `S`, damage_numbers `p`).  Hence: clone the font.
#
# THE DIGITS ARE VANILLA'S, PIXEL FOR PIXEL.  `VANILLA_ITEMCOUNT_GLYPHS` below is
# a transcription of the thirteen 5x7 cells of
# `ZIP/assets/animations/UI NEW/Fonts/spr_ui_hud_font_itemcount.png` (65x7, three
# colours only: transparent, #000000, #ffffff).  It is embedded rather than read
# from the archive so this generator stays hermetic and deterministic; when the
# archive IS present, `check_font_against_vanilla()` re-reads it and fails the
# audit on any drift.  Do not "improve" a digit: a badge whose 7 disagrees with
# the 7 on every other panel in the game is a bug report.
#
# THE HOUSE STYLE, DERIVED FROM THOSE BYTES.  A glyph is a 3x5 WHITE core inside
# the 5x7 cell (cols 1-3, rows 1-5) wrapped in a #000000 outline that is exactly
# the core's 4-NEIGHBOUR dilation -- verified against all ten digits: `0`'s top
# row is `.ooo.`, not `ooooo`, so the corners are not outlined.  (`+` is the one
# vanilla cell drawn with an 8-neighbour outline; it is transcribed as drawn and
# not regularised.)  `k` and `m` are therefore authored as cores and outlined by
# `outline4()`, which is the rule, not a resemblance to it.
#
#   k -- full ascender height (rows 1-5), stem + notched arm, so it stands as
#        tall as the digits it follows.
#   m -- x-height (rows 2-5), two full stems and a 2-row middle stem.  The
#        short middle stem is what separates it from an `n` at three pixels
#        wide, and the x-height is what separates it from `k` at a glance.
#
# THE DECIMAL POINT MOVES ONE PIXEL LEFT, AND THAT IS THE WHOLE POINT.  Vanilla's
# `.` cell lights exactly ONE pixel, at cell column 2, and `characters."." = 2`.
# Glyphs are drawn left to right and later glyphs paint OVER earlier ones
# (`Anchor.gml:1094-1105`), so with an advance of 2 the next glyph's black outline
# column lands on cell column 2 -- on the dot itself.  In vanilla that never
# shows, because every string item_count is ever asked to draw is an integer
# (`CraftingMenu.gml:402/558`, `DragonshrineMenu.gml:340`, `GossipMenu.gml:74`).
# Ours are not: "1.2k" is the first item_count-family string in which `.` is
# followed by a digit, and drawn vanilla-faithfully it renders as `12k` -- again
# a wrong number, silently.  Two fixes were possible: advance 3 (costs a pixel on
# every decimal and pushes "9.9k" past the coin budget below), or move the lit
# pixel to column 1 and keep the advance at 2.  We take the second: the advance
# stays vanilla's, the cell keeps its exact shape and pixel count, and the dot
# lands dead centre of the 1px gap between the two digits.  `audit_font_strings()`
# is the gate that proves it and would have caught the vanilla layout.
# --------------------------------------------------------------------------

FONT_DIR = MOD + "/animations/UI NEW/Fonts"
FONT_SHAPE_DIR = MOD + "/shapes/UI NEW/Fonts"
FIDDLE_FONT_DIR = MOD + "/fiddle/fonts"
FONT_SPRITE = "spr_ui_hud_font_netstor_count"
FONT_TABLE = "netstor_count"
FONT_CELL_W, FONT_CELL_H = 5, 7

# `.` and `o` and `#` == transparent / #000000 / #ffffff, one string per row.
# Transcribed from the shipped PNG; see check_font_against_vanilla().
VANILLA_ITEMCOUNT_GLYPHS = {
    "0": (".ooo.", "o###o", "o#o#o", "o#o#o", "o#o#o", "o###o", ".ooo."),
    "1": ("..o..", ".o#o.", "o##o.", ".o#o.", ".o#o.", ".o#o.", "..o.."),
    "2": (".ooo.", "o###o", "ooo#o", "o###o", "o#ooo", "o###o", ".ooo."),
    "3": (".ooo.", "o###o", ".oo#o", ".o##o", ".oo#o", "o###o", ".ooo."),
    "4": (".o.o.", "o#o#o", "o#o#o", "o###o", ".oo#o", "..o#o", "...o."),
    "5": (".ooo.", "o###o", "o#ooo", "o###o", "ooo#o", "o###o", ".ooo."),
    "6": (".oooo", "o###o", "o#ooo", "o###o", "o#o#o", "o###o", ".ooo."),
    "7": (".ooo.", "o###o", ".oo#o", ".o#o.", ".o#o.", ".o#o.", "..o.."),
    "8": (".ooo.", "o###o", "o#o#o", "o###o", "o#o#o", "o###o", ".ooo."),
    "9": (".ooo.", "o###o", "o#o#o", "o###o", "ooo#o", "o###o", ".ooo."),
    ".": (".....", ".....", ".....", ".....", ".oo..", ".o#o.", "..oo."),
    "/": (".....", "..oo.", ".o#o.", ".o#o.", "o#o..", "o#o..", "oo..."),
    "+": (".....", ".ooo.", "oo#oo", "o###o", "oo#oo", ".ooo.", "....."),
}

FONT_LEGEND = {"o": BK, "#": WHITE}


def outline4(rows):
    """Wrap every '#' in its 4-neighbour black outline -- the vanilla rule."""
    g = [list(r) for r in rows]
    for y in range(FONT_CELL_H):
        for x in range(FONT_CELL_W):
            if g[y][x] != "#":
                continue
            for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
                if 0 <= nx < FONT_CELL_W and 0 <= ny < FONT_CELL_H \
                        and g[ny][nx] == ".":
                    g[ny][nx] = "o"
    return tuple("".join(r) for r in g)


def font_core(core_rows, top):
    """Place a 3-wide core at cols 1-3 starting at row `top`, in a 5x7 cell."""
    rows = [["."] * FONT_CELL_W for _ in range(FONT_CELL_H)]
    for dy, r in enumerate(core_rows):
        for dx, ch in enumerate(r):
            if ch == "#":
                rows[top + dy][1 + dx] = "#"
    return tuple("".join(r) for r in rows)


def shift_left(rows):
    return tuple(r[1:] + "." for r in rows)


# order == frame order: `index = string_pos(char, order) - 1` (Anchor.gml:1092).
# Vanilla's thirteen in vanilla's order, then ours appended -- so the strip is a
# strict superset of item_count and frames 0..12 mean what they mean in vanilla.
FONT_ORDER = "0123456789./+km"

FONT_GLYPHS = dict(VANILLA_ITEMCOUNT_GLYPHS)
FONT_GLYPHS["."] = shift_left(VANILLA_ITEMCOUNT_GLYPHS["."])
FONT_GLYPHS["k"] = outline4(font_core(("#..", "#.#", "##.", "#.#", "#.#"), 1))
FONT_GLYPHS["m"] = outline4(font_core(("###", "###", "#.#", "#.#"), 2))

# `characters.<c>` -- the per-glyph advance, i.e. how far x_off moves AFTER the
# cell is drawn.  Vanilla's thirteen verbatim (`0`-`9` = 4 except `1` = 3,
# `.` = 2, `/` = 3, `+` = 4); `k` and `m` take the digit advance because their
# cores are the digit's full 3px width.  Nothing here is a guess: an advance one
# too small eats the next glyph's outline, one too large opens a gap, and
# audit_font_strings() below measures both.
FONT_ADVANCE = {
    "0": 4, "1": 3, "2": 4, "3": 4, "4": 4,
    "5": 4, "6": 4, "7": 4, "8": 4, "9": 4,
    ".": 2, "/": 3, "+": 4, "k": 4, "m": 4,
}


def font_strip():
    """The 15-frame 5x7 strip, laid out left to right like every other strip."""
    cv = Canvas(FONT_CELL_W * len(FONT_ORDER), FONT_CELL_H)
    for i, ch in enumerate(FONT_ORDER):
        cv.blit_rows(i * FONT_CELL_W, 0, FONT_GLYPHS[ch], FONT_LEGEND)
    return cv


# --------------------------------------------------------------------------
# The renderer, reimplemented -- and the audit that rides on it
# --------------------------------------------------------------------------


def font_compose(text):
    """Exactly `Anchor.gml:1087-1107`: draw each cell at x_off, then advance.

    Returns (rows, width, placements) where `placements` is [(char, x_off), ...]
    in draw order.  A character absent from FONT_ORDER is skipped WITHOUT
    advancing, which is the engine's behaviour and the bug this font exists to
    make impossible."""
    width = sum(FONT_ADVANCE.get(c, 0) for c in text)
    span = width + FONT_CELL_W
    rows = [["."] * span for _ in range(FONT_CELL_H)]
    placements = []
    x_off = 0
    for ch in text:
        if ch not in FONT_ORDER:
            continue
        placements.append((ch, x_off))
        cell = FONT_GLYPHS[ch]
        for y in range(FONT_CELL_H):
            for x in range(FONT_CELL_W):
                if cell[y][x] != ".":
                    rows[y][x_off + x] = cell[y][x]
        x_off += FONT_ADVANCE[ch]
    return ["".join(r) for r in rows], width, placements


def abbrev_value(v):
    """The Python mirror of yads_abbrev_value (GML).

    Kept here so the art gate below is driven by the SAME strings the mod will
    actually ask the font to draw.  Floors, never rounds: a value badge may
    understate by less than one unit of its own suffix, never overstate."""
    if v < 0:
        v = 0
    if v < 1000:
        return str(v)
    if v < 10000:
        w, f = v // 1000, (v // 100) % 10
        return "%dk" % w if f == 0 else "%d.%dk" % (w, f)
    if v < 1000000:
        return "%dk" % (v // 1000)
    if v < 10000000:
        w, f = v // 1000000, (v // 100000) % 10
        return "%dm" % w if f == 0 else "%d.%dm" % (w, f)
    return "%dm" % (v // 1000000)


# Every boundary of abbrev_value, plus the widest string each branch can emit.
FONT_AUDIT_VALUES = [
    0, 1, 9, 10, 99, 100, 999,
    1000, 1001, 1099, 1100, 1234, 1999, 9900, 9999,
    10000, 10999, 99999, 123456, 999999,
    1000000, 1099999, 1234567, 9999999,
    10000000, 12345678, 999999999,
]


def audit_font_strings():
    """Two gates, both arithmetic, neither by eye.

    1. NOTHING THE FONT CAN BE ASKED TO DRAW LOSES A LIT PIXEL.  Composed left
       to right with later cells painting over earlier ones, every '#' of every
       placed glyph must still be '#' in the finished line.  This is the gate
       that rejects vanilla's `.` at advance 2 (its single lit pixel sits in the
       column the next glyph's outline lands on) and that would reject any
       future advance set off by one.
    2. EVERY CHARACTER IS RENDERABLE.  Any output of abbrev_value containing a
       character outside FONT_ORDER would be silently dropped by the engine and
       silently scored 0 by sprite_font_width -- a wrong number, not a clipped
       one."""
    problems = []
    for v in FONT_AUDIT_VALUES:
        text = abbrev_value(v)
        for ch in text:
            if ch not in FONT_ORDER:
                problems.append("font: abbrev(%d) = %r contains %r, which is "
                                "not in order %r" % (v, text, ch, FONT_ORDER))
        rows, _, placements = font_compose(text)
        for ch, x_off in placements:
            cell = FONT_GLYPHS[ch]
            for y in range(FONT_CELL_H):
                for x in range(FONT_CELL_W):
                    if cell[y][x] == "#" and rows[y][x_off + x] != "#":
                        problems.append(
                            "font: %r -- glyph %r at x=%d loses its lit pixel "
                            "(%d,%d) to a later cell" % (text, ch, x_off, x, y))
    return problems


def check_font_against_vanilla():
    """If the shipped archive is reachable, prove the digits really are vanilla's.

    Hermetic when it is not: the embedded transcription is the source of truth
    for the build, this only catches it drifting from the game."""
    import io
    import zipfile

    zip_path = os.environ.get("FOM_ASSETS_ZIP", GAME_ASSETS_ZIP)
    if not os.path.isfile(zip_path):
        return ["font: vanilla cross-check SKIPPED (no archive at %s)" % zip_path]

    entry = "assets/animations/UI NEW/Fonts/spr_ui_hud_font_itemcount.png"
    with zipfile.ZipFile(zip_path) as zf:
        im = Image.open(io.BytesIO(zf.read(entry))).convert("RGBA")
    px = im.load()
    problems = []
    if im.size != (FONT_CELL_W * 13, FONT_CELL_H):
        problems.append("font: vanilla itemcount is %dx%d, expected %dx%d"
                        % (im.size[0], im.size[1], FONT_CELL_W * 13, FONT_CELL_H))
        return problems
    for i, ch in enumerate("0123456789./+"):
        for y in range(FONT_CELL_H):
            row = ""
            for x in range(FONT_CELL_W):
                p = px[i * FONT_CELL_W + x, y]
                row += "." if p[3] == 0 else ("#" if p[:3] == (255, 255, 255)
                                              else "o")
            if row != VANILLA_ITEMCOUNT_GLYPHS[ch][y]:
                problems.append("font: glyph %r row %d is %r in the archive, "
                                "%r here" % (ch, y, row,
                                             VANILLA_ITEMCOUNT_GLYPHS[ch][y]))
    return problems


# --------------------------------------------------------------------------
# meta.toml writers (R8 §2.2 templates verbatim; meta_properties.id omitted
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

# `[netstor_count]` for the fiddle merge.  GENERATED, not hand-authored, and
# that is deliberate: the glyph bitmaps and the advances are one design, and a
# hand-edited advance that disagrees with the art draws a wrong number in a way
# nothing downstream can detect.  One writer, one truth.  MOMI merges this into
# the game's own `assets/fiddle/fonts/sprite_fonts.toml` by path
# (`Installer.DestinationPath` = "assets/" + the mod-relative path), and the
# destination has no `[[table arrays]]` at all, so none of the Tomlyn table-array
# re-open hazard that shadows the crafting-menu merge applies here.
FIDDLE_FONT_HEADER = (
    '# YADS -- the value badges\' own sprite font.\n'
    '#\n'
    '# MOMI merges this ONE key into the game\'s fonts/sprite_fonts.toml.  It is a\n'
    '# clone of vanilla [item_count] (same sprite geometry, same thirteen glyphs,\n'
    '# same advances) extended with `k` and `m`, because the badge abbreviates and\n'
    '# item_count cannot spell it: Anchor.gml:1092-1107 SKIPS an unknown character\n'
    '# without advancing x_off and anchor_utils.gml:2542 scores it 0, so "1.2k" in\n'
    '# item_count would both draw and measure as "1.2".\n'
    '#\n'
    '# GENERATED BY make_art.py -- edit that, not this.  The advances below and the\n'
    '# pixels in spr_ui_hud_font_netstor_count.png are one design; make_art.py\'s\n'
    '# audit_font_strings() composes every string the mod can emit and fails if any\n'
    '# glyph loses a lit pixel to the next one.\n'
    '#\n'
    '# Fonts.gml:15-21 asserts every `characters` key occurs in `order` AND that\n'
    '# the two have the same length, at boot, for EVERY font in the merged file.\n'
    '\n'
)


# Every vanilla sprite ships a paired `poly_` bounds Shape under `shapes/`
# mirroring `animations/` (R1 §2.E; R1 risk 9 -- "ship a poly for every
# sprite").  MOMI mints `id` and auto-links `required_assets` to the paired
# spr_ asset, so both are omitted here.  All world sprites of a vanilla chest
# share ONE box sized to the resting (closed) pose, not per-frame -- the glow
# overlay follows the same rule.
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


def save_strip(directory, name, frames, duration=None):
    """frames: list of Canvas, all FRAME_W x FRAME_H.  Writes PNG + meta."""
    n = len(frames)
    strip = Image.new("RGBA", (FRAME_W * n, FRAME_H), (0, 0, 0, 0))
    for i, cv in enumerate(frames):
        strip.paste(cv.im, (i * FRAME_W, 0))
    png = "%s/%s.png" % (directory, name)
    strip.save(png)
    if n == 1:
        meta = META_WORLD_STATIC.format(w=FRAME_W, h=FRAME_H, oh=OFF_H, ov=OFF_V)
    else:
        meta = META_WORLD_ANIM.format(w=FRAME_W, h=FRAME_H, n=n, d=duration,
                                      oh=OFF_H, ov=OFF_V)
    write_text("%s/%s.meta.toml" % (directory, name), meta)
    return png


def save_icon(directory, name, cv):
    png = "%s/%s.png" % (directory, name)
    cv.im.save(png)
    write_text("%s/%s.meta.toml" % (directory, name), META_ICON)
    # icon shape: the whole 18x18 frame around the "Middle" pivot, verbatim
    # vanilla (poly_ui_item_furniture_basic_chest_v01: [-9,-9] / [18,18])
    write_text("%s/poly_%s.meta.toml" % (ICON_SHAPE_DIR, name[4:]),
               META_SHAPE.format(ox=-9, oy=-9, w=18, h=18))
    return png


def save_craft_icon(name, cv):
    """PNG + meta + the paired box Shape, in vanilla's own tree position.

    The Shape is `offset = [0, 0]` / `dimensions = [14, 14]` -- vanilla's, not
    the item icons' [-9,-9], because these icons have no centred pivot to be
    relative to."""
    png = "%s/%s.png" % (CRAFT_ICON_DIR, name)
    cv.im.save(png)
    write_text("%s/%s.meta.toml" % (CRAFT_ICON_DIR, name), META_CRAFT_ICON)
    write_text("%s/poly_%s.meta.toml" % (CRAFT_ICON_SHAPE_DIR, name[4:]),
               META_SHAPE.format(ox=0, oy=0, w=CRAFT_ICON_W, h=CRAFT_ICON_W))
    return png


def save_font(cv):
    """PNG + meta + the paired box Shape + the fiddle table, in vanilla's tree.

    The Shape is `offset = [0, 0]` / `dimensions = [5, 7]` -- one CELL, not the
    whole strip, copied from `poly_ui_hud_font_itemcount.meta.toml` in the
    archive.  R1 risk 9: a sprite with no paired poly throws "invalid asset id,
    required Shape" the moment something draws it."""
    png = "%s/%s.png" % (FONT_DIR, FONT_SPRITE)
    cv.im.save(png)
    write_text("%s/%s.meta.toml" % (FONT_DIR, FONT_SPRITE),
               META_FONT.format(w=FONT_CELL_W, h=FONT_CELL_H,
                                n=len(FONT_ORDER)))
    write_text("%s/poly_%s.meta.toml" % (FONT_SHAPE_DIR, FONT_SPRITE[4:]),
               META_SHAPE.format(ox=0, oy=0, w=FONT_CELL_W, h=FONT_CELL_H))

    body = ["[%s]" % FONT_TABLE,
            '\tsprite = "%s"' % FONT_SPRITE,
            '\torder = "%s"' % FONT_ORDER]
    for ch in FONT_ORDER:
        body.append('\tcharacters."%s" = %d' % (ch, FONT_ADVANCE[ch]))
    write_text("%s/sprite_fonts.toml" % FIDDLE_FONT_DIR,
               FIDDLE_FONT_HEADER + "\n".join(body) + "\n")
    return png


def world_shape_box(closed_im):
    """Box hitbox for a unit's world sprites: the resting (closed) pose's
    opaque bounds, grown 1px per side and clamped to the frame, expressed
    relative to the sprite pivot (16, 24)."""
    x0, y0, x1, y1 = closed_im.getbbox()          # x1/y1 exclusive
    x0 = max(0, x0 - 1)
    y0 = max(0, y0 - 1)
    x1 = min(FRAME_W, x1 + 1)
    y1 = min(FRAME_H, y1 + 1)
    return dict(ox=x0 - int(OFF_H), oy=y0 - int(OFF_V), w=x1 - x0, h=y1 - y0)


# --------------------------------------------------------------------------
# Sanity checks -- run on every generated canvas
# --------------------------------------------------------------------------


def audit(name, im, orphans=True):
    """Returns a list of problem strings (empty == clean).

    `orphans=False` for the glow overlays: isolated single pixels are the
    POINT there (diodes, the travelling spark), not a drawing mistake."""
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
    for fx in range(0, im.width, FRAME_W if im.width % FRAME_W == 0 else im.width):
        fw = FRAME_W if im.width % FRAME_W == 0 else im.width
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
    alpha untouched (V14-C §1.4 -- the engine's own blend semantics).  Used
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
# Contact sheet
# --------------------------------------------------------------------------


def contact_sheet(rows, path, zoom=4):
    """rows: list of (label, [PIL.Image, ...]) -- one row per unit, every
    sprite in that unit laid out left to right on a neutral checker."""
    from PIL import ImageDraw

    pad, gap, label_h = 12, 10, 14
    row_w = [sum(im.width for im in ims) * zoom + gap * (len(ims) - 1)
             for _, ims in rows]
    row_h = [max(im.height for im in ims) * zoom + label_h + 6 for _, ims in rows]
    sheet_w = max(row_w) + pad * 2
    sheet_h = sum(row_h) + pad * (len(rows) + 1)

    sheet = Image.new("RGBA", (sheet_w, sheet_h), (0x3a, 0x3d, 0x4c, 255))
    ck = Image.new("RGBA", (sheet_w, sheet_h), (0, 0, 0, 0))
    ckpx = ck.load()
    for y in range(sheet_h):
        for x in range(sheet_w):
            if ((x // 8) + (y // 8)) % 2 == 0:
                ckpx[x, y] = (0x44, 0x47, 0x57, 255)
    sheet.alpha_composite(ck)

    dr = ImageDraw.Draw(sheet)
    y = pad
    for i, (label, ims) in enumerate(rows):
        dr.text((pad, y), label, fill=(0xe8, 0xe8, 0xf0, 255))
        x = pad
        base = y + label_h + 6
        for im in ims:
            big = im.resize((im.width * zoom, im.height * zoom), Image.NEAREST)
            sheet.alpha_composite(big, (x, base + (max(j.height for j in ims)
                                                  - im.height) * zoom))
            x += im.width * zoom + gap
        y += row_h[i] + pad
    sheet.save(path)
    return path


# --------------------------------------------------------------------------
# main
# --------------------------------------------------------------------------


def main():
    for d in (WORLD_DIR, ICON_DIR, WORLD_SHAPE_DIR, ICON_SHAPE_DIR,
              CRAFT_ICON_DIR, CRAFT_ICON_SHAPE_DIR,
              FONT_DIR, FONT_SHAPE_DIR, FIDDLE_FONT_DIR):
        os.makedirs(d, exist_ok=True)

    produced = []      # (path, expected_w, expected_h)
    preview = []
    problems = []

    states = (
        ("closed", ["closed"], None),
        ("opened", ["opened"], None),
        ("opening", ["opening0", "opening1"], OPENING_DUR),
        ("bounce", ["bounce0", "bounce1", "bounce2"], BOUNCE_DUR),
    )

    for unit in ("heart", "block", "panel"):
        frame = FRAMER[unit]
        row_images = []
        box = world_shape_box(frame("closed").im)
        body_top = FRAME_H            # highest opaque row over ALL base poses

        for state, poses, dur in states:
            frames = [frame(p) for p in poses]
            name = "spr_furniture_netstor_%s_%s" % (unit, state)
            png = save_strip(WORLD_DIR, name, frames, dur)
            write_text("%s/poly_%s.meta.toml" % (WORLD_SHAPE_DIR, name[4:]),
                       META_SHAPE.format(**box))
            produced.append((png, FRAME_W * len(frames), FRAME_H))
            im = Image.open(png).convert("RGBA")
            problems += audit(name, im)
            body_top = min(body_top, im.getbbox()[1])
            row_images.append(im)

        # ---- the CONNECTED glow overlay ------------------------------------
        glow_frames = [GLOW[unit](f) for f in range(GLOW_LEN)]
        gname = "spr_furniture_netstor_%s_glow" % unit
        gpng = save_strip(WORLD_DIR, gname, glow_frames, GLOW_DUR)
        write_text("%s/poly_%s.meta.toml" % (WORLD_SHAPE_DIR, gname[4:]),
                   META_SHAPE.format(**box))
        produced.append((gpng, FRAME_W * GLOW_LEN, FRAME_H))
        gim = Image.open(gpng).convert("RGBA")
        problems += audit(gname, gim, orphans=False)
        tones = count_tones(gim)
        if len(tones) > 3:
            problems.append("%s: %d tones, spec allows 2-3 luminance rungs"
                            % (gname, len(tones)))
        # v1.4: the tinted strip must be pure LUMINANCE.  Any colour left in
        # it survives the multiply and skews (or kills) every runtime tint --
        # this is precisely how the v1.3 cyan strips failed (V14-C §1.4).
        for t in sorted(tones):
            if not (t[0] == t[1] == t[2]):
                problems.append("%s: non-grey glow pixel %s -- untintable"
                                % (gname, str(t[:3])))
            elif t not in (G1, G2, G3):
                problems.append("%s: off-ramp glow tone %s" % (gname, str(t[:3])))

        # ---- the DISCONNECTED sad-face overlay -----------------------------
        off_frames = [OFFLINE[unit](f) for f in range(OFFLINE_LEN)]
        oname = "spr_furniture_netstor_%s_offline" % unit
        opng = save_strip(WORLD_DIR, oname, off_frames, OFFLINE_DUR)
        write_text("%s/poly_%s.meta.toml" % (WORLD_SHAPE_DIR, oname[4:]),
                   META_SHAPE.format(**box))
        produced.append((opng, FRAME_W * OFFLINE_LEN, FRAME_H))
        oim = Image.open(opng).convert("RGBA")
        problems += audit(oname, oim)
        otones = count_tones(oim)
        if len(otones) > 4:
            problems.append("%s: %d tones, spec allows 3 + black outline"
                            % (oname, len(otones)))
        # the face must hover CLEAR of the unit in every bobbed frame, over
        # every base pose -- the whole point of putting it above the sprite.
        face_bot = oim.getbbox()[3] - 1
        if face_bot >= body_top:
            problems.append("%s: face reaches row %d but %s body starts at "
                            "row %d" % (oname, face_bot, unit, body_top))

        ic = ICONS[unit]()
        ol = outline_canvas(ic)
        p1 = save_icon(ICON_DIR, "spr_ui_item_netstor_%s" % unit, ic)
        p2 = save_icon(ICON_DIR, "spr_ui_item_netstor_%s_outline" % unit, ol)
        produced.append((p1, 18, 18))
        produced.append((p2, 18, 18))
        problems += audit("spr_ui_item_netstor_%s" % unit, ic.im)
        row_images.append(ic.im)
        row_images.append(ol.im)

        preview.append((
            "netstor_%s    closed | opened | opening f0 f1 | bounce f0 f1 f2 "
            "| icon | outline" % unit, row_images))
        # the glow is only meaningful composited over the body it hugs
        closed_im = Image.open("%s/spr_furniture_netstor_%s_closed.png"
                               % (WORLD_DIR, unit)).convert("RGBA")
        comps = []
        for cvg in glow_frames:
            comp = closed_im.copy()
            comp.alpha_composite(cvg.im)
            comps.append(comp)
        preview.append(("netstor_%s glow  (8 frames @ 0.2s, over the CLOSED "
                        "pose)" % unit, comps))
        ocomps = []
        for cvo in off_frames:
            comp = closed_im.copy()
            comp.alpha_composite(cvo.im)
            ocomps.append(comp)
        preview.append(("netstor_%s offline  (4 frames @ 0.35s, over the "
                        "CLOSED pose)" % unit, ocomps))
        # v1.4: the same glow frame put through each runtime `image_blend`, so
        # all four states can be eyeballed side by side.  Only the OVERLAY is
        # multiplied here -- the body underneath is a separate, untinted
        # renderer, exactly as at runtime.
        tcomps = []
        for _, rgb in TINTS:
            comp = closed_im.copy()
            comp.alpha_composite(tint_image(glow_frames[TINT_FRAME].im, rgb))
            tcomps.append(comp)
        preview.append(("netstor_%s glow TINT SIM (frame %d x image_blend)  "
                        "green=empty | yellow=in use | red=full | cyan=heart+"
                        "panel | white=untinted/highlight-clobber"
                        % (unit, TINT_FRAME), tcomps))

    # ---- the Remote Access Panel's item icon (Beta 1.2) --------------------
    # Outside the unit loop because it is not a unit: the remote has no object
    # prototype, so no world strip, no glow, no offline face and no shape box
    # around a placed body.  What it does have is exactly what any item needs --
    # an 18x18 icon, its pure-white outline sibling, and the two Shape polys
    # save_icon writes for them.
    #
    # `outlines.json` is NOT written from here.  make_art.py has never touched
    # that file and must not start: it is hand-maintained, and a generator that
    # rewrote it would silently drop any entry a future hand edit added.  A
    # missing entry there costs the icon its outline (spr_nothing substitute
    # plus an error line), so the entry is added in the same change as the art
    # and the ship gate greps for it.
    rem = icon_remote()
    rem_ol = outline_canvas(rem)
    r1 = save_icon(ICON_DIR, "spr_ui_item_netstor_remote", rem)
    r2 = save_icon(ICON_DIR, "spr_ui_item_netstor_remote_outline", rem_ol)
    produced.append((r1, 18, 18))
    produced.append((r2, 18, 18))
    problems += audit("spr_ui_item_netstor_remote", rem.im)
    problems += audit("spr_ui_item_netstor_remote_outline", rem_ol.im)
    preview.append(("netstor_remote  (item icon only -- not a placeable)   "
                    "icon | outline", [rem.im, rem_ol.im]))

    # ---- the crafting sub-category icon (v1.5) -----------------------------
    # Outside the unit loop on purpose: it belongs to a MENU, not to a placeable,
    # so it has no world strip, no glow, no outline and no 18x18 sibling.
    cat_name = "spr_ui_crafting_category_icon_netstor"
    cat = craft_category_icon()
    cat_png = save_craft_icon(cat_name, cat)
    produced.append((cat_png, CRAFT_ICON_W, CRAFT_ICON_W))
    problems += audit(cat_name, cat.im)
    # Shown twice: bare, so the silhouette and its 1px inset can be checked, and
    # composited on #f9edf8 -- the only background it is ever seen on, and the
    # one that decides whether the cyan seam still reads.
    cat_on_paper = Image.new("RGBA", (CRAFT_ICON_W, CRAFT_ICON_W), PAPER)
    cat_on_paper.alpha_composite(cat.im)
    preview.append(("crafting sub-category icon (14x14, UI atlas, shown at 4x)"
                    "   bare | on the crafting page's #f9edf8 paper",
                    [cat.im, cat_on_paper]))

    # ---- the value badges' sprite font (Alpha 1.5) -------------------------
    # Also outside the unit loop, and for a stronger reason than the icon: this
    # is not a picture of anything, it is a TYPEFACE plus the data table that
    # measures it, and both come out of one place so they cannot disagree.
    font_cv = font_strip()
    font_png = save_font(font_cv)
    produced.append((font_png, FONT_CELL_W * len(FONT_ORDER), FONT_CELL_H))
    # orphans=False: the `.` cell is a single lit pixel with a black outline
    # around it, and `1`/`4`/`7` carry deliberately detached outline pixels --
    # the orphan rule is about hand-drawn art, not about a font's outline.
    problems += audit(FONT_SPRITE, font_cv.im, orphans=False)
    font_tones = count_tones(font_cv.im)
    if font_tones - {BK, WHITE}:
        problems.append("%s: off-palette tone(s) %s -- the vanilla font is "
                        "black + white only" % (FONT_SPRITE,
                                                sorted(font_tones - {BK, WHITE})))
    problems += check_font_against_vanilla()
    problems += audit_font_strings()
    # Shown as the strip, then as the strings the mod will actually draw --
    # composed by the same routine the engine uses, so the sheet is evidence,
    # not an impression.
    font_row = [font_cv.im]
    for text in ("999", "1.2k", "9.9k", "999k", "1.9m", "12345"):
        rows, width, _ = font_compose(text)
        cell = Canvas(max(1, width + FONT_CELL_W), FONT_CELL_H)
        cell.blit_rows(0, 0, rows, FONT_LEGEND)
        font_row.append(cell.im)
    preview.append(("sprite font %s (5x7 cells, 15 frames, UI atlas, 4x)   "
                    "strip | 999 | 1.2k | 9.9k | 999k | 1.9m | 12345"
                    % FONT_SPRITE, font_row))

    problems += check_tint_ramp()

    contact_sheet(preview, PREVIEW, zoom=4)

    # ---------------- verification table ------------------------------------
    print("")
    print("output tree: %s" % MOD)
    print("")
    print("%-58s %-11s %-11s %s" % ("FILE", "EXPECTED", "ACTUAL", "OK"))
    print("-" * 96)
    allok = True
    for path, ew, eh in sorted(produced):
        im = Image.open(path)
        ok = (im.size == (ew, eh))
        allok = allok and ok
        print("%-58s %-11s %-11s %s" % (
            os.path.basename(path), "%dx%d" % (ew, eh),
            "%dx%d" % im.size, "OK" if ok else "MISMATCH"))
    print("-" * 96)
    print("dimension check: %s" % ("ALL PASS" if allok else "FAILURES PRESENT"))

    # ---------------- the badge width budget, measured -----------------------
    # This is the table yads_badge_slot's COIN_TEXT_MAX is
    # read off.  The slot is 22px; the tesserae coin is 7px and sits 1px clear
    # of the number, so a badge that wants to keep its coin has 14px of text.
    # `width` here is sprite_font_width(text, "netstor_count") computed the
    # engine's way -- the sum of the advances, not a glyph count.
    coin_max = 22 - 7 - 1
    print("")
    print("badge width budget: 22px slot - 7px coin - 1px gap = %dpx of text"
          % coin_max)
    print("%-12s %-10s %-7s %-7s %s"
          % ("VALUE", "ABBREV", "GLYPHS", "WIDTH", "COIN"))
    print("-" * 52)
    widest = 0
    for v in FONT_AUDIT_VALUES:
        text = abbrev_value(v)
        _, width, _ = font_compose(text)
        widest = max(widest, width)
        print("%-12d %-10s %-7d %-7d %s"
              % (v, text, len(text), width,
                 "yes" if width <= coin_max else "no"))
    print("-" * 52)
    print("widest abbreviated badge: %dpx (bare) / %dpx (with coin+gap) "
          "against a 22px slot" % (widest, widest + 8))
    if problems:
        print("\nAUDIT PROBLEMS (%d):" % len(problems))
        for p in problems:
            print("  " + p)
    else:
        print("audit: binary alpha OK, no orphan pixels, glow tone count OK, "
              "glow strips grey-only and tintable")
    print("preview: %s" % PREVIEW)


if __name__ == "__main__":
    main()
