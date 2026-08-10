-- ╔══════════════════════════════════════════════════════════╗
-- ║  EditMode.lua                                            ║
-- ║  Purpose: In-game frame positioning interface — drag to  ║
-- ║           reposition, nudge tool, anchor/strata controls.║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local Theme = KE.Theme

local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local pairs = pairs
local ipairs = ipairs
local GetCursorPosition = GetCursorPosition
local IsShiftKeyDown = IsShiftKeyDown
local IsControlKeyDown = IsControlKeyDown
local tonumber = tonumber
local IsMouseButtonDown = IsMouseButtonDown
local STANDARD_TEXT_FONT = STANDARD_TEXT_FONT
local UIParent = UIParent

local EditMode = {}
KE.EditMode = EditMode

EditMode.isActive = false
EditMode.registeredElements = {}
EditMode.overlayFrames = {}
EditMode.selectedElementKey = nil
EditMode.nudgeFrame = nil
EditMode.isShiftFaded = false
EditMode.activeCategory = nil

local BORDER_SIZE = 2
local FILL_ALPHA = 0.25
local TEXT_FONT_SIZE = 14
local SHIFT_FADE_ALPHA = 0.1
local CATEGORY_ROW_HEIGHT = 20

-- Categories are the sidebar's own sections. A nil id means no filter.
-- The sidebar also has settings_section and optimize_section; neither registers
-- a mover, so a button for them would only ever be dimmed.
local CATEGORIES = {
    { label = "All" },
    { id = "combat_section",   label = "Combat" },
    { id = "aura_section",     label = "Auras" },
    { id = "class_section",    label = "Class" },
    { id = "qol_section",      label = "QoL" },
    { id = "dungeons_section", label = "Dungeons" },
    { id = "skinning_section", label = "Skinning" },
}

function EditMode:IsSelectableCategory(sectionId)
    if not sectionId then return false end
    for _, category in ipairs(CATEGORIES) do
        if category.id == sectionId then return true end
    end
    return false
end

---------------------------------------------------------------------------------
-- Grid, Guides and Snapping
---------------------------------------------------------------------------------

local function GuideDB()
    return KE.db and KE.db.global and KE.db.global.EditModeGuides
end

function EditMode:GetGuideSetting(name)
    local db = GuideDB()
    if not db then return nil end
    return db[name]
end

function EditMode:SetGuideSetting(name, value)
    local db = GuideDB()
    if not db then return end
    db[name] = value
end

-- Captured once per drag. Re-reading the settings mid-drag would let the
-- live update and the commit disagree about what they were snapping to.
function EditMode:BuildSnapContext()
    local width, height = UIParent:GetWidth(), UIParent:GetHeight()
    return {
        enabled = self:GetGuideSetting("Snapping") and true or false,
        spacing = tonumber(self:GetGuideSetting("Spacing")) or 32,
        -- Whole units. The screen centre is fractional at a non-perfect UI
        -- scale or an odd physical dimension, and a fractional lattice would
        -- push every single snap through the offset rounding downstream.
        originX = math.floor((width or 0) / 2 + 0.5),
        originY = math.floor((height or 0) / 2 + 0.5),
    }
end

---------------------------------------------------------------------------------
-- Element Registration
---------------------------------------------------------------------------------

function EditMode:RegisterElement(config)
    if not config or not config.key then return end
    if not config.frame and not config.frameName then return end
    if not config.getPosition or not config.setPosition then return end

    self.registeredElements[config.key] = {
        key = config.key,
        displayName = config.displayName or config.key,
        frame = config.frame,
        frameName = config.frameName,
        getPosition = config.getPosition,
        setPosition = config.setPosition,
        getParentFrame = config.getParentFrame,
        getAnchorFrom = config.getAnchorFrom,
        module = config.module,
        isEligible = config.isEligible,
        getOverlayInset = config.getOverlayInset,
        guiPath = config.guiPath,
        guiTab = config.guiTab,
        guiContext = config.guiContext,
    }

    -- If edit mode is already active, create overlay for this element
    if self.isActive then
        self:CreateOverlayForElement(config.key)
        self:UpdateCategorySelector()
    end
end

function EditMode:UnregisterElement(key)
    if not key then return end

    local overlay = self.overlayFrames[key]
    if overlay then
        -- Keep the frame for reuse; a fresh one would collide with its name.
        self:CancelDrag(overlay)
        self:RetireOverlay(overlay)
    end

    self.registeredElements[key] = nil

    if self.selectedElementKey == key then
        self:SelectElement(nil)
    end

    if self.isActive then
        self:UpdateCategorySelector()
    end
end

function EditMode:GetElementFrame(element)
    if element.frame then
        return element.frame
    elseif element.frameName then
        return _G[element.frameName]
    end
    return nil
end

---------------------------------------------------------------------------------
-- Overlay Frame Creation
---------------------------------------------------------------------------------

-- Inset values cross the module boundary, so one module forgetting a secret
-- guard would otherwise throw from a layout path and take the whole tool down.
local function SafeInset(value)
    if type(value) ~= "number" or issecretvalue(value) then return 0 end
    return value
end
EditMode._SafeInset = SafeInset

-- An element with no resolvable section shows only when unfiltered, so a module
-- whose sidebar page is missing still reaches the tool instead of disappearing.
function EditMode:ElementMatchesCategory(element)
    if not self.activeCategory then return true end
    return KE:GetSectionForItem(element.guiPath) == self.activeCategory
end

-- Two reasons an element deserves no box even though it is still registered.
-- Its module was switched off: registration outlives the module, so without
-- this the box outlives it too. Or the module is running but something else
-- owns the position in the current mode.
--
-- Visibility is deliberately NOT used here. Some movers are invisible proxies
-- by design, previews are switched on after overlays are built, and the
-- visibility APIs are secret-capable.
function EditMode:ElementIsLive(element)
    local module = element.module
    if module and module.IsEnabled and not module:IsEnabled() then
        return false
    end
    if element.isEligible and not element.isEligible() then
        return false
    end
    return true
end

function EditMode:ElementShouldShow(element)
    if not element then return false end
    if not self:ElementMatchesCategory(element) then return false end
    return self:ElementIsLive(element)
end

-- How many elements a category would actually show. Uses the same liveness rule
-- as the overlays, so a category whose modules are all switched off reads as
-- empty instead of selecting into a blank screen.
function EditMode:CountElementsInCategory(sectionId)
    local count = 0
    for _, element in pairs(self.registeredElements) do
        if (not sectionId or KE:GetSectionForItem(element.guiPath) == sectionId)
            and self:ElementIsLive(element) then
            count = count + 1
        end
    end
    return count
end

function EditMode:SetCategory(sectionId)
    if self.activeCategory == sectionId then return end
    self.activeCategory = sectionId

    -- Previews FIRST. A later round sizes boxes from what is on screen, so
    -- sizing before the new category's content exists would measure the old one.
    if KE.PreviewManager then
        KE.PreviewManager:UpdatePreviewState()
    end

    self:RefreshLiveState()
end

function EditMode:CreateOverlayFrame(element)
    local targetFrame = self:GetElementFrame(element)
    if not targetFrame then return nil end

    -- Create overlay frame
    local overlay = CreateFrame("Frame", "KE_EditMode_" .. element.key, UIParent, "BackdropTemplate")
    overlay:SetFrameStrata("TOOLTIP")
    overlay:SetFrameLevel(1000)

    -- Set backdrop with border. BORDER_SIZE is intent in screen pixels;
    -- multiply by KE:GetPixelSize() so the 2-screen-pixel highlight
    -- renders crisply regardless of UI scale.
    local overlayBorder = BORDER_SIZE * KE:GetPixelSize()
    overlay:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = overlayBorder,
        insets = { left = overlayBorder, right = overlayBorder, top = overlayBorder, bottom = overlayBorder },
    })

    -- Apply colors
    overlay:SetBackdropColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], FILL_ALPHA)
    overlay:SetBackdropBorderColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)

    -- Create identifier text
    local text = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("CENTER", overlay, "CENTER", 0, 0)
    text:SetText(element.displayName)
    text:SetFont(KE.FONT or STANDARD_TEXT_FONT, TEXT_FONT_SIZE, "OUTLINE")
    text:SetShadowOffset(0, 0)
    text:SetShadowColor(0, 0, 0, 0)
    text:SetTextColor(Theme.textSecondary[1], Theme.textSecondary[2], Theme.textSecondary[3], 0.2)
    overlay.text = text

    -- Store element reference
    overlay.element = element

    -- Setup drag handling
    self:SetupDragHandlers(overlay)

    return overlay
end

