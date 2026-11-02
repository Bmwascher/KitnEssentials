-- ╔══════════════════════════════════════════════════════════╗
-- ║  PotionReady.lua                                         ║
-- ║  Module: Combat Potion Ready                             ║
-- ║  Purpose: Shows "Potion Ready" text when a combat        ║
-- ║           potion is in bags and off cooldown. Respects   ║
-- ║           instance, combat, and healer visibility.       ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class PotionReady: AceModule, AceEvent-3.0
local PR = KitnEssentials:NewModule("PotionReady", "AceEvent-3.0")

local C_Item           = C_Item
local C_Container      = C_Container
local C_Timer          = C_Timer
local CreateFrame      = CreateFrame
local IsInInstance     = IsInInstance
local UIParent         = UIParent
local GetTime          = GetTime
local GetCombatRating  = GetCombatRating
local math_floor       = math.floor
local math_huge        = math.huge
local math_max         = math.max
local pcall, type      = pcall, type
local tostring         = tostring

local ATTACH_KEY = "potionReady"
local DETACHED_HEIGHT = 30

---------------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------------
local POTION_IDS = {
    -- Regular potions
    241308, 241309,                 -- Light's Potential (Gold, Silver)
    241288, 241289,                 -- Potion of Recklessness (Gold, Silver)
    241292, 241293,                 -- Draught of Rampant Abandon (Gold, Silver)
    241300, 241301,                 -- Lightfused Mana Potion (Gold, Silver)
    241294, 241295,                 -- Potion of Devoured Dreams (Gold, Silver)
    241302, 241303,                 -- Void-Shrouded Tincture (Gold, Silver)
    -- Fleeting potions
    245898, 245897,                 -- Fleeting Light's Potential (Gold, Silver)
    245902, 245903,                 -- Fleeting Potion of Recklessness (Gold, Silver)
    245910, 245911,                 -- Fleeting Draught of Rampant Abandon (Gold, Silver)
    245916, 245917,                 -- Fleeting Lightfused Mana Potion (Gold, Silver)
    245904, 245905,                 -- Fleeting Potion of Devoured Dreams (Gold, Silver)
}

-- Every Forever combat potion shares one cooldown, so one held potion
-- answers for all of them.
if KE.IS_FOREVER then
    POTION_IDS = KE.CombatDataForever and KE.CombatDataForever.POTION_IDS or {}
end

-- Retail: the gold, silver and fleeting copies of one potion, for the icon's
-- count. The Recklessness family answers the stat.
local POTION_FAMILIES = {
    { 241308, 241309, 245898, 245897 },   -- Light's Potential
    { 241288, 241289, 245902, 245903 },   -- Potion of Recklessness
    { 241292, 241293, 245910, 245911 },   -- Draught of Rampant Abandon
    { 241300, 241301, 245916, 245917 },   -- Lightfused Mana Potion
    { 241294, 241295, 245904, 245905 },   -- Potion of Devoured Dreams
    { 241302, 241303 },                   -- Void-Shrouded Tincture
}
local RECK_FAMILY = POTION_FAMILIES[2]
local FAMILY_OF = {}
for _, family in ipairs(POTION_FAMILIES) do
    for _, id in ipairs(family) do FAMILY_OF[id] = family end
end

-- In Icon mode the stat comes back this many seconds before the potion is ready.
local STAT_LEAD = 10
local STAT_COALESCE = 0.1
-- The Text mode stat line, as a share of the text size.
local TEXT_STAT_SCALE = 0.8
local PREVIEW_ICON_ITEM = 241288
local QUESTION_MARK = "Interface\\Icons\\INV_Misc_QuestionMark"
-- CR_CRIT_MELEE, CR_HASTE_MELEE, CR_MASTERY, CR_VERSATILITY_DAMAGE_DONE.
local STAT_RATINGS = { 9, 18, 26, 29 }
local STAT_KEYS = { "crit", "haste", "mastery", "vers" }
local STAT_NAMES = { "Crit", "Haste", "Mastery", "Vers" }

