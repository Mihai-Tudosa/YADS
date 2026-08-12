# ANCHOR UI facts — hover, tap, lock and visibility

Split from `CLAUDE.md` (size rule). These are engine facts about the ANCHOR UI
system, each paid for with a real bug. Read before adding or changing any
clickable in `view.gml`.

## NEVER OVERLAP TWO HOVER LISTENERS

ANCHOR holds one `current_hovered_node`, and `hover_node` releases the previous
holder unconditionally — clearing its `in_hover`, `in_tap` and `tap_is_deferred`
(`Anchor.gml:1806`, `:1862-1864`). The walk is REVERSE registration order
(`:370`), so the node registered FIRST is visited LAST and wins; registering a
button last hands it the hover only to have it stolen back in the same frame.
Ordering cannot fix it in either direction (`take_tap` mutes the press,
`Input.gml:270`, so the thief gets nothing either). Suppress the loser instead:
`listen_for_hovers(false)` is the whole gate (`Anchor.gml:377`) and touches
neither lock, enabled, art nor pilot — vanilla toggles it per frame from a think
(`anchor_utils.gml:1004-1014`). This was the Beta 1.1 clear-X bug: the search
plate (a hover listener by virtue of its tap callback, `Node.gml:519-520`) stole
hover from the X every frame, which both flickered the hover art and wiped the
X's deferred tap before the release frame — a completely dead button that passed
two static audit waves.

## Hover acquisition is move-gated; release is not

Hover is acquired only when `mouse_is_active` (moved this frame, or a button is
down — `Anchor.gml:231`, `:387`) but released on any frame the pointer is
outside. So a widget that loses its hover once per frame reads as "hovered only
while the mouse moves", and its art can still flash: `key_sprite_target` art is
chosen during the node's own step (`:600-618`), before a later thief runs.
Residual this implies: a widget that APPEARS under a parked pointer shows no
hover until the first pixel of movement (or a press). Accepted for the clear-X.

## The audit lesson

Both Beta 1.1 waves verified each mechanism's semantics in isolation and missed
the interaction. For any UI change: walk ONE FULL FRAME of the anchor loop, in
iteration order, with all listeners present — hover acquisition, theft, tap
defer, release — before calling it verified. Semantics-per-call is not enough.
