#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""fam_stone -- the three stone storage chests.

Three palettes (v1 warm tan, v2 cooler tan, v3 blue-grey) of one carved-block
drawing: 40x48, pivot 16/28, lid_band 12..25, lid_safe 26, 13 rows of rim to
trace (26..38) -- a comfortable budget, on par with basic_wood.

THE DIODES -- THE ONE FAMILY WITH NO METAL AT ALL.  Every other family in
Beta 1.3 hangs its diodes on an applied fitting (a rivet, a hasp, a corner
brass post); this crate is carved stone from the lid to the foot and the
archive confirms there is nothing metal anywhere on it -- no rivets, no
hinges, no lock plate, in any of the three palettes.  Forcing a rivet onto
bare rock would be inventing hardware that is not there, so the diodes sit on
the nearest DEFENSIBLE substitute: the quoins, the visibly reinforced corner
blocks that run down both sides of the case, cut in a plainly darker stone
than the flat face between them -- read directly off the pixels, not assumed:

    v1 face fill   #c9b894 / #e4d8b7      v1 quoin   #8c765b
    v2 face fill   #b1a192 / #c7b9ab      v2 quoin   #87786e
    v3 face fill   #acafbb / #989dac      v3 quoin   #63697a / #63697a

-- the same darker-corner relationship in all three palettes, i.e. a real
carved feature and not a one-off shading accident. Diode rows chosen where the
quoin colour is stable pixel-for-pixel between `_closed` and `_opened` (row 30
was tried first and rejected: it differs between poses in all three palettes,
because the opened pose's interior reveal reaches that high):

    row 31   x=6  quoin        row 31   x=25 quoin   (mirror: CENTRE=15.5,
    row 33   x=6  quoin        row 33   x=25 quoin     31-6=25)

verified identical `_main_closed` vs `_main_opened` at all four coordinates in
v1, v2 and v3 alike, both rows well inside `lid_safe` (26). The read: two
lantern-like points glowing from the case's stone corner reinforcements rather
than from any fitting -- the honest alternative for a crate that was simply
never built with metal parts.
"""

from crates import _kit as kit

# Every twinned chest of the family, exactly as `crates/_geom.py` lists them.
MEMBERS = [
    "stone_storage_chest_v1",
    "stone_storage_chest_v2",
    "stone_storage_chest_v3",
]

REP = "stone_storage_chest_v1"

PARAMS = kit.GlowParams(diodes=((6, 31), (25, 31), (6, 33), (25, 33)))
