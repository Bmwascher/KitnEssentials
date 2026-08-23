-- ╔══════════════════════════════════════════════════════════╗
-- ║  StanceText.lua                                          ║
-- ║  Module: Stance Text                                     ║
-- ║  Purpose: Shows an icon when the current form, stance    ║
-- ║           or aura does not match what the spec expects.  ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class StanceText: AceModule, AceEvent-3.0
local ST = KitnEssentials:NewModule("StanceText", "AceEvent-3.0")

local CreateFrame = CreateFrame
local GetSpecialization = C_SpecializationInfo.GetSpecialization
local GetSpecializationInfo = C_SpecializationInfo.GetSpecializationInfo
local unpack = unpack
local ipairs = ipairs
local tostring = tostring
local InCombatLockdown = InCombatLockdown
local GetShapeshiftForm = GetShapeshiftForm
local GetShapeshiftFormInfo = GetShapeshiftFormInfo
local C_UnitAuras = C_UnitAuras
local C_Spell = C_Spell
local C_SpellBook = C_SpellBook
local C_RestrictedActions = C_RestrictedActions
local UIParent = UIParent

local MISSING_TEXT_DEFAULT = "MISSING"
local WRONG_TEXT_DEFAULT = "WRONG"

-- Per-spec expected form, keyed by specialization ID.
--
--   spellID  the form/aura/stance that spec is expected to hold
--   check    "form"  read through GetShapeshiftForm -- every spec today
--            "aura"  read through the player's auras. No spec uses this: aura
--                    identity is unreadable in combat, encounters, challenge
--                    mode and PvP, so the check goes blind exactly where it
--                    matters. Kept, with its guard, for a state that has no
--                    form equivalent. Prefer a form check whenever one exists.
--   also     extra spell IDs that also satisfy the requirement
--
-- Paladin auras and Warrior stances have several valid choices, so their
-- expected one is a setting; the value here is the default.
local WARRIOR_STANCES = { 386164, 386196, 386208 }
local PALADIN_AURAS   = { 465, 317920, 32223 }
local EVOKER_ATTUNE   = { 403264, 403265 }

local SPECS = {
    -- Warrior
    [71]   = { spellID = 386164, check = "form", options = WARRIOR_STANCES },
    [72]   = { spellID = 386196, check = "form", options = WARRIOR_STANCES },
    [73]   = { spellID = 386208, check = "form", options = WARRIOR_STANCES },
    -- Paladin: the three auras are the three stances, so they read as forms.
    [65]   = { spellID = 465,    check = "form", options = PALADIN_AURAS },
    [66]   = { spellID = 465,    check = "form", options = PALADIN_AURAS },
    [70]   = { spellID = 32223,  check = "form", options = PALADIN_AURAS },
    -- Druid
    [102]  = { spellID = 24858,  check = "form" },
    [103]  = { spellID = 768,    check = "form" },
    [104]  = { spellID = 5487,   check = "form" },
    -- Priest: Shadowform is a form, not a buff, so it reads in combat where an
    -- aura check cannot. Voidform is not a separate form -- it leaves the
    -- Shadowform reading in place -- so the alternative below never fires today.
    -- It stays as a backstop, and costs nothing: alternatives are only walked
    -- once the primary reading has already failed.
    [258]  = { spellID = 232698, check = "form", also = { 194249 } },
    -- Evoker: an attunement registers as a shapeshift form, so it reads like a
    -- Warrior stance. Reading it as an aura instead goes blind in restricted
    -- content and reports every attuned Evoker as missing one.
    [1473] = { spellID = 403264, check = "form", options = EVOKER_ATTUNE },
}
ST.SPECS = SPECS

-- Options page order. Every class is listed regardless of what is being
-- played, so settings can be prepared for an alt.
ST.CLASS_ORDER = { "WARRIOR", "PALADIN", "DRUID", "PRIEST", "EVOKER" }
ST.CLASS_SPECS = {
    WARRIOR = { 71, 72, 73 },
    PALADIN = { 65, 66, 70 },
    DRUID   = { 102, 103, 104 },
    PRIEST  = { 258 },
    EVOKER  = { 1473 },
}
ST.SPEC_NAMES = {
    [71] = "Arms", [72] = "Fury", [73] = "Protection",
    [65] = "Holy", [66] = "Protection", [70] = "Retribution",
    [102] = "Balance", [103] = "Feral", [104] = "Guardian",
    [258] = "Shadow", [1473] = "Augmentation",
}

local SPELL_NAMES = {
    [386164] = "Battle Stance", [386196] = "Berserker Stance", [386208] = "Defensive Stance",
    [465] = "Devotion Aura", [317920] = "Concentration Aura", [32223] = "Crusader Aura",
    [24858] = "Moonkin Form", [768] = "Cat Form", [5487] = "Bear Form",
    [232698] = "Shadowform", [403264] = "Black Attunement", [403265] = "Bronze Attunement",
}
ST.SPELL_NAMES = SPELL_NAMES

local function SpecEntry()
    local specIndex = GetSpecialization and GetSpecialization()
    local specID = specIndex and specIndex > 0 and GetSpecializationInfo(specIndex) or nil
    return specID, specID and SPECS[specID] or nil
