#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""fam_miners -- the two mineshaft miners' crates.

THE ODD ONE ON WIDTH: 56x48 against the 40x48 every other family bar `mist`
uses, pivot (24.0, 24.0) instead of (16.0, 24.0).  `_geom.py`'s rim already
carries that difference (rows 17..38, xl/xr spanning 9..39 at the widest), so
`crate_glow`'s defaults need no width-specific change -- `seam_inset=4` still
leaves a real span (the row-36 seam runs xl=12..xr=36, inset to 16..32, an
18px seam vs basic_wood's 16px one) and the rim/underglow both walk `geom.rim`
directly, so they hug this wider silhouette exactly as they hug the 40px one.
Rendered and judged over both poses before deciding that -- see the module
docstring's sibling comment in `crate_glow` for why a *fixed* pixel step (the
spark) would have been wrong here; the span-relative one already in `_kit.py`
is what makes this family safe to leave untuned.

THE DIODES.  This crate carries NO metal at all -- every opaque pixel sampled
from the game archive lands far from every M1..M4 slate tone (nearest-match
distances in the thousands; basic_wood's actual rivet pixel is an exact hit at
distance 0).  It is built the way a mining crate should be: wood board, wood
batten, and two barrel-cap-style wooden dowel ends poking out the left and
right sides.  Those dowel-cap highlights -- (197,181,138) at (11,24)/(37,24),
(164,143,111) at (11,25)/(37,25) -- are the single brightest, most clearly
"fitting"-like feature on the object: a fastener's cap, just carved from wood
instead of stamped from iron.  Verified byte-for-byte identical between the
closed and opened sprites (both position and colour), which the family's own
interior batten lines (columns 15..17 / 31..33) are NOT -- those read as
plank/batten shading in the closed pose but become the black-outlined edge of
the open cavity in the opened one, i.e. exactly the "hardware that isn't
hardware once the lid moves" trap the spec warns about.  The dowel caps sit
outside that swept region entirely (they are side ornament, not lid-adjacent),
which is why they survive untouched.
"""

from crates import _kit as kit

# Every twinned chest of the family, exactly as `crates/_geom.py` lists them.
MEMBERS = [
    "miners_crate_chest_v1",
    "miners_crate_chest_v2",
]

REP = "miners_crate_chest_v1"

# ---------------------------------------------------------------------------
# THE ONLY AUTHORED LINE.  Rim, underglow and seam are the shipped defaults --
# `geom.rim` already carries this family's extra width, so nothing about the
# generic drawer needs retuning for it (rendered and confirmed, not assumed).
#
# THE DIODES sit on the two wooden dowel-cap ends, symmetric left/right, two
# rows deep for the same visual weight basic_wood's four give its rivets.
# Legal by `lid_safe` (24/25 >> 17) and, more than legal, STABLE: sampled
# pixel-for-pixel identical in both the closed and opened archive sprites, so
# the lit dot still sits on the same wood-cap fitting whichever pose is on
# screen while the overlay plays.
# ---------------------------------------------------------------------------
PARAMS = kit.GlowParams(diodes=((11, 24), (37, 24), (11, 25), (37, 25)))
