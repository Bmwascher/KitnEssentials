-- ╔══════════════════════════════════════════════════════════╗
-- ║  HealerExternals.lua                                     ║
-- ║  Purpose: party members' externals and raid cooldowns as ║
-- ║           icons in a movable box.                        ║
-- ╚══════════════════════════════════════════════════════════╝
--
-- One group slot of the party cooldowns pipeline. A cell for a spell cast on
-- one target is read from one sensor per party member, so its buff landing on
-- anyone starts the count; a raid cooldown's cell is read from its caster
-- alone. The game names no caster, so another player's cast of the same
-- spell starts it too.

---@class KE
local KE = select(2, ...)

local C_Spell = C_Spell
local CreateFrame = CreateFrame
local UIParent = UIParent
local UnitExists = UnitExists
local ipairs = ipairs
local issecretvalue = issecretvalue
local string_format = string.format

local Rules = KE.HealerExternalsRules
local CDRules = KE.PartyCooldownsRules
local PotRules = KE.PartyPotionsRules
local Cell = KE.PartyCooldownsCell
local Spec = KE.PartyCooldownsSpec
local Track = KE.PartyCooldownsSensor

local HX = {
    members = {}, records = {}, byToken = {}, guids = {}, units = {}, entries = {},
    style = { colors = {} }, sampleCells = {}, sampleTrackers = {},
}
KE.HealerExternals = HX

-- Flip to true, /reload, repro, read the log.
local DEBUG_HX = false

HX.QUEUE_KEY = "healerExternals"
HX.DEFAULT_POSITION = { AnchorFrom = "CENTER", AnchorTo = "CENTER", XOffset = -420, YOffset = 150 }
-- Each position context's saved keys; the Raid Cooldowns page reads them too.
HX.POSITION_KEYS = {
    DEFAULT = { pos = "HealerExtPosition", kind = "HealerExtAnchorFrameType", parent = "HealerExtParentFrame",
                strata = "HealerExtStrata" },
    HEALER  = { pos = "HealerExtHealerPosition", kind = "HealerExtHealerAnchorFrameType",
                parent = "HealerExtHealerParentFrame", strata = "HealerExtHealerStrata" },
}
-- "HEALER" or "DEFAULT": the view the Raid Cooldowns page shows, whatever
-- the switch. Never cleared: reopening the settings shows the page again
-- without rendering it.
HX.previewContext = nil
-- The context the box was last placed in, whether Use Healer Position was on
-- then, and the settings table it was placed from. Only HX.ApplyPosition sets
-- them; the label, the getters and the writer read them, so all three
-- describe the box where it stands.
local placedContext, placedSplit, placedDB = "DEFAULT", false, nil
-- Seconds between checks for the end of a drag that refused a placement.
local DRAG_RETRY = 0.2
-- The cooldown icon with no active state laid over it.
HX.VIEW = {
    New = Cell.New, Dress = Cell.Dress, Write = Cell.Write, Range = Cell.Range, Clear = Cell.Clear,
    Seat = Cell.Seat, WriteCharges = Cell.WriteCharges, overlay = false,
}

-- Reads wait out a roster change, longer than the module's 0.5 s settle.
local ROSTER_HOLD = 1
local BLACK = { 0, 0, 0, 1 }
local screen = { anchorFrameType = "UIPARENT" }
local EDIT_MODE_KEY = "HealerExternals"
-- Per grow direction: the box corner the first icon sits in, and the step.
local GROW = {
    RIGHT = { corner = "TOPLEFT",    dx = 1,  dy = 0 },
    LEFT  = { corner = "TOPRIGHT",   dx = -1, dy = 0 },
    DOWN  = { corner = "TOPLEFT",    dx = 0,  dy = -1 },
    UP    = { corner = "BOTTOMLEFT", dx = 0,  dy = 1 },
}
-- Preview icons: left is a sample's seconds to go; one without is ready.
local SAMPLES = { { id = 33206, left = 122 }, { id = 102342 }, { id = 97462 } }

local placement = {}

local function Debug(fmt, ...)
    if DEBUG_HX then KE:Print("Raid Cooldowns: " .. string_format(fmt, ...)) end
end

