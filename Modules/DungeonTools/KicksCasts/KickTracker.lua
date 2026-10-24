-- ╔══════════════════════════════════════════════════════════╗
-- ║  KickTracker.lua                                         ║
-- ║  Module: Interrupt Tracker                               ║
-- ║  Purpose: Party interrupt cooldown bars with class       ║
-- ║           colors, dark mode, channel kick detection,     ║
-- ║           and healer position override.                  ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class KickTracker: AceModule, AceEvent-3.0, AceTimer-3.0
local KT = KitnEssentials:NewModule("KickTracker", "AceEvent-3.0", "AceTimer-3.0")

---------------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------------
local GetTime = GetTime
local CreateFrame = CreateFrame
-- Group-member unit reads stay plain under addon restrictions (probed in
-- game); the typed aliases record that for the checker.
---@type fun(unit: string): string?
local UnitGUID = UnitGUID
---@type fun(unit: string): string?, string?
local UnitName = UnitName
---@type fun(unit: string): string?, string?, number?
local UnitClass = UnitClass
local UnitExists = UnitExists
local IsInInstance = IsInInstance
local IsInGroup = IsInGroup
local GetSpecialization = C_SpecializationInfo.GetSpecialization
local GetSpecializationInfo = C_SpecializationInfo.GetSpecializationInfo
---@type fun(unit: string): string
local UnitGroupRolesAssigned = UnitGroupRolesAssigned
local C_Timer = C_Timer
local C_ClassColor = C_ClassColor
local C_Spell = C_Spell
local UnitTokenFromGUID = UnitTokenFromGUID
local GetRaidTargetIndex = GetRaidTargetIndex
local GetSpecializationInfoForSpecID = GetSpecializationInfoForSpecID
local UnitCanAttack = UnitCanAttack
local issecretvalue = issecretvalue
local string_find = string.find
local string_format = string.format
local math_floor = math.floor
local math_abs = math.abs
local math_max = math.max
local pairs = pairs
local ipairs = ipairs
local wipe = wipe
local table_insert = table.insert
local table_sort = table.sort

---------------------------------------------------------------------------------
-- Interrupt Database
---------------------------------------------------------------------------------
-- Spec kicks live in Core/Interrupts.lua. An own cast of any of these starts
-- the player's kick cooldown.
local INTERRUPT_SPELL_IDS = KE:GetInterruptKickSpellSet()

-- Class kicks for teammates not yet inspected, each at the class's longest
-- kick time (KT.FallbackKick holds the role rule). allRoles: every spec of
-- the class has this kick; otherwise only a DAMAGER or TANK role proves a
-- kicking spec. tankCd and healerCd replace cd for that role.
local CLASS_FALLBACK_INTERRUPTS = {
    DEATHKNIGHT = { id = 47528,  cd = 15, allRoles = true },
    DEMONHUNTER = { id = 183752, cd = 15, allRoles = true },
    DRUID       = { id = 106839, cd = 60, tankCd = 15 },  -- Balance's Solar Beam
    EVOKER      = { id = 351338, cd = 20 },
    HUNTER      = { id = 147362, cd = 24, allRoles = true },
    MAGE        = { id = 2139,   cd = 25, allRoles = true },
    MONK        = { id = 116705, cd = 15 },
    PALADIN     = { id = 96231,  cd = 15 },
    PRIEST      = { id = 15487,  cd = 30 },  -- Shadow only; a DPS role proves it
    ROGUE       = { id = 1766,   cd = 15, allRoles = true },
    SHAMAN      = { id = 57994,  cd = 12, allRoles = true, healerCd = 30 },
    WARLOCK     = { id = 19647,  cd = 30, allRoles = true },  -- Demonology's Axe Toss
    WARRIOR     = { id = 6552,   cd = 15, allRoles = true },
}

local ROW_SLOTS = 5  -- a party's rows
local RAID_MARK_SHEET = "Interface\\TargetingFrame\\UI-RaidTargetingIcons"
local OWN_KICK_MATCH_WINDOW = 0.5

local SAME_FRAME = 0.02  -- two reports of one stopped channel land this close

local function FormatRemaining(remaining)
    if remaining > 6 then return string_format("%d", math_floor(remaining)) end
    return string_format("%.1f", remaining)
end

-- The countdown is KE's own plain arithmetic, so an unchanged string is skipped.
local function SetTimerText(bar, text)
    if bar.lastTimerText ~= text then
        bar.timerText:SetText(text)
        bar.lastTimerText = text
    end
end
KT.FormatRemaining, KT.SetTimerText = FormatRemaining, SetTimerText

-- Flip true to trace preview lifecycle, cooling-bar OnUpdate cadence,
-- container OnUpdate ticks, and nameplate-interrupt token resolution.
-- Default false; revert after diagnosis.
local DEBUG_KT = false
-- Per-frame heartbeat logging (container tick + preview cooling tick) is far
-- spammier than the event logs — separate opt-in.
local DEBUG_KT_TICKS = false
local _ktContainerTickCounter = 0
local _ktCoolingTickCounter = 0
local KT_TICK_LOG_EVERY = 20   -- container OnUpdate at 20fps -> ~once/sec
local KT_COOLING_LOG_EVERY = 60  -- cooling per-bar at ~60fps -> ~once/sec

KT.containerFrame = nil
KT.isPreview = false
KT.editModeRegistered = false
KT.previewContext = nil    -- "HEALER" | "DEFAULT" | nil (GUI editing/preview override)
KT.guiConfigContext = nil  -- "HEALER" | "DEFAULT" | nil (which context the GUI edits)

KT.partyMembers = {}     -- [guid] = { unit, name, classToken, matchClass, specID, interruptData, kickStart, kickDuration, inspect }
-- A teammate also carries inspectRespec and inspectMisses (KT:WantsInspect).

KT.barPool = {}           -- array of reusable bar frames
KT.activeBars = {}        -- [guid] = barFrame
KT.sortedBars = {}        -- ordered array for layout
KT._coolingList = {}      -- reusable temp table for LayoutBars
KT._readyList = {}        -- reusable temp table for LayoutBars

KT.isActive = false
KT.activationID = 0       -- bumped on each activation; deferred callbacks check it
KT.combatEventsRegistered = false
KT.ownClaim = {}  -- at: the player's last kick cast; see KT:ClaimOwnKick
KT.lastEventAt = {}  -- [nameplate token] = its last accepted interrupt time

---------------------------------------------------------------------------------
-- DB Helper
---------------------------------------------------------------------------------
function KT:UpdateDB()
    self.db = KE.db.profile.KickTracker
end

---------------------------------------------------------------------------------
-- Party Spec Tracking
---------------------------------------------------------------------------------
local function GetPlayerSpecID()
    local specIndex = GetSpecialization()
    if specIndex then
        return GetSpecializationInfo(specIndex)
    end
    return 0
end

local function SpecRole(specID)
    if type(specID) ~= "number" or specID <= 0 or not GetSpecializationInfoForSpecID then return "DAMAGER" end
    local _, _, _, _, role = GetSpecializationInfoForSpecID(specID)
    return role or "DAMAGER"
end

local function KickRow(id, cd, specID, role)
    return { id = id, cd = cd, role = role or SpecRole(specID) }
end

function KT:GetInterruptDataForSpec(specID)
    if not specID or specID == 0 then return nil end
    local kick = KE:GetTrackedKickForSpec(specID)
    if not kick then return nil end
    return KickRow(kick.id, kick.cd, specID)
end

-- The spec's kick, and the inspect snapshot its talents come from
-- (KT.LearnFacts).
function KT:ApplySpecKick(member, specID, snap)
    KT.LearnFacts(member, snap, self:GetInterruptDataForSpec(specID))
    member.specID = specID
end

local function isTalentKnown(talentID)
    return C_SpellBook.IsSpellKnown(talentID) == true
end

-- The player's own talents read as rank 1 or 0, never unknown.
local function ownRank(talentID)
    return isTalentKnown(talentID) and 1 or 0
end

-- The player's kick duration from its definition (KT.KickDuration); a kick
-- without one keeps the row's cooldown.
function KT:OwnKickCooldown(data, succeeded)
    local def = KE:GetKickDefinition(KE:GetCanonicalKickSpell(data.id))
    if not def then return data.cd end
    return KT.KickDuration(def, GetPlayerSpecID(), ownRank, succeeded)
end

local function isOwnKickKnown(id)
    return C_SpellBook.IsSpellKnownOrInSpellBook(id)
        or C_SpellBook.IsSpellKnownOrInSpellBook(id, Enum.SpellBookSpellBank.Pet)
end

-- The player's main kick. A spec with several candidates (a warlock) uses the
-- kick the player cast with this demon (castKick) while it is set; without it,
-- the first candidate the player or the active demon knows, so the row
-- follows the demon. With neither there is no own row.
function KT:GetOwnInterruptData(specID, castKick)
    local candidates = KE:GetInterruptCandidatesForSpec(specID)
    if not candidates or #candidates < 2 then return self:GetInterruptDataForSpec(specID) end
    local kick = KT.OwnKickFallback(KT.PickOwnKick(candidates, isOwnKickKnown), castKick)
    if not kick then return nil end
    return KickRow(KE:GetCanonicalKickSpell(kick.id), kick.cd, specID)
