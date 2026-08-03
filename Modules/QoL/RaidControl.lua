-- ===========================================================================
-- Raid Control
--
-- A draggable "Raid Control" button pinned to the top (or bottom) edge of the
-- screen whenever you are in a group. Click it and a utility panel drops out:
--   Ready Check
--   10s / 20s Countdown  (shift-click either one cancels a running countdown)
--   Dungeon Difficulty dropdown + Everyone Assist checkbox
--   Group Sort row       (only when the Group Sort engine is present)
--   Shared Notes         (only when NorthernSkyRaidTools is loaded)
--   World-marker bar (secure) and role-count icons with a roster tooltip
--
-- The panel REPLACES Blizzard's Raid Manager flyout: enabling this module
-- hides that frame outright. Restoring it takes a /reload after disabling.
--
-- Taint/combat discipline: every secure attribute write and every Show/Hide
-- of a secure frame is InCombatLockdown-guarded, and state changes asked for
-- during combat are deferred to PLAYER_REGEN_ENABLED. Open/close of the panel
-- itself runs through secure handler snippets, so it still works in combat.
--
-- ONE EXCEPTION, and it is deliberate. OnDisable's combat deferral cannot
-- fire: Ace tears the module's events down immediately afterwards, so the
-- PLAYER_REGEN_ENABLED it registers is unregistered before the event arrives.
-- Disabling in combat therefore leaves the button up until a reload. Only a
-- profile switch can reach that path -- the config window hides itself in
-- combat -- so it is left exactly as the reference wrote it.
--
-- Performance: fully event-driven (GROUP_ROSTER_UPDATE, PLAYER_ENTERING_WORLD,
-- PARTY_LEADER_CHANGED, PLAYER_DIFFICULTY_CHANGED and the combat events).
-- Zero OnUpdate, zero per-frame cost.
-- ===========================================================================

---@class KE
local KE = select(2, ...)

if not KitnEssentials then
    error("RaidControl: Addon object not initialized. Check file load order!")
    return
end

---@class RaidControl: AceModule, AceEvent-3.0
local RC = KitnEssentials:NewModule("RaidControl", "AceEvent-3.0")

local _G = _G
local next, floor = next, floor
local mod = _G.mod
local strsub, format = strsub, format
local gsub = _G.gsub
local tinsert, wipe, sort = tinsert, wipe, sort
local ipairs, select = ipairs, select

local CreateFrame = CreateFrame
local type, pcall = type, pcall
local GameTooltip_Hide = GameTooltip_Hide
local GetDungeonDifficultyID = _G.GetDungeonDifficultyID
local GetNumGroupMembers = GetNumGroupMembers
local GetRaidRosterInfo = GetRaidRosterInfo
local GetTexCoordsByGrid = _G.GetTexCoordsByGrid
local InCombatLockdown = InCombatLockdown
local IsEveryoneAssistant = _G.IsEveryoneAssistant
local IsInGroup = IsInGroup
local IsInInstance = IsInInstance
local IsInRaid = IsInRaid
local PlaySound = PlaySound
local SecureHandlerSetFrameRef = _G.SecureHandlerSetFrameRef
local SetDungeonDifficultyID = _G.SetDungeonDifficultyID
local UnitClass = UnitClass
local UnitExists = UnitExists
local UnitGroupRolesAssigned = UnitGroupRolesAssigned
local UnitIsGroupAssistant = _G.UnitIsGroupAssistant
local UnitIsGroupLeader = UnitIsGroupLeader
local UnitName = UnitName
local UIParent = UIParent

local SetEveryoneIsAssistant = C_PartyInfo.SetEveryoneIsAssistant
local DoReadyCheck = C_PartyInfo.DoReadyCheck
local DoCountdown = C_PartyInfo.DoCountdown
local IsShiftKeyDown = IsShiftKeyDown

local IG_MAINMENU_OPTION_CHECKBOX_ON = _G.SOUNDKIT and _G.SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON
local RAID_CLASS_COLORS = RAID_CLASS_COLORS
local PRIEST_COLOR = RAID_CLASS_COLORS.PRIEST
local NUM_RAID_GROUPS = _G.NUM_RAID_GROUPS or 8
local NUM_RAID_ICONS = _G.NUM_RAID_ICONS or 8
local PANEL_WIDTH = 250
-- Panel height WITH the two Group Sort rows and WITHOUT the Shared Notes row.
-- Step 8's arithmetic adjusts from this baseline in both directions.
local PANEL_HEIGHT = 155
local BUTTON_HEIGHT = 20
local BUTTON_WIDTH = PANEL_WIDTH - 20
local TARGET_SIZE = 22

local CWM = _G.SLASH_CLEAR_WORLD_MARKER1
local WM = _G.SLASH_WORLD_MARKER1

local roleRoster = {}
local roleCount = {}
local roles = {
    { role = "TANK" },
    { role = "HEALER" },
    { role = "DAMAGER" },
}

