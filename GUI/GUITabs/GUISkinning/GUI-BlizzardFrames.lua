-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-BlizzardFrames.lua                                  ║
-- ║  Purpose: Config page for the Blizzard frame skins.      ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

local ipairs = ipairs

-- Key strings must match the second argument of each RegisterEarly call
-- in Modules/Skinning/Frames/. A mismatch silently disables nothing --
-- the gate reads Skins[key] ~= false, so an unknown key is always "on".
local FRAME_SKINS = {
    { key = "ChatConfig", text = "Chat Settings" },
    { key = "GMChat",     text = "GM Chat" },
}

local function GetDB()
    return KE.db.profile.Skinning.BlizzardFrames
end

GUIFrame:RegisterContent("SkinBlizzardFramesGeneral", function(scrollChild, yOffset)
    local db = GetDB()
    local card = GUIFrame:CreateCard(scrollChild, "Global Font Adjust", yOffset)

    local row = GUIFrame:CreateRow(card.content, Theme.rowHeightLast)
    local slider = GUIFrame:CreateSlider(row, "Font Size Adjust", {
        min = -4, max = 6, step = 1, value = db.FontOffset or 0,
        tooltip = "Grows or shrinks every font inside skinned windows together. 0 is the designed look.",
        callback = function(val)
            db.FontOffset = val
            if KE.Skins and KE.Skins.SetFontOffset then KE.Skins.SetFontOffset(val) end
        end,
    })
    row:AddWidget(slider, 1)
    card:AddRow(row, Theme.rowHeightLast, 0)

    return yOffset + card:GetContentHeight() + Theme.paddingMedium
end)

GUIFrame:RegisterContent("SkinBlizzardFramesFrames", function(scrollChild, yOffset)
    local db = GetDB()
    db.Skins = db.Skins or {}
    local card = GUIFrame:CreateCard(scrollChild, "Frame Skins", yOffset)

    -- Keyed on ANY-on, not all-on. With all-on semantics, unticking a single
    -- frame reads as master-off and collapses the card, hiding the user's
    -- own choices while the remaining skins keep applying.
    local anyOn = false
    for _, entry in ipairs(FRAME_SKINS) do
        if db.Skins[entry.key] ~= false then anyOn = true break end
    end

    card:AddHeaderToggle(anyOn, function(checked)
        for _, entry in ipairs(FRAME_SKINS) do
            -- Explicit branches. The `and false or nil` idiom can never
            -- yield false, which is exactly the value this table needs.
            if checked then
                db.Skins[entry.key] = nil
            else
                db.Skins[entry.key] = false
            end
        end
        KE:SkinningReloadPrompt()
        GUIFrame:RefreshContent()
    end)

    for _, entry in ipairs(FRAME_SKINS) do
        local row = GUIFrame:CreateRow(card.content, Theme.rowHeight)
        local check = GUIFrame:CreateCheckbox(row, entry.text, {
            value = db.Skins[entry.key] ~= false,
            callback = function(checked)
                if checked then
                    db.Skins[entry.key] = nil
                else
                    db.Skins[entry.key] = false
                end
                KE:SkinningReloadPrompt()
            end,
        })
        row:AddWidget(check, 1)
        card:AddRow(row, Theme.rowHeight, 0)
    end

    return yOffset + card:GetContentHeight() + Theme.paddingMedium
end)

GUIFrame:RegisterTabbedContent("SkinBlizzardFrames", {
    { id = "SkinBlizzardFramesGeneral", label = "General" },
    { id = "SkinBlizzardFramesFrames",  label = "Frames" },
}, {
    headerBuilder = function(scrollChild, yOffset)
        local db = GetDB()
        local card = GUIFrame:CreateCard(scrollChild, "Blizzard Frames", yOffset)
        card:AddHeaderToggle(db.Enabled == true, function(checked)
            db.Enabled = checked
            KE:SkinningReloadPrompt()
            GUIFrame:RefreshContent()
        end)
        local newOffset = yOffset + card:GetContentHeight() + Theme.paddingSmall
        -- Disabled collapses to the header bar alone: no tab strip, no page.
        return newOffset, db.Enabled ~= true
    end,
})
