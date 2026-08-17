-- ╔══════════════════════════════════════════════════════════╗
-- ║  Modules/Combat/AuraEngine/Rules.lua                     ║
-- ║  Purpose: pure decision logic for the aura engine.       ║
-- ║  No WoW API, no frames -- so it is testable headlessly.  ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)

local table_concat = table.concat
local table_insert = table.insert

local Rules = {}
KE.AuraRules = Rules

-- Ordered so the emitted string does not depend on table iteration order.
-- INCLUDE_NAME_PLATE_ONLY is deliberately absent: it is handled separately
-- below because it does not follow the negation rule.
local NEGATABLE_FILTERS = {
    "PLAYER",
    "RAID",
    "CROWD_CONTROL",
    "IMPORTANT",
    "RAID_PLAYER_DISPELLABLE",
}

-- Each enabled checkbox means "remove auras matching this", so an enabled
-- filter becomes a NEGATED token.
--
-- INCLUDE_NAME_PLATE_ONLY inverts, and cannot be negated at all: the game
-- documents negation on it as ignored, and IsValidFilterString accepts the
-- negated form without complaint. Its absence already excludes nameplate-only
-- auras, so "hide them" is the token's absence and "show them" is its
-- positive presence. Getting this backwards fails silently.
function Rules.BuildDebuffFilter(filters)
    filters = filters or {}

    local parts = { "HARMFUL" }

    for i = 1, #NEGATABLE_FILTERS do
        local key = NEGATABLE_FILTERS[i]
        if filters[key] then
            table_insert(parts, "!" .. key)
        end
    end

    if not filters.INCLUDE_NAME_PLATE_ONLY then
        table_insert(parts, "INCLUDE_NAME_PLATE_ONLY")
    end

    return table_concat(parts, "|")
end
