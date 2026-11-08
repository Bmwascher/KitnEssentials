-- ╔══════════════════════════════════════════════════════════╗
-- ║  Modules/QoL/Campfire/CampfireButtons.lua                ║
-- ║  Purpose: Campfire's secure Sleeping Bag and kit         ║
-- ║           buttons, their placement and combat driver.    ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)

local Rules = KE.CampfireRules
local Views = KE.CampfireViews

local C_Container = C_Container
local C_Item = C_Item
local C_Timer = C_Timer
local CreateFrame = CreateFrame
local GetTime = GetTime
local InCombatLockdown = InCombatLockdown
local RegisterStateDriver = RegisterStateDriver
local UIParent = UIParent
local UnregisterStateDriver = UnregisterStateDriver
local max = math.max

local Buttons = {}
KE.CampfireButtons = Buttons

local ROUND_SCALE, ROUND_GAP = 0.55, 12
local SIMPLE_SIZE, SIMPLE_GAP = 26, 4
local KIT_LABEL, KIT_LABEL_SIZE, KIT_LABEL_GAP = "Light a Fire", 13, 3
local COUNT_SIZE = 12
local TIME_SHARE, TIME_MIN_SIZE = 0.32, 10
-- The sample's Well-Rested time: a preview shows the bag with time on it, as live play does.
local SAMPLE_REST_LEFT = 3000
-- A cooldown this short is the global cooldown, not the item's own.
local GLOBAL_COOLDOWN = 1.5
local COOLDOWN_PAD = 0.1

local bag, kit, sample, active
local cooldownGen = 0

local function Dress(frame)
    -- Plain SetTexture with no filter argument: a game icon loaded with
    -- TRILINEAR crashes the Forever client.
    frame.icon = frame:CreateTexture(nil, "ARTWORK")
    frame.icon:SetAllPoints(frame)
    frame.cooldown = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
    frame.cooldown:SetAllPoints(frame)
    frame.cooldown:EnableMouse(false)
    frame.cooldown:SetDrawEdge(false)
    frame.cooldown:SetDrawBling(false)
    frame.cooldown:SetHideCountdownNumbers(true)
    frame.cooldown:Hide()
    frame.count = frame:CreateFontString(nil, "OVERLAY")
    frame.count:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
    frame.label = frame:CreateFontString(nil, "OVERLAY")
    frame.label:SetPoint("TOP", frame, "BOTTOM", 0, -KIT_LABEL_GAP)
    frame.time = frame:CreateFontString(nil, "OVERLAY")
    frame.time:SetPoint("CENTER", frame, "CENTER", 0, 0)
end

local function NewSecure(name)
    local button = CreateFrame("Button", name, UIParent, "SecureActionButtonTemplate")
    button:RegisterForClicks("AnyUp", "AnyDown")
    button:Hide()
    Dress(button)
    return button
end

local function SetIcon(frame, itemId)
    if frame.iconItem == itemId then return end
    local icon = C_Item.GetItemIconByID(itemId)
    if not icon then return end
    frame.icon:SetTexture(icon)
    frame.iconItem = itemId
end

-- Secure frames take coordinates, never an anchor to the shape: an anchor would
-- make the shape protected, and the shape changes in combat.
local function SpotFor(db)
    if db.Shape == "ROUND" then
        local x, y = Views.round:GetCenter()
        if KE:IsSecretValue(x) or KE:IsSecretValue(y) or not x then return nil end
        local size = db.RoundSize * ROUND_SCALE
        local half = db.RoundSize / 2 + Views.TRACK_OUT
        local side = db.ListSide == "LEFT" and 1 or -1
        return x + side * (half + ROUND_GAP + size / 2), y - half + size / 2, size
    end
    local x, y = Views.simple:GetCenter()
    if KE:IsSecretValue(x) or KE:IsSecretValue(y) or not x then return nil end
    return x - db.SimpleWidth / 2 - SIMPLE_GAP - SIMPLE_SIZE / 2, y, SIMPLE_SIZE
end

local function Place(frame, x, y, size)
    if frame.placedX == x and frame.placedY == y and frame.placedSize == size then return end
    frame.placedX, frame.placedY, frame.placedSize = x, y, size
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
    frame:SetSize(size, size)
end

-- left: Well-Rested's seconds left, which sets the time's color; nil for no time.
local function Style(frame, which, stacks, db, size, left)
    KE:ApplyFontToText(frame.count, db.FontFace, COUNT_SIZE, "OUTLINE")
    KE:ApplyFontToText(frame.label, db.FontFace, KIT_LABEL_SIZE, db.FontOutline)
    KE:ApplyFontToText(frame.time, db.FontFace, max(TIME_MIN_SIZE, size * TIME_SHARE), "OUTLINE")
    frame.count:SetText((stacks and stacks > 0) and stacks or "")
    frame.label:SetText(which == "kit" and db.Shape == "ROUND" and KIT_LABEL or "")
    if left then frame.time:SetTextColor(Views.KeyColor(Rules.RingColorKey(left, false))) end
end

