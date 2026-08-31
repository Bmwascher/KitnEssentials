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
local math_ceil  = math.ceil

local Engine = {}
KE.AuraEngine = Engine

local DEBUG_AE = false

-- Enforces the invariant the comment below documents: keyed on the owner
-- object itself (weak so a module's teardown does not pin it), so a second
-- Register call reusing the same Ace3 owner is caught immediately instead of
-- silently overwriting the first display's event handlers.
local ownerDisplays = setmetatable({}, { __mode = "k" })

-- OWNER is the Ace3 module object, and it is not optional. AceEvent registers
-- against the owner it was embedded into, and CallbackHandler keys every
-- registration by that owner -- two displays sharing one owner would overwrite
-- each other's handlers for the same event. Edit Mode needs the same object
-- for its `module` field.
function Engine.Register(owner, declaration, getSettings)
    if ownerDisplays[owner] then
        error("AuraEngine.Register: owner is already registered to display '"
            .. tostring(ownerDisplays[owner]) .. "'", 2)
    end
    ownerDisplays[owner] = declaration.key

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

-- A module the user switched off never runs OnEnable, so it never calls
-- Register and owns no display at all. The preview manager still calls
-- HidePreview on it whenever a config page changes -- that branch is not
-- gated on the Enabled setting the way the show branch is -- so a nil display
-- reaches these entry points on the ordinary path, not an exotic one. The
-- handle guards below sit one level too deep to catch it.
local function NoDisplay(display)
    return display == nil
end

function Engine.RegisterEvents(display)
    if NoDisplay(display) then return end

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

    -- Two policies. The default SUSPENDS the display, which is right for a
    -- tracker whose subject is the fight rather than the player. A display of
    -- the player's own auras instead FOLLOWS the player into the seat, which
    -- is what the vehicle unit token is for.
    local function ApplyVehicle(inVehicle)
        if display.declaration.vehiclePolicy == "follow" then
            if display.handle then
                KE.AuraContainer.SetUnit(display.handle, inVehicle and "vehicle" or "player")
            end
            return
        end
        display.vehicleDisabled = inVehicle
        Engine.ApplyDisplayState(display, display.getSettings())
    end

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
        ApplyVehicle(true)
    end)

    owner:RegisterEvent("UNIT_EXITED_VEHICLE", function(_, unitTarget)
        if unitTarget ~= "player" then return end
        C_Timer.After(0.1, function()
            ApplyVehicle(UnitHasVehicleUI("player") or false)
        end)
    end)

    owner:RegisterEvent("PLAYER_ENTERING_WORLD", function()
        ApplyVehicle(UnitHasVehicleUI("player") or false)
    end)
end

---------------------------------------------------------------------------------
-- Settings routing -- the single entry point for any settings change.
---------------------------------------------------------------------------------

function Engine.ApplySettings(display)
    if NoDisplay(display) then return end

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
        Engine.RegWithEditMode(display)

        -- A reload inside a vehicle would otherwise come up on the player's
        -- own auras until the next vehicle event, which may never arrive.
        if display.declaration.vehiclePolicy == "follow" and UnitHasVehicleUI("player") then
            KE.AuraContainer.SetUnit(display.handle, "vehicle")
        end

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
    Engine.ApplyDisplayState(display, settings)

    -- The overlay box is computed from these settings and is only
    -- recomputed on request, so it would otherwise keep the previous
    -- dimensions until something unrelated refreshed it.
    if KE.EditMode then KE.EditMode:RefreshLiveState() end
end

