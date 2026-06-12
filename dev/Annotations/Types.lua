---@meta
-- ╔═══════════════════════════════════════════════════════════╗
-- ║  Annotations/Types.lua — 12.0 API + Frame extension stubs ║
-- ║                                                           ║
-- ║  Type-only declarations for WoW 12.0 APIs that wowlua-ls  ║
-- ║  doesn't ship by default: Secret Values introspection,    ║
-- ║  LuaDurationObject, taint-safe boolean primitives, and    ║
-- ║  typed UnitCastingDuration / UnitChannelDuration returns. ║
-- ║                                                           ║
-- ║  KE call-site counts (audit 2026-05-03):                  ║
-- ║    issecretvalue & co. — 55 sites                         ║
-- ║    LuaDurationObject methods — 9 sites                    ║
-- ║    Set*FromBoolean primitives — 7 sites in CastbarHelpers ║
-- ║                                                           ║
-- ║  Loaded by wowlua-ls only. NOT loaded by WoW. NOT shipped ║
-- ║  (Annotations/ is in .pkgmeta ignore + .gitignore).       ║
-- ║                                                           ║
-- ║  Add stubs here as new 12.0 APIs appear. KE's own helpers ║
-- ║  belong in Annotations/KE.lua, not here.                  ║
-- ╚═══════════════════════════════════════════════════════════╝

-- ─── Secret Values introspection ──────────────────────────
-- All declared in `.wowluarc.json` globals.read (line 19) for
-- recognition; this file gives them signatures and return types.

---@param value any
---@return boolean
function issecretvalue(value) end

---@param t table
---@return boolean
function issecrettable(t) end

---@param t table
---@return boolean
function canaccesstable(t) end

---@param value any
---@return boolean
function canaccessvalue(value) end

-- ─── Duration / Curve objects (12.0 secret-value-aware) ──
-- Returned by UnitCastingDuration / UnitChannelDuration. May
-- carry secret values; check :HasSecretValues() before any
-- arithmetic that would taint.

---@class LuaCurveObject

---@class LuaDurationObject
---@field Assign fun(self: LuaDurationObject, other: LuaDurationObject)
---@field copy fun(self: LuaDurationObject): LuaDurationObject
---@field EvaluateElapsedPercent fun(self: LuaDurationObject, curve: LuaCurveObject, modifier: number?): number
---@field EvaluateRemainingPercent fun(self: LuaDurationObject, curve: LuaCurveObject, modifier: number?): number
---@field GetElapsedDuration fun(self: LuaDurationObject, modifier: number?): number
---@field GetElapsedPercent fun(self: LuaDurationObject, modifier: number?): number
---@field GetEndTime fun(self: LuaDurationObject, modifier: number?): number
---@field GetModRate fun(self: LuaDurationObject): number
---@field GetRemainingDuration fun(self: LuaDurationObject, modifier: number?): number
---@field GetRemainingPercent fun(self: LuaDurationObject, modifier: number?): number
---@field GetStartTime fun(self: LuaDurationObject, modifier: number?): number
---@field GetTotalDuration fun(self: LuaDurationObject, modifier: number?): number
---@field HasSecretValues fun(self: LuaDurationObject): boolean
---@field IsZero fun(self: LuaDurationObject): boolean
---@field Reset fun(self: LuaDurationObject)
---@field SetTimeFromEnd fun(self: LuaDurationObject, endTime: number, duration: number, modRate: number?)
---@field SetTimeFromStart fun(self: LuaDurationObject, startTime: number, duration: number, modRate: number?)
---@field SetTimeSpan fun(self: LuaDurationObject, startTime: number, endTime: number)
---@field SetToDefaults fun(self: LuaDurationObject)

---@param unit string
---@return LuaDurationObject|nil
function UnitCastingDuration(unit) end

---@param unit string
---@return LuaDurationObject|nil
function UnitChannelDuration(unit) end

-- ─── Taint-safe boolean primitives ────────────────────────
-- Heavily used in Combat/CastbarHelpers.lua to set alpha or
-- vertex color from a secret-value boolean (notInterruptible)
-- without performing the boolean test in Lua, which would
-- taint. Project memory: feedback_secret_value_overguarding,
-- reference_secret_value_behaviors.

---@class Frame
---@field SetAlphaFromBoolean fun(self: Frame, bool: boolean, alphaIfTrue: number?, alphaIfFalse: number?)
---@field SetShown fun(self: Frame, bool: boolean)

---@class FontString
---@field SetAlphaFromBoolean fun(self: FontString, bool: boolean, alphaIfTrue: number?, alphaIfFalse: number?)

---@class Texture
---@field SetVertexColorFromBoolean fun(self: Texture, bool: boolean, colorIfTrue: number[], colorIfFalse: number[])

-- `duration` accepts both the project's hand-written LuaDurationObject stub
-- and the LS's bundled DurationObject type (e.g. C_Spell.GetSpellChargeDuration's
-- return) — they're the same runtime object under two annotation names.
---@class StatusBar
---@field SetTimerDuration fun(self: StatusBar, duration: LuaDurationObject|DurationObject, interpolation: any?, direction: any?)

---@class Cooldown
---@field SetSwipeTexture fun(self: Cooldown, texture: string, r: number?, g: number?, b: number?, a: number?)

-- ─── Misc 12.0 globals KE references ──────────────────────

---@type function
GameMovieFinished = GameMovieFinished

---@type function
GetMouseFocus = GetMouseFocus

---@class ElvUI_SpellBookTooltip: GameTooltip
ElvUI_SpellBookTooltip = ElvUI_SpellBookTooltip
