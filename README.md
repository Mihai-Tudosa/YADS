# YADS - Yet Another Digital Storage Mod

**Back up your saves before installing any mod. It's a beta.**

Network storage for **Fields of Mistria**. One search bar for every chest you own.

**Beta 1.3**, by mykay. Requires the [Mods of Mistria Installer](https://www.nexusmods.com/fieldsofmistria/mods/78) 0.15.1+.

If you've played modded Minecraft or Terraria you already know the idea. This is
my love letter to Applied Energistics 2, Refined Storage and Magic Storage:
link storage units into a network and browse all of it from one terminal.
Search, sort, filter, quick-stack.

## How it works

Build a **Storage Heart**, stand Storage Blocks and converted chests next to
it, and open an **Access Panel** to browse everything they hold in one
searchable view. Units link edge to edge, diagonals don't count, and
connectors carry the link further than touching allows. Networks don't cross
map boundaries: the whole outdoor farm is one area, and the farmhouse, the
cellar and every other interior needs a Heart of its own.

Storage Blocks and crates tint green, yellow or red by how full they are, so
red means nearly full, not broken. Hearts, panels and connectors glow the
set's cyan. A unit that missed the chain shows a sad face instead. Don't
place units on tables, they won't connect there.

Once a network has an Access Panel, its blocks and crates stop opening one by
one, the Panel is the door. A network with no Heart behaves as plain chests,
so your items are never locked away.

## Your first network

1. Craft a Storage Heart and place it.
2. Place a Storage Block so it touches the Heart.
3. Place an Access Panel touching either one.
4. Interact with the Panel, the same button that opens any chest. That's the
   network view.
5. Hold a Network Converter and interact with a placed chest nearby to wire
   it in too.

Interact with the Heart itself any time for a status report on the whole
network.

## Crafting

Everything crafts at the Crafting Station under its own **Digital Storage**
category, from Woodcrafting level 1. The Remote needs level 3. The Heart, the
Block and the Panel also show up under Chests & Storage. The Converter and
the Remote don't: neither is a chest, so neither can be placed.

| Unit | Recipe | Role |
|---|---|---|
| **Storage Heart** | 50 Wood, 5 Copper Ingot, 1 Glass | The brain, one per network |
| **Storage Block** | 30 Wood, 1 Copper Ingot | 30 slots, chain as many as you want |
| **Access Panel** | 1 Copper Ingot, 1 Glass | The door to the network |
| **Network Converter** | 1 Copper Ingot, 1 Glass | One is spent per conversion |
| **Remote Access Panel** | 5 Ruby, 5 Sapphire, 5 Copper Ingot, 5 Iron Ingot, 1 Access Panel | The network in your pocket |

And the four connectors, the floor pieces described below. Four looks, one
job, so pick whichever you like or can afford:

| Connector | Recipe |
|---|---|
| **Magic Carpet** | 3 Fiber |
| **Magic Tile** | 3 Stone |
| **Bundle of Cables** | 2 Wood, 1 Copper Ore |
| **Cloud Connector** | 1 Glass, 2 Fiber |

## Any chest can join

Every convertible vanilla chest, 59 of them (basic wood in all its colors,
deluxe, royal, stone, coral, the Deluxe and Lovely Cottage iceboxes, mist,
void, obsidian, the Mines chest, the dragon chest, the Breath of Spring
chest, even the mimic), can become a network crate: the same look and the
same capacity (30, 42 or 54 slots by tier), wired in. A crate glows and sulks
like a Storage Block. The mist chest floats, so its glow lands on the shadow
beneath it.

The **Network Converter** does the converting. Hold one and interact with a
placed chest and it becomes a crate, contents untouched. Interact with a
crate instead and it turns back into the chest it was, contents intact.
Either direction eats one converter.

**Upgrading is a gesture, not a rebuild.** Hold a bigger chest and interact
with any placed chest or crate: the target becomes the held chest's crate,
everything inside carries over, and the old shell pops back into your
backpack. It costs the chest you're holding plus one converter, and it
refuses with a clear message if the contents wouldn't fit the new size.
Crates have no recipes of their own, converting is the only way to get one.

## Connectors

Four floor pieces carry the network between units that are too far apart to
touch. Lay a path and everything standing on it or right beside it joins the
same network. They chain to each other without limit, so one path can run
clear across the farm. All four are walkable, have no hitbox, and you can
place a chest or a crate right on top of one. They glow cyan once they're
carrying a live network, and they draw as a connected run: a straight run is
one unbroken line, corners bend, junctions branch, and stacked clouds merge
into one bank. A freshly placed piece can take a second to settle into its
shape.

The Cloud Connector floats above the ground and has no line at ground level,
so a run that mixes it with the others shows a gap where it sits. The network
is still whole there, the cloud just runs its own way.

Three small things to know: building over a connector with a blueprint or
farm expansion removes it without dropping the item, so re-route before you
build. A connector fully covered by a chest can't be picked up until the
chest moves. And connectors can't share a cell with a decorative rug, it's
one rug layer per cell.

Nothing glowing? Interact with the Storage Heart for a status report, then
check in order: give it a second, the glow settles a moment after you place
things. Is there a Heart in this room at all? Are the pieces touching edge to
edge, not corner to corner? Is anything sitting on a table?

## Remote access

Craft a **Remote Access Panel**, hold it and interact with a Storage Heart,
and the two are linked. Press **F6** anywhere to browse that network, even
from the bottom of the mines. A tap opens your default network, or your only
one. Holding the key for half a second always opens a list of every network
you've linked, one row each with its room, its blocks and how full it is.
Tick the box on a row to make that network your default.

**Rebind the key in game**: hold your remote key, click Rebind key in the
list's footer, press the one you want. It takes effect instantly, no restart.
It has to be one keyboard key on its own, no Ctrl or Shift combos and no
gamepad buttons, a limit of the installer this mod is built on. Keys the game
already uses are refused with a reason, and letters are warned about, they
also type into the search box. Holding **F6** always opens the list whatever
you rebound to, so a bad key can never lock you out. You can still set
`remote_hotkey` in `%LOCALAPPDATA%\FieldsOfMistria\mod_data\yads\yads.json`
by hand if you prefer; a name typed there is read once when the game starts.

To unlink a remote, open an Access Panel and take it back out of the grid.
You can't take it out through the remote's own view, that cell is visible but
locked there, so a misclick in the mines can't strand you from your storage.
Putting it back in won't re-link it, you hand it to the Heart again.

Controller players: the network view is fully navigable on a pad, and the
Steam Deck opens its keyboard for the search box. The remote key is the one
keyboard-only thing.

## The network view

- The vanilla storage UI over every connected unit at once, 45 cells a page.
  Withdraw and deposit exactly like a chest.
- A real search box with full text editing, an X to clear it, and an
  auto-focus toggle so it's ready the moment the panel opens. Ctrl with the
  arrow keys jumps a whole word at a time, Ctrl+Backspace and Ctrl+Delete eat
  one too.
- 14 category filters that put things where you'd expect, plus a "Museum
  needs" lens for what the museum still wants.
- Five sort modes: Category, Name, Value, Stack value, Count. Your pick is
  remembered.
- Value badges per stack or per item. Big numbers abbreviate, like `12.3k`.
- Quick-stack tops the network up from your backpack with one button: every
  stack of a kind the network already holds. Remotes are the one thing it
  skips.
- Crafting stations pull from your crates automatically. That one is vanilla
  behavior: the units are real chests, so they qualify.

## Good to know

- Your items live in the real chest inventories of the placed units, which
  the game's own save system writes. If the game crashes with the view open,
  nothing is lost.
- A unit that still holds items takes five pickaxe swings to break, with a
  warning on the first. Empty ones break in one. Break a full one anyway and
  the contents drop to the ground, like any chest.
- If a deposit doesn't fully fit, the rest comes straight back with a toast.
  Nothing is silently eaten.
- You can squeeze between crates: solid core, walkable edges, so a wall of
  storage is not a fence.

## Install

1. Extract the zip into the game's install folder under `mods/` (Steam:
   right-click Fields of Mistria, Manage, Browse local files), so that
   `mods/yads/manifest.json` exists. Not the `%LOCALAPPDATA%` folder, that
   one only holds saves and logs.
2. Run the Mods of Mistria Installer, tick **YADS**, hit Install.
3. Play. Recipes unlock automatically, existing saves included.

Built and tested against the August 2026 game patch.

## Before uninstalling

**Empty every unit first.** Uninstalling destroys any items left inside
placed units: the engine discards objects it no longer recognizes and their
inventories go with them, there is no recovery. Move everything to your
backpack or into plain chests before removing the mod. Backpack items are
safe.

## Credits

Applied Energistics 2, Refined Storage and Magic Storage for the genre. Built
with [Mods of Mistria / MMAPI](https://github.com/Garethp/Mods-of-Mistria-Installer),
thanks to Garethp and its maintainers. And thanks to NPC Studio for shipping
source readable enough to mod this deeply.

Found a bug? Report it with your log file
(`%LOCALAPPDATA%\FieldsOfMistria\mod_data\yads\logs\yads.log`).

If YADS saved you an afternoon of chest-diving, you can buy me a coffee:
[paypal.me/tudosamihai](https://paypal.me/tudosamihai). The mod is free and
stays free.
