-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-FrameChooser.lua                                    ║
-- ║  Purpose: Frame picker utility for selecting anchor      ║
-- ║  frames.                                                 ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)

KE.FrameChooser = {}
local FC = KE.FrameChooser
local Theme = KE.Theme

-- Local references
local ResetCursor = ResetCursor
local tostring = tostring
local pairs = pairs
local CreateFrame = CreateFrame
local IsMouseButtonDown = IsMouseButtonDown
local SetCursor = SetCursor
local GetMouseFoci = GetMouseFoci
local GetMouseFocus = GetMouseFocus

---------------------------------------------------------------------------------
-- Frame Creation
---------------------------------------------------------------------------------

-- State
local chooserFrame = nil
local chooserBox = nil
local isActive = false
local currentCallback = nil
local originalValue = nil
local oldPick = nil
local oldPickName = nil

-- Frames that take no mouse but stand for what is hovered over them. The pick
-- is the proxy's own global name, so the saved value resolves like a typed
-- one. An array: the area test must not depend on pairs order.
local proxies = {}

-- A meter bar row is four parents below the dock; the rest is headroom.
local PROXY_WALK_LIMIT = 10

-- With no frame, KE:IsUnsafeAnchor only asks whether a value is a readable,
-- unforbidden region, testing for a secret before anything else; nil fails it.
-- Every frame the chooser touches passes it before any method is called on it.
local function IsReadable(frame)
    return not KE:IsUnsafeAnchor(nil, frame)
end

local function ReadableParent(frame)
    local parent = frame:GetParent()
    if IsReadable(parent) then return parent end
    return nil
end

-- GetName can answer secret. The second return says so, because a secret name
-- and no name mean different things to the walk.
local function ReadableName(frame)
    if type(frame.GetName) ~= "function" then return nil, false end
    local name = frame:GetName()
    if issecretvalue(name) then return nil, true end
    return name, false
end

-- Get frame name recursively, using parent key if no :GetName() exists. A
-- secret name, field or key names nothing.
local function RecurseGetName(frame)
    if not frame then return nil end

    local name, secret = ReadableName(frame)
    if secret then return nil end
    if name then
        return name
    end

    local parent = ReadableParent(frame)
    if parent then
        for key, child in pairs(parent) do
            if not issecretvalue(child) and not issecretvalue(key) and child == frame then
                local parentName = RecurseGetName(parent)
                if parentName then
                    return parentName .. "." .. tostring(key)
                end
            end
        end
    end

    return nil
end

-- Create the frame chooser UI elements
local function EnsureFrameChooserUI()
    if chooserFrame then return end

    chooserFrame = CreateFrame("Frame", "KEFrameChooser", UIParent)
    chooserFrame:SetFrameStrata("TOOLTIP")
    chooserFrame:SetAllPoints(UIParent)
    chooserFrame:EnableMouse(false)
    chooserFrame:Hide()

    -- Highlight box around hovered frame
    chooserBox = CreateFrame("Frame", nil, chooserFrame, "BackdropTemplate")
    chooserBox:SetFrameStrata("TOOLTIP")
    chooserBox:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 3,
        insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    local accent = (Theme and Theme.accent) or { 1, 0.82, 0, 1 }
    chooserBox:SetBackdropBorderColor(accent[1], accent[2], accent[3], accent[4] or 1)
    chooserBox:Hide()

    -- Instructions text
    local instructions = chooserFrame:CreateFontString(nil, "OVERLAY")
    KE:ApplyThemeFont(instructions, "large")
    instructions:SetPoint("TOP", UIParent, "TOP", 0, -50)
    instructions:SetText("Click on a frame to select it as anchor\nRight-click to cancel")
    instructions:SetTextColor(0, 1, 0, 1)
    chooserFrame.instructions = instructions
end

---------------------------------------------------------------------------------
-- Proxies
---------------------------------------------------------------------------------

local function ProxyFor(frame)
    for i = 1, #proxies do
        if proxies[i].frame == frame then return proxies[i] end
    end
    return nil
end

-- IsVisible can answer secret, which counts as hidden.
local function IsShownProxy(entry)
    local visible = entry.frame:IsVisible()
    return not issecretvalue(visible) and visible == true
end

local function Claims(entry, name)
    return entry.claims ~= nil and entry.claims(name) == true
end

-- The proxy above the focus, when every named frame between them is one the
-- proxy claims. A named frame it does not claim keeps its own pick, and a name
-- that cannot be read refuses the proxy.
local function ProxyAbove(focus)
    local current, entry = focus, nil
    for _ = 1, PROXY_WALK_LIMIT do
        if current == nil or current == UIParent then return nil end
        entry = ProxyFor(current)
        if entry then break end
        current = ReadableParent(current)
    end
    if not entry or not IsShownProxy(entry) then return nil end

    local passed = focus
    while passed ~= entry.frame do
        if passed == nil then return nil end
        local name, secret = ReadableName(passed)
        if secret or (name and not Claims(entry, name)) then return nil end
        passed = ReadableParent(passed)
    end
    return entry
