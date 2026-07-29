-- ╔══════════════════════════════════════════════════════════╗
-- ║  dev/spec/skinregistry_spec.lua                          ║
-- ║  Proves the config grid and the S:Register dispatcher    ║
-- ║  agree on every key. Reads both source trees as TEXT --   ║
-- ║  no module is loaded, so this needs no _ke_loader entry.  ║
-- ╚══════════════════════════════════════════════════════════╝
--
-- The gate this closes: GUI/GUITabs/GUISkinning/GUI-BlizzardFrames.lua reads
-- `Skins[key] ~= false`, so a key nothing registers is always "on" and a
-- misspelt row controls nothing. Neither direction of that typo shows up any
-- other way -- it is silent in-game and silent in luacheck.

local lfs = require("lfs")

local GUI_FILE = "GUI/GUITabs/GUISkinning/GUI-BlizzardFrames.lua"
local SKINNING_ROOT = "Modules/Skinning"

-- Keys the reference always dispatches with no grid row, cited at
-- GUI-BlizzardFrames.lua:27-32 (minor or loading-screen-rare frames). A row
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
-- depth, in order. Nested calls (e.g. a function-literal argument's body)
-- sit one depth deeper and their string literals are never collected, so
-- the LAST entry in the returned list is the call's last string ARGUMENT --
-- exactly the skin key -- not merely the last string literal anywhere
-- inside it.
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
-- call and adds the last string argument of each to `into`. %a* covers both
-- spellings ("Register" / "RegisterEarly") in one pass.
local function collectRegistrations(text, into)
    local pos = 1
    while true do
        local s, e = text:find("S:Register%a*%s*%(", pos)
        if not s then break end
        local strings = callArgStrings(text, e + 1)
        local key = strings[#strings]
        if key then into[key] = true end
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

    local registered = {}
    local files = walkLuaFiles(SKINNING_ROOT, {})
    assert(#files > 0, "expected at least one .lua file under " .. SKINNING_ROOT)
    for _, path in ipairs(files) do
        collectRegistrations(readFile(path), registered)
    end

    it("registers every FRAME_SKINS / ADDON_SKINS key somewhere under Modules/Skinning/, except NON_REGISTRY_ROWS", function()
        local missing = {}
        local function check(keys)
            for _, key in ipairs(keys) do
                if not NON_REGISTRY_ROWS[key] and not registered[key] then
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
        for key in pairs(registered) do
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
end)
