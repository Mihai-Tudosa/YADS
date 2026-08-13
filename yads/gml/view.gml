// YADS - the network view and the heart's status popup: the menus, their extra
// widgets, and teardown.
//
// Definitions only. Nothing in this file executes at boot.
//
// The network view has exactly ONE door: the Access Panel. The heart opens the
// read-only status popup in section 6 instead, and a block on a live network
// opens nothing at all. See the interaction rationale in boot.gml section 6.
//
// The menu is a plain vanilla Menu.Storage. A mod cannot mint a new Menu enum
// value - ANCHOR.spawn_menu is a hard-coded switch with `default: impossible(...)`
// and no seam covers it - so we reuse Storage and dress it after build(), the way
// the museum donation basket does (MuseumDonationMenu.gml:16-58).
//
// The builder chain below is byte-for-byte the lost-and-found shape
// (obj_lost_and_found.gml:32-38). with_pull_button(false) is MANDATORY, not
// cosmetic: include_pull_button defaults to TRUE (StorageMenu.gml:277), and with
// node == undefined the pull button asserts and then null-derefs
// self.node.use_in_crafting inside StorageBanner.build.
//
// Every widget callback here only RECORDS a request. The tick applies it. That
// keeps a single writer on the mirror inventory and keeps UI input one frame
// behind the reconciler, which is what makes the delta window exactly one action.

//
// 1. OPEN
//
// _remote is true for every hotkey open and false for every Access Panel open.
//
// ONE FLAG, ONE RULE, AND IT IS NOT "IS THE HEART IN THIS ROOM". A same-room
// hotkey open has no interact context either - nobody pressed a button on a
// crate, nobody is standing in front of one - so making the flag depend on
// distance would buy one lid animation and cost a second code path that only
// misbehaves in the rare case. Everything the flag turns off is either
// cosmetic (the chest lid) or an optimisation (a glow invalidation), so
// "hotkey ⇒ remote" is the whole rule.
//
// WHAT IT TURNS OFF, and nothing else:
//
//   THE LID. yads_open_chest/yads_close_chest write sprite_index and
//   image_speed onto node.renderer. A node in another location HAS no live
//   renderer - Grid.gml:208-212 builds them for the current location only -
//   but node.renderer is never cleared when the instances die, so the field
//   holds a stale instance id from the last time that room was loaded. Instance
//   ids are recycled, so instance_is_alive can answer TRUE about an id that now
//   belongs to something else entirely, and the write lands on a stranger. That
//   is the whole hazard: not a missing animation, a write into another object.
//
//   THE TEARDOWN GLOW INVALIDATION. Section 9's rescan is already filtered to
//   the current location, so a remote session cannot have staled anything it
//   would rebuild - and the reconciler still invalidates on its own whenever
//   items actually moved, which covers the fill tier of a block in this room if
//   the network happens to be here. Skipping it is not a correctness change,
//   it is declining to schedule a ~15k-op rescan that has nothing to look at.
//
// Everything else runs completely unchanged, and that is a property of the
// design rather than a coincidence: the scan, the index, the projection and the
// reconciler read node.inventory and parent_grid and never once ask what
// location they are in.
function yads_open_view(_node, _scan, _remote = false) {
    var _rt = yads_runtime();

    // THE FILE READ GOES FIRST, before a menu exists and before anything is
    // registered anywhere. mmapi_config_read_valid does real synchronous IO -
    // directory_exists, file_exists, a JSON parse, and on a first read a write
    // (mmapi.gml:452-463) - which makes it the newest and by far the most
    // failure-prone thing this function touches. Run here, a throw costs nothing:
    // no menu was spawned, no view was registered, the override returns undefined
    // and the engine opens its own chest UI on the panel. Run anywhere below, it
    // would abort a half-built menu instead.
    //
    // In the steady state this is a struct read; the tick warms the memo on its
    // first safe frame. This ordering is for the frame where it is not.
    var _config = yads_config();

    var _view = {
        node: _node,                 // the panel we were opened from
        remote: _remote,             // opened by hotkey: no lid, no glow work
        members: _scan.members,      // every chest node in the network
        // Blocks only. Read by has_room, deposit and deposit_fit; the three must
        // always agree about where an item is allowed to land or the trailing
        // slots advertise room that a deposit then bounces off.
        deposit_targets: _scan.deposit_targets,
        inv: Inventory(YADS_VIEW_SIZE),
        menu: undefined,

        rows: [],                    // aggregate index
        names: {},                   // agg key -> display name, memoized
        shadow: {},                  // agg key -> { item, count } as last projected
        has_room: true,              // does any BLOCK have an empty slot

        index_dirty: true,
        project_dirty: true,
        closing: false,
        torn_down: false,

        page: 0,
        pages: 1,
        page_request: undefined,
        // Seeded from the file, not from the macro: the sort order is persisted
        // (yads_tap_sort writes it through), so the panel opens the way the
        // player last left it. _config is the memo read at the top of this
        // function and is already range-guarded by yads_config.
        sort_mode: _config.sort_mode,
        sort_request: undefined,
        filter: YADS_FILTER_ALL,
        filter_request: undefined,
        // Which eight of the sixteen filter groups the bar is currently showing.
        // Purely presentational - the APPLIED filter is `filter` above and does
        // not move when the page does, so a player can select "Fish & Bugs" on
        // page 1, flip to page 2, and the grid keeps showing fish.
        cat_page: 0,
        cat_page_request: undefined,
        query: "",

        // Reconciler fast-path baseline: sum of every mirror slot's `updates`
        // counter as of the last projection/reconcile. undefined forces the
        // first tick to run one full diff and set it.
        updates_sum: undefined,

        page_text: undefined,
        sort_button: undefined,
        search_plate: undefined,
        search_node: undefined,
        search_hint: undefined,
        search_clear: undefined,        // the X inside the box, shown only when it has text
        filter_plate: undefined,
        filter_buttons: [],
        filter_icons: [],               // the icon sprite inside each button
        filter_prev: undefined,         // the bar's two page arrows
        filter_next: undefined,

        // The search box's line editor. Every one of these is OURS - the only
        // engine field the editor writes is the raw takes_input flag, and it
        // writes it exactly once per focus change (see search_focus).
        //
        // `editing` REPLACES every read of search_node.takes_input as "is the box
        // focused", because after the hand-flip that field is false while we are
        // typing. Missing one of those reads is not cosmetic: view_closing and
        // teardown both gate their blur on it, and a skipped blur leaves
        // ANCHOR.text_input_node pointing at a node that is about to be freed and
        // the OS text-input session open.
        editing: false,
        caret: 0,                       // characters BEFORE the caret, 0..len
        sel_anchor: 0,                  // selection is [min, max) with `caret`
        blink: 0,                       // our own counter, the engine's is dead
        repeat_key: undefined,          // which key currently owns auto-repeat
        repeat_timer: 0,
        caret_node: undefined,          // 1px rect, positioned by measurement
        sel_node: undefined,            // stretched rect behind the selection
        search_max_width: 0,            // the budget we re-implement ourselves

        // The value badges and the shelf toggle that drives them.
        value_badges: [],               // one TextNode per PAGE cell (45)
        value_coins: [],                // the tesserae glyph beside each
        value_button: undefined,
        value_icon: undefined,
        value_hint_plate: undefined,
        value_hint_label: undefined,

        autosearch_button: undefined,       // the toggle beside the search box
        autosearch_icon: undefined,         // its checkbox sprite, swapped by its own think
        autosearch_hint_plate: undefined,   // the toggle's OWN tooltip backplate
        autosearch_hint_label: undefined,   // and its TextNode
        hint_plate: undefined,          // the FILTER BAR's tooltip backplate, hidden by default
        hint_label: undefined,          // the one TextNode the FILTER buttons write into
    };

    // Play the chest opening exactly like the engine's own chest branch does
    // (Interact.gml:768-771). We claimed the interaction, so this is ours to do
    // - unless nobody interacted with anything, in which case see the remote
    // note over this function.
    if (!_remote) { yads_open_chest(_node); }

    var _menu = ANCHOR.spawn_menu(Menu.Storage)
        .set_inventories(_view.inv, ARI.inventory)
        .with_pull_button(false)   // MANDATORY: node is undefined
        .with_left_banner()        // sort + trash over the network side
        .with_right_banner()       // stack + sort over the backpack
        .build();

    // ui.menu_closed reports kind == Menu.Storage for every vanilla chest too, so
    // stamp the instance. Dynamic fields on menu structs are normal - the engine
    // reads `e[$ "is_tooltip"]` off them (Anchor.gml:178).
    //
    // The stamp stays HERE, at the moment the menu is born: it is how the close
    // path recognises our instance, and a menu that exists must be recognisable
    // from the first frame it exists. The registration below depends on it.
    _menu.netstor_view = _view;
    _view.menu = _menu;

    // REGISTERED HERE, AND THE POSITION IS THE WHOLE OF THE ARGUMENT: the first
    // statement after the menu exists and the view struct is whole, and BEFORE
    // any decoration (widgets, badges, the first projection, refresh, focus).
    //
    // WHAT REGISTRATION MEANS. _rt.view is what attaches the reconciler. Three
    // consumers gate on it and all three return early while it is unset:
    // yads_tick (boot.gml:723-724), yads_menu_closed (boot.gml:2148) and
    // the game_saving hook (boot.gml:2181). So a LIVE Storage menu with
    // _rt.view unset is a menu whose left pane holds real, withdrawable member
    // items and which nothing reconciles: `pair.add(slot.item, n)` credits the
    // backpack and the member chest is never debited. That is silent
    // duplication, and it is what registering last used to risk for every line
    // between the spawn and the end of this function.
    //
    // PER-FIELD VALIDITY, the three consumers' FIRST post-registration run,
    // walked field by field against the struct literal above:
    //
    //   tick :569  _view.menu            - set on the line above, so the
    //                                      defensive teardown branch is skipped.
    //   tick :576  yads_reconcile reads inv (:84), updates_sum (:119) and
    //              shadow (:89). updates_sum is undefined until a projection
    //              closes its books, and the never-projected guard at the head
    //              of yads_reconcile re-baselines and returns false on exactly
    //              that state - covering BOTH the ordinary empty mirror and
    //              the partial mirror a mid-projection throw leaves behind
    //              (which, diffed against an empty shadow, would have minted
    //              the whole visible page into the blocks - B12w2 MAJOR-1).
    //              members (:79), deposit_targets (:83) and torn_down (:95)
    //              are all valid from the literal regardless.
    //   tick :582  closing (:94) = false.
    //   tick :585-646  page_request/page, sort_request/sort_mode,
    //              filter_request/filter, cat_page_request/cat_page - all from
    //              the literal (:97-113). Every _request is undefined, so each
    //              branch is skipped and neither yads_apply_sort_label nor
    //              yads_refresh_filter_bar is reached; both are widget-guarded
    //              in any case (:3092-3097, :1781-1783).
    //   tick :652  search_node (:124) = undefined - branch guarded, skipped.
    //   tick :662  project_dirty (:93) = true, so yads_project DOES run on that
    //              first tick. It reads index_dirty (:92) -> index_build over
    //              members, rows (:87), query (:114), filter (:106), sort_mode
    //              (:104), pages/page (:97-98), inv (:84), menu (:85, set), has_room
    //              (:90), value_badges (:154 = [], so yads_badge_slot returns at
    //              its length test, :1648) and page_text (:121 = undefined,
    //              guarded at network.gml:642). The squares read off the menu is
    //              itself [$ ]-guarded (network.gml:604-606).
    //   menu_closed  _ctx.menu, then _menu[$ "netstor_view"] == _rt.view. The
    //              stamp is written one line above this one, so the identity
    //              test holds from the first frame the menu exists. teardown
    //              then reads torn_down (:95), closing (:94), editing (:143 =
    //              false, so the blur is skipped), reconcile (above),
    //              flush_hand (menu -> left_menu, [$ ]-guarded at
    //              network.gml:1287-1291), remote (:78), node (:77), and nulls a
    //              list every name of which exists in the literal.
    //   game_saving  view, reconcile, flush_hand, closing, then project or
    //              view_totals - all covered above.
    //
    // Every field the three consumers touch is initialised in the struct literal
    // at :76-167. The single exception is `menu`, and this line sits behind it.
    //
    // THROW BEFORE THIS LINE: menu absent, view absent. yads_config, the literal,
    // yads_open_chest and the spawn chain are all above. The interact path's
    // throw is swallowed by mmapi_run_override and the engine's own interact()
    // opens its vanilla chest UI on the panel; the remote path's is swallowed by
    // mmapi's per-installer catch (mmapi.gml:75-84) and nothing appears. Neither
    // leaves a mirror, so there is nothing to duplicate. Unchanged from 1.1.
    //
    // THROW AFTER THIS LINE: menu present, view present, reconciler attached.
    // Every withdrawal from that menu is debited from the member chests on the
    // very next tick. The duplication window is closed by the PAIR of this
    // registration and yads_reconcile's never-projected guard: registration
    // alone would let a mid-projection throw hand the reconciler a partial
    // mirror over an empty shadow, which reads as a page of fresh deposits.
    // The menu is an ordinary Menu.Storage, so Escape closes it, ui.menu_closed
    // fires carrying our stamp, and yads_teardown releases _rt.view early (after
    // its undefined guard and torn_down latch, :3210-3212, :3231-3232).
    // The lock-out the old ordering feared - a registered view nobody can clear,
    // with object_interact swallowing every press until a reload - CANNOT happen
    // from here, and for the reason that decides the whole placement: a menu
    // exists to be closed. A half-decorated menu is cosmetically wrong and
    // custody-correct; registering last had it exactly backwards.
    //
    // NEVER ABOVE THE TWO LINES ABOVE. With _view.menu still undefined the next
    // tick takes the defensive branch at boot.gml:726-730 and tears the view down
    // under a menu the spawn was still building; and a throw inside the spawn
    // chain would leave teardown reading a `menu` field that never existed. Both
    // are avoided by taking the stamp and the assignment first - two plain writes
    // to an already-allocated struct, neither of which can throw.
    _rt.view = _view;

    // Replace on_close the sanctioned way (Factories.gml:129-131). The vanilla
    // body is a no-op with node == undefined anyway, and we need the chest to
    // shut and the last action to be written through before the fade starts.
    _menu.on_close = method(_menu, function() {
        yads_view_closing(self);
    });

    yads_build_widgets(_view);

    // Before the first projection, because the projection is what fills them:
    // yads_badge_slot is called from project's own slot loop
    // and no-ops harmlessly if the array is not there yet, but building first
    // means the numbers are right on frame one instead of one projection late.
    yads_build_badges(_view, _menu);

    yads_project(_view);

    // AND ENABLE THE SLOTS THIS FRAME, or every badge draws once at the GUI
    // origin. InventoryMenu.build ends each slot with refresh_slot against a
    // mirror that is still empty at spawn_menu time, so all 54 nodes.item are
    // disabled when we hang the badges off them. compute_node_caches SKIPS a
    // disabled node (Anchor.gml:702-706), so the item's cache_x/cache_y keep
    // their Node.gml:78 defaults of 0 - but enable_node derives visibility from
    // the node's OWN flag and never consults the parent (Anchor.gml:1620), and
    // the Text render pass tests only safe_enabled and the bbox (Anchor.gml:
    // 1041-1050). So a badge we just enabled resolves RightIn/TopIn against a
    // parent at (0,0) and renders at GUI ~(-3, 0), at full opacity, over a menu
    // still fading in - the alpha chain is broken at the same uncomputed parent.
    // It self-heals on the next frame's listen_for_updates, which is exactly one
    // frame too late to be invisible.
    //
    // refresh() is the engine's own idempotent re-derive of every slot from the
    // inventory (InventoryMenu.gml:152-156): it enables the filled slots in this
    // frame, plays no sound, moves nothing, and the tick's own refresh next frame
    // then finds nothing to do. It must run AFTER the projection, which is what
    // puts the rows in the mirror it reads.
    var _left_menu = _menu[$ "left_menu"];
    if (_left_menu != undefined) {
        // AND THE ONE THING A REMOTE VIEW WILL NOT LET YOU TAKE, installed
        // before that refresh so it is true on frame one rather than on the
        // first repaint. In a remote view the bound remote's own cell is
        // visible, tooltipped and completely inert: taking it out would unlink
        // the network from the surface that unlinking closes, and H2 refuses to
        // let it back in, so the walk home would be the only repair. The
        // derivation, both directions and the cell-reuse rule are all in
        // yads_remote_slot_filter; _remote is the whole of the condition.
        if (_remote) { _left_menu.filter_callback = yads_remote_slot_filter; }
        _left_menu.refresh();
    }

    // AE2-style: the box is already listening, so the player types the moment the
    // panel opens. The gate is two tests, each carrying real weight against the
    // engine's OSK condition (Node.gml:1173-1175):
    //
    //     if steam_on_deck() || (steam_in_big_picture_mode() && ON_GAMEPAD) {
    //         self.spawned_steam_keyboard = steam_open_textbox();
    //
    //   !steam_on_deck() - the FIRST arm ignores input type entirely: a Deck in
    //     touch/trackpad mode reads as KBM (Input.gml:35-86), so without this
    //     test every Deck open threw the OSK over the menu. ON_KBM cannot cover
    //     this case; only the direct predicate can.
    //   ON_KBM - besides "auto-typing needs a keyboard", it is what disarms the
    //     SECOND arm: ON_KBM and ON_GAMEPAD are the same enum read
    //     (Init.gml:28-29), so under ON_KBM the Big-Picture arm cannot fire and
    //     a Big Picture session with a real keyboard attached keeps auto-focus.
    //
    // SAFE FROM BOTH CALLERS, and since 1.2 they sit on opposite sides of the
    // ANCHOR pass, so the argument has to cover both rather than name one.
    //
    //   PANEL (yads_open_view from object.interact). interact() runs from
    //     obj_ari's step, i.e. AFTER this frame's ANCHOR.on_begin_step, so the
    //     first run of search_think is the NEXT frame - by which time the click
    //     or key that opened the panel is long consumed.
    //   REMOTE (yads_open_view from yads_remote_view, new in 1.2). Our tick is
    //     drained at the head of Game.step_begin, BEFORE ANCHOR.on_begin_step
    //     (Game.gml:570-582), so search_think's first run is later in the SAME
    //     frame and the hotkey's own press is still live for it. boot.gml §5b
    //     carries the frame order and its derivation.
    //
    // What makes the remote case safe is not the frame, it is the keycode. Every
    // blur path below is keyed to a code the hotkey is not: vk_escape / vk_enter
    // (:2491), InputId.MenuBack (:2518, default binding "escape"), the Steam-OSK
    // arm (:2530 - and the two-test gate on the next line disarms both arms of
    // the engine condition that could have set spawned_steam_keyboard in the
    // first place), and a left-click outside the plate (:2549). No vanilla
    // default binds any F-key - Settings.gml's whole binding table contains no
    // vk_f* at all - and the engine mentions vk_f6 in exactly three places, none
    // of them a reader: the KEYBOARD_INPUTS membership list (InputUtils.gml:180)
    // and the two name<->code translation tables (:590, :705). A function-key
    // hotkey therefore deposits no edge any blur path can see. A LETTER hotkey
    // would, which is the second reason - on top of the raw-poll one in §5 - that
    // this mod binds function keys only.
    if (ON_KBM && !steam_on_deck()
        && _config.auto_search && _view.search_node != undefined) {
        yads_search_focus(_view);
    }

    return _view;
}

//
// 2. WIDGETS
//
// Three additions to the vanilla storage menu, built in this order:
//
//   a. the row-6 plate - an opaque strip covering the nine landing slots, which
//      carries the eight category filter buttons and their shared tooltip label;
//   b. a control bar BELOW the plate: the pager, the value-badge toggle and the
//      sort cycle, all packed against its right-hand end - the left of that bar
//      belongs to the glyph guide, see build_bottom_bar;
//   c. a search strip ABOVE the plate: the auto-focus toggle and the search box.
//
// Everything is parented inside the menu so it moves, fades and frees with it.
//
// WHY THE SEARCH IS ABOVE THE PLATE. On the bottom bar it shares 228px with
// three other controls and comes out 96px wide - a field you cannot read your
// own query in. The minspec canvas has ~34px of dimmed background ABOVE the plate
// (verifier-measured: the plate spans canvas y 34..223 of 240) against ~17px
// below it, so the roomier band was the one nothing was using. The strip hangs
// off left_box with Align.TopIn and a NEGATIVE y, which is the exact mirror of
// how the bottom bar hangs with BottomIn and a positive one: TopIn resolves to
// `y + parent.cache_y` and BottomIn to `y + parent.cache_y + parent.height -
// node.height` (anchor_utils.gml:253-283), so -18 and +8 are the same gesture.
//
// It is right-aligned and 76px short of full width because that band is NOT
// empty: StorageBanner.build parents the ribbon on left_box at Align.LeftIn /
// Align.TopOut and nudges it to y=1 (StorageMenu.gml:49-50), i.e. directly above
// the plate's top-left corner, and the two-icon backplate is 77x23. The strip
// therefore sits on the banner's own row, to its right, with a 5px gap.
//
// PILOT ORDER vs VISUAL ORDER. Rows are pilot rows in CREATION order and the
// grid's pilot already holds the banner (row 0) and the six slot rows (1..6, row
// 6 all locked and skipped) by the time we run, so nothing of ours can be
// threaded in above the slots - the three rows we add are always the last three.
// Given that, they are ordered by how often a pad reaches for them rather than
// by where they sit: filters (7) and the pager/sort bar (8) are what a pad user
// actually walks down into, and the search strip (9) - which a pad cannot type
// into without the on-screen keyboard anyway - is last. So the eye reads
// search / grid / filters / pager while the stick walks grid -> filters ->
// pager -> search. Deliberate; do not "fix" it by reordering the builders
// without re-reading this note.
//
// Note what is NOT here: no extra button on the StorageBanner. The banner's
// backplate sprite is chosen by button count
// (`spr_ui_inventory_ribbon_{count}_icon_backplate`, StorageMenu.gml:465) and
// only _2_, _3_ and _4_ exist in the assets - a fifth would 404.
//
function yads_build_widgets(_view) {
    var _menu = _view.menu;
    var _pilot = _menu.left_menu.pilot;

    yads_build_filters(_view, _menu, _pilot);

    // Do NOT move the grid: the 54-plate's slot wells are painted into the art
    // and the vanilla centering already lands the 22px squares exactly on them
    // (measured: first well at x=13,y=23 on the 240x189 plate; canvas 234x162
    // centers to x=3,y=14 + 10px padding = 13,24). Any add_y produces a ghost
    // grid of half-covered wells. The plate also has no free interior band, so
    // both control strips float outside it - and museum-style floating controls
    // are a vanilla look.
    var _bar_width = max(180, _menu.left_box.get_width() - 12);

    yads_build_bottom_bar(_view, _menu, _pilot, _bar_width);
    yads_build_search_strip(_view, _menu, _pilot, _bar_width);

    // 2d. Mouse wheel over the network grid flips pages. Same guard shape the
    //     Scroller uses (Scroller.gml:250-258). left_box carries no think
    //     callback of its own, so this does not overwrite one.
    _menu.left_box.set_think_callback(yads_box_think, [_view]);

    // 2e. Repoint the two banner buttons that are wrong for a paged mirror.
    //
    //     The LEFT banner's sort icon taps straight into inventory.sort() on
    //     the 54-slot mirror (StorageMenu.gml:286-288) - on a full page that is
    //     one List entry PER UNIT (up to ~45k) re-added one by one, a
    //     multi-second freeze, and the result is vanilla ItemUse order that our
    //     next projection silently discards. Repointed to the mod's own
    //     sort-cycle, it becomes a second, consistent way to change ordering.
    //
    //     The RIGHT banner's stack icon gates each backpack slot on
    //     pair.item_id_quantity() - the MIRROR - so it silently no-ops for
    //     anything not on the visible page (StorageMenu.gml:479-481).
    //     Repointed to a member-side quick-stack, it means what it shows.
    //
    //     Both reads are guarded: if a game update renames the fields we fall
    //     back to vanilla behaviour rather than crash.
    // intentional_override=true: we are deliberately replacing the banner's
    // own callbacks, and without it Node.set_tap_callback logs a Warn with an
    // eager debug_get_callstack on every menu open (Node.gml:515-518).
    var _left_banner = _menu[$ "left_banner"];
    if (_left_banner != undefined) {
        var _sort_icon = _left_banner[$ "sort_icon"];
        if (_sort_icon != undefined) {
            _sort_icon.set_tap_callback(yads_tap_sort, [_view], true);
        }
    }
    var _right_banner = _menu[$ "right_banner"];
    if (_right_banner != undefined) {
        var _stack_icon = _right_banner[$ "stack_icon"];
        if (_stack_icon != undefined) {
            _stack_icon.set_tap_callback(yads_tap_stack, [_view], true);
        }
    }
}

