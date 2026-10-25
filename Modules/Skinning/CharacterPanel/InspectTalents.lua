-- ╔══════════════════════════════════════════════════════════╗
-- ║  InspectTalents.lua                                      ║
-- ║  Module: Inspect Talents                                 ║
-- ║  Purpose: Talent tree panel beside the inspect window,   ║
-- ║           read from the inspect data Blizzard fetched,   ║
-- ║           compared against your own talents.             ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class InspectTalents: AceModule, AceEvent-3.0, AceHook-3.0
local IT = KitnEssentials:NewModule("InspectTalents", "AceEvent-3.0", "AceHook-3.0")

-- Both load before this file. InspectPanel's inspect-window helpers hold no
-- state, so they serve here while that module is disabled.
local IP = KitnEssentials:GetModule("InspectPanel", true)
local CP = KitnEssentials:GetModule("CharacterPanel", true)

local _G = _G
local CreateFrame = CreateFrame
local GameTooltip = GameTooltip
local C_AddOns = C_AddOns
local C_ClassTalents = C_ClassTalents
local C_Spell = C_Spell
local C_SpecializationInfo = C_SpecializationInfo
local C_Texture = C_Texture
local C_Timer = C_Timer
local C_TooltipInfo = C_TooltipInfo
local C_Traits = C_Traits
local GetSpecializationInfoForSpecID = GetSpecializationInfoForSpecID
local UnitName = UnitName
local issecretvalue = issecretvalue
local ipairs, pairs, pcall, type = ipairs, pairs, pcall, type
local tonumber, tostring = tonumber, tostring
local wipe = wipe
local floor, max, min, sqrt, atan2 = math.floor, math.max, math.min, math.sqrt, math.atan2

---------------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------------
local INSPECT_CONFIG_ID = -1
local GRID_UNIT = 300
local SPEC_SPLIT = 12.5
local SPEC_SHIFT = 2
local HEADER_H = 34
local PAD = 10
local COL_GAP = 20
local HERO_LABEL_H = 14
local LEGEND_H = 16
local NODE_GAP = 10
local APEX_EXTRA = 10
-- Room for the name, four chips and Copy Loadout above a narrow tree.
local MIN_WIDTH = 460
local STATE_W, STATE_H = 220, 80
local SUBLINE_Y = -19
local SUBLINE_GAP = 3
local ICON_SIZE = 12
local CHIP_W, CHIP_H, CHIP_GAP, CHIP_Y = 46, 26, 4, 4
local COPY_W, COPY_H, COPY_Y = 86, 20, 7
local SWATCH = 10
local DIFF_THICKNESS = 2
local UNTAKEN_SHADE = 0.45
local DEFAULT_NODE_SIZE = 22
local FALLBACK_ICON = 134400
local CHOICE_TEX = "Interface\\ChatFrame\\ChatFrameExpandArrow"
local ARROW_TEX = "Interface\\AddOns\\KitnEssentials\\Media\\GUITextures\\collapse.png"
local ARROW_SIZE, ARROW_GLYPH, ARROW_GAP = 18, 12, 2
local ARROW_RIGHT, ARROW_LEFT = 1.5708, -1.5708
local ARROW_REST = { 0.85, 0.85, 0.85 }
local MUTED = { 0.6, 0.6, 0.6 }
local EDGE_INACTIVE = { 0.46, 0.46, 0.52, 0.9 }
local NEUTRAL_BORDER = { 0, 0, 0, 1 }
local DIFF_COLORS = {
    theirs = { 0.239, 0.608, 1, 1 },
    yours = { 1, 0.643, 0.227, 1 },
    different = { 1, 1, 1, 1 },
}
local LEGEND = {
    { key = "theirs", text = "They have, you don't" },
    { key = "yours", text = "You have, they don't" },
    { key = "different", text = "Different pick or rank" },
}
local STATS_RETRY_DELAY = 0.6
local STATS_MAX_RETRIES = 4
local SEPARATOR = "\194\183"

local NodeType = Enum and Enum.TraitNodeType
local SUBTREE_SELECTION = NodeType and NodeType.SubTreeSelection or 3
local NODE_SELECTION = NodeType and NodeType.Selection or 2
local EntryType = Enum and Enum.TraitNodeEntryType
local CAPSTONE = {
    [EntryType and EntryType.SpendCapstoneCircle or 13] = true,
    [EntryType and EntryType.SpendCapstoneSquare or 14] = true,
}

-- Chip order on a tie, and the localized names the gear lines are matched on.
local STAT_ORDER = {
    { key = "haste", label = "HASTE", token = "ITEM_MOD_HASTE_RATING_SHORT" },
    { key = "mastery", label = "MAST", token = "ITEM_MOD_MASTERY_RATING_SHORT" },
    { key = "crit", label = "CRIT", token = "ITEM_MOD_CRIT_RATING_SHORT" },
    { key = "vers", label = "VERS", token = "ITEM_MOD_VERSATILITY" },
}
local STAT_SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17 }
local STAT_PATTERNS = {}
for _, def in ipairs(STAT_ORDER) do
    local name = _G[def.token]
    if type(name) == "string" and name ~= "" then
        STAT_PATTERNS[#STAT_PATTERNS + 1] = {
            key = def.key,
            pat = "%+([%d%.,%s]-)%s*" .. name:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1") .. "(.*)",
        }
    end
end

-- Use, equip and proc text quotes numbers that are not gear stats.
local SKIP_LINE_TYPES = {}
do
    local lineTypes = Enum and Enum.TooltipDataLineType
    if lineTypes then
        for _, n in ipairs({ "SpellDescription", "FlavorText", "UsageRequirement",
            "ItemSpellTriggerOnUse", "ItemSpellTriggerOnEquip", "ItemSpellTriggerOnProc" }) do
            if type(lineTypes[n]) == "number" then SKIP_LINE_TYPES[lineTypes[n]] = true end
        end
    end
end

---------------------------------------------------------------------------------
-- Rules (pure; exported for the spec)
---------------------------------------------------------------------------------
local function OpenGate(settingOn, moduleOn, frame, wanted, validRaw, readResult)
    if not settingOn or not moduleOn then return "hidden" end
    local shown = IP and IP.InspectFrameShown
    if not (shown and shown(frame)) then return "hidden" end
    if not wanted then return "closed" end
    if issecretvalue(validRaw) or validRaw ~= true then return "waiting" end
    if readResult == nil then return "waiting" end
    if readResult == "ready" then return "tree" end
    return "unavailable"
end
IT._OpenGate = OpenGate

