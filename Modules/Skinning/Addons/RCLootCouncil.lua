local KE = select(2, ...)
local S = KE.Skins
local _G = _G
local ipairs = ipairs
local pairs = pairs
local pcall = pcall
local type = type
local hooksecurefunc = hooksecurefunc
local math_max = math.max
local math_floor = math.floor

local SKIN_KEY = "kitnui"
local MSA_BACKDROPS = { "Backdrop", "MenuBackdrop" }

local function ClearOwnBackdrop(frame)
    if frame and frame.SetBackdrop then frame:SetBackdrop(nil) end
end

-- RC repaints its own backdrop on every skin change, and it would cover the
-- skin's backdrop, which sits one frame level below.
local function SkinFrame(frame)
    local content, title = frame.content, frame.title
    if content then
        ClearOwnBackdrop(content)
        S.Backdrop(content)
        if content.Update then hooksecurefunc(content, "Update", ClearOwnBackdrop) end
    end
    if title then
        ClearOwnBackdrop(title)
        S.Template(title, "Default")
        if title.Update then hooksecurefunc(title, "Update", ClearOwnBackdrop) end
        -- RC centers the title on the window's top edge, so half of its opaque
        -- plate would cover the window's first row.
        title:ClearAllPoints()
        title:SetPoint("BOTTOM", frame, "TOP", 0, 0)
    end
end

local function SkinButton(button)
    S.Button(button)
end

-- RC recolors this border itself (item state), so it stays on RC's own frame:
-- a backdrop drawn below it would never get the color.
local function SkinIconBordered(button)
    if not button.SetBackdrop then return end
    S.OwnBackdrop(button)
    local bg, border = S.palette.control, S.palette.border
    button:SetBackdropColor(bg[1], bg[2], bg[3], bg[4])
    button:SetBackdropBorderColor(border[1], border[2], border[3], border[4])
    -- RC draws the item icon in BACKGROUND as well; the plate goes under it.
    if button.Center then button.Center:SetDrawLayer("BACKGROUND", -1) end
    local normal = button.GetNormalTexture and button:GetNormalTexture()
    if normal then
        S.Icon(normal)
        S.InsetToEdge(normal, button)
    end
    local highlight = button.GetHighlightTexture and button:GetHighlightTexture()
    if highlight then
        highlight:SetColorTexture(1, 1, 1, 0.3)
        S.InsetToEdge(highlight, button)
    end
end

local Elements = {
    RCFrame = SkinFrame,
    RCButton = SkinButton,
    IconBordered = SkinIconBordered,
}

local function SkinElement(skin, frame)
    if not frame or S.data(frame).rcSkinned then return end
    S.data(frame).rcSkinned = true
    skin(frame)
end

