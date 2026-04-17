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
local function SortedKeys(tbl)
    local keys = {}
    for k in pairs(tbl) do keys[#keys + 1] = k end
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
-- width. Flush-left to match the "Tags for..." header above.
local function AddTagRow(card, tagText, descText)
    local TAG_COL_WIDTH = 210

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
        KE:ColorTextByTheme("-") .. " Map a character to a nickname displayed on ElvUI unit frames.\n" ..
        KE:ColorTextByTheme("-") .. " Falls back to the character name when no nickname is set.\n" ..
        KE:ColorTextByTheme("-") .. " ElvUI path: UnitFrames > Group Units > Party/Raid Tabs > Name > Text Format\n" ..
        KE:ColorTextByTheme("-") .. " Example: [classcolor][kes:nickname]",
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

    AddTagRow(aboutCard, "[kes:nickname]",        "Full nickname")
    AddTagRow(aboutCard, "[kes:nickname:N]",      "First N characters  (N is any number from 1 to 30)")
    AddTagRow(aboutCard, "[kes:nickname:short]",  "6 characters")
    AddTagRow(aboutCard, "[kes:nickname:medium]", "10 characters")
    AddTagRow(aboutCard, "[kes:nickname:long]",   "20 characters")
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

    ---------------------------------------------------------------------------------
    -- Card 3: Saved Nicknames (column layout + row separators)
    ---------------------------------------------------------------------------------
    local sorted = SortedKeys(nicks)
    local countSuffix = (#sorted > 0) and ("  (" .. #sorted .. ")") or ""
    local listCard = GUIFrame:CreateCard(scrollChild, "Saved Nicknames" .. countSuffix, yOffset)

    if #sorted == 0 then
        listCard:AddLabel("No nicknames saved yet. Add one above.")
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
    return yOffset
end)
