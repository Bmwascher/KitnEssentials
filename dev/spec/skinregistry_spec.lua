-- ╔══════════════════════════════════════════════════════════╗
-- ║  dev/spec/skinregistry_spec.lua                          ║
-- ║  Proves the config grid and the S:Register dispatcher    ║
-- ║  agree on every key, AND that every WINDOW_MAP addon     ║
-- ║  filter names an addon a real registration actually uses. ║
-- ╚══════════════════════════════════════════════════════════╝
--
-- The gate this closes: GUI/GUITabs/GUISkinning/GUI-BlizzardFrames.lua reads
-- `Skins[key] ~= false`, so a key nothing registers is always "on" and a
-- misspelt row controls nothing. Neither direction of that typo shows up any
-- other way -- it is silent in-game and silent in luacheck.
--
-- The grid/dispatcher agreement above reads both source trees as TEXT. The
-- dead-filter guard (Task 15) cannot: WINDOW_MAP nests `skins` and `addons`
-- lists, and a second hand-rolled text parser for that shape would be its
-- own defect surface. So this file ALSO loads
-- Modules/Skinning/EUIWindows.lua for real, through dev/spec/_ke_loader.lua,
-- and reads S.WINDOW_MAP as an actual Lua table.

local lfs = require("lfs")
local L = require("dev.spec._ke_loader")

local GUI_FILE = "GUI/GUITabs/GUISkinning/GUI-BlizzardFrames.lua"
local SKINNING_ROOT = "Modules/Skinning"

-- Keys the reference always dispatches with no grid row, cited at
-- GUI-BlizzardFrames.lua (minor or loading-screen-rare frames). A row
-- is not required for these -- it is also not FORBIDDEN, so ChatConfig and
-- Dialogs correctly appear both here and as grid rows (Deviation 3).
local ALWAYS_ON = {
    AdventureMap = true, Battlenet = true, ChatConfig = true,
    ChromieTime = true, CooldownManager = true, Dialogs = true,
    ExtraButtons = true, Help = true, PetBattle = true,
    Runeforge = true, SharedDropDownList = true, TimeManager = true,
    TooltipStatusBar = true, TutorialFrame = true,
}

-- Rows that are deliberately NOT dispatcher-backed. ContextMenus is an
-- AceAddon module with its own Enabled flag and its own isOn/onToggle
-- accessors, so it has a grid row and no S:Register call. Adding a key
-- here is a decision, not a workaround -- anything else in FRAME_SKINS
-- or ADDON_SKINS must be registered.
local NON_REGISTRY_ROWS = { ContextMenus = true }

local function readFile(path)
    local f, err = io.open(path, "r")
    if not f then error("could not open " .. path .. ": " .. tostring(err), 2) end
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

