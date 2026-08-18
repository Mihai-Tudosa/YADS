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

    //
    // ============================ THE KEY LIST SEAM ============================
    //
    // THIS TABLE IS THE ONLY PLACE THE MOD ENUMERATES ITS PLACED CONTENT KEYS.
    // Membership, the interact ladder, the deposit-target set, the scan's heart
    // and panel counters and the offline face are all derived from it below, so
    // adding a unit is a row here plus its fiddle tables - and nothing else in
    // any .gml file.
    //
    // ADDING THE BETA 1.3 CRATE TWINS IS AN APPEND TO THIS ARRAY AND NOTHING
    // ELSE. The generator that emits the netstor_crate_<vanilla chest key>
    // tables into fiddle/object_prototypes/furniture.toml emits the matching
    // rows here, in the same deterministic order, each one shaped
    //     { key: "netstor_crate_<...>", kind: YADS_KIND_CRATE, slug: "<family>" },
    // where `slug` is the ART FAMILY, not the key: the loop below spells it
    // "spr_furniture_netstor_" + slug + "_offline", and one overlay pair is
    // shared by every twin of a family (crates/fam_basic_wood.py ->
    // spr_furniture_netstor_crate_basic_wood_glow/_offline, i.e. slug
    // "crate_basic_wood"). Nothing below counts the rows, assumes three, or
    // assumes the kinds are distinct - 59 rows all saying YADS_KIND_CRATE, many
    // of them sharing a slug, is the expected shape.
    //
    // A KEY THE INSTALLED CONTENT SET DOES NOT CARRY IS SILENTLY SKIPPED.
    // try_string_to_object_id returns an Option and never throws for an unknown
    // name (the magic-enum contract, mistria-sdk/asset-properties/magic-enums.md
    // :11-14; Grid.gml:1075-1082 leans on exactly that at load time), so an
    // unresolved row costs its unit its membership and costs every other row
    // nothing. That is what makes it safe for this list to name a key before the
    // fiddle ships it, and it is why the loop below `continue`s rather than
    // asserting.
    //
    // EVERY KEY HERE IS FROZEN THE MOMENT IT SHIPS. Grid.gml:1075-1082 drops a
    // saved node whose object_id string no longer resolves, and it drops it WITH
    // ITS WHOLE INVENTORY. Renaming a row is deleting players' items.
    //
    static UNIT_KEYS = [
        { key: "netstor_heart", kind: YADS_KIND_HEART, slug: "heart" },
        { key: "netstor_block", kind: YADS_KIND_CRATE, slug: "block" },
        { key: "netstor_panel", kind: YADS_KIND_PANEL, slug: "panel" },
        // THE FOUR CONNECTORS, spliced verbatim from
        // connector_unit_keys.generated.gml. Each is its own art family of one,
        // so slug == key minus "netstor_", and the loop below resolves
        // "spr_furniture_netstor_link_<x>_offline" for each.
        //
        // THEY ARE RUGS, and that is the whole reason they are in THIS table and
        // in no other. Membership is what the scan's flood needs in order to walk
        // THROUGH them; everything else the table feeds either skips them by
        // construction or never sees them at all:
        //   * kind -> YADS_KIND_LINK, which the scan treats as traversable
        //     frontier and section 9 tints cyan (yads_glow_tint's non-CRATE arm);
        //   * offline -> one face per connector IF the art layer ships the strip;
        //     see section 9's connector pass for what happens when it does not;
        //   * to_crate/to_chest -> NO ENTRY, and this is load-bearing rather than
        //     incidental: pass three's only filter is
        //     `string_copy(_key, 1, _plen) != CRATE_PREFIX`, and "netstor_link_"
        //     is not "netstor_crate_", so the pairing loop `continue`s on all
        //     four before it resolves anything. yads_crate_for_chest,
        //     yads_chest_for_crate and yads_shell_object therefore all return
        //     undefined for a connector, which is exactly how the converter and
        //     the upgrade gestures decline it - by a table miss, with no
        //     exclusion list and no new code. DO NOT EVER NAME A CONNECTOR
        //     "netstor_crate_*"; that one string would make it convertible.
        { key: "netstor_link_carpet", kind: YADS_KIND_LINK, slug: "link_carpet" },
        { key: "netstor_link_tile", kind: YADS_KIND_LINK, slug: "link_tile" },
        { key: "netstor_link_cables", kind: YADS_KIND_LINK, slug: "link_cables" },
        { key: "netstor_link_cloud", kind: YADS_KIND_LINK, slug: "link_cloud" },
        // basic_wood -- spr_furniture_netstor_crate_basic_wood_offline
        { key: "netstor_crate_basic_wood_chest_black", kind: YADS_KIND_CRATE, slug: "crate_basic_wood" },
        { key: "netstor_crate_basic_wood_chest_blue", kind: YADS_KIND_CRATE, slug: "crate_basic_wood" },
        { key: "netstor_crate_basic_wood_chest_cottage", kind: YADS_KIND_CRATE, slug: "crate_basic_wood" },
        { key: "netstor_crate_basic_wood_chest_dark", kind: YADS_KIND_CRATE, slug: "crate_basic_wood" },
        { key: "netstor_crate_basic_wood_chest_green", kind: YADS_KIND_CRATE, slug: "crate_basic_wood" },
        { key: "netstor_crate_basic_wood_chest_haunted_attic", kind: YADS_KIND_CRATE, slug: "crate_basic_wood" },
        { key: "netstor_crate_basic_wood_chest_light", kind: YADS_KIND_CRATE, slug: "crate_basic_wood" },
        { key: "netstor_crate_basic_wood_chest_medium", kind: YADS_KIND_CRATE, slug: "crate_basic_wood" },
        { key: "netstor_crate_basic_wood_chest_orange", kind: YADS_KIND_CRATE, slug: "crate_basic_wood" },
        { key: "netstor_crate_basic_wood_chest_pink", kind: YADS_KIND_CRATE, slug: "crate_basic_wood" },
        { key: "netstor_crate_basic_wood_chest_purple", kind: YADS_KIND_CRATE, slug: "crate_basic_wood" },
        { key: "netstor_crate_basic_wood_chest_red", kind: YADS_KIND_CRATE, slug: "crate_basic_wood" },
        { key: "netstor_crate_basic_wood_chest_white", kind: YADS_KIND_CRATE, slug: "crate_basic_wood" },
        { key: "netstor_crate_basic_wood_chest_witch_queen", kind: YADS_KIND_CRATE, slug: "crate_basic_wood" },
        { key: "netstor_crate_basic_wood_chest_yellow", kind: YADS_KIND_CRATE, slug: "crate_basic_wood" },
        // coral -- spr_furniture_netstor_crate_coral_offline
        { key: "netstor_crate_coral_storage_chest_blue", kind: YADS_KIND_CRATE, slug: "crate_coral" },
        { key: "netstor_crate_coral_storage_chest_purple", kind: YADS_KIND_CRATE, slug: "crate_coral" },
        // deluxe -- spr_furniture_netstor_crate_deluxe_offline
        { key: "netstor_crate_deluxe_storage_chest_aqua", kind: YADS_KIND_CRATE, slug: "crate_deluxe" },
        { key: "netstor_crate_deluxe_storage_chest_black", kind: YADS_KIND_CRATE, slug: "crate_deluxe" },
        { key: "netstor_crate_deluxe_storage_chest_blue", kind: YADS_KIND_CRATE, slug: "crate_deluxe" },
        { key: "netstor_crate_deluxe_storage_chest_dark_brown", kind: YADS_KIND_CRATE, slug: "crate_deluxe" },
        { key: "netstor_crate_deluxe_storage_chest_gold", kind: YADS_KIND_CRATE, slug: "crate_deluxe" },
        { key: "netstor_crate_deluxe_storage_chest_gray", kind: YADS_KIND_CRATE, slug: "crate_deluxe" },
        { key: "netstor_crate_deluxe_storage_chest_green", kind: YADS_KIND_CRATE, slug: "crate_deluxe" },
        { key: "netstor_crate_deluxe_storage_chest_light_brown", kind: YADS_KIND_CRATE, slug: "crate_deluxe" },
        { key: "netstor_crate_deluxe_storage_chest_orange", kind: YADS_KIND_CRATE, slug: "crate_deluxe" },
        { key: "netstor_crate_deluxe_storage_chest_pink", kind: YADS_KIND_CRATE, slug: "crate_deluxe" },
        { key: "netstor_crate_deluxe_storage_chest_purple", kind: YADS_KIND_CRATE, slug: "crate_deluxe" },
        { key: "netstor_crate_deluxe_storage_chest_red", kind: YADS_KIND_CRATE, slug: "crate_deluxe" },
        { key: "netstor_crate_deluxe_storage_chest_white", kind: YADS_KIND_CRATE, slug: "crate_deluxe" },
        // dragon -- spr_furniture_netstor_crate_dragon_offline
        { key: "netstor_crate_dragon_chest", kind: YADS_KIND_CRATE, slug: "crate_dragon" },
        // flower -- spr_furniture_netstor_crate_flower_offline
        { key: "netstor_crate_spring_festival_flower_chest", kind: YADS_KIND_CRATE, slug: "crate_flower" },
        // fridge -- spr_furniture_netstor_crate_fridge_offline
        { key: "netstor_crate_cottage_fridge_v1", kind: YADS_KIND_CRATE, slug: "crate_fridge" },
        { key: "netstor_crate_cottage_fridge_v2", kind: YADS_KIND_CRATE, slug: "crate_fridge" },
        // icebox -- spr_furniture_netstor_crate_icebox_offline
        { key: "netstor_crate_deluxe_icebox_blue", kind: YADS_KIND_CRATE, slug: "crate_icebox" },
        { key: "netstor_crate_deluxe_icebox_green", kind: YADS_KIND_CRATE, slug: "crate_icebox" },
        { key: "netstor_crate_deluxe_icebox_pink", kind: YADS_KIND_CRATE, slug: "crate_icebox" },
        { key: "netstor_crate_deluxe_icebox_white", kind: YADS_KIND_CRATE, slug: "crate_icebox" },
        { key: "netstor_crate_deluxe_icebox_yellow", kind: YADS_KIND_CRATE, slug: "crate_icebox" },
        // mimic -- spr_furniture_netstor_crate_mimic_offline
        { key: "netstor_crate_mimic_storage_chest", kind: YADS_KIND_CRATE, slug: "crate_mimic" },
        // miners -- spr_furniture_netstor_crate_miners_offline
        { key: "netstor_crate_miners_crate_chest_v1", kind: YADS_KIND_CRATE, slug: "crate_miners" },
        { key: "netstor_crate_miners_crate_chest_v2", kind: YADS_KIND_CRATE, slug: "crate_miners" },
        // mist -- spr_furniture_netstor_crate_mist_offline
        { key: "netstor_crate_mist_storage_chest_v1", kind: YADS_KIND_CRATE, slug: "crate_mist" },
        { key: "netstor_crate_mist_storage_chest_v2", kind: YADS_KIND_CRATE, slug: "crate_mist" },
        { key: "netstor_crate_mist_storage_chest_v3", kind: YADS_KIND_CRATE, slug: "crate_mist" },
        { key: "netstor_crate_mist_storage_chest_v4", kind: YADS_KIND_CRATE, slug: "crate_mist" },
        // obsidian -- spr_furniture_netstor_crate_obsidian_offline
        { key: "netstor_crate_lava_caves_obsidian_storage_chest_blue", kind: YADS_KIND_CRATE, slug: "crate_obsidian" },
        { key: "netstor_crate_lava_caves_obsidian_storage_chest_purple", kind: YADS_KIND_CRATE, slug: "crate_obsidian" },
        // royal -- spr_furniture_netstor_crate_royal_offline
        { key: "netstor_crate_royal_chest_blue", kind: YADS_KIND_CRATE, slug: "crate_royal" },
        { key: "netstor_crate_royal_chest_dark_wood", kind: YADS_KIND_CRATE, slug: "crate_royal" },
        { key: "netstor_crate_royal_chest_green", kind: YADS_KIND_CRATE, slug: "crate_royal" },
        { key: "netstor_crate_royal_chest_purple", kind: YADS_KIND_CRATE, slug: "crate_royal" },
        { key: "netstor_crate_royal_chest_red", kind: YADS_KIND_CRATE, slug: "crate_royal" },
        { key: "netstor_crate_royal_chest_wood", kind: YADS_KIND_CRATE, slug: "crate_royal" },
        // stone -- spr_furniture_netstor_crate_stone_offline
        { key: "netstor_crate_stone_storage_chest_v1", kind: YADS_KIND_CRATE, slug: "crate_stone" },
        { key: "netstor_crate_stone_storage_chest_v2", kind: YADS_KIND_CRATE, slug: "crate_stone" },
        { key: "netstor_crate_stone_storage_chest_v3", kind: YADS_KIND_CRATE, slug: "crate_stone" },
        // void -- spr_furniture_netstor_crate_void_offline
        { key: "netstor_crate_void_storage_chest_v1", kind: YADS_KIND_CRATE, slug: "crate_void" },
        { key: "netstor_crate_void_storage_chest_v2", kind: YADS_KIND_CRATE, slug: "crate_void" },
    ];
    //
    // ========================== END THE KEY LIST SEAM ==========================
    //

    // Pass one: resolve, and find the largest id we own.
    //
    // The tables below are sized from THAT rather than from ObjectId.LEN.
    // ObjectId.LEN is the engine's own idiom for an ObjectId-keyed array
    // (GridPrototypes.gml:65, GrowBack.gml:7, Ari.gml:24) and it would work, but
    // it allocates ~1738 cells to describe at most 62 keys and it means naming a
    // member of a generated enum from mod GML - the one habit this whole section
    // exists to break. Max-resolved is smaller, mentions no enum, and costs one
    // bounds test per read, which every read needs anyway (see yads_kind_at).
    var _rows = array_length(UNIT_KEYS);
    var _resolved = array_create(_rows, undefined);
    var _top = -1;
    for (var _i = 0; _i < _rows; _i++) {
        var _id = try_string_to_object_id(UNIT_KEYS[_i].key);
        _resolved[_i] = _id;
        if (_id != undefined && _id > _top) { _top = _id; }
    }

    // Pass two: stamp. `undefined` is the fill AND the answer for "not ours", so
    // the ~1700 cells we never write are already correct. _top is -1 when nothing
    // resolved and array_create(0, ...) is an empty array, which every reader
    // then bounds-rejects - the same fail-open the whole section takes on a
    // partial content set.
    var _kind = array_create(_top + 1, undefined);
    var _offline = array_create(_top + 1, undefined);
    // Same length and the same undefined fill as `offline`, and read under the
    // same bounds rule. Only the four connector rows ever get an entry.
    var _glow_v = array_create(_top + 1, undefined);
    var _offline_v = array_create(_top + 1, undefined);
    // THE OVERLAY DEPTH POLICY. `true` = pin this key's top_sheet_renderer into
    // the floor band; undefined (the fill, and the answer for all 58 other keys
    // plus the Cloud) = leave it on the y-sorted depth the engine gave it. See
    // yads_glow_apply's pin for what the band is and why only three keys want
    // it.
    var _glow_floor = array_create(_top + 1, undefined);
    for (var _i = 0; _i < _rows; _i++) {
        var _id = _resolved[_i];
        if (_id == undefined) { continue; }            // key not installed
        _kind[_id] = UNIT_KEYS[_i].kind;

        // THE OFFLINE FACE, RESOLVED HERE INSTEAD OF PER RESCAN. Section 9 used
        // to call try_string_to_asset three times inside yads_glow_rescan and
        // argued that three lookups on an event-driven rebuild were cheaper than
        // a memo with a lifetime of its own to get wrong. At sixty-two keys that
        // trade inverts: the rescan runs up to once a second on the
        // YADS_GLOW_TTL backstop, so it would be ~62 string-keyed asset lookups
        // per second forever. This memo has no lifetime of its own to get wrong
        // either - it is the ids memo, which already dies on save.game_loaded,
        // strictly more often than an asset table can be re-minted.
        _offline[_id] = try_string_to_asset(
            "spr_furniture_netstor_" + UNIT_KEYS[_i].slug + "_offline");

        // THE D2 "WOVEN" AUTOTILE VARIANT TABLES, connectors and nothing else.
        //
        // A connector's OVERLAY cannot carry its adjacency variant in
        // image_index the way its BODY does - the overlay's frames are its
        // eight-frame pulse - so each variant is a separately named sprite and
        // the runtime picks one by name, which is the same swap this section
        // already performs between `_glow` and `_offline`. Sixteen of them, one
        // per NSEW mask, resolved HERE for the same reason `_offline` is:
        // yads_glow_rescan re-dirties once a second forever, and 4 keys x 32
        // string-keyed asset lookups per second is not a thing to do to a frame
        // budget. This memo dies on save.game_loaded, strictly more often than
        // the asset table can be re-minted.
        //
        // GATED ON THE KIND so the other 58 keys cost nothing: a crate twin has
        // no adjacency and no variants, and asking for
        // "spr_furniture_netstor_crate_royal_glow_v7" 59 times a save load
        // would be 944 lookups for a guaranteed miss.
        //
        // A MISS IS THE WHOLE FAIL-SOFT. yads_variant_assets returns undefined
        // when the art layer shipped no variant at all (an art tree older than
        // this GML), and yads_glow_apply then falls back to the unsuffixed
        // `_glow` / `_offline` - which for the glow is byte-identical to the
        // v0 (isolated) variant, so the connectors go back to looking exactly
        // like Beta 1.3 rather than looking broken. `_offline_v*` legitimately
        // misses for three of the four: only the Cloud ships offline variants,
        // because only the Cloud's body lives in its overlay.
        if (UNIT_KEYS[_i].kind == YADS_KIND_LINK) {
            _glow_v[_id] = yads_variant_assets(
                "spr_furniture_netstor_" + UNIT_KEYS[_i].slug + "_glow_v");
            _offline_v[_id] = yads_variant_assets(
                "spr_furniture_netstor_" + UNIT_KEYS[_i].slug + "_offline_v");

            // THE FLAT THREE WANT THEIR GLOW IN THE FLOOR BAND; THE CLOUD DOES
            // NOT. A carpet, a tile and a cable bundle are floor coverings and
            // their overlay is light lying ON that floor, so it must never be
            // in front of a chest standing on it - which is the 1.3c bug (see
            // yads_glow_apply's pin). The Cloud's overlay is not a marking, it
            // IS the cloud, drawn twelve rows up and floating clear of the
            // ground; pinning it to the floor would bury a floating object
            // under every crate in the room. Its `top_sprite_depth_offset = 2`
            // and its y-sort are the whole reason it reads as airborne.
            //
            // SELECTED BY SLUG, once per save load rather than per frame, and
            // spelled as "not the Cloud" so a fifth FLAT connector inherits the
            // right answer by default while a second FLOATING one has to come
            // here and say so. Four string compares per ids rebuild; the
            // per-frame path reads a bool off its cache entry and does no
            // lookup at all.
            if (UNIT_KEYS[_i].slug != "link_cloud") { _glow_floor[_id] = true; }
        }
    }

    // Pass three: THE CONVERSION PAIRS, both directions, derived from the same
    // seam and from nothing else.
    //
    // A twin's key IS its source's key with one prefix on the front - that is
    // the naming rule the content wave shipped under - so the pairing needs no
    // second table to fall out of step with UNIT_KEYS. Strip the prefix,
    // resolve what is left, and stamp both directions.
    //
    // THIS IS WHAT MAKES THE THREE EXCLUDED CHESTS SAFE WITH NO SPECIAL CASE.
    // stable_storage_chest, turn_in_box and starter_shipping_box have no twin,
    // so no row here names them, so no entry is ever stamped for them and the
    // converter gesture reads `undefined` and defers to vanilla. Same for every
    // chest another mod ships, every factory, and the AutoFeeder (which carries
    // a 54-slot inventory and no interaction_chest at all, Furniture.gml:865).
    // An exclusion list would have been a second place to be wrong; there is no
    // list.
    //
    // BOTH LOOKUPS ARE ObjectId-INDEXED ARRAYS, like `kind` and `offline`, and
    // for the same reason - but they get their OWN length, because a source's
    // id can be larger than any of ours. ObjectIds are minted alphabetically
    // over the whole merged content set, and `royal_*`, `spring_festival_*`,
    // `stone_*` and `void_*` all sort after "netstor", so `_top` above is not an
    // upper bound here. Every reader bounds-guards its own array; that rule is
    // what lets the four arrays disagree about length.
    //
    // `netstor_block` is a CRATE whose key carries no prefix, so it is skipped
    // by the string test and has no downgrade target. Correct: it is the mod's
    // own unit, not a converted chest, and there is nothing to hand back.
    static CRATE_PREFIX = "netstor_crate_";
    var _plen = string_length(CRATE_PREFIX);
    var _source = array_create(_rows, undefined);
    var _pair_top = -1;
    for (var _i = 0; _i < _rows; _i++) {
        var _id = _resolved[_i];
        if (_id == undefined) { continue; }
        var _key = UNIT_KEYS[_i].key;
        if (string_copy(_key, 1, _plen) != CRATE_PREFIX) { continue; }
        var _src = try_string_to_object_id(string_delete(_key, 1, _plen));
        if (_src == undefined) { continue; }   // source chest not installed
        _source[_i] = _src;
        if (_src > _pair_top) { _pair_top = _src; }
        if (_id > _pair_top) { _pair_top = _id; }
    }

    var _to_crate = array_create(_pair_top + 1, undefined);
    var _to_chest = array_create(_pair_top + 1, undefined);
    for (var _i = 0; _i < _rows; _i++) {
        var _src = _source[_i];
        if (_src == undefined) { continue; }
        _to_crate[_src] = _resolved[_i];
        _to_chest[_resolved[_i]] = _src;
    }

    // remote_item IS SPELLED DIFFERENTLY BECAUSE IT IS A DIFFERENT KIND OF
    // NUMBER. `kind` and `heart` are ObjectIds - grid nodes, compared against
    // node.object_id. The remote is not placeable and has no prototype, so it
    // only ever exists as an ItemId, compared against live_item.item_id. Both
    // enums are minted per load and both renumber, so both belong in this memo
    // and both die on save.game_loaded; the name is what stops a future reader
    // from testing an ItemId against a node.
    //
    // `heart` is the one named ObjectId left, and it stays because the heart is
    // and remains a SINGLETON: the remote binding scan looks for "the node that
    // is a heart holding a remote" (boot.gml section 5c) and the glow rescan's
    // installed-guard asks "did the heart key resolve at all". Both are cheaper
    // and clearer as one number than as a table walk.
    //
    // DELIBERATELY ABSENT: `block` and `panel`. Every reader of those two became
    // a kind test in Beta 1.3, and leaving the names here would invite the next
    // reader to write `_object_id == _ids.block` again - which is precisely the
    // bug the table exists to prevent, because a crate twin is a full member and
    // is not netstor_block.
    _rt.ids = {
        heart: try_string_to_object_id("netstor_heart"),
        remote_item: try_string_to_item_id("netstor_remote"),
        // The Network Converter, and an ItemId for the same reason
        // remote_item is one: it is not placeable, has no prototype, and is
        // only ever compared against live_item.item_id.
        converter_item: try_string_to_item_id("netstor_converter"),
        // source chest ObjectId -> its twin's, and back. See pass three.
        to_crate: _to_crate,
        to_chest: _to_chest,
        // object_id -> YADS_KIND_*, or undefined for "not one of ours".
        kind: _kind,
        // object_id -> the unit's offline-face sprite asset, or undefined when
        // the art layer did not ship one (that unit then falls back to the
        // visible-toggle path in yads_glow_apply).
        offline: _offline,
        // object_id -> a 16-entry array of overlay sprites indexed by NSEW
        // adjacency mask, or undefined for "this key has no autotile variants"
        // (every key that is not a connector, plus the offline table's three
        // flat connectors). THE ONLY PLACE THE VARIANT STATE LIVES IS HERE AND
        // IN THE GLOW CACHE - never on a placed node. See yads_scan's note and
        // Grid.gml:1444-1449: the serializer copies every struct field it does
        // not recognise straight into the player's save, and rugs ride the same
        // walker, so a `node.yads_mask = 6` would be written to disk, read back
        // forever, and be wrong the moment the neighbour changed.
        glow_variants: _glow_v,
        offline_variants: _offline_v,
        // object_id -> true when this key's OVERLAY belongs in the floor band
        // rather than on the y-sorted depth the engine gives it, undefined for
        // everything else. Same ObjectId-indexed shape and same bounds rule as
        // the four tables above; read once per cache build, never per frame.
        glow_floor: _glow_floor,
        // Did ANY placed unit key resolve? The "is our content installed at all"
        // guard, replacing the three-way `heart == undefined && block ==
        // undefined && panel == undefined` test that predated the table.
        any: (_top >= 0),
    };
    return _rt.ids;
}

