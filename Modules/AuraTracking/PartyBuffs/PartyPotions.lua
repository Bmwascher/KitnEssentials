-- ╔══════════════════════════════════════════════════════════╗
-- ║  PartyPotions.lua                                        ║
-- ║  Purpose: party potion bars in one movable box.          ║
-- ╚══════════════════════════════════════════════════════════╝
--
-- Each row is one sensor slot of the party cooldowns pipeline, drawn as a bar.
-- Every bound member keeps one place in party order: the gap an ended bar
-- leaves cannot be closed, since that needs a range narrower than the client
-- draws.

---@class KE
local KE = select(2, ...)

local C_ClassColor = C_ClassColor
local C_Spell = C_Spell
local CreateFrame = CreateFrame
local UIParent = UIParent
local UnitClass = UnitClass
local UnitExists = UnitExists
local UnitName = UnitName
local ipairs = ipairs
local math_floor = math.floor
local math_max = math.max
local pairs = pairs
local pcall = pcall
local string_format = string.format
local type = type

local Rules = KE.PartyPotionsRules
local CDRules = KE.PartyCooldownsRules
local Bar = KE.PartyPotionsBar
local Track = KE.PartyCooldownsSensor

local Pot = { rows = {}, byToken = {}, samples = {}, style = {} }
KE.PartyPotions = Pot

-- Flip to true, /reload, repro, read the log.
local DEBUG_PP = false

-- Box order, from the top (from the bottom when growing up).
local ORDER = { "player", "party1", "party2", "party3", "party4" }
-- Reads wait out a roster change, longer than the module's 0.5 s settle, so a
-- token that now names someone else is never read before the settle decides.
local ROSTER_HOLD = 1
local GRAY = { 0.5, 0.5, 0.5 }
local BOX_CONFIG = { anchorFrameType = "UIPARENT", Strata = "MEDIUM" }

-- Preview rows: class, name, share of the length left.
local SAMPLES = {
    { class = "DEATHKNIGHT", name = "Death Knight", left = 0.95 },
    { class = "DRUID",       name = "Druid",        left = 0.74 },
    { class = "MAGE",        name = "Mage",         left = 0.52 },
    { class = "HUNTER",      name = "Hunter",       left = 0.31 },
    { class = "PRIEST",      name = "Priest",       left = 0.12 },
}

local EDIT_MODE_ELEMENT = {
    key = "PartyPotions",
    displayName = "Party Potions",
    guiPath = "PartyBuffs",
    guiTab = "PartyBuffsPotions",
}

local function Debug(fmt, ...)
    if DEBUG_PP then KE:Print("Party Potions: " .. string_format(fmt, ...)) end
end

local function IsSecret(v) return KE:IsSecretValue(v) end

local function Exists(token) return UnitExists(token) == true end

local function Texture(id)
    local texture = C_Spell.GetSpellTexture(id)
    if KE:IsSecretValue(texture) then return nil end
    return texture
end

local function ClassColor(class)
    local c = C_ClassColor.GetClassColor(class)
    if not c then return GRAY end
    return { c.r, c.g, c.b }
end

-- The name may be secret: it only reaches SetText. A class the game hides
-- gives a gray bar.
local function Who(token)
    local name
    local ok, value = pcall(UnitName, token)
    if ok then name = value end
    local color = GRAY
    local okClass, _, class = pcall(UnitClass, token)
    if okClass and not KE:IsSecretValue(class) and type(class) == "string" then color = ClassColor(class) end
    return name, color
end

---------------------------------------------------------------------------------
-- The box and its rows
---------------------------------------------------------------------------------
local function MakeBox()
    if Pot.box then return end
    Pot.box = CreateFrame("Frame", "KitnEssentialsPartyPotions", UIParent)
    Pot.box:SetFrameStrata("MEDIUM")
    Pot.box:Hide()
end

local function NewLayer()
    local layer = CreateFrame("Frame", nil, Pot.box)
    layer:SetAllPoints(Pot.box)
    return layer
end

local function Corners()
    if Pot.style.up then return "BOTTOMLEFT", "TOPLEFT" end
    return "TOPLEFT", "BOTTOMLEFT"
end

-- Placed rows one after another, anchored to each other.
local function Stack()
    local corner, far = Corners()
    local gap = Pot.style.up and Pot.style.spacing or -Pot.style.spacing
    local prev
    for _, row in ipairs(Pot.rows) do
        local c = row.bar
        if c.placed then
            c:ClearAllPoints()
            if prev then
                c:SetPoint(corner, prev, far, 0, gap)
            else
                c:SetPoint(corner, Pot.live, corner, 0, 0)
            end
            prev = c
        end
    end
end

