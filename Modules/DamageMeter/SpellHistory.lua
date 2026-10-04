-- ╔══════════════════════════════════════════════════════════╗
-- ║  DamageMeter/SpellHistory.lua                            ║
-- ║  Module: Damage Meter                                    ║
-- ║  Purpose: A strip of the player's recent casts, newest   ║
-- ║           first, each icon fading after a delay.         ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class DamageMeter: AceModule
local DM = KitnEssentials:GetModule("DamageMeter")

local type = type
local select = select
local tonumber = tonumber
local floor = math.floor
local wipe = wipe
local issecretvalue = issecretvalue
local CreateFrame = CreateFrame
local UIParent = UIParent
local GetInventoryItemID = GetInventoryItemID
local C_Spell = C_Spell
local C_SpellBook = C_SpellBook
local C_Item = C_Item
local C_Container = C_Container

local KIND_SPELL, KIND_ITEM, KIND_PET = "spell", "item", "pet"
local STATUS_OK, STATUS_FAILED, STATUS_RESTORE = "ok", "failed", "restore"

---------------------------------------------------------------------------------
-- Cast classifier
--
-- Pure: every game lookup arrives through `api` and all memory lives in
-- `state`, so dev/spec/dm_spell_history_spec.lua drives it headlessly.
-- Returns texture, kind, status as plain values. The only allocation is the
-- SENT ring, once, on the first press.
---------------------------------------------------------------------------------

local function SetCurrent(state, isPet, castGUID)
    if isPet then state.curPet = castGUID else state.curPlayer = castGUID end
end

local function SetChannel(state, isPet, spellID, castGUID)
    if isPet then
        state.channelPet, state.channelPetGUID = spellID, castGUID
    else
        state.channelPlayer, state.channelPlayerGUID = spellID, castGUID
    end
end

local function SetLast(state, isPet, castGUID)
    if isPet then state.lastPet = castGUID else state.lastPlayer = castGUID end
end

local function SetFailed(state, isPet, castGUID)
    if isPet then state.failedPet = castGUID else state.failedPlayer = castGUID end
end

-- The slot the next cast writes; 0 is an empty ring.
local function NextHead(head, size)
    return head % size + 1
end

-- The castGUIDs of the player's last few UNIT_SPELLCAST_SENT, the presses. A
-- queued press can send before the previous cast succeeds, so one slot is not
-- enough. Made on the first press and never grown.
local SENT_SLOTS = 4

local function RecordSent(state, castGUID)
    local sent = state.sent
    if not sent then
        sent = {}
        state.sent = sent
    end
    local slot = NextHead(state.sentHead or 0, SENT_SLOTS)
    sent[slot] = castGUID
    state.sentHead = slot
end

local function WasSent(state, castGUID)
    local sent = state.sent
    if castGUID == nil or not sent then return false end
    for i = 1, SENT_SLOTS do
        if sent[i] == castGUID then return true end
    end
    return false
end

-- Autocast pet basics would fill the strip, so a pet spell shows only while
-- its autocast flag reads plainly false; secret or missing counts as on.
local function AcceptCast(isPet, spellID, state, api, castGUID)
    if isPet then
        if not api.isPetKnown(spellID) then return nil end
        local auto = api.autoCast(spellID)
        if api.isSecret(auto) or auto ~= false then return nil end
        local tex = api.getTexture(spellID)
        if not tex then return nil end
        return tex, KIND_PET
    end
    if api.isKnown(spellID) then
        local shown = api.getOverride(spellID)
        if type(shown) ~= "number" or shown == 0 then shown = spellID end
        local tex = api.getTexture(shown)
        if not tex then return nil end
        return tex, KIND_SPELL
    end
    if not state.items then return nil end
    local item = api.itemFor(spellID)
    if item then
        local tex = api.getItemIcon(item)
        if not tex then return nil end
        return tex, KIND_ITEM
    end
    -- A toy or another ability outside the spellbook shows only when the
    -- player pressed it; an effect the game casts on its own had no SENT.
    if not WasSent(state, castGUID) then return nil end
    local tex = api.getTexture(spellID)
    if not tex then return nil end
    return tex, KIND_SPELL
end

local function ShowCast(isPet, spellID, castGUID, state, api)
    local tex, kind = AcceptCast(isPet, spellID, state, api, castGUID)
    if not tex then return nil end
    SetLast(state, isPet, castGUID)
    return tex, kind, STATUS_OK
