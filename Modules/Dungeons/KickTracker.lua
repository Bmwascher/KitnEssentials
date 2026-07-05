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
local UnitGUID = UnitGUID
local UnitName = UnitName
local UnitClass = UnitClass
local UnitExists = UnitExists
local IsInInstance = IsInInstance
local IsInGroup = IsInGroup
local GetSpecialization = GetSpecialization
local GetSpecializationInfo = GetSpecializationInfo
local UnitGroupRolesAssigned = UnitGroupRolesAssigned
local C_Timer = C_Timer
local C_ClassColor = C_ClassColor
local C_Spell = C_Spell
local UnitNameFromGUID = UnitNameFromGUID
local UnitClassFromGUID = UnitClassFromGUID
local UnitTokenFromGUID = UnitTokenFromGUID
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

-- LibSpecialization: passive group spec/role tracking via addon comms.
-- Replaces the prior CanInspect/NotifyInspect/INSPECT_READY plumbing
-- (~75 lines of throttle/queue management). Optional load — module
-- degrades to "no party member specs known until you re-zone with the
-- lib loaded" if absent.
local LibSpec = LibStub("LibSpecialization", true)

---------------------------------------------------------------------------------
-- Interrupt Database
---------------------------------------------------------------------------------
-- From ExwindDB, verified values. Specs without a kick have id = 0.
local INTERRUPT_DATA = {
    -- Death Knight: Mind Freeze 12s
    [250]  = { id = 47528,  cd = 12, role = "TANK" },
    [251]  = { id = 47528,  cd = 12, role = "DAMAGER" },
    [252]  = { id = 47528,  cd = 12, role = "DAMAGER" },
    -- Demon Hunter: Disrupt 15s
    [577]  = { id = 183752, cd = 15, role = "DAMAGER" },
    [581]  = { id = 183752, cd = 15, role = "TANK" },
    [1480] = { id = 183752, cd = 15, role = "DAMAGER" },
    -- Druid: Skull Bash 15s (Feral/Guardian only)
    [102]  = { id = 0, cd = 0 },
    [103]  = { id = 106839, cd = 15, role = "DAMAGER" },
    [104]  = { id = 106839, cd = 15, role = "TANK" },
    [105]  = { id = 0, cd = 0 },
    -- Evoker: Quell 20/18s (Devastation/Augmentation only)
    [1467] = { id = 351338, cd = 20, role = "DAMAGER" },
    [1468] = { id = 0, cd = 0 },
    [1473] = { id = 351338, cd = 18, role = "DAMAGER" },
    -- Hunter: Counter Shot 24s / Muzzle 15s
    [253]  = { id = 147362, cd = 24, role = "DAMAGER" },
    [254]  = { id = 147362, cd = 24, role = "DAMAGER" },
    [255]  = { id = 187707, cd = 15, role = "DAMAGER" },
    -- Mage: Counterspell 20s
    [62]   = { id = 2139,   cd = 20, role = "DAMAGER" },
    [63]   = { id = 2139,   cd = 20, role = "DAMAGER" },
    [64]   = { id = 2139,   cd = 20, role = "DAMAGER" },
    -- Monk: Spear Hand Strike 15s (Brewmaster/Windwalker only)
    [268]  = { id = 116705, cd = 15, role = "TANK" },
    [269]  = { id = 116705, cd = 15, role = "DAMAGER" },
    [270]  = { id = 0, cd = 0 },
    -- Paladin: Rebuke 15s (Protection/Retribution only)
    [65]   = { id = 0, cd = 0 },
    [66]   = { id = 96231,  cd = 15, role = "TANK" },
    [70]   = { id = 96231,  cd = 15, role = "DAMAGER" },
    -- Priest: Silence 30s (Shadow only)
    [256]  = { id = 0, cd = 0 },
    [257]  = { id = 0, cd = 0 },
    [258]  = { id = 15487,  cd = 30, role = "DAMAGER" },
    -- Rogue: Kick 15s
    [259]  = { id = 1766,   cd = 15, role = "DAMAGER" },
    [260]  = { id = 1766,   cd = 15, role = "DAMAGER" },
    [261]  = { id = 1766,   cd = 15, role = "DAMAGER" },
    -- Shaman: Wind Shear 12s (Ele/Enh), 30s (Resto)
    [262]  = { id = 57994,  cd = 12, role = "DAMAGER" },
    [263]  = { id = 57994,  cd = 12, role = "DAMAGER" },
    [264]  = { id = 57994,  cd = 30, role = "HEALER" },
    -- Warlock: Spell Lock 24/30/24s
    [265]  = { id = 19647,  cd = 24, role = "DAMAGER" },
    [266]  = { id = 19647,  cd = 30, role = "DAMAGER" },
    [267]  = { id = 19647,  cd = 24, role = "DAMAGER" },
    -- Warrior: Pummel 15s
    [71]   = { id = 6552,   cd = 15, role = "DAMAGER" },
    [72]   = { id = 6552,   cd = 15, role = "DAMAGER" },
    [73]   = { id = 6552,   cd = 15, role = "TANK" },
}