end
ST.SpecEntry = SpecEntry

local function HasAura(spellID, also)
    if C_UnitAuras.GetPlayerAuraBySpellID(spellID) then return true end
    if also then
        for _, extra in ipairs(also) do
            if C_UnitAuras.GetPlayerAuraBySpellID(extra) then return true end
        end
    end
    return false
end

-- The four states in which the aura system stops reporting which spell an aura
-- belongs to. A by-ID lookup then answers "absent" for an aura that is present,
-- so the aura check has to stay quiet rather than accuse. Form checks read a
-- different subsystem and are never affected.
local AURA_HIDDEN_STATES
do
    local kinds = Enum and Enum.AddOnRestrictionType
    AURA_HIDDEN_STATES = kinds and {
        kinds.Combat, kinds.Encounter, kinds.ChallengeMode, kinds.PvPMatch,
    } or nil
end

local function AuraIdentityVisible()
    if not (AURA_HIDDEN_STATES and C_RestrictedActions
        and C_RestrictedActions.IsAddOnRestrictionActive) then
        return true
    end
    for _, state in ipairs(AURA_HIDDEN_STATES) do
        if C_RestrictedActions.IsAddOnRestrictionActive(state) then return false end
    end
    return true
end

-- The form the player is actually in, as a spell ID, or nil.
local function CurrentFormSpell()
    local index = GetShapeshiftForm()
    if not index or index == 0 then return nil end
    local _, _, _, spellID = GetShapeshiftFormInfo(index)
    return spellID
end

local function SpellIsKnown(spellID)
    if not (C_SpellBook and C_SpellBook.IsSpellKnown) then return true end
    return C_SpellBook.IsSpellKnown(spellID) == true
end

-- Reused rather than rebuilt: UNIT_AURA for the player fires constantly in
-- combat, and the reference's inline version allocates nothing on this path.
local evalContext = {
    hasAura = HasAura,
    isKnown = SpellIsKnown,
    auraIdentityVisible = AuraIdentityVisible,
}

-- The whole rule, with every world reading passed in. Returns the spell id to
-- draw, or nil to hide. Kept free of API calls so the rules can be tested
-- without faking the shapeshift and aura subsystems.
--
-- ctx fields: inCombat, currentFormSpell, hasAura(spellID, also),
-- isKnown(spellID), auraIdentityVisible()
function ST:EvaluateSpec(db, specID, entry, ctx)
    if not entry then return nil end

    local key = tostring(specID)
    if db[key .. "Enabled"] == false then return nil end

    -- Out-of-combat suppression is per spec: a Guardian druid out of combat is
    -- usually travelling, a Balance druid out of combat is usually not.
    if db[key .. "CombatOnly"] and not ctx.inCombat then return nil end

    local wanted = tonumber(db[key .. "Spell"]) or entry.spellID

    -- Not learned yet (low level, or the talent is not taken) -- nothing to
    -- remind about, and the icon would be a lie.
    if not ctx.isKnown(wanted) then return nil end

    local satisfied
    if entry.check == "aura" then
        satisfied = ctx.hasAura(wanted, entry.also)
        -- Only the accusing path pays for the check, which is the rare one.
        if not satisfied and not ctx.auraIdentityVisible() then return nil end
    else
        satisfied = ctx.currentFormSpell == wanted
        -- A form can have stand-ins too, the way Voidform stands in for
        -- Shadowform, so the alternatives count here as much as on the aura path.
        if not satisfied and entry.also then
            for _, extra in ipairs(entry.also) do
                if ctx.currentFormSpell == extra then
                    satisfied = true
                    break
                end
            end
        end
    end
    if satisfied then return nil end

    -- Reverse Icon shows what you ARE in rather than what you should be in.
    -- Useful for Warriors, where "you are in the wrong stance" reads better
    -- than "you are missing the right one". Falls back to the wanted icon when
    -- you are in no form at all, which would otherwise draw nothing.
    if db[key .. "ReverseIcon"] then
        return ctx.currentFormSpell or wanted
    end
    return wanted
end

function ST:UpdateDB()
    self.db = KE.db.profile.StanceText
end

function ST:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

function ST:CreateFrame()
    if self.frame then return end
    local db = self.db

    local f = CreateFrame("Frame", "KE_StanceTextDisplay", UIParent)
    f:SetSize(db.IconSize, db.IconSize)
    f:SetFrameStrata(db.Strata or "MEDIUM")

    -- AddBorders disables per-texture pixel snap; leave it off. Re-enabling it
    -- fights the grid maths and every repaint undoes it anyway.
    KE:AddBorders(f, db.BorderColor)

    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    KE:ApplyIconZoom(icon)
    f.icon = icon

    f.text = f:CreateFontString(nil, "OVERLAY")
    f.text:SetPoint("BOTTOM", f, "TOP", 0, 4)
    f.text:SetWordWrap(false)
    -- A FontString with no font THROWS on SetText, so the font is applied at
    -- creation and never conditionally.
    KE:ApplyFontToText(f.text, db.FontFace, db.FontSize, db.FontOutline)

    f:Hide()
    self.frame = f
    KE:ApplyFramePosition(f, db.Position, db)
