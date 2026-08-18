# Remote hotkey and network picker — engine facts

Split from `CLAUDE.md` (size rule), same as `anchor-ui-facts.md` and
`safety-invariants.md`. These are the findings behind the Remote Access Panel's
hotkey and the Beta 1.2 network picker. Read before touching `yads_remote_*`,
`yads_picker_*`, `yads_install_hotkeys` or the hotkey block of `yads_tick`.

The code carries the full derivations: `boot.gml` §5b (frame order), §5c (the
gesture ladder, the scan and the guards), §5d (the live rebind and the F6
rescue), `view.gml` §7 (the popup surface), §7f (the capture and its policy).

**`mmapi_hotkeys.gml` has two line-number namespaces and every citation says
which.** `payload:` is the 262-line file the 0.15.1 installer really writes into
`assets.zip` — what runs, and what everything the mod depends on is cited
against. `source:` is the 755-line file in the momi repo, which carries the
chord and pad machinery the installer strips; it is cited only where the point
is about something the payload does **not** contain. An unmarked `:650` used to
send a reader 387 lines past the payload's EOF. Same convention in `boot.gml` §5
and `view.gml` §7f.

> **2026-08-17 — THE TWO NAMESPACES HAVE MERGED.** MOMI 0.15.5 (the installer
> the owner ran at 18:10; `assets.zip` mtime 2026-08-17 18:10) stages a **756-line**
> `mmapi_hotkeys.gml`: the chord and pad machinery the 0.15.1 installer stripped
> is now IN the payload — `mmapi_hotkey_register_binding`, `mmapi_hotkey_register_pad`,
> `mmapi_hotkey_binding_from_name`, `mmapi_hotkey_name_from_binding`,
> `mmapi_hotkey_pad_from_name`, `mmapi_hotkey_name_from_pad`,
> `mmapi_hotkey_binding_held` and three `__mmapi_hotkey_*` helpers. So **every
> `payload:` anchor below is stale by the offsets in the table**, and the two
> claims that the payload lacks the chord/pad functions are now false. The eight
> other mmapi payload files (`mmapi.gml`, `mmapi_hooks.gml`, `mmapi_debug.gml`,
> `mmapi_local.gml`, `mmapi_events.gml`, `mmapi_combat.gml`, `mmapi_modsave.gml`)
> are **byte-identical** to the 0.15.1 payload — the config API, the
> `mmapi_run_installs` drain and `mmapi_emit`'s per-handler catch are untouched.
> `mmapi_hook_catalog.gml` only GAINED five hooks; all eight this mod registers
> are still present with unchanged kinds.
>
> Every load-bearing fact re-verified against the 0.15.5 payload and still true:
>
> | fact | 0.15.1 | 0.15.5 |
> |---|---|---|
> | `vk_from_name` vocabulary (38 names, identical set) | `11-56` | `16-61` |
> | `GAMEPAD_*` → `undefined` | `44-52` | `49-57` |
> | `name_from_vk` is the exact inverse | `63-94` | `68-99` (code identical, comments reworded) |
> | reverse lookup, guarded `vk_*` probes | `88-92` | `93-97` |
> | `register` head / registry init | `96-102` | `412-418` |
> | `register` engine KeyCode probe | `103-122` | `419-438` |
> | `register` early-RETURNS without pushing | `110-122` | `426-438` |
> | conflict Warn, both fire | `124-131` | `440-447` |
> | `array_push` is the only writer; entry is `{vk, callback, mod_name}` | `133` | `450` |
> | capability-report try/catch idiom | `169-175` | `515-521` |
> | poll has no pause / menu / room / text-focus test | `220-260` | `604-753` (keyboard arm `664-699`) |
> | poll snapshots the array LENGTH once, then re-reads each entry | `231` | `665` |
> | plain forward loop over push order | `232` | `666` |
> | `keyboard_check_pressed` = a press EDGE | `240` | `680` |
> | per-entry dead-marking, never the whole poll | `241-247` | `681-687` |
> | `entry.callback()` takes no arguments | `250` | `690` |
> | registers at payload file scope (`__mmapi_register_as`) | `262` | `755` |
>
> Three behavioural deltas, none of which breaks the remote:
> 1. `array_push` at `:450` is now preceded by `__mmapi_hotkey_warn_bare_overlap`
>    (`:449`), a log-only advisory. The pushed entry's shape is unchanged, so
>    §5d's live `entry.vk` mutation still lands.
> 2. The poll's `if (hotkeys == undefined) { return; }` is gone; the count is now
>    `(hotkeys == undefined) ? 0 : array_length(hotkeys)`. Still ONE snapshot
>    before the loop — the heal path's append is still seen on the next frame.
> 3. **NEW RISK, advisory only:** a chord registered by another mod runs FIRST
>    (`:619-660`) and CONSUMES its trigger code for that frame, so a bare
>    registration on the same key stays quiet. If a future mod binds e.g.
>    `SHIFT+F5` while the remote sits on `F5`, the remote misses that frame.
>    Nothing on our side can observe it; the rebind picker is the escape hatch.

## The poll is RAW, and it fires in our own frame

