-- ╔══════════════════════════════════════════════════════════╗
-- ║  Modules/Skinning/RestedXP/RestedXPSetup.lua             ║
-- ║  Purpose: What setup changes in RestedXP's saved         ║
-- ║           settings for this character, and putting it    ║
-- ║           back.                                          ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)

local C_AddOns, C_Timer, GetServerTime, UnitGUID = C_AddOns, C_Timer, GetServerTime, UnitGUID
local hooksecurefunc, ipairs, type = hooksecurefunc, ipairs, type

local Safe, Rules, Theme = KE.RestedXPSafe, KE.RestedXPRules, KE.RestedXPTheme

local Setup = {}
KE.RestedXPSetup = Setup

local MODULE = "SkinRestedXP"
local KE_ADDON, RXP_ADDON = "KitnEssentials", "RXPGuides"
local PROFILE_CALLS = { "RefreshProfile", "CopyProfile", "ResetProfile" }
-- An accepted reload ends this Lua at the end of the frame that asked for it, and a
-- timer runs only on a later frame, so this fires only in a session the client kept.
-- The seconds are margin for any frame drawn while the client leaves the world.
local RELOAD_REFUSED_SECONDS = 2
local TEXT_DROPPED = "RestedXP's settings changed before the change you approved could apply, so nothing changed."
local TEXT_EXPIRED = "The change you approved waited too long for a reload, so nothing changed."
local TEXT_MISSED = "RestedXP started before KitnEssentials could apply its setup at this load, so nothing changed."
local TEXT_REFUSED = "The reload did not happen, so nothing changed. Click the button again to apply it."
local TEXT_NOT_LOADING = "Turn on KitnEssentials and RestedXP Guides in the AddOns list for this character, " ..
    "then click again. Nothing changed."
local TEXT_NO_PROFILE = "RestedXP's profile could not be read, so nothing changed."
-- The page's line for a click whose change could not be kept: a refused reload, or
-- an addon set not to load next time.
local watching, onProfileChange, clickNote
-- This load's start: the change taken off the store, whether the start-up call was
-- set and whether it came, whether RestedXP was already running, what became of the
-- change, a new character's setup that the start missed, and for the smoke, whether
-- the call came before RestedXP read its theme or built its V2 window, and whether
-- the call changed V2.
local job, due, booted, late, result, newMissed, beforeBuild, v2Changed

-- A profile KE cannot name has no record to tie a write to, so it counts as no
-- profile.
function Setup.Profile()
    local settings = Safe.Dig(_G.RXP, "settings")
    local profile = Safe.Dig(settings, "profile")
    return type(profile) == "table" and Safe.Has(settings, "GetSettingsDB") and profile or nil
end

local function ProfileKey()
    if not Setup.Profile() then return nil end
    local key = Safe.Run("SetupProfileKey", _G.RXP.settings.GetSettingsDB)
    return type(key) == "string" and key or nil
end

-- The current RestedXP profile's record, and only that one. Every undo and restore
-- reads through here, so a profile with no record writes nothing.
function Setup.Record()
    local store = KE:GetCharStore(false)
    return Rules.RecordFor(store and store.RestedXPSetup, ProfileKey())
end

function Setup.Plan()
    local profile = Setup.Profile()
    return profile and Rules.PlanSetup(Theme.Option("Look"), profile) or nil
end

function Setup.Undo()
    local profile, record = Setup.Profile(), Setup.Record()
    if not (profile and record) then return nil end
    return Rules.PlanUndo(record.before, profile)
end

-- A newer write or save replaces a waiting change, and a click's note no longer
-- holds once a later change has gone through.
local function NewerChange(store)
    Rules.Supersede(store)
    clickNote = nil
end

function Setup.Write(rows)
    local profile, key = Setup.Profile(), ProfileKey()
    if not (profile and key) then return end
    local store = KE:GetCharStore(true)
    store.RestedXPSetup = store.RestedXPSetup or {}
    local record = store.RestedXPSetup[key] or { before = {} }
    store.RestedXPSetup[key] = record
    Rules.MergeBefore(record.before, profile, Rules.RowKeys(rows))
    for _, row in ipairs(rows) do profile[row.key] = row.after end
    NewerChange(store)
end

local function ClearRecord(profile)
    local store, key = KE:GetCharStore(false), ProfileKey()
    local records = store and store.RestedXPSetup
    local record = Rules.RecordFor(records, key)
    if record and Rules.ClearDone(record.before, profile) then records[key] = nil end
