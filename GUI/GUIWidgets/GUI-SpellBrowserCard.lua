-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-SpellBrowserCard.lua                                ║
-- ║  Purpose: BigWigs spell browser. Search field +          ║
-- ║  per-boss grouped spell list with icons + Use buttons.   ║
-- ║  Used by DungeonTimers per-trigger Cfg page.             ║
-- ║                                                          ║
-- ║  Frames are pooled via KE.FramePool — the entire card    ║
-- ║  (with its persistent searchInput EditBox), spell rows,  ║
-- ║  boss headers, and separators all reuse instances across ║
-- ║  renders instead of leaking to UIParent on each rebuild. ║
-- ║                                                          ║
-- ║  Pooling the outer card preserves searchInput focus      ║
-- ║  across live-search rebuilds: the EditBox is the same    ║
-- ║  WoW frame instance every render, so HasFocus() carries  ║
-- ║  through. RebuildSpellList only swaps the inner pooled   ║
-- ║  rows — no full panel re-render needed.                  ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

local table_insert = table.insert
local ipairs = ipairs
local CreateFrame = CreateFrame

---------------------------------------------------------------------------------
-- Inner-pool factories: spell rows, boss headers, separators
---------------------------------------------------------------------------------

local function CreateSpellRowKit(holder)
    local row = CreateFrame("Frame", nil, holder)
    row:SetHeight(28)
    row:EnableMouse(true)

    local iconFrame = CreateFrame("Frame", nil, row)
    iconFrame:SetSize(24, 24)
    iconFrame:SetPoint("LEFT", row, "LEFT", 4, 0)

    local iconTexture = iconFrame:CreateTexture(nil, "ARTWORK")
    iconTexture:SetPoint("TOPLEFT", 1, -1)
    iconTexture:SetPoint("BOTTOMRIGHT", -1, 1)

    local iconBorder = CreateFrame("Frame", nil, iconFrame, "BackdropTemplate")
    iconBorder:SetAllPoints()
    iconBorder:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    iconBorder:SetBackdropBorderColor(0, 0, 0, 1)

    local label = row:CreateFontString(nil, "OVERLAY")
    label:SetPoint("LEFT", iconFrame, "RIGHT", 6, 0)
    label:SetPoint("RIGHT", row, "RIGHT", -70, 0)
    label:SetJustifyH("LEFT")
    KE:ApplyThemeFont(label, "small")

    local useBtn = GUIFrame:CreateButton(row, "Use", { width = 80, height = 22 })
    useBtn:SetPoint("RIGHT", row, "RIGHT", -4, 0)

    local kit = {
        row = row,
        iconFrame = iconFrame,
        iconTexture = iconTexture,
        iconBorder = iconBorder,
        label = label,
        useBtn = useBtn,
        _spellId = nil,
        _onSpellSelect = nil,
    }

    row:SetScript("OnEnter", function(self)
        if not kit._spellId then return end
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR_RIGHT", 30, 0)
        GameTooltip:SetSpellByID(kit._spellId)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)

    useBtn:HookScript("OnEnter", function(btn)
        if not kit._spellId then return end
        GameTooltip:SetOwner(btn, "ANCHOR_CURSOR_RIGHT", 30, 0)
        GameTooltip:SetSpellByID(kit._spellId)
        GameTooltip:Show()
    end)
    useBtn:SetScript("OnClick", function()
        if kit._onSpellSelect and kit._spellId then
            kit._onSpellSelect(kit._spellId)
        end
    end)

    return kit
end

local function CreateBossHeaderKit(holder)
    local row = CreateFrame("Frame", nil, holder)
    row:SetHeight(14)

    local label = row:CreateFontString(nil, "OVERLAY")
    label:SetPoint("LEFT", row, "LEFT", 4, -4)
    KE:ApplyThemeFont(label, "normal")

    return { row = row, label = label }
end

local function CreateSeparatorKit(holder)
    local row = CreateFrame("Frame", nil, holder)
    row:SetHeight(1)

    local tex = row:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    tex:SetColorTexture(Theme.border[1], Theme.border[2], Theme.border[3], 0.5)

    return { row = row, tex = tex }
end

local spellRowPool   = KE.FramePool:New(CreateSpellRowKit)
local bossHeaderPool = KE.FramePool:New(CreateBossHeaderKit)
local separatorPool  = KE.FramePool:New(CreateSeparatorKit)

---------------------------------------------------------------------------------
-- Inner-kit Configure: per-render data update only
---------------------------------------------------------------------------------

local function ConfigureSpellRow(kit, spell, onSpellSelect)
    kit.iconTexture:SetTexture(spell.icon or 134400)
    KE:ApplyIconZoom(kit.iconTexture)

    kit.label:SetText(spell.name .. "|cffffffff (" .. spell.spellId .. ")|r")
    kit.label:SetTextColor(Theme.textSecondary[1], Theme.textSecondary[2], Theme.textSecondary[3], 1)

    kit._spellId = spell.spellId
    kit._onSpellSelect = onSpellSelect
