local KE = select(2, ...)
local S = KE.Skins
local _G = _G
local ipairs = ipairs
local type = type
local pcall = pcall
local hooksecurefunc = hooksecurefunc
local function NOOP() end

local function GetFriendsUI()
    local ns = _G.BetterFriendlist
    return ns and ns.FriendsUI
end

-- nil while the addon has applied no layout yet, or holds one deferred in
-- combat; it applies that one again after combat or at the next show.
local function LayoutFor(ui)
    if type(ui) ~= "table" or type(ui.IsModernActive) ~= "function" then return "legacy" end
    if ui.appliedStyle == nil or ui.pendingStyle ~= nil then return nil end
    return ui:IsModernActive() and "modern" or "legacy"
end
S._BFLLayoutFor = LayoutFor

local function IsModern()
    local ui = GetFriendsUI()
    return type(ui) == "table" and type(ui.IsModernActive) == "function" and ui:IsModernActive() == true
end

-- The Modern layout swaps these action buttons for runtime copies and keeps
-- the originals under a BFL_Legacy key.
local function LegacyButton(owner, key)
    return owner and (owner["BFL_Legacy" .. key] or owner[key])
end

local function GetBFLModule(name)
    local ns = _G.BetterFriendlist
    local mod = ns and ns.GetModule and ns:GetModule(name)
    return type(mod) == "table" and mod or nil
end

-- pcall: a scroll box the addon has not set up yet may have no view to walk.
local function EachFrame(box, fn)
    if type(box) == "table" and type(box.ForEachFrame) == "function" then
        pcall(box.ForEachFrame, box, fn)
    end
end

local function DressInviteRow(button)
    if not button or S.data(button).bflSkinned then return end
    S.data(button).bflSkinned = true
    S.Button(button.AcceptButton)
    S.Button(button.DeclineButton)
end

local normalizePending = false
local function NormalizeRaidGrid(passes)
    if normalizePending then return end
    normalizePending = true
    _G.C_Timer.After(0, function()
        normalizePending = false
        local f2 = _G.BetterFriendsFrame
        local rf = f2 and f2.RaidFrame
        local cont = rf and (rf.GroupsContainer
            or (rf.GroupsInset and rf.GroupsInset.GroupsContainer))
        if not cont or not cont:IsVisible() then return end
        local _, phH = GetPhysicalScreenSize()
        for g = 1, 8 do
            local grp = cont["Group" .. g]
            if grp then
                local eff = grp:GetEffectiveScale()
                local toPhys = (eff and eff > 0) and (eff * (phH or 768) / 768) or 1
                local top = grp.GetTop and grp:GetTop()
                if top and grp.AdjustPointsOffset then
                    local tp = top * toPhys
                    local frac = tp - math.floor(tp + 0.5)
                    if math.abs(frac) > 0.01 then grp:AdjustPointsOffset(0, -frac / toPhys) end
                end
                for i = 1, 5 do
                    local sl = grp["Slot" .. i]
                    if sl and S.data(sl).bflSlotSkinned then
                        local st = sl.GetTop and sl:GetTop()
                        if st and sl.AdjustPointsOffset then
                            local sp = st * toPhys
                            local frac = sp - math.floor(sp + 0.5)
                            if math.abs(frac) > 0.01 then sl:AdjustPointsOffset(0, -frac / toPhys) end
                        end
                        local h = sl:GetHeight()
                        if h then
                            local snapped = math.floor(h * toPhys + 0.5) / toPhys
                            if math.abs(snapped - h) > 0.001 then sl:SetHeight(snapped) end
                        end
                        S.FixSubPixelEdge(sl)
                    end
                end
            end
        end
        if (passes or 1) > 1 then NormalizeRaidGrid(passes - 1) end
    end)
end

local TOOLTIP_FONT_BUMP = 1
local function FontBFLTooltipLines()
    local tip = _G.BFL_Tooltip
    if not tip or not tip.NumLines then return end
    for i = 1, tip:NumLines() do
        for _, side in ipairs({ "BFL_TooltipTextLeft", "BFL_TooltipTextRight" }) do
            local fs = _G[side .. i]
            if fs then
                local d = S.data(fs)
                if not d.bflTipBase then
                    local _, size = fs:GetFont()
                    d.bflTipBase = size or 12
                end
                S.SetFont(fs, d.bflTipBase + TOOLTIP_FONT_BUMP, "OUTLINE")
            end
        end
    end
end

local function FontFriendsTooltip()
    local tip = _G.FriendsTooltip
    if not tip or not tip.GetRegions then return end
    for _, r in ipairs({ tip:GetRegions() }) do
        if r.IsObjectType and r:IsObjectType("FontString") then
            local d = S.data(r)
            if not d.fttBase then
                local _, size = r:GetFont()
                d.fttBase = size or 10
            end

            local target = (d.fttBase >= 12) and (d.fttBase + 1) or 12
            S.SetFont(r, target, "OUTLINE")
        end
    end
end

local tooltipHooked = false
local function HookBFLTooltip()
    if tooltipHooked then return end
    local tip = _G.BFL_Tooltip
    if not tip or not tip.HookScript then return end
    tooltipHooked = true
    tip:HookScript("OnShow", FontBFLTooltipLines)
    FontBFLTooltipLines()
end

local function KillSearchPlates(box)
    if not box or not box.GetChildren then return end
    local ours = S.GetBackdrop(box)

    for _, child in ipairs({ box:GetChildren() }) do
        if child ~= ours and not (child.IsObjectType and child:IsObjectType("Button")) then
            if child.SetBackdrop then pcall(child.SetBackdrop, child, nil) end
            if child.SetAlpha then child:SetAlpha(0) end
        end
    end

    if box.GetRegions then
        local instr = box.Instructions
        local itext = instr and instr.GetText and instr:GetText()
        for _, r in ipairs({ box:GetRegions() }) do
            if r.IsObjectType and r:IsObjectType("Texture") then
                local layer = r.GetDrawLayer and r:GetDrawLayer()
                if layer ~= "OVERLAY" and layer ~= "HIGHLIGHT" then
                    S.KillTexture(r)
                end
            elseif r.IsObjectType and r:IsObjectType("FontString") and instr and r ~= instr then
                if itext and r.GetText and r:GetText() == itext then
                    r:SetAlpha(0)
                end
            end
        end
    end
end

local function SkinInset(inset)
    if not inset or S.data(inset).bflSkinned then return end
    S.data(inset).bflSkinned = true
    S.StripTextures(inset)

    local bd = S.Template(inset, "Transparent")
    if bd then
        bd:ClearAllPoints()
        bd:SetPoint("TOPLEFT", inset, "TOPLEFT", 4, -4)
        bd:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -4, 4)
    end
end

local function SkinHeaderRow(button)
    if not button then return end
    if button.BG then
        button.BG:SetTexture(nil)
        button.BG:Hide()
    end
    if S.data(button).bflSkinned then return end
    S.data(button).bflSkinned = true
    S.Backdrop(button, 1)
end

local INVITE_GLYPH_SIZE = 16
local INVITE_GLYPH_DISABLED = 0.55

-- The Modern layout's own in-group test. Each field is checked for secrecy
-- before it is tested, and a secret GUID never reaches the call: the API
-- rejects secret arguments from addon code.
local function FriendInGroup(friend)
    if type(friend) ~= "table" then return false end
    local connected = friend.connected
    if KE:IsSecretValue(connected) or not connected then return false end
    local guid = friend.guid
    if KE:IsSecretValue(guid) then return false end
    if not guid then
        local info = friend.gameAccountInfo
        if type(info) ~= "table" then return false end
        guid = info.playerGuid
        if KE:IsSecretValue(guid) or not guid then return false end
    end
    local sq = _G.C_SocialQueue
    if not (sq and sq.IsSystemSupported and sq.GetGroupForPlayer) or not sq.IsSystemSupported() then
        return false
    end
    local ok, group = pcall(sq.GetGroupForPlayer, guid)
    return ok and group ~= nil
