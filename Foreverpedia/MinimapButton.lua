local _, ns = ...
local L = ns.L
local CreateFrame = ns.CreateDetachedFrame or CreateFrame

local MinimapButton = {}
ns.MinimapButton = MinimapButton

local DEFAULT_ANGLE = 220
local DISTANCE_FROM_EDGE = 4

local function cursorAngle()
    if not (Minimap and Minimap.GetCenter and GetCursorPosition) then
        return DEFAULT_ANGLE
    end
    local centerX, centerY = Minimap:GetCenter()
    local scale = Minimap.GetEffectiveScale and Minimap:GetEffectiveScale() or 1
    local cursorX, cursorY = GetCursorPosition()
    cursorX, cursorY = cursorX / scale, cursorY / scale
    local deltaX, deltaY = cursorX - centerX, cursorY - centerY
    local radians
    if math.atan2 then
        radians = math.atan2(deltaY, deltaX)
    elseif deltaX == 0 then
        radians = deltaY >= 0 and math.pi / 2 or -math.pi / 2
    else
        radians = math.atan(deltaY / deltaX)
        if deltaX < 0 then radians = radians + math.pi end
    end
    return math.deg(radians)
end

function MinimapButton:UpdatePosition(angle)
    local button = self.button
    if not (button and Minimap) then return end
    angle = tonumber(angle) or DEFAULT_ANGLE
    local width = Minimap.GetWidth and Minimap:GetWidth() or 140
    local height = Minimap.GetHeight and Minimap:GetHeight() or 140
    local radiusX = width / 2 + DISTANCE_FROM_EDGE
    local radiusY = height / 2 + DISTANCE_FROM_EDGE
    local radians = math.rad(angle)
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER",
        math.cos(radians) * radiusX, math.sin(radians) * radiusY)
end

function MinimapButton:RefreshVisibility()
    if not self.button then return end
    local shown = not ns.Settings or ns.Settings:IsMinimapButtonShown()
    self.button:SetShown(shown)
end

function MinimapButton:Initialize()
    if self.button or not Minimap then return end

    local button = CreateFrame("Button", "ForeverpediaMinimapButton", Minimap)
    button:SetSize(32, 32)
    button:SetFrameStrata("MEDIUM")
    if Minimap.GetFrameLevel then button:SetFrameLevel(Minimap:GetFrameLevel() + 8) end
    button:RegisterForClicks("LeftButtonUp")
    button:RegisterForDrag("LeftButton")

    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetSize(24, 24)
    background:SetPoint("CENTER")
    background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(22, 22)
    icon:SetPoint("CENTER")
    icon:SetTexture("Interface\\AddOns\\Foreverpedia\\Media\\ForeverpediaIcon.png")

    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetSize(24, 24)
    highlight:SetPoint("CENTER")
    highlight:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    highlight:SetBlendMode("ADD")

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(54, 54)
    border:SetPoint("TOPLEFT", 0, 0)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    button:SetScript("OnClick", function()
        if ns.UI and ns.UI.frame and ns.UI.frame:IsShown() then
            ns.UI.frame:Hide()
        elseif ns.UI and ns.UI.OpenSearch then
            ns.UI:OpenSearch()
        end
    end)
    button:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local angle = cursorAngle()
            ForeverpediaDB = ForeverpediaDB or {}
            ForeverpediaDB.minimapButtonAngle = angle
            MinimapButton:UpdatePosition(angle)
        end)
    end)
    button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Foreverpedia")
        GameTooltip:AddLine(L("minimap_button_click"), 1, 1, 1)
        GameTooltip:AddLine(L("minimap_button_drag"), 0.72, 0.72, 0.72)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)

    self.button = button
    self:UpdatePosition(ForeverpediaDB and ForeverpediaDB.minimapButtonAngle)
    self:RefreshVisibility()
end
