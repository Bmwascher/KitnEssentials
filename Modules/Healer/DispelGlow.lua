-- ╔══════════════════════════════════════════════════════════╗
-- ║  DispelGlow.lua                                          ║
-- ║  Module: Dispel Glow (ElvUI party/raid/tank frames)      ║
-- ║  Purpose: Colored 1px border + top fade band on ElvUI    ║
-- ║           party/raid/tank/assist frames whenever a       ║
-- ║           dispellable debuff is present, including       ║
-- ║           private auras. Color matches the dispel type   ║
-- ║           using the Aura Debuffs dispel palette.         ║
-- ║                                                          ║
-- ║  Requires ElvUI. Ported from atrocityEssentials          ║
-- ║  DispelGlow: hooks ElvUI's AuraHighlight.PostUpdate (no  ║
-- ║  independent aura scanning) and anchors Blizzard's native║
-- ║  PrivateAuraAnchor for private auras the aura API hides. ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class DispelGlow: AceModule, AceEvent-3.0
local DG = KitnEssentials:NewModule("DispelGlow", "AceEvent-3.0")

-- Diagnostic flag: when true, tints every managed overlay red (frame
-- discovery sanity-check) and logs per-frame setup. Leave false in ship
-- builds. The production path is purely event-driven — no live OnUpdate.
local DEBUG_DG = false

-- Localisation
local CreateFrame            = CreateFrame
local C_UnitAuras            = C_UnitAuras
local C_Timer                = C_Timer
local pairs                  = pairs
local ipairs                 = ipairs
local tostring               = tostring
local math_max               = math.max
local UnitExists             = UnitExists
local IsInRaid               = IsInRaid
local GetAuraDispelTypeColor = C_UnitAuras and C_UnitAuras.GetAuraDispelTypeColor

local GRADIENT_TEX = "Interface\\AddOns\\KitnEssentials\\Media\\DispelGlow\\Gradient_V"

------------------------------------------------------------------------
-- ElvUI presence. The module is still created when ElvUI is absent (so
-- the GUI can render its "requires ElvUI" note and the sidebar entry
-- works); OnEnable short-circuits without it. ElvUI's `E` is resolved
-- lazily, never at file scope, so `unpack(ElvUI)` is never run on nil.
------------------------------------------------------------------------
local function HasElvUI()
    return _G.ElvUI ~= nil
end

------------------------------------------------------------------------
-- Shared dispel palette. DispelGlow reuses the curve Aura Debuffs builds
-- from the user's Dispel Type Colors, so the glow color always matches
-- the configured debuff palette. Queried fresh each paint so palette
-- edits are picked up without a reload.
------------------------------------------------------------------------
local function GetDispelColorCurve()
    local ad = KitnEssentials:GetModule("AuraDebuffs", true)
    if ad and ad.GetDispelColorCurve then
        return ad:GetDispelColorCurve()
    end
    return nil
end

------------------------------------------------------------------------
-- Dispel capability gate. Built once at enable (and on SPELLS_CHANGED)
-- from LibDispel. If the player has zero friendly dispel abilities
-- (e.g. warrior), we skip all regular-aura glows. This avoids Blizzard's
-- broken RAID_PLAYER_DISPELLABLE filter flagging debuffs for classes
-- with offensive purges but no friendly cleanses.
--
-- We can't check the specific debuff type at render time because
-- C_UnitAuras returns secret values that can't be used as table keys.
------------------------------------------------------------------------
local hasAnyFriendlyDispel = false

local function UpdateDispelCapability()
    hasAnyFriendlyDispel = false
    local E = _G.ElvUI and unpack(_G.ElvUI)
    local lib = E and E.Libs and E.Libs.Dispel
    if lib and lib.GetMyDispelTypes then
        for _, v in pairs(lib:GetMyDispelTypes()) do
            if v then hasAnyFriendlyDispel = true; return end
        end
    end
end

------------------------------------------------------------------------
-- State
------------------------------------------------------------------------
-- containerByFrame: [hostFrame] = { visual = Frame, unit = string,
--                                   privateWrapper = Frame, privateAnchorID }
local containerByFrame = {}
-- observedFrames:   [hostFrame] = true (OnAttributeChanged hooked once)
local observedFrames   = {}

