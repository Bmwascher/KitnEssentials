-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-DispelTypeColorsCard.lua                            ║
-- ║  Purpose: Shared "Dispel Type Colors" card builder.      ║
-- ║  The per-type dispel color palette lives on the          ║
-- ║  AuraDebuffs profile (db.DispelColors) and is consumed   ║
-- ║  by BOTH the Aura Debuffs icon highlight AND the Dispel  ║
-- ║  Glow border. This card is rendered on the Aura Debuffs  ║
-- ║  page AND cross-linked onto the Healer Utilities > Dispel║
-- ║  Glow page; edits from either refresh both consumers.    ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

-- Default colors. Also used by the Reset button to wipe a user override
-- back to default. Must match the backend DISPEL_DEFAULTS in
-- Modules/Combat/AuraDebuffs.lua so a reset shows the same color the
-- curve resolves to.
--   None    #CC0000   Magic   #0081FF   Curse   #9F06E4
--   Disease #F16A09   Poison  #7BC700   Bleed   #B8000F
--   Enrage  #F35FF5
local DISPEL_DEFAULTS = {
    None    = { 0.800, 0.000, 0.000, 1 },  -- #CC0000
    Magic   = { 0.000, 0.506, 1.000, 1 },  -- #0081FF
    Curse   = { 0.624, 0.024, 0.894, 1 },  -- #9F06E4
    Disease = { 0.945, 0.416, 0.035, 1 },  -- #F16A09
    Poison  = { 0.482, 0.780, 0.000, 1 },  -- #7BC700
    Bleed   = { 0.722, 0.000, 0.059, 1 },  -- #B8000F
    Enrage  = { 0.953, 0.373, 0.961, 1 },  -- #F35FF5
}
-- 4x2 grid order: None | Magic | Curse | Disease | Poison | Bleed | Enrage
local DISPEL_TYPES = { "None", "Magic", "Curse", "Disease", "Poison", "Bleed", "Enrage" }

-- Refresh every consumer of the dispel palette after an edit. AuraDebuffs
-- rebuilds its color curve + repaints icons; DispelGlow re-evaluates each
-- managed frame's border. Both calls are no-ops when the module is absent
-- or disabled, so this is safe to fire from either page.
local function ApplyPalette()
    if not KitnEssentials then return end
    local ad = KitnEssentials:GetModule("AuraDebuffs", true)
    if ad and ad.ApplySettings then ad:ApplySettings() end
    local dg = KitnEssentials:GetModule("DispelGlow", true)
    if dg and dg.ApplySettings then dg:ApplySettings() end
end

-- config = {
--   db         : AuraDebuffs profile table (KE.db.profile.AuraDebuffs) -- holds DispelColors
--   manager    : WidgetStateManager for the host page (required)
--   stateGroup : manager group to register widgets under (default "all")
-- }
-- Returns: newYOffset
function GUIFrame:CreateDispelTypeColorsCard(scrollChild, yOffset, config)
    local db         = config.db
    local manager    = config.manager
    local stateGroup = config.stateGroup or "all"

    if not db.DispelColors then db.DispelColors = {} end
    local dispelColors = db.DispelColors

    ----------------------------------------------------------------
    -- Card: Dispel Type Colors
    --
    -- 4x2 grid (last cell empty), per-type ColorPicker + Reset button with
    -- a separator between rows. Always editable regardless of the consuming
    -- module's mode — color choices persist and take effect when active.
    ----------------------------------------------------------------
    local card = GUIFrame:CreateCard(scrollChild, "Dispel Type Colors", yOffset)
    manager:Register(card, stateGroup)

    -- Local table of per-type ColorPicker widget refs so Reset callbacks can
    -- find and update the right picker by type name.
    local dispelPickers = {}

    local function CreateDispelCell(row, dtype, isRight)
        local picker = GUIFrame:CreateColorPicker(row, dtype, {
            color    = dispelColors[dtype] or DISPEL_DEFAULTS[dtype] or { 1, 1, 1, 1 },
            callback = function(r, g, b, a)
                dispelColors[dtype] = { r, g, b, a }
                ApplyPalette()
            end,
        })
        row:AddWidget(picker, 0.35)
        manager:Register(picker, stateGroup)
        dispelPickers[dtype] = picker

        local resetBtn = GUIFrame:CreateButton(row, "Reset", {
            height   = 24,
            tooltip  = "Reset " .. dtype .. " to default (" ..
                       string.format("#%02X%02X%02X",
                           DISPEL_DEFAULTS[dtype][1] * 255 + 0.5,
                           DISPEL_DEFAULTS[dtype][2] * 255 + 0.5,
                           DISPEL_DEFAULTS[dtype][3] * 255 + 0.5) .. ").",
            callback = function()
                local d = DISPEL_DEFAULTS[dtype]
                dispelColors[dtype] = nil  -- drop user override
                if dispelPickers[dtype] and dispelPickers[dtype].SetColor then
                    dispelPickers[dtype]:SetColor(d[1], d[2], d[3], d[4] or 1)
                end
                ApplyPalette()
            end,
        })
        -- Match the 48x24 ColorPicker swatch dimensions: button height = 24
        -- and top anchored at y=-14 so it lines up edge-to-edge with the
        -- swatch. Right-cell button gets a small leftward nudge so its right
        -- edge lines up with the separator-bar's right edge.
        local btnXOffset = isRight and -3 or 0
        row:AddWidget(resetBtn, 0.15, nil, btnXOffset, -14)
        manager:Register(resetBtn, stateGroup)
    end

    -- Lay out in 4 rows of 2 cells each. Separator between rows.
    local numTypes = #DISPEL_TYPES
    local pairIdx = 1
    while pairIdx <= numTypes do
        local typeA   = DISPEL_TYPES[pairIdx]
        local typeB   = DISPEL_TYPES[pairIdx + 1]
        local isLast  = (pairIdx + 2 > numTypes)
        local rowH    = isLast and Theme.rowHeightLast or Theme.rowHeight

        local dtRow = GUIFrame:CreateRow(card.content, rowH)
        CreateDispelCell(dtRow, typeA, false)
        if typeB then
            CreateDispelCell(dtRow, typeB, true)
        end
        card:AddRow(dtRow, rowH, isLast and 0 or nil)

        if not isLast then
            local sepRow = GUIFrame:CreateRow(card.content, Theme.rowHeightSeparator)
            local sep = GUIFrame:CreateSeparator(sepRow)
            sepRow:AddWidget(sep, 1)
            manager:Register(sep, stateGroup)
            card:AddRow(sepRow, Theme.rowHeightSeparator)
        end

        pairIdx = pairIdx + 2
    end

    return card:GetNextOffset()
end
