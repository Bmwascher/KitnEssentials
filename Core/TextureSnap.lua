-- ╔══════════════════════════════════════════════════════════╗
-- ║  TextureSnap.lua                                         ║
-- ║  Purpose: Global texture-snap defeat via metatable       ║
-- ║           hooks. Ports the pattern from EllesmereUI      ║
-- ║           (EllesmereUI.lua:1090-1184).                   ║
-- ║                                                          ║
-- ║  WoW re-enables SetSnapToPixelGrid on every texture      ║
-- ║  property change (SetTexture/SetColorTexture/etc.).      ║
-- ║  This file hooks those methods on every widget metatable ║
-- ║  so KE:DisablePixelSnap calls survive Blizzard's resets. ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)

local issecretvalue = _G.issecretvalue
local issecrettable = _G.issecrettable

-- Weak-keyed set of objects we've disabled. Tracking it outside the
-- object's own table avoids tainting Blizzard's secure widget tables.
local _pixelSnapDisabled = setmetatable({}, { __mode = "k" })
KE._pixelSnapDisabled = _pixelSnapDisabled

-- Disables Blizzard's per-texture pixel-grid snapping on `obj` and
-- records that we did so in the weak-keyed set. Safe against tainted
-- and forbidden frames.
function KE:DisablePixelSnap(obj)
    if not obj then return end
    if issecretvalue and issecretvalue(obj) then return end
    if issecrettable and issecrettable(obj) then return end
    if _pixelSnapDisabled[obj] then return end
    if obj.IsForbidden and obj:IsForbidden() then return end

    local target = obj
    if not obj.SetSnapToPixelGrid and obj.GetStatusBarTexture then
        target = obj:GetStatusBarTexture()
        if type(target) ~= "table" or not target.SetSnapToPixelGrid then
            _pixelSnapDisabled[obj] = true
            return
        end
    end

    if target.SetSnapToPixelGrid then
        target:SetSnapToPixelGrid(false)
        target:SetTexelSnappingBias(0)
    end
    _pixelSnapDisabled[obj] = true
end

-- When Blizzard re-enables snap on a tracked object, drop it from the
-- set so the next DisablePixelSnap call re-applies cleanly.
local function WatchPixelSnap(frame, snap)
    if issecrettable and issecrettable(frame) then return end
    if (frame and not frame:IsForbidden()) and _pixelSnapDisabled[frame] and snap then
        _pixelSnapDisabled[frame] = nil
    end
end

local _hookedMetatables = {}
local function HookPixelSnap(object)
    local mk = getmetatable(object)
    if not mk then return end
    mk = mk.__index
    if not mk or _hookedMetatables[mk] then return end

    if mk.SetSnapToPixelGrid or mk.SetStatusBarTexture or mk.SetColorTexture
       or mk.SetVertexColor or mk.CreateTexture or mk.SetTexCoord or mk.SetTexture then
        if mk.SetSnapToPixelGrid then hooksecurefunc(mk, "SetSnapToPixelGrid", WatchPixelSnap) end
        if mk.SetStatusBarTexture then hooksecurefunc(mk, "SetStatusBarTexture", function(o) KE:DisablePixelSnap(o) end) end
        if mk.SetColorTexture then hooksecurefunc(mk, "SetColorTexture", function(o) KE:DisablePixelSnap(o) end) end
        if mk.SetVertexColor then hooksecurefunc(mk, "SetVertexColor", function(o) KE:DisablePixelSnap(o) end) end
        -- CreateTexture hook receives the *parent Frame* (the receiver), not the
        -- new Texture (which is the return value, invisible to hooksecurefunc).
        -- The new Texture gets snap-disabled when its SetTexture/SetColorTexture
        -- fires (which happens immediately after creation in real callers). This
        -- hook is effectively redundant — kept to match EUI's reference verbatim.
        if mk.CreateTexture then hooksecurefunc(mk, "CreateTexture", function(o) KE:DisablePixelSnap(o) end) end
        if mk.SetTexCoord then hooksecurefunc(mk, "SetTexCoord", function(o) KE:DisablePixelSnap(o) end) end
        if mk.SetTexture then hooksecurefunc(mk, "SetTexture", function(o) KE:DisablePixelSnap(o) end) end
        _hookedMetatables[mk] = true
    end
end

-- Hook all known widget types by creating one of each and hooking its metatable
local hookFrame = CreateFrame("Frame")
HookPixelSnap(hookFrame)
HookPixelSnap(hookFrame:CreateTexture())
HookPixelSnap(hookFrame:CreateFontString())
HookPixelSnap(hookFrame:CreateMaskTexture())

-- Enumerate existing frame types to catch any we missed
local hookedTypes = { Frame = true }
local enumObj = EnumerateFrames()
while enumObj do
    local objType = enumObj:GetObjectType()
    if not enumObj:IsForbidden() and not hookedTypes[objType] then
        HookPixelSnap(enumObj)
        hookedTypes[objType] = true
    end
    enumObj = EnumerateFrames(enumObj)
end

-- ScrollFrame + StatusBar metatables aren't always enumerable above
HookPixelSnap(CreateFrame("ScrollFrame"))
do
    local sb = CreateFrame("StatusBar")
    sb:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    HookPixelSnap(sb)
    local sbt = sb:GetStatusBarTexture()
    if sbt then HookPixelSnap(sbt) end
end