end

-- `unit` is "player" or "pet", a literal from the frame that received the
-- event; the payload's own unit token is never read.
local function Classify(event, unit, spellID, castGUID, state, api)
    local isPet = unit == "pet"
    -- Ahead of the secret test, so a secret payload cannot leave a channel
    -- open. An older channel's stop, arriving after the spell was recast,
    -- leaves the new channel in place.
    if event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        local open = state.channelPlayerGUID
        if isPet then open = state.channelPetGUID end
        if api.isSecret(castGUID) or castGUID == open then
            SetChannel(state, isPet, nil, nil)
        end
        return nil
    end
    if api.isSecret(spellID) or api.isSecret(castGUID) then return nil end

    if event == "UNIT_SPELLCAST_SENT" then
        if not isPet and castGUID ~= nil then RecordSent(state, castGUID) end
        return nil
    end

    local current, channel, last, failedGUID
    if isPet then
        current, channel, last, failedGUID = state.curPet, state.channelPet, state.lastPet, state.failedPet
    else
        current, channel, last, failedGUID = state.curPlayer, state.channelPlayer, state.lastPlayer, state.failedPlayer
    end

    if event == "UNIT_SPELLCAST_START" then
        SetCurrent(state, isPet, castGUID)
        return nil
    end

    -- Only a cast that started can show as failed: an instant press refused
    -- before it began never had a START.
    if event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_FAILED" then
        if current == nil or castGUID ~= current then return nil end
        SetCurrent(state, isPet, nil)
        local tex, kind = AcceptCast(isPet, spellID, state, api)
        if not tex then return nil end
        SetFailed(state, isPet, castGUID)
        return tex, kind, STATUS_FAILED
    end

    if event == "UNIT_SPELLCAST_CHANNEL_START" then
        SetChannel(state, isPet, spellID, castGUID)
        -- Its SUCCEEDED may have arrived first and already shown it. Channel
        -- events can carry a nil castGUID, which must not match a nil last.
        if castGUID ~= nil and castGUID == last then return nil end
        return ShowCast(isPet, spellID, castGUID, state, api)
    end

    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        if castGUID == current then SetCurrent(state, isPet, nil) end
        -- A failure reported ahead of the success the cast turned out to be.
        if castGUID == failedGUID then
            SetFailed(state, isPet, nil)
            return nil, nil, STATUS_RESTORE
        end
        -- A channel reports SUCCEEDED once per tick.
        if spellID == channel or castGUID == last then return nil end
        return ShowCast(isPet, spellID, castGUID, state, api)
    end

    return nil
end

---------------------------------------------------------------------------------
-- Ring arithmetic
---------------------------------------------------------------------------------

-- 0 is the newest position, size - 1 the oldest.
local function SlotPosition(slot, head, size)
    return (head - slot) % size
end

-- Busted seams (dev/spec/dm_spell_history_spec.lua).
DM.SpellHistoryClassify = Classify
DM.SpellHistoryNextHead = NextHead
DM.SpellHistorySlotPosition = SlotPosition

---------------------------------------------------------------------------------
-- Fade plan
---------------------------------------------------------------------------------

-- "held" waits for combat to end. Any mode but "ICON" is the whole row, the
-- default, so a missing setting reads as it.
local function FadePlan(mode, hold, inCombat, delay)
    if delay <= 0 then return "none" end
    if hold and inCombat then return "held" end
    if mode == "ICON" then return "icon" end
    return "strip"
end

DM.SpellHistoryFadePlan = FadePlan

---------------------------------------------------------------------------------
-- Attached placement
---------------------------------------------------------------------------------

-- The dock's rect arrives in GetRect order. A nil value, which the caller
-- passes for a secret one, keeps the outside placement. Touching the screen
-- edge counts as fitting.
local function FitsOutside(edge, gap, left, bottom, width, height, stripW, stripH, screenW, screenH)
    if left == nil or bottom == nil or width == nil or height == nil then return true end
    if edge == "BOTTOM" then return bottom - gap - stripH >= 0 end
    if edge == "LEFT" then return left - gap - stripW >= 0 end
    if edge == "RIGHT" then return left + width + gap + stripW <= screenW end
    return bottom + height + gap + stripH <= screenH
end

