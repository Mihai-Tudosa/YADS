// YADS - boot, lifecycle, hooks and the per-frame tick.
//
// WHERE THE EXECUTABLE LINES LIVE
// Every executable top-level statement in this mod is at the BOTTOM of THIS
// file. mmapi attribution is temporal - the registration APIs read
// mmapi_current_mod() at call time (mmapi.gml:20-36) - so a second file running
// its own mmapi_mod_declare between our declare and our registrations would
// steal them. The other two files hold definitions only.
//
// WHY THE FUNCTION PREFIX LOOKS LIKE THAT, AND WHY THE FOLDER MUST BE `yads`
// MOMI derives the legal top-level prefixes from the mod's FOLDER NAME and its
// manifest symbol (GmlModLint.cs:78-83): for each of those two namespaces it
// accepts `<ns>_` and `__<ns>_`, and nothing else. The manifest symbol is the
// mod id with dots and dashes replaced - long, and it moves whenever the
// manifest does; the folder name is short, stable and ours. So the folder is
// named `yads` and every top-level function is `yads_*`. RENAME THE FOLDER AND
// THE MOD STOPS INSTALLING: under --strict-lints every unprefixed function is a
// file-bearing finding, and one file-bearing finding excludes the whole mod,
// content included (GmlLayer.cs:100-113, MANIFEST.md:52-54). The state global is
// global.__yads, the mod's own namespace root, which is exempt from every root
// check the linter makes.
//
// THE SHAPE OF THE THING
// An Access Panel opens ONE vanilla Menu.Storage whose left inventory is a
// synthetic Inventory(54). That inventory is a MIRROR, never a custodian: the
// real items stay in the member chests' own node.inventory at all times, so the
// engine's own save walks them and a crash mid-view loses nothing. Each frame
// the tick diffs the mirror against a shadow snapshot and applies the net
// per-item delta to the member chests - the write-through reconciler.
//
// The three units are split by ROLE rather than sharing one door: the panel
// browses, the heart reports (a read-only status popup), and a block on a live
// network is sealed shut. Deposits land in blocks only. See section 6.
//
// NOTHING THAT CAN THROW MAY RUN between the mirror diff and the shadow
// advance, because a failure there replays a delta that the member chests
// already took. It is why the reconciler handles overflow in a tail. See
// section 8 of network.gml.
//
// PICK PROTECTION is the one thing this mod does OUTSIDE a menu: a unit holding
// items does not come apart in one pickaxe swing. It is a filter at the head of
// pick_node (resource.node_modifier) plus one field on the node -
// `destructable`, which the engine reads in exactly two places, both in
// Pick.gml, and WHICH IS SERIALIZED into the player's save by the grid's
// generic struct walker (Grid.gml:1367-1445 out, :1175-1256 back in; the engine
// relies on that round trip for its own permanent water_blocker nodes,
// Patches.gml:426-452). So the field is written TRANSIENTLY and never left
// changed: the filter sets it for the duration of one pick_node call, the tick
// puts it back on the next frame, and the save handler puts it back once more
// before a byte is written. See section 10 of network.gml for the whole
// mechanism, for the base rule that keeps an engine-forced `false` forced, and
// for why a blocked swing still REACHES us and is therefore countable.

#macro YADS_MOD "yads"
#macro YADS_VERSION "Beta 1.0"

// Bumped whenever the shape of the config struct changes. mmapi_config_read_valid
// returns {} for any other stamp (mmapi.gml:498-512), so an old file degrades to
// "every key takes its default" instead of feeding us a field that no longer means
// what it used to.
//
// DO NOT BUMP IT FOR A PURELY ADDITIVE KEY. The stamp exists to reject a file
// whose keys no longer MEAN what they used to, and adding one changes the
// meaning of nothing. mmapi_config_number already returns its default for an
// absent or wrongly-typed member (mmapi.gml:534-539) and mmapi_config_write
// materialises the new key back to disk on the first read, so an older file
// migrates itself. A needless bump buys nothing and silently resets every
// setting the player had.
#macro YADS_CONFIG_VERSION 1

// The synthetic left inventory. 54 is the largest size with a
// ui/misc/inventory/storage/<n> fiddle entry (misc.toml:302-336) and the only
// one StorageMenu.build can lay out at 9 columns; anything else faults in
// fiddle_get. LOST_AND_FOUND is a shipping Inventory(54) with node == undefined,
// so this exact shape is exercised by vanilla (obj_lost_and_found.gml:32-38).
#macro YADS_VIEW_SIZE 54

// How many of those 54 slots show network contents. The remaining 9 (slots
// 45..53, the last row) stay empty on purpose: they are the deposit landing
// zone. Without them a completely full page would leave the network with no
// reachable free slot, which both blocks deposits and makes the ESC-drop path
// (InventoryMenu.gml:101-119) throw the held stack on the floor because can_add
// said no.
//
// The row is hidden behind the filter plate and its nine squares are lock()ed.
// The slots stay LIVE and empty underneath: lock() only kills mouse hover and pilot
// navigation on the UI node (Anchor.gml:377, Pilot.gml:298-307), while both
// landing paths - InventoryAction.Transfer's pair.add and the ESC-drop's
// source_inventory.add - address the Inventory object and never touch a node
// (InventoryMenu.gml:425-436, :101-118). So the net still catches, it just
// stopped being a row of confusingly clickable holes.
#macro YADS_PAGE_CELLS 45

