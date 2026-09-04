---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

local string_format = string.format
local string_gsub = string.gsub
local table_concat = table.concat
local math_floor = math.floor

local DEFAULT_ORDER = {
    "crit", "haste", "mastery", "vers", "leech", "avoidance", "speed",
}

-- Gap between a label and its figure, so every row keeps one rhythm.
local LABEL_GAP = " "

-- Bodies carry the placeholder the engine fills. The value itself never
-- enters the string, which is what keeps a restricted figure renderable.
local BODY = {
    percent = function(decimals) return "%." .. decimals .. "f%%" end,
    rating = function() return "%.0f" end,
    both = function(decimals) return "%.0f (%." .. decimals .. "f%%)" end,
}

-- Which figures each body consumes, in the order its placeholders appear.
local NEEDS = {
    percent = { "percent" },
    rating = { "rating" },
    both = { "rating", "percent" },
}

-- Text that lands INSIDE a template the engine fills later. A percent sign
-- would be read there as a placeholder and a pipe as the start of a colour
-- escape, so both are doubled. Labels are user-typed, so this is reachable.
local function EscapeText(text)
    if text == nil then return "" end
    local escaped = string_gsub(tostring(text), "%%", "%%%%")
    escaped = string_gsub(escaped, "|", "||")
    return escaped
end

-- Versatility is the only figure built by ADDING two getters, and addition is
-- what a restricted value refuses. Either operand being restricted makes the
-- sum illegal, so the last clean total stands in. Falling back to the rating
-- bonus alone is wrong: it drops the non-rating contribution silently and the
-- result still looks like a real number.
local function ResolveVersatility(ratingBonus, baseBonus, cached, isSecret)
    if ratingBonus == nil or baseBonus == nil then return cached, cached end
    if isSecret(ratingBonus) or isSecret(baseBonus) then return cached, cached end
    local total = ratingBonus + baseBonus
    return total, total
end

-- Draw order: the saved order first, filtered to the stats switched on, then
-- any key the saved order never mentioned. Without that second pass a stale
-- saved order would hide a stat outright rather than merely misplace it.
local function VisibleKeys(order, stats)
    local seen, keys = {}, {}
    for index = 1, #(order or {}) do
        local key = order[index]
        if stats[key] and not seen[key] then
            seen[key] = true
            if stats[key].Shown then keys[#keys + 1] = key end
        end
    end
    for index = 1, #DEFAULT_ORDER do
        local key = DEFAULT_ORDER[index]
        if not seen[key] and stats[key] and stats[key].Shown then
            keys[#keys + 1] = key
        end
    end
    return keys
end

-- Build the template and the figures that fill it. No figure is inspected
-- here; the only test applied is against nil, which is legal on a restricted
-- value and means the figure is genuinely absent rather than merely hidden.
local function BuildRows(entries, opts)
    local rows, vals = {}, {}
    -- Clamped to a whole number here rather than trusted from the profile: the
    -- decimals value lands in a format specifier, and a fractional one builds
    -- "%.1.5f" -- which errors on every repaint until the setting changes.
    local decimals = math_floor((opts.decimals or 2) + 0.5)
    if decimals < 0 then decimals = 0 elseif decimals > 3 then decimals = 3 end
    for index = 1, #entries do
        local item = entries[index]
        local mode = BODY[item.valueMode] and item.valueMode or "percent"
        local body = BODY[mode](decimals)
        local needs = NEEDS[mode]
        local ready = true
        for slot = 1, #needs do
            if item[needs[slot]] == nil then ready = false end
        end
        if ready then
            for slot = 1, #needs do
                vals[#vals + 1] = item[needs[slot]]
            end
        else
            body = "?"
        end
        local valueHex = opts.coloredValues and item.hex or "ffffff"
        if opts.showLabel then
            rows[#rows + 1] = string_format("|cff%s%s%s|r%s|cff%s%s|r",
                item.hex, EscapeText(item.label), EscapeText(opts.separator),
                LABEL_GAP, valueHex, body)
        else
            rows[#rows + 1] = string_format("|cff%s%s|r", valueHex, body)
        end
    end
    return table_concat(rows, "\n"), vals
end

KE.SecondaryStatsFormat = {
    DEFAULT_ORDER = DEFAULT_ORDER,
    EscapeText = EscapeText,
    ResolveVersatility = ResolveVersatility,
    VisibleKeys = VisibleKeys,
    BuildRows = BuildRows,
}
