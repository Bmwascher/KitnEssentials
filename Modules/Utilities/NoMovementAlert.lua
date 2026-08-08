-- ╔══════════════════════════════════════════════════════════╗
-- ║  NoMovementAlert.lua                                     ║
-- ║  Module: No Movement Alert                               ║
-- ║  Purpose: Shows the current spec's mobility spells        ║
-- ║           counting down, so the gap-closer or escape      ║
-- ║           state is always on screen.                      ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class NoMovementAlert: AceModule, AceEvent-3.0
local NMA = KitnEssentials:NewModule("NoMovementAlert", "AceEvent-3.0")

-- Zero idle cost: no cooldown or aura events are registered at all until
-- the module is enabled, and the poll ticker only runs while at least one
-- tracked spell is actually on cooldown.
--
-- MAINTENANCE: the spell tables below are hardcoded ids and WILL drift with
-- talent and expansion changes. The user override list (db.Spells) is the
-- escape hatch: it can disable a preset, retext it, or add an id that never
-- shipped, so users self-correct without waiting on a build.

local C_Spell = C_Spell
local C_Timer = C_Timer
local UnitClass, UnitAffectingCombat = UnitClass, UnitAffectingCombat

------------------------------------------------------------------------
-- Data tables
------------------------------------------------------------------------
local MOVEMENT_ABILITIES = {
    DEATHKNIGHT = { [250] = { 48265, 212552 }, [251] = { 48265, 212552 }, [252] = { 48265, 444010, 444347, 212552 } },
    DEMONHUNTER = { [577] = { 195072 }, [581] = { 189110 }, [1480] = { 1234796 } },
    DRUID       = { [102] = { 102401, 252216, 1850, 102417 }, [103] = { 102401, 252216, 1850, 102417 }, [104] = { 102401, 252216, 106898, 1850, 102417 }, [105] = { 102401, 252216, 1850, 102417 } },
    EVOKER      = { [1467] = { 358267 }, [1468] = { 358267 }, [1473] = { 358267 } },
    HUNTER      = { [253] = { 186257, 781 }, [254] = { 186257, 781 }, [255] = { 186257, 781 } },
    MAGE        = { [62] = { 212653, 1953 }, [63] = { 212653, 1953 }, [64] = { 212653, 1953 } },
    MONK        = { [268] = { 115008, 109132, 119085, 361138 }, [269] = { 115008, 109132, 119085, 361138, 101545 }, [270] = { 115008, 109132, 119085, 361138 } },
    PALADIN     = { [65] = { 190784 }, [66] = { 190784 }, [70] = { 190784 } },
    PRIEST      = { [256] = { 121536, 73325 }, [257] = { 121536, 73325 }, [258] = { 121536, 73325 } },
    ROGUE       = { [259] = { 36554, 2983 }, [260] = { 195457, 2983 }, [261] = { 36554, 2983 } },
    SHAMAN      = { [262] = { 79206, 90328, 192063, 58875 }, [263] = { 90328, 192063, 58875 }, [264] = { 79206, 90328, 192063, 58875 } },
    WARLOCK     = { [265] = { 48020, 111400 }, [266] = { 48020, 111400 }, [267] = { 48020, 111400 } },
    WARRIOR     = { [71] = { 6544 }, [72] = { 6544 }, [73] = { 6544 } },
}

-- Aura-tracked: no cooldown to count down, so the aura being up IS the
-- state. Membership decides HOW a spell is tracked, never whether it is
-- on (Burning Rush ships unchecked via DEFAULT_OFF).
local BUFF_ACTIVE_SPELLS = {
    [111400] = "Burning Rush Active!",
}

-- Same ability under different form/talent IDs: any of them satisfies
-- the others' cooldown lookups.
local SPELL_ALIAS_GROUPS = {
    { 102401, 16979, 102417, 252216 },
    { 106898, 77761, 77764 },
}

-- Fallback durations for spells whose cooldown the API reports as 0
-- until first cast (charge/category oddities).
local SPELL_CATEGORY_DURATION = {
    [102401] = 15, [16979] = 15, [102417] = 15, [252216] = 15,
    [1850] = 18,
    [106898] = 120, [77761] = 120,
}

-- Presets that ship UNCHECKED: absence of an override means enabled,
-- except for these. Ticking the box writes an explicit enabled = true.
local DEFAULT_OFF = {
    [2983] = true,                    -- Sprint
    [73325] = true,                   -- Leap of Faith
    [106898] = true, [77761] = true, [77764] = true, -- Stampeding Roar
    [1850] = true,                    -- Dash
    [252216] = true,                  -- Tiger Dash
    [212552] = true,                  -- Wraith Walk
    [79206] = true,                   -- Spiritwalker's Grace
    [58875] = true, [90328] = true,   -- Spirit Walk
    [111400] = true,                  -- Burning Rush
}

KE.MOVEMENT_ABILITIES = MOVEMENT_ABILITIES
KE.MOVEMENT_BUFF_ACTIVE = BUFF_ACTIVE_SPELLS
KE.MOVEMENT_DEFAULT_OFF = DEFAULT_OFF

local ALIAS_MAP = {}
do
    for _, group in ipairs(SPELL_ALIAS_GROUPS) do
        for _, id in ipairs(group) do ALIAS_MAP[id] = group end
        for _, id in ipairs(group) do
            if not SPELL_CATEGORY_DURATION[id] then
                for _, other in ipairs(group) do
                    if SPELL_CATEGORY_DURATION[other] then
                        SPELL_CATEGORY_DURATION[id] = SPELL_CATEGORY_DURATION[other]
                        break
                    end
                end
            end
        end
    end
