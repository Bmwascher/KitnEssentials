local KE = select(2, ...)
local format = string.format
local gsub = string.gsub

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

-- Which cache keys one group member gets. Chat delivers a sender name that
-- may or may not carry a realm suffix, so the cache has to answer to both
-- forms. A same-realm member reads back from the unit API with NO realm, so
-- keying on the bare name alone leaves that member unreachable whenever chat
-- supplies the qualified form -- which is why role icons appeared for the
-- player, whose own realm is always readable, and for nobody else.
--
-- Returns the bare key and the qualified key. playerRealm stands in for a
-- missing member realm, since an absent realm IS the player's own realm.
--
-- The realm is NORMALIZED before it becomes a key. The unit API hands back a
-- display realm that keeps its spaces and punctuation, while a chat sender's
-- suffix has both stripped -- so a key built from the raw value reads
-- "Twisting Nether" against a sender's "TwistingNether" and never matches on
-- any multiword realm. Case is left alone: the suffix keeps its capitals.
-- Lua's %p is ASCII under the C locale, so bytes at or above 128 survive and
-- an accented realm still matches.
local function NormalizeRealm(realm)
    if type(realm) ~= "string" or realm == "" then return nil end
    local stripped = gsub(realm, "[%s%p]", "")
    return stripped ~= "" and stripped or nil
end

function KE.ChatRoleIconKeys(name, realm, playerRealm)
    if type(name) ~= "string" or name == "" then return nil end
    local qualifier = NormalizeRealm(realm) or NormalizeRealm(playerRealm)
    if not qualifier then return name end
    return name, name .. "-" .. qualifier
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
--
-- The art table is read directly rather than through the skinning helper that
-- the Group Finder painters share. This file exists so a spec can load the
-- builder without the skinning tree, and that loader supplies no KE.Skins at
-- all; one duplicated table lookup is the price of keeping it loadable alone.
function KE.BuildChatRoleIconStrings(set)
    local out = {}
    local art = KE.ROLE_ICON_ART and KE.ROLE_ICON_ART[set]
    for i = 1, #ROLES do
        local role = ROLES[i]
        if art then
            out[role] = format("|T%s:14:14|t", art[role])
        else
            out[role] = format("|A:%s:14:14|a", LARGE_ROLE_ATLASES[role])
        end
    end
    return out
end
