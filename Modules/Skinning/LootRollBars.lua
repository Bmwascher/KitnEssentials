---@class KE
local KE = select(2, ...)
local S = KE.Skins

if not KitnEssentials then return end

local LR = KitnEssentials:GetModule("LootRoll", true)
if not LR then return end

local _G = _G
local next, wipe, unpack = next, wipe, unpack
local tinsert, tremove, format = table.insert, table.remove, string.format
local CreateFrame = CreateFrame
local UIParent = UIParent
local GameTooltip = GameTooltip
local GameTooltip_Hide = GameTooltip_Hide
local GameTooltip_ShowCompareItem = GameTooltip_ShowCompareItem
local GetLootRollItemInfo = GetLootRollItemInfo
local GetLootRollItemLink = GetLootRollItemLink
local GetLootRollTimeLeft = GetLootRollTimeLeft
local IsModifiedClick = IsModifiedClick
local IsShiftKeyDown = IsShiftKeyDown
local RollOnLoot = RollOnLoot
local GetItemInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
local C_Timer = C_Timer

local NEED, GREED, PASS = NEED, GREED, PASS
local TRANSMOGRIFY, ROLL_DISENCHANT = TRANSMOGRIFY, ROLL_DISENCHANT

LR.RollBars = {}
local waitingRolls = {}

local rollTypes = { [1] = "need", [2] = "greed", [3] = "disenchant", [4] = "transmog", [0] = "pass" }

local ILVL_SLOTS = {
    INVTYPE_HEAD = true, INVTYPE_NECK = true, INVTYPE_SHOULDER = true,
    INVTYPE_CLOAK = true, INVTYPE_CHEST = true, INVTYPE_ROBE = true,
    INVTYPE_WRIST = true, INVTYPE_HAND = true, INVTYPE_WAIST = true,
    INVTYPE_LEGS = true, INVTYPE_FEET = true, INVTYPE_FINGER = true,
    INVTYPE_TRINKET = true, INVTYPE_WEAPON = true, INVTYPE_SHIELD = true,
    INVTYPE_2HWEAPON = true, INVTYPE_WEAPONMAINHAND = true,
    INVTYPE_WEAPONOFFHAND = true, INVTYPE_HOLDABLE = true,
    INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true,
}
local BIND_TEXT = {
    [1] = "BoP",
    [2] = "BoE",
    [3] = "BoU",
    [8] = "BoW",
}

local function QualityColor(quality)
    local qc = _G.ITEM_QUALITY_COLORS and _G.ITEM_QUALITY_COLORS[quality or 1]
    if qc then return qc.r, qc.g, qc.b end
    return 1, 1, 1
end

local function ClickRoll(button)
    RollOnLoot(button.parent.rollID, button.rolltype)
end

local function SetTip(button)
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    GameTooltip:AddLine(button.tiptext)
    if not button:IsEnabled() then
        GameTooltip:AddLine("|cffff3333" .. "Can't Roll")
    end
    GameTooltip:Show()
end

local function SetItemTip(button, event)
    if not button.rollID or (event == "MODIFIER_STATE_CHANGED" and not button:IsMouseOver()) then return end
    GameTooltip:SetOwner(button, "ANCHOR_TOPLEFT")
    GameTooltip:SetLootRollItem(button.rollID)
    if IsShiftKeyDown() and GameTooltip_ShowCompareItem then GameTooltip_ShowCompareItem() end
end

local function LootClick(button)
    if IsModifiedClick() then
        _G.HandleModifiedItemClick(button.link)
    end
end

local function StatusUpdate(status, elapsed)
    local bar = status.parent
    local rollID = bar.rollID
    if not rollID then
        bar:Hide()
        return
    end
    -- v3.5.694: previews drain locally -- GetLootRollTimeLeft errors on
    -- anything but a live numeric roll id.
    if bar.isPreview then
        local v = (status:GetValue() or 0) - elapsed
        if v <= 0 then
            LR:HidePreview()
        else
            status:SetValue(v)
        end
        return
    end
    if status.elapsed and status.elapsed > 0.1 then
        local timeLeft = GetLootRollTimeLeft(rollID)
        if timeLeft <= 0 then
            LR.CANCEL_LOOT_ROLL(bar, "OnUpdate", rollID)
        else
            status:SetValue(timeLeft)
            status.elapsed = 0
        end
    else
        status.elapsed = (status.elapsed or 0) + elapsed
    end
