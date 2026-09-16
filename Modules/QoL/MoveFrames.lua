-- ╔══════════════════════════════════════════════════════════╗
-- ║  MoveFrames.lua                                          ║
-- ║  Module: Move Frames                                     ║
-- ║  Purpose: Let the player left-click and drag almost any  ║
-- ║           Blizzard window anywhere on screen.            ║
-- ║                                                          ║
-- ║  Positions are temporary by default: a window returns    ║
-- ║  to its managed spot the next time it opens. Remember    ║
-- ║  Positions (opt-in) keeps one saved point per window     ║
-- ║  and puts it back on show and after Blizzard re-points   ║
-- ║  it.                                                     ║
-- ║                                                          ║
-- ║  ONE-WAY IN PART: disabling unhooks the drag scripts,    ║
-- ║  but the SetMovable / EnableMouse flags already written  ║
-- ║  onto Blizzard frames stay until the next /reload. The   ║
-- ║  config page says so and offers the reload.              ║
-- ║                                                          ║
-- ║  A protected frame never gets SetMovable / EnableMouse   ║
-- ║  / StartMoving / SetPoint from insecure code: that       ║
-- ║  taints its tree. It drags through a secure snippet,     ║
-- ║  never in combat. Protection can arrive late (PVEFrame   ║
-- ║  gains it with its result list), so the drag handlers    ║
-- ║  re-check it per drag. The three InCombatLockdown        ║
-- ║  guards are load-bearing, never remove one.              ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class MoveFrames: AceModule, AceEvent-3.0, AceHook-3.0
---@field initialized boolean?
local MF = KitnEssentials:NewModule("MoveFrames", "AceEvent-3.0", "AceHook-3.0")

local _G = _G
local pairs, type = pairs, type
local strsplit, wipe = strsplit, wipe
local table_insert = table.insert

local InCombatLockdown, RunNextFrame = InCombatLockdown, RunNextFrame
local IsShiftKeyDown, IsControlKeyDown, IsAltKeyDown = IsShiftKeyDown, IsControlKeyDown, IsAltKeyDown
local GetCursorPosition, GetScreenWidth, GetScreenHeight = GetCursorPosition, GetScreenWidth, GetScreenHeight
local CreateFrame, UIParent = CreateFrame, UIParent

-- tDeleteItem and GenerateFlatClosure are not in the project's luacheck
-- read_globals allowlist; reach them through _G rather than widen it.
local tDeleteItem = _G.tDeleteItem
local GenerateFlatClosure = _G.GenerateFlatClosure

local C_AddOns_IsAddOnLoaded = C_AddOns.IsAddOnLoaded

local BlizzardFrames = {
    "AddonList",
    "BankFrame",
    "BonusRollFrame",
    "CatalogShopFrame",
    "ChatConfigFrame",
    "CinematicFrame",
    "ContainerFrame1",
    "ContainerFrameCombinedBags",
    "DestinyFrame",
    -- GameMenuFrame REMOVED. Making it movable means
    -- SetMovable/EnableMouse on a protected frame, which taints it, and
    -- Blizzard's Exit Game handler then calls the protected Quit() from
    -- tainted execution:
    --
    --   [KitnEssentials] Protected function violation: callback()
    --   (ADDON_ACTION_FORBIDDEN)
    --
    -- A user could not quit the game until they reloaded. Not worth a
    -- draggable menu.
    "GossipFrame",
    "GroupLootContainer",
    "GuildInviteFrame",
    "GuildRegistrarFrame",
    "HelpFrame",
    "ItemTextFrame",
    "LFDRoleCheckPopup",
    "LFGDungeonReadyDialog",
    "LFGDungeonReadyStatus",
    "LootFrame",
    "MerchantFrame",
    "ModelPreviewFrame",
    "PingSystemTutorial",
    "PVEFrame",
    "PVPReadyDialog",
    "PetitionFrame",
    "QuestFrame",
    "QuestLogPopupDetailFrame",
    "QuickKeybindFrame",
    "RaidBrowserFrame",
    "RaidParentFrame",
    "ReadyCheckFrame",
    "RecruitAFriendRecruitmentFrame",
    "RecruitAFriendRewardsFrame",
    "ReportCheatingDialog",
    "ReportFrame",
    "SettingsPanel",
    "SplashFrame",
    "TabardFrame",
    "TaxiFrame",
    "TradeFrame",
    "TutorialFrame",
    ["FriendsFrame"] = {
        "FriendsFrame.IgnoreListWindow",
    },
    ["DressUpFrame"] = {
        "DressUpFrame.CustomSetDetailsPanel",
        "DressUpFrame.SetSelectionPanel",
    },
    ["MailFrame"] = {
        "SendMailFrame",
        "MailFrameInset",
        ["OpenMailFrame"] = {
            "OpenMailFrame.OpenMailSender",
            "OpenMailFrame.OpenMailFrameInset",
        },
    },
    ["WorldMapFrame"] = {
        "QuestMapFrame",
    },
}

