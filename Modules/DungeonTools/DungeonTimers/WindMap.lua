-- ╔══════════════════════════════════════════════════════════╗
-- ║  WindMap.lua                                             ║
-- ║  Module: Dungeon Timers (wind map)                       ║
-- ║  Purpose: Optional arena panel for an encounter with a   ║
-- ║           windMap entry: next wind arrow, fire drop      ║
-- ║           marker and three forecast cards. Silent.       ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class DungeonTimers
local DT = KitnEssentials:GetModule("DungeonTimers", true)
if not DT then return end

local State = KE._DungeonTimerState
local Map = KE._DungeonWindMapState

local pairs = pairs
local type = type
local CreateFrame = CreateFrame
local GetTime = GetTime
local UIParent = UIParent
local issecretvalue = issecretvalue
local C_Texture = C_Texture
local UnitExists = UnitExists
local UnitIsDead = UnitIsDead

local FRAME_NAME = "KE_DungeonTimersWindMap"

-- Fixed encounter tokens; a token is read for presence, death and casts only,
-- never as a boss identity.
local BOSS_UNITS = { "boss1", "boss2", "boss3", "boss4", "boss5" }
local MAP_FILE = "DungeonTimers\\RubyWindMap.png"

-- Logical units at scale 1: two label lines, a 216 map block holding the
-- 160 arena, and three cards along the bottom.
local WIDTH, HEIGHT, PAD = 232, 320, 8
local LINE_HEIGHT, LINE_GAP, BLOCK_GAP = 14, 4, 6
local MAP_SIZE, ARENA_SIZE = 216, 160
local CARD_WIDTH, CARD_HEIGHT, CARD_GAP, GLYPH_SIZE = 68, 44, 6, 24
local ARROW_SIZE, FIRE_SIZE = 32, 38

-- A Winds cast start belongs to the held wind when it is forecast within
-- this many seconds, or already overdue.
local CAST_LEAD = 5
-- The token the encounter binds Winds of Change to (Erkhart); only its casts
-- are read for confirmation.
local CAST_UNIT = "boss1"
local TICK = 0.1

-- The boss cast events the map reads: the start and every end but STOP,
-- which a completed cast also fires.
local CAST_EVENTS = {
    "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_INTERRUPTED",
    "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_FAILED_QUIET",
}
local CAST_ENDS = {
    UNIT_SPELLCAST_SUCCEEDED = true,
    UNIT_SPELLCAST_INTERRUPTED = false,
    UNIT_SPELLCAST_FAILED = false,
    UNIT_SPELLCAST_FAILED_QUIET = false,
}

local DIRECTION_NAMES = { "North-West", "South-West", "South-East", "North-East" }

-- Label strings are built once, so a tick never concatenates.
local WIND_TEXT = {}
for i = 1, #DIRECTION_NAMES do
    WIND_TEXT[i] = "Next wind: " .. DIRECTION_NAMES[i]
end
local DROP_TEXT = {
    airborne = {
        "Drop: North-West", "Drop: South-West, lower", "Drop: South-East", "Drop: North-East, lower",
    },
    grounded = {
        "Drop: North-West", "Drop: South-West, upper", "Drop: South-East", "Drop: North-East, upper",
    },
}
local WIND_WAITING, WIND_SYNCING = "Next wind: --", "Next wind: Syncing"
local DROP_WAITING, DROP_SYNCING = "Drop: --", "Drop: Syncing"

-- Each arrow starts at the opposite edge and travels toward its own side.
local ARROWS = {
    { atlas = "NPE_ArrowUp", point = "BOTTOM", x = 0, y = 128 },
    { atlas = "NPE_ArrowLeft", point = "RIGHT", x = -128, y = 0 },
    { atlas = "NPE_ArrowDown", point = "TOP", x = 0, y = -128 },
    { atlas = "NPE_ArrowRight", point = "LEFT", x = 128, y = 0 },
}
local FIRE_ATLAS = "dreamsurge_fire-portal-icon"
-- The marker sits on the edge the wind needs. On a side edge the phase picks
-- the lower part while the dragon is airborne and the upper once grounded.
local FIRE_POINTS = {
    airborne = { { 0, 36 }, { -36, -18 }, { 0, -72 }, { 36, -18 } },
    grounded = { { 0, 72 }, { -36, 18 }, { 0, -36 }, { 36, 18 } },
}

