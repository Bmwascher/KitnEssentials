-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-Nicknames.lua                                       ║
-- ║  GUI: Nicknames                                          ║
-- ║  Purpose: Manage per-character nickname mappings used by ║
-- ║           the kes:nickname ElvUI tag family.             ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme    = KE.Theme

local CreateFrame = CreateFrame
local UnitFullName = UnitFullName
local UnitIsPlayer = UnitIsPlayer
local UnitExists = UnitExists
local GetNormalizedRealmName = GetNormalizedRealmName
local strtrim = strtrim
local pairs = pairs
local ipairs = ipairs
local table_sort = table.sort
local string_format = string.format

-- Separator used in the /kesnick chat print
local SEP = "\194\187\194\187"

-- Destructive-action color, matching "Reset All Triggers" in Timer Settings
local REMOVE_COLOR = { 0.9, 0.2, 0.2, 1 }

-- Persisted across GUIFrame:RefreshContent() so typing into the search box
-- doesn't wipe the filter on every keystroke.
local currentFilter = ""

-- Set to true in the search box's OnTextChanged so the next build re-focuses
-- the new search box (the old one gets destroyed by RefreshContent). Consumed
-- and cleared on that build. Flag-based rather than "re-focus whenever filter
-- is non-empty" so backspacing to empty text still keeps focus mid-typing.
local searchShouldFocus = false

-- Keys scheduled to flash an accent overlay on the next build. Populated by
-- save/import/replace handlers; each row consumes (and clears) its own entry
-- as the list rebuilds. Using a set lets bulk imports flash every new row.
local flashKeys = {}

---------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------

local function BuildKey(name, realm)
    if not name or name == '' then return nil end
    if not realm or realm == '' then
        realm = GetNormalizedRealmName()
    end
    if not realm or realm == '' then return nil end
    return name .. '-' .. realm
end

local function GetTargetKey()
    if not UnitExists('target') then return nil, "No target." end
    if not UnitIsPlayer('target') then return nil, "Target is not a player." end
    local name, realm = UnitFullName('target')
    local key = BuildKey(name, realm)
    if not key then return nil, "Could not build key for target." end
    return key
end

local function GetNickDB()
    return KE.db and KE.db.global and KE.db.global.Nicknames
end

local function NotifyChange()
    if KE.RefreshNicknameTags then KE:RefreshNicknameTags() end
end

