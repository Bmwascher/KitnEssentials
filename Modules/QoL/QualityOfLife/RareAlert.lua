-- ╔══════════════════════════════════════════════════════════╗
-- ║  RareAlert.lua                                           ║
-- ║  Module: Rare Alert                                      ║
-- ║  Purpose: Warns of a rare near the player in the open    ║
-- ║           world, with a card that follows it.            ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@type RareAlert
local RA = KitnEssentials:NewModule("RareAlert", "AceEvent-3.0")

local TICK_INTERVAL = 0.1
local CLOSE_AFTER = 3
local HORN_FILE = 598196

RA.HORN_SOUND = "Gruntling Horn"

-- Each runs while its What Fires tick is on, or while a card follows its rare.
local LISTENERS = {
    VIGNETTE_MINIMAP_UPDATED = "FireVignette",
    NAME_PLATE_UNIT_ADDED = "FirePlate",
    PLAYER_TARGET_CHANGED = "FireTarget",
    UPDATE_MOUSEOVER_UNIT = "FireTarget",
}

local CARD_EVENTS = {
    "UNIT_HEALTH",
    "UNIT_FLAGS",
    "UNIT_FACTION",
    "UNIT_CLASSIFICATION_CHANGED",
    "NAME_PLATE_UNIT_REMOVED",
    "PLAYER_REGEN_DISABLED",
    "PLAYER_REGEN_ENABLED",
}

local PREVIEW = {
    npc = 5828,
    name = "Humar the Pridelord",
    levelText = "23",
    elite = true,
    unitSeen = true,
}
local PREVIEW_LEVEL = 23
local PREVIEW_DROP = { name = "Mark of the Pack Leader", quality = 3, new = true }
local PREVIEW_ROTATION = 0.6
local PREVIEW_YARDS = 140

---------------------------------------------------------------------------------
-- Module State
---------------------------------------------------------------------------------

-- The rare on the card, and "loud", "quiet" or "preview" for what is shown.
RA.rare = nil
RA.shown = nil
RA.listening = false
RA.editModeRegistered = false
-- Session memory by creature, so a reload clears it.
RA.seen = {}
-- When a live unit last proved a creature friendly or not a rare.
RA.proved = {}

function RA:UpdateDB()
    self.db = KE.db.profile.RareAlert
end

---------------------------------------------------------------------------------
-- Secret-safe reads
---------------------------------------------------------------------------------

local function Known(value, whenSecret)
    if KE:IsSecretValue(value) then return whenSecret end
    return value and true or false
end

-- Nil for a secret value, so a comparison on the result can never raise an error.
local function Plain(value)
    if KE:IsSecretValue(value) then return nil end
    return value
end

local function SameGUID(value, guid)
    if KE:IsSecretValue(value) then return false end
    return value == guid
end

-- Whether the unit is gray to the player, and its level color. A secret
-- difficulty cannot be known, so it reads as not gray with no color.
local function UnitDanger(unit)
    local difficulty = C_PlayerInfo.GetContentDifficultyCreatureForPlayer(unit)
    if KE:IsSecretValue(difficulty) or not difficulty then return false, nil end
    return difficulty == Enum.RelativeContentDifficulty.Trivial, (GetDifficultyColor(difficulty))
end

---------------------------------------------------------------------------------
-- Rare table
---------------------------------------------------------------------------------

-- Both return nil until the rare table exists.
function RA:RareRecord(_)
    return nil
end

function RA:RareLoot(_)
    return nil
end

local function RecordFriendly(record)
    if not record then return false end
    local faction = UnitFactionGroup("player")
    if faction == "Alliance" then return record.reactA == 1 end
    if faction == "Horde" then return record.reactH == 1 end
    return false
end

local function RecordGray(record)
    if not record or not record.high then return false end
    return GetCreatureDifficultyColor(record.high) == QuestDifficultyColors["trivial"]
end

-- Spots are flat x, y pairs in percent.
local function NearestSpot(spots, player)
    local bestX, bestY, bestDistance = spots[1], spots[2], nil
    if not player then return bestX, bestY end
    local px, py = player:GetXY()
    for i = 1, #spots, 2 do
        local dx, dy = spots[i] / 100 - px, spots[i + 1] / 100 - py
        local distance = dx * dx + dy * dy
        if not bestDistance or distance < bestDistance then
            bestX, bestY, bestDistance = spots[i], spots[i + 1], distance
        end
    end
    return bestX, bestY
