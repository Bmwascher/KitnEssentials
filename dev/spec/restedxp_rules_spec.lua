-- Modules/Skinning/RestedXP: the rules a later edit breaks silently. What the
-- window reads from RestedXP, what setup writes and undoes, what turning off
-- gives back, when the arrow hides, and which part a missing call turns off.
-- RestedXP is passed in as a plain table, so no Blizzard fake is needed.
local L = require("dev.spec._ke_loader")

describe("restedxp rules", function()
    local KE, Rules, Model, Safe

    before_each(function()
        KE = L.loadRestedXPRules()
        Rules, Model, Safe = KE.RestedXPRules, KE.RestedXPWindowModel, KE.RestedXPSafe
    end)

    local function Shown(text, visible)
        return {
            GetText = function() return text end,
            IsShown = function() return visible ~= false end,
        }
    end

    local function Steps(count)
        local list = {}
        for i = 1, count do list[i] = { index = i } end
        return list
    end

    local function Snapshot(count)
        local rows = {}
        for i = 1, count do
            rows[i] = { index = i, text = "Step " .. i .. "\nsecond line", complete = false, hidden = false }
        end
        return { rows = rows }
    end

    local function Rxp(fields)
        local rxp = {
            currentGuide = { title = "Northshire 1-6", steps = Steps(60) },
            GetGuideProgress = function() return 8 end,
            RXPFrame = { activeSteps = {} },
            v2 = { BuildGuideStepsSnapshot = function() return Snapshot(12) end },
            icons = {},
        }
        for key, value in pairs(fields or {}) do rxp[key] = value end
        return rxp
    end

    local function Tint(text) return "<" .. text .. ">" end

    it("reads the heading from the chapter in its own order, the progress, no progress and no guide", function()
        for _, row in ipairs({
            { chapter = "23-24 Wetlands", subgroup = "Speedrun Guide 20-30", want = "<23-24> Wetlands" },
            { chapter = "Northshire 1-6", title = "Other", want = "Northshire <1-6>" },
            { chapter = "", subgroup = "Speedrun Guide 20-30", want = "Speedrun Guide <20-30>" },
            { title = "1-6 Northshire", want = "<1-6> Northshire" },
            { title = "Northshire 1-6", want = "Northshire <1-6>" },
            { title = "Northshire", want = "Northshire" },
        }) do
            Model.Stale()
            local rxp = Rxp({
                currentGuide = { title = row.title, subgroup = row.subgroup, steps = Steps(60) },
                GetGuideName = row.chapter and function() return row.chapter end or nil,
            })
            assert.equals(row.want, Model.Read(rxp, { tint = Tint }).heading, row.want)
        end

        local model = Model.Read(Rxp(), {})
        assert.equals(8, model.step)
        assert.equals(60, model.total)
        assert.near(8 / 60, model.fraction, 0.0001)
        assert.equals(13, model.percent)

        local unknown = Model.Read(Rxp({ GetGuideProgress = function() return nil end }), {})
        assert.is_nil(unknown.step)
        assert.is_nil(unknown.fraction)

        assert.is_nil(Model.Read(Rxp({ currentGuide = { empty = true, steps = {} } }), {}))
        assert.is_nil(Model.Read(Rxp({ currentGuide = false }), {}))
    end)

    it("skips hidden active steps, caps at three and starts the list after the last active step", function()
        local rxp = Rxp({
            GetGuideProgress = function() return 3 end,
            RXPFrame = { activeSteps = {
                { index = 2, active = true, elements = {} },
                { index = 3, active = true, hidewindow = true, elements = {} },
                { index = 4, active = true, hidetip = true, elements = {} },
                { index = 5, active = true, elements = {} },
                { index = 6, active = true, elements = {} },
                { index = 7, active = true, elements = {} },
            } },
        })
        local model = Model.Read(rxp, {})
        assert.equals(3, #model.steps)
        assert.is_true(model.current[2] and model.current[5] and model.current[6])
        assert.is_nil(model.current[7])
        assert.equals(6, model.after)
        assert.equals(7, model.list[model.first].index)
    end)

    it("reads a row's text, icon and done state", function()
        local function Row(element)
            local rxp = Rxp({ RXPFrame = { activeSteps = { { index = 1, active = true, elements = { element } } } } })
            Model.Stale()
            return Model.Read(rxp, {}).steps[1].rows[1]
        end

        assert.equals("from the frame", Row({ text = "raw", frame = { text = Shown("from the frame") } }).text)
        assert.equals("raw", Row({ text = "raw", frame = { text = Shown("") } }).text)
        assert.equals("", Row({ text = "raw", frame = { icon = Shown("G", false) } }).icon)
        assert.equals("G", Row({ text = "raw", frame = { icon = Shown("G") } }).icon)
        assert.is_true(Row({ text = "raw", frame = { button = { GetChecked = function() return true end } } }).done)
        assert.is_true(Row({ text = "raw", completed = true }).done)
        assert.is_false(Row({ text = "raw" }).done)
    end)

    it("hides only the tag-along step it was asked to, until RestedXP retires it", function()
        for _, row in ipairs({
            { step = { index = 40, completewith = "next" }, progress = 41, want = true, name = "behind, by next" },
            { step = { index = 40, completewith = "crocs" }, progress = 41, want = true, name = "behind, by label" },
            { step = { index = 41, completewith = "next" }, progress = 41, want = false, name = "the progress step" },
            { step = { index = 40, sticky = true }, progress = 41, want = false, name = "sticky with no target" },
            { step = { index = 41 }, progress = 41, want = false, name = "the current step" },
            { step = { index = 40, completewith = "next" }, want = false, name = "no progress" },
            { progress = 41, want = false, name = "no step" },
        }) do
            assert.equals(row.want, Rules.TagAlong(row.step, row.progress), row.name)
        end

        local tagAlong = { index = 40, active = true, completewith = "next", elements = {} }
        local twin = { index = 40, active = true, completewith = "next", elements = {} }
        local current = { index = 41, active = true, elements = {} }
        local hidden = { [tagAlong] = true }
        local rxp = Rxp({
            GetGuideProgress = function() return 41 end,
            RXPFrame = { activeSteps = { tagAlong, twin, current } },
        })
        local model = Model.Read(rxp, { hidden = hidden })
        assert.equals(2, #model.steps)
        assert.equals(twin, model.steps[1].source)
        assert.equals(current, model.steps[2].source)

        tagAlong.active = nil
        Model.Read(rxp, { hidden = hidden })
        assert.is_nil(hidden[tagAlong])
        tagAlong.active = true
        assert.equals(3, #Model.Read(rxp, { hidden = hidden }).steps)
    end)

    it("lifts a lead icon, marks an item icon as nested, leaves a mid-line marker and strips escapes", function()
        for _, row in ipairs({
            { shown = "|TInterface\\AddOns\\X\\a.tga:0|t Accept", glyph = "",
              text = "Accept", icon = "|TInterface\\AddOns\\X\\a.tga:0|t", nested = false },
            { shown = "|T134400:0|t Item", glyph = "", text = "Item", icon = "|T134400:0|t", nested = true },
            { shown = "|TInterface\\Icons\\inv.blp:0|t Item", glyph = "",
              text = "Item", icon = "|TInterface\\Icons\\inv.blp:0|t", nested = true },
            { shown = "Go |TX:0|t there", glyph = "", text = "Go |TX:0|t there", icon = "", nested = false },
            { shown = "Text", glyph = "G", text = "Text", icon = "G", nested = false },
        }) do
            local text, icon, nested = Rules.Lifted(row.shown, row.glyph)
            assert.equals(row.text, text, row.shown)
            assert.equals(row.icon, icon, row.shown)
            assert.equals(row.nested, nested, row.shown)
        end

        assert.equals("red link end",
            Rules.Plain("|cff112233red|r |TInterface\\x:0|t|A:atlas:0:0|a|Hitem:1|hlink|h end"))
    end)

    it("counts from the text or the bags and fills the meter", function()
        local function Count() return 2 end

        local have, need, bags = Rules.Counted(nil, nil, nil, "Meat: 3/8", Count)
        assert.same({ 3, 8, false }, { have, need, bags })
        have, need, bags = Rules.Counted("buy", 5, 4, "ignored 9/9", Count)
        assert.same({ 2, 4, true }, { have, need, bags })
        have, need = Rules.Counted(nil, nil, nil, "no count", Count)
        assert.is_nil(have)
        assert.is_nil(need)

        for _, row in ipairs({
            { name = "count of one", have = 1, need = 1, want = nil },
            { name = "no count", want = nil },
            { name = "partial", have = 3, need = 8, want = 0.375 },
            { name = "past the total", have = 9, need = 8, want = 1 },
            { name = "done buy", have = 1, need = 4, bags = true, done = true, want = 1 },
            { name = "done line keeps its count", have = 3, need = 8, done = true, want = 0.375 },
        }) do
            assert.equals(row.want, Rules.CountFill(row.have, row.need, row.bags, row.done), row.name)
        end
    end)

    it("clamps the list window at both ends and finds the first step after an index", function()
        for _, row in ipairs({
            { first = 5, scroll = 0, count = 6, total = 20, top = 5, kept = 0 },
            { first = 5, scroll = 100, count = 6, total = 20, top = 15, kept = 10 },
            { first = 5, scroll = -100, count = 6, total = 20, top = 1, kept = -4 },
            { first = 1, scroll = 0, count = 6, total = 0, top = 1, kept = 0 },
            { first = 1, scroll = 3, count = 10, total = 4, top = 1, kept = 0 },
        }) do
            local top, kept = Rules.ListWindow(row.first, row.scroll, row.count, row.total)
            assert.equals(row.top, top)
            assert.equals(row.kept, kept)
        end

        local list = { { index = 2 }, { index = 4 }, { index = 6 } }
        assert.equals(1, Rules.FirstAfter(list, 0))
        assert.equals(3, Rules.FirstAfter(list, 4))
        assert.equals(4, Rules.FirstAfter(list, 6))
        assert.equals(1, Rules.FirstAfter({}, 3))
    end)

    it("takes a valid option, snaps and clamps a number and defaults anything else", function()
        for _, row in ipairs({
            { "ArrowSize", nil, 100 }, { "ArrowSize", "x", 100 }, { "ArrowSize", 500, 200 },
            { "ArrowSize", 10, 60 }, { "ArrowSize", 152, 150 }, { "ArrowSize", 153, 155 },
            { "ArrowTextSize", nil, 14 }, { "SetUpNewCharacters", nil, false },
            { "ArrowWords", "yes", true }, { "ArrowWords", false, false },
            { "WindowColors", nil, "accent" }, { "WindowColors", "palette", "accent" },
            { "WindowColors", "custom", "custom" }, { "FollowAccent", nil, false }, { "FollowAccent", true, true },
            { "FontOutline", nil, "OUTLINE" }, { "FontOutline", "shadow", "shadow" },
        }) do
            assert.equals(row[3], Rules.Option(row[1], row[2]), row[1] .. " " .. tostring(row[2]))
        end
    end)

    it("plans setup rows by starting values", function()
        local THEME = Rules.THEME_NAME
        for _, row in ipairs({
            { profile = {},
              keys = { "enableBetaFeatures", "enableV2Interface", "activeTheme" }, reload = true },
            { profile = { enableBetaFeatures = true },
              keys = { "enableV2Interface", "activeTheme" }, reload = true },
            { profile = { enableBetaFeatures = true, enableV2Interface = true },
              keys = { "activeTheme" }, reload = nil },
            { profile = { enableBetaFeatures = true, enableV2Interface = true, activeTheme = THEME },
              keys = {}, reload = nil },
        }) do
            local rows = Rules.PlanSetup(row.profile)
            assert.same(row.keys, Rules.RowKeys(rows))
            assert.equals(row.reload, rows.reload)
        end
    end)

    it("returns each starting state through setup and undo, and never overwrites the record", function()
        local THEME = Rules.THEME_NAME
        for _, start in ipairs({
            { enableBetaFeatures = false, enableV2Interface = false, activeTheme = "RXP Blue" },
            { enableV2Interface = false, activeTheme = "Dark" },
            { enableBetaFeatures = true, enableV2Interface = false, activeTheme = "Dark" },
        }) do
            local profile = {}
            for key, value in pairs(start) do profile[key] = value end

            local rows = Rules.PlanSetup(profile)
            local before = Rules.MergeBefore({}, profile, Rules.RowKeys(rows))
            if start.enableBetaFeatures then
                assert.is_nil(before.enableBetaFeatures)
            else
                assert.is_false(before.enableBetaFeatures)
            end
            for _, row in ipairs(rows) do profile[row.key] = row.after end
            assert.equals(THEME, profile.activeTheme)

            Rules.MergeBefore(before, profile, { "activeTheme" })
            assert.equals(start.activeTheme, before.activeTheme)

            for _, row in ipairs(Rules.PlanUndo(before, profile)) do profile[row.key] = row.after end
            assert.equals(start.activeTheme, profile.activeTheme)
            assert.is_false(profile.enableV2Interface)
            assert.equals(start.enableBetaFeatures or false, profile.enableBetaFeatures or false)
            assert.is_true(Rules.ClearDone(before, profile))
        end
    end)

    it("calls rows the same only with the same keys and values in order", function()
        local shown = { { key = "enableV2Interface", now = false, after = true } }
        for _, row in ipairs({
            { other = { { key = "enableV2Interface", now = false, after = true } }, want = true },
            { other = { { key = "enableBetaFeatures", now = false, after = true } }, want = false },
            { other = { { key = "enableV2Interface", now = true, after = true } }, want = false },
            { other = { { key = "enableV2Interface", now = false, after = "Dark" } }, want = false },
            { other = { shown[1], shown[1] }, want = false },
            { other = {}, want = false },
        }) do
            assert.equals(row.want, Rules.SameRows(shown, row.other))
        end
    end)

    it("refuses a setup write unless every gate holds", function()
        for _, row in ipairs({
            { true, true, true, false, true },
            { false, true, true, false, false },
            { true, false, true, false, false },
            { true, nil, true, false, false },
            { true, true, false, false, false },
            { true, true, true, true, false },
        }) do
            assert.equals(row[5], Rules.SetupMayWrite(row[1], row[2], row[3], row[4]))
        end
    end)

    it("applies a waiting change at RestedXP's start only as the preview showed it", function()
        local SAVED, LIMIT = 1000, Rules.PENDING_SECONDS
        local function Pending(kind, now)
            return { kind = kind, profile = "A", at = SAVED,
                     rows = { { key = "enableV2Interface", now = now, after = true } } }
        end
        local untimed = Pending("undo", false)
        untimed.at = nil
        local profile = { enableV2Interface = false }
        local soon = SAVED + 5
        for _, row in ipairs({
            { Pending("setup", false), "A", profile, true, soon, true, nil, "setup as shown" },
            { Pending("undo", false), "A", profile, false, soon, true, nil, "undo needs no module gate" },
            { Pending("setup", false), "A", profile, true, SAVED + LIMIT, true, nil, "at the limit" },
            { Pending("setup", false), "A", profile, false, soon, false, "changed", "setup with the gates failing" },
            { Pending("setup", false), "B", profile, true, soon, false, "changed", "another profile" },
            { Pending("setup", false), nil, profile, true, soon, false, "changed", "no profile name" },
            { Pending("setup", true), "A", profile, true, soon, false, "changed", "a Now value changed" },
            { Pending("other", false), "A", profile, true, soon, false, "changed", "an unknown kind" },
            { { kind = "setup", profile = "A", at = SAVED, rows = {} }, "A", profile, true, soon, false, "changed",
              "no rows" },
            { nil, "A", profile, true, soon, false, "changed", "nothing waiting" },
            { Pending("setup", false), "A", nil, true, soon, false, "changed", "no profile table" },
            { Pending("setup", false), "A", profile, true, SAVED + LIMIT + 1, false, "expired", "past the limit" },
            { untimed, "A", profile, true, soon, false, "expired", "no saved time" },
            { Pending("setup", false), "A", profile, true, SAVED - 1, false, "expired", "saved in the future" },
            { Pending("setup", false), "A", profile, true, nil, false, "expired", "no time now" },
        }) do
            local applies, why = Rules.PendingApplies(row[1], row[2], row[3], row[4], row[5])
            assert.equals(row[6], applies, row[8])
            assert.equals(row[7], why, row[8])
        end
    end)

    it("lets a newer approved change or a profile event replace one waiting for RestedXP's start", function()
        local store, now = {}, 1000
        local v2 = { { key = "enableV2Interface", now = false, after = true } }
        Rules.SavePending(store, "setup", "A", v2, now)
        Rules.SavePending(store, "undo", "A", v2, now)
        assert.equals("undo", Rules.TakePending(store).kind)
        assert.is_nil(Rules.TakePending(store))

        -- Turning off put the theme back, its Beta and V2 Undo waits after a refused
        -- reload, and Setup again has only the theme left, so it writes live.
        local profile = { enableBetaFeatures = true, enableV2Interface = true, activeTheme = "Dark" }
        Rules.SavePending(store, "undo", "A", {
            { key = "enableBetaFeatures", now = true, after = false },
            { key = "enableV2Interface", now = true, after = false },
        }, now)
        local rows = Rules.PlanSetup(profile)
        assert.same({ "activeTheme" }, Rules.RowKeys(rows))
        assert.is_nil(rows.reload)
        assert.is_true(Rules.PendingApplies(store.RestedXPPending, "A", profile, true, now))
        for _, row in ipairs(rows) do profile[row.key] = row.after end
        Rules.Supersede(store)
        assert.is_nil(Rules.TakePending(store))

        -- A setup waits for profile A; A is deleted and made again with the same
        -- values. Name and values cannot tell the new A apart, so the profile event
        -- that the delete needs first is what drops it.
        Rules.SavePending(store, "setup", "A", v2, now)
        local remade = { enableV2Interface = false }
        assert.is_true(Rules.PendingApplies(store.RestedXPPending, "A", remade, true, now))
        Rules.Supersede(store)
        assert.is_nil(Rules.TakePending(store))
        Rules.Supersede(nil)

        -- A refused reload: the timer armed by one save clears that change only.
        Rules.SavePending(store, "setup", "A", v2, now)
        local first = store.RestedXPPending
        Rules.SavePending(store, "undo", "A", v2, now)
        local newer = store.RestedXPPending
        assert.is_false(Rules.DropIfWaiting(store, first))
        assert.equals(newer, store.RestedXPPending)
        assert.is_true(Rules.DropIfWaiting(store, newer))
        assert.is_nil(Rules.TakePending(store))
        assert.is_false(Rules.DropIfWaiting(store, newer))
        assert.is_false(Rules.DropIfWaiting(nil, newer))
    end)

    it("saves a change for the next start only when both addons load then", function()
        for _, row in ipairs({
            { true, true, true, "the client's check says both" },
            { 2, 2, true, "both All for this character's GUID" },
            { true, 2, true, "one answer of each kind" },
            { 1, 2, false, "Some is not this character" },
            { 0, 2, false, "KitnEssentials off" },
            { 2, false, false, "the client's check says RestedXP is off" },
            { 0, 0, false, "both off" },
            { nil, 2, false, "no answer for KitnEssentials" },
            { 2, nil, false, "no answer for RestedXP" },
        }) do
            assert.equals(row[3], Rules.BothLoadNext(row[1], row[2]), row[4])
        end
    end)

    it("writes a preview only while it still shows the write", function()
        local profile, other = {}, {}
        local shown = { { key = "activeTheme", now = "Dark", after = "KitnEssentials" } }
        local same = { { key = "activeTheme", now = "Dark", after = "KitnEssentials" } }
        local moved = { { key = "activeTheme", now = "Blue", after = "KitnEssentials" } }
        assert.is_true(Rules.PreviewHolds(same, profile, profile, shown))
        assert.is_false(Rules.PreviewHolds(nil, profile, profile, shown))
        assert.is_false(Rules.PreviewHolds(same, other, profile, shown))
        assert.is_false(Rules.PreviewHolds(same, nil, nil, shown))
        assert.is_false(Rules.PreviewHolds(moved, profile, profile, shown))
    end)

    it("compares two themes by every value, nested ones included", function()
        local function Theme()
            return { font = "A", colors = { accent = { 1, 0, 0 } } }
        end
        local changedDeep, extra, missing = Theme(), Theme(), Theme()
        changedDeep.colors.accent[2] = 1
        extra.colors.line = { 0, 0, 0 }
        missing.font = nil
        assert.is_true(Rules.SameDeep(Theme(), Theme()))
        assert.is_false(Rules.SameDeep(Theme(), changedDeep))
        assert.is_false(Rules.SameDeep(Theme(), extra))
        assert.is_false(Rules.SameDeep(Theme(), missing))
        assert.is_false(Rules.SameDeep(Theme(), nil))
    end)

    it("keeps the font a later load found, for the start-up theme only", function()
        local kept = { name = "Pack", path = "pack.ttf" }
        local path, record = Rules.ThemeFont("Pack", "pack.ttf", nil, false, "default.ttf")
        assert.equals("pack.ttf", path)
        assert.same(kept, record)
        assert.equals(kept, select(2, Rules.ThemeFont("Pack", "pack.ttf", kept, true, "default.ttf")))
        for _, row in ipairs({
            { "Pack", true, "pack.ttf", kept },
            { "Other", true, "default.ttf", kept },
            { "Pack", false, "default.ttf", nil },
        }) do
            local got, keep = Rules.ThemeFont(row[1], nil, kept, row[2], "default.ttf")
            assert.equals(row[3], got, row[1])
            assert.equals(row[4], keep, row[1])
        end
    end)

    it("keeps each RestedXP profile's record apart", function()
        local records = { A = { before = { activeTheme = "Dark" } } }
        assert.equals("Dark", Rules.RecordFor(records, "A").before.activeTheme)
        assert.is_nil(Rules.RecordFor(records, "B"))
        assert.is_nil(Rules.RecordFor(records, nil))
        assert.is_nil(Rules.RecordFor(nil, "A"))
    end)

    it("sets up only an unseen character with the switch on", function()
        for _, row in ipairs({
            { on = true, seen = false, want = true },
            { on = true, seen = true, want = false },
            { on = false, seen = false, want = false },
            { on = nil, seen = nil, want = false },
        }) do
            assert.equals(row.want, Rules.ShouldAutoSetup(row.on, row.seen))
        end
    end)

    it("reads each color from KE's tokens, the accent or Custom, for the window and the theme", function()
        local ACCENT, BACK = { 0.1, 0.2, 0.3, 1 }, { 0.5, 0.6, 0.7, 0.8 }
        local WHITE, BLACK = { 1, 1, 1 }, { 0, 0, 0 }
        local OFF_BOX = { 8 / 255, 8 / 255, 8 / 255 }
        local tokens = Rules.Tokens(ACCENT)

        local function Reads(color, source, alpha, name)
            assert.near(source[1], color[1], 0.0001, name)
            assert.near(source[2], color[2], 0.0001, name)
            assert.near(source[3], color[3], 0.0001, name)
            assert.near(alpha, color[4], 0.0001, name)
        end

        local colors = Rules.WindowColors(tokens, false, BACK, 55, "accent")
        Reads(colors.panel, BACK, 0.8, "panel")
        Reads(colors.box, OFF_BOX, 0.55, "box")
        Reads(colors.border, BLACK, 1, "border")
        Reads(colors.boxBorder, BLACK, 1, "box border")
        Reads(colors.line, WHITE, 0.28, "line")
        Reads(colors.barBack, WHITE, 0.28, "bar track")
        Reads(colors.barFill, ACCENT, 1, "bar fill")
        Reads(colors.accent, ACCENT, 1, "accent")
        Reads(colors.title, WHITE, 1, "title")

        local custom = { title = { 1, 0, 0, 1 }, box = { 0, 1, 0, 1 }, border = { 0, 0, 1, 1 } }
        local picked = Rules.WindowColors(tokens, false, BACK, 55, "custom", custom)
        Reads(picked.title, custom.title, 1, "custom title")
        Reads(picked.box, custom.box, 0.55, "custom box keeps the opacity setting")
        Reads(picked.boxBorder, custom.border, 1, "custom border")
        Reads(picked.accent, ACCENT, 1, "accent is not a custom color")
        Reads(Rules.WindowColors(tokens, false, BACK, 55, "accent", custom).title, WHITE, 1, "accent mode ignores custom")
        assert.is_nil(Rules.WindowColors(tokens, false, nil, 55, "accent").panel)

        local theme = Rules.ThemeFields(tokens, "font", BACK)
        Reads(theme.background, BACK, 0.8, "background")
        Reads(theme.bottomFrameBG, BACK, 0.8, "bottom")
        Reads(theme.bottomFrameHighlight, WHITE, 0.15, "highlight")
        Reads(theme.mapPins, ACCENT, 1, "pins")
        assert.equals("font", theme.font)
        assert.is_nil(theme.dividerColor)
        assert.is_nil(theme.chromeColor)
    end)

    it("takes the accent's wash only with the follow on and no Custom", function()
        local ACCENT, BACK = { 0.1, 0.2, 0.3, 1 }, { 0.5, 0.6, 0.7, 0.8 }
        local NEAR_BLACK, BLACK = { 8 / 255, 8 / 255, 8 / 255 }, { 0, 0, 0 }
        local tokens = Rules.Tokens(ACCENT)

        local function Reads(color, source, alpha, name)
            for channel = 1, 3 do assert.near(source[channel], color[channel], 0.0001, name) end
            assert.near(alpha, color[4], 0.0001, name)
        end

        local function Wash(base, share)
            local mixed = {}
            for channel = 1, 3 do mixed[channel] = base[channel] + (ACCENT[channel] - base[channel]) * share end
            return mixed
        end

        local off = Rules.WindowColors(tokens, false, BACK, 55, "accent")
        local on = Rules.WindowColors(tokens, true, BACK, 55, "accent")
        Reads(on.panel, Wash(NEAR_BLACK, Rules.WASH_PANEL), Rules.WASH_PANEL_ALPHA, "panel")
        Reads(on.box, Wash(NEAR_BLACK, Rules.WASH_BOX), 0.55, "box keeps the opacity setting")
        Reads(on.border, Wash(BLACK, Rules.WASH_EDGE), 1, "window edge")
        Reads(on.boxBorder, Wash(BLACK, Rules.WASH_EDGE), 1, "box edge")
        assert.same(off.line, on.line)
        assert.same(off.title, on.title)
        assert.same(off.barBack, on.barBack)
        assert.is_nil(Rules.WindowColors(tokens, true, nil, 55, "accent").panel)

        local custom = { box = { 0, 1, 0, 1 }, border = { 0, 0, 1, 1 } }
        local picked = Rules.WindowColors(tokens, true, BACK, 55, "custom", custom)
        Reads(picked.panel, BACK, 0.8, "Custom gives Background Color back")
        Reads(picked.box, custom.box, 0.55, "custom box")
        Reads(picked.border, custom.border, 1, "custom border")

        for _, row in ipairs({
            { true, "accent", true }, { true, nil, true }, { false, "accent", false },
            { nil, "accent", false }, { true, "custom", false },
        }) do
            assert.equals(row[3], Rules.Washed(row[1], row[2]))
        end
    end)

    it("keeps the first record of a frame", function()
        local home = Rules.KeepHome(nil, 1, true)
        assert.same({ alpha = 1, mouse = true }, home)
        assert.equals(home, Rules.KeepHome(home, 0, false))
    end)

    it("composes the arrow text from the two switches", function()
        for _, row in ipairs({
            { 142, "Kill", true, true, false, "142 yd\nKill" },
            { 142, nil, true, true, false, "142 yd" },
            { 142, "Kill", false, true, false, "Kill" },
            { 142, "Kill", true, false, false, "142 yd" },
            { 142, "Kill", false, false, false, "" },
            { 142, "Kill", true, true, true, nil },
            { nil, "Kill", true, true, false, "Kill" },
        }) do
            assert.equals(row[6], Rules.ArrowText(row[1], row[2], row[3], row[4], row[5]))
        end
    end)

    it("decides the window, Show In and the flash", function()
        for _, row in ipairs({
            { true, false, true }, { false, false, false }, { true, true, false },
        }) do
            assert.equals(row[3], Rules.WindowMayStart(row[1], row[2]))
        end

        for _, row in ipairs({
            { "none", true }, { "scenario", true }, { nil, true }, { "party", false }, { "raid", false },
            { "pvp", false }, { "arena", false },
        }) do
            assert.equals(row[2], Rules.ShowInAllowed(row[1], true, false, false, false), tostring(row[1]))
            assert.equals(not row[2], Rules.ShowInAllowed(row[1], false, true, true, true), tostring(row[1]))
        end

        local guide, other = {}, {}
        assert.is_true(Rules.ShouldFlash(guide, 3, guide, 4))
        assert.is_false(Rules.ShouldFlash(guide, 3, guide, 3))
        assert.is_false(Rules.ShouldFlash(guide, 3, other, 4))
        assert.is_false(Rules.ShouldFlash(nil, nil, guide, 4))
    end)

    it("gives This Character one state and one button, lit only when an action exists", function()
        local beta = { { key = "enableBetaFeatures" }, reload = true }
        local theme = { { key = "activeTheme" } }
        local none = {}
        for _, row in ipairs({
            { { installed = false }, "notInstalled", "setup", false },
            { { loaded = false }, "notLoaded", "setup", false },
            { { profile = false }, "noProfile", "setup", false },
            { { waiting = "setup", plan = beta }, "reloading", "setup", false },
            { { waiting = "undo", plan = none, undo = beta }, "reloading", "undo", false },
            { { window = false, plan = beta }, "noWindow", "setup", false },
            { { window = false, plan = none, undo = theme }, "noWindow", "undo", true },
            { { window = false, plan = none, undo = beta, missed = true }, "noWindow", "setup", false },
            { { plan = beta }, "notSetUp", "setup", true },
            { { plan = beta, undo = theme }, "notSetUp", "setup", true },
            { { plan = theme }, "themeOnly", "setup", true },
            { { plan = theme, missed = true }, "themeOnly", "setup", true },
            { { plan = beta, missed = true }, "setupMissed", "setup", false },
            { { plan = beta, undo = theme, missed = true }, "setupMissed", "undo", true },
            { { plan = none, undo = theme }, "setUp", "undo", true },
            { { plan = none, undo = beta }, "setUp", "undo", true },
            { { plan = none, undo = theme, missed = true }, "setUp", "undo", true },
            { { plan = none, undo = beta, missed = true }, "undoMissed", "undo", false },
            { { plan = none, undo = none }, "setUpFound", "undo", false },
            { { plan = none }, "setUpFound", "undo", false },
        }) do
            local facts = { installed = true, loaded = true, profile = true, window = true }
            for key, value in pairs(row[1]) do facts[key] = value end
            local state, button, live = Rules.CharacterState(facts)
            assert.equals(row[2], state)
            assert.equals(row[3], button, row[2])
            assert.equals(row[4], live, row[2])
        end
        assert.is_true(Rules.Doable(theme, true))
        assert.is_false(Rules.Doable(beta, true))
        assert.is_true(Rules.Doable(beta, false))
        assert.is_false(Rules.Doable(none, false))
        assert.is_false(Rules.Doable(nil, false))
    end)

    it("turns off only the part a missing call belongs to", function()
        local function Full()
            local function Call() end
            return {
                RegisterTheme = Call, ReloadTheme = Call, SetStep = Call, GetGuideProgress = Call,
                settings = { profile = {}, GetSettingsDB = Call },
                icons = {},
                arrowFrame = { texture = {}, text = {}, UpdateVisuals = Call },
                v2 = { IsGuideWindowEnabled = Call, BuildGuideStepsSnapshot = Call },
                RXPFrame = { activeSteps = {} },
            }
        end

        local all = Rules.Parts(Full())
        assert.same({ Theme = true, Arrow = true, Icons = true, Setup = true, Window = true }, all)

        for _, row in ipairs({
            { name = "RegisterTheme", off = "Theme", cut = function(r) r.RegisterTheme = nil end },
            { name = "ReloadTheme", off = "Theme", cut = function(r) r.ReloadTheme = nil end },
            { name = "arrow text", off = "Arrow", cut = function(r) r.arrowFrame.text = nil end },
            { name = "UpdateVisuals", off = "Arrow", cut = function(r) r.arrowFrame.UpdateVisuals = nil end },
            { name = "icons", off = "Icons", cut = function(r) r.icons = nil end },
            { name = "profile name", off = "Setup", cut = function(r) r.settings.GetSettingsDB = nil end },
            { name = "snapshot", off = "Window", cut = function(r) r.v2.BuildGuideStepsSnapshot = nil end },
            { name = "active steps", off = "Window", cut = function(r) r.RXPFrame.activeSteps = nil end },
        }) do
            local rxp = Full()
            row.cut(rxp)
            local parts = Rules.Parts(rxp)
            for part, on in pairs(parts) do
                assert.equals(part ~= row.off, on, row.name .. ": " .. part)
            end
        end

        local rxp = Full()
        rxp.settings = nil
        local parts = Rules.Parts(rxp)
        assert.is_false(parts.Theme)
        assert.is_false(parts.Setup)
        assert.is_true(parts.Icons)
    end)

    it("returns a call's results and reports a raising site once", function()
        local reports = 0
        _G.geterrorhandler = function() return function() reports = reports + 1 end end

        local a, b = Safe.Run("site", function() return 1, 2 end)
        assert.same({ 1, 2 }, { a, b })

        for _ = 1, 3 do
            assert.is_nil((Safe.Run("broken", function() error("no") end)))
        end
        assert.equals(1, reports)
        Safe.Run("other", function() error("no") end)
        assert.equals(2, reports)
    end)
end)
