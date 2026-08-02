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

        Cursor = {
            SchemaVersion = 0,
            Enabled    = true,
            Size       = 67,
            Texture    = "circle_normal",
            ColorMode  = "theme",
            Color      = { 1, 1, 1, 1 },
            Visibility = "always",

            GCD = {
                Enabled            = true,
                Mode               = "integrated",
                Attached           = true,
                Size               = 50,
                Texture            = "circle_light",
                RingColorMode      = "theme",  RingColor  = { 1, 1, 1, 1 },
                SwipeColorMode     = "custom", SwipeColor = { 1, 1, 1, 0.8 },
                Reverse            = false,
                VisibilityOverride = nil,
                InstanceOnly       = false,
            },

            Cast = {
                Enabled            = false,
                Attached           = true,
                Size               = 72,
                Texture            = "circle_normal",
                RingColorMode      = "class",  RingColor  = { 1, 1, 1, 1 },
                SwipeColorMode     = "theme",  SwipeColor = { 1, 1, 1, 0.7 },
                SparkEnabled       = true,
                SparkColorMode     = "ring",
                SparkColor         = { 1, 1, 1, 1 },
                VisibilityOverride = nil,
                InstanceOnly       = false,
            },

            Trail = {
                Enabled            = true,
                DotDuration        = 0.5,
                DotBaseSize        = 40,
                Density            = 0.016,
                ColorInherit       = true,
                Color              = { 1, 1, 1, 1 },
                VisibilityOverride = nil,
                InstanceOnly       = false,
            },

            Dispel = {
                Enabled            = true,
                Attached           = true,
                AnchorPoint        = "CENTER",
                XOffset            = 0,
                YOffset            = 10,
                FontFace           = "Expressway",
                FontSize           = 18,
                TextColor          = { 1, 1, 1, 1 },
                VisibilityOverride = nil,
                InstanceOnly       = false,
            },

            -- Taunt cooldown countdown at the cursor. Tank specs only --
            -- C:_TauntEvaluateGate activates it on a tank spec and tears it
            -- down otherwise, so Enabled=true still shows nothing on a healer.
            -- Ships OFF: the reference disables its module at init for the
            -- same reason (<REF>/Combat/TauntCursor.lua:53).
            Taunt = {
                Enabled            = false,
                Attached           = true,
                AnchorPoint        = "CENTER",
                XOffset            = 10,
                YOffset            = 10,
                FontFace           = "Expressway",
                FontSize           = 18,
                TextColor          = { 1, 1, 1, 1 },
                VisibilityOverride = nil,
                InstanceOnly       = false,
            },
        },

        PetStatusText = {
            Enabled = true,
            Strata = "MEDIUM",
            anchorFrameType = "UIPARENT",
            ParentFrame = "UIParent",
            Position = DefaultPosition(0, 100),
            FontSize = 26,
            FontFace = "Expressway",
            FontOutline = "SOFTOUTLINE",
            PetMissing = "PET MISSING",
            PetDead = "PET DEAD",
            PetPassive = "PET PASSIVE",
            PetWrong = "WRONG PET",
            MissingColor = { 1, 0.82, 0, 1 },       -- #FFD100
            DeadColor = { 1, 0.2, 0.2, 1 },          -- #FF3333
            PassiveColor = { 1, 0, 0.549, 1 },        -- #FF008C
            WrongColor = { 1, 0.4, 0, 1 },            -- #FF6600
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
            VoidcoreEnabled = true,
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
            -- Focus-castbar-only features (opt-in):
            OutOfRangeOpacity = 1,        -- 1 = disabled; < 1 dims bar when interrupt out of range
            IgnoreFriendlies = false,     -- hide bar when focus is not attackable
            ImportantGlow = {
                Enabled = false,
                GlowType = "pixel",           -- "pixel" or "autocast" (LibCustomGlow)
                Color = { 1, 0.85, 0.1, 1 },  -- glow color when C_Spell.IsSpellImportant is true
                GlowLines = 8,                -- pixel: line count / autocast: particle count
                GlowFrequency = 0.25,         -- animation speed (lower = faster)
                GlowLength = 8,               -- pixel only: line length
                GlowThickness = 2,            -- pixel only: line thickness
                GlowScale = 1,                -- autocast only: particle scale
                GlowBorder = true,            -- pixel only: draw the connecting border
            },
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
            Strata = "MEDIUM",
            anchorFrameType = "UIPARENT",
            ParentFrame = "UIParent",
            Position = DefaultPosition(0, -160),
        },

        PlayerAbsorbs = {
            Enabled = false,
            Strata = "MEDIUM",
            anchorFrameType = "PLAYERFRAME",
            ParentFrame = "UIParent",
            Position = DefaultPosition(0, -10), -- above the player frame; tune in-game
            IconSize = 18,
            ShowIcon = false,
            IconSide = "LEFT", -- LEFT/RIGHT side of the number (stacked Down/Up modes only)
            IconSpacing = 4, -- px between an icon and its number
            RowSpacing = 4,  -- px between the shield and heal-absorb readouts (stacked/adjacent)
            Separation = 140, -- px between the two sides in SPLIT (flank) growth
            SplitIconLead = true, -- SPLIT only: false = flank mirror (icons bracket the gap); true = both lead with the icon
            GrowthDirection = "UP", -- DOWN/UP = stacked, RIGHT/LEFT = side-by-side, SPLIT = flank; heal grows off the shield

            -- true = abbreviated (1.2M): number+icon fade FadeTime sec after a change
            -- (a secret 0 can't instant-hide while abbreviating). false = full numbers
            -- that persist while a shield is up and blank instantly at 0 (TruncateWhenZero);
            -- only the icon fades. See Modules/Utilities/PlayerAbsorbs.lua Display header.
            AbbreviateNumber = true,
            HideWhenZero = true,
            FadeTime = 10, -- seconds the icon (and, when abbreviating, the number) lingers after a change

            FontFace = "Expressway",
            FontSize = 16,
            FontOutline = "OUTLINE",
            ShieldColor = { 0.37, 0.82, 1, 1 },    -- cyan
            HealAbsorbColor = { 1, 0.48, 0.48, 1 }, -- red
        },

        BurningRush = {
            Enabled = true,
            IconSize = 45,
            -- Glow (consumed by GUI-GlowSettingsCard — these are its default key names)
            GlowEnabled = true,
            GlowType = "pixel",
            GlowColor = { 1, 0.5, 0, 1 },
            GlowXOffset = 0,
            GlowYOffset = 0,
            GlowLines = 5,
            GlowFrequency = 0.25,
            GlowLength = 10,
            GlowThickness = 2,
            GlowBorder = true,
            GlowScale = 1,
            GlowDuration = 1,
            GlowStartAnim = false,
            -- Position (anchorFrameType/ParentFrame/Strata are ROOT keys; AnchorFrom/To + offsets live in Position)
            Strata = "MEDIUM",
            anchorFrameType = "UIPARENT",
            ParentFrame = "UIParent",
            Position = DefaultPosition(0, 125),
        },

        TotemTracker = {
            Enabled = true,
            IconSize = 44,
            IconSpacing = 1,
            GrowDirection = "RIGHT", -- RIGHT | LEFT | UP | DOWN
            ShowTimer = true,
            DecimalThreshold = 5, -- seconds; below this the timer shows one decimal (0 = off)
            Swipe = false,
            Reverse = false,

            FontFace = "Expressway",
            FontOutline = "OUTLINE",
            TimerFontSize = 18,

            Strata = "MEDIUM",
            anchorFrameType = "PLAYERFRAME",
            ParentFrame = "UIParent",
            Position = { AnchorFrom = "LEFT", AnchorTo = "BOTTOMLEFT", XOffset = 0, YOffset = -61 },
        },

        InnervateTracker = {
            Enabled = true,
            IconSize = 40,
            ShowLabel = true,
            LabelText = "FREE",
            LabelColor = { 0, 1, 0, 1 }, -- #00ff00
            LabelFontSize = 14,
            ShowTimer = true,
            TimerColor = { 1, 1, 1, 1 },
            TimerFontSize = 18,
            FontFace = "Expressway",
            FontOutline = "OUTLINE",
            -- Glow (CreateGlowSettingsCard default key names)
            GlowEnabled   = false,
            GlowType      = "pixel",
            GlowColor     = { 0, 1, 0, 1 }, -- #00ff00
            GlowLines     = 5,
            GlowFrequency = 0.25,
            GlowLength    = 10,
            GlowThickness = 2,
            GlowBorder    = true,
            GlowScale     = 1.0,
            GlowStartAnim = true,
            GlowDuration  = 1.0,
            -- Sound (CreateSoundSettingsCard default key names)
            actionOnShowSound = "None",
            actionOnHideSound = "None",
            Strata = "MEDIUM",
            anchorFrameType = "UIPARENT",
            ParentFrame = "UIParent",
            Position = DefaultPosition(0, -120),
        },

        MaintenanceTracker = {
            Enabled = true,
            IconSize = 34,
            CountFontSize = 14,
            CountColor = { 1, 1, 1, 1 },
            ShowLowest = true,
            LowestFontSize = 14,
            GrowthDirection = "LEFT",   -- RIGHT | LEFT | UP | DOWN
            Spacing = 4,
            LowThreshold = 3,
            MidThreshold = 6,
            LowDurationColor = { 1, 0.302, 0.302, 1 },  -- #ff4d4d
            MidDurationColor = { 1, 0.749, 0.2, 1 },     -- #ffbf33
            HighDurationColor = { 0, 1, 0.059, 1 },      -- #00ff0f
            FontFace = "Expressway",
            FontOutline = "OUTLINE",
            Strata = "MEDIUM",
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
            Strata = "MEDIUM",
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
            AutoConfirmLootRoll = true,
            AutoPassHousing = true,
            AutoPassHousingMode = "NEED",  -- "PASS" or "NEED"
            ConfirmBonusRoll = true,
            AutoAcceptQuests = false,
            AutoTurnInQuests = false,
            AutoVoidcoresGold = true,
            AutoUnwatchHidden = true,
            QuestModifier = "SHIFT",
            AutoDeclineDuels = false,
            AutoDeclinePetBattles = false,
            AutoAcceptRes = false,
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
            -- Teammate kick records (12.0.5: exact teammate CDs are hidden)
            KickRecordDuration = 15,        -- seconds a teammate kick record stays visible
            KickSync = true,                -- broadcast own kicks to party KE users (real CD sync)
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
            anchorFrameType = "PLAYERFRAME",
            ParentFrame = "UIParent",
            Position = { AnchorFrom = "LEFT", AnchorTo = "LEFT", XOffset = 3, YOffset = 0 },
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
            Strata = "MEDIUM",
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
            Position = { AnchorFrom = "TOP", AnchorTo = "BOTTOM", XOffset = 0, YOffset = 5 },
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
            NoOverwrite = true,
            AnnounceReadyCheck = true,
        },

        KeystoneHelper = {
            Enabled = true,

            -- Feature toggles
            ResetEnabled = true,
            ResetMessage = "Instance reset!",
            RerollEnabled = true,
            YourKeyEnabled = true,

            -- Shared reminder appearance/position (one block for both frames —
            -- Reroll and Your Key? are never on screen together live)
            Size = 64,
            FontFace = "Expressway",
            FontOutline = "SOFTOUTLINE",
            FontSize = 36,
            FontColor = { 1, 1, 1, 1 },
            FontColorKey = { 1, 1, 1, 1 },
            Strata = "MEDIUM",
            AnchorFrameType = "UIPARENT",
            ParentFrame = "UIParent",
            Position = DefaultPosition(0, 165),

            -- Per-feature glow
            RerollGlowEnabled = true,
            RerollGlowColor = { 0, 1, 0, 1 },
            RerollGlowLines = 5,
            RerollGlowFrequency = 0.25,
            RerollGlowLength = 10,
            RerollGlowThickness = 2,
            YourKeyGlowEnabled = true,
            YourKeyGlowColor = { 0.2, 0.6, 1, 1 },
            YourKeyGlowLines = 5,
            YourKeyGlowFrequency = 0.25,
            YourKeyGlowLength = 10,
            YourKeyGlowThickness = 2,
        },

        -- Quick-access side panel docked to the right of the Group Finder:
        -- this week's affixes, one-click category searches, a Mythic+
        -- dungeon/role filter pane, and a weekly-runs footer.
        -- Ships DISABLED: it rewrites Blizzard's LFGList search results, so
        -- it is opt-in.
        --
        -- The six keys below Enabled are SESSION state, not preferences: the
        -- module overwrites every one of them on each OnEnable (login, reload
        -- and toggle) by design -- filters are meant to start clean each
        -- session. That makes the SortBy and SortDescending values here
        -- effectively dead. They are kept so the shape is complete. Do not
        -- "fix" them by deleting the reset; the reset is the behaviour.
        GroupFinderPanel = {
            Enabled        = false,
            DungeonFilter  = {},        -- [activityGroupID] = true
            PartyFit       = false,     -- shown as "Needs Role"
            HasTank        = false,
            HasHealer      = false,
            SortBy         = "DEFAULT", -- DEFAULT / OVERALL_SCORE / DUNGEON_SCORE
            SortDescending = true,
        },

        -- Quick Create: a row of season-dungeon buttons on the Group Finder
        -- Entry Creation form. One click lists a group for that dungeon.
        -- Ships DISABLED: it modifies a Blizzard form's layout, so it is
        -- opt-in, matching the reference.
        LFGQuickCreate = {
            Enabled          = false,
            QuickCreate      = true,
            DefaultPlaystyle = 1,
            DoubleClickStart = true,
        },

        -- Popup with a one-click dungeon teleport when you join a Group
        -- Finder group. Hides on entering the dungeon, leaving the group,
        -- or entering combat.
        LFGReminder = {
            Enabled     = true,
            Scale       = 1.05,
            ShowDisable = true,
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
        },

        Recuperate = {
            Enabled = false,
            LoadInRaid = true,
            LoadInParty = false,
            Size = 40,
            anchorFrameType = "PLAYERFRAME",
            ParentFrame = "UIParent",
            Strata = "MEDIUM",
            Position = { AnchorFrom = "RIGHT", AnchorTo = "RIGHT", XOffset = -36, YOffset = 0 },
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

        CharacterPanel = {
            -- Master
            Enabled                  = true,

            -- Warning text (KE-original, preserved)
            ShowEnchants             = true,
            ShowMissingGems          = true,
            HideCharacterBackground  = false,

            -- Decimal item level (ElvUI-gated)
            DecimalItemLevel         = true,

            -- Character text features (ElvUI-gated)
            ShowRaceText             = true,
            ShowFactionOnLevel       = true,

            -- Item track indicators (no ElvUI conflict)
            TrackIndicatorsEnabled   = true,
            TrackLetterSize          = 14,

            -- Gem socket helper (no ElvUI conflict)
            SocketHelperEnabled      = true,
            SocketButtonSize         = 24,
            SocketButtonSpacing      = 1,
            ShowOnlyEmptySockets     = false,

            -- Per-slot detail overlays (no ElvUI conflict)
            ShowSlotItemLevel    = true,
            ShowEnchantNames     = true,
            ShowSlotGems         = true,
            SlotInfoFontSize     = 15,

            -- Shared font face/outline (warnings + character panel text)
            FontFace                 = "Expressway",
            FontOutline              = "OUTLINE",

            -- Warning text size (independent)
            FontSize                 = 14,

            -- Character panel text sizes (ElvUI-gated)
            LevelTextSize            = 13,
            NameTextSize             = 14,
            StatsFontSize            = 13,
            CategoryFontSize         = 13,
            IlvlValueSize            = 18,
        },

        -- Map scale. Extracted from the removed WorldMap module. Not a CVar:
        -- this is WorldMapFrame:SetScale(). Its own module (not a lodger in
        -- Automation) so it keeps an independent enable state.
        -- Default matches the old WorldMap.ScaleEnabled so existing users keep
        -- the behaviour they have today.
        MapScale = {
            Enabled = true,
            Scale = 1.2,
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

            -- Runtime memory (persisted): last flask stat the player had buffed
            -- ("mastery" / "haste" / "crit" / "vers"). Multiple flask items can map
            -- to the same buff, and `pairs(FLASKS)` ordering is non-deterministic,
            -- so without a preference the click button picks a random flask when the
            -- bag holds more than one stat. UpdateFlask updates this whenever a
            -- flask buff is detected — mirrors BR's ConsumableMemory aura path.
            LastFlaskStat = nil,

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

        AuraExternals = {
            Enabled           = true,
            ShowBigDefensives = false,
            Strata            = "MEDIUM",
            anchorFrameType   = "PLAYERFRAME",
            ParentFrame       = "UIParent",
            Position          = { AnchorFrom = "BOTTOMRIGHT", AnchorTo = "TOPRIGHT", XOffset = 0, YOffset = 81 },
            IconSize          = 52,
            IconSpacing       = 1,
            IconsPerRow       = 2,
            MaxRows           = 2,
            Swipe             = false,
            Reverse           = true,
            GrowHorizontal    = "LEFT",
            GrowVertical      = "UP",
            GlowEnabled       = true,
            GlowType          = "pixel",
            GlowColor         = { 0, 1, 0, 1 },
            -- PixelGlow extended params (passed to LCG.PixelGlow_Start)
            GlowLines         = 8,
            GlowFrequency     = 0.25,
            GlowLength        = 10,
            GlowThickness     = 1,
            GlowBorder        = false,
            GlowScale         = 1.0,
            GlowStartAnim     = true,
            GlowDuration      = 1.0,
            SoundEnabled      = false,
            SoundName         = "None",
            FontFace          = "Expressway",
            FontSize          = 14,
            FontOutline       = "OUTLINE",
            TimerFontSize     = 18,
            TimerPosition     = { AnchorFrom = "CENTER", AnchorTo = "CENTER", XOffset = 0, YOffset = 0 },
            StackPosition     = { AnchorFrom = "BOTTOMRIGHT", AnchorTo = "BOTTOMRIGHT", XOffset = -1, YOffset = 1 },
        },

        AuraDebuffs = {
            Enabled            = true,
            Strata             = "MEDIUM",
            anchorFrameType    = "PLAYERFRAME",
            ParentFrame        = "UIParent",
            Position           = { AnchorFrom = "BOTTOMLEFT", AnchorTo = "TOPLEFT", XOffset = 0, YOffset = 1 },
            IconSize           = 52,
            IconSpacing        = 1,
            IconsPerRow        = 3,
            MaxRows            = 2,
            Swipe              = true,
            Reverse            = true,
            GrowHorizontal     = "RIGHT",
            GrowVertical       = "UP",
            BorderColor        = { 0.8, 0, 0, 1 },
            BorderColorMode    = "dispel",
            -- DispelColors are user overrides; the GUI's DISPEL_DEFAULTS
            -- table provides the AE-matched fallback colors when nil.
            -- All 7 types Blizzard surfaces (incl. None/Enrage) are valid keys.
            DispelColors = {
                None    = nil,
                Magic   = nil,
                Curse   = nil,
                Disease = nil,
                Poison  = nil,
                Bleed   = nil,
                Enrage  = nil,
            },
            -- "Filtering Options" — each enabled filter REMOVES matching auras
            -- from tracking. Default PLAYER=true because the player's own
            -- debuffs are usually not what you want on a boss-debuff tracker.
            -- RAID_IN_COMBAT is HELPFUL-only per AuraUtil.AuraFilters, so it
            -- isn't surfaced here.
            Filters = {
                PLAYER                  = true,
                RAID                    = false,
                CROWD_CONTROL           = false,
                IMPORTANT               = false,
                RAID_PLAYER_DISPELLABLE = false,
                INCLUDE_NAME_PLATE_ONLY = false,
            },
            Blocklist     = {},
            FontFace      = "Expressway",
            FontSize      = 14,
            FontOutline   = "OUTLINE",
            TimerFontSize = 16,
            TimerPosition  = { AnchorFrom = "CENTER",      AnchorTo = "CENTER",      XOffset = 0, YOffset = 0 },
            StackPosition  = { AnchorFrom = "BOTTOMRIGHT", AnchorTo = "BOTTOMRIGHT", XOffset = 0, YOffset = 2 },
            DispelPosition = { AnchorFrom = "TOPRIGHT",    AnchorTo = "TOPRIGHT",    XOffset = 0, YOffset = 0 },
        },

        TargetedSpells = {
            Enabled = true,
            IconSize = 36,
            Gap = 3,
            TextSpacing = 45,           -- middle countdown slot width (px)
            Grow = "UP",                -- "DOWN" | "UP" only (no horizontal in v1)
            MaxIcons = 10,              -- entry cap; invisible entries count (secret targeting)
            FontFace = "Expressway",
            FontSize = 32,
            FontOutline = "OUTLINE",    -- no SOFTOUTLINE (widget-managed countdown text)
            FontColor = { 1, 0.976, 0.153, 1 }, -- countdown text #FFF927 (plain values into SetTextColor)
            Decimals = 1,               -- countdown digits below 60s (0-2)
            GlowImportant = true,
            IndicateInterrupts = true,
            ShowInDungeons = true,
            ShowInDelves = true,
            ShowInRaids = false,
            ShowInOpenWorld = false,
            ShowInPvP = false,
            Strata = "MEDIUM",
            anchorFrameType = "UIPARENT",
            ParentFrame = "UIParent",
            Position = DefaultPosition(0, 0),
            CVarDeclined = false,       -- internal: nameplateShowOffscreen prompt
            EnableFixup = false,        -- internal: one-time v3.2.1 enable migration
        },

        CopyAnything = {
            Enabled = false,
            Key = "C",
            Modifier = "ctrl",
        },

        AlertFrames = {
            Enabled = false,
            Position = {
                AnchorFrom = "TOP",
                AnchorTo = "TOP",
                XOffset = 0,
                YOffset = -60,
            },
            MoveEventToasts = false,
            EventToastPosition = {
                AnchorFrom = "TOP",
                AnchorTo = "TOP",
                XOffset = 0,
                YOffset = -190,
            },
        },

        MerchantPages = {
            Enabled = false,
            Pages = 2,
        },

        -----------------------------------------------------------------
        -- Dungeons Modules
        -----------------------------------------------------------------

        Dungeons = {
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
            },
            HealerMana = {
                Enabled = false,
                DisableOnHealer = false,
                Strata = "MEDIUM",
                anchorFrameType = "UIPARENT",
                ParentFrame = "UIParent",
                Position = DefaultPosition(-400, 200),
                -- Raid/Dungeon mode (added 2026-05-30)
                EnableInRaid = true,        -- master toggle: Raid Mode active at all
                MaxHealers = 6,             -- cap on raid healers shown
                ExcludeBenchGroups = true,  -- hide healers in raid subgroups 7-8 (bench convention)
                GrowDirection = "DOWN",     -- "DOWN" | "UP"
                FrameSpacing = 4,           -- px gap between stacked frames
                SplitPositioning = false,   -- off = both modes share Position
                RaidPosition = DefaultPosition(-400, 200),
                RaidAnchorFrameType = "UIPARENT",  -- Raid's own Anchored To (Dungeon uses anchorFrameType)
                RaidParentFrame = "UIParent",
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
                Enabled = true,
                EnableInDungeons = true,
                EnableInRaids = false,

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
                    -- TTS reminder: spoken when focus dies while you're in combat.
                    TTSReminder = false,
                    TTSText = "Focus Dead",
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
                    GrowthDirection = "DOWN",
                    Strata = "MEDIUM",
                    anchorFrameType = "UIPARENT",
                    ParentFrame = "UIParent",
                    Position = {
                        AnchorFrom = "CENTER",
                        AnchorTo = "CENTER",
                        XOffset = -316,
                        YOffset = 190,
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
        -- Dungeon Timers Module
        -----------------------------------------------------------------

        DungeonTimers = {
            Enabled = true,
            RoleFilterEnabled = true,
            MutePresetSounds = false,
            SoundChannel = "Master",
            SpellRoleOverrides = {},
            SpellDisabled = {},
            SpellShowAtOverrides = {},
            SpellTimeOffsets = {},
            SpellDisplayOverrides = {},
            SpellDisplayTextOverrides = {},
            SpellDecimalThresholds = {},
            SpellColorOverrides = {},
            SpellSoundsOnShow = {},
            SpellSoundsOnHide = {},

            BarDisplay = {
                barWidth = 279,
                barHeight = 27,
                fontFace = "Expressway",
                fontSize = 14,
                fontOutline = "OUTLINE",
                barTexture = "KitnUI",
                iconEnabled = true,
            },

            BarGroup = {
                AnchorFrom = "CENTER",
                AnchorTo = "CENTER",
                XOffset = 317,
                YOffset = 190,
                GrowthDirection = "DOWN",
                Spacing = 1,
                ShowAtSeconds = 10,
                Strata = "MEDIUM",
                anchorFrameType = "UIPARENT",
                ParentFrame = "UIParent",
            },

            TextDisplay = {
                fontFace = "Expressway",
                fontSize = 26,
                fontOutline = "SOFTOUTLINE",
                textAlign = "CENTER",
                -- Spell-icon prefix on text-mode timers (KE-standard zoom +
                -- border, anchored to the static label so timer width changes
                -- don't shift icon/label). Matches ExBoss's "[icon] [name]
                -- [timer]" layout.
                ShowSpellIcon = true,
                -- Multiplier on the text-line height to size the icon; lets
                -- users tune the icon relative to the font without changing
                -- the font itself. Clamped 0.25-2.0 at apply time.
                IconScale = 0.7,
            },

            TextGroup = {
                AnchorFrom = "CENTER",
                AnchorTo = "CENTER",
                XOffset = 0,
                YOffset = 100,
                GrowthDirection = "DOWN",
                Spacing = 0,
                ShowAtSeconds = 5,
                Strata = "MEDIUM",
                anchorFrameType = "UIPARENT",
                ParentFrame = "UIParent",
            },
        },

        -----------------------------------------------------------------
        -- Dungeon Trash Tracker (nameplate-driven trash-cast inference)
        --
        -- A sibling of DungeonTimers that shares its GUI section but runs
        -- off nameplate cast inference rather than BigWigs. Central alerts
        -- reuse the DungeonTimers bar/text renderer + groups; only the
        -- on-plate icons are configured here. Per-ability overrides are
        -- keyed "mapID:npcID:spellID" (parallel to the DungeonTimers
        -- per-spell override tables above).
        -----------------------------------------------------------------

        DungeonTrash = {
            Enabled = true,

            -- Central bar/text alerts fully reuse DungeonTimers' Bar/Text groups:
            -- visuals (BarDisplay/TextDisplay) AND position/growth/reveal window
            -- (BarGroup/TextGroup, incl. ShowAtSeconds). A trash alert in "bar"
            -- mode lands on the boss BAR stack, "text" on the boss TEXT stack, at
            -- the exact same placement + reveal timing — there is no separate
            -- trash position to configure. Only the
            -- on-nameplate icons below are trash-owned config.

            -- On-nameplate cooldown icons (Phase 4 render surface).
            Nameplate = {
                ShowIcons = true,
                IconSize = 30,
                AnchorSide = "RIGHT",
                Gap = 1,
                OffsetX = 0,
                OffsetY = 0,
                BorderOverride = false,
                BorderColor = { 0.2, 0.85, 0.2, 1 },
                CountFontSize = 14,
                Strata = "MEDIUM",
            },

            -- Per-ability overrides (keyed "mapID:npcID:spellID"). Keep this
            -- list in lockstep with TrashConfig.lua's OVERRIDE_TABLES — an
            -- undeclared table still works (ovTable lazy-creates) but AceDB's
            -- logout defaults-stripping then leaves empty `{}` clutter in the
            -- SavedVariables forever.
            SpellDisabled = {},
            SpellColorOverrides = {},
            SpellDisplayOverrides = {},
            SpellNameplateOverrides = {},
            SpellRoleOverrides = {},
            SpellSoundOverrides = {},
            SpellLabelOverrides = {},
            SpellRevealOverrides = {},
            SpellDecimalThresholds = {},
        },

        -----------------------------------------------------------------
        -- Damage Meter Module
        --
        -- Module-owned defaults (MPT pattern): the canonical table is
        -- DM_DEFAULTS in Modules/DamageMeter/Core.lua, seeded + bound by
        -- DM:UpdateDB. No section here on purpose -- don't re-add one.
        -----------------------------------------------------------------

        -----------------------------------------------------------------
        -- Skinning Modules
        -----------------------------------------------------------------

        Skinning = {
            Tooltips = {
                Enabled = false,
                BackdropColor = { 0.063, 0.063, 0.063, 0.9 },
                BorderColor = { 0, 0, 0, 1 },
                FontFace = "Expressway",
                FontOutline = "OUTLINE",
                FontSize = 12,
                HeaderFontSize = 14,
                SmallFontSize = 11,
                HealthBarHidden = false,
                HealthBarHeight = 7,
                HealthBarTexture = "Blizzard",
                HealthBarText = true,
                HealthTextSize = 10,
                ClassColorNames = true,
                GuildColorEnabled = true,
                -- ElvUI's guild green (|cff00ff10), which the rank shares.
                GuildColor = { r = 0, g = 1, b = 0.0627 },
                TargetLine = true,
                GuildRankLine = false,
                HideGuildRealm = false,
                HideFactionLine = true,
                AlwaysShowRealm = false,
                CompareHeader = false,
                MythicPlusLine = false,
                HideInCombat = false,
                CursorAnchor = false,
                CursorOffsetX = 10,
                CursorOffsetY = -10,
                ShowIDs = "MODIFIER",
                Position = {
                    AnchorFrom = "BOTTOMRIGHT",
                    AnchorTo = "BOTTOMRIGHT",
                    XOffset = -120,
                    YOffset = 220,
                    AnchorFrameType = "SCREEN",
                    ParentFrame = "UIParent",
                    Strata = "TOOLTIP",
                },
            },
            Chat = {
                Enabled = false,
                Width = 448,
                Height = 245,
                FontFace = "Expressway",
                FontOutline = "OUTLINE",
                FontSize = 14,
                TabFontSize = 12,
                EditBoxFontSize = 14,
                ShortChannels = true,
                FadeEnabled = true,
                FadeTime = 30,
                MaxLines = 500,
                TimestampFormat = "[%H:%M] ",
                UseLocalTime = true,
                TimestampColorEnabled = true,
                TimestampColor = { r = 0.6, g = 0.6, b = 0.6 },
                Backdrop = {
                    Enabled = true,
                    -- #080808 @ 80% -- matches the Damage Meter backdrop
                    -- (Modules/DamageMeter/Core.lua:194) so the two panels
                    -- read as one family on screen.
                    Color = { 0.031, 0.031, 0.031, 0.8 },
                    BorderColor = { 0, 0, 0, 1 },
                },
                EditBox = {
                    -- Opaque on purpose: at 0.8 the tab strip behind the edit
                    -- box bleeds through its text (ABOVE_CHAT_INSIDE overlaps
                    -- the tab bar).
                    BackdropColor = { 0.031, 0.031, 0.031, 1 },
                    BorderColor = { 0, 0, 0, 1 },
                },
                TabBackdrop = {
                    -- Off by default so the tab strip blends into the panel.
                    -- When on, this frame draws its own solid 1px border over
                    -- the panel backdrop, which reads as a seam across the
                    -- top of the chat window.
                    Enabled = false,
                    Color = { 0, 0, 0, 0.2 },
                    BorderColor = { 0, 0, 0, 1 },
                },
                FadeTabs = true,
                EditBoxPosition = "ABOVE_CHAT_INSIDE",
                NumScrollMessages = 3,
                TabSelector = "NONE",
                TabSelectorColor = { r = 1, g = 1, b = 1 },
                TabSelectedTextEnabled = true,
                TabSelectedTextColor = { r = 1, g = 0, b = 0.549 },  -- #FF008C
                TabTextColor = { r = 0.57, g = 0.57, b = 0.57 },
                TabFontOutline = "OUTLINE",
                anchorFrameType = "UIPARENT",
                ParentFrame = "UIParent",
                Position = {
                    AnchorFrom = "BOTTOMLEFT",
                    AnchorTo = "BOTTOMLEFT",
                    XOffset = 1,
                    YOffset = 1,
                },
                WhisperSounds = {
                    Enabled = false,
                    WhisperSound = "None",
                    BNetWhisperSound = "None",
                },
                ClassColorWhispers = true,
                GuildMemberStatus = true,
                GuildMemberStatusInviteLink = true,
                RoleIcons = true,
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
            BlizzardFrames = {
                Enabled    = false,
                FontOffset = 0,
                -- Global outline switch for skinned Blizzard text. The skin
                -- asks for OUTLINE at 104 call sites (the reference's design);
                -- at 12px that dilate closes the counters of tight glyphs and
                -- dense lists like the guild roster read as blobby. Off by
                -- default, matching EllesmereUI, which never outlines Blizzard
                -- text. On restores every call site's designed outline.
                FontOutline = false,
                -- Base point size the global Blizzard font override scales
                -- from. Every font object keeps its own relative size; this
                -- moves them together. 12 is Blizzard's own baseline.
                FontBaseSize = 12,
                -- Per-frame opt-out. A missing key means ON; only an
                -- explicit false disables a skin. The registry's gate reads
                -- Skins[key] ~= false, so the polarity matters.
                Skins      = {},
            },
            -- Blizzard's UI widget frames: the top-centre status bars and text
            -- widgets used by M+ timers, event progress, power bars and zone
            -- objectives. Standalone module, not a skin key -- it hooks the
            -- widget mixins rather than a named window.
            UIWidgets = {
                Enabled = true,
                FontFace = "Expressway",
                FontOutline = "OUTLINE",
                -- Status bar widgets (M+ timer, power bars)
                StatusBar = {
                    Enabled = true,
                    Width = 0,            -- Custom width (0 = use default)
                    StyleLabel = true,    -- Style the label above bars
                    StyleBarText = true,  -- Style text on the bar
                    LabelSize = 14,       -- Font size for labels
                    BarTextSize = 12,     -- Font size for bar text
                    StripTextures = true, -- Remove Blizzard textures and add backdrop
                    BackdropColor = { 0, 0, 0, 0.8 },
                    BorderColor = { 0, 0, 0, 1 },
                },
                -- Text widgets
                TextWidget = {
                    Enabled = true,
                    Width = 400, -- Custom width (0 = use default)
                    StyleText = true,
                    Size = 17,
                },
            },
            -- Game-wide replacement of Blizzard's shared font OBJECTS (quest
            -- text, objective tracker, number fonts, mail, tooltips...). Off by
            -- default: it changes text everywhere, not just inside skinned
            -- windows, so it is opt-in.
            BlizzardFonts = {
                Enabled = false,
                -- Per-category size overrides (GUI sliders). Unlisted objects
                -- keep their stock size scaled by BlizzardFrames.FontBaseSize.
                Sizes = {
                    Objective = 13,  -- objective tracker lines (stock 12)
                    QuestText = 13,  -- quest body text (stock 13)
                    QuestTitle = 14, -- quest titles (stock 18)
                    QuestSmall = 12, -- small quest text (stock 12)
                    MailBody = 13,   -- mail body (stock 15)
                },
            },
            -- Group loot rolls. Two mutually exclusive modes: Replace = true
            -- swaps Blizzard's chunky GroupLootFrames for a slim bar stack of
            -- our own; Replace = false skins and repositions Blizzard's own
            -- windows instead.
            LootRoll = {
                Enabled = true,
                Replace = true,
                Width = 340,
                Height = 22,
                ButtonSize = 22,
                Spacing = 1,
                NameFontSize = 13,
                BarTexture = "KitnUI", -- LSM statusbar name
                Skin = true,          -- (legacy mode) flatten + border the roll windows
                QualityBorder = true, -- quality colour: bar/icon border (both modes)
                Reposition = true,    -- (legacy mode) re-anchor the container
                Position = {
                    -- BOTTOM: the container grows upward as rolls stack,
                    -- so anchoring the bottom keeps the first roll still.
                    Point = "BOTTOM",
                    RelPoint = "CENTER",
                    X = 0,
                    Y = 205,       -- lift the stack up out of dead centre
                },
            },
            -- Compact replacement loot window: a slim one-row-per-item list at
            -- a fixed position, replacing Blizzard's LootFrame entirely while
            -- enabled. Opt-in, because the Loot skin key already styles
            -- Blizzard's own window and that is the default look.
            Loot = {
                Enabled = false,
                QualityBorder = true, -- tint the window border to the best drop
                MinWidth = 150,
                Position = {
                    Point = "TOPRIGHT",
                    RelPoint = "TOPRIGHT",
                    X = -618,
                    Y = -564,
                },
            },
            ContextMenus = {
                Enabled = false,
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
