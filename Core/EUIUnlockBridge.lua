-- ╔══════════════════════════════════════════════════════════╗
-- ║  EUIUnlockBridge.lua                                     ║
-- ║  Core: EllesmereUI unlock-mode bridge                    ║
-- ║  Purpose: publish KE movers as EUI unlock elements so     ║
-- ║           EUI elements can anchor to them.                ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)

local Bridge = {}
KE.EUIUnlock = Bridge

-- KE stores every element position as AnchorFrom / AnchorTo / XOffset /
-- YOffset; EllesmereUI hands movers the same four values under different
-- names. Both directions default identically so a half-written profile cannot
-- park a frame at nil.
function Bridge.ToEUIPosition(pos)
    if type(pos) ~= "table" then return nil end
    return {
        point    = pos.AnchorFrom or "CENTER",
        relPoint = pos.AnchorTo or "CENTER",
        x        = pos.XOffset or 0,
        y        = pos.YOffset or 0,
    }
end

function Bridge.FromEUIPosition(point, relPoint, x, y)
    return {
        AnchorFrom = point or "CENTER",
        AnchorTo   = relPoint or "CENTER",
        XOffset    = x or 0,
        YOffset    = y or 0,
    }
end

local pairs = pairs
local ipairs = ipairs
local type = type
local tinsert = table.insert

-- EUI element keys are global across every addon that registers, so ours are
-- namespaced. Registered elements are never removed: an element that goes
-- hidden reports isHidden instead, which keeps anchors pointing at it alive.
local KEY_PREFIX = "KE_"
local DEFAULT_GROUP = "KitnEssentials"
local DEFAULT_ORDER = 500

-- Must equal the real addon folder name: EllesmereUI's export list ticks a row
-- only when the folder reports as loaded.
local PROFILE_FOLDER = "KitnEssentials"

local pending = {}   -- configs handed over before EUI or the frame was ready
local published = {}        -- euiKey -> true, so a re-register is a no-op
local publishedConfigs = {} -- list of { config = ..., opts = ... }, never pruned

local function EUI()
    local eui = _G.EllesmereUI
    if not eui then return nil end
    if not (eui.RegisterUnlockElements and eui.MakeUnlockElement) then return nil end
    return eui
end

