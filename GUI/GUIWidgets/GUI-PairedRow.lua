-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-PairedRow.lua                                       ║
-- ║  Purpose: A row holding a master checkbox and one        ║
-- ║           dependent control that exists only while the   ║
-- ║           master is on, with a chevron between them.     ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

local math_pi = math.pi

local CHEVRON = "Interface\\AddOns\\KitnEssentials\\Media\\GUITextures\\collapse.png"
local CHEVRON_SIZE = 18
local CHEVRON_GAP = -4
local CHEVRON_Y = -6

-- The one home of the clear rule. A hidden checkbox dependent is reset, so a
-- setting the player cannot see can never still be acting. A dropdown has no
-- off state and keeps its value; neither dropdown dependent can act while its
-- master is off, so there is nothing to make safe.
function GUIFrame.ResolvePairedDependent(masterOn, clearable)
    if masterOn then return true, false end
    return false, clearable == true
end

function GUIFrame:CreatePairedRow(card, config)
    config = config or {}
    local masterCfg = config.master or {}
    local depCfg = config.dependent or {}
    local height = config.height or Theme.rowHeight
    local group = config.group or "all"
    local clearable = depCfg.clear ~= nil

    -- Read live, never captured. A captured boolean belongs to one build of
    -- the row, and every paired master on the page rebuilds it; a dependent's
    -- deferred callback can outlive its own build and then write against a
    -- master that has since gone off.
    local function MasterOn()
        return masterCfg.get() and true or false
    end

    local show, clearNow = GUIFrame.ResolvePairedDependent(MasterOn(), clearable)

    -- Runs at build too: a saved profile can already hold a dependent switched
    -- on beneath a master that is off, and it would otherwise keep acting unseen.
    if clearNow then depCfg.clear() end

    local row = GUIFrame:CreateRow(card.content, height)

    local master = GUIFrame:CreateCheckbox(row, masterCfg.label, {
        value = MasterOn(),
        tooltip = masterCfg.tooltip,
        callback = function(checked)
            -- The clear runs BEFORE the caller's callback, because that
            -- callback is where the module's apply chain runs: clearing after
            -- it would let the apply see a dependent that is about to vanish
            -- and act on it until the next apply.
            local _, shouldClear = GUIFrame.ResolvePairedDependent(checked and true or false, clearable)
            if shouldClear then depCfg.clear() end
            if masterCfg.callback then masterCfg.callback(checked) end
            GUIFrame:RefreshContent()
        end,
    })
    row:AddWidget(master, 0.5)

    local function DependentWrite(value)
        if not GUIFrame.ResolvePairedDependent(MasterOn(), clearable) then return end
        if depCfg.callback then depCfg.callback(value) end
    end

    local dependent
    if show then
        if depCfg.kind == "dropdown" then
            dependent = GUIFrame:CreateDropdown(row, depCfg.label, {
                options = depCfg.options,
                value = depCfg.value,
                tooltip = depCfg.tooltip,
                callback = DependentWrite,
            })
        else
            dependent = GUIFrame:CreateCheckbox(row, depCfg.label, {
                value = depCfg.value and true or false,
                tooltip = depCfg.tooltip,
                callback = DependentWrite,
            })
        end
        row:AddWidget(dependent, 0.5)

        -- Anchored to the dependent rather than to the row, so the row's
        -- OnSizeChanged reflow carries the chevron at every window width.
        -- A quarter turn points the shipped down-arrow right; arrow glyphs
        -- render as empty boxes in Expressway, so this must be a texture.
        local arrow = row:CreateTexture(nil, "OVERLAY")
        arrow:SetTexture(CHEVRON)
        arrow:SetVertexColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
        arrow:SetSize(CHEVRON_SIZE, CHEVRON_SIZE)
        arrow:SetPoint("RIGHT", dependent, "LEFT", CHEVRON_GAP, CHEVRON_Y)
        arrow:SetRotation(math_pi / 2)
        arrow:SetTexelSnappingBias(0)
        arrow:SetSnapToPixelGrid(false)
        row.chevron = arrow
    end

    card:AddRow(row, height, config.spacing)

    if config.manager then
        config.manager:Register(master, group)
        if dependent then config.manager:Register(dependent, group) end
    end

    return row, master, dependent
end
