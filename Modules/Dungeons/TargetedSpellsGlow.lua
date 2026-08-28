-- ╔══════════════════════════════════════════════════════════╗
-- ║  TargetedSpellsGlow.lua                                  ║
-- ║  Module: Targeted Spells                                 ║
-- ║  Purpose: Size-parameterized pixel glow for the entry    ║
-- ║           icons. LibCustomGlow variant that takes        ║
-- ║           width/height as plain arguments: rect queries  ║
-- ║           (GetSize) on the secret-alpha-bound entry      ║
-- ║           subtree return SECRET numbers in live combat,  ║
-- ║           so stock LCG's internal GetSize arithmetic     ║
-- ║           throws (BugSack-confirmed).         ║
-- ╚══════════════════════════════════════════════════════════╝

-- Derived from LibCustomGlow (pixel glow only), reworked to take an explicit
-- size. MIT License:
--
-- Copyright (c) 2022 Benjamin Staneck
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in all
-- copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
-- SOFTWARE.

---@class KE
local KE = select(2, ...)

local CreateFramePool, CreateTexturePool = CreateFramePool, CreateTexturePool
local UIParent = UIParent
local tinsert, tremove = table.insert, table.remove
local floor, min = math.floor, math.min
local pairs, type = pairs, type

local textureList = {
    empty = [[Interface\AdventureMap\BrokenIsles\AM_29]],
    white = [[Interface\BUTTONS\WHITE8X8]],
}
local GlowParent = UIParent

local GlowMaskPool = {
    createFunc = function(self)
        return self.parent:CreateMaskTexture()
    end,
    resetFunc = function(_, mask)
        mask:Hide()
        mask:ClearAllPoints()
    end,
    AddObject = function(self, object)
        self.activeObjects[object] = true
        self.activeObjectCount = self.activeObjectCount + 1
    end,
    ReclaimObject = function(self, object)
        tinsert(self.inactiveObjects, object)
        self.activeObjects[object] = nil
        self.activeObjectCount = self.activeObjectCount - 1
    end,
    Release = function(self, object)
        local active = self.activeObjects[object] ~= nil
        if active then
            self:resetFunc(object)
            self:ReclaimObject(object)
        end
        return active
    end,
    Acquire = function(self)
        local object = tremove(self.inactiveObjects)
        local isNew = object == nil
        if isNew then
            object = self:createFunc()
            self:resetFunc(object, isNew)
        end
        self:AddObject(object)
        return object, isNew
    end,
    Init = function(self, parent)
        self.activeObjects = {}
        self.inactiveObjects = {}
        self.activeObjectCount = 0
        self.parent = parent
    end,
}

GlowMaskPool:Init(GlowParent)

local GlowTexPool = CreateTexturePool(
    GlowParent,
    "ARTWORK",
    7,
    nil,
    function(_, tex)
        local maskNum = tex:GetNumMaskTextures()
        for idx = maskNum, 1, -1 do
            tex:RemoveMaskTexture(tex:GetMaskTexture(idx))
        end
        tex:Hide()
        tex:ClearAllPoints()
    end
)

local GlowFramePool = CreateFramePool(
    "Frame",
    GlowParent,
    nil,
    function(_, frame)
        frame:SetScript("OnUpdate", nil)

        local parent = frame:GetParent()
        if parent and frame.name and parent[frame.name] then
            parent[frame.name] = nil
        end

        if frame.textures then
            for _, texture in pairs(frame.textures) do
                GlowTexPool:Release(texture)
            end
        end

        if frame.bg then
            GlowTexPool:Release(frame.bg)
            frame.bg = nil
        end

        if frame.masks then
            for _, mask in pairs(frame.masks) do
                GlowMaskPool:Release(mask)
            end
            frame.masks = nil
        end

        frame.textures = {}
        frame.info = {}
        frame.name = nil
        frame.timer = nil
        frame.throttle = nil
        -- KE delta: the consumer binds glow visibility via
        -- SetAlphaFromBoolean (possibly 0) — pooled frames must come back
        -- neutral or the next user inherits an invisible glow.
        frame:SetAlpha(1)
        frame:Hide()
        frame:ClearAllPoints()
    end
)

