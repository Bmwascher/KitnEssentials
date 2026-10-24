-- ╔══════════════════════════════════════════════════════════╗
-- ║  TimerState.lua                                          ║
-- ║  Module: Dungeon Timers (private state)                  ║
-- ║  Purpose: Pause-aware source clocks, ownership scoping    ║
-- ║           and stop/expiry policy decisions. Plain Lua     ║
-- ║           only, no WoW API, no frames, no timers.         ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)

local type = type
local pairs = pairs
local tonumber = tonumber
local math_huge = math.huge

local State = {}

local SLOT_KINDS = {
    phantom = true,
    message = true,
    postcast = true,
    shieldWatch = true,
    shield = true,
    sequel = true,
    cue = true,
}

local function isValidNumber(v)
    return type(v) == "number" and v == v and v ~= math_huge and v ~= -math_huge
end

-- Pause-aware elapsed/remaining, shared by SampleClock and the pure decision
-- functions. Assumes now is already validated; performs no mutation.
local function evaluateClock(clock, now)
    local elapsedSinceReceipt
    if clock.pausedAt ~= nil then
        elapsedSinceReceipt = clock.pausedAt - clock.receivedAt - clock.accumulatedPause
    else
        elapsedSinceReceipt = now - clock.receivedAt - clock.accumulatedPause
    end
    local sourceElapsed = clock.initialElapsed + elapsedSinceReceipt
    local remaining = clock.sourceSpan - sourceElapsed
    return elapsedSinceReceipt, sourceElapsed, remaining
end

function State.New()
    return {
        scopes = {},
        slots = {},
        instancesByOwner = {},
        moduleEpoch = 0,
        encounterEpochs = {},
        nextGeneration = 0,
        scopeSerialCounter = 0,
        nextSlotGeneration = 0,
        awaitingStop = {},
        timelineEvents = {},
        cueCounts = {},
        publications = {},
        startBars = {},
        castBars = {},
    }
end

-- Legacy-compat fields an explicit row may not carry: any of them would let
-- an old hook produce unqualified S2 output.
local EXPLICIT_FORBIDDEN_FIELDS = {
    "channelDuration", "forceDuration", "postCastBar", "phantomFollowupOf",
    "spawnOnMessage", "shieldBar", "secondary", "castDisplayText",
}

local function HasForbiddenExplicitField(row)
    for i = 1, #EXPLICIT_FORBIDDEN_FIELDS do
        if row[EXPLICIT_FORBIDDEN_FIELDS[i]] ~= nil then return true end
    end
    return row.extendByChannel == true
end

local function MovesOrigin(binding)
    return binding.castConfirm ~= nil or binding.castMatch ~= nil
end

local CAST_MATCH_MAX_SPELLS, WAIT_MAX = 4, 5

local function ReadSpellSet(list)
    if type(list) ~= "table" then return nil end
    local count = #list
    if count < 1 or count > CAST_MATCH_MAX_SPELLS then return nil end
    for key in pairs(list) do
        if type(key) ~= "number" or key < 1 or key > count or key % 1 ~= 0 then return nil end
    end
    local set = {}
    for i = 1, count do
        local id = list[i]
        if not isValidNumber(id) or id <= 0 or id % 1 ~= 0 or set[id] then return nil end
        set[id] = true
    end
    return set
end

-- A missing/invalid contract or a forbidden field refuses the row outright;
-- it never falls back to a legacy, Message, CastTimer or phantom binding.
local function BuildExplicitTimerBinding(encounterId, spellId, row)
    local contract = row.timerSource
    if type(contract) ~= "table" then return nil end
    if contract.kind ~= "Timer" then return nil end
    if contract.isCooldown ~= true then return nil end
    if contract.policy ~= "estimated-impact" then return nil end
    if contract.spanMode ~= "remaining-only" then return nil end
    if contract.collisionPolicy ~= "refuse-unresolved-label" then return nil end
    if not isValidNumber(contract.stopTolerance) or contract.stopTolerance <= 0 then return nil end
    if not isValidNumber(row.castDuration) or row.castDuration < 0 then return nil end
    local anchor = contract.anchor
    if anchor ~= nil and anchor ~= "timeline-finished" then return nil end
    local castConfirm = contract.castConfirm
    if castConfirm ~= nil and castConfirm ~= "boss-cast-start" then return nil end
    local pausedStop = contract.pausedStop
    if pausedStop ~= nil and (pausedStop ~= "retire" or anchor ~= "timeline-finished") then return nil end
    local queueAfter = contract.queueAfter
    if queueAfter ~= nil and (type(queueAfter) ~= "table" or not isValidNumber(queueAfter.parent)
        or not isValidNumber(queueAfter.delay) or queueAfter.delay <= 0) then
        return nil
    end
    local canceledStop = contract.canceledStop
    if canceledStop ~= nil and (type(canceledStop) ~= "table"
        or not isValidNumber(canceledStop.stage) or canceledStop.stage <= 0
        or not isValidNumber(canceledStop.within) or canceledStop.within <= 0 or canceledStop.within > 1
        or anchor ~= "timeline-finished" or castConfirm ~= nil or pausedStop ~= nil or queueAfter ~= nil) then
        return nil
    end
    local retainEarlyFinished = contract.retainEarlyFinished
    if retainEarlyFinished ~= nil and (retainEarlyFinished ~= true
        or anchor ~= "timeline-finished" or castConfirm ~= nil or pausedStop ~= nil
        or queueAfter ~= nil or canceledStop ~= nil) then
        return nil
    end
    local suppressConcurrentRestart = contract.suppressConcurrentRestart
    if suppressConcurrentRestart ~= nil and (type(suppressConcurrentRestart) ~= "table"
        or not isValidNumber(suppressConcurrentRestart.from)
        or not isValidNumber(suppressConcurrentRestart.duration)
        or suppressConcurrentRestart.duration <= 0
        or suppressConcurrentRestart.from <= suppressConcurrentRestart.duration
        or anchor ~= "timeline-finished" or castConfirm ~= nil or pausedStop ~= nil
        or queueAfter ~= nil or canceledStop ~= nil or retainEarlyFinished ~= nil) then
        return nil
    end
    local holdOverlapping = contract.holdOverlapping
    if holdOverlapping ~= nil and (holdOverlapping ~= true
        or anchor ~= "timeline-finished" or castConfirm ~= nil or pausedStop ~= nil
        or queueAfter ~= nil or canceledStop ~= nil or retainEarlyFinished ~= nil
        or suppressConcurrentRestart ~= nil) then
        return nil
    end
    local replacement = contract.replacement
    if replacement ~= nil and (type(replacement) ~= "table"
        or not isValidNumber(replacement.from) or not isValidNumber(replacement.duration)
        or replacement.duration <= 0 or replacement.from <= replacement.duration
        or anchor ~= "timeline-finished" or castConfirm ~= nil or pausedStop ~= nil
        or queueAfter ~= nil or canceledStop ~= nil or retainEarlyFinished ~= nil
        or suppressConcurrentRestart ~= nil or holdOverlapping ~= nil) then
        return nil
    end
    -- A held receipt has no timeline record, so only an unanchored row may be held.
    local pullReceipt = contract.pullReceipt
    if pullReceipt ~= nil and (pullReceipt ~= true or anchor ~= nil) then return nil end
    local castMatch, castMatchSpells = contract.castMatch, nil
    if castMatch ~= nil then
        if type(castMatch) ~= "table" or not isValidNumber(row.castDuration) or row.castDuration <= 0
            or castConfirm ~= nil or pausedStop ~= nil or queueAfter ~= nil or canceledStop ~= nil
            or retainEarlyFinished ~= nil or suppressConcurrentRestart ~= nil or holdOverlapping ~= nil
            or replacement ~= nil or pullReceipt ~= nil or contract.waitAfter ~= nil then
            return nil
        end
        for field in pairs(castMatch) do
            if field ~= "spells" and field ~= "within" and field ~= "endpoint" then return nil end
        end
        castMatchSpells = ReadSpellSet(castMatch.spells)
        if not castMatchSpells then return nil end
        local within = castMatch.within
        if anchor == "timeline-finished" then
            if not isValidNumber(within) or within <= 0 or within > WAIT_MAX then return nil end
        elseif within ~= nil then
            return nil
        end
        local endpoint = castMatch.endpoint
        if endpoint ~= nil and (endpoint ~= "cast-end" or anchor ~= nil) then return nil end
    end
    local waitAfter = contract.waitAfter
    -- The queue builder needs an anchored target, so a queued waitAfter row would lose its queue.
    if waitAfter ~= nil and (not isValidNumber(waitAfter) or waitAfter <= 0 or waitAfter > WAIT_MAX
        or anchor ~= nil or castConfirm ~= nil or queueAfter ~= nil) then
        return nil
    end
    local soonOnHold = contract.soonOnHold
    if soonOnHold ~= nil and (soonOnHold ~= true or anchor ~= "timeline-finished" or holdOverlapping ~= nil) then
        return nil
    end
    -- A forecast known to end early: the countdown runs this many seconds
    -- behind it and still ends at the timeline Finished. The clock keeps the
    -- provider's duration, which the timeline match compares.
    local forecastLead = contract.forecastLead
    if forecastLead ~= nil and (not isValidNumber(forecastLead) or forecastLead <= 0 or forecastLead > 1
        or anchor ~= "timeline-finished" or castConfirm ~= nil or pausedStop ~= nil
        or queueAfter ~= nil or canceledStop ~= nil or retainEarlyFinished ~= nil
        or suppressConcurrentRestart ~= nil or holdOverlapping ~= nil or replacement ~= nil
        or castMatch ~= nil or soonOnHold ~= nil) then
        return nil
    end
    if HasForbiddenExplicitField(row) then return nil end

    return {
        encounterId = encounterId,
        key = spellId,
        kind = "Timer",
        discriminator = true,
        policy = "estimated-impact",
        spanMode = "remaining-only",
        curationId = spellId,
        extension = row.castDuration,
        stopTolerance = contract.stopTolerance,
        collisionPolicy = contract.collisionPolicy,
        anchor = anchor,
        castConfirm = castConfirm,
        pausedStop = pausedStop,
        queueAfter = queueAfter,
        canceledStop = canceledStop and { stage = canceledStop.stage, within = canceledStop.within },
        retainEarlyFinished = retainEarlyFinished,
        suppressConcurrentRestart = suppressConcurrentRestart and {
            from = suppressConcurrentRestart.from, duration = suppressConcurrentRestart.duration,
        },
        holdOverlapping = holdOverlapping,
        replacement = replacement and { from = replacement.from, duration = replacement.duration },
        pullReceipt = pullReceipt,
        castMatch = castMatchSpells and {
            spells = castMatchSpells, within = castMatch.within, endpoint = castMatch.endpoint,
            curated = castMatch.endpoint and row.castDuration or nil,
        },
        waitAfter = waitAfter,
        soonOnHold = soonOnHold,
        forecastLead = forecastLead,
    }
end

local CUE_ALLOWED_FIELDS = {
    name = true, iconOverride = true, source = true, duration = true, leadDelay = true,
    maxPerPull = true, prepareText = true, endedText = true, endedDuration = true,
    endedColor = true, endsOnAnchor = true, hidesForecasts = true, ordinals = true, messageCount = true,
    pullReceipt = true, interruptResult = true, ordinalSounds = true,
    role = true, display = true, displayText = true, color = true, sound = true,
    soundOnHide = true, showAtSeconds = true, disabled = true,
}

