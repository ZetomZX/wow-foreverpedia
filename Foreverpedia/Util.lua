local _, ns = ...

local Util = {}
ns.Util = Util

local KEY_SEPARATOR = "\031"

function Util.CopyArray(source)
    local result = {}
    for index, value in ipairs(source or {}) do
        result[index] = value
    end
    return result
end

function Util.Key(...)
    local values = {}
    for index = 1, select("#", ...) do
        values[index] = tostring(select(index, ...) or "")
    end
    return table.concat(values, KEY_SEPARATOR)
end

function Util.RelationKey(relation)
    return Util.Key(
        relation.kind,
        relation.npcID,
        relation.entityID,
        relation.questID,
        relation.recipeID,
        relation.outputItemID,
        relation.name,
        relation.detail,
        relation.zone
    )
end

function Util.AppendUnique(target, additions, keyBuilder)
    keyBuilder = keyBuilder or Util.RelationKey
    local seen = {}
    for _, value in ipairs(target) do
        seen[keyBuilder(value)] = true
    end
    for _, value in ipairs(additions or {}) do
        local key = keyBuilder(value)
        if not seen[key] then
            target[#target + 1] = value
            seen[key] = true
        end
    end
end

function Util.VersionAtLeast(actual, required)
    local function parse(version)
        local major, minor, patch = tostring(version or ""):match("^(%d+)%.(%d+)%.(%d+)")
        return tonumber(major), tonumber(minor), tonumber(patch)
    end

    local actualMajor, actualMinor, actualPatch = parse(actual)
    local requiredMajor, requiredMinor, requiredPatch = parse(required)
    if not actualMajor or not requiredMajor then return false end
    if actualMajor ~= requiredMajor then return actualMajor > requiredMajor end
    if actualMinor ~= requiredMinor then return actualMinor > requiredMinor end
    return actualPatch >= requiredPatch
end

function Util.Trim(value)
    return tostring(value or ""):match("^%s*(.-)%s*$") or ""
end

function Util.SetButtonEnabled(button, enabled)
    if enabled then button:Enable() else button:Disable() end
end
