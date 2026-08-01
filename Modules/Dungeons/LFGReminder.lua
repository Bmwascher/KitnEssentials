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
local C_SpellBook = C_SpellBook
local SpellBookBank_Player = Enum.SpellBookSpellBank.Player
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
-- Both secret predicates get the same fallback: an environment missing one
-- would be missing both, and a bare call to either throws.
local issecretvalue = issecretvalue or function() return false end
local issecrettable = issecrettable or function() return false end

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
local combatHidden         -- the hide came from combat, not from the user


local BuildPopup, ShowPrompt, HidePrompt, ClearPending
local UpdateButtonVisuals, ResolveDungeon
local SavePosition, ApplySavedPosition, ApplyDisableVisibility

-- Read-only test seams. The pending state stays in the upvalues above --
-- these expose it without creating a second source of truth that could
-- drift from it. _GetPendingAttrSpellID exists specifically so the
-- cancellation spec can observe the deferred ATTRIBUTE write: asserting on
-- pendingSpellID alone would pass even without ClearPending's
-- pendingAttrSpellID line, making that test a false gate.
function LR:_GetPendingSpellID()     return pendingSpellID end
function LR:_GetPendingName()        return pendingName end
function LR:_GetPendingAttrSpellID() return pendingAttrSpellID end

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
        if not C_SpellBook.IsSpellKnown(sid, SpellBookBank_Player) then
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
        -- The DB write and the disable both land, but nothing redraws an
        -- open config page, so its master toggle kept showing ON until a
        -- reload. EnableModule/DisableModule's posthook only refreshes
        -- previews, not content. The IsShown guard is load-bearing:
        -- RefreshContent refuses to rebuild while hidden and defers instead,
        -- because a hidden rebuild orphaned frames in a past leak.
        if KE.GUIFrame and KE.GUIFrame:IsShown() then
            KE.GUIFrame:RefreshContent()
        end
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
    local known = C_SpellBook.IsSpellKnown(sid, SpellBookBank_Player)
    secureBtn._icon:SetDesaturated(not known)
    secureBtn._icon:SetAlpha(known and 1 or 0.4)
    local lc = known and 1 or 0.5
    secureBtn._label:SetTextColor(lc, lc, lc, 1)
    if known then
        -- Duration object, not the startTime/duration pair: those two carry no
        -- NeverSecret flag, so under SecretWhenCooldownsRestricted the
        -- comparison throws and a live cooldown renders as ready.
        -- GetSpellCooldownDuration is AllowedWhenTainted and returns a handle we
        -- only truth-test, never read (SpellDocumentation.lua:265-282). Same
        -- shape as Modules/Combat/Cursor.lua:826-831.
        local duration = C_Spell and C_Spell.GetSpellCooldownDuration
            and C_Spell.GetSpellCooldownDuration(sid)
        if duration then
            secureBtn._cd:SetCooldownFromDurationObject(duration, true)
        else
            secureBtn._cd:Clear()
        end
    else
        secureBtn._cd:Clear()
    end
end

-- Resolve the accepted dungeon via a CLEAN string chain. The pcall below is
-- LOAD-BEARING, not belt-and-braces: GetSearchResultInfo and
-- GetActivityInfoTable are both SecretArguments = "AllowedWhenUntainted"
-- (LFGListInfoDocumentation.lua:378, :167), so a secret resultID throws.
ResolveDungeon = function(resultID)
    if not (C_LFGList and C_LFGList.GetSearchResultInfo) then return end
    pcall(function()
        local info = C_LFGList.GetSearchResultInfo(resultID)
        if type(info) ~= "table" then return end
        local activityID = info.activityID
        -- issecretTABLE, not issecretvalue: a table can be non-secret itself
        -- while its reads produce secrets (FrameScriptDocumentation.lua:227-231
        -- vs :244-248). This is the only live path -- LfgSearchResultData has no
        -- activityID field in 12.0.7 (LFGListInfoDocumentation.lua:905-910).
        if activityID == nil and info.activityIDs and not issecrettable(info.activityIDs) then
            activityID = info.activityIDs[1]
        end
        if issecretvalue(activityID) or activityID == nil then return end
        local act = C_LFGList.GetActivityInfoTable(activityID)
        if type(act) ~= "table" then return end
        local fullName = act.fullName
        if type(fullName) ~= "string" or issecretvalue(fullName) then return end
        local spellID = ResolveTeleportSpellByName(fullName)
        if spellID then
            pendingSpellID = spellID
            -- Name only, no trailing difficulty suffix
            pendingName = (fullName:gsub("%s*%b()%s*$", ""))
        end
    end)
end

