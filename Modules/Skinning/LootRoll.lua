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
local LR = KitnEssentials:NewModule("LootRoll", "AceEvent-3.0")

-- The profile-switch path and the ElvUI startup skip both gate on
-- name:find("^Skin") or module.keDeferToReload (Core/ProfileManager.lua:458,
-- Core/Main.lua:174). "LootRoll" fails the ^Skin test, and re-running Setup
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

function LR:ApplyPosition()
    if not self.db then return end

    if self.db.Replace and self.RollBars_Anchor and self._barsWired then
        self:RollBars_Anchor()
        return
    end
    local c = _G.GroupLootContainer
    if not c then return end
    -- v3.5.755: layout removal is by REPARENTING (see the Unmanage note
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

    c:ClearAllPoints()
    c:SetPoint(point, UIParent, p.RelPoint or "CENTER", p.X or 0, y)
end

-- Single watcher: unmanage (if still pending) then position, in that
-- order -- positioning a frame that is still managed would be undone by
-- the next layout pass.
-- Re-applies the position once Blizzard's managed layout has settled.
-- Two frames rather than one: the layout is dirty-marked and can settle
-- on either of the next two.
function LR:ReassertPosition()
    if self._reassertPending then return end
    self._reassertPending = true

    C_Timer.After(0, function()
        self:ApplyPosition()
        C_Timer.After(0, function()
            self._reassertPending = nil
            self:ApplyPosition()
        end)
    end)
end

function LR:WaitForRegen()
    if self._regenPending then return end
    self._regenPending = true

    local w = CreateFrame("Frame")
    w:RegisterEvent("PLAYER_REGEN_ENABLED")
    w:SetScript("OnEvent", function(f)
        f:UnregisterAllEvents()
        LR._regenPending = nil
        if LR._unmanage then LR._unmanage() end
        LR:ApplyPosition()
    end)
end

function LR:GetMover()
    if self.mover then return self.mover end
    local m = CreateFrame("Frame", "KE_LootRollMover", UIParent, "BackdropTemplate")
    m:SetSize(340, 90)
    m:SetFrameStrata("FULLSCREEN_DIALOG")
    m:SetClampedToScreen(true)
    -- v3.5.871 ("their own unlock anchors on top of the addon's
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

function LR:Setup()

    if self.db.Replace then
        if self.SetupRollBars then self:SetupRollBars() end
        return
    end
    if self.TeardownRollBars then self:TeardownRollBars() end

    local c = _G.GroupLootContainer
    if not c then return end

    if not self._wired then
        -- v3.5.755 (taint report: ADDON_ACTION_BLOCKED on
        -- UIParentRightManagedFrameContainer:ClearAllPoints during a
        -- stance-bar update): writing UIPARENT_MANAGED_FRAME_POSITIONS
        -- (even nil) taints the table, and setting ignoreInLayout on a
        -- managed child taints the boolean the SECURE layout pass reads
        -- -- either poisons UIParent_ManageFramePositions, which then
        -- detonates on the next managed-layout update anywhere (the
        -- stance bar, in the report). The taint-free removal is
        -- REPARENTING the container out of the managed hierarchy: the
        -- layout pass enumerates container children secure-side, so a
        -- frame that simply isn't a child anymore needs no field writes
        -- at all. Our ClearAllPoints/SetPoint in ApplyPosition are then
        -- writes on an unmanaged frame -- legal. Deferred to
        -- REGEN_ENABLED if a roll wires up mid-combat.
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

        -- GroupLootContainer inherits UIParentBottomManagedFrameTemplate
        -- and its XML parent is ALREADY UIParent, so reparenting removes
        -- nothing -- the managed system tracks it through layoutParent.
        -- Its layout pass re-anchors the frame to the BOTTOM of the
        -- screen, and it runs AFTER our hook (Layout marks dirty and
        -- settles on a later frame). Result: the container appears where
        -- the user put it, then drops to the bottom.
        --
        -- Re-asserting on the frame after the layout has settled is what
        -- makes it stick. Cheap: it only runs while a roll is on screen.
        --
        -- DEVIATION (task-3, corrects <REF>:266-279): these three hooks
        -- are PERMANENT -- hooksecurefunc cannot be undone, and none of
        -- the reference's three callbacks tested whether the module was
        -- still enabled, so KitnEssentials:DisableModule("LootRoll") left
        -- the container getting repositioned and roll frames getting
        -- skinned anyway -- the user's off-switch did not turn the
        -- feature off. Each callback below now bails first when the
        -- module is disabled.
        if type(_G.GroupLootContainer_Update) == "function" then
            hooksecurefunc("GroupLootContainer_Update", function(container)
                if not LR:IsEnabled() then return end
                LR:ApplyPosition()
                SkinAllRollFrames(container)
                LR:ReassertPosition()
            end)
        end

        c:HookScript("OnShow", function()
            if not LR:IsEnabled() then return end
            LR:ReassertPosition()
        end)
        if type(_G.GroupLootContainer_AddFrame) == "function" then
            hooksecurefunc("GroupLootContainer_AddFrame", function(_, frame)
                if not LR:IsEnabled() then return end
                if LR.db.Skin then SkinRollFrame(frame) end
            end)
        end

        self._wired = true
    end

    self:ApplyPosition()
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
            self:ApplyPosition()
            if KE.GUIFrame and KE.GUIFrame.RefreshContent then
                pcall(function() KE.GUIFrame:RefreshContent("LootRoll") end)
            end
        end,
        -- v3.5.871: guiPath is a SIDEBAR ITEM ID and there is no sidebar
        -- item "LootRoll" -- Open Settings was silently falling through to
        -- "just open the GUI". These sections live in the consolidated
        -- Blizzard Frames tab, so route through it (KE's sidebar id:
        -- GUI/GUIMain/GUI-MainFrame.lua:123). guiContext is dropped here:
        -- KE's GUIFrame:OpenPage stores it as pendingContext and nothing
        -- reads it (GUI/GUIWidgets/GUI-Sidebar.lua:756). guiTab IS set --
        -- it is KE's live equivalent of the same intent, seeding
        -- GUIFrame.tabbedPageState so Open Settings lands on the right
        -- subtab of the tabbed Blizzard Frames page (Core/EditMode.lua:56,
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
    -- v3.5.871: leave /kes edit when the module does.
    if KE.EditMode then
        KE.EditMode:UnregisterElement("LootRoll")
        self.editModeRegistered = nil
    end
    if self.TeardownRollBars then self:TeardownRollBars() end
    local c = _G.GroupLootContainer
    -- v3.5.755: restore by reparenting (flag writes taint the secure
    -- layout pass).
    --
    -- DEVIATION (task-3, corrects <REF>:347-350): the reference's own
    -- comment here claimed this was "combat-deferred implicitly -- next
    -- ApplyPosition out of combat also restores", which is false on the
    -- path that actually reaches OnDisable: ApplyPosition's restore
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
