#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""links.py -- THE FOUR CONNECTORS (Beta 1.3, the `netstor_link_*` set).

A connector is a `rug = true` prototype: no hitbox, walkable, layable UNDER a
placed unit, and traversable by the network scan.  It holds nothing -- the
custody surface of a connector is zero by construction (b13 recon H1) -- so its
whole job is to be SEEN: a lit path across the farm that says which crates are
on the network and which are stranded.

  Magic Carpet      spr_furniture_netstor_link_carpet   a woven runner whose
                    hem and fringe follow the run -- a rug that is secretly a
                    wire.
  Magic Tile        spr_furniture_netstor_link_tile     slate flagstones with
                    an inlaid trace; the chamfer opens where the path goes.
  Bundle of Cables  spr_furniture_netstor_link_cables   a bundle that BENDS,
                    clamped at every turn, ferruled at every dead end.
  Cloud Connector   spr_furniture_netstor_link_cloud    a puff floating clear
                    of the ground, merging into a bank along the run.

WHY THIS IS ITS OWN MODULE, beside `crates/` rather than inside it

  * `crates/` is a family fan-out over VANILLA chest geometry: `__init__.py`
    globs `fam_*.py`, every family validates itself against `_geom.py`, and a
    twin ships no body art at all because its body is a vanilla sprite named by
    string.  A connector has no vanilla body, no family and no chest -- it would
    fail every structural check that file exists to make.
  * `make_art.py`'s authored-unit loop is hard-wired to the 40x48 canvas and the
    four chest-lid states (closed / opening / opened / bounce).  A connector has
    none of those: it is a flat 32x32 quad, and since D2 it has SIXTEEN poses
    that are not an animation.

  So this module owns its own drawers and `make_art.py` gains ONE loop over
  `CONNECTORS`, exactly as it gained one over `crates.FAMILIES`.

WHAT IT MAY DRAW WITH.  `crates/_kit.py` and nothing else -- the same palette,
the same Canvas, the same G-ramp, the same meta templates and the same audits
the three authored units and the fourteen crate families use.  A connector that
invented a colour would be a fifth set that stops matching the other four one
edit later.

===========================================================================
D2 "WOVEN" -- THE CONNECTED-TEXTURE SYSTEM
===========================================================================

Every connector's BODY is a SIXTEEN-FRAME AUTOTILE STRIP, one frame per NSEW
adjacency mask, and the frame index IS the mask:

    mask = 1*north + 2*west + 4*east + 8*south

which is not a convention this file invented -- it is the engine's own fence
autotiler, `inner_fence_auto_tile` (Furniture.gml:2193), verbatim.  Copying it
buys the one thing a made-up order cannot: the runtime write is
`renderer.image_index = mask` with `image_speed = 0`, which is exactly what the
engine itself does at Furniture.gml:1265-1271 after every renderer rebuild.  We
are riding a path the engine already walks, in the same direction.

FRAME 0 IS THE ISOLATED PIECE and must read as a finished object on its own --
a lone mat, a lone flagstone, a lone coil of cable, a lone puff.  Every other
frame OPENS on the sides a neighbour is on: the carpet drops its hem and grows
its field to the tile edge so two carpets weld into one long runner; the tile
drops its chamfer; the cable bends a real 8px bundle round a clamp; the cloud
stretches its shadow and merges its body into a bank.

THE GLOW IS NO LONGER THE DRAWING.  Under D1 the body was direction-neutral and
the overlay carried all the routing; under D2 the body carries the path and the
overlay is a soft UNDER-LIGHT that only says the path is alive.  That is why
the D2 glow is a rung dimmer than the shipped v1.3 one everywhere: two bright
drawings of the same line is one drawing too many.

OVERLAY VARIANTS ARE SEPARATE SPRITES, NOT FRAMES.  The overlay's frames are
its ANIMATION -- eight of them, the set-wide pulse -- so the variant cannot also
live in `image_index`.  It lives in the sprite NAME instead, which is the swap
the runtime already performs:

    spr_furniture_netstor_link_<slug>_glow_v0 .. _glow_v15     8 frames each
    spr_furniture_netstor_link_cloud_offline_v0 .. _v15        4 frames each

`..._glow` (no suffix) still ships, is byte-for-byte the v0 variant, and is what
the object prototype's `top_sprite` names.  It is the fail-soft: an art layer
without the variant strips leaves every connector wearing the isolated glow,
which is dim and correct-looking rather than absent.

OFFLINE IS SHAPELESS FOR THE FLAT THREE -- one 4-frame marker, a dead pad at the
crossing, identical in all four frames and identical for all sixteen masks.  It
can afford to be: the BODY strip is what carries the shape, and the body is
still drawn when the network is down.  The CLOUD cannot afford it, and that is
the whole reason it ships sixteen offline variants: its body lives ENTIRELY in
the overlay (its base sprite is only a shadow on the grass), so a shapeless
offline face would make a merged cloud bank snap back to a single puff -- or,
if the strip were missing altogether, make the Cloud VANISH the moment it went
offline.  No connector may ever become invisible when offline.

THE TWO LAYERS, and why the Cloud can float (b13 recon Q1.6)

  A rug renderer gets its base sprite pushed to `get_floor_depth()` -- under
  Ari, under shadows, under everything -- but `top_sheet_renderer.depth` is
  never revisited, so the `top_sprite` overlay keeps ORDINARY y-sorted depth.
  That is one object drawing on two depth layers, and it is free.

  Three of the four ignore it and simply draw a flat quad with the overlay
  hugging it.  The Cloud USES it, as above.

THE GLOW IS TINTED, so it is grey (the v1.4 rule, unchanged).  `image_blend` is
a per-channel multiply and these strips carry LUMINANCE ONLY -- G1/G2/G3, never
a colour.  `yads_glow_tint` returns the set's cyan for any non-CRATE kind, so a
connector arrives cyan with a zero-line diff to that function.

RESTRAINT IS A REQUIREMENT HERE, not a preference.  These pieces TILE: a player
runs thirty of them across a farm.  Whatever the glow does, thirty copies of it
do at once, so:

  * the conductor never goes dark and never goes full-bright -- it rides
    SEAM_G (G1 <-> G2), the same two-rung swing the crate seam uses, so a long
    path breathes instead of flashing.  D2 rides it a rung LOWER than v1.3
    (`SEAM_G[p-1]`) because the body is now drawing the same line;
  * exactly ONE travelling charge per axis, stepping 2px per frame in GLOBAL
    tile phase.  16px of tile over 8 frames means the charge leaves one tile
    exactly as the next tile's charge leaves it -- the path reads as ONE running
    charge rather than as thirty independent blinkers.  D2 widens it from a hard
    2px G3 spark to a 4px swell at the pulse tone, which is DIMMER on half the
    cycle (GTONE[0] is G1) and never lights more than one stretch per axis;
  * the spill and the accent pixels pulse half a cycle out of phase with each
    other, so no frame is ever the "everything is bright" frame;
  * an arm is only drawn where a neighbour actually is.  A dead-end connector
    lights one arm, not four, so a run's ends do not leak light into the grass.

GEOMETRY, measured off vanilla's smallest rug (b13 recon Q4.4)

  `void_flagstone_small_v1` is `size = [2, 2]` -- 16x16 px, the smallest
  footprint in the game -- on a 32x32 canvas with pivot (8.0, 8.0) and its
  content in canvas [8..23] on both axes.  The pivot is therefore the
  footprint's top-left corner and there are 8px of bleed on every side.  All
  three flat connectors copy that exactly, and the carpet's fringe is the one
  thing that uses the bleed.  The Cloud takes a taller 32x48 canvas with pivot
  (8.0, 24.0) -- same footprint, 24 rows of sky above it.
