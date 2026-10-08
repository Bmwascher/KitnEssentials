-- ╔══════════════════════════════════════════════════════════╗
-- ║  GreatVaultCover.lua                                     ║
-- ║  Module: Great Vault Alert (Reward Cover)                ║
-- ║  Purpose: Hides each Great Vault reward behind a card    ║
-- ║           until it is clicked.                           ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end
local GVA = KitnEssentials:GetModule("GreatVaultAlert")

local _G = _G
local CreateFrame = CreateFrame
local PlaySound = PlaySound
local PlaySoundFile = PlaySoundFile
local hooksecurefunc = hooksecurefunc
local wipe = wipe
local pcall, type, select, ipairs, pairs, next, tostring = pcall, type, select, ipairs, pairs, next, tostring
local math_max = math.max
local math_floor = math.floor
local string_format = string.format

---------------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------------
local VAULT_ADDON = "Blizzard_WeeklyRewards"
local STORE_KEY = "GreatVaultRevealed"
local ART = "Interface\\AddOns\\KitnEssentials\\Media\\Vault\\VaultCover.png"
local ART_RIGHT, ART_BOTTOM = 438 / 512, 252 / 256
local SKULL = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_8:16|t"
local BAD_LOOT_TEXT = "GG, Fuggin Easy. Better luck next week!"
local HIGHLIGHT_ALPHA = 0.25
local PULSE_ALPHA, PULSE_SECONDS = 0.55, 1.4
-- The reveal flare keeps its own start, so a brighter breath leaves it as it is.
local REVEAL_FROM_ALPHA = 0.3
local FLARE_SECONDS, FADE_SECONDS, GROW_SCALE = 0.12, 0.38, 1.06
local JACKPOT_SECONDS = 1.5
local GOLD_R, GOLD_G, GOLD_B = 1, 0.82, 0

-- Unskinned cards take the card art's own cut-corner shape through a mask.
-- False falls back to a rectangle over the visible plate inside that art.
local MASK_TO_CARD_ART = true

-- Stored by name, played by SOUNDKIT key, so a renumbered kit cannot break a
-- saved choice. The page lists these ahead of None and the shared sounds.
GVA.COVER_SOUNDS = {
    { key = "Blizzard - Epic Loot",      kit = "UI_EPICLOOT_TOAST" },
    { key = "Blizzard - Legendary Loot", kit = "UI_LEGENDARY_LOOT_TOAST" },
    { key = "Blizzard - Gift Unwrap",    kit = "UI_STORE_UNWRAP" },
    { key = "Blizzard - Great Vault",    kit = "UI_WEEKLY_REWARD_CONFIRMED_REWARD" },
}

---------------------------------------------------------------------------------
-- Rules
---------------------------------------------------------------------------------
-- CanClaimRewards is true only at the vault itself with a reward still to
-- pick; a missing or erroring call covers nothing.
function GVA.CoverActive(listening, enabled, coverOn, canClaimFn)
    if not (listening and enabled and coverOn) then return false end
    if type(canClaimFn) ~= "function" then return false end
    local ok, can = pcall(canClaimFn)
    return ok and can == true
end

-- A currency listed ahead of the item would leave rewards[1] without an item
-- id, so the first reward that has one is used.
local function FirstItemDBID(info)
    if type(info) ~= "table" or type(info.rewards) ~= "table" then return nil end
    for _, reward in ipairs(info.rewards) do
        if type(reward) == "table" and reward.itemDBID ~= nil then
            return reward.itemDBID
        end
    end
    return nil
end

function GVA.CardKey(info)
    if type(info) ~= "table" then return nil end
    if info.claimID ~= nil then return "c" .. tostring(info.claimID) end
    local dbid = FirstItemDBID(info)
    if dbid ~= nil then return "i" .. tostring(dbid) end
    return nil
end

function GVA.CardWantsCover(active, hasRewards, key, store, seen)
    if not active or not hasRewards or seen then return false end
    if key ~= nil and type(store) == "table" and store[key] == true then return false end
    return true
end

-- An early Refresh can arrive before any reward data; with nothing on offer
-- the store is left alone rather than wiped.
function GVA.PruneRevealed(store, live)
    if type(store) ~= "table" or type(live) ~= "table" or next(live) == nil then return end
    for key in pairs(store) do
        if not live[key] then store[key] = nil end
    end
