# YADS - Yet Another Digital Storage Mod

**Back up your saves before installing any mod. It's a beta.**

Network storage for **Fields of Mistria**. One search bar for every crate you own.

**Beta 1.2**, by mykay. Requires the [Mods of Mistria Installer](https://www.nexusmods.com/fieldsofmistria/mods/78) 0.15.1+.

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
- A **Remote Access Panel** you carry in your pocket: 5 Ruby, 5 Sapphire,
  5 Copper Ingot, 5 Iron Ingot and one Access Panel, at Woodcrafting level 3.
  It is crafted under "Digital Storage" only, not under "Chests & Storage",
  because it isn't a chest and can't be placed. Hold it and interact with a
  Storage Heart to link the two, then press **F6** anywhere to browse that
  network, from the bottom of the mines if you like. Take it back out of the
  view to unlink; putting it back in won't re-link it, you have to hand it to
  the Heart again. Unlinking only works at an Access Panel: in the remote's own
  view that one cell is visible but locked, so a misclick in the mines can't cut
  you off from your own storage.
- **Change the key in game, no restart.** Holding your remote key for half a
  second always opens the network picker, whatever you have bound it to and
  however many networks you own. Click **Rebind key** in its footer, then press
  the key you want. It takes effect immediately and is remembered. Keys the
  game already uses are refused with a reason on the hint line, and it follows
  your own control rebinds rather than the defaults. Letters are allowed but
  warned about, because they will also type into the search box while a network
  view is open. It has to be one keyboard key on its own: no Ctrl or Shift
  combinations and no gamepad buttons. That is a limit of the installer this
  mod is built on, not a choice, and it may lift when MOMI updates. You can
  still set `remote_hotkey` in
  `%LOCALAPPDATA%\FieldsOfMistria\mod_data\yads\yads.json` by hand if you
  prefer; a name typed there is read once when the game starts.
- **Holding F6 always gets you back.** Whatever you rebind to, holding **F6**
  for half a second opens the picker, so a key you can't press any more is
  never a dead end. A tap of F6 does nothing once you've rebound: it's a
  rescue, not a second shortcut.
- **Several networks on one key.** Link a remote to as many Storage Hearts as
  you like. *Holding* your remote key always brings up the picker: one row per
  network, with the room it's in, how many Storage Blocks it has and how full
  it is. Click a row to open it. Tick the box on the right to make that network
  your default, and from then on a tap goes straight there; tick the same box
  again to clear it. With no default set, a tap opens your only network, or the
  picker if you have several. Because a hold has to be able to mean something
  else, a tap is read when you let the key go rather than the moment you press
  it, which is not something you will feel. The one case where the key fires on
  the press itself is several networks and no default, where a tap and a hold
  both mean "show me the list" anyway. Your default is remembered per install
  rather than per save, so a heart that doesn't exist in the save you loaded is
  simply ignored, and the key behaves as if you had never set one. The list
  shows up to eight networks, the ones in the room you're standing in first.
- A real search box with full text editing, and an auto-focus toggle so it's
  ready the moment the panel opens.
- One tap on the X empties the search box, and Ctrl with the arrow keys jumps a
  whole word at a time. Ctrl+Backspace and Ctrl+Delete eat one too.
- 14 category filters, plus All and a "Museum needs" lens for what the museum
  still wants.
- Value badges on every stack (off, per stack, or per item). Big numbers
  abbreviate to things like `12.3k`.
- Five sort modes: Category, Name, Value, Stack value, Count. Your pick sticks,
  so every panel opens the way you left it.
- Quick-stack your backpack into the network with one button. Remotes are the
  one thing it skips, so it can never file your remote away in a crate.
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

## Credits

Applied Energistics 2, Refined Storage and Magic Storage for the genre. Built
with [Mods of Mistria / MMAPI](https://github.com/Garethp/Mods-of-Mistria-Installer),
thanks to Garethp and its maintainers. And thanks to NPC Studio for shipping
source readable enough to mod this deeply.

If YADS saved you an afternoon of chest-diving, you can buy me a coffee:
[paypal.me/tudosamihai](https://paypal.me/tudosamihai). The mod is free and
stays free.
