-- ╔══════════════════════════════════════════════════════════╗
-- ║  TrainingPanel.lua                                       ║
-- ║  Purpose: The one What's Training panel: its rows, and   ║
-- ║           its place beside the book, a trainer or alone. ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)

local T = KE.Training or {}
KE.Training = T

local Rules = KE.TrainingRules

local C_Spell, C_Timer = C_Spell, C_Timer
local CreateFrame = CreateFrame
local GameTooltip = GameTooltip
local InCombatLockdown = InCombatLockdown
local IsShiftKeyDown = IsShiftKeyDown
local MenuUtil = MenuUtil
local UIParent = UIParent
local ipairs, issecretvalue, min = ipairs, issecretvalue, math.min
local concat = table.concat

local Panel = {}
T.Panel = Panel

local WIDTH, ALONE_HEIGHT = 300, 643
local HEADER_HEIGHT, SEARCH_HEIGHT, PAD = 32, 22, 8
local BLOCK_HEIGHT, BARS_HEIGHT = 124, 26
local MAX_STOPS, STOPS_TOP, STOP_HEIGHT, READ_HEIGHT = 3, 88, 14, 18
local ROW_HEIGHT, SECTION_HEIGHT, ICON_SIZE = 30, 20, 22
local NEED, GAP, PIN_INSET = 308, 8, 66
local SCROLLBAR_ROOM, SWAP_NAMES_ROOM = 8, 30
local SMALL_LINE_HEIGHT, ICON_TOP = 14, (ROW_HEIGHT - ICON_SIZE) / 2
local FOOTER_LINE_WIDTH, FOOTER_TEXT_GAP = WIDTH - 2 * PAD, 8
local WEAPON_LINE_WIDTH = WIDTH - 2 * PAD - SCROLLBAR_ROOM - ICON_SIZE - 6
local BOOK_BUTTON_WIDTH, BOOK_BUTTON_HEIGHT = 150, 26
local DATA_DELAY = 0.1
local WHITE = "Interface\\Buttons\\WHITE8X8"
local FALLBACK_ICON = 134400
local CLOSE_GLYPH = "x"
local TIP_UNTICK_ALL = "Click to untick every spell."
local TIP_TICK_ALL = "Click to tick every spell but skipped spells and new professions."

local HEX = {
    gold = "ffd100", silver = "c8c8d0", copper = "eda55f", amber = "e6bf4d",
    green = "4dcc66", muted = "9c9c9c", white = "ffffff",
}
local WINDOW_COLOR = { 0.031, 0.031, 0.031, 0.98 }
local FIELD_COLOR = { 0.075, 0.075, 0.075, 1 }
local BORDER_COLOR = { 0.188, 0.188, 0.188, 1 }
local AMBER_COLOR = { 0.902, 0.749, 0.302, 1 }
local UNKNOWN_COLOR = { 0.612, 0.612, 0.612, 1 }
local UNKNOWN_BAR_HEIGHT = 4
local BACKDROP = { bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 }

local frame, bookButton
local bookHooked, trainerHooked = false, false
local bookAnchored, placeAfterCombat = false, false
local anchoredTo
local drawQueued, dataQueued = false, false
local rows, barTextures = {}, {}
local gains, requested = {}, {}

local state = {
    host = nil, alone = false, bookOpen = false, closed = false,
    query = "", open = {},
}

function T.Paint(key, text)
    local hex = key == "accent" and KE:GetThemeColorHex() or HEX[key]
    return "|cff" .. hex .. text .. "|r"
end

function T.Coins(copper)
    return Rules.Coins(copper, T.Paint)
end

local function MakeText(parent, size)
    local text = parent:CreateFontString(nil, "OVERLAY")
    KE:ApplyThemeFont(text, size)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(false)
    return text
end

local function Backdrop(target, color)
    target:SetBackdrop(BACKDROP)
    target:SetBackdropColor(color[1], color[2], color[3], color[4])
    target:SetBackdropBorderColor(BORDER_COLOR[1], BORDER_COLOR[2], BORDER_COLOR[3], BORDER_COLOR[4])
end

function Panel.MakeButton(parent, label, width, height, onClick)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetSize(width, height)
    Backdrop(button, FIELD_COLOR)
    button.text = MakeText(button, "small")
    button.text:SetPoint("CENTER")
    button.text:SetText(label)
    button:SetScript("OnClick", onClick)
    button:SetScript("OnDisable", function(self) self.text:SetAlpha(0.5) end)
    button:SetScript("OnEnable", function(self) self.text:SetAlpha(1) end)
    return button
end

local function SectionTotal(section)
    return Rules.TotalText(section.copper, section.approx, section.unpriced, T.Coins)
end

local function PriceText(entry)
    if entry.mark == "quest" then return "" end
    if entry.mark == "none" then return "At the trainer" end
    return (entry.mark == "~" and "~" or "") .. T.Coins(entry.copper)
end

local function RequestDescription(id)
    if requested[id] or not C_Spell.RequestLoadSpellData then return end
    requested[id] = true
    C_Spell.RequestLoadSpellData(id)
end

local function GainText(entry)
    local needs = entry.row.needs
    if not needs then return nil end
    local id = entry.id
    if gains[id] ~= nil then return gains[id] or nil end
    local old, new = C_Spell.GetSpellDescription(needs), C_Spell.GetSpellDescription(id)
    if not old or old == "" then RequestDescription(needs) end
    if not new or new == "" then RequestDescription(id) end
    if not old or old == "" or not new or new == "" then return nil end
    local gain = Rules.RankGain(old, new)
    gains[id] = gain or false
    return gain
end

