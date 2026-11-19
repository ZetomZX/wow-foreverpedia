local _, ns = ...
local L = ns.L
local CreateFrame = ns.CreateDetachedFrame or CreateFrame

local CraftTree = {
    depth = ns.Config.craftTree.defaultDepth,
    history = {},
    nodeButtons = {},
    lineTextures = {},
    quantityBadges = {},
    professionButtons = {},
}
ns.CraftTree = CraftTree

local COLORS = ns.Theme.colors
local limits = ns.Config.craftTree
local MAX_DEPTH = limits.maximumDepth
local MAX_RECIPES_PER_ITEM = limits.maximumRecipesPerItem
local MAX_OUTPUTS_PER_ITEM = limits.maximumOutputsPerItem
local MAX_INGREDIENTS_PER_RECIPE = limits.maximumIngredientsPerRecipe
local MAX_NODES_PER_COLUMN = limits.maximumNodesPerColumn
local NODE_HEIGHT = limits.nodeHeight

local SOURCE_KIND_INFO = {
    herb = { "Interface\\Icons\\INV_Misc_Herb_07", "herb", 2 },
    fishing = { "Interface\\Icons\\Trade_Fishing", "fishing", 2 },
    drop = { "Interface\\Icons\\INV_Misc_MonsterClaw_04", "creature_drop", 4 },
    vendor = { "Interface\\Icons\\INV_Misc_Coin_01", "vendor", 3 },
    object = { "Interface\\Icons\\INV_Misc_Chest_03", "object_or_chest", 6 },
    quest_reward = { "Interface\\Icons\\INV_Misc_Note_01", "quest_reward", 5 },
    container = { "Interface\\Icons\\INV_Box_01", "container", 6 },
    gathering = { "Interface\\Icons\\INV_Pick_02", "gathering", 2 },
    disenchant = { "Interface\\Icons\\Spell_Holy_GreaterHeal", "disenchant", 2 },
    pickpocket = { "Interface\\Icons\\INV_Misc_Bag_11", "pickpocket", 4 },
    spell_loot = { "Interface\\Icons\\INV_Misc_MagicDust_01", "spell_loot", 5 },
    mail = { "Interface\\Icons\\INV_Letter_15", "mail", 6 },
}

local SOURCE_KIND_ORDER = {
    "gathering", "disenchant", "herb", "fishing", "vendor", "drop", "pickpocket",
    "quest_reward", "object", "container", "spell_loot", "mail",
}

local setBackdrop = ns.Theme.SetBackdrop
local itemName = ns.GetItemName

local function itemIcon(itemID)
    if C_Item and C_Item.GetItemIconByID then
        return C_Item.GetItemIconByID(itemID)
    end
    return 134400
end

local function copyPath(path)
    local result = {}
    for itemID in pairs(path or {}) do result[itemID] = true end
    return result
end

local setButtonEnabled = ns.Util.SetButtonEnabled