local BlizzardFramesOnDemand = {
    ["Blizzard_AccountStore"] = {
        "AccountStoreFrame",
    },
    ["Blizzard_AchievementUI"] = {
        ["AchievementFrame"] = {
            "AchievementFrame.Header",
            "AchievementFrame.SearchResults",
        },
    },
    ["Blizzard_AnimaDiversionUI"] = {
        ["AnimaDiversionFrame"] = {
            "AnimaDiversionFrame.ScrollContainer",
            "AnimaDiversionFrame.ReinforceProgressFrame",
        },
    },
    ["Blizzard_AlliedRacesUI"] = {
        "AlliedRacesFrame",
    },
    ["Blizzard_ArchaeologyUI"] = {
        "ArchaeologyFrame",
    },
    ["Blizzard_ArtifactUI"] = {
        "ArtifactFrame",
    },
    ["Blizzard_AuctionHouseUI"] = {
        "AuctionHouseFrame",
    },
    ["Blizzard_AzeriteEssenceUI"] = {
        "AzeriteEssenceUI",
    },
    ["Blizzard_AzeriteRespecUI"] = {
        "AzeriteRespecFrame",
    },
    ["Blizzard_AzeriteUI"] = {
        "AzeriteEmpoweredItemUI",
    },
    ["Blizzard_BehavioralMessaging"] = {
        "BehavioralMessagingDetails",
    },
    ["Blizzard_BindingUI"] = {
        "KeyBindingFrame",
    },
    ["Blizzard_BlackMarketUI"] = {
        "BlackMarketFrame",
    },
    ["Blizzard_Calendar"] = {
        ["CalendarFrame"] = {
            "CalendarCreateEventFrame",
            "CalendarCreateEventInviteListScrollFrame",
            "CalendarViewEventFrame",
            "CalendarViewEventFrame.HeaderFrame",
            "CalendarViewEventInviteListScrollFrame",
            "CalendarViewHolidayFrame",
        },
    },
    ["Blizzard_ChallengesUI"] = {
        "ChallengesKeystoneFrame",
    },
    ["Blizzard_Channels"] = {
        "ChannelFrame",
        "CreateChannelPopup",
    },
    ["Blizzard_ClickBindingUI"] = {
        ["ClickBindingFrame"] = {
            "ClickBindingFrame.ScrollBox",
        },
        "ClickBindingFrame.TutorialFrame",
    },
    ["Blizzard_ChromieTimeUI"] = {
        "ChromieTimeFrame",
    },
    ["Blizzard_Collections"] = {
        "CollectionsJournal",
    },
    ["Blizzard_Communities"] = {
        "ClubFinderGuildFinderFrame.RequestToJoinFrame",
        "ClubFinderCommunityAndGuildFinderFrame.RequestToJoinFrame",
        ["CommunitiesFrame"] = {
            "CommunitiesFrame.GuildMemberDetailFrame",
            "CommunitiesFrame.NotificationSettingsDialog",
        },
        "CommunitiesFrame.RecruitmentDialog",
        "CommunitiesSettingsDialog",
        "CommunitiesGuildLogFrame",
        "CommunitiesGuildNewsFiltersFrame",
        "CommunitiesGuildTextEditFrame",
    },
    ["Blizzard_CooldownViewer"] = {
        "CooldownViewerSettings",
    },
    ["Blizzard_Contribution"] = {
        "ContributionCollectionFrame",
    },
    ["Blizzard_CovenantPreviewUI"] = {
        "CovenantPreviewFrame",
    },
    ["Blizzard_CovenantRenown"] = {
        "CovenantRenownFrame",
    },
    ["Blizzard_CovenantSanctum"] = {
        "CovenantSanctumFrame",
    },
    ["Blizzard_DeathRecap"] = {
        "DeathRecapFrame",
    },
    ["Blizzard_DelvesCompanionConfiguration"] = {
        "DelvesCompanionConfigurationFrame",
        "DelvesCompanionAbilityListFrame",
    },
    ["Blizzard_DelvesDifficultyPicker"] = {
        "DelvesDifficultyPickerFrame",
    },
    ["Blizzard_EncounterJournal"] = {
        ["EncounterJournal"] = {
            "EncounterJournal.instanceSelect.ScrollBox",
            "EncounterJournal.encounter.info.overviewScroll",
            "EncounterJournal.encounter.info.detailsScroll",
        },
    },
    ["Blizzard_ExpansionLandingPage"] = {
        "ExpansionLandingPage",
    },
    ["Blizzard_FlightMap"] = {
        "FlightMapFrame",
    },
    ["Blizzard_GarrisonUI"] = {
        "GarrisonBuildingFrame",
        "GarrisonCapacitiveDisplayFrame",
        "GarrisonMissionFrame",
        "GarrisonMonumentFrame",
        "GarrisonRecruiterFrame",
        "GarrisonRecruitSelectFrame",
        "GarrisonShipyardFrame",
        "OrderHallMissionFrame",
        "BFAMissionFrame",
        ["CovenantMissionFrame"] = {
            "CovenantMissionFrame.MissionTab",
            "CovenantMissionFrame.MissionTab.MissionPage",
            "CovenantMissionFrame.MissionTab.MissionPage.CostFrame",
            "CovenantMissionFrame.MissionTab.MissionPage.StartMissionFrame",
            "CovenantMissionFrame.MissionTab.MissionList.MaterialFrame",
            "CovenantMissionFrame.FollowerList.listScroll",
            "CovenantMissionFrame.FollowerList.MaterialFrame",
        },
        ["GarrisonLandingPage"] = {
            "GarrisonLandingPageReportListListScrollFrame",
            "GarrisonLandingPageFollowerListListScrollFrame",
        },
    },
    ["Blizzard_GenericTraitUI"] = {
        ["GenericTraitFrame"] = {
            "GenericTraitFrame.ButtonsParent",
        },
    },
    ["Blizzard_GMChatUI"] = {
        "GMChatStatusFrame",
    },
    ["Blizzard_GuildBankUI"] = {
        "GuildBankFrame",
    },
    ["Blizzard_GuildControlUI"] = {
        "GuildControlUI",
    },
    ["Blizzard_GuildRename"] = {
        "GuildRenameFrame",
    },
    ["Blizzard_HouseList"] = {
        "HouseListFrame",
    },
    ["Blizzard_HousingBulletinBoard"] = {
        "HousingBulletinBoardFrame",
        "HousingInviteResidentFrame",
        "NeighborhoodChangeNameDialog",
    },
    ["Blizzard_HousingCharter"] = {
        "HousingCharterRequestSignatureDialog",
    },
    ["Blizzard_HousingCornerstone"] = {
        "HousingCornerstoneFrame",
        "HousingCornerstoneHouseInfoFrame",
        "HousingCornerstonePurchaseFrame",
        "HousingCornerstoneVisitorFrame",
        "ImportHouseConfirmationDialog",
        "MoveHouseConfirmationDialog",
    },
    ["Blizzard_HousingCreateNeighborhood"] = {
        "HousingCreateCharterNeighborhoodConfirmationFrame",
        "HousingCreateNeighborhoodCharterFrame",
    },
    ["Blizzard_HousingDashboard"] = {
        "HousingDashboardFrame",
    },
    ["Blizzard_HousingHouseFinder"] = {
        "HouseFinderFrame",
    },
    ["Blizzard_HousingHouseSettings"] = {
        "AbandonHouseConfirmationDialog",
        "HousingHouseSettingsFrame",
    },
    ["Blizzard_HousingModelPreview"] = {
        "HousingModelPreviewFrame",
    },
    ["Blizzard_InspectUI"] = {
        "InspectFrame",
    },
    ["Blizzard_IslandsPartyPoseUI"] = {
        "IslandsPartyPoseFrame",
    },
    ["Blizzard_IslandsQueueUI"] = {
        "IslandsQueueFrame",
    },
    ["Blizzard_ItemInteractionUI"] = {
        "ItemInteractionFrame",
    },
    ["Blizzard_ItemSocketingUI"] = {
        "ItemSocketingFrame",
    },
    ["Blizzard_ItemUpgradeUI"] = {
        "ItemUpgradeFrame",
    },
    ["Blizzard_Kiosk"] = {
        "GameKioskSessionStartedDialog",
    },
    ["Blizzard_MacroUI"] = {
        "MacroFrame",
    },
    ["Blizzard_MajorFactions"] = {
        "MajorFactionRenownFrame",
    },
    ["Blizzard_ObliterumUI"] = {
        "ObliterumForgeFrame",
    },
    ["Blizzard_MatchCelebrationPartyPoseUI"] = {
        "MatchCelebrationPartyPoseFrame",
    },
    ["Blizzard_OrderHallUI"] = {
        "OrderHallTalentFrame",
    },
    ["Blizzard_PlayerSpells"] = {
        "HeroTalentsSelectionDialog",
        ["PlayerSpellsFrame"] = {
            "PlayerSpellsFrame.TalentsFrame.ButtonsParent",
        },
    },
    ["Blizzard_PlayerChoice"] = {
        "PlayerChoiceFrame",
    },
    ["Blizzard_Professions"] = {
        "InspectRecipeFrame",
        "ProfessionsFrame.CraftingPage.SchematicForm.QualityDialog",
        "ProfessionsFrame.OrdersPage.OrderView.OrderDetails.SchematicForm.QualityDialog",
        ["ProfessionsFrame"] = {
            "ProfessionsFrame.CraftingPage.CraftingOutputLog",
            "ProfessionsFrame.CraftingPage.CraftingOutputLog.ScrollBox",
        },
    },
    ["Blizzard_ProfessionsBook"] = {
        "ProfessionsBookFrame",
    },
    ["Blizzard_ProfessionsCustomerOrders"] = {
        ["ProfessionsCustomerOrdersFrame"] = {
            "ProfessionsCustomerOrdersFrame.Form",
            "ProfessionsCustomerOrdersFrame.Form.CurrentListings",
        },
    },
    ["Blizzard_PVPMatch"] = {
        "PVPMatchResults",
    },
    ["Blizzard_PVPUI"] = {
        "PVPMatchScoreboard",
    },
    ["Blizzard_RemixArtifactUI"] = {
        ["RemixArtifactFrame"] = {
            "RemixArtifactFrame.Header",
            "RemixArtifactFrame.ButtonsParent",
        },
    },
    ["Blizzard_ScrappingMachineUI"] = {
        "ScrappingMachineFrame",
    },
    ["Blizzard_Soulbinds"] = {
        "SoulbindViewer",
    },
    ["Blizzard_StableUI"] = {
        "StableFrame",
    },
    ["Blizzard_SubscriptionInterstitialUI"] = {
        "SubscriptionInterstitialFrame",
    },
    ["Blizzard_TalentUI"] = {
        "PlayerTalentFrame",
    },
    ["Blizzard_TimeManager"] = {
        "TimeManagerFrame",
    },
    ["Blizzard_TokenUI"] = {
        "CurrencyTransferMenu",
    },
    ["Blizzard_TorghastLevelPicker"] = {
        "TorghastLevelPickerFrame",
    },
    ["Blizzard_TrainerUI"] = {
        "ClassTrainerFrame",
    },
    ["Blizzard_Transmog"] = {
        "TransmogFrame",
    },
    ["Blizzard_UIPanels_Game"] = {
        ["CharacterFrame"] = {
            "CurrencyTransferLog",
            "PaperDollFrame",
            "ReputationFrame",
            "TokenFrame",
            "TokenFramePopup",
        },
    },
    ["Blizzard_VoidStorageUI"] = {
        "VoidStorageFrame",
    },
    ["Blizzard_WarfrontsPartyPoseUI"] = {
        "WarfrontsPartyPoseFrame",
    },
    ["Blizzard_WeeklyRewards"] = {
        "WeeklyRewardsFrame",
    },
}

