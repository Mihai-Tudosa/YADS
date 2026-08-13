// YADS - the network layer: id resolution, the flood-fill scan, the
// aggregate index, the projection onto the mirror inventory, and the
// write-through reconciler.
//
// Definitions only. Nothing in this file executes at boot.
//
// CUSTODY RULE, stated once and honoured everywhere below:
//   The member chests' node.inventory objects are the ONLY custodians of real
//   items. The 54-slot mirror is a rendering of them. Every function here either
//   reads the members to build the mirror (index/projection) or reads the mirror
//   to correct the members (reconciler). Nothing ever "lives" in the mirror.

//
// 1. RUNTIME ID RESOLUTION
//
// ObjectId and ItemId are minted from the merged fiddle tables at load
// (magic_enums.meta.toml), they are sorted alphabetically, and they renumber
// whenever the installed content set changes. Writing ObjectId.NetstorHeart in
// mod GML compiles - the dialect late-binds - and then fails in game. So: resolve
// by string, memoize for the session, and throw the memo away on save.game_loaded.
//
function yads_ids() {
    var _rt = yads_runtime();
    if (_rt.ids != undefined) { return _rt.ids; }

    // try_ variants return undefined for an unknown key, which is exactly what
    // we want if only part of the content installed.
    //
    // remote_item IS SPELLED DIFFERENTLY BECAUSE IT IS A DIFFERENT KIND OF
    // NUMBER. The other three are ObjectIds - grid nodes, compared against
    // node.object_id. The remote is not placeable and has no prototype, so it
    // only ever exists as an ItemId, compared against live_item.item_id. Both
    // enums are minted per load and both renumber, so both belong in this memo
    // and both die on save.game_loaded; the name is what stops a future reader
    // from testing an ItemId against a node.
    _rt.ids = {
        heart: try_string_to_object_id("netstor_heart"),
        block: try_string_to_object_id("netstor_block"),
        panel: try_string_to_object_id("netstor_panel"),
        remote_item: try_string_to_item_id("netstor_remote"),
    };
    return _rt.ids;
}

// Is this live item a Remote Access Panel? One struct read and one compare, and
// the single place the mod asks that question - the quick-stack skip, the
// deposit refusal, the binding scan and the link gesture all route through it,
// so "what counts as a remote" cannot drift between them.
//
// undefined _ids.remote_item means the item did not install (a partial content
// set), and then NOTHING is a remote: every guard fails open to the pre-1.2
// behaviour rather than matching an undefined against an item_id.
function yads_is_remote(_item) {
    if (_item == undefined) { return false; }
    var _remote = yads_ids().remote_item;
    if (_remote == undefined) { return false; }
    return _item.item_id == _remote;
}

// Is this node one of ours? Used as the flood-fill predicate.
function yads_is_member(_node) {
    if (_node == undefined) { return false; }

    var _object_id = _node[$ "object_id"];
    if (_object_id == undefined) { return false; }

    var _ids = yads_ids();
    return (_ids.heart != undefined && _object_id == _ids.heart)
        || (_ids.block != undefined && _object_id == _ids.block)
        || (_ids.panel != undefined && _object_id == _ids.panel);
}

//
// 2. NETWORK SCAN (breadth-first, footprint ring)
//
// Adjacency is "our footprints share an orthogonal grid edge". Only the ring of
// cells immediately outside a footprint can touch anything outside it, so we
// walk that ring instead of the interior or the whole board - O(perimeter) per
// node. The ring never visits the four diagonal corners, which is what makes the
// relation orthogonal-only rather than "touching at a corner counts".
//
// Two rules that are easy to get wrong:
//   * footprint comes from write_size_x/write_size_y on the NODE, never
//     prototype.size - a rotated object swaps them (Furniture.gml:2028-2035);
//   * a network never leaves its Grid. Every location has its own Grid struct
//     and crossing them has no spatial meaning, so we compare parent_grid by
//     reference on every neighbour.
//
// Returns { members: [node...], deposit_targets: [node...], hearts: n,
// panels: n, grid: <Grid> }.
//
// MEMBERS are every node on the network that carries an inventory - all three of
// ours do, but the check is there so a future memberless unit cannot crash the
// index. Members are what the aggregate index reads and what withdrawals drain:
// everything the network holds is visible and retrievable, wherever it sits.
//
// DEPOSIT_TARGETS are the blocks, and only the blocks. Storage capacity is the
// block's job, so nothing the mod does ever pushes an item into a heart or a
// panel. Built here, in the same BFS pass, so that "who can receive a deposit"
// is one named piece of scan output rather than the same object_id test repeated
// in three hot loops that could drift apart.
//
// PANELS is the count of Access Panels, for the same reason and by the same rule:
// "does this network have a browsing surface at all" is a question TWO surfaces
// ask - the interaction ladder, to decide whether sealing a block would strand
// its contents, and the heart's status popup, to decide whether to print the
// "craft an Access Panel" pointer. Both read this one number rather than walking
// the member list twice; two independent walks of one list are two things that
// can drift apart.
//
function yads_scan(_start) {
    var _result = { members: [], deposit_targets: [], hearts: 0, panels: 0, grid: undefined };

    var _grid = _start[$ "parent_grid"];
    if (_grid == undefined) { return _result; }
    _result.grid = _grid;

    var _ids = yads_ids();

    // Visited is keyed by the neighbour's ANCHOR cell, because a long shared edge
    // resolves to the same node_parent struct at several ring cells.
    var _visited = array_create(_grid.node_len, false);
    _visited[_grid.node_index_for_cell(_start.top_left_x, _start.top_left_y)] = true;

    // Plain growable array + read cursor. This codebase uses no ds_queue anywhere.
    var _frontier = [_start];
    var _head = 0;

    while (_head < array_length(_frontier)) {
        var _current = _frontier[_head];
        _head += 1;

        if (_ids.heart != undefined && _current.object_id == _ids.heart) {
            _result.hearts += 1;
        }
        if (_current[$ "inventory"] != undefined) {
            array_push(_result.members, _current);
            if (_ids.block != undefined && _current.object_id == _ids.block) {
                array_push(_result.deposit_targets, _current);
            }
            // Counted inside the members branch, not beside it, so this number
            // is exactly "panels a walk of _members would have found".
            if (_ids.panel != undefined && _current.object_id == _ids.panel) {
                _result.panels += 1;
            }
        }

        var _x0 = _current.top_left_x;
        var _y0 = _current.top_left_y;
        var _w = _current.write_size_x;
        var _h = _current.write_size_y;

        for (var _i = 0; _i < _w; _i++) {
            yads_scan_probe(_grid, _x0 + _i, _y0 - 1, _visited, _frontier);
            yads_scan_probe(_grid, _x0 + _i, _y0 + _h, _visited, _frontier);
        }
        for (var _j = 0; _j < _h; _j++) {
            yads_scan_probe(_grid, _x0 - 1, _y0 + _j, _visited, _frontier);
            yads_scan_probe(_grid, _x0 + _w, _y0 + _j, _visited, _frontier);
        }
    }

    return _result;
}

function yads_scan_probe(_grid, _tx, _ty, _visited, _frontier) {
    var _ni = _grid.try_node_index_for_cell(_tx, _ty);
    if (_ni == undefined) { return; }                        // off the grid
    if (_grid.node_object_id[_ni] == undefined) { return; }  // empty cell

    var _neighbor = _grid.node_parent[_ni];
    if (_neighbor == undefined) { return; }
    if (_neighbor[$ "parent_grid"] != _grid) { return; }     // never bridge grids
    if (!yads_is_member(_neighbor)) { return; }

    var _anchor = _grid.node_index_for_cell(_neighbor.top_left_x, _neighbor.top_left_y);
    if (_visited[_anchor]) { return; }

    _visited[_anchor] = true;
    array_push(_frontier, _neighbor);
}

//
// 3. AGGREGATION KEY
//
// Two stacks merge in a chest exactly when LiveItem.partial_eq holds
// (LiveItem.gml:44-66), so the display grouping uses the same tuple. Anything
// that blocks stacking - an infusion, an inner item, a purse value, a cosmetic,
// a date photo - correctly shows up as its own row.
//
function yads_agg_key(_item) {
    var _key = string(_item.item_id)
        + "|" + string(_item.infusion)
        + "|" + string(_item.inner_item)
        + "|" + string(_item.gold_to_gain)
        + "|" + string(_item.cosmetic)
        + "|" + string(_item.pet_cosmetic_set_name)
        + "|" + string(_item.date_photo);

    var _animal = _item[$ "animal_cosmetic"];
    if (_animal == undefined) { return _key + "|-"; }
    return _key + "|" + string(_animal[$ "animal"]) + ":" + string(_animal[$ "cosmetic"]);
}

//
// 4. SORT BUCKETS
//
// There is no category field on an item prototype anywhere in the data; every
// classification in this game is tag-driven plus the derived prototype.use. This
// is the 14-bucket taxonomy, first match wins, ordered so the things a player
// withdraws sit above the 1456-item furniture blob.
//
// Vanilla Inventory.sort() is deliberately NOT reused: it keys on the ItemUse
// ordinal, which files every raw material into one undifferentiated bucket at
// the very end - fine for a 30-slot chest, useless for a network.
//
// ItemUse is declared as text in Items.gml:611, so its members are safe to name;
// ItemId/ObjectId are not, which is why nothing here mentions one.
//
function yads_category(_item_id) {
    var _rt = yads_runtime();
    if (_rt.categories == undefined) { _rt.categories = array_create(0); }

    // The cache stores cat+1, so that the 0 array_resize pads new entries with
    // reads as "not computed yet" instead of as bucket 0.
    var _cache = _rt.categories;
    if (_item_id < array_length(_cache)) {
        var _cached = _cache[_item_id];
        if (is_real(_cached) && _cached > 0) { return _cached - 1; }
    }

    var _proto = ITEM_PROTOTYPES[_item_id];
    var _tags = _proto.tags;
    var _cat;

    if (_proto.tool_type != undefined || _tags.contains("tool")) {
        _cat = 0;   // Tools
    } else if (_tags.contains("weapon") || _tags.contains("sword")
            || _tags.contains("armor") || _tags.contains("accessory")) {
        _cat = 1;   // Weapons and armour
    } else if (_proto.use == ItemUse.PlantSeed || _proto.use == ItemUse.PlantSapling
            || _tags.contains("seed")) {
        _cat = 2;   // Seeds and saplings
    } else if (_tags.contains("crop") || _tags.contains("forageable")
            || _tags.contains("mines_forageable") || _tags.contains("flower")
            || _tags.contains("mushroom") || _tags.contains("berry")) {
        _cat = 3;   // Crops and forage
    } else if (_tags.contains("fishy") || _tags.contains("fishable") || _tags.contains("bugs")) {
        _cat = 4;   // Fish and bugs
    } else if (_tags.contains("animal_product") || _tags.contains("animal_harvest")
            || _tags.contains("animal_fibre") || _tags.contains("ranching")
            || _tags.contains("egg")) {
        _cat = 5;   // Animal products
    } else if (_tags.contains("food") || _tags.contains("drink") || _proto.use == ItemUse.Consume) {
        _cat = 6;   // Food and drink
    } else if (_tags.contains("ore") || _tags.contains("gem")
            || _tags.contains("ingot") || _tags.contains("essence_stone")) {
        _cat = 7;   // Ores, gems, ingots
    } else if (_tags.contains("material") || _tags.contains("refined_material")
            || _tags.contains("refined_ore") || _tags.contains("monster_part")
            || _tags.contains("animal_feed") || _tags.contains("junk")) {
        _cat = 8;   // Materials
    } else if (_tags.contains("archaeology") || _tags.contains("replica")) {
        _cat = 9;   // Artifacts and replicas
    } else if (_tags.contains("furniture")) {
        _cat = 10;  // Furniture and decor
    } else if (_proto.use == ItemUse.Wallpaper || _proto.use == ItemUse.Flooring
            || _proto.use == ItemUse.PlaceTile) {
        _cat = 11;  // Flooring and wallpaper
    } else if (_tags.contains("scroll")
            || matches(_proto.use, ItemUse.LearnRecipe, ItemUse.UnlockCosmetic,
                       ItemUse.UnlockAnimalCosmetic, ItemUse.UnlockPetCosmetic,
                       ItemUse.UnlockPetSkin, ItemUse.UnlockSong, ItemUse.UnlockDate,
                       ItemUse.ExpandInventory)) {
        _cat = 12;  // Scrolls and unlocks
    } else {
        _cat = 13;  // Everything else
    }

    if (_item_id >= array_length(_cache)) { array_resize(_cache, _item_id + 1); }
    _cache[_item_id] = _cat + 1;
    return _cat;
}

//
// 5. AGGREGATE INDEX
//
// One pass over every member slot, grouped by partial_eq key. The row keeps a
// TEMPLATE reference to one of the real LiveItem structs - never a copy. Sharing
// a LiveItem between inventories is exactly what the vanilla stack button does
// (StorageMenu.gml:475-489), and nothing in this mod ever mutates a live item,
// so the aliasing is safe. Deposits clone, because those really do move.
//
// Rebuilt only when the members actually changed - a page flip, a search
// keystroke or a sort change re-derives the projection from this cached index.
//
function yads_index_build(_view) {
    var _rows = [];
    var _seen = {};

    // Totals read ALL members - the heart's contents are as browsable and as
    // withdrawable as anything else, they simply stopped being a deposit target.
    var _members = _view.members;
    for (var _m = 0; _m < array_length(_members); _m++) {
        var _inventory = _members[_m][$ "inventory"];
        if (_inventory == undefined) { continue; }

        var _size = _inventory.size();
        for (var _i = 0; _i < _size; _i++) {
            var _slot = _inventory.slot(_i);

            // count == 0 and item == undefined are the same state; the invariant
            // is maintained by InventorySlot.remove.
            if (_slot.count == 0 || _slot.item == undefined) { continue; }

            var _item = _slot.item;
            var _key = yads_agg_key(_item);
            var _at = _seen[$ _key];

            if (_at == undefined) {
                _at = array_length(_rows);
                _seen[$ _key] = _at;

                var _name = yads_row_name(_view, _key, _item);
                array_push(_rows, {
                    key: _key,
                    item: _item,
                    total: 0,
                    name: _name,
                    lower_name: string_lower(_name),
                    cat: yads_category(_item.item_id),
                    // Resolved to a plain number at load (Items.gml:408-412), so
                    // sorting on it costs nothing. bin_value() would re-run perk
                    // lookups per comparison.
                    value: _item.prototype.value.bin,
                    // max_stack is 999 for everything except tools, weapons,
                    // identify items, chest-openers and armor, which are 1.
                    stack: max(1, _item.prototype.max_stack),
                });
            }

            _rows[_at].total += _slot.count;
        }
    }

    _view.rows = _rows;
    _view.has_room = yads_has_room(_view);
    _view.index_dirty = false;
}

