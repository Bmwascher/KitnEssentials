-- ╔══════════════════════════════════════════════════════════╗
-- ║  WorldMap.lua                                            ║
-- ║  Module: World Map                                       ║
-- ║  Purpose: Adjustable minimized map scale, coordinate     ║
-- ║           waypoint search bar with live preview, and     ║
-- ║           city map icons for services and trainers.      ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class WorldMap: AceModule, AceEvent-3.0
local WM = KitnEssentials:NewModule("WorldMap", "AceEvent-3.0")

local CreateFrame = CreateFrame
local tonumber = tonumber
local format = string.format
local gsub = string.gsub
local ipairs = ipairs
local pairs = pairs
local wipe = wipe
local math_sqrt = math.sqrt
local math_atan2 = math.atan2
local math_cos = math.cos
local math_sin = math.sin
local math_min = math.min
local math_max = math.max
local math_pi = math.pi
local math_random = math.random

local C_Map = C_Map
local C_SuperTrack = C_SuperTrack
local UiMapPoint = UiMapPoint
local EventRegistry = EventRegistry
local Mixin = Mixin
-- NOTE: MapCanvasPinMixin / MapCanvasDataProviderMixin / CreateFromMixins /
-- C_Texture / GetProfessions / GetProfessionInfo are looked up at call time
-- (not captured as locals) because Blizzard_MapCanvas and related modules
-- are LoadOnDemand — they can be nil at file-parse time.

