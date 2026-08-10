# YADS — Yet Another Digital Storage Mod

Network storage for **Fields of Mistria**. One search bar for every crate you own.

**Beta 1.0** · by mykay · requires [Mods of Mistria Installer](https://www.nexusmods.com/fieldsofmistria/mods/78) 0.15.1+

If you have played modded Minecraft or Terraria you already know this mod. YADS
is a homage to **Applied Energistics 2**, **Refined Storage** and **Magic
Storage** — the "stop opening forty chests" genre — rebuilt for Mistria's pace.
Link storage units into a network, walk up to one terminal, and see everything
at once: searchable, sortable, filterable, paged, with quick-stack.

---

## The three units

| Unit | Recipe | Role |
|---|---|---|
| **Storage Heart** | 50 Wood · 5 Copper Ingot · 1 Glass | The brain. One per network. Interact for a status report: blocks connected, how full each is, how full the network is. It does not store your things — it knows where they are. |
| **Storage Block** | 30 Wood · 1 Copper Ingot | 30 slots of network capacity each. Chain as many as you like. Sealed while connected; a block with no heart behaves as a plain chest, so items are never trapped. |
| **Access Panel** | 1 Copper Ingot · 1 Glass | The terminal. Interact to browse the whole network. |

All three are crafted at the **Woodcrafting Station** from crafting level 1 — a
brand-new save qualifies, and the station is pre-placed on every farm. They list
in two places: vanilla's own "Chests & Storage", and a dedicated **"Digital
Storage"** sub-category (Functional tab, last in the list). 日本語 players get a
translated header for it.

**Copper *Ingot*, not Copper Ore.** Ingots are refined at a **Forge** — a
Blacksmithing placeable sold by the Carpenter for 2,000g, not pre-placed on a new
farm. Balor's Wagon rotates Copper Ingot into stock sometimes.

## Features

- **Aggregated network view.** Vanilla storage UI, 45 item cells a page, over
  every connected unit at once. Withdraw and deposit exactly like a chest.
- **A real search box.** Click to place the cursor, then type — arrows, Home/End,
  Backspace/Delete, Shift+select, Ctrl+A, Ctrl+C/X/V. With auto-search on (a
  toggle, and it persists) the box is focused the moment the panel opens.
- **16 category filters** on a paged bottom row — All, the 14 item categories,
  and "Museum needs", which shows only what the museum is still missing. One at a
  time, ANDed with the search box.
- **Value badges** in the corner of every occupied cell, cycling
  off → per stack → per item. It is what selling would actually pay right now
  (quality, infusions and perks included); big totals abbreviate to `12.3k`.
- **Five sort modes** from one button: Category → Name → Value → Stack val →
  Count.
- **Quick-stack to network** from the banner button, from any page.
- **Pages** via the bottom-bar arrows, the mouse wheel over the grid, or
  PAGE_UP / PAGE_DOWN.
- **Craft from the network for free.** Mistria's crafting stations already pull
  materials from chests; the units *are* chests, so they join automatically.
- **Squeeze between crates (Beta 1.0).** Each unit's collision is a solid core
  with walkable margins, so a wall of them is a wall you can still walk along
  rather than a fence.
- **Removal protection.** A unit that still holds items takes five pickaxe swings
  to break, with a toast on the first. A wide charged swing counts as one, not
  one per tile; so does a bomb blast. The count resets after ten seconds, on
  reload, or on leaving the room. This is a guard against the *accident*, not
  data-loss prevention — vanilla already drops a broken unit's whole inventory on
  the ground.
- **Connection at a glance.** Connected units glow; a unit that missed the chain
  wears a sad face. Blocks tint by fill: green empty, yellow in use, red full.
  Beta 1.0 softens all three to pastel so they sit in Mistria's palette.
- If a deposit cannot fully fit, the remainder comes straight back to you with a
  "Network storage is full." toast. Nothing is ever silently eaten.

**Building a network:** place units so their footprints touch on an edge, in any
arrangement. One heart per chain is required (more is fine). Networks are
per-room — the engine's grids are per-location, so the farm and each farmhouse
room are separate networks. Do not place units on tables: table surfaces are
separate sub-grids, so they will not link.

## Install

1. Download the zip and extract it into `Fields of Mistria/mods/` so that it
   reads `mods/yads/manifest.json` — no double-nesting.
2. Run the Mods of Mistria Installer, tick **YADS**, and Install.
3. Play. Recipes unlock automatically on existing saves, no popup.

### Updating from an Alpha build

**The mod id changed in Beta 1.0.** MOMI sees this as a different mod, so:

1. Delete the old `mods/Digital Storage/` folder.
2. Extract the new `mods/yads/`.
3. In the MOMI list, **tick YADS once** — the old entry's tick does not carry
   over. Then Install.

Your saves and everything stored in placed units are unaffected: the content keys
(`netstor_heart`, `netstor_block`, `netstor_panel` and their sprites) deliberately
did not change, because the engine serializes placed objects by name.

Two settings reset to their defaults, once: auto-search (back to on) and the value
badge mode (back to off). They live in the mod's config file, which moved with the
mod id.

## First-launch checklist

1. **The game boots to the title screen.** If it does not: MOMI → Uninstall all,
   confirm it boots again, and report it. The value badges need their own sprite
   font merged into the game's font table, and the engine resolves every entry in
   that table with a hard asset lookup at boot — the one merge in this mod that
   cannot fail soft. Once in-game, glance at the gold/essence numbers on the HUD;
   they use vanilla fonts from the same merged table, so if they render the merge
   kept every vanilla entry intact.
2. Woodcrafting Station → **Chests & Storage** → three items with icons and the
   right recipes (Copper **Ingot**).
3. Craft one of each. Place a Heart, a Block touching it, a Panel touching either.
   All three should glow.
4. **Open the Heart with no Panel placed** → a single toast, nothing else. Place a
   Panel and open the Heart again → the full status popup.
5. **Open the Panel.** Deposit a stack, close, open the Block directly — the stack
   is physically in a unit. Withdraw it back. Sleep to save, reload, still
   correct. *This is the custody test.*
6. Watch a Block's glow while depositing: green → yellow → red. Move a unit out of
   the chain: sad face.
7. Walk between two adjacent units — you should fit through the gap.
8. Swing a pickaxe at a non-empty unit: toast, then five swings to break. It
   behaves the same from any side, including while standing on the unit itself.
9. Search (typing, arrows, Ctrl+A/C/V), sort-cycle, page-flip all three ways,
   quick-stack, the "Museum needs" filter, and the value badge cycle. Confirm the
   value setting survives closing and reopening the panel.
10. Put materials only in the network → the Woodcrafting Station shows recipes as
    craftable and consumes from the units.

## Known quirks

- **You can wall yourself in, and you can always get out.** Because each unit is
  now walkable at its outer columns, the 16px gap between two flush units is
  ground you can stand on — and if you then place units north and south with
  their solid cores over that gap, you are standing in a sealed 16px pocket.
  Nothing in the game's placement check tests for "does this enclose someone",
  in vanilla either. The way out: swing your pickaxe at any adjacent unit — an
  empty one comes apart in one swing, one that holds items takes five. Sleeping
  or leaving the room also resolves it.
- **Networks are per-room and do not span tables.** The engine's grids are
  per-location and a table surface is its own sub-grid; a unit on a table joins
  nothing and gets no swing protection.
- **The vanilla Throw key** can still push an item straight into one specific
  unit, bypassing the network view. Engine behaviour, no mod hook reaches it.
  Harmless — the item shows up in the view wherever it lands.

## ⚠ Before uninstalling

**Empty every YADS unit first.** On load the engine drops placed objects whose
name it no longer recognises, and their inventories are never re-attached —
anything still inside is permanently gone. Items in your backpack are fine. This
is engine behaviour for any content mod, not something YADS can guard against
from the outside.

## Troubleshooting

- Logs: `%LOCALAPPDATA%\FieldsOfMistria\mod_data\yads\logs\`
- Settings: the config file in the same `mod_data\yads\` folder.
- Uninstall: MOMI → Uninstall all. It rebuilds `assets.zip` from the pristine
  backup and leaves saves untouched — but read the warning above first.

## Build from source

Nothing in the repository is generated at install time; the mod folder is what
ships. The tooling is there so you can change the art or re-run the gates.

```sh
# Regenerate every sprite, every .meta.toml sidecar and the sprite-font table.
# Deterministic: a clean run over an unmodified checkout produces byte-identical
# files. Needs Pillow.
python make_art.py yads

# Static symbol check: every symbol the mod's GML calls must exist in the game's
# own GML or in the MMAPI payload. Point it at a directory holding an extraction
# of the game's assets/gml (as gmlsrc/) and, optionally, a MOMI checkout (momi/).
python check_symbols.py yads/gml /path/to/corpus
# ...or set FOM_CORPUS instead of passing the path.

# THE SHIP GATE. Exit 0 means the installer would install this mod.
# The mod path MUST be absolute — a relative path silently skips the GML tree.
# Never call momi-cli with any other flag form: unknown flags fall through to a
# live install.
ModsOfMistriaInstaller-cli.exe --lint "<abs path>/yads" \
    "<game>/assets.bak.zip" --strict-lints --compile-check require
```

The mod folder **must** stay named `yads`. MOMI derives the legal GML function
prefixes from the folder name and the manifest symbol, and every function in this
mod is `yads_*`; rename the folder and `--strict-lints` excludes the whole mod,
content included.

The engine research notes this mod was built from are deliberately **not** in this
repository. They quote the game's shipped GML source verbatim, which is not mine
to republish.

## Credits

Standing on the shoulders of the storage giants: **Applied Energistics 2**,
**Refined Storage** and **Magic Storage** (Terraria), and every other mod that
taught us a chest wall is a UI problem.

Built with [Mods of Mistria / MMAPI](https://github.com/Garethp/Mods-of-Mistria-Installer)
— enormous thanks to Garethp and its maintainers for the modding layer that makes
this possible. And to NPC Studio, whose engine ships source readable enough to mod
this deeply.

By **mykay**.

## Support

If YADS saved you an afternoon of chest-diving and you feel like buying me a
coffee: [paypal.me/tudosamihai](https://paypal.me/tudosamihai). No obligation —
the mod is and stays free.
