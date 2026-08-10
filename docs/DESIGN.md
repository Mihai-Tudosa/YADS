# YADS for Fields of Mistria — implementation design

Original build-night design, 2026-08-07. Research lives in `research/R1..R8.md`,
which is kept out of the published repository (it quotes engine source verbatim).

> **This is the original build-night design.** The architecture — custody rule,
> write-through projection, reconciler — still holds, and this file stays the
> contract for it. Identity facts below are current as of Beta 1.0; for current
> features, hooks and status see `CLAUDE.md`.

User spec: Storage Heart (50 wood, 5 copper, 1 glass) · Storage Block (30 wood,
1 copper) · Access Panel (1 copper, 1 glass). Panel/heart opens ONE aggregated,
paged, searchable, sortable view of every connected storage unit. Withdraw,
deposit, search/sort. Craft-from-network: **confirmed already-vanilla** (R5) —
chests feed all CraftingMenu stations globally; our units join automatically.

## Identity

- Mod folder: `yads/` · manifest.json: name "YADS - Yet Another Digital Storage
  Mod", author "mykay", version "Beta 1.0", minInstallerVersion **"0.15.1"**,
  manifestVersion 1, requires_hooks — 8: the original four
  ("object.interact","ui.menu_closed","save.game_saving","save.game_loaded")
  plus "furniture.place_guard","camera.culls_processed","game.room_changed",
  "resource.node_modifier" (see CLAUDE.md for what each carries).
- The FOLDER NAME is the GML namespace. MOMI accepts `<ns>_` / `__<ns>_` for
  ns in {folder name, manifest symbol} (GmlModLint.cs:78-83), so the folder must
  stay `yads` for `yads_*` to lint.
- ALL top-level GML functions + constructors prefixed `yads_`
  (the DirName∪Symbol rule under --strict-lints; a bare `netstor_`
  prefix fails that lint for functions). Single state struct `global.__yads`
  (house pattern, R6 Q1 — globals are not under the prefix lint), accessed via
  local `_rt`. Never define any name that
  exists in the engine corpus (export collision skips the WHOLE mod, R6 warn 3;
  engine-builtin shadowing bricks boot and no tool catches it, R1 warn 2).
- Content keys (bare, collision-avoiding, R1 Q3): `netstor_heart`,
  `netstor_block`, `netstor_panel`.

## Architecture (final, supersedes the skeleton's open decisions)

**D1/D2/D3 RESOLVED — write-through paged projection over vanilla StorageMenu:**

- Real items live ONLY in real chest `node.inventory`s at all times. Saves walk
  node inventories (R5 warn 1); a synthetic inventory is never custodian.
- View = `Inventory(54)` synthetic left inventory in a vanilla StorageMenu
  (`ANCHOR.spawn_menu(Menu.Storage).set_inventories(view, ARI.inventory)
  .with_pull_button(false).with_left_banner().with_right_banner().build()` —
  byte-for-byte the lost-and-found shape, R2 Q3). node stays undefined;
  `on_close` overridden Factories-style (R2 Q2 end).
- The view shows one PAGE (≤54 stacks) of the aggregated index. Page slots are
  written directly (slot.item / slot.count + updates bump — the vanilla sort
  pattern, R2 Q9). Trailing EMPTY view slots are exposed only while the network
  has receiving capacity (deposit affordance; prevents the transfer_only_flag
  soft-lock from lying, R2 warn 3).
- **Reconciler**: every frame while a view is open (latched `mmapi_register`
  tick), diff view slots against a shadow snapshot; net deltas per item-key are
  applied to member chests (withdraw → decrement matching member slots;
  deposit → merge/place into members). Key = LiveItem identity via
  `partial_eq` template refs (R3 Q1/Q2). One player action per frame + tick
  ordering (mmapi drain runs before ANCHOR think, R2 Q8/R6 Q1) keeps the
  pending window to a single action, and a mid-save is harmless: members are
  authoritative, an unreconciled pickup simply un-happens on load. On
  `save.game_saving`: run one immediate reconcile + flush the menu hand via
  the vanilla give-item path if a view is open.
- Aggregation index rebuilt on open, page flip, search change, sort change,
  and after every reconcile that changed members.

