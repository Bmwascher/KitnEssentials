local KE = select(2, ...)
local S = KE.Skins
local _G = _G
local gsub = string.gsub
local hooksecurefunc = hooksecurefunc

-- Blizzard bakes dark colour codes into gossip text -- black headers, near
-- black body -- which disappear on a dark backdrop, and it sizes inline icons
-- without the texcoords that keep them square. Both are fixed in the string
-- rather than on the fontstring, because Blizzard re-sets the text on every
-- refresh and anything applied to the widget is lost.
local DARK_CODES = {
    ["000000"] = "ffffff",
    ["414141"] = "7b8489",
}

local COLOUR_CODE  = "|c[fF][fF](%x%x%x%x%x%x)"
local ICON_UNSIZED = ":32:32:0:0"
local ICON_SQUARE  = ":32:32:0:0:64:64:5:59:5:59"

local function Relight(code)
    return "|cFF" .. (DARK_CODES[code] or code)
end

-- Returns the rewritten string, or nil when it was already fine.
local function Readable(text, colourOnly)
    if not text or text == "" then return end

    local out = text
    if not colourOnly then out = gsub(out, ICON_UNSIZED, ICON_SQUARE) end
    out = gsub(out, COLOUR_CODE, Relight)

    if out ~= text then return out end
end

-- Blizzard hands us its own colour; anything that is not already white is one
-- of the dark picks and gets overridden.
local function WhitenText(text, r, g, b)
    if r ~= 1 or g ~= 1 or b ~= 1 then
        text:SetTextColor(1, 1, 1)
    end
end

local function Gossip_SetFormattedText(button, textFormat, text, skip)
    if skip then return end

    local lit = Readable(textFormat, true)
    if lit then button:SetFormattedText(lit, text, true) end
end

local function Gossip_SetText(button, text)
    local lit = Readable(text)
    if lit then button:SetFormattedText("%s", lit, true) end
end

-- Same override, but SimpleHTML takes the element type as its first argument.
local function WhitenPageText(pageText, headerType, r, g, b)
    if r ~= 1 or g ~= 1 or b ~= 1 then
        pageText:SetTextColor(headerType, 1, 1, 1)
    end
end

local function DressGreetingRow(button)
    local d = S.data(button)
    if d.gossipSkinned then return end

    if button.GreetingText then
        button.GreetingText:SetTextColor(1, 1, 1)
        hooksecurefunc(button.GreetingText, "SetTextColor", WhitenText)
    end

    local fontString = button.GetFontString and button:GetFontString()
    if fontString then
        fontString:SetTextColor(1, 1, 1)
        hooksecurefunc(fontString, "SetTextColor", WhitenText)

        Gossip_SetText(button, button:GetText())
        hooksecurefunc(button, "SetText", Gossip_SetText)
        hooksecurefunc(button, "SetFormattedText", Gossip_SetFormattedText)
    end

    d.gossipSkinned = true
end

local function GreetingRows(frame)
    if frame.ForEachFrame and frame.view then
        frame:ForEachFrame(DressGreetingRow)
    end
end

local function Skin()
    local frame = _G.GossipFrame
    if not frame then return end
    S.Frame(frame)

    if _G.ItemTextScrollFrame and _G.ItemTextScrollFrame.ScrollBar then
        S.TrimScrollBar(_G.ItemTextScrollFrame.ScrollBar)
    end
    if frame.GreetingPanel then
        if frame.GreetingPanel.ScrollBar then S.TrimScrollBar(frame.GreetingPanel.ScrollBar) end
        if frame.GreetingPanel.GoodbyeButton then S.Button(frame.GreetingPanel.GoodbyeButton) end
        if frame.GreetingPanel.ScrollBox then
            hooksecurefunc(frame.GreetingPanel.ScrollBox, "Update", GreetingRows)
            GreetingRows(frame.GreetingPanel.ScrollBox)
        end
    end
    if _G.ItemTextFrameCloseButton then S.CloseButton(_G.ItemTextFrameCloseButton) end
    if _G.ItemTextNextPageButton then S.ArrowButton(_G.ItemTextNextPageButton, "right") end
    if _G.ItemTextPrevPageButton then S.ArrowButton(_G.ItemTextPrevPageButton, "left") end

    if frame.FriendshipStatusBar then
        for i = 1, 4 do
            local notch = frame.FriendshipStatusBar["Notch" .. i]
            if notch then
                notch:SetColorTexture(0, 0, 0)
                notch:SetSize(1, 16)
            end
        end
    end

    if _G.ItemTextFrame then
        S.StripTextures(_G.ItemTextFrame, true)
        S.Backdrop(_G.ItemTextFrame)
    end
    if _G.ItemTextScrollFrame then S.StripTextures(_G.ItemTextScrollFrame) end

    if _G.GossipFrameInset then _G.GossipFrameInset:Hide() end
    if _G.QuestFont then _G.QuestFont:SetTextColor(1, 1, 1) end

    if _G.ItemTextPageText then
        _G.ItemTextPageText:SetTextColor("P", 1, 1, 1)
        hooksecurefunc(_G.ItemTextPageText, "SetTextColor", WhitenPageText)
    end

    if frame.Background then frame.Background:Hide() end
end

S:RegisterEarly(Skin, "Gossip")