`mmapi_hotkeys_poll` has no pause test, no menu test, no room test and no
text-focus test, so the callback may do nothing but raise a flag. It registers
at mmapi payload file scope, ahead of `yads_tick` in the same
`mmapi_run_installs` drain, and the drain is a plain forward loop over push
order — so the tick consumes that flag **in the same frame the key went down**,
not the next one. Everything the press does is therefore gated by
`yads_remote_ready`: `instance_exists(obj_ari)`, `!game_paused()`, the FSM in
`{Default, MountDefault}`, no open view, no open picker, **no converter confirm
popup and no live convert escrow**.

Those last two are hardening rather than a fix, and neither was exploitable. The
confirm popup sets `PauseStatus.MENU`, so `game_paused()` already refused; the
escrow is closed by the sweeper at the head of `yads_tick`, strictly above
`yads_remote_press` in the same tick, so either it was gone or the throw that
stranded it also skipped the press. But that made the guard *tick order plus
somebody else's pause flag*, which is the same doctrine gap the `view` and
`picker` clauses exist to close — they are redundant against `game_paused()` too
and kept because they are the invariants this mod depends on. Two struct reads,
same argument. See `docs/converter-facts.md` for the escrow.

`game_paused()` is one call over a bitfield of `CUTSCENE | WINDOW | MENU`
(`Pause.gml:1-15`). `WINDOW` is OS window focus only — the two writers are
`Window.on_end_step`'s focus arms (`Window.gml:42`, `:53`) behind
`SETTINGS.get("pause_on_unfocus")`. In-game modals are covered by `MENU`
instead, because `[default] pause = "main"` in `ui/menus/standard_menus.toml` is
inherited by every entry in it, and `[popup]` declares the same in
`misc_menus.toml`.

**Auto-focus safety rests on the KEYCODE, not the frame.** F-keys deposit no
glyph into `keyboard_string()` (the engine has exactly one call site,
`Anchor.gml:470-486`, and it appends the raw return into every vanilla text
node with no filtering — if F-keys emitted glyphs, vanilla's own farm/pet/save
naming would be visibly corrupt). Nothing reads `vk_f6`: the engine names it in
three places, all non-readers (`InputUtils.gml:180`, `:590`, `:705`), and
`Settings.gml`'s binding table has no `vk_f*` at all. A **letter** hotkey does
not have that property; it is allowed — from the config file and from the
in-game capture, which accepts it with a warning printed on the hint line at the
moment it is chosen. F8/F9/F10 belong to the debug agent and the capture refuses
them outright.

## The rebind: how a live registration is re-pointed

The picker's footer carries a **Rebind key** button. It captures the next key
and applies it to the running game — registry, config file and hint together,
no restart. Everything below is a property of the payload the 0.15.1 installer
actually ships, not of the mmapi source tree.

**The poll re-reads the entry every frame.** `mmapi_hotkeys_poll` snapshots only
the array LENGTH (`mmapi_hotkeys.gml payload:231`). Inside the loop it takes
the entry fresh (`var entry = hotkeys[i]`, `:233`) and reads the field on the
spot (`keyboard_check_pressed(entry.vk)`, `:240`). So writing a new `vk` into our own
entry changes which key fires our callback on the very next poll. Nothing is
de-registered, and nothing could be: the payload has no unregister call.

**The entry reference is stable, but "register pushed one" is not.**
`array_push` is the only writer of `global.__mmapi_hotkeys` (`:133`) and there
is no remover, so the array is append-only and an index names one entry for the
process. But `mmapi_hotkey_register` early-RETURNS without pushing when the
engine rejects the KeyCode and the environment demonstrably has a keyboard
(`:110-122`). `yads_remote_register` therefore measures the length across the
call and only claims `_reg[_before]` when it grew by exactly one.

**The dead flag is permanent, and the capture proof retires it.** A KeyCode that
throws at poll time sets `entry.dead = true` and is skipped forever (`:234`,
`:241-247`). Nothing in the payload clears it — not register, not the poll, not
the capability sweep — so one bad `vk` written into our entry would kill the
remote hotkey for the session with no way back. The capture makes that
unreachable rather than guarding it: a `vk` reaches the commit only if it (i)
came out of `mmapi_hotkey_vk_from_name` and (ii) was **just** returned true by
`keyboard_check_pressed` on this frame. (ii) is a stronger proof than register's
own probe — register calls `keyboard_check` once and infers, while we have
watched the engine accept this exact code in this session. We still never write
over a corpse: a missing or already-dead entry gets a **fresh registration**
instead of a mutation, so mmapi keeps ownership of a flag we never set.

**A refused registration is reported, not papered over.** `yads_remote_rebind`
returns "the registry now answers this vk" — true on the mutation path, and on a
heal that registered; false only when the heal's `mmapi_hotkey_register` was
refused. `yads_picker_rebind_commit` reads it: on false it writes nothing, shows
`picker_bind_failed` on the hint line, arms the F6 rescue (that is the state the
rescue exists for) and **stays in capture**, so the next key pressed is still the
answer and ESC still cancels. Continuing would have written the config file,
rebuilt the hold hint and flashed "X is now your remote key" about a dead
binding. `yads_ensure_rescue` latches `rescue_installed` only **after** its own
pre/post length test passes, for the same reason: a refused rescue must be
retriable, not recorded as installed. Both are unreachable given the capture
proof above; both are written because everything else in those functions is
defensive against a proof it already has.