-- A class trainer's row, as its row in the planned list: rank, gain and tag.
local function OfferLine(offer)
    if offer.isProfession then return "Uses a profession slot" end
    local entry = offer.id and T.plan and T.plan.entry[offer.id]
    if not entry then return "" end
    local parts = {}
    local rank = C_Spell.GetSpellSubtext(entry.id)
    if rank and rank ~= "" then parts[#parts + 1] = rank end
    local gain = GainText(entry)
    if gain then parts[#parts + 1] = T.Paint("green", gain) end
    if entry.tag then parts[#parts + 1] = entry.tag end
    return concat(parts, ", ")
end

local function SecondLine(entry)
    local rank = C_Spell.GetSpellSubtext(entry.id)
    local parts = {}
    if rank and rank ~= "" then parts[#parts + 1] = rank end
    if entry.state == "rank" then
        parts[#parts + 1] = "from level " .. entry.level
    elseif entry.state == "quest" then
        parts[#parts + 1] = "Taught by a quest"
    elseif entry.state == "now" or entry.state == "soon" then
        local gain = GainText(entry)
        if gain then parts[#parts + 1] = T.Paint("green", gain) end
    end
    if entry.tag then parts[#parts + 1] = entry.tag end
    return concat(parts, ", ")
end

---------------------------------------------------------------------------------
-- The rows
---------------------------------------------------------------------------------
local function OpenMenu(owner, id)
    if not MenuUtil then return end
    local store = T.Store()
    local name = T.NameOf(id)
    local spells = T.classData and T.classData.spells or {}
    local function Changed()
        T.module:RebuildPlan()
        Panel.QueueDraw()
    end
    MenuUtil.CreateContextMenu(owner, function(_, root)
        if store.skipped[id] then
            root:CreateButton("Stop Skipping", function() store.skipped[id] = nil; Changed() end)
            root:CreateButton("Stop Skipping All Ranks", function()
                Rules.SkipAll(spells, name, T.NameOf, store.skipped, nil)
                Changed()
            end)
        else
            root:CreateButton("Skip", function() store.skipped[id] = true; Changed() end)
            root:CreateButton("Skip All Ranks", function()
                Rules.SkipAll(spells, name, T.NameOf, store.skipped, true)
                Changed()
            end)
        end
        if T.db.RankSwap and name then
            if store.kept[name] then
                root:CreateButton("Let Update Bars Swap It", function() store.kept[name] = nil; T.Swap.Scan() end)
            else
                root:CreateButton("Keep This Rank on My Bars", function() store.kept[name] = true; T.Swap.Scan() end)
            end
        end
    end)
end

local function RowSpellId(item)
    if item.entry then return item.entry.id end
    if item.offer then return item.offer.id end
    return nil
end

local function OnRowClick(self, button)
    local item = self.item
    if not item then return end
    if item.kind == "section" then
        if item.action then
            item.action()
            -- Its tooltip would still name the click just done.
            GameTooltip:Hide()
            Panel.QueueDraw()
        elseif item.toggle then
            state.open[item.key] = not state.open[item.key]
            Panel.QueueDraw()
        end
        return
    end
    local id = RowSpellId(item)
    if IsShiftKeyDown() and id then
        local insert = _G.ChatFrameUtil and _G.ChatFrameUtil.InsertLink
        local link = C_Spell.GetSpellLink(id)
        if insert and link then insert(link) end
        return
    end
    if button == "RightButton" then
        if id then OpenMenu(self, id) end
        return
    end
    if item.kind == "offer" and not item.dim then
        T.Learn.Toggle(item.offer)
        Panel.QueueDraw()
    end
end

local function IsCut(text)
    local cut = text:IsTruncated()
    return not issecretvalue(cut) and cut
end

local function OnRowEnter(self)
    self.hover:Show()
    local item = self.item
    if not item then return end
    if item.kind == "section" or item.kind == "text" then
        if item.tip or IsCut(self.name) then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(item.tip or self.name:GetText(), 1, 1, 1, 1, true)
            GameTooltip:Show()
        end
        return
    end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if item.kind == "later" then
        GameTooltip:SetText("Level " .. item.group.level, 1, 1, 1)
        for _, entry in ipairs(item.group.rows) do
            GameTooltip:AddLine(T.NameOf(entry.id) or "", 1, 1, 1)
        end
    elseif item.offer and GameTooltip.SetTrainerService then
        GameTooltip:SetTrainerService(item.offer.index)
    else
        local id = RowSpellId(item) or (item.weapon and item.weapon[2])
        if id then GameTooltip:SetSpellByID(id) end
        local entry = item.entry
        if entry and entry.state == "rank" and entry.row.needs then
            GameTooltip:AddLine("Waits on " .. (T.NameOf(entry.row.needs) or "an earlier rank") .. ".", 1, 0.82, 0)
        end
        if entry and entry.tag then GameTooltip:AddLine(entry.tag, 0.61, 0.61, 0.61) end
    end
    if self.sub:IsShown() and IsCut(self.sub) then GameTooltip:AddLine(self.sub:GetText(), 1, 1, 1, true) end
    GameTooltip:Show()
end

local function OnRowLeave(self)
    self.hover:Hide()
    GameTooltip:Hide()
end

local function GetRow(index)
    local row = rows[index]
    if row then return row end
    row = CreateFrame("Button", nil, frame.content)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row.hover = row:CreateTexture(nil, "BACKGROUND")
    row.hover:SetAllPoints()
    row.hover:SetColorTexture(1, 1, 1, 0.06)
    row.hover:Hide()
    row.box = row:CreateTexture(nil, "ARTWORK")
    row.box:SetSize(12, 12)
    row.box:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ICON_SIZE, ICON_SIZE)
    row.name = MakeText(row, "normal")
    row.name:SetJustifyV("TOP")
    row.sub = MakeText(row, "small")
    row.sub:SetJustifyV("BOTTOM")
    row.price = MakeText(row, "small")
    row.price:SetJustifyH("RIGHT")
    row.price:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row:SetScript("OnClick", OnRowClick)
    row:SetScript("OnEnter", OnRowEnter)
    row:SetScript("OnLeave", OnRowLeave)
    rows[index] = row
    return row
end

local function LayoutSpellRow(row, hasBox, iconFile, dim)
    row.box:SetShown(hasBox)
    row.icon:Show()
    row.icon:SetTexture(iconFile or FALLBACK_ICON)
    row.icon:SetDesaturated(dim)
    row.icon:ClearAllPoints()
    row.icon:SetPoint("LEFT", row, "LEFT", hasBox and 16 or 0, 0)
    row.name:ClearAllPoints()
    row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 6, 0)
    row.name:SetPoint("RIGHT", row.price, "LEFT", -4, 0)
    row.sub:ClearAllPoints()
    row.sub:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 6, 0)
    row.sub:SetPoint("RIGHT", row.price, "LEFT", -4, 0)
    row.sub:Show()
    local alpha = dim and 0.5 or 1
    row.name:SetAlpha(alpha)
    row.sub:SetAlpha(alpha)
end

local function LayoutTextRow(row)
    row.box:Hide()
    row.icon:Hide()
    row.sub:Hide()
    row.name:ClearAllPoints()
    row.name:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.name:SetPoint("RIGHT", row.price, "LEFT", -4, 0)
    row.name:SetAlpha(1)
end

-- The second line takes the row's whole width, and the price moves up to the first.
local function WidenSecondLine(row)
    row.price:ClearAllPoints()
    row.price:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, -4)
    row.sub:SetPoint("RIGHT", row, "RIGHT", 0, 0)
end

-- The width a string's text renders at, or nil when it reads secret.
local function TextWidth(text)
    local width = text:GetUnboundedStringWidth()
    if issecretvalue(width) then return nil end
    return width
end

-- One line when lead and map fit the room, else the map on a line of its own. A width
-- that reads secret takes two lines. True when the text took two.
local function SetLeadAndMap(text, room, lead, map)
    text:SetWordWrap(false)
    if not (lead and map) then
        text:SetText(lead and T.Paint("muted", lead) or "")
        return false
    end
    text:SetText(T.Paint("muted", lead .. ", " .. map))
    local width = TextWidth(text)
    if width and width <= room then return false end
    text:SetWordWrap(true)
    text:SetText(T.Paint("muted", lead .. ",\n" .. map))
    return true
end

local function FillRow(row, item)
    row.item = item
    row.sub:SetWordWrap(false)
    row.price:ClearAllPoints()
    row.price:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row.price:SetText(item.right or "")
    if item.kind == "section" or item.kind == "text" then
        LayoutTextRow(row)
        row.name:SetText(item.left or "")
        return SECTION_HEIGHT
    end
    if item.kind == "later" then
        LayoutSpellRow(row, false, nil, false)
        row.icon:Hide()
        WidenSecondLine(row)
        row.name:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -2)
        row.sub:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 2)
        row.name:SetText("Level " .. item.group.level)
        row.sub:SetText(#item.group.rows .. (#item.group.rows == 1 and " spell" or " spells") .. item.byThen)
        return ROW_HEIGHT
    end
    if item.kind == "weapon" then
        LayoutSpellRow(row, false, C_Spell.GetSpellTexture(item.weapon[2]), false)
        WidenSecondLine(row)
        row.name:SetText(T.NameOf(item.weapon[2]) or "")
        T.Route.Ensure()
        if not SetLeadAndMap(row.sub, WEAPON_LINE_WIDTH, T.Route.WeaponText(item.weapon)) then return ROW_HEIGHT end
        -- The icon and name keep the places a one-line row gives them.
        row.icon:ClearAllPoints()
        row.icon:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -ICON_TOP)
        row.sub:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 6, -SMALL_LINE_HEIGHT)
        return ROW_HEIGHT + SMALL_LINE_HEIGHT
    end
    if item.kind == "offer" then
        local offer = item.offer
        LayoutSpellRow(row, not item.dim, offer.icon, item.dim)
        row.name:SetText(offer.name)
        row.sub:SetText(item.sub or "")
        if not item.dim then
            local ticked = T.Learn.IsTicked(offer)
            local accent = KE.Theme.accent
            row.box:SetColorTexture(ticked and accent[1] or BORDER_COLOR[1], ticked and accent[2] or BORDER_COLOR[2],
                ticked and accent[3] or BORDER_COLOR[3], 1)
        end
        return ROW_HEIGHT
    end
    local entry = item.entry
    LayoutSpellRow(row, false, C_Spell.GetSpellTexture(entry.id), item.dim)
    row.name:SetText(T.NameOf(entry.id) or "")
    row.sub:SetText(SecondLine(entry))
    return ROW_HEIGHT
end

local function DrawItems(items)
    local y, content = 0, frame.content
    for index, item in ipairs(items) do
        local row = GetRow(index)
        local height = FillRow(row, item)
        row:SetHeight(height)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
        row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -y)
        row:Show()
        y = y + height
    end
    for index = #items + 1, #rows do
        rows[index].item = nil
        rows[index]:Hide()
    end
    content:SetHeight(y)
    if frame.scrollbar then
        local height = frame.scroll:GetHeight()
        if not issecretvalue(height) then frame.scrollbar:UpdateVisibility(y, height or 0) end
    end
