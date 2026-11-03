-- ╔══════════════════════════════════════════════════════════╗
-- ║  ImminentDemise.lua                                      ║
-- ║  Module: Imminent Demise Counter                         ║
-- ║  Purpose: Counts Slayer's Strikes toward the next        ║
-- ║           Sudden Death from Imminent Demise.             ║
-- ║  Note: Warrior only; live while Imminent Demise is       ║
-- ║        known.                                            ║
-- ╚══════════════════════════════════════════════════════════╝
--
-- The game shows no count, so each strike is counted from its cooldown
-- event, and Execute lighting up with a strike sets a wrong count right.

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class ImminentDemise: AceModule, AceEvent-3.0
local ID = KitnEssentials:NewModule("ImminentDemise", "AceEvent-3.0")
-- Gates the preview manager.
ID.classRestriction = "WARRIOR"

local Rules = KE.ImminentDemiseRules
local Ask = KE.PlateSlots.Ask
local IsOwnSpecChange = KE.ShamanProcRules.IsOwnSpecChange

local CreateFrame = CreateFrame
local C_Timer = C_Timer
local GetTime = GetTime
local UnitClass = UnitClass
local issecretvalue = issecretvalue
local ipairs, pcall, tostring = ipairs, pcall, tostring
local math_max = math.max
local wipe = wipe

-- Flip to true, /reload, repro, read the log.
local DEBUG_ID = false

-- Talent state is not reliable on the frame a talent event fires.
local TALENT_EVAL_DELAY = 2
local COUNT_GAP = 6
-- Above the icon's cooldown swipe and countdown.
local ICON_LEVEL_OFFSET = 30
local VIEWER_ORDER = { "Essential", "Utility" }
local EMPTY_COLOR = { 0.06, 0.06, 0.06, 0.85 }

local function IsKnown(spellID)
    return Ask(C_SpellBook and C_SpellBook.IsSpellKnownOrInSpellBook, spellID)
end

local function ModeOf(db)
    local mode = db.DisplayMode
    if mode == "PIPS" or mode == "TEXT" then return mode end
    return "ICON"
end

local function TalentIcon()
    local getTexture = C_Spell and C_Spell.GetSpellTexture
    if getTexture then
        local ok, icon = pcall(getTexture, Rules.TALENT)
        if ok and not KE:IsSecretValue(icon) and icon then return icon end
    end
    return Rules.ICON
end

local function FindIcon()
    for _, key in ipairs(VIEWER_ORDER) do
        local icon = KE.CDMIcons.Find(key, Rules.CDM_IDS)
        if icon then return icon end
    end
    return nil
end

local function DeferredEvaluate()
    ID.evalTimer = nil
    if ID:IsEnabled() then ID:Evaluate() end
end

-- Runs inside Blizzard's refresh, before the re-dealt icons draw: the count
-- must not show for one frame on an icon now carrying another spell. The
-- stale flag keeps a strike before the next frame's search from showing it.
local function CheckIcon()
    local icon = ID.icon
    if not icon then return end
    local id = icon:GetCooldownID()
    if issecretvalue(id) or id == nil or id ~= ID.iconID then
        ID.iconStale = true
        ID.holder:Hide()
    end
end

local function Replace()
    if ID:WantsAttach() then ID:Place() end
end

local function EndTest()
    ID.testing, ID.testCount = false, nil
    wipe(ID.testTimers)
    if ID.resumePreview then
        ID.resumePreview = false
        ID:ShowPreview()
    else
        ID:ApplyLayout()
    end
end

---------------------------------------------------------------------------------
-- Setup
---------------------------------------------------------------------------------
function ID:UpdateDB()
    self.db = KE.db.profile.ImminentDemise
end

function ID:OnInitialize()
    self:UpdateDB()
    self.state = Rules.New()
    self.live, self.isPreview, self.resumePreview, self.testing = false, false, false, false
    self.watching, self.iconStale = false, false
    self.testTimers = {}
    -- Plain counters for the smoke probes.
    self.strikes, self.secretSeen, self.glows = 0, 0, 0
    self.matched, self.ghosts, self.fixes = 0, 0, 0
    self:SetEnabledState(false)
end

