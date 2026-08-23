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
-- fill it therefore had nothing to fill. A FontString on a single centre
-- anchor needs no size at all: when a measurement can be refused, find the
-- layout that needs no measurement.

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class HavocTracker: AceModule
local HT = KitnEssentials:NewModule("HavocTracker", "AceEvent-3.0")
HT.classRestriction = "WARLOCK"

local _G = _G
local CreateFrame = CreateFrame
local C_AddOns = C_AddOns
local C_Timer = C_Timer
local UnitClass = UnitClass
local GetSpecialization = C_SpecializationInfo.GetSpecialization
local GetSpecializationInfo = C_SpecializationInfo.GetSpecializationInfo
local pcall = pcall
local unpack = unpack

-- Flip to true, /reload, repro, read the log. The slot-anchoring line is the
-- one that matters: a refusal there means the bound unit is identity-restricted
-- and no amount of layout work will make this display appear.
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

---------------------------------------------------------------------------------
-- Module State
---------------------------------------------------------------------------------
HT.anchor = nil
HT.container = nil
HT.previewText = nil
HT.active = false
HT.previewing = false
HT.editModeRegistered = false

local function WarningText(db)
    local text = db.WarningText
    if text and text ~= "" then return text end
    return DEFAULT_TEXT
end

local function AnchorHeight(db)
    return (db.WarningFontSize or 24) + 8
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
-- Load-on-demand. Testing the global alone lets addon load order decide whether
-- this feature exists at all.
local function ContainersAvailable()
    if _G.AuraContainerSortMethod == nil and C_AddOns and C_AddOns.LoadAddOn
        and C_AddOns.IsAddOnLoaded and not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") then
        pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer")
    end
    return _G.AuraContainerSortMethod ~= nil
end

function HT:CreateAnchor()
    if self.anchor then return end
    local db = self.db

    local frame = CreateFrame("Frame", "KE_HavocWarning", UIParent)
    frame:SetSize(ANCHOR_WIDTH, AnchorHeight(db))
    frame:SetFrameStrata(db.Strata or "MEDIUM")
    KE:ApplyFramePosition(frame, db.WarningPosition, db)
    self.anchor = frame
end

-- The engine's one legal creation window for this button. Everything drawn on it
-- has to be built here; outside it the button is not ours to touch, and even
-- asking whether it is shown is refused.
function HT:InitWarningButton(button)
    local db = self.db

    local text = button:CreateFontString(nil, "OVERLAY")
    -- One anchor point, deliberately. SetAllPoints would tie the string to a
    -- button whose size we cannot know.
    text:SetPoint("CENTER", button, "CENTER", 0, 0)
    KE:ApplyFontToText(text, db.FontFace, db.WarningFontSize, db.FontOutline)
    text:SetTextColor(unpack(db.WarningColor))
    text:SetText(WarningText(db))
    text:Show()
end

function HT:BuildContainer()
    if self.container then return end
    if not ContainersAvailable() then
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

    local added, slot = pcall(container.AddAuraSlot, container, "havoctarget", "HARMFUL|PLAYER", options)
    if DEBUG_HT then KE:Print("[HT] slot added=" .. tostring(added)) end
    if not added then return end

    -- A slot takes no part in the flow layout and MUST be anchored by hand. An
    -- unanchored frame has no position, so the engine matches the aura, builds
    -- the button, and draws it nowhere with no error to show for it.
    --
    -- pcall'd because these are refused outright on a container bound to an
    -- identity-restricted unit.
    if slot then
        local anchored = pcall(function()
            slot:ClearAllPoints()
            slot:SetPoint("CENTER", self.anchor, "CENTER", 0, 0)
            slot:SetSize(ANCHOR_WIDTH, AnchorHeight(self.db))
        end)
        if DEBUG_HT then
            KE:Print("[HT] slot anchoring " .. (anchored and "allowed" or "REFUSED"))
        end
    end

    pcall(container.SetUnit, container, "target")
    pcall(container.UpdateAllAuras, container)
    if container.SetEnabled then pcall(container.SetEnabled, container, true) end
    container:Show()

    self.container = container
end

---------------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------------
function HT:PLAYER_TARGET_CHANGED()
    if not self.container then return end
    -- Re-pointed rather than left to follow.
    local ok = pcall(self.container.SetUnit, self.container, "target")
    pcall(self.container.UpdateAllAuras, self.container)
    if DEBUG_HT then KE:Print("[HT] retargeted ok=" .. tostring(ok)) end
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
    self:RegisterEvent("PLAYER_TARGET_CHANGED")
    self:PLAYER_TARGET_CHANGED()
end

function HT:Deactivate()
    if not self.active then return end
    self.active = false
    self:UnregisterEvent("PLAYER_TARGET_CHANGED")
    if self.container then
        self.container:Hide()
    end
end

---------------------------------------------------------------------------------
-- Edit Mode
---------------------------------------------------------------------------------
function HT:RegWithEditMode()
    if KE.EditMode and not self.editModeRegistered then
        self:CreateAnchor()
        KE.EditMode:RegisterElement({
            key = "HavocTracker", displayName = "Havoc Warning", frame = self.anchor,
            module = self,
            getPosition = function() return self.db.WarningPosition end,
            setPosition = function(pos)
                self.db.WarningPosition = pos
                KE:ApplyFramePosition(self.anchor, self.db.WarningPosition, self.db)
            end,
            getParentFrame = function() return KE:ResolveAnchorFrame(self.db.anchorFrameType, self.db.ParentFrame) end,
            guiPath = "StatusTexts",
            guiTab = "HavocTracker",
        })
        self.editModeRegistered = true
    end
end

---------------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------------
function HT:ApplySettings()
    if not self:IsEnabled() then return end
    self:UpdateDB()
    if self.anchor then
        self.anchor:SetSize(ANCHOR_WIDTH, AnchorHeight(self.db))
        self.anchor:SetFrameStrata(self.db.Strata or "MEDIUM")
        KE:ApplyFramePosition(self.anchor, self.db.WarningPosition, self.db)
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
    KE:ApplyFontToText(self.previewText, db.FontFace, db.WarningFontSize, db.FontOutline)
    self.previewText:SetTextColor(unpack(db.WarningColor))
    self.previewText:SetText(WarningText(db))
    self.previewText:Show()
    self.anchor:Show()
end

function HT:HidePreview()
    self.previewing = false
    if self.previewText then self.previewText:Hide() end
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
    -- Deferred once: the spec is not reliably readable on the frame this runs.
    C_Timer.After(0.5, function()
        if self:IsEnabled() then self:EvaluateGate() end
    end)
end

function HT:OnDisable()
    self:Deactivate()
    self:UnregisterAllEvents()
    self:HidePreview()
    -- Clearing the guard is what lets a later enable register again.
    if KE.EditMode then KE.EditMode:UnregisterElement("HavocTracker") end
    self.editModeRegistered = false
end