local buttonEvents = { "GROUP_ROSTER_UPDATE", "PARTY_LEADER_CHANGED" }

local function SetGrabCoords(data, xOffset, yOffset)
    data.texA, data.texB, data.texC, data.texD = GetTexCoordsByGrid(xOffset, yOffset, 256, 256, 67, 67)
end

SetGrabCoords(roles[1], 1, 2)
SetGrabCoords(roles[2], 2, 1)
SetGrabCoords(roles[3], 2, 2)

function RC:UpdateDB()
    self.db = KE.db.profile.RaidControl
end

function RC:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

-- --- Predicates -------------------------------------------------------------
local function NotInPVP()
    local _, instanceType = IsInInstance()
    return instanceType ~= "pvp" and instanceType ~= "arena"
end

local function IsLeader()
    return UnitIsGroupLeader("player") and NotInPVP()
end

local function HasPermission()
    return (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) and NotInPVP()
end

local function InGroup()
    return IsInGroup() and NotInPVP()
end

-- Screen half the button currently sits in (drives drop direction and the
-- role tooltip anchor).
local function ScreenPosition(frame)
    local x, y = KE.Skins.SafeCenter(frame)
    local w, h = UIParent:GetSize()
    return (y or 0) < h / 2, (x or 0) < w / 2 -- bottom, left
end

-- --- Widget factories -------------------------------------------------------
-- Leader-gated buttons grey their label when the player lacks permission.
local function SetButtonEnabled(button, enabled, isLeader)
    if button.SetChecked then
        button:SetChecked(enabled)
    else
        button.enabled = enabled
    end

    if button.Text then -- grey when isLeader is explicitly false
        button.Text:SetFormattedText("%s%s|r",
            ((isLeader ~= nil and isLeader) or (isLeader == nil and enabled)) and "|cFFffffff" or "|cFF888888",
            button.label)
    end
end

local function CreateUtilButton(name, parent, template, width, height, point, relativeto, point2, xOfs, yOfs, label, events, eventFunc, mouseFunc)
    local S = KE.Skins
    local btn = CreateFrame("Button", name, parent, template)
    btn:SetSize(width, height)
    S.Button(btn)
    btn.label = label or ""

    if events then
        btn:UnregisterAllEvents()
        for _, event in next, events do
            btn:RegisterEvent(event)
        end
    end

    btn:SetScript("OnEvent", eventFunc)
    btn:SetScript("OnMouseUp", mouseFunc)

    if point then
        btn:SetPoint(point, relativeto, point2, xOfs, yOfs)
    end

    if label then
        -- Blank button text, English client so not the locale gap: raw
        -- fontstrings had NO inherited font object -- if the custom SetFont
        -- fails on a client for any reason, the string has no font at all
        -- and renders NOTHING (the dropdown/checkbox labels survived
        -- because they inherit Blizzard objects). Inherit GameFontHighlight
        -- as the floor: worst case is wrong typeface, never invisible
        -- controls.
        local text = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        S.SetFont(text, 12, "")
        text:SetPoint("CENTER", btn, "CENTER", 0, 0)
        text:SetJustifyH("CENTER")
        text:SetText(btn.label)
        btn:SetFontString(text)
        btn.Text = text
    end

    if eventFunc then
        eventFunc(btn)
    end

    return btn
end

local function CreateDropdown(name, parent, width, point, relativeto, point2, xOfs, yOfs, label, events, eventFunc, setupFunc)
    local S = KE.Skins
    local dropdown = CreateFrame("DropdownButton", name, parent, "WowStyle1DropdownTemplate")
    dropdown:SetWidth(width)

    if events then
        dropdown:UnregisterAllEvents()
        for _, event in next, events do
            dropdown:RegisterEvent(event)
        end
    end

    dropdown:SetScript("OnEvent", eventFunc)
    dropdown:SetPoint(point, relativeto, point2, xOfs, yOfs)

    S.DropDown(dropdown, true)

    if label then
        dropdown.label = dropdown:CreateFontString(nil, "OVERLAY")
        S.SetFont(dropdown.label, 12, "")
        dropdown.label:SetPoint("LEFT", dropdown, "RIGHT", 4, 0)
        dropdown.label:SetText(label)
    end

    setupFunc(dropdown)

    if eventFunc then
        eventFunc(dropdown)
    end

    return dropdown
end

local function CreateCheckBox(name, parent, size, point, relativeto, point2, xOfs, yOfs, label, events, eventFunc, clickFunc)
    local S = KE.Skins
    local box = CreateFrame("CheckButton", name, parent, "UICheckButtonTemplate")
    box:SetSize(size, size)
    box.label = label or ""

    if events then
        box:UnregisterAllEvents()
        for _, event in next, events do
            box:RegisterEvent(event)
        end
    end

    box:SetScript("OnEvent", eventFunc)
    box:SetScript("OnClick", clickFunc)

    S.CheckBox(box)

    if box.Text then
        box.Text:SetPoint("LEFT", box, "RIGHT", 2, 0)
        box.Text:SetText(box.label)
        S.SetFont(box.Text, 12, "")
    end

    box:SetPoint(point, relativeto, point2, xOfs, yOfs)

    if eventFunc then
        eventFunc(box)
    end

    return box