-- State ----------------------------------------------------------------------

local disabled = {}    -- [frame] = true while movement is suppressed via SetMovable API
local moveTargets = {} -- [handle frame] = frame that actually moves
local secureDrag = {}  -- .frame plus press-time cursor and centre while a protected drag is live

local framePaths = {}  -- [frame] = dotted path it was registered under; keys the saved positions
local applying = {}    -- [frame] = true while our own SetPoint is in flight
local onShowExtra = {} -- [frame] = work Frame_OnShow runs after the saved point is applied

-- Put back where it was dragged, the choice dialog opens off its own layout,
-- the bonus roll prompt off the anchor Alert Frames gives it, and the loot
-- container off Blizzard's managed layout; a drag on those is temporary.
local IGNORE_REMEMBER = {
    BonusRollFrame = true,
    GroupLootContainer = true,
    PlayerChoiceFrame = true,
}

local MODIFIER_DOWN = {
    SHIFT = IsShiftKeyDown,
    CTRL = IsControlKeyDown,
    ALT = IsAltKeyDown,
}

-- Hold To Move: NONE (or anything unknown) means any left-drag moves the window.
local function ModifierHeld(modifier)
    local fn = MODIFIER_DOWN[modifier or "NONE"]
    return (not fn) or fn() == true
end