-- The label's point, the icon's point and the offset for a Stat Position;
-- anything unknown sits above. Returned, not tabled: a mixed table types
-- every cell as string or number, which SetPoint rejects.
---@param position string?
---@return "TOP"|"BOTTOM"|"LEFT"|"RIGHT" point
---@return "TOP"|"BOTTOM"|"LEFT"|"RIGHT" relativePoint
---@return number offsetX
---@return number offsetY
local function StatAnchor(position)
    if position == "BELOW" then return "TOP", "BOTTOM", 0, -2 end
    if position == "LEFT" then return "RIGHT", "LEFT", -4, 0 end
    if position == "RIGHT" then return "LEFT", "RIGHT", 4, 0 end
    return "BOTTOM", "TOP", 0, 2
end

---------------------------------------------------------------------------------
-- Module State
---------------------------------------------------------------------------------
PR.frame    = nil
PR.text     = nil
PR.isPreview          = false
PR.editModeRegistered = false
PR.inCombat           = false
PR.inInstance         = false
PR._listening         = false
-- Forever: the first listed potion in the bags, looked up again only after
-- a bag change.
PR.heldPotion         = nil
PR.heldDirty          = true
-- Retail: the laid-out mode, the potion the icon shows and its family count
-- (looked up again after a bag change), and the Recklessness stat's state.
PR.layoutMode         = "text"
PR.attached           = false
PR.lineSize           = 20
PR.picture            = nil
PR.firstHeld          = nil
PR.reckHeldID         = nil
PR.iconCount          = 0
PR.iconParts          = nil
PR.statLabels         = nil
PR.statSize           = nil
PR.statWanted         = false
PR.statPreview        = false
-- The measure generation a queued measure belongs to; nil when none is queued.
PR.statQueuedGen      = nil
PR.statValues         = {}
PR.statEventFrame     = nil
PR.measureGeneration  = 0
PR.wakeGeneration     = 0
PR.wakeKey            = nil

---------------------------------------------------------------------------------
-- DB Helper
---------------------------------------------------------------------------------
function PR:UpdateDB()
    self.db = KE.db.profile.PotionReady
end

---------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------
local function HasPotion(id)
    local count = C_Item.GetItemCount(id, false, false, true)
    return count and count > 0
end

local function IsPotionReady(id)
    local start, duration, enable = C_Container.GetItemCooldown(id)
    if not start or not enable then return false end
    return enable == 1 and (start == 0 or duration == 0)
end

-- Retail Text mode's rule: some held listed potion is ready.
local function AnyListedReady()
    for _, id in ipairs(POTION_IDS) do
        if HasPotion(id) and IsPotionReady(id) then return true end
    end
    return false
end

-- When id's cooldown ends: 0 when ready, math.huge while it is not counting.
local function CooldownEnd(id)
    local start, duration, enable = C_Container.GetItemCooldown(id)
    if not start or not enable then return math_huge end
    if enable ~= 1 then return math_huge end
    if start == 0 or duration == 0 then return 0 end
    return start + duration
end

-- Forever keeps today's text display and never shows the stat.
local function Mode(db)
    if KE.IS_FOREVER or not db or db.DisplayMode ~= "icon" then return "text" end
    return "icon"
end

local function StatOn(db)
    return not KE.IS_FOREVER and db ~= nil and db.ReckStat ~= nil and db.ReckStat.Enabled == true
end

-- A saved color, else the Secondary Stats hue for that stat.
local function StatColor(rs, i)
    local c = rs.Colors and rs.Colors[STAT_KEYS[i]]
    if type(c) == "table" then return c[1] or 1, c[2] or 1, c[3] or 1 end
    local hex = KE.SecondaryStatHex and KE.SecondaryStatHex[STAT_KEYS[i]]
    if hex then
        local color = KE:CreateColor(hex)
        return color.r, color.g, color.b
    end
    return 1, 1, 1
end

---------------------------------------------------------------------------------
-- Visibility Checks
---------------------------------------------------------------------------------
-- Pure, so the rule is spec-covered; the caller supplies the three reads.
function PR.PassesGates(db, inInstance, inCombat, isHealer)
    if db.InstanceOnly and not inInstance then return false end
    if db.CombatOnly and not inCombat then return false end
    if db.DisableOnHealer and isHealer then return false end
    return true
end