//
// 2a. THE BOTTOM BAR - pager, then sort cycle
//
// Vertical budget note, and the binding constraint on this whole bar:
// the plate bottoms out at canvas y~223 of the 240px minspec canvas and the
// arrows' enlarged bboxes reach ~y=239 with set_y(8). That fits with ~1px to
// spare - do NOT increase set_y, the bar height, or the arrows' bottom bbox
// offset without re-measuring against Display.gml's minspec constants. This is
// also why the pager got its symmetry from HORIZONTAL spacing rather than from a
// fatter hit box: growing the bbox downwards is the one direction with no room.
//
function yads_build_bottom_bar(_view, _menu, _pilot, _bar_width) {
    _pilot.request_newline();   // pilot row 8

    var _bar = ANCHOR.positional(_menu.left_box)
        .set_size(_bar_width, 16)
        .set_align(Align.Center, Align.BottomIn)
        .set_y(8);   // BottomIn 189-16+8: 8px past the plate's bottom edge

    // A shelf under the controls, because three widgets floating over the
    // dimmed background read as three loose widgets rather than as one bar.
    //
    // FIRST, before every other child, and that is load-bearing rather than
    // tidy: children of _bar all default to _bar.z - 1, all of them are
    // Sprite-queue nodes, the depth test is cmpfunc_lessequal, and equal depths
    // resolve in REGISTRATION order (Anchor.gml:844). The backplate is behind the
    // arrows and the sort button because it was created before them.
    //
    // spr_ui_hud_item_toast_box is the game's own vocabulary for a small floating
    // control shelf - it is what the HUD's item toast rides on - and the mod's
    // other floating widget, the tooltip, is the same pink-cream family. It is a
    // 7x7 nine-slice, so its minimum honest height is 14 and the bar's 16 clears
    // it by a pixel top and bottom; below 14 the interior height goes negative
    // and draw_sprite_stretched_ext mirrors a band across the middle
    // (Anchor.gml:896-901). A 16px plate at the bar's existing y and height adds
    // NO vertical extent, which is the only reason it is free: the arrows' bboxes
    // already reach y~239 of the 240px minspec canvas.
    //
    // (The warm alternative, spr_ui_generic_store_option_box_body, is 8x8 and
    // would need exactly 16 - no slack at all - to say the same thing. Nothing in
    // the atlas actually matches the storage plate's #66271F wood; every generic
    // nine-slice is pink-cream paper.)
    ANCHOR.nine_slice(_bar)
        .set_sprite(spr_ui_hud_item_toast_box)
        .set_size(_bar_width, 16)
        .set_align(Align.Center, Align.Middle);

    // THE BAR'S LEFT 68 PIXELS ARE DELIBERATELY EMPTY. They are the GLYPH
    // GUIDE's footprint, budgeted against the widest shipped locale rather than
    // against English - see the pager note below for the measurements.
    //
    // The ESC/Close hint is a separate menu on a separate canvas: hud_menus.toml
    // gives every HUD menu canvas_kind "screen" and [glyph_guide] overrides only
    // layer = "popup", so its backplate is LeftIn/BottomIn at (4, -4) on the
    // SCREEN canvas, 55 x (7 + 18 per glyph) and grown to
    // 16 + 16 + string_width(local_get("misc_local/close")) when that exceeds 55
    // - about 65px wide in English (GlyphGuideMenu.gml:146-194). This menu asks
    // for it itself, every frame, through AnchorMenu.run_exit_listening
    // (AnchorMenu.gml:171), and hides_hud does not suppress it (GlyphGuide is not
    // in menu_is_hud's list, anchor_utils.gml:134-141).
    //
    // Our canvas is minspec, which is FIXED at 426.667 x 240 (Display.gml:4-5,
    // Node.gml:816-819) and centred on the screen canvas. The Scale setting
    // changes the texel size, so turning it UP shrinks the screen canvas TOWARD
    // minspec and the inset between the two goes to zero - dragging the
    // screen-anchored glyph plate onto this menu's own bottom-left corner. At
    // 2560x1440 "4x" the inset is exactly (0,0) and the plate covers minspec
    // x 4..65, y 211..236; at 1920x1080 "3x" it still eats the bottom rows. The
    // hint is not growing, the menu's frame is coming down to meet it.
    //
    // The bar spans canvas x 16..244 and y 215..231, so canvas = bar-local + 16
    // and the plate's danger band is bar-local x 0..49 in English and 0..64 in
    // Russian, which is the widest of the seven shipped locales and therefore the
    // number this layout is budgeted against - measured, not estimated, from
    // assets/fiddle/fonts/text_widths.toml and the shipped translation tables:
    // eng "Close" 29px -> plate to canvas 65, spa "Cerrar" 37 -> 73, fra
    // "Fermer" 39 -> 75, rus "Закрыть" 44 -> 80. (The three CJK locales cannot be
    // measured from that table at all; they float at or above the 55px floor, so
    // budgeting to the Russian number covers them unless a CJK "close" is wider
    // than seven Cyrillic letters, which no plausible rendering is.)
    //
    // Nothing may be placed in bar-local 0..64. A widget there - the value
    // toggle used to sit at bar-local 0..16, canvas 16..32, dead centre of the
    // plate - cannot be rescued by a nudge, so everything on this bar is pinned
    // to the RIGHT edge and the dangerous run holds nothing at all.
    //
    // There is no z that wins this: the glyph guide is on AnchorLayer.Popup,
    // above AboveFader (anchor_utils.gml:121-131), which is already the highest
    // layer this mod uses.
    //
    // THE PAGER IS ONE FIXED-WIDTH CLUSTER rather than three independently
    // placed nodes: the arrows pin to its ends and the counter centres inside it,
    // so "1 / 1" and "23 / 23" - and any locale's rendering of either - stay
    // balanced instead of drifting as the string grows. It is 72 wide and
    // right-anchored rather than centred in the bar; the width is derived below.
    //
    // The arithmetic, right to left, in bar-local pixels (bar width 228; the
    // rule is anchor_utils.gml:222-240, cache_x = x + parent.cache_x +
    // parent.width - node.width, so canvas = bar-local + 16):
    //
    //   sort button  RightIn -1, 58 wide          169 .. 227
    //   value toggle RightIn -61, 16 wide         151 .. 167   (2px gap)
    //   pager        RightIn -88, 72 wide          68 .. 140   (3px gap to the
    //                                                           toggle, measured
    //                                                           off the right
    //                                                           arrow's bbox)
    //
    // set_bbox_offset(-4, -5, 8, 12) on each arrow moves its left edge 4px out
    // and its right edge 8px out (Node.gml:362-365 takes left/top/right/bottom),
    // so the cluster's hit boxes run 64..148 and the toggle starts 3px clear of
    // them. Every widget is anchored to the bar's RIGHT edge so the whole row
    // travels together if the plate ever changes width; only the empty run on
    // the left absorbs the difference, which is the run that is supposed to be
    // empty.
    //
    // Why the gaps matter at all: ANCHOR walks nodes in reverse registration
    // order (Anchor.gml:370) and hover_node releases the previously hovered node
    // before claiming the new one (:1805-1819), so inside an overlap the
    // LATER-registered node hovers first and eats the tap - muting the press -
    // and then the EARLIER one hovers and releases it. It ping-pongs for as long
    // as the mouse sits there. Survivable and pointless: keep the gaps.
    //
    // 72 AND NOT 88. The glyph plate's right edge is not 65 in every language:
    // GlyphGuideMenu.gml:190-194 sizes it as
    // 16 + sprite_get_width(glyph) + string_width_font(local_get(
    // "misc_local/close")), and against the shipped width table and the shipped
    // translations that is canvas 65 in English, 73 in Spanish ("Cerrar"), 75 in
    // French ("Fermer") and 80 in Russian ("Закрыть"). An 88px cluster puts the
    // left arrow's SPRITE at canvas 68 - fully buried under the plate in three
    // shipped locales, and unquantifiable but same-risk in the three CJK ones.
    // The cluster is anchored to the bar's right edge and the toggle behind it
    // cannot move (it is the widget this whole layout exists to rescue), so the
    // only way to buy those pixels was to spend the cluster's own width:
    //
    //   left arrow SPRITE  canvas 84 .. 89   - 4px clear of the Russian plate,
    //                                          and clear of every locale's
    //   left arrow BBOX    canvas 80         - touches the Russian plate's edge,
    //                                          harmless: the plate is a callback-
    //                                          less nine-slice, so it fails the
    //                                          listens_for_hovers && safe_unlocked
    //                                          gate at Anchor.gml:377 and takes
    //                                          no hovers to steal
    //   right arrow BBOX   canvas 164        - unchanged, 3px clear of the toggle
    //
    // WHICH THE COUNTER PAID FOR, and why "Page" left the string. Centred in a
    // 72px cluster between two 5px arrows, the counter has 62px. "Page 100 / 100"
    // measures 77 in the standard font, so the word had to go: "100 / 100" is 49px,
    // leaving 13px of slack.
    //
    // THE CEILING IS SET BY CELLS, NOT BY ITEM IDS. project() splits every row
    // into ceil(total / max_stack) cells before paging, so the page count is
    // bounded by occupied member SLOTS: 35 Storage Blocks are 1,050 slots and
    // pass 23 pages with a single item kind in them. Measured against
    // fonts/text_widths.toml (digit 6, space 3, "/" 7): "23 / 23" 37px,
    // "100 / 100" 49px, "999 / 999" 49px, and even "1000 / 1000" is 61px against
    // the 62px interior. Four digits needs ~45,000 cells - about 1,500 blocks,
    // placeable on the 188x144 farm grid and absurd rather than impossible - and
    // still fits; five needs more grid than the farm has. Budget any replacement
    // string against three or four digits a side, not two.
    //
    // Two arrows either side of a fraction is not a control anybody needs the word
    // "Page" to read, and the key is a mod key with no translations, so the English
    // measurement is the measurement in every language.
    var _pager = ANCHOR.positional(_bar)
        .set_size(72, 16)
        .set_align(Align.RightIn, Align.Middle)
        .set_x(-88);

    // Both arrows wrap, matching the farm-building selector
    // (FarmBuildingSelectionMenu.gml:195-218), which is also where the enlarged
    // bbox comes from - the arrow sprites are tiny. The two offsets are
    // identical so both arrows are equally easy to hit.
    ANCHOR.sprite(_pager)
        .set_sprites_from_key("spr_ui_scroller_arrow_left")
        .set_align(Align.LeftIn, Align.Middle)
        .set_x(0)
        .set_bbox_offset(-4, -5, 8, 12)
        .set_tap_sound("SoundEffects/UI/UIExtraPositiveClick")
        .set_tap_callback(yads_tap_prev, [_view])
        .add_to_pilot(_pilot);

    _view.page_text = ANCHOR.text(_pager)
        .set_lut(COMMON_LUT)
        .set_align(Align.Center, Align.Middle)
        .set_text(yads_page_label(0, 1));

    ANCHOR.sprite(_pager)
        .set_sprites_from_key("spr_ui_scroller_arrow_right")
        .set_align(Align.RightIn, Align.Middle)
        .set_x(0)
        .set_bbox_offset(-4, -5, 8, 12)
        .set_tap_sound("SoundEffects/UI/UIExtraPositiveClick")
        .set_tap_callback(yads_tap_next, [_view])
        .add_to_pilot(_pilot);

    // The value-badge cycle, between the pager and the sort button. Added to the
    // pilot after both arrows and before the sort button, so the row still walks
    // left to right under the stick - the same rule the whole bar is built on,
    // and the reason this call moved down the function when the widget moved
    // right across the bar.
    //
    // It stays on this bar rather than emigrating to the search strip: the strip
    // is spent (16 toggle + 3 + 133 search = 152 of 152) and every pixel taken
    // from it comes straight off the query the player can read back - a second
    // 16px toggle up there would cut the field from ~21 characters to ~18.
    yads_build_value_toggle(_view, _bar, _pilot);

    // Sort cycle. The label is a localization key, swapped on every change.
    // Added to the pilot LAST of the four, so the row still walks left-to-right
    // under the stick.
    //
    // THE BUTTON IS 58 WIDE AND THE LABEL GETS 52 OF IT. add_text_label builds
    // the label with allow_line_breaks() and prevent_spillover() (Node.gml:
    // 1860-1873) and a TextNode's reflow budget is parent.width -
    // max(x * 2, required_padding), with required_padding defaulting to 6
    // (Node.gml:963, :1069-1074) - so 52, not 58. A label wider than that wraps
    // to two lines and draws several pixels above and below a 14px button, in
    // every locale, since these keys have no translations. SHORTEN THE STRING,
    // never widen the button: widening leftwards eats the 2px gap to the value
    // toggle, and every other widget on this bar is pinned to the right edge.
    // Every label this switch can produce is measured in ui.toml; keep them
    // under 52px against assets/fiddle/fonts/text_widths.toml.
    _view.sort_button = ANCHOR.nine_slice(_bar)
        .set_sprites_from_key("spr_ui_button")
        .set_size(58, 14)
        .set_align(Align.RightIn, Align.Middle)
        .set_x(-1)
        // The PERSISTED mode's key, not a baked "sort_category": the view is
        // seeded from the config file, so a hardcoded label would spend the
        // first frame lying about an order the grid is already in. Every key
        // this can produce is measured in ui.toml against the 52px budget above.
        //
        // This is the ONLY open-time write of this label - add_text_label ends
        // in set_key (Node.gml:1878), which is exactly what yads_apply_sort_label
        // does, so calling that at open too would have been the same string
        // written twice. From here on the tick owns it: it repaints the label
        // whenever it applies a sort_request (boot.gml section 3c).
        .add_text_label(yads_sort_key(_view.sort_mode),
            COMMON_LUT, CommonLutIndex.Dark)
        .set_tap_sound("SoundEffects/UI/UIExtraPositiveClick")
        .add_hover_outline()
        .set_tap_callback(yads_tap_sort, [_view])
        .add_to_pilot(_pilot);
}

//
// 2a-i. THE VALUE-BADGE TOGGLE
//
// A three-state cycle - off, whole-stack, per-unit - on one 16px square, built
// exactly like the auto-search toggle it is the sibling of: a common_slice square
// whose lit/unlit state comes from the engine's own sprite state machine through
// set_selected_getter (Anchor.gml:600-618), a plain child sprite for the glyph,
// and its OWN tooltip plate and OWN think on its own node, so nothing about it
// depends on an unrelated builder having survived its early returns.
//
// One icon for all three states rather than three: the box lights for "badges are
// on" and the tooltip names WHICH of the two on-states is running. A player
// hovering to find out gets the exact answer in words; a player glancing across
// the bar gets the binary they actually wanted.
//
// IT SITS CLEAR OF THE GLYPH GUIDE'S FOOTPRINT - see the danger geometry over
// build_bottom_bar - at bar-local 151..167, i.e. canvas 167..183, two pixels
// left of the sort button and about a hundred clear of the worst-case plate.
// Two consequences here:
//
//   * RightIn -61 rather than LeftIn 0, so the button hangs off the same edge as
//     the sort button beside it and the pair travels together.
//   * the tooltip is CENTRED. A centred plate over a button at the bar's LEFT
//     edge would put half of itself past the storage plate's left border; from
//     the right-hand end the opposite is true - the widest label, "Values: per
//     stack" at 91px plus 10 of padding, spans canvas 125..226 centred,
//     comfortably inside the plate's 10..250, where LeftIn would push it to 268
//     and hang it over the dimmed background.
//
// AND IT NEEDS ITS OWN LAYER, which the horizontal reasoning does not show. Do
// the vertical arithmetic: the bar is BottomIn set_y(8) on a 240x189 left_box, so its
// top edge is 8 + 189 - 16 = box y 181; TopOut is round(y + parent.cache_y) -
// height (anchor_utils.gml:259-266), so a 16px plate at set_y(-2) spans y 163..
// 179. The filter plate is canvas(3,14) + (8,129) by 218x24 - y 143..167, x
// 11..229. They overlap on four rows, 163..167, and the filter plate is opaque,
// spans the full width of the box so no horizontal shift can clear it, and lives
// on AnchorLayer.AboveFader, which clears the depth buffer behind it
// (anchor_utils.gml:121-131) and eats the tooltip's top border rows.
//
// No y value fixes it either: clearing the plate needs y >= 167, which is on top
// of the toggle itself, and below the bar is spent - the arrows' bboxes already
// reach the 240px minspec floor (see the vertical budget note in section 2a). So
// the tooltip joins the plate on AboveFader and wins on depth instead, exactly
// the way the filter bar's own tooltip does - that one inherits the layer from
// its parent, this one has to ask, because its parent is on Standard.
//
function yads_build_value_toggle(_view, _bar, _pilot) {
    _view.value_button = common_slice(_bar, 16, 16)
        .set_align(Align.RightIn, Align.Middle)
        .set_x(-61)
        .set_tap_sound("SoundEffects/UI/UIExtraPositiveClick")
        .set_tap_callback(yads_tap_value, [_view])
        .set_selected_getter(yads_value_selected, [])
        .add_to_pilot(_pilot);

    // 14x14, an exact fit inside the 16px square with the 1px margin the
    // common_slice border wants, and it is the game's own "this is about
    // tesserae" glyph (the EOD summary's sold-items header).
    _view.value_icon = ANCHOR.sprite(_view.value_button)
        .set_sprite(yads_value_icon())
        .set_align(Align.Center, Align.Middle);

    // 16, not 14: spr_ui_tooltip_box is an 8x8 nine-slice and 2 * frame_size is
    // its floor. Both sizing sites - here and the per-key resize in the think
    // below - have to agree or the first hover undoes it.
    //
    // z 40 on AboveFader, and both numbers are load-bearing. The layer is the fix
    // (see the header); the z is what wins inside it, because within one layer the
    // depth test is cmpfunc_lessequal and LOWER z draws in front. The filter plate
    // is z 50 and its deepest descendant - the tooltip label it owns - is 47, so
    // 40 clears the whole subtree with room, and the label this plate parents
    // inherits 39 and stays in front of its own plate. It is still far below the
    // toggle's own z (canvas 100 -> left_box 99 -> bar 98 -> button 97), which is
    // what the DEBUG_ASSERTIONS child-behind-parent assert checks (Anchor.gml:
    // 794-800). The label needs no override of its own: children inherit the
    // parent's layer (Node.gml:56-60). AboveFader still renders below Popup, so
    // item tooltips and the drag hand keep drawing over this.
    _view.value_hint_plate = ANCHOR.nine_slice(_view.value_button, 40, AnchorLayer.AboveFader)
        .set_sprite(spr_ui_tooltip_box)
        .set_size(70, 16)
        .set_align(Align.Center, Align.TopOut)
        .set_y(-2)
        .set_enabled(false);

    _view.value_hint_label = ANCHOR.text(_view.value_hint_plate)
        .set_lut(COMMON_LUT)
        .set_align(Align.Center, Align.Middle)
        .allow_line_breaks(false)
        .set_key(yads_value_label_key());

    // On the toggle, never on the plate it drives: a disabled node does not think
    // (Anchor.gml:374) and could never turn itself back on.
    _view.value_button.set_think_callback(
        yads_value_think, [_view]);
}

//
// 2b. THE SEARCH STRIP - auto-focus toggle, then the search box
//
// Hangs ABOVE the plate; see the geometry derivation in section 2's header for
// why TopIn/-18 and why the strip clears the left 76px.
//
// The field may or may not be focused at build time - see the auto-focus block
// in yads_open_view - but the rule it exists under has not
// changed: while ANCHOR.text_input_node is set, every keyboard-bound InputId is
// zeroed each frame (Anchor.gml:194-202), MenuBack included, so focus ALWAYS
// costs the player one extra ESC to close the menu. That is the AE2 trade, it is
// why the toggle sits right next to the box, and it is why the toggle's own
// state is the first thing its tooltip says.
//
function yads_build_search_strip(_view, _menu, _pilot, _bar_width) {
    _pilot.request_newline();   // pilot row 9

    // 76 clears the 77x23 two-icon banner ribbon; -6 puts the strip's right edge
    // on the same column as the bottom bar's. -18 centres the 16px strip on the
    // ribbon's own row (the ribbon occupies plate-local y -22..1).
    var _strip_width = max(120, _bar_width - 76);
    var _strip = ANCHOR.positional(_menu.left_box)
        .set_size(_strip_width, 16)
        .set_align(Align.RightIn, Align.TopIn)
        .set_x(-6)
        .set_y(-18);

    // The toggle. common_slice hands us the whole spr_ui_generic_box state set
    // including SELECTED, and the selected getter is read every frame by the
    // engine's own sprite state machine (Anchor.gml:600-618), so the lit box IS
    // the "on" indicator - no think callback of ours is needed for it. The
    // checkbox glyph on top is the second, unambiguous read of the same bit.
    //
    // The glyph is spr_ui_generic_renown_magnify_icon_{enabled,hovered,locked,
    // tapped}, 11x11, a complete four-state family under UI NEW/Generic/Icons/.
    // It is easy to miss when searching the atlas because the file is named
    // after the renown screen that uses it, not after what it draws. See
    // yads_autosearch_icon for why it goes on with plain set_sprite rather than
    // set_sprites_from_key.
    _view.autosearch_button = common_slice(_strip, 16, 16)
        .set_align(Align.LeftIn, Align.Middle)
        .set_x(0)
        .set_tap_sound("SoundEffects/UI/UIExtraPositiveClick")
        .set_tap_callback(yads_tap_autosearch, [_view])
        .set_selected_getter(yads_autosearch_selected, [])
        .add_to_pilot(_pilot);

    _view.autosearch_icon = ANCHOR.sprite(_view.autosearch_button)
        .set_sprite(yads_autosearch_icon())
        .set_align(Align.Center, Align.Middle);

    // The toggle's OWN tooltip, and the toggle's OWN poll. NEITHER MAY LIVE ON
    // THE FILTER PLATE'S think (yads_hint_think), for two separate reasons.
    //
    //   * Dependency. build_filters has three defensive early-returns (no
    //     left_menu, no slots, no canvas) and its last statement is the one that
    //     installs that poll. Take any of them - a game update renaming a vanilla
    //     field is exactly what they are there for - and the search strip still
    //     builds, the toggle still flips, the generic box still lights (that goes
    //     through set_selected_getter, which the engine polls itself), but the
    //     checkbox glyph freezes at its build-time frame. A widget that lies
    //     about a setting stored in a file is worse than a widget with no icon.
    //   * Geometry. The shared plate hangs off the filter plate at the BOTTOM of
    //     the menu; the toggle is at the TOP. The label for it appeared roughly
    //     117px away from the control it described, across the item grid.
    //
    // So the toggle carries both jobs itself, on a node that exists whenever the
    // toggle exists. Its tooltip hangs above the strip, in the dimmed band the
    // storage plate does not use, right over the control it names - and on the
    // Standard layer it inherits from the toggle, so it draws over that
    // background without needing the filter plate's AboveFader override.
    //
    // BUDGET, measured rather than eyeballed: left_box is Middle-aligned in the
    // GUI canvas at set_y(8), so at the 240px minspec its top edge is screen
    // y = 8 + floor((240-189)/2 + 0.5) = 34 (anchor_utils.gml:267-274); the strip
    // is TopIn/-18 off it, i.e. y 16..32, and the toggle fills it. TopOut resolves
    // to round(y + parent.cache_y) - height, so this plate lands at 14 - 16 = -2
    // and spans y -2..14. The free band is exactly 16px and the box wants 18 with
    // its gap, so at MINSPEC ONLY the top two rows fall above the canvas edge -
    // ANCHOR culls only a node whose bbox misses the screen entirely
    // (Anchor.gml:833-838), so it still draws, two pixels of border short. Every
    // taller view height has the room, because the plate is centred and the band
    // grows with it. Noted, not hidden: if that clip ever reads badly, the fix is
    // set_y(0), not a shorter box - 16 is the nine-slice floor.
    _view.autosearch_hint_plate = ANCHOR.nine_slice(_view.autosearch_button)
        .set_sprite(spr_ui_tooltip_box)
        .set_size(60, 16)   // 16 minimum: 8x8 nine-slice, see the note in build_filters
        .set_align(Align.Center, Align.TopOut)
        .set_y(-2)
        .set_enabled(false);

    _view.autosearch_hint_label = ANCHOR.text(_view.autosearch_hint_plate)
        .set_lut(COMMON_LUT)
        .set_align(Align.Center, Align.Middle)
        .allow_line_breaks(false)
        .set_key(yads_autosearch_label_key());

    // On the toggle, not on the plate it drives: a disabled node does not think
    // (Anchor.gml:374) and could never turn itself back on. common_slice installs
    // no think callback of its own, so this overwrites nothing and logs no Warn.
    _view.autosearch_button.set_think_callback(
        yads_autosearch_think, [_view]);

    // 19 is the toggle plus its gap, taken off the strip. No floor here: the
    // strip is already floored at 120 above, so the narrowest box this can
    // produce is 101px - the minspec case anyone re-deriving the budget below
    // wants, and the reason the old max(48, ...) was unreachable arithmetic
    // that made the worst case read as 26px of query room instead of 79.
    var _search_width = _strip_width - 19;

    // The width budget the LINE EDITOR enforces by hand. It is the same number
    // that goes into set_max_width below, kept on the view because once the
    // engine's text driver is switched off nothing enforces max_width any more:
    // with can_line_break false, update_display_text assigns display_text = text
    // verbatim (Node.gml:1099-1109) and the ONLY truncation in the whole engine
    // is the driver's own reject-the-keystroke test (Anchor.gml:477-479). Forget
    // this and a long query renders straight out through the plate.
    //
    // 22, not 8, and every one of them measured rather than guessed: 3 for the
    // text node's own LeftIn inset, 14 for the clear button's visible plate at
    // the right edge (its opaque alpha bbox is 2,2..16,16 of an 18x18 sprite -
    // see the bottom of this function), 3 for what sits right of that plate
    // (set_x(-1) plus the sprite's own 2px transparent margin), and 2 of gap.
    // Concretely: RightIn puts the button's node at plate_right-19..plate_right-1
    // (anchor_utils.gml:232-239), so its ink starts at plate_right-17, while the
    // text can reach plate_left + 3 + (_search_width - 22) = plate_right - 19.
    // The clearance is real but it is 2px, not the 4 this comment used to claim.
    // At the shipped _bar_width of 228 the query budget is 111px, down from the
    // 125px of the -8 days - about two characters - and 79px at minspec.
    //
    // It is charged UNCONDITIONALLY even though the X only appears once there is
    // a query, because the budget is what the editor measures every keystroke
    // against - a budget that grew while the box was empty would let the first
    // characters land in space the X is about to occupy, and the engine's own
    // render order draws Text after Sprite at equal depth, so they would come out
    // on top of the button rather than clipped by it.
    _view.search_max_width = _search_width - 22;

    _view.search_plate = ANCHOR.nine_slice(_strip)
        .set_sprites_from_key("spr_ui_text_input_box")
        .set_size(_search_width, 14)
        .set_align(Align.LeftIn, Align.Middle)
        .set_x(19)
        .set_tap_callback(yads_tap_search, [_view])
        .add_to_pilot(_pilot);

    // ORDER IS LOAD-BEARING AND ALWAYS HAS BEEN: set_max_width's last-but-one
    // statement is a bare self.allow_line_breaks() whose parameter defaults to
    // TRUE (Node.gml:1224-1232), so it silently re-enables reflow. The
    // .allow_line_breaks(false) below it is what turns it back off. Never
    // reorder those two lines.
    _view.search_node = ANCHOR.text(_view.search_plate)
        .set_align(Align.LeftIn, Align.Middle)
        .set_x(3)
        .set_lut(COMMON_LUT)
        .set_max_width(_view.search_max_width)
        .set_text("")
        .allow_line_breaks(false)
        .set_think_callback(yads_search_think, [_view]);

    // Placeholder hint, shown only while the box is empty and unfocused. It is
    // a sibling label, never the field's own text - hint text in the field
    // itself would become the live search query and filter everything out.
    _view.search_hint = ANCHOR.text(_view.search_plate)
        .set_align(Align.LeftIn, Align.Middle)
        .set_x(3)
        .set_lut(COMMON_LUT)
        .set_lut_index(CommonLutIndex.Dark)
        .set_key(YADS_LOCAL_ROOT + "search_placeholder");

    // THE SELECTION BAND AND THE CARET, the two nodes that make the box an editor
    // rather than a buffer.
    //
    // WHY NODES AND NOT A SPLICED "|". The engine's caret is a literal pipe
    // appended to display_text on one frame in thirty (Anchor.gml:1136-1145), and
    // "|" has an advance width of 2px, so a caret spliced anywhere but the end
    // shoves every glyph to its right by two pixels at 2Hz. A separate node has
    // no width in the string at all.
    //
    // WHY THEY LAND BEHIND THE TEXT, for free: the per-layer render order is
    // Sprite -> Text -> Typewriter -> Custom (Anchor.gml:830/1041/1122/1220/1353),
    // the depth test is cmpfunc_lessequal, and equal depths resolve in submission
    // order. Both of these are children of the search plate, exactly like the text
    // node, so all three sit at plate.z - 1 and the glyphs are drawn over the
    // band. The caret is a sprite too and is therefore also behind the glyphs -
    // invisible for a 1px bar that lives BETWEEN characters.
    //
    // WHY PLAIN SPRITE NODES AND NOT NINE-SLICES. spr_pixel is the engine's own
    // rect primitive and BuggerMenu.gml:57-63 drives it as a nine-slice - but a
    // nine-slice narrower than 2 * frame_size draws its interior at a NEGATIVE
    // width (Anchor.gml:896-901), and the caret is one pixel wide. A plain sprite
    // node sizes itself as spr_width * scale (Anchor.gml:757-760) and draws with
    // draw_sprite_ext(..., scale_x, scale_y, ..., color, alpha) (:1021-1031), so
    // scale IS the rectangle, at any size, with no floor.
    //
    // DARK, not white. The field's interior is #F2E3ED cream, and the render pass
    // runs premultiplied (gpu_set_blendmode_ext(bm_one, bm_inv_src_alpha),
    // Anchor.gml:845), so a translucent light rect washes the box out while a
    // translucent dark one reads as a proper selection band under dark glyphs.
    _view.sel_node = ANCHOR.sprite(_view.search_plate)
        .set_sprite(spr_pixel)
        .set_align(Align.LeftIn, Align.Middle)
        .set_scale(1, 9)
        .set_color(c_black)
        .set_alpha(0.30)
        .set_enabled(false);

    // Created after the band so that at equal depth it is submitted later and
    // draws on top of it.
    _view.caret_node = ANCHOR.sprite(_view.search_plate)
        .set_sprite(spr_pixel)
        .set_align(Align.LeftIn, Align.Middle)
        .set_scale(1, 9)
        .set_color(c_black)
        .set_enabled(false);

    //
    // THE CLEAR BUTTON. Three decisions, each of which has exactly one right
    // answer here.
    //
    // IT IS A CHILD OF THE PLATE, not of the strip - AND THAT ALONE DOES NOT
    // MAKE A CLICK ON IT COUNT AS "INSIDE THE BOX". The blur test in
    // yads_search_think is a bbox test on ONE node, not a hierarchy walk, and
    // nothing in ANCHOR clips a child to its parent's rect. This sprite is
    // 18x18 in a 14px-tall plate, and Align.Middle resolves to
    // floor((14 - 18) / 2 + 0.5) = -2 (anchor_utils.gml:267-273), so the raw
    // node spans plate_y-2 .. plate_y+16: two rows of it stick out above the
    // plate and two below, which is where the hovered/tapped art paints its
    // ring. Left as-is, a click in those four rows both cleared the query and
    // blurred the field, and 1-2px above a box that draws nothing there wiped
    // the query from what looks like empty strip.
    //
    // TWO HALVES CLOSE IT, and both are load-bearing.
    //
    //   * THE HITBOX IS TRIMMED TO THE ART, set_bbox_offset(2, 2, -2, -2)
    //     below. process_node_bbox adds those four numbers to the cached rect
    //     and touches nothing else (anchor_utils.gml:296-308) - the sprite is
    //     still drawn from cache_x/cache_y at 18x18, so this shrinks the target
    //     without scaling a pixel. set_size CANNOT do this job: a plain sprite
    //     node's width/height are recomputed from spr_* * scale on every dirty
    //     pass (Anchor.gml:751-758), so a set_size(14, 14) is silently undone.
    //     The numbers are the art's own alpha bbox (2,2)-(16,16), i.e. the
    //     hitbox is now exactly the visible plate, and it lands wholly inside
    //     the text plate's rect. Vanilla drives its own widgets this way
    //     (anchor_utils.gml:908, Scroller.gml:31, ToolbarMenu.gml:229).
    //     What it does not move is the ring: hovered/tapped are 18x18 of opaque
    //     art, so a hover still paints 2px over the plate's border - it just
    //     can no longer be triggered from outside the button.
    //   * THE BLUR TEST NAMES BOTH NODES ANYWAY (yads_search_think). The trim
    //     above is a fact about this sprite at this alignment; "a click on the
    //     X is not a click outside the box" is the contract, and it belongs
    //     where it is enforced rather than being inferred from an 18x18 asset
    //     staying 18x18 forever.
    //
    // IT IS REGISTERED LAST, AND THAT IS NOT WHAT MAKES IT WIN THE CLICK - the
    // claim this comment carried through Beta 1.1, which cost the button both its
    // hover and its tap in-engine. ANCHOR walks nodes in REVERSE registration
    // order (Anchor.gml:370), so the last node built is the first OFFERED the
    // hover - and then the plate, visited after it, takes that hover straight
    // back, because hover_node releases the previous holder unconditionally
    // (:1806, :1862-1864) and only one node may hold it. Being offered first is
    // being stolen from afterwards. Two overlapping hover listeners cannot both
    // work by ordering alone in either direction; what makes this one win is
    // yads_search_think closing the plate's gate for the frames the pointer is
    // over this button, and the full argument lives there. Registration order
    // still matters for the SAME-FRAME seam that fix depends on: the text node
    // carrying the poll must sit between the plate and this button, which it
    // does, so do not move either block past it.
    //
    // IT IS A PLAIN SPRITE NODE, NOT A NINE-SLICE, and this one is a crash-class
    // distinction rather than a style one. spr_ui_button_close_{main,hovered,
    // tapped} are SINGLE-FRAME 18x18 images - their meta.toml carries no
    // frame_len, unlike spr_ui_button (3x3, frame_len 9) and every other
    // nine-sliceable key in that folder. Nine-slice drawing indexes frames
    // 0*frame_count .. 8*frame_count (Anchor.gml:918-1000) and set_sprite
    // divides frame_count by 9 for a nine-slice node (Node.gml:1569-1571), and
    // it sizes the corners from spr_width, so a 14x14 nine-slice off an 18x18
    // sprite would draw its interior at width 14 - 36 = -22 (the same trap
    // documented over the caret above). As a plain sprite node the art is used
    // exactly as drawn: the node self-sizes to 18x18 (Anchor.gml:751-758), the
    // main state's opaque plate is the inner 14x14 (alpha bbox 2,2..16,16) and
    // the 2px margin is where the hovered and tapped states put their ring.
    //
    // set_sprites_from_key still gives it the full six-state set: load_button_
    // sprites resolves enabled from _main, pressed from _tapped, hovered from
    // _hovered, and falls back to enabled for locked and the rest
    // (anchor_utils.gml:2502-2515). The key is absent from ui/misc.toml's
    // button_sprite_prefixes, which costs one DEBUG-only warn at first use and
    // nothing at runtime; that file is vanilla's and not ours to edit.
    //
    // No tooltip: the strip's width budget is spent (see build_bottom_bar), and
    // an X in a search box needs no caption in any locale.
    _view.search_clear = ANCHOR.sprite(_view.search_plate)
        .set_sprites_from_key("spr_ui_button_close")
        .set_align(Align.RightIn, Align.Middle)
        .set_x(-1)
        .set_bbox_offset(2, 2, -2, -2)   // hitbox = the drawn plate, see above
        .set_tap_sound("SoundEffects/UI/UIExtraPositiveClick")
        .set_tap_callback(yads_tap_search_clear, [_view])
        .add_to_pilot(_pilot)
        .set_enabled(false)
        .set_unlocked(false);   // both flags - see the note in yads_search_think
}

