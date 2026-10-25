-- ╔══════════════════════════════════════════════════════════╗
-- ║  FocusMarker.lua                                         ║
-- ║  Module: Focus Marker                                    ║
-- ║  Purpose: Auto-creates a macro for focus targeting and   ║
-- ║           raid marker assignment, plus an optional       ║
-- ║           per-character focus interrupt macro.           ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

local FM = KitnEssentials:NewModule("FocusMarker", "AceEvent-3.0")

local InCombatLockdown = InCombatLockdown
local GetMacroIndexByName = GetMacroIndexByName
local EditMacro = EditMacro
local CreateMacro = CreateMacro
local GetNumMacros = GetNumMacros
local GetMacroInfo = GetMacroInfo
local IsInGroup = IsInGroup
local IsInRaid = IsInRaid
local UnitClass = UnitClass
local C_ChatInfo = C_ChatInfo
local C_Spell = C_Spell
local C_SpellBook = C_SpellBook
local C_Timer = C_Timer
local CreateFrame = CreateFrame
local GetTime = GetTime
local IsInInstance = IsInInstance
local GetNumGroupMembers = GetNumGroupMembers
local UnitFullName = UnitFullName
local GetNormalizedRealmName = GetNormalizedRealmName
---@type fun(unit: string): string?
local UnitGUID = UnitGUID
local issecretvalue = issecretvalue
local GetSpecialization = C_SpecializationInfo.GetSpecialization
local GetSpecializationInfo = C_SpecializationInfo.GetSpecializationInfo
local table_concat = table.concat
local pcall = pcall
local type = type

---------------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------------
local NO_KICK_SPECS = {
    [102]  = true, -- Balance Druid
    [105]  = true, -- Resto Druid
    [65]   = true, -- Holy Paladin
    [256]  = true, -- Disc Priest
    [257]  = true, -- Holy Priest
    [270]  = true, -- Mistweaver Monk
    [1468] = true, -- Preservation Evoker
}
local table_insert = table.insert
local tostring = tostring

local MACRO_CONDITIONALS_DEFAULT = "[@mouseover,exists,nodead][]"

local NAME_TO_INDEX = {
    Star = 1, Circle = 2, Diamond = 3, Triangle = 4,
    Moon = 5, Square = 6, Cross = 7, Skull = 8, None = 0,
}

local FA = KE.FocusAnnounce
local ASK_GAP = 2      -- seconds between marker requests: a zone-in's roster burst asks once
local REPLY_DELAY = 1  -- seconds an answer waits, so a burst of requests gets one

local KICK_MACRO_NAME = "!FocusKick"
local KICK_MACRO_ICON = 134400
local MACRO_BODY_MAX = 255

-- The documented caps stand in when the constants table is missing, so the
-- lookup never indexes nil.
local MACRO_CONSTS = Constants and Constants.MacroConsts
local MAX_ACCOUNT_MACROS = MACRO_CONSTS and MACRO_CONSTS.MAX_ACCOUNT_MACROS or 120
local MAX_CHARACTER_MACROS = MACRO_CONSTS and MACRO_CONSTS.MAX_CHARACTER_MACROS or 30

FM.KICK_MACRO_NAME = KICK_MACRO_NAME
FM.MACRO_BODY_MAX = MACRO_BODY_MAX
FM.MAX_CHARACTER_MACROS = MAX_CHARACTER_MACROS

---------------------------------------------------------------------------------
-- Macro ranges
---------------------------------------------------------------------------------
-- The marker macro owns the account range and the kick macro the character
-- range, so two macros of one name in different ranges never touch.
function FM.ClassifyMacroHit(index, first, last)
    if not index or index == 0 then return "miss" end
    if index >= first and index <= last then return "own" end
    return "other"
end

