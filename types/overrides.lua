---@meta
---Local LuaLS fixes on top of the `types/rs` submodule
---(FriendlyDevelopment/runescape-api-stubs).

-- Methods in generated/ui/component_collection.lua are declared on a bare
-- `ComponentCollection` table while the class is `ui.ComponentCollection`.
-- Mirror the existing `Component` alias so those methods resolve.
---@alias ComponentCollection ui.ComponentCollection
