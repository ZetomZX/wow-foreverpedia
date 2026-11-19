local _, ns = ...

local Gamepad = ns.Gamepad
if not Gamepad then return end

local L = ns.L
local CreateFrame = ns.CreateDetachedFrame or CreateFrame
local focused = false
local bindingsInstalled = false
local currentControl
local viewWasDown = false
local fallbackDown = {}
local heldNavigation = {}
local bindingOwner
local handlers = {}
local viewBindingOwner
local viewBindingButton
local viewBindingInstalled = false
local bindingsPendingClear = false
local REPEAT_DELAY = 0.38
local REPEAT_INTERVAL = 0.11
local REPEAT_BINDINGS = { up = "PADDUP", down = "PADDDOWN" }

local BINDINGS = {
    up = "PADDUP", down = "PADDDOWN", left = "PADDLEFT", right = "PADDRIGHT",
    accept = "PAD1", back = "PAD2", toggleTop = "PAD3", craftTree = "PAD4",
    previousTab = "PADLSHOULDER", nextTab = "PADRSHOULDER",
    focusList = "PADLTRIGGER", focusDetails = "PADRTRIGGER",
    holdItem = "PADRSTICK",
}

local HANDLER_NAMES = {
    up = "ForeverpediaGamepadUp", down = "ForeverpediaGamepadDown",
    left = "ForeverpediaGamepadLeft", right = "ForeverpediaGamepadRight",
    accept = "ForeverpediaGamepadAccept", back = "ForeverpediaGamepadBack",
    toggleTop = "ForeverpediaGamepadToggleTop",
    craftTree = "ForeverpediaGamepadCraftTree",
    previousTab = "ForeverpediaGamepadPreviousTab",
    nextTab = "ForeverpediaGamepadNextTab",
    focusList = "ForeverpediaGamepadFocusList",
    focusDetails = "ForeverpediaGamepadFocusDetails",
    holdItem = "ForeverpediaGamepadHoldItem",
}

local function shown(frame)
    return frame and frame.IsShown and frame:IsShown()
end

local function enabled(frame)
    return shown(frame) and (not frame.IsEnabled or frame:IsEnabled())
end

local function controlCenter(frame)
    if not frame or not frame.GetCenter then return nil, nil end
    local ok, x, y = pcall(frame.GetCenter, frame)
    return ok and x or nil, ok and y or nil
end

