-- ╔══════════════════════════════════════════════════════════╗
-- ║  KickTrackerPlates.lua                                   ║
-- ║  Module: Interrupt Tracker                               ║
-- ║  Purpose: kick icons on enemy nameplates, in one row per ║
-- ║           plate beside its health bar.                   ║
-- ╚══════════════════════════════════════════════════════════╝
-- Plain values drive every Lua decision. Meter totals and raid marker
-- indexes only ever reach SetMinMaxValues and SetValue on hidden status bars
-- (gates) whose fill edges move clips over the icons; nothing is read back
-- from a gate, clip, icon or plate, and no geometry is measured. Each element
-- of a row hangs from the end of the one before it: a pair of bars, a
-- standard and a reverse fill fed the same values, ends one slot on while the
-- element shows and where it starts once it is hidden, so the row closes up.

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@type KickTracker
local KT = KitnEssentials:GetModule("KickTracker")

local CreateFrame = CreateFrame
local UIParent = UIParent
local C_NamePlate = C_NamePlate
local C_Timer = C_Timer
local C_Spell = C_Spell
local C_ClassColor = C_ClassColor
local GetTime = GetTime
local UnitExists = UnitExists
local UnitIsUnit = UnitIsUnit
local UnitCanAttack = UnitCanAttack
local UnitClass = UnitClass
local GetSpecializationInfoForSpecID = GetSpecializationInfoForSpecID
local issecretvalue = issecretvalue
local pcall = pcall
local pairs = pairs
local type = type
local wipe = wipe
local table_remove = table.remove
local table_sort = table.sort

local WHITE = "Interface\\Buttons\\WHITE8X8"
local ICON_CROP = 0.08
local LIFT_LEVEL = 10
local PLATE_TOP = 1000    -- frame levels above the nameplate in the off position
local GATE_SPAN = 100     -- counts up to this many move a gate's fill a whole span
local SAMPLE_CD = 30
local GHOST_CELLS = 4     -- a ghost's cells; the player is never one
local CELL_LEVELS = 4     -- frame levels one ghost cell takes
local BASE_SLACK = 0.1    -- a read this much before a kick still serves as its baseline
local READY_SLACK = 0.05  -- a relayout this long after a cooldown's end finds it over
local MAX_PLATES = 40

local PLATE_UNITS = {}
for i = 1, MAX_PLATES do PLATE_UNITS[i] = "nameplate" .. i end

local P = {
    live = {},     -- [member GUID] = that kicker's live icon
    rows = {},     -- [nameplate token] = { head, list }
    waiting = {},  -- elements whose plate went, waiting for it to come back
    pending = {},  -- [member GUID] = the placement waiting its frame: { seq, open, unit, stamp, at, base, gen }
    epoch = {},    -- [nameplate token] = moved each time that plate goes
    dirty = {},    -- [nameplate token] = true while its row waits for the next layout pass
    free = { live = {}, row = {} },
    samples = {},
    gen = 0,       -- moved by every reset; one-frame callbacks check it
}
KT.plateState = P
P.ghosts = {}       -- live ghosts, oldest first
P.free.ghost = {}
P.packet = { units = {}, before = {}, after = {} }  -- the last update's gate totals, until the next read
P.packetT = -1
P.readySeq = 0      -- the token of the one ready timer (KT:WakeAt); P.readyAt is its plain time

