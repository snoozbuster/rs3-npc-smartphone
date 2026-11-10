# NPC Smartphone

RS3 plugin that improves the **NPC Contact** spell picker (search / favorites /
clearer UX). Development targets the official RuneScape plugin beta client
(Lua 5.4.8 API).

Docs:

- [`docs/npc-contact-interface.md`](docs/npc-contact-interface.md) — iface `88` / spellbook schema
- [`docs/interface-capabilities.md`](docs/interface-capabilities.md) — what we can mutate in stock UI

## Requirements

- RuneScape **plugin beta** client (Jagex Launcher → beta link from the [getting started](https://developer.runescape.com/rs/getting-started.html) docs)
- This repo checked out under WSL (or anywhere you can write to the beta `dev_plugins` folder)
- `rsync` (and optionally `inotify-tools` for watch mode)

## Deploy (WSL → Windows beta client)

Default destination:

`/mnt/c/ProgramData/Jagex/RuneScape-BETA/dev_plugins/npc-smartphone`

```bash
./scripts/deploy.sh          # one-shot copy
./scripts/deploy.sh --watch  # re-copy on save (needs: sudo apt install inotify-tools)
```

Override the parent folder if needed:

```bash
RS3_DEV_PLUGINS=/mnt/c/path/to/RuneScape-BETA/dev_plugins ./scripts/deploy.sh
```

`scripts/deploy.sh` rsyncs `src/` (excluding `*_spec.lua`) plus root `plugin.json` into that folder.

Confirm the beta cache root while the client is loading (cog icon on the load
window). You want the folder that contains `*.jcache` files; `dev_plugins`
should sit next to that.

## Load / reload in the client

1. Log into the **beta** world (import save from the lobby if needed).

- [Open beta](jagex:launch=runescape,args=[configURI=rs-launch://www.runescape.com/jav_config_beta.ws])

2. Open the client console: **Alt + `** (key under Esc).
3. Refresh the plugin list if you just created the folder:

   ```
   prf
   plist
   ```

   You should see `npc-smartphone`.

4. Enable it:

   ```
   pon npc-smartphone
   ```

5. After editing Lua and re-deploying, reload without toggling off:

   ```
   prl npc-smartphone
   ```

Other useful commands:

| Command               | Effect                                        |
| --------------------- | --------------------------------------------- |
| `poff npc-smartphone` | Disable                                       |
| `plist`               | List discovered plugins (`[ENABLED]` when on) |

Console output from the plugin is prefixed with `[npc-smartphone]`.

## Unit tests

First-time setup (project-local Lua 5.4.8 + busted via micromamba):

```bash
./scripts/setup-busted.sh
```

Run tests:

```bash
./scripts/test.sh
```

Specs live next to sources as `src/*_spec.lua` (excluded from deploy).

## Quick smoke test

1. `./scripts/deploy.sh` then `prl npc-smartphone` (or `pon` the first time).
2. Switch to the Lunar spellbook and cast **NPC Contact**.
3. Console should log `contact iface 88 OPEN` and a `contacts (29):` dump.
4. **F9** re-prints the contact list while the picker is open.

## References

- [Getting started](https://developer.runescape.com/rs/getting-started.html)
- [Plugin structure](https://developer.runescape.com/rs/structure.html)
- [Hello world / console](https://developer.runescape.com/rs/tutorial/1helloworld.html)
- [Plugin guidelines](https://developer.runescape.com/rs/submission/guidelines.html)