// Is there an empty slot anywhere a deposit could actually land? Computed over
// DEPOSIT_TARGETS, never over members: this drives the dimming of the trailing
// mirror slots, and a heart or panel with a free slot would otherwise light the
// grid up as "room here" for a deposit that has nowhere to go but back into the
// player's hands with a "network full" toast. The two must agree or the UI lies.
//
// Partial-stack headroom is deliberately not counted, exactly as before: the
// dimming is a hint about empty slots, and making it depend on which items are
// on the visible page would make it flicker.
function yads_has_room(_view) {
    var _targets = _view.deposit_targets;

    for (var _m = 0; _m < array_length(_targets); _m++) {
        var _inventory = _targets[_m][$ "inventory"];
        if (_inventory == undefined) { continue; }

        var _size = _inventory.size();
        for (var _i = 0; _i < _size; _i++) {
            var _slot = _inventory.slot(_i);
            if (_slot.count == 0 || _slot.item == undefined) { return true; }
        }
    }

    return false;
}

// get_display_name() costs one or two native local_get calls plus a possible
// fmt, so it is memoized per aggregation key for the life of the view.
function yads_row_name(_view, _key, _item) {
    var _cached = _view.names[$ _key];
    if (_cached != undefined) { return _cached; }

    var _name = _item.get_display_name();
    if (!is_string(_name)) { _name = string(_name); }

    _view.names[$ _key] = _name;
    return _name;
}

//
// 6. COMPARATORS
//
// Fed to array_sort, which is what List.sort_with uses under the hood. All four
// tie-break on the display name through the same native comparison the vanilla
// inventory sort uses, so equal-looking rows never jitter between projections.
//
function yads_cmp_category(_a, _b) {
    if (_a.cat != _b.cat) { return sign(_a.cat - _b.cat); }
    return string_alphanumeric_comparison(_a.name, _b.name);
}

function yads_cmp_name(_a, _b) {
    return string_alphanumeric_comparison(_a.name, _b.name);
}

function yads_cmp_value(_a, _b) {
    if (_a.value != _b.value) { return sign(_b.value - _a.value); }   // dearest first
    return string_alphanumeric_comparison(_a.name, _b.name);
}

// What the whole pile is worth, dearest pile first. The unit sort above answers
// "what is one of these worth"; this one answers "where is the money", which on
// a network holding thousands of items is a different question with a different
// answer - it ranks 900 wood over one gold bar, and that is the point.
//
// The product is computed per comparison rather than cached as a third field on
// the row. Both operands are plain numbers already sitting on the struct, so the
// multiply is cheaper than the cache line it would take to avoid it, and a
// cached product is one more thing index_build has to keep in step with `total`
// - which every deposit changes.
//
// value is the row's cached prototype number, exactly like cmp_value's, NOT
// bin_value(): sorting must not re-run perk lookups per comparison. The badges
// deliberately disagree (see yads_badge_slot) because they
// are read one at a time against a tooltip, not thousands at a time against
// each other.
function yads_cmp_stack_value(_a, _b) {
    var _a_worth = _a.value * _a.total;
    var _b_worth = _b.value * _b.total;
    if (_a_worth != _b_worth) { return sign(_b_worth - _a_worth); }
    return string_alphanumeric_comparison(_a.name, _b.name);
}

function yads_cmp_count(_a, _b) {
    if (_a.total != _b.total) { return sign(_b.total - _a.total); }   // biggest pile first
    return string_alphanumeric_comparison(_a.name, _b.name);
}

// Does a sort bucket belong to a filter group? The answer is trivial, and that
// is the point: group 0 is All, groups 1..14 are the sort buckets ONE FOR ONE,
// and group 15 is the museum lens, which is not a bucket at all and never
// reaches this function. Any coarser grouping would mean two taxonomies to keep
// in step and buttons whose label does not match what they sweep up.
//
// Kept as its own named predicate rather than inlined into the projection so the
// mapping is stated in exactly one place - the icon table and the tooltip table
// in view.gml both index the same group numbers.
function yads_filter_match(_group, _cat) {
    if (_group <= YADS_FILTER_ALL) { return true; }
    if (_group >= YADS_FILTER_MUSEUM) { return true; }
    return (_cat == _group - 1);
}

// The museum lens: "this item is exhibitable AND has not been donated yet".
//
// Written exactly the way the game writes it, three times, verbatim:
// MuseumDonationMenu.gml:5-8 (the basket's per-item cap), Requirements.gml:640-643
// (the CompletedMuseum achievement) and TestSuite.gml:4451. Both operands are
// plain bool arrays indexed by item_id - MUSEUM_DATA.museum_items is built once by
// museum_parse_sets and assigned at Setup.gml:172, MUSEUM_PROGRESS is allocated at
// Game.gml:19 - so the whole predicate is two array reads.
//
// NOT MEMOIZED, on purpose. The mod caches sort buckets because
// ITEM_PROTOTYPES[i].tags.contains(...) is a dozen Map lookups; two array indices
// are not in that class, and a memo would buy one index in exchange for an
// invalidation contract and a staleness bug (donate at the museum, open the panel,
// the filter lies). It is also unnecessary: museum_items is frozen after Setup,
// MUSEUM_PROGRESS is monotonic within a session, and its only in-play writer - the
// donation basket, MuseumDonationMenu.gml:32-48 - is itself a Menu.Storage that
// closes itself on the donating tap and therefore cannot coexist with this view.
//
// Bounds-guarded on every hop even though the engine's own call sites are not. A
// mod item whose id sits past the end of an array sized before the fiddle merge
// must read as "not exhibitable", never fault: this runs inside a projection that
// runs inside a think, where a throw is uncaught and repeats every frame.
function yads_museum_needed(_item_id) {
    var _data = MUSEUM_DATA;
    if (_data == undefined) { return false; }

    var _eligible = _data[$ "museum_items"];
    if (_eligible == undefined) { return false; }
    if (_item_id < 0 || _item_id >= array_length(_eligible)) { return false; }
    if (!_eligible[_item_id]) { return false; }

    var _done = MUSEUM_PROGRESS;
    if (_done == undefined) { return true; }
    if (_item_id >= array_length(_done)) { return true; }
    return !_done[_item_id];
}

//
// 7. PROJECTION
//
// index -> filter -> sort -> split into stacks -> one page -> the 54 slots.
//
// Slots are written the way vanilla's own Inventory.sort() writes them: assign
// item and count directly and bump `updates`, which is what InventorySubscriber
// watches and what makes InventoryMenu repaint the square
// (Inventory.gml:267-273, InventoryMenu.gml:19-54).
//
// The last statement snapshots the shadow, so a projection is always
// self-consistent with the reconciler that runs after it.
//
function yads_project(_view) {
    if (_view.index_dirty == true) { yads_index_build(_view); }

    // 7a. Filter: category group AND case-insensitive substring of the display
    //     name. Both run here, before paging, because the page count is derived
    //     from what survives - filtering after the split would produce a "Page
    //     1 / 7" that no arrow could ever reach the end of.
    var _rows = _view.rows;
    var _query = _view.query;
    var _filter = _view.filter;
    //
    //     The museum lens is a filter GROUP rather than a second toggle, so it
    //     stays single-select with the categories and costs the bar no extra
    //     control. It cannot go through filter_match, which only sees a sort
    //     bucket: "does the museum still want this" is a property of the item id.
    var _museum = (_filter == YADS_FILTER_MUSEUM);
    var _matched = [];
    for (var _i = 0; _i < array_length(_rows); _i++) {
        var _row = _rows[_i];
        if (_museum) {
            if (!yads_museum_needed(_row.item.item_id)) { continue; }
        } else if (_filter != YADS_FILTER_ALL
            && !yads_filter_match(_filter, _row.cat)) { continue; }
        if (_query != "" && string_pos(_query, _row.lower_name) == 0) { continue; }
        array_push(_matched, _row);
    }

    // 7b. Sort.
    switch (_view.sort_mode) {
        case YADS_SORT_NAME:
            array_sort(_matched, yads_cmp_name);
            break;
        case YADS_SORT_VALUE:
            array_sort(_matched, yads_cmp_value);
            break;
        case YADS_SORT_STACK_VALUE:
            array_sort(_matched, yads_cmp_stack_value);
            break;
        case YADS_SORT_COUNT:
            array_sort(_matched, yads_cmp_count);
            break;
        default:
            array_sort(_matched, yads_cmp_category);
            break;
    }

    // 7c. Split every row into displayable stacks. A slot count above max_stack
    //     would make InventorySlot.room_for_item return a NEGATIVE number, and
    //     InventoryMenu's PutDown feeds that straight into slot.add - which would
    //     quietly subtract items. Never write a count above the stack size.
    //
    //     WE never write one. The ENGINE can, and does: a gamepad PickUpOne takes
    //     the `secondary_behavior` branch, whose amount is the literal 1 with NO
    //     room check (InventoryMenu.gml:417-421), so hovering a mirror cell that
    //     already holds a full stack of the item in hand and pressing it pushes
    //     that cell to max_stack + 1 for one frame. The invariant is restored by
    //     TICK ORDERING, not by the write path: reconcile runs before project at
    //     every call site and reconcile always dirties the projection when it
    //     moved anything (boot.gml:576 then :662-663), so a reconcile ->
    //     project pair is guaranteed between any two of InventoryMenu's
    //     input_check frames. The over-stack is diffed out as a real deposit and
    //     the row is re-split here at min(_left, stack) before the engine can read
    //     a negative room_for_item back. Proven absorbed - recorded so that nobody
    //     "hardens" the split loop against a state it is already the cure for.
    var _cells = [];
    for (var _i = 0; _i < array_length(_matched); _i++) {
        var _row = _matched[_i];
        var _left = _row.total;
        while (_left > 0) {
            var _take = min(_left, _row.stack);
            array_push(_cells, { item: _row.item, count: _take });
            _left -= _take;
        }
    }

    // 7d. Paging.
    var _cell_count = array_length(_cells);
    _view.pages = max(1, ceil(_cell_count / YADS_PAGE_CELLS));
    _view.page = clamp(_view.page, 0, _view.pages - 1);
    var _base = _view.page * YADS_PAGE_CELLS;

    // 7e. Write the mirror.
    //
    //     Every slot stays deposit-open (empty required_tags). The earlier
    //     design shut the empties with a sentinel tag while no member slot was
    //     free, and verification killed it twice over: ESC-drop pops the held
    //     stack ONE UNIT AT A TIME when can_add says no (InventoryMenu.gml:
    //     101-118 -> drop_item, one instance + one List per unit - a 999-item
    //     hand froze the frame), and "no fully empty member slot" ignores
    //     partial-stack headroom, so deposit legality changed with the visible
    //     page. Open slots make every deposit succeed into the mirror; the
    //     reconciler then fits what the members can take and hands the honest
    //     remainder back through ARI.give_item (drop_item_stack: ONE instance
    //     for the whole overflow) plus a "network full" toast. The dimming
    //     below stays as a hint that no member slot is empty.
    var _inventory = _view.inv;

    // The squares only exist once the menu is built; every use of them below is
    // guarded so a projection can also run on a view whose menu has gone.
    var _squares = undefined;
    if (_view.menu != undefined) {
        var _left_menu = _view.menu[$ "left_menu"];
        if (_left_menu != undefined) { _squares = _left_menu[$ "slots"]; }
    }

    for (var _s = 0; _s < YADS_VIEW_SIZE; _s++) {
        var _slot = _inventory.slot(_s);

        var _cell = undefined;
        if (_s < YADS_PAGE_CELLS && (_base + _s) < _cell_count) {
            _cell = _cells[_base + _s];
        }

        if (_cell == undefined) {
            yads_write_slot(_slot, undefined, 0);
            yads_shade_square(_squares, _s, _view.has_room ? 1 : 0.45);
            // The engine cannot clear this one for us - refresh_slot returns at
            // count == 0 before it reaches the board - and a stale lock on an
            // empty cell refuses the deposit the empty cell exists to invite.
            yads_soft_lock_square(_squares, _s, false);
        } else {
            yads_write_slot(_slot, _cell.item, _cell.count);
            yads_shade_square(_squares, _s, 1);
            // The one cell a player may read and not touch, and only through the
            // remote. In a LOCAL view this is skipped and withdrawing the remote
            // unlinks the network, exactly as it always has. Never written false
            // here: that is vanilla's clause to write, not ours.
            if (_view.remote == true && yads_is_remote(_cell.item)) {
                yads_soft_lock_square(_squares, _s, true);
            }
        }

        // Value badges, written from the same loop and from the same _cell that
        // just went into the slot - there is no second source of truth for them
        // to drift from. This is also the only place they are written: a
        // per-badge think would run 45 times a frame forever, re-deriving
        // slot.item and re-running bin_value() to discover that nothing moved,
        // whereas project() runs only when something actually changed.
        yads_badge_slot(_view, _s, _cell);
    }

    // 7f. Re-baseline. Read back from the slots rather than trusting what we
    //     meant to write; the slots are the thing the reconciler will diff.
    //     The updates-sum baseline moves with it so our own writes do not
    //     trip the reconciler's change detector next frame.
    _view.shadow = yads_view_totals(_view);
    _view.updates_sum = yads_updates_sum(_inventory);
    _view.project_dirty = false;

    if (_view.page_text != undefined) {
        _view.page_text.set_text(yads_page_label(_view.page, _view.pages));
    }
}

// Fetch a format pattern for a string we build ourselves.
//
// Mod GML is installed outside the tree the installer rewrites local_get( ->
// mmapi_local_get( over, so a bare local_get() in this file reaches the NATIVE:
// no local.missing filter, no local.get filter, and a missing key comes back in
// one of three shapes - undefined, the key echoed straight back, or the literal
// "MISSING". The old `!is_string` guard only caught the first, so a key that
// failed to install would have rendered "mods/yads/ui/page_label" in
// the UI. mmapi_local_get is the public payload entry to the same waist the
// engine's own calls go through, and the widened test below turns all three miss
// shapes into the caller's hard-coded English.
//
// set_key() call sites need none of this: TextNode.set_key calls local_get from
// ENGINE code (Node.gml:1013), which is inside the rewrite.
function yads_pattern(_key, _fallback) {
    var _text = mmapi_local_get(_key);
    if (!is_string(_text) || _text == _key || _text == "MISSING") { return _fallback; }
    return _text;
}

// "1 / 4", localized. The ui.toml entry carries two {} placeholders; the
// engine's own idiom for that shape is format(local_get(key), args...)
// (CalendarMenu.gml:274).
//
// The hard-coded fallback must stay in step with ui.toml's own value. It is
// what renders when the key did not install, and a fallback wider than the pager
// cluster would overrun the arrows in exactly the case where nothing else is
// working either. See the layout comment over the pager.
function yads_page_label(_page, _pages) {
    var _pattern = yads_pattern(
        YADS_LOCAL_ROOT + "page_label", "{} / {}");
    return format(_pattern, string(_page + 1), string(_pages));
}

// Direct slot write, skipped when nothing actually changed - an unchanged slot
// keeps its `updates` counter, which keeps InventoryMenu from replaying the
// elastic pop-in animation and the put-down sound on every projection.
function yads_write_slot(_slot, _item, _count) {
    var _same = (_slot.count == _count)
        && ((_count == 0) || (_slot.item != undefined && _slot.item.partial_eq(_item)));
    if (_same) { return; }

    _slot.item = (_count == 0) ? undefined : _item;
    _slot.count = _count;
    _slot.updates += 1;
}