//
// 2f. THE ROW-6 PLATE AND THE CATEGORY FILTERS
//
// The last row of the mirror is structurally always empty - it is the deposit
// landing zone, never projected into - so it would otherwise read as nine broken
// slots. An opaque plate covers it, and the reclaimed strip carries the category
// filters.
//
function yads_build_filters(_view, _menu, _pilot) {
    var _left_menu = _menu[$ "left_menu"];
    if (_left_menu == undefined) { return; }

    // 1. Neutralise the nine landing squares. lock() is the vanilla idiom for
    //    "this cell exists but must not be touched" (GridLayout locks its empty
    //    cells, anchor_utils.gml:925) and it is the single call that kills mouse
    //    hover AND pilot navigation at once: the hover gate is
    //    `listens_for_hovers && safe_unlocked` (Anchor.gml:377) and
    //    Pilot.position_is_valid returns node.safe_unlocked (Pilot.gml:298-307),
    //    so find_first_acceptable_node walks the whole row past. It also
    //    survives the lock/unlock cycle any popup inflicts on every other open
    //    menu, because set_unlocked keeps the personal `false` (Node.gml:578-592).
    //
    //    NOT disable(): ANCHOR.enable_node sets safe_enabled without consulting
    //    the parent (Anchor.gml:1620), so refresh_slot's nodes.item.enable()
    //    (InventoryMenu.gml:170) would resurrect the icon of a disabled square
    //    the moment an ESC-drop landed there.
    var _slots = _left_menu[$ "slots"];
    if (_slots == undefined) { return; }

    var _slot_count = array_length(_slots);
    for (var _s = YADS_PAGE_CELLS;
         _s < YADS_VIEW_SIZE && _s < _slot_count; _s++) {
        _slots[_s].square.lock();
    }

    var _canvas = _left_menu[$ "canvas"];
    if (_canvas == undefined) { return; }

    // 2. The plate. Geometry straight out of InventoryMenu.build's own slot
    //    placement: slot_x = (i mod 9) * 24 + 10, slot_y = (i div 9) * 24 + 10
    //    (INVENTORY_SLOT_SIZE 22 + INVENTORY_SLOT_PADDING 2), so row 6 occupies
    //    canvas-local x 10..224, y 130..152 while row 5 ends at y 128. 8,129 by
    //    218x24 clears row 5 by a pixel and bleeds two past the squares.
    //
    //    AnchorLayer.AboveFader, not a clever z. Layers are strictly stacked and
    //    each one that drew anything clears the depth buffer behind it
    //    (Anchor.gml:824, :1378-1380), so nothing in the Standard-layer storage
    //    menu can poke through - not even an item icon whose count badge sits at
    //    z 0 and which ANCHOR.enable_node just re-appended to the end of the
    //    render queue, which is precisely how a z-only plate loses a lessequal
    //    tie. AboveFader still renders BELOW Popup, so the drag hand and item
    //    tooltips keep drawing over the plate - which is what we want. Alpha and
    //    lifetime follow the parent chain regardless of the layer override
    //    (anchor_utils.gml:202-204, Anchor.gml:1695-1698), so the plate fades
    //    with the menu and is freed with it.
    var _plate = ANCHOR.nine_slice(_canvas, 50, AnchorLayer.AboveFader)
        .set_sprite(spr_ui_popup_box)
        .set_size(218, 24)
        .set_xy(8, 129);
    _view.filter_plate = _plate;

    // 3. Eight icon-only buttons at the vanilla banner's pitch -
    //    centered_positions(count, 22, 2) is exactly what StorageBanner.build
    //    uses (StorageMenu.gml:467), and Center/Middle alignment puts a 22px
    //    square in a 24px plate with the 1px margin already there.
    //
    //    common_slice hands us the whole spr_ui_generic_box state set in one
    //    call - enabled / hovered / tapped / locked / SELECTED - and points
    //    key_sprite_target at the node, so the engine's own per-frame sprite
    //    state machine (Anchor.gml:600-618) paints the active filter the moment
    //    is_selected() says so. That is the entire "pressed state" implementation:
    //    no think callback of ours, no second node.
    //
    //    Deliberately absent: add_glyph, because each one installs a think
    //    callback that taps its node on INPUT.take_press regardless of focus
    //    (Node.gml:1833-1839) and eight sharing one InputId would all fire
    //    together; and add_hover_outline, because the generic-box hovered sprite
    //    already IS the highlight.
    //
    //    Icons are resolved by string, fail-soft: try_string_to_asset returns
    //    undefined if a game update ever renames one, and spr_illegal_16 is the
    //    engine's own "this asset is missing" placeholder.
    //    THE BAR IS PAGED, and the mechanism is the whole design decision: the
    //    sixteen groups are shown eight at a time by ROTATING CONTENT through
    //    eight permanent buttons. Nothing is ever added to, removed from, enabled
    //    or disabled in this row after it is built.
    //
    //    The alternative - build sixteen and hide half - does not work here.
    //    There is no remove_from_pilot in the whole Node API (only add_to_pilot,
    //    Node.gml:496-504), and Pilot.position_is_valid returns node.safe_unlocked
    //    and never looks at safe_enabled (Pilot.gml:298-306), so a disabled button
    //    is an INVISIBLE STOP the stick still lands on. Eight buttons whose icon,
    //    tooltip key and selected-getter all resolve `cat_page * 8 + slot` cost
    //    one set_sprite each per flip - which early-outs when the asset is
    //    unchanged (Node.gml:1558-1564) - and touch the pilot exactly zero times.
    //
    //    Width check: 8 * 22 + 7 * 2 = 190 for the cluster, plus two 12px arrows
    //    pinned outside it = 214 of the plate's 218. The arrows are
    //    spr_ui_store_{left,right}_arrow (12x10) rather than the 5x10 scroller
    //    arrows the item pager uses - they are a registered button prefix so
    //    set_sprites_from_key resolves all six roles without a DEBUG_ASSERTIONS
    //    warn (anchor_utils.gml:2499-2501), they carry a real _locked frame, and
    //    two pagers wearing different art is a feature: nobody confuses the
    //    category pager with the item pager.
    _pilot.request_newline();   // idempotent; build() already left one pending

    // THE ARROWS CARRY THE OFF-PAGE FILTER STATE, and that is the only reason
    // they have a selected getter. Paging is presentational and the applied
    // filter deliberately does not move with it, so a player can narrow the grid
    // to Fish & Bugs on page 0, flip to page 1, and be looking at eight unlit
    // buttons over a grid that is still hiding most of the network with nothing
    // on screen saying why. Lighting the arrow that points at the active filter's
    // page restores the missing sentence without a ninth widget.
    //
    // set_sprites_from_key already pointed key_sprite_target at the node, so the
    // engine's own per-frame state machine (Anchor.gml:599-618) does the painting
    // the moment is_selected() says so - no think of ours. The store-arrow family
    // ships _main/_hovered/_tapped/_locked and NO _selected, and load_button_
    // sprites falls back selected -> _pressed -> _tapped (anchor_utils.gml:2513,
    // :2507-2509), so a lit arrow wears its tapped frame: distinct from _main,
    // and hover and tap still outrank it in the state machine's own order.
    _view.filter_prev = ANCHOR.sprite(_plate)
        .set_sprites_from_key("spr_ui_store_left_arrow")
        .set_align(Align.LeftIn, Align.Middle)
        .set_x(0)
        .set_bbox_offset(0, -3, 0, 6)
        .set_tap_sound("SoundEffects/UI/UIExtraPositiveClick")
        .set_tap_callback(yads_tap_cat_prev, [_view])
        .set_selected_getter(yads_cat_arrow_selected, [_view, -1])
        .add_to_pilot(_pilot);

    var _positions = centered_positions(YADS_FILTER_SLOTS, 22, 2);
    var _buttons = array_create(YADS_FILTER_SLOTS, undefined);
    var _icons = array_create(YADS_FILTER_SLOTS, undefined);

    for (var _s = 0; _s < YADS_FILTER_SLOTS; _s++) {
        // Both callbacks are baked with the SLOT index, never with a group: the
        // group is derived from the live cat_page every time they run, which is
        // what makes a page flip zero work for the pilot and zero work for the
        // engine's selection state machine.
        var _square = common_slice(_plate, 22, 22)
            .set_align(Align.Center, Align.Middle)
            .set_x(_positions[_s])
            .set_bbox_offset(0, 0, -2, -2)
            .set_tap_sound("SoundEffects/UI/UIExtraPositiveClick")
            .set_tap_callback(yads_tap_filter, [_view, _s])
            .set_selected_getter(yads_filter_selected, [_view, _s])
            .add_to_pilot(_pilot);

        _icons[_s] = ANCHOR.sprite(_square)
            .set_sprite(yads_filter_icon(
                yads_filter_group(_view, _s)))
            .set_align(Align.Center, Align.Middle);

        _buttons[_s] = _square;
    }

    _view.filter_next = ANCHOR.sprite(_plate)
        .set_sprites_from_key("spr_ui_store_right_arrow")
        .set_align(Align.RightIn, Align.Middle)
        .set_x(0)
        .set_bbox_offset(0, -3, 0, 6)
        .set_tap_sound("SoundEffects/UI/UIExtraPositiveClick")
        .set_tap_callback(yads_tap_cat_next, [_view])
        .set_selected_getter(yads_cat_arrow_selected, [_view, 1])
        .add_to_pilot(_pilot);

    _view.filter_buttons = _buttons;
    _view.filter_icons = _icons;

    // 4. The shared tooltip. Eight icon-only buttons are eight icons until
    //    something names them. One node names all SIXTEEN groups, because the
    //    key is resolved from the hovered slot's live group - which is also what
    //    makes a page flip cost the tooltip nothing.
    //
    //    ONE TextNode, for the eight FILTER BUTTONS AND NOTHING ELSE. An
    //    off-plate client - the auto-search toggle is the obvious candidate -
    //    would get its label rendered at the bottom of the menu describing a
    //    control at the top, and would tie its own state to this function having
    //    run at all; that toggle owns its own plate and poll instead
    //    (build_search_strip). The key is swapped to whichever button is hovered,
    //    exactly the way the sort button's label is swapped on every sort change.
    //    set_key early-outs when the key is unchanged (Node.gml:1007-1010), so
    //    the steady state costs one comparison.
    //
    //    Hung off the plate's TOP edge on the plate's own AboveFader layer
    //    (children inherit their parent's layer, Node.gml:56-60), so it draws
    //    over the slot row above it and can never be mistaken for an item icon.
    //    It CANNOT collide with a slot tooltip: those are Popup-layer menus that
    //    render strictly above AboveFader and to the LEFT (left_menu.
    //    tooltip_on_left, StorageMenu.gml:75), and the mouse cannot be over a
    //    slot and over a filter button at the same time anyway.
    //
    //    Disabled while nothing is hovered. The poll therefore must NOT live on
    //    this node - a disabled node does not think (Anchor.gml:374) and it
    //    could never turn itself back on - so it lives on the plate, which is
    //    always enabled and had no think callback of its own.
    //    SIXTEEN PIXELS TALL, NOT FOURTEEN, and the rule is the one this file
    //    already derives for the status fill bar: a nine-slice shorter than
    //    2 * frame_size draws its two border rows overlapped and its interior
    //    with a NEGATIVE height (Anchor.gml:896-901, `ch = node.height - h * 2`),
    //    which draw_sprite_stretched_ext renders as a vertically mirrored band
    //    across the middle of the box. spr_ui_tooltip_box is an 8x8 nine-slice,
    //    so 16 is its floor and 14 was two pixels under it. Both sizing sites
    //    have to agree - this one and the per-key resize in hint_think - or the
    //    first hover undoes the fix.
    //
    //    set_y(-4) rather than -2 keeps the visible gap over the filter plate at
    //    4px now that the box is 2px taller (TopOut resolves to
    //    round(y + parent.cache_y) - height, anchor_utils.gml:259-266, so the
    //    box's bottom edge sits |y| pixels above the plate's top edge).
    //
    //    IT DOES NOT CLEAR THE SLOT GRID, and no y value can. Slot row index 4
    //    occupies canvas-local y 106..128 (slot_y = (i div 9) * 24 + 10,
    //    InventoryMenu.gml:226) and this plate's parent starts at 129 - there is
    //    no gap between them to move into. So hovering a filter still covers the
    //    bottom of three squares on the last visible row. Accepted for the filter
    //    bar, whose label has to sit next to the buttons it names; the auto-search
    //    toggle, which had no such constraint and was borrowing this plate from
    //    the other end of the menu, got its own in build_search_strip instead.
    _view.hint_plate = ANCHOR.nine_slice(_plate)
        .set_sprite(spr_ui_tooltip_box)
        .set_size(60, 16)
        .set_align(Align.Center, Align.TopOut)
        .set_y(-4)
        .set_enabled(false);

    _view.hint_label = ANCHOR.text(_view.hint_plate)
        .set_lut(COMMON_LUT)
        .set_align(Align.Center, Align.Middle)
        .allow_line_breaks(false)
        .set_key(YADS_LOCAL_ROOT + "filter_farming");

    _plate.set_think_callback(yads_hint_think, [_view]);
}

//
// 2g. THE VALUE BADGES
//
// One TextNode per PAGE cell, showing what the stack under it is worth in
// tesserae. Built once, written from the projection, cycled off/stack/unit by
// the shelf toggle.
//
// IT HAS TO BE OUR OWN NODES. The slot's existing count badge is not text at
// all: item_node.count is a SpriteNode over spr_ui_hud_item_count_baked_text, a
// 1000-frame sheet of pre-rendered integers selected with set_index
// (anchor_utils.gml:1652-1657, :1669). There is no string in it to overwrite.
//
// PARENTED TO nodes.item, NOT nodes.square, and three separate things fall out
// of that for free:
//
//   * z. A child defaults to parent.z - 1. The item icon is 49, so the badge
//     lands at 48 - in front of the icon, behind the count badge and the
//     sub-icon (both set_z(0)). A square-parented badge would default to 49,
//     tie with the icon, and lose the cmpfunc_lessequal tie every time
//     refresh_slot re-appended the icon to the render queue.
//   * Visibility. refresh_slot disables nodes.item on an empty slot
//     (InventoryMenu.gml:165-167) and the cascade takes the badge with it. The
//     re-enable cascade passes personal = false (Anchor.gml:1628-1630), so a
//     badge comes back only if ITS OWN flag is true - which is exactly what the
//     user toggle writes.
//   * Alpha. cache_alpha multiplies through the parent
//     (anchor_utils.gml:203), so the badge dims with a soft-locked slot and with
//     this mod's own no-room shading without a line of code.
//
// FORTY-FIVE, NOT FIFTY-FOUR. Rows 1-5 only: row 6 lives under the filter
// plate, which is on AnchorLayer.AboveFader, and layers are strictly stacked
// with a depth clear between them - a badge down there could never be seen.
//
// A 5x7 SPRITE FONT, not currency's 8x10: 4px digits against 7px. Five digits is
// 20px in the small font and 35px in currency, and the slot is 22px wide.
// Vanilla makes the same choice for a tesserae price over an item icon
// (CraftingMenu.gml:395-404), and that call site is also why there is no LUT
// here - it pairs the small font with none.
//
// TOP-RIGHT, because it is the only free corner: the count badge owns
// RightIn/BottomIn and the infusion sub-icon owns LeftIn/BottomIn
// (anchor_utils.gml:1653, :1660).
//
// THE FONT IS OURS, AND IT HAD TO BE. The badge abbreviates - 1234 -> "1.2k",
// 9999999 -> "9.9m" - and the vanilla font cannot spell that.
// `item_count`'s order is "0123456789./+"
// (fonts/sprite_fonts.toml:187-202): THIRTEEN GLYPHS, NO LETTERS. The
// sprite-font draw loop skips any character it cannot find in `order` WITHOUT
// ADVANCING x_off (Anchor.gml:1090-1107) and sprite_font_width scores that same
// character `?? 0` (anchor_utils.gml:2533-2545), so "1.2k" would have drawn as
// "1.2" AND measured as "1.2": a badge reading 1.2 tesserae over a stack worth
// 1200. Not a clipped number - a WRONG one, silently, with nothing anywhere in
// the engine raising a hand. No other shipped sprite font has a `k` or an `m`
// either (every letter in the whole of sprite_fonts.toml: currency/skill/
// player_level `x`, medium_2 `LVNIxУР`, price `S`, damage_numbers `p`, and
// aldarian's 25 uppercase `ABCDEFGHIJKLMNOPRSTUVWXYZ` - which has no lowercase
// and, being the rune alphabet, no digits at all, so it could not spell "1.2k"
// even with a `k` in it), and the standard text font, which has both, is 6px per
// digit - so its "999k" is 24px where our whole slot is 22.
//
// So: `netstor_count`, resolved by exactly the same path as any vanilla name.
// load_sprite_fonts() (Fonts.gml:4-31) walks EVERY top-level key of
// fiddle_get("fonts/sprite_fonts") at boot (Setup.gml:125) into
// SPRITE_FONTS[$ key], and set_sprite_font is a plain lookup in that struct
// (Node.gml:984-991) - it knows nothing about where a key came from. MOMI merges
// our one-key mod file into the game's own sprite_fonts.toml by path
// (TOMLInstaller.InstallGenericToml -> Installer.DestinationPath = "assets/" +
// the mod-relative path), and that destination contains no [[table arrays]] at
// all, so the Tomlyn re-open hazard that shadows the crafting-menu merge cannot
// apply. The strip is spr_ui_hud_font_netstor_count: vanilla's thirteen 5x7
// cells transcribed pixel for pixel plus `k` and `m` in the same 3x5-core,
// 4-neighbour-outline style. make_art.py owns both the pixels and the advance
// table and gates them together; see THE SPRITE FONT there.
//
// THE COIN. spr_ui_crafting_tesserae_icon, 7x7, is the game's own
// inline "this number is tesserae" glyph and the only one authored to sit beside
// this text - the font's cell is 5x7, so the two are an exact height match and
// vanilla pairs them with no y nudge at all (CraftingMenu.gml:396-404). It
// hangs off the badge as a CHILD at LeftOut/Middle, which is what makes the pair
// right-align as one unit without a measurement of ours: LeftOut resolves to
// round(x + parent.cache_x) - node.width (anchor_utils.gml:216-222) and the
// badge's own cache_x is already the RightIn result, so the coin tracks every
// digit the number gains or loses. Middle centres a 7px sprite against a 7px
// node - a sprite-font TextNode's height is sprite_get_height of the font sheet
// (Node.gml:1116-1120), not a line height.
//
// IS OUR FONT ACTUALLY IN THE TABLE? The one question the two sprite-font calls
// below are not allowed to ask by trying.
//
// set_sprite_font (Node.gml:984-988) and sprite_font_width (anchor_utils.gml:
// 2533-2537) both end in `assert_neq(..., "SpriteFont `{}` does not exist", ...)`.
// assert_neq is a fabricator runtime builtin defined nowhere in the corpus, so its
// failure mode is not inspectable from GML and "it throws" is the only conservative
// reading. That matters here more than anywhere else in the file: open_view spawns
// the Menu.Storage at :137 and stamps it at :153, and registers _rt.view LAST at
// :222-230 precisely so a failure leaves garbage rather than a lock-out - but a
// throw at :170 lands between those, leaving a LIVE, fully interactive storage menu
// whose left inventory is the synthetic mirror with no reconciler attached to it
// (menu_closed bails on _rt.view == undefined, the tick never reconciles), and
// anything the player drags into that mirror dies when the menu frees. The mirror's
// custody-less guarantee holds only while a reconciler is behind it.
//
// The precondition is the GML installed while fiddle/fonts/sprite_fonts.toml did
// not merge, which no realistic MOMI path produces (a lint failure excludes the mod
// wholesale, TOMLInstaller runs every collected TOML in one pass, Uninstall restores
// the pristine zip). It is a mod-supplied font name, though, where a vanilla one
// would always resolve - so the class of failure exists, and four lines buy the
// whole of it back.
//
// Read as global[$ ] rather than through the SPRITE_FONTS macro because the table
// is genuinely undefined until Setup.gml:125 runs load_sprite_fonts(), and the same
// [$ ]-guarded global read is what the glow rescan uses for __STORAGE_NODES.
function yads_badge_font_ready() {
    var _fonts = global[$ "sprite_fonts"];
    if (_fonts == undefined) { return false; }
    return _fonts[$ YADS_BADGE_FONT] != undefined;
}

function yads_build_badges(_view, _menu) {
    // No font, no badges - and no throw. value_badges stays the empty array the
    // view was born with, badge_slot's bounds test declines every write, and the
    // panel opens with everything else intact.
    if (!yads_badge_font_ready()) { return; }

    // The same three defensive reads build_filters makes, for the same reason: a
    // game update renaming a vanilla field must cost a feature, not the panel.
    var _left_menu = _menu[$ "left_menu"];
    if (_left_menu == undefined) { return; }

    var _slots = _left_menu[$ "slots"];
    if (_slots == undefined) { return; }

    var _count = min(YADS_PAGE_CELLS, array_length(_slots));
    var _badges = array_create(_count, undefined);
    var _coins = array_create(_count, undefined);

    for (var _s = 0; _s < _count; _s++) {
        var _item_node = _slots[_s][$ "item"];
        if (_item_node == undefined) { continue; }

        var _badge = ANCHOR.text(_item_node)
            .set_sprite_font(YADS_BADGE_FONT)
            .set_align(Align.RightIn, Align.TopIn)
            // y = -2 lifts the number clear of the icon's own top edge. The
            // badge is a 7px-tall sprite-font node hard against TopIn, so at
            // y = 0 its lowest glyph row overlapped the tallest item sprites
            // and the digits read against artwork rather than against the
            // slot. Two pixels is the whole of the overlap and still leaves
            // the badge inside the square: RightIn/TopIn resolve against
            // nodes.item, which is inset within the 22px slot.
            //
            // ACCEPTED COSMETIC EDGE, measured, so nobody re-derives it as a
            // bug: -2 lands the badge FLUSH with the slot border, not clear of
            // it. The slot is a 22px nine-slice (InventoryMenu.gml:3, :229-230)
            // and item_node is centred in it, so an 18x18 icon - which is what
            // 3375 of the game's 3381 item frames are, and what all of ours
            // are - starts at square_top + 2 and the badge's top glyph row sits
            // at square_top + 0, on the spr_ui_generic_box border art. The one
            // 20x20 frame in the whole archive
            // (spr_ui_item_wearable_underwear_shorts_polkadot) puts it at
            // square_top - 1, one pixel outside; there is no scissor in the
            // nine-slice path to clip it. Owner asked for the two pixels and
            // the readability is worth it. -1 would buy the border back.
            .set_xy(1, -2)
            .set_text("")
            .set_enabled(false);

        // The coin, parented to the number rather than to the slot: see the note
        // above for why LeftOut off the badge is what right-aligns the pair. -1
        // is the gap, since LeftOut puts this node's RIGHT edge on the parent's
        // left edge before x is applied.
        _coins[_s] = ANCHOR.sprite(_badge)
            .set_sprite(spr_ui_crafting_tesserae_icon)
            .set_align(Align.LeftOut, Align.Middle)
            .set_x(-1)
            .set_enabled(false);

        _badges[_s] = _badge;
    }

    _view.value_badges = _badges;
    _view.value_coins = _coins;
}

// How a tesserae value is spelled on a 22px-wide badge.
//
//   <= 999      verbatim                     999      -> "999"
//   1000-9999   one decimal, ".0" trimmed    1234     -> "1.2k",  1099 -> "1k"
//   10k-999k    whole thousands              123456   -> "123k"
//   >= 1e6      one decimal, ".0" trimmed    1234567  -> "1.2m",  1e6  -> "1m"
//   >= 1e7      whole millions               12345678 -> "12m"
//
// The last rule is not in the original spec and is a WIDTH guard, not a
// rounding one: without it 12345678 spells "12.3m", five glyphs and 18px, wider
// than the 16px worst case every other branch is bounded by. It cannot make a
// number wrong - it is still the same floor - and it is unreachable in practice
// anyway (999 of the priciest item in the game does not approach 1e7).
//
// FLOOR EVERYWHERE, never round. A value badge that says "1k" over a stack worth
// 1099 understates by less than one unit of its own suffix; one that rounded
// would say "1k" over 999 and "10k" over 9501, i.e. it would claim a threshold
// the stack has not crossed. Understating within the suffix is a display
// convention; overstating is a lie about the player's money.
//
// INTEGER ARITHMETIC ONLY - div and mod, never a division that produces a real.
// The two parts of "1.2k" are built as separate integers and concatenated,
// because string(real) in this engine is not guaranteed to give one decimal
// place and a badge that renders "1.20000001k" would be dropped glyph by glyph
// by a font that has no more digits to give.
//
// _v DOES NOT ARRIVE INTEGRAL, and the floor at the top of this function is not
// defensive - it is load-bearing. bin_value() is NOT integral by construction:
// LiveItem.gml:238-249 rounds only the INFUSION term, and the base it adds that
// to is prototype.value.bin, which Items.gml:7-15 defaults to `store * 0.5`
// whenever a prototype ships no explicit bin. Twenty-one vanilla items have an
// odd `store` and no `bin` - every 175g cooked dish, mocha at 275, seed_celosia
// at 15, seed_cucumber at 25 - so their bin is a genuine `.5` real. A stack of
// Deviled Eggs reached the `_v < 1000` arm as 87.5 and this function returned
// string(87.5): a badge reading "87.50", five glyphs and 18px, in a place whose
// stated ceiling is four glyphs and 16px, and disagreeing with the tooltip on
// the same cell (which strips the trailing zero through num_display,
// TooltipMenu.gml:80). The magnitude was never wrong; the invariant was.
//
// Flooring here rather than at the two call sites keeps ONE rule for the whole
// family: every branch below already floors (div truncates), so flooring the
// input makes "floor everywhere" true of the function as a whole and leaves no
// arm that has to think about it. It is also the conservative direction - see
// FLOOR EVERYWHERE above.
//
// WHAT IT COSTS, stated for the case that actually occurs. Half a tessera per
// ITEM, which the per-item badge shows and nobody can see; but the stack badge
// multiplies the floored unit by the count (see badge_slot), so the understatement
// is 0.5 x count, up to 499.5 on a 999-stack - and that is enough to move the
// printed suffix digit: 999 Deviled Eggs show floor(87.5) x 999 = 86,913 -> "86k"
// where the true stack value is 87.5 x 999 = 87,412.5 -> "87k". So this is a
// suffix-digit-sized trade, not a rounding crumb. It is still the right trade -
// the stack badge is always exactly the per-item badge times the count, which is
// the only property a player can check by eye.
//
// The affected prototypes are the 21 vanilla odd-`store`/no-`bin` items above PLUS
// one of our own: netstor_set.toml gives netstor_heart
// `value = { bin = "self.recipe * 1.1" }`, an expression with no integrality
// guarantee at all.
//
// The negative clamp is insurance, not a case: nothing in the game produces a
// negative bin_value. But `-` is not in the font's order, so a negative would be
// drawn and measured with the sign silently dropped - "-5" reading as "5" - and
// that is the exact failure mode this whole change exists to remove. Clamping
// to 0 is visibly wrong instead of invisibly wrong. It runs BEFORE the floor, so
// a hypothetical -0.5 clamps to 0 rather than flooring to -1.
function yads_abbrev_value(_v) {
    if (_v < 0) { _v = 0; }
    _v = floor(_v);

    if (_v < 1000) { return string(_v); }

    if (_v < 10000) {
        var _whole = _v div 1000;
        var _tenth = (_v div 100) mod 10;
        if (_tenth == 0) { return string(_whole) + "k"; }
        return string(_whole) + "." + string(_tenth) + "k";
    }

    if (_v < 1000000) { return string(_v div 1000) + "k"; }

    if (_v < 10000000) {
        var _mwhole = _v div 1000000;
        var _mtenth = (_v div 100000) mod 10;
        if (_mtenth == 0) { return string(_mwhole) + "m"; }
        return string(_mwhole) + "." + string(_mtenth) + "m";
    }

    return string(_v div 1000000) + "m";
}

