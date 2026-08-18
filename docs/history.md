# Version history — shipped and superseded

Split from `CLAUDE.md` (size rule). Current status lives there; this file is
the record of what each earlier version was and what its audit found. Engine
facts discovered along the way live in `CLAUDE.md` § Engine facts.

Everything below predates the Beta 1.0 rebrand and is written in the old
identifiers (`prajaja_digital_storage_*`, `global.__netstor`, the
`DigitalStorage*.gml` filenames). They are now `yads_*`, `global.__yads` and
`gml/boot.gml` / `gml/network.gml` / `gml/view.gml`. The `netstor_*` CONTENT
keys did not move and never will.

## Beta 1.3 wave 4 — the upgrade gesture (current; here for the blast radius only)

The feature itself is in `CLAUDE.md` § Status and `docs/converter-facts.md`. What belongs
in the record is the surface it touched: **7 functions added, 14 code-changed, 161 of the
175 pre-existing token-identical, 0 removed**, and all nine §8 functions token-identical
(`yads_reconcile`, `yads_updates_sum`, `yads_view_totals`, `yads_withdraw`,
`yads_mirror_remove`, `yads_deposit`, `yads_quick_stack`, `yads_deposit_fit`,
`yads_flush_hand`). No art: `tools/regen_gate.py` still reports 175 files byte-identical.
Two shipped facts were corrected in passing — `convert_body` is six reflowed lines, not the
four the 1.3 comment claimed, and `downgrade_body` four, not three — and gate 0d's verdict
was split out as `YADS_CONVERT_FOOTPRINT`, which convert and downgrade fold straight back
onto `convert_refused` because neither can produce it.

## Beta 1.3 waves 1-2 — the kind table and the classifier fix (shipped, superseded as status)

- **The ObjectId-indexed kind table** (`CLAUDE.md` § Standing constraints) replaced all 16
  id-comparison sites, so adding the 59 `netstor_crate_*` twins was an append to `UNIT_KEYS`
  and nothing else; an unresolved key is silently skipped, which is what lets the list name a
  key before the fiddle ships it. `ITEM_KEYS` (boot.gml §4) is a SEPARATE seam — items with a
  RECIPE — and the recipe-less twins never go in it. `OFFLINE_SLUGS` folded into the memo as
  `offline[object_id]`: three `try_string_to_asset` calls per glow rescan would have been 62 a
  second at scale. No behaviour change on the then-current four keys, proved per site over all
  8 install states; §8 was token-identical.
- **`yads_category`'s ladder let PROVENANCE tags outrank IDENTITY**, in four arms plus two
  found afterwards: `fishable`, `gem`, the `furniture` tag over the never-reachable bucket 11,
  `mushroom` and the derived `use == Consume` all describe where a thing came from or what you
  can do to it, and a `material`/`refined_material`/`food`/`archaeology` identity (`_strong`)
  now beats them — except at bucket 7, where every ore carries `material` and the guard would
  empty it. 227 items reclassified (221 + 6), 0 residual, no save impact; evidence per arm
  below.

## The sort-bucket classifier fix — full evidence (shipped IN Beta 1.3)

Not superseded; this is the working detail behind `CLAUDE.md`'s one-paragraph
summary, parked here for the size rule. There was no separate 1.2.1 release —
the four-arm fix and the two-arm follow-up ship together in Beta 1.3.

**The bug class, stated once.** `yads_category` (network.gml §4) is an ordered
first-match-wins ladder over `prototype.tags` plus the derived `prototype.use`.
Several arms tested a tag that describes where an item CAME FROM, or what you
can do to it, above the tag that says what it IS. Vanilla never has to choose —
`AlmanacMenu.gml:16` is `contains_any_value_from`, i.e. membership, and
`sub_menus.toml:21-34` cheerfully lists `basic_wood` under both the Fishing lens
and the Materials lens. A 14-bucket sort IS a partition, so it must choose.

The discriminator is one local, `_strong` = `material` / `refined_material` /
`food` / `archaeology` — vanilla's own almanac lenses for identity — and it now
gates three arms. It must NEVER gate bucket 7: every ore carries `material`, so
`!_strong` would empty it.

