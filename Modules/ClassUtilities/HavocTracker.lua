-- ╔══════════════════════════════════════════════════════════╗
-- ║  HavocTracker.lua                                        ║
-- ║  Module: Havoc Tracker                                   ║
-- ║  Purpose: Warn while the player's own Havoc sits on the  ║
-- ║           target they are hitting, which wastes it.      ║
-- ║  Note: Destruction Warlock only.                         ║
-- ╚══════════════════════════════════════════════════════════╝
--
-- NOTHING HERE READS AN AURA. The display is a Blizzard aura container handed a
-- spell-id filter: the engine matches and the engine draws, which is the only
-- way to know this inside instanced content, where reading a unit's auras is
-- restricted outright.
--
-- It is text rather than an icon because an icon cannot be made to work. The
-- engine's aura button becomes access-restricted while the bound unit's aura
-- data is secret, so a Get or Set call on it can be refused outright rather
-- than returning anything -- which is why every touch of it after AddAuraSlot
-- returns is pcall'd rather than issecretvalue-guarded. A texture stretched to
-- fill it therefore had nothing to fill. A FontString on a single center
-- anchor needs no size at all: when a measurement can be refused, find the
-- layout that needs no measurement.

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class HavocTracker: AceModule
local HT = KitnEssentials:NewModule("HavocTracker", "AceEvent-3.0")
HT.classRestriction = "WARLOCK"

local CreateFrame = CreateFrame
local C_Timer = C_Timer
local UnitClass = UnitClass
local GetSpecialization = C_SpecializationInfo.GetSpecialization
local GetSpecializationInfo = C_SpecializationInfo.GetSpecializationInfo
local pcall = pcall
local unpack = unpack
local UnitExists = UnitExists
local UnitCanAssist = UnitCanAssist
local Ask = KE.PlateSlots.Ask

-- Flip to true, /reload, repro, read the log.
local DEBUG_HT = false

---------------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------------
-- The talent that applies Havoc automatically applies the same debuff, so one
-- id covers both.
local HAVOC_IDS = { [80240] = true }
local DESTRUCTION_SPEC = 267
local DEFAULT_TEXT = "Havoc Target"
local ANCHOR_WIDTH = 280
local ATTACH_KEY = "havoc"

---------------------------------------------------------------------------------
-- Module State
---------------------------------------------------------------------------------
HT.anchor = nil
HT.container = nil
HT.previewText = nil
HT.active = false
HT.previewing = false
HT.editModeRegistered = false
HT.bound = false
HT.targetWanted = nil

local function WarningText(db)
    local text = db.WarningText
    if text and text ~= "" then return text end
    return DEFAULT_TEXT
end

-- Keyed on the toggle and the saved Combat Texts settings rather than on
-- Combat Texts running: the game builds the warning once, possibly before
-- Combat Texts is up. Returns face, outline, size.
local function EffectiveStyle(db)
    local ct = KE.db and KE.db.profile.CombatTexts
    if db.AttachToCombatTexts and ct then
        local cm = KitnEssentials:GetModule("CombatTexts", true)
        local size = cm and cm.ResolveAttachedSize(true, db.AttachOwnFontSize, db.WarningFontSize, ct.FontSize)
        return ct.FontFace, ct.FontOutline, size or db.WarningFontSize
    end
    return db.FontFace, db.FontOutline, db.WarningFontSize
end

-- builtSize is the largest size the game's warning was built at this session.
-- That text keeps it until a reload, so the anchor never shrinks below it.
local function AnchorHeight(db, builtSize)
    local _, _, size = EffectiveStyle(db)
    return math.max(size or 24, builtSize or 0) + 8
end

---------------------------------------------------------------------------------
-- DB Helper
---------------------------------------------------------------------------------
function HT:UpdateDB()
    self.db = KE.db.profile.HavocTracker
end

function HT:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