end

-- The spec's talent-added kicks the player's talents make real.
function KT:GetOwnExtraKicks(specID)
    return KT.WantedExtraKicks(KE:GetExtraKicksForSpec(specID), isTalentKnown)
end

-- Every refresh that sets the player's main kick comes here (roster, spec,
-- pet or spellbook change), so a change is handled once whichever runs first.
-- A new spec ends the cast mark. A new kick has not been used, so its cooldown
-- starts clear. Returns whether the main kick changed, then whether anything
-- the row shows changed.
function KT:ApplyOwnKicks(member, specID)
    local specChanged = member.ownKickSpec ~= specID
    if specChanged then
        member.ownKickSpec = specID
        member.castKick = nil
    end
    local data = self:GetOwnInterruptData(specID, member.castKick)
    local oldID = member.interruptData and member.interruptData.id
    member.interruptData = data
    local extrasChanged
    member.extraKicks, extrasChanged = KT.SyncExtraKicks(member.extraKicks, self:GetOwnExtraKicks(specID))
    local mainChanged = oldID ~= (data and data.id)
    if mainChanged then
        member.kickStart, member.kickDuration = nil, nil
    end
    return mainChanged, mainChanged or specChanged or extrasChanged
end

-- A teammate not yet inspected gets the class kick (KT.FallbackKick).
function KT:GuessClassInterrupt(unit, classToken)
    -- IsSafeValue before the table key: a secret key would throw.
    local fallback = classToken and KE:IsSafeValue(classToken)
        and CLASS_FALLBACK_INTERRUPTS[classToken]
    if not fallback then return nil end
    return KT.FallbackKick(fallback, UnitGroupRolesAssigned(unit))
end

-- A clock's length for a member's main kick: the player's from their own
-- talents, a teammate's from their inspected facts (an unknown talent gives
-- the longest), a class fallback row's own duration. succeeded: the kick's
-- interrupt is confirmed.
function KT:ClockDuration(member, succeeded)
    local data = member.interruptData
    if not data then return nil end
    if member.unit == "player" then return self:OwnKickCooldown(data, succeeded) end
    if data.fallback then return data.cd end
    local def = KE:GetKickDefinition(KE:GetCanonicalKickSpell(data.id))
    if not def then return data.cd end
    local snap = member.inspect
    return KT.KickDuration(def, member.specID, function(talent) return KT.SnapshotRank(snap, talent) end,
        succeeded)
end

-- classToken is for display: the C-side class color takes it secret or not.
-- KT.KeyMembers compares the class in Lua, so its copy is kept plain only.
local function SetMemberClass(member, classToken)
    member.classToken = classToken
    if KE:IsSafeValue(classToken) then
        member.matchClass = classToken
    else
        member.matchClass = nil
    end
end

function KT:RefreshPartyRoster()
    if not self.db or not self.db.Enabled then return end

    local currentGuids = {}
    local units = { "player" }
    for i = 1, 4 do
        units[i + 1] = "party" .. i
    end

    for _, unit in ipairs(units) do
        if UnitExists(unit) then
            local guid = UnitGUID(unit)
            if guid then
                currentGuids[guid] = unit
                local name = UnitName(unit)
                local _, classToken = UnitClass(unit)

                if not self.partyMembers[guid] then
                    self.partyMembers[guid] = {}
                end
                local member = self.partyMembers[guid]
                member.unit = unit
                member.name = name
                SetMemberClass(member, classToken)

                if unit == "player" then
                    local specID = GetPlayerSpecID() or 0
                    if specID > 0 then
                        member.specID = specID
                        self:ApplyOwnKicks(member, specID)
                    end
                else
                    local snap = self.inspectHandle and self.inspectHandle:Get(guid)
                    local spec = snap and snap.spec
                    if type(spec) == "number" and spec > 0 then
                        if member.inspect ~= snap or member.specID ~= spec then
                            self:ApplySpecKick(member, spec, snap)
                        end
                    elseif not member.interruptData then
                        -- Not inspected yet: the class kick, so the bar exists.
                        member.interruptData = self:GuessClassInterrupt(unit, classToken)
                    end
                end
            end
        end
    end

    -- Remove members who left
    for guid in pairs(self.partyMembers) do
        if not currentGuids[guid] then
            self.partyMembers[guid] = nil
            if self.activeBars[guid] then
                self:ReleaseBar(guid)
            end
        end
    end

    self:UpdateInspectDemand()
    self:UpdateBars()
    self:LayoutBars()
end

-- The player's own spec; teammates' specs come from inspection
-- (KT:OnInspectRead).
function KT:ApplySpecData(guid, unit, specID)
    local _, classToken = UnitClass(unit)
    local member = self.partyMembers[guid]
    if member then
        SetMemberClass(member, classToken)
        member.specID = specID
        self:ApplyOwnKicks(member, specID)
        self:UpdateBars()
        self:LayoutBars()
    end
end

function KT:OnPlayerSpecChanged(_, unit)
    self:RefreshInspectedSpec(unit)
    local specID = GetPlayerSpecID()
    if not specID or specID == 0 then return end

    local guid = UnitGUID("player")
    if not guid then return end

    self:ApplySpecData(guid, "player", specID)

    -- Re-apply position in case healer override is active
    if self.db and self.db.UseHealerPosition then
        self:ApplySettings()
        self:RefreshEditMode()  -- relabel overlay if spec crossed the healer boundary
    end
end

---------------------------------------------------------------------------------
-- Teammate facts (the shared inspector)
---------------------------------------------------------------------------------
-- Subscribed on the first activation, never at load or while disabled.
-- Without the inspector teammates keep the class kick.
function KT:EnsureInspect()
    if self.inspectHandle or not KE.GroupInspect then return end
    self.inspectHandle = KE.GroupInspect:Subscribe("KickTracker", {
        Wants = function(guid) return KT:WantsInspect(guid) end,
        -- Every want takes the short try budget, so a teammate is never asked
        -- more often for the tracker than other owners ask on their own.
        OnlyStale = function() return true end,
        OnRead = function(guid, _, snapshot) KT:OnInspectRead(guid, snapshot) end,
        OnChanged = function(guid, snapshot) KT:OnInspectChanged(guid, snapshot) end,
    })
end