function ID:CreateFrames()
    if self.anchor then return end
    local anchor = CreateFrame("Frame", "KE_ImminentDemiseAnchor", UIParent)
    anchor:SetSize(1, 1)
    self.anchor = anchor
    KE:RegisterAnchorRepair(anchor, function()
        return self.db.anchorFrameType == "PLAYERFRAME"
    end, function() self:ApplyPosition() end)

    -- Mouse off, so the icon it may sit on keeps its tooltip.
    local holder = CreateFrame("Frame", "KE_ImminentDemise", anchor)
    holder:SetAllPoints(anchor)
    holder:EnableMouse(false)
    holder:Hide()
    self.holder = holder
    self.text = holder:CreateFontString(nil, "OVERLAY")
    self.text:SetPoint("CENTER", holder, "CENTER", 0, 0)
end

---------------------------------------------------------------------------------
-- Position and Edit Mode
---------------------------------------------------------------------------------
function ID:ApplyPosition()
    if not self.anchor then return end
    KE:ApplyFramePosition(self.anchor, self.db.Position, self.db)
end

function ID:AnchorElement()
    return {
        key = "ImminentDemise",
        displayName = Rules.LABEL,
        frame = self.anchor,
        module = self,
        guiPath = "ClassTools",
        guiTab = "ImminentDemise",
        getPosition = function() return self.db.Position end,
        getParentFrame = function()
            return KE:ResolveAnchorFrame(self.db.anchorFrameType, self.db.ParentFrame)
        end,
        setPosition = function(pos)
            local p = self.db.Position
            p.AnchorFrom, p.AnchorTo = pos.AnchorFrom, pos.AnchorTo
            p.XOffset, p.YOffset = pos.XOffset, pos.YOffset
            self:ApplyPosition()
        end,
    }
end

function ID:UnregisterAnchor()
    KE.EditMode:UnregisterElement("ImminentDemise")
    self.anchorRegistered, self.anchorMode = nil, nil
end

-- Registering the same frame again would cancel a drag in progress, so only
-- a mode change, which resizes the box, registers it again.
function ID:RegisterAnchor()
    if not self.anchor then return end
    if self.live or self.isPreview then
        local mode = ModeOf(self.db)
        if self.anchorRegistered and self.anchorMode ~= mode then self:UnregisterAnchor() end
        if not self.anchorRegistered then
            KE.EditMode:RegisterElement(self:AnchorElement())
            self.anchorRegistered, self.anchorMode = true, mode
        end
    else
        self:UnregisterAnchor()
    end
end

---------------------------------------------------------------------------------
-- Layout
---------------------------------------------------------------------------------
function ID:GetRoot(key)
    local root = self[key]
    if not root then
        root = CreateFrame("Frame", nil, self.holder)
        root:SetAllPoints(self.holder)
        root:Hide()
        self[key] = root
    end
    return root
end

function ID:LayoutIcon()
    local db = self.db
    local root = self:GetRoot("iconRoot")
    local ic = self.iconEl
    if not ic then
        ic = {}
        ic.tex = root:CreateTexture(nil, "ARTWORK")
        ic.tex:SetAllPoints(root)
        ic.tex:SetTexture(TalentIcon())
        KE:ApplyIconZoom(ic.tex)
        KE:AddIconBorders(root, { 0, 0, 0, 1 })
        ic.count = root:CreateFontString(nil, "OVERLAY")
        self.iconEl = ic
    end
    local size = db.IconSize or 40
    self.anchor:SetSize(size, size)
    KE:ApplyFontToText(ic.count, db.FontFace, db.FontSize or 20, db.FontOutline)
    local spot = Rules.SPOTS[db.CountPosition] or Rules.SPOTS.CENTER
    ic.count:ClearAllPoints()
    ic.count:SetPoint(spot[1], root, spot[2], spot[3] + (db.CountX or 0), spot[4] + (db.CountY or 0))
    root:Show()
end