local BACKDROP = {
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
}
local LINK_COLOR = { 1, 0.5, 0.1, 1 }
local CARD_BORDER = { 0, 0, 0, 1 }
local FALLBACK_ICON = 134400

local atlasKnown = {}

-- A missing atlas omits its glyph; the labels still carry the state.
local function HasAtlas(atlas)
    local known = atlasKnown[atlas]
    if known == nil then
        known = (C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) ~= nil) or false
        atlasKnown[atlas] = known
    end
    return known
end

local function MapSettings()
    local profile = KE.db and KE.db.profile
    local db = profile and profile.DungeonTimers
    return db and db.WindMap
end

local function PreviewSpitId()
    for _, enc in pairs(KE.EncounterData) do
        if type(enc.windMap) == "table" then return enc.windMap.spit end
    end
    return nil
end

local function SetGatedText(fontString, text)
    if fontString._windMapText == text then return end
    fontString._windMapText = text
    fontString:SetText(text)
end

local function NewText(parent, size)
    local text = parent:CreateFontString(nil, "OVERLAY")
    KE:ApplyFontToText(text, "Expressway", size, "OUTLINE")
    return text
end

local function NewCard(frame, index)
    local card = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    card:SetSize(CARD_WIDTH, CARD_HEIGHT)
    card:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PAD + (index - 1) * (CARD_WIDTH + CARD_GAP), PAD)
    card:SetBackdrop(BACKDROP)
    card:SetBackdropColor(0, 0, 0, 0.6)
    card:SetBackdropBorderColor(CARD_BORDER[1], CARD_BORDER[2], CARD_BORDER[3], CARD_BORDER[4])
    card.glyph = card:CreateTexture(nil, "ARTWORK")
    card.glyph:SetSize(GLYPH_SIZE, GLYPH_SIZE)
    card.glyph:SetPoint("TOP", card, "TOP", 0, -3)
    card.mark = NewText(card, 14)
    card.mark:SetPoint("CENTER", card.glyph, "CENTER", 0, 0)
    card.time = NewText(card, 11)
    card.time:SetPoint("BOTTOM", card, "BOTTOM", 0, 3)
    card:Hide()
    return card
end

local function ShowArrow(frame, direction)
    local cfg = direction and ARROWS[direction]
    if not (cfg and HasAtlas(cfg.atlas)) then
        if frame.arrowDirection then
            frame.arrowDirection = nil
            frame.arrowGroup:Stop()
            frame.arrow:Hide()
        end
        return
    end
    if frame.arrowDirection == direction then return end
    frame.arrowDirection = direction
    frame.arrowGroup:Stop()
    frame.arrow:SetAtlas(cfg.atlas, false)
    frame.arrow:ClearAllPoints()
    frame.arrow:SetPoint(cfg.point, frame.arena, cfg.point, 0, 0)
    frame.arrowMove:SetOffset(cfg.x, cfg.y)
    frame.arrow:Show()
    frame.arrowGroup:Play()
end

local function ShowFire(frame, direction, phase)
    local points = phase and FIRE_POINTS[phase]
    local point = points and direction and points[direction]
    if not (point and HasAtlas(FIRE_ATLAS)) then
        if frame.fireDirection then
            frame.fireDirection = nil
            frame.firePhase = nil
            frame.fireAlpha:Stop()
            frame.fireScale:Stop()
            frame.fire:Hide()
        end
        return
    end
    if frame.fireDirection == direction and frame.firePhase == phase then return end
    frame.fireDirection = direction
    frame.firePhase = phase
    frame.fire:ClearAllPoints()
    frame.fire:SetPoint("CENTER", frame.arena, "CENTER", point[1], point[2])
    frame.fire:Show()
    frame.fireAlpha:Stop()
    frame.fireAlpha:Play()
    frame.fireScale:Stop()
    frame.fireScale:Play()
