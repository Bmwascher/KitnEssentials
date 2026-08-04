---@class KE
local KE = select(2, ...)
local S = KE.Skins

if not KitnEssentials then
    error("LootRoll: Addon object not initialized. Check file load order!")
    return
end

---@class LootRoll: AceModule, AceEvent-3.0
---@field _reassertPending boolean? true while a ReassertPosition retry is queued; nil once it settles
---@field _regenPending boolean? true while WaitForRegen's PLAYER_REGEN_ENABLED watcher is armed; nil once it fires
---@field editModeRegistered boolean? true while the EditMode element is registered; nil after OnDisable/UnregisterElement
---@field _pendingRestore boolean? true while OnDisable's combat-deferred GroupLootContainer restore watcher is armed; nil once it fires
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
local C_Timer = C_Timer
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

-- `why` is DEBUG_LR-only: it names the caller in the trace. Probe run 1
-- logged an ApplyPosition whose "before" state was already
-- correct, and there was no way to tell which of the six call sites produced
-- it -- Setup, the GLC_Update hook, the OnShow hook, either ReassertPosition
-- tick, the regen watcher, or an external GUI/EditMode call. Untagged, the
-- trace could not answer its own question. Callers that do not pass it show as
-- "external", which is itself the answer for the GUI and EditMode paths.
function LR:ApplyPosition(why)
    if not self.db then return end

    if self.db.Replace and self.RollBars_Anchor and self._barsWired then
        self:RollBars_Anchor()
        return
    end
    local c = _G.GroupLootContainer
    if not c then return end
    -- layout removal is by REPARENTING (see the Unmanage note
    -- below) -- the ignoreInLayout flag writes are gone; that boolean
    -- is read inside the SECURE managed-layout pass and writing it from
    -- here taints the whole UIParent_ManageFramePositions execution.
    -- Restore path: hand the container back to its original managed
    -- parent; Reposition path: ensure it's unmanaged, then position.
    -- Repositioning an unmanaged frame is legal, but the reparent that
    -- unmanages it is not safe in combat -- so bail, and come back the
    -- moment combat ends rather than waiting for the next roll event.
    -- Without that the container sat at Blizzard's managed spot for the
    -- rest of the fight and then jumped.
    if InCombatLockdown() then
        LR:WaitForRegen()
        return
    end
    if not self.db.Reposition then
        if self._origGLCParent and c:GetParent() ~= self._origGLCParent then
            c:SetParent(self._origGLCParent)
        end
        return
    end
    if c:GetParent() ~= _G.UIParent then
        self._origGLCParent = self._origGLCParent or c:GetParent()
        c:SetParent(_G.UIParent)
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

    local tag = "ApplyPosition<" .. (why or "external") .. ">"
    LogState(tag .. ":before")
    c:ClearAllPoints()
    c:SetPoint(point, UIParent, p.RelPoint or "CENTER", p.X or 0, y)
    LogState(tag .. ":after")
end

-- Single watcher: unmanage (if still pending) then position, in that
-- order -- positioning a frame that is still managed would be undone by
-- the next layout pass.
-- Re-applies the position once Blizzard's managed layout has settled.
-- Two frames rather than one: the layout is dirty-marked and can settle
-- on either of the next two.
function LR:ReassertPosition()
    if self._reassertPending then
        LogState("ReassertPosition:already-pending")
        return
    end
    self._reassertPending = true
    LogState("ReassertPosition:armed")

    -- DEVIATION A (task-3 FIX ROUND 2): both timer callbacks below are two
    -- of the five async re-entries the module-disabled guard covers (see
    -- the longer note at the hook installs below). Each bails when the
    -- module is disabled, but must still clear _reassertPending first --
    -- otherwise a disable mid-flight would leave the flag stuck true and
    -- silently block every ReassertPosition call for the rest of the
    -- session, even after the module is re-enabled.
    C_Timer.After(0, function()
        LogState("ReassertPosition:tick1")
        if not LR:IsEnabled() then
            LR._reassertPending = nil
            return
        end
        self:ApplyPosition("reassert-tick1")
        C_Timer.After(0, function()
            LogState("ReassertPosition:tick2")
            self._reassertPending = nil
            if not LR:IsEnabled() then return end
            self:ApplyPosition("reassert-tick2")
        end)
    end)
