---@meta
-- ╔═════════════════════════════════════════════════════════════╗
-- ║  Annotations/Types.lua — compat globals + third-party       ║
-- ║  stubs ONLY                                                 ║
-- ║                                                             ║
-- ║  wowlua-ls 0.23.0's bundled API DB natively ships the full  ║
-- ║  12.0 secret-value surface with correct 12.0.7 signatures:  ║
-- ║  issecretvalue/issecrettable/canaccesstable/canaccessvalue, ║
-- ║  LuaDurationObject + LuaCurveObject, UnitCastingDuration /  ║
-- ║  UnitChannelDuration, Set*FromBoolean primitives,           ║
-- ║  StatusBar:SetTimerDuration, Cooldown:SetSwipeTexture.      ║
-- ║  Verified 2026-07 by decompressing                          ║
-- ║  server/stubs/precomputed.bin.zst — this file no longer     ║
-- ║  re-declares any of that (the old hand-stubs had drifted    ║
-- ║  wrong in several places vs. the official signatures).      ║
-- ║                                                             ║
-- ║  What remains here:                                         ║
-- ║    (a) removed-API compat globals KE keeps behind nil-checks║
-- ║    (b) third-party addon stubs                              ║
-- ║                                                             ║
-- ║  Loaded by wowlua-ls only. NOT loaded by WoW. NOT shipped   ║
-- ║  (Annotations/ is in .pkgmeta ignore + .gitignore).         ║
-- ║                                                             ║
-- ║  Do NOT add new 12.0 API stubs here unless `wowlua_ls check`║
-- ║  proves the native DB lacks them. KE's own helpers belong in║
-- ║  Annotations/KE.lua, not here.                              ║
-- ╚═════════════════════════════════════════════════════════════╝

-- ─── Removed-API compat globals ───────────────────────────────

---@type function
GameMovieFinished = GameMovieFinished

-- GetMouseFocus was REMOVED in 12.0. KE keeps a guarded call behind
-- `if GetMouseFocus then` in GUI/GUIHelpers/GUI-FrameChooser.lua:111
-- (documented in the .luacheckrc drift allowlist). Typed nilable so the
-- LS reflects that the global may not exist at runtime.
---@type function|nil
GetMouseFocus = GetMouseFocus

-- ─── Third-party addon stubs ───────────────────────────────────

---@class ElvUI_SpellBookTooltip: GameTooltip
ElvUI_SpellBookTooltip = ElvUI_SpellBookTooltip