-- The name lookup answers the common case in one call. Only a hit in the other
-- range means a same-named macro may still sit in ours, and only that pays for
-- a scan, bounded by the range's macro count.
local function FindMacroInRange(name, characterRange)
    local first = characterRange and MAX_ACCOUNT_MACROS + 1 or 1
    local capacity = characterRange and MAX_CHARACTER_MACROS or MAX_ACCOUNT_MACROS
    local hit = GetMacroIndexByName(name)
    local where = FM.ClassifyMacroHit(hit, first, first + capacity - 1)
    if where == "own" then return hit end
    if where == "miss" then return nil end
    local numAccount, numCharacter = GetNumMacros()
    local count = (characterRange and numCharacter or numAccount) or 0
    for i = first, first + count - 1 do
        if GetMacroInfo(i) == name then return i end
    end
    return nil
end

---------------------------------------------------------------------------------
-- DB Helper
---------------------------------------------------------------------------------
function FM:UpdateDB()
    self.db = KE.db.profile.FocusMarker
end

function FM:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

---------------------------------------------------------------------------------
-- Marker
---------------------------------------------------------------------------------
function FM.ResolveMarker(db, classFile)
    if db.MarkerFromClass and classFile and db.ClassMarkers then
        local marker = db.ClassMarkers[classFile]
        if marker and NAME_TO_INDEX[marker] then
            return marker
        end
    end
    return db.SelectedMarker
end

function FM:GetPlayerClass()
    if not self.classFile then
        local _, classFile = UnitClass("player")
        self.classFile = classFile
    end
    return self.classFile
end

function FM:GetEffectiveMarker()
    return FM.ResolveMarker(self.db, self:GetPlayerClass())
end

---------------------------------------------------------------------------------
-- Core Logic
---------------------------------------------------------------------------------
function FM:GetConditionals()
    local cond = self.db.MacroConditionals
    if not cond or cond == "" then
        return MACRO_CONDITIONALS_DEFAULT
    end
    return cond
end

function FM:BuildMacroBody()
    local db = self.db
    local lines = {}
    local cond = self:GetConditionals()
    local idx = NAME_TO_INDEX[self:GetEffectiveMarker()] or 0

    -- No Overwrite: prefix the marker index with ~ so the 12.0.7 /tm skips
    -- targets that already carry a marker. Only meaningful when placing a
    -- marker (idx > 0); a ~0 clear is nonsensical.
    local noOverwrite = db.NoOverwrite and idx > 0

    -- /focus line (unless mark-only mode)
    if not db.MarkOnly then
        table_insert(lines, "/focus " .. cond)
    end

    -- Build /tm conditional (inject nogroup:raid if enabled)
    local tmCond = cond
    if db.NoRaid then
        local inner = cond:match("^%[(.*)%]$") or cond
        tmCond = "[nogroup:raid," .. inner .. "]"
    end

    -- Anti-toggle line (force clear before re-apply). Suppressed under No
    -- Overwrite: clearing the marker first would wipe an existing one and
    -- defeat the ~ guard.
    if not db.NoToggle and not noOverwrite then
        table_insert(lines, "/tm " .. tmCond .. " 0")
    end

    -- Marker line (~idx under No Overwrite, plain idx otherwise)
    local markerArg = noOverwrite and ("~" .. tostring(idx)) or tostring(idx)
    table_insert(lines, "/tm " .. tmCond .. " " .. markerArg)

    return table_concat(lines, "\n")
end

function FM:ApplyMacro()
    if InCombatLockdown() then
        self.pendingMacro = true
        return
    end

    local db = self.db
    local name = db.MacroName or "!FocusMarker"
    local icon = db.MacroIcon or 1033497
    local body = self:BuildMacroBody()

    local ok, err = pcall(function()
        -- Try to find existing macro by current name, in the account range only
        local mIndex = FindMacroInRange(name, false)
        if mIndex then
            EditMacro(mIndex, name, icon, body)
            return
        end

        -- If we had a previous name, try to rename it (account range only)
        if self.lastMacroName and self.lastMacroName ~= name then
            local oldIndex = FindMacroInRange(self.lastMacroName, false)
            if oldIndex then
                EditMacro(oldIndex, name, icon, body)
                return
            end
        end

        -- No existing macro — create new global macro
        CreateMacro(name, icon, body, nil)
    end)

    if not ok then
        KE:Print("FocusMarker macro error: " .. tostring(err))
    end

    self.lastMacroName = name
    self.pendingMacro = false