end

local function CategoryDuration(spellId)
    if SPELL_CATEGORY_DURATION[spellId] then return SPELL_CATEGORY_DURATION[spellId] end
    local group = ALIAS_MAP[spellId]
    if group then
        for _, id in ipairs(group) do
            if SPELL_CATEGORY_DURATION[id] then return SPELL_CATEGORY_DURATION[id] end
        end
    end
    return 0
end

------------------------------------------------------------------------
-- Secret-safe API wrappers (12.x returns secret values in some states;
-- KE:IsSecretValue is the house guard).
------------------------------------------------------------------------
-- Midnight makes cooldown numbers SECRET in combat. Discarding any secret
-- value and returning 0 would make every tracked spell read as "ready",
-- nothing would render, and the frame would hide itself for the rest of
-- the fight.
--
-- Secret values can be DISPLAYED, just never inspected: keep the secret
-- number, skip every comparison against it, and hand it to
-- SetFormattedText, which renders it without the addon ever reading it.
-- Same doctrine as Cursor.lua's SetCooldownFromDurationObject note --
-- never boolean-test a secret.
--
-- isOnGCD carries the whole answer, and it is three-valued rather than two:
--   false -- a real cooldown is running, so report it
--   true  -- the global cooldown only, so stay quiet
--   nil   -- nothing worth reporting: an idle spell
-- Only an explicit false renders. Reading nil as "cannot tell" and falling
-- through to the cooldown duration object instead is what put a one-second
-- countdown under an ability whose real cooldown is half a minute: that
-- object hands back a value whenever it is asked, including when the spell
-- is ready, and the value is secret so nothing about it can be checked.
--
-- This holds identically inside and outside addon restrictions. The field
-- tracks the cooldown, not the environment.
function NMA:ReadCooldown(spellId)
    if not (C_Spell and C_Spell.GetSpellCooldown) then return nil end
    local ok, info = pcall(C_Spell.GetSpellCooldown, spellId)
    if not ok or type(info) ~= "table" then return nil end

    if info.isOnGCD ~= false then return nil end

    local rem = info.timeUntilEndOfStartRecovery
    if rem == nil and C_Spell.GetSpellCooldownDuration then
        local duration = C_Spell.GetSpellCooldownDuration(spellId)
        if duration then
            local okD, r = pcall(duration.GetRemainingDuration, duration)
            if okD then rem = r end
        end
    end
    if rem == nil then return nil end

    if KE:IsSecretValue(rem) then return rem, nil, true end
    if rem > 0 then return rem, info.duration, false end
    return nil
end

-- Threshold gate: nothing is shown until its countdown drops under this many
-- seconds. Returns nil when the gate is off, so every caller can treat nil as
-- "no limit" rather than testing the pair of settings itself.
function NMA:ThresholdSeconds()
    local db = self.db
    if not db or not db.MaxRemainingEnabled then return nil end
    local seconds = db.MaxRemaining
    if type(seconds) ~= "number" or seconds <= 0 then return nil end
    return seconds
end

-- Alpha curve for the gate, rebuilt only when the threshold changes: the
-- evaluation below runs for every gated line on every tick.
function NMA:ThresholdCurve(seconds)
    if not (C_CurveUtil and C_CurveUtil.CreateCurve and Enum and Enum.LuaCurveType) then
        return nil
    end
    if self.thresholdCurveFor ~= seconds then
        local curve = C_CurveUtil.CreateCurve()
        curve:SetType(Enum.LuaCurveType.Step)
        curve:AddPoint(0, 1)
        curve:AddPoint(seconds, 1)
        curve:AddPoint(seconds + 0.001, 0)
        self.thresholdCurve, self.thresholdCurveFor = curve, seconds
    end
    return self.thresholdCurve
end

-- The gate for a cooldown whose remaining time cannot be read. Inside addon
-- restrictions that number is secret, so the comparison happens in the client:
-- the duration object is evaluated against the curve and hands back an alpha,
-- itself secret, which is legal in an alpha sink and nowhere else. A hidden
-- line still occupies its row -- knowing to skip the row would mean reading
-- the very value the client is withholding.
function NMA:ThresholdAlpha(spellId, seconds)
    local curve = self:ThresholdCurve(seconds)
    if not curve or not (C_Spell and C_Spell.GetSpellCooldownDuration) then return nil end
    local ok, duration = pcall(C_Spell.GetSpellCooldownDuration, spellId)
    if not ok or not duration then return nil end
    local okE, alpha = pcall(duration.EvaluateRemainingDuration, duration, curve)
    if not okE then return nil end
    return alpha
end

local function SafeCharges(spellId)
    if not (C_Spell and C_Spell.GetSpellCharges) then return nil end
    local ok, info = pcall(C_Spell.GetSpellCharges, spellId)
    if not ok or type(info) ~= "table" then return nil end
    if KE:IsSecretValue(info.currentCharges) or KE:IsSecretValue(info.maxCharges) then return nil end
    return info
end

-- One call covers what the two removed globals computed between them:
-- known, or present in the player's spell book including overrides. Those
-- globals now only exist behind a deprecation CVar and are going away.
local function SpellKnown(spellId)
    if not (C_SpellBook and C_SpellBook.IsSpellKnownOrInSpellBook) then return false end
    local ok, known = pcall(C_SpellBook.IsSpellKnownOrInSpellBook, spellId,
        Enum.SpellBookSpellBank.Player, true)
    return ok and known == true
end