------------------------------------------------------------------------
-- Visual aesthetic constants
------------------------------------------------------------------------
local TOPGLOW_ALPHA_TOP = 0.7
local TOPGLOW_HEIGHT    = 14
local BORDER_INSET      = 1
local BORDER_THICKNESS  = 1

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------
local function IsValidUnitToken(s)
    if type(s) ~= "string" or s == "" then return false end
    return UnitExists and UnitExists(s)
end

local function GetFrameUnit(node)
    if not node then return nil end
    local unit = node.unit
    if IsValidUnitToken(unit) then return unit end
    if node.GetAttribute then
        unit = node:GetAttribute("unit")
        if IsValidUnitToken(unit) then return unit end
    end
    return nil
end

------------------------------------------------------------------------
-- Visual construction: 1px colored border inset 1px from the frame edge,
-- plus a 14px-tall vertical fade band at the top fading from alpha 0.7 at
-- the top to alpha 0 at the bottom.
------------------------------------------------------------------------
local function BuildVisual(frame)
    local visual = CreateFrame("Frame", nil, frame)
    visual:SetAllPoints(frame)
    visual:SetFrameLevel(frame:GetFrameLevel() + 10)
    visual:EnableMouse(false)
    if visual.SetMouseClickEnabled then visual:SetMouseClickEnabled(false) end
    visual:Hide()

    local function edge() return visual:CreateTexture(nil, "OVERLAY") end

    visual.borderTop = edge()
    visual.borderTop:SetPoint("TOPLEFT",  frame, "TOPLEFT",   BORDER_INSET, -BORDER_INSET)
    visual.borderTop:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -BORDER_INSET, -BORDER_INSET)
    visual.borderTop:SetHeight(BORDER_THICKNESS)

    visual.borderBottom = edge()
    visual.borderBottom:SetPoint("BOTTOMLEFT",  frame, "BOTTOMLEFT",   BORDER_INSET, BORDER_INSET)
    visual.borderBottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -BORDER_INSET, BORDER_INSET)
    visual.borderBottom:SetHeight(BORDER_THICKNESS)

    visual.borderLeft = edge()
    visual.borderLeft:SetPoint("TOPLEFT",    frame, "TOPLEFT",     BORDER_INSET, -BORDER_INSET)
    visual.borderLeft:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT",  BORDER_INSET,  BORDER_INSET)
    visual.borderLeft:SetWidth(BORDER_THICKNESS)

    visual.borderRight = edge()
    visual.borderRight:SetPoint("TOPRIGHT",    frame, "TOPRIGHT",    -BORDER_INSET, -BORDER_INSET)
    visual.borderRight:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -BORDER_INSET,  BORDER_INSET)
    visual.borderRight:SetWidth(BORDER_THICKNESS)

    visual.topGlow = visual:CreateTexture(nil, "OVERLAY")
    visual.topGlow:SetTexture(GRADIENT_TEX)
    visual.topGlow:SetVertexColor(1, 1, 1, 0)
    visual.topGlow:SetPoint("TOPLEFT",  frame, "TOPLEFT",   BORDER_INSET + BORDER_THICKNESS, -(BORDER_INSET + BORDER_THICKNESS))
    visual.topGlow:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -(BORDER_INSET + BORDER_THICKNESS), -(BORDER_INSET + BORDER_THICKNESS))
    visual.topGlow:SetHeight(TOPGLOW_HEIGHT)

    return visual
end

