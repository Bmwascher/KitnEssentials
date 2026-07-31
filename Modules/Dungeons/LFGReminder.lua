-- ╔══════════════════════════════════════════════════════════╗
-- ║  LFGReminder.lua                                         ║
-- ║  Module: LFG Reminder                                    ║
-- ║  Purpose: When you join a Group Finder group for a       ║
-- ║           dungeon with a known teleport, show a small    ║
-- ║           popup with the dungeon name and a one-click    ║
-- ║           teleport button. Hides on entering the         ║
-- ║           dungeon, leaving the group, or entering        ║
-- ║           combat.                                        ║
-- ║                                                          ║
-- ║  Taint / secret-value safety -- critical, read before    ║
-- ║  editing:                                                ║
-- ║    * The teleport spellID fed to SetAttribute("spell")   ║
-- ║      is ALWAYS a static integer from our own name->spell ║
-- ║      table, never an LFG field.                          ║
-- ║    * The dungeon resolves on LFG_LIST_JOINED_GROUP,      ║
-- ║      where the search result is readable (browse/apply-  ║
-- ║      phase secrecy is lifted once joined). Every field   ║
-- ║      is still issecretvalue-guarded and the whole lookup ║
-- ║      pcall'd: a secret can only skip the prompt, never   ║
-- ║      error. The dungeon name is only ever SetText'd,     ║
-- ║      which accepts secrets.                              ║
-- ║    * The secure button is created ONCE and ALWAYS out of ║
-- ║      combat: normally at enable, else on the next        ║
-- ║      PLAYER_REGEN_ENABLED. NOTHING may call BuildPopup   ║
-- ║      during combat -- it writes SetAttribute("type",     ║
-- ║      "spell") on a protected frame. Only the "spell"     ║
-- ║      attribute is rewritten later, also only out of      ║
-- ║      combat (deferred when a join lands mid-combat).     ║
-- ║    * No Blizzard Group Finder frame is ever hooked or    ║
-- ║      SetScript-ed.                                       ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class LFGReminder: AceModule, AceEvent-3.0
local LR = KitnEssentials:NewModule("LFGReminder", "AceEvent-3.0")

local type = type
local pcall = pcall
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local IsPlayerSpell = IsPlayerSpell
local IsInGroup = IsInGroup
local IsInInstance = IsInInstance
local UIParent = UIParent
local C_Spell = C_Spell
-- Indexed off _G, unlike its neighbours: C_LFGList is the one API this file
-- touches that is NOT in .luacheckrc's allowlist, so a bare capture is a
-- W113 (accessing undefined global) and every task gates on zero warnings.
-- Modules/Skinning/Frames/LFG.lua:122 already reaches this same API this way.
-- Do NOT widen .luacheckrc instead.
local C_LFGList = _G.C_LFGList
local GameTooltip = GameTooltip
local issecretvalue = issecretvalue or function() return false end

-- Dungeon display name (lowercase, difficulty suffix stripped) ->
-- teleport spellID. Season-volatile data matched by name against
-- GetActivityInfoTable's fullName.
--
-- English keys only. The reference also carries ten Cyrillic keys, which
-- were dropped deliberately: they cannot ever match. The lookup lowercases
-- with Lua's string.lower, which is byte-wise and ASCII-only, so a
-- capitalised Cyrillic name ("Небесный путь") never folds to the lowercase
-- key ("небесный путь") -- measured 2026-07-31 in this project's Lua 5.1.
-- They are dead entries upstream too, and KE ships no localisation, so
-- carrying them would imply support that does not exist. Adding real
-- Russian support means Cyrillic-aware case folding, not these keys.
local TELEPORT_BY_NAME = {
    ["magisters' terrace"]         = 1254572,
    ["maisara caverns"]            = 1254559,
    ["nexus-point xenas"]          = 1254563,
    ["windrunner spire"]           = 1254400,
    ["algeth'ar academy"]          = 393273,
    ["pit of saron"]               = 1254555,
    ["seat of the triumvirate"]    = 1254551,
    ["skyreach"]                   = 159898,
}

local function ResolveTeleportSpellByName(displayName)
    if type(displayName) ~= "string" then return nil end
    local n = displayName:lower():gsub("%s*%b()%s*$", "")
    return TELEPORT_BY_NAME[n]
end

-- Test seam. The lookup is a pure file-local with no other handle, and no
-- function references it until the resolve chain lands, so debug.getupvalue
-- has nothing to reach it through.
LR._ResolveTeleportSpellByName = ResolveTeleportSpellByName

-- Layout constants
local POPUP_W     = 210
local TITLE_H     = 27
local PAD         = 10
local NAME_TOP    = TITLE_H + 9
local NAME_H      = 24
local BTN_TOP     = NAME_TOP + NAME_H
local BTN_H       = 56
local DISABLE_TOP = BTN_TOP + BTN_H + 8
local DISABLE_H   = 16
local POPUP_H     = DISABLE_TOP + DISABLE_H + 10

-- State (plain upvalues; never keyed by a possibly-secret resultID)
local popup, secureBtn
local pendingSpellID       -- resolved teleport spell (static integer)
local pendingName          -- dungeon display name (clean)
local pendingAttrSpellID   -- spell attr stashed for out-of-combat write
local pendingShow          -- join landed in combat; show on REGEN_ENABLED
local pendingHide          -- hide requested in combat; flush on REGEN_ENABLED

local BuildPopup, ShowPrompt, HidePrompt, ClearPending
local UpdateButtonVisuals, ResolveDungeon
local SavePosition, ApplySavedPosition, ApplyDisableVisibility

function LR:UpdateDB()
    if KE.db and KE.db.profile then
        self.db = KE.db.profile.LFGReminder
    end
end