local function UI_New(ui, elementType)
    local skin = Elements[elementType]
    if not skin then return end
    local frames = ui:GetCreatedFramesOfType(elementType)
    SkinElement(skin, frames[#frames])
end

local HEADER_FLOOR = 8
-- The table library draws each header inside its column less this much on
-- each side.
local HEADER_PADDING = 2.5

-- The current size when every header fits at it, else the largest whole size
-- below it that fits, else the floor. A size at or below the floor is never
-- raised.
local function headerSize(current, fits)
    if current <= HEADER_FLOOR or fits(current) then return current end
    local size = math_floor(current)
    if size == current then size = size - 1 end
    while size > HEADER_FLOOR do
        if fits(size) then return size end
        size = size - 1
    end
    return HEADER_FLOOR
end

-- A header string is anchored to both sides of its column, so its string width
-- stops at the column; the unbounded width is the whole text's.
local function HeaderTextWidth(fs)
    if fs.GetUnboundedStringWidth then return fs:GetUnboundedStringWidth() end
    return fs:GetStringWidth()
end

-- A header wider than its column is cut, and the library re-anchors every
-- header on each column change, so headers are fitted by size instead: one
-- size for the whole table. The library keeps these strings for the columns'
-- life, so the size holds.
local function FitHeaders(name, cols)
    if type(cols) ~= "table" then return end
    local strings, widths = {}, {}
    for i, col in ipairs(cols) do
        local header = _G[name .. "HeadCol" .. i]
        local fs = header and header.GetFontString and header:GetFontString()
        if fs and type(col) == "table" and type(col.width) == "number" then
            strings[#strings + 1] = fs
            widths[#widths + 1] = col.width - 2 * HEADER_PADDING
        end
    end
    local first = strings[1]
    if not first then return end
    local _, current = first:GetFont()
    if not current then return end
    local function setSize(size)
        for _, fs in ipairs(strings) do
            local face, _, flags = fs:GetFont()
            if face then fs:SetFont(face, size, flags or "") end
        end
    end
    local function fits(size)
        if size ~= current then setSize(size) end
        for i, fs in ipairs(strings) do
            local w = HeaderTextWidth(fs)
            if type(w) == "number" and not issecretvalue(w) and w > widths[i] then
                return false
            end
        end
        return true
    end
    local size = headerSize(current, fits)
    if size ~= current then setSize(size) end
end

local function SkinScrollTable(lib, cols, _, _, _, parent)
    local parentName = parent and parent.GetName and parent:GetName()
    if not (parentName and parentName:find("^RC")) then return end
    local frame = _G["ScrollTable" .. ((lib.framecount or 1) - 1)]
    if not frame or S.data(frame).rcSkinned then return end
    S.data(frame).rcSkinned = true
    ClearOwnBackdrop(frame)
    S.Backdrop(frame)
    local name = frame:GetName()
    S.ScrollBar(_G[name .. "ScrollFrameScrollBar"])
    local trough, troughBorder = _G[name .. "ScrollTrough"], _G[name .. "ScrollTroughBorder"]
    if trough then trough:Hide() end
    if troughBorder then troughBorder:Hide() end
    FitHeaders(name, cols)
end

-- The library parks released controls on a nil parent. Across that round trip
-- a plate can come back far above its control and cover the label, so every
-- plate goes back under its owner on each spawn.
local function RelevelPlate(owner)
    local bd = S.GetBackdrop(owner)
    if not bd then return end
    local target = math_max(owner:GetFrameLevel() - 1, 0)
    if bd:GetFrameLevel() ~= target then bd:SetFrameLevel(target) end
end

-- Every dialog of this library instance is styled: the library pools dialogs
-- and their controls across popups, so styling one popup styles the pool.
local function SkinDialogs(lib)
    if not lib.active_dialogs then return end
    for _, dialog in ipairs(lib.active_dialogs) do
        if not S.data(dialog).rcSkinned then
            S.data(dialog).rcSkinned = true
            ClearOwnBackdrop(dialog)
            S.Backdrop(dialog)
            -- Reset puts the library's dialog art back on every reuse.
            hooksecurefunc(dialog, "Reset", ClearOwnBackdrop)
            S.CloseButton(dialog.close_button)
        end
        RelevelPlate(dialog)
        if dialog.buttons then
            for _, button in ipairs(dialog.buttons) do
                S.Button(button)
                RelevelPlate(button)
            end
        end
        if dialog.editboxes then
            for _, editBox in ipairs(dialog.editboxes) do
                S.EditBox(editBox)
                RelevelPlate(editBox)
            end
        end
        if dialog.checkboxes then
            for _, checkBox in ipairs(dialog.checkboxes) do
                S.CheckBox(checkBox)
                RelevelPlate(checkBox)
            end
        end
    end
end

local msaLevels = 0

local function OnListShow(list)
    local d = S.data(list)
    if d.rcSkinned then return end
    d.rcSkinned = true
    local name = list:GetName()
    if not name then return end
    for _, suffix in ipairs(MSA_BACKDROPS) do
        local backdrop = _G[name .. suffix]
        if backdrop then
            ClearOwnBackdrop(backdrop)
            S.Backdrop(backdrop)
        end
    end
end

-- MSA calls this for every menu button it adds, so the common path is one
-- comparison; each new level gets the same first-show skin.
local function HookNewLevels()
    local maxLevels = _G.MSA_DROPDOWNMENU_MAXLEVELS or 0
    if maxLevels <= msaLevels then return end
    for level = msaLevels + 1, maxLevels do
        local list = _G["MSA_DropDownList" .. level]
        if list and list.HookScript then list:HookScript("OnShow", OnListShow) end
    end
    msaLevels = maxLevels
end

-- RC's page paths name the arrow's direction. Anything else, the clear value
-- included, says nothing about it.
local function PageDirection(texture)
    if type(texture) ~= "string" then return nil end
    if texture:find("PrevPage", 1, true) then return "left" end
    if texture:find("NextPage", 1, true) then return "right" end
    return nil
end

-- RC flips the arrow by swapping its page textures; the skin's arrow follows.
local function PageButton_SetNormalTexture(button, texture)
    local arrow = S.data(button).arrow
    local direction = PageDirection(texture)
    if arrow and direction then S.ArrowTexture(arrow, direction) end
end

-- No plate: the arrow helper re-kills the textures of every child frame on
-- hover, show and each state change, a backdrop child included. The engine
-- shows the normal texture itself after a click, past any hide, so its art is
-- cleared instead.
local function SkinPageButton(button, direction)
    if not button or S.data(button).rcSkinned then return end
    S.data(button).rcSkinned = true
    S.ArrowButton(button, direction)
    S.ClearButtonArt(button)
    hooksecurefunc(button, "SetNormalTexture", PageButton_SetNormalTexture)
end

local function VotingFrame_GetFrame()
    local frame = _G.DefaultRCLootCouncilFrame
    if not frame then return end
    local addon = _G.RCLootCouncil
    local db = addon and addon.Getdb and addon:Getdb()
    local votingDB = db and db.modules and db.modules.RCVotingFrame
    SkinPageButton(frame.moreInfoBtn, votingDB and votingDB.moreInfo and "left" or "right")
end

local function LootHistory_GetFrame()
    local frame = _G.DefaultRCLootHistoryFrame
    if frame then SkinPageButton(frame.moreInfoBtn, "left") end
end

local function SessionData_GetFrame(sessionData)
    local frame = sessionData and sessionData.frame
    if not frame or S.data(frame).rcSkinned then return end
    S.data(frame).rcSkinned = true
    if frame.NineSlice then frame.NineSlice:SetAlpha(0) end
    S.Backdrop(frame)
end

local function SessionFrame_GetFrame()
    S.CheckBox(_G.DefaultRCSessionSetupFrameToggle)
end

local function Sync_Spawn()
    local frame = _G.DefaultRCLootCouncilSyncFrame
    local bar = frame and frame.statusBar
    if not bar or S.data(bar).rcSkinned then return end
    S.data(bar).rcSkinned = true
    bar:SetStatusBarTexture(KE:GetStatusbarPath("KitnUI"))
    S.StatusBar(bar)
end

-- RC gives only the player's own items a row border; the skin swaps it for a
-- thin one in the skin's border color. backdropInfo is read directly because
-- GetBackdrop copies a table on every call, and this runs on every row update.
local function LootEntry_Update(entry)
    local frame = entry and entry.frame
    if not (frame and frame.backdropInfo) then return end
    S.OwnBackdrop(frame, true)
    local border = S.palette.border
    frame:SetBackdropBorderColor(border[1], border[2], border[3], border[4])
end

-- RC re-points and re-sizes the bar on every relayout, with insets sized for
-- its thick tooltip border, so the fit is re-applied after each one.
local function LootEntry_FitBar(entry)
    if entry.timeoutBar and entry.frame then S.InsetToEdge(entry.timeoutBar, entry.frame) end
end

local function SkinLootEntry(entry)
    local d = S.data(entry)
    if d.rcSkinned then return end
    d.rcSkinned = true
    if entry.timeoutBar then
        entry.timeoutBar:SetStatusBarTexture(KE:GetStatusbarPath("KitnUI"))
    end
    -- Rows of other players' items wear no KE edge, so the row is tracked for
    -- its bar alone.
    if entry.frame then S.TrackEdgeClients(entry.frame) end
    LootEntry_FitBar(entry)
    if entry.UpdatePosition then hooksecurefunc(entry, "UpdatePosition", LootEntry_FitBar) end
    if entry.noteEditbox then
        ClearOwnBackdrop(entry.noteEditbox)
        S.EditBox(entry.noteEditbox)
    end
    LootEntry_Update(entry)
    hooksecurefunc(entry, "Update", LootEntry_Update)
end

local function EntryManager_GetEntry(manager)
    if not manager.entries then return end
    for _, entry in ipairs(manager.entries) do SkinLootEntry(entry) end
end

local inOwnCall = false

-- Inside its own ActivateSkin call the hook must do nothing, or it recurses.
local function ensurePlan(present, isKitnUI, ownCall)
    if ownCall then return false, false end
    return not present, not (present and isKitnUI)
end

local function CopyColor(target, source)
    if type(target) ~= "table" then target = {} end
    target[1], target[2], target[3], target[4] = source[1], source[2], source[3], source[4]
    return target
end

local function WriteEntry(entry)
    entry.name = "KitnUI"
    entry.bgColor = CopyColor(entry.bgColor, S.palette.window)
    entry.borderColor = CopyColor(entry.borderColor, S.palette.border)
    entry.background = "Solid"
    entry.border = "None"
end

-- Profile switches, settings sync and the player's own pick all pass through
-- ActivateSkin, and a sync can replace the whole skin list.
local function ensureSkinEntry(addon)
    local db = addon and addon.Getdb and addon:Getdb()
    local skins = db and db.skins
    if type(skins) ~= "table" then return end
    local insert, activate = ensurePlan(skins[SKIN_KEY] ~= nil, db.currentSkin == SKIN_KEY, inOwnCall)
    if insert then
        local entry = {}
        WriteEntry(entry)
        skins[SKIN_KEY] = entry
    end
    if activate then
        inOwnCall = true
        local ok, err = pcall(addon.ActivateSkin, addon, SKIN_KEY)
        inOwnCall = false
        if not ok then _G.geterrorhandler()(err) end
    end
end

-- The entry's colors follow KE's saved window colors; refreshed before RC's
-- own login ActivateSkin copies them into its windows.
local function RefreshEntryColors(addon)
    local db = addon.Getdb and addon:Getdb()
    local skins = db and db.skins
    local entry = type(skins) == "table" and skins[SKIN_KEY]
    if type(entry) == "table" then WriteEntry(entry) end
end

-- Covers RC having built elements before the hooks went in.
local function SweepCreated(ui)
    for elementType, skin in pairs(Elements) do
        for _, frame in ipairs(ui:GetCreatedFramesOfType(elementType)) do
            SkinElement(skin, frame)
        end
    end
end

local function HookModule(addon, name, method, func)
    local module = addon:GetModule(name, true)
    if module and module[method] then hooksecurefunc(module, method, func) end
end

local function Skin()
    local addon = _G.RCLootCouncil
    if not (addon and addon.UI and addon.GetModule) then return end

    hooksecurefunc(addon.UI, "New", UI_New)
    hooksecurefunc(addon.UI, "NewNamed", UI_New)

    local LibStub = _G.LibStub
    local ScrollingTable = LibStub and LibStub("ScrollingTable", true)
    if ScrollingTable then hooksecurefunc(ScrollingTable, "CreateST", SkinScrollTable) end
    local LibDialog = LibStub and LibStub("LibDialog-1.1", true)
    if LibDialog then hooksecurefunc(LibDialog, "Spawn", SkinDialogs) end

    HookModule(addon, "RCVotingFrame", "GetFrame", VotingFrame_GetFrame)
    HookModule(addon, "RCLootHistory", "GetFrame", LootHistory_GetFrame)
    HookModule(addon, "RCSessionFrame", "GetFrame", SessionFrame_GetFrame)
    HookModule(addon, "Sync", "Spawn", Sync_Spawn)

    local lootHistory = addon:GetModule("RCLootHistory", true)
    if lootHistory and lootHistory.SessionData then
        hooksecurefunc(lootHistory.SessionData, "GetSessionResponsesFrame", SessionData_GetFrame)
    end

    local lootFrame = addon:GetModule("RCLootFrame", true)
    if lootFrame and lootFrame.EntryManager then
        hooksecurefunc(lootFrame.EntryManager, "GetEntry", EntryManager_GetEntry)
        EntryManager_GetEntry(lootFrame.EntryManager)
    end

    if _G.MSA_DropDownMenu_CreateFrames then
        HookNewLevels()
        hooksecurefunc("MSA_DropDownMenu_CreateFrames", HookNewLevels)
    end

    SweepCreated(addon.UI)
    RefreshEntryColors(addon)
    ensureSkinEntry(addon)
    hooksecurefunc(addon, "ActivateSkin", ensureSkinEntry)
end

S:Register("RCLootCouncil", Skin, "RCLootCouncil")
