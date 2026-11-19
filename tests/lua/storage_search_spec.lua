local root = ...
local namespace = {}

assert(loadfile(root .. "/Foreverpedia/Config.lua"))("Foreverpedia", namespace)
assert(loadfile(root .. "/Foreverpedia/Util.lua"))("Foreverpedia", namespace)
namespace.L = function(key) return key end
namespace.Locale = { GetLanguage = function() return "ruRU" end }
namespace.GetItemSearchItems = function()
    return {
        [1] = { "Ёлка", "елка" },
        [2] = { "Большая ёлка", "большая елка" },
        [3] = { "Ель", "ель" },
    }
end

ForeverpediaDB = nil
assert(loadfile(root .. "/Foreverpedia/Storage.lua"))("Foreverpedia", namespace)
assert(loadfile(root .. "/Foreverpedia/Search.lua"))("Foreverpedia", namespace)

namespace.Storage:Initialize()
namespace.Storage:Remember(1, "sources", {
    kind = "drop", npcID = 10, name = "Creature", zone = "Zone A", quantity = 2,
})
namespace.Storage:Remember(1, "sources", {
    kind = "drop", npcID = 10, name = "Creature", zone = "Zone B", quantity = 4,
})
local record = namespace.Storage:GetObservation(1, false)
assert(#record.sources == 1)
assert(record.sources[1].observedCount == 2)
assert(record.sources[1].minQuantity == 2)
assert(record.sources[1].maxQuantity == 4)

assert(namespace.Storage:SaveObservedRecipe(200, {
    professionID = 197,
    outputItemID = 300,
    outputQuantity = 1,
    ingredients = { { 1, 3 }, { 2, 1 } },
    clientBuild = "70938",
}))
assert(not namespace.Storage:SaveObservedRecipe(200, {
    professionID = 197,
    outputItemID = 300,
    outputQuantity = 1,
    ingredients = { { 1, 3 }, { 2, 1 } },
    clientBuild = "70938",
}))
assert(namespace.Storage:CountObservedRecipes() == 1)
assert(namespace.Storage:GetObservedRecipe(200).outputItemID == 300)
assert(namespace.Storage:GetObservedRecipesForOutput(300)[1] == 200)
assert(namespace.Storage:GetObservedRecipesUsing(1)[1] == 200)

local results = namespace.Search:Find("ЁЛКА", 2)
assert(#results == 2)
assert(results[1].itemID == 1)
assert(results[2].itemID == 2)

print("Storage and search runtime spec: OK")