function EditMode:UpdateOverlayPosition(overlay)
    local element = overlay.element
    local targetFrame = element and self:GetElementFrame(element)

    -- Three callers reach here from a next-frame timer, so the tool can have
    -- closed in between: a combat auto-exit hides every overlay, and without
    -- this a late timer would show a pooled one back over a closed tool.
    if not self.isActive or not targetFrame then
        overlay:Hide()
        return
    end

    -- A drag in flight always finishes. Hiding the overlay mid-drag would strand
    -- the target re-anchored to the screen corner with no OnDragStop to undo it.
    if not overlay.isDragging and not self:ElementShouldShow(element) then
        overlay:Hide()
        return
    end

    -- The box is sometimes larger than the frame: decorations anchored just
    -- outside an edge are part of what the user sees and expects to grab. They
    -- must not reach the drag, which still measures the frame itself. All four
    -- default to zero, which is the plain SetAllPoints behaviour.
    local left, right, top, bottom = 0, 0, 0, 0
    if element.getOverlayInset then
        left, right, top, bottom = element.getOverlayInset()
    end
    left, right = SafeInset(left), SafeInset(right)
    top, bottom = SafeInset(top), SafeInset(bottom)

    overlay:ClearAllPoints()
    overlay:SetPoint("TOPLEFT", targetFrame, "TOPLEFT", -left, top)
    overlay:SetPoint("BOTTOMRIGHT", targetFrame, "BOTTOMRIGHT", right, -bottom)
    overlay:Show()
end

-- The one refresh entry point. Anything that can change whether an element
-- deserves a box calls this and nothing else. Three things follow from
-- liveness, and splitting them is how they drift: the boxes themselves, whether
-- the selected element is still one of them, and the per-category counts that
-- grey out an empty category button.
function EditMode:RefreshLiveState()
    if not self.isActive then return end

    for _, overlay in pairs(self.overlayFrames) do
        self:UpdateOverlayPosition(overlay)
    end

    -- A selection that just stopped qualifying would leave the nudge tool
    -- driving something with no box on screen.
    if self.selectedElementKey then
        local selected = self.registeredElements[self.selectedElementKey]
        if not (selected and self:ElementShouldShow(selected)) then
            self:SelectElement(nil)
        end
    end

    self:UpdateCategorySelector()
end

-- Everything a pooled overlay must forget before it is reused. Exit resets the
-- same state; retirement has to do it too, or a frame comes back mid-animation
-- or still wearing its selected colours.
function EditMode:RetireOverlay(overlay)
    if overlay._fadeFrame then
        overlay._fadeFrame:SetScript("OnUpdate", nil)
    end

    overlay.element = nil
    overlay:Hide()
    overlay:SetAlpha(1)
    overlay:SetBackdropColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], FILL_ALPHA)
    overlay:SetBackdropBorderColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)

    if overlay.text then
        overlay.text:SetAlpha(1)
        overlay.text:SetTextColor(Theme.textSecondary[1], Theme.textSecondary[2],
            Theme.textSecondary[3], 0.2)
        overlay.text:SetText("")
    end
end

function EditMode:CreateOverlayForElement(key)
    local element = self.registeredElements[key]
    if not element then return end

    -- Reuse the pooled overlay. Its name is already taken, so a second frame
    -- would orphan the first.
    if self.overlayFrames[key] then
        local overlay = self.overlayFrames[key]
        local wasSelected = (self.selectedElementKey == key)

        -- Never rebind a live element: cancel any drag, then retire, then adopt.
        self:CancelDrag(overlay)
        self:RetireOverlay(overlay)

        overlay.element = element
        if overlay.text then
            overlay.text:SetText(element.displayName)
        end
        self:UpdateOverlayPosition(overlay)

        -- Retirement cleared the selected styling. Re-apply it for the new
        -- element, which also refreshes the nudge readout, or drop the
        -- selection if the new element is not one this view can show.
        if wasSelected then
            self.selectedElementKey = nil
            self:SelectElement(self:ElementShouldShow(element) and key or nil)
        end
        return
    end

    local overlay = self:CreateOverlayFrame(element)
    if overlay then
        self.overlayFrames[key] = overlay
        self:UpdateOverlayPosition(overlay)
    end
end

---------------------------------------------------------------------------------
-- Drag Handling
---------------------------------------------------------------------------------

function EditMode:SetupDragHandlers(overlay)
    overlay:EnableMouse(true)
    overlay:SetMovable(true)
    overlay:RegisterForDrag("LeftButton")

    -- didDrag and the start coordinates stay local: only this overlay's own
    -- handlers read them, and OnDragStart rewrites them before any use. The
    -- drag flag lives on the overlay because the cancel path outside these
    -- closures has to see it.
    local didDrag = false
    local startX, startY = 0, 0
    local frameStartX, frameStartY = 0, 0

    -- Only the live update samples the cursor and snaps. The commit reads what
    -- the live update resolved, so the position that was last shown is by
    -- definition the position that gets saved.
    local snapContext = nil
    local snappedX, snappedY = nil, nil

    overlay:SetScript("OnDragStart", function(self)
        if InCombatLockdown() then return end

        local element = self.element
        if not element then return end

        local targetFrame = EditMode:GetElementFrame(element)
        if not targetFrame then return end

        -- Read the origin BEFORE committing to the drag. GetRect is
        -- SecretWhenAnchoringSecret, and a frame anchored to a restricted
        -- parent reports a secret rect, so there is no origin to measure from.
        -- Every value below feeds arithmetic, which throws on a secret. Refuse
        -- the drag rather than start one that computes a wrong offset: the
        -- element can still be moved by the nudge controls and the GUI.
        local left, bottom, width, height = targetFrame:GetRect()
        if issecretvalue(left) or issecretvalue(bottom)
            or issecretvalue(width) or issecretvalue(height) then
            KE:Print("Cannot drag this element: its position is protected. Use the nudge arrows instead.")
            return
        end

        self.isDragging = true
        didDrag = true

        -- Get cursor start position
        local scale = UIParent:GetEffectiveScale()
        startX, startY = GetCursorPosition()
        startX, startY = startX / scale, startY / scale

        if left and bottom and width and height then
            frameStartX = left + width / 2
            frameStartY = bottom + height / 2
        end

        snapContext = EditMode:BuildSnapContext()
        snappedX, snappedY = nil, nil

        -- Visual feedback
        self:SetAlpha(0.7)
    end)

    overlay:SetScript("OnDragStop", function(self)
        if not self.isDragging then return end
        self.isDragging = false
        self:SetAlpha(1)
        EditMode:HideCentreGuides()

        local element = self.element
        if not element then return end

        local targetFrame = EditMode:GetElementFrame(element)
        if not targetFrame then return end

        -- Get the current position/anchor settings from the module's DB
        local currentPos = element.getPosition()
        local anchorFrom = element.getAnchorFrom and element.getAnchorFrom()
            or currentPos.AnchorFrom or "CENTER"
        local anchorTo = currentPos.AnchorTo or "CENTER"

        -- Get the parent frame
        local parentFrame = UIParent
        if element.getParentFrame then
            parentFrame = element.getParentFrame() or UIParent
        end

        -- Reuse the decision the live update already made. Resampling here
        -- would run the same arithmetic on a different cursor reading, and near
        -- the edge of the snap threshold the two answers differ by the whole
        -- threshold -- a visible jump at the moment the button comes up.
        local newCenterX, newCenterY = snappedX, snappedY
        if not newCenterX then
            -- A drag that ended before any update ran, so there is no earlier
            -- decision to contradict. This is the only place the commit reads
            -- the cursor, and it is unreachable once one update has run.
            local scale = UIParent:GetEffectiveScale()
            local curX, curY = GetCursorPosition()
            curX, curY = curX / scale, curY / scale
            newCenterX, newCenterY = KE:SnapCenter(
                frameStartX + (curX - startX),
                frameStartY + (curY - startY),
                snapContext)
        end

        -- Parent rect for the offset calculation. The target's own rect is
        -- already known readable -- OnDragStart refuses the drag otherwise, and
        -- the drag proxy has since re-anchored it to UIParent -- but the
        -- module's chosen parent is a separate frame and can still be
        -- anchoring-secret on its own. Treat an unreadable rect exactly like a
        -- missing one and fall back to the screen.
        local parentLeft, parentBottom, parentWidth, parentHeight = parentFrame:GetRect()
        -- Every secret question first: GetRect can return nothing AND can
        -- return secrets, and asking `not parentLeft` of a secret throws.
        if issecretvalue(parentLeft) or issecretvalue(parentBottom)
            or issecretvalue(parentWidth) or issecretvalue(parentHeight)
            or not parentLeft then
            parentLeft, parentBottom = 0, 0
            parentWidth, parentHeight = UIParent:GetWidth(), UIParent:GetHeight()
        end

        local frameWidth, frameHeight = targetFrame:GetWidth(), targetFrame:GetHeight()

        local offsetX, offsetY = KE:ResolveAnchorOffsets(
            newCenterX, newCenterY, anchorFrom, anchorTo,
            frameWidth, frameHeight,
            parentLeft, parentBottom, parentWidth, parentHeight)

        -- Save using the ORIGINAL anchors, edit mode does not change anchor points
        local newPos = {
            AnchorFrom = anchorFrom,
            AnchorTo = anchorTo,
            XOffset = offsetX,
            YOffset = offsetY,
        }

        element.setPosition(newPos)
        C_Timer.After(0, function()
            EditMode:UpdateOverlayPosition(self)

            -- A frame's worth of delay is enough for the tool to close, the
            -- element to be unregistered, or its category or eligibility to
            -- change. SelectElement validates none of that, so selecting
            -- blindly here can drive the nudge controls from a box that is no
            -- longer on screen.
            local current = EditMode.registeredElements[element.key]
            if EditMode.isActive and current == self.element
                and EditMode:ElementShouldShow(current) then
                EditMode:SelectElement(element.key)
            end

            if KE.GUIFrame and KE.GUIFrame.mainFrame and KE.GUIFrame.mainFrame:IsShown() then
                KE.GUIFrame:RefreshContent()
            end
        end)
    end)

    -- Update position while dragging
    overlay:SetScript("OnUpdate", function(self)
        if not self.isDragging then return end

        local element = self.element
        if not element then return end

        local targetFrame = EditMode:GetElementFrame(element)
        if not targetFrame then return end

        local scale = UIParent:GetEffectiveScale()
        local curX, curY = GetCursorPosition()
        curX, curY = curX / scale, curY / scale
        local deltaX = curX - startX
        local deltaY = curY - startY

        -- Move visually using BOTTOMLEFT as a screen-coordinate proxy
        local onCentreX, onCentreY
        snappedX, snappedY, onCentreX, onCentreY =
            KE:SnapCenter(frameStartX + deltaX, frameStartY + deltaY, snapContext)

        targetFrame:ClearAllPoints()
        targetFrame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", snappedX, snappedY)

        EditMode:SetCentreGuides(onCentreX, onCentreY)

        EditMode:UpdateOverlayPosition(self)
    end)

    -- Mouseover stuff
    overlay:SetScript("OnEnter", function(self)
        local element = self.element
        if not element then return end
        if self.text and EditMode.selectedElementKey ~= element.key then
            self.text:SetTextColor(Theme.textSecondary[1], Theme.textSecondary[2], Theme.textSecondary[3], 1)
            self:SetBackdropBorderColor(Theme.textSecondary[1], Theme.textSecondary[2], Theme.textSecondary[3], 1)
        end
    end)
    overlay:SetScript("OnLeave", function(self)
        local element = self.element
        if not element then return end
        if self.text and EditMode.selectedElementKey ~= element.key then
            self.text:SetTextColor(Theme.textSecondary[1], Theme.textSecondary[2], Theme.textSecondary[3], 0.2)
            self:SetBackdropBorderColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
        end
    end)

    -- Reset drag flag on mouse down
    overlay:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then
            didDrag = false
        end
    end)

    -- Click to select for nudge tool
    overlay:SetScript("OnMouseUp", function(self, button)
        local element = self.element
        if not element then return end
        if button == "LeftButton" and not didDrag then
            EditMode:SelectElement(element.key)
        end
    end)
