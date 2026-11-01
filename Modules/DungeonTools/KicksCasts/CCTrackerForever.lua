-- ╔══════════════════════════════════════════════════════════╗
-- ║  Modules/DungeonTools/KicksCasts/CCTrackerForever.lua    ║
-- ║  Purpose: CC Tracker's crowd control list on the Forever ║
-- ║           client, which replaces the shipped list.       ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)

-- Printed by dev/scripts/derive-forever-cc.lua; paste its output unchanged.
KE.CC_TRACKER_SEEDS = {
    { key = "POLYMORPH", label = "Polymorph (all)", group = "MAGE", default = true, ids = {
        118, 12824, 12825, 12826, 28270, 28271, 28272,
    } },
    { key = "REPENTANCE", label = "Repentance", group = "PALADIN", default = true, ids = {
        20066,
    } },
    { key = "TURN_EVIL", label = "Turn Undead", group = "PALADIN", default = true, ids = {
        2878, 5627, 10326,
    } },
    { key = "FREEZING_TRAP", label = "Freezing Trap", group = "HUNTER", default = true, ids = {
        3355, 14308, 14309,
    } },
    { key = "SCARE_BEAST", label = "Scare Beast", group = "HUNTER", default = true, ids = {
        1513, 14326, 14327,
    } },
    { key = "SAP", label = "Sap", group = "ROGUE", default = true, ids = {
        6770, 2070, 11297,
    } },
    { key = "BLIND", label = "Blind", group = "ROGUE", default = true, ids = {
        2094,
    } },
    { key = "BANISH", label = "Banish", group = "WARLOCK", default = true, ids = {
        710, 18647,
    } },
    { key = "FEAR", label = "Fear", group = "WARLOCK", default = true, ids = {
        5782, 6213, 6215,
    } },
    { key = "SEDUCTION", label = "Seduction", group = "WARLOCK", default = true, ids = {
        6358,
    } },
    { key = "HIBERNATE", label = "Hibernate", group = "DRUID", default = true, ids = {
        2637, 18657, 18658,
    } },
    { key = "ENTANGLING_ROOTS", label = "Entangling Roots", group = "DRUID", default = false, ids = {
        339, 1062, 5195, 5196, 9852, 9853,
    } },
    { key = "SHACKLE_HORROR", label = "Shackle Undead", group = "PRIEST", default = true, ids = {
        9484, 9485, 10955,
    } },
}
