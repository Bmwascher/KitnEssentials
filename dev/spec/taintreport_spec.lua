-- luacheck: std lua51+busted
local helpers = require("dev.spec._helpers")

local originalGlobals = {}
local globalsToRestore = {
    "CreateFrame", "canaccessvalue", "canaccesstable", "next", "debugstack",
    "time", "date", "GetBuildInfo", "C_AddOns", "UIParent",
    "UISpecialFrames", "GameFontNormal", "KitnEssentials",
}

local function restoreHarnessGlobals()
    before_each(function()
        for _, name in ipairs(globalsToRestore) do
            originalGlobals[name] = _G[name]
        end
    end)

    after_each(function()
        for _, name in ipairs(globalsToRestore) do
            _G[name] = originalGlobals[name]
        end
    end)
end

local function shallowKeys(value)
    local keys = {}
    for key in pairs(value) do
        keys[#keys + 1] = key
    end
    table.sort(keys)
    return keys
end

local function storedSource(site, options)
    options = options or {}
    return {
        site = site,
        keLines = options.keLines or { site },
        keLinesOmitted = options.keLinesOmitted or 0,
        observedSamples = options.observedSamples or 1,
    }
end

local function storedGroup(action, options)
    options = options or {}
    local sources = options.sources or {}
    local observed = 0
    for _, source in ipairs(sources) do
        observed = observed + source.observedSamples
    end
    local walks = options.walks
    if walks == nil then walks = math.max(1, observed) end
    local stackUnavailable = options.stackUnavailable
    if stackUnavailable == nil then stackUnavailable = walks - observed end
    local count = options.count or walks
    return {
        event = options.event or "ADDON_ACTION_BLOCKED",
        action = action,
        firstSeen = options.firstSeen or 1799999900,
        lastSeen = options.lastSeen or 1799999950,
        count = count,
        walks = walks,
        notWalked = options.notWalked or (count - walks),
        stackUnavailable = stackUnavailable,
        stackInputTruncated = options.stackInputTruncated or 0,
        sourceUnavailable = options.sourceUnavailable or 0,
        sourceSamplesOmitted = options.sourceSamplesOmitted or 0,
        sources = sources,
    }
end

local function storedLog(groups, options)
    options = options or {}
    return {
        schema = options.schema or 1,
        savedAt = options.savedAt or 1800000000,
        groups = groups,
        omitted = options.omitted or 0,
        supersededRestored = options.supersededRestored or 0,
    }
end

local function loadTaintReport(options)
    options = options or {}

    local rawNext = originalGlobals.next or next
    local registeredEvents = {}
    local valueGuardCalls = {}
    local tableGuardCalls = {}
    local nextVisits = {}
    local printed = {}
    local addonCalls = {}
    local frameCreateCount = 0
    local frameHideCount = 0
    local lastEditText
    local now = options.now or 1800000000
    local stackValue = options.stack or "Interface/AddOns/KitnEssentials/Core/Main.lua:101: in function <...>"
    local stackError = options.stackError
    local stackCalls = 0
    local valueAccess = options.valueAccess or function()
        return true
    end
    local tableAccess = options.tableAccess or function()
        return true
    end
    local eventFrame

    local function makeObject(kind, name)
        local object = {
            _kind = kind,
            _name = name,
            _scripts = {},
            _shown = false,
            _value = 0,
            _min = 0,
            _max = 0,
            _width = 720,
        }

        function object:RegisterEvent(event)
            registeredEvents[#registeredEvents + 1] = event
        end
        function object:SetScript(scriptName, callback)
            self._scripts[scriptName] = callback
        end
        function object:GetScript(scriptName)
            return self._scripts[scriptName]
        end
        function object:CreateTexture()
            return makeObject("Texture")
        end
        function object:CreateFontString()
            return makeObject("FontString")
        end
        function object:Show()
            self._shown = true
        end
        function object:Hide()
            if self._name == "KE_TaintReportFrame" then
                frameHideCount = frameHideCount + 1
            end
            self._shown = false
            local callback = self._scripts.OnHide
            if callback then callback(self) end
        end
        function object:IsShown()
            return self._shown
        end
        function object:SetText(text)
            if self._kind == "EditBox" then
                lastEditText = text
            end
            self._text = text
        end
        function object:GetText()
            return self._text
        end
        function object:SetValue(value)
            self._value = value
            local callback = self._scripts.OnValueChanged
            if callback then callback(self, value) end
        end
        function object:GetValue()
            return self._value
        end
        function object:SetMinMaxValues(minimum, maximum)
            self._min, self._max = minimum, maximum
        end
        function object:GetMinMaxValues()
            return self._min, self._max
        end
        function object:GetWidth()
            return self._width
        end
        function object:SetWidth(width)
            self._width = width
        end
        function object:SetSize(width)
            self._width = width
        end

        local noOps = {
            "SetBackdrop", "SetBackdropColor", "SetBackdropBorderColor",
            "SetHeight", "SetPoint", "ClearAllPoints", "SetAllPoints",
            "SetColorTexture", "SetTexture", "SetRotation", "SetVertexColor",
            "SetTexelSnappingBias", "SetSnapToPixelGrid", "SetJustifyH",
            "SetFont", "SetTextColor", "SetShadowColor", "SetShadowOffset",
            "SetMovable", "EnableMouse", "SetFrameStrata", "SetClampedToScreen",
            "RegisterForDrag", "StartMoving", "StopMovingOrSizing",
            "SetOrientation", "SetThumbTexture", "SetMultiLine", "SetMaxLetters",
            "SetAutoFocus", "SetScrollChild", "SetVerticalScroll",
            "EnableMouseWheel", "SetParent",
        }
        for _, method in ipairs(noOps) do
            object[method] = function()
            end
        end
        return object
    end

    _G.UIParent = makeObject("Frame", "UIParent")
    _G.UISpecialFrames = {}
    _G.GameFontNormal = {
        GetFont = function()
            return "Fonts\\FRIZQT__.TTF"
        end,
    }
    _G.KitnEssentials = options.KitnEssentials
    _G.CreateFrame = function(kind, name)
        local object = makeObject(kind, name)
        if not eventFrame then
            eventFrame = object
        end
        if name == "KE_TaintReportFrame" then
            frameCreateCount = frameCreateCount + 1
        end
        return object
    end
    _G.canaccessvalue = function(value)
        valueGuardCalls[#valueGuardCalls + 1] = value
        return valueAccess(value)
    end
    _G.canaccesstable = function(value)
        tableGuardCalls[#tableGuardCalls + 1] = value
        return tableAccess(value)
    end
    _G.next = function(value, key)
        nextVisits[value] = (nextVisits[value] or 0) + 1
        return rawNext(value, key)
    end
    _G.debugstack = function(...)
        stackCalls = stackCalls + 1
        if stackError then error(stackError) end
        if type(stackValue) == "function" then
            return stackValue(...)
        end
        return stackValue
    end
    _G.time = function()
        return now
    end
    _G.date = function()
        return options.reportDate or "2027-01-15 08:00:00"
    end
    _G.GetBuildInfo = function()
        return options.clientVersion or "12.1.0", options.clientBuild or "69497",
            options.clientDate or "Jan 15 2027", 120100
    end

    local addons = options.addons or {}
    _G.C_AddOns = {
        GetNumAddOns = function()
            addonCalls[#addonCalls + 1] = { "count" }
            if options.addonCountError then error(options.addonCountError) end
            if options.addonCount ~= nil then return options.addonCount end
            return #addons
        end,
        GetAddOnInfo = function(index)
            addonCalls[#addonCalls + 1] = { "info", index }
            local addon = addons[index] or {}
            return addon.name, addon.title, addon.notes or "", true,
                addon.reason or "", addon.security or "INSECURE"
        end,
        IsAddOnLoaded = function(index)
            addonCalls[#addonCalls + 1] = { "loaded", index }
            local addon
            if type(index) == "number" then
                addon = addons[index]
            else
                for _, candidate in ipairs(addons) do
                    if candidate.name == index then addon = candidate; break end
                end
            end
            if options.loadedResult then
                return options.loadedResult(index, addon)
            end
            return addon and addon.loaded or false, addon and addon.loaded or false
        end,
        GetAddOnMetadata = function(index, field)
            addonCalls[#addonCalls + 1] = { "metadata", index, field }
            if index == "KitnEssentials" and field == "Version" then
                return options.addonVersion or "4.5.0"
            end
            local addon = type(index) == "number" and addons[index] or nil
            if not addon then
                for _, candidate in ipairs(addons) do
                    if candidate.name == index then addon = candidate; break end
                end
            end
            return addon and addon.version or "unavailable"
        end,
    }

    local KE = {
        Print = function(_, message)
            printed[#printed + 1] = message
        end,
        GetFontPath = function()
            return "Fonts\\FRIZQT__.TTF"
        end,
        GetThemeColor = function(_, key)
            local colors = {
                accent = { 1, 0, 0.549, 1 },
                border = { 0, 0, 0, 1 },
                textPrimary = { 1, 1, 1, 1 },
                textSecondary = { 0.8, 0.8, 0.8, 1 },
                bgDark = { 0.03, 0.03, 0.03, 0.9 },
                bgMedium = { 0.05, 0.05, 0.05, 0.95 },
            }
            return colors[key]
        end,
        ApplyFramePosition = function()
        end,
    }

    local function loadProduction(reducedCounter)
        if not reducedCounter then
            helpers.loadModule("Modules/Diagnostics/TaintReport.lua", KE)
            return
        end

        local handle = assert(io.open("Modules/Diagnostics/TaintReport.lua", "rb"))
        local source = handle:read("*a")
        handle:close()
        local replacements
        source, replacements = source:gsub("MAX_COUNTER%s*=%s*2147483647", "MAX_COUNTER = 7")
        assert.equals(1, replacements)
        local chunk = assert(loadstring(source, "@Modules/Diagnostics/TaintReport.lua"))
        chunk("KitnEssentials", KE)
    end

    loadProduction(options.reducedCounter)

    local state = {
        KE = KE,
        taintReport = KE.TaintReport,
        eventFrame = eventFrame,
        printed = printed,
        registeredEvents = registeredEvents,
        valueGuardCalls = valueGuardCalls,
        tableGuardCalls = tableGuardCalls,
        nextVisits = nextVisits,
        addonCalls = addonCalls,
    }
    function state.fire(event, attribution, action)
        return eventFrame:GetScript("OnEvent")(eventFrame, event, attribution, action)
    end
    function state.logout()
        return state.fire("PLAYER_LOGOUT")
    end
    function state.initialize(db)
        db = db or { global = {} }
        state.db = db
        KE.TaintReport.Initialize(db)
        return db
    end
    function state.run(command)
        lastEditText = nil
        KE.TaintReport.RunCommand(command or "")
        return lastEditText
    end
    function state.setNow(value)
        now = value
    end
    function state.setValueAccess(callback)
        valueAccess = callback
    end
    function state.setTableAccess(callback)
        tableAccess = callback
    end
    function state.setStack(value, thrown)
        stackValue = value
        stackError = thrown
    end
    function state.stackCalls()
        return stackCalls
    end
    function state.frameCreateCount()
        return frameCreateCount
    end
    function state.frameHideCount()
        return frameHideCount
    end
    function state.lastEditText()
        return lastEditText
    end
    return state
end

describe("TaintReport capture and access guards", function()
    restoreHarnessGlobals()

    it("registers only both protected-action events and logout", function()
        local state = loadTaintReport()
        assert.same({
            "ADDON_ACTION_BLOCKED",
            "ADDON_ACTION_FORBIDDEN",
            "PLAYER_LOGOUT",
        }, state.registeredEvents)
    end)

    it("exposes only Initialize and RunCommand", function()
        local state = loadTaintReport()
        assert.same({ "Initialize", "RunCommand" }, shallowKeys(state.taintReport))
    end)

    it("drops unreadable attribution before comparison, grouping, or stack work", function()
        local state = loadTaintReport({
            valueAccess = function(value)
                return value ~= "KitnEssentials"
            end,
        })
        assert.has_no.errors(function()
            state.fire("ADDON_ACTION_BLOCKED", "KitnEssentials", "RAW_ACTION_SENTINEL")
        end)
        state.initialize()
        local report = assert(state.run(""))
        assert.is_truthy(report:find("Inaccessible attribution events: 1", 1, true))
        assert.is_truthy(report:find("No KE-attributed protected actions were captured.", 1, true))
        assert.is_nil(report:find("RAW_ACTION_SENTINEL", 1, true))
        assert.equals(0, state.stackCalls())
    end)

    it("ignores oversized and exact-length non-KE attribution without walking stacks", function()
        local state = loadTaintReport()
        state.fire("ADDON_ACTION_BLOCKED", string.rep("K", 200), "oversized")
        state.fire("ADDON_ACTION_BLOCKED", "OtherEssential", "same-length")
        state.initialize()
        local report = assert(state.run(""))
        assert.is_truthy(report:find("No KE-attributed protected actions were captured.", 1, true))
        assert.is_nil(report:find("oversized", 1, true))
        assert.is_nil(report:find("same-length", 1, true))
        assert.equals(0, state.stackCalls())
    end)

    it("uses a fixed action label when the function payload is unreadable", function()
        local sentinel = setmetatable({}, {
            __index = function()
                error("unreadable action was indexed")
            end,
        })
        local state = loadTaintReport({
            valueAccess = function(value)
                return value ~= sentinel
            end,
        })
        state.fire("ADDON_ACTION_FORBIDDEN", "KitnEssentials", sentinel)
        state.initialize()
        local report = assert(state.run(""))
        assert.is_truthy(report:find("<function unavailable>", 1, true))
        assert.is_nil(report:find(tostring(sentinel), 1, true))
    end)

    it("counts thrown and inaccessible stacks without raw string work", function()
        local inaccessibleStack = "INACCESSIBLE_STACK_SENTINEL"
        local state = loadTaintReport({ stackError = "stack failed" })
        state.fire("ADDON_ACTION_BLOCKED", "KitnEssentials", "firstAction")
        state.setStack(inaccessibleStack)
        state.setValueAccess(function(value)
            return value ~= inaccessibleStack
        end)
        state.fire("ADDON_ACTION_BLOCKED", "KitnEssentials", "secondAction")
        state.initialize()
        local report = assert(state.run(""))
        assert.is_truthy(report:find("Stack unavailable samples: 2", 1, true))
        assert.is_truthy(report:find("firstAction", 1, true))
        assert.is_truthy(report:find("secondAction", 1, true))
        assert.is_nil(report:find(inaccessibleStack, 1, true))
        assert.equals(2, state.stackCalls())
    end)

    it("does not print or install finished strings rejected by the value guard", function()
        local state = loadTaintReport({
            valueAccess = function(value)
                if type(value) ~= "string" then return true end
                if value:find("A protected action attributed", 1, true) then return false end
                if value:find("KitnEssentials Taint Report", 1, true) == 1 then return false end
                return true
            end,
        })
        state.initialize()
        state.fire("ADDON_ACTION_BLOCKED", "KitnEssentials", "BlockedFunction")
        assert.equals(0, #state.printed)
        assert.is_nil(state.run(""))
        assert.equals(0, state.frameCreateCount())
    end)

    it("keeps direct access wrappers and never wraps either predicate directly", function()
        local handle = assert(io.open("Modules/Diagnostics/TaintReport.lua", "rb"))
        local source = handle:read("*a")
        handle:close()
        assert.is_truthy(source:find("local function DirectCanAccess(value)", 1, true))
        assert.is_truthy(source:find("local function DirectCanAccessTable(value)", 1, true))
        assert.is_nil(source:find("pcall(canaccessvalue", 1, true))
        assert.is_nil(source:find("pcall(canaccesstable", 1, true))
    end)
end)

describe("TaintReport parsing, dedupe, and capture bounds", function()
    restoreHarnessGlobals()

    local pathCases = {
        "Interface/AddOns/KitnEssentials/Core/Main.lua:101: in function <...>",
        "[Interface/AddOns/KitnEssentials/Core/Main.lua]:101: in function <...>",
        "Interface\\AddOns\\KitnEssentials\\Core\\Main.lua:101: in function <...>",
        "[string \"@Interface/AddOns/KitnEssentials/Core/Main.lua\"]:101: in function <...>",
    }

    it("selects the first non-diagnostic KE frame in every supported path form", function()
        for index, expected in ipairs(pathCases) do
            local state = loadTaintReport({
                stack = "Interface/AddOns/KitnEssentials/Modules/Diagnostics/TaintReport.lua:900\n"
                    .. expected,
            })
            state.fire("ADDON_ACTION_BLOCKED", "KitnEssentials", "path" .. index)
            state.initialize()
            local report = assert(state.run(""))
            assert.is_truthy(report:find(expected, 1, true))
            assert.is_nil(report:find("TaintReport.lua:900", 1, true))
        end
    end)

    it("retains six distinct KE lines in stack order and discloses later lines", function()
        local lines = {
            "Interface/AddOns/KitnEssentials/Core/One.lua:1",
            "Interface/AddOns/KitnEssentials/Core/Two.lua:2",
            "Interface/AddOns/KitnEssentials/Core/Three.lua:3",
            "Interface/AddOns/KitnEssentials/Core/Four.lua:4",
            "Interface/AddOns/KitnEssentials/Core/Five.lua:5",
            "Interface/AddOns/KitnEssentials/Core/Six.lua:6",
            "Interface/AddOns/KitnEssentials/Core/Seven.lua:7",
            "Interface/AddOns/KitnEssentials/Core/Eight.lua:8",
        }
        local state = loadTaintReport({ stack = table.concat(lines, "\n") })
        state.fire("ADDON_ACTION_BLOCKED", "KitnEssentials", "manyLines")
        state.initialize()
        local report = assert(state.run(""))
        local prior = 0
        for index = 1, 6 do
            local position = assert(report:find(lines[index], 1, true))
            assert.is_true(position > prior)
            prior = position
        end
        assert.is_nil(report:find(lines[7], 1, true))
        assert.is_nil(report:find(lines[8], 1, true))
        assert.is_truthy(report:find("KE lines omitted: 2", 1, true))
    end)

    it("reports source frame unavailable when only diagnostic KE frames remain", function()
        local state = loadTaintReport({
            stack = "Interface/AddOns/KitnEssentials/Modules/Diagnostics/TaintReport.lua:10\n"
                .. "Interface/AddOns/OtherAddon/Main.lua:20",
        })
        state.fire("ADDON_ACTION_BLOCKED", "KitnEssentials", "selfOnly")
        state.initialize()
        local report = assert(state.run(""))
        assert.is_truthy(report:find("source frame unavailable", 1, true))
        assert.is_nil(report:find("OtherAddon", 1, true))
    end)

    it("dedupes equal scope, event, and action while separating every changed dimension", function()
        local restoredGroup = {
            event = "ADDON_ACTION_BLOCKED", action = "same", firstSeen = 1799999900,
            lastSeen = 1799999950, count = 1, walks = 1, notWalked = 0,
            stackUnavailable = 1, stackInputTruncated = 0,
            sourceUnavailable = 0, sourceSamplesOmitted = 0, sources = {},
        }
        local db = { global = { TaintLog = {
            schema = 1, savedAt = 1800000000, groups = { restoredGroup },
            omitted = 0, supersededRestored = 0,
        } } }
        local state = loadTaintReport()
        state.initialize(db)
        state.fire("ADDON_ACTION_BLOCKED", "KitnEssentials", "same")
        state.fire("ADDON_ACTION_BLOCKED", "KitnEssentials", "same")
        state.fire("ADDON_ACTION_FORBIDDEN", "KitnEssentials", "same")
        state.fire("ADDON_ACTION_BLOCKED", "KitnEssentials", "different")
        local report = assert(state.run(""))
        assert.equals(3, select(2, report:gsub("Action: same", "")))
        assert.is_truthy(report:find("Occurrences: 2", 1, true))
        assert.is_truthy(report:find("[current] ADDON_ACTION_FORBIDDEN", 1, true))
        assert.is_truthy(report:find("Action: different", 1, true))
        assert.is_truthy(report:find("[restored] ADDON_ACTION_BLOCKED", 1, true))
    end)

    it("walks only the first five matching occurrences", function()
        local state = loadTaintReport()
        for _ = 1, 6 do
            state.fire("ADDON_ACTION_BLOCKED", "KitnEssentials", "repeat")
        end
        state.initialize()
        local report = assert(state.run(""))
        assert.equals(5, state.stackCalls())
        assert.is_truthy(report:find("Occurrences: 6", 1, true))
        assert.is_truthy(report:find("Unsampled occurrences: 1", 1, true))
    end)

    it("merges equal sampled sites, retains three sites, and discloses later samples", function()
        local sites = { "Alpha", "Alpha", "Beta", "Gamma", "Delta" }
        local cursor = 0
        local state = loadTaintReport({
            stack = function()
                cursor = cursor + 1
                return "Interface/AddOns/KitnEssentials/Core/" .. sites[cursor] .. ".lua:1"
            end,
        })
        for _ = 1, 5 do
            state.fire("ADDON_ACTION_BLOCKED", "KitnEssentials", "sources")
        end
        state.initialize()
        local report = assert(state.run(""))
        assert.is_truthy(report:find("Alpha.lua:1", 1, true))
        assert.is_truthy(report:find("(2 observations)", 1, true))
        assert.is_truthy(report:find("Beta.lua:1", 1, true))
        assert.is_truthy(report:find("Gamma.lua:1", 1, true))
        assert.is_nil(report:find("Delta.lua:1", 1, true))
        assert.is_truthy(report:find("Source samples omitted: 1", 1, true))
    end)

    it("caps and sanitizes action input before it can inject report lines", function()
        local raw = string.rep("A", 500) .. "\nINJECTED_REPORT_LINE" .. string.rep("Z", 100)
        local state = loadTaintReport()
        state.fire("ADDON_ACTION_BLOCKED", "KitnEssentials", raw)
        state.initialize()
        local report = assert(state.run(""))
        local action = assert(report:match("Action: ([^\n]+)"))
        assert.is_true(#action <= 160)
        assert.is_truthy(action:find("[truncated]", 1, true))
        assert.is_nil(report:find("INJECTED_REPORT_LINE", 1, true))
        assert.is_nil(report:find(string.rep("Z", 20), 1, true))
    end)

    it("caps raw stacks, candidate lines, and retained source lines with one disclosure", function()
        local longLine = "Interface/AddOns/KitnEssentials/Core/Long.lua:1 " .. string.rep("L", 1400)
        local rawStack = longLine .. "\n" .. string.rep("R", 17000)
        local state = loadTaintReport({ stack = rawStack })
        state.fire("ADDON_ACTION_BLOCKED", "KitnEssentials", "longStack")
        state.initialize()
        local report = assert(state.run(""))
        local site = assert(report:match("Sampled source 1 %([^\n]+%): ([^\n]+)"))
        assert.is_true(#site <= 300)
        assert.is_truthy(site:find("[truncated]", 1, true))
        assert.is_truthy(report:find("Stack input truncated samples: 1", 1, true))
        assert.is_nil(report:find(string.rep("R", 100), 1, true))
    end)

    it("evicts the oldest restored group before refusing new current evidence", function()
        local function restored(action, seen)
            return {
                event = "ADDON_ACTION_BLOCKED", action = action,
                firstSeen = seen, lastSeen = seen, count = 1, walks = 1,
                notWalked = 0, stackUnavailable = 1, stackInputTruncated = 0,
                sourceUnavailable = 0, sourceSamplesOmitted = 0, sources = {},
            }
        end
        local db = { global = { TaintLog = {
            schema = 1, savedAt = 1800000000,
            groups = { restored("old-restored", 1799999900), restored("new-restored", 1799999950) },
            omitted = 0, supersededRestored = 0,
        } } }
        local state = loadTaintReport()
        state.initialize(db)
        for index = 1, 23 do
            state.fire("ADDON_ACTION_BLOCKED", "KitnEssentials", "current-" .. index)
        end
        state.fire("ADDON_ACTION_BLOCKED", "KitnEssentials", "new-current")
        local report = assert(state.run(""))
        assert.is_nil(report:find("old-restored", 1, true))
        assert.is_truthy(report:find("new-restored", 1, true))
        assert.is_truthy(report:find("new-current", 1, true))
        assert.is_nil(report:find("Refused action groups", 1, true))
    end)

    it("bounds refused identities and the total tracked key budget", function()
        local state = loadTaintReport()
        for index = 1, 25 do
            state.fire("ADDON_ACTION_BLOCKED", "KitnEssentials", "accepted-" .. index)
        end
        for index = 1, 51 do
            state.fire("ADDON_ACTION_BLOCKED", "KitnEssentials", "refused-" .. index)
        end
        state.initialize()
        local report = assert(state.run(""))
        assert.is_truthy(report:find("Refused action groups: at least 50", 1, true))
        assert.is_truthy(report:find("Refused occurrences: 51", 1, true))
        assert.equals(25, state.stackCalls())
    end)

    it("saturates count and keeps derived unsampled evidence as a lower bound", function()
        local state = loadTaintReport({ reducedCounter = true })
        for _ = 1, 10 do
            state.fire("ADDON_ACTION_BLOCKED", "KitnEssentials", "saturated")
        end
        state.initialize()
        local report = assert(state.run(""))
        assert.is_truthy(report:find("Occurrences: at least 7", 1, true))
        assert.is_truthy(report:find("Unsampled occurrences: at least 2", 1, true))
        assert.equals(5, state.stackCalls())
    end)

    it("emits one notification for a repeated burst and leaves unsampled events unattributed", function()
        local state = loadTaintReport()
        state.initialize()
        for _ = 1, 30 do
            state.fire("ADDON_ACTION_BLOCKED", "KitnEssentials", "burst")
        end
        local report = assert(state.run(""))
        assert.equals(1, #state.printed)
        assert.equals(5, state.stackCalls())
        assert.is_truthy(report:find("Occurrences: 30", 1, true))
        assert.is_truthy(report:find("Unsampled occurrences: 25", 1, true))
        assert.is_truthy(report:find("(5 observations)", 1, true))
        assert.is_nil(report:find("(30 observations)", 1, true))
    end)
end)

describe("TaintReport persistence", function()
    restoreHarnessGlobals()

    it("keeps an empty slot absent and makes pre-attachment logout a no-op", function()
        local state = loadTaintReport()
        assert.has_no.errors(function() state.logout() end)
        local db = state.initialize()
        assert.is_nil(db.global.TaintLog)
        state.logout()
        assert.is_nil(db.global.TaintLog)
    end)

    it("canonicalizes a valid restore into fresh copies without replaying initialization", function()
        local originalLine = "Interface/AddOns/KitnEssentials/Core/Restore.lua:8"
        local originalGroup = storedGroup("restored-only", {
            sources = { storedSource(originalLine) },
        })
        local originalStore = storedLog({ originalGroup }, { omitted = 2, supersededRestored = 3 })
        local db = { global = { TaintLog = originalStore } }
        local state = loadTaintReport()
        state.initialize(db)
        local canonical = assert(db.global.TaintLog)
        assert.not_equals(originalStore, canonical)
        assert.not_equals(originalGroup, canonical.groups[1])
        assert.not_equals(originalGroup.sources, canonical.groups[1].sources)
        assert.not_equals(originalGroup.sources[1].keLines,
            canonical.groups[1].sources[1].keLines)
        assert.same({ "groups", "omitted", "savedAt", "schema", "supersededRestored" },
            shallowKeys(canonical))
        originalGroup.action = "MUTATED"
        originalGroup.sources[1].keLines[1] = "MUTATED_LINE"
        local report = assert(state.run(""))
        assert.is_truthy(report:find("restored-only", 1, true))
        assert.is_truthy(report:find(originalLine, 1, true))
        assert.is_nil(report:find("MUTATED", 1, true))
        state.logout()
        assert.equals(canonical, db.global.TaintLog)
        state.initialize({ global = { TaintLog = storedLog({ storedGroup("ignored") }) } })
        assert.equals(canonical, db.global.TaintLog)
    end)

    it("persists dirty current evidence as bounded schema copies", function()
        local state = loadTaintReport()
        local db = state.initialize()
        state.fire("ADDON_ACTION_BLOCKED", "KitnEssentials", "dirty")
        state.fire("ADDON_ACTION_BLOCKED", "KitnEssentials", "dirty")
        state.logout()
        local store = assert(db.global.TaintLog)
        assert.equals(1, store.schema)
        assert.equals(1800000000, store.savedAt)
        assert.equals(1, #store.groups)
        assert.equals(2, store.groups[1].count)
        assert.is_true(#store.groups <= 10)
        assert.same({
            "action", "count", "event", "firstSeen", "lastSeen", "notWalked",
            "sourceSamplesOmitted", "sourceUnavailable", "sources",
            "stackInputTruncated", "stackUnavailable", "walks",
        }, shallowKeys(store.groups[1]))
    end)

    it("selects current groups first and then newest restored groups deterministically", function()
        local restored = {}
        for index = 1, 10 do
            restored[index] = storedGroup("restored-" .. index, {
                lastSeen = 1799999900 + index,
                firstSeen = 1799999800 + index,
            })
        end
        local db = { global = { TaintLog = storedLog(restored) } }
        local state = loadTaintReport()
        state.initialize(db)
        state.fire("ADDON_ACTION_FORBIDDEN", "KitnEssentials", "current-b")
        state.fire("ADDON_ACTION_BLOCKED", "KitnEssentials", "current-a")
        state.logout()
        local groups = db.global.TaintLog.groups
        assert.equals(10, #groups)
        assert.equals("current-a", groups[1].action)
        assert.equals("current-b", groups[2].action)
        assert.equals("restored-10", groups[3].action)
        assert.equals("restored-3", groups[10].action)
        assert.equals(2, db.global.TaintLog.omitted)
    end)

    it("persists a current/restored collision once and carries supersession through reload", function()
        local rows = { storedGroup("collision", { lastSeen = 1799999990 }) }
        for index = 1, 9 do rows[#rows + 1] = storedGroup("other-" .. index) end
        local db = { global = { TaintLog = storedLog(rows) } }
        local state = loadTaintReport()
        state.initialize(db)
        state.fire("ADDON_ACTION_BLOCKED", "KitnEssentials", "collision")
        state.logout()
        local store = db.global.TaintLog
        assert.equals(10, #store.groups)
        assert.equals(1, store.supersededRestored)
        local collisions = 0
        for _, group in ipairs(store.groups) do
            if group.action == "collision" then collisions = collisions + 1 end
        end
        assert.equals(1, collisions)

        local second = loadTaintReport()
        second.initialize({ global = { TaintLog = store } })
        local secondReport = assert(second.run(""))
        assert.is_truthy(secondReport:find("Restored groups superseded: 1", 1, true))
    end)

    it("classifies non-admitted and evicted restored rows exactly once", function()
        local restored = {
            storedGroup("collision", { lastSeen = 1799999900 }),
            storedGroup("different", { lastSeen = 1799999910 }),
        }
        local db = { global = { TaintLog = storedLog(restored) } }
        local state = loadTaintReport()
        for index = 1, 24 do
            local action = index == 1 and "collision" or "preinit-" .. index
            state.fire("ADDON_ACTION_BLOCKED", "KitnEssentials", action)
        end
        state.initialize(db)
        state.fire("ADDON_ACTION_BLOCKED", "KitnEssentials", "post-init")
        state.logout()
        local store = assert(db.global.TaintLog)
        assert.equals(1, store.supersededRestored)
        assert.equals(16, store.omitted)
        local secondDB = { global = { TaintLog = store } }
        local second = loadTaintReport()
        second.initialize(secondDB)
        second.logout()
        assert.equals(1, secondDB.global.TaintLog.supersededRestored)
        assert.equals(16, secondDB.global.TaintLog.omitted)
    end)

    it("fails closed at every persisted table boundary before traversal", function()
        local function boundaryStore(targetName, target)
            local source = storedSource("Interface/AddOns/KitnEssentials/Core/S.lua:1")
            local group = storedGroup("boundary", { sources = { source } })
            local store = storedLog({ group })
            if targetName == "store" then return target end
            if targetName == "groups" then store.groups = target
            elseif targetName == "group" then store.groups[1] = target
            elseif targetName == "sources" then group.sources = target
            elseif targetName == "source" then group.sources[1] = target
            elseif targetName == "keLines" then source.keLines = target end
            return store
        end

        for _, boundary in ipairs({ "store", "groups", "group", "sources", "source", "keLines" }) do
            for _, mode in ipairs({ "value-false", "value-throw", "table-false", "table-throw" }) do
                local target = setmetatable({}, {
                    __index = function() error("boundary indexed: " .. boundary) end,
                })
                local state = loadTaintReport({
                    valueAccess = function(value)
                        if value ~= target then return true end
                        if mode == "value-throw" then error("value guard") end
                        return mode ~= "value-false"
                    end,
                    tableAccess = function(value)
                        if value ~= target then return true end
                        if mode == "table-throw" then error("table guard") end
                        return mode ~= "table-false"
                    end,
                })
                local db = { global = { TaintLog = boundaryStore(boundary, target) } }
                assert.has_no.errors(function() state.initialize(db) end)
                assert.is_nil(db.global.TaintLog)
                assert.is_nil(state.nextVisits[target])
                if mode:find("value", 1, true) then
                    local tableCalled = false
                    for _, value in ipairs(state.tableGuardCalls) do
                        if value == target then tableCalled = true end
                    end
                    assert.is_false(tableCalled)
                end
            end
        end
    end)

    it("rejects inaccessible scalars at representative schema depths", function()
        for _, fieldPath in ipairs({ "savedAt", "omitted", "supersededRestored",
            "action", "count", "site", "observedSamples", "keLine" }) do
            local sentinel = {}
            local source = storedSource("Interface/AddOns/KitnEssentials/Core/S.lua:1")
            local group = storedGroup("scalar", { sources = { source } })
            local store = storedLog({ group })
            if fieldPath == "savedAt" then store.savedAt = sentinel
            elseif fieldPath == "omitted" then store.omitted = sentinel
            elseif fieldPath == "supersededRestored" then store.supersededRestored = sentinel
            elseif fieldPath == "action" then group.action = sentinel
            elseif fieldPath == "count" then group.count = sentinel
            elseif fieldPath == "site" then source.site = sentinel
            elseif fieldPath == "observedSamples" then source.observedSamples = sentinel
            else source.keLines[1] = sentinel end
            local state = loadTaintReport({
                valueAccess = function(value)
                    if value == sentinel then error("scalar guard") end
                    return true
                end,
            })
            local db = { global = { TaintLog = store } }
            assert.has_no.errors(function() state.initialize(db) end)
            assert.is_nil(db.global.TaintLog)
        end
    end)

    it("rejects malformed top-level arrays within eleven raw next visits", function()
        local cases = {
            function() return { schema = 2, savedAt = 1800000000, groups = {}, omitted = 0, supersededRestored = 0 } end,
            function() return storedLog("not-a-table") end,
            function() local rows = {}; for i = 1, 11 do rows[i] = storedGroup("g" .. i) end; return storedLog(rows) end,
            function() return storedLog({ [1] = storedGroup("one"), [3] = storedGroup("three") }) end,
            function() return storedLog({ [1.5] = storedGroup("fraction") }) end,
            function() return storedLog({ storedGroup("expired", { firstSeen = 1, lastSeen = 1 }) }) end,
        }
        for _, makeStore in ipairs(cases) do
            local store = makeStore()
            local groups = type(store) == "table" and store.groups or nil
            local state = loadTaintReport()
            local db = { global = { TaintLog = store } }
            state.initialize(db)
            assert.is_nil(db.global.TaintLog)
            if type(groups) == "table" then
                assert.is_true((state.nextVisits[groups] or 0) <= 11)
            end
        end
    end)

    it("rejects over-cap nested arrays within four and seven raw next visits", function()
        local sources = {}
        for index = 1, 4 do
            sources[index] = storedSource("Interface/AddOns/KitnEssentials/Core/S" .. index .. ".lua:1")
        end
        local sourceGroup = storedGroup("too-many-sources", { sources = sources, walks = 4 })
        local sourceState = loadTaintReport()
        local sourceDB = { global = { TaintLog = storedLog({ sourceGroup }) } }
        sourceState.initialize(sourceDB)
        assert.is_nil(sourceDB.global.TaintLog)
        assert.is_true((sourceState.nextVisits[sources] or 0) <= 4)

        local lines = {}
        for index = 1, 7 do
            lines[index] = "Interface/AddOns/KitnEssentials/Core/L" .. index .. ".lua:1"
        end
        local lineSource = storedSource(lines[1], { keLines = lines })
        local lineGroup = storedGroup("too-many-lines", { sources = { lineSource } })
        local lineState = loadTaintReport()
        local lineDB = { global = { TaintLog = storedLog({ lineGroup }) } }
        lineState.initialize(lineDB)
        assert.is_nil(lineDB.global.TaintLog)
        assert.is_true((lineState.nextVisits[lines] or 0) <= 7)
    end)

    it("drops unknown fields while keeping valid dense schema data", function()
        local source = storedSource("Interface/AddOns/KitnEssentials/Core/Known.lua:1")
        local group = storedGroup("known", { sources = { source } })
        local store = storedLog({ group })
        store.unknown = { huge = string.rep("x", 10000) }
        group.unknown = { nested = true }
        source.unknown = "value"
        local db = { global = { TaintLog = store } }
        local state = loadTaintReport()
        state.initialize(db)
        local canonical = assert(db.global.TaintLog)
        assert.is_nil(canonical.unknown)
        assert.is_nil(canonical.groups[1].unknown)
        assert.is_nil(canonical.groups[1].sources[1].unknown)
        assert.equals("known", canonical.groups[1].action)
    end)

    it("drops malformed, expired, duplicate, oversized, and skewed rows without refreshing age", function()
        local valid = storedGroup("valid", { lastSeen = 1799999950 })
        local duplicate = storedGroup("valid", { lastSeen = 1799999960 })
        local invalid = storedGroup("bad\naction")
        local expired = storedGroup("expired", { firstSeen = 1, lastSeen = 1 })
        local oversized = storedGroup(string.rep("x", 161))
        local future = storedGroup("future", {
            firstSeen = 1800000301, lastSeen = 1800000301,
        })
        local beyondSaved = storedGroup("beyond-saved", {
            firstSeen = 1800000300, lastSeen = 1800000301,
        })
        local exactBoundary = storedGroup("boundary", {
            firstSeen = 1800000300, lastSeen = 1800000300,
        })
        local store = storedLog({ valid, duplicate, invalid, expired, oversized,
            future, beyondSaved, exactBoundary })
        local db = { global = { TaintLog = store } }
        local state = loadTaintReport()
        state.initialize(db)
        local canonical = assert(db.global.TaintLog)
        assert.equals(2, #canonical.groups)
        local actions = {
            [canonical.groups[1].action] = true,
            [canonical.groups[2].action] = true,
        }
        assert.is_true(actions.valid)
        assert.is_true(actions.boundary)
        assert.equals(6, canonical.omitted)
        local validLastSeen
        for _, group in ipairs(canonical.groups) do
            if group.action == "valid" then validLastSeen = group.lastSeen end
        end
        assert.equals(1799999950, validLastSeen)
        local identity = canonical
        state.logout()
        assert.equals(identity, db.global.TaintLog)
    end)

    it("rejects malformed store counters and preserves saturated carry values", function()
        for _, bad in ipairs({ -1, 1.5, 2147483648 }) do
            local db = { global = { TaintLog = storedLog({ storedGroup("bad-counter") }, {
                omitted = bad,
            }) } }
            local state = loadTaintReport()
            state.initialize(db)
            assert.is_nil(db.global.TaintLog)
        end

        local db = { global = { TaintLog = storedLog({ storedGroup("carry") }, {
            omitted = 7, supersededRestored = 7,
        }) } }
        local state = loadTaintReport({ reducedCounter = true })
        state.initialize(db)
        local report = assert(state.run(""))
        assert.is_truthy(report:find("Persisted groups omitted: at least 7", 1, true))
        assert.is_truthy(report:find("Restored groups superseded: at least 7", 1, true))
    end)

    it("never persists refused keys, raw stacks, UI state, or current-only counters", function()
        local state = loadTaintReport({ stack = "RAW_STACK_SENTINEL\nInterface/AddOns/KitnEssentials/Core/Safe.lua:1" })
        local db = state.initialize()
        for index = 1, 25 do
            state.fire("ADDON_ACTION_BLOCKED", "KitnEssentials", "accepted-" .. index)
        end
        state.fire("ADDON_ACTION_BLOCKED", "KitnEssentials", "REFUSED_SENTINEL")
        state.run("")
        state.logout()
        local serialized = table.concat((function()
            local values = {}
            for _, group in ipairs(db.global.TaintLog.groups) do
                values[#values + 1] = group.action
                for _, source in ipairs(group.sources) do values[#values + 1] = source.site end
            end
            return values
        end)(), "\n")
        assert.is_nil(serialized:find("REFUSED_SENTINEL", 1, true))
        assert.is_nil(serialized:find("RAW_STACK_SENTINEL", 1, true))
        assert.is_nil(db.global.TaintLog.refusedByEvent)
        assert.is_nil(db.global.TaintLog.frame)
    end)

    it("clear resets memory, persistence, notifications, and text without eager UI", function()
        local preinit = loadTaintReport()
        preinit.fire("ADDON_ACTION_BLOCKED", "KitnEssentials", "pending")
        local db = preinit.initialize()
        preinit.logout()
        assert.is_table(db.global.TaintLog)
        preinit.run("clear")
        assert.is_nil(db.global.TaintLog)
        assert.equals(0, preinit.frameCreateCount())
        local report = assert(preinit.run(""))
        assert.is_truthy(report:find("No KE-attributed protected actions were captured.", 1, true))
        assert.is_nil(report:find("pending", 1, true))
    end)

    it("allows a later valid initialization after an invalid database", function()
        local state = loadTaintReport()
        assert.has_no.errors(function() state.taintReport.Initialize(false) end)
        local db = { global = {} }
        state.taintReport.Initialize(db)
        state.fire("ADDON_ACTION_BLOCKED", "KitnEssentials", "late-attach")
        state.logout()
        assert.equals("late-attach", db.global.TaintLog.groups[1].action)
    end)
end)

describe("TaintReport report and lazy dialog", function()
    restoreHarnessGlobals()

    local function countAddonCalls(calls, kind, numericOnly)
        local count = 0
        for _, call in ipairs(calls) do
            if call[1] == kind and (not numericOnly or type(call[2]) == "number") then
                count = count + 1
            end
        end
        return count
    end

    it("reports an explicit empty state and bounded header metadata", function()
        local state = loadTaintReport()
        state.initialize()
        local report = assert(state.run(""))
        assert.is_truthy(report:find("KitnEssentials Taint Report", 1, true))
        assert.is_truthy(report:find("Addon version: 4.5.0", 1, true))
        assert.is_truthy(report:find("Client build: 69497", 1, true))
        assert.is_truthy(report:find("Report time: 2027-01-15 08:00:00", 1, true))
        assert.is_truthy(report:find("Blizzard attribution is not proof", 1, true))
        assert.is_truthy(report:find("No KE-attributed protected actions were captured.", 1, true))
    end)

    it("renders current groups before restored groups with explicit scopes", function()
        local db = { global = { TaintLog = storedLog({ storedGroup("restored") }) } }
        local state = loadTaintReport()
        state.initialize(db)
        state.fire("ADDON_ACTION_BLOCKED", "KitnEssentials", "current")
        local report = assert(state.run(""))
        local current = assert(report:find("[current]", 1, true))
        local restored = assert(report:find("[restored]", 1, true))
        assert.is_true(current < restored)
    end)

    it("emits every nonzero global and aggregate disclosure without zero noise", function()
        local lossSource = storedSource("Interface/AddOns/KitnEssentials/Core/Loss.lua:1", {
            keLinesOmitted = 1, observedSamples = 1,
        })
        local lossGroup = storedGroup("restored-loss", {
            count = 7, walks = 5, notWalked = 2, stackUnavailable = 1,
            stackInputTruncated = 1, sourceUnavailable = 1,
            sourceSamplesOmitted = 2, sources = { lossSource },
        })
        local addons = {}
        for index = 1, 301 do
            addons[index] = {
                name = "Loaded" .. index, title = "Loaded " .. index,
                version = "1", loaded = true,
            }
        end
        local state = loadTaintReport({ addons = addons, addonCount = 1025 })
        state.initialize({ global = { TaintLog = storedLog({ lossGroup }, {
            omitted = 2, supersededRestored = 3,
        }) } })
        local unreadableAction = setmetatable({}, {})
        state.setValueAccess(function(value)
            if value == "UNREADABLE_ATTR" then return false end
            if value == unreadableAction then return false end
            return true
        end)
        state.fire("ADDON_ACTION_BLOCKED", "UNREADABLE_ATTR", "ignored")
        state.fire("ADDON_ACTION_BLOCKED", "KitnEssentials", unreadableAction)
        local lossReport = assert(state.run(""))
        for _, expected in ipairs({
            "Unsampled occurrences: 2",
            "Stack unavailable samples: 1",
            "Stack input truncated samples: 1",
            "Source unavailable samples: 1",
            "Source samples omitted: 2",
            "KE lines omitted: 1",
        }) do
            assert.is_truthy(lossReport:find(expected, 1, true), expected)
        end
        for index = 1, 24 do
            state.fire("ADDON_ACTION_BLOCKED", "KitnEssentials", "fill-" .. index)
        end
        state.fire("ADDON_ACTION_BLOCKED", "KitnEssentials", "refused")
        local report = assert(state.run(""))
        for _, expected in ipairs({
            "Inaccessible attribution events: 1",
            "Unavailable action payloads: 1",
            "Refused action groups: 1",
            "Refused occurrences: 1",
            "Persisted groups omitted: 3",
            "Restored groups superseded: 3",
            "Addon indices unscanned: 1",
            "Loaded addons omitted: 1",
        }) do
            assert.is_truthy(report:find(expected, 1, true), expected)
        end

        local empty = loadTaintReport()
        empty.initialize()
        local emptyReport = assert(empty.run(""))
        assert.is_nil(emptyReport:find("Refused occurrences:", 1, true))
        assert.is_nil(emptyReport:find("Stack unavailable samples:", 1, true))
        assert.is_nil(emptyReport:find("Persisted groups omitted:", 1, true))
    end)

    it("queries addon state only when the report command runs", function()
        local state = loadTaintReport()
        state.fire("ADDON_ACTION_BLOCKED", "KitnEssentials", "capture-only")
        state.initialize()
        assert.equals(0, #state.addonCalls)
        state.run("")
        assert.is_true(#state.addonCalls > 0)
    end)

    it("bounds dynamic environment strings before sorting and formatting", function()
        local longName = string.rep("N", 1100) .. "\nINJECTED_ADDON_LINE"
        local longTitle = string.rep("T", 1100)
        local longVersion = string.rep("V", 1100)
        local state = loadTaintReport({
            addonVersion = string.rep("K", 1100),
            clientBuild = string.rep("B", 1100),
            reportDate = string.rep("D", 1100),
            addons = {{
                name = longName, title = longTitle, version = longVersion, loaded = true,
            }},
        })
        state.initialize()
        local report = assert(state.run(""))
        assert.is_truthy(report:find("[truncated]", 1, true))
        assert.is_nil(report:find("INJECTED_ADDON_LINE", 1, true))
        for line in report:gmatch("[^\n]+") do
            if line:find("Loaded addon:", 1, true) then
                assert.is_true(#line <= 1024)
            end
        end
    end)

    it("uses only the access-proven loaded return", function()
        local loading = loadTaintReport({
            addons = {{ name = "LoadingOnly", title = "Loading Only", version = "1" }},
            loadedResult = function()
                return true, false
            end,
        })
        loading.initialize()
        local loadingReport = assert(loading.run(""))
        assert.is_nil(loadingReport:find("Loaded addon: LoadingOnly", 1, true))

        local inaccessible = loadTaintReport({
            addonCount = 1,
            valueAccess = function(value)
                return value ~= false
            end,
        })
        inaccessible.initialize()
        local inaccessibleReport = assert(inaccessible.run(""))
        assert.is_truthy(inaccessibleReport:find("Addon load states unavailable: 1", 1, true))
        assert.is_truthy(inaccessibleReport:find("BugSack: unavailable", 1, true))
        assert.is_truthy(inaccessibleReport:find("BugGrabber: unavailable", 1, true))
    end)

    it("refuses malformed addon counts without indexed calls but always checks both tools", function()
        local cases = {
            { addonCount = -1 },
            { addonCount = 1.5 },
            { addonCount = math.huge },
            { addonCount = 2147483648 },
            { addonCountError = "count failed" },
        }
        for _, options in ipairs(cases) do
            local state = loadTaintReport(options)
            state.initialize()
            local report = assert(state.run(""))
            assert.is_truthy(report:find("Addon index scan: unavailable", 1, true))
            assert.equals(0, countAddonCalls(state.addonCalls, "info", true))
            assert.equals(2, countAddonCalls(state.addonCalls, "loaded", false))
        end

        local inaccessible = loadTaintReport({
            addonCount = 5,
            valueAccess = function(value) return value ~= 5 end,
        })
        inaccessible.initialize()
        local report = assert(inaccessible.run(""))
        assert.is_truthy(report:find("Addon index scan: unavailable", 1, true))
        assert.equals(0, countAddonCalls(inaccessible.addonCalls, "info", true))
        assert.equals(2, countAddonCalls(inaccessible.addonCalls, "loaded", false))
    end)

    it("enforces the exact indexed-addon scan ceiling and separate loss counters", function()
        local cases = {
            { count = 0, calls = 0, unscanned = nil },
            { count = 1024, calls = 1024, unscanned = nil },
            { count = 1025, calls = 1024, unscanned = "Addon indices unscanned: 1" },
            { count = 2147483647, calls = 1024,
                unscanned = "Addon indices unscanned: 2147482623" },
        }
        for _, case in ipairs(cases) do
            local state = loadTaintReport({ addonCount = case.count })
            state.initialize()
            local report = assert(state.run(""))
            assert.equals(case.calls, countAddonCalls(state.addonCalls, "info", true))
            assert.equals(case.calls, countAddonCalls(state.addonCalls, "loaded", true))
            assert.equals(2, countAddonCalls(state.addonCalls, "loaded", false) - case.calls)
            if case.unscanned then
                assert.is_truthy(report:find(case.unscanned, 1, true))
            else
                assert.is_nil(report:find("Addon indices unscanned:", 1, true))
            end
        end
    end)

    it("retains only 300 loaded addon rows and discloses later loaded rows", function()
        local addons = {}
        for index = 1, 305 do
            addons[index] = {
                name = string.format("Addon%03d", 306 - index),
                title = "Title" .. index,
                version = "1",
                loaded = true,
            }
        end
        local state = loadTaintReport({ addons = addons })
        state.initialize()
        local report = assert(state.run(""))
        assert.equals(300, select(2, report:gsub("Loaded addon:", "")))
        assert.is_truthy(report:find("Loaded addons omitted: 5", 1, true))
        local first = assert(report:find("Loaded addon: Addon006", 1, true))
        local later = assert(report:find("Loaded addon: Addon007", 1, true))
        assert.is_true(first < later)
    end)

    it("keeps the complete mandatory prefix when maximum-density detail truncates", function()
        local function denseLine(label, index)
            local prefix = "Interface/AddOns/KitnEssentials/Core/" .. label .. index .. ".lua:1 "
            return prefix .. string.rep("X", 300 - #prefix)
        end
        local restored = {}
        for groupIndex = 1, 10 do
            local sources = {}
            for sourceIndex = 1, 3 do
                local lines = {}
                for lineIndex = 1, 6 do
                    lines[lineIndex] = denseLine("R" .. groupIndex .. "S" .. sourceIndex, lineIndex)
                end
                sources[sourceIndex] = storedSource(lines[1], {
                    keLines = lines,
                    observedSamples = sourceIndex == 3 and 3 or 1,
                })
            end
            local options = { sources = sources, walks = 5, count = 5,
                firstSeen = 1799999700 + groupIndex,
                lastSeen = 1799999800 + groupIndex }
            if groupIndex == 1 then
                options.count = 7
                options.notWalked = 2
                options.stackUnavailable = 1
                options.stackInputTruncated = 1
                options.sourceUnavailable = 1
                options.sourceSamplesOmitted = 1
                sources[3] = nil
                sources[1].keLinesOmitted = 1
            end
            restored[groupIndex] = storedGroup("dense-restored-" .. groupIndex, options)
        end

        local addons = {}
        for index = 1, 300 do
            local suffix = string.format("%03d", index)
            addons[index] = {
                name = suffix .. string.rep("N", 297),
                title = suffix .. string.rep("T", 297),
                version = suffix .. string.rep("V", 297),
                loaded = true,
            }
        end
        local state = loadTaintReport({ addons = addons })
        state.initialize({ global = { TaintLog = storedLog(restored, {
            omitted = 1, supersededRestored = 1,
        }) } })
        for groupIndex = 1, 15 do
            state.fire("ADDON_ACTION_BLOCKED", "KitnEssentials", "dense-current-" .. groupIndex)
        end
        local report = assert(state.run(""))
        local detailStart = assert(report:find("\n[current]", 1, true))
        assert.is_true(detailStart - 1 <= 8192)
        for _, expected in ipairs({
            "Unsampled occurrences: 2",
            "Stack unavailable samples: 1",
            "Stack input truncated samples: 1",
            "Source unavailable samples: 1",
            "Source samples omitted: 1",
            "KE lines omitted: 1",
        }) do
            assert.is_truthy(report:find(expected, 1, true), expected)
        end
        assert.is_true(#report <= 90000)
        assert.is_truthy(report:find("[report truncated]", -40, true))
        assert.equals("[report truncated]\n", report:sub(-19))
    end)

    it("prints exact usage for unknown commands without creating a frame", function()
        local state = loadTaintReport()
        state.initialize()
        assert.is_nil(state.run("wat"))
        assert.same({ "Usage: /kes taint [clear]" }, state.printed)
        assert.equals(0, state.frameCreateCount())
    end)

    it("creates the singleton dialog lazily, reuses it, and clears its text", function()
        local state = loadTaintReport()
        state.initialize()
        local first = assert(state.run(""))
        assert.equals(1, state.frameCreateCount())
        local hidesBefore = state.frameHideCount()
        local second = assert(state.run(""))
        assert.equals(first, second)
        assert.equals(1, state.frameCreateCount())
        assert.equals("", state.run("clear"))
        assert.equals(1, state.frameCreateCount())
        assert.is_true(state.frameHideCount() > hidesBefore)
        assert.equals("", state.lastEditText())
    end)

    it("contains none of the forbidden background or input-control paths", function()
        local handle = assert(io.open("Modules/Diagnostics/TaintReport.lua", "rb"))
        local source = handle:read("*a")
        handle:close()
        for _, forbidden in ipairs({
            "OnUpdate", "C_Timer", "NewTicker", "EnumerateFrames", "EnableKeyboard",
            "SetPropagateKeyboardInput", "SetFocus", "HighlightText",
        }) do
            assert.is_nil(source:find(forbidden, 1, true), forbidden)
        end
    end)
end)