end

local function ConfigureBossHeader(kit, headerText)
    kit.label:SetText(headerText)
    kit.label:SetTextColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
end

local function ConfigureSeparator(kit)
    kit.tex:SetColorTexture(Theme.border[1], Theme.border[2], Theme.border[3], 0.5)
end

---------------------------------------------------------------------------------
-- RebuildSpellList: refresh the per-boss list inside an existing kit's card
-- without recreating the card or searchInput. Called by Configure on render
-- AND by the searchInput's OnTextChanged on every (debounced) keystroke.
---------------------------------------------------------------------------------

local function RebuildSpellList(kit)
    local card = kit.card
    local spells = kit._spells or {}
    local searchFilter = kit._searchFilter or ""
    local onSpellSelect = kit._onSpellSelect

    -- Release inner kits back to their pool holders. The persistent searchRow
    -- and noMatchRow stay parented to card.content (they are not in any pool).
    spellRowPool:ReleaseAll()
    bossHeaderPool:ReleaseAll()
    separatorPool:ReleaseAll()

    -- Reset the card's row tracking past index 1 without touching the
    -- persistent searchRow. Don't call card:Reset() — it reparents every row
    -- (including searchRow) to nil → orphans the focus-carrying editbox to
    -- UIParent. Don't even re-AddRow searchRow — AddRow does SetParent +
    -- ClearAllPoints which is a no-op when the parent is unchanged BUT can
    -- subtly disrupt focus on EditBox descendants in some WoW versions.
    -- Instead, freeze searchRow at index 1 (where the factory put it) and
    -- reset currentY to the post-searchRow high-water mark.
    card.currentY = kit._postSearchY
    if card.rows then
        for i = #card.rows, 2, -1 do card.rows[i] = nil end
    end
    card.content:SetHeight(card.currentY)

    -- Filter
    local filteredSpells = {}
    local searchLower = searchFilter:lower()
    for _, spell in ipairs(spells) do
        if searchLower == "" or (spell.name and spell.name:lower():find(searchLower, 1, true)) then
            table_insert(filteredSpells, spell)
        end
    end

    -- Group by boss
    local bossGroups = {}
    local bossOrder = {}
    local bossInfo = {}
    for _, spell in ipairs(filteredSpells) do
        local bossKey = spell.sortKey or 999999
        if not bossGroups[bossKey] then
            bossGroups[bossKey] = {}
            table_insert(bossOrder, bossKey)
            bossInfo[bossKey] = {
                name = spell.bossName or "Unknown",
                num = spell.bossNum or 0,
            }
        end
        table_insert(bossGroups[bossKey], spell)
    end
    table.sort(bossOrder)

    for _, bossKey in ipairs(bossOrder) do
        local boss = bossInfo[bossKey]
        local headerText = boss.num > 0
            and string.format("B%d %s", boss.num, boss.name)
            or string.format("— %s —", boss.name)

        local headerKit = bossHeaderPool:Acquire(card.content)
        ConfigureBossHeader(headerKit, headerText)
        card:AddRow(headerKit.row, 14)

        local separatorKit = separatorPool:Acquire(card.content)
        ConfigureSeparator(separatorKit)
        card:AddRow(separatorKit.row, 4)

        for _, spell in ipairs(bossGroups[bossKey]) do
            local rowKit = spellRowPool:Acquire(card.content)
            ConfigureSpellRow(rowKit, spell, onSpellSelect)
            card:AddRow(rowKit.row, 28)
        end
    end

    if #filteredSpells == 0 and searchFilter ~= "" then
        kit.noMatchRow:Show()
        card:AddRow(kit.noMatchRow, 30)
    else
        kit.noMatchRow:Hide()
    end
end

---------------------------------------------------------------------------------
-- Outer-pool factory: persistent card + searchInput + noMatchRow per kit.
-- The searchInput is the focus-carrying widget; reusing the same WoW EditBox
-- instance every render is what makes live-search not blow away focus.
---------------------------------------------------------------------------------