---------------------------------------------------------------------------------
-- Gate
---------------------------------------------------------------------------------
-- The two values the gate decides on.
local function ReadSpecIdentity()
    local _, class = UnitClass("player")
    local specIndex = GetSpecialization and GetSpecialization()
    local specID = specIndex and specIndex > 0 and GetSpecializationInfo(specIndex) or nil
    return class, specID
end

local function WantsSpec(class, specID)
    return class == "WARLOCK" and specID == DESTRUCTION_SPEC
end

function HT:IsWantedSpec()
    return WantsSpec(ReadSpecIdentity())
end

-- Off-spec nothing is registered and no container is built.
--
-- The identity is sampled ONCE here and both the decision and the debug line are
-- derived from that one sample. Calling IsWantedSpec and then re-reading for the
-- log would let a spec change between the two make the log describe a decision
-- that was never taken.
function HT:EvaluateGate()
    local enabled = self.db.Enabled == true
    local class, specID = ReadSpecIdentity()
    local wantedSpec = WantsSpec(class, specID)
    if DEBUG_HT then
        KE:Print(("[HT] gate enabled=%s class=%s spec=%s -> %s"):format(
            tostring(enabled), tostring(class), tostring(specID),
            (enabled and wantedSpec) and "activate" or "deactivate"))
    end
    if not (enabled and wantedSpec) then return self:Deactivate() end
    self:Activate()
end

---------------------------------------------------------------------------------
-- Display
---------------------------------------------------------------------------------

function HT:CreateAnchor()
    if self.anchor then return end
    local frame = CreateFrame("Frame", "KE_HavocWarning", UIParent)
    frame:SetFrameStrata(self.db.Strata or "MEDIUM")
    self.anchor = frame
    -- Attached, the login anchor pass must not put the anchor back on its own
    -- Player Frame position.
    KE:RegisterAnchorRepair(frame, function()
        return not self:IsAttached() and self.db.anchorFrameType == "PLAYERFRAME"
    end, function() self:ApplyPosition() end)
    self:ApplyPosition()
end

function HT:IsAttached()
    local cm = KitnEssentials:GetModule("CombatTexts", true)
    return cm ~= nil and cm:AcceptsAttach(self.db.AttachToCombatTexts == true)
end

-- Moves only our anchor. The engine's button is centered on it and follows,
-- so nothing here touches the button.
function HT:ApplyPosition()
    local anchor = self.anchor
    if not anchor then return end
    local cm = KitnEssentials:GetModule("CombatTexts", true)
    local wantAttach = (self:IsEnabled() or self.previewing) and cm ~= nil and self:IsAttached()
    -- The built-size floor is for the stack only; detached, the height keeps
    -- its own rule so a centered anchor does not move.
    anchor:SetSize(ANCHOR_WIDTH, AnchorHeight(self.db, wantAttach and self.builtSize or nil))
    local attached = wantAttach and cm:SetAttachedFrame(ATTACH_KEY, anchor)
    if not attached then
        if cm then cm:SetAttachedFrame(ATTACH_KEY, nil) end
        KE:ApplyFramePosition(anchor, self.db.WarningPosition, self.db)
    end
    if cm then cm:SyncAttachSubscription(self, self:IsEnabled() or self.previewing) end
end

-- The engine's one legal creation window for this button. Everything drawn on it
-- has to be built here; outside it the button is not ours to touch, and even
-- asking whether it is shown is refused.
function HT:InitWarningButton(button)
    local db = self.db

    -- A slot takes no part in the flow layout, so it is placed by hand: an
    -- unplaced button is matched and drawn nowhere, with no error.
    button:ClearAllPoints()
    button:SetPoint("CENTER", self.anchor, "CENTER", 0, 0)
    button:SetSize(ANCHOR_WIDTH, AnchorHeight(db))
    -- Display only: no aura tooltip, and clicks reach the world.
    pcall(button.SetMouseClickEnabled, button, false)
    pcall(button.SetMouseMotionEnabled, button, false)

    local text = button:CreateFontString(nil, "OVERLAY")
    -- One anchor point, deliberately. SetAllPoints would tie the string to a
    -- button whose size we cannot know.
    text:SetPoint("CENTER", button, "CENTER", 0, 0)
    local face, outline, size = EffectiveStyle(db)
    KE:ApplyFontToText(text, face, size, outline)
    -- Recorded on the module, not the button. The anchor was last sized from
    -- these same settings, so nothing needs moving here.
    self.builtSize = math.max(self.builtSize or 0, size or 24)
    text:SetTextColor(unpack(db.WarningColor))
    text:SetText(WarningText(db))
    text:Show()
