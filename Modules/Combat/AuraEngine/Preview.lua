-- ╔══════════════════════════════════════════════════════════╗
-- ║  Modules/Combat/AuraEngine/Preview.lua                   ║
-- ║  Purpose: the config-panel preview -- plain frames, never ║
-- ║  an AuraContainer, and the swap with the live container.  ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)

local math_floor = math.floor
local math_ceil  = math.ceil

local Preview = {}
KE.AuraPreview = Preview

-- How often the ticker recomputes the timer text and checks for an expired
-- icon. The text only changes once per whole second (FormatRemaining below),
-- so anything finer would burn cycles for no visible difference.
local TICK_INTERVAL = 0.5

---------------------------------------------------------------------------------
-- Plan functions -- pure decisions. The swap is expressed as a PLAN, a table
-- of what should be true, so it can be tested without standing up frames.
-- Enter/Exit below do nothing but carry the plan out.
---------------------------------------------------------------------------------

-- Entering preview leaves the ANCHOR shown so the mover and the position
-- stay live; only the container goes away.
function Preview.PlanEnter()
    return { containerShown = false, containerEnabled = false, anchorShown = true }
end

function Preview.PlanExit(ctx)
    if ctx.isHidden then
        -- A reconfiguration like any other: it waits for release. The anchor
        -- is restored regardless so the user is never left with nothing where
        -- they were positioning something.
        return { containerShown = false, containerEnabled = false, anchorShown = true, pendGeneral = true }
    end
    return {
        containerShown   = ctx.state,
        containerEnabled = ctx.state,
        anchorShown      = ctx.state,
        pendGeneral      = false,
    }
end

---------------------------------------------------------------------------------
-- Per-display frame state -- pools, the ticker, and the current entries.
-- The handle itself is NOT kept here: display.handle is the one place it
-- lives, so there is exactly one copy that can go stale after a rebuild
-- replaces the container. Pools persist across Exit/Enter -- releasing a
-- FramePool's kits only hides them, so dropping the table on every Exit
-- would orphan real WoW frames (SetParent(nil) -> UIParent) instead of
-- reusing them, and Rebuild can fire many times in a row while a slider
-- drags.
---------------------------------------------------------------------------------

local previewState = {}

local function GetPreviewState(display)
    local state = previewState[display.key]
    if not state then
        state = {}
        previewState[display.key] = state
    end
    return state
end

local function ApplyContainerPlan(handle, plan)
    if not handle then return end
    handle.container:SetShown(plan.containerShown)
    handle.container:SetEnabled(plan.containerEnabled)
    handle.anchorFrame:SetShown(plan.anchorShown)
end

local function GroupsByKey(display)
    local map = {}
    for i = 1, #display.groups do
        local group = display.groups[i]
        map[group.key] = group
    end
    return map
end

-- One pool per GROUP KEY, never one for the whole display. A group's
-- capabilities (hasGlow, hasBorder, hasDispel) come from its declaration and
-- never change at runtime, so keying purely on groupKey is enough -- the same
-- key can never resolve to a different capability set later.
local function EnsurePool(state, groupKey, display, group, settings)
    state.pools = state.pools or {}
    local pool = state.pools[groupKey]
    if not pool then
        pool = KE.FramePool:New(function(holder)
            local frame = CreateFrame("Frame", nil, holder)
            KE.AuraStyle.InitializePreviewFrame(frame, display, group, settings)
            return frame
        end)
        state.pools[groupKey] = pool
    end
    return pool
end

-- Same grid math the module this engine replaces used to lay out its own
-- buttons: button[1] sits at the position corner, later icons step by
-- IconSize + IconSpacing per column/row, signed by the grow direction.
local function PositionEntryFrame(frame, index, display, settings)
    local perRow   = settings.IconsPerRow or display.defaultIconsPerRow
    local size     = settings.IconSize or 0
    local spacing  = settings.IconSpacing or 0
    local dx       = (size + spacing) * (settings.GrowHorizontal == "LEFT" and -1 or 1)
    local dy       = (size + spacing) * (settings.GrowVertical == "UP" and 1 or -1)
    local row      = math_floor((index - 1) / perRow)
    local col      = (index - 1) % perRow
    local pin      = (settings.Position and settings.Position.AnchorFrom) or "CENTER"

    frame:ClearAllPoints()
    frame:SetPoint(pin, frame:GetParent(), pin, col * dx, row * dy)
end

-- Mirrors the live formatter's breakpoints (Style.lua's GetDurationFormatter)
-- without going through C_StringUtil: that formatter only drives text via
-- SetDurationText, a registration call plain preview frames cannot accept.
local function FormatRemaining(seconds)
    if seconds <= 0 then return "" end
    if seconds >= 60 then
        return math_floor(seconds / 60) .. "m"
    end
    return tostring(math_ceil(seconds))
end

local function UpdateEntryTimer(frame, entry, now)
    if not frame.keTimer then return end
    frame.keTimer:SetText(FormatRemaining(entry.expirationTime - now))
end

-- StyleAuraFrame paints the dispel ring pure white in "dispel" mode, because
-- on a live button the game repaints it per aura through the registered
-- dispel texture. A preview frame gets no such registration, so that repaint
-- never happens and the ring would stay white without this. Applied in both
-- colour modes: in the non-dispel mode the ring is already this colour, so
-- repainting it changes nothing.
local function RepaintDispelRing(frame, settings)
    local ring = frame.keDispel and frame.keDispel.ring
    if not ring then return end

    local r, g, b, a = KE:ResolveColor(settings.BorderColor, { 0.8, 0, 0, 1 })
    ring.top:SetColorTexture(r, g, b, a);    ring.top:SetSnapToPixelGrid(false)
    ring.bottom:SetColorTexture(r, g, b, a); ring.bottom:SetSnapToPixelGrid(false)
    ring.left:SetColorTexture(r, g, b, a);   ring.left:SetSnapToPixelGrid(false)
    ring.right:SetColorTexture(r, g, b, a);  ring.right:SetSnapToPixelGrid(false)