-- Advances past a string literal or a comment starting at position i in
-- text, returning the position just after it, plus the literal's contents
-- when it was a string (nil for a comment). Both must be skipped whole so a
-- stray paren or quote inside either can never desync the depth count below.
local function skipStringOrComment(text, i)
    local c = text:sub(i, i)
    if c == '"' or c == "'" then
        local quote = c
        local j = i + 1
        local len = #text
        while j <= len do
            local cj = text:sub(j, j)
            if cj == "\\" then
                j = j + 2
            elseif cj == quote then
                break
            else
                j = j + 1
            end
        end
        return j + 1, text:sub(i + 1, j - 1)
    end
    if text:sub(i, i + 1) == "--" then
        local eqs, longStart = text:match("^%-%-%[(=*)%[()", i)
        if eqs then
            local closeStart, closeEnd = text:find("%]" .. eqs .. "%]", longStart)
            if closeStart then return closeEnd + 1, nil end
            return #text + 1, nil
        end
        local nl = text:find("\n", i)
        return (nl and nl + 1 or #text + 1), nil
    end
    return nil, nil
end

-- Given the position right after a call's opening '(', walks forward with
-- balanced-paren depth tracking (across newlines) until that same paren
-- closes, and returns every string literal seen at the call's own argument
-- depth, in order. A NESTED CALL's arguments sit one depth deeper and are
-- never collected, so the LAST entry is normally the call's last string
-- ARGUMENT -- exactly the skin key.
--
-- KNOWN LIMIT: an inline `function() ... end` argument does NOT raise the
-- depth (its `()` opens and closes immediately), so a bare string literal
-- in such a body WOULD be collected and could be mistaken for the key.
-- The two registrations that pass a function literal --
-- Frames/EncounterJournal.lua and GlobalFonts.lua -- contain no
-- string literals at all, so this is latent rather than live. A future
-- inline body with a bare string needs that argument hoisted to a named
-- local, or this scanner taught to skip `function`..`end` spans.
local function callArgStrings(text, startPos)
    local depth = 1
    local i = startPos
    local len = #text
    local strings = {}
    while i <= len do
        local c = text:sub(i, i)
        if c == '"' or c == "'" or text:sub(i, i + 1) == "--" then
            local nextPos, literal = skipStringOrComment(text, i)
            if literal and depth == 1 then
                strings[#strings + 1] = literal
            end
            i = nextPos
        elseif c == "(" then
            depth = depth + 1
            i = i + 1
        elseif c == ")" then
            depth = depth - 1
            if depth == 0 then return strings end
            i = i + 1
        else
            i = i + 1
        end
    end
    return strings
end

-- Scans one file's text for every S:Register(...) / S:RegisterEarly(...)
-- call and adds the last string argument of each to `registrations[key]`,
-- alongside the call's addon (the FIRST depth-1 string) -- or `false` for a
-- RegisterEarly call, which has no addon argument at all. %a* covers both
-- spellings ("Register" / "RegisterEarly") in one pass.
--
-- A zero-string match is how the scanner steps over S:Register's and
-- S:RegisterEarly's own function DEFINITIONS in SkinAPI.lua (their parameter
-- lists are bare identifiers, never string literals) -- `if key then` skips
-- it, same as before this file recorded addons. A plain S:Register call
-- yielding only ONE string is different: it means the addon was passed as a
-- variable, which this codebase never does, and silently skipping it would
-- make the dead-filter guard below vacuous for exactly the file that broke
-- the convention -- so that case is a hard failure instead.
local function collectRegistrations(text, registrations, path)
    local pos = 1
    while true do
        local s, e = text:find("S:Register%a*%s*%(", pos)
        if not s then break end
        local isEarly = text:sub(s, e):find("RegisterEarly", 1, true) ~= nil
        local strings = callArgStrings(text, e + 1)
        local key = strings[#strings]
        if key then
            local addon = false
            if not isEarly then
                if #strings < 2 then
                    error("S:Register call in " .. path
                        .. " has no addon string literal -- addon passed as a variable?", 0)
                end
                addon = strings[1]
            end
            registrations[key] = registrations[key] or {}
            registrations[key][#registrations[key] + 1] = addon
        end
        pos = e + 1
    end
end

-- Given the position of a `local NAME = {` assignment's opening brace,
-- returns the substring of its balanced body (braces only, same
-- string/comment-aware skipping as callArgStrings).
local function balancedBraceBody(text, openPos)
    local depth = 1
    local i = openPos + 1
    local len = #text
    while i <= len do
        local c = text:sub(i, i)
        if c == '"' or c == "'" or text:sub(i, i + 1) == "--" then
            local nextPos = skipStringOrComment(text, i)
            i = nextPos
        elseif c == "{" then
            depth = depth + 1
            i = i + 1
        elseif c == "}" then
            depth = depth - 1
            if depth == 0 then return text:sub(openPos + 1, i - 1) end
            i = i + 1
        else
            i = i + 1
        end
    end
    error("unbalanced braces starting at " .. openPos)
end

-- Extracts the ordered list of `key = "..."` values from a table body.
local function extractKeys(body)
    local keys = {}
    for key in body:gmatch('key%s*=%s*"([^"]*)"') do
        keys[#keys + 1] = key
    end
    return keys
end

local function tableBody(text, varName)
    local s = text:find(varName .. "%s*=%s*{")
    if not s then error("could not find " .. varName .. " table in " .. GUI_FILE) end
    local openPos = text:find("{", s)
    return balancedBraceBody(text, openPos)
end

local function toSet(list)
    local set = {}
    for _, v in ipairs(list) do set[v] = true end
    return set
end

describe("skin grid and dispatcher agree (GUI-BlizzardFrames.lua <-> Modules/Skinning/*)", function()
    local guiText = readFile(GUI_FILE)
    local frameKeys = extractKeys(tableBody(guiText, "FRAME_SKINS"))
    local addonKeys = extractKeys(tableBody(guiText, "ADDON_SKINS"))
    local frameKeySet = toSet(frameKeys)
    local addonKeySet = toSet(addonKeys)

    local registrations = {}
    local files = walkLuaFiles(SKINNING_ROOT, {})
    assert(#files > 0, "expected at least one .lua file under " .. SKINNING_ROOT)
    for _, path in ipairs(files) do
        collectRegistrations(readFile(path), registrations, path)
    end

    it("registers every FRAME_SKINS / ADDON_SKINS key somewhere under Modules/Skinning/, except NON_REGISTRY_ROWS", function()
        local missing = {}
        local function check(keys)
            for _, key in ipairs(keys) do
                if not NON_REGISTRY_ROWS[key] and not registrations[key] then
                    missing[#missing + 1] = key
                end
            end
        end
        check(frameKeys)
        check(addonKeys)
        table.sort(missing)
        assert.same({}, missing,
            "grid row(s) with no matching S:Register/S:RegisterEarly call: " .. table.concat(missing, ", "))
    end)

    it("gives every registered key a grid row or an ALWAYS_ON entry", function()
        local unaccounted = {}
        for key in pairs(registrations) do
            if not frameKeySet[key] and not addonKeySet[key] and not ALWAYS_ON[key] then
                unaccounted[#unaccounted + 1] = key
            end
        end
        table.sort(unaccounted)
        assert.same({}, unaccounted,
            "registered key(s) with no grid row and no ALWAYS_ON entry: " .. table.concat(unaccounted, ", "))
    end)

    it("has no key in both FRAME_SKINS and ADDON_SKINS", function()
        local both = {}
        for key in pairs(frameKeySet) do
            if addonKeySet[key] then both[#both + 1] = key end
        end
        table.sort(both)
        assert.same({}, both, "key(s) present in both FRAME_SKINS and ADDON_SKINS: " .. table.concat(both, ", "))
    end)

    -- Task 15's dead-filter guard: WINDOW_MAP's `addons` filter matches
    -- EllesmereUI's own coverage per Blizzard addon name. If a filter names
    -- an addon no registration under its skin key(s) actually uses,
    -- S.GetSuppression matches nothing and the row behaves as fully
    -- unsuppressed while GetSuppressionState still reports "partial" -- the
    -- grid claims a coverage overlap that isn't real, and in game the window
    -- carries two borders. Nothing else catches this: it is silent in
    -- luacheck and silent in every OTHER busted spec.
    --
    -- WINDOW_MAP nests `skins` and `addons` lists, so this loads
    -- EUIWindows.lua for real (via _ke_loader) instead of adding a second
    -- hand-rolled text parser for its shape.
    local _, euiKE = L.loadEUIWindows()
    local WINDOW_MAP = euiKE.Skins.WINDOW_MAP

    local filteredRows = {}
    for _, row in ipairs(WINDOW_MAP) do
        if row.addons then filteredRows[#filteredRows + 1] = row end
    end

    it("positive control: exactly the housing and delves rows carry an addons filter", function()
        -- Without this, the two assertions below pass trivially on an empty
        -- loop the moment WINDOW_MAP stops carrying any filtered row at all --
        -- the same vacuity class this plan has rejected three times already.
        local euiKeys = {}
        for _, row in ipairs(filteredRows) do euiKeys[#euiKeys + 1] = row.euiKey end
        table.sort(euiKeys)
        assert.same({ "delves", "housing" }, euiKeys)
    end)

    it("every addon a filtered row names matches at least one real registration under its skin key", function()
        for _, row in ipairs(filteredRows) do
            for _, skinKey in ipairs(row.skins) do
                local regs = registrations[skinKey] or {}
                for _, addonName in ipairs(row.addons) do
                    local found = false
                    for _, regAddon in ipairs(regs) do
                        if regAddon == addonName then found = true break end
                    end
                    assert.is_true(found,
                        "WINDOW_MAP row '" .. row.euiKey .. "' filters addon '" .. addonName
                            .. "' but no S:Register under key '" .. skinKey .. "' uses that addon name")
                end
            end
        end
    end)

    it("every filtered row leaves at least one registration NOT covered by its filter", function()
        for _, row in ipairs(filteredRows) do
            local addonSet = {}
            for _, a in ipairs(row.addons) do addonSet[a] = true end
            for _, skinKey in ipairs(row.skins) do
                local regs = registrations[skinKey] or {}
                local hasUncovered = false
                for _, regAddon in ipairs(regs) do
                    -- A `false` entry (RegisterEarly, no addon) can never match
                    -- a named filter, so it always counts as uncovered too.
                    if not (regAddon and addonSet[regAddon]) then hasUncovered = true break end
                end
                assert.is_true(hasUncovered,
                    "WINDOW_MAP row '" .. row.euiKey .. "' filter covers EVERY registration under key '"
                        .. skinKey .. "' -- it should be an unfiltered row instead")
            end
        end
    end)
end)