// Dim the squares that cannot take a deposit. The square's own think callback
// only ever reassigns its sprite, so an alpha set from here survives.
function yads_shade_square(_squares, _index, _alpha) {
    if (_squares == undefined) { return; }
    if (_index >= array_length(_squares)) { return; }

    var _square = _squares[_index].square;
    if (_square.get_alpha() == _alpha) { return; }
    _square.set_alpha(_alpha);
}

// THE MIRROR'S ONE READ-ONLY CELL: the bound remote, seen through that remote.
//
// YOU CANNOT UNPLUG THE ANTENNA THROUGH THE ANTENNA. Withdrawing the remote from
// a network view is the unlink gesture, and at the Access Panel that is exactly
// what it should be. Through the REMOTE it is a trap with no way back: the
// binding is gone, yads_deposit_fit refuses to let a remote back into the
// network (H2), and the surface the player would repair it from is the surface
// that just closed. One misclick at the bottom of the mines would cost the walk
// home. So in a remote view the cell is visible, inspectable, and inert.
//
// InventoryMenu has exactly one seam for that, and it is a constructor argument
// no vanilla call site passes and the mod cannot reach - StorageMenu builds both
// InventoryMenus itself (StorageMenu.gml:29-30). So we assign the field the
// constructor would have set (InventoryMenu.gml:2, :502) after build(), which is
// the same post-build dressing the two banner buttons already get. refresh_slot
// then calls it for every slot it repaints and ORs the answer into `soft_lock`
// (:180-182), and that one flag does three things at once:
//
//   * the square's think takes the soft_locked branch INSTEAD OF input_check
//     (:253-260). input_check is the sole entry to PickUp, PutDown and Transfer
//     and to every gamepad variant of the three (:315-437), so BOTH DIRECTIONS
//     DIE TOGETHER - which is the requirement, because a PutDown onto an
//     occupied cell is a SWAP (:406-411) and would have carried the remote out
//     just as surely as a click on it;
//   * ANCHOR.take_tap() eats the press and plays UIUnableToInteract (:255-258),
//     so the refusal has a voice and the press cannot fall through to anything
//     else. That is the whole of the click feedback and it is free; detecting
//     the attempt ourselves to raise a toast would need a listener of our own
//     over the grid, which is the one thing anchor-ui-facts forbids;
//   * the icon draws at half alpha (:186) - the game's own "you cannot take
//     this" idiom, already on screen in this very menu whenever the backpack is
//     full. The square art does not change: spr_ui_inventory_slot ships no
//     _hovered_untappable frame, so anchor_utils.gml:2517 falls the key back to
//     the ordinary hovered sprite. Vanilla's own soft-locked storage cells look
//     the same; nothing here is a new visual language.
//
// The pilot is untouched: soft_lock writes a blackboard entry and an alpha and
// never `unlocked` or `enabled`, and Pilot.position_is_valid reads safe_unlocked
// alone - so the cell stays navigable-but-inert rather than becoming the dead
// stop a set_enabled(false) would have made of it (anchor-ui-facts).
//
// A PREDICATE ON THE ITEM, NEVER ON THE CELL INDEX, and that is what makes the
// 45 recycled cells safe: refresh_slot re-derives the flag from whatever the
// cell holds NOW, so the page flip that puts iron ore where the remote was
// clears the lock with no bookkeeping of ours. The one hole it leaves - a cell
// emptied rather than refilled - is closed by yads_soft_lock_square below.
//
// Installed on a remote view's left menu ONLY, which is why this reads no view
// handle and no global: a local view never has one, and its cells behave exactly
// as they did before. A bare function reference in a struct field, invoked as
// `self.filter_callback(slot)`, is the same shape mmapi's own hotkey registry
// runs our callbacks through (mmapi_hotkeys.gml payload:250, `entry.callback()`).
function yads_remote_slot_filter(_slot) {
    return !yads_is_remote(_slot.item);
}

// Assert a square's soft-lock flag from the projection, one walk AHEAD of the
// engine's own re-derive.
//
// WHY THIS EXISTS, given the filter above is the steady-state truth. refresh_slot
// runs from the InventoryMenu CANVAS's think (InventoryMenu.gml:19-29, :209-211),
// and the node walk is reverse registration order (Anchor.gml:370) - the canvas
// is created before its squares (:205, :224-236), so it is visited AFTER all 45
// of them. Our tick runs above the entire walk. A cell we repaint is therefore
// read by this frame's square thinks and only re-derived at the end of the same
// frame, so the remote would be live for exactly one frame every time it landed
// in a cell that was something else before. Writing the flag WITH the item
// closes that gap; the engine's re-derive later in the frame agrees with it.
//
// ONLY EVER TRUE, EXCEPT ON A CELL WE JUST EMPTIED. refresh_slot ORs a second
// clause we do not own - "the backpack cannot take this" (:174-177), which is on
// screen for every mirror cell whenever ARI is full - so writing false onto an
// OCCUPIED cell would unlock a cell vanilla means to be locked. An emptied cell
// carries no such clause: refresh_slot RETURNS at count == 0 before it touches
// the board (:164-168), so nothing but us can write that cell's flag. Clearing
// it there is mandatory rather than tidy - the flag would otherwise outlive the
// item it described and leave a phantom cell that refuses deposits into a slot
// the mirror is advertising as free.
//
// Written unguarded by a read-back, unlike yads_shade_square: board_set is one
// struct assignment through Map.set (Map.gml:25-29) with no invalidation behind
// it, and board_get answers undefined for a key refresh_slot has never written,
// which is not a value worth comparing a bool against.
function yads_soft_lock_square(_squares, _index, _locked) {
    if (_squares == undefined) { return; }
    if (_index >= array_length(_squares)) { return; }

    _squares[_index].square.board_set("soft_locked", _locked);
}

//
// 8. THE RECONCILER
//
// Everything the storage menu can do to the mirror, and why a per-key total diff
// covers all of it (InventoryMenu.gml:315-439, StorageMenu.gml:470-590):
//
//   PickUp / PickUp-half   our_slot.remove(n)              -> key total falls
//   Transfer (out)         transfer_slot.remove(n)         -> key total falls
//   PutDown (same item)    our_slot.add(hand_item, n)      -> key total rises
//   PutDown (swap)         hand_slot.swap(our_slot)        -> one falls, one rises
//   Transfer (in)          pair.add(item, n)               -> key total rises
//   Stack button           pair.add(item, n) per slot      -> key totals rise
//   ESC while holding      source_inventory.add(item)      -> key total rises
//   Left sort button       drain + re-add + direct writes  -> pure permutation, zero
//   Trash button           operates on the hand only       -> nothing (the pickup
//                                                             already withdrew it)
//
// Only the last two are non-obvious. Vanilla sort rewrites all 54 slots and bumps
// every `updates`, but it conserves per-key totals exactly, so a total diff
// reports no delta and we leave the player's re-ordering alone. Trash destroys
// what is in the hand, and the hand was filled by a PickUp we already turned into
// a real withdrawal, so the items are correctly gone.
//
// Withdrawals walk member slots by hand instead of calling Inventory.remove,
// because that matches on the raw item id and would happily eat an infused
// variant to satisfy a request for the plain one. They target ALL members;
// deposits target the blocks only.
//
// Deposits never call Inventory.add without a room check: add() has no capacity
// test and dereferences the undefined slot it gets back when the inventory is
// full.
//
// ORDERING GUARANTEE, and it is load-bearing. The two apply loops below
// are PURE inventory arithmetic - they move counts between the mirror's shadow
// and the member chests and touch nothing else. The shadow advance and the two
// dirty flags follow immediately after them. Only THEN does anything that
// reaches outside this file run: the overflow refund (ARI.give_item) and the
// "network full" toast (create_notification), which are the only two plausibly
// throwing calls on the whole path. Our tick is wrapped in mmapi_run_installs'
// swallow-all try/catch (mmapi.gml:75-84), so a throw here is silent and the
// rest of the frame's tick work is skipped - which makes WHERE it can happen the
// entire safety argument:
//
//   * shadow AFTER the moves, never before: if the shadow advanced first and a
//     deposit then failed, the mirror would be declared reconciled for items the
//     members never received - a silent LOSS.
//   * refunds AFTER the shadow, never interleaved with the moves: if the books
//     were still half-closed when give_item or the toast threw, the shadow would
//     still describe the pre-move mirror while the members had already taken the
//     delta, and the next diff would apply the same delta a second time. Replay
//     is DUPLICATION, and the fast path at the top of this function means nothing
//     self-heals it - it sits dormant until the player's next action.
//
// Between the diff and the shadow advance, therefore, only engine-total
// inventory math runs. yads_deposit carries no give_item and no toast for
// exactly that reason: it reports what it could not place and this function pays
// the remainder back once the books balance. The withdraw short-report lives in
// the tail for the same reason.
//
// THE RESTING INVARIANT, stated once: at every frame boundary,
//     for every key K in shadow:  shadow[K].count <= sum over members of
//                                 units partial_eq to shadow[K].item
// Both writers uphold it unconditionally. project() derives the shadow from an
// index built out of the members. reconcile() strips overflowed units out of
// the mirror and out of _now before writing shadow = _now, so the books never
// record units the members did not receive - the overflow's custody passes to
// the local _overflow array, which the refund tail pays back to the player.
// The tail is ALLOWED to fail, and the guarantee is ordering, not totality:
// give_item is total for our inputs, and the one call that is not -
// create_notification, with its unguarded ANCHOR.get_menu deref - is
// sequenced last, after every refund has landed. Do not reorder it upward. A violated invariant is
// what turns a hypothetical mid-frame throw into duplication (stale shadow
// replays the delta) or loss (projection paints over unrecorded units); holding
// it makes every partial-failure outcome a pure display artefact.
//
// Returns true when anything moved.
//
function yads_reconcile(_view) {
    // Never-projected guard. updates_sum is written in exactly two places: this
    // function (below) and a COMPLETED projection's books (yads_project 7f).
    // undefined here therefore means no projection has ever closed its books:
    // either the mirror is empty (nothing to diff), or a projection threw
    // mid-write and the mirror holds a partial page whose originals still live
    // in the members. Diffing that partial page against an empty shadow would
    // classify every visible stack as a fresh push and mint clones into the
    // blocks while the originals stay put - automatic duplication, no player
    // action (B12 wave-2 MAJOR-1). Adopt the mirror as the projection it is
    // and stand down: every mirror slot was written FROM a member item, so
    // shadow = view_totals restates the resting invariant (shadow[K] <= members[K]
    // for every mirrored key - the mirror is one page, so a key straddling a
    // page boundary mirrors less than the members hold) without moving anything. project_dirty is still
    // true after a mid-write throw, so the next tick re-projects and the books
    // close normally.
    if (_view.updates_sum == undefined) {
        _view.updates_sum = yads_updates_sum(_view.inv);
        _view.shadow = yads_view_totals(_view);
        return false;
    }

    // Fast path: the diff below allocates (one struct per occupied slot plus an
    // 8-part key string), which is real garbage at 60fps on a full page. Every
    // mutation the menu can make bumps some slot's `updates` counter - vanilla's
    // own InventorySubscriber watches exactly this - so an unchanged sum means
    // an unchanged mirror and the whole diff can be skipped.
    var _sum = yads_updates_sum(_view.inv);
    if (_sum == _view.updates_sum) { return false; }
    _view.updates_sum = _sum;

    var _now = yads_view_totals(_view);
    var _shadow = _view.shadow;
    var _changed = false;

    // Collect first, apply in two passes. A PutDown onto an occupied cell is a
    // swap: one key falls and another rises in the same frame. Running every
    // withdrawal before any deposit means the space the outgoing item vacates is
    // available to the incoming one, so a swap into a brim-full network works
    // instead of bouncing off it.
    var _pulls = [];
    var _pushes = [];

    // Keys the mirror used to show.
    var _keys = struct_get_names(_shadow);
    for (var _i = 0; _i < array_length(_keys); _i++) {
        var _key = _keys[_i];
        var _was = _shadow[$ _key];
        var _is = _now[$ _key];
        var _have = (_is == undefined) ? 0 : _is.count;

        if (_have < _was.count) {
            array_push(_pulls, { item: _was.item, count: _was.count - _have });
        } else if (_have > _was.count) {
            array_push(_pushes, { item: _is.item, count: _have - _was.count });
        }
    }

    // Keys that appeared out of nowhere - a deposit of something the network did
    // not previously hold, or the far side of a swap.
    _keys = struct_get_names(_now);
    for (var _i = 0; _i < array_length(_keys); _i++) {
        var _key = _keys[_i];
        if (_shadow[$ _key] != undefined) { continue; }
        var _is = _now[$ _key];
        array_push(_pushes, { item: _is.item, count: _is.count });
    }

    // --- APPLY. Nothing in this stretch may do anything but move items. --------
    var _shorts = [];
    for (var _i = 0; _i < array_length(_pulls); _i++) {
        var _pull = _pulls[_i];
        var _got = yads_withdraw(_view, _pull.item, _pull.count);
        _changed = true;
        if (_got < _pull.count) {
            // Should be unreachable - the mirror is built from these very slots.
            // Recorded here, REPORTED in the refund tail: the apply stretch stays
            // pure. The projection this reconcile already forces repaints the
            // display down to what the members really held.
            array_push(_shorts, { item: _pull.item, count: _pull.count - _got });
        }
    }

    // What the blocks could not take. One entry per template, because the two
    // diff loops walk disjoint key sets (the second skips every key the shadow
    // already had), so a template can be pushed at most once per reconcile.
    var _overflow = [];
    for (var _i = 0; _i < array_length(_pushes); _i++) {
        var _push = _pushes[_i];
        var _placed = yads_deposit(_view, _push.item, _push.count);
        _changed = true;
        if (_placed < _push.count) {
            array_push(_overflow, { item: _push.item, count: _push.count - _placed });
        }
    }

    // Overflowed units exist NOWHERE in the members, so they may not stay in the
    // mirror either: strip them out and amend _now to match, so the books below
    // record only what the members actually received. This is what makes the
    // resting invariant - shadow[K] <= sum of member counts for K - hold
    // UNCONDITIONALLY rather than "until the next projection": without this
    // step, a throw in the refund tail would leave a shadow that either replays
    // the delta (duplication) or, projected over, vanishes it (loss). After it,
    // the overflow lives only in the _overflow array, custody-equivalent to a
    // hand the refund tail pays out.
    for (var _i = 0; _i < array_length(_overflow); _i++) {
        var _entry = _overflow[_i];
        // Decrement by what was REMOVED, never by what was requested. The two
        // are provably equal today (every overflow entry is bounded by the
        // mirror's own totals, and nothing between view_totals and this strip
        // can shrink the mirror - withdraw walks members, deposit_fit walks
        // blocks, neither can reach _view.inv), but book-keeping off the
        // request would make that unwritten proof load-bearing: a short strip
        // would under-record the mirror and next frame's diff would re-deposit
        // the residue - duplication. Off the actual count, a short strip
        // degrades to a stale display that the projection repaints.
        var _stripped = yads_mirror_remove(_view, _entry.item, _entry.count);

        var _key = yads_agg_key(_entry.item);
        var _tot = _now[$ _key];
        if (_tot != undefined) {
            _tot.count -= _stripped;
            if (_tot.count <= 0) { struct_remove(_now, _key); }
        }
    }

    // The mirror_remove calls above bumped slot update counters; re-baseline so
    // the fast path does not schedule a spurious diff next frame.
    if (array_length(_overflow) > 0) {
        _view.updates_sum = yads_updates_sum(_view.inv);
    }

    // --- BOOKS. The members are the truth again; say so before doing anything ---
    // else. Moved forward even if the caller defers the re-projection, or the
    // next tick would replay the same delta.
    if (_changed) {
        _view.shadow = _now;
        _view.index_dirty = true;
        _view.project_dirty = true;

        // Items just moved into or out of member chests, so the glow cache's
        // per-block fill tier (empty / in use / full, section 9) is now derived
        // from stale counts. Without this line a deposit made with the panel
        // open would reach the glow only when the panel CLOSED (view teardown
        // invalidates) or when the 60-frame TTL next expired, which for a fill
        // signal is a visible second of wrong colour.
        //
        // Safe here, in the books group, and the ordering argument above is
        // untouched by it: this is one struct-field write behind two struct reads
        // (yads_glow_invalidate -> glow_state), it allocates
        // nothing, it cannot throw, and it happens AFTER the shadow advance - so
        // it is not in the apply stretch and it is not in the may-fail tail
        // either. It also cannot be lost to a throw in that tail. The tick reads
        // the flag on the NEXT frame (glow_poll runs before reconcile,
        // boot.gml section 3), i.e. a one-frame lag.
        yads_glow_invalidate();
    }

    // --- REFUNDS. Everything past this line is allowed to fail. ---------------
    var _overflow_count = array_length(_overflow);
    if (_overflow_count > 0) {
        for (var _i = 0; _i < _overflow_count; _i++) {
            // give_item drops what the backpack cannot hold on the ground rather
            // than crashing the way ARI.inventory.add would, and with no obj_ari
            // at all it routes to the home grid's lost_items (Ari.gml:465-498) -
            // total for our inputs, on every branch. clone() so the two
            // inventories never share one struct across a boundary we control.
            // The trailing false silences its pickup sound: the toast is the
            // signal here.
            ARI.give_item(_overflow[_i].item.clone(), _overflow[_i].count,
                false, false, false);
        }

        // ONE toast for the whole reconcile, not one per template - the player
        // performed a single action and "the network is full" is a single fact.
        //
        // WHICH fact, though, is now two possibilities, because yads_deposit_fit
        // bounces a Remote Access Panel for a reason that has nothing to do with
        // capacity (H2, see the note over that function). "Network storage is
        // full" would be an outright lie in front of a half-empty crate, and it
        // would not tell the player the one thing they need to know, which is
        // that a remote is linked by HANDING it to a heart.
        //
        // ANY remote in the overflow picks the specific message. If a deposit of
        // several kinds overflowed at once - only possible as the two halves of
        // a PutDown swap, since the diff loops walk disjoint key sets - the
        // remote's message wins, because "the network is full" is a fact the
        // player can see in the grid while "that item is not depositable" is one
        // they cannot.
        //
        // THIS IS THE ONLY EDIT 1.2 MAKES INSIDE THE RECONCILER, and it is
        // deliberately in the may-fail tail rather than anywhere above the
        // shadow advance: it reads the local _overflow array and picks a string.
        // It moves nothing, it writes no field, and it runs after the books are
        // closed - so the §8 ordering proof is untouched by it, in exactly the
        // way the give_item loop above it already is.
        //
        // No toast on the TEARDOWN path: during Anchor.shutdown the InfoToasts
        // menu may already be off open_menus and create_notification derefs it
        // unguarded (InfoToastsMenu.gml:121-123). Gating on torn_down (not
        // closing) keeps the toast alive for the normal-close reconcile, where
        // the player's last action can still overflow and InfoToasts is
        // definitely alive.
        if (_view.torn_down != true) {
            var _refused = false;
            for (var _i = 0; _i < _overflow_count; _i++) {
                if (yads_is_remote(_overflow[_i].item)) { _refused = true; break; }
            }
            create_notification(YADS_LOCAL_ROOT
                + (_refused ? "remote_no_deposit" : "network_full"), 60 * 3);
        }
    }

    // Shorts are a should-never bug report, not a player event: rate limited,
    // and here in the tail because even a logging call has no business inside
    // the apply stretch.
    for (var _i = 0; _i < array_length(_shorts); _i++) {
        mmapi_warn_rate_limited("netstor_withdraw_short", YADS_MOD,
            "withdraw short by " + string(_shorts[_i].count)
            + " of item " + string(_shorts[_i].item.item_id));
    }

    return _changed;
}