---------------------------------------------------------------------------------
-- Debug
---------------------------------------------------------------------------------
local DEBUG_WM = false
local function dprint(...)
    if not DEBUG_WM then return end
    local parts = { "[WM]" }
    for i = 1, select("#", ...) do
        parts[#parts + 1] = tostring((select(i, ...)))
    end
    KE:Print(table.concat(parts, " "))
end

---------------------------------------------------------------------------------
-- Module State
---------------------------------------------------------------------------------
WM.searchBar = nil
WM.scaleCallbacksRegistered = false
WM.mapIconsProvider = nil
WM.playerProfessions = {}
WM.antiOverlapApplied = {}

---------------------------------------------------------------------------------
-- DB Helper
---------------------------------------------------------------------------------
function WM:UpdateDB()
    self.db = KE.db.profile.WorldMap
end

function WM:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

---------------------------------------------------------------------------------
-- Core Logic
---------------------------------------------------------------------------------
function WM:ApplyScale()
    if not self.db or not self.db.ScaleEnabled then
        self:RevertScale()
        return
    end
    if not WorldMapFrame then return end

    local size = self.db.Scale or 1.2

    WorldMapFrame:SetClampedToScreen(true)
    WorldMapFrame:SetScale(size)

    -- Register minimize/maximize callbacks (closures capture the size correctly)
    if not self.scaleCallbacksRegistered then
        EventRegistry:RegisterCallback("WorldMapMinimized", function()
            if self.db and self.db.ScaleEnabled then
                WorldMapFrame:SetScale(self.db.Scale or 1.2)
            end
        end, self)
        EventRegistry:RegisterCallback("WorldMapMaximized", function()
            WorldMapFrame:SetScale(1)
        end, self)
        self.scaleCallbacksRegistered = true
    end
end

function WM:RevertScale()
    if WorldMapFrame then
        WorldMapFrame:SetScale(1)
    end
    if self.scaleCallbacksRegistered then
        EventRegistry:UnregisterCallback("WorldMapMinimized", self)
        EventRegistry:UnregisterCallback("WorldMapMaximized", self)
        self.scaleCallbacksRegistered = false
    end
end

-- Parse coordinate text into x, y values.
-- Accepts formats like: 45 67, 45.2 67.8, 45, 67, /way 45 67
local function ParseCoordinates(text)
    if not text or text == "" then return nil, nil end

    -- Strip common prefixes
    text = gsub(text, "^%s*/way%s*", "")
    text = gsub(text, "^%s*way%s*", "")

    -- Normalize separators
    text = gsub(text, "[,/|\"'%[%]%(%)]+", " ")
    text = gsub(text, "%s+", " ")
    text = gsub(text, "^%s+", "")
    text = gsub(text, "%s+$", "")

    -- Extract numbers
    local numbers = {}
    for num in text:gmatch("([%d%.]+)") do
        local n = tonumber(num)
        if n then
            numbers[#numbers + 1] = n
        end
    end

    if #numbers < 2 then return nil, nil end

    local x, y = numbers[1], numbers[2]
    if x > 100 or y > 100 then return nil, nil end

    return x, y
end

local function SetWaypoint(x, y)
    local mapID = WorldMapFrame:IsShown() and WorldMapFrame:GetMapID()
        or C_Map.GetBestMapForUnit("player")

    if not mapID then return false, "No map found" end

    -- Scale to 0-1 range if needed
    if x > 1 then x = x / 100 end
    if y > 1 then y = y / 100 end

    if not C_Map.CanSetUserWaypointOnMap(mapID) then
        return false, "Can't set waypoint here"
    end

    C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(mapID, x, y))
    C_SuperTrack.SetSuperTrackedUserWaypoint(true)

    local mapInfo = C_Map.GetMapInfo(mapID)
    local mapName = mapInfo and mapInfo.name or "Unknown"
    return true, format("%s (%.1f, %.1f)", mapName, x * 100, y * 100)
end

---------------------------------------------------------------------------------
-- Frame Creation
---------------------------------------------------------------------------------
function WM:CreateSearchBar()
    if self.searchBar then return end
    if not WorldMapFrame then return end
    if not self.db or not self.db.WaypointBarEnabled then return end

    local fontSize = 12

    -- EditBox
    local editBox = CreateFrame("EditBox", "KE_WorldMapSearchBar", WorldMapFrame)
    editBox:SetSize(140, 20)
    editBox:SetPoint("TOPLEFT", WorldMapFrame, "TOPLEFT", 3, -5)
    editBox:SetAutoFocus(false)
    editBox:SetMaxLetters(50)
    editBox:SetFrameStrata("DIALOG")

    -- Backdrop
    local bg = CreateFrame("Frame", nil, editBox, BackdropTemplateMixin and "BackdropTemplate")
    bg:SetAllPoints(editBox)
    bg:SetFrameLevel(editBox:GetFrameLevel() - 1)
    local px = KE:GetPixelSize()
    bg:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = px,
        insets = { left = px, right = px, top = px, bottom = px },
    })
    bg:SetBackdropColor(0, 0, 0, 0.7)
    bg:SetBackdropBorderColor(0, 0, 0, 1)

    -- Font
    local fontPath = KE:GetFontPath("Expressway") or "Fonts\\FRIZQT__.TTF"
    editBox:SetFont(fontPath, fontSize, "")
    editBox:SetTextColor(1, 1, 1, 1)
    editBox:SetTextInsets(4, 4, 0, 0)

    -- Placeholder text
    local placeholder = editBox:CreateFontString(nil, "ARTWORK")
    placeholder:SetFont(fontPath, fontSize, "")
    placeholder:SetTextColor(0.5, 0.5, 0.5, 0.8)
    placeholder:SetText("/way x y")
    placeholder:SetPoint("LEFT", editBox, "LEFT", 4, 0)
    editBox.placeholder = placeholder

    -- Status text (shows result after pressing Enter)
    local statusText = editBox:CreateFontString(nil, "ARTWORK")
    statusText:SetFont(fontPath, fontSize - 1, "OUTLINE")
    statusText:SetPoint("LEFT", editBox, "RIGHT", 5, 0)
    editBox.statusText = statusText

    -- Focus handlers
    editBox:SetScript("OnEditFocusGained", function()
        placeholder:Hide()
    end)

    editBox:SetScript("OnEditFocusLost", function(eb)
        local text = eb:GetText()
        if not text or text:gsub(" ", "") == "" then
            placeholder:Show()
        end
    end)

    -- Live preview while typing
    editBox:SetScript("OnTextChanged", function(eb, userInput)
        if not userInput then return end
        local text = eb:GetText()
        if not text or text:gsub(" ", "") == "" then
            statusText:SetText("")
            return
        end

        local x, y = ParseCoordinates(text)
        if x and y then
            local mapID = WorldMapFrame:GetMapID() or C_Map.GetBestMapForUnit("player")
            local mapInfo = mapID and C_Map.GetMapInfo(mapID)
            local name = mapInfo and mapInfo.name or ""
            statusText:SetTextColor(0.3, 1, 0.3, 1)
            statusText:SetText(format("%s (%.1f, %.1f)", name, x, y))
        else
            statusText:SetTextColor(1, 0.3, 0.3, 1)
            statusText:SetText("Invalid")
        end
    end)

    -- Enter to set waypoint
    editBox:SetScript("OnEnterPressed", function(eb)
        local text = eb:GetText()
        local x, y = ParseCoordinates(text)
        if x and y then
            local success, msg = SetWaypoint(x, y)
            if success then
                statusText:SetTextColor(0.3, 1, 0.3, 1)
                statusText:SetText(msg)
                KE:Print("Waypoint set: " .. msg)
                eb:SetText("")
            else
                statusText:SetTextColor(1, 0.3, 0.3, 1)
                statusText:SetText(msg)
            end
        else
            statusText:SetTextColor(1, 0.3, 0.3, 1)
            statusText:SetText("Invalid coordinates")
        end
        eb:ClearFocus()
    end)

    -- Escape to cancel
    editBox:SetScript("OnEscapePressed", function(eb)
        eb:SetText("")
        statusText:SetText("")
        placeholder:Show()
        eb:ClearFocus()
    end)

    self.searchBar = editBox