end

---------------------------------------------------------------------------------
-- Focus Kick
---------------------------------------------------------------------------------
local function IsKickKnown(id)
    return C_SpellBook.IsSpellKnownOrInSpellBook(id)
        or C_SpellBook.IsSpellKnownOrInSpellBook(id, Enum.SpellBookSpellBank.Pet)
end

-- The tracker kick stands in only for a spec with no candidate list, so a
-- spec whose candidates are all unknown gets no macro.
function FM.PickKickSpell(candidates, trackerKick, isKnown)
    if not candidates then
        local id = trackerKick and trackerKick.id
        if id and isKnown(id) then return id end
        return nil
    end
    for i = 1, #candidates do
        local entry = candidates[i]
        local id = type(entry) == "table" and entry.id or entry
        if id and isKnown(id) then
            return id
        end
    end
    return nil
end

function FM.BuildKickBody(spellName, db, markerIdx)
    if not spellName or spellName == "" then return nil end
    local lines = { "#showtooltip " .. spellName }
    if db.KickStopCasting then
        lines[#lines + 1] = "/stopcasting"
    end
    local cond = "[@focus,harm,nodead]"
    if db.KickMouseover then
        cond = cond .. "[@mouseover,harm,nodead]"
    end
    if db.KickTargetFallback then
        cond = cond .. "[]"
    end
    lines[#lines + 1] = "/cast " .. cond .. " " .. spellName
    -- Always ~: a kick press must never toggle an existing marker off.
    if db.KickMarkFocus and markerIdx and markerIdx > 0 then
        lines[#lines + 1] = "/tm [@focus] ~" .. tostring(markerIdx)
    end
    local body = table_concat(lines, "\n")
    if #body > MACRO_BODY_MAX then return nil end
    return body
end

-- Returns state, spellID, body, specName, spellName. Only "ready" carries a body.
function FM:ComputeKick()
    local specIndex = GetSpecialization()
    local specID, specName
    if specIndex then
        specID, specName = GetSpecializationInfo(specIndex)
    end
    if not specID or specID == 0 then
        return "nospec"
    end
    local candidates = KE:GetInterruptCandidatesForSpec(specID)
    local trackerKick = not candidates and KE:GetTrackedKickForSpec(specID) or nil
    local spellID = FM.PickKickSpell(candidates, trackerKick, IsKickKnown)
    if not spellID then
        return "nokick", nil, nil, specName
    end
    local spellName = C_Spell.GetSpellName(spellID)
    if not spellName then
        return "loading", spellID, nil, specName
    end
    local body = FM.BuildKickBody(spellName, self.db, NAME_TO_INDEX[self:GetEffectiveMarker()] or 0)
    if not body then
        return "toolong", spellID, nil, specName, spellName
    end
    return "ready", spellID, body, specName, spellName
end

-- The macro's current body, so a player's hand edit is seen and written over.
function FM:ReadKickBody()
    local index = FindMacroInRange(KICK_MACRO_NAME, true)
    if not index then return nil end
    local body = select(3, GetMacroInfo(index))
    return body
end

-- An existing macro is always edited, even with every slot used; only a new
-- one needs a free slot. No fallback to an account slot: that macro would be
-- shared by every character.
function FM.KickSlotAction(found, numCharacter, maxCharacter)
    if found then return "edit" end
    if numCharacter >= maxCharacter then return "full" end
    return "create"
end

local function WriteKick(fm, body)
    local index = FindMacroInRange(KICK_MACRO_NAME, true)
    local numCharacter = 0
    if not index then
        local _, count = GetNumMacros()
        numCharacter = count or 0
    end
    local action = FM.KickSlotAction(index ~= nil, numCharacter, MAX_CHARACTER_MACROS)
    if action == "edit" and index then
        local current = select(3, GetMacroInfo(index))
        if current ~= body then
            -- Nil name and icon change only the body, so an icon the player picked survives.
            EditMacro(index, nil, nil, body)
        end
        fm.kickSlotsFull = false
        return
    end
    if action == "full" then
        fm.kickSlotsFull = true
        if not fm.kickFullWarned then
            fm.kickFullWarned = true
            KE:Print("Focus Kick: your " .. MAX_CHARACTER_MACROS .. " character macro slots are full; free one "
                .. "and KE will create " .. KICK_MACRO_NAME .. ".")
        end
        return
    end
    CreateMacro(KICK_MACRO_NAME, KICK_MACRO_ICON, body, true)
    fm.kickSlotsFull = false
    KE:Print("Focus Kick: created " .. KICK_MACRO_NAME .. " in your character macros (/macro, second tab).")
end

-- An id that already loaded once is not requested again: a load that succeeds
-- with the name still missing would otherwise request, load and refresh forever.
function FM:RequestKickSpellData(spellID)
    if self.loadedSpellID == spellID then return end
    if self.pendingSpellID ~= spellID then
        self.pendingSpellID = spellID
        self:RegisterEvent("SPELL_DATA_LOAD_RESULT", "OnKickSpellDataLoaded")
    end
    C_Spell.RequestLoadSpellData(spellID)
end

-- A failed load waits for the next ordinary trigger; re-requesting on failure
-- would repeat every frame.
function FM:OnKickSpellDataLoaded(_, spellID, success)
    if spellID ~= self.pendingSpellID then return end
    self.pendingSpellID = nil
    self:UnregisterEvent("SPELL_DATA_LOAD_RESULT")
    if success then
        self.loadedSpellID = spellID
        self:QueueKickRefresh()
    end
end

-- Macro writes are refused in combat, so a combat refresh only marks itself
-- pending; the drain recomputes from live state, never a body built before it.
function FM.KickRefreshAction(enabled, kickOn, inCombat)
    if not enabled or not kickOn then return "skip" end
    if inCombat then return "defer" end
    return "run"
end

function FM:RefreshKickMacro()
    local action = FM.KickRefreshAction(self:IsEnabled(), self.db.KickMacroEnabled, InCombatLockdown())
    if action == "skip" then return end
    if action == "defer" then
        self.pendingKick = true
        return
    end
    self.pendingKick = false
    local state, spellID, body = self:ComputeKick()
    if state == "loading" then
        self:RequestKickSpellData(spellID)
    elseif state == "ready" then
        local ok, err = pcall(WriteKick, self, body)
        if not ok then
            KE:Print("Focus Kick macro error: " .. tostring(err))
        end
    end
end

function FM:QueueKickRefresh()
    if self.kickQueued then return end
    if not self.kickRefreshFn then
        self.kickRefreshFn = function()
            self.kickQueued = false
            self:RefreshKickMacro()
        end
    end
    self.kickQueued = true
    C_Timer.After(0, self.kickRefreshFn)
end

function FM:OnKickUnitEvent(_, unit)
    if unit == "player" then
        self:QueueKickRefresh()
    end
end

function FM:OnKickSpellsChanged()
    self:QueueKickRefresh()
end

-- The enabled check matters: the settings page calls ApplySettings on a
-- disabled module too, and AceEvent would register on it.
function FM:UpdateKickEvents()
    if self:IsEnabled() and self.db.KickMacroEnabled then
        self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", "OnKickUnitEvent")
        self:RegisterEvent("SPELLS_CHANGED", "OnKickSpellsChanged")
        -- Only warlock interrupts come from a pet.
        if self:GetPlayerClass() == "WARLOCK" then
            self:RegisterEvent("UNIT_PET", "OnKickUnitEvent")
        end
        self:QueueKickRefresh()
    else
        self:UnregisterEvent("PLAYER_SPECIALIZATION_CHANGED")
        self:UnregisterEvent("SPELLS_CHANGED")
        self:UnregisterEvent("UNIT_PET")
        self:UnregisterEvent("SPELL_DATA_LOAD_RESULT")
        self.pendingKick = false
        self.pendingSpellID = nil
    end
end

---------------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------------
-- A marker change inside a party instance is told at once, and the Kick
-- Tracker's own lane hears it.
function FM:ApplySettings()
    self:ApplyMacro()
    self:UpdateKickEvents()
    self:SyncAnnounceEvents(false)
    local index = self:MarkerIndex()
    if self:IsEnabled() and index ~= self.sentIndex then
        self.sentIndex = index
        self:SendMarkerMessages("F", "stateUpdate")
        self:SendMessage(FA.MARKER_CHANGED)
    end
end

---------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------
-- SendChatMessage is refused while chat messaging is locked, which a running
-- keystone does between pulls with no combat lockdown. The caller checks the
-- lock and sends in the same tick, so nothing can change between the two.
function FM.AnnounceAllowed(specID, inGroup, inRaid, inCombat, chatLocked)
    if specID and NO_KICK_SPECS[specID] then return false end
    if not inGroup or inRaid or inCombat or chatLocked then return false end
    return true
end

-- The effective marker as its index, 1 to 8; nil for None.
function FM:MarkerIndex()
    local index = NAME_TO_INDEX[self:GetEffectiveMarker() or "Star"]
    if index and index >= 1 then return index end
    return nil
end

function FM:_AnnounceFocusMarkerOnReadyCheck()
    local db = self.db
    if not db.AnnounceReadyCheck then return end
    local specID = KE:GetPlayerSpecId()
    if not FM.AnnounceAllowed(specID, IsInGroup(), IsInRaid(), InCombatLockdown(),
        KE:IsChatMessagingLocked()) then
        return
    end
    local index = self:MarkerIndex()
    if not index then return end
    C_ChatInfo.SendChatMessage(FA.ChatLine(index), "PARTY")
    self:SendMarkerMessages("F", "stateUpdate")
end

local function InPartyInstance()
    local _, instanceType = IsInInstance()
    return instanceType == "party"
end

-- "Name-Realm" and the bare name, plain, or nil.
local function OwnFullName()
    local name, realm = UnitFullName("player")
    if issecretvalue(name) or issecretvalue(realm) or type(name) ~= "string" then return nil end
    if type(realm) ~= "string" or realm == "" then realm = GetNormalizedRealmName() end
    if type(realm) ~= "string" then return nil end
    return name .. "-" .. realm, name
end

-- The addon messages pass the chat announce's own gate, inside a party
-- instance, with a marker to tell. A nil kind skips that message.
function FM:SendMarkerMessages(euiKind, mdtKind)
    if not self.db.AnnounceReadyCheck or not InPartyInstance() then return end
    if not FM.AnnounceAllowed(KE:GetPlayerSpecId(), IsInGroup(), IsInRaid(), InCombatLockdown(),
        KE:IsChatMessagingLocked()) then
        return
    end
    local index = self:MarkerIndex()
    if not index then return end
    FA.RegisterPrefixes()
    local guid = UnitGUID("player")
    if euiKind and guid then
        C_ChatInfo.SendAddonMessage(FA.EUIKT_PREFIX, FA.EUIKTMessage(euiKind, index, guid), "PARTY")
    end
    local fullName, name = OwnFullName()
    if mdtKind and fullName then
        local text = FA.EncodeMDT(FA.MDTPayload(mdtKind, fullName, name, self:GetPlayerClass(), index))
        if text then C_ChatInfo.SendAddonMessage(FA.MDT_PREFIX, text, "PARTY") end
    end
end

-- A full party asks for the others' markers, at most once per ASK_GAP.
function FM:RequestMarkers()
    if GetNumGroupMembers() ~= 5 then return end
    local now = GetTime()
    if self.askedAt and now - self.askedAt < ASK_GAP then return end
    self.askedAt = now
    self:SendMarkerMessages("R", "stateRequest")
end

function FM:ReplyMarker()
    if self.replyArmed then return end
    self.replyArmed = true
    C_Timer.After(REPLY_DELAY, function()
        self.replyArmed = false
        if self:IsEnabled() then self:SendMarkerMessages("F", nil) end
    end)
end

-- Requests from teammates' addons get the player's marker; nothing else is
-- read here. A request inside a key, on another channel, or from the player
-- or anyone outside the party is refused.
function FM:OnMarkerAddon(prefix, text, channel, sender)
    if issecretvalue(prefix) or issecretvalue(text) or issecretvalue(channel) or issecretvalue(sender) then return end
    local locked = KE:IsChatMessagingLocked()
    if prefix == FA.EUIKT_PREFIX then
        local kind, _, guid = FA.ParseEUIKT(text)
        if kind ~= "R" or FA.AddonRefused(prefix, channel, locked, FA.TeammateGuid(guid) ~= nil) then return end
        self:ReplyMarker()
    elseif prefix == FA.MDT_PREFIX then
        if FA.AddonRefused(prefix, channel, locked, FA.TeammateByName(sender) ~= nil) then return end
        local payload = FA.DecodeMDT(text)
        if not payload or payload.kind ~= "stateRequest" then return end
        self:SendMarkerMessages(nil, "stateResponse")
    end
end

function FM:OnAnnounceEvent(event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        C_Timer.After(1, function()
            if self:IsEnabled() then self:SyncAnnounceEvents(true) end
        end)
    elseif event == "GROUP_ROSTER_UPDATE" then
        local size = GetNumGroupMembers()
        if size == 5 and (self.groupSize or 0) < 5 then self:RequestMarkers() end
        self.groupSize = size
    elseif event == "CHAT_MSG_ADDON" then
        self:OnMarkerAddon(...)
    end
end

-- The zone-in listener runs while the announce is on; the addon channel and
-- the roster are heard only inside a party instance. A zone-in asks.
function FM:SyncAnnounceEvents(zoneIn)
    local frame = self.announceFrame
    if not (self:IsEnabled() and self.db.AnnounceReadyCheck) then
        if frame then frame:UnregisterAllEvents() end
        return
    end
    if not frame then
        frame = CreateFrame("Frame")
        frame:SetScript("OnEvent", function(_, event, ...) self:OnAnnounceEvent(event, ...) end)
        self.announceFrame = frame
    end
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    if InPartyInstance() then
        FA.RegisterPrefixes()
        frame:RegisterEvent("CHAT_MSG_ADDON")
        frame:RegisterEvent("GROUP_ROSTER_UPDATE")
        if zoneIn then
            self.groupSize = GetNumGroupMembers()
            self:RequestMarkers()
        end
    else
        frame:UnregisterEvent("CHAT_MSG_ADDON")
        frame:UnregisterEvent("GROUP_ROSTER_UPDATE")
    end
end

function FM:OnEnable()
    self:ApplyMacro()

    if not self.readyCheckFrame then
        self.readyCheckFrame = CreateFrame("Frame")
        self.readyCheckFrame:SetScript("OnEvent", function()
            self:_AnnounceFocusMarkerOnReadyCheck()
        end)
    end
    self.readyCheckFrame:RegisterEvent("READY_CHECK")

    self:RegisterEvent("PLAYER_REGEN_ENABLED", function()
        if self.pendingMacro then
            self:ApplyMacro()
        end
        if self.pendingKick then
            self:QueueKickRefresh()
        end
    end)

    self:UpdateKickEvents()
    self.sentIndex = self:MarkerIndex()
    self:SyncAnnounceEvents(true)
    self:SendMessage(FA.MARKER_CHANGED)
end

function FM:OnDisable()
    self:UnregisterAllEvents()
    if self.readyCheckFrame then
        self.readyCheckFrame:UnregisterAllEvents()
    end
    if self.announceFrame then
        self.announceFrame:UnregisterAllEvents()
    end
    self:SendMessage(FA.MARKER_CHANGED)
    self.lastMacroName = nil
    self.pendingKick = false
    self.pendingSpellID = nil
end