end

local iconCoords = {
    [0] = { 1.05, -0.1, 1.05, -0.1 },
    [2] = { 0.05, 1.05, -0.025, 0.85 },
    [1] = { 0.05, 1.05, -0.05, 0.95 },
    [3] = { 0.05, 1.05, -0.05, 0.95 },
    [4] = { 0, 1, 0, 1 },
}

local function RollTexCoords(button, icon, rolltype, minX, maxX, minY, maxY)
    local offset = icon == button.pushedTex and (rolltype == 0 and -0.05 or 0.05) or 0
    icon:SetTexCoord(minX - offset, maxX, minY - offset, maxY)
    if icon == button.disabledTex then
        icon:SetDesaturated(true)
        icon:SetAlpha(0.25)
    end
end

local function RollButtonTextures(button, texture, rolltype)
    button:SetNormalTexture(texture)
    button:SetPushedTexture(texture)
    button:SetDisabledTexture(texture)
    button:SetHighlightTexture(texture)

    button.normalTex = button:GetNormalTexture()
    button.disabledTex = button:GetDisabledTexture()
    button.pushedTex = button:GetPushedTexture()
    button.highlightTex = button:GetHighlightTexture()

    local minX, maxX, minY, maxY = unpack(iconCoords[rolltype])
    RollTexCoords(button, button.normalTex, rolltype, minX, maxX, minY, maxY)
    RollTexCoords(button, button.disabledTex, rolltype, minX, maxX, minY, maxY)
    RollTexCoords(button, button.pushedTex, rolltype, minX, maxX, minY, maxY)
    RollTexCoords(button, button.highlightTex, rolltype, minX, maxX, minY, maxY)
end

local function RollMouseDown(button)
    if button.highlightTex then button.highlightTex:SetAlpha(0) end
end

local function RollMouseUp(button)
    if button.highlightTex then button.highlightTex:SetAlpha(1) end
end

local function CreateRollButton(parent, texture, rolltype, tiptext)
    local button = CreateFrame("Button", format("$parent_%sButton", tiptext), parent)
    button:SetScript("OnMouseDown", RollMouseDown)
    button:SetScript("OnMouseUp", RollMouseUp)
    button:SetScript("OnClick", ClickRoll)
    button:SetScript("OnEnter", SetTip)
    button:SetScript("OnLeave", GameTooltip_Hide)
    button:SetMotionScriptsWhileDisabled(true)
    button:SetHitRectInsets(3, 3, 3, 3)

    RollButtonTextures(button, texture, rolltype)

    button.parent = parent
    button.rolltype = rolltype
    button.tiptext = tiptext
    return button
end

local function BarOnEvent(bar, event, rollID)
    LR[event](bar, event, rollID)
end

