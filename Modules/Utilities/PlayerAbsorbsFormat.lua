---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

local AbbreviateNumbers = _G.AbbreviateNumbers
local BreakUpLargeNumbers = _G.BreakUpLargeNumbers
local C_StringUtil = _G.C_StringUtil
local math_floor = math.floor

local function IsSecretValue(value)
    return type(_G.issecretvalue) == "function" and _G.issecretvalue(value)
end

-- Format an absorb amount into a display string, secret-safe.
--   amount       number | nil | secret value
--   abbreviate   bool — K/M/B abbreviation
--   hideWhenZero bool — return "" at zero
-- Returns the display string ("" renders nothing).
-- NOTE: secret zero-blanking only works WITHOUT abbreviation — TruncateWhenZero
-- returns "" at zero without branching on the (secret) value. With abbreviation
-- on, a secret zero shows the abbreviated value (faithful to the reference).
local function FormatAbsorb(amount, abbreviate, hideWhenZero)
    if IsSecretValue(amount) then
        if hideWhenZero and not abbreviate
            and C_StringUtil and type(C_StringUtil.TruncateWhenZero) == "function" then
            return C_StringUtil.TruncateWhenZero(amount)
        end
        if abbreviate and AbbreviateNumbers then
            return AbbreviateNumbers(amount)
        end
        return string.format("%.0f", amount) -- AllowedWhenTainted
    end

    amount = tonumber(amount) or 0
    if amount < 0 then amount = 0 end
    if hideWhenZero and amount <= 0.0001 then
        return ""
    end
    if abbreviate and AbbreviateNumbers then
        return AbbreviateNumbers(amount)
    end
    if BreakUpLargeNumbers then
        return BreakUpLargeNumbers(math_floor(amount + 0.5))
    end
    return tostring(math_floor(amount + 0.5))
end

KE.PlayerAbsorbsFormat = { Format = FormatAbsorb }
