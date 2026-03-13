-- KitnEssentials namespace
---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

-- Credit: Built on original WA code created by Nnoggie

---@class CopyAnything: AceModule, AceEvent-3.0
local CA = KitnEssentials:NewModule("CopyAnything", "AceEvent-3.0")

local IsControlKeyDown = IsControlKeyDown
local IsShiftKeyDown = IsShiftKeyDown
local IsAltKeyDown = IsAltKeyDown
local select = select
local strsplit = strsplit
local strupper = strupper
local issecretvalue = issecretvalue
local GetMacroIndexByName = GetMacroIndexByName
local GetMacroSpell = GetMacroSpell
local GetMacroItem = GetMacroItem
local tonumber = tonumber
local tostring = tostring
local CreateFrame = CreateFrame
local type = type
local InCombatLockdown = InCombatLockdown
local C_AddOns = C_AddOns
local StaticPopupDialogs = StaticPopupDialogs

function CA:UpdateDB()
    self.db = KE.db.profile.CopyAnything
end

function CA:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

--------------------------------------------------------------------------------
-- Static Popup
--------------------------------------------------------------------------------
local DIALOG_NAME = "KE_COPY_ANY_ID_DIALOG"
local popupInitialized = false

local function CreatePopup()
    if popupInitialized then return end
    StaticPopupDialogs[DIALOG_NAME] = {
        text = "CTRL-C to copy %s",
        button1 = CLOSE,
        OnShow = function(dialog, data)
            local function HidePopup() dialog:Hide() end
            dialog.EditBox:SetScript("OnEscapePressed", HidePopup)
            dialog.EditBox:SetScript("OnEnterPressed", HidePopup)
            dialog.EditBox:SetScript("OnKeyUp", function(_, key)
                if IsControlKeyDown() and key == "C" then
                    HidePopup()
                end
            end)
            dialog.EditBox:SetMaxLetters(0)
            dialog.EditBox:SetText(data)
            dialog.EditBox:HighlightText()
        end,
        hasEditBox = true,
        EditBoxWidth = 240,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
    popupInitialized = true
end

--------------------------------------------------------------------------------
-- Modifier check
--------------------------------------------------------------------------------
local function CheckModifiers(mod)
    if not mod then return true end
    if type(mod) == "string" then
        local t = {}
        mod = mod:lower()
        if mod:find("ctrl") then t.ctrl = true end
        if mod:find("shift") then t.shift = true end
        if mod:find("alt") then t.alt = true end
        mod = t
    end
    if mod.shift and not IsShiftKeyDown() then return false end
    if mod.ctrl and not IsControlKeyDown() then return false end
    if mod.alt and not IsAltKeyDown() then return false end
    return true
end

local function GetNPCIDFromGUID(guid)
    if not guid then return end
    return select(6, strsplit("-", guid))
end

--------------------------------------------------------------------------------
-- Copy logic
--------------------------------------------------------------------------------
function CA:TryCopy(key)
    if C_ChallengeMode.IsChallengeModeActive() or InCombatLockdown() then return end
    local db = self.db
    if not db or not db.key or not db.mod then return end
    if key ~= strupper(db.key) then return end
    if not CheckModifiers(db.mod) then return end

    local copyId, copyName

    -- Spell
    if not issecretvalue(GameTooltip:GetSpell()) then
        local spellName, spellId = GameTooltip:GetSpell()
        if spellId then
            copyId = spellId
            copyName = spellName
        end
    end

    -- Item
    if not issecretvalue(GameTooltip:GetItem()) then
        if not copyId then
            local itemName, _, itemId = GameTooltip:GetItem()
            if itemId then
                copyId = itemId
                copyName = itemName
            end
        end
    end

    -- Unit / NPC / Player
    if not issecretvalue(GameTooltip:GetUnit()) then
        if not copyId then
            local unitName, _, unitGUID = GameTooltip:GetUnit()
            local npcId = GetNPCIDFromGUID(unitGUID)
            if npcId then
                copyId = npcId
                copyName = unitName
            elseif unitName then
                copyId = unitName
                copyName = "Player Name"
            end
        end
    end

    -- Aura / Other tooltip data
    if not issecretvalue(GameTooltip:GetTooltipData()) then
        if not copyId then
            local data = GameTooltip:GetTooltipData()
            if data then
                if GameTooltip:IsTooltipType(7) then
                    local aura = C_Spell.GetSpellInfo(data.id)
                    if aura then
                        copyId = data.id
                        copyName = aura.name
                    end
                else
                    copyId = data.id
                    copyName = "Other"
                end
            end
        end
    end

    -- ElvUI SpellBook Tooltip
    if C_AddOns.IsAddOnLoaded("ElvUI") then
        if not issecretvalue(ElvUI_SpellBookTooltip) then
            if not copyId and ElvUI_SpellBookTooltip then
                local data = ElvUI_SpellBookTooltip:GetTooltipData()
                if data and ElvUI_SpellBookTooltip:IsTooltipType(1) then
                    copyId = data.id
                    copyName = ElvUI_SpellBookTooltip.TextLeft1:GetText()
                end
            end
        end
    end

    -- Macro handling
    if not issecretvalue(GameTooltip:IsTooltipType()) then
        if not copyId and GameTooltip:IsTooltipType(25) then
            local info = GameTooltip:GetPrimaryTooltipInfo()
            if info and info.getterArgs then
                local actionSlot = info.getterArgs[1]
                local macroName = GetActionText(actionSlot)
                if macroName then
                    local macroSlot = GetMacroIndexByName(macroName)
                    local spellId = GetMacroSpell(macroSlot)
                    local _, itemLink = GetMacroItem(macroSlot)
                    if spellId then
                        local spellInfo = C_Spell.GetSpellInfo(spellId)
                        if spellInfo then
                            copyId = spellId
                            copyName = spellInfo.name
                        end
                    elseif itemLink then
                        local itemId = tonumber(itemLink:match("item:(%d+)"))
                        if itemId then
                            local itemName = C_Item.GetItemInfo(itemId)
                            if itemName then
                                copyId = itemId
                                copyName = itemName
                            end
                        end
                    end
                end
            end
        end
    end

    if copyId then
        StaticPopup_Show(DIALOG_NAME, copyName, nil, tostring(copyId))
    end
end

function CA:ApplySettings()
    self:UpdateDB()
end

function CA:OnEnable()
    if not self.db.Enabled then return end
    CreatePopup()
    if not self.frame then
        self.frame = CreateFrame("Frame", "KE_CopyFrame")
        self.frame:SetPropagateKeyboardInput(true)
        self.frame:SetScript("OnKeyDown", function(_, key)
            CA:TryCopy(key)
        end)
    end
    self.frame:EnableKeyboard(true)
end

function CA:OnDisable()
    if self.frame then
        self.frame:EnableKeyboard(false)
    end
end
