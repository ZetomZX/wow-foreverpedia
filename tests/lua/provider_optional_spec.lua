local root = ...

C_Item = {
    GetItemIDForItemInfo = function(value)
        return tonumber(tostring(value):match("item:(%d+)"))
    end,
    GetItemNameByID = function(id) return "Item " .. id end,
}
C_AddOns = { GetAddOnMetadata = function() return nil end }
C_Map = { GetAreaInfo = function(id) return id == 12 and "Elwynn Forest" or nil end }
C_Spell = { GetSpellInfo = function(id) return { name = "Spell " .. id } end }
GetLocale = function() return "ruRU" end
LibQuestieDB, ItemDB, NpcDB, QuestDB, ObjectDB = nil, nil, nil, nil, nil
ForeverpediaDB = { observations = {} }

local namespace = {
    DataPackage = { manifest = { schema = 3, version = "0.9.1" } },
    ItemSearchData = { manifest = { source = "client", version = "1" } },
    RecipeData = {
        manifest = { source = "client", version = "1" },
        professions = {}, professionIcons = {}, ingredients = {}, outputs = {}, reagents = {},
    },
    ClassAbilityData = { manifest = {}, uses = {} },
    SourceData = {
        manifest = { source = "QuestieDB", version = "1.0.16" },
        drops = { [100] = { { 10, 25.5, 0, 0 } } },
        fishing = {}, fishingPools = {}, gathering = {},
    },
    QuestieSnapshot = {
        manifest = { source = "QuestieDB", version = "1.0.16" },
        items = {
            [100] = {
                [1] = { 10 }, [2] = { 20 }, [4] = 42, [5] = { 40 },
                [6] = { 11 }, [7] = { 41 }, [8] = 43, [9] = 7, [10] = 9,
            },
        },
        npcs = {
            [10] = { "NPC 10", "НИП 10", 10, 12, 12 },
            [11] = { "NPC 11", "Торговец 11", 20, 20, 12 },
        },
        quests = {
            [40] = { "Quest 40", "Задание 40", 15, 12 },
            [41] = { "Quest 41", "Задание 41", 16, 12 },
            [42] = { "Quest 42", "Задание 42", 17, 12 },
        },
        objects = { [20] = { "Object 20", "Объект 20", 12 } },
    },
}

assert(loadfile(root .. "/Foreverpedia/Config.lua"))("Foreverpedia", namespace)
assert(loadfile(root .. "/Foreverpedia/Util.lua"))("Foreverpedia", namespace)
assert(loadfile(root .. "/Foreverpedia/Localization.lua"))("Foreverpedia", namespace)
assert(loadfile(root .. "/Foreverpedia/Storage.lua"))("Foreverpedia", namespace)
assert(loadfile(root .. "/Foreverpedia/Provider.lua"))("Foreverpedia", namespace)

local ok, message = namespace.DataProvider:Initialize()
assert(ok, message)
local status = namespace.DataProvider:GetStatus()
assert(status.questieAvailable == false)
assert(status.snapshotVersion == "1.0.16")

local result = namespace.DataProvider:Get(100)
assert(#result.sources == 4, "snapshot should expose drop, vendor, object and quest reward")
assert(#result.uses == 3, "snapshot should expose quest, start quest and taught spell")
assert(result.sources[1].name == "НИП 10")
assert(result.sources[1].chance == "25.5%")
local reward
for _, relation in ipairs(result.sources) do
    if relation.kind == "quest_reward" then reward = relation end
end
assert(reward and reward.name == "Задание 40")
assert(reward.questLevel == 15)
assert(reward.questFaction == nil)
assert(#reward.locations == 0)
assert(namespace.DataProvider:GetManifest().questieAvailable == false)

print("Provider optional QuestieDB spec: OK")
