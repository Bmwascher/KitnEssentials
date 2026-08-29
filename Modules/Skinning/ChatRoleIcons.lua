local KE = select(2, ...)
local format = string.format

local LARGE_ROLE_ATLASES = {
    TANK    = "groupfinder-icon-role-large-tank",
    HEALER  = "groupfinder-icon-role-large-heal",
    DAMAGER = "groupfinder-icon-role-large-dps",
}
local ROLES = { "TANK", "HEALER", "DAMAGER" }

-- The identity refusal, as its own decision so it can be tested without a
-- fake of the group API. The cache is keyed by name, so a member whose role
-- or name is unreadable has nothing safe to draw and nothing safe to key it
-- by; a secret realm is refused for the same reason, since it forms the
-- second key. A nil or empty realm is the same-realm case and is fine.
--
-- Returns name, realm on acceptance; nil to skip the member.
function KE.AcceptChatMember(role, name, realm)
    if not (KE:IsSafeValue(role) and KE:IsSafeValue(name)) then return nil end
    if KE:IsSecretValue(realm) then return nil end
    if type(role) ~= "string" or type(name) ~= "string" then return nil end
    if realm ~= nil and type(realm) ~= "string" then return nil end
    if realm == "" then realm = nil end
    return name, realm
end

-- One table per SET, not one per session. The previous builder returned early
-- if it had ever run, so whichever set was built first would have been the
-- only set chat could ever show.
--
-- circle draws the Blizzard role badge here, the same as `blizzard`. It is the
-- only set whose Group Finder art composes two glyphs, and chat cannot express
-- that: in an |A| escape the declared width IS the advance, so an overlay
-- reserves the sum of both widths however far the second is offset back --
-- roughly 26 pixels of run for 14 pixels of art, which reads as a gap before
-- the name. Drawing the class ring alone instead loses the role, which is the
-- one thing a role icon exists to show.
--
-- Chat therefore needs no class at all, which is why nothing here reads one.
function KE.BuildChatRoleIconStrings(set)
    local out = {}
    for i = 1, #ROLES do
        local role = ROLES[i]
        if set == "modern" then
            out[role] = format("|T%s:14:14|t", KE.ROLE_ICONS[role])
        else
            out[role] = format("|A:%s:14:14|a", LARGE_ROLE_ATLASES[role])
        end
    end
    return out
end