end

-- Both gates answer with a secret-capable boolean, so neither may be
-- truth-tested. Fail closed on either one being true or secret. IsProtected
-- alone is not enough: an unprotected mover that a secure header anchors to is
-- still restricted.
local function CanReanchor(frame)
    local protected = frame:IsProtected()
    if issecretvalue(protected) or protected == true then return false end

    -- Fail closed if the method is missing too. Every current target is a Frame
    -- or a Button and both carry it, so this is unreachable today, but a gate
    -- that cannot be asked is not a gate that said yes.
    if not frame.IsAnchoringRestricted then return false end

    local restricted = frame:IsAnchoringRestricted()
    if issecretvalue(restricted) or restricted == true then return false end

    return true
end

-- A drag leaves the target temporarily anchored to the screen corner, so any
-- path that ends a drag early has to put it back.
--
-- Going through the module's own setter is not sufficient. The commonest way a
-- drag is interrupted is entering combat, and some setters refuse to run then:
-- the aura header movers call a position update that returns immediately in
-- combat, so the frame would stay in the corner. Re-anchor the frame directly
-- as well, which is a plain frame operation, and let the setter persist the
-- value for the next full apply.
function EditMode:CancelDrag(overlay)
    if not overlay or not overlay.isDragging then return end
    overlay.isDragging = false
    overlay:SetAlpha(1)
    self:HideCentreGuides()

    local element = overlay.element
    if not element then return end
    local key = element.key

    -- Both closures re-resolve the element, the frame AND the position from the
    -- registry at call time. A deferred restore can run long after this element
    -- was unregistered, rebuilt or rebound to a different db table, and pairing
    -- a live frame with a value captured earlier would place it using a
    -- position that no longer belongs to it.
    local function Reanchor()
        local live = EditMode.registeredElements[key]
        if not live then return end
        local frame = EditMode:GetElementFrame(live)
        if not frame then return end
        local pos = live.getPosition and live.getPosition()
        if not pos then return end
        local parent = live.getParentFrame and live.getParentFrame() or UIParent
        local anchorFrom = live.getAnchorFrom and live.getAnchorFrom()
            or pos.AnchorFrom or "CENTER"
        frame:ClearAllPoints()
        frame:SetPoint(anchorFrom, parent, pos.AnchorTo or "CENTER",
            pos.XOffset or 0, pos.YOffset or 0)
    end

    -- The setter is module code. Whatever the target frame itself reports, a
    -- setter may reposition a secure child or a protected frame of its own --
    -- one module's setter positions a secure action button -- so it is never
    -- called during lockdown.
    local function Reapply()
        local live = EditMode.registeredElements[key]
        if not live or not live.setPosition then return end
        local pos = live.getPosition and live.getPosition()
        if pos then live.setPosition(pos) end
    end

    if InCombatLockdown() then
        -- Re-anchor now when both permission gates allow it: that is what stops
        -- the frame sitting in the screen corner for the rest of the fight.
        -- Anything restricted has to wait for the queue.
        local targetFrame = self:GetElementFrame(element)
        if targetFrame and CanReanchor(targetFrame) then
            Reanchor()
        else
            KE:RunAfterCombat(Reanchor)
        end
        KE:RunAfterCombat(Reapply)
    else
        Reanchor()
        Reapply()
    end
end

---------------------------------------------------------------------------------
-- Enter / Exit / Toggle
---------------------------------------------------------------------------------

function EditMode:Enter()
    if self.isActive then return end
    if InCombatLockdown() then
        KE:Print("Cannot enter edit mode during combat.")
        return
    end

    self.isActive = true

    -- Open on the category of the page the user came from. activeSection is not
    -- cleared when the GUI closes, so it is only trustworthy while the GUI is
    -- open; a cold /kes edit opens unfiltered.
    --
    -- The sidebar has sections the strip deliberately does not offer, because
    -- they own no movers. Adopting one of those would filter everything away
    -- with no button lit to show why, so they normalise to All.
    local PM = KE.PreviewManager
    local opening = PM and PM.guiOpen and PM.activeSection or nil
    -- Written out rather than folded into an `and/or` chain: the test returns a
    -- boolean, so `opening and Test(opening) or nil` yields `true`, not the
    -- section id, and every element then fails the category match.
    if opening and self:IsSelectableCategory(opening) then
        self.activeCategory = opening
    else
        self.activeCategory = nil
    end

    -- Create overlays for all registered elements
    for key in pairs(self.registeredElements) do
        self:CreateOverlayForElement(key)
    end

    self:ShowNudgeFrame()
    self:ShowGuideFrame()
    if KE.PreviewManager then KE.PreviewManager:SetEditModeActive(true) end

    -- Overlays are built before previews are switched on, so this is the first
    -- point where both are in their final state.
    self:RefreshLiveState()
    self:SetupEscapeHandler()
    self:SetupShiftHandler()
    self:SetupCombatHandler()
    self:StartDeselectChecker()

    local EnterMsg =
    "Edit Mode |cff00ff00enabled|r.\nDrag elements to reposition.\nHold Shift to see through overlay.\nPress ESC or type /kes edit to exit."
    KE:CreateMessagePopup(20, EnterMsg, 14, UIParent, 200, 0)
end

