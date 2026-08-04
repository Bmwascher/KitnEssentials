---@class KE
local KE = select(2, ...)
local S = KE.Skins

if not KitnEssentials then
    error("LootFrame: Addon object not initialized. Check file load order!")
    return
end

---@class LootFrame: AceModule, AceEvent-3.0
local LF = KitnEssentials:NewModule("LootFrame", "AceEvent-3.0")

-- Destructive: Build() calls _G.LootFrame:UnregisterAllEvents(), which no
-- OnDisable can undo. The profile-switch path and the ElvUI startup skip both
-- gate on name:find("^Skin") or module.keDeferToReload
-- (Core/ProfileManager.lua, Core/Main.lua), and "LootFrame" fails the
-- ^Skin test.
LF.keDeferToReload = true

local _G = _G
local max = math.max
local next = next
local unpack = unpack
local hooksecurefunc = hooksecurefunc
local CreateFrame = CreateFrame
local UIParent = UIParent
local GameTooltip = GameTooltip
local CloseLoot = CloseLoot
local LootSlot = LootSlot
local LootSlotHasItem = LootSlotHasItem
local GetNumLootItems = GetNumLootItems
local GetLootSlotInfo = GetLootSlotInfo
local GetLootSlotLink = GetLootSlotLink
local GetCursorPosition = GetCursorPosition
local IsFishingLoot = IsFishingLoot
local IsModifiedClick = IsModifiedClick
local ResetCursor = ResetCursor
local UnitIsDead = UnitIsDead
local UnitIsFriend = UnitIsFriend
local UnitName = UnitName
local StaticPopup_Hide = StaticPopup_Hide
local CursorUpdate = CursorUpdate
local CursorOnUpdate = CursorOnUpdate
local GetCVarBool = C_CVar and C_CVar.GetCVarBool
local GetItemReagentQualityInfo = C_TradeSkillUI and C_TradeSkillUI.GetItemReagentQualityInfo

local LCG = LibStub and LibStub("LibCustomGlow-1.0", true)

local ROW_H = 28
local lootFrame

local coinTextureIDs = {
    [133784] = true, [133785] = true, [133786] = true,
    [133787] = true, [133788] = true, [133789] = true,
}

local function QualityColor(quality)
    local qc = _G.ITEM_QUALITY_COLORS and _G.ITEM_QUALITY_COLORS[quality or 1]
    if qc then return qc.r, qc.g, qc.b end
    return 1, 1, 1
end

local function SlotEnter(slot)
    local id = slot:GetID()
    if LootSlotHasItem(id) then
        GameTooltip:SetOwner(slot, "ANCHOR_RIGHT")
        GameTooltip:SetLootItem(id)
        if CursorUpdate then CursorUpdate(slot) end
    end
    slot.hover:Show()
end

local function SlotLeave(slot)
    slot.hover:Hide()
    GameTooltip:Hide()
    ResetCursor()
end

local function SlotClick(slot)
    local frame = _G.LootFrame
    frame.selectedQuality = slot.quality
    frame.selectedItemName = slot.name:GetText()
    frame.selectedTexture = slot.icon:GetTexture()
    frame.selectedLootButton = slot:GetName()
    frame.selectedSlot = slot:GetID()

    if IsModifiedClick() then
        _G.HandleModifiedItemClick(GetLootSlotLink(frame.selectedSlot))
    else
        StaticPopup_Hide("CONFIRM_LOOT_DISTRIBUTION")
        LootSlot(frame.selectedSlot)
    end
end

local function SlotShow(slot)
    if GameTooltip:IsOwned(slot) then
        GameTooltip:SetOwner(slot, "ANCHOR_RIGHT")
        GameTooltip:SetLootItem(slot:GetID())
        if CursorOnUpdate then CursorOnUpdate(slot) end
    end
end

