-- ╔══════════════════════════════════════════════════════════╗
-- ║  TimeSpiral.lua                                          ║
-- ║  Module: Time Spiral Tracker                             ║
-- ║  Purpose: Shows the Time Spiral buff with the player's   ║
-- ║           movement-spell icon. All classes supported.    ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class TimeSpiral: AceModule, AceEvent-3.0
local TSP = KitnEssentials:NewModule("TimeSpiral", "AceEvent-3.0")

local C_SpellBook = C_SpellBook
local SpellBookBank_Player = Enum.SpellBookSpellBank.Player
local GetSpecialization = C_SpecializationInfo.GetSpecialization
local GetSpecializationInfo = C_SpecializationInfo.GetSpecializationInfo
local ipairs = ipairs

---------------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------------
local TIME_SPIRAL_ICON = 4622479

-- The buff lands under a different id for each class.
local TIME_SPIRAL_BUFF_IDS = {
    375226, 375229, 375230, 375234, 375238, 375240, 375252,
    375253, 375254, 375255, 375256, 375257, 375258,
}

-- Per-spec movement spells as { spellID, iconID }, in priority order. The
-- icon is the first entry the player knows, so specs with talent alternates
-- list every choice.
local PRIMARY_BY_SPEC = {
    -- Death Knight
    [250]  = { { 48265, 237561 } },                                    -- Blood: Death's Advance
    [251]  = { { 48265, 237561 } },                                    -- Frost: Death's Advance
    [252]  = { { 48265, 237561 } },                                    -- Unholy: Death's Advance
    -- Demon Hunter
    [577]  = { { 195072, 1247261 } },                                  -- Havoc: Fel Rush
    [581]  = { { 189110, 1344650 } },                                  -- Vengeance: Infernal Strike
    [1480] = { { 1234796, 7554213 } },                                 -- Devourer: Shift
    -- Druid (Dash > Tiger Dash)
    [102]  = { { 1850, 132120 }, { 252216, 1817485 } },                -- Balance
    [103]  = { { 1850, 132120 }, { 252216, 1817485 } },                -- Feral
    [104]  = { { 1850, 132120 }, { 252216, 1817485 } },                -- Guardian
    [105]  = { { 1850, 132120 }, { 252216, 1817485 } },                -- Restoration
    -- Evoker
    [1467] = { { 358267, 4622463 } },                                  -- Devastation: Hover
    [1468] = { { 358267, 4622463 } },                                  -- Preservation: Hover
    [1473] = { { 358267, 4622463 } },                                  -- Augmentation: Hover
    -- Hunter
    [253]  = { { 186257, 132242 } },                                   -- Beast Mastery: Cheetah
    [254]  = { { 186257, 132242 } },                                   -- Marksmanship: Cheetah
    [255]  = { { 186257, 132242 } },                                   -- Survival: Cheetah
    -- Mage (Blink > Shimmer)
    [62]   = { { 1953, 135736 }, { 212653, 135739 } },                 -- Arcane
    [63]   = { { 1953, 135736 }, { 212653, 135739 } },                 -- Fire
    [64]   = { { 1953, 135736 }, { 212653, 135739 } },                 -- Frost
    -- Monk (Roll > Chi Torpedo)
    [268]  = { { 109132, 574574 }, { 115008, 607849 } },               -- Brewmaster
    [270]  = { { 109132, 574574 }, { 115008, 607849 } },               -- Mistweaver
    [269]  = { { 109132, 574574 }, { 115008, 607849 } },               -- Windwalker
    -- Paladin
    [65]   = { { 190784, 1360759 } },                                  -- Holy: Divine Steed
    [66]   = { { 190784, 1360759 } },                                  -- Protection: Divine Steed
    [70]   = { { 190784, 1360759 } },                                  -- Retribution: Divine Steed
    -- Priest
    [256]  = { { 73325, 463835 } },                                    -- Discipline: Leap of Faith
    [257]  = { { 73325, 463835 } },                                    -- Holy: Leap of Faith
    [258]  = { { 73325, 463835 } },                                    -- Shadow: Leap of Faith
    -- Rogue
    [259]  = { { 2983, 132307 } },                                     -- Assassination: Sprint
    [260]  = { { 2983, 132307 } },                                     -- Outlaw: Sprint
    [261]  = { { 2983, 132307 } },                                     -- Subtlety: Sprint
    -- Shaman: Gust of Wind / Spirit Walk are talent-choice (mutually
    -- exclusive); Spiritwalker's Grace is a separate talent stackable
    -- on top. Per-spec priority reflects typical spec preference, with
    -- the alternates listed as fallbacks so detection always lands on
    -- something the player actually has.
    [262]  = { { 79206, 451170 }, { 192063, 463565 }, { 58875, 132328 } }, -- Elemental: SWG > GoW > SW
    [263]  = { { 58875, 132328 }, { 192063, 463565 }, { 79206, 451170 } }, -- Enhancement: SW > GoW > SWG
    [264]  = { { 79206, 451170 }, { 192063, 463565 }, { 58875, 132328 } }, -- Restoration: SWG > GoW > SW
    -- Warlock
    [265]  = { { 48020, 237560 } },                                    -- Affliction: Demonic Circle: Teleport
    [266]  = { { 48020, 237560 } },                                    -- Demonology: Demonic Circle: Teleport
    [267]  = { { 48020, 237560 } },                                    -- Destruction: Demonic Circle: Teleport
    -- Warrior
    [71]   = { { 6544, 236171 } },                                     -- Arms: Heroic Leap
    [72]   = { { 6544, 236171 } },                                     -- Fury: Heroic Leap
    [73]   = { { 6544, 236171 } },                                     -- Protection: Heroic Leap
}