function LR:RollBar_Create(index)
    local db = self.db
    local bar = CreateFrame("Frame", "KE_LootRollBar" .. index, UIParent)
    bar:SetScript("OnEvent", BarOnEvent)
    bar:RegisterEvent("CANCEL_LOOT_ROLL")
    pcall(bar.RegisterEvent, bar, "CANCEL_ALL_LOOT_ROLLS")
    bar:Hide()

    local status = CreateFrame("StatusBar", nil, bar)
    status:SetFrameLevel(bar:GetFrameLevel())
    status:SetScript("OnUpdate", StatusUpdate)
    status:SetStatusBarTexture(KE:GetStatusbarPath(db.BarTexture or "KitnUI"))
    status.parent = bar
    -- v3.5.818 (bar had no visible outline): the backdrop was
    -- flush with the status bar's rect, so the FILL texture (higher
    -- frame level) painted over the border pixels on every side.
    -- Castbar convention is fill-inside-border; equivalent here:
    -- extend the backdrop 1px outside the fill.
    local sbd = S.Backdrop(status)
    if sbd then
        sbd:ClearAllPoints()
        sbd:SetPoint("TOPLEFT", status, "TOPLEFT", -1, 1)
        sbd:SetPoint("BOTTOMRIGHT", status, "BOTTOMRIGHT", 1, -1)
    end
    bar.status = status

    local spark = status:CreateTexture(nil, "ARTWORK", nil, 1)
    spark:SetBlendMode("BLEND")
    spark:SetPoint("RIGHT", status:GetStatusBarTexture())
    spark:SetPoint("BOTTOM")
    spark:SetPoint("TOP")
    spark:SetWidth(2)
    status.spark = spark

    local button = CreateFrame("Button", nil, bar)
    S.Backdrop(button)
    button:SetScript("OnEvent", SetItemTip)
    button:SetScript("OnEnter", SetItemTip)
    button:SetScript("OnLeave", GameTooltip_Hide)
    button:SetScript("OnClick", LootClick)
    button:RegisterEvent("MODIFIER_STATE_CHANGED")
    bar.button = button

    button.icon = button:CreateTexture(nil, "OVERLAY")
    button.icon:SetPoint("TOPLEFT", 1, -1)
    button.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    button.stack = button:CreateFontString(nil, "OVERLAY")
    button.stack:SetPoint("BOTTOMRIGHT", -1, 1)
    S.SetFont(button.stack, 12, "OUTLINE")

    button.ilvl = button:CreateFontString(nil, "OVERLAY")
    button.ilvl:SetPoint("BOTTOM", button, "BOTTOM", 0, 0)
    S.SetFont(button.ilvl, 11, "OUTLINE")

    bar.pass = CreateRollButton(bar, [[Interface\Buttons\UI-GroupLoot-Pass-Up]], 0, PASS or "Pass")
    bar.disenchant = CreateRollButton(bar, [[Interface\Buttons\UI-GroupLoot-DE-Up]], 3, ROLL_DISENCHANT or "Disenchant")
    bar.transmog = CreateRollButton(bar, [[Interface\MINIMAP\TRACKING\Transmogrifier]], 4, TRANSMOGRIFY or "Transmog")
    bar.greed = CreateRollButton(bar, [[Interface\Buttons\UI-GroupLoot-Coin-Up]], 2, GREED or "Greed")
    bar.need = CreateRollButton(bar, [[Interface\Buttons\UI-GroupLoot-Dice-Up]], 1, NEED or "Need")

    local name = bar:CreateFontString(nil, "OVERLAY")
    S.SetFont(name, db.NameFontSize or 13, "OUTLINE")
    name:SetJustifyH("LEFT")
    name:SetWordWrap(false)
    bar.name = name

    local bind = bar:CreateFontString(nil, "OVERLAY")
    S.SetFont(bind, db.NameFontSize or 13, "OUTLINE")
    bar.bind = bind

    tinsert(self.RollBars, bar)
    return bar
end

function LR:RollBar_Get(i)
    if i then
        return self.RollBars[i] or self:RollBar_Create(i)
    else
        for _, bar in next, self.RollBars do
            if not bar.rollID then return bar end
        end
    end
end

local MAX_BARS = 4

function LR:RollBars_Layout()
    local db = self.db
    local width = db.Width or 340
    local height = db.Height or 22
    local btnSize = db.ButtonSize or height

    for i = 1, MAX_BARS do
        local bar = self:RollBar_Get(i)
        bar:SetSize(width, height)

        bar.status:SetStatusBarTexture(KE:GetStatusbarPath(db.BarTexture or "KitnUI"))

        bar.button:ClearAllPoints()
        bar.button:SetPoint("RIGHT", bar, "LEFT", -2, 0)
        bar.button:SetSize(height, height)

        for _, key in next, rollTypes do
            local btn = bar[key]
            if btn then
                btn:SetSize(btnSize, btnSize)
                btn:ClearAllPoints()
            end
        end

        bar.status:ClearAllPoints()
        bar.name:ClearAllPoints()
        bar.bind:ClearAllPoints()

        bar.status:SetPoint("BOTTOM", bar, "BOTTOM", 3, 0)
        bar.status:SetSize(width, height / 3)

        local anchor = bar.status
        bar.pass:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", -3, 0)
        bar.disenchant:SetPoint("RIGHT", bar.pass, "LEFT", -3, 0)
        bar.transmog:SetPoint("RIGHT", bar.disenchant, "LEFT", -3, 0)
        bar.greed:SetPoint("RIGHT", bar.transmog, "LEFT", -3, 0)
        bar.need:SetPoint("RIGHT", bar.greed, "LEFT", -3, 0)

        bar.name:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 1, 3)
        bar.name:SetPoint("RIGHT", bar.bind, "LEFT", -1, 0)
        bar.bind:SetPoint("RIGHT", bar.need, "LEFT", -1, 0)

        S.SetFont(bar.name, db.NameFontSize or 13, "OUTLINE")
        S.SetFont(bar.bind, db.NameFontSize or 13, "OUTLINE")
    end

    self:RollBars_Anchor()
