#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""fam_void -- the void storage chest, 2 palettes.

`spr_furniture_void_chest_v1/v2_main_*` -- a proper hinged chest, not an
appliance: `lid_band=(13, 32)` moves like basic_wood's, but the lid swings
much further open (rows 13-32, twenty rows) leaving only `glow_rows=6` --
the smallest budget of any family bar mist's zero.  Verified directly
against the archive: rows 33-38 are byte-identical between the closed and
opened frames (the band `crates/_geom.py` measured never differs), so the
generic rim/under-glow/seam and the diodes below all sit on a strip of the
chest's own base that is guaranteed stable, not merely "probably fine
because it's low."

THE AESTHETIC.  The rest of the family is a near-black chest with a
magenta/violet jewelled trim (`#ab57d6` etc.) rather than basic_wood's iron
straps -- there is no literal rivet to point at, so the diodes below are
placed on the closest equivalent this body actually has: the two bright
corner-post studs that are already part of the vanilla art, one either side
of the front, present unchanged in both poses.  Because the budget is so
small and the body so dark, the connected glow is left at the generic
drawer's defaults rather than pushed brighter -- six rows of rim is already
a third of the chest's total height, and this family is meant to still read
as a void chest first and a lit network node second.
"""

from crates import _kit as kit

MEMBERS = [
    "void_storage_chest_v1",
    "void_storage_chest_v2",
]

REP = "void_storage_chest_v1"

# ---------------------------------------------------------------------------
# THE DIODES.  Verified against the archive frames (void_storage_chest_v1_
# main_closed.png / _opened.png): rows 33-38 are pixel-identical between the
# two poses (confirmed by direct diff, not inferred from lid_band alone), so
# every candidate below is safe in both by construction.  The two chosen
# points are the brightest pixel of the chest's own jewelled corner-post
# trim -- #ab57d6, the same magenta accent used the whole way up the body's
# vertical banding -- at the row where that trim reads as a single isolated
# stud rather than as part of a taller vertical run, so it plausibly pulses
# on its own instead of looking like it is cutting a larger shape in half.
# Symmetric either side of centre (x=15.5), echoing basic_wood's two-strap
# pairing without inventing hardware this body does not have.
PARAMS = kit.GlowParams(diodes=((7, 36), (25, 36)))