-- One secret field the layout reads makes the whole read unavailable: a
-- tree with holes in it would misstate the build.
local function KeepNode(info)
    if type(info) ~= "table" then return "skip" end
    local visible, nodeType, posX, posY, sub = info.isVisible, info.type, info.posX, info.posY, info.subTreeID
    if issecretvalue(visible) or issecretvalue(nodeType) or issecretvalue(posX)
        or issecretvalue(posY) or issecretvalue(sub) then
        return "secret"
    end
    if not visible or nodeType == SUBTREE_SELECTION then return "skip" end
    if type(posY) ~= "number" or posY < 0 then return "skip" end
    if issecretvalue(info.ranksPurchased) or issecretvalue(info.activeRank)
        or issecretvalue(info.maxRanks) or issecretvalue(info.subTreeActive) then
        return "secret"
    end
    -- An unreadable pick would otherwise draw the first option as taken.
    local entry, ids = info.activeEntry, info.entryIDs
    if issecretvalue(entry) or issecretvalue(ids) then return "secret" end
    if type(entry) == "table" and issecretvalue(entry.entryID) then return "secret" end
    if type(ids) == "table" then
        for _, entryID in ipairs(ids) do
            if issecretvalue(entryID) then return "secret" end
        end
    end
    return "keep"
end
IT._KeepNode = KeepNode

local function PickHeroSubTree(subtrees)
    local flagged, infoActive, best, bestRanks
    for _, s in ipairs(subtrees) do
        local id = s.id
        if s.flagged and (flagged == nil or id < flagged) then flagged = id end
        if s.infoActive and (infoActive == nil or id < infoActive) then infoActive = id end
        local ranks = s.ranks or 0
        if ranks > 0 and (bestRanks == nil or ranks > bestRanks
            or (ranks == bestRanks and id < best)) then
            best, bestRanks = id, ranks
        end
    end
    return flagged or infoActive or best
end
IT._PickHeroSubTree = PickHeroSubTree

local function CompareGate(settingOn, theirSpecID, yourSpecID)
    if not settingOn then return "none" end
    if issecretvalue(theirSpecID) or issecretvalue(yourSpecID) then return "unknown" end
    if not theirSpecID or theirSpecID == 0 or not yourSpecID or yourSpecID == 0 then return "unknown" end
    if theirSpecID ~= yourSpecID then return "differs" end
    return "on"
end
IT._CompareGate = CompareGate

local function DiffCategory(theirEntry, theirRank, yourEntry, yourRank)
    if issecretvalue(theirEntry) or issecretvalue(theirRank)
        or issecretvalue(yourEntry) or issecretvalue(yourRank) then
        return nil
    end
    theirRank, yourRank = theirRank or 0, yourRank or 0
    if theirRank > 0 and yourRank == 0 then return "theirs" end
    if yourRank > 0 and theirRank == 0 then return "yours" end
    if theirRank > 0 and (theirEntry ~= yourEntry or theirRank ~= yourRank) then return "different" end
    return nil
end
IT._DiffCategory = DiffCategory

-- Your hero column compares only on a plain "active" signal for the drawn
-- subtree and nothing against it. Ranks never count: a hero tree you
-- switched away from keeps its purchased ranks.
local function HeroCompareOn(sawActive, sawOther, infoActive)
    if sawOther then return false end
    if sawActive then return true end
    if issecretvalue(infoActive) then return false end
    return infoActive == true
end
IT._HeroCompareOn = HeroCompareOn

---------------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------------
local panel, arrow
local nodePool, edgePool = {}, {}
local numNodes, numEdges = 0, 0
local records, byID, numRecords = {}, {}, 0
local entryCache, subInfoCache = {}, {}
local heroList, heroByID = {}, {}
local BL, BR, BH = {}, {}, {}
local rowMin, rowMax, heroShift = {}, {}, {}
local stats, chipOrder, sublinePieces = {}, {}, {}
local wanted, foreign, readPending = false, false, false
local readValid, readResult, readGUID = false, nil, nil
local playerName, specName, specIcon, theirSpecRaw
local heroSub, heroName, heroIcon
local compareState, yourSpecName = "none", nil
local statsShown, statTries, statTimer = false, 0, nil
local Apply

local function DB() return CP and CP.db end

local function Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d = pcall(fn, ...)
    if not ok then return nil end
    return a, b, c, d
end

local function WindowShown()
    local shown = IP and IP.InspectFrameShown
    return shown ~= nil and shown(_G.InspectFrame) == true
end

local function WindowGUID()
    local guid = IP and IP.InspectFrameGUID
    if not guid then return nil end
    return guid()
end

---------------------------------------------------------------------------------
-- Reading the inspected tree
---------------------------------------------------------------------------------
local function RankOf(info)
    local purchased, active = info.ranksPurchased, info.activeRank
    if issecretvalue(purchased) then return purchased end
    if issecretvalue(active) then return active end
    purchased = type(purchased) == "number" and purchased or 0
    active = type(active) == "number" and active or 0
    return max(purchased, active)
end

-- A secret answer is passed on, not turned into nil: nil means "no pick",
-- and the difference rule must see the secret to refuse it.
local function ActiveEntryID(info)
    local entry = info.activeEntry
    if issecretvalue(entry) then return entry end
    if type(entry) ~= "table" then return nil end
    return entry.entryID
end

local function EntryRef(entryID)
    if issecretvalue(entryID) or type(entryID) ~= "number" then return nil end
    local cached = entryCache[entryID]
    if cached ~= nil then return cached or nil end
    local ref = false
    local entry = Call(C_Traits.GetEntryInfo, INSPECT_CONFIG_ID, entryID)
    local defID = type(entry) == "table" and entry.definitionID or nil
    if not issecretvalue(defID) and type(defID) == "number" then
        local def = Call(C_Traits.GetDefinitionInfo, defID)
        if type(def) == "table" then
            local spellID, icon, name = def.spellID, def.overrideIcon, def.overrideName
            if issecretvalue(spellID) or type(spellID) ~= "number" then spellID = nil end
            if issecretvalue(icon) then icon = nil end
            if issecretvalue(name) or type(name) ~= "string" or name == "" then name = nil end
            if spellID and C_Spell then
                if not icon then
                    local tex = Call(C_Spell.GetSpellTexture, spellID)
                    if not issecretvalue(tex) then icon = tex end
                end
                if not name then
                    local spellName = Call(C_Spell.GetSpellName, spellID)
                    if not issecretvalue(spellName) and type(spellName) == "string" and spellName ~= "" then
                        name = spellName
                    end
                end
            end
            local entryType = entry.type
            ref = {
                entryID = entryID, spellID = spellID, icon = icon or FALLBACK_ICON, name = name,
                apex = not issecretvalue(entryType) and CAPSTONE[entryType] == true,
            }
        end
    end
    entryCache[entryID] = ref
    return ref or nil
end

local function InspectSubTree(subTreeID)
    local cached = subInfoCache[subTreeID]
    if cached ~= nil then return cached or nil end
    local info = Call(C_Traits.GetSubTreeInfo, INSPECT_CONFIG_ID, subTreeID)
    if type(info) ~= "table" then info = false end
    subInfoCache[subTreeID] = info
    return info or nil
end

local function GridX(v) return floor(v / GRID_UNIT + 0.5) * 0.5 end
local function GridY(v) return -floor(-v / GRID_UNIT + 0.5) * 0.5 end