end

function LR:WaitForRegen()
    if self._regenPending then
        LogState("WaitForRegen:already-pending")
        return
    end
    self._regenPending = true
    LogState("WaitForRegen:armed")

    local w = CreateFrame("Frame")
    w:RegisterEvent("PLAYER_REGEN_ENABLED")
    w:SetScript("OnEvent", function(f)
        f:UnregisterAllEvents()
        LR._regenPending = nil
        LogState("WaitForRegen:fired")
        -- DEVIATION A (task-3 FIX ROUND 2): the watcher must always disarm
        -- itself (UnregisterAllEvents + clear the pending flag above), but
        -- must not re-apply the feature once the module has been disabled
        -- -- see the longer note at the hook installs below.
        if not LR:IsEnabled() then return end
        if LR._unmanage then LR._unmanage() end
        LR:ApplyPosition("regen-watcher")
    end)
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
    -- hooksecurefunc cannot be undone -- the DEVIATION A lesson below. Its own
    -- flag, not _wired: _wired belongs to the legacy branch that Setup never
    -- reaches in Replace mode.
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
        -- (taint report: ADDON_ACTION_BLOCKED on
        -- UIParentRightManagedFrameContainer:ClearAllPoints during a
        -- stance-bar update): writing UIPARENT_MANAGED_FRAME_POSITIONS
        -- (even nil) taints the table, and setting ignoreInLayout on a
        -- managed child taints the boolean the SECURE layout pass reads
        -- -- either poisons UIParent_ManageFramePositions, which then
        -- detonates on the next managed-layout update anywhere (the
        -- stance bar, in the report). Reparenting the container out of
        -- the managed hierarchy needs no field writes at all, so it is
        -- taint-free, and our ClearAllPoints/SetPoint in ApplyPosition
        -- are then writes on a frame Blizzard's layout no longer walks.
        -- Deferred to REGEN_ENABLED if a roll wires up mid-combat.
        --
        -- What the reparent does and does NOT buy -- two separate layers,
        -- and it only exits one of them. Earlier comments here and below
        -- each described one layer as if it were the whole story:
        --
        --  1. LAYOUT CHILD ENUMERATION -- exited. BaseLayoutMixin's
        --     GetLayoutChildren walks GetChildren()
        --     (Blizzard_SharedXML/LayoutFrame.lua), so once the
        --     container is reparented to UIParent instead,
        --     UIParentBottomManagedFrameContainer's Layout() genuinely
        --     cannot reach it.
        --  2. MANAGER MEMBERSHIP -- kept. The frame stays in the container's
        --     showingFrames table (written in Blizzard_UIParent/Shared/
        --     UIParent.lua). UpdateManagedFrames iterates THAT table, not the
        --     child list, and its UpdateFrame reparents the frame back. Every
        --     hide/show cycle also re-runs OnShow -> AddManagedFrame.
        --
        -- So the reparent alone cannot hold the position: the layout pass
        -- puts the container back at the BOTTOM of the screen and our hook
        -- has to move it again. That is the visible "jumps to the bottom,
        -- then back" the bug report describes. Re-asserting
        -- after the layout settles is what makes it stick today.
        local function Unmanage()
            if c:GetParent() ~= _G.UIParent then
                LR._origGLCParent = LR._origGLCParent or c:GetParent()
                c:SetParent(_G.UIParent)
            end
        end
        LR._unmanage = Unmanage
        if InCombatLockdown() then
            LR:WaitForRegen()
        else
            Unmanage()
        end

        -- The three hooks below are the layer-2 mitigation described above:
        -- they re-assert our position after Blizzard's managed layout has
        -- moved the container. Cheap -- they only do work while a roll is
        -- on screen.
        --
        -- These three hooks are PERMANENT -- hooksecurefunc cannot be undone.
        -- Without an enabled test in each callback,
        -- KitnEssentials:DisableModule("LootRoll") left the container getting
        -- repositioned and roll frames getting skinned anyway, so the user's
        -- off-switch did not turn the feature off. Each callback below bails
        -- first when the module is disabled.
        --
        -- The same guard is needed on two ASYNC re-entries
        -- these hooks feed into, not just here -- five paths total.
        -- WaitForRegen's PLAYER_REGEN_ENABLED watcher and both of
        -- ReassertPosition's C_Timer.After callbacks call ApplyPosition
        -- on a later frame, after this Setup call has returned; a disable
        -- that lands in the gap between arming one of those and it firing
        -- otherwise re-applies the feature anyway. Worse, in combat that
        -- race pits WaitForRegen's watcher against Deviation B's own
        -- restore watcher on the SAME PLAYER_REGEN_ENABLED event, and
        -- registration order decides which one wins -- the unfavourable
        -- order undoes the disable-time restore until reload. Both
        -- watchers now check LR:IsEnabled() before touching the container
        -- (see WaitForRegen and ReassertPosition above), while still
        -- disarming/clearing their own pending flags unconditionally.
        --
        -- ApplyPosition itself stays deliberately UNGUARDED: every
        -- synchronous caller (Setup, the GUI position sliders, Edit
        -- Mode's setPosition) only runs while the module is legitimately
        -- enabled, and a blanket guard inside ApplyPosition would risk
        -- breaking those live paths for no gain -- the leak is strictly
        -- in the async re-entries, so that's where the guard belongs.
        if type(_G.GroupLootContainer_Update) == "function" then
            hooksecurefunc("GroupLootContainer_Update", function(container)
                LogState("GLC_Update:hook")
                if not LR:IsEnabled() then return end
                LR:ApplyPosition("glc-update")
                SkinAllRollFrames(container)
                LR:ReassertPosition()
            end)
        end

        -- ApplyPosition FIRST, then ReassertPosition -- the same order the
        -- GroupLootContainer_Update hook above uses. ReassertPosition alone
        -- puts its first correction a C_Timer.After(0) away, so the container
        -- renders for one frame at Blizzard's managed spot before moving.
        c:HookScript("OnShow", function()
            -- Logged BEFORE the enabled guard: Blizzard's AddManagedFrame has
            -- already run by the time this fires (it is the mixin's own OnShow),
            -- so this line records the state the managed system just left the
            -- container in, which is the whole question.
            LogState("Container:OnShow")
            if not LR:IsEnabled() then return end
            LR:ApplyPosition("container-onshow")
            LR:ReassertPosition()
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
            if KE.GUIFrame and KE.GUIFrame.RefreshContent then
                pcall(function() KE.GUIFrame:RefreshContent("LootRoll") end)
            end
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
    local c = _G.GroupLootContainer
    -- restore by reparenting (flag writes taint the secure
    -- layout pass).
    --
    -- This is NOT combat-deferred implicitly by the next out-of-combat
    -- ApplyPosition, which is the tempting reading. On the path that actually
    -- reaches OnDisable, ApplyPosition's restore
    -- branch only runs when self.db.Reposition is FALSE, so a user who
    -- disables the MODULE while leaving Reposition on (the GUI's normal
    -- toggle) got no restore at all, in or out of combat. When combat
    -- blocks the reparent below, set a pending flag and watch for
    -- PLAYER_REGEN_ENABLED to finish the restore -- a dedicated one-shot
    -- watcher, NOT LR:WaitForRegen(), which also calls
    -- _unmanage()/ApplyPosition() and would re-apply the very feature
    -- the user just disabled.
    if c and LR._origGLCParent and c:GetParent() ~= LR._origGLCParent then
        if InCombatLockdown() then
            -- Diagnostic state only -- nothing reads this flag or gates on
            -- it. The watcher below is already one-shot (UnregisterAllEvents
            -- on first fire) and idempotent (re-checks _origGLCParent vs.
            -- the current parent before setting), so a later reader should
            -- not assume _pendingRestore is what prevents double-arming.
            LR._pendingRestore = true
            local w = CreateFrame("Frame")
            w:RegisterEvent("PLAYER_REGEN_ENABLED")
            w:SetScript("OnEvent", function(f)
                f:UnregisterAllEvents()
                LR._pendingRestore = nil
                if LR._origGLCParent and c:GetParent() ~= LR._origGLCParent then
                    c:SetParent(LR._origGLCParent)
                end
            end)
        else
            c:SetParent(LR._origGLCParent)
        end
    end
end
