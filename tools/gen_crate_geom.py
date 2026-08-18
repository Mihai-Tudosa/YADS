#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""gen_crate_geom.py -- derive `crates/_geom.py` from the game archive.

THE ONLY THING IN THIS REPOSITORY THAT READS THE CHEST ART.  It opens
`assets.bak.zip` exactly once, parses the vanilla fiddle out of it, measures
every chest's four role strips, groups the chests into visual families by
EXACT mask identity, and writes a checked-in Python module.  `make_art.py`
then never touches the archive: the build is hermetic and byte-deterministic
whether or not the game is installed.

That pairing is the file's own precedent, not an invention:
`VANILLA_ITEMCOUNT_GLYPHS` (make_art.py) is an embedded transcription of
vanilla pixels and `check_font_against_vanilla()` re-reads the archive only as
an audit.  This script is the same shape at family scale --
`python tools/gen_crate_geom.py --check` re-derives everything and fails on any
drift from the committed `_geom.py`, which is the gate to run after a game
patch (art recon H14: a chest sprite moved one pixel silently desyncs every
glow in its family).

HOW THE FAMILIES ARE FOUND -- derived, not authored.  Every chest in a family
is a pure palette swap of one drawing, so the families are exactly the classes
of chests whose FOUR role strips have pixel-identical alpha masks, compared
pivot-aligned (translated by the sprite pivot, i.e. where the game actually
draws them).  Exact equality, no threshold, no clustering parameter to tune --
and it splits the two silhouette coincidences (spring-festival vs basic at IoU
0.92, mimic vs deluxe at 0.90) for free, because 0.92 is not 1.00.  Only two
things are authored: the family's NAME (it becomes a frozen sprite name) and
its representative (documentation only -- every member is identical by the
grouping's own construction).

WHAT IT EMITS, per family:  canvas, pivot AS NUMBERS, base_row, top_all,
lid_band, bounce_band, lid_safe, glow_rows, face_pad, face_y0, and `rim` --
the (y, xleft, xright) of every row of the closed pose from lid_safe down to
base_row.  Per member: the four vanilla sprite names, the item key and icon,
inventory_size, footprint, and any optional `interaction_chest` keys the twin
must copy (bark_offset, open_sfx, close_sfx).

Run:  python tools/gen_crate_geom.py            # write crates/_geom.py
      python tools/gen_crate_geom.py --check    # verify it, write nothing
      python tools/gen_crate_geom.py --recon    # also diff the b13 recon JSON
"""

import io
import json
import os
import re
import sys
import zipfile

try:
    from PIL import Image
except ImportError:  # pragma: no cover
    sys.exit("Pillow is required:  pip install pillow")

HERE = os.path.dirname(os.path.abspath(__file__)).replace("\\", "/")
REPO = os.path.dirname(HERE)
OUT = REPO + "/crates/_geom.py"

GAME_ASSETS_ZIP = ("C:/Program Files (x86)/Steam/steamapps/common/"
                   "Fields of Mistria/assets.bak.zip")
RECON = "C:/Claude/.scratch/b13recon"

FURNITURE_TOML = "assets/fiddle/object_prototypes/furniture.toml"
ITEMS_PREFIX = "assets/fiddle/items/"

# --------------------------------------------------------------------------
# The sad-face bubble's vertical budget.  `_kit.FACE_ROWS` is 9 rows tall and
# `_kit.FACE_BOB` moves it (0, -1, 0, +1), so across the 4 frames it sweeps 11
# rows.  It is anchored as low as it can go -- its lowest bobbed row sits
# exactly one row above the body's topmost opaque row -- which fixes the base
# y0 at `top_all + face_pad - 10` and its highest bobbed top row at
# `top_all + face_pad - 11`.  So the canvas must be padded until
# `top_all + face_pad >= 11`, not >= 10.
#
# THE RECON IS OFF BY ONE HERE and this is the corrected value: `measure2.py`
# used `need = FACE_H + FACE_BOB = 10`, which leaves the up-bobbed frame's top
# row at y = -1, clipped off the canvas.  --recon reports every family where
# the two disagree.
# --------------------------------------------------------------------------
FACE_H = 9
FACE_BOB_UP = 1
FACE_BOB_DOWN = 1
FACE_NEED = FACE_H + FACE_BOB_UP + FACE_BOB_DOWN      # 11

# --------------------------------------------------------------------------
# THE TWO AUTHORED TABLES.
#
# FAMILY_NAME maps a family's representative chest to the family's name.  That
# name becomes `spr_furniture_netstor_crate_<name>_glow`, which is an asset
# name a prototype resolves BY STRING -- so it freezes the moment it ships.
# The representative is the chest the family's overlays are generated from and
# the chest the contact sheet composites them over; every other member is
# pixel-identical in silhouette by the grouping's construction, so the choice
# is editorial.
# --------------------------------------------------------------------------
FAMILY_NAME = {
    "basic_wood_chest_dark":                 "basic_wood",
    "deluxe_storage_chest_red":              "deluxe",
    "royal_chest_wood":                      "royal",
    "deluxe_icebox_white":                   "icebox",
    "mist_storage_chest_v1":                 "mist",
    "stone_storage_chest_v1":                "stone",
    "cottage_fridge_v1":                     "fridge",
    "miners_crate_chest_v1":                 "miners",
    "coral_storage_chest_blue":              "coral",
    "lava_caves_obsidian_storage_chest_blue": "obsidian",
    "void_storage_chest_v1":                 "void",
    "spring_festival_flower_chest":          "flower",
    "dragon_chest":                          "dragon",
    "mimic_storage_chest":                   "mimic",
}

# Never twinned.  Each carries its reason; all three are corroborated
# independently by the plumbing recon's worklist.  THIS IS ALSO THE CONVERTER'S
# EXCLUSION LIST, and the only copy of it: the gesture's pair tables are derived
# from the twins that exist, so a chest with no twin here is simply one the
# converter defers on (`docs/converter-facts.md`).
EXCLUDED = {
    "starter_shipping_box":
        "shipping_bin = true -- a network member that sells your items "
        "overnight (Furniture.gml:871-873)",
    "turn_in_box":
        "belongs_to_ari = false, destructable = false, no item -- a town "
        "fixture, not player-placeable",
    "stable_storage_chest":
        "no item places it (a stable fixture), so there is no twin item to "
        "hand back on pickup; also the only 1px-offset member of its family",
}


# --------------------------------------------------------------------------
# A deliberately small TOML reader.  The vanilla fiddle is flat: `[header]`
# lines and `key = value` lines, tabs for indentation, `#` comments.  Nothing
# here needs a real parser and a real parser would need a dependency.
# --------------------------------------------------------------------------

HDR = re.compile(r'^\s*\[([^\]\[]+)\]')
KV = re.compile(r'^\s*([A-Za-z_][A-Za-z0-9_.]*)\s*=\s*(.+?)\s*$')


def parse_tables(text):
    """-> {table name: {key: raw value string}}, in file order."""
    tables = {}
    cur = None
    for line in text.split("\n"):
        m = HDR.match(line)
        if m:
            cur = m.group(1).strip()
            tables.setdefault(cur, {})
            continue
        m = KV.match(line)
        if m and cur is not None:
            val = m.group(2)
            if not val.startswith('"'):
                val = val.split("#")[0].strip()
            tables[cur][m.group(1)] = val
    return tables


def unquote(v):
    if v is None:
        return None
    v = v.strip()
    if len(v) >= 2 and v[0] == '"' and v[-1] == '"':
        return v[1:-1]
    return v


def as_int_pair(v):
    if v is None:
        return None
    nums = re.findall(r"-?\d+", v)
    return (int(nums[0]), int(nums[1])) if len(nums) >= 2 else None


# --------------------------------------------------------------------------
# Archive reading
# --------------------------------------------------------------------------


class Archive(object):
    def __init__(self, path):
        self.zf = zipfile.ZipFile(path)
        # Basename index, built from a SORTED name list.  The archive has 122k
        # entries and the game files sprites by art-department folder, not by
        # prototype, so every lookup is by leaf name.  Sorted, and with
        # ambiguity recorded rather than resolved by luck: two entries sharing
        # a leaf name would otherwise make which one we measured depend on zip
        # ordering, and `_geom.py` is checked in.
        self.by_leaf = {}
        self.ambiguous = {}
        for n in sorted(self.zf.namelist()):
            if n.endswith("/"):
                continue
            leaf = n.rsplit("/", 1)[-1].lower()
            if leaf in self.by_leaf:
                self.ambiguous.setdefault(leaf, [self.by_leaf[leaf]]).append(n)
            else:
                self.by_leaf[leaf] = n

    def read(self, entry):
        return self.zf.read(entry)

    def find_asset(self, sprite, ext):
        """Locate <sprite><ext> anywhere in the tree."""
        leaf = sprite.lower() + ext
        if leaf in self.ambiguous:
            raise ValueError("%s is ambiguous in the archive: %s"
                             % (leaf, self.ambiguous[leaf]))
        return self.by_leaf.get(leaf)

    def sprite_meta(self, sprite):
        p = self.find_asset(sprite, ".meta.toml")
        if not p:
            return None
        d = {}
        for line in self.read(p).decode("utf-8", "replace").split("\n"):
            m = KV.match(line)
            if m:
                d[m.group(1)] = m.group(2).split("#")[0].strip()
        return d

    def sprite_frames(self, sprite):
        """-> (list of PIL frames, frame_w, frame_h, meta)."""
        meta = self.sprite_meta(sprite)
        png = self.find_asset(sprite, ".png")
        if meta is None or png is None:
            raise KeyError("sprite %r not in the archive" % sprite)
        im = Image.open(io.BytesIO(self.read(png))).convert("RGBA")
        fs = as_int_pair(meta.get("frame_size")) or im.size
        fw, fh = fs
        n = im.width // fw
        return ([im.crop((i * fw, 0, (i + 1) * fw, fh)) for i in range(n)],
                fw, fh, meta)


def resolve_anchor(raw, size):
    """`horizontal`/`vertical` -> a NUMBER.

    `"Middle"` resolves to size/2 (MOMI CompactFurnitureGenerator.cs:232-236,
    `AnchorToShapeOffset`).  Two chests -- dragon and spring-festival -- write
    the string, and art recon H7 is precisely that growing the overlay canvas
    for `face_pad` while KEEPING the string shifts the art by pad/2, silently.
    `_geom.py` therefore only ever carries numbers."""
    v = unquote(raw)
    if v is None:
        return 0.0
    if v.lower() == "middle":
        return float(size // 2)
    if v.lower() in ("left", "top"):
        return 0.0
    if v.lower() in ("right", "bottom"):
        return float(size)
    return float(v)


def mask_of(im):
    px = im.load()
    return tuple(tuple(px[x, y][3] != 0 for x in range(im.width))
                 for y in range(im.height))


# --------------------------------------------------------------------------
# Census + measurement
# --------------------------------------------------------------------------

ROLES = (("closed", "sprite"), ("opened", "open_sprite"),
         ("opening", "opening_sprite"), ("bounce", "bounce_sprite"))

# The `interaction_chest` keys a twin must copy verbatim beyond the four
# sprites and inventory_size.  Measured over all 62: `bark_offset` on the two
# cottage fridges and the five deluxe iceboxes, the two SFX on the four mist
# chests, and nothing else (art recon Q1.1 / H12).
CARRY_KEYS = ("bark_offset", "open_sfx", "close_sfx")


def census(ar):
    """Every `interaction_chest` prototype, joined to its placing item."""
    furn = parse_tables(ar.read(FURNITURE_TOML).decode("utf-8", "replace"))

    chest_keys = []
    for name in furn:
        if name == "default":
            continue
        if name.endswith(".interaction_chest"):
            key = name[:-len(".interaction_chest")]
            if "." not in key:
                chest_keys.append(key)
    chest_keys.sort()

    # every item whose `object` names one of them
    wanted = set(chest_keys)
    items = {}
    for entry in sorted(ar.zf.namelist()):
        if not entry.startswith(ITEMS_PREFIX) or not entry.endswith(".toml"):
            continue
        tabs = parse_tables(ar.read(entry).decode("utf-8", "replace"))
        for tname, body in tabs.items():
            if "." in tname:
                continue
            obj = unquote(body.get("object"))
            if obj in wanted:
                items.setdefault(obj, []).append(dict(
                    item=tname,
                    icon=unquote(body.get("icon_sprite")),
                    name=unquote(body.get("name")),
                    file=entry[len("assets/fiddle/"):]))

    rows = []
    for key in chest_keys:
        root = furn.get(key, {})
        south = furn.get(key + ".south", {})
        ic = furn.get(key + ".interaction_chest", {})
        its = sorted(items.get(key, []), key=lambda d: d["item"])
        rows.append(dict(
            key=key,
            footprint=as_int_pair(root.get("size")) or (1, 1),
            proto_offset=as_int_pair(south.get("offset")),
            inventory_size=int(re.findall(r"\d+", ic.get("inventory_size",
                                                         "0"))[0]),
            belongs_to_ari=unquote(ic.get("belongs_to_ari")),
            shipping_bin=unquote(ic.get("shipping_bin")),
            sprites={role: unquote(south.get(field) if field == "sprite"
                                   else ic.get(field))
                     for role, field in ROLES},
            carry={k: ic[k] for k in CARRY_KEYS if k in ic},
            items=its))
    return rows


def measure(ar, row):
    """All four role strips of one chest, reduced to masks and bands."""
    frames = {}
    fw = fh = None
    meta0 = None
    for role, _field in ROLES:
        name = row["sprites"][role]
        if not name:
            raise KeyError("%s has no %s sprite" % (row["key"], role))
        fr, w, h, meta = ar.sprite_frames(name)
        if fw is None:
            fw, fh, meta0 = w, h, meta
        elif (w, h) != (fw, fh):
            raise ValueError("%s: %s is %dx%d, closed is %dx%d"
                             % (row["key"], role, w, h, fw, fh))
        frames[role] = [mask_of(f) for f in fr]

    closed = frames["closed"][0]
    lid = frames["closed"] + frames["opened"] + frames["opening"]
    bnc = frames["bounce"]

    def band(masks):
        rs = [y for y in range(fh) if any(m[y] != closed[y] for m in masks)]
        return (min(rs), max(rs)) if rs else (None, None)

    lid_band = band(lid)
    bounce_band = band(bnc)

    every = lid + bnc
    rows_any = [y for y in range(fh) if any(any(m[y]) for m in every)]
    top_all = min(rows_any)
    base_row = max(y for y in range(fh) if any(closed[y]))
    lid_safe = (lid_band[1] + 1) if lid_band[1] is not None else top_all

    rim = []
    for y in range(lid_safe, base_row + 1):
        xs = [x for x in range(fw) if closed[y][x]]
        if xs:
            rim.append((y, min(xs), max(xs)))

    face_pad = max(0, FACE_NEED - top_all)

    cols_any = [x for x in range(fw) if any(closed[y][x] for y in range(fh))]
    rows_closed = [y for y in range(fh) if any(closed[y])]
    closed_bbox = (min(cols_any), min(rows_closed),
                   max(cols_any) + 1, max(rows_closed) + 1)

    return dict(
        canvas=(fw, fh),
        closed_bbox=closed_bbox,
        pivot=(resolve_anchor(meta0.get("horizontal"), fw),
               resolve_anchor(meta0.get("vertical"), fh)),
        pivot_raw=(meta0.get("horizontal"), meta0.get("vertical")),
        top_all=top_all,
        base_row=base_row,
        lid_band=lid_band,
        bounce_band=bounce_band,
        lid_safe=lid_safe,
        glow_rows=len(rim),
        face_pad=face_pad,
        face_y0=top_all + face_pad - (FACE_H + FACE_BOB_DOWN),
        rim=tuple(rim),
        signature=(fw, fh,
                   resolve_anchor(meta0.get("horizontal"), fw),
                   resolve_anchor(meta0.get("vertical"), fh),
                   tuple(tuple(frames[r][i] for i in range(len(frames[r])))
                         for r, _f in ROLES)),
    )


def group_families(measured):
    """Exact-signature grouping.  Compared pivot-aligned: two chests share a
    signature only if their canvas, their pivot and every alpha mask of all
    four role strips are identical, which is the very property the family
    contract asserts (`_kit` generates ONE overlay pair per family)."""
    groups = {}
    for key in sorted(measured):
        groups.setdefault(measured[key]["signature"], []).append(key)
    return [sorted(v) for v in groups.values()]


# --------------------------------------------------------------------------
# Emitting crates/_geom.py
# --------------------------------------------------------------------------

HEADER = '''#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""crates/_geom.py -- GENERATED, READ-ONLY.  Do not hand-edit.

Per-family and per-member geometry for the Beta 1.3 chest twins, derived from
the game archive by `tools/gen_crate_geom.py` and CHECKED IN so `make_art.py`
stays hermetic: a build must not change its bytes because a game is or is not
installed, or because a different game build is.  (Same pairing as
`VANILLA_ITEMCOUNT_GLYPHS` + `check_font_against_vanilla()` in make_art.py.)

ARCHIVE DRIFT.  These numbers describe one game build.  A patch that moves a
chest sprite by a pixel silently desyncs every glow in that family, and
nothing at build time can see it.  After any game update run

    python tools/gen_crate_geom.py --check

which re-derives everything from the archive and exits non-zero on any
disagreement with this file.  Then regenerate and re-judge the contact sheet.

PIVOTS ARE NUMBERS, ALWAYS.  Two chests (`dragon_chest`,
`spring_festival_flower_chest`) write `vertical = "Middle"` in their sprite
meta.  MOMI resolves that to size/2 (CompactFurnitureGenerator.cs:232-236), so
an overlay whose canvas is grown by `face_pad` while keeping the string would
shift by pad/2 -- silently, because the string stays valid.  Resolved here,
once.

FIELDS
  canvas       (W, H) of every role strip of the family
  closed_bbox  (x0, y0, x1, y1) opaque bounds of the CLOSED pose, x1/y1
               exclusive.  The overlay strips' paired `poly_` Shapes are sized
               from THIS -- the box belongs to the object the overlay is drawn
               on, which is the vanilla chest, not to the overlay's own few
               lit pixels
  pivot        (horizontal, vertical), numbers, from the body sprite's meta
  top_all      topmost opaque row over ALL poses of ALL four role strips
  base_row     last opaque row of the CLOSED pose -- where the unit plants
  lid_band     (top, bot) rows that differ between closed / opened / opening,
               or (None, None) when the opened silhouette equals the closed one
  bounce_band  the same for the bounce strip (transient: art recon H6 accepts
               a 1-3px misalignment for the <1s a Throw-bounce plays)
  lid_safe     first row at or below which a glow pixel is safe in every pose
  glow_rows    how many rows of silhouette that leaves -- 0 means the generic
               rim drawer has nothing to trace and the family MUST override
  face_pad     rows of canvas the offline strip adds ABOVE the body so the sad
               face clears it; the offline canvas is (W, H + face_pad) and its
               pivot is (h, v + face_pad)
  face_y0      the bubble's un-bobbed top row, in OFFLINE-canvas coordinates
  rim          ((y, xleft, xright), ...) for every row of the CLOSED pose from
               lid_safe down to base_row -- the path the generic glow traces

MEMBERS[key]["carry"] holds the optional `interaction_chest` keys a twin must
copy VERBATIM, as raw TOML value text (quotes included) so a generator can
splice them without re-quoting: `bark_offset` on the two cottage fridges and
the five deluxe iceboxes, `open_sfx`/`close_sfx` on the four mist chests.  A
twin that drops them barks in the wrong place or opens with the wrong sound.
"""

'''


def py_repr(v):
    if isinstance(v, float):
        return repr(v)
    if isinstance(v, tuple):
        if not v:
            return "()"
        return "(" + ", ".join(py_repr(x) for x in v) + ("," if len(v) == 1
                                                         else "") + ")"
    return repr(v)


def emit(families, members, source_note):
    out = [HEADER]
    out.append("SOURCE = %r\n\n" % source_note)
    out.append('''
class Geom(object):
    """One family's geometry.  Attribute access, no setters: a family module
    reads this and never writes it."""

    __slots__ = ("family", "rep", "members", "canvas", "closed_bbox",
                 "pivot", "top_all", "base_row", "lid_band", "bounce_band",
                 "lid_safe", "glow_rows", "face_pad", "face_y0", "rim")

    def __init__(self, **kw):
        for k in self.__slots__:
            object.__setattr__(self, k, kw[k])

    def __setattr__(self, k, v):
        raise AttributeError("crates/_geom.py is generated and read-only "
                             "(tried to set %r)" % k)

    @property
    def width(self):
        return self.canvas[0]

    @property
    def height(self):
        return self.canvas[1]

    @property
    def offline_canvas(self):
        return (self.canvas[0], self.canvas[1] + self.face_pad)

    @property
    def offline_pivot(self):
        return (self.pivot[0], self.pivot[1] + self.face_pad)

    def __repr__(self):
        return "<Geom %s %dx%d rim=%d rows pad=%d>" % (
            self.family, self.canvas[0], self.canvas[1],
            len(self.rim), self.face_pad)


''')

    out.append("# ---- per-family geometry "
               + "-" * 49 + "\n\nFAMILIES = {\n")
    for fam in sorted(families):
        f = families[fam]
        out.append('    "%s": Geom(\n' % fam)
        out.append('        family="%s",\n' % fam)
        out.append('        rep="%s",\n' % f["rep"])
        out.append('        members=%s,\n' % py_repr(tuple(f["members"])))
        for k in ("canvas", "closed_bbox", "pivot", "top_all", "base_row",
                  "lid_band", "bounce_band", "lid_safe", "glow_rows",
                  "face_pad", "face_y0"):
            out.append("        %s=%s,\n" % (k, py_repr(f[k])))
        out.append("        rim=(\n")
        for (y, xl, xr) in f["rim"]:
            out.append("            (%d, %d, %d),\n" % (y, xl, xr))
        out.append("        ),\n    ),\n")
    out.append("}\n\n")

    out.append("# ---- per-member identity " + "-" * 49 + "\n#\n"
               "# `sprites` are VANILLA asset names: the twin's prototype "
               "sets them by string\n# and IS that chest -- same pixels, same "
               "frame counts, same durations, and\n# vanilla's own `poly_` "
               "and shadow_manifest entry come with them.  No body art\n"
               "# is generated for a twin, ever.\n\n")
    out.append("MEMBERS = {\n")
    for key in sorted(members):
        m = members[key]
        out.append('    "%s": {\n' % key)
        out.append('        "family": "%s",\n' % m["family"])
        out.append('        "item": %s,\n' % py_repr(m["item"]))
        out.append('        "icon": %s,\n' % py_repr(m["icon"]))
        out.append('        "inventory_size": %d,\n' % m["inventory_size"])
        out.append('        "footprint": %s,\n' % py_repr(m["footprint"]))
        out.append('        "proto_offset": %s,\n' % py_repr(m["proto_offset"]))
        out.append('        "sprites": {\n')
        for role, _f in ROLES:
            out.append('            "%s": "%s",\n' % (role, m["sprites"][role]))
        out.append("        },\n")
        if m["carry"]:
            out.append('        "carry": {%s},\n'
                       % ", ".join('"%s": %r' % (k, v)
                                   for k, v in sorted(m["carry"].items())))
        else:
            out.append('        "carry": {},\n')
        out.append("    },\n")
    out.append("}\n\n")

    out.append("# ---- never twinned " + "-" * 55 + "\n\nEXCLUDED = {\n")
    for k in sorted(EXCLUDED):
        out.append('    "%s":\n        "%s",\n' % (k, EXCLUDED[k]))
    out.append("}\n\n")

    out.append('''
# GEOM is the flat view the family spec names: GEOM[<chest object key>] gives
# that chest's family Geom.  Every member of a family shares one Geom object
# by construction -- the grouping that built this file is exact mask identity,
# so there is nothing per-member left to vary.
GEOM = {key: FAMILIES[m["family"]] for key, m in MEMBERS.items()}


def members_of(family):
    """Every twinned chest of `family`, in sorted order."""
    return list(FAMILIES[family].members)
''')
    return "".join(out)


# --------------------------------------------------------------------------
# The recon cross-check
# --------------------------------------------------------------------------


def recon_diff(measured):
    """Diff every measured field against the b13 recon's own artifacts."""
    path = RECON + "/overlay_geom2.json"
    if not os.path.isfile(path):
        return ["recon cross-check SKIPPED (no %s)" % path]
    with open(path, encoding="utf-8") as fh:
        recon = {e["key"]: e for e in json.load(fh)}
    notes = []
    for key in sorted(measured):
        if key not in recon:
            notes.append("%s: absent from overlay_geom2.json" % key)
            continue
        r, m = recon[key], measured[key]
        checks = [
            ("canvas", tuple(r["canvas"]), m["canvas"]),
            ("top_all", r["top_all"], m["top_all"]),
            ("base_row", r["base_row"], m["base_row"]),
            ("lid_band", tuple(r["lid_band"]), m["lid_band"]),
            ("bounce_band", tuple(r["bounce_band"]), m["bounce_band"]),
            ("lid_safe", r["lid_safe"], m["lid_safe"]),
            ("glow_rows", r["glow_rows"], m["glow_rows"]),
            ("rim", tuple(tuple(t) for t in r["rim"]), m["rim"]),
        ]
        for label, a, b in checks:
            if a != b:
                notes.append("%s: %s recon=%s measured=%s"
                             % (key, label, a, b))
        # face_pad is EXPECTED to differ by exactly one wherever it binds --
        # see the FACE_NEED comment.  Report it as an explained delta, not a
        # disagreement, and shout if the delta is anything else.
        if r["face_pad"] != m["face_pad"]:
            delta = m["face_pad"] - r["face_pad"]
            notes.append("%s: face_pad recon=%d measured=%d (%s)"
                         % (key, r["face_pad"], m["face_pad"],
                            "+1, the documented off-by-one" if delta == 1
                            else "UNEXPECTED delta %+d" % delta))
    return notes


# --------------------------------------------------------------------------
# main
# --------------------------------------------------------------------------


def build():
    zip_path = os.environ.get("FOM_ASSETS_ZIP", GAME_ASSETS_ZIP)
    if not os.path.isfile(zip_path):
        sys.exit("gen_crate_geom: no game archive at %s\n"
                 "(set FOM_ASSETS_ZIP)  -- crates/_geom.py is checked in, so "
                 "this script is only needed to regenerate or verify it."
                 % zip_path)
    ar = Archive(zip_path)
    rows = census(ar)
    measured = {}
    for row in rows:
        measured[row["key"]] = measure(ar, row)
    return zip_path, rows, measured


def assemble(rows, measured):
    by_key = {r["key"]: r for r in rows}
    groups = group_families(measured)

    problems = []
    families, members = {}, {}
    named = set()

    for grp in sorted(groups, key=lambda g: g[0]):
        reps = [k for k in grp if k in FAMILY_NAME]
        if not reps:
            if all(k in EXCLUDED for k in grp):
                continue                      # the two excluded fixtures
            problems.append("unnamed family %s -- add a FAMILY_NAME entry"
                            % (grp,))
            continue
        if len(reps) > 1:
            problems.append("family %s names %d representatives: %s"
                            % (grp, len(reps), reps))
        rep = reps[0]
        named.add(rep)
        fam = FAMILY_NAME[rep]
        twinned = [k for k in grp if k not in EXCLUDED]
        if not twinned:
            continue
        g = measured[rep]
        # the contract the family spec asserts, checked rather than assumed
        for k in twinned:
            for field in ("canvas", "closed_bbox", "pivot", "rim",
                          "lid_band", "lid_safe", "top_all", "base_row",
                          "face_pad"):
                if measured[k][field] != g[field]:
                    problems.append("%s: %s differs from rep %s (%s vs %s)"
                                    % (k, field, rep, measured[k][field],
                                       g[field]))
        families[fam] = dict(rep=rep, members=twinned, **{
            k: g[k] for k in ("canvas", "closed_bbox", "pivot", "top_all",
                              "base_row", "lid_band", "bounce_band",
                              "lid_safe", "glow_rows", "face_pad", "face_y0",
                              "rim")})
        for k in twinned:
            row = by_key[k]
            it = row["items"][0] if row["items"] else None
            if it is None:
                problems.append("%s: no item places it, yet it is twinned" % k)
            members[k] = dict(
                family=fam, item=(it or {}).get("item"),
                icon=(it or {}).get("icon"),
                inventory_size=row["inventory_size"],
                footprint=row["footprint"],
                proto_offset=row["proto_offset"],
                sprites=row["sprites"], carry=row["carry"])

    for rep in sorted(set(FAMILY_NAME) - named):
        problems.append("FAMILY_NAME names %r, which is not any group's "
                        "representative" % rep)
    return families, members, groups, problems


def main(argv):
    check = "--check" in argv
    show_recon = "--recon" in argv

    zip_path, rows, measured = build()
    families, members, groups, problems = assemble(rows, measured)

    print("")
    print("gen_crate_geom -- %s" % zip_path)
    print("chests with an interaction_chest prototype : %d" % len(rows))
    print("exact-signature families                   : %d" % len(groups))
    print("families in scope (excluded fixtures out)  : %d" % len(families))
    print("twinned members                            : %d" % len(members))
    print("")
    print("%-12s %3s %-8s %-11s %-7s %-11s %-9s %-5s %-4s %-4s %s"
          % ("FAMILY", "n", "canvas", "pivot", "topAll", "lid band",
             "lid_safe", "glow", "pad", "y0", "representative"))
    print("-" * 118)
    for fam in sorted(families):
        f = families[fam]
        print("%-12s %3d %-8s %-11s %-7d %-11s %-9d %-5d %-4d %-4d %s"
              % (fam, len(f["members"]), "%dx%d" % f["canvas"],
                 "%g/%g" % f["pivot"], f["top_all"],
                 "%s..%s" % f["lid_band"], f["lid_safe"], f["glow_rows"],
                 f["face_pad"], f["face_y0"], f["rep"]))
    print("-" * 118)

    if show_recon:
        notes = recon_diff(measured)
        print("")
        print("RECON CROSS-CHECK (overlay_geom2.json), %d note(s):"
              % len(notes))
        for n in notes:
            print("  " + n)

    text = emit(families, members,
                "generated by tools/gen_crate_geom.py from " + zip_path)

    if problems:
        print("")
        print("PROBLEMS (%d):" % len(problems))
        for p in problems:
            print("  " + p)
        print("")
        print("RESULT: FAIL -- nothing written")
        return 1

    if check:
        if not os.path.isfile(OUT):
            print("RESULT: FAIL -- no committed %s to check against" % OUT)
            return 1
        with open(OUT, encoding="utf-8") as fh:
            have = fh.read()
        if have == text:
            print("RESULT: PASS -- crates/_geom.py matches the archive")
            return 0
        print("RESULT: FAIL -- crates/_geom.py has DRIFTED from the archive")
        import difflib
        diff = list(difflib.unified_diff(have.splitlines(),
                                         text.splitlines(),
                                         "committed", "archive", n=1))
        for line in diff[:80]:
            print("  " + line)
        if len(diff) > 80:
            print("  ... %d more diff lines" % (len(diff) - 80))
        return 1

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(text)
    print("")
    print("wrote %s (%d bytes)" % (OUT, len(text)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
