-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-Core.lua                                            ║
-- ║  Purpose: Core GUI framework — frame creation,           ║
-- ║  show/hide, theme initialization.                        ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)

local GUIFrame = {}
KE.GUIFrame = GUIFrame

local type = type
local pcall = pcall
local pairs = pairs
local ipairs = ipairs
local tostring = tostring
local CreateFrame = CreateFrame
local table_insert = table.insert

local Theme = KE.Theme

---------------------------------------------------------------------------------
-- Frame Creation
---------------------------------------------------------------------------------

-- Content registration
GUIFrame.registeredContent = {}

function GUIFrame:RegisterContent(id, buildFunc)
    if type(buildFunc) ~= "function" then return end
    self.registeredContent[id] = buildFunc
end

function GUIFrame:HasContent(id)
    return self.registeredContent[id] ~= nil
end

-- Content cleanup callbacks (fire on REAL item switch only — used by modules
-- that need to tear down preview state, etc.)
GUIFrame.contentCleanupCallbacks = {}

function GUIFrame:RegisterContentCleanup(key, callback)
    if type(key) == "string" and type(callback) == "function" then
        self.contentCleanupCallbacks[key] = callback
    end
end

function GUIFrame:UnregisterContentCleanup(key)
    if key then self.contentCleanupCallbacks[key] = nil end
end

-- Content rebuild callbacks (fire UNCONDITIONALLY at the start of every
-- RefreshContent — used by widget pools to ReleaseAll before the new render
-- starts so kits can be re-acquired into the fresh scrollChild without
-- being orphaned by the teardown loop).
GUIFrame.contentRebuildCallbacks = {}

function GUIFrame:RegisterContentRebuildCallback(key, callback)
    if type(key) == "string" and type(callback) == "function" then
        self.contentRebuildCallbacks[key] = callback
    end
end

function GUIFrame:UnregisterContentRebuildCallback(key)
    if key then self.contentRebuildCallbacks[key] = nil end
end

-- Toggle callbacks wait out a short delay. A page rebuild inside that delay
-- runs them first, while the page they belong to is still whole, instead of
-- letting them reach widgets another page has since taken.
-- One entry per call, in the order scheduled; whichever of its timer or a
-- drain reaches an entry first runs it.
GUIFrame._deferred = {}

