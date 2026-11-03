-- ╔══════════════════════════════════════════════════════════╗
-- ║  PartySkips.lua                                          ║
-- ║  Purpose: Shroud, Mass Invisibility and Invisibility     ║
-- ║           Potion countdown bars in one movable box.      ║
-- ╚══════════════════════════════════════════════════════════╝
--
-- Nothing here reads an aura. Blizzard aura containers draw each bar's icon,
-- fill and seconds, and KE only dresses the buttons. A container watches one
-- unit, so there are two: one on the party's rogue for Shroud, one on the
-- player for the rest. The buttons deny tainted access while auras are
-- secret, so every touch of a container or a button after creation is a
-- pcall.

---@class KE
local KE = select(2, ...)

local AnchorUtil = AnchorUtil
local C_Spell = C_Spell
local CreateFrame = CreateFrame
local UIParent = UIParent
local UnitClass = UnitClass
local ipairs = ipairs
local math_max = math.max
local pairs = pairs
local pcall = pcall
local string_format = string.format
local type = type

local Cell = KE.PartyCooldownsCell
local PBRules = KE.PartyBuffsRules
local HXRules = KE.HealerExternalsRules
local Rules = KE.PartySkipsRules

local Skip = { style = { colors = {} }, samples = {} }
KE.PartySkips = Skip

Skip.QUEUE_KEY = "partySkips"
-- The box's starting place while a Select Frame anchor cannot be used: the
-- profile's own default.
Skip.DEFAULT_POSITION = { AnchorFrom = "TOPLEFT", AnchorTo = "LEFT", XOffset = 1, YOffset = 70 }

-- Flip to true, /reload, repro, read the log.
local DEBUG_PS = false

local WHITE = "Interface\\Buttons\\WHITE8X8"
local PLACEHOLDER_ICON = 134400
local TEXT_PAD = 4
-- #080808 at 80%, the Potion bars' default background.
local BACKGROUND = { 0.031, 0.031, 0.031, 0.80 }
-- Leaves out any long or permanent aura that shares an ID.
local MAX_DURATION = 60
-- Without a direction the fill shows the elapsed share and grows.
local BAR_OPTIONS = {
    interpolation = Enum.StatusBarInterpolation.Immediate,
    direction = Enum.StatusBarTimerDirection.RemainingTime,
}
-- Tenths under ten seconds, whole seconds from ten up.
local TIMER_SETTINGS = { DecimalThreshold = 10 }
local SAMPLE_FILL = 0.6
local SAMPLE_SECONDS = "9.4"

-- Box order from the top (from the bottom when growing up). The potion's buff
-- shares its ID with no long aura, so it takes no duration limit.
local SHROUD = { key = "shroud", name = "Shroud of Concealment", onKey = "SkipShroud",
    colorKey = "SkipShroudColor", ids = { [114018] = true }, icon = 114018, maxDuration = MAX_DURATION }
local INVIS = { key = "invis", name = "Mass Invisibility", onKey = "SkipMassInvis",
    colorKey = "SkipMassInvisColor", ids = { [414664] = true }, icon = 414664, maxDuration = MAX_DURATION }
local POTION = { key = "potion", name = "Invisibility Potion", onKey = "SkipPotion",
    colorKey = "SkipPotionColor", ids = { [1236551] = true }, icon = 1236551 }
local SPELLS = { SHROUD, INVIS, POTION }

-- Shroud is read on the party's first rogue, or on you on a rogue: the copy
-- the rest of the party gets has no duration, so it has no time to show. A
-- spell's place in its container's list is its group's layoutIndex.
Skip.rogue = { key = "rogue", name = "KitnEssentialsPartySkipsShroud", spells = { SHROUD }, groups = {}, pin = {} }
Skip.mine = { key = "mine", name = "KitnEssentialsPartySkipsContainer", spells = { INVIS, POTION },
    groups = {}, pin = {} }
