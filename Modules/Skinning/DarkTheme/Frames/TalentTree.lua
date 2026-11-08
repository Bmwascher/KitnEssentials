local KE = select(2, ...)
local S = KE.Skins

local _G = _G
local ipairs = ipairs
local hooksecurefunc = hooksecurefunc

-- State colors carry game meaning, so they stay out of the themed palette.
local STATE_COLORS = {
    gold  = { 1, 0.82, 0 },
    green = { 0.25, 1, 0.25 },
    gray  = { 0.5, 0.5, 0.5 },
    red   = { 1, 0.2, 0.2 },
}

local EDGE_COLOR_KEYS = {
    ["talents-arrow-line-yellow"] = "gold",
    ["talents-arrow-line-gray"]   = "gray",
    ["talents-arrow-line-locked"] = "gray",
    ["talents-arrow-line-red"]    = "red",
}

-- Same grouping as the client's state-border rule, which draws every
-- non-disabled state other than maxed with the spendable art.
function S._TalentStateColorKey(visualState, states)
    if visualState == nil or not states then return nil end
    if visualState == states.RefundInvalid or visualState == states.DisplayError then
        return "red"
    elseif visualState == states.Maxed then
        return "gold"
    elseif visualState == states.Gated or visualState == states.Disabled
        or visualState == states.Locked then
        return "gray"
    elseif visualState == states.Normal or visualState == states.Selectable
        or visualState == states.Invisible then
        return "green"
    end
    return nil
end

-- Desaturated first so the tint replaces the art's own hue. No key restores
-- the art, so an unknown state never keeps a stale color.
local function Paint(tex, key)
    if not tex then return end
    local c = key and STATE_COLORS[key]
    if c then
        tex:SetDesaturated(true)
        tex:SetVertexColor(c[1], c[2], c[3])
    else
        tex:SetDesaturated(false)
        tex:SetVertexColor(1, 1, 1)
    end
end

local function RecolorNode(button, _, visualState)
    local util = _G.TalentButtonUtil
    local key = S._TalentStateColorKey(visualState, util and util.BaseVisualState)
    Paint(button.StateBorder, key)
    Paint(button.StateBorderHover, key)
end

local function SkinNode(button)
    if not (button and button.SetBorderAtlas and button.StateBorder) then return end
    local d = S.data(button)
    if not d.talentNode then
        d.talentNode = true
        hooksecurefunc(button, "SetBorderAtlas", RecolorNode)
    end
    -- The first state is drawn before the hook exists.
    RecolorNode(button, nil, button.GetVisualState and button:GetVisualState())
end

local function RecolorEdge(_, edge)
    local line = edge and edge.Line
    if not (line and line.GetAtlas) then return end
    local key = EDGE_COLOR_KEYS[line:GetAtlas()]
    Paint(line, key)
    Paint(edge.ArrowHead, key)
end

local function OnButtonAcquired(_, button)
    SkinNode(button)
end

local function SkinChoices(choice)
    local frames = choice.selectionFrameArray
    if not frames then return end
    for _, f in ipairs(frames) do SkinNode(f) end
end

local callbackOwner = {}

function S.TalentTree(talentFrame)
    if not talentFrame then return end
    local d = S.data(talentFrame)
    if d.talentTree then return end
    local event = talentFrame.Event and talentFrame.Event.TalentButtonAcquired
    if not (event and talentFrame.RegisterCallback and talentFrame.UpdateEdgeFrameLevel) then return end
    d.talentTree = true

    talentFrame:RegisterCallback(event, OnButtonAcquired, callbackOwner)
    -- Every arrow state update ends in this call, with the arrow as its argument.
    hooksecurefunc(talentFrame, "UpdateEdgeFrameLevel", RecolorEdge)
    -- Flyout options come from a display pool that fires no acquire callback.
    local choice = talentFrame.SelectionChoiceFrame
    if choice and choice.SetSelectionOptions then
        hooksecurefunc(choice, "SetSelectionOptions", SkinChoices)
        SkinChoices(choice)
    end

    if talentFrame.EnumerateAllTalentButtons then
        for button in talentFrame:EnumerateAllTalentButtons() do SkinNode(button) end
    end
    local edges = talentFrame.edgePool
    if edges and edges.EnumerateActive then
        for edge in edges:EnumerateActive() do RecolorEdge(talentFrame, edge) end
    end
end

local function IconButtonEnter(button)
    local plate = S.GetBackdrop(button)
    if plate and button:IsEnabled() then
        local b = S.palette.brand
        plate:SetBackdropBorderColor(b[1], b[2], b[3], 1)
    end
end

local function IconButtonLeave(button)
    local plate = S.GetBackdrop(button)
    if plate then
        local c = S.borderColor
        plate:SetBackdropBorderColor(c[1], c[2], c[3], c[4])
    end
end

function S.TalentIconButton(button)
    if not (button and button.Icon) then return end
    local d = S.data(button)
    if d.talentIconButton then return end
    d.talentIconButton = true

    local plate = S.Backdrop(button)
    if plate then
        local c = S.palette.control
        plate:SetBackdropColor(c[1], c[2], c[3], c[4])
    end
    local hl = button.GetHighlightTexture and button:GetHighlightTexture()
    if hl then hl:SetAlpha(0) end
    button:HookScript("OnEnter", IconButtonEnter)
    button:HookScript("OnLeave", IconButtonLeave)
end
