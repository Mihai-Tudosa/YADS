#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""make_fiddle.py -- the Beta 1.3 chest-twin ("crate") fiddle generator.

Emits, from `crates/_geom.py` plus the checked-in `SOURCE_ITEMS` table below:

  1. 59 object prototypes, SPLICED into
     `yads/fiddle/object_prototypes/furniture.toml` between two sentinel
     comment lines.  That file is NOT splittable: GridPrototypes.gml:69 loads
     prototypes as `fiddle_get("object_prototypes/" + category_name)` where the
     category IS the file name, so a second file would be a category the engine
     never reads.  Everything outside the sentinels is byte-identical after a
     run and the generator asserts it rather than claiming it.
  2. 59 items, written WHOLE into
     `yads/fiddle/items/furniture/netstor_crates.toml`.  Item files ARE
     auto-discovered under `fiddle/items/**`, so this one may be its own file.
  3. `crate_unit_keys.generated.gml` at the repo root -- the 59 rows for the
     UNIT_KEYS seam in `yads/gml/network.gml` section 1.  This generator does
     NOT edit yads/gml; it emits the rows and says where they go.

WHY A GENERATOR AND NOT HAND-WRITTEN TOML.  Every key here is save-serialized
BY NAME.  Grid.gml:1075-1082 drops a saved node whose `object_id` string no
longer resolves and it drops it WITH ITS WHOLE INVENTORY, so a typo in one of
these 59 names is a silent deletion of a player's items.  A checked-in
deterministic generator is the only shape in which "these 59 names never
change" is a property of the repository rather than a property of nobody having
edited the file lately.  Run it twice: the second run must produce no diff.

    python make_fiddle.py                      # write into ./yads
    python make_fiddle.py <mod dir>            # write into another tree
    python make_fiddle.py --dry-run            # report only, touch nothing
    python make_fiddle.py --check-vanilla      # re-derive from the game corpus
                                               #   (FOM_CORPUS, or pass a path)

======================================================================
THE DESIGN, stated once
======================================================================

Each of 59 vanilla chests gets ONE twin that is a full network member exactly
like a Storage Block.  The twin's BODY is the vanilla chest's own sprite, named
by the prototype: a mod prototype may name a vanilla sprite (Furniture.gml:216
resolves `sprite` through `string_to_asset` against the global asset table).
So the twin IS that chest -- same pixels, same frame counts, same durations --
and the collision poly, the shadow-manifest entry, the item icon and its
`outlines.json` entry all come free, because they are vanilla's and they are
keyed by the sprite name we just reused.  A twin therefore ships NO body art.

The "this is networked" signal is entirely `top_sprite`: the per-FAMILY glow
overlay that the `crates/` package generates,
`spr_furniture_netstor_crate_<family>_glow`.  One overlay pair serves every
member of a family because within a family the canvas, the pivot and the rim
path are identical (exact mask identity is how `tools/gen_crate_geom.py`
grouped them) and the glow carries no chest colour at all.

Keys are `netstor_crate_<vanilla object key>`, object key == item key, which is
what makes the converter's mapping a string concat.

======================================================================
THE FIVE THINGS THAT MUST NOT BE GOT WRONG, and why each is what it is
======================================================================

