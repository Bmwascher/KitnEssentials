-- ╔══════════════════════════════════════════════════════════╗
-- ║  TooltipStatusBar.lua                                    ║
-- ║  Purpose: Skins the progress bars that appear inside     ║
-- ║           tooltips (reputation, experience).             ║
-- ║  Owner: SkinTooltips calls the installer from OnEnable.  ║
-- ║  The reference dispatches this through its always-on     ║
-- ║  skin engine; KE's equivalent dispatch is gated on the   ║
-- ║  separate Blizzard Frames toggle, so it would never fire ║
-- ║  for a user who only enabled tooltips.                   ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local S = KE.Skins
local _G = _G
local hooksecurefunc = hooksecurefunc

local function SkinBar(bar)
    -- Ported verbatim, including the ordering quirk: this sets `skinned`
    -- before S.StatusBar runs, and S.StatusBar early-returns on that flag,
    -- so its backdrop call is dead. That is upstream's behaviour and the
    -- look this port is matching. Do not "fix" it.
    if S.data(bar).skinned then return end
    S.data(bar).skinned = true
    S.StripTextures(bar)
    S.StatusBar(bar)
    S.ProgressFill(bar)
end

-- hooksecurefunc closures can never be removed, so a second install would
-- stack a permanent duplicate layer. Once per session, whatever happens.
local installed = false

function S.InstallTooltipStatusBarHook()
    if installed then return end
    -- ElvUI's approach restored -- they SecureHook
    -- GameTooltip_ShowStatusBar to skin status bars. My v831 event
    -- driver came from the "hooks in a flow taint it" theory, which
    -- ElvUI disproves at scale. The real LootHistory seed was
    -- KillTexture surgery (fixed v838).
    if not _G.GameTooltip_ShowStatusBar then return end
    installed = true
    hooksecurefunc("GameTooltip_ShowStatusBar", function(tooltip)
        -- Every permanent hook in the tooltip skin gates on TT:IsEnabled(),
        -- because disabled must mean inert. This hook is permanent too, so it
        -- carries the same gate.
        local TT = KitnEssentials:GetModule("SkinTooltips", true)
        if not (TT and TT:IsEnabled()) then return end
        local pool = tooltip and tooltip.statusBarPool
        if not pool or not pool.EnumerateActive then return end
        for bar in pool:EnumerateActive() do
            SkinBar(bar)
        end
    end)
end