-- Pure, so the rule is spec-covered. ready is the shown potion's; the
-- Recklessness cooldown alone decides the stat, which Text mode shows only
-- when that potion is ready and Icon mode from STAT_LEAD seconds before.
function PR.ResolveDisplay(mode, gatesPass, held, ready, reckHeld, reckLeft, onlyWhileReady, statOn, specOn)
    local shown
    if mode == "icon" then
        shown = gatesPass and held and (ready or not onlyWhileReady)
    else
        shown = gatesPass and ready
    end
    shown = shown == true
    local lead = mode == "icon" and STAT_LEAD or 0
    local stat = shown and statOn and specOn and reckHeld
        and type(reckLeft) == "number" and reckLeft <= lead
    return shown, stat == true
end

function PR:PassesVisibility()
    local db = self.db
    return PR.PassesGates(db, self.inInstance, self.inCombat, db.DisableOnHealer and KE:IsPlayerHealerSpec())
end

-- The cooldown and bag events only matter while the text may show. Only
-- CheckPotions turns them off, because it hides the text in the same call;
-- anywhere else, onlyOn keeps them until then, so the text hides on the same
-- event it always did.
function PR:SyncListening(onlyOn)
    local want = (self:IsEnabled() and self.db and self.db.Enabled and self:PassesVisibility())
        and true or false
    if want == self._listening then return end
    if onlyOn and not want then return end
    self._listening = want
    if want then
        -- Bag changes were not heard while off.
        self.heldDirty = true
        self:RegisterEvent("BAG_UPDATE_DELAYED", "BAG_UPDATE_DELAYED")
        self:RegisterEvent("SPELL_UPDATE_COOLDOWN", "SPELL_UPDATE_COOLDOWN")
    else
        self:UnregisterEvent("BAG_UPDATE_DELAYED")
        self:UnregisterEvent("SPELL_UPDATE_COOLDOWN")
    end
end

---------------------------------------------------------------------------------
-- Core Logic
---------------------------------------------------------------------------------
-- Every show and hide of the text goes through here, so an attached text's
-- place in the Combat Texts stack follows it.
function PR:SetTextShown(shown)
    if not self.frame then return end
    if shown then self.frame:Show() else self.frame:Hide() end
    local cm = KitnEssentials:GetModule("CombatTexts", true)
    if cm then cm:AttachedFrameChanged(ATTACH_KEY) end
end

function PR:CheckPotions()
    if not self.frame then return end
    self:SyncListening()
    if self.isPreview then return end
    if not self:PassesVisibility() then
        self:SetStatWanted(false)
        self:SetTextShown(false)
        return
    end

    if KE.IS_FOREVER then
        if self.heldDirty then
            self.heldPotion = nil
            for _, id in ipairs(POTION_IDS) do
                if HasPotion(id) then
                    self.heldPotion = id
                    break
                end
            end
            self.heldDirty = false
        end
        self:SetTextShown(self.heldPotion ~= nil and IsPotionReady(self.heldPotion))
        return
    end

    local mode, statOn = Mode(self.db), StatOn(self.db)
    if mode == "text" and not statOn then
        self:SetStatWanted(false)
        self:SetTextShown(AnyListedReady())
        return
    end
    self:CheckDisplay(mode, statOn)
end