local function SpellInfo(spellId)
    if not (C_Spell and C_Spell.GetSpellInfo) then return nil end
    local ok, info = pcall(C_Spell.GetSpellInfo, spellId)
    if ok and type(info) == "table" and info.name then return info end
    return nil
end

-- Choice nodes: one talent replaces another, so the player can only ever have
-- one of the pair. Both IDs still read as KNOWN -- the base is learned from
-- levelling and never stops being known, and known-ness is asked with
-- overrides included -- and their names differ, so neither SpellKnown nor the
-- name dedupe separates them, and both render as two rows counting the same
-- cooldown.
--
-- Asking the API which one is live does not work: an override resolver either
-- misfires on unrelated spells or, once narrowed to spells the player does
-- not have, never fires at all for a baseline spell like Dash. The
-- relationships are a fixed three-entry list; stating them is exact and costs
-- nothing.
--
-- MOST SPECIFIC FIRST: the talent that replaces, then the one it replaces.
local EXCLUSIVE_GROUPS = {
    { 252216, 1850 },   -- Tiger Dash replaces Dash
    { 212653, 1953 },   -- Shimmer replaces Blink
    { 115008, 109132 }, -- Chi Torpedo replaces Roll
}
local EXCLUSIVE_OF = {}
for _, group in ipairs(EXCLUSIVE_GROUPS) do
    for _, id in ipairs(group) do EXCLUSIVE_OF[id] = group end
end

-- True when a MORE SPECIFIC member of this spell's group is known: that is
-- the one the player actually has, so this one is the replaced half. Order
-- within the group is the priority, so this holds whichever way round the
-- list is written.
local function ReplacedByKnownChoice(spellId)
    local group = EXCLUSIVE_OF[spellId]
    if not group then return false end
    for _, other in ipairs(group) do
        if other == spellId then return false end
        if SpellKnown(other) then return true end
    end
    return false
end

------------------------------------------------------------------------
-- Effective enable state: an explicit saved override wins, otherwise
-- absence means enabled unless the preset is default-off.
------------------------------------------------------------------------
-- Overrides are PER SPEC. Keys are "specID:spellID"; the bare "spellID"
-- key is the older account-wide form and is still read as a fallback so
-- existing choices survive, but new writes are per spec. A spell that
-- appears in several specs (Wild Charge, Dash) can now be tracked on
-- Feral and ignored on Balance.
local function SpellKey(specId, spellId)
    return tostring(specId or 0) .. ":" .. tostring(spellId)
end

local function SpellEnabled(db, spellId, specId)
    local spells = db.Spells
    if spells then
        local o = specId and spells[SpellKey(specId, spellId)]
        if o and o.enabled ~= nil then return o.enabled ~= false end
        local legacy = spells[tostring(spellId)]
        if legacy and legacy.enabled ~= nil then return legacy.enabled ~= false end
    end
    return not DEFAULT_OFF[spellId]
end

local function SpellCustomText(db, spellId, specId)
    local spells = db.Spells
    if spells then
        local o = specId and spells[SpellKey(specId, spellId)]
        if not (o and o.customText and o.customText ~= "") then
            o = spells[tostring(spellId)]
        end
        if o and o.customText and o.customText ~= "" then return o.customText end
    end
    return BUFF_ACTIVE_SPELLS[spellId]
end
KE.MOVEMENT_SPELL_KEY = SpellKey

-- Thin accessors over the two file-local resolvers, so the rules can be tested
-- without the frames and the cooldown APIs around them.
function NMA:IsSpellEnabled(db, spellId, specId)
    return SpellEnabled(db, spellId, specId)
end

function NMA:GetCategoryDuration(spellId)
    return CategoryDuration(spellId)
end

function NMA:IsReplacedChoice(spellId)
    return ReplacedByKnownChoice(spellId)
end

------------------------------------------------------------------------
-- Display frame + pooled slots
------------------------------------------------------------------------
function NMA:UpdateDB()
    self.db = KE.db.profile.NoMovementAlert
end

function NMA:OnInitialize()
    self:UpdateDB()
    self.slots = {}
    self.tracked = {}
    self.auraActive = {}
    self.glowing = {}
    -- Charge counts are SECRET in combat, so a live read there returns
    -- nothing and the spell falls through to the plain-cooldown path --
    -- which for a charge spell sitting on charges is zero, hence
    -- "Infernal Strike - 0". Remember what was learned while the values
    -- were readable and maintain it through cast events instead.
    --   chargeMeta[spellId] = { max, recharge }  -- learned when readable
    --   chargeCount[spellId] = last known count  -- kept current in combat
    self.chargeMeta = {}
    self.chargeCount = {}
    self.chargeTimers = {}
    self.isPreview = false
    self:SetEnabledState(false)
end

function NMA:CreateFrame_()
    if self.frame then return end
    local frame = CreateFrame("Frame", "KE_MovementAlert", UIParent)
    frame:SetSize(220, 40)
    frame:Hide()
    self.frame = frame
end

function NMA:GetSlot(index)
    local slot = self.slots[index]
    if slot then return slot end

    slot = CreateFrame("Frame", nil, self.frame)
    slot:SetSize(220, 30)

    slot.text = slot:CreateFontString(nil, "OVERLAY")
    slot.text:SetPoint("CENTER")

    self.slots[index] = slot
    -- Style BEFORE returning: callers (Update/ShowPreview) write text into
    -- a fresh slot before LayoutSlots gets to style it, and a FontString
    -- with no font set throws "Font not set" on SetText.
    self:StyleSlot(slot)
    return slot
end

