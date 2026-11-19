local _, ns = ...
local L = ns.L
local Util = ns.Util

local Provider = {
    REQUIRED_CONTRACT = ns.Config.questieContract,
    MIN_QUESTIEDB_VERSION = ns.Config.minimumQuestieVersion,
    REQUIRED_DATA_SCHEMA = ns.Config.dataSchema,
    MIN_DATA_VERSION = ns.Config.minimumDataVersion,
    questieCache = {},
    questieCacheSize = 0,
    -- New adapters only need to return relation arrays and register here.
    RELATION_READERS = {
        { method = "ReadRecipes", collection = "uses" },
        { method = "ReadClassAbilityUses", collection = "uses" },
        { method = "ReadCraftSources", collection = "sources" },
        { method = "ReadFishingSources", collection = "sources" },
        { method = "ReadGatheringSources", collection = "sources" },
        { method = "ReadObjectSources", collection = "sources" },
        { method = "ReadContainerSources", collection = "sources" },
        { method = "ReadDisenchantSources", collection = "sources" },
        { method = "ReadPickpocketSources", collection = "sources" },
        { method = "ReadSpellLootSources", collection = "sources" },
        { method = "ReadMailSources", collection = "sources" },
    },
}
ns.DataProvider = Provider

-- QuestieDB is optional. These locals are bound either to its full API or to
-- compact read-only facades over Foreverpedia_Data during Initialize().
local ItemDB, NpcDB, QuestDB, ObjectDB

local EMPTY_ITEM = {
    sources = {},
    uses = {},
}

local function addonMetadata(field)
    if C_AddOns and C_AddOns.GetAddOnMetadata then
        return C_AddOns.GetAddOnMetadata("QuestieDB", field)
    end
end

local function localizedSnapshotName(row)
    if not row then return nil end
    return ns.Locale:GetLanguage() == "ruRU" and (row[2] or row[1]) or row[1]
end

local function createSnapshotDatabases(snapshot)
    local items = snapshot.items or {}
    local npcs = snapshot.npcs or {}
    local quests = snapshot.quests or {}
    local objects = snapshot.objects or {}
    local function itemField(index, empty)
        return function(id)
            local row = items[id]
            return row and row[index] or empty
        end
    end
    local item = {
        Exists = function(id) return items[id] ~= nil end,
        npcDrops = itemField(1, {}), objectDrops = itemField(2, {}),
        itemDrops = itemField(3, {}), startQuest = itemField(4),
        questRewards = itemField(5, {}), vendors = itemField(6, {}),
        relatedQuests = itemField(7, {}), teachesSpell = itemField(8),
        class = itemField(9), subClass = itemField(10),
        name = function(id) return ns.GetItemName(id) end,
    }
    local npc = {
        name = function(id) return localizedSnapshotName(npcs[id]) end,
        minLevel = function(id) return npcs[id] and npcs[id][3] end,
        maxLevel = function(id) return npcs[id] and npcs[id][4] end,
        zoneID = function(id) return npcs[id] and npcs[id][5] end,
        spawns = function() return nil end,
    }
    local quest = {
        name = function(id) return localizedSnapshotName(quests[id]) end,
        questLevel = function(id) return quests[id] and quests[id][3] end,
        zoneOrSort = function(id) return quests[id] and quests[id][4] end,
        requiredRaces = function() return nil end,
        startedBy = function() return {} end,
    }
    local object = {
        name = function(id) return localizedSnapshotName(objects[id]) end,
        zoneID = function(id) return objects[id] and objects[id][3] end,
        spawns = function() return nil end,
    }
    return item, npc, quest, object
end

local function fallbackName(prefix, id)
    return string.format("%s #%d", prefix, id)
end

local function npcName(npcID)
    local recipeName = ns.RecipeData and ns.RecipeData.trainerNames
        and ns.RecipeData.trainerNames[npcID]
    return NpcDB.name(npcID)
        or localizedSnapshotName(recipeName)
        or (ns.SourceData and ns.SourceData.npcNames
            and ns.SourceData.npcNames[npcID])
end

local function areaName(areaID)
    if areaID and areaID ~= 0 and C_Map and C_Map.GetAreaInfo then
        return C_Map.GetAreaInfo(areaID)
    end
end

local function npcDetail(npcID)
    local minimum = NpcDB.minLevel(npcID)
    local maximum = NpcDB.maxLevel(npcID)
    if not minimum or minimum == 0 then
        return nil
    end
    if not maximum or maximum == 0 or minimum == maximum then
        return L("level", minimum)
    end
    return L("level_range", minimum, maximum)
end

local function npcZone(npcID)
    return areaName(NpcDB.zoneID(npcID))
end

local function entityLocations(database, entityID)
    local result = {}
    local spawns = database and database.spawns and database.spawns(entityID)
    for areaID, coordinates in pairs(spawns or {}) do
        for _, coordinate in ipairs(coordinates or {}) do
            result[#result + 1] = {
                areaID = areaID,
                zone = areaName(areaID),
                x = coordinate[1],
                y = coordinate[2],
            }
        end
    end
    table.sort(result, function(left, right)
        if left.areaID == right.areaID then
            if left.x == right.x then
                return (left.y or 0) < (right.y or 0)
            end
            return (left.x or 0) < (right.x or 0)
        end
        return left.areaID < right.areaID
    end)
    return result
end

local function gatheringSourceRows(itemID)
    return ns.SourceData and ns.SourceData.gathering
        and ns.SourceData.gathering[itemID]
end

local function gatheringObjectIDs(itemID)
    local result = {}
    for _, source in ipairs(gatheringSourceRows(itemID) or {}) do
        local professionID, entityIDs = unpack(source)
        -- Skinning sources are creatures. Every other gathering source in the
        -- generated index is a game object and may also occur in objectDrops.
        if professionID ~= 393 and type(entityIDs) == "table" then
            for _, entityID in ipairs(entityIDs) do
                result[entityID] = true
            end
        end
    end
    return result