local function allControls()
    if not (ns.UI and ns.UI.GetGamepadControls) then return {} end
    local controls = ns.UI:GetGamepadControls()
    local result = {}
    for _, control in ipairs(controls or {}) do
        if enabled(control) then result[#result + 1] = control end
    end
    return result
end

local function zoneControls(zone)
    local result = {}
    for _, control in ipairs(allControls()) do
        if control.fpGamepadZone == zone then result[#result + 1] = control end
    end
    table.sort(result, function(left, right)
        local lx, ly = controlCenter(left)
        local rx, ry = controlCenter(right)
        ly, ry = ly or 0, ry or 0
        if math.abs(ly - ry) > 3 then return ly > ry end
        return (lx or 0) < (rx or 0)
    end)
    return result
end

local function contains(controls, target)
    for _, control in ipairs(controls) do
        if control == target then return true end
    end
    return false
end

local function callScript(control, scriptName)
    if not (control and control.GetScript) then return end
    local script = control:GetScript(scriptName)
    if script then pcall(script, control) end
end

local function scrollFrameFor(control)
    local frame = ns.UI and ns.UI.frame
    if not frame or not control then return nil end
    local zone = control.fpGamepadZone
    if zone == "list" then return frame.scroll end
    if zone == "details" then return frame.details and frame.details.scroll end
    if zone == "tree" and ns.CraftTree and ns.CraftTree.frame then
        return ns.CraftTree.frame.scroll
    end
end

local function ensureVisible(control)
    local scroll = scrollFrameFor(control)
    if not (scroll and control.GetTop and control.GetBottom
            and scroll.GetTop and scroll.GetBottom) then return end
    local top, bottom = control:GetTop(), control:GetBottom()
    local viewTop, viewBottom = scroll:GetTop(), scroll:GetBottom()
    if not (top and bottom and viewTop and viewBottom) then return end
    local offset = scroll:GetVerticalScroll() or 0
    if top > viewTop - 6 then
        scroll:SetVerticalScroll(math.max(0, offset - (top - viewTop) - 12))
    elseif bottom < viewBottom + 6 then
        local maximum = scroll.GetVerticalScrollRange and scroll:GetVerticalScrollRange() or offset
        scroll:SetVerticalScroll(math.min(maximum, offset + (viewBottom - bottom) + 12))
    end
end

local function setSelected(control)
    if not focused then return end
    if currentControl == control and enabled(control) then
        ensureVisible(control)
        return
    end
    if currentControl then callScript(currentControl, "OnLeave") end
    currentControl = control
    local ring = Gamepad.focusRing
    if not (ring and control) then
        if ring then ring:Hide() end
        return
    end
    ring:SetParent(control)
    ring:SetFrameLevel((control.GetFrameLevel and control:GetFrameLevel() or 1) + 20)
    ring:ClearAllPoints()
    ring:SetPoint("TOPLEFT", control, "TOPLEFT", -4, 4)
    ring:SetPoint("BOTTOMRIGHT", control, "BOTTOMRIGHT", 4, -4)
    ring:Show()
    ensureVisible(control)
    callScript(control, "OnEnter")
    if Gamepad.UpdateLegend then Gamepad:UpdateLegend() end
end

local function firstInZone(zone)
    return zoneControls(zone)[1]
end

local function nearestInZone(zone, reference)
    local controls = zoneControls(zone)
    if #controls == 0 then return nil end
    local rx, ry = controlCenter(reference)
    if not rx then return controls[1] end
    local best, bestScore
    for _, control in ipairs(controls) do
        local x, y = controlCenter(control)
        if x and y then
            local score = math.abs(x - rx) + math.abs(y - ry) * 2
            if not bestScore or score < bestScore then
                best, bestScore = control, score
            end
        end
    end
    return best or controls[1]
end

local function nearestDirectional(direction, requiredZone)
    local x, y = controlCenter(currentControl)
    if not x then return nil end
    local best, bestScore
    for _, control in ipairs(allControls()) do
        if control ~= currentControl
                and (not requiredZone or control.fpGamepadZone == requiredZone) then
            local cx, cy = controlCenter(control)
            if cx and cy then
                local primary, secondary
                if direction == "left" and cx < x - 2 then
                    primary, secondary = x - cx, math.abs(cy - y)
                elseif direction == "right" and cx > x + 2 then
                    primary, secondary = cx - x, math.abs(cy - y)
                elseif direction == "up" and cy > y + 2 then
                    primary, secondary = cy - y, math.abs(cx - x)
                elseif direction == "down" and cy < y - 2 then
                    primary, secondary = y - cy, math.abs(cx - x)
                end
                if primary then
                    local score = primary + secondary * 2.5
                    if not bestScore or score < bestScore then
                        best, bestScore = control, score
                    end
                end
            end
        end
    end
    return best
end

local function moveWithinZone(zone, delta)
    local controls = zoneControls(zone)
    local index
    for position, control in ipairs(controls) do
        if control == currentControl then index = position break end
    end
    local target = index and controls[index + delta]
    if target then setSelected(target) end
    return target ~= nil
end

local function moveVertical(delta)
    if not currentControl then return end
    local zone = currentControl.fpGamepadZone
    if moveWithinZone(zone, delta) then return end
    local target
    if zone ~= "top" and zone ~= "list" and zone ~= "details" then
        target = nearestDirectional(delta < 0 and "up" or "down")
    end
    if target then setSelected(target) end
end

function Gamepad:Move(direction)
    if not focused then return end
    self:RefreshFocus()
    if not currentControl then return end
    local zone = currentControl.fpGamepadZone
    if zone == "tree" then
        local target = nearestDirectional(direction, "tree")
        if target then setSelected(target) end
        return
    end
    if zone == "top" then
        local delta = (direction == "left" or direction == "up") and -1 or 1
        moveWithinZone(zone, delta)
        return
    end
    if direction == "up" then moveVertical(-1) return end
    if direction == "down" then moveVertical(1) return end
    if zone == "list" or zone == "details" or zone == "search" then return end
    local target
    if zone == "options" or zone == "tree_top" or zone == "tree_filters" then
        local delta = direction == "left" and -1 or 1
        if moveWithinZone(zone, delta) then return end
    end
    target = nearestDirectional(direction)
    if target then setSelected(target) end
end

local function scheduleRefresh(preferredZone)
    local callback = function() Gamepad:RefreshFocus(preferredZone) end
    if C_Timer and C_Timer.After then C_Timer.After(0, callback) else callback() end
end

function Gamepad:Activate()
    if not (focused and currentControl) then return end
    if currentControl == ns.UI.frame.searchBox then
        currentControl:SetFocus()
        return
    end
    if currentControl.fpGamepadActivate then
        currentControl:fpGamepadActivate()
    elseif currentControl.Click then
        currentControl:Click("LeftButton")
    end
    scheduleRefresh(currentControl and currentControl.fpGamepadZone)
end

function Gamepad:Back()
    if not focused then return end
    local tree = ns.CraftTree and ns.CraftTree.frame
    if shown(tree) then
        if ns.CraftTree.history and #ns.CraftTree.history > 0 then
            ns.CraftTree:GoBack()
        else
            tree:Hide()
        end
        scheduleRefresh("list")
        return
    end
    local frame = ns.UI and ns.UI.frame
    if not frame then return end
    if shown(frame.optionsPanel) then
        frame.optionsPanel:Hide()
        scheduleRefresh("top")
        return
    end
    if frame.searchBox and frame.searchBox.HasFocus and frame.searchBox:HasFocus()
            or shown(frame.searchSuggestions) then
        frame.searchSuggestions:Hide()
        frame.searchBox:ClearFocus()
        scheduleRefresh("top")
        return
    end
    if ns.UI.history and #ns.UI.history > 0 then ns.UI:GoBack() else frame:Hide() end
    scheduleRefresh("list")
end

function Gamepad:FocusSearch()
    local frame = ns.UI and ns.UI.frame
    if not (focused and frame and frame.searchBox) then return end
    if shown(frame.optionsPanel) then frame.optionsPanel:Hide() end
    setSelected(frame.searchBox)
    frame.searchBox:SetFocus()
end

function Gamepad:ToggleOptions()
    local frame = ns.UI and ns.UI.frame
    if not (focused and frame and frame.optionsButton) then return end
    frame.optionsButton:Click("LeftButton")
    scheduleRefresh(shown(frame.optionsPanel) and "options" or "top")
end

function Gamepad:SwitchTab(delta)
    if not (focused and ns.UI and ns.UI.frame) then return end
    if shown(ns.UI.frame.optionsPanel) or shown(ns.CraftTree and ns.CraftTree.frame) then return end
    local target = ns.UI.activeTab == "uses"
        and (delta > 0 and "sources" or "uses")
        or (delta < 0 and "uses" or "sources")
    ns.UI:SetTab(target)
    scheduleRefresh("list")
end

function Gamepad:ToggleTopPanel()
    if not focused then return end
    local frame = ns.UI and ns.UI.frame
    if not frame or shown(frame.optionsPanel) then return end
    if shown(ns.CraftTree and ns.CraftTree.frame) then
        local zone = currentControl and currentControl.fpGamepadZone
        local target = zone == "tree"
            and (firstInZone("tree_filters") or firstInZone("tree"))
            or firstInZone("tree")
        if target then setSelected(target) end
        return
    end
    if currentControl and currentControl.fpGamepadZone == "top" then
        if frame.searchBox and frame.searchBox.ClearFocus then frame.searchBox:ClearFocus() end
        if frame.searchSuggestions then frame.searchSuggestions:Hide() end
        setSelected(firstInZone("list") or firstInZone("details"))
    else
        setSelected(firstInZone("top"))
    end
end

function Gamepad:FocusPane(zone)
    if not focused or shown(ns.CraftTree and ns.CraftTree.frame) then return end
    local frame = ns.UI and ns.UI.frame
    if not frame or shown(frame.optionsPanel) then return end
    if currentControl and currentControl.fpGamepadZone == zone then return end
    local target = nearestInZone(zone, currentControl) or firstInZone(zone)
    if target then setSelected(target) end
end

function Gamepad:AdjustDepth(delta)
    local tree = ns.CraftTree
    if not (focused and tree and shown(tree.frame) and tree.SetDepth) then return false end
    tree:SetDepth((tree.depth or 1) + delta)
    scheduleRefresh(currentControl and currentControl.fpGamepadZone or "tree")
    return true
end

function Gamepad:OpenCraftTree()
    if not (focused and ns.CraftTree and ns.UI) then return end
    if shown(ns.CraftTree.frame) then return end
    local recipeModifier = IsKeyDown and IsKeyDown("PADRTRIGGER")
    local relation
    if recipeModifier then
        relation = currentControl
            and (currentControl.fpGamepadRecipe or currentControl.recipe)
        local selection = ns.UI.detailSelection
        if not relation and selection and selection.kind == "recipe" then
            relation = selection.relation
        end
    end
    if relation and ns.CraftTree.OpenRecipe then
        ns.CraftTree:OpenRecipe(relation)
        scheduleRefresh("tree")
        return
    end
    local itemID = currentControl and currentControl.itemID or ns.UI.currentItemID
    if not recipeModifier and itemID
            and ns.CraftTree.IsAvailable
            and ns.CraftTree:IsAvailable(itemID) then
        ns.CraftTree:Open(itemID)
        scheduleRefresh("tree")
    end
end

local ACTIONS = {
    up = function() Gamepad:Move("up") end,
    down = function() Gamepad:Move("down") end,
    left = function() Gamepad:Move("left") end,
    right = function() Gamepad:Move("right") end,
    accept = function() Gamepad:Activate() end,
    back = function() Gamepad:Back() end,
    toggleTop = function() Gamepad:ToggleTopPanel() end,
    craftTree = function() Gamepad:OpenCraftTree() end,
    previousTab = function() Gamepad:SwitchTab(-1) end,
    nextTab = function() Gamepad:SwitchTab(1) end,
    focusList = function()
        if not Gamepad:AdjustDepth(-1) then Gamepad:FocusPane("list") end
    end,
    focusDetails = function()
        if not Gamepad:AdjustDepth(1) then Gamepad:FocusPane("details") end
    end,
    -- The hold itself is read in Gamepad.lua. This binding only prevents an
    -- underlying Blizzard window (notably professions) from handling the
    -- same R3 press while Foreverpedia has focus.
    holdItem = function() end,
}

local function createBindingFrames()
    if bindingOwner then return end
    bindingOwner = CreateFrame("Frame", "ForeverpediaGamepadBindingOwner", UIParent)
    for action, name in pairs(HANDLER_NAMES) do
        local button = CreateFrame("Button", name, UIParent)
        button:SetSize(1, 1)
        button:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", -20, -20)
        button:EnableMouse(false)
        button:SetScript("OnClick", ACTIONS[action])
        handlers[action] = button
    end
end

local function clearBindings()
    if InCombatLockdown and InCombatLockdown() then
        bindingsPendingClear = true
        return false
    end
    if bindingOwner and ClearOverrideBindings then
        local ok = pcall(ClearOverrideBindings, bindingOwner)
        if not ok then
            bindingsPendingClear = true
            return false
        end
    end
    bindingsInstalled = false
    bindingsPendingClear = false
    return true
end

local function applyBindings()
    clearBindings()
    if not (focused and SetOverrideBindingClick
            and not (InCombatLockdown and InCombatLockdown())) then return end
    createBindingFrames()
    local success = true
    for action, key in pairs(BINDINGS) do
        local ok = pcall(SetOverrideBindingClick, bindingOwner, true,
            key, HANDLER_NAMES[action], "LeftButton")
        success = success and ok
    end
    if success then bindingsInstalled = true else clearBindings() end
end

local function createViewBindingFrames()
    if viewBindingOwner then return end
    viewBindingOwner = CreateFrame(
        "Frame", "ForeverpediaGamepadViewBindingOwner", UIParent)
    viewBindingButton = CreateFrame(
        "Button", "ForeverpediaGamepadViewBindingButton", UIParent)
    viewBindingButton:SetSize(1, 1)
    viewBindingButton:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", -20, -20)
    viewBindingButton:EnableMouse(false)
    if viewBindingButton.RegisterForClicks then
        viewBindingButton:RegisterForClicks("AnyDown", "AnyUp")
    end
    viewBindingButton:SetScript("OnClick", function(_, _, down)
        if down == false then Gamepad:ToggleWindowFocus() end
    end)
end

local function clearViewBinding()
    if InCombatLockdown and InCombatLockdown() then return false end
    if viewBindingOwner and ClearOverrideBindings then
        pcall(ClearOverrideBindings, viewBindingOwner)
    end
    viewBindingInstalled = false
    return true
end

local function applyViewBinding()
    if viewBindingInstalled or not SetOverrideBindingClick
            or (InCombatLockdown and InCombatLockdown()) then return end
    createViewBindingFrames()
    viewBindingInstalled = pcall(SetOverrideBindingClick,
        viewBindingOwner, true, "PADBACK",
        "ForeverpediaGamepadViewBindingButton", "LeftButton")
end

local function bindingGlyph(key, fallbackKey)
    -- Steam Input can expose the face buttons as the raw SDL indices 1-4.
    -- Those are implementation details, not labels printed on the Deck.
    -- Keep the addon's stable A/B/X/Y mapping for face buttons and reject
    -- numeric/"Button N" results for every other gamepad control as well.
    if key == "PAD1" or key == "PAD2" or key == "PAD3" or key == "PAD4" then
        return L(fallbackKey)
    end
    if GetBindingText then
        local ok, value = pcall(GetBindingText, key, 1)
        if ok and type(value) == "string" and value ~= "" then
            local technical = value:gsub("%s+", ""):upper()
            if not technical:match("^%d+$")
                    and not technical:match("^BUTTON%d+$")
                    and technical ~= key then
                return value
            end
        end
    end
    return L(fallbackKey)
end

local LEGEND = {
    { keys = { { "PAD1", "gamepad_button_a" } }, label = "gamepad_select", width = 82, kind = "accept" },
    { keys = { { "PAD2", "gamepad_button_b" } }, label = "gamepad_back", width = 82, kind = "back" },
    { keys = { { "PAD3", "gamepad_button_x" } }, label = "gamepad_top", width = 90, kind = "top" },
    { keys = { { "PADBACK", "gamepad_button_view" } }, label = "gamepad_game", width = 96, kind = "view" },
}

local function createLegendEntry(parent, definition)
    local entry = CreateFrame("Frame", nil, parent)
    entry:SetSize(definition.width, 30)
    local previous
    for _, keyInfo in ipairs(definition.keys) do
        local anchor = previous
        if previous then
            local separator = entry:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            separator:SetSize(10, 25)
            separator:SetJustifyH("CENTER")
            separator:SetPoint("LEFT", previous, "RIGHT", 1, 0)
            separator:SetText(L("gamepad_combo_separator"))
            separator:SetTextColor(0.95, 0.72, 0.27)
            anchor = separator
        end
        local key = entry:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        key:SetSize(25, 25)
        key:SetJustifyH("CENTER")
        if anchor then key:SetPoint("LEFT", anchor, "RIGHT", 1, 0)
        else key:SetPoint("LEFT", 0, 0) end
        key:SetText(bindingGlyph(keyInfo[1], keyInfo[2]))
        previous = key
    end
    local label = entry:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("LEFT", previous, "RIGHT", 4, 0)
    label:SetPoint("RIGHT", entry, "RIGHT", 0, 0)
    label:SetJustifyH("LEFT")
    label:SetText(L(definition.label))
    label:SetTextColor(0.95, 0.72, 0.27)
    entry.label = label
    entry.kind = definition.kind
    return entry
end

local function createLegend(frame)
    if Gamepad.legend then return end
    local legend = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    legend:SetHeight(38)
    legend:SetPoint("BOTTOMLEFT", 18, 4)
    legend:SetPoint("BOTTOMRIGHT", -18, 4)
    legend:SetFrameLevel(frame:GetFrameLevel() + 15)
    legend:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    legend:SetBackdropColor(0.035, 0.030, 0.026, 0.96)
    legend:SetBackdropBorderColor(0.34, 0.31, 0.27, 0.96)
    legend.entries = {}
    local previous
    for index, definition in ipairs(LEGEND) do
        local entry = createLegendEntry(legend, definition)
        if previous then entry:SetPoint("LEFT", previous, "RIGHT", 7, 0)
        else entry:SetPoint("LEFT", 10, 0) end
        legend.entries[index] = entry
        previous = entry
    end
    legend:Hide()
    Gamepad.legend = legend

    local ring = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    ring:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
    })
    ring:SetBackdropBorderColor(1, 0.78, 0.20, 1)
    ring:EnableMouse(false)
    ring:Hide()
    Gamepad.focusRing = ring
