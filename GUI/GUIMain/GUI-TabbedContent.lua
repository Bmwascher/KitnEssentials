-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-TabbedContent.lua                                   ║
-- ║  Purpose: One sidebar entry hosting several existing      ║
-- ║  RegisterContent pages behind a sub-tab strip — the      ║
-- ║  sidebar-diet mechanism.                                 ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame

local ipairs = ipairs

-- Active tab per page, session only. Which tab you last viewed is not a setting.
GUIFrame.tabbedPageState = GUIFrame.tabbedPageState or {}

-- Falls back to the first tab when the remembered id is absent OR no longer in
-- `tabs` — a stale id would otherwise render an empty page.
function GUIFrame:ResolveActiveTab(itemId, tabs)
    local remembered = self.tabbedPageState[itemId]
    if remembered then
        for _, tab in ipairs(tabs) do
            if tab.id == remembered then return remembered end
        end
    end
    return tabs[1] and tabs[1].id or nil
end

-- tabs = { { id = "<registered content id>", label = "<display>" }, ... }
-- opts.headerBuilder(scrollChild, yOffset) -> (newYOffset, collapse)
--   Renders above the tab strip; collapse = true returns immediately with no
--   strip and no tab content (the lone-header-bar state for a disabled module).
--
-- Builders resolve LIVE at build time, so a tab's page may be registered after
-- this call — GUI.xml load order does not matter.
function GUIFrame:RegisterTabbedContent(itemId, tabs, opts)
    self:RegisterContent(itemId, function(scrollChild, yOffset)
        if opts and opts.headerBuilder then
            local headerOffset, collapse = opts.headerBuilder(scrollChild, yOffset)
            yOffset = headerOffset or yOffset
            if collapse then return yOffset end
        end

        local activeId = GUIFrame:ResolveActiveTab(itemId, tabs)

        local _, tabOffset = GUIFrame:CreateSubTabs(scrollChild, yOffset, {
            tabs = tabs,
            activeId = activeId,
            onSwitch = function(newId)
                GUIFrame.tabbedPageState[itemId] = newId
            end,
            fill = true,
        })
        yOffset = tabOffset

        local builder = activeId and GUIFrame.registeredContent[activeId]
        if builder then
            yOffset = builder(scrollChild, yOffset)
        end
        return yOffset
    end)
end
