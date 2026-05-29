-- ╔══════════════════════════════════════════════════════════╗
-- ║  TextureSnap.lua                                         ║
-- ║  Purpose: One-shot pixel-snap defeat for KE's OWN        ║
-- ║           textures (1px borders / overlays).            ║
-- ║                                                          ║
-- ║  KE:DisablePixelSnap(obj) turns off Blizzard's per-      ║
-- ║  texture pixel-grid snapping so KE's 1px borders render  ║
-- ║  crisply. Border helpers (Core/Widgets.lua) call it (or  ║
-- ║  SetSnapToPixelGrid(false) directly) at creation, and    ║
-- ║  re-assert it after any border recolor — SetColorTexture ║
-- ║  re-enables Blizzard's snap on the texture.              ║
-- ║                                                          ║
-- ║  HISTORY / DO-NOT-REGRESS:                                ║
-- ║  An earlier version (feat/pixel-perfect-overhaul, the    ║
-- ║  2026-05-27 merge) installed a GLOBAL metatable hook     ║
-- ║  ported verbatim from EllesmereUI: hooksecurefunc on     ║
-- ║  SetTexture / SetColorTexture / SetVertexColor /         ║
-- ║  SetTexCoord / SetStatusBarTexture / CreateTexture for   ║
-- ║  EVERY widget metatable in the game, plus an             ║
-- ║  EnumerateFrames walk. EUI is a full-UI replacement, so  ║
-- ║  it owns that cost. KE is a passenger module — the hook  ║
-- ║  made KE's closure run on every texture op by Blizzard   ║
-- ║  and every other addon, and recorded every game-wide     ║
-- ║  texture in a weak set. GetAddOnMemoryUsage bills the    ║
-- ║  on-stack addon, so KE was charged for the whole game's  ║
-- ║  texture churn: ~+8 MB at fresh /reload (5.9 → 13.8 MB)  ║
-- ║  and ~+2.3 s idle CPU. Confirmed by git-bisect reload    ║
-- ║  test (2026-05-28). Scoped back to KE's own textures.    ║
-- ║  DO NOT re-add the global metatable hook here.           ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)

local issecretvalue = _G.issecretvalue
local issecrettable = _G.issecrettable
local type = type

-- Disables Blizzard's per-texture pixel-grid snapping on `obj`. Safe against
-- tainted / forbidden frames (secret-value + IsForbidden guards). For
-- StatusBars (which don't expose SetSnapToPixelGrid directly) it targets the
-- inner status-bar texture instead. Idempotent — SetSnapToPixelGrid(false)
-- can be called repeatedly, so callers re-assert it freely after a recolor.
function KE:DisablePixelSnap(obj)
    if not obj then return end
    if issecretvalue and issecretvalue(obj) then return end
    if issecrettable and issecrettable(obj) then return end
    if obj.IsForbidden and obj:IsForbidden() then return end

    local target = obj
    if not obj.SetSnapToPixelGrid and obj.GetStatusBarTexture then
        target = obj:GetStatusBarTexture()
        if type(target) ~= "table" or not target.SetSnapToPixelGrid then
            return
        end
    end

    if target.SetSnapToPixelGrid then
        target:SetSnapToPixelGrid(false)
        target:SetTexelSnappingBias(0)
    end
end