local INTERRUPT_SPELL_IDS = {}
for _, data in pairs(INTERRUPT_DATA) do
    if data.id and data.id > 0 then
        INTERRUPT_SPELL_IDS[data.id] = true
    end
end
INTERRUPT_SPELL_IDS[119910] = true  -- Command Demon: Spell Lock
INTERRUPT_SPELL_IDS[89766]  = true  -- Axe Toss (Felguard pet actual)
INTERRUPT_SPELL_IDS[119914] = true  -- Command Demon: Axe Toss

-- Class-default kicks for members whose spec is still unknown (teammates
-- without a LibSpec-carrying addon never broadcast their spec). Values match
-- INTERRUPT_DATA; where specs differ the reference's lowest-CD rule applies.
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

-- Flip true to trace preview lifecycle, cooling-bar OnUpdate cadence,
-- container OnUpdate ticks, and nameplate-interrupt token resolution.
-- Default false; revert after diagnosis.
local DEBUG_KT = false
local _ktContainerTickCounter = 0
local _ktCoolingTickCounter = 0
local KT_TICK_LOG_EVERY = 20   -- container OnUpdate at 20fps -> ~once/sec
local KT_COOLING_LOG_EVERY = 60  -- cooling per-bar at ~60fps -> ~once/sec

KT.containerFrame = nil
KT.isPreview = false
KT.editModeRegistered = false
KT.previewContext = nil    -- "HEALER" | "DEFAULT" | nil (GUI editing/preview override)
KT.guiConfigContext = nil  -- "HEALER" | "DEFAULT" | nil (which context the GUI edits)

KT.partyMembers = {}     -- [guid] = { unit, name, classToken, specID, interruptData, kickStart, kickDuration }
KT.nameSpecCache = {}    -- [playerName] = specID, fed by LibSpec.RegisterGroup callback

KT.kickRecords = {}       -- array of { id, name, color, iconID, startTime, duration } — teammate kick records
KT.nextRecordID = 0       -- monotonic; records keyed "record"..id in activeBars (GUIDs may be secret)

KT.barPool = {}           -- array of reusable bar frames
KT.activeBars = {}        -- [guid] = barFrame
KT.sortedBars = {}        -- ordered array for layout
KT._coolingList = {}      -- reusable temp table for LayoutBars
KT._readyList = {}        -- reusable temp table for LayoutBars

KT.isActive = false
KT.combatEventsRegistered = false

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

function KT:GetInterruptDataForSpec(specID)
    if not specID or specID == 0 then return nil end
    local data = INTERRUPT_DATA[specID]
    if data and data.id and data.id > 0 then
        return data
    end
    return nil
end