-- Retail, with the stat on or in Icon mode. The bag scan runs again only
-- after a bag change; readiness is read every time.
function PR:CheckDisplay(mode, statOn)
    local db = self.db
    if self.heldDirty then
        self.firstHeld, self.reckHeldID, self.iconCount = nil, nil, 0
        for _, id in ipairs(POTION_IDS) do
            if HasPotion(id) then
                self.firstHeld = self.firstHeld or id
                if FAMILY_OF[id] == RECK_FAMILY then self.reckHeldID = self.reckHeldID or id end
            end
        end
        self.picture = self.reckHeldID or self.firstHeld
        if self.picture then
            for _, id in ipairs(FAMILY_OF[self.picture] or { self.picture }) do
                self.iconCount = self.iconCount + (C_Item.GetItemCount(id, false, false, true) or 0)
            end
        end
        self.heldDirty = false
    end

    local ready
    if mode == "icon" then
        ready = self.picture ~= nil and IsPotionReady(self.picture)
    else
        ready = AnyListedReady()
    end

    local reckEnd, reckLeft = nil, math_huge
    if self.reckHeldID then
        reckEnd = CooldownEnd(self.reckHeldID)
        reckLeft = reckEnd == 0 and 0 or math_max(0, reckEnd - GetTime())
    end
    local specOn = KE:IsSpecEnabled(db.ReckStat and db.ReckStat.EnabledSpecs, KE:GetPlayerSpecId())
    local shown, statWanted = PR.ResolveDisplay(mode, true, self.picture ~= nil, ready,
        self.reckHeldID ~= nil, reckLeft, db.OnlyWhileReady == true, statOn, specOn)

    if mode == "icon" then self:PaintIcon() end
    self:SetTextShown(shown)
    self:SetStatWanted(statWanted)
    if mode == "icon" and shown and statOn and specOn and reckEnd and reckEnd ~= math_huge
        and reckLeft > STAT_LEAD then
        self:ArmWake(reckEnd, reckLeft - STAT_LEAD + 0.05)
    end
end

-- One wake per cooldown, keyed on its end: it brings the stat in STAT_LEAD
-- seconds before the potion is ready, a moment no event marks.
function PR:ArmWake(key, delay)
    if self.wakeKey == key then return end
    self.wakeKey = key
    self.wakeGeneration = self.wakeGeneration + 1
    local myGeneration = self.wakeGeneration
    C_Timer.After(delay, function()
        if myGeneration ~= self.wakeGeneration then return end
        self.wakeKey = nil
        if self:IsEnabled() and self.db and self.db.Enabled then self:CheckPotions() end
    end)
end

function PR:PaintIcon()
    local parts = self.iconParts
    if not parts then return end
    local picture = self.picture
    if parts.shownPicture ~= picture then
        parts.shownPicture = picture
        parts.tex:SetTexture(picture and C_Item.GetItemIconByID(picture) or QUESTION_MARK)
    end
    if parts.countValue ~= self.iconCount then
        parts.countValue = self.iconCount
        parts.count:SetText(tostring(self.iconCount))
    end
    local start, duration = 0, 0
    if picture and self.db.ShowCooldown ~= false then
        local s, d, enable = C_Container.GetItemCooldown(picture)
        if s and d and enable == 1 and d > 0 then start, duration = s, d end
    end
    if parts.cdStart ~= start or parts.cdDuration ~= duration then
        parts.cdStart, parts.cdDuration = start, duration
        if duration > 0 then
            parts.cooldown:SetCooldown(start, duration)
        else
            parts.cooldown:Clear()
        end
    end
end

---------------------------------------------------------------------------------
-- Recklessness Stat
---------------------------------------------------------------------------------
function PR:ShowStat(winner)
    local labels = self.statLabels
    if not labels then return end
    for i = 1, 4 do labels[i]:SetAlpha(i == winner and 1 or 0) end
end

-- Ratings are read only while the stat is wanted.
function PR:SetStatWanted(on)
    on = on == true and self.statLabels ~= nil
    if on == self.statWanted then return end
    self.statWanted = on
    if on then
        self:SyncStatEvents(true)
        self:QueueMeasure()
    else
        self:SyncStatEvents(false)
        self.measureGeneration = self.measureGeneration + 1
        if KE.RatingCompare then KE.RatingCompare.Cancel() end
        self:ShowStat(nil)
    end
    if self.layoutMode == "text" then self:FitTextFrame() end
end

function PR:SyncStatEvents(on)
    if on then
        if not self.statEventFrame then
            local f = CreateFrame("Frame")
            f:SetScript("OnEvent", function() self:QueueMeasure() end)
            self.statEventFrame = f
        end
        local f = self.statEventFrame
        f:RegisterUnitEvent("UNIT_AURA", "player")
        f:RegisterEvent("COMBAT_RATING_UPDATE")
        f:RegisterEvent("MASTERY_UPDATE")
        f:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
        f:RegisterEvent("TRAIT_CONFIG_UPDATED")
    elseif self.statEventFrame then
        self.statEventFrame:UnregisterAllEvents()
    end
end

