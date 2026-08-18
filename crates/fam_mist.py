#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""fam_mist -- the four mist storage chests.  THE ONE FAMILY WITH NO SILHOUETTE.

`crates/_geom.py` gives this family `lid_band = (9, 24)`, `base_row = 23`,
`lid_safe = 25` and therefore `glow_rows = 0` and an EMPTY `rim`.  That is not a
quirk of the measurement: the mist chest is a floating cloud whose entire drawing
animates -- `closed` is a 4-frame idle, `opening` 8, `opened` 8, `bounce` 6, and
every row from 9 to 24 has a different width in at least one of them.  There is
no row of the object a static rim can hug, so `kit.crate_glow` traces nothing and
emits EIGHT TRANSPARENT FRAMES: a family shipped as network storage carrying no
network marking whatsoever.  `audit_glow_strip`'s "every frame has a lit pixel"
rule exists because of this file, and this file is the reason it never fires.

WHAT THE OVERLAY DRAWS INSTEAD: THE HOVER PAD.
The cloud has no foot -- but it has a SHADOW, and the shadow is the object's
presence on the ground.  `spr_furniture_mist_storage_chest_v*_shadow_*` is a
solid ellipse occupying rows 21..31 in every frame of every pose (only its WIDTH
breathes, by 1-3px per side), it is registered for all four role sprites in
`shadow_manifest.json`, and `obj_node_renderer.set_sprite` attaches it
automatically -- a crate twin naming the vanilla sprite gets it for free (art
recon 2.2).  `obj_shadow_level` is instanced at the room's SHADOW layer depth
(`Decor.gml:185`, `setup_room.gml:386`) and draws the grid as a `bm_dest_color`
multiply, i.e. a level below the furniture -- so our `top_sprite` lands on top
of both the shadow and the body, and the pad reads as light ON the ground.

Rows 25..31 of that ellipse are the only part of the chest that is both LEGAL
(at or below `lid_safe = 25`) and REAL (there is something there to light).  So
the glow is a lit pad on the ground with the cloud hovering over it, and the
four elements of the set's vocabulary map onto it one for one:

    the crate's ...            becomes the pad's ...
    rim hugging the silhouette  the pad's two walls, rows 26..29, drop-biased
                                so the light pools at the near edge
    lit seam + running spark    the pad's leading edge, row 25 -- the widest
                                row, and the only straight run the ellipse has
    dashed marching under-glow  rows 30..31, the light spilling off the near
                                edge, dashing on `(x + f) % 2` exactly as the
                                generic drawer does along a chest's base
    diodes on the chest's own   there IS no legal hardware -- the cloud is all
    hardware, out of phase      above `lid_safe` -- so they sit at the pad's two
                                corner posts, where the seam meets the walls,
                                which is the same place `netstor_block` puts its
                                own (the seam spans between the corner plates)

Judged against `fam_basic_wood`'s contact sheet at 6-14x over grass, wood floor
and cave rock, in all four tints, over the closed idle, the opened idle and the
bounce: same three rungs, same triangle pulse, same dash rhythm, same travelling
spark, same tint behaviour.  The SHAPE differs because the object does -- which
is the recipe's whole premise.

WHAT THIS FAMILY DOES NOT OVERRIDE: the sad face.  `face_pad = 4` puts the
bubble's lowest bobbed row at 10 against a body starting at 11, and the cloud is
symmetric about the pivot, so `kit.sad_face` is correct unchanged.