-- Combat deferral: a minimal local queue drained on PLAYER_REGEN_ENABLED.
local combatQueue = {}
local function AfterCombat(fn)
    if not InCombatLockdown() then
        fn()
        return
    end
    table_insert(combatQueue, fn)
    MF:RegisterEvent("PLAYER_REGEN_ENABLED", "DrainCombatQueue")
end

function MF:DrainCombatQueue()
    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
    local queue = combatQueue
    combatQueue = {}
    for _, fn in pairs(queue) do
        fn()
    end
end

-- Resolve "A.B.C" dotted paths or direct frame refs
local function GetFrame(frameOrName)
    local frame
    if frameOrName then
        if frameOrName.GetName then
            frame = frameOrName
        else
            frame = _G
            local path = { strsplit(".", frameOrName) }
            for i = 1, #path do
                frame = frame and frame[path[i]]
            end
        end
    end
    return frame
end

-- Secure drag ------------------------------------------------------------------
-- Insecure SetMovable / EnableMouse / StartMoving / SetPoint on a protected
-- frame taint its tree; PVEFrame is protected once its result list is up,
-- and that list compares secret values. A protected frame is moved only by
-- a secure snippet, which taints nothing, and never in combat.

local function IsProtectedFrame(frame)
    return frame and frame.IsProtected and frame:IsProtected() == true
