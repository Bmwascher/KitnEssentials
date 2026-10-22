-- ╔══════════════════════════════════════════════════════════╗
-- ║  VersionCompare.lua                                      ║
-- ║  Purpose: Numeric version comparison shared by the       ║
-- ║           version check and the skin suppression layer.  ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)

local tonumber, type = tonumber, type
local math_max = math.max

-- Splits a version string into numeric segments. Anything unparseable
-- yields an empty list, which sorts LOWER than every real version.
local function segments(v)
    local out = {}
    if type(v) ~= "string" then return out end
    for part in v:gmatch("%d+") do
        out[#out + 1] = tonumber(part)
    end
    return out
end

--- Numeric-segment version compare. A missing segment counts as 0, so
--- "8.6" and "8.6.0" are equal. String compare would put "8.6.10" below
--- "8.6.4"; this does not.
---@return number -1 | 0 | 1
function KE:CompareVersions(a, b)
    local sa, sb = segments(a), segments(b)
    for i = 1, math_max(#sa, #sb) do
        local x, y = sa[i] or 0, sb[i] or 0
        if x < y then return -1 end
        if x > y then return 1 end
    end
    return 0
end