-- The teammates, party1 to party4, while the tracker is active: a new list
-- each time, since the inspector reads the entries live and never writes them.
function KT:UpdateInspectDemand()
    local handle = self.inspectHandle
    if not handle then return end
    if not self.isActive then
        handle:SetDemand(nil)
        return
    end
    local list = {}
    for i = 1, 4 do
        local unit = "party" .. i
        for guid, member in pairs(self.partyMembers) do
            if member.unit == unit then list[#list + 1] = { guid = guid, unit = unit } end
        end
    end
    handle:SetDemand(list)
end

-- A teammate is wanted until their spec and their kick's talents are read
-- (KT.InspectWanted).
function KT:WantsInspect(guid)
    local member = self.partyMembers[guid]
    if not member or member.unit == "player" or not self.inspectHandle then return false end
    local snap = self.inspectHandle:Get(guid)
    local spec = snap and snap.spec
    local demand = (type(spec) == "number" and spec > 0) and KE:GetKickTalentDemand(spec) or nil
    return KT.InspectWanted(snap, demand, member.inspectRespec, member.inspectMisses)
end

-- Inside the inspector's answer: the rank read, and nothing else. The answer
-- settles a respec; a failed read counts toward KT.InspectWanted's limit,
-- except one that waits for combat's end.
function KT:OnInspectRead(guid, snapshot)
    local handle = self.inspectHandle
    local member = self.partyMembers[guid]
    if not handle or not member then return end
    local spec = snapshot and snapshot.spec
    if type(spec) ~= "number" or spec <= 0 then return end
    member.inspectRespec = nil
    if member.specID ~= spec then member.inspectMisses = nil end
    local demand = KE:GetKickTalentDemand(spec)
    if not next(demand) then return end
    local ranks, reason = handle:ReadRanks(guid, spec, demand)
    if ranks then
        member.inspectMisses = nil
    elseif reason ~= "combat" then
        member.inspectMisses = (member.inspectMisses or 0) + 1
    end
end

-- After the answer: the row follows the inspected spec, and the snapshot
-- gives the talent ranks (KT.SnapshotRank).
function KT:OnInspectChanged(guid, snapshot)
    local member = self.partyMembers[guid]
    if not self.isActive or not member or member.unit == "player" then return end
    local spec = snapshot and snapshot.spec
    if type(spec) ~= "number" or spec <= 0 then return end
    self:ApplySpecKick(member, spec, snapshot)
    self:UpdateBars()
    self:LayoutBars()
end

-- A teammate's respec keeps them wanted until the next answer, marks their
-- snapshot stale and wakes the queue. Their row keeps its last spec, with its
-- talents unknown, until the re-read.
function KT:RefreshInspectedSpec(unit)
    local handle = self.inspectHandle
    if not handle or not self.isActive or issecretvalue(unit) or type(unit) ~= "string" then return end
    if not string_find(unit, "^party[1-4]$") then return end
    local guid = KE:GetSafeUnitGUID(unit)
    local member = guid and self.partyMembers[guid]
    if not member then return end
    member.inspectRespec, member.inspectMisses = true, nil
    handle:Refresh(guid, "spec")
    handle:Wake()
end

---------------------------------------------------------------------------------
-- Self Kick Confirmation
---------------------------------------------------------------------------------
-- duration: the clock's length, nil for KT:ClockDuration's. remaining: a
-- cooldown already under way.
function KT:ConfirmKick(guid, duration, remaining)
    local member = self.partyMembers[guid]
    if not member or not member.interruptData then return end

    duration = duration or self:ClockDuration(member, false)
    member.kickDuration = duration
    member.kickStart = GetTime() - (remaining and (duration - remaining) or 0)

    -- Immediately update bar visuals so the transition from ready→cooling is instant
    local bar = self.activeBars[guid]
    if bar then
        local isDark = self.db.ColorMode == "dark"
        self:StartBarTimer(bar, member.kickStart, member.kickDuration)
        -- Drawn as cooling; the next pass redraws it if an extra kick is up.
        bar.rowKick, bar.rowReady = nil, false
        self:ApplyBarColor(bar, member, true)
        bar.iconTex:SetDesaturated(true)
        -- Dark mode: white name while cooling
        if isDark and bar.nameText then
            bar.nameText:SetTextColor(1, 1, 1, 1)
        end
        if self.db.ShowTimer and bar.timerText then
            SetTimerText(bar, FormatRemaining(remaining or member.kickDuration))
        end
    end

    self:LayoutBars()
end

function KT:RefreshMemberRow(guid)
    local bar = self.activeBars[guid]
    if bar then self:UpdateBarVisuals(bar, self.partyMembers[guid]) end
    self:LayoutBars()
end

function KT:ClearKick(guid)
    local member = self.partyMembers[guid]
    if not member then return end
    member.kickStart = nil
    member.kickDuration = nil
    self:RefreshMemberRow(guid)
end

---------------------------------------------------------------------------------
-- Teammate kicks: rows and nameplate interrupts
---------------------------------------------------------------------------------
-- A readable kicker is charged at once; a hidden one's interrupt waits for
-- the meter update that names its kicker (KickTrackerMeter.lua).

-- Display-only values of a kicked cast; each may be secret.
local function InterruptedSpellIcon(spellID)
    if not (issecretvalue(spellID) or spellID ~= nil) then return nil end
    local ok, tex = pcall(C_Spell.GetSpellTexture, spellID)
    if ok then return tex end
    return nil
end

-- The mob's raid marker now; the nameplate token is never kept.
local function RaidMarkOf(unit)
    local ok, index = pcall(GetRaidTargetIndex, unit)
    if ok and (issecretvalue(index) or index ~= nil) then return index, true end
    return nil, false
end

local function KickedFrom(entry)
    return { icon = entry.iconID, mark = entry.raidMark, hasMark = entry.hasRaidMark }
end
KT.KickedFrom = KickedFrom

-- A nameplate UNIT_SPELLCAST_INTERRUPTED with a non-nil interruptedBy is ground
-- truth that someone's kick landed. The kicker's token sorts it
-- (KT.ClassifyKicker): the player's own goes on the own row, a teammate the
-- game names plainly is charged at once, and a hidden kicker's joins the plate
-- batch the next meter update names (KT:QueueHiddenPlate).
function KT:HandleNameplateInterrupt(unit, spellID, interruptedBy)
    if not self.db.Enabled or self.isPreview or not self.isActive then return end
    -- The payload may be secret while unit spellcasts are restricted; a
    -- secret unit is never tested.
    if issecretvalue(unit) or not unit or not string_find(unit, "^nameplate") then return end
    if not (issecretvalue(interruptedBy) or interruptedBy ~= nil) then return end  -- channel ended naturally, not kicked

    -- A friendly nameplate's cast stopped by an enemy is no party kick.
    local okAttack, canAttack = pcall(UnitCanAttack, "player", unit)
    if KT.RefusesInterruptUnit(okAttack, canAttack, issecretvalue(canAttack)) then return end

    local now = GetTime()
    if KT.SameInterrupt(self.lastEventAt, unit, now, SAME_FRAME) then return end
    self.lastEventAt[unit] = now

    -- The token can read plain ("party1") while the GUID is secret, so the
    -- token is sorted first; the GUID is compared only when plain.
    local ok, token = pcall(UnitTokenFromGUID, interruptedBy)
    local guidSecret = issecretvalue(interruptedBy)
    if DEBUG_KT then
        KE:Print(string_format("[KT] nameplate interrupt unit=%s tokenOk=%s token=%s guidSecret=%s",
            tostring(unit), tostring(ok), issecretvalue(token) and "secret" or tostring(token),
            tostring(guidSecret)))
    end
    local kind, index = KT.ClassifyKicker(ok, token, issecretvalue(token), guidSecret)
    local mark, hasMark = RaidMarkOf(unit)
    local entry = {
        startTime = now,
        iconID = InterruptedSpellIcon(spellID),  -- possibly secret; SetTexture-only
        raidMark = mark,                          -- possibly secret; SetSpriteSheetCell-only
        hasRaidMark = hasMark,
    }

    if kind == "own" then
        local kicked = KickedFrom(entry)
        -- The own cast's readable claim, not the meter's own-pending stamp: a
        -- meter credit may already have cleared that.
        if KT.TakeOwnClaim(self.ownClaim, now, OWN_KICK_MATCH_WINDOW) then
            self:ShowKicked(UnitGUID("player"), kicked)
        else
            -- A readable own interrupt with no cast before it belongs to the
            -- cast still to come.
            self._ownEarlyLandingAt, self._ownEarlyKicked = now, kicked
        end
        self._ownPending = false
        self._ownLandedAt = now
        self:ExpectMeter("player", UnitGUID("player"), now)
        self:TryOwnReduction()
        return
    end

    local guid
    if kind == "member" then
        guid = UnitGUID("party" .. index)
    elseif kind == "guid" then
        guid = self:RosterKicker(interruptedBy)
    else
        self:QueueHiddenPlate(entry, now)
        return
    end
    local member = guid and self.partyMembers[guid]
    -- A kicker outside the party has no row and no meter list.
    if not member then
        if DEBUG_KT then KE:Print("[KT] readable kicker outside the party: dropped") end
        return
    end
    if member.interruptData then self:ChargeKick(entry, guid) end
    self:ExpectMeter(member.unit, guid, now)
    if DEBUG_KT then KE:Print("[KT] readable teammate: " .. kind) end
end

-- The roster member a plain kicker GUID belongs to: a teammate, or the owner
-- of a party pet. Only plain GUIDs are compared.
function KT:RosterKicker(interrupterGuid)
    if not KE:IsSafeValue(interrupterGuid) then return nil end
    local member = self.partyMembers[interrupterGuid]
    if member then
        if member.unit == "player" then return nil end
        return interrupterGuid
    end
    for i = 1, 4 do
        local petGuid = UnitGUID("partypet" .. i)
        if KE:IsSafeValue(petGuid) and petGuid == interrupterGuid then
            local ownerGuid = UnitGUID("party" .. i)
            if ownerGuid and self.partyMembers[ownerGuid] then return ownerGuid end
        end
    end
    return nil
end

-- A teammate's kick on their own row, timed from the interrupt, with the
-- duration of a confirmed success. Returns true when it charged.
function KT:ChargeKick(entry, guid)
    local member = self.partyMembers[guid]
    if not member or not member.interruptData then return false end
    self:ReleaseLayers(guid, entry.startTime)
    local cd = self:ClockDuration(member, true)
    local remaining = cd - (GetTime() - entry.startTime)
    if remaining <= 0 then return false end
    self:ConfirmKick(guid, cd, remaining)
    self:ShowKicked(guid, KickedFrom(entry))
    return true
end

-- A row shows the spell its kick interrupted, and its marker, while the kick
-- cools (KT:UpdateBarVisuals). The member's next kick clears them.
function KT:ShowKicked(guid, kicked)
    local member = guid and self.partyMembers[guid]
    if not member then return end
    member.kicked = kicked
    self:RefreshMemberRow(guid)
end

-- ConfirmKick redraws only the cooling state, not the icon or the marker.
function KT:RedrawKicked(guid)
    local member, bar = self.partyMembers[guid], self.activeBars[guid]
    if member and (member.kicked or (bar and bar.kickedShown)) then self:RefreshMemberRow(guid) end
end

-- Drops the nameplate and meter state together, so none outlives the other.
function KT:ClearKickQueues()
    wipe(self.lastEventAt)
    self:ClearMeterState()
end

---------------------------------------------------------------------------------
-- Own kick success
---------------------------------------------------------------------------------

-- A kick the player cast and a nameplate interrupt credited to the player
-- are one success when they land within the window, in either order.
function KT:TryOwnReduction()
    if not KT.OwnKickMatched(self._ownKickAt, self._ownLandedAt, OWN_KICK_MATCH_WINDOW) then return end
    self._ownKickAt, self._ownLandedAt = nil, nil
    self:ApplyOwnSuccess()
end

-- A confirmed success takes the success rule's seconds off the running own
-- clock, once per cast: the one change to a clock already running. The
-- shorter cooldown is the own row's arithmetic, never a cooldown read.
function KT:ApplyOwnSuccess()
    if self._ownSucceeded then return end
    self._ownSucceeded = true
    local guid = UnitGUID("player")
    local member = guid and self.partyMembers[guid]
    local data = member and member.interruptData
    if not data then return end
    local seconds = self:OwnKickCooldown(data, false) - self:OwnKickCooldown(data, true)
    if seconds <= 0 then return end
    local duration = member.kickDuration
    local remaining = KT.ReducedRemaining(member.kickStart, duration, GetTime(), seconds)
    if not remaining then return end
    if remaining > 0 then
        self:ConfirmKick(guid, duration, remaining)
    else
        self:ClearKick(guid)
    end
end

---------------------------------------------------------------------------------
-- Event Handlers
---------------------------------------------------------------------------------
function KT:OnSpellcastInterrupted(_, unit, _, spellID, interruptedBy)
    self:HandleNameplateInterrupt(unit, spellID, interruptedBy)
end

-- Payload matches INTERRUPTED: (unitTarget, castGUID, spellID, interruptedBy).
-- The pre-rework handler read interruptedBy from the spellID slot (off-by-one,
-- masked by the old correlator's discard path) — fixed here.
function KT:OnChannelStop(_, unit, _, spellID, interruptedBy)
    self:HandleNameplateInterrupt(unit, spellID, interruptedBy)
end

-- Every own cast, main kick or extra kick: when this cast's readable
-- interrupt already arrived, its kicked spell is this cast's and nothing is
-- left to claim (returns true); otherwise the cast opens the claim a readable
-- own interrupt takes (KT.TakeOwnClaim).
function KT:ClaimOwnKick(now, member)
    local early, earlyKicked = self._ownEarlyLandingAt, self._ownEarlyKicked
    self._ownEarlyLandingAt, self._ownEarlyKicked = nil, nil
    if KT.OwnKickMatched(now, early, OWN_KICK_MATCH_WINDOW) then
        if member then member.kicked = earlyKicked end
        self.ownClaim.at = nil
        return true
    end
    if member then member.kicked = nil end
    self.ownClaim.at = now
    return false
end

-- A talent-added kick starts only when KT:GetOwnExtraKicks listed it; the
-- same spell without its talent is not a kick.
function KT:StartOwnExtraKick(guid, spellID)
    local member = self.partyMembers[guid]
    local list = member and member.extraKicks
    if not list then return end
    for i = 1, #list do
        local entry = list[i]
        if entry.id == spellID then
            entry.kickStart, entry.kickDuration = GetTime(), entry.cd
            self:ClaimOwnKick(entry.kickStart, member)
            self:RefreshMemberRow(guid)
            return
        end
    end
end

function KT:OnSpellcastSucceeded(_, unit, _, spellID)
    if not self.db.Enabled or self.isPreview or not self.isActive then return end
    -- The payload is secret while unit spellcasts are restricted, and a secret
    -- is never compared or used as a table key.
    if issecretvalue(unit) or issecretvalue(spellID) then return end
    if unit ~= "player" and unit ~= "pet" then return end

    -- Party members' casts do not fire this event for kicks at all —
    -- teammate detection lives in HandleNameplateInterrupt.
    local extra = KE:GetExtraKick(spellID)
    if not INTERRUPT_SPELL_IDS[spellID] and not extra then return end
    local guid = UnitGUID("player")
    if not guid then return end
    if extra then
        self:StartOwnExtraKick(guid, spellID)
        return
    end
    local kickID = KE:GetCanonicalKickSpell(spellID)
    local now = GetTime()
    -- Command Demon fires for both the player and the pet: one press, one kick.
    if KT.DuplicateOwnKick(self._lastOwnKickID, self._lastOwnKickAt, kickID, now, OWN_KICK_MATCH_WINDOW) then
        return
    end
    self._lastOwnKickID, self._lastOwnKickAt = kickID, now
    self._ownKickAt, self._ownSucceeded = now, nil
    local member = self.partyMembers[guid]
    -- Pending until the meter credits the player or OWN_WINDOW passes,
    -- unless this cast's readable interrupt already arrived.
    self._ownT = now
    self._ownPending = not self:ClaimOwnKick(now, member)
    local data = member and member.interruptData
    local kickCd = member and KE:GetKickCooldownForSpec(member.specID, kickID)
    if member and kickCd then
        -- A kick the player cast stays known until the demon or the spec
        -- changes; the spellbook check cannot undo it (KT.OwnKickFallback).
        if not (member.castKick and member.castKick.id == kickID) then
            member.castKick = { id = kickID, cd = kickCd }
        end
        -- A demon swap the events have not shown yet, or a demon kick the
        -- spellbook check missed: the kick just cast is the kick, and a
        -- missing row appears.
        if not data or data.id ~= kickID then
            data = KickRow(kickID, kickCd, member.specID, data and data.role)
            member.interruptData = data
            self:UpdateBars()
            self:LayoutBars()
        end
    end
    local cd = data and self:OwnKickCooldown(data, false)
    self:ConfirmKick(guid, cd)
    self:RedrawKicked(guid)
    self:TryOwnReduction()
end

---------------------------------------------------------------------------------
-- Combat Event Registration
---------------------------------------------------------------------------------
-- AceEvent-3.0 has no RegisterUnitEvent; a frame of its own lets the client
-- filter by unit. Only the own-kick event lives here: the interrupt events
-- stay on AceEvent because they must see every unit.
function KT:CreateCastFrame()
    if self.castFrame then return end
    local frame = CreateFrame("Frame")
    frame:SetScript("OnEvent", function(_, event, ...)
        if event == "UNIT_PET" then
            -- A new demon: the kick cast with the old one is no longer known.
            local guid = UnitGUID("player")
            local member = guid and self.partyMembers[guid]
            if member then member.castKick = nil end
            self:OnOwnKicksChanged()
        else
            self:OnSpellcastSucceeded(event, ...)
        end
    end)
    self.castFrame = frame
end

function KT:RegisterCombatEvents()
    if self.combatEventsRegistered then return end
    self:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED", "OnSpellcastInterrupted")
    self:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP", "OnChannelStop")
    self.castFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "pet")
    self.castFrame:RegisterUnitEvent("UNIT_PET", "player")
    self:RegisterEvent("SPELLS_CHANGED", "OnOwnKicksChanged")
    self:RegisterEvent("DAMAGE_METER_COMBAT_SESSION_UPDATED", "OnMeterUpdate")
    self:RegisterEvent("DAMAGE_METER_RESET", "OnMeterReset")
    self.combatEventsRegistered = true
end

function KT:UnregisterCombatEvents()
    if not self.combatEventsRegistered then return end
    self:UnregisterEvent("UNIT_SPELLCAST_INTERRUPTED")
    self:UnregisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
    if self.castFrame then self.castFrame:UnregisterAllEvents() end
    self:UnregisterEvent("SPELLS_CHANGED")
    self:UnregisterEvent("DAMAGE_METER_COMBAT_SESSION_UPDATED")
    self:UnregisterEvent("DAMAGE_METER_RESET")
    self.combatEventsRegistered = false

    self:ClearKickQueues()
end

---------------------------------------------------------------------------------
-- Environment Detection
---------------------------------------------------------------------------------
function KT:ShouldBeActive()
    if not self.db or not self.db.Enabled then return false end
    local inInstance, instanceType = IsInInstance()
    if not inInstance or instanceType ~= "party" then return false end
    if not IsInGroup() then return false end
    return true
end

function KT:CheckActivation()
    local shouldBeActive = self:ShouldBeActive()

    if shouldBeActive and not self.isActive then
        self.isActive = true
        -- A callback scheduled before a disable must not act in this activation.
        self.activationID = self.activationID + 1
        self._ownKickCheckPending = false
        -- A read or a cast cut off by a deactivation must not carry into this one.
        self._meterReadPending, self._ownPending = false, false
        self:RegisterCombatEvents()
        self:EnsureInspect()
        if self.containerFrame then
            self:ApplyContainerPosition()
            self.containerFrame:Show()
        end
        self:RefreshPartyRoster()
        -- The first read is the baseline: kicks before the activation are
        -- not credited.
        self:RebaseMeter()
    elseif not shouldBeActive and self.isActive then
        self.isActive = false
        self:UnregisterCombatEvents()  -- also clears the interrupt queues
        self:HideAllBars()
        if self.containerFrame then self.containerFrame:Hide() end
        wipe(self.partyMembers)
        self:UpdateInspectDemand()
    end
end

function KT:OnZoneChange()
    C_Timer.After(1, function()
        self:CheckActivation()
    end)
end

function KT:OnRosterUpdate()
    if self.isActive then
        self:RefreshPartyRoster()
    else
        self:CheckActivation()
    end
end

-- A demon swap, a talent change or a respec can change the player's kick
-- (KT:ApplyOwnKicks clears it). The live spec is read, so a
-- respec is applied here if this runs before OnPlayerSpecChanged. Most
-- SPELLS_CHANGED events change nothing and redraw nothing.
function KT:RefreshOwnKicks()
    local guid = UnitGUID("player")
    local member = guid and self.partyMembers[guid]
    if not member then return end
    local specID = GetPlayerSpecID()
    if not specID or specID == 0 then return end
    member.specID = specID
    local _, anyChanged = self:ApplyOwnKicks(member, specID)
    if not anyChanged then return end
    self:UpdateBars()
    self:LayoutBars()
end

-- UNIT_PET and SPELLS_CHANGED can arrive together; one check a frame later
-- reads the settled spellbook. The payloads are not read.
function KT:OnOwnKicksChanged()
    if self._ownKickCheckPending then return end
    self._ownKickCheckPending = true
    local activation = self.activationID
    C_Timer.After(0, function()
        if self.activationID ~= activation then return end
        self._ownKickCheckPending = false
        if self.isActive then self:RefreshOwnKicks() end
    end)
end

---------------------------------------------------------------------------------
-- Bar Creation & Pool
---------------------------------------------------------------------------------
function KT:CreateBar()
    local db = self.db
    local barFrame = CreateFrame("Frame", nil, self.containerFrame, "BackdropTemplate")
    barFrame:SetSize(db.BarWidth, db.BarHeight)
    barFrame:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    barFrame:SetBackdropBorderColor(0, 0, 0, 1)

    -- StatusBar (inset 1px for border)
    local statusBar = CreateFrame("StatusBar", nil, barFrame)
    statusBar:SetPoint("TOPLEFT", barFrame, "TOPLEFT", 1, -1)
    statusBar:SetPoint("BOTTOMRIGHT", barFrame, "BOTTOMRIGHT", -1, 1)
    local texPath = KE:GetStatusbarPath(db.StatusBarTexture or "KitnUI")
    statusBar:SetStatusBarTexture(texPath)
    statusBar:SetMinMaxValues(0, 1)
    statusBar:SetValue(1)
    barFrame.statusBar = statusBar

    -- Background texture for the unfilled portion
    local bgTex = statusBar:CreateTexture(nil, "BACKGROUND")
    bgTex:SetAllPoints()
    bgTex:SetTexture(texPath)
    bgTex:SetVertexColor(0.1, 0.1, 0.1, 0.8)
    barFrame.bgTex = bgTex

    -- Icon (inside the bar, overlapping the left/right edge)
    local iconFrame = CreateFrame("Frame", nil, statusBar)
    iconFrame:SetSize(db.IconSize, db.IconSize)
    iconFrame:SetFrameLevel(statusBar:GetFrameLevel() + 2)
    barFrame.iconFrame = iconFrame

    local iconBg = iconFrame:CreateTexture(nil, "BACKGROUND")
    iconBg:SetAllPoints()
    iconBg:SetColorTexture(0, 0, 0, 1)
    barFrame.iconBg = iconBg

    barFrame.iconTex = iconFrame:CreateTexture(nil, "ARTWORK")
    barFrame.nameText = statusBar:CreateFontString(nil, "OVERLAY")
    barFrame.timerText = statusBar:CreateFontString(nil, "OVERLAY")
    barFrame.raidMarkTex = statusBar:CreateTexture(nil, "OVERLAY")
    self:ApplyRegionDefaults(barFrame)

    barFrame:Hide()
    return barFrame
end

-- Every property CreateBar sets on a region once.
function KT:ApplyRegionDefaults(bar)
    local iconTex = bar.iconTex
    iconTex:SetDrawLayer("ARTWORK")
    iconTex:ClearAllPoints()
    iconTex:SetPoint("TOPLEFT", bar.iconFrame, "TOPLEFT", 1, -1)
    iconTex:SetPoint("BOTTOMRIGHT", bar.iconFrame, "BOTTOMRIGHT", -1, 1)
    iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    bar.nameText:SetDrawLayer("OVERLAY")
    bar.nameText:SetJustifyH("LEFT")

    bar.timerText:SetDrawLayer("OVERLAY")
    bar.timerText:SetJustifyH("RIGHT")
    bar.timerText:ClearAllPoints()
    bar.timerText:SetPoint("RIGHT", bar.statusBar, "RIGHT", -2, 0)

    bar.raidMarkTex:SetDrawLayer("OVERLAY")
    bar.raidMarkTex:ClearAllPoints()
    bar.raidMarkTex:SetPoint("LEFT", bar.nameText, "RIGHT", 3, 0)
    bar.raidMarkTex:SetTexture(RAID_MARK_SHEET)
    bar.raidMarkTex:Hide()
end

-- Member rows draw a kicked spell's icon and mark, which may be secret
-- (KT:ShowKicked). SetToDefaults clears a text or texture region's secret
-- state before the bar serves another row. Resetting the status bar would
-- drop its layout, so it is only stopped and re-colored; its color may stay
-- secret, and nothing reads it back.
function KT:ResetBarRegions(bar)
    bar.nameText:SetToDefaults()
    bar.timerText:SetToDefaults()
    bar.iconTex:SetToDefaults()
    bar.raidMarkTex:SetToDefaults()
    self:StopBarTimer(bar, 0)
    bar.statusBar:SetStatusBarColor(1, 1, 1, 1)
    bar.lastTimerText = nil
    bar.rowKick, bar.rowReady = nil, false
    bar.kickedShown = nil
    self:ApplyRegionDefaults(bar)
end

-- The raid marker sits in the name's slot, so it follows ShowName. The
-- marker index may be secret: it is only handed to the C-side sprite-sheet
-- call, shown when that call succeeds.
function KT:ApplyNameMarks(bar, raidMark, hasRaidMark)
    local db = self.db
    local markShown = false
    if hasRaidMark and db.ShowName then
        bar.raidMarkTex:SetSize(db.FontSize, db.FontSize)
        bar.raidMarkTex:SetTexture(RAID_MARK_SHEET)
        markShown = pcall(bar.raidMarkTex.SetSpriteSheetCell, bar.raidMarkTex, raidMark, 4, 4)
    end
    bar.raidMarkTex:SetShown(markShown)
end

function KT:GetOrCreateBar(guid)
    if self.activeBars[guid] then
        return self.activeBars[guid]
    end

    -- Try pool first
    local bar = table.remove(self.barPool)
    if not bar then
        bar = self:CreateBar()
    end

    self.activeBars[guid] = bar
    self:_RefreshOnUpdate()
    return bar
end

function KT:ReleaseBar(guid)
    local bar = self.activeBars[guid]
    if not bar then return end
    self:ReleaseLayers(guid)

    bar:Hide()
    bar:SetScript("OnUpdate", nil)
    self:ResetBarRegions(bar)

    self.activeBars[guid] = nil
    table_insert(self.barPool, bar)
    self:_RefreshOnUpdate()
end

function KT:HideAllBars()
    -- Collect GUIDs first to avoid modifying table during iteration
    local guids = {}
    for guid in pairs(self.activeBars) do
        guids[#guids + 1] = guid
    end
    for _, guid in ipairs(guids) do
        self:ReleaseBar(guid)
    end
    wipe(self.sortedBars)
end

---------------------------------------------------------------------------------
-- Bar Visual Updates
---------------------------------------------------------------------------------
-- C_ClassColor.GetClassColor accepts a secret classFilename and may return
-- secret r/g/b. Apply them verbatim; never compare them or compute a shade.
local function GetClassColor(classToken)
    if not classToken then return nil end
    return C_ClassColor.GetClassColor(classToken)
end

local zeroDuration

-- The engine drains (dark) or fills (class color) the bar from a plain start
-- and duration; no Lua runs per frame for the fill.
function KT:StartBarTimer(bar, startTime, duration)
    local d = C_DurationUtil.CreateDuration()
    d:SetTimeFromStart(startTime, duration)
    local direction = (self.db.ColorMode == "dark") and Enum.StatusBarTimerDirection.RemainingTime
        or Enum.StatusBarTimerDirection.ElapsedTime
    bar.statusBar:SetTimerDuration(d, Enum.StatusBarInterpolation.Immediate, direction)
    -- A countdown needs the container pass, which detaches when idle.
    self:StartOnUpdate()
end

-- A zero duration stops the engine drive; the bar then holds `value`.
function KT:StopBarTimer(bar, value)
    if not zeroDuration then zeroDuration = C_DurationUtil.CreateDuration() end
    bar.statusBar:SetTimerDuration(zeroDuration, Enum.StatusBarInterpolation.Immediate,
        Enum.StatusBarTimerDirection.ElapsedTime)
    bar.statusBar:SetMinMaxValues(0, 1)
    bar.statusBar:SetValue(value or 0)
end

-- Geometry + textures that depend only on db.
function KT:ApplyBarGeometry(bar)
    local db = self.db

    -- Size
    bar:SetSize(db.BarWidth, db.BarHeight)

    -- StatusBar texture
    local texPath = KE:GetStatusbarPath(db.StatusBarTexture or "KitnUI")
    bar.statusBar:SetStatusBarTexture(texPath)
    if bar.bgTex then
        bar.bgTex:SetTexture(texPath)
        bar.bgTex:SetVertexColor(unpack(db.BackgroundColor))
    end

    -- Icon (inside bar, left or right edge)
    local iconSize = db.BarHeight  -- match bar height for flush fit
    bar.iconFrame:SetSize(iconSize, iconSize)
    bar.iconFrame:ClearAllPoints()
    if db.IconSide == "RIGHT" then
        bar.iconFrame:SetPoint("RIGHT", bar, "RIGHT", 0, 0)
    else
        bar.iconFrame:SetPoint("LEFT", bar, "LEFT", 0, 0)
    end
    bar.iconFrame:SetShown(db.ShowIcon)

    -- Offset StatusBar: 1px border inset + icon area
    local b = 1 -- border width
    bar.statusBar:ClearAllPoints()
    if db.ShowIcon and db.IconSide == "LEFT" then
        bar.statusBar:SetPoint("TOPLEFT", bar, "TOPLEFT", iconSize, -b)
        bar.statusBar:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -b, b)
    elseif db.ShowIcon and db.IconSide == "RIGHT" then
        bar.statusBar:SetPoint("TOPLEFT", bar, "TOPLEFT", b, -b)
        bar.statusBar:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -iconSize, b)
    else
        bar.statusBar:SetPoint("TOPLEFT", bar, "TOPLEFT", b, -b)
        bar.statusBar:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -b, b)
    end

    -- Name text position (offset past icon)
    bar.nameText:ClearAllPoints()
    bar.nameText:SetPoint("LEFT", bar.statusBar, "LEFT", 2, 0)