end

---------------------------------------------------------------------------------
-- What the list holds
---------------------------------------------------------------------------------
local function AddSection(items, key, left, right, toggle)
    items[#items + 1] = { kind = "section", key = key, left = T.Paint("muted", left), right = right, toggle = toggle }
end

local function AddText(items, text)
    items[#items + 1] = { kind = "text", left = text }
end

local function AddGoldLine(items, plan)
    AddText(items, T.Paint("amber", "your " .. T.Coins(plan.gold) .. " ends here, priced spells"))
end

local function AddEntries(items, plan, section, dim)
    for _, entry in ipairs(section.rows) do
        if plan.goldAt == entry then AddGoldLine(items, plan) end
        items[#items + 1] = { kind = "spell", entry = entry, right = PriceText(entry), dim = dim }
    end
end

local function BuildAwayItems(plan)
    local items = {}
    if state.query ~= "" then
        local found = Rules.Search(plan.rows, state.query, T.NameOf)
        if #found == 0 then AddText(items, T.Paint("muted", "No spells match.")) end
        for _, row in ipairs(found) do
            local entry = plan.entry[row[2]]
            items[#items + 1] = { kind = "spell", entry = entry, right = PriceText(entry) }
        end
        return items
    end
    local now, rank, quest, soon = plan.now, plan.rank, plan.quest, plan.soon
    if #now.rows == 0 and #rank.rows == 0 and #quest.rows == 0 and #soon.rows == 0 and #plan.later == 0 then
        AddText(items, "Nothing left to train.")
    end
    if #now.rows > 0 then
        AddSection(items, "now", ("TRAIN NOW (%d)"):format(#now.rows), SectionTotal(now))
        AddEntries(items, plan, now)
    end
    if #rank.rows > 0 then
        AddSection(items, "rank", ("MISSING A PREVIOUS RANK (%d)"):format(#rank.rows), SectionTotal(rank))
        AddEntries(items, plan, rank)
    end
    if #quest.rows > 0 then
        AddSection(items, "quest", ("NOT SOLD BY THE TRAINER (%d)"):format(#quest.rows))
        AddEntries(items, plan, quest)
    end
    if #soon.rows > 0 then
        AddSection(items, "soon", ("NEXT TWO LEVELS: %d (%d)"):format(plan.neededLevel, #soon.rows), SectionTotal(soon))
        AddEntries(items, plan, soon)
        AddText(items, T.Paint("muted", ("Needed by level %d: "):format(plan.neededLevel))
            .. Rules.TotalText(plan.neededBy, plan.neededApprox, plan.neededUnpriced, T.Coins))
    end
    if #plan.later > 0 then
        AddSection(items, "later", ("LATER LEVELS (%d)"):format(#plan.later))
        for _, group in ipairs(plan.later) do
            if plan.goldAt == group then AddGoldLine(items, plan) end
            items[#items + 1] = {
                kind = "later", group = group,
                right = SectionTotal(group),
                byThen = T.Paint("muted", ", by then ")
                    .. Rules.TotalText(group.byThen, group.byThenApprox, group.byThenUnpriced, T.Coins),
            }
        end
    end
    if #plan.weapons > 0 then
        AddSection(items, "weapons", ("WEAPON SKILLS (%d)"):format(#plan.weapons))
        for _, weapon in ipairs(plan.weapons) do
            items[#items + 1] = { kind = "weapon", weapon = weapon, right = "At the trainer" }
        end
    end
    local talent, skipped, known = plan.talent, plan.skipped, plan.known
    if #talent.rows > 0 then
        AddSection(items, "talent", ("NEEDS A TALENT (%d)"):format(#talent.rows),
            not state.open.talent and "closed" or nil, true)
        if state.open.talent then AddEntries(items, plan, talent, true) end
    end
    if #skipped.rows > 0 then
        AddSection(items, "skipped", ("SKIPPED (%d)"):format(#skipped.rows), "saves " .. SectionTotal(skipped))
        AddEntries(items, plan, skipped, true)
    end
    if #known.rows > 0 then
        AddSection(items, "known", ("KNOWN (%d)"):format(#known.rows), "about " .. SectionTotal(known) .. " spent", true)
        if state.open.known then AddEntries(items, plan, known, true) end
    end
    return items
end

local function EarlierRank(offer, listed)
    if not offer.needs or listed[offer.needs] then return nil end
    local entry = T.plan and T.plan.entry[offer.needs]
    return entry and entry.state == "quest" and "quest" or "elsewhere"
end

local function TickEvery() T.Learn.SetAll(true) end
local function UntickEvery() T.Learn.SetAll(false) end

local function BuildTrainerItems()
    local items = {}
    local open, waiting = T.Learn.Offers()
    if #open > 0 then
        local anyTicked = T.Learn.AnyTicked()
        local label = anyTicked and "Untick all" or "Tick all"
        AddSection(items, "now", ("TRAIN NOW (%d)"):format(#open), T.Paint("accent", label))
        local header = items[#items]
        header.action = anyTicked and UntickEvery or TickEvery
        header.tip = anyTicked and TIP_UNTICK_ALL or TIP_TICK_ALL
        for _, offer in ipairs(open) do
            local cost = T.Learn.CostText(offer.cost)
            local ticked = T.Learn.IsTicked(offer)
            items[#items + 1] = {
                kind = "offer", offer = offer,
                sub = OfferLine(offer),
                right = (ticked and offer.cost and not T.Learn.InPlan(offer)) and T.Paint("amber", cost) or cost,
            }
        end
    end
    if #waiting > 0 then
        AddSection(items, "waiting", ("WAITING (%d)"):format(#waiting))
        local listed = {}
        for _, offer in ipairs(open) do
            if offer.id then listed[offer.id] = true end
        end
        for _, offer in ipairs(waiting) do
            if offer.id then listed[offer.id] = true end
        end
        for _, offer in ipairs(waiting) do
            local above = offer.needs and C_Spell.GetSpellSubtext(offer.needs)
            local sub = Rules.WaitingText(offer, T.level, T.IsKnown, above, EarlierRank(offer, listed))
            items[#items + 1] = {
                kind = "offer", offer = offer, dim = true, sub = sub, right = T.Learn.CostText(offer.cost),
            }
        end
    end
    local plan = T.plan
    if plan and not T.atProfession and #plan.quest.rows > 0 and Rules.HasClassOffer(open, waiting) then
        AddSection(items, "quest", ("NOT SOLD HERE (%d)"):format(#plan.quest.rows))
        AddEntries(items, plan, plan.quest, true)
    end
    if #items == 0 then AddText(items, T.Paint("muted", "This trainer has nothing to offer.")) end
    return items
end

---------------------------------------------------------------------------------
-- The block above the list
---------------------------------------------------------------------------------
local function LookColor(look)
    if look == "short" then return AMBER_COLOR end
    if look == "unknown" then return UNKNOWN_COLOR end
    return KE.Theme.accent
end

local function DrawBars(plan)
    local block = frame.block
    local bars = Rules.Bars(plan, plan.gold)
    local width = (WIDTH - 2 * PAD) / (#bars > 0 and #bars or 1)
    for index, bar in ipairs(bars) do
        local texture = barTextures[index]
        if not texture then
            texture = block.bars:CreateTexture(nil, "ARTWORK")
            barTextures[index] = texture
        end
        local color = LookColor(bar.look)
        texture:SetColorTexture(color[1], color[2], color[3], 1)
        texture:ClearAllPoints()
        texture:SetPoint("BOTTOMLEFT", block.bars, "BOTTOMLEFT", (index - 1) * width, 0)
        -- An unpriced spell adds no height, and its bar must still be seen.
        local least = bar.look == "unknown" and UNKNOWN_BAR_HEIGHT or 1
        local height = bar.height * BARS_HEIGHT
        texture:SetSize(width > 2 and width - 1 or 1, height > least and height or least)
        texture:Show()
    end
    for index = #bars + 1, #barTextures do barTextures[index]:Hide() end
    block.axisLow:SetText(#bars > 0 and (T.Paint("muted", tostring(bars[1].level))) or "")
    block.axisHigh:SetText(#bars > 0 and (T.Paint("muted", tostring(bars[#bars].level))) or "")
end

local function DrawBlock(plan)
    local block, now, gold = frame.block, plan.now, plan.gold
    block.title:SetText(T.Paint("muted", ("THIS VISIT, %d %s"):format(#now.rows, #now.rows == 1 and "SPELL" or "SPELLS")))
    block.total:SetText(SectionTotal(now))
    local share = now.copper > 0 and min(1, gold / now.copper) or 1
    local look = Rules.GoldLook(now.copper, now.unpriced, gold)
    local short = look == "short"
    local color = LookColor(look)
    block.goldFill:SetColorTexture(color[1], color[2], color[3], 1)
    block.goldFill:SetWidth(share > 0 and share * (WIDTH - 2 * PAD) or 1)
    block.have:SetText("You have " .. T.Coins(gold))
    local mark = (now.approx or now.unpriced > 0) and "~" or ""
    block.spare:SetText(short and (mark .. T.Coins(now.copper - gold) .. " short")
        or (mark .. T.Coins(gold - now.copper) .. " spare"))
    DrawBars(plan)
    local stops = Rules.Milestones(plan, plan.level)
    for index, text in ipairs(block.stops) do
        local stop = stops[index]
        text:SetText(stop and (T.Paint("muted", "To " .. stop.level .. " ")
            .. Rules.TotalText(stop.copper, stop.approx, stop.unpriced, T.Coins)) or "")
    end
    local readTop = STOPS_TOP + #stops * STOP_HEIGHT + 4
    block.readCount:ClearAllPoints()
    block.readCount:SetPoint("TOPLEFT", block, "TOPLEFT", 0, -readTop)
    block:SetHeight(readTop + READ_HEIGHT)
    local read, total = Rules.ReadCount(plan.priced, T.Store().prices)
    block.readCount:SetText(read < total and T.Paint("muted", ("%d of %d prices read"):format(read, total)) or "")
end

---------------------------------------------------------------------------------
-- The footer
---------------------------------------------------------------------------------
local function DrawTrainerFooter()
    local footer = frame.footer
    local picked, leaves, label, canBuy = T.Learn.Footer()
    footer.left:SetWordWrap(false)
    footer.left:SetText(picked)
    footer.right:SetText(leaves)
    local pickedWidth, leavesWidth = TextWidth(footer.left), TextWidth(footer.right)
    -- Side by side only when both fit; otherwise, or with a secret width, the second
    -- text takes the line above.
    local oneLine = pickedWidth and leavesWidth and pickedWidth + FOOTER_TEXT_GAP + leavesWidth <= FOOTER_LINE_WIDTH
    footer.left:ClearAllPoints()
    footer.left:SetPoint("BOTTOMLEFT", footer, "BOTTOMLEFT", PAD, 36)
    footer.right:ClearAllPoints()
    if oneLine then
        footer.right:SetPoint("BOTTOMRIGHT", footer, "BOTTOMRIGHT", -PAD, 36)
    else
        footer.right:SetPoint("BOTTOMLEFT", footer, "BOTTOMLEFT", PAD, 36 + SMALL_LINE_HEIGHT)
    end
    footer.learn.text:SetText(label)
    footer.learn:SetEnabled(canBuy)
    footer.learn:Show()
    footer.update:Hide()
    footer.swapTitle:SetText("")
    footer.swapNames:SetText("")
    footer:SetHeight(oneLine and 56 or 56 + SMALL_LINE_HEIGHT)
end

local function DrawAwayFooter()
    local footer, y = frame.footer, PAD
    footer.learn:Hide()
    footer.right:SetText("")
    T.Route.Ensure()
    local split = SetLeadAndMap(footer.left, FOOTER_LINE_WIDTH, T.Route.Footer())
    footer.left:ClearAllPoints()
    footer.left:SetPoint("BOTTOMLEFT", footer, "BOTTOMLEFT", PAD, y + 4)
    footer.left:SetPoint("RIGHT", footer, "RIGHT", -PAD, 0)
    y = y + 26 + (split and SMALL_LINE_HEIGHT or 0)
    local count = #T.Swap.swaps
    if count > 0 then
        footer.swapNames:SetText(T.Paint("muted", concat(T.Swap.Names(), ", ")
            .. ". Right-click a spell under KNOWN to keep its low rank."))
        footer.swapNames:ClearAllPoints()
        footer.swapNames:SetPoint("BOTTOMLEFT", footer, "BOTTOMLEFT", PAD, y)
        footer.swapNames:SetPoint("BOTTOMRIGHT", footer, "BOTTOMRIGHT", -PAD, y)
        local height = footer.swapNames:GetStringHeight()
        local room = (issecretvalue(height) or not height) and SWAP_NAMES_ROOM or height + 4
        y = y + (room > SWAP_NAMES_ROOM and room or SWAP_NAMES_ROOM)
        footer.swapTitle:SetText(("%d bar %s a lower rank"):format(count, count == 1 and "slot holds" or "slots hold"))
        footer.swapTitle:ClearAllPoints()
        footer.swapTitle:SetPoint("BOTTOMLEFT", footer, "BOTTOMLEFT", PAD, y + 4)
        footer.update:ClearAllPoints()
        footer.update:SetPoint("BOTTOMRIGHT", footer, "BOTTOMRIGHT", -PAD, y)
        footer.update:Show()
        y = y + 26
    else
        footer.update:Hide()
        footer.swapTitle:SetText("")
        footer.swapNames:SetText("")
    end
    footer:SetHeight(y)
end

---------------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------------
local function SetTrainerMode(atTrainer)
    frame.search:SetShown(not atTrainer)
    frame.block:SetShown(not atTrainer)
    frame.scroll:ClearAllPoints()
    if atTrainer then
        frame.scroll:SetPoint("TOPLEFT", frame.header, "BOTTOMLEFT", PAD, -PAD)
    else
        frame.scroll:SetPoint("TOPLEFT", frame.block, "BOTTOMLEFT", 0, -PAD)
    end
    frame.scroll:SetPoint("BOTTOMRIGHT", frame.footer, "TOPRIGHT", -PAD, PAD)
    frame.content:SetWidth(WIDTH - 2 * PAD - SCROLLBAR_ROOM)
end

local function UpdateBookButton()
    if not bookButton then return end
    local count = T.plan and #T.plan.now.rows or 0
    bookButton.text:SetText(("Training (%d)"):format(count))
end

local function Draw()
    if not frame or not frame:IsShown() then return end
    local level = T.level or 0
    frame.subtitle:SetText(T.Paint("muted", ("Level %d %s"):format(level, T.className or "")))
    if state.host == "trainer" then
        SetTrainerMode(true)
        DrawTrainerFooter()
        DrawItems(BuildTrainerItems())
    else
        SetTrainerMode(false)
        DrawAwayFooter()
        local plan = T.plan
        if plan then
            frame.block:Show()
            DrawBlock(plan)
            DrawItems(BuildAwayItems(plan))
        else
            frame.block:Hide()
            local items = {}
            AddText(items, T.Paint("amber", T.loadFailure or "The spell list loads when combat ends."))
            DrawItems(items)
        end
    end
    UpdateBookButton()
end

function Panel.QueueDraw()
    if drawQueued then return end
    drawQueued = true
    C_Timer.After(0, function()
        drawQueued = false
        UpdateBookButton()
        Draw()
    end)
end

function Panel.Repaint()
    if not frame then return end
    local accent = KE.Theme.accent
    frame.accentLine:SetColorTexture(accent[1], accent[2], accent[3], 1)
    Panel.QueueDraw()
end

---------------------------------------------------------------------------------
-- The frame
---------------------------------------------------------------------------------
local function OnPanelEvent(_, event)
    if event == "PLAYER_MONEY" then
        T.module:RebuildPlan()
        if T.atTrainer then T.Read.Queue() end
        Panel.QueueDraw()
    elseif event == "SPELL_DATA_LOAD_RESULT" then
        if dataQueued then return end
        dataQueued = true
        C_Timer.After(DATA_DELAY, function()
            dataQueued = false
            Panel.QueueDraw()
        end)
    else
        Panel.QueueDraw()
    end
end

local function SaveAlonePosition()
    local point, _, relativePoint, x, y = frame:GetPoint(1)
    local position = T.db.Position
    position.AnchorFrom, position.AnchorTo, position.XOffset, position.YOffset = point, relativePoint, x, y
end

local function BuildBlock()
    local block = CreateFrame("Frame", nil, frame)
    block:SetPoint("TOPLEFT", frame.search, "BOTTOMLEFT", 0, -PAD)
    block:SetPoint("TOPRIGHT", frame.search, "BOTTOMRIGHT", 0, -PAD)
    block:SetHeight(BLOCK_HEIGHT)
    block.title = MakeText(block, "small")
    block.title:SetPoint("TOPLEFT", block, "TOPLEFT", 0, 0)
    block.total = MakeText(block, "small")
    block.total:SetPoint("TOPRIGHT", block, "TOPRIGHT", 0, 0)
    local goldBack = block:CreateTexture(nil, "BACKGROUND")
    goldBack:SetPoint("TOPLEFT", block, "TOPLEFT", 0, -16)
    goldBack:SetPoint("TOPRIGHT", block, "TOPRIGHT", 0, -16)
    goldBack:SetHeight(6)
    goldBack:SetColorTexture(FIELD_COLOR[1], FIELD_COLOR[2], FIELD_COLOR[3], 1)
    block.goldFill = block:CreateTexture(nil, "ARTWORK")
    block.goldFill:SetPoint("TOPLEFT", goldBack, "TOPLEFT", 0, 0)
    block.goldFill:SetHeight(6)
    block.have = MakeText(block, "small")
    block.have:SetPoint("TOPLEFT", block, "TOPLEFT", 0, -26)
    block.spare = MakeText(block, "small")
    block.spare:SetPoint("TOPRIGHT", block, "TOPRIGHT", 0, -26)
    block.bars = CreateFrame("Frame", nil, block)
    block.bars:SetPoint("TOPLEFT", block, "TOPLEFT", 0, -44)
    block.bars:SetPoint("TOPRIGHT", block, "TOPRIGHT", 0, -44)
    block.bars:SetHeight(BARS_HEIGHT)
    block.axisLow = MakeText(block, "small")
    block.axisLow:SetPoint("TOPLEFT", block.bars, "BOTTOMLEFT", 0, -2)
    block.axisHigh = MakeText(block, "small")
    block.axisHigh:SetPoint("TOPRIGHT", block.bars, "BOTTOMRIGHT", 0, -2)
    block.stops = {}
    for index = 1, MAX_STOPS do
        local top = -(STOPS_TOP + (index - 1) * STOP_HEIGHT)
        local stop = MakeText(block, "small")
        stop:SetPoint("TOPLEFT", block, "TOPLEFT", 0, top)
        stop:SetPoint("TOPRIGHT", block, "TOPRIGHT", 0, top)
        block.stops[index] = stop
    end
    block.readCount = MakeText(block, "small")
    frame.block = block
end

local function BuildFooter()
    local footer = CreateFrame("Frame", nil, frame)
    footer:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    footer:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    footer:SetHeight(PAD)
    footer.left = MakeText(footer, "small")
    footer.right = MakeText(footer, "small")
    footer.swapTitle = MakeText(footer, "small")
    footer.swapNames = MakeText(footer, "small")
    footer.swapNames:SetWordWrap(true)
    footer.update = Panel.MakeButton(footer, "Update Bars", 90, 22, function() T.Swap.Update() end)
    footer.learn = Panel.MakeButton(footer, "", WIDTH - 2 * PAD, 26, function() T.Learn.Buy() end)
    footer.learn:SetPoint("BOTTOM", footer, "BOTTOM", 0, PAD)
    frame.footer = footer
end

local function BuildScroll()
    local scroll = CreateFrame("ScrollFrame", nil, frame)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(WIDTH - 2 * PAD - SCROLLBAR_ROOM, 1)
    scroll:SetScrollChild(content)
    frame.scroll, frame.content = scroll, content
    if KE.GUI and KE.GUI.CreateScrollbar then
        frame.scrollbar = KE.GUI.CreateScrollbar(scroll, { width = 6, scrollStep = ROW_HEIGHT, anchorToScrollFrame = true })
    end
end

local function Build()
    if frame then return end
    frame = CreateFrame("Frame", "KitnEssentialsTrainingPanel", UIParent, "BackdropTemplate")
    frame:SetWidth(WIDTH)
    frame:SetHeight(ALONE_HEIGHT)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    Backdrop(frame, WINDOW_COLOR)
    frame:Hide()

    local header = CreateFrame("Frame", nil, frame)
    header:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    header:SetHeight(HEADER_HEIGHT)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function()
        if state.host == "alone" and not anchoredTo then frame:StartMoving() end
    end)
    header:SetScript("OnDragStop", function()
        if state.host == "alone" and not anchoredTo then
            frame:StopMovingOrSizing()
            SaveAlonePosition()
        end
    end)
    frame.header = header
    local title = MakeText(header, "normal")
    title:SetPoint("LEFT", header, "LEFT", PAD, 0)
    title:SetText("What's Training")
    frame.subtitle = MakeText(header, "small")
    frame.subtitle:SetPoint("LEFT", title, "RIGHT", 8, 0)
    local close = Panel.MakeButton(header, CLOSE_GLYPH, 20, 20, function() Panel.Close() end)
    close:SetPoint("RIGHT", header, "RIGHT", -6, 0)
    frame.accentLine = header:CreateTexture(nil, "ARTWORK")
    frame.accentLine:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
    frame.accentLine:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0)
    frame.accentLine:SetHeight(1)

    local search = CreateFrame("EditBox", nil, frame, "BackdropTemplate")
    search:SetPoint("TOPLEFT", header, "BOTTOMLEFT", PAD, -4)
    search:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", -PAD, -4)
    search:SetHeight(SEARCH_HEIGHT)
    search:SetAutoFocus(false)
    search:SetTextInsets(6, 6, 0, 0)
    KE:ApplyThemeFont(search, "small")
    Backdrop(search, FIELD_COLOR)
    local placeholder = MakeText(search, "small")
    placeholder:SetPoint("LEFT", search, "LEFT", 6, 0)
    placeholder:SetText(T.Paint("muted", "Search spells"))
    search:SetScript("OnEscapePressed", search.ClearFocus)
    search:SetScript("OnEnterPressed", search.ClearFocus)
    search:SetScript("OnTextChanged", function(self)
        state.query = self:GetText() or ""
        placeholder:SetShown(state.query == "")
        Panel.QueueDraw()
    end)
    frame.search = search

    BuildBlock()
    BuildFooter()
    BuildScroll()

    frame:SetScript("OnEvent", OnPanelEvent)
    frame:SetScript("OnShow", function(self)
        self:RegisterEvent("PLAYER_MONEY")
        self:RegisterEvent("SPELL_DATA_LOAD_RESULT")
        self:RegisterEvent("ZONE_CHANGED_NEW_AREA")
        -- These events are off while hidden, so the plan's gold may be old.
        T.module:RebuildPlan()
        T.Swap.Scan()
    end)
    frame:SetScript("OnHide", function(self) self:UnregisterAllEvents() end)
    Panel.Repaint()
end

---------------------------------------------------------------------------------
-- Hosts
---------------------------------------------------------------------------------
local function HostNow()
    return Rules.PanelHost({
        atTrainer = T.atTrainer, gamepad = T.gamepad, trainerWindow = _G.ClassTrainerFrame ~= nil,
        closed = state.closed, bookOpen = state.bookOpen, openWithBook = T.db.OpenWithBook,
        alone = state.alone,
    })
end

-- The whole window, where state.bookOpen is its spell tab. Unhooked or not visible, its
-- OnHide would never come, and a closing it held could not end.
local function BookWindowOpen()
    local window = _G.PlayerSpellsFrame
    if not (bookHooked and window) then return false end
    local visible = window:IsVisible()
    return not issecretvalue(visible) and visible == true
end

local function WaitForCombat()
    placeAfterCombat = true
    T.module:RegisterEvent("PLAYER_REGEN_ENABLED")
end

local function PlaceBeside(target)
    local left, right = target:GetLeft(), target:GetRight()
    local targetScale, baseScale = target:GetEffectiveScale(), UIParent:GetEffectiveScale()
    local screen = UIParent:GetWidth()
    -- A window's anchors or scale can read secret, and no test of them is then allowed.
    if issecretvalue(left) or issecretvalue(right) or issecretvalue(targetScale)
        or issecretvalue(baseScale) or issecretvalue(screen) then
        return false
    end
    if not (left and right) then return false end
    local scale = targetScale / baseScale
    left, right = left * scale, right * scale
    local side = Rules.PanelSide(left, screen - right, NEED)
    frame:ClearAllPoints()
    if side == "right" then
        frame:SetPoint("TOPLEFT", target, "TOPRIGHT", GAP, 0)
        frame:SetPoint("BOTTOMLEFT", target, "BOTTOMRIGHT", GAP, 0)
    elseif side == "left" then
        frame:SetPoint("TOPRIGHT", target, "TOPLEFT", -GAP, 0)
        frame:SetPoint("BOTTOMRIGHT", target, "BOTTOMLEFT", -GAP, 0)
    else
        local center = side == "pinRight" and screen - WIDTH / 2 or WIDTH / 2
        local offset = center - (left + right) / 2
        frame:SetPoint("TOP", target, "TOP", offset, -PIN_INSET * scale)
        frame:SetPoint("BOTTOM", target, "BOTTOM", offset, 0)
    end
    return true
end

local function PlaceAlone()
    frame:ClearAllPoints()
    frame:SetHeight(ALONE_HEIGHT)
    KE:ApplyFramePosition(frame, T.db.Position, { anchorFrameType = "UIPARENT", Strata = "DIALOG" }, false)
end

local function Place(host)
    local target
    if host == "trainer" then
        target = _G.ClassTrainerFrame
    elseif host == "book" then
        target = _G.PlayerSpellsFrame
    end
    local book = _G.PlayerSpellsFrame
    local step = Rules.PlaceStep(host, InCombatLockdown(), book ~= nil and anchoredTo == book)
    if step ~= "place" then WaitForCombat() end
    if step == "keep" then return end
    if step == "place" and target and PlaceBeside(target) then
        anchoredTo = target
        return
    end
    anchoredTo = nil
    PlaceAlone()
end

function Panel.Refresh()
    if not T.active then return end
    local host = HostNow()
    if not host then
        if frame then frame:Hide() end
        state.host = nil
        return
    end
    Build()
    state.host = host
    Place(host)
    frame:Show()
    Panel.QueueDraw()
end

function Panel.Open()
    state.alone = true
    state.closed = false
    Panel.Refresh()
end

function Panel.Close()
    state.closed = Rules.StaysClosed(true, T.atTrainer, BookWindowOpen())
    state.alone = false
    Panel.Refresh()
end

function Panel.Toggle()
    if frame and frame:IsShown() then
        Panel.Close()
    else
        Panel.Open()
    end
end

function Panel.IsShown()
    return frame ~= nil and frame:IsShown()
end

function Panel.HideAll()
    state.alone = false
    state.closed = false
    state.host = nil
    if frame then frame:Hide() end
    if bookButton then bookButton:Hide() end
end

function Panel.OnTrainerShow()
    state.closed = false
    Panel.Refresh()
end

function Panel.OnTrainerClosed(staysOpen)
    local closed, stayAlone = Rules.AfterTrainer(state.closed, staysOpen, BookWindowOpen())
    state.closed = closed
    if stayAlone then state.alone = true end
    Panel.Refresh()
end

---------------------------------------------------------------------------------
-- The book and the trainer window
---------------------------------------------------------------------------------
local function ShowBookButton(book)
    if not bookButton then
        bookButton = Panel.MakeButton(UIParent, "Training (0)", BOOK_BUTTON_WIDTH, BOOK_BUTTON_HEIGHT, function()
            T.db.OpenWithBook = Rules.BookButtonSetting(Panel.IsShown(), T.db.OpenWithBook)
            state.closed = false
            Panel.Refresh()
        end)
        bookButton:SetFrameStrata("DIALOG")
    end
    if not bookAnchored then
        if InCombatLockdown() then
            WaitForCombat()
            return
        end
        bookButton:SetPoint("BOTTOMLEFT", book, "BOTTOMLEFT", 22, 2)
        bookAnchored = true
    end
    UpdateBookButton()
    bookButton:Show()
end

local function OnBookShown()
    if not T.active then return end
    local book = _G.PlayerSpellsFrame
    if not book then return end
    state.bookOpen = true
    ShowBookButton(book)
    C_Timer.After(0, Panel.Refresh)
end

local function OnBookHidden()
    state.bookOpen = false
    if not T.active then return end
    if bookButton then bookButton:Hide() end
    C_Timer.After(0, Panel.Refresh)
end

function Panel.AfterCombat()
    if not placeAfterCombat then return end
    placeAfterCombat = false
    local book = _G.PlayerSpellsFrame
    if state.bookOpen and book then ShowBookButton(book) end
    Panel.Refresh()
end

-- Each installer can run from a load callback after the module turned off.
function Panel.InstallBook()
    if not T.active or T.gamepad then return end
    local host = _G.PlayerSpellsFrame
    local book = host and host.SpellBookFrame
    if not book then return end
    if not bookHooked then
        bookHooked = true
        book:HookScript("OnShow", OnBookShown)
        book:HookScript("OnHide", OnBookHidden)
        -- The book's frame also hides at a tab change, which is not a new opening.
        host:HookScript("OnHide", function()
            if T.active then state.closed = Rules.StaysClosed(state.closed, T.atTrainer, false) end
        end)
        host:HookScript("OnSizeChanged", function()
            if T.active and state.bookOpen then C_Timer.After(0, Panel.Refresh) end
        end)
    end
    if book:IsVisible() then OnBookShown() end
end

function Panel.InstallTrainer()
    if not T.active or T.gamepad then return end
    local trainer = _G.ClassTrainerFrame
    if not trainer or trainerHooked then return end
    trainerHooked = true
    trainer:HookScript("OnShow", function()
        if T.active then C_Timer.After(0, Panel.Refresh) end
    end)
    trainer:HookScript("OnHide", function()
        if T.active then C_Timer.After(0, Panel.Refresh) end
    end)
end
