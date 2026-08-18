#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""fam_flower -- the Spring Festival Flower Chest.  A singleton: one member.

Split out of `basic_wood` on purpose (art recon): it shares that family's
40x48 canvas, pivot and near-identical silhouette (`closed_bbox` differs by a
couple of pixels), but it is a completely different drawing -- a quilted
pink-and-gold lattice, not plain planks -- so a palette-swap assumption would
have painted the wrong picture. Treated here as its own thing, per the brief:
its `PARAMS` is authored from its OWN pixels, not copied from basic_wood's.

40x48, pivot 16/24 (its vanilla meta also writes `vertical = "Middle"`;
`_geom.py` resolves that to 24.0 -- see the module docstring there. As with
`dragon`, this file only ever reads the resolved `_geom` number). lid_band is
14..19, so `lid_safe` is 20 and the generic drawer gets 18 rows of stable
silhouette, the same generous budget as basic_wood.

THE DIODES.  The chest is edged top-to-bottom on both sides by a woven gold
trim band (cols 6..7 left, cols 25..26 right -- read directly off
`spr_decor_spring_festival_flower_chest_spring_*`), distinct from both the
pink quilting and the gold lattice-crossing squares further in. The band's
exact shade cycles row-to-row (it is woven, not flat) and even shifts
slightly between poses at some rows, but at rows 34 and 35 it lands on the
IDENTICAL RGB (#e6b944) in the closed, opened and opening frames alike --
checked pixel-for-pixel, not assumed -- which is as solid a "this is the same
physical trim on every pose" guarantee as `lid_safe` (20) allows this far
below the lid. Both rows sit inside `geom.rim`'s row-34/35 span (cols 5..27),
and cols 6/25 are symmetric about the pivot (9.5px either side of 15.5):

    (6, 34)   (25, 34)
    (6, 35)   (25, 35)

Deliberately not the lattice-crossing squares (cols 9/13/17/21 and similar):
those are the quilting pattern's own motif, repeat only every few rows, and
read as decoration rather than as a fitting the network light could plausibly
be riding on.
"""

from crates import _kit as kit

MEMBERS = [
    "spring_festival_flower_chest",
]

REP = "spring_festival_flower_chest"

PARAMS = kit.GlowParams(diodes=((6, 34), (25, 34), (6, 35), (25, 35)))