`value` -- LITERAL NUMBERS, NEVER A CROSS-ITEM REFERENCE.  ***
    The obvious copy is wrong and the obvious fix is ALSO wrong.

    Wrong #1, copying verbatim: 35 of the 59 source chests carry
    `value = { bin = "self.recipe * 1.1" }`.  A twin has no recipe (see below),
    and `self.recipe` reaches
        assert_neq(lhs.recipe, undefined,
                   "Tried to calculate a value based on {ItemId}'s recipe, but
                    it has none!")                            Items.gml:461-467
    which is a hard failure during `create_item_prototypes`, i.e. at load.

    Wrong #2, the cross-item reference `bin = "<source>.bin"`.  This is widely
    believed to be safe "at any enum ordering" because `query_item_price_expr`
    re-enters on an unresolved string.  IT IS NOT.  Read the re-entry:

        Items.gml:488-490
            if is_string(output) {
                output = query_item_price(output, ident, wip_items);
            }

    `ident` is the ORIGINAL item -- the TWIN -- not `lhs.item_id`.  (Contrast
    Items.gml:476-478, the recipe-component arm, which correctly passes
    `component.item_id`.)  So when the source's own `bin` has not been resolved
    yet and is still the string `"self.recipe * 1.1"`, the re-entry evaluates
    `self` against the TWIN and hits the very assert we were avoiding.

    Items.gml:376-409 resolves in ItemId order, writing each number back into
    the collection, and ItemId is minted alphabetically from the fiddle keys.
    `netstor_crate_*` therefore resolves BEFORE every source whose key sorts
    after "n" -- royal (6), stone (3), void (2), spring_festival (1) = 12 -- and
    11 of those 12 sources use `self.recipe * 1.1`.  Simulated against a
    faithful port of the resolver: the reference form hard-asserts on exactly
    those 11 twins.  Relative alphabetical order is stable under other mods'
    insertions, so this is not a rare race; it is a guaranteed crash.

    Also unsafe in the other direction: a source whose `bin` defaults to
    `"self.store * 0.5"` (Items.gml:11) would make the twin's `store` reference
    re-enter into `self.store` -> the twin's own unresolved `"<source>.store"`
    -> `query_item_price_expr` with `<source>` already on STACK -> the explicit
    `crash("Infinite recursion found in prices ...")` at Items.gml:435-440.

    So: LITERALS.  `SOURCE_ITEMS` carries each source's fully resolved `bin`
    and `store`, derived by `--check-vanilla` from the corpus with a faithful
    port of PARSE_ITEM's defaults + query_item_price + query_item_price_expr.
    Two literal reals mean `query_item_price` returns on its first line
    (`if is_real(input) { return input; }`, Items.gml:509-511) and the resolver
    is never entered at all.  `value` is re-derived from the prototype on every
    load and is NOT save-serialized, so unlike a key or an inventory_size this
    is the one number here that a later release may safely correct.

NO RECIPE -- deliberate, not an omission.
    CraftingMenu.gml:1373-1383 pushes an item into a crafting sub-category only
    if `proto.recipe != undefined`.  A recipe-less twin is therefore never
    pushed -- not as a locked row, not as a greyed row -- so 59 twins cannot
    flood any tab.  Conversion is the only source.  Corollaries kept below:
    no `recipe_is_default` (it would reach `ARI.unlock_recipe` and its
    "learned recipe" popup for a recipe that does not exist), no
    `crafting_level_requirement` (Items.gml:335-339 defaults it to 1 for any
    `furniture`-tagged item, and the only assert that reads it is gated on
    `use == Consume`, Items.gml:379-392), and nothing added to `ITEM_KEYS` in
    boot.gml section 4, which is the RECIPE backfill list and a different seam.

`inventory_size` -- INHERITED FROM THE SOURCE AND FROZEN FOREVER.
    Grid.gml:1139-1145 force-resizes every loaded chest to its CURRENT
    prototype size, and Inventory.gml:49-52 is
        while self.size() > new_size { self.slots.pop(); }
    which pops trailing slots UNDRAINED -- no drain, no `lost_items`, no drop.
    Lowering a shipped twin's size therefore silently deletes the tail of every
    save that used it.  30/42/54 are all legal StorageMenu grid keys, mixed
    capacities in one network are already proven fine (the heart is 54, blocks
    are 30, panels 4), so inheriting costs nothing and matching the chest the
    player converted is the honest behaviour.

`destructable` -- NEVER WRITTEN HERE.
    It is re-derived by the engine from the prototype and then re-forced to
    `false` on any `TileFlag.Unbreakable` cell (Furniture.gml:649, :685-687).
    It is ALSO serialized, through generic struct walkers that never name the
    field (docs/safety-invariants.md, "THE SERIALIZATION TRUTH"), so a value
    written into twin data would be a permission this mod granted, surviving
    into the save and past uninstallation.  The vanilla `[default]` we inherit
    is `destructable = true`; leave it alone.

`collision_grid` -- COPIED FROM THE SOURCE, OR OMITTED.  NEVER OUR MARGINS.
    The mod's own squeeze-between margin `["0110","0110"]` is deliberately NOT
    given to twins.  Three reasons, in order of weight:
      (a) a twin must behave like the chest it replaces;
      (b) `"0110"` is only meaningful on a 4-wide footprint -- the 3-wide
          families (fridge, obsidian) would need `"010"`, an 8px solid core,
          which `yads/fiddle/object_prototypes/furniture.toml` itself rejects
          as "furniture you walk through";
      (c) a walkable margin is the sole thing that makes the LOAD-ORDER
          NEAR-MISS in docs/safety-invariants.md reachable, and 59 keys with
          full collision are 59 keys with no exposure to it.
    Two sources DO declare one: both cottage fridges ship
    `collision_grid = "2"`.  A scalar string fills the whole footprint with
    `collision_string_to_value(first char)` (GridUtils.gml:535-536), and flag 2
    is `set_collision_on_node(..., can_jump_over=false, ...)`
    (GridUtils.gml:580-585) -- MORE solid than the default 1, not less, and
    not a walkable cell anywhere.  Copying it preserves "you cannot vault the
    fridge" and adds no near-miss exposure.  Omitting it would silently make
    the fridge twin jumpable where the fridge was not.
    `"-"` / -1 is never emitted: that arm strips pre-existing ROOM collision
    (GridUtils.gml:569-579).  The generator asserts both facts about its own
    output.

======================================================================
THE THREE EXCLUSIONS -- 62 chest prototypes minus 3 = 59
======================================================================
`crates/_geom.EXCLUDED` is the authority and this generator re-asserts it:
  stable_storage_chest  no item places it, so `find_item_prototype`
                        (Pick.gml:597-606) finds nothing to hand back when the
                        player picks the crate up -- an unremovable unit.
  turn_in_box           `belongs_to_ari = false` (also `destructable = false`,
                        no item): a town fixture, not player-placeable.
  starter_shipping_box  `shipping_bin = true` -- Furniture.gml:871-873 -- a
                        network member that sells the network's contents
                        overnight.

======================================================================
WHAT THIS FILE DOES NOT TOUCH
======================================================================
`yads/gml/` (the key rows are emitted to a separate file for a human to paste),
`make_art.py`, `crates/`, `tools/`, and `yads/data_files/animation/outlines.json`
-- the last one because the twins reuse the vanilla item icons and vanilla
already ships an outline entry for all 59 (3086 entries; verified by
--check-vanilla).
"""

from __future__ import annotations

import argparse
import importlib.util
import os
import re
import sys
import tomllib

HERE = os.path.dirname(os.path.abspath(__file__))


# ---------------------------------------------------------------------------
# Naming and shape.  EVERY STRING IN THIS BLOCK FREEZES THE MOMENT IT SHIPS.
# ---------------------------------------------------------------------------

KEY_PREFIX = "netstor_crate_"        # object key == item key
RECIPE_KEY = "netstor_crate"         # ONE shared key -> ONE almanac row
NAME_PREFIX = "Networked "
DESCRIPTION = ("Wired into a storage network. Adjoin it to a Storage Heart to "
               "pool its space.")

# TAGS.  `furniture` is what puts a placeable in the almanac's Furniture lens
# and what Items.gml:335-339 reads to default crafting_level_requirement;
# `chest_and_storage` is the vanilla Chests & Storage crafting sub-category tag
# (fiddle/ui/crafting/woodcrafting.toml:332 -- its ONLY reader in the whole
# game, and a recipe-less item never reaches it).  Both match what the three
# shipped netstor placeables carry.
#
# DELIBERATELY ABSENT: `netstor_set`.  That tag is the selector for the mod's
# own "Digital Storage" crafting sub-category, and tagging 59 recipe-less
# crates with it would be 59 items advertising a tab they can never appear in.
# The tab keeps exactly its five rows.
TAGS = ("furniture", "chest_and_storage")

# ONE SHARED recipe_key ACROSS ALL 59.  AlmanacMenu.gml:14-20 dedups its lens
# on `proto.recipe_key`, so 59 twins sharing one key collapse to a SINGLE
# almanac row instead of 59, and `mark_item_as_acquired` (Ari.gml:554-563)
# marks that row acquired the first time the player obtains any crate.  Safe
# because the other four readers of recipe_key are all recipe-gated and the
# twins have no recipe: Ari.gml:663-680 (unlock_recipe), TooltipMenu.gml:576
# (only under `recipe_display`, which only `unlock_recipe` sets),
# Stores.gml:38-45 (store stock generation) and dungeon_utils.gml:64-72 (a
# fixed vanilla biome list).  None of them can name a twin.

TOP_SPRITE_DEPTH_OFFSET = 1          # one step in front of the body, as the
                                     # three shipped units already do

# Mirrored from crates/__init__.py and ASSERTED equal to it at run time -- the
# art package is the authority on its own sprite names and this generator must
# not be able to drift from it silently.
SPRITE_PREFIX = "spr_furniture_netstor_crate_"

# The four keys that were frozen before this wave, for the disjointness check.
FROZEN_NETSTOR_KEYS = ("netstor_heart", "netstor_block", "netstor_panel",
                       "netstor_remote")

EXPECTED_MEMBERS = 59
EXPECTED_FAMILIES = 14
EXPECTED_EXCLUSIONS = ("stable_storage_chest", "starter_shipping_box",
                       "turn_in_box")
LEGAL_INVENTORY_SIZES = (30, 42, 54)   # legal StorageMenu grid keys

# ---------------------------------------------------------------------------
# Output locations.
# ---------------------------------------------------------------------------

PROTO_REL = ("fiddle", "object_prototypes", "furniture.toml")
ITEM_REL = ("fiddle", "items", "furniture", "netstor_crates.toml")

# NOT inside yads/.  yads/gml/ is owned by the GML seam and a stray .gml file
# there would be installed as mod code; this is a paste-in artefact for a human.
KEYS_REL = "crate_unit_keys.generated.gml"

# The sentinels.  Matched by exact whole-line equality, so they must never be
# reflowed, re-indented or re-worded.
BEGIN = ("# ==== BEGIN GENERATED CRATE TWINS -- make_fiddle.py -- "
         "DO NOT EDIT BY HAND ====")
END = ("# ==== END GENERATED CRATE TWINS ---- make_fiddle.py -- "
       "DO NOT EDIT BY HAND ====")


# ---------------------------------------------------------------------------
# THE SOURCE TABLE.  GENERATED ONCE, CHECKED IN, RE-VERIFIABLE.
#
# `crates/_geom.py` already carries everything on the PROTOTYPE side -- the
# sprites, the footprint, the offset, the inventory_size and the `carry` keys.
# What it does not carry is the ITEM side, so those four numbers live here:
#
#     <vanilla chest object key>: (display name, bin, store, collision_grid)
#
# `bin` and `store` are the source item's FULLY RESOLVED prices, computed with
# a faithful port of Items.gml's PARSE_ITEM value defaults (:5-17) +
# query_item_price (:507) + query_item_price_expr (:418) over all 2665 vanilla
# items.  `collision_grid` is the source PROTOTYPE's own value, or None when it
# declares none -- only the two cottage fridges do.
#
# EMBEDDED RATHER THAN READ, for the reason crates/_geom.py is embedded and
# make_art.py's VANILLA_ITEMCOUNT_GLYPHS is embedded: a build must not change
# its bytes because a game is or is not installed.  `--check-vanilla`
# re-derives all four from the corpus and fails on any drift, and reports
# SKIPPED when the corpus is not reachable.
#
# A GAME PATCH THAT RE-PRICES A CHEST desyncs its twin's price until this table
# is regenerated.  That is a cosmetic drift, and it is the whole reason the
# literal form is preferable to the reference form, which would answer the same
# patch with a hard failure at load.
# ---------------------------------------------------------------------------

SOURCE_ITEMS = {
    # -- basic_wood
    "basic_wood_chest_black":                    ("Basic Wood Chest",                  65,    250, None),
    "basic_wood_chest_blue":                     ("Basic Wood Chest",                  65,    250, None),
    "basic_wood_chest_cottage":                  ("Basic Wood Chest",                  65,    250, None),
    "basic_wood_chest_dark":                     ("Basic Wood Chest",                  65,    250, None),
    "basic_wood_chest_green":                    ("Basic Wood Chest",                  65,    250, None),
    "basic_wood_chest_haunted_attic":            ("Basic Wood Chest",                  65,    250, None),
    "basic_wood_chest_light":                    ("Basic Wood Chest",                  65,    250, None),
    "basic_wood_chest_medium":                   ("Basic Wood Chest",                  65,    250, None),
    "basic_wood_chest_orange":                   ("Basic Wood Chest",                  65,    250, None),
    "basic_wood_chest_pink":                     ("Basic Wood Chest",                  65,    250, None),
    "basic_wood_chest_purple":                   ("Basic Wood Chest",                  65,    250, None),
    "basic_wood_chest_red":                      ("Basic Wood Chest",                  65,    250, None),
    "basic_wood_chest_white":                    ("Basic Wood Chest",                  65,    250, None),
    "basic_wood_chest_witch_queen":              ("Basic Wood Chest",                  65,    250, None),
    "basic_wood_chest_yellow":                   ("Basic Wood Chest",                  65,    250, None),
    # -- coral
    "coral_storage_chest_blue":                  ("Coral Storage Chest",              230,    460, None),
    "coral_storage_chest_purple":                ("Coral Storage Chest",              230,    460, None),
    # -- deluxe
    "deluxe_storage_chest_aqua":                 ("Deluxe Storage Chest",            9000,  10000, None),
    "deluxe_storage_chest_black":                ("Deluxe Storage Chest",            9000,  10000, None),
    "deluxe_storage_chest_blue":                 ("Deluxe Storage Chest",            9000,  10000, None),
    "deluxe_storage_chest_dark_brown":           ("Deluxe Storage Chest",            9000,  10000, None),
    "deluxe_storage_chest_gold":                 ("Deluxe Storage Chest",            9000,  10000, None),
    "deluxe_storage_chest_gray":                 ("Deluxe Storage Chest",            9000,  10000, None),
    "deluxe_storage_chest_green":                ("Deluxe Storage Chest",            9000,  10000, None),
    "deluxe_storage_chest_light_brown":          ("Deluxe Storage Chest",            9000,  10000, None),
    "deluxe_storage_chest_orange":               ("Deluxe Storage Chest",            9000,  10000, None),
    "deluxe_storage_chest_pink":                 ("Deluxe Storage Chest",            9000,  10000, None),
    "deluxe_storage_chest_purple":               ("Deluxe Storage Chest",            9000,  10000, None),
    "deluxe_storage_chest_red":                  ("Deluxe Storage Chest",            9000,  10000, None),
    "deluxe_storage_chest_white":                ("Deluxe Storage Chest",            9000,  10000, None),
    # -- dragon
    "dragon_chest":                              ("Dragon Chest",                     300,    600, None),
    # -- flower
    "spring_festival_flower_chest":              ("Breath of Spring Storage Chest",   250,   1000, None),
    # -- fridge   (the only two sources that declare a collision_grid)
    "cottage_fridge_v1":                         ("Lovely Cottage Icebox",            280,   1000, "2"),
    "cottage_fridge_v2":                         ("Lovely Cottage Icebox",            280,   1000, "2"),
    # -- icebox
    "deluxe_icebox_blue":                        ("Deluxe Icebox",                  10000,  12000, None),
    "deluxe_icebox_green":                       ("Deluxe Icebox",                  10000,  12000, None),
    "deluxe_icebox_pink":                        ("Deluxe Icebox",                  10000,  12000, None),
    "deluxe_icebox_white":                       ("Deluxe Icebox",                  10000,  12000, None),
    "deluxe_icebox_yellow":                      ("Deluxe Icebox",                  10000,  12000, None),
    # -- mimic
    "mimic_storage_chest":                       ("Mimic Storage Chest",             1220,   2440, None),
    # -- miners
    "miners_crate_chest_v1":                     ("Mines Storage Chest",              130,    260, None),
    "miners_crate_chest_v2":                     ("Mines Storage Chest",              130,    260, None),
    # -- mist
    "mist_storage_chest_v1":                     ("Mist Storage Chest",               500,   1000, None),
    "mist_storage_chest_v2":                     ("Mist Storage Chest",               500,   1000, None),
    "mist_storage_chest_v3":                     ("Mist Storage Chest",               500,   1000, None),
    "mist_storage_chest_v4":                     ("Mist Storage Chest",               500,   1000, None),
    # -- obsidian
    "lava_caves_obsidian_storage_chest_blue":    ("Obsidian Storage Chest",           760,   1520, None),
    "lava_caves_obsidian_storage_chest_purple":  ("Obsidian Storage Chest",           760,   1520, None),
    # -- royal
    "royal_chest_blue":                          ("Royal Chest",                     1840,   3680, None),
    "royal_chest_dark_wood":                     ("Royal Chest",                     1840,   3680, None),
    "royal_chest_green":                         ("Royal Chest",                     1840,   3680, None),
    "royal_chest_purple":                        ("Royal Chest",                     1840,   3680, None),
    "royal_chest_red":                           ("Royal Chest",                     1840,   3680, None),
    "royal_chest_wood":                          ("Royal Chest",                     1840,   3680, None),
    # -- stone
    "stone_storage_chest_v1":                    ("Stone Storage Chest",              380,    760, None),
    "stone_storage_chest_v2":                    ("Stone Storage Chest",              380,    760, None),
    "stone_storage_chest_v3":                    ("Stone Storage Chest",              380,    760, None),
    # -- void
    "void_storage_chest_v1":                     ("Void Storage Chest",               880,   1760, None),
    "void_storage_chest_v2":                     ("Void Storage Chest",               880,   1760, None),
}


class FiddleError(Exception):
    """A structural fault.  Every one of these is a save-serialized content key
    or a load-time crash, so the generator refuses rather than warning."""


# ---------------------------------------------------------------------------
# Inputs
# ---------------------------------------------------------------------------

def load_geom():
    """Load `crates/_geom.py` BY PATH, not as `crates._geom`.

    Importing the package would run `crates/__init__.py`, which globs and
    imports every `fam_*.py` and raises FamilyError on a malformed one.  The
    fiddle tables must be generatable while thirteen family modules are still
    being authored in parallel, so this generator depends on the geometry table
    and on nothing else in the package.  The one thing it does read out of
    `__init__.py` is SPRITE_PREFIX, and it reads it as text (see below).
    """
    path = os.path.join(HERE, "crates", "_geom.py")
    if not os.path.exists(path):
        raise FiddleError("crates/_geom.py not found at %s" % path)
    spec = importlib.util.spec_from_file_location("_yads_crate_geom", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def assert_sprite_prefix():
    """`crates/__init__.py` owns the sprite naming; we mirror it and prove the
    mirror.  Text-scraped rather than imported for the reason above."""
    path = os.path.join(HERE, "crates", "__init__.py")
    if not os.path.exists(path):
        raise FiddleError("crates/__init__.py not found at %s" % path)
    with open(path, "r", encoding="utf-8") as fh:
        src = fh.read()
    m = re.search(r'^SPRITE_PREFIX\s*=\s*"([^"]+)"', src, re.M)
    if m is None:
        raise FiddleError("crates/__init__.py has no top-level SPRITE_PREFIX")
    if m.group(1) != SPRITE_PREFIX:
        raise FiddleError(
            "SPRITE_PREFIX drift: crates/__init__.py says %r, make_fiddle.py "
            "says %r.  The art package is the authority -- every top_sprite "
            "this generator emits would name a sprite that is never drawn."
            % (m.group(1), SPRITE_PREFIX))


def glow_sprite(family):
    return SPRITE_PREFIX + family + "_glow"


def offline_sprite(family):
    """Not referenced from TOML -- network.gml resolves it at run time with the
    SOFT try_string_to_asset, so a missing offline face degrades to the
    visible-toggle path instead of failing.  Reported for the art bill only."""
    return SPRITE_PREFIX + family + "_offline"


def twin_key(chest_key):
    return KEY_PREFIX + chest_key


def ordered_families(geom):
    """Families in sorted name order.

    THE EMISSION ORDER, everywhere, is: families sorted by name, then members
    sorted within -- `for fam in ordered_families(geom): for key in
    sorted(geom.FAMILIES[fam].members)`.  Deterministic ordering is half the
    reason this is a generator rather than hand-written TOML, so nothing here
    ever iterates a dict, and the prototypes, the items and the UNIT_KEYS rows
    all come out in the same order.  Grouped by family rather than flat-sorted
    so each output reads as fourteen reviewable blocks matching the fourteen
    `crates/fam_*.py` modules and the fourteen glow sprites.
    """
    return sorted(geom.FAMILIES)


# ---------------------------------------------------------------------------
# Population gates -- run before a single byte is emitted
# ---------------------------------------------------------------------------

def check_population(geom):
    problems = []

    if len(geom.MEMBERS) != EXPECTED_MEMBERS:
        problems.append("crates/_geom.py has %d members, expected %d"
                        % (len(geom.MEMBERS), EXPECTED_MEMBERS))
    if len(geom.FAMILIES) != EXPECTED_FAMILIES:
        problems.append("crates/_geom.py has %d families, expected %d"
                        % (len(geom.FAMILIES), EXPECTED_FAMILIES))

    # The exclusions are the whole safety argument of the population; assert
    # them here so a regenerated _geom.py that quietly re-admitted one cannot
    # slip through.
    if tuple(sorted(geom.EXCLUDED)) != EXPECTED_EXCLUSIONS:
        problems.append("EXCLUDED is %s, expected %s"
                        % (tuple(sorted(geom.EXCLUDED)), EXPECTED_EXCLUSIONS))
    for key in EXPECTED_EXCLUSIONS:
        if key in geom.MEMBERS:
            problems.append("EXCLUDED chest %r is also a MEMBER" % key)
        if not geom.EXCLUDED.get(key):
            problems.append("EXCLUDED[%r] carries no reason" % key)

    # Every member belongs to exactly one family and every family member is a
    # member: a chest in neither has no twin, a chest in both gets two.
    seen = {}
    for fam in ordered_families(geom):
        for key in geom.FAMILIES[fam].members:
            if key in seen:
                problems.append("chest %r is in families %r and %r"
                                % (key, seen[key], fam))
            seen[key] = fam
            if key not in geom.MEMBERS:
                problems.append("family %r lists %r, which is not a MEMBER"
                                % (fam, key))
    for key in sorted(geom.MEMBERS):
        if key not in seen:
            problems.append("member %r belongs to no family" % key)
        elif geom.MEMBERS[key]["family"] != seen[key]:
            problems.append("member %r says family %r, listed under %r"
                            % (key, geom.MEMBERS[key]["family"], seen[key]))

    # SOURCE_ITEMS must cover exactly the population.
    missing = sorted(set(geom.MEMBERS) - set(SOURCE_ITEMS))
    extra = sorted(set(SOURCE_ITEMS) - set(geom.MEMBERS))
    if missing:
        problems.append("SOURCE_ITEMS is missing %s" % missing)
    if extra:
        problems.append("SOURCE_ITEMS has stale entries %s" % extra)

    for key in sorted(geom.MEMBERS):
        m = geom.MEMBERS[key]
        size = m["inventory_size"]
        if size not in LEGAL_INVENTORY_SIZES:
            problems.append("%s: inventory_size %r is not a legal StorageMenu "
                            "grid key %s" % (key, size, LEGAL_INVENTORY_SIZES))
        if len(m["footprint"]) != 2 or m["footprint"][0] < 1 or m["footprint"][1] < 1:
            problems.append("%s: bad footprint %r" % (key, m["footprint"]))
        for role in ("closed", "opened", "opening", "bounce"):
            if not m["sprites"].get(role, "").startswith("spr_"):
                problems.append("%s: %s sprite %r is not an spr_ name"
                                % (key, role, m["sprites"].get(role)))
        if not m["icon"].startswith("spr_"):
            problems.append("%s: icon %r is not an spr_ name" % (key, m["icon"]))

    # Source item keys must be one-to-one with the population.  Two twins
    # deriving from one source item would be two prototypes fed one name and
    # one price, and -- worse -- `find_item_prototype` (Pick.gml:597-606)
    # returns the FIRST item whose `.object` matches, so a shared source is the
    # shape in which a pickup can hand back the wrong crate.
    #
    # NOTE: the source's item key is NOT always its object key.  Two of the 59
    # differ (`cottage_fridge_v1` is placed by `cottage_fridge_oak`, `_v2` by
    # `cottage_fridge_ash`).  That is fine and is why _geom carries `item`
    # separately: the identity this design needs is that OUR twin's item key
    # equals OUR twin's object key, which it does by construction -- both are
    # KEY_PREFIX + the source OBJECT key.
    by_item = {}
    for key in sorted(geom.MEMBERS):
        src = geom.MEMBERS[key]["item"]
        if src in by_item:
            problems.append("chests %r and %r are both placed by item %r"
                            % (by_item[src], key, src))
        by_item[src] = key

    if problems:
        raise FiddleError("population gate failed:\n  " + "\n  ".join(problems))


def check_keys(geom):
    """The keys are the part that cannot be fixed after release."""
    problems = []
    keys = [twin_key(k) for k in sorted(geom.MEMBERS)]

    if len(set(keys)) != len(keys):
        dupes = sorted({k for k in keys if keys.count(k) > 1})
        problems.append("duplicate twin keys: %s" % dupes)

    clash = sorted(set(keys) & set(FROZEN_NETSTOR_KEYS))
    if clash:
        problems.append("twin key collides with a frozen netstor key: %s" % clash)

    for k in keys:
        if not re.fullmatch(r"[a-z0-9_]+", k):
            problems.append("twin key %r is not snake_case ascii" % k)

    # ObjectId/ItemId are minted by heck UpperCamelCase over the snake_case
    # key (etc/magic_enums.meta.toml), so two keys whose PascalCase forms
    # collide would mint one enum member for two prototypes.
    def pascal(s):
        return "".join(w[:1].upper() + w[1:] for w in s.split("_"))

    pas = [pascal(k) for k in keys]
    if len(set(pas)) != len(pas):
        problems.append("PascalCase enum-name collision among the twins")
    pas_frozen = {pascal(k) for k in FROZEN_NETSTOR_KEYS}
    if set(pas) & pas_frozen:
        problems.append("PascalCase collision with a frozen netstor key")

    if problems:
        raise FiddleError("key gate failed:\n  " + "\n  ".join(problems))


# ---------------------------------------------------------------------------
# Emitters
# ---------------------------------------------------------------------------

def q(s):
    """TOML basic string.  The inputs are asset names, snake_case keys and
    short English sentences; anything needing an escape is a bug, not a case
    to handle."""
    if '"' in s or "\\" in s or "\n" in s:
        raise FiddleError("string needs escaping, which means it is wrong: %r" % s)
    return '"%s"' % s


def family_banner(geom, fam):
    g = geom.FAMILIES[fam]
    members = sorted(g.members)
    sizes = sorted({geom.MEMBERS[k]["inventory_size"] for k in members})
    foot = sorted({tuple(geom.MEMBERS[k]["footprint"]) for k in members})
    carry = sorted({ck for k in members for ck in geom.MEMBERS[k]["carry"]})
    grids = sorted({SOURCE_ITEMS[k][3] for k in members if SOURCE_ITEMS[k][3]})
    line = ("# ---- %s (%d) -- %s -- inv %s -- footprint %s"
            % (fam, len(members), glow_sprite(fam),
               "/".join(str(s) for s in sizes),
               "/".join("%dx%d" % f for f in foot)))
    out = [line]
    if carry:
        out.append("#      carries %s from the source chest" % ", ".join(carry))
    if grids:
        out.append("#      collision_grid %s copied from the source chest"
                   % ", ".join(grids))
    return out


def proto_block(geom, fam, key):
    m = geom.MEMBERS[key]
    tw = twin_key(key)
    grid = SOURCE_ITEMS[key][3]

    out = ["[%s]" % tw,
           "\tsize = [%d, %d]" % (m["footprint"][0], m["footprint"][1])]
    if grid is not None:
        out.append("\tcollision_grid = %s" % q(grid))
    out.append("")
    out.append("\t[%s.south]" % tw)
    out.append("\t\tsprite = %s" % q(m["sprites"]["closed"]))
    out.append("\t\toffset = [%d, %d]" % (m["proto_offset"][0], m["proto_offset"][1]))
    out.append("\t\ttop_sprite = %s" % q(glow_sprite(fam)))
    out.append("\t\ttop_sprite_depth_offset = %d" % TOP_SPRITE_DEPTH_OFFSET)
    out.append("")
    out.append("\t[%s.interaction_chest]" % tw)
    out.append("\t\topen_sprite = %s" % q(m["sprites"]["opened"]))
    out.append("\t\topening_sprite = %s" % q(m["sprites"]["opening"]))
    out.append("\t\tbounce_sprite = %s" % q(m["sprites"]["bounce"]))
    out.append("\t\tinventory_size = %d" % m["inventory_size"])
    # bark_offset / open_sfx / close_sfx, as raw TOML value text from _geom, in
    # sorted key order.  A twin that drops them barks in the wrong place or
    # opens with the wrong sound.
    for ck in sorted(m["carry"]):
        out.append("\t\t%s = %s" % (ck, m["carry"][ck]))
    return out


def proto_body(geom):
    """The lines that go BETWEEN the sentinels."""
    out = [
        "#",
        "# 59 chest twins -- one per player-placeable vanilla chest.  GENERATED by",
        "# make_fiddle.py from crates/_geom.py; edit that pipeline, never these lines.",
        "#",
        "# EVERY KEY BELOW IS FROZEN THE MOMENT IT SHIPS, for the reason at the top of",
        "# this file: Grid.gml:1075-1082 drops a saved node whose object_id string no",
        "# longer resolves, WITH ITS WHOLE INVENTORY.  So is every inventory_size --",
        "# Grid.gml:1139-1145 force-resizes a loaded chest to the CURRENT prototype size",
        "# and Inventory.gml:49-52 pops the trailing slots UNDRAINED, so lowering one",
        "# silently deletes the tail of every save that used it.",
        "#",
        "# THE BODY IS THE VANILLA CHEST'S OWN SPRITE, named by string: a mod prototype",
        "# may name a vanilla asset (Furniture.gml:216).  That is why there is no body",
        "# art in this mod for any of the 59, and why each twin inherits vanilla's",
        "# poly_ collision shape, its shadow_manifest entry, its item icon and that",
        "# icon's outlines.json entry for free.  The network identity is entirely the",
        "# per-FAMILY top_sprite glow overlay, which crates/fam_<family>.py draws.",
        "#",
        "# NO collision_grid EXCEPT WHERE THE SOURCE CHEST HAD ONE.  The netstor set's",
        "# squeeze-between margins are deliberately NOT extended here: a twin must",
        "# behave like the chest it replaces, \"0110\" is meaningless on the two 3-wide",
        "# families, and a walkable margin is the only thing that makes the load-order",
        "# near-miss in docs/safety-invariants.md reachable.  The two cottage fridges",
        "# ship collision_grid = \"2\" (whole-footprint, can_jump_over = false,",
        "# GridUtils.gml:535-536 + :580-585) and their twins copy it.",
        "#",
        "# NO destructable, NO child_grid, NO rule_grid, NO placeable_locations: all",
        "# four are inherited from the game's [default] furniture table, which is what",
        "# the source chests do.  A narrower placeable_locations would be a crate the",
        "# player can never pick up (Pick.gml:452); a child_grid would void the",
        "# five-swing removal guard outright (see the header of this file).",
        "#",
    ]
    for fam in ordered_families(geom):
        out.append("")
        out.extend(family_banner(geom, fam))
        for key in sorted(geom.FAMILIES[fam].members):
            out.append("")
            out.extend(proto_block(geom, fam, key))
    return out


def item_block(geom, key):
    m = geom.MEMBERS[key]
    name, bin_value, store_value, _grid = SOURCE_ITEMS[key]
    tw = twin_key(key)
    return [
        "[%s]" % tw,
        "\tdescription = %s" % q(DESCRIPTION),
        "\ticon_sprite = %s" % q(m["icon"]),
        "\tname = %s" % q(NAME_PREFIX + name),
        "\tobject = %s" % q(tw),
        "\tvalue = { bin = %d, store = %d }" % (bin_value, store_value),
        "\ttags = [%s]" % ", ".join(q(t) for t in TAGS),
        "\trecipe_key = %s" % q(RECIPE_KEY),
    ]


def item_file(geom):
    out = [
        "# <---------NETSTOR CRATE TWIN ITEMS------------->",
        "# GENERATED by make_fiddle.py from crates/_geom.py.  Do not hand-edit: these",
        "# are 59 save-serialized content keys and the generator is what keeps them",
        "# from being renamed by accident.  Re-run it; a clean run is byte-identical.",
        "#",
        "# THE KEYS ARE FROZEN.  Item key == object key for all 59, so renaming one",
        "# here breaks the placed unit too (object_prototypes/furniture.toml).",
        "#",
        "# This file may be its own file -- items are auto-discovered anywhere under",
        "# fiddle/items/** -- unlike the prototypes, which must be spliced into",
        "# object_prototypes/furniture.toml because the CATEGORY IS THE FILE NAME",
        "# (GridPrototypes.gml:69).  It MOMI-merges (MergeTomlTables) into the game's",
        "# item tree, so like every other file this mod ships it must contain ONLY our",
        "# keys and never a [default] table.  make_fiddle.py asserts that.",
        "#",
        "# NO RECIPE, ON PURPOSE.  CraftingMenu.gml:1373-1383 admits an item to a",
        "# sub-category only if `recipe != undefined`, so a recipe-less twin never",
        "# appears in the crafting menu at all and 59 twins cannot flood a tab.",
        "# Conversion is the only source.  Consequently: no recipe_is_default, no",
        "# crafting_level_requirement (Items.gml:335-339 defaults it to 1 for anything",
        "# tagged `furniture`), and no entry in boot.gml's ITEM_KEYS, which is the",
        "# recipe-unlock backfill list and a different seam entirely.",
        "#",
        "# `value` IS TWO LITERALS, NEVER A REFERENCE.  Copying the source's",
        "# `bin = \"self.recipe * 1.1\"` hard-asserts on a recipe-less twin",
        "# (Items.gml:461-467), and the cross-item form `bin = \"<source>.bin\"` does",
        "# TOO for 11 of these 59: Items.gml:488-490 re-enters with `ident`, the",
        "# ORIGINAL item, so a source whose own price is still unresolved evaluates its",
        "# `self.recipe` against the TWIN.  Sources sorting after \"netstor\" -- royal,",
        "# stone, void, spring_festival -- resolve after their twins, and eleven of",
        "# them use exactly that expression.  Two literal reals make",
        "# query_item_price return on its first line and the resolver is never entered.",
        "# The numbers are the source's own fully resolved bin/store; regenerate with",
        "# `python make_fiddle.py --check-vanilla` after a game patch.",
        "#",
        "# ONE SHARED recipe_key.  AlmanacMenu.gml:14-20 dedups its lens on recipe_key,",
        "# so 59 twins under one key are ONE almanac row instead of 59.  Every other",
        "# reader of recipe_key is recipe-gated and cannot name a recipe-less item.",
        "#",
        "# ICONS ARE VANILLA'S.  Each twin names its source chest's icon_sprite, and",
        "# vanilla's outlines.json already carries an entry for all 59, so this mod's",
        "# hand-maintained outlines.json is NOT touched by this wave.",
    ]
    for fam in ordered_families(geom):
        out.append("")
        out.extend(family_banner(geom, fam))
        for key in sorted(geom.FAMILIES[fam].members):
            out.append("")
            out.extend(item_block(geom, key))
    out.append("")
    return out


def unit_keys_file(geom):
    """The rows for the UNIT_KEYS seam in yads/gml/network.gml section 1.

    Emitted to its own file at the repo root because this generator does not
    edit yads/gml.  The seam's own comment specifies the shape:

        { key: "netstor_crate_<...>", kind: YADS_KIND_CRATE, slug: "<family>" }

    where `slug` is the ART family and the loop spells
    "spr_furniture_netstor_" + slug + "_offline" -- so the slug is
    "crate_<family>", giving spr_furniture_netstor_crate_<family>_offline,
    exactly the name crates/__init__.offline_sprite() produces.
    """
    out = [
        "// crate_unit_keys.generated.gml -- GENERATED by make_fiddle.py.",
        "//",
        "// PASTE THESE 59 ROWS into yads/gml/network.gml section 1, replacing the",
        "// line",
        "//     // <<< crate twins append here >>>",
        "// inside the `static UNIT_KEYS = [ ... ];` table.  Keep the order: it is",
        "// families sorted by name, members sorted within, which is the same order",
        "// make_fiddle.py writes the prototypes and the items in.",
        "//",
        "// `slug` is the ART FAMILY, not the key.  The loop below the table spells",
        "// \"spr_furniture_netstor_\" + slug + \"_offline\", and one overlay pair is",
        "// shared by every twin of a family, so many rows share a slug -- which the",
        "// seam's own comment says is the expected shape.  Nothing there counts the",
        "// rows or assumes the kinds are distinct.",
        "//",
        "// A key the installed content set does not carry is silently skipped",
        "// (try_string_to_object_id returns an Option), so these rows are safe to",
        "// land before or after the fiddle tables do.",
        "//",
        "// EVERY KEY HERE IS FROZEN THE MOMENT IT SHIPS.",
        "",
    ]
    for fam in ordered_families(geom):
        out.append("        // %s -- %s" % (fam, offline_sprite(fam)))
        for key in sorted(geom.FAMILIES[fam].members):
            out.append('        { key: "%s", kind: YADS_KIND_CRATE, slug: "crate_%s" },'
                       % (twin_key(key), fam))
    out.append("")
    return out


# ---------------------------------------------------------------------------
# The splice, and the byte-identity proof
# ---------------------------------------------------------------------------

def read_text(path):
    with open(path, "r", encoding="utf-8", newline="") as fh:
        text = fh.read()
    if "\r" in text:
        raise FiddleError("%s contains CR -- the repo is LF-only "
                          "(.gitattributes)" % path)
    return text


def write_text(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(text)


def _sentinel_span(lines):
    """(begin index, end index) or None.  Raises on a half-present pair."""
    has_b, has_e = BEGIN in lines, END in lines
    if has_b != has_e:
        raise FiddleError("exactly one of the two sentinels is present -- "
                          "refusing to guess where the block is")
    if not has_b:
        return None
    b, e = lines.index(BEGIN), lines.index(END)
    if e < b:
        raise FiddleError("the END sentinel precedes the BEGIN sentinel")
    return b, e


def strip_block(text):
    """Everything outside the sentinels, with the whole block removed.

    This is the function the byte-identity claim is made in terms of: after a
    splice, strip_block(new) must equal strip_block(old), and on the very first
    run -- when the file has no sentinels yet -- strip_block(old) IS the whole
    original file, so the comparison proves the original survived untouched.

    THE BLANK LINE IMMEDIATELY BEFORE `BEGIN` BELONGS TO THE BLOCK.  The
    splice inserts exactly one, to keep the block from butting against the last
    prototype; counting it as part of the block is what makes the equality
    above exact instead of exact-up-to-one-newline.
    """
    lines = text.split("\n")
    span = _sentinel_span(lines)
    if span is None:
        return text
    b, e = span
    head = lines[:b]
    if head[-1:] == [""]:
        head = head[:-1]
    return "\n".join(head + lines[e + 1:])


def splice(original, body):
    """Return the new file text with `body` between the sentinels.

    First run (no sentinels): append the block, separated from the existing
    content by exactly one blank line.  Later runs: replace only the lines
    between the two sentinels.  Either way the head and the tail are literal
    slices of the original, so the outside cannot change -- and the caller
    proves it anyway with strip_block().
    """
    lines = original.split("\n")
    span = _sentinel_span(lines)
    if span is not None:
        b, e = span
        head, tail = lines[:b], lines[e + 1:]
    else:
        # The file must end with exactly one newline and no trailing blank
        # line.  Anything else and the append would silently renormalise it,
        # which is the one thing this function promises not to do.
        if lines[-1:] != [""] or lines[-2:-1] == [""]:
            raise FiddleError(
                "%s must end with exactly one newline and no trailing blank "
                "line before the first splice" % PROTO_REL[-1])
        head = lines[:-1] + [""]   # content, then the separator blank line
        tail = [""]                # the file's own trailing newline
    return "\n".join(head + [BEGIN] + body + [END] + tail)


# ---------------------------------------------------------------------------
# Output gates -- run on the emitted text, before it is written
# ---------------------------------------------------------------------------

def check_emitted_toml(text, path_label, expected_keys, allow_existing=()):
    """Parse what we are about to write and check the top-level key set.

    `allow_existing` is the set of keys the file legitimately already had --
    for furniture.toml, the three shipped netstor placeables.  Anything else,
    and in particular a [default] table, would MOMI-merge into and corrupt the
    game's own furniture data.
    """
    problems = []
    try:
        parsed = tomllib.loads(text)
    except Exception as exc:                       # noqa: BLE001 - reported
        raise FiddleError("%s does not parse as TOML: %s" % (path_label, exc))

    top = set(parsed)
    want = set(expected_keys) | set(allow_existing)
    if "default" in top:
        problems.append("%s declares a [default] table -- it would merge into "
                        "and corrupt the vanilla table" % path_label)
    unexpected = sorted(top - want)
    if unexpected:
        problems.append("%s has unexpected top-level keys %s"
                        % (path_label, unexpected))
    absent = sorted(want - top)
    if absent:
        problems.append("%s is missing top-level keys %s" % (path_label, absent))
    if problems:
        raise FiddleError("\n  ".join(problems))
    return parsed


def check_prototypes(parsed, geom):
    """Re-read our own output and check it against `crates/_geom.py`.

    Everything below is a fact about a prototype that cannot be fixed after
    release, or a load-time crash.
    """
    problems = []
    for key in sorted(geom.MEMBERS):
        m = geom.MEMBERS[key]
        tw = twin_key(key)
        p = parsed[tw]

        if list(p["size"]) != list(m["footprint"]):
            problems.append("%s: size %s != source footprint %s"
                            % (tw, p["size"], m["footprint"]))

        south = p["south"]
        if south["sprite"] != m["sprites"]["closed"]:
            problems.append("%s: body sprite %r != %r"
                            % (tw, south["sprite"], m["sprites"]["closed"]))
        if list(south["offset"]) != list(m["proto_offset"]):
            problems.append("%s: offset %s != source %s"
                            % (tw, south["offset"], m["proto_offset"]))
        if south["top_sprite"] != glow_sprite(m["family"]):
            problems.append("%s: top_sprite %r != %r"
                            % (tw, south["top_sprite"], glow_sprite(m["family"])))
        for banned in ("winter_top_sprite", "floor_sprite", "on_sprite",
                       "animation", "secondary_sprite", "interact_mask"):
            if banned in south:
                problems.append("%s.south declares %r, which no source chest has"
                                % (tw, banned))

        ic = p["interaction_chest"]
        if ic["inventory_size"] != m["inventory_size"]:
            problems.append("%s: inventory_size %r != source %r -- FROZEN, see "
                            "Grid.gml:1144" % (tw, ic["inventory_size"],
                                               m["inventory_size"]))
        for role, field in (("opened", "open_sprite"),
                            ("opening", "opening_sprite"),
                            ("bounce", "bounce_sprite")):
            if ic[field] != m["sprites"][role]:
                problems.append("%s: %s %r != %r"
                                % (tw, field, ic[field], m["sprites"][role]))

        # The carried optional keys, and nothing beyond them.
        carried = {k: v for k, v in ic.items()
                   if k not in ("open_sprite", "opening_sprite",
                                "bounce_sprite", "inventory_size")}
        if sorted(carried) != sorted(m["carry"]):
            problems.append("%s: carried interaction_chest keys %s != source %s"
                            % (tw, sorted(carried), sorted(m["carry"])))
        for bad in ("shipping_bin", "belongs_to_ari", "allow_soulbound"):
            if bad in carried:
                problems.append("%s: declares %r -- the three chests that "
                                "override those are the three exclusions" % (tw, bad))

        # Prototype-level fields.  destructable and child_grid are the two that
        # are actively dangerous; the rest must simply be inherited.
        for bad in ("destructable", "child_grid", "child_grid_offset",
                    "rule_grid", "placeable_locations", "check_pick",
                    "interaction_turn_on", "bed_kind", "is_journal"):
            if bad in p:
                problems.append("%s: declares %r -- must inherit from the "
                                "game's [default] furniture table" % (tw, bad))
        for card in ("north", "east", "west"):
            if card in p:
                problems.append("%s: declares .%s -- every chest is south-only"
                                % (tw, card))

        # collision_grid: source's value or nothing, never ours, never "-".
        want_grid = SOURCE_ITEMS[key][3]
        got_grid = p.get("collision_grid")
        if got_grid != want_grid:
            problems.append("%s: collision_grid %r != source %r"
                            % (tw, got_grid, want_grid))
        if got_grid is not None:
            rows = [got_grid] if isinstance(got_grid, str) else list(got_grid)
            for row in rows:
                if "-" in row:
                    problems.append("%s: collision_grid contains '-' (=-1), "
                                    "which strips pre-existing room collision "
                                    "(GridUtils.gml:569-579)" % tw)
                if "0" in row:
                    problems.append("%s: collision_grid contains a walkable "
                                    "cell -- twins get no margins, see the "
                                    "load-order near-miss" % tw)

    if problems:
        raise FiddleError("prototype gate failed:\n  " + "\n  ".join(problems))


def check_items(parsed, geom):
    problems = []
    for key in sorted(geom.MEMBERS):
        m = geom.MEMBERS[key]
        tw = twin_key(key)
        it = parsed[tw]

        if it["object"] != tw:
            problems.append("%s: object %r != its own key" % (tw, it["object"]))
        if it["icon_sprite"] != m["icon"]:
            problems.append("%s: icon_sprite %r != source %r"
                            % (tw, it["icon_sprite"], m["icon"]))
        if list(it["tags"]) != list(TAGS):
            problems.append("%s: tags %s != %s" % (tw, it["tags"], list(TAGS)))
        if "netstor_set" in it["tags"]:
            problems.append("%s: tagged netstor_set -- it would advertise the "
                            "Digital Storage tab, which it can never appear in" % tw)
        if it["recipe_key"] != RECIPE_KEY:
            problems.append("%s: recipe_key %r != %r"
                            % (tw, it["recipe_key"], RECIPE_KEY))
        for bad in ("recipe", "recipe_is_default", "restore",
                    "health_modifier", "stamina_modifier",
                    "crafting_level_requirement"):
            if bad in it:
                problems.append("%s: declares %r" % (tw, bad))

        value = it["value"]
        if sorted(value) != ["bin", "store"]:
            problems.append("%s: value keys %s" % (tw, sorted(value)))
        for field in ("bin", "store"):
            v = value.get(field)
            if not isinstance(v, int) or isinstance(v, bool) or v < 0:
                problems.append("%s: value.%s = %r is not a non-negative "
                                "integer literal -- a string here would enter "
                                "query_item_price and can hard-assert "
                                "(Items.gml:488-490)" % (tw, field, v))
        want = SOURCE_ITEMS[key]
        if value.get("bin") != want[1] or value.get("store") != want[2]:
            problems.append("%s: value %s != source (%d, %d)"
                            % (tw, value, want[1], want[2]))
        if it["name"] != NAME_PREFIX + want[0]:
            problems.append("%s: name %r" % (tw, it["name"]))

    if problems:
        raise FiddleError("item gate failed:\n  " + "\n  ".join(problems))


# ---------------------------------------------------------------------------
# The vanilla audit -- optional, and the only thing here that reads the corpus
# ---------------------------------------------------------------------------

def _walk_items(table, out):
    for k, v in table.items():
        if not isinstance(v, dict):
            continue
        if any(f in v for f in ("name", "icon_sprite", "tags", "value", "description")):
            out[k] = v
        else:
            _walk_items(v, out)


def _resolve_prices(items):
    """A faithful port of Items.gml's price resolution over the whole corpus.

    PARSE_ITEM defaults are Items.gml:5-17; the walk is :376-409 (item order,
    bin then store, WRITING BACK); query_item_price is :507-549 and
    query_item_price_expr is :418-505 -- including the `ident` re-entry at :489
    that this whole design exists to avoid relying on.
    """
    val = {}
    for k, fd in items.items():
        v = dict(fd.get("value", {}))
        if v.get("bin") is None:
            v["bin"] = 0 if v.get("store") is None else "self.store * 0.5"
        if v.get("store") is None:
            v["store"] = "self.bin * 2"
        val[k] = v

    stack = []

    def expr(e, ident):
        lhs, rhs = e, "bin"
        if "." in e:
            parts = e.split(".")
            if len(parts) != 2:
                raise FiddleError("unexpected price expression %r" % e)
            lhs, rhs = parts
        lhs = ident if lhs == "self" else lhs
        if lhs in stack:
            raise FiddleError("infinite recursion in prices at %r from %r"
                              % (lhs, ident))
        stack.append(lhs)
        try:
            if rhs == "bin":
                out = val[lhs]["bin"]
            elif rhs == "store":
                out = val[lhs]["store"]
            elif rhs == "recipe":
                rec = items[lhs].get("recipe")
                if rec is None:
                    raise FiddleError("no recipe on %r" % lhs)
                out = 0
                for comp in rec:
                    if "item" not in comp:
                        continue
                    cv = val[comp["item"]]["bin"]
                    if isinstance(cv, str):
                        cv = price(cv, comp["item"])
                    out += cv * comp["count"]
            else:
                out = items[lhs].get(rhs, items[lhs].get("restore"))
            if isinstance(out, str):
                out = price(out, ident)
            return out
        finally:
            stack.remove(lhs)

    def price(inp, item_key):
        if isinstance(inp, (int, float)):
            return inp
        s = inp.replace(" ", "")
        op = "*" if "*" in s else ("+" if "+" in s else None)
        if op is None:
            # No operator -- a bare reference like "self.recipe" or
            # "hard_wood.bin".  Items.gml:520-522 returns
            # query_item_price_expr's result HERE, unquantised: the block
            # below only runs on the op branch (:530-548), never on this one.
            return expr(s, item_key)
        a, b = s.split(op)
        left = expr(a, item_key)
        output = round(left * float(b)) if op == "*" else left + float(b)

        # Items.gml:541-548 -- query_item_price's UNCONDITIONAL quantisation
        # of the op branch's result, ported here in full for the first time.
        # Boundary semantics, read off the engine exactly: both tests are
        # strict `>` (never `>=`), so output == 200 misses the mod-10 branch
        # and falls into mod-5, and output == 25 misses mod-5 and returns
        # unchanged. Quantisation only rounds DOWN (never up), and it is
        # applied per FIELD, not per item: Items.gml:408-409 calls
        # query_item_price once for `bin` and once for `store`, so the two
        # are quantised independently against their own value, never a
        # shared or combined one.
        #
        # THE TAUTOLOGY THIS CLOSES.  Until this fix, this same truncated
        # port (stopped at Items.gml:533, one line short of the block above)
        # was the ONLY price resolver in this file, shared by check_vanilla
        # (which re-derives prices from the corpus to audit SOURCE_ITEMS)
        # and by SOURCE_ITEMS itself (whose checked-in numbers were produced
        # by a prior run of this same incomplete resolver). Auditing one
        # incomplete port against data produced by that identical incomplete
        # port can never fail -- it was comparing the generator to itself,
        # never to the engine. Completing the port here fixes both sides at
        # once: SOURCE_ITEMS below is corrected to match, and --check-vanilla
        # now compares against a resolver that actually matches Items.gml.
        if output > 200:
            return output - (output % 10)
        elif output > 25:
            return output - (output % 5)
        else:
            return output

    for k in sorted(val):
        stack.clear()
        val[k]["bin"] = price(val[k]["bin"], k)
        stack.clear()
        val[k]["store"] = price(val[k]["store"], k)
    return val


def check_vanilla(geom, corpus):
    """Re-derive SOURCE_ITEMS and _geom's prototype facts from the game corpus.

    Mirrors make_art.py's `check_font_against_vanilla`: an AUDIT, not an input.
    Reports SKIPPED and returns when the corpus is not reachable, so a clean
    build never depends on a game being installed.
    """
    if not corpus:
        print("  vanilla audit: SKIPPED (no corpus; set FOM_CORPUS or pass "
              "--check-vanilla <path>)")
        return True
    assets = corpus
    if os.path.isdir(os.path.join(corpus, "gmlsrc", "assets")):
        assets = os.path.join(corpus, "gmlsrc", "assets")
    proto_path = os.path.join(assets, "fiddle", "object_prototypes")
    item_root = os.path.join(assets, "fiddle", "items")
    if not os.path.isdir(proto_path) or not os.path.isdir(item_root):
        print("  vanilla audit: SKIPPED (no fiddle tree under %s)" % assets)
        return True

    problems = []

    protos = {}
    obj_keys = set()
    for name in sorted(os.listdir(proto_path)):
        if not name.endswith(".toml") or name.endswith(".meta.toml"):
            continue
        with open(os.path.join(proto_path, name), "rb") as fh:
            table = tomllib.load(fh)
        obj_keys.update(k for k in table if k != "default")
        if name == "furniture.toml":
            protos = table

    items = {}
    for root, _dirs, files in os.walk(item_root):
        for name in sorted(files):
            if not name.endswith(".toml") or name.endswith(".meta.toml"):
                continue
            with open(os.path.join(root, name), "rb") as fh:
                _walk_items(tomllib.load(fh), items)

    print("  vanilla audit: %d object keys, %d items, %d furniture prototypes"
          % (len(obj_keys), len(items), len(protos)))

    # Disjointness -- the check that cannot be done hermetically.
    twins = {twin_key(k) for k in geom.MEMBERS}
    clash_obj = sorted(twins & obj_keys)
    clash_item = sorted(twins & set(items))
    if clash_obj:
        problems.append("twin object keys collide with vanilla: %s" % clash_obj)
    if clash_item:
        problems.append("twin item keys collide with vanilla: %s" % clash_item)

    # The population: exactly 62 interaction_chest prototypes, 59 twinned.
    chests = {k for k, v in protos.items()
              if isinstance(v, dict) and isinstance(v.get("interaction_chest"), dict)}
    if len(chests) != EXPECTED_MEMBERS + len(EXPECTED_EXCLUSIONS):
        problems.append("corpus has %d interaction_chest prototypes, expected %d"
                        % (len(chests), EXPECTED_MEMBERS + len(EXPECTED_EXCLUSIONS)))
    if chests - set(geom.MEMBERS) != set(EXPECTED_EXCLUSIONS):
        problems.append("untwinned chests are %s, expected %s"
                        % (sorted(chests - set(geom.MEMBERS)),
                           sorted(EXPECTED_EXCLUSIONS)))

    values = _resolve_prices(items)

    for key in sorted(geom.MEMBERS):
        m = geom.MEMBERS[key]
        p = protos.get(key)
        if p is None:
            problems.append("%s: no such vanilla prototype" % key)
            continue
        if list(p["size"]) != list(m["footprint"]):
            problems.append("%s: footprint drift %s vs _geom %s"
                            % (key, p["size"], m["footprint"]))
        if p["south"]["sprite"] != m["sprites"]["closed"]:
            problems.append("%s: body sprite drift" % key)
        if list(p["south"]["offset"]) != list(m["proto_offset"]):
            problems.append("%s: offset drift %s vs _geom %s"
                            % (key, p["south"]["offset"], m["proto_offset"]))
        ic = p["interaction_chest"]
        if ic["inventory_size"] != m["inventory_size"]:
            problems.append("%s: inventory_size drift %s vs _geom %s -- THIS IS "
                            "FROZEN, do not follow the game"
                            % (key, ic["inventory_size"], m["inventory_size"]))
        for role, field in (("opened", "open_sprite"),
                            ("opening", "opening_sprite"),
                            ("bounce", "bounce_sprite")):
            if ic[field] != m["sprites"][role]:
                problems.append("%s: %s drift" % (key, field))
        carried = {k: v for k, v in ic.items()
                   if k not in ("open_sprite", "opening_sprite",
                                "bounce_sprite", "inventory_size")}
        if sorted(carried) != sorted(m["carry"]):
            problems.append("%s: carry drift %s vs _geom %s"
                            % (key, sorted(carried), sorted(m["carry"])))

        want_grid = SOURCE_ITEMS[key][3]
        got_grid = p.get("collision_grid")
        if got_grid != want_grid:
            problems.append("%s: SOURCE_ITEMS collision_grid %r, corpus %r"
                            % (key, want_grid, got_grid))

        fd = items.get(m["item"])
        if fd is None:
            problems.append("%s: no vanilla item %r" % (key, m["item"]))
            continue
        if fd.get("object") != key:
            problems.append("%s: vanilla item %r places %r, not this prototype"
                            % (key, m["item"], fd.get("object")))
        if fd.get("icon_sprite") != m["icon"]:
            problems.append("%s: icon drift %r vs _geom %r"
                            % (key, fd.get("icon_sprite"), m["icon"]))
        name, bin_value, store_value, _g = SOURCE_ITEMS[key]
        if fd.get("name") != name:
            problems.append("%s: SOURCE_ITEMS name %r, corpus %r"
                            % (key, name, fd.get("name")))
        got = values[m["item"]]
        if got["bin"] != bin_value or got["store"] != store_value:
            problems.append("%s: SOURCE_ITEMS price (%d, %d), corpus (%r, %r)"
                            % (key, bin_value, store_value,
                               got["bin"], got["store"]))

    if problems:
        raise FiddleError("vanilla audit failed:\n  " + "\n  ".join(problems))
    print("  vanilla audit: OK -- 59 prototypes, 59 items, %d prices, "
          "0 key collisions" % (2 * len(geom.MEMBERS)))
    return True


# ---------------------------------------------------------------------------
# Reporting
# ---------------------------------------------------------------------------

def report_art_bill(geom, mod_dir):
    """The glow sprites the emitted prototypes NAME, and whether they exist.

    `top_sprite` resolves through the HARD `string_to_asset`
    (Furniture.gml:229-231), so a glow strip that is not installed is not a
    missing overlay -- it is a throw during prototype parse.  The `_offline`
    strips are resolved at run time by network.gml with the SOFT
    try_string_to_asset and degrade gracefully, so they are listed but are not
    boot-critical.
    """
    anim = os.path.join(mod_dir, "animations")
    have = set()
    for root, _dirs, files in os.walk(anim):
        for f in files:
            if f.startswith("spr_") and f.endswith(".png"):
                have.add(f[:-4])
    missing_glow, missing_offline = [], []
    for fam in ordered_families(geom):
        if glow_sprite(fam) not in have:
            missing_glow.append(glow_sprite(fam))
        if offline_sprite(fam) not in have:
            missing_offline.append(offline_sprite(fam))
    print("  art bill: %d families x 2 strips" % len(geom.FAMILIES))
    if missing_glow:
        print("    MISSING and BOOT-CRITICAL (top_sprite -> hard string_to_asset):")
        for s in missing_glow:
            print("      %s" % s)
    else:
        print("    all %d _glow strips present" % len(geom.FAMILIES))
    if missing_offline:
        print("    missing, degrades soft (network.gml try_string_to_asset): %d"
              % len(missing_offline))
    return missing_glow, missing_offline


# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------

def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("mod_dir", nargs="?", default=None,
                    help="the mod tree to write into (default ./yads, or "
                         "$FOM_MOD_DIR)")
    ap.add_argument("--dry-run", action="store_true",
                    help="run every gate and report, but write nothing")
    ap.add_argument("--check-vanilla", nargs="?", const="", default=None,
                    metavar="CORPUS",
                    help="also re-derive SOURCE_ITEMS and the prototype facts "
                         "from the game corpus and fail on drift "
                         "(default $FOM_CORPUS)")
    args = ap.parse_args(argv)

    mod_dir = args.mod_dir or os.environ.get("FOM_MOD_DIR") or os.path.join(HERE, "yads")
    mod_dir = os.path.abspath(mod_dir)
    proto_path = os.path.join(mod_dir, *PROTO_REL)
    item_path = os.path.join(mod_dir, *ITEM_REL)
    keys_path = os.path.join(HERE, KEYS_REL)

    print("make_fiddle.py -> %s" % mod_dir)

    assert_sprite_prefix()
    geom = load_geom()
    check_population(geom)
    check_keys(geom)
    print("  population: %d twins in %d families, %d excluded (%s)"
          % (len(geom.MEMBERS), len(geom.FAMILIES), len(geom.EXCLUDED),
             ", ".join(sorted(geom.EXCLUDED))))

    if args.check_vanilla is not None:
        corpus = args.check_vanilla or os.environ.get("FOM_CORPUS") or ""
        check_vanilla(geom, corpus)

    # ---- prototypes: splice ------------------------------------------------
    if not os.path.exists(proto_path):
        raise FiddleError("%s does not exist -- this generator splices into the "
                          "mod's existing furniture.toml, it does not create it"
                          % proto_path)
    original = read_text(proto_path)
    new_proto = splice(original, proto_body(geom))

    # THE BYTE-IDENTITY PROOF.  Not a claim: the content outside the sentinels
    # is compared before and after, and a difference is fatal.
    if strip_block(new_proto) != strip_block(original):
        raise FiddleError("the splice changed content OUTSIDE the sentinels in "
                          "%s -- refusing to write" % proto_path)

    parsed_proto = check_emitted_toml(
        new_proto, "object_prototypes/furniture.toml",
        [twin_key(k) for k in geom.MEMBERS],
        # The hand-authored units that legitimately live OUTSIDE the sentinel
        # region: the three originals plus the four Beta 1.3 connectors. Any
        # other stray top-level key is still refused.
        allow_existing=("netstor_heart", "netstor_block", "netstor_panel",
                        "netstor_link_carpet", "netstor_link_tile",
                        "netstor_link_cables", "netstor_link_cloud"))
    check_prototypes(parsed_proto, geom)

    # ---- items: whole file -------------------------------------------------
    new_items = "\n".join(item_file(geom))
    parsed_items = check_emitted_toml(
        new_items, "items/furniture/netstor_crates.toml",
        [twin_key(k) for k in geom.MEMBERS])
    check_items(parsed_items, geom)

    # ---- the GML key rows --------------------------------------------------
    new_keys = "\n".join(unit_keys_file(geom))

    outputs = [(proto_path, new_proto), (item_path, new_items),
               (keys_path, new_keys)]

    changed = []
    for path, text in outputs:
        old = read_text(path) if os.path.exists(path) else None
        if old != text:
            changed.append(path)

    if args.dry_run:
        print("  dry run: %d of %d files would change" % (len(changed), len(outputs)))
        for p in changed:
            print("    %s" % os.path.relpath(p, HERE))
    else:
        for path, text in outputs:
            write_text(path, text)
        print("  wrote %d prototypes into %s"
              % (len(geom.MEMBERS), os.path.relpath(proto_path, HERE)))
        print("  wrote %d items into %s"
              % (len(geom.MEMBERS), os.path.relpath(item_path, HERE)))
        print("  wrote %d UNIT_KEYS rows into %s (paste into "
              "yads/gml/network.gml section 1)"
              % (len(geom.MEMBERS), os.path.relpath(keys_path, HERE)))
        if not changed:
            print("  IDEMPOTENT: nothing changed on this run")

    report_art_bill(geom, mod_dir)
    print("  OK")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except FiddleError as exc:
        print("make_fiddle.py: %s" % exc, file=sys.stderr)
        sys.exit(1)