end

local function SetCardGlyph(card, view, spitIcon)
    local key = view.kind == "spit" and "spit" or (view.direction or "unknown")
    if card.glyphKey == key then return end
    card.glyphKey = key
    local cfg = view.kind == "wind" and view.direction and ARROWS[view.direction]
    if view.kind == "spit" then
        card.glyph:SetTexture(spitIcon or FALLBACK_ICON)
        card.glyph:SetTexCoord(0, 1, 0, 1)
        card.glyph:Show()
        SetGatedText(card.mark, "")
    elseif cfg and HasAtlas(cfg.atlas) then
        card.glyph:SetAtlas(cfg.atlas, false)
        card.glyph:Show()
        SetGatedText(card.mark, "")
    else
        card.glyph:Hide()
        SetGatedText(card.mark, "?")
    end
end

local function ShowCard(card, view, now, emphasized, linked, spitIcon)
    if not view then
        if card.mapShown then
            card.mapShown = nil
            card:Hide()
        end
        return
    end
    SetCardGlyph(card, view, spitIcon)
    SetGatedText(card.time, Map.CardText(view, now))
    if card.linked ~= linked then
        card.linked = linked
        local border = linked and LINK_COLOR or CARD_BORDER
        card:SetBackdropBorderColor(border[1], border[2], border[3], border[4])
    end
    local alpha = emphasized and 1 or 0.7
    if card.cardAlpha ~= alpha then
        card.cardAlpha = alpha
        card:SetAlpha(alpha)
    end
    if not card.mapShown then
        card.mapShown = true
        card:Show()
    end
end

local function Render(frame, now, ordered, state, side, phase, heldView, spitIcon)
    local known = state == "direction" and side or nil
    local windText = WIND_WAITING
    if known then
        windText = WIND_TEXT[known]
    elseif state == "syncing" then
        windText = WIND_SYNCING
    end
    SetGatedText(frame.windText, windText)
    local phaseTexts = known and phase and DROP_TEXT[phase]
    local placed = phaseTexts and phaseTexts[known] or nil
    local dropText = DROP_WAITING
    if placed then
        dropText = placed
    elseif state == "syncing" then
        dropText = DROP_SYNCING
    end
    SetGatedText(frame.dropText, dropText)
    ShowArrow(frame, known)
    ShowFire(frame, placed and known or nil, phase)
    for i = 1, 3 do
        local view = ordered[i]
        ShowCard(frame.cards[i], view, now, i == 1, placed ~= nil and view ~= nil and view == heldView, spitIcon)
    end
end

local function StartTicker(self)
    if not self._windMapTicker then
        self._windMapTicker = self:ScheduleRepeatingTimer("_WindMapRefresh", TICK)
    end
end

local function StopTicker(self)
    if self._windMapTicker then
        self:CancelTimer(self._windMapTicker)
        self._windMapTicker = nil
    end
end

-- The visibility read is secret-capable. An unreadable answer counts as
-- visible: the tick then runs as it would have, and teardown still ends it.
local function PanelVisible(frame)
    local visible = frame:IsVisible()
    if issecretvalue and issecretvalue(visible) then return true end
    return visible == true
end

-- OnHide does not fire for an already-invisible frame. Explicit hides
-- must also stop animations and the tick.
local function ResetPanel(frame)
    frame.arrowGroup:Stop()
    frame.fireAlpha:Stop()
    frame.fireScale:Stop()
    frame.arrow:Hide()
    frame.fire:Hide()
    frame.arrowDirection = nil
    frame.fireDirection = nil
    frame.firePhase = nil
    StopTicker(DT)
end

local function HidePanel(frame)
    ResetPanel(frame)
    frame:Hide()