local HOLDERS = { Skip.rogue, Skip.mine }

local EDIT_MODE_ELEMENT = {
    key = "PartySkips",
    displayName = "Skip Bars",
    guiPath = "PartyBuffs",
    guiTab = "PartyBuffsSkips",
}

local function Debug(fmt, ...)
    if DEBUG_PS then KE:Print("Party Skips: " .. string_format(fmt, ...)) end
end

local function SpellOn(db, spell) return db[spell.onKey] == true end

local function Count(db)
    local n = 0
    for _, spell in ipairs(SPELLS) do
        if SpellOn(db, spell) then n = n + 1 end
    end
    return n
end

local function HolderOn(db, holder)
    for _, spell in ipairs(holder.spells) do
        if SpellOn(db, spell) then return true end
    end
    return false
end

local function Texture(id)
    local texture = C_Spell.GetSpellTexture(id)
    if texture == nil or KE:IsSecretValue(texture) then return PLACEHOLDER_ICON end
    return texture
end

-- The corner the bars grow away from.
local function Corner()
    return Skip.style.up and "BOTTOMLEFT" or "TOPLEFT"
end

-- While Shroud is on it keeps the first place, rogue or not, so the player's
-- bars start one place further along the growth.
local function RowOffset(holder, db)
    if holder ~= Skip.mine or not SpellOn(db, SHROUD) then return 0 end
    local s = Skip.style
    return (s.height + s.gap) * (s.up and 1 or -1)
end

-- A class the game hides counts as unknown.
local function PlainClass(token)
    local ok, _, class = pcall(UnitClass, token)
    if ok and not KE:IsSecretValue(class) and type(class) == "string" then return class end
    return false
end

local partyClasses = {}

-- The unit a container reads: the rogue's for Shroud, nil when the party has
-- none; the player's for the rest.
local function UnitFor(holder)
    if holder ~= Skip.rogue then return "player" end
    for i, token in ipairs(Rules.TOKENS) do partyClasses[i] = PlainClass(token) end
    return Rules.RogueToken(PlainClass("player"), partyClasses)
end

---------------------------------------------------------------------------------
-- Bar regions, shared by the live buttons and the plain preview frames
---------------------------------------------------------------------------------
local function PlaceEdges(frame, edges, px)
    for i = 1, 4 do edges[i]:ClearAllPoints() end
    edges[1]:SetPoint("TOPLEFT", frame, "TOPLEFT")
    edges[1]:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", 0, -px)
    edges[2]:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, px)
    edges[2]:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT")
    edges[3]:SetPoint("TOPLEFT", frame, "TOPLEFT")
    edges[3]:SetPoint("BOTTOMRIGHT", frame, "BOTTOMLEFT", px, 0)
    edges[4]:SetPoint("TOPLEFT", frame, "TOPRIGHT", -px, 0)
    edges[4]:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT")
end

-- Made in one go: a region parented to a live button after its
-- initializeFrame returns has no legal window. The texts sit on a frame above
-- the fill, so the fill never covers them.
local function MakeRegions(frame)
    local r = { edges = {} }
    for i = 1, 4 do
        r.edges[i] = frame:CreateTexture(nil, "BACKGROUND")
        r.edges[i]:SetColorTexture(0, 0, 0, 1)
    end
    r.back = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
    r.back:SetColorTexture(BACKGROUND[1], BACKGROUND[2], BACKGROUND[3], BACKGROUND[4])
    r.icon = frame:CreateTexture(nil, "ARTWORK")
    KE:ApplyIconZoom(r.icon)
    r.bar = CreateFrame("StatusBar", nil, frame)
    r.bar:SetStatusBarTexture(WHITE)
    r.bar:SetMinMaxValues(0, 1)
    r.bar:SetValue(0)
    r.top = CreateFrame("Frame", nil, frame)
    r.top:SetAllPoints(frame)
    r.top:SetFrameLevel(r.bar:GetFrameLevel() + 1)
    r.name = r.top:CreateFontString(nil, "OVERLAY")
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
    r.timer = r.top:CreateFontString(nil, "OVERLAY")
    r.timer:SetJustifyH("RIGHT")
    r.timer:SetTextColor(1, 1, 1, 1)
    frame.ksRegions = r