local function AddFrameAndTex(frame, color, name, count, texture, texCoord, desaturated)
    if frame[name] == nil then
        frame[name] = GlowFramePool:Acquire()
        frame[name]:SetParent(frame)
        frame[name].name = name
    end

    local GlowFrame = frame[name]
    GlowFrame:SetFrameLevel(frame:GetFrameLevel() + 8)
    GlowFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 0.05, 0.05)
    GlowFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0.05)
    GlowFrame:Show()

    if not GlowFrame.textures then
        GlowFrame.textures = {}
    end

    for idx = 1, count do
        if not GlowFrame.textures[idx] then
            GlowFrame.textures[idx] = GlowTexPool:Acquire()
            GlowFrame.textures[idx]:SetTexture(texture)
            GlowFrame.textures[idx]:SetTexCoord(texCoord[1], texCoord[2], texCoord[3], texCoord[4])
            GlowFrame.textures[idx]:SetDesaturated(desaturated)
            GlowFrame.textures[idx]:SetParent(GlowFrame)
            GlowFrame.textures[idx]:SetDrawLayer("ARTWORK", 7)
        end

        if type(color) == "table" and color.GetRGBA then
            GlowFrame.textures[idx]:SetVertexColor(color:GetRGBA())
        else
            GlowFrame.textures[idx]:SetVertexColor(color[1], color[2], color[3], color[4])
        end

        GlowFrame.textures[idx]:Show()
    end

    while #GlowFrame.textures > count do
        GlowTexPool:Release(GlowFrame.textures[#GlowFrame.textures])
        tremove(GlowFrame.textures)
    end

    return GlowFrame
end

KE.TSGlow = {}

do
    local color = { 0.95, 0.95, 0.32, 1 }
    local count = 8
    local th = 1

    local function PCalc1(progress, size, thickness, phases)
        local coord
        if progress > phases[3] or progress < phases[0] then
            coord = 0
        elseif progress > phases[2] then
            coord = size - thickness - (progress - phases[2]) / (phases[3] - phases[2]) * (size - thickness)
        elseif progress > phases[1] then
            coord = size - thickness
        else
            coord = (progress - phases[0]) / (phases[1] - phases[0]) * (size - thickness)
        end
        return floor(coord + 0.5)
    end

    local function PCalc2(progress, size, thickness, phases)
        local coord
        if progress > phases[3] then
            coord = size - thickness - (progress - phases[3]) / (phases[0] + 1 - phases[3]) * (size - thickness)
        elseif progress > phases[2] then
            coord = size - thickness
        elseif progress > phases[1] then
            coord = (progress - phases[1]) / (phases[2] - phases[1]) * (size - thickness)
        elseif progress > phases[0] then
            coord = 0
        else
            coord = size - thickness - (progress + 1 - phases[3]) / (phases[0] + 1 - phases[3]) * (size - thickness)
        end
        return floor(coord + 0.5)
    end

    local GLOW_UPDATE_INTERVAL = 1 / 60

    local function PUpdate(self, elapsed)
        self.throttle = (self.throttle or 0) + elapsed
        if self.throttle < GLOW_UPDATE_INTERVAL then return end
        local step = self.throttle
        self.throttle = 0
        self.timer = self.timer + step / self.info.period

        if self.timer > 1 or self.timer < -1 then
            self.timer = self.timer % 1
        end

        local progress = self.timer
        local width = self.info.width
        local height = self.info.height

        if self.info.needsUpdate then
            self.info.needsUpdate = nil
            local perimeter = 2 * (width + height)

            if perimeter <= 0 then
                return
            end

            self.info.pTLx = {
                [0] = (height + self.info.length / 2) / perimeter,
                [1] = (height + width + self.info.length / 2) / perimeter,
                [2] = (2 * height + width - self.info.length / 2) / perimeter,
                [3] = 1 - self.info.length / 2 / perimeter,
            }
            self.info.pTLy = {
                [0] = (height - self.info.length / 2) / perimeter,
                [1] = (height + width + self.info.length / 2) / perimeter,
                [2] = (height * 2 + width + self.info.length / 2) / perimeter,
                [3] = 1 - self.info.length / 2 / perimeter,
            }
            self.info.pBRx = {
                [0] = self.info.length / 2 / perimeter,
                [1] = (height - self.info.length / 2) / perimeter,
                [2] = (height + width - self.info.length / 2) / perimeter,
                [3] = (height * 2 + width + self.info.length / 2) / perimeter,
            }
            self.info.pBRy = {
                [0] = self.info.length / 2 / perimeter,
                [1] = (height + self.info.length / 2) / perimeter,
                [2] = (height + width - self.info.length / 2) / perimeter,
                [3] = (height * 2 + width - self.info.length / 2) / perimeter,
            }
        end

        if self:IsShown() then
            if not (self.masks[1]:IsShown()) then
                self.masks[1]:Show()
                self.masks[1]:SetPoint("TOPLEFT", self, "TOPLEFT", self.info.th, -self.info.th)
                self.masks[1]:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", -self.info.th, self.info.th)
            end

            if self.masks[2] and not (self.masks[2]:IsShown()) then
                self.masks[2]:Show()
                self.masks[2]:SetPoint("TOPLEFT", self, "TOPLEFT", self.info.th + 1, -self.info.th - 1)
                self.masks[2]:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", -self.info.th - 1, self.info.th + 1)
            end

            if self.bg and not (self.bg:IsShown()) then
                self.bg:Show()
            end

            for index, line in pairs(self.textures) do
                line:SetPoint(
                    "TOPLEFT",
                    self,
                    "TOPLEFT",
                    PCalc1((progress + self.info.step * (index - 1)) % 1, width, self.info.th, self.info.pTLx),
                    -PCalc2((progress + self.info.step * (index - 1)) % 1, height, self.info.th, self.info.pTLy)
                )
                line:SetPoint(
                    "BOTTOMRIGHT",
                    self,
                    "TOPLEFT",
                    self.info.th
                        + PCalc2((progress + self.info.step * (index - 1)) % 1, width, self.info.th, self.info.pBRx),
                    -height
                        + PCalc1((progress + self.info.step * (index - 1)) % 1, height, self.info.th, self.info.pBRy)
                )
            end
        end
    end

    -- width/height MUST be plain numbers (pass config values, never GetSize
    -- results — those are secret inside the entry subtree).
    function KE.TSGlow.PixelGlow_Start(frame, width, height)
        local length = floor((width + height) * (2 / count - 0.1))
        length = min(length, min(width, height))

        local GlowFrame = AddFrameAndTex(frame, color, "_PixelGlow", count, textureList.white, { 0, 1, 0, 1 })

        if not GlowFrame.masks then
            GlowFrame.masks = {}
        end

        if not GlowFrame.masks[1] then
            GlowFrame.masks[1] = GlowMaskPool:Acquire()
            GlowFrame.masks[1]:SetTexture(textureList.empty, "CLAMPTOWHITE", "CLAMPTOWHITE")
            GlowFrame.masks[1]:Show()
        end

        GlowFrame.masks[1]:SetPoint("TOPLEFT", GlowFrame, "TOPLEFT", th, -th)
        GlowFrame.masks[1]:SetPoint("BOTTOMRIGHT", GlowFrame, "BOTTOMRIGHT", -th, th)

        if not GlowFrame.masks[2] then
            GlowFrame.masks[2] = GlowMaskPool:Acquire()
            GlowFrame.masks[2]:SetTexture(textureList.empty, "CLAMPTOWHITE", "CLAMPTOWHITE")
        end

        GlowFrame.masks[2]:SetPoint("TOPLEFT", GlowFrame, "TOPLEFT", th + 1, -th - 1)
        GlowFrame.masks[2]:SetPoint("BOTTOMRIGHT", GlowFrame, "BOTTOMRIGHT", -th - 1, th + 1)

        if not GlowFrame.bg then
            GlowFrame.bg = GlowTexPool:Acquire()
            GlowFrame.bg:SetColorTexture(0.1, 0.1, 0.1, 0.8)
            GlowFrame.bg:SetParent(GlowFrame)
            GlowFrame.bg:SetAllPoints(GlowFrame)
            GlowFrame.bg:SetDrawLayer("ARTWORK", 6)
            GlowFrame.bg:AddMaskTexture(GlowFrame.masks[2])
        end

        for _, tex in pairs(GlowFrame.textures) do
            if tex:GetNumMaskTextures() < 1 then
                tex:AddMaskTexture(GlowFrame.masks[1])
            end
        end

        GlowFrame.timer = GlowFrame.timer or 0
        GlowFrame.throttle = 0
        GlowFrame.info = GlowFrame.info or {}
        GlowFrame.info.step = 1 / count
        GlowFrame.info.period = 4
        GlowFrame.info.th = th
        GlowFrame.info.length = length
        if GlowFrame.info.width ~= width or GlowFrame.info.height ~= height then
            GlowFrame.info.width = width
            GlowFrame.info.height = height
            GlowFrame.info.needsUpdate = true
        end

        PUpdate(GlowFrame, GLOW_UPDATE_INTERVAL)

        GlowFrame:SetScript("OnUpdate", PUpdate)
    end
end

function KE.TSGlow.PixelGlow_Stop(frame)
    if frame._PixelGlow then
        GlowFramePool:Release(frame._PixelGlow)
    end
end