end

function KT:UpdateBarVisuals(bar, member)
    local db = self.db
    local isDarkMode = db.ColorMode == "dark"

    -- A kicked spell's icon and marker may be secret: both regions start
    -- clean before the row draws again.
    if bar.kickedShown then
        bar.iconTex:SetToDefaults()
        bar.raidMarkTex:SetToDefaults()
        self:ApplyRegionDefaults(bar)
    end

    self:ApplyBarGeometry(bar)

    -- The kick that drives the row (KT.PickRowKick); nil is the main kick.
    local rowKick, isReady = nil, true
    if member then rowKick, isReady = KT.PickRowKick(member, GetTime()) end
    bar.rowKick, bar.rowReady = rowKick, isReady

    -- While the kick cools, the spell it interrupted (KT:ShowKicked).
    local kicked
    if member and not isReady then kicked = member.kicked end
    bar.kickedShown = kicked ~= nil

    if member and member.interruptData then
        if kicked and (issecretvalue(kicked.icon) or kicked.icon ~= nil) then
            pcall(bar.iconTex.SetTexture, bar.iconTex, kicked.icon)
        else
            local spellInfo = C_Spell.GetSpellInfo(rowKick and rowKick.id or member.interruptData.id)
            if spellInfo then
                bar.iconTex:SetTexture(spellInfo.iconID)
            else
                bar.iconTex:SetTexture(134400)
            end
        end
    end

    -- Name text
    KE:ApplyFont(bar.nameText, db.FontFace, db.FontSize, db.FontOutline)
    bar.nameText:SetShown(db.ShowName)
    if member then
        bar.nameText:SetText(member.name or "")
        if isDarkMode and isReady and member.classToken then
            local color = GetClassColor(member.classToken)
            if color then
                bar.nameText:SetTextColor(color.r, color.g, color.b, 1)
            else
                bar.nameText:SetTextColor(1, 1, 1, 1)
            end
        else
            bar.nameText:SetTextColor(1, 1, 1, 1)
        end
    end

    if kicked then
        self:ApplyNameMarks(bar, kicked.mark, kicked.hasMark)
    else
        self:ApplyNameMarks(bar)
    end

    -- Timer text
    KE:ApplyFont(bar.timerText, db.FontFace, db.FontSize, db.FontOutline)
    bar.timerText:SetShown(db.ShowTimer)
    bar.timerText:SetTextColor(1, 1, 1, 1)

    -- Icon desaturation (grayed out when on CD)
    bar.iconTex:SetDesaturated(not isReady)

    -- Bar color (ready state)
    if isReady then
        self:ApplyBarColor(bar, member, false)
        -- Dark mode: no fill visible (just dark background). Class mode: full bar.
        self:StopBarTimer(bar, isDarkMode and 0 or 1)
        if db.ShowTimer then
            if db.ShowReadyText and member then
                SetTimerText(bar, db.ReadyText or "Ready")
            else
                SetTimerText(bar, "")
            end
        end
    else
        self:ApplyBarColor(bar, member, true)
        -- The preview animates its own mock bars.
        local src = rowKick or member
        if src.kickDuration and not self.isPreview then
            self:StartBarTimer(bar, src.kickStart, src.kickDuration)
        end
    end