end

-- Size, frame, icon, fill and text places at the style. Every text gets its
-- font here, before anything writes to it. The seconds keep room for "0.0",
-- their widest under a minute.
local function Lay(frame, spell, s)
    local px = KE:GetPixelSize()
    local r = frame.ksRegions
    frame:SetSize(s.width, s.height)
    PlaceEdges(frame, r.edges, px)
    local inner = s.height - 2 * px
    r.icon:ClearAllPoints()
    r.icon:SetPoint("TOPLEFT", frame, "TOPLEFT", px, -px)
    r.icon:SetSize(inner, inner)
    r.icon:SetShown(s.showIcon)
    local left = s.showIcon and inner + px or px
    r.back:ClearAllPoints()
    r.back:SetPoint("TOPLEFT", frame, "TOPLEFT", left, -px)
    r.back:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -px, px)
    r.bar:ClearAllPoints()
    r.bar:SetAllPoints(r.back)
    local color = s.colors[spell.key]
    r.bar:SetStatusBarColor(color[1], color[2], color[3], color[4] or 1)
    KE:ApplyFontToText(r.name, s.fontName, s.textSize, s.outline)
    KE:ApplyFontToText(r.timer, s.fontName, s.textSize, s.outline)
    r.name:SetTextColor(1, 1, 1, 1)
    local reserve = s.showTimer and Cell.TextWidth(s.fontName, s.textSize, s.outline, "0.0") + TEXT_PAD or 0
    local textLeft = left + TEXT_PAD
    local textRight = s.width - px - TEXT_PAD - reserve
    r.name:ClearAllPoints()
    r.name:SetPoint("LEFT", frame, "LEFT", textLeft, 0)
    r.name:SetWidth(math_max(0, textRight - textLeft))
    r.name:SetShown(s.showName)
    r.timer:ClearAllPoints()
    r.timer:SetPoint("RIGHT", frame, "RIGHT", -px - TEXT_PAD, 0)
end

local timerOptions
local function TimerOptions()
    if not timerOptions then
        timerOptions = { textFormatter = KE.AuraStyle.GetDurationFormatter(TIMER_SETTINGS) }
    end
    return timerOptions
end

-- Each registration pairs with a clear, so every switch can be turned back
-- off; off, the string is emptied so nothing lingers.
local function RegisterRegions(button, s)
    local r = button.ksRegions
    if s.showIcon then
        button:SetIcon(r.icon)
    else
        button:ClearIcon()
    end
    if s.showTimer then
        r.timer:Show()
        button:SetDurationText(r.timer, TimerOptions())
    else
        button:ClearDurationText()
        r.timer:SetText("")
        r.timer:Hide()
    end
end

-- The game applies a button's restrictions only after initializeFrame
-- returns, so the plain writes here are allowed; a failure is a defect, and
-- the log names it.
local function DressButton(button, spell)
    MakeRegions(button)
    Lay(button, spell, Skip.style)
    button.ksRegions.name:SetText(spell.name)
    button:SetDurationBar(button.ksRegions.bar, BAR_OPTIONS)
    RegisterRegions(button, Skip.style)
end

-- The button is a Button and would stop a click meant for whatever sits under
-- it, so this runs first and on its own: a button whose dressing fails still
-- lets clicks through.
function Skip.ClickThrough(button)
    local click = pcall(button.SetMouseClickEnabled, button, false)
    local motion = pcall(button.SetMouseMotionEnabled, button, false)
    return click and motion
end

