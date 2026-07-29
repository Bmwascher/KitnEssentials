local KE = select(2, ...)
local S = KE.Skins
local _G = _G
local ipairs = ipairs

local function Skin()
    for _, f in ipairs({
        _G.BNToastFrame,
        _G.TimeAlertFrame,
        _G.TicketStatusFrameButton and _G.TicketStatusFrameButton.NineSlice,
    }) do
        if f then S.Template(f, "Window") end
    end

    local rf = _G.ReportFrame
    if rf then
        S.StripTextures(rf)
        S.Template(rf, "Window")
        S.CloseButton(rf.CloseButton)
        if rf.ReportingMajorCategoryDropdown then pcall(S.DropDown, rf.ReportingMajorCategoryDropdown) end
        S.Button(rf.ReportButton)
        if rf.Comment then S.EditBox(rf.Comment) end
    end

    local rcd = _G.ReportCheatingDialog
    if rcd then
        S.StripTextures(rcd)
        if _G.ReportCheatingDialogCommentFrame then S.StripTextures(_G.ReportCheatingDialogCommentFrame) end
        S.Button(_G.ReportCheatingDialogReportButton)
        S.Button(_G.ReportCheatingDialogCancelButton)
        S.Template(rcd, "Window")
        if _G.ReportCheatingDialogCommentFrameEditBox then S.EditBox(_G.ReportCheatingDialogCommentFrameEditBox) end
    end

    local bti = _G.BattleTagInviteFrame
    if bti then
        S.StripTextures(bti)
        S.Template(bti, "Window")
        for _, child in ipairs({ bti:GetChildren() }) do
            if child:IsObjectType("Button") then S.Button(child) end
        end
    end
end

S:RegisterEarly(Skin, "Battlenet")