end

function Gamepad:UpdateTabHints()
    local frame = ns.UI and ns.UI.frame
    local tabs = frame and frame.tabButtons
    if not tabs then return end
    if self:IsLayoutActive() then
        tabs.uses.label:SetText(bindingGlyph("PADLSHOULDER", "gamepad_button_lb")
            .. "  " .. L("uses"))
        tabs.sources.label:SetText(L("sources") .. "  "
            .. bindingGlyph("PADRSHOULDER", "gamepad_button_rb"))
    else
        tabs.uses.label:SetText(L("uses"))
        tabs.sources.label:SetText(L("sources"))
    end
end

local function createPaneHints(frame)
    if frame.gamepadListHint then return end
    local listHint = frame.listPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    listHint:SetSize(30, 25)
    listHint:SetPoint("TOPRIGHT", frame.listPanel, "TOPRIGHT", -38, -8)
    listHint:SetJustifyH("CENTER")
    listHint:Hide()
    frame.gamepadListHint = listHint

    local detailsHint = frame.details:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    detailsHint:SetSize(30, 25)
    detailsHint:SetPoint("LEFT", frame.details.title, "RIGHT", 8, 0)
    detailsHint:SetJustifyH("CENTER")
    detailsHint:Hide()
    frame.gamepadDetailsHint = detailsHint