---------------------------------------------------------------------------------
-- The box, its place and its look
---------------------------------------------------------------------------------
local function NewLayer(parent)
    local layer = CreateFrame("Frame", nil, parent)
    layer:SetAllPoints(parent)
    return layer
end

local function MakeBox()
    if HX.box then return end
    HX.box = CreateFrame("Frame", "KitnEssentialsHealerExternals", UIParent)
    HX.box:Hide()
    HX.live = NewLayer(HX.box)
end

-- The group slot's sensors get a host of their own, shown only while the slot
-- is bound: hiding it stops a sensor whose disable was refused.
local function MakeSlot()
    if HX.st then return end
    local host = CreateFrame("Frame", nil, UIParent)
    host:SetSize(1, 1)
    host:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
    host:Hide()
    HX.sensorHost = host
    HX.st = Track.NewSlot(HX.live, HX.VIEW, host)
end

-- The page's view counts while the box previews with the settings open.
local function ResolveContext(db)
    local PM = KE.PreviewManager
    local pageView = PM and PM.guiOpen and HX.previewContext or nil
    return Rules.PositionContext(db.UseHealerExtPosition == true, KE:IsPlayerHealerSpec(),
        HX.previewing == true, pageView)
end

-- The placed position. An attached box whose anchor the shared resolution
-- refuses (unnamed, missing or unsafe) takes its starting place: the
-- attached points against the screen would put it above the top edge. The
-- third return says the starting place is in use.
local function Placement(db)
    local keys = HX.POSITION_KEYS[placedContext]
    local kind, name, strata = db[keys.kind], db[keys.parent], db[keys.strata]
    screen.Strata, placement.Strata = strata, strata
    if kind == "SELECTFRAME" and KE:ResolveSelectFrame(name, HX.box) == nil then
        return HX.DEFAULT_POSITION, screen, true
    end
    placement.anchorFrameType, placement.ParentFrame = kind, name
    return db[keys.pos], placement, false
end

-- With Use Healer Position on, the label names the position a drag writes.
function HX.EditModeLabel()
    if not placedSplit then return "Raid Cooldowns" end
    return placedContext == "HEALER" and "Raid Cooldowns (Healer)" or "Raid Cooldowns (Default)"
end

-- Renamed in place: registering again would cancel a drag in progress.
local function Relabel()
    if HX.registered then KE.EditMode:SetElementLabel(EDIT_MODE_KEY, HX.EditModeLabel()) end
end

local function PlaceBox()
    if not HX.box or not KE:CanReanchorNow(HX.box) then return end
    local pos, config = Placement(HX.pb.db)
    KE:ApplyFramePosition(HX.box, pos, config)
end

-- Edit Mode keeps a Revert snapshot per element, and Revert hands it to the
-- setter, which now writes the other key set; the selected box's readout
-- shows the old one too.
local function ContextMoved()
    local EM = KE.EditMode
    if not (HX.registered and EM) then return end
    EM:SnapshotElementPosition(EDIT_MODE_KEY)
    if EM.selectedElementKey == EDIT_MODE_KEY then EM:UpdateNudgeFrameInfo() end
end

local placePending, placeGen = false, 0

-- A queued replay cannot be taken back out of the combat queue or a timer,
-- so it carries the generation it was made in and does nothing once that
-- has moved on.
local function CancelPlacement()
    placePending, placeGen = false, placeGen + 1
end

-- Edit Mode has no drag-end callback, and a drag can end by a drop, Escape,
-- combat, a scale change or another element's re-registration.
local function DeferPlacement(inCombat)
    if placePending then return end
    placePending = true
    local gen = placeGen
    local function Replay()
        if gen ~= placeGen then return end
        local EM = KE.EditMode
        if EM and EM:IsAnyDragInFlight() then
            C_Timer.After(DRAG_RETRY, Replay)
            return
        end
        CancelPlacement()
        HX.ApplyPosition()
    end
    if inCombat then
        KE:RunAfterCombat(Replay)
    else
        C_Timer.After(0, Replay)
    end
end

