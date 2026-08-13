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
#macro YADS_VERSION "Beta 1.2"

// The Remote Access Panel's default hotkey, and the fallback the config read
// falls back TO. A function key on purpose, for the same reason PAGE_UP and
// PAGE_DOWN are (see section 5): the mmapi poll reads raw keyboard state with
// no pause test, no menu test and no text-focus test (mmapi_hotkeys.gml
// payload:220-260 has none of the three - section 5 explains the payload/source
// line-number convention), so a letter bind would fire out of our own search box.
// F8/F9/F10 belong to the debug agent (__mmapi_debug_install_hotkeys claims
// exactly those) and must never be claimed here.
#macro YADS_REMOTE_KEY "F6"

// How many consecutive frames the remote key has to stay down before the press
// means "show me the picker" instead of "open my usual network". 24 frames is
// 400ms at 60fps: past the ~200ms a deliberate tap takes and well short of the
// ~500ms at which a held key starts to feel unresponsive.
//
// IT IS A FRAME COUNT AND THE COUNT IS OURS, not the engine's. The mmapi poll
// only ever hands us a press EDGE (mmapi_hotkeys.gml payload:240), so the
// frames in
// between are counted by yads_remote_hold_poll reading keyboard_check on the
// keycode the watch itself carries - see section 5c for the whole derivation,
// including why that read cannot throw, and 5d for why the watch carries a
// keycode of its own rather than re-reading _rt.remote_vk.
//
// The threshold is only ever REACHED on a press that armed the watch, and the
// arming predicate (also section 5c) is what decides which presses wait for it.
// The one state that does not wait is the one whose TAP already opens the
// picker on the press frame - several networks and no default - so a hold shows
// the list in every state that has a network bound, waiting or not.
#macro YADS_REMOTE_HOLD 24

// WHICH CALLBACK RAISED remote_pending. Two hotkeys can reach the tick now: the
// player's own remote key, and the permanent vk_f6 RESCUE that section 5d
// installs whenever the remote key is something else. They resolve differently
// - the primary runs the whole tap/hold ladder, the rescue is hold-only - so
// the flag has to say which one fired rather than merely that one did.
//
// PRIMARY WINS A SHARED FRAME. The rescue callback refuses to overwrite a
// primary that already claimed this frame, which is only reachable if a player
// rebinds TO F6 (both entries then answer one key) and is the frame in which
// the ladder, not the rescue, is what they asked for.
//
// FREE TO RENUMBER, unlike YADS_SORT_* and YADS_VALUE_*: this never reaches
// mmapi_config_write, so no save file and no config file holds one of these
// integers. Same for the YADS_REBIND_* verdicts below.
#macro YADS_PRESS_PRIMARY 1
#macro YADS_PRESS_RESCUE 2

// The rebind capture's verdict on a pressed key, ORDERED so that "may we take
// it" is one compare: everything below YADS_REBIND_OK is a refusal, everything
// from it up is an acceptance that differs only in what the hint says
// afterwards. Section 7f of view.gml carries the policy and its evidence.
#macro YADS_REBIND_DENY_GAME 0
#macro YADS_REBIND_DENY_RESERVED 1
#macro YADS_REBIND_OK 2
#macro YADS_REBIND_WARN_LETTER 3
#macro YADS_REBIND_WARN_F12 4

// How long the picker's hint line holds the "X is now your remote key" answer
// before falling back to its two steady-state strings. 120 frames is 2s at
// 60fps - long enough to read a short sentence, short enough that the hint is
// back to describing the checkbox column before the player looks for it. It is
// deliberately shorter than the mod's toasts (60 * 3): a toast has to survive
// being glanced at late, a line the player is already looking at does not.
#macro YADS_REBIND_FLASH 120

