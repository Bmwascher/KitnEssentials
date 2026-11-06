-- ╔══════════════════════════════════════════════════════════╗
-- ║  Modules/Skinning/RestedXP/RestedXPSafe.lua              ║
-- ║  Purpose: Guarded calls into RestedXP. A failing site    ║
-- ║           reports once, and a missing call turns off     ║
-- ║           one part.                                      ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)

local pcall, select, type = pcall, select, type

local Safe = {}
KE.RestedXPSafe = Safe

local reported, partsOff = {}, {}

local function Report(site, message)
    if reported[site] then return end
    reported[site] = true
    pcall(geterrorhandler(), message)
end

function Safe.Has(object, method)
    return type(object) == "table" and type(object[method]) == "function"
end

function Safe.Dig(t, ...)
    for i = 1, select("#", ...) do
        if type(t) ~= "table" then return nil end
        t = t[select(i, ...)]
    end
    return t
end

local function Finish(site, ok, ...)
    if ok then return ... end
    Report(site, (...))
end

function Safe.Run(site, fn, ...)
    return Finish(site, pcall(fn, ...))
end

function Safe.Missing(part, site)
    partsOff[part] = true
    Report(site, "KitnEssentials: RestedXP has no " .. site .. ", so " .. part .. " stays off.")
end

function Safe.PartOn(part)
    return not partsOff[part]
end

-- One chat line for a refusal that changed nothing. Nothing failed, so it skips the
-- error handler and shares only the once-per-site limit.
function Safe.Notice(site, message)
    if reported[site] then return end
    reported[site] = true
    KE:Print(message)
end

function Safe.Secret(value)
    return issecretvalue(value)
end