end

-- levels holds one entry per rewarded card: a number, or false when unknown.
function GVA.IsJackpot(levels, i)
    if type(levels) ~= "table" or #levels < 2 then return false end
    local mine = levels[i]
    if type(mine) ~= "number" then return false end
    for j = 1, #levels do
        local other = levels[j]
        if type(other) ~= "number" then return false end
        if j ~= i and other >= mine then return false end
    end
    return true
end

function GVA.TeaseTarget(waiting)
    if type(waiting) == "table" and #waiting == 1 then return waiting[1] end
    return nil
end

function GVA.BadLootLineShown(active, badLootOn, stripShown, noticeShown)
    return (active and badLootOn and stripShown and not noticeShown) and true or false
end

---------------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------------
local covers = {}
local flairs = {}
local seen = {}
local liveKeys = {}
local rewarded, levels, waiting = {}, {}, {}
local badLootLine

-- Read by the frame-level probe, so it needs no walk over card children.
GVA.coverFrames = covers

---------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------
local function HideTeases()
    for _, cover in pairs(covers) do cover.tease:Hide() end
end

local function HideFlavor()
    HideTeases()
    for _, flair in pairs(flairs) do flair:Hide() end
end

-- The global exists only once the load-on-demand vault addon has loaded.
local function VaultFrame()
    local wf = _G.WeeklyRewardsFrame
    if wf and type(wf.Refresh) == "function" then return wf end
    return nil
end

local function CanClaimApi()
    local api = _G.C_WeeklyRewards
    return api and api.CanClaimRewards
end

-- Activities also holds the concession plates; only cards have an ItemFrame.
local function IsCard(frame)
    return type(frame) == "table" and frame.ItemFrame ~= nil and frame.Background ~= nil
end

local function ReadStore()
    local store = KE:GetCharStore()
    local revealed = store and store[STORE_KEY]
    if type(revealed) ~= "table" then return nil end
    return revealed
end

local function WriteStore(key)
    local store = KE:GetCharStore(true)
    if not store then return end
    if type(store[STORE_KEY]) ~= "table" then store[STORE_KEY] = {} end
    store[STORE_KEY][key] = true
end

local function CollectLiveKeys(wf)
    wipe(liveKeys)
    for _, card in ipairs(wf.Activities) do
        if IsCard(card) and card.hasRewards then
            local key = GVA.CardKey(card.info)
            if key then liveKeys[key] = true end
        end
    end
    return liveKeys
end

local function MaxChildLevel(level, ...)
    for i = 1, select("#", ...) do
        local child = select(i, ...)
        if not child.keOwned then level = math_max(level, child:GetFrameLevel()) end
    end
    return level
end

-- Above every card effect and the window's reward swirl, under its controls.
local function CoverLevel(card, sceneLevel)
    return MaxChildLevel(math_max(card:GetFrameLevel(), sceneLevel), card:GetChildren()) + 2
end

local function ArtVisible(art)
    return art:IsShown() and art:GetAlpha() > 0.01 and art:GetAtlas() ~= nil
end

local function SetMasked(cover, masked)
    if cover.masked == masked then return end
    cover.masked = masked
    if masked then
        cover.face:AddMaskTexture(cover.mask)
        cover.shine:AddMaskTexture(cover.mask)
        cover.light:AddMaskTexture(cover.mask)
    else
        cover.face:RemoveMaskTexture(cover.mask)
        cover.shine:RemoveMaskTexture(cover.mask)
        cover.light:RemoveMaskTexture(cover.mask)
    end
end

