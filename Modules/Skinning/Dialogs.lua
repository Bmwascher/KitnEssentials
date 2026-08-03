local KE = select(2, ...)
local S = KE.Skins
local _G = _G
local ipairs = ipairs
local hooksecurefunc = hooksecurefunc

local function HandleBg(bg)
    if not bg then return end
    if bg.IsObjectType and bg:IsObjectType("Texture") then
        bg:SetAlpha(0)
    elseif bg.GetObjectType then
        S.StripTextures(bg)
    end
end

local function StripNineSlicePieces(nineSlice)
    for _, region in ipairs({ nineSlice:GetRegions() }) do
        if region.IsObjectType and region:IsObjectType("Texture") then
            region:SetAlpha(0)
        end
    end

    if nineSlice.pieces then
        for _, piece in ipairs(nineSlice.pieces) do
            if piece.SetAlpha then piece:SetAlpha(0) end
        end
    end
end

local function SkinDialogBorder(nineSlice)
    if not nineSlice or not nineSlice.GetRegions then return end
    StripNineSlicePieces(nineSlice)

    local owner = nineSlice
    local parent = nineSlice:GetParent()
    if parent and parent.NineSlice == nineSlice then owner = parent end

    HandleBg(nineSlice.Bg)
    if owner ~= nineSlice then HandleBg(owner.Bg) end

    if owner.PortraitContainer then owner.PortraitContainer:SetAlpha(0) end

    local function SweepButtons()
        local host = owner ~= nineSlice and owner or parent
        if host and host ~= _G.UIParent then
            for _, child in ipairs({ host:GetChildren() }) do
                if child ~= nineSlice and child:IsObjectType("Button")
                    and ((child.GetFontString and child:GetFontString()) or child.Text) then
                    S.Button(child)
                end
            end
        end
    end

    local d = S.data(owner)
    if not d.aeDialog then
        d.aeDialog = true
        S.Backdrop(owner)
        SweepButtons()

        if _G.C_Timer then
            _G.C_Timer.After(0, SweepButtons)
        end
        owner:HookScript("OnShow", SweepButtons)
    else
        local bd = S.GetBackdrop(owner)
        if bd then bd:Show() end
    end
end

local function Skin()
    if S.skinIndex.__dialogLayoutHook then return end
    local NSU = _G.NineSliceUtil
    if not (NSU and NSU.ApplyLayout and NSU.GetLayout) then return end
    S.skinIndex.__dialogLayoutHook = true

    local dialogLayout = NSU.GetLayout("Dialog")

    local heldBagLayout = NSU.GetLayout("HeldBagLayout")
    hooksecurefunc(NSU, "ApplyLayout", function(container, userLayout)
        if userLayout == dialogLayout then
            SkinDialogBorder(container)
        elseif userLayout == heldBagLayout then
            local top = container:GetParent() or container
            if (top.GetFrameStrata and top:GetFrameStrata() == "DIALOG")
                or (container.GetFrameStrata and container:GetFrameStrata() == "DIALOG") then
                SkinDialogBorder(container)
            end
        end
    end)
end

S:RegisterEarly(Skin, "Dialogs")