end

-- The whole feature: is the current spec in the form it should be in.
function ST:Update()
    local db = self.db
    if not db or not db.Enabled then
        if self.frame then self.frame:Hide() end
        return
    end
    if self.previewing then return end

    local specID, entry = SpecEntry()
    evalContext.inCombat = InCombatLockdown()
    evalContext.currentFormSpell = CurrentFormSpell()
    local shown = self:EvaluateSpec(db, specID, entry, evalContext)

    if not shown then
        if self.frame then self.frame:Hide() end
        return
    end

    self:CreateFrame()
    local f = self.frame
    if not f then return end

    -- The icon is the form being HELD only when Show Current Form is on for
    -- this spec and there is a form to show. With no form at all the fallback
    -- draws the wanted one, which is still a "missing", not a "wrong".
    local current = evalContext.currentFormSpell
    local wrongForm = db[tostring(specID) .. "ReverseIcon"] and current ~= nil and shown == current

    f:SetSize(db.IconSize, db.IconSize)
    f.icon:SetTexture(C_Spell.GetSpellTexture(shown))
    f:SetAlpha(db.Alpha or 1)
    self:ApplyText(db, wrongForm)
    f:Show()
end

-- The "MISSING" caption above the icon.
-- wrongForm says the icon on screen is the form the player IS in, not the one
-- they are missing, so the caption has to say the opposite thing. Showing
-- "MISSING" over the stance you are currently holding reads as a bug.
function ST:ApplyText(db, wrongForm)
    local f = self.frame
    if not f or not f.text then return end
    -- Hidden rather than blanked: nothing to write, nothing to go wrong.
    if not db.ShowText then
        f.text:Hide()
        return
    end
    local text, fallback
    if wrongForm then
        text, fallback = db.TextWrong, WRONG_TEXT_DEFAULT
    else
        text, fallback = db.Text, MISSING_TEXT_DEFAULT
    end
    KE:ApplyFontToText(f.text, db.FontFace, db.FontSize, db.FontOutline)
    f.text:SetTextColor(unpack(db.TextColor))
    f.text:SetText(text and text ~= "" and text or fallback)
    f.text:Show()
end

function ST:ApplySettings()
    if not self:IsEnabled() then return end
    self:UpdateDB()
    if self.frame then
        self.frame:SetFrameStrata(self.db.Strata or "MEDIUM")
        KE:ApplyFramePosition(self.frame, self.db.Position, self.db)
    end
    self:Update()
end

function ST:OnEnable()
    self:UpdateDB()
    if not self.db.Enabled then return end
    self:CreateFrame()

    -- Entirely event-driven -- nothing polls. Form changes are the only thing
    -- that can change the answer, plus the combat transitions that the per-spec
    -- CombatOnly option depends on. UNIT_AURA is deliberately absent: no spec
    -- reads auras, and in restricted content it arrives with a secret unit and
    -- would be discarded anyway. Putting a spec back on the aura check means
    -- registering it again here.
    self:RegisterEvent("UPDATE_SHAPESHIFT_FORM", "Update")
    self:RegisterEvent("UPDATE_SHAPESHIFT_FORMS", "Update")
    self:RegisterEvent("PLAYER_REGEN_DISABLED", "Update")
    self:RegisterEvent("PLAYER_REGEN_ENABLED", "Update")
    self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", "Update")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "Update")
    self:RegisterEvent("PLAYER_ALIVE", "Update")
    self:Update()

    if not self.frame or not KE.EditMode then return end
    KE.EditMode:RegisterElement({
        key = "StanceText",
        module = self,
        displayName = "Missing Forms",
        frame = self.frame,
        getPosition = function() return self.db.Position end,
        setPosition = function(pos)
            self.db.Position = pos
            KE:ApplyFramePosition(self.frame, self.db.Position, self.db)
        end,
        getParentFrame = function() return KE:ResolveAnchorFrame(self.db.anchorFrameType, self.db.ParentFrame) end,
        guiPath = "StatusTexts",
        guiTab = "StanceText",
    })
end

function ST:OnDisable()
    self:UnregisterEvent("UPDATE_SHAPESHIFT_FORM")
    self:UnregisterEvent("UPDATE_SHAPESHIFT_FORMS")
    self:UnregisterEvent("PLAYER_REGEN_DISABLED")
    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
    self:UnregisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    self:UnregisterEvent("PLAYER_ALIVE")
    if self.frame then self.frame:Hide() end
end

-- Preview (options page) -----------------------------------------------

function ST:ShowPreview()
    self:CreateFrame()
    if not self.frame then return end
    self.previewing = true
    local _, entry = SpecEntry()
    local spellID = entry and entry.spellID or 24858
    self.frame:SetSize(self.db.IconSize, self.db.IconSize)
    self.frame.icon:SetTexture(C_Spell.GetSpellTexture(spellID))
    self.frame:SetAlpha(self.db.Alpha or 1)
    self.frame:Show()
end

function ST:HidePreview()
    self.previewing = false
    self:Update()
end