-- Made at the first activation. Each bar exists before any value reaches it,
-- so every fill texture its clips and strips anchor to is fetched while plain.
-- The rows' sensors get a host of their own, shown only while Potion Bars is
-- on and the gate is open: hiding it stops a sensor whose disable was refused.
local function MakeRows()
    if Pot.rows[1] then return end
    Pot.live = NewLayer()
    local host = CreateFrame("Frame", nil, UIParent)
    host:SetSize(1, 1)
    host:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
    host:Hide()
    Pot.sensorHost = host
    for r, token in ipairs(ORDER) do
        local st = Track.NewSlot(Pot.live, Bar, host)
        local bar = Bar.New(Pot.live)
        st.cells[1] = bar
        local row = { token = token, st = st, bar = bar, bound = false }
        Pot.rows[r], Pot.byToken[token] = row, row
    end
end

-- The rows are stacked again by Pot.ApplySettings and re-dressed at the drain
-- that follows it.
local function Restyle(db)
    local s = Pot.style
    s.width, s.height, s.spacing = db.PotionWidth, db.PotionHeight, db.PotionSpacing
    s.icon, s.timer = db.PotionShowIcon == true, db.PotionShowTimer == true
    s.fontName, s.outline, s.textSize = db.FontFace, db.FontOutline, db.PotionTextSize
    s.up = db.PotionGrowth == "UP"
    local box = Pot.box
    box:SetSize(s.width, #ORDER * (s.height + s.spacing) - s.spacing)
    KE:ApplyFramePosition(box, db.PotionPosition, BOX_CONFIG)
end

-- Registering again would cancel a drag in progress.
local function Register()
    if Pot.registered then return end
    local cfg = {}
    for k, v in pairs(EDIT_MODE_ELEMENT) do cfg[k] = v end
    cfg.frame = Pot.box
    cfg.module = Pot.pb
    cfg.getPosition = function() return Pot.pb.db.PotionPosition end
    cfg.setPosition = function(pos)
        local p = Pot.pb.db.PotionPosition
        p.AnchorFrom, p.AnchorTo = pos.AnchorFrom, pos.AnchorTo
        p.XOffset, p.YOffset = pos.XOffset, pos.YOffset
        KE:ApplyFramePosition(Pot.box, p, BOX_CONFIG)
    end
    KE.EditMode:RegisterElement(cfg)
    Pot.registered = true
end

local function Unregister()
    if not Pot.registered then return end
    KE.EditMode:UnregisterElement(EDIT_MODE_ELEMENT.key)
    Pot.registered = nil
end

local function Show()
    local box = Pot.box
    if not box then return end
    if Pot.live then Pot.live:SetShown(not Pot.previewing) end
    if Pot.sampleLayer then Pot.sampleLayer:SetShown(Pot.previewing == true) end
    box:SetShown(Pot.on == true and (Pot.active == true or Pot.previewing == true))
end

---------------------------------------------------------------------------------
-- Binding
---------------------------------------------------------------------------------
local function Unbind(row)
    if not row.bound then return end
    Track.Unbind(row.st)
    row.bound, row.guid = false, nil
end

-- A refused call is tried again at the drain (Pot.OnRelease); the build queue
-- makes the row's sensor, one per frame.
local function Bind(row)
    local entry = Pot.entry
    local name, color = Who(row.token)
    local e = {
        id = entry.id, kind = entry.kind, buffs = entry.buffs, cd = entry.cd,
        texture = entry.texture, name = name, color = color,
    }
    Debug("bind %s", row.token)
    Track.Apply(row.st, row.token, { e }, Pot.style)
    row.bound = true
    row.guid = KE:GetSafeUnitGUID(row.token)
    Bar.SetReady(row.bar, Pot.pb.db.PotionShowReady == true)
    if Track.Missing(row.st) then Pot.pb:Enqueue(row.token) end
end

-- While the module's roster settle runs a token may name someone else, so no
-- row binds; the settle's drain resolves them.
local function Settling()
    return Pot.pb._rosterTimer ~= nil
end

-- Binds the rows the party has and unbinds the rest. After a roster change a
-- row keeps its count only while the game still names the same member there.
function Pot.Resolve()
    if not (Pot.on and Pot.active and Pot.rows[1]) or Settling() then return end
    local want = {}
    if Pot.entry then
        for _, token in ipairs(Rules.Tokens(Pot.pb.db.PotionIncludeSelf == true, Exists)) do want[token] = true end
    end
    local roster = Pot.rosterPending
    Pot.rosterPending = false
    for _, row in ipairs(Pot.rows) do
        if want[row.token] then
            if roster and row.bound
                and not Rules.KeepOnRoster(row.guid, KE:GetSafeUnitGUID(row.token), IsSecret) then
                Track.Reset(row.st)
            end
            Bind(row)
        else
            Unbind(row)
        end
    end
    Stack()
end

-- A token may name someone else until the module's roster settle ends: reads
-- wait, and the first resolve after it decides which counts stay.
function Pot.OnRoster()
    if not (Pot.on and Pot.active) then return end
    Pot.rosterPending = true
    for _, row in ipairs(Pot.rows) do
        if row.bound then Track.Hold(row.st, ROSTER_HOLD) end
    end
end

-- Every bound row's count back to ready, drawn at once. The trackers stay, so
-- a clear during a roster settle shows at once and a key start then still
-- finds them.
local function ClearCounts()
    local n = Track.Now()
    for _, row in ipairs(Pot.rows) do
        local t = row.st.trackers[1]
        if t then
            CDRules.Clear(t, n)
            Track.Push(t, n)
        end
    end
end

-- A committed potion list change clears every bar, even one whose buffs did
-- not change.
function Pot.ClearAll()
    ClearCounts()
end

-- A key's start clears every bar; the module's hold covers the reads.
function Pot.OnKeyStart()
    if not (Pot.on and Pot.active) then return end
    ClearCounts()
end

function Pot.OnRelease()
    Pot.Resolve()
end

-- The build queue's call for a token key. Returns true when the row needs no
-- more builds; a build refused, or skipped because the aura container code
-- cannot load, waits for the drain.
function Pot.BuildNext(token)
    local row = Pot.byToken[token]
    if not (row and row.bound and Pot.on and Pot.active) or Settling() then return true end
    if not Track.Missing(row.st) then return true end
    if not KE:AuraContainersAvailable() then
        Debug("%s: aura containers unavailable", token)
        return true
    end
    local made = Track.BuildNext(row.st)
    Bind(row)
    Stack()
    if not made then return true end
    return not Track.Missing(row.st)
end

---------------------------------------------------------------------------------
-- Preview
---------------------------------------------------------------------------------
local function ForgetSamples()
    for _, sample in ipairs(Pot.samples) do
        if sample.t then
            Track.Forget(sample.t)
            sample.t = nil
        end
        sample.bar:Hide()
    end
end

-- Plain sample bars stacked in the box, counting down and starting again.
-- The preview is redrawn on every roster, resolve and settings change, so a
-- sample keeps its count unless its ready state changed.
local function DrawSamples()
    Pot.sampleLayer = Pot.sampleLayer or NewLayer()
    local s, entry = Pot.style, Pot.entry
    local cd = Rules.SECONDS
    local texture = entry and entry.texture or Rules.FALLBACK_ICON
    local showReady = Pot.pb.db.PotionShowReady == true
    local corner = Corners()
    local step = (s.height + s.spacing) * (s.up and 1 or -1)
    local n = Track.Now()
    for i, info in ipairs(SAMPLES) do
        local sample = Pot.samples[i]
        if not sample then
            sample = { bar = Bar.New(Pot.sampleLayer) }
            Pot.samples[i] = sample
        end
        local bar = sample.bar
        Bar.Dress(bar, s, { texture = texture, cd = cd, name = info.name, color = ClassColor(info.class) })
        bar:ClearAllPoints()
        bar:SetPoint(corner, Pot.sampleLayer, corner, 0, (i - 1) * step)
        local ready = showReady and i == #SAMPLES
        Bar.SetReady(bar, ready)
        if not (sample.t and sample.ready == ready) then
            if sample.t then Track.Forget(sample.t) end
            local t = CDRules.NewTracker(cd, false)
            t.cell, t.view = bar, Bar
            if ready then
                CDRules.Clear(t, n)
            else
                t.loop = math_max(1, math_floor(cd * info.left))
                CDRules.StartLoop(t, n)
            end
            Track.Push(t, n)
            Track.Watch(t)
            sample.t, sample.ready = t, ready
        end
        bar:Show()
    end
end

function Pot.ShowPreview()
    if not (Pot.on and Pot.box) then return end
    Pot.previewing = true
    DrawSamples()
    Show()
end

function Pot.HidePreview()
    if not Pot.previewing then return end
    Pot.previewing = false
    ForgetSamples()
    Show()
end

---------------------------------------------------------------------------------
-- Lifecycle, driven by the Party Cooldowns module
---------------------------------------------------------------------------------
local function UnbindAll()
    Pot.rosterPending = false
    for _, row in ipairs(Pot.rows) do Unbind(row) end
    if Pot.sensorHost then Pot.sensorHost:Hide() end
end

-- Off: no row is bound, no sensor runs, nothing is queued or drawn, and the
-- mover is gone. Frames already made stay hidden.
local function TurnOff()
    Pot.on = false
    UnbindAll()
    ForgetSamples()
    Pot.previewing = false
    Unregister()
    if Pot.box then Pot.box:Hide() end
end

function Pot.Enable(pb)
    Pot.pb = pb
end

function Pot.Disable()
    Pot.active = false
    TurnOff()
end

-- Binding and the samples are left to the module: every caller is followed in
-- the same call by its drain, which resolves the rows, and a settings change
-- by its preview redraw while the preview is up.
function Pot.ApplySettings()
    local pb = Pot.pb
    if not pb then return end
    local db = pb.db
    if not (db.PotionBars == true and Track) then return TurnOff() end
    Pot.on = true
    MakeBox()
    Pot.entry = Rules.Entry(KE.AuraRules.BuildIncludeSpellIDs(db.ListPotions), Texture)
    if Pot.active then
        MakeRows()
        Pot.sensorHost:Show()
    end
    Restyle(db)
    Register()
    if Pot.active then Stack() end
    Show()
end

function Pot.Activate()
    Pot.active = true
    Pot.ApplySettings()
end

function Pot.Deactivate()
    Pot.active = false
    UnbindAll()
    Show()
end
