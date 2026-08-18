#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""fam_deluxe -- the thirteen deluxe storage chests.

The largest family (13 palettes of one drawing: aqua, black, blue, dark_brown,
gold, gray, green, light_brown, orange, pink, purple, red, white).  40x48,
pivot 16/31 -- note the pivot is NOT 16/24 like basic_wood; `_geom.py` (not
this file) is the source of truth for that, and it is what makes lid_safe 29
rather than 20.  base_row 38, lid_band 10..28, so the generic rim/seam/under-
glow has only 10 rows to work with (rows 29..38) -- tight, but the default
`GlowParams` still fits (seam sits at row 36, well inside the band).

THE DIODES.  A deluxe chest's front carries an applied brass lock plate
(`spr_furniture_deluxe_storage_chest_*_main_closed`, rows ~26-33, columns
~11-20 of the 40-wide frame) with a keyhole cutout -- the obvious first
candidate. It FAILS the rule, though, and only direct pixel inspection of the
archive caught it: the plate is drawn on the LID's front lip, not the box, so
in the `_opened` sprite that whole region reverts to flat body colour with no
plate at all (checked byte-for-byte: closed row 29, cols 13/14/17/18 are
`#d19556`, the plate's brass; opened row 29 at the same four coordinates is
`#c84f56`, the "red" variant's plain body red -- verified for the red, gold
and black variants alike, so it is not a palette accident).  A diode there
would light on brass with the lid shut and on bare cloth the instant a player
opens the chest.

The chest's OTHER piece of hardware survives that test: a brass corner post
runs down both sides of the box, independent of the lid, and reads identically
in every pose because it sits below where the lid ever reaches.  Read straight
from the archive (`spr_furniture_deluxe_storage_chest_red_main_{closed,
opened}`, and cross-checked against the gold/black/purple palettes so the
choice is not a red-only fluke):

    row 31   x=4  #b57041      row 31   x=27 #b57041   (mirror: CENTRE=15.5,
    row 34   x=5  #90562e      row 34   x=26 #90562e     31-4=27, 31-5=26)

identical pixel-for-pixel between `_main_closed` and `_main_opened` in every
palette checked, both rows comfortably inside `lid_safe` (29).  Two rows of a
mirrored pair, exactly the basic_wood recipe (two straps, two rows each) --
here it is one post on each side instead of two straps, because that is the
fitting this chest actually has.
"""

from crates import _kit as kit

# Every twinned chest of the family, exactly as `crates/_geom.py` lists them.
MEMBERS = [
    "deluxe_storage_chest_aqua",
    "deluxe_storage_chest_black",
    "deluxe_storage_chest_blue",
    "deluxe_storage_chest_dark_brown",
    "deluxe_storage_chest_gold",
    "deluxe_storage_chest_gray",
    "deluxe_storage_chest_green",
    "deluxe_storage_chest_light_brown",
    "deluxe_storage_chest_orange",
    "deluxe_storage_chest_pink",
    "deluxe_storage_chest_purple",
    "deluxe_storage_chest_red",
    "deluxe_storage_chest_white",
]

REP = "deluxe_storage_chest_red"

PARAMS = kit.GlowParams(diodes=((4, 31), (27, 31), (5, 34), (26, 34)))
