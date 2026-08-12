# Parked for Beta 1.2 — chest-to-Storage-Block converter

Owner decision (2026-08-11): the "chest + copper ingot" alternative recipe is
OUT of Beta 1.1; the converter idea (option B) is liked and parked for 1.2.
This note carries everything the 1.1 recon and audits proved, so 1.2 starts
warm. Local only (gitignored is fine either way; nothing here quotes engine
source at length).

## Why it cannot be a crafting recipe (proven, do not retry)

- One item = one recipe: `recipe` is a scalar field on the item prototype
  (`Items.gml:36`, `:139-185`). No recipe arrays exist in vanilla data.
- `tag =` ingredient components parse but HARD-CRASH the crafting menu
  (`CraftingMenu.gml:593` → `impossible(...)`) and never see chest storage.
- "Basic Wood Chest" is 15 distinct items sharing one display name (the color
  variants, `basic_chest_set.toml`); a recipe names exactly one item id, so any
  recipe-shaped version either floods the menu with same-name rows or rejects
  chests the player literally cannot distinguish by name.
- Items must NEVER share an `object`: zero of 2665 vanilla items do; sharing
  fragments stacks (`LiveItem.partial_eq` gates on `item_id`) and makes
  pick-up identity depend on engine ItemId minting order, which is unresolved
  and possibly per-launch (`Pick.gml:597-605` takes the first match).

## The converter design (option B, owner-approved direction)

Interact with a placed, EMPTY vanilla chest that TOUCHES the network (footprint
adjacency, same rule as the BFS) while carrying ≥1 copper ingot → confirm →
consume the ingot, erase the chest node, write a `netstor_block` node on the
same footprint (both are size [4,2]).

Custody rules (nuclear): only EMPTY chests qualify (contents never touched);
validate everything BEFORE erasing; if the block write fails, re-write the
chest (same footprint just vacated — cannot fail); the erase of an empty chest
spills nothing (`GridUtils.gml:287-323` drains, but it is empty by precondition).
Exclusions: `belongs_to_ari = false` fixtures (`turn_in_box`, stable chest) and
`starter_shipping_box` (`shipping_bin = true`).

Precedent for programmatic node writes: `Patches.gml` water_blocker entries;
our own `furniture.place_guard` knowledge. Erase API: `erase_object_node_by_parent`
(`GridUtils.gml:162`).

Open design points for 1.2:
- Confirm popup vs immediate-with-toast (conversion is NOT reversible — picking
  the block later yields a `netstor_block` item, not the chest). Check whether
  popup_creator supports choice buttons; if not, design the arming gesture.
- The adjacency requirement doubles as the intent discriminator (a plain empty
  chest elsewhere opens normally, no popup spam).
- Interact ladder: extend `yads_object_interact` (`boot.gml`), return undefined
  to defer to vanilla everywhere else.
- Coverage: ALL chest variants qualify by construction (interact is object-id
  based, enumerate the `interaction_chest` prototypes minus exclusions).

Audit reports with the full evidence (session-local, may be gone by 1.2):
B11w1_recipes.md / B11w1_ui.md in the 2026-08-11 session task dir.
