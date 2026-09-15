-- ╔══════════════════════════════════════════════════════════╗
-- ║  BonusRoll.lua                                           ║
-- ║  Module: Bonus Roll                                      ║
-- ║  Purpose: Confirm before a bonus roll coin is spent, and ║
-- ║           pass automatically in chosen content.          ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

local BR = KitnEssentials:NewModule("BonusRoll", "AceEvent-3.0")

local CreateFrame = CreateFrame
local C_Timer = C_Timer
local GetInstanceInfo = GetInstanceInfo
local GetLootSpecialization = GetLootSpecialization
local GetSpecialization = C_SpecializationInfo.GetSpecialization
local GetSpecializationInfo = C_SpecializationInfo.GetSpecializationInfo
local GetSpecializationInfoByID = GetSpecializationInfoByID
local UnitClass = UnitClass
local RAID_CLASS_COLORS = RAID_CLASS_COLORS
local pcall, type = pcall, type
local string_format = string.format

-- No script on a Blizzard button is replaced or hooked: a replaced OnClick
-- taints the roll. An overlay Button takes the click instead, and Spend
-- presses Blizzard's own button, so the spell id and the roll call stay
-- theirs; if the overlay is ever absent their button works as it always did.

---------------------------------------------------------------------------------
-- DB
---------------------------------------------------------------------------------
function BR:UpdateDB()
    self.db = KE.db.profile.BonusRoll
end

function BR:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

function BR:ConfirmOn()
    local db = self.db
    return db ~= nil and db.Enabled == true and db.Confirm ~= false
end

function BR:ConfirmPassOn()
    return self:ConfirmOn() and self.db.ConfirmPass == true
end

---------------------------------------------------------------------------------
-- Blizzard frames, resolved at call time so a missing frame means "no
-- overlay", never a nil index at file scope.
---------------------------------------------------------------------------------
local function PromptFrame()
    local f = _G.BonusRollFrame
    return f and f.PromptFrame
end

local function TargetButton(kind)
    local p = PromptFrame()
    if not p then return nil end
    if kind == "pass" then return p.PassButton end
    return p.RollButton
end

-- "Loot Spec: |c<class>|T<icon>:0|t <name>|r", or "" when no spec resolves.
-- GetLootSpecialization returns 0 for "use current spec"; fall back to the
-- active talent spec then.
local function BuildLootSpecLine()
    local specID = GetLootSpecialization()
    local name, icon
    if specID == 0 then
        local index = GetSpecialization()
        if index then
            local info = { GetSpecializationInfo(index) }
            name = info[2]
            icon = info[4]
        end
    elseif specID then
        local info = { GetSpecializationInfoByID(specID) }
        name = info[2]
        icon = info[4]
    end
    if not name then return "" end
    local _, class = UnitClass("player")
    local color = (RAID_CLASS_COLORS[class] and RAID_CLASS_COLORS[class].colorStr) or "ffffffff"
    return string_format("Loot Spec: |c%s|T%d:0|t %s|r", color, icon or 0, name)
end

-- The spec line is optional: a resolver error must not stop the dialog
-- opening under an overlay that has already taken the click.
local function SpendText(extra)
    local text = "Spend a bonus roll on this?"
    local ok, spec = pcall(BuildLootSpecLine)
    if ok and spec ~= "" then text = text .. "\n\n" .. spec end
    if extra then text = text .. "\n\n" .. extra end
    return text
end

---------------------------------------------------------------------------------
-- Is the prompt still something we can act on? Asked when the overlay is
-- clicked and again when a dialog button is pressed: the prompt has a timer
-- and can go between the two.
---------------------------------------------------------------------------------
function BR.PromptLive(kind, featureOn, state, promptShown, promptVisible, buttonShown, buttonEnabled)
    if not featureOn then return false end
    if state ~= "prompt" then return false end
    if not promptShown or not promptVisible then return false end
    if not buttonShown then return false end
    if kind == "roll" and not buttonEnabled then return false end
    return true
end

function BR:PromptIsLive(kind, featureOn)
    local f, p, btn = _G.BonusRollFrame, PromptFrame(), TargetButton(kind)
    if not (f and p and btn) then return false end
    return BR.PromptLive(kind, featureOn, f.state, p:IsShown(), p:IsVisible(), btn:IsShown(), btn:IsEnabled())
end