function ID:LayoutPips()
    local db = self.db
    local root = self:GetRoot("pipsRoot")
    local pips = self.pips
    if not pips then
        pips = { segs = {} }
        -- Inset by the border, which sits on the segment and the fill would cover.
        local px = KE:GetPixelSize()
        for i = 1, Rules.TOTAL do
            local seg = CreateFrame("Frame", nil, root)
            local bg = seg:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints(seg)
            bg:SetColorTexture(EMPTY_COLOR[1], EMPTY_COLOR[2], EMPTY_COLOR[3], EMPTY_COLOR[4])
            seg.fill = seg:CreateTexture(nil, "ARTWORK")
            seg.fill:SetPoint("TOPLEFT", seg, "TOPLEFT", px, -px)
            seg.fill:SetPoint("BOTTOMRIGHT", seg, "BOTTOMRIGHT", -px, px)
            seg.fill:Hide()
            KE:AddIconBorders(seg, { 0, 0, 0, 1 })
            pips.segs[i] = seg
        end
        pips.count = root:CreateFontString(nil, "OVERLAY")
        self.pips = pips
    end
    local pw, ph, gap = db.PipWidth or 34, db.PipHeight or 18, db.PipSpacing or 3
    local size = db.FontSize or 20
    local showCount = db.ShowCount ~= false
    local rowW = Rules.TOTAL * pw + (Rules.TOTAL - 1) * gap
    local width = showCount and rowW + COUNT_GAP + size * 2 or rowW
    self.anchor:SetSize(width, math_max(ph, size * 1.2))
    for i, seg in ipairs(pips.segs) do
        seg:SetSize(pw, ph)
        seg:ClearAllPoints()
        seg:SetPoint("LEFT", root, "LEFT", (i - 1) * (pw + gap), 0)
        seg:Show()
    end
    KE:ApplyFontToText(pips.count, db.FontFace, size, db.FontOutline)
    pips.count:ClearAllPoints()
    pips.count:SetPoint("LEFT", root, "LEFT", rowW + COUNT_GAP, 0)
    pips.count:SetShown(showCount)
    root:Show()
end

function ID:LayoutText()
    local db = self.db
    local size = db.FontSize or 20
    self.anchor:SetSize(size * 2, size * 1.2)
    KE:ApplyFontToText(self.text, db.FontFace, size, db.FontOutline)
    self.text:Show()
end

-- Only the chosen mode's frames are shown; the others get no calls.
function ID:ApplyLayout()
    if not self.holder then return end
    local mode = ModeOf(self.db)
    self.shownMode = mode
    if self.iconRoot then self.iconRoot:Hide() end
    if self.pipsRoot then self.pipsRoot:Hide() end
    self.text:Hide()
    if mode == "PIPS" then
        self:LayoutPips()
    elseif mode == "TEXT" then
        self:LayoutText()
    else
        self:LayoutIcon()
    end
    self:ApplyPosition()
    self.drawn = nil
    self:SyncWatch()
    self:Place()
    self:Refresh()
end

---------------------------------------------------------------------------------
-- Cooldown Manager attach (Text mode)
---------------------------------------------------------------------------------
function ID:Active()
    return self.live or self.isPreview or self.testing
end

function ID:WantsAttach()
    return ModeOf(self.db) == "TEXT" and self.db.AttachToCDM == true and self:Active()
end

function ID:SyncWatch()
    local want = self:WantsAttach()
    if want == self.watching then return end
    self.watching = want
    if want then
        KE.CDMIcons.Watch("ImminentDemise", Replace, CheckIcon)
    else
        KE.CDMIcons.Unwatch("ImminentDemise")
    end
end

function ID:MoveToAnchor()
    local holder, anchor = self.holder, self.anchor
    holder:SetParent(anchor)
    holder:SetFrameStrata("MEDIUM")
    holder:SetFrameLevel(anchor:GetFrameLevel() + 1)
    holder:ClearAllPoints()
    holder:SetAllPoints(anchor)
    self.text:ClearAllPoints()
    self.text:SetPoint("CENTER", holder, "CENTER", 0, 0)
    self.icon, self.iconID, self.iconStale = nil, nil, false
end

-- Parented to the icon, the count takes its scale and hides with it. Every
-- write here is to KE's own frames. Find matched the icon on a plain id, so
-- the id recorded here is plain.
function ID:Place()
    if not self.holder then return end
    local icon = self:WantsAttach() and FindIcon() or nil
    if icon then
        local holder, db, text = self.holder, self.db, self.text
        holder:SetParent(icon)
        local strata = icon:GetFrameStrata()
        if not issecretvalue(strata) and strata then holder:SetFrameStrata(strata) end
        -- A frame level can be made secret; arithmetic on one would error.
        local level = icon:GetFrameLevel()
        if not issecretvalue(level) then holder:SetFrameLevel(level + ICON_LEVEL_OFFSET) end
        holder:ClearAllPoints()
        holder:SetAllPoints(icon)
        -- Y is the gap away from the icon for ABOVE and BELOW, upward for CENTER.
        local x, y = db.IconX or 0, db.IconY or 2
        text:ClearAllPoints()
        if db.IconPosition == "CENTER" then
            text:SetPoint("CENTER", icon, "CENTER", x, y)
        elseif db.IconPosition == "BELOW" then
            text:SetPoint("TOP", icon, "BOTTOM", x, -y)
        else
            text:SetPoint("BOTTOM", icon, "TOP", x, y)
        end
        self.icon, self.iconID, self.iconStale = icon, icon:GetCooldownID(), false
    else
        self:MoveToAnchor()
    end
    if DEBUG_ID then
        local id = self.iconID
        local where = "screen"
        if issecretvalue(id) then
            where = "secret"
        elseif id ~= nil then
            where = tostring(id)
        end
        KE:Print("[ID] placed on " .. where)
    end
    self:UpdateShown()