-- The one place the context is resolved. A respec, the settings closing or
-- opening, or a view change moves nothing until the next call. A placement
-- refused in combat or during an Edit Mode drag records nothing and runs
-- again once that has ended: a drag measures against the parent it started
-- with, so a placement during one would have the drop write the wrong offsets.
function HX.ApplyPosition()
    if not (HX.on and HX.box) then return end
    if not KE:CanReanchorNow(HX.box) then return DeferPlacement(true) end
    local EM = KE.EditMode
    if EM and EM:IsAnyDragInFlight() then return DeferPlacement(false) end
    CancelPlacement()
    local db = HX.pb.db
    local context = ResolveContext(db)
    local moved = context ~= placedContext or db ~= placedDB
    placedContext, placedSplit, placedDB = context, db.UseHealerExtPosition == true, db
    Relabel()
    PlaceBox()
    if moved then ContextMoved() end
end

-- Edit Mode's writer, on the placed context's keys. While the starting place
-- stands in for an anchor Placement cannot use, the mover works on the
-- screen, so a moved position detaches the box and the starting place handed
-- back unchanged keeps the attachment. It places the box without resolving
-- again, so the box stays where it was dropped. A position measured under
-- another profile's settings is thrown away and the box placed fresh.
local function SetPosition(pos)
    local db = HX.pb.db
    if db ~= placedDB then return HX.ApplyPosition() end
    local keys = HX.POSITION_KEYS[placedContext]
    local _, _, fallback = Placement(db)
    if Rules.MoverDetaches(fallback, pos, HX.DEFAULT_POSITION) then
        db[keys.kind], db[keys.parent] = "UIPARENT", nil
    elseif fallback then
        return PlaceBox()
    end
    local p = db[keys.pos]
    p.AnchorFrom, p.AnchorTo = pos.AnchorFrom, pos.AnchorTo
    p.XOffset, p.YOffset = pos.XOffset, pos.YOffset
    PlaceBox()
end

local function Restyle(db)
    local s = HX.style
    s.size, s.spacing = db.HealerExtIconSize, db.HealerExtSpacing
    s.grow = GROW[db.HealerExtGrowth] or GROW.RIGHT
    s.fontName, s.outline, s.fontSize = db.FontFace, db.FontOutline, db.HealerExtTextSize
    s.showText = db.HealerExtShowText == true
    s.colors.external = db.CategoryColors == true and db.ColorExternal or BLACK
    HX.box:SetSize(s.size, s.size)
end

-- Icon i sits i - 1 steps from the grow direction's corner.
local function Layout(cells, count, parent)
    local s = HX.style
    local g, step = s.grow, s.size + s.spacing
    for i = 1, count do
        local c = cells[i]
        c:ClearAllPoints()
        c:SetPoint(g.corner, parent, g.corner, g.dx * (i - 1) * step, g.dy * (i - 1) * step)
        pcall(Cell.Seat, c)
    end
end

local function Show()
    local box = HX.box
    if not box then return end
    HX.live:SetShown(not HX.previewing)
    if HX.sampleLayer then HX.sampleLayer:SetShown(HX.previewing == true) end
    box:SetShown(HX.on == true and (HX.bound == true or HX.previewing == true))
end

-- Registering again would cancel a drag in progress.
local function Register()
    if HX.registered then return end
    KE.EditMode:RegisterElement({
        key = EDIT_MODE_KEY,
        displayName = HX.EditModeLabel(),
        frame = HX.box,
        module = HX.pb,
        getPosition = function() return (Placement(HX.pb.db)) end,
        setPosition = SetPosition,
        getParentFrame = function()
            local _, config = Placement(HX.pb.db)
            return KE:ResolveAnchorFrame(config.anchorFrameType, config.ParentFrame)
        end,
        guiPath = "PartyBuffs",
        guiTab = "PartyBuffsHealerExternals",
    })
    HX.registered = true
end

local function Unregister()
    if not HX.registered then return end
    KE.EditMode:UnregisterElement(EDIT_MODE_KEY)
    HX.registered = nil
end

---------------------------------------------------------------------------------
-- Binding
---------------------------------------------------------------------------------
-- No trigger registered, every sensor parked, the host hidden.
local function Release()
    if HX.st then Track.Unbind(HX.st) end
    if HX.sensorHost then HX.sensorHost:Hide() end
    HX.bound = false
end