ShowPrompt = function()
    if not (LR.db and LR.db.Enabled ~= false) or not pendingSpellID then return end
    if InCombatLockdown() then
        -- Deferral comes BEFORE BuildPopup, unlike the reference. BuildPopup
        -- calls secureBtn:SetAttribute("type", "spell") on a protected frame
        -- (<REF>:194), which combat blocks -- and OnEnable skips the build in
        -- combat, so this path IS reachable with no popup at all: enable or
        -- /reload during combat, then join a group before it ends.
        -- PLAYER_REGEN_ENABLED builds it and finishes the show.
        pendingAttrSpellID = pendingSpellID
        pendingShow = true
        pendingHide = nil  -- a deferred show supersedes a deferred hide
        return
    end
    BuildPopup()
    popup._name:SetText(pendingName or "")
    secureBtn:SetAttribute("spell", pendingSpellID)  -- static integer
    pendingAttrSpellID = nil
    pendingHide = nil
    UpdateButtonVisuals()
    popup:Show()
end

HidePrompt = function()
    pendingShow = nil
    -- popup parents a SecureActionButton, so popup:Hide() is protected
    -- in combat. Already hidden = nothing to do (the common case when
    -- leaving an instance in combat); genuinely shown in combat = defer.
    if not (popup and popup:IsShown()) then pendingHide = nil; return end
    if InCombatLockdown() then pendingHide = true; return end
    pendingHide = nil
    popup:Hide()
end

ClearPending = function()
    pendingSpellID     = nil
    pendingName        = nil
    pendingShow        = nil
    -- Whatever combat took away is no longer wanted either: this runs on
    -- group-leave and instance-entry, both of which invalidate the prompt.
    combatHidden       = nil
    -- Also clear the deferred attribute write. A combat join sets BOTH
    -- pendingAttrSpellID and pendingShow; if the group breaks before combat
    -- ends, clearing only pendingShow would leave PLAYER_REGEN_ENABLED to
    -- build a popup nobody asked for and arm it with the cancelled
    -- dungeon's teleport. The reference does not clear it because its
    -- ShowPrompt built the popup up front.
    pendingAttrSpellID = nil
end

-- Live refresh for the GUI (scale + disable-text row)
function LR:RefreshVisuals()
    if not popup then return end
    popup:SetScale((self.db and self.db.Scale) or 1.05)
    ApplyDisableVisibility()
end

function LR:LFG_LIST_JOINED_GROUP(_, resultID)
    -- Fires the moment the player joins a Group Finder group; unlike
    -- browse/apply, the search result is readable here. Capture
    -- immediately -- the result can expire shortly after joining.
    ClearPending()
    ResolveDungeon(resultID)
    if pendingSpellID then ShowPrompt() end
end

function LR:GROUP_ROSTER_UPDATE()
    if not IsInGroup() then
        ClearPending(); HidePrompt()
    end
end

function LR:CheckInstance()
    local inInstance, instanceType = IsInInstance()
    if inInstance and instanceType == "party" then
        ClearPending(); HidePrompt()
    end
end

function LR:PLAYER_REGEN_DISABLED()
    -- Remember that COMBAT is what took the prompt away, so REGEN_ENABLED can
    -- put it back. HidePrompt clears pendingShow unconditionally, which is why
    -- the reference never re-shows: by the time combat ends there is no flag
    -- left saying a prompt was wanted. Deliberate deviation from the reference
    -- (Brandon, 2026-08-01) -- the group and dungeon are unchanged, and the
    -- end of the fight is exactly when the teleport becomes useful.
    combatHidden = (popup and popup:IsShown()) or nil
    HidePrompt()  -- teleports can't be cast in combat
end

function LR:PLAYER_REGEN_ENABLED()
    -- Build now if combat prevented it. Both OnEnable and ShowPrompt skip
    -- BuildPopup during combat, so a join that landed mid-combat can arrive
    -- here with no popup at all. Out of combat now, so the secure frame and
    -- its "type" attribute are safe to create.
    --
    -- Gated on a COHERENT live show -- pending show AND pending spell AND
    -- still enabled -- so a cancelled or disabled join never materialises a
    -- popup here.
    local wantShow = pendingShow and pendingSpellID
        and self.db and self.db.Enabled ~= false
    if wantShow and not popup then
        BuildPopup()
    end
    -- Flush a secure attribute write blocked during combat
    if pendingAttrSpellID and secureBtn then
        secureBtn:SetAttribute("spell", pendingAttrSpellID)
        pendingAttrSpellID = nil
    end
    -- Surface a prompt whose join landed mid-combat. The name is set here
    -- rather than in ShowPrompt: that path returned before touching the
    -- popup, which may not have existed yet.
    if wantShow then
        pendingShow = nil
        if popup then popup._name:SetText(pendingName or "") end
        UpdateButtonVisuals()
        if popup then popup:Show() end
    end
    -- Flush a hide blocked during combat -- UNLESS combat is what caused it
    -- and the prompt is still live. The popup is still on screen at this
    -- point (HidePrompt deferred rather than hid), so "re-showing" is really
    -- just cancelling the pending hide. Anything that invalidated the prompt
    -- during the fight -- leaving the group, entering the dungeon -- ran
    -- ClearPending, which nils pendingSpellID and combatHidden, so the hide
    -- proceeds normally in those cases.
    local keepShown = combatHidden and pendingSpellID
        and self.db and self.db.Enabled ~= false
    combatHidden = nil
    if pendingHide then
        pendingHide = nil
        if keepShown and popup and popup:IsShown() then
            popup._name:SetText(pendingName or "")
            UpdateButtonVisuals()
        elseif popup and popup:IsShown() then
            popup:Hide()
        end
    end
