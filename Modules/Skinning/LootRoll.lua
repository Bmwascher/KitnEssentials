---@class KE
local KE = select(2, ...)
local S = KE.Skins

if not KitnEssentials then
    error("LootRoll: Addon object not initialized. Check file load order!")
    return
end

---@class LootRoll: AceModule, AceEvent-3.0
---@field editModeRegistered boolean? true while the EditMode element is registered; nil after OnDisable/UnregisterElement
---@field _barsWired boolean? true once SetupRollBars has registered START_LOOT_ROLL and unregistered UIParent's; nil after TeardownRollBars
---@field _bonusWired boolean? true once the Replace-mode BonusRollFrame re-anchor hook is installed; never cleared (hooksecurefunc is permanent)
---@field _previewBar table? the RollBar table currently showing the GUI preview; nil when no preview is active
---@field _previewTimer table? the C_Timer handle draining the preview; nil once cancelled or fired
local LR = KitnEssentials:NewModule("LootRoll", "AceEvent-3.0")

-- The profile-switch path and the ElvUI startup skip both gate on
-- name:find("^Skin") or module.keDeferToReload (Core/ProfileManager.lua,
-- Core/Main.lua). "LootRoll" fails the ^Skin test, and re-running Setup
-- live would reparent GroupLootContainer mid-session.
LR.keDeferToReload = true

local _G = _G
local hooksecurefunc = hooksecurefunc
local unpack = unpack -- luacheck: ignore 211/unpack
local CreateFrame = CreateFrame
local UIParent = UIParent
local GetLootRollItemInfo = GetLootRollItemInfo
local InCombatLockdown = InCombatLockdown
local GetTime = GetTime
local debugprofilestop = debugprofilestop
local string_format = string.format
local tostring = tostring

-- Flip to true to trace WHO moves GroupLootContainer and WHEN. Diagnoses the
-- "bonus roll jumps to the bottom then back" class of report: three triggers
-- are possible and only a live log separates them. Leave the instrumentation in
-- place after diagnosis -- free tracing if this regresses.
local DEBUG_LR = false

-- GetTime() is FRAME-STABLE -- every call inside one frame returns the same
-- value -- which is exactly the discriminator this bug needs: a correction
-- sharing the container's frame stamp happened same-frame and was never
-- visible, a later stamp rendered wrong first. debugprofilestop() then orders
-- events within that frame. A hand-rolled counter would need an OnUpdate, and
-- this needs neither.
local function LogState(tag)
    if not DEBUG_LR then return end
    local c = _G.GroupLootContainer
    if not c then
        KE:Print(string_format("[LR] %s | no GroupLootContainer", tag))
        return
    end
    local parent = c:GetParent()
    local point, _, relPoint, x, y = c:GetPoint(1)
    -- READ ONLY. Writing this table is what taints Blizzard's layout pass.
    local mgr = _G.UIParentBottomManagedFrameContainer
    local managed = mgr and mgr.showingFrames and mgr.showingFrames[c] ~= nil
    KE:Print(string_format(
        "[LR] %s | f=%.3f t=%.1fms | parent=%s | %s->%s %s,%s | shown=%s managed=%s combat=%s",
        tag, GetTime(), debugprofilestop(),
        tostring(parent and parent:GetName() or parent),
        tostring(point), tostring(relPoint), tostring(x), tostring(y),
        tostring(c:IsShown()), tostring(managed), tostring(InCombatLockdown())))
end
LR.LogState = LogState

function LR:UpdateDB()
    self.db = KE.db.profile.Skinning.LootRoll
end

function LR:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

local function RefreshQualityBorder(frame)
    if not frame then return end
    local bd = S.GetBackdrop(frame)
    if not bd then return end
    if not (LR.db and LR.db.Skin) then return end
    if LR.db.QualityBorder then
        local rollID = frame.rollID or (frame.GetID and frame:GetID())
        local quality
        if rollID and rollID > 0 and GetLootRollItemInfo then
            local _, _, _, q = GetLootRollItemInfo(rollID)
            quality = q
        end
        local qc = quality and _G.ITEM_QUALITY_COLORS and _G.ITEM_QUALITY_COLORS[quality]
        if qc then
            bd:SetBackdropBorderColor(qc.r, qc.g, qc.b, 1)
            return
        end
    end
    bd:SetBackdropBorderColor(unpack(S.borderColor))
end

