-- ╔══════════════════════════════════════════════════════════╗
-- ║  Modules/Combat/AuraEngine/Container.lua                 ║
-- ║  Purpose: everything that touches the secure container.  ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)

local Container = {}
KE.AuraContainer = Container

-- CreateFrame("AuraContainer", ...) fails outright without this, and it must
-- not run at file-parse time.
local function EnsureAuraContainerLoaded()
    if C_AddOns and C_AddOns.LoadAddOn then
        C_AddOns.LoadAddOn("Blizzard_AuraContainer")
    end
end

-- The corner the display grows AWAY from. Container.Create pins it, and
-- ApplyLayout re-pins it when the direction changes.
function Container.CornerFor(settings)
    local up   = settings.GrowVertical == "UP"
    local left = settings.GrowHorizontal == "LEFT"
    return (up and "BOTTOM" or "TOP") .. (left and "RIGHT" or "LEFT")
end

-- The axis elements FILL before wrapping. Blizzard calls this the primary
-- axis: the maximum line size is measured along it, and new lines are added
-- across it. IconsPerRow therefore counts along the filling axis in both
-- cases -- a vertical display reads it as icons per column -- and MaxRows
-- always counts lines.
function Container.IsVerticalAxis(settings)
    return settings.GrowAxis == "VERTICAL"
end

function Container.AxisFor(settings)
    return Container.IsVerticalAxis(settings)
        and AnchorUtil.FlowLayoutAxis.Vertical
        or AnchorUtil.FlowLayoutAxis.Horizontal
end