end

-- --- Marker buttons ---------------------------------------------------------
local function TargetIcons_GetCoords(button)
    local index = button:GetID()
    local idx = (index - 1) * 0.25

    local left = mod(idx, 1)
    local right = left + 0.25
    local top = floor(idx) * 0.25
    local bottom = top + 0.25

    button:GetNormalTexture():SetTexCoord(left, right, top, bottom)
end

do
    -- ground[] is the world-marker id order that makes the flag colours
    -- line up with the target-icon art on the same button.
    local ground = { 5, 6, 3, 2, 7, 1, 4, 8 }

    -- WORLD MARKERS ONLY. Target-marker behavior and the modifier-swap
    -- machinery removed entirely -- every click type places (or clears)
    -- world markers.
    function RC:TargetIcons_UpdateMacro(button, i)
        button:SetAttribute("isclearbutton", i == 0)

        if i == 0 then
            button:SetAttribute("type1", "worldmarker")
            button:SetAttribute("type2", "worldmarker")
            button:SetAttribute("type3", "worldmarker")
            button:SetAttribute("action", "clear")
        else
            local id = ground[i]
            local wm = format("%s %d\n%s %d", CWM, id, WM, id)
            button:SetAttribute("type1", "macro")
            button:SetAttribute("type2", "macro")
            button:SetAttribute("type3", "macro")
            button:SetAttribute("macrotext1", wm)
            button:SetAttribute("macrotext2", wm)
            button:SetAttribute("macrotext3", wm)
        end
    end
end

local function TargetIcons_MouseDown(self)
    local tex = self:GetNormalTexture()
    local width, height = self:GetSize()
    tex:SetSize(width - 4, height - 4)
end

local function TargetIcons_MouseUp(self)
    self:GetNormalTexture():SetSize(self:GetSize())
end

-- Marker buttons carry no tooltip on purpose: the option was removed and the
-- eight icons plus the clear button are self-explanatory in place.

function RC:CreateTargetIcons(panel)
    local S = KE.Skins
    local TargetIcons = CreateFrame("Frame", "KE_RaidControlTargetIcons", panel)
    TargetIcons:SetSize(PANEL_WIDTH, BUTTON_HEIGHT + 8)
    S.Backdrop(TargetIcons)

    local num, previous = NUM_RAID_ICONS + 1, nil -- include clear
    for i = 1, num do
        local id = num - i
        local button = CreateFrame("Button", "$parent_TargetIcon" .. i, TargetIcons, "SecureActionButtonTemplate")
        button:SetScript("OnMouseDown", TargetIcons_MouseDown)
        button:SetScript("OnMouseUp", TargetIcons_MouseUp)
        button:SetAttribute("type1", "macro")
        button:SetAttribute("type2", "macro")
        button:SetAttribute("type3", "macro")
        button:SetNormalTexture(i == num and [[Interface\Buttons\UI-GroupLoot-Pass-Up]] or [[Interface\TargetingFrame\UI-RaidTargetingIcons]])
        button:SetID(id)
        button:SetSize(TARGET_SIZE, TARGET_SIZE)
        button:RegisterForClicks("AnyDown", "AnyUp")

        self:TargetIcons_UpdateMacro(button, id)

        if i == 1 then
            -- Shift left: 9x22 + 8x6 gaps = 246px in the 250 plate; the old
            -- 6px left pad overflowed the right edge by 2px. 2px pad =
            -- symmetric.
            button:SetPoint("TOPLEFT", TargetIcons, 2, -3)
        else
            button:SetPoint("LEFT", previous, "RIGHT", 6, 0)
        end
        previous = button

        local tex = button:GetNormalTexture()
        tex:ClearAllPoints()
        tex:SetPoint("CENTER", button)
        tex:SetSize(TARGET_SIZE, TARGET_SIZE)

        if i ~= num then
            TargetIcons_GetCoords(button)
        end
    end

    return TargetIcons
end

-- --- Role icons ----------------------------------------------------------
local function RoleIcons_SortNames(a, b)
    return strsub(a, 11) < strsub(b, 11) -- skip the |cffxxxxxx prefix
end

local function RoleIcons_AddNames(tbl, name, unitClass)
    local color = (unitClass and RAID_CLASS_COLORS[unitClass]) or PRIEST_COLOR
    tinsert(tbl, format("|cff%02x%02x%02x%s", color.r * 255, color.g * 255, color.b * 255, gsub(name, "%-.+", "*")))
end

local function RoleIcons_AddPartyUnit(unit, iconRole)
    local name = UnitExists(unit) and UnitName(unit)
    local unitRole = name and UnitGroupRolesAssigned(unit)
    if unitRole == iconRole then
        local _, unitClass = UnitClass(unit)
        RoleIcons_AddNames(roleRoster[0], name, unitClass)
    end