-- One colour for every part in theme mode, the three saved ones otherwise.
-- Every read of a colour goes through here so the mode cannot be honoured in
-- one place and forgotten in another.
function NMA:RoleColor(key)
    local db = self.db
    if db.ColorMode == "THEME" then
        local accent = KE.Theme and KE.Theme.accent
        if accent then return accent end
    end
    return db[key] or db.TextColor
end

function NMA:StyleSlot(slot)
    local face, size, outline = self:EffectiveStyle()
    local c = self:RoleColor("TextColor")
    KE:ApplyFontToText(slot.text, face, size, outline)
    slot.text:SetTextColor(c[1], c[2], c[3], c[4] or 1)
    slot:SetSize(220, size + 6)
    -- Opaque by default so a slot reused from a threshold-hidden line comes
    -- back visible. Update re-applies the hidden alpha after it lays out.
    slot:SetAlpha(1)
end

function NMA:LayoutSlots(count)
    local db = self.db
    local _, _, _, effSpacing = self:EffectiveStyle()
    local spacing = effSpacing or db.Spacing or 2
    local prev
    local w, h = 0, 0
    for i = 1, count do
        local slot = self:GetSlot(i)
        self:StyleSlot(slot)
        slot:ClearAllPoints()
        if db.GrowDirection == "RIGHT" or db.GrowDirection == "LEFT" then
            local side = db.GrowDirection == "RIGHT" and "LEFT" or "RIGHT"
            local opp = db.GrowDirection == "RIGHT" and "RIGHT" or "LEFT"
            if prev then
                slot:SetPoint(side, prev, opp, db.GrowDirection == "RIGHT" and spacing or -spacing, 0)
            else
                slot:SetPoint(side, self.frame, side, 0, 0)
            end
            w = w + slot:GetWidth() + spacing
            h = math.max(h, slot:GetHeight())
        else
            local side = db.GrowDirection == "UP" and "BOTTOM" or "TOP"
            local opp = db.GrowDirection == "UP" and "TOP" or "BOTTOM"
            if prev then
                slot:SetPoint(side, prev, opp, 0, db.GrowDirection == "UP" and spacing or -spacing)
            else
                slot:SetPoint(side, self.frame, side, 0, 0)
            end
            h = h + slot:GetHeight() + spacing
            w = math.max(w, slot:GetWidth())
        end
        slot:Show()
        prev = slot
    end
    for i = count + 1, #self.slots do
        self.slots[i]:Hide()
    end
    if count > 0 then
        self.frame:SetSize(math.max(w, 1), math.max(h, 1))
    end
end

------------------------------------------------------------------------
-- Tracked spell resolution
------------------------------------------------------------------------
function NMA:ResolveSpecId()
    if not GetSpecialization then return nil end
    local idx = GetSpecialization()
    if not idx or idx == 0 then return nil end
    local id = GetSpecializationInfo and GetSpecializationInfo(idx)
    return id
end

function NMA:BuildTracked()
    local db = self.db
    local out = {}
    local _, class = UnitClass("player")
    local specId = self:ResolveSpecId()

    local seen, seenName = {}, {}
    local function add(spellId)
        if seen[spellId] then return end
        if not SpellEnabled(db, spellId, specId) then return end
        if not SpellKnown(spellId) then return end
        if ReplacedByKnownChoice(spellId) then return end
        local info = SpellInfo(spellId)
        if not info then return end
        -- Every Druid spec lists Wild Charge twice -- the base ID and the
        -- Travel form variant -- and in Travel Form both are known, so both
        -- passed and rendered as two identical rows. Deduping on the resolved
        -- name rather than the alias group is deliberate: 252216 (Tiger Dash)
        -- shares Wild Charge's alias group for cooldown purposes, and
        -- claiming the whole group would have hidden it whenever both were
        -- talented. Same name means the player sees the same ability twice;
        -- different names are different abilities.
        if seenName[info.name] then return end

        seen[spellId] = true
        seenName[info.name] = true
        -- Learn charge shape while the values are readable; the resolver
        -- falls back to this in combat.
        self:ResolveCharges(spellId)
        out[#out + 1] = {
            spellId = spellId,
            name = info.name,
            icon = info.iconID,
            customText = SpellCustomText(db, spellId, specId),
            isBuffActive = BUFF_ACTIVE_SPELLS[spellId] ~= nil,
            baseDuration = CategoryDuration(spellId),
        }
    end

    if class and specId and MOVEMENT_ABILITIES[class] and MOVEMENT_ABILITIES[class][specId] then
        for _, spellId in ipairs(MOVEMENT_ABILITIES[class][specId]) do add(spellId) end
    end

    -- User-added IDs (the drift escape hatch). Anything with an explicit
    -- enabled = true that is not already a preset for this spec.
    -- User-added IDs (the drift escape hatch). Accept a bare legacy key
    -- or one scoped to the spec we are actually in.
    if db.Spells then
        for key, o in pairs(db.Spells) do
            if o and o.enabled == true then
                local scoped, id = key:match("^(%d+):(%d+)$")
                if id then
                    if tonumber(scoped) == specId then add(tonumber(id)) end
                else
                    local bare = tonumber(key)
                    if bare then add(bare) end
                end
            end
        end
    end

    self.tracked = out
    return out
end

------------------------------------------------------------------------
-- Update loop -- ticker runs ONLY while something is counting down
------------------------------------------------------------------------
-- Decimals ONLY below one second -- a ticking tenths place at 8.4s is
-- noise, at 0.4s it is information.
local function FormatTime(remaining)
    if remaining >= 60 then
        return string.format("%d:%02d", remaining / 60, remaining % 60)
    elseif remaining >= 1 then
        return string.format("%d", remaining)
    end
    return string.format("%.1f", remaining)
