local helpers = require("dev.spec._helpers")

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