end

local function removeGatheringObjects(sources, itemID)
    local objectIDs = gatheringObjectIDs(itemID)
    for index = #sources, 1, -1 do
        local relation = sources[index]
        if (relation.kind == "object" or relation.kind == "herb")
                and relation.entityID and objectIDs[relation.entityID] then
            table.remove(sources, index)
        end
    end
end

local function itemName(itemID)
    if itemID == 0 then
        return nil
    end
    if ns.GetItemName then return ns.GetItemName(itemID) end
    return ItemDB.name(itemID) or fallbackName(L("item"), itemID)
end

local function spellName(spellID)
    if spellID == 0 then
        return nil
    end
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(spellID)
        if info and info.name then
            return info.name
        end
    end
    return fallbackName(L("spell"), spellID)
end

local function recipeIngredients(recipeID)
    local result = {}
    local observed = ns.Storage and ns.Storage:GetObservedRecipe(recipeID)
    local ingredients = observed and observed.ingredients
    if not ingredients or #ingredients == 0 then
        ingredients = ns.RecipeData and ns.RecipeData.ingredients
            and ns.RecipeData.ingredients[recipeID]
    end
    for _, ingredient in ipairs(ingredients or {}) do
        result[#result + 1] = {
            itemID = ingredient[1],
            quantity = ingredient[2],
        }
    end
    return result
end

local function recipeRelation(recipeID, professionID, outputItemID)
    local observed = ns.Storage and ns.Storage:GetObservedRecipe(recipeID)
    if observed then
        if observed.professionID and observed.professionID ~= 0 then
            professionID = observed.professionID
        end
        if observed.outputItemID and observed.outputItemID ~= 0 then
            outputItemID = observed.outputItemID
        end
    end
    local relation = {
        recipeID = recipeID,
        name = spellName(recipeID),
        professionID = professionID,
        professionName = ns.GetProfessionName(professionID),
        professionIcon = ns.RecipeData.professionIcons[professionID],
        outputItemID = outputItemID,
        ingredients = recipeIngredients(recipeID),
        outputQuantity = observed and observed.outputQuantity or nil,
        observedRecipe = observed ~= nil,
        observedBuild = observed and observed.clientBuild or nil,
    }
    local requirement = ns.RecipeData and ns.RecipeData.requirements
        and ns.RecipeData.requirements[recipeID]
    if requirement then
        relation.requiredProfessionID = requirement[1]
        relation.requiredProfessionName = ns.GetProfessionName(requirement[1])
        relation.requiredSkillRank = requirement[2]
        relation.requirementSource = requirement[3]
    end
    return relation
end

