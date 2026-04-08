-- ╔══════════════════════════════════════════════════════════╗
-- ║  AuctionHouseFilter.lua                                  ║
-- ║  Module: Auction House Filter                            ║
-- ║  Purpose: Auto-filter AH to current expansion, auto-     ║
-- ║           focus search bar, craft orders filter.         ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class AuctionHouseFilter: AceModule, AceEvent-3.0
local AHF = KitnEssentials:NewModule("AuctionHouseFilter", "AceEvent-3.0")

local C_Timer = C_Timer

---------------------------------------------------------------------------------
-- DB Helper
---------------------------------------------------------------------------------
function AHF:UpdateDB()
    self.db = KE.db.profile.AuctionHouseFilter
end

function AHF:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

---------------------------------------------------------------------------------
-- Core Logic
---------------------------------------------------------------------------------
function AHF:ApplyAuctionHouseFilter()
    if not self.db.Enabled then return end
    C_Timer.After(0, function()
        if self.db.AuctionHouse.CurrentExpansion then
            local frame = AuctionHouseFrame
            if frame and frame.SearchBar and frame.SearchBar.FilterButton then
                local filterButton = frame.SearchBar.FilterButton
                if filterButton.filters then
                    filterButton.filters[Enum.AuctionHouseFilter.CurrentExpansionOnly] = true
                end
            end
        end

        if self.db.AuctionHouse.FocusSearchBar then
            local frame = AuctionHouseFrame
            if frame and frame.SearchBar and frame.SearchBar.SearchBox then
                frame.SearchBar.SearchBox:SetFocus()
            end
        end
    end)
end

function AHF:ApplyCraftOrdersFilter()
    if not self.db.Enabled then return end
    C_Timer.After(0, function()
        if self.db.CraftOrders.CurrentExpansion then
            local frame = ProfessionsCustomerOrdersFrame
            if frame and frame.BrowseOrders and frame.BrowseOrders.SearchBar then
                local filterDropdown = frame.BrowseOrders.SearchBar.FilterDropdown
                if filterDropdown and filterDropdown.filters then
                    filterDropdown.filters[Enum.AuctionHouseFilter.CurrentExpansionOnly] = true
                end
            end
        end

        if self.db.CraftOrders.FocusSearchBar then
            local frame = ProfessionsCustomerOrdersFrame
            if frame and frame.BrowseOrders and frame.BrowseOrders.SearchBar and frame.BrowseOrders.SearchBar.SearchBox then
                frame.BrowseOrders.SearchBar.SearchBox:SetFocus()
            end
        end
    end)
end

---------------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------------
function AHF:ApplySettings()
end

---------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------
function AHF:OnEnable()
    if not self.db.Enabled then return end
    self:RegisterEvent("AUCTION_HOUSE_SHOW", "ApplyAuctionHouseFilter")
    self:RegisterEvent("CRAFTINGORDERS_SHOW_CUSTOMER", "ApplyCraftOrdersFilter")
end

function AHF:OnDisable()
    self:UnregisterAllEvents()
end