end

---------------------------------------------------------------------------------
-- Event state
---------------------------------------------------------------------------------

function RA:SyncEvents()
    local cardUp = self.rare ~= nil
    for event, tick in pairs(LISTENERS) do
        if self.listening and (cardUp or self.db[tick]) then
            self:RegisterEvent(event)
        else
            self:UnregisterEvent(event)
        end
    end
    for i = 1, #CARD_EVENTS do
        if cardUp then
            self:RegisterEvent(CARD_EVENTS[i])
        else
            self:UnregisterEvent(CARD_EVENTS[i])
        end
    end
end

---------------------------------------------------------------------------------
-- Position and direction
---------------------------------------------------------------------------------

function RA:ReadMap(rare)
    local map = C_Map.GetBestMapForUnit("player")
    rare.map = map
    if map then
        rare.worldW, rare.worldH = C_Map.GetMapWorldSize(map)
    else
        rare.worldW, rare.worldH = nil, nil
    end
end

function RA:ReadSpot(rare)
    if not rare.vignetteGUID or not rare.map then return end
    local where = C_VignetteInfo.GetVignettePosition(rare.vignetteGUID, rare.map)
    if not where then return end
    local x, y = where:GetXY()
    rare.x, rare.y, rare.spotMap = x * 100, y * 100, rare.map
end

-- The vignette's last reading, else the table's nearest spot.
function RA:PinSpot(rare)
    if rare.x then return rare.spotMap, rare.x, rare.y end
    local record = self:RareRecord(rare.npc)
    if not record or not record.spots or #record.spots == 0 then return nil end
    local player = C_Map.GetPlayerMapPosition(record.map, "player")
    return record.map, NearestSpot(record.spots, player)
end

function RA:RefreshPin(rare)
    self:PaintPin(self:PinSpot(rare) ~= nil)
end

function RA:UpdateBearing(rare)
    local map = rare.map
    local player = map and C_Map.GetPlayerMapPosition(map, "player")
    local where = map and C_VignetteInfo.GetVignettePosition(rare.vignetteGUID, map)
    if not player or not where then
        self:ReadMap(rare)
        rare.rotation, rare.yards = nil, nil
        self:PaintBearing(nil)
        return
    end
    local px, py = player:GetXY()
    local vx, vy = where:GetXY()
    local firstReading = not rare.x
    rare.x, rare.y, rare.spotMap = vx * 100, vy * 100, map
    if firstReading then self:RefreshPin(rare) end
    rare.rotation, rare.yards = RA.Bearing(px, py, vx, vy, rare.worldW, rare.worldH, GetPlayerFacing())
    self:PaintBearing(rare.rotation, rare.yards)
end

-- A rare that has left or died keeps its last reading, as the tick does.
function RA:RefreshBearing(rare)
    if not rare.vignetteGUID or not self.db.ShowDirection then
        self:PaintBearing(nil)
    elseif rare.left or rare.dead then
        self:PaintBearing(rare.rotation, rare.yards)
    else
        self:UpdateBearing(rare)
    end
end

---------------------------------------------------------------------------------
-- Health and state
---------------------------------------------------------------------------------

function RA:MarkDead(rare)
    rare.dead = true
    rare.closeIn = rare.closeIn or CLOSE_AFTER
    self:PaintState(rare)
end

function RA:ReadUnitHealth(rare)
    ---@type number
    local value = UnitHealthPercent(rare.unit, false, CurveConstants.ScaleTo100)
    self:PaintHealth(value)
end

-- Reads as a fraction. Dead never comes from the bar: a reading of 0 asks the
-- vignette once.
function RA:UpdateVignetteHealth(rare)
    local fraction = C_VignetteInfo.GetHealthPercent(rare.vignetteGUID)
    if KE:IsSecretValue(fraction) or not fraction then
        rare.lastHealth = nil
        self:PaintHealth(nil)
        return
    end
    local percent = fraction * 100
    if percent == rare.lastHealth then return end
    rare.lastHealth = percent
    self:PaintHealth(percent)
    if fraction == 0 then
        local info = C_VignetteInfo.GetVignetteInfo(rare.vignetteGUID)
        if info and Known(info.isDead, false) then self:MarkDead(rare) end
    end
end

