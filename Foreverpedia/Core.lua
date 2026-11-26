local addonName, ns = ...
local L = ns.L

local eventFrame = CreateFrame("Frame")
local professionClickFrame = CreateFrame("Frame")
local lastModifiedItemID, lastModifiedOpenTime
local tooltipHintState = setmetatable({}, { __mode = "k" })

local function isItemLink(value)
    return type(value) == "string" and value:find("|Hitem:", 1, true) ~= nil
end

local function openItem(itemInfo, modifiedClick)
    local itemID = ns.DataProvider:GetItemID(itemInfo)
    if not itemID then
        print("|cffd9a441Foreverpedia:|r " .. L("core_item_id_error"))
        return
    end

    if modifiedClick and GetTime then
        local now = GetTime()
        if lastModifiedItemID == itemID and lastModifiedOpenTime
                and now - lastModifiedOpenTime < ns.Config.modifiedClickDebounce then
            return
        end
        lastModifiedItemID, lastModifiedOpenTime = itemID, now
    end

    local itemLink = itemInfo
    if type(itemLink) ~= "string" or not isItemLink(itemLink) then
        itemLink = "item:" .. itemID
    end

    ns.UI:OpenItem(itemLink, itemID)
end

local function deferItemOpen(link, modifiedClick)
    local callback = function() openItem(link, modifiedClick) end
    if C_Timer and type(C_Timer.After) == "function" then
        local ok = pcall(C_Timer.After, 0, callback)
        if ok then return end
    end
    callback()
end

local function installModifiedClickHook()
    if ns.modifiedClickHookInstalled then
        return
    end

    if type(HandleModifiedItemClick) ~= "function" or type(hooksecurefunc) ~= "function" then
        print("|cffd9a441Foreverpedia:|r " .. L("core_click_hook_unavailable"))
        return
    end

    hooksecurefunc("HandleModifiedItemClick", function(link)
        if IsAltKeyDown and IsAltKeyDown() and isItemLink(link) then
            deferItemOpen(link, true)
        end
    end)

    -- Chat hyperlinks can bypass HandleModifiedItemClick when Alt has no native action.
    if type(SetItemRef) == "function" then
        hooksecurefunc("SetItemRef", function(link, text, button)
            if button == "LeftButton" and IsAltKeyDown and IsAltKeyDown()
                    and type(link) == "string" and link:match("^item:%d+") then
                local fullLink = type(text) == "string" and text:find("|H" .. link .. "|h", 1, true)
                deferItemOpen(fullLink and text or link, true)
            end
        end)
    end
    ns.modifiedClickHookInstalled = true
end

local function addItemTooltipHint(tooltip)
    if not (tooltip and tooltip.GetItem and tooltip.AddLine) then return end
    local ok, _, link = pcall(tooltip.GetItem, tooltip)
    if not ok or not isItemLink(link) then return end

    local gamepadLayout = ns.Gamepad and ns.Gamepad.IsLayoutActive
        and ns.Gamepad:IsLayoutActive()
    local hintKey = gamepadLayout and "gamepad_tooltip_open" or "alt_open"
    local hintText = L(hintKey)
    local lineCount = tooltip.NumLines and tooltip:NumLines() or 0
    local previous = tooltipHintState[tooltip]
    if previous and previous.link == link and lineCount >= previous.line then
        if previous.key ~= hintKey then
            local tooltipName = tooltip.GetName and tooltip:GetName()
            local fontString = tooltipName
                and rawget(_G, tooltipName .. "TextLeft" .. previous.line)
            if fontString and fontString.SetText then
                fontString:SetText(hintText)
                previous.key = hintKey
                if tooltip.Show then tooltip:Show() end
            end
        end
        return
    end

    tooltip:AddLine(hintText, 0.62, 0.59, 0.53, true)
    local hintLine = tooltip.NumLines and tooltip:NumLines() or lineCount + 1
    local tooltipName = tooltip.GetName and tooltip:GetName()
    local fontString = tooltipName and rawget(_G, tooltipName .. "TextLeft" .. hintLine)
    if fontString and fontString.SetFontObject and rawget(_G, "GameFontDisableSmall") then
        fontString:SetFontObject(GameFontDisableSmall)
    end
    tooltipHintState[tooltip] = { link = link, line = hintLine, key = hintKey }
    if tooltip.Show then tooltip:Show() end
end

local function refreshVisibleTooltipHints()
    for tooltip in pairs(tooltipHintState) do
        if tooltip.IsShown and tooltip:IsShown() then addItemTooltipHint(tooltip) end
    end
end

local function installItemTooltipHints()
    if ns.itemTooltipHintsInstalled then return end

    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall
            and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item then
        TooltipDataProcessor.AddTooltipPostCall(
            Enum.TooltipDataType.Item,
            function(tooltip) addItemTooltipHint(tooltip) end
        )
        ns.itemTooltipHintsInstalled = true
        return
    end

    local installed = false
    for _, name in ipairs({
        "GameTooltip", "ItemRefTooltip", "ShoppingTooltip1", "ShoppingTooltip2",
    }) do
        local tooltip = rawget(_G, name)
        if tooltip and tooltip.HookScript then
            local ok = pcall(tooltip.HookScript, tooltip, "OnTooltipSetItem",
                function(current) addItemTooltipHint(current) end)
            if ok then
                installed = true
                pcall(tooltip.HookScript, tooltip, "OnTooltipCleared", function(current)
                    tooltipHintState[current] = nil
                end)
            end
        end
    end
    ns.itemTooltipHintsInstalled = installed