end

-- Created on first use (the positioner by the first secure positioning
-- request, the updater by the first protected drag), so nothing exists
-- until one happens.
local securePositioner, secureDragUpdater

-- Parented to UIParent so self:GetParent() inside the snippet IS UIParent:
-- every point it writes is relative to that.
local function SecureSetPoint(frame, point, relPoint, x, y)
    if InCombatLockdown() then return false end
    if not securePositioner then
        securePositioner = CreateFrame("Frame", nil, UIParent, "SecureHandlerBaseTemplate")
    end
    securePositioner:SetFrameRef("f", frame)
    securePositioner:SetAttribute("p", point)
    securePositioner:SetAttribute("rp", relPoint)
    securePositioner:SetAttribute("x", x)
    securePositioner:SetAttribute("y", y)
    securePositioner:Execute([[
        local f = self:GetFrameRef("f")
        if not f then return end
        f:ClearAllPoints()
        f:SetPoint(self:GetAttribute("p"), self:GetParent(), self:GetAttribute("rp"), self:GetAttribute("x"), self:GetAttribute("y"))
    ]])
    return true
end

local function StopSecureDrag()
    if secureDragUpdater then secureDragUpdater:Hide() end
    secureDrag.frame = nil
end

-- Moves the dragged frame's centre by the cursor's travel since the press,
-- clamped so the centre stays on screen (a protected frame never gets
-- SetClampedToScreen). Shown only while a protected drag is live. A window
-- hidden mid-drag (Escape with the button held) gets no OnMouseUp, so the
-- updater ends that drag itself.
local function SecureDrag_OnUpdate()
    local frame = secureDrag.frame
    if not frame or InCombatLockdown() or not frame:IsVisible() then
        StopSecureDrag()
        return
    end
    local cx, cy = GetCursorPosition()
    local es = frame:GetEffectiveScale()
    local ues = UIParent:GetEffectiveScale()
    local ucx, ucy = UIParent:GetCenter()
    if not (es and ues and ucx and es > 0 and ues > 0) then return end
    local sx = secureDrag.startX + (cx - secureDrag.cursorX)
    local sy = secureDrag.startY + (cy - secureDrag.cursorY)
    local sw, sh = GetScreenWidth() * ues, GetScreenHeight() * ues
    if sx < 0 then sx = 0 elseif sx > sw then sx = sw end
    if sy < 0 then sy = 0 elseif sy > sh then sy = sh end
    applying[frame] = true
    SecureSetPoint(frame, "CENTER", "CENTER", (sx - ucx * ues) / es, (sy - ucy * ues) / es)
    applying[frame] = nil
end

