local _, ns = ...
local CreateFrame = ns.CreateDetachedFrame or CreateFrame

local Gamepad = {}
ns.Gamepad = Gamepad

local lastTooltipItem
local hold
local pendingNativeTap
local wasDown = false
local progressFrame
local SEGMENT_COUNT = 16
local R3_KEY = _G.GAMEPAD_STICK_RIGHT_PRESS or "PADRSTICK"

function Gamepad:IsLayoutActive()
    return C_InputInterfaceStyle and C_InputInterfaceStyle.GetCurrentStyle
        and Enum and Enum.InputDeviceInterfaceType
        and C_InputInterfaceStyle.GetCurrentStyle()
            == Enum.InputDeviceInterfaceType.Gamepad or false
end

local function itemID(value)
    if type(value) == "number" then return value end
    if type(value) ~= "string" then return nil end
    return tonumber(value) or tonumber(value:match("item:(%d+)"))
end

local function rememberTooltip(tooltip, data)
    if tooltip ~= GameTooltip or not tooltip.GetItem then return end
    local ok, _, link = pcall(tooltip.GetItem, tooltip)
    local value = ok and link or nil
    value = value or (data and data.id)
    if itemID(value) then
        local owner = tooltip.GetOwner and tooltip:GetOwner()
        lastTooltipItem = { value = value, at = GetTime(), owner = owner }
    end
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall
        and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, rememberTooltip)
elseif GameTooltip and GameTooltip.HookScript then
    pcall(GameTooltip.HookScript, GameTooltip, "OnTooltipSetItem", rememberTooltip)
end

local function methodResult(object, name)
    local method = object and object[name]
    if type(method) ~= "function" then return nil end
    local ok, value = pcall(method, object)
    return ok and value or nil
end

local function dataItem(data, depth, seen)
    if type(data) ~= "table" and type(data) ~= "userdata" then return nil end
    depth = depth or 0
    if depth > 4 then return nil end
    seen = seen or {}
    if seen[data] then return nil end
    seen[data] = true

    for _, name in ipairs({ "GetItemLink", "GetHyperlink" }) do
        local value = methodResult(data, name)
        if itemID(value) then return value end
    end
    local value = methodResult(data, "GetItemID")
    if itemID(value) then return value end

    for _, key in ipairs({ "itemLink", "hyperlink", "link" }) do
        value = data[key]
        if itemID(value) then return value end
    end
    for _, key in ipairs({ "itemID", "itemId" }) do
        value = data[key]
        if type(value) == "number" and value > 0 then return value end
    end

    for _, key in ipairs({
        "item", "itemInfo", "reagent", "reagentInfo", "selectedReagent",
        "reagentSlotSchematic", "slotInfo", "elementData", "data",
    }) do
        value = data[key]
        local found = value and dataItem(value, depth + 1, seen)
        if found then return found end
    end

    local reagents = data.reagents
    if type(reagents) == "table" then
        for _, reagent in ipairs(reagents) do
            local found = dataItem(reagent, depth + 1, seen)
            if found then return found end
        end
    end
end

local function reagentContext(frame, data)
    local name = frame and frame.GetName and frame:GetName()
    name = type(name) == "string" and name:lower() or ""
    if name:find("reagent", 1, true) or name:find("ingredient", 1, true) then
        return true
    end
    for _, key in ipairs({
        "reagent", "reagentInfo", "selectedReagent", "reagentSlotSchematic",
        "reagents", "reagentIndex", "reagentSlotIndex",
    }) do
        if (frame and frame[key] ~= nil) or (data and data[key] ~= nil) then
            return true
        end
    end
    return false
end

local function reagentDataItem(data)
    if not data then return nil end
    for _, key in ipairs({
        "reagent", "reagentInfo", "selectedReagent", "reagentSlotSchematic",
        "slotInfo", "reagents",
    }) do
        local value = data[key]
        local found = value and dataItem(value)
        if found then return found end
    end
end

local function professionRecipeID(frame, data)
    local recipeID = data and (data.recipeID
        or data.recipeInfo and data.recipeInfo.recipeID)
    if recipeID then return recipeID end

    local current = frame
    for _ = 1, 10 do
        if not current then break end
        if current.GetElementData then
            local ok, elementData = pcall(current.GetElementData, current)
            if ok and type(elementData) == "table" then
                recipeID = elementData.recipeID
                    or elementData.recipeInfo and elementData.recipeInfo.recipeID
                if recipeID then return recipeID end
            end
        end
        current = current.GetParent and current:GetParent()
    end

    if C_TradeSkillUI and C_TradeSkillUI.GetSelectedRecipeID then
        local ok, selected = pcall(C_TradeSkillUI.GetSelectedRecipeID)
        if ok and selected then return selected end
    end
    local page = _G.ProfessionsFrame and _G.ProfessionsFrame.CraftingPage
    local form = page and page.SchematicForm
    local recipeInfo = form and form.recipeInfo or methodResult(page, "GetRecipeInfo")
    return recipeInfo and recipeInfo.recipeID