-- Procs move ratings many times a second; one measure per STAT_COALESCE.
-- A queued measure belongs to its generation, so turning the stat off and
-- on again queues a fresh one instead of waiting on the canceled one.
function PR:QueueMeasure()
    if not self.statWanted or self.statQueuedGen == self.measureGeneration then return end
    local myGeneration = self.measureGeneration
    self.statQueuedGen = myGeneration
    C_Timer.After(STAT_COALESCE, function()
        if self.statQueuedGen == myGeneration then self.statQueuedGen = nil end
        if myGeneration ~= self.measureGeneration or not self.statWanted then return end
        self:Measure()
    end)
end

-- Plain ratings take the plain pick. Secret ones go to the game-side
-- compare, whose alphas show only the winner. A failed read hides the stat.
-- Every measure cancels the compare before it, so an older answer that is
-- still settling never paints over this one.
function PR:Measure()
    local labels, RC = self.statLabels, KE.RatingCompare
    if not labels or not RC then return end
    RC.Cancel()
    -- Settings can change without a cooldown or bag event (a profile switch).
    if not self:IsEnabled() or not StatOn(self.db) then
        self:SetStatWanted(false)
        return
    end
    local values, secret = self.statValues, false
    for i = 1, 4 do
        local ok, v = pcall(GetCombatRating, STAT_RATINGS[i])
        if not ok then
            self:ShowStat(nil)
            return
        end
        if KE:IsSecretValue(v) then
            secret = true
        elseif type(v) ~= "number" then
            self:ShowStat(nil)
            return
        end
        values[i] = v
    end
    if not secret then
        self:ShowStat(RC.PlainPick(values))
        return
    end
    local myGeneration = self.measureGeneration
    RC.Compare(values, function(ok, alphas)
        if myGeneration ~= self.measureGeneration or not self.statWanted then return end
        if not ok then
            self:ShowStat(nil)
            return
        end
        for i = 1, 4 do labels[i]:SetAlpha(alphas[i]) end
    end)
end

---------------------------------------------------------------------------------
-- Retail Layout
---------------------------------------------------------------------------------
function PR:EnsureIconParts()
    if self.iconParts then return self.iconParts end
    local holder = CreateFrame("Frame", nil, self.frame)
    holder:SetAllPoints(self.frame)
    local tex = holder:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints(holder)
    KE:ApplyIconZoom(tex)
    KE:AddIconBorders(holder)
    local cooldown = CreateFrame("Cooldown", nil, holder, "CooldownFrameTemplate")
    cooldown:SetAllPoints(holder)
    cooldown:SetDrawEdge(false)
    cooldown:SetDrawBling(false)
    cooldown:SetHideCountdownNumbers(true)
    local overlay = CreateFrame("Frame", nil, holder)
    overlay:SetAllPoints(holder)
    overlay:SetFrameLevel(cooldown:GetFrameLevel() + 1)
    local count = overlay:CreateFontString(nil, "OVERLAY")
    count:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", -2, 2)
    KE:ApplyFontToText(count, self.db.FontFace, self.db.CountSize or 12, self.db.FontOutline)
    self.iconParts = { holder = holder, tex = tex, cooldown = cooldown, count = count }
    return self.iconParts
end

-- One label per stat at one anchor; only the winner is visible.
function PR:EnsureStatLabels()
    if self.statLabels then return self.statLabels end
    local labels = {}
    for i = 1, 4 do
        local fs = self.frame:CreateFontString(nil, "OVERLAY")
        KE:ApplyFontToText(fs, self.db.FontFace, 14, self.db.FontOutline)
        fs:SetAlpha(0)
        labels[i] = fs
    end
    self.statLabels = labels
    return labels
end