// ---------------------------------------------------------------------------
// THE ADJACENCY MASK - the engine's own fence bit order, and not ours to pick.
// ---------------------------------------------------------------------------
// inner_fence_auto_tile (Furniture.gml:2193) ends:
//
//     return (1 * north) + (2 * west) + (4 * east) + (8 * south);
//
// and the value goes straight into renderer.image_index, re-asserted after
// every renderer rebuild with image_speed = 0 (Furniture.gml:1265-1271). Our
// connectors do exactly that, so we take exactly that bit order: one autotile
// convention in the process instead of two, and a future reader who has learned
// the engine's fences has already learned ours.
//
// The mask has exactly two consumers, and neither of them is has_flag: it is
// BUILT with set_flag (the pairwise sweep in section 9) and then READ as an
// integer - as `renderer.image_index` for the body and as an array index into
// the per-key variant tables for the overlay. (has_flag does appear in section
// 2, on yads_scan's own visited bitmap, which is a different value entirely.)
// The mask is NEVER persisted - it is recomputed from scratch on every rescan
// and lives only in the glow cache.
#macro YADS_DIR_N 1
#macro YADS_DIR_W 2
#macro YADS_DIR_E 4
#macro YADS_DIR_S 8
#macro YADS_MASK_LEN 16          // 2^4 - one sprite / one body frame per mask

// The opposite compass bit. `yads_glow_side(a, b)` answers "which side of a is
// b on"; b's own mask needs the mirror of that, and mirroring it is cheaper and
// less error-prone than asking the same question twice with the arguments
// swapped.
function yads_dir_opposite(_dir) {
    if (_dir == YADS_DIR_N) { return YADS_DIR_S; }
    if (_dir == YADS_DIR_S) { return YADS_DIR_N; }
    if (_dir == YADS_DIR_W) { return YADS_DIR_E; }
    if (_dir == YADS_DIR_E) { return YADS_DIR_W; }
    return 0;
}

// Resolve a 16-entry autotile variant table by name: `<prefix>0` .. `<prefix>15`.
//
// ALL-OR-NOTHING BY DESIGN at the table level and per-entry inside it. If not a
// single name resolves the whole table comes back undefined, which is the
// caller's "this key has no variants" and costs yads_glow_apply one compare
// instead of a per-frame array read that can only ever miss. If SOME resolve,
// the table is kept with undefined holes and each hole falls back individually
// - a half-shipped art tree then shows the right variant where it has one and
// the isolated face where it does not, which is legible; refusing the whole
// table would instead throw away sixteen good sprites because of one bad one.
function yads_variant_assets(_prefix) {
    var _out = array_create(YADS_MASK_LEN, undefined);
    var _any = false;
    for (var _k = 0; _k < YADS_MASK_LEN; _k++) {
        var _asset = try_string_to_asset(_prefix + string(_k));
        _out[_k] = _asset;
        if (_asset != undefined) { _any = true; }
    }
    if (!_any) { return undefined; }
    return _out;
}

