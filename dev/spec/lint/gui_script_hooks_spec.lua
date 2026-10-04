-- Lint: script hooks and replaced scripts in the settings GUI.
--
-- The GUI reuses its cards, rows and widgets from pools. A hook can never be
-- taken off, so one installed on a pooled widget keeps running for every page
-- that widget serves afterwards, and the pool's runtime check cannot see it.
-- Every HookScript under GUI/ is listed below with the frame it lands on: a
-- frame no pool hands out, or a pooled one hooked once by the constructor
-- that has just made it. A SetScript is held to a receiver whose nearest
-- assignment above the call takes it from CreateFrame or CreateAnimationGroup:
-- a script replaced on a pooled widget is the same defect and just as
-- invisible, and a name can be a made frame early in a file and a pooled one
-- later. A function parameter or a loop variable is not an assignment: a
-- receiver named by one is judged by the nearest earlier assignment of that
-- name, and is flagged when there is none.
local lfs = require("lfs")

-- "file|receiver|handler" -> how many such calls the file makes.
local HOOKS_ALLOWED = {
    -- The main window, its scroll frame and scrollbar: built once.
    ["GUI/GUIMain/GUI-KEScrollbar.lua|thumb|OnShow"] = 1,
    ["GUI/GUIMain/GUI-KEScrollbar.lua|thumb|OnHide"] = 1,
    ["GUI/GUIMain/GUI-MainFrame.lua|scrollFrame|OnScrollRangeChanged"] = 1,
    ["GUI/GUIMain/GUI-MainFrame.lua|scrollChild|OnSizeChanged"] = 1,
    ["GUI/GUIMain/GUI-MainFrame.lua|scrollFrame|OnSizeChanged"] = 1,
    ["GUI/GUIMain/GUI-MainFrame.lua|scrollFrame|OnShow"] = 1,
    ["GUI/GUIHelpers/GUI-ThemePopup.lua|mainFrame|OnHide"] = 1,
    -- The sidebar: built once.
    ["GUI/GUIWidgets/GUI-Sidebar.lua|sidebar|OnSizeChanged"] = 1,
    ["GUI/GUIWidgets/GUI-Sidebar.lua|scrollFrame|OnScrollRangeChanged"] = 1,
    ["GUI/GUIWidgets/GUI-Sidebar.lua|scrollChild|OnSizeChanged"] = 1,
    ["GUI/GUIWidgets/GUI-Sidebar.lua|scrollFrame|OnShow"] = 1,
    ["GUI/GUIWidgets/GUI-Sidebar.lua|sidebar|OnShow"] = 1,
    ["GUI/GUIWidgets/GUI-Sidebar.lua|sidebar|OnHide"] = 1,
    -- Installed once by the factory on a part of the widget it just built.
    ["GUI/GUIWidgets/GUI-KEDropdown.lua|thumb|OnShow"] = 1,
    ["GUI/GUIWidgets/GUI-KEDropdown.lua|thumb|OnHide"] = 1,
    -- The main window's close hook, installed once per session.
    ["GUI/GUITabs/GUIQoL/GUI-Optimize.lua|frame|OnHide"] = 1,
    -- Installed once by the keybind button's constructor, on the button it
    -- has just made.
    ["GUI/GUITabs/GUIUtilities/GUI-WorldMarkerCycler.lua|btn|OnClick"] = 1,
}

-- "file|receiver" for a SetScript whose receiver is not taken from
-- CreateFrame or CreateAnimationGroup by its nearest assignment, with why it
-- is still a frame no pool hands out.
local SETSCRIPT_ALLOWED = {
    -- SetupHover(btn): both callers pass buttons the page made with
    -- CreateFrame (applyBtn, revertBtnSmall).
    ["GUI/GUITabs/GUIQoL/GUI-Optimize.lua|btn"] = true,
    -- The dropdown's own list buttons: it makes them, keeps them on its own
    -- reuse list and never hands one to a page.
    ["GUI/GUIWidgets/GUI-KEDropdown.lua|btn"] = true,
    -- The scroll frame the scrollbar factory is handed by the window that
    -- made it.
    ["GUI/GUIMain/GUI-KEScrollbar.lua|scrollFrame"] = true,
}

