#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""fam_coral -- the two tide-caverns coral storage chests.

THE ONE RECON FLAGGED AS "GOOD BY ACCIDENT": the generic rim is derived
straight from `geom.rim`, i.e. the closed pose's own silhouette, and this
chest's silhouette is a shell body with four light-blue fin/claw shapes
poking out at the corners.  Trace that outline and the rim naturally runs up
and around every fin tip instead of cutting a rectangle through them --
verified here, not inherited: rendered both poses side by side and the fins
read as fins in each, rim included, with no floating or clipped tips. That
holds specifically because `geom.rim` is built from the CLOSED pose's own
alpha mask down to `lid_safe`, and the fins sit well below the lid line
(`lid_band` tops out at 19, the fins start at row ~25), so they are part of
the "safe" silhouette the rim is allowed to touch at all.

THE DIODES -- or rather, why there are none.  This chest has a visible
latch-like white nub in the closed pose (row 32, columns 15/16), but it is
NOT body hardware: it belongs to the lid.  Pixel-sampled proof: the same
(x, y) in the OPENED sprite is plain shell-blue, no nub at all, while a
different white/black latch shape appears near row 21 instead -- i.e. the
latch moved with the lid, the exact trap the diode rule warns about
("a chest missing... must STILL be on hardware in the opened pose, because
the lid moves and carries its fittings with it").  A full byte-identical scan
of every pixel at `lid_safe` (20) and below found nothing bright shared
between the two poses except the corner fins themselves -- which the rim
already lights, so a diode there would just double up the rim's own pixel
rather than add a second, independent signal.  Rather than fake a rivet that
was never drawn, this family ships with the generic rim + dashed underglow +
seam + spark and no diodes: verified in the rendered sheet to still hit every
audit (a lit pixel every frame comes from the rim/underglow, which trace a
silhouette that never goes empty) and to read as a coherent glow without an
invented fastener.
"""

from crates import _kit as kit  # noqa: F401  (imported for parity with every
                                 # other family file; this one needs no PARAMS)

# Every twinned chest of the family, exactly as `crates/_geom.py` lists them.
MEMBERS = [
    "coral_storage_chest_blue",
    "coral_storage_chest_purple",
]

REP = "coral_storage_chest_blue"

# No PARAMS: the shipped `crate_glow` defaults (rim + dashed underglow + seam
# + spark, diodes=()) are exactly right for this family -- see the module
# docstring for why diodes are deliberately omitted rather than guessed at.
