# Agent notes

## Docs

| Doc                                                              | What it covers                                      |
| ---------------------------------------------------------------- | --------------------------------------------------- |
| [README.md](README.md)                                           | Setup, deploy, load/reload, test/lint, editor types |
| [docs/architecture.md](docs/architecture.md)                     | Maintainability, UI pipeline, lib/plugin split      |
| [docs/features.md](docs/features.md)                             | Product features / roadmap                          |
| [docs/npc-contact-interface.md](docs/npc-contact-interface.md)   | iface `88` / spellbook schema                       |
| [docs/interface-capabilities.md](docs/interface-capabilities.md) | What plugins can read/mutate in stock UI            |
| [types/rs/README.md](types/rs/README.md)                         | Official RS plugin API stubs (submodule)            |
| [PrettyUI docs](https://prettyui.j3.gg/)                         | PrettyUI dependency                                 |

## Testing

- New or changed functions get unit tests (`src/*_spec.lua`).
- After every change, run `./scripts/test.sh` and `./scripts/lint.sh` (setup: [README](README.md#testing)).
- `./scripts/test.sh` is **unit tests + LuaLS typecheck**; both must pass.
- Keep EmmyLua annotations accurate on code we write (`---@param` / `@return` / `@class`); prefer narrow duck types over bare `table`. See [architecture](docs/architecture.md#north-star-maintainability).