**Network model:** BFS flood-fill (R7 recipe §Q6) from the interacted node over
nodes whose object_id ∈ {heart, block, panel} (ids resolved at runtime via
`try_string_to_object_id`, memoized per session — enum is fiddle-minted and
renumbers, R4 Q6). Adjacency = footprints (write_size_x/y, R7 warn) sharing an
orthogonal edge on the SAME parent_grid (never bridge grids, R7 warn 2).
Valid network ⇔ contains ≥1 heart. Members' inventories (heart 54 + blocks 30
+ panels 4 each) form the pool. Nothing persisted — sidecar NOT needed at all;
the graph is derived and items are engine-saved.

**Interaction:** `object.interact` override (claim-scoped): claims heart and
panel → open network view (panel with no heart → notification + return true).
Blocks NOT claimed → vanilla per-chest UI (individual access stays possible).
All three prototypes carry `interaction_chest`, so with the GML layer absent
every unit degrades gracefully to a plain chest, and the panel's 4 slots are
just bonus network storage.

## Content files (I-data agent; read R1 §2 + R4 §1-2 fully first)

```
yads/
  manifest.json
  fiddle/items/furniture/netstor_set.toml          # 3 items + recipes
  fiddle/object_prototypes/furniture.toml          # 3 prototypes (merge)
  fiddle/mods/yads/ui.toml              # notification/UI strings
  localization/l10n.meta.toml                      # flat per-file rename entry (R1 §2.5!)
  data_files/animation/outlines.json               # icon→outline (R8 Q5; mandatory-in-practice)
  animations/Placeables/Furniture/Netstor Set/     # world sprites + metas
  animations/Item Icons/Placeables/Furniture/Netstor Set/   # 18×18 icons + outlines
  gml/boot.gml  gml/network.gml  gml/view.gml
```

Items (exact recipe costs; ids verified R3 Q4: `basic_wood`, `ore_copper`,
`glass` — display "Wood", "Copper Ore", "Glass"):

- `netstor_heart` — 50 basic_wood, 5 ore_copper, 1 glass, 30 min; tags
  ["furniture","netstor_set","chest_and_storage"]; crafting_level_requirement 1;
  recipe_key netstor_heart; recipe_is_default true; value { store = 1250,
  bin = "self.recipe * 1.1" }; object netstor_heart; icon spr_ui_item_netstor_heart.
- `netstor_block` — 30 basic_wood, 1 ore_copper, 20 min; same tag shape;
  recipe_key netstor_block; value store 400.
- `netstor_panel` — 1 ore_copper, 1 glass, 10 min; recipe_key netstor_panel;
  value store 150.

Prototypes (template = R4 Q1 verbatim `basic_wood_chest_dark`; deltas only):
size [4,2]; `[.south]` sprite + offset [16,0] convention (verify against R8
templates); `interaction_chest` { open_sprite, opening_sprite, bounce_sprite,
inventory_size: heart **54**, block **30**, panel **4** }. Omit the six optional
interaction_chest keys (R4 Q2). Do NOT set interact_mask. No other interaction
data (mutual exclusion, R1 warn 1). Category tag `chest_and_storage` puts all
three in the vanilla woodcrafting "Chests & Storage" sub-category (R4 Q5) —
crafted at the Crafting Station like vanilla chests.

## Sprites (I-art agent; read R8 fully — tables + palette + meta templates)

Per unit: closed 40×48 (1f), opened 40×48 (1f), opening 80×48 (2f, 0.075s),
bounce 120×48 (3f, 0.1s). Item icon 18×18 + pure-white outline 18×18.
Binary alpha ONLY, pure-black #000000 1px outline, R8 palette as base with:
heart = warm wood + glowing cyan crystal core; block = plain wood + cyan inlay
strip; panel = dark slate terminal + cyan screen on small base. Meta.toml per
R8 copy-paste templates (Default atlas world, UI atlas icons, "Middle" offsets
for icons per R8). No shadows v1 (optional per R8 Q4 evidence — 13.6% of
furniture ships none). outlines.json maps each icon → its outline sprite.

## GML modules (I-gml agent; single agent; read R2+R3+R6 FULLY, R5 §2.4, R7 §Q6)

`gml/boot.gml` (or split ≤3 files; every function netstor_-prefixed):