-- The strip's point, the dock's point and the offset, outside the edge or
-- inside the dock at the gap. Top and Bottom take the corner on the newest
-- icon's side; Left and Right align to the top unless the strip grows up. An
-- unknown edge reads as Top.
local function AttachPoints(edge, grow, gap, inside)
    if edge == "LEFT" or edge == "RIGHT" then
        local v = grow == "UP" and "BOTTOM" or "TOP"
        local sign = edge == "LEFT" and -1 or 1
        if inside then return v .. edge, v .. edge, -sign * gap, 0 end
        local far = edge == "LEFT" and "RIGHT" or "LEFT"
        return v .. far, v .. edge, sign * gap, 0
    end
    local s = grow == "RIGHT" and "LEFT" or "RIGHT"
    if edge ~= "BOTTOM" then edge = "TOP" end
    local sign = edge == "BOTTOM" and -1 or 1
    if inside then return edge .. s, edge .. s, 0, -sign * gap end
    local far = edge == "BOTTOM" and "TOP" or "BOTTOM"
    return far .. s, edge .. s, 0, sign * gap
end

DM.SpellHistoryFitsOutside = FitsOutside
DM.SpellHistoryAttachPoints = AttachPoints

-- The end the newest icon sits at, and the end older icons step toward.
local GROW_START = { LEFT = "RIGHT", RIGHT = "LEFT", UP = "BOTTOM", DOWN = "TOP" }
local GROW_FAR = { LEFT = "LEFT", RIGHT = "RIGHT", UP = "TOP", DOWN = "BOTTOM" }

-- How far to move a free strip's saved offset when its length changes, so the
-- growth-start end stays put. The anchor's place along the growth axis is read
-- from its name; one naming neither end sits on the center line.
local function GrowthShift(anchorFrom, grow, oldLength, newLength)
    if not GROW_START[grow] then grow = "LEFT" end
    anchorFrom = anchorFrom or "CENTER"
    local d = newLength - oldLength
    local shift
    if anchorFrom:find(GROW_START[grow], 1, true) then
        shift = 0
    elseif anchorFrom:find(GROW_FAR[grow], 1, true) then
        shift = d
    else
        shift = d / 2
    end
    if grow == "LEFT" then return -shift, 0 end
    if grow == "RIGHT" then return shift, 0 end
    if grow == "UP" then return 0, shift end
    return 0, -shift
end

DM.SpellHistoryGrowthShift = GrowthShift

-- Attached, a strip is pinned at its newest icon's end, so it only lengthens
-- away from the edge it hugs: outward while outside the dock, inward while
-- inside it. A direction across the edge reads as that one whichever of the
-- two was saved, and the saved Grow is never rewritten.
local INWARD = { TOP = "DOWN", BOTTOM = "UP", LEFT = "RIGHT", RIGHT = "LEFT" }
local OPPOSITE = { LEFT = "RIGHT", RIGHT = "LEFT", UP = "DOWN", DOWN = "UP" }

local function EffectiveGrow(attach, edge, grow, inside)
    if not OPPOSITE[grow] then grow = "LEFT" end
    if attach ~= true then return grow end
    local inward = INWARD[edge] or INWARD.TOP
    if inside then
        if grow == OPPOSITE[inward] then return inward end
    elseif grow == inward then
        return OPPOSITE[inward]
    end
    return grow
end

-- The growth in effect and the anchor for an attached strip.
local function AttachedPlacement(edge, grow, gap, inside)
    local effective = EffectiveGrow(true, edge, grow, inside)
    return effective, AttachPoints(edge, effective, gap, inside)
end

DM.SpellHistoryEffectiveGrow = EffectiveGrow
DM.SpellHistoryAttachedPlacement = AttachedPlacement

---------------------------------------------------------------------------------
-- Game lookups
--
-- The classifier's live `api`. Each function reads the game only when called,
-- so the file still loads headlessly.
---------------------------------------------------------------------------------

local BANK_PLAYER = Enum.SpellBookSpellBank.Player
local BANK_PET = Enum.SpellBookSpellBank.Pet
local EQUIPPED_SLOTS = 19

-- spellID -> itemID for every bag or equipped item with a Use spell. Built on
-- the first item lookup, then rebuilt only after a bag or gear change.
local itemSpell
local itemsStale = true

local function MapItem(map, itemID)
    if not itemID then return end
    local _, spellID = C_Item.GetItemSpell(itemID)
    if spellID then map[spellID] = itemID end
end