end

---------------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------------
function ID:CountNow()
    if self.testing then return self.testCount or 0 end
    if self.isPreview then return Rules.PREVIEW_COUNT end
    return self.state.count
end

-- Every value here is a number this module computed, never a secret, so the
-- changed-count gate is safe.
function ID:Draw(n)
    if n == self.drawn then return end
    self.drawn = n
    local r, g, b, a = KE:ResolveColor(self.db[Rules.COLOR_KEYS[n]], Rules.COLORS[n])
    local text = Rules.Text(n)
    local mode = self.shownMode
    if mode == "ICON" then
        local ic = self.iconEl
        ic.tex:SetDesaturated(n == 0)
        ic.count:SetText(text)
        ic.count:SetTextColor(r, g, b, a)
    elseif mode == "PIPS" then
        local pips = self.pips
        for i, seg in ipairs(pips.segs) do
            if i <= n then
                seg.fill:SetColorTexture(r, g, b, a)
                seg.fill:Show()
            else
                seg.fill:Hide()
            end
        end
        pips.count:SetText(text)
        pips.count:SetTextColor(r, g, b, a)
    else
        self.text:SetText(text)
        self.text:SetTextColor(r, g, b, a)
    end
end

function ID:UpdateShown()
    local holder = self.holder
    if not holder then return end
    local hidden = self.db.HideAtZero == true and self:CountNow() == 0
    holder:SetShown(self:Active() and not self.iconStale and not hidden)
end

function ID:Refresh()
    if not (self.holder and self.shownMode) then return end
    self:Draw(self:CountNow())
    self:UpdateShown()
end

---------------------------------------------------------------------------------
-- Counting
---------------------------------------------------------------------------------
function ID:CountProof(proof)
    if proof == "matched" then
        self.matched = self.matched + 1
    elseif proof == "ghost" then
        self.ghosts = self.ghosts + 1
    elseif proof == "fixed" then
        self.fixes = self.fixes + 1
    end
end

function ID:OnCooldown(_, spellID)
    if KE:IsSecretValue(spellID) then
        self.secretSeen = self.secretSeen + 1
        return
    end
    local door = Rules.DoorFor("SPELL_UPDATE_COOLDOWN", spellID, false)
    if not door then return end
    local state = self.state
    local result, proof = Rules.Signal(state, door, GetTime(), self.ignoreUntil)
    if DEBUG_ID then
        KE:Print(("[ID] %s: %s %s, %d/3"):format(door, result, tostring(proof), state.count))
    end
    if result == "counted" then
        self.strikes = self.strikes + 1
        self:CountProof(proof)
        self:Refresh()
    end
end

function ID:OnGlow(_, spellID)
    if KE:IsSecretValue(spellID) then
        self.secretSeen = self.secretSeen + 1
        return
    end
    if not Rules.IsGlow(spellID, false) then return end
    self.glows = self.glows + 1
    local proof = Rules.Glow(self.state, GetTime())
    if DEBUG_ID then KE:Print(("[ID] glow %d: %s"):format(spellID, tostring(proof))) end
    if proof then
        self:CountProof(proof)
        self:Refresh()
    end
end

---------------------------------------------------------------------------------
-- Activation
---------------------------------------------------------------------------------
-- Going live opens the ignore window too: the cooldown event can be
-- registered in the middle of a login burst.
function ID:SetLive(on)
    if on == self.live then return end
    self.live = on
    if on then
        self.state = Rules.New()
        self.ignoreUntil = GetTime() + Rules.ZONE_IN_IGNORE
        self:RegisterEvent("SPELL_UPDATE_COOLDOWN", "OnCooldown")
        self:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", "OnGlow")
    else
        self:UnregisterEvent("SPELL_UPDATE_COOLDOWN")
        self:UnregisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
        Rules.Reset(self.state)
    end
end

function ID:Evaluate()
    if not self:IsEnabled() then return end
    local _, class = UnitClass("player")
    self:SetLive(class == "WARRIOR" and IsKnown(Rules.TALENT) == true)
    if self.live then self:CreateFrames() end
    if self.holder then self:ApplyLayout() end
    self:RegisterAnchor()