end

-- "Roll - 12" rather than "Roll  12" -- a separator plus its own colour
-- for the countdown, so the eye lands on the number. Colours are
-- hex-wrapped rather than two FontStrings so the whole line stays a
-- single centred string that the bar/icon modes can ignore.
local function Hex(c)
    return string.format("%02x%02x%02x",
        math.floor((c[1] or 1) * 255 + 0.5),
        math.floor((c[2] or 1) * 255 + 0.5),
        math.floor((c[3] or 1) * 255 + 0.5))
end

-- Colour-wrapped line with a printf slot for the time, so a secret
-- number can be rendered via SetFormattedText without being read.
function NMA:ComposeFormat(name, numberFmt)
    local db = self.db
    local sep = db.Separator
    if sep == nil or sep == "" then sep = "-" end
    -- Built by concatenation, NOT string.format: the returned string is
    -- itself a format string whose number slot must survive untouched
    -- for SetFormattedText. Running it through format here consumed that
    -- slot and threw "bad argument to 'format'".
    -- Any literal % in a name or separator is escaped for the same
    -- reason -- it would otherwise be read as a specifier downstream.
    local function esc(s) return (tostring(s):gsub("%%", "%%%%")) end
    return "|cff" .. Hex(self:RoleColor("TextColor")) .. esc(name) .. "|r "
        .. "|cff" .. Hex(self:RoleColor("SeparatorColor")) .. esc(sep) .. "|r "
        .. "|cff" .. Hex(self:RoleColor("TimerColor")) .. numberFmt .. "|r"
end

function NMA:ComposeLine(name, timeText)
    local db = self.db
    local nameHex = Hex(self:RoleColor("TextColor"))
    if not timeText then
        return string.format("|cff%s%s|r", nameHex, name)
    end
    local timeHex = Hex(self:RoleColor("TimerColor"))
    local sep = db.Separator
    if sep == nil or sep == "" then sep = "-" end
    return string.format("|cff%s%s|r |cff%s%s|r |cff%s%s|r",
        nameHex, name, Hex(self:RoleColor("SeparatorColor")), sep, timeHex, timeText)
end

-- Truth when the client will give it, memory when it will not.
function NMA:ResolveCharges(spellId)
    local info = SafeCharges(spellId)
    if info and info.maxCharges and info.maxCharges > 1 then
        self.chargeMeta[spellId] = {
            max = info.maxCharges,
            recharge = info.cooldownDuration or 0,
        }
        self.chargeCount[spellId] = info.currentCharges or 0
        return self.chargeCount[spellId], true
    end
    local meta = self.chargeMeta[spellId]
    if meta then
        -- Known charge spell, count currently unreadable: use the value
        -- we have been maintaining rather than guessing zero.
        return self.chargeCount[spellId] or meta.max, true
    end
    return nil, false
end

-- Casting a tracked charge spell spends one; schedule the refund at its
-- recharge duration. Any readable poll overwrites all of this with truth.
function NMA:OnTrackedCast(_, unit, _, spellId)
    if KE:IsSecretValue(unit) or unit ~= "player" then return end
    if not spellId then return end

    local meta = self.chargeMeta[spellId]
    if not meta then return end

    local left = (self.chargeCount[spellId] or meta.max) - 1
    if left < 0 then left = 0 end
    self.chargeCount[spellId] = left

    local delay = meta.recharge
    if not delay or delay <= 0 then delay = nil end
    if delay then
        self.chargeTimers[spellId] = self.chargeTimers[spellId] or {}
        local t = C_Timer.NewTimer(delay, function()
            local c = (self.chargeCount[spellId] or 0) + 1
            if c > meta.max then c = meta.max end
            self.chargeCount[spellId] = c
            if self:IsEnabled() then self:Update() end
        end)
        table.insert(self.chargeTimers[spellId], t)
    end
    self:Update()
    self:StartTicker()
end

function NMA:CancelChargeTimers()
    for _, list in pairs(self.chargeTimers or {}) do
        for _, t in ipairs(list) do if t and t.Cancel then t:Cancel() end end
    end
    self.chargeTimers = {}
end

function NMA:StartTicker()
    if self.ticker then return end
    self.ticker = C_Timer.NewTicker(0.1, function() self:Update() end)
end

function NMA:StopTicker()
    if self.ticker then
        self.ticker:Cancel()
        self.ticker = nil
    end
end

