-- ╔══════════════════════════════════════════════════════════╗
-- ║  CombatDataForever.lua                                   ║
-- ║  Purpose: The Forever client's spell rank families and   ║
-- ║           combat potions, and the rank lookups.          ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

-- The two tables below are printed by dev/scripts/derive-forever-combat.lua
-- from the game data; change them by re-running it, never by hand.
local RANK_FAMILIES = {
    [10] = { 10, 6141, 8427, 10185, 10186, 10187 },  -- Blizzard
    [17] = { 17, 592, 600, 3747, 6065, 6066, 10898, 10899, 10900, 10901 },  -- Power Word: Shield
    [53] = { 53, 2589, 2590, 2591, 8721, 11279, 11280, 11281, 25300 },  -- Backstab
    [67] = { 67, 9452 },  -- Vindication
    [72] = { 72, 1671, 1672 },  -- Shield Bash
    [78] = { 78, 284, 285, 1608, 11564, 11565, 11566, 11567, 25286 },  -- Heroic Strike
    [99] = { 99, 1735, 9490, 9747, 9898 },  -- Demoralizing Roar
    [100] = { 100, 6178, 11578 },  -- Charge
    [116] = { 116, 205, 837, 7322, 8406, 8407, 8408, 10179, 10180, 10181, 25304 },  -- Frostbolt
    [118] = { 118, 12824, 12825, 12826, 28271, 28272 },  -- Polymorph
    [120] = { 120, 8492, 10159, 10160, 10161 },  -- Cone of Cold
    [122] = { 122, 865, 6131, 10230 },  -- Frost Nova
    [132] = { 132, 2970, 11743 },  -- Detect Invisibility
    [133] = { 133, 143, 145, 3140, 8400, 8401, 8402, 10148, 10149, 10150, 10151, 25306 },  -- Fireball
    [136] = { 136, 3111, 3661, 3662, 13542, 13543, 13544 },  -- Mend Pet
    [168] = { 168, 7300, 7301 },  -- Frost Armor
    [172] = { 172, 6222, 6223, 7648, 11671, 11672, 25311 },  -- Corruption
    [324] = { 324, 26364, 325, 26365, 905, 26366, 945, 26367, 8134, 26369, 10431, 26370, 10432, 26363 },  -- Lightning Shield
    [331] = { 331, 332, 547, 913, 939, 959, 8005, 10395, 10396, 25357 },  -- Healing Wave
    [339] = { 339, 1062, 5195, 5196, 9852, 9853 },  -- Entangling Roots
    [348] = { 348, 707, 1094, 2941, 11665, 11667, 11668, 25309 },  -- Immolate
    [370] = { 370, 8012 },  -- Purge
    [403] = { 403, 408439, 529, 408440, 548, 408441, 915, 408442, 943, 408443, 6041, 408472, 10391, 408473, 10392, 408474, 15207, 408475, 15208, 408477 },  -- Lightning Bolt
    [408] = { 408, 8643 },  -- Kidney Shot
    [421] = { 421, 408479, 930, 408481, 2860, 408482, 10605, 408484 },  -- Chain Lightning
    [453] = { 453, 8192, 10953 },  -- Mind Soothe
    [465] = { 465, 10290, 643, 10291, 1032, 10292, 10293 },  -- Devotion Aura
    [467] = { 467, 782, 1075, 8914, 9756, 9910 },  -- Thorns
    [468] = { 468, 16083 },  -- White Stallion
    [471] = { 471, 16082 },  -- Palomino Stallion
    [498] = { 498, 5573 },  -- Divine Protection
    [527] = { 527, 988 },  -- Dispel Magic
    [543] = { 543, 8457, 8458, 10223, 10225 },  -- Fire Ward
    [579] = { 579, 16080 },  -- Red Wolf
    [585] = { 585, 591, 598, 984, 1004, 6060, 10933, 10934 },  -- Smite
    [586] = { 586, 9578, 9579, 9592, 10941, 10942 },  -- Fade
    [587] = { 587, 597, 990, 6129, 10144, 10145, 28612 },  -- Conjure Food
    [588] = { 588, 7128, 602, 1006, 10951, 10952 },  -- Inner Fire
    [589] = { 589, 594, 970, 992, 2767, 10892, 10893, 10894 },  -- Shadow Word: Pain
    [596] = { 596, 996, 10960, 10961, 25316 },  -- Prayer of Healing
    [604] = { 604, 8450, 8451, 10173, 10174 },  -- Dampen Magic
    [605] = { 605, 10911, 10912 },  -- Mind Control
    [633] = { 633, 2800, 10310 },  -- Lay on Hands
    [635] = { 635, 19982, 639, 19981, 647, 19980, 1026, 19968, 1042, 1313348, 3472, 1313349, 10328, 1313350, 10329, 1313351, 25292, 1313352 },  -- Holy Light
    [642] = { 642, 1020 },  -- Divine Shield
    [679] = { 679, 678, 1866, 680, 2495, 5569, 10332, 10333 },  -- Holy Strike
    [686] = { 686, 695, 705, 1088, 1106, 7641, 11659, 11660, 11661, 25307 },  -- Shadow Bolt
    [687] = { 687, 696 },  -- Demon Skin
    [689] = { 689, 699, 709, 7651, 11699, 11700 },  -- Drain Life
    [693] = { 693, 20752, 20755, 20756, 20757 },  -- Create Soulstone
    [694] = { 694, 7400, 7402, 20559, 20560 },  -- Mocking Blow
    [702] = { 702, 1108, 6205, 7646, 11707, 11708 },  -- Curse of Weakness
    [703] = { 703, 8631, 8632, 8633, 11289, 11290 },  -- Garrote
    [704] = { 704, 7658, 7659, 11717 },  -- Curse of Recklessness
    [706] = { 706, 1086, 11733, 11734, 11735 },  -- Demon Armor
    [710] = { 710, 18647 },  -- Banish
    [724] = { 724, 27870, 27871 },  -- Lightwell
    [740] = { 740, 8918, 9862, 9863 },  -- Tranquility
    [755] = { 755, 3698, 3699, 3700, 11693, 11694, 11695 },  -- Health Funnel
    [770] = { 770, 778, 9749, 9907 },  -- Faerie Fire
    [772] = { 772, 6546, 6547, 6548, 11572, 11573, 11574 },  -- Rend
    [774] = { 774, 1058, 1430, 2090, 2091, 3627, 8910, 9839, 9840, 9841, 25299 },  -- Rejuvenation
    [779] = { 779, 780, 769, 9754, 411128, 9908 },  -- Swipe
    [781] = { 781, 14272, 14273 },  -- Disengage
    [845] = { 845, 7369, 11608, 11609, 20569 },  -- Cleave
    [853] = { 853, 5588, 5589, 10308 },  -- Hammer of Justice
    [879] = { 879, 5614, 5615, 10312, 10313, 10314 },  -- Exorcism
    [976] = { 976, 10957, 10958 },  -- Shadow Protection
    [980] = { 980, 1014, 6217, 11711, 11712, 11713 },  -- Bane of Agony
    [1008] = { 1008, 8455, 10169, 10170 },  -- Amplify Magic
    [1022] = { 1022, 5599, 10278 },  -- Blessing of Protection
    [1064] = { 1064, 10622, 10623 },  -- Chain Heal
    [1079] = { 1079, 9492, 9493, 9752, 9894, 9896 },  -- Rip
    [1082] = { 1082, 3029, 5201, 9849, 9850 },  -- Claw
    [1098] = { 1098, 11725, 11726 },  -- Subjugate Demon
    [1120] = { 1120, 8288, 8289, 11675 },  -- Drain Soul
    [1126] = { 1126, 5232, 6756, 5234, 8907, 9884, 9885 },  -- Mark of the Wild
    [1130] = { 1130, 14323, 14324, 14325 },  -- Hunter's Mark
    [1160] = { 1160, 6190, 11554, 11555, 11556 },  -- Demoralizing Shout
    [1243] = { 1243, 1244, 1245, 2791, 10937, 10938 },  -- Power Word: Fortitude
    [1449] = { 1449, 8437, 8438, 8439, 10201, 10202 },  -- Arcane Explosion
    [1454] = { 1454, 1455, 1456, 11687, 11688, 11689 },  -- Life Tap
    [1459] = { 1459, 1460, 1461, 10156, 10157 },  -- Arcane Intellect
    [1463] = { 1463, 8494, 8495, 10191, 10192, 10193 },  -- Mana Shield
    [1495] = { 1495, 14269, 14270, 14271 },  -- Mongoose Bite
    [1499] = { 1499, 14310, 14311 },  -- Freezing Trap
    [1510] = { 1510, 14294, 14295 },  -- Volley
    [1513] = { 1513, 14326, 14327 },  -- Scare Beast
    [1515] = { 1515, 13481, 13535 },  -- Tame Beast
    [1714] = { 1714, 11719 },  -- Curse of Tongues
    [1715] = { 1715, 7372, 7373 },  -- Hamstring
    [1742] = { 1742, 1753, 1754, 1755, 1756, 16697 },  -- Cower
    [1747] = { 1747, 1748, 1749, 1750, 1751, 16698 },  -- Cower
    [1752] = { 1752, 1757, 1758, 1759, 1760, 8621, 11293, 11294 },  -- Sinister Strike
    [1766] = { 1766, 1767, 1768, 1769 },  -- Kick
    [1776] = { 1776, 1777, 8629, 11285, 11286 },  -- Gouge
    [1784] = { 1784, 1785, 1786, 1787 },  -- Stealth
    [1822] = { 1822, 1823, 1824, 9904 },  -- Rake
    [1850] = { 1850, 9821 },  -- Dash
    [1853] = { 1853, 14922, 14923, 14924, 14925, 14926, 14927 },  -- Growl
    [1856] = { 1856, 1857 },  -- Vanish
    [1943] = { 1943, 8639, 8640, 11273, 11274, 11275 },  -- Rupture
    [1949] = { 1949, 11683, 11684 },  -- Hellfire
    [1966] = { 1966, 6768, 8637, 11303, 25302 },  -- Feint
    [2006] = { 2006, 2010, 10880, 10881, 20770 },  -- Resurrection
    [2008] = { 2008, 20609, 20610, 20776, 20777 },  -- Ancestral Spirit
    [2050] = { 2050, 2052, 2053 },  -- Lesser Heal
    [2054] = { 2054, 2055, 6063, 6064 },  -- Heal
    [2060] = { 2060, 10963, 10964, 10965, 25314 },  -- Greater Heal
    [2061] = { 2061, 9472, 9473, 9474, 10915, 10916, 10917 },  -- Flash Heal
    [2096] = { 2096, 10909 },  -- Mind Vision
    [2098] = { 2098, 6760, 6761, 6762, 8623, 8624, 11299, 11300, 31016 },  -- Eviscerate
    [2120] = { 2120, 2121, 8422, 8423, 10215, 10216 },  -- Flamestrike
    [2362] = { 2362, 17727, 17728 },  -- Create Spellstone
    [2382] = { 2382, 9125 },  -- Generic
    [2637] = { 2637, 18657, 18658 },  -- Hibernate
    [2649] = { 2649, 14916, 14917, 14918, 14919, 14920, 14921 },  -- Growl
    [2652] = { 2652, 2943, 19249, 19261, 19251, 19262, 19252, 19264, 19253, 19265, 19254, 19266 },  -- Touch of Weakness
    [2812] = { 2812, 10318 },  -- Holy Wrath
    [2878] = { 2878, 5627, 10326 },  -- Turn Undead
    [2908] = { 2908, 8955, 9901 },  -- Soothe Animal
    [2912] = { 2912, 8949, 8950, 8951, 9875, 9876, 25298 },  -- Starfire
    [2944] = { 2944, 19276, 19277, 19278, 19279, 19280 },  -- Devouring Plague
    [2948] = { 2948, 8444, 8445, 8446, 10205, 10206, 10207 },  -- Scorch
    [2974] = { 2974, 14267, 14268 },  -- Wing Clip
    [2975] = { 2975, 2976, 2977, 2980, 2981, 2982, 3666, 3667 },  -- Claw
    [2983] = { 2983, 8696, 11305 },  -- Sprint
    [3034] = { 3034, 14279, 14280 },  -- Viper Sting
    [3044] = { 3044, 14281, 14282, 14283, 14284, 14285, 14286, 14287 },  -- Arcane Shot
    [3127] = { 3127, 18848 },  -- Parry
    [3365] = { 3365, 6247, 6477, 6478, 21651 },  -- Opening
    [3599] = { 3599, 6363, 6364, 6365, 10437, 10438 },  -- Searing Totem
    [3674] = { 3674, 14296 },  -- Black Arrow
    [4187] = { 4187, 4188, 4189, 4190, 4191, 4192, 4193, 4194, 5041, 5042 },  -- Great Stamina
    [4195] = { 4195, 4196, 4197, 4198, 4199, 4200, 4201, 4202, 5048, 5049 },  -- Great Stamina
    [5138] = { 5138, 6226, 11703, 11704 },  -- Drain Mana
    [5143] = { 5143, 5144, 5145, 8416, 8417, 10211, 10212, 25345 },  -- Arcane Missiles
    [5171] = { 5171, 6774 },  -- Slice and Dice
    [5176] = { 5176, 5177, 5178, 5179, 5180, 6780, 8905, 9912 },  -- Wrath
    [5185] = { 5185, 5186, 5187, 5188, 5189, 6778, 8903, 9758, 9888, 9889, 25297 },  -- Healing Touch
    [5211] = { 5211, 6798, 8983 },  -- Bash
    [5215] = { 5215, 6783, 9913 },  -- Prowl
    [5221] = { 5221, 6800, 8992, 9829, 9830 },  -- Shred
    [5301] = { 5301, 13358, 16092 },  -- Defensive State (DND)
    [5394] = { 5394, 6375, 6377, 10462, 10463 },  -- Healing Stream Totem
    [5484] = { 5484, 17928 },  -- Howl of Terror
    [5487] = { 5487, 9634 },  -- Bear Form
    [5570] = { 5570, 24974, 24975, 24976, 24977 },  -- Insect Swarm
    [5675] = { 5675, 10495, 10496, 10497 },  -- Mana Spring Totem
    [5676] = { 5676, 17919, 17920, 17921, 17922, 17923 },  -- Searing Pain
    [5730] = { 5730, 6390, 6391, 6392, 10427, 10428 },  -- Stoneclaw Totem
    [5740] = { 5740, 6219, 11677, 11678 },  -- Rain of Fire
    [5782] = { 5782, 6213, 6215 },  -- Fear
    [5857] = { 5857, 11681, 11682 },  -- Hellfire Effect
    [6117] = { 6117, 22782, 22783 },  -- Mage Armor
    [6143] = { 6143, 8461, 8462, 10177, 28609 },  -- Frost Ward
    [6201] = { 6201, 6202, 5699, 11729, 11730 },  -- Create Healthstone
    [6229] = { 6229, 11739, 11740, 28610 },  -- Shadow Ward
    [6233] = { 6233, 6246, 21652 },  -- Closing
    [6280] = { 6280, 6281, 6282, 6283, 6286 },  -- Pet Hardiness
    [6311] = { 6311, 6314, 6315, 6316, 6317 },  -- Pet Aggression
    [6328] = { 6328, 6331, 6332, 6333, 6334 },  -- Pet Recovery
    [6343] = { 6343, 8198, 8204, 8205, 11580, 11581 },  -- Thunder Clap
    [6353] = { 6353, 17924 },  -- Soul Fire
    [6366] = { 6366, 17951, 17952, 17953 },  -- Create Firestone
    [6443] = { 6443, 6444, 6445, 6446, 6447 },  -- Pet Resistance
    [6552] = { 6552, 6554 },  -- Pummel
    [6572] = { 6572, 6574, 7379, 11600, 11601, 25288 },  -- Revenge
    [6673] = { 6673, 5242, 6192, 11549, 11550, 11551, 25289 },  -- Battle Shout
    [6770] = { 6770, 2070, 11297 },  -- Sap
    [6785] = { 6785, 6787, 9866, 9867 },  -- Ravage
    [6789] = { 6789, 17925, 17926 },  -- Death Coil
    [6807] = { 6807, 6808, 6809, 8972, 9745, 9880, 9881 },  -- Maul
    [6896] = { 6896, 17461 },  -- Black Ram
    [6940] = { 6940, 20729 },  -- Blessing of Sacrifice
    [7001] = { 7001, 27873, 27874 },  -- Lightwell Renew
    [7294] = { 7294, 10298, 10299, 10300, 10301 },  -- Retribution Aura
    [7302] = { 7302, 7320, 10219, 10220 },  -- Ice Armor
    [7328] = { 7328, 10322, 10324, 20772, 20773 },  -- Redemption
    [7370] = { 7370, 26184, 26185, 26186, 26202, 28343 },  -- Charge
    [7384] = { 7384, 7887, 11584, 11585 },  -- Overpower
    [7386] = { 7386, 7405, 8380, 11596, 11597 },  -- Sunder Armor
    [8004] = { 8004, 8008, 8010, 10466, 10467, 10468 },  -- Lesser Healing Wave
    [8017] = { 8017, 8018, 8019, 10399, 16314, 16315, 16316 },  -- Rockbiter Weapon
    [8024] = { 8024, 8027, 8030, 16339, 16341, 16342 },  -- Flametongue Weapon
    [8033] = { 8033, 8038, 10456, 16355, 16356 },  -- Frostbrand Weapon
    [8042] = { 8042, 8044, 8045, 8046, 10412, 10413, 10414 },  -- Earth Shock
    [8050] = { 8050, 8052, 8053, 10447, 10448, 29228 },  -- Flame Shock
    [8056] = { 8056, 8058, 10472, 10473 },  -- Frost Shock
    [8071] = { 8071, 8154, 8155, 10406, 10407, 10408 },  -- Stoneskin Totem
    [8075] = { 8075, 8160, 8161, 10442, 25361 },  -- Strength of Earth Totem
    [8092] = { 8092, 8102, 8103, 8104, 8105, 8106, 10945, 10946, 10947 },  -- Mind Blast
    [8122] = { 8122, 8124, 10888, 10890 },  -- Psychic Scream
    [8129] = { 8129, 8131, 10874, 10875, 10876 },  -- Mana Burn
    [8181] = { 8181, 10478, 10479 },  -- Frost Resistance Totem
    [8184] = { 8184, 10537, 10538 },  -- Fire Resistance Totem
    [8190] = { 8190, 10585, 10586, 10587 },  -- Magma Totem
    [8227] = { 8227, 8249, 10526, 16387 },  -- Flametongue Totem
    [8232] = { 8232, 8235, 10486, 16362 },  -- Windfury Weapon
    [8512] = { 8512, 10613, 10614 },  -- Windfury Totem
    [8647] = { 8647, 8649, 8650, 11197, 11198 },  -- Expose Armor
    [8676] = { 8676, 8724, 8725, 11267, 11268, 11269 },  -- Ambush
    [8835] = { 8835, 10627, 25359 },  -- Grace of Air Totem
    [8921] = { 8921, 8924, 8925, 8926, 8927, 8928, 8929, 9833, 9834, 9835 },  -- Moonfire
    [8936] = { 8936, 8938, 8939, 8940, 8941, 9750, 9856, 9857, 9858 },  -- Regrowth
    [8998] = { 8998, 9000, 9892 },  -- Cower
    [9005] = { 9005, 9823, 9827 },  -- Pounce
    [9007] = { 9007, 9824, 9826 },  -- Pounce Bleed
    [9035] = { 9035, 19281, 19282, 19283, 19284, 19285 },  -- Hex of Weakness
    [9484] = { 9484, 9485, 10955 },  -- Shackle Undead
    [9799] = { 9799, 25997 },  -- Eye for an Eye
    [10595] = { 10595, 10600, 10601 },  -- Nature Resistance Totem
    [10795] = { 10795, 17450, 436289 },  -- Ivory Raptor
    [10797] = { 10797, 19296, 19299, 19302, 19303, 19304, 19305 },  -- Starshards
    [11071] = { 11071, 12494 },  -- Frostbite
    [11103] = { 11103, 12355 },  -- Impact
    [11113] = { 11113, 13018, 13019, 13020, 13021 },  -- Blast Wave
    [11366] = { 11366, 12505, 12522, 12523, 12524, 12525, 12526, 18809 },  -- Pyroblast
    [11426] = { 11426, 13031, 13032, 13033 },  -- Ice Barrier
    [12281] = { 12281, 12284, 12700 },  -- Weaponmaster
    [12288] = { 12288, 12707, 12708 },  -- Improved Pummel
    [12290] = { 12290, 12963 },  -- Improved Overpower
    [12294] = { 12294, 21551, 21552, 21553 },  -- Mortal Strike
    [12302] = { 12302, 12765 },  -- Improved Taunt
    [12307] = { 12307, 12944, 12945 },  -- Improved Shield Block
    [12318] = { 12318, 12857, 12858, 12860, 12861 },  -- Improved Battle Shout
    [12319] = { 12319, 12966 },  -- Flurry
    [12322] = { 12322, 12964 },  -- Unbridled Wrath
    [12324] = { 12324, 12876, 12877, 12878, 12879 },  -- Improved Demoralizing Shout
    [12327] = { 12327, 12886 },  -- Improved Challenging Shout
    [12695] = { 12695, 12696 },  -- Charge Rage Bonus Effect
    [12723] = { 12723, 12292 },  -- Sweeping Strikes
    [12976] = { 12976, 12975 },  -- Last Stand
    [13161] = { 13161, 1299445, 1299446, 1299447 },  -- Aspect of the Beast
    [13165] = { 13165, 14318, 14319, 14320, 14321, 14322, 25296 },  -- Aspect of the Hawk
    [13707] = { 13707, 13966, 13967, 13968, 13969 },  -- Fist Weapon Specialization
    [13709] = { 13709, 13706, 13960 },  -- Hack and Slash
    [13795] = { 13795, 13797, 14298, 14302, 14299, 14303, 14300, 14304, 14301, 14305 },  -- Immolation Trap
    [13812] = { 13812, 14314, 14315 },  -- Explosive Trap Effect
    [13813] = { 13813, 14316, 14317 },  -- Explosive Trap
    [13819] = { 13819, 1279399 },  -- Summon Warhorse
    [13896] = { 13896, 19271, 19273, 19274, 19275 },  -- Feedback
    [13908] = { 13908, 19236, 19238, 19240, 19241, 19242, 19243 },  -- Desperate Prayer
    [13976] = { 13976, 13977 },  -- Initiative
    [14076] = { 14076, 14094, 14095 },  -- Improved Sap
    [14749] = { 14749, 14767 },  -- Improved Power Word: Fortitude
    [14752] = { 14752, 14818, 14819, 27841 },  -- Divine Spirit
    [14914] = { 14914, 15262, 15263, 15264, 15265, 15266, 15267, 15261 },  -- Holy Fire
    [15107] = { 15107, 15111, 15112 },  -- Windwall Totem
    [15237] = { 15237, 23455, 15430, 23458, 15431, 23459, 27799, 27803, 27800, 27804, 27801, 27805 },  -- Holy Nova
    [15268] = { 15268, 15323, 15324, 15325, 15326 },  -- Blackout
    [15407] = { 15407, 17311, 17312, 17313, 17314, 18807 },  -- Mind Flay
    [15780] = { 15780, 17453 },  -- Green Mechanostrider
    [16060] = { 16060, 436329, 463006 },  -- Golden Sabercat
    [16180] = { 16180, 16196, 16198 },  -- Nature's Guidance
    [16190] = { 16190, 17354, 17359, 1325256 },  -- Mana Tide Totem
    [16253] = { 16253, 16298, 16299, 16300, 16301 },  -- Shield Specialization
    [16259] = { 16259, 16295 },  -- Enhancing Totems
    [16579] = { 16579, 16580, 16581, 16582 },  -- Lightning Mastery
    [16689] = { 16689, 16810, 16811, 16812, 16813, 17329 },  -- Nature's Grasp
    [16836] = { 16836, 16839, 16840 },  -- Improved Thorns
    [16858] = { 16858, 16859, 16860, 16861, 16862 },  -- Feral Aggression
    [16902] = { 16902, 16903, 16904, 16905, 16906 },  -- Natural Weapons
    [16914] = { 16914, 17401, 17402 },  -- Hurricane
    [17050] = { 17050, 17051, 17053, 17054, 17055 },  -- Improved Mark of the Wild
    [17079] = { 17079, 17082 },  -- Improved Enrage
    [17254] = { 17254, 17262, 17263, 17264, 17265, 17266, 17267, 17268 },  -- Bite
    [17458] = { 17458, 463005 },  -- Fluorescent Green Mechanostrider
    [17815] = { 17815, 17833, 17834, 17835, 17836 },  -- Improved Immolate
    [17877] = { 17877, 18867, 18868, 18869, 18870, 18871 },  -- Shadowburn
    [18126] = { 18126, 18127 },  -- Improved Firebolt
    [18128] = { 18128, 18129 },  -- Improved Lash of Pain
    [18137] = { 18137, 28377, 19308, 28378, 19309, 28379, 19310, 28380, 19311, 28381, 19312, 28382 },  -- Shadowguard
    [18179] = { 18179, 18180, 18181 },  -- Improved Curse of Weakness
    [18265] = { 18265, 18879, 18880, 18881 },  -- Siphon Life
    [18310] = { 18310, 18311, 18312, 18313 },  -- Improved Curse of Exhaustion
    [18544] = { 18544, 18547, 18548, 18549, 18550 },  -- Force of Will
    [18692] = { 18692, 18693 },  -- Improved Healthstone
    [18767] = { 18767, 18768 },  -- Improved Firestone
    [18774] = { 18774, 18775 },  -- Improved Spellstone
    [18821] = { 18821, 18822, 18823, 18824, 18825 },  -- Improved Subjugate Demon
    [19151] = { 19151, 19152, 19153 },  -- Humanoid Slaying
    [19184] = { 19184, 19185 },  -- Entrapment
    [19286] = { 19286, 19287 },  -- Improved Feign Death
    [19306] = { 19306, 1242634, 20909, 20910 },  -- Counterattack
    [19381] = { 19381, 19382, 19383, 19384, 19385 },  -- Melee Specialization
    [19434] = { 19434, 20900, 20901, 20902, 20903, 20904 },  -- Aimed Shot
    [19557] = { 19557, 19558 },  -- Improved Eyes of the Beast
    [19572] = { 19572, 24406 },  -- Improved Mend Pet
    [19577] = { 19577, 24394 },  -- Intimidation
    [19578] = { 19578, 24529, 1310725 },  -- Spirit Bond
    [19740] = { 19740, 19834, 19835, 19836, 19837, 19838, 25291 },  -- Blessing of Might
    [19742] = { 19742, 19850, 19852, 19853, 19854, 25290 },  -- Blessing of Wisdom
    [19870] = { 19870, 19871 },  -- Improved Intimidating Shout
    [19876] = { 19876, 19895, 19896 },  -- Shadow Resistance Aura
    [19888] = { 19888, 19897, 19898 },  -- Frost Resistance Aura
    [19891] = { 19891, 19899, 19900 },  -- Fire Resistance Aura
    [19977] = { 19977, 19978, 19979 },  -- Blessing of Light
    [20042] = { 20042, 20045, 20046, 20047, 20048 },  -- Improved Blessing of Might
    [20043] = { 20043, 20190 },  -- Aspect of the Wild
    [20091] = { 20091, 20092 },  -- Improved Retribution Aura
    [20148] = { 20148, 20149, 20150 },  -- Shield Specialization
    [20154] = { 20154, 20287, 20288, 20289, 20290, 20291, 20292, 20293, 21084 },  -- Seal of Righteousness
    [20165] = { 20165, 20347, 20348, 20349 },  -- Seal of Light
    [20166] = { 20166, 20356, 20357 },  -- Seal of Wisdom
    [20183] = { 20183, 20411, 20412, 20413, 20414 },  -- Judgement of Fury
    [20185] = { 20185, 20344, 20345, 20346 },  -- Judgement of Light
    [20186] = { 20186, 20354, 20355 },  -- Judgement of Wisdom
    [20187] = { 20187, 20280, 20281, 20282, 20283, 20284, 20285, 20286 },  -- Judgement of Righteousness
    [20188] = { 20188, 20300, 20301, 20302, 20303 },  -- Judgement of the Crusader
    [20244] = { 20244, 20245 },  -- Improved Blessing of Wisdom
    [20249] = { 20249, 20250, 20251 },  -- Improved Flash of Light
    [20252] = { 20252, 20616, 20617 },  -- Intercept
    [20335] = { 20335, 20336, 20337 },  -- Improved Seal of the Crusader
    [20359] = { 20359, 20360, 20361 },  -- Lasting Judgement
    [20375] = { 20375, 20915, 20918, 20919, 20920 },  -- Seal of Command
    [20425] = { 20425, 20467, 20962, 20963, 20961, 20964, 20965, 20967, 20966, 20968 },  -- Judgement of Command
    [20484] = { 20484, 20739, 20742, 20747, 20748 },  -- Rebirth
    [20591] = { 20591, 1259802, 1259803 },  -- Expansive Mind
    [20608] = { 20608, 21169 },  -- Reincarnation
    [20647] = { 20647, 5308, 20658, 20660, 20661, 20662 },  -- Execute
    [20736] = { 20736, 14274, 15629, 15630, 15631, 15632 },  -- Distracting Shot
    [20925] = { 20925, 20927, 20928 },  -- Holy Shield
    [21082] = { 21082, 20162, 20305, 20306, 20307, 20308 },  -- Seal of the Crusader
    [21562] = { 21562, 21564 },  -- Prayer of Fortitude
    [21849] = { 21849, 21850 },  -- Gift of the Wild
    [22568] = { 22568, 22827, 22828, 22829, 31018 },  -- Ferocious Bite
    [22845] = { 22845, 22842 },  -- Frenzied Regeneration
    [23100] = { 23100, 23111, 23112 },  -- Dash
    [23146] = { 23146, 23149, 23150 },  -- Dive
    [23163] = { 23163, 23166, 23167 },  -- Harass
    [23759] = { 23759, 23760, 23761, 23762, 23785 },  -- Master Demonologist
    [23881] = { 23881, 23892, 23893, 23894 },  -- Bloodthirst
    [23922] = { 23922, 23923, 23924, 23925 },  -- Shield Slam
    [23992] = { 23992, 24439, 24444, 24445 },  -- Fire Resistance
    [24118] = { 24118, 24119, 24120, 1299332 },  -- Lacerate
    [24275] = { 24275, 24274, 24239 },  -- Hammer of Wrath
    [24294] = { 24294, 24295 },  -- Monster Slaying
    [24424] = { 24424, 24580, 24581, 24582 },  -- Demoralizing Screech
    [24440] = { 24440, 24441, 24463, 24464 },  -- Fire Resistance
    [24446] = { 24446, 24447, 24448, 24449 },  -- Frost Resistance
    [24451] = { 24451, 24454, 24455 },  -- Prowl
    [24475] = { 24475, 24476, 24477, 24478 },  -- Frost Resistance
    [24488] = { 24488, 24505, 24506, 24507 },  -- Shadow Resistance
    [24490] = { 24490, 24514, 24515, 24516 },  -- Shadow Resistance
    [24492] = { 24492, 24502, 24503, 24504 },  -- Nature Resistance
    [24493] = { 24493, 24497, 24500, 24501 },  -- Arcane Resistance
    [24494] = { 24494, 24511, 24512, 24513 },  -- Nature Resistance
    [24495] = { 24495, 24508, 24509, 24510 },  -- Arcane Resistance
    [24545] = { 24545, 24549, 24550, 24551, 24552, 24553, 24554, 24555, 24629, 24630 },  -- Natural Armor
    [24547] = { 24547, 24556, 24557, 24558, 24559, 24560, 24561, 24562, 24631, 24632 },  -- Natural Armor
    [24584] = { 24584, 24588, 24589, 24641 },  -- Scorpid Poison
    [24599] = { 24599, 24607, 24608, 24609 },  -- Furious Howl
    [24845] = { 24845, 25013, 25014, 25015, 25016, 25017 },  -- Lightning Breath
    [25675] = { 25675, 25858, 25859, 434508 },  -- Reindeer
    [25782] = { 25782, 25916 },  -- Greater Blessing of Might
    [25863] = { 25863, 26655 },  -- Summon Black Qiraji Battle Tank
    [25894] = { 25894, 25918 },  -- Greater Blessing of Wisdom
    [26094] = { 26094, 26189, 26190, 1264456 },  -- Thunderstomp
    [26573] = { 26573, 20116, 20922, 20923, 20924 },  -- Consecration
    [27811] = { 27811, 27813 },  -- Blessed Recovery
    [29074] = { 29074, 29077 },  -- Master of Elements
    [29082] = { 29082, 29084, 29086, 29087, 29088 },  -- Weapon Mastery
    [29189] = { 29189, 29191 },  -- Healing Grace
    [29192] = { 29192, 29193 },  -- Improved Weapon Totems
    [29442] = { 29442, 29441 },  -- Magic Absorption
    [30160] = { 30160, 30165 },  -- Elemental Devastation
    [33388] = { 33388, 33391 },  -- Apprentice Riding
    [370637] = { 370637, 381598 },  -- Summon Skeletal Steed
    [400574] = { 400574, 1239696, 1239697, 1239699, 1239700 },  -- Arcane Blast
    [400613] = { 400613, 400614 },  -- Living Bomb
    [400616] = { 400616, 400618, 400619, 400620, 400621, 400622, 400623, 2136, 2137, 2138, 8412, 8413, 10197, 10199 },  -- Fire Blast
    [401502] = { 401502, 1237312, 1237313 },  -- Frostfire Bolt
    [401556] = { 401556, 401558 },  -- Living Flame
    [401859] = { 401859, 401863, 1240826, 1240827 },  -- Prayer of Mending
    [401937] = { 401937, 1240770, 1240771, 1240772, 1240773, 1240774 },  -- Binding Heal
    [401955] = { 401955, 1309595, 1309633, 1309635, 1309636 },  -- Shadow Word: Death
    [402174] = { 402174, 402284, 402289, 1240720, 1240723, 1240727, 1240721, 1240724, 1240730, 1316991, 1316993, 1316995 },  -- Penance
    [403677] = { 403677, 403685, 403686, 403687, 403688, 403689 },  -- Drain Life
    [403835] = { 403835, 403839, 403840, 403841, 403842, 403843, 403844, 403848, 403851, 403852 },  -- Shadow Cleave
    [407627] = { 407627, 25780 },  -- Righteous Fury
    [407778] = { 407778, 407784 },  -- Divine Storm
    [407798] = { 407798, 407799 },  -- Seal of Martyrdom
    [407995] = { 407995, 1238069, 1238070, 1238073 },  -- Primal Bite
    [408120] = { 408120, 1238214, 1238215 },  -- Wild Growth
    [408124] = { 408124, 408245 },  -- Lifebloom
    [408341] = { 408341, 408342, 408343, 408344, 408345 },  -- Fire Nova
    [408490] = { 408490, 408491, 1238299, 1238300, 1238373, 1238376, 1326047 },  -- Lava Burst
    [408514] = { 408514, 408519 },  -- Earth Shield
    [408521] = { 408521, 1239242, 1239243 },  -- Riptide
    [409324] = { 409324, 409333, 409337 },  -- Ancestral Guidance
    [409691] = { 409691, 409693, 409748, 409750, 409751, 409752, 409754, 409755, 415335, 415336, 415337, 415338, 415340, 415341, 415342, 415343, 2973, 14260, 14261, 14262, 14263, 14264, 14265, 14266 },  -- Raptor Strike
    [412020] = { 412020, 19750, 19993, 19939, 1313342, 19940, 1313343, 19941, 1313344, 19942, 1313345, 19943, 1313346 },  -- Flash of Light
    [412758] = { 412758, 1293812, 1293813 },  -- Incinerate
    [413259] = { 413259, 413260 },  -- Mind Sear
    [414647] = { 414647, 414644, 1235826, 1235827 },  -- Lacerate
    [414684] = { 414684, 414687, 414689 },  -- Sunfire
    [415068] = { 415068, 415069, 415070, 415071, 415072, 415073 },  -- Exorcism
    [415236] = { 415236, 415242 },  -- Healing Rain
    [417045] = { 417045, 5217 },  -- Tiger's Fury
    [425012] = { 425012, 425013 },  -- Poisoned Knife
    [425268] = { 425268, 425269, 425270, 425271, 425272, 425273, 425274, 425275, 425276, 425277, 139, 6074, 6075, 6076, 6077, 6078, 10927, 10928, 10929, 25315 },  -- Renew
    [425728] = { 425728, 425729, 425730, 425732, 425733, 425734, 425735, 425736, 425737, 1978, 13549, 13550, 13551, 13552, 13553, 13554, 13555, 25295 },  -- Serpent Sting
    [426241] = { 426241, 426245, 426246, 426247, 426331 },  -- Invocation
    [426320] = { 426320, 426325 },  -- Shadowflame
    [436288] = { 436288, 463007 },  -- Mottled Blood Raptor
    [437138] = { 437138, 1237948, 1237949, 1237950, 1237951 },  -- Revive
    [439748] = { 439748, 439753, 439756 },  -- Starfall
    [440802] = { 440802, 440809 },  -- Frozen Orb
    [440892] = { 440892, 1311676, 1311677, 1311680 },  -- Curse of the Elements
    [444680] = { 444680, 444682 },  -- Lava Breath
    [461607] = { 461607, 1237632 },  -- Divine Steed
    [468766] = { 468766, 5504, 5505, 5506, 6127, 10138, 10139, 10140 },  -- Conjure Water
    [473848] = { 473848, 473853, 473855 },  -- Summon Light Green Qiraji Battle Tank
    [473858] = { 473858, 473859, 473860 },  -- Summon Dark Blue Qiraji Battle Tank
    [473869] = { 473869, 473870, 473871 },  -- Summon Light Blue Qiraji Battle Tank
    [473874] = { 473874, 473875, 473877 },  -- Summon Orange Qiraji Battle Tank
    [473882] = { 473882, 473886, 473887 },  -- Summon Twilight Qiraji Battle Tank
    [1217142] = { 1217142, 1217143, 1217144 },  -- Summon Flawless Yellow Qiraji Battle Tank
    [1217146] = { 1217146, 1217147, 1217148 },  -- Summon Flawless Green Qiraji Battle Tank
    [1217150] = { 1217150, 1217151, 1217152 },  -- Summon Flawless Blue Qiraji Battle Tank
    [1217154] = { 1217154, 1217155, 1217156 },  -- Summon Flawless Red Qiraji Battle Tank
    [1240193] = { 1240193, 1464, 8820, 11604, 11605 },  -- Slam
    [1259812] = { 1259812, 1259813, 1259817, 1259821, 1259823 },  -- Eureka!
    [1260189] = { 1260189, 1260201 },  -- Touch of the Grave
    [1264727] = { 1264727, 1264729, 1264730, 1264731, 1264732 },  -- Swipe
    [1264745] = { 1264745, 1264749, 1264750, 1264751, 1264752 },  -- Pinch
    [1264937] = { 1264937, 1264939, 1264970, 1264971, 1264972 },  -- Dismember
    [1265043] = { 1265043, 1265045, 1265046, 1265047, 1265048 },  -- Tendon Rip
    [1265059] = { 1265059, 1265060, 1265061, 1265062, 1265064 },  -- Mine!
    [1265831] = { 1265831, 1265833, 1265834, 1265835, 1265836 },  -- Savage Rend
    [1265887] = { 1265887, 1265888, 1265890, 1265891, 1265892 },  -- Web
    [1265907] = { 1265907, 1265908, 1265909, 1265911, 1265913 },  -- Dust Cloud
    [1277324] = { 1277324, 1277325, 1277326, 1277327, 1277328 },  -- Dark Sacrifice
    [1277331] = { 1277331, 1277332, 1277333, 1277334, 1277335 },  -- Chastise
    [1277370] = { 1277370, 1277371, 1277372, 1277374, 1277376, 1277377, 1277378 },  -- Divine Grace
    [1277462] = { 1277462, 1277634, 1277638, 1277639, 1277640 },  -- Contingency Plan
    [1293241] = { 1293241, 1293525, 1293526, 1293527 },  -- Summon Hawk
    [1293817] = { 1293817, 1293818, 17962, 18930, 18931, 18932 },  -- Conflagrate
    [1296017] = { 1296017, 1309965, 1309973, 1310029, 1310030 },  -- Comprehend Scroll
    [1299346] = { 1299346, 1299348, 19506, 20905, 20906 },  -- Trueshot Aura
    [1310687] = { 1310687, 1310785, 1310786 },  -- Sniper Shot
    [1310705] = { 1310705, 1310706, 1310707, 399960, 399961, 1241585, 1241588, 1241586, 1241590, 399956, 1241582, 1241584 },  -- Mutilate
    [1310911] = { 1310911, 1311590, 1311595 },  -- Light's Vigil
    [1311606] = { 1311606, 20473, 25912, 25914, 20929, 25911, 25913, 20930, 25902, 25903 },  -- Holy Shock
    [1311649] = { 1311649, 1311656, 20163, 20419, 20421, 20422, 20423 },  -- Seal of Fury
    [1312002] = { 1312002, 400640, 1240044, 1240045, 1240046, 1240047 },  -- Ice Lance
    [1326053] = { 1326053, 1326054, 1326055 },  -- Frost Blast
    [1326079] = { 1326079, 1326080, 1326081, 1326082 },  -- Arcane Wrath
}
local POTION_IDS = {
    118,  -- Minor Healing Potion
    858,  -- Lesser Healing Potion
    929,  -- Healing Potion
    1450,  -- Potion of Fervor
    1710,  -- Greater Healing Potion
    2455,  -- Minor Mana Potion
    2456,  -- Minor Rejuvenation Potion
    2459,  -- Swiftness Potion
    3384,  -- Minor Magic Resistance Potion
    3385,  -- Lesser Mana Potion
    3387,  -- Limited Invulnerability Potion
    3827,  -- Mana Potion
    3928,  -- Superior Healing Potion
    4596,  -- Minor Discolored Healing Potion
    4623,  -- Lesser Stoneshield Potion
    5631,  -- Rage Potion
    5633,  -- Great Rage Potion
    5634,  -- Free Action Potion
    6048,  -- Shadow Protection Potion
    6049,  -- Fire Protection Potion
    6050,  -- Frost Protection Potion
    6051,  -- Holy Protection Potion
    6052,  -- Nature Protection Potion
    6149,  -- Greater Mana Potion
    9030,  -- Restorative Potion
    9036,  -- Magic Resistance Potion
    9144,  -- Wildvine Potion
    13442,  -- Mighty Rage Potion
    13443,  -- Superior Mana Potion
    13444,  -- Major Mana Potion
    13446,  -- Major Healing Potion
    13455,  -- Greater Stoneshield Potion
    13456,  -- Greater Frost Protection Potion
    13457,  -- Greater Fire Protection Potion
    13458,  -- Greater Nature Protection Potion
    13459,  -- Greater Shadow Protection Potion
    13460,  -- Greater Holy Protection Potion
    13461,  -- Greater Arcane Protection Potion
    13462,  -- Purification Potion
    17348,  -- Major Healing Draught
    17349,  -- Superior Healing Draught
    17351,  -- Major Mana Draught
    17352,  -- Superior Mana Draught
    18253,  -- Major Rejuvenation Potion
    18839,  -- Combat Healing Potion
    18841,  -- Combat Mana Potion
    20008,  -- Living Action Potion
    223912,  -- Purification Potion
    223913,  -- Major Healing Potion
    223914,  -- Greater Healing Potion
    241650,  -- Major Discolored Healing Potion
    247239,  -- Lesser Discolored Healing Potion
    247240,  -- Discolored Healing Potion
    247241,  -- Greater Discolored Healing Potion
    247242,  -- Superior Discolored Healing Potion
    250327,  -- Potion of Predatory Senses
    268881,  -- Perishable Minor Healing Potion
    268882,  -- Perishable Lesser Healing Potion
    268883,  -- Perishable Healing Potion
    282011,  -- Restored Healing Potion
    282013,  -- Restored Mana Potion
    287966,  -- Minor Healing Potion
    287967,  -- Lesser Healing Potion
    287968,  -- Minor Mana Potion
    287969,  -- Lesser Mana Potion
    287975,  -- Swiftness Potion
    287976,  -- Free Action Potion
    287977,  -- Greater Healing Potion
}

