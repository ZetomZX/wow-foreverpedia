local _, ns = ...
local L = ns.L
local CreateFrame = ns.CreateDetachedFrame or CreateFrame

local UI = {
    activeTab = "uses",
    expandedGroups = {},
    detailExpanded = {},
    history = {},
    searchResults = {},
    searchSelection = 1,
    failedItemLoads = {},
}
ns.UI = UI

local itemLoadFrame = CreateFrame("Frame")
itemLoadFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
itemLoadFrame:SetScript("OnEvent", function(_, _, itemID, success)
    if success then
        UI.failedItemLoads[itemID] = nil
    elseif itemID then
        UI.failedItemLoads[itemID] = true
    end

    if UI.RefreshItemTooltip then UI:RefreshItemTooltip(itemID) end

    if not (UI.frame and UI.frame:IsShown()) then return end
    if success and ns.CraftTree then ns.CraftTree:RefreshItem(itemID) end
    if UI.currentItemID == itemID then
        UI:Render()
    elseif success and UI.detailSelection and UI.detailSelection.kind == "recipe" then
        UI:RefreshDetails(true)
    end
end)

local COLORS = ns.Theme.colors

local KIND_LABELS = {
    drop = "drop", object = "object", herb = "herb",
    fishing = "fishing", craft = "profession", container = "container",
    gathering = "gathering", profession = "profession", quest = "quest",
    quest_reward = "quest_reward", starts_quest = "starts_quest",
    teaches_spell = "teaches", vendor = "vendor",
    reputation = "reputation", exchange = "exchange",
    disenchant = "disenchant", pickpocket = "pickpocket",
    spell_loot = "spell_loot", mail = "mail",
    class_ability = "class_ability",
}

local function kindLabel(kind)
    return KIND_LABELS[kind] and L(KIND_LABELS[kind]) or kind
end

local USE_GROUPS = {
    { key = "profession", titleKey = "professions", kinds = { profession = true } },
    { key = "class_ability", titleKey = "class_abilities", kinds = { class_ability = true } },
    { key = "quest", titleKey = "quests", kinds = { quest = true, starts_quest = true } },
    { key = "learning", titleKey = "learning", kinds = { teaches_spell = true } },
}

local SOURCE_GROUPS = {
    { key = "drop", titleKey = "creature_drop", kinds = { drop = true } },
    { key = "pickpocket", titleKey = "pickpocketing", kinds = { pickpocket = true } },
    { key = "fishing", titleKey = "fishing", kinds = { fishing = true } },
    { key = "craft", titleKey = "craft", kinds = { craft = true } },
    { key = "disenchant", titleKey = "disenchanting", kinds = { disenchant = true } },
    { key = "herb", titleKey = "herbs", kinds = { herb = true } },
    { key = "object", titleKey = "objects", kinds = { object = true } },
    { key = "quest", titleKey = "quests", kinds = { quest_reward = true } },
    { key = "vendor", titleKey = "vendors", kinds = { vendor = true } },
    { key = "container", titleKey = "containers", kinds = { container = true } },
    { key = "gathering", titleKey = "professional_gathering", kinds = { gathering = true } },
    { key = "spell_loot", titleKey = "spell_sources", kinds = { spell_loot = true } },
    { key = "mail", titleKey = "mail_sources", kinds = { mail = true } },
}

local setBackdrop = ns.Theme.SetBackdrop

local function getQualityColor(quality)
    if quality and ColorManager and ColorManager.GetColorDataForItemQuality then
        local colorData = ColorManager.GetColorDataForItemQuality(quality)
        if colorData and colorData.color then
            return colorData.color:GetRGB()
        end
    end
    return unpack(COLORS.gold)
end

local function getItemInfo(itemInfo)
    if not C_Item or not C_Item.GetItemInfo then
        return nil
    end

    local name, link, quality, itemLevel, _, itemType, itemSubType, _, _, icon =
        C_Item.GetItemInfo(itemInfo)

    if not name then
        return nil
    end

    return {
        name = name,
        link = link,
        quality = quality,
        itemLevel = itemLevel,
        minimumLevel = minimumLevel,
        itemType = itemType,
        itemSubType = itemSubType,
        icon = icon,
    }
end

local function getItemIcon(itemID, itemInfo)
    if itemInfo and itemInfo.icon then
        return itemInfo.icon
    end
    if C_Item and C_Item.GetItemIconByID then
        return C_Item.GetItemIconByID(itemID)
    end
    return nil
end

local itemDisplayName = ns.GetItemName

function UI:ShowItemTooltip(owner, itemID, addLines)
    self.itemTooltipOwner = owner
    self.itemTooltipItemID = itemID
    self.itemTooltipAddLines = addLines
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    if self.failedItemLoads[itemID] then
        GameTooltip:ClearLines()
        local icon = getItemIcon(itemID)
        local iconMarkup = icon and string.format("|T%d:18:18:0:0|t ", icon) or ""
        GameTooltip:AddLine(iconMarkup .. itemDisplayName(itemID),
            COLORS.gold[1], COLORS.gold[2], COLORS.gold[3])
        GameTooltip:AddLine(L("item_not_found"), 1, 0.28, 0.28, true)
        GameTooltip:AddLine(L("item_id", itemID),
            COLORS.muted[1], COLORS.muted[2], COLORS.muted[3])
    else
        GameTooltip:SetHyperlink("item:" .. tostring(itemID))
    end
    if addLines then addLines() end
    GameTooltip:Show()
end

function UI:RefreshItemTooltip(itemID)
    if self.itemTooltipItemID ~= itemID or not self.itemTooltipOwner
            or not GameTooltip:IsShown() then
        return
    end
    self:ShowItemTooltip(self.itemTooltipOwner, itemID, self.itemTooltipAddLines)
end

function UI:HideItemTooltip()
    self.itemTooltipOwner = nil
    self.itemTooltipItemID = nil
    self.itemTooltipAddLines = nil
    GameTooltip:Hide()
end

local function restorePosition(frame)
    local position = ForeverpediaDB and ForeverpediaDB.position
    if position and position.point and position.x and position.y then
        frame:SetPoint(position.point, UIParent, position.relativePoint or position.point,
            position.x, position.y)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 10)
    end
end

local function savePosition(frame)
    if not ForeverpediaDB then
        return
    end

    local point, _, relativePoint, x, y = frame:GetPoint(1)
    ForeverpediaDB.position = {
        point = point,
        relativePoint = relativePoint,
        x = x,
        y = y,
    }
end

local function saveSize(frame)
    if ForeverpediaDB then
        ForeverpediaDB.size = { width = frame:GetWidth(), height = frame:GetHeight() }
    end
end

function UI:SetAvailableUpdate(version)
    self.availableUpdateVersion = version
    if self.frame then self:UpdateTopNotices() end
end

function UI:UpdateTopNotices()
    local frame = self.frame
    if not frame then return end

    local noticeIndex = 0
    local function place(notice, shown)
        notice:ClearAllPoints()
        notice:SetPoint("TOPLEFT", 20, -40 - noticeIndex * 18)
        notice:SetPoint("TOPRIGHT", -20, -40 - noticeIndex * 18)
        notice:SetShown(shown)
        if shown then noticeIndex = noticeIndex + 1 end
    end

    local updateVersion = self.availableUpdateVersion
        or (ns.VersionExchange and ns.VersionExchange.GetNewestSeenVersion
            and ns.VersionExchange:GetNewestSeenVersion())
    if updateVersion then
        frame.updateHint:SetText(L("update_available_banner", updateVersion))
    end
    place(frame.updateHint, updateVersion ~= nil)
    place(frame.questieHint, not frame.questieAvailable)

    frame.header:ClearAllPoints()
    local headerOffset = -54 - noticeIndex * 18
    frame.header:SetPoint("TOPLEFT", 20, headerOffset)
    frame.header:SetPoint("TOPRIGHT", -20, headerOffset)
end

