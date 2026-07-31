-- ╔══════════════════════════════════════════════════════════╗
-- ║  LFGReminder.lua                                         ║
-- ║  Module: LFG Reminder                                    ║
-- ║  Purpose: When you join a Group Finder group for a       ║
-- ║           dungeon with a known teleport, show a small    ║
-- ║           popup with the dungeon name and a one-click    ║
-- ║           teleport button. Hides on entering the         ║
-- ║           dungeon, leaving the group, or entering        ║
-- ║           combat.                                        ║
-- ║                                                          ║
-- ║  Taint / secret-value safety -- critical, read before    ║
-- ║  editing:                                                ║
-- ║    * The teleport spellID fed to SetAttribute("spell")   ║
-- ║      is ALWAYS a static integer from our own name->spell ║
-- ║      table, never an LFG field.                          ║
-- ║    * The dungeon resolves on LFG_LIST_JOINED_GROUP,      ║
-- ║      where the search result is readable (browse/apply-  ║
-- ║      phase secrecy is lifted once joined). Every field   ║
-- ║      is still issecretvalue-guarded and the whole lookup ║
-- ║      pcall'd: a secret can only skip the prompt, never   ║
-- ║      error. The dungeon name is only ever SetText'd,     ║
-- ║      which accepts secrets.                              ║
-- ║    * The secure button is created ONCE and ALWAYS out of ║
-- ║      combat: normally at enable, else on the next        ║
-- ║      PLAYER_REGEN_ENABLED. NOTHING may call BuildPopup   ║
-- ║      during combat -- it writes SetAttribute("type",     ║
-- ║      "spell") on a protected frame. Only the "spell"     ║
-- ║      attribute is rewritten later, also only out of      ║
-- ║      combat (deferred when a join lands mid-combat).     ║
-- ║    * No Blizzard Group Finder frame is ever hooked or    ║
-- ║      SetScript-ed.                                       ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class LFGReminder: AceModule, AceEvent-3.0
local LR = KitnEssentials:NewModule("LFGReminder", "AceEvent-3.0")

local type = type
local pcall = pcall
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local IsPlayerSpell = IsPlayerSpell
local IsInGroup = IsInGroup
local IsInInstance = IsInInstance
local UIParent = UIParent
local C_Spell = C_Spell
-- Indexed off _G, unlike its neighbours: C_LFGList is the one API this file
-- touches that is NOT in .luacheckrc's allowlist, so a bare capture is a
-- W113 (accessing undefined global) and every task gates on zero warnings.
-- Modules/Skinning/Frames/LFG.lua:122 already reaches this same API this way.
-- Do NOT widen .luacheckrc instead.
local C_LFGList = _G.C_LFGList
local GameTooltip = GameTooltip
local issecretvalue = issecretvalue or function() return false end

-- Dungeon display name (lowercase, difficulty suffix stripped) ->
-- teleport spellID. Season-volatile data matched by name against
-- GetActivityInfoTable's fullName.
--
-- English keys only. The reference also carries ten Cyrillic keys, which
-- were dropped deliberately: they cannot ever match. The lookup lowercases
-- with Lua's string.lower, which is byte-wise and ASCII-only, so a
-- capitalised Cyrillic name ("Небесный путь") never folds to the lowercase
-- key ("небесный путь") -- measured 2026-07-31 in this project's Lua 5.1.
-- They are dead entries upstream too, and KE ships no localisation, so
-- carrying them would imply support that does not exist. Adding real
-- Russian support means Cyrillic-aware case folding, not these keys.
local TELEPORT_BY_NAME = {
    ["magisters' terrace"]         = 1254572,
    ["maisara caverns"]            = 1254559,
    ["nexus-point xenas"]          = 1254563,
    ["windrunner spire"]           = 1254400,
    ["algeth'ar academy"]          = 393273,
    ["pit of saron"]               = 1254555,
    ["seat of the triumvirate"]    = 1254551,
    ["skyreach"]                   = 159898,
}

local function ResolveTeleportSpellByName(displayName)
    if type(displayName) ~= "string" then return nil end
    local n = displayName:lower():gsub("%s*%b()%s*$", "")
    return TELEPORT_BY_NAME[n]
end

-- Test seam. The lookup is a pure file-local with no other handle, and no
-- function references it until the resolve chain lands, so debug.getupvalue
-- has nothing to reach it through.
LR._ResolveTeleportSpellByName = ResolveTeleportSpellByName

-- Layout constants
local POPUP_W     = 210
local TITLE_H     = 27
local PAD         = 10
local NAME_TOP    = TITLE_H + 9
local NAME_H      = 24
local BTN_TOP     = NAME_TOP + NAME_H
local BTN_H       = 56
local DISABLE_TOP = BTN_TOP + BTN_H + 8
local DISABLE_H   = 16
local POPUP_H     = DISABLE_TOP + DISABLE_H + 10

