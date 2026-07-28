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
        -- Rivals that expose a switch for JUST the conflicting feature. Turning
        -- the whole addon off would be disproportionate here: EUI's Blizz UI
        -- Enhanced also skins the character sheet, inspect sheet, great vault,
        -- group finder, socket panel, dragon riding and diminishing returns, and
        -- a user who picked KE for TOOLTIPS did not ask to lose any of that.
        -- Rivals with no resolver (TipTac, TinyTooltip, TacoTip) still get the
        -- whole-addon disable, which is right -- they are tooltip addons and
        -- nothing else.
        resolvers = {
            EllesmereUIBlizzardSkin = {
                label = "EllesmereUI's tooltip reskin",
                -- EllesmereUIDB is the base EllesmereUI addon's saved variable
                -- (EllesmereUI.toc:6); customTooltips is the "Reskin Tooltip"
                -- toggle, and EUI's own source says it governs ONLY the game
                -- tooltip (EllesmereUIBlizzardSkin.lua:113-114).
                apply = function()
                    if type(_G.EllesmereUIDB) ~= "table" then return false end
                    _G.EllesmereUIDB.customTooltips = false
                    return true
                end,
                -- Stateless companion to apply(). Flipping the switch leaves the
                -- addon loaded AND enabled, so the enable-state half of
                -- deviation 8 cannot see the resolution -- without this the next
                -- scan would re-raise a conflict the user just settled. Mirrors
                -- EUI's own test: absent means ON, only a literal false is off.
                isActive = function()
                    return type(_G.EllesmereUIDB) ~= "table"
                        or _G.EllesmereUIDB.customTooltips ~= false
                end,
            },
        },
    },
    {
        module = "Chat",
        label  = "Chat",
        dbPath = { "Skinning", "Chat" },
        skinGated = true,
        addons = { "Prat-3.0", "Chatter", "Glass", "ls_Glass",
                   "BasicChatMods", "EllesmereUIChat" },
    },
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
        -- The optional second argument is the rival's resolver. A resolver
        -- flips the rival's OWN switch rather than disabling it, which leaves
        -- the addon loaded and enabled, so the two checks above cannot see that
        -- the conflict is settled. Asking the resolver is what keeps the
        -- subsystem stateless on that path too. The global read lives HERE, in
        -- the presentation layer, so the decision layer stays pure.
        isLoaded = function(name, resolver)
            if not (C_AddOns and C_AddOns.IsAddOnLoaded) then return false end
            if not C_AddOns.IsAddOnLoaded(name) then return false end
            if C_AddOns.GetAddOnEnableState
                and (C_AddOns.GetAddOnEnableState(name) or 0) <= 0 then
                return false
            end
            if resolver and resolver.isActive then return resolver.isActive() end
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
                    local resolver = conflict.resolvers and conflict.resolvers[addonName]
                    if env.isLoaded(addonName, resolver) then
                        queue[#queue + 1] = {
                            module   = conflict.module,
                            label    = conflict.label,
                            dbPath   = conflict.dbPath,
                            source   = addonName,
                            resolver = resolver,
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
                local resolver = conflict.resolvers and conflict.resolvers[addonName]
                if env.isLoaded(addonName, resolver) then return addonName end
            end
            return nil
        end
    end

    return nil
end

---------------------------------------------------------------------------------
-- Prompt queue
---------------------------------------------------------------------------------

-- Folder names read badly in a prompt; show what the user calls them.
local ADDON_LABELS = {
    ["EllesmereUIBlizzardSkin"] = "EllesmereUI BlizzUI Enhanced",
    ["EllesmereUIChat"] = "EllesmereUI Chat",
    ["Prat-3.0"] = "Prat",
    ["BasicChatMods"] = "Basic Chat Mods",
}

local promptQueue = {}
local promptActive = false
-- ONE reload prompt after every conflict is answered, never one per choice.
-- KE:CreatePrompt is a singleton that hides the active dialog
-- (Core/Widgets.lua:271-273), so a per-choice reload prompt would be replaced
-- by the next conflict prompt before it could be clicked. The reference
-- declares this flag but never sets it (v28.1 Core/Conflicts.lua:56), so its
-- own single-reload comment describes behaviour its code does not have.
local pendingReload = false

-- Recursive: the accept and cancel closures call it to advance the queue.
-- `local function` puts the name in scope inside its own body, so no forward
-- declaration is needed.
local function ShowNextPrompt()
    local item = table.remove(promptQueue, 1)
    if not item then
        promptActive = false
        if pendingReload then
            pendingReload = false
            KE:CreateReloadPrompt("Addon conflicts resolved - reload to apply.")
        end
        return
    end
    promptActive = true

    local friendly = ADDON_LABELS[item.source] or item.source

    KE:CreatePrompt(
        item.label .. " Conflict",
        friendly .. " and the KitnEssentials " .. item.label ..
            " module are both enabled - running both will cause visual and" ..
            " functional conflicts.\n\nWhich would you like to use?",
        false, nil, false, nil, nil, nil, nil,
        function()
            -- Prefer the rival's own switch where it has one, so choosing KE
            -- over a tooltip clash does not also take out the eight unrelated
            -- features that ship in the same addon. Falling back to the
            -- whole-addon disable when apply() cannot run still resolves the
            -- conflict, which is the outcome the user asked for.
            local resolver = item.resolver
            if resolver and resolver.apply and resolver.apply() then
                KE:Print(resolver.label .. " disabled - reload to apply.")
            else
                if C_AddOns and C_AddOns.DisableAddOn then
                    C_AddOns.DisableAddOn(item.source)
                end
                KE:Print(friendly .. " disabled - reload to apply.")
            end
            pendingReload = true
            ShowNextPrompt()
        end,
        -- Escape and the close button reach THIS callback too
        -- (Core/Widgets.lua:194-196, :238) -- an accepted risk, recorded in the
        -- Global Constraints. The chat line is the mitigation: an accidental
        -- dismissal announces what it did instead of changing state silently.
        function()
            local moduleDB = ResolveDB(KE.db and KE.db.profile, item.dbPath)
            if moduleDB then moduleDB.Enabled = false end
            pendingReload = true
            KE:Print("KitnEssentials " .. item.label .. " module disabled - reload to apply.")
            ShowNextPrompt()
        end,
        -- Green marks the recommended choice at a glance; the label is a
        -- FontString so the escape renders. Both buttons read "Use X" because
        -- the choice is symmetric -- "Keep" implied the other option was the
        -- destructive one.
        "|cff00ff00Use KitnEssentials|r",
        "Use " .. friendly
    )
end

---------------------------------------------------------------------------------
-- Scanner
---------------------------------------------------------------------------------

--- Rescans and raises any outstanding conflict prompts. Public so
--- `/kes conflicts` can retest a fix without a relog.
function KE:ScanAddonConflicts()
    -- Stall recovery: our callbacks are the only thing that clears
    -- promptActive, and an unrelated KE:CreatePrompt replaces the singleton
    -- and drops them (Core/Widgets.lua:271-273). If no prompt is on screen at
    -- all, ours died unanswered -- reclaim rather than stall forever.
    if promptActive and not KE.activePrompt then
        promptActive = false
        -- Drop the stranded tail too. Whatever survived belongs to a session
        -- whose callbacks are gone, and the rebuild below re-derives every
        -- conflict that is still live -- keeping it would queue each survivor
        -- twice.
        wipe(promptQueue)
    end

    -- A rescan while a prompt is open would append a second copy of a queue
    -- the open session already covers.
    if promptActive then return end

    local env = LiveEnv()
    if not env then return end

    local queue = self:BuildConflictQueue(env)
    for _, item in ipairs(queue) do
        promptQueue[#promptQueue + 1] = item
    end

    if #promptQueue > 0 then
        ShowNextPrompt()
    end
end

local scanner = CreateFrame("Frame")
scanner:RegisterEvent("PLAYER_ENTERING_WORLD")
scanner:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    -- Delayed so the login rush settles first. The reference tuned 5s down to
    -- 2s: longer read as a hang.
    C_Timer.After(2, function()
        -- RunAfterCombat defers to PLAYER_REGEN_ENABLED when in combat, so a
        -- mid-pull login never gets a prompt over the fight.
        KE:RunAfterCombat(function()
            KE:ScanAddonConflicts()
        end)
    end)
end)