end

function LR:RollBars_Anchor()
    local db = self.db
    local spacing = db.Spacing or 1
    local p = db.Position or {}
    local lastBar
    for i, bar in next, self.RollBars do
        bar:ClearAllPoints()
        if i == 1 then
            bar:SetPoint(p.Point or "CENTER", UIParent, p.RelPoint or "CENTER", p.X or 0, p.Y or 250)
        else
            bar:SetPoint("BOTTOM", lastBar, "TOP", 0, spacing + 8)
        end
        lastBar = bar
    end
end

function LR:RollBar_Clear(bar, event)
    bar.rollID = nil
    bar.time = nil
    if next(waitingRolls) then
        local newRoll = waitingRolls[1]
        tremove(waitingRolls, 1)
        LR:START_LOOT_ROLL(event, newRoll.rollID, newRoll.rollTime)
    end
end

function LR.CANCEL_LOOT_ROLL(bar, event, rollID)
    if bar.rollID == rollID then
        LR:RollBar_Clear(bar, event)
    end
end

function LR.CANCEL_ALL_LOOT_ROLLS(bar, event)
    LR:RollBar_Clear(bar, event)
end

-- v3.5.692: sample roll for the GUI -- a fully dressed bar
-- (Thunderfury: legendary color, BoP, ilvl, all four buttons lit) with
-- clicks neutralized so nothing ever calls RollOnLoot on a fake id.
local PREVIEW_SECONDS = 15
local previewButtons = { "need", "greed", "disenchant", "transmog" }

function LR:ShowPreview()
    self:HidePreview()
    local bar = self:RollBar_Get()
    if not bar then return end

    local r, g, b = 1.0, 0.5, 0.0 -- legendary
    -- Sentinel: truthy so RollBar_Get treats the bar as busy (a real
    -- roll must not steal it and inherit mouse-disabled buttons), but
    -- never equal to any numeric rollID a cancel event could carry.
    bar.rollID = "PREVIEW"
    bar.isPreview = true
    bar.time = PREVIEW_SECONDS

    bar.button.link = nil
    bar.button.rollID = nil
    bar.button.icon:SetTexture(135349)
    bar.button.stack:SetShown(false)
    bar.button.ilvl:SetText("80")
    bar.button.ilvl:SetShown(true)
    bar.button.ilvl:SetTextColor(r, g, b)

    for _, key in ipairs(previewButtons) do
        local btn = bar[key]
        if btn then
            btn:SetEnabled(true)
            btn:EnableMouse(false) -- looks only; no RollOnLoot on fakes
        end
    end
    bar.button:EnableMouse(false)

    bar.name:SetText("Thunderfury, Blessed Blade of the Windseeker")
    bar.name:SetTextColor(r, g, b)
    bar.bind:SetVertexColor(1, 0.3, 0.1)
    bar.bind:SetText("BoP")

    local db = self.db
    if not db or db.QualityBorder ~= false then
        bar.status:SetStatusBarColor(r, g, b, 0.7)
        bar.status.spark:SetColorTexture(r, g, b, 0.9)
        local ibd = S.GetBackdrop(bar.button)
        if ibd then ibd:SetBackdropBorderColor(r, g, b, 1) end
    else
        -- v3.5.694: QualityBorder off = the brand path, same as live
        -- rolls -- the missing branch left the statusbar at its
        -- uncolored default (the white-and-grey report).
        local br2, bg2, bb2 = S.palette.brand[1], S.palette.brand[2], S.palette.brand[3]
        bar.status:SetStatusBarColor(br2, bg2, bb2, 0.7)
        bar.status.spark:SetColorTexture(br2, bg2, bb2, 0.9)
        local ibd = S.GetBackdrop(bar.button)
        if ibd then ibd:SetBackdropBorderColor(unpack(S.borderColor)) end
    end

    bar.status.elapsed = 1
    bar.status:SetMinMaxValues(0, PREVIEW_SECONDS)
    bar.status:SetValue(PREVIEW_SECONDS)
    bar:Show()

    self._previewBar = bar
    if self._previewTimer then self._previewTimer:Cancel() end
    -- Hide half a second BEFORE the status bar's own expiry would fire
    -- the CANCEL path with our sentinel id.
    self._previewTimer = C_Timer.NewTimer(PREVIEW_SECONDS - 0.5, function() LR:HidePreview() end)
end