-- State (plain upvalues; never keyed by a possibly-secret resultID)
local popup, secureBtn
local pendingSpellID       -- resolved teleport spell (static integer)
local pendingName          -- dungeon display name (clean)
local pendingAttrSpellID   -- spell attr stashed for out-of-combat write
local pendingShow          -- join landed in combat; show on REGEN_ENABLED
local pendingHide          -- hide requested in combat; flush on REGEN_ENABLED

local BuildPopup, ShowPrompt, HidePrompt, ClearPending
local UpdateButtonVisuals, ResolveDungeon
local SavePosition, ApplySavedPosition, ApplyDisableVisibility

function LR:UpdateDB()
    if KE.db and KE.db.profile then
        self.db = KE.db.profile.LFGReminder
    end
end

local function ShowTip(owner, text)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(text, 1, 1, 1, 1, true)
    GameTooltip:Show()
end

SavePosition = function()
    if not (popup and LR.db) then return end
    local p, _, rp, x, yo = popup:GetPoint()
    if p then LR.db.Pos = { p = p, rp = rp, x = x, y = yo } end
end

ApplySavedPosition = function()
    if not popup then return end
    popup:ClearAllPoints()
    local pos = LR.db and LR.db.Pos
    if pos and pos.p then
        popup:SetPoint(pos.p, UIParent, pos.rp or pos.p, pos.x or 0, pos.y or 0)
    else
        popup:SetPoint("CENTER", UIParent, "CENTER", 0, 150)
    end
end

-- Show/hide the "Disable Feature" text, trimming the window 20px when
-- hidden. Driven by db.ShowDisable (default ON).
ApplyDisableVisibility = function()
    if not popup then return end
    local show = not LR.db or LR.db.ShowDisable ~= false
    if popup._disableBtn then popup._disableBtn:SetShown(show) end
    popup:SetHeight(show and POPUP_H or (POPUP_H - 20))
end