end

local function fitHintButton(button, defaultWidth, maximumWidth)
    if not (button and button.label) then return end
    local measured = button.label.GetStringWidth and button.label:GetStringWidth() or defaultWidth
    button:SetWidth(math.max(72, math.min(maximumWidth, math.ceil(measured) + 12)))
end

function Gamepad:UpdateInlineHints()
    local frame = ns.UI and ns.UI.frame
    if not frame then return end
    local active = self:IsLayoutActive()
    local tree = ns.CraftTree and ns.CraftTree.frame
    local treeActive = active and shown(tree)
    createPaneHints(frame)
    frame.gamepadListHint:SetText(bindingGlyph("PADLTRIGGER", "gamepad_button_lt"))
    frame.gamepadDetailsHint:SetText(bindingGlyph("PADRTRIGGER", "gamepad_button_rt"))
    frame.gamepadListHint:SetShown(active and not treeActive)
    frame.gamepadDetailsHint:SetShown(active and not treeActive)
    local headerButton = frame.craftTreeButton
    if headerButton and headerButton.label then
        headerButton.label:SetText(active
            and (bindingGlyph("PAD4", "gamepad_button_y") .. "  " .. L("craft_chain"))
            or L("craft_chain"))
        if active then fitHintButton(headerButton, 152, 180)
        else headerButton:SetWidth(152) end
    end
    local detailButton = frame.details and frame.details.content
        and frame.details.content.recipeChainButton
    if detailButton and detailButton.label then
        local combo = bindingGlyph("PADRTRIGGER", "gamepad_button_rt")
            .. "  " .. L("gamepad_combo_separator") .. "  "
            .. bindingGlyph("PAD4", "gamepad_button_y")
        detailButton.label:SetText(active and (combo .. "  " .. L("craft_chain"))
            or L("craft_chain"))
        if active then
            local contentWidth = detailButton:GetParent():GetWidth() or 0
            local headingWidth = detailButton.heading and detailButton.heading:GetStringWidth() or 0
            local available = math.max(120, contentWidth - headingWidth - 20)
            fitHintButton(detailButton, 154, available)
        else
            detailButton:SetWidth(154)
        end
    end
    if tree and tree.minusButton and tree.plusButton then
        tree.minusButton:SetWidth(treeActive and 48 or 28)
        tree.plusButton:SetWidth(treeActive and 48 or 28)
        tree.minusButton:SetText(treeActive
            and (bindingGlyph("PADLTRIGGER", "gamepad_button_lt") .. "  -") or "-")
        tree.plusButton:SetText(treeActive
            and (bindingGlyph("PADRTRIGGER", "gamepad_button_rt") .. "  +") or "+")
    end
