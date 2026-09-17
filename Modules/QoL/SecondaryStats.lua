-- ╔══════════════════════════════════════════════════════════╗
-- ║  SecondaryStats.lua                                      ║
-- ║  Module: Secondary Stats                                 ║
-- ║  Purpose: On-screen readout of the player's secondary    ║
-- ║           and tertiary stats.                            ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class SecondaryStats: AceModule, AceEvent-3.0
local SS = KitnEssentials:NewModule("SecondaryStats", "AceEvent-3.0")

local CreateFrame = CreateFrame
local C_Timer = C_Timer
local UnitClass = UnitClass
local GetCritChance = GetCritChance
local UnitSpellHaste = UnitSpellHaste
local GetMasteryEffect = GetMasteryEffect
local GetCombatRating = GetCombatRating
local GetCombatRatingBonus = GetCombatRatingBonus
local GetVersatilityBonus = GetVersatilityBonus
local GetLifesteal = GetLifesteal
local GetAvoidance = GetAvoidance
local GetSpeed = GetSpeed
local issecretvalue = issecretvalue
local GetSpecialization = C_SpecializationInfo.GetSpecialization
local GetSpecializationInfo = C_SpecializationInfo.GetSpecializationInfo
local string_format = string.format
local math_floor = math.floor
local unpack = unpack

---------------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------------
-- One hue per secondary so the rows scan at a glance; the three tertiaries
-- share a hue of their own so the block reads as two groups.
local STAT_HEX = {
    crit = "ffd100",
    haste = "2ecc71",
    mastery = "55aaff",
    vers = "c77dff",
}

local TERTIARY = { leech = true, avoidance = true, speed = true }

local FULL_LABEL = {
    crit = "Crit", haste = "Haste", mastery = "Mastery", vers = "Vers",
    leech = "Leech", avoidance = "Avoidance", speed = "Speed",
}

local SHORT_LABEL = {
    crit = "C", haste = "H", mastery = "M", vers = "V",
    leech = "L", avoidance = "A", speed = "S",
}

-- Rating ids are resolved at read time rather than stored, so a client that
-- renames one cannot leave a stale number here.
local RATING_ID = {
    crit = "CR_CRIT_MELEE",
    haste = "CR_HASTE_MELEE",
    mastery = "CR_MASTERY",
    vers = "CR_VERSATILITY_DAMAGE_DONE",
    leech = "CR_LIFESTEAL",
    avoidance = "CR_AVOIDANCE",
    speed = "CR_SPEED",
}

-- Bursts of rating updates arrive many times a second in combat. Redraw on the
-- leading edge and once more when the burst has settled: spending the window
-- before the first redraw is what leaves the block behind the character sheet.
local BURST_WINDOW = 0.5

-- Events whose FIRST payload argument is a unit token, so the handler may
-- filter on it. Membership is by payload shape, not by name: the equipment
-- event leads with a slot id, and filtering it as a unit would swallow every
-- gear swap.
local UNIT_EVENTS = {
    UNIT_STATS = true,
    UNIT_SPELL_HASTE = true,
    PLAYER_DAMAGE_DONE_MODS = true,
}

-- The events the per-spec gate owns. They are registered when the current spec
-- is enabled and unregistered when it is not, which is what makes a disabled
-- spec cost nothing. The two spec-watch events are deliberately NOT here: they
-- have to outlive the gate or nothing could ever switch it back on.
local STAT_EVENTS = {
    "UNIT_STATS",
    "UNIT_SPELL_HASTE",
    "PLAYER_DAMAGE_DONE_MODS",
    "COMBAT_RATING_UPDATE",
    "MASTERY_UPDATE",
    -- Blizzard declares a dedicated event for each tertiary. Without these
    -- three, those rows only refresh when an unrelated event happens to fire.
    "AVOIDANCE_UPDATE",
    "LIFESTEAL_UPDATE",
    "SPEED_UPDATE",
    "SPELL_POWER_CHANGED",
    "PLAYER_EQUIPMENT_CHANGED",
}

-- Talent and spec state is not reliable immediately on a spec change event.
local SPEC_SETTLE_DELAY = 2