end

local function ProxyClaiming(name)
    for i = 1, #proxies do
        local entry = proxies[i]
        if Claims(entry, name) and IsShownProxy(entry) then return entry end
    end
    return nil
end

-- Only for a proxy whose own area takes no mouse. IsMouseOver is secret when
-- the proxy's anchoring is, which counts as not over.
local function ProxyUnderCursor()
    for i = 1, #proxies do
        local entry = proxies[i]
        if entry.byArea and IsShownProxy(entry) then
            local over = entry.frame:IsMouseOver()
            if not issecretvalue(over) and over == true then return entry end
        end
    end
    return nil
end

-- The frame to highlight and the name to save for this focus, or nil. An Edit
-- Mode box covers the frame it stands for and is never an anchor. A focus that
-- is not a readable region counts as no focus.
local function ResolvePick(focus)
    if not IsReadable(focus) then focus = nil end
    local entry = focus and ProxyAbove(focus)
    if entry then return entry.frame, entry.name end

    local name = focus and RecurseGetName(focus)
    if name == "WorldFrame" or KE:IsEditModeBoxName(name) then name = nil end
    if name then
        entry = ProxyClaiming(name)
        if entry then return entry.frame, entry.name end
        return focus, name
    end

    entry = ProxyUnderCursor()
    if entry then return entry.frame, entry.name end
    return nil, nil
end

-- OnUpdate: track mouse, highlight frames, handle clicks
local function OnUpdateHandler(self, elapsed)
    if not isActive then return end

    -- Right-click cancels
    if IsMouseButtonDown("RightButton") then
        FC:Stop(true)
        return
    end

    -- Left-click confirms
    if IsMouseButtonDown("LeftButton") and oldPickName then
        FC:Stop(false)
        return
    end

    SetCursor("CAST_CURSOR")

    -- Get frame under cursor
    local focus
    if GetMouseFocus then
        focus = GetMouseFocus()
    elseif GetMouseFoci then
        local foci = GetMouseFoci()
        focus = foci and foci[1] or nil
    end

    local pick, pickName = ResolvePick(focus)

    -- Compared on the pick, not the focus: over the chat padding the focus
    -- stays the same while the pick changes.
    if pick ~= oldPick then
        if chooserBox then
            if pick then
                chooserBox:ClearAllPoints()
                chooserBox:SetPoint("BOTTOMLEFT", pick, "BOTTOMLEFT", -4, -4)
                chooserBox:SetPoint("TOPRIGHT", pick, "TOPRIGHT", 4, 4)
                chooserBox:Show()
            else
                chooserBox:Hide()
            end
        end

        if pickName ~= oldPickName then
            oldPickName = pickName
            if currentCallback then
                currentCallback(pickName, true)
            end
        end

        oldPick = pick
    end
end

---------------------------------------------------------------------------------
-- Logic
---------------------------------------------------------------------------------

-- `claims(name)` is true for a named frame that hovering treats as the proxy.
-- `byArea` picks the proxy by its rectangle where nothing over it takes the
-- mouse.
---@param frame Frame
---@param claims (fun(name: string): boolean)?
---@param byArea boolean?
function FC:RegisterProxy(frame, claims, byArea)
    if not IsReadable(frame) then return end
    local name, secret = ReadableName(frame)
    if secret or not name then return end
    local entry = ProxyFor(frame)
    if not entry then
        entry = { frame = frame }
        proxies[#proxies + 1] = entry
    end
    entry.name, entry.claims, entry.byArea = name, claims, byArea == true
end

-- Start frame chooser mode
function FC:Start(callback, initialValue)
    EnsureFrameChooserUI()

    if isActive then
        self:Stop(true)
    end

    isActive = true
    currentCallback = callback
    originalValue = initialValue
    oldPick = nil
    oldPickName = nil

    if chooserFrame then
        chooserFrame:SetScript("OnUpdate", OnUpdateHandler)
        chooserFrame:Show()
    end

    if KE.Print then
        KE:Print("Frame chooser active. Click a frame to select, right-click to cancel.")
    end
end

-- Stop frame chooser mode
function FC:Stop(canceled)
    if not isActive then return end

    isActive = false

    if chooserFrame then
        chooserFrame:SetScript("OnUpdate", nil)
        chooserFrame:Hide()
    end

    if chooserBox then
        chooserBox:Hide()
    end

    ResetCursor()

    if currentCallback then
        if canceled then
            currentCallback(originalValue, false)
        else
            currentCallback(oldPickName, false)
        end
    end

    currentCallback = nil
    originalValue = nil
    oldPick = nil
    oldPickName = nil
end

function FC:IsActive()
    return isActive
end