function EditMode:Exit()
    if not self.isActive then return end
    self.isActive = false
    -- Hide nudge frame
    self:HideNudgeFrame()
    self:HideGuideFrame()
    -- Notify PreviewManager that edit mode is inactive
    if KE.PreviewManager then
        KE.PreviewManager:SetEditModeActive(false)
    end
    -- Hide overlays but KEEP them pooled for reuse. Wiping the table here
    -- would orphan one named frame per registered element on every open/close
    -- cycle (WoW frames can't be destroyed); CreateOverlayForElement reuses
    -- any overlay that already exists and re-adopts its element.
    for _, overlay in pairs(self.overlayFrames) do
        if overlay then
            self:CancelDrag(overlay)
            self:RetireOverlay(overlay)
        end
    end
    self:RemoveEscapeHandler()
    self:RemoveShiftHandler()
    self:RemoveCombatHandler()
    self:StopDeselectChecker()

    local ExitMsg =
    "Edit Mode |cffff0000disabled|r."
    KE:CreateMessagePopup(1, ExitMsg, 14, UIParent, 200, 0)
end

function EditMode:Toggle()
    if self.isActive then
        self:Exit()
    else
        self:Enter()
    end
end

function EditMode:IsActive()
    return self.isActive
end

---------------------------------------------------------------------------------
-- Keyboard and Input Handlers
---------------------------------------------------------------------------------

-- Wires-once singleton: nil-ing the frame in Remove leaked one frame per
-- edit-mode cycle (frames are never GC'd). The frame and its OnKeyDown
-- persist; every Enter re-arms keyboard, propagate (the handler leaves it
-- false after consuming ESC), and Show (hidden frames get no key events).
function EditMode:SetupEscapeHandler()
    if not self.escapeFrame then
        self.escapeFrame = CreateFrame("Frame", "KE_EditModeEscape", UIParent)
        self.escapeFrame:SetScript("OnKeyDown", function(frame, key)
            -- SetPropagateKeyboardInput is restricted in combat, and the combat
            -- auto-exit reaches this frame while still in lockdown — the same
            -- window RemoveEscapeHandler guards. The tool is closing anyway, so
            -- refusing the whole keypress costs at most one swallowed key and
            -- avoids a blocked-action error.
            if InCombatLockdown() then return end

            -- Re-opened for every key, because the flag persists on the frame.
            -- Escape used to be the last thing this handler ever did before the
            -- handler was torn down, so leaving it closed cost nothing; now that
            -- Escape can be consumed without exiting, a stuck flag would swallow
            -- the next keypress, movement included.
            frame:SetPropagateKeyboardInput(true)

            if key == "ESCAPE" then
                frame:SetPropagateKeyboardInput(false)
                EditMode:HandleEscape()
                return
            end

            -- nil means it was not an arrow, which is every other key.
            local deltaX, deltaY = KE:ArrowNudgeDelta(key, IsControlKeyDown())
            if not deltaX then return end

            -- A focused field owns the arrows: without this, moving the caret
            -- in the offset boxes would move the element instead and the
            -- read-out would then overwrite what was typed.
            local focus = GetCurrentKeyBoardFocus()
            if focus and focus.IsVisible then
                local visible = focus:IsVisible()
                -- issecretvalue FIRST. Truth-testing a secret throws, and this
                -- looks at whatever holds focus — other addons' frames
                -- included — so none of them can be assumed clean. A secret
                -- answer routes like a visible one: hands the key back.
                if issecretvalue(visible) or visible then return end
            end

            -- Consumed only when it moved something. Swallowing arrows while
            -- the tool merely sits open would break turning.
            if EditMode:NudgeSelectedElement(deltaX, deltaY) then
                frame:SetPropagateKeyboardInput(false)
            end
        end)
    end
    self.escapeFrame:EnableKeyboard(true)
    self.escapeFrame:SetPropagateKeyboardInput(true)
    self.escapeFrame:Show()
end

function EditMode:RemoveEscapeHandler()
    if not self.escapeFrame then return end
    -- EnableKeyboard is protected in combat and the combat auto-exit path
    -- reaches here in lockdown; Hide() alone keeps the frame inert, and the
    -- next Enter (gated out of combat) re-arms everything.
    if not InCombatLockdown() then
        self.escapeFrame:EnableKeyboard(false)
    end
    self.escapeFrame:Hide()
end

---------------------------------------------------------------------------------
-- Shift-Fade Effect
---------------------------------------------------------------------------------

function EditMode:SetupShiftHandler()
    -- Frame is a create-once singleton (same leak shape as escapeFrame);
    -- the OnUpdate is re-wired per Enter so wasShiftDown starts fresh.
    if not self.shiftFrame then
        self.shiftFrame = CreateFrame("Frame", "KE_EditModeShift", UIParent)
    end
    local wasShiftDown = false
    self.shiftFrame:SetScript("OnUpdate", function()
        if not EditMode.isActive then return end
        local isShiftDown = IsShiftKeyDown()

        -- Detect state change
        if isShiftDown and not wasShiftDown then
            EditMode:ApplyShiftFade(true)
        elseif not isShiftDown and wasShiftDown then
            EditMode:ApplyShiftFade(false)
        end

        wasShiftDown = isShiftDown
    end)
    self.shiftFrame:Show()
end

function EditMode:RemoveShiftHandler()
    if self.shiftFrame then
        self.shiftFrame:SetScript("OnUpdate", nil)
        self.shiftFrame:Hide()
    end
    -- Ensure we restore alpha if edit mode is closed while Shift is held
    if self.isShiftFaded then
        self:ApplyShiftFade(false)
    end
end

local function AnimateOverlayAlpha(overlay, duration, fromAlpha, toAlpha, fillAlpha)
    -- Cancel any existing fade animation
    if overlay._fadeFrame then
        overlay._fadeFrame:SetScript("OnUpdate", nil)
    else
        overlay._fadeFrame = CreateFrame("Frame", nil, overlay)
    end

    local elapsed = 0
    overlay._fadeFrame:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        local t = math.min(elapsed / duration, 1)
        local alpha = fromAlpha + (toAlpha - fromAlpha) * t

        overlay:SetBackdropColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], alpha * fillAlpha)
        overlay:SetBackdropBorderColor(1, 1, 1, alpha)

        if overlay.text then
            overlay.text:SetAlpha(alpha)
        end

        if t >= 1 then
            self:SetScript("OnUpdate", nil)
        end
    end)
end

function EditMode:ApplyShiftFade(fade)
    self.isShiftFaded = fade

    if not self.selectedElementKey then return end

    local overlay = self.overlayFrames[self.selectedElementKey]
    if not overlay then return end

    if fade then
        AnimateOverlayAlpha(overlay, 0.2, 1, SHIFT_FADE_ALPHA, FILL_ALPHA)
    else
        AnimateOverlayAlpha(overlay, 0.2, SHIFT_FADE_ALPHA, 1, FILL_ALPHA)
    end
end

---------------------------------------------------------------------------------
-- Deselect Checker
---------------------------------------------------------------------------------

function EditMode:StartDeselectChecker()
    if not self.deselectChecker then
        self.deselectChecker = CreateFrame("Frame", nil, UIParent)
    end

    local wasMouseDown = false
    self.deselectChecker:SetScript("OnUpdate", function()
        if not EditMode.isActive then return end

        local isDown = IsMouseButtonDown("LeftButton")
        if wasMouseDown and not isDown then
            -- Check if mouse is over any overlay or the nudge frame
            local overAny = false

            if EditMode.nudgeFrame and EditMode.nudgeFrame:IsMouseOver() then
                overAny = true
            end

            -- The category selector is a child of the nudge frame but sits
            -- ABOVE it, and its open list hangs below across the tool. Neither
            -- falls inside the parent's rect, so without this every click on
            -- them reads as a click on empty space and clears the selection the
            -- filter exists to narrow.
            local nudge = EditMode.nudgeFrame
            local overSelector = nudge and nudge.categorySelector
                and nudge.categorySelector:IsMouseOver()
            local overList = nudge and nudge.categoryList
                and nudge.categoryList:IsShown()
                and nudge.categoryList:IsMouseOver()

            if not overAny and (overSelector or overList) then
                overAny = true
            end

            -- A click anywhere else dismisses the list, the way every other
            -- dropdown in the addon behaves.
            if not overSelector and not overList then
                EditMode:CloseCategoryList()
            end

            -- Ignore clicks on the GUI main frame
            if not overAny and KE.GUIFrame and KE.GUIFrame.mainFrame
                and KE.GUIFrame.mainFrame:IsShown()
                and KE.GUIFrame.mainFrame:IsMouseOver() then
                overAny = true
            end

            if not overAny then
                for _, overlay in pairs(EditMode.overlayFrames) do
                    if overlay:IsShown() and overlay:IsMouseOver() then
                        overAny = true
                        break
                    end
                end
            end

            if not overAny then
                EditMode:SelectElement(nil)
            end
        end

        wasMouseDown = isDown
    end)
    self.deselectChecker:Show()
end

function EditMode:StopDeselectChecker()
    if self.deselectChecker then
        self.deselectChecker:SetScript("OnUpdate", nil)
        self.deselectChecker:Hide()
    end
end

---------------------------------------------------------------------------------
-- Combat Handler
---------------------------------------------------------------------------------

function EditMode:SetupCombatHandler()
    -- Create-once singleton (same leak shape as escapeFrame); the OnEvent
    -- stays wired, Remove just unregisters the event.
    if not self.combatFrame then
        self.combatFrame = CreateFrame("Frame")
        self.combatFrame:SetScript("OnEvent", function()
            if EditMode.isActive then
                KE:Print("Edit Mode closed due to entering combat.")
                EditMode:Exit()
            end
        end)
    end
    self.combatFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
end

function EditMode:RemoveCombatHandler()
    if self.combatFrame then
        self.combatFrame:UnregisterAllEvents()
    end
end

---------------------------------------------------------------------------------
-- Theme Refresh
---------------------------------------------------------------------------------

function EditMode:RefreshOverlays()
    if not self.isActive then return end

    for _, overlay in pairs(self.overlayFrames) do
        if overlay then
            overlay:SetBackdropColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], FILL_ALPHA)
            overlay:SetBackdropBorderColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
        end
    end

    -- Update nudge frame styling if it exists
    if self.nudgeFrame then
        self:UpdateNudgeFrameTheme()
    end
end

---------------------------------------------------------------------------------
-- Element Selection
---------------------------------------------------------------------------------