-- Spec unknown (teammate without a LibSpec-carrying addon): reference
-- safe-optimistic rule — assign the class-default kick only when it can't
-- be wrong (every spec of the class kicks, or a DPS/TANK role proves a
-- kicking spec; ambiguous healer/NONE stays hidden rather than showing a
-- phantom bar). Refined or cleared as soon as the real spec arrives.
function KT:GuessClassInterrupt(unit, classToken)
    local fallback = classToken and CLASS_FALLBACK_INTERRUPTS[classToken]
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
                local name = UnitName(unit)
                local _, classToken = UnitClass(unit)

                if not self.partyMembers[guid] then
                    self.partyMembers[guid] = {}
                end
                local member = self.partyMembers[guid]
                member.unit = unit
                member.name = name
                member.classToken = classToken

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
                elseif name and KE:IsSafeValue(name) then
                    specID = self.nameSpecCache[name] or 0
                end

                if specID > 0 then
                    member.specID = specID
                    member.interruptData = self:GetInterruptDataForSpec(specID)
                elseif unit ~= "player" and not member.interruptData then
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
        member.specID = specID
        member.classToken = classToken
        member.interruptData = self:GetInterruptDataForSpec(specID)
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
        if member.name == playerName and member.unit ~= "player" then
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
function KT:ConfirmKick(guid, durationOverride)
    local member = self.partyMembers[guid]
    if not member or not member.interruptData then return end

    member.kickStart = GetTime()
    member.kickDuration = durationOverride or member.interruptData.cd

    -- Immediately update bar visuals so the transition from ready→cooling is instant
    local bar = self.activeBars[guid]
    if bar then
        local isDark = self.db.ColorMode == "dark"
        -- Dark mode: starts full (class color drains to empty)
        -- Class mode: starts empty (fills up with class color as CD recovers)
        bar.statusBar:SetValue(isDark and 1 or 0)
        self:ApplyBarColor(bar, member, true)
        bar.iconTex:SetDesaturated(true)
        -- Dark mode: white name while cooling
        if isDark and bar.nameText then
            bar.nameText:SetTextColor(1, 1, 1, 1)
        end
        if self.db.ShowTimer and bar.timerText then
            bar.timerText:SetText(string_format("%d", member.kickDuration))
        end
    end

    self:LayoutBars()
end

---------------------------------------------------------------------------------
-- Teammate Kick Records (12.0.5 secret-safe)
---------------------------------------------------------------------------------
-- A nameplate UNIT_SPELLCAST_INTERRUPTED with a non-nil interruptedBy is ground
-- truth that someone's kick landed. The GUID is secret for teammates: the game
-- will render the name/icon we derive from it, but our code can never read or
-- compare them. So teammate kicks become transient cooling-style records — we
-- cannot know WHICH roster bar to flip (per-teammate CDs are unrecoverable,
-- probe-confirmed 2026-07-05).
function KT:HandleNameplateInterrupt(unit, spellID, interruptedBy)
    if not self.db.Enabled or self.isPreview or not self.isActive then return end
    if not unit or not string_find(unit, "^nameplate") then return end
    if interruptedBy == nil then return end  -- channel ended naturally, not kicked

    -- Self/teammate split without touching the (possibly secret) GUID:
    -- UnitTokenFromGUID returns a plain token for the player's own units,
    -- nil for anyone else. Self CD is owned by OnSpellcastSucceeded.
    local ok, token = pcall(UnitTokenFromGUID, interruptedBy)
    if DEBUG_KT then
        KE:Print(string_format("[KT] nameplate interrupt unit=%s tokenOk=%s token=%s guidSecret=%s",
            tostring(unit), tostring(ok), tostring(token),
            tostring(not KE:IsSafeValue(interruptedBy))))
    end
    if ok and token then return end

    self:ProcessTeammateKick(interruptedBy, spellID)
end

