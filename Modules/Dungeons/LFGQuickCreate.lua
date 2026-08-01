-- ╔══════════════════════════════════════════════════════════╗
-- ║  LFGQuickCreate.lua                                      ║
-- ║  Module: LFG Quick Create                                ║
-- ║  Purpose: A row of season-dungeon icon buttons on the    ║
-- ║           Group Finder's Entry Creation form. One click  ║
-- ║           lists a group for that dungeon. The dungeon    ║
-- ║           matching your own keystone glows gold with     ║
-- ║           its level; a party member's key glows blue.    ║
-- ║                                                          ║
-- ║  Taint safety -- critical, read before editing:          ║
-- ║    * C_LFGList.CreateListing() MUST be called directly   ║
-- ║      from the hardware click. It is HasRestrictions in   ║
-- ║      12.0.7; routing it through                          ║
-- ║      LFGListEntryCreation_ListGroup() taints and causes  ║
-- ║      ADDON_ACTION_BLOCKED.                               ║
-- ║    * NEVER write ec.generalPlaystyle from addon code.    ║
-- ║      SetEntryTitle is protected and not hardware-event-  ║
-- ║      exempt, and writing the field TAINTS THE FIELD      ║
-- ║      ITSELF -- Blizzard's own later reads then pass a    ║
-- ║      tainted value into SetEntryTitle and get blocked,   ║
-- ║      on Blizzard's path, where no shim can help. The     ║
-- ║      Default Playstyle setting reaches only the          ║
-- ║      CreateListing payload, which is clean.              ║
-- ║    * The double-click feature is a SECURE CLICK RELAY,   ║
-- ║      not an insecure Click(). A SecureActionButton       ║
-- ║      overlay is armed over the tile for 0.35s and the    ║
-- ║      second physical click drives Blizzard's own Start   ║
-- ║      button, so the whole flow stays secure. Its         ║
-- ║      RegisterForClicks MUST include the DOWN edge --     ║
-- ║      modern secure buttons ignore up-only registration.  ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class LFGQuickCreate: AceModule, AceEvent-3.0
local QC = KitnEssentials:NewModule("LFGQuickCreate", "AceEvent-3.0")

local _G = _G
local ipairs = ipairs
local pcall = pcall
local type = type
local pairs = pairs
local math_max = math.max
local CreateFrame = CreateFrame
local C_Timer = C_Timer
-- Indexed off _G, unlike its neighbours: C_LFGList is the one API this file
-- touches that is NOT in .luacheckrc's allowlist, so a bare capture is a
-- W113 (accessing undefined global) and every task gates on zero warnings.
-- Modules/Skinning/Frames/LFG.lua:122 already reaches this same API this way.
-- Do NOT widen .luacheckrc instead.
local C_LFGList = _G.C_LFGList
local C_ChallengeMode = C_ChallengeMode
local C_MythicPlus = C_MythicPlus
local GameTooltip = GameTooltip
local IsInGroup = IsInGroup
local LibStub = LibStub
local hooksecurefunc = hooksecurefunc
local InCombatLockdown = InCombatLockdown

-- The party-keystone library is OPTIONAL. Every call site is guarded, so
-- without it the module still works -- the player's own gold key glow is
-- read directly from the API and never goes through the library.
local LKS = LibStub and LibStub:GetLibrary("LibKeystone", true)
local partyKeys = {}   -- [senderShortName] = { level = n, cmID = n }

local issecretvalue = issecretvalue
local playerShortName = UnitNameUnmodified and UnitNameUnmodified("player") or UnitName("player")
-- Both name APIs are SecretWhenUnitIdentityRestricted (UnitDocumentation.lua
-- :2367-2382 and :2401-2415). This capture runs once at file load, which is
-- normally unrestricted -- but a /reload inside a restricted context captures
-- a SECRET string, and this value is later concatenated into tooltip text and
-- compared against a comms sender. Both throw on a secret. Fail closed to nil;
-- the one tooltip use site falls back to a generic label.
if issecretvalue and issecretvalue(playerShortName) then playerShortName = nil end

