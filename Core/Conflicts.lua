-- ╔══════════════════════════════════════════════════════════╗
-- ║  Conflicts.lua                                           ║
-- ║  Purpose: Detect rival addons that duplicate a KE        ║
-- ║           module's job, and let the user pick one.       ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)

---------------------------------------------------------------------------------
-- A rival addon doing the same job as a KE module is a user choice, not
-- something to resolve silently: a conflict raises a prompt offering both
-- owners. Prompting is state-driven -- it fires only while BOTH sides are
-- enabled -- so it self-silences after a choice and returns only if the user
-- deliberately re-enables both. Nothing is stored, so nothing goes stale.
--
-- Ported from atrocityEssentials v28.1 Core/Conflicts.lua. The deviations are
-- listed in dev/docs/superpowers/specs/2026-07-27-aes-a2-conflict-registry-design.md;
-- two are easy to "fix" back by mistake:
--   * ElvUI detection is deliberately absent. UseElvUI already hard-disables
--     every Skin* module (Core/Main.lua:170-177), so a branch for it would be
--     unreachable.
--   * skinGated entries are skipped while KE:ShouldNotLoadModule() is true.
--     The saved Enabled flag stays true when ElvUI holds the module inert, so
--     testing the flag alone would prompt about a conflict that is not
--     happening.
---------------------------------------------------------------------------------

local CONFLICTS = {
    {
        module = "SkinTooltips",
        label  = "Tooltip",
        -- KE's skinning DB is nested, so the path is data rather than the
        -- reference's flat profile[moduleName] lookup.
        dbPath = { "Skinning", "Tooltips" },
        -- Skipped wholesale when ElvUI owns skinning.
        skinGated = true,
        -- EllesmereUIBlizzardSkin restyles GameTooltip with EUI's dark style
        -- (EllesmereUIBlizzardSkin.lua:96) -- the same frames SkinTooltips
        -- restyles. The other three are tooltip replacements carried over
        -- from the reference's list.
        addons = { "TipTac", "TinyTooltip", "TacoTip", "EllesmereUIBlizzardSkin" },
    },
    -- The Chat entry lands here when A3 ships the module.
}

---------------------------------------------------------------------------------
-- Decision layer (pure)
---------------------------------------------------------------------------------

-- Walks a dbPath through a profile table. Returns nil rather than erroring
-- when a step is missing, so one malformed entry skips instead of breaking
-- the whole scan. The type guard is defensive only: every dbPath comes from
-- the CONFLICTS table above, so no test can reach it.
local function ResolveDB(profile, dbPath)
    if type(dbPath) ~= "table" then return nil end
    local node = profile
    for _, key in ipairs(dbPath) do
        if type(node) ~= "table" then return nil end
        node = node[key]
    end
    if type(node) ~= "table" then return nil end
    return node
end

-- The live environment the in-game paths run against. Returns nil before the
-- DB exists, which makes every caller a no-op during early login.
local function LiveEnv()
    if not (KE.db and KE.db.profile) then return nil end
    return {
        profile = KE.db.profile,
        -- "Loaded AND still enabled". DisableAddOn does not unload an addon,
        -- so a rival the user just turned off keeps reporting as loaded until
        -- the reload; without the enable-state half, /kes conflicts would
        -- re-raise the conflict they just resolved. Statelessness is the
        -- point: re-enabling the rival re-arms the prompt by itself.
        -- The > 0 comparison is Blizzard's own
        -- (.wow-api-reference/.../Blizzard_AddOnList/AddonList.lua:188).
        isLoaded = function(name)
            if not (C_AddOns and C_AddOns.IsAddOnLoaded) then return false end
            if not C_AddOns.IsAddOnLoaded(name) then return false end
            if C_AddOns.GetAddOnEnableState then
                return (C_AddOns.GetAddOnEnableState(name) or 0) > 0
            end
            return true
        end,
        shouldNotLoad = KE:ShouldNotLoadModule() and true or false,
    }
end

--- Builds the ordered list of conflict prompts to raise.
--- env.profile        the AceDB profile table
--- env.isLoaded       function(addonName) -> boolean
--- env.shouldNotLoad  true when ElvUI owns skinning
---@return table queue array of { module, label, dbPath, source }; never nil
function KE:BuildConflictQueue(env)
    local queue = {}
    if type(env) ~= "table" then return queue end
    if type(env.profile) ~= "table" or type(env.isLoaded) ~= "function" then
        return queue
    end

    for _, conflict in ipairs(CONFLICTS) do
        if not (conflict.skinGated and env.shouldNotLoad) then
            local moduleDB = ResolveDB(env.profile, conflict.dbPath)
            if moduleDB and moduleDB.Enabled then
                for _, addonName in ipairs(conflict.addons) do
                    if env.isLoaded(addonName) then
                        queue[#queue + 1] = {
                            module = conflict.module,
                            label  = conflict.label,
                            dbPath = conflict.dbPath,
                            source = addonName,
                        }
                    end
                end
            end
        end
    end

    return queue
end

--- Live lookup: "is this module off WHILE another addon does its job".
--- Stateless on purpose, so it self-corrects when the rival is uninstalled --
--- there is no stored "disabled by a conflict" flag to go stale. Pass env to
--- drive it headlessly; omit it in game.
---@return string|nil rival the rival addon's folder name
function KE:GetModuleConflict(moduleName, env)
    env = env or LiveEnv()
    if not env then return nil end

    for _, conflict in ipairs(CONFLICTS) do
        if conflict.module == moduleName then
            if conflict.skinGated and env.shouldNotLoad then return nil end
            local moduleDB = ResolveDB(env.profile, conflict.dbPath)
            -- `not moduleDB` matters: an unreadable DB means the module's
            -- state is UNKNOWN, not off. BuildConflictQueue's `moduleDB and
            -- moduleDB.Enabled` fails closed for the same nil, but here the
            -- polarity is inverted, so the same expression would fail OPEN and
            -- report a conflict for a module we could not read.
            if not moduleDB or moduleDB.Enabled then return nil end
            for _, addonName in ipairs(conflict.addons) do
                if env.isLoaded(addonName) then return addonName end
            end
            return nil
        end
    end

    return nil
end