function PR:LayoutStat(mode, face, outline, size)
    local labels, rs = self.statLabels, self.db.ReckStat or {}
    if not labels then return end
    local statSize
    if mode == "icon" then
        statSize = rs.FontSize or 14
    else
        statSize = math_max(8, math_floor(size * TEXT_STAT_SCALE + 0.5))
    end
    self.statSize = statSize
    local prefix = ""
    if rs.ShowPrefix ~= false and type(rs.Prefix) == "string" and rs.Prefix ~= "" then
        local c = rs.PrefixColor or { 1, 1, 1, 1 }
        prefix = KE:WrapColor(rs.Prefix, c[1], c[2], c[3]) .. " "
    end
    local point, relativePoint, offsetX, offsetY = StatAnchor(rs.Position)
    for i = 1, 4 do
        local fs = labels[i]
        KE:ApplyFontToText(fs, face, statSize, outline)
        fs:ClearAllPoints()
        if mode == "icon" then
            fs:SetPoint(point, self.frame, relativePoint, offsetX, offsetY)
        else
            fs:SetPoint("TOP", self.text, "BOTTOM", 0, -2)
        end
        local r, g, b = StatColor(rs, i)
        fs:SetText(prefix .. KE:WrapColor(STAT_NAMES[i], r, g, b))
    end
end

-- Attached, the frame holds both lines so the stack makes room for the
-- stat; the text keeps its own line at the top.
function PR:FitTextFrame()
    local f, t = self.frame, self.text
    if not f or not t then return end
    local both = self.attached and (self.statWanted or self.statPreview) and self.statSize ~= nil
    local line = self.attached and (self.lineSize + 2) or DETACHED_HEIGHT
    t:ClearAllPoints()
    if both then
        f:SetHeight(line + self.statSize + 2)
        t:SetPoint("CENTER", f, "TOP", 0, -line / 2)
    else
        f:SetHeight(line)
        t:SetPoint("CENTER", f, "CENTER", 0, 0)
    end
    if self.attached then
        local cm = KitnEssentials:GetModule("CombatTexts", true)
        if cm then cm:AttachedFrameChanged(ATTACH_KEY) end
    end
end

-- Sample content, no reads: the Recklessness icon with a count of 3, and
-- Haste as the stat while it is on.
function PR:PaintPreview()
    self:SetStatWanted(false)
    local parts = self.iconParts
    if self.layoutMode == "icon" and parts then
        parts.shownPicture = PREVIEW_ICON_ITEM
        parts.tex:SetTexture(C_Item.GetItemIconByID(PREVIEW_ICON_ITEM) or QUESTION_MARK)
        parts.countValue = nil
        parts.count:SetText("3")
        parts.cdStart, parts.cdDuration = 0, 0
        parts.cooldown:Clear()
    end
    self.statPreview = StatOn(self.db) and self.statLabels ~= nil
    self:ShowStat(self.statPreview and 2 or nil)
    if self.layoutMode == "text" then self:FitTextFrame() end
end

-- Retail only: lays out the chosen mode, and the stat labels while the stat is on.
function PR:ApplyLayout(attached, face, outline, size)
    local db = self.db
    local mode = Mode(db)
    self.layoutMode, self.attached, self.lineSize = mode, attached == true, size
    if mode == "icon" then
        local parts = self:EnsureIconParts()
        self.frame:SetSize(db.IconWidth or 40, db.IconHeight or 40)
        KE:ApplyFramePosition(self.frame, db.Position, db)
        self.text:Hide()
        parts.holder:Show()
        KE:ApplyFontToText(parts.count, db.FontFace, db.CountSize or 12, db.FontOutline)
        if db.ShowCount ~= false then parts.count:Show() else parts.count:Hide() end
        parts.shownPicture, parts.countValue, parts.cdStart = false, nil, nil
    else
        self.frame:SetWidth(200)
        self.text:Show()
        if self.iconParts then self.iconParts.holder:Hide() end
    end
    if StatOn(db) then
        self:EnsureStatLabels()
        self:LayoutStat(mode, face, outline, size)
    end
    if mode == "text" then self:FitTextFrame() end
    if self.isPreview then
        self:PaintPreview()
    elseif self:IsEnabled() and db.Enabled then
        -- A profile switch reaches this module through ApplySettings alone, so
        -- the display and the stat's reads are settled here, not on the next event.
        self:CheckPotions()
    else
        self:SetStatWanted(false)
    end
end

