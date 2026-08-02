-- ╔══════════════════════════════════════════════════════════╗
-- ║  CompareHeader.lua                                       ║
-- ║  Module: Compare Header                                  ║
-- ║  Purpose: Style the "Equipped" header on item comparison ║
-- ║           tooltips so it matches the rest of the tooltip ║
-- ║           skin instead of keeping Blizzard's art.        ║
-- ║                                                          ║
-- ║  Taint safety: this styles the header's own FRAME        ║
-- ║  REGIONS once, at enable time. It never runs inside a    ║
-- ║  tooltip build hook and never touches tooltip TEXT --    ║
-- ║  the reference's earlier text-mutating version tainted   ║
-- ║  the tooltip system and was replaced by exactly this.    ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class CompareHeader: AceModule
local CH = KitnEssentials:NewModule("CompareHeader")

local _G = _G
local ipairs = ipairs

-- The module name does not match the ^Skin test, and the style is applied
-- once with no teardown, so turning it off has to prompt for a reload the
-- way the Skin* siblings do.
CH.keDeferToReload = true

local function StyleHeader(tt)
    local S = KE.Skins
    if not (CH.active and tt and S) then return end
    local header = tt.CompareHeader
    if not header or S.data(header).skinned then return end
    S.StripTextures(header)
    S.Backdrop(header)
    S.data(header).skinned = true
end

-- A PRIVATE lifecycle table, deliberately not the saved tooltip block.
--
-- Both of KE's lifecycle passes read `module.db.Enabled` and do nothing at
-- all for a module that does not publish one: the startup enable loop
-- (Core/Main.lua:169-178) and the profile-switch sync
-- (Core/ProfileManager.lua:449-475, where `wantEnabled ~= nil` gates the
-- whole comparison). This module's real setting lives inside the tooltip
-- block, so it publishes an effective flag here and mirrors `active` into it.
-- NEVER write this back into the saved profile -- it is a lifecycle mirror,
-- not a setting.
CH.db = { Enabled = false }

function CH:UpdateDB()
    -- Same block the tooltip page reads (GUI/GUITabs/GUISkinning/GUI-Tooltips.lua:50).
    --
    -- Gated on the tooltip module's own Enabled as well as our setting. The
    -- page returns right after its master toggle when tooltip skinning is off
    -- (GUI-Tooltips.lua:152-154), so our checkbox is unreachable in that
    -- state; without this second condition the module would keep styling with
    -- no control the user can see. The reference had a standalone toggle and
    -- so had no such coupling -- this follows from KE's placement, not from
    -- the port.
    local skin = KE.db and KE.db.profile and KE.db.profile.Skinning
    local db = skin and skin.Tooltips
    self.active = (db and db.Enabled == true and db.CompareHeader == true) and true or false
    self.db.Enabled = self.active
end

-- ElvUI styles this same header itself, so KE stands down when ElvUI owns
-- skinning. With the published flag above, both lifecycle passes DO cover
-- this module and both already skip it under ElvUI via `keDeferToReload`.
-- This explicit check is belt-and-braces on the paths that reach OnEnable
-- and ApplySettings directly -- the GUI callback, for one, which no
-- lifecycle pass mediates.
local function Suppressed()
    return KE.ShouldNotLoadModule and KE:ShouldNotLoadModule() and true or false
end

function CH:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState((self.active and not Suppressed()) and true or false)
end

function CH:OnEnable()
    self:UpdateDB()
    if Suppressed() then return end
    if not self.active then return end
    -- The four headers are static frames, created at login and reused, so a
    -- one-time pass needs no per-show re-apply. The delayed second pass
    -- covers a shopping tooltip whose header is built lazily on first use.
    local function StyleAll()
        for _, base in ipairs({ "ShoppingTooltip", "ItemRefShoppingTooltip" }) do
            for i = 1, 2 do
                StyleHeader(_G[base .. i])
            end
        end
    end
    StyleAll()
    if _G.C_Timer then
        _G.C_Timer.After(2, StyleAll)
    end
end

function CH:ApplySettings()
    self:UpdateDB()
    if Suppressed() then
        if self:IsEnabled() then self:Disable() end
        return
    end
    if self.active then
        if not self:IsEnabled() then self:Enable() end
        self:OnEnable()
    else
        if self:IsEnabled() then self:Disable() end
    end
end
