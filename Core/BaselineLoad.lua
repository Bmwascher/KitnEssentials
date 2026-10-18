-- ╔══════════════════════════════════════════════════════════╗
-- ║  BaselineLoad.lua                                        ║
-- ║  Purpose: Marks a load of the baseline file lists.       ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)

-- Only the TOC's baseline-client lines load this file, the same condition
-- that picks the baseline lists, so Core/Availability.lua follows the files
-- that actually loaded.
KE.BASELINE_LOAD = true