-- EllesmereUI keeps an unlock-layout edge only when both of its endpoints
-- resolve to a folder in its own profile map. KE is not one of its modules, so
-- without this entry every anchor pointing at a KE element is dropped when a
-- profile is exported AND when one is imported, and the import's merge then
-- deletes the user's live edge as well. Stamping the element's folder is not
-- enough on its own: that classifies the key, this admits the folder.
--
-- Folder and display are all an entry needs. The map's own loop over canon and
-- suffix runs at file load, so it never sees this insert; every later consumer
-- falls back to the folder name, and nothing reads a field we do not set.
local function InjectProfileAddon()
    local eui = _G.EllesmereUI
    local map = eui and eui._ADDON_DB_MAP
    if type(map) ~= "table" then return end

    for _, entry in ipairs(map) do
        if type(entry) == "table" and entry.folder == PROFILE_FOLDER then return end
    end

    map[#map + 1] = { folder = PROFILE_FOLDER, display = "KitnEssentials" }
end
Bridge.InjectProfileAddon = InjectProfileAddon

local function ResolveFrame(config)
    if config.frame then return config.frame end
    if config.frameName then return _G[config.frameName] end
    return nil
end

-- A match child's targets as its settings page shows them, per key, recorded by
-- the page through ShownMatchTargets as it is built. The page needs a rebuild
-- only when the live targets differ from those, never on a matched resize.
local matchShown = {}
local checkPending = {}

local function ShownDiffers(key)
    local shown = matchShown[key]
    if not shown then return false end
    local width = Bridge:MatchTarget(key, "width") or false
    local height = Bridge:MatchTarget(key, "height") or false
    return shown.width ~= width or shown.height ~= height
end

-- A frame later, once a cleared match has left unlock mode's store, and once
-- for however many setter calls that frame brought.
local function ScheduleMatchCheck(config)
    local gui = KE.GUIFrame
    if checkPending[config.key] or not (gui and gui.mainFrame and gui.mainFrame:IsShown()) then return end
    checkPending[config.key] = true
    C_Timer.After(0, function()
        checkPending[config.key] = nil
        if not (config.guiPath and gui.mainFrame:IsShown() and gui.selectedSidebarItem == config.guiPath) then
            return
        end
        if not ShownDiffers(config.key) then return end
        local ok, err = pcall(gui.RefreshContent, gui)
        if not ok then geterrorhandler()(err) end
    end)
end

-- The key and axis whose setter this bridge is running, so a pull made from
-- inside that apply knows the apply already covers it.
local sizingKey, sizingAxis

-- Unlock mode pcalls a match child's setter, but its typed size boxes call it
-- bare, so a raise is contained here and still reported.
local function ApplyMatchedSize(config, axis, setter, size)
    if type(size) ~= "number" or size ~= size or size <= 0 then return end
    local outerKey, outerAxis = sizingKey, sizingAxis
    sizingKey, sizingAxis = config.key, axis
    local ok, err = pcall(setter, size)
    sizingKey, sizingAxis = outerKey, outerAxis
    if not ok then geterrorhandler()(err) end
    ScheduleMatchCheck(config)
end

local function BuildElement(config, opts)
    local eui = EUI()
    if not eui then return nil end

    local euiKey = KEY_PREFIX .. config.key
    local isHidden = opts and opts.isHidden

    -- A registration that hands over size setters is a match child: unlock mode
    -- shows its match buttons and calls the setters at login, on its target's
    -- resize and in combat. Every other registration keeps its size on the
    -- module's own sliders, which matchUnavailable says: it may be matched TO,
    -- but never takes its own size from something else.
    local setWidth = opts and opts.setWidth
    local setHeight = opts and opts.setHeight
    local matchUnavailable, matchedWidth, matchedHeight, positionHeld
    if setWidth or setHeight then
        if setWidth then matchedWidth = function(_, w) ApplyMatchedSize(config, "width", setWidth, w) end end
        if setHeight then matchedHeight = function(_, h) ApplyMatchedSize(config, "height", setHeight, h) end end
        -- After a match apply outside unlock mode, unlock mode re-places a child
        -- whose position reads CENTER/CENTER against the screen, noInitHook or
        -- not. Held while no unlock anchor places it, KE's own placement stands;
        -- an anchored child still follows its anchor.
        positionHeld = function() return not Bridge:IsAnchored(config.key) end
    else
        matchUnavailable = function()
            return "Size is set in the KitnEssentials options."
        end
    end

    return eui.MakeUnlockElement({
        key   = euiKey,
        label = (opts and opts.label) or config.displayName or config.key,
        group = (opts and opts.group) or DEFAULT_GROUP,
        order = (opts and opts.order) or DEFAULT_ORDER,

        -- noAnchorTo and noAnchorTarget are deliberately NOT set: being an
        -- anchor target is the whole reason for registering.
        --
        -- noResize is deliberately NOT set either, and must not be re-added.
        -- Unlock mode's validator deletes any width or height match whose
        -- TARGET carries that flag, and it runs on every unlock-mode open, so
        -- the flag silently destroys the one relationship these elements exist
        -- to support. It also gates nothing worth keeping: unlock mode's
        -- movers have no sizing grip, and the match apply reads a target
        -- through getSize without ever consulting it. What the flag does cost
        -- is the mover's X and Y position boxes, which work and are wanted.
        matchUnavailable = matchUnavailable,
        setWidth = matchedWidth,
        setHeight = matchedHeight,
        isPositionHeld = positionHeld,

        -- KE places and pixel-snaps its own frames, so unlock mode must not
        -- re-place them: its init pass would otherwise re-apply the position
        -- against a grid derived from the frame's effective scale, which is the
        -- exact method KE's pixel-perfect system rejects, and it would force the
        -- anchor's relative frame to the screen. Dependents anchored to us still
        -- follow: the size hook and the anchor pass are outside this branch.
        noInitHook = true,

        getFrame = function() return ResolveFrame(config) end,

        getSize = function()
            local frame = ResolveFrame(config)
            if not frame or not frame.GetWidth then return nil end
            return frame:GetWidth(), frame:GetHeight()
        end,

        isHidden = function()
            if isHidden then return isHidden() == true end
            local frame = ResolveFrame(config)
            return frame == nil
        end,

        savePos = function(_, point, relPoint, x, y)
            -- The mover hands back coordinates already converted to
            -- UIParent's CENTER. KE re-applies the same four values against
            -- the element's OWN resolved anchor parent, so the two coordinate
            -- spaces agree only while that parent is UIParent. Refuse the
            -- write otherwise: the frame would land somewhere else entirely,
            -- silently.
            if config.getParentFrame then
                local parent = config.getParentFrame()
                if parent and parent ~= _G.UIParent then return end
            end

            -- Unlock mode always hands back CENTER/CENTER, so storing its four
            -- values verbatim would overwrite whatever anchor points the user
            -- picked in KE's own position card. Re-express the same screen
            -- position against the stored pair instead, and only fall back to
            -- CENTER when there is no stored pair or no live size to work from.
            local stored = config.getPosition()
            local frame = ResolveFrame(config)
            local uiParent = _G.UIParent
            -- Measure rather than test for the getter: a frame that has not been
            -- through a layout pass answers nil or zero, and a zero-extent frame
            -- would silently place the anchor half the frame's real size out.
            local fw = frame and frame.GetWidth and frame:GetWidth()
            local fh = frame and frame.GetHeight and frame:GetHeight()
            local pw = uiParent and uiParent.GetWidth and uiParent:GetWidth()
            local ph = uiParent and uiParent.GetHeight and uiParent:GetHeight()

            if point == "CENTER" and relPoint == "CENTER"
                and stored and stored.AnchorFrom and stored.AnchorTo
                and not (stored.AnchorFrom == "CENTER" and stored.AnchorTo == "CENTER")
                and fw and fw > 0 and fh and fh > 0
                and pw and pw > 0 and ph and ph > 0
            then
                -- KE:ResolveAnchorOffsets works in absolute screen coordinates
                -- and rounds, which is what keeps a stored offset a whole number
                -- for the position card's sliders. Unlock mode measures from the
                -- parent's center, so lift its pair into that space first.
                local pl = uiParent:GetLeft() or 0
                local pb = uiParent:GetBottom() or 0
                local ox, oy = KE:ResolveAnchorOffsets(
                    pl + pw / 2 + (x or 0), pb + ph / 2 + (y or 0),
                    stored.AnchorFrom, stored.AnchorTo,
                    fw, fh, pl, pb, pw, ph)
                config.setPosition(Bridge.FromEUIPosition(
                    stored.AnchorFrom, stored.AnchorTo, ox, oy))
            else
                config.setPosition(Bridge.FromEUIPosition(point, relPoint, x, y))
            end

            -- The position card reads the profile when its page is built, so an
            -- outside write is invisible until the page is rebuilt. KE's own
            -- edit mode refreshes here for the same reason.
            -- Contained on purpose: this runs inside unlock mode's own save
            -- loop, so a page builder that threw would abort that loop and
            -- leave the session open with other addons unsaved.
            if KE.GUIFrame and KE.GUIFrame.mainFrame and KE.GUIFrame.mainFrame:IsShown() then
                local ok, err = pcall(KE.GUIFrame.RefreshContent, KE.GUIFrame)
                -- Contained, not swallowed: the loop survives either way, and a
                -- page builder that broke still has to be reportable.
                if not ok then geterrorhandler()(err) end
            end
        end,

        loadPos = function()
            return Bridge.ToEUIPosition(config.getPosition())
        end,

        -- No-op on purpose. A KE position always holds a usable anchor and the
        -- module's own position card reads it; blanking it would leave that card
        -- with nothing to show and the frame unplaced.
        clearPos = function() end,

        applyPos = function()
            local pos = config.getPosition()
            if pos then config.setPosition(pos) end
        end,
    })
end

local REAPPLY_INTERVAL = 0.1
local REAPPLY_MAX_TRIES = 20 -- about two seconds, then give up rather than poll forever

-- GetLeft answers nil until a frame has been through a layout pass, which is
-- the same test EUI's own apply makes before it gives up. Re-applying earlier
-- hits the identical bail this is working around.
local function AllPublishedFramesLaidOut()
    for _, entry in ipairs(publishedConfigs) do
        local frame = ResolveFrame(entry.config)
        if not frame or not frame.GetLeft or not frame:GetLeft() then return false end
    end
    return true
end

local function ReapplyAnchorsToUs()
    local eui = EUI()
    local anchors = _G.EllesmereUIDB and _G.EllesmereUIDB.unlockAnchors
    if not (eui and eui.ReapplyUnlockAnchor and type(anchors) == "table") then return end

    for childKey, info in pairs(anchors) do
        if type(info) == "table" and info.target and published[info.target] then
            KE:SafeCall("EllesmereUI unlock re-apply", eui.ReapplyUnlockAnchor, childKey)
        end
    end
end

-- Unlock mode runs several size-match passes, but none of them keys off an
-- element REGISTERING, and the one hook that does fire on late registration
-- re-applies anchors only. KE publishes after those passes have run, so a match
-- naming a KE element would stay inert until something else happened to resize.
-- There is no per-record re-apply to call; pushing from the target reaches every
-- child matched to it, which is the same direction the anchor loop above works
-- in.
--
-- Guarded per function, not per addon: EllesmereUI dropping one axis must cost
-- that axis, not both.
local function ReapplyMatchesToUs()
    local eui = EUI()
    if not eui then return end

    for _, entry in ipairs(publishedConfigs) do
        local euiKey = KEY_PREFIX .. entry.config.key
        if eui.PropagateWidthMatch then KE:SafeCall("EllesmereUI width match", eui.PropagateWidthMatch, euiKey) end
        if eui.PropagateHeightMatch then KE:SafeCall("EllesmereUI height match", eui.PropagateHeightMatch, euiKey) end
    end
end
Bridge.ReapplyMatchesToUs = ReapplyMatchesToUs

-- The element key unlock mode holds as this element's width or height target,
-- or nil. pcall because the store belongs to another addon.
function Bridge:MatchTarget(key, axis)
    local eui = EUI()
    if not eui then return nil end
    local get = (axis == "height") and eui.GetHeightMatchTarget or eui.GetWidthMatchTarget
    if type(get) ~= "function" then return nil end
    local ok, target = pcall(get, KEY_PREFIX .. key)
    if ok and type(target) == "string" then return target end
    return nil
end

-- The live targets for a settings page as it is built, recorded as the ones it
-- shows, so the page check compares with what is on screen.
function Bridge:ShownMatchTargets(key)
    local width, height = self:MatchTarget(key, "width"), self:MatchTarget(key, "height")
    local shown = matchShown[key]
    if not shown then
        shown = {}
        matchShown[key] = shown
    end
    shown.width, shown.height = width or false, height or false
    return width, height
end

-- Pulls refused inside an apply of another axis, per key and axis, made a frame
-- later unless a pull of that axis runs first.
local deferredPulls = {}

local function DeferPull(key, axis)
    local slot = deferredPulls[key]
    if not slot then
        slot = {}
        deferredPulls[key] = slot
    end
    if slot[axis] then return end
    slot[axis] = true
    C_Timer.After(0, function()
        if not slot[axis] then return end
        slot[axis] = nil
        Bridge:PullMatch(key, axis)
    end)
end

-- A match whose CHILD is ours has no per-child apply to call; pushing from the
-- child's target reaches it, along with that target's other children. Answers
-- false only for a pull it could not make yet. Inside unlock mode's own apply it
-- never pushes, since a nested push would re-apply the siblings and clear the
-- apply's in-progress flag early: the axis being applied is already covered,
-- and any other is made a frame later.
function Bridge:PullMatch(key, axis)
    local eui = EUI()
    if not eui or not published[KEY_PREFIX .. key] then return true end
    if eui._propagatingMatch then
        if sizingKey == key and sizingAxis == axis then return true end
        DeferPull(key, axis)
        return false
    end
    local slot = deferredPulls[key]
    if slot then slot[axis] = nil end
    local target = self:MatchTarget(key, axis)
    if not target then return true end
    if axis == "height" then
        if eui.PropagateHeightMatch then
            KE:SafeCall("EllesmereUI height pull", eui.PropagateHeightMatch, target)
        end
    elseif eui.PropagateWidthMatch then
        KE:SafeCall("EllesmereUI width pull", eui.PropagateWidthMatch, target)
    end
    return true
end

-- Unlock mode applies every match at login, before KE publishes, so a KE child
-- was never sized. Only the axes a registration gave a setter for are pulled.
local function PullMatchesToUs()
    for _, entry in ipairs(publishedConfigs) do
        local opts = entry.opts
        if opts and opts.setWidth then Bridge:PullMatch(entry.config.key, "width") end
        if opts and opts.setHeight then Bridge:PullMatch(entry.config.key, "height") end
    end
end
Bridge.PullMatchesToUs = PullMatchesToUs

-- Reset when the ticker stops, not left latched: frames appear in waves, so a
-- later batch publishes after this pass has already finished and its children
-- need a pass of their own.
local reapplyScheduled = false
local function ScheduleReapply()
    if reapplyScheduled then return end
    reapplyScheduled = true

    local tries = 0
    local ticker
    ticker = C_Timer.NewTicker(REAPPLY_INTERVAL, function()
        tries = tries + 1
        if AllPublishedFramesLaidOut() then
            ReapplyAnchorsToUs()
            ReapplyMatchesToUs()
            PullMatchesToUs()
            ticker:Cancel()
            reapplyScheduled = false
        elseif tries >= REAPPLY_MAX_TRIES then
            ticker:Cancel()
            reapplyScheduled = false
        end
    end)
end

local function PublishPending()
    local eui = EUI()
    if not eui then return end

    local batch = {}
    local stillPending = {}
    for _, entry in ipairs(pending) do
        local euiKey = KEY_PREFIX .. entry.config.key
        -- An already-published key is skipped: re-registering would rebuild
        -- this element's closures for no gain. Anchors pointing at it live in a
        -- separate store and are unaffected either way.
        if not published[euiKey] then
            if ResolveFrame(entry.config) then
                local element = BuildElement(entry.config, entry.opts)
                if element then
                    tinsert(batch, element)
                    published[euiKey] = true
                    tinsert(publishedConfigs, entry)
                end
            else
                tinsert(stillPending, entry)
            end
        end
    end

    pending = stillPending
    if #batch > 0 then
        eui:RegisterUnlockElements(batch, "KitnEssentials")
        ScheduleReapply()
    end
end

-- Whether EllesmereUI currently holds an unlock anchor for one of our elements,
-- named by the element's own key. An anchored element is positioned by its
-- center, so a module that lays itself out has to know: its own size changes
-- move both of its edges rather than growing from one. pcall because the query
-- belongs to another addon and a raise here would take the caller's layout with
-- it.
function Bridge:IsAnchored(key)
    local eui = EUI()
    if not eui or type(eui.IsAnchored) ~= "function" then return false end
    local ok, anchored = pcall(eui.IsAnchored, KEY_PREFIX .. key)
    return ok and anchored == true
end

function Bridge:Register(config, opts)
    if type(config) ~= "table" or not config.key then return end
    if type(config.getPosition) ~= "function" or type(config.setPosition) ~= "function" then return end
    if published[KEY_PREFIX .. config.key] then return end

    for _, entry in ipairs(pending) do
        if entry.config.key == config.key then return end
    end

    tinsert(pending, { config = config, opts = opts })
    PublishPending()
end

-- PLAYER_LOGIN as well as the entering-world pass: the map entry has to be in
-- place before anything can export or import a profile, and an installer runs
-- on the user's command well after login. Both handlers are idempotent.
local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:RegisterEvent("PLAYER_ENTERING_WORLD")
boot:SetScript("OnEvent", function()
    InjectProfileAddon()
    PublishPending()
end)
