# NPC Contact interface schema

Captured on the RS3 plugin beta client while developing `npc-smartphone`.
IDs and layout may change with game updates; treat this as a working map, not a
stable public API.

UI modification lessons from reshaping this picker live in
[interface-capabilities.md](./interface-capabilities.md).

## Overview

Casting **NPC Contact** (Lunar spellbook) opens a picker titled **"Choose a
character"** — originally a grid of NPC chatheads with name labels underneath.
Selecting a portrait runs a **Speak-to** interface op and starts the contact
dialogue.

| Piece | Interface ID | Notes |
|-------|--------------|-------|
| Lunar spellbook host | `1886` | Contains the NPC Contact spell button |
| Contact picker | `88` | Present while the picker is in use; may linger after close |

There is no dedicated `InterfaceOpened` event. `GetInterface(88) ~= nil` alone
is **not** a reliable “picker visible” check — the interface object can exist
with `0×0` geometry or before slots spawn. Prefer: viewport size ≥ ~50×50,
`visibleGlobal ~= false`, and at least one contact label/button.

Slots populate over several `Event.Logic` ticks after open.

## Spellbook entry (pre-picker)

Right-click / hover on the NPC Contact spell yields MiniMenu entries on the
spellbook interface:

| Action | `MiniMenuActionType` | Value | Component |
|--------|----------------------|-------|-----------|
| Cast | `IF_BUTTONX1` | `57` | `iface=1886 static=1 cat=0 dyn=108 type=3` |
| Redial `'…'` | `IF_BUTTONX2` | `1007` | same component family; verb includes last contact name |

- `actionEntryType` = `INTERFACE` (`1`)
- `subjectText` includes colour tags, e.g. `<col=00ff00>NPC Contact`
- Strip tags before string matching: `gsub(text, "<[^>]+>", "")`

Persisted discovery keys (optional): `spellInterfaceId`, `spellStaticId`,
`spellCategoryId`, `spellDynamicId`.

## Contact picker (`iface=88`)

### Static scaffold (roles)

Observed while the picker is fully populated (approx. sizes on a typical
desktop layout; expect variation):

| Static | Type | Approx. size / pos | Role |
|--------|------|--------------------|------|
| `0` | LAYER (`20`) | ~471×284 @ `(5,5)`; scroll ~470×750 with chatheads | **Scroll viewport** for the contact grid |
| `1` | LAYER | ~470×750 @ `(0,0)` | Host for chathead **MODEL**s + Speak-to (`dyn=N`) |
| `2` | LAYER | ~470×750 @ `(0,0)` | Host for name **LABEL**s (`dyn=N`) |
| `3` | LAYER | ~16×284 @ `(475,5)` | **Scrollbar gutter** (track / thumb / arrows) |
| `4` | LAYER | ~512×334 @ `(0,0)` | Outer frame shell |
| `5`–`7` | LAYER | ~496×294 (e.g. `@ (8,32)`) | Mid chrome / content frame |
| `8` | LAYER | ~512×334 @ `(0,0)` | Outer chrome; title + border sprites |
| `9` | (interactive) | ~16×16 near top-right | **Close** — `ops={1:Close}` |

Parent walks from a contact label climb through these layers and then **out of
iface `88`** into toplevel UI (e.g. ~1440×-wide game viewport). Never `SetSize`
nodes whose `interfaceID ~= 88` or whose width looks like the game window.

### Title

| Address | Text |
|---------|------|
| `static=8 cat=0 dyn=14` | `Choose a character` |

### Contact slots

Each contact **N** (observed `N = 0 .. 28`) is a pair of dynamic children that
share the same `dyn` index:

| Role | Address | Observed type | Details |
|------|---------|---------------|---------|
| Chathead + Speak-to | `static=1 cat=0 dyn=N` | `4` (**MODEL**) | `ops={1:Speak-to}` when available; also the click target |
| Name label | `static=2 cat=0 dyn=N` | `2` (**LABEL**) | Plain display name in `content` |

Lookup helpers:

```lua
local button = ui.Interfaces:GetComponent(88, 1, 0, N) -- Speak-to / chathead
local label  = ui.Interfaces:GetComponent(88, 2, 0, N) -- name text
local name   = label and label.content
```

Grid layout with stock chatheads (beta capture):

| Metric | Approx. value |
|--------|----------------|
| Columns | `5` (dyn `0..4` = first row, etc.) |
| Label cell height | ~95 |
| Row pitch | ~125 |
| First label `baseY` | ~15 |

Clearing MODEL visuals does **not** collapse the grid. Labels stay in
chathead-sized cells until repositioned / resized. A names-only pitch around
~22 worked in testing. After packing, Speak-to MODELs are unhidden, visually
cleared, and moved onto those label cells so names remain clickable.

### Scrollbar (`static=3`)

- Not exposed as `layer.scrollbar` (unlike InputField / Combo).
- Dynamic children `dyn=0..6` are thin SPRITEs (~16px wide): track, thumb,
  up/down arrows.
- Hide the gutter layer and its children (`hidden = true`). Wheel interaction
  can resurrect chrome; re-apply while the picker stays open.
- Do **not** heuristic-match “any thin sprite on the right” — that also hits
  the right frame border under `static=8` (e.g. `dyn=7` @ x≈504).

### Other dynamic regions