end

local function reagentSlotIndex(frame, data)
    for _, container in ipairs({ data, data and data.slotInfo, frame }) do
        if container then
            for _, key in ipairs({
                "reagentIndex", "reagentSlotIndex", "slotIndex", "index",
            }) do
                local value = tonumber(container[key])
                if value then return value end
            end
        end
    end
    local name = frame and frame.GetName and frame:GetName()
    local index = type(name) == "string"
        and tonumber(name:lower():match("reagent[^%d]*(%d+)"))
    if index then return index end
    local id = frame and frame.GetID and frame:GetID()
    return tonumber(id) and tonumber(id) > 0 and tonumber(id) or nil
end

local function professionReagentItem(frame, data)
    local name = frame and frame.GetName and frame:GetName() or ""
    local legacyIndex = tonumber(name:match("TradeSkillReagent(%d+)"))
    if legacyIndex and _G.TradeSkillFrame and GetTradeSkillReagentItemLink then
        local selected = _G.TradeSkillFrame.selectedSkill
        local link = selected and GetTradeSkillReagentItemLink(selected, legacyIndex)
        if link then return link end
    end
    legacyIndex = tonumber(name:match("CraftReagent(%d+)"))
    if legacyIndex and _G.CraftFrame and GetCraftReagentItemLink then
        local selected = _G.CraftFrame.selectedCraft
        local link = selected and GetCraftReagentItemLink(selected, legacyIndex)
        if link then return link end
    end

    local recipeID = professionRecipeID(frame, data)
    if not (recipeID and C_TradeSkillUI and C_TradeSkillUI.GetRecipeSchematic) then
        return nil
    end
    local ok, schematic = pcall(C_TradeSkillUI.GetRecipeSchematic, recipeID, false)
    local slots = ok and schematic and schematic.reagentSlotSchematics
    if type(slots) ~= "table" then return nil end
    local index = reagentSlotIndex(frame, data)
    local slot = index and (slots[index] or slots[index + 1])
    if not slot and #slots == 1 then slot = slots[1] end
    return slot and dataItem(slot) or nil
end

local function buttonItem(frame, allowRecipeOutput)
    if not frame then return nil end
    local ok, location = pcall(function()
        return frame.GetItemLocation and frame:GetItemLocation()
    end)
    if ok and location and location.IsValid and location:IsValid()
            and C_Item and C_Item.GetItemLink then
        local link = C_Item.GetItemLink(location)
        if link then return link end
    end
    local direct = allowRecipeOutput == false and reagentDataItem(frame) or dataItem(frame)
    if direct then return direct end

    local data
    if frame.GetElementData then
        local gotData, elementData = pcall(frame.GetElementData, frame)
        if gotData and type(elementData) == "table" then
            local found = allowRecipeOutput == false
                and reagentDataItem(elementData) or dataItem(elementData)
            if found then return found end
            data = elementData
        end
    end
    if reagentContext(frame, data) then
        local reagent = professionReagentItem(frame, data)
        if reagent then return reagent end
    end
    if allowRecipeOutput ~= false and not reagentContext(frame, data) then
        local recipeID = data and data.recipeInfo and data.recipeInfo.recipeID
        if recipeID and C_TradeSkillUI and C_TradeSkillUI.GetRecipeOutputItemData then
            local gotOutput, output = pcall(C_TradeSkillUI.GetRecipeOutputItemData, recipeID)
            if gotOutput and output then return output.hyperlink or output.itemID end
        end
    end
    local name = frame.GetName and frame:GetName() or ""
    if name:find("^Character%a+Slot$") and frame.GetID and GetInventoryItemLink then
        return GetInventoryItemLink("player", frame:GetID())
    end
    if name:find("^MerchantItem%d+ItemButton$") and frame.GetID then
        local merchant = _G.MerchantFrame
        local buyback = merchant and merchant.selectedTab == 2
        return buyback and GetBuybackItemLink and GetBuybackItemLink(frame:GetID())
            or GetMerchantItemLink and GetMerchantItemLink(frame:GetID())
    end
    if frame.objectType == "item" and frame.type and frame.GetID then
        local log = _G.QuestInfoFrame and _G.QuestInfoFrame.questLog
        return log and GetQuestLogItemLink and GetQuestLogItemLink(frame.type, frame:GetID())
            or GetQuestItemLink and GetQuestItemLink(frame.type, frame:GetID())
    end
    return nil, reagentContext(frame, data)
