-- ╔══════════════════════════════════════════════════════════╗
-- ║  Modules/Skinning/RestedXP/RestedXPRules.lua             ║
-- ║  Purpose: The RestedXP module's pure rules.              ║
-- ║           No WoW API, no frames.                         ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)

local floor, math_max, math_min = math.floor, math.max, math.min
local ipairs, next, pairs, select, tonumber, type = ipairs, next, pairs, select, tonumber, type

local Safe = KE.RestedXPSafe
local Has, Dig = Safe.Has, Safe.Dig

local Rules = {}
KE.RestedXPRules = Rules

Rules.THEME_NAME = "KitnEssentials"

local THEME_KEY = "activeTheme"
local THEME_TEXTURES = "Interface/AddOns/RXPGuides/Textures/DarkMode/"
local WHITE_TEXTURE = "Interface/BUTTONS/WHITE8X8"
local CHANNEL_MAX, ROUND, PERCENT = 255, 0.5, 100
local COUNT_MIN = 2
local HEIGHT_SLACK = 0.001
local COUNT_PATTERN = "(%d+)%s*/%s*(%d+)"
local LEAD_ICON, LEAD_PLAIN = "^%s*(|T[^|]*|t)%s*", "^|T([^|:]+):%d+|t$"
local LEAD_PATH, CONTENT_ID, CONTENT_DIR = "^|T([^|:]+)", "^%d+$", "interface[/\\]icons[/\\]"
local TEXT_YARDS = "%d yd"
local GROUP_MARK, GROUP_BRAND, GROUP_FACTION = "^%*", "^RestedXP ", " %([AH]%)$"

---------------------------------------------------------------------------------
-- Colors
---------------------------------------------------------------------------------
local function RGB(hex)
    return {
        tonumber(hex:sub(1, 2), 16) / CHANNEL_MAX,
        tonumber(hex:sub(3, 4), 16) / CHANNEL_MAX,
        tonumber(hex:sub(5, 6), 16) / CHANNEL_MAX,
    }
end

local OFF_BOX = RGB("080808")
local BLACK = RGB("000000")
local KE_TOKENS = { fg = RGB("ffffff"), muted = RGB("c8c8c8") }

-- How much accent each part takes over KE's near-black or black while the backdrop
-- and highlights follow it, and the backdrop's alpha then.
Rules.WASH_PANEL, Rules.WASH_BOX, Rules.WASH_EDGE = 0.10, 0.06, 0.40
Rules.WASH_PANEL_ALPHA = 0.92

local function With(color, alpha)
    return { color[1], color[2], color[3], alpha }
end

function Rules.Hex(color)
    return ("%02x%02x%02x"):format(floor(color[1] * CHANNEL_MAX + ROUND), floor(color[2] * CHANNEL_MAX + ROUND),
        floor(color[3] * CHANNEL_MAX + ROUND))
end

local function Mix(base, color, share)
    return {
        base[1] + (color[1] - base[1]) * share,
        base[2] + (color[2] - base[2]) * share,
        base[3] + (color[3] - base[3]) * share,
    }
end

function Rules.Tokens(accent)
    return { fg = KE_TOKENS.fg, muted = KE_TOKENS.muted, accent = accent }
end

function Rules.ThemeFields(tokens, font, back)
    local accent, fg = tokens.accent, tokens.fg
    return {
        name = Rules.THEME_NAME,
        displayName = Rules.THEME_NAME,
        author = Rules.THEME_NAME,
        background = With(back, back[4] or 1),
        bottomFrameBG = With(back, back[4] or 1),
        bottomFrameHighlight = { 1, 1, 1, 0.15 },
        mapPins = With(accent, 1),
        tooltip = "|cff" .. Rules.Hex(accent),
        textColor = { fg[1], fg[2], fg[3] },
        font = font,
        texturePath = THEME_TEXTURES,
        bgTextures = { edge = WHITE_TEXTURE, bottom = WHITE_TEXTURE, guideName = WHITE_TEXTURE },
    }