"""

from crates._kit import *          # noqa: F401,F403  (the shared vocabulary)


# --------------------------------------------------------------------------
# THE MASK -- the engine's own fence bit order, Furniture.gml:2193.
#
#     return (1 * north) + (2 * west) + (4 * east) + (8 * south);
#
# Copied rather than chosen.  `network.gml` writes `renderer.image_index = mask`
# and the engine's own fence re-apply (Furniture.gml:1265-1271) writes exactly
# the same shape of value into exactly the same field, so a future reader who
# knows one knows the other.
# --------------------------------------------------------------------------

N, W, E, S = 1, 2, 4, 8
DIRS = (N, W, E, S)
DIRNAME = {N: "N", W: "W", E: "E", S: "S"}
OPPOSITE = {N: S, S: N, W: E, E: W}

MASK_LEN = 16                   # 2^4 -- one body frame, one glow sprite each

A_EW = E | W
A_NS = N | S


def has(mask, d):
    return (mask & d) != 0


def deg(mask):
    """How many arms this piece has: 0 isolated, 1 dead end, 2 straight or
    corner, 3 tee, 4 cross."""
    return sum(1 for d in DIRS if has(mask, d))


# --------------------------------------------------------------------------
# THE CANVASES
# --------------------------------------------------------------------------

FLAT_W = FLAT_H = 32
FLAT_PIVOT = (8.0, 8.0)

CLOUD_W, CLOUD_H = 32, 48
CLOUD_PIVOT = (8.0, 24.0)

# The 16x16 footprint quad, in canvas coordinates.  Identical on both canvases
# in x; the Cloud's is pushed down to make room for the sky.
Q0, Q1 = 8, 23                  # flat canvas: footprint rows AND columns
CQ0, CQ1 = 24, 39               # cloud canvas: footprint rows

# The conductor's own centre pair.  `LIVE` and `RTN` are the centre PAIR of the
# 16px quad (which is centred on 15.5), so anything mirrored about them is
# symmetric and tiles without a seam.  The conductor runs on `LIVE` alone; `RTN`
# is the down-and-right neighbour -- the shadow side, since the whole set is lit
# from the top-left -- and is where the via's swell and the shadow corner sit.
LIVE = 15
RTN = 16

# THE FOUR EDGE MIDPOINTS, and the tone that must be sitting on them.
#
# This is `audit_autotile_body`'s only handle on whether the sixteen frames are
# in the RIGHT ORDER.  Frame count and non-emptiness are cheap and were already
# checked; neither can see an N/S or W/E transposition, which is the exact bug a
# hand-written bit table invites and the exact bug that makes a run of carpets
# grow arms into empty grass.  So the audit reads each frame back at the point
# where the arm crosses the tile edge and asserts the CONDUCTOR TONE is there
# when, and only when, that frame's bit is set.
#
# The midpoints are the drawers' own numbers, not measurements: `arm_line`
# terminates a north arm at (LIVE, Q0), a west arm at (Q0, LIVE), and so on, so
# these four points are where the three flat pieces put C2 and nowhere else.
# CLOSED sides are not merely empty there -- the carpet's hem and the tile's
# chamfer both paint BK across the same pixel -- which is precisely why the
# probe tests for the conductor's own tone rather than for ink.
FLAT_EDGE_AT = {N: (LIVE, Q0), W: (Q0, LIVE), E: (Q1, LIVE), S: (LIVE, Q1)}
FLAT_EDGE_TONE = C2

# THE BODY STRIP'S AUTHORED FRAME RATE, and it is ZERO because this strip has no
# time axis at all.  `frame_len = 16` here is a pure INDEX SPACE -- frame n IS
# adjacency mask n -- and the only thing that ever selects a frame is the
# runtime's `renderer.image_index = mask`.
#
# THE ENGINE DOES NOT DEFAULT A NODE RENDERER TO `image_speed = 0`, and that is
# the whole reason this number matters.  obj_node_renderer's Create spells out
# some forty fields by hand and image_speed is not among them
# (obj_node_renderer.gml:388-436); obj_grass_backing, which really is meant to
# be still, has to say `image_speed: 0.0` for itself (obj_node_renderer.gml:744);
# and the engine's OWN sixteen-frame fence strips ship `duration = 0.1`
# (spr_decor_starter_wood_fence_spring.meta.toml) and are held still only because
# create_furniture_renderer pins `image_speed = 0` by hand for `prototype.fence`
# nodes (Furniture.gml:1265-1271).  A rug is not a fence, so the ONLY thing
# holding a connector's body still is `yads_glow_apply`'s own per-frame assert --
# and that assert reaches a renderer only while its connector is in the glow
# cache and on screen.  At the old 10.0, a connector the cache never reached
# played all sixteen shapes at ten seconds a frame, forever, in front of the
# player.  Frame 0 for an un-applied renderer is not a bounded pre-apply
# courtesy; it is the correctness requirement.
#
# `duration = 0.0` IS THE ENGINE'S OWN "does not animate" VALUE.  It is
# explicitly legal for a scalar (single frame-rate) animation whatever frame_len
# says, and illegal only inside a per-frame duration ARRAY, where a zero-length
# frame has no meaning (mistria-sdk/asset-properties/animations.md:105-115); a
# missing `duration` is assumed to be 0.0, which is what every still sprite in
# the game ships; and MOMI's own furniture generator writes "0.1 for animations /
# 0.0 for stills" (ModsOfMistriaInstallerLib/Generator/CompactFurnitureGenerator
# .cs:179-180).  Residual, recorded because nothing in the archive proves it
# directly: no VANILLA sprite pairs frame_len > 1 with duration 0.0, so this is
# the documented contract rather than an observed one.  The runtime assert stays
# regardless -- it is what survives a wrong guess here.
BODY_DUR = 0.0


# --------------------------------------------------------------------------
# Shared helpers
# --------------------------------------------------------------------------


def _halo_cells(cv, cells, open_rows=(), open_cols=()):
    """An 8-connected 1px black outline around an arbitrary cell set.

    Same construction as `draw_gem`'s socket ring in make_art.py, and sorted
    for the same reason: the generator's contract is that a clean run is
    byte-identical, and set iteration order is not something to bet that on.

    `open_rows` / `open_cols` ARE THE MERGE SEAM, and they exist because an
    outlined sprite that merges into a NEIGHBOURING COPY of itself must not
    draw its outline across that neighbour.  The Cloud's offline face is the
    only thing in the mod with that problem, and it has it on both axes: the
    line one step past the far end of a merge lobe or a merge column is exactly
    the line the neighbour's own puff occupies, so a cap there paints a black
    bar THROUGH the neighbour's body.  (Two clouds side by side have the same
    y and therefore the same y-sorted overlay depth, so which of the two bars
    survives is down to instance order -- a black seam that flickers between
    equally wrong states.  It is visible in every shipped `_offline_v` with a W
    or E bit; this is where it stops.)  Naming the lines the outline must leave
    open is the whole fix -- the lobe's and the column's SIDES still get their
    outline, which is what keeps a merged bank a drawn object rather than a
    blob.  Both empty by default: every other caller is a silhouette that ends
    where it ends."""
    mask = set(cells)
    skip_y = set(open_rows)
    skip_x = set(open_cols)
    for (x, y) in sorted(mask):
        for ny in (y - 1, y, y + 1):
            if ny in skip_y:
                continue
            for nx in (x - 1, x, x + 1):
                if nx in skip_x:
                    continue
                if (nx, ny) not in mask:
                    cv.set(nx, ny, BK)


def _rows_cells(x0, y0, rows):
    """The occupied cells of a character-grid sprite, as a flat list."""
    out = []
    for dy, row in enumerate(rows):
        for dx, ch in enumerate(row):
            if ch != ".":
                out.append((x0 + dx, y0 + dy))
    return out


def _halo(cv, x0, y0, rows):
    """`_halo_cells` for a character-grid sprite -- the icon's spelling."""
    _halo_cells(cv, _rows_cells(x0, y0, rows))


def arm_line(cv, d, c, live=LIVE, q0=Q0, q1=Q1):
    """1px conductor from the quad centre to the edge in direction `d`.

    It runs to the EDGE on purpose, cutting the piece's own outline at the
    midpoint: the outline break is what makes two abutting tiles look welded
    rather than stacked.

    ONE PIXEL WIDE, and that is a whole design decision.  The first cut drew a
    live line plus a shadow return beside it -- two pixels of cyan through the
    middle of a 16px tile, which is 12% of its width, and it stopped reading as
    a thread woven through a rug and started reading as a window pane dividing
    it into four brown quadrants.  A 1px thread with a swelling at the crossing
    reads as wiring; 2px reads as architecture.  The half-pixel asymmetry that
    costs (LIVE = 15 on a quad centred at 15.5) is invisible at this scale and
    tiles perfectly, because every tile has it."""
    if d == N:
        cv.vline(live, q0, live, c)
    elif d == S:
        cv.vline(live, live, q1, c)
    elif d == W:
        cv.hline(q0, live, live, c)
    else:
        cv.hline(live, q1, live, c)


