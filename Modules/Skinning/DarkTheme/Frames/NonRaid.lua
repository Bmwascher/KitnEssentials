local KE = select(2, ...)
local S = KE.Skins
local _G = _G
local ipairs = ipairs

local function Skin()
    local frame = _G.RaidInfoFrame
    if not frame or S.data(frame).raidInfoSkinned then return end
    S.data(frame).raidInfoSkinned = true

    S.StripTextures(frame)
    if _G.RaidInfoInstanceLabel then S.StripTextures(_G.RaidInfoInstanceLabel) end
    if _G.RaidInfoIDLabel then S.StripTextures(_G.RaidInfoIDLabel) end

    if frame.NineSlice and frame.NineSlice.SetAlpha then frame.NineSlice:SetAlpha(0) end
    if frame.Border and frame.Border.SetAlpha then frame.Border:SetAlpha(0) end
    for _, child in ipairs({ frame:GetChildren() }) do
        if not child:GetName() and child.Center
            and child.GetNumChildren and child:GetNumChildren() == 0 then
            child:SetAlpha(0)
        end
    end
    S.Backdrop(frame)

    if frame.Header then
        S.StripTextures(frame.Header)
        if frame.Header.CenterBG then frame.Header.CenterBG:SetAlpha(0) end
    end

    for _, name in ipairs({
        "RaidInfoScrollFrameScrollBarBG",
        "RaidInfoScrollFrameScrollBarTop",
        "RaidInfoScrollFrameScrollBarBottom",
        "RaidInfoScrollFrameScrollBarMiddle",
    }) do
        local tex = _G[name]
        if tex then S.KillTexture(tex) end
    end

    for _, name in ipairs({
        "RaidFrameConvertToRaidButton",
        "RaidFrameRaidInfoButton",
        "RaidInfoExtendButton",
        "RaidInfoCancelButton",
    }) do
        local btn = _G[name]
        S.Button(btn)

        if btn then S.FontStrings(btn, 12, "") end
    end

    if _G.RaidInfoInstanceLabel then S.FontStringsDeep(_G.RaidInfoInstanceLabel, 12, "", 1) end
    if _G.RaidInfoIDLabel then S.FontStringsDeep(_G.RaidInfoIDLabel, 12, "", 1) end

    if frame.ScrollBox and S.HookScrollBox then
        S.HookScrollBox(frame.ScrollBox, function(row)
            if S.data(row).raidInfoFonted then return end
            S.data(row).raidInfoFonted = true
            S.FontStringsDeep(row, 12, "", 1)
            if row.name then S.SetFont(row.name, 13, "") end
        end)
    end

    S.CloseButton(_G.RaidInfoCloseButton)
    S.ScrollBar(frame.ScrollBar)
    if _G.RaidFrameAllAssistCheckButton then
        S.CheckBox(_G.RaidFrameAllAssistCheckButton)
    end
end

S:RegisterEarly(Skin, "NonRaid")