-- The button always spans the whole card, so no edge of a covered card can
-- be clicked through to select it; only the face takes the card's shape. A
-- skin that hides the card art leaves a flat panel, so the face fills it
-- inside a 1 px edge.
local function PlaceCover(cover, card)
    local art = card.Background
    local face = cover.face
    cover:ClearAllPoints()
    cover:SetAllPoints(card)
    face:ClearAllPoints()
    if not ArtVisible(art) then
        local px = KE:GetPixelSize()
        face:SetPoint("TOPLEFT", cover, "TOPLEFT", px, -px)
        face:SetPoint("BOTTOMRIGHT", cover, "BOTTOMRIGHT", -px, px)
        cover.edge:Show()
        SetMasked(cover, false)
    elseif MASK_TO_CARD_ART then
        face:SetAllPoints(art)
        cover.edge:Hide()
        cover.mask:ClearAllPoints()
        cover.mask:SetAllPoints(art)
        cover.mask:SetAtlas(art:GetAtlas())
        SetMasked(cover, true)
    else
        face:SetPoint("TOPLEFT", art, "TOPLEFT", 1, -1)
        face:SetPoint("BOTTOMRIGHT", art, "BOTTOMRIGHT", -3, 3)
        cover.edge:Hide()
        SetMasked(cover, false)
    end
end

local function CardItemLink(card)
    local api = _G.C_WeeklyRewards
    if not (api and api.GetItemHyperlink) then return nil end
    local dbid = card.ItemFrame and card.ItemFrame.displayedItemDBID
    if dbid == nil then dbid = FirstItemDBID(card.info) end
    if dbid == nil then return nil end
    local ok, link = pcall(api.GetItemHyperlink, dbid)
    if ok and type(link) == "string" then return link end
    return nil
end

local function QualityColor(card)
    local items = _G.C_Item
    if not (items and items.GetItemQualityByID and items.GetItemQualityColor) then return nil end
    local link = CardItemLink(card)
    if not link then return nil end
    local ok, quality = pcall(items.GetItemQualityByID, link)
    if not ok or type(quality) ~= "number" then return nil end
    local okColor, r, g, b = pcall(items.GetItemQualityColor, quality)
    if okColor and type(r) == "number" and type(g) == "number" and type(b) == "number" then
        return r, g, b
    end
    return nil
end

local function CardItemLevel(card)
    local items = _G.C_Item
    if not (items and items.GetDetailedItemLevelInfo) then return nil end
    local link = CardItemLink(card)
    if not link then return nil end
    local ok, level = pcall(items.GetDetailedItemLevelInfo, link)
    if ok and type(level) == "number" then return level end
    return nil
end

local function NewFaceCopy(cover, layer)
    local tex = cover:CreateTexture(nil, layer)
    tex:SetTexture(ART)
    tex:SetTexCoord(0, ART_RIGHT, 0, ART_BOTTOM)
    tex:SetBlendMode("ADD")
    return tex
end

local function RefreshOpenVault()
    local wf = VaultFrame()
    if GVA._coverHooked and wf and wf:IsShown() and GVA:CoverWatched() then
        GVA:UpdateCovers()
    end
end

---------------------------------------------------------------------------------
-- Sound
---------------------------------------------------------------------------------
function GVA:PlayCoverSound(key)
    if type(key) ~= "string" or key == "None" then return end
    local channel = self.db.SoundChannel or "Master"
    for _, sound in ipairs(GVA.COVER_SOUNDS) do
        if sound.key == key then
            local kits = _G.SOUNDKIT
            local id = kits and kits[sound.kit]
            if id then PlaySound(id, channel) end
            return
        end
    end
    local path = KE.LSM and KE.LSM:Fetch("sound", key, true)
    if path then PlaySoundFile(path, channel) end
end