end

-- One talent change fires several events; Evaluate runs once, after the last.
function ID:OnTalentChanged()
    if self.evalTimer then self.evalTimer:Cancel() end
    self.evalTimer = C_Timer.NewTimer(TALENT_EVAL_DELAY, DeferredEvaluate)
end

function ID:OnSpecChanged(_, unit)
    if IsOwnSpecChange(unit, KE:IsSecretValue(unit)) then
        self:OnTalentChanged()
    end
end

-- The count keeps running across a zone change; only the re-announce burst
-- is ignored. With nothing live it re-reads talents, since at a cold login
-- both enable-time reads can land before talents are readable.
function ID:OnEnteringWorld()
    self.ignoreUntil = GetTime() + Rules.ZONE_IN_IGNORE
    if not self.live then self:OnTalentChanged() end
end

function ID:ApplySettings()
    self:UpdateDB()
    if self.db.Enabled then
        if not self:IsEnabled() then
            KitnEssentials:EnableModule("ImminentDemise")
        else
            if self.holder then self:ApplyLayout() end
            self:RegisterAnchor()
        end
    elseif self:IsEnabled() then
        KitnEssentials:DisableModule("ImminentDemise")
    end
end

---------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------
function ID:OnEnable()
    self:UpdateDB()
    -- Class before anything else: a non-warrior gets no events, frame or mover.
    local _, class = UnitClass("player")
    if class ~= "WARRIOR" then return end

    self:RegisterEvent("PLAYER_TALENT_UPDATE", "OnTalentChanged")
    self:RegisterEvent("TRAIT_CONFIG_UPDATED", "OnTalentChanged")
    self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", "OnSpecChanged")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnEnteringWorld")
    self:Evaluate()
    -- At login the talents may not be readable yet; a second pass catches them.
    self:OnTalentChanged()
end

-- KE's frame never stays parented to a Blizzard icon after this.
function ID:OnDisable()
    self:UnregisterAllEvents()
    self.live = false
    if self.evalTimer then
        self.evalTimer:Cancel()
        self.evalTimer = nil
    end
    self:StopTest()
    Rules.Reset(self.state)
    self.isPreview, self.resumePreview = false, false
    if self.holder then
        self:SyncWatch()
        self:MoveToAnchor()
        self.holder:Hide()
    end
    self:UnregisterAnchor()
end

---------------------------------------------------------------------------------
-- Preview (PreviewManager contract), test run, reset, status
---------------------------------------------------------------------------------
-- A placement sample: it ignores the talent and the count.
function ID:ShowPreview()
    self:UpdateDB()
    self:CreateFrames()
    self.isPreview = true
    self:ApplyLayout()
    self:RegisterAnchor()
end

-- Also called on a disabled module during section changes, so every path is
-- safe without a live display.
function ID:HidePreview()
    self.isPreview, self.resumePreview = false, false
    if self:IsEnabled() then
        self:Evaluate()
        return
    end
    if self.holder then
        self:SyncWatch()
        self:MoveToAnchor()
        self.holder:Hide()
    end
    self:UnregisterAnchor()
end

function ID:StopTest()
    for _, timer in ipairs(self.testTimers) do timer:Cancel() end
    wipe(self.testTimers)
    self.testing, self.testCount = false, nil
end

-- A sample on any class; real strikes keep counting under it.
function ID:Test()
    self:UpdateDB()
    self:CreateFrames()
    -- The preview manager still counts the page's preview as shown and will
    -- not call ShowPreview again, so the test brings it back.
    if self.isPreview then self.resumePreview = true end
    self.isPreview = false
    self:StopTest()
    self.testing = true
    local steps = Rules.TEST_STEPS
    self.testCount = steps[1]
    for i = 2, #steps do
        local n = steps[i]
        self.testTimers[#self.testTimers + 1] = C_Timer.NewTimer((i - 1) * Rules.TEST_STEP, function()
            self.testCount = n
            self:Refresh()
        end)
    end
    self.testTimers[#self.testTimers + 1] = C_Timer.NewTimer(#steps * Rules.TEST_STEP, EndTest)
    self:ApplyLayout()
end

function ID:ResetCount()
    Rules.Reset(self.state)
    if DEBUG_ID then KE:Print("[ID] count set to 0") end
    self:Refresh()
end

function ID:TalentStatus()
    return IsKnown(Rules.TALENT) == true
end
