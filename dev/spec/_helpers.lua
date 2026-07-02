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

-- Minimal AceAddon shim: a global KitnEssentials whose NewModule/GetModule
-- hand back one shared table per module name, so module files that call
-- KitnEssentials:NewModule/GetModule at load resolve headlessly. Returns the
-- registry: modules["MythicPlusTimer"] is the module table after loadModule.
-- Unconditional install (no `or` guard) — deterministic regardless of what ran
-- earlier in the file (busted insulates _G per spec file, not per describe).
function M.installAddonShim()
    local modules = {}
    _G.KitnEssentials = {
        db = { global = {}, profile = {} },
        NewModule = function(_, name) modules[name] = modules[name] or {}; return modules[name] end,
        GetModule = function(_, name) modules[name] = modules[name] or {}; return modules[name] end,
    }
    return modules
end

return M
