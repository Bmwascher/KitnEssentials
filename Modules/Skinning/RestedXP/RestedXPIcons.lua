-- ╔══════════════════════════════════════════════════════════╗
-- ║  Modules/Skinning/RestedXP/RestedXPIcons.lua             ║
-- ║  Purpose: RestedXP's step icons in KE's own, put in its  ║
-- ║           icon table as it starts.                       ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)

local pairs, type = pairs, type
local floor = math.floor

local Safe, Rules, Theme = KE.RestedXPSafe, KE.RestedXPRules, KE.RestedXPTheme

local Icons = {}
KE.RestedXPIcons = Icons

local ART = "Interface\\AddOns\\KitnEssentials\\Media\\RestedXP\\Icons\\"
local EXTENSION = ".tga"
local ESCAPE = "|T%s%s%s:0:0:0:0:%d:%d:0:%d:0:%d:%d:%d:%d|t"
local TEXELS = 64
local CHANNEL_MAX, ROUND = 255, 0.5
local ART_PATTERN = ART:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
local LOOK_PATTERN = "|T" .. ART_PATTERN .. "(%a+)%.tga"
local INLINE_PATTERN = "|T([^|:]+):%d+|t"

-- These two sit inside guide text, so only the window swaps them, as it reads a row.
local INLINE = {
    ["interface/worldmap/chatbubble_64grey.blp"] = "gossip",
    ["interface/cursor/crosshair/interact.blp"] = "interact",
}

local GLYPHS = {
    accept = "accept", acceptmultiple = "accept",
    daily = "daily",
    turnin = "turnin", turninmultiple = "turnin",
    dailyturnin = "dailyturnin",
    collect = "collect", collectmultiple = "collect",
    equip = "equip",
    combat = "combat",
    complete = "complete", scenario = "complete",
    vendor = "vendor",
    reputation = "reputation",
    fly = "fly",
    fp = "fp",
    ["goto"] = "goto", groundgoto = "goto", flygoto = "goto", explore = "goto",
    gossip = "gossip",
    hs = "home", home = "home",
    trainer = "trainer", train = "trainer",
    arrow = "arrow",
    marker = "marker",
    xp = "xp", xpto60 = "xp",
    stable = "stable",
    tame = "tame",
    abandon = "abandon",
    error = "error",
    link = "link",
    clock = "clock",
    engrave = "engrave",
    clicknext = "clicknext",
    deathskip = "deathskip",
}

local bakedAccent

-- True once RestedXP's table holds KE's icons. Only a reload takes them out.
function Icons.Applied()
    return bakedAccent ~= nil
end

-- The accent is baked into each escape, and RestedXP's own rows draw them as they
-- stand.
function Icons.AccentStale()
    return bakedAccent ~= nil and Rules.Hex(Theme.Tokens().accent) ~= bakedAccent
end

local function Channel(value)
    return floor(value * CHANNEL_MAX + ROUND)
end

local function Escape(glyph)
    local accent = Theme.Tokens().accent
    return ESCAPE:format(ART, glyph, EXTENSION, TEXELS, TEXELS, TEXELS, TEXELS, Channel(accent[1]),
        Channel(accent[2]), Channel(accent[3]))
end

-- Only string values are replaced, so a key RestedXP drops or renames is left
-- alone. A late swap shows an icon twice: its V2 window strips an icon by
-- comparing text with this table, so this runs only as RestedXP starts.
function Icons.Apply()
    local icons = Safe.Dig(_G.RXP, "icons")
    if type(icons) ~= "table" then
        Safe.Missing("Icons", "icons table")
        return
    end
    for key, glyph in pairs(GLYPHS) do
        if type(icons[key]) == "string" then icons[key] = Escape(glyph) end
    end
    bakedAccent = Rules.Hex(Theme.Tokens().accent)
end

function Icons.PathOf(text)
    if type(text) ~= "string" then return nil end
    local glyph = text:match(LOOK_PATTERN)
    return glyph and (ART .. glyph .. EXTENSION) or nil
end

-- These two follow what RestedXP's table holds, not the settings, so a window's
-- rows stay one set until the next reload.
function Icons.TextureFor(glyph)
    if not bakedAccent then return nil end
    return ART .. glyph .. EXTENSION
end

function Icons.InlineText(text)
    if not bakedAccent or type(text) ~= "string" then return text end
    return (text:gsub(INLINE_PATTERN, function(path)
        local glyph = INLINE[path:lower():gsub("\\", "/")]
        if glyph then return Escape(glyph) end
    end))
end
