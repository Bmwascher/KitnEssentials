---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

local AbbreviateNumbers = _G.AbbreviateNumbers
local BreakUpLargeNumbers = _G.BreakUpLargeNumbers
local C_StringUtil = _G.C_StringUtil
local math_floor = math.floor

-- Localize the secret-safe primitives once (both are AllowedWhenTainted):
--   TruncateWhenZero    — blanks a secret 0 to "" without branching on it.
--   FloorToNearestString — integer-to-string for a secret number. This is the
--     taint-safe replacement for string.format("%.0f", <secret>), which is NOT
--     safe: it forces a numeric conversion that throws on a secret value.
local issecretvalue = type(_G.issecretvalue) == "function" and _G.issecretvalue or nil
local TruncateWhenZero = C_StringUtil and type(C_StringUtil.TruncateWhenZero) == "function"
    and C_StringUtil.TruncateWhenZero or nil
local FloorToNearestString = C_StringUtil and type(C_StringUtil.FloorToNearestString) == "function"
    and C_StringUtil.FloorToNearestString or nil

local function IsSecretValue(value)
    return issecretvalue ~= nil and issecretvalue(value)
end

-- Format an absorb amount into a display string, secret-safe.
--   amount       number | nil | secret value
--   abbreviate   bool — K/M/B abbreviation
--   hideWhenZero bool — return "" at zero
-- Returns the display string ("" renders nothing).
-- NOTE: secret zero-blanking only works WITHOUT abbreviation — TruncateWhenZero
-- returns "" at zero without branching on the (secret) value. With abbreviation
-- on, a secret zero shows the abbreviated value.
local function FormatAbsorb(amount, abbreviate, hideWhenZero)
    if IsSecretValue(amount) then
        if hideWhenZero and not abbreviate and TruncateWhenZero then
            return TruncateWhenZero(amount)
        end
        if abbreviate and AbbreviateNumbers then
            return AbbreviateNumbers(amount)
        end
        -- Non-abbreviated secret with hideWhenZero off: floor-to-string (AllowedWhenTainted).
        if FloorToNearestString then
            return FloorToNearestString(amount)
        end
        return AbbreviateNumbers and AbbreviateNumbers(amount) or ""
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