------------------------------------------------------------------------
-- Build a Blizzard PrivateAuraAnchor on the host frame so private
-- dispellable auras render their dispel indicator inside our anchor.
-- Private aura state is not readable from addon code — Blizzard handles
-- detection and rendering itself when given an anchor.
--
-- Returns wrapper frame and anchorID. Both nil if registration fails.
-- Failures are silent and per-frame — other frames can still succeed.
------------------------------------------------------------------------
local function BuildPrivateAnchor(frame, unit)
    if not C_UnitAuras or not C_UnitAuras.AddPrivateAuraAnchor then return nil, nil end
    if not unit or not UnitExists(unit) then return nil, nil end

    -- Numeric group-type: 4 = party, 5 = raid (matches Blizzard internals)
    local groupType
    if unit:match("^party") then groupType = 4
    elseif unit:match("^raid") then groupType = 5
    elseif unit == "player" then
        groupType = IsInRaid() and 5 or 4
    else return nil, nil end

    -- Expand the wrapper slightly BEYOND the frame edges. Combined with a
    -- frame level BELOW the unit frame, the health bar masks Blizzard's
    -- chunky gradient/border — only 1-2px of border peeks out around the
    -- edges, creating a clean thin border effect.
    local wrapper = CreateFrame("Frame", nil, frame)
    wrapper:SetParent(frame)
    wrapper:ClearAllPoints()
    local PRIVATE_EXPAND = 1
    wrapper:SetPoint("TOPLEFT", -PRIVATE_EXPAND, PRIVATE_EXPAND)
    wrapper:SetPoint("BOTTOMRIGHT", PRIVATE_EXPAND, -PRIVATE_EXPAND)
    wrapper:SetFrameLevel(math_max(frame:GetFrameLevel() - 1, 0))
    wrapper:EnableMouse(false)
    if wrapper.SetMouseClickEnabled then wrapper:SetMouseClickEnabled(false) end

    wrapper:SetAttribute("max-buffs", 0)
    wrapper:SetAttribute("max-debuffs", 0)
    wrapper:SetAttribute("max-dispel-debuffs", 1)
    wrapper:SetAttribute("ignore-buffs", true)
    wrapper:SetAttribute("ignore-debuffs", true)
    wrapper:SetAttribute("ignore-dispel-debuffs", true)
    wrapper:SetAttribute("dispel-indicator-option", 1)
    wrapper:SetAttribute("show-dispel-indicator-overlay", true)
    wrapper:SetAttribute("suppress-dispel-border-icons", true)
    wrapper:SetAttribute("always-hide-duration", true)
    wrapper:SetAttribute("set-aura-size-to-icon-size", true)
    wrapper:SetAttribute("icon-size", 12)
    wrapper:SetAttribute("power-bar-used-height", 0)
    wrapper:SetAttribute("aura-organization-type", 0)
    wrapper:SetAttribute("group-type", groupType)
    wrapper:SetAttribute("update-settings", true)
    wrapper:SetAlpha(1.0)
    wrapper:Show()

    local ok, anchorID = pcall(function()
        return C_UnitAuras.AddPrivateAuraAnchor({
            unitToken            = unit,
            auraIndex            = 1,
            isContainer          = true,
            parent               = wrapper,
            showCountdownFrame   = false,
            showCountdownNumbers = false,
        })
    end)

    if not ok or not anchorID then
        wrapper:Hide()
        wrapper:SetParent(nil)
        return nil, nil
    end

    -- Force Blizzard to re-snapshot the wrapper's frame level.
    local level = wrapper:GetFrameLevel()
    wrapper:SetFrameLevel(0)
    wrapper:SetFrameLevel(level)

    return wrapper, anchorID
end

------------------------------------------------------------------------
-- Apply a Color (from GetAuraDispelTypeColor) to the visual.
--
-- r,g,b,a may be secret-marked even when the curve we passed in had clean
-- values (Blizzard returns curve-evaluated colors through the protected-
-- data flow). SetColorTexture and SetVertexColor both accept secret values
-- transparently; CreateColor errors on them.
--
-- Borders use SetColorTexture (solid colored bar). The top fade band is a
-- pre-baked white-to-transparent gradient texture tinted by SetVertexColor
-- — the texture's built-in alpha gradient gives the vertical fade, and
-- tinting it preserves that gradient.
------------------------------------------------------------------------
local function ApplyVisualColor(visual, color)
    if not visual or not color then return end
    local r, g, b, a = color:GetRGBA()
    if r == nil then return end
    a = a or 1.0
    for _, tex in ipairs({ visual.borderTop, visual.borderBottom,
                          visual.borderLeft, visual.borderRight }) do
        if tex then tex:SetColorTexture(r, g, b, a) end
    end
    if visual.topGlow then
        visual.topGlow:SetVertexColor(r, g, b, a)
        visual.topGlow:SetAlpha(TOPGLOW_ALPHA_TOP)
    end
end

