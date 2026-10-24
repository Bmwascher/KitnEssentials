-- ╔══════════════════════════════════════════════════════════╗
-- ║  RoleIconSamples.lua                                     ║
-- ║  Purpose: The saved role icon set's read path, and the   ║
-- ║           inline samples that label its dropdown.        ║
-- ╚══════════════════════════════════════════════════════════╝

local KE = select(2, ...)
local S = KE.Skins
local format = string.format
local pairs = pairs

-- The one place the art decision is made. Returns a texture path for an art
-- set, or nil for a set that draws atlases instead. Exported so the routing
-- can be tested without a mocked frame tree; the Group Finder painters stay
-- file-local to Frames/LFG.lua and reachable only through Blizzard's hooks.
function S.RoleArtPath(set, role)
    local art = KE.ROLE_ICON_ART[set]
    return art and art[role] or nil
end

-- Derived from the art table, so this list never drifts from the art. The two
-- non-art keys are the only literals. A new set still needs its own entry in
-- the GUI's display order and in the spec loader's mirror of the art table.
local ROLE_ICON_SETS = { blizzard = true, circle = true }
for set in pairs(KE.ROLE_ICON_ART) do ROLE_ICON_SETS[set] = true end

-- The single read path for the saved role-icon-set key. LFG.lua, Chat.lua and
-- the GUI callback all come through GetRoleIconSet, so an absent or
-- unrecognized value cannot mean different things on different surfaces.
function S.GetRoleIconSet()
    local bs = KE.db and KE.db.profile and KE.db.profile.Skinning
        and KE.db.profile.Skinning.BlizzardFrames
    local set = bs and bs.RoleIconSet
    return ROLE_ICON_SETS[set] and set or "modern"
end

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
-- color reading every other row has.
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