// Write one badge, from the projection's slot loop, with the same _cell that
// just went into the slot. _cell == undefined means "this slot is empty".
//
// A STRING, never the raw number: set_text runs num_display() on a real
// (Node.gml:1040-1042), which inserts thousands separators - and the badge
// font's order has no comma, so the renderer would skip the character without
// advancing x_off (Anchor.gml:1092-1107) and the output would be right BY
// ACCIDENT. abbrev_value returns a string for exactly this reason.
//
// bin_value(), never the row's cached value.bin: the row caches the raw
// prototype number because SORTING must not re-run perk lookups per comparison,
// but bin_value() adds the Quality infusion bonus and the two BackInVogue
// archaeology perks (LiveItem.gml:238-249). The tooltip this very slot pops
// shows bin_value() (TooltipMenu.gml:80), and two numbers on one cell that
// disagree is worse than no number. 45 calls per projection, not per comparison.
//
// bin and not store: bin_value() is what selling pays (EodMenu.gml:976-987),
// store_value() is what a shop would CHARGE for an item the player already owns.
function yads_badge_slot(_view, _index, _cell) {
    var _badges = _view[$ "value_badges"];
    if (_badges == undefined) { return; }
    if (_index < 0 || _index >= array_length(_badges)) { return; }

    var _node = _badges[_index];
    if (_node == undefined) { return; }

    // The coin rides the badge and is switched separately - it is dropped
    // whenever the number is too wide for the two of them to share the slot.
    var _coins = _view[$ "value_coins"];
    var _coin = undefined;
    if (_coins != undefined && _index < array_length(_coins)) { _coin = _coins[_index]; }

    // Off, or nothing in the slot: clear and hide. The disable is PERSONAL, so
    // the engine's own re-enable cascade will not bring a switched-off badge
    // back when the slot refills. The coin needs no disable of its own here:
    // disable_node recurses into every enabled child with personal = false
    // (Anchor.gml:1653-1658), which hides it while leaving its own flag for the
    // show path below to overwrite.
    var _mode = yads_config().value_mode;
    if (_cell == undefined || _mode == YADS_VALUE_OFF) {
        _node.set_text("");
        _node.set_enabled(false);
        return;
    }

    // floor() on BOTH arms, not just on the way into abbrev_value, because the
    // multiply is where a half-tessera stops being invisible: bin_value() can be
    // a genuine `.5` (Items.gml:7-15 defaults value.bin to store * 0.5, and 21
    // vanilla prototypes have an odd store, as does our own netstor_heart), and
    // 87.5 x 7 is 612.5 while floor(87.5) x 7 is 609. Flooring the UNIT first is
    // the honest one - it is the number the per-item mode shows, so seven of them
    // must be seven times what one of them says, and a stack badge that does not
    // agree with its own per-item badge is worse than either being half a tessera
    // light.
    //
    // AT A FULL STACK THAT IS NOT A CRUMB. The gap is 0.5 x count, so 999 Deviled
    // Eggs read 86,913 -> "86k" against a true 87,412.5 -> "87k": under one suffix
    // unit in absolute terms, but a whole printed digit. Consistency is still worth
    // it; a 7-stack is just not the case to quote when saying what it costs.
    // abbrev_value floors again on entry; that is belt and braces, not a second
    // opinion, and it is what makes this function's arithmetic checkable on its
    // own.
    var _unit = floor(_cell.item.bin_value());
    var _value = (_mode == YADS_VALUE_STACK)
        ? _unit * _cell.count
        : _unit;

    // 22px slot minus the 7px coin and its 1px gap. The arithmetic is unchanged
    // by the abbreviation - the slot and the coin did not move - but WHICH
    // badges pass it did, so it is re-derived here rather than inherited.
    //
    // Measured, not counted. sprite_font_width sums the font's real advances
    // (anchor_utils.gml:2533-2545), and in netstor_count '1' is 3px and '.' is
    // 2px where every other glyph a badge can emit - the other digits, 'k' and
    // 'm' - is 4px. So the gate is a pixel budget, not a character limit, and it
    // lands like this (the table is make_art.py's, printed on every art run):
    //
    //   "999"  12px  coin      "1.2k" 13px  coin      "9.9k" 14px  coin
    //   "1k"    7px  coin      "10k"  11px  coin      "9.9m" 14px  coin
    //   "123k" 15px  no        "999k" 16px  no        "999m" 16px  no
    //
    // The abbreviation's real win is the CEILING: every badge is at most 4
    // glyphs and 16px, where an unabbreviated number can be six digits and 24px
    // of text over a 22px slot. 16 + 7 + 1 = 24 is the worst case for the pair,
    // so even a coin-bearing badge overhangs by at most a pixel each side into
    // the 2px inter-slot gap - and by construction it never does, because
    // anything that wide has already dropped its coin.
    //
    // THE CEILING IS THE FLOOR'S: it holds only because every value reaching
    // abbrev_value is an integer. It is not one by nature - see the note over
    // that function - and without the floors, 21 vanilla item kinds can put
    // "87.50" (5 glyphs, 18px) or, per stack, "962.50" (6 glyphs, 22px) into
    // this slot. Both floor() calls in this file exist to make the sentence
    // above true rather than merely intended.
    static COIN_TEXT_MAX = 14;

    // Text before enable, so a badge coming back on never shows one frame of the
    // previous slot's number.
    var _text = yads_abbrev_value(_value);
    _node.set_text(_text);
    _node.set_enabled(true);

    // AFTER the badge, never before: enable_node does not consult the parent
    // (Anchor.gml:1603-1633), so enabling a child while its parent is disabled
    // puts the child in the render queue with an uncomputed cache - the same
    // GUI-origin ghost the first-frame refresh() in open_view exists to avoid.
    // Enabling the badge first also runs the re-enable cascade, which this line
    // then corrects to whatever the width test wants.
    //
    // The SAME font name that drew it. Measuring a string in one font and
    // drawing it in another is how a badge silently disagrees with itself, so
    // both sites read the one macro.
    //
    // And the same font-table guard build_badges takes, because sprite_font_width
    // carries the identical assert_neq (anchor_utils.gml:2533-2537). Unreachable
    // today - a missing font means build_badges returned before any coin existed,
    // so _coin is undefined and this branch never runs - but the two sprite-font
    // call sites are guarded independently, so that neither one's safety depends
    // on the other's reasoning surviving an edit.
    if (_coin != undefined) {
        if (!yads_badge_font_ready()) {
            _coin.set_enabled(false);
        } else {
            _coin.set_enabled(
                sprite_font_width(_text, YADS_BADGE_FONT)
                    <= COIN_TEXT_MAX);
        }
    }
}

// Which of the sixteen groups a physical button is offering right now. The one
// place the page arithmetic is written; every other site asks this.
//
// Modulo FILTER_LEN, which is a no-op on the shipping numbers (2 pages * 8 slots
// lands exactly on 0..15) and is the whole enforcement of the invariant stated
// over the macros. It is what makes FILTER_LEN a real bound rather than a
// comment: grow the taxonomy past what SLOTS * PAGES covers and the surplus
// buttons wrap onto real groups - wrong content, but every icon, every tooltip
// key and every filter_match arm still resolves - instead of indexing past the
// ICONS table into spr_illegal_16 with a label switch falling through.
function yads_filter_group(_view, _slot) {
    return (_view.cat_page * YADS_FILTER_SLOTS + _slot)
        mod YADS_FILTER_LEN;
}

// Repaint the eight buttons for the current page. Called from the tick, and only
// from there, when a page request lands - build_filters paints page 0 itself
// through the same filter_group + filter_icon pair.
//
// set_sprite early-outs on an unchanged asset (Node.gml:1558-1564), and the
// tooltip and the selection highlight need no repaint at all: both resolve the
// group through yads_filter_group every frame anyway - the
// tooltip from the plate's think, the highlight from the engine's own sprite
// state machine polling our selected getter (Anchor.gml:600-618).
function yads_refresh_filter_bar(_view) {
    var _icons = _view.filter_icons;
    if (_icons == undefined) { return; }

    for (var _s = 0; _s < array_length(_icons); _s++) {
        if (_icons[_s] == undefined) { continue; }
        _icons[_s].set_sprite(yads_filter_icon(
            yads_filter_group(_view, _s)));
    }
}

// Group -> icon asset. 14x14 (store/crafting) and 14x13 (almanac) single-frame
// UI-atlas sprites; none of those families has the _hovered/_selected siblings
// set_sprites_from_key wants, so they go on as a plain child sprite over a
// generic_box square (the same two-node shape the almanac uses,
// AlmanacMenu.gml:47-50).
//
// Sixteen entries: All, the fourteen sort buckets in bucket order, and the
// museum lens. The two-state museum pair is the same one the item tooltip
// switches on (TooltipMenu.gml:172-175), so a player who has hovered an item
// already knows what it means; _off - "the museum still wants this" - is the
// right face for a filter that finds exactly those.
function yads_filter_icon(_group) {
    static ICONS = [
        "spr_ui_crafting_category_icon_all",        //  0 All
        "spr_ui_store_category_icon_tools",         //  1 Tools
        "spr_ui_store_category_icon_weapons",       //  2 Weapons and armour
        "spr_ui_store_category_icon_seeds",         //  3 Seeds and saplings
        "spr_ui_journal_almanac_icon_crops",        //  4 Crops and forage
        "spr_ui_store_category_icon_fish",          //  5 Fish and bugs
        "spr_ui_journal_almanac_icon_ranching",     //  6 Animal products
        "spr_ui_store_category_icon_cooked_dishes", //  7 Food and drink
        "spr_ui_journal_almanac_icon_blacksmithing",//  8 Ores, gems, ingots
        "spr_ui_store_category_icon_materials",     //  9 Materials
        "spr_ui_journal_almanac_icon_artifacts",    // 10 Artifacts and replicas
        "spr_ui_store_category_icon_furniture",     // 11 Furniture and decor
        "spr_ui_store_category_icon_objects",       // 12 Flooring and wallpaper
        "spr_ui_store_category_icon_cooking_recipes",// 13 Scrolls and unlocks
        "spr_ui_store_category_icon_misc",          // 14 Everything else
        "spr_ui_generic_icon_museum_off",           // 15 Museum needs
    ];

    if (_group < 0 || _group >= array_length(ICONS)) { return spr_illegal_16; }

    // Resolved by string, fail-soft: try_string_to_asset returns undefined if a
    // game update ever renames one, and spr_illegal_16 is the engine's own
    // "this asset is missing" placeholder.
    var _asset = try_string_to_asset(ICONS[_group]);
    if (_asset == undefined) { return spr_illegal_16; }
    return _asset;
}

// Group -> tooltip key. Eleven of the sixteen names already exist, translated
// into every shipped language, in the game's own misc_local table - reading a
// vanilla key is free, while WRITING to misc_local.toml would be a merge into a
// 629-key shared file and is forbidden. The five whose wording is ours live in
// the mod's own ui.toml.
//
// ui.toml also carries filter_farming, which nothing here resolves: it named a
// coarser group in an older taxonomy. It stays as a harmless orphan rather than
// being deleted out from under a translation that may already exist.
function yads_filter_label_key(_group) {
    switch (_group) {
        case 1: return "misc_local/tools";
        case 2: return "misc_local/equipment";
        case 3: return YADS_LOCAL_ROOT + "filter_seeds";
        case 4: return YADS_LOCAL_ROOT + "filter_crops";
        case 5: return YADS_LOCAL_ROOT + "filter_fish_bugs";
        case 6: return "misc_local/ranching";
        case 7: return "misc_local/food";
        case 8: return "misc_local/blacksmithing";
        case 9: return "misc_local/materials";
        case 10: return "misc_local/artifacts";
        case 11: return "misc_local/furniture";
        case 12: return YADS_LOCAL_ROOT + "filter_flooring";
        case 13: return YADS_LOCAL_ROOT + "filter_scrolls";
        case 14: return "misc_local/other";
        case YADS_FILTER_MUSEUM:
            return YADS_LOCAL_ROOT + "filter_museum";
    }
    return "misc_local/all_items";   // group 0, and any unknown group
}

// The toggle describes its own CURRENT state rather than the action it would
// perform: "Auto-search: on" reads as a status when you are hovering to check,
// and as a promise you can break when you are hovering to change it. Both
// readings are correct; "Turn auto-search off" only has the second.
function yads_autosearch_label_key() {
    return YADS_LOCAL_ROOT
        + (yads_config().auto_search ? "autosearch_on" : "autosearch_off");
}

// The toggle's glyph: the UI atlas's own magnifying glass.
//
// PLAIN set_sprite ON A PLAIN CHILD, not set_sprites_from_key on the button.
// spr_ui_generic_renown_magnify_icon_* is a complete enabled/hovered/locked/
// tapped family, but it is NOT listed in button_sprite_prefixes, so
// set_sprites_from_key would log a warn under DEBUG_ASSERTIONS
// (anchor_utils.gml:2499-2501) on every menu open. It is also not needed: the
// common_slice box underneath already carries every hover/tap/selected state,
// and this glyph only has to say which way the setting is set.
//
// enabled for on, locked for off - the family's own bright/greyed pair, which is
// the same visual grammar every locked button in the game uses. Resolved through
// try_string_to_asset with the generic checkbox pair as a fallback, because
// these are assets this mod names but does not ship: a rename in a game update
// should cost the icon, not the mod.
function yads_autosearch_icon() {
    var _on = yads_config().auto_search;

    var _asset = try_string_to_asset(_on
        ? "spr_ui_generic_renown_magnify_icon_enabled"
        : "spr_ui_generic_renown_magnify_icon_locked");
    if (_asset != undefined) { return _asset; }

    return _on ? spr_ui_generic_checkbox_on : spr_ui_generic_checkbox_off;
}

// The value toggle's glyph: one asset for all three states, because the lit
// generic box says "on" and the tooltip says which of the two on-states. 14x14,
// an exact fit for the 16px square - it is the EOD summary's own tesserae header
// icon, the game's biggest and clearest "this is about money" glyph.
function yads_value_icon() {
    var _asset = try_string_to_asset("spr_ui_eod_summary_tesserae_header_icon");
    if (_asset == undefined) { return spr_illegal_16; }
    return _asset;
}

// The toggle describes its CURRENT state, exactly like the auto-search one:
// "Values: stack totals" reads as a status when you are checking and as a
// promise you can break when you are about to change it.
function yads_value_label_key() {
    switch (yads_config().value_mode) {
        case YADS_VALUE_STACK:
            return YADS_LOCAL_ROOT + "value_stack";
        case YADS_VALUE_UNIT:
            return YADS_LOCAL_ROOT + "value_unit";
    }
    return YADS_LOCAL_ROOT + "value_off";
}

//
// 3. WIDGET CALLBACKS - request recorders only
//
function yads_tap_prev(_view) {
    yads_request_page(_view, _view.page - 1);
}

function yads_tap_next(_view) {
    yads_request_page(_view, _view.page + 1);
}

// The one request recorder that ALSO writes a file, because the sort order is
// both view state and a preference. The request half is untouched - the tick is
// still what applies it, resets the page, dirties the projection and repaints
// the label, and it is still the only writer of _view.sort_mode.
//
// THE REQUEST IS WHAT GETS PERSISTED, not _view.sort_mode: the tick has not run
// yet, so sort_mode is still the OLD mode here and writing it would save the
// order the player just cycled away from.
//
// ACCEPTED, because the alternative is worse: tap sort and close the panel on
// the SAME frame and the file keeps a mode the grid never rendered - the tick
// returns at its closing guard (boot.gml section 3b) before it ever reaches the
// request block. One cycle step at worst, and self-consistent on the next open,
// which is the only place the number is read. Deferring the write to the tick
// instead would lose the preference outright on that same frame.
function yads_tap_sort(_view) {
    if (_view.closing == true) { return; }
    _view.sort_request = wrap(_view.sort_mode + 1, YADS_SORT_LEN);

    var _cfg = yads_config();
    _cfg.sort_mode = _view.sort_request;

    mmapi_config_write(YADS_MOD,
        YADS_CONFIG_VERSION, _cfg);
}

// Tapping the ACTIVE group clears back to All. Every player expects a
// single-select filter bar to be dismissable by clicking the lit button again,
// and the alternative - hunting for the All button - is a worse default than a
// harmless double-tap. Tapping All is idempotent.
//
// Takes the SLOT, not the group: the button was baked once and the page moves
// under it, so the group has to be resolved at tap time or every flip would have
// to rewrite eight callbacks.
function yads_tap_filter(_view, _slot) {
    if (_view.closing == true) { return; }

    var _group = yads_filter_group(_view, _slot);
    _view.filter_request = (_view.filter == _group)
        ? YADS_FILTER_ALL
        : _group;
}

// Read every frame by the engine's sprite state machine (Anchor.gml:600-618)
// via Node.is_selected. Reads the APPLIED filter, not the pending request, so
// the highlight and the grid contents always describe the same frame - and
// resolves the slot's current group, so the lit button follows the page without
// any repaint of ours.
function yads_filter_selected(_view, _slot) {
    return (_view.filter == yads_filter_group(_view, _slot));
}

// "The active filter lives that way." Read every frame by the same sprite state
// machine, off the two page arrows, with _step -1 for the left one and +1 for the
// right. True only when a NARROWING filter is applied and its button is on
// another page - the state that would otherwise be reported by nothing at all.
//
// All is excluded on purpose. It is the resting state of every session, the grid
// under it is not narrowed, and lighting both arrows for it would make the lit
// arrow mean "you have paged away" rather than "something is hidden from you".
//
// With FILTER_PAGES == 2 the two directions land on the same page and both arrows
// light, which is honest: either one gets you there. The wrap keeps that true for
// any page count without special-casing the two-page layout it ships with.
function yads_cat_arrow_selected(_view, _step) {
    if (_view.filter == YADS_FILTER_ALL) { return false; }

    var _home = _view.filter div YADS_FILTER_SLOTS;
    if (_home == _view.cat_page) { return false; }

    return (wrap(_view.cat_page + _step, YADS_FILTER_PAGES) == _home);
}

// The category bar's two page arrows. Both wrap, like the item pager's, because
// with two pages a non-wrapping arrow would be dead half the time and would need
// lock()/unlock() churn on every flip to say so honestly.
function yads_tap_cat_prev(_view) {
    if (_view.closing == true) { return; }
    _view.cat_page_request = wrap(_view.cat_page - 1, YADS_FILTER_PAGES);
}

function yads_tap_cat_next(_view) {
    if (_view.closing == true) { return; }
    _view.cat_page_request = wrap(_view.cat_page + 1, YADS_FILTER_PAGES);
}

// The value-badge cycle: off -> stack -> unit -> off. Like the auto-search
// toggle and unlike every other widget in this file, it writes its state
// straight through rather than recording a request, because that state is a
// FILE, not view state - there is nothing for the tick to serialise and the
// setting should survive an alt-F4 taken one second later.
//
// What it does hand the tick is project_dirty: the badges are written from the
// projection's own slot loop, so one re-projection is what repaints all 45 of
// them with the new mode. That keeps the badge write in exactly one place.
function yads_tap_value(_view) {
    if (_view.closing == true) { return; }

    var _cfg = yads_config();
    _cfg.value_mode = wrap(_cfg.value_mode + 1, YADS_VALUE_LEN);

    mmapi_config_write(YADS_MOD,
        YADS_CONFIG_VERSION, _cfg);

    _view.project_dirty = true;
}

// Lit whenever badges are showing at all. Takes no view: the setting is global,
// not per-view, exactly like the auto-search getter beside it.
function yads_value_selected() {
    return (yads_config().value_mode != YADS_VALUE_OFF);
}

// The value toggle's own poll, on the toggle's own node - the same two jobs and
// the same reasoning as the auto-search toggle's think: keep the label honest,
// and show it only while the button is hovered. The icon never changes, so
// unlike auto-search there is no glyph to swap.
function yads_value_think(_view) {
    if (_view.closing == true) { return; }

    var _plate = _view.value_hint_plate;
    var _label = _view.value_hint_label;
    var _toggle = _view.value_button;
    if (_plate == undefined || _label == undefined || _toggle == undefined) { return; }

    if (!_toggle.is_hovered()) {
        _plate.set_enabled(false);
        return;
    }

    // Measure then size, like every other tooltip here: the label is the plate's
    // child and centred in it, so sizing first would move the text it was
    // measured against. 16 is the 8x8 nine-slice floor and must match the
    // creation site.
    _label.set_key(yads_value_label_key());
    _plate.set_size(_label.measure().x + 10, 16);
    _plate.set_enabled(true);
}

function yads_tap_search(_view) {
    if (_view.closing == true) { return; }
    var _node = _view.search_node;
    if (_node == undefined) { return; }

    // Already focused: do nothing. set_takes_input has no idempotence check of
    // its own (Node.gml:1168-1177) - it re-runs start_text_input(), resets the
    // cursor timer, and on a Deck or in Big Picture calls steam_open_textbox()
    // AGAIN. Clicking into a box you are already typing in must not re-summon
    // the on-screen keyboard over the query you were halfway through.
    //
    // The test is OUR flag, not node.takes_input, which is false for the whole
    // time the box has focus - see yads_search_focus.
    if (_view.editing == true) { return; }

    yads_search_focus(_view);
}

// The clear X. Empties the box and leaves the editor in the state a fresh focus
// would: caret at 0, no selection, caret solid.
//
// IT DOES NOT TOUCH _view.query, AND MUST NOT. The query is polled off the text
// node by the tick (boot.gml section 3d), which is the single place that decides
// the view has a new filter and re-projects - so writing set_text("") here is
// the whole change, and the grid comes back on the next frame through the same
// path a keystroke uses. A second writer here would race the poll and could
// re-project against a string the node no longer holds.
//
// It does not blur, and it does not focus either: whichever side of focus the
// player was on is where they stay. That is not a property of parentage - see
// the geometry note over the button in build_search_strip - it is held up by
// the trimmed hitbox and by the blur test in yads_search_think naming this node
// alongside the plate.
function yads_tap_search_clear(_view) {
    if (_view.closing == true) { return; }

    var _node = _view.search_node;
    if (_node == undefined) { return; }

    _node.set_text("");
    _view.caret = 0;
    _view.sel_anchor = 0;
    _view.blink = 0;

    yads_caret_paint(_view);

    // AND MOVE THE PAD CURSOR OFF THE BUTTON THAT IS ABOUT TO VANISH. On a pad
    // the tap is not deferred to release (Anchor.gml:414-418), so this callback
    // runs mid-walk and the text node's think - later in the same reverse walk -
    // locks and disables the X on this very frame. set_unlocked(false) releases
    // the hover (Node.gml:581-583), the pilot's position keeps pointing at the
    // now-invalid cell, Pilot.get() returns undefined for it (Pilot.gml:88-93)
    // and try_pilot_hover no-ops (Anchor.gml:1911-1921): nothing is highlighted,
    // and since the X is the last cell of its row, East is a dead press under
    // the default Freeze overflow (Pilot.gml:331-337, :353-355). The player has
    // to guess West/North/South to get the cursor back.
    //
    // try_force_select is the engine's own one-call re-seat: it finds the node
    // in the pilot map, moves the cursor onto it and hovers it (Pilot.gml:238-249).
    // The try_ form, because it RETURNS false where force_select asserts (:261).
    // The plate is the right landing spot - it is the cell the X sits on top of
    // and the control the player was just using.
    //
    // ONLY UNDER DIRECTIONAL CONTROL. In point control the hover belongs to the
    // mouse and is recomputed from the pointer every frame anyway, and
    // hover_node would additionally force_select through the pilot
    // (Anchor.gml:1816-1817) - i.e. a mouse click would teleport the pad cursor.
    //
    // RESIDUAL, accepted: deleting the LAST CHARACTER FROM THE KEYBOARD while
    // the pad cursor rests on the X strands it in the same way, and that path
    // does not come through here. One West/North/South press recovers it.
    if (ANCHOR.in_directional_control()) {
        var _plate = _view.search_plate;
        if (_plate != undefined && _plate.pilot != undefined) {
            _plate.pilot.try_force_select(_plate);
        }
    }
}

//
// 3b. THE SEARCH BOX'S FOCUS, AND WHY node.takes_input IS FALSE WHILE TYPING
//
// The search box is a real line editor: a caret you can move, a selection,
// clipboard, insert-in-the-middle. None of that is possible while the engine's
// own text driver is running, because that driver only ever APPENDS to the end
// of the string and backspaces off the end of it (Anchor.gml:470-513).
//
// set_takes_input(true) does five separable things (Node.gml:1158-1177):
//
//   1. run_logic |= true                  - the node keeps thinking
//   2. ANCHOR.text_input_node = self      - **the keyboard blanking**
//   3. self.takes_input = true            - **the append driver + the "|" caret**
//   4. start_text_input()                 - the OS/IME text-input session
//   5. steam_open_textbox() on a Deck     - the on-screen keyboard
//
// Only (3) reads the RAW FIELD: the driver at Anchor.gml:463 and the caret
// splice at Anchor.gml:1136 are both `if node.takes_input`. Everything else is
// gated somewhere else entirely. In particular (2), the thing that stops WASD
// walking the farmer across the room while you type, is
// `if self.text_input_node != undefined` on the ANCHOR (Anchor.gml:194-202) -
// an ANCHOR field, written by statement 2 of set_takes_input, and NOT re-read
// from the node afterwards. So calling set_takes_input(true) and then setting
// the node's own flag back to false keeps 1, 2, 4 and 5 and drops only 3.
//
// That is the whole trick, and it is the only engine-owned field this mod
// writes. Two readers exist in the entire corpus (Anchor.gml:463, :1136) plus
// get_takes_input, which is called once, by BuggerMenu. If a future engine adds
// a third reader the failure mode is a missing feature, not a crash - and
// _view.editing exists precisely so that backing this out means rewriting one
// pair of functions.
//
// BLUR IS UNCONDITIONAL AND THEREFORE SAFE: set_takes_input(false) does not test
// the raw flag before cleaning up (Node.gml:1161-1167), so it still calls
// stop_text_input(), clears ANCHOR.text_input_node and forgets the Deck keyboard
// no matter what we left the field set to.
//
function yads_search_focus(_view) {
    var _node = _view.search_node;
    if (_node == undefined) { return; }

    _node.set_takes_input(true);   // effects 1, 2, 4 and 5 all fire
    _node.takes_input = false;     // effect 3 only: driver and engine caret off
    _view.editing = true;

    // Land the caret at the end of whatever was already there and select
    // nothing, which is what every text field in every OS does on focus.
    var _len = string_length(_node.get_text());
    _view.caret = _len;
    _view.sel_anchor = _len;
    _view.blink = 0;
    _view.repeat_key = undefined;
    _view.repeat_timer = 0;

    yads_caret_paint(_view);
}

function yads_search_blur(_view) {
    // ACCEPTED COSMETIC, stated so nobody re-derives it as a bug: set_takes_input
    // (false) also strips the first "|" from display_text without dirtying the
    // cache (Node.gml:1164), so a query containing a literal pipe renders one
    // character short from blur until the next thing that dirties the node - a
    // hover on the plate is enough. `text` is untouched, so the query, the
    // projection and the caret arithmetic are all correct, and "|" matches no
    // Mistria item name. With takes_input false for the whole focus session it
    // is deterministic rather than frame-dependent, and self-healing either way.
    var _node = _view.search_node;
    if (_node != undefined) { _node.set_takes_input(false); }

    _view.editing = false;
    _view.repeat_key = undefined;
    _view.repeat_timer = 0;

    // Collapse the selection so a re-focus never inherits one, and hide both
    // rects. Painting with editing already false is what hides them.
    _view.sel_anchor = _view.caret;
    yads_caret_paint(_view);
}

// The auto-focus toggle. NOT a request recorder, and deliberately so: this
// writes no view state and moves no item, it flips a preference and persists it
// on the spot, so there is nothing for the tick to serialise. Writing straight
// through also means the setting survives an alt-F4 taken one second later,
// which is the whole reason it lives in a file instead of in the runtime struct.
//
// It does NOT retro-focus or retro-blur the box. Turning it on mid-session says
// what the NEXT panel does; yanking focus out from under a half-typed query
// would be a worse surprise than the one the toggle exists to prevent.
function yads_tap_autosearch(_view) {
    if (_view.closing == true) { return; }

    var _cfg = yads_config();
    _cfg.auto_search = !_cfg.auto_search;

    mmapi_config_write(YADS_MOD,
        YADS_CONFIG_VERSION, _cfg);
}

// Read every frame by the engine's sprite state machine (Anchor.gml:600-618),
// exactly like the filter buttons' getter. Takes no view: the setting is global,
// not per-view.
function yads_autosearch_selected() {
    return yads_config().auto_search;
}

// The FILTER BAR's tooltip poll. Lives on the filter plate - see the placement
// note in build_filters for why it cannot live on the label it drives - and runs
// once per frame for the life of the menu.
//
// Eight controls, one label, and nothing else. Anything off-plate - the
// auto-search toggle, say - is served by its own think on its own node
// (yads_autosearch_think). This function is therefore about the plate it is
// attached to and nothing else, which is what makes its early returns safe to
// reason about.
//
// is_hovered() is Node.in_hover (Node.gml:456-462), which the mouse path sets in
// ANCHOR's node loop AND the pilot path sets through Pilot.try_force_select ->
// ANCHOR.hover_node (Pilot.gml:238-247), so one test covers mouse and stick
// without a second code path.
//
// Cost in the common case - nothing hovered - is eight struct reads and an
// early-outing set_enabled(false) (Node.gml:642-651).
function yads_hint_think(_view) {
    if (_view.closing == true) { return; }

    var _plate = _view.hint_plate;
    var _label = _view.hint_label;
    if (_plate == undefined || _label == undefined) { return; }

    var _key = undefined;

    var _buttons = _view.filter_buttons;
    for (var _i = 0; _i < array_length(_buttons); _i++) {
        if (_buttons[_i] == undefined) { continue; }
        if (_buttons[_i].is_hovered()) {
            // Slot -> group through the live page, so the label follows the
            // rotation without the bar having to repaint anything on a flip.
            _key = yads_filter_label_key(
                yads_filter_group(_view, _i));
            break;
        }
    }

    if (_key == undefined) {
        _plate.set_enabled(false);
        return;
    }

    // Order matters: name it, measure it, then fit the backplate around it. The
    // label is the plate's child and centred in it, so resizing the plate moves
    // the text - measuring first and sizing second is the only order that lands
    // a locale's longest string inside its own box. measure() only re-lays the
    // text out when the cache is dirty, i.e. only on the frames the key actually
    // changed (Node.gml:1091-1096).
    //
    // 16, matching the creation site: the 8x8 nine-slice minimum. A resize back
    // to 14 here would reintroduce the overlapped borders and the mirrored
    // interior band on the very first hover.
    _label.set_key(_key);
    _plate.set_size(_label.measure().x + 10, 16);
    _plate.set_enabled(true);
}

// The auto-search toggle's own poll, on the toggle's own node. Two jobs, and
// neither may be moved onto the filter plate's think - see the note beside the
// tooltip's construction in build_search_strip.
//
//   1. Keep the checkbox glyph honest. The lit/unlit generic box is driven by
//      the engine's sprite state machine through our selected getter, but the
//      tick mark on top is a plain child sprite that somebody has to swap.
//      set_sprite early-outs on an unchanged asset (Node.gml:1558-1561), so the
//      steady state is one config struct read and one comparison.
//   2. Show the toggle's label while it is hovered, and only then.
//
// This node always exists when the strip exists, so neither job can be lost to a
// defensive early return in an unrelated builder.
function yads_autosearch_think(_view) {
    if (_view.closing == true) { return; }

    var _icon = _view.autosearch_icon;
    if (_icon != undefined) {
        _icon.set_sprite(yads_autosearch_icon());
    }

    var _plate = _view.autosearch_hint_plate;
    var _label = _view.autosearch_hint_label;
    var _toggle = _view.autosearch_button;
    if (_plate == undefined || _label == undefined || _toggle == undefined) { return; }

    if (!_toggle.is_hovered()) {
        _plate.set_enabled(false);
        return;
    }

    // Same measure-then-size order, and for the same reason, as the filter bar's
    // label. The key changes only when the player flips the setting, so measure()
    // re-lays the text out about as often as that happens.
    _label.set_key(yads_autosearch_label_key());
    _plate.set_size(_label.measure().x + 10, 16);
    _plate.set_enabled(true);
}

// Right-banner stack icon, repointed: quick-stack the backpack into the
// NETWORK (member chests), not into the visible page.
function yads_tap_stack(_view) {
    if (_view.closing == true) { return; }
    yads_quick_stack(_view);
}

function yads_request_page(_view, _page) {
    if (_view.pages <= 1) { return; }
    _view.page_request = wrap(_page, _view.pages);
}

