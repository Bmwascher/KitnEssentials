---@meta
-- ╔══════════════════════════════════════════════════════════╗
-- ║  Annotations/KE.lua — type-only definitions              ║
-- ║                                                          ║
-- ║  Loaded by wowlua-ls for editor autocomplete + nil-      ║
-- ║  checking. NOT loaded by WoW (not listed in any .xml     ║
-- ║  manifest). NOT shipped (this folder is in .pkgmeta      ║
-- ║  ignore + .gitignore).                                   ║
-- ║                                                          ║
-- ║  Add fields/methods here as the LS flags them. This is   ║
-- ║  a living seed — extend, don't replace.                  ║
-- ╚══════════════════════════════════════════════════════════╝

---@class AceDB
---@field profile table
---@field global table
---@field defaults table
local AceDB

---@class KETheme
---@field accent number[]
---@field rowHeight number
---@field rowHeightLast number
---@field rowHeightSeparator number
---@field paddingSmall number
---@field paddingMedium number
---@field paddingLarge number
---@field bgLight number[]
---@field bgMedium number[]
---@field bgDark number[]
---@field border number[]
---@field borderSize number
---@field textPrimary number[]
---@field textSecondary number[]
---@field sidebarWidth number
---@field contentWidth number
local KETheme

-- Animation curves created via C_CurveUtil.CreateCurve() in Core/Curves.lua.
-- Typed as CurveObjectBase (the wowlua-ls alias for LuaCurveObjectBase) so
-- they're accepted by APIs like UnitHealthPercent / DurationObject:Evaluate.
---@class KE.Curves
---@field HealthMissingAlpha CurveObjectBase
---@field DurationDecimals CurveObjectBase

---@class KE.FramePool
local KE_FramePool = {}

--- Create a new typed pool.
---@param factory  fun(holder: Frame): table
---@param resetter fun(kit: table)?
---@return KE.FramePool
function KE_FramePool:New(factory, resetter) end

--- Borrow a kit, reparenting it to `parent`. Grows the pool on demand.
---@param parent Frame
---@return table kit
function KE_FramePool:Acquire(parent) end

--- Mark every active kit as idle. Reparents kits back to the pool's
--- hidden holder. Always called at the top of a render.
function KE_FramePool:ReleaseAll() end

---@class KE
---@field db AceDB
---@field FONT string
---@field LSM table
---@field Theme KETheme
---@field GUIFrame table
---@field EditMode table
---@field ProfileManager table
---@field DungeonTimerPresets table
---@field GUI table
---@field FramePool KE.FramePool
---@field curves KE.Curves
---@field defaults table
---@field msgContainer Frame? # message-popup singleton (Core/Widgets.lua)
---@field promptDialog Frame? # prompt-dialog singleton (Core/Widgets.lua)
---@field activePrompt Frame? # currently-open prompt; nil when closed
local KE = {}

-- ─── Print / chat ─────────────────────────────────────────
---@param ... any
function KE:Print(...) end

