local loader = dofile("dev/spec/_ke_loader.lua")

describe("RaidControl", function()
    local RC, KE, seams

    before_each(function()
        RC, KE, seams = loader.loadRaidControl()
    end)

    describe("module lifecycle", function()
        it("OnInitialize disables the module AND refreshes the db first", function()
            -- Ordering matters: a fresh profile must have self.db populated
            -- before anything can enable the module. Recording the call order
            -- is what a constant "always disable" implementation fails.
            local calls = {}
            RC.SetEnabledState = function(_, v) calls[#calls + 1] = "enabled:" .. tostring(v) end
            local realUpdateDB = RC.UpdateDB
            RC.UpdateDB = function(s) calls[#calls + 1] = "updatedb" realUpdateDB(s) end
            RC:OnInitialize()
            assert.same({ "updatedb", "enabled:false" }, calls)
        end)

        it("UpdateDB re-reads the live profile table every call", function()
            -- Two calls against two DIFFERENT tables. A stub that installs a
            -- fixed table passes a single-value check but fails this one, and
            -- the identity assertion rules out a copy.
            local first = { Enabled = false, Position = {}, marker = "one" }
            KE.db.profile.RaidControl = first
            RC:UpdateDB()
            assert.equals("one", RC.db.marker)
            assert.is_true(rawequal(first, RC.db))

            local second = { Enabled = true, Position = {}, marker = "two" }
            KE.db.profile.RaidControl = second
            RC:UpdateDB()
            assert.equals("two", RC.db.marker)
            assert.is_true(rawequal(second, RC.db))
        end)

        it("UpdateDB reads the FLAT profile key, not a nested one", function()
            -- Planted decoy: a nested Miscellaneous.RaidControl must be ignored.
            KE.db.profile.Miscellaneous = { RaidControl = { marker = "nested" } }
            KE.db.profile.RaidControl = { Enabled = false, Position = {}, marker = "flat" }
            RC:UpdateDB()
            assert.equals("flat", RC.db.marker)
        end)
    end)

    describe("TargetIcons_GetCoords", function()
        -- The marker atlas is a 4x4 grid read left-to-right, top-to-bottom by
        -- button ID. These four IDs pin all four rows and both edge columns;
        -- a constant return cannot satisfy more than one of them.
        local cases = {
            { id = 1, left = 0.00, right = 0.25, top = 0.00, bottom = 0.25 },
            { id = 4, left = 0.75, right = 1.00, top = 0.00, bottom = 0.25 },
            { id = 5, left = 0.00, right = 0.25, top = 0.25, bottom = 0.50 },
            { id = 8, left = 0.75, right = 1.00, top = 0.25, bottom = 0.50 },
        }

        for _, case in ipairs(cases) do
            it("maps button id " .. case.id .. " to its grid cell", function()
                local got
                local button = {
                    GetID = function() return case.id end,
                    GetNormalTexture = function()
                        return { SetTexCoord = function(_, l, r, t, b) got = { l, r, t, b } end }
                    end,
                }
                seams.targetIconsGetCoords(button)
                assert.is_not_nil(got)
                assert.is_true(math.abs(got[1] - case.left) < 1e-9)
                assert.is_true(math.abs(got[2] - case.right) < 1e-9)
                assert.is_true(math.abs(got[3] - case.top) < 1e-9)
                assert.is_true(math.abs(got[4] - case.bottom) < 1e-9)
            end)
        end
    end)

    describe("ScreenPosition", function()
        -- Returns (bottom, left): true when the frame's centre is in the
        -- lower / left half of a 1600x900 UIParent.
        -- UIParent must be installed by the loader, BEFORE the module chunk
        -- runs: the module captures it as a file-scope local, so assigning
        -- _G.UIParent here would leave the module reading a different table.
        local function withCentre(x, y)
            RC, KE, seams = loader.loadRaidControl({
                SafeCenter = function() return x, y end,
                UIParent = { GetSize = function() return 1600, 900 end },
            })
            return seams.screenPosition
        end

        it("reports bottom-left for a frame near the origin", function()
            local bottom, left = withCentre(10, 10)({})
            assert.is_true(bottom)
            assert.is_true(left)
        end)

        it("reports top-right for a frame near the far corner", function()
            local bottom, left = withCentre(1590, 890)({})
            assert.is_false(bottom)
            assert.is_false(left)
        end)

        it("treats a nil centre as the origin rather than erroring", function()
            local bottom, left = withCentre(nil, nil)({})
            assert.is_true(bottom)
            assert.is_true(left)
        end)

        it("reports top-left for a frame off the diagonal", function()
            -- The three cases above all sit on the screen diagonal, where
            -- x and y move together -- a swapped-return implementation
            -- (bottom, left = (x or 0) < w/2, (y or 0) < h/2) or a
            -- swapped-dimension one (w and h transposed) satisfies all
            -- three anyway. An off-diagonal point pins the two returns to
            -- DIFFERENT halves of the screen, so either swap fails it.
            local bottom, left = withCentre(10, 890)({})
            assert.is_false(bottom)
            assert.is_true(left)
        end)
    end)

    describe("group predicates", function()
        it("NotInPVP is false in an arena and false in a battleground", function()
            for _, kind in ipairs({ "arena", "pvp" }) do
                RC, KE, seams = loader.loadRaidControl({
                    IsInInstance = function() return true, kind end,
                })
                assert.is_false(seams.notInPVP())
            end
        end)

        it("NotInPVP is true in a party dungeon", function()
            RC, KE, seams = loader.loadRaidControl({
                IsInInstance = function() return true, "party" end,
            })
            assert.is_true(seams.notInPVP())
        end)

        it("InGroup requires BOTH being grouped and not being in PVP", function()
            local matrix = {
                { grouped = true,  kind = "party", want = true },
                { grouped = true,  kind = "arena", want = false },
                { grouped = false, kind = "party", want = false },
                { grouped = false, kind = "arena", want = false },
            }
            for _, row in ipairs(matrix) do
                RC, KE, seams = loader.loadRaidControl({
                    IsInGroup = function() return row.grouped end,
                    IsInInstance = function() return true, row.kind end,
                })
                assert.equals(row.want, seams.inGroup() and true or false)
            end
        end)
    end)

    describe("RoleIcons_AddNames", function()
        it("colours the entry by class and truncates the realm to a star", function()
            local out = {}
            seams.roleIconsAddNames(out, "Kitn-Ravencrest", "MAGE")
            assert.equals(1, #out)
            -- 0.25*255 = 63.75 -> %02x truncates to 3f; 0.78*255 -> c6; 0.92*255 -> ea
            assert.equals("|cff3fc6eaKitn*", out[1])
        end)

        it("falls back to the priest colour for an unknown class", function()
            local out = {}
            seams.roleIconsAddNames(out, "Nobody", nil)
            assert.equals("|cffffffffNobody", out[1])
        end)

        it("falls back to the priest colour when the class token is secret", function()
            -- A real class key ("MAGE") marked secret. An unguarded lookup
            -- would still find MAGE's colour in the mock's plain table --
            -- indexing does not itself error the way it would against a
            -- real secret value -- so this only fails if the guard rejects
            -- the token BEFORE the lookup, not because indexing throws.
            RC, KE, seams = loader.loadRaidControl({
                issecretvalue = function(v) return v == "MAGE" end,
            })
            local out = {}
            seams.roleIconsAddNames(out, "Nobody", "MAGE")
            assert.equals("|cffffffffNobody", out[1])
        end)

        it("leaves a realmless name untouched apart from the colour prefix", function()
            local out = {}
            seams.roleIconsAddNames(out, "Kitn", "MAGE")
            assert.equals("|cff3fc6eaKitn", out[1])
        end)
    end)

    describe("RoleIcons_SortNames", function()
        it("orders by the name AFTER the 10-character colour prefix", function()
            -- The colour codes are chosen so the two orderings DISAGREE:
            -- raw string order puts Zed first (byte 5 is "0" vs "f"), name
            -- order puts Aaa first. A comparator that forgot the strsub
            -- therefore fails this, which is the whole point. Picking the
            -- colours the other way round makes the example vacuous.
            local list = { "|cff000000Zed", "|cffffffffAaa" }
            table.sort(list, seams.roleIconsSortNames)
            assert.equals("|cffffffffAaa", list[1])
            assert.equals("|cff000000Zed", list[2])
        end)
    end)
end)