local function recipeUseRows(itemID)
    local rows = {}
    for _, recipe in ipairs(ns.RecipeData and ns.RecipeData.reagents
            and ns.RecipeData.reagents[itemID] or {}) do
        rows[recipe[1]] = recipe
    end
    for _, recipeID in ipairs(ns.Storage:GetObservedRecipesUsing(itemID)) do
        local observed = ns.Storage:GetObservedRecipe(recipeID)
        local quantity = 1
        for _, ingredient in ipairs(observed and observed.ingredients or {}) do
            if (ingredient[1] or ingredient.itemID) == itemID then
                quantity = ingredient[2] or ingredient.quantity or 1
                break
            end
        end
        rows[recipeID] = {
            recipeID,
            observed and observed.professionID or 0,
            observed and observed.outputItemID or 0,
            quantity,
        }
    end
    local result = {}
    for _, recipe in pairs(rows) do result[#result + 1] = recipe end
    table.sort(result, function(left, right) return left[1] < right[1] end)
    return result
end

local function recipeOutputRows(itemID)
    local rows = {}
    for _, recipe in ipairs(ns.RecipeData and ns.RecipeData.outputs
            and ns.RecipeData.outputs[itemID] or {}) do
        rows[recipe[1]] = recipe
    end
    for _, recipeID in ipairs(ns.Storage:GetObservedRecipesForOutput(itemID)) do
        local observed = ns.Storage:GetObservedRecipe(recipeID)
        rows[recipeID] = { recipeID, observed and observed.professionID or 0 }
    end
    local result = {}
    for _, recipe in pairs(rows) do result[#result + 1] = recipe end
    table.sort(result, function(left, right) return left[1] < right[1] end)
    return result
end

local function addNpcSources(target, ids, kind, detailPrefix, provenance, seen)
    for _, npcID in ipairs(ids or {}) do
        if not seen or not seen[npcID] then
            local detail = npcDetail(npcID)
            if detailPrefix then
                detail = detail and (detailPrefix .. " · " .. detail) or detailPrefix
            end
            target[#target + 1] = {
                kind = kind,
                name = npcName(npcID) or fallbackName("NPC", npcID),
                detail = detail,
                zone = npcZone(npcID),
                provenance = provenance,
                npcID = npcID,
                locations = entityLocations(NpcDB, npcID),
            }
            if seen then
                seen[npcID] = true
            end
        end
    end
end

local function formattedChance(value)
    if not value then
        return nil
    end
    local text = string.format("%.2f", value):gsub("0+$", ""):gsub("%.$", "")
    return text .. "%"
end

local function formattedChanceRange(minimum, maximum)
    if not minimum or minimum <= 0 then return nil end
    if not maximum or maximum <= minimum then return formattedChance(minimum) end
    return string.format("%s–%s", formattedChance(minimum):gsub("%%$", ""),
        formattedChance(maximum))
end

local function addDropTableSources(target, drops, provenance, seen)
    for _, drop in ipairs(drops or {}) do
        local npcID, chance, minimum, maximum = unpack(drop)
        target[#target + 1] = {
            kind = "drop",
            name = npcName(npcID) or fallbackName("NPC", npcID),
            detail = npcDetail(npcID),
            zone = npcZone(npcID),
            chance = formattedChance(chance),
            chanceValue = chance,
            minQuantity = minimum,
            maxQuantity = maximum,
            provenance = provenance,
            npcID = npcID,
            locations = entityLocations(NpcDB, npcID),
        }
        seen[npcID] = true
    end
end

local function mergeObservedSources(target, additions)
    local function sourceKey(relation)
        return Util.Key(relation.kind, relation.npcID, relation.entityID, relation.name)
    end
    local existing = {}
    for _, relation in ipairs(target) do
        existing[sourceKey(relation)] = relation
    end
    for _, relation in ipairs(additions or {}) do
        local key = sourceKey(relation)
        local current = existing[key]
        if current then
            current.minQuantity = relation.minQuantity or current.minQuantity
            current.maxQuantity = relation.maxQuantity or current.maxQuantity
            current.zone = current.zone or relation.zone
            current.observedCount = relation.observedCount or current.observedCount
        else
            target[#target + 1] = relation
            existing[key] = relation
        end
    end
end

local function acquisitionSourceKey(relation)
    local hasStableID = relation.npcID or relation.entityID or relation.questID
        or relation.spellID or relation.mailTemplateID
    return Util.Key(
        relation.kind,
        relation.npcID,
        relation.entityID,
        relation.questID,
        relation.spellID,
        relation.mailTemplateID,
        hasStableID and nil or relation.name,
        hasStableID and nil or relation.detail,
        hasStableID and nil or relation.zone
    )
end

local function mergeGeneratedSources(target, additions)
    local existing = {}
    for _, relation in ipairs(target) do
        existing[acquisitionSourceKey(relation)] = relation
    end
    for _, relation in ipairs(additions or {}) do
        local key = acquisitionSourceKey(relation)
        local current = existing[key]
        if current then
            current.chance = current.chance or relation.chance
            current.chanceValue = current.chanceValue or relation.chanceValue
            current.minQuantity = current.minQuantity or relation.minQuantity
            current.maxQuantity = current.maxQuantity or relation.maxQuantity
            current.detail = current.detail or relation.detail
            current.zone = current.zone or relation.zone
            if (not current.locations or #current.locations == 0)
                    and relation.locations and #relation.locations > 0 then
                current.locations = relation.locations
            end
        else
            target[#target + 1] = relation
            existing[key] = relation
        end
    end
end

local function sortDrops(sources)
    local drops, other = {}, {}
    for _, relation in ipairs(sources) do
        if relation.kind == "drop" then
            drops[#drops + 1] = relation
        else
            other[#other + 1] = relation
        end
    end
    table.sort(drops, function(left, right)
        local leftChance, rightChance = left.chanceValue or -1, right.chanceValue or -1
        if leftChance == rightChance then
            return (left.name or "") < (right.name or "")
        end
        return leftChance > rightChance
    end)
    local result = {}
    for _, relation in ipairs(drops) do
        result[#result + 1] = relation
    end
    for _, relation in ipairs(other) do
        result[#result + 1] = relation
    end
    return result
end

local questDetailCache = {}

local function maskContains(mask, required)
    if not mask or not required then return false end
    local bitLibrary = rawget(_G, "bit") or rawget(_G, "bit32")
    if bitLibrary and type(bitLibrary.band) == "function" then
        return bitLibrary.band(mask, required) ~= 0
    end
    return mask == required
end

local function questFaction(questID)
    if not Provider.questieAvailable then return nil end
    local requiredRaces = QuestDB.requiredRaces and QuestDB.requiredRaces(questID)
    if not requiredRaces or requiredRaces == 0 then return L("both_factions") end
    local enum = LibQuestieDB and LibQuestieDB.Enum
    local masks = (enum and enum.factionRaceMasks)
        or (LibQuestieDB and LibQuestieDB.factionRaceMasks)
    if not masks then return L("special_requirements") end
    local alliance = maskContains(requiredRaces, masks.Alliance)
    local horde = maskContains(requiredRaces, masks.Horde)
    if alliance and horde then return L("both_factions") end
    if alliance then return L("alliance") end
    if horde then return L("horde") end
    return L("special_requirements")
end

local function questDetails(questID)
    local cached = questDetailCache[questID]
    if cached then return cached end
    local result = {
        questLevel = QuestDB.questLevel and QuestDB.questLevel(questID),
        questFaction = questFaction(questID),
        locations = {},
        starterNames = {},
    }
    local seenLocations, seenStarters = {}, {}
    local startedBy = QuestDB.startedBy and QuestDB.startedBy(questID) or {}
    local function addStarters(ids, database, prefix)
        for _, entityID in ipairs(ids or {}) do
            local name = database.name(entityID) or fallbackName(prefix, entityID)
            if not seenStarters[name] then
                result.starterNames[#result.starterNames + 1] = name
                seenStarters[name] = true
            end
            for _, location in ipairs(entityLocations(database, entityID)) do
                local key = Util.Key(location.areaID, location.x, location.y)
                if not seenLocations[key] then
                    result.locations[#result.locations + 1] = location
                    seenLocations[key] = true
                end
            end
        end
    end
    addStarters(startedBy[1], NpcDB, "NPC")
    addStarters(startedBy[2], ObjectDB, L("object"))
    for _, itemID in ipairs(startedBy[3] or {}) do
        local name = itemName(itemID) or fallbackName(L("item"), itemID)
        if not seenStarters[name] then
            result.starterNames[#result.starterNames + 1] = name
            seenStarters[name] = true
        end
    end
    table.sort(result.starterNames)
    result.zone = result.locations[1] and result.locations[1].zone or nil
    if not result.zone and QuestDB.zoneOrSort then
        local zoneID = QuestDB.zoneOrSort(questID)
        result.zone = zoneID and zoneID > 0 and areaName(zoneID) or nil
    end
    questDetailCache[questID] = result
    return result
end

local function applyQuestDetails(relation, questID)
    local details = questDetails(questID)
    relation.questID = questID
    relation.questLevel = details.questLevel
    relation.questFaction = details.questFaction
    relation.locations = details.locations
    relation.starterNames = details.starterNames
    relation.zone = details.zone or relation.zone
    return relation
end

local function addNamedRelations(target, ids, database, kind, detail, prefix, provenance)
    local seenIDs = {}
    for _, id in ipairs(ids or {}) do
        local name = database.name(id) or fallbackName(prefix, id)
        if not seenIDs[id] then
            local zoneID
            if database.zoneID then
                zoneID = database.zoneID(id)
            elseif database.zoneOrSort then
                local value = database.zoneOrSort(id)
                zoneID = value and value > 0 and value or nil
            end
            local relation = {
                kind = kind,
                name = name,
                detail = detail,
                zone = areaName(zoneID),
                provenance = provenance,
                entityID = id,
                locations = database.spawns and entityLocations(database, id) or nil,
                questID = (kind == "quest" or kind == "quest_reward") and id or nil,
            }
            if relation.questID then applyQuestDetails(relation, relation.questID) end
            target[#target + 1] = relation
            seenIDs[id] = true
        end
    end
end

local function recipeLearningSources(recipeID)
    local result, seen = {}, {}
    local function add(source, identity)
        identity = identity or Util.Key(source.kind, source.npcID, source.entityID, source.name)
        if not seen[identity] then
            result[#result + 1] = source
            seen[identity] = true
        end
    end

    local observed = ns.Storage:GetRecipeTrainers(recipeID)
    for npcID, trainer in pairs(observed or {}) do
        add({
            kind = "trainer",
            name = trainer.name or npcName(npcID) or fallbackName("NPC", npcID),
            zone = trainer.zone or npcZone(npcID),
            npcID = npcID,
            locations = entityLocations(NpcDB, npcID),
            price = trainer.price,
            observed = true,
        }, "trainer:" .. npcID)
    end

    local learning = ns.RecipeData.learning and ns.RecipeData.learning[recipeID]
    for _, trainerData in ipairs(learning and learning.trainers or {}) do
        local npcID, trainingPrice = unpack(trainerData)
        add({
            kind = "trainer",
            name = npcName(npcID) or fallbackName("NPC", npcID),
            zone = npcZone(npcID),
            npcID = npcID,
            locations = entityLocations(NpcDB, npcID),
            price = trainingPrice,
            historical = true,
        }, "trainer:" .. npcID)
    end

    for _, itemData in ipairs(learning and learning.items or {}) do
        local recipeItemID, buyPrice, vendorStack = unpack(itemData)
        local recipeItemName = itemName(recipeItemID) or fallbackName(L("recipe"), recipeItemID)
        local found = false
        for _, npcID in ipairs(ItemDB.vendors(recipeItemID) or {}) do
            found = true
            local observedPrice = ns.Storage:GetVendorPrice(recipeItemID, npcID)
            add({ kind = "recipe_vendor", name = npcName(npcID) or fallbackName("NPC", npcID),
                zone = (observedPrice and observedPrice.zone) or npcZone(npcID), npcID = npcID,
                recipeItemID = recipeItemID, recipeItemName = recipeItemName,
                locations = entityLocations(NpcDB, npcID),
                price = (observedPrice and observedPrice.price) or buyPrice,
                vendorStack = (observedPrice and observedPrice.stack) or vendorStack },
                "vendor:" .. npcID .. ":" .. recipeItemID)
        end
        for _, npcID in ipairs(ItemDB.npcDrops(recipeItemID) or {}) do
            found = true
            add({ kind = "recipe_drop", name = npcName(npcID) or fallbackName("NPC", npcID),
                zone = npcZone(npcID), npcID = npcID, recipeItemID = recipeItemID,
                recipeItemName = recipeItemName, locations = entityLocations(NpcDB, npcID) },
                "drop:" .. npcID .. ":" .. recipeItemID)
        end
        for _, objectID in ipairs(ItemDB.objectDrops(recipeItemID) or {}) do
            found = true
            add({ kind = "recipe_object",
                name = ObjectDB.name(objectID) or fallbackName(L("object"), objectID),
                zone = areaName(ObjectDB.zoneID(objectID)), entityID = objectID,
                recipeItemID = recipeItemID, recipeItemName = recipeItemName,
                locations = entityLocations(ObjectDB, objectID) },
                "object:" .. objectID .. ":" .. recipeItemID)
        end
        for _, questID in ipairs(ItemDB.questRewards(recipeItemID) or {}) do
            found = true
            local zone = QuestDB.zoneOrSort(questID)
            add(applyQuestDetails({ kind = "recipe_quest",
                name = QuestDB.name(questID) or fallbackName(L("quest"), questID),
                zone = zone and zone > 0 and areaName(zone) or nil, questID = questID,
                recipeItemID = recipeItemID, recipeItemName = recipeItemName }, questID),
                "quest:" .. questID .. ":" .. recipeItemID)
        end
        local observedRecord = ns.Storage:GetObservation(recipeItemID, false)
        for _, observedSource in ipairs(observedRecord and observedRecord.sources or {}) do
            local observedKind = ({
                vendor = "recipe_vendor",
                drop = "recipe_drop",
                object = "recipe_object",
            })[observedSource.kind]
            if observedKind then
                found = true
                local npcID, objectID = observedSource.npcID, observedSource.entityID
                local observedPrice = npcID
                    and ns.Storage:GetVendorPrice(recipeItemID, npcID)
                local identity = observedKind == "recipe_vendor"
                    and ("vendor:" .. tostring(npcID) .. ":" .. recipeItemID)
                    or observedKind == "recipe_drop"
                        and ("drop:" .. tostring(npcID) .. ":" .. recipeItemID)
                    or ("object:" .. tostring(objectID) .. ":" .. recipeItemID)
                add({
                    kind = observedKind,
                    name = observedSource.name,
                    zone = observedSource.zone,
                    npcID = npcID,
                    entityID = objectID,
                    recipeItemID = recipeItemID,
                    recipeItemName = recipeItemName,
                    locations = npcID and entityLocations(NpcDB, npcID)
                        or objectID and entityLocations(ObjectDB, objectID) or nil,
                    price = observedPrice and observedPrice.price,
                    vendorStack = observedPrice and observedPrice.stack,
                    observed = true,
                }, identity)
            end
        end
        if not found then
            add({ kind = "recipe_unknown", name = L("source_undefined"),
                recipeItemID = recipeItemID, recipeItemName = recipeItemName },
                "item:" .. recipeItemID)
        end
    end
    table.sort(result, function(left, right)
        if left.kind == right.kind then
            return (left.zone or "") .. (left.name or "") < (right.zone or "") .. (right.name or "")
        end
        return left.kind < right.kind
    end)
    return result
end

function Provider:GetItemID(itemInfo)
    if type(itemInfo) == "number" then
        return itemInfo
    end

    if C_Item and C_Item.GetItemIDForItemInfo then
        local itemID = C_Item.GetItemIDForItemInfo(itemInfo)
        if itemID then
            return itemID
        end
    end

    if type(itemInfo) == "string" then
        return tonumber(itemInfo:match("item:(%d+)")) or tonumber(itemInfo)
    end
end

function Provider:Initialize()
    if not ns.DataPackage or not ns.ItemSearchData or not ns.RecipeData
            or not ns.SourceData or not ns.QuestieSnapshot then
        return false, L("data_missing")
    end
    local dataManifest = ns.DataPackage.manifest
    if not dataManifest or dataManifest.schema ~= self.REQUIRED_DATA_SCHEMA then
        return false, L("data_schema_incompatible")
    end
    if not Util.VersionAtLeast(dataManifest.version, self.MIN_DATA_VERSION) then
        return false, L("data_version_required",
            self.MIN_DATA_VERSION,
            dataManifest.version or L("unknown_version")
        )
    end

    local liveItem = rawget(_G, "ItemDB")
    local liveNpc = rawget(_G, "NpcDB")
    local liveQuest = rawget(_G, "QuestDB")
    local liveObject = rawget(_G, "ObjectDB")
    local version = addonMetadata("Version")
    local compatible = LibQuestieDB and type(LibQuestieDB.RequireContract) == "function"
        and liveItem and liveNpc and liveQuest and liveObject
        and Util.VersionAtLeast(version, self.MIN_QUESTIEDB_VERSION)
        and select(1, LibQuestieDB.RequireContract(self.REQUIRED_CONTRACT))
    if compatible then
        ItemDB, NpcDB, QuestDB, ObjectDB = liveItem, liveNpc, liveQuest, liveObject
        self.questieAvailable = true
        self.questieVersion = version
        self.contractVersion = LibQuestieDB.contractVersion
    else
        ItemDB, NpcDB, QuestDB, ObjectDB = createSnapshotDatabases(ns.QuestieSnapshot)
        self.questieAvailable = false
        self.questieVersion = nil
        self.contractVersion = nil
    end
    return true
end

function Provider:ReadQuestie(itemID)
    local cached = self.questieCache[itemID]
    if cached then
        return cached
    end

    local snapshotItem = ns.QuestieSnapshot and ns.QuestieSnapshot.items
        and ns.QuestieSnapshot.items[itemID]
    local indexedDrops = ns.SourceData and ns.SourceData.drops
        and ns.SourceData.drops[itemID]
    if not ItemDB.Exists(itemID) and not indexedDrops and not snapshotItem then
        return EMPTY_ITEM
    end

    local provenance = self.questieAvailable
        and ("QuestieDB " .. (self.questieVersion or "unknown"))
        or ("Foreverpedia snapshot " .. (ns.QuestieSnapshot.manifest.version or "unknown"))
    local result = {
        sources = {},
        uses = {},
    }

    local seenDropNpcs = {}
    addDropTableSources(result.sources,
        indexedDrops,
        provenance, seenDropNpcs)
    addNpcSources(result.sources, ItemDB.npcDrops(itemID), "drop", nil, provenance,
        seenDropNpcs)
    addNpcSources(result.sources, ItemDB.vendors(itemID), "vendor", L("sells_item"), provenance)
    -- A herb item does not make every object containing it a herb node. Real
    -- profession nodes are identified by the generated gathering index below;
    -- all remaining entries are ordinary lootable objects.
    addNamedRelations(result.sources, ItemDB.objectDrops(itemID), ObjectDB, "object",
        L("looted_object"), L("object"), provenance)
    removeGatheringObjects(result.sources, itemID)
    addNamedRelations(result.sources, ItemDB.itemDrops(itemID), ItemDB, "container",
        L("may_contain"), L("item"), provenance)
    addNamedRelations(result.sources, ItemDB.questRewards(itemID), QuestDB, "quest_reward",
        L("quest_reward_detail"), L("quest"), provenance)

    local relatedQuests = {}
    local seenRelatedQuests = {}
    for _, questID in ipairs(ItemDB.relatedQuests(itemID) or {}) do
        if not seenRelatedQuests[questID] then
            relatedQuests[#relatedQuests + 1] = questID
            seenRelatedQuests[questID] = true
        end
    end
    -- QuestieDB 1.0.16 leaves many Item.relatedQuests rows incomplete. The
    -- shipped snapshot reverse-indexes Quest.objectives, so retain it as a
    -- fallback even when the full optional QuestieDB addon is active.
    for _, questID in ipairs(snapshotItem and snapshotItem[7] or {}) do
        if not seenRelatedQuests[questID] then
            relatedQuests[#relatedQuests + 1] = questID
            seenRelatedQuests[questID] = true
        end
    end
    table.sort(relatedQuests)
    addNamedRelations(result.uses, relatedQuests, QuestDB, "quest",
        L("quest_related"), L("quest"), provenance)

    local startQuestID = ItemDB.startQuest(itemID)
    if startQuestID and startQuestID ~= 0 then
        result.uses[#result.uses + 1] = {
            kind = "starts_quest",
            name = QuestDB.name(startQuestID) or fallbackName(L("quest"), startQuestID),
            detail = L("starts_quest_detail"),
            provenance = provenance,
            questID = startQuestID,
        }
    end

    local taughtSpellID = ItemDB.teachesSpell(itemID)
    if taughtSpellID and taughtSpellID ~= 0 then
        result.uses[#result.uses + 1] = {
            kind = "teaches_spell",
            name = spellName(taughtSpellID),
            detail = L("teaches_detail"),
            provenance = provenance,
        }
    end

    self.questieCache[itemID] = result
    self.questieCacheSize = self.questieCacheSize + 1
    return result
end

function Provider:ReadRecipes(itemID)
    local recipes = recipeUseRows(itemID)
    if #recipes == 0 then
        return nil
    end

    local result = {}
    local provenance = string.format(
        "%s %s",
        ns.RecipeData.manifest.source,
        ns.RecipeData.manifest.version
    )
    for _, recipe in ipairs(recipes) do
        local recipeID, professionID, outputItemID, quantity = unpack(recipe)
        local outputName = itemName(outputItemID)
        local relation = recipeRelation(recipeID, professionID, outputItemID)
        relation.kind = "profession"
        relation.detail = outputName and L("creates_requires", outputName, quantity)
            or L("requires", quantity)
        relation.quantity = quantity
        relation.learningSources = recipeLearningSources(recipeID)
        relation.provenance = relation.observedRecipe
            and L("live_recipe_provenance", relation.observedBuild or L("unknown_version"))
            or provenance
        result[#result + 1] = relation
    end
    return result
end

local function maskContains(classMask, classBit)
    return math.floor((classMask or 0) / classBit) % 2 == 1
end

function Provider:ReadClassAbilityUses(itemID)
    local rows = ns.ClassAbilityData and ns.ClassAbilityData.uses
        and ns.ClassAbilityData.uses[itemID]
    if not rows or #rows == 0 then return nil end

    local result = {}
    local manifest = ns.ClassAbilityData.manifest or {}
    local provenance = string.format(
        "%s %s",
        manifest.source or "WoW client DB2",
        manifest.version or L("unknown_version")
    )
    for _, row in ipairs(rows) do
        local spellID, classMask, skillLineID, quantity = unpack(row)
        local added = false
        for _, classBit in ipairs(ns.ClassMaskOrder or {}) do
            if maskContains(classMask, classBit) then
                local name = spellName(spellID)
                result[#result + 1] = {
                    kind = "class_ability",
                    name = name,
                    displayName = L("class_ability_row", name, quantity),
                    detail = L("class_ability_consumes", quantity),
                    spellID = spellID,
                    classMask = classBit,
                    className = ns.GetClassName(classBit),
                    skillLineID = skillLineID,
                    quantity = quantity,
                    provenance = provenance,
                }
                added = true
            end
        end
        if not added then
            local name = spellName(spellID)
            result[#result + 1] = {
                kind = "class_ability",
                name = name,
                displayName = L("class_ability_row", name, quantity),
                detail = L("class_ability_consumes", quantity),
                spellID = spellID,
                classMask = classMask,
                className = L("unknown_class"),
                skillLineID = skillLineID,
                quantity = quantity,
                provenance = provenance,
            }
        end
    end
    return result
end

function Provider:ReadCraftSources(itemID)
    local recipes = recipeOutputRows(itemID)
    if #recipes == 0 then
        return nil
    end
    local result = {}
    for _, recipe in ipairs(recipes) do
        local recipeID, professionID = unpack(recipe)
        local relation = recipeRelation(recipeID, professionID, itemID)
        relation.kind = "craft"
        relation.learningSources = recipeLearningSources(recipeID)
        relation.provenance = relation.observedRecipe
            and L("live_recipe_provenance", relation.observedBuild or L("unknown_version"))
            or ("WoW client DB2 " .. ns.RecipeData.manifest.version)
        result[#result + 1] = relation
    end
    return result
end

function Provider:GetCraftRecipesForOutput(itemID)
    local result = {}
    for _, recipe in ipairs(recipeOutputRows(itemID)) do
        local recipeID, professionID = unpack(recipe)
        result[#result + 1] = recipeRelation(recipeID, professionID, itemID)
    end
    return result
end

function Provider:GetCraftUses(itemID)
    local result = {}
    for _, recipe in ipairs(recipeUseRows(itemID)) do
        local recipeID, professionID, outputItemID, quantity = unpack(recipe)
        local relation = recipeRelation(recipeID, professionID, outputItemID)
        relation.outputName = itemName(outputItemID)
        relation.quantity = quantity
        result[#result + 1] = relation
    end
    return result
end

function Provider:HasCraftRelations(itemID)
    return #(self:GetCraftRecipesForOutput(itemID)) > 0
        or #(self:GetCraftUses(itemID)) > 0
end

function Provider:ReadFishingSources(itemID)
    local sources = ns.SourceData and ns.SourceData.fishing
        and ns.SourceData.fishing[itemID]
    local pools = ns.SourceData and ns.SourceData.fishingPools
        and ns.SourceData.fishingPools[itemID]
    if not sources and not pools then
        return nil
    end
    local result = {}
    for _, source in ipairs(sources or {}) do
        local areaID, chance, minimum, maximum = unpack(source)
        result[#result + 1] = {
            kind = "fishing",
            name = L("open_water"),
            zone = areaName(areaID) or L("zone_number", areaID),
            areaID = areaID,
            chance = chance and chance > 0 and formattedChance(chance) or nil,
            chanceValue = chance,
            minQuantity = minimum,
            maxQuantity = maximum,
            provenance = "CMaNGOS Classic Era",
            historical = true,
        }
    end
    for _, source in ipairs(pools or {}) do
        local objectID, chance, minimum, maximum = unpack(source)
        local locations = entityLocations(ObjectDB, objectID)
        result[#result + 1] = {
            kind = "fishing",
            name = (ObjectDB and ObjectDB.name and ObjectDB.name(objectID))
                or (ns.SourceData.fishingPoolNames
                    and ns.SourceData.fishingPoolNames[objectID])
                or fallbackName(L("fishing_object"), objectID),
            zone = locations[1] and locations[1].zone or nil,
            entityID = objectID,
            locations = locations,
            waterType = L("fishing_pool"),
            chance = chance and chance > 0 and formattedChance(chance) or nil,
            chanceValue = chance,
            minQuantity = minimum,
            maxQuantity = maximum,
            provenance = "CMaNGOS Classic Era",
            historical = true,
        }
    end
    return result
end

function Provider:ReadGatheringSources(itemID)
    local sources = gatheringSourceRows(itemID)
    if not sources then return nil end
    local result = {}
    for _, source in ipairs(sources) do
        local professionID, entityIDs = unpack(source)
        local sourceCount = type(entityIDs) == "table" and #entityIDs or entityIDs
        local professionName = ns.GetProfessionName(professionID)
        local locations, seenLocations = {}, {}
        -- Herbs and ore have fixed world nodes, so their combined spawn list
        -- is meaningful. Skinning lists creature types instead of fixed
        -- gathering points and remains summarized by source count.
        if professionID ~= 393 and type(entityIDs) == "table" then
            for _, entityID in ipairs(entityIDs) do
                for _, location in ipairs(entityLocations(ObjectDB, entityID)) do
                    local key = Util.Key(location.areaID, location.x, location.y)
                    if not seenLocations[key] then
                        locations[#locations + 1] = location
                        seenLocations[key] = true
                    end
                end
            end
            table.sort(locations, function(left, right)
                if left.areaID == right.areaID then
                    if left.x == right.x then
                        return (left.y or 0) < (right.y or 0)
                    end
                    return (left.x or 0) < (right.x or 0)
                end
                return left.areaID < right.areaID
            end)
        end
        result[#result + 1] = {
            kind = "gathering",
            name = professionName,
            detail = sourceCount and sourceCount > 0
                and L("known_source_types", sourceCount) or nil,
            professionID = professionID,
            professionName = professionName,
            professionIcon = ns.RecipeData.professionIcons[professionID],
            sourceCount = sourceCount,
            sourceEntityIDs = type(entityIDs) == "table" and entityIDs or nil,
            zone = locations[1] and locations[1].zone or nil,
            locations = locations,
            provenance = "CMaNGOS Classic Era",
            historical = true,
        }
    end
    return result
end

local function sourceRows(indexName, itemID)
    return ns.SourceData and ns.SourceData[indexName]
        and ns.SourceData[indexName][itemID]
end

function Provider:ReadObjectSources(itemID)
    local sources = sourceRows("objects", itemID)
    if not sources then return nil end
    local result = {}
    for _, source in ipairs(sources) do
        local objectID, chance, minimum, maximum = unpack(source)
        local locations = entityLocations(ObjectDB, objectID)
        result[#result + 1] = {
            kind = "object",
            name = (ObjectDB and ObjectDB.name and ObjectDB.name(objectID))
                or (ns.SourceData.objectNames and ns.SourceData.objectNames[objectID])
                or fallbackName(L("object"), objectID),
            detail = L("looted_object"),
            zone = locations[1] and locations[1].zone or nil,
            chance = chance and chance > 0 and formattedChance(chance) or nil,
            chanceValue = chance,
            minQuantity = minimum,
            maxQuantity = maximum,
            entityID = objectID,
            locations = locations,
            provenance = "CMaNGOS Classic Era",
            historical = true,
        }
    end
    return result
end

function Provider:ReadContainerSources(itemID)
    local sources = sourceRows("containers", itemID)
    if not sources then return nil end
    local result = {}
    for _, source in ipairs(sources) do
        local containerID, chance, minimum, maximum = unpack(source)
        result[#result + 1] = {
            kind = "container",
            name = itemName(containerID) or fallbackName(L("item"), containerID),
            detail = L("may_contain"),
            chance = chance and chance > 0 and formattedChance(chance) or nil,
            chanceValue = chance,
            minQuantity = minimum,
            maxQuantity = maximum,
            entityID = containerID,
            containerItemID = containerID,
            provenance = "CMaNGOS Classic Era",
            historical = true,
        }
    end
    return result
end

local QUALITY_KEYS = {
    [0] = "quality_poor",
    [1] = "quality_common",
    [2] = "quality_uncommon",
    [3] = "quality_rare",
    [4] = "quality_epic",
    [5] = "quality_legendary",
}

function Provider:ReadDisenchantSources(itemID)
    local sources = sourceRows("disenchant", itemID)
    if not sources then return nil end
    local result = {}
    for _, source in ipairs(sources) do
        local quality, minimumLevel, maximumLevel, sourceCount,
            minimumChance, maximumChance, minimumQuantity, maximumQuantity = unpack(source)
        local qualityName = L(QUALITY_KEYS[quality] or "quality_unknown")
        local name
        if minimumLevel == maximumLevel then
            name = L("disenchant_items_level", qualityName, minimumLevel)
        else
            name = L("disenchant_items_range", qualityName, minimumLevel, maximumLevel)
        end
        result[#result + 1] = {
            kind = "disenchant",
            name = name,
            detail = L("source_items_count", sourceCount),
            chance = formattedChanceRange(minimumChance, maximumChance),
            chanceValue = maximumChance,
            minQuantity = minimumQuantity,
            maxQuantity = maximumQuantity,
            sourceCount = sourceCount,
            itemQuality = quality,
            minimumItemLevel = minimumLevel,
            maximumItemLevel = maximumLevel,
            provenance = "CMaNGOS Classic Era",
            historical = true,
        }
    end
    return result
end

function Provider:ReadPickpocketSources(itemID)
    local sources = sourceRows("pickpocket", itemID)
    if not sources then return nil end
    local result = {}
    for _, source in ipairs(sources) do
        local npcID, chance, minimum, maximum = unpack(source)
        local locations = entityLocations(NpcDB, npcID)
        result[#result + 1] = {
            kind = "pickpocket",
            name = npcName(npcID)
                or fallbackName("NPC", npcID),
            detail = npcDetail(npcID),
            zone = npcZone(npcID),
            chance = chance and chance > 0 and formattedChance(chance) or nil,
            chanceValue = chance,
            minQuantity = minimum,
            maxQuantity = maximum,
            npcID = npcID,
            locations = locations,
            provenance = "CMaNGOS Classic Era",
            historical = true,
        }
    end
    return result
end

function Provider:ReadSpellLootSources(itemID)
    local sources = sourceRows("spellLoot", itemID)
    if not sources then return nil end
    local result = {}
    for _, source in ipairs(sources) do
        local spellID, chance, minimum, maximum = unpack(source)
        result[#result + 1] = {
            kind = "spell_loot",
            name = spellName(spellID),
            detail = L("spell_loot_detail"),
            chance = chance and chance > 0 and formattedChance(chance) or nil,
            chanceValue = chance,
            minQuantity = minimum,
            maxQuantity = maximum,
            spellID = spellID,
            provenance = "CMaNGOS Classic Era",
            historical = true,
        }
    end
    return result
end

function Provider:ReadMailSources(itemID)
    local sources = sourceRows("mail", itemID)
    if not sources then return nil end
    local minimumQuantity, maximumQuantity
    for _, source in ipairs(sources) do
        local _, _, minimum, maximum = unpack(source)
        minimumQuantity = minimumQuantity and math.min(minimumQuantity, minimum) or minimum
        maximumQuantity = maximumQuantity and math.max(maximumQuantity, maximum) or maximum
    end
    return {
        {
            kind = "mail",
            name = L("mail_source"),
            detail = L("mail_templates_count", #sources),
            minQuantity = minimumQuantity,
            maxQuantity = maximumQuantity,
            provenance = "CMaNGOS Classic Era",
            historical = true,
        },
    }
end

function Provider:Get(itemID)
    local questie = self:ReadQuestie(itemID)
    local observed = ns.Storage:GetObservation(itemID, false)
    local result = {
        sources = Util.CopyArray(questie.sources),
        uses = Util.CopyArray(questie.uses),
    }
    local hasRelations = questie ~= EMPTY_ITEM or observed ~= nil

    if observed then
        mergeObservedSources(result.sources, observed.sources)
        removeGatheringObjects(result.sources, itemID)
        Util.AppendUnique(result.uses, observed.uses)
    end

    for _, reader in ipairs(self.RELATION_READERS) do
        local additions = self[reader.method](self, itemID)
        if additions and #additions > 0 then
            hasRelations = true
            if reader.collection == "sources" then
                mergeGeneratedSources(result.sources, additions)
            else
                Util.AppendUnique(result[reader.collection], additions)
            end
        end
    end

    if not hasRelations then return EMPTY_ITEM end

    removeGatheringObjects(result.sources, itemID)
    result.sources = sortDrops(result.sources)

    return result
end

function Provider:GetManifest()
    return {
        schema = ns.Config.dataSchema,
        dataset = self.questieAvailable and L("client_dataset",
            self.questieVersion or "unknown", ns.RecipeData.manifest.version)
            or L("snapshot_dataset", ns.QuestieSnapshot.manifest.version,
                ns.RecipeData.manifest.version),
        game = "WoW Forever",
        interface = ns.Config.interface,
        contract = self.contractVersion,
        questieAvailable = self.questieAvailable,
    }
end

function Provider:GetStatus()
    return {
        version = self.questieVersion,
        contractVersion = self.contractVersion,
        cachedItems = self.questieCacheSize,
        recipeVersion = ns.RecipeData and ns.RecipeData.manifest.version,
        dropTableAvailable = ns.SourceData and ns.SourceData.drops ~= nil,
        sourceVersion = ns.SourceData and ns.SourceData.manifest.version,
        questieAvailable = self.questieAvailable,
        snapshotVersion = ns.QuestieSnapshot and ns.QuestieSnapshot.manifest.version,
        observedRecipes = ns.Storage:CountObservedRecipes(),
    }
end

