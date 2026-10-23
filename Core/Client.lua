-- ╔══════════════════════════════════════════════════════════╗
-- ║  Client.lua                                              ║
-- ║  Purpose: Which game client is running, decided once     ║
-- ║           from the interface version.                    ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)

-- The interface version decides, never the project ID: the Forever client
-- loads mainline TOCs without reporting the mainline project. An unreadable
-- value is not Forever, so nothing Forever-only starts on a guess.
local getBuildInfo = _G.GetBuildInfo
local interface = getBuildInfo and select(4, getBuildInfo())
KE.IS_FOREVER = type(interface) == "number" and interface >= 16000 and interface < 20000
