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
local C_Timer = C_Timer

-- Flip to true, /reload, then right-click a UNIT and hover a submenu. The log
-- answers the one thing source cannot: which branch of SkinFrame's
-- secret-dimension rescue a submenu frame actually takes.
local DEBUG_CM = false

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

-- The menu skin is four operations on the menu frame ITSELF:
-- StripTextures, CreateBackdrop + SetInside, HandleTrimScrollBar,
-- OffsetFrameLevel. Nothing else.
--
-- What we had on top, and why it's gone: WalkGlyphs recursed into the
-- menu's CHILD ENTRIES to re-brand radio ticks, running from inside
-- the menu system's acquired-frame callback. Those entries carry the
-- dropdown's selection -- and taint.log convicted exactly that value:
-- CurrencyTransferMenu.sourceCharacterData came back addon-owned, read at
-- CurrencyTransfer.lua, blocking
-- RequestCurrencyFromAccountCharacter. Never touch menu entries; a
-- working transfer beats brand-colored radial marks.
local function SkinFrame(frame)
    if not frame then return end
    local S = GetS()
    if not S then return end

    -- Menus opened from secure UnitPopup paths (right-click a unit frame)
    -- carry SECRET dimensions. Anchoring TOPLEFT+BOTTOMRIGHT makes our
    -- backdrop derive its size from theirs, so
    -- BackdropTemplateMixin:SetupTextureCoordinates reads a secret
    -- GetWidth() and dies at Backdrop.lua:
    --
    --   attempt to perform arithmetic on local 'width' (a secret number
    --   value, while execution tainted by an addon)
    --
    -- The size is therefore read BEFORE anything is created or anchored --
    -- S.Backdrop two-point anchors on creation, so checking afterwards would
    -- already be too late. A menu that will not give usable numbers simply
    -- goes unskinned; it keeps Blizzard's own look rather than erroring.
    local w, h = frame:GetWidth(), frame:GetHeight()
    if DEBUG_CM then
        -- tostring(frame) is the table address: the same address reappearing
        -- across menus is what proves pooling, which is the whole question here.
        KE:Print("[CM] SkinFrame " .. tostring(frame)
            .. " usableSize=" .. tostring(w ~= nil and h ~= nil
                and not KE:IsSecretValue(w) and not KE:IsSecretValue(h))
            .. " hasBackdrop=" .. tostring(backdrops[frame] ~= nil)
            .. " wasStripped=" .. tostring(stripped[frame] ~= nil))
    end
    if not w or not h or KE:IsSecretValue(w) or KE:IsSecretValue(h) then
        -- menu frames are POOLED. A frame stripped on an earlier
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
            if DEBUG_CM then
                KE:Print("[CM]   rescue A: reuse existing backdrop -> "
                    .. (stripped[frame] and "SHOW" or "HIDE"))
            end
            if stripped[frame] then existing:Show() else existing:Hide() end
        elseif stripped[frame] then
            -- Stripped on a previous use and pooled back with no backdrop
            -- of its own: build one now. Two-point anchoring is only
            -- unsafe because it makes OUR width derive from a secret one;
            -- SetAllPoints on a frame that is already ours to draw is the
            -- lesser evil against an invisible menu.
            local bd = S.Backdrop(frame)
            if DEBUG_CM then
                KE:Print("[CM]   rescue B: rebuild on stripped pooled frame -> bd="
                    .. tostring(bd ~= nil))
            end
            if bd then
                backdrops[frame] = bd
                ourFrames[bd] = true
                bd:Show()
            end
        elseif DEBUG_CM then
            -- The suspected submenu case: never skinned, never stripped, so
            -- nothing happens and Blizzard's own art should still be showing.
            -- If the submenu looks BARE here, the strip came from somewhere else.
            KE:Print("[CM]   rescue C: untouched frame, no action")
        end
        return
    end

    -- PRE-LAYOUT GUARD. A menu frame reports 1x1 until Blizzard
    -- has laid it out, and the acquired-frame callback can fire before that
    -- happens. Those numbers are READABLE -- just wrong -- so the secret-value
    -- test above cannot catch them, and every branch below trusts them.
    --
    -- Stripping on a 1x1 measurement is unrecoverable in one pass: the Blizzard
    -- art goes, our backdrop is built 1x1 and is invisible, and the menu then
    -- lays out to full size with its text drawn over nothing. That is exactly
    -- the submenu bug: an in-game log showed the root at 164x342 and the
    -- submenu at 1x1 in the same open.
    --
    -- Bailing WITHOUT stripping leaves Blizzard's own art in place, which looks
    -- correct. The deferral in OnMenuOpen is what actually gets these frames
    -- skinned; this guard is the backstop for anything that is still unlaid
    -- out a frame later. 16 is below any real menu (one row is ~20px tall) and
    -- far above the 1x1 default.
    if w < 16 or h < 16 then
        if DEBUG_CM then
            KE:Print("[CM]   PRE-LAYOUT skip (not stripped): w=" .. tostring(w)
                .. " h=" .. tostring(h))
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
    if DEBUG_CM then
        KE:Print("[CM]   SKINNED normally: w=" .. tostring(w) .. " h=" .. tostring(h)
            .. " bd=" .. tostring(bd ~= nil))
    end
end

local function OnMenuOpen(manager, _ownerRegion, menuDescription)
    local menu = manager and manager.GetOpenMenu and manager:GetOpenMenu()
    -- This marker is what separates ROOT from SUBMENU in the log: the first
    -- SkinFrame line after an OPEN is the root menu; every SkinFrame line after
    -- that with no intervening OPEN arrived through the acquired-frame
    -- callback, which is how submenus reach us.
    if DEBUG_CM then
        KE:Print("[CM] === OPEN === root=" .. tostring(menu ~= nil)
            .. " canRegisterAcquired="
            .. tostring(menuDescription ~= nil
                and menuDescription.AddMenuAcquiredCallback ~= nil))
    end
    if menu then SkinFrame(menu) end

    -- DEFERRED BY ONE FRAME. Acquired frames -- which is how
    -- SUBMENUS reach us -- arrive before Blizzard has laid them out, measuring
    -- 1x1. Skinning them synchronously stripped their art and built an
    -- invisible 1x1 backdrop; see the pre-layout guard in SkinFrame for the
    -- full diagnosis. C_Timer.After(0) puts the measurement one frame later,
    -- by which point the layout has run.
    --
    -- The root menu above is deliberately NOT deferred. It measures correctly
    -- today (164x342 in the diagnostic log) and deferring it would flash an
    -- unskinned menu for a frame. The guard covers it if that ever changes.
    if menuDescription and menuDescription.AddMenuAcquiredCallback then
        menuDescription:AddMenuAcquiredCallback(function(frame)
            C_Timer.After(0, function() SkinFrame(frame) end)
        end)
    end
end

function CM:Setup()
    if self._hooked then return true end
    local Menu = _G.Menu
    if not (Menu and Menu.GetManager) then return false end
    local manager = Menu.GetManager()
    if not manager then return false end

    -- A REVERTED experiment. The poller was built on a WRONG
    -- theory ("hooks inside a secure flow taint it"). They don't:
    -- hooksecurefunc is designed to be taint-safe -- the hook body
    -- runs with our taint, then execution returns to secure. Blizzard
    -- functions, this manager included, take thousands of such hooks
    -- with none of these errors. What taints is what a hook body
    -- WRITES, or replacing methods Blizzard calls (the real root).
    -- This skin only reads and sets visual state, so hooking
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