| arm | was | now | items | why the old signal was not identity |
|---|---|---|---|---|
| 4 Fish and bugs | `fishy\|fishable\|bugs` | `!_strong && (…\|dive)` | 2 + 27 + 2 + 1 | `fishable` has ONE engine reader, `Items.gml:317-331`, and it only picks a catch-sprite icon variant. Wood, Fiber and cooked seafood carry it. `dive` added because vanilla's own fish lens is `["fishable","dive"]` (`sub_menus.toml:28`), rescuing `pond_snail`/`river_snail`. |
| 7 Ores, gems, ingots | `gem` | `gem && !wood` | 1 | `gem` has zero engine readers; `hard_wood` (`materials.toml:16-27`) is the only item with a bogus one, and `wood` is the two-item discriminator vanilla hands us. |
| 11 before 10 | 10 first | 11 first | 107 | every `wallpaper`/`flooring`/`tile_placement` item ALSO carries the `furniture` tag (`basic_wallpaper_oak` = `["furniture","wallpaper","basic_set"]`), so bucket 10 swallowed all of them and bucket 11 shipped holding **0 of 2665 items** in every release. Reordering assigns the same literal bucket numbers, so it renumbers nothing. |
| 10 Furniture | `furniture` tag | `… \|\| use == PlaceObject` | 81 | `Items.gml:205-213` ASSERTS that an item with an `object` field places a node whose `ObjectCategory` IS Furniture — strictly stronger than the tag. Spouse furniture, 10-heart gifts, date photos, pet beds and the crafting stations carry no `furniture` tag. |
| 3 Crops and forage | `mushroom` | `mushroom && !_strong` | 4 | `mushroom` has zero engine readers as an item tag (the `pets.toml` hits are a `PetKind` fed through `string_to_pet_kind`, `PetPrototypes.gml:25`) and no almanac lens. `glowing_mushroom`, `purple_mushroom`, `red_toadstool`, `wild_mushroom` are Mushroom-monster drops (`monsters/shroom.toml:75/118/172/216`) tagged `["material","mushroom","mushroomy"]` and never `forageable`. |
| 6 Food and drink | `… \|\| use == Consume` | `… \|\| (Consume && !_strong)` | 2 | `Items.gml:135-136` infers `edible` from a bare `restore`, so the arm catches anything chewable. `chocolate` (`["pantry","choco","material"]`, restore 10) and `ice_block` (`["material"]`, restore 6) are cooking ingredients; chocolate's seven `pantry`+`material` siblings (curry_powder, honey ×4, rock_salt, soy_sauce) were already in Materials. |

**Deliberately NOT gated.** `crop` and `forageable` are almanac lenses in their
own right, with two and four engine readers, so they outrank `material` on
purpose: the four material-tagged shells (`blue_conch_shell`,
`pink_scallop_shell`, `sand_dollar`, `spirula_shell`) and the five real forage
mushrooms (`earthshroom`, `morel_mushroom`, `oyster_mushroom`, `pineshroom`,
`spirit_mushroom`) stay in bucket 3. The `food`/`drink` TAGS at bucket 6 are not
gated either — only the derived `Consume` is.