end

function Gamepad:ResolveFrameItem(frame)
    return buttonItem(frame, true)
end

local function framesRelated(left, right)
    if not left or not right then return false end
    local current = left
    for _ = 1, 12 do
        if current == right then return true end
        current = current.GetParent and current:GetParent()
        if not current then break end
    end
    current = right
    for _ = 1, 12 do
        if current == left then return true end
        current = current.GetParent and current:GetParent()
        if not current then break end
    end
    return false
end

local function itemFromFocus(frame)
    if not frame then return nil end
    local parent = frame.GetParent and frame:GetParent()
    local loot = _G.LootFrame
    if parent and parent.GetSlotIndex and loot and loot:IsShown() and GetLootSlotLink then
        local okSlot, slot = pcall(parent.GetSlotIndex, parent)
        local okLink, link = okSlot and type(slot) == "number"
            and pcall(GetLootSlotLink, slot)
        if okLink and link then return link end
    end
    for _, candidate in ipairs({ frame, parent }) do
        if candidate and candidate.GetBagID and candidate.GetID
                and C_Container and C_Container.GetContainerItemLink then
            local okBag, bagID = pcall(candidate.GetBagID, candidate)
            local okSlot, slotID = pcall(candidate.GetID, candidate)
            if okBag and okSlot and type(bagID) == "number"
                    and type(slotID) == "number" then
                local okLink, link = pcall(
                    C_Container.GetContainerItemLink, bagID, slotID)
                if okLink and link then return link end
            end
        end
    end
    local candidate = frame
    local isReagent = false
    for _ = 1, 7 do
        local value, candidateIsReagent = buttonItem(candidate, not isReagent)
        if value then return value end
        isReagent = isReagent or candidateIsReagent
        candidate = candidate and candidate.GetParent and candidate:GetParent()
    end
end

local function visibleTooltipItem()
    local tooltip = _G.GameTooltip
    if not (tooltip and tooltip.IsShown and tooltip:IsShown() and tooltip.GetItem) then
        return nil
    end
    local ok, _, link = pcall(tooltip.GetItem, tooltip)
    if ok and itemID(link) then return link end
end

local function focusedItem()
    local addonFocus = Gamepad.GetFocusedControl and Gamepad:GetFocusedControl()
    if addonFocus and itemID(addonFocus.itemID) then
        return addonFocus.itemID, addonFocus
    end
    local navigation = _G.SmartNavigation
    local focus = navigation and navigation.GetCurrentButton
        and navigation:GetCurrentButton()
    -- Gamepad profession reagent buttons expose the selected item reliably through
    -- GameTooltip, while their navigation frame may only carry the output recipe.
    local value = visibleTooltipItem()
    if value then return value, focus end

    local okFocus, focusValue = pcall(itemFromFocus, focus)
    value = okFocus and focusValue or nil
    if value then return value, focus end

    if GetMouseFoci then
        local foci = { GetMouseFoci() }
        if #foci == 1 and type(foci[1]) == "table" and not foci[1].GetParent then
            foci = foci[1]
        end
        for _, frame in ipairs(foci) do
            local okFrame, frameValue = pcall(itemFromFocus, frame)
            value = okFrame and frameValue or nil
            if value then return value, frame end
        end
    elseif GetMouseFocus then
        focus = GetMouseFocus()
        local okFrame, frameValue = pcall(itemFromFocus, focus)
        value = okFrame and frameValue or nil
        if value then return value, focus end
    end

    if lastTooltipItem and GetTime() - lastTooltipItem.at < ns.Config.gamepadTooltipMemory
            and (not focus or framesRelated(lastTooltipItem.owner, focus)) then
        return lastTooltipItem.value, focus
    end
end

local function modified()
    for _, key in ipairs({ "PADLSHOULDER", "PADRSHOULDER", "PADLTRIGGER", "PADRTRIGGER" }) do
        if IsKeyDown(key) then return true end
    end
    return false
end

local function holdTarget()
    local windowFocused = Gamepad.IsWindowFocused and Gamepad:IsWindowFocused()
    local addonFocus = windowFocused and Gamepad.GetFocusedControl
        and Gamepad:GetFocusedControl()
    local focusedAddonItem = addonFocus and itemID(addonFocus.itemID)
    local active = Gamepad:IsLayoutActive()
        and (not windowFocused or focusedAddonItem ~= nil)
        and not (InCombatLockdown and InCombatLockdown())
    if not active or modified() then return nil end
    return focusedItem()
