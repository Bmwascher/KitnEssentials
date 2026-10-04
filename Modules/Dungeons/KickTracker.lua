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
local UnitNameFromGUID = UnitNameFromGUID
local UnitClassFromGUID = UnitClassFromGUID
local UnitTokenFromGUID = UnitTokenFromGUID
local GetRaidTargetIndex = GetRaidTargetIndex
local GetSpecializationInfoForSpecID = GetSpecializationInfoForSpecID
local issecretvalue = issecretvalue
local GetNormalizedRealmName = GetNormalizedRealmName
local string_find = string.find
local string_format = string.format
local math_floor = math.floor
local math_abs = math.abs
local math_max = math.max
local math_random = math.random
local pairs = pairs
local ipairs = ipairs
local wipe = wipe
local table_insert = table.insert
local table_sort = table.sort

-- LibSpecialization: passive group spec/role tracking via addon comms.
-- Replaces the prior CanInspect/NotifyInspect/INSPECT_READY plumbing
-- (~75 lines of throttle/queue management). Optional load — module
-- degrades to "no party member specs known until you re-zone with the
-- lib loaded" if absent.
local LibSpec = LibStub("LibSpecialization", true)

---------------------------------------------------------------------------------
-- Interrupt Database
---------------------------------------------------------------------------------
-- Spec kicks live in Core/Interrupts.lua. An own cast of any of these starts
-- the player's kick cooldown.
local INTERRUPT_SPELL_IDS = KE:GetInterruptKickSpellSet()

-- Class-default kicks for members whose spec is still unknown (teammates
-- without a LibSpec-carrying addon never broadcast their spec). Values match
-- Core/Interrupts.lua; where specs differ the lowest CD wins.
-- allRoles = every spec of the class has this kick; otherwise only a
-- DAMAGER/TANK role assignment proves a kicking spec. Healer shamans keep
-- Wind Shear at its 30s CD.
local CLASS_FALLBACK_INTERRUPTS = {
    DEATHKNIGHT = { id = 47528,  cd = 12, allRoles = true },
    DEMONHUNTER = { id = 183752, cd = 15, allRoles = true },
    DRUID       = { id = 106839, cd = 15 },
    EVOKER      = { id = 351338, cd = 18 },
    HUNTER      = { id = 187707, cd = 15, allRoles = true },
    MAGE        = { id = 2139,   cd = 20, allRoles = true },
    MONK        = { id = 116705, cd = 15 },
    PALADIN     = { id = 96231,  cd = 15 },
    PRIEST      = { id = 15487,  cd = 30 },  -- Shadow only; a DPS role proves it
    ROGUE       = { id = 1766,   cd = 15, allRoles = true },
    SHAMAN      = { id = 57994,  cd = 12, allRoles = true, healerCd = 30 },
    WARLOCK     = { id = 19647,  cd = 24, allRoles = true },
    WARRIOR     = { id = 6552,   cd = 15, allRoles = true },
}

local KICK_RECORD_FALLBACK_DURATION = 15
local KICK_RECORD_GRACE = 0.4  -- records stay invisible this long so a comm
                               -- claim can discard them before they render
local HELLO_THROTTLE = 10
local KICK_PAIR_WINDOW = 1.5
local HELLO_REPLY_JITTER = 0.6
local RAID_MARK_SHEET = "Interface\\TargetingFrame\\UI-RaidTargetingIcons"
local OWN_KICK_MATCH_WINDOW = 0.5

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

KT.partyMembers = {}     -- [guid] = { unit, name, classToken, specID, interruptData, kickStart, kickDuration, kickVerified }
KT.nameSpecCache = {}    -- [playerName] = specID, fed by LibSpec.RegisterGroup callback

KT.kickRecords = {}       -- array of { id, name, iconID, colorR/G/B, startTime, duration } — teammate kick records
KT.nextRecordID = 0       -- monotonic; records keyed "record"..id in activeBars (GUIDs may be secret)

KT.barPool = {}           -- array of reusable bar frames
KT.activeBars = {}        -- [guid] = barFrame
KT.sortedBars = {}        -- ordered array for layout
KT._coolingList = {}      -- reusable temp table for LayoutBars
KT._readyList = {}        -- reusable temp table for LayoutBars

KT.isActive = false
KT.activationID = 0       -- bumped on each activation; deferred callbacks check it
KT.combatEventsRegistered = false
KT.commState = {}  -- commBlocked: a lockdown refusal since the last successful send
KT.kickPairing = { claims = {}, paired = {} }  -- keyed guid..":"..kickID; see KT.PairComm
KT.ownClaim = {}  -- at: the player's last kick cast; see KT:ClaimOwnKick

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

-- The spec's default kick, until a message has set or cleared the member's kick.
function KT:ApplySpecKick(member, specID)
    if not KT.KeepsMessageKick(member) then
        member.interruptData = self:GetInterruptDataForSpec(specID)
    end
    member.specID = specID
end

local function isTalentKnown(talentID)
    return C_SpellBook.IsSpellKnown(talentID) == true
end

-- The player's own kick cooldown with flat talent changes applied. KICK and
-- HELLO carry it, so receivers see the true cooldown.
function KT:OwnKickCooldown(data)
    return KT.TalentedCooldown(data.cd, KE:GetFlatKickTalents(data.id), isTalentKnown)
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
-- starts clear. Either way synced teammates hear the kick, or spell 0 for
-- none, at once; a change to the talent-added kick alone is announced too.
-- Returns whether the main kick changed, then whether anything the row shows
-- changed.
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
    local hello = KT.OwnKickHello(mainChanged, specChanged, extrasChanged)
    if hello then
        self:BroadcastHello(true, hello == "tell")
    end
    return mainChanged, mainChanged or specChanged or extrasChanged
end