function KT:ProcessTeammateKick(interrupterGuid, interruptedSpellID)
    -- Resolve what the game lets us see about the kicker. The name may be
    -- secret (SecretWhenUnitIdentityRestricted); classFilename is documented
    -- plain (no secret flag in UnitDocumentation) — IsSafeValue-check both
    -- anyway before using either as a comparison value.
    local ok, name = pcall(UnitNameFromGUID, interrupterGuid)
    if not ok or name == nil then return end

    local classToken
    local okClass, _, cf = pcall(UnitClassFromGUID, interrupterGuid)
    if okClass and cf and KE:IsSafeValue(cf) then classToken = cf end

    -- Deterministic attribution — flip the real roster bar when identity
    -- data is readable: (1) plain name -> exact member; (2) plain class ->
    -- the ONLY kick-capable member of that class. No guessing beyond that
    -- (the references discarded roster heuristics for false attributions).
    local target
    if KE:IsSafeValue(name) then
        for guid, member in pairs(self.partyMembers) do
            if member.unit ~= "player" and member.name == name
                and member.interruptData then
                target = guid
                break
            end
        end
    end
    if not target and classToken then
        local matches, candidate = 0, nil
        for guid, member in pairs(self.partyMembers) do
            if member.unit ~= "player" and member.classToken == classToken
                and member.interruptData then
                matches = matches + 1
                candidate = guid
            end
        end
        if matches == 1 then target = candidate end
    end

    if DEBUG_KT then
        KE:Print(string_format("[KT] teammate kick nameSafe=%s classSafe=%s attributed=%s",
            tostring(KE:IsSafeValue(name)), tostring(classToken ~= nil), tostring(target ~= nil)))
    end

    if target then
        self:ConfirmKick(target)
        return
    end

    -- Unattributable — transient record fallback. Class color best-effort.
    local color
    if classToken then
        local okColor, c = pcall(C_ClassColor.GetClassColor, classToken)
        if okColor and c then color = c end
    end

    -- Interrupted spell's icon (display-only; both id and texture may be secret).
    local iconID
    if interruptedSpellID ~= nil then
        local okTex, tex = pcall(C_Spell.GetSpellTexture, interruptedSpellID)
        if okTex then iconID = tex end
    end

    self.nextRecordID = self.nextRecordID + 1
    local record = {
        id = self.nextRecordID,
        name = name,          -- possibly secret; SetText-only
        color = color,        -- plain color object or nil
        iconID = iconID,      -- possibly secret; SetTexture-only
        startTime = GetTime(),
        duration = self.db.KickRecordDuration or KICK_RECORD_FALLBACK_DURATION,
    }
    table_insert(self.kickRecords, record)

    -- Bound the list: oldest records fall off past MaxBars.
    while #self.kickRecords > (self.db.MaxBars or 5) do
        local old = table.remove(self.kickRecords, 1)
        self:ReleaseBar("record" .. old.id)
    end

    local bar = self:GetOrCreateBar("record" .. record.id)
    self:UpdateRecordBarVisuals(bar, record)
    bar:Show()
    self:LayoutBars()
end

function KT:ClearKickRecords()
    for _, record in ipairs(self.kickRecords) do
        self:ReleaseBar("record" .. record.id)
    end
    wipe(self.kickRecords)
end

---------------------------------------------------------------------------------
-- KE-to-KE Kick Sync (addon comm)
---------------------------------------------------------------------------------
-- Party members also running KitnEssentials broadcast their own kicks, letting
-- receivers flip the sender's REAL roster bar with the exact CD — full
-- per-member tracking among KE users. Non-KE teammates keep the record
-- fallback. Comms over INSTANCE_CHAT probe-verified working 2026-07-05
-- (family rule); every send/parse is pcall'd so blocked contexts degrade
-- silently to records.
local COMM_PREFIX = "KEKick"
-- BliZzi Party Tools interop (reference v4.1.4): their dispatcher accepts
-- KICK from any class-auto-registered party member — no HELLO handshake
-- required — and normalizes senders with Ambiguate like we do. Wire format:
-- "B1;KICK;spellID;cd". Format drift on their side degrades to ignored
-- messages, never errors (watch on reference syncs).
local BLIZZI_PREFIX = "BliZziIT"
local COMM_SUCCESS = Enum and Enum.SendAddonMessageResult
    and Enum.SendAddonMessageResult.Success or 0