// Bounds-guarded read of the ObjectId-indexed kind table: YADS_KIND_* for one of
// ours, undefined for everything else in the game.
//
// _kinds is passed in rather than fetched, so a loop pays one yads_ids() call and
// one struct read for the whole walk instead of one per node.
//
// THE BOUNDS TEST IS NOT DECORATION, and the case is easy to construct: the table
// is sized from the largest id the MOD resolved, ObjectIds are minted
// alphabetically over the whole merged content set, and any other mod whose
// object keys sort after "netstor_*" mints ids past the end of it. Those nodes
// must read as "not ours", never fault - this runs inside a BFS inside a think,
// where a throw is uncaught and repeats every frame. Same guard, same reason and
// same shape as yads_museum_needed.
function yads_kind_at(_kinds, _object_id) {
    if (_object_id == undefined) { return undefined; }
    if (_object_id < 0 || _object_id >= array_length(_kinds)) { return undefined; }
    return _kinds[_object_id];
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
//
// ONE BOUNDS-GUARDED ARRAY READ, and the shape matters more than it looks. This
// is the hottest predicate in the mod, on two independent axes:
//
//   * yads_scan_probe calls it once per ring cell - 12 for a 4x2 footprint - for
//     every node the BFS touches, so a 50-unit network is ~600 calls inside the
//     single frame a menu opens;
//   * yads_glow_rescan calls it once per STORAGE_NODES entry, i.e. once per
//     inventory-bearing node in the ENTIRE save, every location, up to once a
//     second on the YADS_GLOW_TTL backstop.
//
// The pre-1.3 body was three id compares. Three was fine for three keys; with
// sixty-two it would have been sixty-two, i.e. ~37k compares on the menu-open
// frame and ~18k a second on the rescan. This is one read regardless of key
// count, and it is cheaper than the three compares it replaces.
//
// Inlined rather than routed through yads_kind_at because at this call frequency
// the helper's own call frame is the dominant cost, and its body is these three
// lines.
function yads_is_member(_node) {
    if (_node == undefined) { return false; }

    var _object_id = _node[$ "object_id"];
    if (_object_id == undefined) { return false; }

    var _kinds = yads_ids().kind;
    if (_object_id < 0 || _object_id >= array_length(_kinds)) { return false; }
    return _kinds[_object_id] != undefined;
}

//
// 2. NETWORK SCAN (breadth-first, two layers, footprint + ring)
//
// Adjacency is "our footprints share an orthogonal grid edge, OR one is laid
// under the other". The ring of cells immediately outside a footprint carries
// the first relation and the footprint's own interior carries the second, so we
// walk footprint + ring per node - O(area + perimeter). The ring never visits
// the four diagonal corners, which is what makes the edge relation
// orthogonal-only rather than "touching at a corner counts".
//
// Two rules that are easy to get wrong:
//   * footprint comes from write_size_x/write_size_y on the NODE, never
//     prototype.size - a rotated object swaps them (Furniture.gml:2028-2035);
//   * a network never leaves its Grid. Every location has its own Grid struct
//     and crossing them has no spatial meaning, so we compare parent_grid by
//     reference on every neighbour.
//
// ---------------------------------------------------------------------------
// THE SECOND LAYER - CONNECTORS (Beta 1.3)
// ---------------------------------------------------------------------------
// A Grid stores TWO independent occupancy layers per cell (Grid.gml:20-21):
//
//   node_object_id[] / node_parent[]       ordinary furniture - chests, units
//   node_rug_id[]    / node_rug_parent[]   RUGS - our four connectors
//
// They are genuinely independent. write_furniture_to_location's rug arm writes
// ONLY the two rug arrays and never node_object_id, never collision
// (Furniture.gml:668-675), and can_write_object_on_node allows a unit ON a rug
// cell and a rug UNDER a Furniture-category object (GridUtils.gml:70-83). So a
// crate and a connector can and routinely will occupy the SAME cell.
//
// That is the whole feature: a connector extends adjacency. A unit beside one
// joins, a unit standing on one joins, and connectors chain to each other - so a
// carpet path across the farm links its two ends. The probe below therefore
// reads BOTH layers at every cell of footprint + ring, and a LINK popped off the
// frontier is walked exactly like a unit.
//
// A LINK CONTRIBUTES NOTHING BUT REACH. It has no inventory (a rug prototype
// declares no interaction_chest), so it falls outside the
// `inventory != undefined` guard below and enters neither `members` nor
// `deposit_targets` nor `panels`. The aggregate index, the projection, the
// reconciler, yads_has_room, yads_deposit_fit and the status popup's block count
// are all built on those three and are byte-identical in behaviour with
// connectors on the network. THE CUSTODY SURFACE OF A CONNECTOR IS ZERO BY
// CONSTRUCTION, not by a filter somebody has to remember - which is why section
// 8 took no edit for this feature and must not acquire one.
//
// Returns { members: [node...], deposit_targets: [node...], links: [node...],
// hearts: n, panels: n, grid: <Grid> }.
//
// LINKS is the connectors the walk crossed. Nothing in the mod requires it
// today - the glow runs its own flood off the cached units in section 9, and the
// status popup deliberately does NOT print a connector count (a capacity report
// has no row for a thing with no capacity, and its row budget is already the
// binding constraint). It is here because the walk knows the answer for free and
// because "how many connectors is this network standing on" is the one question
// a future diagnostic surface would ask.
//
// MEMBERS are every node on the network that carries an inventory - all three of
// ours do, but the check is there so a future memberless unit cannot crash the
// index. Members are what the aggregate index reads and what withdrawals drain:
// everything the network holds is visible and retrievable, wherever it sits.
//
// DEPOSIT_TARGETS are the CRATES, and only the crates - every unit whose kind is
// YADS_KIND_CRATE, which is netstor_block plus every netstor_crate_* twin.
// Storage capacity is the crate's job, so nothing the mod does ever pushes an
// item into a heart or a panel. Built here, in the same BFS pass, so that "who
// can receive a deposit" is one named piece of scan output rather than the same
// object_id test repeated in three hot loops that could drift apart.
//
// IT IS A KIND TEST AND NOT AN ID TEST FOR A REASON THAT COSTS ITEMS IF GOT
// WRONG: a network built entirely out of crate twins would have zero deposit
// targets under an id test, yads_has_room would report "full" forever, and every
// deposit would bounce back to the player with a "network full" toast on a
// network that is mostly empty. Nothing downstream has to change for a longer
// list - yads_has_room and yads_deposit_fit both walk it by array_length and read
// only `inventory` off each entry, and mixed capacities in one list are already
// the shipped case (heart 54, block 30, panel 4).
//
// PANELS is the count of Access Panels, for the same reason and by the same rule:
// "does this network have a browsing surface at all" is a question TWO surfaces
// ask - the interaction ladder, to decide whether sealing a block would strand
// its contents, and the heart's status popup, to decide whether to print the
// "craft an Access Panel" pointer. Both read this one number rather than walking
// the member list twice; two independent walks of one list are two things that
// can drift apart.
//
// The two visited BITS, one per occupancy layer. See yads_scan's note on why a
// single boolean per cell is not enough once rugs are in the walk.
//
// Values 1 and 2 are the two low bits and nothing else depends on them; they are
// consumed only by has_flag/set_flag inside this section and are never persisted,
// never compared against an engine enum and never written onto a node.
#macro YADS_SEEN_OBJ 1
#macro YADS_SEEN_RUG 2

function yads_scan(_start) {
    var _result = { members: [], deposit_targets: [], links: [], hearts: 0, panels: 0, grid: undefined };

    var _grid = _start[$ "parent_grid"];
    if (_grid == undefined) { return _result; }
    _result.grid = _grid;

    // Hoisted once for the whole walk: one yads_ids() call and one struct read,
    // then a plain array read per frontier pop.
    var _kinds = yads_ids().kind;

    // ---------------------------------------------------------------------
    // THE VISITED SET IS A LOCAL BITMASK, AND IT MUST STAY LOCAL.
    // ---------------------------------------------------------------------
    // Visited is keyed by the neighbour's ANCHOR cell, because a long shared edge
    // resolves to the same parent struct at several ring cells.
    //
    // ONE ARRAY, TWO BITS, because the two layers can legally anchor at the SAME
    // cell index: a crate at (10,10) standing on a connector at (10,10) gives two
    // distinct nodes one anchor, and a plain boolean array would silently drop
    // whichever the walk reached second - the exact configuration the feature
    // exists to support. has_flag/set_flag are the engine's own accessors
    // (Utilities/Bitflags.gml:14, :33), so check_symbols.py resolves them and no
    // bitwise operator appears in mod GML.
    //
    // Allocation is UNCHANGED from the pre-1.3 walk: one array_create(node_len),
    // filled with 0 instead of `false`. Nothing per cell, nothing per probe.
    //
    // ***** NEVER STAMP THE VISITED MARK ON A NODE STRUCT. *****
    // The obvious implementation - `node.yads_seen = true` - would write into the
    // player's SAVE and stay there forever. create_grid_object_serialization_data
    // walks struct_get_names(parent) and its default arm is a verbatim
    // `o[$ n] = parent[$ n]` (Grid.gml:1444-1449) over every name not in its
    // eight-entry skip list; the load walker's skip list (Grid.gml:1255) omits
    // unknown names too, so the field round-trips. Rugs ride that exact same
    // walker - the serializer pushes node_rug_parent entries into the same
    // object_list as ordinary nodes (Grid.gml:1298-1301) - so a connector is no
    // safer to stamp than a crate is. (This is the same mechanism
    // docs/safety-invariants.md proves for `node.destructable`, pointed the other
    // way: there the round trip is a hazard to respect, here it is a hazard to
    // stay out of entirely.) A local array cannot be serialized because nothing
    // reachable from a node points at it.
    var _visited = array_create(_grid.node_len, 0);

    // The start node is always an OBJECT node: yads_scan is called from
    // object.interact with the pressed node, and from yads_remote_scan with a
    // heart. A rug registers no interaction and is never in STORAGE_NODES, so
    // neither caller can hand us one - and if a future caller did, seeding the
    // wrong bit costs one redundant re-push, not a wrong answer.
    _visited[_grid.node_index_for_cell(_start.top_left_x, _start.top_left_y)] = YADS_SEEN_OBJ;

    // Plain growable array + read cursor. This codebase uses no ds_queue anywhere.
    var _frontier = [_start];
    var _head = 0;

    while (_head < array_length(_frontier)) {
        var _current = _frontier[_head];
        _head += 1;

        // One table read per popped node, then three integer compares against
        // it. The start node is the only entry that did not come through
        // yads_is_member, so the bounds guard inside yads_kind_at is load-bearing
        // here too: yads_scan is called on whatever node the caller was handed.
        var _kind = yads_kind_at(_kinds, _current[$ "object_id"]);

        if (_kind == YADS_KIND_HEART) {
            _result.hearts += 1;
        }
        // Connectors, counted OUTSIDE the members guard because that is the whole
        // point of them: a LINK has no inventory and must stay out of the three
        // lists below, which are the mod's entire custody vocabulary.
        if (_kind == YADS_KIND_LINK) {
            array_push(_result.links, _current);
        }
        if (_current[$ "inventory"] != undefined) {
            array_push(_result.members, _current);
            if (_kind == YADS_KIND_CRATE) {
                array_push(_result.deposit_targets, _current);
            }
            // Counted inside the members branch, not beside it, so this number
            // is exactly "panels a walk of _members would have found".
            if (_kind == YADS_KIND_PANEL) {
                _result.panels += 1;
            }
        }

        // Rug nodes carry top_left_x/y and write_size_x/y exactly like object
        // nodes: both layers are built by the same create_parent_object_node
        // (Furniture.gml:647, GridUtils.gml:84-95), and the rug arm changes only
        // WHICH cell arrays get written. So one footprint derive serves both.
        var _x0 = _current.top_left_x;
        var _y0 = _current.top_left_y;
        var _w = _current.write_size_x;
        var _h = _current.write_size_y;

        // THE RING - the edge relation. Cells immediately outside the footprint,
        // orthogonal only.
        for (var _i = 0; _i < _w; _i++) {
            yads_scan_probe(_grid, _x0 + _i, _y0 - 1, _visited, _frontier);
            yads_scan_probe(_grid, _x0 + _i, _y0 + _h, _visited, _frontier);
        }
        for (var _j = 0; _j < _h; _j++) {
            yads_scan_probe(_grid, _x0 - 1, _y0 + _j, _visited, _frontier);
            yads_scan_probe(_grid, _x0 + _w, _y0 + _j, _visited, _frontier);
        }

        // THE FOOTPRINT - the overlap relation, and the only way to see the OTHER
        // layer at our own cells: a connector laid under this unit, or a unit
        // standing on this connector. Self-hits on our own layer cost one array
        // read and one has_flag, because our own anchor is already marked.
        for (var _i = 0; _i < _w; _i++) {
            for (var _j = 0; _j < _h; _j++) {
                yads_scan_probe(_grid, _x0 + _i, _y0 + _j, _visited, _frontier);
            }
        }
    }

    return _result;
}

// One cell, BOTH layers. Split from yads_scan_take so that "which cells do we
// look at" and "what counts as a neighbour" stay two separate questions.
//
// COST, MEASURED AGAINST THE PRE-1.3 WALK. Cells probed per popped node goes
// 2(w+h) -> 2(w+h) + w*h, and layer reads per cell go 1 -> 2:
//
//   4x2 unit         12 cells / 12 layer-reads  ->  20 cells / 40 layer-reads
//   2x2 connector    (not walked before)        ->  12 cells / 24 layer-reads
//
// A 50-unit network with no connectors: 600 -> 2,000 layer-reads on the
// menu-open frame. The same network threaded with a 100-tile carpet path:
// 2,000 + 2,400 = 4,400. A deliberately absurd 1,000-tile carpet: ~26,000 -
// still one frame, and still fewer reads than the array_create(node_len) this
// function already performs (the farm is 188x144 ~ 27,000 cells,
// Grid.gml:479-488). ALLOCATIONS PER SCAN ARE UNCHANGED at exactly one, and
// there is no per-cell or per-probe allocation of any kind. yads_scan runs on
// menu open, on a remote press and on the interact ladder - all human-rate.
function yads_scan_probe(_grid, _tx, _ty, _visited, _frontier) {
    var _ni = _grid.try_node_index_for_cell(_tx, _ty);
    if (_ni == undefined) { return; }                        // off the grid

    yads_scan_take(_grid, _grid.node_object_id[_ni], _grid.node_parent[_ni],
        YADS_SEEN_OBJ, _visited, _frontier);
    yads_scan_take(_grid, _grid.node_rug_id[_ni], _grid.node_rug_parent[_ni],
        YADS_SEEN_RUG, _visited, _frontier);
}

// One candidate on one layer: the pre-1.3 probe body, unchanged in substance and
// parameterised on which pair of cell arrays it was read from.
//
// PARENTS, NOT PER-CELL IDS, is what the anchor dedup buys: a 2x2 connector
// writes node_rug_parent at four cells and every one of them resolves to the one
// parent struct, so the walk enqueues it once however many of its cells the
// probe sweep happens to cross. Identical to how the object layer has always
// behaved for a 4x2 crate's eight cells.
//
// `parent_grid` is present on a rug node for the same reason it is on an object
// node - Furniture.gml:730 writes it outside the rug branch - so the
// never-bridge-grids rule needs no special case and keeps a connector on a
// tabletop out of the walk. (It cannot be there anyway: the child-grid descent
// is gated on `proto.rug == false`, Furniture.gml:592-609.)
function yads_scan_take(_grid, _id, _neighbor, _bit, _visited, _frontier) {
    if (_id == undefined) { return; }                        // layer empty here
    if (_neighbor == undefined) { return; }
    if (_neighbor[$ "parent_grid"] != _grid) { return; }     // never bridge grids
    if (!yads_is_member(_neighbor)) { return; }

    var _anchor = _grid.node_index_for_cell(_neighbor.top_left_x, _neighbor.top_left_y);
    if (has_flag(_visited[_anchor], _bit)) { return; }

    _visited[_anchor] = set_flag(_visited[_anchor], _bit);
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

    // `fishable` is not "this is a fish": Items.gml:317-331 is its ONLY engine
    // reader, and all that code does is pick a catch-sprite icon variant, so
    // Wood and Fiber carry it because a rod can pull them out of the water too.
    // Vanilla itself refuses to choose between the two readings - sub_menus
    // .toml:28 lists the "fish" almanac lens as tags=["fishable","dive"] and
    // :31 lists "materials" as tags=["material"], and AlmanacMenu.gml:16 tests
    // contains_any_value_from - membership, not a partition. A 14-bucket sort
    // IS a partition, so a strong material/food/archaeology identity below must
    // beat the provenance tags `fishy`/`fishable`/`dive`/`bugs` at bucket 4.
    //
    // THREE ARMS READ THIS, not one: bucket 4 as above, the `mushroom` clause of
    // bucket 3, and the derived-`Consume` clause of bucket 6. All three are the
    // same shape - a signal that describes where an item CAME FROM or what you
    // can do to it, ranked above the tag that says what it IS. Each arm's own
    // note names the items it moves and the evidence. What `_strong` must never
    // gate is bucket 7 (see its note) or the `crop`/`forageable` clauses of
    // bucket 3: those tags ARE almanac lenses of their own, i.e. vanilla
    // asserting an identity, not describing a provenance.
    var _strong = _tags.contains("material") || _tags.contains("refined_material")
               || _tags.contains("food")     || _tags.contains("archaeology");

    if (_proto.tool_type != undefined || _tags.contains("tool")) {
        _cat = 0;   // Tools
    } else if (_tags.contains("weapon") || _tags.contains("sword")
            || _tags.contains("armor") || _tags.contains("accessory")) {
        _cat = 1;   // Weapons and armour
    } else if (_proto.use == ItemUse.PlantSeed || _proto.use == ItemUse.PlantSapling
            || _tags.contains("seed")) {
        _cat = 2;   // Seeds and saplings
    // `mushroom` is gated on !_strong for exactly the reason `fishable` is at
    // bucket 4. It has ZERO engine readers as an item tag - the only "mushroom"
    // strings left in the corpus are pets.toml's, and those are a PetKind fed
    // through string_to_pet_kind (PetPrototypes.gml:25), plus a dungeon vote
    // naming an OBJECT - and vanilla's almanac has no mushroom lens, it has a
    // `material` one (sub_menus.toml:31). The four items this moves are the
    // Mushroom-monster drops (items/other/monster_drops.toml, rolled at
    // monsters/shroom.toml:75/118/172/216): glowing_mushroom, purple_mushroom,
    // red_toadstool and wild_mushroom, every one tagged
    // ["material","mushroom","mushroomy"], not one of them tagged `forageable`,
    // and their own descriptions saying "sometimes dropped by Mushroom
    // monsters". They are crafting materials shaped like mushrooms.
    //
    // The five REAL forage mushrooms are untouched and stay here: earthshroom,
    // morel_mushroom, oyster_mushroom, pineshroom and spirit_mushroom all carry
    // `forageable`, whose clause is deliberately NOT gated - `forageable` and
    // `crop` are almanac lenses in their own right (sub_menus.toml:22/26) with
    // four and two engine readers respectively, so they are vanilla asserting an
    // identity rather than describing where a thing came from. That is also why
    // the four material-tagged shells (blue_conch_shell, pink_scallop_shell,
    // sand_dollar, spirula_shell) stay in this bucket: vanilla lists them under
    // Forageables itself. Measured: gating `mushroom` moves exactly four items.
    } else if (_tags.contains("crop") || _tags.contains("forageable")
            || _tags.contains("mines_forageable") || _tags.contains("flower")
            || (_tags.contains("mushroom") && !_strong) || _tags.contains("berry")) {
        _cat = 3;   // Crops and forage
    // `dive` is added here (not just fishy/fishable/bugs) because vanilla's own
    // almanac fish lens is tags=["fishable","dive"] (sub_menus.toml:28) - it
    // rescues pond_snail/river_snail, which carry no other tag, and costs
    // nothing: no `dive` item also carries a `_strong` tag.
    } else if (!_strong && (_tags.contains("fishy") || _tags.contains("fishable")
            || _tags.contains("dive") || _tags.contains("bugs"))) {
        _cat = 4;   // Fish and bugs
    } else if (_tags.contains("animal_product") || _tags.contains("animal_harvest")
            || _tags.contains("animal_fibre") || _tags.contains("ranching")
            || _tags.contains("egg")) {
        _cat = 5;   // Animal products
    // The `food` and `drink` TAGS are identity - `food` is precisely what
    // vanilla's own "cooked_dishes" almanac lens reads (sub_menus.toml:24) - and
    // neither is gated. The DERIVED `use == Consume` is not identity: Items.gml:
    // 135-136 infers `edible` from a bare `restore`/`health_modifier`/
    // `stamina_modifier` field, so an item lands here merely because chewing it
    // does something. That arm has to stay - 32 of the items it catches are
    // potions, syrups, fountains and untagged cooked dishes that have no other
    // route to this bucket - but it must not outrank a material identity.
    //
    // Two items were reaching bucket 6 through it alone: `chocolate` ("A bar of
    // quality chocolate. Used in a variety of cooking recipes.", tags
    // ["pantry","choco","material"], restore 10) and `ice_block` ("A foraged
    // block of pure ice. Commonly used as a cooking ingredient.", tags
    // ["material"], restore 6). Both are cooking INGREDIENTS, and chocolate's
    // seven `pantry`+`material` siblings - curry_powder, honey, honey_deluxe,
    // honey_legendary, honey_premium, rock_salt, soy_sauce - carry no restore
    // and have always sorted into Materials, so this also reunites a split
    // family. `choco` and `pantry` have no engine reader at all; their only
    // other appearance is in NPC gift-preference lists (npcs/dozy.toml:41-42).
    //
    // ice_block is the one judgement call here: forageables.toml:23 spawns it as
    // a common winter forageable, so bucket 3 is arguable - but vanilla did not
    // give it the `forageable` tag its shelf-mate rose_hip has, the classifier
    // sees only tags and `use`, and `material` is its sole tag. Materials is the
    // bucket its data asks for. Measured: gating `Consume` moves exactly two.
    } else if (_tags.contains("food") || _tags.contains("drink")
            || (_proto.use == ItemUse.Consume && !_strong)) {
        _cat = 6;   // Food and drink
    // `!_strong` must NOT gate this bucket: every ore/ingot carries `material`,
    // so that guard would empty it. `hard_wood` is the single item with a bogus
    // `gem` tag (materials.toml:27, tags=[...,"wood","gem"]) and `wood` is the
    // two-item discriminator (basic_wood, hard_wood) vanilla already hands us,
    // so gate `gem` on `!wood` instead of on `!_strong`.
    } else if (_tags.contains("ore") || _tags.contains("ingot")
            || _tags.contains("essence_stone")
            || (_tags.contains("gem") && !_tags.contains("wood"))) {
        _cat = 7;   // Ores, gems, ingots
    } else if (_tags.contains("material") || _tags.contains("refined_material")
            || _tags.contains("refined_ore") || _tags.contains("monster_part")
            || _tags.contains("animal_feed") || _tags.contains("junk")) {
        _cat = 8;   // Materials
    } else if (_tags.contains("archaeology") || _tags.contains("replica")) {
        _cat = 9;   // Artifacts and replicas
    // 11 BEFORE 10: every wallpaper/flooring/tile item ALSO carries the
    // `furniture` tag (e.g. basic_wallpaper_oak = ["furniture","wallpaper",
    // "basic_set"], basic_set.toml), so testing the furniture tag first
    // swallows all of them and bucket 11 ships holding 0 of 2665 items.
    // Reordering only changes which arm fires first; it assigns the same
    // literal bucket numbers, so it renumbers nothing.
    } else if (_proto.use == ItemUse.Wallpaper || _proto.use == ItemUse.Flooring
            || _proto.use == ItemUse.PlaceTile) {
        _cat = 11;  // Flooring and wallpaper
    // `use == PlaceObject` is a HARDER furniture test than the tag: Items.gml:
    // 205-213 ASSERTS that any item with an `object` field places a node whose
    // ObjectCategory IS Furniture, so this test is strictly stronger than (and
    // a superset of) the `furniture` tag. Spouse furniture, 10-heart gifts,
    // date photos, pet beds and the crafting-station furniture all place an
    // object but carry no `furniture` tag, and without this test they fall
    // through to bucket 13.
    } else if (_tags.contains("furniture") || _proto.use == ItemUse.PlaceObject) {
        _cat = 10;  // Furniture and decor
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
// CONNECTORS JOIN THE SAME OVERLAY, WITH ONE DELIBERATE ASYMMETRY. A connected
// connector glows the set's cyan, exactly like a heart or a panel. A
// disconnected one does NOT get a sad face by default: it gets whatever its own
// art family ships as an `_offline` strip (all four connectors ship one; the
// flat three's frames are identical by design, an unlit face with no blink) -
// and if a strip ever fails to resolve, the overlay is simply hidden and the
// piece lies there unlit. A frowning carpet is an error
// message about a thing the player cannot fix by pressing it, and unlike a crate
// a connector holds nothing, so there is no stranded-contents problem for the
// sad face to warn about. The Cloud Connector is the exception and MUST ship an
// offline strip: its whole body lives in the overlay, so hiding it would leave a
// bare shadow on the grass. All of that is expressed as data - one row per key in
// the offline table - and costs this section no branch at all; see
// yads_glow_link_probe.
//
// EVERY PLACED CONNECTOR IN THE ROOM IS MANAGED, not only the flood-reachable
// ones, and that took a full sweep of the rug layer to buy. The flood seeds off
// STORAGE_NODES, rugs are not in STORAGE_NODES (they have no inventory,
// Furniture.gml:869-874), and there is no registry of placed rugs at all - the
// grid cell arrays ARE the record (Grid.gml:20-21). So a connector is
// flood-visible only while some cached unit reaches it, and two ordinary player
// actions break that:
//
//   ORPHANED       break the last crate anchoring a carpet run. The count poll
//                  fires, the rescan runs, the flood finds no seed, and the run
//                  would keep both its stale autotile shape (a tee arm pointing
//                  at the empty cell the chest used to fill) and its lit cyan
//                  overlay - forever, or until a unit is placed near it again.
//   NEVER-ANCHORED lay a path first and place the crates afterwards. Until the
//                  first crate lands, nothing has ever looked at those rugs.
//
// Both are now closed by yads_glow_link_orphans, which walks this grid's
// node_rug_id array once per rescan and merges every LINK the flood did not
// reach as an UNLIT cache entry. That is the ~27,000-cell walk this section used
// to refuse; the refusal was right about the cost and wrong about the price of
// the bug. It is bounded (once per rescan, i.e. at worst once a YADS_GLOW_TTL),
// it is a flat array scan rather than the engine's own nested cell walk, and it
// is the same order as the pairwise sweep this function already runs at the same
// cadence. See that function's header for the arithmetic.
//
// CONSEQUENCE, AND IT IS THE POINT: an orphan run retiles. Its arms toward a
// removed unit retract on the next rescan because that unit is no longer in
// `_units` to contribute a bit, while its arms toward its own neighbours REMAIN,
// because those carpets are still physically adjacent and still in `_units`. And
// it goes dark: an unlit connector wears its `_offline` face (the single
// shapeless one for the flat three, `_offline_v<mask>` for the Cloud) instead of
// keeping the glow the engine handed it at creation. That last part is a
// deliberate change from Beta 1.3, where an uncached connector kept its lit look.
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
// A CONNECTOR IS FAIL-SOFT ON THE PAINT ONLY, NEVER ON THE TOPOLOGY. Both
// degradations above are per-unit and cosmetic, which is fine for a thing that
// only reports its own state - but a connector is an EDGE, and a missing edge
// paints the sad face on its healthy neighbours. So an art-less connector is
// still cached, still unions, and is merely skipped by yads_glow_apply. The two
// sites that make that true are commented at length: the tail of
// yads_glow_link_probe and the `_top == undefined` arm of yads_glow_apply.
//
// ---------------------------------------------------------------------------
// D2 "WOVEN" - THE CONNECTED TEXTURE (the connectors' second channel)
// ---------------------------------------------------------------------------
// A connector does not only report whether it is lit; it reports WHICH WAY THE
// RUN GOES. Every connector carries a 4-bit NSEW adjacency mask in the engine's
// own fence bit order (YADS_DIR_*, 1*N + 2*W + 4*E + 8*S, Furniture.gml:2193),
// and that mask drives two independent art channels:
//
//   BODY    renderer.image_index = mask, image_speed = 0. The base strip is a
//           sixteen-frame autotile whose frame index IS the mask, so the hem
//           opens, the chamfer drops and the cable bundle bends toward every
//           neighbour. This is the engine's own fence mechanism, applied to a
//           rug, and it is re-asserted every frame for the reason the engine
//           re-asserts its own (Furniture.gml:1265-1271): renderer rebuilds.
//   OVERLAY sprite_index = a NAMED per-mask variant, `..._glow_v<mask>` (and
//           `..._offline_v<mask>` for the Cloud alone). It cannot be an
//           image_index: the overlay's frames are its eight-frame pulse, and
//           spending them on adjacency would stop the glow animating.
//
// WHERE THE MASK COMES FROM, and where it does NOT live. It is accumulated in
// the pairwise sweep at the end of yads_glow_rescan out of yads_glow_side - the
// SAME relation the union-find uses, widened from a boolean to a compass bit -
// so a connector's art and the network's topology cannot disagree about what
// "next to" means. It lives in the glow cache entry and in nothing else; the
// per-key variant TABLES live in the ids memo (section 1). It is never written
// onto the rug node, because Grid.gml:1444-1449 would serialize it into the
// player's save and hand it back, stale, forever.
//
// PAINT IS DOWNSTREAM OF THE SCAN AND NEVER A PARTICIPANT. yads_scan does not
// read a mask, a variant or a renderer; a connector conducts because it is a
// LINK on the rug layer at an adjacent cell, exactly as it did before D2. An
// art layer that shipped none of the sixteen variants would change how the farm
// LOOKS and nothing at all about what is connected to what.
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
// current location, flood outward onto the rug layer to pick up the connectors
// they reach, union-find the lot by flush adjacency and overlap, and light every
// component that contains a heart.
//
// This deliberately does NOT reuse yads_scan. That function allocates
// array_create(grid.node_len) per call, and node_len on the farm is
// at least 188*144 ~ 27000 (Grid.gml:479-488) - fine once per menu open,
// catastrophic as a cache builder. Working straight off the node footprints
// costs ~15k VM ops for fifty units and touches no grid array at all.
//
// THE CONNECTOR PASS IS THE ONE EXCEPTION TO "touches no grid array", and it
// comes in two halves with very different shapes.
//
// The FLOOD is bounded by the topology: it reads node_rug_id/node_rug_parent at
// footprint + ring of each cached entry, which is 20 cells for a 4x2 unit and 12
// for a 2x2 connector. Fifty units threaded with a hundred connectors is
// 50*20 + 100*12 = 2,200 rug reads per rescan, against the 11,175 pairs the
// union below then walks at that entry count - i.e. the flood costs about a
// fifth of the pass it feeds, and it allocates one bounded struct-as-set rather
// than a node_len array.
//
// The ORPHAN SWEEP that follows it is bounded by the ROOM, and this function
// used to refuse to pay for it. It walks this grid's node_rug_id array once -
// node_len entries, which on the farm is dims.x*dims.y >= 188*144 ~ 27,000
// (Grid.gml:17, 476-488) - to find the connectors the flood cannot reach at all.
// Three things make that affordable where "a node_len sweep per frame" never
// was:
//
//   * ONCE PER RESCAN, never per frame. A rescan is an event (a STORAGE_NODES
//     count change) or the YADS_GLOW_TTL backstop, so the ceiling is ~1 Hz.
//   * A FLAT ARRAY WALK. `ni` is the array index, so this is one array read and
//     one undefined-compare per cell. The engine's own two full-grid passes -
//     initialize_on_room_start (Grid.gml:490-503) and the save serializer
//     (Grid.gml:1287-1301) - do the same thing through a nested x/y loop and a
//     node_index_for_cell call per cell, which is strictly more work.
//   * THE SAME ORDER AS THE PASS BELOW IT. At the fifty-units-plus-a-hundred-
//     carpets figure the pairwise sweep is already 11,175 pairs of several
//     struct reads each; ~27,000 single array reads is the same low-milliseconds
//     spike at the same cadence, not a new class of cost.
//
// There is no cheaper enumeration to switch to: the Grid keeps NO iterable rug
// collection. node_rug_id/node_rug_parent are node_len cell arrays (Grid.gml:
// 20-21) and every consumer in the engine - the serializer, the room-start
// renderer build, SetupFullStart, the test suite - walks all the cells. The one
// list-shaped alternative, `with (obj_node_renderer)`, is not an alternative at
// all: obj_node_renderer is in the camera's cull list (Camera.gml:306) and a
// deactivated instance is invisible to instance iteration, so it would enumerate
// the screen rather than the room.
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

    // Offline art, one asset per KEY, indexed by object_id and resolved once per
    // save load inside the ids memo (section 1) rather than once per rescan.
    //
    // THIS USED TO BE THREE try_string_to_asset CALLS RIGHT HERE, and the note
    // that justified them said three lookups on an event-driven rebuild were not
    // worth a memo with a lifetime of its own to get wrong. That was true at
    // three keys and is false at sixty-two: this function is not purely
    // event-driven - YADS_GLOW_TTL re-dirties it once a second unconditionally -
    // so the per-key form would be ~62 string-keyed asset lookups every second
    // for the whole session. The memo it moved into is the ids memo, which is
    // dropped on save.game_loaded, so it has no lifetime of its own at all.
    //
    // Per-KEY rather than per-KIND is also what lets a crate twin point at its
    // own art family's overlay without the three-element array here having to
    // grow a meaning it cannot carry - there are three kinds and rather more
    // faces. A slug the art layer did not ship comes back undefined, and that
    // unit falls back to the visible-toggle path in glow_apply.
    var _offline = _ids.offline;
    var _kinds = _ids.kind;

    var _units = [];
    var _rejected = 0;   // in-location members whose renderer/overlay was not up
    var _len = _list.count();
    for (var _i = 0; _i < _len; _i++) {
        var _node = _list.get(_i);
        if (_node == undefined) { continue; }

        // Membership AND kind out of one table read. This used to be
        // yads_is_member here and a second heart/block/panel derive 60 lines
        // down; the table makes them the same question, so it is asked once.
        var _kind = yads_kind_at(_kinds, _node[$ "object_id"]);
        if (_kind == undefined) { continue; }        // not one of ours

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

        // (Which unit this is was already read off the kind table at the head of
        // the loop. The old three-way derive here defaulted to "panel" for
        // anything that was neither heart nor block, which was safe only while
        // "ours" meant exactly three keys - with the crate twins that default
        // would have painted 59 crates with the panel's role tint.)

        // Fill tier inputs, for CRATES ONLY. There is no O(1) "occupied slots"
        // accessor anywhere on Inventory - size() is capacity, total_items() sums
        // counts, is_empty() is itself a scan - so this is a walk, and it is
        // walked here rather than in glow_apply because apply now runs every
        // frame and a rescan is an event. 50 crates x 30 slots is 1,500 slot
        // reads per rescan, an order of magnitude under the union-find below it.
        //
        // Hearts and panels are not asked: they are tinted by ROLE (cyan, "this
        // is the brain / this is the door"), never by fullness, because neither
        // is a deposit target and a heart reading "full" would advertise a
        // capacity the network will not use.
        var _used = 0;
        var _size = 0;
        if (_kind == YADS_KIND_CRATE) {
            // Read here rather than at the top of the loop: crates are the only
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
            // THE NODE THIS ENTRY WAS BUILT FROM, carried for one job: proving,
            // at apply time, that `renderer` is still THIS node's renderer. See
            // yads_glow_apply's identity re-check. It is a field in the CACHE
            // struct - nothing is ever written back onto the node - so it costs
            // the serializer nothing (Grid.gml:1444-1449 walks node fields, not
            // ours), and it is spelled at all three push sites because
            // glow_apply reads it off every entry and a struct missing a field
            // is a fault, not a default.
            node: _node,
            renderer: _renderer,
            top: _top,
            grid: _parent,
            // YADS_KIND_* - kept so glow_apply can pick a tint without
            // re-deriving it from object_id against a memo that may have been
            // dropped by a save load since.
            kind: _kind,
            // Occupied and total slots, crates only (0/0 for the other two).
            used: _used,
            size: _size,
            // The two sprites this unit's overlay alternates between. Read from
            // the prototype, not from _top.sprite_index, which by now may be
            // whatever the last apply wrote.
            glow_asset: yads_glow_top_sprite(_node),
            // Indexed by object_id, not by kind: sixty-two keys share three
            // kinds but not three faces. In range by construction - the same
            // read that produced a non-undefined _kind proves it.
            offline_asset: _offline[_node.object_id],
            // THE D2 AUTOTILE, and for everything in THIS loop it is inert: a
            // heart, a panel or a crate has one body sprite and one overlay, so
            // its mask stays 0 and both variant tables stay undefined, which is
            // the pair yads_glow_apply reads as "nothing to do". The fields are
            // spelled here anyway because the two cache-entry literals in this
            // section must stay the same SHAPE - glow_apply reads them off every
            // entry, and a struct missing a field is a fault, not a default.
            mask: 0,
            glow_variants: undefined,
            offline_variants: undefined,
            // Never for anything in THIS loop - a heart, a panel and a crate
            // are y-sorted objects and their overlay belongs on their own face.
            // Spelled here for the shape rule two comments up.
            glow_floor: false,
            // Footprint from the NODE, never prototype.size: rotation swaps the
            // two (Furniture.gml:2028-2035).
            x0: _node.top_left_x,
            y0: _node.top_left_y,
            w: _node.write_size_x,
            h: _node.write_size_y,
            heart: (_kind == YADS_KIND_HEART),
            root: array_length(_units),   // union-find: each unit starts alone
            lit: false,
        });
    }

    // -----------------------------------------------------------------------
    // THE CONNECTOR PASS - the one place section 9 leaves STORAGE_NODES.
    // -----------------------------------------------------------------------
    // Everything above walked STORAGE_NODES, which is the only global registry
    // of placed nodes the engine keeps - and it is gated on
    // `node.inventory != undefined` (Furniture.gml:869-874). A connector has no
    // inventory, so IT IS NOT IN THERE, and there is no other list: the rug cell
    // arrays are the entire record of a placed rug (Grid.gml:20-21;
    // grid.pet_beds and grid.terrain_editors take prototypes we do not declare).
    //
    // So connectors have to be FOUND, and the flood below is how. It seeds off
    // the units already cached, probes the RUG layer at footprint + ring of every
    // entry in the queue, and appends each LINK it finds - which then joins the
    // queue itself, so a chain of connectors is walked end to end. The relation
    // the probe implements is exactly `yads_glow_side || yads_glow_overlaps`:
    // a ring hit means the rug occupies a cell orthogonally outside us (edge), a
    // footprint hit means it occupies one of ours (overlap).
    //
    // RUG LAYER ONLY - a deliberate narrowing of the recon's design, which also
    // probed the object layer from a connector so that "a unit reachable only
    // through a carpet" would be picked up. That probe cannot find anything new:
    // every inventory-bearing node in the entire save is in STORAGE_NODES, and
    // the loop above already took every one of them in this location. Units
    // reached only through a carpet are already cached; what they needed was the
    // CARPET, and the union below is what connects them. Halving the flood's
    // probe count for a provably empty result is worth the paragraph.
    //
    // VISITED IS A LOCAL STRUCT-AS-SET, and the two things it is not are both
    // deliberate:
    //   * NOT a field stamped on the rug node. That would be written into the
    //     player's save and read back forever - the serializer's default arm is
    //     a verbatim copy of every unnamed struct field (Grid.gml:1444-1449) and
    //     rugs ride the same walker (Grid.gml:1298-1301). See yads_scan's note.
    //   * NOT array_create(node_len). This is a 1 Hz cache builder and the whole
    //     reason it does not reuse yads_scan is that ~27,000-cell allocation
    //     (see this function's header). The set is bounded by the number of
    //     connectors actually laid, not by the size of the farm.
    // Keying by anchor cell index is collision-free HERE in a way it would not be
    // for the object layer: rugs never descend into a child grid (the descent is
    // gated on `proto.rug == false`, Furniture.gml:592-609), so every LINK is on
    // the one top-level grid of the one location this rescan filters to, and two
    // different Grids cannot contribute the same index.
    var _flood = {
        location: _location,
        kinds: _kinds,
        offline: _offline,
        // The D2 autotile's overlay tables, carried in for the same reason
        // `offline` is: the probe stamps them onto every connector it caches so
        // the per-frame apply never touches yads_ids().
        glow_variants: _ids.glow_variants,
        offline_variants: _ids.offline_variants,
        // The overlay depth policy, carried in for the same reason and stamped
        // onto every connector the probe caches.
        glow_floor: _ids.glow_floor,
        seen: {},        // anchor cell index (as a key) -> index into `units`
        units: _units,
    };

    // The queue IS `_units`, walked with a cursor: connectors are appended to it,
    // so the cursor chains through them with no second structure and no second
    // liveness rule. array_length is re-read each iteration on purpose.
    var _cursor = 0;
    while (_cursor < array_length(_units)) {
        var _u = _units[_cursor];
        var _ug = _u.grid;
        var _ux = _u.x0;
        var _uy = _u.y0;
        var _uw = _u.w;
        var _uh = _u.h;

        for (var _i = 0; _i < _uw; _i++) {
            yads_glow_link_probe(_flood, _ug, _ux + _i, _uy - 1, _cursor);
            yads_glow_link_probe(_flood, _ug, _ux + _i, _uy + _uh, _cursor);
        }
        for (var _j = 0; _j < _uh; _j++) {
            yads_glow_link_probe(_flood, _ug, _ux - 1, _uy + _j, _cursor);
            yads_glow_link_probe(_flood, _ug, _ux + _uw, _uy + _j, _cursor);
        }
        for (var _i = 0; _i < _uw; _i++) {
            for (var _j = 0; _j < _uh; _j++) {
                yads_glow_link_probe(_flood, _ug, _ux + _i, _uy + _j, _cursor);
            }
        }

        _cursor += 1;
    }

    // -----------------------------------------------------------------------
    // THE ORPHAN SWEEP - every connector the flood could not reach.
    // -----------------------------------------------------------------------
    // AFTER the flood and BEFORE the pairwise sweep, and both halves of that
    // ordering are load-bearing.
    //
    // After the flood, because the flood is what decides LIT-NESS and the
    // sweep must not touch it. `seen` is already populated, so a connector the
    // flood took is skipped here on one struct read; only the unreachable ones
    // are appended, they carry `heart: false` and their own fresh `root`, and
    // nothing in this function can union them into a heart's component. (Nor
    // could the pairwise pass below: the flood probes footprint + ring of every
    // entry it holds, which is exactly yads_glow_side || yads_glow_overlaps, so
    // a connector adjacent to or under ANY cached entry was already found. What
    // reaches this sweep is by construction adjacent to nothing cached.)
    //
    // Before the pairwise sweep, because the sweep is where the MASK comes from
    // and an orphan run has to retile too. Its arms toward a unit that is gone
    // retract - there is no entry left to contribute that bit - while its arms
    // toward its own neighbours survive, because those carpets are still there
    // and are now in `_units` beside it. That is the whole feature.
    //
    // `_world` rather than a per-unit grid: rugs never descend into a child
    // grid (the descent is gated on `proto.rug == false`, Furniture.gml:592-609),
    // so every connector in this location is on the one top-level Grid, which is
    // GRID (Game.gml:645-653 assigns it from GRIDS[location]).
    //
    // The flood's count is snapshotted FIRST: the not-yet retry at the bottom
    // of this function has to see what the flood alone delivered. Orphan
    // entries are pushed renderer-less on the same build-straddling frame that
    // rejects every unit, so testing the post-sweep length would let a dozen
    // renderer-less carpets mask the "empty with rejections" signal and
    // silently disable the short retry in any room with a connector.
    var _flood_count = array_length(_units);
    yads_glow_link_orphans(_flood, _world);

    var _count = array_length(_units);

    // Pairwise union over flush adjacency. Quadratic, but on a count that is
    // bounded by how many crates a player can be bothered to place: 50 units is
    // 1225 pairs of a handful of integer compares, and this runs on an event,
    // not per frame.
    //
    // CONNECTORS ENLARGE THAT COUNT, and honestly: 50 units threaded with a
    // 100-tile carpet path is 150 entries and 11,175 pairs, ~9x the pair count at
    // the same 1 Hz. Still a low-milliseconds spike on an event, and the entries
    // are the same handful of integer compares.
    //
    // THIS LOOP IS ALSO WHERE THE D2 AUTOTILE MASK COMES FROM, and it is the
    // right place for exactly one reason: it is already asking, of every pair,
    // the question the mask needs answered. Widening the old boolean adjacency
    // test into yads_glow_side's compass bit makes the mask FREE - no second
    // sweep, no second adjacency definition, and no possibility of the art and
    // the topology disagreeing about what "next to" means, because they are now
    // the same call. (That is why the old note here about making this loop
    // linear by skipping any pair with a LINK on either side is gone: the flood
    // above would still cover the unions, but the mask genuinely needs the
    // pairwise sweep, so the shortcut is no longer free.)
    //
    // ONLY EDGE ADJACENCY CONTRIBUTES A BIT. An OVERLAP - a crate standing on a
    // carpet - unions the two, because that is the headline half of the feature,
    // but it has no compass direction to contribute and must not invent one: a
    // lone carpet under a lone crate is a piece with no run through it and draws
    // the isolated pose, which is what it is.
    //
    // A CONNECTOR DELIBERATELY TAKES A BIT TOWARD A NON-CONNECTOR NEIGHBOUR -
    // toward a crate, a heart or a panel - and that is intended, not a leak:
    // only `_a.kind == YADS_KIND_LINK` is tested before set_flag, never the
    // neighbour's kind, so a carpet abutting a crate draws its arm INTO the
    // thing it feeds. That is what makes a run read as plumbing rather than as a
    // separate decorative strip that happens to stop next to a chest. The
    // neighbour keeps mask 0 (the `_units[_b].kind == YADS_KIND_LINK` guard),
    // because a chest has no autotile to drive.
    //
    // A UNIT WHOSE RENDERER WAS NOT UP is not in `_units` and therefore does not
    // contribute its side. That is cosmetic and self-healing (the next rescan
    // has it), and it is the same fail-soft the lit state itself takes.
    for (var _a = 0; _a < _count; _a++) {
        for (var _b = _a + 1; _b < _count; _b++) {
            // Structs compare by reference on this runtime. A network never
            // leaves its Grid - a table surface is a child grid and does not
            // bridge to the floor.
            if (_units[_a].grid != _units[_b].grid) { continue; }

            var _side = yads_glow_side(_units[_a], _units[_b]);
            if (_side == 0
                && !yads_glow_overlaps(_units[_a], _units[_b])) { continue; }

            if (_side != 0) {
                if (_units[_a].kind == YADS_KIND_LINK) {
                    _units[_a].mask = set_flag(_units[_a].mask, _side);
                }
                if (_units[_b].kind == YADS_KIND_LINK) {
                    _units[_b].mask = set_flag(_units[_b].mask,
                        yads_dir_opposite(_side));
                }
            }

            yads_glow_union(_units, _a, _b);
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
    // glow it was born with. Tested against the FLOOD's count, snapshotted
    // before the orphan sweep (see there): orphan entries are not units
    // arriving, and on this exact frame they exist and are renderer-less.
    if (_flood_count == 0 && _rejected > 0) {
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

// WHICH SIDE of `_a` does `_b` lie on? YADS_DIR_* for a shared orthogonal grid
// edge, 0 for anything else.
//
// THIS IS `yads_glow_adjacent` WITH ITS ANSWER WIDENED from a boolean to a
// compass bit, and it REPLACES it outright rather than wrapping it. The
// relation is byte-for-byte the pre-D2 one; only the return type grew. Two
// spellings would have been the mistake: the D2 autotile picks a connector's
// art from these bits and the union-find picks the network's topology from the
// same call, and an adjacency the ART believes in that differs from the one the
// NETWORK believes in is exactly the bug where a carpet draws itself joined to
// a crate it does not conduct to, or draws itself alone in the middle of a live
// run. One relation, one function, both readers. (Same rule, same reason, as
// yads_glow_union's "two hand-inlined copies of a union are two things that can
// drift apart".)
//
// The relation is the BFS ring probe's: the AABBs must be flush on one axis AND
// overlap by a non-zero amount on the other, which is what excludes the four
// diagonal corners - two crates meeting at a single point are not connected. A
// flush pair that fails the overlap test returns 0 without falling through to
// the other axis, exactly as the boolean version returned false there; the two
// branches cannot both be true anyway (that would need a footprint of width or
// height zero).
function yads_glow_side(_a, _b) {
    var _ax1 = _a.x0 + _a.w;
    var _ay1 = _a.y0 + _a.h;
    var _bx1 = _b.x0 + _b.w;
    var _by1 = _b.y0 + _b.h;

    if (_ax1 == _b.x0 || _bx1 == _a.x0) {                   // vertical seam
        if ((min(_ay1, _by1) - max(_a.y0, _b.y0)) <= 0) { return 0; }
        return (_ax1 == _b.x0) ? YADS_DIR_E : YADS_DIR_W;
    }
    if (_ay1 == _b.y0 || _by1 == _a.y0) {                   // horizontal seam
        if ((min(_ax1, _bx1) - max(_a.x0, _b.x0)) <= 0) { return 0; }
        return (_ay1 == _b.y0) ? YADS_DIR_S : YADS_DIR_N;
    }

    return 0;
}

// Do two footprints OVERLAP - share at least one cell? The second connectivity
// relation, and it exists because the first one cannot see this case at all.
//
// yads_glow_side tests "flush on one axis AND non-zero overlap on the
// other", which is false for two footprints that genuinely overlap: a 4x2 crate
// at (10,10) and a 2x2 connector at (10,10) are flush on NEITHER axis
// (ax1=14 != bx0=10, bx1=12 != ax0=10, ay1=12 != by0=10, by1=12 != ay0=10), so
// it returns false. Chest-on-carpet is exactly that configuration, and it is the
// headline half of the feature.
//
// THIS RELATION CAN ONLY EVER FIRE ACROSS LAYERS, which is what makes it safe to
// union on: can_write_object_on_node refuses a second object on an occupied cell
// (GridUtils.gml:76-77) and refuses a second rug on a rugged cell
// (GridUtils.gml:71-75), so two crates can never overlap and neither can two
// connectors. The only pairs this can return true for are unit-over-connector
// and connector-under-unit, which is precisely what it is for.
//
// Strict inequalities, so a flush edge is NOT an overlap: at ax1 == bx0 the test
// `_b.x0 < _a.x0 + _a.w` reads `14 < 14` and fails. The two relations therefore
// partition rather than double-count - harmless either way, since union-find is
// idempotent, but it keeps each one meaning exactly one thing.
function yads_glow_overlaps(_a, _b) {
    return _a.x0 < (_b.x0 + _b.w) && _b.x0 < (_a.x0 + _a.w)
        && _a.y0 < (_b.y0 + _b.h) && _b.y0 < (_a.y0 + _a.h);
}

// Merge two cache entries' components. One spelling, two callers - the pairwise
// pass and the connector flood - because two hand-inlined copies of a union are
// two things that can drift apart.
function yads_glow_union(_units, _a, _b) {
    var _ra = yads_glow_find(_units, _a);
    var _rb = yads_glow_find(_units, _b);
    if (_ra != _rb) { _units[_rb].root = _ra; }
}

// ONE CELL OF THE CONNECTOR FLOOD: look at the rug layer, and if a connector is
// there, cache it and union it to the entry we were probing from.
//
// `_from` is the index of the entry whose footprint + ring we are walking. The
// union is done HERE rather than left to the pairwise pass because the probe
// already proves the relation - a ring cell means edge-adjacent, a footprint cell
// means overlapping - so the answer is free and does not need re-deriving from
// two AABBs. The pairwise pass would reach the same conclusion; see its note.
//
// THE SEEN MAP CARRIES A REJECTION SENTINEL. A vanilla rug, or one of ours that
// is not yet paintable, is stamped -1 rather than left unstamped, so a decorative
// carpet lying under a 4x2 crate costs one kind lookup for the whole rescan
// instead of eight. -1 is distinguishable from an index because indices are
// array positions and the first is 0.
//
// A REJECTED CONNECTOR IS NOT COUNTED INTO _rejected, and that is not an
// oversight. That counter exists for one decision - "everything was rejected, so
// this is a not-yet rather than a no; take the short retry" - and it is read as
// `array_length(_units) == 0 && _rejected > 0`. The flood only runs when there is
// at least one seeded unit to run it from, so _units is never empty when a
// connector could be rejected, and the branch could not fire whatever we counted.
// The mixed state it would otherwise describe is unreachable anyway:
// initialize_on_room_start builds BOTH layers' renderers in the same cell walk,
// in the same function, on the same frame (Grid.gml:493-503), so a live crate and
// a rendererless carpet beside it is not a state the engine passes through.
function yads_glow_link_probe(_flood, _grid, _tx, _ty, _from) {
    var _ni = _grid.try_node_index_for_cell(_tx, _ty);
    if (_ni == undefined) { return; }                     // off the grid
    if (_grid.node_rug_id[_ni] == undefined) { return; }  // no rug on this cell

    var _node = _grid.node_rug_parent[_ni];
    if (_node == undefined) { return; }

    var _units = _flood.units;

    // Dedupe by PARENT, not by cell: a 2x2 connector answers at four cells and
    // every one of them resolves to the one parent struct. Anchor cell of the
    // parent is the parent's identity, exactly as in yads_scan_take.
    var _key = string(_grid.node_index_for_cell(_node.top_left_x, _node.top_left_y));

    var _at = _flood.seen[$ _key];
    if (_at != undefined) {
        // Already judged this rescan. Union anyway when it is one of ours: this
        // is how a connector bridges two separately-seeded clusters - the second
        // cluster's probe finds it already cached and joins onto it.
        if (_at >= 0) { yads_glow_union(_units, _from, _at); }
        return;
    }

    // Ours, and a connector specifically? Bounds-guarded, because a mod loading
    // after us mints ObjectIds past the end of our table and its rugs reach this
    // line - they must read "not ours" and never fault.
    if (yads_kind_at(_flood.kinds, _node[$ "object_id"]) != YADS_KIND_LINK) {
        _flood.seen[$ _key] = -1;
        return;
    }

    var _parent = _node[$ "parent_grid"];
    if (_parent == undefined || _parent.location_id != _flood.location) {
        _flood.seen[$ _key] = -1;
        return;
    }

    // ***** A CONNECTOR CONDUCTS WHETHER OR NOT IT CAN BE PAINTED. *****
    // This is the one place this section deliberately does NOT copy the
    // STORAGE_NODES loop, and the asymmetry is the whole point.
    //
    // Up there, a unit whose renderer or overlay is not up is dropped from the
    // cache, and the only consequence is that THAT unit carries no status
    // overlay - the fail-soft this section's header describes. A connector is
    // different in kind: it is not just a thing that gets painted, it is an EDGE
    // in the connectivity graph. Drop it and the two units it joins fall into
    // different components and both paint the sad face - the glow would then be
    // lying about a network that is, in yads_scan's eyes and in fact, perfectly
    // connected. A cosmetic gap on one piece is fail-soft; a wrong answer about
    // topology on its neighbours is not.
    //
    // So the entry is cached with whatever it has, `undefined` included, and
    // yads_glow_apply skips unpaintable entries without touching them. The rule
    // was forged when this code briefly ran ahead of the connector art: every
    // connector then reached this line with top_sheet_renderer undefined, and
    // the reject-on-missing rule would have silently un-linked every carpet in
    // the game while yads_scan happily linked them. The art has since shipped
    // (all four glow strips resolve), but the rule stays load-bearing: any
    // future unit whose overlay lags, fails to resolve, or is stripped by a
    // partial install must still CONDUCT even when it cannot PAINT.
    //
    // instance_is_alive rather than instance_exists, for the reason the loop
    // above gives at length: Camera.process_culls deactivates renderers and a
    // deactivated instance is invisible to instance_exists, so a carpet running
    // off the edge of the screen must not read as a broken chain.
    var _renderer = _node[$ "renderer"];
    var _top = undefined;
    if (_renderer != undefined && instance_is_alive(_renderer)) {
        var _sheet = _renderer.top_sheet_renderer;
        if (_sheet != undefined && instance_is_alive(_sheet)) { _top = _sheet; }
    }

    // In range by construction: the same bounds-guarded read that produced a
    // non-undefined kind above proves it, and `offline`, `glow_variants` and
    // `offline_variants` are all built to the same length as `kind` in section
    // 1's pass two.
    var _face = _flood.offline[_node.object_id];
    var _glow_v = _flood.glow_variants[_node.object_id];
    var _offline_v = _flood.offline_variants[_node.object_id];
    // NORMALISED TO A REAL BOOL at the one point the table is read. The table's
    // fill is `undefined` like every other ObjectId-indexed table in section 1,
    // but the per-frame reader is an `if` and this runtime's truthiness of
    // undefined is not something a per-frame hook should be finding out.
    var _floor = (_flood.glow_floor[_node.object_id] == true);

    var _index = array_length(_units);
    array_push(_units, {
        // The rug node itself - yads_glow_apply's identity re-check reads it.
        // See the STORAGE_NODES loop's note on this field.
        node: _node,
        renderer: _renderer,
        top: _top,
        grid: _parent,
        kind: YADS_KIND_LINK,
        // NO FILL TIER. A connector stores nothing, so it reports nothing, and
        // 0/0 is what routes it into yads_glow_tint's first arm: that arm is
        // `kind != YADS_KIND_CRATE || size <= 0`, which a LINK satisfies twice
        // over and which returns the set's cyan. yads_glow_tint and
        // yads_glow_apply took ZERO edits for this feature.
        used: 0,
        size: 0,
        glow_asset: yads_glow_top_sprite(_node),
        // THE OFFLINE FACE IS KEY-DRIVEN, NOT KIND-DRIVEN, and that is the whole
        // answer to "what does a disconnected connector look like":
        //
        //   * art layer ships spr_furniture_netstor_link_<x>_offline -> the
        //     overlay SWAPS to it, unlit and untinted, and the piece stays on
        //     screen. This is mandatory for the Cloud Connector, whose entire
        //     body lives in the overlay: hiding it would leave a bare shadow
        //     ellipse on the grass.
        //   * art layer ships none -> try_string_to_asset returned undefined,
        //     and yads_glow_apply's degraded-art path hides the overlay while
        //     disconnected (and resets interacting/blend/alpha so a unit hidden
        //     mid-highlight comes back clean).
        //
        // What SHIPPED: all four connectors carry an _offline strip. The flat
        // three's frames are deliberately identical (an unlit conductor face,
        // no blink) so a field of stranded tiles never strobes in unison; the
        // Cloud's is animated and load-bearing per the first bullet. No sad
        // faces on any of them: a frowning carpet reads as an error the player
        // cannot act on, and "this floor is not lit" is already unambiguous.
        //
        // Either way this is ONE table read and no branch. The offline table is
        // built per KEY from the same UNIT_KEYS seam that gave us the kind
        // (section 1), so the four connectors needed no entry added to it and no
        // exclusion from it - which is exactly why it was made per-key.
        offline_asset: _face,
        // ------------------------------------------------------------------
        // THE D2 "WOVEN" AUTOTILE STATE. This is the only place it lives.
        // ------------------------------------------------------------------
        // `mask` starts at 0 - the isolated pose - and is filled in by the
        // pairwise sweep in yads_glow_rescan, which is the one pass that knows
        // every neighbour of every entry. It is deliberately NOT computed here:
        // the flood visits a connector once, from whichever entry happened to
        // find it first, and would only ever see that one side.
        //
        // ***** IT IS NOT WRITTEN ONTO THE RUG NODE, EVER. ***** The obvious
        // implementation - `_node.yads_mask = 6` - would be serialized into the
        // player's save and read back forever: the grid serializer's default arm
        // is a verbatim copy of every struct field it does not name
        // (Grid.gml:1444-1449), rugs ride that same walker
        // (Grid.gml:1298-1301), and the load walker's skip list omits unknown
        // names too. A stale mask on disk is a connector that draws itself
        // joined to a neighbour that was picked up three seasons ago. This cache
        // entry dies with the rescan, which is exactly the lifetime the value
        // has.
        //
        // The two tables are the ObjectId-indexed ones from section 1, read once
        // here so the per-frame apply does no lookup at all. Either may be
        // undefined; the flat three legitimately have no offline variants.
        mask: 0,
        glow_variants: _glow_v,
        offline_variants: _offline_v,
        // Flat connector -> its overlay is pinned into the floor band by
        // yads_glow_apply; Cloud -> false, it stays y-sorted and airborne.
        glow_floor: _floor,
        x0: _node.top_left_x,
        y0: _node.top_left_y,
        w: _node.write_size_x,
        h: _node.write_size_y,
        // A connector is never a heart, so it never lights a component on its
        // own - a carpet with no unit on it stays dark, which is correct.
        heart: false,
        root: _index,
        lit: false,
    });

    _flood.seen[$ _key] = _index;
    yads_glow_union(_units, _from, _index);
}

// EVERY CONNECTOR THE FLOOD DID NOT REACH, merged as an UNLIT cache entry.
//
// WHY THIS EXISTS. yads_glow_link_probe finds a connector by being flooded over
// from a cached unit, so it finds exactly the connectors some unit reaches. The
// two states it cannot see are the two the player produces most easily: a run
// whose last anchoring unit was just picked up (ORPHANED), and a path laid
// before any unit was placed on it (NEVER-ANCHORED). An unreached connector is
// not merely un-lit - it is UNMANAGED, so it keeps whatever the engine gave it
// at creation: the lit glow overlay, and mask 0, or worse, whatever mask the
// last rescan that DID reach it wrote, which is an arm pointing at an empty
// cell. Section 9's header has the full statement of the bug.
//
// WHY IT IS A FULL SWEEP. The Grid keeps no iterable rug collection: node_rug_id
// and node_rug_parent are node_len cell arrays (Grid.gml:20-21) and every engine
// consumer walks all the cells - the save serializer (Grid.gml:1287-1301), the
// room-start renderer build (Grid.gml:490-503), SetupFullStart, the test suite.
// So there is nothing cheaper to iterate, and the cost argument that makes this
// affordable ONCE PER RESCAN rather than per frame is in yads_glow_rescan's
// header. This walks the flat array directly instead of the engine's nested x/y
// loop, because `ni` IS the index: node_index_for_cell is `y * dims.x + x` over
// `node_len = dims.x * dims.y` (Grid.gml:17, 78-81), so 0..node_len-1 visits
// every cell exactly once and nothing else.
//
// WHAT IT DOES NOT DO. It does not union - an orphan is by definition adjacent
// to nothing already cached, and giving it a union partner here would be
// inventing an edge. It does not seed the flood - a connector found here cannot
// reach anything the flood missed, for the same reason. It does not decide
// lit-ness: it pushes `heart: false` and its own `root`, and the sweep in
// yads_glow_rescan then finds no heart in its component. Lit-ness stays strictly
// flood-derived.
//
// The entry it pushes is the SAME SHAPE as the other two push sites, field for
// field, for the reason both of them state: yads_glow_apply reads every field
// off every entry and a struct missing one is a fault, not a default.
function yads_glow_link_orphans(_flood, _grid) {
    var _rug_id = _grid.node_rug_id;
    var _rug_parent = _grid.node_rug_parent;
    var _len = array_length(_rug_id);
    var _units = _flood.units;

    for (var _ni = 0; _ni < _len; _ni++) {
        // The whole steady-state cost of this function: one array read and one
        // compare for every cell with no rug on it.
        if (_rug_id[_ni] == undefined) { continue; }

        var _node = _rug_parent[_ni];
        if (_node == undefined) { continue; }

        // Dedupe by PARENT via its anchor cell, spelled exactly as
        // yads_glow_link_probe spells it - a 2x2 connector answers at four
        // cells, and the two functions share one `seen` map, so the two key
        // derivations have to be the same expression or the map has two names
        // for one rug.
        var _key = string(_grid.node_index_for_cell(_node.top_left_x, _node.top_left_y));
        if (_flood.seen[$ _key] != undefined) { continue; }

        // Bounds-guarded, for yads_kind_at's reason: a mod loading after us
        // mints ObjectIds past the end of our table and its rugs reach this
        // line. The -1 sentinel is the probe's, and means the same thing here -
        // a decorative rug judged once for the whole rescan.
        if (yads_kind_at(_flood.kinds, _node[$ "object_id"]) != YADS_KIND_LINK) {
            _flood.seen[$ _key] = -1;
            continue;
        }

        // Belt and braces. A rug in THIS grid's cell arrays is in this grid, so
        // this cannot fail - but the probe tests it and dropping the test here
        // would leave two rules for one question.
        var _parent = _node[$ "parent_grid"];
        if (_parent == undefined || _parent.location_id != _flood.location) {
            _flood.seen[$ _key] = -1;
            continue;
        }

        // A CONNECTOR IS CACHED WHETHER OR NOT IT CAN BE PAINTED, exactly as in
        // the probe and for the same reason stated there at length: an entry
        // with `top == undefined` is skipped by yads_glow_apply without
        // dirtying. instance_is_alive rather than instance_exists, because
        // obj_node_renderer is deactivated by the camera cull and a connector
        // off the edge of the screen must not read as absent.
        var _renderer = _node[$ "renderer"];
        var _top = undefined;
        if (_renderer != undefined && instance_is_alive(_renderer)) {
            var _sheet = _renderer.top_sheet_renderer;
            if (_sheet != undefined && instance_is_alive(_sheet)) { _top = _sheet; }
        }

        // In range by construction - the bounds-guarded kind read above proves
        // it, and all four tables are built to one length in section 1.
        var _index = array_length(_units);
        array_push(_units, {
            node: _node,
            renderer: _renderer,
            top: _top,
            grid: _parent,
            kind: YADS_KIND_LINK,
            used: 0,
            size: 0,
            glow_asset: yads_glow_top_sprite(_node),
            offline_asset: _flood.offline[_node.object_id],
            mask: 0,
            glow_variants: _flood.glow_variants[_node.object_id],
            offline_variants: _flood.offline_variants[_node.object_id],
            glow_floor: (_flood.glow_floor[_node.object_id] == true),
            x0: _node.top_left_x,
            y0: _node.top_left_y,
            w: _node.write_size_x,
            h: _node.write_size_y,
            heart: false,
            root: _index,
            lit: false,
        });

        _flood.seen[$ _key] = _index;
    }
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

    // The floor band, resolved AT MOST ONCE per call and only if some cached
    // unit actually wants it. get_floor_depth() is a room-layer lookup
    // (RoomServiceUtils.gml:10-16), so it is neither free enough to call per
    // unit nor stable enough to memoise across frames: it is per ROOM, and a
    // memo would have a lifetime of its own to get wrong the first time a
    // player walks into a cellar. Once per frame is the honest answer.
    var _floor_depth = undefined;
    var _floor_asked = false;

    for (var _i = 0; _i < _count; _i++) {
        var _unit = _units[_i];

        // -------------------------------------------------------------------
        // THE D2 "WOVEN" BODY VARIANT - connectors only, and asserted HERE, in
        // the per-frame loop, for the reason the engine asserts its own fences
        // here: a renderer rebuild resets image_index, and rebuilds happen on
        // room start, on season change and on every write_node. Furniture.gml:
        // 1265-1271 is the engine doing precisely this - image_speed = 0, then
        // image_index = the cached fence index - after every rebuild. We are
        // one line behind it on the same road.
        //
        // KIND-GATED, AND THAT GATE IS LOAD-BEARING. Every other unit we cache
        // has a base renderer driven by the interaction_chest lid state machine
        // (Furniture.gml:1226-1232 restores cardinal_data.sprite at the end of
        // every open/close/bounce); writing image_index on one of those would
        // freeze a chest mid-animation. A rug has no lid, no interaction and no
        // animation of its own - its sixteen frames are not a time axis, they
        // are the mask space - so image_speed = 0 costs it nothing.
        //
        // instance_exists, NOT instance_is_alive, and this is the ONE site in
        // this section that departs from that rule. obj_node_renderer IS in the
        // camera's cull list (Camera.gml:306) and a deactivated instance is
        // invisible to instance_exists, so this write simply does not happen for
        // an off-screen connector - which is what the ENGINE's own fence
        // autotiler does at Furniture.gml:2165-2167, guarded the same way, for
        // the same reason. Nothing is lost: yads_glow_apply is also a
        // camera.culls_processed handler, i.e. it runs on the one frame a
        // renderer that just scrolled back into view is active but has not yet
        // drawn, so the piece is retiled before it is ever seen wrong. The
        // overlay below deliberately keeps instance_is_alive: obj_node_renderer
        // _top is not in the cull list at all.
        //
        // KNOWN AND ACCEPTED: retiling lags placement by up to one
        // YADS_GLOW_TTL (about a second). Laying a rug does NOT bump
        // STORAGE_NODES.count - a connector has no inventory and never enters
        // that list (Furniture.gml:869-874) - so yads_glow_poll's count poll
        // cannot see it and the TTL backstop is what catches it. The player sees
        // a newly laid connector show its isolated pose and then snap into the
        // run. That is a DIRTY-TRIGGER gap, not a discovery gap: since
        // yads_glow_link_orphans the rescan does sweep every rug cell in the
        // room, so the piece is always found - the wait is only for the next
        // rescan to happen. Closing it properly would mean running that sweep
        // per FRAME, which is the ~27,000-cell walk this section still refuses;
        // one second of the isolated pose is not worth sixty times the cost.
        //
        // THE IDENTITY RE-CHECK, and it is here because of what this write
        // targets. obj_node_renderer is not our object - every crop, tree,
        // chest, rock and fence in the world is one - and this is the only
        // place the mod writes image_speed/image_index on one. A cache entry
        // outlives its node by up to one YADS_GLOW_TTL (nothing re-dirties on a
        // RUG pickup - see the paragraph above), so between the pickup and the
        // next rescan we are holding an instance handle to a destroyed
        // renderer. If Fabricator ever recycles instance ids inside that
        // window, that handle resolves to somebody else's renderer and we would
        // freeze it at image_speed = 0 on frame `mask` - a crop stuck
        // mid-growth, a tree that never sways.
        //
        // obj_node_renderer carries `self.node`, set in init
        // (obj_node_renderer.gml:465) and declared unconditionally in Create
        // (:394, the same guarantee that makes the top_sheet_renderer read in
        // the rescan safe), so the check is one instance read and one reference
        // compare: is this still the renderer of the node this entry was built
        // from? A recycled id fails it and we simply do not write.
        //
        // But `node` is only declared on obj_node_renderer, and the recycled id
        // this check exists for could just as well land on some OTHER object -
        // a drop effect, an overlay - where reading an undeclared variable
        // THROWS, inside a per-frame hook. So the vocabulary is proven first:
        // `object_index` is a builtin (readable on anything, engine precedent
        // obj_dungeon_ladder_down.gml:19), and only an actual obj_node_renderer
        // gets its `node` read. Wrong object type: skip. Right type, wrong
        // node: skip. Only the renderer this entry was built from is written.
        //
        // `node` is a field of OUR cache struct, never a field written back
        // onto the node, so it is invisible to the grid serializer.
        //
        // THE OVERLAY BELOW TAKES NO SUCH CHECK, because there is nothing to
        // check it against: obj_node_renderer_top's Create sets only `depth`
        // and `interacting` and it is handed no node reference at all
        // (obj_node_renderer_top.gml; Furniture.gml:946-947 creates it bare and
        // assigns sprite_index). The only proxy available is
        // `_unit.renderer.top_sheet_renderer == _unit.top`, which is
        // deliberately NOT taken, for two reasons. First, it is itself a
        // non-builtin read through the possibly-recycled BASE id - the exact
        // hazard the body check above exists to contain - so it would need the
        // same object_index pre-guard to be safe at all. Second, even made
        // safe, it couples the overlay's per-frame update to the base
        // renderer, in a section whose whole liveness discipline exists to
        // keep culling out of the topology. The overlay path writes only
        // builtins plus `interacting` (which obj_node_renderer_top declares),
        // so a mis-targeted write there is visual, never a fault. Recorded
        // rather than fixed.
        if (_unit.kind == YADS_KIND_LINK) {
            var _body = _unit.renderer;
            if (_body != undefined && instance_exists(_body)
                && _body.object_index == obj_node_renderer
                && _body.node == _unit.node) {
                if (_body.image_speed != 0) { _body.image_speed = 0; }

                // DEGRADED ART FAIL-SOFT, the same one the overlay has below.
                // `image_index = mask` is only meaningful against a strip that
                // really carries all sixteen masks; an art layer older than
                // this GML ships the pre-D2 single-frame body, and writing 6
                // into it would either clamp, wrap or read out of range
                // depending on what the runtime feels like. So the write is
                // gated on the frame count, and a short strip silently keeps
                // frame 0 - the isolated pose - which is the same "legible
                // rather than absent" degradation the variant table takes.
                // image_speed = 0 above is asserted either way: it is what
                // holds a short strip on frame 0 in the first place.
                if (_body.image_number >= YADS_MASK_LEN
                    && _body.image_index != _unit.mask) {
                    _body.image_index = _unit.mask;
                }
            }
        }

        // Same test as the rescan, for the same reason: one liveness predicate
        // across the whole glow path, and the only one that is correct under
        // culling (GridUtils.gml:171).
        var _top = _unit.top;

        // NO OVERLAY TO ASSERT ONTO, and that is a resting state rather than a
        // fault. Only the connector pass caches an entry like this - it keeps a
        // connector in the graph so it still JOINS the units on either side of it
        // even when its art has not shipped or its renderer is not up (see
        // yads_glow_link_probe). Skipping without setting `dirty` is the whole
        // point: this is not evidence the world was rebuilt under us, and
        // dirtying on it would re-run the rescan every single frame for as long
        // as one art-less connector is on the farm.
        //
        // No unit cached by the STORAGE_NODES loop can reach this line - that
        // loop rejects a missing overlay outright - so this costs the fifty-crate
        // case one undefined compare per unit per frame and changes nothing about
        // its behaviour.
        if (_top == undefined) { continue; }

        if (!instance_is_alive(_top)) { _glow.dirty = true; continue; }

        // -------------------------------------------------------------------
        // THE FLOOR-BAND DEPTH PIN - the flat three's overlay, and nothing
        // else in the game.
        // -------------------------------------------------------------------
        // THE BUG. A rug's BASE renderer is pushed to get_floor_depth() at the
        // very END of create_furniture_renderer (Furniture.gml:1525-1530; the
        // `-= 1` there is for non-rugs, so a rug lands on the floor value
        // exactly). Its top_sheet_renderer is created ~575 lines EARLIER, at
        // Furniture.gml:946-952, and the branch that runs for a top-level grid
        // is
        //
        //     top_sheet_renderer.depth =
        //         get_instance_depth(renderer.y, -top_sprite_depth_offset);
        //
        // i.e. ORDINARY Y-SORT, computed before the base was moved and never
        // re-synced after. So a connector's glow y-sorts against the player,
        // the chests and the crates - and `top_sprite_depth_offset = 1` puts it
        // one step IN FRONT of its own row on top of that. A crate standing on
        // a carpet, which is the headline case of this whole feature, gets the
        // carpet's glow painted across its face. That is the 1.3c report.
        //
        // Vanilla never hits it: no shipped prototype declares depth_to_floor
        // and top_sprite together (0 of 371 with a top_sprite), so this engine
        // path has only ever run for us.
        //
        // WHY get_floor_depth() - 1. Depth sorts SMALLER = NEARER: the y-sort
        // is `floor(z_offset - yy)` (RoomServiceUtils.gml:4-8), so a thing
        // lower on screen gets a more negative depth and draws in front, and
        // the background stack runs the other way (dungeon: ground 2000..1200,
        // floor sprites 1150, shadows 1100, walls 1000..800, foreground wall
        // -1000, Game itself -15000). One step BELOW the floor value is
        // therefore one step in FRONT of the connector's own body, and still
        // some 1,150 steps behind every y-sorted actor, whose depths are
        // -y (negative for any y on the map).
        //
        // -1 IS THE ENGINE'S OWN SPELLING OF THIS, twice. It is what a non-rug
        // depth_to_floor object gets (Furniture.gml:1528, :971), and - exactly
        // our problem - it is how the engine draws a DECAL ON TOP OF A RUG:
        // Footsteps.gml:35-41 computes `node.renderer.depth - 1` for a
        // footprint landing on a depth_to_floor node and applies it at :97-99.
        // We are one line behind the engine on the same road, again. We spell
        // it get_floor_depth() - 1 rather than `_body.depth - 1` on purpose:
        // that keeps this write a pure function of the room and reads NOTHING
        // off the base renderer, which the paragraph below needs.
        //
        // THE BAND HAS OTHER TENANTS at exactly floor - 1: the base renderer
        // of the 11 vanilla depth_to_floor-but-not-rug prototypes (the pet
        // beds, the animal ball and gramophone, the teleportation pad,
        // Furniture.gml:1525-1530's `-= 1` arm), the floor_renderer of the 10
        // floor_sprite prototypes (crafting stations, forges, bridges,
        // Furniture.gml:968-971), and the placement preview
        // (obj_tile_cursor.gml:571-572). A pet bed standing on a lit carpet
        // TIES the glow's depth, and no GML tie-break exists - native draw
        // order decides. Cosmetic either way, and better than before, when
        // the glow drew in front of all of them unconditionally. Footprints
        // do NOT tie: our connectors declare no `footstep`, so a footprint on
        // one lands at get_floor_depth() itself, one step behind the glow.
        //
        // SHADOWS STAY ABOVE THE GLOW IN MOST ROOMS - the farm, the barns and
        // 72 of the 85 room maps put the shadow layer in front of the floor
        // layer - and that is the accepted outcome, not a guarantee. An
        // emissive glow drawn over every shadow in the room would be
        // defensible on its own terms, but it is not buildable: the shadow
        // layer's position relative to the floor layer is NOT STABLE ACROSS
        // ROOMS (dungeon has shadows at 1100 in front of floor sprites at
        // 1150; the 13 rm_farmhouse-family maps put FloorSprites in front of
        // Shadows, so THERE the glow draws over shadows, the player's
        // included), so `get_shadow_depth() - 1` means different things in
        // different rooms and in some of them it is wrong. The floor value is
        // the only anchor with one meaning everywhere, so the glow is anchored
        // to it and lands wherever the room puts its shadows.
        //
        // RE-ASSERTED PER FRAME for the body autotile's reason, verbatim: the
        // engine destroys and rebuilds every node renderer on a new day
        // (Grid.gml:1669-1671 from NewDay.gml:299) and on room entry
        // (Grid.gml:550, :579), and the rebuilt overlay is created bare on
        // y-sort again. Nothing in the engine writes this instance's depth
        // after creation - obj_node_renderer_top has a create and a draw and no
        // step, and the only other engine writes to a top sheet are
        // sprite_index swaps and the highlighter's blend/alpha - so the assert
        // fights nobody; it only has to outlive the rebuilds. Guarded on
        // inequality like the tint and image_speed below it, so it is a compare
        // on every frame but a write only on the frames it was really lost.
        //
        // NO IDENTITY GUARD, and the invariant that permits that is preserved.
        // The long note above explains why the overlay path takes none and
        // rests instead on "a mis-targeted overlay write is visual, never a
        // fault": every field it writes is either a builtin or a field
        // obj_node_renderer_top itself declares. `depth` IS A BUILTIN - the
        // engine writes it on undeclared instances routinely
        // (obj_furniture_previewer declares six fields and not depth, yet
        // obj_tile_cursor.gml:570-575 writes its depth from outside every
        // frame; Game.gml:7 assigns it bare in a create), so a write through a
        // recycled instance id cannot throw. It would move some other
        // renderer's sprite to the floor for up to one YADS_GLOW_TTL, which is
        // exactly the visual-never-fault property the section already accepts.
        //
        // KIND-FREE BY CONSTRUCTION: `glow_floor` was resolved from the
        // ObjectId-indexed table when this entry was built, so this costs one
        // bool test per unit per frame and no string work, no lookup and no
        // second definition of "which of our keys is flat".
        //
        // ORDERING IS LOAD-BEARING: get_floor_depth() is the FIRST engine
        // room query this per-frame path has ever made, and it is safe only
        // because it sits BELOW the instance_is_alive guard and because the
        // glow cache is reset on room change and rebuilt empty on every bail
        // - i.e. GRID is provably live whenever the cache is non-empty. Move
        // this call above the guard, or give the cache a way to survive a
        // room transition, and "a mis-targeted overlay write is visual,
        // never a fault" stops being carried by the write alone.
        if (_unit.glow_floor) {
            if (!_floor_asked) {
                _floor_depth = get_floor_depth();
                _floor_asked = true;
            }
            // undefined means the room has no floor-sprite layer to anchor to.
            // Leave the overlay where the engine put it rather than doing
            // arithmetic on undefined inside a per-frame hook.
            if (_floor_depth != undefined) {
                var _pin = _floor_depth - 1;
                if (_top.depth != _pin) { _top.depth = _pin; }
            }
        }

        var _want = _unit.lit ? _unit.glow_asset : _unit.offline_asset;

        // THE D2 "WOVEN" OVERLAY VARIANT, chosen by SPRITE NAME rather than by
        // image_index, because the overlay's frames are already spoken for: they
        // are its eight-frame pulse, and an overlay that spent them on adjacency
        // would be a connector whose glow stopped animating. So the mask picks a
        // SPRITE and the pulse keeps the frames - which costs nothing new here,
        // because swapping this instance's sprite_index is the mechanism this
        // whole section is built on.
        //
        // undefined table  -> not a connector, or an art layer with no variants:
        //                     keep the unsuffixed asset (`_glow` is byte-
        //                     identical to the v0 isolated variant, so this
        //                     degrades to Beta 1.3's look, not to nothing).
        // undefined entry  -> a half-shipped variant set: same fallback, per
        //                     mask. This is also the resting state of the three
        //                     FLAT connectors' offline table, which is undefined
        //                     on purpose: their BODY carries the shape and is
        //                     still drawn when the network is down, so one
        //                     shapeless dead-pad marker is correct for all
        //                     sixteen masks. Only the Cloud ships offline
        //                     variants, because only the Cloud's body lives in
        //                     its overlay.
        //
        // The bounds test is belt-and-braces - mask is built from four bits and
        // the tables are YADS_MASK_LEN long - but this runs every frame inside a
        // hook where a throw is uncaught, and every other array read in this
        // file is guarded for that same reason.
        var _table = _unit.lit ? _unit.glow_variants : _unit.offline_variants;
        if (_table != undefined
            && _unit.mask >= 0 && _unit.mask < array_length(_table)) {
            var _variant = _table[_unit.mask];
            if (_variant != undefined) { _want = _variant; }
        }

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
// Crates are the only units that store, so they are the only ones that report a
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
    if (_unit.kind != YADS_KIND_CRATE || _unit.size <= 0) { return make_color_rgb(64, 200, 214); }

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
// :403 takes node_rug_parent instead), and we return undefined for it, which
// yads_node_modifier turns into "declined" so vanilla's one-swing rug removal
// runs untouched. It still has to STOP the scan, because it stopped the
// engine's.
//
// SINCE BETA 1.3 SOME OF OUR OWN CONTENT IS A RUG - the four connectors - so the
// old reason for declining ("none of our units is ever a rug, so that is somebody
// else's node") is FACTUALLY DEAD. The behaviour is unchanged and now rests on a
// better reason: A CONNECTOR HOLDS NOTHING. The five-swing guard is a guard
// against knocking over a full crate by accident (see this section's header); a
// connector has no inventory, cannot have one, and drops itself back as an item
// in one swing like any rug. Protecting it would be pure friction - five swings
// to lift a carpet - guarding a loss that consists of one 3-fiber item that is
// handed straight back. Declining is the right answer for connectors and for
// vanilla rugs alike, so one `return undefined` still covers both.
//
// THE TWO SCANS AGREE CELL FOR CELL, which is the property this replication
// exists to preserve, and the mixed-layer cases are where that is worth spelling
// out. Both here and in Pick.gml the object layer is tested FIRST at each cell:
//
//   * connector UNDER a unit, at a cell the unit occupies - node_object_id is
//     set, so both scans resolve to the UNIT and section 10 protects it exactly
//     as it did before connectors existed. The carpet is not the target and
//     cannot be, which also means a connector whose footprint lies entirely
//     inside a unit's is unreachable until the unit moves. That is the engine's
//     own first-hit rule (Pick.gml:110-120), not ours, and it is a README line
//     rather than a bug.
//   * connector BESIDE a unit, connector cell first in the 2x2 window - both
//     scans resolve to the connector, we decline, and vanilla lifts it in one
//     swing.
//
// AND NEITHER ERASE TOUCHES THE OTHER LAYER, which is what makes the mixed cell
// safe in both directions. erase_rug_node clears only node_rug_id /
// node_rug_parent over the rug's own footprint (GridUtils.gml:109-146), so
// lifting a carpet out from under a chest leaves the chest standing and full -
// and lifts the WHOLE carpet, including the cells hidden under the chest, since
// it walks the rug parent's footprint rather than the picked cell.
// erase_object_node_data is the mirror image: it clears node_object_id /
// node_parent / node_top_left_x/y and never the rug arrays
// (GridUtils.gml:366-392), so picking the chest leaves the carpet lying there
// and the network re-forms around it on the next rescan. The one crossover is
// node_furniture_footstep, which the object erase wipes over its own footprint
// (GridUtils.gml:377-379) and would therefore strip from a carpet underneath -
// which is why the connector prototypes deliberately declare no `footstep`.
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

    // `any` is the table's own answer to "did any placed unit key resolve",
    // which is exactly what the three-way heart/block/panel test it replaces
    // asked while those were the only three keys. It stays correct as the key
    // list grows, and it costs one struct read instead of three.
    var _ids = yads_ids();
    if (!_ids.any) { return undefined; }   // content not installed

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

//
// 11. THE NODE-REPLACE MACHINE - the converter's engine
//
// ONE function turns a placed node into a different placed node on the same
// footprint with its contents intact, and both converter gestures are that one
// function with its two arguments swapped. It is the only code in this mod that
// holds a player's items OUTSIDE an inventory, even for a statement, so the
// whole section is written around that fact.
//
// WHY AN ERASE-THEN-WRITE AT ALL. There is no engine call that re-points a node
// at a different prototype: object_id, prototype, the collision cells, the
// renderer, the STORAGE_NODES registration and the node's own write_size_* are
// all written together by write_furniture_to_location and read back apart by a
// dozen callers. Mutating a subset of them by hand is how you get a node whose
// sprite disagrees with its footprint. So the node is destroyed and remade, and
// everything below exists to make that survivable.
//
// THE BITE, AND IT IS THE WHOLE REASON THIS IS NOT FIVE LINES:
// erase_object_node_by_parent IS NOT INERT ON A FULL CHEST. It reaches
// GridUtils.gml:287-323, which drains every slot and either drops the items on
// the ground (same location) or pushes them into grid.lost_items (elsewhere),
// and only then removes the node from STORAGE_NODES. Nothing is destroyed - that
// is the floor under every failure below - but "contents preserved" is broken
// the moment the erase sees a non-empty inventory. So the machine CAPTURES AND
// EMPTIES FIRST and erases second, and step 5 always finds nothing to spill.
//
// THE ESCROW IS THE THROW-SAFETY STORY. Between the capture and the restore the
// items exist in exactly one place: a plain array hanging off global.__yads.
// That struct is reachable from yads_tick, which runs every frame from
// Game.step_begin whether or not any menu is open, so a throw at any step leaves
// a record something else can find. A local variable would be unreachable and
// the items would be gone. Every mutating step stamps `stage` before it acts,
// and yads_convert_recover reads that stamp to decide what to put back where.
//
// AND IT NEVER LIVES TWO FRAMES. The sweeper sits immediately after
// yads_pick_poll at the head of the tick - poll stays first, because nothing
// that can throw may run ahead of the destructable restore - and it refunds once
// and clears. A retry loop around item custody is how duplication happens; the
// one concession is a single escalation, described over yads_convert_recover.
//
// save.game_saving FLUSHES IT TOO. The escrow is not serialized (this mod
// registers no modsave sidecar), so items sitting in it while the grids write
// would simply cease to exist. The save handler runs the same sweeper, after the
// pick flush and before anything else.
//
// WHAT CROSSES, AND WHAT MUST NOT. The grid serializer is a generic struct
// walker whose skip list is prototype / last_update / renderer / sub_grid_blob /
// parent_grid / write_size_x / write_size_y / active_toy_sfx (Grid.gml:1419-1428),
// so every other field on a node round-trips through the save and has to be
// carried by hand:
//
//   * use_in_crafting - PLAYER-SETTABLE, in the vanilla StorageMenu
//     (StorageMenu.gml:525-547), and re-derived from the prototype by every
//     write (Furniture.gml:871-873). A player who excluded this chest from
//     crafting expects the crate to stay excluded.
//   * chest_icon - the label the player chose for the chest. Reset to undefined
//     by the write (Furniture.gml:760).
//   * infusion - reachable and REAL: use_item.gml:122 stamps it onto the node
//     when an infused furniture item is placed, and Pick.gml:470/:513 hand it
//     back on pickup. Reset by the write (Furniture.gml:650).
//   * destructable - CARRIED BY NOBODY, deliberately. docs/safety-invariants.md
//     section "THE destructable CONTRACT": we may take a permission away for a
//     moment and may never grant one. The write derives it from the prototype
//     and then re-forces false on any TileFlag.Unbreakable cell under the new
//     footprint (Furniture.gml:646, :685-687), which is exactly the engine's own
//     answer. Copying the old value would let a stale true outlive the rule that
//     produced it.
//   * on and date_photo - nothing to carry. Both are written unconditionally by
//     every furniture write (Furniture.gml:651-652), `on` has no reader anywhere
//     in the corpus, and date_photo is only ever set for an is_date_photo
//     prototype, which no chest is.
//
// THE TWO PROTOTYPES ARE PLACEMENT-IDENTICAL, WHICH IS WHY STEP 6 CAN BE TRUSTED.
// Audited over all 59 pairs: same size, same inventory_size, same collision_grid
// (only the two cottage fridges override it, and the twin copies the source's
// "2" verbatim), and neither side overrides rule_grid, input_terrain,
// output_terrain, placeable_locations, sub_grid, rug, destructable, can_be_child
// or depth_offset. So every test inside furniture_test_flag_mask answers the same
// for the target as it did for the source, and the cells were vacated by our own
// erase one statement earlier. Gate 0f then closes the last gap by running the
// engine's OWN furniture_test_flag_mask against the target prototype, with
// ignore_object set so the source standing there is not counted - which makes
// the gate pass exactly when the write would succeed rather than approximately.
//
// ROTATION IS A NON-ISSUE, VERIFIED RATHER THAN ASSUMED. All 59 source
// prototypes declare a .south block and nothing else, so proto.cardinals has
// length 1 and furniture_rotation_amount(0, proto) is wrap(0, 1) == 0
// (Furniture.gml:2017-2020). The footprint gate at 0d catches the case anyway: a
// rotated node's write_size_x/y are swapped (Furniture.gml:2028-2035) and would
// no longer equal the target's size.
//
// THE THIRD GESTURE - THE UPGRADE - IS THE SAME MACHINE WITH ONE MORE THING IN
// THE ESCROW. Hold a vanilla chest ITEM at a placed chest or crate and the
// footprint ends up carrying the HELD chest's twin, with the old shell handed
// back as an item. Nothing above changes: the target is still an arbitrary
// ObjectId this function is pointed at, still gated by 0a-0g, still erased and
// re-written the same way. What changes is that the two prototypes are no longer
// the same chest's pair, and that has exactly two consequences, both of which
// were already gates rather than assumptions:
//
//   * 0d (footprint) and 0e (capacity) become REAL DOORWAYS a player meets,
//     because a different chest's twin can be a different size and can hold
//     fewer slots. Both were written as asserts against a future content set and
//     both are now load-bearing on the shipped one.
//   * 0f stays EXACT across families. furniture_test_flag_mask reads only
//     can_be_child, rug, size, rule_grid, input_terrain and placeable_locations
//     (Furniture.gml:1958-2010); the 118-prototype audit found that no chest
//     overrides any of the last five and 0d has just proved `size` equal, so two
//     chest prototypes of the same footprint answer that test identically. The
//     collision_grid difference the two cottage fridges carry is not read by it
//     at all - it is applied by the write, after the answer is in.
//
// AND THE SHELL IS CUSTODY, NOT BOOKKEEPING. Between the erase and the hand-off
// the player's old chest exists only as an ItemId on the escrow, so it is staged
// there BEFORE the capture, under the same sweeper, and it is popped before it is
// placed. It is also the one escrow field whose disposition is CONDITIONAL: the
// recovery paths can put the source back on the footprint, and paying an item for
// a shell that is standing in the world again would mint a chest. See
// yads_convert_settle_shell for the one compare that decides it.
//

// The escrow's stage stamps. Strings rather than numbers because they are read
// only by the sweeper's own ladder, they are never persisted anywhere, and the
// one time anybody reads one it will be in a debugger at 2am.
#macro YADS_CONVERT_CAPTURED "captured"
#macro YADS_CONVERT_EMPTIED "emptied"
#macro YADS_CONVERT_ERASED "erased"
#macro YADS_CONVERT_WRITTEN "written"
#macro YADS_CONVERT_REFUND "refund"

// Why yads_convert_check said no. OK is 0 so the caller can test it with one
// compare; DEFER is the one verdict that is NOT a refusal - it means "this is not
// our gesture", and the gesture must hand the press back to the engine untouched.
// Free to renumber: nothing persists one of these.
#macro YADS_CONVERT_OK 0
#macro YADS_CONVERT_DEFER 1
#macro YADS_CONVERT_REFUSED 2
#macro YADS_CONVERT_BLOCKED 3
#macro YADS_CONVERT_NO_ROOM 4
// Split out of REFUSED by the upgrade wave, and the split is the codebase's own
// rule applied rather than a new one: "one refusal, one string", split whenever
// the refusal has a fix the player can act on. For the two converter gestures
// this verdict is unreachable - a twin copies its source's size, and all 59
// sources are single-cardinal so nothing rotates (see the header) - so they map
// it back onto the general string and their behaviour is unchanged. For the
// UPGRADE it is reachable and common: 4 of the 59 twins are [3,2] and the other
// 55 are [4,2], i.e. 440 of the 3,422 ordered chest pairs, and "cannot be
// converted where it stands" would tell that player to move a chest that is
// standing exactly where it should be.
#macro YADS_CONVERT_FOOTPRINT 5

// The twin for a placed vanilla chest, and the source chest for a placed twin.
// Both are one bounds-guarded array read, both return undefined for anything with
// no pair, and the bounds test is load-bearing for the same reason yads_kind_at's
// is: these arrays are sized from the largest id the PAIRING resolved, and any
// object minted past that must read "no pair", never fault.
function yads_crate_for_chest(_object_id) {
    if (_object_id == undefined) { return undefined; }
    var _table = yads_ids().to_crate;
    if (_object_id < 0 || _object_id >= array_length(_table)) { return undefined; }
    return _table[_object_id];
}

function yads_chest_for_crate(_object_id) {
    if (_object_id == undefined) { return undefined; }
    var _table = yads_ids().to_chest;
    if (_object_id < 0 || _object_id >= array_length(_table)) { return undefined; }
    return _table[_object_id];
}

// THE UPGRADE'S TWO LOOKUPS, and both are the pair tables again rather than a
// third table, because a third table is a third thing to fall out of step with
// UNIT_KEYS.
//
// The twin a HELD ITEM would write. An item prototype's `object` is the
// ObjectId the item places, or undefined for everything that places nothing
// (Items.gml:51 builds it exactly that way, so the field is always present and
// is either a real or undefined). Feed that straight into the same
// source-chest -> twin table the convert gesture uses and the answer is
// "undefined unless this is one of the 59 convertible chests", with no new
// vocabulary: a hoe, a fish, a converter, a bed, another mod's chest and the
// three excluded fixtures all read undefined and defer.
//
// The [$ ] read on `prototype` is the house guard, not politeness: LiveItem sets
// it in its constructor (LiveItem.gml:5) and every live item therefore has one,
// but a bare read of an absent struct member faults on this runtime and this
// runs against whatever the player is holding.
function yads_twin_for_item(_item) {
    if (_item == undefined) { return undefined; }
    var _proto = _item[$ "prototype"];
    if (_proto == undefined) { return undefined; }
    return yads_crate_for_chest(_proto[$ "object"]);
}

// The object whose ITEM comes back when this node is replaced - the SHELL.
//
// A crate hands back the chest it was made from; a paired vanilla chest hands
// back itself. Anything the pair tables do not know has no shell and therefore
// no upgrade: netstor_block (a crate whose key carries no prefix, so no source),
// hearts and panels, the three excluded fixtures, every chest another mod ships,
// and every non-chest node in the game. That is the same "there is no exclusion
// list" mechanism the converter runs on, reused rather than restated.
//
// THE ORDER OF THE TWO READS MATTERS AND IS SAFE EITHER WAY: no key is both a
// twin and a source, because a twin's key is its source's key with
// "netstor_crate_" on the front and no such doubly-prefixed key exists.
function yads_shell_object(_object_id) {
    var _source = yads_chest_for_crate(_object_id);
    if (_source != undefined) { return _source; }
    if (yads_crate_for_chest(_object_id) != undefined) { return _object_id; }
    return undefined;
}

// EVERY GATE, AND NOT ONE MUTATION. Called twice per conversion on purpose: once
// by the gesture, before the confirm popup is built, so the player is never asked
// to confirm something that will then refuse; and once by the machine, on the
// frame it acts, because a popup is a frame or more of wall-clock time and the
// second call is what makes the first one advisory rather than load-bearing.
//
// Returns YADS_CONVERT_OK or one of the four verdicts above.
function yads_convert_check(_node, _target_object_id) {
    if (_node == undefined) { return YADS_CONVERT_DEFER; }
    if (_target_object_id == undefined) { return YADS_CONVERT_DEFER; }

    // 0a. A grid to write into.
    var _grid = _node[$ "parent_grid"];
    if (_grid == undefined) { return YADS_CONVERT_DEFER; }

    // 0b. NOT ON A TABLE, and this one is a renderer fact rather than a taste.
    //     A tabletop is a CHILD GRID (Furniture.gml:706-723), and Grid.write_node
    //     only calls initialize_node_renderer when self.is_setup
    //     (Grid.gml:208-215). Child grids are minted by `new Grid(...)`, which
    //     sets is_setup false (Grid.gml:50), and NOTHING ever sets it true for
    //     one - the six sites that set the flag are all location, dungeon or
    //     building grids. Their renderers come from the parent's own
    //     create_furniture_renderer, via child_grid.initialize_on_room_start
    //     (Furniture.gml:1549), which our write does not reach. Converting a
    //     chest on a table would therefore produce an INVISIBLE crate holding
    //     the player's items.
    //
    //     Refusing costs nothing anyone wants: a network never leaves its Grid,
    //     so a crate on a table could never join one, and Pick.gml:411-429
    //     collects child nodes on a swing at the TABLE, which voids the
    //     five-swing removal guard the units depend on.
    //
    //     THIS LINE IS THE SOLE CHILD-GRID GUARD, and gate 0f does NOT back it
    //     up, which is the opposite of what the shape of the two suggests.
    //     furniture_test_flag_mask opens with exactly this test
    //     (Furniture.gml:1959) - `grid.parent_node != undefined &&
    //     !proto.can_be_child` - and the second half is never true for a chest:
    //     vanilla's furniture.toml declares `[default] can_be_child = true`
    //     (:91, the [default] table opens at :7) and NOT ONE of the 59 source
    //     chests overrides it, while the mod's own furniture.toml sets it on no
    //     twin and carries no [default] of its own. Machine-checked over all 118
    //     prototypes, both sides. So 0f answers "fine" for a chest on a table and
    //     this compare is the whole defence. Delete it and the feature writes
    //     invisible crates onto tabletops.
    //
    //     WHAT IS *NOT* TESTED, stated so it is a known gap rather than a
    //     forgotten one: is_setup and location_id == CURRENT_LOCATION_ID, the
    //     other two halves of Grid.write_node's renderer condition
    //     (Grid.gml:208-212). A non-current-location grid is unreachable through
    //     interact() - the press comes from a node the player is standing next
    //     to - so the failure it would cause (an invisible, uninteractable node
    //     holding the player's items, exactly what 0b exists to prevent) has no
    //     construction today. It is worth naming anyway, because gate 0f below
    //     passes ignore_ari = (_grid != global[$ "__grid"]): the author of that
    //     line explicitly contemplated a grid that is not GRID, and the two
    //     assumptions should not be able to drift apart silently.
    if (_grid[$ "parent_node"] != undefined) { return YADS_CONVERT_REFUSED; }

    // 0c. A target prototype, and it has to be a chest.
    //
    //     NODE_PROTOTYPES is read through global[$ ] rather than the macro for
    //     the reason the glow poll reads STORAGE_NODES that way: a bare read of
    //     an unset global faults on this runtime, and this can run on frames the
    //     prototype table has not been built on.
    var _protos = global[$ "__node_prototypes"];
    if (_protos == undefined) { return YADS_CONVERT_DEFER; }
    if (_target_object_id < 0 || _target_object_id >= array_length(_protos)) {
        return YADS_CONVERT_DEFER;
    }
    var _proto = _protos[_target_object_id];
    if (_proto == undefined) { return YADS_CONVERT_DEFER; }
    var _chest = _proto[$ "interaction_chest"];
    if (_chest == undefined) { return YADS_CONVERT_DEFER; }

    // 0d. FOOTPRINT. Guaranteed by construction for a twin - the generator copies
    //     its source's size - and asserted anyway, because the assert is what
    //     makes that guarantee checkable rather than remembered, and because it
    //     is the test that catches a rotated source for free (see the header).
    //     [4,2] and [3,2] are both real shapes in the worklist.
    //
    //     THE UPGRADE MADE THIS A DOORWAY. For the two converter gestures the
    //     target is the source's own twin and the sizes match by construction;
    //     for the upgrade the target is a DIFFERENT chest's twin and the two
    //     footprints genuinely disagree 13% of the time, so this is now the gate
    //     a player meets rather than one that documents an invariant. It is also
    //     what keeps gate 0f exact across families: furniture_test_flag_mask
    //     reads only can_be_child, rug, size, rule_grid, input_terrain and
    //     placeable_locations (Furniture.gml:1958-2010), and no chest prototype
    //     overrides any of those five - so once the SIZE matches, two chest
    //     prototypes answer that test identically.
    var _size = _proto[$ "size"];
    if (_size == undefined) { return YADS_CONVERT_DEFER; }
    if (_size.x != _node.write_size_x || _size.y != _node.write_size_y) {
        return YADS_CONVERT_FOOTPRINT;
    }

    // 0e. CAPACITY, checked BEFORE anything is erased for a reason that has a
    //     body count: Grid.gml:1139-1145 force-resizes a loaded chest to its
    //     CURRENT prototype size and Inventory.gml:49-52 pops the trailing slots
    //     UNDRAINED. A target smaller than the occupied slot count would delete
    //     the tail on the next load, silently, in the player's save.
    //
    //     IT IS A REAL DOORWAY SINCE THE UPGRADE, not the assert it was. For
    //     convert and downgrade a twin copies its source's inventory_size and
    //     this cannot fire - which is why it was written down anyway, as the
    //     difference between a toast and deleted items on the day that stops
    //     being true. The upgrade points a DIFFERENT chest's twin at the node,
    //     and the shipped content set carries three capacities (54, 42 and 30
    //     slots), so a 30-slot chest held at a 40-stack unit lands here on the
    //     ordinary way through. The bound is `_chest.inventory_size`, i.e. the
    //     TARGET'S, which is the held chest's - exactly the rule the gesture
    //     advertises.
    var _inventory = _node[$ "inventory"];
    if (_inventory == undefined) { return YADS_CONVERT_DEFER; }
    var _occupied = 0;
    var _slots = _inventory.size();
    for (var _i = 0; _i < _slots; _i++) {
        var _slot = _inventory.slot(_i);
        if (_slot.count > 0 && _slot.item != undefined) { _occupied += 1; }
    }
    if (_occupied > _chest.inventory_size) { return YADS_CONVERT_NO_ROOM; }

    // 0f. THE ENGINE'S OWN PLACEMENT TEST, RUN BEFORE ANYTHING IS ERASED.
    //
    //     WHY THIS RATHER THAN A HAND-ROLLED CHECK. The one input to step 6 that
    //     our own erase does not control is whether a creature is standing in
    //     the footprint: write_furniture_to_location passes
    //     ignore_ari = (grid != GRID) as its eighth argument (Furniture.gml:642),
    //     the gesture always runs on the grid the player is standing in, so the
    //     Ari/pet/animal rectangle at :1966-1982 is LIVE for our write. A
    //     hand-written collision_rectangle would have had to reproduce that
    //     rectangle's boundary semantics exactly, and "close enough" fails in the
    //     one direction that costs a chest.
    //
    //     So this calls the SAME FUNCTION the write will call, with the same
    //     arguments, and takes its answer. The only argument that differs is
    //     ignore_object = true, which skips the per-cell occupancy test
    //     (:2004) - the one test the source is currently failing on purpose,
    //     because it is standing there, and the one our own erase clears one
    //     statement before the write runs.
    //
    //     THAT MAKES THE GATE EXACT RATHER THAN CONSERVATIVE: it passes exactly
    //     when the write would succeed, so step 6's failure arm is unreachable in
    //     the absence of an engine change, and a refusal here is a refusal the
    //     engine was going to make anyway - with the difference that nothing has
    //     been destroyed yet.
    //
    //     local_pos_is_valid (:611-613) is deliberately NOT re-tested: it only
    //     asks whether the footprint is on the grid, and the source is standing
    //     on it. Neither is the child-grid recursion arm (:594-608), which is
    //     unreachable for us twice over - gate 0b refused a child grid, and no
    //     chest prototype has a child_grid of its own.
    var _x0 = _node.top_left_x;
    var _y0 = _node.top_left_y;
    var _rot = furniture_rotation_amount(0, _proto);
    var _matrix = furniture_calc_rot_to_rotation_matrix(_rot, _proto);
    var _rot_data = furniture_mask_prep_vecdata(_size, _matrix);
    if (!furniture_test_flag_mask(_rot_data, _grid, _x0, _y0, _proto, _matrix,
            true, _grid != global[$ "__grid"])) {
        return YADS_CONVERT_BLOCKED;
    }

    // 0g. NO SECOND SURFACE AND NO SECOND CONVERSION. The view, the picker and
    //     the confirm popup cannot coexist with the gesture anyway - all three
    //     pause the world, and the interact ladder returns before reaching us -
    //     but "no other surface of ours is up" is an invariant this mod keeps for
    //     itself rather than inherits from somebody else's pause flag. The escrow
    //     test is the real one: a second replace starting while one is in flight
    //     would overwrite the first one's only record of where the items are.
    //
    //     convert_ask IS ON THIS LIST AND THE ESCROW IS NOT A SUBSTITUTE FOR IT.
    //     They are different objects: `convert` is the escrow, live for a
    //     statement, and `convert_ask` is the confirm popup, live for as long as
    //     the player looks at it. Without this line the ladder's vanilla-chest arm
    //     (boot.gml, the `_mine == undefined` branch) could raise a SECOND popup
    //     over the first - yads_open_convert overwrites _rt.convert_ask, orphaning
    //     the first _ask so yads_menu_closed's reference compare declines to clear
    //     it, and handing ANCHOR.get_menu two menus of one type, which is its
    //     "more than one was open" assert (Anchor.gml:154-174). A crash, not item
    //     loss - and it was standing on `[popup] pause = "main"` alone, which is
    //     exactly the external flag this mod refuses to rely on. Belt and braces
    //     with the ladder's own guard, the way view and picker are already
    //     guarded in both places.
    //
    //     AND IT DOES NOT REFUSE THE CONFIRM THAT OPENED THE POPUP, which is the
    //     one thing this line could plausibly break, because the executor clears
    //     convert_ask in the same statement it consumes the request
    //     (yads_convert_apply, boot.gml) and it does so BEFORE the re-gate. That
    //     ordering is load-bearing: ANCHOR's close() only sets free_requested, so
    //     ui.menu_closed - and with it yads_menu_closed's clear - does not fire
    //     until the free-requested drain at the head of the NEXT
    //     ANCHOR.on_begin_step (Anchor.gml:262-271), which is later in the same
    //     frame as our tick and never before it (mmapi_run_installs is the first
    //     statement of Game.step_begin, ahead of TICK++ and therefore ahead of
    //     ANCHOR). A gate 0g that read convert_ask without that clear would refuse
    //     every confirm this mod has ever raised.
    var _rt = yads_runtime();
    if (_rt.view != undefined) { return YADS_CONVERT_REFUSED; }
    if (_rt[$ "picker"] != undefined) { return YADS_CONVERT_REFUSED; }
    if (_rt[$ "convert_ask"] != undefined) { return YADS_CONVERT_REFUSED; }
    if (_rt[$ "convert"] != undefined) { return YADS_CONVERT_REFUSED; }

    return YADS_CONVERT_OK;
}

// THE MACHINE. Returns true when the node standing on the footprint afterwards is
// the target and holds everything the source held; false when it refused or
// rolled back, in which case the caller must NOT consume the converter.
//
// The step numbers below are the ones the throw table in docs/converter-facts.md
// is written against; keep the two in step.
//
// _swap IS THE UPGRADE'S WHOLE EXTENSION TO THIS FUNCTION, and it is undefined
// for both converter gestures, which pass it explicitly so that nobody has to
// remember an optional argument's default. When present it is
//
//     { shell: <ItemId>, infusion: <string or undefined> }
//
// and it says two things the two-argument form cannot:
//
//   * SHELL - the old node does not come back as itself, so the item that would
//     place it is owed to the player. It is staged in the escrow BEFORE the
//     capture, alongside the stacks and under the same sweeper, for the reason
//     the stacks are: between the erase and the hand-off it exists nowhere else,
//     and a throw with it in a local variable is silent deletion. Its
//     disposition is NOT unconditional - see yads_convert_settle_shell.
//   * INFUSION - what to stamp on the NEW node, which for an upgrade is not the
//     old node's. An upgrade is a PICKUP FOLLOWED BY A PLACEMENT and vanilla
//     stamps each half from its own item: a placed furniture node takes the
//     PLACED item's infusion (use_item.gml:122) and a picked-up furniture item
//     takes the NODE's (Pick.gml:511-513). Convert and downgrade are neither -
//     the same shell stays on the footprint - so they carry the node's own
//     infusion straight across, which is what passing undefined here means.
//     Getting this wrong in either direction destroys or mints a Quality
//     infusion, which is the one infusion whose supported_tags is ["furniture"]
//     (fiddle/infusions.toml) and therefore the one a chest can carry.
function yads_replace_node(_node, _target_object_id, _swap) {
    if (yads_convert_check(_node, _target_object_id) != YADS_CONVERT_OK) {
        return false;
    }

    var _rt = yads_runtime();
    var _grid = _node.parent_grid;
    var _x0 = _node.top_left_x;
    var _y0 = _node.top_left_y;
    var _source_object_id = _node.object_id;
    var _inventory = _node.inventory;

    // 1. DROP THE PICK COUNTER, restoring `base` while the node is still alive.
    //    The poll's liveness sweep would drop the entry within a frame anyway -
    //    the erase destroys the renderer (GridUtils.gml:170-172) and
    //    yads_pick_poll tests instance_is_alive on it - but that sweep runs
    //    yads_pick_release on a DETACHED node struct, writing `base` into a field
    //    nothing will ever read again. Releasing here puts the value back on the
    //    node while it is still the one in the grid, which is the only version of
    //    "every suppression we write is undone by us" with no exceptions in it.
    yads_pick_forget(_node);

    // 2. Mark the connectivity cache. Belt and braces: our own write raises
    //    furniture.place_guard, which invalidates it, and yads_glow_apply
    //    re-dirties when a cached overlay stops being alive. The full table is in
    //    docs/converter-facts.md; the redundancy is here so that a later refactor
    //    of either of those two cannot silently reopen the same-frame erase+write
    //    hole the STORAGE_NODES count poll has by design.
    yads_glow_invalidate();

    // 3. THE ESCROW, WRITTEN BEFORE THE SOURCE IS TOUCHED. Everything the
    //    recovery needs is in it before there is anything to recover - the
    //    stacks it is about to take, and, on an upgrade, the shell item that
    //    stops existing in the world at step 5.
    //
    //    `infusion` IS "WHAT THE TARGET GETS" and `shell_infusion` is "what the
    //    SOURCE had", which is both what the returned item gets and what a
    //    re-written source is put back with. They hold the same value for
    //    convert and downgrade, where the shell stays on the footprint and
    //    nothing is returned, and they differ on an upgrade for the reason
    //    spelled out over the signature: two different items, two different
    //    infusions, one each. yads_convert_restore picks between them by asking
    //    which of the two is actually standing, so no caller has to.
    var _escrow = {
        grid: _grid,
        x: _x0,
        y: _y0,
        source: _source_object_id,
        target: _target_object_id,
        slots: [],
        use_in_crafting: _node[$ "use_in_crafting"],
        chest_icon: _node[$ "chest_icon"],
        infusion: (_swap == undefined) ? _node[$ "infusion"] : _swap.infusion,
        shell: (_swap == undefined) ? undefined : _swap.shell,
        shell_infusion: _node[$ "infusion"],
        stage: YADS_CONVERT_CAPTURED,
    };
    _rt.convert = _escrow;

    // 4. CAPTURE AND EMPTY, one slot at a time, appending as we go so a throw
    //    part-way leaves the escrow describing exactly what has left the chest.
    //
    //    THE LIVE LiveItem, NOT A CLONE, and that is the opposite of what
    //    yads_link_remote does, for a reason rather than by oversight: the remote
    //    hands ONE of possibly several across an inventory boundary, so the
    //    source stack survives and aliasing would fragment it. Here the slot is
    //    emptied in the same breath, so the struct ends the statement with
    //    exactly one owner - the same argument vanilla's own Throw handler makes
    //    when it drains a stack and hands the structs over (Furniture.gml:1245).
    //
    //    slot.drain() IS FORBIDDEN. Inventory.gml:410-411 is
    //    `list = list == undefined ? List() : undefined;` - the argument test is
    //    inverted, so passing a list nulls it and the next push faults. Read the
    //    pair and call remove().
    var _size = _inventory.size();
    for (var _i = 0; _i < _size; _i++) {
        var _slot = _inventory.slot(_i);
        var _item = _slot.item;
        var _count = _slot.count;
        if (_count <= 0 || _item == undefined) { continue; }
        array_push(_escrow.slots, { item: _item, count: _count });
        _slot.remove(_count);
    }
    _escrow.stage = YADS_CONVERT_EMPTIED;

    // 5. ERASE. The source inventory is empty, so GridUtils.gml:288-320 finds
    //    nothing to drain and spills nothing; what it does do is deregister from
    //    STORAGE_NODES (:322), destroy the renderer, clear the collision on every
    //    footprint cell and detach the four per-cell grid arrays.
    erase_object_node_by_parent(_grid, _node);
    _escrow.stage = YADS_CONVERT_ERASED;

    // 6. WRITE, through Grid.write_node and NEVER through
    //    write_furniture_to_location directly.
    //
    //    THIS IS THE ONE PLACE THE BUILD DEPARTS FROM THE RECON'S SEQUENCE, and
    //    it is not cosmetic: write_furniture_to_location DOES NOT CREATE A
    //    RENDERER. Grid.write_node does, one line later, and only for a grid that
    //    is set up and current (Grid.gml:208-215). The bare call would have left
    //    a node that is invisible, uninteractable and unglowable, holding the
    //    player's items. write_node is also what vanilla's own placement uses
    //    (use_item.gml:103), and it keeps the GROW_BACK collider bookkeeping
    //    symmetric with the erase (Grid.gml:264-277 against GridUtils.gml:199-212)
    //    - moot for chests, none of which are grow-back candidates, and free.
    //
    //    The fourth argument is ctx, which the Furniture arm passes straight
    //    through as `rotation` (Grid.gml:258). Zero, which is also the only value
    //    a single-cardinal prototype can produce.
    var _new = _grid.write_node(_x0, _y0, _target_object_id, 0);

    if (_new == undefined) {
        // ROLLBACK R. Unreachable as the code stands - gate 0f is the engine's
        // own placement test run against this very prototype on this very
        // footprint, and the only thing it did not test is the occupancy our
        // erase then cleared - so this arm exists for the engine changing under
        // us, not for a case anyone can construct today. It is inline rather
        // than left to the sweeper because the world is exactly as we left it
        // one statement ago and the sweeper is a frame away. Re-write the SOURCE
        // on the footprint we just vacated: same size, same rules, same cells,
        // nothing ran in between.
        var _back = _grid.write_node(_x0, _y0, _source_object_id, 0);
        if (_back != undefined) {
            yads_convert_restore(_escrow, _back);
            // THE SHELL IS BACK IN THE WORLD, so it is not owed as an item.
            // Settling it here rather than leaving it to the sweeper is the same
            // argument the rollback itself makes: the world is exactly as we
            // left it one statement ago and we know what is standing on the
            // footprint, so nothing is served by a frame's delay. Cancelling is
            // what stops the rollback from paying the player a chest for a swap
            // that did not happen.
            yads_convert_settle_shell(_escrow, _back);
            _rt.convert = undefined;
            yads_glow_invalidate();
            create_notification(YADS_LOCAL_ROOT + "convert_failed", 60 * 3);
            return false;
        }
        // Both writes refused. Leave the escrow at "erased" and let the sweeper
        // have it next frame: it tries the source once more and then hands the
        // contents back to the player. There is nothing left that this function
        // could still save.
        return false;
    }
    _escrow.stage = YADS_CONVERT_WRITTEN;

    // 7. RESTORE, then release the escrow.
    yads_convert_restore(_escrow, _new);

    // 7b. THE SHELL, HANDED OVER WHILE THE ESCROW IS STILL REGISTERED. The
    //     target is standing, so the old shell is gone from the world and the
    //     item is owed - which is exactly what yads_convert_settle_shell
    //     concludes from the node it is shown, so the decision is made in one
    //     place for the success path and the four recovery paths alike. Then the
    //     hand-off pops it out of the escrow BEFORE it places it, the same
    //     ordering the refund arm uses on the stacks: a throw between the pop
    //     and the give loses at most this one item and can never mint a second.
    //
    //     ORDER AGAINST STEP 8: the escrow is released AFTER this line, so a
    //     throw inside the hand-off leaves a registered escrow with an empty
    //     slots array and possibly a shell, and the sweeper closes it next frame
    //     against a footprint the target is now standing on - which settles to
    //     "owed" again and pays it. That is the recoverable direction.
    yads_convert_settle_shell(_escrow, _new);
    yads_convert_hand_shell(_escrow);

    // 8. RELEASE THE ESCROW - AND ONLY IF IT IS EMPTY. This test is the whole
    //    difference between "de-register" and "de-register whatever is still in
    //    it", and the second one is silent deletion: the escrow is the only
    //    record of where those items are, so clearing it while it holds a stack
    //    or a staged shell destroys them with no toast, no log line and no
    //    backstop. It is the mistake this section refuses everywhere else -
    //    yads_convert_recover clears and then immediately refunds (:3772-3773),
    //    and its no-player arm (:3758-3759) would rather hold the escrow
    //    indefinitely than clear while holding something - and step 8 used to be
    //    the one de-registration in section 11 not paired with a hand-back.
    //
    //    TWO WAYS THE ESCROW CAN STILL HOLD SOMETHING HERE, both currently
    //    unreachable and neither provable at this line:
    //
    //      * yads_convert_restore ends its while on `_i >= _size` and returns
    //        SILENTLY with whatever did not fit still in _escrow.slots. It fits
    //        today for two reasons that both live outside this function: gate 0e
    //        proved _occupied <= target.inventory_size, and Furniture.gml:758-759
    //        mints node.inventory as a FRESH Inventory of exactly that size with
    //        every slot at count == 0, so restore's "never overwrite" skip never
    //        fires and the fit is total. Either premise moving reopens this.
    //      * yads_convert_hand_shell returns BEFORE popping when
    //        !instance_exists(obj_ari) (:3711), leaving the shell staged.
    //        yads_convert_apply proved the player exists at boot.gml:2626 in this
    //        same frame with no yield in between - again, outside this function.
    //
    //    LEAVE IT REGISTERED RATHER THAN REFUND INLINE, which is the same call
    //    step 7b makes one line up and for the same reason: the sweeper is the
    //    one place that knows how to finish an escrow, it runs at the head of the
    //    very next tick (boot.gml:646) and again from save.game_saving
    //    (boot.gml:2815), and it tries the GOOD outcome first - pour the
    //    remainder into whatever is standing on the footprint - before handing
    //    anything to the player. An inline refund would skip straight to the
    //    player's hands for a stack the target could have taken.
    //
    //    THE THREE INVARIANTS THIS KEEPS, spelled out because the shape looks
    //    like a retry and is not:
    //
    //      * NO DOUBLE-DRAIN. The stage is re-asserted as WRITTEN, never REFUND,
    //        so the sweeper takes its in-place arm exactly once (:3764) and every
    //        stack it places is array_delete'd out of the escrow before the slot
    //        write. The re-assert is a no-op against step 6's own stamp and is
    //        written out anyway, so that "what the sweeper will see" is decided
    //        here rather than inherited from forty lines up.
    //      * NO TWO-FRAME LIFETIME ON THE HAPPY PATH. Empty escrow, empty shell,
    //        and this clears in the statement that created it exactly as before.
    //        The second frame is bought only by a world that already went wrong.
    //      * GATE 0g STILL REFUSES. A live escrow is a REFUSED verdict (:3383),
    //        so no new gesture can start on top of one, and the tick runs the
    //        sweeper (boot.gml:646) strictly above yads_convert_apply (:663) -
    //        so a stranded escrow is closed before the next confirm executes.
    //
    //    The return value is unchanged and still true: the target is standing on
    //    the footprint holding what it could take, so the swap happened and the
    //    caller's two costs are payable. Returning false would leave a converted
    //    world nobody paid for.
    if (array_length(_escrow.slots) <= 0 && _escrow[$ "shell"] == undefined) {
        _rt.convert = undefined;
    } else {
        _escrow.stage = YADS_CONVERT_WRITTEN;
    }

    // 9. Re-mark the cache now that the new node exists. The place_guard already
    //    did this from inside the write; this line is what keeps the statement
    //    true if that guard is ever unregistered.
    yads_glow_invalidate();
    return true;
}

// Pour the escrow into a node, in capture order, and re-apply the three carried
// fields. Every stack it places is REMOVED from the escrow first, so the array is
// always the exact list of what is still homeless - which is what lets the sweeper
// resume after a throw without ever placing a stack twice.
//
// DIRECT SLOT WRITES, NOT Inventory.add. add() loops slot_for_item and MERGES into
// partial stacks (Inventory.gml:65-74), which would reorder the chest, and it
// RETURNS the remainder it could not place rather than raising - a return value
// that is very easy to drop on the floor. The three-line direct write is the same
// idiom the vanilla storage sort uses and the same one section 7 writes the mirror
// page with.
//
// The slot bound is re-read from the target rather than trusted from the capacity
// gate: the gate proved it fits and this proves it, and on some future content set
// where they disagree the difference is a REMAINDER LEFT IN THE ESCROW instead of
// a write past the end of the inventory.
//
// AND THE REMAINDER IS WHY THIS FUNCTION MAY RETURN SILENTLY. The while ends on
// `_i >= _size` with whatever did not fit still in _escrow.slots, and it raises
// nothing, because it is not this function's decision: it is a pour, and the
// caller owns the custody. Every one of the five call sites is followed by
// something that reads the array again -
//
//   * step 8 (:3583) refuses to de-register a non-empty escrow and leaves it for
//     the sweeper, which pours the rest into the standing node next frame and
//     then hands whatever still will not fit to the player;
//   * the inline rollback R (:3541) and the sweeper's two arms (:3820, :3835) all
//     fall through to yads_convert_refund, which empties the array into the
//     backpack and then onto the ground.
//
// So a remainder costs a frame and a toast, never an item. That was NOT true
// before the step 8 test existed: the success path used to clear the escrow
// unconditionally one statement later, and this comment used to promise "items in
// the player's hands instead of items nowhere" against a success path that had no
// player's-hands arm at all. The promise is now kept by the caller rather than
// asserted here.
function yads_convert_restore(_escrow, _node) {
    var _inventory = _node[$ "inventory"];
    if (_inventory != undefined) {
        var _size = _inventory.size();
        var _i = 0;
        while (_i < _size && array_length(_escrow.slots) > 0) {
            var _slot = _inventory.slot(_i);
            _i += 1;
            if (_slot.count > 0) { continue; }        // never overwrite
            var _stack = _escrow.slots[0];
            array_delete(_escrow.slots, 0, 1);
            _slot.item = _stack.item;
            _slot.count = _stack.count;
            _slot.updates += 1;
        }
    }

    // The three serialized per-node fields the write reset. destructable is
    // deliberately absent - see the section header.
    //
    // use_in_crafting and chest_icon follow the CONTAINER, in every direction
    // and on every path: they are choices the player made about the box in that
    // spot, not about the sprite on it, and an upgrade leaves a box in that spot.
    if (_escrow.use_in_crafting != undefined) {
        _node.use_in_crafting = _escrow.use_in_crafting;
    }
    if (_escrow.chest_icon != undefined) {
        _node.chest_icon = _escrow.chest_icon;
    }

    // THE INFUSION FOLLOWS THE SHELL, so it is chosen by WHAT IS STANDING rather
    // than by which of the five call sites we are in. Three of them (the inline
    // rollback, and the sweeper's two empty-cell arms) pour into a re-written
    // SOURCE, and two pour into the TARGET; on convert and downgrade the two
    // escrow fields are the same value and this is a no-op, and on an upgrade it
    // is the difference between putting the old chest back the way it was and
    // stamping the held chest's Quality onto it.
    var _infusion = (_node[$ "object_id"] == _escrow.source)
        ? _escrow.shell_infusion : _escrow.infusion;
    if (_infusion != undefined) {
        _node.infusion = _infusion;
    }
}

// IS THE SHELL STILL OWED? Asked once per escrow, against the node standing on
// the footprint at the moment of asking, and it is the whole reason the shell can
// be staged before the erase without ever being paid twice.
//
// THE RULE IS ONE COMPARE: the old shell is still in the world exactly when the
// node on the footprint is the SOURCE. Then the player already has it, standing
// where they left it, and an item on top of that would be a second copy. Every
// other world - the target standing (the swap happened), an empty cell (the erase
// took it and nothing replaced it), somebody else's node (ours is gone either
// way) - means the shell the player owned no longer exists, and the item is owed.
//
// TESTED AGAINST source AND NOT AGAINST target on purpose: those two are the same
// question only while the footprint holds one of ours, and the empty-cell and
// foreign-node cases are precisely where they differ. Source == target is
// impossible here - the upgrade's same-shell refusal is what removes it, and the
// two converter gestures never carry a shell at all.
//
// It cannot meaningfully throw: two guarded struct reads on a node the caller has
// already resolved. That matters because it runs inside the sweeper's one-shot
// window, and a throw here would fall through to the refund arm, which pays.
function yads_convert_settle_shell(_escrow, _node) {
    if (_escrow[$ "shell"] == undefined) { return; }
    if (_node == undefined) { return; }
    if (_node[$ "object_id"] == _escrow.source) { _escrow.shell = undefined; }
}

// THE SHELL, HANDED OVER. Popped from the escrow BEFORE it is placed, which is
// the refund arm's ordering and the refund arm's reason: the escrow is the
// custodian rather than a second copy, so "briefly in none" costs one item and
// "briefly in two" mints one.
//
// ARI.give_item IS THE WHOLE MAY-FAIL PATH IN ONE CALL, and it is the engine's
// own: room_for_item first, drop_item_stack at the player's feet for whatever
// does not fit, inventory.add for the rest, and grid.lost_items at the house door
// when there is no obj_ari at all (Ari.gml:465-495). That last arm is why this
// needs no player test of its own, though the sweeper has already made one.
//
// show_new_popup IS FALSE. give_item's "you found a new thing" arm builds an
// await_popup chain (Ari.gml:511-519), and this runs from the tick with the
// mod's own popup a frame in the rear-view; a chest is not a discovery worth
// risking a second menu over. The pickup toast and sound stay - the player just
// received an item and should see it land.
//
// THE LIVE ITEM IS BUILT THE WAY vanilla's own furniture pickup builds it
// (Pick.gml:509-515): mint from the prototype's item_id, and stamp the node's
// infusion only if the fresh item did not come with a default_infusion of its
// own (LiveItem.gml:15-16). try_string_to_infusion tolerates undefined - Pick
// hands it node.infusion unguarded, and every furniture write sets that field to
// undefined (Furniture.gml:650).
function yads_convert_hand_shell(_escrow) {
    var _id = _escrow[$ "shell"];
    if (_id == undefined) { return; }

    // NO PLAYER, NO HAND-OFF - AND NO POP EITHER, so the shell stays staged and
    // the sweeper's own no-player wait keeps the escrow alive until there is
    // somewhere to put it. give_item does have a no-obj_ari arm (it pushes to
    // the house grid's lost_items), but it reaches that arm only after
    // dereferencing ARI for room_for_item, and nothing in this mod reads ARI
    // without the instance test.
    if (!instance_exists(obj_ari)) { return; }

    _escrow.shell = undefined;

    var _live = new LiveItem(_id);
    if (_live.infusion == undefined) {
        _live.infusion = try_string_to_infusion(_escrow.shell_infusion);
    }
    ARI.give_item(_live, 1, true, false, true);
}

// THE SWEEPER. Runs from the head of yads_tick, immediately after yads_pick_poll,
// and again from save.game_saving. It is a LAST-RESORT REFUND, not a re-attempt:
// it tries the in-place restore for its stage exactly once and hands whatever is
// left back to the player.
//
// ONE ESCALATION, THEN GONE. The stage is stamped to REFUND before the in-place
// arm runs, so a throw inside that arm means the next frame skips it entirely and
// goes straight to the player's hands; and the refund arm de-registers the escrow
// before it starts. Two frames maximum, one attempt at the good outcome, one at
// the simple one, and no loop. The alternative shapes are both worse: clearing
// first would lose everything to a throw in the recovery, and never clearing would
// retry item custody forever.
//
// THE REFUND POPS BEFORE IT PLACES. Each stack leaves the array and is then put
// somewhere; a throw between the two loses at most that one stack and can never
// duplicate one. That ordering is the mirror image of yads_link_remote's
// add-then-remove and for the same reason: there, "briefly in two places" was the
// recoverable failure; here it is the unrecoverable one, because the escrow is the
// custodian rather than a second copy.
function yads_convert_recover(_rt) {
    var _escrow = _rt[$ "convert"];
    if (_escrow == undefined) { return; }

    // NO PLAYER, NO REFUND - AND NO CLEAR EITHER, which is the one place the
    // "never two frames" rule bends and it bends the safe way. With items still
    // in the escrow and no obj_ari there is nowhere to hand them, so clearing
    // would DELETE them; waiting costs one struct read a frame and the world
    // comes back within a few. This is not a retry around a failing operation -
    // it is a wait for a precondition, and the two exits from it (the next frame
    // with a player, or save.game_loaded, which drops the escrow of a save that
    // is being replaced anyway) are both bounded. Unreachable in practice: the
    // gesture cannot start without a player.
    //
    // A STAGED SHELL COUNTS AS SOMETHING TO HAND BACK, exactly like a stack:
    // it may turn out to be owed, and the arm that would pay it also needs a
    // player. Waiting is free and clearing would delete it.
    if ((array_length(_escrow.slots) > 0 || _escrow[$ "shell"] != undefined)
        && !instance_exists(obj_ari)) { return; }

    var _stage = _escrow.stage;
    _escrow.stage = YADS_CONVERT_REFUND;

    if (_stage != YADS_CONVERT_REFUND) {
        yads_convert_recover_inplace(_escrow, _stage);
    }

    // De-register before the refund, so a throw in the refund cannot bring us
    // back here a third time. What is left in slots at that point is lost - the
    // single residual, and it needs a bug in the loop below on top of the bug
    // that stranded the escrow in the first place.
    _rt.convert = undefined;
    yads_convert_refund(_escrow);
    yads_glow_invalidate();
}

// Put the contents back where they belong, if there is still a "there".
//
// CAPTURED - the source is still standing and only some of its slots were
//   emptied. Resolve the node at the footprint and pour the escrow back in.
// EMPTIED / ERASED - the source is gone, or at EMPTIED about to be (the throw
//   landed between the last remove and the erase). Probe the footprint: if a node
//   with an inventory is still there, fill it; otherwise re-write the SOURCE and
//   fill that. Re-writing the source rather than the target is deliberate - the
//   player asked for a conversion, did not get one, and should be handed back what
//   they had, not a half-finished version of what they wanted.
// WRITTEN - the target is standing and the restore threw part-way. The node at the
//   footprint is the right one; pour the rest in.
//
// A frame or more may have passed, so nothing here trusts a remembered struct: the
// node is re-resolved from the grid cell every time.
//
// A STAGED SHELL IS THE SECOND REASON TO RUN, and it is why the fast path below
// tests for one. An upgrade that stranded with an empty chest has nothing to pour
// and still has a decision to make - is the old shell standing or not - so it has
// to reach the probe. Convert and downgrade never carry a shell, so for them the
// test is `array_length(_escrow.slots) <= 0` and this function is what it was.
//
// THE SHELL IS SETTLED AGAINST WHATEVER THE PROBE FOUND, on every arm that ends
// with a node standing on the footprint, and left alone on the two arms that end
// with the cell empty or unresolvable - where "left alone" means "still owed",
// which is correct: the erase took the shell and nothing put one back.
function yads_convert_recover_inplace(_escrow, _stage) {
    if (array_length(_escrow.slots) <= 0 && _escrow[$ "shell"] == undefined) {
        return;
    }

    var _grid = _escrow.grid;
    if (_grid == undefined) { return; }

    // Cannot be undefined in practice: try_node_index_for_cell is a bounds test
    // against grid.dims (Grid.gml:85-91) and these coordinates came off a node
    // that was standing on this grid. Guarded because a fault here is inside the
    // one-shot recovery window.
    var _ni = _grid.try_node_index_for_cell(_escrow.x, _escrow.y);
    if (_ni == undefined) { return; }

    var _node = _grid.node_parent[_ni];
    if (_node != undefined && _node[$ "inventory"] != undefined) {
        yads_convert_restore(_escrow, _node);
        yads_convert_settle_shell(_escrow, _node);
        return;
    }

    // The cell is empty. Only the two stages that erased may re-write, and only
    // the source: at CAPTURED nothing was erased, so an empty cell means something
    // outside this mod took the node, and re-writing would be a second mod's
    // business. Either way the shell is left owed - the world has no chest on
    // that footprint, so handing the item back is the only way the player ends up
    // with what they started with.
    if (_stage != YADS_CONVERT_EMPTIED && _stage != YADS_CONVERT_ERASED) { return; }

    var _back = _grid.write_node(_escrow.x, _escrow.y, _escrow.source, 0);
    if (_back == undefined) { return; }        // the refund arm takes it
    yads_convert_restore(_escrow, _back);
    yads_convert_settle_shell(_escrow, _back);
}

// Whatever the in-place arm could not place goes back to the player: into the
// backpack while it fits, and at their feet after that. Both are the engine's own
// paths for exactly this - can_add then add is the guard vanilla's chest Throw
// predicate uses (Furniture.gml:1257), and a stack on the ground is what
// erase_object_node_data itself does with a chest it could not empty
// (GridUtils.gml:296-311).
//
// THE DROP SURVIVES A SAVE, and this is a CORRECTION: earlier waves shipped a
// "known residual" here claiming a dropped obj_item is not serialized and that a
// refund raised from save.game_saving with a full backpack therefore puts a stack
// somewhere the save will not record. That is FALSE, and it was false in the
// direction that makes a reader defend against nothing.
//
// save_game records loose world items, in this order (SaveGame.gml):
//
//    1  function save_game(save_path) {
//    2      var saver = new RustSaver(save_path);
//    3      Game.last_serde_path = save_path;   <- save.game_saving emits HERE
//   13-26      for (LocationId) { grid.save(saver); }
//   29      store_loose_items_as_lost();
//   38          var data = serialize_lost_items(grid.lost_items);
//
// The seam plants the emit immediately after line 3 (momi
// docs/MMAPI/seams/save_game_saving.md), so yads_game_saving - and this function
// under it - runs at line ~4, before a byte is written.
// drop_item_stack instantiates the obj_item on the spot
// (drop_item.gml:39-47: instance_create_layer then setup(items)), and
// store_loose_items_as_lost is `with obj_item { GRID.lost_items.push({x, y,
// items}) }` (Items.gml:687-696) - every live world item, unconditionally, no
// filter and no age test. serialize_lost_items writes them (Items.gml:711-729)
// and restore_lost_items re-instantiates them on load (Items.gml:698-709, via
// Grid.gml:517 over LoadGame.gml:331's deserialize).
//
// SO THE CONCLUSION THE OLD COMMENT PROPPED UP SURVIVES AND GETS STRONGER: this
// function is safe on BOTH of its paths. On the tick path the item is in the
// world and the player walks over it; on the save path it is on the ground when
// line 29 harvests it, so it persists as a lost item and comes back at the same
// coordinates on load. There is no unserialized-drop residual. The engine's own
// chest-erase drop (GridUtils.gml:296-311) has the same property, which is now a
// reason to trust it rather than a shared caveat.
//
// The one real residual in this function is the pop-then-place window on a single
// stack, stated over yads_convert_recover, and it needs a throw inside the
// four-statement loop below on top of the throw that stranded the escrow.
//
// THE SHELL RIDES ALONG, AND IT GOES FIRST. By the time this runs,
// yads_convert_settle_shell has already decided whether it is owed at all, so a
// shell still staged here is one the world no longer holds. First because it is
// the thing the player will look for - their chest - and because it is one call
// rather than a loop, so it is the smallest window in the function.
//
// THE TOAST IS RAISED FOR EITHER, which is why the early returns became
// conditions: an upgrade of an EMPTY unit that stranded past the erase has no
// stacks and still owes a chest, and a recovery the player is not told about is
// a chest that appears in their pack for no reason they can see.
function yads_convert_refund(_escrow) {
    var _gave = false;

    if (_escrow[$ "shell"] != undefined) {
        yads_convert_hand_shell(_escrow);
        // False only on the no-player bail, which leaves it staged rather than
        // spent - and which the caller's own guard has already excluded.
        _gave = (_escrow[$ "shell"] == undefined);
    }

    if (array_length(_escrow.slots) > 0 && instance_exists(obj_ari)) {
        var _backpack = ARI.inventory;

        while (array_length(_escrow.slots) > 0) {
            var _stack = _escrow.slots[0];
            array_delete(_escrow.slots, 0, 1);

            var _item = _stack.item;
            var _count = _stack.count;
            if (_item == undefined || _count <= 0) { continue; }

            // Pass the LIVE ITEM, never its item_id: room_for_item mints a
            // throwaway LiveItem for a bare id and partial_eq then fails against
            // anything carrying a variant (Inventory.gml:353-358).
            if (_backpack.can_add(_item, _count)) {
                _backpack.add(_item, _count);
                continue;
            }

            // drop_item_stack keeps the whole stack as ONE world item, which is
            // what the engine does with a drained chest slot; drop_item would
            // scatter `count` separate instances at the player's feet.
            var _list = List();
            repeat (_count) { _list.push(_item); }
            drop_item_stack(obj_ari.x, obj_ari.y, _list);
        }

        _gave = true;
    }

    if (_gave) {
        create_notification(YADS_LOCAL_ROOT + "convert_recovered", 60 * 3);
    }
}