end

local function OnEnter_Role(self)
    wipe(roleRoster)

    for i = 0, NUM_RAID_GROUPS do -- 0 is the party bucket
        roleRoster[i] = {}
    end

    local iconRole = self.role
    local isRaid = IsInRaid()
    if IsInGroup() and not isRaid then
        RoleIcons_AddPartyUnit("player", iconRole)
    end

    for i = 1, GetNumGroupMembers() do
        if isRaid then
            local name, _, group, _, _, unitClass, _, _, _, _, _, unitRole = GetRaidRosterInfo(i)
            if name and unitRole == iconRole then
                RoleIcons_AddNames(roleRoster[group], name, unitClass)
            end
        else
            RoleIcons_AddPartyUnit("party" .. i, iconRole)
        end
    end

    -- Giant flashing tooltip, two defects. (1) A UIParent-owned ANCHOR_NONE
    -- tooltip's lifetime isn't tied to the hovered frame and gets reclaimed
    -- instantly -- own it by self, like the marker tooltips (which never
    -- flashed). (2) The INLINE_<ROLE>_ICON title escapes are dimension-less
    -- atlas markup on Midnight and render at natural atlas size (the
    -- "giant"); use the plain localized title instead. Also: the old quadrant
    -- math destructured two returns from single-return ScreenPosition, so
    -- `left` was always nil -- gone with the pattern.
    local GameTooltip = _G.GameTooltip
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:SetText(_G[iconRole])

    for group, list in next, roleRoster do
        sort(list, RoleIcons_SortNames)

        for _, name in next, list do
            GameTooltip:AddLine((group == 0 and name) or format("[%d] %s", group, name), 1, 1, 1)
        end

        roleRoster[group] = nil
    end

    GameTooltip:Show()
end

function RC:OnEvent_RoleIcons(event, initLogin, isReload)
    self:PositionSections()

    if event ~= "PLAYER_ENTERING_WORLD" or (initLogin or isReload) then
        wipe(roleCount)

        if IsInRaid() then
            for i = 1, GetNumGroupMembers() do
                local role = select(12, GetRaidRosterInfo(i))
                if role and role ~= "NONE" then roleCount[role] = (roleCount[role] or 0) + 1 end
            end
        elseif IsInGroup() then
            for i = 1, GetNumGroupMembers() - 1 do
                local role = UnitGroupRolesAssigned("party" .. i)
                if role and role ~= "NONE" then roleCount[role] = (roleCount[role] or 0) + 1 end
            end
            local myrole = UnitGroupRolesAssigned("player")
            if myrole and myrole ~= "NONE" then roleCount[myrole] = (roleCount[myrole] or 0) + 1 end
        end

        for role, icon in next, self.RoleIcons.icons do
            icon.count:SetText(roleCount[role] or 0)
        end
    end
end

function RC:CreateRoleIcons(panel)
    local S = KE.Skins
    local RoleIcons = CreateFrame("Frame", "KE_RaidControlRoleIcons", panel)
    -- "icon: #" pairs -- count beside the icon instead of overlaid on it,
    -- three cells evenly spaced. Plate widened to 0.44 for breathing room;
    -- Close computes its width from the plate so the flush right edge
    -- holds.
    RoleIcons:SetSize(PANEL_WIDTH * 0.44, BUTTON_HEIGHT + 8)
    S.Backdrop(RoleIcons)
    RoleIcons:RegisterEvent("PLAYER_ENTERING_WORLD")
    RoleIcons:RegisterEvent("GROUP_ROSTER_UPDATE")
    RoleIcons:SetScript("OnEvent", function(_, event, a, b) RC:OnEvent_RoleIcons(event, a, b) end)
    RoleIcons.icons = {}

    -- Plate contents off-center: each icon+count pair centers within its
    -- third of the plate, making lead and trail space symmetric. pairW =
    -- 18px icon + 3 gap + ~8px digit.
    local cellW = (PANEL_WIDTH * 0.44) / 3
    -- Two-digit raid counts clipped the plate edge: icon-to-count gap
    -- tightened to 1px and the centering budget now assumes two digits, so
    -- "15" stays inside its cell.
    local pairW = 33 -- 18 icon + 1 gap + ~14 two-digit count
    for i, data in ipairs(roles) do
        local frame = CreateFrame("Frame", "$parent_" .. data.role, RoleIcons)
        frame:SetSize(18, 18)
        frame:SetPoint("LEFT", RoleIcons, "LEFT", (i - 1) * cellW + (cellW - pairW) / 2, 0)

        -- Modern role icons (KE.ROLE_ICONS, shared with the LFG skin),
        -- 1px border (S.Backdrop), art inset 1px.
        S.Backdrop(frame)
        local texture = frame:CreateTexture(nil, "OVERLAY")
        texture:SetTexture(KE.ROLE_ICONS[data.role])
        texture:SetTexCoord(0, 1, 0, 1)
        texture:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
        texture:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
        frame.texture = texture

        local Count = frame:CreateFontString(nil, "OVERLAY")
        S.SetFont(Count, 12, "OUTLINE")
        Count:SetPoint("LEFT", frame, "RIGHT", 1, 0)
        Count:SetText(0)
        frame.count = Count

        frame.role = data.role
        frame:SetScript("OnEnter", OnEnter_Role)
        frame:SetScript("OnLeave", GameTooltip_Hide)

        RoleIcons.icons[data.role] = frame
    end

    self.RoleIcons = RoleIcons
    return RoleIcons