end

local function RenderPreview(self, frame)
    local phase = self._windMapPreviewPhase
    local now = GetTime()
    local direction = phase == "grounded" and 4 or 2
    local spit = { kind = "spit", deadline = now + 8, seq = 1 }
    local wind = { kind = "wind", direction = direction, deadline = now + 12, seq = 2 }
    local spitId = PreviewSpitId()
    Render(frame, now, { spit, wind }, "direction", direction, phase, wind,
        spitId and self:ResolveSpellIcon(spitId))
end

function DT:_WindMapFrame()
    local frame = self._windMapFrame
    if frame then return frame end
    frame = CreateFrame("Frame", FRAME_NAME, UIParent, "BackdropTemplate")
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetBackdrop(BACKDROP)
    frame:SetBackdropColor(0, 0, 0, 0.55)
    frame:SetBackdropBorderColor(0, 0, 0, 1)
    frame:Hide()

    frame.windText = NewText(frame, 12)
    frame.windText:SetHeight(LINE_HEIGHT)
    frame.windText:SetPoint("TOP", frame, "TOP", 0, -PAD)
    frame.dropText = NewText(frame, 12)
    frame.dropText:SetHeight(LINE_HEIGHT)
    frame.dropText:SetPoint("TOP", frame.windText, "BOTTOM", 0, -LINE_GAP)

    local block = CreateFrame("Frame", nil, frame)
    block:SetSize(MAP_SIZE, MAP_SIZE)
    block:SetPoint("TOP", frame, "TOP", 0, -(PAD + LINE_HEIGHT * 2 + LINE_GAP + BLOCK_GAP))
    local art = block:CreateTexture(nil, "BACKGROUND")
    art:SetAllPoints()
    art:SetTexture(KE.PATH .. MAP_FILE)

    local arena = CreateFrame("Frame", nil, block)
    arena:SetSize(ARENA_SIZE, ARENA_SIZE)
    arena:SetPoint("CENTER", block, "CENTER", 0, 0)
    frame.arena = arena

    frame.arrow = arena:CreateTexture(nil, "OVERLAY")
    frame.arrow:SetSize(ARROW_SIZE, ARROW_SIZE)
    frame.arrow:Hide()
    frame.arrowGroup = frame.arrow:CreateAnimationGroup()
    frame.arrowGroup:SetLooping("REPEAT")
    frame.arrowMove = frame.arrowGroup:CreateAnimation("Translation")
    frame.arrowMove:SetDuration(1)
    frame.arrowMove:SetSmoothing("OUT")
    frame.arrowMove:SetEndDelay(0.6)

    frame.fire = arena:CreateTexture(nil, "OVERLAY")
    frame.fire:SetSize(FIRE_SIZE, FIRE_SIZE)
    if HasAtlas(FIRE_ATLAS) then frame.fire:SetAtlas(FIRE_ATLAS, false) end
    frame.fire:Hide()
    frame.fireAlpha = frame.fire:CreateAnimationGroup()
    frame.fireAlpha:SetLooping("BOUNCE")
    local fade = frame.fireAlpha:CreateAnimation("Alpha")
    fade:SetFromAlpha(0.5)
    fade:SetToAlpha(1)
    fade:SetDuration(0.6)
    fade:SetSmoothing("IN_OUT")
    frame.fireScale = frame.fire:CreateAnimationGroup()
    frame.fireScale:SetLooping("BOUNCE")
    local pulse = frame.fireScale:CreateAnimation("Scale")
    pulse:SetOrigin("CENTER", 0, 0)
    pulse:SetScaleFrom(1, 1)
    pulse:SetScaleTo(1.15, 1.15)
    pulse:SetDuration(0.6)
    pulse:SetSmoothing("OUT")
    pulse:SetEndDelay(0.05)

    frame.cards = {}
    for i = 1, 3 do frame.cards[i] = NewCard(frame, i) end

    frame:SetScript("OnEvent", function(_, event, ...) DT:_WindMapOnEvent(event, ...) end)

    frame:SetScript("OnHide", ResetPanel)
    -- Visible again, a parent's show included. Anything drawn or started while
    -- invisible is discarded, then the preview or the live panel is redrawn.
    frame:SetScript("OnShow", function(f)
        ResetPanel(f)
        if DT._windMapPreview then
            RenderPreview(DT, f)
        else
            DT:_WindMapRefresh()
        end
    end)

    self._windMapFrame = frame
    return frame
