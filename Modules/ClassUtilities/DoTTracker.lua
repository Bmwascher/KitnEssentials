-- ╔══════════════════════════════════════════════════════════╗
-- ║  DoTTracker.lua                                          ║
-- ║  Module: DoT Tracker                                     ║
-- ║  Purpose: How many of the enemies in the fight carry     ║
-- ║           each of the player's DoTs.                     ║
-- ╚══════════════════════════════════════════════════════════╝
--
-- NOTHING HERE READS AN ENEMY AURA OR THE COUNT. For each counted enemy and
-- DoT, a Blizzard aura container watches that enemy's nameplate for that one
-- debuff, laid out 512 px wide while it is up and 1 px while it is not. The
-- containers are chained and a tail frame hangs off the last one, so with S
-- sensors and n lit the tail sits n * 512 + (S - n) px along. One label per
-- possible n rides the tail inside a clipping window, and only the label for
-- the real n lands in it. Container sizes are secret at all times, so nothing
-- on the chain measures itself.

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class DoTTracker: AceModule
local DT = KitnEssentials:NewModule("DoTTracker", "AceEvent-3.0")

local _G = _G
local CreateFrame = CreateFrame
local UIParent = UIParent
local C_AddOns = C_AddOns
local C_Spell = C_Spell
local C_SpellBook = C_SpellBook
local C_Timer = C_Timer
local UnitClass = UnitClass
local UnitExists = UnitExists
local UnitCanAttack = UnitCanAttack
local UnitCanAssist = UnitCanAssist
local UnitIsDead = UnitIsDead
local UnitAffectingCombat = UnitAffectingCombat
local issecretvalue = issecretvalue
local ipairs, pcall, tostring = ipairs, pcall, tostring
local math_ceil, math_max, math_min = math.ceil, math.max, math.min
local table_concat = table.concat

local Rules = KE.DoTTrackerRules
local Ask = KE.PlateSlots.Ask

-- Flip to true, /reload, repro, read the log. Nothing can print the lit count:
-- no code knows it.
local DEBUG_DOT = false

local STRIDE = 512
local TICK_SECONDS = 1
local SPEC_SETTLE_DELAY = 2
local TAIL_TEMPLATE = "DisableUntrustedLayoutScriptsTemplate"
local AURA_FILTER = "HARMFUL|PLAYER"
local SENSOR_GROUP = "dot"
local TIMER_SLOT = "t"
local UNIT_EVENTS = { "UNIT_FLAGS", "UNIT_THREAT_LIST_UPDATE", "UNIT_FACTION" }
local DEFAULT_SOME = { 1, 1, 1, 1 }
local DEFAULT_ALL = { 0.35, 1, 0.35, 1 }
local DEFAULT_TIMER = { 1, 1, 1, 1 }
local GLOW_OFF = { GlowEnabled = false }
local SAMPLE_LIT = { 3, 6, 2, 5 }
local SAMPLE_TIMERS = { "16", "23", "9", "12" }
local SAMPLE_TOTAL = 6
local NONE = {}

DT.root = nil
DT.cells = {}
DT.list = {}
DT.slots = nil
DT.runner = nil
DT.gate = nil
DT.requestGate = nil
DT.gateEventsOn = false
DT.buildTarget = 0
DT.listKey = nil
DT.active = false
DT.applying = false
DT.previewing = false
DT.inCombat = false
DT.paintedTotal = -1
DT.editModeRegistered = false
DT.someColor = DEFAULT_SOME
DT.allColor = DEFAULT_ALL

local measureFS

---------------------------------------------------------------------------------
-- DB Helper
---------------------------------------------------------------------------------
function DT:UpdateDB()
    self.db = KE.db.profile.DoTTracker
end

function DT:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

---------------------------------------------------------------------------------
-- Reads
---------------------------------------------------------------------------------
-- The game's spell-id filter guard counts immune and uninteractable units as
-- assistable; asked any other way, a unit it treats as friendly would pass.
local function CanAssist(unit)
    return Ask(UnitCanAssist, "player", unit, true, true)
end

local unitApi = {
    exists    = function(unit) return Ask(UnitExists, unit) end,
    canAttack = function(unit) return Ask(UnitCanAttack, "player", unit) end,
    canAssist = CanAssist,
    isDead    = function(unit) return Ask(UnitIsDead, unit) end,
    inCombat  = function(unit) return Ask(UnitAffectingCombat, unit) end,
}

local function Verdict(unit, strict)
    return Rules.Verdict(unit, strict, DT.db.OnlyEnemiesInCombat ~= false, unitApi)
end

local function IsKnown(spellID)
    return Ask(C_SpellBook and C_SpellBook.IsSpellKnown, spellID, Enum.SpellBookSpellBank.Player)
end

-- Load-on-demand, and the tail template is the feature: without it nothing of
-- ours may hang off a container that has a group.
local function ContainersAvailable()
    if _G.AuraContainerSortMethod == nil and C_AddOns and C_AddOns.LoadAddOn
        and C_AddOns.IsAddOnLoaded and not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") then
        pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer")
    end
    if _G.AuraContainerSortMethod == nil then return false end
    local xml = _G.C_XMLUtil
    if not (xml and xml.GetTemplateInfo) then return false end
    local ok, info = pcall(xml.GetTemplateInfo, TAIL_TEMPLATE)
    return ok and info ~= nil
end

