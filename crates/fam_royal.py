#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""fam_royal -- the six royal chests.

Six palettes (blue, dark_wood, green, purple, red, wood) of one ornate drawing:
40x48, pivot 16/24, lid_band 11..31 -- the deepest lid band of any of these
three families -- so lid_safe sits at 32 and the generic glow gets only 7 rows
(32..38) to trace. Small budget, but this chest is the gold-plated one of the
set: a brass corner post runs the full height of both sides and a brass lock
plate sits on the front, so hardware is not in short supply.

THE DIODES.  Same trap as `deluxe`, checked the same way before trusting it:
the lock plate (rows ~27-33, the keyhole cutout, brightest at `#ffffff`) is
carried on the lid's front lip, and vanishes into flat body colour the moment
the sprite switches to `_opened` -- row 32, cols 13/14, are the plate's brass
`#ffc13b` in `_main_closed` and the wood/blue-variant's own body tone in
`_main_opened`. Not a candidate.

The corner post is: read straight from the archive
(`spr_furniture_royal_chest_{wood,blue,red}_main_{closed,opened}`), pixel-for-
pixel identical across every palette and both poses:

    row 33   x=5  #de8240      row 33   x=26 #de8240   (mirror: CENTRE=15.5,
    row 36   x=5  #feed68      row 36   x=26 #feed68     31-5=26)

Row 36's `#feed68` is the single brightest tone on the whole chest short of
the lock's keyhole highlight -- the corner post's top gilt cap -- so the
diodes sit on the most obviously "gold fitting" pixels available, exactly the
kind of candidate the brief expects this family to hand over easily. Both rows
are comfortably inside `lid_safe` (32..38 is the whole safe band; these are
33 and 36).
"""

from crates import _kit as kit

# Every twinned chest of the family, exactly as `crates/_geom.py` lists them.
MEMBERS = [
    "royal_chest_blue",
    "royal_chest_dark_wood",
    "royal_chest_green",
    "royal_chest_purple",
    "royal_chest_red",
    "royal_chest_wood",
]

REP = "royal_chest_wood"

PARAMS = kit.GlowParams(diodes=((5, 33), (26, 33), (5, 36), (26, 36)))