--- Recommend disabling a redundant external addon when a KE module runs alongside it.
---@param addon string       addon folder name to detect via C_AddOns.IsAddOnLoaded
---@param label string       display name shown to the user
---@param moduleName string  the KE module's display name
---@param slash string       slash hint to toggle the KE module off
---@param state table        table holding the once-flag (caller's db)
---@param key string         once-flag field on `state`
function KE:WarnRedundantAddon(addon, label, moduleName, slash, state, key) end

-- ─── Color resolution ─────────────────────────────────────
--- Read a saved color table (which may be sparse) and fall back per-index.
---@param saved number[]?
---@param default number[]
---@return number r
---@return number g
---@return number b
---@return number a
function KE:ResolveColor(saved, default) end

---@param mode string?
---@param color number[]?
---@return number r
---@return number g
---@return number b
---@return number a
function KE:GetAccentColor(mode, color) end

---@param text string
---@return string
function KE:ColorTextByTheme(text) end

-- ─── Font helpers ─────────────────────────────────────────
---@param name string
---@return string
function KE:GetFontPath(name) end

---@param outline string?
---@return string
function KE:GetFontOutline(outline) end

---@param fontPath string
---@return boolean
function KE:IsFontValid(fontPath) end

---@param fontStr FontString
---@param name string
---@param size number
---@param outline string?
---@return boolean
function KE:ApplyFont(fontStr, name, size, outline) end

---@param fontStr FontString
---@param face string
---@param size number
---@param outline string?
---@param shadowConfig table?
function KE:ApplyFontToText(fontStr, face, size, outline, shadowConfig) end

---@param fontStr FontString
---@param options table?
function KE:CreateSoftOutline(fontStr, options) end

function KE:ValidateProfileFonts() end

function KE:FillProfileDefaults() end

-- ─── Frame / position helpers ────────────────────────────
---@param frame Frame
---@param pos table
---@param db table?
function KE:ApplyFramePosition(frame, pos, db) end

---@param frame Frame
---@param pos table
---@param db table?
function KE:ApplyFramePositionWithSnap(frame, pos, db) end

---@param frame Frame
---@param config table?
function KE:ApplyBackdrop(frame, config) end

---@param tex Texture
---@param zoom number?
function KE:ApplyIconZoom(tex, zoom) end

---@param frame Frame
---@param color number[]?
function KE:AddIconBorders(frame, color) end

---@param frame Frame
---@param color number[]?
function KE:AddBorders(frame, color) end

---@param anchorFrameType string?
---@param parentFrame string?
---@return Frame?
function KE:ResolveAnchorFrame(anchorFrameType, parentFrame) end

---@param anchorFrom string
---@return string
function KE:GetTextPointFromAnchor(anchorFrom) end

---@param anchorFrom string
---@return string
function KE:GetTextJustifyFromAnchor(anchorFrom) end

-- ─── GUI helpers ─────────────────────────────────────────
-- Accepts both FontStrings and EditBoxes — both expose SetFont. The
-- callers in Core/Widgets.lua use it on EditBoxes (the search/import
-- inputs) where the underlying type is `EditBox & BackdropTemplate`.
---@param fontStr FontString|EditBox
---@param size string  -- "small" | "normal" | "large"
function KE:ApplyThemeFont(fontStr, size) end

-- Matches the real signature in Core/Widgets.lua. Most params are optional;
-- the common usage shape is
--   KE:CreatePrompt(title, text, false, nil, false, nil, nil, nil, nil,
--                   onAccept, onCancel, "Accept", "Cancel")
---@param title string
---@param text string
---@param showEditBox boolean?
---@param editBoxLabelText string?
---@param useTexture boolean?
---@param texturePath string?
---@param textureSizeX number?
---@param textureSizeY number?
---@param textureColor number[]?
---@param onAccept function?
---@param onCancel function?
---@param acceptText string?
---@param cancelText string?
---@param showSecondEditBox boolean?
---@param secondEditBoxLabel string?
function KE:CreatePrompt(title, text, showEditBox, editBoxLabelText, useTexture, texturePath, textureSizeX,
                              textureSizeY, textureColor, onAccept, onCancel, acceptText, cancelText,
                              showSecondEditBox, secondEditBoxLabel) end

function KE:SkinningReloadPrompt() end

-- ─── KitnEssentials AceAddon globals ──────────────────────
---@class KitnEssentials
---@field db AceDB
KitnEssentials = {}

---@param name string
---@param ... string
---@return AceModule
function KitnEssentials:NewModule(name, ...) end

---@param name string
---@param silent boolean?
---@return AceModule?
function KitnEssentials:GetModule(name, silent) end

---@param name string
function KitnEssentials:EnableModule(name) end

---@param name string
function KitnEssentials:DisableModule(name) end

-- AceModule shape (what every KE:NewModule() returns).
-- Module-specific methods (function MOD:UpdateTicks() etc.) are not
-- declared here; `undefined-field` is disabled in .wowluarc.json so the
-- per-module method explosion doesn't flood the Problems panel.
---@class AceModule
---@field db table
---@field name string
local AceModule

---@return boolean
function AceModule:IsEnabled() end

---@param state boolean
function AceModule:SetEnabledState(state) end

--- Ace3 RegisterEvent: handler may be a string (method name on self),
--- a function, or omitted (Ace looks for self[event] as the handler).
---@param event string
---@param handler? string|function
function AceModule:RegisterEvent(event, handler) end

function AceModule:UnregisterAllEvents() end

-- AceHook-3.0 supports two argument shapes:
--   self:Hook(funcName, handler?)         — hooks _G[funcName]
--   self:Hook(object, method, handler?)   — hooks object[method]
-- Same for SecureHook / RawHook / HookScript / SecureHookScript.
-- The wowlua-ls built-in Ace3 stub only exposes the 3-arg object form,
-- so we add the 1-arg-string overload here so call sites like
-- `self:SecureHook("TalkingHead_LoadUI", fn)` don't flag.
---@overload fun(self: AceModule, functionName: string, handler: function|string?)
---@param object table
---@param method string
---@param handler function|string?
function AceModule:SecureHook(object, method, handler) end

---@overload fun(self: AceModule, functionName: string, handler: function|string?)
---@param object table
---@param method string
---@param handler function|string?
function AceModule:Hook(object, method, handler) end

---@overload fun(self: AceModule, functionName: string, handler: function|string?)
---@param object table
---@param method string
---@param handler function|string?
function AceModule:RawHook(object, method, handler) end

---@param msg string
function AceModule:Hide(msg) end