end

-- The professions frame binds R3 on button-down to its Set Amount popup.
-- Delay that one native action until button-up so a short press keeps the
-- Blizzard behavior, while a completed hold can consume it for Foreverpedia.
function Gamepad:DeferNativeR3Tap(callback)
    if type(callback) ~= "function" or not IsKeyDown or not IsKeyDown(R3_KEY) then
        return false
    end
    local value = holdTarget()
    if not value then return false end
    if hold and not hold.done then
        hold.nativeTap = callback
    else
        pendingNativeTap = callback
    end
    return true
end

local professionHooksInstalled = false
local professionBindingOwner
local professionBindingButton
local professionBindingInstalled = false
local PROFESSION_BINDING_BUTTON = "ForeverpediaProfessionR3BindingButton"

local function isR3Key(key)
    return key == R3_KEY or key == "PADRSTICK"
end

local function professionR3Callback(frame)
    local group = frame and frame.adjustAmount
    if not (group and type(group.functions) == "table") then return nil end
    for _, entry in pairs(group.functions) do
        for _, key in ipairs(entry.keys or {}) do
            if isR3Key(key) and type(entry.func) == "function" then
                return entry.func
            end
        end
    end
end

local function callNativeR3(callback)
    if type(callback) ~= "function" then return end
    if securecallfunction then
        pcall(securecallfunction, callback)
    else
        pcall(callback)
    end
end

local function createProfessionBindingFrames()
    if professionBindingOwner then return end
    professionBindingOwner = CreateFrame(
        "Frame", "ForeverpediaProfessionR3BindingOwner", UIParent)
    professionBindingButton = CreateFrame(
        "Button", PROFESSION_BINDING_BUTTON, UIParent)
    professionBindingButton:SetSize(1, 1)
    professionBindingButton:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", -20, -20)
    professionBindingButton:EnableMouse(false)
    if professionBindingButton.RegisterForClicks then
        professionBindingButton:RegisterForClicks("AnyDown", "AnyUp")
    end
    professionBindingButton:SetScript("OnClick", function(_, _, down)
        if down == false then return end
        local callback = professionR3Callback(_G.ProfessionsFrame)
        if not callback then return end
        local nativeTap = function() callNativeR3(callback) end
        if not Gamepad:DeferNativeR3Tap(nativeTap) then nativeTap() end
    end)
end

local function professionHasFocus(frame)
    if not (frame and frame.IsShown and frame:IsShown()) then return false end
    local page = frame.CraftingPage
    if page and page.IsShown and not page:IsShown() then return false end
    local navigation = _G.SmartNavigation
    if not (navigation and navigation.GetActiveFrame) then return false end
    local ok, activeFrame = pcall(navigation.GetActiveFrame, navigation)
    return ok and activeFrame == frame
end

local function clearProfessionBinding()
    if not professionBindingInstalled then return end
    if InCombatLockdown and InCombatLockdown() then return end
    if professionBindingOwner and ClearOverrideBindings then
        pcall(ClearOverrideBindings, professionBindingOwner)
    end
    professionBindingInstalled = false
end

local function updateProfessionBinding(frame, force)
    local wanted = Gamepad:IsLayoutActive() and professionHasFocus(frame)
        and not (Gamepad.IsWindowFocused and Gamepad:IsWindowFocused())
        and professionR3Callback(frame) ~= nil
    if not wanted then
        clearProfessionBinding()
        return
    end
    if professionBindingInstalled and not force then return end
    if not SetOverrideBindingClick or (InCombatLockdown and InCombatLockdown()) then
        return
    end
    createProfessionBindingFrames()
    local ok = pcall(SetOverrideBindingClick, professionBindingOwner, true,
        R3_KEY, PROFESSION_BINDING_BUTTON, "LeftButton")
    professionBindingInstalled = ok
end

local function installProfessionHooks()
    local mixin = _G.ProfessionsMixin
    if mixin and hooksecurefunc and not professionHooksInstalled then
        professionHooksInstalled = true
        if type(mixin.UpdateSmartNavFocus) == "function" then
            hooksecurefunc(mixin, "UpdateSmartNavFocus", function(self)
                -- Blizzard has just restored its own R3 binding. Put our
                -- isolated override on top without changing Blizzard tables.
                updateProfessionBinding(self, true)
            end)
        end
    end
    updateProfessionBinding(_G.ProfessionsFrame)
end

installProfessionHooks()