-- Sort nickname keys: primary by nickname (so entries sharing the same nick
-- group together, matching NSRT's Management panel behavior), secondary by
-- character name within each group. Case-insensitive to keep "Bite" and
-- "bite" in the same bucket.
-- When `filter` is non-empty, only includes keys whose Name-Realm or nickname
-- contains the filter as a case-insensitive substring.
local function SortedKeys(tbl, filter)
    local keys = {}
    local lowerFilter = filter and filter ~= "" and filter:lower() or nil
    for k, v in pairs(tbl) do
        if not lowerFilter
            or k:lower():find(lowerFilter, 1, true)
            or (v or ""):lower():find(lowerFilter, 1, true) then
            keys[#keys + 1] = k
        end
    end
    table_sort(keys, function(a, b)
        local na = (tbl[a] or ""):lower()
        local nb = (tbl[b] or ""):lower()
        if na ~= nb then return na < nb end
        return a:lower() < b:lower()
    end)
    return keys
end

-- FontString-only cell used for column layouts in the saved list.
local function MakeColumnCell(parent, text, color, fontSize, justifyH)
    local cell = CreateFrame("Frame", nil, parent)
    local fs = cell:CreateFontString(nil, "OVERLAY")
    fs:SetAllPoints(cell)
    fs:SetJustifyH(justifyH or "LEFT")
    fs:SetJustifyV("MIDDLE")
    fs:SetWordWrap(false)
    KE:ApplyThemeFont(fs, fontSize or "normal")
    if color then
        fs:SetTextColor(color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)
    end
    fs:SetText(text or "")
    cell.text = fs
    return cell
end

-- Flat link-style button (no backdrop) used for secondary actions like
-- "Use Current Target". Subtle at rest, brightens on hover.
local function MakeLinkButton(parent, text, onClick)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetHeight(14)

    local fs = btn:CreateFontString(nil, "OVERLAY")
    fs:SetAllPoints(btn)
    fs:SetJustifyH("RIGHT")
    fs:SetJustifyV("MIDDLE")
    KE:ApplyThemeFont(fs, "small")
    local accent = Theme.accent
    fs:SetTextColor(accent[1], accent[2], accent[3], 0.65)
    fs:SetText(text or "")

    btn:SetFontString(fs)
    local w = fs:GetStringWidth()
    btn:SetWidth((w > 0 and w or 120) + 4)

    btn:SetScript("OnEnter", function()
        fs:SetTextColor(accent[1], accent[2], accent[3], 1)
    end)
    btn:SetScript("OnLeave", function()
        fs:SetTextColor(accent[1], accent[2], accent[3], 0.65)
    end)
    btn:SetScript("OnClick", function() if onClick then onClick() end end)

    btn.text = fs
    return btn
end

-- Renders a `tag  desc` row with both cells aligned via a fixed tag-column
-- width. Flush-left to match the "Tags for..." header above. Width tuned to
-- fit the longest tag (`[kes:nickname:colour:N]`) plus gutter, leaving the
-- remaining card width to the description so longer explanations don't clip.
local function AddTagRow(card, tagText, descText)
    local TAG_COL_WIDTH = 180

    local row = CreateFrame("Frame", nil, card.content)
    row:SetHeight(18)

    local tagFS = row:CreateFontString(nil, "OVERLAY")
    tagFS:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    tagFS:SetWidth(TAG_COL_WIDTH)
    tagFS:SetJustifyH("LEFT")
    tagFS:SetWordWrap(false)
    KE:ApplyThemeFont(tagFS, "normal")
    -- Neutral primary color so tags don't blend into the accent-colored subheader
    local tp = Theme.textPrimary
    tagFS:SetTextColor(tp[1] or 1, tp[2] or 1, tp[3] or 1, 1)
    tagFS:SetText(tagText)

    local descFS = row:CreateFontString(nil, "OVERLAY")
    descFS:SetPoint("TOPLEFT", row, "TOPLEFT", TAG_COL_WIDTH, 0)
    descFS:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 0)
    descFS:SetJustifyH("LEFT")
    descFS:SetWordWrap(false)
    KE:ApplyThemeFont(descFS, "normal")
    -- Matches the gray (#888888) descriptor color used by the CVars page
    descFS:SetTextColor(0x88 / 0xFF, 0x88 / 0xFF, 0x88 / 0xFF, 1)
    descFS:SetText(descText)

    card:AddRow(row, 18, 2)
end

---------------------------------------------------------------------------------
-- Content Builder
---------------------------------------------------------------------------------

GUIFrame:RegisterContent("Nicknames", function(scrollChild, yOffset)
    local T = Theme
    local nicks = GetNickDB()
    if not nicks then
        local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
        errorCard:AddLabel("Nicknames database not available.")
        return yOffset + errorCard:GetContentHeight() + T.paddingMedium
    end

    ---------------------------------------------------------------------------------
    -- Card 1: Nicknames (module-name card with Note + tag reference)
    ---------------------------------------------------------------------------------
    local aboutCard = GUIFrame:CreateCard(scrollChild, "Custom Nicknames", yOffset)

    -- Top half: "Note" block with explicit bullets (prefixed by theme-colored
    -- dashes to match the pattern used by other KE modules). Includes the
    -- ElvUI navigation path + example so new users know where tags go.
    local noteHeight = 86
    local noteRow = GUIFrame:CreateRow(aboutCard.content, noteHeight)
    local noteText = GUIFrame:CreateText(noteRow,
        KE:ColorTextByTheme("Note"),
        KE:ColorTextByTheme("-") .. " Map a character to a nickname displayed on ElvUI and Unhalted Unit Frames.\n" ..
        KE:ColorTextByTheme("-") .. " Falls back to the character name when no nickname is set.\n" ..
        KE:ColorTextByTheme("-") .. " ElvUI path: UnitFrames \194\187 Group Units \194\187 Party/Raid Tabs \194\187 Name \194\187 Text Format\n" ..
        KE:ColorTextByTheme("-") .. " UUF path: coming soon \194\187 party/raid frames in development",
        noteHeight, "hide")
    noteRow:AddWidget(noteText, 1)
    aboutCard:AddRow(noteRow, noteHeight)

    -- CreateText renders its body in small/textSecondary by default (quiet note).
    -- For the Nicknames page we want the note to carry more weight — bump the
    -- body font to "normal" and the color to textPrimary. Themed dashes still
    -- render in accent because they're wrapped with ColorTextByTheme.
    if noteText.container and noteText.container.label then
        local body = noteText.container.label
        KE:ApplyThemeFont(body, "normal")
        body:SetTextColor(T.textPrimary[1] or 1, T.textPrimary[2] or 1, T.textPrimary[3] or 1, 1)
    end

    -- Divider between sections
    aboutCard:AddSeparator()

    -- Bottom half: tags reference with a proper subheader (large, accent-colored)
    local tagsHeader = aboutCard.content:CreateFontString(nil, "OVERLAY")
    tagsHeader:SetPoint("TOPLEFT", aboutCard.content, "TOPLEFT", 0, -aboutCard.currentY)
    tagsHeader:SetPoint("TOPRIGHT", aboutCard.content, "TOPRIGHT", 0, -aboutCard.currentY)
    tagsHeader:SetJustifyH("LEFT")
    KE:ApplyThemeFont(tagsHeader, "large")
    tagsHeader:SetTextColor(T.accent[1], T.accent[2], T.accent[3], 1)
    tagsHeader:SetText("Available Tags")
    aboutCard.currentY = aboutCard.currentY + (tagsHeader:GetStringHeight() or 16) + 6
    aboutCard.content:SetHeight(aboutCard.currentY)
    aboutCard:UpdateHeight()

    AddTagRow(aboutCard, "[kes:nickname]",            "Full nickname")
    AddTagRow(aboutCard, "[kes:nickname:N]",          "First N characters  (N is 1 to 30)")
    AddTagRow(aboutCard, "[kes:nickname:short]",      "6 characters")
    AddTagRow(aboutCard, "[kes:nickname:medium]",     "10 characters")
    AddTagRow(aboutCard, "[kes:nickname:long]",       "20 characters")

    -- ElvUI class-color hint, placed just above the separator so it reads as
    -- "last thing in the shared block". Same gray as the UUF note below —
    -- parallel structure, each side documents its class-color path.
    local elvuiHint = aboutCard.content:CreateFontString(nil, "OVERLAY")
    elvuiHint:SetPoint("TOPLEFT", aboutCard.content, "TOPLEFT", 0, -aboutCard.currentY)
    elvuiHint:SetPoint("TOPRIGHT", aboutCard.content, "TOPRIGHT", 0, -aboutCard.currentY)
    elvuiHint:SetJustifyH("LEFT")
    KE:ApplyThemeFont(elvuiHint, "small")
    elvuiHint:SetTextColor(0x88 / 0xFF, 0x88 / 0xFF, 0x88 / 0xFF, 1)
    elvuiHint:SetText("ElvUI class color: prefix any KES tag with [classcolor].")
    aboutCard.currentY = aboutCard.currentY + (elvuiHint:GetStringHeight() or 12) + 4
    aboutCard.content:SetHeight(aboutCard.currentY)
    aboutCard:UpdateHeight()

    -- Subsection divider: tags above work in both ElvUI and UUF; the tags
    -- below are UUF-only because ElvUI users get class color by prefixing
    -- any name tag with ElvUI's built-in [classcolor] (see hint above).
    aboutCard:AddSeparator()

    local uufHeader = aboutCard.content:CreateFontString(nil, "OVERLAY")
    uufHeader:SetPoint("TOPLEFT", aboutCard.content, "TOPLEFT", 0, -aboutCard.currentY)
    uufHeader:SetJustifyH("LEFT")
    KE:ApplyThemeFont(uufHeader, "normal")
    uufHeader:SetTextColor(T.accent[1], T.accent[2], T.accent[3], 1)
    uufHeader:SetText("UUF only")
    aboutCard.currentY = aboutCard.currentY + (uufHeader:GetStringHeight() or 14) + 2
    aboutCard.content:SetHeight(aboutCard.currentY)
    aboutCard:UpdateHeight()

    local uufNote = aboutCard.content:CreateFontString(nil, "OVERLAY")
    uufNote:SetPoint("TOPLEFT", aboutCard.content, "TOPLEFT", 0, -aboutCard.currentY)
    uufNote:SetPoint("TOPRIGHT", aboutCard.content, "TOPRIGHT", 0, -aboutCard.currentY)
    uufNote:SetJustifyH("LEFT")
    KE:ApplyThemeFont(uufNote, "small")
    uufNote:SetTextColor(0x88 / 0xFF, 0x88 / 0xFF, 0x88 / 0xFF, 1)
    uufNote:SetText("All tags above also work in UUF.")
    aboutCard.currentY = aboutCard.currentY + (uufNote:GetStringHeight() or 12) + 6
    aboutCard.content:SetHeight(aboutCard.currentY)
    aboutCard:UpdateHeight()

    AddTagRow(aboutCard, "[kes:nickname:color]",      "Class color")
    AddTagRow(aboutCard, "[kes:nickname:color:N]",    "Class color + first N chars  (N is 1 to 30)")
    yOffset = yOffset + aboutCard:GetContentHeight() + T.paddingMedium

    ---------------------------------------------------------------------------------
    -- Card 2: Add / Update Nickname
    ---------------------------------------------------------------------------------
    local addCard = GUIFrame:CreateCard(scrollChild, "Add / Update Nickname", yOffset)

    -- Character editbox (full width) — tight spacing so the link feels attached
    local nameRow = GUIFrame:CreateEditBox(addCard.content, "Character  (Name-Realm)", "", nil)
    -- Bump label font from "small" default to "normal" for readability
    if nameRow.label then KE:ApplyThemeFont(nameRow.label, "normal") end
    addCard:AddRow(nameRow, 40, 2)

    -- "Use Current Target" secondary action, right-aligned beneath the field
    local linkRow = CreateFrame("Frame", nil, addCard.content)
    linkRow:SetHeight(14)
    local useTargetLink = MakeLinkButton(linkRow, "Use Current Target", function()
        local key, err = GetTargetKey()
        if not key then KE:Print(err) return end
        nameRow:SetValue(key)
    end)
    useTargetLink:SetPoint("TOPRIGHT", linkRow, "TOPRIGHT", -2, 0)
    addCard:AddRow(linkRow, 14)

    -- Nickname editbox (full width, uniform with Character)
    local nickRow = GUIFrame:CreateEditBox(addCard.content, "Nickname", "", nil)
    if nickRow.label then KE:ApplyThemeFont(nickRow.label, "normal") end
    addCard:AddRow(nickRow, 40)

    local function DoSave()
        local key = strtrim(nameRow:GetValue() or "")
        local nick = strtrim(nickRow:GetValue() or "")
        if key == "" then KE:Print("Character (Name-Realm) is required.") return end
        if nick == "" then KE:Print("Nickname is required.") return end
        -- If no realm was entered, append the current normalized realm so the
        -- key matches what UnitFullName produces at tag-lookup time.
        if not key:find("-") then
            local realm = GetNormalizedRealmName()
            if realm and realm ~= "" then key = key .. "-" .. realm end
        end
        nicks[key] = nick
        KE:Print(string_format("Saved: %s %s %s", key, SEP, nick))
        flashKeys[key] = true
        NotifyChange()
        GUIFrame:RefreshContent()
    end

    -- Save button spans the full card width (form-submit style).
    -- spacing=0 on AddWidget prevents the trailing gap that would otherwise
    -- leave the button ~6px narrower than the editboxes above it.
    local saveRow = GUIFrame:CreateRow(addCard.content, 28)
    local saveBtn = GUIFrame:CreateButton(saveRow, "Save", {
        height = 26,
        callback = DoSave,
    })
    saveRow:AddWidget(saveBtn, 1.0, 0)
    addCard:AddRow(saveRow, 28)

    -- Enter-to-save on the nickname field
    if nickRow.editBox then
        nickRow.editBox:SetScript("OnEnterPressed", function(self)
            self:ClearFocus()
            DoSave()
        end)
    end

    -- Tab from Character field into Nickname (Shift-Tab back to Character)
    if nameRow.editBox and nickRow.editBox then
        nameRow.editBox:SetScript("OnTabPressed", function()
            nickRow.editBox:SetFocus()
        end)
        nickRow.editBox:SetScript("OnTabPressed", function()
            nameRow.editBox:SetFocus()
        end)
    end

    yOffset = yOffset + addCard:GetContentHeight() + T.paddingMedium

    -- Total count (filter-independent). Drives the Export / Clear All disabled
    -- state and the Saved Nicknames header's "N of M" display.
    local totalCount = 0
    for _ in pairs(nicks) do totalCount = totalCount + 1 end

    -- Display shared "Something went wrong" popup instead of a chat line —
    -- error state is important enough to surface even when chat is hidden.
    local function ShowErrorPopup(title, msg)
        KE:CreatePrompt(title, msg or "unknown error",
            false, nil, false, nil, nil, nil, nil,
            function() end, nil, "OK", nil)
    end

    -- Snapshot-diff around an import so we can populate flashKeys with only
    -- the rows that were added or updated. For replace-mode imports the
    -- backend wipes first, so any key present afterwards is "touched".
    local function ImportWithFlash(text, replaceAll)
        local before = {}
        for k, v in pairs(nicks) do before[k] = v end
        local ok, msg = KE:ImportNicknames(text, replaceAll)
        if ok then
            for k, v in pairs(nicks) do
                if before[k] ~= v then flashKeys[k] = true end
            end
        end
        return ok, msg
    end

    ---------------------------------------------------------------------------------
    -- Card 3: Import / Export
    ---------------------------------------------------------------------------------
    -- Mirrors the Dungeon Timers Import/Export card: a single edit box, an
    -- Export button that opens a copyable popup, and an Import button that
    -- consumes the current edit box text. Format is a compact
    -- AceSerializer+LibDeflate payload behind the "!KEN1!" prefix.
    -- Sits above Saved Nicknames so the action buttons stay reachable without
    -- scrolling past a long list.
    local ioCard = GUIFrame:CreateCard(scrollChild, "Import / Export", yOffset)

    local bullet = KE:ColorTextByTheme("-")
    ioCard:AddLabel("|cff888888" .. bullet .. " Export produces a compact string you can share with friends.\n" ..
        bullet .. " Import merges by default. Toggle Replace to wipe first.|r")

    local ioRow = GUIFrame:CreateRow(ioCard.content, 50)
    local ioBox = GUIFrame:CreateEditBox(ioRow, "Paste import string or click Export...", "", function() end)
    ioRow:AddWidget(ioBox, 1)
    ioCard:AddRow(ioRow, 50)

    -- Mode toggle for Import. Sits in the right half of its own row so it
    -- visually stacks above the Import button below — making the pairing
    -- obvious without needing extra "affects Import only" copy. Export is
    -- always a full dump of the local table and is unaffected.
    local replaceMode = false
    local toggleRow = GUIFrame:CreateRow(ioCard.content, 36)

    -- Empty left half (under Export) — pushes the toggle into the right half.
    local toggleSpacer = CreateFrame("Frame", nil, toggleRow)
    toggleRow:AddWidget(toggleSpacer, 0.5, 0)

    local replaceCheck = GUIFrame:CreateCheckbox(toggleRow,
        "Replace entire list",
        false,
        function(state) replaceMode = state end)
    toggleRow:AddWidget(replaceCheck, 0.5)

    -- On/off descriptor to the right of the toggle knob. Same #888888 gray as
    -- the card's intro bullets so it reads as "helper" and not as a secondary
    -- label. Knob center sits at y=-26 inside the 36px row; nudged 2px lower
    -- because the FontString's visual midline reads slightly high of its
    -- anchor center.
    local replaceDesc = replaceCheck:CreateFontString(nil, "OVERLAY")
    replaceDesc:SetPoint("LEFT", replaceCheck, "TOPLEFT", 56, -28)
    replaceDesc:SetJustifyH("LEFT")
    KE:ApplyThemeFont(replaceDesc, "small")
    replaceDesc:SetTextColor(0x88 / 0xFF, 0x88 / 0xFF, 0x88 / 0xFF, 1)
    replaceDesc:SetText("ON wipes  ·  OFF merges")

    ioCard:AddRow(toggleRow, 36)

    local ioBtnRow = GUIFrame:CreateRow(ioCard.content, 28)

    local exportBtn = GUIFrame:CreateButton(ioBtnRow, "Export", {
        height = 26,
        callback = function()
            local encoded, err, count = KE:ExportNicknames()
            if encoded then
                KE:CreatePrompt(
                    "Export Nicknames (" .. count .. ")",
                    encoded,
                    true,
                    "Copy the string above (Ctrl+C)",
                    false
                )
            else
                ShowErrorPopup("Export Failed", err)
            end
        end,
    })
    ioBtnRow:AddWidget(exportBtn, 0.5)
    -- Nothing to export from an empty table — gray out so the button doesn't
    -- open a popup with a "No nicknames to export" error.
    if exportBtn.SetEnabled then exportBtn:SetEnabled(totalCount > 0) end

    local importBtn = GUIFrame:CreateButton(ioBtnRow, "Import", {
        height = 26,
        callback = function()
            local text = (ioBox.GetValue and ioBox:GetValue()) or ""
            if text == "" then
                ShowErrorPopup("Import", "Paste an import string first.")
                return
            end
            -- Replace mode is destructive in the same way Clear All is:
            -- require confirmation before wiping the local list.
            if replaceMode then
                KE:CreatePrompt(
                    "Replace Your Nickname List",
                    "This will wipe your current list before applying the import.\n\nAre you sure?",
                    false, nil, false, nil, nil, nil, nil,
                    function()
                        local ok, msg = ImportWithFlash(text, true)
                        if ok then
                            KE:Print(msg)
                            ioBox:SetValue("")
                            GUIFrame:RefreshContent()
                        else
                            ShowErrorPopup("Import Failed", msg)
                        end
                    end,
                    nil, "Replace", "Cancel"
                )
                return
            end
            local ok, msg = ImportWithFlash(text, false)
            if ok then
                KE:Print(msg)
                ioBox:SetValue("")
                GUIFrame:RefreshContent()
            else
                ShowErrorPopup("Import Failed", msg)
            end
        end,
    })
    ioBtnRow:AddWidget(importBtn, 0.5)
    ioCard:AddRow(ioBtnRow, 28)

    yOffset = yOffset + ioCard:GetContentHeight() + T.paddingMedium

    ---------------------------------------------------------------------------------
    -- Card 4: Saved Nicknames (column layout + row separators)
    ---------------------------------------------------------------------------------
    local sorted = SortedKeys(nicks, currentFilter)
    local hasFilter = currentFilter ~= ""
    local countSuffix
    if hasFilter then
        countSuffix = " (" .. #sorted .. " of " .. totalCount .. ")"
    elseif totalCount > 0 then
        countSuffix = " (" .. totalCount .. ")"
    else
        countSuffix = ""
    end
    local listCard = GUIFrame:CreateCard(scrollChild, "Saved Nicknames" .. countSuffix, yOffset)

    -- Search box in the card header (right side). Filters the Saved list
    -- live; the filter persists across GUIFrame:RefreshContent() via the
    -- module-level currentFilter so typing doesn't wipe on each keystroke.
    -- Only shown once the user has actually saved something — an empty
    -- database has nothing to filter.
    if totalCount > 0 and listCard.header then
        local searchBox = CreateFrame("EditBox", nil, listCard.header, "BackdropTemplate")
        searchBox:SetSize(200, 20)
        searchBox:SetPoint("RIGHT", listCard.header, "RIGHT", -T.paddingMedium, 0)
        searchBox:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        searchBox:SetBackdropColor(T.bgDark[1], T.bgDark[2], T.bgDark[3], 1)
        searchBox:SetBackdropBorderColor(T.border[1], T.border[2], T.border[3], 1)
        searchBox:SetTextInsets(6, 6, 0, 0)
        KE:ApplyThemeFont(searchBox, "small")
        searchBox:SetTextColor(T.textPrimary[1], T.textPrimary[2], T.textPrimary[3], 1)
        searchBox:SetAutoFocus(false)
        searchBox:SetMaxLetters(40)
        searchBox:SetText(currentFilter)

        -- Muted placeholder "Search..." shown only when the box is empty AND
        -- not focused — the standard input placeholder pattern.
        local placeholder = searchBox:CreateFontString(nil, "OVERLAY")
        placeholder:SetPoint("LEFT", searchBox, "LEFT", 6, 0)
        KE:ApplyThemeFont(placeholder, "small")
        placeholder:SetTextColor(T.textSecondary[1], T.textSecondary[2], T.textSecondary[3], 0.6)
        placeholder:SetText("Search...")
        if currentFilter ~= "" then placeholder:Hide() end

        local function UpdatePlaceholder()
            if searchBox:GetText() == "" and not searchBox:HasFocus() then
                placeholder:Show()
            else
                placeholder:Hide()
            end
        end

        searchBox:SetScript("OnEditFocusGained", function()
            searchBox:SetBackdropBorderColor(T.accent[1], T.accent[2], T.accent[3], 1)
            placeholder:Hide()
        end)
        searchBox:SetScript("OnEditFocusLost", function()
            searchBox:SetBackdropBorderColor(T.border[1], T.border[2], T.border[3], 1)
            UpdatePlaceholder()
        end)
        searchBox:SetScript("OnEscapePressed", function(self)
            self:SetText("")
            self:ClearFocus()
            searchShouldFocus = false
            if currentFilter ~= "" then
                currentFilter = ""
                GUIFrame:RefreshContent()
            end
        end)
        -- Only rebuild on actual user typing (userInput==true). SetText from
        -- the restore-state path above fires OnTextChanged with userInput=false,
        -- which would infinitely rebuild if we didn't guard.
        searchBox:SetScript("OnTextChanged", function(self, userInput)
            if not userInput then return end
            currentFilter = self:GetText() or ""
            searchShouldFocus = true
            GUIFrame:RefreshContent()
        end)
        searchBox:SetScript("OnEnterPressed", function(self)
            self:ClearFocus()
            searchShouldFocus = false
        end)

        -- Hand focus back to the new search box when the rebuild was triggered
        -- by the user typing into the old one. Consumed immediately so
        -- unrelated rebuilds (Save, Remove, Import) don't steal focus.
        if searchShouldFocus then
            searchShouldFocus = false
            searchBox:SetFocus()
            searchBox:SetCursorPosition(#currentFilter)
        end
    end

    if #sorted == 0 then
        if hasFilter then
            listCard:AddLabel("No matches for \"" .. currentFilter .. "\".")
        elseif totalCount == 0 then
            listCard:AddLabel("No nicknames saved yet. Add one above, or paste an import string in Import/Export.")
        end
    else
        -- Tighter column widths so the Remove button hugs the right edge
        local COL_CHAR   = 0.50
        local COL_NICK   = 0.30
        local COL_ACTION = 0.20
        local ROW_H = 28
        local BTN_H = 22
        local VCENTER_OFFSET = -(ROW_H - BTN_H) / 2

        -- Header
        local header = GUIFrame:CreateRow(listCard.content, 18)
        local muted = { T.textSecondary[1], T.textSecondary[2], T.textSecondary[3], 0.6 }
        header:AddWidget(MakeColumnCell(header, "CHARACTER", muted, "small"), COL_CHAR)
        header:AddWidget(MakeColumnCell(header, "NICKNAME",  muted, "small"), COL_NICK)
        header:AddWidget(MakeColumnCell(header, "",          muted, "small"), COL_ACTION)
        listCard:AddRow(header, 18, 2)
        listCard:AddSeparator()

        -- Group-boundary dividers: draw a 1px line at the TOP of each new
        -- nickname group (skipped on the very first data row since the
        -- header's AddSeparator already sits above it). Rows within the same
        -- group sit flush, so the 4 Dunnis visually cluster.
        local lastNick = nil

        for i, key in ipairs(sorted) do
            local nick = nicks[key]
            local isNewGroup = (i > 1) and (nick ~= lastNick)
            lastNick = nick

            -- Group separator: 6px spacer with a 2px divider centered inside.
            -- Centering the line in its own frame gives symmetric padding
            -- above and below (2px / line / 2px) — previously the line lived
            -- at the top of the next row, which left more breathing room
            -- above than below. Uses the same #888888 gray as the tag subtext
            -- in the About card, at reduced alpha so it reads as "muted
            -- detail" instead of "solid divider".
            if isNewGroup then
                local spacer = CreateFrame("Frame", nil, listCard.content)
                spacer:SetHeight(6)
                local divider = spacer:CreateTexture(nil, "ARTWORK")
                divider:SetHeight(2)
                divider:SetPoint("LEFT", spacer, "LEFT", 0, 0)
                divider:SetPoint("RIGHT", spacer, "RIGHT", 0, 0)
                divider:SetColorTexture(0x88 / 0xFF, 0x88 / 0xFF, 0x88 / 0xFF, 0.35)
                listCard:AddRow(spacer, 6, 0)
            end

            local row = GUIFrame:CreateRow(listCard.content, ROW_H)

            -- Make the whole row clickable: clicking fills the Add/Update
            -- fields above so the user can tweak and re-Save (upsert).
            row:EnableMouse(true)
            local hoverBg = row:CreateTexture(nil, "BACKGROUND")
            hoverBg:SetAllPoints(row)
            hoverBg:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 0.10)
            hoverBg:Hide()
            row:SetScript("OnEnter", function() hoverBg:Show() end)
            row:SetScript("OnLeave", function() hoverBg:Hide() end)

            -- Flash overlay: when this key was just saved/imported, briefly
            -- pulse an accent texture on its own layer (ARTWORK, above hoverBg)
            -- so it survives hover interactions. Fades from full alpha to 0
            -- over 0.8s, then removes itself. flashKeys is cleared immediately
            -- so a second refresh without a new mutation doesn't re-flash.
            if flashKeys[key] then
                flashKeys[key] = nil
                local flashTex = row:CreateTexture(nil, "ARTWORK")
                flashTex:SetAllPoints(row)
                flashTex:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 0.45)
                local ag = flashTex:CreateAnimationGroup()
                local alpha = ag:CreateAnimation("Alpha")
                alpha:SetFromAlpha(1)
                alpha:SetToAlpha(0)
                alpha:SetDuration(0.8)
                alpha:SetSmoothing("OUT")
                ag:SetScript("OnFinished", function() flashTex:Hide() end)
                ag:Play()
            end
            row:SetScript("OnMouseDown", function(_, button)
                if button ~= "LeftButton" then return end
                nameRow:SetValue(key)
                nickRow:SetValue(nick)
                -- Pull focus so the user sees where the input landed
                if nickRow.editBox then nickRow.editBox:SetFocus() end
            end)

            -- Character column
            row:AddWidget(MakeColumnCell(row, key,
                { T.textPrimary[1] or 1, T.textPrimary[2] or 1, T.textPrimary[3] or 1, 1 }),
                COL_CHAR)

            -- Nickname column (theme accent, left-aligned to match the header)
            row:AddWidget(MakeColumnCell(row, nick,
                { T.accent[1], T.accent[2], T.accent[3], 1 }),
                COL_NICK)

            -- Remove button, red text, vertically centered. Button frames
            -- consume their own clicks, so Remove doesn't trigger the row's
            -- click-to-edit handler above.
            local removeBtn = GUIFrame:CreateButton(row, "Remove", {
                height = BTN_H,
                callback = function()
                    nicks[key] = nil
                    KE:Print("Removed nickname for " .. key)
                    NotifyChange()
                    GUIFrame:RefreshContent()
                end,
            })
            if removeBtn.text then
                removeBtn.text:SetTextColor(REMOVE_COLOR[1], REMOVE_COLOR[2], REMOVE_COLOR[3], REMOVE_COLOR[4])
            end
            -- spacing=0 removes the trailing gap so the button's right edge
            -- sits flush with the row's right edge (and the underline below).
            row:AddWidget(removeBtn, COL_ACTION, 0, nil, VCENTER_OFFSET)

            listCard:AddRow(row, ROW_H, 2)
        end
    end

    yOffset = yOffset + listCard:GetContentHeight() + T.paddingMedium

    ---------------------------------------------------------------------------------
    -- Card 5: Clear All
    ---------------------------------------------------------------------------------
    -- Destructive bulk-delete with a confirmation popup. Mirrors the Reset
    -- pattern from Timer Settings; the button's text is tinted red to match
    -- the Remove buttons in the Saved Nicknames list.
    local clearCard = GUIFrame:CreateCard(scrollChild, "Clear All", yOffset)
    clearCard:AddLabel("|cff888888Remove every saved nickname. This cannot be undone.|r")

    local clearRow = GUIFrame:CreateRow(clearCard.content, 28)
    local clearBtn = GUIFrame:CreateButton(clearRow, "Clear All Nicknames", {
        height = 26,
        callback = function()
            KE:CreatePrompt(
                "Clear All Nicknames",
                "This will permanently remove every saved nickname.\n\nAre you sure?",
                false, nil, false, nil, nil, nil, nil,
                function()
                    local removed = KE:ClearAllNicknames()
                    KE:Print("Cleared " .. removed .. " nickname(s).")
                    GUIFrame:RefreshContent()
                end,
                nil, "Clear", "Cancel"
            )
        end,
    })
    if clearBtn.text then
        clearBtn.text:SetTextColor(REMOVE_COLOR[1], REMOVE_COLOR[2], REMOVE_COLOR[3], REMOVE_COLOR[4])
    end
    clearRow:AddWidget(clearBtn, 1.0, 0)
    -- Empty list → nothing to clear; disable the button so clicking doesn't
    -- pop a pointless confirmation.
    if clearBtn.SetEnabled then clearBtn:SetEnabled(totalCount > 0) end
    clearCard:AddRow(clearRow, 28)

    yOffset = yOffset + clearCard:GetContentHeight() + T.paddingMedium

    return yOffset
end)