**The name is mmapi's reverse lookup, never the engine's.**
`mmapi_hotkey_name_from_vk` (`:63-94`) is written as the exact inverse of the
resolver — arithmetic for digits and letters, a probe of the forward map for the
named keys — so what it returns is guaranteed to parse back. The engine's own
tables spell the same keys lowercase (`InputUtils.gml:590`, `:705`) and
`vk_from_name`'s single-character arm tests `ord` against `"A".."Z"` only, so
`"f6"` round-trips to nothing.

**Everything DISPLAYED comes from the live binding, never from the
`remote_hotkey` string.** `yads_config` validates that field as "a non-empty
string" and nothing else (`boot.gml:441-442`), and an unresolvable name is
deliberately left in the file — `yads_install_hotkeys` warns, takes `vk_f6` and
does not repair the text (`boot.gml:980-989`), because it is the player's text
and may be a name a later mmapi resolves. So the picker's hold hint is built
from `mmapi_hotkey_name_from_vk(_rt.remote_vk)` (`view.gml` §7c), not from the
field. Reading the field would open the ONE surface that exists to repair a typo
with "Tap CTRL+F6 = default" — naming a key that does nothing, and contradicting
the `remote_key_bad` toast that has just said "using F6". It also makes that
line's width bound true rather than assumed: `name_from_vk` only ever returns a
name whose forward lookup yields the same vk (`payload:88-92`), so the display
vocabulary is exactly mmapi's own and its longest member is `PAGE_DOWN`. The
file self-heals on the next successful rebind, which writes this same
function's output.

**The vocabulary is 55 names and that is the whole space** — A-Z, 0-9, F1-F12,
INSERT, DELETE, HOME, PAGE_UP, PAGE_DOWN, SHIFT, CONTROL. The engine's own
`KEYBOARD_INPUTS` is far wider (`InputUtils.gml:123-200`: space, tab, enter,
brackets, punctuation, arrows) and every extra key would capture fine and then
fail to survive a restart, because only these names parse back. They are
resolved and probed with `keyboard_check` inside `try` once at capture entry —
mmapi's own capability idiom (`:169-175`) — so the per-frame scan is throw-free.

**A captured key that is still held cannot fire the gesture.**
`keyboard_check_pressed` is an EDGE. The frame that commits the rebind consumed
that key's press edge inside the capture poll, and `raw_keyboard` produces no
second `Pressed` for a key that never came up. So the first fire of the new
hotkey needs a release and a fresh press — which is also why the picker is not
still open underneath it: nothing fired.

## ESC during capture is a LOCK derivation, not `manual_exit_listening`

While capturing, the picker calls `menu.lock()` — `AnchorMenu.lock` →
`canvas.lock()` → `set_unlocked(false)` (`AnchorMenu.gml:337-343`,
`Node.gml:594-596`). One call, three effects:

- rows, checkboxes and Close leave the node loop's **clickable** arm, gated on
  `listens_for_hovers && safe_unlocked` (`Anchor.gml:377` — the statement, not
  the bare `//` above it, matching `view.gml:2454`'s pre-existing citation).
  Hover is not fully covered: `ANCHOR.try_pilot_hover` grants it on
  `!node.freed` alone (`Anchor.gml:1911-1923`), so a pad hover mark can still
  land on a locked node. Nothing follows from it — the pilot cannot **move**
  (`position_is_valid` returns `node.safe_unlocked`, `Pilot.gml:298-307`; an
  all-locked map returns `Freeze`, `:318-320`, `:440-442`), every mouse tap runs
  through the gate above, and the only pad confirm left on the plate is Close's
  glyph think, itself gated on `is_unlocked()` (`Node.gml:1833-1839`);
- `run_exit_listening` bails at its `canvas.is_unlocked()` test
  (`AnchorMenu.gml:170-183`), so ESC and click-outside cannot close the picker —
  **and `InputId.MenuBack` is left unclaimed for our own think to read as
  cancel**;
- every THINK keeps running, because the node loop gates on
  `run_logic && safe_enabled && !marked_for_death` (`Anchor.gml:374`) and lock
  touches none of those. Same fact `yads_picker_closing` already relies on.

Vanilla's rebind popup instead clears `manual_exit_listening`
(`SettingsMenu.gml:797`). That would be the wrong tool here: it silences the
exit listener and nothing else, so our rows would stay live and a click could
open a network while the capture waited for a key. Vanilla escapes that because
its capture is a fresh popup with nothing else on it — and it *still* locks the
surface behind it (`option_scroller.lock()`, `:795`).

`unlock()` restores exactly what was there: the propagation to children passes
`personal = false`, which leaves each child's own `unlocked` untouched and
recomputes `safe_unlocked` from it (`Node.gml:578-590`).

**The cancel must be taken in the THINK, never in `yads_tick`.** The tick runs
from the head of `Game.step_begin`, ABOVE `INPUT.begin_frame()`
(`Game.gml:570-582`), and `begin_frame` clears `input_overrides` and recomputes
every raw status for the frame (`Input.gml:26-33`) — a `take_press` up there is
answered from the previous frame and then overwritten. In the think we are after
`begin_frame` and inside the same walk. And the backplate *can* see `MenuBack`
even though the popup canvas overrides every `InputId` while it is up
(`PopupMenu.gml:305-309`, with `raw_status` returning `Off` for anything
overridden, `Input.gml:274-277`): the walk is REVERSE registration order
(`Anchor.gml:370`) and the canvas is created before the backplate it parents, so
the backplate is visited FIRST and the override loop runs after us every frame.
`take_press` mutes what it hands back (`Input.gml:270` → `:421-430`), and that
mute is **load-bearing**: cancelling unlocks immediately, and the canvas think
runs after us in the same walk, so `run_exit_listening` finds an unlocked canvas
and asks for `MenuBack` itself. It gets nothing — `process_binary` skips a
`Pressed` flag carrying `Muted` — so the picker survives the ESC that ended the
capture instead of closing on it. (An earlier version of this note also claimed
the mute protects `AnchorMenu.think`'s own exit listener, run after the whole
node walk at `Anchor.gml:653-656`. For a popup that listener never runs at all:
`AnchorMenu.think` gates on `listen_for_exit_flag` (`AnchorMenu.gml:162-164`),
seeded from `self.data.listen_for_exit` (`:89`), and `[popup]` sets
`listen_for_exit = false  # also handled manually`
(`ui/menus/misc_menus.toml:66`). A belt that was never buckled, not a hole.)

The capture also skips its FIRST frame (`armed: false`). The button's tap
callback runs in the same ANCHOR pass as the think — the button is registered
after the backplate and the walk is reverse — so anything down on the commit
frame would be captured as the choice. Vanilla skips exactly one frame for
exactly this, through the blackboard rather than a struct field
(`SettingsMenu.gml:820`, `:898-900`).

## What the capture refuses, and why

| verdict | keys | evidence |
| --- | --- | --- |
| deny, reserved | SHIFT, CONTROL | the search editor's OWN modifiers, read raw on every focused frame — `keyboard_check(vk_shift)` at `view.gml:2594`, `keyboard_check(vk_control)` at `:2647` — so a modifier hotkey fires the gesture in the middle of the player's own shortcut. STATIC for both: CONTROL is caught by the live table today only because `InputId.Walk` defaults to `"control"` (`Settings.gml:127`), and a player who rebinds or clears Walk would otherwise get a **silent** accept |
| deny, reserved | PAGE_UP, PAGE_DOWN | already ours — `yads_install_hotkeys` registers both as the view's pager |
| deny, reserved | F8, F9, F10 | mmapi's debug agent claims exactly those (`mmapi_debug.gml:967-969`) |
| deny, game | any hit from `BINDINGS.inputs_using_keycode(vk)` | `Input.gml:523-537`, the LIVE table, so it follows a player's own rebinds. Stock: W A S D E Q T G M R C and 0-9 (`Settings.gml:120-164`) |
| accept, warn | **every** letter | the poll has no text-focus test, so a letter also types into the search box. Every single-character name that survives the deny-game clause returns `WARN_LETTER`, so `YADS_REBIND_OK` is unreachable for a letter |
| accept, warn | F12 | Steam's overlay takes it for screenshots on most installs |
| accept, silent | F1-F7, F11, INSERT, HOME, DELETE — eleven keys, no letter among them | F2 and DELETE are **not** unread: both are the vanilla Bugger console toggle (`Bugger.gml:122`). It is compiled out — `BUGGER.update()` runs only under `if DEBUG_TOOLS` (`Game.gml:578-579`, `Setup.gml:449-450`) and `BuggerInitialize.gml:2` returns early without it — so the verdict is right and the reason is "dead in retail". Nothing reads the other nine |

The old form of this table put "unclaimed letters" in the silent row and gave
"nothing reads them" as the evidence for F2. Both were wrong about the shipped
code; the behaviour never matched either claim.

**The SHIFT deny is not about the search box**, and the wrong reason is what
left CONTROL asymmetric for a wave. While that box has focus the network view is
open, and `yads_remote_ready` refuses every press in that state
(`_rt.view != undefined`, `boot.gml:1607`) — `yads_remote_press` clears the flag
and returns with no scan and no toast (`:1622`, `:1627-1630`). The search box is
protected by the gate; this list exists because a bare modifier is a bad
shortcut and because the gesture would resolve against the player's own combo.

ESC is on neither list because it cannot arrive: `vk_escape` has no name in
mmapi's vocabulary, so it is not in the scanned array at all. It reaches this
surface only as `InputId.MenuBack`, i.e. as cancel.

**No binding-type filter on the deny-game test, and that is derived.**
`inputs_using_keycode` compares raw keycodes across keyboard, mouse and pad
bindings alike, so in principle a pad constant equal to one of ours would be a
false hit. It cannot be one of ours: every code in the vocabulary is a member of
`KEYBOARD_INPUTS`, and `keycode_to_binding_type` classifies by that array before
it looks at the pad one (`InputUtils.gml:388-400`) — a pad binding carrying one
of these numbers would be a code the engine itself calls a keyboard code.

## The two F6 layers

**(a) The fallback.** A `remote_hotkey` the resolver cannot parse now takes
`vk_f6` **with the full gesture ladder**, plus the log warn and a one-shot toast
on the first press that could act. This INVERTS Beta 1.2's "one warn and no
hotkey", and the reason is that the surface which repairs a bad binding is now
*behind* the hotkey: no hotkey means no picker means no Rebind button, so a typo
would be a locked door with the key inside. F6 is hard-coded on that arm rather
than resolved through `YADS_REMOTE_KEY`, because it is the arm where a name
already failed to resolve.

**(b) The rescue.** `vk_f6` is registered a SECOND time, hold-only, whenever the
active key is not F6 — `yads_ensure_rescue`, idempotent behind
`rescue_installed`, called from install and from every rebind commit. Not
registered on a default install, because two entries on one vk is supported
(mmapi logs a conflict Warn and fires both, `:124-133`) but the Warn would be
noise in every log and both callbacks would answer one press. The callback
carries the mirror guard the latch cannot: a player can rebind BACK to F6
afterwards and there is no way to take a registration back, so from that frame
`if (_rt.remote_vk == vk_f6) return;` stands the rescue down and lets the ladder
answer alone.

**Primary precedence on a shared frame is that mirror guard, not push order.**
Install order is PAGE_UP, PAGE_DOWN, primary, rescue, and the poll is a forward
loop over it (`payload:232`) — but `yads_remote_rebind`'s heal path *appends* a
fresh primary, which lands **after** the rescue, and from then on the loop
visits the rescue first. It does not matter: the only state in which both
entries fire on one frame is both carrying `vk_f6`, i.e. `_rt.remote_vk ==
vk_f6`, which is precisely what guard 1 tests — and `yads_remote_rebind` writes
`_rt.remote_vk` on its first line, before it touches the entry. The second
guard (`remote_pending == YADS_PRESS_PRIMARY`) earns its place against a
**stale** flag instead: if `yads_tick` throws above the hotkey block the flag
survives unconsumed, and the guard suppresses one rescue press rather than
acting on it.

Hold-only is what keeps the rescue from being a second hotkey: a tap of F6 after
rebinding to J does nothing at all. `_rt.remote_hold` is one slot carrying
`{ frames, vk, rescue }`, so the poll counts the key that actually fired rather
than re-reading `_rt.remote_vk` — which is what lets one watch serve a gesture
running on F6 while the remote key is something else.

## Chords and pad binds are absent from the payload

`mmapi_hotkey_register_binding`, `mmapi_hotkey_binding_from_name` and
`mmapi_hotkey_register_pad` exist in the mmapi SOURCE tree but not in the 0.15.1
installer's payload. Calling one is a strict-lint finding, and one finding
excludes the whole mod, content included. `check_symbols.py` cannot catch it —
its corpus is the source checkout, which is ahead of the exe. Only the momi lint
reads what will really be installed. One keyboard key, no modifiers.

## The hold gesture, and why it needs no try/catch

The poll hands out a press EDGE and nothing else, so "is it still down?" is our
question. `_rt.remote_hold` is one slot carrying `{ frames, vk, rescue }`, and
`yads_remote_hold_poll` reads `keyboard_check` on **`_hold.vk`** — the key that
actually fired — once per frame for as long as an armed press has not resolved.
It is a snapshot rather than a live read of `_rt.remote_vk` because the F6
rescue's gesture runs on a different key from the remote key (see "The two F6
layers").

The engine rejects a KeyCode it has no entry for, which is why mmapi wraps its
own poll in a try/catch and retires the entry that threw
(`mmapi_hotkeys.gml payload:241-247`). Our poll only ever runs because one of
our two callbacks fired, and both are reached only from the statement after a
successful `keyboard_check_pressed` on the very code the watch then reads (`:240` → `:250`)
— so the engine has already accepted it this session. That holds for the
rescue's `vk_f6` exactly as for the primary's key, which is why one function
serves both. Both functions take the same KeyCode through
the same conversion; the engine's own text driver reads them against one code in
consecutive statements (`Anchor.gml:489`, `:497`). No try/catch in a function
that runs every frame of a hold.

Counting is uniform: `yads_remote_press` seeds `frames` at 0 and the poll, which
the tick runs immediately after it, takes it to 1 — so every frame the key is
down adds exactly one, press frame included, and `YADS_REMOTE_HOLD` is a plain
"24 frames of holding" (400ms at 60fps).

## The arming predicate

Write `C` for the number of bound hearts and `D` for "a VALID default exists".
`T` is what a tap does, `H` what a hold does:

| state | T | H | | armed |
| --- | --- | --- | --- | --- |
| `C = 0` | toast | toast | same | no |
| `C = 1`, `!D` | open it | picker | differ | **yes** |
| `C = 1`, `D` | open it | picker | differ | **yes** |
| `C >= 2`, `D` | default | picker | differ | **yes** |
| `C >= 2`, `!D` | picker | picker | same | no |

Waiting is only worth its latency where `T` and `H` differ — three rows — and
all three now arm:

    armed  <=>  (C == 1 || D)

`C >= 2, !D` is the one row that never qualified and still doesn't: its tap
opens the picker on the press frame, so arming would spend 400ms reaching a
surface the player is already looking at. Which is the whole point of the
headline — **holding the key always shows the picker**, in every state with a
network bound. Where the hold is armed it shows after 400ms; in `C >= 2, !D`
the press frame shows it sooner. There is no state in which a player holds the
key and nothing happens.

That sentence is what every instruction we ship says (README, Nexus page,
`remote_key_bad`), and the whole point of this correction is that it is now
true rather than nearly true.

**Two predicates fell here, and both were locally right.** The first cut
shipped `C >= 2 || D` and paid release latency on a row its own table marked
"same outcome" (B12p wave-1 A-m1) — still valid, still why that row is out.
The picker audit corrected it to `D` alone, dropping `C = 1, !D` on the ground
that the hold there "offers only a checkbox whose default the tap ladder
reaches anyway". True of the checkbox and false of the surface: the **Rebind
key** button lives in that same footer, so one bound network and no default
made the picker — and with it the only in-game way to change the remote key —
unreachable. It came back from play as "holding F6 does not seem to do
anything", which is precisely what an unarmed hold looks like. This is the
third predicate and the first one field-driven: the rebind feature turned the
picker into the mod's settings surface, and an arming rule tuned for tap
latency had quietly made that surface conditional.

The C == 1 arm costs one key release on a single-network tap, which is
imperceptible, and buys the whole settings surface. It is not a special case
bolted on — it is the `C = 1` rows of the table, which always read `differ`.

The predicate reads a **validated** default rather than "the file has one",
because an unmatched default changes no tap outcome — the ladder falls through
it — so arming on it would add 400ms for nothing. At `C = 1` a stale default is
now doubly harmless: validation fails, `D` is false, the `C == 1` arm holds the
row anyway, and the release opens the sole network, which is the same node the
default would have named had it matched.

Clearing a default is possible from any `C`, by two routes now: `D` re-arms the
hold that opens the list that unticks it, and at `C = 1` the hold is armed
whether or not `D` holds.

**The hint line is the predicate's public face** (`view.gml` §7c). Its
no-default state carries both jobs — "Tick a default, hold `<key>` = this
list" — so the hold is taught in the state that has no default as well as in
the state that has one. The property the picker audit praised, "the hint
mentions the hold exactly where the hold is armed", is no longer a plain
complement of the predicate and is replaced by a stronger one: **the hint's
hold claim is true in every state it is visible in.** In `C >= 2, !D` the hold
is unarmed and the claim still holds, because the press frame produces the same
list. The line promises the list, not the latency.

## The default's identity is a string, not a LocationId

`remote_default_loc` stores `location_id_to_string(id)`, not the integer.
`LocationId` is minted from the fiddle tables at load and renumbers whenever the
installed content set changes, and the config file is per **install**, not per
save. The engine itself persists location ids as strings for the same reason —
every grid file round-trips through `location_id_to_string` /
`string_to_location_id` (`LoadGame.gml:36`, `:83`, `:249`).

The other two keys are the node's own `top_left_x` / `top_left_y`, the same pair
the flood-fill keys its visited set on. A default that names a heart the loaded
save does not have simply fails to match in `yads_remote_scan`, `default_index`
stays -1, and the tap ladder behaves as if the file were empty. That is why no
sidecar and no `YADS_CONFIG_VERSION` bump were needed.

Residual, noted not defended: child grids (table surfaces) **inherit** their
owner's location id (`Furniture.gml:708`), so two hearts sharing a cell
coordinate in one room — one of them on a table — would be one identity. Our
units are 4x2; a table surface has no such footprint to offer.

## A popup can carry taps, and the picker's rows do not overlap

`Menu.Popup` is the only menu type a mod can spawn outright: a hand-rolled
`AnchorMenu` subtype has to borrow an existing menu's fiddle config
(`AnchorMenu.gml:63`), which then lets `ANCHOR.get_menu` find two menus of one
type and trip its assert (`Anchor.gml:154-174`), and borrowing `Menu.Storage`
would collide with the very view the list exists to open.

The status popup proved only that a popup can hold text. `PopupMenu.create_button`
(`PopupMenu.gml:58-108`) proves the rest: it is a nine-slice on the backplate
with `set_sprites_from_key`, `add_hover_outline`, `set_tap_callback` and
`add_to_pilot` — the engine's own popup buttons are ordinary ANCHOR clickables,
built by the same calls as the network view's own widgets.

Inherited free: ESC and pad-back (the canvas think runs `run_exit_listening`
every frame, `:301-305`), the pause (`[popup] pause = "main"`), and the pilot
(`spawn()` takes it at `:260-263`, `on_close` hands the previous one back at
`:49-51`).

**Row geometry is the hover argument.** ANCHOR grants hover to at most one node
and `hover_node` releases the previous holder unconditionally, wiping its
`in_hover`, `in_tap` AND `tap_is_deferred` — so two overlapping hover listeners
cannot both work in either registration order (see `anchor-ui-facts.md`). The
clear-X had no way out of its overlap: it must sit inside the text plate because
the plate is the field. A picker row has no such constraint, so the two controls
are non-overlapping siblings:

    row (positional, 230 x 18)          local x 0..230, y 0..18
      open   LeftIn  x 0,  208 x 16     x   0..208, y 1..17
      box    RightIn x -2,  16 x 16     x 212..228, y 1..17

`Align.RightIn` is `x + parent.cache_x + parent.width - node.width` and
`Align.Middle` is `floor((parent.height - node.height) / 2 + 0.5)`
(`anchor_utils.gml:232-239`, `:267-273`), so both lie wholly inside the row with
4px of dead positional between them. No `listen_for_hovers` gate, no per-frame
poll to keep one alive, no bbox trim. Neither the row container nor the backplate
can steal either: `listens_for_hovers` is only ever set by `set_tap_callback` /
`listen_for_taps` (`Node.gml:519-520`, `:486-487`), and `set_think_callback` sets
`run_logic` alone (`:540-550`).

## Closing the picker to open a view: `request_hide(0)` first

`AnchorMenu.close` does not remove a menu from `ANCHOR.open_menus`. It sets
`close_requested` and, through a chain, `free_requested`; the per-frame drain at
the head of `Anchor.on_begin_step` (`Anchor.gml:262-273`) is what frees it. Our
tick runs before that drain, so a closing popup and a freshly spawned view are
both on `open_menus` for the rest of the frame. Harmless in itself — `get_menu`
only asserts on two menus of one type, and the drain removes the popup's `MENU`
pause flag and then re-ORs the flag from every menu still open (`:282-286`), so
the view keeps the world paused.

What is **not** harmless is the popup's think. It calls `INPUT.override_input`
on every `InputId` for as long as `mutes_input` holds (`PopupMenu.gml:305-309`),
a merely-locked canvas keeps thinking (the node loop gates on
`run_logic && safe_enabled` alone, `Anchor.gml:374`), and `[popup]` declares
`close_transition` with `fade_out_frames = 10`. A plain `close()` therefore gives
the new view ten frames of `raw_status` returning `Off` (`Input.gml:276`). Clicks
would still land — the node walk reaches the view's nodes before the popup's
canvas — but `MenuBack` is taken after the walk (`:653-656`), so ESC would do
nothing for a sixth of a second.

`request_hide(0)` before `close()` fixes both halves: the instant branch calls
`canvas.disable()`, which fails the node loop's `safe_enabled` test so the think
never runs again; and the second `request_hide` that `close()` performs for the
transition returns at `hide_requests > 1 && !instant` (`AnchorMenu.gml:271-273`)
without starting an ease, so `in_transition()` is false and the awaiting chain
sets `free_requested` at its first look.

## Registration is asymmetric, on purpose

`_rt.view` is set immediately after the menu spawn: registration attaches the
reconciler, and a throw before it leaves a live, withdrawable, UN-reconciled
mirror. Registering early cannot wedge, because a Storage menu can always be
closed.

`_rt.picker` is set **after** `spawn()`. A throw between `popup_creator` and
`spawn()` leaves an unspawned popup on `open_menus` with a disabled canvas, which
never runs `run_exit_listening` and therefore can never be closed by the player.
Registering that would make `yads_remote_ready` refuse every press for the rest
of the session. The orphan is the status popup's exposure too and is unchanged by
where the line sits; what the line decides is whether the hotkey dies with it.

`ui.menu_closed` is the only release site for either, and it tests the picker
stamp **first** — a picker routinely closes on a frame when no view exists, and
the old `_rt.view == undefined` early-out would have skipped the release and
wedged the hotkey behind the picker clause until the next save load.

## You cannot unplug the antenna through the antenna

In a **remote** view the bound remote's own cell is visible, tooltipped and
completely inert. In a **local** view (Access Panel) it is unchanged, and
withdrawing it there is still the documented unlink gesture.

**The asymmetry is the lockout, not the gesture.** Unlinking is fine at the
network, because the network is right there to hand the remote back to. Through
the remote it is one misclick away and irreversible from where the player is
standing: the binding is containment, so the withdrawal ends it; `yads_deposit_fit`
refuses to let a remote back into the network at all (H2), so putting it back is
answered with a refund and no re-link; and the only surface that re-links is a
Storage Heart the player has just cut themselves off from. From the bottom of the
mines the repair is the walk home. Every other item in the mirror is fungible;
this one is the door key, and it was reachable through the door.

**The mechanism is `InventoryMenu`'s own read-only-slot seam, and it kills both
directions with one flag.** `refresh_slot` ORs `filter_callback(slot)` into
`soft_lock` (`InventoryMenu.gml:180-182`) and parks it on the square's blackboard
(`:191`). The square's think then takes the soft-locked branch **instead of**
`input_check` (`:253-260`), and `input_check` is the sole entry to PickUp, PutDown
and Transfer and to every gamepad variant of the three (`:315-437`). Both
directions had to die together: a PutDown onto an occupied cell is a **swap**
(`:406-411`), so a hand carrying anything would have extracted the remote exactly
as a click on it would. `ANCHOR.take_tap()` in that same branch eats the press and
plays `UIUnableToInteract` (`:255-258`), and the icon draws at half alpha (`:186`),
which is the same "you cannot take this" the menu already shows on every cell when
the backpack is full. No toast: detecting the refused click would need a listener
of ours over the grid, which `anchor-ui-facts.md` forbids outright, and the
engine's sound is already the feedback. No new art either - `spr_ui_inventory_slot`
ships no `_hovered_untappable` frame and `anchor_utils.gml:2517` falls the key back
to the ordinary hovered sprite, so a soft-locked storage cell looks in our menu
exactly as it looks in vanilla's.

The pad is safe by construction: `soft_lock` writes a blackboard entry and an
alpha, never `unlocked` or `enabled`, and `Pilot.position_is_valid` reads
`safe_unlocked` alone (`Pilot.gml:296-307`). The cell stays navigable and answers
the confirm with the refusal sound, rather than becoming the dead stop that
`set_enabled(false)` would have made of it.

**Nothing the reconciler reads can see any of it.** The whole mechanism is node
state: a `Map` entry and a node alpha. `slot.updates` is untouched, so
`updates_sum` is untouched and the fast path still returns on the compare;
`partial_eq` is untouched, so the per-key diff is unchanged; and nothing moves,
because the only mover is the reconciler and it was never told.

**The lock follows the ITEM, never the cell**, which is what makes the 45 recycled
cells safe. `yads_remote_slot_filter` is a predicate on `_slot.item`, and the
engine re-derives it in `refresh_slot` for every cell it repaints, so a page flip
that puts iron ore where the remote was clears the lock with no bookkeeping of
ours. Two holes needed closing by hand, and both live in `yads_project`:

- **The emptied cell.** `refresh_slot` RETURNS at `count == 0` before it reaches
  the board (`:164-168`), so the engine cannot clear a flag off a cell it just
  emptied. Left alone that is a phantom that refuses deposits into a slot the
  mirror is advertising as free, and it is a hole vanilla has too. The projection
  clears it on the empty branch, which is safe precisely because nothing else can
  write an empty cell's flag.
- **The one-frame gap.** `refresh_slot` runs from the InventoryMenu CANVAS's think
  (`:19-29`, `:209-211`) and the node walk is reverse registration order
  (`Anchor.gml:370`), so the canvas is visited AFTER all 45 of its squares. Our
  tick is above the whole walk, so a cell we repaint is read by this frame's square
  thinks and only re-derived at the end of it. The projection therefore asserts the
  flag with the item, and the engine's re-derive later in the same frame agrees.
  `yads_soft_lock_square` only ever writes TRUE, except on that empty branch:
  `refresh_slot` ORs a second clause we do not own ("the backpack cannot take
  this", `:174-177`), and writing false onto an occupied cell would unlock a cell
  vanilla means to be locked.

There is no third writer to worry about. The mirror's cell CONTENTS are written by
`yads_project` and by the reconciler's own strip, and the two vanilla buttons that
would have permuted them behind our back are repointed at build: the left banner's
`inventory.sort()` and the right banner's `pair.add()` quick-stack
(`view.gml` §2e). A vanilla sort would have moved the remote to another cell
between two refreshes; it cannot run.

## Recorded residuals (picker audit and rebind wave)

- **A foreign menu on top of a live capture: REACHABLE, and now handled.** The
  rebind wave first recorded "a second popup over the picker drops our capture's
  lock without ending the capture (`PopupMenu.gml:36-47`, `:252-258`) —
  unreachable today". It is not unreachable: that reasoning covers menus *we* or
  the *player* open, and the engine opens one on its own account. When the last
  gamepad leaves `gamepads_connected()` while `active_input_type` is `Gamepad`,
  `INPUT.begin_frame` creates and spawns `GAMEPAD_LOST_POPUP`
  (`Input.gml:133-148`) with no pause test, no menu test and no room test — a
  controller unplugged or a battery dying mid-capture. `begin_frame` runs before
  `ANCHOR.on_begin_step` in the same step (`Game.gml:573`, `:582`), so the very
  first frame the capture think sees is already covered. Covered, the capture is
  half-deaf: the foreign canvas think overrides every `InputId`
  (`PopupMenu.gml:305-309`) ahead of us in the reverse walk (`Anchor.gml:370`),
  so `take_press(MenuBack)` reads `Off` (`Input.gml:274-278`) and ESC cannot
  cancel — while `keyboard_check_pressed` is raw and would still **commit** a
  rebind through a modal the player is reading.

  **Fixed** in `yads_picker_capture_think`: if `ANCHOR.open_menus.last()` is not
  our menu, the capture takes the same exit ESC takes (end capture, unlock, keep
  the picker open). `open_menus` is a `List` pushed in creation order
  (`Anchor.gml:148`) and nothing reorders it, `last()` is O(1) and answers
  `undefined` on an empty list (`List.gml:435-441`), and comparing menu structs
  by identity is the engine's own idiom (`PopupMenu.gml:41`, `:255`).

  **The unlock under a still-live foreign modal is safe, checked not assumed.**
  Every route from an unlocked node of ours to an *action* ends in
  `INPUT.take_press`: the node loop's tap arm calls `ANCHOR.take_tap`
  (`Anchor.gml:404` → `:1832-1834`), `check_for_click_close` ends in the same
  call (`:1570-1577`), and Close's glyph think is `take_press` too
  (`Node.gml:1833-1839`). All read through `raw_status`, which returns `Off` for
  an overridden `InputId`, and the foreign popup re-asserts that override every
  frame it is up — through its fade as well, because the override block sits
  *outside* the `close_requested` test (`PopupMenu.gml:301-309`). What survives
  is a hover outline on a row, which is cosmetic. So the unlock does **not** need
  deferring until we are top of the stack again. The remaining exposure is one
  cancelled capture the player did not ask to cancel, on a frame where a modal
  just took the screen.

- **The orphan-popup exposure.** `popup_creator` pushes the menu onto
  `open_menus` and ORs `PauseStatus.MENU` (`Anchor.gml:257`,
  `AnchorMenu.gml:111-112`) BEFORE the mod decorates it, and the canvas stays
  disabled until `spawn()` — so a throw during row-building would leave the
  game permanently paused behind a menu with no visible content, with mmapi
  swallowing the throw. Audited unreachable today (`ARI` never cleared after
  `Game.gml:12`, `LOCATIONS` bounds-checked, `yads_scan` guarded), but every
  new read added to row-building re-opens the question. Same class as the
  status popup, wider surface. Check this list before adding a row field.
- **ESC and a row click on the same frame: the click wins.** The reverse node
  walk (`Anchor.gml:370`) fires the row tap before the canvas think takes
  `MenuBack`, so the network view opens despite the dismissal. No corruption,
  one surprising frame, not worth a guard.
