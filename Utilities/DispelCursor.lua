-- ╔══════════════════════════════════════════════════════════╗
-- ║  DispelCursor.lua                                        ║
-- ║  Module: Dispel CD on Cursor                             ║
-- ║  Purpose: Shows dispel cooldown timer following the      ║
-- ║           cursor. Auto-detects class dispel spell.       ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class DispelCursor: AceModule, AceEvent-3.0
local DC = KitnEssentials:NewModule("DispelCursor", "AceEvent-3.0")

local CreateFrame = CreateFrame
local GetCursorPosition = GetCursorPosition
local C_Spell = C_Spell
local C_SpellBook = C_SpellBook
local ipairs = ipairs
local UIParent = UIParent

---------------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------------
local DISPEL_SPELL_IDS = {
    -- Healer dispels
    115450, -- Detox (Monk - MW)
    4987,   -- Cleanse (Paladin - Holy)
    527,    -- Purify (Priest - Holy/Disc)
    360823, -- Naturalize (Evoker - Preservation)
    88423,  -- Nature's Cure (Druid - Restoration)
    77130,  -- Purify Spirit (Shaman - Restoration)
    -- DPS/Tank dispels
    119905, -- Singe Magic (Warlock - Imp Dispel)
    213634, -- Purify Disease (Priest - Shadow)
    218164, -- Detox (Monk - WW/BM)
    213644, -- Cleanse Toxins (Paladin - Ret/Prot)
    2782,   -- Remove Corruption (Druid - Balance/Feral)
    475,    -- Remove Curse (Mage)
    365585, -- Expunge (Evoker - Devastation/Augmentation)
    51886,  -- Cleanse Spirit (Shaman - Elemental/Enhancement)
}

---------------------------------------------------------------------------------
-- Module State
---------------------------------------------------------------------------------
DC.frame = nil
DC.trackedSpellId = nil

---------------------------------------------------------------------------------
-- DB Helper
---------------------------------------------------------------------------------
function DC:UpdateDB()
    self.db = KE.db.profile.DispelCursor
end

function DC:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

---------------------------------------------------------------------------------
-- Core Logic
---------------------------------------------------------------------------------
function DC:FindDispelSpell()
    self.trackedSpellId = nil
    for _, spellID in ipairs(DISPEL_SPELL_IDS) do
        if C_SpellBook.IsSpellInSpellBook(spellID) then
            self.trackedSpellId = spellID
            return
        end
    end
end

---------------------------------------------------------------------------------
-- Frame Creation
---------------------------------------------------------------------------------
function DC:CreateFrame()
    if self.frame then return end
    local db = self.db

    local frame = CreateFrame("Frame", "KE_DispelCursorFrame", UIParent)
    frame:SetFrameStrata("TOOLTIP")
    frame:SetSize(1, 1)

    -- Cooldown frame (hidden, just for countdown text)
    local cooldownFrame = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
    cooldownFrame:SetSize(1, 1)
    cooldownFrame:SetDrawSwipe(false)
    cooldownFrame:SetDrawEdge(false)
    cooldownFrame:SetDrawBling(false)
    cooldownFrame:SetHideCountdownNumbers(false)

    -- Find the countdown text region
    local cooldownText = nil
    for _, region in ipairs({ cooldownFrame:GetRegions() }) do
        if region:GetObjectType() == "FontString" then
            cooldownText = region
            break
        end
    end

    if not cooldownText then
        cooldownText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    end
    local fontPath = KE:GetFontPath(db.FontFace) or KE.FONT
    cooldownText:SetFont(fontPath, db.FontSize or 18, "OUTLINE")
    local cr, cg, cb, ca = KE:ResolveColor(db.TextColor, { 1, 1, 1, 1 })
    cooldownText:SetTextColor(cr, cg, cb, ca)

    cooldownText:SetPoint("CENTER", UIParent, "BOTTOMLEFT", 0, 0)

    frame.cooldownFrame = cooldownFrame
    frame.cooldownText = cooldownText

    -- Update cooldown when it changes
    -- v1.4 upstream pattern: GetSpellCooldownDuration replaces GetSpellCooldown
    local function UpdateCooldown()
        if not DC.trackedSpellId then
            cooldownFrame:Clear()
            return
        end
        local duration = C_Spell.GetSpellCooldownDuration(DC.trackedSpellId)
        if duration then
            cooldownFrame:SetCooldownFromDurationObject(duration, false)
        else
            cooldownFrame:Clear()
        end
    end

    -- Follow cursor (throttled to ~60fps)
    local cursorElapsed = 0
    frame:SetScript("OnUpdate", function(_, elapsed)
        cursorElapsed = cursorElapsed + elapsed
        if cursorElapsed < 0.016 then return end
        cursorElapsed = 0

        local sdb = DC.db
        if not sdb or not sdb.Enabled then
            frame:Hide()
            return
        end
        local x, y = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale()
        cooldownText:ClearAllPoints()
        cooldownText:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT",
            (x / scale) + (sdb.XOffset or 10),
            (y / scale) + (sdb.YOffset or 10))
    end)

    -- Events
    frame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    frame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_SPECIALIZATION_CHANGED" then
            DC:FindDispelSpell()
        end
        UpdateCooldown()
    end)

    frame:Show()
    self.frame = frame
end

---------------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------------
function DC:ApplySettings()
    if not self.frame or not self.frame.cooldownText then return end
    local db = self.db
    local fontPath = KE:GetFontPath(db.FontFace) or KE.FONT
    self.frame.cooldownText:SetFont(fontPath, db.FontSize or 18, "OUTLINE")
    local cr, cg, cb, ca = KE:ResolveColor(db.TextColor, { 1, 1, 1, 1 })
    self.frame.cooldownText:SetTextColor(cr, cg, cb, ca)
end

---------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------
function DC:OnEnable()
    if not self.db.Enabled then return end
    self:CreateFrame()
    self:FindDispelSpell()
end

function DC:OnDisable()
    if self.frame then
        self.frame:UnregisterAllEvents()
        self.frame:SetScript("OnUpdate", nil)
        self.frame:SetScript("OnEvent", nil)
        self.frame:Hide()
    end
end

---------------------------------------------------------------------------------
-- Preview
---------------------------------------------------------------------------------
function DC:ShowPreview()
    if not self.frame then self:CreateFrame() end
    self:ApplySettings()
    self.frame:Show()
end

function DC:HidePreview()
    if not self.frame then return end
    if not self.db or not self.db.Enabled then
        self.frame:Hide()
    end
end

function DC:Refresh()
    self:ApplySettings()
end