local function RebuildItemMap()
    local map = itemSpell
    if map then
        wipe(map)
    else
        map = {}
        itemSpell = map
    end
    for slot = 1, EQUIPPED_SLOTS do
        MapItem(map, GetInventoryItemID("player", slot))
    end
    -- The reagent bag above these holds only crafting reagents.
    for bag = 0, NUM_BAG_SLOTS or 4 do
        local slots = C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, slots do
            MapItem(map, C_Container.GetContainerItemID(bag, slot))
        end
    end
    itemsStale = false
end

local GAME_API = {
    isSecret = issecretvalue,
    isKnown = function(spellID)
        return C_SpellBook.IsSpellKnownOrInSpellBook(spellID, BANK_PLAYER, true)
    end,
    isPetKnown = function(spellID)
        return C_SpellBook.IsSpellKnownOrInSpellBook(spellID, BANK_PET, true)
    end,
    autoCast = function(spellID)
        local _, enabled = C_Spell.GetSpellAutoCast(spellID)
        return enabled
    end,
    itemFor = function(spellID)
        if itemsStale then RebuildItemMap() end
        return itemSpell and itemSpell[spellID]
    end,
    getOverride = function(spellID) return C_Spell.GetOverrideSpell(spellID) end,
    getTexture = function(spellID) return (C_Spell.GetSpellTexture(spellID)) end,
    getItemIcon = function(itemID) return C_Item.GetItemIconByID(itemID) end,
}

local castState = { items = false }

---------------------------------------------------------------------------------
-- Strip
--
-- A fixed ring of icons built once, parented to the dock so the strip shows
-- exactly when the meter does. Each icon fades with its own C-side animation;
-- no Lua runs per frame.
---------------------------------------------------------------------------------

local MAX_ICONS = 10
local FADE_DURATION = 1
local PUSH_DURATION = 0.25
local FAILED_MARK_SCALE = 0.7
local FAILED_ATLAS = "common-icon-redx"
local PLACEHOLDER_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local PLAIN_BORDER = { 0, 0, 0, 1 }
local PET_BORDER = { 0.298, 0.686, 0.314, 1 }
local BORDER_SIDES = { "top", "bottom", "left", "right" }

-- Per growth: the anchor at the start end, where the newest icon sits, and
-- the direction older icons step in.
local GROW_POINT = { LEFT = "TOPRIGHT", RIGHT = "TOPLEFT", UP = "BOTTOMLEFT", DOWN = "TOPLEFT" }
local GROW_X = { LEFT = -1, RIGHT = 1, UP = 0, DOWN = 0 }
local GROW_Y = { LEFT = 0, RIGHT = 0, UP = 1, DOWN = -1 }

local UNIT_EVENTS = {
    "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP",
}
local FAILED_EVENTS = {
    "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_FAILED",
}
local ITEM_EVENTS = { "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED" }

local strip
local petFrame
local icons = {}
local ringSize = 0
local head = 0
local fadeDelay = 0
local growPoint, stepX, stepY = "TOPRIGHT", 0, 0
-- The strip's size from the last Layout, and the attached anchor last applied,
-- so a dock layout that changes nothing re-anchors nothing.
local stripW, stripH, stripStep = 0, 0, 0
local placedPoint, placedRel, placedX, placedY, placedStrata, placedSnapped

-- SetColorTexture turns the pixel-grid snap back on; borders stay unsnapped.
local function SetBorderPet(icon, pet)
    local c = pet and PET_BORDER or PLAIN_BORDER
    local borders = icon.borders
    for i = 1, #BORDER_SIDES do
        local tex = borders[BORDER_SIDES[i]]
        tex:SetColorTexture(c[1], c[2], c[3], c[4])
        tex:SetSnapToPixelGrid(false)
    end
    icon.pet = pet
end

-- A push still running is stopped first, so it restarts from the new anchor
-- instead of finishing from the old one.
local function ReanchorShown(push)
    local frame = strip
    if not frame then return end
    for slot = 1, ringSize do
        local icon = icons[slot]
        if icon:IsShown() then
            local pos = SlotPosition(slot, head, ringSize)
            icon:ClearAllPoints()
            icon:SetPoint(growPoint, frame, growPoint, pos * stepX, pos * stepY)
            if push then
                icon.entry:Stop()
                icon.entry:Play()
                if pos == 0 then
                    icon.appear:Stop()
                    icon.appear:Play()
                end
            end
        end
    end
end

