local _, ns = ...

local Storage = {}
ns.Storage = Storage

local observedRecipeIndex

local function database()
    ForeverpediaDB = ForeverpediaDB or {}
    ForeverpediaDB.observations = ForeverpediaDB.observations or {}
    ForeverpediaDB.recipeTrainers = ForeverpediaDB.recipeTrainers or {}
    ForeverpediaDB.vendorPrices = ForeverpediaDB.vendorPrices or {}
    ForeverpediaDB.observedRecipes = ForeverpediaDB.observedRecipes or {}
    return ForeverpediaDB
end

function Storage:Initialize()
    local store = database()
    if (store.schema or 0) < ns.Config.savedVariablesSchema
            and store.languageMode ~= "manual" then
        store.languageMode = "auto"
    end

    store.schema = ns.Config.savedVariablesSchema
    store.language = ns.Locale:GetLanguage()
    if store.showMinimapButton == nil then
        store.showMinimapButton = true
    end
    -- Removed settings from pre-0.8 builds must not leak into future behavior.
    store.gamepadChord = nil
    store.gamepadHoldEnabled = nil
    store.craftTreeEnabled = nil
    store.blockedActions = nil
    return store
end

function Storage:CountObservations()
    local count = 0
    for _, record in pairs(database().observations or {}) do
        count = count + #(record.sources or {}) + #(record.uses or {})
    end
    return count
end

function Storage:CountObservedRecipes()
    local count = 0
    for _ in pairs(database().observedRecipes) do count = count + 1 end
    return count
end

function Storage:GetObservedRecipe(recipeID)
    return database().observedRecipes[recipeID]
end

function Storage:GetObservedRecipes()
    return database().observedRecipes
end

local function buildObservedRecipeIndex()
    if observedRecipeIndex then return observedRecipeIndex end
    observedRecipeIndex = { outputs = {}, reagents = {} }
    local function add(collection, itemID, recipeID)
        if not itemID or itemID == 0 then return end
        collection[itemID] = collection[itemID] or {}
        collection[itemID][#collection[itemID] + 1] = recipeID
    end
    for recipeID, recipe in pairs(database().observedRecipes) do
        add(observedRecipeIndex.outputs, recipe.outputItemID, recipeID)
        for _, ingredient in ipairs(recipe.ingredients or {}) do
            add(observedRecipeIndex.reagents, ingredient[1] or ingredient.itemID, recipeID)
        end
    end
    return observedRecipeIndex
end

function Storage:GetObservedRecipesForOutput(itemID)
    return buildObservedRecipeIndex().outputs[itemID] or {}
end

function Storage:GetObservedRecipesUsing(itemID)
    return buildObservedRecipeIndex().reagents[itemID] or {}
end

local function sameIngredients(left, right)
    if #(left or {}) ~= #(right or {}) then return false end
    for index, ingredient in ipairs(left or {}) do
        local other = right[index]
        if not other or (ingredient[1] or ingredient.itemID) ~= (other[1] or other.itemID)
                or (ingredient[2] or ingredient.quantity) ~= (other[2] or other.quantity) then
            return false
        end
    end
    return true
end

function Storage:SaveObservedRecipe(recipeID, recipe)
    if not recipeID or type(recipe) ~= "table" then return false end
    local recipes = database().observedRecipes
    local current = recipes[recipeID]
    if current and current.professionID == recipe.professionID
            and current.outputItemID == recipe.outputItemID
            and current.outputQuantity == recipe.outputQuantity
            and current.clientBuild == recipe.clientBuild
            and sameIngredients(current.ingredients, recipe.ingredients) then
        return false
    end
    recipes[recipeID] = recipe
    observedRecipeIndex = nil
    return true
end

function Storage:GetObservation(itemID, create)
    local observations = database().observations
    local record = observations[itemID]
    if not record and create then
        record = { sources = {}, uses = {} }
        observations[itemID] = record
    end
    return record
end

function Storage:GetRecipeTrainers(recipeID)
    return database().recipeTrainers[recipeID]
end

function Storage:GetVendorPrice(itemID, npcID)
    local itemPrices = database().vendorPrices[itemID]
    return itemPrices and itemPrices[npcID]
end

function Storage:Remember(itemID, collection, relation)
    local record = self:GetObservation(itemID, true)
    local target = record[collection]
    local function observationKey(value)
        return ns.Util.Key(value.kind, value.npcID, value.entityID, value.questID, value.name)
    end
    local key = observationKey(relation)
    for _, current in ipairs(target) do
        if observationKey(current) == key then
            current.observedCount = (current.observedCount or 1) + 1
            if relation.quantity then
                current.minQuantity = math.min(current.minQuantity or relation.quantity,
                    relation.quantity)
                current.maxQuantity = math.max(current.maxQuantity or relation.quantity,
                    relation.quantity)
            end
            current.zone = current.zone or relation.zone
            return current
        end
    end

    relation.observed = true
    relation.observedCount = 1
    relation.provenance = ns.L("local_observation")
    if relation.quantity then
        relation.minQuantity = relation.minQuantity or relation.quantity
        relation.maxQuantity = relation.maxQuantity or relation.quantity
    end
    target[#target + 1] = relation
    return relation
end

function Storage:SaveVendorPrice(itemID, npcID, price, stack, zone)
    if not npcID then return end
    local prices = database().vendorPrices
    prices[itemID] = prices[itemID] or {}
    prices[itemID][npcID] = { price = price, stack = stack, zone = zone }
end

function Storage:SaveTrainer(recipeID, npcID, trainer)
    if not recipeID or not npcID then return end
    local trainers = database().recipeTrainers
    trainers[recipeID] = trainers[recipeID] or {}
    trainers[recipeID][npcID] = trainer
end