end

-- --- Section anchoring ------------------------------------------------------
local function ReanchorSection(section, bottom, target)
    if section then
        -- Marker bar + role icons never rendered: some UI frameworks wrap
        -- SetPoint and resolve a nil relativeTo as the frame's PARENT. Native
        -- 5-arg SetPoint does not -- on Midnight the nil-target call fails,
        -- the sections get no points, and unanchored frames don't draw.
        -- Resolve the target explicitly.
        -- DOCTRINE: wrapper APIs (:Point/:Size/:SetInside) carry nil-argument
        -- semantics native calls don't -- check the wrapper when porting, not
        -- just the call site.
        target = target or section:GetParent()
        section:ClearAllPoints()
        if bottom then
            section:SetPoint("BOTTOMLEFT", target, "TOPLEFT", 0, 1)
        else
            section:SetPoint("TOPLEFT", target, "BOTTOMLEFT", 0, -1)
        end
    end
end

function RC:OnRegen_PositionSections()
    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
    self._positionDirty = nil
    self:PositionSections()
end

function RC:PositionSections()
    if not self.setup then return end
    -- User-facing ADDON_ACTION_BLOCKED: since the SECURE Close button
    -- anchors to RoleIcons, drafting RoleIcons into the protected anchor
    -- chain -- moving it in combat is now a protected operation, same as
    -- TargetIcons always was. Combat-deferred dirty flag: bail entirely in
    -- combat, replay the full layout on PLAYER_REGEN_ENABLED.
    if InCombatLockdown() then
        if not self._positionDirty then
            self._positionDirty = true
            self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnRegen_PositionSections")
        end
        return
    end
    local bottom = ScreenPosition(self.ShowButton)
    ReanchorSection(self.TargetIcons, bottom, nil) -- nil target = panel (parent)
    ReanchorSection(self.RoleIcons, bottom, self.TargetIcons)
end

-- --- Show/hide driver -------------------------------------------------------
function RC:ToggleRaidControl(event)
    if InCombatLockdown() then
        self:RegisterEvent("PLAYER_REGEN_ENABLED", "ToggleRaidControl")
        return
    end

    local panel = self.Panel
    local status = InGroup()
    self.ShowButton:SetShown(status and not panel.toggled)
    panel:SetShown(status and panel.toggled)

    if event == "PLAYER_REGEN_ENABLED" then
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
    end
end

-- --- Drag / position persistence --------------------------------------------
local function DragStart_ShowButton(self)
    if InCombatLockdown() then return end
    self:StartMoving()
end

local function DragStop_ShowButton(self)
    if InCombatLockdown() then return end
    self:StopMovingOrSizing()

    local xOffset = self:GetCenter()
    xOffset = xOffset - UIParent:GetWidth() * 0.5
    local bottom = ScreenPosition(self)

    self:ClearAllPoints()
    if bottom then
        self:SetPoint("BOTTOM", UIParent, "BOTTOM", xOffset, -1)
    else
        self:SetPoint("TOP", UIParent, "TOP", xOffset, 1)
    end

    local pos = RC.db.Position
    pos.bottom = bottom and true or false
    pos.x = xOffset

    RC:PositionSections()
end

-- --- Click handlers ----------------------------------------------------------
local function OnClick_ShowButton(self)
    RC.Panel.toggled = true
    RC:PositionSections()
end

local function OnClick_CloseButton()
    RC.Panel.toggled = false
end

local function OnEvent_PermissionButton(self)
    SetButtonEnabled(self, HasPermission())
end

local function OnClick_ReadyCheckButton(self)
    if self.enabled and InGroup() and not InCombatLockdown() then
        DoReadyCheck()
    end
end

-- Shift-click on either countdown button cancels a running countdown --
-- DoCountdown(0), same as /pull 0.
local function OnClick_Countdown10()
    if InGroup() and not InCombatLockdown() then
        DoCountdown(IsShiftKeyDown() and 0 or 10)
    end
end

local function OnClick_Countdown20()
    if InGroup() and not InCombatLockdown() then
        DoCountdown(IsShiftKeyDown() and 0 or 20)
    end
end

local function OnClick_EveryoneAssist(self)
    if IsLeader() then
        if not InCombatLockdown() then
            PlaySound(IG_MAINMENU_OPTION_CHECKBOX_ON)
            SetEveryoneIsAssistant(self:GetChecked())
        end
    else
        self:SetChecked(IsEveryoneAssistant())
    end
