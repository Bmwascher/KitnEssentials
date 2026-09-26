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
-- Returns texture, kind, status as plain values; nothing is allocated.
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

-- Autocast pet basics would fill the strip, so a pet spell shows only while
-- its autocast flag reads plainly false; secret or missing counts as on.
local function AcceptCast(isPet, spellID, state, api)
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
    if not item then return nil end
    local tex = api.getItemIcon(item)
    if not tex then return nil end
    return tex, KIND_ITEM
end

local function ShowCast(isPet, spellID, castGUID, state, api)
    local tex, kind = AcceptCast(isPet, spellID, state, api)
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

    local current, channel, last
    if isPet then
        current, channel, last = state.curPet, state.channelPet, state.lastPet
    else
        current, channel, last = state.curPlayer, state.channelPlayer, state.lastPlayer
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
        state.lastFailedGUID = castGUID
        return tex, kind, STATUS_FAILED
    end

    if event == "UNIT_SPELLCAST_CHANNEL_START" then
        SetChannel(state, isPet, spellID, castGUID)
        -- Its SUCCEEDED may have arrived first and already shown it.
        if castGUID == last then return nil end
        return ShowCast(isPet, spellID, castGUID, state, api)
    end

    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        if castGUID == current then SetCurrent(state, isPet, nil) end
        -- A failure reported ahead of the success the cast turned out to be.
        if castGUID == state.lastFailedGUID then
            state.lastFailedGUID = nil
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

-- The slot the next cast writes; 0 is an empty ring.
local function NextHead(head, size)
    return head % size + 1
end

-- 0 is the newest position, size - 1 the oldest.
local function SlotPosition(slot, head, size)
    return (head - slot) % size
end

-- Busted seams (dev/spec/dm_spell_history_spec.lua).
DM.SpellHistoryClassify = Classify
DM.SpellHistoryNextHead = NextHead
DM.SpellHistorySlotPosition = SlotPosition

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
local lastFailedSlot
local fadeDelay = 0
local growPoint, stepX, stepY = "TOPRIGHT", 0, 0

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

local function ReanchorShown()
    local frame = strip
    if not frame then return end
    for slot = 1, ringSize do
        local icon = icons[slot]
        if icon:IsShown() then
            local pos = SlotPosition(slot, head, ringSize)
            icon:ClearAllPoints()
            icon:SetPoint(growPoint, frame, growPoint, pos * stepX, pos * stepY)
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
        icon.live = false
        icon:Hide()
    end
    head = 0
    lastFailedSlot = nil
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
    icon.live = false
    return icon
end

local function Push(tex, kind, status)
    if ringSize < 1 then return end
    head = NextHead(head, ringSize)
    if lastFailedSlot == head then lastFailedSlot = nil end
    local icon = icons[head]
    local failed = status == STATUS_FAILED
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
    if failed then lastFailedSlot = head end
    ReanchorShown()
end

-- The cast a failure report greyed out succeeded after all: undo the grey in
-- place. Its fade keeps running from the failed push.
local function Restore()
    local slot = lastFailedSlot
    lastFailedSlot = nil
    if not slot then return end
    local icon = icons[slot]
    if not icon.live then return end
    icon.tex:SetDesaturated(false)
    icon.mark:Hide()
end

-- Classified even while hidden, so channel and cast state stay right.
local function HandleCast(unit, event, castGUID, spellID)
    local tex, kind, status = Classify(event, unit, spellID, castGUID, castState, GAME_API)
    if status == STATUS_RESTORE then
        Restore()
    elseif tex and strip and strip:IsVisible() then
        Push(tex, kind, status)
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
        castState.curPet, castState.lastPet = nil, nil
        SetChannel(castState, true, nil, nil)
    end
    if not failed then
        castState.curPlayer, castState.curPet, castState.lastFailedGUID = nil, nil, nil
        lastFailedSlot = nil
    end
end

local function Layout(sh)
    local frame = strip
    if not frame then return end
    local count = floor(tonumber(sh.Count) or 5)
    if count < 1 then
        count = 1
    elseif count > MAX_ICONS then
        count = MAX_ICONS
    end
    if count ~= ringSize then
        -- The slot arithmetic is per ring size, so a new size starts empty.
        ClearRing()
        ringSize = count
    end

    local grow = GROW_POINT[sh.Grow] and sh.Grow or "LEFT"
    local size = KE:PixelSnap(tonumber(sh.IconSize) or 32)
    local step = size + KE:PixelSnap(tonumber(sh.Spacing) or 2)
    growPoint = GROW_POINT[grow]
    stepX, stepY = GROW_X[grow] * step, GROW_Y[grow] * step

    local length = count * step - (step - size)
    if GROW_Y[grow] == 0 then
        frame:SetSize(length, size)
    else
        frame:SetSize(size, length)
    end

    local markSize = KE:PixelSnap(size * FAILED_MARK_SCALE)
    for slot = 1, #icons do
        local icon = icons[slot]
        icon:SetSize(size, size)
        icon.mark:SetSize(markSize, markSize)
    end
    fadeDelay = tonumber(sh.FadeDelay) or 5
end

-- Attached, the strip sits outside the dock's chosen edge, at the corner on
-- the newest icon's side (the right corner for vertical growth).
local function Place(db, sh)
    local frame = strip
    if not frame then return end
    local dock = DM.dock
    if sh.Attach == true and dock then
        local side = sh.Grow == "RIGHT" and "LEFT" or "RIGHT"
        local gap = KE:PixelSnap(tonumber(sh.AttachGap) or 2)
        frame:ClearAllPoints()
        if sh.AttachEdge == "BOTTOM" then
            frame:SetPoint("TOP" .. side, dock, "BOTTOM" .. side, 0, -gap)
        else
            frame:SetPoint("BOTTOM" .. side, dock, "TOP" .. side, 0, gap)
        end
        frame:SetFrameStrata(db.Strata or "MEDIUM")
        KE:SnapFrameToPixels(frame)
    else
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
    ClearRing()
    frame:Hide()
    SetChannel(castState, false, nil, nil)
    SetChannel(castState, true, nil, nil)
    castState.curPlayer, castState.curPet = nil, nil
    castState.lastPlayer, castState.lastPet, castState.lastFailedGUID = nil, nil, nil
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
    Place(db, sh)
    SyncMover(sh.Attach ~= true)
    frame:Show()
    SyncPreview()
end