-- How many layout elements the display can produce: the configured grid, or
-- the enchant slot count when that is larger. Enchant frames are registered
-- once at creation and there is no call to withdraw one, so a grid smaller
-- than the slot count cannot drop them -- it has to make room, or icons draw
-- outside the box the mover uses. A display declaring no enchants gets the
-- plain grid, unchanged.
function Container.ElementCapacity(display, settings)
    local perRow = settings.IconsPerRow or display.defaultIconsPerRow
    local grid   = perRow * (settings.MaxRows or 1)

    local enchants = display.declaration and display.declaration.itemEnchantments
    if not enchants then return grid end

    return math.max(grid, #enchants.slots)
end

-- elementWidth/Height come from IconSize because the flow layout measures
-- from these numbers, not from the frames. groupSpacing and forceNewLine stay
-- at Blizzard's defaults deliberately: setting groupSpacing to the element
-- spacing would DOUBLE the gap at the block boundary, where the first group's
-- trailing element spacing already sits.
function Container.GroupLayout(settings)
    local size    = settings.IconSize
    local spacing = settings.IconSpacing
    return {
        elementWidth   = size,
        elementHeight  = size,
        elementSpacing = spacing,
        lineSpacing    = spacing,
        groupSpacing   = 0,
        forceNewLine   = false,
    }
end

-- Reserved, not counted live. Counting only ACTIVE enchants would keep more
-- icons visible, but changing the budget as enchants come and go is a
-- reconfiguration, and reconfiguration DEFERS under restriction -- so inside a
-- keystone the correction would not land and the overflow would happen anyway.
--
-- The subtraction cannot go negative, because ElementCapacity is at least the
-- slot count. A one-icon display with weapon enchants declared therefore shows
-- no auras and its enchants, which is the only honest answer: the slots exist
-- and cannot be given back.
function Container.TotalLimit(display, settings)
    local enchants = display.declaration and display.declaration.itemEnchantments
    local reserved = enchants and #enchants.slots or 0
    return Container.ElementCapacity(display, settings) - reserved
end

-- The grid's span along one axis. The anchor's size and the flow layout's
-- wrap point are the same quantity measured twice -- the box the user drags
-- and the point the icons wrap -- so they are computed in one place and
-- cannot drift apart.
local function GridSpan(count, settings)
    return count * settings.IconSize + (count - 1) * settings.IconSpacing
end

-- The anchor has no size of its own until this runs -- every corner of a
-- zero-size frame coincides, so neither the pin nor the position math
-- notices, but the Edit Mode mover needs a real rectangle to grab, and
-- ApplyFramePosition's pixel snap reads the frame's ACTUAL edges. Called
-- before ApplyLayout in both Create and Reconfigure so the snap always runs
-- last, against the correct size, never a 0x0 or stale one.
function Container.SizeAnchor(handle, display, settings)
    local along  = settings.IconsPerRow or display.defaultIconsPerRow
    -- Derived from the element capacity rather than MaxRows directly, so the
    -- box always covers everything that can draw. For a display with no
    -- enchants this is exactly MaxRows and nothing changes.
    local across = math.ceil(Container.ElementCapacity(display, settings) / along)
    if Container.IsVerticalAxis(settings) then
        handle.anchorFrame:SetSize(GridSpan(across, settings), GridSpan(along, settings))
    else
        handle.anchorFrame:SetSize(GridSpan(along, settings), GridSpan(across, settings))
    end
end

-- Blizzard owns the frame list, so ask Blizzard. The provider grows it with
-- every batch, and a private copy would drift the first time a batch landed
-- without this addon noticing.
function Container.EachGroupFrame(handle, groupKey, fn)
    local n = handle.container:GetAuraGroupFrameCount(groupKey)
    for i = 1, n do
        local frame = handle.container:GetAuraGroupFrame(groupKey, i)
        if frame then fn(frame) end
    end
end

-- Index-based, never pairs: Blizzard falls back to REGISTRATION order when no
-- layout index separates two groups, so the declaration order is the
-- on-screen block order. Unordered iteration would silently reverse the
-- blocks.
--
-- Every declared group is added, including one whose count is zero. The
-- setter path fetches a group through a required-lookup helper that errors on
-- an unknown key, so a lazily added group would make every later settings
-- change conditional on whether something had added it yet.
function Container.AddGroups(handle, display, settings)
    local limits = display.splitLimit(Container.TotalLimit(display, settings), settings)

    for i = 1, #display.groups do
        local group = display.groups[i]

        -- THREE arguments. The filter string is its own parameter, not an
        -- options field. The sort enums are PLAIN GLOBALS, not Enum.* members.
        handle.container:AddAuraGroup(group.key, group.buildFilter(settings), {
            candidateFilters = group.buildCandidates(settings),
            maxFrameCount    = limits[group.key] or 0,
            sortMethod       = AuraContainerSortMethod[display.sortMethod],
            sortDirection    = AuraContainerSortDirection.Normal,
            -- Reads current settings at call time rather than closing over the
            -- creation-time table. Frames allocate in later batches, and a
            -- captured table would style a batch from the profile that was
            -- live when the group was added.
            --
            -- Nothing is recorded here. AddAuraGroup allocates its first batch
            -- and runs this callback BEFORE it returns, so any bookkeeping
            -- table this function wrote into would not exist yet. Blizzard's
            -- own frame enumeration is used instead, and it cannot go stale.
            initializeFrame  = function(button)
                local live = display.getSettings()
                KE.AuraStyle.InitializeButton(button, display, group, live)
            end,
            layout           = Container.GroupLayout(settings),
        })
    end
end

-- Enchant frames are layout elements in their own right, NOT members of an
-- aura group, but their slots ARE reserved out of the group budget: capacity
-- is the configured grid or the declared slot count, whichever is larger,
-- and the aura group's limit is that capacity minus the reserved slots.
-- layoutIndex 0 puts them ahead of every group, which is where Blizzard's
-- own frame shows them.
--
-- Add-only, like groups: there is no public remove, so this runs once at
-- creation and never again.
function Container.AddItemEnchantments(handle, display, settings)
    local spec = display.declaration.itemEnchantments
    if not spec then return end

    local layout = Container.GroupLayout(settings)
    layout.layoutIndex = 0
    handle.container:SetItemEnchantmentLayout(layout)

    for i = 1, #spec.slots do
        local frame = handle.container:AddItemEnchantment(spec.slots[i], {
            -- Same live-settings read as the group callback, for the same
            -- reason: a captured table would dress a later batch from the
            -- profile that was current when the slot was added.
            initializeFrame = function(button)
                local live = display.getSettings()
                KE.AuraStyle.InitializeButton(button, display, spec, live)
            end,
            -- The display this replaces showed an enchant whether or not it
            -- was expiring, so permanent enchants stay visible.
            hidePermanent = false,
        })

        if frame then
            handle.enchantFrames[#handle.enchantFrames + 1] = frame
        end
    end
end

-- Two frames per display. The anchor is a plain Frame carrying Position, the
-- KE mover and the pixel snap; the container is its CHILD.
--
-- The container cannot be the positioned frame: the first AddAuraGroup adds
-- UntrustedLayoutScriptExecution to its forbidden aspects, so KE frames
-- cannot anchor to it afterwards, and it calls SetSize on itself so its size
-- is not ours to reason about. Parenting it to the anchor is also what makes
-- hiding the anchor hide the display.
function Container.Create(display, settings)
    EnsureAuraContainerLoaded()

    local anchorFrame = CreateFrame("Frame", "KE_" .. display.key .. "Anchor", UIParent)

    local container = CreateFrame(
        "AuraContainer",
        "KE_" .. display.key .. "Container",
        anchorFrame,
        "CustomAuraContainerTemplate"
    )
    -- The DERIVED corner, not TOPLEFT, and pinned HERE rather than left to
    -- ApplyLayout. Two reasons. A fixed TOPLEFT would be a second anchor that
    -- ApplyLayout's SetPoint does not remove, leaving the container
    -- constrained by two points. And this call happens before any
    -- AddAuraGroup, which is the only point where a pin is certainly legal —
    -- see the STOP condition in ApplyLayout.
    local corner = Container.CornerFor(settings)
    container:SetPoint(corner, anchorFrame, corner, 0, 0)

    container:SetUnit("player")

    -- corner is REMEMBERED so ApplyLayout can tell a real direction change
    -- from an ordinary settings change. Without it, every reconfiguration —
    -- and the ApplyLayout call two lines below — would re-pin, which fires
    -- the one call whose legality is still an open question.
    --
    -- defaultIconsPerRow travels with the handle for the same reason
    -- TotalLimit reads it: ApplyLayout has no display argument, so this is
    -- its only route to the same fallback.
    local handle = {
        anchorFrame        = anchorFrame,
        container          = container,
        corner             = corner,
        defaultIconsPerRow = display.defaultIconsPerRow,
        enchantFrames      = {},
    }

    Container.AddGroups(handle, display, settings)
    Container.AddItemEnchantments(handle, display, settings)
    Container.SizeAnchor(handle, display, settings)
    Container.ApplyLayout(handle, settings)

    return handle
end

-- state is the CONTAINER DISPLAY state and reaches nothing else. Two inputs
-- feed it: the module's Enabled setting and the vehicle rule. It does not own
-- the sound registry — entering a vehicle hides the icons and leaves the
-- sounds registered.
--
-- The engine calls this on first creation too. A container is ENABLED at birth — the
-- intrinsic sets it through KeyValues, which the template inherits — so this
-- does not repair a default; it makes the display MATCH its configured
-- state. A module switched off in saved settings must come up hidden and
-- disabled.
--
-- anchorShown is a SEPARATE decision the caller makes, never derived from
-- state: the preview frames are children of the anchor, so a hidden container
-- does not imply a hidden anchor.
function Container.ApplyState(handle, state, anchorShown)
    handle.container:SetShown(state)
    handle.container:SetEnabled(state)
    handle.anchorFrame:SetShown(anchorShown)
end

-- The container owns its unit, so a vehicle swap is a plain setter rather
-- than a secure attribute driver. Blizzard rebuilds the display from the new
-- unit's auras on its own.
function Container.SetUnit(handle, unitToken)
    handle.container:SetUnit(unitToken)
end

-- Groups are add-only with no public remove, so retiring is always a zero
-- count and never a removal. Keys are author-assigned literals that never
-- change, so nothing here goes stale.
function Container.Reconfigure(handle, display, settings)
    local limits = display.splitLimit(Container.TotalLimit(display, settings), settings)

    for i = 1, #display.groups do
        local group = display.groups[i]
        handle.container:SetAuraGroupFilterString(group.key, group.buildFilter(settings))
        handle.container:SetAuraGroupCandidateFilters(group.key, group.buildCandidates(settings))
        handle.container:SetAuraGroupMaxFrameCount(group.key, limits[group.key] or 0)
        handle.container:SetAuraGroupLayout(group.key, Container.GroupLayout(settings))

        -- Buttons already created keep their creation-time dressing until
        -- something restyles them. Icon size, fonts, anchors, swipe direction,
        -- border, dispel decoration and the glow all live on the button, not
        -- in the group options, so a settings change that skipped this would
        -- apply to future frames only. A profile switch is the visible case:
        -- the container survives it, and the current module resyncs its
        -- persistent frame for exactly this reason.
        Container.EachGroupFrame(handle, group.key, function(button)
            -- Registration too, not only dressing: every registered region has
            -- a setting that switches it off, and switching it back on has to
            -- re-register. RegisterRegions is idempotent for this reason.
            KE.AuraStyle.RegisterRegions(button, display, group, settings)
            KE.AuraStyle.StyleAuraFrame(button, settings, group.capabilities)
            KE.AuraGlow.Apply(button, settings, group.capabilities)
        end)
    end

    -- Enchant frames keep their creation-time dressing exactly as group
    -- frames do, and there is no group enumeration that reaches them, so the
    -- registered frames are re-dressed from the handle's own record.
    local enchantSpec = display.declaration.itemEnchantments
    if enchantSpec then
        local layout = Container.GroupLayout(settings)
        layout.layoutIndex = 0
        handle.container:SetItemEnchantmentLayout(layout)

        for i = 1, #handle.enchantFrames do
            local button = handle.enchantFrames[i]
            KE.AuraStyle.RegisterRegions(button, display, enchantSpec, settings)
            KE.AuraStyle.StyleAuraFrame(button, settings, enchantSpec.capabilities)
        end
    end

    Container.SizeAnchor(handle, display, settings)
    Container.ApplyLayout(handle, settings)
end

-- Growth direction, anchor point, maximum line size, strata, and the anchor
-- frame's position. Runs once at the end of Create and again on every
-- reconfiguration.
function Container.ApplyLayout(handle, settings)
    local horizontalDirection = settings.GrowHorizontal == "LEFT"
        and AnchorUtil.FlowDirection.Left
        or AnchorUtil.FlowDirection.Right
    local verticalDirection = settings.GrowVertical == "UP"
        and AnchorUtil.FlowDirection.Up
        or AnchorUtil.FlowDirection.Down
    handle.container:SetFlowLayoutGrowthDirection(horizontalDirection, verticalDirection)

    -- Set BEFORE the anchor point and the maximum line size: both are
    -- interpreted relative to the primary axis, so setting them first would
    -- apply them against the previous axis for one layout pass.
    handle.container:SetFlowLayoutAxis(Container.AxisFor(settings))

    -- Must agree with the pin corner below — see Container.CornerFor. The
    -- flow layout anchors every element corner-to-corner at this point and
    -- grows away from it, so a mismatch puts the fixed point on the moving
    -- edge and the block slides regardless of the pin.
    handle.container:SetFlowLayoutAnchorPoint(Container.CornerFor(settings))

    -- Blizzard's default is infinity, so without this the display never
    -- wraps and IconsPerRow silently becomes a total cap instead of a row
    -- width. Falls back the same way TotalLimit does -- ApplyLayout has no
    -- display argument, so handle.defaultIconsPerRow is the only route to it.
    local perRow = settings.IconsPerRow or handle.defaultIconsPerRow
    handle.container:SetFlowLayoutMaximumLineSize(GridSpan(perRow, settings))

    -- Applied to BOTH frames. A child inherits its parent's strata at
    -- creation, but whether a later SetFrameStrata on the parent propagates
    -- to an already-created child is undocumented, so both are set directly.
    local strata = settings.Strata or "MEDIUM"
    handle.anchorFrame:SetFrameStrata(strata)
    handle.container:SetFrameStrata(strata)

    -- Guarded on the stored corner. ApplyLayout runs on every reconfiguration
    -- and once during creation, so an unconditional re-pin would fire the
    -- uncertain late call constantly — including immediately after the
    -- groups are added, which is precisely the case the creation-time pin
    -- exists to avoid.
    --
    -- STOP condition: the creation-time pin (Container.Create) runs before
    -- any AddAuraGroup and is safe. This re-pin does not: it runs after the
    -- first AddAuraGroup, which adds a forbidden layout-script aspect to the
    -- container, and whether ClearAllPoints/SetPoint on the container remain
    -- legal past that point is undocumented. If either call errors or
    -- silently fails in-game, report it rather than working around it.
    local nextCorner = Container.CornerFor(settings)
    if nextCorner ~= handle.corner then
        handle.container:ClearAllPoints()
        handle.container:SetPoint(nextCorner, handle.anchorFrame, nextCorner, 0, 0)
        handle.corner = nextCorner
    end

    KE:ApplyFramePosition(handle.anchorFrame, settings.Position, settings)
end