local SETSCRIPT_DIRS = { "GUI/GUITabs", "GUI/GUIWidgets", "GUI/GUIMain", "GUI/GUIHelpers" }

-- True when the nearest assignment to receiver above pos takes its value from
-- CreateFrame or CreateAnimationGroup. The frontier keeps `x.btn = ...` from
-- counting as an assignment to `btn`; the `[^=]` keeps a comparison out.
local function MadeNearby(text, receiver, pos)
    local escaped = receiver:gsub("%p", "%%%0")
    local pattern = "%f[%w_%.]" .. escaped .. "%s*=([^=][^\n]*)"
    local value
    local from = 1
    while true do
        local s, _, rhs = text:find(pattern, from)
        if not s or s >= pos then break end
        value = rhs
        -- One character on, not past the match: a match runs to the end of
        -- its line, and a later assignment on that line is the nearer one.
        from = s + 1
    end
    if not value then return false end
    return value:find("^%s*[%w_%.:]*CreateFrame%s*%(") ~= nil
        or value:find("^%s*[%w_%.:]*CreateAnimationGroup%s*%(") ~= nil
end

-- Adds every offending "path|receiver" in text to offenders, marks every
-- receiver it looked at in seen, and returns how many calls it checked.
local function SetScriptOffenders(path, text, offenders, seen)
    local checked = 0
    for pos, receiver in text:gmatch("()([%w_%.]+)%s*:%s*SetScript%s*%(") do
        checked = checked + 1
        local key = path .. "|" .. receiver
        seen[key] = true
        if not MadeNearby(text, receiver, pos) and not SETSCRIPT_ALLOWED[key] then
            offenders[#offenders + 1] = key
        end
    end
    return checked
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

local function CheckTree(dirs)
    local offenders, seen, checked = {}, {}, 0
    local files = {}
    for _, dir in ipairs(dirs) do walkLuaFiles(dir, files) end
    for _, path in ipairs(files) do
        checked = checked + SetScriptOffenders(path, readFile(path), offenders, seen)
    end
    table.sort(offenders)
    return offenders, seen, checked
end

describe("script hooks in the settings GUI", function()
    it("hooks only the listed frames: built once, or hooked once by their own constructor", function()
        local files = walkLuaFiles("GUI", {})
        assert.is_true(#files > 50, "positive control: the GUI tree was found")
        local found = {}
        for _, path in ipairs(files) do
            for receiver, handler in readFile(path):gmatch('([%w_%.]+)%s*:%s*HookScript%s*%(%s*"([%w_]+)"') do
                local key = path .. "|" .. receiver .. "|" .. handler
                found[key] = (found[key] or 0) + 1
            end
        end
        assert.same(HOOKS_ALLOWED, found)
    end)

    it("replaces scripts only on receivers last assigned from CreateFrame or CreateAnimationGroup", function()
        local offenders, _, checked = CheckTree(SETSCRIPT_DIRS)
        assert.is_true(checked > 100, "positive control: the walked files do set scripts")
        assert.same({}, offenders)
    end)

    it("walks the main-window folder as well as the page and widget folders", function()
        local _, seen = CheckTree(SETSCRIPT_DIRS)
        local inMainWindow = false
        for key in pairs(seen) do
            if key:find("GUI/GUIMain/", 1, true) == 1 then inMainWindow = true end
        end
        assert.is_true(inMainWindow)
    end)

    it("judges a receiver by its nearest assignment above the call, not by any in the file", function()
        local sample = table.concat({
            'local row = CreateFrame("Frame", nil, parent)',
            'row:SetScript("OnShow", Paint)',
            "row = GUIFrame:CreateRow(parent)",
            'row:SetScript("OnHide", Paint)',
            'local cell = CreateFrame("Frame", nil, parent); cell = GUIFrame:CreateRow(parent)',
            'cell:SetScript("OnShow", Paint)',
        }, "\n")
        local offenders = {}
        SetScriptOffenders("sample.lua", sample, offenders, {})
        assert.same({ "sample.lua|row", "sample.lua|cell" }, offenders)
    end)
end)