THE ONE ACCEPTED DEFECT is art recon H6, and it is the same one every family
carries: `bounce_band = (7, 26)` reaches past `lid_safe`, so for the <1s a
Throw-bounce plays the cloud dips over the pad's top two rows.  Transient, and
the alternative is a bounce-synchronised overlay the engine will not give us.
"""

# Every twinned chest of the family, exactly as `crates/_geom.py` lists them.
# All four are pixel-identical in every frame of every role sprite AND in every
# shadow frame -- checked mask-for-mask against the archive, not assumed -- so
# one pad serves all four.  They differ only in cloud tint.
MEMBERS = [
    "mist_storage_chest_v1",
    "mist_storage_chest_v2",
    "mist_storage_chest_v3",
    "mist_storage_chest_v4",
]

REP = "mist_storage_chest_v1"


# ---------------------------------------------------------------------------
# THE PAD.  `{row: (xleft, xright)}` of the chest's own shadow, from `lid_safe`
# down to the shadow's last row -- the `geom.rim` that `_geom.py` could not
# produce, because it measures the BODY and the body has no stable edge.
#
# Measured off `spr_furniture_mist_storage_chest_v1_shadow_closed` FRAME 0,
# which is the NARROWEST of the 26 shadow frames the four poses contain (the
# closed idle breathes +1px per side on frames 1-2; opened runs +2 to +3;
# bounce +3).  Narrowest on purpose: a ring traced on it is inscribed on the
# shadow in every pose and never spills onto bare ground, which is the only
# choice that looks deliberate rather than lucky when the pose changes.
#
# Symmetric about x = 23.5, i.e. `pivot[0] - 0.5`, the same CENTRE convention
# the authored units use.
# ---------------------------------------------------------------------------
PAD = {
    25: (15, 32),      # the leading edge -- widest row, and `lid_safe`
    26: (15, 32),
    27: (15, 32),
    28: (16, 31),
    29: (17, 30),
    30: (19, 28),      # the near edge, where the light spills
    31: (22, 25),
}

PAD_TOP = 25           # == geom.lid_safe; the seam row
PAD_UNDER = 30         # first row of the dashed under-glow
PAD_BASE = 31          # last row of the shadow; the pad plants here

# The pad's corner posts, where the leading edge meets the walls.  Lit half a
# cycle out of phase with the rim, so the pad never goes fully dark -- the same
# job, and the same `PULSE[(f + 4) % 8]` phase, as a chest's latch diodes.
POSTS = ((15, 26), (15, 27), (32, 26), (32, 27))

# `drop(y)` over the four wall rows: the bottom two at full pulse, the top two
# one rung down, so the light pools at the near edge exactly as it pools at a
# chest's foot.  Two bands over four rows is the most a 7-row pad can carry;
# `GlowParams`' (6, 10) is sized for an 18-row chest and would leave the whole
# pad on one rung.
DROP0, DROP1 = 4, 6


def glow(kit, geom, f):
    """One frame of the hover pad.  Overrides `kit.crate_glow` entirely --
    there is no `geom.rim` for it to trace."""
    # `_geom.py` is regenerated from the archive after a game patch, and the
    # PAD table above is NOT: it is the one hand-measured thing in this
    # family.  If the patch moved the chest, `lid_safe` moves with it and the
    # pad would silently detach from the shadow -- no audit can see that,
    # because every row here would still be legal and lit.  So say so loudly.
    if geom.lid_safe != PAD_TOP:
        raise ValueError(
            "fam_mist: geom.lid_safe is %d, not the %d this family's PAD table "
            "was measured against.  The mist chest moved; re-measure PAD off "
            "spr_furniture_mist_storage_chest_v1_shadow_closed frame 0 (rows "
            "lid_safe..last, narrowest pose) before regenerating."
            % (geom.lid_safe, PAD_TOP))

    w, h = geom.canvas
    cv = kit.Canvas(w, h)
    lvl = kit.PULSE[f]

    # ---- the leading edge: the seam, with the spark running along it -------
    # Drawn full width rather than inset: on a chest the seam spans BETWEEN the
    # corner plates and the silhouette carries the rest of the row, but here
    # the row IS the silhouette's widest chord, and stopping short of the walls
    # opens two gaps that read as a broken ring rather than as a seam.
    xl, xr = PAD[PAD_TOP]
    cv.hline(xl, xr, PAD_TOP, kit.SEAM_G[lvl])
    span = xr - xl + 1
    sx = xl + int(round(f * (span - 2) / float(kit.GLOW_LEN - 1)))
    cv.set(sx, PAD_TOP, kit.G3)
    cv.set(sx + 1, PAD_TOP, kit.G3)

    # ---- rim down the pad's two walls --------------------------------------
    for y in range(PAD_TOP + 1, PAD_UNDER):
        xl, xr = PAD[y]
        d = PAD_BASE - y
        drop = 0 if d < DROP0 else (1 if d < DROP1 else 2)
        kit.rim(cv, xl, y, lvl, drop)
        kit.rim(cv, xr, y, lvl, drop)

    # ---- dashed light spilling off the near edge ---------------------------
    # Two rows, not one: an ellipse's last row is four pixels wide and a dash
    # on four pixels is two pixels, which cannot be seen to march.  Rows 30 and
    # 31 together give the same read a chest's full-width base row gives.
    for y in range(PAD_UNDER, PAD_BASE + 1):
        xl, xr = PAD[y]
        for x in range(xl, xr + 1):
            if (x + f) % 2 == 0:
                kit.rim(cv, x, y, lvl, 1)

    # ---- corner posts, half a cycle out of phase ---------------------------
    dp = kit.PULSE[(f + kit.GLOW_LEN // 2) % kit.GLOW_LEN]
    if dp >= 1:
        for (dx, dy) in POSTS:
            cv.set(dx, dy, kit.GTONE[dp])
    return cv