end

local function positionLegend(legend, frame, tree)
    local parent = tree or frame
    if legend:GetParent() ~= parent then legend:SetParent(parent) end
    legend:ClearAllPoints()
    if tree and tree.panel then
        legend:SetPoint("BOTTOMLEFT", tree.panel, "BOTTOMLEFT", 18, 4)
        legend:SetPoint("BOTTOMRIGHT", tree.panel, "BOTTOMRIGHT", -18, 4)
        legend:SetFrameLevel(tree.panel:GetFrameLevel() + 15)
    else
        legend:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 18, 4)
        legend:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -18, 4)
        legend:SetFrameLevel(frame:GetFrameLevel() + 15)
    end
end

function Gamepad:UpdateLegend()
    local frame = ns.UI and ns.UI.frame
    local active = self:IsLayoutActive() and shown(frame)
    local tree = ns.CraftTree and ns.CraftTree.frame
    local treeShown = shown(tree)
    if self.legend and frame then positionLegend(self.legend, frame, treeShown and tree or nil) end
    if self.legend then self.legend:SetShown(active) end
    if frame and frame.footer then frame.footer:SetShown(not active) end
    if tree and tree.footer then tree.footer:SetShown(not (active and treeShown)) end
    self:UpdateTabHints()
    self:UpdateInlineHints()
    if not self.legend then return end
    for _, entry in ipairs(self.legend.entries) do
        if entry.kind == "back" then
            local canGoBack = shown(ns.CraftTree and ns.CraftTree.frame)
                or ns.UI.history and #ns.UI.history > 0
            entry.label:SetText(L(canGoBack and "gamepad_back" or "gamepad_close"))
        elseif entry.kind == "view" then
            entry.label:SetText(L(focused and "gamepad_game" or "gamepad_window"))
        elseif entry.kind == "top" then
            if treeShown then
                entry.label:SetText(L(currentControl
                    and currentControl.fpGamepadZone == "tree"
                    and "gamepad_filters" or "gamepad_chain"))
            else
                entry.label:SetText(L(currentControl and currentControl.fpGamepadZone == "top"
                    and "gamepad_list" or "gamepad_top"))
            end
        end
        entry:SetAlpha(focused and 1 or (entry.kind == "view" and 1 or 0.42))
    end