end

-- Live only for a Theme row. Beta and V2 come here only from Setup.Boot.
function Setup.WriteUndo(rows)
    local profile = Setup.Profile()
    if not profile then return end
    for _, row in ipairs(rows) do profile[row.key] = row.after end
    ClearRecord(profile)
    NewerChange(KE:GetCharStore(false))
end

-- The current profile only: another profile's record waits for its own Undo, because
-- writing it here would change a profile the player is not looking at. What the player
-- picked since setup stays theirs.
function Setup.RestoreTheme()
    local profile, record = Setup.Profile(), Setup.Record()
    local stored = record and record.before.activeTheme
    if not (profile and stored) then return end
    if profile.activeTheme == Rules.THEME_NAME then
        profile.activeTheme = stored
        NewerChange(KE:GetCharStore(false))
        Theme.ReloadOrAsk()
    end
    record.before.activeTheme = nil
    ClearRecord(profile)
end

function Setup.MarkSeen()
    KE:GetCharStore(true).RestedXPSeen = true
end

-- Every gate that lets the module run, from the current profile. Read at each
-- click, because an open preview or a profile switch can outlast them.
function Setup.MayWrite()
    local module = KitnEssentials:GetModule(MODULE, true)
    return Rules.SetupMayWrite(module ~= nil and module:IsEnabled(), KE.db.profile.SkinRestedXP.Enabled,
        KE:IsFeatureAvailable(MODULE), KE:ShouldNotLoadModule())
end

-- RestedXP starts before KE's modules run, so the start asks the saved flag and the
-- gates, not whether the module is running yet.
local function MayWriteAtStart()
    return Rules.SetupMayWrite(true, KE.db.profile.SkinRestedXP.Enabled, KE:IsFeatureAvailable(MODULE),
        KE:ShouldNotLoadModule())
end

-- With the module off too: an Undo preview can be open then.
function Setup.ProfileChanged()
    if onProfileChange then onProfileChange() end
end

-- A profile made again under a waiting change's name has the same name and can have
-- the same values, so any RestedXP profile event drops the change. Deleting that
-- profile needs a switch first, because AceDB refuses to delete the one in use.
local function OnRestedXPProfile()
    Rules.Supersede(KE:GetCharStore(false))
    Setup.ProfileChanged()
end

-- RestedXP's database is a local of its settings file, and its callbacks call these
-- methods by name, so a hook on them is the one place to see a change. Copy and
-- reset edit the same table, which a compare of tables would miss. Installed once,
-- when the page is built.
function Setup.WatchProfile(listener)
    onProfileChange = listener or onProfileChange
    if watching then return end
    watching = true
    local settings = Safe.Dig(_G.RXP, "settings")
    for _, name in ipairs(PROFILE_CALLS) do
        if Safe.Has(settings, name) then hooksecurefunc(settings, name, OnRestedXPProfile) end
    end
end

---------------------------------------------------------------------------------
-- At RestedXP's start
---------------------------------------------------------------------------------
-- RestedXP reads Beta and V2 as it starts, and flipping them while it runs sends it
-- down the other branch with the first one's frames built. A change with either is
-- saved in KE's own table with what its preview showed, and the next start applies
-- it. The newest approved change replaces the one waiting, even with no profile to
-- name. Called only from the click that asked for the reload: if this session still
-- runs when the timer fires, the client refused the reload and the change goes.
function Setup.SavePending(kind, rows)
    local store, key = KE:GetCharStore(true), ProfileKey()
    NewerChange(store)
    if not key then return end
    Rules.SavePending(store, kind, key, rows, GetServerTime())
    local saved = store.RestedXPPending
    C_Timer.After(RELOAD_REFUSED_SECONDS, function()
        if not Rules.DropIfWaiting(store, saved) then return end
        clickNote = TEXT_REFUSED
        Safe.Notice("SetupRefused", TEXT_REFUSED)
        Setup.ProfileChanged()
    end)
end

-- A change saved while either addon is set not to load next time would wait for a
-- load that cannot take it. The click asks this before it asks for the
-- reload, so it saves nothing and asks for none.
-- The client's own per-character check where it is loaded, else the call it makes,
-- by this character's GUID.
local function LoadsNext(name)
    local util = _G.AddOnUtil
    if type(util) == "table" and type(util.IsAddOnEnabledForCurrentCharacter) == "function" then
        return util.IsAddOnEnabledForCurrentCharacter(name)
    end
    local guid = UnitGUID("player")
    if not guid then return nil end
    return C_AddOns.GetAddOnEnableState(name, guid)