-- The live container stays HIDDEN while the preview is up, whatever the
-- computed state says. Without this, every settings change re-shows the real
-- display underneath the preview.
function Engine.ApplyDisplayState(display, settings)
    -- The five registered events fire from login and every zone change
    -- whether or not the module has ever created a container -- OnEnable
    -- (and with it Container.Create) never runs for a module the user has
    -- switched off, so display.handle stays nil for the display's entire
    -- lifetime in that case. Same guard as SetModuleEnabled's disable branch
    -- and Preview.Enter/Exit.
    if not display.handle then return end

    local state = Rules.ComputeState(settings.Enabled, display.vehicleDisabled)
    local container = state.container and not display.previewActive

    -- The anchor is a SEPARATE decision from the container. Preview frames are
    -- its children and it carries the mover and the position the user is
    -- editing, so while a preview is up it stays shown whatever the container
    -- does -- which is exactly what Preview.PlanEnter already specifies.
    local anchor = display.previewActive or container

    KE.AuraContainer.ApplyState(display.handle, container, anchor)
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
    if NoDisplay(display) then return end

    if enabled then
        -- AceEvent's OnEmbedDisable calls owner:UnregisterAllEvents() on
        -- every Ace module disable, and AceEvent declares no OnEmbedEnable to
        -- undo that -- so re-enable must re-register explicitly or the
        -- display goes deaf for the rest of the session. Safe to repeat:
        -- CallbackHandler-1.0 keys each registration by owner+event, so a
        -- second RegisterEvent call overwrites the closure rather than
        -- stacking a duplicate.
        Engine.RegisterEvents(display)
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

    -- The preview's ticker is plain Lua, not a container event registration,
    -- so it keeps firing against hidden frames for the rest of the session
    -- unless the preview is explicitly exited here.
    if display.previewActive then
        Engine.HidePreview(display)
    end

    -- Hiding alone only unregisters the container's dynamic aura events and
    -- marks a rebuild -- it does not clear painted auras, so do not rely on
    -- it alone. ApplyState's SetEnabled(false) does the real work. Applied
    -- unconditionally after HidePreview, whose own plan may otherwise have
    -- left the container shown.
    if display.handle then
        KE.AuraContainer.ApplyState(display.handle, false, false)
    end

    -- Clears the general pending flag, so a later restriction release cannot
    -- resurrect work for a module the user switched off. Also discards
    -- whatever HidePreview just recorded above -- correct, since the module
    -- is off and owes nothing.
    display.gate:Cancel()
end

---------------------------------------------------------------------------------
-- Preview
---------------------------------------------------------------------------------

function Engine.ShowPreview(display)
    if NoDisplay(display) then return end

    -- A module never OnEnable'd (switched off) has no handle, and
    -- Preview.Enter already refuses a nil handle -- but flagging the preview
    -- active first would wedge the display: the flag says a preview is up,
    -- so ApplyDisplayState keeps the live container hidden, and no preview
    -- exists to show in its place.
    if display.previewActive or not display.handle then return end
    display.previewActive = true
    KE.AuraPreview.Enter(display.handle, display, display.getSettings())
end

function Engine.HidePreview(display)
    if NoDisplay(display) then return end
    if not display.previewActive then return end
    display.previewActive = false
    local settings = display.getSettings()
    local state = Rules.ComputeState(settings.Enabled, display.vehicleDisabled)
    local plan = KE.AuraPreview.Exit(display.handle, display, settings, state.container)

    -- Preview.Exit deliberately does not register the debt it plans --
    -- Request may only be called once, exactly here, by the caller that owns
    -- the gate. isHidden() is still true in this window when the plan says
    -- pendGeneral, so Request's restricted branch is the one that fires: it
    -- SETS the flag and returns false, rather than its unrestricted branch,
    -- which would clear one. ApplySettings records the same flag at change
    -- time, so this is a deliberate second record for any mutation path that
    -- skips it; the flag is idempotent.
    if plan and plan.pendGeneral then
        display.gate:Request("general")
    end
end

---------------------------------------------------------------------------------
-- Edit Mode -- the mover and its hitbox.
---------------------------------------------------------------------------------

-- The grid term is zero by construction: the anchor is sized to the grid and
-- the grid is pinned at the corner it grows away from, so the icons can never
-- reach outside the anchor box and the inset is carried entirely by the text
-- and dispel decorations. Every element anchors to a BUTTON, so the host for a
-- text inset is one icon square rather than the container.
--
-- The dispel term is safe to include even for a display with no DispelPosition
-- setting: with both anchor points absent it centres against itself and nets
-- to zero, which is what the modules this engine replaces without a dispel
-- decoration already relied on.
local function GetOverlayInset(display, settings)
    -- GetGridOverlayInset counts columns then rows, so a vertical display
    -- passes them the other way round: its IconsPerRow is a column height.
    local along  = settings.IconsPerRow or display.defaultIconsPerRow
    -- Same derivation as Container.SizeAnchor, so the hitbox and the anchor
    -- can never disagree about how many lines the display occupies.
    local across = math_ceil(KE.AuraContainer.ElementCapacity(display, settings) / along)
    local cols, rows = along, across
    if KE.AuraContainer.IsVerticalAxis(settings) then
        cols, rows = across, along
    end

    local grid = { KE:GetGridOverlayInset(
        cols,
        rows,
        settings.IconSize,
        settings.IconSpacing,
        KE.AuraContainer.CornerFor(settings),
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