-- A token can change creature with no event of ours: the mouse moves off it, or
-- the focus changes. Every read of a held token asks this first. A token that
-- fails is resolved again, which refreshes health from whatever replaces it.
function RA:TokenHolds(rare)
    if SameGUID(UnitGUID(rare.unit), rare.guid) then return true end
    self:ResolveToken(rare.unit)
    return false
end

function RA:RefreshHealth(rare)
    if rare.unit then
        if self:TokenHolds(rare) then self:ReadUnitHealth(rare) end
    elseif rare.vignetteGUID and not rare.left then
        rare.lastHealth = nil
        self:UpdateVignetteHealth(rare)
    else
        -- Cleared so the tick repaints when a vignette that left comes back.
        rare.lastHealth = nil
        self:PaintHealth(nil)
    end
end

-- Closes silently on a friendly or non-rare creature. Clearing the stamp lets a
-- rare that was briefly not attackable alert again by a unit; the proof holds back
-- its vignette alone. Class is asked before death so a dead non-rare still closes,
-- and death before attack because a corpse reads as not attackable.
function RA:RefuteCard(rare)
    local class = Plain(UnitClassification(rare.unit))
    if not class or class == "rare" or class == "rareelite" then
        if rare.dead or Known(UnitIsDead(rare.unit), true) then return false end
        if Known(UnitCanAttack("player", rare.unit), true) then return false end
    end
    self.seen[rare.npc] = nil
    RA.Stamp(self.proved, rare.npc, GetTime())
    self:CloseCard()
    return true
end

function RA:ReadUnitState(rare)
    if self:RefuteCard(rare) then return end
    local tapped = Known(UnitIsTapDenied(rare.unit), false)
    local changed = tapped ~= (rare.tapped or false)
    rare.tapped = tapped
    if Known(UnitIsDead(rare.unit), false) and not rare.dead then
        self:MarkDead(rare)
    elseif changed then
        self:PaintState(rare)
    end
end

function RA:ReadDrop(rare)
    rare.drop = self.db.ShowDrop and RA.BestDrop(self:RareLoot(rare.npc)) or nil
end

---------------------------------------------------------------------------------
-- Following the rare
---------------------------------------------------------------------------------

function RA:CheckTargeted()
    local rare = self.rare
    if not rare or rare.targeted then return end
    if not SameGUID(UnitGUID("target"), rare.guid) then return end
    rare.targeted = true
    rare.closeIn = rare.closeIn or CLOSE_AFTER
    self:PaintState(rare)
end

-- The first token moves the portrait to the live creature and replaces table
-- values with live ones, unless it closes the card first.
function RA:AdoptUnit(rare, token)
    self:ReadUnitState(rare)
    if self.rare ~= rare then return end
    local class = Plain(UnitClassification(token))
    if class then rare.elite = class == "rareelite" end
    -- A live level below 1 is unknown to the card, and a table level must not stand
    -- in for it.
    local level = Plain(UnitLevel(token))
    if level then
        rare.levelText = RA.LevelText(level, level)
        local _, color = UnitDanger(token)
        rare.levelColor = color
    end
    self:SetPortrait(token, rare.npc)
    self:PaintIdentity(rare)
    self:PaintState(rare)
    self:ReadUnitHealth(rare)
end

-- gone is a token that is leaving but may still resolve.
function RA:ResolveToken(gone)
    local rare = self.rare
    if not rare then return end
    local token = UnitTokenFromGUID(rare.guid)
    if KE:IsSecretValue(token) then token = nil end
    if token == gone then token = nil end
    if token == rare.unit then return end
    rare.unit = token
    if not token then
        -- The bar's source is gone: the vignette feeds it now, or it hides.
        self:RefreshHealth(rare)
        return
    end
    if rare.unitSeen then
        self:ReadUnitState(rare)
        if self.rare == rare then self:ReadUnitHealth(rare) end
    else
        rare.unitSeen = true
        self:AdoptUnit(rare, token)
    end
end

function RA:AdoptVignette(rare, vignetteGUID, info)
    rare.vignetteGUID = vignetteGUID
    rare.left = false
    if not rare.map then self:ReadMap(rare) end
    self:ReadSpot(rare)
    self:RefreshPin(rare)
    if Known(info.isDead, false) then
        self:MarkDead(rare)
    else
        self:PaintState(rare)
    end
end