end

function KT:ApplyBarColor(bar, member, isCooling)
    local db = self.db
    local isDarkMode = db.ColorMode == "dark"

    if isDarkMode then
        -- Dark mode: cooling bars use class color (fill drains over time)
        -- Ready bars use SetValue(0) so fill color doesn't matter, but set it anyway
        if isCooling and member and member.classToken then
            local color = GetClassColor(member.classToken)
            if color then
                bar.statusBar:SetStatusBarColor(color.r, color.g, color.b, 1)
                return
            end
        end
        bar.statusBar:SetStatusBarColor(0.3, 0.3, 0.3, 1)
    elseif isCooling then
        if db.ClassColorCooling and member and member.classToken then
            local color = GetClassColor(member.classToken)
            if color then
                bar.statusBar:SetStatusBarColor(color.r, color.g, color.b, 1)
                return
            end
        end
        bar.statusBar:SetStatusBarColor(unpack(db.CoolingColor))
    else
        if member and member.classToken then
            local color = GetClassColor(member.classToken)
            if color then
                bar.statusBar:SetStatusBarColor(color.r, color.g, color.b, 1)
                return
            end
        end
        bar.statusBar:SetStatusBarColor(unpack(db.ReadyColor))
    end
end

---------------------------------------------------------------------------------
-- Bar Sorting & Layout
---------------------------------------------------------------------------------
function KT:GetRolePriority(member)
    if not member or not member.interruptData then return 999 end
    local role = member.interruptData.role
    local db = self.db
    if role == "TANK" then return db.SortTankPriority or 1 end
    if role == "HEALER" then return db.SortHealerPriority or 2 end
    return db.SortDPSPriority or 3