---------------------------------------------------------------------------------
-- Icon pick
---------------------------------------------------------------------------------
function TSP.PickIcon(list, isKnown, fallback)
    if list then
        for _, entry in ipairs(list) do
            if isKnown(entry[1]) then return entry[2] end
        end
    end
    return fallback
end

-- IsSpellKnown only: IsSpellInSpellBook and IsSpellUsable also report spells
-- whose talent is not selected.
local function IsKnownByPlayer(spellID)
    return C_SpellBook.IsSpellKnown(spellID, SpellBookBank_Player)
end

local function CurrentSpecList()
    local specID = GetSpecializationInfo(GetSpecialization() or 0)
    if not specID then return nil end
    return PRIMARY_BY_SPEC[specID]
end

-- The fallback is not cached, so a pick made before spell data loads is
-- retried on the next call.
function TSP:GetDisplayIcon()
    if self.iconID then return self.iconID end
    local icon = TSP.PickIcon(CurrentSpecList(), IsKnownByPlayer, TIME_SPIRAL_ICON)
    if icon ~= TIME_SPIRAL_ICON then self.iconID = icon end
    return icon
end

---------------------------------------------------------------------------------
-- Display declaration
---------------------------------------------------------------------------------
local function BuildCandidates()
    local set = {}
    for i = 1, #TIME_SPIRAL_BUFF_IDS do
        set[TIME_SPIRAL_BUFF_IDS[i]] = true
    end
    return { includeSpellIDs = set }
end

local function BuildPreview()
    return {
        { icon = TSP:GetDisplayIcon(), groupKey = "timespiral", count = 0 },
    }
end

-- Every live paint goes through here, so paintedIcon is what the buttons
-- show. The cached pick is not: the preview caches one without painting them.
local function LiveIcon()
    local icon = TSP:GetDisplayIcon()
    TSP.paintedIcon = icon
    return icon
end

-- No vehiclePolicy: the default hides the display in a vehicle seat, where a
-- movement ability cannot be used. "follow" would watch the vehicle unit,
-- which never carries the buff.
local DECLARATION = {
    key = "TimeSpiral",
    dbKey = "TimeSpiral",
    displayName = "Time Spiral",
    guiPath = "ClassTools",
    guiTab = "TimeSpiral",
    sortMethod = "AuraInstanceIDOnly",
    defaultIconsPerRow = 1,

    groups = {
        {
            key = "timespiral",
            buildFilter = function() return "HELPFUL" end,
            buildCandidates = BuildCandidates,
            capabilities = {
                hasBorder = true,
                hasDispelBadge = false,
                hasDispelRing = false,
                hasGlow = true,
                hasLabel = true,
                hasTimerFont = true,
                fixedIcon = LiveIcon,
            },
        },
    },

    splitLimit = function(total)
        return { timespiral = total }
    end,

    sounds = {
        spellIDs = TIME_SPIRAL_BUFF_IDS,
        unit = "player",
        settingKeys = { enabled = "SoundEnabled", name = "SoundName" },
    },

    buildPreview = BuildPreview,
}

---------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------
function TSP:UpdateDB()
    self.db = KE.db.profile.TimeSpiral
end

function TSP:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

function TSP:OnEnable()
    self:UpdateDB()
    if not self.db or not self.db.Enabled then return end

    -- Spec and spell events are not received while the module is off, so a
    -- pick cached before a disable can be stale.
    self.iconID = nil

    if not self.display then
        self.display = KE.AuraEngine.Register(self, DECLARATION, function() return self.db end)
    else
        KE.AuraEngine.RegisterEvents(self.display)
    end

    KE.AuraEngine.ApplySettings(self.display)

    -- AceEvent drops every event on disable, so each enable registers these.
    -- PLAYER_ENTERING_WORLD stays the engine's: a second registration on this
    -- owner would replace its handler.
    self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", "OnSpecChanged")
    self:RegisterEvent("TRAIT_CONFIG_UPDATED", "RepickIcon")
    self:RegisterEvent("SPELLS_CHANGED", "RepickIcon")
end

-- Reconfigures only when the new pick differs from the painted icon. The
-- engine defers that while auras are restricted, so a pick that fell back at
-- login is repainted once spell data lands outside a restricted window.
function TSP:RepickIcon()
    self.iconID = nil
    if self:GetDisplayIcon() ~= self.paintedIcon then
        KE.AuraEngine.ApplySettings(self.display)
    end
end

-- The event fires for every group member; only the player's spec decides the
-- icon.
function TSP:OnSpecChanged(_, unit)
    if unit ~= "player" then return end
    self:RepickIcon()
end

function TSP:OnDisable()
    KE.AuraEngine.SetModuleEnabled(self.display, false)
end

function TSP:ApplySettings()
    self:UpdateDB()
    KE.AuraEngine.ApplySettings(self.display)
end

function TSP:ShowPreview()
    KE.AuraEngine.ShowPreview(self.display)
end

function TSP:HidePreview()
    KE.AuraEngine.HidePreview(self.display)
end