-- id -> its family, for every id but the one that keys RANK_FAMILIES.
local reverse

-- The ranks of the spell's family, lowest first, or nil.
local function FamilyOf(id)
    if type(id) ~= "number" then return nil end
    local family = RANK_FAMILIES[id]
    if family then return family end
    if not reverse then
        reverse = {}
        for _, ranks in pairs(RANK_FAMILIES) do
            for i = 2, #ranks do reverse[ranks[i]] = ranks end
        end
    end
    return reverse[id]
end

-- The highest rank isKnown accepts, walking down; for an id in no family,
-- the id itself when known.
local function HighestKnown(id, isKnown)
    local family = FamilyOf(id)
    if not family then
        if type(id) == "number" and isKnown(id) == true then return id end
        return nil
    end
    for i = #family, 1, -1 do
        if isKnown(family[i]) == true then return family[i] end
    end
    return nil
end

local function SameFamily(a, b)
    if type(a) ~= "number" or type(b) ~= "number" then return false end
    if a == b then return true end
    local family = FamilyOf(a)
    return family ~= nil and family == FamilyOf(b)
end

-- Each id as its highest known rank, unknown ones dropped, each once,
-- sorted. A new table per call.
local function Collapse(ids, isKnown)
    local out, seen = {}, {}
    for i = 1, #ids do
        local rank = HighestKnown(ids[i], isKnown)
        if rank and not seen[rank] then
            seen[rank] = true
            out[#out + 1] = rank
        end
    end
    table.sort(out)
    return out
end

KE.CombatDataForever = {
    RANK_FAMILIES = RANK_FAMILIES,
    POTION_IDS = POTION_IDS,
    FamilyOf = FamilyOf,
    HighestKnown = HighestKnown,
    SameFamily = SameFamily,
    Collapse = Collapse,
}
