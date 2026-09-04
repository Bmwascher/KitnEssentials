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

--- Shared combat clock/liveness machine (Core/CombatState.lua). KE.CombatState
--- is the live singleton, built at file load; New(deps) is exposed for specs.
---@class KE.CombatState
local KE_CombatState = {}

---@param deps table
---@return KE.CombatState
function KE_CombatState.New(deps) end

---@return boolean
function KE_CombatState:IsLive() end

---@return boolean
function KE_CombatState:IsFrozen() end

---@return number? seconds
function KE_CombatState:GetDuration() end

---@return boolean
function KE_CombatState:PlayerJoined() end

---@return boolean
function KE_CombatState:GroupInCombat() end

---@return number
function KE_CombatState:Generation() end

---@param key string
---@param wanted boolean
function KE_CombatState:SetFineCadence(key, wanted) end

---@param key string
---@param callbacks { OnStart: fun()?, OnStop: fun(reason: string)?, OnGroupClear: fun()?, OnClockTick: fun(seconds: number?, frac: number)? }
function KE_CombatState:RegisterListener(key, callbacks) end

---@param key string
function KE_CombatState:UnregisterListener(key) end

function KE_CombatState:OnRegenDisabled() end
function KE_CombatState:OnRegenEnabled() end
function KE_CombatState:OnEncounterStart() end
---@param success any
function KE_CombatState:OnEncounterEnd(success) end
---@param unit string?
function KE_CombatState:OnUnitFlags(unit) end
function KE_CombatState:OnPvPMatchComplete() end
function KE_CombatState:OnEnteringWorld() end

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
---@field CombatState KE.CombatState
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

--- All interrupt spell IDs represented by Core/Interrupts.lua, shared by
--- announce consumers. Callers treat the returned table as read-only.
---@return table<number, true>
function KE:GetInterruptAnnounceSpellSet() end

--- Row matcher for searchable dropdowns (Core/Globals.lua). True when
--- `query` matches `displayText` as a case-insensitive plain substring,
--- with inline |T...|t texture tags stripped first; falls back to `key`
--- when `displayText` is nil. A nil or empty query always matches.
---@param displayText string|nil
---@param key string|number|nil
---@param query string|number|nil
---@return boolean
function KE.DropdownSearchMatches(displayText, key, query) end

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

--- The list key every font dropdown offers as its first entry. Never stored.
KE.FONT_FOLLOW_GLOBAL = "*global*"

--- Adds the follow-the-global entry to an LSM font list and returns the list.
--- Handles both the hash and the ordered-array list shapes. effectiveName
--- overrides the label's font name where the pick inherits from a module face
--- rather than the profile-wide one.
---@param fontList table?
---@param effectiveName string?
---@return table
function KE:AddFollowGlobalFont(fontList, effectiveName) end

--- What a dropdown pick should store: nil for the follow-the-global sentinel,
--- the key itself otherwise.
---@param key string?
---@return string?
function KE:StoredFontFace(key) end

---@param fontPath string
---@return boolean
function KE:IsFontValid(fontPath) end

--- Any object carrying SetFont, not just a FontString: EditBox and SimpleHTML
--- both reach here, and SimpleHTML's textType-first signature is branched on
--- inside. A nil name means "no per-module choice" and resolves to the global
--- font (KE:GetFontPath).
---@param fontStr FontString|EditBox|SimpleHTML
---@param name string?
---@param size number
---@param outline string?
---@return boolean
function KE:ApplyFont(fontStr, name, size, outline) end

--- Narrower than KE:ApplyFont on purpose: the shadow calls below the font
--- application are unverified on a SimpleHTML frame, and nothing passes one.
---@param fontStr FontString|EditBox
---@param face string?
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

--- Rewrites the pre-opt-in "module left enabled" absence as an explicit true.
--- Reads the raw saved variables, so it MUST run before AceDB:New.
function KE:MigrateModuleEnableDefaults() end

--- Renames the Combat Logger's two retired profile keys and clears the old
--- ones. Reads the raw saved variables, so it MUST run before AceDB:New.
function KE:MigrateCombatLoggerKeys() end

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