-- Out of a party with the box on, and with the box off: nobody is watched or
-- inspected for it. Called again before a resolve, it makes no new tables.
local function Forget()
    Release()
    HX.rosterPending = false
    if HX.forgotten then return end
    local listed = #HX.members > 0
    HX.members, HX.records, HX.byToken, HX.guids = {}, {}, {}, {}
    HX.forgotten = true
    -- The spec module keeps the list it was last handed; the rows' list
    -- alone takes the box's healers off it.
    if listed and HX.pb and HX.pb.active then HX.pb:SyncMembers() end
end

-- While the module's roster settle runs a token may name someone else.
local function Settling()
    return HX.pb._rosterTimer ~= nil
end

local function On()
    return HX.on == true and HX.st ~= nil and Rules.On(HX.pb.db, HX.active, HX.pb.inRaid)
end

-- A refused call is issued again at the next drain; the build queue makes the
-- missing sensors, one per frame.
local function Bind()
    local st = HX.st
    HX.sensorHost:Show()
    if not Track.ApplyGroup(st, HX.units, HX.entries, HX.style) then Debug("a sensor call was refused") end
    if Track.Missing(st) then HX.pb:Enqueue(HX.QUEUE_KEY) end
    Layout(st.cells, #HX.entries, HX.live)
    HX.bound = true
end

-- A hidden GUID keeps the record last read for the same token, as a party
-- frame row does; a roster change or a closed gate clears it first.
local function Kept(token)
    local m = HX.byToken[token]
    if m and m.unit == token then return m end
    return nil
end

-- The units the cells watch, in token order: every one once a cell watches
-- them all, else each owner's.
local function WatchedUnits(units, entries)
    local want = {}
    for _, e in ipairs(entries) do
        if not e.units then return units end
        want[e.units[1]] = true
    end
    local out = {}
    for _, token in ipairs(units) do
        if want[token] then out[#out + 1] = token end
    end
    return out
end

-- Runs at every drain. A roster change is decided here, at the first drain
-- after the settle: the counts stay only for the same members.
function HX.Resolve()
    if not On() then
        Forget()
        Show()
        return
    end
    if Settling() then return end
    local units = PotRules.Tokens(true, UnitExists)
    local party, members, records, byToken = {}, {}, {}, {}
    local moved
    for _, token in ipairs(units) do
        local m = Spec.Member(token) or Kept(token)
        if m then
            local before = m.spec
            Spec.Resolve(m)
            if m.isPlayer then Spec.ReadSelf(m) end
            if m.spec ~= before then
                moved = moved or {}
                moved[#moved + 1] = m
            end
            records[m], byToken[token] = true, m
            -- members is the box's inspect list, and you are never inspected.
            if not m.isPlayer and Rules.Candidate(m.class, m.role) then members[#members + 1] = m end
            party[#party + 1] = {
                token = token, guid = m.guid, spec = m.spec, class = m.class, talents = m.talents,
            }
        end
    end
    HX.members, HX.records, HX.byToken = members, records, byToken
    HX.forgotten = false
    HX.pb:SyncMembers()
    local sources, guids = Rules.Sources(party, HX.pb.db), {}
    for i, source in ipairs(sources) do guids[i] = source.member.guid end
    local entries = Rules.Order(sources)
    for _, e in ipairs(entries) do e.texture = C_Spell.GetSpellTexture(e.show or e.id) end
    if HX.rosterPending and not Rules.KeepOnRoster(HX.guids, guids, issecretvalue) then Track.Reset(HX.st) end
    HX.rosterPending, HX.guids = false, guids
    HX.units, HX.entries = WatchedUnits(units, entries), entries
    Debug("units %d sources %d icons %d", #HX.units, #guids, #entries)
    if #entries > 0 then Bind() else Release() end
    HX.ApplyPosition()
    Show()
    -- Spec.Resolve announces no change, so the party frame rows showing a
    -- record whose spec moved here are rebuilt, as a change rebuilds them.
    -- Their binds find the spec unmoved and call nothing back.
    if moved then
        for _, m in ipairs(moved) do HX.pb:RebindMember(m) end
        if HX.pb.previewing then HX.pb:ShowPreview() end
    end
end

-- Reads wait and nobody is inspected for the box until the settle's drain.
function HX.OnRoster()
    if not (HX.on and HX.active and HX.st) then return end
    HX.rosterPending = true
    HX.members, HX.byToken = {}, {}
    Track.Hold(HX.st, ROSTER_HOLD)
end

-- Off, the switch has already released the slot and hidden the box.
function HX.OnRelease()
    if not HX.on then return end
    HX.Resolve()
end

function HX.OnMemberChanged(m)
    if HX.records[m] then HX.Resolve() end
end

-- The build queue's call for HX.QUEUE_KEY. Returns true when nothing is left
-- to build; a build refused, or skipped because the aura container code
-- cannot load, waits for the drain.
function HX.BuildNext()
    local st = HX.st
    if not (HX.bound and On()) or Settling() then return true end
    if not Track.Missing(st) then return true end
    if not KE:AuraContainersAvailable() then
        Debug("aura containers unavailable")
        return true
    end
    if not Track.BuildNext(st) then return true end
    Bind()
    return not Track.Missing(st)
end

---------------------------------------------------------------------------------
-- Preview
---------------------------------------------------------------------------------
local function ForgetSamples()
    for i, c in ipairs(HX.sampleCells) do
        local t = HX.sampleTrackers[i]
        if t then
            Track.Forget(t)
            HX.sampleTrackers[i] = nil
        end
        c:Hide()
    end
end

-- Plain sample icons; the counting one starts again when it runs out. The
-- preview is redrawn on every roster, resolve and settings change, so a
-- sample keeps its count while its length is unchanged.
local function DrawSamples()
    HX.sampleLayer = HX.sampleLayer or NewLayer(HX.box)
    local spells = KE.PartyCooldownsData.SPELLS
    local n = Track.Now()
    for i, sample in ipairs(SAMPLES) do
        local c = HX.sampleCells[i]
        if not c then
            c = Cell.New(HX.sampleLayer)
            HX.sampleCells[i] = c
        end
        local spell = spells[sample.id]
        local e = {
            id = sample.id, kind = spell.kind, cd = Rules.ClampSeconds(spell.cd),
            texture = C_Spell.GetSpellTexture(sample.id),
        }
        Cell.Dress(c, HX.style, e)
        local t = HX.sampleTrackers[i]
        if not (t and t.cd == e.cd) then
            if t then Track.Forget(t) end
            t = CDRules.NewTracker(e.cd, false)
            t.cell = c
            if sample.left then
                t.loop = sample.left
                CDRules.StartLoop(t, n)
            else
                CDRules.Clear(t, n)
            end
            Track.Watch(t)
            HX.sampleTrackers[i] = t
        end
        Track.Push(t, n)
        c:Show()
    end
    Layout(HX.sampleCells, #SAMPLES, HX.sampleLayer)
end

function HX.ShowPreview()
    if not (HX.on and HX.box) then return end
    HX.previewing = true
    DrawSamples()
    HX.ApplyPosition()
    Show()
end

-- A preview may have placed the box at the page's view. Hiding the whole
-- interface passes keepPlace: it hides the drawing only, and the show that
-- follows places the box, so the Revert snapshot is not retaken twice.
function HX.HidePreview(keepPlace)
    if not HX.previewing then return end
    HX.previewing = false
    ForgetSamples()
    if not keepPlace then HX.ApplyPosition() end
    Show()
end

---------------------------------------------------------------------------------
-- Lifecycle, driven by the Party Cooldowns module
---------------------------------------------------------------------------------
-- Off: nothing bound, inspected or drawn, and no mover. Frames already made
-- stay hidden; a queued build finds the box off and ends.
local function TurnOff()
    HX.on = false
    CancelPlacement()
    Forget()
    ForgetSamples()
    HX.previewing = false
    Unregister()
    if HX.box then HX.box:Hide() end
end

function HX.Enable(pb)
    HX.pb = pb
end

function HX.Disable()
    HX.active = false
    TurnOff()
end

-- Binds nothing: every caller is followed by the module's drain, which
-- resolves, and a settings change by its preview redraw.
function HX.ApplySettings()
    local pb = HX.pb
    if not pb then return end
    local db = pb.db
    if db.HealerExternals ~= true then return TurnOff() end
    HX.on = true
    MakeBox()
    if HX.active then MakeSlot() end
    Restyle(db)
    Register()
    HX.ApplyPosition()
    Show()
end

function HX.Activate()
    HX.active = true
    HX.ApplySettings()
end

function HX.Deactivate()
    HX.active = false
    Forget()
    Show()
end
