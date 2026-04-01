-- KitnEssentials namespace
---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class VantusRune: AceModule, AceEvent-3.0
local VR = KitnEssentials:NewModule("VantusRune", "AceEvent-3.0")

local CreateFrame = CreateFrame
local GetTime = GetTime
local C_Timer = C_Timer
local ipairs = ipairs
local string_format = string.format

---------------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------------
local BUTTON_WIDTH = 150
local BUTTON_HEIGHT = 35

-- Vantus Rune item IDs in priority order (best quality first)
-- Update these each raid tier
local RUNE_PRIORITY = { 245880, 245879 }
local RUNE_SET = {}
for _, id in ipairs(RUNE_PRIORITY) do RUNE_SET[id] = true end

---------------------------------------------------------------------------------
-- Module state
---------------------------------------------------------------------------------
VR.vantusButton = nil
VR.popup = nil
VR.popupEndTime = nil

---------------------------------------------------------------------------------
-- UpdateDB
---------------------------------------------------------------------------------
function VR:UpdateDB()
    self.db = KE.db.profile.VantusRune
end

---------------------------------------------------------------------------------
-- Bag Helpers
---------------------------------------------------------------------------------
function VR:PlayerHasRune()
    for bag = 0, 4 do
        local slots = C_Container.GetContainerNumSlots(bag)
        for slot = 1, slots do
            local itemID = C_Container.GetContainerItemID(bag, slot)
            if itemID and RUNE_SET[itemID] then return true end
        end
    end
    return false
end

function VR:FindEmptyBagSlot()
    for bag = 0, 4 do
        local slots = C_Container.GetContainerNumSlots(bag)
        for slot = 1, slots do
            if not C_Container.GetContainerItemID(bag, slot) then
                return bag, slot
            end
        end
    end
    return nil, nil
end

---------------------------------------------------------------------------------
-- Guild Bank Search
---------------------------------------------------------------------------------
function VR:FindRuneInGuildBank()
    local numTabs = GetNumGuildBankTabs()
    for _, targetID in ipairs(RUNE_PRIORITY) do
        for tab = 1, numTabs do
            local _, _, canView, _, _, numWithdrawals = GetGuildBankTabInfo(tab)
            if canView and numWithdrawals > 0 then
                for slot = 1, 98 do
                    local link = GetGuildBankItemLink(tab, slot)
                    if link then
                        local itemID = GetItemInfoInstant(link)
                        if itemID == targetID then
                            return tab, slot, itemID
                        end
                    end
                end
            end
        end
    end
    return nil
end

---------------------------------------------------------------------------------
-- Withdrawal
---------------------------------------------------------------------------------
function VR:WithdrawRune(guildTab, guildSlot, bagIndex, bagSlot)
    ClearCursor()
    SplitGuildBankItem(guildTab, guildSlot, 1)
    C_Container.PickupContainerItem(bagIndex, bagSlot)

    -- Verify after a short delay — Blizzard may silently block cross-realm withdrawals
    C_Timer.After(0.5, function()
        if self:PlayerHasRune() then
            if self.db.ShowChatMessages then
                KE:Print("|cff00ff00Vantus Rune withdrawn!|r")
            end
        else
            if self.db.ShowChatMessages then
                KE:Print("|cffff4444Withdrawal failed. Cross-realm guild banks cannot split/withdraw items.|r")
            end
        end
    end)
end

function VR:StartWithdrawal()
    -- Already have one?
    if self:PlayerHasRune() then
        if self.db.ShowChatMessages then
            KE:Print("|cff00aaffYou already have a Vantus Rune in your bags.|r")
        end
        return
    end

    -- Bag space?
    local bagIndex, bagSlot = self:FindEmptyBagSlot()
    if not bagIndex then
        if self.db.ShowChatMessages then
            KE:Print("|cffff8800No free bag slots for Vantus Rune.|r")
        end
        return
    end

    -- Rune available?
    local guildTab, guildSlot = self:FindRuneInGuildBank()
    if not guildTab then
        if self.db.ShowChatMessages then
            KE:Print("|cffff4444No Vantus Rune found in the Guild Bank, or out of withdrawals.|r")
        end
        return
    end

    -- Show confirmation popup
    self:ShowConfirmation(guildTab, guildSlot, bagIndex, bagSlot)
end