// Sum of every slot's `updates` counter - the cheap change detector the
// reconciler's fast path keys on. InventorySlot.add/remove/swap and our own
// write_slot all bump it; nothing decrements it, so equal sums mean untouched.
function yads_updates_sum(_inventory) {
    var _sum = 0;
    var _size = _inventory.size();
    for (var _s = 0; _s < _size; _s++) {
        _sum += _inventory.slot(_s).updates;
    }
    return _sum;
}

// Per-key totals of the mirror, with one live template item per key.
function yads_view_totals(_view) {
    var _totals = {};
    var _inventory = _view.inv;
    var _size = _inventory.size();

    for (var _s = 0; _s < _size; _s++) {
        var _slot = _inventory.slot(_s);
        if (_slot.count == 0 || _slot.item == undefined) { continue; }

        var _key = yads_agg_key(_slot.item);
        var _entry = _totals[$ _key];
        if (_entry == undefined) {
            _totals[$ _key] = { item: _slot.item, count: _slot.count };
        } else {
            _entry.count += _slot.count;
        }
    }

    return _totals;
}

// Take `_count` units matching `_template` out of the member chests, slot by
// slot, honouring partial_eq. Returns how many it actually got.
//
// Pure inventory arithmetic and NOTHING else: this runs inside the reconciler's
// apply stretch, where every statement must be engine-total. Even the
// short-report belongs elsewhere - it is a rate-limited warn whose IO is
// internally try/caught, but the apply stretch's proof must not have to lean on
// that - so it happens in the reconciler's refund tail, off this function's
// consumed return value.
//
// WHICH member slot pays is BFS member order then slot order, and for remotes
// that is a documented residual rather than a guarantee. Every netstor_remote is
// partial_eq to every other - no infusion can attach (neither `material` nor
// `netstor_set` is an infusion-supported tag) and clone() preserves every field
// partial_eq reads (LiveItem.gml:252-262) - so the aggregate merges the whole
// network's remotes into ONE row, and withdrawing 1 of N off that row takes
// whichever the walk reaches first. If a spare remote were sitting in a non-heart
// member, that could unbind the network instead of returning the spare, silently.
//
// It is unreachable through this mod: yads_quick_stack skips remotes (:1131) and
// yads_deposit_fit refuses them (H2 below), so no mod path can put one in a
// block. The one door left is vanilla's own Throw side-channel, which
// Furniture.gml:1236-1262 registers on every interaction_chest node
// unconditionally and which drains the whole held stack (:1245) with no seam
// covering it - the same residual the README already documents. Items are
// conserved on every branch and the state is recoverable in both directions
// (a stray remote is still visible and withdrawable in the aggregate), so this is
// noted here rather than defended against: a per-slot preference would put an
// item-kind special case inside the reconciler's apply stretch, which is the one
// place in this mod that has to stay pure arithmetic.
function yads_withdraw(_view, _template, _count) {
    var _left = _count;
    var _members = _view.members;

    for (var _m = 0; _m < array_length(_members) && _left > 0; _m++) {
        var _inventory = _members[_m][$ "inventory"];
        if (_inventory == undefined) { continue; }

        var _size = _inventory.size();
        for (var _i = 0; _i < _size && _left > 0; _i++) {
            var _slot = _inventory.slot(_i);
            if (_slot.count == 0 || _slot.item == undefined) { continue; }
            if (!_slot.item.partial_eq(_template)) { continue; }

            var _take = min(_left, _slot.count);
            _slot.remove(_take);
            _left -= _take;
        }
    }

    return _count - _left;
}

// Remove `_count` units matching `_template` from the MIRROR's own slots - the
// same surgery as withdraw, aimed at _view.inv. The reconciler uses it to strip
// overflowed units out of the display before it closes its books, so the shadow
// never records units the members did not receive.
function yads_mirror_remove(_view, _template, _count) {
    var _left = _count;
    var _inventory = _view.inv;
    var _size = _inventory.size();

    for (var _i = 0; _i < _size && _left > 0; _i++) {
        var _slot = _inventory.slot(_i);
        if (_slot.count == 0 || _slot.item == undefined) { continue; }
        if (!_slot.item.partial_eq(_template)) { continue; }

        var _take = min(_left, _slot.count);
        _slot.remove(_take);
        _left -= _take;
    }

    return _count - _left;
}

// Push `_count` units of `_template` into the STORAGE BLOCKS, returning how many
// actually landed. Anything that does not fit is the CALLER's to hand back - the
// reconciler does it from its refund tail, once its books are closed.
//
// Blocks only, in scan order. A network of one heart and no blocks therefore has
// zero capacity and bounces every deposit straight back - which is the correct
// reading of "blocks are what stores things", not a bug: the heart's and the
// panels' slack is deliberately not part of the pool.
//
// NO give_item AND NO TOAST IN HERE, ever. Those are the two calls on the
// deposit path that can throw, and from here they would run with the shadow
// still describing the pre-move mirror - so a failure would replay the delta on
// the next diff, which is duplication. Kept to pure inventory arithmetic, this
// function cannot leave the books in a state worth replaying.
//
// It is deposit_fit under the reconciler's own name, and it DELEGATES rather than
// repeating the loop on purpose: "where may an item land" has to be one body, or
// quick-stack and the reconciler can drift apart about it.
function yads_deposit(_view, _template, _count) {
    return yads_deposit_fit(_view, _template, _count);
}

// Quick-stack: push every backpack stack whose kind the network already holds
// into the storage blocks, page-agnostic. The "does the network already hold
// this?" test deliberately reads the ALL-MEMBERS index - topping up an item the
// heart is holding is still a top-up - while the mover below is block-scoped
// like every other deposit path. It replaces the vanilla stack button's
// behaviour, whose per-slot predicate is pair.item_id_quantity() on
// the MIRROR (StorageMenu.gml:479-481) - i.e. it silently no-ops for anything
// not on the visible page. Items move member-side only; the next projection
// repaints the mirror from the rebuilt index.
function yads_quick_stack(_view) {
    if (_view.closing == true) { return; }
    if (_view.index_dirty == true) { yads_index_build(_view); }

    var _rows = _view.rows;
    var _backpack = ARI.inventory;
    var _moved_any = false;

    var _size = _backpack.size();
    for (var _i = 0; _i < _size; _i++) {
        var _slot = _backpack.slot(_i);
        if (_slot.count == 0 || _slot.item == undefined) { continue; }

        // H1: NEVER QUICK-STACK A REMOTE. The row test below would pass the
        // moment the network's own bound remote is in the index, and the mover
        // would then push the player's spare remotes into a STORAGE BLOCK -
        // where a binding is unreadable, because the binding scan looks in
        // hearts and only in hearts. One keystroke would quietly convert a
        // spare remote into landfill and, on a network whose heart already
        // holds one, would read as "quick-stack ate my remote".
        //
        // Belt and braces with the refusal in yads_deposit_fit: that one makes
        // the fit come back zero so nothing could move anyway, and this one
        // stops us asking. Neither is redundant - deposit_fit's refusal is what
        // the RECONCILER path needs, this skip is what makes the intent local
        // and legible at the one site that walks the player's own backpack.
        if (yads_is_remote(_slot.item)) { continue; }

        // Only stacks of a kind the network already holds, like the vanilla
        // button - quick-stack is "top up", not "dump everything".
        var _key = yads_agg_key(_slot.item);
        var _known = false;
        for (var _r = 0; _r < array_length(_rows); _r++) {
            if (_rows[_r].key == _key) { _known = true; break; }
        }
        if (!_known) { continue; }

        // Fit what the members can take; NO overflow bounce here - anything
        // that does not fit simply stays in the backpack slot it came from.
        var _fitted = yads_deposit_fit(_view, _slot.item, _slot.count);
        if (_fitted > 0) {
            _slot.remove(_fitted);
            _moved_any = true;
        }
    }

    if (_moved_any) {
        // UIInventoryPutDown is the sound the menu itself plays when a stack
        // lands in a slot (InventoryMenu.gml:76) - the semantically right cue
        // for "your items just went into storage".
        TANGO.play("SoundEffects/UI/UIInventoryPutDown");
        _view.index_dirty = true;
        _view.project_dirty = true;

        // Same reason as the reconciler's: quick-stack is the OTHER function in
        // this file that moves items into blocks while the panel is open, so it
        // is the other place the glow's fill tier goes stale. Gated on the flag
        // that already means "something really moved".
        yads_glow_invalidate();
    }
}

// Deposit into the storage blocks, returning how much fitted. THE one mover for
// every deposit path in the mod - quick-stack calls it directly, the reconciler
// through yads_deposit - so the two cannot disagree about where an item may
// land. It never routes overflow anywhere: the caller keeps custody of the
// remainder and decides what to do with it.
function yads_deposit_fit(_view, _template, _count) {
    // H2: THE REMOTE IS NOT DEPOSITABLE. THE choke point, and it is here rather
    // than in the reconciler's push classification for the reason the comment
    // above already gives: this function is the single admission gate for every
    // deposit path in the mod, so a refusal written here cannot be routed
    // around by a caller that grows later.
    //
    // WHY REFUSE AT ALL. Deposits land in BLOCKS. The binding a remote encodes
    // is "this remote sits in that HEART's inventory" - the scan in boot.gml
    // filters on object_id == heart before it ever reads an inventory. A remote
    // that reached a block would therefore be a live item in a real chest that
    // no longer means anything: not lost, but silently demoted, with the panel
    // showing it in the aggregate and the hotkey saying "no heart is linked".
    //
    // ZERO IS A COMPLETE ANSWER, and it is the same answer a brim-full network
    // gives. The caller keeps custody of every unit, exactly as this function's
    // contract already says, and the reconciler's existing overflow machinery
    // does the rest - strip from the mirror, amend the books, refund to the
    // player from the tail. Nothing new is invented and no item is touched.
    //
    // THE RESTING INVARIANT, PER OUTCOME (the §8 statement: for every key K in
    // shadow, shadow[K].count <= the members' total of units partial_eq to it):
    //
    //   REFUSE-AND-REFUND. The push arrives because the mirror gained N remotes
    //   the members never had. We place 0, so the members are byte-identical to
    //   before. The reconciler pushes {item, N} onto _overflow, mirror_remove
    //   takes those N back out of the mirror and _now is decremented by exactly
    //   what was stripped, so `shadow = _now` records only the remotes the
    //   members really hold (the heart's own bound one, if any - unchanged).
    //   shadow[K] == members[K]: the invariant holds with equality, which is the
    //   same place a full-network bounce leaves it. The N units then live only
    //   in the local _overflow array until give_item hands them back, and that
    //   call is in the may-fail tail AFTER the books are closed, so a throw
    //   there costs the player N remotes at worst and can never duplicate them.
    //
    //   WITHDRAW (the unbind, still allowed). Untouched by this branch: a
    //   withdrawal is a PULL, and pulls never reach this function. The mirror
    //   loses N, yads_withdraw takes N out of the heart's slots, `shadow = _now`
    //   records the reduced total, and shadow[K] == members[K] again. When N
    //   empties the heart's last remote the key leaves both sides together, and
    //   the binding is gone because the binding IS that item's presence -
    //   which is the entire unbind mechanism, needing no code of its own.
    //
    // THE ROUND TRIP IS ONE-WAY, ACCEPTED, AND DOCUMENTED RATHER THAN FIXED.
    // Pull the bound remote out through the view and push it straight back in and
    // you do not get the binding back: the pull unbound it (above), and the push
    // is a deposit, so it lands here and is refused. The units are conserved
    // exactly - the reconciler strips them from the mirror and give_item returns
    // them to the BACKPACK - and the remote_no_deposit toast says what happened,
    // but the affordance still looks reversible for the length of one drag, and
    // yads_has_room (:360-375) computes its dimming over deposit_targets alone
    // and knows nothing about this refusal, so the trailing mirror slots are
    // undimmed and invite the drop.
    //
    // Not worth code. Re-binding through the view would mean a deposit path that
    // targets a HEART, which is exactly the blocks-only rule that makes "where may
    // an item land" a single body; and dimming a slot per template would make the
    // dim state depend on what is in the player's hand. The gesture that binds is
    // handing the remote to the heart (§6b), it is the only one, and the README
    // says so. This is a display honesty gap, not a custody one.
    //
    // Cost: one struct read and one integer compare per deposited template, on
    // a path that only runs when the diff already found a change.
    if (yads_is_remote(_template)) { return 0; }

    var _left = _count;
    var _targets = _view.deposit_targets;

    for (var _m = 0; _m < array_length(_targets) && _left > 0; _m++) {
        var _inventory = _targets[_m][$ "inventory"];
        if (_inventory == undefined) { continue; }

        // Pass the struct, not an id: room_for_item allocates a throwaway
        // LiveItem per slot when it is handed a bare id.
        var _room = _inventory.room_for_item(_template);
        if (_room <= 0) { continue; }

        var _take = min(_left, _room);
        // clone() so the two inventories do not end up sharing one struct across
        // a boundary we control; it is partial_eq to the original, so it stacks.
        _inventory.add(_template.clone(), _take);
        _left -= _take;
    }

    return _count - _left;
}

