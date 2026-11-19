local root = ...

local uses = {}
for recipeID = 1, 10 do
    uses[#uses + 1] = {
        recipeID = recipeID,
        professionID = 333,
        outputItemID = 0,
        outputName = nil,
        quantity = 1,
    }
end
uses[#uses + 1] = {
    recipeID = 20,
    professionID = 197,
    outputItemID = 200,
    outputName = "Alpha",
    quantity = 2,
}
uses[#uses + 1] = {
    recipeID = 21,
    professionID = 197,
    outputItemID = 201,
    outputName = "Beta",
    quantity = 3,
}

local namespace = {
    Config = {
        craftTree = {
            defaultDepth = 2,
            maximumDepth = 2,
            maximumRecipesPerItem = 2,
            maximumOutputsPerItem = 8,
            maximumIngredientsPerRecipe = 8,
            maximumNodesPerColumn = 10,
            nodeHeight = 62,
        },
    },
    Theme = { colors = {}, SetBackdrop = function() end },
    Util = { SetButtonEnabled = function() end },
    L = function(key) return key end,
    GetItemName = function(itemID) return "Item " .. itemID end,
    DataProvider = {
        GetCraftRecipesForOutput = function() return {} end,
        GetCraftUses = function(_, itemID)
            return itemID == 11176 and uses or {}
        end,
        Get = function() return { sources = {}, uses = {} } end,
    },
}

assert(loadfile(root .. "/Foreverpedia/CraftTree.lua"))("Foreverpedia", namespace)
local craftTree = namespace.CraftTree
craftTree.IsProfessionEnabled = function() return true end

local graph = craftTree:BuildGraph(11176)
assert(graph.nodes["1:200"], "a valid output must survive effect-only enchanting recipes")
assert(graph.nodes["1:201"], "all valid outputs below the limit must be shown")
assert(graph.nodes["1:recipe:1"], "effect-only enchanting recipes must be visible")
assert(#graph.edges == 8)
assert(graph.hiddenRecipes == 4, "only recipes beyond the visible limit should be hidden")

local enchantment = {
    recipeID = 13612,
    professionID = 333,
    professionName = "Enchanting",
    professionIcon = "enchant-icon",
    outputItemID = 0,
    name = "Enchant Gloves - Mining",
    ingredients = {
        { itemID = 2772, quantity = 3 },
        { itemID = 10940, quantity = 2 },
    },
}
assert(craftTree:IsRecipeAvailable(enchantment))
local enchantGraph = craftTree:BuildRecipeGraph(enchantment)
assert(enchantGraph.nodes["0:recipe:13612"], "enchantment must have a recipe root")
assert(enchantGraph.nodes["-1:2772"], "first enchantment ingredient must be visible")
assert(enchantGraph.nodes["-1:10940"], "second enchantment ingredient must be visible")
assert(#enchantGraph.edges == 2, "ingredients must connect to the enchantment root")