function NMA:Update()
    if self.isPreview then return end
    local db = self.db
    if not db or not db.Enabled or not self.frame then return end

    if db.HideOutOfCombat and not UnitAffectingCombat("player") then
        self.frame:Hide()
        self:StopTicker()
        return
    end

    local shown, anyRunning = 0, false
    local threshold = self:ThresholdSeconds()
    -- Alphas are applied after LayoutSlots, which restyles every slot and
    -- resets alpha as it goes.
    local alphas = self.slotAlphas or {}
    self.slotAlphas = alphas
    wipe(alphas)

    for _, entry in ipairs(self.tracked) do
        -- Secret-safe render contract: `secretValue` means "show this,
        -- never look at it". Text lines are therefore emitted either as
        -- a plain SetText (safe values) or a SetFormattedText with the
        -- secret number as an argument (never compared, never formatted
        -- by us).
        local plainLine, fmtLine, fmtValue, lineAlpha

        if entry.isBuffActive then
            if self.auraActive[entry.spellId] then
                plainLine = self:ComposeLine(entry.customText or entry.name, nil)
            end
        else
            local chargesLeft, isChargeSpell = self:ResolveCharges(entry.spellId)

            -- No usability gate: IsSpellUsable reports only learned status and
            -- resources -- per its own docs -- and returns TRUE for a spell
            -- sitting on cooldown, so gating on it would hide every countdown.
            -- The charge rule is enforced just below instead.
            local rem, _, isSecret = self:ReadCooldown(entry.spellId)

            -- A charge spell with a charge still banked is NOT unavailable.
            -- isOnGCD does not filter the recharge out, so spending one of two
            -- charges put a countdown on screen for an ability the player
            -- could still use. chargesLeft is a plain number even in combat --
            -- SafeCharges refuses secret counts and ResolveCharges falls back
            -- to the count it maintains -- so this comparison is safe.
            if isChargeSpell and chargesLeft and chargesLeft > 0 then
                rem, isSecret = nil, nil
            end

            if isSecret then
                anyRunning = true
                self.readyFired = self.readyFired or {}
                self.readyFired[entry.spellId] = true
                if rem ~= nil then
                    fmtLine = self:ComposeFormat(entry.customText or entry.name, "%.0f")
                    fmtValue = rem
                    if threshold then
                        lineAlpha = self:ThresholdAlpha(entry.spellId, threshold)
                    end
                else
                    plainLine = self:ComposeLine(entry.customText or entry.name, "...")
                end
            elseif rem then
                anyRunning = true
                self.readyFired = self.readyFired or {}
                self.readyFired[entry.spellId] = true
                -- Readable remaining time, so the gate drops the line outright
                -- and the row goes with it. anyRunning above is what keeps the
                -- ticker alive to bring it back when the countdown comes down.
                if not (threshold and rem > threshold) then
                    plainLine = self:ComposeLine(entry.customText or entry.name, FormatTime(rem))
                end
            else
                if self.readyFired and self.readyFired[entry.spellId] then
                    self.readyFired[entry.spellId] = nil
                    if db.SoundEnabled and db.Sound and db.Sound ~= "None" and KE.LSM then
                        local path = KE.LSM:Fetch("sound", db.Sound, true)
                        if path then pcall(PlaySoundFile, path, "Master") end
                    end
                end
                if db.ShowWhenReady then
                    local suffix = chargesLeft and chargesLeft > 0 and ("x" .. chargesLeft) or nil
                    plainLine = self:ComposeLine(entry.customText or entry.name, suffix)
                end
            end
        end

        if plainLine or fmtLine then
            shown = shown + 1
            local text = self:GetSlot(shown).text
            if fmtLine then
                text:SetFormattedText(fmtLine, fmtValue)
            else
                text:SetText(plainLine)
            end
            alphas[shown] = lineAlpha
        end
    end

    if shown > 0 then
        self:LayoutSlots(shown)
        for i = 1, shown do
            if alphas[i] ~= nil then self.slots[i]:SetAlpha(alphas[i]) end
        end
        self:ApplyPosition()
        self.frame:Show()
    else
        self.frame:Hide()
    end

    -- While attached, this slot in the stack moves as Combat Texts
    -- messages come and go. The ticker only runs while something is
    -- counting down -- exactly when this is visible -- so re-seating here
    -- costs nothing when idle and keeps formation when not.
    if not anyRunning then self:StopTicker() end
end

function NMA:Refresh()
    if self.isPreview then return end
    self:BuildTracked()
    -- Tracked list just changed, so the glow cache and buff states are
    -- re-derived for the new set rather than carried over.
    self:SeedGlowState()
    self:RefreshBuffStates()
    self:Update()
    self:StartTicker()
end

-- Display-only refresh for the high-frequency cooldown/charge/usable events.
--
-- Those events change what a tracked spell is DOING, never which spells are
-- tracked -- that set only moves on spec, talent, knowledge and settings
-- changes, which have their own handlers. Running the full Refresh here meant
-- BuildTracked allocating a fresh table per tracked spell, plus two dedupe
-- tables and a closure, several times a second in combat; SPELL_UPDATE_USABLE
-- alone fires on every resource change. That allocation churn is what the
-- garbage collector pauses on, and the pause is what is felt as stutter.
--
-- Update() reads live cooldown state per entry itself, so refreshing the
-- display and making sure the ticker is running is the entire job here.
--
-- Rate-capped with a trailing flush so a burst of events costs one pass rather
-- than one per event. The cap matches the ticker's own 0.1s period, so nothing
-- is displayed later than it already would have been. The flush closure is
-- allocated once at load, not once per event (same reason as the UNIT_AURA
-- debounce in AuraExternals.lua).
local DISPLAY_REFRESH_CAP = 0.1

local flushDisplayRefresh = function()
    NMA._displayCapped = false
    if NMA._displayPending then
        NMA._displayPending = false
        NMA:RefreshDisplay()
    end
end

function NMA:RefreshDisplay()
    if self.isPreview then return end
    if self._displayCapped then
        self._displayPending = true
        return
    end
    self._displayCapped = true
    self:Update()
    self:StartTicker()
    C_Timer.After(DISPLAY_REFRESH_CAP, flushDisplayRefresh)