------------------------------------------------------------------------
-- Hook ElvUI's AuraHighlight PostUpdate on a unit frame's element.
--
-- Instead of scanning auras ourselves, we wrap the PostUpdate that oUF
-- calls after MidnightLoop has already determined whether the unit has a
-- dispellable debuff. We receive the result (debuffType and aura) and just
-- apply/hide our visual overlay — zero independent aura iteration.
------------------------------------------------------------------------
local function HookAuraHighlight(frame)
    local element = frame and frame.AuraHighlight
    if not element or element._keDispelHooked then return end
    if not element.PostUpdate then return end
    element._keDispelHooked = true

    local orig = element.PostUpdate

    element.PostUpdate = function(self, parentFrame, unit, aura, debuffType, texture, wasFiltered, style, color)
        orig(self, parentFrame, unit, aura, debuffType, texture, wasFiltered, style, color)

        local entry = containerByFrame[parentFrame]
        if not entry or not entry.visual then return end

        if debuffType and aura and aura.auraInstanceID and aura.isHarmful
           and hasAnyFriendlyDispel then
            local curve = GetDispelColorCurve()
            if curve then
                local c = GetAuraDispelTypeColor(unit, aura.auraInstanceID, curve)
                if c then
                    ApplyVisualColor(entry.visual, c)
                    entry.visual:Show()
                    -- Hide Blizzard's private overlay to avoid double-glow
                    if entry.privateWrapper then entry.privateWrapper:SetAlpha(0) end
                    return
                end
            end
        end

        entry.visual:Hide()
        -- Restore Blizzard's overlay for private auras (only if player can dispel)
        if entry.privateWrapper then
            entry.privateWrapper:SetAlpha(hasAnyFriendlyDispel and 1 or 0)
        end
    end
end

------------------------------------------------------------------------
-- Force oUF to re-evaluate AuraHighlight on a frame, which triggers our
-- hooked PostUpdate with the current state.
------------------------------------------------------------------------
local function ForceAuraHighlightUpdate(frame)
    local element = frame and frame.AuraHighlight
    if element and element.ForceUpdate then
        element:ForceUpdate()
    end
end

------------------------------------------------------------------------
-- Per-frame setup/teardown.
------------------------------------------------------------------------
local function SetupContainer(frame, unit)
    if containerByFrame[frame] then return end
    local visual = BuildVisual(frame)
    if DEBUG_DG then
        local tex = visual:CreateTexture(nil, "OVERLAY")
        tex:SetAllPoints(visual)
        tex:SetColorTexture(1, 0, 0, 0.4)
        visual:Show()
    end
    containerByFrame[frame] = {
        visual = visual,
        unit   = unit,
    }
    -- Hook ElvUI's AuraHighlight so we react to its dispel detection
    HookAuraHighlight(frame)
    if DEBUG_DG then
        KE:Print(("[DG] setup %s -> %s"):format(
            tostring(unit),
            tostring(frame.GetName and frame:GetName() or "<anon>")))
    end
    -- Trigger an initial update via oUF so our hook fires with current state
    ForceAuraHighlightUpdate(frame)
end

local function TeardownContainer(frame)
    local entry = containerByFrame[frame]
    if not entry then return end
    if entry.privateAnchorID and C_UnitAuras and C_UnitAuras.RemovePrivateAuraAnchor then
        pcall(C_UnitAuras.RemovePrivateAuraAnchor, entry.privateAnchorID)
    end
    if entry.privateWrapper then
        entry.privateWrapper:Hide()
        entry.privateWrapper:SetParent(nil)
    end
    if entry.visual then
        entry.visual:Hide()
        entry.visual:SetParent(nil)
    end
    containerByFrame[frame] = nil
end

local function TeardownAll()
    for frame in pairs(containerByFrame) do TeardownContainer(frame) end
end

------------------------------------------------------------------------
-- React to the host frame's unit attribute changing (ElvUI roster
-- reshuffling). No deferred-queue gymnastics needed since we never touch
-- forbidden objects — the hook body can do real work inline.
------------------------------------------------------------------------
local function UpdateFrameAnchor(frame)
    if not frame then return end
    local newUnit = GetFrameUnit(frame)
    local entry   = containerByFrame[frame]
    local oldUnit = entry and entry.unit
    if newUnit == oldUnit then return end
    if entry then TeardownContainer(frame) end
    if newUnit then
        local w = frame.GetWidth  and frame:GetWidth()  or 0
        local h = frame.GetHeight and frame:GetHeight() or 0
        if w > 0 and h > 0 then
            SetupContainer(frame, newUnit)
        else
            C_Timer.After(0.1, function() UpdateFrameAnchor(frame) end)
        end
    end
end