end

-- Full alpha: the color alone shows the disabled state.
local function TintInviteGlyph(glyph, enabled)
    if not glyph then return end
    glyph:SetDesaturated(true)
    glyph:SetAlpha(1)
    if enabled then
        glyph:SetVertexColor(1, 1, 1)
    else
        glyph:SetVertexColor(INVITE_GLYPH_DISABLED, INVITE_GLYPH_DISABLED, INVITE_GLYPH_DISABLED)
    end
end

local function PaintLegacyInviteGlyph(tp)
    local glyph = S.data(tp).inviteGlyph
    if not glyph or IsModern() then return end
    local enabled = tp:IsEnabled()
    local atlas = FriendInGroup(tp.friendData) and "friends-icon-friendsInGroup" or "friends-icon-friendsAvailable"
    glyph:SetAtlas(enabled and atlas or (atlas .. "-dis"))
    glyph:SetSize(INVITE_GLYPH_SIZE, INVITE_GLYPH_SIZE)
    TintInviteGlyph(glyph, enabled)
    glyph:Show()
end

-- BFL re-fonts raid names with its own font object and smooth scaling on
-- each roster update; KE's font goes back on after theirs, smooth scaling
-- off, or the letters sit at uneven heights.
local function RefontRaidName(button)
    local name = button and button.Name
    if not name or not S.data(button).bflSlotSkinned then return end
    S.data(name).fontSize = nil   -- their SetFontObject changed the string under KE's cache
    S.SetFont(name, 12, "OUTLINE")
    if name.SetSmoothScaling then pcall(name.SetSmoothScaling, name, false) end
end

-- The addon re-dresses this button on every row update, so the art removal
-- and the glyph are re-applied each time; the strip clears the glyph's atlas
-- too. The Recent Allies party button also wears the Modern treatment, so the
-- Legacy box is re-placed after a layout switch.
local function FlattenInviteButton(tp)
    if not tp then return end
    local d = S.data(tp)

    if not d.bflSkinned then
        d.bflSkinned = true
        local w, h = tp:GetSize()
        if w and h then tp:SetSize(math.floor(w + 0.5), math.floor(h + 0.5)) end
        local glyph = tp:CreateTexture(nil, "OVERLAY")
        glyph:SetPoint("CENTER", 0, 0)
        d.inviteGlyph = glyph
        tp:HookScript("OnEnable", PaintLegacyInviteGlyph)
        tp:HookScript("OnDisable", PaintLegacyInviteGlyph)
    end
    if d.inviteLayout ~= "legacy" then
        d.inviteLayout = "legacy"
        S.Backdrop(tp, 4)
    end

    S.StripTextures(tp)
    S.ClearButtonArt(tp)
    -- After the strip, which clears the hover highlight too.
    S.Hover(tp, S.GetBackdrop(tp))
    PaintLegacyInviteGlyph(tp)
end

local function HookIf(owner, name, fn)
    if type(owner) == "table" and type(owner[name]) == "function" then
        -- The checker infers this parameter from its call sites and cannot
        -- see the table guard above.
        ---@diagnostic disable-next-line: type-mismatch
        hooksecurefunc(owner, name, fn)
    end
end

local function HookLazy(module, creatorNames, skinFn)
    -- Callers pass whatever GetModule or a namespace field returns, which is
    -- not always a table to hook onto.
    if type(module) ~= "table" then return end
    for _, name in ipairs(creatorNames) do
        HookIf(module, name, function() pcall(skinFn) end)
    end
    pcall(skinFn)
end

local function SkinRaidTools()
    local f = _G.BetterFriendlistRaidToolsFrame
    if not f or S.data(f).rtSkinned then return end
    S.data(f).rtSkinned = true

    S.StripTextures(f)
    for _, key in ipairs({ "NineSlice", "Bg", "Inset", "Background" }) do
        if f[key] then S.StripTextures(f[key], true) end
    end
    local bg = _G.BetterFriendlistRaidToolsFrameBg
    if bg and bg.SetAlpha then bg:SetAlpha(0) end
    S.Backdrop(f)
    if f.CloseButton then S.CloseButton(f.CloseButton) end
    if f.TitleContainer then S.FontStrings(f.TitleContainer, 13, "") end

    if _G.BFLRaidToolsSortMode then pcall(S.DropDown, _G.BFLRaidToolsSortMode) end
    if _G.BFLRaidToolsPreserveGroups then pcall(S.DropDown, _G.BFLRaidToolsPreserveGroups) end

    if _G.BFLRaidToolsBalanceDps then S.CheckBox(_G.BFLRaidToolsBalanceDps) end
    if _G.BFLRaidToolsResumeCheck then S.CheckBox(_G.BFLRaidToolsResumeCheck) end

    for _, key in ipairs({ "sortButton", "splitButton", "splitOddsButton", "promoteButton" }) do
        if f[key] then S.Button(f[key]) end
    end
end

local function SkinChangelog()
    local f = _G.BetterFriendlistChangelogFrame
    if not f or S.data(f).bflSkinned then return end
    S.data(f).bflSkinned = true
    S.Frame(f)
    SkinInset(f.MainInset)
    S.Button(f.DiscordButton)
    S.Button(f.GitHubButton)
    S.Button(f.KoFiButton)
    if f.ScrollBar then
        S.ScrollBar(f.ScrollBar)
    elseif f.ScrollFrame then
        for _, child in ipairs({ f.ScrollFrame:GetChildren() }) do
            if child:IsObjectType("Slider") then S.ScrollBar(child) end
        end
    end
end

local function SkinHelp()
    local f = _G.BetterFriendlistHelpFrame
    if not f or S.data(f).bflSkinned then return end
    S.data(f).bflSkinned = true
    S.Frame(f)
    SkinInset(f.Inset)
    if f.ScrollBar then
        S.ScrollBar(f.ScrollBar)
    elseif f.ScrollFrame then
        for _, child in ipairs({ f.ScrollFrame:GetChildren() }) do
            if child:IsObjectType("Slider") then S.ScrollBar(child) end
        end
    end
end

local function SkinLegacySettings()
    local f = _G.BetterFriendlistSettingsFrame
    if not f or S.data(f).bflSkinned then return end
    S.data(f).bflSkinned = true
    S.Frame(f)
    S.Tabs("BetterFriendlistSettingsFrameTab", 10)
    SkinInset(f.MainInset)
    if f.ContentScrollFrame then S.ScrollBar(f.ContentScrollFrame.ScrollBar) end
end

local function SkinSettingsShell(designer)
    local ok, f = pcall(function() return designer:GetFrame() end)
    if not ok or not f or S.data(f).bflSkinned then return end
    S.data(f).bflSkinned = true
    S.Frame(f)
    for _, key in ipairs({ "TopBar", "Sidebar", "ContentShell", "SearchShell" }) do
        local child = f[key]
        if child then
            S.StripTextures(child)
            S.Backdrop(child)
        end
    end
    if f.SearchBox then S.EditBox(f.SearchBox) end
    for _, key in ipairs({ "ResetButton", "LockButton", "DensityButton" }) do
        local btn = f[key]
        if btn and btn.GetObjectType and btn:GetObjectType() == "Button" then
            S.Button(btn)
        end
    end
end

