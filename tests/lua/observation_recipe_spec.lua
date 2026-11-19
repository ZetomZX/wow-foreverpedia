local root = ...

local frame
CreateFrame = function()
    frame = { events = {}, scripts = {} }
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:RegisterUnitEvent(event) self.events[event] = true end
    function frame:SetScript(kind, callback) self.scripts[kind] = callback end
    return frame
end

GetBuildInfo = function() return "1.60.1", "70938", nil, 16001 end
time = function() return 123456 end
C_TradeSkillUI = {
    GetAllRecipeIDs = function() return { 9001 } end,
    GetRecipeOutputItemData = function(recipeID)
        assert(recipeID == 9001)
        return { itemID = 300, quantity = 2 }
    end,
    GetRecipeSchematic = function(recipeID)
        assert(recipeID == 9001)
        return {
            reagentSlotSchematics = {
                { reagents = { { itemID = 100, quantityRequired = 3 } } },
                { reagents = { { itemID = 101, quantityRequired = 1 } } },
            },
        }
    end,
    GetTradeSkillLineForRecipe = function(recipeID)
        assert(recipeID == 9001)
        return 2939, nil, 185
    end,
}

local saved
local namespace = {
    Config = { fishingObservationWindow = 8 },
    RecipeData = { professions = { [185] = "Cooking" }, requirements = {} },
    Storage = {
        SaveObservedRecipe = function(_, recipeID, recipe)
            saved = { id = recipeID, recipe = recipe }
            return true
        end,
    },
}
namespace.L = function(key) return key end

assert(loadfile(root .. "/Foreverpedia/ObservationCollector.lua"))("Foreverpedia", namespace)
assert(frame.events.TRADE_SKILL_LIST_UPDATE)
assert(namespace.ObservationCollector:ScanRecipes() == 1)
assert(saved.id == 9001)
assert(saved.recipe.professionID == 185)
assert(saved.recipe.outputItemID == 300)
assert(saved.recipe.outputQuantity == 2)
assert(saved.recipe.ingredients[1][1] == 100)
assert(saved.recipe.ingredients[1][2] == 3)
assert(saved.recipe.clientBuild == "70938")
assert(saved.recipe.observedAt == 123456)

print("Recipe observation runtime spec: OK")