end

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------
-- Buff-active spells were previously detected ONLY by
-- C_UnitAuras.GetPlayerAuraBySpellID. Midnight hides many buffs from the
-- player's aura scan, so that returns nil while the effect is genuinely
-- active -- InnervateTracker.lua documents the same thing. It is not M+
-- specific: plain combat is restricted too.
--
-- Fallback is the spell-activation overlay glow. Burning Rush glows while
-- it is toggled on, and the glow events are not aura reads, so they keep
-- working where the aura scan does not:
--
--   SPELL_ACTIVATION_OVERLAY_GLOW_SHOW / _HIDE  -- live changes
--   C_SpellActivationOverlay.IsSpellOverlayed   -- state on login/zone
--
-- The aura read stays primary; the glow is consulted only while the scan
-- is returning nothing.
function NMA:SeedGlowState()
    local overlayed = C_SpellActivationOverlay and C_SpellActivationOverlay.IsSpellOverlayed
    if not overlayed then return end

    for _, entry in ipairs(self.tracked) do
        if entry.isBuffActive then
            local ok, on = pcall(overlayed, entry.spellId)
            self.glowing[entry.spellId] = (ok and on) or nil
        end
    end
end

function NMA:OnGlowShow(_, spellId)
    if not spellId or not BUFF_ACTIVE_SPELLS[spellId] then return end
    self.glowing[spellId] = true
    if self:RefreshBuffStates() then self:Update() end
end

function NMA:OnGlowHide(_, spellId)
    if not spellId or not BUFF_ACTIVE_SPELLS[spellId] then return end
    self.glowing[spellId] = nil
    if self:RefreshBuffStates() then self:Update() end
end

function NMA:ReadBuffActive(entry)
    local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, entry.spellId)
    if ok and aura then return true end
    if ok and self.auraScanTrusted then return false end

    return self.glowing[entry.spellId] and true or false
end

function NMA:RefreshBuffStates()
    local changed = false
    for _, entry in ipairs(self.tracked) do
        if entry.isBuffActive then
            local active = self:ReadBuffActive(entry)
            if self.auraActive[entry.spellId] ~= active then
                self.auraActive[entry.spellId] = active
                changed = true
            end
        end
    end
    return changed
end

function NMA:OnAura(_, unit)
    if KE:IsSecretValue(unit) or unit ~= "player" then return end

    -- One confirmed aura read proves the scan works in this context;
    -- from then on it is authoritative and the cast fallback is inert.
    if not self.auraScanTrusted then
        for _, entry in ipairs(self.tracked) do
            if entry.isBuffActive then
                local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, entry.spellId)
                if ok and aura then self.auraScanTrusted = true break end
            end
        end
    end

    if self:RefreshBuffStates() then self:Update() end
end

-- Death ends these buffs and the glow with them; re-read rather than
-- assume, since IsSpellOverlayed is authoritative.
function NMA:ClearBuffFallback()
    self.glowing = {}
    self.auraScanTrusted = nil
    self:SeedGlowState()
    if self:RefreshBuffStates() then self:Update() end
end

-- Optional attach to the Combat Texts stack. Combat Texts owns
-- KE_CombatTextsContainer, whose height ArrangeMessages() recomputes
-- every time a message shows or hides -- so anchoring our TOP to its
-- BOTTOM makes the alerts genuinely flow underneath its messages rather
-- than just sitting near them, and one anchor moves both. Works for all
-- three display modes; no coupling into Combat Texts' message pooling.
-- Falls back to our own Position whenever Combat Texts is off or its
-- container does not exist yet.
function NMA:GetCombatTextsContainer()
    local cm = KitnEssentials and KitnEssentials:GetModule("CombatTexts", true)
    if not cm or not cm.container then return nil end
    if not (cm.db and cm.db.Enabled) then return nil end
    return cm.container
end

-- Height the visible Combat Texts messages actually occupy, using that
-- module's own frames and spacing. Zero when nothing is shown.
function NMA:CombatTextsUsedHeight()
    local cm = KitnEssentials and KitnEssentials:GetModule("CombatTexts", true)
    if not (cm and cm.messageFrames) then return 0 end
    local spacing = (cm.db and cm.db.Spacing) or 4
    local used = 0
    for _, f in pairs(cm.messageFrames) do
        if f and f.IsShown and f:IsShown() then
            used = used + (f:GetHeight() or 0) + spacing
        end
    end
    return used
end

function NMA:IsAttached()
    return self.db and self.db.AttachToCombatTexts and self:GetCombatTextsContainer() ~= nil
end

-- Attached means "be a Combat Texts line" -- font face/size/outline and
-- the stack spacing come from that module, so the alerts match the
-- messages they sit under instead of drifting from them. The matching
-- GUI rows are hidden while attached for the same reason.
function NMA:EffectiveStyle()
    local db = self.db
    if self:IsAttached() then
        local cm = KitnEssentials:GetModule("CombatTexts", true)
        local c = cm and cm.db
        if c then
            return c.FontFace or db.FontFace, c.FontSize or db.FontSize,
                   c.FontOutline or db.FontOutline, c.Spacing or db.Spacing, 1
        end
    end
    return db.FontFace, db.FontSize, db.FontOutline, db.Spacing, db.Scale or 1
end

function NMA:ApplyPosition()
    local db, frame = self.db, self.frame
    if not frame or not db then return end
    frame:ClearAllPoints()

    local container = db.AttachToCombatTexts and self:GetCombatTextsContainer()
    if container then
        -- Take the NEXT SLOT in the Combat Texts stack, not a position
        -- under the container. Its container keeps a 30px minimum height
        -- even with nothing shown (ArrangeMessages: max(30, ...)), so
        -- anchoring to BOTTOM would leave a phantom row of empty space.
        -- Measuring the actually-visible message frames instead means: no
        -- messages up -> sit exactly where the first one would; messages
        -- up -> sit directly after them, at their own spacing.
        frame:SetPoint("TOP", container, "TOP", 0, -self:CombatTextsUsedHeight())
    else
        KE:ApplyFramePosition(frame, db.Position, db)
    end
    local _, _, _, _, scale = self:EffectiveStyle()
    frame:SetScale(scale)