local function SkinRAF(frame)
    local raf = frame.RecruitAFriendFrame
    if not raf or S.data(raf).bflSkinned then return end
    S.data(raf).bflSkinned = true
    if raf.Border then S.StripTextures(raf.Border) end
    if raf.Background then raf.Background:Hide() end
    local rc = raf.RewardClaiming
    if rc then
        if rc.Background then rc.Background:SetAlpha(0) end
        S.Backdrop(rc)
        S.Button(rc.ClaimOrViewRewardButton)
        SkinInset(rc.Inset)
        if rc.NextRewardButton then S.Backdrop(rc.NextRewardButton) end
    end
    local rl = raf.RecruitList
    if rl then
        SkinInset(rl.ScrollFrameInset)
        S.ScrollBar(rl.ScrollBar)
        if rl.Header then
            if rl.Header.Background then rl.Header.Background:Hide() end
            S.StripTextures(rl.Header)
            S.Backdrop(rl.Header)
        end
    end
    local sp = raf.SplashFrame
    if sp then
        S.StripTextures(sp)
        S.Backdrop(sp)
        if sp.Background then sp.Background:Hide() end
        if sp.PictureFrame then sp.PictureFrame:Hide() end
        if sp.Watermark then sp.Watermark:Hide() end
        for _, key in ipairs({ "Bracket_TopLeft", "Bracket_TopRight", "Bracket_BottomLeft", "Bracket_BottomRight" }) do
            if sp[key] then sp[key]:Hide() end
        end
        S.Button(sp.OKButton)
    end
end

local function StripPanelShell(frame)
    if not frame then return end
    if frame.NineSlice and frame.NineSlice.SetAlpha then frame.NineSlice:SetAlpha(0) end
    for _, key in ipairs({ "Bg", "TitleBg", "TopTileStreaks", "PortraitIcon", "PortraitMask" }) do
        local r = frame[key]
        if r and r.SetAlpha then r:SetAlpha(0) end
        if r and r.Hide then r:Hide() end
    end
    if frame.TitleContainer and frame.TitleContainer.TitleBg then
        frame.TitleContainer.TitleBg:SetAlpha(0)
    end
    local inset = frame.Inset
    if inset then
        if inset.Bg then inset.Bg:SetAlpha(0) end
        if inset.NineSlice and inset.NineSlice.SetAlpha then inset.NineSlice:SetAlpha(0) end
    end

    for _, target in ipairs({ frame, inset }) do
        local bd = target and S.GetBackdrop and S.GetBackdrop(target)
        if bd then
            bd:Show()
            bd:SetAlpha(1)
            local tone = (target == inset) and S.palette.panel or S.palette.window
            bd:SetBackdropColor(tone[1], tone[2], tone[3], tone[4])

        end
    end
    local close = frame.CloseButton
        or (frame.GetName and frame:GetName() and _G[frame:GetName() .. "CloseButton"])
    if close then

        local x = S.data(close).closeX
        if x then
            local blizz = { close:GetNormalTexture(), close:GetPushedTexture(),
                close:GetHighlightTexture(), close:GetDisabledTexture() }
            for i = 1, 4 do
                local t = blizz[i]
                if t and t.SetAlpha then t:SetAlpha(0) end
            end
            x:Show()
        end
    end
end

-- Legacy layout only. The whole account row hangs off BattlenetFrame: the
-- status dropdown anchors to its LEFT and the contacts and settings buttons
-- chain off its RIGHT, so one anchor moves all four. The Legacy XML gives that
-- anchor x = 10 against the title bar's center, which widens the left margin
-- by 10 and runs the settings cog against the frame edge. The Modern layout
-- anchors the row on both sides, and rewriting point 1 there drops the right.
--
-- Only the X is rewritten; point, relative frame and Y go straight back down,
-- so a later version moving the row vertically is not undone.
local function CenterBattlenetRow(bnet)
    if not bnet or not bnet.GetPoint then return end
    local p, rel, rp, x, y = bnet:GetPoint(1)
    if not p or not rel or x == 0 then return end
    bnet:ClearAllPoints()
    bnet:SetPoint(p, rel, rp, 0, y)
end

local MODERN_SURFACES = {
    "ContentBackground", "ContentInsetTint", "TopFade", "BottomFade", "TopDivider", "BottomDivider",
}
local SIDE_TAB_ICON_IDLE = 0.651
local THEME_CONTROL_STYLERS = {
    "SkinButton", "SkinDropdown", "SkinDropdownIndicator", "SkinEditBox", "SkinCheckButton", "SkinFrame",
}
local ownedControls = setmetatable({}, { __mode = "k" })
local INVITE_STATE_ART = {
    { "NormalTexture", "GetNormalTexture" },
    { "PushedTexture", "GetPushedTexture" },
    { "DisabledTexture", "GetDisabledTexture" },
    { "HighlightTexture", "GetHighlightTexture" },
}

local function ZeroAlpha(region)
    if region and region.SetAlpha then region:SetAlpha(0) end
end

-- The addon shows, hides and tints these backgrounds, and creates the inset
-- tint at its first theme apply, but never sets their alpha, so alpha 0 holds
-- and KE's window backdrop shows through.
local function ModernSurfaces()
    local ui = GetFriendsUI()
    local root = type(ui) == "table" and ui.root
    if not root then return end
    for _, key in ipairs(MODERN_SURFACES) do
        ZeroAlpha(root[key])
    end
    ZeroAlpha(root.FilterBar and root.FilterBar.Background)
    ZeroAlpha(root.BattleNetBar and root.BattleNetBar.Background)
end

local function DressSideTab(tab)
    local d = S.data(tab)
    if d.bflSideTab then return end
    d.bflSideTab = true
    -- The dark theme's own opt-out flag; its skin engine skips the tab.
    tab.BFL_DarkNoButtonChrome = true
    ownedControls[tab] = true
    S.Hover(tab, S.Template(tab, "Default"))
end

-- Every pass: the addon's selection refresh shows its tab backdrop again after
-- the opt-out hid it, and a theme apply resets the tab art and icon color.
local function PaintSideTabs()
    local ui = GetFriendsUI()
    local tabs = type(ui) == "table" and ui.sideTabs
    if not tabs then return end
    for _, tab in ipairs(tabs) do
        DressSideTab(tab)
        if tab.BFL_DarkBackdrop then tab.BFL_DarkBackdrop:Hide() end
        ZeroAlpha(tab.Background)
        ZeroAlpha(tab.SelectedTexture)
        ZeroAlpha(tab.HighlightTexture)
        local selected = tab:IsEnabled() and tab.sectionID ~= nil and tab.sectionID == ui.selectedSection
        local bd = S.GetBackdrop(tab)
        if bd then
            if selected then
                S.PaintBrand(bd, "SetBackdropBorderColor", 1)
            else
                S.ForgetBrand(bd)
                bd:SetBackdropBorderColor(S.borderColor[1], S.borderColor[2], S.borderColor[3], S.borderColor[4])
            end
        end
        local icon = tab.Icon or tab.icon
        if icon and icon.SetVertexColor then
            local v = selected and 1 or SIDE_TAB_ICON_IDLE
            icon:SetVertexColor(v, v, v)
        end
    end
end

-- The addon sets the bar art back to full alpha on every pass.
local function SkinModernHeaderBar(button, hover)
    if not button then return end
    local d = S.data(button)
    if not d.bflModernHeader then
        d.bflModernHeader = true
        local bd = S.Backdrop(button, 1)
        if hover then S.Hover(button, bd) end
    end
    ZeroAlpha(button.GetNormalTexture and button:GetNormalTexture())
    ZeroAlpha(button.GetPushedTexture and button:GetPushedTexture())
end

-- The dark theme styles a control again after KE has dressed it, on a first
-- section visit and a theme switch, and a color change re-shows its backdrop.
-- On a control KE claimed, that backdrop and the arrow box are hidden and
-- KE's caret is shown again.
local function ReassertControl(ctl)
    if ctl.BFL_DarkBackdrop then ctl.BFL_DarkBackdrop:Hide() end
    if ctl.BFL_DarkDropdownIndicator then ctl.BFL_DarkDropdownIndicator:Hide() end
    local caret = S.data(ctl).caret
    if caret then caret:SetAlpha(1) end
end

