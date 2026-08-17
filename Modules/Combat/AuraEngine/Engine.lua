-- ╔══════════════════════════════════════════════════════════╗
-- ║  Modules/Combat/AuraEngine/Engine.lua                    ║
-- ║  Purpose: the facade -- registration, events, settings   ║
-- ║  routing, and the display lifecycle every consumer uses. ║
-- ╚══════════════════════════════════════════════════════════╝

-- Rules is NOT in scope here otherwise: it is a local inside Rules.lua,
-- published only as KE.AuraRules.
local KE    = select(2, ...)
local Rules = KE.AuraRules

local math_floor = math.floor

local Engine = {}
KE.AuraEngine = Engine

local DEBUG_AE = false

-- Container.Create leaves the anchor at 0x0 -- every corner of a zero-size
-- frame coincides, so neither the pin nor the position math notices, but the
-- Edit Mode mover needs a real rectangle to grab.
local function SizeAnchor(display, settings)
    local cols = settings.IconsPerRow or display.defaultIconsPerRow
    local rows = settings.MaxRows or 1
    local w = cols * settings.IconSize + (cols - 1) * settings.IconSpacing
    local h = rows * settings.IconSize + (rows - 1) * settings.IconSpacing
    display.handle.anchorFrame:SetSize(w, h)
end

-- OWNER is the Ace3 module object, and it is not optional. AceEvent registers
-- against the owner it was embedded into, and CallbackHandler keys every
-- registration by that owner -- two displays sharing one owner would overwrite
-- each other's handlers for the same event. Edit Mode needs the same object
-- for its `module` field.
function Engine.Register(owner, declaration, getSettings)
    local display = {
        owner              = owner,
        key                = declaration.key,
        sortMethod         = declaration.sortMethod,
        groups             = declaration.groups,
        splitLimit         = declaration.splitLimit,
        buildPreview       = declaration.buildPreview,
        defaultIconsPerRow = declaration.defaultIconsPerRow,
        declaration        = declaration,
        getSettings        = getSettings,
        handle             = nil,
        vehicleDisabled    = false,
        previewActive      = false,
        editModeRegistered = false,
    }

    if declaration.sounds then
        display.sounds = KE.AuraSound.New({
            api = {
                Add    = C_UnitAuras.AddAuraSound,
                Remove = C_UnitAuras.RemoveAuraSound,
            },
            -- The `true` is load-bearing: without it LibSharedMedia returns
            -- its DEFAULT sound for an unknown key, and a user whose stored
            -- SoundName no longer exists would hear something rather than
            -- nothing.
            resolveMedia = function(name) return KE.LSM:Fetch("sound", name, true) end,
            isHidden     = function() return KE:AreAuraIdentitiesHidden() end,
            onDiagnostic = function(msg) if DEBUG_AE then KE:Print(msg) end end,
        })
    end

    display.gate = KE.AuraRestriction.New({
        soundIsPending = display.sounds
            and function() return display.sounds:IsPending() end
            or nil,
    })

    Engine.RegisterEvents(display)
    return display
end

---------------------------------------------------------------------------------
-- Events -- exactly five, and no aura event. Repainting on aura change is
-- entirely the container's job.
---------------------------------------------------------------------------------

