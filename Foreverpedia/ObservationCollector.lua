local _, ns = ...
local L = ns.L

local Collector = {}
ns.ObservationCollector = Collector

local frame = CreateFrame("Frame")
local lastFishingCast = 0
local fishingSpellName

local function spellName(spellID)
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(spellID)
        return info and info.name
    end
    return GetSpellInfo and GetSpellInfo(spellID)
end

local function isFishingSpell(spellID)
    fishingSpellName = fishingSpellName or spellName(7620)
    return spellID and fishingSpellName and spellName(spellID) == fishingSpellName
end

local function itemIDFromLink(link)
    return link and tonumber(link:match("item:(%d+)"))
end

local function entityFromGUID(guid)
    if not guid then
        return nil, nil
    end
    local kind, _, _, _, _, id = strsplit("-", guid)
    return kind, tonumber(id)
end

local function currentZone()
    if C_Map and C_Map.GetBestMapForUnit and C_Map.GetMapInfo then
        local mapID = C_Map.GetBestMapForUnit("player")
        local info = mapID and C_Map.GetMapInfo(mapID)
        return info and info.name
    end
    return GetZoneText and GetZoneText()
end

local function merchantItemPrice(index)
    if C_MerchantFrame and type(C_MerchantFrame.GetItemInfo) == "function" then
        local info = C_MerchantFrame.GetItemInfo(index)
        return info and info.price, info and info.stackCount
    end
    if type(GetMerchantItemInfo) == "function" then
        local _, _, price, stackCount = GetMerchantItemInfo(index)
        return price, stackCount
    end
    return nil, nil
end

local function npcName(npcID)
    return (NpcDB and NpcDB.name and NpcDB.name(npcID)) or L("npc_number", npcID)
end

local function objectName(objectID)
    return (ObjectDB and ObjectDB.name and ObjectDB.name(objectID))
        or L("object_number", objectID)
end

local function fishingObjectName(objectID)
    if objectID == 35591 then
        return L("open_water")
    end
    return ns.SourceData and ns.SourceData.fishingPoolNames
        and ns.SourceData.fishingPoolNames[objectID]
end

function Collector:ScanLoot()
    local slots = GetNumLootItems and GetNumLootItems() or 0
    local now = GetTime and GetTime() or math.huge
    local recentFishing = now - lastFishingCast < ns.Config.fishingObservationWindow
    for slot = 1, slots do
        local link = GetLootSlotLink(slot)
        local itemID = itemIDFromLink(link)
        if itemID then
            local _, _, quantity = GetLootSlotInfo(slot)
            local sources = { GetLootSourceInfo(slot) }
            local fishingRecorded = false
            for index = 1, #sources, 2 do
                local guid = sources[index]
                local sourceKind, sourceID = entityFromGUID(guid)
                if sourceKind == "Creature" and sourceID then
                    ns.Storage:Remember(itemID, "sources", {
                        kind = "drop",
                        name = npcName(sourceID),
                        npcID = sourceID,
                        zone = currentZone(),
                        quantity = quantity or 1,
                        minQuantity = quantity or 1,
                        maxQuantity = quantity or 1,
                    })
                elseif sourceKind == "GameObject" and sourceID then
                    local fishingName = fishingObjectName(sourceID)
                    fishingRecorded = fishingName ~= nil
                    ns.Storage:Remember(itemID, "sources", {
                        kind = fishingName and "fishing" or "object",
                        name = fishingName or objectName(sourceID),
                        entityID = sourceID,
                        zone = currentZone(),
                        quantity = quantity or 1,
                        minQuantity = quantity or 1,
                        maxQuantity = quantity or 1,
                        waterType = fishingName and (sourceID == 35591
                            and L("open_water") or L("fishing_pool")) or nil,
                    })
                end
            end
            if recentFishing and not fishingRecorded then
                ns.Storage:Remember(itemID, "sources", {
                    kind = "fishing",
                    name = L("open_water"),
                    zone = currentZone(),
                    quantity = quantity or 1,
                    minQuantity = quantity or 1,
                    maxQuantity = quantity or 1,
                    waterType = L("open_water"),
                })
            end
        end
    end
end

function Collector:ScanMerchant()
    local npcGUID = UnitGUID and UnitGUID("npc")
    local _, npcID = entityFromGUID(npcGUID)
    local name = UnitName and UnitName("npc") or (npcID and npcName(npcID))
        or L("unknown_vendor")
    for index = 1, (GetMerchantNumItems and GetMerchantNumItems() or 0) do
        local itemID = itemIDFromLink(GetMerchantItemLink(index))
        if itemID then
            local price, stackCount = merchantItemPrice(index)
            if npcID then
                ns.Storage:SaveVendorPrice(itemID, npcID, price, stackCount, currentZone())
            end
            ns.Storage:Remember(itemID, "sources", {
                kind = "vendor",
                name = name,
                npcID = npcID,
                zone = currentZone(),
                detail = L("merchant_observed"),
            })
        end
    end