local function CreateSlot(id)
    local size = ROW_H - 2

    local slot = CreateFrame("Button", "KE_LootSlot" .. id, lootFrame)
    slot:SetPoint("LEFT", 8, 0)
    slot:SetPoint("RIGHT", -8, 0)
    slot:SetHeight(size)
    slot:SetID(id)
    slot:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    slot:SetScript("OnEnter", SlotEnter)
    slot:SetScript("OnLeave", SlotLeave)
    slot:SetScript("OnClick", SlotClick)
    slot:SetScript("OnShow", SlotShow)

    local hover = slot:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints()
    hover:SetColorTexture(0.851, 0.851, 0.851, 0.15)
    hover:Hide()
    slot.hover = hover

    local iconFrame = CreateFrame("Frame", nil, slot)
    iconFrame:SetSize(size, size)
    iconFrame:SetPoint("RIGHT", slot)
    S.Backdrop(iconFrame)
    slot.iconFrame = iconFrame

    local icon = iconFrame:CreateTexture(nil, "ARTWORK")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon:SetPoint("TOPLEFT", 1, -1)
    icon:SetPoint("BOTTOMRIGHT", -1, 1)
    slot.icon = icon

    local count = iconFrame:CreateFontString(nil, "OVERLAY")
    count:SetJustifyH("RIGHT")
    count:SetPoint("BOTTOMRIGHT", iconFrame, -2, 2)
    S.SetFont(count, 12, "OUTLINE")
    -- Quoted, not the number 1: SetText is annotated string?, and the number form was
    -- this wave's only new wowlua-ls warning. Render is identical (SetText
    -- coerces), and the value never reaches the screen -- LOOT_OPENED
    -- overwrites it with the real stack count before the slot is shown.
    count:SetText("1")
    slot.count = count

    local name = slot:CreateFontString(nil, "OVERLAY")
    name:SetJustifyH("LEFT")
    name:SetPoint("LEFT", slot)
    name:SetPoint("RIGHT", icon, "LEFT", -4, 0)
    name:SetNonSpaceWrap(true)
    S.SetFont(name, 13, "OUTLINE")
    slot.name = name

    local questTexture = iconFrame:CreateTexture(nil, "OVERLAY")
    questTexture:SetPoint("TOPLEFT", 1, -1)
    questTexture:SetPoint("BOTTOMRIGHT", -1, 1)
    questTexture:SetTexture(_G.TEXTURE_ITEM_QUEST_BANG)
    questTexture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    slot.questTexture = questTexture

    local profQuality = iconFrame:CreateTexture(nil, "OVERLAY")
    profQuality:SetPoint("TOPLEFT", -3, 2)
    slot.ProfessionQualityOverlayFrame = profQuality

    lootFrame.slots[id] = slot
    return slot
end

local function AnchorSlots(frame)
    local shownSlots = 0
    for _, slot in next, frame.slots do
        if slot:IsShown() then
            shownSlots = shownSlots + 1
            slot:SetPoint("TOP", frame, 4, (-8 + ROW_H) - (shownSlots * ROW_H))
        end
    end
    frame:SetHeight(max(shownSlots * ROW_H + 16, 20))
end

-- Anchors `frame`'s TOPLEFT to Blizzard's LootFrame's TOPLEFT (its
-- authoritative Edit Mode position -- Blizzard re-applies it on every show)
-- when that frame exists, falling back to the saved db.Position otherwise.
-- Read _G.LootFrame at call time, never captured at file scope.
local function AnchorToBlizzardLoot(frame, db)
    local blizzFrame = _G.LootFrame
    if blizzFrame then
        frame:SetPoint("TOPLEFT", blizzFrame, "TOPLEFT", 0, 0)
    else
        local p = db and db.Position or {}
        frame:SetPoint(p.Point or "TOPRIGHT", UIParent, p.RelPoint or "TOPRIGHT", p.X or -618, p.Y or -564)
    end
end

local function FrameHide()
    StaticPopup_Hide("CONFIRM_LOOT_DISTRIBUTION")
    CloseLoot()
    if _G.MasterLooterFrame then _G.MasterLooterFrame:Hide() end
end

function LF:LOOT_SLOT_CLEARED(_, id)
    if not lootFrame:IsShown() then return end
    local slot = lootFrame.slots[id]
    if slot then slot:Hide() end
    AnchorSlots(lootFrame)
end

function LF:LOOT_CLOSED()
    StaticPopup_Hide("LOOT_BIND")
    lootFrame:Hide()
    for _, slot in next, lootFrame.slots do slot:Hide() end
end