end

function Setup.WillLoadNext()
    return Rules.BothLoadNext(LoadsNext(KE_ADDON), LoadsNext(RXP_ADDON))
end

function Setup.NotLoading()
    clickNote = TEXT_NOT_LOADING
    Safe.Notice("SetupNotLoading", TEXT_NOT_LOADING)
    Setup.ProfileChanged()
end

-- The click asks this before it writes, saves or asks for a reload, so a change
-- with no profile name to tie it to changes nothing and asks for no reload.
function Setup.CanSave()
    return ProfileKey() ~= nil
end

function Setup.NoProfile()
    clickNote = TEXT_NO_PROFILE
    Safe.Notice("SetupNoProfile", TEXT_NO_PROFILE)
    Setup.ProfileChanged()
end

-- Off the store at each load KE runs, so a waiting change is tried at one start
-- only, whether or not the start-up call comes; a load without KE leaves it, and
-- its saved time drops it. True when one was waiting.
function Setup.TakePending()
    job = Rules.TakePending(KE:GetCharStore(false))
    return job ~= nil
end

-- Called as the start-up call is set, or found too late to set.
function Setup.Due(tooLate)
    due, late = true, tooLate == true
end

local function V2On()
    local profile = Setup.Profile()
    return not not (profile and profile.enableBetaFeatures and profile.enableV2Interface)
end

local function BootWrites()
    local profile, key = Setup.Profile(), ProfileKey()
    local mayWrite = MayWriteAtStart()
    if job then
        local applies, why = Rules.PendingApplies(job, key, profile, mayWrite, GetServerTime())
        if applies then
            if job.kind == "undo" then Setup.WriteUndo(job.rows) else Setup.Write(job.rows) end
            result = "applied"
        else
            result = why == "expired" and "expired" or "dropped"
        end
    end
    if not (mayWrite and profile) then return end
    local store = KE:GetCharStore(true)
    if not Rules.ShouldAutoSetup(Theme.Option("SetUpNewCharacters"), store.RestedXPSeen) then return end
    store.RestedXPSeen = true
    local rows = Setup.Plan()
    if rows and #rows > 0 then
        Setup.Write(rows)
        result = result or "newCharacter"
    end
end

-- Inside RestedXP's start-up call: its settings database exists, and it has not yet
-- loaded its theme or built its windows. Its reward markers read V2 earlier, and
-- keep what they read for the session. The only place KE writes Beta or V2.
function Setup.Boot()
    booted = true
    beforeBuild = _G.RXPV2GuideWindow == nil and Safe.Dig(_G.RXP, "activeTheme") == nil
    local v2Before = V2On()
    BootWrites()
    v2Changed = V2On() ~= v2Before
end

-- True when this load's start-up call was missed, so a Beta or V2 change made now
-- would most likely miss the next one too.
function Setup.StartMissed()
    return late or (due and not booted)
end

-- What this load's start did: "applied", "newCharacter", "dropped", "expired",
-- "missed" or nil.
function Setup.StartResult()
    if (job or newMissed) and not booted then return "missed" end
    return result
end

-- For the smoke: whether the call came; whether RestedXP had neither loaded its
-- theme nor built its V2 window then; what the start did; and whether the call
-- changed V2, which leaves RestedXP's reward markers on the old look this session.
function Setup.StartFacts()
    return booted == true, beforeBuild == true, Setup.StartResult(), v2Changed == true
end

-- The page's line for a change the click, the reload or the start could not make,
-- or nil.
function Setup.StartNote()
    if clickNote then return clickNote end
    local done = Setup.StartResult()
    if done == "dropped" then return TEXT_DROPPED end
    if done == "expired" then return TEXT_EXPIRED end
    if done == "missed" then return TEXT_MISSED end
end

-- A click's note has already printed its own line.
function Setup.ReportStart()
    local note = not clickNote and Setup.StartNote()
    if note then Safe.Notice("SetupStart", note) end
end

-- Every start marks the character seen, except a login whose start-up call never
-- came while this character's setup was due: it stays unseen for a later load.
function Setup.AtStart(atLogin)
    local store = KE:GetCharStore(true)
    if atLogin and not booted and MayWriteAtStart()
        and Rules.ShouldAutoSetup(Theme.Option("SetUpNewCharacters"), store.RestedXPSeen) then
        newMissed = true
    else
        store.RestedXPSeen = true
    end
    Setup.ReportStart()
end
