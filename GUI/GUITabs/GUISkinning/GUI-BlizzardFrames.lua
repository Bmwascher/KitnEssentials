-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-BlizzardFrames.lua                                  ║
-- ║  Purpose: Config page for the Blizzard frame skins.      ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme
local LSM = KE.LSM or LibStub("LibSharedMedia-3.0", true)


local ipairs = ipairs

local function GetDB()
    return KE.db and KE.db.profile.Skinning.BlizzardFrames
end

-- Key strings must match the LAST string argument of each Register /
-- RegisterEarly call under Modules/Skinning/. A mismatch silently disables
-- nothing -- the gate reads Skins[key] ~= false, so an unknown key is
-- always "on".
--
-- Two entries are not registry skins and carry their own accessors:
-- ContextMenus is an Ace module with its own Enabled flag, and GlobalFonts
-- applies and reverts live instead of on reload. An entry with `isOn` and
-- `onToggle` bypasses the db.Skins read and write entirely.
--
-- Ten keys get no row here, on purpose: AdventureMap,
-- Battlenet, ChromieTime, CooldownManager, ExtraButtons, Help, PetBattle,
-- Runeforge, TimeManager, TutorialFrame -- minor or loading-screen-rare
-- frames. A key with no row still dispatches and defaults on, because the
-- gate above reads Skins[key] ~= false -- don't "fix" this by adding rows.
local FRAME_SKINS = {
    { key = "Achievement",              text = "Achievements" },
    { key = "AddonManager",             text = "AddOn List" },
    { key = "Alerts",                   text = "Alert Popups" },
    { key = "Archaeology",              text = "Archaeology" },
    { key = "AuctionHouse",             text = "Auction House" },
    { key = "Barber",                   text = "Barbershop" },
    { key = "Binding",                  text = "Key Bindings" },
    { key = "BlackMarket",              text = "Black Market" },
    { key = "Calendar",                 text = "Calendar" },
    { key = "CatalogShop",              text = "Catalog Shop" },
    { key = "Channels",                 text = "Chat Channels" },
    { key = "Character",                text = "Character Panel" },
    { key = "ChatConfig",               text = "Chat Settings" },
    { key = "Collectables",             text = "Collections" },
    { key = "Communities",              text = "Communities & Guild" },
    { key = "ContextMenus",             text = "Context Menus",
      -- The name alone, so it fits a third-column cell at any window width.
      -- What it covers moves to the tooltip, which every other row already
      -- uses. The old spelled-out label was 45 characters and needed a
      -- full-width row of its own to avoid clipping.
      tooltip = "Skins right-click and dropdown menus.",
      isOn = function()
          local db = KE.db and KE.db.profile.Skinning.ContextMenus
          return db and db.Enabled == true or false
      end,
      onToggle = function(checked)
          local db = KE.db and KE.db.profile.Skinning.ContextMenus
          if not db then return false end
          db.Enabled = checked
          if checked then
              KitnEssentials:EnableModule("ContextMenus")
          else
              KitnEssentials:DisableModule("ContextMenus")
          end
          -- Un-skinning needs a reload; flagged one way only.
          return not checked
      end },
    { key = "Currency",                 text = "Currency" },
    { key = "DeathRecap",               text = "Death Recap" },
    { key = "Delves",                   text = "Delves" },
    { key = "Dialogs",                  text = "Dialog Borders" },
    { key = "DressingRoom",             text = "Dressing Room" },
    { key = "EditMode",                 text = "Edit Mode" },
    { key = "EncounterJournal",         text = "Adventure Guide" },
    { key = "ExpansionLandingPage",     text = "Expansion Landing Page" },
    { key = "FlightMap",                text = "Flight Map" },
    { key = "Friends",                  text = "Friends List (native)" },
    { key = "GMChat",                   text = "GM Chat" },
    { key = "GenericTrait",             text = "Generic Traits" },
    { key = "GlobalFonts",              text = "Blizzard Fonts",
      isOn = function()
          local db = GetDB()
          return not (db and db.Skins and db.Skins.GlobalFonts == false)
      end,
      onToggle = function(checked)
          local db = GetDB()
          if not db then return false end
          db.Skins = db.Skins or {}
          if checked then
              db.Skins.GlobalFonts = nil
              if KE.Skins and KE.Skins.ApplyGlobalFonts then
                  KE.Skins.ApplyGlobalFonts()
              end
          else
              db.Skins.GlobalFonts = false
              if KE.Skins and KE.Skins.RestoreGlobalFonts then
                  KE.Skins.RestoreGlobalFonts()
              end
          end
          -- No reload prompt either way. This is the one skin a user turns
          -- off because another addon looks BROKEN, so making them reload to
          -- test it is the wrong experience -- hence RestoreGlobalFonts.
          return false
      end },
    { key = "Gossip",                   text = "Gossip" },
    { key = "Guide",                    text = "New Player Guide" },
    { key = "Guild",                    text = "Guild Invite" },
    { key = "GuildBank",                text = "Guild Bank" },
    { key = "GuildControl",             text = "Guild Control" },
    { key = "GuildRegistrar",           text = "Guild Registrar" },
    { key = "Housing",                  text = "Housing" },
    { key = "Inspect",                  text = "Inspect" },
    { key = "InspectRecipe",            text = "Inspect Recipe" },
    { key = "ItemInteraction",          text = "Item Interaction" },
    { key = "ItemUpgrade",              text = "Item Upgrade" },
    { key = "LFG",                      text = "Group Finder (LFG)" },
    { key = "LFGuild",                  text = "Guild Finder" },
    { key = "Loot",                     text = "Loot Window" },
    { key = "LootToast",                text = "Loot Toasts" },
    { key = "LossControl",              text = "Loss of Control" },
    { key = "Macro",                    text = "Macros" },
    { key = "Mail",                     text = "Mail" },
    { key = "MajorFaction",             text = "Renown" },
    { key = "Merchant",                 text = "Merchant" },
    { key = "MirrorTimers",             text = "Mirror Timers" },
    { key = "Misc",                     text = "Misc Dialogs" },
    { key = "NonRaid",                  text = "Raid Info (Lockouts)" },
    { key = "PerksProgram",             text = "Trading Post" },
    { key = "Petition",                 text = "Petitions" },
    { key = "PlayerChoice",             text = "Player Choice" },
    { key = "PlayerSpells",             text = "Talents & Spellbook" },
    { key = "Professions",              text = "Professions" },
    { key = "ProfessionsOrders",        text = "Crafting Orders" },
    { key = "PvP",                      text = "PvP" },
    { key = "PvPMatch",                 text = "PvP Match" },
    { key = "Quest",                    text = "Quests" },
    { key = "QuestChoice",              text = "Quest Choice" },
    { key = "Raid",                     text = "Raid (Legacy)" },
    { key = "Reputation",               text = "Reputation" },
    { key = "SettingsPanel",            text = "Settings Panel" },
    { key = "Socket",                   text = "Item Socketing" },
    { key = "SpellBook",                text = "Professions Book" },
    { key = "Stable",                   text = "Stable" },
    { key = "SubscriptionInterstitial", text = "Subscription Popup" },
    { key = "Tabard",                   text = "Tabard Designer" },
    { key = "TalkingHead",              text = "Talking Head" },
    { key = "Taxi",                     text = "Flight Master" },
    { key = "Trade",                    text = "Trade" },
    { key = "Trainer",                  text = "Trainer" },
    { key = "Transmog",                 text = "Transmogrify" },
    { key = "WeeklyRewards",            text = "Great Vault" },
    { key = "WorldMap",                 text = "World Map" },
}

