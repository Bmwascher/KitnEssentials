---@meta
-- ╔══════════════════════════════════════════════════════════╗
-- ║  Annotations/KE.lua — type-only definitions              ║
-- ║                                                          ║
-- ║  Loaded by wowlua-ls for editor autocomplete + nil-      ║
-- ║  checking. NOT loaded by WoW (not listed in any .xml     ║
-- ║  manifest). NOT shipped (stripped from the zip by        ║
-- ║  .pkgmeta's '- dev' entry; the folder IS tracked in git).║
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
---@field IsLongCast LuaCurveObject

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

--- One curated dungeon entry (Modules/DungeonTimers/DungeonRegistry.lua).
---@class KE.DungeonTimerEntry
---@field key string
---@field name string
---@field iconID number
---@field instanceID number
---@field season number

---@class KE
---@field db AceDB
---@field FONT string
---@field LSM table
---@field Theme KETheme
---@field GUIFrame table
---@field EditMode table
---@field ProfileManager table
---@field GUI table
---@field FramePool KE.FramePool
---@field curves KE.Curves
---@field Skins table # Modules/Skinning/*.lua shared namespace (KE.Skins)
---@field msgContainer Frame? # message-popup singleton (Core/Widgets.lua)
---@field promptDialog Frame? # prompt-dialog singleton (Core/Widgets.lua)
---@field activePrompt Frame? # currently-open prompt; nil when closed
---@field PlayerAbsorbsFormat { Format: fun(amount:any, abbreviate:boolean, hideWhenZero:boolean):string }
---@field DungeonTimerDungeons KE.DungeonTimerEntry[] # Modules/DungeonTimers/DungeonRegistry.lua
local KE = {}

-- ─── Print / chat ─────────────────────────────────────────
--- Real def (Core/Globals.lua) takes ONE arg and concatenates it into
--- the "Kitn|rEssentials:" prefix string — NOT varargs. Extra args at a
--- call site are silently ignored (a real, documented KE:Print bug).
---@param msg string|number
function KE:Print(msg) end

--- Run fn now, or defer it to the next PLAYER_REGEN_ENABLED when in combat
--- lockdown. Queued closures run once, FIFO, each wrapped in
--- xpcall(fn, geterrorhandler()) so one erroring closure can't drop the rest
--- of the queue. Secure-frame mutations (state drivers, secure attributes,
--- Show/Hide on protected frames) route through this instead of executing
--- blocked mid-combat.
---@param fn fun()
function KE:RunAfterCombat(fn) end

--- Recommend disabling a redundant external addon when a KE module runs alongside it.
---@param addon string       addon folder name to detect via C_AddOns.IsAddOnLoaded
---@param label string       display name shown to the user
---@param moduleName string  the KE module's display name
---@param slash string       slash hint to toggle the KE module off
---@param state table        table holding the once-flag (caller's db)
---@param key string         once-flag field on `state`
function KE:WarnRedundantAddon(addon, label, moduleName, slash, state, key) end

-- ─── Module utilities ─────────────────────────────────────
--- True when ElvUI is loaded AND the user has opted into ElvUI handling
--- this area (db.profile.UseElvUI.Enabled) — module init checks this to
--- skip loading its own skinning/handling in favor of ElvUI's.
---@return boolean?
function KE:ShouldNotLoadModule() end

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

---@param db table
---@param entry table
---@return number r, number g, number b, number a
function KE:ReadCardColor(db, entry) end

---@param db table
---@param entry table
---@param r number
---@param g number
---@param b number
---@param a number
function KE:WriteCardColor(db, entry, r, g, b, a) end

-- ─── Slash commands ───────────────────────────────────────
---@return boolean
function KE:IsWAEnabled() end

---@param enabled boolean
---@return boolean newState
function KE:SetWAEnabled(enabled) end

---@param arg string?  "on", "off", or anything else to report the state
function KE:HandleWACommand(arg) end

-- ─── Font helpers ─────────────────────────────────────────
---@param name string?
---@return string
function KE:GetFontPath(name) end

---@param barName string?
---@return string
function KE:GetStatusbarPath(barName) end

---@param outline string?
---@return string
function KE:GetFontOutline(outline) end

--- Single source of truth for the font-outline dropdown option list used by
--- every GUI font card (Core/Globals.lua). `flags.includeMono` adds
--- MONOCHROME, omitted from the base set since it is not universally
--- appropriate.
---@param flags { includeMono: boolean? }?
---@return { key: string, text: string }[]
function KE:GetFontOutlineOptions(flags) end

--- Adds or strips the SLUG glyph-renderer flag per the profile-wide toggle.
--- Outlined text above a size ceiling is left unslugged.
---@param flags string?
---@param size number?
---@return string?
function KE:SlugFlags(flags, size) end

--- Maps retired outline keys to their surviving equivalent for display.
---@param value string?
---@return string
function KE:NormalizeFontOutline(value) end

--- The profile-wide font, resolved by KE:GetFontPath when a module has none.
---@return string
function KE:GetGlobalFont() end

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

--- Preset/alias colour for arbitrary display text, or nil when nothing matches
--- (defined in DungeonTimers.lua; shared with the Dungeon Trash resolvers).
---@param text string?
---@return number[]? color
function KE.ResolveTrashPresetColor(text) end

--- Split text-mode layout shared by the boss text timers and the Dungeon Trash
--- alerts (defined in DungeonTimers.lua): label is the static pivot, icon off
--- its LEFT, timer off its RIGHT; 2px icon gap / 5px timer gap.
---@param anchor Frame
---@param label FontString
---@param timerText FontString
---@param iconFrame Frame?
---@param showIcon boolean?
---@param align string?
function KE.ApplySplitTextLayout(anchor, label, timerText, iconFrame, showIcon, align) end

function KE:ValidateProfileFonts() end

function KE:FillProfileDefaults() end

-- ─── Dungeon Timers registry (Modules/DungeonTimers/DungeonRegistry.lua) ─
--- Distinct seasons present in `registry`, ascending.
---@param registry KE.DungeonTimerEntry[]
---@return number[]
function KE.GetDungeonTimerSeasons(registry) end

--- Registry entries for one season, in registry order.
---@param registry KE.DungeonTimerEntry[]
---@param season number
---@return KE.DungeonTimerEntry[]
function KE.GetDungeonTimerDungeonsForSeason(registry, season) end

--- Initial Dungeons-tab selection: the instance the player is standing in
--- wins, then the saved selection (validated — a stale key falls through),
--- then the newest season's first dungeon.
---@param registry KE.DungeonTimerEntry[]
---@param instanceID number?
---@param saved { season: number?, dungeon: string? }?
---@return number? season
---@return string? dungeonKey
function KE.ResolveDungeonTimerSelection(registry, instanceID, saved) end

-- ─── Frame / position helpers ────────────────────────────
--- Real signature (Core/Globals.lua). `Config` is REQUIRED — its
--- anchorFrameType/ParentFrame fields are indexed unconditionally (via
--- ResolveAnchorFrame) even though the fields themselves are optional.
--- `SetParent` is an optional boolean; truthy reparents `frame` to the
--- resolved anchor frame before positioning. Also snaps the frame to the
--- pixel grid at the end (KE:SnapFrameToPixels).
---@param frame Frame
---@param posConfig { AnchorFrom: string?, AnchorTo: string?, XOffset: number?, YOffset: number? }
---@param Config { anchorFrameType: string?, ParentFrame: string?, Strata: string? }
---@param SetParent boolean?
function KE:ApplyFramePosition(frame, posConfig, Config, SetParent) end

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
---@param borderParent Frame? # frame level control; defaults to `frame` (Core/Widgets.lua)
function KE:AddBorders(frame, color, borderParent) end

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

-- ─── Pixel-perfect helpers (Core/PixelPerfect.lua) ───────
--- Live size of 1 screen pixel in addon coords: 768 / (physH * effScale).
--- Use to snap sizes/offsets/borders onto the actual screen pixel grid.
---@return number
function KE:GetPixelSize() end

--- Symmetric rounding around zero: snaps `value` to the nearest pixel
--- multiple using the cached pixel size from KE:GetPixelSize.
---@param value number?
---@return number
function KE:PixelSnap(value) end

--- Snaps `frame`'s current position to the integer screen-pixel grid by
--- nudging its stored SetPoint offset. Called automatically by
--- KE:ApplyFramePosition; also exposed for direct per-frame use.
---@param frame Frame?
function KE:SnapFrameToPixels(frame) end

-- ─── GUI helpers ─────────────────────────────────────────
-- Accepts both FontStrings and EditBoxes — both expose SetFont. The
-- callers in Core/Widgets.lua use it on EditBoxes (the search/import
-- inputs) where the underlying type is `EditBox & BackdropTemplate`.
---@param fontStr FontString|EditBox
---@param size string|number  -- "small" | "normal" | "large", or a point size
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

--- Wraps KE:CreatePrompt with the standard reload-required chrome
--- (Core/Widgets.lua). Returns the singleton prompt dialog frame.
---@param reason string?
---@return Frame
function KE:CreateReloadPrompt(reason) end

function KE:SkinningReloadPrompt() end

--- Marks a reload as owed. Skinning toggles call this instead of prompting;
--- the GUI frame's OnHide raises one prompt for the whole session.
function KE:FlagReloadNeeded() end

--- Raises the deferred prompt if one is owed, and clears the flag.
---@return Frame?
function KE:FlushPendingReloadPrompt() end

-- ─── Nicknames (Core/Nicknames.lua) ──────────────────────
--- Store key ("Name-NormalizedRealm") from a raw name STRING ("Name" or
--- "Name-Realm"; the realm side is normalized defensively). Pure string
--- helper; nil when either side is unresolvable.
---@param rawName string?
---@param fallbackRealm string? # normalized realm for suffix-less names
---@return string?
function KE:BuildNicknameKey(rawName, fallbackRealm) end

-- ─── Skinning (Modules/Skinning/EUIWindows.lua) ──────────
--- Pure. Which of our skin keys EllesmereUI already covers.
---@param env { loaded: boolean, version: string?, getStyle: (fun(euiKey: string): string?)? }
---@return table set # [skinKey] = euiKey (unfiltered row) | resolved record
---                   { euiKey, addons, partialLabel, partialTooltip }
---                   (filtered row); never nil
function KE:BuildSkinSuppressionSet(env) end

--- Live. Reads the globals, resolves once, caches on KE.Skins.suppressed.
---@return table set # [skinKey] = euiKey | resolved record; never nil
function KE:ResolveSkinSuppression() end

--- Nothing outside Modules/Skinning/EUIWindows.lua may index
--- KE.Skins.suppressed directly -- these two accessors are the only
--- shape-safe reads of it.
--- Is THIS ONE registration suppressed? Returns the owning euiKey string
--- when it is, nil when it is not.
---@param key string # skin key (KE.Skins.skinIndex / skinStatus key)
---@param addon string? # the Blizzard addon this registration came from
---@return string? euiKey
function KE.Skins.GetSuppression(key, addon) end

--- How much of `key` does EllesmereUI own?
---@param key string
---@return string state # "none" | "full" | "partial"
---@return string? euiKey
---@return string? partialLabel
---@return string? partialTooltip
function KE.Skins.GetSuppressionState(key) end

-- ─── Skinning (Modules/Skinning/SkinAPI.lua) ──────────────
--- Mutates the palette in place, then repaints only cached backdrops still
--- wearing the old colour. Re-colours every skinned window with no reload.
---@param bg number[]?     {r,g,b,a} or nil to leave unchanged
---@param border number[]? {r,g,b,a} or nil to leave unchanged
function KE.Skins.SetSkinColors(bg, border) end

--- Re-applies every registered string with no reload.
---@param face string?    LibSharedMedia font name, "" for the addon's own font, nil to leave unchanged
---@param size number?    base size 8-20, nil to leave unchanged
---@param outline string? "NONE" | "OUTLINE" | "THICK", nil to leave unchanged
function KE.Skins.SetSkinFont(face, size, outline) end

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

--- RawHook additionally accepts a hookSecure boolean, either as a 3rd arg
--- after the object/method/handler form or, string-object shorthand, right
--- after the handler: `self:RawHook(functionName, handler, hookSecure)`.
---@overload fun(self: AceModule, functionName: string, handler: function|string?, hookSecure: boolean?)
---@param object table
---@param method string
---@param handler function|string?
---@param hookSecure boolean?
function AceModule:RawHook(object, method, handler, hookSecure) end

---@param msg string
function AceModule:Hide(msg) end

-- Automation's transform picker is a cross-module public surface (the GUI
-- reads it from a different file in Task 4), unlike the module-private
-- methods the AceModule note above says to skip. GetHideTransformItem is a
-- PLAIN FUNCTION field (dot call); SetHideTransformItem is a METHOD (colon
-- call) -- the GUI depends on that asymmetry.
---@class Automation: AceModule
---@field HideTransformsData { order: string[], labels: table<string, string>, items: table[] }
local Automation

---@param key string
---@return boolean
function Automation.GetHideTransformItem(key) end

---@param key string
---@param enabled boolean
function Automation:SetHideTransformItem(key, enabled) end