end

function KT:UpdateBars()
    if self.isPreview then return end

    -- Every member with a kick has a row (KT.RowShown).
    local needsBars = {}
    for guid, member in pairs(self.partyMembers) do
        if KT.RowShown(member) then
            needsBars[guid] = true
        end
    end

    for guid in pairs(self.activeBars) do
        if not needsBars[guid] then
            self:ReleaseBar(guid)
        end
    end

    -- Create/update bars for eligible members
    for guid in pairs(needsBars) do
        local member = self.partyMembers[guid]
        local bar = self:GetOrCreateBar(guid)
        self:UpdateBarVisuals(bar, member)
        bar:Show()
    end
end

-- Self-point = growth-derived vertical edge + horizontal edge from the active
-- position's AnchorFrom. Keeps the box/overlay aligned with the bars across a
-- growth flip while honoring the user's left/center/right anchor choice.
function KT:GetSelfPoint(pos)
    local vertical = (self.db.GrowthDirection == "UP") and "BOTTOM" or "TOP"
    local af = (pos and pos.AnchorFrom) or ""
    local horizontal = af:find("LEFT") and "LEFT" or (af:find("RIGHT") and "RIGHT" or "")
    return vertical .. horizontal
end

-- Active position context: "HEALER" or "DEFAULT". A GUI preview override
-- (previewContext, set while editing) wins; otherwise it's the live spec-driven
-- resolution (UseHealerPosition + healer spec). Single source of truth so the
-- live path, preview, and EditMode all agree on which position is active.
function KT:GetActiveContext()
    local db = self.db
    if not db then return "DEFAULT" end
    -- GUI-driven preview honors the configured context. previewContext mirrors
    -- the Default / Healer sub-tab; guiConfigContext is the persistent fallback because the
    -- PreviewManager can re-fire ShowPreview on section re-entry (after
    -- HidePreview cleared previewContext) before the page rebuilds. Only
    -- consulted while previewing — live play always uses live spec below.
    if self.isPreview and db.UseHealerPosition then
        local ctx = self.previewContext or self.guiConfigContext
        if ctx then return ctx end
    end
    if db.UseHealerPosition and KE:IsPlayerHealerSpec() then
        return "HEALER"
    end
    return "DEFAULT"