---@param frame Frame
---@return boolean
function KE:CanReanchorNow(frame) end

--- For modules that resolve the anchor and place the frame themselves; `fn` is
--- that module's own reposition function (Core/Globals.lua anchor repair).
---@param frame Frame
---@param isPlayerFrame fun(): boolean # is this frame's CURRENT anchor type PLAYERFRAME
---@param fn fun() # replays the module's own placement
function KE:RegisterAnchorRepair(frame, isPlayerFrame, fn) end

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

-- ─── Edit-mode overlay geometry (Core/Globals.lua) ───────
--- Four SIGNED edge insets for an icon grid pinned to one corner of its own
--- container and growing away from it. The pair on each axis cancels, so the
--- box slides with the grid rather than growing to the union of the two.
---@param cols number?
---@param rows number?
---@param size number?
---@param spacing number?
---@param pin string?
---@param growLeft boolean
---@param growUp boolean
---@return number left, number right, number top, number bottom
function KE:GetGridOverlayInset(cols, rows, size, spacing, pin, growLeft, growUp) end

--- How far a fixed-size decoration hung outside one edge of a host reaches
--- past that edge, and past each of the two perpendicular edges. Both
--- non-negative; the caller decides which edges they land on.
---@param size number?
---@param gap number?
---@param hostSize number?
---@return number outward, number cross
function KE:GetSideDecorationInset(size, gap, hostSize) end

--- One snap decision shared by the live drag and the commit, so the two can
--- only ever agree. Pure: the caller supplies the grid in `context`.
---@param x number desired centre, absolute UIParent coordinates
---@param y number
---@param context table? { enabled, spacing, originX, originY, candidatesX,
---       candidatesY, edgeLeft, edgeCentreX, edgeRight, edgeBottom,
---       edgeCentreY, edgeTop }
---@param suppressed boolean? true while the suppress modifier is held
---@return number snappedX
---@return number snappedY
---@return boolean onCentreX true only when the result is the origin itself
---@return boolean onCentreY
---@return number? guideX nil unless an element won this axis
---@return number? guideY
function KE:SnapCenter(x, y, context, suppressed) end

--- Resolves an arrow key and the modifier state into a nudge delta. nil for
--- any other key, so one call both recognises an arrow and resolves it.
---@param key string?
---@param ctrlDown boolean?
---@return number? deltaX
---@return number? deltaY
function KE:ArrowNudgeDelta(key, ctrlDown) end

--- Turns an absolute centre into the two offsets a SetPoint stores. Pure by
--- contract: calls no API, so the caller proves every number clean first.
---@param centerX number
---@param centerY number
---@param anchorFrom string
---@param anchorTo string
---@param frameWidth number
---@param frameHeight number
---@param parentLeft number
---@param parentBottom number
---@param parentWidth number
---@param parentHeight number
---@return number offsetX
---@return number offsetY
function KE:ResolveAnchorOffsets(centerX, centerY, anchorFrom, anchorTo,
                                frameWidth, frameHeight,
                                parentLeft, parentBottom, parentWidth, parentHeight) end

---@param centerX number
---@param centerY number
---@param anchorFrom string
---@param anchorTo string
---@param frameWidth number
---@param frameHeight number
---@param parentLeft number
---@param parentBottom number
---@param parentWidth number
---@param parentHeight number
---@return number offsetX
---@return number offsetY
---@return number representedX
---@return number representedY
function KE:ResolveRepresentablePlacement(centerX, centerY, anchorFrom, anchorTo,
                                frameWidth, frameHeight,
                                parentLeft, parentBottom, parentWidth, parentHeight) end

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

-- ─── Skinning (Modules/Skinning/Frames/LFG.lua) ──────────
--- Returns the selected role icon set: any key of KE.ROLE_ICON_ART, or
--- "blizzard" or "circle". Falls back to "modern" for anything else.
---@return string
function KE.Skins.GetRoleIconSet() end

--- Repaints the Group Finder search rows and role count strips with the
--- current set. Applicant role buttons keep Blizzard's art.
function KE.Skins.RefreshLFGRoleIcons() end

