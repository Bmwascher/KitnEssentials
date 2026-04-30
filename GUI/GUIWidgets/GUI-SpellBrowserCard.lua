-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-SpellBrowserCard.lua                                ║
-- ║  Purpose: BigWigs spell browser. Search field +          ║
-- ║  per-boss grouped spell list with icons + Use buttons.   ║
-- ║  Used by DungeonTimers per-trigger Cfg page.             ║
-- ║                                                          ║
-- ║  Frames are pooled via KE.FramePool — spell rows, boss   ║
-- ║  headers, and separators reuse instances across renders  ║
-- ║  instead of leaking to UIParent on each ClearContent.    ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

local table_insert = table.insert
local ipairs = ipairs
local CreateFrame = CreateFrame

---------------------------------------------------------------------------------
-- Factories: build kit shape once, parent to pool's hidden holder
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
        -- Per-render mutable state, updated by ConfigureSpellRow:
        _spellId = nil,
        _onSpellSelect = nil,
    }

    -- Wire scripts ONCE at kit creation. They read mutable state from kit
    -- fields that ConfigureSpellRow updates per-render. Doing this in the
    -- factory (not Configure) preserves the "no accumulating closures
    -- across renders" property the pool refactor is after — hooks are
    -- bounded to kit lifetime, not render count.

    -- Row is a bare Frame we own; SetScript is safe.
    row:SetScript("OnEnter", function(self)
        if not kit._spellId then return end
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR_RIGHT", 30, 0)
        GameTooltip:SetSpellByID(kit._spellId)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Use button: KEButton already owns OnEnter (border-fade animation)
    -- and OnLeave (animation reverse + GameTooltip:Hide). We HookScript
    -- OnEnter to LAYER the spell tooltip on top of the animation, and we
    -- don't touch OnLeave — KEButton's own OnLeave already hides the
    -- tooltip. OnClick is overridden because KEButton's internal OnClick
    -- would call a nil callback (we didn't pass one to CreateButton).
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
    -- Mirrors GUIFrame:CreateSeparator: a Frame with a 1px texture child.
    local row = CreateFrame("Frame", nil, holder)
    row:SetHeight(1)

    local tex = row:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    tex:SetColorTexture(Theme.border[1], Theme.border[2], Theme.border[3], 0.5)

    return { row = row, tex = tex }
end

---------------------------------------------------------------------------------
-- Pool instances: per-kit-type, file scope, live for the session
---------------------------------------------------------------------------------

local spellRowPool   = KE.FramePool:New(CreateSpellRowKit)
local bossHeaderPool = KE.FramePool:New(CreateBossHeaderKit)
local separatorPool  = KE.FramePool:New(CreateSeparatorKit)

---------------------------------------------------------------------------------
-- Configure: per-render data update only. Script handlers are factory-bound
-- (see CreateSpellRowKit) and read mutable state (_spellId, _onSpellSelect)
-- set here. No SetScript / HookScript in Configure — keeps closures bounded
-- to kit lifetime, not render count.
---------------------------------------------------------------------------------

local function ConfigureSpellRow(kit, spell, onSpellSelect)
    kit.iconTexture:SetTexture(spell.icon or 134400)
    KE:ApplyIconZoom(kit.iconTexture)

    kit.label:SetText(spell.name .. "|cffffffff (" .. spell.spellId .. ")|r")
    kit.label:SetTextColor(Theme.textSecondary[1], Theme.textSecondary[2], Theme.textSecondary[3], 1)

    -- Update mutable state read by the kit's permanently-bound scripts
    -- (wired in CreateSpellRowKit). No SetScript / HookScript here —
    -- handlers are factory-bound and live for the kit's lifetime.
    kit._spellId = spell.spellId
    kit._onSpellSelect = onSpellSelect
end

local function ConfigureBossHeader(kit, headerText)
    kit.label:SetText(headerText)
    kit.label:SetTextColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
end

local function ConfigureSeparator(kit)
    -- Color is set in factory and doesn't change per-render. Kept as a
    -- function so future style variants (e.g. accent separator) have a
    -- clear extension point.
    kit.tex:SetColorTexture(Theme.border[1], Theme.border[2], Theme.border[3], 0.5)
end

---------------------------------------------------------------------------------
-- Public entry: CreateSpellBrowserCard
---------------------------------------------------------------------------------

function GUIFrame:CreateSpellBrowserCard(scrollChild, yOffset, config)
    config = config or {}
    local title = config.title or "Browse BigWigs Spells"
    local spells = config.spells or {}
    local searchFilter = config.searchFilter or ""
    local onSearchChange = config.onSearchChange
    local onSpellSelect = config.onSpellSelect

    -- Release every pooled kit at the top of every render. Kits reparent
    -- back to their pools' hidden holders; the orphaned old card from
    -- the previous render is left empty and eligible for GC.
    spellRowPool:ReleaseAll()
    bossHeaderPool:ReleaseAll()
    separatorPool:ReleaseAll()

    if #spells == 0 then
        local noBwCard = GUIFrame:CreateCard(scrollChild, "BigWigs Spell Browser", yOffset)
        noBwCard:AddLabel(
            "No BigWigs data available for this dungeon. Make sure BigWigs is installed and the dungeon module is loaded.")
        return noBwCard, noBwCard:GetNextOffset()
    end

    local card = GUIFrame:CreateCard(scrollChild, title, yOffset)

    local searchRow = GUIFrame:CreateRow(card.content, Theme.rowHeight)
    local searchInput = GUIFrame:CreateEditBox(searchRow, "Search spells", {
        value = searchFilter,
        callback = function(text)
            if onSearchChange then onSearchChange(text) end
        end
    })
    searchRow:AddWidget(searchInput, 1)
    card:AddRow(searchRow, Theme.rowHeight)

    local filteredSpells = {}
    local searchLower = searchFilter:lower()
    for _, spell in ipairs(spells) do
        if searchLower == "" or (spell.name and spell.name:lower():find(searchLower, 1, true)) then
            table_insert(filteredSpells, spell)
        end
    end

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
        local noMatchRow = GUIFrame:CreateRow(card.content, 30)
        local noMatchLabel = noMatchRow:CreateFontString(nil, "OVERLAY")
        noMatchLabel:SetPoint("LEFT", noMatchRow, "LEFT", 4, 0)
        KE:ApplyThemeFont(noMatchLabel, "small")
        noMatchLabel:SetText("No spells match your search.")
        noMatchLabel:SetTextColor(Theme.textSecondary[1], Theme.textSecondary[2], Theme.textSecondary[3], 1)
        card:AddRow(noMatchRow, 30)
    end

    return card, card:GetNextOffset()
end