end

-- (pos, anchorFrameType, parentFrame, strata) for the active context.
function KT:ResolvePositionConfig()
    return KE:GetActivePositionConfig(self.db, self:GetActiveContext())
end

-- EditMode overlay label — name the context when healer override is on so a
-- drag obviously writes to the right table.
function KT:GetEditModeLabel()
    if self.db and self.db.UseHealerPosition then
        return (self:GetActiveContext() == "HEALER")
            and "Interrupt Tracker (Healer)" or "Interrupt Tracker (Default)"
    end
    return "Interrupt Tracker"
end

-- Re-register so the overlay label tracks the current context. Only meaningful
-- when healer override is on (label is constant otherwise).
function KT:RefreshEditMode()
    if not (KE.EditMode and self.containerFrame) then return end
    -- Re-register so the overlay label (GetEditModeLabel) reflects the current
    -- context — including reverting to plain "Interrupt Tracker" when the
    -- override is toggled off (don't early-out on UseHealerPosition here).
    if KE.EditMode.UnregisterElement then KE.EditMode:UnregisterElement("KickTracker") end
    self.editModeRegistered = false
    self:RegWithEditMode()
end

-- Position the container by its growth-derived self-point so the edit-mode
-- overlay (which spans the full bar stack) stays aligned with the bars when
-- growth flips. Resolves anchor manually (instead of KE:ApplyActivePosition)
-- so the stored AnchorFrom — which holds the horizontal choice — is preserved.
function KT:ApplyContainerPosition()
    if not self.containerFrame then return end
    local pos, aft, pf, strata = self:ResolvePositionConfig()
    local parent = KE:ResolveAnchorFrame(aft, pf, self.containerFrame, true)
    self.containerFrame:SetParent(parent)
    self.containerFrame:ClearAllPoints()
    self.containerFrame:SetPoint(self:GetSelfPoint(pos), parent,
        pos.AnchorTo or "CENTER", pos.XOffset or 0, pos.YOffset or 0)
    self.containerFrame:SetFrameStrata(strata or "MEDIUM")
    KE:SnapFrameToPixels(self.containerFrame)
end

function KT:LayoutBars()
    if not self.containerFrame then return end
    local db = self.db

    -- Build sorted list
    wipe(self.sortedBars)
    local coolingList = wipe(self._coolingList)
    local readyList = wipe(self._readyList)
    local now = GetTime()

    for guid, bar in pairs(self.activeBars) do
        local member = self.partyMembers[guid]
        if member then
            local rowKick, isReady = KT.PickRowKick(member, now)
            local src = rowKick or member
            if not isReady and src.kickDuration then
                local remaining = src.kickDuration - (now - src.kickStart)
                table_insert(coolingList, { guid = guid, bar = bar, member = member, remaining = remaining })
            else
                -- Clear an expired main cooldown; a main kick still cooling
                -- behind a ready extra kick keeps its time.
                if member.kickStart and member.kickDuration
                    and now - member.kickStart >= member.kickDuration then
                    member.kickStart = nil
                    member.kickDuration = nil
                end
                table_insert(readyList, { guid = guid, bar = bar, member = member })
            end
        end
    end

    -- Sort: ready bars by role priority, cooling bars by remaining time
    table_sort(readyList, function(a, b)
        local pa = self:GetRolePriority(a.member)
        local pb = self:GetRolePriority(b.member)
        if pa ~= pb then return pa < pb end
        return (a.guid or "") < (b.guid or "")
    end)

    table_sort(coolingList, function(a, b)
        return a.remaining < b.remaining
    end)

    -- Ready bars first, then cooling
    for _, entry in ipairs(readyList) do
        table_insert(self.sortedBars, entry)
    end
    for _, entry in ipairs(coolingList) do
        table_insert(self.sortedBars, entry)
    end

    local growUp = db.GrowthDirection == "UP"
    local spacing = db.BarSpacing or 2
    local barHeight = db.BarHeight or 20

    -- Bars pin to the container's self-point (growth vertical edge + user
    -- horizontal edge) and stack inward, exactly filling the full-height container.
    local selfPoint = self:GetSelfPoint(self:ResolvePositionConfig())
    local slot = 0
    for _, entry in ipairs(self.sortedBars) do
        local bar = entry.bar
        bar:ClearAllPoints()
        local offset = slot * (barHeight + spacing)
        bar:SetPoint(selfPoint, self.containerFrame, selfPoint, 0, growUp and offset or -offset)
        bar:Show()
        slot = slot + 1
    end

    -- Size the container for every row, so the EditMode overlay spans the
    -- whole group.
    local n = ROW_SLOTS
    self.containerFrame:SetSize(db.BarWidth, barHeight * n + math_max(n - 1, 0) * spacing)
end

---------------------------------------------------------------------------------
-- OnUpdate (Cooldown Progress)
---------------------------------------------------------------------------------
function KT:StartOnUpdate()
    if self._onUpdateActive then return end
    if not self.containerFrame then return end
    self.containerFrame:SetScript("OnUpdate", function(_, elapsed)
        self:OnUpdateBars(elapsed)
    end)
    self._onUpdateActive = true
end

function KT:StopOnUpdate()
    if not self._onUpdateActive then return end
    if self.containerFrame then
        self.containerFrame:SetScript("OnUpdate", nil)
    end
    self._onUpdateActive = false
end

-- A new bar attaches the pass, whose first run decides whether it is needed;
-- no bar detaches it. KT:OnUpdateBars also detaches it when idle. Call after
-- every mutation of activeBars.
function KT:_RefreshOnUpdate()
    if next(self.activeBars) then
        self:StartOnUpdate()
    else
        self:StopOnUpdate()
    end
end

function KT:OnUpdateBars(elapsed)
    self._updateAccum = (self._updateAccum or 0) + elapsed
    if self._updateAccum < 0.05 then return end
    self._updateAccum = 0

    local db = self.db
    local now = GetTime()
    local needsRelayout = false
    local anyCooling = false
    local busy = false  -- a row's main kick runs: its row can still change

    if DEBUG_KT_TICKS then
        _ktContainerTickCounter = _ktContainerTickCounter + 1
        if _ktContainerTickCounter >= KT_TICK_LOG_EVERY then
            _ktContainerTickCounter = 0
            local activeCount = 0
            for _ in pairs(self.activeBars) do activeCount = activeCount + 1 end
            KE:Print(string.format("[KT] OnUpdateBars tick: activeBars=%d isPreview=%s",
                activeCount, tostring(self.isPreview)))
        end
    end

    -- The engine draws every fill; this pass only expires cooldowns and
    -- writes the countdown text when it changes. All arithmetic here is our
    -- own GetTime() math: plain values, no secrets.
    for guid, bar in pairs(self.activeBars) do
        local member = self.partyMembers[guid]
        if member and member.interruptData then
            local rowKick, isReady = KT.PickRowKick(member, now)
            if member.kickStart and member.kickDuration and now - member.kickStart < member.kickDuration then
                busy = true
            end
            if isReady ~= bar.rowReady or rowKick ~= bar.rowKick then
                self:UpdateBarVisuals(bar, member)
                needsRelayout = true
            end
            local src = rowKick or member
            if not isReady and src.kickDuration then
                anyCooling = true
                if db.ShowTimer then
                    SetTimerText(bar, FormatRemaining(src.kickDuration - (now - src.kickStart)))
                end
            end
        end
    end

    -- Periodic re-sort every 1s while cooling
    if anyCooling then
        self._lastSortUpdate = self._lastSortUpdate or 0
        if now - self._lastSortUpdate >= 1.0 then
            self._lastSortUpdate = now
            needsRelayout = true
        end
    else
        self._lastSortUpdate = nil
    end

    if needsRelayout then
        self:LayoutBars()
    end

    if self:TickLayers(now) then busy = true end

    -- Idle: no main kick or layer running, so nothing can change until a
    -- countdown starts or a bar is made, and each of those attaches this again.
    if not busy then self:StopOnUpdate() end
end

---------------------------------------------------------------------------------
-- Frame Creation
---------------------------------------------------------------------------------
function KT:CreateFrames()
    if self.containerFrame then return end

    local frame = CreateFrame("Frame", "KE_KickTracker", UIParent)
    frame:SetSize(1, 1)
    frame:SetFrameStrata(self.db.Strata or "HIGH")
    frame:SetClampedToScreen(true)
    self.containerFrame = frame

    -- Through ResolvePositionConfig, not the raw db key: the healer override
    -- can put a different anchor type on each context.
    KE:RegisterAnchorRepair(frame,
        function()
            local _, aft = self:ResolvePositionConfig()
            return aft == "PLAYERFRAME"
        end,
        function() self:ApplyContainerPosition() end)
end

