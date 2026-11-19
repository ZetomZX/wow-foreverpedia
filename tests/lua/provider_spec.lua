local root = ...

C_Item = {
    GetItemIDForItemInfo = function(value)
        return tonumber(tostring(value):match("item:(%d+)"))
    end,
    GetItemNameByID = function(id)
        return "Item " .. id
    end,
}
C_AddOns = {
    GetAddOnMetadata = function(_, field)
        if field == "Version" then
            return "1.0.16"
        end
    end,
}
C_Map = {
    GetAreaInfo = function(id)
        return id == 12 and "Elwynn Forest" or nil
    end,
}
C_Spell = {
    GetSpellInfo = function(id)
        return { name = "Spell " .. id }
    end,
}
GetLocale = function() return "ruRU" end

LibQuestieDB = {
    contractVersion = 4,
    Enum = { factionRaceMasks = { Alliance = 1, Horde = 2 } },
    RequireContract = function(required)
        return required == 1, required == 1 and nil or "bad contract"
    end,
}
ItemDB = {
    Exists = function(id) return id == 100 or id == 103 or id == 109 end,
    npcDrops = function(id) return id == 100 and { 10 } or {} end,
    vendors = function(id) return id == 100 and { 11 } or {} end,
    objectDrops = function(id)
        return id == 103 and { 20, 21 } or { 20 }
    end,
    itemDrops = function(id) return id == 100 and { 30 } or {} end,
    questRewards = function(id) return id == 100 and { 40 } or {} end,
    relatedQuests = function(id) return id == 100 and { 41 } or {} end,
    startQuest = function(id) return id == 100 and 42 or nil end,
    teachesSpell = function(id) return id == 100 and 43 or nil end,
    class = function() return 7 end,
    subClass = function() return 9 end,
    name = function(id) return "Item " .. id end,
}
NpcDB = {
    name = function(id) return "NPC " .. id end,
    minLevel = function() return 10 end,
    maxLevel = function() return 12 end,
    zoneID = function() return 12 end,
    spawns = function() return { [12] = { { 10.5, 20.5 } } } end,
}
QuestDB = {
    name = function(id) return "Quest " .. id end,
    startedBy = function() return { { 10 }, { 20 }, {} } end,
    questLevel = function() return 15 end,
    requiredRaces = function() return 1 end,
    zoneOrSort = function() return 12 end,
}
ObjectDB = {
    name = function(id)
        if id == 180656 then return nil end
        return "Object " .. id
    end,
    spawns = function(id)
        if id == 20 then
            return { [12] = { { 30.5, 40.5 }, { 31.5, 41.5 } } }
        end
        return { [12] = { { 32.5, 42.5 } } }
    end,
}

ForeverpediaDB = {
    observations = {},
}

local namespace = {
    DataPackage = {
        manifest = { schema = 3, version = "0.9.3", clientBuild = "1.60.1.70959" },
    },
    ItemSearchData = {
        manifest = { source = "WoW client ItemSparse", version = "1.60.1.70959" },
    },
    RecipeData = {
        manifest = { source = "WoW client DB2", version = "1.60.1.70959" },
        professions = { [186] = "Mining", [197] = "Tailoring", [393] = "Skinning" },
        professionIcons = { [186] = 136248, [197] = 136249, [393] = 134366 },
        ingredients = { [200] = { { 100, 2 }, { 101, 1 } } },
        requirements = { [200] = { 197, 75, 1 } },
        outputs = { [300] = { { 200, 197 } } },
        reagents = { [100] = { { 200, 197, 300, 2 } } },
    },
    ClassAbilityData = {
        manifest = { source = "WoW client DB2", version = "1.60.1.70959" },
        uses = { [100] = { { 3561, 128, 237, 1 } } },
    },
    SourceData = {
        manifest = { source = "QuestieDB", version = "1.0.16" },
        drops = { [100] = { { 12, 25.5, 1, 1 } } },
        fishing = { [101] = { { 12, 18, 1, 1 } } },
        fishingPools = { [102] = { { 180656, 85, 1, 1 } } },
        fishingPoolNames = { [180656] = "Косяк шалфокуня" },
        gathering = { [103] = { { 186, { 20 } } } },
        objects = {
            [100] = { { 20, 40, 1, 2 } },
            [104] = { { 22, 30, 1, 1 } },
        },
        objectNames = { [22] = "Historical Object 22" },
        containers = {
            [100] = { { 30, 50, 1, 1 } },
            [105] = { { 31, 25, 1, 2 } },
        },
        disenchant = {
            [11176] = { { 2, 46, 50, 404, 20, 75, 1, 2 } },
        },
        pickpocket = { [106] = { { 10, 12.5, 1, 1 } } },
        npcNames = { [10] = "Historical NPC 10" },
        spellLoot = { [107] = { { 43, 100, 1, 1 } } },
        mail = { [108] = { { 84, 100, 1, 1 }, { 85, 100, 1, 2 } } },
    },
    QuestieSnapshot = {
        manifest = { source = "QuestieDB", version = "1.0.16" },
        items = { [109] = { [7] = { 45 } } },
        npcs = {}, quests = {}, objects = {},
    },
}

