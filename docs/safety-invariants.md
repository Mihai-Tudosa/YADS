# Safety invariants — the facts §10, the badges and the collision grid are shaped by

Split from `CLAUDE.md` (size rule). These are current, load-bearing engineering
facts — not history. Read before touching pick protection, the sprite font or
the units' `collision_grid`.

## THE `destructable` CONTRACT

`node.destructable` must never be derived on a timer and must never rest at
`false`. The shape:

- **The flag never rests at false.** It is written inside one `pick_node` call
  and restored at the head of the next tick (`pick_poll`, which is the FIRST
  statement in `yads_tick` so that nothing which can throw
  runs ahead of the restore). `save.game_saving` flushes every suppression again,
  step 0, before the grids serialize. `save.game_loaded` restores then drops.
- **The BASE RULE.** The first time we touch a node we record the value we found;
  we write only `base && <our intent>`; every restore writes `base`. The engine
  forces `destructable = false` for furniture on a `TileFlag.Unbreakable` cell
  (Furniture.gml:685-687) and that force must survive us. We may take a
  permission away for a moment; we may never grant one. A unit whose `base` is
  already `false` returns from the filter immediately — no entry refresh, no
  count, no toast promising a removal that cannot happen (`hound_help.toml` ships
  a tile rule that is `unbreakable` AND `placeable`, so this is reachable).
- **A one-time save repair**, armed in `game_loaded` and performed from the tick
  once the world is up, undoes a resting `false` that the pre-fix build may
  already have written into a save — gated on `prototype.destructable &&
  !has_flag(grid.node_flags[ni], TileFlag.Unbreakable)`, which is the engine's own
  discriminator between "we damaged this" and "the engine meant it".
- **The invariant the whole feature rests on**: a blocked swing still REACHES
  `pick_node`. `AriFsm.gml:3296` computes `can_pick_node` into `valid_target` and
  then calls the callback at `:3329` **unconditionally**.

## THE SERIALIZATION TRUTH

`node.destructable` **IS** serialized, and no grep of `scripts/Serialization/`
will show you that — the grid serializer and deserializer are **generic struct
walkers that never name a field**:

- OUT — `Grid.gml:1367` walks `struct_get_names(parent)` and skips exactly eight
  names (`:1419-1428`); `destructable` is not among them, so it falls to the
  default arm at `:1445`.
- BACK IN — `load_objects` re-derives from the prototype first (`Furniture.gml:649`)
  and *then* walks the SAVED struct, whose skip list also omits `destructable`,
  ending at `Grid.gml:1255`. **The saved value wins, 150 lines after the
  re-derive.**
- PROOF THE ENGINE RELIES ON IT — `Patches.gml:426-452` writes literal
  `{ object_id: "water_blocker", destructable: false }` entries into
  `farm_objects.object_list`. Those nodes are permanent *by save data*.

So a `false` left behind is a crate welded shut in the player's save, surviving
uninstallation of the mod. That single fact is why §10 is shaped the way it is.

## SPRITE-FONT BOOT COUPLING — the one merge that does not fail soft

The value badges need `netstor_count`, merged into the game's own
`fiddle/fonts/sprite_fonts.toml`. `load_sprite_fonts()` (Fonts.gml:4-31, called
from Setup.gml:125) walks EVERY top-level key of that table and resolves each
sprite with the **hard** `string_to_asset`, no try/catch. Every other thing this
mod merges degrades gracefully — a missing sprite becomes a placeholder, a
missing item id is skipped — but a font-table entry whose sprite did not install
takes the game down **before the title screen, for every save, whether or not the
mod folder is still on disk**. No realistic MOMI path produces that state (a lint
failure excludes the mod wholesale, the TOML installers run in one pass, Uninstall
restores the pristine zip), but it is the reason the first-launch checklist opens
with "does the game still boot". On the GML side both `set_sprite_font` and
`sprite_font_width` sites are gated on the font actually being in
`global.sprite_fonts`, because both end in an `assert_neq` and a throw inside
`build_badges` would strand a live, item-accepting Storage menu with no
reconciler behind it.

## THE LOAD-ORDER NEAR-MISS — the walkable margins' one load-bearing dependency

Recorded because it is closed by an ordering coincidence in the engine, not by
anything this mod does, and because Beta 1.0's `collision_grid` is what put us
within reach of it. Found by the Beta 1.0 collision audit (MINOR 9).

**The path that would lose items.** `load_objects` re-creates every furniture
node through `self.write_node` → `write_furniture_to_location`
(`Grid.gml:1105`), which calls `furniture_test_flag_mask`
(`Furniture.gml:634-645`). That function aborts on

```
collision_rectangle(xx*8, yy*8, (xx+size.x)*8, (yy+size.y)*8,
                    [obj_ari, obj_player_animal, obj_pet])   // Furniture.gml:1973-1981
```

returning `false` → `write_furniture_to_location` returns `undefined` →
`load_objects` logs `error("failed to make …")` and **`continue`s**
(`Grid.gml:1118-1125`). The `node.inventory = inventories[obj.inventory]`
assignment for a chest is at `Grid.gml:1139`, fifteen lines *after* that
`continue`. So the unit and **its entire inventory** would be absent from the
world on load — no drop, no `lost_items`, no error the player can act on.

**Why it is unreachable today.** `write_furniture_to_location` passes
`ignore_ari = grid != GRID` as the eighth argument (`Furniture.gml:642`;
signature at `:1958`), and the Ari rectangle is skipped entirely when
`ignore_ari` is true (`:1966`). `LoadGame.gml` runs every `grid.load(...)` in
its two loops (`:258` dynamic grids, `:291` locations) and only **then** assigns
`GRID = GRIDS[gm_room_to_location_id(room())]` at **`:302`**. Every grid in those
loops is freshly minted by `initialize_grid` (`:270`) and structs compare by
reference on this runtime, so `grid != GRID` is **unconditionally true for the
whole load** — the Ari test is skipped in exactly the place where it would have
deleted a chest. Room re-entry never re-loads a grid; `Game.gml:647`/`:653` only
re-point `GRID`.

**Why this is now worth writing down.** Before Beta 1.0 the scenario was
structurally unreachable: all 4x2 cells were solid, so the player could not be
inside a unit's footprint when the game saved. `collision_grid = ["0110","0110"]`
makes the two outer columns walkable, so "I saved while standing on my crate" is
now an ordinary Tuesday. The only thing between that and total inventory loss is
the order of two statements in `LoadGame.gml`.

**The invariant, stated as a check.** *Any engine update that moves `GRID =`
above the `grid.load()` loops — or that makes `initialize_grid` hand back a grid
that compares equal to `GRID`, or that changes the `ignore_ari` default at
`Furniture.gml:1958` — converts the walkable margins into an item-loss path.*
Re-verify those four lines (`LoadGame.gml:258/291/302`, `Furniture.gml:642`)
after every game patch, before shipping a build against it. There is no hook
that can defend this from the mod side: the abort happens inside the engine's own
load walker, before any seam this mod owns.