function EditMode:SelectElement(key)
    -- Deselect previous
    if self.selectedElementKey and self.overlayFrames[self.selectedElementKey] then
        local prevOverlay = self.overlayFrames[self.selectedElementKey]

        -- Restore to normal state
        prevOverlay:SetBackdropColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], FILL_ALPHA)
        prevOverlay:SetBackdropBorderColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
        if prevOverlay.text then
            prevOverlay.text:SetTextColor(Theme.textSecondary[1], Theme.textSecondary[2], Theme.textSecondary[3], 0.2)
        end
    end

    -- Select new element
    self.selectedElementKey = key

    if key and self.overlayFrames[key] then
        local overlay = self.overlayFrames[key]

        -- Check if Shift is currently held
        if self.isShiftFaded and IsShiftKeyDown() then
            overlay:SetBackdropColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], SHIFT_FADE_ALPHA * FILL_ALPHA)
            overlay:SetBackdropBorderColor(1, 1, 1, SHIFT_FADE_ALPHA)
            if overlay.text then
                overlay.text:SetTextColor(1, 1, 1, 1)
                overlay.text:SetAlpha(SHIFT_FADE_ALPHA)
            end
        else
            -- Highlight selected with white border at full alpha
            overlay:SetBackdropBorderColor(1, 1, 1, 1)
            if overlay.text then
                overlay.text:SetTextColor(1, 1, 1, 1)
            end
        end
    else
        -- No element selected, clear shift fade state
        self.isShiftFaded = false
    end

    -- Update nudge frame display
    self:UpdateNudgeFrameInfo()
end

---------------------------------------------------------------------------------
-- Nudge Frame
---------------------------------------------------------------------------------