function Engine.RegisterEvents(display)
    local owner = display.owner

    -- Two kinds can resolve to the SAME function, so a display owing both
    -- debts reapplies once. A fresh closure per firing is fine here: Drain
    -- only needs the two entries to be the same function within the one call
    -- it is given to.
    local function Reapply()
        local reapply = function() Engine.ApplySettings(display) end
        display.gate:Drain({ general = reapply, sound = reapply })
    end

    -- ADDON_RESTRICTION_STATE_CHANGED is the PRIMARY drain. Deferred one
    -- frame -- conservative, not proven necessary: the documented
    -- false-during-dispatch guarantee belongs to IsAddOnRestrictionActive,
    -- not to ShouldAurasBeSecret.
    owner:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED", function()
        C_Timer.After(0, Reapply)
    end)

    -- PLAYER_REGEN_ENABLED ends combat without ending a keystone, a raid
    -- encounter or a PvP match, so draining only on it would strand deferred
    -- work inside a key. It is a secondary retry, never the sole drain.
    owner:RegisterEvent("PLAYER_REGEN_ENABLED", Reapply)

    -- Entering a vehicle is already the answer, so the flag is set from the
    -- event itself without asking. UnitHasVehicleUI is unreliable around this
    -- event, which is why the exit handler below waits before querying it.
    --
    -- unitTarget is the event's first payload argument; AceEvent passes the
    -- event name first, so it arrives second in the handler. Both vehicle
    -- events fire for OTHER units too, so this filter is the only thing that
    -- stops a party member's vehicle from hiding this player's display.
    owner:RegisterEvent("UNIT_ENTERED_VEHICLE", function(_, unitTarget)
        if unitTarget ~= "player" then return end
        display.vehicleDisabled = true
        Engine.ApplyDisplayState(display, display.getSettings())
    end)

    owner:RegisterEvent("UNIT_EXITED_VEHICLE", function(_, unitTarget)
        if unitTarget ~= "player" then return end
        C_Timer.After(0.1, function()
            display.vehicleDisabled = UnitHasVehicleUI("player") or false
            Engine.ApplyDisplayState(display, display.getSettings())
        end)
    end)

    owner:RegisterEvent("PLAYER_ENTERING_WORLD", function()
        display.vehicleDisabled = UnitHasVehicleUI("player") or false
        Engine.ApplyDisplayState(display, display.getSettings())
    end)
end

---------------------------------------------------------------------------------
-- Settings routing -- the single entry point for any settings change.
---------------------------------------------------------------------------------

function Engine.ApplySettings(display)
    local settings = display.getSettings()

    -- Sound FIRST, and outside the gate. Retiring is never restricted and the
    -- design requires it to happen at once: changing the sound from A to B
    -- inside a key retires A now and registers B on release, and switching
    -- sound off inside a key retires everything now and pends nothing. Behind
    -- the gate, both of those would leave the old sound playing.
    Engine.SyncSound(display, settings)

    if not display.handle then
        -- First creation is PERMITTED while restricted. Only later
        -- reconfiguration defers.
        display.handle = KE.AuraContainer.Create(display, settings)
        SizeAnchor(display, settings)
        Engine.RegWithEditMode(display)
        Engine.ApplyDisplayState(display, settings)
        return
    end

    -- The PREVIEW is rebuilt before the gate, not after it. Opening the config
    -- inside a keystone is an ordinary thing to do, and the preview is plain
    -- frames the restriction does not touch -- so a deferred reconfiguration
    -- must still leave the user's preview matching the setting they just
    -- changed. Behind the gate, it would freeze until they left the key.
    if display.previewActive then
        KE.AuraPreview.Rebuild(display, settings)
    end

    if not display.gate:Request("general") then return end

    KE.AuraContainer.Reconfigure(display.handle, display, settings)
    SizeAnchor(display, settings)
    Engine.ApplyDisplayState(display, settings)
end

-- The live container stays HIDDEN while the preview is up, whatever the
-- computed state says. Without this, every settings change re-shows the real
-- display underneath the preview.
function Engine.ApplyDisplayState(display, settings)
    local state = Rules.ComputeState(settings.Enabled, display.vehicleDisabled)
    local shown = state.container and not display.previewActive
    KE.AuraContainer.ApplyState(display.handle, shown)
end

-- One synchronisation per call, and the only caller of Registry:Sync. It takes
-- the SOUND half of the state rule, which is the half a vehicle does not
-- suspend.
function Engine.SyncSound(display, settings)
    if not display.sounds then return end
    local state = Rules.ComputeState(settings.Enabled, display.vehicleDisabled)
    display.sounds:Sync(display.declaration.sounds, settings, state.sound)
end

---------------------------------------------------------------------------------
-- Enable / disable -- the ACE MODULE going inert, distinct from the module's
-- own Enabled setting that ComputeState reads.
---------------------------------------------------------------------------------

function Engine.SetModuleEnabled(display, enabled)
    if enabled then
        -- Re-enable is a reconfiguration like any other, so it goes through
        -- the gate and defers when restricted.
        Engine.ApplySettings(display)
        return
    end

    -- Sound registrations are Blizzard-side and entirely independent of the
    -- container; a disable that forgets them leaves the module audible after
    -- it is switched off. Retiring also clears the registry's own pending
    -- flag, which is the sound half of "cancel both pending flags".
    if display.sounds then
        display.sounds:RetireAll()
    end

    -- Hiding alone only unregisters the container's dynamic aura events and
    -- marks a rebuild -- it does not clear painted auras, so do not rely on
    -- it alone. ApplyState's SetEnabled(false) does the real work.
    if display.handle then
        KE.AuraContainer.ApplyState(display.handle, false)
    end

    -- Clears the general pending flag, so a later restriction release cannot
    -- resurrect work for a module the user switched off.
    display.gate:Cancel()