for _, spell in ipairs(SPELLS) do
    spell.dress = function(button)
        if not Skip.ClickThrough(button) then Debug("%s: click-through failed", spell.key) end
        if not pcall(DressButton, button, spell) then Debug("%s: button dressing failed", spell.key) end
    end
end

---------------------------------------------------------------------------------
-- The box
---------------------------------------------------------------------------------
local function NewLayer()
    local layer = CreateFrame("Frame", nil, Skip.box)
    layer:SetAllPoints(Skip.box)
    return layer
end

local function MakeBox()
    if Skip.box then return end
    Skip.box = CreateFrame("Frame", "KitnEssentialsPartySkips", UIParent)
    Skip.box:Hide()
    Skip.live = NewLayer()
    Skip.sampleLayer = NewLayer()
    Skip.sampleLayer:Hide()
end

local placement, screen = {}, { anchorFrameType = "UIPARENT" }

-- A Select Frame anchor the shared resolution refuses (unnamed, missing or
-- unsafe) takes the starting place on the screen. The third return says the
-- starting place is in use.
local function Placement(db)
    local kind, name = db.SkipAnchorFrameType, db.SkipParentFrame
    screen.Strata, placement.Strata = db.SkipStrata, db.SkipStrata
    if kind == "SELECTFRAME" and KE:ResolveSelectFrame(name, Skip.box) == nil then
        return Skip.DEFAULT_POSITION, screen, true
    end
    placement.anchorFrameType, placement.ParentFrame = kind, name
    return HXRules.PositionTable(db, "SkipPosition"), placement, false
end

-- A box anchored where the game restricts moves in combat is sized and placed
-- at the next drain instead. The box is as tall as the bars it can show, so
-- the mover covers them.
local function Place(db)
    if not KE:CanReanchorNow(Skip.box) then
        Skip.placePending = true
        return
    end
    Skip.placePending = nil
    local s = Skip.style
    Skip.box:SetSize(s.width, Count(db) * (s.height + s.gap) - s.gap)
    local pos, config = Placement(db)
    KE:ApplyFramePosition(Skip.box, pos, config)
end

local function Restyle(db)
    local s = Skip.style
    s.width, s.height = db.SkipWidth, db.SkipHeight
    s.gap = KE.PartyPotionsRules.Gap(db.SkipSpacing, KE:GetPixelSize())
    s.up = db.SkipGrowth == "UP"
    s.fontName, s.outline, s.textSize = db.FontFace, db.FontOutline, db.SkipTextSize
    s.showIcon, s.showName = db.SkipShowIcon == true, db.SkipShowName == true
    s.showTimer = db.SkipShowTimer == true
    for _, spell in ipairs(SPELLS) do s.colors[spell.key] = db[spell.colorKey] end
    Place(db)
end

-- Registering again would cancel a drag in progress.
local function Register()
    if Skip.registered then return end
    local cfg = {}
    for k, v in pairs(EDIT_MODE_ELEMENT) do cfg[k] = v end
    cfg.frame = Skip.box
    cfg.module = Skip.pb
    cfg.getPosition = function() return (Placement(Skip.pb.db)) end
    -- While the starting place stands in for an anchor Placement cannot use,
    -- the mover works on the screen: a moved position detaches the box, and
    -- the starting place handed back unchanged keeps the attachment.
    cfg.setPosition = function(pos)
        local db = Skip.pb.db
        local _, _, fallback = Placement(db)
        if HXRules.MoverDetaches(fallback, pos, Skip.DEFAULT_POSITION) then
            db.SkipAnchorFrameType, db.SkipParentFrame = "UIPARENT", nil
        elseif fallback then
            return Place(db)
        end
        local p = HXRules.PositionTable(db, "SkipPosition")
        p.AnchorFrom, p.AnchorTo = pos.AnchorFrom, pos.AnchorTo
        p.XOffset, p.YOffset = pos.XOffset, pos.YOffset
        Place(db)
    end
    cfg.getParentFrame = function()
        local _, config = Placement(Skip.pb.db)
        return KE:ResolveAnchorFrame(config.anchorFrameType, config.ParentFrame, Skip.box)
    end
    KE.EditMode:RegisterElement(cfg)
    Skip.registered = true
