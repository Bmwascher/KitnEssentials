local KE = select(2, ...)
local S = KE.Skins
local _G = _G

function S.LegacyTreePage()
    local page = _G.LegacySystemFrame and _G.LegacySystemFrame.TreePage
    if not page or S.data(page).skinned then return end
    S.FontStrings(page)
    local traits = page.LegacyTreeTraitPanel
    if traits then
        S.Button(traits.ApplyButton)
        S.EditBox(traits.SearchBox)
    end
    S.data(page).skinned = true
end
