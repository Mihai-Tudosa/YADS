#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""crates/ -- the Beta 1.3 chest twins.  THIS FILE IS NEVER EDITED BY A FAMILY.

That is its entire reason for existing.  Fourteen families are authored in
parallel, and a registry that had to be edited once per family would be the one
merge point in an otherwise disjoint fan-out.  So it GLOBS: drop
`fam_<family>.py` in this directory and it is discovered, in sorted filename
order, with no other file touched anywhere in the repository.

WHAT A FAMILY MODULE MUST EXPORT
  MEMBERS   list of the vanilla chest object keys this family twins.  It must
            equal `_geom.FAMILIES[<family>].members` exactly -- the geometry
            table already knows every chest of every family, so a MEMBERS that
            disagrees means a chest has silently lost its twin or gained one,
            and that is a save-serialized content key either way.
  REP       the member the two overlay strips are generated from.  Editorial:
            the grouping in `tools/gen_crate_geom.py` is exact mask identity,
            so every member of a family is pixel-identical in silhouette.

WHAT IT MAY EXPORT
  PARAMS    a `_kit.GlowParams` tuning the generic glow (diodes, drop bands,
            seam position).
  glow(kit, geom, f)     -> kit.Canvas, overriding the generic drawer entirely.
  offline(kit, geom, f)  -> kit.Canvas, likewise for the sad face.

The family name is the module's own suffix: `fam_basic_wood.py` is family
`basic_wood`, whose strips are `spr_furniture_netstor_crate_basic_wood_glow`
and `..._offline`.  Those are asset names resolved BY STRING from a prototype,
so they freeze the moment they ship.

Import order is `sorted(glob("fam_*.py"))` -- filename order, never filesystem
order and never import order, because `make_art.py`'s contract is that a clean
run is byte-identical and directory enumeration is not stable across machines.
"""

import glob as _glob
import importlib as _importlib
import os as _os

# _kit and _geom are imported FIRST and bound onto the package, so a family
# module's `from crates import _kit as kit` resolves while this file is still
# executing.
from . import _geom, _kit                        # noqa: F401
from ._geom import GEOM, MEMBERS, EXCLUDED       # noqa: F401

KIT = _kit
GEOM_BY_FAMILY = _geom.FAMILIES

_HERE = _os.path.dirname(_os.path.abspath(__file__))


class FamilyError(Exception):
    """A structural fault in a family module.  Raised at import: a family that
    does not describe itself correctly cannot be drawn, and generating 13
    correct families plus one silently wrong one is the worst outcome."""


def _load():
    mods = []
    for path in sorted(_glob.glob(_os.path.join(_HERE, "fam_*.py"))):
        modname = _os.path.basename(path)[:-3]
        mod = _importlib.import_module("." + modname, __name__)
        family = modname[len("fam_"):]
        if family not in GEOM_BY_FAMILY:
            raise FamilyError(
                "%s.py: no family %r in crates/_geom.py.  Known families: %s"
                % (modname, family, ", ".join(sorted(GEOM_BY_FAMILY))))
        geom = GEOM_BY_FAMILY[family]

        members = getattr(mod, "MEMBERS", None)
        if not members:
            raise FamilyError("%s.py: no MEMBERS table" % modname)
        if list(members) != list(geom.members):
            missing = [k for k in geom.members if k not in members]
            extra = [k for k in members if k not in geom.members]
            raise FamilyError(
                "%s.py: MEMBERS disagrees with crates/_geom.py.  missing=%s "
                "extra=%s  (order must match too; _geom lists them sorted)"
                % (modname, missing, extra))

        rep = getattr(mod, "REP", None)
        if rep not in members:
            raise FamilyError("%s.py: REP %r is not in MEMBERS" % (modname, rep))

        for hook in ("glow", "offline"):
            fn = getattr(mod, hook, None)
            if fn is not None and not callable(fn):
                raise FamilyError("%s.py: %s must be a function "
                                  "(kit, geom, f) -> kit.Canvas"
                                  % (modname, hook))

        mod.FAMILY = family
        mod.GEOM = geom
        mods.append(mod)
    return mods


FAMILIES = _load()

# Sprite names.  Per FAMILY, not per chest: within a family the rim path, the
# canvas and the pivot are identical, and the glow carries no chest colour at
# all (it is pure G1/G2/G3 luminance by mandate), so thirteen deluxe prototypes
# can all name one `top_sprite`.  14 families x 2 strips = 28 sprites, against
# 480 for a per-chest body recipe.
SPRITE_PREFIX = "spr_furniture_netstor_crate_"


def glow_sprite(family):
    return SPRITE_PREFIX + family + "_glow"


def offline_sprite(family):
    return SPRITE_PREFIX + family + "_offline"


def selected(names=None):
    """The families to render.  `names` is the `--families=a,b` filter: a
    family agent renders only its own rows during its review loop."""
    if not names:
        return list(FAMILIES)
    want = {n.strip() for n in names if n.strip()}
    unknown = want - {m.FAMILY for m in FAMILIES}
    if unknown:
        raise FamilyError("--families names %s, which %s no fam_*.py here"
                          % (", ".join(sorted(unknown)),
                             "have" if len(unknown) > 1 else "has"))
    return [m for m in FAMILIES if m.FAMILY in want]
