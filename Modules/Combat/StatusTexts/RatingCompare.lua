-- ╔══════════════════════════════════════════════════════════╗
-- ║  RatingCompare.lua                                       ║
-- ║  Helper: which of four ratings is highest, also while    ║
-- ║  the game keeps them secret.                             ║
-- ╚══════════════════════════════════════════════════════════╝
-- Each rating fills a hidden bar. For a pair, a reverse bar hangs on the
-- first bar's fill edge and holds the second rating, so its fill starts at
-- the difference; a hit test at that point answers "first >= second". The
-- answer may be secret: it only reaches EvaluateColorValueFromBoolean, whose
-- result goes straight to the labels' alphas.

---@class KE
local KE = select(2, ...)

local CreateFrame = CreateFrame
local GetCursorPosition = GetCursorPosition
local issecretvalue = issecretvalue
local ipairs, pcall, type = ipairs, pcall, type

-- Flip to true to print why a hidden compare gave no answer.
local DEBUG_RC = false

local RATING_MAX = 50000
local RATING_PX = 4
-- Min -1, so a rating of 0 still has a fill edge to anchor on.
local BAR_WIDTH = (RATING_MAX + 1) * RATING_PX
local LAYER_X = -(BAR_WIDTH + 400)
local FAR = 1e7
local SETTLE = 0.1
-- Plain values with a tie, for the one-time self-check.
local CHECK_VALUES = { 30, 10, 30, 20 }

local RC = {}
KE.RatingCompare = RC

RC.PAIRS = { { 1, 2 }, { 1, 3 }, { 1, 4 }, { 2, 3 }, { 2, 4 }, { 3, 4 } }

-- Index of the highest of four plain ratings; a tie goes to the earlier one.
function RC.PlainPick(values)
    local best
    for i = 1, 4 do
        local v = values[i]
        if type(v) ~= "number" then return nil end
        if best == nil or v > values[best] then best = i end
    end
    return best
end

-- ge[p] answers "first >= second" for RC.PAIRS[p]; eval(b, ifTrue, ifFalse)
-- picks without reading b. A stat keeps 1 only by winning all three of its
-- pairs, and only the PlainPick winner does.
function RC.FoldAlphas(ge, eval, out)
    for i = 1, 4 do
        local a = 1
        for p, pair in ipairs(RC.PAIRS) do
            if pair[1] == i then
                a = eval(ge[p], a, 0)
            elseif pair[2] == i then
                a = eval(ge[p], 0, a)
            end
        end
        out[i] = a
    end
    return out
end

local layer
local bars, revs, probes = {}, {}, {}
local ge, alphas = {}, {}
local generation = 0
-- nil until the self-check has read plain answers; then true, or false for good.
local checked

local function Build()
    if layer then return end
    layer = CreateFrame("Frame", nil, UIParent)
    layer:SetSize(1, 1)
    layer:SetPoint("LEFT", UIParent, "LEFT", LAYER_X, 0)
    for i = 1, 4 do
        local bar = CreateFrame("StatusBar", nil, layer)
        bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        bar:SetStatusBarColor(0, 0, 0, 0)
        bar:SetSize(BAR_WIDTH, 1)
        bar:SetPoint("LEFT", layer, "LEFT", 0, 0)
        bar:SetMinMaxValues(-1, RATING_MAX)
        bar:SetValue(0)
        bars[i] = bar
    end
    for p, pair in ipairs(RC.PAIRS) do
        local rev = CreateFrame("StatusBar", nil, layer)
        rev:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        rev:SetStatusBarColor(0, 0, 0, 0)
        rev:SetReverseFill(true)
        rev:SetSize(BAR_WIDTH, 1)
        rev:SetPoint("RIGHT", bars[pair[1]]:GetStatusBarTexture(), "RIGHT", 0, 0)
        rev:SetMinMaxValues(-1, RATING_MAX)
        rev:SetValue(0)
        revs[p] = rev
        local probe = CreateFrame("Frame", nil, layer)
        probe:SetHeight(1)
        probe:SetPoint("LEFT", layer, "LEFT", -FAR, 0)
        probe:SetPoint("RIGHT", rev:GetStatusBarTexture(), "LEFT", 0, 0)
        probes[p] = probe
    end
end

local function Feed(values)
    for i = 1, 4 do
        if not pcall(bars[i].SetValue, bars[i], values[i]) then return false end
    end
    for p, pair in ipairs(RC.PAIRS) do
        if not pcall(revs[p].SetValue, revs[p], values[pair[2]]) then return false end
    end
    return true
end

-- A probe's right edge sits at X0 + RATING_PX * (first - second). The test
-- point is half a rating below X0, so whole ratings compare as ">=". The
-- measures must be plain; the answers may be secret and are never compared here.
local function ReadAnswers()
    local left = layer:GetLeft()
    local x = GetCursorPosition()
    local scale = layer:GetEffectiveScale()
    if type(left) ~= "number" or issecretvalue(left) or type(x) ~= "number" or issecretvalue(x)
        or type(scale) ~= "number" or issecretvalue(scale) or scale <= 0 then
        return false, "measure unreadable"
    end
    local reach = x / scale - (left - RATING_PX / 2)
    for p = 1, #probes do
        local probe = probes[p]
        local ok, over = pcall(probe.IsMouseOver, probe, FAR, -FAR, -FAR, reach)
        if not ok then return false, "hit test refused" end
        ge[p] = over
    end
    return true
end

local function SelfCheckVerdict()
    for p, pair in ipairs(RC.PAIRS) do
        local answer = ge[p]
        if issecretvalue(answer) then return nil end
        if answer ~= (CHECK_VALUES[pair[1]] >= CHECK_VALUES[pair[2]]) then return false end
    end
    return true
end

local function Refuse(done, reason)
    if DEBUG_RC then KE:Print("[RC] no answer: " .. reason) end
    done(false)
end

-- Supersedes any compare still settling.
function RC.Cancel()
    generation = generation + 1
end

-- done(true, alphas) or done(false). alphas is reused by the next compare.
function RC.Compare(values, done)
    local eval = C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean
    if type(eval) ~= "function" then return Refuse(done, "no boolean evaluator") end
    if checked == false then return Refuse(done, "self-check failed") end
    Build()
    RC.Cancel()
    local myGeneration = generation

    local function Answer()
        if not Feed(values) then return Refuse(done, "bar write refused") end
        C_Timer.After(SETTLE, function()
            if myGeneration ~= generation then return end
            local ok, reason = ReadAnswers()
            if not ok then return Refuse(done, reason) end
            done(true, RC.FoldAlphas(ge, eval, alphas))
        end)
    end

    if checked then return Answer() end
    if not Feed(CHECK_VALUES) then return Refuse(done, "bar write refused") end
    C_Timer.After(SETTLE, function()
        if myGeneration ~= generation then return end
        local ok, reason = ReadAnswers()
        if not ok then return Refuse(done, reason) end
        local verdict = SelfCheckVerdict()
        if verdict == nil then return Refuse(done, "self-check unreadable") end
        checked = verdict
        if not checked then return Refuse(done, "self-check failed") end
        Answer()
    end)
end
