# Architecture

Target design `npc-smartphone`. Companion docs:

- [npc-contact-interface.md](./npc-contact-interface.md) — iface `88` schema
- [interface-capabilities.md](./interface-capabilities.md) — what we can read/mutate

## North star: maintainability

This plugin will be reviewed by a human before production. Code should make
that job easy.

| Guideline                  | Meaning                                                                                                                                                       |
| -------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Short, well-named methods  | Names and signatures should make inputs and outputs obvious. Prefer small functions over long procedures.                                                     |
| Shared terminology         | Align with RS3 API and PrettyUI concepts (`Component`, `Interface`, `Layer`, Speak-to, `SimpleView`, etc.) where those are the real things being manipulated. |
| Useful abstractions        | Encapsulate when it hides complexity or isolates impurity — not for its own sake.                                                                             |
| Modules group related code | Related behaviour lives together; unrelated concerns do not share a file.                                                                                     |
| Idiomatic Lua              | Tables as records/modules, `require` for boundaries, factories for stateful libs, explicit returns.                                                           |
| Prefer purity              | Pure functions are easier to read and unit-test. Touch the RS3 API and other globals only at well-defined edges of the plugin.                                |
| Accurate type annotations  | EmmyLua/`---@` on functions we write: real `@param` / `@return` / `@class` shapes (narrow duck types over vague `table` when the contract is known). LuaLS-only — not runtime. |

Additional feature constraint: **if all plugin options are off, behaviour
matches the original NPC Contact interface.** That identity should be
assertable in tests against a captured snapshot where possible.

### Guideline that must never be violated

We must not duplicate or synthesize clickable options that perform game
actions. The user must ultimately click the original Speak-to component.
We may mangle that component freely (resize, clear visuals, overlay our own
chrome) but Speak-to stays bound to the stock MODEL and cannot be reparented.

## Fundamental UI architecture

The plugin is built like a small UI app on top of the RS client:

```
plugin state (options, last-contact, …)
        │
        │  subscribe / notify
        ▼
   view adapters  ──►  component (props → element tree)  ──►  host bind
        ▲
        │
 capture / game events (picker open, layer ready, …)
```

UI surfaces follow **component → element → host**:

1. **Component** — pure function of props that returns a declarative element
   tree (`type`, `props`, `children`, event handlers). Testable without a
   UI backend.
2. **Element** — host-agnostic vnode protocol (`lib/element.lua`).
3. **Host** — mounts/patches that tree onto a backend (PrettyUI today;
   a native/stock iface host can be added later without rewriting
   components).

Settings already use this split: `settings/view.render` → element tree →
`lib/prettyui_host` via `lib/bind` (definition = host/render/subscribe;
`mount(parent)` per surface). Bind has no store knowledge — the app closes
over domain state in `render` / `subscribe`. Contact picker work still lands
on the same idea, with a second host for Speak-to bind.

### State and notify

Options and session values live in a domain **state store**. Changes go
through the store; the store **notifies subscribers**. Views (settings hub,
settings ribbon, open contact picker) subscribe and re-render from current
state. Surfaces do not sync each other ad hoc.

Notify after a successful commit (including persistence where relevant).
Skip notify when the value is unchanged. Programmatic UI updates must not
re-enter `set` in a loop (compare-before-set and/or silent updates).

### Capture → component → host

For any surface that draws UI:

1. **Capture** inputs needed for that surface (game UI scrape and/or current
   state).
2. **Component** — pure transform of those inputs into an element tree
   (options applied here).
3. **Host** — mount/update/destroy that tree on live components.

Settings change → rebuild element tree → host update. Picker becomes ready →
same path. That is the rebuild loop; it is intentional and similar to
ordinary UI libraries.

### Two write surfaces when pushing

Plugins cannot create new interfaces. They attach children under an existing
parent (`ui.Type.new(parent, …)` or PrettyUI helpers), and/or mutate stock
components in place.

| Surface                 | API                                              | Used for                                             |
| ----------------------- | ------------------------------------------------ | ---------------------------------------------------- |
| Plugin-owned components | `ui.*.new` / PrettyUI / `Destroy`                | Labels, headers, chrome, settings controls, overlays |
| Stock components        | `SetPos` / `SetSize` / `hidden` / `SetModel` / … | Speak-to MODELs, optional hide of vanilla chrome     |

`parent` on stock components is read-only — Speak-to MODELs cannot be
reparented into a PrettyUI tree. `opConfig.opNames` is read-only — Speak-to
cannot be copied onto a plugin button.

So a “virtual tree” may _reference_ Speak-to leaves as borrowed stock
components with desired geometry/visuals. Push is a reconciler with **two
backends**: create/update/destroy plugin nodes, and mutate stock Speak-to
(and related) components in their original parents.

Custom contact chrome always sits on top of a live iface `88` whose Speak-to
targets have been aligned to the presented layout.

### Settings vs contact views

Both are views of plugin state and can share the same element protocol and
rebuild discipline. They do not share one mega-module:

|            | Contact picker                           | Settings (hub + ribbon)                             |
| ---------- | ---------------------------------------- | --------------------------------------------------- |
| Host       | iface `88` (+ optional overlay)          | PrettyUI on Settings/Content layer `event.component` |
| Capture    | open/ready detection + parse stock slots | mostly current state (+ PersistentDB on load)       |
| Component  | filter / group / redial / layout tree    | options → controls element tree                     |
| Host bind  | plugin UI **and** Speak-to mutate        | plugin UI only                                      |

## Lib / plugin split

Infrastructure lives under `src/lib/`. Domain code lives under the `src` root (e.g. `src/main.lua`). `main.lua` only wires modules to RS
events and shutdown.

### Example file structure

Illustration only. To be refined as implementation proceeds.

```
src/
  main.lua                      -- subscribe events, PluginShutdown; bind + mount
  lib/                          -- no NPC Contact / option-key knowledge
    observable.lua              -- subscribe / notify / set-with-diff
    element.lua                 -- host-agnostic vnode helper
    prettyui_host.lua           -- PrettyUI mount/update/destroy
    bind.lua                    -- bind(host, render, subscribe?).mount(parent)
    …                           -- generic helpers
  state.lua                     -- options + last-contact on observable
  settings.lua                  -- option keys
  settings/
    SettingsPanel.lua           -- props → element tree (pure)
    view.lua                    -- render(parent, store) → Element
  contact/                      -- (future) capture / component / host
  categories.lua                -- NPC → header mapping (data)
```

**`lib/` rule:** a module belongs there only if it has no knowledge of iface
`88`, Speak-to, NPC names, or this plugin’s option keys. RS `require` paths
are relative to the plugin root after deploy (`require("lib/observable")`).

Prefer factory-style libs (`observable.new(...)`) so callers own state
objects rather than sharing mutable module singletons by accident.

Unit tests stay colocated (`*_spec.lua`); pure `lib/` and pure transforms
are where most tests should live.

## Plugin steps (contact UI)

On top of the architecture above, NPC Contact specifically does:

### 1. Capture the contact interface

There is no reliable `InterfaceOpened` event. On `Event.Logic` (and related
hooks as needed):

- detect when iface `88` is meaningfully open (geometry, visibility, not
  merely `GetInterface(88) ~= nil`);
- wait until contact slots are ready (labels/buttons with usable layout);
- parse slots into a data structure with stable identity, at least:
  - `dyn`
  - `name`
  - `hasSpeakTo`
  - handles/addresses for the Speak-to MODEL and name label

Capture includes readiness. Parsing without open/ready is not a complete
capture.

Anti-flash / early suppress of stock chrome is **out of scope for the first
production cut**; revisit later (e.g. hide stock content and present a full
substitute overlay). Correctness of Speak-to binding and options-off
identity come first.

### 2. Apply plugin options (pure component)

Combine captured contacts with plugin state into an **element tree** (layout
plan), for example:

- which contacts are visible (filters);
- grouping under category headers;
- whether chatheads are shown;
- whether a redial row/control is present and which contact it refers to;
- positions / structure for plugin chrome.

With all options off, the tree should describe the vanilla interface
(assertable from a snapshot in tests).

Category metadata (wiki-derived maps, etc.) is domain data fed into this
step, not scraped from the live UI every time.

### 3. Host bind / render

Reconcile the element tree to the live client:

- create or rebuild plugin-owned UI for the presented list (headers, labels,
  redial chrome, …);
- mutate stock Speak-to MODELs so each visible action target aligns with the
  corresponding presented control (clear visuals as needed; do not
  `hidden = true` on Speak-to if that removes the action);
- leave unused Speak-to targets in a safe non-interfering state;
- optionally hide or suppress stock chrome that the substitute UI replaces.

Re-running this after a state notify (settings change while open) is the
supported update path: rebuild element tree → host update.

### 4. Teardown

When the picker closes, options return to all-off while open, or the plugin
shuts down:

- destroy plugin-owned nodes for that surface;
- restore any stock mutations so iface `88` is not left mangled.

Options-off identity in the pure component does not replace live undo of a
previous host bind; shutdown in particular should not leave Speak-to
geometry or models dirty across `poff` / `prl`.

### 5. Settings and last-contact (beside the picker pipeline)

- Load/persist options via PersistentDB behind the domain state store.
- Bind settings once (`prettyui_host` + render/subscribe closed over the
  store); on `SettingsLayerReady` / `ContentLayerReady`, `mount` or
  `update(parent)` so hub and ribbon are separate instances of the same
  definition.
- Last-contact / redial identity is plugin state (persisted as needed),
  updated when the player selects a contact Speak-to — not synthesized as a
  new game action.

```
PersistentDB ↔ domain state store (subscribe / notify)
                      ↓
          settings views │ contact view
                      ↑
              capture (Logic / open-ready)
```

## Related reading

- [Plugin guidelines](https://developer.runescape.com/rs/submission/guidelines.html)
- [Adding a user interface](https://developer.runescape.com/rs/tutorial/2simpleui.html)
- [Plugin structure / require](https://developer.runescape.com/rs/structure.html)
- [PrettyUI](https://prettyui.j3.gg/)