-- Skins for other addons. Each runs only when its addon is installed.
-- An entry with an `addon` field greys out when that addon is missing.
-- Ace3 carries none -- it is a library skin covering any AceGUI window,
-- not one addon's, which is why its file lives under Frames/ while its
-- row lives here. Presentation only: the skins never run for a missing
-- addon anyway, because S:Register dispatch is keyed to ADDON_LOADED.
local ADDON_SKINS = {
    { key = "Ace3",               text = "Addon Config Windows (AceGUI)",
      -- Alone on a full-width row above the grid. Its label is the longest
      -- here, and it is the only row that is not one named addon -- it covers
      -- any AceGUI window -- so standing apart matches what it is.
      soloRow = true },
    { key = "Baganator",          text = "Baganator",            addon = "Baganator" },
    { key = "BetterFriendlist",   text = "Better Friendlist",    addon = "BetterFriendlist" },
    { key = "BigWigs",            text = "BigWigs",              addon = "BigWigs" },
    { key = "BugSack",            text = "BugSack",              addon = "BugSack" },
    { key = "MythicDungeonTools", text = "Mythic Dungeon Tools", addon = "MythicDungeonTools" },
    { key = "SimpleAddonManager", text = "Simple Addon Manager", addon = "SimpleAddonManager" },
    { key = "Simulationcraft",    text = "SimulationCraft",      addon = "Simulationcraft" },
    { key = "TalentLoadoutsEx",   text = "Talent Loadouts Ex",   addon = "TalentLoadoutsEx" },
}

