-- ╔══════════════════════════════════════════════════════════╗
-- ║  CopyAnything.lua                                        ║
-- ║  Module: Copy Anything                                   ║
-- ║  Purpose: Hover a tooltip, press the copy key, and get a ║
-- ║           small window with its spell/item/NPC ID ready  ║
-- ║           to copy.                                       ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

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
local tonumber = tonumber
local tostring = tostring
local CreateFrame = CreateFrame
local type = type
local InCombatLockdown = InCombatLockdown
local C_AddOns = C_AddOns
local C_ActionBar = C_ActionBar

---------------------------------------------------------------------------------
-- DB Helper
---------------------------------------------------------------------------------
function CA:UpdateDB()
    self.db = KE.db.profile.CopyAnything
end

---------------------------------------------------------------------------------
-- Core Logic
---------------------------------------------------------------------------------

-- Shows the copy dialog with the given spell/item/NPC ID and name.
local function ShowCopyDialog(name, id)
    -- The hint always names Ctrl-C, never db.Modifier/db.Key: those two settings
    -- only gate the TOOLTIP-HOVER trigger that opens this window, not a binding
    -- inside it, and the dialog's own copy handler is hardcoded to Ctrl+C.
    -- Naming the configured key here would send a user on e.g. Shift+V into
    -- overwriting the highlighted id with the letter V instead of copying it.
    local hint = "Press " .. KE:ColorTextByTheme("Ctrl-C") .. " to copy"
    -- cancelText ("Close") is the opt-in Core/Widgets.lua reads to show a single
    -- Close button and swap this prompt's title and edit-box colours -- see
    -- CreatePrompt's isCopyPrompt flag.
    KE:CreatePrompt(name or "Copy", tostring(id), true, hint, false, nil, nil, nil, nil, nil, nil, nil, "Close")
end

-- Checks the configured modifier key(s) against the keyboard state.
local function CheckModifiers(mod)
    if not mod then return true end

    -- If mod is a string, convert it to a table
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

-- Copy logic with secret-value checks.
function CA:TryCopy(key)
    -- Fast early-exit BEFORE doing any tooltip work or string upper-casing.
    -- OnKeyDown fires on every single keystroke, so this path stays cheap
    -- when the user isn't actively trying to copy.
    local db = self.db
    if not db or not db.Key or not db.Modifier then return end
    if not CheckModifiers(db.Modifier) then return end
    if key ~= strupper(db.Key) then return end

    if C_ChallengeMode.IsChallengeModeActive() or InCombatLockdown() then return end

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
            -- GameTooltipDataMixin:GetItem() returns (name, hyperlink, id) --
            -- three values, per .wow-api-reference Blizzard_GameTooltip/
            -- Mainline/GameTooltip.lua delegating to
            -- Blizzard_SharedXMLGame/Tooltip/TooltipUtil.lua. The bundled
            -- type-checker DB models only two, a known DB gap.
            ---@diagnostic disable-next-line
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
            -- GameTooltipDataMixin:GetUnit() returns (name, unit, guid) --
            -- three values, per .wow-api-reference Blizzard_GameTooltip/
            -- Mainline/GameTooltip.lua delegating to
            -- Blizzard_SharedXMLGame/Tooltip/TooltipUtil.lua. The
            -- bundled type-checker DB models only two, a known DB gap.
            ---@diagnostic disable-next-line
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
                if GameTooltip:IsTooltipType(7) then -- Aura
                    local aura = C_Spell.GetSpellInfo(data.id)
                    if aura then
                        copyId = data.id
                        copyName = aura.name
                    end
                end

                -- Try hyperlink field (contains "spell:12345" or "item:12345")
                if not copyId and data.hyperlink then
                    local hyperlink = tostring(data.hyperlink)
                    local spellId = tonumber(hyperlink:match("spell:(%d+)"))
                    if spellId then
                        local spellInfo = C_Spell.GetSpellInfo(spellId)
                        if spellInfo then
                            copyId = spellId
                            copyName = spellInfo.name
                        end
                    end
                    if not copyId then
                        local itemId = tonumber(hyperlink:match("item:(%d+)"))
                        if itemId then
                            local itemName = C_Item.GetItemInfo(itemId)
                            copyId = itemId
                            copyName = itemName or "Item"
                        end
                    end
                end

                -- Try resolving first tooltip line as a spell name
                if not copyId and data.lines and data.lines[1] then
                    local firstLine = data.lines[1].leftText
                    if firstLine and not issecretvalue(firstLine) and #firstLine > 0 then
                        local spellInfo = C_Spell.GetSpellInfo(firstLine)
                        if spellInfo and spellInfo.spellID then
                            copyId = spellInfo.spellID
                            copyName = spellInfo.name
                        end
                    end
                end
            end
        end
    end

    -- ElvUI SpellBook Tooltip
    local addonName = "ElvUI"
    if C_AddOns.IsAddOnLoaded(addonName) then
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
                local macroName = C_ActionBar.GetActionText(actionSlot)

                if macroName then
                    local macroSlot = GetMacroIndexByName(macroName)

                    local spellId = GetMacroSpell(macroSlot)
                    -- GetMacroItem is missing from .luacheckrc's macro globals
                    -- (see the reachable-at-call-time note above); reach it
                    -- through _G rather than widening the allowlist.
                    local _, itemLink = _G.GetMacroItem(macroSlot)

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
        ShowCopyDialog(copyName, copyId)
    end