function RA:VignetteGone(rare)
    local info = C_VignetteInfo.GetVignetteInfo(rare.vignetteGUID)
    if info and Known(info.isDead, false) then
        self:MarkDead(rare)
        return
    end
    rare.left = true
    self:PaintState(rare)
    if not rare.unit then self:RefreshHealth(rare) end
end

-- One read per vignette at card open, never on a tick. Returns the vignette to
-- follow, and whether it reports the creature dead. A vignette off the minimap is
-- not followed: its update adopts it if it comes on.
function RA:FindVignette(guid)
    local guids = C_VignetteInfo.GetVignettes()
    if not guids then return nil, false end
    for i = 1, #guids do
        local info = C_VignetteInfo.GetVignetteInfo(guids[i])
        if info and SameGUID(info.objectGUID, guid) then
            local follow = Known(info.onMinimap, false) and guids[i] or nil
            return follow, Known(info.isDead, false)
        end
    end
    return nil, false
end

-- A unit read the rare as alive, and its vignette may know better. Asked before
-- an alert commits to anything, so a dead rare replaces no card, takes no stamp
-- and plays nothing. A secret reading cannot overrule the plain one the alert
-- fired on. A card opened by its vignette has already read any unit in reach.
function RA:OpeningFindsDead(rare)
    if rare.vignetteGUID then return false end
    local follow, dead = self:FindVignette(rare.guid)
    rare.vignetteGUID = follow
    return dead
end

---------------------------------------------------------------------------------
-- Sound and party line
---------------------------------------------------------------------------------

function RA:PlayAlertSound()
    local name = self.db.SoundName
    if name == "None" then return end
    if name ~= RA.HORN_SOUND then
        local file = KE.LSM and KE.LSM:Fetch("sound", name, true)
        if file then
            PlaySoundFile(file, "Master")
            return
        end
    end
    PlaySoundFile(HORN_FILE, "Master")
end

function RA:PlayLoudEffects()
    self:PlayArrival()
    if self.db.PlaySound then self:PlayAlertSound() end
    if self.db.FlashTaskbar then FlashClientIcon() end
end

-- Position comes from the vignette only: a table spot is not where the rare is now.
function RA:AnnounceParty(rare)
    if not RA.PartyAllowed(self.db.AnnounceParty, rare.decision, IsInGroup(LE_PARTY_CATEGORY_HOME),
        IsInRaid(), InCombatLockdown(), KE:IsChatMessagingLocked()) then
        return
    end
    C_ChatInfo.SendChatMessage(RA.PartyLine(rare.name, rare.levelText, rare.elite, rare.x, rare.y), "PARTY")
end

---------------------------------------------------------------------------------
-- Tick
---------------------------------------------------------------------------------

-- One script on one card, set while a real card shows. Every countdown runs
-- from this accumulator.
local tickElapsed = 0

local function OnCardUpdate(_, elapsed)
    tickElapsed = tickElapsed + elapsed
    if tickElapsed < TICK_INTERVAL then return end
    local step = tickElapsed
    tickElapsed = 0
    RA:Tick(step)
end

function RA:StartTick()
    tickElapsed = 0
    self.card:SetScript("OnUpdate", OnCardUpdate)
end

function RA:StopTick()
    if self.card then self.card:SetScript("OnUpdate", nil) end
end

function RA:Tick(step)
    local rare = self.rare
    if not rare then return end
    rare.remaining = rare.remaining - step
    if rare.closeIn then rare.closeIn = rare.closeIn - step end
    if rare.remaining <= 0 or (rare.closeIn and rare.closeIn <= 0) then
        self:CloseCard()
        return
    end
    self:PaintTimeBar(rare.remaining / rare.total)
    if rare.unit then
        self:TokenHolds(rare)
        if self.rare ~= rare then return end
    end
    if rare.vignetteGUID and not rare.left and not rare.dead then
        if self.db.ShowDirection then self:UpdateBearing(rare) end
        if not rare.unit and self.db.ShowHealth then self:UpdateVignetteHealth(rare) end
    end
end

---------------------------------------------------------------------------------
-- Opening and closing
---------------------------------------------------------------------------------

function RA:CloseCard()
    self.rare = nil
    self.shown = nil
    self:StopTick()
    self:HideCard()
    self:SyncEvents()
    self:ClearTarget()
end