---------------------------------------------------------------------------------
-- Frame Creation
---------------------------------------------------------------------------------
function PR:CreateFrame()
    if self.frame then return end

    local f = CreateFrame("Frame", "KE_PotionReady", UIParent)
    f:SetSize(200, DETACHED_HEIGHT)
    f:Hide()

    local t = f:CreateFontString(nil, "OVERLAY")
    t:SetPoint("CENTER", f, "CENTER", 0, 0)

    self.frame = f
    self.text  = t
    -- Attached, the login anchor pass must not put the text back on its own
    -- Player Frame position.
    KE:RegisterAnchorRepair(f, function()
        return not self:IsAttached() and self.db.anchorFrameType == "PLAYERFRAME"
    end, function() self:ApplySettings() end)
end

---------------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------------
function PR:IsAttached()
    if Mode(self.db) == "icon" then return false end
    local cm = KitnEssentials:GetModule("CombatTexts", true)
    return cm ~= nil and cm:TakesAttached(ATTACH_KEY, self.frame, self.db.AttachToCombatTexts == true)
end

-- Attached, the text is a Combat Texts row: that module's face and outline,
-- the resolved size, and the line height Combat Texts gives its own rows.
-- Only an active module takes a slot: the page applies settings to a kept
-- frame while the module is off.
function PR:ApplySettings()
    if not self.frame or not self.text then return end
    local db = self.db
    local cm = KitnEssentials:GetModule("CombatTexts", true)
    local attached = (self:IsEnabled() or self.isPreview) and cm ~= nil and self:IsAttached()

    local face, outline, size = db.FontFace, db.FontOutline, db.FontSize
    if attached and cm then
        face, outline = cm.db.FontFace, cm.db.FontOutline
        size = cm.ResolveAttachedSize(true, db.AttachOwnFontSize, db.FontSize, cm.db.FontSize)
    end
    KE:ApplyFontToText(self.text, face, size, outline)

    local r, g, b, a = KE:GetAccentColor(db.ColorMode, db.Color)
    self.text:SetTextColor(r, g, b, a)
    self.text:SetText(db.Text or "Potion Ready")

    self.frame:SetFrameStrata(db.Strata or "HIGH")
    if attached and cm then
        self.frame:SetHeight(size + 2)
        attached = cm:SetAttachedFrame(ATTACH_KEY, self.frame)
    end
    if not attached then
        if cm then cm:SetAttachedFrame(ATTACH_KEY, nil) end
        self.frame:SetHeight(DETACHED_HEIGHT)
        KE:ApplyFramePosition(self.frame, db.Position, db)
    end
    if not KE.IS_FOREVER then self:ApplyLayout(attached, face, outline, size) end
    if cm then cm:SyncAttachSubscription(self, self:IsEnabled() or self.isPreview) end
    if self:IsEnabled() or self.isPreview then self:RegWithEditMode() end

    -- A profile switch reaches this module here only; a gate it opens needs
    -- the events on for the next cooldown or bag change.
    self:SyncListening(true)
end

---------------------------------------------------------------------------------
-- Edit Mode
---------------------------------------------------------------------------------
function PR:RegWithEditMode()
    if not KE.EditMode then return end
    -- Attached, the Combat Texts mover moves the text; a second mover for it
    -- would fight that one.
    if self:IsAttached() then
        if self.editModeRegistered then
            KE.EditMode:UnregisterElement("PotionReady")
            self.editModeRegistered = false
        end
        return
    end
    if not self.editModeRegistered then
        KE.EditMode:RegisterElement({
            key         = "PotionReady",
            module      = self,
            displayName = "Combat Potion Ready",
            frame       = self.frame,
            getPosition = function() return self.db.Position end,
            setPosition = function(pos)
                self.db.Position = pos
                KE:ApplyFramePosition(self.frame, self.db.Position, self.db)
            end,
            getParentFrame = function()
                return KE:ResolveAnchorFrame(self.db.anchorFrameType, self.db.ParentFrame)
            end,
            -- No sidebar row of its own -- this lives on the Status Texts
            -- page, so guiTab picks its tab there.
            guiPath = "StatusTexts",
            guiTab = "PotionReady",
        })
        self.editModeRegistered = true
    end
end

---------------------------------------------------------------------------------
-- Preview
---------------------------------------------------------------------------------
function PR:ShowPreview()
    if not self.frame then self:CreateFrame() end
    self:RegWithEditMode()
    self.isPreview = true
    self:ApplySettings()
    self.text:SetText(self.db.Text or "Potion Ready")
    self:SetTextShown(true)
