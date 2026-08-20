-- ╔══════════════════════════════════════════════════════════╗
-- ║  ChatLinks.lua                                           ║
-- ║  Module: Chat Link Decoration                            ║
-- ║  Purpose: Prepend an icon to chat hyperlinks and render  ║
-- ║           the profession quality tier as a coloured digit║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

local CL = KitnEssentials:NewModule("ChatLinks", "AceEvent-3.0")

local ceil = ceil
local format = format

---------------------------------------------------------------------------------
-- DB Helper
---------------------------------------------------------------------------------

function CL:UpdateDB()
    self.db = KE.db.profile.Skinning.ChatLinks
end

---------------------------------------------------------------------------------
-- Icon strings
---------------------------------------------------------------------------------

-- Inline texture escapes, cropped 5/64 on each edge to trim the icon border.
-- keepRatio crops the longer axis further instead of stretching the art.
local ICON_TEMPLATE = "|T%s:%d:%d:0:0:64:64:5:59:5:59|t"
local ICON_RATIO_TEMPLATE = "|T%s:%d:%d:0:0:64:64:%d:%d:%d:%d|t"
local ICON_DEFAULT_SIZE = 14

function CL.BuildIconString(texture, height, width, keepRatio)
    if keepRatio and height and height > 0 and width and width > 0 then
        local proportionality = height / width
        local offset = ceil((54 - 54 * proportionality) / 2)
        if proportionality > 1 then
            return format(ICON_RATIO_TEMPLATE, texture, height, width,
                5 + offset, 59 - offset, 5, 59)
        elseif proportionality < 1 then
            return format(ICON_RATIO_TEMPLATE, texture, height, width,
                5, 59, 5 + offset, 59 - offset)
        end
    end

    width = width or height
    return format(ICON_TEMPLATE, texture, height or ICON_DEFAULT_SIZE,
        width or ICON_DEFAULT_SIZE)
end

---------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------

function CL:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

function CL:OnEnable()
    if not self.db then self:UpdateDB() end
end

function CL:OnDisable()
end