---------------------------------------------------------------------------------
-- Content buckets, by instance type and difficulty. 233 (flexible Mythic) is
-- a Mythic raid here; the Combat Logger files it under its own toggle.
---------------------------------------------------------------------------------
local RAID_BUCKET = {
    [7] = "RaidLFR", [17] = "RaidLFR",
    [3] = "RaidNormal", [4] = "RaidNormal", [9] = "RaidNormal", [14] = "RaidNormal",
    [220] = "RaidNormal",
    [5] = "RaidHeroic", [6] = "RaidHeroic", [15] = "RaidHeroic",
    [16] = "RaidMythic", [233] = "RaidMythic",
    [33] = "RaidTimewalking", [151] = "RaidTimewalking",
}
local PARTY_BUCKET = {
    [1] = "DungeonNormalHeroic", [2] = "DungeonNormalHeroic",
    [23] = "DungeonMythic", [8] = "DungeonMythic",
    [24] = "DungeonTimewalking",
}
local BUCKET_LABEL = {
    OpenWorld           = "the open world",
    Delves              = "a Delve",
    Scenarios           = "a scenario",
    DungeonNormalHeroic = "a Normal or Heroic dungeon",
    DungeonMythic       = "a Mythic dungeon",
    DungeonTimewalking  = "a Timewalking dungeon",
    RaidLFR             = "LFR",
    RaidNormal          = "a Normal raid",
    RaidHeroic          = "a Heroic raid",
    RaidMythic          = "a Mythic raid",
    RaidTimewalking     = "a Timewalking raid",
}

function BR.BucketFor(instanceType, difficultyID, inDelve)
    if instanceType == "raid" then return RAID_BUCKET[difficultyID] end
    if instanceType == "party" then return PARTY_BUCKET[difficultyID] end
    if instanceType == "scenario" then return inDelve and "Delves" or "Scenarios" end
    if instanceType == "none" then return "OpenWorld" end
    return nil
end

local function InDelve()
    if not (C_PartyInfo and C_PartyInfo.IsDelveInProgress) then return false end
    local ok, inDelve = pcall(C_PartyInfo.IsDelveInProgress)
    return ok and inDelve == true
end

function BR:ContentBucket()
    local _, instanceType, difficultyID = GetInstanceInfo()
    return BR.BucketFor(instanceType, difficultyID, InDelve())
end

function BR.ShouldAutoPass(enabled, autoPass, bucket)
    if enabled ~= true or type(autoPass) ~= "table" or not bucket then return false end
    return autoPass[bucket] == true
end

---------------------------------------------------------------------------------
-- Overlays: plain Buttons over the Roll and Pass buttons, children of the
-- prompt frame so they hide with it.
---------------------------------------------------------------------------------
function BR:GetOverlay(kind)
    local key = kind == "pass" and "passOverlay" or "rollOverlay"
    local ov = self[key]
    if ov then return ov end

    local p, target = PromptFrame(), TargetButton(kind)
    if not (p and target) then return nil end

    ov = CreateFrame("Button", nil, p)
    ov:SetAllPoints(target)
    ov:SetFrameStrata(target:GetFrameStrata())
    -- Above the button and above anything the loot skin lays over it.
    ov:SetFrameLevel(target:GetFrameLevel() + 5)
    ov:RegisterForClicks("LeftButtonUp")
    ov:SetScript("OnClick", function() self:OnOverlayClick(kind) end)
    local tooltip = kind == "pass" and (_G.PASS or "Pass") or (_G.ROLL or "Roll")
    ov:SetScript("OnEnter", function(btn)
        GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
        GameTooltip:SetText(tooltip)
        GameTooltip:Show()
    end)
    ov:SetScript("OnLeave", function() GameTooltip:Hide() end)
    ov:Hide()
    self[key] = ov
    return ov
end

function BR:SyncOverlays()
    local roll = self:GetOverlay("roll")
    if roll then roll:SetShown(self:ConfirmOn()) end
    local pass = self:GetOverlay("pass")
    if pass then pass:SetShown(self:ConfirmPassOn()) end
end

---------------------------------------------------------------------------------
-- The click, the dialog, and the one place a coin can be spent
---------------------------------------------------------------------------------
local function SpendColor() return KE.Theme and KE.Theme.success end
local function PassColor() return KE.Theme and KE.Theme.error end

local function Prompt(text, acceptText, cancelText, onAccept, onCancel, acceptColor, cancelColor)
    KE:CreatePrompt("Bonus Roll", text, false, nil, false, nil, nil, nil, nil,
        onAccept, onCancel, acceptText, cancelText, nil, nil,
        { acceptColor = acceptColor, cancelColor = cancelColor, closeIsNeutral = true })
end

function BR:OnOverlayClick(kind)
    -- A disabled Roll button (BONUS_ROLL_DEACTIVATE) means the game itself
    -- would refuse; open nothing rather than a dialog that can only fail.
    local featureOn = (kind == "roll" and self:ConfirmOn()) or (kind == "pass" and self:ConfirmPassOn())
    if not self:PromptIsLive(kind, featureOn) then return end

    local onAccept
    if kind == "roll" then
        onAccept = function() self:Press("roll", "roll") end
        self.pending, self.pendingAccept = "roll", onAccept
        Prompt(SpendText(), "Spend", "Pass", onAccept,
            function() self:Press("roll", "pass") end,
            SpendColor(), PassColor())
    else
        onAccept = function() self:Press("pass", "pass") end
        self.pending, self.pendingAccept = "pass", onAccept
        Prompt("Pass on this bonus roll? The coin is kept, but the chance to use it here is gone.",
            "Pass", "Cancel", onAccept,
            function() self.pending, self.pendingAccept = nil, nil end,
            PassColor(), nil)
    end