// Empty the cursor hand back into the player - the same custody math as
// InventoryMenu's own canvas free callback (InventoryMenu.gml:212-221), but
// NOT byte-for-byte: ours passes explicit flags to silence the toast, popup
// and pickup sound (see below). Called early on a save so nothing is left in
// flight when the file is written, and from teardown as the first of the two
// independent hand-return paths.
function yads_flush_hand(_view) {
    var _menu = _view.menu;
    if (_menu == undefined) { return; }

    var _left_menu = _menu[$ "left_menu"];
    if (_left_menu == undefined) { return; }

    // pair_with collapses both hands onto the LEFT menu's (InventoryMenu.gml:8-16).
    var _slot = _left_menu.hand.slot(0);
    if (_slot.count == 0 || _slot.item == undefined) { return; }

    // Silent on purpose (fifth false): this path runs from the save flush and
    // from teardown, and a pickup chirp on every save is noise, not signal.
    // NOTE this is deliberately NOT byte-for-byte the engine's own free
    // callback (InventoryMenu.gml:212-221), which lets the sound play - the
    // custody math is identical, the presentation is not.
    ARI.give_item(_slot.item, _slot.count, false, false, false);
    _slot.remove(_slot.count);
}

//
// 9. THE CONNECTED GLOW, AND THE SAD FACE
//
// Every placed unit that sits on a network WITH A HEART shows an animated glow;
// every stranded or heartless one shows a sad face. That is the only way the
// player can see, without walking up and pressing a button, whether the crate
// they just dropped actually joined the network - which is the single question
// this mod's spatial rules make hard to answer by eye, because adjacency is
// footprint-flush and two units a pixel apart look identical to two touching.
// TWO FACES RATHER THAN PRESENCE/ABSENCE: a missing glow is only legible if you
// already know one was supposed to be there.
//
// MECHANISM. The overlay is `cardinal_data.top_sprite`: the engine spawns an
// independent obj_node_renderer_top per furniture node that declares one
// (Furniture.gml:940-958), gives it its own sprite_index/image_index/depth, and
// then never writes to it again for a chest - the only engine writes after
// creation are the tesserae tree's (Furniture.gml:1483, Interact.gml:319). It is
// not in the cull list (Camera.gml:302-319), it has no shadow caster, and it
// animates itself at its sprite's authored rate. So it is completely orthogonal
// to the interaction_chest lid state machine, which is the whole reason to use
// it: the alternative - swapping the BASE sprite - is reverted to
// cardinal_data.sprite at the end of every open/close/bounce animation
// (Furniture.gml:1226-1232) and would need repairing after each one.
//
// BECAUSE NOTHING ELSE WRITES IT, sprite_index on that instance is ours to own,
// and the two states are a SWAP rather than a `visible` toggle: connected -> the
// glow sprite, disconnected -> spr_furniture_netstor_<unit>_offline. The overlay
// stays visible either way. Two rules make that safe:
//
//   * image_index is NOT auto-reset when sprite_index is assigned - the engine
//     sets it by hand at every one of its own swap sites (Interact.gml:770,
//     StorageMenu.gml:6), which is the tell. Every swap below sets it to 0, or a
//     4-frame face inherits frame 6 of an 8-frame glow.
//   * we never touch `image_alpha`: the highlight path writes it on the overlay
//     every frame the player is looking at the unit (obj_node_renderer.gml:
//     83-87) and would clobber it straight back.
//
// A SECOND CHANNEL on the same instance, `image_blend`, carries the fill tier of
// a connected block (green / yellow / red) and the role colour of a connected
// heart or panel. Unlike sprite_index this one IS contested - the highlight path
// writes it and the overlay's own draw resets it - so it is re-asserted every
// frame from the tick rather than written once per state change. See
// yads_glow_tint and the tick's own note about why camera.culls_processed cannot
// carry that job indoors.
//
// The two assets are resolved at CACHE-BUILD time from the prototype, never off
// the renderer's current sprite_index - by the second apply that field is
// whatever we last put there, so reading it back would latch the state in.
//
// FAIL-SOFT, TWICE OVER. If the content layer ships no top_sprite,
// top_sheet_renderer is undefined everywhere, this whole section finds nothing to
// cache, and the units simply carry no status overlay. If it ships the glow but
// no offline art - an older art layer against newer GML - try_string_to_asset
// returns undefined, offline_asset stays undefined, and that unit alone falls
// back to showing the glow when connected and hiding it when not.
//

// Lazily built, and read with [$ ] rather than declared in yads_runtime()'s
// struct literal, so a global struct left behind by an older boot cannot arrive
// missing the field.
function yads_glow_state(_rt) {
    var _glow = _rt[$ "glow"];
    if (_glow == undefined) {
        _glow = {
            units: [],       // cached {node, renderer, top, ...} triples
            dirty: true,     // a rescan is owed
            count: -1,       // last observed STORAGE_NODES.count()
            ttl: 0,          // frames until the backstop rescan
        };
        _rt.glow = _glow;
    }
    return _glow;
}

function yads_glow_invalidate() {
    yads_glow_state(yads_runtime()).dirty = true;
}

// Hard reset: every cached instance id is presumed dead. Used on room change and
// on save load, both of which destroy and rebuild the world's renderers.
function yads_glow_reset(_rt) {
    var _glow = yads_glow_state(_rt);
    _glow.units = [];
    _glow.dirty = true;
    _glow.count = -1;
    _glow.ttl = 0;
}

// Per-frame upkeep, from the tick. Steady-state cost: one List accessor, one
// decrement, three compares.
//
// The count poll is the removal signal. There is no hook for furniture pickup -
// Pick.gml:402-542 erases through drop_item_to_ground, not drop_item, so
// items.dropped never fires - but every creation of a node with an inventory
// pushes to STORAGE_NODES (Furniture.gml:870) and every erase removes from it
// (GridUtils.gml:322), and List.count() is a one-line accessor over __count.
//
// What it cannot see is an add and a remove inside the SAME frame netting to an
// equal count. Player input cannot produce that, but the engine can and several
// paths do: a blueprint build erases a whole footprint and writes the new one in
// one pass (Blueprints.gml:172), farm expansion erases its fence region and then
// load_objects's the patch (FarmExpansion.gml:14), and the seasonal wilt pass
// does the same shape. So this is not a "cannot happen" - it is a real hole with
// a designed catcher: the count is unchanged, `dirty` is not set, and the lit
// state stays wrong until YADS_GLOW_TTL expires - one second,
// no item risk, self-healing. The TTL exists FOR this case; do not remove it on
// the strength of the count poll looking exhaustive.
function yads_glow_poll(_rt) {
    var _glow = yads_glow_state(_rt);

    // Same shape as the runtime() lazy-init: variable_global_exists does not
    // exist on this runtime, and a bare read of an unset global faults.
    var _list = global[$ "__STORAGE_NODES"];
    var _count = (_list == undefined) ? -1 : _list.count();
    if (_count != _glow.count) {
        _glow.count = _count;
        _glow.dirty = true;
    }

    _glow.ttl -= 1;
    if (_glow.ttl <= 0) { _glow.dirty = true; }

    if (_glow.dirty == true) { yads_glow_rescan(_rt); }
}

// Rebuild the whole cache: walk STORAGE_NODES once, keep our units in the
// current location, union-find them by flush adjacency, and light every
// component that contains a heart.
//
// This deliberately does NOT reuse yads_scan. That function allocates
// array_create(grid.node_len) per call, and node_len on the farm is
// at least 188*144 ~ 27000 (Grid.gml:479-488) - fine once per menu open,
// catastrophic as a cache builder. Working straight off the node footprints
// costs ~15k VM ops for fifty units and touches no grid array at all.
function yads_glow_rescan(_rt) {
    var _glow = yads_glow_state(_rt);
    _glow.dirty = false;
    _glow.units = [];

    // Bails take the SHORT ttl, not the full one: these guards are true during
    // load/transition frames, and a bail that armed the full 60-frame backstop
    // would leave every unit unlit for up to a second after the world becomes
    // ready (nothing else re-dirties on that path). Five frames of retry costs
    // one List accessor each and closes the window.
    _glow.ttl = 5;

    // Before anything else, and before yads_ids() memoizes: this tick also
    // runs on the title screen, where obj_ari does not exist
    // (API_REFERENCE.md:284-288) and where a memo taken off a not-yet-merged
    // fiddle table would stick for the whole session. No player, no world, no
    // glow.
    if (!instance_exists(obj_ari)) { return; }

    var _ids = yads_ids();
    if (_ids.heart == undefined) { return; }     // content not installed

    var _list = global[$ "__STORAGE_NODES"];
    if (_list == undefined) { return; }

    // Renderers exist only for the current location's grid (Grid.gml:208-212),
    // so a unit in another room has nothing to glow. GRID is undefined on the
    // title screen and during some transitions.
    var _world = global[$ "__grid"];
    if (_world == undefined) { return; }
    var _location = _world.location_id;

    // The world is up: this is a real rescan, so arm the full backstop.
    _glow.ttl = YADS_GLOW_TTL;

    // Offline art, one asset per unit kind, resolved here rather than per unit:
    // three lookups per rescan regardless of how many crates are placed, and no
    // "is undefined a miss or a not-yet?" ambiguity to get wrong. Three lookups
    // on an event-driven rebuild are not worth a session memo with a lifetime of
    // its own to get wrong. A slug the art layer did not ship comes back
    // undefined, and that unit falls back to the visible-toggle path in
    // glow_apply.
    static OFFLINE_SLUGS = ["heart", "block", "panel"];
    var _offline = array_create(3, undefined);
    for (var _k = 0; _k < 3; _k++) {
        _offline[_k] = try_string_to_asset(
            "spr_furniture_netstor_" + OFFLINE_SLUGS[_k] + "_offline");
    }

    var _units = [];
    var _rejected = 0;   // in-location members whose renderer/overlay was not up
    var _len = _list.count();
    for (var _i = 0; _i < _len; _i++) {
        var _node = _list.get(_i);
        if (!yads_is_member(_node)) { continue; }

        var _parent = _node[$ "parent_grid"];
        if (_parent == undefined) { continue; }
        if (_parent.location_id != _location) { continue; }

        // THIS RESCAN WRITES NO ENGINE FIELD, and must never be made to. In
        // particular it must not derive `node.destructable`: that field
        // round-trips through the player's save (section 10 carries the proof),
        // and a derive that runs on a timer is exactly the wrong shape for a
        // save-owned field. The pick filter is its sole writer and writes only
        // for the duration of one swing. This function is a CACHE REBUILD, and
        // rebuilds are allowed to be late, wholesale and repeated - none of
        // which a save-owned field tolerates.
        //
        // instance_is_alive, NOT instance_exists, and this is the difference
        // between a glow that reports the topology and one that reports the
        // camera. Camera.process_culls runs instance_deactivate_object(
        // obj_node_renderer) every frame and reactivates only the view + 16px
        // (Camera.gml:291-319), and a DEACTIVATED instance is invisible to
        // instance_exists - the MMAPI hook docs say so outright
        // (camera.culls_processed.md:13). Our tick runs at the head of
        // step_begin, i.e. on the previous frame's cull, so with instance_exists
        // a storage row longer than one screen drops its off-screen half - heart
        // included - and the union-find then declares the visible half dead and
        // paints the sad face on a perfectly healthy network.
        //
        // instance_is_alive is the engine's own test for exactly this: it is what
        // erase_object_renderer uses on node.renderer (GridUtils.gml:171), a path
        // that must work for nodes erased far off-camera or renderers would leak.
        var _renderer = _node[$ "renderer"];
        if (_renderer == undefined || !instance_is_alive(_renderer)) { _rejected += 1; continue; }

        // Direct read, not [$ ]: this is an INSTANCE, not a struct, and
        // obj_node_renderer's create sets top_sheet_renderer = undefined
        // unconditionally (obj_node_renderer.gml:424), so the variable is always
        // there. It stays undefined unless the prototype declared a top_sprite -
        // which is exactly the fail-soft we want if the art layer is absent.
        //
        // obj_node_renderer_top is not in the cull list, so the two tests cannot
        // disagree for it - it is instance_is_alive here for uniformity, so that
        // no reader of this file has to work out which of our liveness checks is
        // deactivation-safe and which is not. All of them are.
        var _top = _renderer.top_sheet_renderer;
        if (_top == undefined || !instance_is_alive(_top)) { _rejected += 1; continue; }

        // Which of the three units is this? Picks the offline face. is_member
        // already guarantees it is one of them, so panel is the correct default
        // rather than a guess.
        var _kind = 2;
        if (_node.object_id == _ids.heart) {
            _kind = 0;
        } else if (_ids.block != undefined && _node.object_id == _ids.block) {
            _kind = 1;
        }

        // Fill tier inputs, for BLOCKS ONLY. There is no O(1) "occupied slots"
        // accessor anywhere on Inventory - size() is capacity, total_items() sums
        // counts, is_empty() is itself a scan - so this is a walk, and it is
        // walked here rather than in glow_apply because apply now runs every
        // frame and a rescan is an event. 50 blocks x 30 slots is 1,500 slot
        // reads per rescan, an order of magnitude under the union-find below it.
        //
        // Hearts and panels are not asked: they are tinted by ROLE (cyan, "this
        // is the brain / this is the door"), never by fullness, because neither
        // is a deposit target and a heart reading "full" would advertise a
        // capacity the network will not use.
        var _used = 0;
        var _size = 0;
        if (_kind == 1) {
            // Read here rather than at the top of the loop: blocks are the only
            // kind that reports a fill level, so hearts and panels never touch
            // the field at all.
            var _inventory = _node[$ "inventory"];
            if (_inventory != undefined) {
                _size = _inventory.size();
                for (var _s = 0; _s < _size; _s++) {
                    var _slot = _inventory.slot(_s);
                    // count == 0 and item == undefined are the same state; both
                    // are tested because every other slot loop in this mod does.
                    if (_slot.count != 0 && _slot.item != undefined) { _used += 1; }
                }
            }
        }

        array_push(_units, {
            renderer: _renderer,
            top: _top,
            grid: _parent,
            // 0 heart, 1 block, 2 panel - kept so glow_apply can pick a tint
            // without re-deriving it from object_id against a memo that may have
            // been dropped by a save load since.
            kind: _kind,
            // Occupied and total slots, blocks only (0/0 for the other two).
            used: _used,
            size: _size,
            // The two sprites this unit's overlay alternates between. Read from
            // the prototype, not from _top.sprite_index, which by now may be
            // whatever the last apply wrote.
            glow_asset: yads_glow_top_sprite(_node),
            offline_asset: _offline[_kind],
            // Footprint from the NODE, never prototype.size: rotation swaps the
            // two (Furniture.gml:2028-2035).
            x0: _node.top_left_x,
            y0: _node.top_left_y,
            w: _node.write_size_x,
            h: _node.write_size_y,
            heart: (_node.object_id == _ids.heart),
            root: array_length(_units),   // union-find: each unit starts alone
            lit: false,
        });
    }

    var _count = array_length(_units);

    // Pairwise union over flush adjacency. Quadratic, but on a count that is
    // bounded by how many crates a player can be bothered to place: 50 units is
    // 1225 pairs of a handful of integer compares, and this runs on an event,
    // not per frame.
    for (var _a = 0; _a < _count; _a++) {
        for (var _b = _a + 1; _b < _count; _b++) {
            // Structs compare by reference on this runtime. A network never
            // leaves its Grid - a table surface is a child grid and does not
            // bridge to the floor.
            if (_units[_a].grid != _units[_b].grid) { continue; }
            if (!yads_glow_adjacent(_units[_a], _units[_b])) { continue; }

            var _ra = yads_glow_find(_units, _a);
            var _rb = yads_glow_find(_units, _b);
            if (_ra != _rb) { _units[_rb].root = _ra; }
        }
    }

    // A component is live exactly when it contains a heart - the same rule the
    // interaction uses, so what the player sees and what the panel does agree.
    var _live = array_create(_count, false);
    for (var _i = 0; _i < _count; _i++) {
        if (_units[_i].heart) { _live[yads_glow_find(_units, _i)] = true; }
    }
    for (var _i = 0; _i < _count; _i++) {
        _units[_i].lit = _live[yads_glow_find(_units, _i)];
    }

    _glow.units = _units;

    // A frame where the world globals are up but this location's renderers are
    // not built yet (room build straddles frames) passes every guard above and
    // then rejects EVERY unit - which is indistinguishable from "no units here"
    // by the cache alone. An empty result with rejections is a not-yet, not a
    // no: take the short retry instead of the 60-frame backstop, or every
    // stranded unit sits out the first second of a room wearing the connected
    // glow it was born with.
    if (array_length(_units) == 0 && _rejected > 0) {
        _glow.ttl = 5;
    }

    yads_glow_apply();
}