-- Claims a control KE dressed. A plain button also takes the opt-out flag so
-- later passes skip it; a dropdown does not, so it keeps the addon's own menu.
local function OwnControl(ctl)
    if not (ctl and S.GetBackdrop(ctl)) then return end
    ownedControls[ctl] = true
    if ctl.GetObjectType and ctl:GetObjectType() == "Button" and ctl.SetupMenu == nil then
        ctl.BFL_DarkNoButtonChrome = true
    end
    ReassertControl(ctl)
end

local function ModernButton(btn, keep)
    S.Button(btn, keep)
    OwnControl(btn)
end

local function SkinRequestCard(button)
    if not button then return end
    ModernButton(button.AcceptButton)
    local decline = button.DeclineButton
    if decline then ModernButton(decline, decline:GetNormalTexture()) end
end

-- The addon re-atlases the state art and recolors the glyph on every pass, so
-- this runs after it each time. The opt-out flag stops its dark theme
-- recoloring the glyph on hover and press. A strip would clear the glyph too.
local function FlattenModernInvite(btn)
    if not btn then return end
    local d = S.data(btn)
    if d.inviteLayout ~= "modern" then
        d.inviteLayout = "modern"
        btn.BFL_DarkNoButtonChrome = true
        ownedControls[btn] = true
        local bd = S.Backdrop(btn, 0)
        if bd then
            local c = S.palette.control
            bd:SetBackdropColor(c[1], c[2], c[3], c[4])
        end
        S.Hover(btn, bd)
        if d.inviteGlyph then d.inviteGlyph:Hide() end
    end
    for _, art in ipairs(INVITE_STATE_ART) do
        local region = btn[art[1]]
        if not region and btn[art[2]] then region = btn[art[2]](btn) end
        ZeroAlpha(region)
    end
    TintInviteGlyph(btn.ActionIcon, btn:IsEnabled())
end

local function CardHover(card)
    local hl = card.highlight
    if not hl then return end
    local c = S.palette.hover
    hl:SetDesaturated(true)
    hl:SetVertexColor(c[1], c[2], c[3])
    hl:SetAlpha(c[4])
end

local STATUS_FIELDS = { "connected", "isAFK", "afk", "isDND", "dnd" }
local STATUS_EDGE_COLORS = {
    online = { 0.184, 0.82, 0.184 },
    away = { 1, 0.69, 0 },
    busy = { 0.9, 0.2, 0.2 },
}
local STATUS_EDGE_WIDTH = 2
local CLASS_ICON_SIZE = 16
local EUI_CLASS_SHEET = "Interface\\AddOns\\EllesmereUI\\media\\icons\\class-full\\modern.tga"
local WHITE = "Interface\\Buttons\\WHITE8x8"

-- Set in EnsureModern; nothing reads them in the Legacy layout.
local playerZone, euiClassCoords

-- The addon's own status precedence: away before busy. A secret field leaves
-- the edge off rather than being tested.
local function StatusEdge(friend)
    if type(friend) ~= "table" then return nil end
    for _, key in ipairs(STATUS_FIELDS) do
        if KE:IsSecretValue(friend[key]) then return nil end
    end
    if not friend.connected then return nil end
    if friend.isAFK or friend.afk then return "away" end
    if friend.isDND or friend.dnd then return "busy" end
    return "online"
end
S._BFLStatusEdge = StatusEdge

local function SameZone(area, zone)
    if KE:IsSecretValue(area) or KE:IsSecretValue(zone) then return false end
    -- Empty before the world loads, and for a friend outside the game.
    return area ~= nil and area ~= "" and area == zone
end
S._BFLSameZone = SameZone

local function ReadPlayerZone()
    local zone = _G.GetRealZoneText and _G.GetRealZoneText()
    if KE:IsSecretValue(zone) then zone = nil end
    playerZone = zone
end

local function FriendClassFile(friend)
    local ns = _G.BetterFriendlist
    local utils = ns and ns.ClassUtils
    if type(utils) ~= "table" or type(utils.GetClassFileForFriend) ~= "function" then return nil end
    local ok, classFile = pcall(utils.GetClassFileForFriend, utils, friend)
    if not ok or KE:IsSecretValue(classFile) or type(classFile) ~= "string" or classFile == "" then return nil end
    return classFile
end

local function PaintClassIcon(icon, classFile)
    local coords = euiClassCoords and euiClassCoords[classFile]
    if type(coords) == "table" then
        icon:SetTexture(EUI_CLASS_SHEET)
        icon:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
    else
        local atlasFor = _G.GetClassAtlas
        if not atlasFor then
            icon:Hide()
            return
        end
        icon:SetTexCoord(0, 1, 0, 1)
        icon:SetAtlas(atlasFor(classFile:lower()))
    end
    icon:Show()
end

local function SameColor(r, g, b, a, c)
    return math.abs(r - c[1]) < 0.01 and math.abs(g - c[2]) < 0.01
        and math.abs(b - c[3]) < 0.01 and math.abs(a - c[4]) < 0.01
end

-- The addon recolors the zone line only when its font settings change. KE
-- puts back the color it covered; a color that is not KE's own tint, alpha
-- included, is the addon's new one, which becomes the color to put back and is
-- never overwritten. d is KE's record for one line, r, g, b, a its current
-- color; returns the color to write, or nil.
local function ZoneColor(d, inZone, r, g, b, a, brand)
    local ink = d.zoneInk
    local mine = d.zoneTinted and ink ~= nil and SameColor(r, g, b, a, ink)
    if inZone then
        if not mine then
            local rest = d.zoneRest or {}
            rest[1], rest[2], rest[3], rest[4] = r, g, b, a
            d.zoneRest = rest
        end
        ink = ink or {}
        ink[1], ink[2], ink[3], ink[4] = brand[1], brand[2], brand[3], 1
        d.zoneInk, d.zoneTinted = ink, true
        return ink
    end
    if not d.zoneTinted then return nil end
    d.zoneTinted = nil
    if mine then return d.zoneRest end
    return nil
end
S._BFLZoneColor = ZoneColor

-- The addon's own selection test, for rows built before the selection hook
-- existed. A secret ID matches nothing.
local function RowSelected(list, friend)
    if type(list) ~= "table" or type(friend) ~= "table" then return false end
    if list.selectedFriend == friend then return true end
    local want = list.selectedFriendUID
    if KE:IsSecretValue(want) or want == nil then return false end
    local uid = friend.uid
    if KE:IsSecretValue(uid) then return false end
    if uid == nil and type(list.GetFriendUID) == "function" then
        local ok, value = pcall(list.GetFriendUID, list, friend)
        if ok then uid = value end
    end
    if KE:IsSecretValue(uid) or uid == nil then return false end
    return uid == want
end
S._BFLRowSelected = RowSelected

local function TintZoneLine(card, friend)
    local info = card.Info
    if not info then return end
    local area
    if friend then
        local kind = friend.type
        if KE:IsSecretValue(kind) then
            area = nil
        elseif kind == "bnet" then
            area = friend.areaName
        else
            area = friend.area
        end
    end
    local d = S.data(info)
    local inZone = SameZone(area, playerZone)
    if not (inZone or d.zoneTinted) then return end
    local r, g, b, a = info:GetTextColor()
    local c = ZoneColor(d, inZone, r, g, b, a, S.palette.brand)
    if c then info:SetTextColor(c[1], c[2], c[3], c[4]) end
end

-- The first number of a count in the accent. d keeps the plain text and KE's
-- last output, so a pass that did not rebuild the text recolors KE's own span;
-- any other color code is left alone.
local function AccentCount(d, text, r, g, b)
    if KE:IsSecretValue(text) or type(text) ~= "string" then return nil end
    if text == d.countOut then text = d.countPlain end
    if text:find("|c", 1, true) then return nil end
    local pre, num, rest = text:match("^(%D*)(%d+)(.*)$")
    if not num then return nil end
    local out = string.format("%s|cff%02x%02x%02x%s|r%s", pre,
        math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5), num, rest)
    d.countPlain, d.countOut = text, out
    return out
