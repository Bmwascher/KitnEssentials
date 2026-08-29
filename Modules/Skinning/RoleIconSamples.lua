local KE = select(2, ...)
local format = string.format

-- Drawn by the `blizzard` set. Chat uses these same three.
local LARGE_ROLE_ATLASES = {
    TANK    = "groupfinder-icon-role-large-tank",
    HEALER  = "groupfinder-icon-role-large-heal",
    DAMAGER = "groupfinder-icon-role-large-dps",
}

-- The `circle` set composes a class ring with a role glyph, which an escape
-- cannot express: the declared width is the layout advance, so an overlay
-- reserves the sum of both widths. The ring alone is what the set is for, and
-- these three classes are blue, green and red, which keeps the tank/healer/dps
-- colour reading every other row has.
local CIRCLE_CLASS_ATLASES = {
    "groupfinder-icon-class-color-SHAMAN",
    "groupfinder-icon-class-color-MONK",
    "groupfinder-icon-class-color-DEATHKNIGHT",
}

local ROLES = { "TANK", "HEALER", "DAMAGER" }
local ICON_SIZE = 16

-- The dropdown label for one role icon set: three inline icons and no text.
-- The widget renders whatever string it is handed, so the sample IS the label
-- and no widget change is needed. Marking that dropdown searchable would break
-- this -- the search matcher strips |T|t escapes but not |A|a.
function KE.BuildRoleIconSample(set)
    local art = KE.ROLE_ICON_ART and KE.ROLE_ICON_ART[set]
    local parts = {}
    for i = 1, #ROLES do
        if art then
            parts[i] = format("|T%s:%d:%d|t", art[ROLES[i]], ICON_SIZE, ICON_SIZE)
        elseif set == "circle" then
            parts[i] = format("|A:%s:%d:%d|a", CIRCLE_CLASS_ATLASES[i], ICON_SIZE, ICON_SIZE)
        else
            parts[i] = format("|A:%s:%d:%d|a", LARGE_ROLE_ATLASES[ROLES[i]], ICON_SIZE, ICON_SIZE)
        end
    end
    return table.concat(parts, " ")
end