-- Spec unknown (teammate without a LibSpec-carrying addon): the
-- safe-optimistic rule — assign the class-default kick only when it can't
-- be wrong (every spec of the class kicks, or a DPS/TANK role proves a
-- kicking spec; ambiguous healer/NONE stays hidden rather than showing a
-- phantom bar). Refined or cleared as soon as the real spec arrives.
function KT:GuessClassInterrupt(unit, classToken)
    -- IsSafeValue before the table key: plain today for party units, but a
    -- secret key would throw (parity with the name-cache guard above).
    local fallback = classToken and KE:IsSafeValue(classToken)
        and CLASS_FALLBACK_INTERRUPTS[classToken]
    if not fallback then return nil end

    local role = UnitGroupRolesAssigned(unit)
    if role == "HEALER" then
        if fallback.healerCd then
            return { id = fallback.id, cd = fallback.healerCd, role = "HEALER" }
        end
        if fallback.allRoles then
            return { id = fallback.id, cd = fallback.cd, role = "HEALER" }
        end
        return nil
    end
    if not fallback.allRoles and role ~= "DAMAGER" and role ~= "TANK" then
        return nil
    end
    return {
        id = fallback.id,
        cd = fallback.cd,
        role = (role == "TANK") and "TANK" or "DAMAGER",
    }
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
                local name, realm = UnitName(unit)
                local _, classToken = UnitClass(unit)

                if not self.partyMembers[guid] then
                    self.partyMembers[guid] = {}
                end
                local member = self.partyMembers[guid]
                member.unit = unit
                member.name = name
                member.classToken = classToken
                -- Identity is compared only through these plain fields;
                -- member.name is for display. The realm-qualified key keeps two
                -- teammates sharing a name apart when messages are matched.
                if KE:IsSafeValue(name) and not issecretvalue(realm) then
                    local raw = (realm and realm ~= "") and (name .. "-" .. realm) or name
                    member.fullKey = KE:BuildNicknameKey(raw, GetNormalizedRealmName())
                    member.shortName = name
                else
                    member.fullKey = nil
                    member.shortName = nil
                end

                -- Spec lookup: player via GetSpecialization (always reliable for
                -- self), party via the LibSpec name cache. If the cache hasn't
                -- yet been populated for this party member (e.g. they just
                -- joined and the comm hasn't arrived), specID stays 0 and the
                -- LibSpec callback will fill it in shortly via ApplySpecData.
                -- IsSafeValue mirrors HealerMana's pattern: UnitName for friendly
                -- party members hasn't been observed secret in M+, but a secret
                -- string used as a table key would silently miss every lookup.
                local specID = 0
                if unit == "player" then
                    specID = GetPlayerSpecID() or 0
                    -- Own kicks are always tracked — the bar may claim Ready
                    member.kickVerified = true
                elseif name and KE:IsSafeValue(name) then
                    specID = self.nameSpecCache[name] or 0
                end

                if specID > 0 then
                    if unit == "player" then
                        member.specID = specID
                        self:ApplyOwnKicks(member, specID)
                    else
                        self:ApplySpecKick(member, specID)
                    end
                elseif unit ~= "player" and not member.interruptData and not member.kickFromMessage then
                    -- No spec data yet — class-default fallback so the bar
                    -- exists at all (LibSpec/comm refinement overwrites it)
                    member.interruptData = self:GuessClassInterrupt(unit, classToken)
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

    self:UpdateBars()
    self:LayoutBars()
end

function KT:ApplySpecData(guid, unit, specID)
    local _, classToken = UnitClass(unit)
    local member = self.partyMembers[guid]
    if member then
        member.classToken = classToken
        if unit == "player" then
            member.specID = specID
            self:ApplyOwnKicks(member, specID)
        else
            self:ApplySpecKick(member, specID)
        end
        self:UpdateBars()
        self:LayoutBars()
    end
end

-- LibSpec group callback: per-member spec/role updates via addon comms. Find
-- the matching partyMembers entry by name and apply the spec. New members may
-- arrive here BEFORE GROUP_ROSTER_UPDATE has populated partyMembers — in that
-- case we just cache the spec and the next RefreshPartyRoster will read it.
function KT:OnLibSpecGroupUpdate(specID, _, _, playerName)
    if not specID or specID == 0 or not playerName then return end
    self.nameSpecCache[playerName] = specID

    if not self.isActive then return end
    for guid, member in pairs(self.partyMembers) do
        if member.shortName == playerName and member.unit ~= "player" then
            self:ApplySpecData(guid, member.unit, specID)
            return
        end
    end
end

function KT:OnPlayerSpecChanged()
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
-- Self Kick Confirmation
---------------------------------------------------------------------------------
-- durationOverride: comm-synced kicks carry the sender's exact CD; nil = spec CD.
-- remaining: a cooldown already under way (a HELLO's remaining time).
function KT:ConfirmKick(guid, durationOverride, remaining)
    local member = self.partyMembers[guid]
    if not member or not member.interruptData then return end

    local duration = durationOverride or member.interruptData.cd
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

-- The member's kick is ready again (a message said so).
function KT:ClearKick(guid)
    local member = self.partyMembers[guid]
    if not member then return end
    member.kickStart = nil
    member.kickDuration = nil
    self:RefreshMemberRow(guid)
end

---------------------------------------------------------------------------------
-- Teammate Kick Records (12.0.5 secret-safe)
---------------------------------------------------------------------------------
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

-- A record's kicked spell, for the row of the kicker who claims it.
local function KickedFromRecord(record)
    return { icon = record.iconID, mark = record.raidMark, hasMark = record.hasRaidMark }
end

-- A nameplate UNIT_SPELLCAST_INTERRUPTED with a non-nil interruptedBy is ground
-- truth that someone's kick landed. The GUID is secret for teammates: the game
-- will render the name/icon we derive from it, but our code can never read or
-- compare them. So teammate kicks become transient cooling-style records — we
-- cannot know WHICH roster bar to flip (per-teammate CDs are unrecoverable,
-- probe-confirmed).
function KT:HandleNameplateInterrupt(unit, spellID, interruptedBy)
    if not self.db.Enabled or self.isPreview or not self.isActive then return end
    -- The payload may be secret while unit spellcasts are restricted; a
    -- secret unit is never tested.
    if issecretvalue(unit) or not unit or not string_find(unit, "^nameplate") then return end
    if not (issecretvalue(interruptedBy) or interruptedBy ~= nil) then return end  -- channel ended naturally, not kicked

    -- Self/teammate split without touching the (possibly secret) GUID: the
    -- token is secret or nil for most teammates but can be plain ("party1"),
    -- so only the player's own units count. Self CD is owned by
    -- OnSpellcastSucceeded.
    local ok, token = pcall(UnitTokenFromGUID, interruptedBy)
    if DEBUG_KT then
        KE:Print(string_format("[KT] nameplate interrupt unit=%s tokenOk=%s token=%s guidSecret=%s",
            tostring(unit), tostring(ok), issecretvalue(token) and "secret" or tostring(token),
            tostring(not KE:IsSafeValue(interruptedBy))))
    end
    -- A hidden kicker (as in a running key) is the player's own kick when the
    -- player just cast one (KT:ClaimOwnKick). No token with a plain GUID is a
    -- kicker outside the group, such as a totem, and is not hidden.
    local now = GetTime()
    local own = ok and KE:IsSafeValue(token) and KT.IsOwnKickToken(token)
    local hidden = not ok or issecretvalue(token) or (token == nil and issecretvalue(interruptedBy))
    local claimed = (own or hidden) and KT.TakeOwnClaim(self.ownClaim, now, OWN_KICK_MATCH_WINDOW)
    if own or claimed then
        local mark, hasMark = RaidMarkOf(unit)
        local kicked = { icon = InterruptedSpellIcon(spellID), mark = mark, hasMark = hasMark }
        if claimed then
            self:ShowKicked(UnitGUID("player"), kicked)
        else
            -- A readable own interrupt with no cast before it belongs to the
            -- cast still to come, which then has nothing to claim.
            self._ownEarlyLandingAt, self._ownEarlyKicked = now, kicked
        end
        self._ownLandedAt = now
        self:TryOwnReduction()
        return
    end

    local raidMark, hasRaidMark = RaidMarkOf(unit)
    self:ProcessTeammateKick(interruptedBy, spellID, raidMark, hasRaidMark, hidden)
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

-- hiddenKicker: the game hid who kicked, so the player's own cast arriving
-- just after may still claim the record (KT:ClaimOwnKick).
function KT:ProcessTeammateKick(interrupterGuid, interruptedSpellID, raidMark, hasRaidMark, hiddenKicker)
    -- What the game lets us see about the kicker, for display only: the name
    -- and class may be secret, so neither is compared.
    local ok, name = pcall(UnitNameFromGUID, interrupterGuid)
    if not ok or not (issecretvalue(name) or name ~= nil) then return end

    -- classToken may be SECRET: it is only handed to the C-side GetClassColor
    -- (AllowedWhenTainted) for the record's color.
    local okClass, _, cf = pcall(UnitClassFromGUID, interrupterGuid)
    local classToken
    if okClass and (issecretvalue(cf) or cf ~= nil) then classToken = cf end

    -- A teammate row comes only from that teammate's own messages; every
    -- other kick is a record, even when the kicker's identity is readable.
    if DEBUG_KT then
        KE:Print(string_format("[KT] teammate kick nameSafe=%s classSafe=%s",
            tostring(KE:IsSafeValue(name)), tostring(KE:IsSafeValue(classToken))))
    end

    -- A synced teammate's KICK that arrived first claims this record, and
    -- the kicked spell goes to that teammate's row.
    if self.commMode ~= "feed" then
        local paired, key = KT.PairRecord(self.kickPairing, GetTime(), KICK_PAIR_WINDOW)
        if paired then
            self:ShowKicked(KT.PairKeyGuid(key),
                { icon = InterruptedSpellIcon(interruptedSpellID), mark = raidMark, hasMark = hasRaidMark })
            return
        end
    end

    -- Class color for the record: pass the (possibly secret) token to the
    -- C-side GetClassColor and apply r/g/b VERBATIM — storing/applying
    -- secrets is legal, any math or comparison on them is not.
    local colorR, colorG, colorB
    if issecretvalue(classToken) or classToken ~= nil then
        local okColor, col = pcall(C_ClassColor.GetClassColor, classToken)
        if okColor and col then
            colorR, colorG, colorB = col.r, col.g, col.b
        end
    end

    local iconID = InterruptedSpellIcon(interruptedSpellID)

    self.nextRecordID = self.nextRecordID + 1
    local record = {
        id = self.nextRecordID,
        name = name,          -- possibly secret; SetText-only
        iconID = iconID,      -- possibly secret; SetTexture-only
        colorR = colorR,      -- class color; possibly secret — apply verbatim,
        colorG = colorG,      -- never do math or comparisons on these
        colorB = colorB,
        startTime = GetTime(),
        duration = self.db.KickRecordDuration or KICK_RECORD_FALLBACK_DURATION,
        raidMark = raidMark,  -- possibly secret; SetSpriteSheetCell-only
        hasRaidMark = hasRaidMark,
        hiddenKicker = hiddenKicker,
    }
    table_insert(self.kickRecords, record)

    -- Bound the list: oldest records fall off past MaxBars.
    while #self.kickRecords > (self.db.MaxBars or 5) do
        local old = table.remove(self.kickRecords, 1)
        self:ReleaseBar("record" .. old.id)
    end

    -- Stash grace: the local nameplate event always
    -- beats the network, so a comm user's kick would blink a record before
    -- the comm claims it. Hold the record invisible for the grace window —
    -- claimed records die unseen; unclaimed ones render 0.4s late.
    local recordID = record.id
    C_Timer.After(KICK_RECORD_GRACE, function()
        self:ShowKickRecord(recordID)
    end)
end

-- Render a stashed record if it survived the grace window (a comm claim or
-- eviction during the grace removes it from kickRecords — never rendered).
function KT:ShowKickRecord(recordID)
    if not self.isActive or self.isPreview then return end
    for _, record in ipairs(self.kickRecords) do
        if record.id == recordID then
            local bar = self:GetOrCreateBar("record" .. recordID)
            self:UpdateRecordBarVisuals(bar, record)
            bar:Show()
            self:LayoutBars()
            return
        end
    end
end

function KT:ClearKickRecords()
    for _, record in ipairs(self.kickRecords) do
        self:ReleaseBar("record" .. record.id)
    end
    wipe(self.kickRecords)
    self:ClearPairing()
end

function KT:ClearPairing()
    wipe(self.kickPairing.claims)
    wipe(self.kickPairing.paired)
end

-- Drops the record a KICK message just claimed.
function KT:RemoveKickRecordAt(index)
    local record = table.remove(self.kickRecords, index)
    if not record then return end
    self:ReleaseBar("record" .. record.id)
    self:LayoutBars()
end

---------------------------------------------------------------------------------
-- KE-to-KE Kick Sync (addon comm)
---------------------------------------------------------------------------------
-- Party members also running KitnEssentials broadcast their own kicks, letting
-- receivers flip the sender's REAL roster bar with the exact CD — full
-- per-member tracking among KE users. Non-KE teammates keep the record
-- fallback. Comms over INSTANCE_CHAT probe-verified working
-- (family rule); every send/parse is pcall'd so blocked contexts degrade
-- silently to records.
local COMM_PREFIX = "KEKick"
-- BliZzi Party Tools interop: their dispatcher accepts
-- KICK from any class-auto-registered party member — no HELLO handshake
-- required — and normalizes senders with Ambiguate like we do. Wire format:
-- "B1;KICK;spellID;cd". Format drift on their side degrades to ignored
-- messages, never errors.
local BLIZZI_PREFIX = "BliZziIT"

local whisperTargets = {}

local function sendAddonMessage(prefix, msg, channel, target)
    return pcall(C_ChatInfo.SendAddonMessage, prefix, msg, channel, target)
end

-- Every send checks the chat lock first (KT.TransmitComm); while locked no
-- roster name is read. A whisper target is built only from plain values.
function KT:Transmit(prefix, msg)
    local locked = KE:IsChatMessagingLocked()
    wipe(whisperTargets)
    if not locked then
        for i = 1, 4 do
            local unit = "party" .. i
            if UnitExists(unit) then
                local n, r = UnitName(unit)
                if KE:IsSafeValue(n) and not issecretvalue(r) then
                    whisperTargets[#whisperTargets + 1] = (r and r ~= "") and (n .. "-" .. r) or n
                end
            end
        end
    end
    return KT.TransmitComm(self.commState, locked, sendAddonMessage,
        prefix, msg, IsInGroup(LE_PARTY_CATEGORY_INSTANCE), whisperTargets)
end

-- skipMirror: a talent-added kick, which the mirror's receivers may take for
-- the sender's main kick.
function KT:BroadcastKick(spellID, cd, skipMirror)
    if not self.db.KickSync then return end
    if not IsInGroup() then return end

    if self:Transmit(COMM_PREFIX, "1;KICK;" .. spellID .. ";" .. cd) == "refused" or skipMirror then return end
    self:Transmit(BLIZZI_PREFIX, "B1;KICK;" .. spellID .. ";" .. cd)
end

-- Presence announce: lets other KE users verify us (and show our bar at
-- Ready) from dungeon start instead of on our first kick. Sent on activation
-- and roster changes (throttled), as a reply to a HELLO (forced when it
-- asked), and forced when the chat lock lifts or the own kicks change.
-- noAnswer marks a reply or a talent-added kick update; neither is answered.
function KT:BroadcastHello(force, noAnswer)
    if not self.db.KickSync then return end
    if not self.isActive or not IsInGroup() then return end

    local guid = UnitGUID("player")
    local member = guid and self.partyMembers[guid]
    local data = member and member.interruptData
    if not member then return end

    local now = GetTime()
    if not KT.HelloAllowed(KE:IsChatMessagingLocked(), self._lastHelloSent, now, force, HELLO_THROTTLE) then
        return
    end
    self._lastHelloSent = now

    -- Spell 0 says the player has no kick now (a demon without one), so
    -- teammates drop the row instead of keeping the last kick they heard.
    local id, cd, remaining = 0, 0, 0
    if data then
        id, cd = data.id, self:OwnKickCooldown(data)
        if member.kickStart and member.kickDuration then
            remaining = math_max(0, member.kickStart + member.kickDuration - now)
        end
    end
    self:Transmit(COMM_PREFIX, KT.EncodeHello(id, cd, remaining, noAnswer,
        member.extraKicks and member.extraKicks[1], now))
    -- Deliberately NO BliZzi-format hello: we stay out of their handshake
    -- (kick-data-only participation, established interop posture).
end

-- R: the sender's own corrected remaining time after a talent shortened its
-- kick. Sync mode only; the mirror carries nothing for it.
function KT:BroadcastReduction(spellID, cd, remaining)
    if not self.db.KickSync or self.commMode ~= "sync" or not IsInGroup() then return end
    self:Transmit(COMM_PREFIX, "1;R;" .. spellID .. ";" .. cd .. ";" .. string_format("%.1f", remaining))
end

-- A kick the player cast and a nameplate interrupt credited to the player
-- are one success when they land within the window, in either order. The
-- shorter cooldown is the own row's arithmetic, never a cooldown read.
function KT:TryOwnReduction()
    if not KT.OwnKickMatched(self._ownKickAt, self._ownLandedAt, OWN_KICK_MATCH_WINDOW) then return end
    local spellID = self._ownKickSpell
    self._ownKickAt, self._ownLandedAt, self._ownKickSpell = nil, nil, nil

    local talentID, seconds = KE:GetInterruptSuccessReduction(spellID)
    if not talentID or not isTalentKnown(talentID) then return end
    local guid = UnitGUID("player")
    local member = guid and self.partyMembers[guid]
    if not member or not member.interruptData then return end
    local duration = member.kickDuration
    local remaining = KT.ReducedRemaining(member.kickStart, duration, GetTime(), seconds)
    if not remaining then return end
    if remaining > 0 then
        self:ConfirmKick(guid, duration, remaining)
    else
        self:ClearKick(guid)
    end
    self:BroadcastReduction(member.interruptData.id, duration, remaining)
end

local function getExtraKick(id)
    return KE:GetExtraKick(id)
end

function KT:OnCommReceived(_, prefix, message, _, sender)
    local isKE = prefix == COMM_PREFIX
    if not isKE and prefix ~= BLIZZI_PREFIX then return end
    if not self.db.Enabled or self.isPreview or not self.isActive then return end
    if not self.db.KickSync then return end
    if not KE:IsSafeValue(sender) then return end

    -- Wire input is untrusted; one pcall wraps parse + attribution so bad
    -- input is dropped, not thrown.
    local ok = pcall(function()
        local shortSender = Ambiguate(sender, "short")
        local senderKey = KE:BuildNicknameKey(sender, GetNormalizedRealmName())
        -- Own echo, compared through the plain identity fields only.
        local playerGuid = UnitGUID("player")
        local own = playerGuid and self.partyMembers[playerGuid]
        if not own then return end
        if (own.fullKey and senderKey == own.fullKey)
            or (not own.fullKey and own.shortName and shortSender == own.shortName) then
            return
        end

        --   KE:     "1;KICK;spellID;cd"
        --           "1;HELLO;spellID;cd;remaining;replyFlag;extraID;extraRemaining"
        --           "1;R;spellID;cd;remaining"
        --   BliZzi: "B1;KICK;spellID;cd" "B1;HELLO;class;spellID;cd"
        local verb, sid, cd, remField, replyFlag, extraField, extraRemField
        if isKE then
            local ver, v, sidStr, cdStr, remStr, flagStr, extraStr, extraRemStr = strsplit(";", message)
            if ver ~= "1" then return end  -- version-gate our own wire
            verb, sid, cd, remField, replyFlag = v, tonumber(sidStr), tonumber(cdStr), remStr, flagStr
            extraField, extraRemField = extraStr, extraRemStr
        else
            local hdr, cmd, a3, a4, a5 = strsplit(";", message)
            if hdr ~= "B1" then return end
            if cmd == "KICK" then
                verb, sid, cd = "KICK", tonumber(a3), tonumber(a4)
            elseif cmd == "HELLO" then
                verb, sid, cd = "HELLO", tonumber(a4), tonumber(a5)  -- a3 = class
            end
        end
        if verb ~= "KICK" and verb ~= "HELLO" and verb ~= "R" then return end
        local valid
        valid, sid, cd = KT.CleanWireKick(verb, sid, cd)
        if not valid then return end
        -- Wire cd is untrusted external input: cap it at the kick's table cd
        -- so a bad client can't wedge a bar for hours.
        local kickID = (sid and sid > 0) and KE:GetCanonicalKickSpell(sid) or nil
        if cd then cd = KT.WireCooldownCap(cd, kickID and KE:GetKickCooldownCap(kickID)) end
        local extra = kickID and KE:GetExtraKick(kickID)

        local guid, member = KT.MemberForSender(self.partyMembers, senderKey, shortSender)
        if not guid then return end
        member.kickVerified = true  -- comm user: bar is tracked for real
        if verb == "HELLO" and isKE then
            local mode = KT.HelloReplyMode(replyFlag)
            if mode then self:ScheduleHelloReply(mode == "force") end
        end
        -- The sender knows their own main kick best (also fills members our
        -- spec logic had to defer); a talent-added kick has its own entry and
        -- never replaces it. Once a message sets or clears the main kick, only
        -- their messages do (KT:ApplySpecKick never re-guesses it); a cleared
        -- kick drops their row until a message names one.
        local change = KT.KickFromMessage(verb, isKE, sid, cd, extra)
        if change == "set" then
            member.kickFromMessage = true
            local role = member.interruptData and member.interruptData.role or "DAMAGER"
            member.interruptData = { id = kickID, cd = cd, role = role }
        elseif change == "clear" then
            member.kickFromMessage = true
            member.interruptData = nil
            member.kickStart, member.kickDuration = nil, nil
            member.extraKicks = nil
            self:UpdateBars()
            self:LayoutBars()
            return
        end
        local now = GetTime()
        local extrasTouched = verb == "HELLO" and isKE
            and KT.HelloExtras(member, extraField, extraRemField, getExtraKick, now)
        if not member.interruptData then return end
        self:UpdateBars()  -- materialize the bar (verified-only roster)
        if extrasTouched then self:RefreshMemberRow(guid) end

        if verb == "KICK" and self.commMode ~= "feed" then
            -- Keyed by teammate and canonical kick: Pummel then a throw inside
            -- the window are two kicks, and each pairs with its own record.
            local result, index = KT.PairComm(self.kickPairing, self.kickRecords,
                guid .. ":" .. (kickID or 0), now, KICK_PAIR_WINDOW)
            if result == "duplicate" then return end
            member.kicked = nil
            if result == "claimed" then
                member.kicked = KickedFromRecord(self.kickRecords[index])
                self:RemoveKickRecordAt(index)
            end
        end

        if extra then
            if verb == "KICK" then
                local entry = KT.ExtraKick(member, kickID, cd)
                entry.kickStart, entry.kickDuration = now, entry.cd
                self:RefreshMemberRow(guid)
            end
            return
        end

        local duration, remaining = KT.MessageBarTimes(remField, cd, member.interruptData.cd)
        -- Only an R that moved the row stamps it; a malformed R changes nothing.
        local action, stamp = KT.CooldownFromMessage(verb, remaining, member.reducedAt, now, KICK_PAIR_WINDOW)
        if stamp then member.reducedAt = now end
        if action == "start" then
            self:ConfirmKick(guid, cd)
        elseif action == "set" then
            self:ConfirmKick(guid, duration, remaining)
        elseif action == "ready" then
            self:ClearKick(guid)
        end
        if verb == "KICK" then self:RedrawKicked(guid) end
    end)
    if not ok and DEBUG_KT then
        local okS, senderStr = pcall(tostring, sender)
        KE:Print("[KT] kick comm parse failed from " .. (okS and senderStr or "?"))
    end
end

-- One reply per burst of HELLOs, spread so a party does not answer at once.
-- force: the burst held a HELLO asking for an answer, which the throttle does
-- not hold back; the reply itself is flagged, so it is never answered.
function KT:ScheduleHelloReply(force)
    if force then self._helloReplyForce = true end
    if self._helloReplyPending then return end
    self._helloReplyPending = true
    local activation = self.activationID
    C_Timer.After(math_random() * HELLO_REPLY_JITTER, function()
        if self.activationID ~= activation then return end
        local forceReply = self._helloReplyForce
        self._helloReplyPending, self._helloReplyForce = false, false
        if self.isActive then self:BroadcastHello(forceReply, true) end
    end)
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

-- The player's kick claims the interrupt it causes when the game hides the
-- kicker. The interrupt can arrive first: its record, still unseen in its
-- grace, is then the player's and goes, its kicked spell onto the own row.
-- Returns that record's time.
function KT:ClaimOwnKick(now, member)
    -- This cast's readable interrupt already arrived: nothing left to claim,
    -- and its kicked spell is this cast's.
    local early, earlyKicked = self._ownEarlyLandingAt, self._ownEarlyKicked
    self._ownEarlyLandingAt, self._ownEarlyKicked = nil, nil
    if KT.OwnKickMatched(now, early, OWN_KICK_MATCH_WINDOW) then
        if member then member.kicked = earlyKicked end
        self.ownClaim.at = nil
        return nil
    end
    if member then member.kicked = nil end
    local index = KT.OwnRecordIndex(self.kickRecords, now, KICK_RECORD_GRACE)
    if not index then
        self.ownClaim.at = now
        return nil
    end
    self.ownClaim.at = nil
    local record = self.kickRecords[index]
    if member then member.kicked = KickedFromRecord(record) end
    self:RemoveKickRecordAt(index)
    return record.startTime
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
            self:BroadcastKick(spellID, entry.cd, true)
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
    self._ownKickAt, self._ownKickSpell = now, kickID
    local member = self.partyMembers[guid]
    local landedAt = self:ClaimOwnKick(now, member)
    if landedAt then self._ownLandedAt = landedAt end
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
        -- missing row appears. The KICK below announces it.
        if not data or data.id ~= kickID then
            data = KickRow(kickID, kickCd, member.specID, data and data.role)
            member.interruptData = data
            self:UpdateBars()
            self:LayoutBars()
        end
    end
    local cd = data and self:OwnKickCooldown(data)
    self:ConfirmKick(guid, cd)
    self:RedrawKicked(guid)
    -- Tell party KE users so they can flip our roster bar with the real CD
    if data then self:BroadcastKick(data.id, cd) end
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
    self:RegisterEvent("CHAT_MSG_ADDON", "OnCommReceived")
    self:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED", "OnRestrictionChanged")
    self.combatEventsRegistered = true
end

function KT:UnregisterCombatEvents()
    if not self.combatEventsRegistered then return end
    self:UnregisterEvent("UNIT_SPELLCAST_INTERRUPTED")
    self:UnregisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
    if self.castFrame then self.castFrame:UnregisterAllEvents() end
    self:UnregisterEvent("CHAT_MSG_ADDON")
    self:UnregisterEvent("ADDON_RESTRICTION_STATE_CHANGED")
    self:UnregisterEvent("SPELLS_CHANGED")
    self.combatEventsRegistered = false
    self.commMode = nil
    self._lastHelloSent = nil
    self.commState.commBlocked = nil

    self:ClearKickRecords()
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
        self._helloReplyPending, self._helloReplyForce = false, false
        self._modeCheckPending, self._ownKickCheckPending = false, false
        self:RegisterCombatEvents()
        if self.containerFrame then
            self:ApplyContainerPosition()
            self.containerFrame:Show()
        end
        self:RefreshPartyRoster()
        self.commState.commBlocked = nil  -- new instance: re-probe the comm channel
        self:UpdateCommMode()
        self:BroadcastHello()  -- announce presence to party KE users
    elseif not shouldBeActive and self.isActive then
        self.isActive = false
        self:UnregisterCombatEvents()  -- also clears kick records
        self:HideAllBars()
        if self.containerFrame then self.containerFrame:Hide() end
        wipe(self.partyMembers)
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
        self:BroadcastHello()  -- late joiners need to learn us (throttled)
    else
        self:CheckActivation()
    end
end

-- Locked chat means teammates' messages cannot arrive, so their rows cannot
-- stay true: feed mode drops them and shows every teammate kick as a record.
function KT:UpdateCommMode()
    local mode, action = KT.CommModeStep(self.commMode, KE:IsChatMessagingLocked())
    self.commMode = mode
    if action == "enter-feed" then
        for _, member in pairs(self.partyMembers) do
            if member.unit ~= "player" then
                member.kickVerified = nil
                member.kickStart = nil
                member.kickDuration = nil
                member.extraKicks = nil
                member.reducedAt = nil
                member.kicked = nil
            end
        end
        self:ClearPairing()
        self:UpdateBars()
        self:LayoutBars()
    elseif action == "enter-sync" then
        self.commState.commBlocked = nil
        self:ClearPairing()
        self:UpdateBars()
        self:LayoutBars()
        self:BroadcastHello(true)
    end
end

-- The payload is not read: Core/Secret.lua records the change in its own
-- handler, so the lock check waits a frame for it.
function KT:OnRestrictionChanged()
    if self._modeCheckPending then return end
    self._modeCheckPending = true
    local activation = self.activationID
    C_Timer.After(0, function()
        if self.activationID ~= activation then return end
        self._modeCheckPending = false
        if self.isActive then self:UpdateCommMode() end
    end)
end

-- A demon swap, a talent change or a respec can change the player's kick
-- (KT:ApplyOwnKicks clears and announces it). The live spec is read, so a
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
    barFrame.markerText = statusBar:CreateFontString(nil, "OVERLAY")
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

    bar.markerText:SetDrawLayer("OVERLAY")
    bar.markerText:SetJustifyH("LEFT")
    bar.markerText:ClearAllPoints()
    bar.markerText:SetPoint("LEFT", bar.nameText, "RIGHT", 1, 0)

    bar.timerText:SetDrawLayer("OVERLAY")
    bar.timerText:SetJustifyH("RIGHT")
    bar.timerText:ClearAllPoints()
    bar.timerText:SetPoint("RIGHT", bar.statusBar, "RIGHT", -2, 0)

    bar.raidMarkTex:SetDrawLayer("OVERLAY")
    bar.raidMarkTex:ClearAllPoints()
    bar.raidMarkTex:SetPoint("LEFT", bar.markerText, "RIGHT", 2, 0)
    bar.raidMarkTex:SetTexture(RAID_MARK_SHEET)
    bar.raidMarkTex:Hide()
end

-- Record bars draw secret names, icons, colors and marks, and member rows a
-- kicked spell's icon and mark (KT:ShowKicked). SetToDefaults clears a text
-- or texture region's secret state before the bar serves another row.
-- Resetting the status bar would drop its layout, so it is only stopped and
-- re-colored; its color may stay secret, and nothing reads it back.
function KT:ResetBarRegions(bar)
    bar.nameText:SetToDefaults()
    bar.markerText:SetToDefaults()
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

-- The trailing "*" and the raid marker sit in the name's slot, so both
-- follow ShowName. The marker index may be secret: it is only handed to the
-- C-side sprite-sheet call, shown when that call succeeds.
function KT:ApplyNameMarks(bar, isRecord, raidMark, hasRaidMark)
    local db = self.db
    local marker = KT.MarkerFor(isRecord, db.ShowName)
    KE:ApplyFont(bar.markerText, db.FontFace, db.FontSize, db.FontOutline)
    bar.markerText:SetTextColor(1, 1, 1, 1)
    bar.markerText:SetText(marker)
    bar.markerText:SetShown(marker ~= "")

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
end

-- A zero duration stops the engine drive; the bar then holds `value`.
function KT:StopBarTimer(bar, value)
    if not zeroDuration then zeroDuration = C_DurationUtil.CreateDuration() end
    bar.statusBar:SetTimerDuration(zeroDuration, Enum.StatusBarInterpolation.Immediate,
        Enum.StatusBarTimerDirection.ElapsedTime)
    bar.statusBar:SetMinMaxValues(0, 1)
    bar.statusBar:SetValue(value or 0)
end

-- Geometry + textures that depend only on db (shared by member and record bars).
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

-- Record bars: teammate kick records. name/iconID may be SECRET — the game
-- renders them; never read back, never compare, never dirty-check SetText.
function KT:UpdateRecordBarVisuals(bar, record)
    local db = self.db
    self:ApplyBarGeometry(bar)

    if issecretvalue(record.iconID) or record.iconID ~= nil then
        pcall(bar.iconTex.SetTexture, bar.iconTex, record.iconID)
    else
        bar.iconTex:SetTexture(134400)
    end
    bar.iconTex:SetDesaturated(true)

    KE:ApplyFont(bar.nameText, db.FontFace, db.FontSize, db.FontOutline)
    bar.nameText:SetShown(db.ShowName)
    pcall(bar.nameText.SetText, bar.nameText, record.name)
    bar.nameText:SetTextColor(1, 1, 1, 1)
    self:ApplyNameMarks(bar, true, record.raidMark, record.hasRaidMark)

    KE:ApplyFont(bar.timerText, db.FontFace, db.FontSize, db.FontOutline)
    bar.timerText:SetShown(db.ShowTimer)
    bar.timerText:SetTextColor(1, 1, 1, 1)

    -- Kicker's class color when the game resolved one (r/g/b may be secret —
    -- applied verbatim, the game paints it); CoolingColor fallback otherwise.
    if issecretvalue(record.colorR) or record.colorR ~= nil then
        bar.statusBar:SetStatusBarColor(record.colorR, record.colorG, record.colorB, 1)
    else
        bar.statusBar:SetStatusBarColor(unpack(db.CoolingColor))
    end
    self:StartBarTimer(bar, record.startTime, record.duration)
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
        self:ApplyNameMarks(bar, false, kicked.mark, kicked.hasMark)
    else
        self:ApplyNameMarks(bar, false)
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
            -- "Ready" is a claim — only bars we can actually track make it
            -- (self and comm-verified members).
            -- Unverified members' timer area stays blank: 12.0.5 hides
            -- their kicks, so Ready would be a guess.
            if db.ShowReadyText and member and member.kickVerified then
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

    -- Collect eligible members: has a kick AND we can actually track it
    -- (self and comm users; KT.RowShown). Everyone else's kicks are records.
    local needsBars = {}
    for guid, member in pairs(self.partyMembers) do
        if KT.RowShown(member, self.commMode) then
            needsBars[guid] = true
        end
    end

    -- Release bars for members who no longer qualify (record bars are owned
    -- by the kickRecords lifecycle, not the roster — skip them here)
    for guid in pairs(self.activeBars) do
        if not needsBars[guid] and not string_find(guid, "^record") then
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
    -- the dropdown; guiConfigContext is the persistent fallback because the
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
    local parent = KE:ResolveAnchorFrame(aft, pf)
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

    -- Teammate kick records join the cooling section (sorted by remaining
    -- like member cooldowns; they never enter the ready list)
    for _, record in ipairs(self.kickRecords) do
        local bar = self.activeBars["record" .. record.id]
        if bar then
            local remaining = record.duration - (now - record.startTime)
            if remaining > 0 then
                table_insert(coolingList, { bar = bar, record = record, remaining = remaining })
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

    -- Position bars
    local growUp = db.GrowthDirection == "UP"
    local maxBars = db.MaxBars or 5
    local spacing = db.BarSpacing or 2
    local barHeight = db.BarHeight or 20

    -- Bars pin to the container's self-point (growth vertical edge + user
    -- horizontal edge) and stack inward, exactly filling the full-height container.
    local selfPoint = self:GetSelfPoint(self:ResolvePositionConfig())
    for i, entry in ipairs(self.sortedBars) do
        local bar = entry.bar
        if i <= maxBars then
            bar:ClearAllPoints()
            local offset = (i - 1) * (barHeight + spacing)
            bar:SetPoint(selfPoint, self.containerFrame, selfPoint, 0, growUp and offset or -offset)
            bar:Show()
        else
            bar:Hide()
        end
    end

    -- Size container to the full max-bar stack so the EditMode overlay spans the
    -- whole group (not just one bar).
    local n = db.MaxBars or 5
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

-- Attach OnUpdate while there is at least one active/preview bar; detach
-- otherwise. Out-of-combat with no group, no kicks → script detached, zero
-- per-frame dispatch cost. Call after every mutation of activeBars.
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
    -- records and writes the countdown text when it changes. All arithmetic
    -- here is our own GetTime() math: plain values, no secrets.
    for guid, bar in pairs(self.activeBars) do
        local member = self.partyMembers[guid]
        if member and member.interruptData then
            local rowKick, isReady = KT.PickRowKick(member, now)
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

    for i = #self.kickRecords, 1, -1 do
        local record = self.kickRecords[i]
        local key = "record" .. record.id
        local bar = self.activeBars[key]
        local remaining = record.duration - (now - record.startTime)

        if remaining <= 0 then
            table.remove(self.kickRecords, i)
            self:ReleaseBar(key)
            needsRelayout = true
        elseif bar then
            anyCooling = true
            if db.ShowTimer then SetTimerText(bar, FormatRemaining(remaining)) end
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
    -- Drop live kick records too: their bars were just released and nothing
    -- re-renders an unexpired record after preview ends.
    self:ClearKickRecords()

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
        if i > (db.MaxBars or 5) then break end

        -- Reuse via the pool (keyed like live bars) — direct CreateBar here
        -- stranded 5 frames per preview cycle since HideAllBars had just
        -- pooled the previous set.
        local bar = self:GetOrCreateBar("preview_" .. i)
        local fakeMember = {
            name = data.name,
            classToken = data.classToken,
            interruptData = { id = data.spellID, cd = data.cd or 15, role = "DAMAGER" },
            kickStart = (not data.ready) and GetTime() or nil,
            kickVerified = true,  -- preview mocks show the verified look
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

    -- Size container to the full max-bar stack so the EditMode overlay spans the
    -- whole group (not just one bar).
    local nPrev = db.MaxBars or 5
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

    -- Kick-sync comm prefixes (pcall: registration can fail at the prefix
    -- cap). BliZzi's prefix is registered so their users' kicks reach us.
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        pcall(C_ChatInfo.RegisterAddonMessagePrefix, COMM_PREFIX)
        pcall(C_ChatInfo.RegisterAddonMessagePrefix, BLIZZI_PREFIX)
    end

    -- Register non-combat events. INSPECT_READY/PLAYER_REGEN_ENABLED no longer
    -- needed — LibSpec handles party spec discovery passively via comms.
    self:RegisterEvent("GROUP_ROSTER_UPDATE", "OnRosterUpdate")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnZoneChange")
    self:RegisterEvent("ZONE_CHANGED_NEW_AREA", "OnZoneChange")
    self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", "OnPlayerSpecChanged")

    if LibSpec then
        LibSpec.RegisterGroup(self, function(specID, role, position, playerName)
            KT:OnLibSpecGroupUpdate(specID, role, position, playerName)
        end)
    end

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
    if LibSpec then LibSpec.UnregisterGroup(self) end
    self.combatEventsRegistered = false
    self:CancelAllTimers()
    self:StopOnUpdate()

    self:ClearKickRecords()
    self:HideAllBars()
    wipe(self.partyMembers)
    wipe(self.nameSpecCache)

    self.isActive = false
    self.isPreview = false
    self.commMode = nil

    if self.containerFrame then self.containerFrame:Hide() end
end

function KT:ApplySettings()
    self:UpdateDB()
    if not self.containerFrame then return end

    self:ApplyContainerPosition()

    -- Re-apply visuals to all active bars
    for guid, bar in pairs(self.activeBars) do
        local member = self.partyMembers[guid]
        if member then
            self:UpdateBarVisuals(bar, member)
        end
    end
    for _, record in ipairs(self.kickRecords) do
        local bar = self.activeBars["record" .. record.id]
        if bar then
            self:UpdateRecordBarVisuals(bar, record)
        end
    end

    self:LayoutBars()

    if self.isPreview then
        self:ShowPreview()
    end
end