end

function HT:BuildContainer()
    if self.container then return end
    if not KE:AuraContainersAvailable() then
        if DEBUG_HT then KE:Print("[HT] build skipped: aura containers unavailable") end
        return
    end
    self:CreateAnchor()

    local ok, container = pcall(CreateFrame, "AuraContainer", nil, self.anchor, "CustomAuraContainerTemplate")
    if DEBUG_HT then KE:Print("[HT] container created=" .. tostring(ok)) end
    if not ok or not container then return end

    container:SetPoint("CENTER", self.anchor, "CENTER", 0, 0)
    container:SetSize(1, 1)

    -- PLAYER restricts the match to Havoc YOU applied, so another Warlock's
    -- cannot announce itself as yours.
    local options = {
        initializeFrame = function(button) HT:InitWarningButton(button) end,
        candidateFilters = { includeSpellIDs = HAVOC_IDS },
    }

    local added = pcall(container.AddAuraSlot, container, "havoctarget", "HARMFUL|PLAYER", options)
    if DEBUG_HT then KE:Print("[HT] slot added=" .. tostring(added)) end
    if not added then return end

    -- Bound and enabled by UpdateTarget.
    container:Show()

    self.container = container
end

---------------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------------
-- The game ignores a spell-id filter for harmful auras on a unit the player
-- can assist, so there the slot would light for any of the player's debuffs.
-- Immune and uninteractable units count as assistable, as the filter's guard
-- counts them.
local function CanAssist(unit)
    return Ask(UnitCanAssist, "player", unit, true, true)
end

-- The same token is a no-op for SetUnit, so a new target is read through
-- UpdateAllAuras.
function HT:UpdateTarget()
    local container = self.container
    if not container then return end
    if not self.bound then
        self.bound = pcall(container.SetUnit, container, "target")
    end
    local want = self.bound
        and KE.DoTTrackerRules.TimerWanted(Ask(UnitExists, "target"), CanAssist("target"))
    self.targetWanted = want
    pcall(container.SetEnabled, container, want)
    if want then pcall(container.UpdateAllAuras, container) end
    if DEBUG_HT then
        KE:Print("[HT] target bound=" .. tostring(self.bound) .. " wanted=" .. tostring(want))
    end
end

-- Either side's faction can change while targeted.
function HT:OnUnitFaction(_, unit)
    if unit == "target" or unit == "player" then self:UpdateTarget() end
end

function HT:Activate()
    if self.active then return end
    self:BuildContainer()
    if not self.container then return end

    -- Show unconditionally, not only on the build path. Deactivate hides the
    -- container, and a second Activate finds it already built and skips
    -- BuildContainer entirely -- so without this an off-then-on toggle, or a
    -- spec swap away and back, leaves a container that is live and unhidden by
    -- nothing. It logs "activate" and draws nothing until a reload.
    self.container:Show()

    self.active = true
    self:RegisterEvent("PLAYER_TARGET_CHANGED", "UpdateTarget")
    self:RegisterEvent("UNIT_FACTION", "OnUnitFaction")
    self:UpdateTarget()
end

function HT:Deactivate()
    if not self.active then return end
    self.active = false
    self:UnregisterEvent("PLAYER_TARGET_CHANGED")
    self:UnregisterEvent("UNIT_FACTION")
    if self.container then
        pcall(self.container.SetEnabled, self.container, false)
        self.container:Hide()
    end
end