// Sort modes, cycled by the sort button.
//
// STACK_VALUE sits immediately after VALUE, not at the end, because the two are
// the same question at two scales - "what is one of these worth" and "what is
// this pile worth" - and a cycle button is read by what its NEXT press gives
// you. Nothing persists a sort mode (it is per-view state, unlike value_mode),
// so renumbering COUNT to make room costs nothing anywhere.
#macro YADS_SORT_CATEGORY 0
#macro YADS_SORT_NAME 1
#macro YADS_SORT_VALUE 2
#macro YADS_SORT_STACK_VALUE 3
#macro YADS_SORT_COUNT 4
#macro YADS_SORT_LEN 5

// Category filters on the row-6 plate. Exactly one is active at a time and it
// composes with the search string as an AND, so a filter narrows what search
// searches.
//
// Group 0 is "All", groups 1..14 are the fourteen sort buckets ONE FOR ONE
// (group == bucket + 1), and group 15 is "Museum needs" - which is not a bucket
// at all but a live predicate over the item id, so it is tested separately in
// the projection. 1 + 14 + 1 = 16 is exactly two pages of eight, which is why
// the taxonomy stays exactly as the sort classifier defines it: an even page
// fill is available without splitting a bucket.
#macro YADS_FILTER_ALL 0
#macro YADS_FILTER_MUSEUM 15
#macro YADS_FILTER_LEN 16

// How many PHYSICAL buttons the plate carries, and therefore how many groups a
// page shows. The plate is 218px and the vanilla banner pitch is 24 (22 + 2), so
// eight buttons plus the two 12px pager arrows is 216 of 218 - the widest layout
// that fits. The buttons are built ONCE and never enabled, disabled or removed:
// paging rotates their CONTENT. Pilot.position_is_valid reads only
// safe_unlocked (Pilot.gml:298-306), so a merely-disabled button stays a stop the
// stick lands on with nothing visible in it, and there is no remove_from_pilot to
// undo an add.
//
// INVARIANT: FILTER_SLOTS * FILTER_PAGES == FILTER_LEN. The taxonomy was chosen
// to make that exact rather than ragged - a partial last page would need the
// surplus buttons lock()ed AND disabled on every flip, which is the churn this
// layout exists to avoid.
//
// FILTER_LEN IS THE GUARD RAIL, NOT THE STEERING WHEEL. Bumping it on its own
// changes nothing reachable: the rotation is FILTER_SLOTS wide and FILTER_PAGES
// deep, and a seventeenth group would ALSO need a seventeenth entry in
// filter_icon's ICONS table and a seventeenth arm in filter_label_key. Three
// unlinked places, and the compiler checks none of them against each other. What
// FILTER_LEN earns its keep doing is bounding the rotation - filter_group takes
// the group modulo it - so a taxonomy that outgrows the layout wraps back onto
// real groups instead of pointing surplus buttons at nothing.
#macro YADS_FILTER_SLOTS 8
#macro YADS_FILTER_PAGES 2

// Value badge modes, cycled by the toggle on the bottom shelf and persisted in
// the config file. OFF is the default: the badge is new information the panel
// never had, but it is also 45 numbers over 45 icons, and a player who does not
// want them should not have to turn them off on every save.
//
// STACK before UNIT in the cycle because the stack total is the number the view
// cannot otherwise give you - the tooltip on the very same cell already shows the
// unit value (TooltipMenu.gml:80, :518).
#macro YADS_VALUE_OFF 0
#macro YADS_VALUE_STACK 1
#macro YADS_VALUE_UNIT 2
#macro YADS_VALUE_LEN 3

// The value badges' sprite font, and the ONE place its name is written. It is
// this mod's own: a [netstor_count] table merged into the game's
// fiddle/fonts/sprite_fonts.toml over spr_ui_hud_font_netstor_count, both
// generated by make_art.py. It clones vanilla [item_count] glyph for glyph and
// advance for advance and adds `k` and `m`, which is what makes the abbreviation
// in yads_abbrev_value drawable AT ALL - see the long note
// over build_badges for why "1.2k" in item_count is a wrong number rather than a
// clipped one. A macro because the name is written twice and the two uses MUST
// agree: one draws the string (set_sprite_font) and the other measures it
// (sprite_font_width) for the coin's width gate, and a font that measures a
// string differently from the way it draws it is exactly the failure this whole
// change exists to remove.
#macro YADS_BADGE_FONT "netstor_count"

// Key auto-repeat for the search box's line editor, mirroring the engine's own
// numbers so the field feels native: TextNode.backspace_info.delay_timer_max is
// 20 (Node.gml:1167-1172) and the driver acts every second frame past it
// (Anchor.gml:505-512). At 60fps that is a 333ms delay then 30Hz.
#macro YADS_REPEAT_DELAY 20
#macro YADS_REPEAT_RATE 2

// Status popup: how many per-block rows the FIXED popup can print before the
// heart switches to the scrolling variant. Nine rows of 15px plus the header,
// the total row and the Close button is already ~212 of the 240px minspec canvas
// (Display.gml:4), so this cap is a layout constraint, not a preference. It is
// only a choice of layout: nothing is hidden either way.
#macro YADS_STATUS_ROWS 8

// How long a connectivity cache entry may go unverified. Placement and removal
// both have real signals (section 9), but demolition, blueprints, farm expansion
// and debug tools erase nodes through paths that raise none of them; one forced
// rescan per second is cheaper than enumerating every erase path.
#macro YADS_GLOW_TTL 60