end

function DT:_WindMapApplyLayout()
    local frame, db = self._windMapFrame, MapSettings()
    if not (frame and db) then return end
    frame:SetScale(db.Scale or 1)
    frame:SetAlpha(db.Opacity or 0.9)
    KE:ApplyFramePosition(frame, db.Position, {
        anchorFrameType = db.AnchorFrameType,
        ParentFrame = db.ParentFrame,
        Strata = db.Strata,
    })
end

function DT:_WindMapRegisterEditMode()
    if not KE.EditMode or self._windMapEditMode then return end
    self._windMapEditMode = true
    KE.EditMode:RegisterElement({
        key = "DungeonTimersWindMap",
        module = self,
        displayName = "Ruby Wind Map",
        frameName = FRAME_NAME,
        isEligible = function()
            local db = MapSettings()
            return db ~= nil and db.Enabled == true
        end,
        getPosition = function()
            local db = MapSettings()
            return db and db.Position
        end,
        setPosition = function(pos)
            local db = MapSettings()
            if not db then return end
            db.Position = pos
            self:_WindMapApplyLayout()
        end,
        getParentFrame = function()
            local db = MapSettings()
            return KE:ResolveAnchorFrame(db and db.AnchorFrameType, db and db.ParentFrame)
        end,
        guiPath = "DTimers_Main",
        guiTab = "DTimers_Dungeons",
    })
end

-- Raw receipt values, read before the row filters and the icon override. The
-- provider sends the receipt whether or not its own bar is enabled, so
-- admission needs no timeline identity; identity only qualifies the stop.
function DT:_WindMapRead(binding, icon, counter)
    local cfg = self._windMapConfig
    if not cfg or binding.encounterId ~= self._windMapEncounterId then return nil end
    local kind
    if binding.curationId == cfg.wind then
        kind = "wind"
    elseif binding.curationId == cfg.spit then
        kind = "spit"
    else
        return nil
    end
    if issecretvalue and issecretvalue(counter) then counter = nil end
    local direction = kind == "wind" and Map.ReadDirection(icon, counter) or nil
    return { kind = kind, direction = direction }
end

-- Fresh forecast deadlines for the wind records, sampled at every receipt,
-- stop, record end and Winds start, so the held wind never waits on a render.
-- A record no longer current keeps its last deadline.
local function SampleWinds(self, map, now)
    for inst, rec in pairs(map.records) do
        if rec.kind == "wind"
            and State.IsCurrent(self._state, inst, rec.generation, inst.moduleEpoch, inst.encounterEpoch) then
            local _, _, remaining = State.Sample(inst, now)
            if remaining then rec.deadline = now + remaining end
        end
    end
end

-- A wind's owner is the one whose shutdown loses the sequence.
function DT:_WindMapAttach(inst, mapData)
    local map = self._windMap
    if not map then return end
    if Map.Admit(map, inst, inst.generation, mapData.kind, mapData.direction) then
        inst.mapObserved = true
        if mapData.kind == "wind" then
            self._windMapOwner = inst.owner
            SampleWinds(self, map, GetTime())
        end
    end
    self:_WindMapWake()
end

-- A stop that neither retires nor reads Canceled is the forecast running out.
-- It is card text only; a read Finished state shows as "Due".
function DT:_WindMapStop(inst, outcome, timelineState)
    local map = self._windMap
    if not map then return end
    if outcome ~= "retire" and timelineState ~= "canceled" then
        local now = GetTime()
        SampleWinds(self, map, now)
        Map.NoteStopped(map, inst, inst.generation, now, timelineState == "finished")
    end
    self:_WindMapWake()