end
S._BFLAccentCount = AccentCount

-- A color code adds no width, so the addon's measurement of the count holds.
local function TintHeaderCount(button)
    local fs = button and button.CountText
    if not (fs and fs.GetText) then return end
    local brand = S.palette.brand
    local out = AccentCount(S.data(fs), fs:GetText(), brand[1], brand[2], brand[3])
    if out then fs:SetText(out) end
end

-- Drawn on KE's own row backdrop, one level under the card, never on the
-- addon's regions.
local function CardCues(card)
    local d = S.data(card)
    if d.cueEdge then return d end
    local bd = S.GetBackdrop(card)
    if not (bd and card.status) then return nil end
    local fill = bd:CreateTexture(nil, "ARTWORK")
    fill:SetTexture(WHITE)
    S.InsetToEdge(fill, bd)
    S.PaintBrand(fill, "SetVertexColor", S.palette.selectedA)
    fill:Hide()
    local edge = bd:CreateTexture(nil, "OVERLAY")
    edge:SetTexture(WHITE)
    edge:SetPoint("TOPLEFT", fill, "TOPLEFT")
    edge:SetPoint("BOTTOMLEFT", fill, "BOTTOMLEFT")
    edge:SetWidth(STATUS_EDGE_WIDTH)
    edge:Hide()
    local icon = bd:CreateTexture(nil, "OVERLAY")
    icon:SetSize(CLASS_ICON_SIZE, CLASS_ICON_SIZE)
    icon:SetPoint("LEFT", card.status, "RIGHT", 1, 0)
    icon:Hide()
    d.cueFill, d.cueEdge, d.cueIcon = fill, edge, icon
    return d
end

local function PaintCardCues(card, d)
    local friend = card.friendData
    local state = StatusEdge(friend)
    local color = state and STATUS_EDGE_COLORS[state]
    if color then
        d.cueEdge:SetVertexColor(color[1], color[2], color[3])
        d.cueEdge:Show()
    else
        d.cueEdge:Hide()
    end
    local classFile = state and FriendClassFile(friend)
    if classFile then
        PaintClassIcon(d.cueIcon, classFile)
    else
        d.cueIcon:Hide()
    end
    TintZoneLine(card, state and friend or nil)
    d.cueFill:SetShown(d.cueSelected == true)
end

-- The addon sets the card art's alpha and recolors its highlight on every
-- pass, so KE writes after it. Row height and anchors stay the addon's.
local function SkinModernCard(card)
    if not card then return end
    local d = S.data(card)
    if not d.bflModernCard then
        d.bflModernCard = true
        ownedControls[card] = true
        local bd = S.Backdrop(card)
        if bd then
            local p = S.palette.panel
            bd:SetBackdropColor(p[1], p[2], p[3], p[4])
        end
    end
    ZeroAlpha(card.CardBackground)
    ZeroAlpha(card.ThemeTint)
    ZeroAlpha(card.FactionTint)
    CardHover(card)
    FlattenModernInvite(card.travelPassButton)
    local cues = CardCues(card)
    if cues then PaintCardCues(card, cues) end
end

local function RetintInvite(btn)
    if btn and S.data(btn).inviteLayout == "modern" then
        TintInviteGlyph(btn.ActionIcon, btn:IsEnabled())
    end
end

local function ModernPass(frame)
    local ui = GetFriendsUI()
    local root = type(ui) == "table" and ui.root
    if not (frame and root) then return end
    ModernSurfaces()
    if root.BattleNetBar then ModernButton(root.BattleNetBar.MenuButton) end
    ModernButton(frame.StreamerModeButton)
    local filters = root.FilterBar
    if filters then
        for _, key in ipairs({ "SortButton", "FilterDropdown", "RecentFilterDropdown" }) do
            pcall(S.DropDown, filters[key], true)
            OwnControl(filters[key])
        end
    end
    if root.BottomActionBar then ModernButton(root.BottomActionBar.AddFriendButton) end
    local requests = root.RequestsFrame
    if requests then
        S.ScrollBar(requests.ScrollBar)
        local warning = requests.RealIDWarning
        if warning then
            ModernButton(warning.ContinueButton)
            S.ScrollBar(warning.ScrollBar)
        end
    end
    local who = frame.WhoFrame
    if who then
        ModernButton(who.BFL_ModernWhoButton)
        ModernButton(who.BFL_ModernAddFriendButton)
        ModernButton(who.BFL_ModernGroupInviteButton)
    end
    local raid = frame.RaidFrame
    if raid then
        ModernButton(raid.BFL_ModernConvertToRaidButton)
        ModernButton(raid.BFL_ModernRaidToolsButton)
        local cp = raid.ControlPanel
        if cp then
            ModernButton(cp.BFL_ModernRaidInfoButton)
            local readyCheck = cp.BFL_ModernReadyCheckButton
            ModernButton(readyCheck, readyCheck and readyCheck.Icon)
        end
    end
    -- Dressed by the shared code, and styled by the dark theme inside the
    -- application, before the control hooks exist.
    OwnControl(frame)
    OwnControl(frame.Inset)
    local hdr = frame.FriendsTabHeader
    if hdr then
        OwnControl(hdr.StatusDropdown)
        OwnControl(hdr.SearchBox)
        OwnControl(hdr.BattlenetFrame)
    end
    PaintSideTabs()
end

local function ReStrip()
    local frame = _G.BetterFriendsFrame
    if frame then
        StripPanelShell(frame)

        local hdr = frame.FriendsTabHeader
        local bnet = hdr and hdr.BattlenetFrame
        if IsModern() then
            ModernSurfaces()
            PaintSideTabs()
        elseif bnet then
            for _, b in ipairs({ bnet.SettingsButton, bnet.ContactsMenuButton }) do
                if b then S.FixSubPixelEdge(b) end
            end
            CenterBattlenetRow(bnet)
        end

        local ins = frame.Inset

        local ibd = ins and S.GetBackdrop and S.GetBackdrop(ins)
        if ibd then
            ibd:ClearAllPoints()
            ibd:SetPoint("TOPLEFT", ins, "TOPLEFT", 4, -4)
            ibd:SetPoint("BOTTOMRIGHT", ins, "BOTTOMRIGHT", -4, 4)
        end
    end
    StripPanelShell(_G.BetterFriendlistSettingsFrame)
end