// Pick protection (section 10 of network.gml): how many pickaxe swings
// a unit that still holds items costs before it comes apart, how long a part-way
// count survives without another swing, and how long the warning toast ducks.
//
// FIVE is a deliberate number rather than a round one: it is long enough that
// nobody clears a full crate by accident and short enough that a player who
// means it does not think the mod has broken the pickaxe. The count is not
// shown, because the swing already tells you - vanilla plays its own "that did
// not work" SFX, shakes the unit and rumbles the pad on every blocked swing
// (Pick.gml:451-460), all of it for free.
//
// TEN SECONDS of no swings resets it. Walk away and the crate is whole again;
// the guard is about accidents, and an accident does not span ten seconds.
//
// THE DUCK IS THE SAME TEN SECONDS, and the two numbers are equal on purpose
// rather than by coincidence. The toast fires once per counter, so the window it
// has to cover is exactly the window a counter can live for. A shorter duck
// leaves a player who paces their swings with no feedback for the rest of a
// count that is still running, and then a second toast inside the same attempt.
// Equal durations mean one toast per attempt and a new toast for every genuinely
// new attempt.
// InfoToastsMenu keys the duck on the message string (InfoToastsMenu.gml:21-24),
// so this ducks OUR key and nothing else.
//
// Both durations are spelled as plain frame counts rather than as 60 * n: a
// parenthesised macro body reads as a function call to check_symbols.py's own
// oracle (its CALL regex is `name(`), and the gate is not worth losing to
// arithmetic that fits in a comment. 600 frames = 10s at 60fps. For the same
// reason DUCK is spelled out rather than aliased to TTL: a macro body that is a
// bare identifier is fine, but two names for one number invite one of them to be
// tuned alone. If you change one, change both, and say why here.
#macro YADS_PICK_SWINGS 5
#macro YADS_PICK_TTL 600
#macro YADS_PICK_DUCK 600

// Localization keys, from fiddle/mods/yads/ui.toml. The key is the
// file path minus .toml plus the entry key (MOD_ANATOMY.md:136-166).
#macro YADS_LOCAL_ROOT "mods/yads/ui/"

//
// 1. STATE
//
// One lazy global struct, the house pattern (MOD_ANATOMY.md:33-77). Everything
// the debug agent needs to watch hangs off global.__yads, and nothing in here
// is ever handed to save_json_file - we register no modsave sidecar at all,
// because the network graph is derived from the grid and the items are saved by
// the engine inside the member chests.
//
function yads_runtime() {
    // variable_global_exists does not exist on this runtime (MOD_ANATOMY.md:190).
    if (global[$ "__yads"] == undefined) {
        global.__yads = {
            registered_hooks: undefined, // the boot latch
            booted: undefined,           // first-safe-frame one-shot
            hotkeys_installed: undefined,// hotkeys do NOT de-duplicate; own latch
            recipes_done: undefined,     // per-save recipe backfill one-shot
            ids: undefined,              // memoized ObjectId/ItemId, per save load
            categories: undefined,       // memoized item_id -> sort bucket
            view: undefined,             // the live network view, or undefined
            glow: undefined,             // connectivity cache for the unit glow
            picks: undefined,            // per-node pickaxe swing counts (section 10)
            config: undefined,           // lazily-read player settings (section 1b)
        };
    }
    return global.__yads;
}

//
// 1b. SETTINGS
//
// One persisted preference, and the API's canonical kit for it: read the file
// through mmapi_config_read_valid (which hands back {} unless the version stamp
// matches), pull each key with its typed accessor and a default, then write the
// normalised struct straight back so the file on disk always documents every
// option at its current shape.
//
// LAZY, NEVER AT BOOT. mmapi's config path does real file IO and the boot frame
// is explicitly not a safe place for it (MOD_ANATOMY.md:107); the tick warms this
// on its first-safe-frame branch, and everything else finds the memo already
// there. The read is [$ ]-guarded for the same reason the glow cache is: a global
// struct left behind by an older boot arrives without the field.
//
function yads_config() {
    var _rt = yads_runtime();

    var _cfg = _rt[$ "config"];
    if (_cfg != undefined) { return _cfg; }

    var _source = mmapi_config_read_valid(YADS_MOD,
        YADS_CONFIG_VERSION);

    // auto_search: focus the search box the moment the network view opens, the
    // way AE2's terminal does. Default ON because typing-first is the whole point
    // of a searchable network, and the cost - one ESC to blur before ESC closes
    // the menu, and no keyboard InputId while the box holds focus
    // (Anchor.gml:194-202) - is exactly what the toggle beside the box exists to
    // hand back. mmapi_config_bool ignores anything that is not a real bool, so a
    // hand-edited file cannot smuggle a string in here.
    //
    // value_mode: 0 off, 1 whole-stack tesserae, 2 per-unit tesserae (the
    // YADS_VALUE_* macros). A preference, not a lens - it says
    // how you like to read a storage grid, so it belongs beside auto_search in
    // the file rather than resetting every time a panel opens. mmapi_config_number
    // range-guards to [0, VALUE_LEN-1] and falls back to the default for anything
    // else, so a hand-edited 7 cannot reach the cycle arithmetic.
    _cfg = {
        auto_search: mmapi_config_bool(_source, "auto_search", true),
        value_mode: mmapi_config_number(_source, "value_mode",
            YADS_VALUE_OFF, 0, YADS_VALUE_LEN - 1),
    };

    mmapi_config_write(YADS_MOD,
        YADS_CONFIG_VERSION, _cfg);

    _rt.config = _cfg;
    return _cfg;
}

