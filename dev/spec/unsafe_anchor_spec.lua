-- Tier 1: a refusal rule. KE:IsUnsafeAnchor decides whether a Select Frame
-- choice may reach SetPoint, SetParent or CreateFrame as a parent: a wrong
-- "safe" is a Lua error in game, a wrong "unsafe" moves a display off the
-- anchor the player chose. The region fakes are static tables answering
-- GetParent, GetNumPoints, GetPoint, IsObjectType and IsForbidden with fixed
-- values, not a stateful Blizzard fake.
local L = require("dev.spec._ke_loader")

-- A frame-type widget carrying its handle at index 0; each extra argument is
-- the relativeTo of one anchor point.
local function region(parent, ...)
    local points = { ... }
    return {
        [0] = newproxy(),
        GetParent = function() return parent end,
        GetNumPoints = function() return #points end,
        GetPoint = function(_, i) return "CENTER", points[i], "CENTER", 0, 0 end,
        IsObjectType = function(_, objectType) return objectType == "Frame" end,
        IsForbidden = function() return false end,
    }
end

describe("unsafe anchor guard", function()
    local KE
    local secret = {}
    local locked = {}

    setup(function()
        KE = L.loadGlobals({
            issecretvalue = function(value) return secret[value] == true end,
            canaccesstable = function(value) return locked[value] ~= true end,
        })
    end)

    before_each(function()
        for k in pairs(secret) do secret[k] = nil end
        for k in pairs(locked) do locked[k] = nil end
    end)

    it("refuses the frame itself", function()
        local frame = region(nil)
        assert.is_true(KE:IsUnsafeAnchor(frame, frame))
    end)

    it("refuses a region whose parent chain reaches the frame", function()
        local frame = region(nil)
        local child = region(frame)
        assert.is_true(KE:IsUnsafeAnchor(frame, region(child)))
    end)

    it("refuses a region whose anchor chain reaches the frame with no parent link", function()
        local frame = region(nil)
        local follower = region(nil, frame)
        assert.is_true(KE:IsUnsafeAnchor(frame, region(nil, follower)))
    end)

    it("accepts a region that does not depend on the frame", function()
        local frame = region(nil)
        local rows = {
            { name = "chain ending at UIParent", frame = frame,
              candidate = region(region(_G.UIParent), _G.UIParent) },
            { name = "chain ending at nil", frame = frame, candidate = region(region(nil)) },
            { name = "no frame argument", candidate = region(nil) },
        }
        for _, row in ipairs(rows) do
            assert.is_false(KE:IsUnsafeAnchor(row.frame, row.candidate), row.name)
        end
    end)

    it("refuses a value that is not a region, with or without a frame", function()
        local frame = region(nil)
        local methodsOnly = {
            GetParent = function() end,
            GetNumPoints = function() return 0 end,
            GetPoint = function() end,
            IsObjectType = function() return true end,
            IsForbidden = function() return false end,
        }
        local secretRegion = region(nil)
        local lockedRegion = region(nil)
        secret[secretRegion] = true
        locked[lockedRegion] = true
        local forbiddenRegion = region(nil)
        forbiddenRegion.IsForbidden = function() return true end
        local hiddenSecurity = region(nil)
        local hiddenAnswer = {}
        secret[hiddenAnswer] = true
        hiddenSecurity.IsForbidden = function() return hiddenAnswer end
        local rows = {
            { name = "methods without a handle", value = methodsOnly },
            { name = "string", value = "UIParent" },
            { name = "number", value = 42 },
            { name = "nil" },
            { name = "secret value", value = secretRegion },
            { name = "unreadable table", value = lockedRegion },
            { name = "forbidden region", value = forbiddenRegion },
            { name = "secret forbidden answer", value = hiddenSecurity },
        }
        for _, row in ipairs(rows) do
            assert.is_true(KE:IsUnsafeAnchor(frame, row.value), row.name .. " with a frame")
            assert.is_true(KE:IsUnsafeAnchor(nil, row.value), row.name .. " without a frame")
        end
    end)

    it("does not follow a secret, unreadable or forbidden parent or anchor target", function()
        local frame = region(nil)
        local hiddenChild = region(frame)
        local hiddenFollower = region(nil, frame)
        local lockedChild = region(frame)
        local forbiddenChild = region(region(frame))
        forbiddenChild.IsForbidden = function() return true end
        secret[hiddenChild] = true
        secret[hiddenFollower] = true
        locked[lockedChild] = true
        local rows = {
            { name = "secret parent", candidate = region(hiddenChild) },
            { name = "secret anchor target", candidate = region(nil, hiddenFollower) },
            { name = "unreadable parent", candidate = region(lockedChild) },
            { name = "forbidden parent", candidate = region(forbiddenChild) },
        }
        for _, row in ipairs(rows) do
            assert.is_false(KE:IsUnsafeAnchor(frame, row.candidate), row.name)
        end
    end)

    it("refuses a chain longer than the walk limit that never reaches the frame", function()
        local chain = region(nil)
        for _ = 1, 99 do chain = region(chain) end
        assert.is_true(KE:IsUnsafeAnchor(region(nil), chain))
    end)

    it("ResolveAnchorFrame falls back to UIParent for an unsafe choice, printing once per name", function()
        local printed = {}
        KE.Print = function(_, msg) printed[#printed + 1] = msg end
        local frame = region(nil)
        local other = region(nil)
        local text = region(nil)
        text.IsObjectType = function() return false end
        local hidden = region(nil)
        secret[hidden] = true
        _G.KE_SpecAnchorSelf = frame
        _G.KE_SpecAnchorOther = other
        _G.KE_SpecAnchorTable = {}
        _G.KE_SpecAnchorText = text
        _G.KE_SpecAnchorSecret = hidden

        assert.equal(other, KE:ResolveAnchorFrame("SELECTFRAME", "KE_SpecAnchorOther", frame))
        assert.equal(_G.UIParent, KE:ResolveAnchorFrame("SELECTFRAME", "KE_SpecAnchorMissing", frame))
        assert.equal(0, #printed)
        assert.equal(_G.UIParent, KE:ResolveAnchorFrame("SELECTFRAME", "KE_SpecAnchorSelf", frame))
        assert.equal(_G.UIParent, KE:ResolveAnchorFrame("SELECTFRAME", "KE_SpecAnchorSelf", frame))
        assert.equal(1, #printed)
        assert.equal(_G.UIParent, KE:ResolveAnchorFrame("SELECTFRAME", "KE_SpecAnchorTable"))
        assert.equal(2, #printed)
        assert.equal(text, KE:ResolveAnchorFrame("SELECTFRAME", "KE_SpecAnchorText", frame))
        assert.equal(_G.UIParent, KE:ResolveAnchorFrame("SELECTFRAME", "KE_SpecAnchorText", frame, true))
        assert.equal(3, #printed)
        assert.equal(_G.UIParent, KE:ResolveAnchorFrame("SELECTFRAME", "KE_SpecAnchorSecret", frame))
        assert.equal(4, #printed)

        _G.KE_SpecAnchorSelf, _G.KE_SpecAnchorOther = nil, nil
        _G.KE_SpecAnchorTable, _G.KE_SpecAnchorText = nil, nil
        _G.KE_SpecAnchorSecret = nil
    end)

    it("refuses a region that is not a frame as a parent, but not as an anchor", function()
        local frame = region(nil)
        local text = region(nil)
        text.IsObjectType = function() return false end
        local hidden = region(nil)
        local hiddenType = {}
        secret[hiddenType] = true
        hidden.IsObjectType = function() return hiddenType end
        assert.is_true(KE:IsUnsafeAnchor(frame, text, true), "text as a parent")
        assert.is_false(KE:IsUnsafeAnchor(frame, text), "text as an anchor")
        assert.is_true(KE:IsUnsafeAnchor(frame, hidden, true), "secret object type as a parent")
        assert.is_true(KE:IsUnsafeAnchor(nil, text, true), "text as a parent with no frame")
    end)

    it("counts each region once, so a small graph with shared ancestors is accepted", function()
        local graph = { region(_G.UIParent) }
        graph[2] = region(graph[1])
        for n = 3, 9 do graph[n] = region(graph[n - 1], graph[n - 2]) end
        assert.is_false(KE:IsUnsafeAnchor(region(nil), graph[9]))
    end)

    it("starts each walk clean after a walk an error interrupted", function()
        local frame = region(nil)
        local failing = true
        local link = region(nil)
        link.GetParent = function()
            if failing then error("interrupted") end
            return frame
        end
        assert.is_false(pcall(KE.IsUnsafeAnchor, KE, frame, region(nil, link)))
        failing = false
        assert.is_true(KE:IsUnsafeAnchor(frame, region(nil, link)))
    end)

    it("refuses a follower and any region that depends on one", function()
        local frame = region(nil)
        local follower = region(nil)
        local followers = { follower }
        local rows = {
            { name = "the follower itself", candidate = follower },
            { name = "parent chain reaches a follower", candidate = region(region(follower)) },
            { name = "anchor chain reaches a follower", candidate = region(nil, region(nil, follower)) },
        }
        for _, row in ipairs(rows) do
            assert.is_true(KE:IsUnsafeAnchor(frame, row.candidate, nil, followers), row.name)
        end
    end)

    it("accepts a region no follower reaches when followers are given", function()
        local frame = region(nil)
        local follower = region(nil)
        assert.is_false(KE:IsUnsafeAnchor(frame, region(region(nil)), nil, { follower }))
    end)

    it("carries no follower from one call into the next", function()
        local frame = region(nil)
        local follower = region(nil)
        assert.is_true(KE:IsUnsafeAnchor(frame, follower, nil, { follower }))
        assert.is_false(KE:IsUnsafeAnchor(frame, follower), "no list from the previous call")
    end)

    it("ResolveAnchorFrame refuses a follower of the display with the line", function()
        local printed = {}
        KE.Print = function(_, msg) printed[#printed + 1] = msg end
        local frame = region(nil)
        local follower = region(nil)
        _G.KE_SpecFollower = follower
        assert.equal(_G.UIParent, KE:ResolveAnchorFrame("SELECTFRAME", "KE_SpecFollower", frame, nil, { follower }))
        assert.equal(1, #printed)
        assert.equal(follower, KE:ResolveAnchorFrame("SELECTFRAME", "KE_SpecFollower", frame))
        _G.KE_SpecFollower = nil
    end)

    it("ResolveAnchorFrame walks a dotted name to the child it names", function()
        local printed = {}
        KE.Print = function(_, msg) printed[#printed + 1] = msg end
        local child = region(nil)
        local numbered = region(nil)
        local root = region(nil)
        root.Content = child
        root[1] = numbered
        _G.KE_SpecDotRoot = root
        local rows = {
            { name = "raw child key", path = "KE_SpecDotRoot.Content", want = child },
            { name = "numeric key", path = "KE_SpecDotRoot.1", want = numbered },
        }
        for _, row in ipairs(rows) do
            assert.equal(row.want, KE:ResolveAnchorFrame("SELECTFRAME", row.path, region(nil)), row.name)
        end
        assert.equal(0, #printed)
        _G.KE_SpecDotRoot = nil
    end)

    it("ResolveAnchorFrame refuses a dotted dead end with the line, and waits silently for a missing first frame", function()
        local printed = {}
        KE.Print = function(_, msg) printed[#printed + 1] = msg end
        local hidden = region(nil)
        secret[hidden] = true
        local unreadable = {}
        locked[unreadable] = true
        local root = region(nil)
        root.Hidden = hidden
        root.Unreadable = unreadable
        _G.KE_SpecDeadRoot = root
        local rows = {
            { name = "missing key", path = "KE_SpecDeadRoot.Missing", lines = 1 },
            { name = "secret step", path = "KE_SpecDeadRoot.Hidden.Child", lines = 1 },
            { name = "unreadable step", path = "KE_SpecDeadRoot.Unreadable.Child", lines = 1 },
            { name = "missing first frame", path = "KE_SpecNoRoot.Child", lines = 0 },
            { name = "name that is not a string", path = true, lines = 0 },
        }
        for _, row in ipairs(rows) do
            local before = #printed
            assert.equal(_G.UIParent, KE:ResolveAnchorFrame("SELECTFRAME", row.path, region(nil)), row.name)
            assert.equal(row.lines, #printed - before, row.name)
        end
        _G.KE_SpecDeadRoot = nil
    end)

    it("ResolveAnchorFrame refuses an Edit Mode box by name, whatever the global holds", function()
        local printed = {}
        KE.Print = function(_, msg) printed[#printed + 1] = msg end
        _G.KE_EditMode_SpecBox = region(nil)
        assert.equal(_G.UIParent, KE:ResolveAnchorFrame("SELECTFRAME", "KE_EditMode_SpecBox", region(nil)))
        assert.equal(1, #printed)
        _G.KE_EditMode_SpecBox = nil
    end)

    -- The loader's UIParent is a no-op table with no widget handle, which
    -- IsRegion refuses, so the case swaps in a region fake for its rows.
    it("ResolveSelectFrame returns nil for each refusal, and UIParent for a name that holds it", function()
        local frame = region(nil)
        local savedParent = _G.UIParent
        finally(function()
            _G.UIParent = savedParent
            _G.KE_SpecSelectAlias, _G.KE_SpecSelectSelf, _G.KE_EditMode_SpecSelect = nil, nil, nil
        end)
        _G.UIParent = region(nil)
        _G.KE_SpecSelectAlias = _G.UIParent
        _G.KE_SpecSelectSelf = frame
        _G.KE_EditMode_SpecSelect = region(nil)
        local rows = {
            { name = "a name holding UIParent", path = "KE_SpecSelectAlias", want = _G.UIParent, missing = false },
            { name = "the display itself", path = "KE_SpecSelectSelf", missing = false },
            { name = "an Edit Mode box", path = "KE_EditMode_SpecSelect", missing = false },
            { name = "a missing first frame", path = "KE_SpecSelectNoRoot", missing = true },
        }
        for _, row in ipairs(rows) do
            local got, missing = KE:ResolveSelectFrame(row.path, frame)
            assert.equal(row.want, got, row.name)
            assert.equal(row.missing, missing, row.name)
        end
    end)

    it("IsEditModeBoxName matches every Edit Mode frame name and nothing else", function()
        local rows = {
            { name = "KE_EditMode_Chat", want = true },
            { name = "KE_EditMode_Chat.text", want = true },
            { name = "KE_EditMode", want = true },
            { name = "KE_EditModeNudge", want = true },
            { name = "KE_EditModeEscape", want = true },
            { name = "KE_EditModeShift", want = true },
            { name = "KE_EditModeGuides", want = true },
            { name = "KE_ChatPanel", want = false },
            { name = "MyKE_EditModeNudge", want = false },
            { name = nil, want = false },
            { name = 42, want = false },
        }
        for _, row in ipairs(rows) do
            assert.equal(row.want, KE:IsEditModeBoxName(row.name), tostring(row.name))
        end
    end)
end)