end

function CA:ApplySettings()
    CA:UpdateDB()
end

---------------------------------------------------------------------------------
-- Listener Lifecycle
---------------------------------------------------------------------------------
-- KE_CopyFrame only ever listens for keyboard input while a tooltip it cares
-- about is on screen: armed on tooltip OnShow, disarmed on OnHide, and hard
-- disarmed on PLAYER_REGEN_DISABLED. A permanently-listening keyboard frame
-- would run this module's insecure Lua on every single keystroke, and with
-- SetPropagateKeyboardInput(true) that keystroke then reaches the secure
-- binding system while KE's code is still on the call stack -- tainting
-- whatever the keybind triggers next (a quest-item cast refusing to fire is
-- the observed failure mode). Never widen this to a permanent listener.
function CA:SetListening(on)
    local f = self.frame
    if not f then return end
    if on and not InCombatLockdown() then
        if not f.keListening then
            f.keListening = true
            f:EnableKeyboard(true)
            f:Show()
        end
    elseif f.keListening then
        f.keListening = nil
        -- Hide is what stops the listening, and it is the only thing that can:
        -- the combat entry path reaches here in lockdown, where EnableKeyboard
        -- is protected and throws. A hidden frame runs no OnKeyDown, so the
        -- taint window closes either way.
        f:Hide()
        if not InCombatLockdown() then f:EnableKeyboard(false) end
    end
end

function CA:InstallListener()
    if self.frame then return end
    local f = CreateFrame("Frame", "KE_CopyFrame")
    f:EnableKeyboard(false)
    f:SetPropagateKeyboardInput(true)
    f:SetScript("OnKeyDown", function(_, key)
        self:TryCopy(key)
    end)
    self.frame = f

    local function arm() if self:IsEnabled() then self:SetListening(true) end end
    local function disarm() self:SetListening(false) end
    for _, tt in ipairs({ _G.GameTooltip, _G.ItemRefTooltip, _G.ElvUI_SpellBookTooltip }) do
        if tt and tt.HookScript then
            tt:HookScript("OnShow", arm)
            tt:HookScript("OnHide", disarm)
        end
    end

    -- Never listen in combat: the copy is refused there anyway, and a
    -- tooltip left open across a pull would re-open the taint window.
    local combat = CreateFrame("Frame")
    combat:RegisterEvent("PLAYER_REGEN_DISABLED")
    combat:SetScript("OnEvent", function() disarm() end)
end

---------------------------------------------------------------------------------
-- Module Lifecycle
---------------------------------------------------------------------------------
function CA:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

function CA:OnEnable()
    if not self.db.Enabled then return end
    self:InstallListener()
    -- Armed by tooltip OnShow, not here -- a tooltip already up at login
    -- arms on its next show.
end

function CA:OnDisable()
    self:SetListening(false)
end