local function SkinRollFrame(frame)
    if not frame then return end
    if not S:IsActive() then return end
    if S.data(frame).skinned then
        RefreshQualityBorder(frame)
        return
    end

    S.StripTextures(frame)
    S.Backdrop(frame)

    local iconFrame = frame.IconFrame or frame.Item
    local icon = (iconFrame and (iconFrame.Icon or iconFrame.icon)) or frame.Icon
    if icon and icon.SetTexCoord then S.Icon(icon, true) end
    if iconFrame then
        if iconFrame.IconBorder and iconFrame.IconBorder.SetAlpha then iconFrame.IconBorder:SetAlpha(0) end
        if iconFrame.NormalTexture and iconFrame.NormalTexture.SetAlpha then iconFrame.NormalTexture:SetAlpha(0) end
    end

    local bar = frame.Timer or frame.Bar or frame.StatusBar
    if bar and bar.SetStatusBarTexture then S.StatusBar(bar) end

    if frame.Name and frame.Name.SetFont then S.SetFont(frame.Name, 12) end

    S.data(frame).skinned = true
    RefreshQualityBorder(frame)
end

local function SkinAllRollFrames(container)
    if not LR.db or not LR.db.Skin then return end
    local maxN = (container and container.maxIndex) or 10
    for i = 1, maxN do
        SkinRollFrame(_G["GroupLootFrame" .. i])
    end
    if container and container.rollFrames then
        for _, f in pairs(container.rollFrames) do SkinRollFrame(f) end
    end
end
LR.SkinAllRollFrames = SkinAllRollFrames

-- Stands in for the container as the thing the roll frames hang off. Ours,
-- so sizing and anchoring it is free; empty, so it draws nothing.
function LR:GetStackAnchor()
    if self.stackAnchor then return self.stackAnchor end
    local a = CreateFrame("Frame", "KE_LootRollStackAnchor", UIParent)
    a:SetSize(1, 1)
    a:EnableMouse(false)
    self.stackAnchor = a
    return a
end

-- Blizzard's own line from GroupLootContainer_Update, with the anchor frame
-- passed in: slot i's CENTER sits reservedSize * (i - 0.5) above the stack's
-- bottom edge. Passing the container itself hands the frames back unchanged.
local function StackRollFrames(c, anchor)
    local rolls = c.rollFrames
    if type(rolls) ~= "table" then return end
    local reserved = c.reservedSize or 100
    for i = 1, (c.maxIndex or 0) do
        local f = rolls[i]
        if f and f.ClearAllPoints then
            f:ClearAllPoints()
            f:SetPoint("CENTER", anchor, "BOTTOM", 0, reserved * (i - 1 + 0.5))
        end
    end
end

-- `why` is DEBUG_LR-only: it names the caller in the trace. Probe run 1
-- logged an ApplyPosition whose "before" state was already
-- correct, and there was no way to tell which of the four call sites produced
-- it -- Setup, the GLC_Update hook, the OnShow hook, or an external GUI/
-- EditMode call. Untagged, the trace could not answer its own question.
-- Callers that do not pass it show as "external", which is itself the
-- answer for the GUI and EditMode paths.
function LR:ApplyPosition(why)
    if not self.db then return end

    if self.db.Replace and self.RollBars_Anchor and self._barsWired then
        self:RollBars_Anchor()
        return
    end
    local c = _G.GroupLootContainer
    if not c then return end
    -- The roll FRAMES are moved, never the container. The container is
    -- managed by the game's bottom-edge layout, and every way out of that
    -- pass -- flag writes or a reparent -- is state the SECURE pass reads.
    -- The frames are ordinary unmanaged children, so writing their points
    -- is legal, in combat included: a roll that starts mid-fight lands at
    -- the chosen spot instead of jumping there when the fight ends.
    if not self.db.Reposition then
        StackRollFrames(c, c)
        return
    end

    -- Anchored by its BOTTOM, not its centre.
    --
    -- GroupLootContainer_Update sets the container's height to
    -- reservedSize * (number of rolls) and anchors each roll frame
    -- relative to the container's BOTTOM. With a CENTER anchor the
    -- bottom edge therefore moves every time a roll is added or
    -- expires, and every roll already on screen jumps with it -- a
    -- single roll sits at y+0, but the moment a second appears the
    -- first drops half a row. Anchoring the bottom pins the first roll
    -- and lets the stack grow upward.
    --
    -- The saved Point is honoured if the user has moved the mover; only
    -- the DEFAULT changes, and a legacy CENTER value is converted so
    -- the stack lands where it used to for one roll.
    local p = self.db.Position or {}
    local point, y = p.Point or "BOTTOM", p.Y or 0
    if point == "CENTER" then
        point = "BOTTOM"
        y = y - (c:GetHeight() or 0) / 2
    end

    -- Matched to the container so a corner or edge anchor lands exactly
    -- where the container would have. Blizzard has already sized it for
    -- this pass; the fallbacks only matter before the first update.
    local a = self:GetStackAnchor()
    local w, h = c:GetWidth() or 0, c:GetHeight() or 0
    a:SetSize(w > 0 and w or 340, h > 0 and h or 100)
    a:ClearAllPoints()
    a:SetPoint(point, UIParent, p.RelPoint or "CENTER", p.X or 0, y)

    local tag = "ApplyPosition<" .. (why or "external") .. ">"
    LogState(tag .. ":before")
    StackRollFrames(c, a)
    LogState(tag .. ":after")