function UI:CreateFrame()
    if self.frame then
        return self.frame
    end

    local frame = CreateFrame("Frame", "ForeverpediaFrame", UIParent, "BackdropTemplate")
    local savedSize = ForeverpediaDB and ForeverpediaDB.size
    frame:SetSize(savedSize and savedSize.width or 1180, savedSize and savedSize.height or 620)
    if frame.SetResizable then frame:SetResizable(true) end
    if frame.SetResizeBounds then
        frame:SetResizeBounds(940, 500, 1600, 1000)
    elseif frame.SetMinResize and frame.SetMaxResize then
        frame:SetMinResize(940, 500)
        frame:SetMaxResize(1600, 1000)
    end
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        savePosition(self)
    end)
    setBackdrop(frame, COLORS.background)
    restorePosition(frame)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 20, -16)
    title:SetText("FOREVERPEDIA")
    title:SetTextColor(unpack(COLORS.gold))

    local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("LEFT", title, "RIGHT", 14, -1)
    hint:SetText(L("addon_subtitle"))
    hint:SetTextColor(unpack(COLORS.muted))

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)

    local back = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    back:SetSize(82, 24)
    back:SetPoint("LEFT", hint, "RIGHT", 18, 0)
    back:SetText(L("back"))
    back:SetScript("OnClick", function() UI:GoBack() end)
    back:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(L("back_tip"))
        GameTooltip:Show()
    end)
    back:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local options = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    options:SetSize(76, 24)
    options:SetPoint("LEFT", back, "RIGHT", 8, 0)
    options:SetText(L("options"))

    local optionsPanel = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    optionsPanel:SetSize(360, 315)
    optionsPanel:SetPoint("TOPLEFT", options, "BOTTOMLEFT", 0, -5)
    optionsPanel:SetFrameStrata("TOOLTIP")
    optionsPanel:SetFrameLevel(frame:GetFrameLevel() + 60)
    setBackdrop(optionsPanel, COLORS.panel)
    optionsPanel:Hide()

    local languageTitle = optionsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    languageTitle:SetPoint("TOPLEFT", 14, -14)
    languageTitle:SetText(L("language"))
    languageTitle:SetTextColor(unpack(COLORS.gold))

    local languageOptions = {
        { value = "ruRU", label = L("russian") },
        { value = "enUS", label = L("english") },
    }
    local languageDropDown = CreateFrame("Frame", "ForeverpediaLanguageDropDown",
        optionsPanel, "UIDropDownMenuTemplate")
    languageDropDown:SetPoint("TOPLEFT", -2, -33)
    UIDropDownMenu_SetWidth(languageDropDown, 170)

    local apply = CreateFrame("Button", nil, optionsPanel, "UIPanelButtonTemplate")
    apply:SetSize(84, 24)
    -- UIPanelButtonTemplate draws its visible border lower than its frame bounds.
    -- Compensate for that inset so the button is visually centered on the dropdown.
    apply:SetPoint("TOPLEFT", 218, -33)
    apply:SetText(L("apply"))

    local languageMenu = CreateFrame("Frame", nil, optionsPanel, "BackdropTemplate")
    languageMenu:SetSize(190, 52)
    languageMenu:SetPoint("TOPLEFT", optionsPanel, "TOPLEFT", 14, -68)
    languageMenu:SetFrameLevel(optionsPanel:GetFrameLevel() + 10)
    setBackdrop(languageMenu, COLORS.panel)
    languageMenu.buttons = {}
    languageMenu:Hide()

    local function setPendingLanguage(language)
        optionsPanel.pendingLanguage = language
        for _, option in ipairs(languageOptions) do
            if option.value == language then
                UIDropDownMenu_SetText(languageDropDown, option.label)
                break
            end
        end
        if language == ns.Locale:GetLanguage() then apply:Disable() else apply:Enable() end
    end

    for index, option in ipairs(languageOptions) do
        local value = option.value
        local button = CreateFrame("Button", nil, languageMenu)
        button:SetHeight(21)
        button:SetPoint("TOPLEFT", 4, -4 - (index - 1) * 21)
        button:SetPoint("TOPRIGHT", -4, -4 - (index - 1) * 21)
        local highlight = button:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetColorTexture(1, 0.78, 0.25, 0.10)
        local label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("LEFT", 8, 0)
        label:SetJustifyH("LEFT")
        label:SetText(option.label)
        button:SetScript("OnClick", function()
            setPendingLanguage(value)
            languageMenu:Hide()
        end)
        languageMenu.buttons[index] = button
    end

    local languageToggle = CreateFrame("Button", nil, optionsPanel)
    languageToggle:SetSize(190, 24)
    languageToggle:SetPoint("TOPLEFT", 14, -40)
    languageToggle:SetFrameLevel(languageDropDown:GetFrameLevel() + 5)
    languageToggle:SetScript("OnClick", function()
        languageMenu:SetShown(not languageMenu:IsShown())
    end)

    apply:SetScript("OnClick", function()
        ns.Locale:SetLanguage(optionsPanel.pendingLanguage)
    end)

    local reloadNote = optionsPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    reloadNote:SetPoint("TOPLEFT", 14, -122)
    reloadNote:SetPoint("RIGHT", -14, 0)
    reloadNote:SetJustifyH("LEFT")
    reloadNote:SetJustifyV("TOP")
    reloadNote:SetWordWrap(true)
    reloadNote:SetText(L("reload_note"))
    reloadNote:SetTextColor(unpack(COLORS.muted))

    local minimapCheckButton = ns.Settings:CreateMinimapCheckButton(optionsPanel)
    minimapCheckButton:SetPoint("TOPLEFT", 10, -148)

    local dataTitle = optionsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    dataTitle:SetPoint("TOPLEFT", 14, -188)
    dataTitle:SetText(L("data_sources_title"))
    dataTitle:SetTextColor(unpack(COLORS.gold))

    local dataSummary = optionsPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    dataSummary:SetPoint("TOPLEFT", 14, -210)
    dataSummary:SetPoint("RIGHT", -14, 0)
    dataSummary:SetJustifyH("LEFT")
    dataSummary:SetJustifyV("TOP")
    dataSummary:SetWordWrap(true)
    dataSummary:SetTextColor(unpack(COLORS.muted))

    local function refreshOptions()
        setPendingLanguage(ns.Locale:GetLanguage())
        ns.Settings:RefreshControls()
        local status = ns.DataProvider:GetStatus()
        local questie = status.questieAvailable
            and L("data_questie_live", status.version or L("unknown_version"))
            or L("data_questie_snapshot", status.snapshotVersion or L("unknown_version"))
        local clientBuild = GetBuildInfo and select(2, GetBuildInfo()) or L("unknown_version")
        dataSummary:SetText(table.concat({
            questie,
            L("data_builds", status.recipeVersion or L("unknown_version"), clientBuild),
            L("data_local", ns.Storage:CountObservations(),
                status.observedRecipes or 0),
            L(status.sourceVersion and "data_cmangos_enabled" or "data_cmangos_disabled"),
        }, "\n"))
    end

    optionsPanel.gamepadControls = { languageToggle, apply, minimapCheckButton }
    optionsPanel.languageMenu = languageMenu

    options:SetScript("OnClick", function()
        local show = not optionsPanel:IsShown()
        if show then refreshOptions() end
        if not show then languageMenu:Hide() end
        optionsPanel:SetShown(show)
    end)
    optionsPanel:SetScript("OnHide", function() languageMenu:Hide() end)

    local searchLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    searchLabel:SetPoint("TOPRIGHT", -354, -17)
    searchLabel:SetText(L("search"))
    searchLabel:SetTextColor(unpack(COLORS.muted))

    local search = CreateFrame("EditBox", "ForeverpediaSearchBox", frame, "InputBoxTemplate")
    search:SetSize(290, 24)
    search:SetPoint("TOPRIGHT", -50, -10)
    search:SetAutoFocus(false)
    search:SetMaxLetters(80)
    search:SetTextInsets(8, 8, 0, 0)

    local searchPlaceholder = search:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    searchPlaceholder:SetPoint("LEFT", 8, 0)
    searchPlaceholder:SetText(L("search_placeholder"))
    search.placeholder = searchPlaceholder

    local suggestions = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    suggestions:SetPoint("TOPLEFT", search, "BOTTOMLEFT", -3, -3)
    suggestions:SetWidth(360)
    suggestions:SetFrameStrata("TOOLTIP")
    suggestions:SetFrameLevel(frame:GetFrameLevel() + 50)
    setBackdrop(suggestions, COLORS.panel)
    suggestions.buttons = {}
    suggestions:Hide()
    for index = 1, ns.Config.searchResultLimit do
        local button = CreateFrame("Button", nil, suggestions)
        button:SetHeight(24)
        button:SetPoint("TOPLEFT", 5, -5 - (index - 1) * 24)
        button:SetPoint("TOPRIGHT", -5, -5 - (index - 1) * 24)
        local highlight = button:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetColorTexture(1, 0.78, 0.25, 0.12)
        local label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        label:SetPoint("LEFT", 6, 0)
        label:SetPoint("RIGHT", -6, 0)
        label:SetJustifyH("LEFT")
        button.label = label
        button:SetScript("OnClick", function(self) UI:OpenSearchResult(self.result) end)
        button:SetScript("OnEnter", function(self)
            if not self.result then return end
            UI.searchSelection = index
            UI:RefreshSearchSelection()
            UI:ShowItemTooltip(self, self.result.itemID)
        end)
        button:SetScript("OnLeave", function() UI:HideItemTooltip() end)
        suggestions.buttons[index] = button
    end

    search:SetScript("OnTextChanged", function(self)
        self.placeholder:SetShown(self:GetText() == "" and not self:HasFocus())
        if not UI.suppressSearch then UI:ScheduleSearch() end
    end)
    search:SetScript("OnEditFocusGained", function(self)
        self.placeholder:Hide()
        UI:ScheduleSearch()
    end)
    search:SetScript("OnEditFocusLost", function(self)
        self.placeholder:SetShown(self:GetText() == "")
    end)
    search:SetScript("OnEnterPressed", function()
        UI:ActivateSearchSuggestion()
    end)
    search:SetScript("OnEscapePressed", function(self)
        suggestions:Hide()
        self:ClearFocus()
    end)
    search:SetScript("OnArrowPressed", function(_, key)
        UI:MoveSearchSelection(key == "DOWN" and 1 or -1)
    end)

    local questieAvailable = ns.DataProvider:GetStatus().questieAvailable
    local questieHint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    questieHint:SetPoint("TOPLEFT", 20, -40)
    questieHint:SetPoint("TOPRIGHT", -20, -40)
    questieHint:SetJustifyH("LEFT")
    questieHint:SetText(L("questie_install_hint"))
    questieHint:SetTextColor(0.95, 0.66, 0.24)
    questieHint:SetShown(not questieAvailable)

    local updateHint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    updateHint:SetPoint("TOPLEFT", 20, -40)
    updateHint:SetPoint("TOPRIGHT", -20, -40)
    updateHint:SetJustifyH("LEFT")
    updateHint:SetTextColor(1, 0.48, 0.20)
    updateHint:Hide()

    local header = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    header:SetPoint("TOPLEFT", 20, -54)
    header:SetPoint("TOPRIGHT", -20, -54)
    header:SetHeight(82)
    setBackdrop(header, COLORS.panel)

    local iconBorder = CreateFrame("Frame", nil, header, "BackdropTemplate")
    iconBorder:SetSize(58, 58)
    iconBorder:SetPoint("LEFT", 12, 0)
    setBackdrop(iconBorder, { 0.02, 0.02, 0.02, 1 })

    local icon = iconBorder:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 5, -5)
    icon:SetPoint("BOTTOMRIGHT", -5, 5)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    iconBorder:EnableMouse(true)
    iconBorder:SetScript("OnEnter", function(self)
        if not UI.currentItemLink then
            return
        end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink(UI.currentItemLink)
        GameTooltip:Show()
    end)
    iconBorder:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    local itemName = header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    itemName:SetPoint("TOPLEFT", iconBorder, "TOPRIGHT", 12, -7)
    itemName:SetPoint("TOPRIGHT", -180, -7)
    itemName:SetJustifyH("LEFT")

    local itemMeta = header:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    itemMeta:SetPoint("TOPLEFT", itemName, "BOTTOMLEFT", 0, -7)
    itemMeta:SetPoint("RIGHT", -180, 0)
    itemMeta:SetJustifyH("LEFT")
    itemMeta:SetTextColor(unpack(COLORS.muted))

    local tabs = {
        { key = "uses", label = L("uses") },
        { key = "sources", label = L("sources") },
    }
    local tabBar = CreateFrame("Frame", nil, frame)
    tabBar:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)
    tabBar:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, -4)
    tabBar:SetHeight(40)
    local tabDivider = tabBar:CreateTexture(nil, "ARTWORK")
    tabDivider:SetPoint("BOTTOMLEFT", 0, 0)
    tabDivider:SetPoint("BOTTOMRIGHT", 0, 0)
    tabDivider:SetHeight(1)
    tabDivider:SetColorTexture(COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.65)

    frame.tabButtons = {}
    local previous
    for _, tab in ipairs(tabs) do
        local button = CreateFrame("Button", nil, tabBar)
        button:SetSize(154, 38)
        if previous then
            button:SetPoint("LEFT", previous, "RIGHT", 8, 0)
        else
            button:SetPoint("LEFT", tabBar, "LEFT", 12, 0)
        end
        local highlight = button:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetPoint("TOPLEFT", 0, -3)
        highlight:SetPoint("BOTTOMRIGHT", 0, 3)
        highlight:SetColorTexture(1, 0.78, 0.25, 0.06)
        local label = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("LEFT", 8, 0)
        label:SetPoint("RIGHT", -8, 0)
        label:SetJustifyH("LEFT")
        label:SetText(tab.label)
        local underline = button:CreateTexture(nil, "OVERLAY")
        underline:SetPoint("BOTTOMLEFT", 4, 0)
        underline:SetPoint("BOTTOMRIGHT", -4, 0)
        underline:SetHeight(2)
        underline:SetColorTexture(unpack(COLORS.gold))
        button.label = label
        button.underline = underline
        button:SetScript("OnClick", function()
            UI:SetTab(tab.key)
        end)
        frame.tabButtons[tab.key] = button
        previous = button
    end

    local craftTreeButton = CreateFrame("Button", nil, header, "BackdropTemplate")
    craftTreeButton:SetSize(152, 28)
    craftTreeButton:SetPoint("RIGHT", header, "RIGHT", -12, 0)
    setBackdrop(craftTreeButton, { 0.035, 0.028, 0.020, 0.78 })
    craftTreeButton:SetBackdropBorderColor(0.28, 0.23, 0.16, 0.85)
    local craftTreeLabel = craftTreeButton:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    craftTreeLabel:SetPoint("CENTER", 0, 0)
    craftTreeLabel:SetText(L("craft_chain"))
    craftTreeLabel:SetTextColor(unpack(COLORS.muted))
    local craftTreeHighlight = craftTreeButton:CreateTexture(nil, "HIGHLIGHT")
    craftTreeHighlight:SetPoint("TOPLEFT", 4, -4)
    craftTreeHighlight:SetPoint("BOTTOMRIGHT", -4, 4)
    craftTreeHighlight:SetColorTexture(1, 0.78, 0.25, 0.06)
    craftTreeButton.label = craftTreeLabel
    craftTreeButton:SetScript("OnClick", function()
        if ns.CraftTree and UI.currentItemID then ns.CraftTree:Open(UI.currentItemID) end
    end)
    craftTreeButton:SetScript("OnEnter", function(self)
        self.label:SetTextColor(unpack(COLORS.gold))
        self:SetBackdropBorderColor(COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.9)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(L("craft_chain_tip1"))
        GameTooltip:AddLine(L("craft_chain_tip2"), 0.70, 0.66, 0.57)
        GameTooltip:Show()
    end)
    craftTreeButton:SetScript("OnLeave", function(self)
        self.label:SetTextColor(unpack(COLORS.muted))
        self:SetBackdropBorderColor(0.28, 0.23, 0.16, 0.85)
        GameTooltip:Hide()
    end)
    craftTreeButton:Hide()

    local details = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    details:SetPoint("TOPRIGHT", tabBar, "BOTTOMRIGHT", 0, -8)
    details:SetPoint("BOTTOMRIGHT", -20, 42)
    details:SetWidth(390)
    setBackdrop(details, COLORS.panel)

    local listPanel = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    listPanel:SetPoint("TOPLEFT", tabBar, "BOTTOMLEFT", 0, -8)
    listPanel:SetPoint("BOTTOMRIGHT", details, "BOTTOMLEFT", -12, 0)
    setBackdrop(listPanel, COLORS.background)

    local scroll = CreateFrame("ScrollFrame", nil, listPanel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 12, -12)
    scroll:SetPoint("BOTTOMRIGHT", -30, 12)

    local detailsTitle = details:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    detailsTitle:SetPoint("TOPLEFT", 14, -13)
    detailsTitle:SetText(L("details"))
    detailsTitle:SetTextColor(unpack(COLORS.gold))

    local detailScroll = CreateFrame("ScrollFrame", nil, details, "UIPanelScrollFrameTemplate")
    detailScroll:SetPoint("TOPLEFT", 12, -36)
    detailScroll:SetPoint("BOTTOMRIGHT", -30, 12)
    local detailContent = CreateFrame("Frame", nil, detailScroll)
    detailContent:SetSize(340, 1)
    detailContent.lines = {}
    detailContent.buttons = {}
    detailContent.itemButtons = {}
    detailContent.groupButtons = {}
    detailScroll:SetScrollChild(detailContent)
    details.scroll = detailScroll
    details.content = detailContent
    details.title = detailsTitle

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(674, 1)
    content.lines = {}
    content.groupButtons = {}
    content.relationButtons = {}
    scroll:SetScrollChild(content)

    local footer = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    footer:SetPoint("BOTTOMLEFT", 20, 18)
    footer:SetPoint("BOTTOMRIGHT", -20, 18)
    footer:SetJustifyH("CENTER")
    footer:SetTextColor(unpack(COLORS.muted))

    frame.header = header
    frame.questieHint = questieHint
    frame.questieAvailable = questieAvailable
    frame.updateHint = updateHint
    frame.itemIcon = icon
    frame.itemName = itemName
    frame.itemMeta = itemMeta
    frame.scroll = scroll
    frame.content = content
    frame.footer = footer
    frame.details = details
    frame.listPanel = listPanel
    frame.tabBar = tabBar
    frame.backButton = back
    frame.optionsButton = options
    frame.optionsPanel = optionsPanel
    frame.searchBox = search
    frame.searchSuggestions = suggestions
    frame.craftTreeButton = craftTreeButton
    frame.gamepadTopControls = { back, options, search }

    local resize = CreateFrame("Button", nil, frame)
    resize:SetSize(20, 20)
    resize:SetPoint("BOTTOMRIGHT", -4, 4)
    resize:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resize:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resize:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    resize:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then frame:StartSizing("BOTTOMRIGHT") end
    end)
    resize:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
        saveSize(frame)
    end)
    frame.resize = resize

    frame:SetScript("OnSizeChanged", function()
        details:SetWidth(math.max(330, math.min(520, frame:GetWidth() * 0.36)))
        local listWidth = math.max(300, scroll:GetWidth() - 24)
        content:SetWidth(listWidth)
        detailContent:SetWidth(math.max(260, detailScroll:GetWidth() - 4))
    end)
    frame:SetScript("OnHide", function()
        if ns.CraftTree and ns.CraftTree.frame then ns.CraftTree.frame:Hide() end
        optionsPanel:Hide()
        if ns.Gamepad and ns.Gamepad.OnWindowHidden then
            ns.Gamepad:OnWindowHidden()
        end
    end)
    details:SetWidth(math.max(330, math.min(520, frame:GetWidth() * 0.36)))
    content:SetWidth(math.max(300, scroll:GetWidth() - 24))
    detailContent:SetWidth(math.max(260, detailScroll:GetWidth() - 4))
    self.frame = frame
    self:UpdateTopNotices()

    if UISpecialFrames then
        UISpecialFrames[#UISpecialFrames + 1] = "ForeverpediaFrame"
    end

    self:UpdateTabs()
    self:UpdateBackButton()
    if ns.Gamepad and ns.Gamepad.AttachUI then ns.Gamepad:AttachUI(frame) end
    frame:Hide()
    return frame
end

local function appendGamepadControls(result, controls, zone)
    for _, control in ipairs(controls or {}) do
        if control and control.IsShown and control:IsShown() then
            control.fpGamepadZone = zone
            result[#result + 1] = control
        end
    end
end

function UI:GetGamepadControls()
    local result = {}
    if ns.CraftTree and ns.CraftTree.frame and ns.CraftTree.frame:IsShown()
            and ns.CraftTree.GetGamepadControls then
        return ns.CraftTree:GetGamepadControls()
    end
    if not (self.frame and self.frame:IsShown()) then return result end

    local optionsPanel = self.frame.optionsPanel
    if optionsPanel and optionsPanel:IsShown() then
        local menu = optionsPanel.languageMenu
        if menu and menu:IsShown() then
            appendGamepadControls(result, menu.buttons, "options")
        else
            appendGamepadControls(result, optionsPanel.gamepadControls, "options")
        end
        return result
    end

    appendGamepadControls(result, self.frame.gamepadTopControls, "top")
    if self.frame.searchSuggestions and self.frame.searchSuggestions:IsShown() then
        appendGamepadControls(result, self.frame.searchSuggestions.buttons, "search")
    end
    local content = self.frame.content
    appendGamepadControls(result, content and content.groupButtons, "list")
    appendGamepadControls(result, content and content.relationButtons, "list")

    local detailContent = self.frame.details and self.frame.details.content
    appendGamepadControls(result, detailContent and detailContent.groupButtons, "details")
    appendGamepadControls(result, detailContent and detailContent.itemButtons, "details")
    appendGamepadControls(result, detailContent and detailContent.buttons, "details")
    appendGamepadControls(result,
        detailContent and { detailContent.recipeChainButton } or nil, "details")
    return result
end

function UI:AcquireLine(fontObject)
    local content = self.frame.content
    local lineIndex = (content.usedLines or 0) + 1
    content.usedLines = lineIndex

    local line = content.lines[lineIndex]
    if not line then
        line = content:CreateFontString(nil, "OVERLAY", fontObject)
        content.lines[lineIndex] = line
    end

    line:Show()
    line:ClearAllPoints()
    line:SetFontObject(fontObject)
    line:SetJustifyH("LEFT")
    line:SetJustifyV("TOP")
    line:SetWordWrap(true)
    line:SetTextColor(unpack(COLORS.normal))
    return line
end

function UI:ClearLines()
    local content = self.frame.content
    content.usedLines = 0
    content.usedGroupButtons = 0
    content.usedRelationButtons = 0
    for _, line in ipairs(content.lines) do
        line:Hide()
    end
    for _, button in ipairs(content.groupButtons) do
        button:Hide()
    end
    for _, button in ipairs(content.relationButtons) do
        button:Hide()
    end
    self.cursorY = -4
end

function UI:AddLine(text, fontObject, color, indent, gap)
    local content = self.frame.content
    local line = self:AcquireLine(fontObject or "GameFontHighlight")
    indent = indent or 4
    line:SetWidth(content:GetWidth() - indent - 8)
    line:SetPoint("TOPLEFT", content, "TOPLEFT", indent, self.cursorY)
    line:SetText(text or "")
    if color then
        line:SetTextColor(unpack(color))
    end

    local height = math.max(16, math.ceil(line:GetStringHeight()))
    self.cursorY = self.cursorY - height - (gap or 6)
    return line
end

local quantityText

local function moneyText(copper)
    if not copper or copper <= 0 then
        return L("price_unknown")
    end
    if GetMoneyString then
        return GetMoneyString(copper, true)
    end
    local gold = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    local coins = copper % 100
    return L("money", gold, silver, coins)
end

local areaToUiMapID
local reopenAfterMap, mapHideHooked = false, false

local function loadAreaMap()
    if areaToUiMapID ~= nil then return areaToUiMapID or nil end
    areaToUiMapID = false
    local support = LibQuestieDB and LibQuestieDB.Support
    if not (support and type(support.Get) == "function") then return nil end
    local ok, zones = pcall(support.Get, "ZoneDB")
    local encoded = ok and zones and zones.private and zones.private.areaIdToUiMapId
    if type(encoded) == "string" and type(loadstring) == "function" then
        local chunk = loadstring(encoded)
        local decoded, mapping = pcall(chunk or error)
        if decoded and type(mapping) == "table" then areaToUiMapID = mapping end
    elseif type(encoded) == "table" then
        areaToUiMapID = encoded
    end
    return areaToUiMapID or nil
end

local function validUiMapID(areaID)
    local mapping = loadAreaMap()
    local mapID = mapping and mapping[areaID] or areaID
    if not mapID or mapID == 0 then return nil end
    if C_Map and type(C_Map.GetMapInfo) == "function" and not C_Map.GetMapInfo(mapID) then
        return nil
    end
    return mapID
end

local function generalZoneName(areaID, fallback)
    local mapID = validUiMapID(areaID)
    if not (mapID and C_Map and type(C_Map.GetMapInfo) == "function") then
        return fallback
    end
    local info = C_Map.GetMapInfo(mapID)
    local zoneType = Enum and Enum.UIMapType and Enum.UIMapType.Zone or 3
    local seen = {}
    while info and info.mapType and info.mapType > zoneType
            and info.parentMapID and info.parentMapID > 0
            and not seen[info.parentMapID] do
        seen[info.parentMapID] = true
        info = C_Map.GetMapInfo(info.parentMapID)
    end
    return info and info.name or fallback
end

local function sourceGeneralZones(relation)
    local seen, result = {}, {}
    local function add(areaID, fallback)
        local zone = generalZoneName(areaID, fallback)
        if zone and zone ~= "" and not seen[zone] then
            seen[zone] = true
            result[#result + 1] = zone
        end
    end
    add(relation.areaID, relation.zone)
    for _, location in ipairs(relation.locations or {}) do
        add(location.areaID, location.zone or relation.zone)
    end
    if #result == 0 then add(nil, relation.zone) end
    table.sort(result)
    return result
end

local function hideForeverpediaForMap()
    if not (UI.frame and UI.frame:IsShown() and WorldMapFrame and WorldMapFrame:IsShown()) then
        return
    end
    if not mapHideHooked and type(WorldMapFrame.HookScript) == "function" then
        mapHideHooked = true
        WorldMapFrame:HookScript("OnHide", function()
            local function reopen()
                if not (reopenAfterMap and UI.frame) then return end
                reopenAfterMap = false
                UI.frame:Show()
                UI.frame:Raise()
                if ns.Gamepad and ns.Gamepad.OnWindowOpened then
                    ns.Gamepad:OnWindowOpened()
                end
            end
            if reopenAfterMap and C_Timer and type(C_Timer.After) == "function" then
                -- Leave Blizzard's protected map-close and native focus-restoration
                -- call chain before showing an addon frame again.
                C_Timer.After(0, reopen)
            else
                reopen()
            end
        end)
    end
    reopenAfterMap = true
    UI.frame:Hide()
end

local function setNativeWaypoint(mapID, x, y)
    if not (C_Map and type(C_Map.SetUserWaypoint) == "function") then return end
    local canSet = true
    if type(C_Map.CanSetUserWaypointOnMap) == "function" then
        local ok, allowed = pcall(C_Map.CanSetUserWaypointOnMap, mapID)
        canSet = ok and allowed == true
    end
    local maker = rawget(_G, "UiMapPoint")
    if not (canSet and type(maker) == "table"
            and type(maker.CreateFromCoordinates) == "function") then return end
    local ok, point = pcall(maker.CreateFromCoordinates, mapID, x / 100, y / 100)
    if not (ok and point) then return end
    local setOK = pcall(C_Map.SetUserWaypoint, point)
    local tracker = rawget(_G, "C_SuperTrack")
    if setOK and type(tracker) == "table"
            and type(tracker.SetSuperTrackedUserWaypoint) == "function" then
        pcall(tracker.SetSuperTrackedUserWaypoint, true)
    end
end

local function setWaypointAndOpenMap(location)
    local areaID, x, y = location and location.areaID, location and location.x, location and location.y
    if type(areaID) ~= "number" or type(x) ~= "number" or type(y) ~= "number" then
        return false
    end
    local mapID = validUiMapID(areaID)
    if not (mapID and WorldMapFrame) then return false end
    local gamepadLayout = ns.Gamepad and ns.Gamepad.IsLayoutActive
        and ns.Gamepad:IsLayoutActive()
    local openedWithMapAPI = false
    if C_Map and type(C_Map.OpenWorldMap) == "function" then
        local ok, opened = pcall(C_Map.OpenWorldMap, mapID)
        openedWithMapAPI = ok and opened ~= false
    end
    if not WorldMapFrame:IsShown() then
        if not openedWithMapAPI and type(ToggleWorldMap) == "function" then
            pcall(ToggleWorldMap)
        elseif not openedWithMapAPI and type(ShowUIPanel) == "function" then
            pcall(ShowUIPanel, WorldMapFrame)
        end
    end
    -- SetMapID synchronously rebuilds Blizzard's Gamepad UI bindings in the
    -- caller's tainted execution path. OpenWorldMap crosses the client API
    -- boundary safely; retain SetMapID only as a non-gamepad legacy fallback.
    if not openedWithMapAPI and not gamepadLayout
            and type(WorldMapFrame.SetMapID) == "function" then
        pcall(WorldMapFrame.SetMapID, WorldMapFrame, mapID)
    end
    setNativeWaypoint(mapID, x, y)
    hideForeverpediaForMap()
    if type(WorldMapFrame.Raise) == "function" then WorldMapFrame:Raise() end
    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(0, function()
            if WorldMapFrame and WorldMapFrame:IsShown() then
                if not openedWithMapAPI and not gamepadLayout
                        and type(WorldMapFrame.SetMapID) == "function" then
                    pcall(WorldMapFrame.SetMapID, WorldMapFrame, mapID)
                end
                setNativeWaypoint(mapID, x, y)
            end
        end)
    end
    return WorldMapFrame:IsShown()
end

function UI:ClearDetails()
    local content = self.frame.details.content
    content.usedLines, content.usedButtons, content.usedItemButtons,
        content.usedGroupButtons = 0, 0, 0, 0
    for _, line in ipairs(content.lines) do line:Hide() end
    for _, button in ipairs(content.buttons) do button:Hide() end
    for _, button in ipairs(content.itemButtons) do button:Hide() end
    for _, button in ipairs(content.groupButtons) do button:Hide() end
    if content.recipeChainButton then content.recipeChainButton:Hide() end
    if content.tooltip then content.tooltip:Hide() end
    self.detailCursorY = -4
end

function UI:DetailCraftTreeButton(relation, heading)
    if not (relation and ns.CraftTree) then return end
    local itemID = relation.outputItemID
    local itemAvailable = itemID and itemID ~= 0 and ns.CraftTree:IsAvailable(itemID)
    local recipeAvailable = ns.CraftTree:IsRecipeAvailable(relation)
    if not (itemAvailable or recipeAvailable) then return end
    local content = self.frame.details.content
    local button = content.recipeChainButton
    if not button then
        button = CreateFrame("Button", nil, content, "BackdropTemplate")
        button:SetSize(154, 25)
        setBackdrop(button, { 0.035, 0.028, 0.020, 0.90 })
        button:SetBackdropBorderColor(0.28, 0.23, 0.16, 0.90)
        local label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("CENTER", 0, 0)
        label:SetTextColor(unpack(COLORS.muted))
        button.label = label
        button:SetScript("OnClick", function(self)
            if not ns.CraftTree then return end
            if self.itemID and self.itemID ~= 0 then
                ns.CraftTree:Open(self.itemID)
            else
                ns.CraftTree:OpenRecipe(self.recipe)
            end
        end)
        button:SetScript("OnEnter", function(self)
            self.label:SetTextColor(unpack(COLORS.gold))
            self:SetBackdropBorderColor(COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.9)
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:AddLine(L("craft_chain_tip1"))
            GameTooltip:AddLine(L("craft_chain_tip2"), 0.70, 0.66, 0.57)
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", function(self)
            self.label:SetTextColor(unpack(COLORS.muted))
            self:SetBackdropBorderColor(0.28, 0.23, 0.16, 0.90)
            GameTooltip:Hide()
        end)
        content.recipeChainButton = button
    end
    button:Show()
    button:ClearAllPoints()
    button.itemID = itemID
    button.recipe = relation
    button.heading = heading
    button.label:SetText(L("craft_chain"))
    local headingWidth = heading and math.ceil(heading:GetStringWidth()) or 0
    button:SetPoint("LEFT", heading, "LEFT", headingWidth + 12, 0)
end

function UI:DetailItemButton(itemID, quantity, indent)
    local content = self.frame.details.content
    local index = (content.usedItemButtons or 0) + 1
    content.usedItemButtons = index
    local button = content.itemButtons[index]
    if not button then
        button = CreateFrame("Button", nil, content)
        button:SetHeight(22)
        button:RegisterForClicks("LeftButtonUp")
        local highlight = button:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetColorTexture(1, 0.78, 0.25, 0.10)
        local label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        label:SetPoint("LEFT", 2, 0)
        label:SetPoint("RIGHT", -2, 0)
        label:SetJustifyH("LEFT")
        button.label = label
        content.itemButtons[index] = button
    end
    button:Show()
    button:ClearAllPoints()
    indent = indent or 12
    button:SetPoint("TOPLEFT", content, "TOPLEFT", indent, self.detailCursorY)
    button:SetWidth(content:GetWidth() - indent - 8)
    local icon = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(itemID)
    local iconMarkup = icon and string.format("|T%d:18:18:0:0|t ", icon) or ""
    local amount = quantity and quantity > 1 and ("  |cffb3a890×" .. quantity .. "|r") or ""
    button.label:SetText(iconMarkup .. itemDisplayName(itemID) .. amount)
    button.itemID = itemID
    button:SetScript("OnEnter", function(self)
        UI:ShowItemTooltip(self, self.itemID, function()
            if not (ns.Gamepad and ns.Gamepad:IsLayoutActive()) then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(L("alt_open"), 0.95, 0.72, 0.27)
            end
        end)
    end)
    button:SetScript("OnLeave", function() UI:HideItemTooltip() end)
    button:SetScript("OnClick", function(self, mouseButton)
        if mouseButton == "LeftButton" and IsAltKeyDown and IsAltKeyDown() then
            UI:OpenItem("item:" .. tostring(self.itemID), self.itemID)
        end
    end)
    button.fpGamepadActivate = function(self)
        UI:OpenItem("item:" .. tostring(self.itemID), self.itemID)
    end
    self.detailCursorY = self.detailCursorY - 24
    if C_Item and C_Item.RequestLoadItemDataByID then
        C_Item.RequestLoadItemDataByID(itemID)
    end
end

function UI:DetailLine(text, fontObject, color, indent, gap)
    local content = self.frame.details.content
    local index = (content.usedLines or 0) + 1
    content.usedLines = index
    local line = content.lines[index]
    if not line then
        line = content:CreateFontString(nil, "OVERLAY", fontObject or "GameFontHighlight")
        content.lines[index] = line
    end
    line:Show()
    line:ClearAllPoints()
    line:SetFontObject(fontObject or "GameFontHighlight")
    line:SetTextColor(unpack(color or COLORS.normal))
    line:SetJustifyH("LEFT")
    line:SetJustifyV("TOP")
    line:SetWordWrap(true)
    indent = indent or 4
    line:SetWidth(content:GetWidth() - indent - 8)
    line:SetPoint("TOPLEFT", content, "TOPLEFT", indent, self.detailCursorY)
    line:SetText(text or "")
    local height = math.max(16, math.ceil(line:GetStringHeight()))
    self.detailCursorY = self.detailCursorY - height - (gap or 5)
    return line
end

function UI:DetailGroupHeader(title, key, count)
    local content = self.frame.details.content
    local index = (content.usedGroupButtons or 0) + 1
    content.usedGroupButtons = index
    local button = content.groupButtons[index]
    if not button then
        button = CreateFrame("Button", nil, content)
        button:SetHeight(22)
        local label = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetAllPoints()
        label:SetJustifyH("LEFT")
        label:SetTextColor(unpack(COLORS.gold))
        button.label = label
        local highlight = button:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetColorTexture(1, 0.78, 0.25, 0.08)
        content.groupButtons[index] = button
    end
    button:Show()
    button:ClearAllPoints()
    button:SetPoint("TOPLEFT", content, "TOPLEFT", 6, self.detailCursorY)
    button:SetWidth(content:GetWidth() - 14)
    local expanded = self.detailExpanded[key] == true
    button.label:SetText(string.format("%s  %s (%d)", expanded and "[-]" or "[+]", title, count))
    button:SetScript("OnClick", function()
        UI.detailExpanded[key] = not expanded
        UI:RefreshDetails(true)
    end)
    self.detailCursorY = self.detailCursorY - 25
    return expanded
end

function UI:DetailCoordinateButton(location, indent)
    local content = self.frame.details.content
    local index = (content.usedButtons or 0) + 1
    content.usedButtons = index
    local button = content.buttons[index]
    if not button then
        button = CreateFrame("Button", nil, content)
        button:SetHeight(19)
        local label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetAllPoints()
        label:SetJustifyH("LEFT")
        button.label = label
        local highlight = button:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetColorTexture(0.25, 0.62, 1, 0.12)
        content.buttons[index] = button
    end
    button:Show()
    button:ClearAllPoints()
    indent = indent or 30
    button:SetPoint("TOPLEFT", content, "TOPLEFT", indent, self.detailCursorY)
    button:SetWidth(content:GetWidth() - indent - 8)
    button.label:SetText("|cff55aaff" .. L("coordinates",
        location.x or 0, location.y or 0) .. "|r")
    button:SetScript("OnClick", function()
        setWaypointAndOpenMap(location)
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L("open_map"))
        GameTooltip:AddLine(location.zone or "", 0.70, 0.66, 0.57)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self.detailCursorY = self.detailCursorY - 21
end

local DETAIL_SOURCE_GROUPS = {
    { key = "drop", titleKey = "drop", kinds = { recipe_drop = true, recipe_object = true } },
    { key = "trainer", titleKey = "trainers", kinds = { trainer = true } },
    { key = "vendor", titleKey = "vendors", kinds = { recipe_vendor = true } },
    { key = "quest", titleKey = "quests", kinds = { recipe_quest = true } },
    { key = "unknown", titleKey = "source_undefined",
        kinds = { recipe_item = true, recipe_unknown = true } },
}

function UI:DetailQuestMetadata(relation, indent)
    if not relation.questID then return end
    indent = indent or 4
    if relation.questLevel and relation.questLevel > 0 then
        self:DetailLine(L("quest_level", relation.questLevel),
            "GameFontHighlightSmall", COLORS.normal, indent, 3)
    end
    if relation.questFaction then
        self:DetailLine(L("faction", relation.questFaction),
            "GameFontHighlightSmall", COLORS.normal, indent, 3)
    end
    if relation.starterNames and #relation.starterNames > 0 then
        local visible = {}
        for index = 1, math.min(3, #relation.starterNames) do
            visible[#visible + 1] = relation.starterNames[index]
        end
        local suffix = #relation.starterNames > 3
            and (" " .. L("more", #relation.starterNames - 3)) or ""
        self:DetailLine(L("starts_at", table.concat(visible, ", "), suffix),
            "GameFontHighlightSmall", COLORS.muted, indent, 5)
    end
end

function UI:DetailLearningSource(source)
    if source.kind == "recipe_unknown" then
        self:DetailLine(L("recipe_item_unknown", tostring(source.recipeItemID or "?")),
            "GameFontHighlightSmall", COLORS.normal, 20, 3)
        self:DetailLine(L("vendor_observe"),
            "GameFontHighlightSmall", COLORS.muted, 20, 3)
        return
    end
    local text = source.name or L("source_unknown")
    if source.price and source.price > 0 then
        text = text .. " • " .. moneyText(source.price)
        if source.vendorStack and source.vendorStack > 1 then
            text = text .. L("per_stack", source.vendorStack)
        end
    end
    if source.zone then text = text .. " • " .. source.zone end
    if source.historical then text = text .. " |cffb3a890(" .. L("classic_data") .. ")|r" end
    self:DetailLine(text, "GameFontHighlightSmall", COLORS.normal, 20, 3)
    self:DetailQuestMetadata(source, 30)
    for index, location in ipairs(source.locations or {}) do
        if index > 5 then break end
        self:DetailCoordinateButton(location, 30)
    end
    if source.locations and #source.locations > 5 then
        self:DetailLine(L("more_coordinates", #source.locations - 5),
            "GameFontHighlightSmall", COLORS.muted, 30, 5)
    end
end

function UI:ShowRecipeDetails(relation, preserveScroll)
    if not self.frame then return end
    local oldScroll = preserveScroll and self.frame.details.scroll:GetVerticalScroll() or 0
    self.detailSelection = { kind = "recipe", relation = relation }
    self:ClearDetails()
    self:DetailLine(relation.name or L("recipe"), "GameFontNormalLarge", COLORS.gold, 4, 8)
    local professionText = relation.professionName or ""
    if relation.requiredSkillRank and relation.requiredSkillRank > 0 then
        professionText = L("profession_with_requirement",
            relation.requiredProfessionName or professionText or L("profession"),
            relation.requiredSkillRank)
    end
    self:DetailLine(professionText, "GameFontHighlightSmall", COLORS.muted, 4, 8)

    local content = self.frame.details.content
    local tooltip = content.tooltip
    if not tooltip then
        tooltip = CreateFrame("GameTooltip", "ForeverpediaDetailTooltip", content, "GameTooltipTemplate")
        content.tooltip = tooltip
    end
    tooltip:ClearAllPoints()
    tooltip:SetOwner(content, "ANCHOR_NONE")
    tooltip:SetPoint("TOPLEFT", content, "TOPLEFT", 4, self.detailCursorY)
    local drawn = type(tooltip.SetSpellByID) == "function"
        and pcall(tooltip.SetSpellByID, tooltip, relation.recipeID)
    if not drawn and type(tooltip.SetHyperlink) == "function" then
        drawn = pcall(tooltip.SetHyperlink, tooltip, "spell:" .. tostring(relation.recipeID))
    end
    if not drawn then tooltip:AddLine(relation.name or L("recipe")) end
    tooltip:Show()
    self.detailCursorY = self.detailCursorY - math.max(70, tooltip:GetHeight() or 0) - 12

    local ingredientsHeader = self:DetailLine(
        L("ingredients"), "GameFontNormal", COLORS.gold, 4, 7)
    self:DetailCraftTreeButton(relation, ingredientsHeader)
    local ingredients = relation.ingredients or {}
    if #ingredients == 0 then
        self:DetailLine(L("no_ingredients"),
            "GameFontHighlightSmall", COLORS.muted, 12, 8)
    else
        for _, ingredient in ipairs(ingredients) do
            self:DetailItemButton(ingredient.itemID or ingredient[1],
                ingredient.quantity or ingredient[2], 12)
        end
        local ingredientHint = ns.Gamepad and ns.Gamepad:IsLayoutActive()
            and L("ingredient_gamepad") or L("ingredient_alt")
        self:DetailLine(ingredientHint,
            "GameFontHighlightSmall", COLORS.muted, 12, 10)
    end

    self:DetailLine(L("acquisition_sources"), "GameFontNormal", COLORS.gold, 4, 7)
    local sources = relation.learningSources or {}
    if #sources == 0 then
        self:DetailLine(L("unknown_source") .. ".", "GameFontHighlightSmall", COLORS.muted, 12, 8)
    else
        local assigned = {}
        for _, definition in ipairs(DETAIL_SOURCE_GROUPS) do
            local group = {}
            for index, source in ipairs(sources) do
                if definition.kinds[source.kind] then
                    group[#group + 1] = source
                    assigned[index] = true
                end
            end
            if #group > 0 then
                local key = "recipe:" .. relation.recipeID .. ":" .. definition.key
                if self:DetailGroupHeader(L(definition.titleKey), key, #group) then
                    for _, source in ipairs(group) do self:DetailLearningSource(source) end
                end
            end
        end
    end
    content:SetHeight(math.max(1, -self.detailCursorY + 10))
    self.frame.details.scroll:SetVerticalScroll(oldScroll)
end

function UI:ShowClassAbilityDetails(relation, preserveScroll)
    if not self.frame then return end
    local oldScroll = preserveScroll and self.frame.details.scroll:GetVerticalScroll() or 0
    self.detailSelection = { kind = "class_ability", relation = relation }
    self:ClearDetails()
    self:DetailLine(relation.name or L("class_ability"),
        "GameFontNormalLarge", COLORS.gold, 4, 8)
    self:DetailLine(L("class_ability_class", relation.className or L("unknown_class")),
        "GameFontHighlightSmall", COLORS.muted, 4, 8)

    local content = self.frame.details.content
    local tooltip = content.tooltip
    if not tooltip then
        tooltip = CreateFrame("GameTooltip", "ForeverpediaDetailTooltip", content,
            "GameTooltipTemplate")
        content.tooltip = tooltip
    end
    tooltip:ClearAllPoints()
    tooltip:SetOwner(content, "ANCHOR_NONE")
    tooltip:SetPoint("TOPLEFT", content, "TOPLEFT", 4, self.detailCursorY)
    local drawn = type(tooltip.SetSpellByID) == "function"
        and pcall(tooltip.SetSpellByID, tooltip, relation.spellID)
    if not drawn and type(tooltip.SetHyperlink) == "function" then
        drawn = pcall(tooltip.SetHyperlink, tooltip,
            "spell:" .. tostring(relation.spellID))
    end
    if not drawn then tooltip:AddLine(relation.name or L("class_ability")) end
    tooltip:Show()
    self.detailCursorY = self.detailCursorY - math.max(70, tooltip:GetHeight() or 0) - 12
    self:DetailLine(L("class_ability_consumes", relation.quantity or 1),
        "GameFontHighlight", COLORS.normal, 4, 8)
    content:SetHeight(math.max(1, -self.detailCursorY + 10))
    self.frame.details.scroll:SetVerticalScroll(oldScroll)
end

function UI:ShowSourceDetails(relation, preserveScroll)
    if relation.recipeID then
        self:ShowRecipeDetails(relation, preserveScroll)
        return
    end
    local oldScroll = preserveScroll and self.frame.details.scroll:GetVerticalScroll() or 0
    self.detailSelection = { kind = "source", relation = relation }
    self:ClearDetails()
    self:DetailLine(relation.name or L("source_section"), "GameFontNormalLarge", COLORS.gold, 4, 8)
    self:DetailLine(kindLabel(relation.kind) or L("source_section"),
        "GameFontHighlightSmall", COLORS.muted, 4, 10)
    self:DetailQuestMetadata(relation, 4)
    if relation.waterType then self:DetailLine(L("water_type", relation.waterType)) end
    if relation.chance then self:DetailLine(L("chance", relation.chance)) end
    if relation.minQuantity and relation.minQuantity > 0 then
        self:DetailLine(L("quantity", quantityText(relation)))
    end
    local locations = relation.locations or {}
    if #locations > 0 then
        local byZone, ordered = {}, {}
        for _, location in ipairs(locations) do
            local zone = location.zone or relation.zone or L("unknown_location")
            if not byZone[zone] then
                byZone[zone] = {}
                ordered[#ordered + 1] = zone
            end
            byZone[zone][#byZone[zone] + 1] = location
        end
        table.sort(ordered)
        for _, zone in ipairs(ordered) do
            local zoneLocations = byZone[zone]
            self:DetailLine(L("location", zone))
            local chances = {}
            for _, location in ipairs(zoneLocations) do
                if location.chance then chances[location.chance] = true end
            end
            local chanceCount, onlyChance = 0, nil
            for chance in pairs(chances) do chanceCount, onlyChance = chanceCount + 1, chance end
            if chanceCount == 1 and onlyChance ~= relation.chance then
                self:DetailLine(L("chance", onlyChance),
                    "GameFontHighlightSmall", COLORS.muted, 16, 5)
            end
            local coordinates = {}
            for _, location in ipairs(zoneLocations) do
                if type(location.x) == "number" and type(location.y) == "number" then
                    coordinates[#coordinates + 1] = location
                end
            end
            local limit = math.min(#coordinates, ns.Config.detailCoordinateLimit)
            for index = 1, limit do
                self:DetailCoordinateButton(coordinates[index], 16)
            end
            if #coordinates > limit then
                self:DetailLine(L("more_coordinates", #coordinates - limit),
                    "GameFontHighlightSmall", COLORS.muted, 16, 5)
            end
        end
    elseif relation.zone then
        self:DetailLine(L("location", relation.zone))
    end
    if relation.historical then
        self:DetailLine(L("classic_warning"),
            "GameFontHighlightSmall", COLORS.muted, 4, 8)
    end
    local content = self.frame.details.content
    content:SetHeight(math.max(1, -self.detailCursorY + 10))
    self.frame.details.scroll:SetVerticalScroll(oldScroll)
end

function UI:RefreshDetails(preserveScroll)
    local selection = self.detailSelection
    if not selection then return end
    if selection.kind == "recipe" then
        self:ShowRecipeDetails(selection.relation, preserveScroll)
    elseif selection.kind == "class_ability" then
        self:ShowClassAbilityDetails(selection.relation, preserveScroll)
    else
        self:ShowSourceDetails(selection.relation, preserveScroll)
    end
end

function UI:AcquireGroupButton()
    local content = self.frame.content
    local buttonIndex = (content.usedGroupButtons or 0) + 1
    content.usedGroupButtons = buttonIndex

    local button = content.groupButtons[buttonIndex]
    if not button then
        button = CreateFrame("Button", nil, content)
        button:SetHeight(22)

        local highlight = button:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetColorTexture(1, 0.78, 0.25, 0.08)

        local label = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("LEFT", 3, 0)
        label:SetPoint("RIGHT", -3, 0)
        label:SetJustifyH("LEFT")
        label:SetTextColor(unpack(COLORS.gold))
        button.label = label
        content.groupButtons[buttonIndex] = button
    end
    button:Show()
    button:ClearAllPoints()
    return button
end

function UI:IsGroupExpanded(key)
    local value = self.expandedGroups[key]
    if value == nil then
        return false
    end
    return value
end

function UI:AddGroupHeader(title, key, count, indent, icon)
    local content = self.frame.content
    local button = self:AcquireGroupButton()
    indent = indent or 10
    button:SetWidth(content:GetWidth() - indent - 8)
    button:SetPoint("TOPLEFT", content, "TOPLEFT", indent, self.cursorY)
    local expanded = self:IsGroupExpanded(key)
    local iconMarkup = icon and icon ~= 0 and string.format("|T%d:18:18:0:0|t ", icon) or ""
    button.label:SetText(string.format("%s  %s%s (%d)", expanded and "[-]" or "[+]",
        iconMarkup, title, count))
    button:SetScript("OnClick", function()
        UI.expandedGroups[key] = not UI:IsGroupExpanded(key)
        UI:Render()
    end)
    self.cursorY = self.cursorY - 25
    return expanded
end

function UI:AcquireRelationButton()
    local content = self.frame.content
    local buttonIndex = (content.usedRelationButtons or 0) + 1
    content.usedRelationButtons = buttonIndex
    local button = content.relationButtons[buttonIndex]
    if not button then
        button = CreateFrame("Button", nil, content)
        button:SetHeight(18)
        local highlight = button:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetColorTexture(1, 0.78, 0.25, 0.08)
        local label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        label:SetPoint("LEFT", 2, 0)
        label:SetPoint("RIGHT", -2, 0)
        label:SetJustifyH("LEFT")
        button.label = label
        content.relationButtons[buttonIndex] = button
    end
    button.fpGamepadRecipe = nil
    button:Show()
    button:ClearAllPoints()
    return button
end

local function showRelationTooltip(owner, relation, tooltipKind)
    UI.itemTooltipOwner = nil
    UI.itemTooltipItemID = nil
    UI.itemTooltipAddLines = nil
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    local drawn = false
    local hasMissingIngredient = false
    if tooltipKind == "spell" then
        for _, ingredient in ipairs(relation.ingredients or {}) do
            local ingredientID = ingredient.itemID or ingredient[1]
            if ingredientID and UI.failedItemLoads[ingredientID] then
                hasMissingIngredient = true
                break
            end
        end
    end
    if tooltipKind == "spell" and hasMissingIngredient then
        GameTooltip:ClearLines()
        GameTooltip:AddLine(relation.name or L("recipe"),
            COLORS.gold[1], COLORS.gold[2], COLORS.gold[3])
        if relation.professionName then
            GameTooltip:AddLine(L("profession_prefix", relation.professionName),
                COLORS.muted[1], COLORS.muted[2], COLORS.muted[3])
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L("ingredients"),
            COLORS.gold[1], COLORS.gold[2], COLORS.gold[3])
        for _, ingredient in ipairs(relation.ingredients or {}) do
            local ingredientID = ingredient.itemID or ingredient[1]
            local quantity = ingredient.quantity or ingredient[2] or 1
            local icon = getItemIcon(ingredientID)
            local iconMarkup = icon and string.format("|T%d:16:16:0:0|t ", icon) or ""
            GameTooltip:AddLine(iconMarkup .. itemDisplayName(ingredientID)
                .. " ×" .. tostring(quantity), 0.92, 0.88, 0.78)
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L("client_item_data_incomplete"), 1, 0.28, 0.28, true)
        drawn = true
    elseif tooltipKind == "spell" or tooltipKind == "class_spell" then
        local spellID = relation.spellID or relation.recipeID
        drawn = type(GameTooltip.SetSpellByID) == "function"
            and pcall(GameTooltip.SetSpellByID, GameTooltip, spellID)
        if not drawn and type(GameTooltip.SetHyperlink) == "function" then
            drawn = pcall(GameTooltip.SetHyperlink, GameTooltip,
                "spell:" .. tostring(spellID))
        end
    elseif tooltipKind == "quest" then
        if type(GameTooltip.SetHyperlink) == "function" then
            drawn = pcall(GameTooltip.SetHyperlink, GameTooltip,
                "quest:" .. tostring(relation.questID))
        end
        if not drawn then
            GameTooltip:AddLine(relation.name or L("quest"))
            local level = QuestDB and QuestDB.questLevel and QuestDB.questLevel(relation.questID)
            if level and level > 0 then
                GameTooltip:AddLine(L("quest_level", level), 0.72, 0.72, 0.72)
            end
            local objectives = QuestDB and QuestDB.objectivesText
                and QuestDB.objectivesText(relation.questID)
            for _, objective in ipairs(objectives or {}) do
                GameTooltip:AddLine(objective, 0.9, 0.85, 0.72, true)
            end
        end
    end
    if not drawn and (tooltipKind == "spell" or tooltipKind == "class_spell") then
        local fallback = tooltipKind == "class_spell" and L("class_ability") or L("recipe")
        GameTooltip:AddLine(relation.name or fallback)
    end
    if tooltipKind == "class_spell" then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L("class_ability_class",
            relation.className or L("unknown_class")),
            COLORS.muted[1], COLORS.muted[2], COLORS.muted[3])
        GameTooltip:AddLine(L("class_ability_consumes", relation.quantity or 1),
            COLORS.normal[1], COLORS.normal[2], COLORS.normal[3])
    end
    if tooltipKind == "spell" and relation.outputItemID then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L("alt_result"),
            0.95, 0.72, 0.27)
    end
    GameTooltip:Show()
end

function UI:AddInteractiveRelation(relation, indent, tooltipKind)
    local content = self.frame.content
    local button = self:AcquireRelationButton()
    button:SetWidth(content:GetWidth() - indent - 8)
    button:SetPoint("TOPLEFT", content, "TOPLEFT", indent, self.cursorY)
    button.fpGamepadRecipe = tooltipKind == "spell" and relation or nil
    button.label:SetText(relation.displayName or relation.name or L("recipe"))
    button:SetScript("OnEnter", function(self)
        showRelationTooltip(self, relation, tooltipKind)
    end)
    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    button:SetScript("OnClick", function(_, mouseButton)
        if tooltipKind == "spell" then
            if mouseButton == "LeftButton" and relation.outputItemID
                    and relation.outputItemID ~= UI.currentItemID
                    and IsAltKeyDown and IsAltKeyDown() then
                GameTooltip:Hide()
                UI:OpenItem("item:" .. tostring(relation.outputItemID), relation.outputItemID)
                return
            end
            UI:ShowRecipeDetails(relation)
        elseif tooltipKind == "class_spell" then
            GameTooltip:Hide()
            UI:ShowClassAbilityDetails(relation)
        elseif tooltipKind == "quest" then
            GameTooltip:Hide()
            UI:ShowSourceDetails(relation)
        end
    end)
    self.cursorY = self.cursorY - 21
    self.cursorY = self.cursorY - 3
end

quantityText = function(relation)
    local minimum = relation.minQuantity or relation.quantity
    if not minimum or minimum <= 0 then
        return L("unknown")
    end
    local maximum = relation.maxQuantity or minimum
    if minimum == maximum then
        return "×" .. minimum
    end
    return string.format("×%d–%d", minimum, maximum)
end

function UI:AddSourceRelation(relation, indent, locationInHeader)
    indent = indent or 26
    local text
    if relation.kind == "drop" or relation.kind == "pickpocket" then
        text = L("drop_row",
            relation.name or L("source_unknown"), relation.chance or L("unknown_chance"))
        if not locationInHeader then
            text = text .. "  •  "
                .. (sourceGeneralZones(relation)[1] or L("unknown_location"))
        end
    else
        text = relation.name or L("unnamed")
        local zones = sourceGeneralZones(relation)
        if #zones == 1 then
            text = text .. "  •  " .. zones[1]
        elseif #zones > 1 then
            text = text .. "  •  " .. L("locations_count", #zones)
        end
    end
    local content = self.frame.content
    local button = self:AcquireRelationButton()
    button:SetWidth(content:GetWidth() - indent - 8)
    button:SetPoint("TOPLEFT", content, "TOPLEFT", indent, self.cursorY)
    button.label:SetText(text)
    button:SetScript("OnEnter", nil)
    button:SetScript("OnLeave", nil)
    button:SetScript("OnClick", function()
        UI:ShowSourceDetails(relation)
    end)
    self.cursorY = self.cursorY - 23
end

function UI:AddFishingRelations(relations)
    local grouped, ordered = {}, {}
    for _, relation in ipairs(relations) do
        local generalZone = sourceGeneralZones(relation)[1]
            or relation.zone or L("unknown_location")
        local key = ns.Util.Key(relation.name, generalZone, relation.entityID)
        local combined = grouped[key]
        if not combined then
            combined = {}
            for field, value in pairs(relation) do combined[field] = value end
            combined.zone = generalZone
            combined.areaID = nil
            combined.chance = nil
            combined.locations = {}
            combined.locationKeys = {}
            grouped[key] = combined
            ordered[#ordered + 1] = combined
        end
        local locations = relation.locations
        if not locations or #locations == 0 then
            locations = { {
                areaID = relation.areaID,
                zone = relation.zone,
            } }
        end
        for _, location in ipairs(locations) do
            local copy = {}
            for field, value in pairs(location) do copy[field] = value end
            copy.chance = copy.chance or relation.chance
            local locationKey = ns.Util.Key(copy.areaID, copy.zone, copy.x, copy.y)
            if not combined.locationKeys[locationKey] then
                combined.locations[#combined.locations + 1] = copy
                combined.locationKeys[locationKey] = true
            end
        end
    end
    table.sort(ordered, function(left, right)
        if left.zone == right.zone then return (left.name or "") < (right.name or "") end
        return (left.zone or "") < (right.zone or "")
    end)
    for _, relation in ipairs(ordered) do
        relation.locationKeys = nil
        self:AddSourceRelation(relation, 28)
    end
end

function UI:AddCraftSourceGroups(relations, groupKey)
    local professions = {}
    for _, relation in ipairs(relations) do
        local professionID = relation.professionID or 0
        local profession = professions[professionID]
        if not profession then
            profession = {
                id = professionID,
                name = relation.professionName or L("unknown_profession"),
                icon = relation.professionIcon,
                relations = {},
            }
            professions[professionID] = profession
        end
        profession.relations[#profession.relations + 1] = relation
    end
    local ordered = {}
    for _, profession in pairs(professions) do ordered[#ordered + 1] = profession end
    table.sort(ordered, function(left, right) return left.name < right.name end)
    for _, profession in ipairs(ordered) do
        local professionKey = groupKey .. ":" .. profession.id
        if self:AddGroupHeader(profession.name, professionKey, #profession.relations, 10,
                profession.icon) then
            for _, relation in ipairs(profession.relations) do
                self:AddSourceRelation(relation, 28)
            end
        end
    end
end

function UI:AddRelation(relation, indent)
    indent = indent or 26
    local kind = kindLabel(relation.kind) or L("other")
    local prefix = relation.kind == "starts_quest" and (kind .. ": ") or ""
    self:AddLine(prefix .. (relation.name or L("unnamed")),
        "GameFontHighlight", nil, indent, 3)

    if relation.detail and relation.detail ~= "" then
        self:AddLine(relation.detail, "GameFontHighlightSmall", COLORS.normal, indent + 14, 3)
    end
    if relation.zone and relation.zone ~= "" then
        self:AddLine(L("zone", relation.zone), "GameFontHighlightSmall", COLORS.muted,
            indent + 14, 3)
    end
    if relation.chance then
        self:AddLine(L("chance", relation.chance), "GameFontHighlightSmall", COLORS.muted,
            indent + 14, 3)
    end
    self.cursorY = self.cursorY - 7
end

function UI:AddDropRelations(relations, groupKey)
    local byZone = {}
    for _, relation in ipairs(relations) do
        local zone = sourceGeneralZones(relation)[1] or L("unknown_location")
        byZone[zone] = byZone[zone] or {}
        byZone[zone][#byZone[zone] + 1] = relation
    end
    local zones = {}
    for zone, entries in pairs(byZone) do
        zones[#zones + 1] = { name = zone, relations = entries }
    end
    table.sort(zones, function(left, right)
        if left.name == L("unknown_location") then
            return false
        end
        if right.name == L("unknown_location") then
            return true
        end
        return left.name < right.name
    end)
    for _, zone in ipairs(zones) do
        local zoneKey = groupKey .. ":zone:" .. zone.name
        if self:AddGroupHeader(zone.name, zoneKey, #zone.relations, 24) then
            for _, relation in ipairs(zone.relations) do
                self:AddSourceRelation(relation, 42, true)
            end
        end
    end
end

local function partitionRelations(relations, definitions)
    local groups = {}
    local assigned = {}
    for _, definition in ipairs(definitions) do
        local group = { definition = definition, relations = {} }
        for index, relation in ipairs(relations or {}) do
            if definition.kinds[relation.kind] then
                group.relations[#group.relations + 1] = relation
                assigned[index] = true
            end
        end
        if #group.relations > 0 then
            groups[#groups + 1] = group
        end
    end

    local other = {}
    for index, relation in ipairs(relations or {}) do
        if not assigned[index] then
            other[#other + 1] = relation
        end
    end
    if #other > 0 then
        groups[#groups + 1] = {
            definition = { key = "other", title = L("other") },
            relations = other,
        }
    end
    return groups
end

function UI:AddProfessionRelations(relations, groupKey)
    local professions = {}
    for _, relation in ipairs(relations) do
        local professionID = relation.professionID or 0
        local profession = professions[professionID]
        if not profession then
            profession = {
                id = professionID,
                name = relation.professionName or L("unknown_profession"),
                icon = relation.professionIcon,
                relations = {},
            }
            professions[professionID] = profession
        end
        profession.relations[#profession.relations + 1] = relation
    end

    local ordered = {}
    for _, profession in pairs(professions) do
        ordered[#ordered + 1] = profession
    end
    table.sort(ordered, function(left, right)
        return left.name < right.name
    end)

    for _, profession in ipairs(ordered) do
        local professionKey = groupKey .. ":" .. profession.id
        if self:AddGroupHeader(profession.name, professionKey, #profession.relations, 24,
            profession.icon) then
            for _, relation in ipairs(profession.relations) do
                self:AddInteractiveRelation(relation, 42, "spell")
            end
        end
    end
end

function UI:AddClassAbilityRelations(relations, groupKey)
    local classes = {}
    for _, relation in ipairs(relations) do
        local classMask = relation.classMask or 0
        local class = classes[classMask]
        if not class then
            class = {
                mask = classMask,
                name = relation.className or L("unknown_class"),
                relationsByName = {},
            }
            classes[classMask] = class
        end
        local relationKey = (relation.name or tostring(relation.spellID))
            .. ":" .. tostring(relation.quantity or 1)
        local current = class.relationsByName[relationKey]
        if not current or (relation.spellID or 0) > (current.spellID or 0) then
            class.relationsByName[relationKey] = relation
        end
    end

    local ordered = {}
    for _, class in pairs(classes) do
        class.relations = {}
        for _, relation in pairs(class.relationsByName) do
            class.relations[#class.relations + 1] = relation
        end
        table.sort(class.relations, function(left, right)
            if left.name == right.name then
                return (left.quantity or 1) < (right.quantity or 1)
            end
            return (left.name or "") < (right.name or "")
        end)
        ordered[#ordered + 1] = class
    end
    table.sort(ordered, function(left, right) return left.name < right.name end)

    for _, class in ipairs(ordered) do
        local classKey = groupKey .. ":" .. class.mask
        if self:AddGroupHeader(class.name, classKey, #class.relations, 24) then
            for _, relation in ipairs(class.relations) do
                self:AddInteractiveRelation(relation, 42, "class_spell")
            end
        end
    end
end

function UI:AddCategorizedSection(relations, emptyText, definitions, sectionKey)
    if not relations or #relations == 0 then
        self:AddLine(emptyText, "GameFontHighlight", COLORS.muted, 14, 16)
        return
    end

    for _, group in ipairs(partitionRelations(relations, definitions)) do
        local groupKey = sectionKey .. ":" .. group.definition.key
        if sectionKey == "sources" and group.definition.key == "craft" then
            self:AddCraftSourceGroups(group.relations, groupKey)
        elseif self:AddGroupHeader(group.definition.titleKey and L(group.definition.titleKey)
                or group.definition.title, groupKey, #group.relations, 10) then
            if group.definition.key == "profession" then
                self:AddProfessionRelations(group.relations, groupKey)
            elseif group.definition.key == "class_ability" then
                self:AddClassAbilityRelations(group.relations, groupKey)
            elseif sectionKey == "sources" and group.definition.key == "fishing" then
                self:AddFishingRelations(group.relations)
            elseif sectionKey == "sources"
                    and (group.definition.key == "drop"
                        or group.definition.key == "pickpocket") then
                self:AddDropRelations(group.relations, groupKey)
            else
                for _, relation in ipairs(group.relations) do
                    if sectionKey == "sources" then
                        self:AddSourceRelation(relation, 28)
                    elseif (relation.kind == "quest" or relation.kind == "starts_quest")
                        and relation.questID then
                        self:AddInteractiveRelation(relation, 28, "quest")
                    else
                        self:AddRelation(relation, 28)
                    end
                end
            end
        end
    end
end

function UI:UpdateTabs()
    if not self.frame then
        return
    end

    for key, button in pairs(self.frame.tabButtons) do
        if key == self.activeTab then
            button.label:SetTextColor(unpack(COLORS.gold))
            button.underline:Show()
        else
            button.label:SetTextColor(unpack(COLORS.muted))
            button.underline:Hide()
        end
    end
end

function UI:UpdateCraftTreeButton()
    if not (self.frame and self.frame.craftTreeButton) then return end
    local visible = ns.CraftTree and ns.CraftTree:IsAvailable(self.currentItemID)
    self.frame.craftTreeButton:SetShown(visible == true)
end

function UI:FindItems(query, limit)
    return ns.Search:Find(query, limit)
end

function UI:RefreshSearchSelection()
    local suggestions = self.frame and self.frame.searchSuggestions
    if not suggestions then return end
    for index, button in ipairs(suggestions.buttons) do
        if button:IsShown() and index == self.searchSelection then
            button:LockHighlight()
        else
            button:UnlockHighlight()
        end
    end
end

function UI:UpdateSearchSuggestions()
    local frame = self.frame
    if not frame then return end
    local query = frame.searchBox:GetText()
    self.searchResults = self:FindItems(query, ns.Config.searchResultLimit)
    self.searchSelection = #self.searchResults > 0 and 1 or 0
    for index, button in ipairs(frame.searchSuggestions.buttons) do
        local result = self.searchResults[index]
        button.result = result
        if result then
            button.label:SetText(L("search_result", result.name, result.itemID))
            button:Show()
        else
            button:Hide()
        end
    end
    if #self.searchResults > 0 and ns.Search:Normalize(query) ~= "" then
        frame.searchSuggestions:SetHeight(#self.searchResults * 24 + 10)
        frame.searchSuggestions:Show()
        self:RefreshSearchSelection()
    else
        frame.searchSuggestions:Hide()
    end
end

function UI:ScheduleSearch()
    self.searchToken = (self.searchToken or 0) + 1
    local token = self.searchToken
    local run = function()
        if token == UI.searchToken then UI:UpdateSearchSuggestions() end
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(ns.Config.searchDelay, run)
    else
        run()
    end
end

function UI:MoveSearchSelection(delta)
    if #self.searchResults == 0 then return end
    self.searchSelection = math.max(1, math.min(#self.searchResults,
        (self.searchSelection or 1) + delta))
    self:RefreshSearchSelection()
end

function UI:OpenSearchResult(result)
    if not result then return end
    if self.frame and self.frame.searchBox then self.frame.searchBox:ClearFocus() end
    if self.frame and self.frame.searchSuggestions then self.frame.searchSuggestions:Hide() end
    self:OpenItem("item:" .. result.itemID, result.itemID)
end

function UI:ActivateSearchSuggestion()
    self:OpenSearchResult(self.searchResults[self.searchSelection or 1])
end

function UI:ClearSearch()
    if not self.frame then return end
    self.suppressSearch = true
    self.frame.searchBox:SetText("")
    self.suppressSearch = false
    self.frame.searchBox:ClearFocus()
    self.frame.searchBox.placeholder:Show()
    self.frame.searchSuggestions:Hide()
    self.searchResults = {}
    self.searchSelection = 0
end

function UI:UpdateBackButton()
    if not self.frame or not self.frame.backButton then return end
    if #self.history > 0 then
        self.frame.backButton:Enable()
    else
        self.frame.backButton:Disable()
    end
end

function UI:GoBack()
    local previous = table.remove(self.history)
    if not previous then return end
    self:OpenItem(previous.itemLink or ("item:" .. previous.itemID), previous.itemID, {
        fromHistory = true,
        tab = previous.tab,
        expandedGroups = previous.expandedGroups,
        detailExpanded = previous.detailExpanded,
        detailSelection = previous.detailSelection,
        scroll = previous.scroll,
        detailScroll = previous.detailScroll,
    })
end

function UI:SetTab(tab)
    self.activeTab = tab
    self:UpdateTabs()
    if self.frame then
        self.frame.scroll:SetVerticalScroll(0)
    end
    self:Render()
end

function UI:Render()
    if not self.frame or not self.currentItemID then
        return
    end

    local itemInfo = getItemInfo(self.currentItemLink)
        or getItemInfo(self.currentItemID)
    local record = ns.DataProvider:Get(self.currentItemID)
    local manifest = ns.DataProvider:GetManifest()
    self:UpdateCraftTreeButton()

    if itemInfo then
        self.currentItemLink = itemInfo.link or self.currentItemLink
        self.frame.itemIcon:SetTexture(getItemIcon(self.currentItemID, itemInfo) or 134400)
        self.frame.itemName:SetText(itemDisplayName(self.currentItemID))
        self.frame.itemName:SetTextColor(getQualityColor(itemInfo.quality))

        local metadata = {}
        if itemInfo.itemType and itemInfo.itemType ~= "" then
            metadata[#metadata + 1] = itemInfo.itemType
        end
        if itemInfo.itemSubType and itemInfo.itemSubType ~= "" then
            metadata[#metadata + 1] = itemInfo.itemSubType
        end
        if itemInfo.itemLevel and itemInfo.itemLevel > 0 then
            metadata[#metadata + 1] = L("item_level", itemInfo.itemLevel)
        end
        self.frame.itemMeta:SetText(table.concat(metadata, "  •  "))
    else
        self.frame.itemIcon:SetTexture(getItemIcon(self.currentItemID) or 134400)
        self.frame.itemName:SetText(L("item_number", self.currentItemID))
        self.frame.itemName:SetTextColor(unpack(COLORS.gold))
        if self.failedItemLoads[self.currentItemID] then
            self.frame.itemMeta:SetText(L("item_not_found"))
        else
            self.frame.itemMeta:SetText(L("loading_item"))
        end
    end

    self:ClearLines()

    if self.activeTab == "uses" then
        self:AddCategorizedSection(record.uses,
            L("no_uses"),
            USE_GROUPS, "uses")
    elseif self.activeTab == "sources" then
        self:AddCategorizedSection(record.sources,
            L("no_sources"),
            SOURCE_GROUPS, "sources")
    end

    local contentHeight = math.max(1, -self.cursorY + 10)
    self.frame.content:SetHeight(contentHeight)
    self.frame.footer:SetText(string.format(
        L("footer"),
        self.currentItemID,
        manifest.dataset or L("unknown"),
        #record.sources,
        #record.uses
    ))
end

function UI:OpenItem(itemLink, itemID, options)
    options = options or {}
    local frame = self:CreateFrame()
    reopenAfterMap = false
    if not options.fromHistory and self.currentItemID and self.currentItemID ~= itemID then
        self.history[#self.history + 1] = {
            itemID = self.currentItemID,
            itemLink = self.currentItemLink,
            tab = self.activeTab,
            expandedGroups = self.expandedGroups,
            detailExpanded = self.detailExpanded,
            detailSelection = self.detailSelection,
            scroll = frame.scroll:GetVerticalScroll(),
            detailScroll = frame.details.scroll:GetVerticalScroll(),
        }
        if #self.history > ns.Config.historyLimit then table.remove(self.history, 1) end
    end
    self.currentItemLink = itemLink
    self.currentItemID = itemID
    self.activeTab = options.tab or "uses"
    self.expandedGroups = options.expandedGroups or {}
    self.detailExpanded = options.detailExpanded or {}
    self.detailSelection = options.detailSelection
    self:ClearSearch()
    self:UpdateBackButton()
    self:UpdateTabs()
    self:Render()
    frame.scroll:SetVerticalScroll(options.scroll or 0)
    if self.detailSelection then
        self:RefreshDetails()
        frame.details.scroll:SetVerticalScroll(options.detailScroll or 0)
    else
        self:ClearDetails()
        self:DetailLine(L("choose_detail"),
            "GameFontHighlight", COLORS.muted, 8, 8)
        frame.details.content:SetHeight(math.max(1, -self.detailCursorY + 10))
    end
    frame:Show()
    frame:Raise()
    if ns.Gamepad and ns.Gamepad.OnWindowOpened then
        ns.Gamepad:OnWindowOpened()
    end

    if Item and Item.CreateFromItemLink then
        local item = Item:CreateFromItemLink(itemLink)
        local ok = pcall(function()
            item:ContinueOnItemLoad(function()
                if UI.currentItemID == itemID then
                    UI.currentItemLink = item:GetItemLink() or UI.currentItemLink
                    UI:Render()
                end
            end)
        end)
        if ok then
            return
        end
    end

    if C_Item and C_Item.RequestLoadItemDataByID then
        C_Item.RequestLoadItemDataByID(itemID)
    end
end

function UI:OpenSearch()
    local frame = self:CreateFrame()
    reopenAfterMap = false
    frame:Show()
    frame:Raise()
    frame.searchBox:SetFocus()
    if frame.searchBox.HighlightText then frame.searchBox:HighlightText() end
    if ns.Gamepad and ns.Gamepad.OnWindowOpened then
        ns.Gamepad:OnWindowOpened()
    end
end