local function StartSecureDrag(frame)
    if InCombatLockdown() then return end
    local fcx, fcy = frame:GetCenter()
    local es = frame:GetEffectiveScale()
    if not (fcx and fcy and es) then return end
    if not secureDragUpdater then
        secureDragUpdater = CreateFrame("Frame")
        secureDragUpdater:SetScript("OnUpdate", SecureDrag_OnUpdate)
    end
    secureDrag.frame = frame
    secureDrag.cursorX, secureDrag.cursorY = GetCursorPosition()
    secureDrag.startX, secureDrag.startY = fcx * es, fcy * es
    secureDragUpdater:Show()
end

-- Which drag a press gets: "secure" for a protected frame out of combat,
-- "native" for an ordinary frame, nil for none.
local function DragPath(button, modifierHeld, protected, inCombat, isDisabled)
    if button ~= "LeftButton" or isDisabled or not modifierHeld then return nil end
    if protected then
        if inCombat then return nil end
        return "secure"
    end
    return "native"
end

-- Remembered positions ---------------------------------------------------------
-- One saved point per window, put back from the window's OnShow and again
-- whenever Blizzard re-points it: the panel manager writes the default spot
-- on every open, so a single apply never holds.

local function CanRemember(self, frame)
    local db = self.db
    if not (db and db.RememberPositions) or self.StopRunning then return false end
    local path = framePaths[frame]
    if not path or IGNORE_REMEMBER[path] then return false end
    return true, path
end

function MF:Remember(frame)
    local ok, path = CanRemember(self, frame)
    if not ok then return end
    local p, rel, rp, x, y = frame:GetPoint(1)
    if not p or not KE:IsSafeValue(x) or not KE:IsSafeValue(y) then return end
    -- Stops the client's layout cache restoring the dragged spot on its own.
    -- An insecure write, so never on a protected window.
    if frame.SetUserPlaced and not IsProtectedFrame(frame) then frame:SetUserPlaced(false) end
    local db = self.db
    if type(db.Positions) ~= "table" then db.Positions = {} end
    db.Positions[path] = {
        point = p,
        relativeTo = (rel and rel.GetName and rel:GetName()) or "UIParent",
        relPoint = rp or p,
        x = x,
        y = y,
    }
end

function MF:ApplySaved(frame)
    local ok, path = CanRemember(self, frame)
    if not ok then return end
    local rec = self.db.Positions and self.db.Positions[path]
    if not rec or not rec.point then return end
    applying[frame] = true
    if IsProtectedFrame(frame) then
        -- The snippet anchors to UIParent by construction.
        SecureSetPoint(frame, rec.point, rec.relPoint or rec.point, rec.x or 0, rec.y or 0)
    else
        local rel = (rec.relativeTo and _G[rec.relativeTo]) or UIParent
        frame:ClearAllPoints()
        frame:SetPoint(rec.point, rel, rec.relPoint or rec.point, rec.x or 0, rec.y or 0)
    end
    applying[frame] = nil
end

-- Post-hooks on the moving frame. `applying` breaks the recursion from our
-- own write; a live secure drag is never fought.
function MF:Frame_OnSetPoint(frame)
    if applying[frame] or secureDrag.frame == frame then return end
    self:ApplySaved(frame)
end

function MF:Frame_OnShow(frame)
    self:ApplySaved(frame)
    local extra = onShowExtra[frame]
    if extra then extra(frame) end
end

-- Windows return to Blizzard's layout the next time they open; one that is
-- open now stays put until then.
function MF:ResetPositions()
    if self.db and type(self.db.Positions) == "table" then wipe(self.db.Positions) end
end

-- Movement handlers ----------------------------------------------------------

function MF:Frame_StartMoving(this, button)
    if InCombatLockdown() and this:IsProtected() then
        return
    end
    local moveTarget = moveTargets[this]
    if not moveTarget then return end
    local protected = IsProtectedFrame(moveTarget) or IsProtectedFrame(this)
    local path = DragPath(button, ModifierHeld(self.db and self.db.Modifier), protected,
        InCombatLockdown(), disabled[moveTarget])
    if path == "secure" then
        StartSecureDrag(moveTarget)
    elseif path == "native" and moveTarget:IsMovable() then
        moveTarget:StartMoving()
    end
end

function MF:Frame_StopMoving(this, button)
    if InCombatLockdown() and this:IsProtected() then
        return
    end
    local moveTarget = moveTargets[this]
    if button ~= "LeftButton" or not moveTarget then return end
    if IsProtectedFrame(moveTarget) or IsProtectedFrame(this) then
        if secureDrag.frame == moveTarget then
            StopSecureDrag()
            self:Remember(moveTarget)
        end
        return
    end
    moveTarget:StopMovingOrSizing()
    self:Remember(moveTarget)
