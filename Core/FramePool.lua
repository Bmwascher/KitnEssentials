-- ╔══════════════════════════════════════════════════════════╗
-- ║  FramePool.lua                                           ║
-- ║  Module: KE.FramePool                                    ║
-- ║  Purpose: Reusable typed frame pool. Lets GUI code that  ║
-- ║           rebuilds frames per-render reuse them instead  ║
-- ║           of leaking via SetParent(nil) -> UIParent      ║
-- ║           orphaning.                                     ║
-- ║                                                          ║
-- ║  Pattern matches Blizzard's FramePool / FramePoolMixin:  ║
-- ║  consumer calls ReleaseAll() at top of render to mark    ║
-- ║  every kit idle, then Acquire(parent) per kit needed.    ║
-- ║  Surplus kits stay hidden in the pool's holder; new      ║
-- ║  demand grows the pool. No individual Release().         ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

local CreateFrame = CreateFrame
local UIParent = UIParent

---@class KE.FramePool
---@field _factory  fun(holder: Frame): table
---@field _resetter fun(kit: table)?
---@field _holder   Frame
---@field _kits     table[]
---@field _activeCount integer
local FramePool = {}
FramePool.__index = FramePool

--- Create a new typed pool.
---@param factory  fun(holder: Frame): table  -- creates one kit when pool is empty
---@param resetter fun(kit: table)?           -- optional; called on each kit during ReleaseAll
---@return KE.FramePool
function FramePool:New(factory, resetter)
    local instance = setmetatable({}, FramePool)
    instance._factory = factory
    instance._resetter = resetter
    instance._holder = CreateFrame("Frame", nil, UIParent)
    instance._holder:Hide()
    instance._kits = {}
    instance._activeCount = 0
    return instance
end

--- Borrow a kit, reparenting it to `parent`. Grows the pool on demand.
--- O(1) amortized — index-based lookup, no table search.
---@param parent Frame
---@return table kit
function FramePool:Acquire(parent)
    self._activeCount = self._activeCount + 1
    local kit = self._kits[self._activeCount]
    if not kit then
        kit = self._factory(self._holder)
        self._kits[self._activeCount] = kit
    end
    -- Kits expose their root Frame as kit.row by convention. Other sub-frames
    -- ride along since they're descendants of the root.
    local root = kit.row or kit.frame or kit
    root:SetParent(parent)
    root:Show()
    return kit
end

--- Mark every active kit as idle. Reparents kits back to the pool's hidden
--- holder (so subsequent ClearContent passes don't orphan them) and calls
--- the resetter on each. Always called at the top of a render before any
--- Acquire — there is no individual Release.
function FramePool:ReleaseAll()
    for i = 1, self._activeCount do
        local kit = self._kits[i]
        local root = kit.row or kit.frame or kit
        root:SetParent(self._holder)
        root:Hide()
        if self._resetter then
            self._resetter(kit)
        end
    end
    self._activeCount = 0
end

KE.FramePool = FramePool