**Known and accepted, not fixed.** 105 `artifact_replica_*` in bucket 9 (the
mod's deliberate taxonomy); 10 `perfect_*` ores in bucket 7; `fossilized_egg`;
`humble_pie` (tags `[]`, a vanilla joke item); `netstor_remote` sorting into
Materials. **Genuinely ambiguous, left alone:** `hay` and `grass_seed` carry
`refined_material` + `animal_feed` + `ranching` and land in bucket 5 via
`ranching`, even though bucket 8 lists `animal_feed`. `ranching` IS an almanac
lens, so both readings are defensible; moving them was out of scope and would
have been a change nobody asked for.

**Verification.** `C:/Claude/.scratch/b13recon/classify.py` replays the ladder
over all 2665 vanilla items in three rulesets: `diff` (pre-fix → four-arm fix)
prints 221 in exactly seven transitions, `diff13` (four-arm → six-arm) prints
the 6 above and nothing else, `diffall` prints 227 — the sets are disjoint.
Bucket populations move only 3 (−4), 6 (−2) and 8 (+6). **Zero save or config
impact**: bucket numbers are not persisted anywhere, `_view.filter` is
view-local, and the `_rt.categories` memo already dies on `save.game_loaded`.

## Status — Beta 1.2 (historical; remote access)

Shipped 2026-08-13. `netstor_remote`, a craftable non-placeable. Hand one to a
Storage Heart and your remote key (default F6, rebound in game) opens it from
anywhere; withdrawing it at a PANEL unbinds. HOLDING the key ALWAYS opens the
picker, the only route to rebind.

- **The binding is CONTAINMENT.** "Linked" means a `netstor_remote` sits in that
  heart's `Inventory`, which the engine already saves inside the chest it lives
  in. No modsave sidecar: nothing to version, repair, or disagree with the world.
- **Scan `STORAGE_NODES`, NEVER `GRIDS[]`** — `GRIDS` is keyed by location and the
  dynamic grids (greenhouses, mini-museum, tables) are not in it. `yads_remote_scan`
  walks it once and returns every bound heart, current location first.
- **THE HOTKEY, PICKER AND REBIND HAVE THEIR OWN FACTS FILE** — `docs/remote-facts.md`.
  Read it before touching `yads_remote_*`, `yads_picker_*`, `yads_rebind_*` or the
  hotkey block of the tick. It is the authored document for the gesture ladder, the
  arming predicate, the default's identity, the picker surface and the rebind, so
  nothing here restates them. The two that bite hardest: the poll is RAW and lands
  in OUR frame, so all of it is gated by `yads_remote_ready`; and chords and pad
  binds are absent from the 0.15.1 payload, which only momi can see.
- **THE KEY REBINDS IN GAME, LIVE** — picker footer, §5d + §7f. mmapi's poll
  re-reads `entry.vk` every frame, so we hold our registry entry (pre/post length
  test: register can early-return WITHOUT pushing) and move it with `_rt.remote_vk`
  in lockstep. **`entry.dead` is PERMANENT and nothing clears it** — only ever
  assign a vk that resolved through `mmapi_hotkey_vk_from_name` AND was just polled
  by `keyboard_check_pressed`; a missing or dead entry gets a FRESH registration,
  never a mutation. Capture `lock()`s the menu, which gates the rows, Close AND
  `run_exit_listening` and so leaves ESC ours to read as cancel, in the THINK and
  never in `yads_tick`. **F6-hold is a permanent hold-only rescue** whenever the
  active key is not F6; an unparseable config name takes F6 with the FULL ladder.
- **H1/H2/H3, the custody exclusions.** `yads_quick_stack` skips backpack remotes (a
  SANCTIONED H1 exclusion: a bare `continue`, provably inert) and `yads_deposit_fit` refuses
  them outright: a remote in a Storage Block is a binding nothing can read. Refusal
  returns 0, so the reconciler's EXISTING overflow path strips and refunds it. A heart's own
  remote stays VISIBLE in the aggregate — never hide member items — but a REMOTE view makes
  that cell INERT (H3): `filter_callback` gates `input_check`, killing pickup and swap alike.
- **`_rt.view` registers right after the menu spawn; `_rt.picker` after `spawn()`.**
  Deliberate (`docs/remote-facts.md`); `ui.menu_closed` releases both, picker first.
- **A remote view skips the chest lid** (`node.renderer` is never cleared, ids are
  recycled, `instance_is_alive` can answer true about a stranger). Residuals: the
  remote sorts into Materials; a withdrawn remote put straight back is refused and
  refunded, still unbound; the picker caps at 8 rows, unnamed rooms "Network N".

## Status — Beta 1.1 (historical; three UI additions)

Shipped 2026-08-11. The two standing rules it established (never bump
`YADS_CONFIG_VERSION` for an added key; a persisted enum's integers ARE the save
format) were promoted into `CLAUDE.md` § Standing constraints and are still
binding. The three additions:

- **Clear-X in the search box.** It works because `yads_search_think` closes the
  plate's `listen_for_hovers` gate while the pointer is over it, NOT because it
  is registered last (the shipped-dead first cut's belief; the mechanism is now
  written up in `docs/anchor-ui-facts.md`). Hitbox trimmed via
  `set_bbox_offset`; the blur test names plate AND button. Full argument at
  `view.gml`'s clear-button block.
- **Ctrl+arrow word-jump** and Ctrl+Backspace/Delete word-delete, the latter as
  "stretch `sel_anchor` to the boundary, then call `yads_edit_delete` unchanged".
  The `yads_edit_repeat` gate stays OUTSIDE the modifier test: it carries
  `repeat_key` across frames, so a skipped call loses the release edge.
- **Sort mode persists** (`config.sort_mode`), seeded into the view struct and
  written through by `yads_tap_sort` — which writes `sort_request`, not
  `sort_mode`, because the tick has not applied it yet. The button's build-time
  label had to move to `yads_sort_key(...)` too, or frame one lies.

## Status — Beta 1.0 (historical; the first public release)

Shipped 2026-08-10. The standing constraints it established (folder name, frozen
`netstor_*` keys, squeeze-between collision, the `check_pick` revert) live in
`CLAUDE.md`; what follows is the one-time work.

**The rebrand.** `mod/` → `yads/`, `prajaja_digital_storage_` → `yads_`,
`PRAJAJA_DIGITAL_STORAGE_` → `YADS_`, `global.__netstor` → `global.__yads`, GML
files → `boot.gml` / `network.gml` / `view.gml`. Manifest: name "YADS - Yet
Another Digital Storage Mod", author "mykay". The rename was mechanical and
proven so (sed-reconstruct from the pre-rename files diffed byte-identical).

- **Three-way loc namespace move**, atomic: `fiddle/mods/digital_storage/` →
  `fiddle/mods/yads/`, the `l10n.meta.toml` key, and the `YADS_LOCAL_ROOT` macro.
- **`mmapi_mod_declare` token** `"digital_storage"` → `"yads"`, which moves the
  config + log dir to `mod_data/yads/`. The owner's two persisted toggles
  (auto_search, value_mode) reset to defaults once. MOMI also treats the new mod
  id as a new mod, so updaters must re-tick YADS in the installer list.

**The pastel palette, and what it costs.** Value badges `.set_xy(1, -2)`; glow
greens/reds/yellows softened to pastel (image_blend is a multiply over near-white
art, so a zeroed channel reads neon). **Accepted tradeoff, recorded once so it is
not rediscovered as a bug:** the pastels cost colour-blind separation. Under a
Viénot deuteranopia simulation the bright-rung green/yellow pair goes from
Euclidean 65 (saturated) to 41 (pastel) — about **37% worse** — and red's
relative luminance rises 54 → 157, halving the red-vs-yellow luminance gap
(182 → 88). Protanopia is marginally better. Green/yellow were already ambiguous
for red-green colour-blindness, so this is a regression on the traffic-light
metaphor, not a new failure. The aesthetics are owner-requested and stand; the
escape hatch if reports come in is a non-colour cue (a fill-level pip, or pushing
"empty" toward blue), not a return to primaries. Green-vs-cyan for normal vision
also halves (230 → 120 at the bright rung), mitigated by the three units having
distinct silhouettes.

**Repo pass.** Process-archaeology comments deleted or rewritten as constraints
(strip-comments diff proves zero code tokens changed); `DESIGN.md` → `docs/`;
`README-FIRST-LAUNCH.md` folded into the public `README.md`; `check_symbols.py`
and `make_art.py` de-personalised (argv/env, no hard-coded user paths).

## Status — Alpha 1.5 (historical; the last pre-public build)

Shipped 2026-08-10, gates green, audit dry. What it added over 1.4:

- **Pickaxe-swing protection.** A unit that still holds items takes five swings
  to remove; an empty one keeps vanilla's single swing. Implemented as a
  `resource.node_modifier` filter at the head of `pick_node` (§10 of the network
  file). The filter never filters — every path returns `undefined`; the work is
  a side effect on the node that the seam's position makes visible to the very
  swing that triggered it. Counted at most once per `TICK`, so a charged
  multi-cell swing (or a bomb blast, which fires one `pick_node` per cell) is one
  attempt, not six. It rests on the three facts in `docs/safety-invariants.md`.
- **Value badges grown up**: abbreviated (`12.3k`) with the game's own tesserae
  coin beside them, on the mod's own sprite font (`netstor_count` — boot-coupled,
  see the safety doc).