local function ShowPlaceholder(icon)
    icon.group:Stop()
    icon.tex:SetTexture(PLACEHOLDER_ICON)
    icon.tex:SetDesaturated(false)
    icon.mark:Hide()
    if icon.pet then SetBorderPet(icon, false) end
    icon:SetAlpha(1)
    icon:Show()
end

local function OnIconFaded(icon)
    icon.live = false
    if DM._guiPreview then
        ShowPlaceholder(icon)
    else
        icon:Hide()
    end
end

local function ClearRing()
    for slot = 1, #icons do
        local icon = icons[slot]
        icon.group:Stop()
        icon.entry:Stop()
        icon.appear:Stop()
        icon.live = false
        icon:Hide()
    end
    head = 0
end

local function CreateIcon(parent)
    local icon = CreateFrame("Frame", nil, parent)
    icon:Hide()

    local tex = icon:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints(icon)
    KE:ApplyIconZoom(tex)
    icon.tex = tex
    KE:AddIconBorders(icon, PLAIN_BORDER)
    icon.pet = false

    local mark = icon:CreateTexture(nil, "OVERLAY")
    mark:SetAtlas(FAILED_ATLAS)
    mark:SetPoint("CENTER", icon, "CENTER", 0, 0)
    mark:Hide()
    icon.mark = mark

    local group = icon:CreateAnimationGroup()
    group:SetToFinalAlpha(true)
    local fade = group:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0)
    fade:SetDuration(FADE_DURATION)
    group:SetScript("OnFinished", function() OnIconFaded(icon) end)
    icon.group, icon.fade = group, fade

    -- Translation takes only an offset, so the push is a zero-length step back
    -- toward the newest end, then the glide forward. ApplyGrowth sets both.
    local entry = icon:CreateAnimationGroup()
    local slideBack = entry:CreateAnimation("Translation")
    slideBack:SetOrder(1)
    slideBack:SetDuration(0)
    local slideIn = entry:CreateAnimation("Translation")
    slideIn:SetOrder(2)
    slideIn:SetDuration(PUSH_DURATION)
    slideIn:SetSmoothing("OUT")
    icon.entry, icon.slideBack, icon.slideIn = entry, slideBack, slideIn

    -- Its own group: an alpha change in the entry group would play over an
    -- older icon's running fade.
    local appear = icon:CreateAnimationGroup()
    local fadeIn = appear:CreateAnimation("Alpha")
    fadeIn:SetFromAlpha(0)
    fadeIn:SetToAlpha(1)
    fadeIn:SetDuration(PUSH_DURATION)
    fadeIn:SetSmoothing("OUT")
    icon.appear = appear
    icon.live = false
    return icon
end

local function Push(tex, kind, status, castGUID)
    if ringSize < 1 then return end
    head = NextHead(head, ringSize)
    local icon = icons[head]
    local failed = status == STATUS_FAILED
    -- Written on every push, so a failed icon a newer cast overwrote no
    -- longer matches a restore.
    icon.failedGUID = failed and castGUID or nil
    icon.tex:SetTexture(tex)
    icon.tex:SetDesaturated(failed)
    icon.mark:SetShown(failed)
    local pet = kind == KIND_PET
    if icon.pet ~= pet then SetBorderPet(icon, pet) end
    icon.live = true
    icon.group:Stop()
    icon:SetAlpha(1)
    icon:Show()
    if fadeDelay > 0 then
        icon.fade:SetStartDelay(fadeDelay)
        icon.group:Play()
    end
    ReanchorShown(true)
end

-- The cast a failure report grayed out succeeded after all: undo the gray in
-- place. Its fade keeps running from the failed push.
local function Restore(castGUID)
    for slot = 1, #icons do
        local icon = icons[slot]
        if icon.live and icon.failedGUID == castGUID then
            icon.failedGUID = nil
            icon.tex:SetDesaturated(false)
            icon.mark:Hide()
            return
        end
    end
end

-- Classified even while hidden, so channel and cast state stay right.
local function HandleCast(unit, event, castGUID, spellID)
    local tex, kind, status = Classify(event, unit, spellID, castGUID, castState, GAME_API)
    if status == STATUS_RESTORE then
        Restore(castGUID)
    elseif tex and strip and strip:IsVisible() then
        Push(tex, kind, status, castGUID)
    end
end

