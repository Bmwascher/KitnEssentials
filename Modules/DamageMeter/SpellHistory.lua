-- ╔══════════════════════════════════════════════════════════╗
-- ║  DamageMeter/SpellHistory.lua                            ║
-- ║  Module: Damage Meter                                    ║
-- ║  Purpose: A strip of the player's recent casts, newest   ║
-- ║           first, each icon fading after a delay.         ║
-- ╚══════════════════════════════════════════════════════════╝

if not KitnEssentials then return end

---@class DamageMeter: AceModule
local DM = KitnEssentials:GetModule("DamageMeter")

local type = type

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

local function SetChannel(state, isPet, spellID)
    if isPet then state.channelPet = spellID else state.channelPlayer = spellID end
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
    state.lastGUID = castGUID
    return tex, kind, STATUS_OK
end

-- `unit` is "player" or "pet", a literal from the frame that received the
-- event; the payload's own unit token is never read.
local function Classify(event, unit, spellID, castGUID, state, api)
    local isPet = unit == "pet"
    -- Ahead of the secret test, so a secret payload cannot leave a channel
    -- open.
    if event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        SetChannel(state, isPet, nil)
        return nil
    end
    if api.isSecret(spellID) or api.isSecret(castGUID) then return nil end

    local current, channel
    if isPet then
        current, channel = state.curPet, state.channelPet
    else
        current, channel = state.curPlayer, state.channelPlayer
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
        SetChannel(state, isPet, spellID)
        -- Its SUCCEEDED may have arrived first and already shown it.
        if castGUID == state.lastGUID then return nil end
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
        if spellID == channel or castGUID == state.lastGUID then return nil end
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
