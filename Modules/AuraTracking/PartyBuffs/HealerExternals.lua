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
-- The gap between the box and Healer Mana in the stack: both draw their
-- borders inside, so 1 leaves one empty pixel between the border lines.
HX.STACK_GAP = 1
-- Whether the box stands on Healer Mana's spot with Healer Mana under it.
HX.stacked = false
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
-- Preview icons: left is a sample's seconds to go; one without is ready.
-- Six, so a row of four or five shows its wrap.
local SAMPLES = {
    { id = 33206, left = 122 }, { id = 102342 }, { id = 97462 },
    { id = 6940 }, { id = 1022 }, { id = 51052 },
}

local placement = {}
-- The grid as the box was last placed: the corner icon 1 sits in, the side a
-- new row or column starts on, and the style it was laid out with. Layout
-- reads only these, so icons drawn between placements match the box. Step 0
-- until the first placement lays the icons out.
local layout = { corner = "TOPLEFT", grow = "RIGHT", perRow = 1, step = 0, wrapUp = false, wrapLeft = false }
-- The box's size and Edit Mode insets, as last applied.
local shape = { w = 0, h = 0, left = 0, right = 0, top = 0, bottom = 0 }
-- Defined further down; placing the box runs them.
local Relayout, Measure, ChainCanMove

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
    return Rules.PositionTable(db, keys.pos), placement, false
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

local stackPos = { AnchorFrom = "TOPLEFT", AnchorTo = "TOPLEFT", XOffset = 0, YOffset = 0 }
local stackConfig = { anchorFrameType = "SELECTFRAME" }

-- In the stack the box's top corner sits on Healer Mana's spot: the left one,
-- or the right one when the icons grow left.
local function StackPlacement(db)
    local corner = db.HealerExtGrowth == "LEFT" and "TOPRIGHT" or "TOPLEFT"
    stackPos.AnchorFrom, stackPos.AnchorTo = corner, corner
    stackConfig.ParentFrame, stackConfig.Strata = HX.stackSpot:GetName(), db.HealerExtStrata
    return stackPos, stackConfig
end

-- The one place the box is sized, placed and its icons laid out, behind the
-- gate for the whole stack, so a refusal leaves all of it as it was. The size
-- is set before the placement, so the pixel snap measures the new size.
local function PlaceBox()
    local s = HX.style
    if not (HX.box and s.size) or not ChainCanMove() then return end
    local db, stacked = HX.pb.db, HX.stacked
    local pos, config
    if stacked then
        pos, config = StackPlacement(db)
    else
        pos, config = Placement(db)
    end
    local grow, perRow, step = s.grow, s.perRow, s.size + s.spacing
    local from = type(pos) == "table" and pos.AnchorFrom or nil
    local wrapUp, wrapLeft = Rules.WrapSide(stacked, from, grow)
    local w, h, left, right, top, bottom = Measure(stacked, grow, perRow, step, wrapUp, wrapLeft)
    HX.box:SetSize(w, h)
    KE:ApplyFramePosition(HX.box, pos, config)
    if grow ~= layout.grow or perRow ~= layout.perRow or step ~= layout.step
        or wrapUp ~= layout.wrapUp or wrapLeft ~= layout.wrapLeft then
        layout.corner, layout.grow, layout.perRow, layout.step = Rules.Corner(grow), grow, perRow, step
        layout.wrapUp, layout.wrapLeft = wrapUp, wrapLeft
        Relayout()
    end
    if w == shape.w and h == shape.h and left == shape.left and right == shape.right
        and top == shape.top and bottom == shape.bottom then return end
    shape.w, shape.h, shape.left, shape.right, shape.top, shape.bottom = w, h, left, right, top, bottom
    -- The Edit Mode boxes read their size and insets only when they refresh.
    if KE.EditMode then KE.EditMode:RefreshLiveState() end
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