function RA:OpenCard(decision, rare)
    if self:OpeningFindsDead(rare) then return end
    if self.shown then self:CloseCard() end

    rare.decision = decision
    rare.total = self.db.StaysFor
    rare.remaining = rare.total
    rare.combat = InCombatLockdown()
    self.rare = rare
    self.shown = decision
    RA.Stamp(self.seen, rare.npc, GetTime())

    self:ReadMap(rare)
    self:ReadSpot(rare)
    self:ReadDrop(rare)

    self:BuildCard()
    self:ApplyCardLook()
    self:PaintIdentity(rare)
    self:PaintState(rare)
    self:PaintTimeBar(1)
    self:RefreshPin(rare)
    self:SetPortrait(rare.unit, rare.npc)
    self:RefreshBearing(rare)
    -- A token read here can close the card, and then nothing below may run.
    self:RefreshHealth(rare)
    if self.rare ~= rare then return end
    self.card:Show()
    self:ResolveToken()
    if self.rare ~= rare then return end

    self:SyncEvents()
    self:ArmTarget()
    self:CheckTargeted()
    self:StartTick()

    if decision == "loud" then
        self:PlayLoudEffects()
        self:AnnounceParty(rare)
    end
end

---------------------------------------------------------------------------------
-- Listeners
---------------------------------------------------------------------------------

-- With no card up, the common event ends at the classification, before any id
-- read and with no allocation. The creature on the card follows and never alerts
-- again, and any unit that shows it is read first, since it may disprove the card.
function RA:CheckUnit(source, unit)
    if self.rare then self:ResolveToken() end
    local rare = self.rare
    if not UnitExists(unit) then return end
    if rare and rare.unit and SameGUID(UnitGUID(unit), rare.guid) then
        self:ReadUnitState(rare)
        rare = self.rare
    end
    -- The GUID alone decides this: the class or name can read secret while it does not.
    if rare and source == "target" then self:CheckTargeted() end
    local class = Plain(UnitClassification(unit))
    if class ~= "rare" and class ~= "rareelite" then return end

    local guid, name = UnitGUID(unit), (UnitName(unit))
    if KE:IsSecretValue(guid) or KE:IsSecretValue(name) then return end
    if not guid or not name then return end
    local npc = RA.NpcOf(guid)

    if rare and rare.npc == npc then return end

    local gray, levelColor = UnitDanger(unit)
    local tapped = Known(UnitIsTapDenied(unit), false)
    local decision = RA.Decide({
        source = source,
        npc = npc,
        isRare = true,
        hostile = Known(UnitCanAttack("player", unit), false),
        dead = Known(UnitIsDead(unit), true),
        tapped = tapped,
        gray = gray,
        friendly = false,
        seenRecently = RA.SeenRecently(self.seen, npc, GetTime()),
    }, self.db)
    if decision == "none" or not RA.Replaces(decision, self.shown) then return end

    local level = Plain(UnitLevel(unit))
    self:OpenCard(decision, {
        npc = npc,
        guid = guid,
        name = name,
        unit = unit,
        unitSeen = true,
        elite = class == "rareelite",
        levelText = RA.LevelText(level, level),
        levelColor = levelColor,
        tapped = tapped,
    })
end

function RA:NAME_PLATE_UNIT_ADDED(_, unit)
    self:CheckUnit("plate", unit)
end

function RA:PLAYER_TARGET_CHANGED()
    self:CheckUnit("target", "target")
end

function RA:UPDATE_MOUSEOVER_UNIT()
    self:CheckUnit("mouseover", "mouseover")
end

function RA:NAME_PLATE_UNIT_REMOVED(_, unit)
    local rare = self.rare
    if not rare or rare.unit ~= unit then return end
    self:ResolveToken(unit)
end

