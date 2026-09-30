-- Lint: script hooks and replaced scripts in the settings GUI.
--
-- The GUI reuses its cards, rows and widgets from pools. A hook can never be
-- taken off, so one installed on a pooled widget keeps running for every page
-- that widget serves afterwards, and the pool's runtime check cannot see it.
-- Every HookScript under GUI/ is listed below with the frame it lands on, each
-- a frame no pool hands out. A SetScript in a page builder or a widget file is
-- held to frames and animation groups that same file made: a script replaced
-- on a pooled widget is the same defect and just as invisible.
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
    ["GUI/GUIWidgets/GUI-KESlider.lua|slider|OnUpdate"] = 1,
    -- The main window's close hook, installed once per session.
    ["GUI/GUITabs/GUIQoL/GUI-Optimize.lua|frame|OnHide"] = 1,
    -- A keybind button the page makes itself with CreateFrame.
    ["GUI/GUITabs/GUIUtilities/GUI-WorldMarkerCycler.lua|btn|OnClick"] = 1,
}

-- "file|receiver" for a SetScript whose receiver the file never assigns from
-- CreateFrame or CreateAnimationGroup, with why it is still a frame no pool
-- hands out.
local SETSCRIPT_ALLOWED = {
    -- SetupHover(btn): both callers pass buttons the page made with
    -- CreateFrame (applyBtn, revertBtnSmall).
    ["GUI/GUITabs/GUIQoL/GUI-Optimize.lua|btn"] = true,
}

local function MadeInFile(text, receiver)
    local escaped = receiver:gsub("%p", "%%%0")
    return text:find(escaped .. "%s*=%s*[%w_%.:]*CreateFrame%s*%(") ~= nil
        or text:find(escaped .. "%s*=%s*[%w_%.:]*CreateAnimationGroup%s*%(") ~= nil
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

describe("script hooks in the settings GUI", function()
    it("hooks only the listed frames, each one no pool hands out", function()
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

    it("replaces scripts in page builders and widget files only on frames the same file made", function()
        local offenders = {}
        local checked = 0
        local files = walkLuaFiles("GUI/GUITabs", {})
        walkLuaFiles("GUI/GUIWidgets", files)
        for _, path in ipairs(files) do
            local text = readFile(path)
            for receiver in text:gmatch("([%w_%.]+)%s*:%s*SetScript%s*%(") do
                checked = checked + 1
                if not MadeInFile(text, receiver) and not SETSCRIPT_ALLOWED[path .. "|" .. receiver] then
                    offenders[#offenders + 1] = path .. "|" .. receiver
                end
            end
        end
        assert.is_true(checked > 100, "positive control: builders and widgets do set scripts")
        table.sort(offenders)
        assert.same({}, offenders)
    end)
end)