---------------------------------------------------------------------------------
-- The stack with Healer Mana
---------------------------------------------------------------------------------
local function HealerMana() return KitnEssentials:GetModule("HealerMana", true) end

-- Whether the box's Default position is still its default attachment, read
-- against the defaults table so that no saved value is ever rewritten.
function HX.Untouched(db)
    local defaults = KE.db and KE.db.defaults and KE.db.defaults.profile
    return Rules.DefaultAttachment(db, defaults and defaults.PartyBuffs)
end

local function Free(frame) return frame == nil or KE:CanReanchorNow(frame) end

-- The box, Healer Mana and its spot anchor to one another while they stack,
-- so a placement of any of them waits until all three may move: one moved
-- alone would anchor to a frame anchored to it.
ChainCanMove = function()
    local HM = HealerMana()
    return Free(HX.box) and (HM == nil or (Free(HM.containerFrame) and Free(HM.spot)))
end
HX.ChainCanMove = ChainCanMove

-- Whether the box should stand on Healer Mana's spot. It moves and makes
-- nothing. A spot that depends on the box, Healer Mana anchored to it by
-- hand, is refused.
local function StackWanted(db, context)
    local shown = HX.on == true and (HX.bound == true or HX.previewing == true)
    if not Rules.Stacks(db.HealerExtHealerManaBelow, HX.Untouched(db), context, shown) then return false end
    local HM = HealerMana()
    if not (HM and HM.StackReady and HM:StackReady()) then return false end
    local spot = HM.spot
    return spot == nil or KE:ResolveSelectFrame(spot:GetName(), HX.box) ~= nil
end

-- Makes and places the spot, so it runs only after the gate. Nil when the
-- spot would depend on the box, which Healer Mana checks before making it,
-- or when one made earlier has come to depend on it.
local function StackSpot()
    local HM = HealerMana()
    local spot = HM and HM.StackSpot and HM:StackSpot(HX.box)
    if not spot or KE:ResolveSelectFrame(spot:GetName(), HX.box) == nil then return nil end
    return spot
end

-- Healer Mana goes back to its own position before the box is placed
-- against it again.
local function Unstack()
    if not HX.stacked then return end
    HX.stacked, HX.stackSpot, HX.stackRight = false, nil, nil
    local HM = HealerMana()
    if HM and HM.FollowBox then HM:FollowBox(nil) end
end

local releasePending = false

-- Off, the box no longer places itself, so the stack ends here. Refused in
-- combat it stays stacked until combat ends; turned on again by then, the
-- box's own placement ends it.
local function ReleaseStack()
    if not HX.stacked or HX.on then return end
    if ChainCanMove() then return Unstack() end
    if releasePending then return end
    releasePending = true
    KE:RunAfterCombat(function()
        releasePending = false
        ReleaseStack()
    end)
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
    if not ChainCanMove() then return DeferPlacement(true) end
    local EM = KE.EditMode
    if EM and EM:IsAnyDragInFlight() then return DeferPlacement(false) end
    CancelPlacement()
    local db = HX.pb.db
    local context = ResolveContext(db)
    local spot = StackWanted(db, context) and StackSpot() or nil
    local moved = context ~= placedContext or db ~= placedDB
    placedContext, placedSplit, placedDB = context, db.UseHealerExtPosition == true, db
    Relabel()
    if spot then
        local right = db.HealerExtGrowth == "LEFT"
        local follow = not HX.stacked or HX.stackRight ~= right
        HX.stacked, HX.stackSpot, HX.stackRight = true, spot, right
        PlaceBox()
        local HM = HealerMana()
        if follow and HM and HM.FollowBox then HM:FollowBox(HX.box, right, HX.STACK_GAP) end
    else
        Unstack()
        PlaceBox()
    end
    if moved then ContextMoved() end
end

