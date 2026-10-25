-- ╔══════════════════════════════════════════════════════════╗
-- ║  PlateAnchor.lua                                         ║
-- ║  Purpose: the health bar a nameplate addon draws, to     ║
-- ║           anchor icons beside. Shared by the trash       ║
-- ║           timers and the Interrupt Tracker.              ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)

local type = type
local UIParent = UIParent
local WorldFrame = WorldFrame
local C_AddOns = C_AddOns

local function isAddonActive(name)
    return (C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(name)) or false
end

-- Resolve the real health-bar widget to anchor icons beside. The C_NamePlate
-- "plate" is a tall frame; anchoring to it floats icons at plate center, so we
-- probe for the actual bar across the supported nameplate addons and skip any
-- frame that's hidden/detached/forbidden (each replacement addon disables the
-- others' bar rather than removing it). Do NOT simplify: the ordering and the
-- visibility guard are exactly what make Plater / Platynator / Blizzard all
-- resolve correctly.
--   • Platynator replaces UnitFrame with its own widget tree → child-walk probe.
--   • Plater draws its own lowercase plate.unitFrame.healthBar and DETACHES the
--     Blizzard HealthBarsContainer → the lowercase bar wins, and we only trust
--     HealthBarsContainer when Plater is NOT driving plates (PlateColor keeps it).
--   • Blizzard default → plate.UnitFrame.healthBar. Anything hidden falls through
--     to the plate itself (graceful center-anchor) rather than an invisible frame.
function KE:ResolvePlateAnchor(plate)
    if type(plate) ~= "table" then return nil end

    -- Usable only if a real, non-forbidden, visible frame whose parent chain
    -- reaches this plate / UIParent / WorldFrame (rejects reparented-offscreen
    -- bars that replacement addons leave behind).
    local function isUsable(obj)
        if not obj or type(obj.GetObjectType) ~= "function" then return false end
        if obj.IsForbidden and obj:IsForbidden() then return false end
        if obj.IsVisible and not obj:IsVisible() then return false end
        local current = obj
        for _ = 1, 8 do
            if not current or type(current.GetParent) ~= "function" then break end
            current = current:GetParent()
            if not current then break end
            if current == plate or current == UIParent or current == WorldFrame then return true end
            if current.IsForbidden and current:IsForbidden() then return false end
            if current.IsShown and not current:IsShown() then return false end
        end
        return true
    end

    -- Platynator: a plate child carrying .widgets + .AurasManager; the health
    -- widget inside has details.kind == "health" and a .statusBar. Gated on the
    -- addon being loaded so non-Platynator users skip the GetChildren() table
    -- allocation on every per-tick plate resolve (its tree can't exist anyway).
    local function findPlatynatorAnchor()
        if not isAddonActive("Platynator") then return nil end
        if type(plate.GetChildren) ~= "function" then return nil end
        local children = { plate:GetChildren() }
        for i = 1, #children do
            local child = children[i]
            if isUsable(child) and child.widgets and child.AurasManager then
                if type(child.GetChildren) == "function" then
                    local widgets = { child:GetChildren() }
                    for j = 1, #widgets do
                        local widget = widgets[j]
                        local details = widget and widget.details
                        if isUsable(widget) and type(details) == "table"
                            and details.kind == "health" and widget.statusBar then
                            return widget
                        end
                    end
                end
                return child
            end
        end
        return nil
    end

    -- EUI (EllesmereUI Nameplates): best-effort.
    -- EUI parents its own plate as a child of the Blizzard nameplate and hides
    -- the default bar, exposing no public accessor; per its source that child
    -- carries a .health StatusBar and a .cast bar. Safe fallback: if this misses
    -- we drop through to the plate center, so verify placement in-game.
    local function findEUIAnchor()
        if not isAddonActive("EllesmereUINameplates") then return nil end
        if type(plate.GetChildren) ~= "function" then return nil end
        local children = { plate:GetChildren() }
        for i = 1, #children do
            local child = children[i]
            if isUsable(child) and child.health and child.cast
                and type(child.health.GetObjectType) == "function" and isUsable(child.health) then
                return child.health
            end
        end
        return nil
    end

    local anchor = findPlatynatorAnchor() or findEUIAnchor()
    if anchor then return anchor end

    -- HealthBarsContainer is a Blizzard field; Plater detaches/hides it, so only
    -- trust it when Plater isn't driving plates (PlateColor keeps it valid).
    if isAddonActive("PlateColor") or not isAddonActive("Plater") then
        local uf = plate.UnitFrame or plate.unitFrame
        if uf and uf.HealthBarsContainer and isUsable(uf) then return uf end
    end

    local candidates = {
        plate.unitFrame and plate.unitFrame.healthBar,   -- Plater (its own bar)
        plate.UnitFrame and plate.UnitFrame.healthBar,   -- Blizzard default
        plate.unitFrame and plate.unitFrame.HealthBar,
        plate.UnitFrame and plate.UnitFrame.HealthBar,
        plate.unitFrame,
        plate.UnitFrame,
    }
    for i = 1, #candidates do
        if isUsable(candidates[i]) then return candidates[i] end
    end

    return plate
end
