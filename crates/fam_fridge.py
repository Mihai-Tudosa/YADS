#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""fam_fridge -- the cottage fridge, 2 palettes (oak / ash).

`spr_furniture_cottage_fridge_v1/v2_main_*` -- a single-door appliance, but
NOT canvas-centred: 32x56 with pivot (12.0, 45.0), against a 32-wide canvas
whose midpoint is 16.  The door hinges on the right and swings out over the
LEFT two-thirds of the canvas, so the family's content sits left of centre --
the reason `crates/_kit.py` grew `face_origin_x()` (it derives the bubble
column from the pivot, never from canvas width, precisely for this member).
A glow author has the same trap: `geom.rim` already encodes the true
per-row silhouette, so nothing here hardcodes a centre either.

Like `icebox`, `lid_band=(None, None)` -- the door swings entirely within the
closed footprint, so `lid_safe` is `top_all` (8) and the full 38-row body is
silhouette-safe.  Same tall-body reasoning as `fam_icebox.py` applies to the
drop tuning; see that file for the arithmetic.
"""

from crates import _kit as kit

MEMBERS = [
    "cottage_fridge_v1",
    "cottage_fridge_v2",
]

REP = "cottage_fridge_v1"

# ---------------------------------------------------------------------------
# Same tall-body scaling as fam_icebox.py: glow_rows=38, base_row=45,
# top_all=8 -- identical geometry budget, so the identical 13/24 split keeps
# the two appliance families reading as one visual register instead of one
# looking top-heavy against the other.
#
# THE DIODES.  Verified against the archive frames (cottage_fridge_v1_main_
# closed.png / _opened.png):
#
# The door's own latch (the hook-shaped handle at rows 27-30, columns 3-7 in
# the closed pose) is on the door leaf itself and swings with it -- gone in
# the opened frame at those coordinates, same failure as the icebox's door
# handles.  The drawer pull-handle below it (rows 36-39) is the surviving
# fitting, but this body is narrower and its door swings across MORE of the
# drawer's own row band than the icebox's doors do (the fridge is a single
# wide door, not two), so only its LEFT edge stays clear of the swung-open
# door in the OPENED frame.  Read pixel-for-pixel off both frames: (8,36)
# and (9,36) are solid #8f6c61 -- the warm mid-grey/tan hardware tone, against
# the e2ceb7 cream body -- in the closed frame AND in the opened frame,
# unchanged.  Both columns sit inside the handle's mounting bracket, one row
# below its outline top, so the pair reads as the visible left post of the
# drawer pull rather than as two stray pixels.
PARAMS = kit.GlowParams(
    drop0=13,
    drop1=24,
    diodes=((8, 36), (9, 36)),
)
