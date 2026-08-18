# Converter facts — the node-replace machine, its escrow, and the confirm popup

Split from `CLAUDE.md` (size rule), and the companion to `docs/remote-facts.md`.
Read before touching `yads_replace_node`, `yads_convert_*`, `yads_upgrade_*`,
`yads_open_convert` or anything that reads `global.__yads.convert*`.

Every claim here is checked against `C:/Claude/.scratch/fom-corpus/gmlsrc/assets`
and cited `file:line` against that tree. Mod citations are against `yads/gml/`.

The converter is the only code in this mod that holds a player's items outside an
inventory, even for a statement. That is why it has a document.

---

## The shape, in one paragraph

`netstor_converter` is a craftable non-placeable (1 copper ingot + 1 glass,
crafting level 1). Hold it and interact with a placed vanilla chest → a confirm
popup → the chest becomes `netstor_crate_<its key>`, contents intact, one
converter spent. Hold it and interact with a placed crate → the same popup → the
crate becomes the chest it came from. Both gestures are one call to
`yads_replace_node(node, target_object_id, undefined)` with the first two
arguments swapped. **Conversion is the only source of the 59 twins**; they carry
no recipe.

**The UPGRADE is the third gesture on the same machine.** Hold a vanilla chest
*item* (any of the 59 convertible sources) and interact with a placed chest **or**
a placed crate → the same popup shape → the footprint ends up carrying the *held*
chest's twin, contents intact. The old shell comes back **as an item**, so shells
are conserved and the converter — spent out of the **backpack**, not the hand —
stays the only true consumable. It is the same `yads_replace_node`, with a third
argument carrying the shell and one infusion. Everything specific to it is marked
**UPGRADE** below.

## The ten-step machine (`network.gml` §11)

| step | what it does | mutating |
|---|---|---|
| 0a–0g | `yads_convert_check` — grid, child-grid, target prototype, footprint, capacity, the engine's own placement test, no-second-surface (`view` · `picker` · `convert_ask` · the live escrow) | no |
| 1 | `yads_pick_forget(node)` — restore `destructable` to `base` while the node is still live | yes (undoes our own) |
| 2 | `yads_glow_invalidate()` | no (a dirty bit) |
| 3 | write the escrow to `global.__yads.convert` — **including the UPGRADE's `shell`** — stage `captured` | no (nothing has left the chest) |
| 4 | capture + empty every occupied slot, appending to the escrow as we go; stage `emptied` | **yes — items leave the world** |
| 5 | `erase_object_node_by_parent`; stage `erased` | **yes — the node is destroyed, and with it the shell** |
| 6 | `grid.write_node(x, y, target, 0)`; stage `written`, or ROLLBACK R | **yes** |
| 7 | `yads_convert_restore` — pour the escrow in, re-apply the carried fields | **yes** |
| **7b** | **UPGRADE**: `yads_convert_settle_shell` decides whether the shell is still owed, then `yads_convert_hand_shell` pops it and hands it over | **yes — an item enters the world** |
| 8 | `_rt.convert = undefined` — escrow released, **and only if it is empty**; otherwise the stage is re-asserted `written` and the escrow is left for the sweeper | no |
| 9 | `yads_glow_invalidate()` | no |

Steps 7b and 8 are in that order deliberately: a throw inside the hand-off leaves
a *registered* escrow the sweeper closes next frame against a footprint the target
is now standing on — which settles to "owed" again and pays it. Releasing first
would have made the same throw a silent loss.

### Step 8 releases only an EMPTY escrow

The de-registration is guarded:

```gml
if (array_length(_escrow.slots) <= 0 && _escrow[$ "shell"] == undefined) {
    _rt.convert = undefined;
} else {
    _escrow.stage = YADS_CONVERT_WRITTEN;
}
```

Beta 1.3 wave 1 shipped this as a bare `_rt.convert = undefined;`, and that was
the **one de-registration in §11 not paired with a hand-back** — the same move
`yads_convert_recover`'s no-player arm refuses to make in as many words
("clearing with nowhere to hand the items would delete them"). Two call sites one
and two statements above it can leave something in the escrow, and neither is
provable at that line:

- `yads_convert_restore` ends its `while` on `_i >= _size` and returns
  **silently**, with whatever did not fit still in `_escrow.slots`;
- `yads_convert_hand_shell` returns **before** `_escrow.shell = undefined` when
  `!instance_exists(obj_ari)`, leaving the shell staged.

Both are unreachable today, on premises that live **outside** §11 — see the walk
below — which is exactly why the test is cheaper than the proof.

**Why leave it registered rather than refund inline.** The sweeper is the only
code that knows how to finish an escrow, and it tries the *good* outcome first:
pour the remainder into whatever is standing on the footprint, and only then hand
the rest to the player. An inline `yads_convert_refund` would skip straight to the
player's hands for a stack the target could have taken. It runs at the head of the
very next tick and again from `save.game_saving`, so "next frame" is bounded.

**The three invariants the guard keeps**, because the shape looks like a retry and
is not:

| invariant | why it holds |
|---|---|
| no double-drain | the stage is re-asserted `written`, never `refund`, so the sweeper takes its in-place arm exactly once (`network.gml`'s `if (_stage != YADS_CONVERT_REFUND)`), and every stack it places is `array_delete`d out of the escrow *before* the slot write |
| no two-frame lifetime on the happy path | an empty escrow with no staged shell clears in the statement that created it, byte for byte as before. The second frame is bought only by a world that already went wrong |
| gate 0g still refuses | a live escrow is a `REFUSED` verdict, so no new gesture starts on top of one; and the tick runs the sweeper (`boot.gml`) strictly **above** `yads_convert_apply`, so a stranded escrow is closed before the next confirm executes |

The return value is unchanged and still `true`: the target is standing and holds
what it could take, so the swap happened and the caller's costs are payable.
Returning `false` would leave a converted world nobody paid for.

### Step 6 is `Grid.write_node`, NOT `write_furniture_to_location`

The 1.3 recon specified the bare `write_furniture_to_location`. That is wrong and
the correction is load-bearing: **that function does not create a renderer**. Only
`Grid.write_node` does, one line after it, and only when `self.is_setup &&
self.location_id == CURRENT_LOCATION_ID` (`Grid.gml:208-215`). A bare call would
have produced an invisible, uninteractable, unglowable node holding the player's
items. `write_node` is also the function vanilla's own placement uses
(`use_item.gml:103`) and it keeps the `GROW_BACK` collider counters symmetric with
the erase (`Grid.gml:264-277` vs `GridUtils.gml:199-212`).

### Gate 0b is the SOLE child-grid guard, and gate 0f does not back it up

The shape of the two suggests redundancy and there is none.
`furniture_test_flag_mask` opens with the same test gate 0b makes —
`grid.parent_node != undefined && !proto.can_be_child` (`Furniture.gml:1959`) —
and the second half is **never true for a chest**:

- vanilla `fiddle/object_prototypes/furniture.toml` declares `[default]
  can_be_child = true` at `:91` (the `[default]` table opens at `:7`), and **not
  one of the 59 source chests overrides it**;
- the mod's own `furniture.toml` sets it on no twin and carries no `[default]` of
  its own, so both sides inherit the same vanilla default.

Machine-checked across all 118 prototypes, together with the other four fields the
test reads: **zero** overrides of `can_be_child`, `rug`, `rule_grid`,
`input_terrain` or `placeable_locations` on any of the 59 sources. (The only
per-prototype override in that set is `collision_grid = "2"` on the two cottage
fridges, and that field is not read by the test at all.)

So gate 0f answers "fine" for a chest on a tabletop, and **`_grid[$ "parent_node"]
!= undefined` is the whole defence**. Delete it and the feature writes invisible
crates onto tables: a child grid is minted by `new Grid(...)` with `is_setup =
false` (`Grid.gml:50`), nothing ever sets it true for one, and `Grid.write_node`
builds a renderer only for `is_setup && location_id == CURRENT_LOCATION_ID`
(`Grid.gml:208-212`).

**What 0b does not test**, named so it is a known gap rather than a forgotten one:
`is_setup` and `location_id == CURRENT_LOCATION_ID`, the other two halves of that
same renderer condition. Nothing in `yads_convert_check` tests either. A
non-current-location grid is unreachable through `interact()` — the press comes
from a node the player is standing next to — so the failure has no construction
today. It is worth writing down because gate 0f itself passes `ignore_ari =
(_grid != global[$ "__grid"])`: the author of that line explicitly contemplated a
grid that is not `GRID`, and the two assumptions should not drift apart silently.

### Gate 0f is the engine's own test, run early

`furniture_test_flag_mask(rot_data, grid, x, y, target_proto, matrix,
ignore_object = true, ignore_ari = grid != GRID)` — the same call step 6 will make
(`Furniture.gml:630-642`), with only the per-cell occupancy test skipped, because
that is the one test the source is failing on purpose (it is standing there) and
the one our own erase clears. **So the gate passes exactly when the write would
succeed.** That makes step 6's failure arm unreachable short of an engine change,
and makes a refusal a refusal the engine was going to make anyway — with nothing
destroyed.

The alternative considered and rejected: a hand-written `collision_rectangle` over
the Ari/pet/animal rectangle. It would have had to reproduce GameMaker's boundary
semantics exactly, and a one-pixel disagreement fails in the direction that costs
a chest (missed refusal) or kills the feature (false refusal on every press).

### Gate 0f stays exact for the UPGRADE, across families

The 1.3 argument for 0f rested on the two prototypes being *the same chest's
pair*. The upgrade points a **different** chest's twin at the footprint, so that
argument has to be re-made — and it holds, on a narrower fact.
`furniture_test_flag_mask` reads exactly six fields of the prototype it is given:
`can_be_child`, `rug`, `size`, `rule_grid`, `input_terrain` and
`placeable_locations` (`Furniture.gml:1958-2010`). The 118-prototype audit found
that **no chest overrides any of the last five**, and gate 0d has just proved
`size` equal. So two chest prototypes of the same footprint answer that test
identically, whatever family they come from. The one field that *does* differ
across families — `collision_grid`, which the two cottage fridges set to `"2"` —
is never read by the test; it is applied by the write, after the answer is in.

### Gate 0d and gate 0e stopped being asserts

Both were written as guards against a future content set and both are now
doorways a player meets on the ordinary way through:

| gate | convert / downgrade | upgrade |
|---|---|---|
| 0d footprint | unreachable — a twin copies its source's `size`, and all 59 sources are single-cardinal so nothing rotates | **reachable**: 4 of the 59 twins are `[3,2]` and 55 are `[4,2]`, i.e. **440 of the 3,422 ordered chest pairs** refuse here |
| 0e capacity | unreachable — a twin copies its source's `inventory_size` | **reachable**: the shipped set carries three capacities (54×32, 42×10, 30×17), so a 30-slot chest held at a 40-stack unit refuses |

0d therefore got its own verdict, `YADS_CONVERT_FOOTPRINT`, split out of
`YADS_CONVERT_REFUSED`. That is the codebase's own rule applied rather than a new
one — *"one refusal, one string; split whenever the refusal has a fix the player
can act on"* — and it is observably a no-op for convert and downgrade, which fold
it straight back onto `convert_refused` because they can never produce it.

---

## Throw analysis — every mutating step

`object.interact` runs inside `mmapi_run_override`, which **swallows a throw**
(`mmapi_hooks.gml:362-368`): no crash, no log line the player sees. A throw in the
tick is caught per installer (`mmapi.gml:71-84`), which skips the rest of that
frame's tick body and runs it again next frame. So every row below has to be
survivable without anybody noticing at the time.

| throw at | world | items | recovered by |
|---|---|---|---|
| gates 0a–0g | untouched | in the chest | nothing needed — no mutation has happened |
| step 1 (`pick_forget`) | untouched | in the chest | nothing needed. The entry it failed to release is swept by `yads_pick_poll`'s liveness test within a frame, and the flag it failed to restore is restored by the same poll |
| step 2 (`glow_invalidate`) | untouched | in the chest | nothing needed |
| step 3 (escrow write) | untouched | in the chest | escrow may exist with `slots: []`, stage `captured`. The sweeper finds zero stacks, places nothing, raises no toast, clears |
| **step 4, part-way** | chest still placed, **partially emptied** | k stacks in the escrow, the rest still in the chest | sweeper, stage `captured`: the node is still at (x,y), so `recover_inplace` pours the k stacks straight back into it. They may land in lower slot indices than they left; nothing is lost |
| **step 4→5 boundary** | chest still placed, fully emptied | all stacks in the escrow | sweeper, stage `emptied`: node still there, pour back |
| **step 5 (erase)** | node gone, cells vacated, renderer destroyed | **all stacks in the escrow only** | sweeper, stage `erased`: the cell is empty, so re-write the **SOURCE** at (x,y) and pour in. Cannot fail for the reason gate 0f exists |
| **step 6 returns undefined** | cells vacated | all in the escrow | **ROLLBACK R**, inline: re-write the source, restore, clear, toast `convert_failed`. Unreachable given gate 0f |
| **step 6 throws** | indeterminate — a node may or may not exist at (x,y) | all in the escrow | sweeper, stage `erased`: probe the cell. A node with an inventory → pour in. Empty → re-write the source and pour in |
| **step 7, part-way** | the target node is placed | k stacks in it, the rest in the escrow | sweeper, stage `written`: re-resolve the node at (x,y) and pour the remainder into its free slots |
| **step 7 returns with a REMAINDER** (no throw at all — the restore simply ran out of slots) | the target node is placed | k stacks in it, the rest in the escrow | **step 8 refuses to de-register a non-empty escrow** and leaves it at stage `written`; the sweeper pours what now fits and refunds the rest. Walked in full below |
| **the sweeper's own in-place arm throws** | as above | in the escrow | the stage was stamped `refund` *before* the arm ran, so the next frame skips the in-place arm entirely and goes straight to the player's hands |
| **the sweeper's refund arm throws** | as above | at most one stack | the escrow was de-registered before the refund started, so there is no third pass. Each stack is popped from the array *before* it is placed, so a throw loses at most one stack and can never duplicate one. **This is the single residual** and it needs a bug inside a four-statement loop on top of the bug that stranded the escrow |
| a save raised while an escrow is live | — | in the escrow | `yads_game_saving` runs the same sweeper, step 0b, after the pick flush and before anything else. The escrow is **not serialized** (no modsave sidecar), so without this call the items would simply cease to exist |
| a load started while an escrow is live | — | dropped | `yads_game_loaded` clears it. The items belong to the outgoing save and there is nowhere to put them: the hook fires before `GRIDS` is rebuilt and with `ARI` about to be replaced. Unreachable — an escrow only outlives its own statement if that statement threw, and the sweeper closes it on the next tick |
| no `obj_ari` when the sweeper runs | — | in the escrow | the sweeper **does not clear** in that state. It waits, one struct read a frame, because clearing with nowhere to hand the items would delete them. Bounded by the next frame with a player, or by `game_loaded` |

### The remainder walk — "the restore left something behind", end to end

This is the construct that used to be lethal, and it is the only row in the table
that needs **no throw anywhere**. It is walked in full because the two premises
that make it unreachable both live outside §11 and neither is asserted at the
point of use.

**Why it does not happen today.**

- Gate 0e proved `_occupied <= target_proto.interaction_chest.inventory_size`,
  counting occupied slots (`count > 0 && item != undefined`), and step 4 captures
  exactly those `_occupied` stacks — one escrow entry per occupied slot, no
  merging.
- `Furniture.gml:758-759` mints `node.inventory =
  Inventory(node.prototype.interaction_chest.inventory_size)` for every furniture
  write with an `interaction_chest` — a **fresh** inventory of exactly the gate's
  bound with every slot at `count == 0`. So `yads_convert_restore`'s
  `if (_slot.count > 0) { continue; }` never skips a slot and the fit is total.

Move either one — an engine that hands back a partly-populated inventory, a
content set where `inventory_size` and the real slot count disagree, a future
`allow_soulbound` filter that refuses a slot — and the `while` ends on
`_i >= _size` with k stacks still in `_escrow.slots`.

**Frame N, inside `yads_replace_node`:**

1. steps 1–6 as usual; the target is standing on the footprint, stage `written`.
2. step 7 `yads_convert_restore` places what fits. Every stack it places is
   `array_delete`d from `_escrow.slots` **before** the slot write, so the array is
   the exact list of what is still homeless. It returns silently with k left.
3. step 7b `yads_convert_settle_shell` sees the **target** standing
   (`object_id != source`) → the shell stays **owed**; `yads_convert_hand_shell`
   pops it and `ARI.give_item`s it. (On convert/downgrade there is no shell and
   both calls are no-ops.)
4. step 8 tests the escrow: `array_length(slots) > 0` → **it is not released**.
   The stage is re-asserted `written`. `yads_replace_node` returns `true`.
5. `yads_convert_apply` charges its costs — correctly: the swap happened.

**Between the frames:** `_rt.convert` is live, so gate 0g refuses any new gesture
and `yads_remote_ready` refuses the hotkey. One frame.

**Frame N+1, at the head of `yads_tick`:**

6. `yads_pick_poll`, then `_rt[$ "convert"] != undefined` → `yads_convert_recover`.
7. The no-player wait does not fire (there is a player), so `_stage = written` is
   read and the stage is stamped `refund` **before** anything runs.
8. `_stage != refund`, so `yads_convert_recover_inplace(escrow, written)` runs
   once: `slots > 0` passes the early-out, the grid cell is re-resolved from
   `(x, y)` — nothing remembered is trusted — and the node found there is the
   target, which has an inventory. `yads_convert_restore` pours whatever now fits
   (nothing, if the target is genuinely full), then `settle_shell` re-asks against
   that node and gets the same answer as step 7b.
9. Back in the sweeper: `_rt.convert = undefined` **then** `yads_convert_refund`.
   Anything still in the array goes `can_add` → `add` into the backpack, and past
   that `drop_item_stack` at the player's feet — which **is** recorded by a save,
   see the `lost_items` note below. Toast `convert_recovered`. `glow_invalidate`.

**Item delta: zero.** The escrow's lifetime is bounded at two frames, the in-place
arm runs exactly once, and every stack is popped before it is placed on both
passes, so nothing can be placed twice.

If instead the shell is the thing left staged (`hand_shell` bailed on no
`obj_ari`), step 8 keeps the escrow for the same reason and the sweeper's
no-player wait holds it — without clearing — until there is a player to hand it
to. That arm is the one place the "never two frames" rule bends, and it bends the
safe way.

### The shell's own rows (UPGRADE only)

The shell is an `ItemId` staged on the escrow at step 3, before anything is
captured, and it is the one escrow field whose payout is **conditional**. Every
row below is on top of the corresponding row above, which still governs the
stacks; the "shell" column says where the player's old chest is.

**The rule, in one compare** (`yads_convert_settle_shell`): the old shell is still
in the world **exactly when the node on the footprint is the `source`**. Then the
player already has it, standing where they left it, and an item on top of that
would mint a second chest. Every other world — the target standing, an empty cell,
a foreign node — means the shell they owned no longer exists and the item is owed.
It is tested against `source` and *not* against `target` on purpose: those two are
the same question only while the footprint holds one of ours, and the empty-cell
and foreign-node cases are precisely where they differ. `source != target` is
guaranteed by the same-shell refusal (see the matrix below), and the two converter
gestures never stage a shell at all.

| throw at | world | shell | recovered by |
|---|---|---|---|
| any gate, including the upgrade's own three | untouched | still the placed node | nothing needed — no shell has been staged |
| step 3 (escrow write) | untouched | staged; the source is standing | sweeper, stage `captured`: the probe finds the **source**, so settle **cancels**. Nothing is handed over and nothing is lost — the chest never left |
| step 4 part-way, and the 4→5 boundary | source standing, partly or fully emptied | staged; source standing | sweeper, stage `captured`/`emptied`: stacks pour back, then settle **cancels** |
| **step 5 (erase)** | node gone, cells vacated | staged, and now genuinely homeless | sweeper, stage `erased`: the cell is empty → re-write the **source** → settle **cancels**. If that write is refused, the shell stays owed and the refund arm hands it over — which is the only outcome in which the player ends up with what they started with |
| **step 6 returns undefined, source re-written** | source standing | staged | **ROLLBACK R**, inline: `yads_convert_settle_shell(_escrow, _back)` **cancels** before the escrow is cleared. No cost is charged (the machine returns false), so a rollback pays the player nothing and takes nothing |
| **step 6 returns undefined, both writes refuse** | cell empty | staged | sweeper, stage `erased`: one more attempt at the source; landed → cancel, refused → the refund arm hands the shell over with the stacks |
| **step 6 throws** | indeterminate | staged | sweeper, stage `erased`: probe. Target standing → pour in, shell **owed**. Source standing → **cancel**. Empty → re-write the source → **cancel** |
| **step 7 part-way** | target standing | staged | sweeper, stage `written`: pour the remainder, settle sees the **target** → **owed** → the refund arm hands it over |
| **step 7b, the settle** | target standing | staged | cannot meaningfully throw: two `[$ ]`-guarded reads on a node the caller already resolved. If it did, the escrow is still registered at stage `written` and the sweeper repeats the same probe next frame for the same answer |
| **step 7b, the hand-off, before the pop** (no `obj_ari`) | target standing | staged, **not** popped | deliberate: `yads_convert_hand_shell` bails *before* clearing the field, so the sweeper's no-player wait — which now counts a staged shell as something to hand back — keeps the escrow alive until there is a player |
| **step 7b, the hand-off, after the pop** | target standing | **gone** | nothing. **The second residual**, and it is exactly one item: `give_item` is called after the field is cleared, the same pop-then-place ordering the refund loop uses, so a throw here loses one chest and can never mint one |
| **step 7b succeeded, throw before step 8** | target standing, shell delivered | delivered | sweeper next frame: zero stacks, `shell == undefined`, so settle and refund are both no-ops, no toast, escrow cleared. `yads_replace_node` never returned, so **neither cost is charged** — and that **MINTS A CHEST**, it does not cost the mod one. Counted below |
| **throw between `replace_node` returning true and `chest.remove(1)`** | target standing, shell delivered | delivered | nothing needed, and the count is the same **+1 mint** as the row above: the world change is complete and neither cost has been taken |
| **throw between the two spends** (after `chest.remove(1)`, before the converter) | target standing, shell delivered | delivered | nothing needed, and **this** one is the mod's freebie: the chest is spent, the converter is not. Net zero objects. Stated in the code as the trade the ordering buys |
| a save raised while a shell is staged | — | staged | `yads_game_saving` runs the same sweeper, and the shell rides its arms exactly like a stack. Not serialized, for the escrow's own reason |
| a load started while a shell is staged | — | dropped | `yads_game_loaded` clears the escrow. Unreachable for the escrow's own reason |
| no `obj_ari` when the sweeper runs | — | staged | the sweeper **waits** rather than clearing, and a staged shell now counts towards "there is something to hand back" — so the wait covers the empty-unit upgrade that has a shell and no stacks |

Two consequences worth stating outright:

- **The shell is never duplicated.** Every path that ends with the source standing
  on the footprint cancels it, and the two that end with an empty cell or the
  target standing pay it. There is no path that both re-writes the source and
  hands the item over.
- **The shell can be lost only by a throw inside `give_item` itself**, on top of
  the throw that stranded the escrow. That is the same shape, and the same size,
  as the residual the stack refund already carries.

### The upgrade's consume-last ordering MINTS a chest, it does not cost the mod one

Two rows of the table above shipped the wrong sign in earlier waves, and it was
the wrong sign in the **duplication** direction, which is why it is called out
rather than quietly patched. Count the chest-shaped objects.

Before the confirm: the player holds **n** copies of the chest item H in the
backpack (n ≥ 1, that is the tool of the gesture), and the shell node **S** stands
on the footprint. **n + 1** chest objects.

After a throw anywhere between `yads_replace_node` returning `true`
(`boot.gml`, the consume block) and `_chest.remove(1)`:

| | count |
|---|---|
| H items still in the backpack — never spent | n |
| the returned shell, handed over by step 7b as an item | 1 |
| `twin(H)` standing on the footprint | 1 |
| **total** | **n + 2** |

**Net +1 chest minted**, and it is a real object: one converter turns the standing
twin back into a real chest through `yads_downgrade_gesture`. The mod did not
"eat a converter and a chest" — it charged nothing at all and handed out a twin.

**Why the opposite framing is right for convert and downgrade.** Those two are a
1:1 footprint swap — `twin(S)` replaces `S`, nothing is returned — so the only
thing an unfinished gesture can leave behind is an unspent converter, which is the
mod's freebie and the player's windfall of one crafting item. The upgrade is a
**three-body** swap (held chest in, old shell out, twin standing), and the same
consume-last ordering that makes the two-body case cost the mod a freebie makes
the three-body case pay the player a chest.

**It is still player-safe, and that is the point of the ordering.** Every error
this consume block can produce is an **over-refund**: the player ends up with the
same objects or more, never fewer. Consume-first would have inverted exactly that.
And the mint is not reachable — it needs a throw inside `yads_upgrade_slot`, which
is four struct reads plus one `_backpack.slot(_index)` on an index the same
function bounds-tested two lines earlier. It is recorded because this table is a
set of claims, and a claim that is wrong in the duplication direction is the one
kind a reader must not inherit.

### The shell is handed over with `ARI.give_item`, not with the refund loop

The stack refund uses `can_add` → `add` → `drop_item_stack` by hand because it is
placing *existing* `LiveItem` structs it must not clone. The shell is a **fresh**
item minted from a prototype, so it can go through the engine's own one-call
path: `give_item` does `room_for_item`, drops the overflow at the player's feet
with `drop_item_stack`, adds the rest, and falls back to
`GRIDS[PlayerHome].lost_items` when there is no player at all
(`Ari.gml:465-495`). It is called `give_item(item, 1, true, false, true)` —
`show_new_popup` **false**, because give_item's "you found a new thing" arm builds
an `await_popup` chain (`Ari.gml:511-519`) and this runs from the tick with the
mod's own popup one frame in the rear-view. The pickup toast and sound stay.

The `LiveItem` is built the way vanilla's own furniture pickup builds it
(`Pick.gml:509-515`): mint from `find_item_prototype(shell_object).item_id`, then
stamp the node's infusion **only if** the fresh item did not arrive with a
`default_infusion` of its own (`LiveItem.gml:15-16`).

### Two infusions, because an upgrade is a pickup followed by a placement

Convert and downgrade leave the same shell on the footprint, so the node's
infusion is carried straight across. An upgrade replaces the shell, and vanilla
stamps each half of that from its own item: a placed furniture node takes the
**placed item's** infusion (`use_item.gml:122`) and a picked-up furniture item
takes the **node's** (`Pick.gml:511-513`). The escrow therefore carries both —
`infusion` is what the target gets, `shell_infusion` is what the source had — and
`yads_convert_restore` picks between them by asking which of the two is actually
standing, so the inline rollback and the sweeper's re-write arms put the source
back the way it was rather than stamping the held chest's Quality onto it.

This is not theoretical. `quality` is the one infusion whose `supported_tags` is
`["furniture"]` (`fiddle/infusions.toml`), every chest item is tagged `furniture`,
and getting it wrong destroys or mints one in every upgrade.

### Why an escrow at all

Between step 4 and step 7 the items exist in exactly one place: a plain array on
`global.__yads`. That struct is reachable from `yads_tick`, which runs every frame
from `Game.step_begin` (`Game.gml:570-582`) whether or not any menu is open. A
local variable would be unreachable, and a throw would be silent deletion.

### Why the sweeper is second in the tick

`yads_pick_poll` is first and must stay first — nothing that can throw may run
ahead of the `destructable` restore (`docs/safety-invariants.md`). The sweeper is
immediately after it, and the confirm executor immediately after the sweeper —
that last order is a dependency, not taste: `yads_convert_check` gate 0g refuses
while an escrow is live, so a stranded one has to be cleared before a new
conversion is attempted.

### …and what being second COSTS: the escrow's two exits are downstream of the pick pass

An accepted coupling, stated because it was previously argued only from the pick
side. Both of the escrow's exits sit **below** a pick call that could throw, and
in both cases the throw takes the exit with it.

| ordering | mechanism | what a throw above costs |
|---|---|---|
| `yads_pick_poll` → the sweeper, in `yads_tick` | `mmapi_run_installs` wraps each installer in `try/catch` and **skips the rest of that installer's body** (`mmapi.gml:71-84`); this whole tick is one installer (`mmapi_register(yads_tick)`) | the sweeper does not run that frame. The picks registry is persistent state, so a data-shaped fault repeats and the sweeper never runs again this session — a stranded escrow then has only `save.game_saving` left, or `game_loaded`'s drop |
| `yads_pick_flush` → the escrow flush, in `yads_game_saving` | one function body, so the rest is skipped outright; and `mmapi_emit` catches **per handler** (`mmapi_hooks.gml:253-257`) rather than aborting the save | **the save commits without the flush.** This is the one path on which a live escrow becomes real, permanent item loss: it is not serialized, the mod registers no modsave sidecar, and what lands on disk is a world whose chest was emptied by a swap that never finished |

**Accepted, not fixed, and the trade is explicit.** What the pick pass prevents is
a `destructable = false` serialized into the player's save — a crate welded shut
permanently, past uninstallation of the mod — which is unrecoverable. What it
gates is a window that only opens **after** a throw has already happened, and the
poll itself is a two-field loop over an array bounded by the units a player swung
at in the last ten seconds. The ordering is right. Reordering the pair to "fix"
this would trade an unrecoverable failure for a recoverable one in the wrong
direction. Both sites carry the paragraph in code.

### A dropped refund IS serialized — the `obj_item` residual does not exist

Earlier waves shipped a "known residual" over `yads_convert_refund` claiming that
a dropped `obj_item` is not serialized, so a refund raised from
`save.game_saving` with a full backpack "puts a stack somewhere the save will not
record". **That is false**, and false in the direction that makes a reader defend
against nothing. `save_game` records it:

```
 1  function save_game(save_path) {
 2      var saver = new RustSaver(save_path);
 3      Game.last_serde_path = save_path;      <- the save.game_saving emit lands here
13-26      for (LocationId) { grid.save(saver); }
29      store_loose_items_as_lost();
38          var data = serialize_lost_items(grid.lost_items);
```

- the seam plants the emit immediately after `Game.last_serde_path = save_path;`
  (momi `docs/MMAPI/seams/save_game_saving.md`), i.e. at line ~4 — **before** the
  grid loop and before line 29;
- `drop_item_stack` instantiates the world item on the spot (`drop_item.gml:39-47`
  — `instance_create_layer(..., obj_item)` then `setup(items)`), so it is live by
  the time line 29 runs;
- `store_loose_items_as_lost` is `with obj_item { GRID.lost_items.push({x, y,
  items}) }` (`Items.gml:687-696`) — **every** live world item, unconditionally, no
  filter and no age test;
- `serialize_lost_items` writes them (`Items.gml:711-729`) and
  `restore_lost_items` re-instantiates them at the same coordinates on load
  (`Items.gml:698-709`, reached via `Grid.gml:517` over `LoadGame.gml:331`'s
  deserialize).

**The conclusion it propped up survives and gets stronger**: `yads_convert_refund`
is safe on *both* of its paths. On the tick path the item is in the world and the
player walks over it; on the save path it persists as a lost item and comes back
on load. The engine's own chest-erase drop (`GridUtils.gml:296-311`) has the same
property, which is now a reason to trust it rather than a shared caveat. The only
real residual in that function is the pop-then-place window on one stack.

---

## What crosses the replace, and what must not

The grid serializer is a generic struct walker whose skip list is `prototype`,
`last_update`, `renderer`, `sub_grid_blob`, `parent_grid`, `write_size_x`,
`write_size_y`, `active_toy_sfx` (`Grid.gml:1419-1428`). Everything else on a node
round-trips through the save, so anything the write resets has to be carried.

| field | carried | why |
|---|---|---|
| `use_in_crafting` | **yes** | player-settable in the vanilla StorageMenu (`StorageMenu.gml:525-547`), serialized via `Grid.gml:1445`'s default arm, and re-derived from the prototype by every write (`Furniture.gml:871-873`) |
| `chest_icon` | **yes** | the label the player chose; reset to `undefined` by the write (`Furniture.gml:760`) |
| `infusion` | **yes** — but see below | reachable and real: `use_item.gml:122` stamps it onto the node when an infused furniture item is placed, `Pick.gml:470`/`:513` hand it back on pickup; reset by the write (`Furniture.gml:650`). Carried straight across for convert/downgrade. **On an UPGRADE it is not carried but re-sourced**: the target gets the HELD item's infusion and the returned shell gets the node's, per "Two infusions" above |
| `destructable` | **NO — never** | `docs/safety-invariants.md` §THE `destructable` CONTRACT. The write derives it from the prototype and then re-forces `false` on any `TileFlag.Unbreakable` cell under the new footprint (`Furniture.gml:646`, `:685-687`). That is the engine's own answer and copying the old value would let a stale `true` outlive the rule that produced it |
| `on`, `date_photo` | no — nothing to carry | both written unconditionally by every furniture write (`Furniture.gml:651-652`); `on` has no reader anywhere in the corpus and `date_photo` is only ever set for an `is_date_photo` prototype, which no chest is |

`inventory` itself is **not** re-pointed. The new node gets a fresh
`Inventory(target.inventory_size)` (`Furniture.gml:759`) and the contents are
copied per slot; handing over the old struct would ship a container whose `size()`
disagrees with its prototype and get force-resized on the next load
(`Grid.gml:1139-1145`).

## Capacity, and why it was asserted before anyone could reach it

A twin copies its source's `inventory_size`, so both *converter* directions are
same-size and the contents always fit. Gate 0e counts occupied slots and refuses
anyway, because `Grid.gml:1139-1145` force-resizes a loaded chest to its
**current** prototype size and `Inventory.gml:49-52` pops the trailing slots
**undrained**. The day a twin's size stops matching its source, that assert is the
difference between a refusal toast and silently deleted items in every save that
used the key.

That day arrived with the upgrade, in the harmless direction: the target is now a
*different* chest's twin, the shipped set carries three capacities (54, 42, 30),
and the assert became the doorway. It bounds on `_chest.inventory_size` — the
**target's**, i.e. the held chest's — which is exactly the rule the gesture
advertises. See the gate table above.

## Rotation

Not an issue, verified rather than trusted: **all 59 source prototypes declare a
`.south` block and nothing else** (audited over
`fiddle/object_prototypes/furniture.toml`). `proto.cardinals` therefore has length
1 and `furniture_rotation_amount(0, proto)` is `wrap(0, 1) == 0`
(`Furniture.gml:2017-2020`). The footprint gate catches it regardless: a rotated
node's `write_size_x/y` are swapped (`Furniture.gml:2028-2035`) and would not equal
the target's `size`.

## The two prototypes are placement-identical

Audited over all 59 pairs: same `size`, same `inventory_size`, same
`collision_grid` (only the two cottage fridges override it, and the twin copies the
source's `"2"` verbatim), and **neither side** overrides `rule_grid`,
`input_terrain`, `output_terrain`, `placeable_locations`, `sub_grid`, `rug`,
`destructable`, `can_be_child` or `depth_offset`. That is what lets gate 0f stand
in for step 6's own test.

For the upgrade the *pair* is not the relevant unit — see "Gate 0f stays exact for
the UPGRADE" above, which re-derives the same conclusion from the narrower fact
that no chest overrides any of the five fields the test actually reads.

---

## Cache invalidation — every cache that could hold a stale node reference

| cache | holds | invalidated by |
|---|---|---|
| `_rt.glow` (`network.gml` §9) | `{node, renderer, top, kind, lit, used, size, ...}` per unit | **three ways, two of them automatic.** (a) `furniture.place_guard` fires at the head of `write_furniture_to_location` for our own write and `yads_place_guard` calls `yads_glow_invalidate()` — confirmed still registered at `boot.gml` §2. (b) `yads_glow_apply` sets `dirty` the frame a cached `top` stops being `instance_is_alive`, which the erase guarantees. (c) our own explicit calls at steps 2 and 9. The redundancy is deliberate and stated in code: the `STORAGE_NODES.count()` poll **cannot** see this change — an erase and a write in one frame net to an equal count, the documented hole over `yads_glow_poll` — so if (a) is ever refactored away, (c) is what stops the hole reopening silently |
| `_rt.picks` (`network.gml` §10) | `{node, base, count, tick, held, ttl}` keyed on the node struct | `yads_pick_forget(node)` at step 1, **before** the erase, so the `base` restore lands on a live node. It also self-sweeps: `yads_pick_poll` drops any entry whose `renderer` is not `instance_is_alive`, and `erase_object_renderer` destroys it (`GridUtils.gml:170-172`) |
| `_rt.ids` (`network.gml` §1) | ObjectId/ItemId numbers, the kind array, the offline assets, the two conversion tables | **not node-scoped.** A replace mints no ids and renumbers nothing. Untouched, correctly |
| `_rt.categories` (`network.gml` §4) | item_id → sort bucket | derived from static prototype data. Untouched |
| `_rt.view` (the network mirror) | `members[]`, `deposit_targets[]`, `rows[]` with live `LiveItem` refs, the shadow snapshot | **cannot coexist with the gesture.** Two independent proofs: the interact ladder returns `true` at `_rt.view != undefined` before any gesture branch, and gate 0g refuses. Behind both, the engine: a Storage menu declares `pause = "main"`, so the FSM cannot reach `attempt_interact` at all. **Corollary worth keeping**: the machine never has to reconcile a live mirror against a node it is about to erase — which is why a "convert" button *inside* the network view would break it |
| `_rt.picker` | the network picker popup | same, same line in the ladder, same gate |
| `_rt.convert_ask` | the confirm popup | the third surface, and now tested in **three** places: the ladder's not-ours arm (defers), the ladder's post-ownership guards (swallows) and gate 0g (refuses). Released by `yads_menu_closed` on the popup's stamp, and earlier than that by `yads_convert_apply` on a Yes — see the frame order below, that early clear is what keeps gate 0g from refusing the confirm itself. It carries `mode` where it carried `down`, and still no shell — the executor re-derives that from the live node |
| engine: `ITEM_PROTOTYPES` | every item prototype, `ItemId`-indexed | **not a cache of ours and not node-scoped.** The upgrade reads it two ways: `item.prototype.object` (one struct hop, `Items.gml:51` guarantees the field exists and is a real or `undefined`) and `find_item_prototype(object)`, which is the engine's own linear scan and the same call vanilla's furniture pickup makes. The scan runs at most twice per confirm — once in the gesture, once in the executor — never on the interact hot path |
| connectivity graph | — | **there is none besides `_rt.glow`.** `yads_scan` allocates fresh per call and the mod deliberately caches nothing |
| engine: `STORAGE_NODES` | every inventory-bearing node | the erase removes (`GridUtils.gml:322`), the write pushes (`Furniture.gml:870`) |
| engine: `grid.node_parent` / `node_object_id` / `node_top_left_*`, collision, footstep | per-cell | the erase clears every footprint cell (`GridUtils.gml:367-390`), the write re-sets them |
| engine: `FACTORIES`, `grid.sprinklers`, `pet_beds`, `pet_dishes`, `activity_nodes`, `terrain_editors` | node lists | not applicable — no chest prototype sets any of the fields that push onto them |
| engine: NPC `activity_handler.target_node` | one node per NPC | cleared by the erase itself (`GridUtils.gml:349-360`) |
| engine: `GROW_BACK` collider counts | per farm cell | symmetric, and moot: no chest is a grow-back candidate (`fiddle/grow_back.toml` lists five rocks/plants) |

---

## The confirm popup, and one full frame of the ANCHOR loop

The surface is `popup_creator(title, body)` plus two `create_button` calls and
nothing else — no geometry of ours. `create_button` auto-glyphs and auto-positions
**exactly two** buttons: #1 takes `InputId.MenuBack`, #2 takes `InputId.Interact`,
and at #2 it pulls the first 40px left and the second 40px right
(`PopupMenu.gml:86-106`). The labels are vanilla's translated `misc_local/no` and
`misc_local/yes`, which is the corpus's own idiom for a two-button confirm
(`Interact.gml:643-644`, `AriUtils.gml:631-632`, `AnimalUtils.gml:695-696`).
**The mod adds no loc key for either button.**

### Hover listeners: exactly two, and they do not overlap

`set_tap_callback` is what sets `listens_for_hovers` (`Node.gml:519-520`), and
`create_button` is the only thing on this popup that calls it. The title and body
are `ANCHOR.text` with `set_key`; the header, the body plate and the backplate are
bare nine-slices; the canvas carries a think, and `set_think_callback` sets
`run_logic` and nothing else (`Node.gml:540-550`). So the "never overlap two hover
listeners" rule has exactly one pair to check.

Both buttons are `Align.Center/Align.BottomIn` at `y = -10` and sized
`max(60, width_for_text_container(label, 18))` (`PopupMenu.gml:64-70`). A button of
width `W` centred at `±40` spans `40 ± W/2`, so the two touch only once `W > 80`,
i.e. only once a label measures more than 62px. "Yes" and "No" are 2–3 glyphs in
every shipped locale, so both sit at the 60px floor: #1 spans −70..−10, #2 spans
+10..+70, **20px of dead plate between them**. Nothing to steal, so no
`listen_for_hovers` gate is needed and none is added.

### The frame, in iteration order

`Anchor.on_begin_step` walks `node_registrar` **backwards**, `node_count-1` down to
0 (`Anchor.gml:362-370`), so the last node registered is visited first. Registration
order here is canvas → backplate → header → title → body → body_text → button #1 →
button #2, so the walk is **#2, #1, body_text, body, title, header, backplate,
canvas**.

With the pointer over Confirm and the mouse going down:

1. **#2** — listens for hovers, unlocked, `mouse_in_node`, `mouse_is_active`, not
   yet `in_hover` → `hover_node(#2)`. That releases the previous holder first
   (`Anchor.gml:1806`), which is #1 only if the pointer was on it a moment ago —
   and #1 cannot be mid-tap, because the two do not overlap.
2. **#2 again**, same visit — `in_hover` and still inside, so `take_tap()` takes the
   LeftMouse press (`:405`); a mouse button is down this frame, so
   `tap_is_deferred = true` rather than tapping now (`:414-418`).
3. **#1** — the pointer is 20px away; nothing.
4. **body_text, body, title, header, backplate** — no listeners, no logic.
5. **canvas, LAST** — `PopupMenu`'s think runs `run_exit_listening` and then
   `INPUT.override_input(i)` for every `InputId` (`PopupMenu.gml:301-309`). Being
   last is exactly what lets the buttons above it read real input while the world
   below it reads none, and it is why `obj_ari`'s FSM — which steps after ANCHOR —
   cannot act while the popup is up.

**Release frame**: #2 is visited first again, `tap_released()` is true, the deferred
tap fires (`:436-440`) → `create_button`'s wrapper has already called `self.close()`
(`:74-79`) → `yads_tap_convert_confirm` records `_rt.convert_do`. The tick performs
the conversion at the head of the next frame.

**On a gamepad**: no hover at all. The pilot has #2 selected and the glyph think on
#2 sees `INPUT.take_press(InputId.Interact)` and calls `ANCHOR.tap_node(#2)`
directly (`Node.gml:1832-1839`) — same callback, no hover involved, and the canvas's
override still runs after it for the same registration-order reason.

### The Interact glyph does not double-fire on the frame the popup is born

The press that opened the popup was **consumed**: chest interactions register with
`take_press = true` (`par_interactable.gml:23`, `:57-60`) and `INPUT.take_press`
flips the raw status so the next read is `Off` (`Input.gml:270-272`). The glyph's
think does not run that frame anyway — `spawn()` enables the canvas after
`ANCHOR.on_begin_step` has already walked the registrar — and on the next frame the
key is *held*, not *pressed*, and `Pressed` is an edge (`Input.gml:421-430`). The
vanilla journal-save popup is built from inside `interact()` in exactly this shape
and ships with exactly this button pair.

### The Interact glyph STAYS, unlike the picker's second button

`yads_open_picker` calls `.remove_glyph()` on its Rebind button because the glyph
was wrong there: it made <kbd>E</kbd> press "Rebind key" from anywhere in the list.
Here it is the point — Interact is the button the player just pressed to raise the
popup, and Interact confirming it is the vanilla grammar for every yes/no in the
game.

### The UPGRADE changed nothing in that walk

Checked rather than assumed. It adds a third pair of strings and a third value of
`mode`; it adds no node, no button, no callback, no glyph and no geometry. The
registrar still holds canvas → backplate → header → title → body → body_text → #1
→ #2, the hover-listener count is still exactly two, and both buttons still carry
`misc_local` labels of two or three glyphs and therefore still sit at the 60px
floor with 20px of dead plate between them. A longer *body* cannot move them:
the body plate is `Align.Middle` and the buttons are `Align.BottomIn` on a
backplate that grows downward, so they stay 10px off its bottom edge whatever the
plate's height. The one thing that could reopen the overlap question is a third
`create_button` call, and the upgrade makes none.

### The mutual exclusion, and the parity claim that was false

Earlier waves claimed the two ladder arms occupied "exactly the pair of positions
`yads_convert_gesture` and `yads_downgrade_gesture` already occupy, no weaker and
no stronger". **It was weaker**, by exactly the guard that prevents a second
confirm popup:

- the ladder's `_mine == undefined` arm — the vanilla-chest arm — **returns before
  the three surface guards**, so `convert_ask` was never tested on it;
- gate 0g tested `_rt.convert`, which is the **escrow**, not `_rt.convert_ask`.
  Different objects with similar names: the escrow lives for a statement, the ask
  lives for as long as the player looks at the popup.

**The failure mode**: a press on a paired vanilla chest with our own popup up →
`yads_open_convert` spawns a second `Menu.Popup` and overwrites
`_rt.convert_ask`, orphaning the first `_ask` (so `yads_menu_closed`'s reference
compare declines to clear it) and handing `ANCHOR.get_menu` two menus of one type
— its "more than one was open" assert (`Anchor.gml:154-174`). **A crash, not item
loss**, and its sole backstop was `[popup] pause = "main"` keeping the FSM out of
`attempt_interact` — precisely the external flag the ladder's own comments say
this mod refuses to rely on.

Both holes are closed, and the claim now holds as stated. Three positions, one
invariant:

| where | test | verdict |
|---|---|---|
| ladder, `_mine == undefined` arm, above both gestures | `convert_ask` | **defer** (`undefined`) |
| ladder, past the ownership test | `view`, `picker`, `convert_ask` | swallow (`true`) |
| gate 0g, inside `yads_convert_check` | `view`, `picker`, `convert_ask`, `convert` | `YADS_CONVERT_REFUSED` |

The first one **defers rather than swallowing**, and the asymmetry is deliberate:
the other two sit past the ownership test and answer for our nodes only, while
that arm runs on every rock, door, sign, bed, crop and NPC in the game. Returning
`true` there would swallow every interaction in the world while the flag is up,
so a `convert_ask` that ever failed to clear would brick the game rather than just
this mod's menus. Deferring closes the hole exactly — the gestures below cannot
run, so no second popup can be built — and hands back a press we have no claim on.

**A fourth position, on the other surface.** `yads_remote_ready` — the arming
predicate for the remote hotkey (`docs/remote-facts.md`) — now names
`convert_ask` and the escrow alongside `view` and `picker`. Neither was
exploitable: the popup sets `PauseStatus.MENU`, so the `game_paused()` line above
already refused, and the escrow is closed by the sweeper at the tick head,
strictly above `yads_remote_press` in the same tick. But that made the guard *tick
order plus somebody else's pause flag*, and two struct reads make it a stated
invariant instead — the same reason `view` and `picker` are on that list although
`game_paused()` covers them too.

### The confirm's own frame order, and why gate 0g does not refuse it

Adding `convert_ask` to gate 0g has one way to go wrong: the executor re-gates
through the same function, so a naive addition would refuse **every** confirm the
mod has ever raised. It does not, because `yads_convert_apply` clears
`convert_ask` in the statement that consumes the request, *before* the re-gate.
That clear is load-bearing, and this is why:

**Frame C — the release frame, inside `ANCHOR.on_begin_step`:**

1. the free-requested drain (`Anchor.gml:262-271`) runs **first** and finds
   nothing: the popup is still open;
2. the node walk reaches button #2, `tap_released()` is true, the deferred tap
   fires. `create_button`'s wrapper (`PopupMenu.gml:74-79`) calls `self.close()`
   **before** the callback;
3. `close()` sets `close_requested`, locks the canvas, sets `free_requested` and
   calls `on_close()` (`AnchorMenu.gml:187-231`). **It does not free the menu**, so
   `ui.menu_closed` does not fire and `yads_menu_closed` does not run;
4. the callback runs: `yads_tap_convert_confirm` records `_rt.convert_do`.

End of frame C: request pending, **`convert_ask` still registered**.

**Frame D:**

5. `mmapi_run_installs()` is the first statement of `Game.step_begin`, ahead of
   `TICK++` and therefore ahead of `CHAINS.on_begin_step()` /
   `ANCHOR.on_begin_step()` (`Game.gml:570-582`, momi
   `seams/game_step_begin_installs.md`). So `yads_tick` → `yads_convert_apply`
   runs **while `convert_ask` is still set**;
6. the executor consumes `convert_do` and clears `convert_ask` in the same breath
   — the ask has been answered and the popup it named closed in frame C;
7. the re-gate at `yads_convert_check`, and `yads_replace_node`'s own re-check,
   both read `convert_ask == undefined` and pass;
8. later in frame D, `ANCHOR.on_begin_step`'s drain finally frees the popup and
   emits `ui.menu_closed`. `yads_menu_closed`'s reference compare finds
   `convert_ask` already `undefined`, declines, and leaks nothing.

On a **No** or an ESC there is no executor and item 8 of this frame walk (the
`yads_menu_closed` reference compare, not §11's step 8) is the only clear there is.
Either way `PAUSE_STATUS`'s `MENU` flag is removed in the same drain, and `obj_ari`
steps after `ANCHOR`, so the first frame in which the player can press interact
again already has both the guard and the pause clear — no spurious refusal.

And behind all of it, `[popup]` declares `pause = "main"`
(`ui/menus/misc_menus.toml`), so the FSM cannot reach `attempt_interact` at all
while one of these is up — which is now the backstop it was always meant to be
rather than the only thing holding the door.

### Measured strings, and one shipped number that was wrong

The body reflows at `backplate(180) − 20 − required_padding(8) = 152px`
(`PopupMenu.gml:139-147`, `Node.gml:1071-1076`), by greedy word wrap
(`ANCHOR.reflow` → `string_apply_newlines`, `Anchor.gml:1540-1546`) in
`fnt_mistria_birdseed` — `popup_description` names no `eng` font of its own
(`fiddle/ui/text_styles.toml:12-16`), so it inherits `standard` and
`fiddle/fonts/text_widths.toml` is the right table.

Re-measured in the upgrade wave against that table:

| key | glyph width | lines @152px |
|---|---|---|
| `convert_body` | 747 | **6** (the 1.3 comment said 4; it was never computed) |
| `downgrade_body` | 460 | **4** (the 1.3 comment said 3) |
| `upgrade_body` | 811 | 6 |
| `convert_title` / `downgrade_title` / `upgrade_title` | 104 / 104 / 103 | 1 each, against the 150px header interior |

Nothing was ever at risk. The plate is
`50 + (title + 4) + 8 + (lines × line_height + 12)` (`PopupMenu.gml:113-177`),
i.e. ~158px for six lines against the 240px minspec GUI canvas (`Display.gml:4`),
and `upgrade_body` lands on the same plate the widest shipped string already uses.
But a budget is only a budget if the numbers in it are real, so the corrected
counts are in the code comment too.

`prevent_spillover` only *logs* (`Node.gml:1134-1145`); it does not clip, so these
numbers are the budget, not a safety net.

Toasts are budgeted against the shipped ceiling of 367px (`remote_key_bad`); the
widest is still `convert_blocked` at 338. The five new ones: `upgrade_no_room`
346, `upgrade_no_tool` 310, `upgrade_footprint` 289, `upgrade_done` 217,
`upgrade_same` 210.

---

## Exclusions are a consequence, not a list

There is **no exclusion list in this mod**. The pair tables are built in
`yads_ids()` by stripping `netstor_crate_` off each crate row in `UNIT_KEYS` and
resolving what is left, so a chest with no twin has no entry, and every lookup
failure returns `undefined`, and `undefined` defers to vanilla. The upgrade added
no third table: `yads_twin_for_item` feeds `item.prototype.object` into `to_crate`
and `yads_shell_object` asks `to_chest` then `to_crate`, so both of its lookups
are the same two arrays and inherit the same exclusions. That covers, with one
mechanism:

- `stable_storage_chest` (no item places it), `turn_in_box` (`belongs_to_ari =
  false`) and `starter_shipping_box` (`shipping_bin = true`) — the content wave
  declined to give them twins, and that single decision is the only place the
  exclusion is written down;
- every chest another mod ships;
- factories and the AutoFeeder, which has a 54-slot inventory and no
  `interaction_chest` at all (`Furniture.gml:865-867`);
- `netstor_block`, a crate whose key carries no prefix, so it has no downgrade
  target — correct, it is the mod's own unit and not a converted chest;
- hearts and panels, which never reach the crate arm.

A **refusal** is different from a defer and swallows the press with a toast: a
chest on a table (gate 0b — a child grid never renders a node written into it), a
footprint mismatch, a capacity shortfall, and the engine's own placement test
saying no.

---

## The upgrade's ladder placement, and its defer/refusal matrix

It is the only gesture in the mod dispatched from **two** arms of
`yads_object_interact`, because it is the only one whose target may be either kind:

```
yads_object_interact
  ├─ _mine == undefined  (not one of ours)
  │     0. convert_ask guard         → DEFERS while our confirm popup is up
  │     1. yads_convert_gesture      → claims a paired VANILLA CHEST
  │     2. yads_upgrade_gesture      → claims a paired VANILLA CHEST      ← new
  ├─ instance_exists(obj_ari) · view · picker · convert_ask guards
  ├─ _mine == YADS_KIND_CRATE
  │     1. yads_downgrade_gesture    → claims a CRATE
  │     2. yads_upgrade_gesture      → claims a CRATE                     ← new
  └─ yads_scan → heart / block / panel ladder as before
```

Second in both arms, and the order is a cost question only: the two are
**mutually exclusive on the held item**. `yads_converter_slot` wants the held item
to *be* `netstor_converter`; `yads_upgrade_slot` wants it to *place* one of the 59
chests; and `netstor_converter`'s fiddle entry names no `object` at all, so it can
never resolve a twin. A press can be at most one of these gestures. The cost added
to the hot path is one extra held-slot read per *press* — human-rate, unlike the
ownership array read at the head of the function, which is why that one is inlined
and these are not.

| the world | verdict | what the player sees |
|---|---|---|
| nothing held / an animal held / held index off the end / no `obj_ari` | **defer** | vanilla behaviour, before any table read |
| held item places nothing (a hoe, a fish, a seed) | **defer** | `prototype.object` is `undefined`; `to_crate` is never indexed |
| held item places something with no twin (a bed, a table, `stable_storage_chest`'s item, another mod's chest) | **defer** | the `to_crate` read misses |
| held item is `netstor_converter` | **defer** — and the *converter* gesture already claimed it one line earlier | the 1.3 behaviour, unchanged |
| target is a rock / door / NPC / tree / crop | **defer** | `yads_shell_object` misses both tables |
| target is `netstor_block`, a heart or a panel | **defer** | `netstor_block` is a crate whose key carries no prefix, so no source; hearts and panels reach neither table |
| target is `turn_in_box` / `starter_shipping_box` / `stable_storage_chest` / another mod's chest | **defer** | no twin ⇒ no shell. The exclusion list that does not exist, again |
| target's shell object is placed by no item | **defer** | unreachable on the shipped set — all 59 sources were audited and each has **exactly one** item prototype naming it. Kept because "we cannot give the shell back" is the one condition under which this gesture must not run |
| the held chest **is** the target's shell | **refuse** `upgrade_same` | tested first, on the tables (`to_crate[shell] == target`), so it costs no scan. This is also what guarantees `source != target` for the settle rule |
| no `netstor_converter` anywhere in the backpack | **refuse** `upgrade_no_tool` | the one inventory *walk* in the mod: the tool is not what is in the hand |
| chest on a table (0b) / a surface of ours already up (0g) | **refuse** `convert_refused` | shared with the converter |
| footprint mismatch (0d) | **refuse** `upgrade_footprint` | 440 of 3,422 ordered pairs |
| capacity shortfall (0e) | **refuse** `upgrade_no_room` | the held chest has fewer slots than this unit has filled |
| a creature in the footprint (0f) | **refuse** `convert_blocked` | shared with the converter |
| everything passes | **claim** | the confirm popup, then the tick |

Two orderings inside that matrix are deliberate. `upgrade_same` goes **before**
the converter check, because it is true regardless of what is in the backpack and
because it is one table read against a full inventory walk. Both go **before**
`yads_convert_check`, which mirrors the converter gestures' own shape — "do I have
the tool" precedes "is this legal" throughout §6c — at the cost of telling a
player standing at a chest on a table that they need a converter, which is true
but not the whole story.

## Consumption order, as shipped

The world change first, then the two costs, each **re-resolved at the instant it
is spent**:

```gml
if (!yads_replace_node(_node, _request.target, _swap)) { return; }

//   1. the held chest, whose shell is now standing on the footprint
//   2. the converter, LAST
if (_up) {
    var _chest = yads_upgrade_slot(_request.target);
    if (_chest != undefined) { _chest.remove(1); }
}
var _spend = _up ? yads_converter_stock() : yads_converter_slot();
if (_spend != undefined) { _spend.remove(1); }
```

**A throw between the two costs the MOD a freebie and never the player an item**:
the swap has happened, the old shell is already back in their hands, and they keep
a converter they should have spent — or, one statement earlier, keep the chest as
well. Reversing the pair would let a throw eat the tool while the chest it was
meant to spend is still in hand, which is the consume-first mistake §6c's header
rejects for the plain conversion.

One accepted wart: the shell is handed over inside `yads_replace_node` (step 7b),
*before* the held chest is removed. With a completely full backpack that means the
shell lands at the player's feet rather than in the slot the held chest is about to
vacate. Fixing it would mean consuming before the world change is finished, which
the doctrine forbids; a stack on the ground is the engine's own fallback and the
player walks over it.

## Freeze

`netstor_converter` is frozen the moment it ships, like every other `netstor_*`
key: item keys are save-serialized by name and a rename deletes every converter in
every backpack. It is a weaker freeze than `netstor_remote`'s — nothing is *bound*
to a converter and none is ever stored in a node — but it is a freeze.
