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

local function BuildElement(config, opts)
    local eui = EUI()
    if not eui then return nil end

    local euiKey = KEY_PREFIX .. config.key
    local isHidden = opts and opts.isHidden

    return eui.MakeUnlockElement({
        key   = euiKey,
        label = (opts and opts.label) or config.displayName or config.key,
        group = (opts and opts.group) or DEFAULT_GROUP,
        order = (opts and opts.order) or DEFAULT_ORDER,

        -- Size belongs to the module's own option sliders. A drag-resize handle
        -- would fight them, so movers are position-only. noAnchorTo and
        -- noAnchorTarget are deliberately NOT set: being an anchor target is the
        -- whole reason for registering.
        noResize = true,

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
                -- parent's centre, so lift its pair into that space first.
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
            pcall(eui.ReapplyUnlockAnchor, childKey)
        end
    end
end

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