------------------------------------------------------------------------
-- Hook OnAttributeChanged once per frame; gate on Enabled at fire time so
-- disabling the module is also a runtime no-op.
------------------------------------------------------------------------
local function ObserveFrame(frame)
    if not frame or observedFrames[frame] then return end
    observedFrames[frame] = true
    frame:HookScript("OnAttributeChanged", function(self, name, _value)
        if name == "unit" and DG.db and DG.db.Enabled then
            UpdateFrameAnchor(self)
        end
    end)
    if DG.db and DG.db.Enabled then UpdateFrameAnchor(frame) end
end

------------------------------------------------------------------------
-- Frame discovery. Direct _G[name] lookup covers party (1×5), raid up to
-- 40-man (8×5), and tank/assist headers up to 8 each. Idempotent so
-- re-discovery on roster events is cheap.
------------------------------------------------------------------------
function DG:Discover()
    if not self.db then return end
    -- Player frame included for private aura detection (isHarmful guard
    -- prevents false positives on buffs for regular dispel glow).
    if _G.ElvUF_Player then ObserveFrame(_G.ElvUF_Player) end
    for g = 1, 8 do
        for b = 1, 5 do
            local p = _G[("ElvUF_PartyGroup%dUnitButton%d"):format(g, b)]
            local r = _G[("ElvUF_RaidGroup%dUnitButton%d"):format(g, b)]
            if p then ObserveFrame(p) end
            if r then ObserveFrame(r) end
        end
    end
    for b = 1, 8 do
        local t = _G[("ElvUF_TankUnitButton%d"):format(b)]
        local a = _G[("ElvUF_AssistUnitButton%d"):format(b)]
        if t then ObserveFrame(t) end
        if a then ObserveFrame(a) end
    end
end

------------------------------------------------------------------------
-- Private aura anchors — decoupled from SetupContainer so they run after
-- Blizzard's secure aura system is ready, not during early frame discovery
-- when AddPrivateAuraAnchor would fail.
------------------------------------------------------------------------
local function AttachPrivateAnchors()
    for frame, entry in pairs(containerByFrame) do
        if not entry.privateAnchorID and entry.unit then
            local wrapper, anchorID = BuildPrivateAnchor(frame, entry.unit)
            if wrapper then
                entry.privateWrapper  = wrapper
                entry.privateAnchorID = anchorID
            end
        end
    end
end

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------
function DG:PLAYER_ENTERING_WORLD()
    self:Discover()
    -- ElvUI may finish creating secure-header buttons after this event
    -- fires; a deferred re-discovery picks them up. Private anchors are
    -- also attached here — by 2s, Blizzard's secure aura system is ready.
    C_Timer.After(2, function()
        self:Discover()
        AttachPrivateAnchors()
    end)
end

function DG:GROUP_ROSTER_UPDATE()
    self:Discover()
    AttachPrivateAnchors()
end

function DG:SPELLS_CHANGED()
    UpdateDispelCapability()
end

------------------------------------------------------------------------
-- Lifecycle
------------------------------------------------------------------------
function DG:UpdateDB()
    self.db = KE.db.profile.DispelGlow
end

function DG:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

function DG:OnEnable()
    self:UpdateDB()
    if not HasElvUI() then
        KE:Print("[DG] Dispel Glow requires ElvUI; module not started.")
        return
    end
    if not (C_UnitAuras and C_UnitAuras.GetAuraDispelTypeColor) then
        KE:Print("[DG] C_UnitAuras dispel API unavailable; module not started.")
        return
    end
    if not self.db or not self.db.Enabled then return end

    UpdateDispelCapability()
    self:Discover()
    C_Timer.After(2, function()
        self:Discover()
    end)
    self:RegisterEvent("PLAYER_ENTERING_WORLD")
    self:RegisterEvent("GROUP_ROSTER_UPDATE")
    self:RegisterEvent("SPELLS_CHANGED")
end

function DG:OnDisable()
    self:UnregisterAllEvents()
    TeardownAll()
end

------------------------------------------------------------------------
-- Apply runtime DB changes. Called from the GUI when a setting flips.
--
-- Enabled is not handled here; EnableModule/DisableModule trigger
-- OnEnable/OnDisable which manage container lifetime.
------------------------------------------------------------------------
function DG:ApplySettings()
    self:UpdateDB()
    if not self.db.Enabled then
        TeardownAll()
        return
    end

    -- Force oUF to re-evaluate AuraHighlight on all managed frames
    for frame in pairs(containerByFrame) do
        ForceAuraHighlightUpdate(frame)
    end
end