def arm_band(cv, d, tones, live=LIVE, q0=Q0, q1=Q1):
    """A thick perpendicular-toned band running from the centre to the edge.

    `tones` is indexed ACROSS the band -- top-to-bottom for an E/W arm and
    left-to-right for an N/S arm -- which is what lets one tone table (the
    cable bundle's three-cables-and-their-shadows) serve both axes."""
    n = len(tones)
    off = live - (n // 2) + 1        # band straddles the centre pair
    for i, t in enumerate(tones):
        if t is None:
            continue
        if d in (E, W):
            y = off + i
            if d == E:
                cv.hline(live, q1, y, t)
            else:
                cv.hline(q0, live, y, t)
        else:
            x = off + i
            if d == S:
                cv.vline(x, live, q1, t)
            else:
                cv.vline(x, q0, live, t)


def centre_block(cv, tones):
    """The square knuckle where arms meet, drawn with the same tone table on
    both axes so a corner's two bands blend instead of butting."""
    n = len(tones)
    off = LIVE - (n // 2) + 1
    for i, t in enumerate(tones):
        if t is None:
            continue
        cv.hline(off, off + n - 1, off + i, t)


# --------------------------------------------------------------------------
# MAGIC CARPET -- a woven runner with the wire run through the weave.
#
# Warm all the way: the W ramp is the vanilla basic-chest wood histogram, so a
# carpet in it sits next to a netstor crate without a colour argument.  The
# field is a 2px CHECKER rather than a texture of noise, because at 16px noise
# reads as dirt and a repeat reads as cloth; the alternating blocks also give
# the eye something to measure the cyan thread against.
#
# THE HEM IS THE AUTOTILE.  It is drawn only on CLOSED sides, so two carpets in
# a row weld into one long rug with one continuous hem, and the fringe hangs
# off the closed END of a run -- which is what a real runner does and what says
# TEXTILE at a glance in a mixed path.
# --------------------------------------------------------------------------


def _weave(cv, x0, y0, x1, y1):
    """2x2 checker with a lit corner on the raised blocks.

    An earlier cut ran a true basketweave -- alternating blocks of horizontal
    and vertical thread, two tones each.  On a 12x12 field quartered by the
    conductor that leaves 5x5 of pattern per quadrant, which is not enough
    repeats for a weave to establish: it read as four little mazes.  A plain
    2x2 checker with one W4 pixel per raised block establishes in two repeats,
    reads as pile catching the light, and survives being cut into quarters."""
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            raised = ((((x - x0) // 2) + ((y - y0) // 2)) % 2 == 0)
            if not raised:
                cv.set(x, y, W2)
            elif (x - x0) % 2 == 0 and (y - y0) % 2 == 0:
                cv.set(x, y, W4)
            else:
                cv.set(x, y, W3)


# The four stitches that tie the weave to the wire.  Also the carpet's glow
# accent, so the pixels that pulse are pixels the body already puts there.
CARPET_STITCH = ((Q0 + 3, Q0 + 3), (Q1 - 3, Q0 + 3),
                 (Q0 + 3, Q1 - 3), (Q1 - 3, Q1 - 3))

# Where a tassel sits along the fringed edge.  Three, not four -- four evenly
# spaced tassels read as legs and turn the rug into a table.
CARPET_FRINGE_AT = (Q0 + 4, LIVE, Q1 - 4)


def carpet_base(mask):
    cv = Canvas(FLAT_W, FLAT_H)
    op = {d: has(mask, d) for d in DIRS}

    # The field first, edge to edge on OPEN sides so the weave crosses the seam
    # unbroken; inset by the hem's two rows on closed ones.
    fx0 = Q0 if op[W] else Q0 + 2
    fx1 = Q1 if op[E] else Q1 - 2
    fy0 = Q0 if op[N] else Q0 + 2
    fy1 = Q1 if op[S] else Q1 - 2
    _weave(cv, fx0, fy0, fx1, fy1)

    # The hem, on closed sides only: lit along the top and left, in shadow
    # along the bottom and right, which is the same light the crates are drawn
    # under.
    if not op[N]:
        cv.hline(Q0, Q1, Q0, BK)
        cv.hline(Q0, Q1, Q0 + 1, W4)
    if not op[S]:
        cv.hline(Q0, Q1, Q1, BK)
        cv.hline(Q0, Q1, Q1 - 1, W1)
    if not op[W]:
        cv.vline(Q0, Q0, Q1, BK)
        cv.vline(Q0 + 1, Q0, Q1, W4)
    if not op[E]:
        cv.vline(Q1, Q0, Q1, BK)
        cv.vline(Q1 - 1, Q0, Q1, W1)
    # A corner is only open when BOTH of its sides are: an L-bend still has to
    # close the outside of its own turn or the rug leaks into the grass.
    for (cx, cy, a, b) in ((Q0, Q0, W, N), (Q1, Q0, E, N),
                           (Q0, Q1, W, S), (Q1, Q1, E, S)):
        if not (op[a] and op[b]):
            cv.set(cx, cy, BK)

    # The woven-in thread, following the path.  Isolated gets a PAD rather than
    # a cross: a lone mat with a four-way wire on it is advertising three
    # connections it does not have.
    if mask == 0:
        cv.rect(LIVE - 1, LIVE - 1, RTN + 1, RTN + 1, C1)
        cv.rect(LIVE, LIVE, RTN, RTN, C2)
        cv.set(LIVE, LIVE, C3)
    else:
        for d in DIRS:
            if has(mask, d):
                arm_line(cv, d, C2)
        cv.set(RTN, LIVE, C2)
        cv.set(LIVE, RTN, C2)
        cv.set(RTN, RTN, C1)
        cv.set(LIVE, LIVE, C3)

    # FRINGE, and only where a runner would really have it: on the closed end
    # opposite the single arm of a run end, or on both ends of a lone mat.  Two
    # pixels long, 4-connected to the hem, so the orphan audit has nothing to
    # find.
    fringe = []
    if mask == 0:
        fringe = [W, E]
    elif deg(mask) == 1:
        fringe = [OPPOSITE[d] for d in DIRS if has(mask, d)]
    for d in fringe:
        for k in CARPET_FRINGE_AT:
            if d == W:
                cv.hline(Q0 - 2, Q0 - 1, k, W3)
            elif d == E:
                cv.hline(Q1 + 1, Q1 + 2, k, W1)
            elif d == N:
                cv.vline(k, Q0 - 2, Q0 - 1, W3)
            else:
                cv.vline(k, Q1 + 1, Q1 + 2, W1)

    for (sx, sy) in CARPET_STITCH:
        cv.set(sx, sy, C1)
    return cv


# --------------------------------------------------------------------------
# MAGIC TILE -- printed circuit meets masonry.
#
# The slate ramp, chamfered corners and a scatter of grit make it a cousin of
# vanilla's paving stones, so it lays into an existing stone path without
# looking like a mod dropped a spaceship in it.  What makes it OURS is the
# etched layer: a pad closing off every DEAD side, a trace running out every
# live one, and the via at the crossing.
#
# THE CHAMFER IS THE AUTOTILE: the black edge and its lit/shadowed inner row are
# drawn only on closed sides, so a run reads as one long slab and a corner turns
# without a seam.
#
# The grit is symmetric under a 180-degree rotation about the tile's centre.
# It reads as random and is not: a tile that is asymmetric under rotation shows
# a seam the moment two of them sit side by side.
# --------------------------------------------------------------------------

TILE_GRIT = ((13, 10, M2), (18, 21, M2),
             (11, 17, M4), (20, 14, M4),
             (17, 12, M2), (14, 19, M2))

# The pads' inner corners -- the tile's glow accent, for the carpet's reason.
TILE_PAD = ((Q0 + 3, Q0 + 3), (Q1 - 3, Q0 + 3),
            (Q0 + 3, Q1 - 3), (Q1 - 3, Q1 - 3))


def tile_base(mask):
    cv = Canvas(FLAT_W, FLAT_H)
    op = {d: has(mask, d) for d in DIRS}
    cv.rect(Q0, Q0, Q1, Q1, M3)

    if not op[N]:
        cv.hline(Q0 + 1, Q1 - 1, Q0, BK)
        cv.hline(Q0 + 1, Q1 - 1, Q0 + 1, M4)
    if not op[S]:
        cv.hline(Q0 + 1, Q1 - 1, Q1, BK)
        cv.hline(Q0 + 1, Q1 - 1, Q1 - 1, M1)
    if not op[W]:
        cv.vline(Q0, Q0 + 1, Q1 - 1, BK)
        cv.vline(Q0 + 1, Q0 + 1, Q1 - 1, M4)
    if not op[E]:
        cv.vline(Q1, Q0 + 1, Q1 - 1, BK)
        cv.vline(Q1 - 1, Q0 + 1, Q1 - 1, M1)
    # The corner pixel: slate when the turn is open on both sides, black when
    # only one is (the chamfer's own corner), and left transparent when both
    # are closed -- that missing pixel is what turns a square into a laid stone.
    for (cx, cy, a, b) in ((Q0, Q0, W, N), (Q1, Q0, E, N),
                           (Q0, Q1, W, S), (Q1, Q1, E, S)):
        if op[a] and op[b]:
            cv.set(cx, cy, M3)
        elif op[a] or op[b]:
            cv.set(cx, cy, BK)

    for (gx, gy, tone) in TILE_GRIT:
        cv.set(gx, gy, tone)

    # The etch.  Isolated keeps the original four corner pads and a bare via;
    # every other mask trades a pad for a trace on each live side.
    if mask == 0:
        for (px, py) in ((Q0 + 2, Q0 + 2), (Q1 - 3, Q0 + 2),
                         (Q0 + 2, Q1 - 3), (Q1 - 3, Q1 - 3)):
            cv.rect(px, py, px + 1, py + 1, C1)
        cv.rect(LIVE - 1, LIVE - 1, RTN + 1, RTN + 1, C1)
        cv.rect(LIVE, LIVE, RTN, RTN, C2)
        cv.set(LIVE, LIVE, C3)
        return cv

    for d in DIRS:
        if has(mask, d):
            arm_line(cv, d, C2)
        elif d == W:
            cv.rect(Q0 + 2, LIVE - 1, Q0 + 3, RTN, C1)
        elif d == E:
            cv.rect(Q1 - 3, LIVE - 1, Q1 - 2, RTN, C1)
        elif d == N:
            cv.rect(LIVE - 1, Q0 + 2, RTN, Q0 + 3, C1)
        else:
            cv.rect(LIVE - 1, Q1 - 3, RTN, Q1 - 2, C1)
    cv.set(RTN, LIVE, C2)
    cv.set(LIVE, RTN, C2)
    cv.set(RTN, RTN, C1)
    cv.set(LIVE, LIVE, C3)
    return cv


# --------------------------------------------------------------------------
# BUNDLE OF CABLES -- the one that physically bends.
#
# Drawn entirely in the base sprite and entirely below the ground plane, so it
# never fights the y-sort (b13 recon Q4.4).  One 8-wide band per arm, drawn
# with the same tone table on both axes: three cables, each a lit tone over a
# hard dark one.  The dark row under each cable is doing real work -- without it
# the eight rows read as one flat grey band with a cyan stripe in it rather than
# as three round things lying next to each other.
# --------------------------------------------------------------------------

# Tone across the 8-row bundle, top to bottom (and left to right on an N/S arm).
CABLE_RUN = (BK, M4, M1, C2, C1, M3, M1, BK)


def cable_base(mask):
    cv = Canvas(FLAT_W, FLAT_H)

    if mask == 0:
        # A COILED bundle: the honest picture of a cable that goes nowhere.
        centre_block(cv, CABLE_RUN)
        cv.rect(Q0 + 3, Q0 + 3, Q1 - 3, Q1 - 3, M2)
        cv.hline(Q0 + 3, Q1 - 3, Q0 + 3, M4)
        cv.hline(Q0 + 3, Q1 - 3, Q1 - 3, M1)
        cv.rect(LIVE - 1, LIVE - 1, RTN + 1, RTN + 1, C1)
        cv.set(LIVE, LIVE, C3)
        cv.set(RTN, RTN, C2)
        return cv

    for d in (N, S, W, E):
        if has(mask, d):
            arm_band(cv, d, CABLE_RUN)

    # A CLAMP where the run actually turns or branches.  A 16px bundle cannot be
    # drawn bending through 90 degrees and still read as three round cables --
    # the clamp is the honest answer, and it keeps a STRAIGHT run completely
    # uninterrupted, which is the case the player sees most.
    straight = (mask in (A_EW, A_NS))
    if deg(mask) >= 3 or (deg(mask) == 2 and not straight):
        a, b = LIVE - 4, RTN + 4
        cv.rect(a, a, b, b, M3)
        cv.hline(a, b, a, BK)
        cv.hline(a, b, b, BK)
        cv.vline(a, a, b, BK)
        cv.vline(b, a, b, BK)
        cv.hline(a + 1, b - 1, a + 1, M4)
        cv.hline(a + 1, b - 1, b - 1, M1)
        cv.rect(LIVE - 1, LIVE - 1, RTN + 1, RTN + 1, C1)
        cv.rect(LIVE, LIVE, RTN, RTN, C2)
    else:
        for d in DIRS:
            if has(mask, d):
                arm_line(cv, d, C2)
    cv.set(LIVE, LIVE, C3)

    # ONE strap per piece, on the first arm clockwise from north and set well
    # inboard: a strap at the tile edge doubles up at every seam and turns a run
    # into a ladder.
    for d in (N, E, S, W):
        if not has(mask, d):
            continue
        if d == W:
            cv.rect(Q0 + 3, LIVE - 4, Q0 + 4, RTN + 4, W3)
            cv.vline(Q0 + 4, LIVE - 4, RTN + 4, W1)
        elif d == E:
            cv.rect(Q1 - 4, LIVE - 4, Q1 - 3, RTN + 4, W3)
            cv.vline(Q1 - 3, LIVE - 4, RTN + 4, W1)
        elif d == N:
            cv.rect(LIVE - 4, Q0 + 3, RTN + 4, Q0 + 4, W3)
            cv.hline(LIVE - 4, RTN + 4, Q0 + 4, W1)
        else:
            cv.rect(LIVE - 4, Q1 - 4, RTN + 4, Q1 - 3, W3)
            cv.hline(LIVE - 4, RTN + 4, Q1 - 3, W1)
        break

    # A ferrule capping the cut end of a stub, on the side the run came from.
    if deg(mask) == 1:
        for d in DIRS:
            if has(mask, d):
                continue
            if d == W and has(mask, E):
                cv.rect(Q0 + 5, LIVE - 4, Q0 + 6, RTN + 4, M4)
                cv.vline(Q0 + 6, LIVE - 4, RTN + 4, M1)
            elif d == E and has(mask, W):
                cv.rect(Q1 - 6, LIVE - 4, Q1 - 5, RTN + 4, M4)
                cv.vline(Q1 - 5, LIVE - 4, RTN + 4, M1)
            elif d == N and has(mask, S):
                cv.rect(LIVE - 4, Q0 + 5, RTN + 4, Q0 + 6, M4)
                cv.hline(LIVE - 4, RTN + 4, Q0 + 6, M1)
            elif d == S and has(mask, N):
                cv.rect(LIVE - 4, Q1 - 6, RTN + 4, Q1 - 5, M4)
                cv.hline(LIVE - 4, RTN + 4, Q1 - 5, M1)
    return cv


# NO GLOW ACCENT TABLE FOR THE CABLE, unlike the carpet's stitches and the
# tile's pads.  v1.3 pulsed two "taps" where the straps crossed the live strand;
# D2's arms are solid 8px bands drawn over the whole centre, so a two-pixel
# accent under one would never be seen.  The item icon still draws its own tap
# (`icon_cable`), which is where that idea now lives.


# --------------------------------------------------------------------------
# CLOUD CONNECTOR -- the one that uses both depth layers.
#
# base sprite  = a shadow on the footprint, at floor depth, STRETCHED along the
#                run so a row of clouds throws one long shadow instead of five
#                dots.  It is the only thing anchoring the piece to a tile, and
#                it costs no `shadow_manifest.json` entry -- 219 of 223 vanilla
#                rug sprites have none and the mod ships none.
# glow overlay = the cloud itself, 12 rows up the canvas, bobbing on the pulse,
#                MERGING into its east/west neighbours so a run is one bank,
#                with two charges dripping out of it toward the ground.
#
# The cloud is LINELESS in the glow.  A glow strip may only emit G1/G2/G3
# (black is not on the ramp and would survive the tint as a hole), so the form
# has to be carried by three luminance rungs alone -- which is what a cloud
# wants anyway.  The OFFLINE face has an outline, on purpose: the glow is lit
# from inside and lineless reads as luminous, while the offline face is an
# object with no light in it and needs its silhouette drawn.
#
# NORTH/SOUTH IS BRIDGED IN THE BODY TOO, and this is where the 1.3c wave
# reversed a D2 decision that reached the owner as a bug ("clouds dont connect
# from top to bottom if they are one above the other").
#
# D2 shipped the east/west merge only and left north/south to the SHADOW, on
# the argument that an east/west neighbour's body is 2px away on a 16px pitch
# while a north/south neighbour's is a full 8 ROWS off, so a north/south bridge
# would be a COLUMN, and a column of cloud reads as a tornado rather than as a
# bank.  The topology was never in doubt -- `yads_glow_side` is one AABB test
# for all four compass bits and a stacked pair sets S on the upper piece and N
# on the lower one exactly as a side-by-side pair sets E and W -- but the only
# thing the player could SEE of it was a stretch in the ground shadow twelve
# rows below the puffs and two three-pixel drips.  That reads as "not
# connected", and the player is right: the piece that says where the network
# goes is the puff.
#
# The tornado argument was about WIDTH, not about the bridge.  A 3px column
# between two 14px puffs is a tornado; a BARRELLED column that leaves the upper
# puff at its own 8px waist, bulges to 12px in the middle and lands on the
# lower puff's shoulders is a second lobe of one cumulus.  That is
# `CLOUD_BRIDGE_NS`, and each puff keeps its own shading through it, so the
# tower reads as stacked lobes rather than as one extruded pipe.
#
# BOTH ENDS DRAW THE WHOLE GAP, which is the east/west lobes' own rule (the two
# five-column lobes overlap by four columns) and it is not redundancy.  The
# overlay's eight frames are its bob, `image_index` is reset only when the
# sprite NAME changes, and two clouds whose masks were last rewritten on
# different rescans can therefore sit up to 2px apart in the bob.  A bridge
# anchored to one end only would then part company with the other; two bridges
# that each span the full gap from their OWN puff always union to a covered
# gap, whatever the phase.  Their pixels are identical whenever the phase is,
# which is the normal case, so the doubling is invisible.
#
# The SHADOW still carries the run on the ground, unchanged -- it is what
# anchors a bank to its tiles.
# --------------------------------------------------------------------------

# 14 wide, cols 9..22, so it is symmetric about the footprint's x=15.5 and sits
# two pixels inside the tile on each side.
# TWO BUMPS ON A CONTINUOUS BODY, not two separated lobes.  The first cut left
# a notch between the lumps that ran a third of the way down the sprite, and at
# 14px a notched top does not read as a cloud -- it reads as a heart.  The bumps
# now sit ON row 1, which is unbroken.
CLOUD_ROWS = (
    "....HH...HHH..",
    "..HHHHHHHHHHH.",
    ".HHHBBBBBBBBB.",
    "HHHBBBBBBBBBBB",
    "HHBBBBBBBBBBBS",
    ".HBBBBBBBBBSSS",
    "..BBBBBBBSSSS.",
    "...SSSSSSSS...",
)
CLOUD_X = 9
CLOUD_Y = 12                    # bottom row 19 -> ~12px clear of the footprint

CLOUD_GLOW_LEGEND = {"H": G3, "B": G2, "S": G1}
CLOUD_OFF_LEGEND = {"H": M4, "B": M3, "S": M3}

# A 2px bob derived from the set's own triangle wave, so the cloud rises and
# settles on the same rhythm every other glow in the mod pulses on.
CLOUD_BOB = tuple(-((p + 1) // 2) for p in PULSE)      # 0,-1,-1,-2,-2,-1,-1,0

# The shadow: half-width per row.
#
# THE BREATH IS GONE, and that is the one thing D2 cost this piece -- a VISIBLE
# change to shipped art, not an internal one, so it is written down here and not
# only in a report.  Beta 1.3's Cloud base strip was a FOUR-FRAME IDLE BOB: the
# shadow breathed in and out under the puff on its own timer.  D2 spends the base
# strip's frames on the sixteen MASKS, selected by `image_index` with
# `image_speed = 0`, so it cannot also be a four-frame idle.  The cloud still
# moves -- the bob moved INTO the overlay, which keeps all eight of its animation
# frames (`CLOUD_BOB`, applied in `cloud_glow`/`cloud_offline`) -- and the shadow
# is now drawn once, at the widest (rest) phase.  A player upgrading from 1.3
# will see the shadow stop pulsing and the cloud keep bobbing.
SHADOW_HALF = (3, 5, 6, 5, 3)
SHADOW_TOP = 31                 # rows 31..35, low in the footprint (24..39)

# The Cloud's edge midpoints, for `FLAT_EDGE_AT`'s reason and on this family's
# own geometry.  The flat three's probe row is the conductor's row; the Cloud has
# no conductor in its base sprite -- its base sprite is the SHADOW -- so the
# probe follows the shadow instead:
#
#   N / S  the two stretch rectangles run the centre pair up to CQ0 and down to
#          CQ1, so the footprint's top and bottom rows are where they show;
#   W / E  the shadow's own widest row is SHADOW_TOP + 2 (SHADOW_HALF[2] = 6),
#          which is the row that reaches Q0 / Q1 when the run continues that way
#          and stops two pixels short of both when it does not.
#
# The tone is M2, the shadow's outer tone.  Its M1 core spans only columns
# 11..20 on that row, so it can never stand in for a merged edge.
CLOUD_EDGE_AT = {N: (LIVE, CQ0), W: (Q0, SHADOW_TOP + 2),
                 E: (Q1, SHADOW_TOP + 2), S: (LIVE, CQ1)}
CLOUD_EDGE_TONE = M2

# The two east/west merge lobes, in canvas columns.  The body is 14px wide on a
# 16px pitch, so the neighbour's own art is already 2px away -- the bridge is a
# pair of stubby lobes, not a limb.
CLOUD_BRIDGE_W = (6, 10)
CLOUD_BRIDGE_E = (21, 25)

# THE NORTH/SOUTH MERGE COLUMN.
#
# TILE_PITCH is the connector footprint, 16px: `size = [2, 2]` on the engine's
# 8x8 grid cells.  The puff is 8 rows tall, so two stacked puffs leave exactly
# TILE_PITCH - len(CLOUD_ROWS) = 8 rows of sky between them, and that is what
# the column has to fill.  Everything below is derived from those two numbers
# rather than written down, so a change to either cannot leave a gap.
TILE_PITCH = 16
CLOUD_GAP = TILE_PITCH - len(CLOUD_ROWS)          # 8 rows of sky

# One (x0, x1) span per gap row, top to bottom -- and PALINDROMIC on purpose:
# the same profile is drawn upward from a puff's top and downward from a puff's
# bottom, so a stacked pair's two halves coincide pixel for pixel.
#
# It leaves the puff at 8px (the puff's own bottom row, cols 12..19), swells to
# 12px and lands at 8px again.  Read against the 14px puff: the waist never
# narrows past the puff's own bottom row, which is what stops it reading as a
# stalk, and never reaches the puff's full width, which is what keeps the two
# lobes legible instead of extruding one long pipe.
CLOUD_BRIDGE_NS = ((12, 19), (11, 20), (11, 20), (10, 21),
                   (10, 21), (11, 20), (11, 20), (12, 19))

CLOUD_DRIP_X = (12, 19)         # symmetric about 15.5
CLOUD_DRIP_TOP = 21


def cloud_bridge_ns(mask, y0):
    """The `(y, x0, x1)` spans of the north/south merge column, top to bottom.

    `y0` is the puff's own top row in this frame (bob included), so the column
    travels with the puff it is attached to.

    NORTH also gets ONE EXTRA ROW, on the puff's own top row `y0`, and it is
    not decoration: `CLOUD_ROWS[0]` is two bumps with a three-pixel NOTCH
    between them, and the notch is a hole in the silhouette -- transparent in
    the glow, black outline in the offline face.  Left alone it becomes a hole
    in the MIDDLE of a merged tower.  The extra row is drawn under the puff (
    both drawers paint the column before `blit_rows`, exactly as they already
    do for the east/west lobes), so the bumps keep their own tones and only the
    notch is filled.  SOUTH needs no such row: `CLOUD_ROWS[-1]` is a solid
    eight-pixel run with nothing to fill."""
    out = []
    if has(mask, N):
        for k, (x0, x1) in enumerate(CLOUD_BRIDGE_NS):
            out.append((y0 - CLOUD_GAP + k, x0, x1))
        out.append((y0,) + CLOUD_BRIDGE_NS[-1])
    if has(mask, S):
        for k, (x0, x1) in enumerate(CLOUD_BRIDGE_NS):
            out.append((y0 + len(CLOUD_ROWS) + k, x0, x1))
    return out


def cloud_merge_open(mask, y0):
    """`(open_rows, open_cols)` for `_halo_cells` -- the lines the offline
    face's outline must leave open so it does not cap a merge into a
    neighbouring cloud.  One line past the far end of each merge, on both axes,
    which is precisely the line the NEIGHBOUR's own puff occupies:

      N   the upper puff's bottom row,  `y0 - CLOUD_GAP - 1`
      S   the lower puff's top row,     `y0 + len(CLOUD_ROWS) + CLOUD_GAP`
      W   the west puff's right column, `CLOUD_BRIDGE_W[0] - 1`
      E   the east puff's left column,  `CLOUD_BRIDGE_E[1] + 1`

    The sides of every lobe and of the column stay outlined; only the seams
    open."""
    rows, cols = [], []
    if has(mask, N):
        rows.append(y0 - CLOUD_GAP - 1)
    if has(mask, S):
        rows.append(y0 + len(CLOUD_ROWS) + CLOUD_GAP)
    if has(mask, W):
        cols.append(CLOUD_BRIDGE_W[0] - 1)
    if has(mask, E):
        cols.append(CLOUD_BRIDGE_E[1] + 1)
    return rows, cols


def cloud_base(mask):
    """The shadow on the grass.  Two tones and a hard edge -- alpha is strictly
    binary here, so 'soft' has to be spelled with a lighter ring rather than
    with a gradient.  It STRETCHES to the footprint edge on any side a
    neighbour is on, so a run merges into one shadow."""
    cv = Canvas(CLOUD_W, CLOUD_H)
    for i, h in enumerate(SHADOW_HALF):
        y = SHADOW_TOP + i
        x0, x1 = 16 - h, 15 + h
        if has(mask, W):
            x0 = Q0
        if has(mask, E):
            x1 = Q1
        cv.hline(x0, x1, y, M2)
        # The near-black core stays under the cloud ITSELF; the merged run is
        # the softer tone only, or a five-cloud row throws a black bar.
        if h >= 2 and 0 < i < len(SHADOW_HALF) - 1:
            cv.hline(17 - h, 14 + h, y, M1)
    if has(mask, N):
        cv.rect(LIVE - 1, CQ0, RTN + 1, SHADOW_TOP + 1, M2)
    if has(mask, S):
        cv.rect(LIVE - 1, SHADOW_TOP + 3, RTN + 1, CQ1, M2)
    return cv


def cloud_glow(mask, f):
    cv = Canvas(CLOUD_W, CLOUD_H)
    p = PULSE[f]
    y0 = CLOUD_Y + CLOUD_BOB[f]

    # MERGE BRIDGES, drawn BEFORE the body so the body's own rungs win where
    # they overlap and the seam never shows a bright edge inside the bank.
    for (side, (bx0, bx1)) in ((W, CLOUD_BRIDGE_W), (E, CLOUD_BRIDGE_E)):
        if not has(mask, side):
            continue
        cv.rect(bx0, y0 + 2, bx1, y0 + 6, G2)
        cv.hline(bx0, bx1, y0 + 1, G3)

    # NORTH/SOUTH: the merge column, on the same rule and drawn at the same
    # point in the frame as the east/west lobes -- before the body, so the
    # puff's own rungs win at the join and no bright seam shows inside the
    # bank.  It replaces the pair of three-pixel drips D2 shipped here; those
    # were the whole visible north/south cue and they read as "not connected".
    #
    # SHADED LIKE THE PUFF, which is the reason the column reads as cloud
    # rather than as pipe: the set is lit from the top-left, `CLOUD_ROWS` puts
    # its G3 highlight on the left arc and its G1 shade on the right, and the
    # column carries the same left-lit / right-shaded pair down the tower.
    # Three tones, all on the G-ramp -- `audit_glow_strip` allows no fourth.
    for (by, bx0, bx1) in cloud_bridge_ns(mask, y0):
        cv.hline(bx0, bx1, by, G2)
        cv.set(bx0, by, G3)
        cv.set(bx1, by, G1)

    cv.blit_rows(CLOUD_X, y0, CLOUD_ROWS, CLOUD_GLOW_LEGEND)

    # A junction lights its own underside: the one cue that says "the charge
    # turns here" without adding a second travelling feature.
    if deg(mask) >= 2:
        cv.hline(13, 18, y0 + 3, G3 if p >= 2 else G2)

    # Two charges falling out of the cloud onto the tile, half a cycle apart.
    # Single unattached pixels, which is exactly what a glow strip is allowed
    # to have (`audit_glow_strip` runs the orphan rule off).
    for i, dx in enumerate(CLOUD_DRIP_X):
        cv.set(dx, CLOUD_DRIP_TOP + ((2 * f + 8 * i) % 16), G3)
    return cv


def cloud_offline(mask, f):
    """The same cloud bank, gone grey, with the network light guttering under
    it.  SIXTEEN OF THESE SHIP, one per mask, because the Cloud's body is the
    overlay: a shapeless offline face would snap a merged bank back to a lone
    puff the instant the heart was picked up."""
    cv = Canvas(CLOUD_W, CLOUD_H)
    y0 = CLOUD_Y + FACE_BOB[f]

    lobes = []
    for (side, (bx0, bx1)) in ((W, CLOUD_BRIDGE_W), (E, CLOUD_BRIDGE_E)):
        if has(mask, side):
            lobes.append((bx0, bx1))
    column = cloud_bridge_ns(mask, y0)

    cells = _rows_cells(CLOUD_X, y0, CLOUD_ROWS)
    for (bx0, bx1) in lobes:
        for by in range(y0 + 1, y0 + 7):
            for bx in range(bx0, bx1 + 1):
                cells.append((bx, by))
    for (by, bx0, bx1) in column:
        for bx in range(bx0, bx1 + 1):
            cells.append((bx, by))
    (open_rows, open_cols) = cloud_merge_open(mask, y0)
    _halo_cells(cv, cells, open_rows, open_cols)

    for (bx0, bx1) in lobes:
        cv.rect(bx0, y0 + 2, bx1, y0 + 6, M3)
        cv.hline(bx0, bx1, y0 + 1, M4)
    # The merge column, offline: the same geometry the glow uses, in the
    # offline face's own two tones (M4 is this palette's highlight, M3 its
    # body).  Before `blit_rows` for the lobes' reason.
    for (by, bx0, bx1) in column:
        cv.hline(bx0, bx1, by, M3)
        cv.set(bx0, by, M4)
    cv.blit_rows(CLOUD_X, y0, CLOUD_ROWS, CLOUD_OFF_LEGEND)

    # The guttering network light under the bank -- two pinpricks, 4-connected
    # to the body's bottom row so the offline strip's orphan rule has nothing
    # to find.
    #
    # A SOUTH NEIGHBOUR NOW SUPPRESSES IT ENTIRELY, where D2 drained it across
    # the full centre pair.  That row is the merge column's first row now: a
    # cyan line drawn there would sit INSIDE the merged tower, which is the one
    # place a "the light stops here" cue must never appear.  The bank continues
    # southward and says so with body, not with light.  Bit S still changes the
    # image (the column is there instead), so the sixteen offline variants stay
    # sixteen distinct files.
    if not has(mask, S):
        ry = y0 + len(CLOUD_ROWS)
        cv.set(LIVE - 1, ry, C1)
        cv.set(RTN + 1, ry, C1)
    return cv


# --------------------------------------------------------------------------
# THE FLAT PIECES' OVERLAYS.
#
# One drawer for all three: the identity is in the BODY, the network marking is
# the set's, and three connectors in a row must look like one path even when
# the player mixed carpet, tile and cable in it.  The only per-piece freedom is
# the two-to-four `accent` pixels, which are always pixels the body itself
# already puts somewhere meaningful (a stitch, a pad).
# --------------------------------------------------------------------------


def spill(cv, mask, f, tone=G1):
    """Dashed light lying ON THE FLOOR either side of each live arm.

    The first cut put this rim on the tile's outer edge instead, and a run of
    them was a sheet of marching ants: every tile got a dotted box, the boxes
    abutted in pairs, and the eye read a grid of separate objects, which is the
    exact opposite of the one thing these pieces exist to communicate.  Hugging
    the wire instead makes a 3px-wide soft line that keeps running when the next
    tile starts -- and under D2 it only runs where an arm does."""
    for i in range(Q0, Q1 + 1):
        if (i + f) % 2:
            continue
        if (has(mask, W) and i <= LIVE) or (has(mask, E) and i >= LIVE):
            cv.set(i, LIVE - 1, tone)
            cv.set(i, LIVE + 1, tone)
        if (has(mask, N) and i <= LIVE) or (has(mask, S) and i >= LIVE):
            cv.set(LIVE - 1, i, tone)
            cv.set(LIVE + 1, i, tone)


def flat_glow(mask, f, accent=()):
    """A soft under-light along the same path the body already draws: dim,
    narrow, and only on the arms that exist."""
    cv = Canvas(FLAT_W, FLAT_H)
    p = PULSE[f]
    t = SEAM_G[p]

    if mask == 0:
        # Isolated: a lone via, no line at all -- nothing to run along.
        cv.rect(LIVE - 1, LIVE - 1, RTN + 1, RTN + 1, G1)
        cv.rect(LIVE, LIVE, RTN, RTN, t)
        cv.set(LIVE, LIVE, GTONE[p])
        return cv

    # The under-light is DIM AND NARROW on purpose: the body already draws the
    # path, so a second bright line over it is two drawings of one thing.  One
    # rung below the crate seam's own swing, still inside SEAM_G.
    spill(cv, mask, f)
    for d in DIRS:
        if has(mask, d):
            arm_line(cv, d, SEAM_G[max(p - 1, 0)])
    cv.set(RTN, LIVE, G1)
    cv.set(LIVE, RTN, G1)
    cv.set(LIVE, LIVE, GTONE[max(p - 1, 0)])

    # ONE travelling charge per axis, 2px per frame, in GLOBAL tile phase: a
    # 4px swell rather than v1.3's hard 2px spark, so it is dimmer on half the
    # cycle and still leaves this tile exactly as the next tile's swell leaves
    # that one.  8 frames x 2px == the tile's own 16px.
    s = Q0 + 2 * f
    for k in range(s, min(s + 4, Q1 + 1)):
        if (has(mask, W) and k <= LIVE) or (has(mask, E) and k >= LIVE):
            cv.set(k, LIVE, GTONE[p])
        if (has(mask, N) and k <= LIVE) or (has(mask, S) and k >= LIVE):
            cv.set(LIVE, k, GTONE[p])

    # Accents, half a cycle out of phase with the spill.
    dp = PULSE[(f + GLOW_LEN // 2) % GLOW_LEN]
    if dp >= 1:
        for (ax, ay) in accent:
            cv.set(ax, ay, GTONE[dp])
    return cv


def flat_offline(mask, f):
    """A dead pad at the crossing -- SHAPELESS, and deliberately so.

    Under D2 the BODY carries the path, and the body is still drawn when the
    network is down: a stranded run still reads as a run, it just is not lit.
    So the offline overlay has exactly one job -- put the via out -- and it does
    it with one marker that is correct for all sixteen masks, which is why the
    flat three ship ONE `_offline` strip and no variants.

    Deliberately IDENTICAL in all four frames.  The strip has four because
    `OFFLINE_LEN`/`OFFLINE_DUR` are a set-wide contract -- the runtime swaps
    `sprite_index` on one renderer between an 8-frame glow and this -- but a
    connector that has lost the network is not doing anything, and thirty
    stranded tiles blinking in unison is precisely the strobe this whole file
    is written to avoid."""
    cv = Canvas(FLAT_W, FLAT_H)
    cv.rect(LIVE - 2, LIVE - 2, RTN + 2, RTN + 2, BK)
    cv.rect(LIVE - 1, LIVE - 1, RTN + 1, RTN + 1, M3)
    cv.rect(LIVE, LIVE, RTN, RTN, C1)
    return cv


# --------------------------------------------------------------------------
# 18x18 ITEM ICONS -- miniatures of the same construction, not downscales, and
# symmetric about x = 8.5 like every other icon in the set.
#
# UNTOUCHED BY D2.  An icon is the thing in your hand: it has no neighbours, so
# it has no mask, and `outlines.json` names all four of them by string.
# --------------------------------------------------------------------------

ICON_W = 18
ICN_LIVE, ICN_RTN = 8, 9        # the icons' own conductor pair, centred on 8.5


def icon_carpet():
    """The rug, laid flat, with fringe -- the one silhouette cue that says
    TEXTILE at 18px and cannot be confused with the tile's slab."""
    cv = Canvas(ICON_W, ICON_W)
    x0, x1, y0, y1 = 2, 15, 3, 15
    cv.hline(x0, x1, y0, BK)
    cv.hline(x0, x1, y1, BK)
    cv.vline(x0, y0 + 1, y1 - 1, BK)
    cv.vline(x1, y0 + 1, y1 - 1, BK)
    cv.hline(x0 + 1, x1 - 1, y0 + 1, W4)
    cv.vline(x0 + 1, y0 + 2, y1 - 2, W4)
    cv.hline(x0 + 1, x1 - 1, y1 - 1, W1)
    cv.vline(x1 - 1, y0 + 2, y1 - 2, W1)
    _weave(cv, x0 + 2, y0 + 2, x1 - 2, y1 - 2)
    # fringe: three tassels a side, two pixels long, each 4-connected to the
    # rug's own hem so the orphan audit has nothing to find.  Three, not four --
    # four evenly spaced tassels read as legs and turned the rug into a table.
    for fy in (y0 + 3, (y0 + y1) // 2, y1 - 3):
        cv.hline(0, 1, fy, W3)
        cv.hline(16, 17, fy, W1)
    # the thread: 1px, for the world sprite's reason
    cv.hline(x0, x1, ICN_LIVE + 1, C2)
    cv.vline(ICN_LIVE, y0, y1, C2)
    cv.set(ICN_RTN, ICN_LIVE + 1, C2)
    cv.set(ICN_LIVE, ICN_RTN + 1, C2)
    cv.set(ICN_LIVE, ICN_LIVE + 1, C3)
    return cv


def icon_tile():
    """The flagstone with its thickness showing, so it reads as a slab you set
    down rather than as a painted square."""
    cv = Canvas(ICON_W, ICON_W)
    # top face
    cv.hline(4, 13, 2, BK)
    cv.vline(3, 3, 10, BK)
    cv.vline(14, 3, 10, BK)
    cv.rect(4, 3, 13, 10, M3)
    cv.hline(4, 13, 3, M4)
    cv.vline(4, 3, 10, M4)
    cv.hline(4, 13, 10, M1)
    cv.vline(13, 4, 10, M1)
    cv.hline(3, 14, 11, BK)
    # the slab's front edge, one pixel wider on each side for perspective
    cv.vline(2, 12, 14, BK)
    cv.vline(15, 12, 14, BK)
    cv.rect(3, 12, 14, 13, M2)
    cv.hline(3, 14, 14, M1)
    cv.hline(3, 14, 15, BK)
    # the etch: four pads, the conductor and the via
    for (px, py) in ((5, 4), (12, 4), (5, 9), (12, 9)):
        cv.set(px, py, C1)
    cv.hline(3, 14, 6, C2)
    cv.vline(ICN_LIVE, 2, 11, C2)
    cv.set(ICN_RTN, 6, C2)
    cv.set(ICN_LIVE, 7, C2)
    cv.set(ICN_RTN, 7, C1)
    cv.set(ICN_LIVE, 6, C3)
    return cv


# The three strands, leaving the bundle's left edge and fanning out.  Written
# as explicit 4-CONNECTED staircases rather than as diagonals: the orphan audit
# pairs a pixel with its edge neighbours only, so a true diagonal is a line of
# orphans, and at 18px a staircase and a diagonal are the same picture anyway.
# Mirrored to the right by x -> 17 - x, so the icon stays symmetric about 8.5
# like every other one in the set.
_ICON_FAN_UP = ((5, 7), (4, 7), (4, 6), (3, 6), (3, 5), (2, 5), (2, 4),
                (1, 4), (0, 4))
_ICON_FAN_DOWN = ((5, 11), (4, 11), (4, 12), (3, 12), (3, 13), (2, 13),
                  (2, 14), (1, 14), (0, 14))


def icon_cable():
    """Three cables gathered into a strap and fanning out at both ends.

    The first cut drew the bundle running edge to edge with a rounded plug on
    each side, and at 18px that is a battery: one capsule, one band.  What says
    CABLE is strands that separate -- the fan is the whole icon, and the middle
    strand staying cyan while the outer two go slate is what says which one of
    them is the network."""
    cv = Canvas(ICON_W, ICON_W)
    # the strapped bundle, rows 6..13
    for i, tone in enumerate(CABLE_RUN):
        cv.hline(6, 11, 6 + i, tone)
    # The fan, both ends, TWO PIXELS THICK -- shadow pass first so a staircase
    # never paints shade over its own highlight.  1px strands read as legs and
    # turned the icon into an insect; 2px reads as cable.
    for (fx, fy) in _ICON_FAN_UP + _ICON_FAN_DOWN:
        cv.set(fx, fy + 1, M2)
        cv.set(17 - fx, fy + 1, M1)
    for (fx, fy) in _ICON_FAN_UP + _ICON_FAN_DOWN:
        cv.set(fx, fy, M4)
        cv.set(17 - fx, fy, M3)
    cv.hline(0, 5, ICN_LIVE + 1, C2)            # the live strand runs straight
    cv.hline(12, 17, ICN_LIVE + 1, C2)
    cv.hline(0, 5, ICN_RTN + 1, C1)
    cv.hline(12, 17, ICN_RTN + 1, C1)
    # the strap, and the tap where it crosses the live strand
    cv.hline(7, 10, 5, BK)
    cv.hline(7, 10, 14, BK)
    for y in range(6, 14):
        cv.set(7, y, W3)
        cv.set(8, y, W2)
        cv.set(9, y, W1)
        cv.set(10, y, W1)
    cv.set(7, ICN_LIVE + 1, C3)
    return cv


def icon_cloud():
    """The puff with its underlight and three drips.  The only icon in the set
    with no ground under it, which is the point: this is the connector that
    does not touch the floor."""
    cv = Canvas(ICON_W, ICON_W)
    # the SAME 14x8 bitmap the world overlay uses, on a different legend: grey
    # body, cyan underside.  One drawing, two readings -- the world sprite is
    # the thing lit from inside, the icon is the thing you are holding.
    _halo(cv, 2, 2, CLOUD_ROWS)
    cv.blit_rows(2, 2, CLOUD_ROWS, {"H": M4, "B": M3, "S": C2})
    cv.hline(5, 12, 9, C3)                  # the underlight, brightest
    # three drips, hanging off the cloud so each one is 4-connected to it
    for (dx, dh) in ((5, 3), (12, 3)):
        cv.vline(dx, 10, 9 + dh, C2)
        cv.set(dx, 9 + dh, C3)
    cv.vline(8, 10, 11, C2)
    cv.set(8, 11, C3)
    cv.vline(9, 10, 11, C2)
    cv.set(9, 11, C3)
    return cv


# --------------------------------------------------------------------------
# THE REGISTRY.
#
# `make_art.py` loops over CONNECTORS exactly as it loops over
# `crates.FAMILIES`.  Every name below is save-serialized BY STRING the moment
# it ships (the object prototype names the sprites, `outlines.json` names the
# icon, and `network.gml` derives the `_offline` and `_glow_v<n>` names from the
# slug), so this table is a freeze list, not a convenience.
# --------------------------------------------------------------------------

SPRITE_PREFIX = "spr_furniture_netstor_"
ICON_PREFIX = "spr_ui_item_netstor_"

# The two suffixes the RUNTIME builds by hand.  They are spelled once here and
# once in `yads_ids()` (network.gml section 1); if they ever have to change,
# both spellings change in the same commit or the variant tables resolve to
# undefined and every connector silently falls back to its isolated pose.
GLOW_VARIANT_SUFFIX = "_glow_v"
OFFLINE_VARIANT_SUFFIX = "_offline_v"


def world_sprite(slug):
    return SPRITE_PREFIX + slug


def glow_sprite(slug):
    return SPRITE_PREFIX + slug + "_glow"


def glow_variant_sprite(slug, mask):
    return SPRITE_PREFIX + slug + GLOW_VARIANT_SUFFIX + str(mask)


def offline_sprite(slug):
    return SPRITE_PREFIX + slug + "_offline"


def offline_variant_sprite(slug, mask):
    return SPRITE_PREFIX + slug + OFFLINE_VARIANT_SUFFIX + str(mask)


def icon_sprite(slug):
    return ICON_PREFIX + slug


class Connector(object):
    """One connector: a 16-frame autotile body, 16 glow variant strips (plus the
    unsuffixed `_glow` the prototype names), an offline face, one icon, one
    canvas, one pivot.

    `offline_variants` is True for the Cloud alone -- see `cloud_offline`."""

    __slots__ = ("slug", "title", "canvas", "pivot", "base_len", "base_dur",
                 "base", "glow", "offline", "icon", "offline_variants",
                 "edge_at", "edge_tone")

    def __init__(self, slug, title, canvas, pivot, base, glow, offline, icon,
                 offline_variants=False, edge_at=None, edge_tone=None):
        self.slug = slug
        self.title = title
        self.canvas = canvas
        self.pivot = pivot
        # `make_art.py` reads these two the way it reads them for every other
        # strip in the mod.  The body's "length" is the mask space, not a time.
        self.base_len = MASK_LEN
        self.base_dur = BODY_DUR
        self.base = base
        self.glow = glow
        self.offline = offline
        self.icon = icon
        self.offline_variants = offline_variants
        # Where `audit_autotile_body` reads this family's frames back, and the
        # tone it must find there.  Required, not defaulted: a family that
        # forgets them would silently ship an unaudited bit order, which is the
        # one thing these two fields exist to make impossible.
        if edge_at is None or edge_tone is None:
            raise ValueError("%s: a connector must declare edge_at/edge_tone "
                             "so its autotile bit order can be audited" % slug)
        self.edge_at = edge_at
        self.edge_tone = edge_tone

    # -- the strips, as lists of Canvas ---------------------------------------

    def base_frames(self):
        """The autotile strip: frame index IS the adjacency mask."""
        return [self.base(m) for m in range(MASK_LEN)]

    def glow_frames(self, mask=0):
        return [self.glow(mask, f) for f in range(GLOW_LEN)]

    def offline_frames(self, mask=0):
        return [self.offline(mask, f) for f in range(OFFLINE_LEN)]

    def offline_masks(self):
        """Which masks get their own `_offline_v<n>` strip.  Empty for the flat
        three: their body carries the shape, so one marker serves every mask."""
        return range(MASK_LEN) if self.offline_variants else range(0)

    def bounds(self):
        """The union of every opaque pixel this connector can ever draw.

        The three units and the crate families size their one Shape to the
        RESTING pose, because for them every other pose is inside it.  That is
        false here twice over: the Cloud's body lives in the overlay, twelve
        rows above anything its base sprite paints, and under D2 the carpet's
        fringe leaves the footprint on whichever side the run ends.  Union is
        the same rule -- 'a box around what this thing is' -- evaluated
        correctly for a two-layer sprite with sixteen poses."""
        box = None
        strips = [self.base_frames()]
        for m in range(MASK_LEN):
            strips.append(self.glow_frames(m))
        for m in self.offline_masks():
            strips.append(self.offline_frames(m))
        strips.append(self.offline_frames(0))
        for frames in strips:
            for cv in frames:
                b = cv.im.getbbox()
                if b is None:
                    continue
                box = b if box is None else (min(box[0], b[0]),
                                             min(box[1], b[1]),
                                             max(box[2], b[2]),
                                             max(box[3], b[3]))
        return box


def _flat(slug, title, base, accent):
    return Connector(slug, title, (FLAT_W, FLAT_H), FLAT_PIVOT,
                     base,
                     lambda m, f, a=accent: flat_glow(m, f, a),
                     flat_offline,
                     {"link_carpet": icon_carpet,
                      "link_tile": icon_tile,
                      "link_cables": icon_cable}[slug],
                     edge_at=FLAT_EDGE_AT, edge_tone=FLAT_EDGE_TONE)


CARPET = _flat("link_carpet", "Magic Carpet", carpet_base, CARPET_STITCH)
TILE = _flat("link_tile", "Magic Tile", tile_base, TILE_PAD)
# The cable takes NO accent: D2's bundle is a solid 8px band and any accent
# under it would be invisible.
CABLE = _flat("link_cables", "Bundle of Cables", cable_base, ())
CLOUD = Connector("link_cloud", "Cloud Connector", (CLOUD_W, CLOUD_H),
                  CLOUD_PIVOT, cloud_base, cloud_glow, cloud_offline,
                  icon_cloud, offline_variants=True,
                  edge_at=CLOUD_EDGE_AT, edge_tone=CLOUD_EDGE_TONE)

CONNECTORS = (CARPET, TILE, CABLE, CLOUD)


# --------------------------------------------------------------------------
# THE OFFLINE AUDIT.
#
# `_kit.audit_offline_strip` is the SAD-FACE audit: it checks a hovering thought
# bubble stays clear of the body it hovers over and keeps the same size in every
# bobbed frame.  A connector's offline face is not a bubble -- three of them are
# a dead pad lying on the floor and the fourth is the object itself gone grey
# -- so applying it would be checking rules none of these art has.
#
# What DOES carry over, and is enforced here, is everything that is about the
# strip rather than about the bubble: binary alpha, the four-tone offline
# palette, and no empty frame (an all-transparent offline strip would ship a
# connector that disappears the moment it loses the network, which for the
# Cloud is literally true because its whole body lives in the overlay).
# --------------------------------------------------------------------------

OFFLINE_TONES = (BK, M4, M3, C1)


def audit_link_offline_strip(name, im, frame_w):
    problems = audit(name, im, orphans=True, frame_w=frame_w)
    tones = count_tones(im)
    if len(tones) > len(OFFLINE_TONES):
        problems.append("%s: %d tones, the offline palette is BK/M4/M3/C1"
                        % (name, len(tones)))
    for t in sorted(tones):
        if t not in OFFLINE_TONES:
            problems.append("%s: off-palette offline tone %s -- a connector's "
                            "offline face is BK / M4 / M3 / C1"
                            % (name, str(t[:3])))
    n = im.width // frame_w
    for i in range(n):
        fr = im.crop((i * frame_w, 0, (i + 1) * frame_w, im.height))
        if fr.getbbox() is None:
            problems.append("%s: frame %d is entirely transparent -- this "
                            "connector would VANISH when it goes offline"
                            % (name, i))
    return problems


# --------------------------------------------------------------------------
# THE AUTOTILE AUDIT -- the rules that only exist because there are sixteen.
# --------------------------------------------------------------------------


def audit_autotile_body(name, im, frame_w, canvas_w, edge_at, edge_tone):
    """The body strip must have exactly MASK_LEN frames, in mask order, no frame
    may be empty, and EVERY FRAME MUST AGREE WITH ITS OWN INDEX.

    An empty frame is not a cosmetic problem: `image_index = mask` would put a
    connector on screen as nothing at all, and the player would read a piece they
    had just placed as having failed to place.

    THE THIRD RULE IS THE ONE WITH TEETH.  Width and non-emptiness are satisfied
    by any sixteen frames in any order, so they cannot see the failure this whole
    system is most exposed to: a transposed bit.  Swap N and S -- or W and E --
    anywhere between `DIRS`, a drawer's `op[]` reads and the runtime's
    `1*N + 2*W + 4*E + 8*S`, and every audit in this file still passes while
    every connector on the farm grows its arms toward the wrong neighbours.  The
    engine cannot catch it either: `renderer.image_index = mask` is correct
    whatever the frame at that index happens to draw.

    So each frame is read back at the four points where an arm would cross the
    tile edge (`edge_at`, this family's own geometry) and the conductor's tone
    (`edge_tone`) must be present there exactly when that frame's bit is set.
    Sixty-four assertions per connector, and a transposition breaks half of
    them."""
    problems = []
    if im.width != canvas_w * MASK_LEN:
        problems.append("%s: %d px wide, expected %d (%d masks x %d)"
                        % (name, im.width, canvas_w * MASK_LEN, MASK_LEN,
                           canvas_w))
        return problems
    for m in range(MASK_LEN):
        fr = im.crop((m * frame_w, 0, (m + 1) * frame_w, im.height))
        if fr.getbbox() is None:
            problems.append("%s: mask %d (frame %d) is entirely transparent -- "
                            "that connector would be INVISIBLE at that "
                            "adjacency" % (name, m, m))
            continue
        px = fr.load()
        for d in DIRS:
            (ex, ey) = edge_at[d]
            drawn = (px[ex, ey] == edge_tone)
            wanted = has(m, d)
            if drawn != wanted:
                problems.append(
                    "%s: mask %d draws %s arm at its %s edge midpoint "
                    "(%d,%d) but the mask says %s -- the frame and its own "
                    "index disagree, which is a transposed autotile bit"
                    % (name, m, "an" if drawn else "NO", DIRNAME[d], ex, ey,
                       "it is there" if wanted else "it is not"))
    return problems