end

local function isProfessionFrameOwner(owner)
    local rootNames = { "TradeSkillFrame", "CraftFrame", "ProfessionsFrame" }
    local current = owner
    for _ = 1, 16 do
        if not current then return false end
        for _, name in ipairs(rootNames) do
            local root = rawget(_G, name)
            if root and current == root then return true end
        end
        if type(current.GetParent) ~= "function" then return false end
        local ok, parent = pcall(current.GetParent, current)
        if not ok or parent == current then return false end
        current = parent
    end
    return false
end

local function hoveredProfessionReagentLink()
    local tooltip = GameTooltip
    if not (tooltip and tooltip.IsShown and tooltip:IsShown()
            and tooltip.GetItem and tooltip.GetOwner) then
        return nil
    end

    local owner = tooltip:GetOwner()
    if not owner then return nil end
    if owner.IsMouseOver and not owner:IsMouseOver() then return nil end
    if not isProfessionFrameOwner(owner) then return nil end

    local ok, _, link = pcall(tooltip.GetItem, tooltip)
    if ok and isItemLink(link) then return link end
    return nil
end

local function installProfessionReagentClickWatcher()
    if ns.professionClickWatcherInstalled then return end
    local ok, registered = pcall(
        professionClickFrame.RegisterEvent, professionClickFrame, "GLOBAL_MOUSE_DOWN"
    )
    if not ok or registered == false then return end

    professionClickFrame:SetScript("OnEvent", function(_, event, button)
        if event ~= "GLOBAL_MOUSE_DOWN" or button ~= "LeftButton"
                or not (IsAltKeyDown and IsAltKeyDown()) then
            return
        end
        local link = hoveredProfessionReagentLink()
        if link then deferItemOpen(link, true) end
    end)
    ns.professionClickWatcherInstalled = true
end

local function handleSlashCommand(message)
    local argument = ns.Util.Trim(message)
    if argument == "" then
        ns.UI:OpenSearch()
        return
    end

    if argument == "help" then
        print("|cffd9a441Foreverpedia:|r " .. L("core_help"))
        return
    end

    if argument == "status" then
        local status = ns.DataProvider:GetStatus()
        print(string.format(
            "|cffd9a441Foreverpedia:|r " .. L("core_status"),
            tostring(select(4, GetBuildInfo())),
            status.version or L("not_installed"),
            status.contractVersion or "?",
            status.recipeVersion or L("unknown_version"),
            status.dropTableAvailable and L("yes") or L("no"),
            ns.Storage:CountObservations(),
            status.cachedItems or 0
        ))
        return
    end

    local itemID = tonumber(argument) or tonumber(argument:match("item:(%d+)"))
    if itemID then
        openItem(itemID)
    else
        print("|cffd9a441Foreverpedia:|r " .. L("core_expected_item"))
    end
end

eventFrame:RegisterEvent("ADDON_LOADED")
pcall(eventFrame.RegisterEvent, eventFrame, "INPUT_DEVICE_INTERFACE_STYLE_CHANGED")
eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "INPUT_DEVICE_INTERFACE_STYLE_CHANGED" then
        refreshVisibleTooltipHints()
        if ns.Gamepad and ns.Gamepad.OnInputStyleChanged then
            ns.Gamepad:OnInputStyleChanged()
        end
        return
    end
    if event ~= "ADDON_LOADED" then
        return
    end

    local loadedAddon = ...
    if loadedAddon ~= addonName then return end

    ns.Storage:Initialize()

    if ns.VersionExchange and ns.VersionExchange.Initialize then
        ns.VersionExchange:Initialize()
    end

    local compatible, message = ns.DataProvider:Initialize()
    if not compatible then
        print("|cffff4040Foreverpedia:|r " .. (message or L("core_incompatible")))
        return
    end

    local interfaceVersion = select(4, GetBuildInfo())
    if interfaceVersion ~= ns.Config.interface then
        print(string.format(
            "|cffffa040Foreverpedia:|r " .. L("core_interface_warning"),
            ns.Config.interface,
            tostring(interfaceVersion)
        ))
    end

    local clientBuild = GetBuildInfo and select(2, GetBuildInfo())
    local dataBuild = ns.RecipeData and ns.RecipeData.manifest
        and ns.RecipeData.manifest.version
    local dataBuildNumber = dataBuild and dataBuild:match("(%d+)$")
    if clientBuild and dataBuildNumber and tostring(clientBuild) ~= dataBuildNumber then
        print(string.format(
            "|cffffa040Foreverpedia:|r " .. L("core_data_build_warning"),
            tostring(clientBuild),
            tostring(dataBuild)
        ))
    end

    installModifiedClickHook()
    installProfessionReagentClickWatcher()
    installItemTooltipHints()

    if ns.Settings and ns.Settings.Initialize then ns.Settings:Initialize() end
    if ns.MinimapButton and ns.MinimapButton.Initialize then
        ns.MinimapButton:Initialize()
    end

    SLASH_FOREVERPEDIA1 = "/foreverpedia"
    SLASH_FOREVERPEDIA2 = "/fp"
    SlashCmdList.FOREVERPEDIA = handleSlashCommand
end)