end

-- Custom replaces the wash, so all of its colors and Background Color act there.
function Rules.Washed(follow, mode)
    return follow == true and mode ~= "custom"
end

-- panel is the Background Color setting, or nil with Window Background off.
function Rules.WindowColors(tokens, follow, panel, opacity, mode, custom)
    local washed = Rules.Washed(follow, mode)
    local accent = tokens.accent
    local boxAlpha = opacity / PERCENT
    local line = { 1, 1, 1, 0.28 }
    local edge = With(washed and Mix(BLACK, accent, Rules.WASH_EDGE) or BLACK, 1)
    local colors = {
        title = With(tokens.fg, 1),
        text = With(tokens.fg, 1),
        accent = With(accent, 1),
        muted = With(tokens.muted, 0.9),
        line = line,
        box = With(washed and Mix(OFF_BOX, accent, Rules.WASH_BOX) or OFF_BOX, boxAlpha),
        border = edge,
        boxBorder = edge,
        barFill = With(accent, 1),
        barBack = With(line, line[4]),
    }
    if panel then
        colors.panel = washed and With(Mix(OFF_BOX, accent, Rules.WASH_PANEL), Rules.WASH_PANEL_ALPHA)
            or With(panel, panel[4] or 1)
    end
    if mode == "custom" and type(custom) == "table" then
        for _, key in ipairs({ "title", "text", "line", "border", "barFill", "barBack" }) do
            if type(custom[key]) == "table" then colors[key] = custom[key] end
        end
        if type(custom.border) == "table" then colors.boxBorder = custom.border end
        if type(custom.box) == "table" then colors.box = With(custom.box, boxAlpha) end
    end
    return colors
end

---------------------------------------------------------------------------------
-- Options
---------------------------------------------------------------------------------
local function Number(default, low, high, step)
    return { kind = "number", default = default, min = low, max = high, step = step or 1 }
end

local function Toggle(default)
    return { kind = "toggle", default = default }
end

local function Choice(default, ...)
    local values = {}
    for i = 1, select("#", ...) do values[select(i, ...)] = true end
    return { kind = "choice", default = default, values = values }
end

local OPTIONS = {
    SetUpNewCharacters = Toggle(true),
    ArrowEnabled = Toggle(true),
    ArrowSize = Number(100, 60, 200, 5),
    ArrowGap = Number(4, 0, 20),
    ArrowWords = Toggle(true),
    ArrowTextSize = Number(14, 8, 24),
    ArrowAddonFont = Toggle(true),
    ArrowDistance = Toggle(true),
    ShowOpenWorld = Toggle(true),
    ShowDungeons = Toggle(true),
    ShowRaids = Toggle(false),
    ShowPvP = Toggle(false),
    CombatFade = Number(50, 0, 100, 5),
    ListedSteps = Number(6, 0, 12),
    Scale = Number(100, 60, 200, 5),
    Width = Number(380, 260, 640),
    UnderTitle = Choice("bar", "bar", "rule", "none"),
    Skip = Choice("shift", "shift", "click", "off"),
    ShowMark = Toggle(true),
    StepYards = Toggle(true),
    StepFlash = Toggle(true),
    FoldObjective = Toggle(true),
    Tips = Toggle(true),
    LineSkip = Toggle(true),
    ScrollBar = Toggle(false),
    Lock = Toggle(false),
    Folded = Toggle(false),
    FontOutline = Choice("OUTLINE", "shadow", "OUTLINE", "THICKOUTLINE", "NONE"),
    TitleSize = Number(16, 10, 28),
    StepSize = Number(13, 8, 24),
    ListSize = Number(12, 8, 24),
    FollowAccent = Toggle(false),
    WindowColors = Choice("accent", "accent", "custom"),
    Panel = Toggle(true),
    Border = Toggle(true),
    BoxOpacity = Number(55, 0, 100),
}