local ICON_SIZE = 32
local ICON_GAP  = 4

-- Season dungeon data. ActiveDungeons() filters to the live season via
-- C_ChallengeMode.GetMapTable(), so no manual source switch is needed when
-- the next season goes live.
local DUNGEONS = {
    -- Season 1
    { key = "windrunner_spire",     mapID = 2805, cmID = 557, lfgID = 1542 },
    { key = "maisara_caverns",      mapID = 2874, cmID = 560, lfgID = 1764 },
    { key = "magisters_terrace",    mapID = 2811, cmID = 558, lfgID = 1760 },
    { key = "nexus_point_xenas",    mapID = 2915, cmID = 559, lfgID = 1768 },
    { key = "algeth_ar_academy",    mapID = 2526, cmID = 402, lfgID = 1160 },
    { key = "seat_of_triumvirate",  mapID = 1753, cmID = 239, lfgID = 486  },
    { key = "skyreach",             mapID = 1209, cmID = 161, lfgID = 182  },
    { key = "pit_of_saron",         mapID = 658,  cmID = 556, lfgID = 1770 },
    -- Season 2
    { key = "altar_of_fangs",       mapID = 2993, cmID = 588, lfgID = 1933 },
    { key = "kings_rest",           mapID = 1762, cmID = 249, lfgID = 514  },
    { key = "ruby_life_pools",      mapID = 2521, cmID = 399, lfgID = 1176 },
    { key = "temple_of_sethraliss", mapID = 1877, cmID = 250, lfgID = 504  },
    { key = "murder_row",           mapID = 2813, cmID = 587, lfgID = 1950 },
    { key = "den_of_nalorakk",      mapID = 2825, cmID = 586, lfgID = 1952 },
    { key = "blinding_vale",        mapID = 2859, cmID = 584, lfgID = 1949 },
    { key = "voidscar_arena",       mapID = 2923, cmID = 585, lfgID = 1951 },
}
local SEASON1_COUNT = 8 -- fallback slice when GetMapTable is empty

local initialized  = false
local buttons      = {}
local container    = nil
local updateTicker = nil

local Init, MakeButton, RefreshGlow, SyncVisibility
local SaveLayout, PushLayout, PopLayout
-- Assigned inside Init (Task 5). Forward-declared so OnDisable can reach the
-- secure overlay, which otherwise lives only in Init's closure.
local HideDoubleClickOverlay

-- Filters DUNGEONS to those active in the current season. Falls back to the
-- season-1 slice when the active set is empty, which happens at early login
-- before map info resolves.
local function ActiveDungeons()
    local fallback = {}
    for i = 1, SEASON1_COUNT do fallback[i] = DUNGEONS[i] end
    if not C_ChallengeMode then return fallback end
    local cmIDs = C_ChallengeMode.GetMapTable()
    if not cmIDs or #cmIDs == 0 then return fallback end

    local active = {}
    for i = 1, #cmIDs do active[cmIDs[i]] = true end

    local out = {}
    for i = 1, #DUNGEONS do
        local d = DUNGEONS[i]
        if d.cmID and d.cmID > 0 and active[d.cmID] then
            out[#out + 1] = d
        end
    end
    return #out > 0 and out or fallback
end

-- Returns the playstyle set in the Entry Creation frame, falling back to the
-- saved default when the frame's value is unset. READ ONLY -- see the header:
-- writing ec.generalPlaystyle taints the field.
local function CurrentPlaystyle()
    local ec = _G.LFGListFrame and _G.LFGListFrame.EntryCreation
    if ec and type(ec.generalPlaystyle) == "number" and ec.generalPlaystyle > 0 then
        return ec.generalPlaystyle
    end
    return (QC.db and QC.db.DefaultPlaystyle) or 0
end

-- Read-only test seams. Both helpers are pure file-locals with no other
-- handle; exporting them creates no second source of truth.
QC._ActiveDungeons   = ActiveDungeons
QC._CurrentPlaystyle = CurrentPlaystyle