-- A plate's lifetime: a kick seen on it carries this, so a placement whose
-- plate went (and whose token may now be another mob's) takes nothing.
function KT:PlateStamp(unit)
    return P.epoch[unit] or 0
end

---------------------------------------------------------------------------------
-- Units and hosts
---------------------------------------------------------------------------------
-- Only an answer read plainly as friendly refuses (KT.RefusesInterruptUnit).
local function IsHostile(unit)
    local ok, attack = pcall(UnitCanAttack, "player", unit)
    return not KT.RefusesInterruptUnit(ok, attack, issecretvalue(attack))
end

-- Plain true only: a secret or failed answer is no match.
local function IsTarget(unit)
    local ok, same = pcall(UnitIsUnit, "target", unit)
    return ok and not issecretvalue(same) and same == true
end

local function TargetPlate()
    if not UnitExists("target") then return nil end
    for i = 1, MAX_PLATES do
        local unit = PLATE_UNITS[i]
        if C_NamePlate.GetNamePlateForUnit(unit) and IsTarget(unit) then return unit end
    end
    return nil
end

-- Called only from the layout pass, which runs in a one-frame callback, never
-- from an event's own stack.
local function AnchorOf(unit)
    local plate = C_NamePlate.GetNamePlateForUnit(unit)
    if not plate then return nil end
    return KE:ResolvePlateAnchor(plate)
end

-- On, the lift draws over every nameplate. Off, the element joins the
-- nameplate itself, so a plate that covers it hides it.
local function HostOf(unit)
    if KT.db.PlateAboveOverlap ~= false then return P.lift, "HIGH", LIFT_LEVEL end
    local plate = C_NamePlate.GetNamePlateForUnit(unit)
    if not plate then return nil end
    return plate, plate:GetFrameStrata(), plate:GetFrameLevel() + PLATE_TOP
end

-- One empty 1x1 frame with no script.
local function EnsureLift()
    if P.lift then return end
    local lift = CreateFrame("Frame", nil, UIParent)
    lift:SetSize(1, 1)
    lift:SetPoint("CENTER")
    lift:SetFrameStrata("HIGH")
    lift:SetFrameLevel(LIFT_LEVEL)
    lift:EnableMouse(false)
    P.lift = lift
end

-- Read on activation, settings and UI_SCALE_CHANGED, never in a nameplate or
-- combat event.
local function ReadScale()
    P.uiScale = UIParent:GetEffectiveScale()
end

-- Sizes and gaps in UIParent units on any plate.
local function Scaled(frame)
    frame:SetIgnoreParentScale(true)
    frame:SetScale(P.uiScale or 1)
end

local function Level(frame, strata, level)
    frame:SetFrameStrata(strata)
    frame:SetFrameLevel(level)
end

---------------------------------------------------------------------------------
-- Gates and step pairs
---------------------------------------------------------------------------------
-- A status bar drawing nothing, its fill unsnapped so the edge sits exactly
-- where the values put it. hidden: alpha 0, for a gate no icon descends from.
local function NewGate(parent, hidden)
    local gate = CreateFrame("StatusBar", nil, parent)
    gate:EnableMouse(false)
    gate:SetStatusBarTexture(WHITE)
    local fill = gate:GetStatusBarTexture()
    fill:SetVertexColor(0, 0, 0, 0)
    if fill.SetSnapToPixelGrid then
        fill:SetSnapToPixelGrid(false)
        fill:SetTexelSnappingBias(0)
    end
    if hidden then gate:SetAlpha(0) end
    gate:SetMinMaxValues(0, 1)
    gate:SetValue(1)
    return gate, fill
end

local function NewClip(parent)
    local clip = CreateFrame("Frame", nil, parent)
    clip:SetClipsChildren(true)
    clip:EnableMouse(false)
    return clip
end

-- How far a gate reaches past its cell on every side: the countdown can
-- spill past the icon by about twice its font size.
local function Margin()
    return 2 * KT.db.PlateTimerSize + 4
end

-- GATE_SPAN cells, each with its margins, wide; its right end just past the
-- cell's margin, so a count short by one leaves the cell outside the clip.
local function SizeGate(gate, about, cw)
    local m = Margin()
    gate:SetSize(GATE_SPAN * (cw + 2 * m + 4), cw + 2 * m)
    gate:ClearAllPoints()
    gate:SetPoint("RIGHT", about, "RIGHT", m + 2, 0)
end

-- Open while the fill is whole: the gate's left edge to the fill's right
-- edge, hung again after every feed.
local function HangWhole(clip, fill, gate)
    clip:ClearAllPoints()
    clip:SetPoint("TOPLEFT", gate, "TOPLEFT", 0, 0)
    clip:SetPoint("BOTTOMLEFT", gate, "BOTTOMLEFT", 0, 0)
    clip:SetPoint("TOPRIGHT", fill, "TOPRIGHT", 0, 0)
    clip:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT", 0, 0)
end

-- Whole from plain values: the element shows.
local function ResetWhole(gate, fill, clip)
    gate:SetMinMaxValues(0, 1)
    gate:SetValue(1)
    HangWhole(clip, fill, gate)
end

local function NewBar(parent, reverse)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:EnableMouse(false)
    if reverse then bar:SetFillStyle(Enum.StatusBarFillStyle.Reverse) end
    bar:SetStatusBarTexture(WHITE)
    local fill = bar:GetStatusBarTexture()
    fill:SetVertexColor(0, 0, 0, 0)
    if fill.SetSnapToPixelGrid then
        fill:SetSnapToPixelGrid(false)
        fill:SetTexelSnappingBias(0)
    end
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    return bar, fill
end

-- Two bars one pitch wide, edge to edge: the pair ends a pitch times
-- 1 + f(v1) - f(v2) on, f a bar's fill share of its range. Fed (base, cur)
-- with the values (base, cur), that is a pitch while the count held and
-- nothing once it rose; an empty range draws alike in both bars and cancels.
local function NewStep(parent)
    local std, stdFill = NewBar(parent, false)
    local rev, revFill = NewBar(parent, true)
    return { std = std, stdFill = stdFill, rev = rev, revFill = revFill }
end

local function SizeStep(pr, pitch, cw)
    pr.std:SetSize(pitch, cw)
    pr.rev:SetSize(pitch, cw)
end

-- From (from, fromPoint, offset) in the row's direction; returns the pair's
-- end, a fill and its point. The reverse bar leads leftward, so the first
-- bar's fill edge faces the second either way.
local function AnchorStep(pr, from, fromPoint, offset, leftward)
    local first, firstFill, second, secondFill
    if leftward then
        first, firstFill, second, secondFill = pr.rev, pr.revFill, pr.std, pr.stdFill
    else
        first, firstFill, second, secondFill = pr.std, pr.stdFill, pr.rev, pr.revFill
    end
    first:ClearAllPoints()
    second:ClearAllPoints()
    if leftward then
        first:SetPoint("RIGHT", from, fromPoint, offset, 0)
        second:SetPoint("RIGHT", firstFill, "LEFT", 0, 0)
        return secondFill, "RIGHT"
    end
    first:SetPoint("LEFT", from, fromPoint, offset, 0)
    second:SetPoint("LEFT", firstFill, "RIGHT", 0, 0)
    return secondFill, "LEFT"
end

local function FeedStep(pr, lo, hi, v1, v2, leftward)
    local first, second
    if leftward then first, second = pr.rev, pr.std else first, second = pr.std, pr.rev end
    first:SetMinMaxValues(lo, hi)
    first:SetValue(v1)
    second:SetMinMaxValues(lo, hi)
    second:SetValue(v2)
end

-- One pitch from plain values.
local function ResetStep(pr, leftward)
    FeedStep(pr, 0, 1, 0, 0, leftward)
end

local function ShowStep(pr, shown)
    pr.std:SetShown(shown)
    pr.rev:SetShown(shown)
end

-- Open where the fill falls short: the fill's right edge to the gate's right
-- end, so the clip opens only once the count rose.
local function HangShort(clip, fill, gate)
    clip:ClearAllPoints()
    clip:SetPoint("TOPLEFT", fill, "TOPRIGHT", 0, 0)
    clip:SetPoint("BOTTOMLEFT", fill, "BOTTOMRIGHT", 0, 0)
    clip:SetPoint("TOPRIGHT", gate, "TOPRIGHT", 0, 0)
    clip:SetPoint("BOTTOMRIGHT", gate, "BOTTOMRIGHT", 0, 0)
end

-- The count at placing as the value, the latest as the maximum: whole until
-- the count rose.
local function FeedWhole(gate, fill, clip, base, cur)
    gate:SetMinMaxValues(0, cur)
    gate:SetValue(base)
    HangWhole(clip, fill, gate)
end

-- A baseline from an older fight counts as 0: the counts restarted since.
local function Base(base, gen)
    if gen == KT.meterFight then return base end
    return 0
end

---------------------------------------------------------------------------------
-- Icons
---------------------------------------------------------------------------------
-- A plain frame, not a BackdropTemplate: a backdrop does arithmetic on a
-- width that is secret over a nameplate.
local function BuildIcon(parent)
    local icon = CreateFrame("Frame", nil, parent)
    icon:EnableMouse(false)
    icon.border = icon:CreateTexture(nil, "BACKGROUND")
    icon.border:SetAllPoints(icon)
    icon.border:SetColorTexture(0, 0, 0, 1)
    icon.art = icon:CreateTexture(nil, "ARTWORK")
    icon.art:SetTexCoord(ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP)
    icon.cd = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
    icon.cd:SetAllPoints(icon.art)
    icon.cd:SetDrawEdge(false)
    icon.cd:EnableMouse(false)
    return icon
end

local function StyleIcon(icon)
    local db = KT.db
    local px = KE:GetPixelSize()
    icon.art:ClearAllPoints()
    icon.art:SetPoint("TOPLEFT", icon, "TOPLEFT", px, -px)
    icon.art:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -px, px)
    icon.cd:SetDrawSwipe(db.PlateSwipe ~= false)
    icon.cd:SetHideCountdownNumbers(db.PlateShowTimer == false)
    KE:ApplyFontToText(icon.cd:GetCountdownFontString(), db.FontFace, db.PlateTimerSize, db.FontOutline)
