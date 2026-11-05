local KE = select(2, ...)
local S = KE.Skins
local _G = _G
local ipairs = ipairs
local pcall = pcall

-- S.DropDown's caret: 14 wide at RIGHT -4.
local CARET_ROOM = 18

local function SkinDropdown(dd, frame)
    pcall(S.DropDown, dd, true)
    -- 22 matches the search box beside it, and y -31 is the search box's top.
    dd:SetHeight(22)
    dd:ClearAllPoints()
    dd:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -31)
    -- Blizzard anchors the text from the top and up to its own arrow, which
    -- sits it low in the shorter box and under the caret.
    local text = dd.Text
    if not text then return end
    local caret = S.data(dd).caret
    text:ClearAllPoints()
    text:SetPoint("LEFT", dd, "LEFT", 8, 0)
    if caret then
        text:SetPoint("RIGHT", caret, "LEFT", -2, 0)
    else
        text:SetPoint("RIGHT", dd, "RIGHT", -(CARET_ROOM + 2), 0)
    end
end

local function Skin()
    local frame = _G.AddonList
    if not frame then return S.Skip("AddonList missing") end
    S.Frame(frame)
    if frame.Dropdown then SkinDropdown(frame.Dropdown, frame) end
    local search = frame.SearchBox
    if search then
        S.EditBox(search)
        -- Blizzard's x=1 puts the magnifier on the 1px border.
        if search.searchIcon then
            search.searchIcon:ClearAllPoints()
            search.searchIcon:SetPoint("LEFT", search, "LEFT", 4, 0)
        end
    end
    for _, key in ipairs({ "CancelButton", "OkayButton", "EnableAllButton", "DisableAllButton" }) do
        if frame[key] then S.Button(frame[key]) end
    end
    if frame.ForceLoad then S.CheckBox(frame.ForceLoad) end
end

local function Arm()
    S.Defer(Skin, _G.AddonList)
end

S:RegisterEarly(Arm, "AddonManager")