end

function Collector:ScanQuestUses(questID)
    if not questID or not C_QuestLog or not C_QuestLog.GetQuestObjectives then
        return
    end
    local questName = (C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(questID))
        or (QuestDB and QuestDB.name and QuestDB.name(questID)) or L("quest_number", questID)
    for _, objective in ipairs(C_QuestLog.GetQuestObjectives(questID) or {}) do
        if objective.type == "item" and objective.objectID then
            ns.Storage:Remember(objective.objectID, "uses", {
                kind = "quest",
                name = questName,
                questID = questID,
                detail = L("quest_item_required"),
            })
        end
    end
end

function Collector:ScanQuestRewards()
    local questID = GetQuestID and GetQuestID()
    if not questID or questID == 0 then
        return
    end
    local questName = GetTitleText and GetTitleText()
        or (QuestDB and QuestDB.name and QuestDB.name(questID)) or L("quest_number", questID)
    for _, rewardType in ipairs({ "reward", "choice" }) do
        local count = rewardType == "reward"
            and (GetNumQuestRewards and GetNumQuestRewards() or 0)
            or (GetNumQuestChoices and GetNumQuestChoices() or 0)
        for index = 1, count do
            local itemID = itemIDFromLink(GetQuestItemLink(rewardType, index))
            if itemID then
                ns.Storage:Remember(itemID, "sources", {
                    kind = "quest_reward",
                    name = questName,
                    questID = questID,
                    zone = currentZone(),
                    detail = L("quest_reward_detail"),
                })
            end
        end
    end
end

local trainerRecipes
local function trainerRecipeIndex()
    if trainerRecipes then
        return trainerRecipes
    end
    trainerRecipes = {}
    local seen = {}
    for _, recipes in pairs(ns.RecipeData and ns.RecipeData.reagents or {}) do
        for _, recipe in ipairs(recipes) do
            local spellID, professionID = recipe[1], recipe[2]
            if not seen[spellID] then
                seen[spellID] = true
                local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
                local name = info and info.name or (GetSpellInfo and GetSpellInfo(spellID))
                local profession = ns.RecipeData.professions[professionID]
                if name and profession then
                    trainerRecipes[profession] = trainerRecipes[profession] or {}
                    trainerRecipes[profession][name] = trainerRecipes[profession][name] or spellID
                end
            end
        end
    end
    return trainerRecipes
end

function Collector:ScanTrainer()
    if not (GetNumTrainerServices and GetTrainerServiceInfo and GetTrainerServiceSkillReq) then
        return
    end
    local _, npcID = entityFromGUID(UnitGUID and UnitGUID("npc"))
    if not npcID then return end
    local index = trainerRecipeIndex()
    for service = 1, GetNumTrainerServices() do
        local recipeName = GetTrainerServiceInfo(service)
        local professionName = GetTrainerServiceSkillReq(service)
        local spellID = professionName and recipeName and index[professionName]
            and index[professionName][recipeName]
        if spellID then
            ns.Storage:SaveTrainer(spellID, npcID, {
                name = UnitName and UnitName("npc") or npcName(npcID),
                zone = currentZone(),
                price = GetTrainerServiceCost and GetTrainerServiceCost(service) or nil,
            })
        end
    end
end

local function call(functionValue, ...)
    if type(functionValue) ~= "function" then return nil end
    local ok, first, second, third = pcall(functionValue, ...)
    if not ok then return nil end
    return first, second, third
end

local function baseProfession(skillLineID, parentSkillLineID)
    local professions = ns.RecipeData and ns.RecipeData.professions or {}
    if professions[skillLineID] then return skillLineID end
    if professions[parentSkillLineID] then return parentSkillLineID end
    return skillLineID or parentSkillLineID or 0
end

local function recipeOutput(ui, recipeID)
    local output = call(ui.GetRecipeOutputItemData, recipeID)
    if type(output) ~= "table" then return nil, 1 end
    local itemID = output.itemID or itemIDFromLink(output.hyperlink or output.itemLink)
    local quantity = output.quantity or output.numItems
        or call(ui.GetRecipeNumItemsProduced, recipeID) or 1
    return itemID, tonumber(quantity) or 1
end