function EditMode:CreateNudgeFrame()
    if self.nudgeFrame then return self.nudgeFrame end
    local arrowTexture = "Interface\\AddOns\\KitnEssentials\\Media\\GUITextures\\collapse.tga"

    -- Main frame
    local frame = CreateFrame("Frame", "KE_EditModeNudge", UIParent, "BackdropTemplate")
    frame:SetSize(160, 332)
    frame:SetPoint("CENTER", UIParent, "CENTER", 400, 0)
    frame:SetFrameStrata("TOOLTIP")
    frame:SetFrameLevel(1001)

    -- Make it movable
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(f) f:StartMoving(true) end)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

    -- Backdrop
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = KE:GetPixelSize(),
    })
    frame:SetBackdropColor(Theme.bgLight[1], Theme.bgLight[2], Theme.bgLight[3], 1)
    frame:SetBackdropBorderColor(Theme.border[1], Theme.border[2], Theme.border[3], 1)

    -- Category selector. Parented to the nudge frame so the two drag together.
    -- Matches the tool's width: a row of seven labelled buttons could not, and
    -- read as a shelf balanced on top of the tool rather than part of it.
    local selector = CreateFrame("Button", nil, frame, "BackdropTemplate")
    selector:SetSize(160, 22)
    selector:SetPoint("BOTTOM", frame, "TOP", 0, 2)
    selector:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = KE:GetPixelSize(),
    })
    selector:SetBackdropColor(Theme.bgDark[1], Theme.bgDark[2], Theme.bgDark[3], 0.95)
    selector:SetBackdropBorderColor(Theme.border[1], Theme.border[2], Theme.border[3], 1)
    frame.categorySelector = selector

    local showingLabel = selector:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    showingLabel:SetPoint("LEFT", selector, "LEFT", 6, 0)
    showingLabel:SetFont(KE.FONT or STANDARD_TEXT_FONT, 12, "OUTLINE")
    showingLabel:SetShadowColor(0, 0, 0, 0)
    showingLabel:SetShadowOffset(0, 0)
    showingLabel:SetText("Showing")
    showingLabel:SetTextColor(Theme.textSecondary[1], Theme.textSecondary[2],
        Theme.textSecondary[3], 0.7)

    local selectorArrow = selector:CreateTexture(nil, "OVERLAY")
    selectorArrow:SetSize(10, 10)
    selectorArrow:SetPoint("RIGHT", selector, "RIGHT", -6, 0)
    selectorArrow:SetTexture(arrowTexture)
    selectorArrow:SetVertexColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
    selectorArrow:SetTexelSnappingBias(0)
    selectorArrow:SetSnapToPixelGrid(false)
    selector.arrow = selectorArrow

    local selectorValue = selector:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    selectorValue:SetPoint("RIGHT", selectorArrow, "LEFT", -4, 0)
    selectorValue:SetFont(KE.FONT or STANDARD_TEXT_FONT, 12, "OUTLINE")
    selectorValue:SetShadowColor(0, 0, 0, 0)
    selectorValue:SetShadowOffset(0, 0)
    selectorValue:SetTextColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
    selector.value = selectorValue

    -- The list hangs below the selector, over the tool. The nudge frame already
    -- sits at TOOLTIP/1001, so the level has to be raised explicitly or the list
    -- draws underneath the thing it opens over.
    local list = CreateFrame("Frame", nil, selector, "BackdropTemplate")
    list:SetPoint("TOPLEFT", selector, "BOTTOMLEFT", 0, -2)
    list:SetPoint("TOPRIGHT", selector, "BOTTOMRIGHT", 0, -2)
    list:SetHeight(#CATEGORIES * CATEGORY_ROW_HEIGHT + 4)
    list:SetFrameStrata("TOOLTIP")
    list:SetFrameLevel(frame:GetFrameLevel() + 20)
    -- The rows leave a border's worth of list uncovered. Without this, a press
    -- on that sliver falls through to the nudge frame beneath and drags the
    -- tool while the user thinks they are using the list.
    list:EnableMouse(true)
    list:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = KE:GetPixelSize(),
    })
    list:SetBackdropColor(Theme.bgDark[1], Theme.bgDark[2], Theme.bgDark[3], 1)
    list:SetBackdropBorderColor(Theme.border[1], Theme.border[2], Theme.border[3], 1)
    list:Hide()
    frame.categoryList = list
    frame.categoryButtons = {}

    for index, category in ipairs(CATEGORIES) do
        local rowY = -2 - (index - 1) * CATEGORY_ROW_HEIGHT
        local btn = CreateFrame("Button", nil, list)
        btn:SetHeight(CATEGORY_ROW_HEIGHT)
        btn:SetPoint("TOPLEFT", list, "TOPLEFT", 2, rowY)
        btn:SetPoint("TOPRIGHT", list, "TOPRIGHT", -2, rowY)

        local hover = btn:CreateTexture(nil, "BACKGROUND")
        hover:SetAllPoints()
        hover:SetColorTexture(Theme.accent[1], Theme.accent[2], Theme.accent[3], 0.25)
        hover:Hide()
        btn.hover = hover

        local catLabel = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        catLabel:SetPoint("LEFT", btn, "LEFT", 6, 0)
        catLabel:SetFont(KE.FONT or STANDARD_TEXT_FONT, 12, "OUTLINE")
        catLabel:SetShadowColor(0, 0, 0, 0)
        catLabel:SetShadowOffset(0, 0)
        catLabel:SetText(category.label)
        btn.label = catLabel

        -- The count that decides whether the row is selectable, shown rather
        -- than only implied by dimming it.
        local catCount = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        catCount:SetPoint("RIGHT", btn, "RIGHT", -6, 0)
        catCount:SetFont(KE.FONT or STANDARD_TEXT_FONT, 11, "OUTLINE")
        catCount:SetShadowColor(0, 0, 0, 0)
        catCount:SetShadowOffset(0, 0)
        btn.count = catCount

        btn.categoryId = category.id
        btn.categoryLabel = category.label

        btn:SetScript("OnEnter", function(self)
            if self:IsEnabled() then self.hover:Show() end
        end)
        btn:SetScript("OnLeave", function(self) self.hover:Hide() end)
        btn:SetScript("OnClick", function(self)
            EditMode:SetCategory(self.categoryId)
            -- Closed on the NEXT frame, not this one. The deselect checker
            -- tests the list's rect on this same mouse-up, and a list already
            -- hidden by then reads as a click on empty space — which would
            -- clear the very selection a switch to All is meant to keep.
            C_Timer.After(0, function() EditMode:CloseCategoryList() end)
        end)

        frame.categoryButtons[index] = btn
    end

    selector:SetScript("OnClick", function() EditMode:ToggleCategoryList() end)
    selector:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
    end)
    selector:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(Theme.border[1], Theme.border[2], Theme.border[3], 1)
    end)

    -- Title
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", frame, "TOP", 0, -6)
    title:SetFont(KE.FONT or STANDARD_TEXT_FONT, 16, "OUTLINE")
    title:SetShadowColor(0, 0, 0, 0)
    title:SetShadowOffset(0, 0)
    title:SetText("Nudge Tool")
    title:SetTextColor(Theme.textSecondary[1], Theme.textSecondary[2], Theme.textSecondary[3], 1)
    frame.title = title

    -- Selected element name
    local selectedText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    selectedText:SetPoint("TOP", title, "BOTTOM", 0, -2)
    selectedText:SetFont(KE.FONT or STANDARD_TEXT_FONT, 12, "OUTLINE")
    selectedText:SetShadowColor(0, 0, 0, 0)
    selectedText:SetShadowOffset(0, 0)
    selectedText:SetText("Click to select")
    selectedText:SetTextColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
    frame.selectedText = selectedText

    -- Helper to create editbox for position values
    local function CreatePosEditBox(parent, labelText, yOffset)
        local row = CreateFrame("Frame", nil, parent)
        row:SetSize(140, 22)
        row:SetPoint("TOP", parent, "TOP", 0, yOffset)

        local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("LEFT", row, "LEFT", 0, 0)
        label:SetFont(KE.FONT or STANDARD_TEXT_FONT, 12, "OUTLINE")
        label:SetShadowColor(0, 0, 0, 0)
        label:SetShadowOffset(0, 0)
        label:SetText(labelText)
        label:SetTextColor(Theme.textSecondary[1], Theme.textSecondary[2], Theme.textSecondary[3], 1)

        local container = CreateFrame("Frame", nil, row, "BackdropTemplate")
        container:SetSize(70, 20)
        container:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        container:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = KE:GetPixelSize(),
        })
        container:SetBackdropColor(Theme.bgDark[1], Theme.bgDark[2], Theme.bgDark[3], 1)
        container:SetBackdropBorderColor(Theme.border[1], Theme.border[2], Theme.border[3], 1)

        local editBox = CreateFrame("EditBox", nil, container)
        editBox:SetPoint("TOPLEFT", 4, -2)
        editBox:SetPoint("BOTTOMRIGHT", -4, 2)
        editBox:SetFontObject("GameFontNormal")
        editBox:SetFont(KE.FONT or STANDARD_TEXT_FONT, 12, "OUTLINE")
        editBox:SetShadowColor(0, 0, 0, 0)
        editBox:SetShadowOffset(0, 0)
        editBox:SetTextColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
        editBox:SetJustifyH("CENTER")
        editBox:SetAutoFocus(false)
        editBox:SetText("--")

        editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

        editBox:SetScript("OnEditFocusGained", function(self)
            container:SetBackdropBorderColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
            self:HighlightText()
        end)

        editBox:SetScript("OnEditFocusLost", function(self)
            container:SetBackdropBorderColor(Theme.border[1], Theme.border[2], Theme.border[3], 1)
            self:HighlightText(0, 0)
        end)

        -- Hover animation
        local hoverR, hoverG, hoverB = Theme.border[1], Theme.border[2], Theme.border[3]
        local animGroup = container:CreateAnimationGroup()
        local anim = animGroup:CreateAnimation("Animation")
        anim:SetDuration(0.15)
        local colorFrom, colorTo = {}, {}

        local function AnimateBorder(toAccent)
            if editBox:HasFocus() then return end
            animGroup:Stop()
            colorFrom.r, colorFrom.g, colorFrom.b = hoverR, hoverG, hoverB
            if toAccent then
                colorTo.r, colorTo.g, colorTo.b = Theme.accent[1], Theme.accent[2], Theme.accent[3]
            else
                colorTo.r, colorTo.g, colorTo.b = Theme.border[1], Theme.border[2], Theme.border[3]
            end
            animGroup:Play()
        end

        animGroup:SetScript("OnUpdate", function(self)
            local progress = self:GetProgress() or 0
            local r = colorFrom.r + (colorTo.r - colorFrom.r) * progress
            local g = colorFrom.g + (colorTo.g - colorFrom.g) * progress
            local b = colorFrom.b + (colorTo.b - colorFrom.b) * progress
            container:SetBackdropBorderColor(r, g, b, 1)
            hoverR, hoverG, hoverB = r, g, b
        end)

        animGroup:SetScript("OnFinished", function()
            container:SetBackdropBorderColor(colorTo.r, colorTo.g, colorTo.b, 1)
            hoverR, hoverG, hoverB = colorTo.r, colorTo.g, colorTo.b
        end)

        editBox:SetScript("OnEnter", function() AnimateBorder(true) end)
        editBox:SetScript("OnLeave", function() AnimateBorder(false) end)

        row.editBox = editBox
        row.container = container
        return row
    end

    -- X position row
    local xRow = CreatePosEditBox(frame, "X Offset:", -42)
    frame.xEditBox = xRow.editBox

    -- Y position row
    local yRow = CreatePosEditBox(frame, "Y Offset:", -66)
    frame.yEditBox = yRow.editBox

    -- Anchor display
    local anchorRow = CreateFrame("Frame", nil, frame)
    anchorRow:SetSize(140, 18)
    anchorRow:SetPoint("TOP", frame, "TOP", 0, -90)

    -- EditBox submit handlers
    local function ApplyPositionFromEditBoxes()
        if not EditMode.selectedElementKey then return end
        local element = EditMode.registeredElements[EditMode.selectedElementKey]
        if not element then return end

        local currentPos = element.getPosition()
        if not currentPos then return end

        local newX = tonumber(frame.xEditBox:GetText())
        local newY = tonumber(frame.yEditBox:GetText())

        if not newX or not newY then
            EditMode:UpdateNudgeFrameInfo()
            return
        end

        local newPos = {
            AnchorFrom = currentPos.AnchorFrom,
            AnchorTo = currentPos.AnchorTo,
            XOffset = KE:RoundOffset(newX),
            YOffset = KE:RoundOffset(newY),
        }

        element.setPosition(newPos)

        -- Repaint the boxes from what was actually stored. The typed text is
        -- still whatever was entered, so without this a fractional entry keeps
        -- showing its fraction while the stored value is the rounded one.
        EditMode:UpdateNudgeFrameInfo()

        if EditMode.overlayFrames[EditMode.selectedElementKey] then
            C_Timer.After(0, function()
                EditMode:UpdateOverlayPosition(EditMode.overlayFrames[EditMode.selectedElementKey])
            end)
        end

        if KE.GUIFrame and KE.GUIFrame.mainFrame and KE.GUIFrame.mainFrame:IsShown() then
            KE.GUIFrame:RefreshContent()
        end
    end

    frame.xEditBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        ApplyPositionFromEditBoxes()
    end)

    frame.yEditBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        ApplyPositionFromEditBoxes()
    end)

    -- D-Pad settings
    local btnSize = 22
    local dpadCenterY = -105

    -- Create arrow button with animated hover
    local function CreateArrowButton(parent, direction, xOff, yOff, rotation)
        local btn = CreateFrame("Button", nil, parent)
        btn:SetSize(btnSize, btnSize)
        btn:SetPoint("TOP", parent, "TOP", xOff, yOff)

        local container = CreateFrame("Frame", nil, btn, "BackdropTemplate")
        container:SetAllPoints(btn)
        container:SetFrameLevel(btn:GetFrameLevel() + 1)
        container:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = KE:GetPixelSize(),
        })
        container:SetBackdropColor(Theme.bgDark[1], Theme.bgDark[2], Theme.bgDark[3], 1)
        container:SetBackdropBorderColor(Theme.border[1], Theme.border[2], Theme.border[3], 1)

        -- Arrow icon
        local icon = container:CreateTexture(nil, "OVERLAY")
        icon:SetAllPoints()
        icon:SetTexture(arrowTexture)
        icon:SetVertexColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
        icon:SetRotation(math.rad(rotation))
        icon:SetTexelSnappingBias(0)
        icon:SetSnapToPixelGrid(false)
        container.icon = icon

        -- Track current color for animation
        local curR, curG, curB = Theme.accent[1], Theme.accent[2], Theme.accent[3]

        -- Hover animation
        local animGroup = btn:CreateAnimationGroup()
        local anim = animGroup:CreateAnimation("Animation")
        anim:SetDuration(0.15)

        local colorFrom = {}
        local colorTo = {}

        local function AnimateColor(toAccent)
            animGroup:Stop()
            colorFrom.r, colorFrom.g, colorFrom.b = curR, curG, curB

            if toAccent then
                colorTo.r, colorTo.g, colorTo.b = Theme.textSecondary[1], Theme.textSecondary[2], Theme.textSecondary[3]
            else
                colorTo.r, colorTo.g, colorTo.b = Theme.accent[1], Theme.accent[2], Theme.accent[3]
            end
            animGroup:Play()
        end

        animGroup:SetScript("OnUpdate", function(self)
            local progress = self:GetProgress() or 0
            local r = colorFrom.r + (colorTo.r - colorFrom.r) * progress
            local g = colorFrom.g + (colorTo.g - colorFrom.g) * progress
            local b = colorFrom.b + (colorTo.b - colorFrom.b) * progress
            icon:SetVertexColor(r, g, b, 1)
            curR, curG, curB = r, g, b
        end)

        animGroup:SetScript("OnFinished", function()
            icon:SetVertexColor(colorTo.r, colorTo.g, colorTo.b, 1)
            curR, curG, curB = colorTo.r, colorTo.g, colorTo.b
        end)

        btn:SetScript("OnEnter", function()
            AnimateColor(true)
        end)

        btn:SetScript("OnLeave", function()
            AnimateColor(false)
        end)

        btn.direction = direction
        return btn
    end

    -- D-Pad buttons positioned
    local spacing = btnSize + 4
    frame.btnUp = CreateArrowButton(frame, "UP", 0, dpadCenterY, 180)
    frame.btnDown = CreateArrowButton(frame, "DOWN", 0, dpadCenterY - (spacing * 2), 0)
    frame.btnLeft = CreateArrowButton(frame, "LEFT", -spacing, dpadCenterY - spacing, -90)
    frame.btnRight = CreateArrowButton(frame, "RIGHT", spacing, dpadCenterY - spacing, 90)

    -- Setup nudge click handlers
    frame.btnUp:SetScript("OnClick", function() EditMode:NudgeSelectedElement(0, 1) end)
    frame.btnDown:SetScript("OnClick", function() EditMode:NudgeSelectedElement(0, -1) end)
    frame.btnLeft:SetScript("OnClick", function() EditMode:NudgeSelectedElement(-1, 0) end)
    frame.btnRight:SetScript("OnClick", function() EditMode:NudgeSelectedElement(1, 0) end)

    -- Done button. Bottom of the stack, so everything above chains off it.
    local doneBtn = CreateFrame("Button", nil, frame, "BackdropTemplate")
    doneBtn:SetSize(140, 22)
    doneBtn:SetPoint("BOTTOM", frame, "BOTTOM", 0, 8)
    doneBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = KE:GetPixelSize(),
    })
    doneBtn:SetBackdropColor(Theme.bgDark[1], Theme.bgDark[2], Theme.bgDark[3], 1)
    doneBtn:SetBackdropBorderColor(Theme.border[1], Theme.border[2], Theme.border[3], 1)

    local doneBtnText = doneBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    doneBtnText:SetPoint("CENTER")
    doneBtnText:SetFont(KE.FONT or STANDARD_TEXT_FONT, 12, "OUTLINE")
    doneBtnText:SetShadowColor(0, 0, 0, 0)
    doneBtnText:SetShadowOffset(0, 0)
    doneBtnText:SetText("Done")
    doneBtnText:SetTextColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
    frame.doneBtn = doneBtn
    frame.doneBtnText = doneBtnText

    -- Not gated on combat: the combat handler exits through this same call.
    doneBtn:SetScript("OnClick", function()
        EditMode:Exit()
    end)

    -- Settings button
    local settingsBtn = CreateFrame("Button", nil, frame, "BackdropTemplate")
    settingsBtn:SetSize(140, 22)
    settingsBtn:SetPoint("BOTTOM", doneBtn, "TOP", 0, 6)
    settingsBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = KE:GetPixelSize(),
    })
    settingsBtn:SetBackdropColor(Theme.bgDark[1], Theme.bgDark[2], Theme.bgDark[3], 1)
    settingsBtn:SetBackdropBorderColor(Theme.border[1], Theme.border[2], Theme.border[3], 1)

    local settingsBtnText = settingsBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    settingsBtnText:SetPoint("CENTER")
    settingsBtnText:SetFont(KE.FONT or STANDARD_TEXT_FONT, 12, "OUTLINE")
    settingsBtnText:SetShadowColor(0, 0, 0, 0)
    settingsBtnText:SetShadowOffset(0, 0)
    settingsBtnText:SetText("Open Settings")
    settingsBtnText:SetTextColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
    frame.settingsBtn = settingsBtn
    frame.settingsBtnText = settingsBtnText

    -- Settings button hover animation
    local settingsBtnR, settingsBtnG, settingsBtnB = Theme.border[1], Theme.border[2], Theme.border[3]
    local settingsAnimGroup = settingsBtn:CreateAnimationGroup()
    local settingsAnim = settingsAnimGroup:CreateAnimation("Animation")
    settingsAnim:SetDuration(0.15)
    local settingsColorFrom, settingsColorTo = {}, {}

    local function AnimateSettingsBtn(toAccent)
        settingsAnimGroup:Stop()
        settingsColorFrom.r, settingsColorFrom.g, settingsColorFrom.b = settingsBtnR, settingsBtnG, settingsBtnB
        if toAccent then
            settingsColorTo.r, settingsColorTo.g, settingsColorTo.b = Theme.accent[1], Theme.accent[2], Theme.accent[3]
        else
            settingsColorTo.r, settingsColorTo.g, settingsColorTo.b = Theme.border[1], Theme.border[2], Theme.border[3]
        end
        settingsAnimGroup:Play()
    end

    settingsAnimGroup:SetScript("OnUpdate", function(self)
        local progress = self:GetProgress() or 0
        local r = settingsColorFrom.r + (settingsColorTo.r - settingsColorFrom.r) * progress
        local g = settingsColorFrom.g + (settingsColorTo.g - settingsColorFrom.g) * progress
        local b = settingsColorFrom.b + (settingsColorTo.b - settingsColorFrom.b) * progress
        settingsBtn:SetBackdropBorderColor(r, g, b, 1)
        settingsBtnR, settingsBtnG, settingsBtnB = r, g, b
    end)

    settingsAnimGroup:SetScript("OnFinished", function()
        settingsBtn:SetBackdropBorderColor(settingsColorTo.r, settingsColorTo.g, settingsColorTo.b, 1)
        settingsBtnR, settingsBtnG, settingsBtnB = settingsColorTo.r, settingsColorTo.g, settingsColorTo.b
    end)

    settingsBtn:SetScript("OnEnter", function() AnimateSettingsBtn(true) end)
    settingsBtn:SetScript("OnLeave", function() AnimateSettingsBtn(false) end)

    settingsBtn:SetScript("OnClick", function()
        EditMode:OpenElementSettings()
    end)

    local GUIDE_SPACINGS = { 8, 16, 32, 64 }

    -- Grid preferences. Stacked above the settings button, top to bottom:
    -- grid, snapping, spacing.
    local function CreateToolToggle(parent, anchorTo, label)
        local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
        btn:SetSize(140, 22)
        btn:SetPoint("BOTTOM", anchorTo, "TOP", 0, 6)
        btn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = KE:GetPixelSize(),
        })
        btn:SetBackdropColor(Theme.bgDark[1], Theme.bgDark[2], Theme.bgDark[3], 1)
        btn:SetBackdropBorderColor(Theme.border[1], Theme.border[2], Theme.border[3], 1)

        local text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        text:SetPoint("CENTER")
        text:SetFont(KE.FONT or STANDARD_TEXT_FONT, 12, "OUTLINE")
        text:SetShadowColor(0, 0, 0, 0)
        text:SetShadowOffset(0, 0)
        text:SetTextColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
        btn.text = text
        btn.label = label

        return btn
    end

    local spacingBtn = CreateToolToggle(frame, settingsBtn, "Spacing")
    local snapBtn = CreateToolToggle(frame, spacingBtn, "Snapping")
    local gridBtn = CreateToolToggle(frame, snapBtn, "Grid")

    frame.spacingBtn = spacingBtn
    frame.snapBtn = snapBtn
    frame.gridBtn = gridBtn

    gridBtn:SetScript("OnClick", function()
        EditMode:SetGuideSetting("ShowGrid", not EditMode:GetGuideSetting("ShowGrid"))
        EditMode:UpdateGuideControls()
        EditMode:RefreshGrid()
    end)

    snapBtn:SetScript("OnClick", function()
        EditMode:SetGuideSetting("Snapping", not EditMode:GetGuideSetting("Snapping"))
        EditMode:UpdateGuideControls()
        -- No redraw: the next drag builds a fresh context and reads this then.
    end)

    spacingBtn:SetScript("OnClick", function()
        local current = EditMode:GetGuideSetting("Spacing") or 32
        local nextValue = GUIDE_SPACINGS[1]
        for i = 1, #GUIDE_SPACINGS do
            if GUIDE_SPACINGS[i] == current then
                nextValue = GUIDE_SPACINGS[(i % #GUIDE_SPACINGS) + 1]
                break
            end
        end
        EditMode:SetGuideSetting("Spacing", nextValue)
        EditMode:UpdateGuideControls()
        -- Spacing is grid geometry, so the grid redraws now rather than waiting
        -- for the tool to be reopened.
        EditMode:RefreshGrid()
    end)

    -- After the assignment, never before: UpdateGuideControls guards on
    -- self.nudgeFrame, so an earlier call returns and leaves all three blank.
    self.nudgeFrame = frame
    self:UpdateGuideControls()
    return frame
end

-- One place decides what each button says, so the build and every click
-- produce the same string. A control that renders its label separately from
-- its click handler drifts the first time one of them changes.
function EditMode:UpdateGuideControls()
    local f = self.nudgeFrame
    if not f or not f.gridBtn then return end
    f.gridBtn.text:SetText("Grid: " ..
        (self:GetGuideSetting("ShowGrid") and "On" or "Off"))
    f.snapBtn.text:SetText("Snapping: " ..
        (self:GetGuideSetting("Snapping") and "On" or "Off"))
    f.spacingBtn.text:SetText("Spacing: " ..
        tostring(self:GetGuideSetting("Spacing") or 32))
end

function EditMode:UpdateNudgeFrameInfo()
    if not self.nudgeFrame then return end

    local frame = self.nudgeFrame

    if not self.selectedElementKey then
        frame.selectedText:SetText("Click to select")
        frame.selectedText:SetTextColor(Theme.textSecondary[1], Theme.textSecondary[2], Theme.textSecondary[3], 1)
        frame.xEditBox:SetText("--")
        frame.yEditBox:SetText("--")
        frame.xEditBox:SetEnabled(false)
        frame.yEditBox:SetEnabled(false)
        frame.settingsBtn:SetEnabled(false)
        frame.settingsBtn:SetAlpha(0.4)
        return
    end

    local element = self.registeredElements[self.selectedElementKey]
    if not element then return end

    frame.selectedText:SetText(element.displayName)
    frame.selectedText:SetTextColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
    frame.xEditBox:SetEnabled(true)
    frame.yEditBox:SetEnabled(true)
    frame.settingsBtn:SetEnabled(true)
    frame.settingsBtn:SetAlpha(1)

    local pos = element.getPosition()
    if pos then
        -- RoundOffset rather than %d alone: Lua 5.1 truncates toward zero when
        -- formatting a fraction, so a value stored before offsets became whole
        -- would read one point off from what a nudge would round it to.
        frame.xEditBox:SetText(string.format("%d", KE:RoundOffset(pos.XOffset)))
        frame.yEditBox:SetText(string.format("%d", KE:RoundOffset(pos.YOffset)))
    end
end

---------------------------------------------------------------------------------
-- GUI Integration
---------------------------------------------------------------------------------

function EditMode:OpenElementSettings()
    if not self.selectedElementKey then
        KE:Print("No element selected.")
        return
    end

    local element = self.registeredElements[self.selectedElementKey]
    if not element then return end

    local GUIFrame = KE.GUIFrame
    if not GUIFrame then return end

    -- guiPath is still the sidebar item id, but for a collapsed module that is
    -- now the tabbed page's id rather than the module's own id.
    local itemId = element.guiPath

    if not itemId then
        -- No guiPath defined, just open GUI
        if not GUIFrame:IsShown() then
            GUIFrame:Show()
        end
        return
    end

    -- Find the parent section ID containing this item
    local sectionId = nil
    local config = GUIFrame.sidebarConfig
    if config then
        for _, section in ipairs(config) do
            if section.type == "header" and section.items then
                for _, item in ipairs(section.items) do
                    if item.id == itemId then
                        sectionId = section.id
                        break
                    end
                end
            end
            if sectionId then break end
        end
    end

    -- A collapsed page hosts several modules behind sub-tabs; guiTab names the
    -- one this element belongs to. tabbedPageState is what ResolveActiveTab
    -- reads on the rebuild OpenPage triggers, so seed it first.
    if element.guiTab and GUIFrame.tabbedPageState then
        GUIFrame.tabbedPageState[itemId] = element.guiTab
    end

    -- Use OpenPage which properly handles showing, expanding section, and selecting item
    -- Pass guiContext as third parameter for granular navigation
    GUIFrame:OpenPage(itemId, sectionId, element.guiContext)
end

function EditMode:UpdateNudgeFrameTheme()
    if not self.nudgeFrame then return end

    -- Update main frame backdrop
    self.nudgeFrame:SetBackdropColor(Theme.bgDark[1], Theme.bgDark[2], Theme.bgDark[3], 0.95)
    self.nudgeFrame:SetBackdropBorderColor(Theme.border[1], Theme.border[2], Theme.border[3], 1)

    if self.nudgeFrame.categorySelector then
        self.nudgeFrame.categorySelector:SetBackdropColor(
            Theme.bgDark[1], Theme.bgDark[2], Theme.bgDark[3], 0.95)
        self.nudgeFrame.categorySelector:SetBackdropBorderColor(
            Theme.border[1], Theme.border[2], Theme.border[3], 1)
        self.nudgeFrame.categorySelector.arrow:SetVertexColor(
            Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
        self.nudgeFrame.categorySelector.value:SetTextColor(
            Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
    end

    -- Three explicit calls, not ipairs over a literal: a nil in an array
    -- literal ends the iteration at the gap and silently skips the rest.
    local function ThemeToolToggle(btn)
        if not btn then return end
        btn:SetBackdropColor(Theme.bgDark[1], Theme.bgDark[2], Theme.bgDark[3], 1)
        btn:SetBackdropBorderColor(Theme.border[1], Theme.border[2], Theme.border[3], 1)
        btn.text:SetTextColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
    end

    ThemeToolToggle(self.nudgeFrame.gridBtn)
    ThemeToolToggle(self.nudgeFrame.snapBtn)
    ThemeToolToggle(self.nudgeFrame.spacingBtn)

    -- Same three colours, but its fontstring hangs off a different field name.
    if self.nudgeFrame.doneBtn then
        self.nudgeFrame.doneBtn:SetBackdropColor(
            Theme.bgDark[1], Theme.bgDark[2], Theme.bgDark[3], 1)
        self.nudgeFrame.doneBtn:SetBackdropBorderColor(
            Theme.border[1], Theme.border[2], Theme.border[3], 1)
        self.nudgeFrame.doneBtnText:SetTextColor(
            Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
    end

    if self.nudgeFrame.categoryList then
        self.nudgeFrame.categoryList:SetBackdropColor(
            Theme.bgDark[1], Theme.bgDark[2], Theme.bgDark[3], 1)
        self.nudgeFrame.categoryList:SetBackdropBorderColor(
            Theme.border[1], Theme.border[2], Theme.border[3], 1)
        for _, btn in ipairs(self.nudgeFrame.categoryButtons) do
            btn.hover:SetColorTexture(Theme.accent[1], Theme.accent[2], Theme.accent[3], 0.25)
        end
    end
    self:UpdateCategorySelector()

    -- Refresh the info display with new colors
    self:UpdateNudgeFrameInfo()
end

-- Escape backs out one layer at a time: an open category list first, the tool
-- second. Without the first layer, dismissing a list you opened by mistake
-- would also throw away the whole session.
function EditMode:HandleEscape()
    local nudge = self.nudgeFrame
    if nudge and nudge.categoryList and nudge.categoryList:IsShown() then
        self:CloseCategoryList()
        return
    end
    self:Exit()
end

function EditMode:ToggleCategoryList()
    local frame = self.nudgeFrame
    if not (frame and frame.categoryList) then return end

    if frame.categoryList:IsShown() then
        self:CloseCategoryList()
    else
        frame.categoryList:Show()
        frame.categorySelector.arrow:SetRotation(math.pi)
    end
end

function EditMode:CloseCategoryList()
    local frame = self.nudgeFrame
    if not (frame and frame.categoryList) then return end

    frame.categoryList:Hide()
    frame.categorySelector.arrow:SetRotation(0)
end

-- The control names the active category; the list carries the rest. An empty
-- category reads as dimmed and unclickable, with its count showing why.
function EditMode:UpdateCategorySelector()
    local frame = self.nudgeFrame
    if not (frame and frame.categoryButtons) then return end

    for _, btn in ipairs(frame.categoryButtons) do
        local count = self:CountElementsInCategory(btn.categoryId)
        local selected = (btn.categoryId == self.activeCategory)
        local populated = count > 0

        btn:SetEnabled(populated)
        btn.count:SetText(count)

        if not populated then
            btn.hover:Hide()
            btn.label:SetTextColor(Theme.textSecondary[1], Theme.textSecondary[2],
                Theme.textSecondary[3], 0.3)
            btn.count:SetTextColor(Theme.textSecondary[1], Theme.textSecondary[2],
                Theme.textSecondary[3], 0.3)
        elseif selected then
            btn.label:SetTextColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
            btn.count:SetTextColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 0.7)
        else
            btn.label:SetTextColor(Theme.textSecondary[1], Theme.textSecondary[2],
                Theme.textSecondary[3], 1)
            btn.count:SetTextColor(Theme.textSecondary[1], Theme.textSecondary[2],
                Theme.textSecondary[3], 0.5)
        end

        if selected then
            frame.categorySelector.value:SetText(btn.categoryLabel)
        end
    end
end

---------------------------------------------------------------------------------
-- Nudge Logic
---------------------------------------------------------------------------------

function EditMode:NudgeSelectedElement(deltaX, deltaY)
    if not self.selectedElementKey then
        KE:Print("No element selected. Click an overlay to select it.")
        return false
    end

    local element = self.registeredElements[self.selectedElementKey]
    if not element then return false end
    local currentPos = element.getPosition()
    if not currentPos then return false end

    -- Calculate new position. Rounding matters even though the delta is whole:
    -- a value stored fractionally before offsets became whole stays fractional
    -- otherwise.
    local newPos = {
        AnchorFrom = currentPos.AnchorFrom,
        AnchorTo = currentPos.AnchorTo,
        XOffset = KE:RoundOffset((currentPos.XOffset or 0) + deltaX),
        YOffset = KE:RoundOffset((currentPos.YOffset or 0) + deltaY),
    }

    -- Save and apply
    element.setPosition(newPos)

    -- Update overlay position
    if self.overlayFrames[self.selectedElementKey] then
        C_Timer.After(0, function()
            self:UpdateOverlayPosition(self.overlayFrames[self.selectedElementKey])
        end)
    end

    -- Update nudge frame display
    self:UpdateNudgeFrameInfo()

    -- Refresh GUI if open
    if KE.GUIFrame and KE.GUIFrame.mainFrame and KE.GUIFrame.mainFrame:IsShown() then
        KE.GUIFrame:RefreshContent()
    end

    -- The key handler swallows an arrow only when this says a position moved.
    return true
end

function EditMode:ShowNudgeFrame()
    if not self.nudgeFrame then
        self:CreateNudgeFrame()
    end
    self.nudgeFrame:Show()
    self:UpdateNudgeFrameInfo()
    self:UpdateCategorySelector()
end

function EditMode:HideNudgeFrame()
    if self.nudgeFrame then
        -- Hiding the tool hides the list with it, but a child keeps its own
        -- shown state, so without this it reopens still expanded next time.
        self:CloseCategoryList()
        self.nudgeFrame:Hide()
    end
    self.selectedElementKey = nil
end

-- NOTE: A per-frame StartPositionUpdates/StopPositionUpdates driver used to
-- live here but was dead code (never called) — overlays auto-track their target
-- via anchors to the target frame in UpdateOverlayPosition, so no polling is
-- needed. Removed to drop the unused OnUpdate path entirely.