- **A fifth sort mode**, stack value (`SORT_LEN` is 5).
- **A dedicated "Digital Storage" Woodcrafting sub-category** appended to vanilla
  "Functional", plus a **one-key Japanese override** — the vanilla jpn table
  carries a dead `sub_categories/5/name` = 「その他」 at exactly the index our
  append lands on, the only such stale index in the shipped localization.
- Layout: pager cluster shrank 92→72 and moved RightIn to clear the glyph
  guide's ESC backplate (80px in Russian); value toggle moved bottom-**right**.
- Recipes moved to **Copper Ingot** (Forge-gated), not Copper Ore.

**Pre-publish audit for 1.5: DRY.** Two waves, four adversarial Opus reviewers.
Wave 1 found 3 MAJOR — a resting `destructable=false`, a charged swing spending
the whole five-swing budget in one hit, and the non-mouse aim path skipping a
suppressed unit — all fixed via the redesign in the safety doc; **wave 2 came
back 0 CRITICAL / 0 MAJOR** across both surfaces, with 16 MINORs, all applied.
**0 CRITICAL has ever been constructed against this mod, across every wave of
every version.** Wave 2 also diffed the shipped GML against the in-engine-proven
Alpha 1.4 build: six hunks in the network file, **not one of them anywhere
inside** `reconcile` / `updates_sum` / `withdraw` / `deposit` / `quick_stack` /
`flush_hand`. The custody path did not move in 1.5.