//
// 2. REGISTRATION (latched)
//
// Boot can run more than once and none of mmapi_register / hotkey / modsave
// registration de-duplicates (MOD_ANATOMY.md:89-91), so everything sits behind
// one flag.
//
function yads_register_callbacks() {
    var _rt = yads_runtime();
    if (_rt.registered_hooks != undefined) { return; }
    _rt.registered_hooks = true;

    // Claim-scoped override: we must return undefined for every node we do not
    // own, and the ownership test must be the first thing we do - this fires for
    // EVERY grid-object interaction in the game (HOOKS.md:206-218).
    mmapi_override("object.interact", yads_object_interact);

    // Fires after the menu is already freed and already off open_menus
    // (ui.menu_closed.md:11). Used only to release what we attached; the
    // commit-back happens earlier, in our on_close replacement.
    mmapi_on("ui.menu_closed", yads_menu_closed);

    // Fires at the top of save_game(), before a single byte is written
    // (seams.toml save_game_saving anchors on `Game.last_serde_path = save_path;`).
    mmapi_on("save.game_saving", yads_game_saving);

    // Start of a load: drop every per-save memo. ItemId/ObjectId are minted from
    // the merged fiddle tables and renumber whenever the installed content set
    // changes, so a cached number is only ever valid for the session that made it.
    mmapi_on("save.game_loaded", yads_game_loaded);

    // --- the three glow hooks (section 9) -------------------------------------
    //
    // A guard, but never a veto: this is the only signal in the whole API that a
    // unit may be about to join a network, and it fires BEFORE the node exists
    // (furniture.place_guard.md), so all it can do is mark the cache dirty for
    // the next tick. Guards fail open and only the Boolean false vetoes, so the
    // handler returns undefined on every path.
    mmapi_guard("furniture.place_guard", yads_place_guard);

    // The documented moment to re-apply per-instance visual state to renderers
    // that culling just reactivated, before the frame draws
    // (camera.culls_processed.md:11-13). Hot: fires every frame culling runs.
    mmapi_on("camera.culls_processed", yads_culls_processed);

    // Every renderer in the world is destroyed and rebuilt across a room change,
    // so every cached instance id and every overlay's visible flag is stale.
    // Edge trigger only - nothing here reads or stores ctx (game.room_changed.md).
    mmapi_on("game.room_changed", yads_room_changed);

    // Pick protection. A FILTER, and the only registration in this
    // list whose handler must return undefined on EVERY path - the value being
    // filtered is the tool modifier of every pickaxe and axe swing in the game
    // (seams.toml pick_node_modifier + chop_node_modifier), and this mod has no
    // business changing it. What it does instead is a side effect on the node,
    // which is legal because the seam sits at the head of pick_node, before its
    // own scan and before the one field the removal reads. Section 10 of
    // network.gml carries the whole argument; the ownership test in
    // the handler is first, for the same reason object.interact's is.
    mmapi_filter("resource.node_modifier", yads_node_modifier);

    mmapi_register(yads_tick);
}