1. **State & lifecycle** — `global.__yads = { ids:{...memoized}, view:undefined }`;
   latched `mmapi_mod_declare` + `mmapi_register(netstor_tick)`; hook
   registrations (object.interact override; ui.menu_closed event;
   save.game_saving event; save.game_loaded event to reset per-save state).
2. **Recipe backfill** — R4 §2.5 pattern: once per save (flag in state, reset
   on save.game_loaded), `ARI.unlock_recipe` all three recipe_keys (existing
   saves never see recipe_is_default, R4 warn 2). Guard with struct/exists
   checks; idempotent.
3. **Network scan** — `netstor_scan(node)` BFS per R7 §Q6 ring-scan recipe
   (plain-array queue, visited via node ref/set on parent_grid only,
   footprint from write_size_x/y). Returns { members:[chest nodes],
   hearts:n }.
4. **Aggregate index** — `netstor_index_build(members)` → array of
   { template LiveItem ref, total, sources:[{slot ref, count}] } grouped by
   partial_eq; plus per-network free-slot count.
5. **Projection** — filter by search string (case-insensitive display-name
   substring, `get_display_name()` R3 Q2), sort by mode ∈ {category (R3 Q5
   14-bucket tag classifier — embed it), name, value (prototype value resolved
   numbers, R3 Q6), count}; write page into view slots directly; expose
   trailing empties = min(9, network free slots > 0 ? free view slots : 0);
   snapshot shadow.
6. **Reconciler** — per-frame while view open: diff → member mutations via
   slot-level surgery honoring partial_eq (R5 §2.4 pattern; `slot.remove(n)`
   / member add respecting room, R2 Q6 table). NEVER call `slot.drain(list)`
   with an argument (engine bug, R2 Q6). NEVER `Inventory.add` without a
   room check (crash when full, R3 warn 2). After applying, rebuild index and
   re-project IF member set changed beyond the view's own edit.
7. **Menu** — `netstor_open_view(scan)`: spawn per R2 Q3 recipe; stamp
   `_menu.netstor_view = state`; override on_close (final reconcile +
   teardown). Post-build widgets (MuseumDonationMenu precedent, R2 Q2):
   page ◀ ▶ sprite buttons + "page i/N" text; sort-cycle button (label via
   ui.toml keys); search box = TextNode `set_takes_input(true)` on click,
   blur on Enter/click-away, AND poll `keyboard_check_pressed(vk_escape)` to
   blur (text focus blanks every keyboard InputId incl. ESC — R2 Q8 critical);
   mouse-wheel page flip when cursor over left box (`mouse_wheel_up/down` +
   `ANCHOR.point_in_node`, Scroller pattern R2 Q5). PAGE_UP/PAGE_DOWN mmapi
   hotkeys (latched; gated on view open) as accessibility extra.
8. **Close/teardown** — on_close + ui.menu_closed (stamped-field test with
   `[$ ]` accessor) both route to `netstor_view_teardown` (idempotent):
   final reconcile, clear state.view. Anchor shutdown path also fires
   ui.menu_closed (R2 Q7) so quit-to-title is covered.

Style: comment-dense; follow game corpus idiom (self., method(), List()/array
usage as the touched APIs demand); try/catch ONLY per MMAPI trampoline rules
(R6 — callbacks are already contained by dispatch; do not wrap hot paths).

## Verification gates (unchanged from skeleton, plus)

1. `tools/check_symbols.py` clean (extend: also flag mod-defined names that
   already exist in corpus = collision/shadowing).
2. GML dialect audit vs corpus + `GmlModLint.cs` warn rules (namespacing!).
3. Data files field-diffed vs R1/R4 verbatims + MOMI merge semantics (esp.
   furniture.toml MERGES into game file — our file must contain ONLY our keys).
4. Red-team INV1–INV5 (revised: custody now write-through; attack the
   reconciler: same-frame double actions, swap PutDown, sort-button permute,
   deposit into full network, infused/quality items, hand-at-close, save
   mid-view, panel-no-heart, two hearts one network, block picked up while
   its stack is on-page — impossible via pause but verify).
5. MOMI CLI `--lint "<mod>" --compile-check require --strict-lints` exit 0.

## Build-night deliverables (all shipped)

Installed mod folder + distributable zip + a first-launch guide covering what was
statically verified vs untested in-engine, an in-game smoke checklist and debug
agent pointers (R6 Q10). That guide is now the "First-launch checklist" section of
the public `README.md`.
