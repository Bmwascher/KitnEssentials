-- dev/spec/api_drift_spec.lua
local C = dofile("dev/scripts/_api_drift_core.lua")

describe("api-drift core (dev/scripts/_api_drift_core.lua)", function()

    describe("serializeRecord", function()
        it("is stable across key order and recurses into nested tables", function()
            local a = C.serializeRecord({ Name = "Foo", Type = "number", Nilable = true,
                Inner = { X = 1, Y = "s" } })
            local b = C.serializeRecord({ Inner = { Y = "s", X = 1 }, Nilable = true,
                Type = "number", Name = "Foo" })
            assert.equals(a, b)
        end)
        it("differs when any scalar (e.g. a secret flag) flips", function()
            local plain  = C.serializeRecord({ Name = "r1", Type = "number" })
            local secret = C.serializeRecord({ Name = "r1", Type = "number", SecretReturns = true })
            assert.not_equals(plain, secret)
        end)
    end)

    describe("flattenDocs", function()
        local tables = {
            { Namespace = "C_Toy", Type = "System",
              Functions = { { Name = "GetToy", Type = "Function",
                  Arguments = { { Name = "id", Type = "number" } },
                  Returns   = { { Name = "name", Type = "cstring" } } } },
              Events = { { LiteralName = "TOYS_UPDATED", Type = "Event",
                  Payload = { { Name = "new", Type = "bool" } } } } },
            { Type = "System",   -- no Namespace: functions are globals
              Functions = { { Name = "UnitFoo", Type = "Function" } } },
            { Type = "System",   -- enums nest under Tables in real doc files
              Tables = { { Name = "ToyQuality", Type = "Enumeration", NumValues = 2,
                  Fields = { { Name = "Common", Type = "ToyQuality", EnumValue = 0 },
                             { Name = "Rare",   Type = "ToyQuality", EnumValue = 1 } } } } },
        }
        local flat = C.flattenDocs(tables)
        it("keys namespaced functions as C_Ns.Name and bare globals as Name", function()
            assert.is_string(flat.functions["C_Toy.GetToy"])
            assert.is_string(flat.functions["UnitFoo"])
        end)
        it("serializes argument and return contents into the function record", function()
            assert.matches("id", flat.functions["C_Toy.GetToy"])
            assert.matches("cstring", flat.functions["C_Toy.GetToy"])
        end)
        it("keys events by LiteralName with payload in the record", function()
            assert.matches("new", flat.events["TOYS_UPDATED"])
        end)
        it("keys enum members as Enum.Name.Member with numeric value", function()
            assert.equals(0, flat.enums["Enum.ToyQuality.Common"])
            assert.equals(1, flat.enums["Enum.ToyQuality.Rare"])
        end)
    end)

    describe("diffMaps", function()
        local old = { A = "1", B = "2", C = "3" }
        local new = { A = "1", B = "2x", D = "4" }
        local d = C.diffMaps(old, new)
        it("finds added, removed, changed — sorted", function()
            assert.same({ "D" }, d.added)
            assert.same({ "C" }, d.removed)
            assert.same({ "B" }, d.changed)
        end)
        it("reports enum renumbers as changed", function()
            local e = C.diffMaps({ ["Enum.X.A"] = 5 }, { ["Enum.X.A"] = 6 })
            assert.same({ "Enum.X.A" }, e.changed)
        end)
    end)

    describe("usedPredicates / filterUsed", function()
        local used = {
            names = { UnitFoo = true },                -- bare globals/frames
            nsCalls = { ["C_Toy.GetToy"] = true },      -- C_Ns.member call sites
            nsAll = { C_Toy = true },                   -- namespaces touched at all
            events = { TOYS_UPDATED = true },
            enums = { ["Enum.ToyQuality.Rare"] = true },
            cvars = { someCVar = true },
        }
        local p = C.usedPredicates(used)
        it("matches functions by exact key or bare-global name", function()
            assert.is_true(p.fn("C_Toy.GetToy"))
            assert.is_true(p.fn("UnitFoo"))
            assert.is_false(p.fn("C_Toy.Other"))
            assert.is_false(p.fn("C_Other.GetToy"))
        end)
        it("namespace-additions predicate matches any member of a used namespace", function()
            assert.is_true(p.fnNsAddition("C_Toy.Brand New"))
            assert.is_false(p.fnNsAddition("C_Other.New"))
        end)
        it("filterUsed splits hits from a miss count", function()
            local r = C.filterUsed({ "C_Toy.GetToy", "C_Other.X", "UnitFoo" }, p.fn)
            assert.same({ "C_Toy.GetToy", "UnitFoo" }, r.hit)
            assert.equals(1, r.miss)
        end)
    end)

    describe("harvestUsedFromSource", function()
        local used = C.newUsedSurface()
        C.harvestUsedFromSource([[
            local n = UnitFoo("player")
            local t = C_Toy.GetToy(5); C_Toy:Weird(1)
            if q == Enum.ToyQuality.Rare then end
            f:RegisterEvent("TOYS_UPDATED")
            SetCVar("someCVar", 1); C_CVar.GetCVar("otherCVar")
            local x = _G.LegacyGlobal
        ]], used)
        it("collects bare names, ns calls, enums, events, cvars, _G forms", function()
            assert.is_true(used.names.UnitFoo)
            assert.is_true(used.nsCalls["C_Toy.GetToy"])
            assert.is_true(used.nsCalls["C_Toy.Weird"])
            assert.is_true(used.nsAll.C_Toy)
            assert.is_true(used.enums["Enum.ToyQuality.Rare"])
            assert.is_true(used.events.TOYS_UPDATED)
            assert.is_true(used.cvars.someCVar)
            assert.is_true(used.cvars.otherCVar)
            assert.is_true(used.names.LegacyGlobal)
        end)
    end)

    describe("parseBIRSource", function()
        local P = dofile("dev/scripts/_apidocs_parser.lua")
        it("harvests names from a returned list", function()
            local s = C.parseBIRSource('return { "GetFoo", "GetBar" }', P.loadSandboxed)
            assert.is_true(s.GetFoo and s.GetBar)
        end)
        it("harvests from nested/global-assigned tables", function()
            local s = C.parseBIRSource(
                'GlobalAPI = { api = { "UnitA" }, events = { "EV_B" } }', P.loadSandboxed)
            assert.is_true(s.UnitA and s.EV_B)
        end)
        it("falls back to quoted-name regex on unloadable source", function()
            local s = C.parseBIRSource('this is not lua "StillFound"', P.loadSandboxed)
            assert.is_true(s.StillFound)
        end)
    end)

    describe("snapshot round-trip", function()
        it("serialize -> load restores the maps", function()
            local P = dofile("dev/scripts/_apidocs_parser.lua")
            local snap = { build = "12.0.7.68275", date = "2026-07-01",
                functions = { ["C_Toy.GetToy"] = "Name=GetToy" },
                events = { TOYS_UPDATED = "LiteralName=TOYS_UPDATED" },
                enums = { ["Enum.ToyQuality.Rare"] = 1 },
                dirs = { "Blizzard_Toys" },
                bir = { globals = { UnitFoo = true }, cvars = {}, events = {},
                        frames = {}, mixins = {} } }
            local back = C.loadSnapshotFromString(C.serializeSnapshot(snap), P.loadSandboxed)
            assert.same(snap, back)
        end)
    end)

    describe("renderReport", function()
        it("exit 1 with breaking lines, 0 without; sections render", function()
            local lines, code = C.renderReport({
                oldBuild = "A", newBuild = "B", oldDate = "d1", date = "d2",
                sections = { breaking = { "C_X.Y REMOVED" }, cside = {}, additions = {} },
                fyiTotal = 10, fyiUsed = 1, links = {} })
            assert.equals(1, code)
            local text = table.concat(lines, "\n")
            assert.matches("%[BREAKING%-USED%]", text)
            assert.matches("C_X%.Y REMOVED", text)
            local _, code0 = C.renderReport({ oldBuild = "A", newBuild = "B",
                oldDate = "d1", date = "d2",
                sections = { breaking = {}, cside = {}, additions = {} },
                fyiTotal = 0, fyiUsed = 0, links = {} })
            assert.equals(0, code0)
        end)

        it("exits 1 when a non-allowlisted c-side removal hits the used surface", function()
            local _, code = C.renderReport({
                oldBuild = "a", newBuild = "b", oldDate = "d1", date = "d2",
                sections = { breaking = {}, cside = { "IsWargame  REMOVED from globals dump" }, additions = {} },
                csideGating = 1, fyiTotal = 0, fyiUsed = 0, links = {},
            })
            assert.equals(1, code)
        end)

        it("exits 0 when every c-side removal is allowlisted", function()
            local _, code = C.renderReport({
                oldBuild = "a", newBuild = "b", oldDate = "d1", date = "d2",
                sections = { breaking = {}, cside = { "X  REMOVED from globals dump  (drift-check allowlisted: ok)" }, additions = {} },
                csideGating = 0, fyiTotal = 0, fyiUsed = 0, links = {},
            })
            assert.equals(0, code)
        end)
    end)
end)