//
// 3. THE TICK
//
// Runs from the head of Game.step_begin, before TICK++ and before
// ANCHOR.on_begin_step (Game.gml:570-582), which is what makes it the single
// writer of the view inventory: every node callback that wants to change the
// page, the sort or the focus only records a REQUEST, and this function applies
// it one frame later. It also means we observe the state the player's input
// produced during the previous frame's ANCHOR pass - the one-action pending
// window the reconciler is designed around.
//
// Cost when nothing is open: a handful of struct reads, the connectivity
// cache's one List.count() poll and a decrement, and a return.
//
function yads_tick() {
    var _rt = yads_runtime();

    // THE PICK COUNTERS' RESTORE, decay and liveness sweep (section 10), and it is
    // the FIRST statement in the tick on purpose. Costs one [$ ] read, one
    // array_length and a return whenever nobody has swung a pickaxe at a full unit
    // in the last ten seconds - which is almost always.
    //
    // Position matters here in a way the glow's does not, and for two separate
    // reasons:
    //
    //   * this runs at the head of Game.step_begin, i.e. before obj_ari takes its
    //     step and therefore before every pick_node call of this frame, which is
    //     what lets the poll undo last frame's suppression without any risk of
    //     undoing this frame's. Do not move it below anything that can swing a
    //     pickaxe.
    //   * mmapi catches a throwing installer per installer and skips the rest of
    //     that installer's body (mmapi.gml:71-84), so anything above this line that
    //     throws would strand a suppression on a node for the whole session -
    //     ensure_recipes most of all, since it only latches recipes_done on its
    //     last line and would therefore throw again every frame. game_loaded states
    //     the doctrine as "every suppression we write is undone by us" with no
    //     exceptions at all; putting nothing above the restore is what makes that
    //     true rather than conditional on every function below it never failing.
    yads_pick_poll(_rt);

    if (_rt.booted != true) {
        _rt.booted = true;
        // File IO and the hotkey registration probe are only safe from here on,
        // never at boot (MOD_ANATOMY.md:107, mmapi_hotkeys.gml:427-438).
        yads_install_hotkeys(_rt);

        // Warm the config here rather than leaving the first read to a widget:
        // the toggle's selected getter and the tooltip poll both call it every
        // frame, and neither is a place to discover a file on disk.
        yads_config();
    }

    if (_rt.recipes_done != true) {
        yads_ensure_recipes(_rt);
    }

    // Connectivity cache upkeep: one List.count() read plus a decrement in the
    // steady state, a ~15k-op rescan only when something actually moved.
    yads_glow_poll(_rt);

    // ...and then assert the cached state onto the overlays, EVERY FRAME. The
    // two glow channels differ in what they write:
    //
    //   * the connected/offline signal lives in sprite_index, which nothing
    //     else in the engine touches on that instance, so one write per state
    //     change holds indefinitely.
    //   * the fill signal lives in image_blend, and the highlight path writes
    //     image_blend on the overlay every frame the player is looking at the
    //     unit (obj_node_renderer.gml:83-87), after which the overlay's own draw
    //     resets it to c_white (obj_node_renderer_top.gml:16-18). A tint is
    //     therefore erased by every highlight and has to be re-asserted.
    //
    // camera.culls_processed cannot carry that job, and this is the finding that
    // forced the change: Camera.process_culls returns immediately unless
    // process_culls_this_room, which is LOCATIONS[id].outdoor (Camera.gml:216-237,
    // :302-305). locations.toml sets outdoor = false in [default] and overrides it
    // for ten outdoor locations only - so the hook fires on the Farm and NOWHERE
    // else these units can be placed. Indoors (player_home*, both greenhouses,
    // every barn and coop, the mini-museum) the tint would sit white until the
    // next rescan or the 60-frame TTL: up to a second of wrong colour after every
    // glance. The culls_processed registration stays exactly as it was, because
    // outdoors it is still the one moment a scrolled-in renderer is alive and has
    // not yet drawn.
    //
    // Cost: array_length plus ~8 ops per cached unit, on a count bounded by how
    // many crates a player bothered to place.
    yads_glow_apply();

    // One-time repair of a `destructable = false` that a pre-release build of
    // this mod may have left in the save being played (section 10). It sits
    // DOWN HERE, not
    // beside the poll above, for the one reason that matters: the poll must precede
    // everything that can throw, and the repair is the newer, longer and therefore
    // likelier of the two to do so. Being late costs nothing - it re-arms every
    // frame until the world is up and then latches - while being early would put a
    // fresh function in front of the invariant the poll's position exists to make
    // unconditional.
    yads_pick_repair(_rt);

    var _view = _rt.view;
    if (_view == undefined) { return; }

    // Defensive: a view whose menu vanished without either close path firing.
    if (_view.menu == undefined) {
        yads_teardown(_view);
        return;
    }

    // 3a. Write-through. Diff the mirror against the shadow and push the net
    //     deltas into the member chests. This is the only place items move.
    yads_reconcile(_view);

    // 3b. Once close() has run the canvas is locked (AnchorMenu.gml:207 ->
    //     Node.set_unlocked(false) recurses to every child), so the player can no
    //     longer act. Keep reconciling - it is cheap and idempotent - but stop
    //     touching nodes that are on their way to being freed.
    if (_view.closing == true) { return; }

    // 3c. Apply UI requests recorded by node callbacks last frame.
    if (_view.page_request != undefined) {
        if (_view.page_request != _view.page) {
            _view.page = _view.page_request;
            _view.project_dirty = true;
        }
        _view.page_request = undefined;
    }

    if (_view.sort_request != undefined) {
        if (_view.sort_request != _view.sort_mode) {
            _view.sort_mode = _view.sort_request;
            _view.page = 0;
            _view.project_dirty = true;
            yads_apply_sort_label(_view);
        }
        _view.sort_request = undefined;
    }

    // The filter buttons record a group the same way every other widget records
    // its request. Applied here, before the projection, so filter+search+page
    // are always resolved together and the page count can never describe a
    // different row set than the one on screen.
    if (_view.filter_request != undefined) {
        if (_view.filter_request != _view.filter) {
            _view.filter = _view.filter_request;
            _view.page = 0;
            _view.project_dirty = true;

            // Bring the lit button on screen. Only eight of the sixteen
            // groups are visible at a time, so "which group is active"
            // is reported by exactly one pixel of UI - the selected sprite on
            // one button - and that button can be on the other page. Applying a
            // filter therefore also decides which page is shown, in both
            // directions: setting one shows its page, clearing back to All shows
            // page 0 where the lit All button is. The only way to get a filter
            // whose button is off screen is now to page away on purpose, and the
            // two arrows light up to say so (filter_prev/next selected getters).
            //
            // Recorded as a REQUEST rather than written here, so cat_page keeps
            // exactly one writer and refresh_filter_bar exactly one call site -
            // the block immediately below. An explicit arrow tap in the same
            // frame is impossible (one tap per frame, and they are different
            // nodes), but if it ever happened the player's tap lands last and
            // wins, which is the right precedence.
            _view.cat_page_request =
                _view.filter div YADS_FILTER_SLOTS;
        }
        _view.filter_request = undefined;
    }

    // The category bar's own page, recorded by the two scroll arrows. It changes
    // WHICH sixteen groups the eight buttons currently offer and nothing else:
    // the applied filter, the index and the projection are all untouched, so this
    // deliberately does not dirty anything. Applied here anyway, with every other
    // request, because a widget callback that writes view state directly is a
    // second writer and this file has exactly one.
    if (_view.cat_page_request != undefined) {
        if (_view.cat_page_request != _view.cat_page) {
            _view.cat_page = _view.cat_page_request;
            yads_refresh_filter_bar(_view);
        }
        _view.cat_page_request = undefined;
    }

    // 3d. Search box. Polled rather than event-driven: the TextNode is fed by
    //     ANCHOR.on_begin_step (Anchor.gml:459-522) and only exposes its value,
    //     and polling keeps every view mutation inside this one function.
    if (_view.search_node != undefined) {
        var _typed = string_lower(string_trim(_view.search_node.get_text()));
        if (_typed != _view.query) {
            _view.query = _typed;
            _view.page = 0;
            _view.project_dirty = true;
        }
    }

    // 3e. At most one projection per frame.
    if (_view.project_dirty == true) {
        yads_project(_view);
    }
}