end

local function Unregister()
    if not Skip.registered then return end
    KE.EditMode:UnregisterElement(EDIT_MODE_ELEMENT.key)
    Skip.registered = nil
end

local function Show()
    local box = Skip.box
    if not box then return end
    Skip.live:SetShown(not Skip.previewing)
    Skip.sampleLayer:SetShown(Skip.previewing == true)
    box:SetShown(Skip.on == true and (Skip.active == true or Skip.previewing == true))
end

---------------------------------------------------------------------------------
-- The containers
---------------------------------------------------------------------------------
local function GroupLayout(index)
    local s = Skip.style
    return {
        elementWidth = s.width, elementHeight = s.height,
        elementSpacing = s.gap, lineSpacing = s.gap,
        groupSpacing = 0, forceNewLine = false,
        layoutIndex = index,
    }
end

-- The client wraps when (height + gap) + height exceeds the maximum, and
-- with a fractional negative gap that sum can land a hair above
-- 2 * height + gap. Half a bar of slack keeps bar 2 in the column and is too
-- small for a third bar to fit.
local function LineSize()
    local s = Skip.style
    return 2 * s.height + s.gap + s.height / 2
end

local function Pin(container, corner, y)
    container:ClearAllPoints()
    container:SetPoint(corner, Skip.live, corner, 0, y)
end

-- A refused setter is issued again at the next drain, which runs this again.
local function ApplyLayout(holder, db)
    local c, s = holder.container, Skip.style
    local flow = AnchorUtil.FlowDirection
    pcall(c.SetFlowLayoutGrowthDirection, c, flow.Right, s.up and flow.Up or flow.Down)
    -- The axis first: the anchor point and the line size are read against it.
    pcall(c.SetFlowLayoutAxis, c, AnchorUtil.FlowLayoutAxis.Vertical)
    local corner, y = Corner(), RowOffset(holder, db)
    pcall(c.SetFlowLayoutAnchorPoint, c, corner)
    pcall(c.SetFlowLayoutMaximumLineSize, c, LineSize())
    if PBRules.NeedsPin(holder.pin, corner, 0, y) then
        PBRules.RecordPin(holder.pin, pcall(Pin, c, corner, y), corner, 0, y)
    end
    -- Groups are add-only, so a spell switched off keeps its group at no bars.
    for i, spell in ipairs(holder.spells) do
        if holder.groups[spell.key] then
            pcall(c.SetAuraGroupLayout, c, spell.key, GroupLayout(i))
            pcall(c.SetAuraGroupMaxFrameCount, c, spell.key, (holder.watching and SpellOn(db, spell)) and 1 or 0)
        end
    end
end

-- Returns false when a touch was refused or the buttons cannot be touched
-- now; the drain tries again.
local function RestyleButtons()
    if KE:AreAuraIdentitiesHidden() then
        for _, holder in ipairs(HOLDERS) do
            if holder.container then return false end
        end
        return true
    end
    local clean = true
    for _, holder in ipairs(HOLDERS) do
        local c = holder.container
        for _, spell in ipairs(holder.spells) do
            if c and holder.groups[spell.key] then
                local okCount, count = pcall(c.GetAuraGroupFrameCount, c, spell.key)
                if okCount and type(count) == "number" then
                    for i = 1, count do
                        local okFrame, button = pcall(c.GetAuraGroupFrame, c, spell.key, i)
                        if not okFrame then
                            clean = false
                        elseif button and button.ksRegions then
                            if not pcall(Lay, button, spell, Skip.style) then clean = false end
                            if not pcall(RegisterRegions, button, Skip.style) then clean = false end
                        end
                    end
                else
                    clean = false
                end
            end
        end
    end
    return clean
