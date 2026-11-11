---
name: luals-types
description: >-
  EmmyLua / LuaLS typing rules for this repo. Use when writing or fixing
  ---@ annotations, aliases, classes, duck-typed options tables, fakes 
  fakes, or typecheck errors from ./scripts/typecheck.sh.
---

# LuaLS / EmmyLua types

## Duck typing: alias, not class

`class` doesn't work for duck typing, it _must_ be an alias because types are nominal.

Use `---@alias` for structural shapes (options bags, injected deps, DB surfaces,
plain data records). Use `---@class` for nominal constructed instances the
module owns (e.g. `StateStore`, `BoundView`, `Probe`).

```lua
-- good: duck / structural
---@alias ProbeDb { GetInt: (fun(self: any, key: string): number?), SetInt: (fun(self: any, key: string, value: number)) }

-- bad: nominal class will not accept PersistentDB or a table literal with the same fields
---@class ProbeDb
---@field GetInt fun(self: ProbeDb, key: string): number?
```

Parenthesize each `fun` inside table aliases so LuaLS does not treat `, NextField`
as another return type (see `StateDb` / `BindOptions`).

## Do not paper over type errors

- Do not use `---@diagnostic disable` (or `-next-line`) to silence assign/field errors.
- Do not widen to `any` / empty `table` / fake fallback types just to make
  typecheck pass. Fix the annotation shape (usually class → alias, or a real
  cast/narrow when the runtime type is known). If you can't figure it out, stop and ask the user for direction.

When `GetComponent` returns `ui.Component` but the call needs
`ui.ComponentCollection` methods, narrow with `---@cast` at the known site —
that is a real type refinement, not a disable.