local function AcquireRecord()
    numRecords = numRecords + 1
    local rec = records[numRecords]
    if rec then
        wipe(rec)
    else
        rec = {}
        records[numRecords] = rec
    end
    return rec
end

-- KeepNode has already refused a secret position, type, subtree or rank.
local function FillRecord(rec, nodeID, info)
    local sub = info.subTreeID
    local posX, posY = info.posX, info.posY
    if type(posX) ~= "number" then posX = 0 end
    rec.id = nodeID
    if sub then
        local si = InspectSubTree(sub)
        local ox, oy = si and si.posX, si and si.posY
        if issecretvalue(ox) or type(ox) ~= "number" then ox = 0 end
        if issecretvalue(oy) or type(oy) ~= "number" then oy = 0 end
        rec.sub = sub
        rec.ix, rec.iy = GridX(posX - ox), GridY(posY - oy)
    else
        local ix = GridX(posX)
        if ix >= SPEC_SPLIT then
            rec.ix = ix - SPEC_SHIFT
        else
            rec.ix, rec.isLeft = ix, true
        end
        rec.iy = GridY(posY)
    end
    local rank = RankOf(info)
    rec.rank, rec.active = rank, rank > 0
    local maxRanks = info.maxRanks
    rec.maxRank = type(maxRanks) == "number" and maxRanks or 1
    rec.isChoice = info.type == NODE_SELECTION
    local entryRaw = ActiveEntryID(info)
    rec.entryRaw = entryRaw
    local chosen
    if not issecretvalue(entryRaw) then chosen = entryRaw end
    local ids = info.entryIDs
    if issecretvalue(ids) or type(ids) ~= "table" then ids = nil end
    if not chosen and ids and not issecretvalue(ids[1]) then chosen = ids[1] end
    rec.ref = EntryRef(chosen)
    rec.apex = rec.ref ~= nil and rec.ref.apex == true
    if rec.isChoice and ids then
        for _, entryID in ipairs(ids) do
            if not issecretvalue(entryID) and entryID ~= chosen then
                local other = EntryRef(entryID)
                if other then
                    rec.other = other
                    break
                end
            end
        end
    end
    local edges = info.visibleEdges
    if not issecretvalue(edges) and type(edges) == "table" then rec.edges = edges end
    if sub then
        local summary = heroByID[sub]
        if not summary then
            local si = InspectSubTree(sub)
            local isActive = si and si.isActive
            summary = { id = sub, flagged = false, ranks = 0,
                infoActive = not issecretvalue(isActive) and isActive == true }
            heroByID[sub] = summary
            heroList[#heroList + 1] = summary
        end
        if info.subTreeActive == true then summary.flagged = true end
        summary.ranks = summary.ranks + rank
    end
end

local function ReadTree()
    numRecords = 0
    wipe(byID)
    wipe(entryCache)
    wipe(subInfoCache)
    wipe(heroList)
    wipe(heroByID)
    heroSub, heroName, heroIcon, readResult = nil, nil, nil, nil
    local valid = Call(C_Traits.HasValidInspectData)
    readValid = not issecretvalue(valid) and valid == true
    if not readValid then return end
    local config = Call(C_Traits.GetConfigInfo, INSPECT_CONFIG_ID)
    local trees = type(config) == "table" and config.treeIDs or nil
    local treeID = type(trees) == "table" and trees[1] or nil
    if issecretvalue(treeID) or type(treeID) ~= "number" then return end
    local nodeIDs = Call(C_Traits.GetTreeNodes, treeID)
    if type(nodeIDs) ~= "table" then return end
    for _, nodeID in ipairs(nodeIDs) do
        if not issecretvalue(nodeID) then
            local info = Call(C_Traits.GetNodeInfo, INSPECT_CONFIG_ID, nodeID)
            local verdict = KeepNode(info)
            if verdict == "secret" then
                numRecords = 0
                readResult = "secret"
                return
            elseif verdict == "keep" then
                FillRecord(AcquireRecord(), nodeID, info)
            end
        end
    end
    -- Only the active hero tree is drawn; the swap keeps every pooled record.
    heroSub = PickHeroSubTree(heroList)
    local kept = 0
    for i = 1, numRecords do
        local rec = records[i]
        if not rec.sub or rec.sub == heroSub then
            kept = kept + 1
            records[i], records[kept] = records[kept], rec
            byID[rec.id] = rec
        end
    end
    numRecords = kept
    if heroSub then
        local si = InspectSubTree(heroSub)
        local name, atlas = si and si.name, si and si.iconElementID
        if not issecretvalue(name) and type(name) == "string" and name ~= "" then heroName = name end
        if not issecretvalue(atlas) and type(atlas) == "string" and atlas ~= ""
            and C_Texture and Call(C_Texture.GetAtlasInfo, atlas) then
            heroIcon = atlas
        end
    end
    readResult = numRecords > 0 and "ready" or "empty"
end

local function ReadIdentity(unit)
    playerName, specName, specIcon, theirSpecRaw = nil, nil, nil, nil
    if not unit then return end
    local name = Call(UnitName, unit)
    if not issecretvalue(name) and type(name) == "string" and name ~= "" then playerName = name end
    local id
    if C_SpecializationInfo then id = Call(C_SpecializationInfo.GetInspectSpecialization, unit) end
    theirSpecRaw = id
    if issecretvalue(id) or type(id) ~= "number" or id == 0 then return end
    local _, sName, _, sIcon = Call(GetSpecializationInfoForSpecID, id)
    if not issecretvalue(sName) and type(sName) == "string" and sName ~= "" then specName = sName end
    if not issecretvalue(sIcon) and sIcon then specIcon = sIcon end
end

---------------------------------------------------------------------------------
-- Comparing with your own talents
---------------------------------------------------------------------------------
local function YourSpec()
    if not C_SpecializationInfo then return nil, nil end
    local index = Call(C_SpecializationInfo.GetSpecialization)
    if issecretvalue(index) or type(index) ~= "number" then return nil, nil end
    local id, name = Call(C_SpecializationInfo.GetSpecializationInfo, index)
    if issecretvalue(name) or type(name) ~= "string" then name = nil end
    return id, name
end

-- Two different hero trees share no talents, so the hero column compares
-- only when your active hero tree is the one drawn.
local function ReadYours(settingOn)
    for i = 1, numRecords do records[i].diff = nil end
    local yourSpec, name
    if settingOn then yourSpec, name = YourSpec() end
    yourSpecName = name
    compareState = CompareGate(settingOn, theirSpecRaw, yourSpec)
    if compareState ~= "on" or readResult ~= "ready" then return end
    local configID = C_ClassTalents and Call(C_ClassTalents.GetActiveConfigID) or nil
    if issecretvalue(configID) or type(configID) ~= "number" then
        compareState = "unknown"
        return
    end
    local sawActive, sawOther = false, false
    for i = 1, numRecords do
        local rec = records[i]
        local info = Call(C_Traits.GetNodeInfo, configID, rec.id)
        local yourEntry, yourRank
        if type(info) == "table" then
            yourEntry, yourRank = ActiveEntryID(info), RankOf(info)
            if rec.sub then
                local active = info.subTreeActive
                if issecretvalue(active) or active == false then
                    sawOther = true
                elseif active == true then
                    sawActive = true
                end
            end
        end
        rec.diff = DiffCategory(rec.entryRaw, rec.rank, yourEntry, yourRank)
    end
    if not heroSub then return end
    local infoActive
    local si = Call(C_Traits.GetSubTreeInfo, configID, heroSub)
    if type(si) == "table" then infoActive = si.isActive end
    if not HeroCompareOn(sawActive, sawOther, infoActive) then
        for i = 1, numRecords do
            if records[i].sub then records[i].diff = nil end
        end
    end
end

---------------------------------------------------------------------------------
-- Gear stats
---------------------------------------------------------------------------------
local function TailOK(tail)
    if tail == "" or not tail:match("^%s*%a") then return true end
    return tail:find("+", 1, true) ~= nil
end

local function ToRating(digits)
    return tonumber((digits:gsub("%D", ""))) or 0
end

local function StripColors(text)
    return (text:gsub("|cn.-:", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

local function ScanSlot(unit, slot)
    local data = Call(C_TooltipInfo.GetInventoryItem, unit, slot)
    if issecretvalue(data) or type(data) ~= "table" then return end
    local lines = data.lines
    if issecretvalue(lines) or type(lines) ~= "table" then return end
    for _, line in ipairs(lines) do
        if not issecretvalue(line) and type(line) == "table" then
            local lineType, text = line.type, line.leftText
            if not issecretvalue(lineType) and not SKIP_LINE_TYPES[lineType]
                and not issecretvalue(text) and type(text) == "string" and text ~= "" then
                text = StripColors(text)
                for _, p in ipairs(STAT_PATTERNS) do
                    local digits, tail = text:match(p.pat)
                    if digits and TailOK(tail) then
                        stats[p.key] = (stats[p.key] or 0) + ToRating(digits)
                    end
                end
            end
        end
    end
end

local RetryStats

local function CancelStatsRetry()
    if statTimer then statTimer:Cancel() end
    statTimer = nil
end

-- Gear tooltips can read empty until the item data lands; a few spaced
-- retries cover that without an event to wait on.
local function ReadStats(unit)
    wipe(stats)
    statsShown = false
    local db = DB()
    if not (db and db.InspectTalentsShowStats ~= false and unit) then return end
    for _, slot in ipairs(STAT_SLOTS) do ScanSlot(unit, slot) end
    for _, def in ipairs(STAT_ORDER) do
        if (stats[def.key] or 0) > 0 then statsShown = true end
    end
    if statsShown or foreign or statTries >= STATS_MAX_RETRIES then return end
    statTries = statTries + 1
    CancelStatsRetry()
    statTimer = C_Timer.NewTimer(STATS_RETRY_DELAY, RetryStats)
end

RetryStats = function()
    statTimer = nil
    if not IT:IsEnabled() or foreign or not WindowShown() then return end
    if readGUID == nil or readGUID ~= WindowGUID() then return end
    local frame = _G.InspectFrame
    ReadStats(frame and frame.unit)
    IT:RepaintChips()
end

---------------------------------------------------------------------------------
-- Frames
---------------------------------------------------------------------------------
local function Style(fs, size, color)
    if CP then CP:ApplyFont(fs, size) end
    fs:SetTextColor(color[1], color[2], color[3])
end

-- Every text gets a font at creation: SetText on a FontString with no font
-- raises. The Character Panel font is applied over it at paint time.
local TEXT_TEMPLATE = "GameFontHighlightSmall"
IT._TEXT_TEMPLATE = TEXT_TEMPLATE

local function NewText(parent, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY", TEXT_TEMPLATE)
    -- The template carries a drop shadow that the Character Panel font
    -- does not reset; Character Panel texts draw without one.
    fs:SetShadowColor(0, 0, 0, 0)
    fs:SetJustifyH(justify or "LEFT")
    return fs
end
IT._NewText = NewText

local function NewBox(parent, frameType)
    local box = CreateFrame(frameType or "Frame", nil, parent)
    box.bg = box:CreateTexture(nil, "BACKGROUND")
    box.bg:SetAllPoints()
    KE:AddBorders(box, KE.Theme.border)
    return box
end

-- Hover state is kept on the button so a repaint after a theme change
-- keeps the hover color.
local function ArrowColor(button)
    local color = ARROW_REST
    if button.hot then
        local skins = KE.Skins
        color = (skins and skins.palette and skins.palette.brand) or KE.Theme.accent
    end
    button.glyph:SetVertexColor(color[1], color[2], color[3])
end

local function ArrowOnEnter(self)
    self.hot = true
    ArrowColor(self)
end

local function ArrowOnLeave(self)
    self.hot = false
    ArrowColor(self)
end

local function ArrowOnClick()
    wanted = not wanted
    Apply()
end

-- Anchored to the close button so it follows that button with or without
-- a skin restyling the window.
local function EnsureArrow()
    if arrow then return arrow end
    local frame = _G.InspectFrame
    if not frame then return nil end
    -- Built in a local, hidden from the start, and published last, so a
    -- raise part way leaves no half-built arrow for later calls to trust.
    local a = CreateFrame("Button", nil, frame)
    a:Hide()
    a:SetSize(ARROW_SIZE, ARROW_SIZE)
    local close = frame.CloseButton
    if close then
        a:SetPoint("TOP", close, "BOTTOM", 0, -ARROW_GAP)
        -- Frame level is a secret aspect; on a secret answer the arrow
        -- keeps its default level, one above the window.
        local level = close:GetFrameLevel()
        if not issecretvalue(level) and type(level) == "number" then
            a:SetFrameLevel(level + 1)
        end
    else
        a:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -28)
    end
    local glyph = a:CreateTexture(nil, "OVERLAY")
    glyph:SetPoint("CENTER")
    glyph:SetSize(ARROW_GLYPH, ARROW_GLYPH)
    glyph:SetTexture(ARROW_TEX)
    a.glyph = glyph
    a:SetScript("OnEnter", ArrowOnEnter)
    a:SetScript("OnLeave", ArrowOnLeave)
    a:SetScript("OnClick", ArrowOnClick)
    ArrowColor(a)
    arrow = a
    IT.arrow = a
    return a
end

local function CopyBorder(btn)
    local c = btn.hot and KE.Theme.accent or KE.Theme.border
    btn:SetBorderColor(c[1], c[2], c[3], c[4] or 1)
end

local function CopyOnEnter(self)
    self.hot = true
    CopyBorder(self)
end

local function CopyOnLeave(self)
    self.hot = false
    CopyBorder(self)
end

local function CopyLoadout()
    local frame = _G.InspectFrame
    local unit = frame and frame.unit
    local loadout
    -- After a foreign reply the inspect data is another player's.
    if unit and not foreign then loadout = Call(C_Traits.GenerateInspectImportString, unit) end
    if issecretvalue(loadout) or type(loadout) ~= "string" or loadout == "" then
        KE:Print("Talent loadout not available for this player.")
        return
    end
    KE:CreatePrompt("Talent Loadout", loadout, true,
        "Press Ctrl+C to copy, then use Import in your talents window.",
        false, nil, nil, nil, nil, nil, nil, nil, "Close")
end

local function EnsurePanel()
    if panel then return panel end
    local frame = _G.InspectFrame
    if not frame then return nil end
    -- Built in a local, hidden from the start, and published last, so a
    -- raise part way leaves no half-built panel for later calls to trust.
    local p = CreateFrame("Frame", nil, frame)
    p:Hide()
    p:SetPoint("TOPLEFT", frame, "TOPRIGHT", 2, 0)
    p:SetClampedToScreen(true)
    p.bg = p:CreateTexture(nil, "BACKGROUND")
    p.bg:SetAllPoints()
    KE:AddBorders(p, KE.Theme.border)

    p.name = NewText(p)
    p.name:SetPoint("TOPLEFT", p, "TOPLEFT", PAD, -5)
    local specFrame = CreateFrame("Frame", nil, p)
    specFrame:SetSize(ICON_SIZE, ICON_SIZE)
    specFrame.icon = specFrame:CreateTexture(nil, "ARTWORK")
    specFrame.icon:SetAllPoints()
    KE:ApplyIconZoom(specFrame.icon, 0.3)
    KE:AddIconBorders(specFrame, KE.Theme.border)
    p.specFrame = specFrame
    p.specText = NewText(p)
    p.dot = NewText(p)
    p.dot:SetText(SEPARATOR)
    p.heroIcon = p:CreateTexture(nil, "ARTWORK")
    p.heroIcon:SetSize(ICON_SIZE, ICON_SIZE)
    p.heroText = NewText(p)
    p.note = NewText(p, "CENTER")
    p.note:SetPoint("CENTER", p, "CENTER", 0, -8)
    p.heroLabel = NewText(p, "CENTER")
    p.legendNote = NewText(p)
    p.legendNote:SetPoint("TOPLEFT", p, "TOPLEFT", PAD, -(HEADER_H + 2))

    p.swatches = {}
    local prev
    for i, entry in ipairs(LEGEND) do
        local swatch = CreateFrame("Frame", nil, p)
        swatch:SetSize(SWATCH, SWATCH)
        swatch.ring = swatch:CreateTexture(nil, "BACKGROUND")
        swatch.ring:SetAllPoints()
        swatch.fill = swatch:CreateTexture(nil, "ARTWORK")
        swatch.label = NewText(p)
        swatch.label:SetPoint("LEFT", swatch, "RIGHT", 4, 0)
        if prev then
            swatch:SetPoint("LEFT", prev.label, "RIGHT", 12, 0)
        else
            swatch:SetPoint("TOPLEFT", p, "TOPLEFT", PAD, -(HEADER_H + 3))
        end
        swatch.key, swatch.text = entry.key, entry.text
        p.swatches[i] = swatch
        prev = swatch
    end

    local copy = NewBox(p, "Button")
    copy:SetSize(COPY_W, COPY_H)
    copy:SetPoint("TOPRIGHT", p, "TOPRIGHT", -PAD, -COPY_Y)
    copy.label = NewText(copy, "CENTER")
    copy.label:SetPoint("CENTER")
    copy:SetScript("OnEnter", CopyOnEnter)
    copy:SetScript("OnLeave", CopyOnLeave)
    copy:SetScript("OnClick", CopyLoadout)
    p.copy = copy

    p.chips = {}
    for i = 1, #STAT_ORDER do
        local chip = NewBox(p)
        chip:SetSize(CHIP_W, CHIP_H)
        chip.label = NewText(chip, "CENTER")
        chip.label:SetPoint("TOP", chip, "TOP", 0, -3)
        chip.value = NewText(chip, "CENTER")
        chip.value:SetPoint("BOTTOM", chip, "BOTTOM", 0, 3)
        p.chips[i] = chip
    end

    panel = p
    IT.panel = p
    return p
end

---------------------------------------------------------------------------------
-- Tooltips
---------------------------------------------------------------------------------
local FillTooltip

local function AddRank(tt, rec)
    if rec.active and rec.maxRank > 1 then
        tt:AddLine(("Rank %d / %d"):format(rec.rank, rec.maxRank), 1, 0.82, 0)
    end
end

local function AddExtras(tt, rec)
    if not rec.active then tt:AddLine("Not taken", MUTED[1], MUTED[2], MUTED[3]) end
    local other = rec.other
    if other and other.name then
        tt:AddLine("Other choice: " .. other.name, MUTED[1], MUTED[2], MUTED[3])
    end
end

-- The trait data holds only the description, so the title is written here
-- and the data appended. A data refresh would rebuild from the data alone
-- and lose the added lines; rebuildPreCall refills the whole tooltip
-- instead, on both the trait and the spell route.
FillTooltip = function(tt, btn)
    local rec = btn.rec
    local ref = rec and rec.ref
    if not ref then return false end
    tt:ClearLines()
    local filled = false
    if ref.name and ref.entryID then
        tt:AddLine(ref.name, 1, 1, 1)
        AddRank(tt, rec)
        local before = tt:NumLines()
        local info = btn.tipInfo
        info.getterArgs[1], info.getterArgs[2] = ref.entryID, rec.rank
        info.tooltipData = nil
        -- A declined rebuild clears append on the primary info.
        info.append = true
        local ok = pcall(tt.ProcessInfo, tt, info)
        filled = ok and tt:NumLines() > before
    end
    if not filled then
        tt:ClearLines()
        if not ref.spellID then return false end
        local info = btn.spellInfo
        info.getterArgs[1] = ref.spellID
        info.tooltipData = nil
        local ok = pcall(tt.ProcessInfo, tt, info)
        if not ok or tt:NumLines() == 0 then return false end
        AddRank(tt, rec)
    end
    AddExtras(tt, rec)
    tt:Show()
    return true
end

local function NodeOnEnter(btn)
    if not btn.rec then return end
    GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
    if not FillTooltip(GameTooltip, btn) then GameTooltip:Hide() end
end

local function NodeOnLeave()
    GameTooltip:Hide()
end

---------------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------------
-- The border is a texture under an inset icon, so the difference border can
-- be two pixels wide; KE:AddIconBorders re-snaps its borders to one.
local function AcquireNode(i)
    local btn = nodePool[i]
    if btn then return btn end
    btn = CreateFrame("Button", nil, panel)
    -- Hidden until painted; the pool stores it only once built.
    btn:Hide()
    btn.border = btn:CreateTexture(nil, "BACKGROUND")
    btn.border:SetAllPoints()
    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    KE:ApplyIconZoom(btn.icon, 0.3)
    btn.rank = NewText(btn, "CENTER")
    btn.choice = btn:CreateTexture(nil, "OVERLAY")
    btn.choice:SetTexture(CHOICE_TEX)
    btn.choice:SetPoint("CENTER", btn, "RIGHT", 0, 0)
    local function Rebuild(tt)
        if tt:GetOwner() ~= btn or not btn.rec then return false end
        -- Blizzard's default rebuild would replay the description alone.
        if not FillTooltip(tt, btn) then tt:Hide() end
        return true
    end
    btn.tipInfo = { getterName = "GetTraitEntry", getterArgs = { n = 2 }, append = true,
        rebuildPreCall = Rebuild }
    btn.spellInfo = { getterName = "GetSpellByID", getterArgs = { n = 1 },
        rebuildPreCall = Rebuild }
    btn:SetScript("OnEnter", NodeOnEnter)
    btn:SetScript("OnLeave", NodeOnLeave)
    nodePool[i] = btn
    return btn
end

local function AcquireEdge(i)
    local edge = edgePool[i]
    if not edge then
        edge = panel:CreateTexture(nil, "BORDER")
        edgePool[i] = edge
    end
    return edge
end

local function ReleaseAll()
    for i = 1, numNodes do
        nodePool[i].rec = nil
        nodePool[i]:Hide()
    end
    for i = 1, numEdges do edgePool[i]:Hide() end
    numNodes, numEdges = 0, 0
end

-- KE:AddIconBorders gives no recolor method; the border is repainted from
-- the theme here so a theme change reaches it.
local function IconBorderColor(frame, c)
    local borders = frame.borders
    if not borders then return end
    for _, tex in pairs(borders) do
        tex:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
        tex:SetSnapToPixelGrid(false)
    end
end

local function PaintHeader(tree)
    local T = KE.Theme
    IconBorderColor(panel.specFrame, T.border)
    Style(panel.name, 12, T.textPrimary)
    panel.name:SetText(playerName or "Talents")
    panel.specFrame:Hide()
    panel.specText:Hide()
    panel.dot:Hide()
    panel.heroIcon:Hide()
    panel.heroText:Hide()
    if not tree then return end
    wipe(sublinePieces)
    if specName then
        if specIcon then
            panel.specFrame.icon:SetTexture(specIcon)
            sublinePieces[#sublinePieces + 1] = panel.specFrame
        end
        Style(panel.specText, 10, MUTED)
        panel.specText:SetText(specName)
        sublinePieces[#sublinePieces + 1] = panel.specText
    end
    if heroName then
        if specName then
            Style(panel.dot, 10, MUTED)
            sublinePieces[#sublinePieces + 1] = panel.dot
        end
        if heroIcon then
            panel.heroIcon:SetAtlas(heroIcon)
            sublinePieces[#sublinePieces + 1] = panel.heroIcon
        end
        Style(panel.heroText, 10, MUTED)
        panel.heroText:SetText(heroName)
        sublinePieces[#sublinePieces + 1] = panel.heroText
    end
    local prev
    for _, piece in ipairs(sublinePieces) do
        piece:ClearAllPoints()
        if prev then
            piece:SetPoint("LEFT", prev, "RIGHT", SUBLINE_GAP, 0)
        else
            piece:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, SUBLINE_Y)
        end
        piece:Show()
        prev = piece
    end
end

-- Largest rating first; an insertion sort, so equal ratings keep the
-- STAT_ORDER order (table.sort is not stable).
local function OrderChips(values, out)
    for i, def in ipairs(STAT_ORDER) do
        local v = values[def.key] or 0
        local j = i
        while j > 1 and (values[out[j - 1].key] or 0) < v do
            out[j] = out[j - 1]
            j = j - 1
        end
        out[j] = def
    end
    return out
end
IT._OrderChips = OrderChips

local function PaintChips(show)
    local T = KE.Theme
    local count = 0
    if show then
        OrderChips(stats, chipOrder)
        count = #STAT_ORDER
    end
    for i, chip in ipairs(panel.chips) do
        if i <= count then
            local def = chipOrder[i]
            chip.bg:SetColorTexture(T.bgMedium[1], T.bgMedium[2], T.bgMedium[3], T.bgMedium[4] or 1)
            chip:SetBorderColor(T.border[1], T.border[2], T.border[3], T.border[4] or 1)
            Style(chip.label, 8, MUTED)
            chip.label:SetText(def.label)
            Style(chip.value, 11, T.textPrimary)
            chip.value:SetText(tostring(stats[def.key] or 0))
            chip:ClearAllPoints()
            chip:SetPoint("TOPRIGHT", panel, "TOPRIGHT",
                -(PAD + COPY_W + CHIP_GAP + (count - i) * (CHIP_W + CHIP_GAP)), -CHIP_Y)
            chip:Show()
        else
            chip:Hide()
        end
    end
end

local function PaintCopy(show)
    local copy, T = panel.copy, KE.Theme
    if not show then
        copy:Hide()
        return
    end
    copy.bg:SetColorTexture(T.bgMedium[1], T.bgMedium[2], T.bgMedium[3], T.bgMedium[4] or 1)
    CopyBorder(copy)
    Style(copy.label, 10, T.textPrimary)
    copy.label:SetText("Copy Loadout")
    copy:Show()
end

local function PaintLegend(active)
    local T = KE.Theme
    local state = active and compareState or "none"
    local px2 = KE:GetPixelSize() * DIFF_THICKNESS
    for _, swatch in ipairs(panel.swatches) do
        if state == "on" then
            local c = DIFF_COLORS[swatch.key]
            swatch.ring:SetColorTexture(c[1], c[2], c[3], c[4])
            swatch.fill:ClearAllPoints()
            swatch.fill:SetPoint("TOPLEFT", swatch, "TOPLEFT", px2, -px2)
            swatch.fill:SetPoint("BOTTOMRIGHT", swatch, "BOTTOMRIGHT", -px2, px2)
            swatch.fill:SetColorTexture(T.bgDark[1], T.bgDark[2], T.bgDark[3], 1)
            Style(swatch.label, 9, T.textPrimary)
            swatch.label:SetText(swatch.text)
            swatch:Show()
            swatch.label:Show()
        else
            swatch:Hide()
            swatch.label:Hide()
        end
    end
    if state == "differs" then
        Style(panel.legendNote, 9, MUTED)
        panel.legendNote:SetText(("Comparison off: you are %s, they are %s."):format(
            yourSpecName or "another spec", specName or "another spec"))
        panel.legendNote:Show()
    else
        panel.legendNote:Hide()
    end
end

local function PaintNode(btn, rec, size, rankSize, compareOn)
    btn:SetSize(size, size)
    btn.rec = rec
    local diff = compareOn and rec.diff or nil
    local color = diff and DIFF_COLORS[diff] or NEUTRAL_BORDER
    local inset = KE:GetPixelSize() * (diff and DIFF_THICKNESS or 1)
    btn.border:SetColorTexture(color[1], color[2], color[3], color[4])
    local icon = btn.icon
    icon:ClearAllPoints()
    icon:SetPoint("TOPLEFT", btn, "TOPLEFT", inset, -inset)
    icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -inset, inset)
    icon:SetTexture(rec.ref and rec.ref.icon or FALLBACK_ICON)
    icon:SetDesaturated(not rec.active)
    local shade = rec.active and 1 or UNTAKEN_SHADE
    icon:SetVertexColor(shade, shade, shade)
    local rank = btn.rank
    Style(rank, rankSize, KE.Theme.textPrimary)
    rank:ClearAllPoints()
    if rec.apex then
        rank:SetPoint("TOP", btn, "BOTTOM", 0, -1)
    else
        rank:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 2, -2)
    end
    rank:SetText((rec.active and rec.maxRank > 1) and (rec.rank .. "/" .. rec.maxRank) or "")
    if rec.isChoice then
        local mark = max(8, floor(size * 0.4 + 0.5))
        btn.choice:SetSize(mark, mark)
        btn.choice:Show()
    else
        btn.choice:Hide()
    end
end

local function ResetBounds(t) t.minX, t.maxX, t.minY, t.maxY = 1e9, -1e9, 1e9, -1e9 end

local function Accumulate(t, rec)
    if rec.ix < t.minX then t.minX = rec.ix end
    if rec.ix > t.maxX then t.maxX = rec.ix end
    if rec.iy < t.minY then t.minY = rec.iy end
    if rec.iy > t.maxY then t.maxY = rec.iy end
end

local function Span(t) return t.maxX > -1e8 and (t.maxX - t.minX + 1) or 0 end

local function ColumnWidth(n, pitch, size) return n > 0 and ((n - 1) * pitch + size) or 0 end

local function BoundsOf(rec)
    if rec.sub then return BH end
    if rec.isLeft then return BL end
    return BR
end

local function DrawState(state)
    ReleaseAll()
    PaintHeader(false)
    PaintChips(false)
    PaintCopy(false)
    PaintLegend(false)
    panel.heroLabel:Hide()
    Style(panel.note, 11, MUTED)
    panel.note:SetText(state == "waiting" and "Waiting for talent data..." or "Talent data not available.")
    panel.note:Show()
    panel:SetSize(STATE_W, STATE_H)
end

local function DrawTree(db)
    ReleaseAll()
    panel.note:Hide()
    PaintHeader(true)
    PaintChips(db.InspectTalentsShowStats ~= false and statsShown)
    PaintCopy(true)
    PaintLegend(true)

    local T = KE.Theme
    local size = db.InspectTalentsNodeSize or DEFAULT_NODE_SIZE
    local pitch = size + NODE_GAP
    local compareOn = compareState == "on"
    local legend = compareState == "on" or compareState == "differs"
    ResetBounds(BL)
    ResetBounds(BR)
    ResetBounds(BH)
    local anyApex = false
    for i = 1, numRecords do
        local rec = records[i]
        Accumulate(BoundsOf(rec), rec)
        if rec.apex then anyApex = true end
    end
    local lW = ColumnWidth(Span(BL), pitch, size)
    local hW = ColumnWidth(Span(BH), pitch, size)
    local rW = ColumnWidth(Span(BR), pitch, size)
    local leftX = PAD
    local heroX = leftX + lW + COL_GAP
    local rightX = hW > 0 and (heroX + hW + COL_GAP) or heroX
    local treeTop = HEADER_H + (legend and LEGEND_H or 0) + PAD
    local heroTop = hW > 0 and HERO_LABEL_H or 0

    wipe(rowMin)
    wipe(rowMax)
    wipe(heroShift)
    if hW > 0 then
        for i = 1, numRecords do
            local rec = records[i]
            if rec.sub then
                local r = rec.iy
                if rowMin[r] == nil or rec.ix < rowMin[r] then rowMin[r] = rec.ix end
                if rowMax[r] == nil or rec.ix > rowMax[r] then rowMax[r] = rec.ix end
            end
        end
        local mid = (BH.minX + BH.maxX) * 0.5
        for r, lo in pairs(rowMin) do heroShift[r] = mid - (lo + rowMax[r]) * 0.5 end
    end

    local lrMinY = min(BL.minY, BR.minY)
    if lrMinY > 1e8 then lrMinY = 0 end
    local mainRows = 0
    if BL.maxY > -1e8 then mainRows = max(mainRows, BL.maxY - lrMinY + 1) end
    if BR.maxY > -1e8 then mainRows = max(mainRows, BR.maxY - lrMinY + 1) end
    local heroRows = BH.maxY > -1e8 and (BH.maxY - BH.minY + 1) or 0
    local body = max(ColumnWidth(mainRows, pitch, size), heroTop + ColumnWidth(heroRows, pitch, size))
    panel:SetSize(max(rightX + rW + PAD, MIN_WIDTH), treeTop + body + PAD + (anyApex and APEX_EXTRA or 0))

    local label = panel.heroLabel
    if hW > 0 and heroName then
        Style(label, 10, T.textPrimary)
        label:SetText(heroName)
        label:SetWidth(hW + COL_GAP)
        label:ClearAllPoints()
        label:SetPoint("TOP", panel, "TOPLEFT", heroX + hW * 0.5, -treeTop)
        label:Show()
    else
        label:Hide()
    end

    local rankSize = max(8, floor(size * 0.42 + 0.5))
    for i = 1, numRecords do
        local rec = records[i]
        -- Count only an acquired button, so ReleaseAll never meets a hole.
        local btn = AcquireNode(numNodes + 1)
        numNodes = numNodes + 1
        local bounds = BoundsOf(rec)
        local baseX = rec.sub and heroX or (rec.isLeft and leftX or rightX)
        local col = rec.ix - bounds.minX + (rec.sub and (heroShift[rec.iy] or 0) or 0)
        local rowBase = rec.sub and BH.minY or lrMinY
        local x = baseX + col * pitch
        local y = -(treeTop + (rec.sub and heroTop or 0) + (rec.iy - rowBase) * pitch)
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", panel, "TOPLEFT", x, y)
        PaintNode(btn, rec, size, rankSize, compareOn)
        btn:Show()
        rec.px, rec.py = x + size * 0.5, y - size * 0.5
    end

    local accent = T.accent
    local edgeW = max(2, floor(size / 10 + 0.5))
    for i = 1, numRecords do
        local rec = records[i]
        if rec.edges then
            for _, edgeInfo in ipairs(rec.edges) do
                local targetID = type(edgeInfo) == "table" and edgeInfo.targetNode or nil
                local target
                if not issecretvalue(targetID) and targetID then target = byID[targetID] end
                if target and target.px then
                    local dx, dy = target.px - rec.px, target.py - rec.py
                    local length = sqrt(dx * dx + dy * dy)
                    if length > 1 then
                        local edge = AcquireEdge(numEdges + 1)
                        numEdges = numEdges + 1
                        edge:SetSize(length, edgeW)
                        edge:ClearAllPoints()
                        edge:SetPoint("CENTER", panel, "TOPLEFT", (rec.px + target.px) * 0.5, (rec.py + target.py) * 0.5)
                        edge:SetRotation(atan2(dy, dx))
                        local on = edgeInfo.isActive
                        if issecretvalue(on) or on == nil then on = rec.active and target.active end
                        local c = on and accent or EDGE_INACTIVE
                        edge:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
                        edge:Show()
                    end
                end
            end
        end
    end
end

Apply = function()
    local db = DB()
    local settingOn = db ~= nil and db.InspectTalentsEnabled ~= false
    local moduleOn = IT:IsEnabled() and CP ~= nil and CP:IsEnabled()
    local state = OpenGate(settingOn, moduleOn, _G.InspectFrame, wanted, readValid, readResult)
    if panel then panel.shownState = nil end
    if state == "hidden" then
        if arrow then arrow:Hide() end
        if panel then panel:Hide() end
        return
    end
    local button = EnsureArrow()
    if button then
        button.glyph:SetRotation(state == "closed" and ARROW_RIGHT or ARROW_LEFT)
        ArrowColor(button)
        button:Show()
    end
    if state == "closed" or not EnsurePanel() then
        if panel then panel:Hide() end
        return
    end
    local T = KE.Theme
    panel.bg:SetColorTexture(T.bgDark[1], T.bgDark[2], T.bgDark[3], T.bgDark[4] or 1)
    panel:SetBorderColor(T.border[1], T.border[2], T.border[3], T.border[4] or 1)
    if state == "tree" then
        DrawTree(db)
    else
        DrawState(state)
    end
    panel.shownState = state
    panel:Show()
end

-- A stats retry changes only the chips; redrawing the tree would also hide
-- and reshow the hovered talent and its tooltip.
function IT:RepaintChips()
    if not (panel and panel.shownState == "tree") then
        Apply()
        return
    end
    local db = DB()
    PaintChips(db ~= nil and db.InspectTalentsShowStats ~= false and statsShown)
end

---------------------------------------------------------------------------------
-- Reads and window events
---------------------------------------------------------------------------------
local function ResetWindowState()
    wanted, foreign = false, false
    readValid, readResult, readGUID = false, nil, nil
    numRecords = 0
    wipe(byID)
    compareState, yourSpecName = "none", nil
    CancelStatsRetry()
    wipe(stats)
    statsShown, statTries = false, 0
    -- The header reads these; the reopened window's waiting panel must not
    -- show the last player.
    playerName, specName, specIcon, theirSpecRaw = nil, nil, nil, nil
    heroSub, heroName, heroIcon = nil, nil, nil
end

-- Reads run only on the window's own data (its show and its own inspect
-- reply): the inspect config holds whichever inspect answered last. A
-- foreign reply that lands before this deferred read has replaced it, so
-- the read waits for the window's next own reply.
local function RunRead()
    readPending = false
    if not IT:IsEnabled() or not WindowShown() or foreign then return end
    local frame = _G.InspectFrame
    local unit = frame and frame.unit
    readGUID = WindowGUID()
    ReadTree()
    ReadIdentity(unit)
    local db = DB()
    ReadYours(db ~= nil and db.InspectTalentsCompare ~= false)
    CancelStatsRetry()
    statTries = 0
    ReadStats(unit)
    Apply()
end

local function ScheduleRead()
    if readPending then return end
    readPending = true
    C_Timer.After(0, RunRead)
end

---------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------
function IT:OnInitialize()
    -- Enabled by the CharacterPanel cascade.
    self:SetEnabledState(false)
end

function IT:OnEnable()
    local db = DB()
    if not (db and db.Enabled and db.InspectTalentsEnabled ~= false) then return end
    if C_AddOns.IsAddOnLoaded("Blizzard_InspectUI") then
        self:InstallWindow()
    else
        self:RegisterEvent("ADDON_LOADED")
    end
end

-- AceHook removes the hooks on disable, so the latch goes with them.
function IT:OnDisable()
    self._hooked = nil
    ResetWindowState()
    if panel then
        ReleaseAll()
        panel:Hide()
    end
    if arrow then arrow:Hide() end
end

function IT:InstallWindow()
    local frame = _G.InspectFrame
    if not frame then return end
    if not self._hooked then
        self._hooked = true
        self:SecureHookScript(frame, "OnShow", "OnInspectShow")
        self:SecureHookScript(frame, "OnHide", "OnInspectHide")
    end
    -- The module is on by default, so no frame is made until a window
    -- show: the arrow and panel come from the first apply after it.
    if WindowShown() then self:OnInspectShow() end
end

function IT:ADDON_LOADED(event, name)
    if name ~= "Blizzard_InspectUI" then return end
    self:UnregisterEvent("ADDON_LOADED")
    self:InstallWindow()
end

function IT:OnInspectShow()
    if not self:IsEnabled() then return end
    self:RegisterEvent("INSPECT_READY")
    local db = DB()
    wanted = db ~= nil and db.InspectTalentsAutoOpen ~= false
    foreign = false
    -- The name comes from the window's own unit, not the inspect data.
    ReadIdentity(_G.InspectFrame and _G.InspectFrame.unit)
    -- The arrow, and the waiting state when requested, show at once.
    Apply()
    ScheduleRead()
end

-- A child frame keeps its own shown flag, so the reopened window would
-- show the last player's panel until the next apply.
function IT:OnInspectHide()
    self:UnregisterEvent("INSPECT_READY")
    ResetWindowState()
    if panel then
        panel:Hide()
        panel.shownState = nil
    end
    if arrow then arrow:Hide() end
end

function IT:INSPECT_READY(event, guid)
    local ready = IP and IP.ReadyForFrame
    if ready and ready(guid, WindowGUID()) then
        foreign = false
        ScheduleRead()
    else
        foreign = true
        CancelStatsRetry()
    end
end

function IT:Refresh()
    if self:IsEnabled() then Apply() end
end

-- Every accent is read from KE.Theme at paint time, so a closed panel
-- needs nothing here: its next open paints in the new theme.
function IT:OnThemeChanged()
    if not self:IsEnabled() then return end
    Apply()
end

-- Reads only your own talents against the stored records.
function IT:RequestCompare()
    if not self:IsEnabled() then return end
    local db = DB()
    ReadYours(db ~= nil and db.InspectTalentsCompare ~= false)
    Apply()
end

function IT:RequestStats()
    if not self:IsEnabled() then return end
    if not foreign and WindowShown() then
        local frame = _G.InspectFrame
        CancelStatsRetry()
        statTries = 0
        ReadStats(frame and frame.unit)
    end
    Apply()
end

-- The profile refresh calls this on a switch, copy, reset or import, with
-- no new inspect reply: re-derive what the settings change from the stored
-- read. Open Automatically applies at the next window opening.
function IT:ApplySettings()
    if not self:IsEnabled() then return end
    local db = DB()
    ReadYours(db ~= nil and db.InspectTalentsCompare ~= false)
    self:RequestStats()
end