// Runs inside ANCHOR.on_begin_step, i.e. AFTER the keyboard blanking at
// Anchor.gml:194-202 has already eaten this frame's MenuBack. So blurring here
// costs the player nothing beyond one press: this ESC blurs, the next one closes
// the menu - unless the hand is holding a stack, in which case the drop takes a
// press of its own in between. See the count in the gamepad blur note below; the
// keyboard chain is the same three consumers in the same order.
function yads_search_think(_view) {
    // Closing guard, like every other think in this file: after teardown the
    // view's node refs are cleared, and a think racing that (it lives on the
    // node, which dies with the canvas a frame later) must touch nothing.
    if (_view.closing == true) { return; }

    var _node = _view.search_node;
    if (_node == undefined) { return; }

    // Placeholder hint: visible only while the box is empty and unfocused.
    // _view.editing, not _node.takes_input - see search_focus.
    var _hint = _view[$ "search_hint"];
    if (_hint != undefined) {
        _hint.set_enabled(_view.editing != true && string_trim(_node.get_text()) == "");
    }

    // The clear X, the hint's exact complement: shown whenever there is anything
    // to clear, focused or not. Driven from here rather than from the button's
    // own think for the reason a disabled node cannot think itself back on
    // (Anchor.gml:374) - this poll runs on the text node, which is never
    // disabled. Same string_trim as the hint so a query of pure spaces, which
    // the tick treats as empty, offers no button to clear it with.
    //
    // BOTH FLAGS, NOT JUST enabled. A disabled node is skipped by the mouse
    // (Anchor.gml:374-377 tests safe_enabled) but NOT by the gamepad: the pilot's
    // position_is_valid reads safe_unlocked alone (Pilot.gml:296-307), and
    // try_pilot_hover then hovers whatever the cursor landed on with no
    // enabled test of its own (Anchor.gml:1911-1921). Enabled-only would leave a
    // permanent invisible stop in this row for every pad player whose query is
    // empty - which is most of the time. set_unlocked also releases the hover if
    // the pointer happened to be on the X when the query emptied, which is
    // exactly the frame after a successful clear.
    //
    // AND THE UNLOCK IS GATED ON THE PLATE, because the two flags are NOT
    // symmetrical about ancestors. set_unlocked defaults to personal = true and
    // ASSIGNS (Node.gml:578-580), so an ungated poll re-unlocks this node one
    // frame after canvas.lock() locked the whole tree, leaving the X as the only
    // pilot-navigable node in a dead menu for the length of the fade.
    // set_enabled has no such hole - it short-circuits against the node's own
    // enabled flag (Node.gml:642-644, :678-680) - so only the unlock needs the
    // guard. The plate's safe_unlocked is the true reading of "an ancestor lock
    // is in force": canvas.lock() propagates set_unlocked(false, false) to every
    // descendant, so it goes false in the same call. _view.closing would NOT be
    // enough - AnchorMenu.request_hide locks the canvas without our close path
    // ever running (AnchorMenu.gml:267-278) - and is in any case already
    // enforced by this think's own guard above.
    var _clear = _view[$ "search_clear"];
    if (_clear != undefined) {
        var _clearable = string_trim(_node.get_text()) != "";
        _clear.set_enabled(_clearable);
        _clear.set_unlocked(_clearable && _view.search_plate.safe_unlocked);
    }

    // ...AND THE PLATE STOPS LISTENING WHILE THE POINTER IS ON THE X.
    //
    // ANCHOR grants hover to AT MOST ONE node - `current_hovered_node` - and
    // hover_node RELEASES the previous holder unconditionally (Anchor.gml:1806),
    // wiping its in_hover, in_tap AND tap_is_deferred (:1862-1864). The node walk
    // runs in REVERSE registration order (:370), so of two OVERLAPPING hover
    // listeners the one registered FIRST is visited LAST and takes the hover away
    // from the other within the same frame. This button's hitbox lies wholly
    // inside the plate's rect and the plate was built first, so without this line
    // the plate stole the X's hover in every frame where `mouse_is_active` held
    // (:387) - which is every frame the pointer moved and every frame a mouse
    // button was down (:231). Both of Beta 1.1's reported symptoms are that one
    // theft:
    //
    //   * HOVER FLICKER. The X's own art is chosen during the X's own step
    //     (:600-618; set_sprites_from_key points key_sprite_target at itself,
    //     Node.gml:1594), which runs BEFORE the plate's theft later in the same
    //     walk - so the hovered sprite appeared for exactly the frames the GUI
    //     mouse position changed and dropped the instant the pointer stood still.
    //   * DEAD CLICK. On the press frame the X won the hover, took the press
    //     (:404 - take_tap MUTES it, Input.gml:270, :421-429) and deferred it to
    //     the release (:414-418). The plate's theft, later in that same frame,
    //     cleared tap_is_deferred before the release ever arrived, and the muted
    //     press left the plate with nothing to fire either: the click did
    //     nothing at all, not even re-focus the field.
    //
    // listen_for_hovers IS that gate (Anchor.gml:377) and touches nothing else -
    // not the lock, not enabled, not the plate's own art (chosen outside the
    // gate, :582-618), not pad navigation (position_is_valid reads safe_unlocked,
    // Pilot.gml:298-307). Vanilla drives the flag exactly this way, per frame
    // from a think callback (anchor_utils.gml:1004-1014).
    //
    // THE ORDER MAKES IT SAME-FRAME. This think lives on the text node, which is
    // registered after the plate and before the X, so the reverse walk reaches
    // the X's hover test, then this poll, then the plate: the flag written here
    // is read by the plate later in the very same frame, never one late.
    //
    // POINT CONTROL ONLY. Under directional control the pointer sits wherever it
    // was abandoned, and a pad's tap is delivered through this same gate (:404) -
    // closing it because the mouse happens to rest on the X would make the search
    // plate untappable with a pad.
    //
    // is_unlocked() - safe_unlocked && safe_enabled - is the engine's own test for
    // "this node may take the hover" (:374, :377), so a hidden or locked X hands
    // the plate straight back. That is also what preserves the canvas-lock
    // property: while the menu closes the X is locked (the poll above gates it on
    // the plate), this reads false, and the plate resumes listening behind its own
    // safe_unlocked - which the same lock has already cleared. No transition frame
    // unlocks anything.
    //
    // The pointer resting where the X APPEARS is the one residual: the acquire at
    // :387 needs mouse_is_active, so until the mouse moves or clicks the plate
    // keeps a hover it can no longer release itself. That is what the box looks
    // like today with the pointer inside it, it costs no input (the press frame
    // sets mouse_is_active and the X takes the hover and the tap), and it heals on
    // the first pixel of movement.
    var _mouse_on_clear = ANCHOR.in_point_control()
        && _clear != undefined
        && _clear.is_unlocked()
        && ANCHOR.point_in_node(_clear, MOUSE_GUI_X, MOUSE_GUI_Y);
    _view.search_plate.listen_for_hovers(!_mouse_on_clear);

    if (_view.editing != true) { return; }

    // BLUR PATHS FIRST, all four of them, and all through search_blur - which
    // drops the engine focus, hides the caret and the selection band, and clears
    // the auto-repeat state, none of which set_takes_input(false) knows about.
    if (keyboard_check_pressed(vk_escape) || keyboard_check_pressed(vk_enter)) {
        yads_search_blur(_view);
        return;
    }

    // Gamepad blur: a pad can focus the plate (its tap is Interact) but can
    // produce none of the keyboard/mouse blur signals, and while the field holds
    // focus every keyboard InputId is blanked (Anchor.gml:194-202) - a pad-only
    // player would be stuck. take_press CONSUMES MenuBack, so each consumer in
    // the chain gets exactly one press.
    //
    // HOW MANY PRESSES, exactly, derived from registration order rather than
    // assumed. ANCHOR walks nodes in REVERSE registration order (Anchor.gml:370)
    // and runs the menu's own exit listening only after the whole node loop
    // (:653-656). InventoryMenu.build registers its hand node first of all
    // (InventoryMenu.gml:197), long before this search node, so the walk reaches
    // us first and the hand second. With an empty hand that is two presses: blur,
    // then close. WITH A STACK IN HAND IT IS THREE:
    //
    //   B #1 -> this callback blurs the field and consumes the press.
    //   B #2 -> we early-return on !editing; the hand node takes the press
    //           and drops the stack back into the mirror (InventoryMenu.gml:101).
    //   B #3 -> the hand node is disabled and skipped; run_exit_listening closes.
    //
    // No press is ever double-consumed and the drop never shares a frame with the
    // close, which is why the reconciler always gets its frame to put the dropped
    // stack back into the members.
    if (INPUT.take_press(InputId.MenuBack)) {
        yads_search_blur(_view);
        return;
    }

    // Steam Deck / Big Picture: the engine opened the on-screen keyboard for
    // us (Node.gml:1173-1175); if the player dismissed it, drop focus too -
    // vanilla's own text popup does exactly this (anchor_utils.gml:787-791).
    //
    // Still correct after the hand-flip: spawned_steam_keyboard is written by
    // set_takes_input's own statement 5, which runs before we clear the raw flag,
    // and cleared by set_takes_input(false) unconditionally.
    if (_node[$ "spawned_steam_keyboard"] == true && !steam_textbox_is_open()) {
        yads_search_blur(_view);
        return;
    }

    // Clicking anywhere outside the box gives focus back to the grid - and the
    // clear X is INSIDE the box for this purpose, whatever its geometry says.
    // Its hitbox is trimmed to sit within the plate's rect (see the clear
    // button in build_search_strip), so today this second test never fires;
    // it is written anyway because the alternative is an unstated dependency
    // on the X's bbox being a subset of the plate's, and a future re-align, a
    // re-cut sprite or a dropped bbox offset would silently turn every clear
    // into a clear-and-blur with nothing to catch it.
    //
    // is_unlocked() is exactly the engine's own condition for this node to have
    // received the click - safe_unlocked && safe_enabled (Node.gml:603-605),
    // the pair tested by the hover walk at Anchor.gml:374-377 - so a click in
    // the X's rect while the query is empty, where there is no button to press,
    // still blurs the way clicking bare plate border does.
    if (mouse_check_button_pressed(mb_left)
        && !ANCHOR.point_in_node(_view.search_plate, MOUSE_GUI_X, MOUSE_GUI_Y)) {
        var _clear_x = _view[$ "search_clear"];
        var _on_clear = _clear_x != undefined
            && _clear_x.is_unlocked()
            && ANCHOR.point_in_node(_clear_x, MOUSE_GUI_X, MOUSE_GUI_Y);

        if (!_on_clear) {
            yads_search_blur(_view);
            return;
        }
    }

    // Still focused: this is where the editor lives.
    yads_search_edit(_view, _node);
}

//
// 3c. THE LINE EDITOR
//
// Runs once per frame while the box has focus, from inside ANCHOR's node loop.
// The seam is same-frame in both directions: the (now dead) text driver would
// have run at Anchor.gml:459, this think runs at :628, and the layout caches are
// recomputed later still, in the draw event (:684-687) - so a caret we move here
// is laid out and drawn this frame, never one late.
//
// keyboard_check* is NOT blanked while focused: the blanking at
// Anchor.gml:194-202 writes only INPUT.raw_keyboard, which is why the ESC test
// above works at all. Arrows, Home/End, Delete and the modifiers are all free.
//
function yads_search_edit(_view, _node) {
    var _text = _node.get_text();
    var _len = string_length(_text);

    // Clamp before anything reads them. The string can move under the editor -
    // a re-focus, the clear X, a game update - and every string_copy below
    // assumes both indices are inside it.
    _view.caret = clamp(_view.caret, 0, _len);
    _view.sel_anchor = clamp(_view.sel_anchor, 0, _len);

    var _typed = keyboard_string();
    var _shift = keyboard_check(vk_shift);

    // THE MODIFIER TEST, and the reason it also looks at _typed.
    //
    // keyboard_check_control_modifier() is called from TitleMenu's version-text
    // think (TitleMenu.gml:189), i.e. every frame of every boot, so it certainly
    // links - it is a runtime builtin defined nowhere in the GML corpus, and it
    // buys the macOS command key. vk_control alone would do; both is free.
    //
    // AltGr, however, IS Ctrl+Alt on Windows, and on a Romanian, Polish or
    // German layout AltGr+key is how you type half the alphabet. The typed string
    // is the only discriminator available: a real Ctrl+V produces no character
    // this frame, while AltGr+V produces one, so requiring _typed == "" turns
    // "Ctrl is down" into "Ctrl is down and the OS did not treat it as typing".
    //
    // ACCEPTED RESIDUAL, and it is UNCLOSABLE rather than merely unclosed - which
    // took a binary read to establish, so it is written down here once. The
    // _typed test catches every AltGr combo that emits a glyph, but X, C and V
    // emit NOTHING under AltGr on Romanian-standard, German and Polish layouts,
    // so an accidental AltGr+X reaches the cut arm below and empties the query.
    //
    // THE SAME HOLE COVERS THE FOUR EDITING COMBOS, and by a wider margin: Left,
    // Right, Backspace and Delete emit no glyph under ANY layout, so _typed is
    // empty for them however Alt is held. On those three layouts AltGr+Backspace
    // therefore eats a whole word instead of one character, AltGr+Delete eats the
    // word to the right, and AltGr+arrow jumps a word instead of a character.
    // Same class, same cause, and the list has to name them or the next reader
    // takes "X, C and V" for the complete set.
    //
    // The obvious guard is `&& !keyboard_check(vk_alt)`, on the reasoning that
    // vk_alt is a stock GameMaker constant this corpus merely never names.
    //
    // THIS IS NOT GAMEMAKER. FieldsOfMistria.exe embeds the Rust `fabricator` GML
    // runtime (crates/compiler, crates/vm, crates/stdlib, pinned at 5fff344), and
    // its virtual-key constants sit in one contiguous name run in the binary:
    // vk_semicolon, the bracket/slash/delete/space/tab keys, vk_backspace,
    // vk_enter, the arrows, vk_f1..vk_f12, vk_escape, the punctuation keys,
    // vk_end, vk_pagedown, vk_pageup, vk_insert, vk_home, vk_caps_lock, vk_shift,
    // vk_control - and then straight into gp_* and mb_*. There is no vk_alt, no
    // vk_lalt, no vk_ralt. The engine's entire keyboard surface is keyboard_check,
    // keyboard_check_pressed, keyboard_check_released, keyboard_string and
    // keyboard_check_control_modifier. NOTHING HERE CAN OBSERVE THE ALT KEY, so
    // the guard cannot be written; naming vk_alt would read an unset variable on
    // every frame of typing. (check_symbols.py's own docstring says this in
    // general terms - "appears in the game source" is the strongest available
    // proof a builtin exists in THIS engine, which is not stock GameMaker - and
    // momi --compile-check is a parser, not a resolver: it rejects `&&&` and
    // `"\q"` but passes an undefined identifier straight through.)
    //
    // Bounded and recoverable, which is why it ships: the blast radius is the
    // search string, Ctrl+V or retyping restores it, no item moves, and the
    // reconciler never sees any of it.
    var _combo = (_typed == "")
        && (keyboard_check(vk_control) || keyboard_check_control_modifier());

    var _moved = false;   // did the text, the caret or the selection change

    if (_combo) {
        if (keyboard_check_pressed(ord("A"))) {
            _view.sel_anchor = 0;
            _view.caret = _len;
            _moved = true;
        }

        // Copy and cut share the copy. clipboard_set_text / clipboard_get_text
        // are proven in shipping code (BuggerMenu.gml:50-52); clipboard_has_text
        // is NOT in the corpus, so the paste below is guarded with is_string.
        var _cut = keyboard_check_pressed(ord("X"));
        if (keyboard_check_pressed(ord("C")) || _cut) {
            var _lo = min(_view.caret, _view.sel_anchor);
            var _hi = max(_view.caret, _view.sel_anchor);
            if (_hi > _lo) {
                clipboard_set_text(string_copy(_text, _lo + 1, _hi - _lo));
                if (_cut) {
                    var _after_cut = yads_edit_delete(_view, _text, true);
                    if (_after_cut != undefined) { _text = _after_cut; _moved = true; }
                }
            }
        }

        if (keyboard_check_pressed(ord("V"))) {
            var _paste = clipboard_get_text();
            if (is_string(_paste) && _paste != "") {
                // One line, always: the field cannot break lines (and must not -
                // set_max_width re-enables reflow as a side effect, which is why
                // allow_line_breaks(false) follows it at the creation site).
                //
                // The tab goes with them. Copying one cell out of a spreadsheet or
                // one cell out of an HTML table is the ordinary way to acquire a
                // leading, trailing or embedded tab, and the tick's string_trim
                // (boot.gml section 3d) only reaches the ends - an
                // embedded one sits inside the token and string_pos then matches
                // nothing, with nothing on screen to explain why. A space is the
                // right replacement rather than "": it is what the column break
                // meant, and it keeps the two words apart.
                _paste = string_replace_all(_paste, "\r", "");
                _paste = string_replace_all(_paste, "\n", " ");
                _paste = string_replace_all(_paste, "\t", " ");

                // TRUE = clip to the budget. A rejected keystroke is one character
                // and the full box explains itself; a rejected paste is up to the
                // whole clipboard vanishing with no insert, no sound and no
                // visual, indistinguishable from "paste is not implemented".
                var _pasted = yads_edit_insert(_view, _node, _text, _paste, true);
                if (_pasted != undefined) { _text = _pasted; _moved = true; }
            }
        }
    }

    // A cut or a paste above changed the string, so the length every clamp below
    // measures against has to be re-read. Cheap, and the alternative is an End
    // key that lands the caret past the end of a string a Ctrl+X shortened in the
    // same frame.
    _len = string_length(_text);

    // NAVIGATION. Each key is asked through the repeat gate, so holding one
    // behaves like the engine's own backspace: 20 frames, then every 2.
    //
    // Left/right with a live selection and no shift COLLAPSE to the selection's
    // near edge instead of stepping - the behaviour every text field has, and
    // the reason a player can undo a Ctrl+A with one arrow press.
    //
    // WITH CTRL HELD THEY JUMP A WORD, and the branch is INSIDE the arm rather
    // than the arm inside an `if (_combo)`. yads_edit_repeat is a state machine
    // that carries repeat_key across frames, so it has to be asked about every
    // key on every frame: skip the call for one frame - which is exactly what
    // wrapping the arms in a modifier test would do the moment Ctrl goes down or
    // comes up mid-hold - and the release edge is missed, ownership is never
    // handed back, and the arrow stops repeating for the rest of the hold.
    //
    // Ctrl+Shift extends the selection for free: only the caret moves here, and
    // the shared `if (!_shift)` line below is what collapses the anchor onto it.
    if (yads_edit_repeat(_view, vk_left)) {
        if (_combo) {
            _view.caret = yads_word_left(_text, _view.caret);
        } else if (!_shift && _view.sel_anchor != _view.caret) {
            _view.caret = min(_view.caret, _view.sel_anchor);
        } else {
            _view.caret = max(0, _view.caret - 1);
        }
        if (!_shift) { _view.sel_anchor = _view.caret; }
        _moved = true;
    }

    if (yads_edit_repeat(_view, vk_right)) {
        if (_combo) {
            _view.caret = yads_word_right(_text, _view.caret);
        } else if (!_shift && _view.sel_anchor != _view.caret) {
            _view.caret = max(_view.caret, _view.sel_anchor);
        } else {
            _view.caret = min(_len, _view.caret + 1);
        }
        if (!_shift) { _view.sel_anchor = _view.caret; }
        _moved = true;
    }

    if (keyboard_check_pressed(vk_home)) {
        _view.caret = 0;
        if (!_shift) { _view.sel_anchor = 0; }
        _moved = true;
    }

    if (keyboard_check_pressed(vk_end)) {
        _view.caret = _len;
        if (!_shift) { _view.sel_anchor = _len; }
        _moved = true;
    }

    // DELETION. A selection is what gets deleted whichever key asked; with no
    // selection, backspace takes the character before the caret and delete the
    // one at it.
    //
    // WITH CTRL HELD THEY EAT A WORD, expressed as "select the word, then delete
    // the selection" rather than as a second deletion path: yads_edit_delete
    // already deletes [min, max) and already reports "nothing to delete" by
    // returning undefined, so stretching the anchor to the word boundary reuses
    // all of it - including the caret placement and the empty-at-the-end guard,
    // which is what makes Ctrl+Backspace at position 0 a no-op instead of an
    // off-by-one. Only with an EMPTY selection: a Ctrl held over a live
    // selection must still delete exactly what is highlighted.
    if (yads_edit_repeat(_view, vk_backspace)) {
        if (_combo && _view.sel_anchor == _view.caret) {
            _view.sel_anchor = yads_word_left(_text, _view.caret);
        }
        var _after_bs = yads_edit_delete(_view, _text, true);
        if (_after_bs != undefined) { _text = _after_bs; _moved = true; }
    }

    if (yads_edit_repeat(_view, vk_delete)) {
        if (_combo && _view.sel_anchor == _view.caret) {
            _view.sel_anchor = yads_word_right(_text, _view.caret);
        }
        var _after_del = yads_edit_delete(_view, _text, false);
        if (_after_del != undefined) { _text = _after_del; _moved = true; }
    }

    // INSERTION, last, so a Ctrl combo has already claimed the frame if it was
    // one. keyboard_string() is this frame's typed characters, not a rolling
    // buffer: nothing in the corpus ever clears it, and if it accumulated, the
    // engine's own driver at Anchor.gml:484 would re-append the whole history
    // every frame and no text field in the game would work.
    //
    // "Select then type replaces" needs no code of its own - edit_insert
    // replaces the selection by construction.
    if (!_combo && _typed != "") {
        var _inserted = yads_edit_insert(_view, _node, _text, _typed);
        if (_inserted != undefined) { _text = _inserted; _moved = true; }
    }

    // set_text early-returns on an unchanged string (Node.gml:1045-1047), so the
    // steady state is one comparison. The TICK is what notices the new value and
    // re-projects (boot.gml section 3d); this function never touches
    // the view's query.
    _node.set_text(_text);

    // Blink on our own counter, because the engine's cursor_timer is only
    // decremented inside the driver we switched off. Any edit resets it, so the
    // caret is solid the instant you type - which is what set_takes_input's own
    // `cursor_timer = 1` was doing for the engine caret.
    _view.blink = (_view.blink + 1) mod (TEXT_CURSOR_BLINK_INTERVAL * 2);
    if (_moved) { _view.blink = 0; }

    yads_caret_paint(_view);
}

// Auto-repeat, one owner at a time. Returns true on the frame the key should
// act: immediately on press, then after YADS_REPEAT_DELAY
// frames of hold, then every YADS_REPEAT_RATE frames - the
// engine's own 20-then-every-2 (Node.gml:1167-1172, Anchor.gml:499-512).
//
// A fresh press always takes ownership, so pressing Delete while holding Left
// stops Left repeating rather than interleaving two repeats.
//
// AND OWNERSHIP COMES BACK, which is what the re-acquire arm below is for.
// Without it the demotion is permanent: the release branch clears repeat_key
// correctly, but if the ONLY acquisition path is keyboard_check_pressed then a
// key that is already down never sees another press edge. Holding Left, then
// tapping and releasing Right, would freeze the caret for the whole rest of the
// Left hold - and the same sequence on Backspace + Delete stops a deletion
// mid-hold, which is the version a player actually notices. The arm hands the
// vacancy to whichever still-held key asks first. Its timer starts at the DELAY
// rather than at 0 so the key resumes SCANNING instead of serving a second
// initial pause, and it returns false because this frame is a resume, not an act.
//
// The release branch therefore still has to clear repeat_key: the clear is what
// creates the vacancy the arm claims. Ownership changes hands one frame later
// than the release, because the four keys are polled in a fixed order and the
// owner may be polled after the claimant - invisible at 60fps.
function yads_edit_repeat(_view, _key) {
    if (keyboard_check_pressed(_key)) {
        _view.repeat_key = _key;
        _view.repeat_timer = 0;
        return true;
    }

    if (!keyboard_check(_key)) {
        if (_view.repeat_key == _key) { _view.repeat_key = undefined; }
        return false;
    }

    if (_view.repeat_key == undefined && keyboard_check(_key)) {
        _view.repeat_key = _key;
        _view.repeat_timer = YADS_REPEAT_DELAY;
        return false;
    }

    if (_view.repeat_key != _key) { return false; }

    _view.repeat_timer += 1;
    if (_view.repeat_timer <= YADS_REPEAT_DELAY) { return false; }

    return ((_view.repeat_timer - YADS_REPEAT_DELAY)
        mod YADS_REPEAT_RATE) == 0;
}

// Replace the selection - or, with no selection, the caret point - with
// _insert, and leave the caret after it. Returns the new string, or UNDEFINED
// when nothing could be inserted, in which case nothing at all has changed.
//
// THE WIDTH CHECK IS OURS NOW. With the driver off, nothing in the engine
// enforces max_width: update_display_text assigns display_text = text verbatim
// when can_line_break is false (Node.gml:1099-1109). It is measured with the
// engine's own string_width_font (Utils.gml:275-279), which sets the draw font
// as a side effect and is safe to call from a think because the render pass
// re-issues draw_set_font per node (Anchor.gml:1135).
//
// Order-independence is what makes an insert-in-the-middle as safe to measure
// as the driver's append: the font's per-glyph advances are additive and the
// table has no kerning pairs (fonts/text_widths.toml).
//
// _CLIP IS WHAT SEPARATES A KEYSTROKE FROM A PASTE. Off, this is the driver's
// own all-or-nothing rejection (Anchor.gml:475-486) - right for one character,
// where the visibly full box is the whole explanation. On, an over-budget insert
// is SHORTENED to what fits instead of dropped, because a 200-character paste
// that silently does nothing looks like a broken feature rather than a full
// field. The same additivity that licenses the measurement makes the width
// monotonic in the prefix length, so a bisection finds the exact cut in
// ceil(log2(n)) measurements and cannot land on a false boundary.
function yads_edit_insert(_view, _node, _text, _insert, _clip = false) {
    var _len = string_length(_text);
    var _lo = min(_view.caret, _view.sel_anchor);
    var _hi = max(_view.caret, _view.sel_anchor);

    var _head = string_copy(_text, 1, _lo);
    var _tail = string_copy(_text, _hi + 1, _len - _hi);
    var _font = _node[$ "font"];

    var _candidate = _head + _insert + _tail;

    if (string_width_font(_candidate, _font) > _view.search_max_width) {
        if (!_clip) { return undefined; }

        // Bisect on the length of the kept PREFIX. _fits is a length known to fit
        // and _over one known not to; _fits starts at 0 because head+tail is the
        // current string minus the selection, and deleting cannot widen a string
        // that already fit. The loop closes the gap to 1 and _fits is the answer.
        var _fits = 0;
        var _over = string_length(_insert);
        while (_over - _fits > 1) {
            var _mid = (_fits + _over) div 2;
            var _try = _head + string_copy(_insert, 1, _mid) + _tail;
            if (string_width_font(_try, _font) > _view.search_max_width) {
                _over = _mid;
            } else {
                _fits = _mid;
            }
        }

        // Not one character of it fits: the box was already full, and there is
        // nothing to show for the paste. Same contract as the rejection above.
        if (_fits <= 0) { return undefined; }

        _insert = string_copy(_insert, 1, _fits);
        _candidate = _head + _insert + _tail;
    }

    _view.caret = _lo + string_length(_insert);
    _view.sel_anchor = _view.caret;
    return _candidate;
}

// Delete the selection, or one character if there is none: before the caret when
// _before, at the caret otherwise. Returns the new string, or UNDEFINED when
// there was nothing to delete (caret at an end with no selection), in which case
// the caller must not report a change.
//
// No width check: deletion cannot grow the string.
function yads_edit_delete(_view, _text, _before) {
    var _len = string_length(_text);
    var _lo = min(_view.caret, _view.sel_anchor);
    var _hi = max(_view.caret, _view.sel_anchor);

    if (_hi <= _lo) {
        if (_before) {
            if (_lo <= 0) { return undefined; }
            _lo -= 1;
        } else {
            if (_hi >= _len) { return undefined; }
            _hi += 1;
        }
    }

    _view.caret = _lo;
    _view.sel_anchor = _lo;
    return string_copy(_text, 1, _lo) + string_copy(_text, _hi + 1, _len - _hi);
}

//
// 3c-i. WORD BOUNDARIES, for Ctrl+arrow and Ctrl+backspace/delete
//
// THEY TAKE THE STRING, NEVER THE NODE. yads_search_edit works on a local
// `_text` that can already differ from _node.get_text() by the time these are
// called - a Ctrl+X or a Ctrl+V earlier in the same frame rewrote the local and
// the node is not written back until the end of the function. Reading the node
// here would compute a boundary in the previous frame's string and hand the
// caret an index into a string that no longer exists.
//
// CHARACTER CLASSES, not Unicode categories: the engine's string surface is
// string_char_at / string_copy / string_pos / string_length and nothing else
// (string_ord_at and chr appear nowhere in the corpus, so neither can be
// assumed to exist in Fabricator). A membership test against a literal
// separator set is therefore both the simplest and the only portable spelling.
// The set is space plus the punctuation that actually occurs in Mistria item
// names and in a typed query - hyphen, underscore, comma, dot, slash, brackets.
// Everything else, letters and digits alike, is word material.
function yads_word_is_sep(_text, _index) {
    static SEPS = " -_,./()";

    // Off either end counts as a separator, which is what makes the loops below
    // stop at the string's edges without a second test.
    if (_index < 1 || _index > string_length(_text)) { return true; }
    return string_pos(string_char_at(_text, _index), SEPS) > 0;
}

// The caret index at the start of the word to the LEFT. The caret counts
// characters BEFORE it, so the character to its left is at 1-based index
// `caret`: skip separators first (so a caret sitting just past a space jumps the
// space rather than stalling on it), then skip the word, and stop on the
// separator that precedes it.
function yads_word_left(_text, _caret) {
    var _i = clamp(_caret, 0, string_length(_text));

    while (_i > 0 && yads_word_is_sep(_text, _i)) { _i -= 1; }
    while (_i > 0 && !yads_word_is_sep(_text, _i)) { _i -= 1; }

    return _i;
}

// The caret index at the start of the NEXT word to the right - the mirror, and
// deliberately "next word start" rather than "end of this word", which is what
// every browser, editor and OS text field does with Ctrl+Right. The character to
// the caret's right is at index caret + 1.
function yads_word_right(_text, _caret) {
    var _len = string_length(_text);
    var _i = clamp(_caret, 0, _len);

    while (_i < _len && !yads_word_is_sep(_text, _i + 1)) { _i += 1; }
    while (_i < _len && yads_word_is_sep(_text, _i + 1)) { _i += 1; }

    return _i;
}