// The overlay sprite the ENGINE gave this node's top renderer at creation, read
// back out of the prototype so we can restore it after a swap.
//
// create_furniture_renderer reads node.prototype.cardinal_data[node.cardinal_index]
// and takes .top_sprite from it, preferring .winter_top_sprite in winter
// (Furniture.gml:892, :940-944); the parser has already turned both into resolved
// assets or undefined (Furniture.gml:229-234), so nothing here needs to look a
// string up. The season branch is repeated rather than assumed away: our own
// content declares no winter override today, but a mod that reads the prototype
// and a mod that ships the art must not be able to disagree about which sprite
// "connected" means.
//
// Every hop is guarded even though the engine dereferences the same chain
// unguarded: a mod that faults inside a per-frame cache rebuild takes the game
// with it, and undefined here simply means this unit keeps whatever its overlay
// already had.
function yads_glow_top_sprite(_node) {
    var _proto = _node[$ "prototype"];
    if (_proto == undefined) { return undefined; }

    var _cardinals = _proto[$ "cardinal_data"];
    if (_cardinals == undefined) { return undefined; }

    var _index = _node[$ "cardinal_index"];
    if (_index == undefined) { return undefined; }
    if (_index < 0 || _index >= array_length(_cardinals)) { return undefined; }

    var _data = _cardinals[_index];
    if (_data == undefined) { return undefined; }

    if (CALENDAR.season() == Season.Winter) {
        var _winter = _data[$ "winter_top_sprite"];
        if (_winter != undefined) { return _winter; }
    }

    return _data[$ "top_sprite"];
}

// Union-find root with path compression. Plain array of structs; no ds_ types,
// matching the rest of this file.
function yads_glow_find(_units, _index) {
    var _root = _index;
    while (_units[_root].root != _root) { _root = _units[_root].root; }

    var _walk = _index;
    while (_units[_walk].root != _walk) {
        var _next = _units[_walk].root;
        _units[_walk].root = _root;
        _walk = _next;
    }

    return _root;
}

// Do two footprints share an orthogonal grid edge? Identical relation to the
// BFS ring probe: the AABBs must be flush on one axis AND overlap by a non-zero
// amount on the other, which is what excludes the four diagonal corners - two
// crates meeting at a single point are not connected.
function yads_glow_adjacent(_a, _b) {
    var _ax1 = _a.x0 + _a.w;
    var _ay1 = _a.y0 + _a.h;
    var _bx1 = _b.x0 + _b.w;
    var _by1 = _b.y0 + _b.h;

    if (_ax1 == _b.x0 || _bx1 == _a.x0) {
        return (min(_ay1, _by1) - max(_a.y0, _b.y0)) > 0;   // vertical seam
    }
    if (_ay1 == _b.y0 || _by1 == _a.y0) {
        return (min(_ax1, _bx1) - max(_a.x0, _b.x0)) > 0;   // horizontal seam
    }

    return false;
}

// Assert the cached state onto the live overlay instances. Three callers: the
// tail of a rescan; camera.culls_processed, which outdoors is the one moment a
// renderer that just scrolled back into view is active but has not yet drawn, so
// the glow is never a frame late on scroll-in; and the tick, every frame,
// because that hook does not fire indoors at all and the fill tint has to be
// re-asserted after every highlight (see the tick's note).
//
// Cost: array_length, then ~8 ops per cached unit. A dead instance anywhere
// means the world was rebuilt under us, so mark dirty and let the tick redo it.
function yads_glow_apply() {
    var _rt = yads_runtime();
    var _glow = _rt[$ "glow"];
    if (_glow == undefined) { return; }

    var _units = _glow.units;
    var _count = array_length(_units);
    if (_count == 0) { return; }

    for (var _i = 0; _i < _count; _i++) {
        var _unit = _units[_i];
        // Same test as the rescan, for the same reason: one liveness predicate
        // across the whole glow path, and the only one that is correct under
        // culling (GridUtils.gml:171).
        var _top = _unit.top;
        if (!instance_is_alive(_top)) { _glow.dirty = true; continue; }

        var _want = _unit.lit ? _unit.glow_asset : _unit.offline_asset;

        // Degraded-art fallback: nothing to swap TO for this state (an art
        // layer older than this GML, or a prototype we could not read). Show
        // the overlay when connected, hide it when not.
        if (_want == undefined) {
            if (_top.visible != _unit.lit) {
                _top.visible = _unit.lit;

                // The base renderer latches `interacting` on the overlay while
                // the player is highlighting the unit, and the overlay's own
                // draw is what consumes and clears it
                // (obj_node_renderer_top.gml:11-25). Hiding it mid-highlight
                // would leave the flag set and make the first frame after it
                // comes back draw once through the highlight shader.
                if (!_unit.lit) {
                    _top.interacting = false;
                    // The highlighter writes blend/alpha on the overlay every
                    // frame it is on (obj_node_renderer.gml:83-87), and the
                    // only engine reset lives inside the interacting branch of
                    // the overlay's own Draw - which never runs while hidden.
                    // Without this, a unit hidden mid-highlight comes back
                    // permanently tinted on the degraded-art path.
                    _top.image_blend = c_white;
                    _top.image_alpha = 1.0;
                }
            }
            continue;
        }

        // Swap path. The overlay is always visible here, so `interacting` is
        // deliberately left alone: the face draws every frame, which means the
        // engine's own consume-and-clear runs every frame, and clearing the flag
        // ourselves would eat the highlight on a disconnected unit - the one the
        // player is most likely to be standing in front of wondering why.
        if (!_top.visible) { _top.visible = true; }

        if (_top.sprite_index != _want) {
            _top.sprite_index = _want;
            _top.image_index = 0;   // never auto-reset on assignment
        }

        // The FILL tint, and the second thing the overlay says.
        //
        // image_blend is a per-channel MULTIPLY against the drawn pixel
        // (obj_node_renderer_top.gml:20 draw_self, or :13 while highlighting), so
        // this only produces three distinguishable colours because the art layer
        // draws the connected glow in near-white luminance. Against saturated
        // cyan art it would not: cyan x red is (95,0,0), a dark maroon, and
        // cyan x yellow is (95,220,0), an olive - two dim smudges next to one
        // clean green. Art and tint are one feature; changing either alone
        // breaks it.
        //
        // Only the connected state is tinted. A disconnected unit is showing the
        // sad face and gets c_white: it has no fill to report, and a red sad face
        // would read as a second, louder error.
        //
        // The write is guarded on inequality, which is not an optimisation but
        // the whole re-assert mechanism: the highlight path overwrites
        // image_blend every frame the player looks at the unit and the overlay
        // resets it to c_white after drawing (obj_node_renderer_top.gml:16-18),
        // so the guard is false exactly on the frames the tint really was lost.
        // image_alpha is still never touched - the highlighter owns it.
        var _tint = _unit.lit ? yads_glow_tint(_unit) : c_white;
        if (_top.image_blend != _tint) { _top.image_blend = _tint; }
    }
}

// Which colour a connected unit's overlay is multiplied by.
//
// Blocks are the only units that store, so they are the only ones that report a
// level: green empty, yellow in use, red full - the traffic-light reading a
// player already has for every other fill gauge in the game. Hearts and panels
// report their ROLE instead, in the set's own cyan, because neither is a deposit
// target and a heart painted "full" would advertise capacity the network will
// never use.
//
// make_color_rgb rather than c_lime / c_yellow / c_red: c_lime is not defined
// anywhere in the game corpus (c_yellow and c_red are), and an identifier the
// engine does not define is a compile error, which under --strict-lints
// excludes the whole mod, content included. Spelling all four out as literals
// keeps one rule instead of a proven pair beside an unproven third.
//
// THE THREE FILL COLOURS ARE PASTEL, NOT PRIMARY. image_blend is a per-channel
// MULTIPLY over near-white overlay art, so a channel at 0 erases that channel
// outright: make_color_rgb(0, 255, 0) painted the glow a hard neon green that
// nothing else in Mistria's palette resembles. Lifting the zeroed channels to
// 130 keeps the same three hues and the same traffic-light reading while the
// result sits in the game's own softer range. Do not "fix" these back to
// saturated primaries; they are chosen against the art, not against a
// colour wheel.
//
// The cyan is UNCHANGED and must stay make_color_rgb(64, 200, 214): it is the
// same value the status popup's fill bar uses (view.gml), so world and UI agree
// on the set's colour. Change one and you must change both.
function yads_glow_tint(_unit) {
    if (_unit.kind != 1 || _unit.size <= 0) { return make_color_rgb(64, 200, 214); }

    if (_unit.used <= 0) { return make_color_rgb(130, 255, 130); }
    if (_unit.used >= _unit.size) { return make_color_rgb(255, 130, 130); }
    return make_color_rgb(255, 250, 160);
}