function RA:VIGNETTE_MINIMAP_UPDATED(_, vignetteGUID, onMinimap)
    local rare = self.rare
    if not onMinimap then
        if rare and rare.vignetteGUID == vignetteGUID then self:VignetteGone(rare) end
        return
    end

    local info = C_VignetteInfo.GetVignetteInfo(vignetteGUID)
    if not info then return end
    local guid, name, atlas = info.objectGUID, info.name, info.atlasName
    if KE:IsSecretValue(guid) or KE:IsSecretValue(name) then return end
    if KE:IsSecretValue(atlas) then atlas = nil end
    local npc = RA.NpcOf(guid)
    if not npc or not name then return end

    -- The card follows its own spawn. Another spawn of the creature goes on to
    -- the decision, where the creature's stamp gives no card.
    if rare and rare.guid == guid then
        self:AdoptVignette(rare, vignetteGUID, info)
        return
    end

    local record = self:RareRecord(npc)
    local friendly = RecordFriendly(record)
    local dead = Known(info.isDead, true)
    local killAtlas = type(atlas) == "string" and atlas:find("Kill", 1, true) ~= nil
    local hostile, gray, tapped = true, RecordGray(record), false
    local unitIsRare, unitAttackable = true, false

    -- A unit in reach knows what the vignette and the table cannot, so its plain
    -- readings beat both. A secret reading cannot be known and changes nothing. With
    -- no unit in reach the table decides, and a tapped rare is loud and the card
    -- turns red when a unit shows it.
    local token = UnitTokenFromGUID(guid)
    if KE:IsSecretValue(token) then token = nil end
    if token then
        local class = Plain(UnitClassification(token))
        unitIsRare = not class or class == "rare" or class == "rareelite"
        local canAttack = UnitCanAttack("player", token)
        hostile = Known(canAttack, true)
        unitAttackable = Known(canAttack, false)
        if unitAttackable then friendly = false end
        dead = dead or Known(UnitIsDead(token), false)
        tapped = Known(UnitIsTapDenied(token), false)
        local unitGray, color = UnitDanger(token)
        if color then gray = unitGray end
    end
    local isRare = unitIsRare and RA.VignetteCounts(npc, onMinimap, dead, record ~= nil, friendly, killAtlas)

    -- An older proof binds until a unit reads the creature as attackable.
    local decision = RA.Decide({
        source = "vignette",
        npc = npc,
        isRare = isRare,
        hostile = hostile,
        dead = dead,
        tapped = tapped,
        gray = gray,
        friendly = friendly,
        seenRecently = RA.SeenRecently(self.seen, npc, GetTime()),
        provedWrong = not unitAttackable and RA.SeenRecently(self.proved, npc, GetTime()),
    }, self.db)
    if decision == "none" or not RA.Replaces(decision, self.shown) then return end

    local elite
    if record then
        elite = record.elite
    else
        elite = type(atlas) == "string" and atlas:find("Elite", 1, true) ~= nil
    end
    self:OpenCard(decision, {
        npc = npc,
        guid = guid,
        name = name,
        vignetteGUID = vignetteGUID,
        elite = elite,
        tapped = tapped,
        levelText = record and RA.LevelText(record.low, record.high),
        levelColor = record and record.high and GetCreatureDifficultyColor(record.high),
    })
end

function RA:UNIT_HEALTH(_, unit)
    local rare = self.rare
    if not rare or unit ~= rare.unit or not self:TokenHolds(rare) then return end
    self:ReadUnitHealth(rare)
    self:ReadUnitState(rare)
end

function RA:UNIT_FLAGS(_, unit)
    local rare = self.rare
    if not rare or unit ~= rare.unit or not self:TokenHolds(rare) then return end
    self:ReadUnitState(rare)
end

function RA:UNIT_FACTION(_, unit)
    local rare = self.rare
    if not rare or unit ~= rare.unit or not self:TokenHolds(rare) then return end
    self:ReadUnitState(rare)
end

function RA:UNIT_CLASSIFICATION_CHANGED(_, unit)
    local rare = self.rare
    if not rare or unit ~= rare.unit or not self:TokenHolds(rare) then return end
    self:ReadUnitState(rare)
    if self.rare ~= rare then return end
    local class = Plain(UnitClassification(unit))
    if class then rare.elite = class == "rareelite" end
    self:PaintIdentity(rare)
    self:PaintState(rare)
end

function RA:PLAYER_REGEN_DISABLED()
    local rare = self.rare
    if not rare then return end
    rare.combat = true
    self:PaintState(rare)
end

function RA:PLAYER_REGEN_ENABLED()
    local rare = self.rare
    if not rare then return end
    rare.combat = false
    self:PaintState(rare)
    self:SettleTarget()
end

function RA:PLAYER_ENTERING_WORLD()
    self.listening = not IsInInstance()
    if not self.listening and self.rare then self:CloseCard() end
    self:SyncEvents()
end