end

-- The kick spell, or the spec or class icon; a spec or class not known
-- plainly falls back to the kick.
local function KickArt(member)
    local style = KT.db.PlateIconStyle
    if style == "spec" and type(member.specID) == "number" and member.specID > 0 then
        local ok, _, _, _, icon = pcall(GetSpecializationInfoForSpecID, member.specID)
        if ok and not issecretvalue(icon) and icon then return icon end
    elseif style == "class" and member.matchClass then
        return "Interface\\Icons\\ClassIcon_" .. member.matchClass
    end
    local data = member.interruptData
    local info = data and C_Spell.GetSpellInfo(data.id)
    return info and info.iconID or 134400
end

-- The class color only from a plain class; otherwise the border stays black.
local function PaintIcon(icon, member)
    icon.art:SetTexture(KickArt(member))
    local color = KT.db.PlateClassBorder ~= false and member.matchClass
        and C_ClassColor.GetClassColor(member.matchClass)
    if color then
        icon.border:SetColorTexture(color.r, color.g, color.b, 1)
    else
        icon.border:SetColorTexture(0, 0, 0, 1)
    end
end

local function PaintCooldown(icon, start, duration)
    if start and duration and duration > 0 then
        icon.cd:SetCooldown(start, duration)
    else
        icon.cd:Clear()
    end
end

---------------------------------------------------------------------------------
-- Live icons: one per kicker
---------------------------------------------------------------------------------
-- The icon fills the element, inside its count gate's clip; the step pair
-- carries the row past it.
local function BuildLive()
    local e = CreateFrame("Frame", nil, P.lift)
    e:EnableMouse(false)
    e:Hide()
    e.gate, e.fill = NewGate(e, true)
    e.clip = NewClip(e)
    e.icon = BuildIcon(e.clip)
    e.icon:SetAllPoints(e)
    e.step = NewStep(e)
    return e
end

local function StyleLive(e)
    local db = KT.db
    local cw = db.PlateIconSize
    e:SetSize(cw, cw)
    StyleIcon(e.icon)
    SizeGate(e.gate, e, cw)
    SizeStep(e.step, cw + db.PlateSpacing, cw)
end

-- The count gate and step pair fed as they last were, or whole while never
-- fed: then the icon shows and keeps one slot.
local function RefeedLive(e)
    local leftward = KT.db.PlateSide == "LEFT"
    if e.cCur ~= nil then
        local base = Base(e.cBase, e.cGen)
        FeedWhole(e.gate, e.fill, e.clip, base, e.cCur)
        FeedStep(e.step, base, e.cCur, base, e.cCur, leftward)
    else
        ResetWhole(e.gate, e.fill, e.clip)
        ResetStep(e.step, leftward)
    end
end

local function LevelLive(e, strata, level)
    Level(e, strata, level)
    Level(e.gate, strata, level)
    Level(e.step.std, strata, level)
    Level(e.step.rev, strata, level)
    Level(e.clip, strata, level + 1)
    Level(e.icon, strata, level + 2)
    Level(e.icon.cd, strata, level + 3)
end

local function AnchorLive(e, from, fromPoint, offset, leftward)
    e:ClearAllPoints()
    e:SetPoint(leftward and "RIGHT" or "LEFT", from, fromPoint, offset, 0)
    local endFill, endPoint = AnchorStep(e.step, from, fromPoint, offset, leftward)
    return endFill, endPoint, 0
end

-- Per element kind: frame levels, row placement, feeding again after a move.
local LEVEL = { live = LevelLive, sample = LevelLive }
local ANCHOR = { live = AnchorLive, sample = AnchorLive }
local REFEED = { live = RefeedLive, sample = RefeedLive }

-- On the unit's host, at its strata and level.
local function Attach(e, unit)
    local host, strata, level = HostOf(unit)
    if not host then return false end
    e:SetParent(host)
    Scaled(e)
    LEVEL[e.kind](e, strata, level)
    e.unit = unit
    e:Show()
    return true
end

-- Off any plate, under the lift.
local function Park(e)
    e:Hide()
    e:ClearAllPoints()
    e:SetParent(P.lift)
    e.unit = nil
end

-- Kinds that wait for their mob's plate to come back, and how each is released.
local WAITS = { live = true }
local RELEASE = {
    live = function(e) KT:ReleaseLive(e.guid) end,
    sample = Park,
}

---------------------------------------------------------------------------------
-- Ghosts: the reveal on a plate for a kick nobody was named for
---------------------------------------------------------------------------------
-- One slot, and inside it one cell per teammate who could have kicked: their
-- icon inside two clips. The reveal clip hangs where its gate's fill (their
-- total before the update, of their total after it as the maximum) falls
-- short, so it opens only where the total rose. The count clip
-- inside it closes once they interrupted again. Later cells draw
-- over earlier ones.
local function BuildGhost()
    local g = CreateFrame("Frame", nil, P.lift)
    g:EnableMouse(false)
    g:Hide()
    g.kind = "ghost"
    g.cells = {}
    g.used = 0
    g.seq = 0
    return g
end

local function BuildCell(g)
    local cell = {}
    cell.gate, cell.fill = NewGate(g, true)
    cell.clip = NewClip(g)
    cell.clip:Hide()
    cell.gateB, cell.fillB = NewGate(g, true)
    cell.clipB = NewClip(cell.clip)
    cell.icon = BuildIcon(cell.clipB)
    cell.icon:SetAllPoints(g)
    cell.stepA, cell.stepB = NewStep(g), NewStep(g)
    return cell
end

local function StyleGhost(g)
    local db = KT.db
    local cw = db.PlateIconSize
    local pitch = cw + db.PlateSpacing
    g:SetSize(cw, cw)
    for k = 1, #g.cells do
        local cell = g.cells[k]
        StyleIcon(cell.icon)
        SizeGate(cell.gate, g, cw)
        SizeGate(cell.gateB, g, cw)
        SizeStep(cell.stepA, pitch, cw)
        SizeStep(cell.stepB, pitch, cw)
    end