end

function Gamepad:AttachUI(frame)
    createLegend(frame)
    createPaneHints(frame)
    -- Foreverpedia deliberately stays outside Blizzard's protected frame-focus
    -- stack. Its own override bindings sit above the currently focused native
    -- window and are removed on close, so Blizzard can restore professions,
    -- bags, or player controls without any addon-written manager state.
    self:UpdateLegend()
end

function Gamepad:IsWindowFocused()
    return focused
end

function Gamepad:GetFocusedControl()
    return focused and currentControl or nil
end

function Gamepad:RefreshFocus(preferredZone)
    self:UpdateLegend()
    if not focused then return end
    local controls = allControls()
    if currentControl and contains(controls, currentControl) then
        setSelected(currentControl)
        return
    end
    local target = preferredZone and firstInZone(preferredZone)
        or firstInZone("list") or firstInZone("top")
        or controls[1]
    setSelected(target)
end

function Gamepad:FocusWindow(preferredZone)
    local frame = ns.UI and ns.UI.frame
    if not (self:IsLayoutActive() and shown(frame)) then return end
    focused = true
    applyBindings()
    self:RefreshFocus(preferredZone)
end

function Gamepad:ReleaseWindowFocus()
    clearBindings()
    focused = false
    if currentControl then callScript(currentControl, "OnLeave") end
    currentControl = nil
    heldNavigation = {}
    if self.focusRing then self.focusRing:Hide() end
    self:UpdateLegend()