---------------------------------------------------------------------------------
-- Confirmation Popup
---------------------------------------------------------------------------------
function VR:CreatePopup()
    if self.popup then return end

    local popup = CreateFrame("Frame", "KE_VantusRunePopup", UIParent, "BackdropTemplate")
    popup:SetSize(460, 120)
    popup:SetPoint("CENTER", UIParent, "CENTER", 0, 200)
    popup:SetFrameStrata("DIALOG")
    popup:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    popup:SetBackdropColor(0.06, 0.06, 0.06, 0.95)
    popup:SetBackdropBorderColor(0, 0, 0, 1)

    -- Title text
    local title = popup:CreateFontString(nil, "OVERLAY")
    title:SetPoint("TOP", popup, "TOP", 0, -12)
    KE:ApplyFont(title, "Expressway", 15, "OUTLINE")
    title:SetText("Withdraw 1 Vantus Rune from Guild Bank?")
    popup.title = title

    -- Rune icon (centered between title and buttons)
    local runeIcon = popup:CreateTexture(nil, "ARTWORK")
    runeIcon:SetSize(36, 36)
    runeIcon:SetPoint("TOP", title, "BOTTOM", 0, -6)
    runeIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    -- Use first priority rune's icon
    local iconID = C_Item and C_Item.GetItemIconByID(RUNE_PRIORITY[1])
    if iconID then runeIcon:SetTexture(iconID) end
    popup.runeIcon = runeIcon

    -- Countdown bar
    local bar = CreateFrame("StatusBar", nil, popup)
    bar:SetSize(460, 10)
    bar:SetPoint("TOP", popup, "BOTTOM", 0, -2)
    bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    local accent = KE.Theme and KE.Theme.accent or { 1, 0, 0.549, 1 }
    bar:SetStatusBarColor(accent[1], accent[2], accent[3], 1)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(1)

    local barBg = bar:CreateTexture(nil, "BACKGROUND")
    barBg:SetAllPoints()
    barBg:SetColorTexture(0.06, 0.06, 0.06, 0.95)

    local barBorder = CreateFrame("Frame", nil, bar, "BackdropTemplate")
    barBorder:SetPoint("TOPLEFT", -1, 1)
    barBorder:SetPoint("BOTTOMRIGHT", 1, -1)
    barBorder:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    barBorder:SetBackdropBorderColor(0, 0, 0, 1)

    local barText = barBorder:CreateFontString(nil, "OVERLAY")
    barText:SetPoint("CENTER", bar, "CENTER", 0, 0)
    KE:ApplyFont(barText, "Expressway", 16, "OUTLINE")
    bar.text = barText

    popup.bar = bar

    -- Yes button
    local yesBtn = CreateFrame("Button", nil, popup, "BackdropTemplate")
    yesBtn:SetSize(120, 30)
    yesBtn:SetPoint("BOTTOM", popup, "BOTTOM", -70, 14)
    yesBtn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    yesBtn:SetBackdropColor(0.15, 0.15, 0.15, 1)
    yesBtn:SetBackdropBorderColor(0, 0, 0, 1)
    local yesTxt = yesBtn:CreateFontString(nil, "OVERLAY")
    yesTxt:SetPoint("CENTER")
    KE:ApplyFont(yesTxt, "Expressway", 14, "OUTLINE")
    yesTxt:SetText("Yes")
    yesTxt:SetTextColor(0.25, 0.75, 0.25)
    yesBtn:SetScript("OnEnter", function() yesBtn:SetBackdropColor(0.3, 0.3, 0.3, 1) end)
    yesBtn:SetScript("OnLeave", function() yesBtn:SetBackdropColor(0.15, 0.15, 0.15, 1) end)
    popup.yesBtn = yesBtn

    -- No button
    local noBtn = CreateFrame("Button", nil, popup, "BackdropTemplate")
    noBtn:SetSize(120, 30)
    noBtn:SetPoint("BOTTOM", popup, "BOTTOM", 70, 14)
    noBtn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    noBtn:SetBackdropColor(0.15, 0.15, 0.15, 1)
    noBtn:SetBackdropBorderColor(0, 0, 0, 1)
    local noTxt = noBtn:CreateFontString(nil, "OVERLAY")
    noTxt:SetPoint("CENTER")
    KE:ApplyFont(noTxt, "Expressway", 14, "OUTLINE")
    noTxt:SetText("No")
    noTxt:SetTextColor(1, 0.25, 0.25)
    noBtn:SetScript("OnEnter", function() noBtn:SetBackdropColor(0.3, 0.3, 0.3, 1) end)
    noBtn:SetScript("OnLeave", function() noBtn:SetBackdropColor(0.15, 0.15, 0.15, 1) end)
    popup.noBtn = noBtn

    -- Countdown OnUpdate
    popup:SetScript("OnUpdate", function()
        if not self.popupEndTime then return end
        local remaining = self.popupEndTime - GetTime()
        if remaining <= 0 then
            self:ClosePopup()
            if self.db.ShowChatMessages then
                KE:Print("|cffffff00Vantus Rune withdrawal timed out.|r")
            end
            return
        end
        local timeout = self.db.ConfirmationTimeout or 15
        popup.bar:SetMinMaxValues(0, timeout)
        popup.bar:SetValue(remaining)
        popup.bar.text:SetFormattedText("%.1f", remaining)
    end)

    popup:Hide()
    self.popup = popup
end

