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

        -- Blizzard's Group Finder advanced filter is ONE account-wide store
        -- (probed in game), so the record of whether the Group Finder Panel
        -- put the current filter there has to be account-wide too. A
        -- profile-scoped flag misses every restore: the profile manager
        -- rebinds each module's db before the enable/disable loop, so the
        -- disable would read the incoming profile's flag and skip the
        -- restore, leaving a restrictive filter behind with the module off.
        GroupFinderPanelOwnsFilter = false,

        -- Tool preferences, not module settings: they describe how edit mode
        -- behaves, so they sit beside the other account-wide entries here
        -- rather than in a profile. A per-profile grid would mean switching
        -- profiles silently changed how the tool behaves.
        EditModeGuides = {
            ShowGrid = false,
            Snapping = true,
            Spacing = 32,
        },

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
        -- for portable keys if we ever add import/export.
        Nicknames = {},
    },
    profile = {
        -- Global
        ShowChatMessage = true,
        -- Slug is Blizzard's GPU glyph renderer. On by default because the
        -- shipped configuration already rendered slugged before the setting
        -- existed; defaulting off would be a silent downgrade on upgrade.
        UseSlugFonts = true,
        -- Resolved by KE:GetFontPath whenever a module has no font of its own.
        GlobalFont = "Expressway",
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
            FontOutline = "OUTLINE",
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
            Shape = "cross",                  -- "cross" or "circle"
            AlwaysShow = false,               -- Show out of combat too, not only in combat
            Thickness = 22,
            Outline = true,
            RangeColorMeleeEnabled = false,
            RangeColorRangedEnabled = false,
            HideWhenInRange = false,          -- Only show the crosshair when the target is out of range
            OutOfRangeColor = { 1, 0, 0, 1 },
        },

        CombatRes = {
            Enabled = false,
            Strata = "HIGH",
            anchorFrameType = "UIPARENT",
            ParentFrame = "UIParent",
            Position = DefaultPosition(0, -60),
            FontSize = 16,
            FontOutline = "OUTLINE",
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
            Enabled = false,
            Strata = "MEDIUM",
            anchorFrameType = "UIPARENT",
            ParentFrame = "UIParent",
            FontSize = 16,
            FontOutline = "OUTLINE",
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
            Enabled    = false,
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
                FontSize           = 18,
                TextColor          = { 1, 1, 1, 1 },
                VisibilityOverride = nil,
                InstanceOnly       = false,
            },

            -- Taunt cooldown countdown at the cursor. Gated on the spellbook --
            -- C:_TauntEvaluateGate activates it on any spec that knows one of
            -- the tracked spells and tears it down otherwise, so Enabled=true
            -- still shows nothing on a spec that knows none. Ships OFF.
            Taunt = {
                Enabled            = false,
                Attached           = true,
                AnchorPoint        = "CENTER",
                XOffset            = 10,
                YOffset            = 10,
                FontSize           = 18,
                TextColor          = { 1, 1, 1, 1 },
                VisibilityOverride = nil,
                InstanceOnly       = false,
            },
        },

        PetStatusText = {
            Enabled = false,
            Strata = "MEDIUM",
            anchorFrameType = "UIPARENT",
            ParentFrame = "UIParent",
            Position = DefaultPosition(0, 100),
            FontSize = 26,
            FontOutline = "OUTLINE",
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
            FontOutline = "OUTLINE",
            ColorMode = "custom",
            Color = { 0.969, 0.027, 0.945, 1 },  -- #F707F1
            ShowIcons = true,
        },

        RaidNotifications = {
            Enabled = false,
            Strata = "MEDIUM",
            anchorFrameType = "UIPARENT",
            ParentFrame = "UIParent",
            Position = DefaultPosition(0, 350),
            FontSize = 37,
            FontOutline = "OUTLINE",
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
            Enabled = false,
            Position = DefaultPosition(0, -61),
            FontSize = 16,
            FontOutline = "OUTLINE",

            GrowDirection = "DOWN",
            ShowWhenReady = false,
            HideOutOfCombat = false,
            MaxRemainingEnabled = true,
            MaxRemaining = 30,
            Spacing = 2,
            Scale = 1,
            AttachToCombatTexts = false,

            -- THEME paints all three parts with the addon accent instead.
            ColorMode = "CUSTOM",
            TextColor = { 1, 1, 1, 1 },
            TimerColor = { 1, 0.82, 0, 1 },
            SeparatorColor = { 0.5, 0.5, 0.5, 1 },
            Separator = "-",

            SoundEnabled = false,
            Sound = "None",

            -- Per-spell overrides, keyed "specID:spellID". Absence means the
            -- preset's own default, so an untouched profile stores nothing.
            Spells = {},
            PreviewCount = 2,
        },

        FocusCastbar = {
            Enabled = false,
            Width = 350,
            Height = 30,
            Strata = "HIGH",
            anchorFrameType = "UIPARENT",
            ParentFrame = "UIParent",
            Position = DefaultPosition(0, 220),
            FontSize = 14,
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
            FontSize = 24,
            FontOutline = "OUTLINE",
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
            TimerFontSize = 16,
            TimerFontOutline = "OUTLINE",
            TimerTextColor = { 1, 1, 1, 1 },
            GlowEnabled = true,
            GlowType = "proc",
            GlowColor = { 0, 1, 0, 1 },
            FontSize = 14,
            FontOutline = "OUTLINE",
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

            FontSize = 16,
            FontOutline = "OUTLINE",
            ShieldColor = { 0.37, 0.82, 1, 1 },    -- cyan
            HealAbsorbColor = { 1, 0.48, 0.48, 1 }, -- red
        },

        BurningRush = {
            Enabled = false,
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
            Enabled = false,
            IconSize = 44,
            IconSpacing = 1,
            GrowDirection = "RIGHT", -- RIGHT | LEFT | UP | DOWN
            ShowTimer = true,
            DecimalThreshold = 5, -- seconds; below this the timer shows one decimal (0 = off)
            Swipe = false,
            Reverse = false,

            FontOutline = "OUTLINE",
            TimerFontSize = 18,

            Strata = "MEDIUM",
            anchorFrameType = "PLAYERFRAME",
            ParentFrame = "UIParent",
            Position = { AnchorFrom = "LEFT", AnchorTo = "BOTTOMLEFT", XOffset = 0, YOffset = -61 },
        },

        DisintegrateTicks = {
            Enabled = false,
            TickColor = { 1, 1, 1, 0.8 },
            TickWidth = 2,
            ClipWarning = {
                Enabled = true,
                Text = "DON'T CLIP",
                FontSize = 16,
                FontOutline = "OUTLINE",
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
            -- 12.0.5 made UnitStat secret during encounters. EMTracker
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
            RepairReport = true,
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
            HideBossBannerLoot = false,
            HideHelptips = true,
            OmniumCharButton = false,
            VaultCharButton = false,
            WindowButtonSize = 26,
            AutoUnwrapCollections = false,
            TrainAllButton = false,
            HideScreenshotStatus = false,
            HideErrorMessages = false,
            HideTransforms = false,
            HideTransformItems = {},
            -- CVars (merged) - boolean
            CVarsEnabled = true,
            enableFloatingCombatText = nil,
            floatingCombatTextCombatDamage_v2 = nil,
            floatingCombatTextCombatHealing_v2 = nil,
            floatingCombatTextReactives_v2 = nil,
            findYourselfModeOutline = nil,
            occludedSilhouettePlayer = nil,
            alwaysCompareItems = false,
            nameplateShowOnlyNameForFriendlyPlayerUnits = nil,
            nameplateUseClassColorForFriendlyPlayerUnitNames = nil,
            -- CVars (merged) - sliders
            SpellQueueWindow = nil,
            RAIDweatherDensity = nil,
            autoLootRate = nil,
        },

        AuctionHouseFilter = {
            Enabled = false,
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
            Enabled = false,
            DelayStop = true,
            PromptAdvanced = true,
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
            Scenario = false,
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
            NameFontSize = 12,
            NameFontOutline = "OUTLINE",
            TimerFontSize = 14,
            TimerFontOutline = "OUTLINE",
            NameColor = { 1, 1, 1, 1 },
            TimerColor = { 1, 1, 1, 1 },
            CritColor = { 1, 0, 1, 1 },
        },

        KickTracker = {
            Enabled = false,
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
            IconSize = 44,
            Alpha = 1,
            BorderColor = { 0, 0, 0, 1 },

            -- Caption above the icon. TextWrong replaces it for specs using
            -- Show Current Form, where the icon is the form being held.
            ShowText = true,
            Text = "MISSING",
            TextWrong = "WRONG",
            TextColor = { 1, 0.3, 0.3, 1 },
            FontSize = 14,
            FontOutline = "OUTLINE",

            -- Warrior defaults to Reverse Icon (show the stance you ARE in)
            -- because "wrong stance" is the useful signal there; the others
            -- show what you are missing. Paladin auras are off by default --
            -- plenty of people run whichever they like.
            ["71Enabled"] = true,  ["71ReverseIcon"] = true,
            ["72Enabled"] = true,  ["72ReverseIcon"] = true,
            ["73Enabled"] = false, ["73ReverseIcon"] = false,
            ["65Enabled"] = false, ["66Enabled"] = false, ["70Enabled"] = false,
            ["102Enabled"] = true, ["103Enabled"] = true, ["104Enabled"] = true,
            ["258Enabled"] = true,
            ["1473Enabled"] = true,

            Strata = "HIGH",
            anchorFrameType = "PLAYERFRAME",
            ParentFrame = "UIParent",
            Position = { AnchorFrom = "LEFT", AnchorTo = "LEFT", XOffset = 3, YOffset = 0 },
        },

        HuntersMark = {
            Enabled = false,
            Strata = "MEDIUM",
            anchorFrameType = "UIPARENT",
            ParentFrame = "UIParent",
            Position = DefaultPosition(0, 120),
            FontSize = 16,
            FontOutline = "OUTLINE",
            Color = { 1, 0.82, 0, 1 },
        },

        HavocTracker = {
            Enabled = false,
            Strata = "MEDIUM",
            anchorFrameType = "UIPARENT",
            ParentFrame = "UIParent",
            FontFace = nil,
            FontOutline = "OUTLINE",
            WarningText = "Havoc Target",
            WarningColor = { 1, 0.1, 0.1, 1 },
            WarningFontSize = 24,
            -- The keys here are AnchorFrom/AnchorTo/XOffset/YOffset. Any other
            -- spelling falls back to CENTER/CENTER/0/0 without an error.
            WarningPosition = { AnchorFrom = "CENTER", AnchorTo = "CENTER", XOffset = 0, YOffset = 180 },
        },

        PotionReady = {
            Enabled = false,
            InstanceOnly = true,
            CombatOnly = false,
            DisableOnHealer = false,
            Text = "Potion Ready",
            FontSize = 20,
            FontOutline = "OUTLINE",
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
            Enabled = false,
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
            -- No GUI control, deliberately: the page is a container and each
            -- feature tab owns its own switch. The container therefore stays
            -- enabled so those switches remain reachable -- the module is
            -- silent while all three features are off, which is how it ships.
            Enabled = true,

            -- Feature toggles. These are the module's real off switches.
            ResetEnabled = false,
            ResetMessage = "Instance reset!",
            RerollEnabled = false,
            YourKeyEnabled = false,

            -- Each reminder owns its own appearance. Position is the one
            -- thing they can share: YourKeyUseRerollPosition parks Your Key
            -- on the Reroll coordinates instead of its own.
            RerollSize = 64,
            RerollFontOutline = "OUTLINE",
            RerollFontSize = 36,
            RerollFontColor = { 1, 1, 1, 1 },
            RerollFontColorKey = { 1, 1, 1, 1 },
            RerollStrata = "MEDIUM",
            RerollAnchorFrameType = "UIPARENT",
            RerollParentFrame = "UIParent",
            RerollPosition = DefaultPosition(0, 165),

            -- The X offset differs from Reroll's on purpose: switching the
            -- follow off must not stack the two on identical coordinates.
            YourKeyUseRerollPosition = true,
            YourKeySize = 64,
            YourKeyFontOutline = "OUTLINE",
            YourKeyFontSize = 36,
            YourKeyFontColor = { 1, 1, 1, 1 },
            YourKeyFontColorKey = { 1, 1, 1, 1 },
            YourKeyStrata = "MEDIUM",
            YourKeyAnchorFrameType = "UIPARENT",
            YourKeyParentFrame = "UIParent",
            YourKeyPosition = DefaultPosition(150, 165),

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

        -- Mythic+ filter pane docked to the right of the Group Finder,
        -- with this week's affixes and a weekly-runs footer. On screen only
        -- while the Mythic+ search is.
        -- Ships DISABLED: it takes over Blizzard's own Group Finder filter
        -- while enabled, so it is opt-in.
        --
        -- The live filter keys below are SESSION state, not preferences: the
        -- module overwrites each of them on every OnEnable (login, reload and
        -- toggle) by design -- filters are meant to start clean each session.
        -- Do not "fix" the values here by deleting the reset; the reset is
        -- the behaviour.
        --
        -- SortBy and SortDescending are DEAD -- nothing reads them. They stay
        -- so a saved profile carrying them is still a valid shape.
        GroupFinderPanel = {
            Enabled        = false,
            DungeonFilter  = {},        -- [activityGroupID] = true
            PartyFit       = false,     -- shown as "Role Opening"
            HasTank        = false,
            HasHealer      = false,
            MinScore       = 0,         -- floor on the leader's overall M+ rating
            SortBy         = "DEFAULT",
            SortDescending = true,
        },

        -- Quick Create: a row of season-dungeon buttons on the Group Finder
        -- Entry Creation form. One click lists a group for that dungeon.
        -- Ships DISABLED: it modifies a Blizzard form's layout, so it is opt-in.
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
            Enabled     = false,
            Scale       = 1.05,
            ShowDisable = true,
        },

        PIMacroBuilder = {
            Enabled = false,
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
            WAEnabled = true,
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
            Enabled = false,
            PlaySound = true,
            SoundFile = "None",
            SoundChannel = "Master",
            ShowChatMessage = true,
            FontSize = 32,
            FontOutline = "OUTLINE",
            AlertDuration = 4,
            Strata = "HIGH",
            anchorFrameType = "UIPARENT",
            ParentFrame = "UIParent",
            Position = DefaultPosition(0, 200),
        },

        -- OFF by default: with it off the vehicle exit button's position is
        -- never touched, and whichever owner claims it keeps it.
        VehicleExit = {
            Enabled = false,
            Strata = "MEDIUM",
            anchorFrameType = "UIPARENT",
            ParentFrame = "UIParent",
            Position = DefaultPosition(0, 150),
        },

        VantusRune = {
            Enabled = false,
            ShowChatMessages = true,
            ConfirmationTimeout = 15,
        },

        CharacterPanel = {
            -- Master
            Enabled                  = false,

            -- Warning text (KE-original, preserved)
            ShowEnchants             = true,
            ShowMissingGems          = true,
            HideCharacterBackground  = false,

            -- Widen the character window so slot text clears the model
            WiderFrame               = false,

            -- Decimal item level (ElvUI-gated)
            DecimalItemLevel         = true,

            -- Character text features (ElvUI-gated)
            ShowRaceText             = true,
            ShowFactionOnLevel       = true,

            -- Slot borders tinted by item rarity (KE skinning only; ElvUI paints its own)
            SlotQualityBorders       = true,

            -- Item track indicators (no ElvUI conflict)
            TrackIndicatorsEnabled   = true,
            ShowUpgradeProgress      = true,
            TrackLetterSize          = 14,

            -- Gem socket helper (no ElvUI conflict)
            SocketHelperEnabled      = true,
            SocketButtonSize         = 24,
            SocketButtonSpacing      = 1,
            ShowOnlyEmptySockets     = false,
            -- Enchant helper shares the socket bar, so it needs both flags on
            EnchantHelperEnabled     = true,

            -- Per-slot detail overlays (no ElvUI conflict)
            -- Inspect-side overlays (own toggle; the module is a separate AceModule)
            InspectPanelEnabled  = true,
            ShowSlotItemLevel    = true,
            ShowEnchantNames     = true,
            -- short = nickname + abbreviations, verbose = keyword only, full = as the tooltip gives it
            EnchantNameStyle     = "short",
            ShowSlotGems         = true,
            SlotInfoFontSize     = 15,

            -- Shared font outline (warnings + character panel text)
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
        MapScale = {
            Enabled = false,
            Scale = 1.2,
            -- 1 is Blizzard's true fullscreen. Below it the map keeps the
            -- maximized layout but draws smaller, which needs the blackout
            -- frame cleared or the result is letterboxing.
            MaximizedScale = 1,
        },

        SpellAlerts = {
            Enabled = false,
            EnabledSpecs = {},  -- nil/missing = ON, false = OFF (per spec index)
        },

        ReadyCheckConsumables = {
            Enabled = false,
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
            FontSize = 13,
            FontOutline = "OUTLINE",

            -- Colors
            -- HeartyFoodColor: tints the food slot's duration text when the active
            -- food buff persists through death (a raid-group convention indicator).
            -- DurationColor: base color for duration + count text on all slots.
            HeartyFoodColor = { 0.2, 1.0, 0.2, 1.0 },
            DurationColor  = { 1.0, 1.0, 1.0, 1.0 },
        },

        AuraExternals = {
            Enabled           = false,
            ShowBigDefensives = false,
            HideSelfCast      = false,
            Strata            = "MEDIUM",
            anchorFrameType   = "PLAYERFRAME",
            ParentFrame       = "UIParent",
            Position          = { AnchorFrom = "BOTTOMRIGHT", AnchorTo = "TOPRIGHT", XOffset = 0, YOffset = 79 },
            IconSize          = 52,
            IconSpacing       = 1,
            IconsPerRow       = 3,
            MaxRows           = 2,
            Swipe             = false,
            Reverse           = true,
            -- Seeded rows carry default = true, which makes them undeletable
            -- in the GUI and lets the restore buttons tell a shipped row from
            -- one the user typed in. Any row may still be switched off.
            --
            -- Many rows share a name because the game returns the same name for
            -- every id of a spell. They are still distinguishable: the
            -- dropdown's own option builder appends the spell ID to every row,
            -- so the label must NOT carry one or it renders twice.
            Allowlist = {
                [33206]   = { label = "Pain Suppression",           enabled = true, default = true },
                [47788]   = { label = "Guardian Spirit",            enabled = true, default = true },
                [255312]  = { label = "Guardian Spirit",            enabled = true, default = true },
                [197268]  = { label = "Ray of Hope",                enabled = true, default = true },
                [1022]    = { label = "Blessing of Protection",     enabled = true, default = true },
                [6940]    = { label = "Blessing of Sacrifice",      enabled = true, default = true },
                [204018]  = { label = "Blessing of Spellwarding",   enabled = true, default = true },
                [102342]  = { label = "Ironbark",                   enabled = true, default = true },
                [116849]  = { label = "Life Cocoon",                enabled = true, default = true },
                [357170]  = { label = "Time Dilation",              enabled = true, default = true },
                [3411]    = { label = "Intervene",                  enabled = true, default = true },
                [147833]  = { label = "Intervene",                  enabled = true, default = true },
                [223658]  = { label = "Safeguard",                  enabled = true, default = true },
                [53480]   = { label = "Roar of Sacrifice",          enabled = true, default = true },

                -- Raid-wide cooldowns. The game flags none of these as an external
                -- defensive, so Blizzard Flagged switches every one of them off.
                [145629]  = { label = "Anti-Magic Zone",            enabled = true, default = true },
                [51052]   = { label = "Anti-Magic Zone",            enabled = true, default = true },
                [209426]  = { label = "Darkness",                   enabled = true, default = true },
                [196718]  = { label = "Darkness",                   enabled = true, default = true },
                [740]     = { label = "Tranquility",                enabled = true, default = true },
                [157982]  = { label = "Tranquility",                enabled = true, default = true },
                [1264623] = { label = "Tranquility",                enabled = true, default = true },
                [359816]  = { label = "Dream Flight",               enabled = true, default = true },
                [362361]  = { label = "Dream Flight",               enabled = true, default = true },
                [363534]  = { label = "Rewind",                     enabled = true, default = true },
                [374227]  = { label = "Zephyr",                     enabled = true, default = true },
                [31821]   = { label = "Aura Mastery",               enabled = true, default = true },
                [317929]  = { label = "Aura Mastery",               enabled = true, default = true },
                [64843]   = { label = "Divine Hymn",                enabled = true, default = true },
                [64844]   = { label = "Divine Hymn",                enabled = true, default = true },
                [81782]   = { label = "Power Word: Barrier",        enabled = true, default = true },
                [62618]   = { label = "Power Word: Barrier",        enabled = true, default = true },
                [325174]  = { label = "Spirit Link Totem",          enabled = true, default = true },
                [98008]   = { label = "Spirit Link Totem",          enabled = true, default = true },
                [97463]   = { label = "Rallying Cry",               enabled = true, default = true },
                [97462]   = { label = "Rallying Cry",               enabled = true, default = true },

                -- Support buffs someone else casts on you rather than
                -- defensives, so the game flags none of them.
                [29166]   = { label = "Innervate",                  enabled = true, default = true },
                [10060]   = { label = "Power Infusion",             enabled = true, default = true },
                [406732]  = { label = "Spatial Paradox",            enabled = true, default = true },
            },
            GrowHorizontal    = "LEFT",
            GrowVertical      = "UP",
            GlowEnabled       = true,
            GlowType          = "pixel",
            GlowColor         = { 0, 1, 0, 1 },
            -- Four of the keys below are retained but unread -- GlowLength,
            -- GlowBorder, GlowScale and GlowStartAnim -- so a profile saved by
            -- an older version still loads cleanly. GlowLines and GlowThickness
            -- became live again with the pixel style; GlowFrequency and
            -- GlowDuration were never dead.
            GlowLines         = 5,
            GlowFrequency     = 0.35,
            GlowLength        = 10,
            GlowThickness     = 2,
            GlowBorder        = false,
            GlowScale         = 1.0,
            GlowStartAnim     = true,
            GlowDuration      = 1.0,
            SoundEnabled      = true,
            -- A BigWigs sound, not one this addon ships. LibSharedMedia returns
            -- nothing for it without BigWigs installed, which reads as a sound
            -- switched on that never plays.
            SoundName         = "BigWigs: Info",
            FontSize          = 14,
            FontOutline       = "OUTLINE",
            TimerFontSize     = 18,
            TimerPosition     = { AnchorFrom = "CENTER", AnchorTo = "CENTER", XOffset = 0, YOffset = 0 },
            StackPosition     = { AnchorFrom = "BOTTOMRIGHT", AnchorTo = "BOTTOMRIGHT", XOffset = -1, YOffset = 2 },
        },

        AuraDebuffs = {
            Enabled            = false,
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
            -- table provides the fallback colors when nil.
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
            -- Optional exclusions: each enabled filter removes additional
            -- matching auras. Player/player-pet source filtering is mandatory.
            -- RAID_IN_COMBAT is HELPFUL-only per AuraUtil.AuraFilters, so it
            -- isn't surfaced here.
            Filters = {
                RAID                    = false,
                CROWD_CONTROL           = false,
                IMPORTANT               = false,
                RAID_PLAYER_DISPELLABLE = false,
                -- ON by default, unlike every other filter here. This one
                -- INVERTS: enabled means the token is absent, which is what
                -- excludes nameplate-only auras. Defaulting it off would put
                -- the token in the filter string and start showing auras this
                -- display has never shown.
                INCLUDE_NAME_PLATE_ONLY = true,
            },
            Blocklist     = {},
            FontSize      = 14,
            FontOutline   = "OUTLINE",
            TimerFontSize = 16,
            TimerPosition  = { AnchorFrom = "CENTER",      AnchorTo = "CENTER",      XOffset = 0, YOffset = 0 },
            StackPosition  = { AnchorFrom = "BOTTOMRIGHT", AnchorTo = "BOTTOMRIGHT", XOffset = 0, YOffset = 2 },
            DispelPosition = { AnchorFrom = "TOPRIGHT",    AnchorTo = "TOPRIGHT",    XOffset = 0, YOffset = 0 },
        },

        BuffTracking = {
            Enabled = false,
            ShowTooltips = true,

            IconSize = 32,
            IconSpacing = 4,
            -- Counted along the axis that fills first, so a vertical display
            -- reads this as icons per column.
            IconsPerRow = 12,
            MaxRows = 3,
            GrowHorizontal = "LEFT",
            GrowVertical = "DOWN",
            GrowAxis = "HORIZONTAL",

            -- Sorting is deliberately NOT configurable: this is skinning, and
            -- Blizzard's own order is what people expect.

            Swipe = true,
            Reverse = false,
            ShowTimer = true,

            BorderColor = { 0, 0, 0, 1 },
            EnchantBorderColor = { 0.6, 0.2, 0.9, 1 },
            StackColor = { 1, 1, 1, 1 },

            FontOutline = "OUTLINE",
            TimerFontSize = 12,
            FontSize = 12,

            Strata = "MEDIUM",
            anchorFrameType = "UIPARENT",
            ParentFrame = "UIParent",
            Position = {
                AnchorFrom = "TOPRIGHT",
                AnchorTo = "TOPRIGHT",
                XOffset = -200,
                YOffset = -20,
            },
        },

        PlayerDebuffTracking = {
            Enabled = false,
            ShowTooltips = true,

            IconSize = 32,
            IconSpacing = 4,
            IconsPerRow = 12,
            MaxRows = 2,
            GrowHorizontal = "LEFT",
            GrowVertical = "DOWN",
            GrowAxis = "HORIZONTAL",

            Swipe = true,
            Reverse = false,
            ShowTimer = true,

            -- "dispel" colours the icon ring by school; anything else paints
            -- the flat BorderColor. This is the switch the settings page shows
            -- as Color By Type.
            BorderColorMode = "dispel",
            BorderColor = { 0, 0, 0, 1 },
            EnchantBorderColor = { 0.6, 0.2, 0.9, 1 },
            StackColor = { 1, 1, 1, 1 },

            FontOutline = "OUTLINE",
            TimerFontSize = 12,
            FontSize = 12,

            Strata = "MEDIUM",
            anchorFrameType = "UIPARENT",
            ParentFrame = "UIParent",
            Position = {
                AnchorFrom = "TOPRIGHT",
                AnchorTo = "TOPRIGHT",
                XOffset = -200,
                YOffset = -160,
            },
        },

        TargetedSpells = {
            Enabled = false,
            IconSize = 36,
            Gap = 3,
            TextSpacing = 45,           -- middle countdown slot width (px)
            Grow = "UP",                -- "DOWN" | "UP" only (no horizontal in v1)
            MaxIcons = 10,              -- entry cap; invisible entries count (secret targeting)
            FontSize = 32,
            FontOutline = "OUTLINE",
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
            EnableFixup = false,        -- internal: one-time enable migration
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
            MoveEventToasts = true,
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

        ColorPicker = {
            Enabled = false,
        },

        MoveFrames = {
            Enabled = false,
        },

        RaidControl = {
            Enabled = false,
            Position = {               -- Show-button position, saved on right-drag
                bottom = false,        -- Snapped to the bottom edge instead of the top
                x = -400,              -- Horizontal offset from screen centre
            },
        },

        CompareHeader = {
            Enabled = false,
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
                FontOutline = "OUTLINE",
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
                -- Raid/Dungeon mode
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
                FontOutline = "OUTLINE",
                HighManaColor = { 1, 1, 1, 1 },
                -- No Raid* keys here on purpose: AceDB rawsets every declared default into
                -- the profile, so a declared twin could never be nil, and nil is what marks
                -- a mode as following Dungeon. SeedRaidLook is their only writer.
            },
            DeathNotifications = {
                Enabled = false,
                EnableInDungeons = true,
                EnableInRaids = false,

                FontSize = 34,
                FontOutline = "OUTLINE",

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
                Enabled = false,

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
            Enabled = false,
            RoleFilterEnabled = true,
            MutePresetSounds = false,
            SoundChannel = "Master",
            -- Last season + dungeon viewed on the Dungeons tab (GUI
            -- navigation state; the dungeon key is what selection trusts,
            -- the season is re-derived from the registry at read time).
            LastViewed = {},
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
                fontSize = 26,
                fontOutline = "OUTLINE",
                textAlign = "CENTER",
                -- Spell-icon prefix on text-mode timers (KE-standard zoom +
                -- border, anchored to the static label so timer width changes
                -- don't shift icon/label). Layout is "[icon] [name] [timer]".
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
            Enabled = false,

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
                FontOutline = "OUTLINE",
                FontSize = 12,
                HeaderFontSize = 14,
                SmallFontSize = 11,
                HealthBarHidden = false,
                HealthBarHeight = 7,
                HealthBarTexture = "Blizzard",
                -- Inert. Both controls and the handler were removed -- 12.0's
                -- tooltip health bar carries a secret 0..1 fraction, so no
                -- readout is possible. Kept only so existing
                -- profiles need no migration; do not build a control on them.
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
                MatchDamageMeterSize = false,
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
                    -- #080808 @ 80% -- matches the Damage Meter backdrop so the
                    -- two panels read as one family on screen.
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
                MergeAchievements = false,
                HighlightKeywords = "%MYNAME%",
                HighlightColor = { 0.267, 1, 0.773 },
                HighlightSound = "None",
                HighlightNoSoundInCombat = false,
                ClassColorMentions = false,
                ExcludedMentions = "",
            },
            ChatHistory = {
                -- Off by default: the marker that keeps a replayed line's
                -- original timestamp is installed by the chat skin, so with
                -- the skin off this would replay every line stamped with the
                -- login time. It also writes chat to disk, which no existing
                -- profile opted into.
                Enabled = false,
                -- Rows kept per character.
                Size = 100,
                -- Per chat type. Keys are the module's HISTORY_TYPES values.
                ShowTypes = {
                    WHISPER  = true,
                    GUILD    = true,
                    OFFICER  = true,
                    PARTY    = true,
                    RAID     = true,
                    INSTANCE = true,
                    CHANNEL  = true,
                    SAY      = true,
                    YELL     = true,
                    EMOTE    = true,
                },
            },
            ChatLinks = {
                Enabled = false,
                Icon = true,
                IconHeight = 14,
                IconWidth = 14,
                KeepRatio = true,
                NumericalQualityTier = true,
                WebAddresses = true,
                WebAddressColor = { 0.31, 0.71, 1 },
            },
            Messages = {
                Enabled = false,
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
                FontSize = 12,
                -- Three-state outline switch for skinned Blizzard text: NONE,
                -- OUTLINE, or THICK. The skin asks for OUTLINE at over a
                -- hundred call sites; at 12px that dilate closes the counters
                -- of tight glyphs, and dense lists like the guild roster read
                -- as blobby, so NONE is the default. A legacy boolean is also
                -- accepted and resolved to NONE/OUTLINE.
                FontOutline = "NONE",
                BackdropColor = { 0.031, 0.031, 0.031, 0.80 },
                BorderColor = { 0, 0, 0, 1 },
                -- Base point size the global Blizzard font override scales
                -- from. Every font object keeps its own relative size; this
                -- moves them together. 12 is Blizzard's own baseline.
                FontBaseSize = 12,
                -- Which role icon SET the Group Finder and group chat both
                -- draw. Any key of KE.ROLE_ICON_ART selects that bundled art;
                -- "blizzard" is the stock role icons; "circle" is the class
                -- circle with a borderless role glyph.
                --
                -- Those descriptions are the GROUP FINDER, which also adds a
                -- class-coloured bar under every art set. Chat reads no class
                -- at all, so it draws the art alone and falls back to the
                -- Blizzard badge for "circle" -- an icon string cannot
                -- compose a glyph over a ring. One setting, two surfaces.
                RoleIconSet = "modern",
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
                Enabled = false,
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
            -- text, objective tracker, number fonts, mail...). Off by
            -- default: it changes text everywhere, not just inside skinned
            -- windows, so it is opt-in. Tooltip fonts are NOT in its reach --
            -- the Tooltips module owns those alone.
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
                Enabled = false,
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
                -- Code-side fallback only, used when _G.LootFrame is missing
                -- (Modules/Skinning/LootFrame.lua's AnchorToBlizzardLoot).
                -- The window normally follows Blizzard's own Edit Mode loot
                -- frame position instead -- this has no control on the page.
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
    char = {
        -- Per-character chat history. Rows are appended by the ChatHistory
        -- module and trimmed to the user's cap; the typing list is the saved
        -- half of the chat edit box's Up/Down recall.
        ChatHistory = {},
        ChatTypingHistory = {},
    },
}

---------------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------------

function KE:GetDefaultDB()
    return Defaults
end

---------------------------------------------------------------------------------
-- Module Enable-Default Migration
---------------------------------------------------------------------------------
-- Every module now ships disabled so a fresh install is opt-in. AceDB strips
-- default-equal leaves at logout, so a profile that left one of these switches
-- ON carries no saved key at all -- once the default is false that is
-- indistinguishable from the user having switched it off. This walks the RAW
-- saved variables BEFORE AceDB:New and writes an explicit true wherever the key
-- is absent, so existing setups survive the flip and later profiles inherit the
-- new default. It cannot run after AceDB:New: by then the new default has been
-- copied in and the distinction is gone.
--
-- Each entry is a path whose LAST element is the key that flipped; everything
-- before it is the table path under the profile.
local FLIPPED_TO_OFF = {
    { "AlertFrames", "Enabled" },
    { "AuctionHouseFilter", "Enabled" },
    { "AuraDebuffs", "Enabled" },
    { "AuraExternals", "Enabled" },
    { "BurningRush", "Enabled" },
    { "CharacterPanel", "Enabled" },
    { "CombatLogger", "Enabled" },
    { "CombatTexts", "Enabled" },
    { "CompareHeader", "Enabled" },
    { "Cursor", "Enabled" },
    { "DamageMeter", "Enabled" },
    { "Dungeons", "DeathNotifications", "Enabled" },
    { "Dungeons", "DungeonCasts", "Enabled" },
    { "DungeonTimers", "Enabled" },
    { "DungeonTrash", "Enabled" },
    { "FocusCastbar", "Enabled" },
    { "FocusMarker", "Enabled" },
    { "GreatVaultAlert", "Enabled" },
    { "KickTracker", "Enabled" },
    { "LFGReminder", "Enabled" },
    { "MapScale", "Enabled" },
    { "MythicPlusTimer", "Enabled" },
    { "NoMovementAlert", "Enabled" },
    { "PetStatusText", "Enabled" },
    { "PIMacroBuilder", "Enabled" },
    { "PotionReady", "Enabled" },
    { "RaidNotifications", "Enabled" },
    { "ReadyCheckConsumables", "Enabled" },
    { "Skinning", "LootRoll", "Enabled" },
    { "Skinning", "UIWidgets", "Enabled" },
    { "TargetedSpells", "Enabled" },
    { "TotemTracker", "Enabled" },
    { "VantusRune", "Enabled" },

    -- KeystoneHelper's container stays enabled (its page has no master
    -- switch); its three feature toggles are the keys that flipped.
    { "KeystoneHelper", "ResetEnabled" },
    { "KeystoneHelper", "RerollEnabled" },
    { "KeystoneHelper", "YourKeyEnabled" },
}

-- Root-level table, outside every AceDB namespace so AceDB never strips it.
-- It records each path this has already handled, NOT a single done flag: a flag
-- would silently skip any entry appended to the list in a later version, and
-- once that version's default has been saved a re-run cannot tell "left on"
-- from "switched off" any more. Per path, the record is exact and self-
-- maintaining -- adding an entry migrates it, on the one condition that the
-- entry lands in the same COMMIT that flips its default. Not the same release:
-- every commit here is live in game over the symlink, so a one-commit gap is
-- long enough for a reload to save the new default and destroy the signal.
local OPT_IN_RECORD = "ModuleDefaultsOptIn"

-- Returns the table holding the flipped key, creating empty parents on the way
-- down. Bails on a saved value that is not a table rather than clobbering it.
local function ResolveParentTable(profile, path)
    local tbl = profile
    for depth = 1, #path - 1 do
        local key = path[depth]
        local node = tbl[key]
        if node == nil then
            node = {}
            tbl[key] = node
        elseif type(node) ~= "table" then
            return nil
        end
        tbl = node
    end
    return tbl
end

function KE:MigrateModuleEnableDefaults()
    local sv = _G.KitnEssentialsDB
    if type(sv) ~= "table" then
        -- Fresh install. Nothing to preserve, but the record still has to land
        -- or the next login would read the brand-new profile as a legacy one
        -- and switch every module back on.
        sv = {}
        _G.KitnEssentialsDB = sv
    end
    local record = sv[OPT_IN_RECORD]
    if type(record) ~= "table" then
        record = {}
        sv[OPT_IN_RECORD] = record
    end

    local profiles = sv.profiles
    for i = 1, #FLIPPED_TO_OFF do
        local path = FLIPPED_TO_OFF[i]
        local id = table.concat(path, ".")
        if not record[id] then
            record[id] = true
            if type(profiles) == "table" then
                local key = path[#path]
                for _, profile in pairs(profiles) do
                    if type(profile) == "table" then
                        local parent = ResolveParentTable(profile, path)
                        if parent and parent[key] == nil then
                            parent[key] = true
                        end
                    end
                end
            end
        end
    end
end

-- Straight key renames inside a block AceDB already registers. Same once-only,
-- per-entry marker as the enable-default migration above, but its own record
-- table: an id here names a rename, an id there is a dotted profile path, and
-- one table would leave a later reader unable to tell them apart.
local KEY_RENAME_RECORD = "KeyRenames"

-- `convert` turns the old saved value into the new one and is called with nil
-- for an absent key, because absent means the key sat at its OLD default and
-- AceDB stripped it at logout.
local KEY_RENAMES = {
    {
        id = "CombatLogger.ScenarioTorghast->Scenario",
        block = "CombatLogger",
        old = "ScenarioTorghast",
        new = "Scenario",
        convert = function(value) return value == true end,
    },
    {
        id = "CombatLogger.DisableACLPrompt->PromptAdvanced",
        block = "CombatLogger",
        old = "DisableACLPrompt",
        new = "PromptAdvanced",
        -- The polarity flips: the old key stored "do not ask".
        convert = function(value) return value ~= true end,
    },
}

function KE:MigrateCombatLoggerKeys()
    local sv = _G.KitnEssentialsDB
    if type(sv) ~= "table" then
        -- Fresh install. Nothing to carry, but the stamp still has to land or
        -- the next login would convert the brand-new profile's absent old keys
        -- and overwrite what the user had just chosen.
        sv = {}
        _G.KitnEssentialsDB = sv
    end

    local record = sv[KEY_RENAME_RECORD]
    if type(record) ~= "table" then
        record = {}
        sv[KEY_RENAME_RECORD] = record
    end

    local profiles = sv.profiles
    for i = 1, #KEY_RENAMES do
        local entry = KEY_RENAMES[i]
        if not record[entry.id] then
            record[entry.id] = true
            if type(profiles) == "table" then
                for _, profile in pairs(profiles) do
                    if type(profile) == "table" then
                        local block = profile[entry.block]
                        if type(block) == "table" then
                            -- A block with neither old key gets its new key at
                            -- the new default, which AceDB strips again at
                            -- logout. Harmless, and cheaper than a second test.
                            block[entry.new] = entry.convert(block[entry.old])
                            block[entry.old] = nil
                        end
                    end
                end
            end
        end
    end
end
