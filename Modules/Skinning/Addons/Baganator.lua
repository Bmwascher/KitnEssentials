local KE = select(2, ...)
local S = KE.Skins
local _G = _G
local next = next -- luacheck: ignore 211/next
local hooksecurefunc = hooksecurefunc -- luacheck: ignore 211/hooksecurefunc

local BRAND = S.palette.brand
local HOVER = S.palette.hover

local skinners = {}

skinners.ItemButton = function(button)
    if S.data(button).bagSkinned then return end
    S.data(button).bagSkinned = true
    S.ItemButton(button)
    if button.IconBorder then S.IconBorder(button.IconBorder, S.GetBackdrop(button)) end

    if button.SlotBackground then button.SlotBackground:Hide() end

    -- Each item button carries its OWN scale, set from the configured icon
    -- size on every layout pass, so a border measured at skin time is wrong
    -- as soon as the bag lays out -- and wrong by a different amount in any
    -- section using a different icon size.
    if button.SetScale and not S.data(button).scaleHooked then
        S.data(button).scaleHooked = true
        hooksecurefunc(button, "SetScale", S.RefreshFrameEdge)
    end
end

skinners.IconButton = function(button) S.Button(button) end
skinners.Button = function(button) S.Button(button) end

-- The bag window is built at scale 1 and rescaled from settings afterwards,
-- so borders measured at build time draw roughly double. Re-measure whenever
-- the window shows or its scale changes.
local function WatchScale(frame)
    if S.data(frame).bagScaleWatched then return end
    S.data(frame).bagScaleWatched = true
    if frame.HookScript then
        frame:HookScript("OnShow", function(f) S.RefreshEdgesUnder(f) end)
    end
    if frame.SetScale then
        hooksecurefunc(frame, "SetScale", function(f) S.RefreshEdgesUnder(f) end)
    end
    S.RefreshEdgesUnder(frame)
end

skinners.ButtonFrame = function(frame)
    if S.data(frame).bagSkinned then return end
    S.data(frame).bagSkinned = true
    S.Frame(frame)

    if frame.Bg then S.KillTexture(frame.Bg) end
    if frame.TopTileStreaks then S.KillTexture(frame.TopTileStreaks) end
    if frame.NineSlice then S.StripTextures(frame.NineSlice, true) end

    WatchScale(frame)
end

skinners.SearchBox = function(box) S.EditBox(box) end
skinners.EditBox = function(box) S.EditBox(box) end
skinners.TabButton = function(tab) S.Tab(tab) end
skinners.TopTabButton = function(tab) S.Tab(tab) end

skinners.SideTabButton = function(tab)
    if S.data(tab).bagSkinned then return end
    S.data(tab).bagSkinned = true
    if tab.Background then tab.Background:Hide() end
    if tab.Icon then
        tab.Icon:ClearAllPoints()
        tab.Icon:SetPoint("CENTER")
        tab.Icon:SetSize(25, 25)
        tab.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
    if tab.SelectedTexture then
        tab.SelectedTexture:ClearAllPoints()
        tab.SelectedTexture:SetPoint("CENTER")
        tab.SelectedTexture:SetSize(25, 25)
        tab.SelectedTexture:SetColorTexture(BRAND[1], BRAND[2], BRAND[3], 0.35)
    end
    S.Backdrop(tab)
    S.Hover(tab)
end

skinners.TrimScrollBar = function(bar) S.TrimScrollBar(bar) end

skinners.ScrollButton = function(button, tags)
    button:SetSize(16, 16)
    button:SetAlpha(1)
    S.ArrowButton(button, (tags and tags.left and "left") or (tags and tags.right and "right") or "down", 14)
end

skinners.CheckBox = function(box) S.CheckBox(box) end
skinners.Slider = function(slider) S.StepSlider(slider) end

skinners.InsetFrame = function(frame)
    if frame.NineSlice then S.StripTextures(frame.NineSlice) end
    S.Inset(frame)
end

skinners.CornerWidget = function(region)
    if region.IsObjectType and region:IsObjectType("FontString") then
        S.SetFont(region, nil, "OUTLINE")
    end
end
skinners.CategoryLabel = skinners.CornerWidget
skinners.CategorySectionHeader = function(frame)
    if frame.IsObjectType and frame:IsObjectType("FontString") then
        S.SetFont(frame, nil, "OUTLINE")
    elseif frame.GetRegions then
        S.FontStrings(frame, nil, "OUTLINE")
    end
end

skinners.Dropdown = function(dd) S.DropDown(dd) end

skinners.Divider = function(tex)
    if not tex.SetColorTexture then return end
    tex:SetPoint("TOPLEFT", 0, 0)
    tex:SetPoint("TOPRIGHT", 0, 0)
    tex:SetHeight(1)
    tex:SetColorTexture(HOVER[1], HOVER[2], HOVER[3], 0.45)
end

skinners.Dialog = function(frame)
    if S.data(frame).bagSkinned then return end
    S.data(frame).bagSkinned = true
    S.StripTextures(frame)
    S.Backdrop(frame)
end

local function Dispatch(details)
    local fn = skinners[details.regionType]
    if fn then
        local ok, err = pcall(fn, details.region, details.tags)
        if not ok then
            print("|cffFF008CKitn|r|cffffffffEssentials:|r Baganator skin [" .. tostring(details.regionType) .. "]: " .. tostring(err))
        end
    end
end

local function Skin()
    local api = _G.Baganator and _G.Baganator.API and _G.Baganator.API.Skins
    if not (api and api.RegisterListener) then return end
    api.RegisterListener(Dispatch)

    -- Catch up on anything built before we registered: each region is handed
    -- to listeners exactly once, on creation, so a frame that already existed
    -- when our listener arrived is never offered at all. Every skinner here
    -- is dedupe-guarded, so replaying is free.
    if api.GetAllFrames then
        local ok, all = pcall(api.GetAllFrames)
        if ok and type(all) == "table" then
            for _, details in ipairs(all) do
                if type(details) == "table" and details.region then Dispatch(details) end
            end
        end
    end
end

S:Register("Baganator", Skin, "Baganator")
