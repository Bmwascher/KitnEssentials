-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-DungeonTimers.lua                                   ║
-- ║  Single "Dungeon Timers" sidebar entry: tabbed host      ║
-- ║  (Dungeon Bosses | Dungeon Trash | General | Bars |      ║
-- ║  Texts | Nameplates) plus the two dungeon tabs —         ║
-- ║  shared Dungeon + Season dropdowns over the editor.      ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = KitnEssentials:GetNamespace()
local GUIFrame = KE.GUIFrame

local ipairs = ipairs
local select = select
local GetInstanceInfo = GetInstanceInfo

KE.GUI = KE.GUI or {}
KE.GUI.DungeonTimers = KE.GUI.DungeonTimers or {}

-- Read only by the in-game load check; each source change to these pages
-- raises it, so the check can tell the final pages from older ones.
KE.GUI.DungeonTimers.GUIRevision = 15

local function GetSettingsDB()
    if not KE.db or not KE.db.profile then return nil end
    return KE.db.profile.DungeonTimers
end

-- Session-sticky selection, shared by the Dungeon Bosses and Dungeon Trash tabs:
-- dropdown picks stick across tab switches and in-place refreshes, but the
-- priority (current dungeon > saved > newest-season fallback) re-runs
-- whenever the user LEAVES the page — sidebar navigation or GUI close drops
-- the sticky pick, and a profile switch hands the page a different settings
-- table, which resets it too. The current-dungeon override never writes
-- LastViewed — standing in a dungeon must not erase the selection the user
-- chose deliberately.
local activeSeason, activeDungeon, activeDB

local function ResetActiveSelection()
    activeSeason, activeDungeon, activeDB = nil, nil, nil
end

local function ResolveActive(db)
    if db ~= activeDB then ResetActiveSelection() end
    if activeDungeon then return end
    activeDB = db
    local instanceID = select(8, GetInstanceInfo())
    activeSeason, activeDungeon = KE.ResolveDungeonTimerSelection(
        KE.DungeonTimerDungeons, instanceID, db and db.LastViewed)
end

-- Every profile mutation path either passes through another sidebar item
-- (the Profiles page) or happens with the GUI closed, so resetting on
-- switch-away and on close covers profile changes without AceDB callback
-- wiring; the db-identity check above is the backstop for anything else.
GUIFrame:RegisterContentCleanup("DTimers_Dungeons_selection", ResetActiveSelection)
GUIFrame:RegisterOnCloseCallback("DTimers_Dungeons_selection", function()
    ResetActiveSelection()
    -- Show() replays a refresh only for dirty content; without this,
    -- closing on this page reopens onto the stale cached build instead of
    -- re-running the selection priority.
    if GUIFrame.selectedSidebarItem == "DTimers_Main" then
        GUIFrame._contentDirtyWhileHidden = true
    end
end)

local function FindEntry(key)
    for _, d in ipairs(KE.DungeonTimerDungeons) do
        if d.key == key then return d end
    end
end

-- Tab switches are in-place refreshes (same sidebar item), so the cleanup
-- callbacks don't fire — each tab hides the previews the other tabs may have
-- left running. The dungeon page itself picks which dungeon preview shows.
local function HideOtherTabPreviews()
    local DT_GUI = KE.GUI.DungeonTimers
    if DT_GUI.HideBarPreviews then DT_GUI.HideBarPreviews() end
    if DT_GUI.HideTextPreviews then DT_GUI.HideTextPreviews() end
    if DT_GUI.HideNameplatePreview then DT_GUI.HideNameplatePreview() end
end

