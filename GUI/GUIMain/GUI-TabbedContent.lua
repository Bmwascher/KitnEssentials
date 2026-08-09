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

-- Nested sub-rows are not pages, so they have no entry in tabbedPageState.
-- Edit Mode can only hand over one id, so a nested id has to be translated to
-- its owning outer tab and then passed down.
GUIFrame.nestedTabOwner = GUIFrame.nestedTabOwner or {}
GUIFrame.pendingNestedTab = GUIFrame.pendingNestedTab or {}

function GUIFrame:RegisterNestedTabs(ownerId, nestedIds)
    for _, nestedId in ipairs(nestedIds) do
        self.nestedTabOwner[nestedId] = ownerId
    end
end

-- Falls back to the first tab when the remembered id is absent OR no longer in
-- `tabs` — a stale id would otherwise render an empty page.
function GUIFrame:ResolveActiveTab(itemId, tabs)
    local remembered = self.tabbedPageState[itemId]
    if remembered then
        for _, tab in ipairs(tabs) do
            if tab.id == remembered then return remembered end
        end

        -- A remembered id that is not an outer tab may be a nested one. Rewrite
        -- the page state to the owning tab and hand the nested id down, so a
        -- later rebuild stays on the right outer tab instead of falling back.
        local owner = self.nestedTabOwner[remembered]
        if owner then
            for _, tab in ipairs(tabs) do
                if tab.id == owner then
                    self.pendingNestedTab[owner] = remembered
                    self.tabbedPageState[itemId] = owner
                    return owner
                end
            end
        end
    end
    return tabs[1] and tabs[1].id or nil
end

-- tabs = { { id = "<registered content id>", label = "<display>" }, ... }
--   or a function returning that list, evaluated at BUILD time. Use the
--   function form when the tab set depends on state -- a page hosting modules
--   that outlive its own master toggle offers only those while the master is
--   off (GUI/GUITabs/GUISkinning/GUI-BlizzardFrames.lua). A shrinking list
--   needs no extra care: ResolveActiveTab above already falls back to the
--   first tab when the remembered id is gone.
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

        local tabList = type(tabs) == "function" and tabs() or tabs
        local activeId = GUIFrame:ResolveActiveTab(itemId, tabList)

        local _, tabOffset = GUIFrame:CreateSubTabs(scrollChild, yOffset, {
            tabs = tabList,
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
