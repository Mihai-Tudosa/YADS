# YADS - Yet Another Digital Storage Mod

**Back up your saves before installing any mod. It's a beta.**

Network storage for **Fields of Mistria**. One search bar for every crate you own.

**Beta 1.0**, by mykay. Requires the [Mods of Mistria Installer](https://www.nexusmods.com/fieldsofmistria/mods/78) 0.15.1+.

If you've played modded Minecraft or Terraria you already know the idea. This is
my love letter to Applied Energistics 2, Refined Storage and Magic Storage:
link storage units into a network and browse all of it from one terminal.
Search, sort, filter, quick-stack.

## The units

| Unit | Recipe | Role |
|---|---|---|
| **Storage Heart** | 50 Wood, 5 Copper Ingot, 1 Glass | The brain. One per network. Interact for a status report. |
| **Storage Block** | 30 Wood, 1 Copper Ingot | 30 slots each. Chain as many as you want. |
| **Access Panel** | 1 Copper Ingot, 1 Glass | The terminal. Open it to browse the network. |

All three are crafted at the Woodcrafting Station from crafting level 1. You
will find them under "Chests & Storage" and under their own "Digital Storage"
category.

Place units so they touch and they link up. Connected units glow (blocks tint
green, yellow or red by how full they are), a unit that missed the chain shows
a sad face. Each room is its own separate network, so the farm and the
farmhouse each need their own Heart. Don't place units on top of tables, they
won't connect to anything there.

## Features

- The vanilla storage UI over every connected unit at once, 45 cells a page.
  Withdraw and deposit exactly like a chest.
- A real search box with full text editing, and an auto-focus toggle so it's
  ready the moment the panel opens.
- 16 category filters, including "Museum needs" for what the museum still wants.
- Value badges on every stack (off, per stack, or per item). Big numbers
  abbreviate to things like `12.3k`.
- Five sort modes: Category, Name, Value, Stack value, Count.
- Quick-stack your backpack into the network with one button.
- Crafting stations pull from the network automatically. That one is vanilla
  behavior: the units are real chests, so they just qualify.
- You can squeeze between crates. Collision is a solid core with walkable
  edges, so a wall of storage is not a fence.
- A unit that still holds items takes five pickaxe swings to break, with a
  warning on the first. Empty ones break in one, like any chest.
- Blocks with no heart behave as plain chests, so your items are never locked
  behind a missing crafting recipe.
- If a deposit doesn't fully fit, the rest comes straight back to you with a
  toast. Nothing is silently eaten.

## Install

1. Extract the zip into `Fields of Mistria/mods/` so the file
   `mods/yads/manifest.json` exists.
2. Run the Mods of Mistria Installer, tick **YADS**, hit Install.
3. Play. Recipes unlock automatically, existing saves included.

## Before uninstalling

**Empty your units first.** The engine drops placed objects it no longer
recognizes, together with everything inside them. Backpack items are safe.
That's how the game treats any removed content mod, but it's worth saying
twice for a storage mod.

## Build from source

The mod folder ships as-is, nothing is generated at install time. The tooling
is here so you can rebuild the art or re-run the checks.

```sh
# Regenerate all sprites and their metadata. Deterministic, needs Pillow.
python make_art.py yads

# Every symbol the GML calls must exist in the game's own code.
# Point it at a folder holding an extraction of the game's assets/gml.
python check_symbols.py yads/gml /path/to/corpus

# The ship gate. Exit 0 means the installer would accept the mod.
# The mod path must be absolute.
ModsOfMistriaInstaller-cli.exe --lint "<abs path>/yads" \
    "<game>/assets.bak.zip" --strict-lints --compile-check require
```

Keep the mod folder named `yads`. The installer derives the legal GML function
prefix from the folder name, and every function here is `yads_*`.

The engine research notes this mod was built from are not in the repo. They
quote the game's source, which isn't mine to republish.

## Credits

Applied Energistics 2, Refined Storage and Magic Storage for the genre. Built
with [Mods of Mistria / MMAPI](https://github.com/Garethp/Mods-of-Mistria-Installer),
thanks to Garethp and its maintainers. And thanks to NPC Studio for shipping
source readable enough to mod this deeply.

If YADS saved you an afternoon of chest-diving, you can buy me a coffee:
[paypal.me/tudosamihai](https://paypal.me/tudosamihai). The mod is free and
stays free.