function VR:ShowConfirmation(guildTab, guildSlot, bagIndex, bagSlot)
    self:CreatePopup()

    local timeout = self.db.ConfirmationTimeout or 15
    self.popupEndTime = GetTime() + timeout
    self.popup.bar:SetMinMaxValues(0, timeout)
    self.popup.bar:SetValue(timeout)
    self.popup.bar.text:SetText(string_format("%.1f", timeout))

    self.popup.yesBtn:SetScript("OnClick", function()
        self:ClosePopup()
        self:WithdrawRune(guildTab, guildSlot, bagIndex, bagSlot)
    end)

    self.popup.noBtn:SetScript("OnClick", function()
        self:ClosePopup()
        if self.db.ShowChatMessages then
            KE:Print("|cffff4444Vantus Rune withdrawal cancelled.|r")
        end
    end)

    self.popup:SetAlpha(0)
    self.popup:Show()
    UIFrameFadeIn(self.popup, 0.2, 0, 1)
end

function VR:ClosePopup()
    self.popupEndTime = nil
    if self.popup then self.popup:Hide() end
end

---------------------------------------------------------------------------------
-- Guild Bank Button
---------------------------------------------------------------------------------
function VR:CreateGuildBankButton()
    if self.vantusButton then
        self.vantusButton:Show()
        return
    end

    local parent = _G.Baganator_SingleViewGuildViewFrameelvui or _G.GuildBankFrame
    if not parent then return end

    -- Match reference: parent to guild bank, use textures instead of BackdropTemplate
    local btn = CreateFrame("Button", "KE_VantusRuneButton", parent)
    btn:SetSize(BUTTON_WIDTH, BUTTON_HEIGHT)
    btn:SetPoint("TOPRIGHT", parent, "BOTTOMRIGHT", -1, -2)

    -- Background texture (not backdrop — avoids ElvUI skinning/clipping issues)
    btn.bg = btn:CreateTexture(nil, "BACKGROUND")
    btn.bg:SetAllPoints()
    btn.bg:SetColorTexture(0.06, 0.06, 0.06, 0.95)

    -- Highlight texture
    btn.hl = btn:CreateTexture(nil, "HIGHLIGHT")
    btn.hl:SetAllPoints()
    btn.hl:SetColorTexture(1, 1, 1, 0.15)

    -- Border frame
    btn.border = CreateFrame("Frame", nil, btn, "BackdropTemplate")
    btn.border:SetPoint("TOPLEFT", -1, 1)
    btn.border:SetPoint("BOTTOMRIGHT", 1, -1)
    btn.border:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    btn.border:SetBackdropBorderColor(0, 0, 0, 1)

    -- Text
    local accent = KE.Theme and KE.Theme.accent or { 1, 0, 0.549, 1 }
    btn.text = btn:CreateFontString(nil, "ARTWORK")
    btn.text:SetPoint("CENTER")
    KE:ApplyFont(btn.text, "Expressway", 15, "OUTLINE")
    btn.text:SetText("Vantus Rune")
    btn.text:SetTextColor(accent[1], accent[2], accent[3], 1)

    btn:SetScript("OnClick", function() self:StartWithdrawal() end)
    btn:SetScript("OnEnter", function()
        btn.bg:SetColorTexture(0.2, 0.2, 0.2, 1)
        GameTooltip:SetOwner(btn, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Click to withdraw 1 Vantus Rune")
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function()
        btn.bg:SetColorTexture(0.06, 0.06, 0.06, 0.95)
        GameTooltip_Hide()
    end)

    btn:Show()
    self.vantusButton = btn
end

---------------------------------------------------------------------------------
-- Event Handlers
---------------------------------------------------------------------------------
---------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------
function VR:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

function VR:GetGuildBankParent()
    return _G.Baganator_SingleViewGuildViewFrameelvui or _G.GuildBankFrame
end

function VR:OnEnable()
    if not self.db.Enabled then return end

    -- Try to create button immediately if parent frame exists
    local parent = self:GetGuildBankParent()
    if parent then
        self:CreateGuildBankButton()
    end

    -- Hook parent OnShow to create/show button when guild bank opens.
    -- Frames may be load-on-demand, so poll via ADDON_LOADED if needed.
    if not self._hooked then
        local function TryHook()
            local gbf = self:GetGuildBankParent()
            if gbf and not self._hooked then
                gbf:HookScript("OnShow", function()
                    if self.db and self.db.Enabled then
                        self:CreateGuildBankButton()
                    end
                end)
                self._hooked = true
                self:CreateGuildBankButton()
            end
        end

        if parent then
            TryHook()
        else
            -- Wait for the frame to be created
            if not self.eventFrame then
                self.eventFrame = CreateFrame("Frame")
            end
            self.eventFrame:RegisterEvent("ADDON_LOADED")
            self.eventFrame:SetScript("OnEvent", function()
                if self:GetGuildBankParent() then
                    TryHook()
                    self.eventFrame:UnregisterEvent("ADDON_LOADED")
                end
            end)
        end
    end
end

function VR:OnDisable()
    if self.eventFrame then
        self.eventFrame:UnregisterAllEvents()
    end
    self:UnregisterAllEvents()
    self:ClosePopup()
    if self.vantusButton then self.vantusButton:Hide() end
end