-- ─── Skinning (Modules/Skinning/ChatRoleIcons.lua) ───────
--- Builds the chat role icon escape strings for one set.
---@param set string
---@return table<string, string>
function KE.BuildChatRoleIconStrings(set) end

--- Cache keys for one group member's chat role icon: the bare name, and the
--- name qualified with a normalized realm. playerRealm substitutes for a
--- missing member realm. Callers must pass already-guarded plain values.
---@param name string?
---@param realm string?
---@param playerRealm string?
---@return string|nil bareKey
---@return string|nil qualifiedKey
function KE.ChatRoleIconKeys(name, realm, playerRealm) end

--- Accepts or refuses one chat member by identity readability.
---@param role any
---@param name any
---@param realm any
---@return string|nil name
---@return string|nil realm
function KE.AcceptChatMember(role, name, realm) end

-- ─── Skinning (Modules/Skinning/RoleIconSamples.lua) ───────
--- Builds one role icon set's dropdown label: three inline icons, no text.
---@param set string
---@return string
function KE.BuildRoleIconSample(set) end

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

-- Module lifecycle fields cleared back to nil on disable.
---@class CharacterPanel
---@field _decimalIlvlHooked boolean?

---@class MapScale
---@field _regenPending boolean?

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

-- ---------------------------------------------------------------------------
-- Backfilled public KE: methods, grouped by source file. The pre-commit hook
-- refuses a new `function KE:Name` whose name is absent from this file.
-- ---------------------------------------------------------------------------

-- Core/AddonTheme.lua
---@param key string
---@return any color # number[] for a color key, or the raw scalar/boolean ThemeDefaults value
function KE:GetThemeColor(key) end

function KE:RefreshTheme() end

---@param mode string
function KE:SetThemeMode(mode) end

---@param presetName string
function KE:SetThemePreset(presetName) end

---@param key string
---@param r number
---@param g number
---@param b number
---@param a number?
function KE:SetCustomColor(key, r, g, b, a) end

function KE:CopyPresetToCustom() end

function KE:ResetTheme() end

function KE:NotifyThemeChange() end

-- Core/Colors.lua
---@return number[]
function KE:GetPlayerClassColor() end

---@param classToken string?
---@return number[]
function KE:GetClassColor(classToken) end

---@param classToken string?
---@return string
function KE:GetClassColorHex(classToken) end

---@param text string
---@param classToken string?
---@return string
function KE:ColorTextByClass(text, classToken) end

---@param r number?
---@param g number?
---@param b number?
---@return string
function KE:RGBAToHex(r, g, b) end

---@return string
function KE:GetThemeColorHex() end

--- Accepts an {r,g,b,a} table, a hex string ("#RRGGBB"/"#RRGGBBAA"), or
--- 0-1 or 0-255 numeric components.
---@param r number|string|table
---@param g number?
---@param b number?
---@param a number?
---@return any color # CreateColor(...) ColorMixin
function KE:CreateColor(r, g, b, a) end

---@param Min number
---@param Max number
---@param ... any
---@return number r
---@return number g
---@return number b
function KE:ColorGradient(Min, Max, ...) end

---@param text string
---@param color number[]
---@return string
function KE:ColorText(text, color) end

-- Core/Conflicts.lua
--- Builds the ordered list of conflict prompts to raise.
---@param env table # { profile: table, isLoaded: fun(addonName: string, resolver: table?): boolean, shouldNotLoad: boolean? }
---@return table queue array of { module, label, dbPath, source, resolver }; never nil
function KE:BuildConflictQueue(env) end

---@param moduleName string
---@param env table?
---@return string|nil rival the rival addon's folder name
function KE:GetModuleConflict(moduleName, env) end

--- Rescans and raises any outstanding conflict prompts.
function KE:ScanAddonConflicts() end

-- Core/Defaults.lua
---@return table Defaults
function KE:GetDefaultDB() end

-- Core/Globals.lua
--- Returns the LSM font NAME a module is configured with, never a file path.
---@param moduleDB table?
---@return string? fontName
function KE:GetEffectiveFont(moduleDB) end

---@return boolean?
function KE:IsEditModeActive() end