-- Each frame is registered for one unit and names it; the payload's unit
-- token is never read.
local function OnStripEvent(_, event, ...)
    if event == "BAG_UPDATE_DELAYED" or event == "PLAYER_EQUIPMENT_CHANGED" then
        itemsStale = true
    elseif event == "UNIT_PET" then
        -- A pet dismissed or replaced mid-channel may never send its stop.
        castState.curPet = nil
        SetChannel(castState, true, nil, nil)
    elseif event == "UNIT_SPELLCAST_SENT" then
        -- unitTarget, target, castGUID, spellID: the target is never read.
        local castGUID, spellID = select(3, ...)
        HandleCast("player", event, castGUID, spellID)
    else
        local castGUID, spellID = select(2, ...)
        HandleCast("player", event, castGUID, spellID)
    end
end

local function OnPetEvent(_, event, ...)
    local castGUID, spellID = select(2, ...)
    HandleCast("pet", event, castGUID, spellID)
end

-- In a preview every empty slot shows a placeholder so the strip can be seen
-- and placed; live icons are left alone.
local function SyncPreview()
    local previewing = DM._guiPreview == true
    for slot = 1, #icons do
        local icon = icons[slot]
        if not icon.live then
            if previewing and slot <= ringSize then
                ShowPlaceholder(icon)
            else
                icon:Hide()
            end
        end
    end
    ReanchorShown()
end

-- Hidden with the meter: live icons never outlive the hide, in a preview
-- too, where the placeholders come back.
local function OnStripHide()
    ClearRing()
    if DM._guiPreview then SyncPreview() end
end

local function Build()
    DM:EnsureDock()
    local frame = CreateFrame("Frame", "KE_DamageMeter_SpellHistory", DM.dock)
    frame:SetClampedToScreen(true)
    for slot = 1, MAX_ICONS do
        icons[slot] = CreateIcon(frame)
    end
    frame:SetScript("OnEvent", OnStripEvent)
    frame:SetScript("OnHide", OnStripHide)
    strip = frame

    local pets = CreateFrame("Frame")
    pets:SetScript("OnEvent", OnPetEvent)
    petFrame = pets
end

local function RegisterCasts(target, unit, failed)
    for i = 1, #UNIT_EVENTS do
        target:RegisterUnitEvent(UNIT_EVENTS[i], unit)
    end
    for i = 1, #FAILED_EVENTS do
        local event = FAILED_EVENTS[i]
        if failed then
            target:RegisterUnitEvent(event, unit)
        else
            target:UnregisterEvent(event)
        end
    end
end

local function RegisterEvents(frame, pets, sh)
    local withPet = sh.IncludePet ~= false
    local failed = sh.ShowFailed ~= false
    RegisterCasts(frame, "player", failed)
    if withPet then
        RegisterCasts(pets, "pet", failed)
        frame:RegisterUnitEvent("UNIT_PET", "player")
    else
        pets:UnregisterAllEvents()
        frame:UnregisterEvent("UNIT_PET")
    end

    local items = sh.IncludeItems ~= false
    -- Without Include Items the press record would let a bag potion through
    -- by its spell, so it lives and dies with the item events.
    if items then
        frame:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")
    else
        frame:UnregisterEvent("UNIT_SPELLCAST_SENT")
        castState.sent, castState.sentHead = nil, nil
    end
    for i = 1, #ITEM_EVENTS do
        local event = ITEM_EVENTS[i]
        if not items then
            frame:UnregisterEvent(event)
        elseif not frame:IsEventRegistered(event) then
            frame:RegisterEvent(event)
            -- Bag and gear changes made while unregistered went unseen.
            itemsStale = true
        end
    end
    castState.items = items

    if not withPet then
        castState.curPet, castState.lastPet, castState.failedPet = nil, nil, nil
        SetChannel(castState, true, nil, nil)
    end
    if not failed then
        castState.curPlayer, castState.curPet = nil, nil
        castState.failedPlayer, castState.failedPet = nil, nil
    end
end

-- Sets the growth corner and step, and moves the shown icons only when either
-- changed: an attached strip's growth flips when it moves inside the dock.
local function ApplyGrowth(grow)
    local point = GROW_POINT[grow]
    local x, y = GROW_X[grow] * stripStep, GROW_Y[grow] * stripStep
    if point == growPoint and x == stepX and y == stepY then return end
    growPoint, stepX, stepY = point, x, y
    -- A push in flight would glide by the old step, so it lands at once.
    for slot = 1, #icons do
        local icon = icons[slot]
        icon.entry:Stop()
        icon.slideBack:SetOffset(-x, -y)
        icon.slideIn:SetOffset(x, y)
    end
    ReanchorShown()
