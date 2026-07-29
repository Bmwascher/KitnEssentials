-- ╔══════════════════════════════════════════════════════════╗
-- ║  ContextMenus.lua                                        ║
-- ║  Module: ContextMenus                                    ║
-- ║  Purpose: Skins Blizzard right-click context menus.      ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)

if not KitnEssentials then
    error("ContextMenus: Addon object not initialized. Check file load order!")
    return
end

local CM = KitnEssentials:NewModule("ContextMenus", "AceEvent-3.0")

-- Skinning applies destructively at enable and OnDisable has no frame
-- teardown, same as the Skin* modules; the name doesn't match
-- ProfileManager's "^Skin" test, so opt in explicitly.
CM.keDeferToReload = true

local hooksecurefunc = hooksecurefunc
local ipairs = ipairs -- luacheck: ignore 211/ipairs
local math_max = math.max
local C_AddOns = C_AddOns

local backdrops = setmetatable({}, { __mode = "k" })
-- Frames whose Blizzard art we have removed. Weak-keyed: pooled menu
-- frames must not be held alive by this.
local stripped = setmetatable({}, { __mode = "k" })
local ourFrames = setmetatable({}, { __mode = "k" })


local function GetS()
    return KE.Skins
end

function CM:UpdateDB()
    self.db = KE.db.profile.Skinning.ContextMenus
end

-- v3.5.836: ElvUI-EXACT port of their menu skin
-- (ElvUI/Game/Mainline/Skins/Menu.lua). Theirs is four operations on
-- the menu frame ITSELF: StripTextures, CreateBackdrop + SetInside,
-- HandleTrimScrollBar, OffsetFrameLevel. Nothing else.
--
-- What we had on top, and why it's gone: WalkGlyphs recursed into the
-- menu's CHILD ENTRIES to re-brand radio ticks, running from inside
-- the menu system's acquired-frame callback. Those entries carry the
-- dropdown's selection -- and taint.log convicted exactly that value:
-- CurrencyTransferMenu.sourceCharacterData came back owned by
-- atrocityEssentials, read at CurrencyTransfer.lua:302, blocking
-- RequestCurrencyFromAccountCharacter at :403. ElvUI never touches
-- menu entries. Parity beats our brand-colored radial marks.
local function SkinFrame(frame)
    if not frame then return end
    local S = GetS()
    if not S then return end

    -- Menus opened from secure UnitPopup paths (right-click a unit frame)
    -- carry SECRET dimensions. Anchoring TOPLEFT+BOTTOMRIGHT makes our
    -- backdrop derive its size from theirs, so
    -- BackdropTemplateMixin:SetupTextureCoordinates reads a secret
    -- GetWidth() and dies at Backdrop.lua:226:
    --
    --   attempt to perform arithmetic on local 'width' (a secret number
    --   value, while execution tainted by 'atrocityEssentials')
    --
    -- The size is therefore read BEFORE anything is created or anchored --
    -- S.Backdrop two-point anchors on creation, so checking afterwards would
    -- already be too late. A menu that will not give usable numbers simply
    -- goes unskinned; it keeps Blizzard's own look rather than erroring.
    local w, h = frame:GetWidth(), frame:GetHeight()
    if not w or not h or KE:IsSecretValue(w) or KE:IsSecretValue(h) then
        -- v4.0.154: menu frames are POOLED. A frame stripped on an earlier
        -- (readable) menu comes back for a secret one, and hiding our
        -- backdrop then left it stripped AND unbacked -- text floating on
        -- the world with no panel, which is what the Target Marker Icon
        -- submenu was showing.
        --
        -- If we have already stripped this frame, its Blizzard art is gone
        -- and hiding ours is strictly worse than keeping it at its last
        -- known size. Only frames we have never touched are left alone.
        local existing = backdrops[frame]
        if existing then
            if stripped[frame] then existing:Show() else existing:Hide() end
        elseif stripped[frame] then
            -- Stripped on a previous use and pooled back with no backdrop
            -- of its own: build one now. Two-point anchoring is only
            -- unsafe because it makes OUR width derive from a secret one;
            -- SetAllPoints on a frame that is already ours to draw is the
            -- lesser evil against an invisible menu.
            local bd = S.Backdrop(frame)
            if bd then
                backdrops[frame] = bd
                ourFrames[bd] = true
                bd:Show()
            end
        end
        return
    end

    -- Stripped only once we know the menu can be skinned -- stripping and
    -- then bailing would leave it with no background at all.
    S.StripTextures(frame)
    stripped[frame] = true

    local bd = backdrops[frame]
    if not bd then
        bd = S.Backdrop(frame)
        if bd then
            backdrops[frame] = bd
            ourFrames[bd] = true
            if frame.ScrollBar then S.TrimScrollBar(frame.ScrollBar) end
        end
    end

    -- Explicit size, not a BOTTOMRIGHT anchor: the geometry stays ours even
    -- if the menu's own dimensions turn secret later in the session.
    if bd then
        bd:ClearAllPoints()
        bd:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
        bd:SetSize(math_max(w - 2, 1), math_max(h - 2, 1))
    end

    if bd then
        local lvl = (frame.GetFrameLevel and frame:GetFrameLevel()) or 1
        bd:SetFrameLevel(math_max(lvl - 1, 0))
        bd:Show()
    end
end

local function OnMenuOpen(manager, _ownerRegion, menuDescription)
    local menu = manager and manager.GetOpenMenu and manager:GetOpenMenu()
    if menu then SkinFrame(menu) end

    if menuDescription and menuDescription.AddMenuAcquiredCallback then
        menuDescription:AddMenuAcquiredCallback(SkinFrame)
    end
end

function CM:Setup()
    if self._hooked then return true end
    local Menu = _G.Menu
    if not (Menu and Menu.GetManager) then return false end
    local manager = Menu.GetManager()
    if not manager then return false end

    -- v3.5.834 REVERT of v3.5.833. The poller was built on a WRONG
    -- theory ("hooks inside a secure flow taint it"). They don't:
    -- hooksecurefunc is designed to be taint-safe -- the hook body
    -- runs with our taint, then execution returns to secure. ElvUI
    -- hooks thousands of Blizzard functions, this manager included,
    -- with none of these errors. What taints is what a hook body
    -- WRITES, or replacing methods Blizzard calls (the real v828
    -- root). This skin only reads and sets visual state, so hooking
    -- is correct here -- and menus skin instantly again.
    hooksecurefunc(manager, "OpenMenu", OnMenuOpen)
    hooksecurefunc(manager, "OpenContextMenu", OnMenuOpen)
    self._hooked = true
    return true
end

function CM:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

function CM:OnEnable()
    if KE:ShouldNotLoadModule() then return end
    if not self.db.Enabled then return end

    if not self:Setup() then
        if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Blizzard_Menu") then
            return
        end
        self:RegisterEvent("ADDON_LOADED", function(_, name)
            if name == "Blizzard_Menu" then
                if self:Setup() then self:UnregisterEvent("ADDON_LOADED") end
            end
        end)
    end
end

function CM:ApplySettings()
    if KE:ShouldNotLoadModule() then return end
    if self.db.Enabled then self:Setup() end
end