## Status — Alpha 1.4 (historical)

**Alpha 1.4** (2026-08-09, from the user's second play session + screenshot):
real line editor in the search box (caret/selection/clipboard via the
takes_input flip trick — engine focus kept, append-driver dropped), 16
rotating category filters incl. live "Museum needs" predicate, per-stack
tesserae value badges (bin_value, off/stack/unit persisted cycle), tri-state
block glow (green empty / yellow in use / red full via image_blend over
near-white regenerated strips; heart/panel cyan; sad face blend-white),
bottom shelf, magnifier toggle icon, ingot recipes, message-only panel-less
heart (owner decision; Throw-fed heart items wait for a panel — documented
residual). Wave-4 audit: 0 CRITICAL, 0 MAJOR; 10 MINORs fixed or documented.

## Status — Alpha 1.3 (historical)

**Alpha 1.3** (2026-08-07, third same-day iteration): auto-focus search +
persisted toggle (mmapi_config, KBM-and-not-Deck gated), search strip above
the plate, centered pager, filter-button hover tooltips, scrolling status
popup past 8 blocks, glow slowed to 1.6s, **sad-face overlay on disconnected
units** (top renderer sprite-swap), panel-less networks fully stand down to
vanilla chests (bidirectional anti-strand). Version string is free-text
("Alpha 1.3") — only minInstallerVersion is parsed. NexusMods page:
`nexus_page.bbcode` (branded YADS; internal mod id unchanged on purpose —
renaming it would force all function prefixes to change).

**Pre-publish audit: DRY.** Three waves, 12 adversarial Opus reviewers,
~5.5M audit tokens: 0 CRITICAL ever constructed; every MAJOR/MINOR fixed
same-day and re-audited by fresh eyes; wave 3 = 0 CRITICAL, 0 MAJOR, and a
per-outcome proof of the reconciler's resting invariant (stated in
`gml/network.gml` §8: shadow ≤ members, unconditionally). Audit
reports: the w1_*/W2-*/W3-* files in the session task dirs (copied nowhere —
regenerate by re-auditing if needed). Gates green.

## Status (v1.2, historical)

**v1.2.0** (2026-08-07, second same-day iteration from live play feedback).
v1.1 confirmed in-engine; v1.2 rework: **Panel browses / Heart reports /
connected Blocks sealed** (heartless units stay vanilla chests — anti-strand
rule). Deposits target BLOCKS ONLY (`_scan.deposit_targets`). Heart keeps its
54-slot container — **never shrink a shipped inventory_size**: the engine
force-resizes loaded chest inventories to the current prototype and destroys
trailing slots (Grid.gml:1137-1154; V12-C proved it against the live save).
Landing row hidden under an AboveFader plate carrying 8 category filter
buttons (lock()ed slots stay live as the ESC-drop net). Crate/monolith/
terminal art + animated cyan glow overlay on connected units (top_sprite +
obj_node_renderer_top.visible; union-find connectivity cache invalidated by
furniture.place_guard + STORAGE_NODES.count() delta + room/load + 60f TTL).
Status popup via popup_creator (V12-B recipe). Known vanilla side-door: the
Throw input deposits into any unit's real inventory, hookless (V12-C §3c).
Research now includes V12-A/B/C. Gates green (checker + momi --lint
--strict-lints --compile-check require). First-run watch list (all three
cleared by the user's v1.2 play session): AboveFader plate rendering,
glow-on-scroll-in staleness, status popup pixel layout.
