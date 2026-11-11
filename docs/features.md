# Features / roadmap

Product goals for `npc-smartphone`. Architecture that implements them:
[architecture.md](./architecture.md).

**Default:** with every option off, the plugin leaves (or restores) the
original NPC Contact picker behaviour.

## Features

### Hide chatheads

Collapse or replace the stock chathead grid with a clearer presentation
(names-only / compact layout as designed). Stock Speak-to MODELs remain the
click targets; visuals may be cleared and hitboxes aligned to the presented
rows.

- **Option:** e.g. `hide chatheads`
- **Status:** Lifted into `contact/picker.lua` (prototype compact pipeline:
  collapse → align Speak-to → clamp scroll → fit window → hide scrollbar).
  Capture / plan / push decomposition still deferred.

### Group contacts under purpose headers

Present contacts in sections such as **Slayer**, **Quests**, **Skilling**,
**Misc** (exact set TBD). Categories should be derived from the allowed NPC
Contact list (wiki / research), not invented per session from UI order
alone.

- **Option:** e.g. `group contacts`
- **Status:** Not started. Needs a stable category map keyed by contact
  identity (name and/or other stable fields from capture).

### Filter contacts

Control which contacts appear in the presented list. Candidates:

- exclude NPCs that cannot currently be called (`hasSpeakTo == false`);
- exclude NPCs from certain categories;
- individually choose which NPCs are shown.

Filters compose with grouping and with hide-chatheads.

- **Options:** dedicated filter settings (category toggles, “callable only”,
  per-NPC visibility, etc. — exact UX TBD)
- **Status:** Not started. Capture already exposes `hasSpeakTo` in the
  prototype parse path.

### Redial

Show a control (top of the list or elsewhere in the interface) for the last
NPC the player contacted. Activating it still requires clicking that
contact’s stock Speak-to MODEL (aligned under the redial chrome).

- **Option:** e.g. `show redial`
- **State:** last-contact identity in the domain store / PersistentDB
- **Status:** Not started. Game already exposes a spellbook MiniMenu
  “Redial” entry; in-picker redial is a separate presented control over the
  matching Speak-to.

## Options surface

Each feature above is gated by plugin options exposed in:

- Plugin Hub settings (`SettingsLayerReady` + PrettyUI)
- In-game Plugins ribbon (`ContentLayerReady` + PrettyUI)

Both surfaces read/write the same state store so they stay in sync.

## Non-goals (constraints)

- No synthesized Speak-to / server actions.
- No rebinding Speak-to onto plugin-created buttons or labels.
- No unhiding components the game has hidden
