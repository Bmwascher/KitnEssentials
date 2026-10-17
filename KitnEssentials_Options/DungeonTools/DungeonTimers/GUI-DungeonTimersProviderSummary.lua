-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-DungeonTimersProviderSummary.lua                    ║
-- ║  Pure BigWigs Messages summary for the "DTimers_Main"    ║
-- ║  header card: status keys, per-state counts and Check    ║
-- ║  now eligibility. No frames or WoW API, so specs load it.║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = KitnEssentials:GetNamespace()

local ipairs = ipairs

KE.GUI = KE.GUI or {}
KE.GUI.DungeonTimers = KE.GUI.DungeonTimers or {}
local DT_GUI = KE.GUI.DungeonTimers

-- A read that failed without naming why is shown as unreadable.
function DT_GUI.ProviderSetupKey(status, reason)
    if status == "unknown" then return reason or "unreadable" end
    return status
end

-- Check now can only help a provider module that is not loaded or not readable.
function DT_GUI.ProviderCheckEligible(key)
    return key == "not-loaded" or key == "unreadable"
end

local COUNT_FIELD = {
    satisfied = "on",
    missing = "off",
    ["not-loaded"] = "notLoaded",
    unreadable = "unreadable",
}

-- Disabled and inapplicable alerts count nowhere.
function DT_GUI.SummarizeProviderSetup(states)
    local summary = { kind = "none", total = 0, on = 0, off = 0, notLoaded = 0, unreadable = 0, canCheck = false }
    local noProvider = false
    for _, entry in ipairs(states) do
        if entry.status ~= "disabled" and entry.status ~= "not-applicable" then
            local key = DT_GUI.ProviderSetupKey(entry.status, entry.reason)
            summary.total = summary.total + 1
            local field = COUNT_FIELD[key]
            if field then summary[field] = summary[field] + 1 end
            if key == "no-provider" then noProvider = true end
            if DT_GUI.ProviderCheckEligible(key) then summary.canCheck = true end
        end
    end
    if summary.total == 0 then
        summary.kind = "none"
    elseif noProvider then
        summary.kind = "no-provider"
    elseif summary.on == summary.total then
        summary.kind = "all-on"
    else
        summary.kind = "mixed"
    end
    return summary
end
