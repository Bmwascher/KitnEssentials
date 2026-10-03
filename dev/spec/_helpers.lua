-- ╔══════════════════════════════════════════════════════════╗
-- ║  dev/spec/_helpers.lua                                   ║
-- ║  Shared helpers for loading KE source files headlessly.  ║
-- ╚══════════════════════════════════════════════════════════╝

local M = {}

-- Settings pages ship as their own addon, so a page reads the addon table
-- through KitnEssentials:GetNamespace() rather than its vararg.
local PAGES_ROOT = "KitnEssentials_Options/"

-- WoW loads each addon Lua file as a chunk whose vararg is
-- (addonName, privateNamespace). We replicate that exactly so a file's
-- top-level `local KE = select(2, ...)` resolves to our table.
--
--   local KE = helpers.loadModule("Core/Interrupts.lua")
--   -- KE now has the functions/tables that file defined on it.
--
-- Pass an existing KE table to accumulate across several files, or a seed
-- (e.g. { Print = function() end }) for files that call KE:Print at load.
--
-- A page path also gets GetNamespace answered with KE. With no
-- KitnEssentials global the page borrows one for its load only; its
-- GetModule finds nothing, which is what a page's file-scope
-- `KitnEssentials and KitnEssentials:GetModule(...)` saw with no global.
function M.loadModule(relpath, KE, addonName)
    KE = KE or {}
    addonName = addonName or "KitnEssentials"
    local chunk, err = loadfile(relpath)
    if not chunk then error("loadfile failed for " .. relpath .. ": " .. tostring(err), 2) end
    if relpath:sub(1, #PAGES_ROOT) ~= PAGES_ROOT then
        chunk(addonName, KE)
        return KE
    end
    local function getNamespace() return KE end
    if _G.KitnEssentials then
        _G.KitnEssentials.GetNamespace = getNamespace
        chunk(addonName, KE)
        return KE
    end
    _G.KitnEssentials = { GetNamespace = getNamespace, GetModule = function() return nil end }
    local ok, runErr = pcall(chunk, addonName, KE)
    _G.KitnEssentials = nil
    if not ok then error(runErr, 0) end
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