//
// 4. RECIPE BACKFILL
//
// recipe_is_default only fires on a NEW GAME (NewGame.gml:72-78) or during a
// save-version migration (Patches.gml:1483-1501), and installing a mod does not
// move GAME_VERSION - so every existing save would never see the three recipes.
// Unlock them by hand, once per loaded save, from the first frame the player
// exists. alert=false suppresses the "new recipe!" popup.
//
function yads_ensure_recipes(_rt) {
    // ARI is constructed with the game, but obj_ari does not exist on the title
    // screen or during some transitions (API_REFERENCE.md:284-288).
    if (!instance_exists(obj_ari)) { return; }

    static ITEM_KEYS = ["netstor_heart", "netstor_block", "netstor_panel"];

    for (var _i = 0; _i < array_length(ITEM_KEYS); _i++) {
        var _item_id = try_string_to_item_id(ITEM_KEYS[_i]);
        if (_item_id == undefined) { continue; }              // content not installed
        if (ari_has_recipe_anywhere(_item_id)) { continue; }  // Ari.gml:1255
        ARI.unlock_recipe(_item_id, false);
    }

    _rt.recipes_done = true;
}

//
// 5. HOTKEYS
//
// PAGE_UP / PAGE_DOWN as an accessibility extra for the paging arrows. Bound to
// function-style keys on purpose: the poll reads raw keyboard state and fires
// even while a text field has focus (mmapi_hotkeys.gml:604-753), so a letter
// bind would type into our own search box. F8/F9/F10 belong to the debug agent
// and must never be claimed (DEBUG.md:26-30).
//
function yads_install_hotkeys(_rt) {
    if (_rt.hotkeys_installed == true) { return; }
    _rt.hotkeys_installed = true;

    var _prev = mmapi_hotkey_vk_from_name("PAGE_UP");
    if (_prev != undefined) {
        mmapi_hotkey_register(_prev, yads_hotkey_prev_page);
    }

    var _next = mmapi_hotkey_vk_from_name("PAGE_DOWN");
    if (_next != undefined) {
        mmapi_hotkey_register(_next, yads_hotkey_next_page);
    }
}

// Hotkey callbacks take no arguments (mmapi_hotkeys.gml:650).
function yads_hotkey_prev_page() {
    var _view = yads_runtime().view;
    if (_view == undefined || _view.closing == true) { return; }
    yads_request_page(_view, _view.page - 1);
}

function yads_hotkey_next_page() {
    var _view = yads_runtime().view;
    if (_view == undefined || _view.closing == true) { return; }
    yads_request_page(_view, _view.page + 1);
}

