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

local pending = {}   -- configs handed over before EUI or the frame was ready
local published = {}        -- euiKey -> true, so a re-register is a no-op
local publishedConfigs = {} -- list of { config = ..., opts = ... }, never pruned

local function EUI()
    local eui = _G.EllesmereUI
    if not eui then return nil end
    if not (eui.RegisterUnlockElements and eui.MakeUnlockElement) then return nil end
    return eui
end

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
            config.setPosition(Bridge.FromEUIPosition(point, relPoint, x, y))
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

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_ENTERING_WORLD")
boot:SetScript("OnEvent", function()
    PublishPending()
end)