//
// 10. PICK PROTECTION
//
// A unit that still holds items takes five pickaxe swings to remove. An empty
// one takes the vanilla single swing, unchanged.
//
// WHAT IT IS NOT. It is not data-loss prevention, and the changelog must not
// claim it is: vanilla drops a storage node's ENTIRE inventory on erase
// (GridUtils.gml:287-323 drains every slot to drop_item_to_ground, or to
// grid.lost_items when the drop point is off-screen, and only then unlists the
// node), so nothing is destroyed today either. What is lost is the player's
// afternoon: fifty-four stacks on the ground around a farm, and a network that
// has silently lost a member. This is a guard against the ACCIDENT - the swing
// aimed at the rock behind the crate - and it is sized for that and nothing
// else.
//
// HOW REMOVAL WORKS, because the shape of the fix follows from it:
//   * furniture removal is a PICKAXE swing and only that. ItemUse.UseTool with
//     ToolType.PickAxe (use_item.gml:189-217) enters PlayerState.Tool, whose
//     per-target callback is pick_axe -> pick_node (AriFsm.gml:2698-2699). The
//     axe cannot touch furniture (Chop.gml handles Stump and Tree only) and
//     neither can the sword (Slash.gml: Grass, Breakable, Crop).
//   * there is NO hitpoint model for furniture. Rocks have node.hitpoints
//     (Pick.gml:136-139); one successful swing erases furniture outright
//     (Pick.gml:539). So "five swings" has to be counted by us or not at all.
//   * the one node field the removal consults is node.destructable
//     (Pick.gml:33 in can_pick_node, :406 in pick_node - the only two readers
//     in the corpus). False makes pick_node play vanilla's own inadequate SFX,
//     shake the unit, rumble the pad and return PickResult.Nothing
//     (Pick.gml:451-460), which pick_axe then turns into no stamina cost and no
//     essence (AriFsm.gml:2704-2707). Every piece of the "that did not work"
//     feedback is vanilla's; we supply none of it.
//
// AND THE SWING STILL LANDS, which is the fact the whole feature rests on. The
// Tool state's per-target loop computes can_pick_node into `valid_target`
// (AriFsm.gml:3296) and then calls self.callback UNCONDITIONALLY at :3329 -
// valid_target is consumed only by the Lightweight infusion's stamina refund.
// So a blocked swing reaches pick_node, our filter fires, and the attempt is
// countable. A design that vetoed the swing earlier (items.use_guard) could not
// count anything.
//
// WHERE WE INTERCEPT. resource.node_modifier is a FILTER at the head of
// pick_node (seams.toml pick_node_modifier: context_before is the function
// signature, context_after is `var is_rug_pick = false;`), so the handler runs
// before pick_node's own four-cell scan, before the category switch, and
// therefore before `var cannot_destroy = node.destructable == false` at :406.
// Flipping the flag inside the filter decides THIS swing, not the next one.
//
// TWO THINGS TO KNOW ABOUT THAT SEAM:
//   * it is shared with chop_node (seams.toml chop_node_modifier), so the
//     handler's first test is ctx.action == "pick". Without it this runs on
//     every axe swing in the game as well.
//   * the hook's own doc string names rocks, forage, dig sites, trees and
//     stumps - not furniture. The seam is nevertheless a positional filter at
//     the function head with no branch between it and the Furniture case, so
//     the doc undersells it. This is a dependency on the seam LOCATOR rather
//     than on the documented contract: if a future MOMI narrows the seam into
//     the Rock branch, protection silently stops and NOTHING ELSE BREAKS - the
//     units go back to being ordinary one-swing furniture, which is the same
//     state the mod ships them in at rest. That is the right direction to fail
//     in, and it is only true because the flag has no resting value of ours.
//
// ---------------------------------------------------------------------------
// destructable IS SERIALIZED. THE FLAG NEVER RESTS AT FALSE.
// ---------------------------------------------------------------------------
// No grep of scripts/Serialization/ will show you this, and a grep is why it is
// easy to get wrong: the grid serializer and deserializer are GENERIC struct
// walkers that never name a single field, so no name search can see them.
//
//   SAVE  Grid.gml:1367 create_grid_object_serialization_data walks
//         struct_get_names(parent) and skips exactly eight names (:1419-1428:
//         prototype, last_update, renderer, sub_grid_blob, parent_grid,
//         write_size_x, write_size_y, active_toy_sfx). `destructable` is not
//         among them, so it falls to the default arm at :1445 and is written
//         verbatim into the location file's object_list entry.
//   LOAD  Grid.gml:1071 load_objects writes the node from the prototype first
//         (:1105 -> Grid.gml:258 -> Furniture.gml:571 -> :649
//         node.destructable = proto.destructable - the "re-derive" that makes
//         this look safe) and THEN runs a second generic walk over the
//         SAVED struct whose skip list (:1182-1252) also omits `destructable`,
//         ending at :1255 node[$ name] = obj[$ name]. The saved value wins,
//         150 lines after the re-derive.
//   PROOF THE ENGINE DEPENDS ON THE ROUND TRIP  Patches.gml:426-452 pushes
//         three literal { object_id: "water_blocker", destructable: false }
//         entries straight into farm_objects.object_list and saves the file
//         (again at :938-953 for auto_feeder_platform). Those nodes are
//         permanent BY SAVE DATA. `destructable` is a save-owned field.
//
// Two things follow, and they are the whole shape of this section:
//
//   1. A FALSE WE LEAVE BEHIND IS A FALSE IN THE PLAYER'S SAVE, surviving
//      uninstallation of the mod as a crate nothing can ever break. So the flag
//      is written TRANSIENTLY - inside one pick_node call, undone on the next
//      frame - and the save handler undoes it once more before the grids
//      serialize (section 7's game_saving). THERE MUST BE NO TIMER-DRIVEN
//      DERIVE ANYWHERE. yads_pick_repair below also undoes any resting false a
//      pre-release build of this mod may have left in a save, using the engine's
//      own Unbreakable test to tell that damage apart from the engine's intent.
//   2. A TRUE WE WRITE CAN DESTROY AN ENGINE INVARIANT. Furniture.gml:685-687
//      forces node.destructable = false for any furniture standing on a
//      TileFlag.Unbreakable cell. Writing an unconditional `true` over that
//      un-breaks the engine's own rule AND persists the damage. Hence the BASE
//      RULE: the
//      first time we touch a node we record the value we found, we never write
//      anything but `base && <our intent>`, and every restore writes `base`.
//      An engine-forced false stays forced, forever, whatever we want.
//
// WHAT IS NOT COVERED, stated once so nobody rediscovers it as a bug:
//   * BOMBS COUNT as attempts, which follows from the flag resting at `base`
//     rather than being a separate decision. obj_damage_tarball tests
//     can_pick_node BEFORE calling pick_node (:176); with the flag at rest that
//     test passes, pick_node runs, and our filter sees the blast exactly like a
//     swing. A blast fires one pick_node per cell of its rect (:172-178) but
//     they are all in one frame, so the frame de-dup below scores the whole
//     blast as one attempt. Five bombs, or any mix of five bombs and swings,
//     still releases the unit. (This stays unconditional only because the
//     prototypes carry NO check_pick - see furniture.toml. A check_pick that
//     also failed on an overlap would take can_pick_node down with it and a
//     bomb at the player's feet would silently stop counting.)
//   * THE WALKABLE MARGINS PUT THE PLAYER INSIDE THE FOOTPRINT, and the
//     non-mouse aim path notices. The gamepad/keyboard target queue pushes the
//     FACED cell first and the player's OWN cell second (obj_ari.gml:1052,
//     :1076, :1100, :1124 - one per cardinal), then takes the first cell whose
//     item_effects_node_at_cell passes (:1149-1176), falling back to
//     QUEUE.first() (:1180). Every footprint cell carries node_object_id,
//     margins included - write_object_inst_node runs for all i,j and BEFORE the
//     collision call (Furniture.gml:665-675, GridUtils.gml:98-105) - so a unit
//     is a legal auto-aim target while the player is STANDING ON IT, which
//     before Beta 1.0 was unreachable ground. A gamepad swing from a margin can
//     therefore resolve the crate underfoot when the faced cell holds nothing
//     pickable. Harmless, and deliberately left alone: the crate is a normal
//     target reached by the normal path, so the five-swing guard covers it
//     exactly as it covers a swing from anywhere else. Recorded because it is
//     the one aiming behaviour the margins created, and because the field that
//     would have blocked it (check_pick) was tried in Beta 1.0 and reverted -
//     it made the refusal SILENT and did so from two cell rows away.
//   * FIRE is already vanilla-safe: Pick.gml:492-494 refuses any node with an
//     interaction_chest when is_burn, and all three of our units have one.
//   * BLUEPRINTS and FARM EXPANSION erase nodes directly (Blueprints.gml:172,
//     FarmExpansion.gml:14) and reach no seam at all. Genuinely hookless, the
//     same shape as the Throw residual.
//   * A UNIT ON A TABLE is not protected. can_be_child is true in the vanilla
//     furniture [default] and we do not override it, so a unit can be placed
//     into a table's child_grid (Furniture.gml:591-608) - and a swing there
//     resolves the TABLE, which is not a member, so we decline and vanilla
//     erases the table and every child in one hit. Contents still drop rather
//     than vanish (GridUtils.gml:287-323), so the wall holds; the five-swing
//     promise simply does not apply. Documented in the README beside the Throw
//     residual, because the honest fix is "networks do not span child grids
//     anyway - do not build on tables".
//   * THE NETSTOR PROTOTYPES MUST NEVER DECLARE child_grid. This is an invariant
//     of the fiddle data, not of this file, and it is the one prototype key that
//     would void the whole feature in silence. `destructable == false` is not a
//     hard veto in this engine: both readers cancel it if ANY destructable-
//     prototype child is standing on the node's own surface -
//       Pick.gml:411-429   inside pick_node, AFTER cannot_destroy is computed:
//                          `if cannot_destroy { for (...target_list...) if
//                          target_list.get(i)[0].prototype.destructable {
//                          cannot_destroy = false; break; } }`
//       Pick.gml:34-52     the same override in can_pick_node, spelled as a
//                          direct `return true` out of the destructable == false
//                          branch instead of clearing a flag.
//     Today this is inert: the vanilla furniture [default] sets child_grid = false
//     and we do not override it, so node.child_grid is undefined, target_list is
//     empty and the loop never runs. Give a unit a tabletop - a very natural
//     request for "a Storage Block you can put a lamp on" - and the five-swing
//     guard is defeated on BOTH paths by setting any ordinary item on top of it,
//     with no other symptom and nothing in this file to catch it. The warning is
//     repeated in fiddle/object_prototypes/furniture.toml, where the change would
//     actually be made.
//
// A CHARGED SWING IS NOT ONE pick_node CALL, and this is the trap the frame
// stamp below exists for. PlayerState.Tool builds `targets` from the tool's
// range pattern (AriFsm.gml:3218) and calls the per-target callback once per target
// (:3265-3332, the call at :3329), and pick_axe turns each of those into its
// own pick_node (:2698-2699). Targets step by two cells (RangePattern.gml:
// 12-72) and each pick_node rescans its own 2x2 window (Pick.gml:103-124), so a
// 4x2 unit - two block-columns wide, and unsnapped, because on_twos_only is
// false in the vanilla [default] - is hit by 2 windows at an even placement and
// up to 6 at an odd one. The engine's own per-node de-dup (AriFsm.gml:3281,
// last_update == node_tick) cannot help: last_update is only stamped at :3323
// inside the Lightweight branch, which requires valid_target, which is
// can_pick_node, which is false for a suppressed unit. It is dead exactly when
// protection is on. Count per CALL and a Tier3 charged swing at an odd-placed
// full crate spends the whole five-swing budget in one swing.
//
// THE FIX IS A FRAME STAMP. The count may advance at most once per TICK
// (Utilities/Tick.gml, `#macro TICK global.__tick`), which is the same idiom
// the engine uses for exactly this shape of problem (obj_tile_cursor.gml:
// 337-338 `no_furniture.tick != TICK`, Furniture.gml:1273 deploy_poof). One
// swing is one frame of target callbacks, so one swing is one count no matter
// how wide the pattern or how the crate is placed.
//
// STATE. One entry per unit recently swung at, in a plain array on the runtime
// struct - not on the node (which cannot be swept), and not in the glow cache
// (which is rebuilt wholesale about once a second, taking every count with it).
// Each entry carries the BASE described above, the count, the frame the count
// last advanced on, and whether OUR value is currently sitting on the node.
// Entries die on a ten-second silence or when the node's renderer stops being
// alive, which is the same liveness test the glow uses and covers erasure
// (erase_object_renderer instance_destroys it, GridUtils.gml:170-174), room
// changes and quit-to-title in one line.
//
// ORDER WITHIN A FRAME, because the whole transient window rests on it:
// mmapi drains its installers at the very head of Game.step_begin, in front of
// TICK++ (seams.toml engine_fix game_step_begin_installs), and the player's
// swing runs later in the same frame from obj_ari's step. So our tick - and
// therefore pick_poll - is strictly BEFORE every pick_node call of its own
// frame, and any suppression pick_poll finds was necessarily written on an
// earlier frame. That is why the restore below needs no timestamp comparison of
// its own; note that it could not use one anyway, since the tick reads TICK one
// short of the value the filter will see.
//

// Lazily built, and [$ ]-guarded like the glow cache for the same reason: a
// global struct left behind by an older boot arrives without the field.
function yads_pick_state(_rt) {
    var _picks = _rt[$ "picks"];
    if (_picks == undefined) {
        _picks = { entries: [] };
        _rt.picks = _picks;
    }
    return _picks;
}

// Put the node back the way we found it. THE ONE PLACE our suppression is
// undone, called from the frame poll, from the empty-unit path in the filter and
// from the save handler, so there is exactly one spelling of "restore" to keep
// correct. Idempotent: an entry that is not holding anything costs one read.
//
// It writes `base`, never `true`. base is what the field held before our first
// write, so an engine-forced false (Furniture.gml:685-687, TileFlag.Unbreakable)
// is restored as false and stays as unbreakable as the engine meant it to be.
function yads_pick_release(_entry) {
    if (_entry.held != true) { return; }
    _entry.node.destructable = _entry.base;
    _entry.held = false;
}

// Per-frame restore, decay and liveness sweep, from the tick. In the steady
// state - which is every frame nobody is hitting a full crate - this is one
// struct read, one array_length and a return.
//
// THE RESTORE IS THE POINT, and it is why this runs unconditionally rather than
// on a timestamp: our tick is strictly ahead of every pick_node call in its own
// frame (see the ordering note in this section's header), so anything still
// suppressed when the poll sees it was suppressed on an EARLIER frame and its
// one-call transient window has closed. The flag therefore spends every frame
// except the one it is swung on holding the value the engine gave it, which is
// what keeps the save clean, keeps `can_pick_node` honest for the non-mouse aim
// path (a resting false makes the gamepad's target queue skip our unit and land
// the swing on whatever is behind it, obj_ari.gml:1032-1182), and makes an
// uninstalled mod leave nothing behind.
//
// Walked BACKWARDS so a delete cannot skip the next entry. The array is bounded
// by how many distinct units one player can swing at inside ten seconds, i.e.
// one, occasionally two.
function yads_pick_poll(_rt) {
    var _picks = _rt[$ "picks"];
    if (_picks == undefined) { return; }

    var _entries = _picks.entries;
    for (var _i = array_length(_entries) - 1; _i >= 0; _i--) {
        var _entry = _entries[_i];
        yads_pick_release(_entry);
        _entry.ttl -= 1;

        // instance_is_alive, not instance_exists: the same rule the whole mod
        // uses (GridUtils.gml:171), and the only one that is correct under
        // camera culling - an off-screen unit is DEACTIVATED, not dead, and
        // dropping its count would hand the player their five swings back for
        // walking two screens away.
        var _renderer = _entry.node[$ "renderer"];
        if (_entry.ttl <= 0 || _renderer == undefined || !instance_is_alive(_renderer)) {
            array_delete(_entries, _i, 1);
        }
    }
}

// Restore every live entry, for the save handler. Cheap - the array is empty
// unless a crate was swung at in the last ten seconds - and it is belt and
// braces over the poll, which has already restored everything the frame is not
// actively swinging at. What it covers is a save raised inside the same frame as
// a swing, where the poll has run but the filter has not.
function yads_pick_flush(_rt) {
    var _picks = _rt[$ "picks"];
    if (_picks == undefined) { return; }

    var _entries = _picks.entries;
    for (var _i = 0; _i < array_length(_entries); _i++) {
        yads_pick_release(_entries[_i]);
    }
}

// Restore and drop the entry for one node, if it has one. Called when a unit
// turns out to be empty: an empty unit has nothing to protect, so it should
// carry no state at all, and a stale count would otherwise let a crate that was
// emptied and refilled inside the ten-second window come apart early.
//
// It never CREATES an entry, and that is the "write true only if we were the
// ones holding it false" rule in code. Without it, an empty unit standing on an
// Unbreakable cell would be handed a `true` it was never supposed to have - the
// exact bug the deleted rescan derive shipped with.
function yads_pick_forget(_node) {
    var _picks = yads_runtime()[$ "picks"];
    if (_picks == undefined) { return; }

    var _entries = _picks.entries;
    for (var _i = array_length(_entries) - 1; _i >= 0; _i--) {
        if (_entries[_i].node != _node) { continue; }
        yads_pick_release(_entries[_i]);
        array_delete(_entries, _i, 1);
        return;
    }
}

