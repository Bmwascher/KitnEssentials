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
end)