end

-- A confirmed cast-matched occurrence's anchor is its observed cast start.
function DT:_WindMapRetimed(inst, now)
    local map = self._windMap
    if not map then return end
    if inst.confirmed and inst.anchorElapsed ~= nil then
        local elapsed = State.Sample(inst, now)
        if elapsed then Map.NoteCastStart(map, inst, inst.generation, now - (elapsed - inst.anchorElapsed)) end
    end
    self:_WindMapWake()
end

-- Retirement clears current identity before this call. Sample the owned
-- clock directly to preserve pauses that occurred while the panel was hidden.
function DT:_WindMapRetired(inst)
    local map = self._windMap
    if not map then return end
    local now = GetTime()
    SampleWinds(self, map, now)
    local rec = map.records[inst]
    if rec and rec.kind == "wind" and rec.generation == inst.generation then
        local _, _, remaining = State.Sample(inst, now)
        if remaining then rec.deadline = now + remaining end
    end
    Map.NoteRetired(map, inst, inst.generation)
    self:_WindMapWake()
end

-- The encounter's stage moved forward. It moves the placement phase even when
-- no map receipt arrives with it.
function DT:_WindMapStage(stage)
    local map = self._windMap
    if not map then return end
    Map.NoteStage(map, stage)
    self:_WindMapWake()
end

-- The owner's shutdown retires its occurrences and loses the sequence.
function DT:_WindMapOwnerStopped(owner)
    local map = self._windMap
    if not map then return end
    if owner == self._windMapOwner then Map.EndHistory(map) end
    self:_WindMapWake()
end

-- Undoes map observation, leaving the occurrence as it would be without the
-- map: a map-only one, or a filtered parent already past its anchor, retires;
-- any other keeps its own timing and drops cast matching it has only for the map.
function DT:_ReleaseMapObservation(inst)
    if not inst.mapObserved then return end
    inst.mapObserved = nil
    if inst.state == "retired" then return end
    local retireJobs = self._observedRetireJobs
    if inst.mapOnly or (retireJobs and retireJobs[inst]) then
        State.Retire(self._state, inst)
        self:ReleaseInstancePresentations(inst, false)
        return
    end
    local presentations = self._presentations[inst]
    if not (presentations and (presentations.primary or presentations.secondary)) then
        self:_CloseCastMatch(inst)
    end
end

local function Readable(value)
    if issecretvalue and issecretvalue(value) then return nil end
    return value
end

-- Reads the fixed boss tokens. A readable dead boss or a readably lost token
-- withdraws inference for the rest of the encounter, in the store and in the
-- encounter's evidence: the held wind and its step are dropped, and only live
-- published winds give a side. Unreadable answers change nothing. Withdrawal
-- is final, so the watch then stops.
function DT:_WindMapScanBosses()
    local map, evidence = self._windMap, self._windMapEvidence
    if not (map and evidence) or map.inferenceWithdrawn then return end
    for i = 1, #BOSS_UNITS do
        local unit = BOSS_UNITS[i]
        local exists = Readable(UnitExists(unit))
        local dead
        if exists == true then dead = Readable(UnitIsDead(unit)) end
        if Map.BossLost(evidence.seen, unit, exists, dead) then
            Map.WithdrawInference(map, evidence)
            self:_WindMapStopBossWatch()
            self:_WindMapWake()
            return
        end
    end
end

