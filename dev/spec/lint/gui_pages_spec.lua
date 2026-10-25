-- Lint: the settings page standard.
--
-- The gui-module-page skill states the standard; this lint holds pages to
-- the parts a source scan can see:
--   L1 a title in a standard family takes its standard form, on a page and
--      as a card factory's default or fixed title
--   L2 no page builds its own "Position Settings" card
--   L3 cards keep the standard order in each ordered function body: one
--      whose first card is a module card, a module's first tab, or a page
--      a sidebar row opens
--   L4 the module card (a first card whose header switch reads .Enabled)
--      has one switch and a description; a sidebar page or tab header
--      that reads db.Enabled has that switch on its first card
--   L5 that description comes before any return after the card, and not
--      inside an if whose own condition reads .Enabled
--   L6 no body control prints a chat line (msgPopup)
--   L7 gold comes from KE:Gold, never a hand-written color code
-- A new page must pass with no entry. A listed page breaks the standard
-- today and its entry names the phase that fixes it; once the page passes,
-- the entry fails the sweep until it is deleted, so the lists only shrink.
--
-- A source scan cannot see titles built at runtime or taken from variables
-- or parameters, titles passed into a page's own card helper, what actually
-- draws (pooled reuse, cards inside branches, layout), order across helper
-- functions (each function body is ordered on its own), the first tab of a
-- list built from constants or by a function, page builders that are not
-- inline functions, a module switch dropped from a tab page, from a page
-- that never reads db.Enabled itself, or from a header builder defined in
-- another file (a known gap), a header builder named where the file has
-- two local functions of that name, a description hidden behind a local
-- that holds the enable state (local disabled = db.Enabled == false), hand-built
-- "<Element> Position" cards, gold built from numbers or hex pieces, files
-- outside the walked folders, or control tooltips.
-- It also over-reaches once: a tab feature switch keyed Enabled in its own
-- table is held as a module card.
local lfs = require("lfs")

local EXTRA_PAGES = { "GUI/GUIMain/GUI-HomePage.lua", "GUI/GUIMain/GUI-ProfilesTab.lua" }
-- Holds GUIFrame.sidebarConfig, the ids of the pages the sidebar opens.
local SIDEBAR_FILE = "GUI/GUIMain/GUI-MainFrame.lua"
local GOLD_DIRS = { "KitnEssentials_Options", "GUI" }
-- A page that passes no title shows its factory's default or fixed title,
-- so those are held to the standard in the factory files themselves. One
-- file per card factory the lint recognizes.
local FACTORY_FILES = {
    "GUI/GUIWidgets/GUI-PositionCard.lua",
    "GUI/GUIWidgets/GUI-FontSettingsCard.lua",
    "GUI/GUIWidgets/GUI-ColorsCard.lua",
    "GUI/GUIWidgets/GUI-DispelTypeColorsCard.lua",
    "GUI/GUIWidgets/GUI-GlowSettingsCard.lua",
    "GUI/GUIWidgets/GUI-AuraApplicationSoundCard.lua",
    "GUI/GUIWidgets/GUI-AuraCasterNameCard.lua",
    "GUI/GUIWidgets/GUI-AuraAllowlistCard.lua",
    "GUI/GUIWidgets/GUI-SpecPicker.lua",
    "GUI/GUIWidgets/GUI-TauntCursorCard.lua",
    "GUI/GUIWidgets/GUI-DispelCursorCard.lua",
}

local CHECKS = { "L1", "L2", "L3", "L4", "L5", "L6", "L7" }
-- Keyed by file with a count, so a listed page cannot gain another.
local COUNTED = { L2 = true, L6 = true, L7 = true }
local PHASES = { ["16"] = true, ["17"] = true, ["18"] = true, ["none until approved"] = true }