end

-- The strip's length along its growth axis, with the clamped count, icon size
-- and step it comes from.
local function StripLength(sh)
    local count = floor(tonumber(sh.Count) or 5)
    if count < 1 then
        count = 1
    elseif count > MAX_ICONS then
        count = MAX_ICONS
    end
    local size = KE:PixelSnap(tonumber(sh.IconSize) or 32)
    local step = size + KE:PixelSnap(tonumber(sh.Spacing) or 2)
    return count * step - (step - size), count, size, step
end

local function Layout(sh)
    local frame = strip
    if not frame then return end
    local length, count, size, step = StripLength(sh)
    if count ~= ringSize then
        -- The slot arithmetic is per ring size, so a new size starts empty.
        ClearRing()
        ringSize = count
    end

    -- The outside reading: both readings share an axis, so the size is right
    -- either way, and Place sets the attached growth once it knows which.
    local grow = EffectiveGrow(sh.Attach, sh.AttachEdge, sh.Grow, false)
    stripStep = step
    ApplyGrowth(grow)

    if GROW_Y[grow] == 0 then
        stripW, stripH = length, size
    else
        stripW, stripH = size, length
    end
    frame:SetSize(stripW, stripH)

    local markSize = KE:PixelSnap(size * FAILED_MARK_SCALE)
    for slot = 1, #icons do
        local icon = icons[slot]
        icon:SetSize(size, size)
        icon.mark:SetSize(markSize, markSize)
    end
    fadeDelay = tonumber(sh.FadeDelay) or 5
end

-- Attached, the strip sits outside the dock's chosen edge when it fits on
-- screen, and inside the dock at the gap when it does not. The dock is a
-- UIParent child with no scale of its own, so its rect and the screen size
-- share units.
local function Place(db, sh)
    local frame = strip
    if not frame then return end
    local dock = DM.dock
    if sh.Attach == true and dock then
        local gap = KE:PixelSnap(tonumber(sh.AttachGap) or 2)
        local left, bottom, width, height = dock:GetRect()
        local secret = issecretvalue(left) or issecretvalue(bottom) or issecretvalue(width)
            or issecretvalue(height)
        if secret then left = nil end
        local fits = FitsOutside(sh.AttachEdge, gap, left, bottom, width, height, stripW, stripH,
            UIParent:GetWidth(), UIParent:GetHeight())
        local grow, point, rel, x, y = AttachedPlacement(sh.AttachEdge, sh.Grow, gap, not fits)
        ApplyGrowth(grow)
        local strata = db.Strata or "MEDIUM"
        -- A placement made while the dock's rect was secret or missing went
        -- unsnapped, so the first layout that can measure the dock makes it again.
        local unmeasured = issecretvalue(left) or not left
        if point == placedPoint and rel == placedRel and x == placedX and y == placedY
            and strata == placedStrata and (placedSnapped or unmeasured) then
            return
        end
        frame:ClearAllPoints()
        frame:SetPoint(point, dock, rel, x, y)
        frame:SetFrameStrata(strata)
        -- The snap reads and tests the strip's own left and bottom, which are
        -- secret whenever the dock's rect is.
        if not secret then KE:SnapFrameToPixels(frame) end
        placedPoint, placedRel, placedX, placedY, placedStrata = point, rel, x, y, strata
        placedSnapped = not unmeasured
    else
        placedPoint = nil
        KE:ApplyFramePosition(frame, sh.Position, sh)
    end
end

---------------------------------------------------------------------------------
-- Edit Mode mover
--
-- Free-standing only: attached, the strip follows the dock. The dock's lock
-- does not apply to it.
---------------------------------------------------------------------------------

local EDIT_KEY = "DamageMeterSpellHistory"
local editConfig
local editRegistered = false

local function SyncMover(want)
    local editMode = KE.EditMode
    local frame = strip
    if not (editMode and frame) then return end
    if want and not editRegistered then
        if not editConfig then
            editConfig = {
                key = EDIT_KEY,
                module = DM,
                displayName = "Spell History",
                frame = frame,
                getParentFrame = function()
                    local sh = DM.db and DM.db.SpellHistory
                    return KE:ResolveAnchorFrame(sh and sh.anchorFrameType, sh and sh.ParentFrame)
                end,
                getPosition = function()
                    local sh = DM.db and DM.db.SpellHistory
                    return sh and sh.Position
                end,
                setPosition = function(pos)
                    local sh = DM.db and DM.db.SpellHistory
                    if not sh then return end
                    sh.Position = pos
                    KE:ApplyFramePosition(frame, sh.Position, sh)
                end,
                guiPath = "DamageMeter",
            }
        end
        editMode:RegisterElement(editConfig)
        editRegistered = true
    elseif not want and editRegistered then
        editMode:UnregisterElement(EDIT_KEY)
        editRegistered = false
    end