local function graphNode(graph, itemID, level)
    local key = tostring(level) .. ":" .. tostring(itemID)
    local existing = graph.nodes[key]
    if existing then return existing end

    graph.levels[level] = graph.levels[level] or {}
    if #graph.levels[level] >= MAX_NODES_PER_COLUMN then
        graph.hiddenNodes = graph.hiddenNodes + 1
        return nil
    end

    local node = {
        key = key,
        itemID = itemID,
        level = level,
        name = itemName(itemID),
    }
    local productionRecipes = ns.DataProvider:GetCraftRecipesForOutput(itemID)
    if #productionRecipes > 0 then
        local recipe = productionRecipes[1]
        node.professionID = recipe.professionID
        node.professionName = recipe.professionName
        node.professionIcon = recipe.professionIcon
        node.recipeName = recipe.name
        node.alternativeRecipes = math.max(0, #productionRecipes - 1)
    end

    local record = ns.DataProvider:Get(itemID)
    local availableKinds = {}
    local labelSeen = {}
    node.sourceLabels = {}
    local function considerSourceIcon(icon, priority)
        if icon and (not node.sourceIconPriority or priority < node.sourceIconPriority) then
            node.sourceIcon = icon
            node.sourceIconPriority = priority
        end
    end
    for _, source in ipairs(record.sources or {}) do
        if source.kind == "gathering" then
            local label = source.professionName or source.name or L("professional_gathering")
            if not labelSeen[label] then
                node.sourceLabels[#node.sourceLabels + 1] = label
                labelSeen[label] = true
            end
            considerSourceIcon(source.professionIcon or SOURCE_KIND_INFO.gathering[1], 2)
        elseif SOURCE_KIND_INFO[source.kind] then
            availableKinds[source.kind] = true
        end
    end
    for _, kind in ipairs(SOURCE_KIND_ORDER) do
        if availableKinds[kind] then
            local info = SOURCE_KIND_INFO[kind]
            considerSourceIcon(info[1], info[3])
            local label = L(info[2])
            if not labelSeen[label] then
                node.sourceLabels[#node.sourceLabels + 1] = label
                labelSeen[label] = true
            end
        end
    end
    if #productionRecipes == 0 and #node.sourceLabels == 0 then
        considerSourceIcon("Interface\\Icons\\INV_Misc_QuestionMark", 99)
        node.sourceLabels[1] = L("unknown_source")
    end
    graph.nodes[key] = node
    graph.levels[level][#graph.levels[level] + 1] = node
    graph.minimumLevel = math.min(graph.minimumLevel, level)
    graph.maximumLevel = math.max(graph.maximumLevel, level)
    return node
end

local function recipeGraphNode(graph, recipe, level)
    local key = tostring(level) .. ":recipe:" .. tostring(recipe.recipeID)
    local existing = graph.nodes[key]
    if existing then return existing end
    graph.levels[level] = graph.levels[level] or {}
    if #graph.levels[level] >= MAX_NODES_PER_COLUMN then
        graph.hiddenNodes = graph.hiddenNodes + 1
        return nil
    end
    local node = {
        key = key,
        recipeID = recipe.recipeID,
        level = level,
        name = recipe.name or L("recipe"),
        icon = recipe.professionIcon,
        professionID = recipe.professionID,
        professionName = recipe.professionName,
        professionIcon = recipe.professionIcon,
        sourceLabels = {},
    }
    graph.nodes[key] = node
    graph.levels[level][#graph.levels[level] + 1] = node
    graph.minimumLevel = math.min(graph.minimumLevel, level)
    graph.maximumLevel = math.max(graph.maximumLevel, level)
    return node
end

local function graphEdge(graph, source, target, recipe, quantity)
    if not source or not target then return end
    local key = table.concat({ source.key, target.key, recipe.recipeID or 0 }, ":")
    if graph.edgeKeys[key] then return end
    graph.edgeKeys[key] = true
    local edge = {
        source = source,
        target = target,
        quantity = quantity,
        recipeID = recipe.recipeID,
        professionName = recipe.professionName,
        professionIcon = recipe.professionIcon,
    }
    graph.edges[#graph.edges + 1] = edge
    source.outgoing = source.outgoing or {}
    target.incoming = target.incoming or {}
    source.outgoing[#source.outgoing + 1] = edge
    target.incoming[#target.incoming + 1] = edge
end

local function characterFilterKey()
    if UnitGUID then
        local guid = UnitGUID("player")
        if guid and guid ~= "" then return guid end
    end
    local name = UnitName and UnitName("player") or "Player"
    local realm = GetRealmName and GetRealmName() or "Forever"
    return tostring(name) .. "-" .. tostring(realm)
end

function CraftTree:DetectPlayerProfessions()
    local owned = {}
    if type(GetProfessions) ~= "function" or type(GetProfessionInfo) ~= "function" then
        return owned
    end
    local ok, primary, secondary, archaeology, fishing, cooking, firstAid =
        pcall(GetProfessions)
    if not ok then return owned end
    local slots = { primary, secondary, archaeology, fishing, cooking, firstAid }
    for slot = 1, 6 do
        local professionIndex = slots[slot]
        if professionIndex then
            local infoOK, name, _, _, _, _, _, skillLine =
                pcall(GetProfessionInfo, professionIndex)
            if infoOK then
                if skillLine and ns.RecipeData.professions[skillLine] then
                    owned[skillLine] = true
                elseif name then
                    for professionID, professionName in pairs(ns.RecipeData.professions or {}) do
                        if professionName == name then owned[professionID] = true end
                    end
                end
            end
        end
    end
    return owned
end

function CraftTree:EnsureProfessionFilters()
    local key = characterFilterKey()
    if self.professionFilters and self.professionFilterKey == key then return end

    ForeverpediaDB = ForeverpediaDB or {}
    ForeverpediaDB.craftTreeProfessionFilters =
        ForeverpediaDB.craftTreeProfessionFilters or {}
    local store = ForeverpediaDB.craftTreeProfessionFilters
    local saved = store[key]
    if type(saved) ~= "table" or type(saved.enabled) ~= "table" then
        saved = { enabled = {}, owned = {} }
        store[key] = saved
    end
    saved.owned = saved.owned or {}

    local owned = self:DetectPlayerProfessions()
    for professionID in pairs(ns.RecipeData.professions or {}) do
        if saved.enabled[professionID] == nil then
            saved.enabled[professionID] = owned[professionID] == true
        elseif owned[professionID] and saved.owned[professionID] == false then
            saved.enabled[professionID] = true
        end
        saved.owned[professionID] = owned[professionID] == true
    end
    self.professionFilterKey = key
    self.professionFilters = saved.enabled
    self.playerProfessions = owned
end

function CraftTree:IsProfessionEnabled(professionID)
    self:EnsureProfessionFilters()
    return self.professionFilters[professionID] == true
end

function CraftTree:ToggleProfession(professionID)
    self:EnsureProfessionFilters()
    self.professionFilters[professionID] = not self.professionFilters[professionID]
    self:Render()
end

function CraftTree:SetProfessionFilterMode(mode)
    self:EnsureProfessionFilters()
    if mode == "reset" then
        self.playerProfessions = self:DetectPlayerProfessions()
    end
    for professionID in pairs(ns.RecipeData.professions or {}) do
        if mode == "all" then
            self.professionFilters[professionID] = true
        elseif mode == "none" then
            self.professionFilters[professionID] = false
        elseif mode == "reset" then
            self.professionFilters[professionID] = self.playerProfessions[professionID] == true
        end
    end
    self:Render()
end

function CraftTree:AutoEnableProductionProfessions(itemID)
    self:EnsureProfessionFilters()
    for _, recipe in ipairs(ns.DataProvider:GetCraftRecipesForOutput(itemID) or {}) do
        if recipe.professionID then self.professionFilters[recipe.professionID] = true end
    end
end

function CraftTree:OrderedProfessions()
    self:EnsureProfessionFilters()
    local professions = {}
    for professionID in pairs(ns.RecipeData.professions or {}) do
        professions[#professions + 1] = {
            id = professionID,
            name = ns.GetProfessionName(professionID),
            icon = ns.RecipeData.professionIcons[professionID],
            owned = self.playerProfessions[professionID] == true,
        }
    end
    table.sort(professions, function(left, right)
        if left.owned ~= right.owned then return left.owned end
        if left.name ~= right.name then return left.name < right.name end
        return left.id < right.id
    end)
    return professions
end

function CraftTree:IsAvailable(itemID)
    return itemID and ns.DataProvider
        and ns.DataProvider:HasCraftRelations(itemID) or false
end

function CraftTree:IsRecipeAvailable(recipe)
    return recipe and recipe.recipeID and #(recipe.ingredients or {}) > 0
end

function CraftTree:ExpandRecipeInputs(graph, target, recipe, level, remaining, path)
    local ingredients = recipe.ingredients or {}
    if #ingredients > MAX_INGREDIENTS_PER_RECIPE then
        graph.hiddenNodes = graph.hiddenNodes + #ingredients - MAX_INGREDIENTS_PER_RECIPE
    end
    for ingredientIndex = 1, math.min(#ingredients, MAX_INGREDIENTS_PER_RECIPE) do
        local ingredient = ingredients[ingredientIndex]
        local ingredientID = ingredient.itemID or ingredient[1]
        local quantity = ingredient.quantity or ingredient[2]
        if ingredientID and ingredientID ~= 0 then
            local source = graphNode(graph, ingredientID, level - 1)
            graphEdge(graph, source, target, recipe, quantity)
            if source and remaining > 1 and not path[ingredientID] then
                local nextPath = copyPath(path)
                nextPath[ingredientID] = true
                local available = ns.DataProvider:GetCraftRecipesForOutput(ingredientID)
                local recipes = {}
                for _, inputRecipe in ipairs(available) do
                    if self:IsProfessionEnabled(inputRecipe.professionID) then
                        recipes[#recipes + 1] = inputRecipe
                    else
                        graph.filteredRecipes = graph.filteredRecipes + 1
                    end
                end
                if #recipes > MAX_RECIPES_PER_ITEM then
                    graph.hiddenRecipes = graph.hiddenRecipes + #recipes - MAX_RECIPES_PER_ITEM
                end
                for recipeIndex = 1, math.min(#recipes, MAX_RECIPES_PER_ITEM) do
                    self:ExpandRecipeInputs(graph, source, recipes[recipeIndex],
                        level - 1, remaining - 1, nextPath)
                end
            end
        end
    end
end

function CraftTree:BuildRecipeGraph(recipe)
    local graph = {
        centerRecipeID = recipe.recipeID,
        nodes = {}, levels = {}, edges = {}, edgeKeys = {},
        minimumLevel = 0, maximumLevel = 0,
        hiddenNodes = 0, hiddenRecipes = 0, filteredRecipes = 0,
    }
    local center = recipeGraphNode(graph, recipe, 0)
    center.isCenter = true
    self:ExpandRecipeInputs(graph, center, recipe, 0, self.depth,
        { ["recipe:" .. tostring(recipe.recipeID)] = true })
    return graph
end

function CraftTree:BuildGraph(centerItemID)
    local graph = {
        centerItemID = centerItemID,
        nodes = {},
        levels = {},
        edges = {},
        edgeKeys = {},
        minimumLevel = 0,
        maximumLevel = 0,
        hiddenNodes = 0,
        hiddenRecipes = 0,
        filteredRecipes = 0,
    }
    local center = graphNode(graph, centerItemID, 0)
    center.isCenter = true

    local function expandInputs(itemID, level, remaining, path)
        if remaining <= 0 then return end
        local available = ns.DataProvider:GetCraftRecipesForOutput(itemID)
        local recipes = {}
        for _, recipe in ipairs(available) do
            if level == 0 or self:IsProfessionEnabled(recipe.professionID) then
                recipes[#recipes + 1] = recipe
            else
                graph.filteredRecipes = graph.filteredRecipes + 1
            end
        end
        if #recipes > MAX_RECIPES_PER_ITEM then
            graph.hiddenRecipes = graph.hiddenRecipes + #recipes - MAX_RECIPES_PER_ITEM
        end
        for recipeIndex = 1, math.min(#recipes, MAX_RECIPES_PER_ITEM) do
            local recipe = recipes[recipeIndex]
            local target = graphNode(graph, itemID, level)
            local ingredients = recipe.ingredients or {}
            if #ingredients > MAX_INGREDIENTS_PER_RECIPE then
                graph.hiddenNodes = graph.hiddenNodes
                    + #ingredients - MAX_INGREDIENTS_PER_RECIPE
            end
            for ingredientIndex = 1, math.min(#ingredients, MAX_INGREDIENTS_PER_RECIPE) do
                local ingredient = ingredients[ingredientIndex]
                local ingredientID = ingredient.itemID or ingredient[1]
                local quantity = ingredient.quantity or ingredient[2]
                if ingredientID and ingredientID ~= 0 then
                    local source = graphNode(graph, ingredientID, level - 1)
                    graphEdge(graph, source, target, recipe, quantity)
                    if source and not path[ingredientID] then
                        local nextPath = copyPath(path)
                        nextPath[ingredientID] = true
                        expandInputs(ingredientID, level - 1, remaining - 1, nextPath)
                    end
                end
            end
        end
    end

    local function expandOutputs(itemID, level, remaining, path)
        if remaining <= 0 then return end
        local available = ns.DataProvider:GetCraftUses(itemID)
        local itemUses, effectUses = {}, {}
        for _, recipe in ipairs(available) do
            local outputID = recipe.outputItemID
            if outputID == itemID then
                graph.hiddenRecipes = graph.hiddenRecipes + 1
            elseif self:IsProfessionEnabled(recipe.professionID) then
                if outputID and outputID ~= 0 then
                    itemUses[#itemUses + 1] = recipe
                else
                    effectUses[#effectUses + 1] = recipe
                end
            else
                graph.filteredRecipes = graph.filteredRecipes + 1
            end
        end
        local function recipeBefore(left, right)
            if (left.outputName or "") ~= (right.outputName or "") then
                return (left.outputName or "") < (right.outputName or "")
            end
            if (left.name or "") ~= (right.name or "") then
                return (left.name or "") < (right.name or "")
            end
            return (left.recipeID or 0) < (right.recipeID or 0)
        end
        table.sort(itemUses, recipeBefore)
        table.sort(effectUses, recipeBefore)
        local uses = {}
        for _, recipe in ipairs(itemUses) do uses[#uses + 1] = recipe end
        for _, recipe in ipairs(effectUses) do uses[#uses + 1] = recipe end
        if #uses > MAX_OUTPUTS_PER_ITEM then
            graph.hiddenRecipes = graph.hiddenRecipes + #uses - MAX_OUTPUTS_PER_ITEM
        end
        for index = 1, math.min(#uses, MAX_OUTPUTS_PER_ITEM) do
            local recipe = uses[index]
            local outputID = recipe.outputItemID
            local source = graphNode(graph, itemID, level)
            local target = outputID and outputID ~= 0
                and graphNode(graph, outputID, level + 1)
                or recipeGraphNode(graph, recipe, level + 1)
            graphEdge(graph, source, target, recipe, recipe.quantity)
            if target and outputID and outputID ~= 0 and not path[outputID] then
                local nextPath = copyPath(path)
                nextPath[outputID] = true
                expandOutputs(outputID, level + 1, remaining - 1, nextPath)
            end
        end
    end

    expandInputs(centerItemID, 0, self.depth, { [centerItemID] = true })
    expandOutputs(centerItemID, 0, self.depth, { [centerItemID] = true })
    return graph
end

function CraftTree:Create(parent)
    if self.frame then return self.frame end

    local overlay = CreateFrame("Frame", "ForeverpediaCraftTreeFrame", parent,
        "BackdropTemplate")
    overlay:SetAllPoints(parent)
    overlay:SetFrameLevel(parent:GetFrameLevel() + 30)
    overlay:EnableMouse(true)
    setBackdrop(overlay, COLORS.overlay, { 0, 0, 0, 0 })

    local panel = CreateFrame("Frame", nil, overlay, "BackdropTemplate")
    panel:SetPoint("TOPLEFT", 34, -42)
    panel:SetPoint("BOTTOMRIGHT", -34, 38)
    setBackdrop(panel, COLORS.craftBackground)

    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -17)
    title:SetText(L("craft_chain_title"))
    title:SetTextColor(unpack(COLORS.gold))

    local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
    close:SetScript("OnClick", function() overlay:Hide() end)

    local back = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    back:SetSize(30, 26)
    back:SetPoint("TOPLEFT", 12, -11)
    back:SetText("<")
    back:SetScript("OnClick", function() CraftTree:GoBack() end)

    local itemLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    itemLabel:SetPoint("TOPLEFT", 18, -51)
    itemLabel:SetPoint("RIGHT", -300, 0)
    itemLabel:SetJustifyH("LEFT")

    local depthLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    depthLabel:SetPoint("TOPRIGHT", -106, -52)
    depthLabel:SetTextColor(unpack(COLORS.muted))

    local minus = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    minus:SetSize(28, 24)
    minus:SetPoint("TOPRIGHT", -68, -43)
    minus:SetText("-")
    minus:SetScript("OnClick", function() CraftTree:SetDepth(CraftTree.depth - 1) end)

    local plus = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    plus:SetSize(28, 24)
    plus:SetPoint("LEFT", minus, "RIGHT", 4, 0)
    plus:SetText("+")
    plus:SetScript("OnClick", function() CraftTree:SetDepth(CraftTree.depth + 1) end)
    depthLabel:ClearAllPoints()
    depthLabel:SetPoint("RIGHT", minus, "LEFT", -8, 0)

    local divider = panel:CreateTexture(nil, "ARTWORK")
    divider:SetPoint("TOPLEFT", 14, -75)
    divider:SetPoint("TOPRIGHT", -14, -75)
    divider:SetHeight(1)
    divider:SetColorTexture(COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.65)

    local filterLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    filterLabel:SetPoint("TOPLEFT", 18, -91)
    filterLabel:SetText(L("professions_label"))
    filterLabel:SetTextColor(unpack(COLORS.muted))

    local professionBar = CreateFrame("Frame", nil, panel)
    professionBar:SetPoint("LEFT", filterLabel, "RIGHT", 8, 0)
    professionBar:SetPoint("RIGHT", panel, "RIGHT", -18, 0)
    professionBar:SetHeight(30)

    local function createFilterActionButton(textKey, tooltipKey, width, mode)
        local button = CreateFrame("Button", nil, professionBar, "UIPanelButtonTemplate")
        button:SetSize(width, 22)
        button:SetText(L(textKey))
        button:SetScript("OnClick", function()
            CraftTree:SetProfessionFilterMode(mode)
        end)
        button:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:AddLine(L(textKey))
            GameTooltip:AddLine(L(tooltipKey), 0.70, 0.66, 0.57, true)
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", function() GameTooltip:Hide() end)
        return button
    end

    local filterReset = createFilterActionButton("filter_reset", "filter_reset_tip", 62, "reset")
    filterReset:SetPoint("RIGHT", professionBar, "RIGHT", 0, 0)
    local filterNone = createFilterActionButton("filter_none", "filter_none_tip", 66, "none")
    filterNone:SetPoint("RIGHT", filterReset, "LEFT", -4, 0)
    local filterAll = createFilterActionButton("filter_all", "filter_all_tip", 50, "all")
    filterAll:SetPoint("RIGHT", filterNone, "LEFT", -4, 0)

    local filterDivider = panel:CreateTexture(nil, "ARTWORK")
    filterDivider:SetPoint("TOPLEFT", 14, -119)
    filterDivider:SetPoint("TOPRIGHT", -14, -119)
    filterDivider:SetHeight(1)
    filterDivider:SetColorTexture(COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.45)

    local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 14, -128)
    scroll:SetPoint("BOTTOMRIGHT", -32, 47)
    local canvas = CreateFrame("Frame", nil, scroll)
    canvas:SetSize(1, 1)
    scroll:SetScrollChild(canvas)

    local footer = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    footer:SetPoint("BOTTOMLEFT", 18, 18)
    footer:SetPoint("BOTTOMRIGHT", -18, 18)
    footer:SetJustifyH("CENTER")
    footer:SetTextColor(unpack(COLORS.muted))

    overlay.panel = panel
    overlay.canvas = canvas
    overlay.scroll = scroll
    overlay.itemLabel = itemLabel
    overlay.depthLabel = depthLabel
    overlay.backButton = back
    overlay.minusButton = minus
    overlay.plusButton = plus
    overlay.footer = footer
    overlay.professionBar = professionBar
    overlay.filterAllButton = filterAll
    overlay.filterNoneButton = filterNone
    overlay.filterResetButton = filterReset
    overlay:SetScript("OnShow", function()
        CraftTree:Render()
        if ns.Gamepad and ns.Gamepad.RefreshFocus then
            ns.Gamepad:RefreshFocus("tree")
        end
    end)
    overlay:SetScript("OnHide", function()
        if ns.Gamepad and ns.Gamepad.RefreshFocus then
            ns.Gamepad:RefreshFocus("list")
        end
    end)
    panel:SetScript("OnSizeChanged", function()
        if not overlay:IsShown() then return end
        if C_Timer and C_Timer.After then
            CraftTree.resizeToken = (CraftTree.resizeToken or 0) + 1
            local token = CraftTree.resizeToken
            C_Timer.After(0, function()
                if token == CraftTree.resizeToken and overlay:IsShown() then
                    CraftTree:Render()
                end
            end)
        end
    end)

    self.frame = overlay
    self.depth = math.max(1, math.min(MAX_DEPTH,
        ForeverpediaDB and ForeverpediaDB.craftTreeDepth or limits.defaultDepth))
    if UISpecialFrames then UISpecialFrames[#UISpecialFrames + 1] = overlay:GetName() end
    overlay:Hide()
    return overlay
end

local function appendGamepadControls(result, controls, zone)
    for _, control in ipairs(controls or {}) do
        if control and control.IsShown and control:IsShown() then
            control.fpGamepadZone = zone
            result[#result + 1] = control
        end
    end
end

function CraftTree:GetGamepadControls()
    local result = {}
    if not (self.frame and self.frame:IsShown()) then return result end
    appendGamepadControls(result, {
        self.frame.filterAllButton,
        self.frame.filterNoneButton,
        self.frame.filterResetButton,
    }, "tree_filters")
    appendGamepadControls(result, self.professionButtons, "tree_filters")
    appendGamepadControls(result, self.nodeButtons, "tree")
    return result
end

function CraftTree:AcquireLine()
    local index = (self.usedLines or 0) + 1
    self.usedLines = index
    local texture = self.lineTextures[index]
    if not texture then
        texture = self.frame.canvas:CreateTexture(nil, "BACKGROUND")
        texture:SetColorTexture(COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.82)
        self.lineTextures[index] = texture
    end
    texture:Show()
    texture:ClearAllPoints()
    return texture
end

function CraftTree:DrawSegment(x, y, width, height)
    local texture = self:AcquireLine()
    if texture.SetRotation then texture:SetRotation(0) end
    texture:SetPoint("TOPLEFT", self.frame.canvas, "TOPLEFT", x, -y)
    texture:SetSize(math.max(1, width), math.max(1, height))
end

function CraftTree:DrawConnection(sourceX, sourceY, targetX, targetY, lane, laneTotal)
    local texture = self:AcquireLine()
    local differenceX = targetX - sourceX
    local total = math.max(1, laneTotal or 1)
    local slot = math.max(1, math.min(total, lane or 1))
    local middleX = sourceX + differenceX * slot / (total + 1)
    if middleX <= sourceX + 3 or middleX >= targetX - 3 then
        middleX = math.floor((sourceX + targetX) / 2)
    end
    if texture.SetRotation then texture:SetRotation(0) end
    texture:SetPoint("TOPLEFT", self.frame.canvas, "TOPLEFT", sourceX, -sourceY)
    texture:SetSize(math.max(1, middleX - sourceX), 2)
    self:DrawSegment(middleX, math.min(sourceY, targetY), 2,
        math.max(2, math.abs(targetY - sourceY)))
    self:DrawSegment(middleX, targetY, math.max(1, targetX - middleX), 2)
    return middleX
end

function CraftTree:AcquireQuantityBadge()
    local index = (self.usedQuantityBadges or 0) + 1
    self.usedQuantityBadges = index
    local badge = self.quantityBadges[index]
    if not badge then
        badge = CreateFrame("Frame", nil, self.frame.canvas, "BackdropTemplate")
        badge:SetHeight(17)
        badge:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 8,
            insets = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        badge:SetBackdropColor(0.035, 0.027, 0.018, 1)
        badge:SetBackdropBorderColor(COLORS.border[1], COLORS.border[2], COLORS.border[3], 1)
        local label = badge:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("CENTER", 0, 0)
        label:SetTextColor(unpack(COLORS.gold))
        badge.label = label
        self.quantityBadges[index] = badge
    end
    badge:Show()
    badge:ClearAllPoints()
    return badge
end

function CraftTree:AcquireNode()
    local index = (self.usedNodes or 0) + 1
    self.usedNodes = index
    local button = self.nodeButtons[index]
    if button then
        button:Show()
        button:ClearAllPoints()
        return button
    end

    button = CreateFrame("Button", nil, self.frame.canvas, "BackdropTemplate")
    button:RegisterForClicks("LeftButtonUp")
    setBackdrop(button, COLORS.node)
    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetPoint("TOPLEFT", 4, -4)
    highlight:SetPoint("BOTTOMRIGHT", -4, 4)
    highlight:SetColorTexture(1, 0.78, 0.25, 0.09)

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(42, 42)
    icon:SetPoint("LEFT", 9, 0)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    local name = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 8, -1)
    name:SetJustifyH("LEFT")
    name:SetJustifyV("TOP")
    name:SetWordWrap(true)

    name:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -28, 7)

    local cornerIcons = {}
    for iconIndex = 1, 4 do
        local cornerIcon = button:CreateTexture(nil, "OVERLAY")
        cornerIcon:SetSize(14, 14)
        cornerIcon:SetPoint("BOTTOMRIGHT", -7 - (iconIndex - 1) * 15, 7)
        cornerIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        cornerIcon:Hide()
        cornerIcons[iconIndex] = cornerIcon
    end

    button.icon = icon
    button.name = name
    button.cornerIcons = cornerIcons
    button:SetScript("OnEnter", function(self)
        if self.recipeID and not self.itemID then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if GameTooltip.SetSpellByID then
                GameTooltip:SetSpellByID(self.recipeID)
            else
                GameTooltip:AddLine(self.name:GetText() or L("recipe"))
            end
            GameTooltip:Show()
            return
        end
        ns.UI:ShowItemTooltip(self, self.itemID, function()
            GameTooltip:AddLine(" ")
            if self.professionName and self.professionName ~= "" then
                GameTooltip:AddLine(L("profession_prefix", self.professionName),
                    0.70, 0.66, 0.57)
            end
            if self.sourceLabels and #self.sourceLabels > 0 then
                GameTooltip:AddLine(L("sources_prefix", table.concat(self.sourceLabels, ", ")),
                    0.70, 0.66, 0.57, true)
            end
            if self.alternativeRecipes and self.alternativeRecipes > 0 then
                GameTooltip:AddLine(L("additional_recipes", self.alternativeRecipes),
                    0.70, 0.66, 0.57)
            end
            if not (ns.Gamepad and ns.Gamepad:IsLayoutActive()) then
                GameTooltip:AddLine(L("tree_center"), 0.95, 0.72, 0.27)
                GameTooltip:AddLine(L("tree_open"), 0.70, 0.66, 0.57)
            end
        end)
    end)
    button:SetScript("OnLeave", function()
        ns.UI:HideItemTooltip()
        GameTooltip:Hide()
    end)
    button:SetScript("OnClick", function(self)
        if not self.itemID then return end
        ns.UI:HideItemTooltip()
        if IsAltKeyDown and IsAltKeyDown() then
            CraftTree.frame:Hide()
            ns.UI:OpenItem("item:" .. tostring(self.itemID), self.itemID)
        else
            CraftTree:Navigate(self.itemID)
        end
    end)
    self.nodeButtons[index] = button
    return button
end

function CraftTree:ClearCanvas()
    self.usedNodes, self.usedLines, self.usedQuantityBadges = 0, 0, 0
    for _, button in ipairs(self.nodeButtons) do button:Hide() end
    for _, texture in ipairs(self.lineTextures) do texture:Hide() end
    for _, badge in ipairs(self.quantityBadges) do badge:Hide() end
end

function CraftTree:AcquireProfessionButton(index)
    local button = self.professionButtons[index]
    if button then
        button:Show()
        button:ClearAllPoints()
        return button
    end
    button = CreateFrame("Button", nil, self.frame.professionBar, "BackdropTemplate")
    button:SetSize(28, 28)
    setBackdrop(button, { 0.045, 0.035, 0.025, 0.98 })
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 4, -4)
    icon:SetPoint("BOTTOMRIGHT", -4, 4)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetPoint("TOPLEFT", 3, -3)
    highlight:SetPoint("BOTTOMRIGHT", -3, 3)
    highlight:SetColorTexture(1, 0.78, 0.25, 0.16)
    button.icon = icon
    button:SetScript("OnClick", function(self)
        CraftTree:ToggleProfession(self.professionID)
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(self.professionName or L("profession"))
        if self.owned then
            GameTooltip:AddLine(L("player_profession"), 0.95, 0.72, 0.27)
        end
        GameTooltip:AddLine(self.enabled and L("filter_on") or L("filter_off"),
            self.enabled and 0.35 or 0.70,
            self.enabled and 0.90 or 0.66,
            self.enabled and 0.35 or 0.57)
        GameTooltip:AddLine(L("click_toggle"), 0.70, 0.66, 0.57)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self.professionButtons[index] = button
    return button
end

function CraftTree:RenderProfessionFilters()
    local professions = self:OrderedProfessions()
    for index, profession in ipairs(professions) do
        local button = self:AcquireProfessionButton(index)
        button:SetPoint("LEFT", self.frame.professionBar, "LEFT", (index - 1) * 31, 0)
        button.professionID = profession.id
        button.professionName = profession.name
        button.owned = profession.owned
        button.enabled = self.professionFilters[profession.id] == true
        button.icon:SetTexture(profession.icon or 134400)
        if button.icon.SetDesaturated then
            button.icon:SetDesaturated(not button.enabled)
        end
        button.icon:SetAlpha(button.enabled and 1 or 0.34)
        if button.enabled then
            button:SetBackdropBorderColor(unpack(COLORS.gold))
        else
            button:SetBackdropBorderColor(0.30, 0.27, 0.22, 0.90)
        end
    end
    for index = #professions + 1, #self.professionButtons do
        self.professionButtons[index]:Hide()
    end
end

local function nodeNameBefore(left, right)
    if left.name ~= right.name then return left.name < right.name end
    return (left.itemID or 0) < (right.itemID or 0)
end

local function connectedCenter(node, incoming)
    local edges = incoming and node.incoming or node.outgoing
    local total, count = 0, 0
    for _, edge in ipairs(edges or {}) do
        local neighbor = incoming and edge.source or edge.target
        if neighbor.centerY then
            total = total + neighbor.centerY
            count = count + 1
        end
    end
    if count > 0 then return total / count end
end

local function positionDependentColumn(nodes, incoming, canvasHeight)
    local entries = {}
    local fallback = canvasHeight / 2
    for _, node in ipairs(nodes) do
        entries[#entries + 1] = {
            node = node,
            preferred = connectedCenter(node, incoming) or fallback,
        }
    end
    table.sort(entries, function(left, right)
        if left.preferred ~= right.preferred then return left.preferred < right.preferred end
        return nodeNameBefore(left.node, right.node)
    end)
    local step = NODE_HEIGHT + 20
    local centers, preferredTotal, actualTotal = {}, 0, 0
    for index, entry in ipairs(entries) do
        local center = entry.preferred
        if index > 1 then center = math.max(center, centers[index - 1] + step) end
        centers[index] = center
        preferredTotal = preferredTotal + entry.preferred
        actualTotal = actualTotal + center
    end
    if #entries > 0 then
        local shift = (preferredTotal - actualTotal) / #entries
        for index = 1, #centers do centers[index] = centers[index] + shift end
        local minimum = 16 + NODE_HEIGHT / 2
        local maximum = canvasHeight - 16 - NODE_HEIGHT / 2
        if centers[1] < minimum then
            local correction = minimum - centers[1]
            for index = 1, #centers do centers[index] = centers[index] + correction end
        end
        if centers[#centers] > maximum then
            local correction = centers[#centers] - maximum
            for index = 1, #centers do centers[index] = centers[index] - correction end
        end
    end
    for index, entry in ipairs(entries) do
        entry.node.centerY = centers[index]
        entry.node.y = centers[index] - NODE_HEIGHT / 2
    end
end

local function layoutGraphVertically(graph, canvasHeight)
    local anchorLevel, anchorCount = 0, -1
    for level = graph.minimumLevel, graph.maximumLevel do
        local count = #(graph.levels[level] or {})
        if count > anchorCount
                or count == anchorCount and math.abs(level) < math.abs(anchorLevel) then
            anchorLevel, anchorCount = level, count
        end
    end

    local anchorNodes = graph.levels[anchorLevel] or {}
    table.sort(anchorNodes, nodeNameBefore)
    local step = NODE_HEIGHT + 20
    local firstCenter = canvasHeight / 2 - (#anchorNodes - 1) * step / 2
    for index, node in ipairs(anchorNodes) do
        node.centerY = firstCenter + (index - 1) * step
        node.y = node.centerY - NODE_HEIGHT / 2
    end
    for level = anchorLevel + 1, graph.maximumLevel do
        positionDependentColumn(graph.levels[level] or {}, true, canvasHeight)
    end
    for level = anchorLevel - 1, graph.minimumLevel, -1 do
        positionDependentColumn(graph.levels[level] or {}, false, canvasHeight)
    end
end

function CraftTree:Render()
    if not (self.frame and self.frame:IsShown()
            and (self.centerItemID or self.centerRecipe)) then return end
    self:ClearCanvas()
    self:RenderProfessionFilters()
    local graph = self.centerRecipe and self:BuildRecipeGraph(self.centerRecipe)
        or self:BuildGraph(self.centerItemID)
    local canvas, scroll = self.frame.canvas, self.frame.scroll
    local availableWidth = math.max(620, scroll:GetWidth() - 6)
    local columnCount = graph.maximumLevel - graph.minimumLevel + 1
    local minimumGap = columnCount > 1 and 42 or 0
    local nodeWidth = math.floor(
        (availableWidth - 24 - minimumGap * (columnCount - 1)) / columnCount)
    nodeWidth = math.max(112, math.min(184, nodeWidth))
    local gap = 0
    if columnCount > 1 then
        gap = math.floor((availableWidth - 24 - nodeWidth * columnCount) / (columnCount - 1))
        gap = math.max(minimumGap, math.min(110, gap))
    end
    local totalWidth = nodeWidth * columnCount + gap * (columnCount - 1)
    local leftOffset = math.max(12, math.floor((availableWidth - totalWidth) / 2))
    local maximumRows = 1

    for level = graph.minimumLevel, graph.maximumLevel do
        local nodes = graph.levels[level] or {}
        maximumRows = math.max(maximumRows, #nodes)
        local x = leftOffset + (level - graph.minimumLevel) * (nodeWidth + gap)
        for _, node in ipairs(nodes) do
            node.x = x
            node.width = nodeWidth
            node.height = NODE_HEIGHT
        end
    end

    local canvasHeight = math.max(scroll:GetHeight() - 2,
        28 + maximumRows * (NODE_HEIGHT + 20))
    canvas:SetSize(availableWidth, canvasHeight)
    layoutGraphVertically(graph, canvasHeight)

    local laneTotals, laneUsed = {}, {}
    for _, edge in ipairs(graph.edges) do
        local key = tostring(edge.source.level) .. ":" .. tostring(edge.target.level)
        laneTotals[key] = (laneTotals[key] or 0) + 1
    end
    for _, edge in ipairs(graph.edges) do
        local source, target = edge.source, edge.target
        if source.x and target.x then
            local sourceX = source.x + source.width
            local sourceY = source.y + source.height / 2
            local targetX = target.x
            local targetY = target.y + target.height / 2
            local key = tostring(source.level) .. ":" .. tostring(target.level)
            laneUsed[key] = (laneUsed[key] or 0) + 1
            local middleX = self:DrawConnection(sourceX, sourceY, targetX, targetY,
                laneUsed[key], laneTotals[key])
            if edge.quantity and edge.quantity > 0 then
                local badge = self:AcquireQuantityBadge()
                local text = "×" .. tostring(edge.quantity)
                badge.label:SetText(text)
                badge:SetWidth(math.max(24, math.ceil(badge.label:GetStringWidth()) + 10))
                if #(target.incoming or {}) > 1 then
                    badge:SetPoint("CENTER", canvas, "TOPLEFT", sourceX + 13, -sourceY)
                else
                    badge:SetPoint("CENTER", canvas, "TOPLEFT", targetX - 13, -targetY)
                end
            end
        end
    end

    for level = graph.minimumLevel, graph.maximumLevel do
        for _, node in ipairs(graph.levels[level] or {}) do
            local button = self:AcquireNode()
            button:SetSize(node.width, node.height)
            button:SetPoint("TOPLEFT", canvas, "TOPLEFT", node.x, -node.y)
            button.itemID = node.itemID
            button.recipeID = node.recipeID
            button.icon:SetTexture(node.icon or (node.itemID and itemIcon(node.itemID)) or 134400)
            button.name:SetText(node.name)
            for iconIndex, texture in ipairs(button.cornerIcons) do
                local cornerIcon = iconIndex == 1 and (node.professionIcon or node.sourceIcon)
                if cornerIcon then
                    texture:SetTexture(cornerIcon)
                    texture:Show()
                else
                    texture:Hide()
                end
            end
            button.professionName = node.professionName
            button.alternativeRecipes = node.alternativeRecipes
            button.sourceLabels = node.sourceLabels
            if node.isCenter then
                button:SetBackdropBorderColor(unpack(COLORS.gold))
            else
                button:SetBackdropBorderColor(unpack(COLORS.border))
            end
            if node.itemID and C_Item and C_Item.RequestLoadItemDataByID then
                C_Item.RequestLoadItemDataByID(node.itemID)
            end
        end
    end

    self.frame.itemLabel:SetText(self.centerRecipe and self.centerRecipe.name
        or itemName(self.centerItemID))
    self.frame.depthLabel:SetText(L("depth", self.depth))
    setButtonEnabled(self.frame.minusButton, self.depth > 1)
    setButtonEnabled(self.frame.plusButton, self.depth < MAX_DEPTH)
    setButtonEnabled(self.frame.backButton, #self.history > 0)
    local hidden = graph.hiddenNodes + graph.hiddenRecipes
    local hint = L("tree_hint")
    if hidden > 0 then
        hint = hint .. L("hidden_branches", hidden)
    end
    if graph.filteredRecipes > 0 then
        hint = hint .. L("filtered_branches", graph.filteredRecipes)
    end
    self.frame.footer:SetText(hint)
end

function CraftTree:SetDepth(depth)
    depth = math.max(1, math.min(MAX_DEPTH, depth or 1))
    if self.depth == depth then return end
    self.depth = depth
    ForeverpediaDB = ForeverpediaDB or {}
    ForeverpediaDB.craftTreeDepth = depth
    self:Render()
end

function CraftTree:Open(itemID)
    if not self:IsAvailable(itemID) then return false end
    local parent = ns.UI and ns.UI.frame
    if not parent then return false end
    self:Create(parent)
    self.history = {}
    self.centerRecipe = nil
    self.centerItemID = itemID
    self:AutoEnableProductionProfessions(itemID)
    self.frame:Show()
    self.frame:Raise()
    self:Render()
    return true
end

function CraftTree:OpenRecipe(recipe)
    if not self:IsRecipeAvailable(recipe) then return false end
    local parent = ns.UI and ns.UI.frame
    if not parent then return false end
    self:Create(parent)
    self.history = {}
    self.centerItemID = nil
    self.centerRecipe = recipe
    self:EnsureProfessionFilters()
    if recipe.professionID then self.professionFilters[recipe.professionID] = true end
    self.frame:Show()
    self.frame:Raise()
    self:Render()
    return true
end

function CraftTree:Navigate(itemID)
    if not itemID or itemID == self.centerItemID then return end
    self.history[#self.history + 1] = self.centerRecipe
        and { recipe = self.centerRecipe } or self.centerItemID
    if #self.history > 30 then table.remove(self.history, 1) end
    self.centerRecipe = nil
    self.centerItemID = itemID
    self:AutoEnableProductionProfessions(itemID)
    self.frame.scroll:SetVerticalScroll(0)
    self:Render()
end

function CraftTree:GoBack()
    local target = table.remove(self.history)
    if not target then return end
    if type(target) == "table" and target.recipe then
        self.centerItemID = nil
        self.centerRecipe = target.recipe
    else
        self.centerRecipe = nil
        self.centerItemID = target
        self:AutoEnableProductionProfessions(target)
    end
    self.frame.scroll:SetVerticalScroll(0)
    self:Render()
end

function CraftTree:RefreshItem(itemID)
    if not (self.frame and self.frame:IsShown()) then return end
    for _, button in ipairs(self.nodeButtons) do
        if button:IsShown() and button.itemID == itemID then
            button.icon:SetTexture(itemIcon(itemID) or 134400)
            button.name:SetText(itemName(itemID))
        end
    end
    if self.centerItemID == itemID then self.frame.itemLabel:SetText(itemName(itemID)) end
end

