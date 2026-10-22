local helpers = require("dev.spec._helpers")
local loader = require("dev.spec._ke_loader")

describe("KE:CompareVersions", function()
    local KE = helpers.loadModule("Core/VersionCompare.lua")

    it("orders by numeric segment, not by string", function()
        assert.equal(1, KE:CompareVersions("8.6.10", "8.6.4"))
        assert.equal(-1, KE:CompareVersions("8.5.9", "8.6.4"))
        assert.equal(0, KE:CompareVersions("8.6.4", "8.6.4"))
    end)

    it("treats a missing or unparseable version as lower", function()
        assert.equal(-1, KE:CompareVersions(nil, "8.6.4"))
        assert.equal(-1, KE:CompareVersions("", "8.6.4"))
        assert.equal(-1, KE:CompareVersions("v-unknown", "8.6.4"))
    end)

    it("tolerates differing segment counts", function()
        assert.equal(-1, KE:CompareVersions("8.6", "8.6.1"))
        assert.equal(0, KE:CompareVersions("8.6.0", "8.6"))
    end)
end)

describe("VersionCheck decisions", function()
    local VC = loader.loadVersionCheck()

    it("ParseMessage accepts only V:<digits and dots>", function()
        local cases = {
            { "V:4.13.12", "4.13.12" },
            { "V:5", "5" },
            { "V:", nil },
            { "V:.4", nil },
            { "V:v4.13.12", nil },
            { "V:4.13.12-beta1", nil },
            { "V:4.13.12-5-gabcdef", nil },
            { "X:4.13.12", nil },
            { " V:4.13.12", nil },
        }
        for _, c in ipairs(cases) do
            assert.equal(c[2], VC.ParseMessage(c[1]), c[1])
        end
        assert.is_nil(VC.ParseMessage(nil))
        assert.is_nil(VC.ParseMessage(42))
    end)

    it("IsPlausible rejects an over-long version and a major more than one ahead", function()
        assert.is_true(VC.IsPlausible("4.13.13", "4.13.12"))
        assert.is_true(VC.IsPlausible("5.0.0", "4.13.12"))
        assert.is_false(VC.IsPlausible("6.0.0", "4.13.12"))
        assert.is_false(VC.IsPlausible("4.13.12345678", "4.13.12"))
    end)

    it("SpokenVersion picks the own version or LAST_RELEASE and refuses unusable values", function()
        local cases = {
            -- isDevCopy, mine, lastRelease, expected
            { false, "4.13.12", "4.13.1", "4.13.12" },
            { true, "4.13.12", "4.13.1", "4.13.1" },
            { true, "4.13.12", nil, nil },
            { true, "4.13.12", "4.13.1-x", nil },
            { false, "4.13.12-beta1", "4.13.1", nil },
            { false, "4.13.12-5-gabcdef", "4.13.1", nil },
            { false, nil, "4.13.1", nil },
        }
        for _, c in ipairs(cases) do
            assert.equal(c[4], VC.SpokenVersion(c[1], c[2], c[3]),
                table.concat({ tostring(c[1]), tostring(c[2]), tostring(c[3]) }, " "))
        end
    end)

    it("HeardAction picks newer, reply, cancel or ignore", function()
        local cases = {
            -- theirs, mine, spoken, channel, expected
            { "4.13.13", "4.13.12", "4.13.12", "GUILD", "newer" },
            { "6.0.0", "4.13.12", "4.13.12", "GUILD", "ignore" },
            { "4.13.11", "4.13.12", "4.13.12", "GUILD", "reply" },
            { "4.13.11", "4.13.12", "4.13.12", "PARTY", "reply" },
            { "4.13.11", "4.13.12", "4.13.12", "RAID", "reply" },
            { "4.13.11", "4.13.12", "4.13.12", "INSTANCE_CHAT", "reply" },
            { "4.13.11", "4.13.12", "4.13.12", "WHISPER", "ignore" },
            { "4.13.12", "4.13.12", "4.13.12", "GUILD", "cancel" },
            { "4.13.11", "4.13.12", nil, "GUILD", "ignore" },
            { "4.13.13", "4.13.12", "4.13.1", "GUILD", "newer" },
            { "4.13.5", "4.13.12", "4.13.1", "GUILD", "cancel" },
            { "4.13.1", "4.13.12", "4.13.1", "GUILD", "cancel" },
            { "4.13.0", "4.13.12", "4.13.1", "GUILD", "reply" },
        }
        for _, c in ipairs(cases) do
            assert.equal(c[5], VC.HeardAction(c[1], c[2], c[3], c[4]),
                table.concat({ c[1], c[2], tostring(c[3]), c[4] }, " "))
        end
    end)

    it("CanSend refuses a locked copy and an unusable or missing spoken version", function()
        assert.is_true(VC.CanSend(false, "4.13.1"))
        local refused = {
            { true, "4.13.1" },
            { false, nil },
            { false, "4.13.12-beta1" },
        }
        for _, c in ipairs(refused) do
            assert.is_false(VC.CanSend(c[1], c[2]), tostring(c[1]) .. " " .. tostring(c[2]))
        end
    end)

    it("NewestAbove returns the newest heard version only when it beats mine", function()
        assert.equal("4.13.14", VC.NewestAbove("4.13.12", "4.13.13", "4.13.14"))
        assert.equal("4.13.14", VC.NewestAbove("4.13.12", "4.13.14", "4.13.13"))
        assert.equal("4.13.13", VC.NewestAbove("4.13.12", nil, "4.13.13"))
        assert.is_nil(VC.NewestAbove("4.13.12", "4.13.12", "4.13.11"))
        assert.is_nil(VC.NewestAbove("4.13.12", nil, nil))
        assert.is_nil(VC.NewestAbove("4.13.12", 42, "x"))
    end)

    it("GroupChannel prefers raid, then party, then instance", function()
        assert.equal("RAID", VC.GroupChannel(true, true, true))
        assert.equal("PARTY", VC.GroupChannel(false, true, true))
        assert.equal("INSTANCE_CHAT", VC.GroupChannel(false, false, true))
        assert.is_nil(VC.GroupChannel(false, false, false))
    end)

    it("ShouldNotify allows one notice per session, only with the switch on and something newer", function()
        assert.is_true(VC.ShouldNotify(false, true, "4.13.13"))
        assert.is_false(VC.ShouldNotify(true, true, "4.13.13"))
        assert.is_false(VC.ShouldNotify(false, false, "4.13.13"))
        assert.is_false(VC.ShouldNotify(false, true, nil))
    end)

    it("IsUsableVersion refuses dev, pre-release, untagged, over-long and non-string versions", function()
        assert.is_true(VC.IsUsableVersion("4.13.12"))
        local refused = { "dev", "4.13.12-beta1", "4.13.12-5-gabcdef", "v4.13.12", "4.13.12345678", "", 4.13 }
        for _, v in ipairs(refused) do
            assert.is_false(VC.IsUsableVersion(v), tostring(v))
        end
        assert.is_false(VC.IsUsableVersion(nil))
    end)

    it("PrefixHeld accepts Success and DuplicatePrefix only", function()
        -- The harness Enum has no RegisterAddonMessagePrefixResult, so the
        -- module falls back to the documented values 0 to 3.
        local cases = {
            -- ok, result, expected
            { true, 0, true },
            { true, 1, true },
            { true, 2, false },
            { true, 3, false },
            { false, 0, false },
        }
        for _, c in ipairs(cases) do
            assert.equal(c[3], VC.PrefixHeld(c[1], c[2]), tostring(c[1]) .. " " .. tostring(c[2]))
        end
    end)
end)