// Put the caret and the selection band where the string says they go.
//
// EVERY OFFSET IS MEASURED, never derived from the text node's own width: an
// empty TextNode reports width 3, because update_display_text substitutes a
// single space for an empty display_text (Node.gml:1110-1112). string_width("")
// is 0, so measuring a zero-length prefix is correct where reading node.width
// would be three pixels wrong.
//
// set_scale rather than set_size: for a plain sprite node compute_node_caches
// recomputes width as spr_width * scale_x (Anchor.gml:757-760), so a set_size
// would be overwritten. It also does not mark the cache dirty (Node.gml:1708),
// which does not matter here - the draw reads scale_x directly (:1021-1031), and
// nothing reads these nodes' cached width: they have no children, they take no
// hovers, and LeftIn/Middle alignment uses x and height only.
function yads_caret_paint(_view) {
    var _caret = _view.caret_node;
    var _band = _view.sel_node;
    if (_caret == undefined || _band == undefined) { return; }

    if (_view.editing != true) {
        _band.set_enabled(false);
        _caret.set_enabled(false);
        return;
    }

    var _node = _view.search_node;
    if (_node == undefined) { return; }

    // 3 is the text node's own set_x, so all three nodes share one origin.
    static BASE_X = 3;

    var _text = _node.get_text();
    var _font = _node[$ "font"];

    var _lo = min(_view.caret, _view.sel_anchor);
    var _hi = max(_view.caret, _view.sel_anchor);

    if (_hi > _lo) {
        var _left = BASE_X + string_width_font(string_copy(_text, 1, _lo), _font);
        var _right = BASE_X + string_width_font(string_copy(_text, 1, _hi), _font);
        _band.set_x(_left)
             .set_scale(max(1, _right - _left), 9)
             .set_enabled(true);
    } else {
        _band.set_enabled(false);
    }

    _caret.set_x(BASE_X + string_width_font(string_copy(_text, 1, _view.caret), _font))
          .set_enabled(_view.blink < TEXT_CURSOR_BLINK_INTERVAL);
}

function yads_box_think(_view) {
    if (!ON_KBM) { return; }
    if (_view.closing == true) { return; }

    var _menu = _view.menu;
    if (_menu == undefined) { return; }
    // [$ ] like build_filters: a think-callback throw is uncaught and repeats
    // every frame, so the same engine-update defence applies here.
    var _left_menu = _menu[$ "left_menu"];
    if (_left_menu == undefined) { return; }

    // Gate on the slot grid's own canvas, not the whole 240x189 plate - the
    // plate includes both banners and the frame, where a wheel tick paging the
    // view would be a surprise. Also respect the canvas lock the way Scroller
    // does (Scroller.gml:250-252): a menu mid-hide from any path stops paging.
    var _grid_canvas = _left_menu[$ "canvas"];
    if (_grid_canvas == undefined) { return; }
    if (!_grid_canvas.is_unlocked()) { return; }
    if (!ANCHOR.point_in_node(_grid_canvas, MOUSE_GUI_X, MOUSE_GUI_Y)) { return; }

    if (mouse_wheel_up()) {
        yads_request_page(_view, _view.page - 1);
    } else if (mouse_wheel_down()) {
        yads_request_page(_view, _view.page + 1);
    }
}

// The sort button's label is a text node created by add_text_label; set_key runs
// it back through local_get.
function yads_apply_sort_label(_view) {
    var _button = _view.sort_button;
    if (_button == undefined) { return; }

    var _label = _button[$ "text_label"];
    if (_label == undefined) { return; }

    _label.set_key(yads_sort_key(_view.sort_mode));
}

function yads_sort_key(_mode) {
    switch (_mode) {
        case YADS_SORT_NAME:
            return YADS_LOCAL_ROOT + "sort_name";
        case YADS_SORT_VALUE:
            return YADS_LOCAL_ROOT + "sort_value";
        case YADS_SORT_STACK_VALUE:
            return YADS_LOCAL_ROOT + "sort_stack_value";
        case YADS_SORT_COUNT:
            return YADS_LOCAL_ROOT + "sort_count";
    }
    return YADS_LOCAL_ROOT + "sort_category";
}

//
// 4. CHEST ANIMATION
//
// We replaced on_close, so the closing half of the vanilla chest animation is
// ours to run. Both halves are lifted from Interact.gml:768-771 and
// StorageMenu.gml:3-10, including the renderer null guard - node.renderer only
// exists while that node's Grid is the current room's Grid.
//
function yads_open_chest(_node) {
    if (_node == undefined) { return; }

    // The renderer is an obj_node_renderer INSTANCE, and nothing in the engine
    // ever clears node.renderer when instances die (e.g. during Game cleanup
    // on quit-to-title, which is exactly when the shutdown teardown path runs),
    // so a liveness test is mandatory. instance_is_alive is the one the engine
    // itself uses on node.renderer (GridUtils.gml:171) and the only one that
    // distinguishes DESTROYED from merely deactivated by culling. It is the
    // mod's single liveness rule; there is no second one anywhere.
    var _renderer = _node[$ "renderer"];
    if (_renderer == undefined || !instance_is_alive(_renderer)) { return; }

    var _chest = _node.prototype[$ "interaction_chest"];
    if (_chest == undefined) { return; }

    _renderer.sprite_index = _chest.opening_sprite;
    _renderer.image_speed = 1;
    _renderer.image_index = 0.0;
    TANGO.play(_chest.open_sfx, _renderer.x, _renderer.y);
}

function yads_close_chest(_node) {
    if (_node == undefined) { return; }

    // Same test as open_chest, same reason (GridUtils.gml:171).
    var _renderer = _node[$ "renderer"];
    if (_renderer == undefined || !instance_is_alive(_renderer)) { return; }

    var _chest = _node.prototype[$ "interaction_chest"];
    if (_chest == undefined) { return; }

    _renderer.sprite_index = _chest.opening_sprite;
    _renderer.image_index = sprite_get_number(_renderer.sprite_index) - 1;
    _renderer.image_speed = -1;
    TANGO.play(_chest.close_sfx, _renderer.x, _renderer.y);
}

//
// 5. CLOSE AND TEARDOWN
//
// Two entry points, both idempotent:
//
//   on_close        - fires inside AnchorMenu.close(), BEFORE the fade and before
//                     any node free callback, i.e. before the hand is emptied into
//                     ARI. This is where the player's last action is written
//                     through and the chest lid comes down.
//   ui.menu_closed  - fires after free() and after the menu is off open_menus, on
//                     both the per-frame drain and the anchor-shutdown path, so
//                     quit-to-title is covered too. This is where we let go.
//
// Between the two the canvas is locked, so nothing more can be picked up; the
// tick keeps reconciling anyway because it is cheap and costs nothing to be sure.
//
function yads_view_closing(_menu) {
    if (_menu == undefined) { return; }

    var _view = _menu[$ "netstor_view"];
    if (_view == undefined) { return; }
    if (_view.closing == true) { return; }
    _view.closing = true;

    // Blur first: while the field holds focus, ANCHOR.text_input_node points at a
    // node that is about to be freed and the OS text-input session is still open.
    // (true_free_node clears the pointer as well - this just stops the IME.)
    // Guarded because set_takes_input(false) unconditionally clears the GLOBAL
    // text_input_node, which we must not touch unless we own it.
    //
    // THE GUARD IS _view.editing, NOT node.takes_input. The raw flag is false
    // for the whole time the box has focus (see search_focus), so a takes_input
    // test here would skip the blur on exactly the path that needs it and leave
    // the OS input session open against a freed node.
    if (_view.editing == true) {
        yads_search_blur(_view);
    }

    // Last write-through while the mirror is still meaningful.
    yads_reconcile(_view);

    // Read with [$ ] rather than directly: this runs off a menu-owned callback,
    // so the view it finds could in principle predate the field. Absent reads
    // as "not remote", which is the pre-1.2 behaviour.
    if (_view[$ "remote"] != true) { yads_close_chest(_view.node); }
}

function yads_teardown(_view) {
    if (_view == undefined) { return; }
    if (_view.torn_down == true) { return; }
    _view.torn_down = true;

    // RELEASE THE VIEW SLOT IMMEDIATELY, before anything that can throw. On the
    // anchor-shutdown path this whole function runs inside the seam's
    // swallow-all try/catch, and everything below - reconcile can reach
    // ARI.give_item and create_notification, close_chest reaches TANGO - can
    // fail. If _rt.view were still set when one of them did, object_interact's
    // `if (_rt.view != undefined) { return true; }` would swallow EVERY press on
    // EVERY unit for the rest of the session, self-healing only at
    // save.game_loaded. A wedged mod is a worse outcome than a missed lid
    // animation.
    //
    // Safe to release this early, verified rather than assumed: nothing in the
    // rest of this function reads _rt.view. Both callers pass the view as an
    // argument and the tick holds it in a local (boot.gml:723), so
    // the identity check below is the only consumer, and re-entry is impossible
    // this frame - teardown runs from step_begin (the tick) or from ANCHOR's
    // menu drain, both of which precede obj_ari's step and therefore any
    // interact().
    var _rt = yads_runtime();
    if (_rt.view == _view) { _rt.view = undefined; }

    // CUSTODY FIRST, COSMETICS LAST. On the anchor-shutdown path this whole
    // function runs inside the seam's swallow-all try/catch, so anything that
    // throws aborts the rest silently. The two calls that protect items - the
    // final reconcile and the hand flush - therefore run before anything that
    // merely looks nice (the chest lid), and the lid write itself is
    // liveness-guarded because Game cleanup may already have destroyed the
    // renderer.
    var _lid_done = (_view.closing == true);   // on_close already shut the lid
    _view.closing = true;

    // Same guard, same reason, on the path on_close never ran.
    if (_view.editing == true) {
        yads_search_blur(_view);
    }

    // on_close normally ran already and this finds a zero delta. It does not
    // run on every path (a menu freed without close(), anchor shutdown), so
    // the reconcile is repeated rather than assumed.
    yads_reconcile(_view);

    // On BOTH close paths this runs FIRST and the engine's own hand-return runs
    // second, finding count == 0. Per-frame drain: the ui.menu_closed emit sits
    // before clear_pending_nodes, so InventoryMenu's free callback has not run
    // yet. Anchor shutdown: the loop calls only on_free(), but after it
    // shutdown() frees screen_canvas, and true_free_node recurses through every
    // descendant - the menu canvas included - so the engine callback DOES still
    // run there, just later (Anchor.gml:51-60). Two independent return paths,
    // ours first: genuine belt-and-braces, and neither may be deleted.
    yads_flush_hand(_view);

    var _is_remote = (_view[$ "remote"] == true);
    if (!_lid_done && !_is_remote) { yads_close_chest(_view.node); }

    // Drop EVERY node reference, not most of them. All of these point at nodes
    // true_free_node has already unhooked (Anchor.gml:1677-1727); reading a field
    // off a freed Node struct is harmless in GML, which is exactly why an
    // omission here is invisible. Keep the list exhaustive against the struct
    // literal in open_view: a partial list is a use-after-free in any language
    // with real frees, and it is the reader's only map of what this view owns.
    _view.menu = undefined;
    _view.members = [];
    _view.deposit_targets = [];
    _view.rows = [];
    _view.page_text = undefined;
    _view.sort_button = undefined;
    _view.search_plate = undefined;
    _view.search_node = undefined;
    _view.search_hint = undefined;
    _view.search_clear = undefined;
    _view.filter_buttons = [];
    _view.filter_icons = [];
    _view.filter_prev = undefined;
    _view.filter_next = undefined;
    _view.filter_plate = undefined;
    _view.autosearch_button = undefined;
    _view.autosearch_icon = undefined;
    _view.autosearch_hint_plate = undefined;
    _view.autosearch_hint_label = undefined;
    _view.hint_plate = undefined;
    _view.hint_label = undefined;

    // The 45 badges are children of the slots' item nodes, which are descendants
    // of the menu canvas, so true_free_node already unhooked them; this is only
    // our reference going away. The two editor rects and the value toggle's four
    // nodes are the same story.
    _view.value_badges = [];
    _view.value_coins = [];
    _view.value_button = undefined;
    _view.value_icon = undefined;
    _view.value_hint_plate = undefined;
    _view.value_hint_label = undefined;
    _view.caret_node = undefined;
    _view.sel_node = undefined;

    // The plate and its buttons are descendants of the menu canvas, so
    // AnchorMenu.free -> true_free_node recursed into them already
    // (AnchorMenu.gml:241-243, Anchor.gml:1695-1698). Dropping our references is
    // all that is left to do.
    //
    // The player was standing in front of a panel for as long as this menu was
    // open, which is plenty of time for the world to have changed underneath the
    // connectivity cache in ways nothing else here would notice. One rescan on
    // the next tick costs a fraction of a millisecond and removes a whole class
    // of "the glow is stale after I closed the menu" reports.
    //
    // Not on a remote close: the cache only ever holds units in the CURRENT
    // location (section 9 filters on parent_grid.location_id), the player has
    // been standing in that location the whole time rather than in front of
    // anything, and the reconciler already invalidates whenever items really
    // moved. The 60-frame TTL and the STORAGE_NODES count poll still cover
    // everything else.
    if (!_is_remote) { yads_glow_invalidate(); }
}

//
// 6. THE HEART'S STATUS POPUP
//
// A read-only report, not a chest. The heart is the brain of the network, so
// interacting with it answers the two questions only the network can answer -
// how many blocks am I connected to, and how full are they - and nothing else.
// It never exposes the heart's own 54 slots and it never opens the view.
//
// Built as a vanilla Menu.Popup. That is the only menu type a mod can spawn
// outright: a hand-rolled AnchorMenu subtype has to borrow an existing menu's
// fiddle config (AnchorMenu.gml:63 reads MENUS.get_unwrap(type), and MENUS comes
// only from fiddle_get_directory("ui/menus")), which then lets ANCHOR.get_menu
// find two menus of one type and trip its "more than one was open" assert
// (Anchor.gml:154-174) - and a PopupMenu that is never pushed onto
// ANCHOR.open_menus asserts twice more on close (PopupMenu.gml:11-37).
//
// The shape is the Inventory Management help popup (StorageMenu.gml:598-782),
// which is the corpus's own "title + N stacked generic_box rows + Close" recipe:
// a title-only popup_creator, an explicit backplate resize, the title bar
// restyled into a tooltip header pinned to the top edge, then rows chained off
// each other with a one-pixel border overlap.
//
// Two rules that make this correct rather than merely plausible:
//   * everything is built BEFORE spawn(). spawn() asserts on a second call and
//     is what enables the canvas, mutes input and takes the pilot
//     (PopupMenu.gml:233-243).
//   * no exit wiring of ours. The canvas think callback runs run_exit_listening
//     every frame (PopupMenu.gml:301-305), which closes on MenuBack or on a
//     click outside the backplate, and the single Close button gets input_id
//     MenuBack plus its glyph for free as button #1 (PopupMenu.gml:87-106). B
//     and Escape both work, on pad and on keyboard, without us asking.
//
// The popup splits in two at the point where the fixed layout runs out of
// canvas. Up to the cap it is this function. Past it,
// yads_open_status_scrolling builds the same report inside a real scroller, so a
// fifty-block farm gets fifty rows rather than a truncated list. Both variants
// show every block they list, the no-panel hint and the network total.
//
function yads_open_status(_scan) {
    // Layout budget. Nine rows is the worst case here now (8 blocks + total,
    // or 7 blocks + no-panel + total) and lands at roughly 212px against a 240px
    // minspec GUI canvas (Display.gml:4) - which is what fixes the row cap, not
    // taste. Anything above it is the scroller's job.
    static PLATE_WIDTH = 200;
    static HEADER_HEIGHT = 24;
    static ROW_WIDTH = 180;
    static ROW_HEIGHT = 16;
    static ROW_PITCH = 15;    // 16 tall, chained with the -1 border overlap
    static ROW_TOP = 38;

    // 6a. Measure.
    //
    //     Per-block rows come from the DEPOSIT TARGETS: "how full is my storage"
    //     is a question about the things that store, and listing a heart or a
    //     panel here would invite exactly the deposit-into-the-heart mental
    //     model the blocks-only rule exists to remove.
    //
    //     The network total is over ALL MEMBERS, because every slot in the
    //     network is withdrawable through the panel regardless of which unit
    //     holds it - a total that omitted the heart's 54 slots would be a lie
    //     for as long as an old save's heart still had items in it.
    var _blocks = [];
    var _targets = _scan.deposit_targets;
    for (var _i = 0; _i < array_length(_targets); _i++) {
        var _inventory = _targets[_i][$ "inventory"];
        if (_inventory == undefined) { continue; }
        array_push(_blocks, yads_fill_of(_inventory));
    }

    var _net_used = 0;
    var _net_size = 0;
    var _members = _scan.members;
    for (var _i = 0; _i < array_length(_members); _i++) {
        var _inventory = _members[_i][$ "inventory"];
        if (_inventory == undefined) { continue; }
        var _fill = yads_fill_of(_inventory);
        _net_used += _fill.used;
        _net_size += _fill.size;
    }
    var _net_pct = (_net_size <= 0) ? 0 : floor(_net_used / _net_size * 100);

    // The network's panel count, straight off the scan - same number the
    // interaction ladder gated on (boot.gml section 6), which is
    // exactly why _panels >= 1 is an INVARIANT here: a panel-less heart never
    // reaches open_status at all - the ladder defers it to the vanilla chest
    // UI and the "craft an Access Panel" pointer rides that branch's toast.
    // This popup exists only on networks that already have a browsing surface.
    var _panels = _scan.panels;

    var _block_count = array_length(_blocks);

    // Past the cap the fixed layout has nothing honest left to do, so hand the
    // whole report to the scrolling variant rather than truncate it.
    if (_block_count > YADS_STATUS_ROWS) {
        return yads_open_status_scrolling(
            _blocks, _net_used, _net_size, _net_pct, _panels);
    }

    var _listed = _block_count;

    // A heartless network cannot reach this function, but a heart with no blocks
    // yet is the ordinary first-craft state and still gets one row saying so.
    var _row_count = max(1, _listed) + 1;

    // The Close button sits at Align.BottomIn, set_y(-10), COMMON_BUTTON_HEIGHT
    // tall (PopupMenu.gml:66-71), and COMMON_BUTTON_HEIGHT is locale-dependent
    // (anchor_utils.gml:10) - so the backplate is measured against it rather
    // than against a hard-coded number that a longer locale would overrun.
    var _last_bottom = ROW_TOP + (_row_count - 1) * ROW_PITCH + ROW_HEIGHT;
    var _height = _last_bottom + 8 + COMMON_BUTTON_HEIGHT + 10;

    // 6b. Shell.
    var _popup = popup_creator(YADS_LOCAL_ROOT + "status_title");

    _popup.backplate.set_size(PLATE_WIDTH, _height);

    // add_title sized the header against the default 180px backplate, so this
    // has to run after the resize (StorageMenu.gml:616-619 does the same).
    _popup.header
        .set_xy(0, 0)
        .set_sprite(spr_ui_tooltip_header_box)
        .set_size(_popup.backplate.get_width(), HEADER_HEIGHT);

    // "{} blocks connected" - the number that answers "did that crate join?".
    ANCHOR.text(_popup.backplate)
        .set_lut(COMMON_LUT)
        .set_align(Align.Center, Align.TopIn)
        .set_y(27)
        .set_text(format(yads_pattern(
                YADS_LOCAL_ROOT + "status_blocks",
                "{} blocks connected"),
            string(_block_count)));

    // 6c. Rows.
    var _previous = undefined;

    if (_listed <= 0) {
        _previous = yads_status_row(_popup, _previous,
            ROW_TOP, ROW_WIDTH, ROW_HEIGHT, false);

        // A static string, so set_key is right and safe: TextNode.set_key calls
        // local_get from ENGINE code (Node.gml:1013), inside the rewrite.
        ANCHOR.text(_previous)
            .set_lut(COMMON_LUT)
            .set_align(Align.Center, Align.Middle)
            .set_key(YADS_LOCAL_ROOT + "status_no_blocks");
    } else {
        var _row_pattern = yads_pattern(
            YADS_LOCAL_ROOT + "status_block_row", "Block {}");
        var _pct_pattern = yads_pattern(
            YADS_LOCAL_ROOT + "status_percent", "{}%");

        for (var _i = 0; _i < _listed; _i++) {
            var _fill = _blocks[_i];

            _previous = yads_status_row(_popup, _previous,
                ROW_TOP, ROW_WIDTH, ROW_HEIGHT, false);

            ANCHOR.text(_previous)
                .set_lut(COMMON_LUT)
                .set_align(Align.LeftIn, Align.Middle)
                .set_x(4)
                .set_text(format(_row_pattern, string(_i + 1)));

            yads_status_bar(_previous,
                (_fill.size <= 0) ? 0 : (_fill.used / _fill.size));

            // Bar AND number: the bar reads at a glance, the number is the
            // accessible, localisable truth.
            ANCHOR.text(_previous)
                .set_lut(COMMON_LUT)
                .set_align(Align.RightIn, Align.Middle)
                .set_x(-4)
                .set_text(format(_pct_pattern, string(_fill.pct)));
        }
    }

    // The footer, on the category box sprite so it reads as a summary rather
    // than as one more block.
    _previous = yads_status_row(_popup, _previous,
        ROW_TOP, ROW_WIDTH, ROW_HEIGHT, true);

    ANCHOR.text(_previous)
        .set_lut(COMMON_LUT)
        .set_align(Align.LeftIn, Align.Middle)
        .set_x(4)
        .set_text(format(yads_pattern(
                YADS_LOCAL_ROOT + "status_total", "Network {}% full"),
            string(_net_pct)));

    ANCHOR.text(_previous)
        .set_lut(COMMON_LUT)
        .set_align(Align.RightIn, Align.Middle)
        .set_x(-4)
        .set_text(format(yads_pattern(
                YADS_LOCAL_ROOT + "status_slots", "{} / {} slots"),
            string(_net_used), string(_net_size)));

    // 6d. Close, and go.
    _popup.create_button("misc_local/close");
    _popup.spawn();

    return _popup;
}

//
// 6e. THE SCROLLING STATUS POPUP
//
// Same report, no cap. Used when the block count outgrows what the fixed layout
// can print inside the 240px minspec canvas.
//
// scrolling_popup(title) (anchor_utils.gml:2038-2053) is the engine's own recipe
// and is used verbatim: a title-only popup_creator, a backplate forced to
// 180x200, a 160x156 positional root and create_scroller over it, with the
// scroller subscribed to the popup's pilot. It does NOT spawn - the caller does,
// after filling it - which is the whole reason it is usable from here.
//
// FOUR THINGS THIS LAYOUT INHERITS AND MUST RESPECT:
//
//   * Elements are 145px wide, not 180: create_scroller's default canvas is
//     (root.width + 2) - SCROLLBAR_WIDTH + 1 (Scroller.gml:459-462). Everything
//     anchored to a row's RIGHT edge - the fill bar at -34, the percentage at
//     -4 - keeps its spacing, because both are right-anchored; only the room for
//     the left-hand label shrinks, from 82px to 47. "Block 47" measures 44.
//
//   * Rows chain themselves. new_element adds `height - 1` of vertical space
//     (Scroller.gml:41), which is the same one-pixel border overlap the fixed
//     popup builds by hand, so ROW_HEIGHT here means the same thing it does up
//     there.
//
//   * NO Close button. The backplate is 200 tall and the scroller's viewport
//     already runs to y~189, so a button at Align.BottomIn/-10 would sit on top
//     of the list and the scroll bar. Vanilla's two scrolling_popup callers
//     (AnimalMenu.gml:297, :581) both spawn without one for exactly this reason,
//     and they lose nothing: AnchorMenu.run_exit_listening publishes the MenuBack
//     glyph through GLYPH_GUIDE every frame and closes on MenuBack or on a click
//     outside the backplate (AnchorMenu.gml:170-183).
//
//   * Gamepad scrolling is the scroller's own right-stick path
//     (scroll_with_stick, Scroller.gml:196-199, consumed at :281-287), NOT
//     add_to_pilot. These rows are reports: they have no tap callback, so
//     handing them to the pilot would build a column of focus stops that do
//     nothing on press and would put the D-pad in charge of a list that the
//     stick can already scroll. The pilot stays on the popup itself.
//
function yads_open_status_scrolling(_blocks, _net_used, _net_size, _net_pct, _panels) {
    static ROW_HEIGHT = 16;

    var _popup = scrolling_popup(YADS_LOCAL_ROOT + "status_title");

    var _scroller = _popup[$ "scroller"];
    if (_scroller == undefined) {
        // Cannot happen against this engine build; if a game update ever changes
        // the helper's shape, an unfilled popup is a better failure than a crash
        // in the heart's only interaction.
        _popup.spawn();
        return _popup;
    }

    _scroller.scroll_with_stick();

    // Header row. The fixed popup floats this line between the title bar and the
    // first row; there is no such gap here (the title header ends around y=24
    // and the scroller viewport starts at ~32), so it becomes the list's own
    // first element, on the category sprite - which is exactly what
    // Scroller.new_header does for a static key (Scroller.gml:46-49).
    var _block_count = array_length(_blocks);

    var _head = _scroller.new_element(ROW_HEIGHT);
    _head.set_sprites_from_key("spr_ui_generic_box_category");

    ANCHOR.text(_head)
        .set_lut(COMMON_LUT)
        .set_align(Align.Center, Align.Middle)
        .set_text(format(yads_pattern(
                YADS_LOCAL_ROOT + "status_blocks",
                "{} blocks connected"),
            string(_block_count)));

    // One row per block, all of them.
    var _row_pattern = yads_pattern(
        YADS_LOCAL_ROOT + "status_block_row", "Block {}");
    var _pct_pattern = yads_pattern(
        YADS_LOCAL_ROOT + "status_percent", "{}%");

    for (var _i = 0; _i < _block_count; _i++) {
        var _fill = _blocks[_i];
        var _row = _scroller.new_element(ROW_HEIGHT);

        ANCHOR.text(_row)
            .set_lut(COMMON_LUT)
            .set_align(Align.LeftIn, Align.Middle)
            .set_x(4)
            .set_text(format(_row_pattern, string(_i + 1)));

        yads_status_bar(_row,
            (_fill.size <= 0) ? 0 : (_fill.used / _fill.size));

        ANCHOR.text(_row)
            .set_lut(COMMON_LUT)
            .set_align(Align.RightIn, Align.Middle)
            .set_x(-4)
            .set_text(format(_pct_pattern, string(_fill.pct)));
    }

    // The footer, split across two centred rows rather than crammed left/right
    // into one. The fixed popup gets away with one 180px row because its two
    // halves have 88px each; at 145 they would be measuring the same pixels.
    // Two rows cost 15px in a list that scrolls and cannot collide in any
    // locale, which a single row could.
    var _total = _scroller.new_element(ROW_HEIGHT);
    _total.set_sprites_from_key("spr_ui_generic_box_category");

    ANCHOR.text(_total)
        .set_lut(COMMON_LUT)
        .set_align(Align.Center, Align.Middle)
        .set_text(format(yads_pattern(
                YADS_LOCAL_ROOT + "status_total", "Network {}% full"),
            string(_net_pct)));

    var _slots = _scroller.new_element(ROW_HEIGHT);
    _slots.set_sprites_from_key("spr_ui_generic_box_category");

    ANCHOR.text(_slots)
        .set_lut(COMMON_LUT)
        .set_align(Align.Center, Align.Middle)
        .set_text(format(yads_pattern(
                YADS_LOCAL_ROOT + "status_slots", "{} / {} slots"),
            string(_net_used), string(_net_size)));

    _popup.spawn();

    return _popup;
}

// Non-empty slot count, slot capacity, and the percentage the popup prints.
// count == 0 and item == undefined are the same state (InventorySlot.remove
// maintains the invariant), so either test alone would do; both are checked
// because every other slot loop in this mod checks both.
function yads_fill_of(_inventory) {
    var _size = _inventory.size();
    var _used = 0;

    for (var _i = 0; _i < _size; _i++) {
        var _slot = _inventory.slot(_i);
        if (_slot.count != 0 && _slot.item != undefined) { _used += 1; }
    }

    return {
        used: _used,
        size: _size,
        pct: (_size <= 0) ? 0 : floor(_used / _size * 100),
    };
}

// One row strip. The first hangs off the backplate at a fixed y; every later one
// chains off its predecessor at Align.BottomOut with set_y(-1), so consecutive
// borders share a pixel instead of doubling up - the vanilla help popup's own
// box_one..box_five idiom (StorageMenu.gml:619-664).
function yads_status_row(_popup, _previous, _top, _width, _height, _is_total) {
    var _sprite = _is_total ? spr_ui_generic_box_category : spr_ui_generic_box_main;

    if (_previous == undefined) {
        return ANCHOR.nine_slice(_popup.backplate)
            .set_sprite(_sprite)
            .set_align(Align.Center, Align.TopIn)
            .set_y(_top)
            .set_size(_width, _height);
    }

    return ANCHOR.nine_slice(_previous)
        .set_sprite(_sprite)
        .set_align(Align.Center, Align.BottomOut)
        .set_y(-1)
        .set_size(_width, _height);
}