end

-- Presses Blizzard's button. `opened` is the dialog this press belongs to,
-- `target` which of their buttons it presses.
function BR:Press(opened, target)
    if self.pending ~= opened then return end
    self.pending, self.pendingAccept = nil, nil

    if not self:PromptIsLive(target, self:ConfirmOn()) then
        KE:Print(KE:ColorTextByTheme("That bonus roll is no longer available."))
        return
    end
    local btn = TargetButton(target)
    if btn and btn.Click then btn:Click("LeftButton") end
end

-- Hides the dialog directly so neither button runs: a prompt timing out must
-- not turn into a pass. Only while the singleton still shows this module's
-- prompt (Core/Widgets.lua nils `_onAccept` on every close and overwrites it
-- on every new prompt), so a dismissed or replaced dialog is left alone.
function BR:ClosePrompt()
    local accept = self.pendingAccept
    self.pending, self.pendingAccept = nil, nil
    if not accept then return end
    local dialog = KE.activePrompt
    if dialog and dialog._onAccept == accept then
        dialog._onAccept, dialog._onCancel = nil, nil
        dialog:Hide()
        KE.activePrompt = nil
    end
end

---------------------------------------------------------------------------------
-- Auto-pass. Pass button only; says what it did and why.
---------------------------------------------------------------------------------
function BR:TryAutoPass()
    local db = self.db
    if not db then return false end
    local bucket = self:ContentBucket()
    if not BR.ShouldAutoPass(db.Enabled, db.AutoPass, bucket) then return false end
    if not self:PromptIsLive("pass", db.Enabled == true) then return false end

    local btn = TargetButton("pass")
    if not (btn and btn.Click) then return false end
    btn:Click("LeftButton")
    KE:Print(KE:ColorTextByTheme("Passed the bonus roll automatically: you are in "
        .. (BUCKET_LABEL[bucket] or bucket) .. "."))
    return true
end

---------------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------------
-- Blizzard builds the prompt from the same event in its own dispatch; a frame
-- later is early enough for the overlays and the auto-pass. A prompt that is
-- not auto-passed is announced: the coin window is easy to miss mid-fight.
function BR:OnPrompt()
    C_Timer.After(0, function()
        if not self:IsEnabled() then return end
        self:SyncOverlays()
        if self:TryAutoPass() then return end
        if self:PromptIsLive("roll", self:ConfirmOn()) then
            KE:Print(KE:ColorTextByTheme("A bonus roll is waiting: click the dice to choose Spend or Pass."))
        end
    end)
end

function BR:OnPromptGone()
    self:ClosePrompt()
end

-- Shows the dialog without a prompt. Neither button goes near a Blizzard
-- frame and `pending` stays nil, so a real prompt arriving mid-preview
-- cannot be acted on by it; `pendingAccept` is set so a disable or a
-- prompt event closes the preview like any other dialog of this module's.
function BR:PreviewPrompt()
    local onAccept = function() KE:Print(KE:ColorTextByTheme("Preview only: no coin was spent.")) end
    self.pending, self.pendingAccept = nil, onAccept
    Prompt(SpendText("|cff888888(preview: nothing will be spent)|r"), "Spend", "Pass", onAccept,
        function() KE:Print(KE:ColorTextByTheme("Preview only: nothing was passed.")) end,
        SpendColor(), PassColor())
end

---------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------
function BR:OnEnable()
    self:UpdateDB()
    if not self.db.Enabled then return end
    self:RegisterEvent("SPELL_CONFIRMATION_PROMPT", "OnPrompt")
    self:RegisterEvent("SPELL_CONFIRMATION_TIMEOUT", "OnPromptGone")
    self:RegisterEvent("BONUS_ROLL_STARTED", "OnPromptGone")
    self:RegisterEvent("BONUS_ROLL_FAILED", "OnPromptGone")
    self:RegisterEvent("BONUS_ROLL_DEACTIVATE", "OnPromptGone")
    self:SyncOverlays()
end

function BR:OnDisable()
    self:UnregisterAllEvents()
    self:ClosePrompt()
    if self.rollOverlay then self.rollOverlay:Hide() end
    if self.passOverlay then self.passOverlay:Hide() end
end

function BR:ApplySettings()
    self:UpdateDB()
    if not self.db.Enabled then return end
    if not self:ConfirmOn() then self:ClosePrompt() end
    self:SyncOverlays()
end