assert(loadfile(root .. "/Foreverpedia/Config.lua"))("Foreverpedia", namespace)
assert(loadfile(root .. "/Foreverpedia/Util.lua"))("Foreverpedia", namespace)
assert(loadfile(root .. "/Foreverpedia/Localization.lua"))("Foreverpedia", namespace)
assert(loadfile(root .. "/Foreverpedia/Storage.lua"))("Foreverpedia", namespace)
local providerChunk = assert(loadfile(root .. "/Foreverpedia/Provider.lua"))
providerChunk("Foreverpedia", namespace)

local ok, message = namespace.DataProvider:Initialize()
assert(ok, message)
assert(namespace.DataProvider:GetItemID("item:100") == 100)

local result = namespace.DataProvider:Get(100)
assert(#result.sources == 6, "expected support-table mob plus five acquisition sources")
assert(#result.uses == 5,
    "expected quest, start quest, taught spell, profession, and class ability uses")
assert(result.sources[1].name == "NPC 12")
assert(result.sources[1].chance == "25.5%")
assert(result.sources[2].zone == "Elwynn Forest")
assert(result.sources[4].kind == "object")
assert(result.uses[4].kind == "profession")
assert(result.uses[4].professionName == "Tailoring")
assert(result.uses[4].professionIcon == 136249)
assert(result.uses[4].requiredProfessionName == "Tailoring")
assert(result.uses[4].requiredSkillRank == 75)
assert(#result.uses[4].ingredients == 2)
assert(result.uses[4].ingredients[1].itemID == 100)
assert(result.uses[4].ingredients[1].quantity == 2)
assert(result.uses[5].kind == "class_ability")
assert(result.uses[5].spellID == 3561)
assert(result.uses[5].classMask == 128)
assert(result.uses[5].className == "Маг")
assert(result.uses[5].quantity == 1)
local questReward
for _, source in ipairs(result.sources) do
    if source.kind == "quest_reward" then questReward = source end
end
assert(questReward and questReward.questLevel == 15)
assert(questReward.questFaction == "Альянс")
assert(#questReward.locations == 2)
assert(namespace.DataProvider:HasCraftRelations(100))
assert(namespace.DataProvider:HasCraftRelations(300))
assert(not namespace.DataProvider:HasCraftRelations(999))
local outputRecipes = namespace.DataProvider:GetCraftRecipesForOutput(300)
assert(#outputRecipes == 1)
assert(outputRecipes[1].professionName == "Tailoring")
assert(#outputRecipes[1].ingredients == 2)
local craftUses = namespace.DataProvider:GetCraftUses(100)
assert(#craftUses == 1)
assert(craftUses[1].outputItemID == 300)
assert(craftUses[1].quantity == 2)

namespace.Storage:SaveObservedRecipe(201, {
    professionID = 197,
    outputItemID = 301,
    outputQuantity = 1,
    ingredients = { { 100, 3 } },
    clientBuild = "70938",
})
local observedResult = namespace.DataProvider:Get(100)
assert(#observedResult.uses == 6)
local observedUse
for _, use in ipairs(observedResult.uses) do
    if use.recipeID == 201 then observedUse = use end
end
assert(observedUse and observedUse.quantity == 3)
assert(observedUse.observedRecipe)
assert(observedUse.provenance:find("70938", 1, true))
local observedOutputs = namespace.DataProvider:GetCraftRecipesForOutput(301)
assert(#observedOutputs == 1)
assert(observedOutputs[1].recipeID == 201)
assert(observedOutputs[1].ingredients[1].itemID == 100)

local openWater = namespace.DataProvider:Get(101)
assert(#openWater.sources == 1)
assert(openWater.sources[1].kind == "fishing")
assert(openWater.sources[1].name == "Открытая вода")
assert(openWater.sources[1].zone == "Elwynn Forest")
assert(openWater.sources[1].chance == "18%")

local pool = namespace.DataProvider:Get(102)
assert(#pool.sources == 1)
assert(pool.sources[1].kind == "fishing")
assert(pool.sources[1].name == "Косяк шалфокуня")
assert(pool.sources[1].entityID == 180656)
assert(pool.sources[1].chance == "85%")

namespace.Storage:Remember(103, "sources", {
    kind = "object", name = "Object 20", entityID = 20, zone = "Elwynn Forest",
})
local gathered = namespace.DataProvider:Get(103)
assert(#gathered.sources == 2, "profession node should be replaced, ordinary object retained")
local gatheredObject, gatheredProfession
for _, source in ipairs(gathered.sources) do
    if source.kind == "object" then gatheredObject = source end
    if source.kind == "gathering" then gatheredProfession = source end
end
assert(gatheredObject and gatheredObject.entityID == 21)
assert(gatheredProfession and gatheredProfession.professionID == 186)
assert(gatheredProfession.professionName == "Mining")
assert(gatheredProfession.sourceCount == 1)
assert(#gatheredProfession.sourceEntityIDs == 1)
assert(gatheredProfession.sourceEntityIDs[1] == 20)
assert(#gatheredProfession.locations == 2)
assert(gatheredProfession.zone == "Elwynn Forest")

local objectSource = namespace.DataProvider:Get(104).sources[1]
assert(objectSource.kind == "object")
assert(objectSource.entityID == 22)
assert(objectSource.chance == "30%")

local containerSource = namespace.DataProvider:Get(105).sources[1]
assert(containerSource.kind == "container")
assert(containerSource.containerItemID == 31)
assert(containerSource.maxQuantity == 2)

local disenchantSource = namespace.DataProvider:Get(11176).sources[1]
assert(disenchantSource.kind == "disenchant")
assert(disenchantSource.name == "Предметы необычного качества, ур. предмета 46–50")
assert(disenchantSource.chance == "20–75%")
assert(disenchantSource.sourceCount == 404)

local pickpocketSource = namespace.DataProvider:Get(106).sources[1]
assert(pickpocketSource.kind == "pickpocket")
assert(pickpocketSource.npcID == 10)
assert(pickpocketSource.chance == "12.5%")

local spellLootSource = namespace.DataProvider:Get(107).sources[1]
assert(spellLootSource.kind == "spell_loot")
assert(spellLootSource.spellID == 43)

local mailSource = namespace.DataProvider:Get(108).sources[1]
assert(mailSource.kind == "mail")
assert(mailSource.maxQuantity == 2)

local status = namespace.DataProvider:GetStatus()
assert(status.version == "1.0.16")
assert(status.contractVersion == 4)
assert(status.cachedItems == 1)
assert(status.dropTableAvailable)

local fallbackQuestUse = namespace.DataProvider:Get(109)
assert(#fallbackQuestUse.uses == 1,
    "snapshot quest-objective relation should supplement live QuestieDB")
assert(fallbackQuestUse.uses[1].questID == 45)

assert(namespace.Util.VersionAtLeast("1.10.0", "1.9.9"))
assert(not namespace.Util.VersionAtLeast("1.9.9", "1.10.0"))

print("Provider runtime spec: OK")