// The count for one node, created at zero on first sight. Structs compare by
// reference on this runtime (mmapi_local.gml:22-23), so identity is the right
// key and there is no id to invent.
//
// `base` IS CAPTURED HERE AND NOWHERE ELSE, which is what makes it a base: this
// function runs exactly once per node per entry lifetime, and it runs before the
// filter's first write, so the value it reads is the engine's. Normalised
// through `!= false` because that is precisely the predicate both engine readers
// use (Pick.gml:33, :406) - a node whose field is somehow absent reads as
// destructable, and restoring it to a literal `true` means the same thing to
// both of them.
//
// `tick` starts at -1, a value TICK can never take (Tick.gml seeds global.__tick
// at 0 and Game.gml:571 only ever increments it), so the first swing always
// counts.
function yads_pick_entry(_node) {
    var _entries = yads_pick_state(
        yads_runtime()).entries;

    for (var _i = 0; _i < array_length(_entries); _i++) {
        if (_entries[_i].node == _node) { return _entries[_i]; }
    }

    var _entry = {
        node: _node,
        base: (_node[$ "destructable"] != false),
        count: 0,
        tick: -1,
        held: false,
        ttl: YADS_PICK_TTL,
    };
    array_push(_entries, _entry);
    return _entry;
}

// ONE-TIME REPAIR OF A CONTAMINATED SAVE, from the tick, once per load.
//
// WHY IT EXISTS. Everything above is about never writing a resting `false`.
// It says nothing about ones already written: a pre-release build of this mod
// derived destructable on a timer and left `false` on every non-empty unit, and
// that value round-trips through the player's save (see the serialization proof in
// this section's header). Load such a save under this build and pick_entry captures
// base = false - the mod would read its own past damage as the engine's
// Unbreakable force and preserve it forever, past uninstallation, with nothing
// anywhere telling the owner why their crate will not come apart.
//
// THE TWO STATES ARE DISTINGUISHABLE AND THE TEST IS THE ENGINE'S OWN. A false the
// engine meant is re-derived on every single load - write_furniture_to_location
// runs Furniture.gml:685-687 against grid.node_flags before the saved struct is
// walked back in - so "the prototype allows breaking AND no cell under the
// footprint carries TileFlag.Unbreakable AND the field is nevertheless false" is
// contamination and nothing else. Anything we cannot resolve (missing grid, cell
// off the grid, prototype without the field) is left exactly as it is: this
// function is only ever allowed to hand a permission back that the engine would
// have granted anyway.
//
// WHY IT IS NOT IN game_loaded. That hook fires at the START of the load
// (seams.toml save_game_loaded anchors on `Game.last_serde_path = loader.save_path;`
// - LoadGame.gml:10), which is before GRIDS is rebuilt and long before any
// furniture is written, and Game clears STORAGE_NODES on entry (Game.gml:28). There
// is nothing to walk yet. game_loaded therefore only re-arms the flag, and the
// repair runs from the tick on the first frame the world is actually up - the same
// shape ensure_recipes uses, and for the same reason.
//
// EXPOSURE, STATED HONESTLY. Only a save played under a pre-release build can
// carry this, so for anyone installing from a public release it is dead code. It
// is one walk of insurance against a class of damage that has no other way back,
// and it costs one struct read per frame once it has latched.
function yads_pick_repair(_rt) {
    if (_rt[$ "picks_repaired"] == true) { return; }

    // No player, no world, no minted ids - and yads_ids() must
    // not memoize off a fiddle table that has not merged yet, exactly as the glow
    // rescan and the filter both guard.
    if (!instance_exists(obj_ari)) { return; }

    var _list = global[$ "__STORAGE_NODES"];
    if (_list == undefined) { return; }

    // Latch BEFORE the walk. A repair that threw halfway would otherwise re-run
    // from the top every frame for the rest of the session, and there is nothing in
    // the walk worth retrying: the nodes it could not resolve this frame are the
    // ones it must not touch at all.
    _rt.picks_repaired = true;

    var _len = _list.count();
    for (var _i = 0; _i < _len; _i++) {
        var _node = _list.get(_i);
        if (!yads_is_member(_node)) { continue; }

        // The only value worth looking at. `!= false` is the predicate both engine
        // readers use (Pick.gml:33, :406), so this is "the engine considers this
        // node unbreakable" and not "the field happens to be missing".
        if (_node[$ "destructable"] != false) { continue; }

        // A prototype that forbids breaking is not ours to overrule. Ours inherit
        // the vanilla furniture [default]'s `destructable = true`.
        var _proto = _node[$ "prototype"];
        if (_proto == undefined || _proto[$ "destructable"] != true) { continue; }

        var _grid = _node[$ "parent_grid"];
        if (_grid == undefined) { continue; }

        // Footprint from the NODE, never prototype.size: rotation swaps the two
        // (Furniture.gml:2028-2035). Any cell we cannot resolve counts as forced,
        // which is the conservative direction.
        var _forced = false;
        var _w = _node.write_size_x;
        var _h = _node.write_size_y;
        for (var _cx = 0; _cx < _w; _cx++) {
            if (_forced) { break; }
            for (var _cy = 0; _cy < _h; _cy++) {
                var _ni = _grid.try_node_index_for_cell(
                    _node.top_left_x + _cx, _node.top_left_y + _cy);
                if (_ni == undefined) { _forced = true; break; }
                if (has_flag(_grid.node_flags[_ni], TileFlag.Unbreakable)) {
                    _forced = true;
                    break;
                }
            }
        }
        if (_forced) { continue; }

        // Drop any entry first. Nothing can have one this early in a load, but an
        // entry created before the repair would be carrying base = false and would
        // put the contamination straight back on the node at its next release.
        // pick_forget is the one spelling of "restore and drop" and costs a walk
        // over an array that is empty.
        yads_pick_forget(_node);
        _node.destructable = true;
    }
}

// Which node this swing is actually aimed at, replicating pick_node's own scan
// (Pick.gml:103-124) cell for cell.
//
// The order is the outer xx loop over the inner yy loop with a `breaker` that
// short-circuits both, i.e. (x,y) -> (x,y+1) -> (x+1,y) -> (x+1,y+1), FIRST HIT
// WINS. Replicating it rather than testing our own footprint is what keeps this
// honest when a unit shares the swing's 2x2 window with something else: whatever
// the engine is about to remove is what we have to reason about.
//
// A cell holding only a rug is a rug pick (Pick.gml:115-117 sets is_rug_pick and
// :403 takes node_rug_parent instead). None of our units is ever a rug, so that
// is somebody else's node and we decline - but it still has to STOP the scan,
// because it stopped the engine's.
function yads_pick_target(_grid, _x, _y) {
    for (var _xx = 0; _xx < 2; _xx++) {
        for (var _yy = 0; _yy < 2; _yy++) {
            var _ni = _grid.try_node_index_for_cell(_x + _xx, _y + _yy);
            if (_ni == undefined) { continue; }                 // off the grid

            var _object = _grid.node_object_id[_ni];
            if (_object == undefined) {
                if (_grid.node_rug_id[_ni] == undefined) { continue; }   // empty cell
                return undefined;                                       // rug pick
            }

            return _grid.node_parent[_ni];
        }
    }

    return undefined;
}

// The filter itself.
//
// IT NEVER CHANGES THE FILTERED VALUE. The value is the tool modifier - the
// charged-swing bonus added to item.damage and to the quality gate - and this
// mod has no opinion about it. Every path returns undefined, which
// mmapi_apply_filters reads with typeof() as "this handler declined" and leaves
// the current value alone (mmapi_hooks.gml:286-290). The work is done entirely
// through the side effect on the node, which the seam's position makes visible
// to the very swing that triggered us.
//
// It does READ the value, once, as the only discriminator available for
// "was this call a player swing?" - see the I32_MAX gate below. Reading a
// filtered value to decide is still declining to filter it.
//
// ORDERED CHEAPEST TEST FIRST, like object_interact's, and for a stronger
// reason: this fires on every pickaxe AND axe swing in the game, at a target
// that is usually a rock.
function yads_node_modifier(_modifier, _ctx) {
    if (_ctx == undefined) { return undefined; }
    if (_ctx[$ "action"] != "pick") { return undefined; }   // the axe shares this hook

    var _grid = _ctx[$ "grid"];
    if (_grid == undefined) { return undefined; }

    // The ctx is built by the seam, so these are always reals - checked anyway,
    // because a throw inside a filter is swallowed and logged by the dispatcher
    // (mmapi_hooks.gml:291-294) and would spend a warn on every swing forever.
    var _x = _ctx[$ "x"];
    var _y = _ctx[$ "y"];
    if (!is_real(_x) || !is_real(_y)) { return undefined; }

    // Before yads_ids() memoizes, and for the same reason the
    // glow rescan carries this guard: the memo is taken off the merged fiddle
    // tables and one taken too early sticks for the whole session. Every
    // pick_node caller in the corpus needs a live world already (AriFsm,
    // MonsterUtils, obj_damage_tarball, TestSuite, Mist/Std.gml:549), so this is
    // provably unreachable today - but the asymmetry with the rescan was not, and
    // the next hook wired into this handler would have inherited it.
    if (!instance_exists(obj_ari)) { return undefined; }

    var _ids = yads_ids();
    if (_ids.heart == undefined && _ids.block == undefined && _ids.panel == undefined) {
        return undefined;   // content not installed
    }

    var _node = yads_pick_target(_grid, _x, _y);
    if (!yads_is_member(_node)) { return undefined; }

    // EMPTY UNITS STAY ONE-HIT. Nothing to protect, no counter, no toast -
    // is_empty short-circuits on the first occupied slot (Inventory.gml:42-46).
    //
    // pick_forget rather than a write: it restores whatever WE put on the node
    // and then drops the entry, and it does nothing at all to a node we never
    // touched. A flat `destructable = true` here would instead announce every
    // empty unit as breakable, including the ones the engine had forced shut.
    var _inventory = _node[$ "inventory"];
    if (_inventory == undefined || _inventory.is_empty()) {
        yads_pick_forget(_node);
        return undefined;
    }

    var _entry = yads_pick_entry(_node);

    // AN ENGINE-UNBREAKABLE UNIT LEAVES BEFORE IT COSTS ANYTHING. base is false
    // only when the engine forced it (Furniture.gml:685-687, a unit standing on a
    // TileFlag.Unbreakable cell), and `base && intent` can never lift that - so
    // five swings buy nothing, fifty buy nothing, and counting them would be
    // bookkeeping for an event that cannot happen. Worse, the toast below would
    // promise a removal the engine will never perform, on top of vanilla's own
    // correct "that did not work" feedback (Pick.gml:451-460).
    //
    // It is reachable, which is why this is code and not a comment: hound_help.toml
    // entry 17 of tile_rule_to_tile_flag lists `unbreakable` AND `placeable` on one
    // cell, so the game ships a tile kind that accepts furniture and then welds it
    // shut. Any such cell inside a placeable_locations entry produces this.
    //
    // The entry survives the return and decays on its own TTL. That is deliberate:
    // dropping it here would re-derive base on every swing, and the whole point of
    // base is that it is read once, before our first write.
    if (!_entry.base) { return undefined; }

    _entry.ttl = YADS_PICK_TTL;

    // ONE COUNT PER FRAME, AND ONLY FOR A SWING THE PLAYER MADE. Two gates,
    // both in this condition:
    //
    //   * TICK. A charged swing calls pick_node once per overlapped target cell,
    //     2 to 6 times for our 4x2 footprint, all inside one frame - see the
    //     header. Counting per call let one charged swing spend the whole
    //     five-swing budget. Counting per frame is the swing.
    //   * I32_MAX. The Resonance perk (MonsterUtils.gml:110-141) and the
    //     Earthbreaker chain (Pick.gml:329-341) re-enter this seam on their own,
    //     with `modifier` hard-coded to I32_MAX; every player path passes 0 or -1
    //     (AriFsm.gml:2699), and so do bombs, cutscenes and the test suite. Both
    //     perk callers are Rock-gated at their call site, so they should not be
    //     able to resolve one of our units at all - but they scan their own 2x2
    //     window from a renderer position, which is not obliged to agree with
    //     ours, and an attempt the player did not make must not consume one of
    //     their five or fire the toast. The suppression below still applies to
    //     them: a perk chain can never take a full unit apart, it just does not
    //     move the counter.
    //     THE DISCRIMINATOR IS A READ OF SOMEBODY ELSE'S VALUE, and filters chain
    //     in registration order with each handler seeing the previous one's output
    //     (mmapi_hooks.gml:262-296), so another mod can move it either way. Both
    //     directions matter:
    //       * a filter that turns I32_MAX into anything else degrades this to "a
    //         perk swing counts", which is exactly the behaviour it replaces;
    //       * a filter that RETURNS I32_MAX - the obvious shape of an
    //         "instant-break tools" mod, copying the engine's own idiom from
    //         Pick.gml:338 - makes this test false on every player swing, so the
    //         count never leaves 0 and every non-empty unit stays un-pickable for
    //         as long as both mods are installed.
    //     The second is a real failure and it is not the benign one. It is still
    //     bounded: the flag rests at `base`, so no save is touched, uninstalling
    //     either mod ends it, and emptying the unit frees it immediately. Closing
    //     it properly needs a second discriminator (e.g. also requiring
    //     _ctx[$ "item"] to be the player's held tool prototype); it is left open
    //     deliberately because no such mod is known to exist and the extra gate
    //     would be untested against a real one.
    var _counted = false;
    if (_modifier != I32_MAX && _entry.tick != TICK) {
        _entry.tick = TICK;
        _entry.count += 1;
        _counted = true;
    }

    // THE RELEASE, AND THE BASE RULE IN ONE LINE. On the fifth counted swing the
    // intent goes true and pick_node - which has not read the field yet -
    // proceeds to the ordinary vanilla removal on THIS swing, not the next one.
    // Below five the intent is false and the swing bounces.
    //
    // STILL ANDed with base, even though the guard above has already sent every
    // base == false node home. The AND is the rule - we are allowed to take a
    // permission away for a moment, we are never allowed to grant one - and it
    // stays spelled out here so the rule lives at the write rather than three
    // screens above it. The early return is an optimisation and a bug fix (it stops
    // the counting and the toast); this line is the safety property, and it must
    // survive anyone moving that return.
    //
    // `held` is the record of whether the node is currently wearing a value that
    // is not its own, and it is what pick_poll undoes next frame. Deriving it as
    // "differs from base" rather than "is false" is what keeps the restore path
    // off a node we never changed.
    //
    // BEFORE THE TOAST, and the ordering is the same rule teardown states:
    // custody first, cosmetics last. create_notification derefs
    // ANCHOR.get_menu(Menu.InfoToasts) unguarded (InfoToastsMenu.gml:121-123)
    // and a throw inside a filter is swallowed by the dispatcher
    // (mmapi_hooks.gml:291-294), which would abandon the rest of this function.
    // With the write first, the worst a failed toast can cost is the message.
    var _flag = _entry.base && (_entry.count >= YADS_PICK_SWINGS);
    _node.destructable = _flag;
    _entry.held = (_flag != _entry.base);

    // One toast per attempt, on the first counted swing of a fresh counter. The
    // duck is keyed on the message (InfoToastsMenu.gml:21-24) and is now the same
    // length as the counter's own life, so a determined player is told once per
    // attempt and never twice inside one.
    if (_counted && _entry.count == 1) {
        create_notification(YADS_LOCAL_ROOT + "block_protected",
            YADS_PICK_DUCK);
    }

    return undefined;
}
