-- ╔══════════════════════════════════════════════════════════╗
-- ║  Identity.lua                                            ║
-- ║  Purpose: Which account-wide character records belong    ║
-- ║           to this character, for migration and cleanup.  ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)

local type = type

-- The key is AceDB's own, read back rather than rebuilt. With regional names
-- on, AceDB keys a character by its full name; otherwise by "Name - Realm".
---@return { charKey: string, name: string?, regional: boolean }|nil
function KE:GetPlayerIdentityParts()
    local keys = self.db and self.db.keys
    local charKey = keys and keys.char
    if self:IsSecretValue(charKey) or type(charKey) ~= "string" or charKey == "" then return nil end
    local regionalNames = _G.RegionalUniqueNamesEnabled
    if not (regionalNames and regionalNames()) then
        return { charKey = charKey, regional = false }
    end
    local name = UnitNameUnmodified("player")
    if self:IsSecretValue(name) or type(name) ~= "string" or name == "" then return nil end
    return { charKey = charKey, name = name, regional = true }
end

-- "owned" is the current key. "unresolved" may be this character's under an
-- older key shape or another surname, so it is neither adopted nor deleted.
-- "other" is proven to belong to another character.
---@param key any
---@param entry any
---@param identity table?
---@return "owned"|"other"|"unresolved"
function KE:ClassifyLegacyCharacterRecord(key, entry, identity)
    if type(identity) ~= "table" or type(entry) ~= "table" then return "unresolved" end
    if self:IsSecretValue(key) or type(key) ~= "string" then return "unresolved" end
    if key == identity.charKey then return "owned" end
    if not identity.regional then return "other" end
    -- A "Name - Realm" key was written before regional names applied.
    if key:find(" - ", 1, true) then return "unresolved" end
    local first = key:match("^(%S+)")
    if first == nil or first == identity.name then return "unresolved" end
    return "other"
end
