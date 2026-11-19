local _, ns = ...
local L = ns.L
local CreateFrame = ns.CreateDetachedFrame or CreateFrame

local AddonSettings = {
    minimapCheckButtons = setmetatable({}, { __mode = "k" }),
}
ns.Settings = AddonSettings

function AddonSettings:IsMinimapButtonShown()
    return not ForeverpediaDB or ForeverpediaDB.showMinimapButton ~= false
end

function AddonSettings:RefreshControls()
    local checked = self:IsMinimapButtonShown()
    for checkButton in pairs(self.minimapCheckButtons) do
        checkButton:SetChecked(checked)
    end
end

function AddonSettings:SetMinimapButtonShown(shown)
    ForeverpediaDB = ForeverpediaDB or {}
    ForeverpediaDB.showMinimapButton = shown == true
    self:RefreshControls()
    if ns.MinimapButton and ns.MinimapButton.RefreshVisibility then
        ns.MinimapButton:RefreshVisibility()
    end
end

function AddonSettings:CreateMinimapCheckButton(parent)
    local checkButton = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    checkButton:SetSize(26, 26)
    if checkButton.SetHitRectInsets then
        checkButton:SetHitRectInsets(0, -284, 0, 0)
    end

    local label = checkButton:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("LEFT", checkButton, "LEFT", 28, 0)
    label:SetJustifyH("LEFT")
    label:SetText(L("show_minimap_button"))
    checkButton.label = label

    checkButton:SetScript("OnClick", function(self)
        AddonSettings:SetMinimapButtonShown(self:GetChecked() == true)
    end)
    checkButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L("show_minimap_button"))
        GameTooltip:AddLine(L("show_minimap_button_tip"), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    checkButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

    self.minimapCheckButtons[checkButton] = true
    checkButton:SetChecked(self:IsMinimapButtonShown())
    return checkButton
end

function AddonSettings:CreateAddonPanel()
    if self.panel then return self.panel end

    local panel = CreateFrame("Frame", "ForeverpediaSettingsPanel", UIParent)
    panel.name = "Foreverpedia"

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Foreverpedia")

    local description = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    description:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    description:SetPoint("RIGHT", panel, "RIGHT", -32, 0)
    description:SetJustifyH("LEFT")
    description:SetText(L("addon_settings_description"))

    local minimapCheckButton = self:CreateMinimapCheckButton(panel)
    minimapCheckButton:SetPoint("TOPLEFT", description, "BOTTOMLEFT", -4, -18)

    panel:SetScript("OnShow", function() AddonSettings:RefreshControls() end)
    panel.minimapCheckButton = minimapCheckButton
    self.panel = panel

    local settingsAPI = rawget(_G, "Settings")
    local registered = false
    if settingsAPI and type(settingsAPI.RegisterCanvasLayoutCategory) == "function"
            and type(settingsAPI.RegisterAddOnCategory) == "function" then
        local ok, category = pcall(
            settingsAPI.RegisterCanvasLayoutCategory, panel, "Foreverpedia"
        )
        if ok and category then
            registered = pcall(settingsAPI.RegisterAddOnCategory, category)
            if registered then self.category = category end
        end
    end
    if not registered and type(InterfaceOptions_AddCategory) == "function" then
        InterfaceOptions_AddCategory(panel)
    end
    return panel
end

function AddonSettings:Initialize()
    self:CreateAddonPanel()
    self:RefreshControls()
end