-- Settings and slot identity of a phase cue; a cue has no spell ID of its own.
function State.CueKey(encounterId, name)
    return "cue:" .. tostring(encounterId) .. ":" .. tostring(name)
end

local function isNonEmptyString(v)
    return type(v) == "string" and v ~= ""
end

-- Cast IDs are opaque and compared only with ==; callers screen secrets first.
function State.IsCastBarId(v)
    return isNonEmptyString(v) or isValidNumber(v)
end

local function isValidColor(c)
    if type(c) ~= "table" or #c ~= 3 then return false end
    for i = 1, 3 do
        if not isValidNumber(c[i]) or c[i] < 0 or c[i] > 1 then return false end
    end
    return true
end

-- Bound both schema admission and matching to limit the formatting work.
local ORDINAL_MIN, ORDINAL_MAX = 2, 9

local function isValidOrdinalTotal(v)
    return isValidNumber(v) and v % 1 == 0 and v >= ORDINAL_MIN and v <= ORDINAL_MAX
end

local function isValidMessageCount(v)
    return isValidNumber(v) and v % 1 == 0 and v >= 1 and v <= ORDINAL_MAX
end

-- Malformed cues install no binding and have no fallback.
local function ValidateCue(name, cue)
    if type(name) ~= "string" or not name:find("^[a-z][a-z0-9_]*$") then return nil end
    if type(cue) ~= "table" then return nil end
    for field in pairs(cue) do
        if not CUE_ALLOWED_FIELDS[field] then return nil end
    end
    if not isNonEmptyString(cue.name) then return nil end
    if type(cue.iconOverride) ~= "number" and type(cue.iconOverride) ~= "string" then return nil end
    local source = cue.source
    if type(source) ~= "table" then return nil end

    local hasEndedText, hasEndedDuration = cue.endedText ~= nil, cue.endedDuration ~= nil
    if hasEndedText ~= hasEndedDuration then return nil end
    if hasEndedText then
        if not isNonEmptyString(cue.endedText) then return nil end
        if not isValidNumber(cue.endedDuration) or cue.endedDuration <= 0 then return nil end
    end
    if cue.endedColor ~= nil and not (hasEndedText and isValidColor(cue.endedColor)) then return nil end

    local kind = source.kind
    if cue.ordinalSounds ~= nil then
        if kind ~= "Message" or not isValidOrdinalTotal(cue.ordinals)
            or type(cue.ordinalSounds) ~= "table"
            or not isNonEmptyString(cue.sound) or cue.sound == "None" then return nil end
        for i = 1, cue.ordinals do
            local sound = cue.ordinalSounds[i]
            if not isNonEmptyString(sound) or sound == "None" then return nil end
        end
        for i in pairs(cue.ordinalSounds) do
            if not isValidNumber(i) or i % 1 ~= 0 or i < 1 or i > cue.ordinals then return nil end
        end
    end
    local result = cue.interruptResult
    if result ~= nil then
        if kind ~= "Message" or type(result) ~= "table" then return nil end
        if not isValidOrdinalTotal(cue.ordinals) or result.ordinal ~= cue.ordinals then return nil end
        if result.unit ~= "boss1" or not isNonEmptyString(result.displayText) then return nil end
        if not isValidNumber(result.duration) or result.duration <= 0 then return nil end
        if not isValidColor(result.color) then return nil end
    end
    if cue.endsOnAnchor ~= nil and (kind ~= "Sequel" or not isValidNumber(cue.endsOnAnchor)) then
        return nil
    end
    if kind == "Message" then
        if not isValidNumber(source.key) then return nil end
        if not isValidNumber(cue.duration) or cue.duration <= 0 then return nil end
        local lead = cue.leadDelay
        if lead ~= nil and (not isValidNumber(lead) or lead < 0) then return nil end
        local cap = cue.maxPerPull
        if cap ~= nil and (not isValidNumber(cap) or cap < 1 or cap % 1 ~= 0) then return nil end
        if cue.prepareText ~= nil then
            if not isNonEmptyString(cue.prepareText) then return nil end
            if not (lead and lead > 0) then return nil end
        end
        local hides = cue.hidesForecasts
        if hides ~= nil then
            if type(hides) ~= "table" or #hides == 0 then return nil end
            for i = 1, #hides do
                if not isValidNumber(hides[i]) then return nil end
            end
        end
        if cue.ordinals ~= nil then
            -- Each ordinal shows at once and alone: no lead, cap, gate, ending or count around it.
            if not isValidOrdinalTotal(cue.ordinals) then return nil end
            if lead ~= nil or cap ~= nil or cue.prepareText ~= nil or hides ~= nil or hasEndedText
                or cue.messageCount ~= nil then
                return nil
            end
        end
        if cue.messageCount ~= nil and not isValidMessageCount(cue.messageCount) then return nil end
        if cue.pullReceipt ~= nil and cue.pullReceipt ~= true then return nil end
        return kind
    end
    if cue.leadDelay ~= nil or cue.maxPerPull ~= nil or cue.prepareText ~= nil
        or cue.hidesForecasts ~= nil or cue.ordinals ~= nil or cue.messageCount ~= nil
        or cue.pullReceipt ~= nil then
        return nil
    end
    if kind == "Timer" then
        if not isValidNumber(source.key) then return nil end
        if source.isCooldown ~= false then return nil end
        if cue.duration ~= nil then return nil end
        return kind
    end
    if kind == "Sequel" then
        if not isValidNumber(source.parent) then return nil end
        if not isValidNumber(source.after) or source.after < 0 then return nil end
        if not isValidNumber(cue.duration) or cue.duration <= 0 then return nil end
        return kind
    end
    return nil
end

