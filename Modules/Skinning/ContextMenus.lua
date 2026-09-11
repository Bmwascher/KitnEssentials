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

-- Flip to true, /reload, then right-click a unit and hover a submenu. The log
-- shows every frame that reaches SkinFrame, whether its backdrop was reused
-- (a pooled frame coming back) and the size the backdrop is tracking.
local DEBUG_CM = false

-- Weak-keyed: menu frames are pooled and must not be held alive by us.
local backdrops = setmetatable({}, { __mode = "k" })
local ourFrames = setmetatable({}, { __mode = "k" })


local function GetS()
    return KE.Skins
end

function CM:UpdateDB()
    self.db = KE.db.profile.Skinning.ContextMenus
end

-- The inset is asked for, not guessed: MenuProxyMixin lays its own content
-- out from frame:GetInset() (InitScrollLayout / PerformLayout), so that is
-- where the panel belongs at any scale. A submenu anchors its TOPLEFT to its
-- parent ROW's TOPRIGHT (GenerateSubmenuInternal), and the row ends one
-- right-inset short of the parent menu's edge, so the two frames overlap;
-- EXTRA_X pulls both x edges in further to narrow that overlap.
--   INSET_SHARE  how much of the menu's own margin to keep (1 = hug the text,
--                0 = Blizzard's full margin)
--   PAD          extra room on every side, on top of that
--   EXTRA_X      extra x-inset on top of that, per panel
local INSET_SHARE = 0.5
local PAD = 2
local EXTRA_X = 1.5
local FALLBACK_X, FALLBACK_Y = 2, 2

local function Inset(value, extra)
    return math_max((value or 0) * INSET_SHARE - PAD + (extra or 0), 0)
end

local function GetInsets(frame)
    if frame.GetInset then
        local ok, inset = pcall(frame.GetInset, frame)
        if ok and type(inset) == "table"
            and not KE:IsSecretValue(inset.left) and not KE:IsSecretValue(inset.top) then
            return Inset(inset.left, EXTRA_X), Inset(inset.top),
                   Inset(inset.right, EXTRA_X), Inset(inset.bottom)
        end
    end
    return FALLBACK_X, FALLBACK_Y, FALLBACK_X, FALLBACK_Y
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

    S.StripTextures(frame)

    -- Relink rather than rebuild: menu frames are POOLED, and a frame
    -- already skinned comes back for a different menu.
    local reused = backdrops[frame] ~= nil
    local bd = backdrops[frame]
    if not bd then
        bd = S.Backdrop(frame)
        if bd then
            backdrops[frame] = bd
            ourFrames[bd] = true
            if frame.ScrollBar then S.TrimScrollBar(frame.ScrollBar) end
        end
    end
    if not bd then return end

    -- Two-point anchoring: the backdrop takes its size from the menu, so
    -- nothing here measures a pooled frame before Blizzard has relaid it out.
    -- A menu opened from a secure path has secret dimensions, which the
    -- backdrop then inherits; S.Backdrop's per-instance
    -- SetupTextureCoordinates returns early on an unreadable size, so that
    -- is safe.
    local left, top, right, bottom = GetInsets(frame)
    bd:ClearAllPoints()
    bd:SetPoint("TOPLEFT", frame, "TOPLEFT", left, -top)
    bd:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -right, bottom)

    local lvl = (frame.GetFrameLevel and frame:GetFrameLevel()) or 1
    bd:SetFrameLevel(math_max(lvl - 1, 0))
    bd:Show()

    if DEBUG_CM then
        -- tostring(frame) is the table address: the same address reappearing
        -- across menus is what proves pooling.
        local w, h = frame:GetWidth(), frame:GetHeight()
        local function show(v) return KE:IsSecretValue(v) and "secret" or tostring(v) end
        KE:Print("[CM] SkinFrame " .. tostring(frame) .. (reused and " reused" or " new")
            .. " size=" .. show(w) .. "x" .. show(h)
            .. " inset=" .. left .. "," .. top .. "," .. right .. "," .. bottom)
    end
end

local function OnMenuOpen(manager, _ownerRegion, menuDescription)
    local menu = manager and manager.GetOpenMenu and manager:GetOpenMenu()
    -- The first SkinFrame line after an OPEN is the root menu; every later one
    -- with no intervening OPEN arrived through the acquired-frame callback,
    -- which is how submenus reach us.
    if DEBUG_CM then
        KE:Print("[CM] === OPEN === root=" .. tostring(menu ~= nil))
    end
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