// Width-driven fill inside a nine-sliced frame - the VitalsMenu idiom
// (VitalsMenu.gml:622-656). Both sprites are nine-slices (a 4x5 frame and a 1x2
// tintable strip), so the frame draws at any size and resizing the strip IS the
// bar; every other progress bar in the corpus is a fixed-width plate that cannot
// be reused at another length.
//
// Both are ANCHOR.nine_slice and not ANCHOR.sprite on purpose: the backplate
// sprite carries a Middle/Middle offset in its meta, which the nine-slice draw
// path ignores (Anchor.gml:904-905) and the plain-sprite path does not - as a
// sprite it would jump half its own size.
function yads_status_bar(_row, _fraction) {
    // 13 tall, not less: the backplate's frame_size is [4,5], so a nine-slice
    // shorter than 2*5 = 10 draws its border rows overlapped and its interior
    // with negative height (Anchor.gml:901). 13 is also the exact height the
    // engine's own only use of this sprite picks (VitalsMenu.gml:48, :622-626).
    // -34, NOT -28, and the six pixels are load-bearing. The
    // percentage beside this bar is RightIn/-4, so its LEFT edge sits at
    // row_right - 4 - string_width(text). In the standard font a digit is 6px
    // and '%' is 7 (fonts/text_widths.toml), so "99%" is 19 wide and starts 5px
    // clear of a bar ending at row_right - 28 - while "100%" is 25 wide and
    // starts at row_right - 29, ONE PIXEL INSIDE IT - so at -28 a full block, or
    // a full network, prints its last digit on top of the bar's frame. Moving
    // the bar rather than shrinking it keeps the fill geometry (60 wide, 54 of
    // travel, the 3px inset strip) exactly as VitalsMenu authored it.
    //
    // Row budget at -34, both callers: the fixed popup's 180px row keeps
    // 82px for the left-hand label and the scroller's 145px row keeps
    // 47. "Block 47" measures 44, so the tighter of the two still fits
    // - a three-digit block index would not, and a network with a hundred blocks
    // is on the scrolling variant where the label is the only thing that could
    // grow. Noted rather than defended: if it ever bites, the fix is a shorter
    // status_block_row string, not a narrower bar.
    var _frame = ANCHOR.nine_slice(_row)
        .set_sprite(spr_ui_hud_health_health_bar_backplate)
        .set_size(60, 13)
        .set_align(Align.RightIn, Align.Middle)
        .set_x(-34);

    var _width = round(54 * clamp(_fraction, 0, 1));

    // The nine-slice draw already guards on width > 0 (Anchor.gml:897), but
    // VitalsMenu zeroes the alpha as well (VitalsMenu.gml:160) and an empty
    // block should read as an empty frame rather than as a hairline.
    ANCHOR.nine_slice(_frame)
        .set_sprite(spr_ui_hud_health_bar_white)
        .set_size(_width, 7)
        .set_xy(3, 3)
        .set_alpha((_width == 0) ? 0 : 1)
        .set_color(make_color_rgb(64, 200, 214));   // the set's cyan

    return _frame;
}

//
// 7. THE NETWORK PICKER
//
// One row per Storage Heart that holds a Remote Access Panel: tap the row to
// open that network, tick the box beside it to make that network the one a TAP
// of the hotkey goes to from now on. Opened by a HOLD of the hotkey, and by a
// tap when the choice is genuinely open (several bound, no default). Section 5c
// of boot.gml carries the gesture ladder and the arming predicate; this file is
// only the surface.
//
// IT MOVES NO ITEMS. There is no mirror, no shadow, no reconciler and no hand:
// the picker reads inventories to print two numbers per row and writes nothing
// but three keys in the config file. That is why it has no teardown worth the
// name - ui.menu_closed releases the registration and the canvas took the nodes
// with it.
//
// WHY A Menu.Popup, and it is the same argument the status popup makes: it is
// the only menu type a mod can spawn outright. A hand-rolled AnchorMenu subtype
// has to borrow an existing menu's fiddle config (AnchorMenu.gml:63 reads
// MENUS.get_unwrap(type), and MENUS comes only from
// fiddle_get_directory("ui/menus")), which then lets ANCHOR.get_menu find two
// menus of one type and trip its "more than one was open" assert
// (Anchor.gml:154-174) - and borrowing Menu.Storage would collide with the very
// view this list exists to open.
//
// AND A POPUP CARRIES TAPS, which is the finding that settled the surface. The
// status popup uses none, so it proved only that a popup can hold text. But
// PopupMenu.create_button (PopupMenu.gml:58-108) is itself a nine-slice on the
// backplate with set_sprites_from_key, add_hover_outline, set_tap_callback and
// add_to_pilot - i.e. the engine's own popup buttons are ordinary ANCHOR
// clickables parented to the backplate, built by the same calls the network
// view's sort button and clear-X are built by. There is no second plumbing to
// discover; the rows below are create_button's shape with our own geometry.
//
// Three inherited behaviours we do not have to build:
//
//   * ESC AND PAD-BACK CLOSE IT. The canvas think runs run_exit_listening every
//     frame (PopupMenu.gml:301-305), which closes on InputId.MenuBack or on a
//     click outside the backplate, and the single Close button gets MenuBack
//     plus its glyph for free as button #1 (:87-106).
//   * IT PAUSES LIKE EVERY OTHER MENU. [popup] declares pause = "main"
//     (ui/menus/misc_menus.toml), applied in AnchorMenu.initialize
//     (AnchorMenu.gml:111-112), so game_paused() holds while the list is up -
//     which is also what makes yads_remote_ready refuse a second press.
//   * THE PILOT IS THE POPUP'S. spawn() takes it (PopupMenu.gml:260-263) and
//     on_close hands the previous one back (:49-51).
//
// TWO HOVER LISTENERS PER ROW, AND THEY DO NOT OVERLAP. See the geometry note
// over yads_picker_row.
//
function yads_open_picker(_scan) {
    // Layout budget, measured the way the status popup's is. The row pitch is
    // the row height exactly - these are POSITIONAL containers, which have no
    // border to share, so the -1 overlap the status popup's nine-slices chain
    // with would be a real one-pixel bite here. The 2px of air between
    // consecutive rows comes from the 16px controls sitting Middle-aligned
    // inside an 18px row instead.
    //
    // 250 WIDE, NOT THE STATUS POPUP'S 200, and the number is derived from the
    // row rather than chosen: the summary is up to "35 blocks, 100%" = 80px in
    // the standard font (fonts/text_widths.toml), the name is trimmed to 14
    // characters (~84px, and up to ~105 once a "(2)" disambiguator is on it),
    // and RightIn/LeftIn insets plus a gap take 12 more. 208 of open button
    // clears that with ~10px to spare; 158 - what a 200px plate would have
    // given - does not.
    //
    // HEIGHT: ROW_TOP + (n-1)*PITCH + ROW_HEIGHT + hint + Close. At the
    // YADS_PICKER_ROWS cap of 8 that is 30 + 126 + 18 + 4 + 11 + 8 + 10 = 207
    // plus COMMON_BUTTON_HEIGHT, which is locale-dependent (anchor_utils.gml:10)
    // and measures 19 in English, ~20 worst known locale - so 226-227 against
    // the 240px minspec canvas (Display.gml:4). 13px of margin, not generous;
    // anything added below the rows must re-run this arithmetic.
    static PLATE_WIDTH = 250;
    static HEADER_HEIGHT = 24;
    static ROW_WIDTH = 230;
    static ROW_HEIGHT = 18;
    static ROW_TOP = 30;
    static OPEN_WIDTH = 208;
    static BOX_SIZE = 16;
    static HINT_GAP = 4;
    static HINT_HEIGHT = 11;
    static NAME_CHARS = 14;

    var _entries = _scan.entries;
    var _listed = min(array_length(_entries), YADS_PICKER_ROWS);

    var _picker = {
        menu: undefined,
        // EVERY entry, not just the listed ones: default_index can point past
        // the cap because entries are ordered current-location-first, so a
        // default bound in another room can be pushed past row 8 by however
        // many local networks sort ahead of it (not by "fewer networks were
        // bound before" - the index is recomputed per scan). The tap ladder in
        // boot.gml is right to keep honouring it. KNOWN EDGE (B12p A-m2): in
        // that state the hint says a default exists but no listed checkbox is
        // lit, and unticking it needs the default's own row - reachable only
        // past 8 bound networks; accepted. Only `choice` is constrained to
        // the rows that exist, because only a row can produce one.
        entries: _entries,
        default_index: _scan.default_index,
        choice: undefined,
        closing: false,
        hint: undefined,
        hint_set: "",
        hint_hold: "",
        // 7f, the rebind capture. `capture` is undefined except while the
        // picker is listening for a key; `flash` counts down the frames the
        // hint holds an answer before returning to its two steady states.
        hint_capture: "",
        capture: undefined,
        flash: 0,
        flash_text: "",
    };

    // 7a. Shell. Everything is built BEFORE spawn(): spawn asserts on a second
    //     call and is what enables the canvas, mutes input and takes the pilot
    //     (PopupMenu.gml:233-243).
    var _height = ROW_TOP + max(_listed - 1, 0) * ROW_HEIGHT + ROW_HEIGHT
        + HINT_GAP + HINT_HEIGHT + 8 + COMMON_BUTTON_HEIGHT + 10;

    var _popup = popup_creator(YADS_LOCAL_ROOT + "picker_title");

    _popup.backplate.set_size(PLATE_WIDTH, _height);

    // add_title sized the header against the default 180px backplate, so this
    // has to run after the resize (StorageMenu.gml:616-619 does the same).
    _popup.header
        .set_xy(0, 0)
        .set_sprite(spr_ui_tooltip_header_box)
        .set_size(_popup.backplate.get_width(), HEADER_HEIGHT);

    // 7b. The rows.
    var _pilot = _popup.pilot;
    var _previous = undefined;
    var _seen = {};

    var _summary_pattern = yads_pattern(
        YADS_LOCAL_ROOT + "picker_summary", "{} blocks, {}%");
    var _network_pattern = yads_pattern(
        YADS_LOCAL_ROOT + "picker_network", "Network {}");
    var _dup_pattern = yads_pattern(
        YADS_LOCAL_ROOT + "picker_dup", "{} ({})");

    for (var _i = 0; _i < _listed; _i++) {
        var _entry = _entries[_i];
        var _node = _entry.node;

        // The two numbers that tell one network from another. A full flood-fill
        // per row is fine here and nowhere else: it happens once, on a frame
        // the player asked for a list, on a paused game - the same cost the
        // heart's own status popup pays on every interact.
        // COUNT PARITY: this counts deposit_targets unfiltered; the status
        // popup filters for a live inventory first. Identical today (every
        // block is a chest and carries one), but these two surfaces print the
        // same sentence - if either count ever changes, change both.
        var _net = yads_scan(_node);
        var _blocks = array_length(_net.deposit_targets);

        var _used = 0;
        var _size = 0;
        var _members = _net.members;
        for (var _m = 0; _m < array_length(_members); _m++) {
            var _inventory = _members[_m][$ "inventory"];
            if (_inventory == undefined) { continue; }
            var _fill = yads_fill_of(_inventory);
            _used += _fill.used;
            _size += _fill.size;
        }
        var _pct = (_size <= 0) ? 0 : floor(_used / _size * 100);

        // The row's name. Trimmed by CHARACTERS in GML rather than by
        // set_max_characters on the node, because the disambiguator has to
        // survive the trim: "Sunnyside Farmstead (2)" truncated by the node
        // would lose the one part of it that disambiguates anything.
        var _label = yads_loc_name(_node[$ "parent_grid"]);
        if (!is_string(_label) || _label == "") {
            _label = format(_network_pattern, string(_i + 1));
        } else if (string_length(_label) > NAME_CHARS) {
            _label = string_copy(_label, 1, NAME_CHARS);
        }

        // Two hearts in one room are two rows with one name, so the second and
        // later get a count. Keyed on the trimmed label, which is what the
        // player actually reads - two different long names that trim to the
        // same 14 characters are as ambiguous on screen as two identical ones.
        var _times = _seen[$ _label];
        _times = (_times == undefined) ? 1 : _times + 1;
        _seen[$ _label] = _times;
        if (_times > 1) {
            _label = format(_dup_pattern, _label, string(_times));
        }

        _previous = yads_picker_row(_popup, _previous, ROW_TOP,
            ROW_WIDTH, ROW_HEIGHT);

        var _open = common_slice(_previous, OPEN_WIDTH, BOX_SIZE)
            .set_align(Align.LeftIn, Align.Middle)
            .set_x(0)
            .set_tap_sound("SoundEffects/UI/UIExtraPositiveClick")
            .set_tap_callback(yads_tap_picker_open, [_picker, _i])
            .add_to_pilot(_pilot);

        ANCHOR.text(_open)
            .set_lut(COMMON_LUT)
            .set_align(Align.LeftIn, Align.Middle)
            .set_x(4)
            .set_text(_label);

        ANCHOR.text(_open)
            .set_lut(COMMON_LUT)
            .set_align(Align.RightIn, Align.Middle)
            .set_x(-4)
            .set_text(format(_summary_pattern, string(_blocks), string(_pct)));

        // THE CHECKBOX. common_slice hands us the whole spr_ui_generic_box
        // state set including SELECTED, read every frame by the engine's own
        // sprite state machine (Anchor.gml:600-618) - but in_hover short-
        // circuits BEFORE is_selected in that ladder, so on a gamepad the
        // focused row's box shows hover, never selection. The tick glyph is
        // therefore not decoration: it is the ONLY default indicator a pad
        // player sees. It is the vanilla settings screen's own pair
        // (SettingsMenu.gml:66-71 swaps exactly these two sprites from a
        // think callback).
        //
        // add_to_pilot with newline_after, so a pad walks DOWN the networks and
        // LEFT/RIGHT between "open it" and "make it default" - one pilot row per
        // network, and the Close button alone on the row after the last.
        var _box = common_slice(_previous, BOX_SIZE, BOX_SIZE)
            .set_align(Align.RightIn, Align.Middle)
            .set_x(-2)
            .set_tap_sound("SoundEffects/UI/UIExtraPositiveClick")
            .set_tap_callback(yads_tap_picker_default, [_picker, _i])
            .set_selected_getter(yads_picker_default_selected, [_picker, _i])
            .add_to_pilot(_pilot, true);

        var _glyph = ANCHOR.sprite(_box)
            .set_sprite(spr_ui_generic_checkbox_off)
            .set_align(Align.Center, Align.Middle);

        // ON THE BOX, NOT ON THE GLYPH: set_think_callback sets run_logic
        // itself (Node.gml:540-550), so either node could host the think - the
        // box is chosen because common_slice installs no think of its own, so
        // this overwrites nothing and logs no Warn (the glyph is plain too,
        // but the box is the node whose selected-getter already owns this
        // row's state; one node, one owner). The glyph is passed by reference
        // rather than looked up through an index, so the poll cannot be
        // pointed at the wrong row by a later edit to the build order.
        //
        // spr_ui_generic_checkbox_{on,off} is a PAIR, not a two-frame sprite,
        // and it is deliberately NOT driven through set_sprites_from_key: the
        // key is absent from ui/misc.toml's button_sprite_prefixes and
        // load_button_sprites resolves _enabled/_main/_pressed/_hovered/
        // _selected/_locked, none of which is _on or _off
        // (anchor_utils.gml:2502-2517). Every one of vanilla's eight call sites
        // swaps the asset on a plain ANCHOR.sprite the way this does.
        _box.set_think_callback(yads_picker_glyph_think,
            [_picker, _i, _glyph]);
    }

    // 7c. The hint line, under the last row.
    //
    // TWO STATES ON ONE NODE rather than one state and a visibility flip. The
    // checkbox column is otherwise uncaptioned - there is no room for a header
    // over a 16px column - so the line has to say what the box does. BOTH
    // STATES ALSO NAME THE HOLD, and that is the correction this wave shipped:
    // the hold is the only route to this surface, and the Rebind button in its
    // footer is the only way to change the remote key in game, so a player who
    // never learns the hold is locked out of the mod's settings. State A
    // teaches it; state B repeats it beside the tap it has just re-pointed. The
    // node never appears or disappears, so the layout below it cannot move, and
    // both strings are built ONCE here rather than re-resolved every frame in
    // the poll.
    //
    // THE HOLD CLAIM IS TRUE IN EVERY VISIBLE STATE, which is the property the
    // picker audit praised in the old wording ("the hint mentions the hold
    // exactly where the hold is armed") - restated for the predicate that
    // replaced it, `armed <=> (C == 1 || D)`, where it is no longer a plain
    // complement:
    //
    //   state B (D)          armed; the hold produces this list after 400ms.
    //   state A, C = 1       armed; same.
    //   state A, C >= 2      NOT armed - and the hold still produces this list,
    //                        because the PRESS FRAME does (boot.gml 5c). The
    //                        line promises the list, not the latency, so it is
    //                        true here too: sooner, not never.
    //
    // A hold taken while the picker is already up does nothing in any of the
    // three, and that is the tick guard rather than the wording:
    // yads_remote_ready refuses every press with _rt.picker set
    // (boot.gml:1608), so no state can re-open what the player is reading.
    //
    // THE HOTKEY NAME IS COMPOSED, NOT INTERPOLATED INTO LOC TEXT. That
    // distinction is the whole reason the remote's TOASTS carry no numbers:
    // create_notification resolves whatever it is handed through local_get
    // (InfoToastsMenu.gml:31), so a toast can only carry a key. A TEXT NODE is
    // the other case - the pattern is resolved first and format() fills it, the
    // way the pager's counter and every status row already do - so the
    // configured key name goes in safely here and could not have gone into a
    // toast at all.
    //
    // THE NAME COMES FROM THE LIVE BINDING, NEVER FROM THE CONFIG STRING.
    // yads_config validates remote_hotkey as "a non-empty string" and nothing
    // more (boot.gml:441-442), and an unresolvable name is deliberately NOT
    // repaired: yads_install_hotkeys warns, takes vk_f6, and leaves the
    // player's text in the file (boot.gml:980-989) because it is their text and
    // may be a name a later mmapi resolves. So the field can say "CTRL+F6"
    // while the live key is F6 - and reading it here would print
    // "Tap CTRL+F6 = default" on the ONE surface that exists to repair that
    // typo, naming a key that does nothing and contradicting the remote_key_bad
    // toast that has just said "using F6" (boot.gml:1646-1648).
    // mmapi_hotkey_name_from_vk is the same reverse lookup the commit trusts
    // (7f), so this line reports what the registry will actually answer to. The
    // file self-heals on the next successful rebind, which writes the same
    // function's output (:4857, :4874).
    //
    // WIDTH, and the bound is now TRUE rather than assumed, because the source
    // is a reverse lookup instead of arbitrary player text. name_from_vk can
    // only return a name whose FORWARD lookup yields this same vk
    // (payload:88-92), and the forward map resolves exactly our vocabulary:
    // single digits and letters, F1-F12, INSERT, DELETE, HOME, PAGE_UP,
    // PAGE_DOWN, SHIFT, CONTROL (payload:11-56). Its other names - NUMPAD_0-9,
    // ALT, CAPS_LOCK, NUM_LOCK, SCROLL_LOCK, PAUSE_BREAK - all resolve forward
    // to undefined (payload:44-52) and so can never match a real vk, and the
    // "vk <ordinal>" fallback needs a non-real vk, which _rt.remote_vk cannot
    // be (boot.gml:980-996). The longest name in that set is "PAGE_DOWN", so
    // both lines are measured with it substituted in, against a 250px plate:
    // "Tick a default, hold PAGE_DOWN = this list" is 224px and
    // "Tap PAGE_DOWN = default, hold = this list" is 220px (173 and 169 with
    // "F6"). These keys have no translations, so the English width is the width
    // in every locale; keep any replacement under 240 with PAGE_DOWN in it.
    //
    // ONE LOOKUP FEEDS BOTH, now that state A names the key as well - two calls
    // could not disagree today, but the pair is one fact and reads as one.
    var _key_name = mmapi_hotkey_name_from_vk(yads_runtime().remote_vk);

    _picker.hint_set = format(
        yads_pattern(YADS_LOCAL_ROOT + "picker_default",
            "Tick a default, hold {} = this list"),
        _key_name);
    _picker.hint_hold = format(
        yads_pattern(YADS_LOCAL_ROOT + "picker_hold_hint",
            "Tap {} = default, hold = this list"),
        _key_name);

    // THIRD STATE, and the only one that is not about the checkbox column: the
    // line the hint shows while the Rebind button has the picker listening for
    // a key (7f). Built here with the other two so the capture think never
    // resolves a pattern on a frame it is polling the keyboard.
    //
    // Measured like its siblings: 173px in the standard font against a 250px
    // plate, no substitution to widen it. "ESC" is spelled rather than glyphed
    // because the cancel is taken through InputId.MenuBack, which a player may
    // have rebound - the word names the default and the button below still
    // carries the real glyph.
    _picker.hint_capture = yads_pattern(
        YADS_LOCAL_ROOT + "picker_capture", "Press a key to use - ESC cancels");

    // Plain COMMON_LUT with no index, which is what the engine puts on this
    // exact backplate (PopupMenu.add_description, :153-160) and what the status
    // popup's own subtitle uses. CommonLutIndex.Dark is for text sitting on a
    // BUTTON or inside a cream text field; on the popup plate it would be the
    // one line in the menu nobody can read.
    _picker.hint = ANCHOR.text(_popup.backplate)
        .set_lut(COMMON_LUT)
        .set_align(Align.Center, Align.TopIn)
        .set_y(ROW_TOP + max(_listed - 1, 0) * ROW_HEIGHT + ROW_HEIGHT + HINT_GAP)
        .allow_line_breaks(false)
        .set_text(_picker.hint_set);

    // The poll that keeps it honest, ON THE BACKPLATE - the one node in this
    // menu that exists for as long as any row does and is never disabled.
    // set_think_callback sets run_logic and NOTHING else (Node.gml:540-550), so
    // this does not turn the backplate into a hover listener that could steal
    // from the rows sitting on it.
    _popup.backplate.set_think_callback(yads_picker_think, [_picker]);

    // 7d. Close, stamp, go.
    //
    // request_newline first, or create_button's own add_to_pilot lands the
    // Close button beside the last row's checkbox (PopupMenu.gml:83-85).
    _pilot.request_newline();
    _popup.create_button("misc_local/close");

    // THE REBIND BUTTON, AND IT MUST COME SECOND. create_button glyphs and
    // positions by button INDEX: #1 takes InputId.MenuBack and its glyph
    // (PopupMenu.gml:87-90, :104-106), #2 takes InputId.Interact, and only at #2
    // does auto_position pull the first button 40px left and push this one 40px
    // right (:91-97). Registering Rebind first would move the ESC glyph onto it
    // and leave Close answering Interact - so Close stays button #1 and this is
    // strictly an addition to the row below the list.
    //
    // ZERO HEIGHT COST. Both buttons are Align.Center/BottomIn at y = -10
    // (:67-70) - one row, two x-offsets - so the plate-height arithmetic over
    // 7a is unchanged and the 8-row worst case still clears the 240px minspec.
    //
    // WIDTH, MEASURED, because two tap targets on one row is the overlap
    // question anchor-ui-facts.md exists to ask. create_button sizes to
    // max(60, string_width(label) + 18) (:64-66). "Rebind key" is 56px in the
    // standard font -> 74 wide, centred at +40, so it spans +3..+77 inside a
    // 125px half-plate. Close is 60 wide in English and 62 in Russian, its
    // widest translation of the seven shipped (rus "Закрыть"), centred at -40 ->
    // -71..-9. The gap is 12px of dead plate and Close would have to reach 86px
    // to touch, which is 68px of label against a longest-known 44. They cannot
    // overlap, so there is no hover to steal and no listen_for_hovers gate to
    // keep alive. This key is ours and untranslated, so 74 is its width in every
    // locale; re-run this arithmetic before re-wording it.
    //
    // remove_glyph() IS NOT COSMETIC. add_glyph installs a think that calls
    // ANCHOR.tap_node(self) whenever INPUT.take_press(input_id) succeeds
    // (Node.gml:1832-1839), so the Interact glyph #2 inherits would make E (or
    // right-click) press Rebind from anywhere in the picker. Freeing the glyph
    // node (Node.gml:1847-1853) takes the think with it. Vanilla does exactly
    // this on its own two-button popups (SettingsMenu.gml:801, :812).
    //
    // close_on_button_tap = false, the SEVENTH argument, or create_button's
    // wrapper closes the popup before our callback runs (:74-79) and the capture
    // would have no surface left to live on.
    _popup.create_button(YADS_LOCAL_ROOT + "picker_rebind",
        yads_tap_picker_rebind, [_picker], undefined, undefined, true, false)
        .remove_glyph();

    // ui.menu_closed reports kind == Menu.Popup for every vanilla popup too, so
    // stamp the instance. Dynamic fields on menu structs are normal - the engine
    // reads `e[$ "is_tooltip"]` off them (Anchor.gml:178). Written BEFORE spawn
    // so the stamp exists from the first frame the menu is live.
    _popup.netstor_picker = _picker;
    _picker.menu = _popup;

    // on_close is PopupMenu's own and does real bookkeeping (the popup stack,
    // the pilot hand-back), so it is NOT replaced the way the view's is. The
    // close_callback slot exists for exactly this and is invoked last
    // (PopupMenu.gml:52-54).
    _popup.close_callback = method(_popup, function() {
        yads_picker_closing(self);
    });

    _popup.spawn();

    // REGISTERED AFTER spawn(), which is the OPPOSITE of yads_open_view's rule,
    // and the asymmetry is the point. There, early registration is what attaches
    // the reconciler to a menu that already holds withdrawable mirror items, and
    // the worst case of registering early - a live menu nobody can clear - is
    // impossible because a Storage menu can always be closed. Here there is no
    // custody to attach and the worst case runs the other way: a throw between
    // popup_creator and spawn() leaves an UNSPAWNED popup on ANCHOR.open_menus
    // with a disabled canvas, which never runs run_exit_listening and therefore
    // can never be closed by the player. Registering that as _rt.picker would
    // make yads_remote_ready refuse every press for the rest of the session.
    // The orphan itself is the status popup's exposure too, and unchanged by
    // where this line sits; what this line decides is whether the hotkey dies
    // with it.
    yads_runtime().picker = _picker;

    return _picker;
}

// One row container, chained off its predecessor the way the status popup's
// rows are - except these are POSITIONAL nodes and chain at set_y(0) rather
// than -1, because a positional has no border for consecutive rows to share.
//
// THE GEOMETRY IS THE HOVER ARGUMENT, so it is written out here rather than
// left to be re-derived. ANCHOR grants hover to AT MOST ONE node and hover_node
// releases the previous holder unconditionally, wiping its in_hover, in_tap AND
// tap_is_deferred (Anchor.gml:1806, :1862-1864) - so two OVERLAPPING hover
// listeners cannot both work, in either registration order, and the Beta 1.1
// clear-X bug was exactly that. The clear-X had no way out of the overlap: it
// has to sit INSIDE the text plate because the plate is the field. A picker row
// has no such constraint, so it takes the cheaper answer the bottom bar's own
// layout note already states - "keep the gaps" (section 2a) - and the two
// controls are non-overlapping siblings:
//
//   row (positional, 230 x 18)          local x 0..230, y 0..18
//     open   LeftIn  x 0,  208 x 16     x   0..208, y 1..17
//     box    RightIn x -2,  16 x 16     x 212..228, y 1..17
//
// RightIn is cache_x = x + parent.cache_x + parent.width - node.width
// (anchor_utils.gml:232-239) and Align.Middle is floor((18 - 16)/2 + 0.5) = 1
// (:267-273), so both controls lie wholly inside the row and 4px of dead
// positional apart. No listen_for_hovers gate, no per-frame poll to keep one
// alive, and no bbox trim - the trims the clear-X needs exist to pull an 18px
// sprite back inside a 14px plate, and nothing here overhangs anything.
//
// The container itself takes no hovers to steal: it carries no tap callback, and
// listens_for_hovers is only ever set by set_tap_callback / listen_for_taps
// (Node.gml:519-520, :486-487). Same for the backplate above it, whose think
// callback sets run_logic alone (:540-550).
function yads_picker_row(_popup, _previous, _top, _width, _height) {
    if (_previous == undefined) {
        return ANCHOR.positional(_popup.backplate)
            .set_size(_width, _height)
            .set_align(Align.Center, Align.TopIn)
            .set_y(_top);
    }

    return ANCHOR.positional(_previous)
        .set_size(_width, _height)
        .set_align(Align.Center, Align.BottomOut)
        .set_y(0);
}

//
// 7e. THE PICKER'S CALLBACKS
//
// Tapping a row RECORDS the choice; boot.gml's tick closes this menu and opens
// that network one frame later. Tapping a checkbox writes the config file
// straight through, exactly like the sort cycle and the value toggle - the
// setting is a FILE, not view state, and it should survive an alt-F4 taken one
// second later.
//

function yads_tap_picker_open(_picker, _index) {
    if (_picker.closing == true) { return; }
    _picker.choice = _index;
}

// Ticking the row that is ALREADY the default clears it, the same gesture the
// filter bar uses for its lit button: every player expects a single-select
// control to be dismissable by pressing the lit one again, and there is nowhere
// else in this UI to say "no default, ask me every time".
//
// SINGLE DEFAULT BY CONSTRUCTION. There is one triple of keys in the file and
// one default_index on the picker, so setting row B does not have to clear row
// A - it overwrites the only slot there is, and every checkbox's selected
// getter reads that one number.
function yads_tap_picker_default(_picker, _index) {
    if (_picker.closing == true) { return; }

    var _entries = _picker[$ "entries"];
    if (_entries == undefined) { return; }
    if (_index < 0 || _index >= array_length(_entries)) { return; }

    var _cfg = yads_config();

    if (_picker.default_index == _index) {
        _picker.default_index = -1;
        _cfg.remote_default_loc = "";
        _cfg.remote_default_x = -1;
        _cfg.remote_default_y = -1;
    } else {
        var _entry = _entries[_index];

        // A heart whose grid could not be named, or whose coordinates are not
        // numbers, is one yads_remote_scan could never match again - the tick
        // would be written to disk and then silently fail validation on every
        // press. Refused instead: the box does not light, and the row still
        // opens its network. Not reachable against this engine (Grid's
        // constructor takes location_id as a required argument, Grid.gml:14,
        // :45, and every placed node carries a top_left), and cheap enough that
        // the invariant is enforced rather than assumed.
        if (!is_string(_entry.loc) || _entry.loc == "") { return; }
        if (!is_real(_entry.tx) || !is_real(_entry.ty)) { return; }

        _picker.default_index = _index;
        _cfg.remote_default_loc = _entry.loc;
        _cfg.remote_default_x = _entry.tx;
        _cfg.remote_default_y = _entry.ty;
    }

    mmapi_config_write(YADS_MOD,
        YADS_CONFIG_VERSION, _cfg);
}

// Read every frame by the engine's own sprite state machine (Anchor.gml:600-618)
// via Node.is_selected, which is what lights the generic box without a think.
function yads_picker_default_selected(_picker, _index) {
    return (_picker.default_index == _index);
}

// The tick glyph, swapped on the frame the state changes. set_sprite is a plain
// assignment, so this is one compare and at most one write per row per frame.
function yads_picker_glyph_think(_picker, _index, _glyph) {
    if (_picker.closing == true) { return; }
    if (_glyph == undefined) { return; }

    _glyph.set_sprite((_picker.default_index == _index)
        ? spr_ui_generic_checkbox_on
        : spr_ui_generic_checkbox_off);
}