---------------------------------------------------------------------------------
-- Module State
---------------------------------------------------------------------------------
SS.frame = nil
SS.isPreview = false
SS.editModeRegistered = false
SS.versCached = nil
SS.classHex = nil
SS.pending = false

---------------------------------------------------------------------------------
-- DB Helper
---------------------------------------------------------------------------------
function SS:UpdateDB()
    self.db = KE.db.profile.SecondaryStats
end

---------------------------------------------------------------------------------
-- Per-spec gate
---------------------------------------------------------------------------------
-- Absent means enabled. Only an explicit opt-out is ever stored, so a profile
-- that has never touched the card stores nothing and behaves exactly as it did
-- before the setting existed.
--
-- An unresolvable spec reads as enabled rather than disabled: failing closed
-- would blank the readout on a fresh character or mid-load, which looks like
-- the module is broken, while failing open corrects itself on the next event.
function SS:IsSpecEnabled(db, specId)
    local specs = db and db.EnabledSpecs
    if not specs or not specId then return true end
    return specs[specId] ~= false
end

function SS:ResolveSpecId()
    if not GetSpecialization then return nil end
    local index = GetSpecialization()
    if not index or index == 0 then return nil end
    return GetSpecializationInfo and GetSpecializationInfo(index)
end

---------------------------------------------------------------------------------
-- Colour
---------------------------------------------------------------------------------
local function ToHex(r, g, b)
    return string_format("%02x%02x%02x",
        math_floor((r or 1) * 255), math_floor((g or 1) * 255), math_floor((b or 1) * 255))
end

-- Cache only a RESOLVED class colour. Caching the white fallback leaves the
-- labels white for the session when the first paint beats the colour system.
-- The secret test comes first: the class file is restricted in restricted
-- content, and testing its truth would throw.
function SS:ClassHex()
    if self.classHex then return self.classHex end
    local _, class = UnitClass("player")
    if issecretvalue and issecretvalue(class) then return nil end
    local colors = _G.RAID_CLASS_COLORS
    local color = class and colors and colors[class]
    if color then
        self.classHex = ToHex(color.r, color.g, color.b)
    end
    return self.classHex
end

function SS:LabelHex(key)
    local db = self.db
    if TERTIARY[key] then
        if db.TertiaryColorMode == "custom" and db.TertiaryColor then
            return ToHex(db.TertiaryColor[1], db.TertiaryColor[2], db.TertiaryColor[3])
        end
        return self:ClassHex() or "ffffff"
    end
    if db.ColorMode == "custom" and db.CustomColor then
        return ToHex(db.CustomColor[1], db.CustomColor[2], db.CustomColor[3])
    end
    if db.ColorMode == "class" then
        return self:ClassHex() or "ffffff"
    end
    return STAT_HEX[key] or "ffffff"
end

function SS:Label(key)
    local db = self.db
    if db.LabelStyle == "short" then return SHORT_LABEL[key] end
    if db.LabelStyle == "custom" then
        local custom = db.CustomLabels and db.CustomLabels[key]
        if custom and custom ~= "" then return custom end
    end
    return FULL_LABEL[key]
end

---------------------------------------------------------------------------------
-- Stat Reads
---------------------------------------------------------------------------------
-- Every figure below is READ and forwarded, never compared, formatted in Lua
-- or used in arithmetic. Versatility is the single exception and is resolved
-- through the formatter's refusal rule.
function SS:ReadPercent(key)
    if key == "crit" then return GetCritChance() end
    if key == "haste" then return UnitSpellHaste("player") end
    if key == "mastery" then return GetMasteryEffect() end
    if key == "leech" then return GetLifesteal() end
    if key == "avoidance" then return GetAvoidance() end
    if key == "speed" then return GetSpeed() end
    if key == "vers" then
        local ratingId = _G[RATING_ID.vers]
        if not ratingId then return nil end
        local value, cached = KE.SecondaryStatsFormat.ResolveVersatility(
            GetCombatRatingBonus(ratingId), GetVersatilityBonus(ratingId),
            self.versCached, issecretvalue)
        self.versCached = cached
        return value
    end
    return nil
end

function SS:ReadRating(key)
    local ratingId = _G[RATING_ID[key]]
    if not ratingId then return nil end
    return GetCombatRating(ratingId)
end