end

local function OnEvent_EveryoneAssist(self)
    SetButtonEnabled(self, IsEveryoneAssistant(), IsLeader())
end

-- --- Dropdown menus (Midnight menu API) --------------------------------------
local function SetupDungeonDifficulty(dropdown)
    local function IsSelected(difficultyID)
        return GetDungeonDifficultyID() == difficultyID
    end
    local function SetSelected(difficultyID)
        SetDungeonDifficultyID(difficultyID)
    end
    dropdown:SetupMenu(function(_, root)
        root:SetTag("KE_RAID_CONTROL_DIFFICULTY")
        root:CreateRadio(_G.PLAYER_DIFFICULTY1, IsSelected, SetSelected, 1)
        root:CreateRadio(_G.PLAYER_DIFFICULTY2, IsSelected, SetSelected, 2)
        root:CreateRadio(_G.PLAYER_DIFFICULTY6, IsSelected, SetSelected, 23)
    end)
end

local function OnEvent_RefreshMenu(self)
    self:GenerateMenu()
end

-- --- Group Sort row (optional; the engine ships separately) ---------------

-- --- Setup -------------------------------------------------------------------
-- Frames parked here are hidden for the session: Hide, mouse off, events off,
-- statehidden for secure templates, and reparented so nothing re-shows them.
local hiddenParent = CreateFrame("Frame")
hiddenParent:Hide()

local function HideFrame(object)
    if type(object) == "string" then object = _G[object] end
    if not object then return end

    if object.HideBase then
        object:HideBase(true) -- Edit Mode adds this fallback when it overrides Hide
    else
        object:Hide(true)
    end

    if object.EnableMouse then
        object:EnableMouse(false)
    end

    if object.UnregisterAllEvents then
        object:UnregisterAllEvents()
        object:SetAttribute("statehidden", true)
    end

    if object.SetUserPlaced then
        pcall(object.SetUserPlaced, object, true)
        pcall(object.SetDontSavePosition, object, true)
    end

    object:SetParent(hiddenParent)
end