---------------------------------------------------------------------------------
-- Geometry
---------------------------------------------------------------------------------
-- Measured on a hidden fontstring of the root, which is ours and plain; the
-- labels themselves live on the tail and are never asked.
local function TextBox(db)
    local size = db.FontSize or 18
    KE:ApplyFontToText(measureFS, db.FontFace, size, db.FontOutline)
    measureFS:SetText(db.CountFormat == "FRACTION" and "00/00" or "00")
    local width = measureFS:GetStringWidth()
    if not width or (issecretvalue and issecretvalue(width)) or width < 1 then width = size * 3 end
    return math_ceil(width) + 6, size + 6
end

-- The sheet glow styles draw past the icon edge; the window grows to keep them.
local function GlowMargin(db)
    if not db.GlowEnabled then return 0 end
    local entry = KE.AuraGlowRules.FLIPBOOKS[KE.AuraGlowRules.ResolveType(db.GlowType)]
    if not entry then return 0 end
    return math_ceil((entry.sizeFactor - 1) / 2 * (db.IconSize or 40))
end

-- Pixels from the icon's top left, y growing downward. The window is the
-- smallest box holding the icon and the text, and stays narrower than a stride
-- so the answers on either side are clipped.
local function Geometry(db)
    local size = db.IconSize or 40
    local tw, th = TextBox(db)
    local tx, ty = db.CountX or 0, -(db.CountY or 0)
    local where = db.CountPosition
    local left, top
    if where == "TOP" then
        left, top = size / 2 - tw / 2, -th
    elseif where == "BOTTOM" then
        left, top = size / 2 - tw / 2, size
    elseif where == "LEFT" then
        left, top = -tw, size / 2 - th / 2
    elseif where == "RIGHT" then
        left, top = size, size / 2 - th / 2
    else
        left, top = size / 2 - tw / 2, size / 2 - th / 2
    end
    left, top = left + tx, top + ty
    local pad = GlowMargin(db)
    local boxL, boxT = math_min(0, left) - pad, math_min(0, top) - pad
    local boxR, boxB = math_max(size, left + tw) + pad, math_max(size, top + th) + pad
    return {
        size = size,
        viewX = boxL, viewY = boxT,
        viewW = math_min(boxR - boxL, STRIDE - 2), viewH = boxB - boxT,
        iconX = -boxL, iconY = -boxT,
        labelX = left + tw / 2 - boxL, labelY = top + th / 2 - boxT,
    }
end

