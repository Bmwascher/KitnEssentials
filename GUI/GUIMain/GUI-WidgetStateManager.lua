-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-WidgetStateManager.lua                              ║
-- ║  Purpose: Reactive widget enable/disable manager.        ║
-- ║  Group widgets by name, attach optional conditions,      ║
-- ║  refresh group state when a master toggle flips.         ║
-- ║                                                          ║
-- ║  IMPORTANT: Register each widget in EXACTLY ONE group.   ║
-- ║  UpdateAll iterates groups via pairs() in unspecified    ║
-- ║  order; multi-group registration produces "last group    ║
-- ║  wins" non-determinism. For conditional widgets, encode  ║
-- ║  the condition on the group (SetCondition) and let       ║
-- ║  UpdateAll's mainEnabled gate handle the master toggle.  ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame

local ipairs = ipairs
local pairs = pairs
local type = type

local KEWidgetStateManagerMixin = {}

function KEWidgetStateManagerMixin:Register(widget, ...)
    if not widget then return end
    local groupNames = { ... }
    for _, groupName in ipairs(groupNames) do
        self.groups[groupName] = self.groups[groupName] or {}
        self.groups[groupName][#self.groups[groupName] + 1] = widget
    end
end

function KEWidgetStateManagerMixin:RegisterGroup(widgets, groupName)
    if not widgets or not groupName then return end
    self.groups[groupName] = self.groups[groupName] or {}
    for _, widget in ipairs(widgets) do
        self.groups[groupName][#self.groups[groupName] + 1] = widget
    end
end

function KEWidgetStateManagerMixin:SetCondition(groupName, conditionFn)
    self.conditions[groupName] = conditionFn
end

function KEWidgetStateManagerMixin:UpdateAll(mainEnabled)
    for groupName, widgets in pairs(self.groups) do
        local groupEnabled = mainEnabled

        if groupEnabled and self.conditions[groupName] then
            local condition = self.conditions[groupName]
            if type(condition) == "function" then
                groupEnabled = condition()
            end
        end

        for _, widget in ipairs(widgets) do
            if widget.SetEnabled then
                widget:SetEnabled(groupEnabled)
            elseif widget.SetDisabled then
                widget:SetDisabled(not groupEnabled)
            end
        end
    end
end

function KEWidgetStateManagerMixin:UpdateGroup(groupName, enabled)
    local widgets = self.groups[groupName]
    if not widgets then return end

    for _, widget in ipairs(widgets) do
        if widget.SetEnabled then
            widget:SetEnabled(enabled)
        elseif widget.SetDisabled then
            widget:SetDisabled(not enabled)
        end
    end
end

function KEWidgetStateManagerMixin:GetGroup(groupName)
    return self.groups[groupName] or {}
end

function KEWidgetStateManagerMixin:Clear()
    self.groups = {}
    self.conditions = {}
end

function GUIFrame:CreateWidgetStateManager()
    local manager = {
        groups = {},
        conditions = {},
    }

    Mixin(manager, KEWidgetStateManagerMixin)

    return manager
end