local function Skin()
    local frame = _G.BetterFriendsFrame
    if not frame or S.data(frame).bflSkinned then return end
    S.data(frame).bflSkinned = true

    S.Frame(frame)
    StripPanelShell(frame)

    -- The Legacy title bar, tabs and action buttons; the Modern layout hides
    -- all of it.
    local function DressLegacyChrome()
        local pb = frame.PortraitButton
        if pb then
            pb:ClearAllPoints()
            pb:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -4)
            pb:SetSize(26, 26)
            pb:SetFrameLevel(frame:GetFrameLevel() + 5)
            local bd = S.Backdrop(pb, 0)
            if not pb.Icon then
                pb.Icon = pb:CreateTexture(nil, "ARTWORK")
                pb.Icon:SetTexture("Interface\\AddOns\\BetterFriendlist\\Textures\\PortraitIcon")
            end
            pb.Icon:ClearAllPoints()
            pb.Icon:SetPoint("TOPLEFT", pb, "TOPLEFT", 1, -1)
            pb.Icon:SetPoint("BOTTOMRIGHT", pb, "BOTTOMRIGHT", -1, 1)
            pb.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            pb.Icon:Show()
            if pb.Glow then
                pb.Glow:ClearAllPoints()
                pb.Glow:SetPoint("TOPLEFT", pb, "TOPLEFT", 1, -1)
                pb.Glow:SetPoint("BOTTOMRIGHT", pb, "BOTTOMRIGHT", -1, 1)
                pb.Glow:SetDrawLayer("OVERLAY")
            end
            S.Hover(pb, bd)
        end

        -- The seam is the anchor offset plus four: S.Tab draws its backdrop through
        -- S.Template(tab, "Default", 2), inset 2 a side, so two chained tabs show
        -- offset + 4 pixels of daylight. -3 is the 1px seam used everywhere else.
        --
        -- Whether a tab is chained decides, not how many anchor points it has:
        -- every tab carries a single point at +3.
        local TAB_CHAIN_OFFSET = -3

        local function IsTabButton(f)
            return (f and f.GetObjectType and f:GetObjectType() == "Button"
                and tostring(f:GetName() or ""):find("Tab") ~= nil) or false
        end

        local function CleanTabAnchors(tab)
            local p, rel, rp, x, y = tab:GetPoint(1)
            if not p then return end

            local wantX = x
            if IsTabButton(rel) then wantX = TAB_CHAIN_OFFSET end

            -- Nothing to do is the common case once it has settled, and returning
            -- here is what stops our own SetPoint re-arming the hook forever.
            if tab:GetNumPoints() == 1 and wantX == x then return end

            tab:ClearAllPoints()
            tab:SetPoint(p, rel, rp, wantX, y)
        end

        local function ArmBottomHeadY(tab)
            if S.data(tab).yArmor then return end
            S.data(tab).yArmor = true
            local function Pin(t, _, _, _, x, y)
                if y ~= -32 or x ~= -2 then
                    local p, rel, rp = t:GetPoint(1)
                    if p and rel == _G.BetterFriendsFrame then
                        t:ClearAllPoints()
                        t:SetPoint(p, rel, rp, -2, -32)
                    end
                end
            end
            Pin(tab, nil, nil, nil, select(4, tab:GetPoint(1)), select(5, tab:GetPoint(1)))
            hooksecurefunc(tab, "SetPoint", Pin)
        end
        local function ArmAnchorShim(tab)
            if S.data(tab).anchorShim then return end
            S.data(tab).anchorShim = true
            -- Inline, not deferred: CleanTabAnchors measures nothing, and a
            -- deferred answer drew the row at Blizzard's offset for one frame on
            -- every tab click. Its early-out is the re-entry guard.
            hooksecurefunc(tab, "SetPoint", CleanTabAnchors)
            CleanTabAnchors(tab)
        end
        -- BFL's dark theme backdrops each tab edge to edge and borders the selected
        -- one, two pixels outside KE's inset box and over the next tab. Its opt-out
        -- flag hides that backdrop on every state pass; the Hide removes one built
        -- before this ran.
        local function MuteDarkTabChrome(tab)
            tab.BFL_DarkNoButtonChrome = true
            if tab.BFL_DarkBackdrop then tab.BFL_DarkBackdrop:Hide() end
        end

        for i = 1, 4 do
            local tab = _G["BetterFriendsFrameTab" .. i]
            if tab then
                S.data(tab).noGeometry = true
                S.Tab(tab)
                ArmAnchorShim(tab)
                MuteDarkTabChrome(tab)
            end
        end
        for i = 1, 4 do
            local tab = _G["BetterFriendsFrameBottomTab" .. i]
            if tab then
                S.data(tab).noGeometry = true
                S.Tab(tab)
                ArmAnchorShim(tab)
                MuteDarkTabChrome(tab)
                if i == 1 then ArmBottomHeadY(tab) end
            end
        end

        local hdr = frame.FriendsTabHeader
        if hdr then
            pcall(S.DropDown, hdr.QuickFilterDropdown, true)
            pcall(S.DropDown, hdr.PrimarySortDropdown, true)
            pcall(S.DropDown, hdr.SecondarySortDropdown, true)
            local bnet = hdr.BattlenetFrame
            if bnet then
                for _, b in ipairs({ bnet.SettingsButton, bnet.ContactsMenuButton }) do
                    if b then
                        S.Button(b, b.Icon)
                        S.FixSubPixelEdge(b)
                    end
                end
            end
        end
        S.Button(frame.AddFriendButton)
        S.Button(frame.SendMessageButton)

        local who, raid = frame.WhoFrame, frame.RaidFrame
        local cp = raid and raid.ControlPanel
        S.Button(LegacyButton(who, "WhoButton"))
        S.Button(LegacyButton(who, "AddFriendButton"))
        S.Button(LegacyButton(who, "GroupInviteButton"))
        S.Button(LegacyButton(raid, "ConvertToRaidButton"))
        S.Button(LegacyButton(raid, "RaidToolsButton"))
        S.Button(LegacyButton(cp, "RaidInfoButton"))
        local readyCheck = LegacyButton(cp, "ReadyCheckButton")
        S.Button(readyCheck, readyCheck and readyCheck.Icon)
    end

    SkinInset(frame.Inset)
    SkinInset(frame.ListInset)
    if frame.WhoFrame then SkinInset(frame.WhoFrame.ListInset) end
    if frame.RaidFrame then
        SkinInset(frame.RaidFrame.GroupsInset)
        SkinInset(frame.RaidFrame.ListInset)

        local container = frame.RaidFrame.GroupsContainer
            or (frame.RaidFrame.GroupsInset and frame.RaidFrame.GroupsInset.GroupsContainer)
        if container then
            for g = 1, 8 do
                local group = container["Group" .. g]
                if group then
                    if group.GroupTitle then S.SetFont(group.GroupTitle, 12, "") end
                    for i = 1, 5 do
                        local slot = group["Slot" .. i]
                        if slot and not S.data(slot).bflSlotSkinned then
                            S.data(slot).bflSlotSkinned = true

                            local bd = S.Backdrop(slot, 0, true)
                            S.FixSubPixelEdge(slot)

                            for _, key in ipairs({ "Name", "Level" }) do
                                local fs = slot[key]
                                if fs then
                                    S.SetFont(fs, 12, "OUTLINE")
                                    if fs.SetSmoothScaling then pcall(fs.SetSmoothScaling, fs, false) end
                                end
                            end
                            if slot.EmptyText then S.SetFont(slot.EmptyText, 12, "") end
                            local bgTex = slot.Background
                            if bgTex then
                                bgTex:SetTexture("Interface\\Buttons\\WHITE8x8")
                                bgTex:SetTexCoord(0, 1, 0, 1)
                                bgTex:SetVertexColor(S.palette.control[1], S.palette.control[2], S.palette.control[3])

                                bgTex:ClearAllPoints()
                                bgTex:SetPoint("TOPLEFT", bd or slot, "TOPLEFT", 1, -1)
                                bgTex:SetPoint("BOTTOMRIGHT", bd or slot, "BOTTOMRIGHT", -1, 1)
                                bgTex.ClearAllPoints = NOOP
                                bgTex.SetPoint = NOOP
                            end
                        end
                    end
                end
            end
        end
    end
    if frame.QuickJoinFrame then SkinInset(frame.QuickJoinFrame.ContentInset) end

    S.ScrollBar(frame.MinimalScrollBar or frame.ScrollBar)
    if frame.RecentAlliesFrame then S.ScrollBar(frame.RecentAlliesFrame.ScrollBar) end
    if frame.WhoFrame then
        S.ScrollBar(frame.WhoFrame.ScrollBar
            or (frame.WhoFrame.ScrollBox and frame.WhoFrame.ScrollBox.ScrollBar))
    end
    if frame.RaidFrame then S.ScrollBar(frame.RaidFrame.ScrollBar) end
    if frame.QuickJoinFrame then
        S.ScrollBar(frame.QuickJoinFrame.ScrollBar
            or (frame.QuickJoinFrame.ScrollBoxContainer and frame.QuickJoinFrame.ScrollBoxContainer.ScrollBar))
        if frame.QuickJoinFrame.ContentInset then
            S.ScrollBar(frame.QuickJoinFrame.ContentInset.ScrollBar)
        end
    end

    S.Button(frame.RecruitmentButton)
    if frame.WhoFrame then
        S.EditBox(frame.WhoFrame.EditBox)

        KillSearchPlates(frame.WhoFrame.EditBox)
        S.Button(frame.WhoFrame.NameHeader)
        S.Button(frame.WhoFrame.LevelHeader)
        S.Button(frame.WhoFrame.ClassHeader)
        pcall(S.DropDown, frame.WhoFrame.ColumnDropdown, true)
    end
    if frame.RaidFrame then
        if frame.RaidFrame.ControlPanel then
            local cp = frame.RaidFrame.ControlPanel
            if cp.EveryoneAssistCheckbox then S.CheckBox(cp.EveryoneAssistCheckbox) end
            if cp.EveryoneAssistLabel then S.SetFont(cp.EveryoneAssistLabel, 12, "OUTLINE") end
            S.CheckBox(frame.RaidFrame.ControlPanel.EveryoneAssistCheckbox)
        end
    end
    if frame.QuickJoinFrame then
        S.Button(frame.QuickJoinFrame.JoinQueueButton)
        if frame.QuickJoinFrame.ContentInset then
            S.Button(frame.QuickJoinFrame.ContentInset.JoinQueueButton)
        end
    end

    HookBFLTooltip()
    if not tooltipHooked and _G.C_Timer then
        _G.C_Timer.After(0, HookBFLTooltip) -- was 2s
    end
    FontFriendsTooltip()
    if not S.data(frame).fttShowHook and frame.HookScript then
        S.data(frame).fttShowHook = true
        frame:HookScript("OnShow", FontFriendsTooltip)
    end

    local header = frame.FriendsTabHeader
    if header then
        S.EditBox(header.SearchBox)

        KillSearchPlates(header.SearchBox)
        pcall(S.DropDown, header.StatusDropdown, true)

        local bnet = header.BattlenetFrame
        if bnet then
            S.StripTextures(bnet)
            S.Backdrop(bnet)

            if not S.data(frame).keBnetDragHook and frame.HookScript then
                S.data(frame).keBnetDragHook = true
                frame:HookScript("OnDragStop", function()
                    if bnet.SettingsButton then S.FixSubPixelEdge(bnet.SettingsButton) end
                    if bnet.ContactsMenuButton then S.FixSubPixelEdge(bnet.ContactsMenuButton) end
                    NormalizeRaidGrid(2)
                end)

                frame:HookScript("OnSizeChanged", function()
                    NormalizeRaidGrid(2)
                end)
            end
            if bnet.BroadcastFrame then
                S.StripTextures(bnet.BroadcastFrame)
                S.Backdrop(bnet.BroadcastFrame)
                S.Button(bnet.BroadcastFrame.UpdateButton)
                S.Button(bnet.BroadcastFrame.CancelButton)
                S.EditBox(bnet.BroadcastFrame.EditBox)
            end
            if bnet.UnavailableInfoFrame then
                S.StripTextures(bnet.UnavailableInfoFrame)
                S.Backdrop(bnet.UnavailableInfoFrame)
            end
        end
    end

    pcall(SkinRAF, frame)

    local ign = frame.IgnoreListWindow
    if ign then
        S.Frame(ign)
        SkinInset(ign.Inset)
        S.ScrollBar(ign.ScrollBar)
        S.Button(ign.UnignorePlayerButton)
    end

    local HookLegacy = NOOP
    local BFLNS = _G.BetterFriendlist
    if BFLNS and BFLNS.GetModule then
        HookLegacy = function()
            -- The dark theme's tab chrome is muted, so KE's own border carries the
            -- selected-tab cue, in the brand color.
            local function PaintTabBorder(tab, selected)
                local bd = S.GetBackdrop(tab)
                if not bd then return end
                if selected then
                    bd:SetBackdropBorderColor(S.palette.brand[1], S.palette.brand[2], S.palette.brand[3], 1)
                else
                    bd:SetBackdropBorderColor(S.borderColor[1], S.borderColor[2], S.borderColor[3], S.borderColor[4])
                end
            end
            if type(BFLNS.ApplyTabVisualState) == "function" then
                hooksecurefunc(BFLNS, "ApplyTabVisualState", function(_, tab, selected)
                    if tab and not IsModern() and S.data(tab).anchorShim then PaintTabBorder(tab, selected) end
                end)
                -- A palette sweep repaints any border still matching the old default,
                -- and a brand change leaves the cue in the old color; both rows
                -- repaint through the addon's own state pass.
                local function RepaintTabs()
                    if IsModern() then return end
                    pcall(BFLNS.RefreshBottomTabVisualState, BFLNS)
                    pcall(BFLNS.RefreshTopTabVisualState, BFLNS)
                end
                hooksecurefunc(S, "SetSkinColors", RepaintTabs)
                hooksecurefunc(S, "RefreshPalette", RepaintTabs)
                RepaintTabs()
            end
            local FriendsList = BFLNS:GetModule("FriendsList")
            if FriendsList then
                pcall(function()
                    hooksecurefunc(FriendsList, "UpdateGroupHeaderButton", function(_, button)
                        if IsModern() then return end
                        SkinHeaderRow(button)
                    end)
                    hooksecurefunc(FriendsList, "UpdateInviteHeaderButton", function(_, button)
                        if IsModern() then return end
                        SkinHeaderRow(button)
                    end)
                    hooksecurefunc(FriendsList, "UpdateFriendButton", function(_, button)
                        if IsModern() then return end
                        FlattenInviteButton(button and button.travelPassButton)
                    end)
                    hooksecurefunc(FriendsList, "UpdateInviteButton", function(_, button)
                        if IsModern() then return end
                        DressInviteRow(button)
                    end)
                end)
            end
        end
        local RecentAllies = BFLNS:GetModule("RecentAllies")
        HookIf(RecentAllies, "InitializeEntry", function(_, button)
            local party = button and button.PartyButton
            if IsModern() then FlattenModernInvite(party) else FlattenInviteButton(party) end
        end)
        HookLazy(BFLNS:GetModule("Changelog"), { "CreateChangelogWindow" }, SkinChangelog)

        HookLazy(BFLNS:GetModule("RaidTools"), { "CreateFrame" }, SkinRaidTools)

        local RFM = BFLNS:GetModule("RaidFrame")
        if RFM and type(RFM.UpdateGroupLayout) == "function" then
            hooksecurefunc(RFM, "UpdateGroupLayout", function()
                NormalizeRaidGrid(2)
            end)
        end
        if RFM and type(RFM.UpdateMemberButton) == "function" then
            hooksecurefunc(RFM, "UpdateMemberButton", function(_, button)
                RefontRaidName(button)
            end)
        end

        HookLazy(BFLNS.HelpFrame, { "CreateFrame", "Toggle" }, SkinHelp)
        pcall(SkinLegacySettings)
        local designer = BFLNS:GetModule("SettingsDesigner")
        if designer then
            if type(designer.Show) == "function" then
                hooksecurefunc(designer, "Show", function(d) pcall(SkinSettingsShell, d) end)
            end
            pcall(SkinSettingsShell, designer)
        end

        local function DeferredReStrip()
            _G.C_Timer.After(0, ReStrip)
        end
        local TM = BFLNS:GetModule("ThemeManager")
        if TM and type(TM.ApplyCurrentTheme) == "function" then
            hooksecurefunc(TM, "ApplyCurrentTheme", DeferredReStrip)
        end
        local DT = BFLNS:GetModule("DarkTheme")
        if DT and type(DT.Remove) == "function" then
            hooksecurefunc(DT, "Remove", DeferredReStrip)
        end

        DeferredReStrip()
    end

    local legacyReady = false
    local function EnsureLegacy()
        if legacyReady then return end
        legacyReady = true
        DressLegacyChrome()
        HookLegacy()
    end

    -- The addon fills the list inside the application this follows, before
    -- the first hooks exist. The sweep dresses those rows by the addon's own
    -- row keys and only reads the frames the scroll boxes hold.
    local function SweepLegacy()
        local list = GetBFLModule("FriendsList")
        EachFrame(list and list.scrollBox, function(row)
            if row.AcceptButton then
                DressInviteRow(row)
            elseif row.travelPassButton then
                FlattenInviteButton(row.travelPassButton)
            elseif row.BG then
                SkinHeaderRow(row)
            end
        end)
        local recent = frame.RecentAlliesFrame
        EachFrame(recent and recent.ScrollBox, function(row)
            if row.PartyButton then FlattenInviteButton(row.PartyButton) end
        end)
    end

    local function OnFriendCard(_, card)
        if IsModern() then SkinModernCard(card) end
    end

    local function OnGroupHeader(_, button)
        if not IsModern() then return end
        SkinModernHeaderBar(button, true)
        TintHeaderCount(button)
    end

    local function OnRequestHeader(_, button)
        if IsModern() then SkinModernHeaderBar(button, false) end
    end

    local function OnRequestCard(_, button)
        if IsModern() then SkinRequestCard(button) end
    end

    -- The addon's dark theme restyles each row after the hooks above, so KE's
    -- look goes back on after its pass.
    local function OnThemeRow(_, row)
        if not (row and IsModern()) then return end
        if row.CardBackground then
            -- Its hover backdrop sits over the card, and its first pass on a
            -- card clears the highlight.
            if row.BFL_DarkBackdrop then row.BFL_DarkBackdrop:Hide() end
            local hl = row.highlight
            if hl and hl:GetAlpha() == 0 then CardHover(row) end
        end
        RetintInvite(row.travelPassButton or row.PartyButton)
    end

    local function OnThemeControl(_, ctl)
        if IsModern() then OwnControl(ctl) end
    end

    -- Rows get a backdrop here too, so only claimed controls are touched.
    local function OnThemeBackdrop(_, target)
        if target and ownedControls[target] and IsModern() then ReassertControl(target) end
    end

    -- Its tree walk and theme removal put an opted-out button's own art back.
    local function OnThemeRestore(_, btn)
        if not (btn and IsModern()) then return end
        local d = S.data(btn)
        if d.inviteLayout == "modern" then
            FlattenModernInvite(btn)
        elseif d.bflSideTab then
            PaintSideTabs()
        end
    end

    -- The Modern lists, for the reason given above SweepLegacy.
    local function SweepModern()
        local ui = GetFriendsUI()
        local list = GetBFLModule("FriendsList")
        EachFrame(list and list.scrollBox, function(row)
            if row.CardBackground then
                S.data(row).cueSelected = RowSelected(list, row.friendData)
                OnFriendCard(nil, row)
            elseif row.HeaderText then
                OnGroupHeader(nil, row)
            end
        end)
        local root = type(ui) == "table" and ui.root
        local requests = root and root.RequestsFrame
        EachFrame(requests and requests.ScrollBox, function(row)
            if row.Background then
                OnRequestCard(nil, row)
            elseif row.ButtonText then
                OnRequestHeader(nil, row)
            end
        end)
        local recent = frame.RecentAlliesFrame
        EachFrame(recent and recent.ScrollBox, function(row)
            if row.PartyButton then FlattenModernInvite(row.PartyButton) end
        end)
    end

    local modernReady = false
    local function EnsureModern()
        if modernReady then return end
        modernReady = true
        local ui = GetFriendsUI()
        -- EllesmereUI does not load or unload mid-session.
        local eui = _G.EllesmereUI
        local coords = type(eui) == "table" and eui.CLASS_ICON_SPRITE_COORDS
        euiClassCoords = type(coords) == "table" and coords or nil
        local zoneWatch = CreateFrame("Frame")
        zoneWatch:RegisterEvent("ZONE_CHANGED_NEW_AREA")
        zoneWatch:RegisterEvent("PLAYER_ENTERING_WORLD")
        zoneWatch:SetScript("OnEvent", ReadPlayerZone)
        ReadPlayerZone()
        -- A click changes the selection without restyling the row. The state
        -- is kept per row: the addon's own selected-row pointer can still name
        -- a row that was recycled for another friend.
        HookIf(GetBFLModule("FriendsList"), "SetButtonSelectionVisual", function(_, button, selected)
            if not IsModern() or not button then return end
            local d = S.data(button)
            d.cueSelected = selected == true
            if d.cueFill then d.cueFill:SetShown(d.cueSelected) end
        end)
        HookIf(ui, "RefreshModernSideTabSelection", function()
            if IsModern() then PaintSideTabs() end
        end)
        HookIf(ui, "StyleGroupHeader", OnGroupHeader)
        HookIf(ui, "InitializeRequestHeader", OnRequestHeader)
        HookIf(ui, "InitializeRequestCard", OnRequestCard)
        HookIf(ui, "StyleFriendCard", OnFriendCard)
        local engine = GetBFLModule("SkinEngine")
        HookIf(engine, "SkinRow", OnThemeRow)
        HookIf(engine, "RefreshRow", OnThemeRow)
        HookIf(engine, "RestoreFrame", OnThemeRestore)
        HookIf(engine, "CreateBackdrop", OnThemeBackdrop)
        for _, name in ipairs(THEME_CONTROL_STYLERS) do
            HookIf(engine, name, OnThemeControl)
        end
    end

    local function OnLayoutApplied()
        local layout = LayoutFor(GetFriendsUI())
        if layout == "modern" then
            EnsureModern()
            ModernPass(frame)
            SweepModern()
        elseif layout == "legacy" then
            EnsureLegacy()
            SweepLegacy()
        end
    end

    local ui = GetFriendsUI()
    if type(ui) == "table" and type(ui.ApplyEffectiveStyle) == "function" then
        hooksecurefunc(ui, "ApplyEffectiveStyle", OnLayoutApplied)
        OnLayoutApplied()
    else
        EnsureLegacy()
        SweepLegacy()
    end