---------------------------------------------------------------------------------
-- Answers
---------------------------------------------------------------------------------
-- Answer k is pushed back by exactly the distance the tail travels when k
-- sensors are lit, dark ones still 1 px each.
local function AnswerX(cell, k)
    return -(k * STRIDE + (#cell.sensors - k))
end

-- Each region only ever has its one point, so SetPoint replaces it in place: a
-- refused move leaves it where it was rather than unanchored.
local function PlaceAnswer(cell, k, answer)
    local geo = cell.geo
    local bx = AnswerX(cell, k)
    answer.label:SetPoint("CENTER", cell.tail, "TOPLEFT", bx + geo.labelX, -geo.labelY)
    answer.border:SetPoint("TOPLEFT", cell.tail, "TOPLEFT", bx + geo.iconX, -geo.iconY)
    answer.border:SetSize(geo.size, geo.size)
    answer.icon:SetPoint("TOPLEFT", cell.tail, "TOPLEFT", bx + geo.iconX + 1, -(geo.iconY + 1))
    answer.icon:SetSize(math_max(1, geo.size - 2), math_max(1, geo.size - 2))
end

local function BuildAnswer(cell, k)
    local answer = {
        label = cell.tail:CreateFontString(nil, "OVERLAY"),
        border = cell.tail:CreateTexture(nil, "BACKGROUND"),
        icon = cell.tail:CreateTexture(nil, "ARTWORK"),
    }
    answer.border:SetColorTexture(0, 0, 0, 1)
    KE:ApplyIconZoom(answer.icon)
    answer.label:Hide()
    answer.border:Hide()
    answer.icon:Hide()
    cell.answers[k] = answer
    return answer
end

local function StyleAnswer(cell, k, answer)
    local db = DT.db
    KE:ApplyFontToText(answer.label, db.FontFace, db.FontSize, db.FontOutline)
    answer.icon:SetTexture(cell.texture)
    local alpha = db.ShowIcon == false and 0 or 1
    answer.icon:SetAlpha(alpha)
    answer.border:SetAlpha(alpha)
    PlaceAnswer(cell, k, answer)
end

-- With empty DoTs hidden, each answer above zero carries its own icon copy:
-- an icon of ours could only be hidden by code that knows the count is zero.
local function PaintAnswers(cell, total)
    local db = DT.db
    local hideEmpty = db.HideEmpty ~= false
    for k = 0, #cell.sensors do
        local answer = cell.answers[k]
        if k <= total then
            local color = Rules.LabelColorKey(k, total) == "all" and DT.allColor or DT.someColor
            answer.label:SetTextColor(color[1], color[2], color[3], color[4])
            answer.label:SetText(Rules.Label(k, total, db.CountFormat))
            answer.label:SetShown(not (hideEmpty and k == 0))
            local ownIcon = hideEmpty and k > 0
            answer.icon:SetShown(ownIcon)
            answer.border:SetShown(ownIcon)
        else
            answer.label:Hide()
            answer.icon:Hide()
            answer.border:Hide()
        end
    end
end

---------------------------------------------------------------------------------
-- Glow
---------------------------------------------------------------------------------
-- Drawn at answer `total`'s icon, so the window shows it only while every
-- counted enemy carries the DoT. A repaint or a new sensor only moves it; a
-- restyle restarts its animations, so it waits for an on/off change or Apply.
-- Off goes through Configure, not Hide: a hidden animation still costs.
local function PlaceGlow(cell, total)
    local host, geo = cell.glow, cell.geo
    if not host or not geo then return end
    local on = DT.db.GlowEnabled == true and total > 0
    if on then
        host:SetPoint("TOPLEFT", cell.tail, "TOPLEFT", AnswerX(cell, total) + geo.iconX, -geo.iconY)
    end
    if on == cell.glowOn then return end
    if on then
        KE.AuraGlow.Configure(host, DT.db, geo.size, geo.size)
    else
        KE.AuraGlow.Configure(host, GLOW_OFF)
    end
    -- Recorded after the write, so a refused one is tried again.
    cell.glowOn = on
end

---------------------------------------------------------------------------------
-- Cells and sensors
---------------------------------------------------------------------------------
local function InitSensorButton(button)
    -- Here only to take up room: no art and no mouse, since lit it spans a
    -- whole stride of play field.
    pcall(button.SetSize, button, 1, 1)
    pcall(button.SetMouseClickEnabled, button, false)
    pcall(button.SetMouseMotionEnabled, button, false)
end

local function PlaceAllAnswers(cell, count)
    StyleAnswer(cell, count, cell.answers[count])
    for k = 0, count - 1 do PlaceAnswer(cell, k, cell.answers[k]) end
end

-- A sensor that cannot join the chain is hidden, and the cell stops growing at
-- the sensors it has.
local function Discard(cell, sensor, reason)
    cell.failed = reason
    pcall(sensor.Hide, sensor)
    return false
end

-- In the order the client allows: the group goes on before anything hangs off
-- the newcomer, then the newcomer is linked, then the tail moves onto it.
local function AddSensor(cell)
    local count = #cell.sensors + 1
    -- The answer comes first, so no sensor is ever counted without one.
    if not cell.answers[count] then
        local built, buildErr = pcall(BuildAnswer, cell, count)
        if not built then
            cell.failed = tostring(buildErr)
            return false
        end
    end
    local ok, sensor = pcall(CreateFrame, "AuraContainer", nil, cell.view, "CustomAuraContainerTemplate")
    if not ok or not sensor then
        cell.failed = "container refused"
        return false
    end
    if not pcall(sensor.SetSize, sensor, 1, 1) then return Discard(cell, sensor, "size refused") end
    local grouped, groupErr = pcall(sensor.AddAuraGroup, sensor, SENSOR_GROUP, AURA_FILTER, {
        maxFrameCount = 1,
        candidateFilters = { includeSpellIDs = { [cell.id] = true } },
        initializeFrame = InitSensorButton,
        layout = { elementWidth = STRIDE, elementHeight = 1, elementSpacing = 0, lineSpacing = 0 },
    })
    -- A sensor without its group would never light.
    if not grouped then return Discard(cell, sensor, tostring(groupErr)) end
    pcall(sensor.SetEnabled, sensor, false)

    -- The tail only ever has its TOPLEFT point, and SetPoint replaces it in
    -- place. With no ClearAllPoints first, a refused move leaves the tail on the
    -- last linked sensor (or the view), so the answers still match the sensors
    -- counted, whichever sensor is refused.
    local prev = cell.sensors[#cell.sensors]
    local linked, linkErr = pcall(function()
        if prev then
            sensor:SetPoint("TOPLEFT", prev, "TOPRIGHT", 0, 0)
        else
            sensor:SetPoint("TOPLEFT", cell.view, "TOPLEFT", 0, 0)
        end
        cell.tail:SetPoint("TOPLEFT", sensor, "TOPRIGHT", 0, 0)
    end)
    if not linked then return Discard(cell, sensor, tostring(linkErr)) end

    cell.sensors[count] = sensor
    -- Every answer's offset counts the sensors. The sensor is linked, so it
    -- counts either way; a refused placement stops the cell growing.
    local placed, placeErr = pcall(PlaceAllAnswers, cell, count)
    if not placed then cell.failed = tostring(placeErr) end
    return true
end

local function NewCell(index)
    local cell = { index = index, sensors = {}, answers = {} }
    local frame = CreateFrame("Frame", nil, DT.root)
    cell.frame = frame
    cell.border = frame:CreateTexture(nil, "BACKGROUND")
    cell.border:SetColorTexture(0, 0, 0, 1)
    cell.border:SetAllPoints(frame)
    cell.icon = frame:CreateTexture(nil, "ARTWORK")
    cell.icon:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
    cell.icon:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
    KE:ApplyIconZoom(cell.icon)

    -- The window: whatever the chain does out at 512 px per lit sensor is
    -- clipped here.
    cell.view = CreateFrame("Frame", nil, frame)
    cell.view:SetClipsChildren(true)
    cell.view:SetFrameLevel(frame:GetFrameLevel() + 5)

    cell.tail = CreateFrame("Frame", nil, cell.view, TAIL_TEMPLATE)
    cell.tail:SetPoint("TOPLEFT", cell.view, "TOPLEFT", 0, 0)
    BuildAnswer(cell, 0)
    cell.glow = KE.AuraGlow.CreateHost(cell.tail, DT.db, TAIL_TEMPLATE)
    -- CreateHost fills its parent; from here on the host keeps one TOPLEFT
    -- point, which PlaceGlow replaces in place.
    cell.glow:ClearAllPoints()
    KE.AuraGlow.Configure(cell.glow, GLOW_OFF)
    cell.glowOn = false

    -- The preview's stand-ins, plain frames off the tail: the real labels line
    -- up only while the game has something to count.
    cell.over = CreateFrame("Frame", nil, frame)
    cell.over:SetAllPoints(frame)
    cell.over:SetFrameLevel(frame:GetFrameLevel() + 6)
    cell.over:Hide()
    cell.sample = cell.over:CreateFontString(nil, "OVERLAY")
    cell.sampleTimer = cell.over:CreateFontString(nil, "OVERLAY")
    cell.previewGlow = KE.AuraGlow.CreateHost(cell.over, DT.db)
    KE.AuraGlow.Configure(cell.previewGlow, GLOW_OFF)

    DT.cells[index] = cell
    return cell
end

-- A cell is reused for whatever DoT takes its place in the row; its groups are
-- re-pointed rather than rebuilt. Only reached with the gate's yes
-- (Rules.PlanApply).
local function Refilter(cell, id)
    local accepted = 0
    for i = 1, #cell.sensors do
        local sensor = cell.sensors[i]
        if pcall(sensor.SetAuraGroupCandidateFilters, sensor, SENSOR_GROUP, { includeSpellIDs = { [id] = true } }) then
            accepted = accepted + 1
        end
    end
    local timerOk
    if cell.timer then
        timerOk = pcall(cell.timer.SetAuraSlotCandidateFilters, cell.timer, TIMER_SLOT, { includeSpellIDs = { [id] = true } })
    end
    if DEBUG_DOT then
        KE:Print(("[DOT] %s re-pointed to %s: sensors %d/%d, timer %s"):format(
            tostring(cell.id), tostring(id), accepted, #cell.sensors, tostring(timerOk)))
    end
    cell.id = id
end

local function StyleCell(cell, geo)
    local db = DT.db
    cell.geo = geo
    cell.texture = C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(cell.id)
    cell.frame:SetSize(geo.size, geo.size)
    cell.icon:SetTexture(cell.texture)
    local alpha = db.ShowIcon == false and 0 or 1
    cell.icon:SetAlpha(alpha)
    cell.border:SetAlpha(alpha)
    cell.view:ClearAllPoints()
    cell.view:SetPoint("TOPLEFT", cell.frame, "TOPLEFT", geo.viewX, -geo.viewY)
    cell.view:SetSize(geo.viewW, geo.viewH)
    cell.tail:SetSize(geo.viewW, geo.viewH)
    cell.glow:SetSize(geo.size, geo.size)
    -- Restyled by the next placement, which Apply forces.
    cell.glowOn = nil
    for k = 0, #cell.sensors do StyleAnswer(cell, k, cell.answers[k]) end
    KE:ApplyFontToText(cell.sample, db.FontFace, db.FontSize, db.FontOutline)
    cell.sample:ClearAllPoints()
    cell.sample:SetPoint("CENTER", cell.frame, "TOPLEFT", geo.viewX + geo.labelX, -(geo.viewY + geo.labelY))
    KE:ApplyFontToText(cell.sampleTimer, db.FontFace, db.TimerFontSize, db.FontOutline)
    local tr, tg, tb, ta = KE:ResolveColor(db.TimerColor, DEFAULT_TIMER)
    cell.sampleTimer:SetTextColor(tr, tg, tb, ta)
    cell.sampleTimer:ClearAllPoints()
    cell.sampleTimer:SetPoint("CENTER", cell.frame, "CENTER", db.TimerX or 0, db.TimerY or 0)
end

-- The root is the first icon, not the row, so the row grows from where it was
-- put however long the list is.
local function LayoutCells()
    local db = DT.db
    local size, gap = db.IconSize or 40, db.Spacing or 4
    local grow = db.GrowDirection or "DOWN"
    DT.root:SetSize(size, size)
    local step = size + gap
    local dx = (grow == "LEFT" and -step) or (grow == "RIGHT" and step) or 0
    local dy = (grow == "UP" and step) or (grow == "DOWN" and -step) or 0
    for i = 1, #DT.list do
        local frame = DT.cells[i].frame
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", DT.root, "TOPLEFT", (i - 1) * dx, (i - 1) * dy)
    end
end

-- A cell past the list, or every cell when the display stops: hidden and kept
-- for the next DoT, with nothing left running on it.
local function RetireCell(cell)
    cell.frame:Hide()
    if cell.timer then pcall(cell.timer.SetEnabled, cell.timer, false) end
    if cell.glowOn ~= false and pcall(KE.AuraGlow.Configure, cell.glow, GLOW_OFF) then
        cell.glowOn = false
    end
    KE.AuraGlow.Configure(cell.previewGlow, GLOW_OFF)
end

---------------------------------------------------------------------------------
-- Target timer
---------------------------------------------------------------------------------
-- The countdown is the game's own, drawn into a fontstring registered on the
-- aura button. That button refuses addon writes while auras are secret, so its
-- place and look are set in initializeFrame, before the restriction attaches,
-- and otherwise only behind the gate.

local function TimerStyleKey(db)
    local color = db.TimerColor or DEFAULT_TIMER
    return table_concat({
        tostring(db.FontFace), tostring(db.TimerFontSize), tostring(db.FontOutline),
        tostring(color[1]), tostring(color[2]), tostring(color[3]), tostring(color[4]),
        tostring(db.TimerX), tostring(db.TimerY), tostring(db.IconSize),
    }, ":")
end

-- Behind the gate only: a write to the restricted slot button. Its one CENTER
-- point is replaced in place, so a refused move leaves it where it was.
local function PlaceTimerSlot(cell)
    local slot, db = cell.timerSlot, DT.db
    if not slot then return true end
    local size = db.IconSize or 40
    local moved = pcall(slot.SetPoint, slot, "CENTER", cell.frame, "CENTER", db.TimerX or 0, db.TimerY or 0)
    local sized = pcall(slot.SetSize, slot, size, size)
    return moved and sized
end

local function StyleTimerText(fontString)
    local db = DT.db
    local fonted = pcall(KE.ApplyFontToText, KE, fontString, db.FontFace, db.TimerFontSize, db.FontOutline)
    local r, g, b, a = KE:ResolveColor(db.TimerColor, DEFAULT_TIMER)
    local colored = pcall(fontString.SetTextColor, fontString, r, g, b, a)
    return fonted and colored
end

local function PlaceTimerContainer(container, frame)
    container:SetFrameLevel(frame:GetFrameLevel() + 7)
    container:SetPoint("CENTER", frame, "CENTER", 0, 0)
    container:SetSize(1, 1)
end

-- True only for a new timer whose text took its style. A container that
-- cannot take its slot is hidden, as a refused sensor is.
local function EnsureTimer(cell)
    if cell.timer or cell.timerFailed then return false end
    local ok, container = pcall(CreateFrame, "AuraContainer", nil, cell.frame, "CustomAuraContainerTemplate")
    if not ok or not container then
        cell.timerFailed = true
        return false
    end
    local styled = false
    local added, slot
    if pcall(PlaceTimerContainer, container, cell.frame) then
        added, slot = pcall(container.AddAuraSlot, container, TIMER_SLOT, AURA_FILTER, {
            candidateFilters = { includeSpellIDs = { [cell.id] = true } },
            initializeFrame = function(button)
                -- A slot takes no part in the flow layout, so it is anchored by hand.
                local db = DT.db
                local size = db.IconSize or 40
                button:ClearAllPoints()
                button:SetPoint("CENTER", cell.frame, "CENTER", db.TimerX or 0, db.TimerY or 0)
                button:SetSize(size, size)
                -- Display only: no aura tooltip, and clicks reach the world.
                pcall(button.SetMouseClickEnabled, button, false)
                pcall(button.SetMouseMotionEnabled, button, false)
                local fontString = button:CreateFontString(nil, "OVERLAY")
                fontString:SetPoint("CENTER", button, "CENTER", 0, 0)
                styled = StyleTimerText(fontString)
                button:SetDurationText(fontString, {})
                cell.timerText = fontString
            end,
        })
    end
    if DEBUG_DOT then KE:Print("[DOT] timer for " .. tostring(cell.id) .. " added=" .. tostring(added)) end
    if not added then
        cell.timerFailed = true
        pcall(container.Hide, container)
        return false
    end
    cell.timer, cell.timerSlot = container, slot
    pcall(container.SetUnit, container, "target")
    return styled
end

local function TargetWanted()
    return Rules.TimerWanted(Ask(UnitExists, "target"), CanAssist("target"))
end

-- Timer work only the gate may allow: a shown cell still without its timer, or
-- a timer whose look is out of date.
function DT:TimersOwed(list, key)
    for i = 1, #list do
        local cell = self.cells[i]
        if not cell then return true end
        if not cell.timer and not cell.timerFailed then return true end
        if cell.timer and cell.timerStyle ~= key then return true end
    end
    return false
end

function DT:StyleTimers(list, key, allowed)
    if not self.active or not allowed then return end
    for i = 1, #list do
        local cell = self.cells[i]
        if not cell.timer then
            -- Unrecorded, a new timer stays owed and the next yes restyles
            -- it; a failed one is never owed again.
            if EnsureTimer(cell) then cell.timerStyle = key end
        elseif cell.timerStyle ~= key then
            local styled = not cell.timerText or StyleTimerText(cell.timerText)
            -- Recorded only when every write went through; otherwise the
            -- timer stays owed and the next yes retries it.
            if PlaceTimerSlot(cell) and styled then cell.timerStyle = key end
        end
    end
end

-- The same token string is a no-op for SetUnit, so a new target is picked up
-- through UpdateAllAuras.
function DT:UpdateTimers()
    local shown = self.active and not self.previewing and self.db.TimerEnabled ~= false
    local want = shown and TargetWanted()
    for i = 1, #self.list do
        local timer = self.cells[i].timer
        if timer then
            pcall(timer.SetShown, timer, shown)
            pcall(timer.SetEnabled, timer, want)
            if want then pcall(timer.UpdateAllAuras, timer) end
        end
    end
    if DEBUG_DOT then KE:Print("[DOT] timers shown=" .. tostring(shown) .. " target=" .. tostring(want)) end
end

-- Whether the game applies the timer's spell-id filter depends on the sides
-- of both the target and the player, and either can change while targeted.
function DT:OnUnitFaction(_, unit)
    if unit == "target" or unit == "player" then self:UpdateTimers() end
end

---------------------------------------------------------------------------------
-- Counting
---------------------------------------------------------------------------------
function DT:BindSlot(slot, unit)
    for i = 1, #self.list do
        local sensor = self.cells[i].sensors[slot]
        if sensor then
            -- Unit before enable: enabling registers the unit's events, and the
            -- off-to-on switch is what makes a reused token read afresh.
            pcall(sensor.SetUnit, sensor, unit)
            pcall(sensor.SetEnabled, sensor, true)
        end
    end
    if DEBUG_DOT then KE:Print("[DOT] slot " .. slot .. " = " .. unit) end
end

function DT:UnbindSlot(slot, unit)
    for _, cell in ipairs(self.cells) do
        local sensor = cell.sensors[slot]
        if sensor then pcall(sensor.SetEnabled, sensor, false) end
    end
    if DEBUG_DOT then KE:Print("[DOT] slot " .. slot .. " released (" .. tostring(unit) .. ")") end
end

function DT:BuildSlot(slot)
    local didWork = false
    for i = 1, #self.list do
        local cell = self.cells[i]
        if #cell.sensors < slot and not cell.failed then
            if AddSensor(cell) then
                didWork = true
            elseif DEBUG_DOT then
                KE:Print("[DOT] " .. tostring(cell.id) .. " stopped growing at " .. #cell.sensors
                    .. ": " .. tostring(cell.failed))
            end
        end
    end
    if didWork then
        for i = 1, #self.list do pcall(PlaceGlow, self.cells[i], self.paintedTotal) end
    end
    if DEBUG_DOT and didWork then KE:Print("[DOT] built slot " .. slot) end
    return didWork
end

function DT:OnScanDone(total)
    if total ~= self.paintedTotal then
        self.paintedTotal = total
        for i = 1, #self.list do
            local cell = self.cells[i]
            -- A refused write is repainted on the next scan, not taken as done.
            if not (pcall(PaintAnswers, cell, total) and pcall(PlaceGlow, cell, total)) then
                self.paintedTotal = -1
                if DEBUG_DOT then KE:Print("[DOT] repaint refused for " .. tostring(cell.id)) end
            end
        end
        if DEBUG_DOT then
            local relaxed = self.slots and self.slots.strict == false
            KE:Print("[DOT] total " .. total .. (relaxed and " (relaxed)" or ""))
        end
    end
    if self.active and not self.applying then self:RaiseBuildTarget() end
end

-- The target never shrinks until a reload or a list or cap change.
function DT:RaiseBuildTarget()
    local highest = 0
    for slot = self.slots:Cap(), 1, -1 do
        if self.slots:UnitOf(slot) then
            highest = slot
            break
        end
    end
    local want = Rules.BuildTarget(self.db.MaxEnemies or 20, highest)
    if want > self.buildTarget then
        self.buildTarget = want
        self.runner:Run(want)
    end
end

-- The cap follows the sensors that exist, so no slot is taken before every
-- shown DoT has a working sensor for it.
function DT:UpdateCap()
    self.slots:SetCap(Rules.UsableCap(self.db.MaxEnemies or 20, self.cells, #self.list))
end

function DT:OnPlateUnitEvent(slots, event, unit)
    if event == "UNIT_THREAT_LIST_UPDATE"
        and not Rules.WantsThreatScan(slots:SlotOf(unit) ~= nil, slots:Total(), slots:Cap()) then
        return
    end
    slots:QueueScan()
end

function DT:EnsureCounting()
    if self.slots then return end
    self.slots = KE.PlateSlots.New({
        verdict = Verdict,
        relax = function() return DT.inCombat end,
        cap = 0,
        onTake = function(slot, unit) DT:BindSlot(slot, unit) end,
        onRelease = function(slot, unit) DT:UnbindSlot(slot, unit) end,
        onScanDone = function(total) DT:OnScanDone(total) end,
        tickSeconds = TICK_SECONDS,
        unitEvents = UNIT_EVENTS,
        onUnitEvent = function(slots, event, unit) DT:OnPlateUnitEvent(slots, event, unit) end,
    })
    self.runner = KE.PlateSlots.NewBuildRunner({
        buildSlot = function(slot) return DT:BuildSlot(slot) end,
        onProgress = function() DT:UpdateCap() end,
    })
end

---------------------------------------------------------------------------------
-- Apply
---------------------------------------------------------------------------------
function DT:CreateRoot()
    if self.root then return end
    local size = self.db.IconSize or 40
    local root = CreateFrame("Frame", "KE_DoTTrackerFrame", UIParent)
    root:SetSize(size, size)
    root:SetFrameStrata(self.db.Strata or "MEDIUM")
    root:Hide()
    measureFS = root:CreateFontString(nil, "BACKGROUND")
    measureFS:SetAlpha(0)
    self.root = root
    KE:ApplyFramePosition(root, self.db.Position, self.db)
end

function DT:ResolveList()
    local _, class = UnitClass("player")
    local specID = KE:GetPlayerSpecId()
    return Rules.ResolveList(KE.DOT_TRACKER_SEEDS, self.db.Spells, class, specID, IsKnown), class, specID
end

-- `list` comes from Rules.PlanApply, so a changed id reaches Refilter only with
-- the gate's yes.
function DT:Apply(list, allowed)
    local db = self.db
    -- A changed list starts with every slot retaken; a look-only change keeps
    -- the sensors bound. The scan Stop reports must not raise the build target
    -- for the list being replaced.
    if self.slots and not Rules.SameList(list, self.list) then
        self.applying = true
        self.slots:Stop()
        self.applying = false
    end

    for i = 1, #list do
        local cell = self.cells[i] or NewCell(i)
        if cell.id == nil then
            cell.id = list[i]
        elseif cell.id ~= list[i] then
            Refilter(cell, list[i])
        end
        cell.frame:Show()
    end
    for i = #list + 1, #self.cells do
        RetireCell(self.cells[i])
    end
    self.list = list

    self.someColor = { KE:ResolveColor(db.SomeColor, DEFAULT_SOME) }
    self.allColor = { KE:ResolveColor(db.AllColor, DEFAULT_ALL) }
    self.root:SetFrameStrata(db.Strata or "MEDIUM")
    KE:ApplyFramePosition(self.root, db.Position, db)
    local geo = Geometry(db)
    for i = 1, #list do
        if not pcall(StyleCell, self.cells[i], geo) and DEBUG_DOT then
            KE:Print("[DOT] style refused for " .. tostring(self.cells[i].id))
        end
    end
    LayoutCells()
    self:StyleTimers(list, TimerStyleKey(db), allowed)

    local listKey = table_concat(list, ",") .. "@" .. tostring(db.MaxEnemies)
    if self.active and listKey ~= self.listKey then
        -- A new list or cap builds from 8 again; sensors a cell already has are
        -- kept and count at once.
        self.listKey = listKey
        self.runner:Cancel()
        self.buildTarget = 0
        self.applying = true
        self.slots:SetCap(0)
        self.applying = false
    end
    self.paintedTotal = -1
    self:OnScanDone(self.slots and self.slots:Total() or 0)
    if self.previewing then self:PaintPreview() end
    self:UpdateLive()
end

function DT:UpdateLive()
    if not self.root then return end
    local db = self.db
    local live = self.active and not self.previewing and (self.inCombat or db.OnlyInCombat == false)
    local plainIcon = self.previewing or db.HideEmpty == false
    for i = 1, #self.list do
        local cell = self.cells[i]
        cell.icon:SetShown(plainIcon)
        cell.border:SetShown(plainIcon)
        -- A hidden window switches its sensors off: a container that is not
        -- visible drops its aura events.
        cell.view:SetShown(not self.previewing)
        cell.over:SetShown(self.previewing)
    end
    self.root:SetShown(live or (self.previewing and #self.list > 0))
    self:UpdateTimers()
    if self.slots then
        if live then self.slots:Start() else self.slots:Stop() end
    end
end

---------------------------------------------------------------------------------
-- Gate and lifecycle
---------------------------------------------------------------------------------
function DT:NeedsRefilter(wanted)
    for i = 1, math_min(#wanted, #self.cells) do
        local id = self.cells[i].id
        if id ~= nil and id ~= wanted[i] then return true end
    end
    return false
end

-- Every gate request goes through here, so the drain's events follow right
-- after.
function DT:Evaluate()
    -- No gate means OnEnable stopped at the Enabled flag: nothing to run.
    if not self:IsEnabled() or not self.gate then return end
    self:Reconcile()
    self:SyncGateEvents()
end

-- The drain needs its events whenever work waits on the gate, active or not:
-- an activation the gate refused (pooled cells to re-point) is owed too.
function DT:SyncGateEvents()
    local want = self.active or self.gate:IsPending("general")
    if want == self.gateEventsOn then return end
    self.gateEventsOn = want
    if want then
        self:RegisterEvent("PLAYER_REGEN_DISABLED", "OnRegenDisabled")
        self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnRegenEnabled")
        self:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED", "OnRestrictionChanged")
    else
        self:UnregisterEvent("PLAYER_REGEN_DISABLED")
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        self:UnregisterEvent("ADDON_RESTRICTION_STATE_CHANGED")
    end
end

function DT:Reconcile()
    local wanted, class, specID = self:ResolveList()
    if #wanted > 0 and not ContainersAvailable() then
        if DEBUG_DOT then KE:Print("[DOT] aura containers unavailable") end
        -- Nothing can be built, so an earlier refusal has nothing left to drain.
        self.gate:Cancel()
        return self:Deactivate()
    end
    local list, allowed = Rules.PlanApply(self.active and self.list or NONE, wanted,
        self:NeedsRefilter(wanted), self:TimersOwed(wanted, TimerStyleKey(self.db)), self.requestGate)
    -- A yes, or nothing gated owed, means this pass applies the settings as
    -- they are: an earlier refusal (a DoT since removed, say) is moot.
    if allowed then self.gate:Cancel() end
    if DEBUG_DOT then
        KE:Print(("[DOT] class=%s spec=%s dots=%d %s"):format(tostring(class), tostring(specID), #wanted,
            list == wanted and "applied" or "waits for the restriction to lift"))
    end
    if not list then return end
    if #list == 0 then return self:Deactivate() end
    self:Activate(list, allowed)
end

function DT:Activate(list, allowed)
    self:CreateRoot()
    self:RegWithEditMode()
    self:EnsureCounting()
    local starting = not self.active
    if starting then
        self.active = true
        self.inCombat = Ask(UnitAffectingCombat, "player") == true
    end
    if self.db.TimerEnabled ~= false then
        self:RegisterEvent("PLAYER_TARGET_CHANGED", "UpdateTimers")
        self:RegisterEvent("UNIT_FACTION", "OnUnitFaction")
    else
        self:UnregisterEvent("PLAYER_TARGET_CHANGED")
        self:UnregisterEvent("UNIT_FACTION")
    end
    self:Apply(list, allowed)
    if starting and KE.EditMode then KE.EditMode:RefreshLiveState() end
end

-- The combat and restriction events go with Evaluate's SyncGateEvents, which
-- every caller of this runs next (OnDisable drops them all).
function DT:Deactivate()
    local wasActive = self.active
    self.active = false
    self:UnregisterEvent("PLAYER_TARGET_CHANGED")
    self:UnregisterEvent("UNIT_FACTION")
    if self.runner then self.runner:Cancel() end
    if self.slots then self.slots:Stop() end
    self.buildTarget = 0
    self.listKey = nil
    self.list = {}
    for _, cell in ipairs(self.cells) do
        RetireCell(cell)
    end
    if self.root then self.root:Hide() end
    if wasActive and KE.EditMode then KE.EditMode:RefreshLiveState() end
end

local function DrainHandler()
    if DEBUG_DOT then KE:Print("[DOT] restriction lifted: applying what waited") end
    DT:Evaluate()
end

local DRAIN_HANDLERS = { general = DrainHandler }

function DT:DrainGate()
    if self.gate then self.gate:Drain(DRAIN_HANDLERS) end
end

local function DrainNextFrame()
    if DT:IsEnabled() then DT:DrainGate() end
end

function DT:OnRestrictionChanged()
    C_Timer.After(0, DrainNextFrame)
end

function DT:OnRegenDisabled()
    self.inCombat = true
    self:UpdateLive()
end

-- Leaving combat is a second chance to drain owed work; the restriction event
-- is the first.
function DT:OnRegenEnabled()
    self.inCombat = false
    self:UpdateLive()
    self:DrainGate()
end

local function SettleNow()
    DT.specTimer = nil
    DT:Evaluate()
end

-- Now and once more after the spec has settled: the first read can still
-- report the previous spec.
function DT:OnSpecChanged(event, unit)
    if event == "PLAYER_SPECIALIZATION_CHANGED" and unit ~= "player" then return end
    self:Evaluate()
    if self.specTimer then self.specTimer:Cancel() end
    self.specTimer = C_Timer.NewTimer(SPEC_SETTLE_DELAY, SettleNow)
end

local function ReResolveNow()
    DT.reResolveQueued = false
    DT:ReResolve()
end

function DT:OnSpellsChanged()
    if self.reResolveQueued then return end
    self.reResolveQueued = true
    C_Timer.After(0, ReResolveNow)
end

function DT:ReResolve()
    if not self:IsEnabled() then return end
    if Rules.SameList(self:ResolveList(), self.list) then return end
    self:Evaluate()
end

local function ApplyQueued()
    DT.applyQueued = false
    if not DT:IsEnabled() then return end
    DT:UpdateDB()
    DT:Evaluate()
end

-- A dragged slider asks many times a frame; one pass on the next frame answers
-- all of them.
function DT:ApplySettings()
    if not self:IsEnabled() or self.applyQueued then return end
    self.applyQueued = true
    C_Timer.After(0, ApplyQueued)
end

function DT:OnEnable()
    self:UpdateDB()
    if not self.db.Enabled then return end
    self.gate = self.gate or KE.AuraRestriction.New({})
    self.requestGate = self.requestGate or function() return DT.gate:Request("general") end
    self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", "OnSpecChanged")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnSpecChanged")
    self:RegisterEvent("TRAIT_CONFIG_UPDATED", "OnSpellsChanged")
    self:RegisterEvent("SPELLS_CHANGED", "OnSpellsChanged")
    self:Evaluate()
end

function DT:OnDisable()
    self:Deactivate()
    self:UnregisterAllEvents()
    self.gateEventsOn = false
    if self.specTimer then
        self.specTimer:Cancel()
        self.specTimer = nil
    end
    if self.gate then self.gate:Cancel() end
    self:HidePreview()
    -- Clearing the guard is what lets a later enable register again.
    if KE.EditMode then KE.EditMode:UnregisterElement("DoTTracker") end
    self.editModeRegistered = false
end

---------------------------------------------------------------------------------
-- Edit Mode and preview
---------------------------------------------------------------------------------
function DT:RegWithEditMode()
    if not KE.EditMode or self.editModeRegistered then return end
    self:CreateRoot()
    KE.EditMode:RegisterElement({
        key = "DoTTracker",
        displayName = "DoT Tracker",
        frame = self.root,
        module = self,
        getPosition = function() return self.db.Position end,
        setPosition = function(pos)
            self.db.Position = pos
            KE:ApplyFramePosition(self.root, self.db.Position, self.db)
        end,
        getParentFrame = function()
            return KE:ResolveAnchorFrame(self.db.anchorFrameType, self.db.ParentFrame)
        end,
        guiPath = "ClassTools",
        guiTab = "DoTTracker",
        isEligible = function() return #self.list > 0 end,
    })
    self.editModeRegistered = true
end

function DT:PaintPreview()
    local db = self.db
    for i = 1, #self.list do
        local cell = self.cells[i]
        local k = SAMPLE_LIT[((i - 1) % #SAMPLE_LIT) + 1]
        local color = Rules.LabelColorKey(k, SAMPLE_TOTAL) == "all" and self.allColor or self.someColor
        cell.sample:SetTextColor(color[1], color[2], color[3], color[4])
        cell.sample:SetText(Rules.Label(k, SAMPLE_TOTAL, db.CountFormat))
        cell.sample:Show()
        cell.sampleTimer:SetText(SAMPLE_TIMERS[((i - 1) % #SAMPLE_TIMERS) + 1])
        cell.sampleTimer:SetShown(db.TimerEnabled ~= false)
        if db.GlowEnabled and k == SAMPLE_TOTAL then
            KE.AuraGlow.Configure(cell.previewGlow, db, cell.geo.size, cell.geo.size)
        else
            KE.AuraGlow.Configure(cell.previewGlow, GLOW_OFF)
        end
    end
end

-- Set even with nothing to show: the manager does not ask again while the page
-- stays open, so a DoT added there has to find the preview already on.
function DT:ShowPreview()
    if not self:IsEnabled() then return end
    self.previewing = true
    if self.active then
        self:PaintPreview()
        self:UpdateLive()
    else
        self:Evaluate()
    end
end

function DT:HidePreview()
    if not self.previewing then return end
    self.previewing = false
    for _, cell in ipairs(self.cells) do
        cell.sample:Hide()
        cell.sampleTimer:Hide()
        KE.AuraGlow.Configure(cell.previewGlow, GLOW_OFF)
    end
    if self.active then
        self:UpdateLive()
    elseif self.root then
        self.root:Hide()
    end
end
