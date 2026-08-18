#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""fam_basic_wood -- the fifteen basic wooden chests.

THE REFERENCE FAMILY.  Copy this file, not the spec, when you author one of the
other thirteen: it is the shortest complete example of the contract, and the
comments say why each of the three numbers below is the number it is.

The family is `spr_furniture_basic_chest_v01..v15` -- one drawing in fifteen
palettes, from `_dark` (v01) through the seven wood/theme variants to the seven
colours.  40x48, pivot 16/24, lid band rows 13..19, so `lid_safe` is 20 and the
glow has 18 rows of stable silhouette to work with: the most generous budget of
any family bar the doorless ones.  Nothing here is measured by hand -- it all
comes from `crates/_geom.py`, which `tools/gen_crate_geom.py` derived from the
game archive.

`stable_storage_chest` is NOT a member.  It is the same drawing (mask identity
1.00) but no item places it -- it is a stable fixture -- so there is no twin
item to hand back when the player picks the crate up.  It is also the only
chest in the game offset by 1px from its own family, which is why it falls into
its own signature group upstream and never reaches this list.

WHAT THIS FAMILY DRAWS: nothing.  Both generic drawers are used unchanged; the
whole authored content is one `GlowParams`.  That is the intended outcome for
most of the fourteen, and a family that finds itself writing pixels should
first check whether it is really fighting `_geom`.
"""

from crates import _kit as kit

# Every twinned chest of the family, exactly as `crates/_geom.py` lists them
# (sorted -- the registry compares the two and refuses a mismatch, because a
# chest quietly dropped from here is a chest with no twin and a chest quietly
# added is a `netstor_crate_*` key with no chest).
MEMBERS = [
    "basic_wood_chest_black",
    "basic_wood_chest_blue",
    "basic_wood_chest_cottage",
    "basic_wood_chest_dark",
    "basic_wood_chest_green",
    "basic_wood_chest_haunted_attic",
    "basic_wood_chest_light",
    "basic_wood_chest_medium",
    "basic_wood_chest_orange",
    "basic_wood_chest_pink",
    "basic_wood_chest_purple",
    "basic_wood_chest_red",
    "basic_wood_chest_white",
    "basic_wood_chest_witch_queen",
    "basic_wood_chest_yellow",
]

# v01, the chest the player crafts first and the one the contact sheet
# composites the overlays over.  Editorial: all fifteen are silhouette-
# identical, which is what lets one strip serve the family.
REP = "basic_wood_chest_dark"

# ---------------------------------------------------------------------------
# THE ONLY AUTHORED LINE IN THE FILE.
#
# Everything except the diodes is the shipped `netstor_block` glow's own
# tuning, ported row for row, so a basic chest and a Storage Block pulse
# identically -- which is the point of the whole recipe: the MOTIF is the same
# on all 59 twins while the OBJECT stays the player's chest.
#
# THE DIODES sit on the chest's own ironwork.  The vanilla drawing carries two
# vertical metal straps down the lid at columns 10 and 21, and puts its single
# brightest pixel -- #767f96, the strap's rivet -- at exactly (10,21), (21,21),
# (10,22) and (21,22).  Lighting those four is not decoration placed on top of
# the chest; it is the chest's existing highlight coming on.  Half a cycle out
# of phase with the rim, so the twin never goes fully dark between pulses.
#
# They are legal by the lid_safe rule (rows 21-22 >= 20) and, more than legal,
# STABLE: below `lid_safe` the alpha mask is identical in every pose, and here
# the straps are metal in the opened pose too -- the lid carries them up to
# rows 14..24, so the overlapping band 20..24 is strap in both.  A diode at
# row 21 lands on strap whether the chest is shut or wide open.
# ---------------------------------------------------------------------------
PARAMS = kit.GlowParams(diodes=((10, 21), (21, 21), (10, 22), (21, 22)))
