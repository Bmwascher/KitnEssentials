-- ╔══════════════════════════════════════════════════════════╗
-- ║  MerchantPages.lua                                       ║
-- ║  Module: Merchant Pages                                  ║
-- ║  Purpose: Show several vendor pages at once instead      ║
-- ║  of flipping through them one page at a time.            ║
-- ║                                                          ║
-- ║  TAINT NOTE: raising MERCHANT_ITEMS_PER_PAGE and         ║
-- ║  creating Blizzard-named MerchantItem<N> frames means    ║
-- ║  merchant code runs tainted. The upstream project        ║
-- ║  shipped this disabled for that reason; it ships         ║
-- ║  enabled here on an explicit ruling, default OFF. If     ║
-- ║  a tooltip stops working after a vendor visit, or an     ║
-- ║  "attempt to perform arithmetic on a secret number       ║
-- ║  value" error appears, suspect this module first.        ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class MerchantPages: AceModule
local MP = KitnEssentials:NewModule("MerchantPages")

local _G = _G
local floor = math.floor
local pairs = pairs
local next = next
local CreateFrame = CreateFrame
local hooksecurefunc = hooksecurefunc
local C_AddOns = C_AddOns

local BLIZZ_PER_PAGE = 10
local BLIZZ_BUYBACK_PER_PAGE = 12

-- KE.Skins is read LAZILY, never hoisted into a file-scope local: this file
-- lives in Modules/QoL/, which loads BEFORE Modules/Skinning/
-- (KitnEssentials.toc), so a file-scope capture of KE.Skins would be nil.
local function GetS() return KE.Skins end

---------------------------------------------------------------------------------
-- DB Helper
---------------------------------------------------------------------------------
function MP:UpdateDB()
    self.db = KE.db.profile.MerchantPages
end

function MP:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

---------------------------------------------------------------------------------
-- Row Skinning
---------------------------------------------------------------------------------
function MP:SkinNewRow(i)
    local S = GetS()
    local item = _G["MerchantItem" .. i]
    if not (S and item) then return end
    item:SetSize(155, 45)
    S.StripTextures(item)
    S.Backdrop(item)
    local slot = _G["MerchantItem" .. i .. "SlotTexture"]
    if slot and slot.SetAlpha then slot:SetAlpha(0) end
    if item.Name and slot then
        item.Name:SetPoint("LEFT", slot, "RIGHT", -5, 5)
        item.Name:SetSize(110, 30)
    end
    local button = _G["MerchantItem" .. i .. "ItemButton"]
    if button then
        S.ItemButton(button)
        button:SetPoint("TOPLEFT", item, "TOPLEFT", 4, -4)
    end
end

---------------------------------------------------------------------------------
-- Layout (Blizzard update-loop hooks)
---------------------------------------------------------------------------------
local function LayoutMerchant()
    if not (MP:IsEnabled() and MP.db and MP.db.Enabled) then return end
    for i = 1, _G.MERCHANT_ITEMS_PER_PAGE do
        local button = _G["MerchantItem" .. i]
        if not button then break end
        button:Show()
        button:ClearAllPoints()
        if (i % BLIZZ_PER_PAGE) == 1 then
            if i == 1 then
                button:SetPoint("TOPLEFT", _G.MerchantFrame, "TOPLEFT", 11, -69)
            else
                button:SetPoint("TOPLEFT", _G["MerchantItem" .. (i - (BLIZZ_PER_PAGE - 1))], "TOPRIGHT", 12, 0)
            end
        else
            if (i % 2) == 1 then
                button:SetPoint("TOPLEFT", _G["MerchantItem" .. (i - 2)], "BOTTOMLEFT", 0, -8)
            else
                button:SetPoint("TOPLEFT", _G["MerchantItem" .. (i - 1)], "TOPRIGHT", 12, 0)
            end
        end
    end
end

