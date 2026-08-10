# Version history — shipped and superseded

Split from `CLAUDE.md` (size rule). Current status lives there; this file is
the record of what each earlier version was and what its audit found. Engine
facts discovered along the way live in `CLAUDE.md` § Engine facts.

Everything below predates the Beta 1.0 rebrand and is written in the old
identifiers (`prajaja_digital_storage_*`, `global.__netstor`, the
`DigitalStorage*.gml` filenames). They are now `yads_*`, `global.__yads` and
`gml/boot.gml` / `gml/network.gml` / `gml/view.gml`. The `netstor_*` CONTENT
keys did not move and never will.

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