// The hint line's poll, AND the host of the rebind capture (7f). set_text
// short-circuits on an unchanged string (Node.gml:1046-1048) and every string
// below was built at open or at commit, so the steady state is still one struct
// read and one compare.
//
// THE CAPTURE RIDES THIS THINK RATHER THAN A NODE OF ITS OWN. It needs a
// per-frame call inside ANCHOR's pass and nothing else; a new node would be a
// new entry in the walk, and any node that took taps would be a new hover
// listener over a plate that already has two per row. The backplate is the one
// node in this menu that outlives every row and is never disabled, which is why
// the hint poll was put here in the first place.
//
// A LOCKED CANVAS KEEPS THINKING, which is what makes that possible while the
// capture has the picker locked: the node loop gates on run_logic &&
// safe_enabled && !marked_for_death and nothing else (Anchor.gml:374), while
// lock only touches safe_unlocked, which gates the hover/tap arm (:377). This
// is the same fact yads_picker_closing already relies on.
function yads_picker_think(_picker) {
    if (_picker.closing == true) { return; }

    var _hint = _picker[$ "hint"];
    if (_hint == undefined) { return; }

    // Listening for a key. Everything else about the picker is frozen.
    var _capture = _picker[$ "capture"];
    if (_capture != undefined) {
        yads_picker_capture_think(_picker, _capture, _hint);
        return;
    }

    // Holding an answer the player has just been given. Counted down here and
    // nowhere else, so a picker that closes mid-flash simply stops counting.
    if (_picker.flash > 0) {
        _picker.flash -= 1;
        _hint.set_text(_picker.flash_text);
        return;
    }

    _hint.set_text((_picker.default_index >= 0)
        ? _picker.hint_hold
        : _picker.hint_set);
}

//
// 7f. THE REBIND CAPTURE
//
// Tap "Rebind key", press a key, and that key is the remote key from the next
// frame on - registry, config file and hint together, with no restart and no
// file to edit. boot.gml section 5d carries the registry half (why the live
// entry can be re-pointed at all, and the permanent dead flag the capture proof
// retires); this is the surface and the policy.
//
// THE LOCK IS THE LEVER, and it does three jobs with one call. While
// _picker.capture is set the menu is locked, which:
//
//   * takes the rows, the checkboxes and Close out of the node loop's
//     clickable arm, which is gated on listens_for_hovers && safe_unlocked
//     (Anchor.gml:377), so a stray click cannot open a network out from under
//     the capture. It removes the TAP, not every hover: ANCHOR.try_pilot_hover
//     grants hover on !node.freed alone, with no safe_unlocked test
//     (Anchor.gml:1911-1923), so a pad hover mark can still land on a locked
//     node. Nothing comes of it, and what actually protects pad input during
//     capture is three other facts - the pilot cannot MOVE, because
//     position_is_valid returns node.safe_unlocked (Pilot.gml:298-307) and an
//     all-locked map makes find_first_acceptable_node return Freeze
//     (:318-320, :440-442); every mouse tap route runs through the gate above;
//     and the only pad CONFIRM route left on this plate is Close's glyph think,
//     itself gated on is_unlocked() (Node.gml:1833-1839), Rebind's glyph having
//     been removed at build time;
//   * stops the popup closing on ESC or on a click outside the plate -
//     run_exit_listening reads canvas.is_unlocked() and bails on false
//     (AnchorMenu.gml:170-183), which is what leaves InputId.MenuBack unclaimed
//     for us to read as "cancel";
//   * leaves every THINK running, because thinks are gated on run_logic &&
//     safe_enabled and lock touches neither (Anchor.gml:374).
//
// WHY LOCK AND NOT manual_exit_listening = false. Clearing that flag is how
// vanilla's own rebind popup refuses ESC (SettingsMenu.gml:797), but it is the
// wrong tool here: it silences the exit listener and NOTHING else, so the rows
// underneath would still be live and a click on one would open a network while
// the capture was still waiting for a key. Vanilla does not have that problem
// because its capture is a fresh popup with nothing else on it - and it still
// locks the surface behind it (option_scroller.lock(), :795). One lock closes
// both halves for us; the ESC behaviour is a consequence of it rather than a
// second mechanism to keep in step.
//
// UNLOCK RESTORES EXACTLY WHAT WAS THERE. set_unlocked propagates to children
// with personal = false, which leaves each child's own `unlocked` untouched and
// recomputes safe_unlocked from it (Node.gml:578-590) - so no node in this menu
// can come back unlocked that was not unlocked before.
//

// Enter capture. Called from the footer button's tap, i.e. from inside ANCHOR's
// node walk, which is precisely why the first frame is skipped below.
function yads_tap_picker_rebind(_picker) {
    if (_picker.closing == true) { return; }
    if (_picker[$ "capture"] != undefined) { return; }

    var _menu = _picker[$ "menu"];
    if (_menu == undefined) { return; }

    // Resolved ONCE, here, so the per-frame poll is a plain loop over codes the
    // engine has already accepted - see yads_rebind_vocab.
    _picker.capture = { armed: false, vocab: yads_rebind_vocab() };
    _picker.flash = 0;
    _menu.lock();
}

// Leave capture, whatever the reason. The single unlock site.
function yads_picker_capture_end(_picker) {
    _picker.capture = undefined;

    var _menu = _picker[$ "menu"];
    if (_menu == undefined) { return; }
    _menu.unlock();
}

// The mmapi keyboard vocabulary, resolved and probed once at capture entry.
//
// THESE 55 NAMES ARE THE WHOLE SPACE, and the reason is round-tripping rather
// than taste. The captured key has to be written to the config file as a NAME,
// and the only names that will parse back are the ones
// mmapi_hotkey_vk_from_name accepts (mmapi_hotkeys.gml payload:11-56): A-Z,
// 0-9, F1-F12 and seven named specials. The engine's own KEYBOARD_INPUTS array
// is far wider (InputUtils.gml:123-200 has space, tab, enter, the bracket and punctuation
// keys, the arrows) and every one of those extra keys would capture fine and
// then fail to survive a restart - a rebind that silently undoes itself is
// worse than one that never offered the key.
//
// PROBED WITH keyboard_check INSIDE try, WHICH IS MMAPI'S OWN IDIOM
// (mmapi_hotkeys.gml payload:169-175): the engine throws on a KeyCode it has
// no entry for, and a name the resolver maps to such a code would otherwise
// throw once per frame from inside the capture poll. Dropping the throwers here is what
// lets the poll below run without a try/catch of its own - the same trade
// yads_remote_hold_poll makes, one step earlier.
//
// The probe is also the FIRST HALF of the proof that lets a captured vk be
// written into a live mmapi entry (boot.gml 5d(3)); the second half is the
// keyboard_check_pressed that actually selects it.
function yads_rebind_vocab() {
    static NAMES = [
        "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M",
        "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z",
        "0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
        "F1", "F2", "F3", "F4", "F5", "F6",
        "F7", "F8", "F9", "F10", "F11", "F12",
        "INSERT", "DELETE", "HOME", "PAGE_UP", "PAGE_DOWN", "SHIFT", "CONTROL",
    ];

    var _out = [];
    for (var _i = 0; _i < array_length(NAMES); _i++) {
        var _name = NAMES[_i];

        // Guarded for the same reason mmapi guards its own reverse lookup
        // (mmapi_hotkeys.gml payload:88-92): the resolver reads bare vk_*
        // constants, which the live runtime defines and a tier-1 VM does not.
        var _vk = undefined;
        try { _vk = mmapi_hotkey_vk_from_name(_name); } catch (__yads_rebind_name) {}
        if (_vk == undefined) { continue; }

        var _ok = false;
        try { keyboard_check(_vk); _ok = true; } catch (__yads_rebind_probe) {}
        if (!_ok) { continue; }

        array_push(_out, { vk: _vk, name: _name });
    }

    return _out;
}

// May we take this key, and what do we owe the player if we do?
//
// ORDERED SO THAT ONE COMPARE ANSWERS THE FIRST QUESTION: anything below
// YADS_REBIND_OK is a refusal. The verdict is also the message (see
// yads_rebind_message), so a deny and its reason cannot drift apart.
//
// DENY - RESERVED. Seven names this mod or its tooling already owns:
//
//   SHIFT       are the EDITOR'S OWN MODIFIER KEYS, and that is the reason -
//   CONTROL     not "it would type into the search box". The network view's
//               search editor reads both raw on every focused frame:
//               keyboard_check(vk_shift) at view.gml:2594 for selection versus
//               caret movement, and keyboard_check(vk_control) at :2647 for the
//               Ctrl+A/C/X/V combos. A modifier bound as the remote key would
//               fire the gesture in the middle of the player's own shortcut -
//               the press that starts Ctrl+A raises our flag, and whichever key
//               they let go of first decides whether the hold arm sees a tap or
//               a hold. A bare modifier is a poor shortcut on its own terms too:
//               it is held down for a large part of any typing session.
//
//               THE SEARCH-BOX ARGUMENT IS VOID, and it is written down so it
//               does not come back. While that box has focus the network view is
//               open, and yads_remote_ready refuses every press in that state
//               (_rt.view != undefined, boot.gml:1607): yads_remote_press clears
//               the pending flag and returns with no scan and no toast
//               (boot.gml:1622, :1627-1630). The search box is protected by the
//               gate, not by this list.
//
//               CONTROL IS ALSO CAUGHT BY THE LIVE TEST BELOW today, because
//               InputId.Walk defaults to "control" (Settings.gml:127) - but only
//               today. A player who rebinds or clears Walk in the settings
//               screen would make it fall through to a SILENT accept:
//               string_length("CONTROL") is 7, so it misses the letter warning,
//               and it is not "F12". The static row is what makes the two
//               modifiers symmetric and unconditional.
//   PAGE_UP     are ours already: yads_install_hotkeys registers both as the
//   PAGE_DOWN   view's pager. mmapi permits two registrations on one vk and
//               fires both (mmapi_hotkeys.gml payload:124-133), so this would not
//               break - it would just mean one key doing two of our jobs, with
//               a conflict Warn in every log.
//   F8 F9 F10   belong to mmapi's debug agent, which claims exactly those three
//               (mmapi_debug.gml:967-969). Same conflict, someone else's tool.
//
// DENY - GAME CONTROL. BINDINGS.inputs_using_keycode(vk) is the LIVE binding
// table, not a copy of the defaults (Input.gml:523-537 walks BINDINGS.bindings,
// the same array raw_status resolves through), so this follows a player who has
// rebound their own controls in the settings screen. It is the check vanilla's
// own rebind popup runs for the same purpose (SettingsMenu.gml:823-824). Out of
// our 55 names the stock table claims W A S D (movement), E (Interact), Q
// (SecondaryInteract and RotateLeft), T (UseToolCharged), G (Throw), M
// (OpenMapMenu), R (RotateRight), C (CastPinnedSpell) and every digit 0-9 (the
// toolbar) - Settings.gml:120-164. CONTROL (Walk, :127) is in that table too,
// but it is denied one clause EARLIER and unconditionally; see the reserved
// block above for why it may not depend on a setting the player can change.
//
// NO BINDING-TYPE FILTER, and that is a derivation rather than an oversight.
// inputs_using_keycode compares raw keycodes across keyboard, mouse and pad
// bindings alike, so in principle a pad constant numerically equal to one of
// ours would produce a false hit. It cannot be one of ours: every code in our
// vocabulary is a member of KEYBOARD_INPUTS (InputUtils.gml:123-200 lists all
// 55), and keycode_to_binding_type classifies by that array before it looks at
// the pad one (:388-400) - so a pad binding carrying one of these numbers would
// be a code the engine itself calls a keyboard code, which is a contradiction
// the engine would trip over long before we did.
//
// ESC IS NOT ON EITHER LIST because it cannot arrive: vk_escape has no name in
// mmapi's vocabulary, so it is not in the array the poll scans. It reaches this
// surface only as InputId.MenuBack, i.e. as cancel.
//
// ACCEPT WITH A WARNING - LETTERS. The poll that fires this hotkey has no
// text-focus test (the whole reason the default is a function key, see the note
// over YADS_REMOTE_KEY), so a letter also types itself into the network view's
// search box. That is a legitimate choice - the view is closed when the key is
// usually pressed, and a player who wants one key should have it - but it has
// to be said at the moment they pick it, not discovered later.
//
// ACCEPT WITH A WARNING - F12. Nothing in the game touches it, but Steam's
// overlay takes it for screenshots by default, so on most installs it will fire
// ours AND take a picture.
//
// EVERYTHING ELSE IS SILENT, AND THAT IS ELEVEN KEYS WITH NO LETTER AMONG
// THEM: F1-F7, F11, INSERT, HOME and DELETE. Every single-character name that
// survives the deny-game clause returns WARN_LETTER, so YADS_REBIND_OK is
// unreachable for a letter - deliberately, per the paragraph above. An earlier
// version of this line put "the letters the binding table has not claimed" in
// the silent set; the code never behaved that way.
//
// F2 AND DELETE ARE IN THAT SET, AND NOT BECAUSE NOTHING READS THEM. Both are
// the vanilla Bugger console toggle - keyboard_check_pressed(vk_f2) ||
// keyboard_check_pressed(vk_delete), Bugger.gml:122 - but BUGGER.update() is
// only ever called under `if DEBUG_TOOLS` (Game.gml:578-579, and Setup's copy
// at Setup.gml:449-450), and BuggerInitialize.gml returns at its second line
// when DEBUG_TOOLS is false. In a retail build the console never runs and that
// reader is dead. The verdict is right; the reason is "compiled out", not
// "unread".
function yads_rebind_verdict(_vk, _name) {
    if (_name == "SHIFT" || _name == "CONTROL"
        || _name == "PAGE_UP" || _name == "PAGE_DOWN"
        || _name == "F8" || _name == "F9" || _name == "F10") {
        return YADS_REBIND_DENY_RESERVED;
    }

    if (BINDINGS.inputs_using_keycode(_vk).count() > 0) {
        return YADS_REBIND_DENY_GAME;
    }

    if (_name == "F12") { return YADS_REBIND_WARN_F12; }

    // A single character in this vocabulary is a digit or a letter. Under STOCK
    // bindings every digit was claimed by the toolbar two clauses ago, so in
    // practice this arm is the letters - but the deny-game test is LIVE, so a
    // player who unbinds a toolbar slot drops that digit through to here. The
    // outcome stays right either way: a digit types into the search box too,
    // which is exactly what picker_set_letter says.
    if (string_length(_name) == 1) { return YADS_REBIND_WARN_LETTER; }

    return YADS_REBIND_OK;
}

// The line the hint shows for a verdict, with the key's name in it.
//
// ONE STATEMENT PER KEY so the loc-closure gate can see each literal, and
// yads_pattern for each so a locale that did not install one still reads
// English rather than the key path (network.gml:661-665).
//
// WIDTHS, measured against fonts/text_widths.toml with the longest name in the
// vocabulary ("PAGE_DOWN") substituted, against the 250px plate and the 240px
// budget the hint line has held since Beta 1.2: deny_game 230, deny_reserved
// 222, set 188, set_letter 230, set_f12 190. Two of those arms cannot actually
// reach nine characters - the letter warning is only ever one character and the
// F12 warning only ever three - so the real widths are 174 and 145. They are
// budgeted at the worst case anyway, because the arm a string belongs to is
// easier to change than a measurement is to remember.
function yads_rebind_message(_verdict, _name) {
    switch (_verdict) {
        case YADS_REBIND_DENY_GAME:
            return format(yads_pattern(YADS_LOCAL_ROOT + "picker_deny_game",
                "{} is a game control - try another"), _name);

        case YADS_REBIND_DENY_RESERVED:
            return format(yads_pattern(YADS_LOCAL_ROOT + "picker_deny_reserved",
                "{} is reserved - try another key"), _name);

        case YADS_REBIND_WARN_LETTER:
            return format(yads_pattern(YADS_LOCAL_ROOT + "picker_set_letter",
                "{} set - it types in the search box"), _name);

        case YADS_REBIND_WARN_F12:
            return format(yads_pattern(YADS_LOCAL_ROOT + "picker_set_f12",
                "{} set - Steam may take it"), _name);
    }

    return format(yads_pattern(YADS_LOCAL_ROOT + "picker_set",
        "{} is now your remote key"), _name);
}

// One frame of listening. Runs from the backplate think, i.e. from inside
// ANCHOR.on_begin_step, which is the ONLY place the cancel can be read.
//
// WHY NOT FROM yads_tick. The tick runs from the head of Game.step_begin,
// ABOVE INPUT.begin_frame() (Game.gml:570-582) - and begin_frame is what clears
// input_overrides and recomputes every raw status for the frame (Input.gml:26-33).
// A take_press up there would be answered from the previous frame's state and
// then overwritten before anything else could see that we took it. Down here we
// are after begin_frame and inside the same walk the rest of the menu runs in.
//
// AND WHY THE BACKPLATE SEES MenuBack AT ALL, with a popup whose canvas think
// calls INPUT.override_input on every InputId while it is up
// (PopupMenu.gml:305-309) and raw_status returning Off for anything overridden
// (Input.gml:274-277). The walk is REVERSE registration order (Anchor.gml:370)
// and the canvas is created before the backplate it parents, so the backplate
// is visited FIRST and the override loop runs after us, every frame. The
// overrides do not carry over: begin_frame clears the whole array at the top of
// the next step. Nothing else claims the press either, because everything that
// would is gated on being unlocked - run_exit_listening (AnchorMenu.gml:172)
// and Close's own glyph think (Node.gml:1833-1839) both test it.
//
// take_press MUTES the press it hands back (Input.gml:270 -> :421-430), and that
// mute is LOAD-BEARING rather than tidy. Cancelling calls unlock() immediately,
// and the canvas think runs AFTER us in the same walk - so on that one frame
// run_exit_listening finds an unlocked canvas and asks for MenuBack itself. It
// gets nothing, because process_binary skips a Pressed flag that carries Muted
// (:421-430), so the picker survives the ESC that ended the capture instead of
// closing on it. (This note used to claim the same mute also covers
// AnchorMenu.think's own exit listener, run after the whole node walk at
// Anchor.gml:653-656. For a POPUP that listener never runs: think gates on
// listen_for_exit_flag (AnchorMenu.gml:162-164), seeded from
// self.data.listen_for_exit (:89), and [popup] sets listen_for_exit = false
// in ui/menus/misc_menus.toml:66. A belt that was never buckled.)
//
// A FOREIGN MENU ON TOP CANCELS THE CAPTURE, AND THAT IS REACHABLE. An earlier
// version of this note called a second popup over the picker unreachable, on
// the grounds that yads_remote_ready refuses our own and the world is paused
// behind this one's MENU flag. Both halves are about menus WE or the PLAYER
// open. The engine opens one on its own account: when the last gamepad drops
// out of gamepads_connected() while active_input_type is Gamepad,
// INPUT.begin_frame creates and spawns GAMEPAD_LOST_POPUP (Input.gml:133-148)
// with no pause test, no menu test and no room test. A controller unplugged or
// a battery dying mid-capture puts one on top of us - and begin_frame runs
// BEFORE ANCHOR.on_begin_step in the same step (Game.gml:573, :582), so the
// first frame this think sees is already covered.
//
// Covered, the capture is HALF DEAF, which is the actual hazard. The new
// popup's canvas think overrides every InputId (PopupMenu.gml:305-309) and its
// nodes registered after ours, so the reverse walk (Anchor.gml:370) runs that
// override loop ahead of us and our take_press(MenuBack) reads Off
// (Input.gml:274-278) - ESC cannot cancel. keyboard_check_pressed is raw and is
// NOT overridden, so the scan below would still COMMIT a rebind through a modal
// the player is reading; and closing that modal drops our capture's lock
// without ending the capture anyway (PopupMenu.gml:36-47, :252-258).
//
// So we take the exit ESC would have taken, on the cheapest correct test there
// is. ANCHOR.open_menus is a List pushed in creation order (Anchor.gml:148) and
// nothing reorders it, so any menu created after our picker sits after it:
// last() != our menu means somebody is on top. last() is O(1) and answers
// undefined on an empty list (List.gml:435-441), and comparing menu structs by
// identity is the engine's own idiom (PopupMenu.gml:41, :255).
//
// UNLOCKING UNDER THE FOREIGN MODAL IS SAFE - checked, not assumed, because
// cancelling means unlock() and a live row list under a live modal is exactly
// what the old note worried about. Four of the five routes from an unlocked
// node of ours to an ACTION end in INPUT.take_press/released: the node loop's
// tap arm calls ANCHOR.take_tap (Anchor.gml:404 -> :1832-1834),
// check_for_click_close ends in the same call (:1570-1577), Close's glyph
// think is take_press (Node.gml:1833-1839), and a DEFERRED tap resolves
// through tap_released -> INPUT.released (Anchor.gml:1827-1829). All four read
// through raw_status, which returns Off for an overridden InputId (:274-278),
// and the foreign popup re-asserts that override every frame it is up -
// through its fade too, because the override block sits OUTSIDE the
// close_requested test (PopupMenu.gml:301-309). The FIFTH route is the pilot
// block (Anchor.gml:311-353), which runs BEFORE the node walk and therefore
// before this frame's override re-assert - it is closed differently: the
// foreign popup's spawn() TOOK the pilot (PopupMenu.gml:260-263), so pad
// navigation drives the modal's nodes, and tap_on_hover defaults false
// (Pilot.gml:10) so a hover alone can never fire. What survives the unlock is
// a hover outline on a row, which is cosmetic. The unlock therefore does not
// need deferring until we are top again.
function yads_picker_capture_think(_picker, _capture, _hint) {
    // Somebody else's menu is on top: end the capture the way ESC does - unlock
    // and keep the picker - because up here we can neither be cancelled nor be
    // allowed to commit. Tested BEFORE the arming skip, so a capture that is
    // covered on its first frame never arms at all.
    var _menu = _picker[$ "menu"];
    var _top = ANCHOR.open_menus.last();
    // A tooltip popup is cosmetic (mute_input(false), TooltipMenu.gml:30) and
    // the engine's own popup_is_open predicate excludes it the same way
    // (Anchor.gml:178, `e[$ "is_tooltip"] != true`). The picker builds no
    // tooltips today, so this clause is unreachable robustness - without it,
    // a future hover hint would read as "covered" and kill every capture.
    if (_menu != undefined && _top != _menu && _top != undefined
        && _top[$ "is_tooltip"] != true) {
        yads_picker_capture_end(_picker);
        return;
    }

    // THE FIRST FRAME IS SKIPPED, and it is not superstition. This think runs
    // in the same ANCHOR pass as the tap that opened the capture: the Rebind
    // button is registered after the backplate, the walk is reverse order, so
    // its tap callback has already run THIS frame by the time we get here.
    // Anything down on the frame the player committed the tap - a key held
    // while they clicked, the keyboard confirm that drove the pilot onto the
    // button - would be captured as their choice. Vanilla's own rebind popup
    // skips exactly one frame for exactly this reason, through the blackboard
    // rather than a struct field (SettingsMenu.gml:820, :898-900).
    if (_capture.armed != true) {
        _capture.armed = true;
        _hint.set_text(_picker.hint_capture);
        return;
    }

    if (INPUT.take_press(InputId.MenuBack)) {
        yads_picker_capture_end(_picker);
        return;
    }

    // Throw-free by construction: every code in here survived a keyboard_check
    // probe at capture entry (yads_rebind_vocab).
    var _vocab = _capture.vocab;
    for (var _i = 0; _i < array_length(_vocab); _i++) {
        var _key = _vocab[_i];
        if (!keyboard_check_pressed(_key.vk)) { continue; }

        var _verdict = yads_rebind_verdict(_key.vk, _key.name);

        // Refused: say why and keep listening. The player is still in capture,
        // so the next key they press is still the one being asked for.
        if (_verdict < YADS_REBIND_OK) {
            _hint.set_text(yads_rebind_message(_verdict, _key.name));
            return;
        }

        yads_picker_rebind_commit(_picker, _key.vk, _verdict, _hint);
        return;
    }
}

// Take the key. Five writes, in an order chosen so that nothing observable is
// half-applied: the live registration first, then the file, then the rescue,
// then the two strings the player reads.
//
// AND THE FIRST WRITE IS CHECKED, because it is the only one that can be
// refused. yads_remote_rebind returns false when its heal path's registration
// was rejected by the engine (boot.gml 5d), which leaves _rt.remote_vk naming a
// key nothing listens for. Continuing past that would write the config file,
// arm the rescue, rebuild the hold hint and flash "X is now your remote key"
// about a dead binding - four lies, one of them persisted to disk. Instead we
// say so on the hint line and STAY IN CAPTURE, which is the same shape a deny
// takes: the player is still being asked for a key, so their next press is
// still the answer, and ESC still cancels. Cancelling outright would be the
// worse choice - it would drop them back to a picker whose hint still names the
// old key with no indication anything was attempted.
//
// The rescue IS armed on that path, and deliberately: a failed rebind is the
// state the F6 hold exists for, and yads_ensure_rescue is idempotent.
//
// Unreachable given the capture proof (5d(3)) - the vk survived keyboard_check
// inside try at vocabulary build and keyboard_check_pressed at selection, so
// register's own probe cannot throw - but every other statement in this
// function is written defensively against a proof it already has, and this one
// was not.
//
// THE NAME IS mmapi's OWN REVERSE LOOKUP, never the engine's keycode_to_string.
// mmapi_hotkey_name_from_vk (mmapi_hotkeys.gml payload:63-94) is written as
// the exact inverse of the resolver we captured through - it reverses digits
// and letters arithmetically and probes the forward map for the named keys - so the string
// it returns is guaranteed to parse back to this same vk on the next boot. The
// engine's own table spells the same keys in lowercase ("f6", InputUtils.gml:590,
// :705), and vk_from_name's single-character arm tests ord against "A".."Z"
// only, so "f6" round-trips to nothing at all.
//
// THE FILE IS WRITTEN THROUGH THE CHECKBOX'S IDIOM (yads_tap_picker_default,
// :4210-4211): mutate the memoized struct and hand the whole thing to
// mmapi_config_write. The setting is a FILE, not view state, and should survive
// an alt-F4 taken one second later.
//
// NO CONFIG-VERSION BUMP AND NO NEW KEY: remote_hotkey has been in the file
// since Beta 1.2 and this only ever writes a value it already accepted.
function yads_picker_rebind_commit(_picker, _vk, _verdict, _hint) {
    var _rt = yads_runtime();

    // Derived ONCE from the vk, and everything below - the file, the hold hint,
    // the confirmation - is fed from this one string rather than read back out
    // of the config struct. Same rule as the hold hint built at open (7c): what
    // the player is shown comes from the live binding, never from the file's
    // opinion of it. mmapi's reverse lookup, never the engine's, for the
    // round-trip reason above.
    var _name = mmapi_hotkey_name_from_vk(_vk);

    // The live half: _rt.remote_vk and our mmapi registry entry, moved
    // together. boot.gml 5d owns the argument for why this is safe and what the
    // caller had to prove to get here.
    if (!yads_remote_rebind(_rt, _vk)) {
        // Refused by the engine. Nothing else is written; the rescue is armed
        // because this is precisely the state it exists for, and the capture
        // stays open so the next key is still the answer.
        _hint.set_text(format(
            yads_pattern(YADS_LOCAL_ROOT + "picker_bind_failed",
                "{} could not be bound - try another"), _name));
        yads_ensure_rescue(_rt);
        return;
    }

    var _cfg = yads_config();
    _cfg.remote_hotkey = _name;
    mmapi_config_write(YADS_MOD, YADS_CONFIG_VERSION, _cfg);

    // The remote key is no longer F6, so the rescue has a job. Idempotent, and
    // it stands itself down if this rebind was BACK to F6.
    yads_ensure_rescue(_rt);

    // Rebuild BOTH steady-state hints rather than leaving one naming the old
    // key. State A carries the key name too since the arming fix (7c), and the
    // picker outlives the rebind - the player is looking at the line that just
    // changed, on the very surface that changed it.
    _picker.hint_set = format(
        yads_pattern(YADS_LOCAL_ROOT + "picker_default",
            "Tick a default, hold {} = this list"),
        _name);
    _picker.hint_hold = format(
        yads_pattern(YADS_LOCAL_ROOT + "picker_hold_hint",
            "Tap {} = default, hold = this list"),
        _name);

    // THE CONFIRMATION GOES ON THE HINT NODE, NOT IN A TOAST, and that is a
    // platform fact rather than a layout preference: create_notification
    // resolves whatever it is handed through local_get (InfoToastsMenu.gml:31),
    // so a toast can only carry a bare key and this sentence has a key NAME in
    // it. A text node is the other case - the pattern is resolved first and
    // format() fills it. Same argument as the hold hint above; see 7c.
    _picker.flash_text = yads_rebind_message(_verdict, _name);
    _picker.flash = YADS_REBIND_FLASH;

    yads_picker_capture_end(_picker);
}

// Fires inside AnchorMenu.close(), before the fade and before any node is
// freed. The picker has nothing to commit, so this only stops the polls: after
// close() the canvas is locked but a locked node still thinks (the node loop
// gates on run_logic && safe_enabled alone, Anchor.gml:374), and a think that
// touched a node on its way to being freed is the one hazard here.
function yads_picker_closing(_menu) {
    if (_menu == undefined) { return; }

    var _picker = _menu[$ "netstor_picker"];
    if (_picker == undefined) { return; }

    _picker.closing = true;
}

// Close the picker NOW, with no fade, so the network view can be built in the
// same frame the row was chosen.
//
// request_hide(0) BEFORE close(), and both halves are load-bearing:
//
//   * request_hide(0) takes the instant branch - alpha 0 and canvas.disable()
//     (AnchorMenu.gml:279-284). A DISABLED canvas fails the node loop's
//     safe_enabled test (Anchor.gml:374), so PopupMenu's think stops running
//     and stops calling INPUT.override_input on every InputId
//     (PopupMenu.gml:305-309). Without it the closing popup would keep every
//     input reading DigitalStatus.Off (Input.gml:276) for the ten frames of its
//     fade ([popup] fade_out_frames = 10, ui/menus/misc_menus.toml), and the
//     view opening underneath would not answer ESC for a sixth of a second.
//   * it also disarms the fade itself. close() calls request_hide() again for a
//     close_transition, and the second call returns at
//     `hide_requests > 1 && !instant` (AnchorMenu.gml:271-273) without starting
//     an ease - so in_transition() is false and the awaiting chain sets
//     free_requested at its first look instead of eleven frames later.
//
// The registration is NOT cleared here. ui.menu_closed is the one place that
// happens, on both the per-frame drain and the anchor-shutdown path, so there
// is exactly one release site and no ordering to get wrong.
function yads_picker_close(_picker) {
    _picker.closing = true;

    var _menu = _picker[$ "menu"];
    if (_menu == undefined) { return; }

    _menu.request_hide(0);
    _menu.close();
}
