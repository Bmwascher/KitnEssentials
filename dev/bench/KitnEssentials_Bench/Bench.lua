-- Benchmark-only staging for the glow cost gate. Adds aura groups that can
-- never show an aura but still force the container's frame provider to
-- allocate, which is the only way to reach the display's allocation
-- high-water without more simultaneous auras than a player can carry.
--
-- This addon is never packaged. Nothing in KitnEssentials references it.

local NS = KITNESSENTIALS_NS

local BATCH        = 10
local TARGET_HOSTS = 40

local staged = false

SLASH_KESBENCH1 = "/kesbench"
SlashCmdList["KESBENCH"] = function()
    -- A local flag, not a group-key probe: the number of groups added varies
    -- with what the provider already owns, so no single key proves the state.
    if staged then
        print("kesbench: already staged -- /reload first if you want to start over")
        return
    end

    local module = KitnEssentials and KitnEssentials:GetModule("AuraExternals", true)
    local display = module and module.display
    if not display or not display.handle then
        print("kesbench: the externals display is not built -- enable the module first")
        return
    end

    local settings = display.getSettings()
    -- Group 1 is the externals group, and it is the one carrying the glow
    -- capability. Copying its descriptor is what makes the staged frames
    -- identical to the real ones rather than merely numerous.
    local template = display.groups[1]

    -- Fill to the target rather than adding a fixed count. A provider that
    -- already grew this session keeps its frames, so a fixed count would stage
    -- a heavier load than the cost table documents and the framerate gate
    -- would be judging the wrong workload.
    local owned = display.handle.container:GetAuraGroupFrameCount(template.key)
    if type(owned) ~= "number" or owned < BATCH or owned > TARGET_HOSTS
        or owned % BATCH ~= 0 then
        print("kesbench: unexpected owned frame count " .. tostring(owned)
            .. " -- /reload and run this before anything else")
        return
    end

    local groupCount = (TARGET_HOSTS - owned) / BATCH
    if groupCount == 0 then
        staged = true
        print("kesbench: provider already owns " .. TARGET_HOSTS .. " hosts, nothing to stage")
        return
    end

    for i = 1, groupCount do
        local key = "kebench" .. i

        display.handle.container:AddAuraGroup(key, template.buildFilter(settings), {
            candidateFilters = template.buildCandidates(settings),
            -- Zero cap: the group can never claim a frame, so nothing new is
            -- ever drawn. AddAuraGroup still allocates its provider batch,
            -- which is the entire point.
            maxFrameCount    = 0,
            sortMethod       = AuraContainerSortMethod[display.sortMethod],
            sortDirection    = AuraContainerSortDirection.Normal,
            initializeFrame  = function(button)
                NS.AuraStyle.InitializeButton(button, display, template, display.getSettings())
            end,
            layout           = NS.AuraContainer.GroupLayout(settings),
        })

        -- Appended so Reconfigure reaches these frames on every settings
        -- change. Without this a glow-type switch would restyle only the real
        -- group, and the staged hosts would contribute allocation without
        -- contributing the animation load being measured.
        display.groups[#display.groups + 1] = {
            key             = key,
            buildFilter     = template.buildFilter,
            buildCandidates = template.buildCandidates,
            capabilities    = template.capabilities,
        }
    end

    staged = true
    print("kesbench: staged " .. (groupCount * BATCH) .. " extra hosts, provider now at "
        .. TARGET_HOSTS .. ". /reload to undo.")
end