end

local function Missing(holder, db)
    if not HolderOn(db, holder) then return false end
    if not holder.container then return true end
    for _, spell in ipairs(holder.spells) do
        if SpellOn(db, spell) and not holder.groups[spell.key] then return true end
    end
    return false
end

local function AnyMissing(db)
    for _, holder in ipairs(HOLDERS) do
        if Missing(holder, db) then return true end
    end
    return false
end

-- Pinned before any group exists, when a pin is certainly allowed; a refused
-- pin records nothing, so the layout pass pins it again.
local function Create(holder)
    local ok, c = pcall(CreateFrame, "AuraContainer", holder.name, Skip.live, "CustomAuraContainerTemplate")
    if not (ok and c) then
        Debug("%s: container failed", holder.key)
        return false
    end
    local corner, y = Corner(), RowOffset(holder, Skip.pb.db)
    PBRules.RecordPin(holder.pin, pcall(c.SetPoint, c, corner, Skip.live, corner, 0, y), corner, 0, y)
    pcall(c.EnableMouse, c, false)
    pcall(c.SetEnabled, c, false)
    holder.container = c
    return true
end

-- The group is registered before the call's last steps, so a late failure
-- leaves it in place; adding it again would assert.
local function AddGroup(holder, index, spell)
    local c = holder.container
    local ok = pcall(c.AddAuraGroup, c, spell.key, "HELPFUL", {
        candidateFilters = { includeSpellIDs = spell.ids, maxDuration = spell.maxDuration },
        maxFrameCount = 1,
        sortMethod = AuraContainerSortMethod.AuraInstanceIDOnly,
        sortDirection = AuraContainerSortDirection.Normal,
        initializeFrame = spell.dress,
        layout = GroupLayout(index),
    })
    if not ok then
        local okHas, has = pcall(c.HasAuraGroup, c, spell.key)
        ok = okHas and has == true
    end
    if ok then holder.groups[spell.key] = true end
    return ok
end

-- Lays one container out, points it at its unit and switches it on. With no
-- unit (no rogue in the party, or its spells all off) it is switched off and
-- keeps its last unit: a container on "none" can match a buff on any group
-- member. A refused call is tried again at the drain (Skip.OnRelease).
local function Bind(holder, db)
    local c = holder.container
    if not c then return end
    local unit = HolderOn(db, holder) and UnitFor(holder) or nil
    holder.watching = unit ~= nil
    ApplyLayout(holder, db)
    if not unit then
        pcall(c.SetEnabled, c, false)
        return
    end
    if holder.unit ~= unit then
        if not pcall(c.SetUnit, c, unit) then
            -- The container may already hold the new unit; nothing is assumed.
            holder.unit = nil
            Debug("%s: SetUnit %s refused", holder.key, unit)
            return
        end
        holder.unit = unit
    end
    pcall(c.SetFrameStrata, c, db.SkipStrata or "MEDIUM")
    if not pcall(c.SetEnabled, c, true) then
        Debug("%s: enable refused", holder.key)
        return
    end
    if not pcall(c.UpdateAllAuras, c) then Debug("%s: refresh refused", holder.key) end
end

-- Queues what is missing, then binds each container. Every drain runs this,
-- the roster settle's included, so the rogue is looked up again whenever the
-- party changes.
function Skip.Resolve()
    if not (Skip.on and Skip.active) then return end
    local db = Skip.pb.db
    if AnyMissing(db) then Skip.pb:Enqueue(Skip.QUEUE_KEY) end
    for _, holder in ipairs(HOLDERS) do Bind(holder, db) end
end