-- One read path for every row, so a special entry cannot render the wrong
-- state. Without this the ContextMenus row reads db.Skins.ContextMenus --
-- a key nothing ever writes -- and renders ON while the module is OFF.
local function EntryIsOn(entry, skins)
    if entry.isOn then return entry.isOn() end
    return skins[entry.key] ~= false
end

-- One write path, for the same reason. Returns true when a reload prompt
-- is owed, so the caller can raise exactly one for a bulk toggle.
local function SetEntry(entry, skins, checked)
    if entry.onToggle then return entry.onToggle(checked) end
    if checked then skins[entry.key] = nil else skins[entry.key] = false end
    return true
end

-- Frame Skins takes three columns; Addon Skins takes two. Their labels are
-- longer ("Mythic Dungeon Tools (not installed)" is 36 characters against the
-- roughly 29 a third of the content width holds) and the list is only nine
-- rows, so squeezing it costs readability and buys nothing.
local FRAME_PER_ROW = 3
local ADDON_PER_ROW = 2
local CELL_H = 24
local CELL_SPACING = 2

-- Sorted by the name the USER reads, not by the internal key. Sorting by key put
-- Key Bindings between Barbershop and Black Market, and Blizzard Fonts under G.
-- Done once at file scope, not per build. Display names are unique across both
-- tables, so table.sort's instability in 5.1 cannot reorder equal keys.
local function SortByText(list)
    table.sort(list, function(a, b) return a.text < b.text end)
end
SortByText(FRAME_SKINS)
SortByText(ADDON_SKINS)

-- An ADDON_SKINS row for an addon the user does not have is shown greyed
-- rather than hidden, so the list reads the same on every machine and a
-- user can see what installing that addon would get them. FRAME_SKINS
-- rows have no `addon` field and are never greyed by this.
local function AddonInstalled(entry)
    if not entry.addon then return true end
    if not (C_AddOns and C_AddOns.DoesAddOnExist) then return true end
    return C_AddOns.DoesAddOnExist(entry.addon)
end

-- True when at least one row in `entries` is covered by EllesmereUI. Keyed on the
-- rows themselves rather than on whether EllesmereUI is loaded, so the note
-- appears exactly when there is a mark on screen to explain -- and never on
-- Addon Skins, whose keys are not in the EllesmereUI map.
local function AnySuppressed(entries)
    if not (KE.Skins and KE.Skins.GetSuppressionState) then return false end
    for _, entry in ipairs(entries) do
        local state = KE.Skins.GetSuppressionState(entry.key)
        if state == "full" or state == "partial" then return true end
    end
    return false
end

-- Renders `entries` as a PER_ROW-wide grid of checkboxes. One column would
-- be unusable at 91 rows.
--
-- S.GetSuppressionState answers one of three states per key:
--   "full"    -- EllesmereUI covers every registration behind this key. The
--               row is greyed and made unclickable rather than hidden: the
--               user chose to turn it on, and silently dropping it from the
--               list reads as a missing feature. Their saved choice is left
--               untouched, so it comes back by itself if EllesmereUI stops
--               covering the window.
--   "partial" -- EllesmereUI covers SOME of the registrations behind this
--               key and not others. The toggle still genuinely controls the
--               registrations EllesmereUI does not touch, so the row stays
--               full opacity and clickable -- greying it would take away the
--               off-switch for the working skins to describe one overlap.
--               It is marked with a trailing " *", and the map row's own
--               description of what is and is not covered becomes its tooltip.
--               The description is NOT used as the label: it runs to 37
--               characters and cannot fit a three-column cell.
--   "none"    -- unchanged: falls through to the not-installed check below.
-- An uninstalled addon row is greyed the same way as "full", but "full" wins
-- when a row is both suppressed and not-installed -- a row can only show one
-- reason at a time, and suppression is the one the user can act on today.
-- Not-installed is checked before "partial": a row whose addon is missing has
-- nothing to skin at all, so "(not installed)" is the more useful message and
-- wins over a partial-coverage note. "partial" cannot also be not-installed
-- today -- FRAME_SKINS rows carry no `addon` field, so AddonInstalled always
-- returns true for them -- but the branch order below is written explicitly
-- rather than relying on that.
-- Resolves one row's rendering: what it says, whether it tips, whether it is
-- greyed. Shared by the grid and the solo rows so the two cannot drift.
local function ResolveRow(entry)
    local state = "none"
    local partialTooltip
    if KE.Skins and KE.Skins.GetSuppressionState then
        local _
        state, _, _, partialTooltip = KE.Skins.GetSuppressionState(entry.key)
    end
    local label = entry.text
    -- An entry may carry its own explanation of what it skins. Every branch
    -- below replaces it, because EllesmereUI coverage or a missing addon says
    -- something about whether the row works at all, which outranks what it
    -- does. Note "partial" replaces the tooltip WITHOUT disabling the row --
    -- that one is a caveat, not a refusal.
    local tooltip = entry.tooltip
    local disabled = false
    if state == "full" then
        -- No text marker. At three columns a suffix pushes long names past the
        -- cell, and the two partial rows' custom labels run to 37 characters and
        -- clip in every case. The greying plus the note line above the grid
        -- carry the meaning instead.
        tooltip = "EllesmereUI already skins this window, so KitnEssentials leaves it alone. Turn EllesmereUI's window skin off to use this one."
        disabled = true
    elseif not AddonInstalled(entry) then
        -- Addon Skins keeps its per-row text: that list is two columns wide, at
        -- most nine rows, and WHICH addons are missing differs per machine, so a
        -- shared note line could not say which rows it meant.
        label = label .. " |cff888888(not installed)|r"
        tooltip = "This addon is not installed, so there is nothing to skin. The setting is kept and applies by itself once you install it."
        disabled = true
    elseif state == "partial" then
        -- A partial row must NOT be greyed: the toggle still controls the
        -- registrations EllesmereUI does not cover, and greying would take away
        -- a working off-switch to describe an overlap. It gets an asterisk
        -- instead, explained by the same note line.
        label = label .. " *"
        tooltip = partialTooltip or "EllesmereUI covers part of this window group. This toggle still controls the rest."
    end
    return label, tooltip, disabled