end

function NMA:ApplySettings()
    self:UpdateDB()
    if self.db and self.db.Enabled then
        if not self:IsEnabled() then
            KitnEssentials:EnableModule("NoMovementAlert")
        elseif self.isPreview then
            -- Refresh/Update both early-out while previewing, so
            -- font/spacing/colour edits would silently do nothing on the
            -- preview -- the one place the user is actually looking.
            -- Repaint the preview instead.
            self:ShowPreview()
        else
            self:ApplyPosition()
            self:Refresh()
        end
    elseif self:IsEnabled() then
        KitnEssentials:DisableModule("NoMovementAlert")
    end
end

local EDIT_MODE_ELEMENT = {
    key = "NoMovementAlert",
    displayName = "No Movement Alert",
    guiPath = "NoMovementAlert",
}

function NMA:RegisterAnchor()
    -- Attached to Combat Texts: that module owns the anchor, so a second
    -- draggable overlay for the same spot would fight it.
    if self:IsAttached() then
        KE.EditMode:UnregisterElement("NoMovementAlert")
        self.editModeRegistered = nil
        self.editModeFrame = nil
        return
    end
    -- Enable and every preview show both land here. Re-registering the same
    -- frame would cancel a drag in progress for nothing. A rebuilt frame still
    -- re-registers, because the stored handle no longer matches.
    if self.editModeRegistered and self.editModeFrame == self.frame then return end

    local cfg = {}
    for k, v in pairs(EDIT_MODE_ELEMENT) do cfg[k] = v end
    cfg.frame = self.frame
    cfg.module = self
    cfg.getPosition = function() return self.db.Position end
    cfg.setPosition = function(pos)
        local p = self.db.Position
        p.AnchorFrom, p.AnchorTo = pos.AnchorFrom, pos.AnchorTo
        p.XOffset, p.YOffset = pos.XOffset, pos.YOffset
        self:ApplyPosition()
    end
    KE.EditMode:RegisterElement(cfg)
    self.editModeRegistered = true
    self.editModeFrame = self.frame
end

function NMA:OnEnable()
    self:UpdateDB()
    self:CreateFrame_()
    self:ApplyPosition()

    -- Display-only + rate-capped: these fire many times a second in combat and
    -- never change which spells are tracked. See RefreshDisplay.
    self:RegisterEvent("SPELL_UPDATE_COOLDOWN", "RefreshDisplay")
    self:RegisterEvent("SPELL_UPDATE_CHARGES", "RefreshDisplay")
    self:RegisterEvent("SPELL_UPDATE_USABLE", "RefreshDisplay")
    self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", "OnSpecChanged")
    self:RegisterEvent("PLAYER_TALENT_UPDATE", "OnSpecChanged")
    self:RegisterEvent("TRAIT_CONFIG_UPDATED", "OnSpecChanged")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnSpecChanged")
    self:RegisterEvent("PLAYER_REGEN_DISABLED", "Refresh")
    self:RegisterEvent("PLAYER_REGEN_ENABLED", "Refresh")
    -- While attached, Combat Texts' container height changes as its
    -- messages come and go; combat transitions are when that happens, and
    -- Refresh -> Update -> ApplyPosition re-seats this underneath.
    self:RegisterEvent("UNIT_AURA", "OnAura")
    self:RegisterEvent("PLAYER_DEAD", "ClearBuffFallback")
    self:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", "OnGlowShow")
    self:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", "OnGlowHide")
    self:SeedGlowState()
    self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", "OnTrackedCast")

    self:BuildTracked()
    self:Update()
    self:RegisterAnchor()
end

function NMA:OnSpecChanged()
    -- Zoning ends these buffs, and whether the aura scan works differs
    -- between the open world and instanced content -- so the fallback
    -- state and the "scan is trustworthy" verdict both reset here.
    self.glowing = {}
    self.auraScanTrusted = nil

    -- Talent/spec state is not reliable immediately on these events.
    C_Timer.After(2, function()
        if self:IsEnabled() then self:Refresh() end
    end)
end

function NMA:OnDisable()
    self:UnregisterAllEvents()
    self:CancelChargeTimers()
    self:StopTicker()
    if self.frame then self.frame:Hide() end
    self.tracked = {}
    self.auraActive = {}
    self.readyFired = nil
    self.isPreview = false
    KE.EditMode:UnregisterElement("NoMovementAlert")
end

------------------------------------------------------------------------
-- Preview (PreviewManager contract)
------------------------------------------------------------------------
function NMA:ShowPreview()
    self:UpdateDB()
    self:CreateFrame_()
    self.isPreview = true
    self:StopTicker()

    local db = self.db
    local samples = { { name = "Roll", remain = 12 }, { name = "Tiger's Lust", remain = 0.4 } }
    local count = math.min(#samples, math.max(1, db.PreviewCount or 2))
    for i = 1, count do
        local s = samples[i]
        self:GetSlot(i).text:SetText(self:ComposeLine(s.name, FormatTime(s.remain)))
    end
    self:LayoutSlots(count)
    self:ApplyPosition()
    self.frame:Show()
    self:RegisterAnchor()
end

function NMA:HidePreview()
    self.isPreview = false
    if not self.frame then return end
    if self.db and self.db.Enabled and self:IsEnabled() then
        self:Refresh()
    else
        self.frame:Hide()
        KE.EditMode:UnregisterElement("NoMovementAlert")
    end
end