//
// 6. INTERACTION
//
// object.interact is an OVERRIDE with claim-scoped contention: ctx IS the grid
// node, a non-undefined return replaces the engine's whole interact() for it,
// and undefined defers (seams.toml:125-129).
//
// We claim ALL THREE units, and on a LIVE network (one that contains a heart)
// each of them does something different. Giving all three the same door - the
// network view - leaves nothing to teach the player what a heart or a panel is
// FOR, so each unit has exactly one job:
//
//   panel  - the only browsing surface. Opens the aggregated network view.
//   heart  - the brain. Opens a read-only status popup: how many blocks are
//            connected, how full each one is, how full the network is. It never
//            opens the view and never shows its own 54 slots as a chest.
//   block  - sealed, BUT ONLY WHEN THE NETWORK HAS AN ACCESS PANEL. A block's
//            own slots are an arbitrary slice of the aggregate; letting the
//            player rummage in one invited exactly the "where did my deposit
//            really go" confusion the network is supposed to remove. Sealing it
//            is only legitimate while the aggregate is reachable somewhere else.
//
// The heart keeps its real 54-slot Inventory - that is a data-model fact we must
// not touch. Grid.gml:1137-1154 force-resizes every loaded chest inventory to
// the CURRENT prototype size and Inventory.resize (Inventory.gml:49-57) pops
// trailing slots without draining them, so shrinking the heart to match its new
// "brain" role would silently destroy whatever the live save has above the new
// size. "Brain" is an interaction rule, enforced here and in the deposit
// targeting; it is not a container change.
//
// THE ANTI-STRAND RULE, which is a safety property and not a convenience:
// NO STATE OF THE WORLD MAY LEAVE A UNIT'S CONTENTS BEHIND A DEAD INTERACTION.
// Blocks and panels physically hold items; every door this ladder closes has to
// leave another one open. It runs in BOTH directions:
//
//   * heartless chain -> defer to the engine, which opens the unit's plain
//     per-chest UI. Smashing the heart must not lock the crates.
//   * hearted chain with NO PANEL -> the BLOCKS defer, for the identical reason.
//     Sealing a block on any live network without first asking whether a
//     browsing surface exists strands heart + full blocks + no panel - which is
//     the ordinary first-craft order, since the Block costs wood and copper
//     while the Panel needs furnace-gated glass. The heart only reports and the
//     block is shut, so there is nothing left to press. The scan therefore
//     carries a panel count and the seal is gated on it.
//
// The HEART is the exception on that second line: it toasts and swallows the
// press rather than deferring (see the branch below), so
// its own 54 slots are the one place the rule is not fully honoured. Bounded and
// recoverable, never lost - the toast names the fix, the recipe is force-unlocked
// by the backfill, and the moment a panel exists the heart is a member and its
// contents appear in the aggregate.
//
// A network with a panel is therefore the only one in which a block says no, and
// in that network the toast's advice is true. Deferring is also still the
// graceful-degradation story if this GML layer is ever skipped entirely.
//
// Not claimable at all: the vanilla Throw input. Furniture.gml:1236-1262
// registers InputId.Throw on every interaction_chest node unconditionally, and
// no seam in the API covers it, so a player standing next to a heart or a panel
// can still hand-feed it directly. Known, accepted, documented in the README -
// it cannot corrupt anything (can_add still gates it) and the next index rebuild
// simply reports the items where they landed.
//
function yads_object_interact(_ctx) {
    var _ids = yads_ids();

    // Cheapest possible test first: this hook is hot.
    var _object_id = _ctx[$ "object_id"];
    if (_object_id == undefined) { return undefined; }

    var _is_heart = (_ids.heart != undefined && _object_id == _ids.heart);
    var _is_block = (_ids.block != undefined && _object_id == _ids.block);
    var _is_panel = (_ids.panel != undefined && _object_id == _ids.panel);
    if (!(_is_heart || _is_block || _is_panel)) { return undefined; }

    // No player instance means no ARI.inventory to pair against and no safe
    // ESC-drop target; hand it back to the engine rather than half-open.
    if (!instance_exists(obj_ari)) { return undefined; }

    var _rt = yads_runtime();

    // ANCHOR.get_menu asserts when two Storage menus are open at once
    // (Anchor.gml:160-167). Swallow the interaction instead of stacking.
    if (_rt.view != undefined) { return true; }

    var _scan = yads_scan(_ctx);

    if (_scan.hearts <= 0) {
        // Heartless chain: defer to the vanilla per-chest UI so the unit's own
        // contents stay reachable. The toast only makes sense on the panel -
        // its whole purpose is network access - whereas a lone block being a
        // plain chest is just what a chest is before a heart arrives.
        //
        // Structurally unreachable when the interacted node IS the heart: the
        // scan counts the start node on its very first frontier pop, so a scan
        // begun at a heart always reports hearts >= 1.
        if (_is_panel) {
            create_notification(YADS_LOCAL_ROOT + "no_heart", 60 * 3);
        }
        return undefined;
    }

    // The brain reports; it does not open - UNLESS the network has no panel, in
    // which case the whole role model stands down and the heart is a chest
    // again, exactly like the blocks below. The anti-strand rule runs in both
    // directions and covers both unit types: a panel-less network must leave
    // every unit's contents reachable the vanilla way (an old save's heart can
    // hold a full 54 slots, and the Throw side-channel can feed a fresh one).
    // The toast carries the "craft an Access Panel" pointer that the status
    // popup would otherwise have shown.
    if (_is_heart) {
        if (_scan.panels <= 0) {
            // Message ONLY. A brief chest-UI fallback here reads as a bug in
            // play; the anti-strand duty on a panel-less network is carried by
            // the BLOCKS below, which open as plain chests until a panel exists.
            //
            // WHAT THIS STRANDS, stated in full: everything sitting in THIS
            // heart's own 54 slots waits for a panel. Two feeds put it there.
            // Items Thrown directly into a panel-less heart is the live one -
            // Furniture.gml registers Throw on every interaction_chest node
            // unconditionally and no seam covers it. The other is any save made
            // before deposits became blocks-only, which can carry a heart
            // holding a full 54 slots of real items; see the blocks-only note
            // over yads_deposit.
            //
            // Recoverable, never lost, which is why this stays a toast: the
            // string says exactly what to do, the recipe is force-unlocked by
            // the backfill below, and one Access Panel turns the heart back into
            // a member whose contents show up in the aggregate. Documented in
            // the README.
            create_notification(YADS_LOCAL_ROOT + "status_no_panel", 60 * 3);
            return true;
        }
        obj_ari.set_idle_simple();
        yads_open_status(_scan);
        return true;
    }

    // Sealed - but only into a network the player can actually browse. With no
    // panel anywhere on the chain the heart reports and every block is shut, and
    // that is a no-browsing-surface state: the anti-strand rule forbids it, so
    // the block falls through to the vanilla chest UI instead and the popup's
    // "craft an Access Panel" pointer becomes advice rather than a dead end.
    //
    // Swallowing the press costs the engine nothing: interact()'s
    // used_object_today write (Interact.gml:95) sits after the seam and is read
    // for no interaction_chest object anywhere in the corpus, and the value
    // interact() returns is discarded by every caller (AriFsm.gml:581-584).
    if (_is_block) {
        if (_scan.panels <= 0) { return undefined; }
        create_notification(YADS_LOCAL_ROOT + "block_sealed", 60 * 3);
        return true;
    }

    if (array_length(_scan.members) <= 0) { return undefined; }

    obj_ari.set_idle_simple();
    yads_open_view(_ctx, _scan);
    return true;
}

