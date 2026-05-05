-- ╔══════════════════════════════════════════════════════════╗
-- ║  Defaults.lua                                            ║
-- ║  Purpose: Default configuration templates for all        ║
-- ║           modules, positions, fonts, and backdrops.      ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)

---------------------------------------------------------------------------------
-- Default Templates
---------------------------------------------------------------------------------

local function DefaultPosition(xOff, yOff)
    return {
        AnchorFrom = "CENTER",
        AnchorTo = "CENTER",
        XOffset = xOff or 0,
        YOffset = yOff or 0,
    }
end

local function DefaultFontShadow()
    return {
        Enabled = false,
        OffsetX = 0,
        OffsetY = 0,
        Color = { 0, 0, 0, 0 },
    }
end

local function DefaultBackdrop()
    return {
        Enabled = false,
        Color = { 0, 0, 0, 0.6 },
        BorderColor = { 0, 0, 0, 1 },
        BorderSize = 1,
        bgWidth = 5,
        bgHeight = 5,
    }
end

---------------------------------------------------------------------------------
-- Saved Variables Schema
---------------------------------------------------------------------------------

local Defaults = {
    global = {
        UseGlobalProfile = false,
        GlobalProfile = "Default",

        GUIState = {
            frame = {
                point = nil,
                relativePoint = nil,
                xOffset = nil,
                yOffset = nil,
                width = nil,
                height = nil,
            },
            selectedGroupId = nil,
            selectedTab = nil,
            minimized = false,
        },

        Theme = {
            Mode = "preset",
            Preset = "KitnUI",
            Custom = {},
        },

        -- Map of "Fullname-NormalizedRealm" -> "Nickname".
        -- Global so nicknames persist across characters/profiles.
        -- Realm portion uses GetNormalizedRealmName() (no spaces/apostrophes)
        -- for NSRT-compatible keys if we ever add import/export.
        Nicknames = {},
    },
    profile = {
        -- Global
        ShowChatMessage = true,
        -- Minimap Icon
        Minimap = {
            hide = false,
        },

        -- ElvUI Integration
        UseElvUI = {
            Enabled = true,
        },

        -----------------------------------------------------------------
        -- Combat Modules
        -----------------------------------------------------------------

        CombatTimer = {
            Enabled = false,
            ShowChatMessage = true,
            Format = "MM:SS",
            BracketStyle = "square",
            FontSize = 28,
            FontFace = "Expressway",
            FontOutline = "SOFTOUTLINE",
            FontShadow = DefaultFontShadow(),
            ColorInCombat = { 1, 1, 1, 1 },
            ColorOutOfCombat = { 1, 1, 1, 0.7 },
            anchorFrameType = "UIPARENT",
            ParentFrame = "UIParent",
            Strata = "HIGH",
            Position = DefaultPosition(0, -100),
            SnapToPixelGrid = false,
            Backdrop = DefaultBackdrop(),
        },

        CombatCross = {
            Enabled = false,
            Strata = "HIGH",
            anchorFrameType = "UIPARENT",
            ParentFrame = "UIParent",
            Position = DefaultPosition(0, -10),
            ColorMode = "custom",
            Color = { 0, 1, 0.169, 1 },
            Thickness = 22,
            Outline = true,
            RangeColorMeleeEnabled = false,
            RangeColorRangedEnabled = false,
            OutOfRangeColor = { 1, 0, 0, 1 },
        },

        CombatRes = {
            Enabled = false,
            Strata = "HIGH",
            anchorFrameType = "UIPARENT",
            ParentFrame = "UIParent",
            Position = DefaultPosition(0, -60),
            SnapToPixelGrid = false,
            FontSize = 16,
            FontFace = "Expressway",
            FontOutline = "SOFTOUTLINE",
            TextSpacing = 4,
            GrowthDirection = "RIGHT",
            SeparatorColor = { 1, 1, 1, 1 },
            TimerColor = { 1, 1, 1, 1 },
            ChargeAvailableColor = { 0.3, 1, 0.3, 1 },
            ChargeUnavailableColor = { 1, 0.3, 0.3, 1 },
            Separator = "|",
            SeparatorCharges = "CR:",
            BracketStyle = "square",
            Backdrop = DefaultBackdrop(),
        },

        CombatTexts = {
            Enabled = true,
            Strata = "MEDIUM",
            anchorFrameType = "UIPARENT",
            ParentFrame = "UIParent",
            FontFace = "Expressway",
            FontSize = 16,
            FontOutline = "SOFTOUTLINE",
            Position = DefaultPosition(0, 125),
            SnapToPixelGrid = false,
            Spacing = 0,
            EnterEnabled = true,
            EnterCombatText = "+Combat",
            EnterColor = { 0.902, 0.902, 0.902, 1 },
            ExitEnabled = true,
            ExitCombatText = "-Combat",
            ExitColor = { 0.486, 0.486, 0.486, 1 },
            CombatDuration = 1.5,
            NoTargetEnabled = false,
            NoTargetText = "NO TARGET",
            NoTargetColor = { 1, 0.8, 0, 1 },
            DurabilityEnabled = true,
            DurabilityText = "LOW DURABILITY",
            DurabilityColor = { 1, 0.302, 0.302, 1 },
            DurabilityThreshold = 25,
            InterruptEnabled = true,
            InterruptText = "Interrupted",
            InterruptColor = { 0.624, 0.749, 1, 1 },
            InterruptDuration = 3.0,
            Backdrop = DefaultBackdrop(),
        },

        CursorCircle = {
            Enabled = false,
            Size = 40,
            Texture = "Circle 3",
            Color = { 1, 1, 1, 1 },
            ColorMode = "theme",
            VisibilityMode = "always",
            UseUpdateInterval = false,
            UpdateInterval = 0.016,
            GCD = {
                Mode = "integrated",
                Size = 25,
                Texture = "Circle 5",
                SwipeColorMode = "custom",
                SwipeColor = { 1, 1, 1, 1 },
                Reverse = true,
                HideOutOfCombat = false,
                RingColorMode = "theme",
                RingColor = { 1, 1, 1, 1 },
            },
        },

        PetStatusText = {
            Enabled = true,
            Strata = "MEDIUM",
            anchorFrameType = "UIPARENT",
            ParentFrame = "UIParent",
            Position = DefaultPosition(0, 100),
            SnapToPixelGrid = false,
            FontSize = 26,
            FontFace = "Expressway",
            FontOutline = "SOFTOUTLINE",
            PetMissing = "PET MISSING",
            PetDead = "PET DEAD",
            PetPassive = "PET PASSIVE",
            MissingColor = { 1, 0.82, 0, 1 },       -- #FFD100
            DeadColor = { 1, 0.2, 0.2, 1 },          -- #FF3333
            PassiveColor = { 1, 0, 0.549, 1 },        -- #FF008C
        },

        -- Old GatewayAlert kept for migration (absorbed into RaidNotifications)
        GatewayAlert = {
            Enabled = false,
            Strata = "HIGH",
            anchorFrameType = "UIPARENT",
            ParentFrame = "UIParent",
            Position = DefaultPosition(0, 150),
            FontSize = 16,
            FontFace = "Expressway",
            FontOutline = "SOFTOUTLINE",
            ColorMode = "custom",
            Color = { 0.969, 0.027, 0.945, 1 },  -- #F707F1
            ShowIcons = true,
        },

        RaidNotifications = {
            Enabled = true,
            Strata = "MEDIUM",
            anchorFrameType = "UIPARENT",
            ParentFrame = "UIParent",
            Position = DefaultPosition(0, 350),
            SnapToPixelGrid = false,
            FontSize = 37,
            FontFace = "Expressway",
            FontOutline = "SOFTOUTLINE",
            ColorMode = "custom",
            Color = { 1, 0, 0.549, 1 },  -- #FF008C
            ShowIcons = true,
            RowSpacing = 4,
            AlertDuration = 40,
            GatewayEnabled = true,
            ResetBossEnabled = true,
            LootBossEnabled = true,
            BenchEnabled = true,
        },

        NoMovementAlert = {
            Enabled = true,
            Strata = "MEDIUM",
            anchorFrameType = "UIPARENT",
            ParentFrame = "UIParent",
            Position = DefaultPosition(0, -61),
            FontSize = 16,
            FontFace = "Expressway",
            FontOutline = "OUTLINE",
            ColorMode = "theme",
            Color = { 1, 0.2, 0.2, 1 },
            DisplayFormat = "NO %n - %t",
            MaxCooldown = 30,
        },

        TargetCastbar = {
            Enabled = false,
            Width = 250,
            Height = 20,
            Strata = "HIGH",
            anchorFrameType = "UIPARENT",
            ParentFrame = "UIParent",
            Position = DefaultPosition(0, -200),
            FontSize = 12,
            FontFace = "Expressway",
            FontOutline = "OUTLINE",
            StatusBarTexture = "KitnUI",
            CastingColor = { 1, 0.7, 0, 1 },
            ChannelingColor = { 0, 0.7, 1, 1 },
            EmpoweringColor = { 0.8, 0.4, 1, 1 },
            NotInterruptibleColor = { 0.7, 0.7, 0.7, 1 },
            HideNotInterruptible = false,
            TextColor = { 1, 1, 1, 1 },
            BackdropColor = { 0, 0, 0, 0.8 },
            BorderColor = { 0, 0, 0, 1 },
            HoldTimer = {
                Enabled = true,
                Duration = 0.5,
                InterruptedColor = { 0.1, 0.8, 0.1, 1 },
                SuccessColor = { 0.8, 0.1, 0.1, 1 },
            },
            KickIndicator = {
                Enabled = true,
                ReadyColor = { 0.1, 0.8, 0.1, 1 },
                NotReadyColor = { 0.5, 0.5, 0.5, 1 },
                TickColor = { 1, 1, 1, 1 },
            },
            TargetNames = {
                Enabled = true,
                Anchor = "RIGHT",
                XOffset = 0,
                YOffset = 14,
                FontSize = 12,
            },
        },

        FocusCastbar = {
            Enabled = true,
            Width = 350,
            Height = 30,
            Strata = "HIGH",
            anchorFrameType = "UIPARENT",
            ParentFrame = "UIParent",
            Position = DefaultPosition(0, 220),
            FontSize = 14,
            FontFace = "Expressway",
            FontOutline = "OUTLINE",
            StatusBarTexture = "KitnUI",
            CastingColor = { 0.624, 0.749, 1, 1 },
            ChannelingColor = { 0.624, 0.749, 0.976, 1 },
            EmpoweringColor = { 0.8, 0.4, 1, 1 },
            NotInterruptibleColor = { 0.780, 0.251, 0.251, 1 },
            HideNotInterruptible = true,
            SoundEnabled = true,
            SoundFile = "Interrupt",
            SoundChannel = "Master",
            MuteSoundOnKickCD = true,
            TextColor = { 1, 1, 1, 1 },
            BackdropColor = { 0, 0, 0, 0.8 },
            BorderColor = { 0, 0, 0, 1 },
            HoldTimer = {
                Enabled = true,
                Duration = 0.5,
                InterruptedColor = { 0.102, 0.8, 0.102, 1 },
                SuccessColor = { 0.8, 0.102, 0.102, 1 },
            },
            KickIndicator = {
                Enabled = true,
                ReadyColor = { 0.624, 0.749, 0.976, 1 },
                NotReadyColor = { 0.502, 0.502, 0.502, 1 },
                TickColor = { 0.102, 0.8, 0.102, 1 },
            },
            TargetNames = {
                Enabled = true,
                Anchor = "RIGHT",
                XOffset = 0,
                YOffset = 14,
                FontSize = 13,
            },
            TargetMarker = {
                Enabled = true,
                Size = 26,
                XOffset = -30,
                YOffset = 0,
                Anchor = "LEFT",
            },
        },

        DispelCursor = {
            Enabled = true,
            FontSize = 18,
            TextColor = { 0.235, 0.929, 1, 1 },  -- #3BECFF
            XOffset = 3,
            YOffset = 3,
        },

        RangeChecker = {
            Enabled = false,
            CombatOnly = false,
            UpdateThrottle = 0.1,
            MaxRange = 40,
            ColorOne = { 1, 0, 0 },
            ColorTwo = { 1, 0.42, 0 },
            ColorThree = { 1, 0.82, 0 },
            ColorFour = { 0, 1, 0 },
            FontFace = "Expressway",
            FontSize = 24,
            FontOutline = "SOFTOUTLINE",
            Strata = "HIGH",
            anchorFrameType = "UIPARENT",
            ParentFrame = "UIParent",
            Position = DefaultPosition(0, -140),
            SnapToPixelGrid = false,
        },

        TimeSpiral = {
            Enabled = false,
            IconSize = 40,
            ShowText = true,
            TextLabel = "FREE",
            TextColor = { 0, 1, 0, 1 },
            ShowTimer = true,
            TimerFontFace = "Expressway",
            TimerFontSize = 16,
            TimerFontOutline = "OUTLINE",
            TimerTextColor = { 1, 1, 1, 1 },
            GlowEnabled = true,
            GlowType = "proc",
            GlowColor = { 0, 1, 0, 1 },
            FontFace = "Expressway",
            FontSize = 14,
            FontOutline = "SOFTOUTLINE",
            Strata = "HIGH",
            anchorFrameType = "UIPARENT",
            ParentFrame = "UIParent",
            Position = DefaultPosition(0, -160),
        },

        DisintegrateTicks = {
            Enabled = false,
            TickColor = { 1, 1, 1, 0.8 },
            TickWidth = 2,
            ClipWarning = {
                Enabled = true,
                Text = "DON'T CLIP",
                FontSize = 16,
                FontFace = "Expressway",
                FontOutline = "SOFTOUTLINE",
                Color = { 1, 0, 0, 1 },
            },
            Strata = "HIGH",
            anchorFrameType = "UIPARENT",
            ParentFrame = "UIParent",
            Position = DefaultPosition(0, -50),
        },

        StasisTracker = {
            Enabled = false,
            Strata = "HIGH",
            anchorFrameType = "UIPARENT",
            ParentFrame = "UIParent",
            Position = DefaultPosition(0, -60),
            GrowthDirection = "Horizontal",
            BarSide = "start",
            IconSize = 40,
            IconSpacing = 2,
            BarHeight = 15,
            BarTexture = "KitnUI",
            ColorMode = "custom",
            Color = { 0.2, 0.5, 0.4, 1 },
            BarBackgroundColor = { 0, 0, 0, 0.8 },
            FontSize = 14,
            FontFace = "Expressway",
            FontOutline = "OUTLINE",
        },

        EbonMightHelper = {
            Enabled = false,
            SoundFile = "None",
            SoundChannel = "Master",
        },

        EbonMightTracker = {
            Enabled = false,
            Mode = "icon",          -- "icon" = icon + border + countdown, "text" = border + state label only
            Strata = "MEDIUM",
            anchorFrameType = "UIPARENT",
            ParentFrame = "UIParent",
            Position = DefaultPosition(0, -150),
            IconSize = 48,
            FontFace = "Expressway",
            FontSize = 22,
            FontOutline = "OUTLINE",
            BaseColor = { 1, 1, 1, 1 },
            CritColor = { 1, 0, 1, 1 },
            DupeColor = { 1, 0.5, 0, 1 },
            OnlyShowCrit = false,
            CombatOnly = false,
            PandemicHighlight = false,
            PandemicGlowType = "pixel",        -- pixel / autocast / button / proc (LibCustomGlow)
            PandemicColor = { 1, 1, 0, 1 },    -- yellow
            -- 12.0.5 made UnitStat secret during encounters. EMTracker v1.2.0
            -- workaround: player saves their mainstat manually (out of combat)
            -- and the crit-detection math uses that cached value. Refreshed via
            -- the "Update from Current Stat" button in the GUI card. 0 = not set
            -- (crit detection is disabled until the user sets it).
            MainStat = 0,
        },

        -----------------------------------------------------------------
        -- QoL Modules
        -----------------------------------------------------------------

        Automation = {
            Enabled = false,
            SkipCinematics = true,
            HideTalkingHead = true,
            HideEventToasts = false,
            HideZoneNote = false,
            HideZoneText = false,
            AutoSellJunk = true,
            AutoRepair = true,
            UseGuildFunds = true,
            AutoRoleCheck = true,
            AutoQueueConfirm = true,
            AutoSlotKeystone = true,
            AutoFillDelete = true,
            AutoLoot = true,
            AutoAcceptQuests = false,
            AutoTurnInQuests = false,
            QuestModifier = "SHIFT",
            AutoDeclineDuels = false,
            AutoDeclinePetBattles = false,
            -- CVars (merged) - boolean
            CVarsEnabled = true,
            enableFloatingCombatText = nil,
            floatingCombatTextCombatDamage_v2 = nil,
            floatingCombatTextCombatHealing_v2 = nil,
            floatingCombatTextReactives_v2 = nil,
            findYourselfModeOutline = nil,
            occludedSilhouettePlayer = nil,
            ffxDeath = nil,
            ffxGlow = nil,
            ResampleAlwaysSharpen = nil,
            alwaysCompareItems = false,
            nameplateShowOnlyNameForFriendlyPlayerUnits = nil,
            nameplateUseClassColorForFriendlyPlayerUnitNames = nil,
            -- CVars (merged) - sliders
            SpellQueueWindow = nil,
            RAIDWaterDetail = nil,
            RAIDweatherDensity = nil,
            autoLootRate = nil,
        },

        AuctionHouseFilter = {
            Enabled = true,
            AuctionHouse = {
                CurrentExpansion = true,
                FocusSearchBar = true,
            },
            CraftOrders = {
                CurrentExpansion = true,
                FocusSearchBar = false,
            },
        },

        CombatLogger = {
            Enabled = true,
            DelayStop = true,
            DisableACLPrompt = false,
            QuietMode = false,
            -- Dungeons
            DungeonNormal = false,
            DungeonHeroic = false,
            DungeonMythic = false,
            DungeonMythicPlus = true,
            DungeonTimewalking = false,
            -- Raids
            RaidLFR = false,
            RaidNormal = true,
            RaidHeroic = true,
            RaidMythic = true,
            RaidTimewalking = false,
            -- PvP
            PvPRegularBG = false,
            PvPRatedBG = false,
            PvPArenaSkirmish = false,
            PvPRatedArena = false,
            PvPSoloShuffle = false,
            PvPWarGame = false,
            -- Scenarios
            ScenarioTorghast = false,
        },

        DragonRiding = {
            Enabled = false,
            HideWhenGrounded = false,
            HideWhenFull = false,
            ShowSecondWind = true,
            ShowSpeedText = true,
            FlipBars = false,
            EnableThrillColor = false,
            Width = 252,
            BarHeight = 16,
            Spacing = 1,
            SpeedFontSize = 14,
            FontFace = "Expressway",
            ShowSurgeIcon = true,
            SurgeIconOnLeft = false,
            SurgeIconAutoSize = true,
            SurgeIconGap = 1,
            SurgeIconSize = 26,
            anchorFrameType = "UIPARENT",
            ParentFrame = "UIParent",
            Strata = "MEDIUM",
            Position = DefaultPosition(0, -375),
            Colors = {
                Vigor = { 1, 0, 0.549, 1 },
                VigorThrill = { 0.2, 0.8, 0.2, 1 },
                SecondWind = { 0.565, 0.953, 0.953, 1 },
            },
        },

        BloodlustTracker = {
            Enabled = false,
            Mode = "pedro",
            Scale = 0.5,
            BasicIconSize = 48,
            FontSize = 22,
            FontFace = "Expressway",
            FontOutline = "SOFTOUTLINE",
            CountdownColor = { 1, 1, 1, 1 },
            SoundEnabled = true,
            SoundChannel = "Master",
            LoopSound = false,
            InstanceOnly = false,
            CombatOnly = false,
            Strata = "MEDIUM",
            anchorFrameType = "UIPARENT",
            ParentFrame = "UIParent",
            Position = DefaultPosition(0, 500),
        },

        PrescienceTracker = {
            Enabled = false,
            Strata = "MEDIUM",
            anchorFrameType = "UIPARENT",
            ParentFrame = "UIParent",
            Position = DefaultPosition(0, -100),
            ShowPrescience = true,
            ShowShiftingSands = false,
            StackDirection = "VERTICAL",
            GrowthDirection = "DOWN",
            MaxEntries = 6,
            IconSize = 32,
            Spacing = 4,
            ShowRoleIcon = true,
            RoleIconScale = 1.0,
            ShowNames = true,
            ClassColorNames = false,
            NameMaxLength = 0,
            NameFontFace = "Expressway",
            NameFontSize = 12,
            NameFontOutline = "OUTLINE",
            TimerFontFace = "Expressway",
            TimerFontSize = 14,
            TimerFontOutline = "OUTLINE",
            NameColor = { 1, 1, 1, 1 },
            TimerColor = { 1, 1, 1, 1 },
            CritColor = { 1, 0, 1, 1 },
        },

        KickTracker = {
            Enabled = true,
            Strata = "MEDIUM",
            anchorFrameType = "UIPARENT",
            ParentFrame = "UIParent",
            Position = DefaultPosition(-650, 105),
            -- Healer position override
            UseHealerPosition = true,
            HealerPosition = DefaultPosition(-650, 65),
            HealerAnchorFrameType = "UIPARENT",
            HealerParentFrame = "UIParent",
            HealerStrata = "MEDIUM",
            -- Bar appearance
            BarWidth = 209,
            BarHeight = 27,
            BarSpacing = 1,
            StatusBarTexture = "KitnUI",
            GrowthDirection = "UP",
            MaxBars = 5,
            IconSide = "LEFT",
            IconSize = 20,
            ShowIcon = true,
            -- Bar colors
            ColorMode = "dark",             -- "class" = class-colored bars + white names, "dark" = dark bars + class-colored names
            CoolingColor = { 0.8, 0.2, 0.2, 1 },
            ReadyColor = { 0.2, 0.8, 0.2, 1 },
            BackgroundColor = { 0.031, 0.031, 0.031, 0.80 },  -- #080808 A:80
            ClassColorCooling = true,       -- true = keep class color while on CD (ExWind style)
            -- Text
            ShowName = true,
            ShowTimer = true,
            FontFace = "Expressway",
            FontSize = 14,
            FontOutline = "OUTLINE",
            -- Ready state
            ShowReadyText = true,
            ReadyText = "Ready",
            -- Sort priorities (1=first, 3=last)
            SortTankPriority = 1,
            SortHealerPriority = 2,
            SortDPSPriority = 3,
        },

        StanceText = {
            Enabled = false,
            FontFace = "Expressway",
            FontSize = 14,
            FontOutline = "SOFTOUTLINE",
            Strata = "HIGH",
            anchorFrameType = "UIPARENT",
            ParentFrame = "UIParent",
            Position = DefaultPosition(-250, -130),
            SnapToPixelGrid = false,
            WARRIOR = {
                ["386164"] = { Enabled = true, Text = "Battle Stance", Color = { 1, 0, 0, 1 } },
                ["386196"] = { Enabled = true, Text = "Berserker Stance", Color = { 1, 0, 0, 1 } },
                ["386208"] = { Enabled = true, Text = "Defensive Stance", Color = { 0.3, 0.7, 1, 1 } },
            },
            PALADIN = {
                ["465"] = { Enabled = true, Text = "Devotion Aura", Color = { 1, 1, 1, 1 } },
                ["317920"] = { Enabled = true, Text = "Concentration Aura", Color = { 0.9, 0.5, 1, 1 } },
                ["32223"] = { Enabled = true, Text = "Crusader Aura", Color = { 1, 0.8, 0.3, 1 } },
            },
            EVOKER = {
                ["403264"] = { Enabled = true, Text = "Black Attunement", Color = { 0.5, 0.2, 0.8, 1 } },
                ["403265"] = { Enabled = true, Text = "Bronze Attunement", Color = { 0.9, 0.7, 0.2, 1 } },
            },
        },

        HuntersMark = {
            Enabled = false,
            Strata = "HIGH",
            anchorFrameType = "UIPARENT",
            ParentFrame = "UIParent",
            Position = DefaultPosition(0, 120),
            FontSize = 16,
            FontFace = "Expressway",
            FontOutline = "OUTLINE",
            Color = { 1, 0.82, 0, 1 },
        },

        PotionReady = {
            Enabled = true,
            InstanceOnly = true,
            CombatOnly = false,
            DisableOnHealer = false,
            Text = "Potion Ready",
            FontSize = 20,
            FontFace = "Expressway",
            FontOutline = "SOFTOUTLINE",
            ColorMode = "theme",
            Color = { 0, 1, 0, 1 },
            Strata = "MEDIUM",
            anchorFrameType = "SELECTFRAME",
            ParentFrame = "UtilityCooldownViewer",
            Position = { AnchorFrom = "TOP", AnchorTo = "BOTTOMRIGHT", XOffset = 0, YOffset = 5 },
            SnapToPixelGrid = false,
        },


        HideBars = {
            Enabled = false,
            Keybind = "",
            Bars = {
                [1] = true, [2] = false, [3] = false,
                [4] = true, [5] = true, [6] = true,
            },
        },

        WorldMarkerCycler = {
            Enabled = false,
            PlaceKey = "",
            PlaceModifier = "",
            ClearKey = "",
            ClearModifier = "",
            OrderList = { 1, 2, 3, 4, 5, 6, 7, 8 },
        },

        FocusMarker = {
            Enabled = true,
            SelectedMarker = "Star",
            MacroName = "FocusMarker",
            MacroIcon = 1033497,
            MacroConditionals = "",
            MarkOnly = false,
            NoRaid = false,
            NoToggle = true,
            AnnounceReadyCheck = true,
        },

        PIMacroBuilder = {
            Enabled = true,
            MacroName = "PI",
            MacroIcon = 135939,
            Trinket1 = true,
            Trinket2 = false,
            VampiricEmbrace = true,
            Racial = "Ancestral Call",
            Potion = "item:241309",
            FleetingPotion = "",
            Custom = "",
        },

        SlashCommands = {
            CDMEnabled = true,
            RLEnabled = true,
            FSEnabled = true,
            LeavePartyEnabled = true,
            ResetInstancesEnabled = true,
            MuteEnabled = true,
            MusicEnabled = true,
        },

        Recuperate = {
            Enabled = false,
            LoadInRaid = true,
            LoadInParty = false,
            Size = 40,
            anchorFrameType = "UIPARENT",
            ParentFrame = "UIParent",
            Strata = "MEDIUM",
            Position = DefaultPosition(0, -90),
        },

        GreatVaultAlert = {
            Enabled = true,
            PlaySound = true,
            SoundFile = "None",
            SoundChannel = "Master",
            ShowChatMessage = true,
            FontSize = 32,
            FontFace = "Expressway",
            FontOutline = "OUTLINE",
            AlertDuration = 4,
            Strata = "HIGH",
            anchorFrameType = "UIPARENT",
            ParentFrame = "UIParent",
            Position = DefaultPosition(0, 200),
        },

        VantusRune = {
            Enabled = true,
            ShowChatMessages = true,
            ConfirmationTimeout = 15,
        },

        MissingEnchants = {
            Enabled = true,
            ShowEnchants = true,
            GemEnabled = true,
            FontFace = "Expressway",
            FontSize = 13,
            FontOutline = "SOFTOUTLINE",
            HideCharacterBackground = false,
        },

        WorldMap = {
            Enabled = true,
            ScaleEnabled = true,
            Scale = 1.2,
            WaypointBarEnabled = true,
            MapIconsEnabled = true,
            MapIconsProfessionFilter = true,
            MapIconsStyle = "small", -- "regular" or "small"
        },

        -- Old standalone RacialsAnchor kept for one-time migration into
        -- PositionController.CDMRacials below. Do not edit; PositionController
        -- consumes its values on first init then sets _migrated = true.
        RacialsAnchor = {
            Enabled = false,
            AnchorFrom = "",
            AnchorTo = "",
            XOffset = 0,
            YOffset = -2,
            PetBarOffset = -15,
        },

        PositionController = {
            Enabled = false,
            -- When true, unit frame anchoring goes no-op on healer specs so
            -- ElvUI's profile positions take back over (matches AE behavior).
            -- Set false to apply anchoring on every spec including healer.
            IgnoreHealerSpec = true,
            PlayerFrame = {
                Enabled = true,
                anchorFrameType = "SELECTFRAME",
                ParentFrame = "EssentialCooldownViewer",
                Position = {
                    AnchorFrom = "RIGHT",
                    AnchorTo = "LEFT",
                    XOffset = -20,
                    YOffset = 0,
                },
            },
            TargetFrame = {
                Enabled = true,
                anchorFrameType = "SELECTFRAME",
                ParentFrame = "EssentialCooldownViewer",
                Position = {
                    AnchorFrom = "LEFT",
                    AnchorTo = "RIGHT",
                    XOffset = 20,
                    YOffset = 0,
                },
            },
            FocusFrame = {
                Enabled = false,
                anchorFrameType = "SELECTFRAME",
                ParentFrame = "ElvUF_Target",
                Position = {
                    AnchorFrom = "TOPLEFT",
                    AnchorTo = "TOPRIGHT",
                    XOffset = 10,
                    YOffset = 0,
                },
            },
            PetFrame = {
                Enabled = true,
                anchorFrameType = "SELECTFRAME",
                ParentFrame = "ElvUF_Player",
                Position = {
                    AnchorFrom = "CENTER",
                    AnchorTo = "BOTTOM",
                    XOffset = 0,
                    YOffset = -10,
                },
            },
            CDMRacials = {
                Enabled = false,
                AnchorFrom = "",
                AnchorTo = "",
                XOffset = 0,
                YOffset = -2,
                PetBarOffset = -15,
            },
        },

        SpellAlerts = {
            Enabled = false,
            EnabledSpecs = {},  -- nil/missing = ON, false = OFF (per spec index)
        },

        ReadyCheckConsumables = {
            Enabled = true,
            -- Position override (default is auto-anchor to ReadyCheckListenerFrame)
            PositionMode = "auto",  -- "auto" or "custom"
            SelfPoint = "BOTTOM",
            AnchorFrame = "UIParent",
            AnchorPoint = "CENTER",
            XOffset = 0,
            YOffset = 100,

            -- Per-category toggles
            ShowFood = true,
            ShowFlask = true,
            ShowWeaponOil = true,    -- main-hand weapon enhancement (slot 16: oil/stone/ammo)
            ShowOffHandOil = true,   -- off-hand weapon enhancement (slot 17)
            ShowAugmentRune = true,
            ShowHealthstone = true,
            ShowClassItem = true,    -- Warlock: Soulstone; hidden for other classes

            -- Runtime memory (persisted): last weapon enhancement item used. Seeds
            -- the click button so the tracker offers your preferred oil/stone/ammo
            -- on future ready checks. Auto-updates when a different enchant is detected.
            LastWeaponEnchantItem = nil,

            -- Behavior
            HideForStarter      = false,  -- suppress if you initiated the ready check
            HidePreviewMock     = true,  -- hide the fake Ready Check popup in the GUI preview
            CauldronFlasksOnly  = false,  -- click button only offers Fleeting (raid cauldron) flasks
            UnlimitedRunesOnly  = false,  -- click button only offers unlimited runes (DF/TWW)

            -- Visuals
            IconSize = 46,
            IconSpacing = 1,

            -- Font settings (for duration text above icons)
            FontFace = "Expressway",
            FontSize = 13,
            FontOutline = "SOFTOUTLINE",

            -- Colors
            -- HeartyFoodColor: tints the food slot's duration text when the active
            -- food buff persists through death (a raid-group convention indicator).
            -- DurationColor: base color for duration + count text on all slots.
            HeartyFoodColor = { 0.2, 1.0, 0.2, 1.0 },
            DurationColor  = { 1.0, 1.0, 1.0, 1.0 },
        },

        BossDebuffs = {
            Enabled = false,
            VisibilityMode = "boss",
            EncounterBlacklist = "",
            MaxDebuffs = 2,
            IconSize = 96,
            Spacing = 1,
            GrowthDirection = "LEFT",
            ShowDuration = true,
            ShowDurationText = true,
            ShowTooltip = true,
            Strata = "MEDIUM",
            anchorFrameType = "UIPARENT",
            ParentFrame = "UIParent",
            Position = { AnchorFrom = "CENTER", AnchorTo = "CENTER", XOffset = -360, YOffset = -55 },
        },

        -----------------------------------------------------------------
        -- Dungeons Modules
        -----------------------------------------------------------------

        Dungeons = {
            WarpDepleteForces = {
                Enabled = true,
                Tooltip = true,
                -- Nameplate % overlay (per-mob contribution shown on nameplate)
                NameplatePercent = false,
                NameplateCombatOnly = true,
                NameplateFontFace = "Expressway",
                NameplateFontSize = 12,
                NameplateFontOutline = "OUTLINE",
                NameplateColorMode = "theme",
                NameplateColor = { 1, 1, 1, 1 },
                NameplateAnchor = "TOPRIGHT",
                NameplateXOffset = -20,
                NameplateYOffset = 2,
                -- Instance Reset Announcer (merged from former InstanceReset module)
                InstanceResetEnabled = true,
                InstanceResetMessage = "Instance reset!",
                -- Death log persistence (survives /reload within same M+ run)
                DeathLog = {
                    mapID = nil,
                    keyLevel = nil,
                    details = {},
                },
            },
            EnemyCounter = {
                Enabled = false,
                CombatOnly = false,
                ShowPrefix = true,
                Prefix = "Enemies:",
                FontSize = 20,
                FontFace = "Expressway",
                FontOutline = "SOFTOUTLINE",
                ColorMode = "theme",
                Color = { 1, 1, 1, 1 },
                Strata = "MEDIUM",
                anchorFrameType = "UIPARENT",
                ParentFrame = "UIParent",
                Position = DefaultPosition(0, 215),
                SnapToPixelGrid = false,
            },
            BigWigsTimers = {
                Enabled = false,

                -- Bar display defaults
                BarDisplay = {
                    barWidth = 200,
                    barHeight = 20,
                    barTexture = "KitnUI",
                    fontFace = "Expressway",
                    fontSize = 12,
                    fontOutline = "OUTLINE",
                    iconEnabled = true,
                },

                -- Text display defaults
                TextDisplay = {
                    fontFace = "Expressway",
                    fontSize = 14,
                    fontOutline = "SOFTOUTLINE",
                    textAlign = "CENTER",
                },

                -- Bar group positioning
                BarGroup = {
                    Position = {
                        AnchorFrom = "CENTER",
                        AnchorTo = "CENTER",
                        XOffset = 0,
                        YOffset = 100,
                    },
                    GrowthDirection = "DOWN",
                    Spacing = 2,
                    Strata = "HIGH",
                    anchorFrameType = "UIPARENT",
                    ParentFrame = "UIParent",
                },

                -- Text group positioning
                TextGroup = {
                    Position = {
                        AnchorFrom = "CENTER",
                        AnchorTo = "CENTER",
                        XOffset = 0,
                        YOffset = -100,
                    },
                    GrowthDirection = "DOWN",
                    Spacing = 2,
                    Strata = "HIGH",
                    anchorFrameType = "UIPARENT",
                    ParentFrame = "UIParent",
                },

                -- Per-dungeon triggers (instanceId maps to BigWigs/LittleWigs boss modules)
                Dungeons = {
                    MagistersTerrace   = { Enabled = true, instanceId = 2811, Triggers = {} },
                    MaisaraCaverns     = { Enabled = true, instanceId = 2874, Triggers = {} },
                    NexusPointXenas    = { Enabled = true, instanceId = 2915, Triggers = {} },
                    WindrunnerSpire    = { Enabled = true, instanceId = 2805, Triggers = {} },
                    AlgetharAcademy    = { Enabled = true, instanceId = 2526, Triggers = {} },
                    PitOfSaron         = { Enabled = true, instanceId = 658, Triggers = {} },
                    SeatOfTriumvirate  = { Enabled = true, instanceId = 1753, Triggers = {} },
                    Skyreach           = { Enabled = true, instanceId = 1209, Triggers = {} },
                },

                -- Default values for new triggers
                TriggerDefaults = {
                    enabled = true,
                    triggerType = "timer",
                    spellId = "",
                    message = "",
                    messageOperator = "find",
                    remainingEnabled = true,
                    remainingOperator = "<=",
                    remainingValue = 5,
                    countEnabled = false,
                    countOperator = "==",
                    countValue = 1,
                    extendTimer = 0,
                    displayType = "bar",
                    useBigWigsColors = true,
                    barColor = { 0.772, 0.168, 0.168, 1 },
                    backgroundColor = { 0.1, 0.1, 0.1, 0.8 },
                    textColor = { 1, 1, 1, 1 },
                    barText1Format = "Tank Hit",
                    barText1Justify = "LEFT",
                    barText1XOffset = 3,
                    barText1YOffset = 0,
                    barText2Format = "%p",
                    barText2Justify = "RIGHT",
                    barText2XOffset = -3,
                    barText2YOffset = 0,
                    textFormat = "%n \194\187 %p",
                    textJustify = "LEFT",
                    showDecimals = true,
                    decimalThreshold = 1,
                    customText = "",
                    loadRoleEnabled = false,
                    loadRoleTank = true,
                    loadRoleHealer = true,
                    loadRoleDPS = true,
                    actionOnShowSound = "None",
                    actionOnHideSound = "None",
                },
            },
            DungeonTimers = {
                Enabled = false,
                RoleFilterEnabled = false,
                SpellRoleOverrides = {},
                SpellDisabled = {},
                SpellShowAtOverrides = {},
                SpellTimeOffsets = {},
                SpellDisplayOverrides = {},
                SpellDisplayTextOverrides = {},

                BarDisplay = {
                    barWidth = 250,
                    barHeight = 22,
                    fontFace = "Expressway",
                    fontSize = 12,
                    fontOutline = "OUTLINE",
                    barTexture = "KitnUI",
                    iconEnabled = true,
                },

                BarGroup = {
                    AnchorFrom = "CENTER",
                    AnchorTo = "CENTER",
                    XOffset = 0,
                    YOffset = 250,
                    GrowthDirection = "DOWN",
                    Spacing = 2,
                    ShowAtSeconds = 0,
                    Strata = "HIGH",
                    anchorFrameType = "UIPARENT",
                    ParentFrame = "UIParent",
                },

                TextDisplay = {
                    fontFace = "Expressway",
                    fontSize = 14,
                    fontOutline = "SOFTOUTLINE",
                    textAlign = "CENTER",
                },

                TextGroup = {
                    AnchorFrom = "CENTER",
                    AnchorTo = "CENTER",
                    XOffset = 0,
                    YOffset = 100,
                    GrowthDirection = "DOWN",
                    Spacing = 0,
                    ShowAtSeconds = 0,
                    Strata = "HIGH",
                    anchorFrameType = "UIPARENT",
                    ParentFrame = "UIParent",
                },
            },
            HealerMana = {
                Enabled = false,
                DisableOnHealer = false,
                Strata = "HIGH",
                anchorFrameType = "UIPARENT",
                ParentFrame = "UIParent",
                Position = DefaultPosition(-400, 200),
                SnapToPixelGrid = false,
                FrameWidth = 120,
                IconSize = 24,
                IconType = "spec",

                NameFontSize = 14,
                NameXOffset = 4,
                NameYOffset = 2,
                ManaFontSize = 14,
                ManaXOffset = 4,
                ManaYOffset = -2,
                FontFace = "Expressway",
                FontOutline = "SOFTOUTLINE",
                HighManaColor = { 1, 1, 1, 1 },
            },
            DeathNotifications = {
                Enabled = false,
                EnableInDungeons = true,
                EnableInRaids = false,
                SnapToPixelGrid = true,

                FontFace = "Expressway",
                FontSize = 34,
                FontOutline = "SOFTOUTLINE",

                Duration = 3,
                Spacing = 4,
                Grow = "DOWN",
                ShowClassIcon = true,

                PartyDeath = {
                    Enabled = true,
                    UseClassColor = true,
                    TextFormat = "%name DIED",
                    TextColor = { 1, 1, 1, 1 },
                },
                FocusDeath = {
                    Enabled = true,
                    Text = "FOCUS DIED",
                    Color = { 1, 0.3, 0.3, 1 },
                },

                anchorFrameType = "UIPARENT",
                ParentFrame = "UIParent",
                Strata = "MEDIUM",
                Position = DefaultPosition(0, 312),
            },
            DungeonCasts = {
                Enabled = true,

                -- Frame settings
                Frame = {
                    MaxBars = 5,
                    Width = 279,
                    Height = 27,
                    Spacing = 1,
                    GrowthDirection = "UP",
                    Strata = "MEDIUM",
                    anchorFrameType = "UIPARENT",
                    ParentFrame = "UIParent",
                    Position = {
                        AnchorFrom = "CENTER",
                        AnchorTo = "CENTER",
                        XOffset = -325,
                        YOffset = 105,
                    },
                },

                -- Bar appearance
                BarDisplay = {
                    StatusBarTexture = "KitnUI",
                    FontFace = "Expressway",
                    FontSize = 14,
                    FontOutline = "OUTLINE",
                    SparkEnabled = true,
                },

                -- Icon settings
                Icon = {
                    Enabled = true,
                    Zoom = 0.3,
                },

                -- Colors
                CastingColor = { 1.0, 0.0, 0.784, 1 },
                ChannelingColor = { 0.0, 0.7, 1.0, 1 },
                NotInterruptibleColor = { 0.6, 0.6, 0.6, 1 },
                BackgroundColor = { 0.031, 0.031, 0.031, 0.80 },
                BorderColor = { 0, 0, 0, 1 },

                -- Raid target icon
                RaidIcon = {
                    Enabled = true,
                    Size = 20,
                },

                -- Text settings
                Text = {
                    NameAlign = "LEFT",
                    TimeAlign = "RIGHT",
                    ShowTime = true,
                    TextColor = { 1, 1, 1, 1 },
                },

                -- Target display settings
                Target = {
                    Enabled = true,
                    ShowClassColor = true,
                    Position = "RIGHT",
                    Separator = "»",
                },
            },
        },

        -----------------------------------------------------------------
        -- Skinning Modules
        -----------------------------------------------------------------

        Skinning = {
            Tooltips = {
                Enabled = false,
                BackgroundColor = { 0, 0, 0, 0.8 },
                BorderColor = { 0, 0, 0, 1 },
                BorderSize = 1,
                HideHealthBar = true,
                FontFace = "Expressway",
                FontOutline = "OUTLINE",
                NameFontSize = 17,
                GuildFontSize = 14,
                RaceLevelFontSize = 14,
                SpecFontSize = 14,
                FactionFontSize = 14,
                Position = {
                    AnchorFrom = "BOTTOMRIGHT",
                    AnchorTo = "BOTTOMRIGHT",
                    XOffset = -1,
                    YOffset = 350,
                },
            },
            Messages = {
                Enabled = false,
                Font = "Expressway",
                FontOutline = "OUTLINE",
                UIErrorsFrame = {
                    Hide = false,
                    Size = 14,
                    Position = {
                        Anchor = "TOP",
                        X = 0,
                        Y = -281,
                    },
                },
                ActionStatusText = {
                    Hide = false,
                    Size = 14,
                    Position = {
                        Anchor = "TOP",
                        X = 0,
                        Y = -251,
                    },
                },
                ChatBubbles = {
                    Enabled = true,
                    Size = 8,
                },
                ObjectiveTracker = {
                    Enabled = true,
                    QuestTextSize = 12,
                    QuestTitleSize = 13,
                },
                ZoneText = {
                    Hide = false,
                    SubZone = {
                        Size = 20,
                    },
                    MainZone = {
                        Size = 40,
                        Anchor = "TOP",
                        X = 0,
                        Y = -200,
                    },
                },
            },
            Mouseover = {
                Enabled = false,
                Alpha = 0.0,
                FadeInDuration = 0.2,
                FadeOutDuration = 1,
                BagMouseover = {
                    Enabled = true,
                },
            },
            MicroMenu = {
                Enabled = false,
                ButtonWidth = 23,
                ButtonHeight = 31,
                ButtonSpacing = -4,
                BackdropSpacing = 0,
                ShowBackdrop = true,
                BackdropColor = { 0, 0, 0, 0.8 },
                BackdropBorderColor = { 0, 0, 0, 1 },
                anchorFrameType = "SELECTFRAME",
                ParentFrame = "Minimap",
                Strata = "MEDIUM",
                Position = {
                    AnchorFrom = "TOP",
                    AnchorTo = "BOTTOM",
                    XOffset = 0,
                    YOffset = -1,
                },
                Mouseover = {
                    Enabled = false,
                    Alpha = 0.0,
                    FadeInDuration = 0.2,
                    FadeOutDuration = 0.2,
                },
            },
            Details = {
                Enabled = false,
                detailsBarH = 26,
                detailsSpacing = 1,
                detailsTitelH = 20,
                detailsWidth = 260,
                backDropOne = {
                    Enabled = true,
                    autoSize = false,
                    detailsBars = 8,
                    width = 260,
                    height = 210,
                    BackgroundColor = { 0, 0, 0, 0.8 },
                    BorderColor = { 0, 0, 0, 1 },
                    Strata = "LOW",
                    Position = {
                        AnchorFrom = "BOTTOMRIGHT",
                        AnchorTo = "BOTTOMRIGHT",
                        XOffset = -1,
                        YOffset = 1,
                    },
                },
                backDropTwo = {
                    Enabled = true,
                    autoSize = false,
                    detailsBars = 8,
                    width = 260,
                    height = 210,
                    BackgroundColor = { 0, 0, 0, 0.8 },
                    BorderColor = { 0, 0, 0, 1 },
                    Strata = "LOW",
                    Position = {
                        AnchorFrom = "BOTTOMRIGHT",
                        AnchorTo = "BOTTOMRIGHT",
                        XOffset = -262,
                        YOffset = 1,
                    },
                },
            },
            ActionBars = {
                Enabled = false,
                HideProfTexture = true,
                HideMacroText = false,
                MouseoverOverride = false,
                Mouseover = {
                    Enabled = false,
                    FadeInDuration = 0.3,
                    FadeOutDuration = 1,
                    Alpha = 0,
                },
                FontFace = "Expressway",
                FontOutline = "OUTLINE",
                FontSizes = {
                    KeybindSize = 12,
                    CooldownSize = 14,
                    ChargeSize = 12,
                    MacroSize = 10,
                },
                KeybindAnchor = "TOPRIGHT",
                KeybindXOffset = -2,
                KeybindYOffset = -2,
                ChargeAnchor = "BOTTOMRIGHT",
                ChargeXOffset = -2,
                ChargeYOffset = 2,
                MacroAnchor = "BOTTOM",
                MacroXOffset = 0,
                MacroYOffset = 2,
                CooldownAnchor = "CENTER",
                CooldownXOffset = 0,
                CooldownYOffset = 0,
                Bars = {
                    Bar1 = {
                        Enabled = true, Spacing = 1, ButtonSize = 40, TotalButtons = 12,
                        Layout = "HORIZONTAL", GrowthDirection = "RIGHT", ButtonsPerLine = 12,
                        ParentFrame = "UIParent", HideEmptyBackdrops = false,
                        BackdropColor = { 0, 0, 0, 0.8 }, BorderColor = { 0, 0, 0, 1 },
                        Position = { AnchorFrom = "BOTTOM", AnchorTo = "BOTTOM", XOffset = 0.1, YOffset = 1.1 },
                        Mouseover = { GlobalOverride = true, Enabled = true, Alpha = 0 },
                        FontSizes = { GlobalOverride = true, KeybindSize = 12, CooldownSize = 14, ChargeSize = 12, MacroSize = 10 },
                        TextPositions = { GlobalOverride = true, KeybindAnchor = "TOPRIGHT", KeybindXOffset = -2, KeybindYOffset = -2, ChargeAnchor = "BOTTOMRIGHT", ChargeXOffset = -2, ChargeYOffset = 2, MacroAnchor = "BOTTOM", MacroXOffset = 0, MacroYOffset = -2 },
                    },
                    Bar2 = {
                        Enabled = true, Spacing = 1, ButtonSize = 40, TotalButtons = 12,
                        Layout = "HORIZONTAL", GrowthDirection = "RIGHT", ButtonsPerLine = 6,
                        ParentFrame = "UIParent", HideEmptyBackdrops = false,
                        BackdropColor = { 0, 0, 0, 0.8 }, BorderColor = { 0, 0, 0, 1 },
                        Position = { AnchorFrom = "BOTTOM", AnchorTo = "BOTTOM", XOffset = 369.1, YOffset = 1.1 },
                        Mouseover = { GlobalOverride = true, Enabled = true, Alpha = 0 },
                        FontSizes = { GlobalOverride = true, KeybindSize = 12, CooldownSize = 14, ChargeSize = 12, MacroSize = 10 },
                        TextPositions = { GlobalOverride = true, KeybindAnchor = "TOPRIGHT", KeybindXOffset = -2, KeybindYOffset = -2, ChargeAnchor = "BOTTOMRIGHT", ChargeXOffset = -2, ChargeYOffset = 2, MacroAnchor = "BOTTOM", MacroXOffset = 0, MacroYOffset = -2 },
                    },
                    Bar3 = {
                        Enabled = true, Spacing = 1, ButtonSize = 40, TotalButtons = 12,
                        Layout = "HORIZONTAL", GrowthDirection = "RIGHT", ButtonsPerLine = 12,
                        ParentFrame = "UIParent", HideEmptyBackdrops = false,
                        BackdropColor = { 0, 0, 0, 0.8 }, BorderColor = { 0, 0, 0, 1 },
                        Position = { AnchorFrom = "BOTTOM", AnchorTo = "BOTTOM", XOffset = 0.1, YOffset = 42.1 },
                        Mouseover = { GlobalOverride = true, Enabled = true, Alpha = 0 },
                        FontSizes = { GlobalOverride = true, KeybindSize = 12, CooldownSize = 14, ChargeSize = 12, MacroSize = 10 },
                        TextPositions = { GlobalOverride = true, KeybindAnchor = "TOPRIGHT", KeybindXOffset = -2, KeybindYOffset = -2, ChargeAnchor = "BOTTOMRIGHT", ChargeXOffset = -2, ChargeYOffset = 2, MacroAnchor = "BOTTOM", MacroXOffset = 0, MacroYOffset = -2 },
                    },
                    Bar4 = {
                        Enabled = true, Spacing = 1, ButtonSize = 40, TotalButtons = 12,
                        Layout = "VERTICAL", GrowthDirection = "RIGHT", ButtonsPerLine = 6,
                        ParentFrame = "UIParent", HideEmptyBackdrops = false,
                        BackdropColor = { 0, 0, 0, 0.8 }, BorderColor = { 0, 0, 0, 1 },
                        Position = { AnchorFrom = "BOTTOMLEFT", AnchorTo = "BOTTOMLEFT", XOffset = 450.1, YOffset = 1.1 },
                        Mouseover = { GlobalOverride = true, Enabled = true, Alpha = 0 },
                        FontSizes = { GlobalOverride = true, KeybindSize = 12, CooldownSize = 14, ChargeSize = 12, MacroSize = 10 },
                        TextPositions = { GlobalOverride = true, KeybindAnchor = "TOPRIGHT", KeybindXOffset = -2, KeybindYOffset = -2, ChargeAnchor = "BOTTOMRIGHT", ChargeXOffset = -2, ChargeYOffset = 2, MacroAnchor = "BOTTOM", MacroXOffset = 0, MacroYOffset = -2 },
                    },
                    Bar5 = {
                        Enabled = true, Spacing = 1, ButtonSize = 40, TotalButtons = 12,
                        Layout = "HORIZONTAL", GrowthDirection = "RIGHT", ButtonsPerLine = 6,
                        ParentFrame = "UIParent", HideEmptyBackdrops = false,
                        BackdropColor = { 0, 0, 0, 0.8 }, BorderColor = { 0, 0, 0, 1 },
                        Position = { AnchorFrom = "BOTTOM", AnchorTo = "BOTTOM", XOffset = -368.1, YOffset = 1.1 },
                        Mouseover = { GlobalOverride = true, Enabled = true, Alpha = 0 },
                        FontSizes = { GlobalOverride = true, KeybindSize = 12, CooldownSize = 14, ChargeSize = 12, MacroSize = 10 },
                        TextPositions = { GlobalOverride = true, KeybindAnchor = "TOPRIGHT", KeybindXOffset = -2, KeybindYOffset = -2, ChargeAnchor = "BOTTOMRIGHT", ChargeXOffset = -2, ChargeYOffset = 2, MacroAnchor = "BOTTOM", MacroXOffset = 0, MacroYOffset = -2 },
                    },
                    Bar6 = {
                        Enabled = true, Spacing = 1, ButtonSize = 40, TotalButtons = 12,
                        Layout = "VERTICAL", GrowthDirection = "RIGHT", ButtonsPerLine = 6,
                        ParentFrame = "UIParent", HideEmptyBackdrops = false,
                        BackdropColor = { 0, 0, 0, 0.8 }, BorderColor = { 0, 0, 0, 1 },
                        Position = { AnchorFrom = "BOTTOMLEFT", AnchorTo = "BOTTOMLEFT", XOffset = 532.1, YOffset = 1.1 },
                        Mouseover = { GlobalOverride = true, Enabled = true, Alpha = 0 },
                        FontSizes = { GlobalOverride = true, KeybindSize = 12, CooldownSize = 14, ChargeSize = 12, MacroSize = 10 },
                        TextPositions = { GlobalOverride = true, KeybindAnchor = "TOPRIGHT", KeybindXOffset = -2, KeybindYOffset = -2, ChargeAnchor = "BOTTOMRIGHT", ChargeXOffset = -2, ChargeYOffset = 2, MacroAnchor = "BOTTOM", MacroXOffset = 0, MacroYOffset = -2 },
                    },
                    Bar7 = {
                        Enabled = true, Spacing = 1, ButtonSize = 40, TotalButtons = 12,
                        Layout = "VERTICAL", GrowthDirection = "RIGHT", ButtonsPerLine = 12,
                        ParentFrame = "UIParent", HideEmptyBackdrops = false,
                        BackdropColor = { 0, 0, 0, 0.8 }, BorderColor = { 0, 0, 0, 1 },
                        Position = { AnchorFrom = "LEFT", AnchorTo = "LEFT", XOffset = 1.1, YOffset = 0.1 },
                        Mouseover = { GlobalOverride = true, Enabled = false, Alpha = 1 },
                        FontSizes = { GlobalOverride = true, KeybindSize = 12, CooldownSize = 14, ChargeSize = 12, MacroSize = 10 },
                        TextPositions = { GlobalOverride = true, KeybindAnchor = "TOPRIGHT", KeybindXOffset = -2, KeybindYOffset = -2, ChargeAnchor = "BOTTOMRIGHT", ChargeXOffset = -2, ChargeYOffset = 2, MacroAnchor = "BOTTOM", MacroXOffset = 0, MacroYOffset = -2 },
                    },
                    Bar8 = {
                        Enabled = true, Spacing = 1, ButtonSize = 40, TotalButtons = 12,
                        Layout = "VERTICAL", GrowthDirection = "RIGHT", ButtonsPerLine = 12,
                        ParentFrame = "UIParent", HideEmptyBackdrops = false,
                        BackdropColor = { 0, 0, 0, 0.8 }, BorderColor = { 0, 0, 0, 1 },
                        Position = { AnchorFrom = "LEFT", AnchorTo = "LEFT", XOffset = 42.1, YOffset = 0.1 },
                        Mouseover = { GlobalOverride = true, Enabled = false, Alpha = 1 },
                        FontSizes = { GlobalOverride = true, KeybindSize = 12, CooldownSize = 14, ChargeSize = 12, MacroSize = 10 },
                        TextPositions = { GlobalOverride = true, KeybindAnchor = "TOPRIGHT", KeybindXOffset = -2, KeybindYOffset = -2, ChargeAnchor = "BOTTOMRIGHT", ChargeXOffset = -2, ChargeYOffset = 2, MacroAnchor = "BOTTOM", MacroXOffset = 0, MacroYOffset = -2 },
                    },
                    PetBar = {
                        Enabled = true, Spacing = 1, ButtonSize = 32, TotalButtons = 10,
                        Layout = "HORIZONTAL", GrowthDirection = "RIGHT", ButtonsPerLine = 10,
                        ParentFrame = "UIParent", HideEmptyBackdrops = false,
                        BackdropColor = { 0, 0, 0, 0.8 }, BorderColor = { 0, 0, 0, 1 },
                        Position = { AnchorFrom = "BOTTOM", AnchorTo = "BOTTOM", XOffset = 0.1, YOffset = 83.1 },
                        Mouseover = { GlobalOverride = false, Enabled = false, Alpha = 0 },
                        FontSizes = { GlobalOverride = true, KeybindSize = 10, CooldownSize = 12, ChargeSize = 10, MacroSize = 8 },
                        TextPositions = { GlobalOverride = true, KeybindAnchor = "TOPRIGHT", KeybindXOffset = -2, KeybindYOffset = -2, ChargeAnchor = "BOTTOMRIGHT", ChargeXOffset = -2, ChargeYOffset = 2, MacroAnchor = "BOTTOM", MacroXOffset = 0, MacroYOffset = -2 },
                    },
                    StanceBar = {
                        Enabled = true, Spacing = 1, ButtonSize = 32, TotalButtons = 10,
                        Layout = "HORIZONTAL", GrowthDirection = "RIGHT", ButtonsPerLine = 10,
                        ParentFrame = "UIParent", HideEmptyBackdrops = true,
                        BackdropColor = { 0, 0, 0, 0.8 }, BorderColor = { 0, 0, 0, 1 },
                        Position = { AnchorFrom = "BOTTOM", AnchorTo = "BOTTOM", XOffset = 0.1, YOffset = 117.1 },
                        Mouseover = { GlobalOverride = false, Enabled = false, Alpha = 0 },
                        FontSizes = { GlobalOverride = true, KeybindSize = 10, CooldownSize = 12, ChargeSize = 10, MacroSize = 8 },
                        TextPositions = { GlobalOverride = true, KeybindAnchor = "TOPRIGHT", KeybindXOffset = -2, KeybindYOffset = -2, ChargeAnchor = "BOTTOMRIGHT", ChargeXOffset = -2, ChargeYOffset = 2, MacroAnchor = "BOTTOM", MacroXOffset = 0, MacroYOffset = -2 },
                    },
                },
            },
            Auras = {
                Enabled = false,
                disableFlashing = true,
                FontFace = "Expressway",
                FontOutline = "OUTLINE",
                FontColor = { 1, 1, 1, 1 },
                buffSize = 36,
                buffBorderColor = { 0, 0, 0, 1 },
                debuffSize = 40,
                debuffBorderColor = { 0.8, 0, 0, 1 },
                defSize = 42,
                defBorderColor = { 0, 0, 0, 1 },
            },
            UICleanup    = { Enabled = false },
            Battlenet    = {
                Enabled = true,
                Position = {
                    AnchorFrom = "BOTTOMLEFT",
                    AnchorTo = "LEFT",
                    XOffset = 1,
                    YOffset = 0,
                },
            },
            RaidManager  = {
                Enabled = false,
                Position = {
                    YOffset = -100,
                },
                Strata = "HIGH",
                FadeOnMouseOut = true,
                FadeInDuration = 0.3,
                FadeOutDuration = 3,
                Alpha = 0,
            },
        },

    },
}

---------------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------------

function KE:GetDefaultDB()
    return Defaults
end
