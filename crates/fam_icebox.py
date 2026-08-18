#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""fam_icebox -- the deluxe icebox, 5 palettes.

`spr_furniture_deluxe_icebox_<colour>_main_*` -- a tall double-door appliance,
40x56, pivot 16/45, `lid_band=(None, None)`.  That None is not "no lid", it is
the measured fact that the CLOSED and OPENED alpha masks are byte-identical:
the two doors swing on hinges at the far left/right edges and never leave the
closed silhouette's bounding footprint, so `lid_safe` collapses to `top_all`
(8) and the WHOLE 38-row body (`glow_rows=38`, the widest budget of any
family) is silhouette-safe in every pose.  Read `crates/_geom.py`'s field
docs before assuming that generosity is free of the diode rule, though --
"silhouette-safe" only says the overlay never floats off the object; it says
nothing about which pixel is still HARDWARE once the doors have rotated open,
which is the thing that had to be checked by eye against the actual archive
frames (see PARAMS below).

WHAT THIS FAMILY DRAWS: nothing.  Both generic drawers are used; the tuning
below is a taller `GlowParams` plus one verified diode cluster.
"""

from crates import _kit as kit

# Every twinned chest of the family, exactly as `crates/_geom.py` lists them.
MEMBERS = [
    "deluxe_icebox_blue",
    "deluxe_icebox_green",
    "deluxe_icebox_pink",
    "deluxe_icebox_white",
    "deluxe_icebox_yellow",
]

# _white, the family's "default" colourway and the one the contact sheet
# composites the overlays over.  All five are palette swaps of one drawing.
REP = "deluxe_icebox_white"

# ---------------------------------------------------------------------------
# TALL-BODY TUNING.
#
# `crate_glow`'s default drop bands (drop0=6, drop1=10) are basic_wood's own
# numbers, sized to an 18-row glow budget: at that scale, 6 rows of "always
# bright" plus 4 of "mid" leaves 8 rows of "only at peak pulse", a sensible
# split.  Applied unchanged to this family's 38 rows, the SAME 6/10 split
# would leave the bottom 6 rows always bright, the next 4 at mid, and the
# remaining 28 rows -- three quarters of the appliance's height, everything
# from the doors up to the vents on the cap -- lit only during the two
# brightest frames of the eight.  Rendered, that reads as a small glowing
# puddle under an otherwise dark fridge, not as a unit whose whole silhouette
# is quietly awake.  Scaled to this family's own budget (38 vs. basic_wood's
# 18, i.e. roughly x2.1) and rounded to a clean split, the bands become
# 13/24: the bottom third of the body pulses through the full triangle wave,
# the middle third holds at a steady mid glow, and only the top third (the
# cap and vents) stays reserved for the brightest frames.
PARAMS = kit.GlowParams(
    drop0=13,
    drop1=24,
    # ------------------------------------------------------------------
    # THE DIODES.  Verified against the actual archive frames (deluxe_icebox
    # _white_main_closed.png / _opened.png), not guessed:
    #
    # The two upper door handles (columns 9-11 and 15-17 at rows 23-32 in the
    # CLOSED pose) do NOT qualify -- they are drawn on the doors themselves,
    # and the doors physically swing open, so those exact (x,y) coordinates
    # show plain cream body/interior colour in the OPENED frame.  Diode rule
    # violated: hardware in one pose, not the other.
    #
    # The DRAWER pull-handle -- the bottom compartment's bar handle -- is the
    # one fitting that survives: only the two upper doors hinge, the drawer
    # beneath them never moves, so its handle sits at the SAME pixels in both
    # poses.  Read directly off both frames: row 36, columns 11 through 19,
    # is solid #877f7b (the mid-grey metal tone used for every hinge, latch
    # and bezel on this sprite, distinct from the d6d0ce/f2efed/ffffff cream
    # body) in the closed frame AND in the opened frame, unchanged pixel for
    # pixel.  The two outer columns of that bar -- its mounting-bracket ends
    # -- are lit here, a symmetric pair either side of centre (x=15.5):
    diodes=((11, 36), (19, 36)),
)