local function LayoutBuyback()
    if not (MP:IsEnabled() and MP.db and MP.db.Enabled) then return end
    local numBuyback = _G.GetNumBuybackItems and _G.GetNumBuybackItems() or 0
    for i = BLIZZ_BUYBACK_PER_PAGE + 1, _G.MERCHANT_ITEMS_PER_PAGE do
        local button = _G["MerchantItem" .. i]
        if not button then break end
        button:ClearAllPoints()
        if i <= numBuyback then
            local row = floor((i - 1) / 3)
            local col = (i - 1) % 3
            if row == 0 then
                if col == 0 then
                    button:SetPoint("TOPLEFT", _G.MerchantItem1, "TOPLEFT", 0, -60)
                else
                    button:SetPoint("TOPLEFT", _G["MerchantItem" .. (i - 1)], "TOPRIGHT", 12, 0)
                end
            else
                if col == 0 then
                    button:SetPoint("TOPLEFT", _G["MerchantItem" .. (i - 3)], "BOTTOMLEFT", 0, -15)
                else
                    button:SetPoint("TOPLEFT", _G["MerchantItem" .. (i - 1)], "TOPRIGHT", 12, 0)
                end
            end
            button:Show()
        else
            button:Hide()
        end
    end
end

---------------------------------------------------------------------------------
-- Setup
---------------------------------------------------------------------------------
function MP:Setup()
    if self.initialized then return end
    -- Defer to dedicated vendor addons.
    for _, addon in pairs({ "ExtVendor", "Krowi_ExtendedVendorUI", "CompactVendor" }) do
        if C_AddOns.IsAddOnLoaded(addon) then return end
    end
    local pages = self.db.Pages or 2
    self.initialized = true

    -- ORDER MATTERS: create every frame FIRST, and only then raise the
    -- item-count global. If anything below fails, Blizzard's update loop
    -- must never see a count larger than the frames that exist -- styling
    -- failing mid-setup AFTER the count was raised is the crash this
    -- ordering prevents.
    local target = pages * BLIZZ_PER_PAGE
    local created = {}
    for i = 1, target do
        if not _G["MerchantItem" .. i] then
            CreateFrame("Frame", "MerchantItem" .. i, _G.MerchantFrame, "MerchantItemTemplate")
            created[#created + 1] = i
            local alt = _G["MerchantItem" .. i .. "AltCurrencyFrame"]
            if alt then alt:Hide() end
        end
    end
    _G.MERCHANT_ITEMS_PER_PAGE = target
    _G.MerchantFrame:SetWidth(30 + pages * 330)
    for _, i in next, created do
        self:SkinNewRow(i)
    end

    if _G.MerchantBuyBackItem and _G.MerchantItem10 then
        _G.MerchantBuyBackItem:ClearAllPoints()
        _G.MerchantBuyBackItem:SetPoint("TOPLEFT", _G.MerchantItem10, "BOTTOMLEFT", 30, -53)
    end

    local buttonOffset = 25 + ((pages - 1) * 165)
    if _G.MerchantPrevPageButton then
        _G.MerchantPrevPageButton:ClearAllPoints()
        _G.MerchantPrevPageButton:SetPoint("CENTER", _G.MerchantFrame, "BOTTOMLEFT", buttonOffset, 93)
    end
    local S = GetS()
    if _G.MerchantPageText and S then
        S.SetFont(_G.MerchantPageText)
        _G.MerchantPageText:ClearAllPoints()
        _G.MerchantPageText:SetPoint("BOTTOM", _G.MerchantFrame, "BOTTOM", 0, 86)
    end
    if _G.MerchantNextPageButton then
        _G.MerchantNextPageButton:ClearAllPoints()
        _G.MerchantNextPageButton:SetPoint("CENTER", _G.MerchantFrame, "BOTTOMRIGHT", -buttonOffset, 93)
    end

    hooksecurefunc("MerchantFrame_UpdateMerchantInfo", LayoutMerchant)
    hooksecurefunc("MerchantFrame_UpdateBuybackInfo", LayoutBuyback)
end

---------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------
function MP:OnEnable()
    self:UpdateDB()
    if not (self.db and self.db.Enabled) then return end
    if _G.MerchantFrame then self:Setup() end
end

-- No OnDisable: the MERCHANT_ITEMS_PER_PAGE global write, the created
-- Blizzard-named MerchantItem<N> frames, and the hooksecurefunc hooks
-- cannot be undone (see the header taint note). Turning the module off in
-- the GUI leaves them installed but inert-guarded by the db.Enabled check
-- inside LayoutMerchant/LayoutBuyback, which is why the GUI page requires
-- a reload to fully hand the window back to Blizzard.

function MP:ApplySettings()
    self:UpdateDB()
end