function LR:HidePreview()
    if self._previewTimer then
        self._previewTimer:Cancel()
        self._previewTimer = nil
    end
    local bar = self._previewBar
    self._previewBar = nil
    if not bar then return end
    -- Restore mouse before the bar returns to the pool -- a real roll
    -- re-acquiring this bar must have working buttons.
    for _, key in ipairs(previewButtons) do
        local btn = bar[key]
        if btn then btn:EnableMouse(true) end
    end
    bar.button:EnableMouse(true)
    bar.isPreview = nil
    bar.rollID = nil -- genuinely free again, with working mouse
    bar:Hide()
    if self.RollBar_Release then self:RollBar_Release(bar) end
end

function LR:START_LOOT_ROLL(event, rollID, rollTime)
    local texture, name, count, quality, _, canNeed, canGreed, canDisenchant, _, _, _, _, canTransmog = GetLootRollItemInfo(rollID)
    if not name then
        for _, rollBar in next, self.RollBars do
            if rollBar.rollID == rollID then
                LR.CANCEL_LOOT_ROLL(rollBar, event, rollID)
            end
        end
        return
    end

    local bar = self:RollBar_Get()
    if not bar then
        tinsert(waitingRolls, { rollID = rollID, rollTime = rollTime })
        return
    end

    local itemLink = GetLootRollItemLink(rollID)
    local _, _, _, itemLevel, _, _, _, _, itemEquipLoc, _, _, itemClassID, itemSubClassID, bindType = GetItemInfo(itemLink)

    local db = self.db
    local r, g, b = QualityColor(quality)

    bar.rollID = rollID
    bar.time = rollTime

    bar.button.link = itemLink
    bar.button.rollID = rollID
    bar.button.icon:SetTexture(texture)
    bar.button.stack:SetShown(count > 1)
    bar.button.stack:SetText(count)

    local showIlvl = itemLevel and (ILVL_SLOTS[itemEquipLoc] or (itemClassID == 3 and itemSubClassID == 11)) and quality and quality > 1
    bar.button.ilvl:SetText(itemLevel or "")
    bar.button.ilvl:SetShown(showIlvl and true or false)
    bar.button.ilvl:SetTextColor(r, g, b)

    bar.need:SetEnabled(canNeed)
    bar.greed:SetEnabled(canGreed and not canTransmog)
    bar.disenchant:SetEnabled(canDisenchant)
    bar.transmog:SetEnabled(canTransmog)

    bar.name:SetText(name)
    bar.name:SetTextColor(r, g, b)

    local bop = bindType == 1
    bar.bind:SetVertexColor(bop and 1 or 0.3, bop and 0.3 or 1, bop and 0.1 or 0.3)
    bar.bind:SetText(BIND_TEXT[bindType] or "")

    if db.QualityBorder ~= false then
        bar.status:SetStatusBarColor(r, g, b, 0.7)
        bar.status.spark:SetColorTexture(r, g, b, 0.9)
        local ibd = S.GetBackdrop(bar.button)
        if ibd then ibd:SetBackdropBorderColor(r, g, b, 1) end
    else
        local br2, bg2, bb2 = S.palette.brand[1], S.palette.brand[2], S.palette.brand[3]
        bar.status:SetStatusBarColor(br2, bg2, bb2, 0.7)
        bar.status.spark:SetColorTexture(br2, bg2, bb2, 0.9)
        local ibd = S.GetBackdrop(bar.button)
        if ibd then ibd:SetBackdropBorderColor(unpack(S.borderColor)) end
    end

    bar.status.elapsed = 1
    bar.status:SetMinMaxValues(0, rollTime)
    bar.status:SetValue(rollTime)

    bar:Show()
end

function LR:SetupRollBars()
    self:RollBars_Layout()

    if not self._barsWired then
        self:RegisterEvent("START_LOOT_ROLL")

        UIParent:UnregisterEvent("START_LOOT_ROLL")
        UIParent:UnregisterEvent("CANCEL_LOOT_ROLL")
        self._barsWired = true
    end
end

function LR:TeardownRollBars()
    if not self._barsWired then return end
    self:UnregisterEvent("START_LOOT_ROLL")
    UIParent:RegisterEvent("START_LOOT_ROLL")
    UIParent:RegisterEvent("CANCEL_LOOT_ROLL")
    for _, bar in next, self.RollBars do
        bar.rollID = nil
        bar:Hide()
    end
    wipe(waitingRolls)
    self._barsWired = false
end