end

local function SkinAddFriendDialog()

    local af = _G.AddFriendFrame
    if not af or S.data(af).skinned then return end
    S.data(af).skinned = true
    if af.Border then af.Border:Hide() end
    S.StripTextures(af)
    S.Template(af, "Window")
    local entry = _G.AddFriendEntryFrame
    if entry then
        S.StripTextures(entry)
        S.FontStringsDeep(entry, 12, "OUTLINE", 2)
        local title = entry.TitleContainer and entry.TitleContainer.Title
        if title then S.SetFont(title, 14, "OUTLINE") end
    end
    if _G.AddFriendNameEditBox then S.EditBox(_G.AddFriendNameEditBox) end
    if _G.AddFriendEntryFrameAcceptButton then S.Button(_G.AddFriendEntryFrameAcceptButton) end
    if _G.AddFriendEntryFrameCancelButton then S.Button(_G.AddFriendEntryFrameCancelButton) end
    local close = af.CloseButton or _G.AddFriendFrameCloseButton
    if close then S.CloseButton(close) end

    af:HookScript("OnShow", function()
        C_Timer.After(0, function()
            S.FixSubPixelEdge(af)

            local entry = _G.AddFriendEntryFrame -- luacheck: ignore 431/entry
            if entry then
                S.FixSubPixelEdge(entry)
                if entry.EditBoxContainer then S.FixSubPixelEdge(entry.EditBoxContainer) end
            end

            if _G.AddFriendEntryFrameAcceptButton then S.FixSubPixelEdge(_G.AddFriendEntryFrameAcceptButton) end
            if _G.AddFriendEntryFrameCancelButton then S.FixSubPixelEdge(_G.AddFriendEntryFrameCancelButton) end
        end)
    end)
end

local function SkinAll()
    Skin()
    SkinAddFriendDialog()
end

S:Register("BetterFriendlist", SkinAll, "BetterFriendlist")