end

local function MakeCheck(parent, entry, skins)
    local label, tooltip, disabled = ResolveRow(entry)
    return GUIFrame:CreateCompactCheckbox(parent, label, {
        value = EntryIsOn(entry, skins),
        tooltip = tooltip,
        disabled = disabled,
        callback = function(checked)
            if SetEntry(entry, skins, checked) then
                KE:FlagReloadNeeded()
            end
            GUIFrame:RefreshContent()
        end,
    })
end

-- Entries flagged soloRow render one per full-width row, above the grid. They
-- stay MEMBERS of their list: dropping one from the table would take it out of
-- the header's any-on read and the bulk toggle too, so the master switch would
-- silently skip a control.
local function BuildSoloRows(card, entries, skins)
    for _, entry in ipairs(entries) do
        if entry.soloRow then
            local row = GUIFrame:CreateRow(card.content, CELL_H)
            row:AddWidget(MakeCheck(row, entry, skins), 1)
            card:AddRow(row, CELL_H, CELL_SPACING)
        end
    end
end

-- The grid gets a FILTERED copy, so a solo entry costs no cell. Striding over
-- it in place would leave a hole mid-grid and push the tail out of step.
local function GridEntries(entries)
    local out = {}
    for _, entry in ipairs(entries) do
        if not entry.soloRow then out[#out + 1] = entry end
    end
    return out
end

local function BuildCheckGrid(card, entries, skins, perRow)
    local grid = GridEntries(entries)
    local i = 1
    while i <= #grid do
        local isLastRow = (i + perRow) > #grid
        local row = GUIFrame:CreateRow(card.content, CELL_H)
        for c = 0, perRow - 1 do
            local entry = grid[i + c]
            if entry then
                row:AddWidget(MakeCheck(row, entry, skins), 1 / perRow)
            end
        end
        if isLastRow then
            card:AddRow(row, CELL_H, 0)
        else
            card:AddRow(row, CELL_H, CELL_SPACING)
        end
        i = i + perRow
    end
end

-- This tab is offered in every state, including the two where the skin engine
-- is not running, because Color Picker and Raid Control ride on it and neither
-- is a skin.
--
-- Note there is no early return on a missing db. Color Picker and Raid Control
-- read their own db and must still render when this page's is absent.
GUIFrame:RegisterContent("SkinBlizzardFramesGeneral", function(scrollChild, yOffset)
    -- Chained, not re-registered: each builder takes (scrollChild, yOffset) and
    -- returns the next offset, which is the same contract RegisterTabbedContent
    -- uses. Resolved live so GUI.xml load order does not matter.
    --
    -- Window Colors leads rather than owning a tab of its own -- two pickers and
    -- a reset never filled one. Gated on the ElvUI check the tab strip used to
    -- apply for it: the windows it colours are not drawn while ElvUI has the
    -- skinning.
    if not (KE.ShouldNotLoadModule and KE:ShouldNotLoadModule()) then
        local colors = GUIFrame.registeredContent and GUIFrame.registeredContent["SkinBlizzardFramesColors"]
        if colors then yOffset = colors(scrollChild, yOffset) end
    end

    local colorPicker = GUIFrame.registeredContent and GUIFrame.registeredContent["ColorPicker"]
    if colorPicker then yOffset = colorPicker(scrollChild, yOffset) end

    local raidControl = GUIFrame.registeredContent and GUIFrame.registeredContent["RaidControl"]
    if raidControl then yOffset = raidControl(scrollChild, yOffset) end

    return yOffset
end)

GUIFrame:RegisterContent("SkinBlizzardFramesFrames", function(scrollChild, yOffset)
    local db = GetDB()
    if not db then return yOffset end
    db.Skins = db.Skins or {}
    local card = GUIFrame:CreateCard(scrollChild, "Frame Skins", yOffset)

    -- Keyed on ANY-on, not all-on. With all-on semantics, unticking a single
    -- frame reads as master-off and collapses the card, hiding the user's
    -- own choices while the remaining skins keep applying.
    local anyOn = false
    for _, entry in ipairs(FRAME_SKINS) do
        -- Counts only what this toggle can actually write. The bulk loop
        -- below skips a fully suppressed entry, so counting one here would
        -- make the header re-read as on the moment RefreshContent re-runs.
        -- A partial entry IS writable -- EllesmereUI only owns part of it --
        -- so it counts here the same as an unsuppressed row.
        local state = "none"
        if KE.Skins and KE.Skins.GetSuppressionState then
            state = KE.Skins.GetSuppressionState(entry.key)
        end
        if state ~= "full" and EntryIsOn(entry, db.Skins) then anyOn = true break end
    end

    card:AddHeaderToggle(anyOn, function(checked)
        local needsReload = false
        for _, entry in ipairs(FRAME_SKINS) do
            -- A fully suppressed row cannot be clicked individually, so a
            -- bulk toggle must not write it either -- that is what keeps the
            -- user's real choice intact until EllesmereUI stops covering
            -- the window. A partial row IS writable -- the toggle still
            -- controls the registrations EllesmereUI does not cover -- so
            -- it is written the same as an unsuppressed row.
            local state = "none"
            if KE.Skins and KE.Skins.GetSuppressionState then
                state = KE.Skins.GetSuppressionState(entry.key)
            end
            if state ~= "full" and SetEntry(entry, db.Skins, checked) then
                needsReload = true
            end
        end
        -- One prompt for the whole batch, not one per entry.
        if needsReload then KE:FlagReloadNeeded() end
    end)

    if AnySuppressed(FRAME_SKINS) then
        card:AddNote("Greyed windows are already skinned by EllesmereUI. Windows marked with * are partly covered, and their toggle still controls the rest. Hover either for detail.")
    end

    -- No solo rows in this list today -- Context Menus was one until its label
    -- was shortened to fit an ordinary cell. Called anyway so adding a flag to
    -- an entry is all it ever takes.
    BuildSoloRows(card, FRAME_SKINS, db.Skins)
    BuildCheckGrid(card, FRAME_SKINS, db.Skins, FRAME_PER_ROW)

    return card:GetNextOffset()
end)

GUIFrame:RegisterContent("SkinBlizzardFramesAddons", function(scrollChild, yOffset)
    local db = GetDB()
    if not db then return yOffset end
    db.Skins = db.Skins or {}
    local card = GUIFrame:CreateCard(scrollChild, "Addon Skins", yOffset)

    if #ADDON_SKINS == 0 then
        card:AddNote("No addon skins are available yet.")
        return card:GetNextOffset()
    end

    -- Counts only what this toggle can actually write. The bulk loop below
    -- skips uninstalled entries, so counting them here would make the
    -- header re-read as on the moment RefreshContent re-runs.
    local anyOn = false
    for _, entry in ipairs(ADDON_SKINS) do
        if AddonInstalled(entry) and EntryIsOn(entry, db.Skins) then anyOn = true break end
    end

    card:AddHeaderToggle(anyOn, function(checked)
        local needsReload = false
        for _, entry in ipairs(ADDON_SKINS) do
            -- An uninstalled row cannot be clicked individually, so a bulk
            -- toggle must not write it either -- that is what keeps the
            -- setting intact until the user installs the addon.
            if AddonInstalled(entry) and SetEntry(entry, db.Skins, checked) then
                needsReload = true
            end
        end
        if needsReload then KE:FlagReloadNeeded() end
    end)

    card:AddNote("Skins for other addons, applied when that addon loads. Changes apply after a /reload.")
    BuildSoloRows(card, ADDON_SKINS, db.Skins)
    BuildCheckGrid(card, ADDON_SKINS, db.Skins, ADDON_PER_ROW)
    return card:GetNextOffset()
end)

-- The Frame Skins tab: both skin lists, one under the other. Addon Skins had a
-- tab of its own and did not need one -- the two gate identically, since both
-- configure the skin engine, so a state that hid one always hid the other.
GUIFrame:RegisterContent("SkinBlizzardFramesSkins", function(scrollChild, yOffset)
    for _, id in ipairs({ "SkinBlizzardFramesFrames", "SkinBlizzardFramesAddons" }) do
        local builder = GUIFrame.registeredContent and GUIFrame.registeredContent[id]
        if builder then yOffset = builder(scrollChild, yOffset) end
    end
    return yOffset
end)

GUIFrame:RegisterContent("SkinBlizzardFramesFonts", function(scrollChild, yOffset)
    local db = GetDB()
    if not db then return yOffset end
    local S = KE.Skins

    local card = GUIFrame:CreateCard(scrollChild, "Skin Font", yOffset)
    card:AddNote("Controls text inside windows KitnEssentials skins. Elements with a deliberately larger size, such as window titles and big counters, keep the gap between them and move together.")

    local fontOptions = {}
    if LSM then
        for name in pairs(LSM:HashTable("font")) do fontOptions[name] = name end
    end

    local rowFace = GUIFrame:CreateRow(card.content, Theme.rowHeight)
    rowFace:AddWidget(GUIFrame:CreateDropdown(rowFace, "Font", {
        options = KE:AddFollowGlobalFont(fontOptions),
        value = db.FontFace or KE.FONT_FOLLOW_GLOBAL,
        searchable = true,
        isFontPreview = true,
        callback = function(key)
            db.FontFace = KE:StoredFontFace(key)
            -- SetSkinFont reads nil as "leave the face alone", so the resolved
            -- name goes across the wire rather than the unset marker.
            if S and S.SetSkinFont then
                S.SetSkinFont(db.FontFace or KE:GetGlobalFont(), nil, nil)
            end
        end,
    }), 0.5)

    -- Hand-rolled rather than taken from KE:GetFontOutlineOptions, because the
    -- skin engine supports exactly these three modes. Note the token is THICK,
    -- not the THICKOUTLINE spelling the rest of the addon uses for a raw font
    -- flag: this key is a mode the engine resolves, not a flag it forwards.
    rowFace:AddWidget(GUIFrame:CreateDropdown(rowFace, "Outline", {
        options = { NONE = "None", OUTLINE = "Outline", THICK = "Thick" },
        value = (S and S._ResolveOutlineMode and S._ResolveOutlineMode(db.FontOutline)) or "NONE",
        callback = function(key)
            db.FontOutline = key
            if S and S.SetSkinFont then S.SetSkinFont(nil, nil, key) end
        end,
    }), 0.5)
    card:AddRow(rowFace, Theme.rowHeight)

    -- One size control, not two. A separate nudge slider did the same
    -- arithmetic in a different unit, so its range is folded into this one
    -- instead. FontOffset is still read and still applied, which is what keeps
    -- an existing saved look unchanged -- it just has no control any more.
    local rowSize = GUIFrame:CreateRow(card.content, Theme.rowHeightLast)
    rowSize:AddWidget(GUIFrame:CreateSlider(rowSize, "Base Font Size", {
        min = 8, max = 26, step = 1, value = db.FontSize or 12,
        tooltip = "Size of text in skinned windows. Larger elements keep their extra size and move with it. 12 is the designed look.",
        callback = function(val)
            db.FontSize = val
            if S and S.SetSkinFont then S.SetSkinFont(nil, val, nil) end
        end,
    }), 1)
    card:AddRow(rowSize, Theme.rowHeightLast, 0)

    yOffset = card:GetNextOffset()

    -- Same subject, wider scope: the game-wide text settings, chained as-is so
    -- this page stays the one place fonts are configured.
    local messages = GUIFrame.registeredContent and GUIFrame.registeredContent["SkinMessages"]
    if messages then yOffset = messages(scrollChild, yOffset) end

    return yOffset
end)

GUIFrame:RegisterContent("SkinBlizzardFramesColors", function(scrollChild, yOffset)
    local db = GetDB()
    if not db then return yOffset end
    local S = KE.Skins

    db.BackdropColor = db.BackdropColor or { 0.031, 0.031, 0.031, 0.80 }
    db.BorderColor = db.BorderColor or { 0, 0, 0, 1 }

    local card = GUIFrame:CreateCard(scrollChild, "Window Colors", yOffset)
    card:AddNote("Both pickers repaint every skinned window that is already open. Frames that carry a colour of their own, such as controls and panels, keep it.")

    local row = GUIFrame:CreateRow(card.content, Theme.rowHeight)
    row:AddWidget(GUIFrame:CreateColorPicker(row, "Background Color", {
        color = db.BackdropColor,
        callback = function(r, g, b, a)
            db.BackdropColor = { r, g, b, a }
            if S and S.SetSkinColors then S.SetSkinColors(db.BackdropColor, nil) end
        end,
    }), 0.5)
    row:AddWidget(GUIFrame:CreateColorPicker(row, "Border Color", {
        color = db.BorderColor,
        callback = function(r, g, b, a)
            db.BorderColor = { r, g, b, a }
            if S and S.SetSkinColors then S.SetSkinColors(nil, db.BorderColor) end
        end,
    }), 0.5)
    card:AddRow(row, Theme.rowHeight)

    local rowR = GUIFrame:CreateRow(card.content, Theme.rowHeightLast)
    rowR:AddWidget(GUIFrame:CreateButton(rowR, "Reset to Default", {
        width = 150,
        tooltip = "Restore the designed window colours.",
        callback = function()
            if not (S and S.SetSkinColors) then return end
            db.BackdropColor = { unpack(S.DEFAULT_BG) }
            db.BorderColor = { unpack(S.DEFAULT_BORDER) }
            S.SetSkinColors(db.BackdropColor, db.BorderColor)
            GUIFrame:RefreshContent()
        end,
    }), 0.35)
    card:AddRow(rowR, Theme.rowHeightLast, 0)

    return card:GetNextOffset()
end)

-- The single-element pages behind one sub-row. Each was a top-level tab,
-- which made the strip long enough to bury the settings people look for.
--
-- This row keeps its own active id. GUIFrame.tabbedPageState is keyed by PAGE,
-- and this row is not a page.
local elementTabs = {
    { id = "SkinBlizzardFramesLootRoll",   label = "Loot Roll" },
    { id = "SkinBlizzardFramesLootWindow", label = "Loot Window" },
    { id = "SkinBlizzardFramesWidgets",    label = "UI Widgets" },
    { id = "VehicleExit",                  label = "Vehicle Exit" },
}
local activeElement = elementTabs[1].id

-- Edit Mode's Open Settings hands over one of these nested ids. The page-level
-- resolver cannot see them, so it needs to know which outer tab owns them.
GUIFrame:RegisterNestedTabs("SkinBlizzardFramesElements", {
    "SkinBlizzardFramesLootRoll",
    "SkinBlizzardFramesLootWindow",
    "SkinBlizzardFramesWidgets",
    "VehicleExit",
})

-- No conflict branch here. Every tab on this row configures a module that
-- stands down under ElvUI, so the whole Elements tab drops out of the strip
-- rather than this row filtering itself.
local function VisibleElementTabs()
    return elementTabs
end
GUIFrame._VisibleElementTabs = VisibleElementTabs

GUIFrame:RegisterContent("SkinBlizzardFramesElements", function(scrollChild, yOffset)
    local tabs = VisibleElementTabs()

    -- Consumed once: re-reading it on every rebuild would drag the user back
    -- here every time the page redraws after they clicked a different sub-tab.
    local pending = GUIFrame.pendingNestedTab["SkinBlizzardFramesElements"]
    if pending then
        activeElement = pending
        GUIFrame.pendingNestedTab["SkinBlizzardFramesElements"] = nil
    end

    local found = false
    for _, tab in ipairs(tabs) do
        if tab.id == activeElement then found = true break end
    end
    if not found then activeElement = tabs[1].id end

    local _, tabOffset = GUIFrame:CreateSubTabs(scrollChild, yOffset, {
        tabs = tabs,
        activeId = activeElement,
        onSwitch = function(newId) activeElement = newId end,
        fill = true,
    })
    yOffset = tabOffset

    local builder = GUIFrame.registeredContent and GUIFrame.registeredContent[activeElement]
    if builder then yOffset = builder(scrollChild, yOffset) end
    return yOffset
end)

-- Three states, evaluated per build, so the master toggle's own RefreshContent
-- switches between them with no reload.
--
-- Exactly TWO of these six configure the skin engine itself -- Frame Skins and
-- Addon Skins -- so they drop out while it is off, because showing them there
-- renders live-looking controls that do nothing.
--
-- Fonts is independent of the engine but still describes a skinned look, so it
-- drops with the engine's own tab. General's Window Colors card is the same
-- case and drops on the same test, gated inside that builder rather than here.
--
-- General is the only tab that stays in every state. It carries Raid Control
-- and the three group-finder pages, none of which is a skin, which is why it
-- does not sit in the two groups above. Elements is engine-independent but not
-- ElvUI-independent: every page on it stands down under ElvUI, so it survives
-- the engine flag and not the conflict state.
--
-- ElvUI is a stricter cut than the engine flag, not a wider one: it drops Fonts
-- and Window Colors too, alongside the skin lists, leaving only General.
-- Color Picker also rides on General but DOES stand down under ElvUI, by its
-- own conflict list rather than the skin gate; its card already says so, which
-- is why it does not change what this list offers.
GUIFrame:RegisterTabbedContent("SkinBlizzardFrames", function()
    local db = GetDB()

    -- Window Colors and Addon Skins have no tab of their own: the first leads
    -- the General page, the second follows Frame Skins on its page. Their
    -- builders are still registered and are chained from there.
    local GENERAL  = { id = "SkinBlizzardFramesGeneral",  label = "General" }
    local FONTS    = { id = "SkinBlizzardFramesFonts",    label = "Fonts" }
    local FRAMES   = { id = "SkinBlizzardFramesSkins",    label = "Frame Skins" }
    local ELEMENTS = { id = "SkinBlizzardFramesElements", label = "Elements" }

    -- In the conflict state only General survives: it carries Raid Control and
    -- the group-finder pages, which are not skins. Fonts drops with the skins,
    -- because the text it styles is not drawn here -- and General's own Window
    -- Colors card drops with it, gated inside that builder.
    if KE.ShouldNotLoadModule and KE:ShouldNotLoadModule() then
        return { GENERAL }
    end

    -- Frame Skins is the only tab that configures the engine itself, so it is
    -- the only one that drops while it is off. Addon Skins rides on it.
    if not db or db.Enabled ~= true then
        return { GENERAL, FONTS, ELEMENTS }
    end

    return { GENERAL, FONTS, FRAMES, ELEMENTS }
end, {
    headerBuilder = function(scrollChild, yOffset)
        local db = GetDB()
        -- No header card without a db -- but do NOT collapse. Collapsing here
        -- returns before the tab strip is built, which would take Character
        -- Screen, Color Picker and Raid Control down
        -- with a table this page alone owns. That is the same reachability rule
        -- the tab list keeps; this is the one path that could still break it.
        if not db then return yOffset, false end
        local card = GUIFrame:CreateCard(scrollChild, "Dark Theme", yOffset)
        card:AddHeaderToggle(db.Enabled == true, function(checked)
            db.Enabled = checked
            KE:FlagReloadNeeded()
            -- AddHeaderToggle's own OnClick already calls RefreshContent.
        end)
        -- Say WHY the engine's own tabs are absent. Hiding them is right --
        -- greyed controls read as "locked on" rather than "does not apply" (the
        -- A6.3b Move Loot Rolls ruling) -- but hiding alone leaves a user unable
        -- to tell those settings exist at all. AddLabel bumps the card off its
        -- lone-header-bar height, which is the intended look here.
        --
        -- The toggle above stays live under ElvUI on purpose: the setting is
        -- kept and applies again if ElvUI is turned off, which is what the label
        -- says. The label claims nothing about the remaining tabs -- Color
        -- Picker stands down under ElvUI too and says so on its own card, so a
        -- blanket "ElvUI does not touch these" here would be false.
        if KE.ShouldNotLoadModule and KE:ShouldNotLoadModule() then
            card:AddNote("|cffffd100ElvUI is handling Blizzard frame skinning.|r KitnEssentials stands down so the two do not fight over the same windows, so the frame and addon skins are not applied right now. Your settings are kept and take effect again if you turn ElvUI off.")
        elseif db.Enabled ~= true then
            card:AddNote("Turn this on to configure frame and addon skins. The tabs below belong to modules that work with it off.")
        end
        local newOffset = yOffset + card:GetContentHeight() + Theme.paddingSmall
        -- Never collapse: the tab list above already drops the engine's own
        -- tabs when it is off, and collapsing as well would take the three
        -- independent modules' settings with it.
        return newOffset, false
    end,
})