end

-- The reveal gate, the count gate and both step pairs. The first pair ends a
-- pitch on, or two once the total rose past its value before the update; the
-- second a pitch, or none once it rose past its value after it. Less two
-- pitches a cell, the chain is one pitch per cell that shows.
local function FeedCell(cell, leftward)
    cell.gate:SetMinMaxValues(0, cell.after)
    cell.gate:SetValue(cell.before)
    HangShort(cell.clip, cell.fill, cell.gate)
    local cur = (cell.cCur ~= nil) and cell.cCur or cell.after
    local floorA = Base(cell.before, cell.gen)
    FeedStep(cell.stepA, floorA, cur, cur, floorA, leftward)
    if cell.cCur ~= nil then
        local floorB = Base(cell.after, cell.gen)
        FeedWhole(cell.gateB, cell.fillB, cell.clipB, floorB, cell.cCur)
        FeedStep(cell.stepB, floorB, cell.cCur, floorB, cell.cCur, leftward)
    else
        ResetWhole(cell.gateB, cell.fillB, cell.clipB)
        ResetStep(cell.stepB, leftward)
    end
end

local function FeedGhost(g)
    local leftward = KT.db.PlateSide == "LEFT"
    for k = 1, g.used do FeedCell(g.cells[k], leftward) end
end

-- Each cell's art and border from its teammate as they are now: at placing,
-- and again on a roster change or a settings change.
local function PaintGhost(g)
    for k = 1, g.used do
        local cell = g.cells[k]
        local member = KT.partyMembers[cell.guid]
        if member then PaintIcon(cell.icon, member) end
    end
end

-- Out of use: closed from plain values, its totals and member dropped.
local function ParkCell(cell, leftward)
    cell.icon.cd:Clear()
    cell.gate:SetMinMaxValues(0, 1)
    cell.gate:SetValue(1)
    HangShort(cell.clip, cell.fill, cell.gate)
    ResetWhole(cell.gateB, cell.fillB, cell.clipB)
    ResetStep(cell.stepA, leftward)
    ResetStep(cell.stepB, leftward)
    ShowStep(cell.stepA, false)
    ShowStep(cell.stepB, false)
    cell.clip:Hide()
    cell.guid, cell.before, cell.after, cell.cCur, cell.gen = nil, nil, nil, nil, nil
end

local function LevelGhost(g, strata, level)
    Level(g, strata, level)
    for k = 1, #g.cells do
        local cell = g.cells[k]
        local base = level + 1 + CELL_LEVELS * (k - 1)
        Level(cell.gate, strata, level)
        Level(cell.gateB, strata, level)
        Level(cell.stepA.std, strata, level)
        Level(cell.stepA.rev, strata, level)
        Level(cell.stepB.std, strata, level)
        Level(cell.stepB.rev, strata, level)
        Level(cell.clip, strata, base)
        Level(cell.clipB, strata, base)
        Level(cell.icon, strata, base + 1)
        Level(cell.icon.cd, strata, base + 2)
    end
end

-- The cells' step pairs chained from the ghost's inner edge; a plain offset
-- undoes their fixed length, so a ghost with no cell open takes no slot.
local function AnchorGhost(g, from, fromPoint, offset, leftward)
    g:ClearAllPoints()
    g:SetPoint(leftward and "RIGHT" or "LEFT", from, fromPoint, offset, 0)
    local endFrom, endPoint = g, leftward and "RIGHT" or "LEFT"
    for k = 1, #g.cells do
        local cell = g.cells[k]
        local on = k <= g.used
        if on then
            endFrom, endPoint = AnchorStep(cell.stepA, endFrom, endPoint, 0, leftward)
            endFrom, endPoint = AnchorStep(cell.stepB, endFrom, endPoint, 0, leftward)
        end
        ShowStep(cell.stepA, on)
        ShowStep(cell.stepB, on)
    end
    local undo = 2 * (KT.db.PlateIconSize + KT.db.PlateSpacing) * g.used
    return endFrom, endPoint, leftward and undo or -undo
end

LEVEL.ghost, ANCHOR.ghost, REFEED.ghost = LevelGhost, AnchorGhost, FeedGhost
WAITS.ghost = true
RELEASE.ghost = function(g) KT:ReleaseGhost(g) end

---------------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------------
local function RowOf(unit)
    local row = P.rows[unit]
    if row then return row end
    row = table_remove(P.free.row)
    if not row then
        local head = CreateFrame("Frame", nil, P.lift)
        head:EnableMouse(false)
        row = { head = head, list = {} }
    end
    P.rows[unit] = row
    return row
end