end

function PR:HidePreview()
    self.isPreview = false
    if self.statPreview then
        self.statPreview = false
        self:ShowStat(nil)
        if self.layoutMode == "text" then self:FitTextFrame() end
    end
    local cm = KitnEssentials:GetModule("CombatTexts", true)
    if cm then cm:SyncAttachSubscription(self, self:IsEnabled()) end
    if self.db and self.db.Enabled and self.frame then
        self:CheckPotions()
    elseif self.frame then
        self:SetTextShown(false)
    end
end

---------------------------------------------------------------------------------
-- Event Handlers
---------------------------------------------------------------------------------
function PR:PLAYER_ENTERING_WORLD()
    local inInstance = IsInInstance()
    self.inInstance = inInstance == true
    -- At once rather than with the delayed check: a cooldown event inside that
    -- second repaints the text.
    self:SyncListening(true)
    C_Timer.After(1, function()
        if self.db and self.db.Enabled then self:CheckPotions() end
    end)
end

function PR:ZONE_CHANGED_NEW_AREA()
    local inInstance = IsInInstance()
    self.inInstance = inInstance == true
    self:CheckPotions()
end

function PR:BAG_UPDATE_DELAYED()
    self.heldDirty = true
    self:CheckPotions()
end

function PR:SPELL_UPDATE_COOLDOWN()
    if self.isPreview then return end
    self:CheckPotions()
end

-- Combat changes whether ratings read secret, and a spec change moves them;
-- QueueMeasure does nothing while the stat is not wanted.
function PR:PLAYER_REGEN_DISABLED()
    self.inCombat = true
    self:CheckPotions()
    self:QueueMeasure()
end

function PR:PLAYER_REGEN_ENABLED()
    self.inCombat = false
    self:CheckPotions()
    self:QueueMeasure()
end

-- The event fires for every group member; only the player's spec decides.
function PR:PLAYER_SPECIALIZATION_CHANGED(_, unit)
    if unit ~= "player" then return end
    self:CheckPotions()
    self:QueueMeasure()
end

---------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------
function PR:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

function PR:OnEnable()
    if not self.db or not self.db.Enabled then return end

    self:CreateFrame()
    self:RegWithEditMode()

    C_Timer.After(0.5, function()
        if not self.db or not self.db.Enabled then return end
        self:ApplySettings()
        self:CheckPotions()
    end)

    self:RegisterEvent("PLAYER_ENTERING_WORLD",       "PLAYER_ENTERING_WORLD")
    self:RegisterEvent("ZONE_CHANGED_NEW_AREA",        "ZONE_CHANGED_NEW_AREA")
    self:RegisterEvent("PLAYER_REGEN_DISABLED",        "PLAYER_REGEN_DISABLED")
    self:RegisterEvent("PLAYER_REGEN_ENABLED",         "PLAYER_REGEN_ENABLED")
    self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED","PLAYER_SPECIALIZATION_CHANGED")
    -- The events that keep these fire only on a change, so a state already in
    -- place when the module comes on (a reload mid-fight, enabling inside an
    -- instance) is read here.
    self.inCombat = UnitAffectingCombat("player") and true or false
    self.inInstance = IsInInstance() == true
    self:SyncListening()
end

function PR:OnThemeChanged()
    if not self.db or not self.db.Enabled then return end
    if (self.db.ColorMode or "custom") == "theme" and self.text then
        local r, g, b, a = KE:GetAccentColor(self.db.ColorMode, self.db.Color)
        self.text:SetTextColor(r, g, b, a)
    end
end

function PR:OnDisable()
    self:UnregisterAllEvents()
    self:SetTextShown(false)
    local cm = KitnEssentials:GetModule("CombatTexts", true)
    if cm then
        cm:SetAttachedFrame(ATTACH_KEY, nil)
        cm:SyncAttachSubscription(self, false)
    end
    self.isPreview = false
    self.inCombat  = false
    self._listening = false
    self.statPreview = false
    self.wakeGeneration = self.wakeGeneration + 1
    self.wakeKey = nil
    self:SetStatWanted(false)
end