-- Flag changes and roster changes on the boss tokens rescan them, so a held
-- wind is covered while no card is live and no tick runs. The tokens seen
-- live in the encounter's evidence, so a restart keeps them.
function DT:_WindMapStartBossWatch(frame)
    frame:RegisterUnitEvent("UNIT_FLAGS", "boss1", "boss2", "boss3", "boss4", "boss5")
    frame:RegisterEvent("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
    self:_WindMapScanBosses()
end

function DT:_WindMapStopBossWatch()
    local frame = self._windMapFrame
    if not frame then return end
    frame:UnregisterEvent("UNIT_FLAGS")
    frame:UnregisterEvent("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
end

-- Watch only Erkhart so unreadable casts from the other boss cannot end
-- the wind sequence. Confirmation outlives forecast cards and withdrawal.
function DT:_WindMapStartCastWatch(frame)
    for i = 1, #CAST_EVENTS do
        frame:RegisterUnitEvent(CAST_EVENTS[i], CAST_UNIT)
    end
end

function DT:_WindMapStopCastWatch()
    local frame = self._windMapFrame
    if not frame then return end
    for i = 1, #CAST_EVENTS do frame:UnregisterEvent(CAST_EVENTS[i]) end
end

-- Unreadable identity may hide a Winds start, and switches the map to live
-- published sides. Readable starts use freshly sampled deadlines even while
-- the panel is hidden.
function DT:_WindMapCastStart(unit, spellID, castBarID)
    local map, cfg = self._windMap, self._windMapConfig
    if not (map and cfg) then return end
    local spell = Readable(spellID)
    if spell ~= nil and spell ~= cfg.wind then return end
    local bar = Readable(castBarID)
    local token = Readable(unit)
    if spell == nil or token == nil or type(bar) ~= "number" then
        if type(bar) ~= "number" then bar = nil end
        if Map.UnreadableCast(map, token, bar) then
            self:_WindMapStopBossWatch()
            DT._dprint("windmap published-only reason=unreadable-cast")
        end
        self:_WindMapWake()
        return
    end
    local now = GetTime()
    SampleWinds(self, map, now)
    Map.BindCast(map, unit, bar, now, CAST_LEAD)
    self:_WindMapWake()
end

function DT:_WindMapCastEnded(unit, castBarID, succeeded)
    local map = self._windMap
    local bar = Readable(castBarID)
    if not map or type(bar) ~= "number" or Readable(unit) == nil then return end
    if Map.CastEnded(map, unit, bar, succeeded) then self:_WindMapWake() end
end

function DT:_WindMapOnEvent(event, unit, _, spellID, arg4, arg5)
    if event == "UNIT_SPELLCAST_START" then
        self:_WindMapCastStart(unit, spellID, arg4)
    elseif CAST_ENDS[event] ~= nil then
        -- An interrupt carries the interrupter before the cast bar.
        local bar = arg4
        if event == "UNIT_SPELLCAST_INTERRUPTED" then bar = arg5 end
        self:_WindMapCastEnded(unit, bar, CAST_ENDS[event])
    else
        self:_WindMapScanBosses()
    end
end

function DT:_WindMapWake()
    local frame = self._windMapFrame
    if not (frame and self._windMap) or self._windMapPreview or not PanelVisible(frame) then return end
    StartTicker(self)
end

local viewList = {}

function DT:_WindMapRefresh()
    local map, frame = self._windMap, self._windMapFrame
    if not (map and frame) or self._windMapPreview then
        StopTicker(self)
        return
    end
    -- Each render rereads the boss tokens, in case no event reported a change.
    self:_WindMapScanBosses()
    local now = GetTime()
    local count = 0
    for inst, rec in pairs(map.records) do
        if not State.IsCurrent(self._state, inst, rec.generation, inst.moduleEpoch, inst.encounterEpoch) then
            Map.NoteRetired(map, inst, rec.generation)
        else
            local _, _, remaining = State.Sample(inst, now)
            if remaining then
                rec.deadline = now + remaining
                rec.paused = inst.state == "paused"
                rec.soon = State.ShowsSoon(inst)
                count = count + 1
                viewList[count] = rec
            end
        end
    end
    for i = count + 1, #viewList do viewList[i] = nil end
    local ordered = Map.Order(viewList)
    local state, side, held = Map.NextWind(map)
    Render(frame, now, ordered, state, side, map.phase, held, self._windMapSpitIcon)
    if count > 0 and PanelVisible(frame) then
        StartTicker(self)
    else
        StopTicker(self)
    end
end

function DT:_WindMapEncounterStart(encounterId, fromEncounterStart)
    self:_WindMapTeardown()
    -- Boss evidence lives for the whole encounter and only a watch from its
    -- start creates it, so a later start never inherits an earlier pull's.
    if fromEncounterStart then self._windMapEvidence = nil end
    local db = MapSettings()
    local enc = encounterId and KE.EncounterData[encounterId]
    local cfg = enc and enc.windMap
    if not (db and db.Enabled == true and type(cfg) == "table") then return end
    local timers = self._bindings and self._bindings.timers[encounterId]
    local windBinding = timers and timers[cfg.wind]
    if not (windBinding and timers[cfg.spit]) then return end
    if fromEncounterStart then self._windMapEvidence = Map.NewEvidence(encounterId) end
    local evidence = self._windMapEvidence
    if evidence and evidence.encounterId ~= encounterId then evidence = nil end
    self._windMap = Map.New()
    -- Only a store started with the encounter saw every wind; any later start
    -- (the map turned on, or a profile change) begins withdrawn and unsure.
    Map.Resume(self._windMap, evidence, fromEncounterStart)
    -- Starts from the encounter's stage, so turning the map on after the
    -- landing is grounded at once.
    Map.NoteStage(self._windMap, self._encounterStage)
    self._windMapConfig = cfg
    self._windMapEncounterId = encounterId
    self._windMapSpitIcon = self:ResolveSpellIcon(cfg.spit)
    local frame = self:_WindMapFrame()
    -- The boss watch serves only a store that can still withdraw.
    if not self._windMap.inferenceWithdrawn then self:_WindMapStartBossWatch(frame) end
    self:_WindMapStartCastWatch(frame)
    self:_WindMapApplyLayout()
    if not self._windMapPreview then
        frame:Show()
        self:_WindMapRefresh()
    end
end

-- Releases what the map added to live occurrences, then hides the panel. Every
-- boundary also ends the preview, except a settings change made from the
-- preview's own row (keepPreview).
function DT:_WindMapTeardown(keepPreview)
    local map = self._windMap
    self._windMap = nil
    self._windMapConfig = nil
    self._windMapEncounterId = nil
    self._windMapOwner = nil
    self:_WindMapStopBossWatch()
    self:_WindMapStopCastWatch()
    if map then
        for inst in pairs(map.records) do self:_ReleaseMapObservation(inst) end
    end
    if not keepPreview then self._windMapPreview = false end
    local frame = self._windMapFrame
    if frame and not self._windMapPreview then HidePanel(frame) end
end

function DT:ApplyWindMapSettings()
    local db = MapSettings()
    local enabled = db ~= nil and db.Enabled == true
    if enabled then
        self:_WindMapFrame()
        self:_WindMapRegisterEditMode()
        if not self._windMap and self._activeEncounterId and self:IsEnabled() then
            self:_WindMapEncounterStart(self._activeEncounterId)
        end
    elseif self._windMap then
        self:_WindMapTeardown(true)
    end
    self:_WindMapApplyLayout()
    if self._windMapPreview then self:ShowWindMapPreview(self._windMapPreviewPhase) end
end

function DT:ShowWindMapPreview(phase)
    if phase ~= "grounded" then phase = "airborne" end
    local frame = self:_WindMapFrame()
    self._windMapPreview = true
    self._windMapPreviewPhase = phase
    self:_WindMapApplyLayout()
    StopTicker(self)
    frame:Show()
    RenderPreview(self, frame)
end

function DT:HideWindMapPreview()
    if not self._windMapPreview then return end
    self._windMapPreview = false
    local frame = self._windMapFrame
    if not frame then return end
    if self._windMap then
        frame:Show()
        self:_WindMapRefresh()
    else
        HidePanel(frame)
    end
end