-- Returns the next offset and the selected registry entry.
local function BuildSelectionCard(scrollChild, yOffset, db)
    local Theme = KE.Theme
    local DT_GUI = KE.GUI.DungeonTimers
    ResolveActive(db)

    local registry = KE.DungeonTimerDungeons
    local seasonOptions = {}
    for _, s in ipairs(KE.GetDungeonTimerSeasons(registry)) do
        seasonOptions[#seasonOptions + 1] = { key = s, text = "Season " .. s }
    end
    local dungeonOptions = {}
    for _, d in ipairs(KE.GetDungeonTimerDungeonsForSeason(registry, activeSeason)) do
        -- Inline texture tag with the standard icon crop, so the dungeon
        -- icon renders in the menu rows and the selected label alike.
        dungeonOptions[#dungeonOptions + 1] = {
            key = d.key,
            text = KE.GetDungeonTimerDungeonLabel(d.iconID, d.name),
        }
    end

    local card = GUIFrame:CreateCard(scrollChild, "Dungeon Selection", yOffset)
    local row = GUIFrame:CreateRow(card.content, Theme.rowHeightLast)
    local dungeonDropdown = GUIFrame:CreateDropdown(row, "Dungeon", {
        options = dungeonOptions,
        value = activeDungeon,
        callback = function(key)
            if key == activeDungeon then return end
            -- The refresh below is same-item and skips cleanup callbacks;
            -- without this hide, a preview from the outgoing dungeon leaks
            -- when the incoming one has no encounters to select.
            if DT_GUI.HideDungeonPreviews then DT_GUI.HideDungeonPreviews() end
            activeDungeon = key
            db.LastViewed = db.LastViewed or {}
            db.LastViewed.season = activeSeason
            db.LastViewed.dungeon = key
            GUIFrame:RefreshContent()
        end,
    })
    row:AddWidget(dungeonDropdown, 0.5)
    local seasonDropdown = GUIFrame:CreateDropdown(row, "Season", {
        options = seasonOptions,
        value = activeSeason,
        callback = function(key)
            if key == activeSeason then return end
            if DT_GUI.HideDungeonPreviews then DT_GUI.HideDungeonPreviews() end
            activeSeason = key
            local list = KE.GetDungeonTimerDungeonsForSeason(registry, key)
            activeDungeon = list[1] and list[1].key or nil
            db.LastViewed = db.LastViewed or {}
            db.LastViewed.season = key
            db.LastViewed.dungeon = activeDungeon
            GUIFrame:RefreshContent()
        end,
    })
    row:AddWidget(seasonDropdown, 0.5)
    card:AddRow(row, Theme.rowHeightLast, 0)
    return card:GetNextOffset(), FindEntry(activeDungeon)
end

local function RegisterDungeonView(contentId, view)
    GUIFrame:RegisterContent(contentId, function(scrollChild, yOffset)
        HideOtherTabPreviews()
        local db = GetSettingsDB()
        if not db then return yOffset end
        local entry
        yOffset, entry = BuildSelectionCard(scrollChild, yOffset, db)
        local DT_GUI = KE.GUI.DungeonTimers
        if entry and DT_GUI.BuildDungeonPage then
            yOffset = DT_GUI.BuildDungeonPage(scrollChild, yOffset, entry.key, entry.name, view)
        elseif DT_GUI.HideDungeonPreviews then
            DT_GUI.HideDungeonPreviews()
        end
        return yOffset
    end)
end

-- The bosses tab keeps its original id, which FIRST_TAB and the spell-preview
-- guard read.
RegisterDungeonView("DTimers_Dungeons", "bosses")
RegisterDungeonView("DTimers_Trash", "trash")

GUIFrame:RegisterTabbedContent("DTimers_Main", {
    { id = "DTimers_Dungeons",   label = "Dungeon Bosses" },
    { id = "DTimers_Trash",      label = "Dungeon Trash" },
    { id = "DTimers_General",    label = "General" },
    { id = "DTimers_Bars",       label = "Bars" },
    { id = "DTimers_Texts",      label = "Texts" },
    { id = "DTimers_Nameplates", label = "Nameplates" },
}, {
    headerBuilder = function(scrollChild, yOffset)
        return KE.GUI.DungeonTimers.BuildHeaderCard(scrollChild, yOffset)
    end,
})