local function DropRow(row)
    row.head:Hide()
    row.head:ClearAllPoints()
    wipe(row.list)
    P.free.row[#P.free.row + 1] = row
end

local function FreeRow(unit)
    local row = P.rows[unit]
    if not row then return end
    P.rows[unit] = nil
    DropRow(row)
end

-- The row's start: PlateBarGap off the anchor's edge on PlateSide, moved by
-- the offsets. TOP and BOTTOM grow right from the bar's left edge. Scaled at
-- every layout, so a UI scale change reaches the gap and offsets too.
local function PlaceHead(head, anchor)
    local db = KT.db
    local gap, ox, oy, side = db.PlateBarGap, db.PlateOffsetX, db.PlateOffsetY, db.PlateSide
    Scaled(head)
    head:SetSize(1, db.PlateIconSize)
    head:ClearAllPoints()
    if side == "RIGHT" then
        head:SetPoint("LEFT", anchor, "RIGHT", gap + ox, oy)
    elseif side == "TOP" then
        head:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", ox, gap + oy)
    elseif side == "BOTTOM" then
        head:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", ox, -gap + oy)
    else
        head:SetPoint("RIGHT", anchor, "LEFT", -gap + ox, oy)
    end
    head:Show()
end

-- Ready live icons nearest the plate, then cooling icons and ghosts by start
-- time, the Rails slot last.
local function RowOrder(a, b)
    local ar, br = a.kind == "rail", b.kind == "rail"
    if ar ~= br then return br end
    local ra, rb = a.ready == true, b.ready == true
    if ra ~= rb then return ra end
    return (a.start or 0) < (b.start or 0)
end

local function AddToRow(e, unit)
    local list = RowOf(unit).list
    list[#list + 1] = e
end

-- Returns the unit whose row held it.
local function RemoveFromRow(e)
    local unit = e.unit
    local row = unit and P.rows[unit]
    if not row then return nil end
    local list = row.list
    for i = #list, 1, -1 do
        if list[i] == e then
            table_remove(list, i)
            break
        end
    end
    return unit
end

-- One row laid out. An empty row goes.
local function LayoutRow(unit)
    local row = P.rows[unit]
    if not row then return end
    local list = row.list
    if #list == 0 then
        FreeRow(unit)
        return
    end
    local anchor = AnchorOf(unit)
    if not anchor then return end
    PlaceHead(row.head, anchor)
    local now = GetTime()
    for i = 1, #list do
        local e = list[i]
        if e.kind == "live" then
            local member = KT.partyMembers[e.guid]
            e.ready = not (member and KT.MainCooling(member, now))
        end
    end
    table_sort(list, RowOrder)
    local leftward = KT.db.PlateSide == "LEFT"
    local from, fromPoint, offset = row.head, leftward and "RIGHT" or "LEFT", 0
    for i = 1, #list do
        local e = list[i]
        from, fromPoint, offset = ANCHOR[e.kind](e, from, fromPoint, offset, leftward)
    end
end

-- Every row marked so far, laid out now. A caller already in a C_Timer
-- callback runs it at once; the armed pass then finds nothing left.
local function FlushLayouts()
    for unit in pairs(P.dirty) do
        P.dirty[unit] = nil
        LayoutRow(unit)
    end
end

-- The armed pass. Only it clears flushArmed, so at most one pass is ever
-- waiting, however many immediate flushes ran meanwhile.
local function LayoutPass()
    P.flushArmed = false
    FlushLayouts()
end

-- On each placement, removal, cooldown change and settings change, never per
-- frame. The row is marked and laid out by the next pass, so the anchor
-- finder only ever runs in a C_Timer callback, whatever stack asked.
function KT:LayoutPlate(unit)
    P.dirty[unit] = true
    if P.flushArmed then return end
    P.flushArmed = true
    C_Timer.After(0, LayoutPass)
end

-- Out of its row or the waiting list, parked; returns the unit it left.
function KT:Unplace(e)
    local old
    if e.waiting then
        local waiting = P.waiting
        for i = #waiting, 1, -1 do
            if waiting[i] == e then
                table_remove(waiting, i)
                break
            end
        end
        e.waiting, e.waitTarget = nil, nil
    else
        old = RemoveFromRow(e)
    end
    Park(e)
    return old
end

---------------------------------------------------------------------------------
-- Placing live icons
---------------------------------------------------------------------------------
-- One frame later, so the anchor finder runs outside the event and a
-- nameplate addon's own plate is attached. stamp: the plate's lifetime when
-- the kick was seen (KT:PlateStamp), or nil for a plate read now; a plate that
-- went since takes nothing. A later call for the same kicker replaces an
-- earlier one still waiting.
function KT:PlaceKickIcon(guid, unit, stamp, counted)
    if not guid or issecretvalue(unit) or type(unit) ~= "string" then return end
    local now = P.epoch[unit] or 0
    if stamp ~= nil and stamp ~= now then return end
    local pend = P.pending[guid]
    if not pend then
        pend = { seq = 0 }
        P.pending[guid] = pend
    end
    pend.seq, pend.open = pend.seq + 1, true
    pend.unit, pend.stamp, pend.at, pend.base, pend.gen = unit, now, GetTime(), nil, nil
    -- counted: a meter-named kick is in the read that named it, so that read
    -- is its baseline. Any other takes the first read at or after it, which
    -- KT:PlatesCounts gives the waiting placement.
    local member = self.partyMembers[guid]
    if counted and member and member.unit ~= "player" then
        pend.base, pend.gen = self.meterBase.a[self:GateSlotOf(member)], KT.meterFight
    end
    local seq, activation, gen = pend.seq, self.activationID, P.gen
    C_Timer.After(0, function()
        if self.activationID ~= activation or P.gen ~= gen or not self.platesOn or pend.seq ~= seq then return end
        pend.open = false
        if pend.stamp ~= (P.epoch[unit] or 0) then return end
        self:PutKickIcon(guid, unit, pend)
    end)
end

-- The player's icon goes to the target's plate at the cast: a missed kick
-- stops nothing, so nothing else would place it.
function KT:PlaceOwnCast(guid)
    local unit = TargetPlate()
    if unit then self:PlaceKickIcon(guid, unit) end
end

-- The kicker's single icon moves to the plate, or is made there; pend is the
-- placement that waited its frame.
function KT:PutKickIcon(guid, unit, pend)
    local member = self.partyMembers[guid]
    if not member or not member.interruptData then return end
    if not C_NamePlate.GetNamePlateForUnit(unit) or not IsHostile(unit) then return end
    local e = P.live[guid]
    local old
    if e then
        old = self:Unplace(e)
    else
        e = table_remove(P.free.live) or BuildLive()
        e.kind, e.guid = "live", guid
        P.live[guid] = e
    end
    if not Attach(e, unit) then
        self:ReleaseLive(guid)
        if old then self:LayoutPlate(old) end
        return
    end
    e.mobGuid = KE:GetSafeUnitGUID(unit)
    e.start, e.kickAt = pend.at, pend.at
    e.cGen, e.cBase, e.cCur = pend.gen, pend.base, nil
    e.needBase = member.unit ~= "player" and pend.gen == nil
    StyleLive(e)
    RefeedLive(e)
    PaintIcon(e.icon, member)
    PaintCooldown(e.icon, member.kickStart, member.kickDuration)
    AddToRow(e, unit)
    if old and old ~= unit then self:LayoutPlate(old) end
    self:LayoutPlate(unit)
    FlushLayouts()
    self:WatchReady(e, member)
end

-- A cooling icon moves to the ready end of its row when the cooldown ends:
-- one timer per placed or repainted kick.
function KT:WatchReady(e, member)
    local now = GetTime()
    if not KT.MainCooling(member, now) then return end
    e.readySeq = (e.readySeq or 0) + 1
    local seq, gen, activation = e.readySeq, P.gen, self.activationID
    C_Timer.After(member.kickStart + member.kickDuration - now + READY_SLACK, function()
        if self.activationID ~= activation or P.gen ~= gen or e.readySeq ~= seq or not e.unit then return end
        self:LayoutPlate(e.unit)
        FlushLayouts()
    end)
end

function KT:ReleaseLive(guid)
    local e = P.live[guid]
    if not e then return end
    P.live[guid] = nil
    local old = self:Unplace(e)
    e.icon.cd:Clear()
    e.guid, e.mobGuid, e.cBase, e.cCur = nil, nil, nil, nil
    P.free.live[#P.free.live + 1] = e
    if old then self:LayoutPlate(old) end
end

---------------------------------------------------------------------------------
-- Count gates and ghosts
---------------------------------------------------------------------------------
function KT:GateSlotOf(member)
    return KT.GateSlot(member, member.unit, self.meterBase.n)
end

-- One timer serves every count gate a read skipped during a cooldown. It
-- wakes at the earliest such end; KT:FeedReady then feeds every element from
-- the latest read, and each one still cooling arms it again. An earlier arm
-- takes over, and the timer it replaced finds its token gone.
function KT:WakeAt(at)
    if P.readyAt and P.readyAt <= at then return end
    P.readySeq = P.readySeq + 1
    P.readyAt = at
    local seq, wait = P.readySeq, at - GetTime()
    C_Timer.After((wait > 0) and wait or 0, function()
        if P.readySeq ~= seq then return end
        P.readyAt = nil
        self:FeedReady()
    end)
end

-- A live icon's baseline is the first read at or after its kick, so it holds
-- that kick's own growth. It is fed only past its own cooldown, so a grip
-- during a cooldown never cuts a running swipe; a read during the cooldown
-- is skipped, and the wake at its end feeds the latest read, on a plate or off.
local function FeedLiveCount(e, member, cur, T)
    if e.needBase then
        if T < e.kickAt - BASE_SLACK then return end
        e.needBase, e.cBase, e.cGen = false, cur, KT.meterFight
        return
    end
    if e.cGen == nil or cur == nil then return end
    if e.cBase == nil and e.cGen == KT.meterFight then return end
    if KT.MainCooling(member, T) then
        KT:WakeAt(member.kickStart + member.kickDuration + READY_SLACK)
        return
    end
    e.cCur = cur
    RefeedLive(e)
end

-- A cell closes again once its teammate interrupted again, fed only past the
-- cell's own cooldown; a read during it is skipped until the wake at its end.
local function FeedCellCount(cell, cur, T, leftward)
    if cur == nil then return end
    local endAt = cell.cdStart + cell.cdDur
    if T < endAt then
        KT:WakeAt(endAt + READY_SLACK)
        return
    end
    cell.cCur = cur
    FeedCell(cell, leftward)
end

-- Each update's gate-slot totals as read (opaque). The cached packet lives
-- only until this next read. A placement still waiting its frame takes this
-- read as its baseline when it is the first at or after its kick.
function KT:PlatesCounts(T, totals)
    local pk = P.packet
    P.packetT = -1
    wipe(pk.units)
    wipe(pk.before)
    wipe(pk.after)
    for guid, pend in pairs(P.pending) do
        local member = pend.open and pend.gen == nil and self.partyMembers[guid]
        if member and member.unit ~= "player" and T >= pend.at - BASE_SLACK then
            pend.base, pend.gen = totals[self:GateSlotOf(member)], KT.meterFight
        end
    end
    self:FeedCounts(T, totals, false)
end

-- Every live icon and ghost cell fed from totals, on a plate or off. ready:
-- a wake, not a read, so an icon still waiting for its baseline is left to
-- the next read, the first at or after its kick.
function KT:FeedCounts(T, totals, ready)
    for guid, e in pairs(P.live) do
        local member = self.partyMembers[guid]
        if member and member.unit ~= "player" and not (ready and e.needBase) then
            FeedLiveCount(e, member, totals[self:GateSlotOf(member)], T)
        end
    end
    local leftward = self.db.PlateSide == "LEFT"
    for i = 1, #P.ghosts do
        local g = P.ghosts[i]
        for k = 1, g.used do
            local cell = g.cells[k]
            local member = self.partyMembers[cell.guid]
            if member then FeedCellCount(cell, totals[self:GateSlotOf(member)], T, leftward) end
        end
    end
end

-- The wake, and any cooldown change: the latest read (opaque, the engine's
-- own current totals, the same table every read gives KT:PlatesCounts).
function KT:FeedReady()
    local totals = self.meterBase and self.meterBase.a
    if not self.platesOn or not totals then return end
    self:FeedCounts(GetTime(), totals, true)
end

-- One update's packet: the teammates KT.AdmitGate took and their gate-slot
-- totals before and after it. plates: the update's hidden plates when nobody
-- was named; each gets a ghost.
function KT:PlatesGate(T, admitted, before, after, plates)
    local pk = P.packet
    wipe(pk.units)
    wipe(pk.before)
    wipe(pk.after)
    for i = 1, #admitted do
        local unit = admitted[i]
        local member = self.meterByUnit[unit]
        if member then
            local slot = self:GateSlotOf(member)
            pk.units[#pk.units + 1] = unit
            pk.before[unit], pk.after[unit] = before[slot], after[slot]
        end
    end
    P.packetT = T
    if not plates then return end
    for i = 1, #plates do
        local plate = plates[i]
        if plate.unit then self:MakeGhost(T, plate.unit, plate.stamp) end
    end
end

-- Plates that joined after their update take its cached packet.
function KT:PlatesLatePlates(T0, plates)
    if P.packetT ~= T0 then return end
    for i = 1, #plates do
        local plate = plates[i]
        if plate.unit then self:MakeGhost(T0, plate.unit, plate.stamp) end
    end
end

-- One ghost per update and plate, its cells from the packet, each cooling
-- from the update's time for that teammate's longest duration. It goes when
-- the longest cell's cooldown ends. stamp: the plate's lifetime when the kick
-- was seen; a plate that went since gets none.
function KT:MakeGhost(T, unit, stamp)
    local now = P.epoch[unit] or 0
    if stamp ~= nil and stamp ~= now then return end
    for i = 1, #P.ghosts do
        local g = P.ghosts[i]
        if g.t == T and g.plate == unit then return end
    end
    local pk = P.packet
    local g = table_remove(P.free.ghost) or BuildGhost()
    local n, longest = 0, 0
    for i = 1, #pk.units do
        local u = pk.units[i]
        local guid = self.meterGuidOf[u]
        local member = guid and self.partyMembers[guid]
        local duration = member and self:ClockDuration(member, false)
        if duration and duration > 0 and n < GHOST_CELLS and pk.before[u] ~= nil and pk.after[u] ~= nil then
            n = n + 1
            local cell = g.cells[n] or BuildCell(g)
            g.cells[n] = cell
            cell.guid, cell.before, cell.after, cell.gen = guid, pk.before[u], pk.after[u], self.meterFight
            cell.cdStart, cell.cdDur = T, duration
            if duration > longest then longest = duration end
        end
    end
    local left = T + longest - GetTime()
    if n == 0 or left <= 0 then
        local leftward = self.db.PlateSide == "LEFT"
        for k = 1, n do ParkCell(g.cells[k], leftward) end
        P.free.ghost[#P.free.ghost + 1] = g
        return
    end
    -- Plain, fixed at making: a sure kick that takes the longest cell out
    -- does not move the ghost's end.
    g.endAt = T + longest
    g.used, g.t, g.start, g.plate, g.stamp = n, T, T, unit, now
    g.seq = g.seq + 1
    P.ghosts[#P.ghosts + 1] = g
    local seq, gen, activation = g.seq, P.gen, self.activationID
    C_Timer.After(0, function()
        if self.activationID ~= activation or P.gen ~= gen or g.seq ~= seq then return end
        if g.stamp ~= (P.epoch[unit] or 0) then
            self:ReleaseGhost(g)
            return
        end
        self:PlaceGhost(g, unit)
    end)
    C_Timer.After(left, function()
        if self.activationID ~= activation or P.gen ~= gen or g.seq ~= seq then return end
        self:ReleaseGhost(g)
    end)
end

-- A frame after its update, on its plate while that is still a hostile one;
-- fed once more a frame after it shows.
function KT:PlaceGhost(g, unit)
    if not C_NamePlate.GetNamePlateForUnit(unit) or not IsHostile(unit) or not Attach(g, unit) then
        self:ReleaseGhost(g)
        return
    end
    g.mobGuid = KE:GetSafeUnitGUID(unit)
    StyleGhost(g)
    PaintGhost(g)
    for k = 1, g.used do
        local cell = g.cells[k]
        PaintCooldown(cell.icon, cell.cdStart, cell.cdDur)
        cell.clip:Show()
    end
    FeedGhost(g)
    AddToRow(g, unit)
    self:LayoutPlate(unit)
    FlushLayouts()
    local seq, gen, activation = g.seq, P.gen, self.activationID
    C_Timer.After(0, function()
        if self.activationID ~= activation or P.gen ~= gen or g.seq ~= seq or not g.unit then return end
        FeedGhost(g)
    end)
end

function KT:ReleaseGhost(g)
    if not g.t then return end
    local ghosts = P.ghosts
    for i = #ghosts, 1, -1 do
        if ghosts[i] == g then
            table_remove(ghosts, i)
            break
        end
    end
    local old = self:Unplace(g)
    local leftward = self.db.PlateSide == "LEFT"
    for k = 1, g.used do ParkCell(g.cells[k], leftward) end
    g.used, g.t, g.plate, g.mobGuid, g.stamp, g.endAt = 0, nil, nil, nil, nil, nil
    g.seq = g.seq + 1
    P.free.ghost[#P.free.ghost + 1] = g
    if old then self:LayoutPlate(old) end
end

-- A sure kick of the member takes their cells out of every ghost that started
-- at or before it; a ghost left with none goes. Returns whether any cell went.
function KT:PlatesSupersede(guid, upto)
    local leftward = self.db.PlateSide == "LEFT"
    local changed = false
    for i = #P.ghosts, 1, -1 do
        local g = P.ghosts[i]
        if g.t <= upto then
            local kept = 0
            for k = 1, g.used do
                local cell = g.cells[k]
                if cell.guid == guid then
                    ParkCell(cell, leftward)
                else
                    kept = kept + 1
                    g.cells[k], g.cells[kept] = g.cells[kept], cell
                end
            end
            if kept ~= g.used then
                changed = true
                g.used = kept
                if kept == 0 then
                    self:ReleaseGhost(g)
                elseif g.unit then
                    LevelGhost(g, g:GetFrameStrata(), g:GetFrameLevel())
                    self:LayoutPlate(g.unit)
                end
            end
        end
    end
    return changed
end

---------------------------------------------------------------------------------
-- Plates going and coming back
---------------------------------------------------------------------------------
-- A plate that went again within the frame is left to its own next add.
function KT:OnPlateAdded(_, unit)
    if issecretvalue(unit) or type(unit) ~= "string" then return end
    local activation, gen, stamp = self.activationID, P.gen, P.epoch[unit] or 0
    C_Timer.After(0, function()
        if self.activationID ~= activation or P.gen ~= gen or not self.platesOn then return end
        if stamp ~= (P.epoch[unit] or 0) then return end
        self:PlateArrived(unit)
    end)
end

-- A waiting element comes back when KT.PlateReturns says the new plate is
-- its mob's.
function KT:PlateArrived(unit)
    if not C_NamePlate.GetNamePlateForUnit(unit) then return end
    local waiting, back = P.waiting, false
    if #waiting > 0 then
        local plateGuid, isTarget = KE:GetSafeUnitGUID(unit), IsTarget(unit)
        for i = #waiting, 1, -1 do
            local e = waiting[i]
            if KT.PlateReturns(e.mobGuid, plateGuid, e.waitTarget, isTarget) and Attach(e, unit) then
                table_remove(waiting, i)
                e.waiting, e.waitTarget = nil, nil
                REFEED[e.kind](e)
                AddToRow(e, unit)
                back = true
            end
        end
    end
    if back then self:LayoutPlate(unit) end
    FlushLayouts()
end

-- An element waits when its mob's GUID read plain at placing, or its mob is
-- the target; any other goes. The plate's lifetime moves first, so every
-- placement still waiting for this token is dropped.
function KT:OnPlateRemoved(_, unit)
    if issecretvalue(unit) or type(unit) ~= "string" then return end
    P.epoch[unit] = (P.epoch[unit] or 0) + 1
    local row = P.rows[unit]
    if not row then return end
    P.rows[unit] = nil
    local isTarget = IsTarget(unit)
    local list = row.list
    for i = #list, 1, -1 do
        local e = list[i]
        list[i] = nil
        if WAITS[e.kind] and (e.mobGuid or isTarget) then
            Park(e)
            e.waiting, e.waitTarget = true, isTarget
            P.waiting[#P.waiting + 1] = e
        else
            RELEASE[e.kind](e)
        end
    end
    DropRow(row)
end

-- A new target ends every wait that counted on the old one.
function KT:OnPlatesTarget()
    local waiting = P.waiting
    for i = #waiting, 1, -1 do
        local e = waiting[i]
        if e.waitTarget then
            e.waitTarget = nil
            if not e.mobGuid then
                table_remove(waiting, i)
                e.waiting = nil
                RELEASE[e.kind](e)
            end
        end
    end
end

---------------------------------------------------------------------------------
-- Engine calls
---------------------------------------------------------------------------------
-- The member's kickStart or kickDuration changed.
function KT:PlatesCooldown(guid)
    self:FeedReady()
    local e, member = P.live[guid], self.partyMembers[guid]
    if not e or not member then return end
    PaintCooldown(e.icon, member.kickStart, member.kickDuration)
    if e.unit then self:LayoutPlate(e.unit) end
    self:WatchReady(e, member)
end

-- A kick, spec or class changed, or a member left.
function KT:PlatesRoster()
    for guid, e in pairs(P.live) do
        local member = self.partyMembers[guid]
        if not member or not member.interruptData then
            self:ReleaseLive(guid)
        else
            PaintIcon(e.icon, member)
        end
    end
    for i = 1, #P.ghosts do PaintGhost(P.ghosts[i]) end
end

function KT:PlatesReset()
    P.gen = P.gen + 1
    wipe(P.pending)
    P.packetT = -1
    wipe(P.packet.units)
    wipe(P.packet.before)
    wipe(P.packet.after)
    for guid in pairs(P.live) do self:ReleaseLive(guid) end
    for i = #P.ghosts, 1, -1 do self:ReleaseGhost(P.ghosts[i]) end
    self:ReleaseSamples()
    for i = #P.waiting, 1, -1 do
        local e = P.waiting[i]
        RELEASE[e.kind](e)
    end
    for unit in pairs(P.rows) do FreeRow(unit) end
    wipe(P.dirty)
end

-- Every element is hosted, styled and laid out again.
function KT:PlatesRestyle()
    if not P.lift then return end
    ReadScale()
    for guid, e in pairs(P.live) do
        if e.unit then Attach(e, e.unit) else Scaled(e) end
        StyleLive(e)
        RefeedLive(e)
        local member = self.partyMembers[guid]
        if member then PaintIcon(e.icon, member) end
    end
    for i = 1, #P.ghosts do
        local g = P.ghosts[i]
        if g.unit then Attach(g, g.unit) else Scaled(g) end
        StyleGhost(g)
        PaintGhost(g)
        FeedGhost(g)
    end
    if self.isPreview then self:PlaceSamples() end
    for unit in pairs(P.rows) do self:LayoutPlate(unit) end
end

function KT:PlatesActivate()
    EnsureLift()
    ReadScale()
    self.platesOn = true
    self:RegisterEvent("NAME_PLATE_UNIT_ADDED", "OnPlateAdded")
    self:RegisterEvent("NAME_PLATE_UNIT_REMOVED", "OnPlateRemoved")
    self:RegisterEvent("PLAYER_TARGET_CHANGED", "OnPlatesTarget")
    self:RegisterEvent("UI_SCALE_CHANGED", "PlatesRestyle")
end

function KT:PlatesDeactivate()
    self.platesOn = false
    self:UnregisterEvent("NAME_PLATE_UNIT_ADDED")
    self:UnregisterEvent("NAME_PLATE_UNIT_REMOVED")
    self:UnregisterEvent("PLAYER_TARGET_CHANGED")
    self:UnregisterEvent("UI_SCALE_CHANGED")
    self:PlatesReset()
end

-- Plates run while the tracker is active and Nameplate Icons is on.
function KT:SyncPlates()
    local want = self.isActive and self.db.PlateIcons == true
    if want and not self.platesOn then
        self:PlatesActivate()
    elseif not want and self.platesOn then
        self:PlatesDeactivate()
    end
end

---------------------------------------------------------------------------------
-- Preview: two samples on the hostile target's plate
---------------------------------------------------------------------------------
function KT:PlatesPreview()
    if self.db.PlateIcons ~= true then
        self:PlatesPreviewEnd()
        return
    end
    EnsureLift()
    ReadScale()
    if not P.previewFrame then
        local frame = CreateFrame("Frame")
        P.placeSamples = function() KT:PlaceSamples() end
        frame:SetScript("OnEvent", function(_, event, unit)
            if event == "NAME_PLATE_UNIT_REMOVED" then
                if not issecretvalue(unit) and unit == P.sampleUnit then KT:ReleaseSamples() end
            elseif event == "NAME_PLATE_UNIT_ADDED" then
                if not P.sampleUnit then C_Timer.After(0, P.placeSamples) end
            else
                KT:PlaceSamples()
            end
        end)
        P.previewFrame = frame
    end
    local frame = P.previewFrame
    frame:RegisterEvent("PLAYER_TARGET_CHANGED")
    frame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    frame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
    self:PlaceSamples()
end

function KT:PutSample(i, member, unit, start, duration)
    local e = P.samples[i]
    if not e then
        e = BuildLive()
        e.kind = "sample"
        P.samples[i] = e
    end
    if not Attach(e, unit) then return end
    e.start, e.ready = i, start == nil
    StyleLive(e)
    RefeedLive(e)
    PaintIcon(e.icon, member)
    PaintCooldown(e.icon, start, duration)
    AddToRow(e, unit)
end

-- The player's own kick, ready, and a Mage's on a 30-second swipe.
function KT:PlaceSamples()
    self:ReleaseSamples()
    if not self.isPreview or self.db.PlateIcons ~= true then return end
    local unit = TargetPlate()
    if not unit or not IsHostile(unit) then return end
    local _, classToken = UnitClass("player")
    local specID = KE:GetPlayerSpecId()
    local kick = specID and KE:GetTrackedKickForSpec(specID)
    self:PutSample(1, { matchClass = classToken, specID = specID, interruptData = { id = kick and kick.id or 1766 } },
        unit)
    self:PutSample(2, { matchClass = "MAGE", specID = 62, interruptData = { id = 2139 } }, unit, GetTime(), SAMPLE_CD)
    P.sampleUnit = unit
    self:LayoutPlate(unit)
end

function KT:ReleaseSamples()
    local unit = P.sampleUnit
    P.sampleUnit = nil
    for i = 1, #P.samples do
        local e = P.samples[i]
        RemoveFromRow(e)
        Park(e)
        e.icon.cd:Clear()
    end
    if unit then self:LayoutPlate(unit) end
end

function KT:PlatesPreviewEnd()
    if P.previewFrame then P.previewFrame:UnregisterAllEvents() end
    self:ReleaseSamples()
end