local function transmitKick(prefix, msg)
    local channel = IsInGroup(LE_PARTY_CATEGORY_INSTANCE) and "INSTANCE_CHAT" or "PARTY"
    local ok, ret = pcall(C_ChatInfo.SendAddonMessage, prefix, msg, channel)
    if ok and ret == COMM_SUCCESS then return end

    -- Result 11 = Enum.SendAddonMessageResult.AddOnMessageLockdown (timed M+
    -- has blocked addon channels). Whisper each member individually instead
    -- (also covers any other send failure).
    for i = 1, 4 do
        local unit = "party" .. i
        if UnitExists(unit) then
            local n, r = UnitName(unit)
            if n then
                local target = (r and r ~= "") and (n .. "-" .. r) or n
                pcall(C_ChatInfo.SendAddonMessage, prefix, msg, "WHISPER", target)
            end
        end
    end
end

function KT:BroadcastKick(spellID, cd)
    if not self.db.KickSync then return end
    if not IsInGroup() then return end

    transmitKick(COMM_PREFIX, "1;" .. spellID .. ";" .. cd)
    transmitKick(BLIZZI_PREFIX, "B1;KICK;" .. spellID .. ";" .. cd)
end

function KT:OnCommReceived(_, prefix, message, _, sender)
    local isKE = prefix == COMM_PREFIX
    if not isKE and prefix ~= BLIZZI_PREFIX then return end
    if not self.db.Enabled or self.isPreview or not self.isActive then return end
    if not self.db.KickSync then return end

    -- Wire input is untrusted (and could be secret in odd contexts); one
    -- pcall wraps parse + attribution so bad input is dropped, not thrown.
    local ok = pcall(function()
        local shortSender = Ambiguate(sender, "short")
        if shortSender == UnitName("player") then return end  -- own echo

        local cd
        if isKE then
            local _, _, cdStr = strsplit(";", message)
            cd = tonumber(cdStr)
        else
            -- BliZzi wire: "B1;KICK;spellID;cd" — ignore their other verbs
            local hdr, cmd, _, cdStr = strsplit(";", message)
            if hdr ~= "B1" or cmd ~= "KICK" then return end
            cd = tonumber(cdStr)
            if not cd or cd <= 0 then return end
        end

        for guid, member in pairs(self.partyMembers) do
            if member.unit ~= "player" and member.name == shortSender then
                if member.interruptData then
                    self:ConfirmKick(guid, cd or member.interruptData.cd)
                    -- The nameplate event usually spawned a record for this
                    -- same kick moments ago — drop it (names may be secret,
                    -- so newest-in-window is the best match we can do).
                    self:RemoveRecentKickRecord(2.5)
                end
                return
            end
        end
    end)
    if not ok and DEBUG_KT then
        local okS, senderStr = pcall(tostring, sender)
        KE:Print("[KT] kick comm parse failed from " .. (okS and senderStr or "?"))
    end
end

function KT:RemoveRecentKickRecord(window)
    local now = GetTime()
    for i = #self.kickRecords, 1, -1 do
        local record = self.kickRecords[i]
        if now - record.startTime <= window then
            table.remove(self.kickRecords, i)
            self:ReleaseBar("record" .. record.id)
            self:LayoutBars()
            return
        end
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