-- check -> key -> { phase = <a PHASES key>, n = <the count, COUNTED checks only> }
-- An L3, L4 or L5 entry ends with the failure's detail as a comment.
local ALLOWED = {
    L1 = {
        -- Phase 18 handles these special pages.
        ["KitnEssentials_Options/DungeonTools/KicksCasts/GUI-CCTracker.lua|Display"] = { phase = "18" },
        ["KitnEssentials_Options/Skinning/GUI-DamageMeter.lua|Font"] = { phase = "18" },
        ["KitnEssentials_Options/Skinning/GUI-MythicPlusTimer.lua|Affixes & Key — Colors"] = { phase = "18" },
        ["KitnEssentials_Options/Skinning/GUI-MythicPlusTimer.lua|Deaths — Colors"] = { phase = "18" },
        ["KitnEssentials_Options/Skinning/GUI-MythicPlusTimer.lua|Forces — Colors"] = { phase = "18" },
        ["KitnEssentials_Options/Skinning/GUI-MythicPlusTimer.lua|Nameplate % — Colors"] = { phase = "18" },
        ["KitnEssentials_Options/Skinning/GUI-MythicPlusTimer.lua|Nameplate % — Position"] = { phase = "18" },
        ["KitnEssentials_Options/Skinning/GUI-MythicPlusTimer.lua|Objectives & Splits — Colors"] = { phase = "18" },
        ["KitnEssentials_Options/Skinning/GUI-MythicPlusTimer.lua|Timer — Colors"] = { phase = "18" },
    },
    L2 = {
        -- Phase 17 moves these onto CreatePositionCard.
        ["KitnEssentials_Options/QoL/GroupTools/GUI-ReadyCheckConsumables.lua"] = { phase = "17", n = 1 },
        ["KitnEssentials_Options/Skinning/DarkTheme/GUI-LootFrame.lua"] = { phase = "17", n = 1 },
        ["KitnEssentials_Options/Skinning/DarkTheme/GUI-LootRoll.lua"] = { phase = "17", n = 1 },
    },
    L3 = {
        -- Phase 17 reorders these.
        ["KitnEssentials_Options/AuraTracking/GUI-AuraDebuffs.lua"] = { phase = "17" }, -- Display after Position
        ["KitnEssentials_Options/AuraTracking/GUI-AuraExternals.lua"] = { phase = "17" }, -- Display after Position
        ["KitnEssentials_Options/AuraTracking/GUI-AuraMovement.lua"] = { phase = "17" }, -- Display after Position
        ["KitnEssentials_Options/AuraTracking/GUI-TotemTracker.lua"] = { phase = "17" }, -- Display after Font
        ["KitnEssentials_Options/DungeonTools/DungeonAlerts/GUI-DeathNotifications.lua"] = { phase = "17" }, -- content after Position
        ["KitnEssentials_Options/DungeonTools/DungeonAlerts/GUI-EnemyCounter.lua"] = { phase = "17" }, -- content after Colors
        ["KitnEssentials_Options/DungeonTools/DungeonAlerts/GUI-TargetedSpells.lua"] = { phase = "17" }, -- content after Font
        ["KitnEssentials_Options/DungeonTools/KicksCasts/GUI-DungeonCasts.lua"] = { phase = "17" }, -- content after Position
        ["KitnEssentials_Options/QoL/GUI-SecondaryStats.lua"] = { phase = "17" }, -- content after Font
        ["KitnEssentials_Options/QoL/GroupTools/GUI-ReadyCheckConsumables.lua"] = { phase = "17" }, -- content after Display
        ["KitnEssentials_Options/Skinning/DarkTheme/GUI-AlertFrames.lua"] = { phase = "17" }, -- content after Position
        ["KitnEssentials_Options/Skinning/DarkTheme/GUI-UIWidgets.lua"] = { phase = "17" }, -- content after Font
        ["KitnEssentials_Options/Skinning/GUI-Chat.lua"] = { phase = "17" }, -- content after Colors
        ["KitnEssentials_Options/Skinning/GUI-DragonRiding.lua"] = { phase = "17" }, -- content after Position
        ["KitnEssentials_Options/Skinning/GUI-Tooltips.lua"] = { phase = "17" }, -- Display after Position
        -- Phase 18 handles these special pages.
        ["KitnEssentials_Options/Combat/ClassTools/GUI-DoTTracker.lua"] = { phase = "18" }, -- content after Font
        ["KitnEssentials_Options/DungeonTools/KicksCasts/GUI-CCTracker.lua"] = { phase = "18" }, -- content after Font
        ["KitnEssentials_Options/Skinning/GUI-CharacterPanel.lua"] = { phase = "18" }, -- content after Font
        ["KitnEssentials_Options/Skinning/GUI-MythicPlusTimer.lua"] = { phase = "18" }, -- content after Position
        -- Interrupt Tracker page: edited only with an approval that names the item.
        ["KitnEssentials_Options/DungeonTools/KicksCasts/GUI-KickTracker.lua"] = { phase = "none until approved" }, -- content after Position
    },
    L4 = {
    },
    L5 = {
        -- Phase 18 handles these special pages.
        ["KitnEssentials_Options/Skinning/GUI-MythicPlusTimer.lua"] = { phase = "18" }, -- return before description
    },
    L6 = {
    },
    L7 = {
        -- Phase 17 moves these onto KE:Gold.
        ["GUI/GUIMain/GUI-Core.lua"] = { phase = "17", n = 1 },
        ["GUI/GUIWidgets/GUI-TauntCursorCard.lua"] = { phase = "17", n = 3 },
        ["KitnEssentials_Options/Combat/ClassTools/GUI-DisintegrateTicks.lua"] = { phase = "17", n = 1 },
        ["KitnEssentials_Options/Combat/ClassTools/GUI-HavocTracker.lua"] = { phase = "17", n = 1 },
        ["KitnEssentials_Options/Combat/ClassTools/GUI-HuntersMark.lua"] = { phase = "17", n = 1 },
        ["KitnEssentials_Options/Combat/ClassTools/GUI-PIAssist.lua"] = { phase = "17", n = 2 },
        ["KitnEssentials_Options/Combat/ClassTools/GUI-PIMacroBuilder.lua"] = { phase = "17", n = 2 },
        ["KitnEssentials_Options/Combat/ClassTools/GUI-ShamanProcCooldowns.lua"] = { phase = "17", n = 1 },
        ["KitnEssentials_Options/Combat/ClassTools/GUI-StasisTracker.lua"] = { phase = "17", n = 1 },
        ["KitnEssentials_Options/Combat/StatusTexts/GUI-PetStatusText.lua"] = { phase = "17", n = 1 },
        ["KitnEssentials_Options/DungeonTools/DungeonTimers/GUI-DungeonTimersCfg.lua"] = { phase = "17", n = 2 },
        ["KitnEssentials_Options/DungeonTools/KeystoneHelper/GUI-LFGReminder.lua"] = { phase = "17", n = 1 },
        ["KitnEssentials_Options/QoL/Automation/GUI-CombatLogger.lua"] = { phase = "17", n = 3 },
        ["KitnEssentials_Options/QoL/QualityOfLife/GUI-MoveFrames.lua"] = { phase = "17", n = 2 },
        ["KitnEssentials_Options/Skinning/DarkTheme/GUI-AlertFrames.lua"] = { phase = "17", n = 1 },
        ["KitnEssentials_Options/Skinning/DarkTheme/GUI-BlizzardFrames.lua"] = { phase = "17", n = 2 },
        ["KitnEssentials_Options/Skinning/DarkTheme/GUI-ColorPicker.lua"] = { phase = "17", n = 1 },
        ["KitnEssentials_Options/Skinning/DarkTheme/GUI-RaidControl.lua"] = { phase = "17", n = 1 },
    },
}

---------------------------------------------------------------------------
-- Titles
---------------------------------------------------------------------------

local RANK = {
    head = 0, ShowIn = 1, content = 2, Display = 3, Position = 4, Font = 5,
    Colors = 6, Backdrop = 7, Glow = 8, Sound = 9, Reset = 10,
}

local DISPLAY_TITLES = {
    ["Display"] = true, ["General"] = true, ["General Settings"] = true,
    ["Display & Visibility"] = true, ["Display Settings"] = true,
}
local SHOW_IN_TITLES = { ["Show In"] = true, ["Active In"] = true, ["Where It Shows"] = true }

