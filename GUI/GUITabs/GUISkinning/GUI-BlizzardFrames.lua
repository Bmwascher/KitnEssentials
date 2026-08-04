-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-BlizzardFrames.lua                                  ║
-- ║  Purpose: Config page for the Blizzard frame skins.      ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

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
-- Ten keys ported alongside these get no row here, on purpose: AdventureMap,
-- Battlenet, ChromieTime, CooldownManager, ExtraButtons, Help, PetBattle,
-- Runeforge, TimeManager, TutorialFrame -- minor or loading-screen-rare
-- frames (reference rationale: GUI/Tabs/Skinning/GUI-BlizzardFrames.lua:
-- 118-124). A key with no row still dispatches and defaults on, because the
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
    { key = "ContextMenus",             text = "Context Menus (right-click and dropdown menus)",
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
          -- Un-skinning needs a reload; the reference flags it one way only.
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
    { key = "Ace3",               text = "Addon Config Windows (AceGUI)" },
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

local PER_ROW = 2
local CELL_H = 40

-- An ADDON_SKINS row for an addon the user does not have is shown greyed
-- rather than hidden, so the list reads the same on every machine and a
-- user can see what installing that addon would get them. FRAME_SKINS
-- rows have no `addon` field and are never greyed by this.
local function AddonInstalled(entry)
    if not entry.addon then return true end
    if not (C_AddOns and C_AddOns.DoesAddOnExist) then return true end
    return C_AddOns.DoesAddOnExist(entry.addon)
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
--               It is relabelled with the map row's own description of what
--               is and is not covered, verbatim.
--   "none"    -- unchanged: falls through to the not-installed check below.
-- An uninstalled addon row is greyed the same way as "full", but "full" wins
-- when a row is both suppressed and not-installed -- a row can only show one
-- reason at a time, and suppression is the one the user can act on today.
-- Not-installed is checked before "partial": a row whose addon is missing has
-- nothing to skin at all, so "(not installed)" is the more useful message and
-- wins over a partial-coverage note. "partial" cannot also be not-installed
-- today -- FRAME_SKINS rows carry no `addon` field, so AddonInstalled always
-- returns true for them (:158-162) -- but the branch order below is written
-- explicitly rather than relying on that.
local function BuildCheckGrid(card, entries, skins)
    local i = 1
    while i <= #entries do
        local isLastRow = (i + PER_ROW) > #entries
        local row = GUIFrame:CreateRow(card.content, CELL_H)
        for c = 0, PER_ROW - 1 do
            local entry = entries[i + c]
            if entry then
                local state = "none"
                local partialLabel, partialTooltip
                if KE.Skins and KE.Skins.GetSuppressionState then
                    local _
                    state, _, partialLabel, partialTooltip = KE.Skins.GetSuppressionState(entry.key)
                end
                local label = entry.text
                local tooltip
                local disabled = false
                if state == "full" then
                    label = label .. " |cff888888(EllesmereUI)|r"
                    tooltip = "EllesmereUI already skins this window, so KitnEssentials leaves it alone. Turn EllesmereUI's window skin off to use this one."
                    disabled = true
                elseif not AddonInstalled(entry) then
                    label = label .. " |cff888888(not installed)|r"
                    tooltip = "This addon is not installed, so there is nothing to skin. The setting is kept and applies by itself once you install it."
                    disabled = true
                elseif state == "partial" then
                    label = partialLabel or (label .. " |cff888888(EllesmereUI)|r")
                    tooltip = partialTooltip or "EllesmereUI covers part of this window group. This toggle still controls the rest."
                end
                local check = GUIFrame:CreateCheckbox(row, label, {
                    value = EntryIsOn(entry, skins),
                    tooltip = tooltip,
                    callback = function(checked)
                        if SetEntry(entry, skins, checked) then
                            KE:SkinningReloadPrompt()
                        end
                        GUIFrame:RefreshContent()
                    end,
                })
                if disabled then
                    -- SetEnabled, not EnableMouse. CreateCheckbox returns the
                    -- ROW; the clickable object is a child button, and
                    -- row:SetEnabled is what reaches it
                    -- (GUI/GUIWidgets/GUI-KEToggle.lua:301-311). EnableMouse on
                    -- the row leaves the button live and the row still clicks.
                    check:SetEnabled(false)
                end
                row:AddWidget(check, 1 / PER_ROW)
            end
        end
        if isLastRow then
            card:AddRow(row, CELL_H, 0)
        else
            card:AddRow(row, CELL_H)
        end
        i = i + PER_ROW
    end
end

GUIFrame:RegisterContent("SkinBlizzardFramesGeneral", function(scrollChild, yOffset)
    local db = GetDB()
    if not db then return yOffset end
    local card = GUIFrame:CreateCard(scrollChild, "Global Font Adjust", yOffset)

    local row = GUIFrame:CreateRow(card.content, Theme.rowHeightLast)
    local slider = GUIFrame:CreateSlider(row, "Font Size Adjust", {
        min = -4, max = 6, step = 1, value = db.FontOffset or 0,
        tooltip = "Grows or shrinks every font inside skinned windows together. 0 is the designed look.",
        callback = function(val)
            db.FontOffset = val
            if KE.Skins and KE.Skins.SetFontOffset then KE.Skins.SetFontOffset(val) end
        end,
    })
    row:AddWidget(slider, 1)
    card:AddRow(row, Theme.rowHeightLast)

    local rowB = GUIFrame:CreateRow(card.content, Theme.rowHeightLast)
    local baseSlider = GUIFrame:CreateSlider(rowB, "Blizzard Font Base Size", {
        min = 8, max = 18, step = 1, value = db.FontBaseSize or 12,
        tooltip = "Base size the Blizzard font override scales from. Every font keeps its relative size; this moves them together. 12 is Blizzard's own baseline.",
        callback = function(val)
            db.FontBaseSize = val
            if KE.Skins and KE.Skins.ApplyGlobalFonts then
                KE.Skins.ApplyGlobalFonts()
            end
            -- The BlizzardFonts sweep scales every UNOVERRIDDEN font object off
            -- this same base, so it has to re-run or the two systems drift
            -- apart. Objects with a per-category size in db.Sizes skip the
            -- scaling entirely (<REF>/Skinning/BlizzardFonts.lua:223-228).
            local bf = KitnEssentials:GetModule("BlizzardFonts", true)
            local fdb = KE.db and KE.db.profile.Skinning.BlizzardFonts
            if bf and fdb and fdb.Enabled and bf.ApplyAll then bf:ApplyAll() end
        end,
    })
    rowB:AddWidget(baseSlider, 1)
    card:AddRow(rowB, Theme.rowHeightLast)

    local rowC = GUIFrame:CreateRow(card.content, Theme.rowHeightLast)
    local outlineCheck = GUIFrame:CreateCheckbox(rowC, "Text Outline", {
        value = db.FontOutline and true or false,
        tooltip = "Draws a black outline around text inside skinned windows. Off is thinner and easier to read in dense lists such as the guild roster; on is the designed look.",
        callback = function(checked)
            db.FontOutline = checked and true or false
            if KE.Skins and KE.Skins.SetFontOutline then
                KE.Skins.SetFontOutline(db.FontOutline)
            end
        end,
    })
    rowC:AddWidget(outlineCheck, 1)
    card:AddRow(rowC, Theme.rowHeightLast, 0)

    return card:GetNextOffset()
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
        if needsReload then KE:SkinningReloadPrompt() end
    end)

    BuildCheckGrid(card, FRAME_SKINS, db.Skins)

    return card:GetNextOffset()
end)