function KE:Init() end

---@param anchor string?
---@return string
function KE:GetPointFromAnchor(anchor) end

---@param itemId string?
---@return string? sectionId
function KE:GetSectionForItem(itemId) end

---@param value any
---@return number
function KE:RoundOffset(value) end

---@param point string?
---@return number x, number y
function KE:GetAnchorFractions(point) end

---@param hostPoint string?
---@param elementPoint string?
---@param xOffset number?
---@param yOffset number?
---@param elementW number?
---@param elementH number?
---@param hostW number?
---@param hostH number?
---@return number left, number right, number top, number bottom
function KE:GetTextOverlayInset(hostPoint, elementPoint, xOffset, yOffset,
                                elementW, elementH, hostW, hostH) end

---@param grid number[] four numbers, left/right/top/bottom
---@param elements number[][] zero or more of the same shape
---@return number left, number right, number top, number bottom
function KE:CombineOverlayInsets(grid, elements) end

---@param fontString FontString?
---@return string?
function KE:FontKey(fontString) end

---@param cache table?
---@param role string?
---@param fontKey string?
---@param width number?
---@param height number?
function KE:CommitTextExtent(cache, role, fontKey, width, height) end

---@param fs FontString?
---@return number?, number?
function KE:MeasureFontString(fs) end

---@param unit string? "player" selects the character sheet; anything else, inspect
---@return boolean
function KE:EUISheetActive(unit) end

---@param unit string? "player" selects the character sheet; anything else, inspect
---@param element string # "ilvl" | "enchant" | "gems" | "track" | "missingEnchant" | "headerText" | "avgIlvl" | "socketPanel"
---@return boolean
function KE:EUIDrawsSlotElement(unit, element) end

---@return boolean
function KE:IsPlayerHealerSpec() end

--- forceContext (optional): "HEALER" / "DEFAULT" overrides the live spec-driven
--- resolution; nil resolves live (UseHealerPosition + current spec).
---@param db table
---@param forceContext string?
---@return table posConfig
---@return string? anchorFrameType
---@return string? parentFrame
---@return string? strata
function KE:GetActivePositionConfig(db, forceContext) end

---@param frame Frame
---@param db table
---@param setParent boolean?
function KE:ApplyActivePosition(frame, db, setParent) end

-- Core/Interrupts.lua
--- Ordered list of { id, cd } entries to try in priority order, or nil when
--- the spec is unknown or has no kick.
---@param specID number
---@return { id: number, cd: number }[]?
function KE:GetInterruptCandidatesForSpec(specID) end

--- Union of all candidate IDs + announce extras for one spec, or nil when unknown.
---@param specID number
---@return table<number, true>?
function KE:GetInterruptSpellSet(specID) end

-- Core/Main.lua
function KE:SetupMinimapIcon() end

-- Core/Nicknames.lua
---@param unit string Unit token (e.g., "player", "party2")
---@return string name Nickname from either source, else raw UnitName
function KE:GetNicknameOrName(unit) end

---@param subject string Unit token, "Name" or "Name-Realm"
---@return string|nil nickname Plain nickname from the external provider, or nil
function KE:GetNSRTNickname(subject) end

---@param own string|nil Nickname from KE's own store
---@param foreign string|nil Nickname from the external provider
---@param realName string|nil Plain name the provider was asked about
---@return string|nil nickname Resolved nickname, or nil when neither applies
function KE:ResolveNicknamePrecedence(own, foreign, realName) end

---@return string|nil encoded
---@return string|nil error
---@return number|nil count
function KE:ExportNicknames() end

---@param importString string
---@param replaceAll boolean|nil wipe local entries before applying the import
---@return boolean success
---@return string message
function KE:ImportNicknames(importString, replaceAll) end

---@return number cleared
function KE:ClearAllNicknames() end

function KE:RefreshNicknameTags() end

-- Core/PixelPerfect.lua
function KE:UpdatePixelCache() end

--- Ideal UI scale (768 / physH). Used for scrollbar step clamping.
---@return number
function KE:GetPixelScale() end