---------------------------------------------------------------------------------
-- Render
---------------------------------------------------------------------------------
function SS:UpdateDisplay()
    if not self.frame or not self.frame:IsShown() then return end
    local db = self.db
    local Format = KE.SecondaryStatsFormat

    local entries = {}
    local keys = Format.VisibleKeys(db.Order, db.Stats or {})
    for index = 1, #keys do
        local key = keys[index]
        local mode = db.Stats[key].ValueMode or "percent"
        -- Plain `if`, not an `and`/`or` chain: that idiom would evaluate the
        -- truthiness of the figure it just read, and a restricted figure
        -- refuses exactly that.
        local percentValue, ratingValue
        if mode ~= "rating" then percentValue = self:ReadPercent(key) end
        if mode ~= "percent" then ratingValue = self:ReadRating(key) end
        entries[#entries + 1] = {
            label = self:Label(key),
            hex = self:LabelHex(key),
            valueMode = mode,
            percent = percentValue,
            rating = ratingValue,
        }
    end

    local template, vals = Format.BuildRows(entries, {
        decimals = db.Decimals or 2,
        separator = db.Separator or ":",
        direction = db.TextDirection or "LEFT",
        showLabel = db.LabelStyle ~= "hidden",
        coloredValues = db.ColoredValues == true,
    })

    -- The engine fills the template. This is the whole point: a restricted
    -- figure is never read in Lua, so it draws its true number.
    self.frame.text:SetFormattedText(template, unpack(vals))
    self:ResizeToText()
end

-- Measuring is the one thing a restricted figure costs. The metrics belong to
-- the last LAID OUT string, so the first clean paint after a restricted one
-- still hands back restricted extents -- test what the arithmetic is about to
-- touch, not what was fed in. Leaving combat brings the footprint back.
function SS:ResizeToText()
    local width = self.frame.text:GetStringWidth()
    local height = self.frame.text:GetStringHeight()
    if issecretvalue and (issecretvalue(width) or issecretvalue(height)) then return end
    if not width or not height then return end
    self.frame:SetSize(width + 2, height + 2)
end

---------------------------------------------------------------------------------
-- Frame Creation
---------------------------------------------------------------------------------
function SS:CreateDisplayFrame()
    if self.frame then return end

    local frame = CreateFrame("Frame", "KE_SecondaryStatsFrame", UIParent)
    frame:SetSize(160, 60)
    frame:SetFrameStrata(self.db.Strata or "LOW")

    local text = frame:CreateFontString(nil, "OVERLAY")
    frame.text = text

    frame:Hide()
    self.frame = frame
end

---------------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------------
-- The public entry, and the ONLY thing a profile switch calls: ProfileManager
-- rebinds the db and then applies settings, so without a gate check here the
-- module keeps reading stats on a spec the incoming profile has turned off, and
-- stays off on one the incoming profile has turned on, until the next zone.
-- Routed, never recursive: the gate reaches the layout below through ApplyLayout.
function SS:ApplySettings()
    if self.isPreview or not self:IsEnabled() then
        self:ApplyLayout()
        return
    end
    self:ApplySpecGate()
end

function SS:ApplyLayout()
    if not self.frame then return end
    local db = self.db

    KE:ApplyFramePosition(self.frame, db.Position, db)

    -- Scale multiplies the font rather than the frame: SetScale would fight the
    -- addon-wide pixel snap that ApplyFramePosition just performed.
    local scale = db.Scale or 1
    KE:ApplyFontToText(self.frame.text, db.FontFace,
        math_floor((db.FontSize or 12) * scale + 0.5), db.FontOutline, db.FontShadow)
    self.frame.text:SetSpacing(math_floor((db.RowGap or 3) * scale + 0.5))

    -- Right-ordered rows need the block to line up on its right edge too,
    -- otherwise the labels sit ragged against the screen edge they face.
    local right = db.TextDirection == "RIGHT"
    self.frame.text:ClearAllPoints()
    self.frame.text:SetPoint(right and "TOPRIGHT" or "TOPLEFT")
    self.frame.text:SetJustifyH(right and "RIGHT" or "LEFT")

    self:UpdateDisplay()
end