local function CreateSpellBrowserCardKit(holder)
    local kit = {}

    -- Card with placeholder title; Configure may swap title text per-render
    -- via card.titleText:SetText.
    local card = GUIFrame:CreateCard(holder, "Browse BigWigs Spells", 0)
    kit.card = card
    -- FramePool reparents kit.row when Acquire/ReleaseAll is called.
    kit.row = card

    -- Persistent search row + EditBox. _onSearchChange is set per-render in
    -- Configure; the EditBox's debounced OnTextChanged reads it via the
    -- editbox row's _onTextChanged slot wired here.
    local searchRow = GUIFrame:CreateRow(card.content, Theme.rowHeight)
    local searchInput = GUIFrame:CreateEditBox(searchRow, "Search spells", {
        value = "",
        callback = function(text)
            -- Enter / focus-lost: same path as live filter, plus persist.
            kit._searchFilter = text
            if kit._onSearchChange then kit._onSearchChange(text) end
            RebuildSpellList(kit)
        end,
        onTextChanged = function(text)
            -- Live typing (debounced ~150ms inside KEEditBox).
            kit._searchFilter = text
            if kit._onSearchChange then kit._onSearchChange(text) end
            RebuildSpellList(kit)
        end,
    })
    searchRow:AddWidget(searchInput, 1)
    -- Anchor searchRow ONCE at the top. Subsequent RebuildSpellList calls
    -- never re-AddRow this — they reset card.currentY to _postSearchY and
    -- start appending pooled rows from there. This keeps the focus-carrying
    -- EditBox's parent chain (editBox → container → searchRow → card.content)
    -- completely untouched across live-typing rebuilds.
    card:AddRow(searchRow, Theme.rowHeight)
    kit.searchRow = searchRow
    kit.searchInput = searchInput
    kit._postSearchY = card.currentY

    -- Persistent "no match" placeholder row. RebuildSpellList shows/hides it.
    local noMatchRow = GUIFrame:CreateRow(card.content, 30)
    local noMatchLabel = noMatchRow:CreateFontString(nil, "OVERLAY")
    noMatchLabel:SetPoint("LEFT", noMatchRow, "LEFT", 4, 0)
    KE:ApplyThemeFont(noMatchLabel, "small")
    noMatchLabel:SetText("No spells match your search.")
    noMatchLabel:SetTextColor(Theme.textSecondary[1], Theme.textSecondary[2], Theme.textSecondary[3], 1)
    noMatchRow:Hide()
    kit.noMatchRow = noMatchRow

    -- Walked by GUIFrame:RefreshKitThemeIfNeeded on theme switch. searchInput
    -- is the only theme-tied widget on this card; the dynamic spell-result
    -- rows are pooled inside RebuildSpellList and re-tinted from current
    -- Theme on each rebuild.
    kit.themeWidgets = { searchInput }

    return kit
end

local browserCardPool = KE.FramePool:New(CreateSpellBrowserCardKit)

local function ConfigureSpellBrowserCardKit(kit, scrollChild, yOffset, config)
    local card = kit.card
    local title = config.title or "Browse BigWigs Spells"
    local spells = config.spells or {}
    local searchFilter = config.searchFilter or ""

    if card.titleText then
        card.titleText:SetText(title)
    end

    -- Re-anchor card to its render position. CreateCard's TOPLEFT/RIGHT
    -- anchoring uses parent + yOffset; FramePool.Acquire already reparented
    -- card to scrollChild, but the anchor offset needs refreshing.
    card:ClearAllPoints()
    card:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", Theme.paddingSmall, -(yOffset or 0) + Theme.paddingSmall)
    card:SetPoint("RIGHT", scrollChild, "RIGHT", -Theme.paddingSmall, 0)
    card._yOffset = yOffset or 0

    -- Refresh theme colors lazily — only when KE._themeVersion has advanced.
    GUIFrame:RefreshKitThemeIfNeeded(kit)

    -- Update mutable kit slots BEFORE setting the searchInput value, so the
    -- silent SetValue doesn't accidentally fire a live-rebuild path (the
    -- silent flag suppresses _onTextChanged regardless, but order matters
    -- if a future change loosens that gate).
    kit._spells = spells
    kit._searchFilter = searchFilter
    kit._onSearchChange = config.onSearchChange
    kit._onSpellSelect = config.onSpellSelect

    -- Silent: don't fire onTextChanged or callback on programmatic seed.
    kit.searchInput:SetValue(searchFilter, true)

    RebuildSpellList(kit)
end

---------------------------------------------------------------------------------
-- Public entry: CreateSpellBrowserCard
---------------------------------------------------------------------------------

function GUIFrame:CreateSpellBrowserCard(scrollChild, yOffset, config)
    config = config or {}
    local spells = config.spells or {}

    -- Empty BigWigs branch: separate, non-pooled card. Focus survival is
    -- irrelevant here (no searchInput is shown). Release the outer pool so
    -- any leftover populated kit reparents back to its holder.
    if #spells == 0 then
        browserCardPool:ReleaseAll()
        spellRowPool:ReleaseAll()
        bossHeaderPool:ReleaseAll()
        separatorPool:ReleaseAll()

        local noBwCard = GUIFrame:CreateCard(scrollChild, "BigWigs Spell Browser", yOffset)
        noBwCard:AddLabel(
            "No BigWigs data available for this dungeon. Make sure BigWigs is installed and the dungeon module is loaded.")
        return noBwCard, noBwCard:GetNextOffset()
    end

    -- Populated branch: borrow a pooled kit (same WoW frames every render
    -- → searchInput focus survives), then refresh layout + list.
    browserCardPool:ReleaseAll()
    local kit = browserCardPool:Acquire(scrollChild)
    ConfigureSpellBrowserCardKit(kit, scrollChild, yOffset, config)

    return kit.card, kit.card:GetNextOffset()
end
