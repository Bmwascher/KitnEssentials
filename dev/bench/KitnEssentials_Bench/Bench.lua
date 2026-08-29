-- Benchmark-only staging for the glow cost gate. Adds aura groups that can
-- never show an aura but still force the container's frame provider to
-- allocate, which is the only way to reach the display's allocation
-- high-water without eleven simultaneous externals on one player.
--
-- This addon is never packaged. Nothing in KitnEssentials references it.

local NS = KITNESSENTIALS_NS

local GROUP_COUNT = 3

SLASH_KESBENCH1 = "/kesbench"
SlashCmdList["KESBENCH"] = function()
    local module = KitnEssentials and KitnEssentials:GetModule("AuraExternals", true)
    local display = module and module.display
    if not display or not display.handle then
        print("kesbench: the externals display is not built -- enable the module first")
        return
    end

    -- AddAuraGroup asserts the key is new, so a second /kesbench would throw
    -- mid-measurement into the BugSack the smoke run expects clean.
    if display.handle.container:HasAuraGroup("kebench1") then
        print("kesbench: already staged -- /reload first if you want to start over")
        return
    end

    local settings = display.getSettings()
    -- Group 1 is the externals group, and it is the one carrying the glow
    -- capability. Copying its descriptor is what makes the staged frames
    -- identical to the real ones rather than merely numerous.
    local template = display.groups[1]

    for i = 1, GROUP_COUNT do
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

    print("kesbench: " .. GROUP_COUNT .. " zero-cap groups added ("
        .. (GROUP_COUNT * 10) .. " extra hosts). /reload to undo.")
end