---------------------------------------------------------------------------------
-- Preview / Edit Mode
---------------------------------------------------------------------------------
function KT:ShowPreview()
    if DEBUG_KT then
        local activeCount = 0
        for _ in pairs(self.activeBars) do activeCount = activeCount + 1 end
        KE:Print(string.format("[KT] ShowPreview enter, activeBars=%d isPreview=%s",
            activeCount, tostring(self.isPreview)))
    end
    if not self.containerFrame then
        self:CreateFrames()
    end
    self:RegWithEditMode()

    self.isPreview = true
    self:HideAllBars()
    -- Drop the live interrupt lists too, so nothing charges or hands back a
    -- row while the preview holds the bars.
    self:ClearKickQueues()

    self:ApplyContainerPosition()

    -- Create 5 mock bars: 3 ready + 2 cooling
    local previewData = {
        { name = UnitName("player"), classToken = select(2, UnitClass("player")), spellID = 1766, ready = true },
        { name = "Warrior", classToken = "WARRIOR", spellID = 6552, ready = true },
        { name = "Mage", classToken = "MAGE", spellID = 2139, ready = true },
        { name = "Hunter", classToken = "HUNTER", spellID = 147362, ready = false, remaining = 8.2, cd = 24 },
        { name = "Shaman", classToken = "SHAMAN", spellID = 57994, ready = false, remaining = 3.7, cd = 12 },
    }

    local db = self.db
    local growUp = db.GrowthDirection == "UP"
    local spacing = db.BarSpacing or 2
    local barHeight = db.BarHeight or 20
    local previewSelfPoint = self:GetSelfPoint(self:ResolvePositionConfig())

    for i, data in ipairs(previewData) do
        -- Reuse via the pool (keyed like live bars) — direct CreateBar here
        -- stranded 5 frames per preview cycle since HideAllBars had just
        -- pooled the previous set.
        local bar = self:GetOrCreateBar("preview_" .. i)
        local fakeMember = {
            name = data.name,
            classToken = data.classToken,
            interruptData = { id = data.spellID, cd = data.cd or 15, role = "DAMAGER" },
            kickStart = (not data.ready) and GetTime() or nil,
        }
        self:UpdateBarVisuals(bar, fakeMember)

        local isDark = db.ColorMode == "dark"
        if data.ready then
            bar.statusBar:SetValue(isDark and 0 or 1)
        else
            local elapsed = data.cd - data.remaining
            -- Dark mode: drain from full to empty. Class mode: fill from empty to full.
            if isDark then
                bar.statusBar:SetValue(data.remaining / data.cd)
            else
                bar.statusBar:SetValue(elapsed / data.cd)
            end
            -- White name while cooling in dark mode
            if isDark and bar.nameText then bar.nameText:SetTextColor(1, 1, 1, 1) end
            KT:ApplyBarColor(bar, fakeMember, true)

            -- Animate the cooling bars
            local startTime = GetTime() - elapsed
            local cdDuration = data.cd
            -- Per-cooling-bar gating state. Closure captures these as fresh
            -- upvalues per OnUpdate attachment so each bar tracks its own
            -- last-applied value/string. Pixel-aware SetValue + last-string
            -- SetText match the patterns used elsewhere in KE
            -- (DungeonTimers OnVisualUpdate, status bars).
            local barWidth = (db.BarWidth or 200)
            if barWidth < 1 then barWidth = 1 end
            local pixelRatio = 1 / barWidth
            local lastBarValue
            local lastTimerStr
            bar:SetScript("OnUpdate", function(self)
                local now = GetTime()
                local rem = cdDuration - (now - startTime)
                if rem <= 0 then
                    if DEBUG_KT then
                        KE:Print(string.format("[KT] cooling bar EXPIRE name=%s",
                            tostring(fakeMember.name)))
                    end
                    self:SetScript("OnUpdate", nil)
                    -- Restore ready state
                    fakeMember.kickStart = nil
                    KT:UpdateBarVisuals(bar, fakeMember)
                    return
                end
                if DEBUG_KT_TICKS then
                    _ktCoolingTickCounter = _ktCoolingTickCounter + 1
                    if _ktCoolingTickCounter >= KT_COOLING_LOG_EVERY then
                        _ktCoolingTickCounter = 0
                        KE:Print(string.format("[KT] cooling tick name=%s rem=%.2f",
                            tostring(fakeMember.name), rem))
                    end
                end
                local newValue
                if isDark then
                    newValue = rem / cdDuration
                else
                    newValue = (now - startTime) / cdDuration
                end
                if not lastBarValue or math_abs(newValue - lastBarValue) >= pixelRatio then
                    bar.statusBar:SetValue(newValue)
                    lastBarValue = newValue
                end
                if db.ShowTimer and bar.timerText then
                    local newStr
                    if rem > 6 then
                        newStr = string_format("%d", math_floor(rem))
                    else
                        newStr = string_format("%.1f", rem)
                    end
                    if newStr ~= lastTimerStr then
                        bar.timerText:SetText(newStr)
                        lastTimerStr = newStr
                    end
                end
            end)
        end

        bar:ClearAllPoints()
        -- Pin to the container's self-point (matches LayoutBars) so preview bars
        -- align with the full-height container and the edit-mode overlay.
        local offset = (i - 1) * (barHeight + spacing)
        bar:SetPoint(previewSelfPoint, self.containerFrame, previewSelfPoint, 0, growUp and offset or -offset)
        bar:Show()
    end

    -- Size the container as KT:LayoutBars does: every row.
    local nPrev = ROW_SLOTS
    self.containerFrame:SetSize(db.BarWidth, barHeight * nPrev + math_max(nPrev - 1, 0) * spacing)
    self.containerFrame:Show()
    self:_RefreshOnUpdate()
end

function KT:HidePreview()
    if DEBUG_KT then
        local activeCount = 0
        for _ in pairs(self.activeBars) do activeCount = activeCount + 1 end
        KE:Print(string.format("[KT] HidePreview enter, activeBars=%d", activeCount))
    end
    self.isPreview = false
    self.previewContext = nil  -- resume live spec-driven resolution
    if not self.containerFrame then return end

    self:HideAllBars()

    if self.isActive then
        self:RefreshPartyRoster()
    else
        self.containerFrame:Hide()
    end
end

function KT:RegWithEditMode()
    if KE.EditMode and not self.editModeRegistered then
        KE.EditMode:RegisterElement({
            key = "KickTracker",
            module = self,
            displayName = self:GetEditModeLabel(),
            frame = self.containerFrame,
            getPosition = function()
                local pos = self:ResolvePositionConfig()
                return pos
            end,
            setPosition = function(pos)
                -- Write to the SAME context getPosition reads (no get/set drift).
                if self:GetActiveContext() == "HEALER" then
                    self.db.HealerPosition = pos
                else
                    self.db.Position = pos
                end
                self:ApplyContainerPosition()
            end,
            -- Self-point = growth vertical edge + user horizontal edge, so drag +
            -- overlay use the same fixed edge as the bars (aligned across a flip).
            getAnchorFrom = function()
                return self:GetSelfPoint((self:ResolvePositionConfig()))
            end,
            getParentFrame = function()
                local _, aft, pf = self:ResolvePositionConfig()
                return KE:ResolveAnchorFrame(aft, pf)
            end,
            guiPath = "KicksCasts",
            guiTab = "KickTracker",
        })
        self.editModeRegistered = true
    end
end

---------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------
function KT:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

function KT:OnEnable()
    if not self.db.Enabled then return end

    self:CreateFrames()
    self:CreateCastFrame()
    self:RegWithEditMode()

    self:RegisterEvent("GROUP_ROSTER_UPDATE", "OnRosterUpdate")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnZoneChange")
    self:RegisterEvent("ZONE_CHANGED_NEW_AREA", "OnZoneChange")
    self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", "OnPlayerSpecChanged")

    -- OnUpdate is gated by _RefreshOnUpdate based on activeBars membership.
    -- It attaches the first time a bar is created (group entered, party
    -- inspected, or preview shown) and detaches when the last bar releases.

    C_Timer.After(0.5, function()
        self:ApplySettings()
        self:CheckActivation()
    end)
end

function KT:OnDisable()
    self:UnregisterAllEvents()
    if self.castFrame then self.castFrame:UnregisterAllEvents() end
    self.combatEventsRegistered = false
    self:CancelAllTimers()
    self:StopOnUpdate()

    self:ClearKickQueues()
    self:HideAllBars()
    wipe(self.partyMembers)
    if self.inspectHandle then
        self.inspectHandle:Release()
        self.inspectHandle = nil
    end

    self.isActive = false
    self.isPreview = false

    if self.containerFrame then self.containerFrame:Hide() end
end

function KT:ApplySettings()
    self:UpdateDB()
    -- A layer copies the bar's settings when it is made.
    self:ReleaseAllLayers()
    if not self.containerFrame then return end

    self:ApplyContainerPosition()

    -- Re-apply visuals to all active bars
    for guid, bar in pairs(self.activeBars) do
        local member = self.partyMembers[guid]
        if member then
            self:UpdateBarVisuals(bar, member)
        end
    end
    self:LayoutBars()

    if self.isPreview then
        self:ShowPreview()
    end
end