---------------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------------
function SS:OnStatEvent(event, arg1)
    -- The unit filter applies ONLY to the unit-scoped events. The equipment
    -- event's first argument is a slot id, so filtering it as a unit would
    -- swallow every gear swap.
    if UNIT_EVENTS[event] and arg1 ~= "player" then return end
    if self.pending then return end
    self.pending = true
    self:UpdateDisplay()
    C_Timer.After(BURST_WINDOW, function()
        self.pending = false
        self:UpdateDisplay()
    end)
end

-- Restricted stat secrecy lifts here. The figures stay live through a fight
-- because they render as arguments; it is the block's measured footprint that
-- needs this edge to catch up.
function SS:OnRegenEnabled()
    self:UpdateDisplay()
end

---------------------------------------------------------------------------------
-- Edit Mode
---------------------------------------------------------------------------------
function SS:RegWithEditMode()
    if KE.EditMode and not self.editModeRegistered then
        KE.EditMode:RegisterElement({
            key = "SecondaryStats",
            module = self,
            displayName = "Secondary Stats Display",
            frame = self.frame,
            getPosition = function() return self.db.Position end,
            setPosition = function(pos)
                self.db.Position = pos
                KE:ApplyFramePosition(self.frame, self.db.Position, self.db)
            end,
            getParentFrame = function()
                return KE:ResolveAnchorFrame(self.db.anchorFrameType, self.db.ParentFrame)
            end,
            guiPath = "SecondaryStats",
        })
        self.editModeRegistered = true
    end
end

---------------------------------------------------------------------------------
-- Preview
---------------------------------------------------------------------------------
function SS:ShowPreview()
    if not self.frame then self:CreateDisplayFrame() end
    self:RegWithEditMode()
    self.isPreview = true
    self.frame:Show()
    self:ApplyLayout()
end

-- The spec gate counts here as much as the master enable: without it, closing
-- the page on a spec the player has just unticked would leave the readout on
-- screen until the next spec change.
function SS:HidePreview()
    self.isPreview = false
    if not self.frame then return end
    if not self.db.Enabled or not self:IsSpecEnabled(self.db, self:ResolveSpecId()) then
        self.frame:Hide()
    end
end

---------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------
function SS:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

function SS:OnEnable()
    if not self.db.Enabled then return end

    -- Registered OUTSIDE the gate, because the gate is what unregisters
    -- everything else: a spec the player disabled has to stay able to hear
    -- itself being switched away from, or it is off until a reload.
    self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", "OnSpecChanged")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnSpecChanged")

    self:ApplySpecGate()
end

function SS:ApplySpecGate()
    if self:IsSpecEnabled(self.db, self:ResolveSpecId()) then
        self:StartForSpec()
    else
        self:StopForSpec()
    end
end

function SS:StartForSpec()
    self:CreateDisplayFrame()
    self:RegWithEditMode()

    for index = 1, #STAT_EVENTS do
        self:RegisterEvent(STAT_EVENTS[index], "OnStatEvent")
    end
    self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnRegenEnabled")

    self.frame:Show()
    -- Re-applied even when the gate was already open, because this is also the
    -- redraw path for a zone change and a spec change.
    self:ApplyLayout()
end

function SS:StopForSpec()
    for index = 1, #STAT_EVENTS do
        self:UnregisterEvent(STAT_EVENTS[index])
    end
    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
    self.pending = false
    -- The preview owns the frame while the settings page is open, so a spec the
    -- player just unticked still draws until they close the page.
    if self.frame and not self.isPreview then self.frame:Hide() end
end

-- Applied twice on purpose. The immediate pass keeps the redraw this event used
-- to trigger, and handles the common case where the spec already reads
-- correctly; the deferred one is the only pass whose spec read can be trusted.
function SS:OnSpecChanged(event, unit)
    -- The spec event carries a unit token and fires for group members as well,
    -- so without this every party spec swap would rebuild this player's block.
    if event == "PLAYER_SPECIALIZATION_CHANGED" and unit ~= "player" then return end
    self:ApplySpecGate()
    C_Timer.After(SPEC_SETTLE_DELAY, function()
        if self:IsEnabled() then self:ApplySpecGate() end
    end)
end

function SS:OnDisable()
    self:UnregisterAllEvents()
    self.pending = false
    self.isPreview = false
    if self.frame then self.frame:Hide() end
end