local function schematicIngredients(ui, recipeID)
    local schematic = call(ui.GetRecipeSchematic, recipeID, false)
    if type(schematic) ~= "table" then return nil end
    local ingredients = {}
    for _, slot in ipairs(schematic.reagentSlotSchematics or {}) do
        local reagent = slot.reagents and slot.reagents[1]
        local itemID = reagent and reagent.itemID
        if itemID and itemID ~= 0 then
            ingredients[#ingredients + 1] = {
                itemID,
                tonumber(reagent.quantityRequired or slot.quantityRequired) or 1,
            }
        end
    end
    return #ingredients > 0 and ingredients or nil
end

local function reagentIngredients(ui, recipeID)
    local count = tonumber(call(ui.GetRecipeNumReagents, recipeID)) or 0
    local ingredients = {}
    for index = 1, count do
        local link = call(ui.GetRecipeReagentItemLink, recipeID, index)
        local itemID = itemIDFromLink(link)
        local info, _, quantity = call(ui.GetRecipeReagentInfo, recipeID, index)
        if type(info) == "table" then
            itemID = itemID or info.itemID or itemIDFromLink(info.hyperlink or info.itemLink)
            quantity = info.quantityRequired or info.requiredQuantity or info.quantity
        end
        if itemID then ingredients[#ingredients + 1] = { itemID, tonumber(quantity) or 1 } end
    end
    return ingredients
end

function Collector:ScanRecipes()
    local ui = C_TradeSkillUI
    if not (ui and ui.GetAllRecipeIDs) then return 0 end
    local recipeIDs = call(ui.GetAllRecipeIDs)
    if type(recipeIDs) ~= "table" then return 0 end

    local changed = 0
    local clientBuild = GetBuildInfo and select(2, GetBuildInfo()) or nil
    for _, recipeID in ipairs(recipeIDs) do
        local outputItemID, outputQuantity = recipeOutput(ui, recipeID)
        local ingredients = schematicIngredients(ui, recipeID)
            or reagentIngredients(ui, recipeID)
        local skillLineID, parentSkillLineID
        if ui.GetTradeSkillLineForRecipe then
            local ok, skill, _, parent = pcall(ui.GetTradeSkillLineForRecipe, recipeID)
            if ok then skillLineID, parentSkillLineID = skill, parent end
        end
        local staticRequirement = ns.RecipeData and ns.RecipeData.requirements
            and ns.RecipeData.requirements[recipeID]
        local professionID = baseProfession(skillLineID,
            parentSkillLineID or (staticRequirement and staticRequirement[1]))
        if outputItemID or #ingredients > 0 then
            local saved = ns.Storage:SaveObservedRecipe(recipeID, {
                professionID = professionID,
                outputItemID = outputItemID or 0,
                outputQuantity = outputQuantity,
                ingredients = ingredients,
                clientBuild = clientBuild,
                observedAt = time and time() or nil,
            })
            if saved then changed = changed + 1 end
        end
    end
    return changed
end

frame:RegisterEvent("LOOT_OPENED")
frame:RegisterEvent("MERCHANT_SHOW")
frame:RegisterEvent("QUEST_ACCEPTED")
frame:RegisterEvent("QUEST_COMPLETE")
frame:RegisterEvent("TRAINER_SHOW")
frame:RegisterEvent("TRAINER_UPDATE")
pcall(frame.RegisterEvent, frame, "TRADE_SKILL_LIST_UPDATE")
frame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
local EVENT_HANDLERS = {
    UNIT_SPELLCAST_SUCCEEDED = function(...)
        local spellID = select(3, ...)
        if isFishingSpell(spellID) then
            lastFishingCast = GetTime and GetTime() or 0
        end
    end,
    LOOT_OPENED = function() Collector:ScanLoot() end,
    MERCHANT_SHOW = function() Collector:ScanMerchant() end,
    QUEST_ACCEPTED = function(...)
        local _, questID = ...
        Collector:ScanQuestUses(questID)
    end,
    QUEST_COMPLETE = function() Collector:ScanQuestRewards() end,
    TRAINER_SHOW = function() Collector:ScanTrainer() end,
    TRAINER_UPDATE = function() Collector:ScanTrainer() end,
    TRADE_SKILL_LIST_UPDATE = function()
        if Collector.recipeScanPending then return end
        Collector.recipeScanPending = true
        local function scan()
            Collector.recipeScanPending = nil
            if Collector:ScanRecipes() > 0 and ns.UI and ns.UI.frame
                    and ns.UI.frame:IsShown() then
                ns.UI:Render()
            end
        end
        if C_Timer and C_Timer.After then C_Timer.After(1, scan) else scan() end
    end,
}

frame:SetScript("OnEvent", function(_, event, ...)
    local handler = EVENT_HANDLERS[event]
    if handler then handler(...) end
end)