end

function MF:HandleFrame(this, bindTo)
    local thisFrame = GetFrame(this)
    local bindingTargetFrame = GetFrame(bindTo)

    if not thisFrame or moveTargets[thisFrame] then
        return
    end

    if InCombatLockdown() and thisFrame:IsProtected() then
        AfterCombat(function()
            self:HandleFrame(this, bindTo)
        end)
        return
    end

    local target = bindingTargetFrame or thisFrame
    -- Protection can arrive after this runs (PVEFrame gains it with its
    -- result list); the drag handlers re-check it per press.
    if not (IsProtectedFrame(thisFrame) or IsProtectedFrame(target)) then
        thisFrame:SetMovable(true)
        thisFrame:SetClampedToScreen(true)
        thisFrame:EnableMouse(true)
    end
    moveTargets[thisFrame] = target

    -- Saved positions key on the dotted path of the frame that MOVES, so a
    -- window reached through a handle stores under the window.
    framePaths[thisFrame] = framePaths[thisFrame]
        or (type(this) == "string" and this)
        or (thisFrame.GetName and thisFrame:GetName())
    if not framePaths[target] then
        framePaths[target] = (type(bindTo) == "string" and bindTo) or framePaths[thisFrame]
    end

    self:SecureHookScript(thisFrame, "OnMouseDown", "Frame_StartMoving")
    self:SecureHookScript(thisFrame, "OnMouseUp", "Frame_StopMoving")

    -- Several handles can share one target; each hook goes on once.
    if not self:IsHooked(target, "OnShow") then
        self:SecureHookScript(target, "OnShow", "Frame_OnShow")
    end
    if not self:IsHooked(target, "SetPoint") then
        self:SecureHook(target, "SetPoint", "Frame_OnSetPoint")
    end
    if target:IsVisible() then self:ApplySaved(target) end
end

function MF:HandleFramesWithTable(frameTable, parent)
    for key, value in pairs(frameTable) do
        if type(key) == "number" and type(value) == "string" then
            self:HandleFrame(value, parent)
        elseif type(key) == "string" and type(value) == "table" then
            self:HandleFrame(key, parent)
            self:HandleFramesWithTable(value, key)
        end
    end
end

function MF:HandleAddon(_, addon)
    local frameTable = BlizzardFramesOnDemand[addon]
    if not frameTable then
        return
    end

    self:HandleFramesWithTable(frameTable)

    -- Frame-specific fixes
    AfterCombat(function()
        if addon == "Blizzard_EncounterJournal" then
            local replacement = function(rewardFrame)
                if rewardFrame.data then
                    _G.EncounterJournalTooltip:ClearAllPoints()
                end
                self.hooks.AdventureJournal_Reward_OnEnter(rewardFrame)
            end
            self:RawHook("AdventureJournal_Reward_OnEnter", replacement, true)
            self:RawHookScript(_G.EncounterJournal.suggestFrame.Suggestion1.reward, "OnEnter", replacement)
            self:RawHookScript(_G.EncounterJournal.suggestFrame.Suggestion2.reward, "OnEnter", replacement)
            self:RawHookScript(_G.EncounterJournal.suggestFrame.Suggestion3.reward, "OnEnter", replacement)
        elseif addon == "Blizzard_Communities" then
            local dialog = _G.CommunitiesFrame.NotificationSettingsDialog
            if dialog then
                dialog:ClearAllPoints()
                dialog:SetAllPoints()
            end
        elseif addon == "Blizzard_PlayerChoice" and _G.PlayerChoiceFrame then
            -- These three go through AceHook, never a raw HookScript, which
            -- cannot be undone. That way module disable
            -- removes them and a re-enable does not stack a second copy.
            self:SecureHookScript(_G.PlayerChoiceFrame, "OnHide", function()
                if not InCombatLockdown() or not _G.PlayerChoiceFrame:IsProtected() then
                    _G.PlayerChoiceFrame:ClearAllPoints()
                end
            end)
        elseif addon == "Blizzard_PlayerSpells" and _G.HeroTalentsSelectionDialog and _G.PlayerSpellsFrame then
            local function startStopMoving(frame)
                if not MF.initialized or IsProtectedFrame(frame) then
                    return
                end
                local backup = frame:IsMovable()
                frame:SetMovable(true)
                frame:StartMoving()
                frame:StopMovingOrSizing()
                frame:SetMovable(backup)
            end
            local function onShow(frame)
                startStopMoving(frame)
                RunNextFrame(GenerateFlatClosure(startStopMoving, frame))
            end

            startStopMoving(_G.HeroTalentsSelectionDialog)
            -- Both frames already carry the Frame_OnShow hook, and AceHook
            -- refuses a second one, so the fix rides that handler.
            for _, frame in pairs({ _G.PlayerSpellsFrame, _G.HeroTalentsSelectionDialog }) do
                if not self:IsHooked(frame, "OnShow") then
                    self:SecureHookScript(frame, "OnShow", "Frame_OnShow")
                end
                onShowExtra[frame] = onShow
            end
        end
    end)