end

local function TearDown()
    local frame = strip
    if not frame then return end
    frame:UnregisterAllEvents()
    SyncMover(false)
    if petFrame then petFrame:UnregisterAllEvents() end
    -- Hidden before the clear: in a preview, OnStripHide shows the
    -- placeholders again.
    frame:Hide()
    ClearRing()
    SetChannel(castState, false, nil, nil)
    SetChannel(castState, true, nil, nil)
    castState.curPlayer, castState.curPet = nil, nil
    castState.lastPlayer, castState.lastPet = nil, nil
    castState.failedPlayer, castState.failedPet = nil, nil
    castState.sent, castState.sentHead = nil, nil
end

---------------------------------------------------------------------------------
-- Entry point: module enable and disable, the settings page, previews and
-- profile switches all come through here.
---------------------------------------------------------------------------------

function DM:ApplySpellHistory()
    local db = self.db
    local sh = db and db.SpellHistory
    if not (self.enabled and sh and sh.Enabled) then
        TearDown()
        return
    end
    if not strip then Build() end
    local frame, pets = strip, petFrame
    if not (frame and pets) then return end
    RegisterEvents(frame, pets, sh)
    Layout(sh)
    -- Layout may have resized the strip, which needs a fresh snap.
    placedPoint = nil
    Place(db, sh)
    SyncMover(sh.Attach ~= true)
    frame:Show()
    SyncPreview()
end

-- Called at the end of the dock's layout, where its size and place are final,
-- so a move, a resize or a chat-size match re-decides inside or outside.
function DM:PlaceSpellHistory()
    local sh = self.db and self.db.SpellHistory
    if not (strip and sh and sh.Attach == true and strip:IsShown()) then return end
    Place(self.db, sh)
end

-- The unrounded offsets the last resize moved to, and the placement it left.
-- While the strip is still placed exactly so, the next resize goes on from
-- them, so a run of resizes rounds once rather than once per step; any other
-- change to the placement starts again from the saved offsets.
local carry = { exactX = 0, exactY = 0 }

local function CarriedOffset(sh, pos, length)
    if carry.length == length and carry.x == pos.XOffset and carry.y == pos.YOffset
        and carry.from == pos.AnchorFrom and carry.to == pos.AnchorTo and carry.grow == sh.Grow
        and carry.frameType == sh.anchorFrameType and carry.parent == sh.ParentFrame then
        return carry.exactX, carry.exactY
    end
    return pos.XOffset or 0, pos.YOffset or 0
end

-- Read by the smoke's load check: the carry is otherwise file-local.
DM.SpellHistoryCarriedOffset = CarriedOffset

-- The settings page's Count, Icon Size and Spacing. A free strip's saved
-- offset moves by the length change, so its growth-start end stays put to
-- within the whole-number rounding and the pixel snap; a Grow change, a drag
-- or a profile switch never shifts it.
function DM:ResizeSpellHistory(key, value)
    local sh = self.db and self.db.SpellHistory
    if not sh then return end
    local oldLength = StripLength(sh)
    sh[key] = value
    local newLength = StripLength(sh)
    local pos = sh.Position
    if sh.Attach ~= true and pos and newLength ~= oldLength then
        local x, y = CarriedOffset(sh, pos, oldLength)
        local dx, dy = GrowthShift(pos.AnchorFrom, sh.Grow, oldLength, newLength)
        x, y = x + dx, y + dy
        pos.XOffset, pos.YOffset = KE:RoundOffset(x), KE:RoundOffset(y)
        carry.exactX, carry.exactY, carry.x, carry.y = x, y, pos.XOffset, pos.YOffset
        carry.length, carry.from, carry.to, carry.grow = newLength, pos.AnchorFrom, pos.AnchorTo, sh.Grow
        carry.frameType, carry.parent = sh.anchorFrameType, sh.ParentFrame
    end
    self:ApplySpellHistory()
end