function GUIFrame:DeferWidgetCallback(delay, fn)
    local queue = self._deferred
    local entry = { fn = fn }
    queue[#queue + 1] = entry
    C_Timer.After(delay, function()
        if entry.done then return end
        entry.done = true
        for i = 1, #queue do
            if queue[i] == entry then
                table.remove(queue, i)
                break
            end
        end
        fn()
    end)
end

function GUIFrame:DrainDeferredWidgetCallbacks()
    local queue = self._deferred
    if #queue == 0 then return end
    self._drainingDeferred = true
    while #queue > 0 do
        local entry = table.remove(queue, 1)
        entry.done = true
        -- A failing callback must not leave the flag set: every later
        -- refresh would be swallowed.
        local ok, err = pcall(entry.fn)
        if not ok then geterrorhandler()(err) end
    end
    self._drainingDeferred = nil
end


-- Refresh a pool kit's theme-tied colors lazily — only on the first Configure
-- after KE:RefreshTheme bumped the theme version. Each kit caches the version
-- it was last refreshed at; mismatch triggers card-level + widget-level
-- ApplyThemeColors. Pools call this from their Configure path; non-pool
-- callers (which build cards from scratch each render) pick up the new
-- palette implicitly so they never need this helper.
function GUIFrame:RefreshKitThemeIfNeeded(kit, widgets)
    local v = (KE._themeVersion or 0)
    if kit._themeVersion == v then return end
    if kit.card and kit.card.ApplyThemeColors then
        kit.card:ApplyThemeColors()
    end
    -- widgets param overrides the kit-level convention; fall back to
    -- kit.themeWidgets which factories can set once.
    widgets = widgets or kit.themeWidgets
    if widgets then
        for _, w in ipairs(widgets) do
            if w and w.ApplyThemeColors then w:ApplyThemeColors() end
        end
    end
    kit._themeVersion = v
end

-- On-close callbacks
GUIFrame.onCloseCallbacks = {}

function GUIFrame:RegisterOnCloseCallback(key, callback)
    if type(key) == "string" and type(callback) == "function" then
        self.onCloseCallbacks[key] = callback
    end
end

function GUIFrame:FireOnCloseCallbacks()
    for _, callback in pairs(self.onCloseCallbacks) do
        pcall(callback)
    end
end

---------------------------------------------------------------------------------
-- Settings pages addon
---------------------------------------------------------------------------------

local PAGES_ADDON = "KitnEssentials_Options"
local PAGES_MISSING = "KitnEssentials Options is not installed. Reinstall KitnEssentials (both folders ship together)."
local PAGES_DISABLED = "KitnEssentials Options is disabled. Enable it in the AddOn list, then open settings again."
local PAGES_ENABLED = "KitnEssentials Options was disabled; enabled it to open settings."
local PAGES_MISMATCH = "KitnEssentials and KitnEssentials Options are different versions (%s / %s). Update or reinstall both."
local PAGES_FAILED = "Settings pages could not load (%s). Open settings again to retry, or reinstall KitnEssentials if it keeps failing."

-- Pure. The version is compared before the enable state, so a disabled copy
-- from another version is reported as a mismatch and never enabled; a version
-- the client did not return never counts as a match.
function GUIFrame.PagesLoadAction(state)
    if state.loaded then return "ready" end
    if state.loading then return "loading" end
    if not state.exists then return "missing" end
    if not state.coreVersion or state.coreVersion ~= state.pagesVersion then return "mismatch" end
    if not state.enabled then return "disabled" end
    return "load"
end

-- Nothing is latched, so the next open tries again.
function GUIFrame:PagesLoadFailed(message)
    if self.mainFrame and message ~= self._pagesLoadMessage then
        -- A not-loaded card on screen shows the old reason until rebuilt.
        self._contentDirtyWhileHidden = true
    end
    self._pagesLoadMessage = message
    KE:Print(message)
    return false, false
end

function GUIFrame:LoadPages()
    local loaded, reason = C_AddOns.LoadAddOn(PAGES_ADDON)
    if not loaded then
        local text = reason and _G["ADDON_" .. reason]
        if type(text) ~= "string" then
            text = reason or "unknown"
        end
        return self:PagesLoadFailed(PAGES_FAILED:format(text))
    end
    self._pagesLoaded = true
    return true, true, false, true
end

-- Pure. Whether another addon's enable state looks changed and not yet
-- saved: loaded but disabled, or enabled and loadable but not loaded. A
-- load-on-demand addon is not loaded until asked, so only its disable shows.
function GUIFrame.AddOnChangePending(name, enabled, loaded, loadOnDemand, loadable)
    if name == PAGES_ADDON then return false end
    if loaded then return not enabled end
    return enabled and not loadOnDemand and loadable == true
end

local function OtherAddOnChangesPending(character)
    for i = 1, C_AddOns.GetNumAddOns() do
        local name = C_AddOns.GetAddOnName(i)
        local enabled = C_AddOns.GetAddOnEnableState(i, character) > Enum.AddOnEnableState.None
        local _, loaded = C_AddOns.IsAddOnLoaded(i)
        local loadOnDemand = C_AddOns.IsAddOnLoadOnDemand(i)
        local loadable
        if enabled and not loaded and not loadOnDemand then
            loadable = C_AddOns.IsAddOnLoadable(i, character)
        end
        if GUIFrame.AddOnChangePending(name, enabled, loaded, loadOnDemand, loadable) then
            return true
        end
    end
    return false
end

-- Enabled for this character only; the message names the manual fix when
-- the load still fails.
function GUIFrame:LoadDisabledPages(character)
    -- An unsaved enable is lost at logout, but saving commits every staged
    -- change, so it is skipped while the AddOn List is open (its Okay or
    -- Cancel decides) or another change looks staged.
    local othersPending = OtherAddOnChangesPending(character)
    C_AddOns.EnableAddOn(PAGES_ADDON, character)
    local addonList = _G.AddonList
    if not othersPending and not (addonList and addonList:IsShown()) then
        C_AddOns.SaveAddOns()
    end
    if C_AddOns.LoadAddOn(PAGES_ADDON) then
        self._pagesLoaded = true
        KE:Print(PAGES_ENABLED)
        return true, true, false, true
    end
    return self:PagesLoadFailed(PAGES_DISABLED)
end

-- Returns ready, newlyReady, loading, compiled. newlyReady is true on the
-- first call that finds the pages usable, whoever loaded them; loading is
-- true only for a call made from inside the pages' own load; compiled is
-- true when this call ran the load.
function GUIFrame:EnsurePagesLoaded()
    if self._pagesLoaded then return true, false end
    -- The other reads need an addon name the client knows.
    local exists = C_AddOns.DoesAddOnExist(PAGES_ADDON)
    local state = { exists = exists }
    local character = KE:GetSafeUnitGUID("player")
    if exists then
        local loadedOrLoading, loaded = C_AddOns.IsAddOnLoaded(PAGES_ADDON)
        state.loaded = loaded
        state.loading = loadedOrLoading and not loaded
        state.coreVersion = C_AddOns.GetAddOnMetadata("KitnEssentials", "Version")
        state.pagesVersion = C_AddOns.GetAddOnMetadata(PAGES_ADDON, "Version")
        -- With no readable GUID the enable state cannot be read: the load is
        -- tried, and a disabled addon fails with the client's own reason.
        state.enabled = true
        if character then
            local enableState = C_AddOns.GetAddOnEnableState(PAGES_ADDON, character)
            state.enabled = enableState ~= nil and enableState > Enum.AddOnEnableState.None
        end
    end
    local action = GUIFrame.PagesLoadAction(state)
    if action == "ready" then
        self._pagesLoaded = true
        return true, true
    elseif action == "loading" then
        return false, false, true
    elseif action == "missing" then
        return self:PagesLoadFailed(PAGES_MISSING)
    elseif action == "mismatch" then
        return self:PagesLoadFailed(PAGES_MISMATCH:format(state.coreVersion or "unknown", state.pagesVersion or "unknown"))
    elseif action == "disabled" then
        return self:LoadDisabledPages(character)
    end
    return self:LoadPages()
end

-- The deferred Show, one frame after the pages loaded. The combat handler
-- takes a pending open when combat starts first, turning it into a reopen
-- after combat as it does for an open window.
function GUIFrame:FinishPendingOpen()
    if not self._openPending then return end
    self._openPending = nil
    if InCombatLockdown() then
        self.reopenAfterCombat = true
        return
    end
    self._continuingOpen = true
    self:Show()
end

---------------------------------------------------------------------------------
-- Show / Hide
---------------------------------------------------------------------------------

-- Toggle the GUI window
function GUIFrame:Toggle()
    -- The window can never be on screen during combat, so the only thing a
    -- toggle can flip is whether it will be open once combat ends.
    if InCombatLockdown() then
        if self.reopenAfterCombat then
            self.reopenAfterCombat = nil
            KE:Print("Options window will stay closed after combat.")
        else
            self.reopenAfterCombat = true
            KE:Print("Options will open after combat ends.")
        end
        return
    end
    if self.mainFrame and self.mainFrame:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

-- Check if GUI is currently shown
function GUIFrame:IsShown()
    return self.mainFrame and self.mainFrame:IsShown()
end

-- Show the GUI
function GUIFrame:Show()
    if InCombatLockdown() then
        KE:Print("Options will open after combat ends.")
        self.reopenAfterCombat = true
        return
    end
    if self._openPending then return end
    local continuing = self._continuingOpen
    self._continuingOpen = nil
    local _, newlyReady, loading, compiled = self:EnsurePagesLoaded()
    if (newlyReady or loading) and self.mainFrame then
        -- The page on screen may be the not-loaded card from an earlier
        -- failure; the replay further down rebuilds it.
        self._contentDirtyWhileHidden = true
    end
    -- Nothing builds or selects while the pages compile or in the call that
    -- compiled them; the window builds a frame later. A Show nested inside
    -- the load has already set _openPending. The continuation already runs a
    -- frame later, so pages it finds ready build at once.
    if loading or compiled or self._openPending or (newlyReady and not continuing) then
        if not self._openPending then
            self._openPending = true
            C_Timer.After(0, function() self:FinishPendingOpen() end)
        end
        return
    end
    if not self.mainFrame then
        self:CreateMainFrame()
    end
    self.mainFrame:Show()
    -- RefreshTheme repaints only a shown window, so an accent changed while
    -- this one was hidden reaches the header button here.
    if self.PaintEditModeButton then
        self.PaintEditModeButton()
    end
    KE.GUIOpen = true
    if KE.PreviewManager then
        KE.PreviewManager:SetGUIOpen(true)
    end
    -- Initialize sidebar and show default page on first open
    if not self.selectedSidebarItem then
        self:InitializeSidebarExpansion()
        self:RefreshSidebar()
        self:SelectSidebarItem("HomePage")
    else
        -- The expand-all setting describes how the window opens, so it is
        -- re-applied on every open; off leaves hand-collapsed sections alone.
        if KE.db and KE.db.profile and KE.db.profile.ExpandSidebarOnOpen then
            self:ApplySidebarExpansion()
            self:RefreshSidebar()
        end
        -- A waiting page link rebuilds the content below; replaying first
        -- would build a page nobody sees.
        if self._contentDirtyWhileHidden and not self._pendingPage then
            -- A refresh was requested while hidden (RefreshContent's hidden gate
            -- swallowed it) — replay it once so the reopened page isn't stale.
            self:RefreshContent()
        end
    end
    local page = self._pendingPage
    if page then
        self._pendingPage = nil
        self.pendingContext = page.context
        self:ShowPage(page.itemId, page.sectionId)
    end
end

-- Collapse the window to its title bar, so in-world elements stay reachable
-- without losing the page being worked on. Drag handlers live on the main
-- frame, which stays shown, so a collapsed window still moves. Saved height
-- lives on the table rather than the frame so a hide/show cycle cannot lose it.
--
-- The resize minimum has to drop with it: the next layout pass would otherwise
-- clamp the frame straight back up to the full minimum height.
function GUIFrame:ToggleMinimize()
    local frame = self.mainFrame
    if not frame then return end
    self.minimized = not self.minimized

    if self.minimized then
        self._savedHeight = frame:GetHeight()
        if self.contentArea then self.contentArea:Hide() end
        if self.sidebar then self.sidebar:Hide() end
        if self.bottomBar then self.bottomBar:Hide() end
        local collapsed = Theme.headerHeight + Theme.borderSize * 2
        frame:SetResizeBounds(self.minWidth, collapsed)
        frame:SetHeight(collapsed)
    else
        -- Height first, then the bound. Raising the minimum while the frame is
        -- still collapsed clamps it to that minimum and fires an extra size
        -- pass on the way back up.
        frame:SetHeight(self._savedHeight or self.minHeight)
        frame:SetResizeBounds(self.minWidth, self.minHeight)
        if self.contentArea then self.contentArea:Show() end
        if self.sidebar then self.sidebar:Show() end
        if self.bottomBar then self.bottomBar:Show() end

        -- RefreshContent refuses to rebuild while collapsed, so the page can be
        -- stale by the time it comes back — an edit-mode drag writes positions
        -- the sliders never saw.
        if self._contentDirtyWhileHidden then
            self:RefreshContent()
        end
    end

    if self.PaintMinimizeArrow then self:PaintMinimizeArrow() end
end

-- Hide the GUI
function GUIFrame:Hide()
    if self.mainFrame then
        self.mainFrame:Hide()
    end
    -- Clear search on close
    if self.searchEditBox then
        self.searchEditBox:SetText("")
        self.searchEditBox:ClearFocus()
    end
    self.searchFilter = ""
    -- Fire cleanup
    for _, callback in pairs(self.contentCleanupCallbacks) do
        pcall(callback)
    end
    self:FireOnCloseCallbacks()
    KE.GUIOpen = false
    if KE.PreviewManager then
        KE.PreviewManager:SetGUIOpen(false)
    end
end

---------------------------------------------------------------------------------
-- Theme
---------------------------------------------------------------------------------

-- Apply theme colors to all GUI elements
function GUIFrame:ApplyThemeColors()
    if not self.mainFrame then return end
    local T = Theme
    local frame = self.mainFrame

    -- Main frame
    frame:SetBackdropColor(T.bgDark[1], T.bgDark[2], T.bgDark[3], T.bgDark[4])
    frame:SetBackdropBorderColor(T.border[1], T.border[2], T.border[3], T.border[4])

    -- Sidebar
    if self.sidebar then
        self.sidebar:SetBackdropColor(T.bgDark[1], T.bgDark[2], T.bgDark[3], 0.40)
    end

    -- Content area
    if frame.content then
        frame.content:SetBackdropColor(0, 0, 0, 0)
    end

    -- Refresh sidebar visuals
    self:RefreshSidebar()

    -- Search bar
    if self.searchContainer then
        self.searchContainer:SetBackdropColor(T.fieldBg[1], T.fieldBg[2], T.fieldBg[3], T.fieldBg[4])
        self.searchContainer:SetBackdropBorderColor(T.fieldBorder[1], T.fieldBorder[2], T.fieldBorder[3], 1)
    end
    if self.searchEditBox then
        self.searchEditBox:SetTextColor(T.accent[1], T.accent[2], T.accent[3], 1)
    end

    if self.RefreshProfilerFooter then
        self:RefreshProfilerFooter()
    end

    -- Update title and version text with new accent color
    if self.titleText then
        self.titleText:SetText(KE:ColorTextByTheme("Kitn") .. "Essentials")
    end
    if self.versionText then
        self.versionText:SetText("|cff888888v" .. (KE.Version or "?") .. "|r")
    end
    if self.PaintEditModeButton then
        self.PaintEditModeButton()
    end

    -- Rebuild current content to pick up new accent colors
    if self.selectedSidebarItem then
        self:RefreshContent()
    end

    -- The theme popup sits outside the content tree and is never rebuilt by
    -- RefreshContent above, so it needs its own resync here.
    if self.RefreshThemePopup then
        self:RefreshThemePopup()
    end
end

---------------------------------------------------------------------------------
-- Widget Pools
---------------------------------------------------------------------------------
-- WoW never frees a frame, so a page rebuild that orphans its cards leaks
-- them for the session. Cards, rows and widgets made under the live page come
-- from these pools and go back when the page is torn down. An object that
-- something else has added a frame or region to is retired, orphaned rather
-- than reused, because those additions cannot be taken off again.
local DEBUG_GUIPOOL = false

GUIFrame._pools = {}
GUIFrame._poolStats = { retired = 0, failed = 0, retiredByPage = {} }

-- base and measured hold two numbers per owned frame: its child count, then
-- its region count.
function GUIFrame.PoolIsClean(base, measured, busy)
    if busy then return false end
    for i = 1, #base do
        if base[i] ~= measured[i] then return false end
    end
    return true
end

-- Deletes every key added since construction and puts back every method that
-- was replaced or removed. Keys starting with _ke belong to the pool and stay.
function GUIFrame.PoolSweepKeys(obj, snapshot)
    for k in pairs(obj) do
        if snapshot[k] == nil and not (type(k) == "string" and string.sub(k, 1, 3) == "_ke") then
            obj[k] = nil
        end
    end
    for k, v in pairs(snapshot) do
        if type(v) == "function" and obj[k] ~= v then
            obj[k] = v
        end
    end
end

local WidgetPool = {}
WidgetPool.__index = WidgetPool

-- Shared by every release, so checking an object allocates nothing.
local measured = {}

local function Snapshot(obj)
    local snapshot = {}
    for k, v in pairs(obj) do
        snapshot[k] = type(v) == "function" and v or true
    end
    return snapshot
end

local function RecordBaseline(obj)
    local base = {}
    for i, frame in ipairs(obj._keOwned) do
        base[i * 2 - 1] = frame:GetNumChildren()
        base[i * 2] = frame:GetNumRegions()
    end
    obj._keBase = base
end

-- Everything a release does to the object, run under one pcall by Release.
-- Returns true once the object is parked on the holder, false when the guard
-- refuses it.
local function ReleaseSteps(pool, obj)
    -- Hidden first, so whatever the hide sets off (focus loss, a list
    -- closing) still runs against the old binding.
    obj:Hide()
    pool.reset(obj)
    local owned = obj._keOwned
    for i = 1, #owned do
        measured[i * 2 - 1] = owned[i]:GetNumChildren()
        measured[i * 2] = owned[i]:GetNumRegions()
    end
    local busy = obj._keIsBusy ~= nil and obj:_keIsBusy()
    if not GUIFrame.PoolIsClean(obj._keBase, measured, busy) then return false end
    GUIFrame.PoolSweepKeys(obj, obj._keSnapshot)
    obj:ClearAllPoints()
    obj:SetParent(pool:GetHolder())
    return true
end

function WidgetPool:GetHolder()
    local holder = self.holder
    if not holder then
        holder = CreateFrame("Frame", nil, UIParent)
        holder:Hide()
        self.holder = holder
    end
    return holder
end

function WidgetPool:Acquire(parent)
    local free = self.free
    local obj = free[#free]
    if obj then
        free[#free] = nil
    else
        obj = self.construct(self:GetHolder())
        self.created = self.created + 1
        obj._kePool = self
        obj._keGen = 0
        RecordBaseline(obj)
        obj._keSnapshot = Snapshot(obj)
    end
    obj._keState = "used"
    obj:SetParent(parent)
    -- A page may have dimmed the object's root; a fresh one starts opaque.
    obj:SetAlpha(1)
    obj:Show()
    return obj
end

function WidgetPool:Release(obj)
    if obj._kePool ~= self or obj._keState ~= "used" then return end
    obj._keState = "releasing"
    local ok, clean = pcall(ReleaseSteps, self, obj)
    obj._keGen = obj._keGen + 1
    if ok and clean then
        obj._keState = "free"
        local free = self.free
        free[#free + 1] = obj
        return
    end
    obj._keState = "retired"
    -- Protected as well: a release that already failed once must not raise
    -- into the page rebuild.
    pcall(obj.Hide, obj)
    pcall(obj.SetParent, obj, nil)
    KE_GUI_ORPHAN_COUNT = (KE_GUI_ORPHAN_COUNT or 0) + 1
    local stats = GUIFrame._poolStats
    -- A page rebuild names the page being torn down; any other release
    -- happens on the page still showing.
    local page = GUIFrame._releasingPage or GUIFrame.selectedSidebarItem or "HomePage"
    if ok then
        stats.retired = stats.retired + 1
        stats.retiredByPage[page] = (stats.retiredByPage[page] or 0) + 1
    else
        stats.failed = stats.failed + 1
    end
    if DEBUG_GUIPOOL then
        KE:Print("pool " .. self.kind .. (ok and " retired on " or " failed on ") .. page
            .. (ok and "" or (": " .. tostring(clean))))
    end
end

-- holdsWidgets marks a pool whose objects are containers other pooled objects
-- may be made under (rows, a page's own hosts); a leaf widget is never one.
function GUIFrame:NewWidgetPool(kind, construct, reset, holdsWidgets)
    local pool = setmetatable({
        kind = kind, construct = construct, reset = reset, free = {}, created = 0,
        holdsWidgets = holdsWidgets == true,
    }, WidgetPool)
    self._pools[kind] = pool
    return pool
end

-- Parts a pooled object makes for itself after construction raise its
-- baseline, so they are never taken for something a page added. Both do
-- nothing on an unpooled object.
function GUIFrame:PoolGrow(obj, frame, children, regions)
    local owned, base = obj._keOwned, obj._keBase
    if not (owned and base) then return end
    for i = 1, #owned do
        if owned[i] == frame then
            base[i * 2 - 1] = base[i * 2 - 1] + children
            base[i * 2] = base[i * 2] + regions
            return
        end
    end
end

function GUIFrame:PoolOwn(obj, frame)
    local owned, base = obj._keOwned, obj._keBase
    if not (owned and base) then return end
    owned[#owned + 1] = frame
    base[#base + 1] = frame:GetNumChildren()
    base[#base + 1] = frame:GetNumRegions()
end

-- Pooling follows the page down from its root: the live scroll child, the
-- content of a card in use, or a row or other widget holder in use. Those are
-- the containers whose release walks their pooled children. Anything made
-- elsewhere (kit holders, the theme popup, a page's own frames, another
-- widget) is built directly, with no pooling.
function GUIFrame:IsPoolParent(parent)
    if not parent then return false end
    local area = self.contentArea
    if area and parent == area.scrollChild then return true end
    local owner = parent._kePoolOwner
    if owner then
        return owner._kePool ~= nil and owner._keState == "used"
    end
    local pool = parent._kePool
    return pool ~= nil and pool.holdsWidgets and parent._keState == "used" or false
end

-- A pool's object for this parent: from the pool under a pool parent, built
-- directly under any other, where nothing would ever release it.
function GUIFrame:AcquirePooled(kind, parent)
    local pool = self._pools[kind]
    if self:IsPoolParent(parent) then
        return pool:Acquire(parent)
    end
    return pool.construct(parent)
end

-- One child a container tracks or holds. A pooled object still here goes back
-- to its pool; any other frame still here is orphaned, as a rebuild always
-- does; a child something else has since taken is left alone. Regions are never
-- reparented: they stay and fail their container's check.
function GUIFrame:ReleaseTracked(child, container)
    if child:GetParent() ~= container then return end
    local pool = child._kePool
    if pool then
        if child._keState == "used" then pool:Release(child) end
        return
    end
    if not child:IsObjectType("Frame") then return end
    KE_GUI_ORPHAN_COUNT = (KE_GUI_ORPHAN_COUNT or 0) + 1
    child:Hide()
    child:SetParent(nil)
end

---------------------------------------------------------------------------------
-- Card System
---------------------------------------------------------------------------------
-- Every card carries one shared method set, copied on at construction, so the
-- pool's sweep can put back any method a page replaced.
local CardMethods = {}

local HEADER_HEIGHT = 32
local TOGGLE_W, TOGGLE_H, TOGGLE_KNOB = 34, 16, 12

local function PaintHeaderToggle(btn)
    local T = Theme
    local knob = btn._knob
    knob:ClearAllPoints()
    if btn._checked then
        btn:SetBackdropColor(T.accent[1] * 0.5, T.accent[2] * 0.5, T.accent[3] * 0.5, 1)
        knob:SetPoint("RIGHT", btn, "RIGHT", -2, 0)
        knob:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 0.8)
    else
        btn:SetBackdropColor(T.fieldBg[1], T.fieldBg[2], T.fieldBg[3], T.fieldBg[4])
        knob:SetPoint("LEFT", btn, "LEFT", 2, 0)
        knob:SetColorTexture(T.knobOff[1], T.knobOff[2], T.knobOff[3], T.knobOff[4])
    end
end

local function HeaderToggleSetChecked(btn, on)
    btn._checked = on and true or false
    PaintHeaderToggle(btn)
end

local function HeaderToggleGetChecked(btn)
    return btn._checked
end

-- The edge is one physical pixel, so it is re-applied when the UI scale has
-- changed since the button was last used.
local function ApplyHeaderToggleBackdrop(btn)
    local edge = KE:GetPixelSize()
    if btn._edge == edge then return end
    btn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = edge,
    })
    btn._edge = edge
end

-- One per card, made on first use; every AddHeaderToggle call rebinds it.
local function NewHeaderToggle(card)
    local btn = CreateFrame("Button", nil, card.header, "BackdropTemplate")
    btn:SetSize(TOGGLE_W, TOGGLE_H)
    ApplyHeaderToggleBackdrop(btn)
    local knob = btn:CreateTexture(nil, "ARTWORK")
    knob:SetSize(TOGGLE_KNOB, TOGGLE_KNOB)
    btn._knob = knob
    btn.SetChecked = HeaderToggleSetChecked
    btn.GetChecked = HeaderToggleGetChecked

    btn:SetScript("OnClick", function(b)
        -- Read before the callback runs: the rebuild below can hand this
        -- button to another card.
        local label, onValueChanged = b._label, b._onValueChanged
        b:SetChecked(not b._checked)
        local checked = b._checked
        if onValueChanged then onValueChanged(checked) end
        -- The chat line lives here so that no page prints its own.
        KE:Print(label .. ": " .. (checked and "|cff4DCC66On|r" or "|cffE64D4DOff|r"))
        -- A disabled module renders as a lone header bar, so the page must
        -- rebuild here for that to apply immediately.
        GUIFrame:RefreshContent()
        GUIFrame:RefreshSidebar()
    end)
    btn:SetScript("OnEnter", function(b)
        GameTooltip:SetOwner(b, "ANCHOR_TOP")
        GameTooltip:SetText(b._checked and "Enabled" or "Disabled", 1, 1, 1)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    card._keHeaderToggle = btn
    GUIFrame:PoolGrow(card, card.header, 1, 0)
    GUIFrame:PoolOwn(card, btn)
    return btn
end

-- Header toggle: the MODULE-ENABLE control. A switch in the card's title
-- bar reads as "this feature on/off"; everything in the body below is
-- settings. Keeps enables visually distinct from ordinary option toggles,
-- which live in body rows.
function CardMethods:AddHeaderToggle(initialState, onValueChanged)
    if not self.header then return nil end
    local btn = self._keHeaderToggle or NewHeaderToggle(self)
    ApplyHeaderToggleBackdrop(btn)
    btn:SetBackdropBorderColor(Theme.fieldBorder[1], Theme.fieldBorder[2], Theme.fieldBorder[3], 1)
    btn:ClearAllPoints()
    btn:SetPoint("LEFT", self.titleText, "RIGHT", 12, 0)
    btn._label = self.titleText:GetText()
    btn._onValueChanged = onValueChanged
    btn:SetChecked(initialState)
    btn:Show()
    self.headerToggle = btn
    return btn
end

function CardMethods:AddRow(widget, height, spacing)
    height = height or widget:GetHeight() or 24
    spacing = spacing or Theme.paddingSmall
    widget:SetParent(self.content)
    widget:ClearAllPoints()
    widget:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, -self.currentY)
    widget:SetPoint("TOPRIGHT", self.content, "TOPRIGHT", 0, -self.currentY)
    self.currentY = self.currentY + height + spacing
    table_insert(self.rows, widget)
    self.content:SetHeight(self.currentY)
    self:UpdateHeight()
    return widget
end

-- Labels and separators are regions, which cannot be orphaned; a card keeps
-- the ones it has made and hands them out again.
local function TakeRegion(card, kind)
    local free = kind == "label" and card._keLabelFree or card._keSepFree
    local region = free[#free]
    if region then
        free[#free] = nil
    else
        if kind == "label" then
            region = card.content:CreateFontString(nil, "OVERLAY")
        else
            region = card.content:CreateTexture(nil, "ARTWORK")
        end
        region._keKind = kind
        GUIFrame:PoolGrow(card, card.content, 0, 1)
    end
    region:ClearAllPoints()
    region:Show()
    return region
end

local function ReturnRegion(card, region)
    region:Hide()
    local free = region._keKind == "label" and card._keLabelFree or card._keSepFree
    free[#free + 1] = region
end

function CardMethods:AddLabel(text)
    local T = Theme
    local label = TakeRegion(self, "label")
    label:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, -self.currentY)
    label:SetPoint("TOPRIGHT", self.content, "TOPRIGHT", 0, -self.currentY)
    label:SetJustifyH("LEFT")
    KE:ApplyThemeFont(label, "normal")
    label:SetText(text)
    label:SetTextColor(T.textSecondary[1], T.textSecondary[2], T.textSecondary[3], 1)
    local height = label:GetStringHeight() or 14
    self.currentY = self.currentY + height + T.paddingSmall
    self.content:SetHeight(self.currentY)
    self:UpdateHeight()
    table_insert(self.regions, label)
    return label
end

-- A label with the accent-coloured lead-in the GUI uses for explanatory
-- text. Resolved per call, not captured, so it follows a theme change.
function CardMethods:AddNote(text)
    return self:AddLabel(KE:ColorTextByTheme("-") .. " " .. text)
end

function CardMethods:AddSeparator()
    local T = Theme
    local sep = TakeRegion(self, "sep")
    sep:SetHeight(T.borderSize)
    sep:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, -self.currentY - T.paddingSmall)
    sep:SetPoint("TOPRIGHT", self.content, "TOPRIGHT", 0, -self.currentY - T.paddingSmall)
    sep:SetColorTexture(T.divider[1], T.divider[2], T.divider[3], T.divider[4])
    self.currentY = self.currentY + T.borderSize + T.paddingSmall * 2
    self.content:SetHeight(self.currentY)
    self:UpdateHeight()
    table_insert(self.regions, sep)
    return sep
end

function CardMethods:AddSpacing(amount)
    amount = amount or Theme.paddingMedium
    self.currentY = self.currentY + amount
    self.content:SetHeight(self.currentY)
    self:UpdateHeight()
end

-- A mark lets a card redraw everything below one point without a page
-- rebuild.
function CardMethods:MarkBody()
    return { y = self.currentY, rows = #self.rows, regions = #self.regions }
end

function CardMethods:TruncateBody(mark)
    for i = #self.rows, mark.rows + 1, -1 do
        GUIFrame:ReleaseTracked(self.rows[i], self.content)
        self.rows[i] = nil
    end
    for i = #self.regions, mark.regions + 1, -1 do
        ReturnRegion(self, self.regions[i])
        self.regions[i] = nil
    end
    self.currentY = mark.y
    self.content:SetHeight(self.currentY)
    self:UpdateHeight()
end

-- Header-only collapse: a card with no body rows or labels — a module whose
-- only control is its header toggle, or any module rendered as a lone header
-- bar while disabled — is just its title bar. Without this branch the card
-- still reserves paddingMedium*2 of empty body beneath the header, which
-- reads as a stray gap between it and the next card.
function CardMethods:UpdateHeight()
    local totalHeight
    if self.currentY == 0 and self.headerHeight > 0 then
        -- Exactly the header, so the header plate covers the card entirely
        -- and the bar is one solid colour. No borderSize*2 allowance: the
        -- header is flush at (0,0) with its own edge, so that allowance
        -- would expose two pixels of card backdrop under the header.
        totalHeight = self.headerHeight
        self.content:Hide()
    else
        totalHeight = self.headerHeight + self.currentY + Theme.paddingMedium * 2
        self.content:Show()
    end
    self:SetHeight(totalHeight)
    self.contentHeight = totalHeight
end

function CardMethods:GetContentHeight()
    return self.contentHeight
end

function CardMethods:GetNextOffset()
    return self._yOffset + self:GetContentHeight() + Theme.paddingSmall
end

-- Lazy-create a transparent click-blocker overlay above the card content.
-- Shown when the card is disabled to make widget interactions non-functional
-- without recursively walking row.widgets / kit subframes (which would need
-- per-widget knowledge of how each card type lays out its children).
local function GetMouseBlocker(card)
    local blocker = card._keBlocker
    if not blocker then
        blocker = CreateFrame("Frame", nil, card)
        blocker:SetAllPoints(card)
        blocker:EnableMouse(true)
        -- Don't capture mouse wheel — let scroll events bubble up to the
        -- scrollFrame so the user can still scroll past a disabled card.
        blocker:Hide()
        card._keBlocker = blocker
        GUIFrame:PoolGrow(card, card, 1, 0)
        GUIFrame:PoolOwn(card, blocker)
    end
    -- +100 above the card's own frame level should cover all default-level
    -- descendants. Re-levelled on every use: a reused card can sit at a
    -- different level than when the blocker was made.
    blocker:SetFrameLevel(card:GetFrameLevel() + 100)
    return blocker
end

function CardMethods:SetEnabled(enabled)
    if enabled then
        self:SetAlpha(1)
        if self.header then self.header:SetAlpha(1) end
        if self.titleText then self.titleText:SetAlpha(1) end
        if self._keBlocker then self._keBlocker:Hide() end
    else
        self:SetAlpha(0.5)
        if self.header then self.header:SetAlpha(0.5) end
        if self.titleText then self.titleText:SetAlpha(0.5) end
        GetMouseBlocker(self):Show()
    end
end

-- Re-apply theme-tied colors. KE:RefreshTheme replaces Theme.bgLight /
-- accent / border tables via CopyColor; values copied at construction
-- (SetBackdropColor, SetTextColor) become stale. Every acquire calls this.
function CardMethods:ApplyThemeColors()
    local TT = Theme
    self:SetBackdropColor(TT.bgLight[1], TT.bgLight[2], TT.bgLight[3], TT.bgLight[4])
    self:SetBackdropBorderColor(TT.border[1], TT.border[2], TT.border[3], TT.border[4])
    if self.header then
        self.header:SetBackdropColor(TT.bgMedium[1], TT.bgMedium[2], TT.bgMedium[3], TT.bgMedium[4])
        self.header:SetBackdropBorderColor(TT.border[1], TT.border[2], TT.border[3], TT.border[4])
    end
    if self.titleText then
        self.titleText:SetTextColor(TT.accent[1], TT.accent[2], TT.accent[3], 1)
    end
end

function CardMethods:Reset()
    self:TruncateBody({ y = 0, rows = 0, regions = 0 })
    self.contentHeight = 0
    self.content:SetHeight(1)
    -- One source of truth for card height; a reset card has no rows, so this
    -- resolves to the header-only collapse above.
    self:UpdateHeight()
end

local function NewCard(parent, titled)
    local T = Theme
    local card = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    card:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = T.borderSize,
    })
    card.rows = {}
    card.regions = {}
    card._keLabelFree = {}
    card._keSepFree = {}
    card.headerHeight = 0

    if titled then
        card.headerHeight = HEADER_HEIGHT
        local header = CreateFrame("Frame", nil, card, "BackdropTemplate")
        header:SetHeight(HEADER_HEIGHT)
        header:SetPoint("TOPLEFT", card, "TOPLEFT", 0, 0)
        header:SetPoint("TOPRIGHT", card, "TOPRIGHT", 0, 0)
        header:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = T.borderSize,
        })
        card.header = header

        local titleText = header:CreateFontString(nil, "OVERLAY")
        titleText:SetPoint("LEFT", header, "LEFT", T.paddingMedium, 0)
        card.titleText = titleText
    end

    local content = CreateFrame("Frame", nil, card)
    content:SetPoint("TOPLEFT", card, "TOPLEFT", T.paddingMedium, -card.headerHeight - T.paddingMedium)
    content:SetPoint("TOPRIGHT", card, "TOPRIGHT", -T.paddingMedium, -card.headerHeight - T.paddingMedium)
    content:EnableMouse(false)
    content._kePoolOwner = card
    card.content = content

    for name, fn in pairs(CardMethods) do
        card[name] = fn
    end
    card._keOwned = card.header and { card, card.header, content } or { card, content }
    return card
end

local function ConfigureCard(card, parent, title, yOffset, width)
    local T = Theme
    card:ClearAllPoints()
    card:SetPoint("TOPLEFT", parent, "TOPLEFT", T.paddingSmall, -(yOffset or 0) + T.paddingSmall)
    if width then
        card:SetWidth(width)
    else
        card:SetPoint("RIGHT", parent, "RIGHT", -T.paddingSmall, 0)
    end
    card:EnableMouse(false)
    if card.titleText then
        card.header:SetAlpha(1)
        card.titleText:SetAlpha(1)
        KE:ApplyThemeFont(card.titleText, "large")
        card.titleText:SetText(title)
    end
    if card._keBlocker then card._keBlocker:Hide() end
    card:ApplyThemeColors()
    card.contentHeight = 0
    card.currentY = 0
    card._yOffset = yOffset or 0
    card.content:SetHeight(1)
    card:UpdateHeight()
end

local function ReleaseCard(card)
    local rows, content = card.rows, card.content
    for i = #rows, 1, -1 do
        GUIFrame:ReleaseTracked(rows[i], content)
        rows[i] = nil
    end
    -- A pooled row built on this card but never added to it.
    if content:GetNumChildren() > 0 then
        for _, child in ipairs({ content:GetChildren() }) do
            if child._kePool then GUIFrame:ReleaseTracked(child, content) end
        end
    end
    local regions = card.regions
    for i = #regions, 1, -1 do
        ReturnRegion(card, regions[i])
        regions[i] = nil
    end
    local toggle = card._keHeaderToggle
    if toggle then
        toggle:Hide()
        toggle._label = nil
        toggle._onValueChanged = nil
    end
    if card._keBlocker then card._keBlocker:Hide() end
end

local function NewTitledCard(holder) return NewCard(holder, true) end
local function NewPlainCard(holder) return NewCard(holder, false) end

-- The header exists only on titled cards, so each shape has its own pool.
local cardPool = GUIFrame:NewWidgetPool("card", NewTitledCard, ReleaseCard)
local plainCardPool = GUIFrame:NewWidgetPool("card:plain", NewPlainCard, ReleaseCard)

function GUIFrame:CreateCard(parent, title, yOffset, width)
    local titled = title ~= nil and title ~= ""
    local card
    if self:IsPoolParent(parent) then
        card = (titled and cardPool or plainCardPool):Acquire(parent)
    else
        card = NewCard(parent, titled)
    end
    ConfigureCard(card, parent, title, yOffset, width)
    return card
end

local function RebuildPageLater()
    C_Timer.After(0, function() GUIFrame:RefreshContent() end)
end

-- Applies a card's height change to the page without a rebuild. That is only
-- right while nothing is drawn below the card; otherwise, or when the card has
-- no parent or position to measure, the page is rebuilt a frame later.
function GUIFrame:ResizeCardInPlace(card, oldHeight)
    local delta = card:GetContentHeight() - oldHeight
    if delta == 0 then return end
    local parent = card:GetParent()
    local cardTop = card:GetTop()
    if not parent or not cardTop then
        RebuildPageLater()
        return
    end
    for _, child in ipairs({ parent:GetChildren() }) do
        if child ~= card and child:IsShown() then
            local top = child:GetTop()
            if not top or top < cardTop then
                RebuildPageLater()
                return
            end
        end
    end
    parent:SetHeight(parent:GetHeight() + delta)
end

---------------------------------------------------------------------------------
-- Row System
---------------------------------------------------------------------------------
local RowMethods = {}

-- Lays the widgets out across the row by their width shares. The width is
-- kept because OnSizeChanged fires only when the size differs from the one
-- last reported, so a reused row the same size as on its last use gets none.
local function RowOnSizeChanged(row, width)
    row._keLastWidth = width
    local x = 0
    for _, widget in ipairs(row.widgets) do
        local widgetWidth = width * widget._widthPct - (widget._spacing or 0)
        widget:ClearAllPoints()
        widget:SetPoint("TOPLEFT", row, "TOPLEFT", x + (widget._xOffset or 0), widget._yOffset or 0)
        widget:SetWidth(widgetWidth)
        x = x + widgetWidth + (widget._spacing or Theme.paddingSmall)
    end
end

function RowMethods:AddWidget(widget, widthPct, spacing, xOffset, yOffset)
    widthPct = widthPct or 0.5
    spacing = spacing or Theme.paddingSmall
    xOffset = xOffset or 0
    yOffset = yOffset or 0
    widget:SetParent(self)
    widget:ClearAllPoints()
    widget:SetPoint("TOPLEFT", self, "TOPLEFT", self.nextX + xOffset, yOffset)
    if not widget.explicitHeight then
        widget:SetHeight(self._rowHeight)
    end
    widget._widthPct = widthPct
    widget._spacing = spacing
    widget._xOffset = xOffset
    widget._yOffset = yOffset
    table_insert(self.widgets, widget)
    -- Laid out at once at the last reported width. A row that ends up a
    -- different size still gets OnSizeChanged, which lays it out again.
    local width = self._keLastWidth
    if width and width > 0 then RowOnSizeChanged(self, width) end
    self.nextX = self.nextX + 10
end

-- A row owns at most one chevron texture, made on first use, so a caller that
-- needs one never adds a region the row's pool would reject.
function RowMethods:GetChevron()
    local chevron = self._keChevron
    if not chevron then
        chevron = self:CreateTexture(nil, "OVERLAY")
        self._keChevron = chevron
        GUIFrame:PoolGrow(self, self, 0, 1)
    end
    chevron:ClearAllPoints()
    chevron:Show()
    return chevron
end

-- A row owns at most one label, made on first use like the chevron. Every
-- call puts it back to one known state, because the next page to get this
-- row may set less than the last one did.
function RowMethods:GetLabel(size)
    local label = self._keLabel
    if not label then
        label = self:CreateFontString(nil, "OVERLAY")
        self._keLabel = label
        GUIFrame:PoolGrow(self, self, 0, 1)
    end
    KE:ApplyThemeFont(label, size)
    label:ClearAllPoints()
    label:SetSize(0, 0)
    label:SetJustifyH("CENTER")
    label:SetJustifyV("MIDDLE")
    label:SetWordWrap(true)
    label:SetAlpha(1)
    label:SetTextColor(1, 1, 1, 1)
    label:SetText("")
    label:Show()
    return label
end

local function NewRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row.widgets = {}
    for name, fn in pairs(RowMethods) do
        row[name] = fn
    end
    row:SetScript("OnSizeChanged", RowOnSizeChanged)
    row._keOwned = { row }
    return row
end

local function ReleaseRow(row)
    local widgets = row.widgets
    for i = #widgets, 1, -1 do
        GUIFrame:ReleaseTracked(widgets[i], row)
        widgets[i] = nil
    end
    if row._keChevron then row._keChevron:Hide() end
    if row._keLabel then row._keLabel:Hide() end
    -- A pooled widget built on this row but never added to it.
    if row:GetNumChildren() > 0 then
        for _, child in ipairs({ row:GetChildren() }) do
            if child._kePool then GUIFrame:ReleaseTracked(child, row) end
        end
    end
end

-- Rows hold other pooled widgets; a page may register holders of its own.
local rowPool = GUIFrame:NewWidgetPool("row", NewRow, ReleaseRow, true)

function GUIFrame:CreateRow(parent, height)
    height = height or 24
    local row
    if self:IsPoolParent(parent) then
        row = rowPool:Acquire(parent)
    else
        row = NewRow(parent)
    end
    row:SetHeight(height)
    row:EnableMouse(false)
    row._rowHeight = height
    row.nextX = 0
    return row
end

---------------------------------------------------------------------------------
-- RefreshContent
---------------------------------------------------------------------------------
function GUIFrame:RefreshContent()
    -- Leak tracer: every call increments a /run-readable global so a runaway
    -- rebuild loop can be detected and its page named live, without a debug
    -- build:
    --   /run print(KE_GUI_REFRESH_COUNT, KE_GUI_REFRESH_ITEM, KE_GUI_ORPHAN_COUNT)
    -- Counts ABOVE the contentArea guard on purpose: a pre-first-open call is
    -- still a caller worth catching. Cost is one add + two writes per call.
    KE_GUI_REFRESH_COUNT = (KE_GUI_REFRESH_COUNT or 0) + 1
    KE_GUI_REFRESH_ITEM = self.selectedSidebarItem or "HomePage"

    -- A callback drained below, or a release in the teardown loop, may ask
    -- for a rebuild; the rebuild already under way is the one it wants.
    if self._drainingDeferred or self._tearingDown then return end

    if not self.contentArea then return end

    -- NEVER rebuild while the GUI is hidden. Every frame a page builds for
    -- itself is orphaned by the clear pass below, and frames are never
    -- garbage-collected, so an event-driven caller firing with the GUI closed
    -- (Automation's CVAR_UPDATE handler) would leak on every event. Mark dirty
    -- and bail; Show() replays one refresh so a reopened page is never stale.
    -- Minimized counts as hidden here. The frame is still shown, so the test
    -- below passes, but the page is not on screen and every edit-mode drop
    -- calls in.
    if self.minimized or not (self.mainFrame and self.mainFrame:IsShown()) then
        self._contentDirtyWhileHidden = true
        return
    end
    self._contentDirtyWhileHidden = nil

    -- A toggle still waiting to fire its callback fires it now, while the
    -- page it belongs to is whole.
    self:DrainDeferredWidgetCallbacks()

    -- Fire rebuild callbacks FIRST so widget pools can ReleaseAll their
    -- kits back to their hidden holders before the clear loop below would
    -- orphan them. Always fires regardless of in-place vs.
    -- item-switch — pools need to release every render, not just on
    -- item changes.
    for _, callback in pairs(self.contentRebuildCallbacks) do
        pcall(callback)
    end

    local itemId = self.selectedSidebarItem or "HomePage"
    local sameItem = (self.contentArea._lastItemId == itemId)
    -- Anything released or retired during the teardown below is counted
    -- against the page being torn down, not the one being built.
    self._releasingPage = self.contentArea._lastItemId or itemId

    -- Fire content cleanup callbacks ONLY on real item switch — same-item
    -- refreshes shouldn't tear down preview state.
    if not sameItem then
        for _, callback in pairs(self.contentCleanupCallbacks) do
            pcall(callback)
        end
    end

    self.contentArea._lastItemId = itemId

    -- Clear existing content
    local scrollChild = self.contentArea.scrollChild

    for _, region in ipairs({ scrollChild:GetRegions() }) do
        if region:GetObjectType() == "FontString" or region:GetObjectType() == "Texture" then
            region:Hide()
        end
    end
    -- Pooled objects go back to their pools; anything else is orphaned and
    -- counted in KE_GUI_ORPHAN_COUNT, the leak's ground truth. A release that
    -- raises must not leave the flag set: every later refresh would be
    -- swallowed.
    self._tearingDown = true
    local released, releaseErr = pcall(function()
        for _, child in ipairs({ scrollChild:GetChildren() }) do
            self:ReleaseTracked(child, scrollChild)
        end
    end)
    self._tearingDown = nil
    self._releasingPage = nil
    if not released then error(releaseErr, 0) end

    local T = Theme
    local yOffset = T.paddingMedium

    if itemId and self.registeredContent[itemId] then
        local ok, result = pcall(self.registeredContent[itemId], scrollChild, yOffset)
        if ok and result then
            yOffset = result
        elseif ok then
            -- Builder returned nil (stub) — show placeholder
            yOffset = self:BuildPlaceholderContent(scrollChild, yOffset)
        else
            local errorCard = self:CreateCard(scrollChild, "Error", yOffset)
            errorCard:AddLabel("Content builder failed: " .. tostring(result))
            yOffset = yOffset + errorCard:GetContentHeight() + T.paddingMedium
        end
    elseif not self._pagesLoaded then
        yOffset = self:BuildPagesNotLoadedContent(scrollChild, yOffset)
    else
        -- No registered builder
        yOffset = self:BuildPlaceholderContent(scrollChild, yOffset)
    end

    scrollChild:SetHeight(yOffset + T.paddingLarge)
end

-- Placeholder for tabs with no content builder yet
function GUIFrame:BuildPlaceholderContent(scrollChild, yOffset)
    local T = Theme
    local card = self:CreateCard(scrollChild, "Coming Soon", yOffset)
    card:AddLabel("This section is under construction.")
    card:AddSpacing(T.paddingSmall)
    yOffset = yOffset + card:GetContentHeight() + T.paddingMedium
    return yOffset
end

function GUIFrame:BuildPagesNotLoadedContent(scrollChild, yOffset)
    local T = Theme
    local card = self:CreateCard(scrollChild, "Settings pages not loaded", yOffset)
    card:AddLabel(self._pagesLoadMessage or "")
    card:AddSpacing(T.paddingSmall)
    yOffset = yOffset + card:GetContentHeight() + T.paddingMedium
    return yOffset
end