function KT:OnSpellcastSucceeded(_, unit, _, spellID)
    if not self.db.Enabled or self.isPreview or not self.isActive then return end
    if unit ~= "player" and unit ~= "pet" then return end

    -- Own casts (player + own pet) deliver a PLAIN spellID in 12.0.5. Party
    -- members' casts do not fire this event for kicks at all (probe-confirmed
    -- 2026-07-05) — teammate detection lives in HandleNameplateInterrupt.
    if not INTERRUPT_SPELL_IDS[spellID] then return end
    local guid = UnitGUID("player")
    if guid then
        self:ConfirmKick(guid)
        -- Tell party KE users so they can flip our roster bar with the real CD
        local member = self.partyMembers[guid]
        if member and member.interruptData then
            self:BroadcastKick(member.interruptData.id, member.interruptData.cd)
        end
    end
end

---------------------------------------------------------------------------------
-- Combat Event Registration
---------------------------------------------------------------------------------
function KT:RegisterCombatEvents()
    if self.combatEventsRegistered then return end
    self:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED", "OnSpellcastInterrupted")
    self:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP", "OnChannelStop")
    self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", "OnSpellcastSucceeded")
    self:RegisterEvent("CHAT_MSG_ADDON", "OnCommReceived")
    self.combatEventsRegistered = true
end

function KT:UnregisterCombatEvents()
    if not self.combatEventsRegistered then return end
    self:UnregisterEvent("UNIT_SPELLCAST_INTERRUPTED")
    self:UnregisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
    self:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    self:UnregisterEvent("CHAT_MSG_ADDON")
    self.combatEventsRegistered = false

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
        self:RegisterCombatEvents()
        if self.containerFrame then
            self:ApplyContainerPosition()
            self.containerFrame:Show()
        end
        self:RefreshPartyRoster()
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
    else
        self:CheckActivation()
    end
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

    local iconTex = iconFrame:CreateTexture(nil, "ARTWORK")
    iconTex:SetPoint("TOPLEFT", 1, -1)
    iconTex:SetPoint("BOTTOMRIGHT", -1, 1)
    iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    barFrame.iconTex = iconTex

    -- Name text (offset right of icon when icon is on the left)
    local nameText = statusBar:CreateFontString(nil, "OVERLAY")
    nameText:SetJustifyH("LEFT")
    barFrame.nameText = nameText

    -- Timer text
    local timerText = statusBar:CreateFontString(nil, "OVERLAY")
    timerText:SetPoint("RIGHT", statusBar, "RIGHT", -2, 0)
    timerText:SetJustifyH("RIGHT")
    barFrame.timerText = timerText

    barFrame:Hide()
    return barFrame
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

    if record.iconID ~= nil then
        pcall(bar.iconTex.SetTexture, bar.iconTex, record.iconID)
    else
        bar.iconTex:SetTexture(134400)
    end
    bar.iconTex:SetDesaturated(true)

    KE:ApplyFont(bar.nameText, db.FontFace, db.FontSize, db.FontOutline)
    bar.nameText:SetShown(db.ShowName)
    local nameOk = pcall(bar.nameText.SetText, bar.nameText, record.name)
    if not nameOk then bar.nameText:SetText("") end
    bar.nameText:SetTextColor(1, 1, 1, 1)

    KE:ApplyFont(bar.timerText, db.FontFace, db.FontSize, db.FontOutline)
    bar.timerText:SetShown(db.ShowTimer)
    bar.timerText:SetTextColor(1, 1, 1, 1)

    if record.color then
        bar.statusBar:SetStatusBarColor(record.color.r, record.color.g, record.color.b, 1)
    else
        bar.statusBar:SetStatusBarColor(unpack(db.CoolingColor))
    end
end