function RC:Setup()
    if self.setup then return end
    self.setup = true

    local S = KE.Skins
    local db = self.db

    -- This panel REPLACES the Blizzard Raid Manager (the left-edge flyout
    -- tab): full kill via the frame hider (Hide + UnregisterAllEvents +
    -- reparent), so roster events can't re-show it. The raid FRAMES are
    -- unaffected -- CompactRaidFrameContainer is parented to UIParent on
    -- Midnight (Edit Mode managed), verified against wow-ui-source.
    -- Restoring the Blizzard manager takes a /reload after disabling.
    HideFrame(_G.CompactRaidFrameManager)

    -- Panel (secure base so the show button's snippet can drive it in combat)
    local panel = CreateFrame("Frame", "KE_RaidControlPanel", UIParent, "SecureHandlerBaseTemplate")
    S.Backdrop(panel)
    -- Two blocks are conditional. Resize the panel by each absent or present
    -- block (BUTTON_HEIGHT + a 3px gap per row) instead of leaving dead space.
    -- PANEL_HEIGHT already includes the two Group Sort rows and excludes the
    -- Shared Notes row -- see the comment on PANEL_HEIGHT itself.
    local hasGroupSort = KE.GroupSort ~= nil
    local hasSharedNotes = _G.C_AddOns and _G.C_AddOns.IsAddOnLoaded("NorthernSkyRaidTools")
    local panelHeight = PANEL_HEIGHT
    if not hasGroupSort then panelHeight = panelHeight - 2 * (BUTTON_HEIGHT + 3) end
    if hasSharedNotes then panelHeight = panelHeight + (BUTTON_HEIGHT + 3) end
    panel:SetSize(PANEL_WIDTH, panelHeight)
    panel:SetPoint("TOP", UIParent, "TOP", -400, 1)
    panel:SetFrameLevel(3)
    panel:SetFrameStrata("HIGH")
    panel.toggled = false
    panel:Hide()
    self.Panel = panel

    -- Show button
    local pos = db.Position
    local ShowButton = CreateUtilButton("KE_RaidControlShowButton", UIParent, "SecureHandlerClickTemplate",
        136, BUTTON_HEIGHT, nil, nil, nil, nil, nil, _G.RAID_CONTROL or "Raid Control", nil, nil, OnClick_ShowButton)
    if pos.bottom then
        ShowButton:SetPoint("BOTTOM", UIParent, "BOTTOM", pos.x or -400, -1)
    else
        ShowButton:SetPoint("TOP", UIParent, "TOP", pos.x or -400, 1)
    end
    ShowButton:SetMovable(true)
    ShowButton:SetClampedToScreen(true)
    ShowButton:SetClampRectInsets(0, 0, -1, 1)
    ShowButton:SetFrameStrata("HIGH")
    ShowButton:RegisterForDrag("RightButton")
    ShowButton:SetScript("OnDragStart", DragStart_ShowButton)
    ShowButton:SetScript("OnDragStop", DragStop_ShowButton)
    ShowButton:Hide()
    self.ShowButton = ShowButton

    SecureHandlerSetFrameRef(ShowButton, "KE_RaidControlPanel", panel)
    ShowButton:SetAttribute("_onclick", [=[
        local utility = self:GetFrameRef('KE_RaidControlPanel')
        local close = utility:GetFrameRef('KE_RaidControlClose')

        self:Hide()
        utility:Show()
        utility:ClearAllPoints()
        close:ClearAllPoints()

        local point = self:GetPoint()
        if point and strfind(point, 'BOTTOM') then
            utility:SetPoint('BOTTOM', self)
            close:SetPoint('BOTTOMRIGHT', utility, 'TOPRIGHT', -1, 30)
        else
            utility:SetPoint('TOP', self)
            close:SetPoint('TOPRIGHT', utility, 'BOTTOMRIGHT', -1, -30)
        end
    ]=])

    self.TargetIcons = self:CreateTargetIcons(panel)

    local CloseButton = CreateUtilButton("KE_RaidControlClose", panel, "SecureHandlerClickTemplate",
        PANEL_WIDTH * 0.6, BUTTON_HEIGHT + 8, "TOP", panel, "BOTTOM", 0, 0, _G.CLOSE or "Close", nil, nil, OnClick_CloseButton)
    SecureHandlerSetFrameRef(CloseButton, "KE_RaidControlShowButton", ShowButton)
    CloseButton:SetAttribute("_onclick", [=[self:GetParent():Hide(); self:GetFrameRef('KE_RaidControlShowButton'):Show()]=])
    SecureHandlerSetFrameRef(panel, "KE_RaidControlClose", CloseButton)

    -- Row 1: Ready Check, full width.
    -- Top rows started 5px further left than the rest: the
    -- dropdown/assist/Group Sort chain resolves to x=10; Ready Check and
    -- the countdowns anchored at x=5. Aligned: left edge 10, right edge
    -- 10 + BUTTON_WIDTH (matching the utility rows below), countdown halves
    -- sized (BUTTON_WIDTH - 5) / 2 so the pair plus its 5px gap lands on
    -- the same right edge.
    local ReadyCheckButton = CreateUtilButton("KE_RaidControlReadyCheck", panel, nil,
        BUTTON_WIDTH, BUTTON_HEIGHT, "TOPLEFT", panel, "TOPLEFT", 10, -4,
        _G.READY_CHECK or "Ready Check", buttonEvents, OnEvent_PermissionButton, OnClick_ReadyCheckButton)

    -- Row 2: 10s Countdown | 20s Countdown
    local Countdown10Button = CreateUtilButton("KE_RaidControlCountdown10", panel, nil,
        (BUTTON_WIDTH - 5) * 0.5, BUTTON_HEIGHT, "TOPLEFT", ReadyCheckButton, "BOTTOMLEFT", 0, -5,
        "10s Countdown", nil, nil, OnClick_Countdown10)
    CreateUtilButton("KE_RaidControlCountdown20", panel, nil,
        (BUTTON_WIDTH - 5) * 0.5, BUTTON_HEIGHT, "TOPLEFT", Countdown10Button, "TOPRIGHT", 5, 0,
        "20s Countdown", nil, nil, OnClick_Countdown20)

    -- Row 3: Dungeon Difficulty
    local DifficultyDropdown = CreateDropdown("KE_RaidControlDifficulty", panel, 85,
        "TOPLEFT", Countdown10Button, "BOTTOMLEFT", 0, -5, -- rows now share x=10
        _G.CRF_DIFFICULTY or "Difficulty", { "PLAYER_DIFFICULTY_CHANGED" }, OnEvent_RefreshMenu, SetupDungeonDifficulty)

    -- Everyone Assist
    local EveryoneAssist = CreateCheckBox("KE_RaidControlEveryoneAssist", panel, BUTTON_HEIGHT + 4,
        "TOPLEFT", DifficultyDropdown, "BOTTOMLEFT", -4, -3,
        _G.ALL_ASSIST_LABEL_LONG or "Everyone is Assistant", buttonEvents, OnEvent_EveryoneAssist, OnClick_EveryoneAssist)

    local lastUtilRow = EveryoneAssist
    local lastUtilXOfs, lastUtilYOfs = 4, -3

    if hasGroupSort then
        -- Combat-gated: SetEnabled(false) blocks input, grey text signals it.
        -- The hard gate lives in GroupSort:Run; this is the visual layer.
        -- eventFunc also runs once at creation, so a /reload mid-combat starts
        -- the buttons in the correct state.
        local sortButtonEvents = { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }
        local function OnEvent_SortButton(self)
            local inCombat = _G.InCombatLockdown()
            self:SetEnabled(not inCombat)
            if self.Text then
                if inCombat then
                    self.Text:SetTextColor(0.5, 0.5, 0.5)
                else
                    self.Text:SetTextColor(1, 1, 1)
                end
            end
        end
        local SortDefault = CreateUtilButton("KE_RaidControlSortDefault", panel, nil,
            BUTTON_WIDTH, BUTTON_HEIGHT, "TOPLEFT", EveryoneAssist, "BOTTOMLEFT", 4, -3,
            "Default Arrangement", sortButtonEvents, OnEvent_SortButton,
            function() KE.GroupSort:Run("default") end)
        local SplitGroups = CreateUtilButton("KE_RaidControlSplitGroups", panel, nil,
            (BUTTON_WIDTH - 5) * 0.5, BUTTON_HEIGHT, "TOPLEFT", SortDefault, "BOTTOMLEFT", 0, -3,
            "Split Groups", sortButtonEvents, OnEvent_SortButton,
            function() KE.GroupSort:Run("split") end)
        CreateUtilButton("KE_RaidControlSplitOdds", panel, nil,
            (BUTTON_WIDTH - 5) * 0.5, BUTTON_HEIGHT, "TOPLEFT", SplitGroups, "TOPRIGHT", 5, 0,
            "Evens/Odds", sortButtonEvents, OnEvent_SortButton,
            function() KE.GroupSort:Run("odds") end)
        lastUtilRow = SplitGroups
        lastUtilXOfs, lastUtilYOfs = 0, -3
    end

    -- NSRT Shared Notes: opens NorthernSkyRaidTools' window on the
    -- SharedNotes tab. NSRT's internals are addon-private; the public
    -- contract is the slash command (/ns reminders -> NSUI:Show() +
    -- SelectTabByName("SharedNotes"), SlashCommands.lua:25), reachable via
    -- SlashCmdList["NSUI"] -- literally "as if typed".
    if hasSharedNotes then
        -- The button is a TOGGLE for NSRT's window; our panel stays open.
        -- NSRT's window is the global NSUI frame (DF:CreateSimplePanel 5th
        -- arg, UI/Core.lua:177); when shown, we press its LITERAL X
        -- (frame.Close, LibDFramework panel.lua:2359) via :Click() so DF's
        -- own close handler and hooks run. Everything here is insecure --
        -- no combat gate in either direction.
        CreateUtilButton("KE_RaidControlNSRTNotes", panel, nil,
            BUTTON_WIDTH, BUTTON_HEIGHT, "TOPLEFT", lastUtilRow,
            "BOTTOMLEFT", lastUtilXOfs, lastUtilYOfs,
            "Shared Notes", nil, nil, function()
                local f = _G.NSUI
                if f and f.IsShown and f:IsShown() then
                    local x = f.Close or f.CloseButton
                    if x and x.Click then x:Click() else f:Hide() end
                    return
                end
                local handler = _G.SlashCmdList and _G.SlashCmdList.NSUI
                if not handler or not pcall(handler, "reminders") then
                    KE:Print("Shared Notes: the Northern Sky Raid Tools command is unavailable (addon updated?)")
                end
            end)
    end

    -- Role check exists on Midnight, add the icon strip
    self:CreateRoleIcons(panel)

    -- Close matches the role-icon plate exactly -- top/bottom pinned to
    -- RoleIcons (no more height mismatch), right edge landing on
    -- PANEL_WIDTH like the marker row above. Also an explicit opaque
    -- fill; the control-grey 0.90 read too transparent next to the
    -- plates.
    local closeBtn = _G.KE_RaidControlClose
    if closeBtn and self.RoleIcons then
        closeBtn:ClearAllPoints()
        closeBtn:SetPoint("TOPLEFT", self.RoleIcons, "TOPRIGHT", 5, 0)
        closeBtn:SetPoint("BOTTOMLEFT", self.RoleIcons, "BOTTOMRIGHT", 5, 0)
        closeBtn:SetWidth(PANEL_WIDTH - self.RoleIcons:GetWidth() - 5)
        -- Opaque override removed -- Close read darker than its
        -- siblings; standard S.Button fill everywhere.
    end
    self:PositionSections()
end

function RC:OnEnable()
    self:UpdateDB()

    if InCombatLockdown() then
        self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnCombatEnd")
        return
    end

    self:Setup()
    self:RegisterEvent("GROUP_ROSTER_UPDATE", "ToggleRaidControl")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "ToggleRaidControl")
    self:ToggleRaidControl()
end

function RC:OnCombatEnd()
    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
    if self:IsEnabled() then
        self:Setup()
        self:RegisterEvent("GROUP_ROSTER_UPDATE", "ToggleRaidControl")
        self:RegisterEvent("PLAYER_ENTERING_WORLD", "ToggleRaidControl")
        self:ToggleRaidControl()
    else
        self.ShowButton:Hide()
        self.Panel:Hide()
    end
end

function RC:OnDisable()
    self:UnregisterEvent("GROUP_ROSTER_UPDATE")
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    if not self.setup then return end

    if InCombatLockdown() then
        self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnCombatEnd")
        return
    end
    self.ShowButton:Hide()
    self.Panel:Hide()
end
