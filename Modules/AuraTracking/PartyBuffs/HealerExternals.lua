-- ╔══════════════════════════════════════════════════════════╗
-- ║  HealerExternals.lua                                     ║
-- ║  Purpose: each party healer's external cooldown as one   ║
-- ║           icon in a movable box.                         ║
-- ╚══════════════════════════════════════════════════════════╝
--
-- One group slot of the party cooldowns pipeline: a cell per external, read
-- from one sensor per party member, so its buff landing on anyone starts the
-- count. The game names no caster, so another player's cast of the same
-- spell starts it too.

---@class KE
local KE = select(2, ...)

local _G = _G
local C_Spell = C_Spell
local CreateFrame = CreateFrame
local UIParent = UIParent
local UnitExists = UnitExists
local ipairs = ipairs
local issecretvalue = issecretvalue
local string_format = string.format
local type = type

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
-- The cooldown icon with no active state laid over it.
HX.VIEW = {
    New = Cell.New, Dress = Cell.Dress, Write = Cell.Write, Range = Cell.Range, Clear = Cell.Clear,
    overlay = false,
}

-- Reads wait out a roster change, longer than the module's 0.5 s settle.
local ROSTER_HOLD = 1
local BLACK = { 0, 0, 0, 1 }
local SCREEN = { anchorFrameType = "UIPARENT", Strata = "MEDIUM" }
local EDIT_MODE_KEY = "HealerExternals"
-- Per grow direction: the box corner the first icon sits in, and the step.
local GROW = {
    RIGHT = { corner = "TOPLEFT",    dx = 1,  dy = 0 },
    LEFT  = { corner = "TOPRIGHT",   dx = -1, dy = 0 },
    DOWN  = { corner = "TOPLEFT",    dx = 0,  dy = -1 },
    UP    = { corner = "BOTTOMLEFT", dx = 0,  dy = 1 },
}
-- Preview icons: left is a sample's seconds to go; one without is ready.
local SAMPLES = { { id = 33206, left = 122 }, { id = 102342 } }

local placement = { Strata = "MEDIUM" }

local function Debug(fmt, ...)
    if DEBUG_HX then KE:Print("Healer Externals: " .. string_format(fmt, ...)) end
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
    HX.box:SetFrameStrata("MEDIUM")
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

-- An attached box whose anchor is unnamed (the Frame field cleared), does not
-- exist (Healer Mana off since login), or is refused by KE:IsUnsafeAnchor (not
-- a frame, the box itself, or a frame that depends on it) takes its starting
-- place: the attached points against the screen would put it above the top
-- edge. The third return says the starting place is in use.
local function Placement(db)
    local kind, name = db.HealerExtAnchorFrameType, db.HealerExtParentFrame
    if kind == "SELECTFRAME" then
        if type(name) ~= "string" then return HX.DEFAULT_POSITION, SCREEN, true end
        local frame = _G[name]
        local missing = not issecretvalue(frame) and frame == nil
        if missing or KE:IsUnsafeAnchor(HX.box, frame) then return HX.DEFAULT_POSITION, SCREEN, true end
    end
    placement.anchorFrameType, placement.ParentFrame = kind, name
    return db.HealerExtPosition, placement, false
end

function HX.ApplyPosition()
    if not HX.box then return end
    local pos, config = Placement(HX.pb.db)
    KE:ApplyFramePosition(HX.box, pos, config)
end

-- Edit Mode's writer. While the starting place stands in for an anchor that
-- is missing or refused the mover works on the screen, so a moved position
-- detaches the box and the starting place handed back unchanged keeps the
-- attachment.
local function SetPosition(pos)
    local db = HX.pb.db
    local _, _, fallback = Placement(db)
    if Rules.MoverDetaches(fallback, pos, HX.DEFAULT_POSITION) then
        db.HealerExtAnchorFrameType, db.HealerExtParentFrame = "UIPARENT", nil
    elseif fallback then
        return HX.ApplyPosition()
    end
    local p = db.HealerExtPosition
    p.AnchorFrom, p.AnchorTo = pos.AnchorFrom, pos.AnchorTo
    p.XOffset, p.YOffset = pos.XOffset, pos.YOffset
    HX.ApplyPosition()
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
        displayName = "Healer Externals",
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

-- Runs at every drain. A roster change is decided here, at the first drain
-- after the settle: the counts stay only for the same healers.
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
        local m = token ~= "player" and (Spec.Member(token) or Kept(token))
        if m then
            local before = m.spec
            Spec.Resolve(m)
            if m.spec ~= before then
                moved = moved or {}
                moved[#moved + 1] = m
            end
            records[m], byToken[token] = true, m
            if Rules.Candidate(m.class, m.role) then members[#members + 1] = m end
            party[#party + 1] = { token = token, guid = m.guid, spec = m.spec }
        end
    end
    HX.members, HX.records, HX.byToken = members, records, byToken
    HX.forgotten = false
    HX.pb:SyncMembers()
    local entries, guids = {}, {}
    for i, healer in ipairs(Rules.Healers(party, HX.pb.db)) do
        guids[i] = healer.member.guid
        for _, e in ipairs(healer.entries) do
            e.texture = C_Spell.GetSpellTexture(e.id)
            -- The group slot keeps a count with its healer when the list shifts.
            e.owner = healer.member.guid
            entries[#entries + 1] = e
        end
    end
    if HX.rosterPending and not Rules.KeepOnRoster(HX.guids, guids, issecretvalue) then Track.Reset(HX.st) end
    HX.rosterPending, HX.guids = false, guids
    HX.units, HX.entries = units, entries
    Debug("units %d healers %d icons %d", #units, #guids, #entries)
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

function HX.HidePreview()
    if not HX.previewing then return end
    HX.previewing = false
    ForgetSamples()
    Show()
end

---------------------------------------------------------------------------------
-- Lifecycle, driven by the Party Cooldowns module
---------------------------------------------------------------------------------
-- Off: nothing bound, inspected or drawn, and no mover. Frames already made
-- stay hidden; a queued build finds the box off and ends.
local function TurnOff()
    HX.on = false
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