-- Edit Mode's writer, on the placed context's keys. While the starting place
-- stands in for an anchor Placement cannot use, the mover works on the
-- screen, so a moved position detaches the box and the starting place handed
-- back unchanged keeps the attachment. It never resolves the context, so the
-- box stays where it was dropped.
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
    local p = Rules.PositionTable(db, keys.pos)
    p.AnchorFrom, p.AnchorTo = pos.AnchorFrom, pos.AnchorTo
    p.XOffset, p.YOffset = pos.XOffset, pos.YOffset
    PlaceBox()
end

local function Restyle(db)
    local s = HX.style
    s.size, s.spacing = db.HealerExtIconSize, db.HealerExtSpacing
    s.grow, s.perRow = db.HealerExtGrowth, Rules.PerRow(db.HealerExtIconsPerRow)
    s.fontName, s.outline, s.fontSize = db.FontFace, db.FontOutline, db.HealerExtTextSize
    s.showText = db.HealerExtShowText == true
    s.colors.external = db.CategoryColors == true and db.ColorExternal or BLACK
end

-- Icon i sits at its grid place from icon 1, which fills the layout's corner.
local function Layout(cells, count, parent)
    local corner = layout.corner
    for i = 1, count do
        local c = cells[i]
        local x, y = Rules.GridPlace(i, layout.perRow, layout.grow, layout.step, layout.wrapUp, layout.wrapLeft)
        c:ClearAllPoints()
        c:SetPoint(corner, parent, corner, x, y)
        pcall(Cell.Seat, c)
    end
end

Relayout = function()
    if HX.bound and HX.st then Layout(HX.st.cells, #HX.entries, HX.live) end
    if HX.previewing and HX.sampleLayer then Layout(HX.sampleCells, #SAMPLES, HX.sampleLayer) end
end

local function OverlayInset()
    return shape.left, shape.right, shape.top, shape.bottom
end

local function Count()
    if HX.previewing then return #SAMPLES end
    if HX.bound and HX.entries then return #HX.entries end
    return 0
end

-- A free box is icon 1 alone, sized as one icon, so a wrap
-- never moves icon 1; the KE Edit Mode box is inset onto the grid and the
-- drag still measures the box itself. A stacked box is the grid, so Healer
-- Mana can hang under its bottom edge; its corner pin keeps its edges whole.
Measure = function(stacked, grow, perRow, step, wrapUp, wrapLeft)
    local size = HX.style.size
    local cols, rows = Rules.GridShape(Count(), perRow, grow)
    if stacked then return (cols - 1) * step + size, (rows - 1) * step + size, 0, 0, 0, 0 end
    return size, size, Rules.GridInset(cols, rows, step, Rules.Extends(grow, wrapUp, wrapLeft))
end

-- The box's own size and insets back Healer Mana's Edit Mode box over the
-- stack.
function HX.StackInset(spotW)
    return Rules.StackInset(shape.w, shape.h, spotW, HX.STACK_GAP, HX.stackRight == true)
end

-- Shows and hides only: whoever changes what the box holds places it first.
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
        getOverlayInset = OverlayInset,
        getParentFrame = function()
            local _, config = Placement(HX.pb.db)
            return KE:ResolveAnchorFrame(config.anchorFrameType, config.ParentFrame)
        end,
        guiPath = "PartyBuffs",
        guiTab = "PartyBuffsHealerExternals",
        -- In the stack the box moves with Healer Mana's position.
        isEligible = function() return not HX.stacked end,
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
    if not Track.ApplyGroup(st, HX.units, HX.entries, HX.style) then
        Debug("a sensor call was refused or an icon was not drawn")
    end
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
        HX.ApplyPosition()
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
-- interface passes keepPlace: the drawing stops but HX.previewing stays set,
-- so the interface showing again, or the preview's end if that comes first,
-- places the box once.
function HX.HidePreview(keepPlace)
    if not HX.previewing then return end
    ForgetSamples()
    if keepPlace then return end
    HX.previewing = false
    HX.ApplyPosition()
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
    ReleaseStack()
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
    HX.ApplyPosition()
    Show()
end
