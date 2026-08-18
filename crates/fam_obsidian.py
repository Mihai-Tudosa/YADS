#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""fam_obsidian -- the two lava-caves obsidian storage chests.

THE ODD ONE ON HEADROOM: 32x40, the smallest canvas of any twinned family, and
`top_all=4` leaves only 4 rows between the body's own topmost pixel and the
canvas edge -- which is why `face_pad=7` grows the offline canvas rather than
the usual 0.  `lid_safe=16` still leaves a real 16-row rim budget (16..31),
generous enough that the generic rim/underglow/seam need no retuning; judged
over both poses before leaving them at the shipped defaults.

THE DIODES.  Unlike the wood-and-batten families, this chest is drawn with an
actual gold CLASP: a bright hinge/latch nub sitting dead centre where the lid
meets the body, rendered in a colour (#ffcf36) that appears nowhere else on
the object and reads unmistakably as metal fitting rather than shell or stone.
Sampled pixel-for-pixel against both archive sprites: columns 11/12/13 at row
21 are (255,207,54) IN BOTH THE CLOSED AND OPENED POSE, identical to the byte --
the one feature on this chest proven to survive the lid swinging back, exactly
the test basic_wood's rivets pass and the reason to prefer this over the
gold TRIM band running along rows 19/20/29/30 (also byte-stable, but a plain
band reads as trim, not as the object's one working fastener).  Two diodes,
flanking the clasp's brightest column rather than sitting on it, so the lit
pair reads as the two rivets holding the clasp down rather than replacing its
own highlight.
"""

from crates import _kit as kit

# Every twinned chest of the family, exactly as `crates/_geom.py` lists them.
MEMBERS = [
    "lava_caves_obsidian_storage_chest_blue",
    "lava_caves_obsidian_storage_chest_purple",
]

REP = "lava_caves_obsidian_storage_chest_blue"

# ---------------------------------------------------------------------------
# THE ONLY AUTHORED LINE.  Rim/underglow/seam are the shipped defaults -- the
# 16-row budget from `lid_safe` down to `base_row` is plenty for the pulse to
# read without crowding the clasp.
#
# THE DIODES flank the golden clasp nub, one column either side of its
# brightest pixel (row 21, column 12).  Legal by `lid_safe` (21 >> 16) and
# pixel-verified identical in both poses -- the lit pair sits on real gold
# hardware whether the chest is shut or standing open.
# ---------------------------------------------------------------------------
PARAMS = kit.GlowParams(diodes=((11, 21), (13, 21)))
