-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-DungeonAlerts.lua                                   ║
-- ║  GUI: Dungeon Alerts. Three dungeon pages on one row.    ║
-- ║  The per-module builders stay registered under their own ║
-- ║  ids and are dispatched here as tabs.                    ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame

GUIFrame:RegisterTabbedContent("DungeonAlerts", {
    { id = "DeathNotifications", label = "Death Notifications" },
    { id = "EnemyCounter",       label = "Enemy Counter" },
    { id = "TargetedSpells",     label = "Targeted Spells" },
})
