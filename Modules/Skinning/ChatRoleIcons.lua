local KE = select(2, ...)
local format = string.format

local LARGE_ROLE_ATLASES = {
    TANK    = "groupfinder-icon-role-large-tank",
    HEALER  = "groupfinder-icon-role-large-heal",
    DAMAGER = "groupfinder-icon-role-large-dps",
}
local ROLES = { "TANK", "HEALER", "DAMAGER" }

-- Which set can actually be drawn for one member. Only `circle` composes the
-- class into its string, so only `circle` degrades when the class is
-- unreadable -- and it degrades to the Blizzard role badge, because a class
-- circle without its class is not drawable. The other two never read the
-- class, so a secret class changes nothing for them.
function KE.ResolveChatRoleIconSet(set, hasClass)
    if set == "circle" and not hasClass then return "blizzard" end
    return set
end

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
-- circle is keyed ROLE_CLASS as well as ROLE: it draws the class ring, and a
-- member whose class is unreadable still gets the plain ROLE entry.
--
-- In an |A| escape the declared width IS the advance, so a two-atlas overlay
-- reserves the sum of both widths however far the second is offset back --
-- roughly 26 pixels of run for 14 pixels of art, which reads as a gap before
-- the name. Chat therefore draws the class ring alone; the Group Finder,
-- laying out real textures rather than an escape sequence, keeps the role
-- glyph on top of it.
function KE.BuildChatRoleIconStrings(set, classes)
    local out = {}
    for i = 1, #ROLES do
        local role = ROLES[i]
        if set == "modern" then
            out[role] = format("|T%s:14:14|t", KE.ROLE_ICONS[role])
        else
            out[role] = format("|A:%s:14:14|a", LARGE_ROLE_ATLASES[role])
        end
    end
    if set ~= "circle" then return out end

    for i = 1, #ROLES do
        local role = ROLES[i]
        for j = 1, #classes do
            local class = classes[j]
            -- The class token is concatenated as-is. The atlas lookup is
            -- case-insensitive and the key set is not uniformly upper case.
            out[role .. "_" .. class] = format(
                "|A:groupfinder-icon-class-color-%s:14:14|a", class)
        end
    end
    return out
end
