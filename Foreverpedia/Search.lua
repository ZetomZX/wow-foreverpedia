local _, ns = ...

local Search = {}
ns.Search = Search

local CYRILLIC_LOWER = {
    ["А"]="а", ["Б"]="б", ["В"]="в", ["Г"]="г", ["Д"]="д", ["Е"]="е",
    ["Ё"]="е", ["Ж"]="ж", ["З"]="з", ["И"]="и", ["Й"]="й", ["К"]="к",
    ["Л"]="л", ["М"]="м", ["Н"]="н", ["О"]="о", ["П"]="п", ["Р"]="р",
    ["С"]="с", ["Т"]="т", ["У"]="у", ["Ф"]="ф", ["Х"]="х", ["Ц"]="ц",
    ["Ч"]="ч", ["Ш"]="ш", ["Щ"]="щ", ["Ъ"]="ъ", ["Ы"]="ы", ["Ь"]="ь",
    ["Э"]="э", ["Ю"]="ю", ["Я"]="я", ["ё"]="е",
}

function Search:Normalize(value)
    local result = string.lower(tostring(value or ""))
    for upper, lower in pairs(CYRILLIC_LOWER) do
        result = result:gsub(upper, lower)
    end
    return ns.Util.Trim(result:gsub("%s+", " "))
end

local function resultBefore(left, right)
    if left.score ~= right.score then return left.score < right.score end
    if left.length ~= right.length then return left.length < right.length end
    if left.normalized ~= right.normalized then return left.normalized < right.normalized end
    return left.itemID < right.itemID
end

function Search:Find(query, limit)
    local normalizedQuery = self:Normalize(query)
    if normalizedQuery == "" then return {} end

    limit = limit or ns.Config.searchResultLimit
    local results = {}
    local numericID = tonumber(normalizedQuery)
    for itemID, item in pairs(ns.GetItemSearchItems() or {}) do
        local name, normalized = item[1], item[2]
        normalized = normalized or self:Normalize(name)
        local position = normalized and normalized:find(normalizedQuery, 1, true)
        local score
        if numericID and itemID == numericID then
            score = -1
        elseif normalized == normalizedQuery then
            score = 0
        elseif position == 1 then
            score = 1
        elseif normalized and normalized:find(" " .. normalizedQuery, 1, true) then
            score = 2
        elseif position then
            score = 3
        end

        if score then
            local candidate = {
                itemID = itemID,
                name = name,
                normalized = normalized,
                score = score,
                length = #normalized,
            }
            local inserted = false
            for index, current in ipairs(results) do
                if resultBefore(candidate, current) then
                    table.insert(results, index, candidate)
                    inserted = true
                    break
                end
            end
            if not inserted then results[#results + 1] = candidate end
            if #results > limit then table.remove(results) end
        end
    end
    return results
end