GUIFrame:RegisterContent("SkinBlizzardFramesAddons", function(scrollChild, yOffset)
    local db = GetDB()
    if not db then return yOffset end
    db.Skins = db.Skins or {}
    local card = GUIFrame:CreateCard(scrollChild, "Addon Skins", yOffset)

    if #ADDON_SKINS == 0 then
        card:AddLabel("No addon skins are available yet.")
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
        if needsReload then KE:SkinningReloadPrompt() end
    end)

    card:AddLabel("Skins for other addons, applied when that addon loads. Changes apply after a /reload.")
    BuildCheckGrid(card, ADDON_SKINS, db.Skins)
    return card:GetNextOffset()
end)

-- Three states, evaluated per build, so the master toggle's own RefreshContent
-- switches between them with no reload.
--
-- Exactly TWO of these eight configure the skin engine itself -- Frame Skins and
-- Addon Skins -- so they drop out while it is off, because showing them there
-- renders live-looking controls that do nothing.
--
-- Five of the remaining six are INDEPENDENT of the engine and ship enabled: Loot
-- Roll, Loot Window, UI Widgets (which also hosts Alert Frames' controls),
-- Character Screen, and Blizzard Texts. They must stay reachable while the
-- engine is off -- there is no other route to them, not the sidebar, not the
-- keyword search, not an Edit Mode Open Settings button, all of which land here.
--
-- General is the sixth and is the hybrid, which is why it is not in either
-- group. It is offered in EVERY state because Color Picker and Raid Control ride
-- on it; the engine-specific part of it, the font card, is what turns off
-- instead. That is a change from the old rule, which dropped General entirely.
--
-- ElvUI is a stricter cut than the engine flag, not a wider one. Loot Roll,
-- Loot Window, UI Widgets and Blizzard Texts all stand down under ElvUI
-- (Modules/Skinning/LootRoll.lua:558, LootFrame.lua:379, UIWidgets.lua:46,
-- BlizzardMessages.lua:181), so they drop out too. General and Character Screen
-- survive because Raid Control (no ElvUI gate at all) rides on General, and
-- Character Panel keeps its non-overlapping features. Color Picker also rides on
-- General but DOES stand down under ElvUI, by its own conflict list rather than
-- the skin gate (Modules/QoL/ColorPicker.lua:58, :259-260); its card already says
-- so, which is why it does not change what this list offers.
--
-- The Character Screen tab is deliberately not named Character Panel -- the
-- Frame Skins grid already has a row by that name for the window skin (:45).
GUIFrame:RegisterTabbedContent("SkinBlizzardFrames", function()
    local db = GetDB()

    local GENERAL     = { id = "SkinBlizzardFramesGeneral",    label = "General" }
    local FRAMES      = { id = "SkinBlizzardFramesFrames",     label = "Frame Skins" }
    local ADDONS      = { id = "SkinBlizzardFramesAddons",     label = "Addon Skins" }
    local LOOT_ROLL   = { id = "SkinBlizzardFramesLootRoll",   label = "Loot Roll" }
    local LOOT_WINDOW = { id = "SkinBlizzardFramesLootWindow", label = "Loot Window" }
    local WIDGETS     = { id = "SkinBlizzardFramesWidgets",    label = "UI Widgets" }
    local CHAR_SCREEN = { id = "CharacterPanel",               label = "Character Screen" }
    local TEXTS       = { id = "SkinMessages",                 label = "Blizzard Texts" }

    if KE.ShouldNotLoadModule and KE:ShouldNotLoadModule() then
        return { GENERAL, CHAR_SCREEN }
    end

    if not db or db.Enabled ~= true then
        return { GENERAL, LOOT_ROLL, LOOT_WINDOW, WIDGETS, CHAR_SCREEN, TEXTS }
    end

    return { GENERAL, FRAMES, ADDONS, LOOT_ROLL, LOOT_WINDOW, WIDGETS, CHAR_SCREEN, TEXTS }
end, {
    headerBuilder = function(scrollChild, yOffset)
        local db = GetDB()
        if not db then return yOffset, true end
        local card = GUIFrame:CreateCard(scrollChild, "Blizzard Frames", yOffset)
        card:AddHeaderToggle(db.Enabled == true, function(checked)
            db.Enabled = checked
            KE:SkinningReloadPrompt()
            -- AddHeaderToggle's own OnClick already calls RefreshContent.
        end)
        -- Say WHY the engine's own tabs are absent. Hiding them is right --
        -- greyed controls read as "locked on" rather than "does not apply"
        -- (the A6.3b Move Loot Rolls ruling) -- but hiding alone leaves a user
        -- unable to tell those settings exist at all. AddLabel bumps the card
        -- off its lone-header-bar height, which is the intended look here.
        if db.Enabled ~= true then
            card:AddLabel("Turn this on to configure frame and addon skins. The tabs below belong to modules that work with it off.")
        end
        local newOffset = yOffset + card:GetContentHeight() + Theme.paddingSmall
        -- Never collapse: the tab list above already drops the engine's own
        -- tabs when it is off, and collapsing as well would take the three
        -- independent modules' settings with it.
        return newOffset, false
    end,
})