//
// 7. CLOSE / SAVE / LOAD
//
// ui.menu_closed carries { menu, kind } and kind is Menu.Storage for every
// vanilla chest too, so the only usable discriminator is a field we stamped on
// the instance ourselves - read with [$ ], because a bare read of an absent
// struct member faults.
//
function yads_menu_closed(_ctx) {
    var _rt = yads_runtime();
    if (_rt.view == undefined) { return; }

    var _menu = _ctx[$ "menu"];
    if (_menu == undefined) { return; }
    if (_menu[$ "netstor_view"] == undefined) { return; }

    // Structs compare by reference on this runtime (mmapi_local.gml:22-23).
    if (_menu[$ "netstor_view"] != _rt.view) { return; }

    yads_teardown(_rt.view);
}

// The save WILL happen after this returns, and it starts with the grids, so
// anything still in flight has to land now or it never existed.
function yads_game_saving(_ctx) {
    var _rt = yads_runtime();

    // 0. Put every pick-protected node back to the value the engine gave it,
    //    BEFORE anything else and outside the view guard, because this one is
    //    not about the view at all. node.destructable is walked into the save by
    //    the grid serializer like any other node field (section 10 of
    //    network.gml carries the proof), so a suppression left on a
    //    node while the grids serialize is a crate welded shut in the player's
    //    save file - permanently, and past uninstallation of this mod.
    //
    //    The tick's poll has already restored everything it could see, so this
    //    is normally a walk over an empty array. What it exists for is the one
    //    frame where a save is raised after the filter has run and before the
    //    next poll. Cheap enough to run unconditionally, and the alternative is a
    //    class of corruption with no way back.
    //
    //    It also leaves the state re-derivable: the entries keep their bases and
    //    their counts, only `held` is cleared, so the next poll finds nothing to
    //    do and the next swing continues the sequence where it left off.
    yads_pick_flush(_rt);

    var _view = _rt.view;
    if (_view == undefined) { return; }

    // 1. Apply the last frame's action to the member chests.
    yads_reconcile(_view);

    // 2. The cursor "hand" holds real items that were already taken out of the
    //    chests. They live in no serialized inventory, so give them back to the
    //    player exactly the way InventoryMenu's own free callback does
    //    (InventoryMenu.gml:212-221).
    yads_flush_hand(_view);

    // 3. Rebuild the mirror so the shadow matches what the slots now hold; a
    //    stale shadow after the save would replay the flushed hand as a delta.
    if (_view.closing != true) {
        yads_project(_view);
    } else {
        _view.shadow = yads_view_totals(_view);
    }
}

function yads_game_loaded(_ctx) {
    var _rt = yads_runtime();
    _rt.ids = undefined;            // never cache a minted enum value across a load
    _rt.categories = undefined;     // keyed by item_id, so it dies with the ids
    _rt.recipes_done = undefined;   // backfill again for the save being loaded
    _rt.view = undefined;           // no menu survives a load

    // Every node struct a pick counter names belongs to the save being replaced.
    // The poll's liveness test would drop them within a frame anyway (the old
    // grids' renderers are destroyed), but a memo keyed on dead nodes has no
    // business outliving the save that made them, and this is the function whose
    // whole job is saying so.
    //
    // Restore before dropping, and not because these particular nodes matter -
    // they are about to be discarded with their grids. It is so that "every
    // suppression we write is undone by us" has no exceptions at all, which is a
    // far easier property to keep true than "every suppression we write is
    // undone by us, except on the paths where the node was going to die anyway".
    yads_pick_flush(_rt);
    _rt.picks = undefined;

    // Re-arm the one-time contamination repair for the save being loaded. It cannot
    // run here - this hook fires at the start of the load, before GRIDS exists and
    // with STORAGE_NODES already cleared (Game.gml:28) - so it is armed here and
    // performed by the tick on the first frame the world is up, the same division
    // of labour recipes_done uses above.
    _rt.picks_repaired = undefined;

    // Every node, renderer and overlay instance in the cache belongs to the save
    // that is being replaced. Drop the lot; the next tick rebuilds it.
    yads_glow_reset(_rt);
}

//
// 8. GLOW HOOK HANDLERS
//
// The three handlers are here rather than with the cache itself because this is
// the file that registers them, and because two of the three are one line: the
// interesting code all lives in section 9 of network.gml.
//

// A guard that never guards. It fires at the head of write_furniture_to_location
// for EVERY furniture placement in the game, including several hundred times
// during room setup, so the body must be one struct write and nothing else - and
// it must return undefined on every path, because the Boolean false would veto a
// placement that has nothing to do with us. It also fires BEFORE the node is
// written, which is why it only marks dirty: the rescan has to see the node, so
// it happens on the next tick.
function yads_place_guard(_ctx) {
    yads_glow_invalidate();
    return undefined;
}

// Fires after instance_activate_region has reactivated the on-screen renderers
// and before the frame draws - the one moment a scrolled-in renderer is alive
// but has not yet drawn. Re-asserting the overlay flags here is what keeps a
// unit from popping into view wearing last frame's glow state.
function yads_culls_processed(_ctx) {
    yads_glow_apply();
}

// Room change destroys and rebuilds every renderer in the world (Grid.gml:
// 208-212 only builds them for the current location), so every cached instance
// id is dead and every new overlay is born visible. Full reset, not a dirty bit.
function yads_room_changed(_ctx) {
    yads_glow_reset(yads_runtime());
}

//
// 9. BOOT WIRING - memory only, and the last two lines in the mod.
//
mmapi_mod_declare(YADS_MOD, YADS_VERSION);
yads_register_callbacks();