-- The bag's Well-Rested time runs on the game's binding; a dropped bag stops it.
local function SetRestTime(button, rest)
    if not button.binding then
        if not rest then return end
        Views.AddCountdown(button)
    end
    Views.SetCountdown(button, rest and rest.expiry, rest and rest.duration)
end

local function Drop(button)
    if button == bag then SetRestTime(button, nil) end
    if button.driven then
        UnregisterStateDriver(button, "visibility")
        button.driven = false
    end
    button:Hide()
end

local function Arm(button, itemId)
    SetIcon(button, itemId)
    if button.armedItem == itemId then return end
    button.armedItem = itemId
    button.cooldownEnds = nil
    button:SetAttribute("type1", "item")
    button:SetAttribute("item1", "item:" .. itemId)
end

local function ReadCooldown(itemId)
    local start, duration = C_Container.GetItemCooldown(itemId)
    if KE:IsSecretValue(start) or KE:IsSecretValue(duration) then return nil end
    if not start or not duration or duration <= GLOBAL_COOLDOWN then return nil end
    if start + duration <= GetTime() then return nil end
    return start, duration
end

function Buttons.Build()
    if bag or InCombatLockdown() then return end
    bag = NewSecure("KE_CampfireBagButton")
    kit = NewSecure("KE_CampfireKitButton")
end

-- Outside combat only. In combat the driver has them hidden, and the
-- PLAYER_REGEN_ENABLED refresh brings them back to this call.
-- rest: the bag's Well-Rested read, with expiry nil when it is gone; nil when unread.
function Buttons.Sync(wanted, kitItem, db, rest)
    if not bag or InCombatLockdown() then return end
    local button = (wanted == "bag" and bag) or (wanted == "kit" and kit) or nil
    if bag ~= button then Drop(bag) end
    if kit ~= button then Drop(kit) end
    active = button
    if not button then return end

    local x, y, size = SpotFor(db)
    if not x then
        Drop(button)
        active = nil
        return
    end
    Arm(button, wanted == "kit" and kitItem or Rules.SLEEPING_BAG)
    Place(button, x, y, size)
    local expiry = rest and rest.expiry
    Style(button, wanted, rest and rest.stacks, db, size, expiry and expiry - GetTime())
    if button == bag then SetRestTime(button, rest) end
    if not button.driven then
        -- No show clause: outside combat it parses to nil and does nothing, so
        -- the module keeps the choice of when to show the button.
        RegisterStateDriver(button, "visibility", "[combat] hide")
        button.driven = true
    end
    button:Show()
    Buttons.UpdateCooldown()
end

-- Every button sync lands here, and BAG_UPDATE_COOLDOWN fires on every global
-- cooldown, so one cooldown end arms one one-shot.
function Buttons.UpdateCooldown()
    local button = active
    if not button or InCombatLockdown() then return end
    -- The bag stays in full color through its cooldown, with no sweep.
    if button == bag then
        button.icon:SetDesaturated(false)
        button.cooldownEnds = nil
        button.cooldown:Hide()
        return
    end
    local start, duration = ReadCooldown(button.armedItem)
    button.icon:SetDesaturated(start ~= nil)
    if not start then
        button.cooldownEnds = nil
        button.cooldown:Hide()
        return
    end
    local ends = start + duration
    if button.cooldownEnds == ends then return end
    button.cooldownEnds = ends
    button.cooldown:SetCooldown(start, duration)
    button.cooldown:Show()
    local gen = cooldownGen
    C_Timer.After(ends - GetTime() + COOLDOWN_PAD, function()
        if gen ~= cooldownGen or button.cooldownEnds ~= ends then return end
        button.cooldownEnds = nil
        if button == active then Buttons.UpdateCooldown() end
    end)
end

-- Plain Lua, so it runs at once, in combat too: a queued cooldown one-shot does
-- nothing, and the next UpdateCooldown arms a fresh one.
function Buttons.StopCooldowns()
    cooldownGen = cooldownGen + 1
    if not bag then return end
    bag.cooldownEnds, kit.cooldownEnds = nil, nil
end

-- A secure button cannot be destroyed, so a disabled module clears the action:
-- a click with no type does nothing.
function Buttons.Disarm()
    if not bag or InCombatLockdown() then return end
    active = nil
    for _, button in ipairs({ bag, kit }) do
        Drop(button)
        button:SetAttribute("type1", nil)
        button:SetAttribute("item1", nil)
        button.armedItem = nil
    end
end

-- A plain frame in the button's spot, so a click in a preview never uses an item.
function Buttons.ShowSample(which, db)
    if not sample then
        sample = CreateFrame("Frame", nil, UIParent)
        Dress(sample)
    end
    local x, y, size = SpotFor(db)
    if not x then
        sample:Hide()
        return
    end
    SetIcon(sample, which == "kit" and Rules.KITS[1] or Rules.SLEEPING_BAG)
    Place(sample, x, y, size)
    local left = which == "bag" and SAMPLE_REST_LEFT or nil
    Style(sample, which, which == "bag" and 1 or 0, db, size, left)
    sample.time:SetText(left and Views.ShortTime(left) or "")
    sample:Show()
end

function Buttons.HideSample()
    if sample then sample:Hide() end
end