---------------------------------------------------------------------------------
-- Pin
---------------------------------------------------------------------------------

function RA:PlacePin()
    local rare = self.rare
    if not rare then return end
    local map, x, y = self:PinSpot(rare)
    if not map then return end
    if KE.Waypoint then
        KE.Waypoint.Place(rare.name, map, x, y)
        return
    end
    if not C_Map.CanSetUserWaypointOnMap(map) then
        KE:Print("That map does not take waypoints.")
        return
    end
    C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(map, x / 100, y / 100))
    C_SuperTrack.SetSuperTrackedUserWaypoint(true)
end

---------------------------------------------------------------------------------
-- Secure target button
---------------------------------------------------------------------------------

-- Parented to UIParent, not the card, so the card can hide and slide in combat
-- with no protected frame under it.
local TARGET_NAME = "KE_RareAlertTarget"
local TARGET_MACRO = "/targetexact %s"
-- Out of combat the clear keeps the skull off another target when the rare is out
-- of reach. A macro cannot change in combat, so each line reads combat at the press.
local SKULL_MACRO = "/cleartarget [nocombat]\n/targetexact %s\n/tm [nocombat] !8"
local TARGET_LEVEL_ABOVE = 10

function RA:CreateTarget()
    if self.target or InCombatLockdown() then return end
    local target = CreateFrame("Button", TARGET_NAME, UIParent,
        "SecureActionButtonTemplate, SecureHandlerStateTemplate")
    target:RegisterForClicks("AnyUp", "AnyDown")
    target:SetAttribute("type1", "macro")
    -- A bare /click passes down as false, and the secure handler would act only
    -- on the down while ActionButtonUseKeyDown is on.
    target:SetAttribute("useOnKeyDown", false)
    -- Combat entry is lockdown, so only a secure handler can hide the button
    -- then. Showing it again is ordinary Lua once combat ends.
    target:SetAttribute("_onstate-combat", [=[
        if newstate == "hide" then self:Hide() end
    ]=])
    target:SetScript("PostClick", function(_, button, down)
        if button == "RightButton" and not down and RA.rare then RA:CloseCard() end
    end)
    target:SetScript("OnLeave", function() RA:UncoverCard() end)
    target:Hide()
    self.target = target
end

function RA:ArmTarget()
    local rare, target = self.rare, self.target
    if not rare or not target or InCombatLockdown() then return end
    local macro = self.db.SkullOnClick and SKULL_MACRO or TARGET_MACRO
    target:SetAttribute("macrotext1", macro:format((rare.name:gsub("%c", ""))))
end

function RA:ClearTargetNow()
    -- A newer card owns the macro.
    if self.rare or InCombatLockdown() then return end
    self:UncoverCard()
    self.target:SetAttribute("macrotext1", nil)
end

function RA:ClearTarget()
    if not self.target then return end
    if InCombatLockdown() then
        KE:RunAfterCombat(function() self:ClearTargetNow() end)
        return
    end
    self:ClearTargetNow()
end

function RA:CoverCard()
    local card, target = self.card, self.target
    if not self.rare or not card or not target or InCombatLockdown() then return end
    -- These read secret with the card's anchor chain, and arithmetic on one raises
    -- an error. A secret one leaves the card uncovered.
    local left, bottom = Plain(card:GetLeft()), Plain(card:GetBottom())
    local height = Plain(card:GetHeight())
    local pin = self.parts.pin
    local right = pin:IsShown() and Plain(pin:GetLeft()) or Plain(card:GetRight())
    if not left or not bottom or not right or not height then return end
    local scale = card:GetEffectiveScale() / UIParent:GetEffectiveScale()
    target:ClearAllPoints()
    target:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left * scale, bottom * scale)
    target:SetSize((right - left) * scale, height * scale)
    target:SetFrameStrata(card:GetFrameStrata())
    target:SetFrameLevel(card:GetFrameLevel() + TARGET_LEVEL_ABOVE)
    -- The driver runs only while the button is up, so an idle button costs nothing.
    if not self.combatDriver then
        RegisterStateDriver(target, "combat", "[combat] hide; [nocombat] show")
        self.combatDriver = true
    end
    -- The driver writes only on a change, so a "hide" left by the last combat would
    -- swallow the next combat's hide and leave the button up through it.
    target:SetAttribute("state-combat", "show")
    target:Show()
end

