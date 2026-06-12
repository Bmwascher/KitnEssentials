-- ╔══════════════════════════════════════════════════════════╗
-- ║  dev/spec/_helpers.lua                                   ║
-- ║  Shared helpers for loading KE source files headlessly.  ║
-- ╚══════════════════════════════════════════════════════════╝

local M = {}

-- WoW loads each addon Lua file as a chunk whose vararg is
-- (addonName, privateNamespace). We replicate that exactly so a file's
-- top-level `local KE = select(2, ...)` resolves to our table.
--
--   local KE = helpers.loadModule("Core/Interrupts.lua")
--   -- KE now has the functions/tables that file defined on it.
--
-- Pass an existing KE table to accumulate across several files, or a seed
-- (e.g. { Print = function() end }) for files that call KE:Print at load.
function M.loadModule(relpath, KE, addonName)
    KE = KE or {}
    addonName = addonName or "KitnEssentials"
    local chunk, err = loadfile(relpath)
    if not chunk then error("loadfile failed for " .. relpath .. ": " .. tostring(err), 2) end
    chunk(addonName, KE)
    return KE
end

return M
