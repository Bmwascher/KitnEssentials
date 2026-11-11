-- ╔══════════════════════════════════════════════════════════╗
-- ║  Modules/Skinning/RestedXP/RestedXPWindowModel.lua       ║
-- ║  Purpose: What RestedXP is showing, as plain data: the   ║
-- ║           heading, progress, active steps and the list.  ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)

local ipairs, type = ipairs, type
local floor, math_max, math_min = math.floor, math.max, math.min

local Safe, Rules = KE.RestedXPSafe, KE.RestedXPRules
local Has, Dig, Run, Secret = Safe.Has, Safe.Dig, Safe.Run, Safe.Secret

local Model = {}
KE.RestedXPWindowModel = Model

local ACTIVE_SHOWN = 3
local PERCENT, ROUND = 100, 0.5
local TEXT_STEP = "Step %d"
local TEXT_NO_GUIDE = "No guide selected"

local kept

local function Same(text) return text end

local function Heading(rxp, guide, tint)
    local chapter = Has(rxp, "GetGuideName") and Run("WindowGuideName", rxp.GetGuideName, guide)
    local title = type(chapter) == "string" and chapter ~= "" and chapter
        or guide.title or guide.subgroup or guide.name
    if type(title) ~= "string" then return "" end
    return Rules.TintRange(title, tint)
end

-- Read as RestedXP's guide menu reads it: the display group where the guide has one.
local function Group(guide)
    local group = guide.groupdisplayname
    if type(group) ~= "string" then group = guide.group end
    return Rules.GuideGroupName(group)
end

local function ShownText(rxp, element, frame)
    local text = Dig(frame, "text")
    local shown = Has(text, "GetText") and text:GetText()
    if not Secret(shown) and type(shown) == "string" and shown ~= "" and shown ~= " " then return shown end
    local raw = element.text ~= " " and element.text or element.tooltipText or element.rawtext
    raw = type(raw) == "string" and raw or ""
    return Has(rxp, "ReplaceNpcIds") and Run("WindowNpc", rxp.ReplaceNpcIds, raw, element) or raw
end

local function Glyph(rxp, element, frame)
    local icon = Dig(frame, "icon")
    local glyph = Has(icon, "GetText") and icon:GetText()
    if Secret(glyph) then glyph = "" end
    if Has(icon, "IsShown") and icon:IsShown() == false then glyph = "" end
    if type(glyph) ~= "string" then glyph = element.icon or Dig(rxp, "icons", element.tag) or "" end
    return glyph
end

local function Row(rxp, element, opts)
    local frame = element.frame
    local shown = ShownText(rxp, element, frame)
    if opts.iconText then shown = opts.iconText(shown) end
    local text, glyph, nested = Rules.Lifted(shown, Glyph(rxp, element, frame))
    local button = Dig(frame, "button")
    local done = Has(button, "GetChecked") and button:GetChecked() or element.completed or element.skip
    local have, need, bags = Rules.Counted(element.tag, element.id, element.qty, text, opts.getCount)
    return {
        text = text, icon = glyph, done = done and true or false, source = Dig(frame, "text"),
        have = have, need = need, bags = bags, nested = nested,
    }
end

local function ActiveSteps(rxp, hidden)
    local out = {}
    if hidden then Rules.PruneHidden(hidden) end
    for _, step in ipairs(Dig(rxp, "RXPFrame", "activeSteps") or {}) do
        if step.active and not step.hidewindow and not step.hidetip and not (hidden and hidden[step]) then
            out[#out + 1] = step
            if #out == ACTIVE_SHOWN then break end
        end
    end
    return out
end

local function StepLabel(step)
    if step.title and step.title ~= "" then return step.title end
    return TEXT_STEP:format(step.index)
end

local function Listed(v2)
    if not Has(v2, "BuildGuideStepsSnapshot") then return nil end
    local snapshot = Run("WindowSteps", v2.BuildGuideStepsSnapshot, v2, true)
    if type(Dig(snapshot, "rows")) ~= "table" then return nil end
    local list = {}
    for _, row in ipairs(snapshot.rows) do
        if not row.hidden then
            list[#list + 1] = { index = row.index, line = row.text:match("^[^\n]*"), done = row.complete and true or false }
        end
    end
    return list
end

local function Steps(rxp, guide)
    if not (kept and kept.guide == guide) then
        local list = Listed(rxp.v2)
        if not list then return nil end
        kept = { guide = guide, list = list }
    end
    return kept.list
end

function Model.Stale()
    kept = nil
end

function Model.LineText(entry)
    if not entry.text then entry.text = Rules.Plain(entry.line) end
    return entry.text
end

function Model.NoGuide()
    return { heading = TEXT_NO_GUIDE, steps = {}, current = {}, list = {}, first = 1, empty = true }
end

function Model.Read(rxp, opts)
    local guide = rxp.currentGuide
    if not guide or guide.empty then return nil end
    local model = {
        heading = Heading(rxp, guide, opts.tint or Same), group = Group(guide),
        steps = {}, current = {}, guide = guide,
    }
    local step = Has(rxp, "GetGuideProgress") and Run("WindowProgress", rxp.GetGuideProgress) or nil
    local total = type(guide.steps) == "table" and #guide.steps or 0
    if step and total > 0 then
        model.step, model.total = step, total
        model.fraction = math_min(1, math_max(0, step / total))
        model.percent = floor(model.fraction * PERCENT + ROUND)
    end
    local after = step or 0
    for _, activeStep in ipairs(ActiveSteps(rxp, opts.hidden)) do
        local rows = {}
        for _, element in ipairs(activeStep.elements or {}) do
            if element.text or element.rawtext or element.tooltipText then
                local row = Row(rxp, element, opts)
                row.step = activeStep
                rows[#rows + 1] = row
            end
        end
        model.steps[#model.steps + 1] = { label = StepLabel(activeStep), rows = rows, source = activeStep }
        model.current[activeStep.index] = true
        if activeStep.index > after then after = activeStep.index end
    end
    model.list = Steps(rxp, guide) or {}
    model.after, model.first = after, Rules.FirstAfter(model.list, after)
    return model
end