-- The build queue's call for Skip.QUEUE_KEY: each container first, then one
-- group per frame. Returns true when nothing is left to build; a build
-- refused, or skipped because the aura container code cannot load, waits for
-- the drain.
function Skip.BuildNext()
    if not (Skip.on and Skip.active) then return true end
    local db = Skip.pb.db
    if not AnyMissing(db) then return true end
    if not KE:AuraContainersAvailable() then
        Debug("aura containers unavailable")
        return true
    end
    for _, holder in ipairs(HOLDERS) do
        if Missing(holder, db) then
            if not holder.container then return not Create(holder) end
            for i, spell in ipairs(holder.spells) do
                if SpellOn(db, spell) and not holder.groups[spell.key] then
                    if not AddGroup(holder, i, spell) then
                        Debug("group %s refused", spell.key)
                        return true
                    end
                    break
                end
            end
            break
        end
    end
    if AnyMissing(db) then return false end
    Skip.Resolve()
    return true
end

-- Drains what a refusal left: the place, the restyle, and through
-- Skip.Resolve the builds, the layout, the units and the bind.
function Skip.OnRelease()
    if not Skip.on then return end
    if Skip.placePending and Skip.box then Place(Skip.pb.db) end
    if Skip.restylePending then Skip.restylePending = not RestyleButtons() end
    Skip.Resolve()
end

---------------------------------------------------------------------------------
-- Preview: plain frames, static, in the live look and order
---------------------------------------------------------------------------------
local function DrawSamples()
    local s, db = Skip.style, Skip.pb.db
    local corner = Corner()
    local step = (s.height + s.gap) * (s.up and 1 or -1)
    local placed = 0
    for i, spell in ipairs(SPELLS) do
        local f = Skip.samples[i]
        if SpellOn(db, spell) then
            if not f then
                f = CreateFrame("Frame", nil, Skip.sampleLayer)
                MakeRegions(f)
                Skip.samples[i] = f
            end
            local r = f.ksRegions
            Lay(f, spell, s)
            r.icon:SetTexture(Texture(spell.icon))
            r.bar:SetValue(SAMPLE_FILL)
            r.name:SetText(spell.name)
            r.timer:SetText(SAMPLE_SECONDS)
            r.timer:SetShown(s.showTimer)
            f:ClearAllPoints()
            f:SetPoint(corner, Skip.sampleLayer, corner, 0, placed * step)
            f:Show()
            placed = placed + 1
        elseif f then
            f:Hide()
        end
    end
end

function Skip.ShowPreview()
    if not (Skip.on and Skip.box) then return end
    Skip.previewing = true
    DrawSamples()
    Show()
end

function Skip.HidePreview()
    if not Skip.previewing then return end
    Skip.previewing = false
    Show()
end

---------------------------------------------------------------------------------
-- Lifecycle, driven by the Party Cooldowns module
---------------------------------------------------------------------------------
-- A disabled container registers no UNIT_AURA. Frames cannot be destroyed,
-- so they wait hidden until /reload.
local function Release()
    for _, holder in ipairs(HOLDERS) do
        local c = holder.container
        if c then pcall(c.SetEnabled, c, false) end
    end
end

-- Off: no container runs, nothing is drawn, and the mover is gone.
local function TurnOff()
    Skip.on = false
    Release()
    Skip.previewing = false
    Unregister()
    if Skip.box then Skip.box:Hide() end
end

function Skip.Enable(pb)
    Skip.pb = pb
end

function Skip.Disable()
    Skip.active = false
    TurnOff()
end

-- Binding is left to the module: every caller is followed in the same call by
-- its drain, which resolves, and a settings change by its preview redraw.
function Skip.ApplySettings()
    local pb = Skip.pb
    if not pb then return end
    local db = pb.db
    if not (db.SkipBars == true and Count(db) > 0) then return TurnOff() end
    Skip.on = true
    MakeBox()
    Restyle(db)
    Skip.restylePending = not RestyleButtons()
    Register()
    Show()
end

function Skip.Activate()
    Skip.active = true
    Skip.ApplySettings()
end

function Skip.Deactivate()
    Skip.active = false
    Release()
    Show()
end
