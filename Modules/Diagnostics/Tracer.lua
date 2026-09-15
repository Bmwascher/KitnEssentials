-- ╔══════════════════════════════════════════════════════════╗
-- ║  Tracer.lua                                              ║
-- ║  Module: KE Frame Tracer                                 ║
-- ║  Purpose: /kes trace [Frame] [secs] prints every         ║
-- ║           geometry write on a frame with the addon file  ║
-- ║           that made it.                                  ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

local GetTime        = GetTime
local CreateFrame    = CreateFrame
local hooksecurefunc = hooksecurefunc
local debugstack     = debugstack
local issecretvalue  = issecretvalue
local GetMouseFoci   = GetMouseFoci
local GetMouseFocus  = GetMouseFocus
local wipe           = wipe

local pcall    = pcall
local type     = type
local select   = select
local tostring = tostring
local ipairs   = ipairs
local format   = string.format
local concat   = table.concat
local math_min = math.min

local DEFAULT_SECONDS = 6

local Tracer = {}

-- Hooks cannot be removed, so they are installed once per object and gated on
-- the trace being live. Weak keys let a traced frame be collected.
local hooked  = setmetatable({}, { __mode = "k" })
local targets = setmetatable({}, { __mode = "k" })
local traceUntil, frameNo = 0, 0
local ticker

local FRAME_METHODS = { "SetPoint", "ClearAllPoints", "SetWidth", "SetHeight", "SetSize", "SetAlpha", "Show", "Hide" }
local TEXT_METHODS  = { "SetPoint", "ClearAllPoints", "SetWidth", "SetAlpha", "SetFont" }

-- The first non-Blizzard, non-tracer line answers "whose code decided this";
-- Blizzard is only ever the messenger.
function Tracer.ParseCaller(stack)
    if type(stack) ~= "string" then return "?" end
    local first
    for line in stack:gmatch("[^\n]+") do
        local _, file, ln = line:match("AddOns(.)(.-):(%d+)")
        if file then
            file = file:gsub("[\"%]]", "")
            first = first or (file .. ":" .. ln)
            if not file:find("^Blizzard_") and not file:find("Diagnostics/Tracer%.lua$") then
                return file .. ":" .. ln
            end
        end
    end
    return first or "?"
end

-- Depth 4 skips this function, the hook body and the hook dispatcher; the
-- debugstack call stays here so the offset holds.
local function Caller()
    local ok, stack = pcall(debugstack, 4, 20, 0)
    if not ok then return "?" end
    return Tracer.ParseCaller(stack)
end

function Tracer.FormatArg(v)
    if issecretvalue(v) then return "<secret>" end
    local t = type(v)
    if t == "number" then return format("%.1f", v) end
    if t == "string" then return '"' .. v .. '"' end
    if t == "table" and v.GetName then return v:GetName() or "<unnamed frame>" end
    return tostring(v)
end

local function Hook(obj, label, methods)
    if hooked[obj] then return end
    hooked[obj] = true
    for _, m in ipairs(methods) do
        if type(obj[m]) == "function" then
            hooksecurefunc(obj, m, function(_, ...)
                if not targets[obj] or GetTime() > traceUntil then return end
                local n = select("#", ...)
                local parts = {}
                for i = 1, math_min(n, 5) do
                    parts[i] = Tracer.FormatArg((select(i, ...)))
                end
                KE:Print(format("|cff888888f%d|r %s.%s(%s)  <- %s",
                    frameNo, label, m, concat(parts, ", "), Caller()))
            end)
        end
    end
end

local function EndTrace()
    ticker:Hide()
    wipe(targets)
    KE:Print("Trace finished.")
end

local function StartTicker()
    if not ticker then
        ticker = CreateFrame("Frame")
        ticker:SetScript("OnUpdate", function()
            frameNo = frameNo + 1
            if GetTime() > traceUntil then EndTrace() end
        end)
    end
    ticker:Show()
end

function Tracer.Run(name, seconds)
    local f
    if name and name ~= "" then
        f = _G[name]
    else
        local foci = GetMouseFoci and GetMouseFoci()
        f = foci and foci[1]
        if not f and GetMouseFocus then f = GetMouseFocus() end
    end
    if type(f) ~= "table" or not f.GetObjectType then
        KE:Print("Trace: no frame " .. ((name and name ~= "") and ('named "' .. name .. '"') or "under the cursor") .. ".")
        return
    end
    seconds = seconds or DEFAULT_SECONDS
    local label = (f.GetName and f:GetName()) or "<unnamed>"
    Hook(f, label, FRAME_METHODS)
    targets[f] = true
    local text = f.Text or (f.GetFontString and f:GetFontString())
    if text then
        Hook(text, label .. ".Text", TEXT_METHODS)
        targets[text] = true
    end
    traceUntil = GetTime() + seconds
    StartTicker()
    KE:Print(format("Tracing %s for %d seconds -- do the thing now.", label, seconds))
end

KE.Tracer = Tracer