end

local function PopulateEntryContent(frame, entry, now)
    if frame.keIcon then
        frame.keIcon:SetTexture(entry.icon)
    end
    if frame.keCount then
        frame.keCount:SetText((entry.count and entry.count > 0) and tostring(entry.count) or "")
    end
    if frame.keCooldown then
        frame.keCooldown:SetCooldown(entry.expirationTime - entry.duration, entry.duration)
    end
    UpdateEntryTimer(frame, entry, now)
end

local function TeardownFrames(state)
    if state.ticker then
        state.ticker:Cancel()
        state.ticker = nil
    end
    if state.pools then
        for _, pool in pairs(state.pools) do
            pool:ReleaseAll()
        end
    end
    state.entries = {}
end

-- Tears down the preview frames for a display without touching the
-- container. Shared by Exit (which applies a container plan afterward) and
-- Rebuild (which never does, because the container is already hidden while
-- the preview is open and must stay that way).
local function TeardownPreviewFrames(display)
    local state = previewState[display.key]
    if state then
        TeardownFrames(state)
    end
end

-- Counts down every active entry and re-seeds any that reach zero, from
-- `now`, so the preview loops forever instead of freezing on an expired icon.
local function TickPreview(state)
    local now = GetTime()
    for i = 1, #state.entries do
        local item  = state.entries[i]
        local entry, frame = item.entry, item.frame
        if now >= entry.expirationTime then
            entry.expirationTime = now + entry.duration
            if frame.keCooldown then
                frame.keCooldown:SetCooldown(now, entry.duration)
            end
        end
        UpdateEntryTimer(frame, entry, now)
    end
end

-- Icon file IDs and the count sequence come from display.buildPreview --
-- there is no spell lookup anywhere in this path. Rules.lua stays
-- GetTime()-free, so the timing half (auraInstanceID, spellId, duration,
-- expirationTime) is assembled here from Rules.PreviewTiming(index).
local function BuildFrames(state, handle, display, settings)
    TeardownFrames(state)

    local groupsByKey = GroupsByKey(display)
    local total   = KE.AuraContainer.TotalLimit(display, settings)
    local entries = display.buildPreview(settings, total)
    local now     = GetTime()

    state.entries = {}
    for i = 1, #entries do
        local entry = entries[i]
        entry.auraInstanceID = i
        entry.spellId        = 0
        local duration, offset = KE.AuraRules.PreviewTiming(i)
        entry.duration        = duration
        entry.expirationTime  = now - offset + duration

        local group = groupsByKey[entry.groupKey]
        if group then
            local pool  = EnsurePool(state, entry.groupKey, display, group, settings)
            local frame = pool:Acquire(handle.anchorFrame)

            -- Re-dress unconditionally, whether the frame is new or reused,
            -- so a reused kit always matches the CURRENT settings rather than
            -- whatever was live the first time this group's pool was built.
            KE.AuraStyle.StyleAuraFrame(frame, settings, group.capabilities)
            KE.AuraGlow.Apply(frame, settings, group.capabilities)
            RepaintDispelRing(frame, settings)

            PositionEntryFrame(frame, i, display, settings)
            PopulateEntryContent(frame, entry, now)

            state.entries[#state.entries + 1] = { entry = entry, frame = frame }
        end
    end

    state.ticker = C_Timer.NewTicker(TICK_INTERVAL, function() TickPreview(state) end)
end

---------------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------------

function Preview.Enter(handle, display, settings)
    if not handle then return end
    ApplyContainerPlan(handle, Preview.PlanEnter())
    BuildFrames(GetPreviewState(display), handle, display, settings)
end

-- settings is unused: Exit's only work is the container swap and the
-- restriction check, neither of which reads it. Kept in the signature
-- because the interface names it explicitly.
--
-- The restriction check reads display.gate's own predicate directly --
-- never Request, which CLEARS the pending flag on a true answer because a
-- true answer is a promise that the caller acts on it immediately. Exit's
-- own plan may then decide not to restore the container (a disabled module,
-- or the caller's moduleState says otherwise), so asking Request here would
-- consume a debt Exit is not guaranteed to honour. Every display gets a gate
-- when it is registered, so this is never nil in production.
function Preview.Exit(handle, display, _settings, moduleState)
    local isHidden = display.gate.isHidden()
    local plan = Preview.PlanExit({ isHidden = isHidden, state = moduleState })

    TeardownPreviewFrames(display)
    ApplyContainerPlan(handle, plan)

    return plan
end

-- What a settings change reaches while the preview is open: discard the
-- current preview frames and rebuild them from current settings, so size,
-- layout, quotas and glow all follow the user's edit. It goes through the
-- same frame-building path Enter uses -- never a second construction path,
-- so the preview cannot drift from itself -- but it skips the container
-- swap entirely: the container is already hidden while the preview is open
-- and must stay that way, so cycling it through Exit's show/enable plan on
-- every settings tick would re-register a secure container's events for no
-- visible change.
function Preview.Rebuild(display, settings)
    local handle = display.handle
    if not handle then return end

    TeardownPreviewFrames(display)
    Preview.Enter(handle, display, settings)
end
