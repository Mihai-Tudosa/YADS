#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""fam_mimic -- the Mimic Storage Chest.  A singleton: one member, and the
tightest headroom budget of any family bar the lava obsidian chest.

40x48, pivot 16/31 (a plain number in the vanilla meta -- no "Middle" string
here, so no anchor trap to worry about). `top_all` is 4: the chest's two
pointed "ear" arches reach almost to the top of the canvas. `lid_band` is
4..14 (just those ears/the gap between them), so `lid_safe` is 15 and the
generic drawer gets a generous 24 rows (`glow_rows=24`) despite the tight top
-- the lid band itself is short, it is just high up. `face_pad` is 7, the
second-largest in the set, purely to give the sad-face bubble (9 rows + a
1px bob either way) somewhere to sit above a chest that already claims row 4.

THE DIODES.  This is a plain-wood monster in disguise -- the full closed-pose
palette (checked by histogram) is eight wood tones plus black linework plus
exactly 2px of grey/white for the fang tips. There is no metal anywhere: no
slate, no gilt, nothing from the palette any other twin uses for hardware.
The closest thing to a "fitting" is the lighter corner-post trim flanking the
lower drawer front (cols 3..4 left, cols 27..28 right), one shade brighter
than the dark recessed panel it borders -- read directly off
`spr_furniture_mimic_storage_chest_main_*`. Scanned row-by-row against
closed/opened/opening together, rows 15..33 all shift shade between poses (the
mimic's "head" and "mouth" are doing a lot of acting there), but rows 34..37
land on the IDENTICAL RGB (#e29b5a) in all three poses -- checked pixel-for-
pixel. That is the plain lower housing below the mouth entirely, which is
exactly where a disguised monster would still need to look like ordinary
chest joinery. Cols 4/27 sit 11.5px either side of the pivot (15.5):

    (4, 35)   (27, 35)
    (4, 36)   (27, 36)

Deliberately NOT the two fang tips (cols 10/20, rows 31-32): those are the
mimic's own anatomy, not network hardware, and at row 20 the same columns
turn out to be the dark mouth-cavity interior in the OPENED pose -- exactly
the "lands in open air once the lid moves" trap the brief warns about, even
though row 20 is nominally >= lid_safe (its ALPHA stays opaque across poses,
which is all `lid_safe` promises; its identity as "hardware" does not).

THE SAD FACE: kept as the generic bubble, not overridden. Judgment call: the
mimic already has a face (the two ear-arches read as brows, the seam between
head and body as a shut mouth with two fangs pointing out of it), and the
mod's own bubble hovers directly above that in `face_pad`'s reserved rows,
so there is a real risk of "face on a face." Having rendered it (see the
family's contact sheet), the two do not compete: the bubble sits a clear row
above the ear-tips even at its lowest bob, it is a flat cartoon thought-cloud
rather than another set of features, and the net read is "the monster is
sulking that nobody's stealing from it" -- which lands as an in-theme joke
for a mimic specifically, not a confusing double face. Left as the default.
"""

from crates import _kit as kit

MEMBERS = [
    "mimic_storage_chest",
]

REP = "mimic_storage_chest"

PARAMS = kit.GlowParams(diodes=((4, 35), (27, 35), (4, 36), (27, 36)))
