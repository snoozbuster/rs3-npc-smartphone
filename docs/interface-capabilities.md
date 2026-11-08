# Interface modification capabilities

Notes from reshaping the NPC Contact picker (`iface=88`) in `npc-smartphone` on
the RS3 plugin beta client. This is practical experience with the documented UI
API, not a substitute for the official docs.

See also: [npc-contact-interface.md](./npc-contact-interface.md).

## What plugins can do

### Read the live tree

| API | Use |
|-----|-----|
| `ui.Interfaces:GetInterface(id)` | Is an interface currently loaded? |
| `ui.Interfaces:GetComponent(iface, static [, cat, dyn])` | Fetch a static or dynamic component |
| `component.x / y / width / height` | Resolved layout (read-only) |
| `component.scrollable`, `scrollWidth`, `scrollHeight`, `scrollX`, `scrollY` | Scroll region state |
| `component.content` (labels) | Display text |
| `component.opConfig.opNames` | Interface ops (e.g. Speak-to, Close) |
| `component.parent` / `parentStatic` / `interfaceID` | Walk ancestry; stay inside the target iface |
| `ComponentCollection:IterateDynamicComponents(cb)` | Enumerate dynamic children |

`GetInterface(id) ~= nil` only means the interface object exists. It can linger
with `0×0` geometry or before dynamic children spawn. Prefer also checking
`width`/`height`, `visibleGlobal`, and at least one expected child.

### Mutate built-in components

These work on stock (game-authored) components inside a loaded interface:

| API | Effect |
|-----|--------|
| `component.hidden = true` | Lua-side hide. Guidelines forbid *unhiding* game-hidden components. |
| `component:SetPos(x, y, …)` | Move origin (optional parent/self percentages) |
| `component:SetSize(w, h, …)` | Resize (optional parent percentages) |
| `component:SetScrollSize(w, h)` | Resize scroll content region |
| `component:SetScrollPos(x, y)` | Jump scroll origin |
| `ui.Model:SetModel(…)` | Change/clear a model (not needed for simple hide) |

Resizing real component bounds also changes hit-testing: leftover empty space
from a taller layout stops intercepting clicks once the layers are shortened.

### Create plugin UI

Plugins cannot create new interfaces. Attach new components under an existing
parent, typically:

`ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP)`

That path is for overlays / replacements, not for editing stock chrome. Mixing
both is fine: reshape the stock picker *and* draw a plugin panel above it.

## What does not work (or is easy to misuse)

| Assumption | Reality |
|------------|---------|
| Layer `.scrollbar` like InputField/Combo | Contact picker layers report `scrollable=true` but `scrollbar` is absent/`nil`. The bar is separate sprite chrome (see iface `88` static `3`). |
| One-tick defer after open | Dynamic slots often need several Logic ticks. Apply too early → no-op; apply too late → flash of stock UI. |
| Hide models ⇒ layout collapses | Label cells stay chathead-tall until you `SetPos`/`SetSize` them. |
| Walk `parent` until `nil` and resize | Parents eventually leave the picker into the game viewport (~1440× wide). Resizing those changes the whole client window. Gate on `interfaceID` and a max width. |
| Heuristic “thin sprite on the right” | Can match the scrollbar *or* the right frame border. Prefer known static IDs from a scaffold dump. |
| Parent `SetSize` then child `SetSize` with the same delta | Children may already have been auto-resized by the parent. Snapshot heights first, then apply once. |

## Guidelines that affect UI work

From the [plugin guidelines](https://developer.runescape.com/rs/submission/guidelines.html):

**Allowed / expected**
- Filtering, sorting, interface customisation
- Hiding or rearranging for clarity / accessibility
- Overlays that reorganise visible, public information

**Not allowed (relevant bits)**
- Unhiding components the game has hidden
- Auto-performing actions / synthesizing server ops
- New MiniMenu entries that send server actions
- Moving/resizing **3D component click zones** to invent unfair hit targets

For NPC Contact that means: hiding chathead MODELs and packing LABELs for
display is fine; do not relocate MODEL Speak-to hitboxes as a fake list
control. Prefer a plugin overlay for new clickable UI, and keep Speak-to as the
player’s real action on the stock targets (or a clearly allowed alternative).

## Patterns that worked

### Anti-flash

1. Detect the shell as soon as viewport geometry is non-zero.
2. Immediately `hidden = true` on the chathead layer (`static=1`) and scrollbar
   gutter (`static=3`), every Logic tick until the full reshape runs.
3. Wait until contact labels exist with real `width`/`height`, then pack/fit.

### Pack a grid without chatheads

1. Read each label’s `x`/`y`/`width`/`height`.
2. Keep first-row X positions as column anchors.
3. Use a text-sized row pitch (label cells were ~95px tall / ~125px pitch with
   chatheads; ~22px worked for names-only).
4. `SetSize` each label to the new row height, then `SetPos` into the dense grid.
5. Leave MODEL components hidden; do not move their click zones.

### Fit the window to content

1. Shorten content hosts (`static=1` / `2`) to `contentBottom + pad`.
2. Clamp viewport scroll (`static=0`) so `scrollHeight` does not exceed the view
   when content fits (reduces need for a bar).
3. Snapshot frame layer sizes, then subtract one shared delta
   (`oldViewportH - contentBottom`) from outer/chrome layers only inside
   iface `88` and below a safe max width (~600).
4. Re-`SetScrollPos(0, 0)` after fitting so the list is not mid-scrolled into a
   short viewport.
5. Keep re-hiding the scrollbar gutter while open — wheel input can resurrect it.

## Debugging checklist

- Log `static`, `type`, `width×height`, `x,y`, `scrollable`, `scrollWxH` for
  statics `0..9` on open.
- `IterateDynamicComponents` on chrome statics (not the huge contact streams)
  to find scrollbar / border sprites.
- Confirm `interfaceID` on every node before `SetSize`.
- If layout “almost” works but clips: check for double-shrink and bottom pad,
  not only row pitch.

## Official references

- [Interface](https://developer.runescape.com/rs/ui/interface.html)
- [Component](https://developer.runescape.com/rs/ui/component.html)
- [Component collection](https://developer.runescape.com/rs/ui/component_collection.html)
- [Model](https://developer.runescape.com/rs/ui/decorative_components/model.html)
- [Adding a user interface](https://developer.runescape.com/rs/tutorial/2simpleui.html)
- [Plugin guidelines](https://developer.runescape.com/rs/submission/guidelines.html)