end

-- Public API ------------------------------------------------------------------

---Whether the module is active (BlizzMove/MoveAnything defer counts as off)
function MF:IsRunning()
    return self.db and self.db.Enabled == true and not self.StopRunning
end

---Temporarily suppress/allow movement of a handled frame
function MF:SetMovable(frame, movable)
    if not self:IsRunning() then
        return
    end
    local targetFrame = GetFrame(frame)
    if not targetFrame then
        return
    end
    disabled[targetFrame] = not movable
    if not movable and secureDrag.frame == targetFrame then
        StopSecureDrag()
    end
end

-- Lifecycle -------------------------------------------------------------------

function MF:UpdateDB()
    if KE.db and KE.db.profile then
        self.db = KE.db.profile.MoveFrames
    end
end

function MF:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(self.db and self.db.Enabled == true)
end

function MF:OnEnable()
    self:UpdateDB()
    if not self.db or self.db.Enabled ~= true then return end
    if self.initialized then return end

    -- Defer to dedicated movers.
    if C_AddOns_IsAddOnLoaded("BlizzMove") then
        self.StopRunning = "BlizzMove"
        return
    end
    if C_AddOns_IsAddOnLoaded("MoveAnything") then
        self.StopRunning = "MoveAnything"
        return
    end

    self.initialized = true

    -- Trade Skill Master special handling, always on and not an option: TSM
    -- replaces the merchant frame wholesale, so excluding it is strictly
    -- correct whenever TSM is present.
    if C_AddOns_IsAddOnLoaded("TradeSkillMaster") then
        tDeleteItem(BlizzardFrames, "MerchantFrame")
    end

    -- Mail inset reparent. Not an ElvUI-only fix -- the insets are parented
    -- oddly and drag the wrong frame without it.
    if _G.MailFrameInset then
        _G.OpenMailFrameInset:SetParent(_G.OpenMailFrame)
        _G.MailFrameInset:SetParent(_G.MailFrame)
    end

    -- Always-loaded Blizzard frames
    self:HandleFramesWithTable(BlizzardFrames)

    -- Legacy PVP frame guard (nil on Midnight; ported for parity)
    if _G.BattlefieldFrame and _G.PVPParentFrame then
        _G.BattlefieldFrame:SetParent(_G.PVPParentFrame)
        _G.BattlefieldFrame:ClearAllPoints()
        _G.BattlefieldFrame:SetAllPoints()
    end

    -- Load-on-demand Blizzard frames
    self:RegisterEvent("ADDON_LOADED", "HandleAddon")
    for addon in pairs(BlizzardFramesOnDemand) do
        if C_AddOns_IsAddOnLoaded(addon) then
            self:HandleAddon(nil, addon)
        end
    end

    -- Blizzard container anchoring fights the mover; clear on layout
    -- (inert while Baganator replaces the bags).
    if _G.ContainerFrameSettingsManager then
        local GetBagsShown = _G.ContainerFrameSettingsManager.GetBagsShown
        self:SecureHook(_G.ContainerFrameSettingsManager, "GetBagsShown", function()
            for _, bag in pairs(GetBagsShown(_G.ContainerFrameSettingsManager) or {}) do
                bag:ClearAllPoints()
            end
        end)
    end
end

function MF:OnDisable()
    -- AceHook unhooks everything automatically on module disable. Wipe
    -- the bookkeeping so a mid-session re-enable rebuilds the hooks
    -- (HandleFrame early-returns on populated moveTargets otherwise).
    -- SetMovable / EnableMouse state on Blizzard frames persists until
    -- reload -- the GUI flags a reload prompt on disable.
    wipe(moveTargets)
    wipe(disabled)
    StopSecureDrag()
    wipe(combatQueue)
    wipe(framePaths)
    wipe(applying)
    wipe(onShowExtra)
    self.initialized = nil
    self.StopRunning = nil
end