--- Snaps to the nearest even pixel multiple.
---@param value number?
---@return number
function KE:PixelSnapEven(value) end

--- Floors to a half-pixel boundary.
---@param value number?
---@return number
function KE:PixelHalfFloor(value) end

---@param value number?
---@param dim number?
---@return number?
function KE:PixelSnapCenter(value, dim) end

---@param obj Frame
---@param anchor string
---@param p1 Frame|number?
---@param p2 string|number?
---@param p3 number?
---@param p4 number?
function KE:PixelPoint(obj, anchor, p1, p2, p3, p4) end

---@param frame Frame
---@param w number
---@param h number?
function KE:PixelSize(frame, w, h) end

---@param frame Frame
---@param w number
function KE:PixelWidth(frame, w) end

---@param frame Frame
---@param h number
function KE:PixelHeight(frame, h) end

---@param obj Frame
---@param anchor Frame?
---@param xOff number?
---@param yOff number?
function KE:PixelInside(obj, anchor, xOff, yOff) end

---@param obj Frame
---@param anchor Frame?
---@param xOff number?
---@param yOff number?
function KE:PixelOutside(obj, anchor, xOff, yOff) end

--- Backwards-compat alias for PixelSnap.
---@param value number?
---@return number
function KE:PixelRound(value) end

---@return number
function KE:PixelBestSize() end

---@param tex Texture
function KE:DisableTextureSnap(tex) end

function KE:ResnapAllBorders() end

-- Core/Secret.lua
---@param value any
---@return boolean
function KE:IsSecretValue(value) end

---@param value any
---@return boolean
function KE:NotSecretValue(value) end

---@param value any
---@return boolean
function KE:IsSafeValue(value) end

---@param object any
---@return boolean
function KE:IsSecretTable(object) end

---@param object any
---@return boolean
function KE:NotSecretTable(object) end

---@param value any
---@return boolean
function KE:CanAccessValue(value) end

---@param value any
---@return boolean
function KE:CanNotAccessValue(value) end

---@param object any
---@return boolean?
function KE:HasSecretValues(object) end

---@param object any
---@return boolean
function KE:NoSecretValues(object) end

---@param body any text to wrap, secret or not
---@param prefix string|nil
---@param suffix string|nil
---@return any|nil joined
function KE:WrapSecretText(body, prefix, suffix) end

---@return boolean
function KE:AreAuraIdentitiesHidden() end

--- The identifier is whatever the guarded query passes: id, name, name with
--- subtext, or link.
---@param spellIdentifier any
---@return boolean
function KE:IsAuraHiddenForSpell(spellIdentifier) end

---@param unit any
---@param updateInfo table?
---@return boolean
function KE:IsUnreadableAuraPayload(unit, updateInfo) end

---@param unit string
---@return string?
function KE:GetSafeUnitName(unit) end

---@param unit string
---@return string?
function KE:GetSafeUnitGUID(unit) end

---@param fontString FontString
---@return string?
function KE:GetSafeText(fontString) end

--- 0 = none, 1 = partial, 2 = full.
---@return number
function KE:GetRestrictionState() end

---@return boolean
function KE:IsFullyRestricted() end

---@return boolean
function KE:IsRestricted() end

---@return boolean
function KE:CanMakeProtectedCalls() end

--- targetState: 0 = run when fully clear, 1 = run when partial or clear.
---@param targetState number
---@param callback fun()?
function KE:DeferUntilUnrestricted(targetState, callback) end

-- Core/TextureSnap.lua
---@param obj Frame|Texture?
function KE:DisablePixelSnap(obj) end

-- Core/Widgets.lua
---@param timer number
---@param text string
---@param fontSize number
---@param parentFrame Frame?
---@param xOffset number?
---@param yOffset number?
---@return Frame?
function KE:CreateMessagePopup(timer, text, fontSize, parentFrame, xOffset, yOffset) end

---@param frame Frame
---@param targetAlpha number
---@param duration number
function KE:CombatSafeFade(frame, targetAlpha, duration) end

-- Modules/QoL/SlashCommands.lua
---@return boolean
function KE:HasAuraAddon() end

function KE:ApplySlashCommands() end