end

function LR:GetMover()
    if self.mover then return self.mover end
    local m = CreateFrame("Frame", "KE_LootRollMover", UIParent, "BackdropTemplate")
    m:SetSize(340, 90)
    m:SetFrameStrata("FULLSCREEN_DIALOG")
    m:SetClampedToScreen(true)
    -- ("their own unlock anchors on top of the addon's
    -- toggle anchors ... causing position mismatches"): the mover's own
    -- drag scripts are gone and it never Shows itself any more. It had
    -- been a SECOND draggable anchor sitting on the same frame EditMode
    -- already owns, with its own OnDragStop that force-wrote CENTER/CENTER
    -- regardless of what EditMode had just stored -- so dragging one moved
    -- the other's idea of the anchor. /kes edit is the single anchor UI
    -- now; this frame is a positioned, invisible proxy that EditMode
    -- overlays (its overlay does SetAllPoints(target), which needs the
    -- proxy anchored but not shown, and EditMode draws its own border,
    -- tint and label -- so ours are removed rather than doubled).
    self.mover = m
    self:SyncMover()
    m:Hide()
    return m
end

-- Re-anchor the proxy from the db. Called at creation, by EditMode's
-- setPosition, and by the GUI offset sliders so the /kes edit overlay
-- tracks slider edits live.
function LR:SyncMover()
    local m = self.mover
    if not m then return end
    local p = self.db and self.db.Position or {}
    m:ClearAllPoints()
    m:SetPoint(p.Point or "BOTTOM", UIParent, p.RelPoint or "CENTER", p.X or 0, p.Y or 0)
end

-- Replace mode: put the BONUS ROLL prompt where the roll bars are.
--
-- Bonus rolls never become KE roll bars -- they arrive on
-- SPELL_CONFIRMATION_PROMPT, not START_LOOT_ROLL, so SetupRollBars'
-- unregister does not intercept them. Blizzard hands BonusRollFrame to
-- GroupLootContainer and anchors it there, which in Replace mode leaves it at
-- Blizzard's bottom-centre managed spot while every other roll obeys the
-- user's position.
--
-- We re-anchor the FRAME rather than moving the container, which is what the
-- legacy branch does. That avoids the managed-frame system entirely:
-- BonusRollFrame is parented to UIParent and is a plain <Frame>
-- (Blizzard_UIPanels_Game/Mainline/GroupLootFrame.xml), so ClearAllPoints
-- and SetPoint on it are legal in combat and taint nothing. And it is
-- sufficient: GroupLootFrame.lua is the ONLY place any roll frame is
-- ever anchored, and both entry paths -- AddFrame and ReplaceFrame -- end in
-- GroupLootContainer_Update, the function we post-hook.
--
-- Only the PROMPT. BonusRollLootWonFrame / BonusRollMoneyWonFrame, which
-- replace it once the roll resolves, are loot toasts: they set AlertFrame as
-- their alert container (GroupLootFrame.lua) and are handed to
-- AlertFrame:AddAlertFrame, so the alert chain owns their placement and
-- re-anchoring them would just fight it.
local function AnchorBonusRoll()
    if not LR:IsEnabled() then return end
    local db = LR.db
    if not db or not db.Replace then return end

    local f = _G.BonusRollFrame
    if not f or not f:IsShown() then return end

    -- Bar 1's own anchor and defaults (LootRollBars.lua), so the prompt
    -- lands where a roll bar would. NOT the legacy branch's BOTTOM/0 pair, and
    -- emphatically not its CENTER->BOTTOM conversion -- that exists because the
    -- legacy container grows upward as rolls stack, and this is one fixed-size
    -- frame anchored directly.
    local p = db.Position or {}
    f:ClearAllPoints()
    f:SetPoint(p.Point or "CENTER", UIParent, p.RelPoint or "CENTER", p.X or 0, p.Y or 250)
    LogState("AnchorBonusRoll")
end
LR.AnchorBonusRoll = AnchorBonusRoll

function LR:Setup()

    -- Installed for BOTH modes and guarded inside on db.Replace, because
    -- hooksecurefunc cannot be undone. Its own flag, not _wired: _wired
    -- belongs to the legacy branch that Setup never reaches in Replace mode.
    if not self._bonusWired and type(_G.GroupLootContainer_Update) == "function" then
        hooksecurefunc("GroupLootContainer_Update", AnchorBonusRoll)
        self._bonusWired = true
    end

    if self.db.Replace then
        if self.SetupRollBars then self:SetupRollBars() end
        return
    end
    if self.TeardownRollBars then self:TeardownRollBars() end

    local c = _G.GroupLootContainer
    if not c then return end

    -- Probe run 1 captured no Container:OnShow at all, and the two
    -- explanations need different fixes: the container was already shown when
    -- the hooks went in (so OnShow had already fired and we can never see it),
    -- or the hooks were not installed yet. This line dates the install and
    -- records whether the container was already up at that moment.
    LogState("Setup:pre-wire wired=" .. tostring(self._wired == true))

    if not self._wired then
        -- Each callback below bails first when the module is disabled --
        -- hooksecurefunc cannot be undone, so without this test
        -- KitnEssentials:DisableModule("LootRoll") left the container
        -- getting repositioned and roll frames getting skinned anyway.
        if type(_G.GroupLootContainer_Update) == "function" then
            hooksecurefunc("GroupLootContainer_Update", function(container)
                LogState("GLC_Update:hook")
                if not LR:IsEnabled() then return end
                LR:ApplyPosition("glc-update")
                SkinAllRollFrames(container)
            end)
        end

        c:HookScript("OnShow", function()
            -- Logged BEFORE the enabled guard: Blizzard's AddManagedFrame has
            -- already run by the time this fires (it is the mixin's own OnShow),
            -- so this line records the state the managed system just left the
            -- container in, which is the whole question.
            LogState("Container:OnShow")
            if not LR:IsEnabled() then return end
            LR:ApplyPosition("container-onshow")
        end)
        c:HookScript("OnHide", function() LogState("Container:OnHide") end)
        if type(_G.GroupLootContainer_AddFrame) == "function" then
            hooksecurefunc("GroupLootContainer_AddFrame", function(_, frame)
                if not LR:IsEnabled() then return end
                if LR.db.Skin then SkinRollFrame(frame) end
            end)
        end

        self._wired = true
    end

    self:ApplyPosition("setup")
    SkinAllRollFrames(c)
end

function LR:ApplySettings()
    if not self.db.Enabled then return end
    self:Setup()
end

function LR:RegisterEditMode()
    if not KE.EditMode or self.editModeRegistered then return end
    self.editModeRegistered = true
    local mover = self:GetMover()
    KE.EditMode:RegisterElement({
        key = "LootRoll",
        module = self,
        -- Neither replacing the frames nor repositioning them means nothing
        -- owns this position, so there is nothing to drag.
        isEligible = function()
            return (self.db.Replace or self.db.Reposition) and true or false
        end,
        displayName = "Loot Roll",
        frame = mover,
        getPosition = function()
            local p = self.db.Position or {}
            self:SyncMover()
            return {
                AnchorFrom = p.Point or "BOTTOM",
                AnchorTo = p.RelPoint or "CENTER",
                XOffset = p.X or 0,
                YOffset = p.Y or 0,
            }
        end,
        setPosition = function(pos)
            self.db.Position.Point = pos.AnchorFrom
            self.db.Position.RelPoint = pos.AnchorTo
            self.db.Position.X = pos.XOffset
            self.db.Position.Y = pos.YOffset
            self:SyncMover()
            self:ApplyPosition("editmode")
        end,
        -- guiPath is a SIDEBAR ITEM ID and there is no sidebar
        -- item "LootRoll" -- Open Settings was silently falling through to
        -- "just open the GUI". These sections live in the consolidated
        -- Blizzard Frames tab, so route through it (KE's sidebar id:
        -- GUI/GUIMain/GUI-MainFrame.lua). guiContext is dropped here:
        -- KE's GUIFrame:OpenPage stores it as pendingContext and nothing
        -- reads it (GUI/GUIWidgets/GUI-Sidebar.lua). guiTab IS set --
        -- it is KE's live equivalent of the same intent, seeding
        -- GUIFrame.tabbedPageState so Open Settings lands on the right
        -- subtab of the tabbed Blizzard Frames page (Core/EditMode.lua,
        -- :1122-1126). The subtab id itself is created in Task 6.
        guiPath = "SkinBlizzardFrames",
        guiTab = "SkinBlizzardFramesLootRoll",
    })
end

function LR:OnEnable()
    if KE:ShouldNotLoadModule() then return end
    if not self.db.Enabled then return end
    self:Setup()
    self:RegisterEditMode()
end

function LR:OnDisable()
    if self.mover then self.mover:Hide() end
    -- leave /kes edit when the module does.
    if KE.EditMode then
        KE.EditMode:UnregisterElement("LootRoll")
        self.editModeRegistered = nil
    end
    if self.TeardownRollBars then self:TeardownRollBars() end
    -- Hand the roll frames back to the container's own stack. Nothing else to
    -- undo: the container was never moved and no field of it was written.
    local c = _G.GroupLootContainer
    if c then StackRollFrames(c, c) end
end
