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

    -- Follow cursor (throttled to ~60fps).
    -- Skip-if-stationary cache: when (cursor, scale, offsets) all match the
    -- prior tick, ClearAllPoints+SetPoint is a no-op so we return early.
    -- Offsets are part of the key so a live GUI offset edit still repositions
    -- without the user needing to nudge the cursor. Sentinel -1 ensures the
    -- first tick always runs.
    local cursorElapsed = 0
    local lastX, lastY, lastScale, lastXOff, lastYOff = -1, -1, -1, -1, -1
    frame._onUpdate = function(_, elapsed)
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
        local xOff = sdb.XOffset or 10
        local yOff = sdb.YOffset or 10
        if x == lastX and y == lastY and scale == lastScale
           and xOff == lastXOff and yOff == lastYOff then
            return
        end
        lastX, lastY, lastScale, lastXOff, lastYOff = x, y, scale, xOff, yOff

        cooldownText:ClearAllPoints()
        cooldownText:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT",
            (x / scale) + xOff,
            (y / scale) + yOff)
    end

    -- Event handler stashed on the frame so re-enable can re-attach it
    -- without needing to recreate the closures over UpdateCooldown / locals.
    frame._onEvent = function(_, event)
        if event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_SPECIALIZATION_CHANGED" then
            DC:FindDispelSpell()
        end
        UpdateCooldown()
    end

    self.frame = frame
    self:_AttachScripts()
end

---------------------------------------------------------------------------------
-- Script attach / detach (live-toggle support)
---------------------------------------------------------------------------------
-- CreateFrame is idempotent (early-returns if self.frame exists), so a
-- toggle off->on cycle skipped re-attaching scripts and the frame stayed
-- visible-but-frozen — no cursor follow, no cooldown numbers — until
-- /reload. The OnEnable / OnDisable lifecycle now flows through these
-- helpers so the scripts live and die with the module's enabled state.
function DC:_AttachScripts()
    local frame = self.frame
    if not frame then return end
    frame:SetScript("OnUpdate", frame._onUpdate)
    frame:SetScript("OnEvent",  frame._onEvent)
    frame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    frame:Show()
end

function DC:_DetachScripts()
    local frame = self.frame
    if not frame then return end
    frame:UnregisterAllEvents()
    frame:SetScript("OnUpdate", nil)
    frame:SetScript("OnEvent",  nil)
    frame:Hide()
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
    self:_AttachScripts()  -- idempotent re-enable: CreateFrame above is a no-op, this re-arms the scripts
    self:FindDispelSpell()
end

function DC:OnDisable()
    self:_DetachScripts()
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