function Rules.Option(key, value)
    local option = OPTIONS[key]
    if option.kind == "number" then
        if type(value) ~= "number" then return option.default end
        local snapped = floor(value / option.step + ROUND) * option.step
        return math_min(option.max, math_max(option.min, snapped))
    elseif option.kind == "toggle" then
        if type(value) ~= "boolean" then return option.default end
        return value
    end
    if value ~= nil and option.values[value] then return value end
    return option.default
end

function Rules.Range(key)
    return OPTIONS[key].min, OPTIONS[key].max
end

---------------------------------------------------------------------------------
-- Setup
---------------------------------------------------------------------------------
local SETUP_ROWS = {
    { key = "enableBetaFeatures", label = "Beta Features", after = true, reload = true },
    { key = "enableV2Interface", label = "V2 Interface", after = true, reload = true },
    { key = THEME_KEY, label = "Theme", after = Rules.THEME_NAME },
}

local function AddRow(rows, def, now, after)
    rows[#rows + 1] = { key = def.key, label = def.label, now = now, after = after }
    if def.reload then rows.reload = true end
end

function Rules.PlanSetup(profile)
    local rows = {}
    for _, def in ipairs(SETUP_ROWS) do
        if profile[def.key] ~= def.after then AddRow(rows, def, profile[def.key], def.after) end
    end
    return rows
end

function Rules.RowKeys(rows)
    local keys = {}
    for i, row in ipairs(rows) do keys[i] = row.key end
    return keys
end

function Rules.SameDeep(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return a == b end
    for key, value in pairs(a) do
        if not Rules.SameDeep(value, b[key]) then return false end
    end
    for key in pairs(b) do
        if a[key] == nil then return false end
    end
    return true
end

-- The theme's font path for a font name. A media pack can load after RestedXP
-- starts, so the start-up build takes the path a later load found for the same
-- name; once every addon has loaded, a name the library does not know has no path,
-- and the kept one goes. Returns the path and the record to keep.
function Rules.ThemeFont(name, found, kept, early, fallback)
    local same = type(kept) == "table" and kept.name == name
    if found then
        if same and kept.path == found then return found, kept end
        return found, { name = name, path = found }
    end
    if not early then return fallback, nil end
    if same and type(kept.path) == "string" then return kept.path, kept end
    return fallback, kept
end

-- Whether a preview still shows what a write would do.
function Rules.SameRows(a, b)
    if #a ~= #b then return false end
    for i, row in ipairs(a) do
        local other = b[i]
        if row.key ~= other.key or row.now ~= other.now or row.after ~= other.after then return false end
    end
    return true
end

-- Running alone does not answer this: a profile manager that defers a switch leaves
-- the module running with its saved flag off.
function Rules.SetupMayWrite(running, enabled, available, elvuiInCharge)
    return not not (running and enabled == true and available and not elvuiInCharge)
end

-- A waiting change lives across one reload: the refused-reload timer clears it in a
-- session that goes on. A crash or quit before that timer leaves it for a later
-- load KE may not run in, so it also expires after one loading screen, with room
-- for a slow disk and a long addon list.
Rules.PENDING_SECONDS = 300

-- A change waiting for RestedXP's start writes only what its preview showed: the
-- same profile, by name, and each row's Now still true, within the time above. A
-- setup also needs the module's gates; an undo puts back the player's own values,
-- so it does not. False comes with "expired" or "changed".
function Rules.PendingApplies(pending, profileName, profile, mayWrite, now)
    if type(pending) ~= "table" or type(pending.rows) ~= "table" or type(profile) ~= "table" then
        return false, "changed"
    end
    local age = type(pending.at) == "number" and type(now) == "number" and now - pending.at
    if not age or age < 0 or age > Rules.PENDING_SECONDS then return false, "expired" end
    if profileName == nil or pending.profile ~= profileName or #pending.rows == 0 then return false, "changed" end
    if not (pending.kind == "undo" or (pending.kind == "setup" and mayWrite)) then return false, "changed" end
    for _, row in ipairs(pending.rows) do
        if profile[row.key] ~= row.now then return false, "changed" end
    end
    return true
end

-- One change waits per character, and the newest approved one wins: a newer save
-- replaces it, and every write KE makes outside the start and every RestedXP profile
-- event clears it, so a waiting change never runs after one the player approved
-- later, or on a profile made again under the same name.
function Rules.SavePending(store, kind, profileName, rows, now)
    local copy = {}
    for i, row in ipairs(rows) do copy[i] = { key = row.key, now = row.now, after = row.after } end
    store.RestedXPPending = { kind = kind, profile = profileName, rows = copy, at = now }
end

function Rules.Supersede(store)
    if type(store) == "table" then store.RestedXPPending = nil end
end

function Rules.TakePending(store)
    local pending = type(store) == "table" and store.RestedXPPending or nil
    Rules.Supersede(store)
    return pending
end

-- A change saved for the next start needs both addons to load then. Each answer is
-- the client's own check, a boolean, or the enable state it reads for this
-- character's GUID, which counts only at All, as the client's check counts it.
local ENABLE_ALL = 2

local function LoadsNext(answer)
    return answer == true or answer == ENABLE_ALL
end

function Rules.BothLoadNext(keAnswer, rxpAnswer)
    return LoadsNext(keAnswer) and LoadsNext(rxpAnswer)
end

-- The refused-reload timer clears only the change it was armed for. True when it did.
function Rules.DropIfWaiting(store, saved)
    if type(store) ~= "table" or saved == nil or store.RestedXPPending ~= saved then return false end
    store.RestedXPPending = nil
    return true
end

function Rules.PreviewHolds(rows, profile, shownProfile, shownRows)
    return rows ~= nil and profile ~= nil and profile == shownProfile and Rules.SameRows(rows, shownRows)
end

-- What KE changed belongs to one RestedXP profile, so no other profile can read it.
function Rules.RecordFor(records, key)
    return type(records) == "table" and key ~= nil and records[key] or nil
end

-- A key with a record keeps it, so a second setup never stores KE's own values
-- as the player's. An unset switch records false, so it can be undone.
function Rules.MergeBefore(before, profile, keys)
    for _, key in ipairs(keys) do
        if before[key] == nil then
            local value = profile[key]
            if value == nil and key ~= THEME_KEY then value = false end
            before[key] = value
        end
    end
    return before
end

function Rules.PlanUndo(before, profile)
    local rows = {}
    for _, def in ipairs(SETUP_ROWS) do
        local stored = before[def.key]
        if stored ~= nil and stored ~= profile[def.key] then
            AddRow(rows, def, profile[def.key], stored)
        end
    end
    return rows
end

-- Clears the keys whose value is back, and says whether the record is empty.
function Rules.ClearDone(before, profile)
    for key, value in pairs(before) do
        if value == profile[key] or (value == false and profile[key] == nil) then before[key] = nil end
    end
    return next(before) == nil
end

function Rules.ShouldAutoSetup(on, seen)
    return on == true and not seen
end

local function HasRows(rows)
    return rows ~= nil and #rows > 0
end

-- A Beta or V2 change waits for the next start, and after this load's start was
-- missed the next one most likely is too.
function Rules.Doable(rows, missed)
    return HasRows(rows) and not (rows.reload and missed)
end

-- The This Character card shows one state and one button, and the button grays only
-- when no action exists. Returns the state, "setup" or "undo", and whether it is lit.
function Rules.CharacterState(facts)
    if not facts.installed then return "notInstalled", "setup", false end
    if not facts.loaded then return "notLoaded", "setup", false end
    if not facts.profile then return "noProfile", "setup", false end
    if facts.waiting then return "reloading", facts.waiting == "undo" and "undo" or "setup", false end
    local canSetUp, canUndo = Rules.Doable(facts.plan, facts.missed), Rules.Doable(facts.undo, facts.missed)
    if not facts.window then
        if canUndo then return "noWindow", "undo", true end
        return "noWindow", "setup", false
    end
    if HasRows(facts.plan) then
        if canSetUp then return facts.plan.reload and "notSetUp" or "themeOnly", "setup", true end
        if canUndo then return "setupMissed", "undo", true end
        return "setupMissed", "setup", false
    end
    if canUndo then return "setUp", "undo", true end
    if HasRows(facts.undo) then return "undoMissed", "undo", false end
    return "setUpFound", "undo", false
end

local WINDOW_SAYS_ON = { notSetUp = false, themeOnly = true, setUp = true, setUpFound = true }

-- A state's words tell what the saved settings make of KE's window, which runs as its
-- last start left it until the next settings pass. True while the two differ.
function Rules.WindowPending(state, running)
    local saysOn = WINDOW_SAYS_ON[state]
    return saysOn ~= nil and saysOn ~= (running == true)
end

---------------------------------------------------------------------------------
-- Giving back
---------------------------------------------------------------------------------
function Rules.KeepHome(home, alpha, mouse)
    if home then return home end
    return { alpha = alpha, mouse = mouse }
end

---------------------------------------------------------------------------------
-- Arrow
---------------------------------------------------------------------------------
-- nil leaves RestedXP's own text alone; "" hides the text.
function Rules.ArrowText(distance, words, showDistance, showWords, wrongContinent)
    if wrongContinent then return nil end
    local line = showDistance and type(distance) == "number" and TEXT_YARDS:format(distance) or nil
    local objective = showWords and words or nil
    if line and objective then return line .. "\n" .. objective end
    return line or objective or ""
end

---------------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------------
function Rules.WindowMayStart(v2On, rivalWindowOn)
    return v2On == true and not rivalWindowOn
end

-- A scenario counts as open world, as RestedXP's own instance test treats it.
function Rules.ShowInAllowed(kind, openWorld, dungeons, raids, pvp)
    if kind == "party" then return dungeons == true end
    if kind == "raid" then return raids == true end
    if kind == "pvp" or kind == "arena" then return pvp == true end
    return openWorld == true
end

function Rules.ShouldFlash(lastGuide, lastAfter, guide, after)
    return lastGuide ~= nil and lastGuide == guide and lastAfter ~= after
end

-- RestedXP keeps such a step active beside the guide's progress until the guide
-- passes its target, so a skip has no step to move past: the window hides its box.
function Rules.TagAlong(step, progress)
    return type(step) == "table" and step.completewith ~= nil and progress ~= nil and step.index ~= progress
end

-- A hidden box lasts only while RestedXP keeps its step active, so a step the guide
-- passed shows again if the guide returns to it.
function Rules.PruneHidden(hidden)
    for step in pairs(hidden) do
        if not step.active then hidden[step] = nil end
    end
end

function Rules.Parts(rxp)
    local arrow = Dig(rxp, "arrowFrame")
    local v2 = Dig(rxp, "v2")
    local settings = Dig(rxp, "settings")
    local hasProfile = type(Dig(settings, "profile")) == "table"
    return {
        Theme = Has(rxp, "RegisterTheme") and Has(rxp, "ReloadTheme") and hasProfile,
        Arrow = Has(arrow, "UpdateVisuals") and type(Dig(arrow, "texture")) == "table"
            and type(Dig(arrow, "text")) == "table",
        Icons = type(Dig(rxp, "icons")) == "table",
        Setup = hasProfile and Has(settings, "GetSettingsDB"),
        Window = Has(v2, "IsGuideWindowEnabled") and Has(v2, "BuildGuideStepsSnapshot")
            and Has(rxp, "GetGuideProgress") and Has(rxp, "SetStep")
            and type(Dig(rxp, "RXPFrame", "activeSteps")) == "table",
    }
end

---------------------------------------------------------------------------------
-- Reading guide text
---------------------------------------------------------------------------------
-- The level range tinted where the text has it, first or last.
function Rules.TintRange(text, tint)
    local range, place = text:match("^(%d+%-%d+)%s+(.+)$")
    if range then return tint(range) .. " " .. place end
    place, range = text:match("^(.-)%s+(%d+%-%d+)$")
    if place then return place .. " " .. tint(range) end
    return text
end

-- The guide's group as the window's top bar names it: without the leading mark
-- RestedXP gives some groups, the RestedXP in front, or the faction at the end.
function Rules.GuideGroupName(group)
    if type(group) ~= "string" then return nil end
    local name = group:gsub(GROUP_MARK, ""):gsub(GROUP_BRAND, ""):gsub(GROUP_FACTION, "")
    if name == "" then return nil end
    return name
end

function Rules.Plain(text)
    text = text:gsub("|c%x%x%x%x%x%x%x%x", "")
    text = text:gsub("|r", "")
    text = text:gsub("|T[^|]*|t", "")
    text = text:gsub("|A[^|]*|a", "")
    text = text:gsub("|H[^|]*|h", "")
    text = text:gsub("|h", "")
    return (text:gsub("^%s+", ""))
end

function Rules.Counted(tag, id, qty, shown, getCount)
    if type(tag) == "string" and tag:find("^buy") and type(id) == "number" and type(qty) == "number" then
        return getCount(id), qty, true
    end
    local have, need = Rules.Plain(shown):match(COUNT_PATTERN)
    return tonumber(have), tonumber(need), false
end

-- The meter's fill, or nil for a row that draws none.
function Rules.CountFill(have, need, bags, done)
    if not need or need < COUNT_MIN then return nil end
    if bags and done then return 1 end
    return math_min(1, math_max(0, (have or 0) / need))
end

function Rules.Lifted(shown, glyph)
    if glyph ~= "" then return shown, glyph, false end
    local lead = shown:match(LEAD_ICON)
    if not lead then return shown, glyph, false end
    local path = lead:match(LEAD_PLAIN)
    local named = lead:match(LEAD_PATH) or ""
    local content = named:match(CONTENT_ID) or named:lower():find(CONTENT_DIR)
    return (shown:gsub(LEAD_ICON, "", 1)), path and ("|T" .. path .. ":0|t") or lead, content and true or false
end

function Rules.FirstAfter(list, index)
    local low, high = 1, #list + 1
    while low < high do
        local middle = floor((low + high) / 2)
        if list[middle].index > index then high = middle else low = middle + 1 end
    end
    return low
end

-- The list's first shown position and the scroll that position leaves.
function Rules.ListWindow(first, scroll, count, total)
    local top = math_max(1, math_min(first + scroll, math_max(first, total - count + 1)))
    return top, top - first
end

-- The steps a window height holds. A height set from a whole count can read just
-- under it once the frame has stored it, so a hair of slack keeps that count.
function Rules.StepsForHeight(height, chrome, lineHeight, labelLines)
    return math_max(0, floor((height - chrome) / lineHeight + HEIGHT_SLACK) - labelLines)
end

-- Listed Steps under a held grip. A list with fewer rows leaves the window shorter
-- than the setting, so the height says nothing until it moves a whole line, and then
-- moves the setting only the way the height went.
function Rules.GripSteps(listed, height, pressedHeight, count, lineHeight)
    local moved = height - pressedHeight
    if moved > -lineHeight and moved < lineHeight then return listed end
    if moved > 0 then return math_max(listed, count) end
    return math_min(listed, count)
end

-- RestedXP's running bars, each under the one key the owner map names for it, so a
-- frame under two keys comes once. Most time left first, as RestedXP sorts them, and
-- equal times in key order, so two bars never swap lines between redraws.
function Rules.TimerOrder(bars, owned, now)
    local list = {}
    for key, bar in pairs(bars) do
        if owned[bar] == key and bar:IsShown() and type(bar.exp) == "number" and bar.exp > now then
            list[#list + 1] = bar
        end
    end
    table.sort(list, function(a, b)
        if a.exp ~= b.exp then return a.exp > b.exp end
        return tostring(owned[a]) < tostring(owned[b])
    end)
    return list
end