function KT:UpdateBarVisuals(bar, member)
    local db = self.db
    local isDarkMode = db.ColorMode == "dark"

    self:ApplyBarGeometry(bar)

    -- Set icon texture
    if member and member.interruptData then
        local spellInfo = C_Spell.GetSpellInfo(member.interruptData.id)
        if spellInfo then
            bar.iconTex:SetTexture(spellInfo.iconID)
        else
            bar.iconTex:SetTexture(134400)
        end
    end

    -- Ready state: no active kick cooldown
    local isReady = not member or not member.kickStart

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

    -- Timer text
    KE:ApplyFont(bar.timerText, db.FontFace, db.FontSize, db.FontOutline)
    bar.timerText:SetShown(db.ShowTimer)
    bar.timerText:SetTextColor(1, 1, 1, 1)

    -- Icon desaturation (greyed out when on CD)
    bar.iconTex:SetDesaturated(not isReady)

    -- Bar color (ready state)
    if isReady then
        self:ApplyBarColor(bar, member, false)
        -- Dark mode: no fill visible (just dark background). Class mode: full bar.
        bar.statusBar:SetValue(isDarkMode and 0 or 1)
        if db.ShowTimer then
            if db.ShowReadyText then
                bar.timerText:SetText(db.ReadyText or "Ready")
            else
                bar.timerText:SetText("")
            end
        end
    else
        self:ApplyBarColor(bar, member, true)
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

    -- Collect eligible members (those with interrupt abilities)
    local needsBars = {}
    for guid, member in pairs(self.partyMembers) do
        if member.interruptData then
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
            local isCooling = member.kickStart and member.kickDuration
                and (now - member.kickStart) < member.kickDuration
            if isCooling then
                local remaining = member.kickDuration - (now - member.kickStart)
                table_insert(coolingList, { guid = guid, bar = bar, member = member, remaining = remaining })
            else
                -- Clear expired cooldowns
                if member.kickStart then
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

    if DEBUG_KT then
        _ktContainerTickCounter = _ktContainerTickCounter + 1
        if _ktContainerTickCounter >= KT_TICK_LOG_EVERY then
            _ktContainerTickCounter = 0
            local activeCount = 0
            for _ in pairs(self.activeBars) do activeCount = activeCount + 1 end
            KE:Print(string.format("[KT] OnUpdateBars tick: activeBars=%d isPreview=%s",
                activeCount, tostring(self.isPreview)))
        end
    end

    for guid, bar in pairs(self.activeBars) do
        local member = self.partyMembers[guid]
        if member and member.kickStart and member.kickDuration then
            local elapsedTime = now - member.kickStart
            local remaining = member.kickDuration - elapsedTime

            if remaining <= 0 then
                -- CD expired — restore ready state
                member.kickStart = nil
                member.kickDuration = nil
                self:UpdateBarVisuals(bar, member)
                needsRelayout = true
            else
                anyCooling = true
                local isDark = db.ColorMode == "dark"
                -- Dark mode: drain from full to empty (remaining/duration)
                -- Class mode: fill from empty to full (elapsed/duration)
                if isDark then
                    bar.statusBar:SetValue(remaining / member.kickDuration)
                else
                    bar.statusBar:SetValue(elapsedTime / member.kickDuration)
                end

                if db.ShowTimer and bar.timerText then
                    if remaining > 6 then
                        local displayVal = math_floor(remaining)
                        bar.timerText:SetText(string_format("%d", displayVal))
                    else
                        bar.timerText:SetText(string_format("%.1f", remaining))
                    end
                end
            end
        end
    end

    -- Drain + expire teammate kick records under the same 0.05s accumulator.
    -- All arithmetic here is our own GetTime() math — plain values, no secrets.
    local isDark = db.ColorMode == "dark"
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
            if isDark then
                bar.statusBar:SetValue(remaining / record.duration)
            else
                bar.statusBar:SetValue((now - record.startTime) / record.duration)
            end
            if db.ShowTimer and bar.timerText then
                if remaining > 6 then
                    bar.timerText:SetText(string_format("%d", math_floor(remaining)))
                else
                    bar.timerText:SetText(string_format("%.1f", remaining))
                end
            end
        end
    end

    -- Periodic re-sort every 1s while cooling (matches ExWind)
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
                if DEBUG_KT then
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
            guiPath = "KickTracker",
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

    self:LayoutBars()

    if self.isPreview then
        self:ShowPreview()
    end
end