-- Duplicate source claims install neither cue. Sequel claims are checked with rows.
-- Phase Timers have no anchor: their uncounted bars expire without a provider stop.
local function BuildCueBindings(encounterId, phaseCues, bindings)
    local sequelCues, accepted, gateCues = {}, {}, {}
    local claims = { Message = {}, Timer = {} }
    for name, cue in pairs(phaseCues) do
        local kind = ValidateCue(name, cue)
        local cueKey = State.CueKey(encounterId, name)
        if kind == "Sequel" then
            sequelCues[#sequelCues + 1] = { cueKey = cueKey, cue = cue }
        elseif kind then
            local key = cue.source.key
            claims[kind][key] = (claims[kind][key] or 0) + 1
            accepted[#accepted + 1] = { kind = kind, key = key, cueKey = cueKey, hides = cue.hidesForecasts,
                pullReceipt = cue.pullReceipt }
        end
    end
    for i = 1, #accepted do
        local entry = accepted[i]
        if claims[entry.kind][entry.key] == 1 then
            if entry.kind == "Message" then
                bindings.messages[encounterId] = bindings.messages[encounterId] or {}
                bindings.messages[encounterId][entry.key] = {
                    encounterId = encounterId, key = entry.key, kind = "Message",
                    curationId = entry.cueKey, cueKey = entry.cueKey, pullReceipt = entry.pullReceipt,
                }
                if entry.hides then
                    gateCues[#gateCues + 1] = { cueKey = entry.cueKey, hides = entry.hides }
                end
            else
                bindings.phaseTimers[encounterId] = bindings.phaseTimers[encounterId] or {}
                bindings.phaseTimers[encounterId][entry.key] = {
                    encounterId = encounterId, key = entry.key, kind = "Timer", discriminator = false,
                    policy = "estimated-impact", spanMode = "remaining-only",
                    curationId = entry.cueKey, cueKey = entry.cueKey, extension = 0,
                }
            end
        end
    end
    return sequelCues, gateCues
end

-- One Sequel child per parent whose explicit Timer binding anchors on
-- timeline-finished without castConfirm: a confirm would move the origin the
-- child is timed from. A parent named by two Sequel rows gets neither,
-- whatever order pairs() visits them in. A claimed parent owns its
-- forecast-zero decision, so whether its cue is shown cannot change which
-- occurrences reach the child.
local function BuildSequelBindings(encounterId, spells, timersForEncounter, sequelCues)
    local byParent, claims = {}, {}
    for childId, row in pairs(spells) do
        local contract = type(row) == "table" and row.timerSource
        if type(contract) == "table" and contract.kind == "Sequel" then
            local parentId = contract.parent
            if isValidNumber(parentId) then
                claims[parentId] = (claims[parentId] or 0) + 1
                local parent = parentId ~= childId and timersForEncounter and timersForEncounter[parentId]
                if parent and parent.anchor == "timeline-finished" and not MovesOrigin(parent)
                    and isValidNumber(contract.after) and contract.after >= 0
                    and isValidNumber(row.castDuration) and row.castDuration >= 0
                    and contract.after + row.castDuration > 0
                    and not HasForbiddenExplicitField(row) then
                    byParent[parentId] = {
                        encounterId = encounterId,
                        key = childId,
                        kind = "Sequel",
                        curationId = childId,
                        parent = parentId,
                        after = contract.after,
                    }
                end
            end
        end
    end
    for i = 1, #sequelCues do
        local cueKey, cue = sequelCues[i].cueKey, sequelCues[i].cue
        local parentId = cue.source.parent
        claims[parentId] = (claims[parentId] or 0) + 1
        local parent = timersForEncounter and timersForEncounter[parentId]
        local enderId = cue.endsOnAnchor
        local ender = enderId ~= nil and enderId ~= parentId and timersForEncounter
            and timersForEncounter[enderId]
        -- An invalid ender refuses the cue; its claim on the parent still counts.
        local enderValid = enderId == nil
            or (ender and ender.anchor == "timeline-finished" and not MovesOrigin(ender))
        if parent and parent.anchor == "timeline-finished" and not MovesOrigin(parent) and enderValid then
            byParent[parentId] = {
                encounterId = encounterId,
                key = cueKey,
                kind = "Sequel",
                curationId = cueKey,
                cueKey = cueKey,
                parent = parentId,
                after = cue.source.after,
                duration = cue.duration,
                endsOnAnchor = enderId,
            }
        end
    end
    for parentId, count in pairs(claims) do
        if count > 1 then byParent[parentId] = nil end
    end
    if next(byParent) == nil or not timersForEncounter then return nil end
    for parentId in pairs(byParent) do
        timersForEncounter[parentId].ownsExpiry = true
    end
    return byParent
end

-- A row owned only so its forecast-zero decision runs without a frame keeps the
-- unowned Finished admission. A sequel parent is built first and stays strict.
local function OwnExpiryAdmittingFinished(binding)
    if binding.ownsExpiry then return end
    binding.ownsExpiry = true
    binding.admitsLateFinished = true
end

-- A gated row loses its frames for the window, so its forecast-zero decision
-- must run in its own job: every gated row takes the owned expiry.
local function BuildForecastGates(gateCues, timersForEncounter)
    local gates
    for i = 1, #gateCues do
        local entry = gateCues[i]
        local spells, valid = {}, true
        for j = 1, #entry.hides do
            local row = timersForEncounter and timersForEncounter[entry.hides[j]]
            if not (row and row.anchor == "timeline-finished" and not row.holdOverlapping and not MovesOrigin(row)) then
                valid = false
                break
            end
            spells[entry.hides[j]] = true
        end
        if valid then
            gates = gates or {}
            gates[entry.cueKey] = spells
        end
    end
    if not gates then return nil end
    for _, spells in pairs(gates) do
        for spellId in pairs(spells) do OwnExpiryAdmittingFinished(timersForEncounter[spellId]) end
    end
    return gates
end

-- One target per parent. A prediction cancels the target's presentation-begun
-- hold, which must never be an owned expiry, so an owned target is refused,
-- including one that is itself a queue parent. The parent owns its expiry so
-- its Finished is read whether or not its row is shown.
local function BuildQueueBindings(timersForEncounter)
    if not timersForEncounter then return nil end
    local byParent, claims = {}, {}
    for targetId, target in pairs(timersForEncounter) do
        local queueAfter = target.queueAfter
        if queueAfter then
            local parentId = queueAfter.parent
            claims[parentId] = (claims[parentId] or 0) + 1
            local parent = parentId ~= targetId and timersForEncounter[parentId]
            if parent and parent.anchor == "timeline-finished" and not MovesOrigin(parent)
                and target.anchor == "timeline-finished" and not target.ownsExpiry then
                byParent[parentId] = { target = targetId, delay = queueAfter.delay }
            end
        end
    end
    for parentId, entry in pairs(byParent) do
        if claims[parentId] > 1 or claims[entry.target] then byParent[parentId] = nil end
    end
    if next(byParent) == nil then return nil end
    for parentId in pairs(byParent) do OwnExpiryAdmittingFinished(timersForEncounter[parentId]) end
    return byParent
end

local SHIELD_FIELDS = { parent = true, baseAmount = true, timeout = true, displayText = true }

-- A legacy row's shieldBar keeps the cleanup cap its row timing gives.
local function BuildLegacyShieldBinding(encounterId, spellId, row)
    local cfg = row.shieldBar
    if type(cfg) ~= "table" or not isValidNumber(cfg.baseAmount) or cfg.baseAmount <= 0 then return nil end
    local span = row.channelDuration
    if not isValidNumber(span) then span = row.castDuration end
    if not isValidNumber(span) then span = 60 end
    return {
        encounterId = encounterId, parent = spellId, explicit = false,
        baseAmount = cfg.baseAmount, timeout = span + 2, displayText = cfg.displayText,
    }
end

-- One entry per parent, on an anchored unconfirmed explicit Timer row, so the
-- parent's qualified Finished can open the channel window. Every entry naming
-- a parent counts toward its claim, so a malformed second entry still refuses
-- the first.
local function BuildShieldBindings(encounterId, shields, timersForEncounter)
    local byParent, claims = {}, {}
    for i = 1, #shields do
        local entry = shields[i]
        local parentId = type(entry) == "table" and entry.parent
        if isValidNumber(parentId) then
            claims[parentId] = (claims[parentId] or 0) + 1
            local known = true
            for field in pairs(entry) do
                if not SHIELD_FIELDS[field] then known = false end
            end
            local parent = timersForEncounter and timersForEncounter[parentId]
            if known and parent and parent.anchor == "timeline-finished" and not MovesOrigin(parent)
                and isValidNumber(entry.baseAmount) and entry.baseAmount > 0
                and isValidNumber(entry.timeout) and entry.timeout > 0
                and (entry.displayText == nil or isNonEmptyString(entry.displayText)) then
                byParent[parentId] = {
                    encounterId = encounterId, parent = parentId, explicit = true,
                    baseAmount = entry.baseAmount, timeout = entry.timeout, displayText = entry.displayText,
                }
            end
        end
    end
    for parentId, count in pairs(claims) do
        if count > 1 then byParent[parentId] = nil end
    end
    if next(byParent) == nil then return nil end
    return byParent
end

-- Indexes existing encounter data into Timer/Message bindings plus a
-- parent-to-phantom lookup and, for explicit encounters, a parent-to-sequel
-- lookup. spawnOnMessage rows resolve only through Message; phantomFollowupOf
-- and Sequel rows emit no Timer binding of their own. An unknown non-nil
-- timerPolicy deliberately installs nothing for its encounter.
function State.BuildBindings(encounterData)
    encounterData = encounterData or {}
    local bindings = {
        timers = {}, messages = {}, casts = {}, phantoms = {}, sequels = {}, phaseTimers = {},
        cueEnders = {}, cuesEndedByWindow = {}, forecastGates = {}, queues = {}, shields = {},
    }
    for encounterId, encounter in pairs(encounterData) do
        local timerPolicy = encounter.timerPolicy
        local spells = encounter.spells or {}
        if timerPolicy == nil then
            for spellId, row in pairs(spells) do
                if row.phantomFollowupOf then
                    local parentId = tonumber(row.phantomFollowupOf)
                    local phantomsForEncounter = bindings.phantoms[encounterId]
                    if not phantomsForEncounter then
                        phantomsForEncounter = {}
                        bindings.phantoms[encounterId] = phantomsForEncounter
                    end
                    local list = phantomsForEncounter[parentId]
                    if not list then
                        list = {}
                        phantomsForEncounter[parentId] = list
                    end
                    list[#list + 1] = spellId
                elseif row.spawnOnMessage then
                    local messagesForEncounter = bindings.messages[encounterId]
                    if not messagesForEncounter then
                        messagesForEncounter = {}
                        bindings.messages[encounterId] = messagesForEncounter
                    end
                    messagesForEncounter[spellId] = {
                        encounterId = encounterId,
                        key = spellId,
                        kind = "Message",
                        curationId = spellId,
                    }
                else
                    local timersForEncounter = bindings.timers[encounterId]
                    if not timersForEncounter then
                        timersForEncounter = {}
                        bindings.timers[encounterId] = timersForEncounter
                    end
                    local extension = (row.castDuration or 0) + ((row.extendByChannel and row.channelDuration) or 0)
                    timersForEncounter[spellId] = {
                        encounterId = encounterId,
                        key = spellId,
                        kind = "Timer",
                        discriminator = "any",
                        policy = "legacy",
                        spanMode = "remaining-only",
                        curationId = spellId,
                        extension = extension,
                    }
                    local shield = BuildLegacyShieldBinding(encounterId, spellId, row)
                    if shield then
                        bindings.shields[encounterId] = bindings.shields[encounterId] or {}
                        bindings.shields[encounterId][spellId] = shield
                    end
                end
            end
        elseif timerPolicy == "explicit" then
            for spellId, row in pairs(spells) do
                local binding = BuildExplicitTimerBinding(encounterId, spellId, row)
                if binding then
                    local timersForEncounter = bindings.timers[encounterId]
                    if not timersForEncounter then
                        timersForEncounter = {}
                        bindings.timers[encounterId] = timersForEncounter
                    end
                    timersForEncounter[spellId] = binding
                end
            end
            local sequelCues, gateCues = {}, {}
            if type(encounter.phaseCues) == "table" then
                sequelCues, gateCues = BuildCueBindings(encounterId, encounter.phaseCues, bindings)
            end
            bindings.sequels[encounterId] = BuildSequelBindings(encounterId, spells,
                bindings.timers[encounterId], sequelCues)
            bindings.forecastGates[encounterId] = BuildForecastGates(gateCues, bindings.timers[encounterId])
            bindings.queues[encounterId] = BuildQueueBindings(bindings.timers[encounterId])
            if type(encounter.shields) == "table" then
                bindings.shields[encounterId] = BuildShieldBindings(encounterId, encounter.shields,
                    bindings.timers[encounterId])
            end
            local sequelsForEncounter = bindings.sequels[encounterId] or {}
            for _, sequel in pairs(sequelsForEncounter) do
                if sequel.endsOnAnchor then
                    local enders = bindings.cueEnders[encounterId] or {}
                    bindings.cueEnders[encounterId] = enders
                    local list = enders[sequel.endsOnAnchor] or {}
                    enders[sequel.endsOnAnchor] = list
                    list[#list + 1] = sequel.cueKey
                    local window = sequelsForEncounter[sequel.endsOnAnchor]
                    if window and window.cueKey then
                        local ended = bindings.cuesEndedByWindow[window.cueKey] or {}
                        bindings.cuesEndedByWindow[window.cueKey] = ended
                        ended[#ended + 1] = sequel.cueKey
                    end
                end
            end
        end
    end
    return bindings
end

-- Exactly one matching curation contract or refusal; never scans.
function State.ResolveBinding(bindings, encounterIds, activeEncounterId, kind, key, discriminator)
    if not isValidNumber(activeEncounterId) then return nil, "invalid-encounter" end

    local ownsEncounter = false
    if encounterIds then
        for i = 1, #encounterIds do
            if encounterIds[i] == activeEncounterId then
                ownsEncounter = true
                break
            end
        end
    end
    if not ownsEncounter then return nil, "unknown-encounter" end

    local byKind
    if kind == "Timer" then byKind = bindings.timers
    elseif kind == "Message" then byKind = bindings.messages
    elseif kind == "CastTimer" then byKind = bindings.casts
    else return nil, "unknown-kind" end

    if kind == "Timer" and discriminator == false then
        local phaseTimers = bindings.phaseTimers and bindings.phaseTimers[activeEncounterId]
        local phaseBinding = phaseTimers and phaseTimers[key]
        if phaseBinding then return phaseBinding end
    end

    local byEncounter = byKind[activeEncounterId]
    local binding = byEncounter and byEncounter[key]
    if not binding then return nil, "no-binding" end

    if binding.discriminator ~= nil and binding.discriminator ~= "any"
        and binding.discriminator ~= discriminator then
        return nil, "discriminator-mismatch"
    end

    return binding
end

function State.ResolvePullBinding(bindings, encounterIds, kind, key, discriminator)
    if type(encounterIds) ~= "table" then return nil, "invalid-encounter" end
    for i = 1, #encounterIds do
        local binding = State.ResolveBinding(bindings, encounterIds, encounterIds[i], kind, key, discriminator)
        if binding and binding.pullReceipt then return binding end
    end
    return nil, "not-pull-receipt"
end

-- A live scope is reused so repeated Timers keep their slot jobs; after
-- retirement a fresh serial and slot table invalidate the old scope.
function State.AdmitOwner(store, owner, encounterId)
    if owner == nil then return nil, "invalid-owner" end
    if not isValidNumber(encounterId) then return nil, "invalid-encounter" end

    local existing = store.scopes[owner]
    if existing and existing.encounterId == encounterId and State.IsScopeCurrent(store, owner, existing) then
        return existing
    end

    store.scopeSerialCounter = store.scopeSerialCounter + 1
    local scope = {
        owner = owner,
        encounterId = encounterId,
        serial = store.scopeSerialCounter,
        moduleEpoch = store.moduleEpoch,
        encounterEpoch = store.encounterEpochs[encounterId] or 0,
    }
    store.scopes[owner] = scope
    store.slots[owner] = { kinds = {} }
    return scope
end

function State.IsScopeCurrent(store, owner, scope)
    local current = store.scopes[owner]
    if not current or not scope or current ~= scope then return false end
    if current.moduleEpoch ~= store.moduleEpoch then return false end
    if current.encounterEpoch ~= (store.encounterEpochs[current.encounterId] or 0) then return false end
    return true
end

function State.NewClock(remaining, span, now)
    if not isValidNumber(remaining) or remaining <= 0 then return nil, "invalid-remaining" end
    if not isValidNumber(span) or span < remaining then return nil, "invalid-span" end
    if not isValidNumber(now) then return nil, "invalid-time" end
    return {
        receivedAt = now,
        remainingAtReceipt = remaining,
        sourceSpan = span,
        initialElapsed = span - remaining,
        accumulatedPause = 0,
        pausedAt = nil,
        lastAcceptedNow = now,
    }
end

-- Refuses before mutating; advances lastAcceptedNow only on an accepted read.
function State.SampleClock(clock, now)
    if not clock then return nil, "unknown-clock" end
    if not isValidNumber(now) then return nil, "invalid-time" end
    if now < clock.lastAcceptedNow then return nil, "backwards-clock" end
    clock.lastAcceptedNow = now
    return evaluateClock(clock, now)
end

function State.PauseClock(clock, now)
    if not clock then return nil, "unknown-clock" end
    if not isValidNumber(now) then return nil, "invalid-time" end
    if now < clock.lastAcceptedNow then return nil, "backwards-clock" end
    clock.lastAcceptedNow = now
    if clock.pausedAt ~= nil then return false end
    clock.pausedAt = now
    return true
end

function State.ResumeClock(clock, now)
    if not clock then return nil, "unknown-clock" end
    if not isValidNumber(now) then return nil, "invalid-time" end
    if now < clock.lastAcceptedNow then return nil, "backwards-clock" end
    clock.lastAcceptedNow = now
    if clock.pausedAt == nil then return false end
    clock.accumulatedPause = clock.accumulatedPause + (now - clock.pausedAt)
    -- Native casts continue during provider pauses; retain this interval for start admission.
    clock.lastPauseFrom, clock.lastPauseTo = clock.pausedAt, now
    clock.pausedAt = nil
    return true
end

-- Renamed provider bars can share a label; include the cue identity to keep them separate.
local CUE_INSTANCE_PREFIX = "\001cue:"

local function CueInstanceKey(cueKey, label)
    return CUE_INSTANCE_PREFIX .. tostring(cueKey) .. "\001" .. tostring(label)
end

local function InstanceKey(binding, label)
    if binding.cueKey then return CueInstanceKey(binding.cueKey, label) end
    return label
end

-- New instance plus retired predecessor if the same owner/exact label
-- existed. The predecessor is retired only after the new clock validates,
-- so a refused Start leaves the store untouched.
-- A track-only parent keeps dependent timing work without rendering.
function State.Start(store, owner, label, binding, remaining, span, now, primaryAdmitted, trackOnly)
    local scope = store.scopes[owner]
    if not scope then return nil, "unknown-owner" end
    if label == nil then return nil, "invalid-label" end
    if type(binding) ~= "table" then return nil, "invalid-binding" end

    local sourceClock, reason = State.NewClock(remaining, span, now)
    if not sourceClock then return nil, reason end

    store.nextGeneration = store.nextGeneration + 1
    local generation = store.nextGeneration

    local ownerInstances = store.instancesByOwner[owner]
    if not ownerInstances then
        ownerInstances = {}
        store.instancesByOwner[owner] = ownerInstances
    end
    local storeKey = InstanceKey(binding, label)
    local predecessor = ownerInstances[storeKey]
    if predecessor then
        predecessor.state = "retired"
    end

    local encounterId = binding.encounterId
    local instance = {
        owner = owner,
        label = label,
        binding = binding,
        generation = generation,
        scope = scope,
        state = "running",
        sourceClock = sourceClock,
        castClock = nil,
        followupEligible = primaryAdmitted == true,
        followupConsumed = false,
        trackOnly = trackOnly == true,
        moduleEpoch = store.moduleEpoch,
        encounterEpoch = store.encounterEpochs[encounterId] or 0,
        encounterId = encounterId,
        storeKey = storeKey,
    }
    ownerInstances[storeKey] = instance
    return instance, predecessor
end

-- Effective elapsed since receipt, source elapsed, remaining and phase
-- remaining. Paused reads use the held clock; no allocation.
function State.Sample(instance, now)
    if not instance then return nil, "unknown-instance" end

    local effectiveElapsed, sourceElapsed, remaining = State.SampleClock(instance.sourceClock, now)
    if effectiveElapsed == nil then return nil, sourceElapsed end

    local phaseRemaining = remaining
    if instance.castClock then
        local castEffective, castSourceOrReason, castRemaining = State.SampleClock(instance.castClock, now)
        if castEffective == nil then return nil, castSourceOrReason end
        phaseRemaining = castRemaining
    end

    return effectiveElapsed, sourceElapsed, remaining, phaseRemaining
end

function State.Find(store, owner, label)
    local ownerInstances = store.instancesByOwner[owner]
    if not ownerInstances then return nil end
    local instance = ownerInstances[label]
    if not instance or instance.state == "retired" then return nil end
    return instance
end

function State.FindCue(store, owner, cueKey, label)
    local ownerInstances = store.instancesByOwner[owner]
    if not ownerInstances then return nil end
    local instance = ownerInstances[CueInstanceKey(cueKey, label)]
    if not instance or instance.state == "retired" then return nil end
    return instance
end

-- Label-only callbacks follow the latest bound receipt, even after filtering or expiry.
-- A receipt records routing ownership; it does not prove a provider bar was drawn.
function State.NotePublication(store, owner, label, binding)
    if label == nil then return end
    local bucket = store.publications[owner]
    if not bucket then
        bucket = { labels = {} }
        store.publications[owner] = bucket
    end
    bucket.encounterId = binding.encounterId
    bucket.labels[label] = binding.cueKey or false
end

-- Retain a cue's key after expiry so callers cannot fall back to an older same-label row.
function State.FindPublished(store, owner, label)
    local bucket = store.publications[owner]
    local cueKey = bucket and label ~= nil and bucket.labels[label] or nil
    if cueKey then return State.FindCue(store, owner, cueKey, label), cueKey end
    return State.Find(store, owner, label), nil
end

-- Per-owner set of pilot labels seen since their last valid matching stop or
-- explicit teardown: a set, never a source-event count or a key-to-label map.
-- The guard needs a current scope for the claimed encounter; callers screen
-- secret labels before calling.
function State.ObservePilotLabel(store, owner, encounterId, label)
    if label == nil or type(label) ~= "string" or label == "" then return nil, "invalid-label" end
    local scope = store.scopes[owner]
    if not scope or scope.encounterId ~= encounterId or not State.IsScopeCurrent(store, owner, scope) then
        return nil, "invalid-scope"
    end

    local bucket = store.awaitingStop[owner]
    if not bucket then
        bucket = { encounterId = encounterId, labels = {} }
        store.awaitingStop[owner] = bucket
    end
    bucket.encounterId = encounterId
    if bucket.labels[label] then return false, "outstanding" end
    bucket.labels[label] = true
    return true
end

-- Clears a matching entry ahead of the caller's instance lookup. A missing
-- bucket or label is a no-op, so a stray stop can touch no other owner's
-- entry.
function State.ResolveAwaitingStop(store, owner, label)
    if label == nil or type(label) ~= "string" or label == "" then return false end
    local bucket = store.awaitingStop[owner]
    if not bucket or not bucket.labels[label] then return false end
    bucket.labels[label] = nil
    return true
end

-- Encounter-scoped record of a timeline event's NeverSecret fields, keyed by
-- the tick it was added on. Resolution happens at the stop, so the order of
-- the ADDED handler and the publisher's Timer inside one dispatch is moot.
-- maxQueueDuration is optional: an unusable value records nil and only the
-- hold refuses on it.
function State.RecordTimelineEvent(store, encounterId, eventId, duration, now, maxQueueDuration)
    if not isValidNumber(encounterId) then return nil, "invalid-encounter" end
    if not isValidNumber(eventId) then return nil, "invalid-event" end
    if not isValidNumber(duration) or duration <= 0 then return nil, "invalid-duration" end
    if not isValidNumber(now) then return nil, "invalid-time" end
    local byTick = store.timelineEvents[encounterId]
    if not byTick then
        byTick = {}
        store.timelineEvents[encounterId] = byTick
    end
    local list = byTick[now]
    if not list then
        list = {}
        byTick[now] = list
    end
    local maxQueue
    if isValidNumber(maxQueueDuration) and maxQueueDuration >= 0 then maxQueue = maxQueueDuration end
    list[#list + 1] = { id = eventId, duration = duration, maxQueue = maxQueue }
    return true
end

-- With a provider identity only that event qualifies; without one, exactly
-- one event on the receipt tick with the receipt's exact duration. Other
-- ticks are never consulted. The second return is the recorded queue
-- allowance, nil when unusable.
function State.ResolveTimelineEvent(store, instance)
    if not instance then return nil, "unknown-instance" end
    local identity = instance.timelineIdentity
    if identity == "refused" then return nil, "identity-refused" end
    local byTick = store.timelineEvents[instance.encounterId]
    local list = byTick and byTick[instance.sourceClock.receivedAt]
    if identity ~= nil then
        if list then
            for i = 1, #list do
                local entry = list[i]
                if entry.id == identity and entry.duration == instance.sourceClock.remainingAtReceipt then
                    return entry.id, entry.maxQueue
                end
            end
        end
        return nil, "exact-mismatch"
    end
    if not list then return nil, "no-event" end
    local found
    for i = 1, #list do
        if list[i].duration == instance.sourceClock.remainingAtReceipt then
            if found ~= nil then return nil, "ambiguous" end
            found = list[i]
        end
    end
    if found == nil then return nil, "no-event" end
    return found.id, found.maxQueue
end

-- One StartBar evidence record per owner, reused; "poisoned" refuses the rest
-- of a tick whose evidence conflicted.
local function isValidEventId(v)
    return isValidNumber(v) and v > 0 and v % 1 == 0
end

-- A replacement waits on its predecessor, never in a queue that can outlive it.
function State.HoldTimerReplacement(store, owner, label, binding, remaining, now, identity, payload)
    local inst = State.FindPublished(store, owner, label)
    if not inst then return nil, "no-predecessor" end
    if inst.replacementSeen then
        inst.pendingReplacement = nil
        return nil, "ambiguous"
    end
    local opt = binding.replacement
    if not opt or not inst.binding.replacement or inst.binding.curationId ~= binding.curationId
        or inst.state ~= "running" or inst.hasPaused or inst.anchorElapsed ~= nil
        or not State.IsScopeCurrent(store, owner, inst.scope)
        or remaining ~= opt.duration or inst.sourceClock.remainingAtReceipt ~= opt.from
        or not isValidNumber(now) or now < inst.sourceClock.receivedAt
        or not isValidEventId(identity) or not isValidEventId(inst.timelineIdentity)
        or identity == inst.timelineIdentity then
        return nil, "unqualified-replacement"
    end
    inst.replacementSeen = true
    inst.pendingReplacement = {
        encounterId = binding.encounterId, timelineIdentity = identity, payload = payload,
        sourceClock = { receivedAt = now, remainingAtReceipt = remaining },
    }
    return true
end

-- Consume once, before retiring the predecessor. Other controls discard the receipt.
function State.TakeTimerReplacement(store, inst, now, outcome, timelineState, eventId)
    local receipt = inst and inst.pendingReplacement
    if not receipt then return nil end
    inst.pendingReplacement = nil
    if outcome ~= "retire" or timelineState ~= "canceled" or eventId ~= inst.timelineIdentity
        or not State.IsScopeCurrent(store, inst.owner, inst.scope)
        or State.FindPublished(store, inst.owner, inst.label) ~= inst
        or inst.state ~= "running" or inst.hasPaused or inst.anchorElapsed ~= nil
        or not isValidNumber(now) or now < receipt.sourceClock.receivedAt
        or now - receipt.sourceClock.receivedAt > 0.5 then
        return nil
    end
    return receipt
end

-- accepted false: the caller refused shape or secrecy, so no value is compared.
function State.NoteStartBar(store, owner, encounterId, now, accepted, key, text, time, isCooldown, eventId)
    local record = store.startBars[owner]
    if record and record.at == now and record.state ~= "empty" then
        record.state = "poisoned"
        return "poisoned"
    end
    local valid = accepted and isValidNumber(key) and isNonEmptyString(text)
        and isValidNumber(time) and time > 0 and type(isCooldown) == "boolean"
        and isValidEventId(eventId)
    if not record then
        if not valid then return "rejected" end
        record = {}
        store.startBars[owner] = record
    end
    record.at = now
    record.encounterId = encounterId
    if not valid then
        record.state = "empty"
        return "rejected"
    end
    record.state = "pending"
    record.key, record.text, record.time = key, text, time
    record.isCooldown, record.eventId = isCooldown, eventId
    return "pending"
end

-- A nil owner cannot be attributed, so every record pending on this tick is poisoned.
function State.TakeStartBar(store, owner, now)
    if owner == nil then
        State.PoisonStartBars(store, nil, now)
        return "absent"
    end
    local record = store.startBars[owner]
    if not record then return "absent" end
    if record.at ~= now then
        record.state = "empty"
        return "absent"
    end
    if record.state == "poisoned" then return "refused" end
    if record.state ~= "pending" then return "absent" end
    record.state = "empty"
    return "pending", record.key, record.text, record.time, record.isCooldown, record.eventId
end

-- nil without evidence, the event ID on a full match from an enabled bar, else "refused".
function State.MatchStartBar(evidence, key, text, time, isCooldown, eventId,
                             timerKey, timerText, timerTime, timerCooldown, isBarEnabled)
    if evidence == "absent" then return nil end
    if evidence ~= "pending" then return "refused" end
    if isBarEnabled ~= true or key ~= timerKey or text ~= timerText or time ~= timerTime
        or isCooldown ~= timerCooldown then
        return "refused"
    end
    return eventId
end

-- A nil owner poisons every record pending on this tick.
function State.PoisonStartBars(store, owner, now)
    if owner ~= nil then
        local record = store.startBars[owner]
        if record then
            record.state = "poisoned"
            record.at = now
        end
        return
    end
    for _, record in pairs(store.startBars) do
        if record.at == now and record.state == "pending" then record.state = "poisoned" end
    end
end

local HOLD_TOLERANCE = 0.5

-- Hold bound on the pause-excluded elapsed clock: receipt remaining plus the
-- correlated event's queue allowance plus tolerance. Instance data, never a
-- state value: Pause and Resume overwrite instance.state and must leave it.
function State.BeginHold(instance, maxQueueDuration)
    if not instance then return nil, "unknown-instance" end
    if instance.anchorElapsed ~= nil then return nil, "already-anchored" end
    if instance.holdDeadline ~= nil then return nil, "already-held" end
    if not isValidNumber(maxQueueDuration) or maxQueueDuration < 0 then return nil, "invalid-maxqueue" end
    instance.holdDeadline = instance.sourceClock.remainingAtReceipt + maxQueueDuration + HOLD_TOLERANCE
    return instance.holdDeadline
end

-- The start a new prediction must exceed: the last accepted prediction, else
-- the provider deadline. Pause-excluded elapsed-clock units.
local function CurrentStart(instance)
    return instance.predictedStart or instance.sourceClock.remainingAtReceipt
end

-- The one unresolved occurrence that would still be waiting at the queued
-- start. Anchored, retired, track-only and later instances never qualify, and
-- two qualifying instances refuse both.
function State.SelectQueuedTarget(store, owner, targetId, now, delay)
    if not isValidNumber(now) or not isValidNumber(delay) or delay <= 0 then return nil, "invalid-input" end
    local ownerInstances = store.instancesByOwner[owner]
    if not ownerInstances then return nil, "none" end
    local found
    for _, instance in pairs(ownerInstances) do
        if instance.state ~= "retired" and not instance.trackOnly and instance.anchorElapsed == nil
            and instance.binding.curationId == targetId then
            local elapsed = evaluateClock(instance.sourceClock, now)
            if CurrentStart(instance) < elapsed + delay then
                if found then return nil, "ambiguous" end
                found = instance
            end
        end
    end
    if not found then return nil, "none" end
    return found
end

-- The bound is the hold deadline BeginHold would set. It is a conservative
-- qualification and expiry limit, not a proof that no later cast can start:
-- past it the forecast is no longer qualified, so it never outlives the hold.
function State.Predict(instance, now, delay, maxQueue)
    if not instance then return nil, "unknown-instance" end
    if instance.state == "retired" then return nil, "retired" end
    if instance.state == "paused" then return nil, "paused" end
    if instance.anchorElapsed ~= nil then return nil, "already-anchored" end
    if not isValidNumber(delay) or delay <= 0 then return nil, "invalid-delay" end
    if not isValidNumber(maxQueue) or maxQueue < 0 then return nil, "invalid-maxqueue" end
    local elapsed, reason = State.SampleClock(instance.sourceClock, now)
    if elapsed == nil then return nil, reason end
    local start = elapsed + delay
    if start <= CurrentStart(instance) then return nil, "not-later" end
    local bound = instance.sourceClock.remainingAtReceipt + maxQueue + HOLD_TOLERANCE
    if start >= bound then return nil, "beyond-queue" end
    if bound < instance.sourceClock.remainingAtReceipt + (instance.binding.extension or 0) then
        return nil, "truncates-baseline"
    end
    instance.predictedStart = start
    instance.predictBound = bound
    instance.holdDeadline = nil
    return start + (instance.binding.extension or 0), bound
end

function State.PredictedRemaining(instance, effectiveElapsed)
    if instance.predictedStart == nil then return nil end
    return instance.predictedStart + (instance.binding.extension or 0) - effectiveElapsed
end

function State.Pause(store, owner, label, now)
    local instance = State.FindPublished(store, owner, label)
    if not instance then return nil, false end
    instance.pendingReplacement = nil

    if instance.retainedEstimate then return nil, "retained-estimate" end
    -- A completed followed cast runs its remaining offset on wall time.
    if instance.castCompleted then return nil, "cast-completed" end
    local changed, reason = State.PauseClock(instance.sourceClock, now)
    if changed == nil then return nil, reason end
    if changed then
        instance.state = "paused"
        instance.hasPaused = true
        if instance.castClock then
            State.PauseClock(instance.castClock, now)
        end
    end
    return instance, changed
end

function State.Resume(store, owner, label, now)
    local instance = State.FindPublished(store, owner, label)
    if not instance then return nil, false end
    instance.pendingReplacement = nil

    if instance.retainedEstimate then return nil, "retained-estimate" end
    local changed, reason = State.ResumeClock(instance.sourceClock, now)
    if changed == nil then return nil, reason end
    if changed then
        instance.state = "running"
        if instance.castClock then
            State.ResumeClock(instance.castClock, now)
        end
    end
    return instance, changed
end

-- Both stages must match: the stage turns before the previous stage's bars
-- are canceled, so a stop-time read alone would keep those bars as well.
local function CanRetainCanceled(instance, now, providerStage)
    local opt = instance.binding.canceledStop
    if not opt then return false end
    if instance.holdDeadline ~= nil or instance.predictBound ~= nil then return false end
    if instance.publishedStage ~= opt.stage or providerStage ~= opt.stage then return false end
    local effectiveElapsed = evaluateClock(instance.sourceClock, now)
    local deadline = instance.sourceClock.remainingAtReceipt
    return effectiveElapsed >= deadline - opt.within
        and effectiveElapsed <= deadline + instance.binding.stopTolerance
        and effectiveElapsed < deadline + instance.binding.extension
end

-- Some future forecasts finish in the dispatch that publishes them.
local function CanRetainEarlyFinished(instance, now)
    if not instance.binding.retainEarlyFinished or instance.binding.ownsExpiry then return false end
    if instance.state == "paused" or instance.hasPaused then return false end
    if instance.holdDeadline ~= nil or instance.predictBound ~= nil then return false end
    local age = now - instance.sourceClock.receivedAt
    local tolerance = instance.binding.stopTolerance
    return age >= 0 and age <= tolerance and instance.sourceClock.remainingAtReceipt - age > tolerance
end

-- An unusable read records nothing, so the occurrence can never qualify.
function State.RecordPublishedStage(instance, stage)
    if instance and isValidNumber(stage) then instance.publishedStage = stage end
end

-- The occurrence keeps its original end and never anchors, holds or pauses again.
function State.RetainEstimate(instance, reason)
    instance.retainedEstimate = reason
end

-- Pure decision: never mutates the clock. timelineState is "finished",
-- "canceled", "paused" or nil, supplied only for an anchored binding. A
-- Paused read retires a row that opted in with pausedStop. A qualified
-- Finished on an unanchored anchor row outranks the paused test (the module
-- resumes in full before anchoring) but never the hold bound. The
-- estimated-impact branch runs before the legacy forceDuration exception so
-- an unrelated forceDuration cannot excuse an early stop; other non-legacy
-- policies always retire, and the S1 branch table below applies to legacy
-- only. providerStage is read only for a canceledStop row's Canceled stop.
function State.ClassifyStop(instance, now, forceDuration, timelineState, queueAllowance, providerStage)
    if instance.binding.policy == "estimated-impact" then
        if instance.retainedEstimate then return "ignore" end
        if instance.binding.anchor == "timeline-finished" and instance.anchorElapsed == nil
            and timelineState == "finished" then
            if CanRetainEarlyFinished(instance, now) then return "retain-finished" end
            if instance.predictBound ~= nil
                and evaluateClock(instance.sourceClock, now) >= instance.predictBound then
                return "retire"
            end
            local holdDeadline = instance.holdDeadline
            if holdDeadline ~= nil then
                local effectiveElapsed = evaluateClock(instance.sourceClock, now)
                if effectiveElapsed >= holdDeadline then return "retire" end
            elseif instance.binding.ownsExpiry and not instance.binding.admitsLateFinished then
                -- An extended parent needs an expiry-granted hold beyond forecast zero.
                local effectiveElapsed = evaluateClock(instance.sourceClock, now)
                local extension = instance.binding.extension or 0
                local remainingAtReceipt = instance.sourceClock.remainingAtReceipt
                if effectiveElapsed >= remainingAtReceipt + extension + (instance.binding.forecastLead or 0) then
                    -- A zero-extension parent's Finished may precede its expiry job.
                    -- Apply the same queue bound in either callback order.
                    if extension > 0 then return "retire" end
                    if not isValidNumber(queueAllowance) or queueAllowance < 0 then return "retire" end
                    if effectiveElapsed >= remainingAtReceipt + queueAllowance + HOLD_TOLERANCE then
                        return "retire"
                    end
                end
            end
            if instance.state == "paused" then return "resume-and-anchor" end
            return "anchor"
        end
        -- The native cast owns its end even if the provider pauses or stops its forecast.
        if instance.castEndAt ~= nil then return "ignore" end
        if instance.state == "paused" then return "retire" end
        if instance.anchorElapsed ~= nil then return "ignore" end
        if timelineState == "canceled" and CanRetainCanceled(instance, now, providerStage) then
            return "retain-canceled"
        end
        if instance.binding.anchor == "timeline-finished" and timelineState == "canceled" then
            return "retire"
        end
        if instance.binding.pausedStop == "retire" and timelineState == "paused" then return "retire" end

        local effectiveElapsed = evaluateClock(instance.sourceClock, now)
        local providerDeadline = instance.sourceClock.remainingAtReceipt
        local extension = instance.binding.extension or 0
        local predictedEnd = providerDeadline + extension

        -- Rule 4 before rule 3: at zero extension the predicted endpoint
        -- equals the provider deadline, so a stop inside the tolerance would
        -- satisfy both.
        if effectiveElapsed >= predictedEnd then return "retire" end
        if extension <= 0 then return "retire" end

        local tolerance = instance.binding.stopTolerance or 0
        if effectiveElapsed < providerDeadline - tolerance then return "retire" end
        return "keep-estimate"
    end

    if forceDuration then return "ignore" end
    if instance.binding.policy ~= "legacy" then return "retire" end
    if instance.castClock ~= nil then return "retire" end

    local effectiveElapsed = evaluateClock(instance.sourceClock, now)
    local remainingAtReceipt = instance.sourceClock.remainingAtReceipt
    if effectiveElapsed < remainingAtReceipt - 0.5 then return "retire" end

    local extension = instance.binding.extension or 0
    if extension > 0 then
        local totalRemaining = remainingAtReceipt + extension - effectiveElapsed
        if totalRemaining > 0 then return "enter-legacy-cast" end
        return "retire"
    end
    return "legacy-followup-and-retire"
end

-- Records the qualified Finished instant once; a paused clock or a second
-- call refuses. Returns the anchored total in elapsed-clock units, the same
-- unit the reveal and retire job deadlines use. A hold ends here.
function State.Anchor(instance, now, eventId)
    if not instance then return nil, "unknown-instance" end
    if instance.anchorElapsed ~= nil then return nil, "already-anchored" end
    if instance.state == "paused" then return nil, "paused" end
    local effectiveElapsed, reason = State.SampleClock(instance.sourceClock, now)
    if effectiveElapsed == nil then return nil, reason end
    instance.anchorElapsed = effectiveElapsed
    if instance.binding.suppressConcurrentRestart and isValidEventId(eventId) then
        instance.anchorAt, instance.anchorEventId = now, eventId
    end
    instance.holdDeadline = nil
    instance.predictedStart = nil
    instance.predictBound = nil
    return effectiveElapsed + (instance.binding.extension or 0)
end

-- A concurrent shorter restart can outlive the cast that already consumed the forecast.
function State.IsConcurrentRestart(instance, anchored)
    local opt = instance.binding.suppressConcurrentRestart
    if not opt or instance == anchored or instance.owner ~= anchored.owner
        or instance.scope ~= anchored.scope or instance.encounterId ~= anchored.encounterId
        or instance.binding.curationId ~= anchored.binding.curationId then
        return false
    end
    if instance.state ~= "running" or anchored.state ~= "running" or instance.hasPaused
        or instance.anchorElapsed ~= nil or instance.retainedEstimate ~= nil
        or instance.holdDeadline ~= nil or instance.predictBound ~= nil then
        return false
    end
    if not isValidNumber(anchored.anchorAt) or not isValidEventId(anchored.anchorEventId)
        or not isValidEventId(instance.timelineIdentity) or instance.timelineIdentity == anchored.anchorEventId then
        return false
    end
    local tolerance = instance.binding.stopTolerance
    if anchored.sourceClock.remainingAtReceipt ~= opt.from
        or instance.sourceClock.remainingAtReceipt ~= opt.duration
        or not isValidNumber(anchored.anchorElapsed) or anchored.anchorElapsed < opt.from - tolerance then
        return false
    end
    local distance = instance.sourceClock.receivedAt - anchored.anchorAt
    return distance >= -tolerance and distance <= tolerance
end

-- Display/expiry remaining for an anchored instance; nil when not anchored.
function State.AnchoredRemaining(instance, effectiveElapsed)
    if instance.anchorElapsed == nil then return nil end
    local extension = instance.castExtension or instance.binding.extension or 0
    return instance.anchorElapsed + extension - effectiveElapsed
end

function State.Confirm(instance, now)
    if not instance then return nil, "unknown-instance" end
    if instance.anchorElapsed == nil then return nil, "not-anchored" end
    if instance.confirmed then return nil, "already-confirmed" end
    if instance.state == "paused" then return nil, "paused" end
    local effectiveElapsed, reason = State.SampleClock(instance.sourceClock, now)
    if effectiveElapsed == nil then return nil, reason end
    instance.anchorElapsed = effectiveElapsed
    instance.confirmed = true
    return effectiveElapsed + (instance.binding.extension or 0)
end

-- Records a fresh cast clock exactly once; a second call refuses. The
-- returned fill is the current total remaining (source clock remaining
-- plus the extension), while the cast clock itself times the full curated
-- extension from this receipt. The cast clock inherits the source clock's
-- paused state, so a Stop received while the source is paused does not
-- start cast-phase time.
function State.BeginLegacyCast(instance, now, extension)
    if not instance then return nil, "unknown-instance" end
    if instance.castClock then return nil, "already-cast" end

    local castClock, reason = State.NewClock(extension, extension, now)
    if not castClock then return nil, reason end

    local effectiveElapsed, sourceElapsedOrReason, fill = State.SampleClock(instance.sourceClock, now)
    if effectiveElapsed == nil then return nil, sourceElapsedOrReason end

    if instance.sourceClock.pausedAt ~= nil then
        castClock.pausedAt = now
    end

    instance.castClock = castClock
    return fill + extension
end

-- Pure decision: never enters a cast from local expiry. The estimated-impact
-- branch has no legacy stale grace and no follow-up.
function State.ClassifyExpiry(instance, now)
    if instance.binding.policy == "estimated-impact" then
        local effectiveElapsed, _, remaining = evaluateClock(instance.sourceClock, now)
        local anchored = State.AnchoredRemaining(instance, effectiveElapsed)
        if anchored ~= nil then
            -- A cast wait outlives a shorter estimate until its own bound; a
            -- longer estimate is ended by the wait's job, never by this read.
            if instance.waitBound ~= nil then
                if effectiveElapsed < instance.waitBound or anchored > 0 then return "keep" end
                return "retire"
            end
            if anchored > 0 then return "keep" end
            return "retire"
        end
        local extension = instance.binding.extension or 0
        if instance.predictBound ~= nil then
            if effectiveElapsed >= instance.predictBound then return "retire" end
            if State.PredictedRemaining(instance, effectiveElapsed) > 0 then return "keep" end
        elseif remaining + extension + (instance.binding.forecastLead or 0) > 0 then
            return "keep"
        end
        -- Forecast zero. Only an anchor row may hold; the module resolves
        -- hold-eligible once and either sets holdDeadline or retires. A
        -- retained terminal event ends at its original estimate.
        if instance.retainedEstimate then return "retire" end
        if instance.binding.anchor ~= "timeline-finished" and not instance.binding.waitAfter then
            return "retire"
        end
        local holdDeadline = instance.holdDeadline
        -- An owned-expiry instance takes this decision in its own job, never
        -- from a presentation, so showing or hiding its cue cannot move it.
        if holdDeadline == nil then
            if instance.binding.ownsExpiry then return "keep" end
            return "hold-eligible"
        end
        if effectiveElapsed < holdDeadline then return "keep" end
        return "retire"
    end

    if instance.binding.policy ~= "legacy" then
        local _, _, remaining = evaluateClock(instance.sourceClock, now)
        if remaining > 0 then return "keep" end
        return "retire"
    end

    if instance.castClock ~= nil then
        local _, _, castRemaining = evaluateClock(instance.castClock, now)
        if castRemaining <= 0 then return "legacy-followup-and-retire" end
        return "keep"
    end

    local _, _, remaining = evaluateClock(instance.sourceClock, now)
    if remaining > 0 then return "keep" end

    local extension = instance.binding.extension or 0
    if extension <= 0 then return "legacy-followup-and-retire" end
    if remaining + extension > -1.5 then return "keep" end
    return "retire"
end

-- Reveal and end instants of a sequel cue planned at its parent's anchor. A
-- window of zero, or one covering the whole span, reveals at the anchor.
function State.PlanSequel(now, after, extension, window)
    if not isValidNumber(now) then return nil, "invalid-time" end
    if not isValidNumber(after) or after < 0 then return nil, "invalid-after" end
    if not isValidNumber(extension) or extension < 0 then return nil, "invalid-extension" end
    if not isValidNumber(window) then return nil, "invalid-window" end
    local span = after + extension
    if span <= 0 then return nil, "invalid-span" end
    local endAt = now + span
    if window <= 0 or window >= span then return now, endAt end
    return endAt - window, endAt
end

-- True once only, for a current instance reachable from the store's own
-- index and started with primaryAdmitted true.
function State.TakeFollowup(store, instance)
    if not instance then return false end
    if State.Find(store, instance.owner, instance.label) ~= instance then return false end
    if not instance.followupEligible then return false end
    if instance.followupConsumed then return false end
    instance.followupConsumed = true
    return true
end

function State.Retire(store, instance)
    if not instance or instance.state == "retired" then return false end
    instance.state = "retired"
    instance.pendingReplacement = nil
    local ownerInstances = store.instancesByOwner[instance.owner]
    local storeKey = instance.storeKey or instance.label
    if ownerInstances and ownerInstances[storeKey] == instance then
        ownerInstances[storeKey] = nil
    end
    return true
end

function State.RetireOwner(store, owner)
    local retired = {}
    local ownerInstances = store.instancesByOwner[owner]
    if ownerInstances then
        for _, instance in pairs(ownerInstances) do
            if instance.state ~= "retired" then
                instance.state = "retired"
                retired[#retired + 1] = instance
            end
        end
    end
    store.scopes[owner] = nil
    store.slots[owner] = nil
    store.instancesByOwner[owner] = nil
    store.awaitingStop[owner] = nil
    store.publications[owner] = nil
    store.startBars[owner] = nil
    return retired
end

-- Buckets are walked by their own recorded encounterId: a filtered or expired
-- record has no instance to find in instancesByOwner, and IsScopeCurrent
-- reads stale for that encounter's scopes once the epoch bumps below.
function State.RetireEncounter(store, encounterId)
    local retired = {}
    for _, ownerInstances in pairs(store.instancesByOwner) do
        for label, instance in pairs(ownerInstances) do
            if instance.state ~= "retired" and instance.encounterId == encounterId then
                instance.state = "retired"
                retired[#retired + 1] = instance
                ownerInstances[label] = nil
            end
        end
    end
    for owner, bucket in pairs(store.awaitingStop) do
        if bucket.encounterId == encounterId then
            store.awaitingStop[owner] = nil
        end
    end
    for owner, bucket in pairs(store.publications) do
        if bucket.encounterId == encounterId then
            store.publications[owner] = nil
        end
    end
    for owner, record in pairs(store.startBars) do
        if record.encounterId == encounterId then
            store.startBars[owner] = nil
        end
    end
    store.timelineEvents[encounterId] = nil
    store.cueCounts[encounterId] = nil
    store.castBars[encounterId] = nil
    store.encounterEpochs[encounterId] = (store.encounterEpochs[encounterId] or 0) + 1
    return retired
end

function State.RetireAll(store)
    local retired = {}
    for _, ownerInstances in pairs(store.instancesByOwner) do
        for label, instance in pairs(ownerInstances) do
            if instance.state ~= "retired" then
                instance.state = "retired"
                retired[#retired + 1] = instance
                ownerInstances[label] = nil
            end
        end
    end
    store.awaitingStop = {}
    store.publications = {}
    store.startBars = {}
    store.timelineEvents = {}
    store.castBars = {}
    store.moduleEpoch = store.moduleEpoch + 1
    return retired
end

-- Slot counters live under the owner's current scope, so a scope no longer
-- current (RetireOwner, epoch bump) invalidates any generation allocated
-- under it, even if the owner is later re-admitted.
function State.NextSlot(store, owner, kind, slotKey)
    local scope = store.scopes[owner]
    if not scope then return nil, "unknown-owner" end
    if not State.IsScopeCurrent(store, owner, scope) then return nil, "stale-scope" end
    if not SLOT_KINDS[kind] then return nil, "unknown-kind" end

    local slots = store.slots[owner]
    if not slots then
        slots = { kinds = {} }
        store.slots[owner] = slots
    end
    local kindTable = slots.kinds[kind]
    if not kindTable then
        kindTable = {}
        slots.kinds[kind] = kindTable
    end
    store.nextSlotGeneration = store.nextSlotGeneration + 1
    local newGeneration = store.nextSlotGeneration
    kindTable[slotKey] = newGeneration
    return newGeneration
end

function State.IsSlotCurrent(store, owner, kind, slotKey, generation)
    local scope = store.scopes[owner]
    if not scope then return false end
    if not State.IsScopeCurrent(store, owner, scope) then return false end
    if not SLOT_KINDS[kind] then return false end
    local slots = store.slots[owner]
    if not slots then return false end
    local kindTable = slots.kinds[kind]
    if not kindTable then return false end
    return kindTable[slotKey] == generation
end

function State.IsCueInterruptCurrent(store, watch, now)
    return isValidNumber(now) and now >= watch.startedAt and now < watch.endAt
        and State.IsScopeCurrent(store, watch.owner, watch.scope)
        and State.IsSlotCurrent(store, watch.owner, "cue", watch.slotKey, watch.generation)
end

function State.MatchCueInterrupt(store, watch, unit, castBarID, now)
    return not watch.completed and unit == watch.unit
        and State.IsCastBarId(castBarID) and State.IsCastBarId(watch.castBarID)
        and castBarID == watch.castBarID and State.IsCueInterruptCurrent(store, watch, now)
end

-- One cast ID belongs to one kick. A completed kick also refuses a repeat of
-- its own number whose ID could not be read; another kick number still shows.
function State.IsCueMessageDuplicate(store, watch, ordinal, castBarID, now)
    if not State.IsCueInterruptCurrent(store, watch, now) then return false end
    if castBarID ~= nil then return castBarID == watch.castBarID end
    return watch.completed == true and watch.ordinal == ordinal
end

-- Whether a source-owned delayed operation may still act. Retired, replaced
-- (generation mismatch) or previous-epoch tokens always fail.
function State.IsCurrent(store, instance, generation, moduleEpoch, encounterEpoch)
    if not instance then return false end
    if instance.state == "retired" then return false end
    if instance.generation ~= generation then return false end
    if store.moduleEpoch ~= moduleEpoch then return false end
    if (store.encounterEpochs[instance.encounterId] or 0) ~= encounterEpoch then return false end
    return true
end

-- Presentation order never changes source clocks or discards a later occurrence.
function State.PresentationHead(store, instance, eligible)
    if not instance.binding.holdOverlapping
        or not State.IsScopeCurrent(store, instance.owner, instance.scope) then return nil end
    local instances = store.instancesByOwner[instance.owner]
    if not instances then return nil end
    local head
    for _, candidate in pairs(instances) do
        if candidate.scope == instance.scope and candidate.encounterId == instance.encounterId
            and candidate.binding.curationId == instance.binding.curationId
            and candidate.binding.holdOverlapping and not candidate.trackOnly
            and State.IsCurrent(store, candidate, candidate.generation, candidate.moduleEpoch, candidate.encounterEpoch)
            and eligible(candidate)
            and (not head or candidate.generation < head.generation) then
            head = candidate
        end
    end
    return head
end

-- elapsed deadlines sample the supplied clock; wall deadlines only need an
-- accepted monotonic now. Never schedules anything.
function State.JobRemaining(clockPolicy, deadline, clock, now)
    if not isValidNumber(deadline) then return nil, "invalid-time" end

    if clockPolicy == "elapsed" then
        local effectiveElapsed, reason = State.SampleClock(clock, now)
        if effectiveElapsed == nil then return nil, reason end
        return deadline - effectiveElapsed
    elseif clockPolicy == "wall" then
        if not isValidNumber(now) then return nil, "invalid-time" end
        return deadline - now
    end
    return nil, "invalid-clock-policy"
end

-- Count filtered receipts too; owner re-admission must not reset the per-pull cap.
function State.AdmitCue(store, encounterId, cueKey, maxPerPull)
    local counts = store.cueCounts[encounterId]
    if not counts then
        counts = {}
        store.cueCounts[encounterId] = counts
    end
    local count = counts[cueKey] or 0
    if maxPerPull ~= nil and count >= maxPerPull then return false, "over-cap" end
    counts[cueKey] = count + 1
    return true
end

function State.ClearCueCounts(store, encounterId)
    store.cueCounts[encounterId] = nil
end

-- Formats the provider's own text for each ordinal and compares, so no
-- locale's wording is parsed. A message equal to two ordinals refuses.
function State.MatchMessageOrdinal(message, template, rename, total)
    if type(message) ~= "string" or type(template) ~= "string" or not isNonEmptyString(rename)
        or not isValidOrdinalTotal(total) then
        return nil, "invalid-input"
    end
    local found
    for n = 1, total do
        local ok, text = pcall(string.format, template, rename, n, total)
        if not ok or type(text) ~= "string" then return nil, "template-error" end
        if text == message then
            if found then return nil, "ambiguous" end
            found = n
        end
    end
    if not found then return nil, "unmatched" end
    return found
end

function State.MatchMessageCount(message, template, rename, n)
    if type(message) ~= "string" or type(template) ~= "string" or not isNonEmptyString(rename)
        or not isValidMessageCount(n) then
        return nil, "invalid-input"
    end
    local ok, text = pcall(string.format, template, rename, n)
    if not ok or type(text) ~= "string" then return nil, "template-error" end
    if text ~= message then return nil, "unmatched" end
    return n
end

-- Option flags are a bit set held in one number. 2^31 bounds both the set and
-- a mask, so adding a clear single bit never leaves the range.
local PROVIDER_FLAG_LIMIT = 2147483648

local function isWholeNumber(v)
    return isValidNumber(v) and v % 1 == 0
end

-- A multi-bit mask would make the arithmetic bit test and the added value
-- wrong, so it is refused, never approximated.
local function isSingleBit(v)
    if not isWholeNumber(v) or v < 1 or v >= PROVIDER_FLAG_LIMIT then return false end
    while v > 1 do
        if v % 2 ~= 0 then return false end
        v = v / 2
    end
    return true
end

local function hasBit(flags, mask)
    return flags % (mask * 2) >= mask
end

function State.ProviderMessageStatus(flags, messageBit, emphasizeBit)
    if not isWholeNumber(flags) or flags < 0 or flags >= PROVIDER_FLAG_LIMIT then return "unknown" end
    if not isSingleBit(messageBit) or not isSingleBit(emphasizeBit) then return "unknown" end
    if messageBit == emphasizeBit then return "unknown" end
    if hasBit(flags, messageBit) or hasBit(flags, emphasizeBit) then return "satisfied" end
    return "missing"
end

-- Only flags read at acceptance may contribute to the new value.
function State.PlanProviderMessageEnable(opened, current)
    if current.inCombat then return "refuse", "combat" end
    if not current.cueEnabled then return "refuse", "cue-disabled" end
    local status = State.ProviderMessageStatus(current.flags, current.messageBit, current.emphasizeBit)
    if status == "unknown" or current.profile == nil then return "refuse", "unknown" end
    if current.profile ~= opened.profile then return "refuse", "profile-changed" end
    if status == "satisfied" then return "satisfied" end
    return "write", current.flags + current.messageBit
end

function State.ProviderSetupGate(input)
    if not input.hasDescriptor then return "no-descriptor" end
    if not input.moduleEnabled then return "module-disabled" end
    if not input.cueEnabled then return "cue-disabled" end
    if input.inCombat then return "combat" end
    if input.applicable == false then return "not-applicable" end
    return nil
end

function State.PlanProviderSetup(input)
    local missing = input.status == "missing"
    if input.pending == "other" then
        return input.explicit and missing and "open" or "keep"
    end
    if input.pending then
        if not missing then return "close" end
        if input.explicit then return "open" end
        if input.pending == "auto" and not input.inInstance then return "close" end
        return "keep"
    end
    if not missing then return "none" end
    if input.explicit then return "open" end
    if input.inInstance and not input.answered then return "open" end
    return "none"
end

-- gates: one owner's records by cue key, each { endsAt = wall time, spells = set }.
function State.GateCovers(gates, curationId, now)
    if not gates or not isValidNumber(now) then return false end
    for _, gate in pairs(gates) do
        if gate.spells[curationId] and now < gate.endsAt then return true end
    end
    return false
end

-- Once a qualified Finished has opened the window, it runs to its own deadline
-- whatever later stops say.
function State.ResolveShieldWatch(explicit, outcome, opened)
    if explicit ~= true or opened then return "keep" end
    if outcome == "anchor" or outcome == "resume-and-anchor" then return "open" end
    if outcome == "ignore" then return "keep" end
    return "close"
end

-- A shield belongs to the boss unit that channeled it.
function State.ShieldUnitMatches(shieldUnit, shieldCastBarId, unit, castBarId)
    if shieldUnit == nil or unit ~= shieldUnit then return false end
    if shieldCastBarId ~= nil and castBarId ~= nil and shieldCastBarId ~= castBarId then return false end
    return true
end

-- An explicit watch belongs to its parent occurrence until the qualified
-- Finished; after it, the opened window outlives the occurrence.
function State.ShieldWatchOnRetire(explicit, finished)
    if explicit ~= true or finished then return "keep" end
    return "close"
end

-- Readability permission does not establish observed cast identity.
local CAST_CLOCK_TOLERANCE = 0.1

-- The cast start and end in seconds when a START (or a pushback of a matched
-- cast) and the same unit's cast snapshot describe one running cast of an
-- allowed spell. Values arrive screened.
function State.CastTimesFromEvidence(spells, startSpell, startBar, snapSpell, snapBar, startMs, endMs, now)
    if type(spells) ~= "table" or startSpell == nil or not spells[startSpell] then return nil, "not-allowed" end
    if snapSpell ~= startSpell then return nil, "snapshot-spell" end
    if not State.IsCastBarId(startBar) or snapBar ~= startBar then return nil, "cast-bar" end
    if not isValidNumber(now) then return nil, "invalid-time" end
    if not isValidNumber(startMs) or not isValidNumber(endMs) or endMs <= startMs then return nil, "cast-times" end
    local castStart, castEnd = startMs / 1000, endMs / 1000
    if castStart > now + CAST_CLOCK_TOLERANCE or castEnd <= now then return nil, "cast-times" end
    return castStart, castEnd
end

-- The cast's end on the pause-excluded clock, plus the user offset, measured
-- from the matched start. The cast end replaces only the curated part of the
-- effective extension, so the offset counts once; never before the start.
local function CastEndExtension(instance, effectiveElapsed, now, castEnd)
    local offset = (instance.binding.extension or 0) - instance.binding.castMatch.curated
    local extension = effectiveElapsed + (castEnd - now) + offset - instance.anchorElapsed
    if extension < 0 then extension = 0 end
    return extension
end

-- From its forecast zero, less the stop tolerance, or from its anchor, until
-- it is confirmed, closed, paused, retired, or its own expiry decision would
-- retire it; a retirement callback that has not run yet keeps nothing open.
function State.IsCastMatchEligible(instance, now)
    if not instance or not instance.binding.castMatch then return false end
    if instance.state ~= "running" or instance.confirmed or instance.castMatchClosed then return false end
    if not isValidNumber(now) then return false end
    if State.ClassifyExpiry(instance, now) ~= "keep" then return false end
    if instance.anchorElapsed ~= nil then return true end
    local elapsed = evaluateClock(instance.sourceClock, now)
    return elapsed >= instance.sourceClock.remainingAtReceipt - instance.binding.stopTolerance
end

-- A wall-clock cast start on the pause-excluded clock of a running
-- occurrence. A start during the latest pause reads the frozen value; a start
-- before it adds that pause back. An earlier pause inside the lead is not
-- added back, so the result can only read early, never late.
local function CastStartElapsed(instance, now, castStart)
    local clock = instance.sourceClock
    local elapsed = evaluateClock(clock, now)
    local from, to = clock.lastPauseFrom, clock.lastPauseTo
    if from == nil or castStart >= to then
        local lead = now - castStart
        if lead < 0 then lead = 0 end
        return elapsed - lead
    end
    if castStart >= from then return elapsed - (now - to) end
    return elapsed - (now - castStart) + (to - from)
end

-- A cast belongs to an occurrence only if it started after that occurrence
-- became eligible, less one stop tolerance for a START that precedes the
-- provider's stop by a frame. An older still-running cast is never adopted.
function State.AdmitsCastStart(instance, now, castStart)
    if not isValidNumber(now) or not isValidNumber(castStart) then return false end
    local tolerance = instance.binding.stopTolerance
    local eligibleFrom = instance.sourceClock.remainingAtReceipt - tolerance
    if instance.anchorElapsed ~= nil and instance.anchorElapsed < eligibleFrom then
        eligibleFrom = instance.anchorElapsed
    end
    return CastStartElapsed(instance, now, castStart) >= eligibleFrom - tolerance
end

function State.SelectCastOccurrence(candidates, spellId, now, castStart)
    local found
    for i = 1, #candidates do
        local instance = candidates[i]
        if State.IsCastMatchEligible(instance, now) and instance.binding.castMatch.spells[spellId]
            and State.AdmitsCastStart(instance, now, castStart) then
            if found then return nil, "ambiguous" end
            found = instance
        end
    end
    if not found then return nil, "no-occurrence" end
    return found
end

-- One observed cast re-times at most one occurrence per pull.
function State.TakeCastBar(store, encounterId, castBarId)
    if not State.IsCastBarId(castBarId) or not isValidNumber(encounterId) then return false end
    local seen = store.castBars[encounterId]
    if not seen then
        seen = {}
        store.castBars[encounterId] = seen
    end
    if seen[castBarId] then return false end
    seen[castBarId] = true
    return true
end

function State.IsCastBarUsed(store, encounterId, castBarId)
    if not State.IsCastBarId(castBarId) or not isValidNumber(encounterId) then return false end
    local seen = store.castBars[encounterId]
    return seen ~= nil and seen[castBarId] == true
end

-- Re-times the occurrence from the cast's start on the pause-excluded clock.
-- A curated row runs its effective extension from there; a cast-end row runs
-- to the cast's own end. Ends any hold, prediction or wait.
function State.MatchCast(instance, now, castStart, castEnd)
    if not instance then return nil, "unknown-instance" end
    if instance.state ~= "running" then return nil, "not-running" end
    if instance.confirmed then return nil, "already-confirmed" end
    if not isValidNumber(castStart) then return nil, "invalid-start" end
    local endpoint = instance.binding.castMatch and instance.binding.castMatch.endpoint
    if endpoint and not isValidNumber(castEnd) then return nil, "invalid-end" end
    if not State.AdmitsCastStart(instance, now, castStart) then return nil, "predates-occurrence" end
    if State.ClassifyExpiry(instance, now) ~= "keep" then return nil, "expired" end
    local effectiveElapsed, reason = State.SampleClock(instance.sourceClock, now)
    if effectiveElapsed == nil then return nil, reason end
    -- Native casts continue during a timeline pause, so the endpoint uses the full wall lead.
    -- Start admission separately uses the pause-excluded clock.
    local lead = now - castStart
    if lead < 0 then lead = 0 end
    instance.anchorElapsed = effectiveElapsed - lead
    if endpoint then
        instance.castExtension = CastEndExtension(instance, effectiveElapsed, now, castEnd)
        instance.castEndAt = castEnd
    end
    instance.confirmed = true
    instance.holdDeadline = nil
    instance.predictedStart = nil
    instance.predictBound = nil
    instance.waitBound = nil
    return instance.anchorElapsed + (instance.castExtension or instance.binding.extension or 0)
end

function State.FollowCastEnd(instance, now, castEnd)
    if not instance then return nil, "unknown-instance" end
    if instance.castExtension == nil then return nil, "not-following" end
    if instance.state ~= "running" then return nil, "not-running" end
    if not isValidNumber(castEnd) then return nil, "invalid-end" end
    -- A countdown its own expiry decision has ended is not revived by a late pushback.
    if State.ClassifyExpiry(instance, now) ~= "keep" then return nil, "expired" end
    local effectiveElapsed, reason = State.SampleClock(instance.sourceClock, now)
    if effectiveElapsed == nil then return nil, reason end
    instance.castExtension = CastEndExtension(instance, effectiveElapsed, now, castEnd)
    instance.castEndAt = castEnd
    return instance.anchorElapsed + instance.castExtension
end

-- kind: "interrupted", "failed" or "stopped", already bound to the followed
-- cast's token and cast bar. An interrupt, a failure or a stop more than one
-- stop tolerance before the last read end did not complete: the occurrence
-- ends without a completion claim. A stop at the end is the completion, so
-- any user offset past it still runs.
function State.EndFollowedCast(instance, kind, now)
    if not instance or instance.castEndAt == nil or instance.state == "retired" then
        return nil, "not-following"
    end
    if kind ~= "interrupted" and kind ~= "failed" and kind ~= "stopped" then return nil, "unknown-kind" end
    if not isValidNumber(now) then return nil, "invalid-time" end
    -- An expired countdown is left to its own due retirement, whatever the
    -- stop: neither an early end nor a completion may move or silence it.
    if State.ClassifyExpiry(instance, now) ~= "keep" then return nil, "expired" end
    if kind == "stopped" and now >= instance.castEndAt - instance.binding.stopTolerance then
        return "completed"
    end
    instance.endedUnconfirmed = true
    return "ended-early"
end

-- After a completing stop the cast ended now, or at its read end when the
-- stop came inside the tolerance before it. Only the user offset still ahead
-- of that end remains, on wall time: a paused clock resumes and the
-- occurrence no longer pauses. Returns the anchored total, the wall seconds
-- left and whether the clock resumed.
function State.CompleteFollowedCast(instance, now)
    if not instance or instance.castEndAt == nil or instance.state == "retired" then
        return nil, "not-following"
    end
    if not isValidNumber(now) then return nil, "invalid-time" end
    -- Completion never reopens a countdown its own expiry decision has ended.
    if State.ClassifyExpiry(instance, now) ~= "keep" then return nil, "expired" end
    local offset = (instance.binding.extension or 0) - instance.binding.castMatch.curated
    local castEnd = instance.castEndAt
    if castEnd < now then castEnd = now end
    local left = castEnd + offset - now
    if left < 0 then left = 0 end
    local resumed = false
    if instance.state == "paused" then
        local changed, reason = State.ResumeClock(instance.sourceClock, now)
        if changed == nil then return nil, reason end
        instance.state = "running"
        resumed = changed
    end
    local effectiveElapsed, reason = State.SampleClock(instance.sourceClock, now)
    if effectiveElapsed == nil then return nil, reason end
    instance.castExtension = effectiveElapsed + left - instance.anchorElapsed
    instance.castEndAt = castEnd
    instance.castCompleted = true
    return instance.anchorElapsed + instance.castExtension, left, resumed
end

-- A provider stop leaves a cast-matched occurrence open only while its exact
-- timeline event reads Active or Finished; anything else closes it for good.
function State.NoteCastMatchStop(instance, timelineState)
    if not instance.binding.castMatch or instance.confirmed then return end
    if timelineState ~= "active" and timelineState ~= "finished" then instance.castMatchClosed = true end
end

-- answers: one { spellId, answer } per boss unit and allowed spell, with answer
-- "readable", "secret" or "unknown". Each allowed spell needs a readable
-- answer from some unit, or no cast could end the wait.
function State.SelectWait(spells, answers)
    if type(answers) ~= "table" or #answers == 0 then return nil, "no-boss-unit" end
    local readable = {}
    for i = 1, #answers do
        if answers[i].answer == "readable" then readable[answers[i].spellId] = true end
    end
    for spellId in pairs(spells) do
        if not readable[spellId] then return nil, "spell-not-readable" end
    end
    return true
end

-- An unclaimed running cast cannot supply another START after the estimate ends.
function State.BeginCastWait(instance, now, castRunning)
    local castMatch = instance and instance.binding.castMatch
    if not (castMatch and castMatch.within) then return nil, "no-wait" end
    if instance.anchorElapsed == nil then return nil, "not-anchored" end
    if instance.confirmed or instance.castMatchClosed then return nil, "closed" end
    if instance.state ~= "running" then return nil, "not-running" end
    if castRunning and isValidNumber(now) and State.ClassifyExpiry(instance, now) ~= "keep" then
        return nil, "cast-running-at-end"
    end
    instance.waitBound = instance.anchorElapsed + castMatch.within
    return instance.waitBound
end

-- An unmatched wait returns to a still-running estimate; past it, the
-- occurrence ends without a completion claim.
function State.EndCastWait(instance, now)
    if instance.waitBound == nil then return nil end
    instance.waitBound = nil
    local elapsed = evaluateClock(instance.sourceClock, now)
    if State.AnchoredRemaining(instance, elapsed) > 0 then return "estimate" end
    instance.endedUnconfirmed = true
    return "expired"
end

-- Past forecast zero the occurrence waits for its provider stop, once; a stop
-- already seen refuses the wait.
function State.BeginForecastWait(instance)
    local within = instance and instance.binding.waitAfter
    if not within then return nil, "no-wait" end
    if instance.forecastWaitDone then return nil, "stop-seen" end
    if instance.holdDeadline ~= nil then return nil, "already-held" end
    instance.holdDeadline = instance.sourceClock.remainingAtReceipt + (instance.binding.extension or 0) + within
    return instance.holdDeadline
end

function State.EndForecastWait(instance)
    if not instance.binding.waitAfter then return end
    instance.forecastWaitDone = true
    instance.holdDeadline = nil
end

function State.ShowsSoon(instance)
    if instance.waitBound ~= nil then return true end
    return instance.holdDeadline ~= nil
        and (instance.binding.soonOnHold == true or instance.binding.waitAfter ~= nil)
end

-- An unconfirmed wait claims no completion, so it ends without a hide sound.
function State.EndsSilently(instance)
    if instance.waitBound ~= nil or instance.endedUnconfirmed then return true end
    return instance.binding.waitAfter ~= nil and instance.holdDeadline ~= nil
end

KE._DungeonTimerState = State