---------------------------------------------------------------------------------
-- Covers
---------------------------------------------------------------------------------
function GVA:CreateCover(card)
    local cover = CreateFrame("Button", nil, card)
    cover.keOwned = true
    cover:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    cover:Hide()

    local edge = cover:CreateTexture(nil, "BACKGROUND")
    edge:SetAllPoints()
    edge:SetColorTexture(0, 0, 0, 1)
    cover.edge = edge

    local face = cover:CreateTexture(nil, "BORDER")
    face:SetTexture(ART)
    face:SetTexCoord(0, ART_RIGHT, 0, ART_BOTTOM)
    face:SetAllPoints()
    cover.face = face

    local shine = NewFaceCopy(cover, "ARTWORK")
    shine:SetAllPoints(face)
    shine:SetAlpha(0)
    cover.shine = shine

    local light = NewFaceCopy(cover, "HIGHLIGHT")
    light:SetAllPoints(face)
    light:SetAlpha(HIGHLIGHT_ALPHA)
    cover.light = light

    local mask = cover:CreateMaskTexture()
    mask:SetAllPoints(cover)
    cover.mask = mask
    cover.masked = false

    local tease = cover:CreateFontString(nil, "OVERLAY")
    tease:SetPoint("BOTTOM", cover, "BOTTOM", 0, 12)
    tease:Hide()
    cover.tease = tease

    local pulse = cover:CreateAnimationGroup()
    pulse:SetLooping("BOUNCE")
    local breathe = pulse:CreateAnimation("Alpha")
    breathe:SetTarget(shine)
    breathe:SetFromAlpha(0)
    breathe:SetToAlpha(PULSE_ALPHA)
    breathe:SetDuration(PULSE_SECONDS)
    breathe:SetSmoothing("IN_OUT")
    cover.pulse = pulse

    local reveal = cover:CreateAnimationGroup()
    reveal:SetToFinalAlpha(true)
    local flare = reveal:CreateAnimation("Alpha")
    flare:SetTarget(shine)
    flare:SetFromAlpha(REVEAL_FROM_ALPHA)
    flare:SetToAlpha(1)
    flare:SetDuration(FLARE_SECONDS)
    flare:SetOrder(1)
    local fade = reveal:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0)
    fade:SetDuration(FADE_SECONDS)
    fade:SetSmoothing("IN")
    fade:SetOrder(2)
    local grow = reveal:CreateAnimation("Scale")
    grow:SetScaleFrom(1, 1)
    grow:SetScaleTo(GROW_SCALE, GROW_SCALE)
    grow:SetOrigin("CENTER", 0, 0)
    grow:SetDuration(FADE_SECONDS)
    grow:SetSmoothing("OUT")
    grow:SetOrder(2)
    reveal:SetScript("OnFinished", function() cover:Hide() end)
    cover.reveal = reveal

    cover:SetScript("OnShow", function(btn)
        btn:SetAlpha(1)
        btn.shine:SetAlpha(0)
        btn.shine:SetVertexColor(1, 1, 1)
        btn:EnableMouse(true)
        btn.pulse:Play()
    end)
    cover:SetScript("OnHide", function(btn)
        btn.pulse:Stop()
        btn.reveal:Stop()
        btn.tease:Hide()
    end)
    cover:SetScript("OnClick", function(btn) GVA:RevealCover(btn) end)

    covers[card] = cover
    return cover
end

function GVA:ShowJackpot(card)
    local flair = flairs[card]
    if not flair then
        flair = CreateFrame("Frame", nil, card)
        flair.keOwned = true
        flair:SetAllPoints(card)
        local wash = flair:CreateTexture(nil, "ARTWORK")
        wash:SetAllPoints()
        wash:SetColorTexture(GOLD_R, GOLD_G, GOLD_B, 0.35)
        wash:SetBlendMode("ADD")
        local word = flair:CreateFontString(nil, "OVERLAY")
        word:SetPoint("CENTER")
        flair.word = word
        local fade = flair:CreateAnimationGroup()
        fade:SetToFinalAlpha(true)
        local alpha = fade:CreateAnimation("Alpha")
        alpha:SetFromAlpha(1)
        alpha:SetToAlpha(0)
        alpha:SetDuration(JACKPOT_SECONDS)
        fade:SetScript("OnFinished", function() flair:Hide() end)
        -- Also hidden through the closing window: a stopped fade never
        -- reaches OnFinished, so the flair hides itself or reopens shown.
        flair:SetScript("OnHide", function(f)
            f.fade:Stop()
            f:Hide()
        end)
        flair.fade = fade
        flair:Hide()
        flairs[card] = flair
    end
    KE:ApplyFontToText(flair.word, self.db.FontFace, 22, "OUTLINE")
    flair.word:SetTextColor(GOLD_R, GOLD_G, GOLD_B)
    flair.word:SetText("Jackpot!")
    local cover = covers[card]
    flair:SetFrameLevel((cover and cover:GetFrameLevel() or card:GetFrameLevel()) + 1)
    flair.fade:Stop()
    flair:SetAlpha(1)
    flair:Show()
    flair.fade:Play()
end