// How many networks the picker's fixed layout can print. Eight rows of 18px
// under a 24px header, plus the hint line and the Close button, is ~221 of the
// 240px minspec canvas (Display.gml:4) - so this is a layout constraint, the
// same one YADS_STATUS_ROWS answers to, and not a preference.
//
// UNLIKE THE STATUS POPUP THERE IS NO SCROLLING VARIANT, and that is a decision
// rather than an omission. A ninth bound network needs a ninth Remote Access
// Panel - 5 Ruby, 5 Sapphire, 5 Copper Ingot, 5 Iron Ingot and an Access Panel
// each - and the rows here are TAPPABLE and pilot-navigable, so a scroller
// would be a second interactive surface to audit for one-hover/one-tap
// correctness (Scroller.subscribe_to_pilot, Scroller.gml:301-321, is the path
// if it is ever wanted) for a case no real save reaches. Rows past the cap are
// dropped from the LIST only: the scan sorts hearts in the player's current
// location first, so the ones you are standing next to always make it, every
// network is still reachable from its own Access Panel, and a default already
// set on an unlisted network still opens on a tap.
#macro YADS_PICKER_ROWS 8

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
// you.
//
// THESE NUMBERS ARE NOW A SAVE FORMAT, so the order is no longer free. The
// config file stores sort_mode as the raw INTEGER (yads_config below,
// yads_tap_sort in view.gml), and mmapi_config_number only range-guards it -
// it cannot know the meaning of 3 moved. Renumber, reorder or remove any
// YADS_SORT_* macro and every existing player's saved preference silently
// becomes a different sort order: the persisted integer means "position in the
// cycle as this version numbered it", nothing more. Adding a mode at the END
// and bumping LEN is the one edit that is still free. Anything else needs a
// config migration, or the deliberate acceptance that saved values reinterpret.
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
            picker: undefined,           // the network picker popup, or undefined (§7b of view.gml)
            remote_pending: undefined,   // YADS_PRESS_* - a hotkey fired; the tick acts (same frame, §5b)
            remote_vk: undefined,        // the remote key's CURRENT keycode (§5c), rebindable live (§5d)
            remote_entry: undefined,     // our row in global.__mmapi_hotkeys; .vk is what the poll reads (§5d)
            rescue_installed: undefined, // the vk_f6 rescue is registered; one-shot latch (§5d)
            remote_key_fallback: undefined, // the config named a key mmapi cannot resolve; we took F6 (§5)
            remote_hold: undefined,      // { frames, vk, rescue } while an ARMED press is still down (§5c)
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
    // sort_mode: the order the grid opens in. A preference for the same reason
    // value_mode is one - it says how you like to read a storage grid - and the
    // one setting a player re-picks on every single panel until it persists.
    // Same range guard, so a hand-edited 9 cannot reach the cycle arithmetic or
    // the label switch.
    //
    // ADDING A KEY DOES NOT NEED A CONFIG-VERSION BUMP, and MUST NOT GET ONE:
    // mmapi_config_read_valid discards a file whose version differs, so a bump
    // would silently reset auto_search and value_mode for every existing player
    // to buy nothing. A new key at the SAME version is self-healing -
    // mmapi_config_number returns the default for a key the file does not have,
    // and the unconditional write below materialises it on the spot.
    // remote_hotkey: the key that opens the linked heart's network from
    // anywhere. A STRING, spelled the way mmapi spells keys - "F6", "F7",
    // "PAGE_UP", "INSERT", "HOME", "DELETE", or a single digit or UPPERCASE
    // letter - because that is the vocabulary mmapi_hotkey_vk_from_name accepts
    // (mmapi_hotkeys.gml payload:11-56) and a player editing this file by
    // hand should be typing the same names the API documents. UPPERCASE is not
    // pedantry: the single-character arm tests ord(name) against ord("0")..ord("9") and
    // ord("A")..ord("Z") only, so "e" resolves to undefined and takes the
    // warn-and-no-hotkey path. Chords are NOT available; yads_install_hotkeys
    // carries the reason.
    //
    // THE FILE IS NO LONGER THE ONLY WRITER, AND IT IS NO LONGER THE FAST ONE.
    // The picker's Rebind button captures a key in-game and commits it here and
    // to the live registry in the same frame (§5d, view.gml §7f), so the normal
    // way to change this key involves neither this file nor a restart.
    //
    // HAND-EDITING THE FILE STILL NEEDS ONE, though, and that is a property of
    // two latches rather than a decision: this struct is memoized in _rt.config
    // and nothing clears it - yads_game_loaded drops ids, categories,
    // recipes_done, view, remote_pending, picks and glow, and deliberately not
    // this - while yads_install_hotkeys is one-shot behind _rt.hotkeys_installed
    // and reads the key at registration time. So the file is READ once per
    // process even though it is now WRITTEN whenever the picker commits.
    // Documented in the README as the alternative it is.
    //
    // Read by hand rather than through a typed accessor because mmapi ships no
    // mmapi_config_string - only _bool and _number (mmapi.gml:524, :534). The
    // shape is the same: wrong type or empty falls back to the default, and the
    // unconditional write below materialises the default into the file so the
    // option documents itself. An unresolvable name is NOT repaired here; it is
    // reported once by yads_install_hotkeys, which is the layer that knows.
    var _hotkey = _source[$ "remote_hotkey"];
    if (!is_string(_hotkey) || _hotkey == "") { _hotkey = YADS_REMOTE_KEY; }

    // remote_default_loc / _x / _y: WHICH Storage Heart a tap of the hotkey
    // opens when several of them hold a remote. Written by the picker's
    // checkboxes and by nothing else; "" / -1 / -1 is "no default", which is
    // what a fresh file says and what the picker writes back when the player
    // unticks the row that was set.
    //
    // THE LOCATION IS A STRING, NOT THE LocationId NUMBER, and that is the same
    // finding that governs ObjectId and ItemId everywhere else in this mod:
    // LocationId is minted from the fiddle tables at load and RENUMBERS
    // whenever the installed content set changes, so an integer written by one
    // install means a different room in the next. The ENGINE ITSELF persists
    // location ids as strings for exactly this reason - every grid file is
    // saved and reloaded through location_id_to_string /
    // string_to_location_id (LoadGame.gml:36, :83, :249) - and
    // location_id_to_string is the round trip we reuse. mmapi ships no
    // mmapi_config_string, so this is hand-read the way remote_hotkey above is:
    // wrong type or absent falls back to the default and the unconditional
    // write below materialises it.
    //
    // THE COORDINATES ARE THE NODE'S OWN top_left, the same pair the flood-fill
    // scan keys its visited set on, so "the same heart" means the same cell in
    // the same location. Nothing here is a save file: the config is per
    // INSTALL, not per save, so a player with two farms can carry a default
    // that names a heart the loaded save does not have. That is benign by
    // construction - yads_remote_scan only ever accepts a default that matches
    // a CURRENTLY bound heart, so a stale one simply fails to match and the tap
    // falls through to the sole-network or picker arm. Documented in the README
    // rather than defended in code, because the alternative (a modsave sidecar)
    // would reintroduce exactly the "data that can disagree with the world"
    // this mod has none of.
    //
    // The range guard on the two numbers is [-1, 100000]: -1 is the sentinel
    // and the upper bound is far past any grid the game has (the farm is
    // 188x144), so a hand-edited file cannot smuggle anything unusable in.
    // Neither number is ever used as an index.
    var _default_loc = _source[$ "remote_default_loc"];
    if (!is_string(_default_loc)) { _default_loc = ""; }

    _cfg = {
        auto_search: mmapi_config_bool(_source, "auto_search", true),
        value_mode: mmapi_config_number(_source, "value_mode",
            YADS_VALUE_OFF, 0, YADS_VALUE_LEN - 1),
        sort_mode: mmapi_config_number(_source, "sort_mode",
            YADS_SORT_CATEGORY, 0, YADS_SORT_LEN - 1),
        remote_hotkey: _hotkey,
        remote_default_loc: _default_loc,
        remote_default_x: mmapi_config_number(_source, "remote_default_x",
            -1, -1, 100000),
        remote_default_y: mmapi_config_number(_source, "remote_default_y",
            -1, -1, 100000),
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
        // never at boot (MOD_ANATOMY.md:107, mmapi_hotkeys.gml payload:103-122).
        //
        // This is also where the config file is first read, because
        // install_hotkeys needs remote_hotkey out of it. The order inside that
        // function is deliberate: the two pager keys are registered BEFORE the
        // config read, so a throw in the file IO costs the remote hotkey only.
        yads_install_hotkeys(_rt);

        // Warm the config here rather than leaving the first read to a widget:
        // the toggle's selected getter and the tooltip poll both call it every
        // frame, and neither is a place to discover a file on disk. Normally a
        // memo hit by now; this is the line that still holds if the hotkey
        // install ever stops reading it.
        yads_config();
    }

    if (_rt.recipes_done != true) {
        yads_ensure_recipes(_rt);
    }

    // THE REMOTE HOTKEY, all three of its beats: the press, the hold watch that
    // press may arm, and the picker row a previous frame chose. AFTER pick_poll
    // (nothing may precede that restore, section 10) and after the boot branch
    // (the hotkey cannot have been registered before it ran), and BEFORE the
    // view work below. Section 5c carries what each beat decides.
    //
    // That last placement is a fast path, not a correctness requirement, and the
    // distinction matters because the obvious reading of it is wrong: a view
    // opened here is reconciled LATER IN THIS SAME TICK, not next frame.
    // The reconcile is a guaranteed no-op: yads_open_view's own projection sets
    // _view.shadow and _view.updates_sum (network.gml:638-639) before it returns,
    // and nothing after it moves an item - InventoryMenu.refresh only re-derives
    // node display from the slots and never touches slot.updates
    // (InventoryMenu.gml:151-162) - so the reconciler's fast path
    // (network.gml:788-789) returns on the updates-sum compare. Below the view
    // work it would cost the same nothing one frame later instead. Above is
    // simply where a statement that can build a menu belongs.
    //
    // The flag is normally undefined, so this costs one struct read. It carries
    // WHICH callback fired (YADS_PRESS_*), because the rescue resolves as a
    // hold and nothing else - see section 5d.
    var _press = _rt[$ "remote_pending"];
    if (_press != undefined) {
        yads_remote_press(_rt, _press == YADS_PRESS_RESCUE);
    }

    // ...and the hold watch that press may have armed, BELOW it and never
    // above. Two reasons, and both are about the press frame:
    //
    //   * a press arriving while an older watch is somehow still live must win,
    //     and it does: yads_remote_press overwrites remote_hold outright.
    //   * the watch counts EVERY frame the key is down INCLUDING the press
    //     frame, which is what makes the threshold a plain "24 frames of
    //     holding". yads_remote_press seeds frames at 0 and this poll, running
    //     immediately after it in the same tick, takes it to 1.
    //
    // Normally undefined, so this costs one struct read.
    if (_rt[$ "remote_hold"] != undefined) {
        yads_remote_hold_poll(_rt);
    }

    // The picker's row tap, applied HERE rather than in the tap callback, for
    // the same reason every other widget in this mod records a request instead
    // of acting: a callback that closed one menu and spawned another would be
    // doing it from inside ANCHOR's own node walk. Costs one struct read.
    var _picker = _rt[$ "picker"];
    if (_picker != undefined && _picker.choice != undefined) {
        yads_picker_choose(_rt, _picker);
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

    // EVERY ITEM THE MOD SHIPS BELONGS IN THIS LIST, and a new one is not
    // optional. recipe_is_default fires on a new game only, so an item missing
    // from here is locked forever on every save that already exists - and if it
    // were ever the only item in its crafting sub-category, the whole tab would
    // vanish too, because CraftingMenu.gml:199-206 drops a sub-category none of
    // whose items are unlocked.
    static ITEM_KEYS = ["netstor_heart", "netstor_block", "netstor_panel",
        "netstor_remote"];

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
// TWO LINE-NUMBER NAMESPACES FOR ONE FILENAME, AND EVERY CITATION SAYS WHICH.
// mmapi_hotkeys.gml exists twice and they are not the same file:
//
//   payload:  the 262-line copy the 0.15.1 installer actually writes into
//             assets.zip. This is what runs. Everything the mod DEPENDS on is
//             cited against it.
//   source:   the 755-line file in the momi repo, which carries the chord and
//             pad machinery the installer strips. Cited only where the point
//             being made is about something that is NOT in the payload.
//
// An unmarked ":650" used to send a reader 387 lines past the payload's EOF, so
// the marker is not decoration. Same convention in view.gml section 7f and in
// docs/remote-facts.md.
//
// PAGE_UP / PAGE_DOWN as an accessibility extra for the paging arrows. Bound to
// function-style keys on purpose: the poll reads raw keyboard state and fires
// even while a text field has focus (mmapi_hotkeys.gml payload:220-260), so a
// letter bind would type into our own search box. F8/F9/F10 belong to the debug
// agent and must never be claimed (DEBUG.md:26-30).
//
// THE REMOTE'S KEY IS THE PLAYER'S, AND THESE TWO ARE NOT. The pager pair is
// fixed and the rebind capture refuses to hand either of them out (view.gml
// 7f), because they are already registered here and one key doing two of our
// jobs is not a shortcut anyone asked for. The remote key is chosen in-game and
// applied live - section 5d - which is also why the letter argument above is
// now a WARNING rather than a rule: a player who wants a letter may have one,
// told at the moment they pick it what it will do to the search box.
//
// NO GAMEPAD BINDING, and that is a finding rather than an omission. The only
// two pad buttons a "browse from anywhere" gesture could plausibly want are the
// stick clicks, and BOTH are taken by vanilla gameplay: gp_stickl is
// InputId.Ride (Settings.gml:133, and Patches.gml:1204-1226 is a save migration
// that deliberately MOVED it there) and gp_stickr is InputId.NextToolbarTab
// (Settings.gml:161, consumed at ToolbarMenu.gml:116). The mmapi poll does not
// consume a plain press - only a matched multi-part chord consumes its trigger,
// and then only against other mmapi registrations (mmapi_hotkeys.gml
// source:639-648) - so registering either one would fire OUR callback and the
// vanilla action on the same click. A pad user who mounts their horse and lands
// in a storage menu is worse off than a pad user with no shortcut at all. The
// paddles are the only genuinely unbound pad buttons in the vanilla table, and
// mmapi's own name->gp_* map has no entry for them (mmapi_hotkeys.gml
// source:109-130), so they are out of reach. Both of those citations are SOURCE
// lines by necessity: neither the chord poll nor the pad map exists in the
// payload at all, which is the paragraph below. Keyboard only, per the README.
//
// And the question is settled a second time, ahead of that argument, by the
// shipped installer: the collision reasoning above is derived from the mmapi
// SOURCE tree, but the 0.15.1 payload the installer actually ships carries no
// pad machinery whatever - no mmapi_hotkey_register_pad, no __mmapi_pad_hotkeys,
// no gamepad_button_check_pressed, and no chord apparatus either (see the note
// in yads_install_hotkeys). There is nothing to call. The collision argument is
// what would still be true if there were.
function yads_install_hotkeys(_rt) {
    if (_rt.hotkeys_installed == true) { return; }
    _rt.hotkeys_installed = true;

    // EVERY REGISTRATION NAMES US EXPLICITLY. mmapi_hotkey_register falls back
    // to mmapi_current_mod() for the entry's mod_name, and that global is only
    // set while the installer is draining a mod's own install - outside it the
    // function returns the literal "unknown" (mmapi.gml:32-36). These calls run
    // from OUR TICK, i.e. from the lifecycle drain and not the install drain, so
    // without the opts every conflict Warn, every rejected-KeyCode Warn and
    // every failed-callback Warn in the log would blame a mod called "unknown".
    // mmapi's own debug agent passes the same opts for the same reason
    // (mmapi_debug.gml:967-969).
    var _prev = mmapi_hotkey_vk_from_name("PAGE_UP");
    if (_prev != undefined) {
        mmapi_hotkey_register(_prev, yads_hotkey_prev_page, { mod_name: YADS_MOD });
    }

    var _next = mmapi_hotkey_vk_from_name("PAGE_DOWN");
    if (_next != undefined) {
        mmapi_hotkey_register(_next, yads_hotkey_next_page, { mod_name: YADS_MOD });
    }

    // The remote's key, from the config file.
    //
    // SINGLE KEYS ONLY - NOT A SIMPLIFICATION, A PLATFORM LIMIT. mmapi's chord
    // API (mmapi_hotkey_binding_from_name + mmapi_hotkey_register_binding,
    // which would let remote_hotkey read "CONTROL+F6") exists in the mmapi
    // SOURCE tree but is NOT in the payload the installer actually ships:
    // grepping ModsOfMistriaInstaller-cli.exe 0.15.1 - the version this mod
    // declares as its minimum - finds mmapi_hotkey_vk_from_name and
    // mmapi_hotkey_register and neither binding symbol. Calling them is a
    // strict-lint finding ("calls X, which nothing defines") and one finding
    // excludes the WHOLE mod, content included. The same probe says
    // mmapi_hotkey_register_pad is absent too, which settles the gamepad
    // question a second time over on top of the one in the header comment.
    //
    // check_symbols.py cannot catch this class of thing and it is worth knowing
    // why: its corpus is the mmapi SOURCE checkout, which is ahead of the exe.
    // The momi lint is the only gate that reads what will really be installed.
    //
    // vk_from_name returns undefined for anything it cannot resolve, chord
    // strings included (it splits on nothing and rejects multi-character names
    // outside its table, mmapi_hotkeys.gml payload:11-56), so one test covers a
    // typo, a chord, and a key the engine has no KeyCode for.
    //
    // ONE WARN AND THE FULL LADDER ON F6, WHICH INVERTS WHAT BETA 1.2 SHIPPED.
    // That version argued for "one warn and NO hotkey": a player who typed a key
    // they meant is better served by the shortcut being visibly absent, with a
    // line in the log saying so, than by it silently answering on a key they did
    // not ask for. The argument was sound while the config file was the only way
    // to set the key. It is not sound any more, and the reason is the Rebind
    // button: the surface that repairs a bad binding is now BEHIND the hotkey.
    // "No hotkey" means no picker, which means no Rebind button, which means the
    // only way out of a typo is finding the config file - the exact thing the
    // in-game rebind exists to spare the player. A dead shortcut is no longer a
    // clear signal; it is a locked door.
    //
    // So an unresolvable name takes F6 - the documented default - with the WHOLE
    // gesture ladder on it, not a stripped rescue. It is a working shortcut on a
    // key the README names, the log says exactly what was wrong, and the toast
    // below says it where a player will actually read it. One press of F6 then
    // reaches the picker, whose Rebind button writes a name the file will parse
    // next time. (F6 hard-coded rather than YADS_REMOTE_KEY resolved through the
    // vocabulary: this is the arm where a name FAILED to resolve, and answering
    // it with another name lookup would leave one more way to end up with
    // nothing at all.)
    var _name = yads_config().remote_hotkey;
    var _vk = mmapi_hotkey_vk_from_name(_name);
    if (_vk == undefined) {
        mmapi_log_warn(YADS_MOD, "remote_hotkey \"" + _name
            + "\" is not a single key mmapi can resolve; falling back to F6."
            + " Use a name like F6, F7, PAGE_UP, INSERT or HOME - or just hold"
            + " F6 and press Rebind key in the network picker.");
        _rt.remote_key_fallback = true;
        _vk = vk_f6;
    }

    // KEPT, and this is the one line the hold gesture rests on. The poll hands
    // our callback a press EDGE and nothing else, so "is it still down?" has to
    // be asked by us, on the same keycode, on later frames - see section 5c.
    // Stored BEFORE the registration so the field and the binding can never
    // disagree about which key this is.
    _rt.remote_vk = _vk;

    // The return is deliberately NOT read here, unlike at the rebind commit
    // (view.gml 7f). At install there is nobody to tell and nothing to undo: a
    // refusal has already logged exactly one Warn from mmapi, _rt.remote_entry
    // stays undefined so a later commit heals with a FRESH registration instead
    // of mutating a corpse, and the rescue below is the recovery either way.
    yads_remote_register(_rt, _vk);

    // And the rescue, if the key we just took is not F6 already. Section 5d.
    yads_ensure_rescue(_rt);
}

//
// 5d. THE LIVE REBIND, AND THE RESCUE THAT MAKES IT SAFE
//
// The picker's Rebind button captures a key and applies it WITHOUT a restart.
// Two mechanisms make that possible and one makes it survivable; all three are
// properties of the shipped payload rather than of the mmapi source tree, so
// every claim below cites the payload the installer really carries.
//
// (1) THE POLL RE-READS THE ENTRY EVERY FRAME. mmapi_hotkeys_poll snapshots
//     only the array LENGTH (mmapi_hotkeys.gml payload:231); inside the loop
//     it takes the entry fresh (`var entry = hotkeys[i]`, :233) and reads
//     `entry.vk` on the spot (`keyboard_check_pressed(entry.vk)`, :240). So
//     writing a new vk into our own entry struct changes which key fires our callback on the
//     very next poll. Nothing has to be de-registered - and nothing COULD be:
//     the payload has no unregister call at all.
//
// (2) WE CAN HOLD A REFERENCE TO THAT ENTRY. array_push is the only writer of
//     global.__mmapi_hotkeys (:133) and there is no remover, so the array is
//     append-only and an entry's identity is stable for the process. What is
//     NOT stable is the assumption that registering pushed one: register
//     early-RETURNS without pushing when the engine rejects the KeyCode and the
//     environment demonstrably has a keyboard (:110-122). yads_remote_register
//     therefore measures the length before and after and only claims
//     _reg[_before] when it grew by exactly one.
//
// (3) THE DEAD FLAG IS PERMANENT, AND IT IS THE ONE REAL HAZARD. If the engine
//     ever throws on an entry's KeyCode at poll time, the poll sets
//     entry.dead = true and skips that entry forever (:234, :241-247). NOTHING
//     in the payload clears it - not register, not the poll, not the capability
//     sweep - so a single bad vk written into our entry would retire the remote
//     hotkey for the rest of the session with no way back.
//
//     The capture path retires that hazard rather than guarding against it. A
//     vk only ever reaches the commit if it (i) came out of
//     mmapi_hotkey_vk_from_name, i.e. it is in the engine's KeyCode table by
//     mmapi's own resolver, and (ii) was JUST returned true by
//     keyboard_check_pressed inside the capture poll on this very frame. (ii)
//     is a STRONGER proof than register's own probe: register calls
//     keyboard_check once and infers, while we have watched the engine accept
//     this exact code in this exact session. A code that has just been polled
//     cannot be a code the poll is about to throw on.
//
//     We still never write over a corpse. If our entry is missing or already
//     carries dead, the commit registers a FRESH entry instead of mutating the
//     old one - which respects mmapi's ownership of that flag (we never clear a
//     flag we did not set) and costs one skipped struct read per frame forever.
//
// THE RESCUE. A player can bind the remote to a key their keyboard cannot
// produce, or a key they then forget. The picker is the only surface that can
// rebind, and the hotkey is the only way to the picker, so a bad bind would
// otherwise be a locked door with the key inside. vk_f6 - the documented
// default - is therefore registered a SECOND time as a permanent hold-only
// rescue whenever the remote key is something else.
//
// HOLD-ONLY, and that is what keeps it from being a second hotkey. A tap of F6
// after rebinding to J does nothing at all: the rescue arms the hold watch and
// an early release resolves to nothing (yads_remote_hold_poll's rescue arm).
// So F6 is not a shortcut the player has to think about; it is a 400ms
// insurance policy that only ever produces the list.
//
// NOT REGISTERED WHEN THE REMOTE KEY IS ALREADY F6, which is the default and
// therefore the common install. Two entries on one vk is a supported state -
// mmapi logs a conflict Warn and fires both (:124-133) - but the Warn would be
// noise in every default log, and the two callbacks would both answer one press.
// The callback carries the mirror guard for the case the latch cannot cover:
// registering happens once, but a player can rebind BACK to F6 afterwards, and
// from that frame on the rescue must stand down and let the ladder answer.
//
// THE LATCH IS SET AFTER THE REGISTRATION, NOT BEFORE, and the order matters
// for exactly one reason: mmapi_hotkey_register early-returns WITHOUT pushing
// when the engine rejects the KeyCode (payload:110-122). Latching first would
// record "installed" against nothing and refuse to try again for the rest of
// the process - and this is the locked-door insurance, the one registration
// this mod cannot afford to lose quietly. The same pre/post length test
// yads_remote_register uses, for the same reason; a refusal simply leaves the
// latch down so the next commit tries again.
function yads_ensure_rescue(_rt) {
    if (_rt[$ "rescue_installed"] == true) { return; }
    if (_rt[$ "remote_vk"] == vk_f6) { return; }

    var _reg = global[$ "__mmapi_hotkeys"];
    var _before = (_reg == undefined) ? 0 : array_length(_reg);

    mmapi_hotkey_register(vk_f6, yads_hotkey_remote_rescue, { mod_name: YADS_MOD });

    _reg = global[$ "__mmapi_hotkeys"];
    if (_reg == undefined) { return; }
    if (array_length(_reg) != _before + 1) { return; }

    _rt.rescue_installed = true;
}

// Register the primary remote hotkey and keep the registry entry it produced.
//
// THE PRE/POST LENGTH TEST IS THE WHOLE POINT. mmapi_hotkey_register returns
// nothing and does not always push (mmapi_hotkeys.gml payload:110-122), so
// "the last element is ours" is a guess. Measuring the length across the call
// turns it into a fact, and because the array is append-only the index we
// measured names our entry for the rest of the process.
//
// Returns true when _rt.remote_entry now names a live entry. A false means the
// engine refused the KeyCode: the config-file binding is still recorded in
// _rt.remote_vk (so the hint and the rebind commit stay honest about what the
// player asked for) and mmapi has already logged exactly one Warn saying so.
function yads_remote_register(_rt, _vk) {
    // Guarded read: the global does not exist until the first registration, and
    // a bare read of an unset global faults on this runtime.
    var _reg = global[$ "__mmapi_hotkeys"];
    var _before = (_reg == undefined) ? 0 : array_length(_reg);

    mmapi_hotkey_register(_vk, yads_hotkey_remote, { mod_name: YADS_MOD });

    // Re-read rather than reuse: register CREATES the global on its first call
    // (mmapi_hotkeys.gml payload:97), so the pre-call read can legitimately
    // be undefined while the post-call one is not.
    _reg = global[$ "__mmapi_hotkeys"];
    if (_reg == undefined) { return false; }
    if (array_length(_reg) != _before + 1) { return false; }

    _rt.remote_entry = _reg[_before];
    return true;
}

// Point the live registration at a new key. The single writer of the pair
// (_rt.remote_vk, entry.vk), which is why it exists as a function rather than
// three lines at the call site: the hold poll and yads_remote_ready read one of
// them and the mmapi poll reads the other, and a frame in which they disagreed
// would arm a watch on a key that is not the key that fired.
//
// THE CALLER OWES THE PROOF, and it is the one in section 5d(3): _vk must have
// come from mmapi_hotkey_vk_from_name AND have just been accepted by
// keyboard_check_pressed this frame. Nothing else may call this.
//
// RETURNS "the registry now answers _vk". True on the mutation path, which
// cannot fail - the entry is ours and the write is a field assignment - and on
// a heal that registered. FALSE only when the heal's registration was refused,
// in which case _rt.remote_vk names a key nothing is listening for and the
// CALLER MUST NOT REPORT SUCCESS: the picker's commit is the one caller, and it
// stays in capture and says so rather than writing the config file.
function yads_remote_rebind(_rt, _vk) {
    _rt.remote_vk = _vk;

    var _entry = _rt[$ "remote_entry"];
    if (_entry == undefined || _entry[$ "dead"] == true) {
        // No live row, or a retired one we must not resurrect (5d(3)). Register
        // a fresh entry and let the old one sit in the array being skipped.
        _rt.remote_entry = undefined;
        return yads_remote_register(_rt, _vk);
    }

    _entry.vk = _vk;
    return true;
}

// Hotkey callbacks take no arguments (mmapi_hotkeys.gml payload:250).
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
// 5b. THE REMOTE HOTKEY
//
// RAISES A FLAG AND NOTHING ELSE, and the frame order is the interesting part -
// so it is DERIVED here rather than assumed, because an earlier version of this
// comment assumed it and got it backwards.
//
// THE ORDER, PROVEN. The poll and our tick land in the SAME drain, in a fixed
// order, and the poll is first:
//
//   1. mmapi_run_installs() is the FIRST statement of Game.step_begin, inserted
//      above TICK++ by the game_step_begin_installs engine fix
//      (seams.toml:2195), against the pristine body at Game.gml:570-582.
//   2. It is a plain forward loop over push order with no sorting and no
//      removal: array_push at mmapi.gml:51-53, the drain at :66-84. Every
//      registered fn runs every frame, in registration order.
//   3. mmapi_hotkeys_poll self-registers at payload FILE SCOPE
//      (mmapi_hotkeys.gml payload:262). Our tick registers through
//      mmapi_register(yads_tick) inside yads_register_callbacks (:564), reached
//      from the executable tail of this file. mmapi's tree is staged before any mod's
//      and installs under assets/gml/scripts/mmapi/, which sorts ahead of
//      assets/gml/scripts/mykay_yads__.../ - so the poll takes a LOWER index in
//      global.__mmapi_installs and runs before us in every drain.
//
// Therefore the callback below sets remote_pending and yads_tick consumes it
// (:651-654) LATER IN THE SAME mmapi_run_installs() CALL: the view is built on
// the press frame, before INPUT.begin_frame() and before ANCHOR.on_begin_step().
// Not the next frame. Anything downstream that wants a "previous frame" property
// does not have one.
//
// SO WHY A FLAG AT ALL, given it buys no frame. Position and cost, both real.
// Opening from the callback would build a menu at an arbitrary point relative to
// yads_pick_poll, whose place at the head of the tick is load-bearing (section
// 10), and would put a ~15k-op scan plus a menu build inside a poll iterating a
// global array. The tick has one defined position in our own function; the
// callback has none.
//
// THE AUTO-FOCUS EDGE, argued from the real order. yads_open_view focuses the
// search box in the same call that builds it, so on this path search_think's
// FIRST run is later in the same frame, with the hotkey's press still live.
// Safe, and for a reason that is about the keycode rather than the frame:
//
//   * a function key deposits nothing into keyboard_string(). The engine has
//     exactly one keyboard_string() site and it appends the raw return value
//     into every vanilla text node with no filtering (Anchor.gml:470-486, farm
//     / pet / save naming). If F-keys emitted glyphs there, vanilla's own text
//     entry would be visibly corrupt.
//   * nothing reads vk_f6. The engine names it in three places, none of them a
//     reader: the KEYBOARD_INPUTS membership list (InputUtils.gml:180) and the
//     two name<->code tables (:590, :705). No vanilla default binds any F-key -
//     Settings.gml's binding table has no vk_f* at all - and this mod reads no
//     keycode of its own.
//   * every blur path in the search editor is keyed to something else: vk_escape
//     / vk_enter (view.gml:2491), InputId.MenuBack (:2518), the Steam-OSK arm
//     (:2530, disarmed at the source by open_view's ON_KBM && !steam_on_deck
//     gate) and a left-click outside the plate (:2549). None is reachable by F6.
//
// The safety is over-determined, which is worth saying plainly: it would survive
// any one of those three being wrong. What it would NOT survive is a future blur
// path that reads a raw keypress, and that is the reader this note exists for.
//
// ONE REAL STRUCTURAL DIFFERENCE from the panel path, recorded because it is not
// obvious: a menu spawned from interact() is built after this frame's ANCHOR
// pass, so its first hover/tap walk is next frame, while a menu built in our tick
// is walked in the SAME frame it is born. Tap-through is still impossible - the
// hover acquire needs mouse_is_active (Anchor.gml:387) and the tap needs
// take_tap (:404), which is take_press on LeftMouse/Interact (:1832-1834 ->
// Input.gml:270 -> raw_status(id, true)). A press that predates the menu produced
// its Pressed edge on an earlier frame, and raw_status MUTES what it hands out
// (Input.gml:421-429) with the Muted flag cleared only by a fresh press edge
// (:47-52) - so there is no press flag left for a brand-new node to take. A click
// ON the open frame is a genuine click on a menu that exists.
//
// The flag is a plain latch, not a counter: two presses in one frame are one
// open, and a press while a view or the picker is already up is a no-op (the
// guard is yads_remote_ready, called from yads_remote_press, not here, so that
// this stays the cheapest possible callback on a poll that runs every frame).
function yads_hotkey_remote() {
    yads_runtime().remote_pending = YADS_PRESS_PRIMARY;
}

// The permanent vk_f6 rescue (section 5d). Same shape as the callback above -
// raise a flag, decide nothing - plus the one guard the latch cannot express.
//
// THE MIRROR GUARD. yads_ensure_rescue refuses to register while the remote key
// IS F6, but a player can rebind back to F6 afterwards, and there is no way to
// take a registration back. From that frame the primary entry and this one both
// answer F6, so this callback stands down and the ladder answers alone.
//
// PRIMARY PRECEDENCE, AND THE MIRROR GUARD IS WHAT DELIVERS IT - not push
// order, which an earlier version of this comment named and which does not
// hold. Install order is PAGE_UP, PAGE_DOWN, primary, rescue, and the poll is a
// plain forward loop over that order (mmapi_hotkeys.gml payload:232), so the
// primary does run first at install. But yads_remote_rebind's heal path APPENDS
// a fresh primary when our entry is missing or dead, and an append lands AFTER
// the rescue - from that moment the loop visits the rescue first and guard 2
// below can never be the thing that resolves a shared frame.
//
// It does not need to be. The ONLY state in which both entries fire on one
// frame is entry_primary.vk == entry_rescue.vk == vk_f6, i.e. _rt.remote_vk ==
// vk_f6 - and that is exactly guard 1, which stands the rescue down whatever
// the visit order. yads_remote_rebind sets _rt.remote_vk on its FIRST line,
// before touching the entry, so the guard is already true on the frame the
// rebind lands.
//
// Guard 2 therefore earns its place against a STALE flag rather than a shared
// frame: if yads_tick throws above the hotkey block, remote_pending survives
// unconsumed into the next frame, and the guard suppresses one rescue press
// rather than acting on a flag nobody cleared. Cheap, and it keeps "two entries
// on one key must resolve to the ladder" true by two independent routes.
function yads_hotkey_remote_rescue() {
    var _rt = yads_runtime();
    if (_rt[$ "remote_vk"] == vk_f6) { return; }
    if (_rt[$ "remote_pending"] == YADS_PRESS_PRIMARY) { return; }
    _rt.remote_pending = YADS_PRESS_RESCUE;
}

//
// 5c. WHICH NETWORK, AND THE HOLD THAT ASKS
//
// A player can bind a remote to every Storage Heart they own, so one keypress
// has to answer "which one". Beta 1.2's first cut answered it by guessing -
// local heart, else the only one, else the first in the registry plus a toast
// apologising for the guess - and the toast was the tell that the guess was the
// wrong shape of answer. It is now a CHOICE the player makes, once, and a list
// they can open whenever they want to change it.
//
//   TAP    the valid default, else the only bound heart, else the picker.
//   HOLD   the picker, always.
//   0 bound   the remote_none toast, on either gesture.
//
// ALL THREE ROWS ARE ABOUT THE PLAYER'S OWN KEY, whatever they have rebound it
// to (section 5d). The vk_f6 RESCUE runs a different, deliberately smaller
// gesture - hold only, picker only, nothing on a tap - and is registered only
// while the remote key is not F6 itself.
//
// THE ARMING PREDICATE, derived rather than picked, and corrected in the field.
// Write T for what a tap does and H for what a hold does, over the two things
// the press frame knows - the number of bound hearts C and whether a VALID
// default exists D:
//
//   C = 0            T = toast     H = toast     same    do not arm
//   C = 1, !D        T = open it   H = picker    differ  ARM
//   C = 1, D         T = open it   H = picker    differ  ARM  (D names that one)
//   C >= 2, D        T = default   H = picker    differ  ARM
//   C >= 2, !D       T = picker    H = picker    same    do not arm
//
// Waiting is only ever worth its latency where T and H DIFFER, which is the
// middle three rows - and every one of them now arms:
//
//     armed  <=>  (C == 1 || D)
//
// C >= 2 with no default stays unarmed because its TAP already opens the
// picker on the press frame: arming would spend 400ms to reach an outcome the
// player is already looking at. Note what that means for the user-facing rule -
// "hold the key and the list appears" is true THERE TOO, it just appears
// sooner. So with any network bound at all:
//
//     HOLDING THE KEY ALWAYS SHOWS THE PICKER.
//
// That is the sentence the README, the Nexus page and remote_key_bad all tell
// the player, and it is now true in every state instead of in the states an
// optimisation happened to leave standing.
//
// TWO EARLIER PREDICATES FELL HERE. One is still load-bearing, one is the trap:
//
//   * `C >= 2 || D`, the first cut. It armed the C>=2,!D row that its own
//     table marks "same outcome", paying release latency for nothing - B12p
//     wave-1 A-m1. That lesson is still valid and is why that row is still out.
//   * `D` alone, the picker audit's correction. It dropped C=1,!D as well, on
//     the argument that the hold there "offers only a checkbox whose default
//     the tap ladder reaches anyway". True of the CHECKBOX and false of the
//     SURFACE: the Rebind button (section 5d) lives in that same footer, so one
//     bound network and no default made the picker - and with it the only way
//     to change the remote key in game - unreachable. Reported from play as
//     "holding F6 does not seem to do anything", which is exactly what an
//     unarmed hold looks like. The optimisation had optimised away the mental
//     model every instruction we ship depends on.
//
// The C == 1 arm costs one key RELEASE on a single-network tap, which is
// imperceptible, and buys the whole settings surface. It is not a special case
// bolted on: it is the C=1 rows of the table, which always said "differ".
//
// WHY THE PREDICATE READS A *VALIDATED* DEFAULT rather than "the file has one":
// an unmatched default changes no tap outcome (the ladder falls through it), so
// arming on it would add 400ms to a keypress in exchange for nothing. At C = 1
// a stale default is now doubly harmless - D goes false, the C == 1 arm holds
// the row anyway, and the release still opens the sole network, which is the
// same node the default would have named had it matched.
//
// Clearing a default is still possible from any C, and by two routes now: D
// re-arms the hold that opens the list that unticks it, and at C = 1 the hold
// is armed whether or not D holds.
//
// LOCAL-FIRST IS NOW AN ORDERING, NOT A CHOICE. 1.2 opened the heart in the
// room you were standing in without asking. That silent preference is gone -
// tap goes to your default wherever it is, which is what a default means - but
// the information is not: yads_remote_scan lists hearts in the current location
// first, so the picker's top rows are the ones you are next to.
//

// Every Storage Heart in this save that is holding a Remote Access Panel.
//
// THE BINDING IS CONTAINMENT. There is no mod save data anywhere in YADS and
// there is not going to be: "linked" means a netstor_remote item is sitting in
// that heart's own Inventory, which the ENGINE already saves, loads, migrates
// and backs up as part of the chest it lives in. Nothing to version, nothing to
// repair, nothing that can disagree with the world.
//
// WALK STORAGE_NODES, NEVER GRIDS[]. The global node list is the only
// enumeration that reaches every placed unit in the save: GRIDS is indexed by
// location and the dynamic grids (greenhouses, the mini-museum, every table
// surface) are not in it under a location id at all, so a GRIDS walk silently
// cannot see a heart in the greenhouse. Section 9's rescan reads the same
// global for the same reason; the difference is that IT filters to the current
// location and this deliberately does not.
//
// Returns { entries: [ { node, loc, tx, ty } ], default_index }, entries in
// picker order - current location first, registry (i.e. placement) order within
// each group - and default_index the position of the entry the config file
// names, or -1 when the file names none of them. It TOASTS FOR NOBODY: an empty
// list is a fact the two callers report differently.
function yads_remote_scan() {
    var _out = { entries: [], default_index: -1 };

    var _ids = yads_ids();
    if (_ids.heart == undefined || _ids.remote_item == undefined) {
        return _out;   // content not installed
    }

    // Same guarded read as glow_poll: variable_global_exists does not exist on
    // this runtime and a bare read of an unset global faults. STORAGE_NODES is
    // cleared at the start of a load (Game.gml:28), so this is also the "world
    // is not up yet" test.
    var _list = global[$ "__STORAGE_NODES"];
    if (_list == undefined) { return _out; }

    // The player's current location, for the ordering below. Guarded the same
    // way and allowed to be undefined - a missing GRID just means every bound
    // heart is "elsewhere", which is a fine answer for a rule that only ever
    // PREFERS the local ones.
    var _world = global[$ "__grid"];
    var _here = (_world == undefined) ? undefined : _world[$ "location_id"];

    var _local = [];
    var _rest = [];

    var _len = _list.count();
    for (var _i = 0; _i < _len; _i++) {
        var _node = _list.get(_i);
        if (_node == undefined) { continue; }
        if (_node[$ "object_id"] != _ids.heart) { continue; }

        var _inventory = _node[$ "inventory"];
        if (_inventory == undefined) { continue; }
        if (_inventory.item_id_quantity(_ids.remote_item) <= 0) { continue; }

        // [$ ] on parent_grid AND on its location_id. Section 9's rescan reads
        // the latter bare and has shipped that way, but it only ever asks about
        // nodes it is about to filter by location; this walk deliberately spans
        // every grid in the save, dynamic ones included, and a grid shape
        // without the field would fault a bare read.
        var _grid = _node[$ "parent_grid"];
        var _where = (_grid == undefined) ? undefined : _grid[$ "location_id"];

        var _entry = {
            node: _node,
            loc: yads_loc_key(_grid),      // "" when it cannot be named in a file
            tx: _node[$ "top_left_x"],
            ty: _node[$ "top_left_y"],
        };

        if (_here != undefined && _where == _here) {
            array_push(_local, _entry);
        } else {
            array_push(_rest, _entry);
        }
    }

    for (var _i = 0; _i < array_length(_local); _i++) {
        array_push(_out.entries, _local[_i]);
    }
    for (var _i = 0; _i < array_length(_rest); _i++) {
        array_push(_out.entries, _rest[_i]);
    }

    // THE DEFAULT IS VALIDATED AGAINST THIS LIST AND NOWHERE ELSE. The config
    // file is per install, not per save, so it can name a heart the loaded save
    // has never had - a second farm, a different profile, a network the player
    // dismantled. Matching it here means a stale default is not an error state
    // at all: it matches nothing, default_index stays -1, and the tap ladder
    // falls through to the sole-network or picker arm exactly as if the file
    // had been empty.
    var _cfg = yads_config();
    var _loc = _cfg.remote_default_loc;
    var _x = _cfg.remote_default_x;
    var _y = _cfg.remote_default_y;

    if (is_string(_loc) && _loc != "" && _x >= 0 && _y >= 0) {
        for (var _i = 0; _i < array_length(_out.entries); _i++) {
            var _candidate = _out.entries[_i];
            if (_candidate.loc == _loc
                && _candidate.tx == _x
                && _candidate.ty == _y) {
                _out.default_index = _i;
                break;
            }
        }
    }

    return _out;
}

// The stable, install-independent name of the location a grid belongs to, or ""
// when there is not one. This is the string the config file stores; see the
// remote_default_loc note in section 1b for why a string and not the LocationId
// number.
//
// Child grids - table surfaces - INHERIT their owner's location id
// (Furniture.gml:708 passes grid.location_id straight into the new Grid), so a
// heart standing on a table names the room it is in, and two hearts at the same
// cell coordinates in one room, one of them on a table, would be one identity.
// Noted rather than defended: our units are 4x2 and the collision needs both
// nodes to share a top_left, which is not a shape a table surface can offer a
// crate this size.
function yads_loc_key(_grid) {
    if (_grid == undefined) { return ""; }

    var _id = _grid[$ "location_id"];
    if (!is_real(_id)) { return ""; }

    // Bound the codegen'd converter against the table the engine built, rather
    // than trusting a number that arrived from a struct field.
    var _table = global[$ "__locations"];
    if (_table == undefined) { return ""; }
    if (_id < 0 || _id >= array_length(_table)) { return ""; }

    return location_id_to_string(_id);
}

// The HUMAN name of a grid's location, for the picker's rows, or undefined when
// the game has none. Not to be confused with yads_loc_key above, which is the
// machine-readable one the config file stores.
//
// TWO SOURCES, because locations.toml has no single one. LOCATIONS[id].name is
// a LOCALIZATION KEY rather than text (l10n.meta.toml registers
// `locations = ["*/name"]`, so the fiddle build replaces the value with its own
// key path), and it is the ONE field on that struct built without a
// `?? location_default` fallback (Location.gml:88) - so it is undefined for
// every location whose table omits `name`, which is most of them. The farm is
// one of those, and it is also the one place the player named themselves, so it
// reads ARI.farm_name the way the map does (MapMenu.gml:83) and
// show_room_title does (anchor_utils.gml:1771).
//
// Everything still unnamed after those two - the greenhouses, the barns and
// coops, the mini-museum - returns undefined and the picker prints its numbered
// fallback instead. Their real names live on the BUILDING node rather than on
// the location (find_building(dyn_index).name, BuildingUtils.gml:27), and
// reaching them costs a 27k-cell walk of the farm grid behind a global cache
// with no reset hook we can see. Declined: a row that says "Network 3" beside
// its own block count and fill percentage is not ambiguous in play, and the
// name is the only thing lost.
function yads_loc_name(_grid) {
    if (_grid == undefined) { return undefined; }

    var _id = _grid[$ "location_id"];
    if (!is_real(_id)) { return undefined; }

    var _table = global[$ "__locations"];
    if (_table == undefined) { return undefined; }
    if (_id < 0 || _id >= array_length(_table)) { return undefined; }

    // Compared as a STRING rather than against LocationId.Farm: the enum is
    // fiddle-minted and this mod never spells a minted member, while the toml
    // table name it derives from is the same in every install.
    if (location_id_to_string(_id) == "farm") {
        var _farm = ARI[$ "farm_name"];
        if (is_string(_farm) && _farm != "") { return _farm; }
        return undefined;
    }

    var _entry = _table[_id];
    if (_entry == undefined) { return undefined; }

    var _key = _entry[$ "name"];
    if (!is_string(_key) || _key == "") { return undefined; }

    // local_has takes the full key path (FiddleParsers.gml:355) and is the
    // engine's own "is this string translatable" test. Without it a location
    // whose key never made it into the tables would print the key.
    if (!local_has(_key)) { return undefined; }
    return local_get(_key);
}

// May the hotkey act at all? Every clause earns its place:
//
//   obj_ari - no player instance means no ARI.inventory to pair the menu
//     against and no safe ESC-drop target, the same reason object_interact
//     bails on it. Also the title screen.
//   game_paused() - PAUSE_STATUS is a bitfield of CUTSCENE | WINDOW | MENU
//     (Pause.gml:1-15), so this ONE call covers a cutscene, an unfocused game
//     window and every open menu including a chest the player is already in.
//     The hotkey poll has no pause test of its own, which is exactly why this
//     one has to be here.
//
//     WINDOW IS NOT "A MODAL DIALOG". It is OS window focus and nothing else:
//     the only two writers in the corpus are Window.on_end_step's focus-lost
//     and focus-regained arms (Window.gml:42, :53), both behind
//     SETTINGS.get("pause_on_unfocus") (:37). The in-game cases are covered by
//     MENU instead, dialogue included: [default] pause = "main" in
//     ui/menus/standard_menus.toml is inherited by every entry in that file,
//     [storage] and [textbox] included, and "main" maps to PauseStatus.MENU
//     (AnchorMenu.gml:33-42), applied in the menu's own create at :111-112.
//   the FSM state - paused is not the same as busy. Fishing, swinging a tool,
//     riding into a transition and every other transient state leaves
//     PAUSE_STATUS empty, and opening a storage menu on top of one of them puts
//     the player back into it on close. Default and MountDefault are the two
//     states in which the player is simply standing (or sitting on a horse)
//     with nothing in flight.
//   _rt.view / _rt.picker - ANCHOR.get_menu asserts when two menus of ONE TYPE
//     are open at once (Anchor.gml:160-167). Both are redundant against
//     game_paused today, since either menu sets PauseStatus.MENU, and both are
//     kept because they are the invariants this mod actually depends on rather
//     than implications of someone else's flag. The picker clause is what stops
//     a second press from stacking a second popup on the first.
//
// Read by the press handler AND re-read at the moment a hold resolves, because
// 400ms is long enough for a cutscene to start.
function yads_remote_ready(_rt) {
    if (!instance_exists(obj_ari)) { return false; }
    if (game_paused()) { return false; }
    if (_rt.view != undefined) { return false; }
    if (_rt[$ "picker"] != undefined) { return false; }

    var _state = obj_ari.fsm.current_state_id();
    return (_state == PlayerState.Default || _state == PlayerState.MountDefault);
}

// Consume the pending flag: the press frame, and only ever the press frame.
// Called from the tick, after pick_poll and after the boot branch, i.e. from
// step_begin on the SAME frame the key went down - the hotkey poll registers
// ahead of our tick and both run inside one mmapi_run_installs() drain, so the
// flag is raised and consumed without a frame in between. Section 5b carries
// the derivation and what the auto-focus safety actually rests on (the keycode,
// not the frame).
function yads_remote_press(_rt, _rescue) {
    _rt.remote_pending = undefined;

    // A press that cannot act also cancels any watch it might otherwise have
    // inherited: the world moved, and a stale hold has nothing left to resolve
    // against.
    if (!yads_remote_ready(_rt)) {
        _rt.remote_hold = undefined;
        return;
    }

    // THE RESCUE PRESS ARMS AND DECIDES NOTHING (section 5d). No scan, no
    // toast, no tap outcome: it is 400ms of F6 or it never happened. Arming is
    // unconditional here precisely because the arming predicate below is about
    // whether tap and hold DIFFER, and for the rescue there is no tap arm to
    // differ from - the whole gesture is the hold.
    if (_rescue) {
        _rt.remote_hold = { frames: 0, vk: vk_f6, rescue: true };
        return;
    }

    // A hand-edited config named a key mmapi could not resolve and we took F6
    // instead (section 5). Said once, on the first press that could act, which
    // is the frame the player is asking "why F6?" - a log line alone is
    // invisible and the boot frame is not a place to raise a toast.
    if (_rt[$ "remote_key_fallback"] == true) {
        _rt.remote_key_fallback = undefined;
        create_notification(YADS_LOCAL_ROOT + "remote_key_bad", 60 * 4);
    }

    var _scan = yads_remote_scan();
    var _count = array_length(_scan.entries);

    // Nothing bound anywhere. Same answer on tap and on hold, so it is given
    // now rather than 400ms from now.
    if (_count <= 0) {
        _rt.remote_hold = undefined;
        create_notification(YADS_LOCAL_ROOT + "remote_none", 60 * 3);
        return;
    }

    // The arming predicate: a hold is armed exactly when tap and hold would
    // DIFFER, and that is every state with a network bound EXCEPT "several
    // networks, no default" - where the tap opens the picker on this very
    // frame, so waiting 400ms would buy the same surface later. Everywhere
    // else the hold is the ONLY route to the picker and to the Rebind button
    // in its footer, C == 1 included. See the derivation over this section for
    // the two predicates this one replaces and why each fell.
    if (!(_count == 1 || _scan.default_index >= 0)) {
        _rt.remote_hold = undefined;
        yads_remote_act(_rt, _scan, false);
        return;
    }

    // ARMED: nothing opens on this frame. frames starts at 0 and the poll that
    // runs immediately after this one in the same tick takes it to 1, so the
    // press frame is counted exactly once.
    //
    // THE WATCH CARRIES ITS OWN KEYCODE rather than re-reading _rt.remote_vk
    // per frame, and the rescue is why: its gesture runs on vk_f6 while the
    // remote key is something else, so one shared slot needs the key IN it.
    // Snapshotting is also the honest reading for the primary - the watch is
    // counting frames of the key that fired, which a live rebind mid-hold would
    // otherwise silently change underneath it.
    _rt.remote_hold = { frames: 0, vk: _rt.remote_vk, rescue: false };
}

// Is the key still down? Runs once per frame for as long as an armed press has
// not resolved, and for no frames at all otherwise.
//
// THE RAW READ CANNOT THROW HERE, and that is a derivation rather than a hope.
// The engine rejects a KeyCode it has no entry for, which is why mmapi wraps its
// own poll in a try/catch and retires the entry that failed
// (mmapi_hotkeys.gml payload:241-247). But this function only ever runs
// because a hotkey callback of ours fired, and BOTH of them are reached only
// from the line after a successful keyboard_check_pressed on the very code the watch
// then reads (mmapi_hotkeys.gml payload:240 -> :250) - so by the time we get
// here the
// engine has already accepted it this session. That is true of the rescue's
// vk_f6 exactly as it is of the primary's key, which is why one function serves
// both. keyboard_check and keyboard_check_pressed take the same KeyCode through
// the same conversion; the engine's own text driver reads both against one code
// in consecutive statements (Anchor.gml:489, :497). No try/catch, therefore, in
// a function that runs every frame of a hold.
//
// ONE SLOT, TWO GESTURES. _rt.remote_hold carries the keycode it is counting
// and whether it came from the rescue, so a rescue hold and a primary hold
// cannot both be live and cannot be confused for one another. The rescue arm
// differs in exactly one place: an early release resolves to NOTHING.
function yads_remote_hold_poll(_rt) {
    var _hold = _rt.remote_hold;
    var _vk = _hold[$ "vk"];
    if (_vk == undefined) {
        _rt.remote_hold = undefined;   // cannot have been armed; belt and braces
        return;
    }

    if (keyboard_check(_vk)) {
        _hold.frames += 1;
        if (_hold.frames < YADS_REMOTE_HOLD) { return; }

        // Threshold. Disarm FIRST so that nothing below can leave a watch
        // running against a menu it just opened, and re-scan rather than reuse
        // the press frame's list: 400ms is long enough to have walked into
        // another room, which changes the row order.
        _rt.remote_hold = undefined;
        if (!yads_remote_ready(_rt)) { return; }
        yads_remote_act(_rt, yads_remote_scan(), true);
        return;
    }

    // Released before the threshold.
    _rt.remote_hold = undefined;

    // THE RESCUE HAS NO TAP. F6 is insurance, not a second shortcut: a player
    // whose remote key is J must be able to press F6 by accident - or out of
    // muscle memory from before they rebound - without a menu appearing. Only
    // the deliberate 400ms produces the picker.
    if (_hold.rescue == true) { return; }

    // It was a tap after all.
    if (!yads_remote_ready(_rt)) { return; }
    yads_remote_act(_rt, yads_remote_scan(), false);
}

// Do the thing the gesture asked for. The caller has already proved
// yads_remote_ready; this only decides between the two surfaces.
function yads_remote_act(_rt, _scan, _want_picker) {
    var _count = array_length(_scan.entries);
    if (_count <= 0) {
        create_notification(YADS_LOCAL_ROOT + "remote_none", 60 * 3);
        return;
    }

    if (_want_picker) {
        yads_open_picker(_scan);
        return;
    }

    // The tap ladder: the valid default, else the only one, else the picker.
    var _index = _scan.default_index;
    if (_index < 0) {
        if (_count > 1) {
            yads_open_picker(_scan);
            return;
        }
        _index = 0;
    }

    yads_remote_view(_scan.entries[_index].node);
}

// Open one bound heart's network as a REMOTE view. The single place the two
// gestures and the picker's own row tap all converge, so "what a chosen network
// does" cannot drift between them.
//
// NO set_idle_simple() HERE, unlike the two interaction doors. That call exists
// to stop a player who walked into a unit mid-stride from sliding while the menu
// is up; a remote open happens wherever the player is standing, and the guard
// has already proved they are in Default or MountDefault, so there is no motion
// to cancel and nothing to interrupt.
//
// Opened REMOTE. See the note over yads_open_view's remote flag for what that
// turns off and why.
function yads_remote_view(_heart) {
    if (_heart == undefined) { return; }

    var _scan = yads_scan(_heart);
    if (array_length(_scan.members) <= 0) { return; }

    yads_open_view(_heart, _scan, true);
}

// The picker's row tap, applied from the tick one frame after the player made
// it. CLOSE FIRST, THEN OPEN, and the order is not a preference:
//
//   * AnchorMenu.close does not remove the menu from ANCHOR.open_menus. It sets
//     close_requested and (through a chain) free_requested, and the per-frame
//     drain at the head of Anchor.on_begin_step is what frees it and takes it
//     off the list (Anchor.gml:262-273). Our tick runs BEFORE that drain, so
//     the closing popup and the new Storage menu are both on open_menus for the
//     rest of this frame. That is harmless in itself - get_menu only asserts on
//     two menus of the SAME type (Anchor.gml:160-167) and these are Popup and
//     Storage - and PAUSE_STATUS survives it: the drain removes the popup's
//     MENU flag and then re-ORs the flag from every menu still open, which now
//     includes the view (:282-286).
//   * WHAT IS NOT HARMLESS IS THE POPUP'S THINK. PopupMenu's canvas think calls
//     INPUT.override_input on every InputId for as long as mutes_input holds
//     (PopupMenu.gml:305-309), and a merely-locked canvas keeps thinking - the
//     node loop gates on run_logic && safe_enabled and nothing else
//     (Anchor.gml:374). [popup] declares close_transition with
//     fade_out_frames = 10 (ui/menus/misc_menus.toml), so a plain close() would
//     leave the fresh view with ten frames of raw_status returning Off
//     (Input.gml:276) - clicks would still land, because the node walk reaches
//     the view's nodes before the popup's canvas, but MenuBack is taken after
//     the walk (:653-656) and ESC would do nothing for a sixth of a second.
//     yads_picker_close spends request_hide(0) to disable the canvas outright
//     instead; see the note there.
function yads_picker_choose(_rt, _picker) {
    var _index = _picker.choice;
    _picker.choice = undefined;

    var _entries = _picker[$ "entries"];
    if (_entries == undefined) { return; }
    if (_index < 0 || _index >= array_length(_entries)) { return; }

    var _heart = _entries[_index].node;

    yads_picker_close(_picker);

    // Re-proved rather than assumed: yads_remote_ready cannot be used here
    // because the popup this function just closed is still on open_menus, so
    // game_paused() is still true and will be for as long as the view is up.
    // The two clauses that still mean something are the two the view itself
    // needs.
    if (!instance_exists(obj_ari)) { return; }
    if (_rt.view != undefined) { return; }

    yads_remote_view(_heart);
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
    //
    // The picker is on the same line for the same reason yads_remote_ready
    // names it: a modal list of networks is not a state in which a crate should
    // open underneath. Unreachable in practice - the popup declares
    // pause = "main" - and kept because "no second surface while one of ours is
    // up" is the invariant this mod depends on rather than an implication of
    // someone else's flag.
    if (_rt.view != undefined) { return true; }
    if (_rt[$ "picker"] != undefined) { return true; }

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
        // THE LINK GESTURE, and it goes first in the heart's ladder - ahead of
        // the panel-less bail below - because handing a heart its remote is the
        // one thing that must work on a network with nothing else on it. The
        // remote IS a browsing surface; a player who crafted one before they
        // crafted an Access Panel would otherwise meet "craft an Access Panel"
        // while holding the thing that replaces it.
        //
        // Returns true either way once we know the held item is a remote: the
        // press was aimed at this heart with this item, and deferring to the
        // engine would open a plain chest UI on top of a gesture the player
        // meant as a handover.
        if (yads_link_remote(_ctx)) { return true; }

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
// 6b. THE LINK GESTURE
//
// Interacting with a Storage Heart while holding a Remote Access Panel hands
// the remote over. Returns TRUE when the gesture was ours (linked, or refused
// because the heart is full) and FALSE when the player was not holding a
// remote, in which case the ladder above carries on to the status popup.
//
// THIS IS THE ONE PLACE THE MOD MOVES A REAL ITEM OUTSIDE THE RECONCILER, so
// the custody order is written out rather than inferred:
//
//   1. PROVE ROOM FIRST. Inventory.add has no capacity test at all - it loops
//      on slot_for_item, which returns undefined for a full inventory, and then
//      dereferences it (Inventory.gml:65-74). can_add is room_for_item >= count
//      (Inventory.gml:93-96) and is the guard vanilla's own Throw predicate uses
//      before the same insertion (Furniture.gml:1257). A full heart therefore
//      costs a toast and nothing else: the remote never leaves the player.
//   2. ADD, THEN REMOVE. The vanilla transfer order, twice over
//      (StorageMenu.gml:483-485, InventoryMenu.gml:430-435): compute the
//      movable amount, put it in the destination, and only then take it out of
//      the source. Nothing in this engine is transactional, so the order
//      decides which way a mid-step failure falls - and "briefly in two places"
//      is recoverable while "briefly in none" is not.
//   3. EXACTLY ONE. slot.remove(1) rather than slot.drain(): a player carrying
//      three remotes for three hearts hands over one. (drain() also has an
//      inverted argument test, Inventory.gml:342 - never call it with a list.)
//
// CLONE, DO NOT ALIAS, and this is where we depart from Furniture.gml's Throw
// handler even though it is otherwise the model for this whole function. Throw
// DRAINS the whole stack (Furniture.gml:1245), so the source slot is empty
// afterwards and the struct it handed over has exactly one owner. We take one
// of possibly several, so the source stack can survive - and passing the live
// struct would leave the player's remaining remotes and the heart's new one
// sharing a single LiveItem across an inventory boundary. yads_deposit_fit
// already clones for precisely this reason. It is lossless here: clone()
// (LiveItem.gml:252-262) copies item_id, inner_item, cosmetic, animal_cosmetic,
// pet_cosmetic_set_name, gold_to_gain, infusion and date_photo - i.e. everything
// except auto_use and icon_override - and the remote can carry neither
// (auto_use is only ever set from an `auto_use` key in the item's fiddle entry,
// LiveItem.gml:374-375, and ours has none; icon_override is set for
// ItemId.MistHeldItem only, LiveItem.gml:137-140). That copy set is also a
// superset of every field partial_eq reads, which is what stops the clone from
// desyncing the can_add check below from the add that follows it.
//
function yads_link_remote(_node) {
    // held_item() is sugar for exactly this pair of reads (Ari.gml:446-448); we
    // take the slot itself because step 3 needs it. The bounds test is not
    // theoretical politeness: Inventory.slot goes through List.get, which
    // ASSERTS rather than returning undefined (List.gml:143-146), and a throw
    // in here is swallowed by mmapi_run_override and silently degrades to the
    // engine's own chest UI.
    var _backpack = ARI.inventory;
    var _index = ARI.held_item_index;
    if (_index < 0 || _index >= _backpack.size()) { return false; }

    var _slot = _backpack.slot(_index);
    if (_slot.count <= 0 || _slot.item == undefined) { return false; }
    if (!yads_is_remote(_slot.item)) { return false; }

    // Carrying an animal is its own held state. The vanilla handler this whole
    // function is modelled on - the chest Throw predicate - tests it before
    // acting (Furniture.gml:1257-1258), and so do the crafting stations, the
    // ladders and the stores. NOT every vanilla held-item handler does: the
    // furniture production hand-off (Furniture.gml:1175-1177) and the NPC
    // engagement-ring arm (par_NPC.gml:1343-1354) read ARI.held_item() with no
    // animal test at all. Ours checks because the gesture it guards is a
    // transfer into a chest, which is the same shape as the one handler that
    // does - conservative by choice, not by convention.
    if (ARI.held_animal_id != undefined) { return false; }

    var _inventory = _node[$ "inventory"];
    if (_inventory == undefined) { return false; }

    // Pass the LIVE ITEM, never its item_id: room_for_item mints a throwaway
    // LiveItem for a bare id and then partial_eq fails against anything with a
    // variant (Inventory.gml:353-358, and the unit test at :529-535 proves it).
    if (!_inventory.can_add(_slot.item, 1)) {
        create_notification(YADS_LOCAL_ROOT + "remote_heart_full", 60 * 3);
        return true;
    }

    _inventory.add(_slot.item.clone(), 1);
    _slot.remove(1);

    create_notification(YADS_LOCAL_ROOT + "remote_linked", 60 * 3);
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

    var _menu = _ctx[$ "menu"];
    if (_menu == undefined) { return; }

    // THE PICKER FIRST, and above the view's own early-out rather than beside
    // it: the two stamps are different fields on different menu types and a
    // picker can close on a frame when no view exists at all, which is in fact
    // the ordinary case (ESC on the list). Reading _rt.view first, as this
    // function did when there was only one stamp to find, would have skipped
    // the release entirely and wedged the hotkey behind yads_remote_ready's
    // picker clause until the next save load.
    //
    // Releasing is ALL there is to do. The picker owns no items, no inventory
    // and no reconciler, so unlike yads_teardown there is nothing to commit -
    // its nodes died with the canvas in AnchorMenu.free one statement before
    // this event was emitted.
    var _picker = _menu[$ "netstor_picker"];
    if (_picker != undefined) {
        _picker.closing = true;
        _picker.menu = undefined;
        // Structs compare by reference on this runtime (mmapi_local.gml:22-23),
        // so a stale popup can never clear a newer one's registration.
        if (_rt[$ "picker"] == _picker) { _rt.picker = undefined; }
        return;
    }

    if (_rt.view == undefined) { return; }
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
    _rt.picker = undefined;         // nor does the picker popup

    // A press held over from the save being replaced. The tick would otherwise
    // act on it against the new world: the hotkey poll has no room or load test
    // of its own, so a key pressed on the loading screen sets this flag and the
    // first tick of the new save would open somebody else's crate.
    //
    // The hold watch goes for the same reason and one more of its own: it names
    // frames counted against a world that no longer exists, and a key still
    // held across the load would otherwise resolve into the new save as a
    // gesture nobody made there.
    //
    // remote_vk, remote_entry and rescue_installed deliberately STAY. They are
    // the BINDING, which is per PROCESS and not per save: the registry entry
    // this mod holds a reference to lives in a global mmapi never empties, and
    // the config file the key came from is per install. Clearing them here
    // would leave a live registration nothing points at - the one state from
    // which a rebind could not repair itself. Same reasoning as the
    // hotkeys_installed latch they were stored beside.
    _rt.remote_pending = undefined;
    _rt.remote_hold = undefined;

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