---------------------------------------------------------------------------------
-- Edit Mode
---------------------------------------------------------------------------------
function HT:RegWithEditMode()
    if not KE.EditMode then return end
    self:CreateAnchor()
    -- Attached, the Combat Texts mover moves the warning; a second mover for
    -- it would fight that one.
    if self:IsAttached() then
        if self.editModeRegistered then
            KE.EditMode:UnregisterElement("HavocTracker")
            self.editModeRegistered = false
        end
        return
    end
    if self.editModeRegistered then return end
    KE.EditMode:RegisterElement({
        key = "HavocTracker", displayName = "Havoc Warning", frame = self.anchor,
        module = self,
        getPosition = function() return self.db.WarningPosition end,
        setPosition = function(pos)
            self.db.WarningPosition = pos
            KE:ApplyFramePosition(self.anchor, self.db.WarningPosition, self.db)
        end,
        getParentFrame = function() return KE:ResolveAnchorFrame(self.db.anchorFrameType, self.db.ParentFrame) end,
        guiPath = "ClassTools",
        guiTab = "HavocTracker",
    })
    self.editModeRegistered = true
end

---------------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------------
function HT:ApplySettings()
    if not self:IsEnabled() then return end
    self:UpdateDB()
    if self.anchor then
        self.anchor:SetFrameStrata(self.db.Strata or "MEDIUM")
        self:ApplyPosition()
        self:RegWithEditMode()
    end

    -- Re-draw the preview if one is up. Without this every control on the page
    -- looks dead while the options are open, because the live display is hidden
    -- precisely when you are looking at the preview.
    if self.previewing then self:ShowPreview() end

    self:EvaluateGate()
end

---------------------------------------------------------------------------------
-- Preview
---------------------------------------------------------------------------------
-- Draws on OUR anchor, never the engine button: an engine button cannot be made
-- to show an absent aura, and writing to one behind the engine's back is undone
-- by its next update.
function HT:ShowPreview()
    self:CreateAnchor()
    self:RegWithEditMode()
    self.previewing = true
    local db = self.db

    if not self.previewText then
        self.previewText = self.anchor:CreateFontString(nil, "OVERLAY")
        self.previewText:SetPoint("CENTER", self.anchor, "CENTER", 0, 0)
    end
    local face, outline, size = EffectiveStyle(db)
    KE:ApplyFontToText(self.previewText, face, size, outline)
    self.previewText:SetTextColor(unpack(db.WarningColor))
    self.previewText:SetText(WarningText(db))
    self.previewText:Show()
    self.anchor:Show()
    self:ApplyPosition()
end

function HT:HidePreview()
    self.previewing = false
    if self.previewText then self.previewText:Hide() end
    local cm = KitnEssentials:GetModule("CombatTexts", true)
    if cm then cm:SyncAttachSubscription(self, self:IsEnabled()) end
end

---------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------
function HT:OnEnable()
    self:UpdateDB()
    -- Class before anything else. Without it a non-Warlock with the module
    -- switched on still gets an anchor frame and an Edit Mode mover, because
    -- neither the mover registry nor classRestriction filters on class --
    -- classRestriction gates the preview manager only.
    local _, class = UnitClass("player")
    if class ~= "WARLOCK" then return end
    if not self.db.Enabled then return end

    self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", "EvaluateGate")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "EvaluateGate")
    self:RegWithEditMode()
    -- A retained anchor skips CreateAnchor's placement, and disable dropped
    -- the slot and the subscription.
    self:ApplyPosition()
    -- Deferred once: the spec is not reliably readable on the frame this runs.
    C_Timer.After(0.5, function()
        if self:IsEnabled() then self:EvaluateGate() end
    end)
end

function HT:OnDisable()
    self:Deactivate()
    self:UnregisterAllEvents()
    self:HidePreview()
    local cm = KitnEssentials:GetModule("CombatTexts", true)
    if cm then cm:SetAttachedFrame(ATTACH_KEY, nil) end
    -- Clearing the guard is what lets a later enable register again.
    if KE.EditMode then KE.EditMode:UnregisterElement("HavocTracker") end
    self.editModeRegistered = false
end