-- A title holding one of a family's words is that family's card. Its
-- standard form is the plain title, or "<Element><tail>" where it has a tail.
local WORD_FAMILIES = {
    { kind = "Position", words = { Position = true, Positions = true },
      standard = "Position Settings", tail = " Position" },
    { kind = "Font", words = { Font = true, Fonts = true }, standard = "Font Settings", tail = " Font" },
    { kind = "Colors", words = { Color = true, Colors = true }, standard = "Colors", tail = " Colors" },
    { kind = "Backdrop", words = { Backdrop = true }, standard = "Backdrop" },
    { kind = "Glow", words = { Glow = true }, standard = "Glow", tail = " Glow" },
    { kind = "Sound", words = { Sound = true, Sounds = true }, standard = "Sound", tail = " Sound" },
}

-- One or more words of letters, digits, apostrophes, & or %, single-spaced.
-- A dash is not allowed, so a dashed element title is not a standard form.
local function IsElement(text)
    return text ~= "" and ((" " .. text):gsub(" [%w'&%%]+", "")) == ""
end

local function HasWord(title, words)
    for word in title:gmatch("[%w']+") do
        if words[word] then return true end
    end
    return false
end

-- The title's kind, and whether it is in a standard form.
local function ClassifyTitle(title)
    if title == "Reset" or title:find("^Reset ") then return "Reset", true end
    if SHOW_IN_TITLES[title] then return "ShowIn", title == "Show In" end
    if DISPLAY_TITLES[title] or title:find(" Display Settings$") then
        return "Display", title == "Display Settings"
    end
    for _, family in ipairs(WORD_FAMILIES) do
        if HasWord(title, family.words) then
            if title == family.standard then return family.kind, true end
            local tail = family.tail
            local element = tail and title:sub(-#tail) == tail and title:sub(1, -#tail - 1)
            return family.kind, element and IsElement(element) or false
        end
    end
    return "content", true
end

---------------------------------------------------------------------------
-- Source views
---------------------------------------------------------------------------

-- Two copies of text, each as long as it, so an offset is the same place in
-- both: code blanks the comments; masked also blanks the inside of every
-- string, so structure can be matched without a string's contents fooling it.
local function Strip(text)
    local code, masked = {}, {}
    local i, n = 1, #text
    local function Blank(s) return (s:gsub("[^\n]", " ")) end
    while i <= n do
        local c = text:sub(i, i)
        local level = c == "[" and text:match("^%[(=*)%[", i)
        if c == "-" and text:sub(i + 1, i + 1) == "-" then
            local long = text:match("^%[(=*)%[", i + 2)
            local stop
            if long then
                local _, e = text:find("]" .. long .. "]", i + 4 + #long, true)
                stop = e or n
            else
                local e = text:find("\n", i, true)
                stop = e and e - 1 or n
            end
            local piece = Blank(text:sub(i, stop))
            code[#code + 1], masked[#masked + 1] = piece, piece
            i = stop + 1
        elseif c == '"' or c == "'" then
            local j = i + 1
            while j <= n do
                local d = text:sub(j, j)
                if d == "\\" then
                    j = j + 2
                elseif d == c or d == "\n" then
                    break
                else
                    j = j + 1
                end
            end
            if j > n then j = n end
            code[#code + 1] = text:sub(i, j)
            masked[#masked + 1] = c .. Blank(text:sub(i + 1, j - 1)) .. text:sub(j, j)
            i = j + 1
        elseif level then
            local _, e = text:find("]" .. level .. "]", i + 2 + #level, true)
            local stop = e or n
            local piece = text:sub(i, stop)
            code[#code + 1], masked[#masked + 1] = piece, Blank(piece)
            i = stop + 1
        else
            local e = text:find("[%-\"'%[]", i + 1)
            local stop = e and e - 1 or n
            local piece = text:sub(i, stop)
            code[#code + 1], masked[#masked + 1] = piece, piece
            i = stop + 1
        end
    end
    return table.concat(code), table.concat(masked)
end

local OPENS = { ["function"] = true, ["if"] = true, ["do"] = true, ["repeat"] = true }
local CLOSES = { ["end"] = true, ["until"] = true }
-- Stands for code outside every function.
local FILE_LEVEL = { start = 0, stop = math.huge }

-- Every block in masked as { word, start, stop }, in the order they open,
-- and the function bodies among them. for and while open their block with
-- do, so these four words are enough.
local function Blocks(masked)
    local units, blocks, stack = {}, {}, {}
    for pos, word in masked:gmatch("()%f[%w_]([%a_][%w_]*)") do
        if OPENS[word] then
            local block = { word = word, start = pos, stop = #masked }
            blocks[#blocks + 1] = block
            if word == "function" then units[#units + 1] = block end
            stack[#stack + 1] = block
        elseif CLOSES[word] then
            local top = stack[#stack]
            stack[#stack] = nil
            if top then top.stop = pos end
        end
    end
    return units, blocks
end

-- The innermost function body holding pos.
local function UnitAt(units, pos)
    local best = FILE_LEVEL
    for _, unit in ipairs(units) do
        if unit.start <= pos and pos <= unit.stop and unit.start > best.start then best = unit end
    end
    return best
end

---------------------------------------------------------------------------
-- Card calls
---------------------------------------------------------------------------

local FACTORY_KIND = {
    CreatePositionCard = "Position",
    CreateFontSettingsCard = "Font",
    CreateColorsCard = "Colors",
    CreateDispelTypeColorsCard = "Colors",
    CreateGlowSettingsCard = "Glow",
    CreateAuraGlowCard = "Glow",
    CreateAuraApplicationSoundCard = "Sound",
}
local CARD_CALL = "()GUIFrame%s*:%s*(Create%w*Card)%s*()%("

-- The offset of the bracket that closes the one at open.
local function CloseOf(masked, open)
    local depth = 0
    for i = open, #masked do
        local c = masked:sub(i, i)
        if c == "(" or c == "{" or c == "[" then
            depth = depth + 1
        elseif c == ")" or c == "}" or c == "]" then
            depth = depth - 1
            if depth == 0 then return i end
        end
    end
    return #masked
end

-- The offset just past the first top-level comma inside the brackets.
local function SecondArg(masked, open, close)
    local depth = 0
    for i = open + 1, close - 1 do
        local c = masked:sub(i, i)
        if c == "(" or c == "{" or c == "[" then
            depth = depth + 1
        elseif c == ")" or c == "}" or c == "]" then
            depth = depth - 1
        elseif c == "," and depth == 0 then
            return i + 1
        end
    end
    return nil
end

-- The plain string literal starting at the first non-space from pos, before
-- limit. A literal joined to more text is built at runtime, so it is nil.
local function LiteralAt(code, masked, pos, limit)
    local q = pos and masked:find("%S", pos)
    if not q or q >= limit then return nil end
    local quote = masked:sub(q, q)
    if quote ~= '"' and quote ~= "'" then return nil end
    local e = masked:find(quote, q + 1, true)
    if not e or e >= limit then return nil end
    local after = masked:find("%S", e + 1)
    if after and masked:sub(after, after + 1) == ".." then return nil end
    return code:sub(q + 1, e - 1)
end

-- The first name assigned on the line where the call at pos starts.
local function AssignedName(masked, pos)
    local start = 1
    while true do
        local nl = masked:find("\n", start, true)
        if not nl or nl >= pos then break end
        start = nl + 1
    end
    local prefix = masked:sub(start, pos - 1)
    return prefix:match("^%s*local%s+([%a_][%w_]*)[%s,%w_]*=%s*$")
        or prefix:match("^%s*([%a_][%w_]*)[%s,%w_]*=%s*$")
end

local function Cards(code, masked, units)
    local cards = {}
    for pos, name, open in masked:gmatch(CARD_CALL) do
        local close = CloseOf(masked, open)
        local card = { pos = pos, unit = UnitAt(units, pos), var = AssignedName(masked, pos) }
        if name == "CreateCard" then
            card.title = LiteralAt(code, masked, SecondArg(masked, open, close), close)
            card.isError = card.title == "Error"
            card.handBuilt = card.title == "Position Settings"
            card.kind = card.title and ClassifyTitle(card.title) or "content"
        else
            local key = masked:find("%f[%w_]title%s*=%s*[\"']", open)
            if key and key < close then
                card.title = LiteralAt(code, masked, masked:find("[\"']", key), close)
            end
            card.kind = FACTORY_KIND[name] or "content"
        end
        cards[#cards + 1] = card
    end
    return cards
end

---------------------------------------------------------------------------
-- Checks
---------------------------------------------------------------------------

local function Positions(masked, pattern)
    local found = {}
    for pos in masked:gmatch(pattern) do found[#found + 1] = pos end
    return found
end

-- The positions in list after from and before limit that sit in unit itself,
-- not in a function nested inside it.
local function InUnit(list, units, unit, from, limit)
    local found = {}
    for _, pos in ipairs(list) do
        if pos > from and pos < limit and UnitAt(units, pos) == unit then found[#found + 1] = pos end
    end
    return found
end

local RETURN = "()%f[%w_]return%f[^%w_]"
local TABBED_CALL = "RegisterTabbedContent%s*()%("
local TAB_ID = "%f[%w_]id%s*=%f[^=]%s*()"
local BUILDER = "RegisterContent%s*%(%s*()[\"']"
local SIDEBAR = "sidebarConfig%s*=%s*()%{"
local SIDEBAR_ITEMS = "%f[%w_]items%s*=%s*()%{"
local ENABLED = "%.Enabled%f[^%w_]"
local DB_ENABLED = "()%f[%w_]db%.Enabled%f[^%w_]"

-- The literal ids between from and stop, in order.
local function LiteralIds(code, masked, from, stop)
    local ids = {}
    while true do
        local s, _, at = masked:find(TAB_ID, from)
        if not s or s > stop then return ids end
        ids[#ids + 1] = LiteralAt(code, masked, at, stop) or false
        from = at
    end
end

-- Adds each literal tab list's first id to index.first, and the id of every
-- row in a GUIFrame.sidebarConfig items list to index.sidebar; section ids
-- are not pages. A tab list built by a function or held in a constant adds
-- nothing, so its tabs are never taken for sidebar pages.
local function IndexPages(code, masked, index)
    for open in masked:gmatch(TABBED_CALL) do
        local close = CloseOf(masked, open)
        local list = SecondArg(masked, open, close)
        local brace = list and masked:find("%S", list)
        if brace and masked:sub(brace, brace) == "{" then
            local first = LiteralIds(code, masked, brace, CloseOf(masked, brace))[1]
            if first then index.first[first] = true end
        end
    end
    for open in masked:gmatch(SIDEBAR) do
        local stop = CloseOf(masked, open)
        for items in masked:sub(1, stop):gmatch(SIDEBAR_ITEMS) do
            if items > open then
                for _, id in ipairs(LiteralIds(code, masked, items, CloseOf(masked, items))) do
                    if id then index.sidebar[id] = true end
                end
            end
        end
    end
end

-- The units passed as a tab host's headerBuilder: inline, or by name when
-- the file has exactly one local function of that name. With two or more,
-- which one is in scope is not resolved, and none is taken.
local function HeaderUnits(masked, units)
    local starts, heads = {}, {}
    for _, unit in ipairs(units) do starts[unit.start] = unit end
    for value in masked:gmatch("headerBuilder%s*=%s*()") do
        local name = masked:match("^([%a_][%w_]*)", value)
        local at = name == "function" and value or nil
        if name and name ~= "function" then
            local defs = Positions(masked, "local%s+()function%s+" .. name .. "%s*%(")
            if #defs == 1 then at = defs[1] end
        end
        if at and starts[at] then heads[starts[at]] = true end
    end
    return heads
end

-- The innermost block holding pos.
local function BlockAt(blocks, pos)
    local best
    for _, block in ipairs(blocks) do
        if block.start < pos and pos < block.stop and (not best or block.start > best.start) then
            best = block
        end
    end
    return best
end

-- Whether the if block's own conditions before pos, its if and each of its
-- elseifs, read .Enabled directly. Conditions of nested ifs and code in
-- nested functions belong to other blocks and are not read. A local that
-- holds the enable state is not followed.
local function TestsEnabled(masked, blocks, block, pos)
    local open
    local text = masked:sub(block.start, pos)
    for rel, word in text:gmatch("()%f[%w_]([%a_][%w_]*)") do
        local at = block.start + rel - 1
        if (word == "if" and at == block.start) or (word == "elseif" and BlockAt(blocks, at) == block) then
            open = at + #word
        elseif word == "then" and open and BlockAt(blocks, at) == block then
            if masked:sub(open, at - 1):find(ENABLED) then return true end
            open = nil
        end
    end
    return false
end

-- unit -> id, for each RegisterContent("<id>", function ...) builder.
local function BuilderIds(code, masked, units)
    local starts = {}
    for _, unit in ipairs(units) do starts[unit.start] = unit end
    local ids = {}
    for q in masked:gmatch(BUILDER) do
        local close = masked:find(masked:sub(q, q), q + 1, true)
        local fn = close and select(3, masked:find("^%s*,%s*()function%f[^%w_]", close + 1))
        if fn and starts[fn] then ids[starts[fn]] = code:sub(q + 1, close - 1) end
    end
    return ids
end

-- Whether the header switch at pos takes its value from a key named Enabled.
local function ReadsEnabled(masked, pos)
    local open = masked:find("%(", pos)
    local close = CloseOf(masked, open)
    local stop = SecondArg(masked, open, close) or close
    return masked:sub(open + 1, stop - 1):find(ENABLED) ~= nil
end

-- L1-L6 for one page, then how many card calls and header switches it has.
local function PageChecks(path, code, masked, index)
    local found = { L1 = {}, L2 = {}, L3 = {}, L4 = {}, L5 = {}, L6 = {} }
    local units, blocks = Blocks(masked)
    local cards = Cards(code, masked, units)
    local ids = BuilderIds(code, masked, units)
    local headers = HeaderUnits(masked, units)
    local returns = Positions(masked, RETURN)
    local dbReads = Positions(masked, DB_ENABLED)

    local byUnit, unitOrder, handBuilt = {}, {}, 0
    for _, card in ipairs(cards) do
        if not card.isError then
            if card.handBuilt then handBuilt = handBuilt + 1 end
            local list = byUnit[card.unit]
            if not list then
                list = {}
                byUnit[card.unit] = list
                unitOrder[#unitOrder + 1] = card.unit
            end
            list[#list + 1] = card
        end
    end
    if handBuilt > 0 then found.L2[path] = handBuilt end

    for _, unit in ipairs(unitOrder) do
        local list = byUnit[unit]
        local first = list[1]
        local limit = list[2] and list[2].pos or unit.stop
        local toggles, labels = {}, {}
        if first.var then
            local name = first.var
            toggles = InUnit(Positions(masked, "()%f[%w_]" .. name .. "%s*:%s*AddHeaderToggle%s*%("),
                units, unit, first.pos, limit)
            labels = InUnit(Positions(masked, "()%f[%w_]" .. name .. "%s*:%s*AddLabel%s*%("),
                units, unit, first.pos, limit)
        end
        local head = #toggles > 0
        local module = head and ReadsEnabled(masked, toggles[1])
        local id = ids[unit]
        local sidebarPage = id ~= nil and index.sidebar[id] == true
        -- A later tab may depart from the order unless it is a module's own
        -- page; a tab whose list could not be read is not ordered.
        local ordered = module or sidebarPage or (id ~= nil and index.first[id] == true)

        local top, topKind = -1, nil
        for i, card in ipairs(list) do
            local isHead = head and i == 1
            if card.title and not isHead then
                local _, standard = ClassifyTitle(card.title)
                if not standard then found.L1[path .. "|" .. card.title] = true end
            end
            if ordered then
                local kind = isHead and "head" or card.kind
                local rank = RANK[kind]
                if rank < top then
                    found.L3[path] = found.L3[path] or (kind .. " after " .. topKind)
                elseif rank > top then
                    top, topKind = rank, kind
                end
            end
        end

        -- A sidebar page or tab header that itself reads db.Enabled is a
        -- module's page, so its first card must carry the switch. A read in
        -- a nested callback belongs to that callback.
        if not head and (sidebarPage or headers[unit])
            and #InUnit(dbReads, units, unit, unit.start, unit.stop) > 0 then
            found.L4[path] = "no switch"
        end

        if module then
            local label = labels[1]
            if not label then
                found.L4[path] = "no description"
            elseif #toggles > 1 then
                found.L4[path] = #toggles .. " switches"
            end
            if label then
                if #InUnit(returns, units, unit, first.pos, label) > 0 then
                    found.L5[path] = "return before description"
                else
                    -- Only an if that tests the enable state hides the
                    -- description from a module that is off.
                    for _, block in ipairs(blocks) do
                        if block.word == "if" and block.start > first.pos and block.start < label
                            and label < block.stop and UnitAt(units, block.start) == unit
                            and TestsEnabled(masked, blocks, block, label) then
                            found.L5[path] = "description behind an enable test"
                        end
                    end
                end
            end
        end
    end

    local chat = #Positions(masked, "()%f[%w_]msgPopup%f[^%w_]")
    if chat > 0 then found.L6[path] = chat end

    return found, #cards, #Positions(masked, "()AddHeaderToggle%s*%(")
end

-- L1 for a factory's own titles: each config.title or "<literal>" default,
-- and each CreateCard whose title is a literal.
local function FactoryTitles(path, code, masked)
    local found = {}
    local function Check(title)
        if not title then return end
        local _, standard = ClassifyTitle(title)
        if not standard then found[path .. "|" .. title] = true end
    end
    for q in masked:gmatch("config%.title%s+or%s+()[\"']") do
        Check(LiteralAt(code, masked, q, math.huge))
    end
    for _, open in ipairs(Positions(masked, "GUIFrame%s*:%s*CreateCard%s*()%(")) do
        local close = CloseOf(masked, open)
        Check(LiteralAt(code, masked, SecondArg(masked, open, close), close))
    end
    return found
end

local function GoldCount(code)
    local lower, n, from = code:lower(), 0, 1
    while true do
        local _, e = lower:find("|cffffd100", from, true)
        if not e then return n end
        n, from = n + 1, e + 1
    end
end

local function readFile(path)
    local f = assert(io.open(path, "r"))
    local text = f:read("*a")
    f:close()
    return text
end

local function walkLuaFiles(dir, acc)
    for entry in lfs.dir(dir) do
        if entry ~= "." and entry ~= ".." then
            local path = dir .. "/" .. entry
            local mode = lfs.attributes(path, "mode")
            if mode == "directory" then
                walkLuaFiles(path, acc)
            elseif mode == "file" and entry:match("%.lua$") then
                acc[#acc + 1] = path
            end
        end
    end
    return acc
end

-- first: the first id of each literal tab list; sidebar: every id in
-- GUIFrame.sidebarConfig.
local function NewIndex() return { first = {}, sidebar = {} } end

-- Every check for one source, with its own tab lists and sidebar rows
-- indexed and L7 counted on the same text.
local function CheckSource(path, text)
    local code, masked = Strip(text)
    local index = NewIndex()
    IndexPages(code, masked, index)
    local found = PageChecks(path, code, masked, index)
    local gold = GoldCount(code)
    found.L7 = gold > 0 and { [path] = gold } or {}
    return found
end

-- What differs between found and allowed for one check: an offender with no
-- entry, a count that moved, an entry with nothing left to excuse, or an
-- entry naming no known phase.
local function Diff(check, found, allowed)
    found = found or {}
    local out = {}
    for key, value in pairs(found) do
        local entry = allowed[key]
        if not entry then
            local detail = ""
            if COUNTED[check] then
                detail = " n=" .. value
            elseif type(value) == "string" then
                detail = " (" .. value .. ")"
            end
            out[#out + 1] = check .. " unlisted " .. key .. detail
        elseif COUNTED[check] and entry.n ~= value then
            out[#out + 1] = check .. " count " .. key .. " n=" .. value .. ", listed n=" .. tostring(entry.n)
        end
    end
    for key, entry in pairs(allowed) do
        if found[key] == nil then out[#out + 1] = check .. " stale " .. key end
        if not PHASES[entry.phase] then out[#out + 1] = check .. " phase " .. key end
    end
    table.sort(out)
    return out
end

local function Sweep()
    local found, stats = {}, { files = 0, cards = 0, toggles = 0 }
    for _, check in ipairs(CHECKS) do found[check] = {} end
    local paths = walkLuaFiles("KitnEssentials_Options", {})
    for _, path in ipairs(EXTRA_PAGES) do paths[#paths + 1] = path end
    -- A host's tab list, the sidebar and the tabs' builders sit in
    -- different files, so every list is indexed before any page is checked.
    local index, pages = NewIndex(), {}
    local sidebarCode, sidebarMasked = Strip(readFile(SIDEBAR_FILE))
    IndexPages(sidebarCode, sidebarMasked, index)
    for i, path in ipairs(paths) do
        local code, masked = Strip(readFile(path))
        IndexPages(code, masked, index)
        pages[i] = { path = path, code = code, masked = masked }
    end
    for _, page in ipairs(pages) do
        local result, cards, toggles = PageChecks(page.path, page.code, page.masked, index)
        for check, keys in pairs(result) do
            for key, value in pairs(keys) do found[check][key] = value end
        end
        stats.files = stats.files + 1
        stats.cards = stats.cards + cards
        stats.toggles = stats.toggles + toggles
    end
    for _, path in ipairs(FACTORY_FILES) do
        local code, masked = Strip(readFile(path))
        for key, value in pairs(FactoryTitles(path, code, masked)) do found.L1[key] = value end
    end
    for _, dir in ipairs(GOLD_DIRS) do
        for _, path in ipairs(walkLuaFiles(dir, {})) do
            local gold = GoldCount((Strip(readFile(path))))
            if gold > 0 then found.L7[path] = gold end
        end
    end
    return found, stats
end

local SAMPLE = "KitnEssentials_Options/Sample/GUI-Sample.lua"

-- A module page that meets the standard, with body added after its
-- module-off return.
local function Page(body)
    return table.concat({
        'GUIFrame:RegisterContent("Sample", function(scrollChild, yOffset)',
        "    local db = KE.db.profile.Sample",
        '    local card1 = GUIFrame:CreateCard(scrollChild, "Sample", yOffset)',
        "    card1:AddHeaderToggle(db.Enabled ~= false, function(checked) db.Enabled = checked end)",
        '    card1:AddLabel("Does one thing.")',
        "    if db.Enabled == false then return card1:GetNextOffset() end",
        table.concat(body, "\n"),
        "    return yOffset",
        "end)",
    }, "\n")
end

-- A tab host whose first tab is SampleMain, followed by the inline builder
-- of tab id with body inside it.
local HOST = table.concat({
    'GUIFrame:RegisterTabbedContent("Sample", {',
    '    { id = "SampleMain", label = "Main" },',
    '    { id = "SampleMore", label = "More" },',
    "}, { headerBuilder = BuildHeader })",
}, "\n")

local function Tab(id, body)
    return table.concat({
        HOST,
        'GUIFrame:RegisterContent("' .. id .. '", function(scrollChild, yOffset)',
        "    local db = KE.db.profile.Sample",
        table.concat(body, "\n"),
        "    return yOffset",
        "end)",
    }, "\n")
end

-- A sidebar row for Sample, followed by Sample's inline builder with body
-- inside it.
local function Sidebar(body)
    return table.concat({
        "GUIFrame.sidebarConfig = {",
        '    { id = "core", type = "header", items = { { id = "Sample", text = "Sample" } } },',
        "}",
        'GUIFrame:RegisterContent("Sample", function(scrollChild, yOffset)',
        "    local db = KE.db.profile.Sample",
        table.concat(body, "\n"),
        "    return yOffset",
        "end)",
    }, "\n")
end

local STANDARD_PAGE = table.concat({
    'GUIFrame:RegisterContent("Sample", function(scrollChild, yOffset)',
    "    local db = KE.db and KE.db.profile.Sample",
    "    if not db then",
    '        local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)',
    '        errorCard:AddLabel("Database not available")',
    "        return errorCard:GetNextOffset()",
    "    end",
    "    local function AddListCard(title)",
    "        local list = GUIFrame:CreateCard(scrollChild, title, yOffset)",
    "        return list:GetNextOffset()",
    "    end",
    '    local card1 = GUIFrame:CreateCard(scrollChild, "Sample", yOffset)',
    "    card1:AddHeaderToggle(db.Enabled ~= false, function(checked)",
    "        db.Enabled = checked",
    "        if not checked then return end",
    "    end)",
    '    card1:AddLabel("Does one thing.")',
    "    yOffset = card1:GetNextOffset()",
    "    if db.Enabled == false then return yOffset end",
    '    local shown = GUIFrame:CreateCard(scrollChild, "Show In", yOffset)',
    '    local display = GUIFrame:CreateCard(scrollChild, "Display Settings", yOffset)',
    '    local _, posOffset = GUIFrame:CreatePositionCard(scrollChild, yOffset, { title = "Bar Position" })',
    "    local _, fontOffset = GUIFrame:CreateFontSettingsCard(scrollChild, yOffset, {})",
    "    yOffset = GUIFrame:CreateColorsCard(scrollChild, yOffset, {})",
    '    local backdrop = GUIFrame:CreateCard(scrollChild, "Backdrop", yOffset)',
    '    GUIFrame:CreateGlowSettingsCard(scrollChild, yOffset, { title = "Glow" })',
    "    GUIFrame:CreateAuraApplicationSoundCard(scrollChild, yOffset, {})",
    '    local reset = GUIFrame:CreateCard(scrollChild, "Reset", yOffset)',
    "    return yOffset",
    "end)",
}, "\n")

local ROWS = {
    { name = "L1: a family title in a variant form", check = "L1", key = SAMPLE .. "|Glow Settings",
      src = Page({ '    local glow = GUIFrame:CreateCard(scrollChild, "Glow Settings", yOffset)' }) },
    { name = "L1: a factory's default title in a variant form", check = "L1", factory = true,
      path = "GUI/GUIWidgets/GUI-Sample.lua", key = "GUI/GUIWidgets/GUI-Sample.lua|Glow Settings",
      src = '    local title = config.title or "Glow Settings"' },
    { name = "L1: a factory's fixed card title in a variant form", check = "L1", factory = true,
      path = "GUI/GUIWidgets/GUI-Sample.lua", key = "GUI/GUIWidgets/GUI-Sample.lua|Glow Settings",
      src = '    local card = GUIFrame:CreateCard(scrollChild, "Glow Settings", yOffset)' },
    { name = "L2: a hand-built Position Settings card", check = "L2", key = SAMPLE, n = 1,
      src = Page({ '    local pos = GUIFrame:CreateCard(scrollChild, "Position Settings", yOffset)' }) },
    { name = "L3: a factory Position card after the Font card", check = "L3", key = SAMPLE,
      detail = "Position after Font",
      src = Page({
          "    GUIFrame:CreateFontSettingsCard(scrollChild, yOffset, {})",
          "    GUIFrame:CreatePositionCard(scrollChild, yOffset, {})",
      }) },
    { name = "L3: a literal Sound card before the Glow card", check = "L3", key = SAMPLE,
      detail = "Glow after Sound",
      src = Page({
          '    local sound = GUIFrame:CreateCard(scrollChild, "Sound", yOffset)',
          '    local glow = GUIFrame:CreateCard(scrollChild, "Glow", yOffset)',
      }) },
    { name = "L3: a content card before Show In", check = "L3", key = SAMPLE,
      detail = "ShowIn after content",
      src = Page({
          '    local thing = GUIFrame:CreateCard(scrollChild, "Thing", yOffset)',
          '    local shown = GUIFrame:CreateCard(scrollChild, "Show In", yOffset)',
      }) },
    { name = "L3: a host's first tab, with no switch, Position after Font", check = "L3", key = SAMPLE,
      detail = "Position after Font",
      src = Tab("SampleMain", {
          "    GUIFrame:CreateFontSettingsCard(scrollChild, yOffset, {})",
          "    GUIFrame:CreatePositionCard(scrollChild, yOffset, {})",
      }) },
    { name = "L3: a sidebar page with no switch, Position after Font", check = "L3", key = SAMPLE,
      detail = "Position after Font",
      src = Sidebar({
          "    GUIFrame:CreateFontSettingsCard(scrollChild, yOffset, {})",
          "    GUIFrame:CreatePositionCard(scrollChild, yOffset, {})",
      }) },
    { name = "L4: a sidebar page that reads db.Enabled with no switch", check = "L4", key = SAMPLE,
      detail = "no switch",
      src = Sidebar({
          '    local card1 = GUIFrame:CreateCard(scrollChild, "Sample", yOffset)',
          '    card1:AddLabel("Does one thing.")',
          "    if db.Enabled == false then return card1:GetNextOffset() end",
      }) },
    { name = "clean: a sidebar page with no switch whose nested callback reads db.Enabled", clean = true,
      src = Sidebar({
          '    local card1 = GUIFrame:CreateCard(scrollChild, "Sample", yOffset)',
          "    card1:AddButton('Test', function() local db = KE.db.profile.Other return db.Enabled end)",
      }) },
    { name = "L4: a tab header builder that reads db.Enabled with no switch", check = "L4", key = SAMPLE,
      detail = "no switch",
      src = table.concat({
          "local function BuildHeader(scrollChild, yOffset)",
          "    local db = KE.db.profile.Sample",
          '    local card = GUIFrame:CreateCard(scrollChild, "Sample", yOffset)',
          '    card:AddLabel("Does one thing.")',
          "    return card:GetNextOffset(), db.Enabled == false",
          "end",
          HOST,
      }, "\n") },
    { name = "L4: a module card with no description", check = "L4", key = SAMPLE,
      detail = "no description",
      src = table.concat({
          'GUIFrame:RegisterContent("Sample", function(scrollChild, yOffset)',
          "    local db = KE.db.profile.Sample",
          '    local card1 = GUIFrame:CreateCard(scrollChild, "Sample", yOffset)',
          "    card1:AddHeaderToggle(db.Enabled ~= false, function(checked) db.Enabled = checked end)",
          "    return card1:GetNextOffset()",
          "end)",
      }, "\n") },
    { name = "L5: the description after the module-off return", check = "L5", key = SAMPLE,
      detail = "return before description",
      src = table.concat({
          'GUIFrame:RegisterContent("Sample", function(scrollChild, yOffset)',
          "    local db = KE.db.profile.Sample",
          '    local card1 = GUIFrame:CreateCard(scrollChild, "Sample", yOffset)',
          "    card1:AddHeaderToggle(db.Enabled ~= false, function(checked) db.Enabled = checked end)",
          "    if db.Enabled == false then return card1:GetNextOffset() end",
          '    card1:AddLabel("Does one thing.")',
          "    return card1:GetNextOffset()",
          "end)",
      }, "\n") },
    { name = "L5: the description behind an if that reads .Enabled", check = "L5", key = SAMPLE,
      detail = "description behind an enable test",
      src = table.concat({
          "local function BuildHeader(scrollChild, yOffset)",
          "    local db = KE.db.profile.Sample",
          '    local card = GUIFrame:CreateCard(scrollChild, "Sample", yOffset)',
          "    card:AddHeaderToggle(db.Enabled ~= false, function(checked) db.Enabled = checked end)",
          '    if db.Enabled ~= false then card:AddLabel("Does one thing.") end',
          "    return card:GetNextOffset(), db.Enabled == false",
          "end",
      }, "\n") },
    { name = "L6: a body control that prints a chat line", check = "L6", key = SAMPLE, n = 1,
      src = Page({ '    local box = GUIFrame:CreateCheckbox(row, "Thing", { msgPopup = true })' }) },
    { name = "L7: a hand-written gold color code", check = "L7", key = SAMPLE, n = 1,
      src = Page({ '    card1:AddNote("Type |cffffd100/kes|r to open it.")' }) },
    { name = "clean: the standard page", clean = true, src = STANDARD_PAGE },
    { name = "clean: a later tab with no switch, cards out of order", clean = true,
      src = Tab("SampleMore", {
          "    GUIFrame:CreateFontSettingsCard(scrollChild, yOffset, {})",
          "    GUIFrame:CreatePositionCard(scrollChild, yOffset, {})",
      }) },
    { name = "clean: a later tab's feature switch not keyed Enabled, no description, cards out of order",
      clean = true,
      src = Tab("SampleMore", {
          '    local card = GUIFrame:CreateCard(scrollChild, "Kick Macro", yOffset)',
          "    card:AddHeaderToggle(db.KickMacroEnabled ~= false, function(checked) db.KickMacroEnabled = checked end)",
          "    if db.KickMacroEnabled == false then return card:GetNextOffset() end",
          "    GUIFrame:CreateFontSettingsCard(scrollChild, yOffset, {})",
          "    GUIFrame:CreatePositionCard(scrollChild, yOffset, {})",
      }) },
    { name = "clean: a description inside do and an if that reads no .Enabled itself", clean = true,
      src = table.concat({
          'GUIFrame:RegisterContent("Sample", function(scrollChild, yOffset)',
          "    local db = KE.db.profile.Sample",
          '    local card1 = GUIFrame:CreateCard(scrollChild, "Sample", yOffset)',
          "    card1:AddHeaderToggle(db.Enabled ~= false, function(checked) db.Enabled = checked end)",
          "    local disabled = db.Enabled == false",
          "    do",
          "        if not disabled then",
          "            card1:AddButton('Test', function() if db.Enabled then return end end)",
          '            card1:AddLabel("Does one thing here.")',
          "        else",
          '            card1:AddLabel("Does one thing.")',
          "        end",
          "    end",
          "    if db.Enabled == false then return card1:GetNextOffset() end",
          "    return card1:GetNextOffset()",
          "end)",
      }, "\n") },
}

describe("settings page standard", function()
    it("fails each check's offender, passes it once listed, and passes the standard shapes", function()
        for _, row in ipairs(ROWS) do
            local path = row.path or SAMPLE
            local found
            if row.factory then
                local code, masked = Strip(row.src)
                found = { L1 = FactoryTitles(path, code, masked) }
            else
                found = CheckSource(path, row.src)
            end
            if row.clean then
                for _, check in ipairs(CHECKS) do
                    assert.same({}, Diff(check, found[check], {}), row.name .. ", " .. check)
                end
            else
                local suffix = row.n and (" n=" .. row.n) or row.detail and (" (" .. row.detail .. ")") or ""
                local unlisted = row.check .. " unlisted " .. row.key .. suffix
                assert.same({ unlisted }, Diff(row.check, found[row.check], {}), row.name)
                local listed = { [row.key] = { phase = "16", n = row.n } }
                assert.same({}, Diff(row.check, found[row.check], listed), row.name)
            end
        end

        local found = CheckSource(SAMPLE, STANDARD_PAGE)
        assert.same({ "L4 stale " .. SAMPLE }, Diff("L4", found.L4, { [SAMPLE] = { phase = "16" } }))
    end)

    it("holds every settings page to the standard, apart from the listed ones", function()
        local found, stats = Sweep()
        assert.is_true(stats.files > 80, "positive control: the settings pages were walked")
        assert.is_true(stats.cards > 300, "positive control: card calls were read")
        assert.is_true(stats.toggles > 70, "positive control: header switches were read")
        local problems = {}
        for _, check in ipairs(CHECKS) do
            for _, line in ipairs(Diff(check, found[check], ALLOWED[check])) do
                problems[#problems + 1] = line
            end
        end
        assert.same({}, problems, table.concat(problems, "\n"))
    end)
end)