local professionEvents = CreateFrame("Frame")
if professionEvents.RegisterEvent then
    pcall(professionEvents.RegisterEvent, professionEvents, "ADDON_LOADED")
    pcall(professionEvents.RegisterEvent, professionEvents, "PLAYER_LOGIN")
    pcall(professionEvents.RegisterEvent, professionEvents, "PLAYER_REGEN_DISABLED")
    professionEvents:SetScript("OnEvent", function(_, event, addonName)
        if event == "PLAYER_REGEN_DISABLED" then
            clearProfessionBinding()
        elseif event == "PLAYER_LOGIN" or addonName == "Blizzard_Professions" then
            installProfessionHooks()
        end
    end)
end

local function createProgress()
    if progressFrame then return progressFrame end
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetSize(18, 18)
    frame:SetFrameStrata("TOOLTIP")
    frame.segments = {}
    local radius = 6.5
    for index = 1, SEGMENT_COUNT do
        local angle = math.pi / 2 - (index - 1) * math.pi * 2 / SEGMENT_COUNT
        local segment = frame:CreateTexture(nil, "ARTWORK")
        segment:SetColorTexture(0.34, 0.27, 0.14, 0.55)
        segment:SetSize(1.7, 3.2)
        segment:SetPoint("CENTER", frame, "CENTER",
            math.cos(angle) * radius, math.sin(angle) * radius)
        if segment.SetRotation then segment:SetRotation(angle + math.pi / 2) end
        frame.segments[index] = segment
    end
    frame:Hide()
    progressFrame = frame
    return frame
end

local function showProgress(start, anchor)
    local frame = createProgress()
    frame:ClearAllPoints()
    if anchor and anchor.GetRight and anchor:GetRight() then
        frame:SetPoint("LEFT", anchor, "RIGHT", 4, 0)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, -80)
    end
    local duration = ns.Config.gamepadHoldDuration - ns.Config.gamepadHoldShowAfter
    local progress = math.max(0, math.min(1,
        (GetTime() - start - ns.Config.gamepadHoldShowAfter) / duration))
    local lit = math.ceil(progress * SEGMENT_COUNT)
    for index, segment in ipairs(frame.segments) do
        if index <= lit then
            segment:SetColorTexture(1, 0.72, 0.18, 0.96)
        else
            segment:SetColorTexture(0.34, 0.27, 0.14, 0.55)
        end
    end
    frame:Show()
end

local function hideProgress()
    if progressFrame then
        progressFrame:Hide()
    end
end

local function openDeferred(value)
    local id = itemID(value)
    if not id then return end
    local callback = function()
        if ns.CraftTree and ns.CraftTree.frame and ns.CraftTree.frame:IsShown() then
            ns.CraftTree.frame:Hide()
        end
        ns.UI:OpenItem(type(value) == "string" and value or "item:" .. id, id)
    end
    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(0, callback)
    else
        callback()
    end
end

local watcher = CreateFrame("Frame")
watcher:SetScript("OnUpdate", function()
    installProfessionHooks()
    if not IsKeyDown then return end
    local down = IsKeyDown(R3_KEY)
    local windowFocused = Gamepad.IsWindowFocused and Gamepad:IsWindowFocused()
    local addonFocus = windowFocused and Gamepad.GetFocusedControl
        and Gamepad:GetFocusedControl()
    local focusedAddonItem = addonFocus and itemID(addonFocus.itemID)
    local active = Gamepad:IsLayoutActive()
        and (not windowFocused or focusedAddonItem ~= nil)
        and not (InCombatLockdown and InCombatLockdown())
    if not active or not down then
        local pending = hold and hold.openOnRelease and hold.value
        local nativeTap = not down and not pending
            and ((hold and hold.nativeTap) or pendingNativeTap)
        if hold then hideProgress() end
        hold = nil
        pendingNativeTap = nil
        wasDown = down
        if pending then
            openDeferred(pending)
        elseif nativeTap then
            if C_Timer and type(C_Timer.After) == "function" then
                C_Timer.After(0, nativeTap)
            else
                nativeTap()
            end
        end
        return
    end
    if not hold and not wasDown then
        if modified() then
            hold = { done = true }
        else
            local value, anchor = focusedItem()
            hold = {
                start = GetTime(), value = value, anchor = anchor,
                nativeTap = pendingNativeTap, done = not value,
            }
            pendingNativeTap = nil
        end
    end
    wasDown = down
    if not hold or hold.done then return end
    local elapsed = GetTime() - hold.start
    if elapsed < ns.Config.gamepadHoldShowAfter then return end
    if elapsed < ns.Config.gamepadHoldDuration then
        showProgress(hold.start, hold.anchor)
        return
    end
    hold.done = true
    hold.openOnRelease = true
    hideProgress()
end)