end

function Gamepad:ToggleWindowFocus()
    if focused then self:ReleaseWindowFocus() else self:FocusWindow() end
end

function Gamepad:OnWindowOpened()
    if not self:IsLayoutActive() then return end
    local frame = ns.UI and ns.UI.frame
    if not frame then return end
    applyViewBinding()
    self:FocusWindow("list")
end

function Gamepad:OnWindowHidden()
    self:ReleaseWindowFocus()
    clearViewBinding()
end

function Gamepad:OnInputStyleChanged()
    if not self:IsLayoutActive() then
        self:ReleaseWindowFocus()
        clearViewBinding()
    elseif shown(ns.UI and ns.UI.frame) then
        applyViewBinding()
    end
    self:UpdateLegend()
end

local watcher = CreateFrame("Frame")
watcher:SetScript("OnUpdate", function()
    local frame = ns.UI and ns.UI.frame
    if not (IsKeyDown and Gamepad:IsLayoutActive() and shown(frame)) then
        viewWasDown = false
        heldNavigation = {}
        return
    end
    if not viewBindingInstalled then
        local viewDown = IsKeyDown("PADBACK")
        if viewWasDown and not viewDown then Gamepad:ToggleWindowFocus() end
        viewWasDown = viewDown
    else
        viewWasDown = false
    end

    if focused and not bindingsInstalled then
        for action, key in pairs(BINDINGS) do
            local down = IsKeyDown(key)
            if down and not fallbackDown[action] then ACTIONS[action]() end
            fallbackDown[action] = down
        end
    end

    local zone = currentControl and currentControl.fpGamepadZone
    local canRepeat = focused and (zone == "list" or zone == "details")
    local now = GetTime and GetTime() or 0
    for action, key in pairs(REPEAT_BINDINGS) do
        local down = canRepeat and IsKeyDown(key)
        local state = heldNavigation[action]
        if down and not state then
            heldNavigation[action] = { nextAt = now + REPEAT_DELAY }
        elseif down and now >= state.nextAt then
            ACTIONS[action]()
            state.nextAt = now + REPEAT_INTERVAL
        elseif not down then
            heldNavigation[action] = nil
        end
    end
end)

local events = CreateFrame("Frame")
pcall(events.RegisterEvent, events, "PLAYER_REGEN_DISABLED")
pcall(events.RegisterEvent, events, "PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        heldNavigation = {}
    elseif event == "PLAYER_REGEN_ENABLED" then
        if bindingsPendingClear or not focused then clearBindings() end
        if focused and not bindingsInstalled then applyBindings() end
    end
end)