end

---------------------------------------------------------------------------------
-- Map Icons — Data
---------------------------------------------------------------------------------
local PROFESSION_SKILL_LINE = {
    ["Fishing"]        = 356,
    ["Cooking"]        = 185,
    ["Mining"]         = 186,
    ["Engineering"]    = 202,
    ["Leatherworking"] = 165,
    ["Blacksmithing"]  = 164,
    ["Tailoring"]      = 197,
    ["Herbalism"]      = 182,
    ["Inscription"]    = 773,
    ["Jewelcrafting"]  = 755,
    ["Enchanting"]     = 333,
    ["Alchemy"]        = 171,
    ["Skinning"]       = 393,
}

-- Base pin is 24x24 (CityGuide's "Icons with tooltips" default). Some maps need
-- a bigger multiplier because the city is small and dense (Silvermoon/Dornogal);
-- large cities (SW/Org) render fine at 1x.
local CITY_SCALE = {
    [2393] = 3.0, -- Silvermoon (matches CityGuide Registry entry)
    [84]   = 1.0, -- Stormwind
    [85]   = 1.0, -- Orgrimmar
}

local DECOR  = "Interface\\Housing\\inv_12ph_genericfixture"

-- Minimap-style icon paths for Small Icons mode (round/simple icons with glow
-- backdrop). Pin falls back to `texture` if no `minimapIcon` is defined.
local MM_AUCTIONEER = "Interface\\Minimap\\Tracking\\Auctioneer"
local MM_BANKER     = "Interface\\Minimap\\Tracking\\Banker"
local MM_INNKEEPER  = "Interface\\Minimap\\Tracking\\Innkeeper"
local MM_STABLE     = "Interface\\Minimap\\Tracking\\StableMaster"
local MM_BARBER     = "Interface\\Minimap\\Tracking\\Barbershop"
local MM_TRANSMOG   = "Interface\\Minimap\\Tracking\\Transmogrifier"
local MM_UPGRADE    = "Interface\\Minimap\\Tracking\\upgradeitem-32x32"
local MM_PROF       = "Interface\\Minimap\\Tracking\\Profession"
local MM_PVP        = "Interface\\Cursor\\Crosshair\\missions"
local MM_WORKORDERS = "Interface\\Cursor\\Crosshair\\workorders"
local MM_COMET      = "Interface\\Cursor\\Crosshair\\bastionteleporter"
local MM_PORTAL_A   = "Interface\\Minimap\\vehicle-alliancemageportal"
local MM_PORTAL_H   = "Interface\\Minimap\\vehicle-hordemageportal"
local MM_PORTAL_M   = "Interface\\Minimap\\vehicle-alliancewarlockportal"
local MM_BATTLE     = "Interface\\Minimap\\Tracking\\battlemaster"

-- Bundled custom icons (copied from CityGuide with matching filenames)
local KE_ICON       = "Interface\\AddOns\\KitnEssentials\\Media\\Icon\\"
local MM_TRADINGPOST = KE_ICON .. "tp"
local MM_DELVES      = KE_ICON .. "delves"
local MM_HARANDAR    = KE_ICON .. "harandar"
local MM_VENDOR      = KE_ICON .. "vendor"
local MM_DECOR       = KE_ICON .. "decor"

local MAP_ICONS = {
    -- Silvermoon City
    [2393] = {
        -- Services
        { x = 0.509, y = 0.759, texture = "Interface\\Icons\\INV_Misc_Coin_01",                minimapIcon = MM_AUCTIONEER, title = "Auction House" },
        { x = 0.507, y = 0.652, texture = "Interface\\Icons\\INV_Misc_Bag_07",                 minimapIcon = MM_BANKER,     title = "Bank" },
        { x = 0.562, y = 0.701, texture = "Interface\\Icons\\inv_misc_rune_01",                minimapIcon = MM_INNKEEPER,  title = "Innkeeper" },
        { x = 0.534, y = 0.663, texture = "Interface\\Icons\\spell_arcane_portaldalarancrater", minimapIcon = MM_PORTAL_H,   title = "Portals" },
        { x = 0.486, y = 0.618, texture = "Interface\\Icons\\ui_itemupgrade",                minimapIcon = MM_UPGRADE,    title = "Item Upgrades & Crest Exchange" },
        { x = 0.527, y = 0.575, texture = "Interface\\Icons\\Ui_transmog_showequippedgear",  minimapIcon = MM_TRANSMOG,   title = "Transmogrifier" },
        { x = 0.451, y = 0.556, texture = "Interface\\Icons\\INV_Misc_Note_06",              minimapIcon = MM_WORKORDERS, title = "Crafting Orders" },
        { x = 0.524, y = 0.780, texture = "Interface\\Icons\\ui_delves",                     minimapIcon = MM_DELVES,     title = "Delves" },
        { x = 0.536, y = 0.446, texture = "Interface\\Minimap\\Tracking\\StableMaster",      minimapIcon = MM_STABLE,     title = "Stable Master" },
        { x = 0.426, y = 0.787, texture = "Interface\\Minimap\\Tracking\\Barbershop",        minimapIcon = MM_BARBER,     title = "Barbershop" },
        { x = 0.404, y = 0.648, atlas   = "CreationCatalyst-32x32",                                                       title = "Catalyst" },

        -- Activities / POIs
        { x = 0.363, y = 0.846, texture = "Interface\\Icons\\Ability_rogue_combatexpertise", minimapIcon = MM_PVP,        title = "Training Dummies" },
        { x = 0.420, y = 0.583, texture = "Interface\\Icons\\Spell_Shadow_Teleport",         minimapIcon = MM_PORTAL_M,   title = "M+ Teleports" },
        { x = 0.489, y = 0.781, texture = "Interface\\Icons\\Tradingpostcurrency",           minimapIcon = MM_TRADINGPOST, title = "Trading Post" },
        { x = 0.369, y = 0.681, texture = "Interface\\Icons\\inv_achievement_zone_harandar", minimapIcon = MM_HARANDAR,   title = "Harandar" },
        { x = 0.353, y = 0.657, texture = "Interface\\Icons\\inv_zone_voidstorm",            minimapIcon = MM_COMET,      title = "Voidstorm" },
        { x = 0.511, y = 0.565, texture = DECOR,                                             minimapIcon = MM_DECOR,      title = "Housing Decor" },
        { x = 0.416, y = 0.669, texture = "Interface\\Icons\\ui_plundercoins",               minimapIcon = MM_VENDOR,     title = "Finery Vendor" },
        { x = 0.519, y = 0.486, texture = "Interface\\Icons\\inv_misc_coin_16",              minimapIcon = MM_AUCTIONEER, title = "Black Market AH" },
        { x = 0.363, y = 0.811, texture = "Interface\\Icons\\achievement_legionpvp2tier3",   minimapIcon = MM_BATTLE,     title = "PvP Vendor" },

        -- Profession Trainers (all share a generic profession minimap icon in small mode)
        { x = 0.447, y = 0.603, texture = "Interface\\Icons\\Trade_Fishing",                   minimapIcon = MM_PROF, title = "Fishing",        type = "Fishing" },
        { x = 0.562, y = 0.701, texture = "Interface\\Icons\\INV_Misc_Food_15",                minimapIcon = MM_PROF, title = "Cooking",        type = "Cooking" },
        { x = 0.426, y = 0.529, texture = "Interface\\Icons\\Trade_Mining",                    minimapIcon = MM_PROF, title = "Mining",         type = "Mining" },
        { x = 0.436, y = 0.538, texture = "Interface\\Icons\\Trade_Engineering",               minimapIcon = MM_PROF, title = "Engineering",    type = "Engineering" },
        { x = 0.432, y = 0.557, texture = "Interface\\Icons\\INV_Misc_ArmorKit_17",            minimapIcon = MM_PROF, title = "Leatherworking", type = "Leatherworking" },
        { x = 0.438, y = 0.518, texture = "Interface\\Icons\\Trade_BlackSmithing",             minimapIcon = MM_PROF, title = "Blacksmith",     type = "Blacksmithing" },
        { x = 0.480, y = 0.542, texture = "Interface\\Icons\\Trade_Tailoring",                 minimapIcon = MM_PROF, title = "Tailoring",      type = "Tailoring" },
        { x = 0.481, y = 0.515, texture = "Interface\\Icons\\Trade_Herbalism",                 minimapIcon = MM_PROF, title = "Herbalism",      type = "Herbalism" },
        { x = 0.466, y = 0.515, texture = "Interface\\Icons\\INV_Inscription_Tradeskill01",    minimapIcon = MM_PROF, title = "Inscription",    type = "Inscription" },
        { x = 0.480, y = 0.549, texture = "Interface\\Icons\\INV_Misc_Gem_01",                 minimapIcon = MM_PROF, title = "Jewelcrafting",  type = "Jewelcrafting" },
        { x = 0.478, y = 0.536, texture = "Interface\\Icons\\Trade_Engraving",                 minimapIcon = MM_PROF, title = "Enchanting",     type = "Enchanting" },
        { x = 0.470, y = 0.521, texture = "Interface\\Icons\\Trade_Alchemy",                   minimapIcon = MM_PROF, title = "Alchemy",        type = "Alchemy" },
        { x = 0.432, y = 0.557, texture = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01",           minimapIcon = MM_PROF, title = "Skinning",       type = "Skinning" },
    },

    -- Stormwind (Alliance capital)
    [84] = {
        { x = 0.618, y = 0.730, texture = "Interface\\Icons\\INV_Misc_Coin_01",              minimapIcon = MM_AUCTIONEER, title = "Auction House" },
        { x = 0.622, y = 0.765, texture = "Interface\\Icons\\INV_Misc_Bag_07",               minimapIcon = MM_BANKER,     title = "Bank" },
        { x = 0.492, y = 0.842, texture = "Interface\\Icons\\Spell_Arcane_PortalDalaran",    minimapIcon = MM_PORTAL_A,   title = "Portal Room" },
        { x = 0.614, y = 0.661, texture = "Interface\\Minimap\\Tracking\\Barbershop",        minimapIcon = MM_BARBER,     title = "Barbershop" },
        { x = 0.801, y = 0.625, texture = "Interface\\Icons\\Ability_rogue_combatexpertise", minimapIcon = MM_PVP,        title = "Training Dummies" },
        { x = 0.493, y = 0.801, texture = DECOR,                                             minimapIcon = MM_DECOR,      title = "Housing Decor (Books)" },
        { x = 0.779, y = 0.659, texture = DECOR,                                             minimapIcon = MM_DECOR,      title = "Housing Decor (PvP)" },
        { x = 0.676, y = 0.730, texture = DECOR,                                             minimapIcon = MM_DECOR,      title = "Housing Decor" },
        { x = 0.745, y = 0.183, texture = "Interface\\Icons\\Spell_Arcane_PortalStormWind",  minimapIcon = MM_PORTAL_M,   title = "Cataclysm Portals" },
    },

    -- Orgrimmar (Horde capital)
    [85] = {
        { x = 0.540, y = 0.730, texture = "Interface\\Icons\\INV_Misc_Coin_01",              minimapIcon = MM_AUCTIONEER, title = "Auction House" },
        { x = 0.490, y = 0.820, texture = "Interface\\Icons\\INV_Misc_Bag_07",               minimapIcon = MM_BANKER,     title = "Bank" },
        { x = 0.487, y = 0.760, texture = "Interface\\Icons\\Tradingpostcurrency",           minimapIcon = MM_TRADINGPOST, title = "Trading Post" },
        { x = 0.528, y = 0.891, texture = DECOR,                                             minimapIcon = MM_DECOR,      title = "Housing Decor" },
        { x = 0.504, y = 0.583, texture = DECOR,                                             minimapIcon = MM_DECOR,      title = "Housing Decor (Org Quartermaster)" },
        { x = 0.586, y = 0.504, texture = DECOR,                                             minimapIcon = MM_DECOR,      title = "Housing Decor (Books)" },
        { x = 0.389, y = 0.720, texture = DECOR,                                             minimapIcon = MM_DECOR,      title = "Housing Decor (PvP)" },
    },
}

WM.MAP_ICONS = MAP_ICONS

---------------------------------------------------------------------------------
-- Map Icons — Profession Tracking
---------------------------------------------------------------------------------
function WM:UpdatePlayerProfessions()
    wipe(self.playerProfessions)
    if not _G.GetProfessions or not _G.GetProfessionInfo then return end

    local p1, p2, _, fish, cook = _G.GetProfessions()
    for _, prof in ipairs({ p1, p2, fish, cook }) do
        if prof then
            local _, _, _, _, _, _, skillLine = _G.GetProfessionInfo(prof)
            if skillLine then
                self.playerProfessions[skillLine] = true
            end
        end
    end
end

---------------------------------------------------------------------------------
-- Map Icons — Anti-Overlap
---------------------------------------------------------------------------------
-- Spreads pins that sit on top of each other. Mutates x/y once per map; a
-- guard prevents re-running on refresh so the positions stay stable.
local function ApplyAntiOverlap(points)
    local minDist = 0.015

    for i = 1, #points do
        for j = i + 1, #points do
            local p1, p2 = points[i], points[j]

            local dx = p1.x - p2.x
            local dy = p1.y - p2.y
            local dist = math_sqrt(dx * dx + dy * dy)

            if dist < minDist then
                local angle = math_atan2(dy, dx)
                if angle ~= angle then
                    angle = math_random() * math_pi * 2
                end

                local push = (minDist - dist) * 0.5

                p1.x = math_min(math_max(p1.x + math_cos(angle) * push, 0.01), 0.99)
                p1.y = math_min(math_max(p1.y + math_sin(angle) * push, 0.01), 0.99)

                p2.x = math_min(math_max(p2.x - math_cos(angle) * push, 0.01), 0.99)
                p2.y = math_min(math_max(p2.y - math_sin(angle) * push, 0.01), 0.99)
            end
        end
    end
end

---------------------------------------------------------------------------------
-- Map Icons — Pin Creation
---------------------------------------------------------------------------------
local function CreatePin(map, mp)
    -- Match the reference exactly: parent = map (WorldMapFrame), mixin for position.
    local pin = CreateFrame("Frame", nil, map)

    if _G.MapCanvasPinMixin then
        Mixin(pin, _G.MapCanvasPinMixin)
        if pin.OnLoad then
            pin:OnLoad()
        end
    end

    pin.mapPoint = mp
    mp.pin = pin
    pin.owningMap = map

    pin:EnableMouse(true)
    pin:SetMouseClickEnabled(true)
    pin:SetMouseMotionEnabled(true)
    -- Use a high pin frame level so our pins render above Blizzard's default
    -- POI / quest / portal pins (which typically sit at levels 20-500).
    -- WAYPOINT_LOCATION is ~1500 in Blizzard's PinFrameLevelsManager.
    if pin.UseFrameLevelType then
        pin:UseFrameLevelType("PIN_FRAME_LEVEL_WAYPOINT_LOCATION")
    end
    -- Belt-and-suspenders: raise numeric level too in case the mixin lookup
    -- gives something lower than expected.
    pin:SetFrameLevel((pin:GetFrameLevel() or 0) + 100)

    pin:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(mp.title)
        GameTooltip:Show()
    end)

    pin:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    pin:SetScript("OnMouseUp", function(self, button)
        if button ~= "LeftButton" then return end
        local mapID = map:GetMapID()
        if not mapID then return end
        if not C_Map.CanSetUserWaypointOnMap(mapID) then return end

        local wp = UiMapPoint.CreateFromCoordinates(mapID, mp.x, mp.y)
        C_Map.SetUserWaypoint(wp)
        C_SuperTrack.SetSuperTrackedUserWaypoint(true)
    end)

    -- Small icons mode uses a slightly larger base (30) because the minimap
    -- icons are round and visually smaller than a filled 24x24 square.
    local smallMode = WM.db and WM.db.MapIconsStyle == "small" and mp.minimapIcon
    local baseSize = mp.size or (smallMode and 30 or 24)
    pin:SetSize(baseSize, baseSize)

    if smallMode then
        -- Circular glow backdrop (matches CityGuide's Small Icons look)
        local glow = pin:CreateTexture(nil, "BACKGROUND")
        glow:SetSize(baseSize * 2.4, baseSize * 2.4)
        glow:SetPoint("CENTER")
        glow:SetTexture("Interface\\GLUES\\Models\\UI_Draenei\\GenericGlow64")
        glow:SetVertexColor(1, 1, 0.8, 0.5)
        glow:SetBlendMode("ADD")
        pin.glow = glow

        pin.tex = pin:CreateTexture(nil, "ARTWORK")
        pin.tex:SetAllPoints()
        pin.tex:SetTexture(mp.minimapIcon, nil, nil, "LINEAR")
        -- Minimap icons have their own shape — no border crop
    elseif mp.texture and mp.texture ~= "" then
        pin.tex = pin:CreateTexture(nil, "ARTWORK")
        pin.tex:SetAllPoints()
        -- File-based texture (typically Interface\Icons\, 64x64 source).
        -- 4th arg "LINEAR" = bilinear filtering for smooth up/downscale.
        pin.tex:SetTexture(mp.texture, nil, nil, "LINEAR")
        -- Crop the standard icon border (~5% padding around the art)
        pin.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    elseif mp.atlas and mp.atlas ~= "" then
        pin.tex = pin:CreateTexture(nil, "ARTWORK")
        pin.tex:SetAllPoints()
        -- 3rd arg "LINEAR" = bilinear filtering instead of default NEAREST.
        pin.tex:SetAtlas(mp.atlas, false, "LINEAR")
    end
    if pin.tex and pin.tex.SetSnapToPixelGrid then
        pin.tex:SetSnapToPixelGrid(false)
    end
    if pin.tex and pin.tex.SetTexelSnappingBias then
        pin.tex:SetTexelSnappingBias(0)
    end

    -- Final scale = per-pin override × per-city multiplier
    local cityScale = CITY_SCALE[map.GetMapID and map:GetMapID()] or 1.0
    pin:SetScale((mp.scale or 1) * cityScale)
    if pin.SetPosition then
        pin:SetPosition(mp.x, mp.y)
    end

    return pin
end

---------------------------------------------------------------------------------
-- Map Icons — Update & Provider
---------------------------------------------------------------------------------
function WM:UpdateMapIcons(map)
    if not map or not map.GetMapID then return end
    local uiMapID = map:GetMapID()
    dprint("UpdateMapIcons uiMapID=", tostring(uiMapID))
    local points = MAP_ICONS[uiMapID]
    if not points then
        dprint("no points for this map")
        return
    end

    if not self.antiOverlapApplied[uiMapID] then
        ApplyAntiOverlap(points)
        self.antiOverlapApplied[uiMapID] = true
    end

    self:UpdatePlayerProfessions()

    local filter = self.db and self.db.MapIconsProfessionFilter
    local shown, hidden = 0, 0

    for _, mp in ipairs(points) do
        local hide = false

        if filter and mp.type then
            local skill = PROFESSION_SKILL_LINE[mp.type]
            if skill and not self.playerProfessions[skill] then
                hide = true
            end
        end

        if not hide then
            local pin = mp.pin or CreatePin(map, mp)
            if pin.SetPosition then
                pin:SetPosition(mp.x, mp.y)
            end
            pin:Show()
            shown = shown + 1
        elseif mp.pin then
            mp.pin:Hide()
            hidden = hidden + 1
        end
    end

    if DEBUG_WM then
        local canvas = map.GetCanvas and map:GetCanvas()
        local cw = canvas and canvas:GetWidth() or 0
        local ch = canvas and canvas:GetHeight() or 0
        dprint("pins shown=", shown, "hidden=", hidden, "canvas=", cw, "x", ch)
    end
end

function WM:SetupMapIconsProvider()
    if self.mapIconsProvider then return end
    if not WorldMapFrame then return end
    if not _G.CreateFromMixins or not _G.MapCanvasDataProviderMixin then
        dprint("mixins not yet available, deferring provider setup")
        return
    end

    local Provider = _G.CreateFromMixins(_G.MapCanvasDataProviderMixin)

    Provider.RemoveAllData = function()
        for _, points in pairs(MAP_ICONS) do
            for _, mp in ipairs(points) do
                if mp.pin then
                    mp.pin:Hide()
                end
            end
        end
    end

    Provider.RefreshAllData = function(provider)
        provider:RemoveAllData()
        if WM.db and WM.db.MapIconsEnabled then
            WM:UpdateMapIcons(provider:GetMap())
        end
    end

    -- Fires when the map canvas resizes. Blizzard's own pin pool re-applies
    -- positions here; we do the same so pins don't stay stuck at (0,0)
    -- when the provider was refreshed before the canvas had real dimensions.
    Provider.OnCanvasSizeChanged = function(provider)
        if not (WM.db and WM.db.MapIconsEnabled) then return end
        local map = provider:GetMap()
        if not map then return end
        local uiMapID = map:GetMapID()
        local points = MAP_ICONS[uiMapID]
        if not points then return end
        for _, mp in ipairs(points) do
            if mp.pin and mp.pin.SetPosition then
                mp.pin:SetPosition(mp.x, mp.y)
            end
        end
        dprint("OnCanvasSizeChanged: re-applied positions for map", tostring(uiMapID))
    end

    WorldMapFrame:AddDataProvider(Provider)
    self.mapIconsProvider = Provider
    dprint("provider attached to WorldMapFrame")
end

function WM:RefreshMapIcons()
    if self.mapIconsProvider and self.mapIconsProvider.RefreshAllData then
        self.mapIconsProvider:RefreshAllData()
    end
end

-- Destroy every pin frame so next refresh rebuilds them with current settings.
-- Used when the visual style changes (Regular ↔ Small Icons).
function WM:RebuildMapIcons()
    for _, points in pairs(MAP_ICONS) do
        for _, mp in ipairs(points) do
            if mp.pin then
                mp.pin:Hide()
                mp.pin:SetParent(nil)
                mp.pin = nil
            end
        end
    end
    self:RefreshMapIcons()
end

---------------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------------
function WM:ApplySettings()
    self:UpdateDB()
    if not self.db then return end

    -- Scale
    self:ApplyScale()

    -- Waypoint search bar
    if self.db.WaypointBarEnabled then
        if WorldMapFrame then
            self:CreateSearchBar()
            if self.searchBar then
                self.searchBar:Show()
            end
        end
    else
        if self.searchBar then
            self.searchBar:Hide()
        end
    end

    -- Map icons
    if WorldMapFrame then
        self:SetupMapIconsProvider()
        self:RefreshMapIcons()
    end
end

---------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------
function WM:OnEnable()
    if not self.db or not self.db.Enabled then return end

    -- Retry provider setup when Blizzard_WorldMap / Blizzard_MapCanvas load,
    -- in case they weren't available at our first ApplySettings pass.
    self:RegisterEvent("ADDON_LOADED", function(_, addonName)
        if addonName == "Blizzard_WorldMap" or addonName == "Blizzard_MapCanvas" then
            dprint("ADDON_LOADED:", addonName, "— retrying map icons setup")
            self:ApplySettings()
        end
    end)

    C_Timer.After(0, function()
        self:ApplySettings()
    end)
end

function WM:OnDisable()
    self:RevertScale()
    -- Hide search bar
    if self.searchBar then
        self.searchBar:Hide()
    end
    -- Hide map icons
    if self.mapIconsProvider and self.mapIconsProvider.RemoveAllData then
        self.mapIconsProvider:RemoveAllData()
    end
end