function LF:LOOT_OPENED(_, autoloot)
    lootFrame:Show()
    if not lootFrame:IsShown() then
        CloseLoot(not autoloot)
        return
    end

    if IsFishingLoot() then
        lootFrame.title:SetText("Loot")
    elseif not UnitIsFriend("player", "target") and UnitIsDead("target") then
        lootFrame.title:SetText(UnitName("target"))
    else
        lootFrame.title:SetText(_G.LOOT or "Loot")
    end

    lootFrame:ClearAllPoints()

    if GetCVarBool and GetCVarBool("lootUnderMouse") then
        local scale = lootFrame:GetEffectiveScale()
        local x, y = GetCursorPosition()
        lootFrame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", (x / scale) - 40, (y / scale) + 20)
        lootFrame:Raise()
    else
        AnchorToBlizzardLoot(lootFrame, self.db)
    end

    local maxQuality, maxWidth = 0, 0
    local numItems = GetNumLootItems()
    if numItems > 0 then
        for i = 1, numItems do
            local slot = lootFrame.slots[i] or CreateSlot(i)
            local textureID, item, count, _, quality, _, isQuestItem, questId, isActive = GetLootSlotInfo(i)
            local r, g, b = QualityColor(quality or 0)
            local itemLink = GetLootSlotLink(i)

            if item and coinTextureIDs[textureID] then
                item = item:gsub("\n", ", ")
            end

            slot.count:SetShown(count and count > 1)
            slot.count:SetText(count or "")

            slot.quality = quality
            slot.name:SetText(item)
            slot.name:SetTextColor(r, g, b)
            slot.icon:SetTexture(textureID)

            maxWidth = max(maxWidth, slot.name:GetStringWidth())
            if quality then maxQuality = max(maxQuality, quality) end

            if GetItemReagentQualityInfo then
                local info = itemLink and GetItemReagentQualityInfo(itemLink)
                if info and info.iconInventory then
                    slot.ProfessionQualityOverlayFrame:SetAtlas(info.iconInventory, true)
                    slot.ProfessionQualityOverlayFrame:Show()
                else
                    slot.ProfessionQualityOverlayFrame:Hide()
                end
            end

            local questTexture = slot.questTexture
            if questId and not isActive then
                questTexture:Show()
                if LCG then LCG.ButtonGlow_Start(slot.iconFrame) end
            elseif questId or isQuestItem then
                questTexture:Hide()
                if LCG then LCG.ButtonGlow_Start(slot.iconFrame) end
            else
                questTexture:Hide()
                if LCG then LCG.ButtonGlow_Stop(slot.iconFrame) end
            end

            if textureID then
                slot:Enable()
                slot:Show()
            end
        end
    else
        local slot = lootFrame.slots[1] or CreateSlot(1)
        slot.name:SetText("No Loot")
        slot.name:SetTextColor(QualityColor(0))
        slot.icon:SetTexture(136511)
        slot.count:Hide()
        slot:Disable()
        slot:Show()
        maxWidth = max(maxWidth, slot.name:GetStringWidth())
    end

    AnchorSlots(lootFrame)

    local bd = S.GetBackdrop(lootFrame)
    if bd then
        if self.db.QualityBorder ~= false and maxQuality > 1 then
            local r, g, b = QualityColor(maxQuality)
            bd:SetBackdropBorderColor(r, g, b, 0.8)
        else
            bd:SetBackdropBorderColor(unpack(S.borderColor))
        end
    end
    lootFrame:SetWidth(max(maxWidth + 60, self.db.MinWidth or 150))
end

function LF:OPEN_MASTER_LOOT_LIST()
    if _G.MasterLooterFrame_Show and _G.LootFrame.selectedLootButton then
        _G.MasterLooterFrame_Show(_G.LootFrame.selectedLootButton)
    end
end

function LF:UPDATE_MASTER_LOOT_LIST()
    if _G.MasterLooterFrame_UpdatePlayers and _G.LootFrame.selectedLootButton then
        _G.MasterLooterFrame_UpdatePlayers()
    end
end

-- This module owns no Edit Mode anchor of its own -- it follows Blizzard's
-- LootFrame anchor instead (AnchorToBlizzardLoot above). SetPoint against
-- Blizzard's frame is a live frame relationship: when Blizzard re-anchors
-- its own frame, ours moves with it, with no re-application needed.
function LF:ApplyPosition()
    local f = _G.KE_LootFrame
    if f and f:IsShown() then
        f:ClearAllPoints()
        AnchorToBlizzardLoot(f, self.db)
    end
end

function LF:UpdateDB()
    self.db = KE.db.profile.Skinning.Loot
end

function LF:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

function LF:Build()
    if lootFrame then return end

    lootFrame = CreateFrame("Button", "KE_LootFrame", UIParent)
    lootFrame:Hide()
    lootFrame:SetClampedToScreen(true)
    lootFrame:SetSize(256, 64)
    S.Backdrop(lootFrame)
    lootFrame:SetFrameStrata(_G.LootFrame and _G.LootFrame:GetFrameStrata() or "HIGH")
    lootFrame:SetToplevel(true)

    lootFrame.title = lootFrame:CreateFontString(nil, "OVERLAY")
    S.SetFont(lootFrame.title, 13, "OUTLINE")
    lootFrame.title:SetPoint("BOTTOMLEFT", lootFrame, "TOPLEFT", 0, 3)

    lootFrame.slots = {}
    lootFrame:SetScript("OnHide", FrameHide)

    hooksecurefunc("CloseSpecialWindows", function()
        if lootFrame and lootFrame:IsShown() then lootFrame:Hide() end
    end)

    if _G.LootFrame then _G.LootFrame:UnregisterAllEvents() end

    if _G.MasterLooterFrame then
        hooksecurefunc(_G.MasterLooterFrame, "Hide", _G.MasterLooterFrame.ClearAllPoints)
    end
end

function LF:OnEnable()
    if KE:ShouldNotLoadModule() then return end
    self:UpdateDB()
    if not self.db or not self.db.Enabled then return end

    self:Build()
    self:RegisterEvent("LOOT_OPENED")
    self:RegisterEvent("LOOT_SLOT_CLEARED")
    self:RegisterEvent("LOOT_CLOSED")

    pcall(self.RegisterEvent, self, "OPEN_MASTER_LOOT_LIST")
    pcall(self.RegisterEvent, self, "UPDATE_MASTER_LOOT_LIST")
end

function LF:OnDisable()
    self:UnregisterAllEvents()
    if lootFrame then lootFrame:Hide() end
end

function LF:ApplySettings()
    self:UpdateDB()
end
