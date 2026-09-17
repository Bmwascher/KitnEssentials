-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-SpecPicker.lua                                      ║
-- ║  Purpose: Shared specialization controls — a spec header ║
-- ║           row, the live spec id, the playable class/spec ║
-- ║           map, and a class picker that opens on the      ║
-- ║           player's own class.                            ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

local CreateFrame = CreateFrame
local C_Timer = C_Timer
local UnitClass = UnitClass
local GetNumClasses = GetNumClasses
local GetSpecializationInfoForClassID = GetSpecializationInfoForClassID
local GetSpecialization = C_SpecializationInfo.GetSpecialization
local GetSpecializationInfo = C_SpecializationInfo.GetSpecializationInfo
local GetNumSpecializationsForClassID = C_SpecializationInfo.GetNumSpecializationsForClassID
local table_sort = table.sort
local ipairs = ipairs
local next = next
local type = type

---------------------------------------------------------------------------------
-- Spec header
---------------------------------------------------------------------------------
-- Icon plus name, drawn above a spec's controls so a card of near identical
-- rows reads as a list of specs rather than a wall of checkboxes.
function GUIFrame:CreateSpecHeaderRow(parent, labelText, config)
    if type(config) ~= "table" then config = {} end

    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(26)

    local border = row:CreateTexture(nil, "BACKGROUND")
    border:SetSize(20, 20)
    border:SetPoint("LEFT", row, "LEFT", 0, 0)
    border:SetColorTexture(0, 0, 0, 1)

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(18, 18)
    icon:SetPoint("CENTER", border, "CENTER")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    if config.icon then icon:SetTexture(config.icon) else border:Hide() end

    local text = labelText or ""
    if config.current then
        text = text .. "  " .. KE:ColorTextByTheme("(current)")
    end

    local fs = row:CreateFontString(nil, "OVERLAY")
    fs:SetPoint("LEFT", border, "RIGHT", 6, 0)
    fs:SetJustifyH("LEFT")
    KE:ApplyThemeFont(fs, "large")
    fs:SetText(text)
    fs:SetTextColor(Theme.textSecondary[1], Theme.textSecondary[2], Theme.textSecondary[3], 1)

    return row
end

---------------------------------------------------------------------------------
-- Spec and class data
---------------------------------------------------------------------------------
function GUIFrame.GetCurrentSpecID()
    if not GetSpecialization then return nil end
    local index = GetSpecialization()
    if not index or index == 0 then return nil end
    return GetSpecializationInfo and GetSpecializationInfo(index)
end

local classSpecs

-- Class token -> spec ids, for every playable class. Built on first use and
-- cached for the session: the data is static, and the callers rebuild their
-- whole page on every tick. An empty read is never cached, so a call that
-- lands before the client can answer does not poison the cache.
--
-- Counted with GetNumSpecializationsForClassID rather than a fixed 1-4 loop,
-- which silently truncates a class that gains a fifth spec.
function GUIFrame.GetClassSpecs()
    if classSpecs then return classSpecs end

    local out = {}
    local numClasses = GetNumClasses and GetNumClasses() or 0
    for classID = 1, numClasses do
        local info = C_CreatureInfo and C_CreatureInfo.GetClassInfo(classID)
        local token = info and info.classFile
        if token then
            local specs = {}
            local count = GetNumSpecializationsForClassID and GetNumSpecializationsForClassID(classID) or 0
            for index = 1, count do
                local specID = GetSpecializationInfoForClassID and GetSpecializationInfoForClassID(classID, index)
                if specID then specs[#specs + 1] = specID end
            end
            if #specs > 0 then out[token] = specs end
        end
    end

    if next(out) == nil then return out end
    classSpecs = out
    return classSpecs
end

---------------------------------------------------------------------------------
-- Class picker
---------------------------------------------------------------------------------
-- The picked class lives for one visit to one page, never in the profile. A
-- stored pick outlives its usefulness: the page then opens on whatever class was
-- inspected last, which is rarely the one the player is on.
local sessionClass = {}

local function ResetSessionClass()
    -- Nothing picked means nothing to undraw. Closing the window fires this on
    -- every page, so an unconditional body would mark content dirty for players
    -- who never open a picker and cost them a page rebuild on every open.
    if next(sessionClass) == nil then return end
    sessionClass = {}
    -- Clearing the pick is not enough on the way out. A page that has already
    -- been drawn stays drawn while the window is shut, and reopening replays a
    -- refresh only for content marked dirty, so the reopened page would still
    -- show the class picked last time. Marked only while hidden: a sidebar
    -- switch is already rebuilding, and setting it there would buy one
    -- redundant refresh on the next open.
    if not GUIFrame:IsShown() then
        GUIFrame._contentDirtyWhileHidden = true
    end
end

-- Fires on a real sidebar item switch and on window close, but not on the
-- in-place rebuild the dropdown's own callback triggers, so the pick survives it.
GUIFrame:RegisterContentCleanup("SpecPickerClass", ResetSessionClass)

function GUIFrame.ResolvePickerClass(sessionToken, playerToken, tokens)
    local valid = {}
    for _, token in ipairs(tokens) do valid[token] = true end
    if sessionToken and valid[sessionToken] then return sessionToken end
    if playerToken and valid[playerToken] then return playerToken end
    return tokens[1]
end

-- Config: { scope, classTokens, label }. Returns the row and the class token the
-- caller should draw, so the caller never reads the picker's state itself.
function GUIFrame:CreateClassPickerRow(parent, config)
    if type(config) ~= "table" then config = {} end

    local scope = config.scope or "default"
    local tokens = {}
    for _, token in ipairs(config.classTokens or {}) do tokens[#tokens + 1] = token end
    table_sort(tokens)

    local _, playerClass = UnitClass("player")
    local shownClass = GUIFrame.ResolvePickerClass(sessionClass[scope], playerClass, tokens)

    local options = {}
    for _, token in ipairs(tokens) do
        local label = (_G.LOCALIZED_CLASS_NAMES_MALE and _G.LOCALIZED_CLASS_NAMES_MALE[token]) or token
        if token == playerClass then label = label .. "  " .. KE:ColorTextByTheme("(current)") end
        options[#options + 1] = { key = token, text = label }
    end
    table_sort(options, function(a, b) return a.text < b.text end)

    local row = GUIFrame:CreateRow(parent, 36)
    local dropdown
    dropdown = GUIFrame:CreateDropdown(row, config.label or "Class", {
        options = options,
        value = shownClass,
        callback = function(key)
            sessionClass[scope] = key
            -- Close the list instantly, THEN rebuild a frame later: the animated
            -- close was still running when the rebuild hit, and the orphaned list
            -- frame flashed at the bottom of the screen.
            if dropdown and dropdown._closeDropdown then
                dropdown._closeDropdown(true)
            end
            C_Timer.After(0, function() GUIFrame:RefreshContent() end)
        end,
    })
    row:AddWidget(dropdown, 1)

    return row, shownClass
end