function GVA:PrintCoverRecap()
    local best, bestLevel
    for i = 1, #rewarded do
        local level = levels[i]
        if not best or (type(level) == "number" and (type(bestLevel) ~= "number" or level > bestLevel)) then
            best, bestLevel = rewarded[i], level
        end
    end
    local link = best and CardItemLink(best)
    if not link then return false end
    if type(bestLevel) == "number" then
        KE:Print(string_format("Great Vault: best reward %s, item level %d", link, math_floor(bestLevel + 0.5)))
    else
        KE:Print(string_format("Great Vault: best reward %s", link))
    end
    return true
end

function GVA:AfterReveal(clicked)
    local wf = VaultFrame()
    if not wf or type(wf.Activities) ~= "table" then return end
    local db = self.db
    wipe(rewarded)
    wipe(levels)
    wipe(waiting)
    local clickedIndex
    for _, card in ipairs(wf.Activities) do
        if IsCard(card) and card.hasRewards then
            rewarded[#rewarded + 1] = card
            if card == clicked then clickedIndex = #rewarded end
            local cover = covers[card]
            if cover and cover:IsShown() and not cover.reveal:IsPlaying() then
                waiting[#waiting + 1] = cover
            end
        end
    end

    local flavor = db.CoverFlavor ~= false
    local recap = db.CoverChatRecap == true and #waiting == 0 and not self._coverRecapDone
    if not (flavor or recap) then return end
    for i = 1, #rewarded do
        levels[i] = CardItemLevel(rewarded[i]) or false
    end

    if flavor then
        if clickedIndex and GVA.IsJackpot(levels, clickedIndex) then self:ShowJackpot(clicked) end
        local last = GVA.TeaseTarget(waiting)
        if last then
            local tease = last.tease
            KE:ApplyFontToText(tease, self.db.FontFace, 14, "OUTLINE")
            tease:SetTextColor(1, 1, 1)
            tease:SetText("Last one...")
            tease:Show()
        end
    end
    if recap and self:PrintCoverRecap() then
        self._coverRecapDone = true
    end
end

function GVA:RevealCover(cover)
    if cover.reveal:IsPlaying() then return end
    local db = self.db
    -- The claim can end before Blizzard's next Refresh hides the cover; a
    -- click then only hides it.
    if not GVA.CoverActive(self._listening, db.Enabled, db.CoverEnabled ~= false, CanClaimApi()) then
        cover:Hide()
        return
    end
    local card = cover:GetParent()
    cover:EnableMouse(false)
    cover.tease:Hide()

    local key = GVA.CardKey(card.info)
    seen[key or card] = true
    if key then WriteStore(key) end

    self:PlayCoverSound(db.CoverSound)

    -- Replays the card's own sparkle; a plain animation frame Blizzard
    -- toggles the same way, read by nothing on the claim path.
    local burst = card.RewardGenerated
    if card.hasRewards and burst then
        burst:Hide()
        burst:Show()
    end

    local r, g, b = QualityColor(card)
    if r then cover.shine:SetVertexColor(r, g, b) end
    cover.pulse:Stop()
    cover.reveal:Play()

    self:AfterReveal(card)
end

---------------------------------------------------------------------------------
-- Bad Loot Line
---------------------------------------------------------------------------------
-- Parented to the strip itself, never to its layout frame, whose children
-- Blizzard hides and lays out on every Refresh.
function GVA:UpdateBadLootLine(wf, active)
    local strip = wf.ConcessionsFrame
    local plates = strip and strip.Rewards
    local notice = wf.PreviousRewardNotification
    local show = plates ~= nil and GVA.BadLootLineShown(active, self.db.CoverBadLoot ~= false,
        strip:IsShown(), notice ~= nil and notice:IsShown())
    if not show then
        if badLootLine then badLootLine:Hide() end
        return
    end
    if not badLootLine then
        badLootLine = CreateFrame("Frame", nil, strip)
        badLootLine.keOwned = true
        badLootLine:SetSize(600, 18)
        badLootLine:SetPoint("TOP", plates, "BOTTOM", 0, -4)
        local text = badLootLine:CreateFontString(nil, "OVERLAY")
        text:SetPoint("CENTER")
        badLootLine.text = text
    end
    local text = badLootLine.text
    KE:ApplyFontToText(text, self.db.FontFace, 14, "OUTLINE")
    text:SetTextColor(1, 0.3, 0.3)
    text:SetText(SKULL .. " " .. BAD_LOOT_TEXT .. " " .. SKULL)
    badLootLine:Show()
end

---------------------------------------------------------------------------------
-- Refresh
---------------------------------------------------------------------------------
function GVA:UpdateCovers()
    local wf = VaultFrame()
    if not wf or type(wf.Activities) ~= "table" then return end
    local db = self.db
    local active = wf:IsShown()
        and GVA.CoverActive(self._listening, db.Enabled, db.CoverEnabled ~= false, CanClaimApi())
        or false

    local store
    if active then
        store = ReadStore()
        if store then GVA.PruneRevealed(store, CollectLiveKeys(wf)) end
    end

    local scene = wf.ModelScene
    local sceneLevel = scene and scene:GetFrameLevel() or 0
    local wanted = 0
    for _, card in ipairs(wf.Activities) do
        if IsCard(card) then
            local key = GVA.CardKey(card.info)
            local cover = covers[card]
            if GVA.CardWantsCover(active, card.hasRewards, key, store, seen[key or card]) then
                cover = cover or self:CreateCover(card)
                -- Re-covered mid-fade: hiding stops the reveal, and OnShow
                -- then restores the cover.
                if cover.reveal:IsPlaying() then cover:Hide() end
                PlaceCover(cover, card)
                cover:SetFrameLevel(CoverLevel(card, sceneLevel))
                cover:Show()
                wanted = wanted + 1
            elseif cover and cover:IsShown() and (not active or not cover.reveal:IsPlaying()) then
                cover:Hide()
            end
        end
    end

    -- Only a click shows a tease, so any count but one means it is stale.
    if not active or db.CoverFlavor == false then
        HideFlavor()
    elseif wanted ~= 1 then
        HideTeases()
    end

    self:UpdateBadLootLine(wf, active)
end

---------------------------------------------------------------------------------
-- Gate and hooks
---------------------------------------------------------------------------------
function GVA:CoverWatched()
    local db = self.db
    return (self._listening and db and db.Enabled and db.CoverEnabled ~= false) and true or false
end

-- hooksecurefunc cannot be removed, so each hook returns at once while the
-- cover is not watched.
function GVA:InstallCoverHooks()
    if self._coverHooked then return end
    local wf = VaultFrame()
    if not wf then return end
    self._coverHooked = true
    hooksecurefunc(wf, "Refresh", function()
        if not GVA:CoverWatched() then return end
        GVA:UpdateCovers()
    end)
    wf:HookScript("OnHide", function() GVA:OnVaultHidden() end)
end

function GVA:OnCoverAddonLoaded(_, name)
    if name ~= VAULT_ADDON then return end
    self._coverWaiting = false
    self:UnregisterEvent("ADDON_LOADED")
    if self:CoverWatched() then self:InstallCoverHooks() end
end

function GVA:UpdateCoverWatch()
    if self:CoverWatched() then
        if self._coverHooked then return end
        if VaultFrame() then
            self:InstallCoverHooks()
        elseif not self._coverWaiting then
            self._coverWaiting = true
            self:RegisterEvent("ADDON_LOADED", "OnCoverAddonLoaded")
        end
        return
    end
    if self._coverWaiting then
        self._coverWaiting = false
        self:UnregisterEvent("ADDON_LOADED")
    end
    self:HideCovers()
end

-- The recap flag is left for OnVaultHidden: the recap prints once per opening.
function GVA:HideCovers()
    for _, cover in pairs(covers) do cover:Hide() end
    for _, flair in pairs(flairs) do flair:Hide() end
    if badLootLine then badLootLine:Hide() end
    wipe(seen)
end

function GVA:OnVaultHidden()
    if next(seen) == nil and not self._coverRecapDone then return end
    wipe(seen)
    self._coverRecapDone = false
end

function GVA:ApplyCover()
    self:UpdateCoverWatch()
    RefreshOpenVault()
end

-- The player's own click, so it clears the store rested or not.
function GVA:ResetRevealed()
    local store = KE:GetCharStore()
    if store then store[STORE_KEY] = nil end
    wipe(seen)
    HideFlavor()
    RefreshOpenVault()
end