function RA:UncoverCard()
    local target = self.target
    if not target or InCombatLockdown() then return end
    target:Hide()
    if self.combatDriver then
        UnregisterAttributeDriver(target)
        self.combatDriver = false
    end
end

-- Runs from the module's combat-end event and from the button's deferred
-- creation, in whichever order they arrive, so the last one finds the button.
function RA:SettleTarget()
    local card = self.card
    if not self.rare or not card or InCombatLockdown() then return end
    self:ArmTarget()
    if Known(card:IsMouseOver(), false) then
        self:CoverCard()
    else
        self:UncoverCard()
    end
end

-- The button covering the card takes the mouse from it, which is not a leave.
function RA:OnCardLeave()
    local target = self.target
    if target and target:IsShown() and Known(target:IsMouseOver(), false) then return end
    self:UncoverCard()
end

---------------------------------------------------------------------------------
-- Edit Mode
---------------------------------------------------------------------------------

function RA:RegWithEditMode()
    if KE.EditMode and not self.editModeRegistered then
        KE.EditMode:RegisterElement({
            key = "RareAlert",
            module = self,
            displayName = "Rare Alert",
            frame = self.holder,
            getPosition = function() return self.db.Position end,
            setPosition = function(pos)
                self.db.Position = pos
                KE:ApplyFramePosition(self.holder, self.db.Position, self.db)
            end,
            getParentFrame = function()
                return KE:ResolveAnchorFrame(self.db.anchorFrameType, self.db.ParentFrame)
            end,
            guiPath = "QualityOfLife",
            guiTab = "RareAlert",
        })
        self.editModeRegistered = true
    end
end

---------------------------------------------------------------------------------
-- Preview and settings
---------------------------------------------------------------------------------

function RA:PaintPreview()
    PREVIEW.levelColor = GetCreatureDifficultyColor(PREVIEW_LEVEL)
    PREVIEW.drop = self.db.ShowDrop and PREVIEW_DROP or nil
    self:ApplyCardLook()
    self:PaintIdentity(PREVIEW)
    self:PaintState(PREVIEW)
    self:PaintTimeBar(1)
    self:PaintPin(true)
    self:PaintBearing(PREVIEW_ROTATION, PREVIEW_YARDS)
    self:PaintHealth(100)
end

-- No tick, no sound, no stamp and no secure arm.
function RA:ShowPreview()
    if self.rare then return end
    self:CreateHolder()
    self:RegWithEditMode()
    self:BuildCard()
    self.shown = "preview"
    self:PaintPreview()
    self:SetPortrait(nil, PREVIEW.npc)
    self.card:Show()
end

-- A real alert that took over a preview stays up when the page closes.
function RA:HidePreview()
    if not self:IsEnabled() then return end
    if self.shown ~= "preview" then return end
    self.shown = nil
    self:HideCard()
end

function RA:TestAlert()
    if self.rare then self:CloseCard() end
    self:ShowPreview()
    self:PlayLoudEffects()
end

function RA:ResetPosition()
    local defaults = KE:GetDefaultDB().profile.RareAlert
    self.db.Position = CopyTable(defaults.Position)
    self.db.anchorFrameType = defaults.anchorFrameType
    self.db.ParentFrame = defaults.ParentFrame
    if self.holder then self:ApplyHolder() end
end

function RA:ApplySettings()
    if not self.holder then return end
    self:ApplyHolder()
    if self.listening then self:SyncEvents() end
    if not self.parts then return end
    self:ApplyCardLook()
    local rare = self.rare
    if rare then
        self:ReadDrop(rare)
        self:PaintState(rare)
        self:RefreshBearing(rare)
        self:RefreshHealth(rare)
        self:ArmTarget()
    elseif self.shown == "preview" then
        self:PaintPreview()
    end
end

---------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------

function RA:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

function RA:OnEnable()
    if not self.db.Enabled then return end
    self:CreateHolder()
    self:RegWithEditMode()
    self:RegisterEvent("PLAYER_ENTERING_WORLD")
    self:PLAYER_ENTERING_WORLD()
    KE:RunAfterCombat(function()
        if not self.db.Enabled then return end
        self:CreateTarget()
        self:SettleTarget()
    end)
end

function RA:OnDisable()
    self.listening = false
    self:CloseCard()
    self:UnregisterAllEvents()
    self.proved = {}
end
