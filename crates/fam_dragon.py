#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""fam_dragon -- the Dragon Chest.  A singleton: one member, one drawing.

40x48, pivot 16/24 (its vanilla meta writes `vertical = "Middle"`; `_geom.py`
has already resolved that to the number 24.0 -- see the PIVOTS ARE NUMBERS
note there.  This file never reads the raw meta, only `_geom`, so the trap
does not reach here).  The lid band is unusually tall, rows 6..27: the whole
ornate upper two-thirds of the chest -- both claw pairs and the central
gem-latch -- swings with the lid, which is why `lid_safe` lands as far down
as row 28 and the generic drawer gets only 11 rows of stable silhouette
(`glow_rows=11`), all of it the plain rectangular base (`rim` is `(y, 3, 28)`
for every one of those 11 rows -- no taper at all, unlike a basic chest's
rounded corners).

THE DIODES.  Read off the actual pixels of `spr_decor_dragon_chest_spring_*`
(closed/opened/opening all agree byte-for-byte at these coordinates -- checked
directly, not assumed): the chest has FOUR gilt claw-feet, one at each lower
corner, and each foot's upper knuckle sits at row 28 (widest, brightest gold,
#da9734/#b47124) with its shadowed underside at row 29 (#53270b, the same dark
gold-edge tone on both feet). Both rows are >= lid_safe (28), and both are
inside `geom.rim`'s row-28..38 rectangle. The four points are the two
knuckles + their shadow pixels, symmetric about the pivot (col 5 and col 26
are each 10.5px from centre 15.5):

    (5, 28)   (26, 28)     -- knuckle highlight, brightest gold on the foot
    (5, 29)   (26, 29)     -- knuckle shadow, dark gold-edge tone

Deliberately NOT the central gem-latch (cols 13..18): it reads beautifully in
the closed pose but is mounted on the LID -- in the opened frame it is up at
rows 10..13, nowhere near row 28..29 -- so a diode there would float in mid-
air the instant the chest opens. Also not the upper claw pair (rows 11..16)
or the middle claw pair (rows 22..27): both are inside the lid band and
disappear from these absolute rows the moment the lid swings.
"""

from crates import _kit as kit

MEMBERS = [
    "dragon_chest",
]

REP = "dragon_chest"

PARAMS = kit.GlowParams(diodes=((5, 28), (26, 28), (5, 29), (26, 29)))