| Parent static | Sample dyn range | Observed type | Notes |
|---------------|------------------|---------------|-------|
| `3` | `0`–`6` | SPRITE (`3`) | Scrollbar pieces |
| `5` | `0`–`2` | SPRITE | Panel / corner chrome |
| `8` | various | mix | Title at `dyn=14`; edge/corner border sprites (e.g. `dyn=6/7`, `11/13`) |
| `9` | `0`–`1` | under Close | |

### Slot list (beta capture)

`speak=false` means the MODEL exists and has a name label, but no Speak-to op
(content locked out by quest / account state — e.g. Cyrisus after WGS).

| dyn | Speak-to | Name |
|-----|----------|------|
| 0 | yes | Honest Jimmy |
| 1 | yes | Bert the Sandman |
| 2 | yes | Advisor Ghrim |
| 3 | yes | Spria |
| 4 | yes | Lanthus |
| 5 | yes | Sumona |
| 6 | yes | Mazchna |
| 7 | yes | Lapalok |
| 8 | yes | Vannaka |
| 9 | yes | Murphy |
| 10 | yes | Chaeldar |
| 11 | **no** | Cyrisus |
| 12 | yes | Chuck |
| 13 | yes | Kuradal |
| 14 | yes | Dark mage |
| 15 | yes | Pikkupstix |
| 16 | yes | Pauline Polaris |
| 17 | yes | Oneiromancer |
| 18 | yes | Islwyn |
| 19 | yes | Mieliki Tapio |
| 20 | yes | Morvran |
| 21 | yes | Urluk |
| 22 | yes | Laniakea |
| 23 | yes | Estate agent |
| 24 | yes | Jacquelyn |
| 25 | yes | Mandrith |
| 26 | yes | Polletix |
| 27 | yes | Raptor |
| 28 | yes | Random |

Order and membership can change with quests / expansions; always prefer reading
labels and ops from the live interface over hardcoding this table.

## MiniMenu behaviour on the picker

- Hovering the **window chrome** (and each portrait MODEL) produces INTERFACE
  MiniMenu entries on `iface=88`.
- Portrait entries use:
  - `verbText` = `Speak-to`
  - `subjectText` = empty
  - `actionType` = `57` (`IF_BUTTONX1`)
  - identity in `component.dynamicID` (the slot `N`)
- NPC **names are not** in MiniMenu subject/full text. Resolve names from the
  paired LABEL at `static=2 cat=0 dyn=N`.
- Left-click / selecting Speak-to is the legitimate player action. Plugins must
  not synthesize server actions (guidelines: no auto-performing actions; no new
  MiniMenu entries that send server ops).

## Component type cheat sheet (inferred from dump + docs)

`ui.ComponentType` docs do not publish numeric values; these match our capture
against the documented enum order:

| Numeric `type` | Likely enum | Evidence |
|----------------|-------------|----------|
| `2` | LABEL | Name strings in `content` |
| `3` | SPRITE | Scrollbar / border chrome |
| `4` | MODEL | Speak-to targets; chatheads |
| `20` | LAYER | Static layout parents |

Chatheads are almost certainly `ui.Model` with something like `NPC_HEAD`, but
model type / NPC id were not dumped in the discovery pass.

## Lifecycle notes (open → ready → reshape)

1. Shell appears: `static=0` gets real width/height (still may have no slots).
2. Dynamic contacts spawn over subsequent Logic ticks.
3. Stock layout: tall content (~750) inside shorter viewport (~284) ⇒ scrollbar.
4. For a names-only layout we (after slots are ready):
   - hide `static=3` gutter (+ children); refresh while open
   - pack `static=2` labels into a dense 5-column grid (labels `clickthrough`)
   - clear Speak-to MODEL visuals, move/resize onto those labels
   - shrink content hosts `1`/`2` and fit frame statics `0,3,4–8` by one shared
     height delta (snapshot sizes first to avoid double-shrink)
   - clamp `static=0` scroll region and `SetScrollPos(0, 0)`
   - on toggle-off, restore MODEL geometry/visuals and `MoveToFront` labels
     (`static=2`) so chatheads don’t stay stacked above names

Shortening the real layers also removes the old tall click-intercept region.
Speak-to stays on the stock MODEL ops; only position/visibility of those
components change. `hidden=true` on Speak-to MODELs removes the call action —
clear visuals instead.

## Plugin-facing recipe

1. On `Event.Logic`, treat the picker as open only when geometry + a contact
   slot look real (not merely `GetInterface(88) ~= nil`).
2. Wait until slots are ready.
3. When slots are ready, iterate `dyn = 0 ..` until several consecutive misses:
   - name from `GetComponent(88, 2, 0, dyn)`
   - Speak-to from `GetComponent(88, 1, 0, dyn).opConfig`
4. Reshape stock UI: pack labels, overlay cleared Speak-to MODELs on those
   cells, fit / hide scrollbar; and/or build search / favorites as a plugin
   overlay on `TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP`.
5. Keep Speak-to on the stock MODEL components (no op rebinding). Making those
   MODELs invisible and aligning them to labels is the allowed way to keep
   names clickable when chatheads are hidden.

## Related docs

- [Interface capabilities (this project)](./interface-capabilities.md)
- [MiniMenu](https://developer.runescape.com/rs/game/minimenu.html)
- [Interface](https://developer.runescape.com/rs/ui/interface.html)
- [Component](https://developer.runescape.com/rs/ui/component.html)
- [Model](https://developer.runescape.com/rs/ui/decorative_components/model.html)
- [Plugin guidelines](https://developer.runescape.com/rs/submission/guidelines.html)
