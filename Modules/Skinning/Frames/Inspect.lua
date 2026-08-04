local KE = select(2, ...)
local S = KE.Skins
local _G = _G
local next = next
local hooksecurefunc = hooksecurefunc -- luacheck: ignore 211/hooksecurefunc

local function DressPvpTalents(slot)
    if not slot then return end
    local icon = slot.Texture
    S.StripTextures(slot)
    if slot.Border then slot.Border:Hide() end
    if icon then
        S.Icon(icon, true)
        local bd = S.GetBackdrop(icon)
        if bd then bd:SetFrameLevel(2) end
    end
end

local function Skin()
    local frame = _G.InspectFrame
    if not frame then return end
    S.Frame(frame)
    if _G.InspectPaperDollFrame and _G.InspectPaperDollFrame.ViewButton then
        S.Button(_G.InspectPaperDollFrame.ViewButton)
    end
    if _G.InspectPaperDollItemsFrame and _G.InspectPaperDollItemsFrame.InspectTalents then
        S.Button(_G.InspectPaperDollItemsFrame.InspectTalents)
        _G.InspectPaperDollItemsFrame.InspectTalents:ClearAllPoints()
        _G.InspectPaperDollItemsFrame.InspectTalents:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", 0, -1)
    end

    local pvp = _G.InspectPVPFrame
    if pvp then
        if pvp.SmallWreath then
            pvp.SmallWreath:ClearAllPoints()
            pvp.SmallWreath:SetPoint("TOPLEFT", -2, -25)
        end
        for i = 1, 3 do DressPvpTalents(pvp["TalentSlot" .. i]) end
        if pvp.BG then S.KillTexture(pvp.BG) end
    end

    S.Tabs("InspectFrameTab", 5)

    local model = _G.InspectModelFrame
    if model then
        S.StripTextures(model)
        -- no S.Backdrop here. With the background scene art
        -- killed the backdrop rendered as an opaque black
        -- box; the Character pane's model scene is strip-only and
        -- transparent, so this now matches it.
        for _, name in next, { "TopLeft", "TopRight", "Top", "Left", "Right",
            "BottomLeft", "BottomRight", "Bottom", "Bottom2" } do
            local border = _G["InspectModelFrameBorder" .. name]
            if border then S.KillTexture(border) end
        end
        -- background scene art killed to match the Character
        -- pane (its CharacterModelScene is StripTextures'd by the skin).
        -- The dark S.Backdrop above shows through instead. The old
        -- desaturation-preservation block is gone with the art.
        if model.BackgroundOverlay then S.KillTexture(model.BackgroundOverlay) end
        for _, corner in next, { "TopLeft", "TopRight", "BotLeft", "BotRight" } do
            local bg = _G["InspectModelFrameBackground" .. corner]
            if bg then S.KillTexture(bg) end
        end
    end

    if _G.InspectGuildFrameBG then S.KillTexture(_G.InspectGuildFrameBG) end

    if _G.InspectPaperDollItemsFrame then
        for _, slot in next, { _G.InspectPaperDollItemsFrame:GetChildren() } do
            if (slot:IsObjectType("Button") or slot:IsObjectType("ItemButton")) and slot.icon then
                S.Icon(slot.icon, true)
                slot.icon:SetPoint("TOPLEFT", slot, "TOPLEFT", 1, -1)
                slot.icon:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", -1, 1)
                S.StripTextures(slot)
                S.Hover(slot, slot.icon)
                if slot.IconBorder then
                    S.IconBorder(slot.IconBorder, S.GetBackdrop(slot.icon))
                end
            end
        end
    end
end

S:Register("Blizzard_InspectUI", Skin, "Inspect")