end

function LR:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

function LR:OnEnable()
    self:UpdateDB()
    if not (self.db and self.db.Enabled ~= false) then return end
    if not InCombatLockdown() then
        BuildPopup()  -- secure button needs out-of-combat creation
    end
    self:RegisterEvent("LFG_LIST_JOINED_GROUP")
    self:RegisterEvent("GROUP_ROSTER_UPDATE")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "CheckInstance")
    self:RegisterEvent("ZONE_CHANGED_NEW_AREA", "CheckInstance")
    self:RegisterEvent("PLAYER_REGEN_DISABLED")
    self:RegisterEvent("PLAYER_REGEN_ENABLED")
end

function LR:OnDisable()
    ClearPending()
    pendingHide = nil
    -- Do NOT use HidePrompt here. AceAddon disables our embeds immediately
    -- after this returns, and AceEvent's OnEmbedDisable calls
    -- UnregisterAllEvents (Libs/AceEvent-3.0/AceEvent-3.0.lua:112-115) --
    -- so a hide that HidePrompt deferred via pendingHide could never be
    -- flushed: our PLAYER_REGEN_ENABLED is gone.
    --
    -- KE:RunAfterCombat (Core/Globals.lua:154) owns its own frame and its
    -- own PLAYER_REGEN_ENABLED registration, so it survives our disable.
    -- It runs the closure immediately when out of combat.
    if popup and popup:IsShown() then
        KE:RunAfterCombat(function()
            -- Keep the popup ONLY if the module came back AND has a fresh
            -- live prompt. "Enabled" alone is not enough: this disable just
            -- cleared the pending state, so a re-enable with no new join
            -- would strand the old popup on screen with its old teleport
            -- still armed.
            if LR:IsEnabled() and pendingSpellID then return end
            -- Out of combat here, so both writes are safe.
            if secureBtn then secureBtn:SetAttribute("spell", nil) end
            if popup and popup:IsShown() then popup:Hide() end
        end)
    end
end

---------------------------------------------------------------------------------
-- Preview
---------------------------------------------------------------------------------

-- Force-show the popup with sample contents so the user can drag it into
-- place from the config panel. The reference has no preview; KE adds one
-- because dragging is the only way to position this frame and the only
-- other route to seeing it is joining a real dungeon group.
--
-- The "spell" attribute is CLEARED here, not just left unwritten. This is
-- the same secure button a real prompt arms, and nothing on the teardown
-- path unsets it -- so without this line a preview shown after any real
-- prompt would still cast that dungeon's teleport on click, from a config
-- screen. Combat-gated like every other write to this button.
function LR:ShowPreview()
    if not self:IsEnabled() then return end
    if InCombatLockdown() then return end
    BuildPopup()
    if not popup then return end
    if secureBtn then secureBtn:SetAttribute("spell", nil) end
    popup._name:SetText("Skyreach")
    if secureBtn and secureBtn._icon then
        local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(159898)
        if info and info.iconID then secureBtn._icon:SetTexture(info.iconID) end
        secureBtn._icon:SetDesaturated(false)
        secureBtn._icon:SetAlpha(1)
    end
    if secureBtn and secureBtn._label then
        secureBtn._label:SetTextColor(1, 1, 1, 1)
    end
    popup:Show()
end

function LR:HidePreview()
    if not popup then return end
    -- Same protection as HidePrompt: the popup parents a secure button.
    if InCombatLockdown() then return end
    if pendingSpellID then
        -- A real prompt is live underneath the preview -- restore it
        -- rather than hiding the user's actual teleport. The attribute has
        -- to be re-armed too: ShowPreview cleared it.
        if secureBtn then secureBtn:SetAttribute("spell", pendingSpellID) end
        popup._name:SetText(pendingName or "")
        UpdateButtonVisuals()
        return
    end
    popup:Hide()
end