-- Build the popup + secure button (once, out of combat)
BuildPopup = function()
    if popup then return popup end
    -- Resolved HERE, not at file scope: Dungeons.xml loads before
    -- Skinning.xml (KitnEssentials.toc:21 vs :25), so a file-top capture
    -- is nil and every skin call silently no-ops.
    local S = KE.Skins

    popup = CreateFrame("Frame", "KE_LFGReminderPopup", UIParent)
    popup:SetSize(POPUP_W, POPUP_H)
    popup:SetFrameStrata("DIALOG")
    popup:SetMovable(true)
    popup:EnableMouse(true)
    popup:RegisterForDrag("LeftButton")
    popup:SetScript("OnDragStart", function(s) s:StartMoving() end)
    popup:SetScript("OnDragStop", function(s) s:StopMovingOrSizing(); SavePosition() end)

    if S and S.Backdrop then S.Backdrop(popup) end

    -- Header bar with the static title
    local hdrBg = popup:CreateTexture(nil, "BORDER")
    hdrBg:SetColorTexture(0, 0, 0, 0.25)
    hdrBg:SetPoint("TOPLEFT", 1, -1); hdrBg:SetPoint("TOPRIGHT", -1, 0); hdrBg:SetHeight(TITLE_H)

    local title = popup:CreateFontString(nil, "OVERLAY")
    if S and S.SetFont then S.SetFont(title, 11, "") end
    title:SetPoint("TOPLEFT", PAD, -8)
    title:SetPoint("TOPRIGHT", -(PAD + 16), -8)
    title:SetJustifyH("LEFT")
    title:SetWordWrap(false)
    title:SetText("LFG Reminder")

    -- Joined dungeon's full name (SetText accepts secret strings)
    local nameFS = popup:CreateFontString(nil, "OVERLAY")
    if S and S.SetFont then S.SetFont(nameFS, 13, "") end
    nameFS:SetPoint("TOPLEFT", popup, "TOPLEFT", PAD, -NAME_TOP)
    nameFS:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -PAD, -NAME_TOP)
    nameFS:SetJustifyH("CENTER")
    nameFS:SetWordWrap(true)
    popup._name = nameFS

    -- Close (X) in the header
    local xBtn = CreateFrame("Button", nil, popup)
    xBtn:SetSize(16, 16)
    xBtn:SetPoint("RIGHT", hdrBg, "RIGHT", -6, 0)
    if S and S.CloseButton then S.CloseButton(xBtn, 12) end
    xBtn:SetScript("OnClick", function() HidePrompt() end)

    -- Secure teleport button (once; type + clicks set here and NEVER
    -- touched again; only "spell" is rewritten, out of combat).
    secureBtn = CreateFrame("Button", "KE_LFGReminderTeleport", popup, "SecureActionButtonTemplate")
    secureBtn:SetSize(POPUP_W - PAD * 2, BTN_H)
    -- A protected frame can only be anchored to another FRAME, never a
    -- region -- anchor to the popup, below the name text.
    secureBtn:SetPoint("TOP", popup, "TOP", 0, -BTN_TOP)
    secureBtn:RegisterForClicks("AnyUp", "AnyDown")
    secureBtn:SetAttribute("type", "spell")

    -- A child frame parented to the secure button is legal, and the button
    -- is only ever created out of combat.
    if S and S.Backdrop then
        S.Backdrop(secureBtn)
    else
        local btnBg = secureBtn:CreateTexture(nil, "BACKGROUND")
        btnBg:SetAllPoints()
        btnBg:SetColorTexture(0.04, 0.04, 0.06, 0.9)
    end

    local icon = secureBtn:CreateTexture(nil, "ARTWORK")
    icon:SetSize(40, 40)
    icon:SetPoint("LEFT", 8, 0)
    if S and S.Icon then S.Icon(icon, true) else icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
    secureBtn._icon = icon

    local btnLabel = secureBtn:CreateFontString(nil, "OVERLAY")
    if S and S.SetFont then S.SetFont(btnLabel, 12, "") end
    btnLabel:SetPoint("LEFT", icon, "RIGHT", 8, 0)
    btnLabel:SetPoint("RIGHT", -6, 0)
    btnLabel:SetJustifyH("LEFT")
    btnLabel:SetWordWrap(false)
    btnLabel:SetText("Teleport")
    secureBtn._label = btnLabel

    local hover = secureBtn:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints()
    hover:SetColorTexture(1, 1, 1, 0.12)

    -- Cooldown inherits the button's protection: anchor to the button
    -- FRAME matching the icon's rect, never to the icon texture.
    local cd = CreateFrame("Cooldown", nil, secureBtn, "CooldownFrameTemplate")
    cd:SetPoint("LEFT", secureBtn, "LEFT", 8, 0)
    cd:SetSize(40, 40)
    cd:SetHideCountdownNumbers(true)
    cd:SetDrawSwipe(true); cd:SetDrawBling(false); cd:SetDrawEdge(false)
    secureBtn._cd = cd

    secureBtn:SetScript("OnEnter", function(self)
        local sid = pendingSpellID
        if not sid then return end
        if not IsPlayerSpell(sid) then
            ShowTip(self, "You have not learned this dungeon teleport yet.")
            return
        end
        -- pcall'd whole-condition: see the note under UpdateButtonVisuals.
        local ok, onCD = pcall(function()
            local cdInfo = C_Spell and C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(sid)
            return cdInfo and cdInfo.duration and cdInfo.duration > 0
        end)
        if ok and onCD then
            ShowTip(self, "Teleport on Cooldown")
        else
            ShowTip(self, "Teleport to " .. (pendingName or "dungeon"))
        end
    end)
    secureBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- "Disable Feature" text: turns the whole feature off immediately
    local disableBtn = CreateFrame("Button", nil, popup)
    disableBtn:SetSize(POPUP_W - PAD * 2, DISABLE_H)
    disableBtn:SetPoint("TOP", popup, "TOP", 0, -DISABLE_TOP)
    local disableLbl = disableBtn:CreateFontString(nil, "OVERLAY")
    if S and S.SetFont then S.SetFont(disableLbl, 10, "") end
    disableLbl:SetAllPoints()
    disableLbl:SetJustifyH("CENTER")
    disableLbl:SetText("Disable Feature")
    disableLbl:SetTextColor(0.6, 0.6, 0.6, 1)
    disableBtn:SetScript("OnEnter", function() disableLbl:SetTextColor(1, 0.3, 0.3, 1) end)
    disableBtn:SetScript("OnLeave", function() disableLbl:SetTextColor(0.6, 0.6, 0.6, 1) end)
    disableBtn:SetScript("OnClick", function()
        if LR.db then LR.db.Enabled = false end
        KitnEssentials:DisableModule("LFGReminder")
    end)
    popup._disableBtn = disableBtn

    -- Intentionally NOT Escape-closable: stays until teleport, dungeon
    -- entry, group leave, or disable.
    popup:SetScale((LR.db and LR.db.Scale) or 1.05)
    ApplySavedPosition()
    ApplyDisableVisibility()
    popup:Hide()
    return popup
end

UpdateButtonVisuals = function()
    if not secureBtn or not pendingSpellID then return end
    local sid = pendingSpellID
    local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(sid)
    if info and info.iconID then secureBtn._icon:SetTexture(info.iconID) end
    local known = IsPlayerSpell(sid)
    secureBtn._icon:SetDesaturated(not known)
    secureBtn._icon:SetAlpha(known and 1 or 0.4)
    local lc = known and 1 or 0.5
    secureBtn._label:SetTextColor(lc, lc, lc, 1)
    if known then
        -- pcall'd whole-condition, per the note below.
        local ok, applied = pcall(function()
            local cdInfo = C_Spell and C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(sid)
            if cdInfo and cdInfo.startTime and cdInfo.duration and cdInfo.duration > 0 then
                secureBtn._cd:SetCooldown(cdInfo.startTime, cdInfo.duration)
                return true
            end
            return false
        end)
        if not (ok and applied) then secureBtn._cd:Clear() end
    else
        secureBtn._cd:Clear()
    end
end