end

---------------------------------------------------------------------------------
-- Preview
---------------------------------------------------------------------------------

function Engine.ShowPreview(display)
    if display.previewActive then return end
    display.previewActive = true
    KE.AuraPreview.Enter(display.handle, display, display.getSettings())
end

function Engine.HidePreview(display)
    if not display.previewActive then return end
    display.previewActive = false
    local settings = display.getSettings()
    local state = Rules.ComputeState(settings.Enabled, display.vehicleDisabled)
    KE.AuraPreview.Exit(display.handle, display, settings, state.container)
end

---------------------------------------------------------------------------------
-- Edit Mode -- the mover and its hitbox.
---------------------------------------------------------------------------------

-- The container is sized to the grid, but the grid is pinned to the module's
-- anchor corner and grows from there, so a growth setting that opposes the
-- anchor slides every icon out of the frame. Every element anchors to a
-- BUTTON, so the host for a text inset is one icon square rather than the
-- container.
--
-- The dispel term is safe to include even for a display with no DispelPosition
-- setting: with both anchor points absent it centres against itself and nets
-- to zero, which is what the modules this engine replaces without a dispel
-- decoration already relied on.
local function GetOverlayInset(display, settings)
    local grid = { KE:GetGridOverlayInset(
        settings.IconsPerRow or display.defaultIconsPerRow,
        settings.MaxRows or 1,
        settings.IconSize,
        settings.IconSpacing,
        (settings.Position and settings.Position.AnchorFrom) or "CENTER",
        settings.GrowHorizontal == "LEFT",
        settings.GrowVertical == "UP"
    ) }

    -- An absent measurement leaves the element a point at its anchor, which
    -- still carries the offset and is a true lower bound.
    local icon = settings.IconSize or 0
    local extents = display.textExtents or {}
    local dispel = math_floor(icon * KE.AuraStyle.DISPEL_ICON_FRACTION)

    local function textInset(pos, role)
        if not pos then return { 0, 0, 0, 0 } end
        local e = extents[role] or {}
        return { KE:GetTextOverlayInset(pos.AnchorTo, pos.AnchorFrom,
            pos.XOffset, pos.YOffset, e.width, e.height, icon, icon) }
    end

    return KE:CombineOverlayInsets(grid, {
        textInset(settings.TimerPosition, "timer"),
        textInset(settings.StackPosition, "stack"),
        { KE:GetTextOverlayInset(
            settings.DispelPosition and settings.DispelPosition.AnchorTo,
            settings.DispelPosition and settings.DispelPosition.AnchorFrom,
            settings.DispelPosition and settings.DispelPosition.XOffset,
            settings.DispelPosition and settings.DispelPosition.YOffset,
            dispel, dispel, icon, icon) },
    })
end

-- Called once, at first creation. module = display.owner for the same reason
-- Register uses it for events: Edit Mode's `module` field must be the same
-- object CallbackHandler keys registrations by.
function Engine.RegWithEditMode(display)
    if not KE.EditMode or display.editModeRegistered then return end
    local decl = display.declaration

    KE.EditMode:RegisterElement({
        key         = display.key,
        module      = display.owner,
        displayName = decl.displayName,
        frame       = display.handle.anchorFrame,
        getPosition = function()
            return display.getSettings().Position
        end,
        setPosition = function(pos)
            local settings = display.getSettings()
            settings.Position = pos
            KE:ApplyFramePosition(display.handle.anchorFrame, settings.Position, settings)
        end,
        -- Read at call time: a value captured at registration goes stale the
        -- moment the user changes a growth direction.
        getOverlayInset = function()
            return GetOverlayInset(display, display.getSettings())
        end,
        getParentFrame = function()
            local settings = display.getSettings()
            return KE:ResolveAnchorFrame(settings.anchorFrameType, settings.ParentFrame)
        end,
        guiPath = decl.guiPath or display.key,
    })
    display.editModeRegistered = true
end
